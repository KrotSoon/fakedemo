// FakeMimic features on top of record / replay:
//   takes      - one action starts every assigned bot and tv_record (<folder>_take<N>), one stops both
//   timing     - shift a recording earlier / later without re-recording
//   path       - draw a recording's route with beams (removed before a take: beams are entities and
//                would end up in the demo)
//   over       - record yourself while the assigned bots are already replaying
//   transform  - put a recording's path at your position and view direction
//   deaths     - a bot dies when its path ends
// Edits live next to the recording in <name>.fme (key=value lines), the .fmr stays untouched.
using System.Drawing;
using BotControllerApi;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Cvars;
using CounterStrikeSharp.API.Modules.Utils;
using Vector = CounterStrikeSharp.API.Modules.Utils.Vector;

namespace FakeMimic;

// per-recording edits, applied when the recording is loaded for a bot
public class RecordingEdits
{
    public int OffsetTicks;          // >0 starts later, <0 skips the first ticks
    public float Dx, Dy, Dz, Yaw;    // path moved by (Dx,Dy,Dz) after turning it by Yaw around its start
    public bool DieAtEnd;
    public string Model = "";        // character model of the bot, "" = team default (FakeMimic.Models.cs)

    public static RecordingEdits Load(string path)
    {
        var e = new RecordingEdits();
        if (!File.Exists(path)) return e;
        foreach (var line in File.ReadAllLines(path))
        {
            var kv = line.Split('=', 2);
            if (kv.Length != 2) continue;
            var v = kv[1].Trim();
            float F() => float.Parse(v, System.Globalization.CultureInfo.InvariantCulture);
            switch (kv[0].Trim())
            {
                case "offset": e.OffsetTicks = int.Parse(v); break;
                case "dx": e.Dx = F(); break;
                case "dy": e.Dy = F(); break;
                case "dz": e.Dz = F(); break;
                case "yaw": e.Yaw = F(); break;
                case "die_at_end": e.DieAtEnd = v == "1"; break;
                case "model": e.Model = v; break;
            }
        }
        return e;
    }

    public void Save(string path)
    {
        var ci = System.Globalization.CultureInfo.InvariantCulture;
        File.WriteAllLines(path, new[]
        {
            $"offset={OffsetTicks}",
            $"dx={Dx.ToString(ci)}", $"dy={Dy.ToString(ci)}", $"dz={Dz.ToString(ci)}", $"yaw={Yaw.ToString(ci)}",
            $"die_at_end={(DieAtEnd ? 1 : 0)}",
            $"model={Model}",
        });
    }

    public bool Moved => Dx != 0 || Dy != 0 || Dz != 0 || Yaw != 0;
}

public partial class FakeMimic
{
    const int TicksPerSecond = 64;

    string EditsPathOf(string name) => Path.Combine(MapDir, name + ".fme");
    RecordingEdits EditsOf(string name) => RecordingEdits.Load(EditsPathOf(name));

    // ---------------- applying edits ----------------

    // recording as the bot will play it: path transform and negative offset applied to a copy
    static Recording Prepare(Recording src, RecordingEdits e)
    {
        var ticks = (ReplayTick[])src.Ticks.Clone();
        var commands = (ReplayCommandFrame[])src.Commands.Clone();
        var subs = src.Subs;

        if (e.Moved && ticks.Length > 0)
        {
            var ox = ticks[0].Pre.OriginX;
            var oy = ticks[0].Pre.OriginY;
            var (sin, cos) = MathF.SinCos(e.Yaw * MathF.PI / 180f);
            void Move(ref MovementSnapshot s)
            {
                float x = s.OriginX - ox, y = s.OriginY - oy;
                s.OriginX = ox + x * cos - y * sin + e.Dx;
                s.OriginY = oy + x * sin + y * cos + e.Dy;
                s.OriginZ += e.Dz;
                (s.VelX, s.VelY) = (s.VelX * cos - s.VelY * sin, s.VelX * sin + s.VelY * cos);
                s.Yaw += e.Yaw;
            }
            for (var i = 0; i < ticks.Length; i++)
            {
                Move(ref ticks[i].Pre);
                Move(ref ticks[i].Post);
            }
            for (var i = 0; i < commands.Length; i++) commands[i].Yaw += e.Yaw;
        }

        if (e.OffsetTicks < 0)
        {
            // skip the first ticks together with their subtick moves and command frames
            var skip = Math.Min(-e.OffsetTicks, Math.Max(0, ticks.Length - 1));
            var skipSubs = 0;
            for (var i = 0; i < skip; i++) skipSubs += (int)ticks[i].NumSubtick;
            ticks = ticks[skip..];
            if (commands.Length >= skip) commands = commands[skip..];
            subs = subs[Math.Min(skipSubs, subs.Length)..];
        }

        return new Recording { Team = src.Team, Weapons = src.Weapons, Ticks = ticks, Subs = subs, Commands = commands };
    }

    // ---------------- takes ----------------

    string? _take;   // demo name of the running take

    string NextTakeName()
    {
        var game = Path.GetFullPath(Path.Combine(Server.GameDirectory, "csgo"));
        var i = 1;
        while (File.Exists(Path.Combine(game, $"{_category}_take{i}.dem"))) i++;
        return $"{_category}_take{i}";
    }

    string StartTake()
    {
        if (_take != null) return $"take '{_take}' is already running";
        if (_bc == null) return "CS2-Bot-Controller is not installed";
        ClearPaths();
        _take = NextTakeName();
        var name = _take;
        // the bots respawn in this tick and start in the next one: the demo starts with them
        Go();
        Server.NextFrame(() =>
        {
            Server.ExecuteCommand($"tv_record {name}");
            FireTakeStarted(name);
        });
        return $"take '{name}': bots and demo started. H > Stop take (or DEL) to finish";
    }

    string StopTake()
    {
        Server.ExecuteCommand("tv_stoprecord");
        Halt();
        var msg = _take != null ? $"take '{_take}' saved: {_take}.dem" : "demo stopped";
        FireTakeStopped();
        _take = null;
        return msg;
    }

    [ConsoleCommand("fm_take", "fm_take - start a take (all bots + demo), again to stop it")]
    public void CmdTake(CCSPlayerController? caller, CommandInfo cmd) =>
        cmd.ReplyToCommand("[FM] " + (_take == null ? StartTake() : StopTake()));

    [ConsoleCommand("fm_takestop", "fm_takestop - stop the demo and the bots")]
    public void CmdTakeStop(CCSPlayerController? caller, CommandInfo cmd) => cmd.ReplyToCommand("[FM] " + StopTake());

    // ---------------- recording over a running replay ----------------

    string RecordOver(string name)
    {
        if (_bc == null) return "CS2-Bot-Controller is not installed";
        if (_replays.Count == 0) return "no bots assigned: Movements > a movement > Play on T/CT bot";
        // the recording starts in the same tick as the replays
        return Go(() =>
        {
            var p = LocalHuman();
            var msg = StartRec(name);
            if (p != null) Say(p, msg + " H > 1 to stop");
        });
    }

    // ---------------- timing ----------------

    string Shift(string name, float seconds)
    {
        var e = EditsOf(name);
        e.OffsetTicks += (int)MathF.Round(seconds * TicksPerSecond);
        e.Save(EditsPathOf(name));
        Reload(name);
        return $"'{name}' starts {DescribeOffset(e.OffsetTicks)}";
    }

    string ResetTiming(string name)
    {
        var e = EditsOf(name);
        e.OffsetTicks = 0;
        e.Save(EditsPathOf(name));
        Reload(name);
        return $"'{name}' timing reset";
    }

    static string DescribeOffset(int ticks) =>
        ticks == 0 ? "on time" : $"{Math.Abs(ticks) / (float)TicksPerSecond:0.0} s {(ticks > 0 ? "later" : "earlier")}";

    // assigned bots keep playing what was loaded; reload the edited version for them
    void Reload(string name)
    {
        foreach (var r in _replays.Where(r => r.Name == name))
        {
            r.Rec = Recording.Load(PathOf(name));
            r.Edits = EditsOf(name);
        }
    }

    // ---------------- transform ----------------

    string PutPathHere(string name)
    {
        var p = LocalHuman();
        var pawn = p?.PlayerPawn.Value;
        if (p == null || pawn?.AbsOrigin == null) return "you must be alive";
        var rec = Recording.Load(PathOf(name));
        if (rec.Ticks.Length == 0) return "empty recording";
        var start = rec.Ticks[0].Pre;
        var e = EditsOf(name);
        e.Yaw = pawn.EyeAngles.Y - start.Yaw;
        e.Dx = pawn.AbsOrigin.X - start.OriginX;
        e.Dy = pawn.AbsOrigin.Y - start.OriginY;
        e.Dz = pawn.AbsOrigin.Z - start.OriginZ;
        e.Save(EditsPathOf(name));
        Reload(name);
        return $"'{name}' now starts where you stand, facing your view";
    }

    string ResetPath(string name)
    {
        var e = EditsOf(name);
        (e.Dx, e.Dy, e.Dz, e.Yaw) = (0, 0, 0, 0);
        e.Save(EditsPathOf(name));
        Reload(name);
        return $"'{name}' path is back where it was recorded";
    }

    // ---------------- deaths ----------------

    string ToggleDieAtEnd(string name)
    {
        var e = EditsOf(name);
        e.DieAtEnd = !e.DieAtEnd;
        e.Save(EditsPathOf(name));
        Reload(name);
        return $"'{name}': {(e.DieAtEnd ? "dies when the path ends" : "stays standing at the end")}";
    }

    // called by OnTick when a replay reaches its end
    void OnReplayEnd(Replay r)
    {
        if (r.Edits.DieAtEnd && r.Bot?.PlayerPawn.Value is { IsValid: true } pawn)
            pawn.CommitSuicide(false, true);
        else if (r.Bot != null)
            _bc?.Lock(r.Bot.Slot, LockKind.All);
    }

    // A bot that plays a recording stays dead when killed: only Go() brings it back.
    // fd_fake.cfg turns the game's auto-respawn on, but it cannot leave out single players, and
    // switching it off inside the death event is too late. So while FakeMimic runs it takes the
    // respawn over: the cvars go off and everybody else is respawned here after RespawnDelay.
    const float RespawnDelay = 2f;
    bool _ownRespawn;   // the cfg wanted auto-respawn and FakeMimic does it instead

    void TakeOverRespawn()
    {
        foreach (var name in new[] { "mp_respawn_on_death_t", "mp_respawn_on_death_ct" })
        {
            var cvar = ConVar.Find(name);
            if (cvar == null || !cvar.GetPrimitiveValue<bool>()) continue;
            _ownRespawn = true;
            cvar.SetValue(false);
        }
    }

    [GameEventHandler]
    public HookResult OnAnyDeath(EventPlayerDeath ev, GameEventInfo info)
    {
        var victim = ev.Userid;
        if (victim is not { IsValid: true }) return HookResult.Continue;
        var r = _replays.FirstOrDefault(x => x.Bot == victim);
        if (r != null)
        {
            _bc?.StopReplay(victim.Slot);
            r.Running = false;
            return HookResult.Continue;   // stays dead until the next start
        }
        if (_ownRespawn && !victim.IsHLTV)
            AddTimer(RespawnDelay, () => { if (victim is { IsValid: true, PawnIsAlive: false } && victim.TeamNum >= 2) victim.Respawn(); });
        return HookResult.Continue;
    }
    // ---------------- path preview ----------------

    readonly List<CBeam> _beams = new();
    const int BeamEveryTicks = 8;
    const int MaxBeams = 200;

    string ShowPath(string name)
    {
        ClearPaths();
        var rec = Prepare(Recording.Load(PathOf(name)), EditsOf(name));
        var color = rec.Team == 2 ? Color.FromArgb(255, 238, 140, 60) : Color.FromArgb(255, 90, 150, 255);
        var step = Math.Max(BeamEveryTicks, rec.Ticks.Length / MaxBeams + 1);
        for (var i = step; i < rec.Ticks.Length; i += step)
            DrawBeam(rec.Ticks[i - step].Pre, rec.Ticks[i].Pre, color);
        // the end point stands out: a short vertical post
        if (rec.Ticks.Length > 0)
        {
            var end = rec.Ticks[^1].Pre;
            var top = end;
            top.OriginZ += 72;
            DrawBeam(end, top, Color.FromArgb(255, 228, 174, 57));
        }
        AddTimer(20f, ClearPaths);
        return $"path of '{name}' shown for 20 s ({_beams.Count} segments, start = first segment)";
    }

    void DrawBeam(MovementSnapshot a, MovementSnapshot b, Color color)
    {
        var beam = Utilities.CreateEntityByName<CBeam>("beam");
        if (beam == null) return;
        beam.Render = color;
        beam.Width = 2.5f;
        beam.Teleport(new Vector(a.OriginX, a.OriginY, a.OriginZ + 4), new QAngle(0, 0, 0), new Vector(0, 0, 0));
        beam.EndPos.X = b.OriginX;
        beam.EndPos.Y = b.OriginY;
        beam.EndPos.Z = b.OriginZ + 4;
        beam.DispatchSpawn();
        _beams.Add(beam);
    }

    void ClearPaths()
    {
        foreach (var b in _beams.Where(b => b.IsValid)) b.Remove();
        _beams.Clear();
    }

    [ConsoleCommand("fm_path", "fm_path <name> - show a recording's route for 20 s")]
    public void CmdPath(CCSPlayerController? caller, CommandInfo cmd) => cmd.ReplyToCommand("[FM] " + ShowPath(cmd.ArgByIndex(1)));

    // ---------------- menus for the features ----------------

    void TimingMenu(CCSPlayerController p, string name)
    {
        Show(p, new Menu($"{name}: {DescribeOffset(EditsOf(name).OffsetTicks)}", new List<MenuItem>
        {
            new("Earlier by 0.5 s", pl => { Say(pl, Shift(name, -0.5f)); TimingMenu(pl, name); }),
            new("Earlier by 0.1 s", pl => { Say(pl, Shift(name, -0.1f)); TimingMenu(pl, name); }),
            new("Later by 0.1 s", pl => { Say(pl, Shift(name, 0.1f)); TimingMenu(pl, name); }),
            new("Later by 0.5 s", pl => { Say(pl, Shift(name, 0.5f)); TimingMenu(pl, name); }),
            new("Reset timing", pl => { Say(pl, ResetTiming(name)); TimingMenu(pl, name); }),
            new("← Back", pl => RecordingMenu(pl, name)),
        }));
    }

    void PathMenu(CCSPlayerController p, string name)
    {
        var e = EditsOf(name);
        Show(p, new Menu($"{name}: path and death", new List<MenuItem>
        {
            new("Show path (20 s)", pl => { Say(pl, ShowPath(name)); PathMenu(pl, name); }),
            new("Put path here (my spot and view)", pl => { Say(pl, PutPathHere(name)); PathMenu(pl, name); }),
            new("Path back to where it was recorded", pl => { Say(pl, ResetPath(name)); PathMenu(pl, name); }),
            new($"Die at end: {(e.DieAtEnd ? "yes" : "no")}", pl => { Say(pl, ToggleDieAtEnd(name)); PathMenu(pl, name); }),
            new("← Back", pl => RecordingMenu(pl, name)),
        }));
    }
}
