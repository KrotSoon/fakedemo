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
using FakeMimicApi;
using Vector =CounterStrikeSharp.API.Modules.Utils.Vector;

namespace FakeMimic;

// per-recording edits, applied when the recording is loaded for a bot
public class RecordingEdits
{
    public int OffsetTicks;          // >0 starts later, <0 skips the first ticks
    public float Dx, Dy, Dz, Yaw;    // path moved by (Dx,Dy,Dz) after turning it by Yaw around its start
    public bool DieAtEnd;
    public string Model = "";        // character model of the bot, "" = team default (FakeMimic.Models.cs)
    public string Skins = "";        // weapon paints, knife, gloves of the bot (SkinSet text, FakeMimic.Skins.cs)

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
                case "skins": e.Skins = v; break;
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
            $"skins={Skins}",
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

        var buys = src.Buys;
        if (e.OffsetTicks < 0)
        {
            var skip = Math.Min(-e.OffsetTicks, Math.Max(0, ticks.Length - 1));
            buys = buys.Select(b => (Math.Max(0, b.Tick - skip), b.Item)).ToList();   // skipped ones at the start
            (ticks, subs, commands) = From(ticks, subs, commands, skip);
        }

        // the history is one opaque block for the whole recording with the original angles: it cannot be cut
        // or turned, so a skipped start or a moved path plays with the bot's own spread
        var history = e.OffsetTicks < 0 || e.Moved ? Array.Empty<byte>() : src.History;
        return new Recording { Team = src.Team, Weapons = src.Weapons, Ticks = ticks, Subs = subs, Commands = commands, Buys = buys, History = history };
    }

    // the ticks from `skip` on, together with their subtick moves and command frames
    static (ReplayTick[], SubtickMove[], ReplayCommandFrame[]) From(ReplayTick[] ticks, SubtickMove[] subs, ReplayCommandFrame[] commands, int skip)
    {
        var skipSubs = 0;
        for (var i = 0; i < skip; i++) skipSubs += (int)ticks[i].NumSubtick;
        return (ticks[skip..], subs[Math.Min(skipSubs, subs.Length)..], commands.Length >= skip ? commands[skip..] : commands);
    }

    // ---------------- collisions ----------------
    // The replay puts the bot at the recorded spot every tick, through anybody standing there. With
    // Collisions on, a bot whose next spot is inside a live player (and closer to them than now: walking
    // away is free) stops there, its replay paused, and goes on from the same tick when the way is clear.
    // The rest of a paused recording plays without its input history (it is one block that cannot be cut).
    bool _collide;
    const float HullWidth = 32f, HullHeight = 72f;

    string CollidePrefsPath => Path.Combine(FakeDemoPaths.Root, "collisions.txt");

    void LoadCollidePrefs()
    {
        try { _collide = File.ReadAllText(CollidePrefsPath).Trim() == "on"; }
        catch (Exception) { /* no file: off */ }
    }

    void SetCollide(bool on)
    {
        _collide = on;
        Directory.CreateDirectory(FakeDemoPaths.Root);
        File.WriteAllText(CollidePrefsPath, on ? "on" : "off");
        if (!on) foreach (var r in _replays.Where(r => r.PausedAt >= 0)) Resume(r);
    }

    [ConsoleCommand("fm_collisions", "fm_collisions <0|1> - bots stop in front of players instead of going through")]
    public void CmdCollisions(CCSPlayerController? caller, CommandInfo cmd)
    {
        SetCollide(cmd.ArgByIndex(1) != "0");
        cmd.ReplyToCommand($"[FM] collisions {(_collide ? "on" : "off")}");
    }

    // where the replay is in the prepared recording: a replay loaded after a collision has its own ticks
    // (slowed ones first), Map gives the recorded tick of each
    int Cursor(Replay r)
    {
        var c = _bc!.ReplayCursor(r.Bot!.Slot);
        return r.Map is { Length: > 0 } map ? map[Math.Clamp(c, 0, map.Length - 1)] : c;
    }

    // A stopped bot went on as soon as its next spot was free, took one step, hit the player again: it
    // jittered and filled every gap. It goes on when its path for the next ResumeLookTicks keeps
    // ResumeMargin more room and has been clear for ResumeClearTicks. A bot sees StopLookTicks ahead and
    // brakes to the spot in front of the player instead of stopping dead; it starts again over RampTicks.
    const float ResumeMargin = 16f;
    const int ResumeLookTicks = 20, ResumeClearTicks = 6, StopLookTicks = 8, RampTicks = 13;
    // where a player will be: someone running across is gone when the bot gets there and stops nobody
    const float StaySeconds = 0.15f;

    // the spot of `tick`, reached `ahead` ticks from now, holds a live player then and StaySeconds later
    // (with `margin` more room), and is closer to them than the bot is now (walking away is free)
    bool Blocked(Replay r, int tick, int ahead, float margin = 0)
    {
        var ticks = r.Prepared?.Ticks;
        if (ticks == null || tick < 0 || tick >= ticks.Length) return false;
        var next = ticks[tick].Post;
        var now = r.Bot!.PlayerPawn.Value?.AbsOrigin;
        var dt = Math.Max(0, ahead) / (float)TicksPerSecond;
        foreach (var p in FakeDemoPlayers.All())
        {
            if (p is not { IsValid: true, IsBot: false, IsHLTV: false, PawnIsAlive: true } || p.PlayerPawn.Value is not { AbsOrigin: { } at } pawn) continue;
            var v = pawn.AbsVelocity;
            bool Inside(float t, out float dx, out float dy)
            {
                dx = next.OriginX - (at.X + v.X * t);
                dy = next.OriginY - (at.Y + v.Y * t);
                // centres closer than a hull width: the square hulls also touch corner to corner on a
                // diagonal path 40 units aside, where a player slides by but the bot stopped
                return dx * dx + dy * dy < (HullWidth + margin) * (HullWidth + margin) && Math.Abs(next.OriginZ - at.Z) < HullHeight;
            }
            if (!Inside(dt, out var x, out var y) || !Inside(dt + StaySeconds, out _, out _)) continue;
            if (now == null) return true;
            float px = at.X + v.X * dt, py = at.Y + v.Y * dt;
            if (x * x + y * y <= (now.X - px) * (now.X - px) + (now.Y - py) * (now.Y - py)) return true;
        }
        return false;
    }

    // Two players inside each other are both stuck (the player could not step out of a bot that braked
    // into them). A stopped bot inside a live player steps back along its own path to the nearest spot
    // that is free and goes on from there later, so the movement stays the recorded one
    const int StepBackTicks = 64;

    static bool Touches(float x, float y, float z, Vector o) =>
        Math.Abs(o.X - x) < HullWidth && Math.Abs(o.Y - y) < HullWidth && Math.Abs(o.Z - z) < HullHeight;

    bool TouchesPlayer(float x, float y, float z) => FakeDemoPlayers.All().Any(p =>
        p is { IsValid: true, IsBot: false, IsHLTV: false, PawnIsAlive: true } && p.PlayerPawn.Value?.AbsOrigin is { } o && Touches(x, y, z, o));

    void StepBack(Replay r)
    {
        if (r.Prepared is not { } rec || r.Bot?.PlayerPawn.Value is not { AbsOrigin: { } at } pawn || !TouchesPlayer(at.X, at.Y, at.Z)) return;
        for (var t = r.PausedAt - 1; t >= Math.Max(0, r.PausedAt - StepBackTicks); t--)
        {
            var s = rec.Ticks[t].Post;
            if (TouchesPlayer(s.OriginX, s.OriginY, s.OriginZ)) continue;
            pawn.Teleport(new Vector(s.OriginX, s.OriginY, s.OriginZ), null, new Vector(0, 0, 0));
            r.PausedAt = t + 1;
            r.ClearSince = -1;
            return;
        }
    }

    // a paused bot: true once the way ahead has stayed clear long enough
    bool MayResume(Replay r)
    {
        var clear = true;
        for (var t = r.PausedAt; t < r.PausedAt + ResumeLookTicks && clear; t++) clear = !Blocked(r, t, t - r.PausedAt + RampTicks / 2, ResumeMargin);
        if (!clear) { r.ClearSince = -1; return false; }
        if (r.ClearSince < 0) r.ClearSince = Server.TickCount;
        return Server.TickCount - r.ClearSince >= ResumeClearTicks;
    }

    // a running bot: brakes when its path is blocked within StopLookTicks
    bool CheckCollision(Replay r)
    {
        var c = Cursor(r);
        for (var t = c; t < c + StopLookTicks; t++)
        {
            // where the player will be, and where they are now (braking into a player got both stuck)
            if (!Blocked(r, t, t - c) && !Blocked(r, t, 0)) continue;
            Brake(r, c, t);
            return true;
        }
        return false;
    }

    // Slowed playback between recorded ticks: tick k of n is at recorded position from + Tau(k) (in ticks,
    // the bot stands at Post(from) before it), moving at Rate(k) of the recorded speed. Positions, speed and
    // view are interpolated; the rest comes from the nearest recorded tick, without its subtick moves,
    // weapon switch or event (a throw or drop is not played twice)
    static (ReplayTick[], ReplayCommandFrame[], int[]) Slowed(Recording rec, int from, int n, Func<int, double> tau, Func<int, float> rate)
    {
        var src = rec.Ticks;
        var ticks = new ReplayTick[n];
        var commands = new ReplayCommandFrame[n];
        var map = new int[n];
        MovementSnapshot At(double x, float speed)
        {
            x = Math.Clamp(x, 0, src.Length - 1);
            var i = (int)Math.Floor(x);
            var j = Math.Min(i + 1, src.Length - 1);
            var f = (float)(x - i);
            MovementSnapshot a = src[i].Post, b = src[j].Post, s = f < 0.5f ? a : b;
            float L(float p, float q) => p + (q - p) * f;
            s.OriginX = L(a.OriginX, b.OriginX); s.OriginY = L(a.OriginY, b.OriginY); s.OriginZ = L(a.OriginZ, b.OriginZ);
            s.VelX = L(a.VelX, b.VelX) * speed; s.VelY = L(a.VelY, b.VelY) * speed; s.VelZ = L(a.VelZ, b.VelZ) * speed;
            s.Pitch = L(a.Pitch, b.Pitch);
            s.Yaw = a.Yaw + (((b.Yaw - a.Yaw) % 360 + 540) % 360 - 180) * f;
            s.DuckAmount = L(a.DuckAmount, b.DuckAmount);
            return s;
        }
        for (var k = 0; k < n; k++)
        {
            double x0 = from + tau(k), x1 = from + tau(k + 1);
            var near = Math.Clamp((int)Math.Round(x1), 0, src.Length - 1);
            ticks[k] = src[near];
            ticks[k].Pre = At(x0, rate(k));
            ticks[k].Post = At(x1, rate(k + 1));
            ticks[k].NumSubtick = 0;
            ticks[k].EventFlags = 0;
            if (near < rec.Commands.Length)
            {
                commands[k] = rec.Commands[near];
                commands[k].WeaponSelect = 0;
                commands[k].Pitch = ticks[k].Post.Pitch;
                commands[k].Yaw = ticks[k].Post.Yaw;
            }
            map[k] = near;
        }
        return (ticks, commands, map);
    }

    // load ticks (slowed ones, then recorded ones from `rest` on) into the bot's replay
    bool Load(Replay r, ReplayTick[] slowTicks, ReplayCommandFrame[] slowCommands, int[] slowMap, int rest)
    {
        var rec = r.Prepared!;
        var (ticks, subs, commands) = rest < rec.Ticks.Length ? From(rec.Ticks, rec.Subs, rec.Commands, rest) : ([], [], []);
        var map = slowMap.Concat(Enumerable.Range(rest, ticks.Length)).ToArray();
        if (map.Length == 0 || r.Bot?.PlayerPawn.Value is not { } pawn || _bc == null) return false;
        _bc.StopReplay(r.Bot.Slot);
        if (!_bc.SetReplayPawn(r.Bot.Slot, pawn.Handle) ||
            !_bc.LoadReplay(r.Bot.Slot, [.. slowTicks, .. ticks], subs, [.. slowCommands, .. commands]))
        {
            Server.PrintToConsole($"[FM] replay '{r.Name}' did not load after a collision");
            return false;
        }
        r.Map = map;
        _bc.Unlock(r.Bot.Slot, LockKind.All);
        r.Running = _bc.StartReplay(r.Bot.Slot);
        return r.Running;
    }

    // braking: a player walking towards the bot is in its next spot already, it stops where it is
    bool StopBraking(Replay r)
    {
        var c = _bc!.ReplayCursor(r.Bot!.Slot);
        if (_bc.TryGetReplayTick(r.Bot.Slot, out var next) == false || !TouchesPlayer(next.Post.OriginX, next.Post.OriginY, next.Post.OriginZ)) return false;
        Pause(r, r.Map is { Length: > 0 } map ? map[Math.Clamp(c, 0, map.Length - 1)] : c);
        return true;
    }

    // the bot stands at Post(c - 1); it slows down to a stop at Post(blocked - 1), the spot before the player
    void Brake(Replay r, int c, int blocked)
    {
        var dist = blocked - c;   // recorded ticks still to cover
        if (dist <= 0) { Pause(r, c); return; }
        var n = 2 * dist;         // from full speed to 0 in twice the time
        var (ticks, commands, map) = Slowed(r.Prepared!, c - 1, n, k => k - k * (double)k / (2 * n), k => 1f - (float)k / n);
        r.BrakeTo = blocked;
        if (!Load(r, ticks, commands, map, r.Prepared!.Ticks.Length)) Pause(r, c);
    }

    void Pause(Replay r, int at)
    {
        r.PausedAt = at;
        r.BrakeTo = -1;
        r.ClearSince = -1;
        _bc!.StopReplay(r.Bot!.Slot);
        _bc.Lock(r.Bot.Slot, LockKind.All);
    }

    // from a standstill at Post(PausedAt - 1) up to the recorded speed over RampTicks
    void Resume(Replay r)
    {
        var at = r.PausedAt;
        r.PausedAt = -1;
        if (r.Prepared == null) return;
        double Tau(int k) => k * (double)k / (2 * RampTicks);
        var (ticks, commands, map) = Slowed(r.Prepared, at - 1, RampTicks, Tau, k => (float)k / RampTicks);
        Load(r, ticks, commands, map, at - 1 + (int)Math.Round(Tau(RampTicks)) + 1);
    }

    // ---------------- the map as it was before the bots ----------------
    // Every start (once, each pass of a loop, a demo, a preview) clears what the last run left behind:
    // dropped weapons, grenades in flight, fires, smokes, the bomb, bodies, broken glass, and the bullet holes
    // and blood. Decals live in the game, not on the server, and the game drops all of them on round_start:
    // that event alone is sent to the players (cl_removedecals only clears the one surface under the crosshair).
    static readonly string[] Leftovers = { "inferno", "planted_c4", "smokegrenade_projectile", "hegrenade_projectile",
        "flashbang_projectile", "molotov_projectile", "incgrenade_projectile", "decoy_projectile" };

    void ClearMap()
    {
        var removed = 0;
        foreach (var e in Utilities.GetAllEntities())
        {
            if (e is not { IsValid: true }) continue;
            var name = e.DesignerName;
            var dropped = name.StartsWith("weapon_") && e.As<CBasePlayerWeapon>().OwnerEntity.Value is not { IsValid: true };
            if (!dropped && Array.IndexOf(Leftovers, name) < 0) continue;
            e.Remove();
            removed++;
        }
        Server.ExecuteCommand("ragdoll_cleanup_all; shatterglass_cleanup");
        foreach (var p in FakeDemoPlayers.All().Where(p => p is { IsValid: true, IsBot: false, IsHLTV: false }))
            new EventRoundStart(true).FireEventToClient(p);   // the game clears its decals
        if (removed > 0) Server.PrintToConsole($"[FM] map cleared: {removed} leftovers");
        // the round start also drops beams and outlines in the game: add-ons draw theirs again, a moment
        // later (what is made in the same tick reaches the player before the event and is dropped too)
        AddTimer(0.1f, () => _api?.RaiseMapCleared());
    }

    [ConsoleCommand("fm_clearmap", "fm_clearmap - remove dropped weapons, grenades, bodies and decals (done on every start)")]
    public void CmdClearMap(CCSPlayerController? caller, CommandInfo cmd) => ClearMap();

    // ---------------- takes ----------------

    string? _take;   // demo name of the running take

    string NextTakeName()
    {
        var game = Path.GetFullPath(Path.Combine(Server.GameDirectory, "csgo"));
        var i = 1;
        while (File.Exists(Path.Combine(game, $"{_category}_demo{i}.dem"))) i++;
        return $"{_category}_demo{i}";
    }

    string StartTake()
    {
        if (_take != null) return $"demo '{_take}' is already recording";
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
        return $"demo '{name}': bots and recording started. H > Stop demo (or DEL) to finish";
    }

    string StopTake()
    {
        Server.ExecuteCommand("tv_stoprecord");
        Halt();
        var msg = _take != null ? $"demo saved: {_take}.dem" : "demo stopped";
        FireTakeStopped();
        _take = null;
        return msg;
    }

    [ConsoleCommand("fm_take", "fm_take - record a demo (all bots play), again to stop it")]
    public void CmdTake(CCSPlayerController? caller, CommandInfo cmd) =>
        cmd.ReplyToCommand("[FM] " + (_take == null ? StartTake() : StopTake()));

    [ConsoleCommand("fm_takestop", "fm_takestop - stop the demo and the bots")]
    public void CmdTakeStop(CCSPlayerController? caller, CommandInfo cmd) => cmd.ReplyToCommand("[FM] " + StopTake());

    // ---------------- recording over a running replay ----------------

    // The player sees the bots about 4 ticks late (interpolation), and the server rewinds them for the
    // player's shots. The recording's input history carries that interpolation, so the replayed shots are
    // rewound the same way: the recording starts in the same tick as the replays.
    string RecordOver(string name)
    {
        if (_bc == null) return "CS2-Bot-Controller is not installed";
        if (_replays.Count == 0) return "no bots assigned: Movements > a movement > Play on T/CT bot";
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
        // the last one of a single pass: an open main menu shows Off again
        if (!_looping && !_starting && !_replays.Any(x => x.Running) && LocalHuman() is { } p) Reshow(p, "FakeMimic", MainMenu);
    }

    // A bot that plays a recording stays dead when killed: only Go() brings it back.
    // fd_fake.cfg turns the game's auto-respawn on, but it cannot leave out single players, and
    // switching it off inside the death event is too late. So while FakeMimic runs it takes the
    // respawn over: the cvars go off and everybody else is respawned here after RespawnDelay.
    const float RespawnDelay = 2f;
    bool _ownRespawn;   // the cfg wanted auto-respawn and FakeMimic does it instead

    // ---------------- your own configs ----------------
    // The launcher copies Documents\FakeDemo\configs into cfg\fdc (configs\auto runs by itself after the
    // fake binds); this screen runs any of them. unfake puts your binds and the settings they change back
    string OwnCfgDir => Path.Combine(Server.GameDirectory, "csgo", "cfg", "fdc");

    List<string> OwnCfgs() => !Directory.Exists(OwnCfgDir) ? new() :
        Directory.GetFiles(OwnCfgDir, "*.cfg").Select(f => Path.GetFileNameWithoutExtension(f))
            .Concat(Directory.Exists(Path.Combine(OwnCfgDir, "auto"))
                ? Directory.GetFiles(Path.Combine(OwnCfgDir, "auto"), "*.cfg").Select(f => "auto/" + Path.GetFileNameWithoutExtension(f))
                : [])
            .ToList();

    void ConfigsMenu(CCSPlayerController p) => ConfigsMenu(p, 0);

    void ConfigsMenu(CCSPlayerController p, int page)
    {
        var entries = OwnCfgs().Select(c => new MenuItem(c.StartsWith("auto/") ? c[5..] : c, pl =>
        {
            Server.ExecuteCommand($"exec fdc/{c}");
            Say(pl, $"config '{c}' run (unfake puts your binds back)");
            ConfigsMenu(pl, page);
        }) { Value = c.StartsWith("auto/") ? "auto" : null }).ToList();
        if (entries.Count == 0)
            entries.Add(new("Put .cfg files into Documents\\FakeDemo\\configs", _ => { }) { Kind = ApiRowKind.Info });
        entries.Add(new("Your binds back (unfake)", pl => { Server.ExecuteCommand("exec fd_unfake"); Say(pl, "your binds back; fake keys: exec fd_user"); ConfigsMenu(pl, page); }));
        ShowPaged(p, "Your configs", entries, page, ConfigsMenu, MainMenu);
    }

    // a hot reload: the cvars go back on, or the new instance found them off and nobody respawned
    public override void Unload(bool hotReload)
    {
        if (_ownRespawn)
            foreach (var name in new[] { "mp_respawn_on_death_t", "mp_respawn_on_death_ct" }) ConVar.Find(name)?.SetValue(true);
        if (!hotReload) Unfake();   // the game is closing in a way that skipped quit
        base.Unload(hotReload);
    }

    // CS2 saves the binds it has when it closes into the Steam profile and its Steam Cloud copy: the fake
    // binds came back in a normal game (from the cloud copy) after the launcher had fixed the local file.
    // quit / exit wait for fd_unfake (the player's own binds, written by the launcher), then go on
    bool _quitting;

    HookResult OnQuit(CCSPlayerController? p, CommandInfo cmd)
    {
        if (_quitting) return HookResult.Continue;
        _quitting = true;
        Server.ExecuteCommand($"exec fd_unfake; {cmd.GetCommandString}");
        return HookResult.Stop;
    }

    static void Unfake() => Server.ExecuteCommand("exec fd_unfake");

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
            (r.PausedAt, r.BrakeTo) = (-1, -1);
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
            new("Put path here (my spot and view)", pl => { Say(pl, PutPathHere(name)); PathMenu(pl, name); }),
            new("Path back to where it was recorded", pl => { Say(pl, ResetPath(name)); PathMenu(pl, name); }),
            new($"Die at end: {(e.DieAtEnd ? "yes" : "no")}", pl => { Say(pl, ToggleDieAtEnd(name)); PathMenu(pl, name); }),
            new("← Back", pl => RecordingMenu(pl, name)),
        }));
    }
}
