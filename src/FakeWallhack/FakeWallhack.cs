// FakeWallhack: bots seen through walls and the paths of their movements, for practising a move and for
// recording over running bots. Every bot gets a glowing copy of its model that follows it through a hidden
// relay prop, and is kept "spotted" so the radar shows it; paths are beams along the recorded route.
// Only the human player is sent the copies and beams: GOTV never gets them, so demos show ordinary bots.
// On: J (fw_wallhack) or its screen in FakeMimic's menu; by itself while FakeMimic records a movement or a take.
// Settings are kept in Documents\FakeDemo\wallhack.txt.
using System.Drawing;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Core.Capabilities;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Memory;
using CounterStrikeSharp.API.Modules.Utils;
using FakeMimicApi;
using Microsoft.Extensions.Logging;
using Vector = CounterStrikeSharp.API.Modules.Utils.Vector;

namespace FakeWallhack;

public class FakeWallhack : BasePlugin
{
    public override string ModuleName => "FakeWallhack";
    public override string ModuleVersion => GetType().Assembly.GetName().Version?.ToString(3) ?? "?";
    public override string ModuleAuthor => "fakedemo";
    public override string ModuleDescription => "Bots and their paths seen through walls (not in demos)";

    static readonly PluginCapability<IFakeMimicApi> FakeMimic = new(IFakeMimicApi.Capability);

    sealed class Glow
    {
        public required CBaseModelEntity Relay;
        public required CBaseModelEntity Copy;
        public required CCSPlayerPawn Pawn;
        public required string Model;
        public required Color Color;
        public int Alpha = 255;
    }

    static readonly string[] WhoNames = { "All", "Enemies", "Team", "Recorded" };
    static readonly string[] RangeNames = { "Any", "10 m", "20 m", "40 m" };
    static readonly float[] RangeUnits = { float.MaxValue, 394, 787, 1575 };   // 1 m ≈ 39.4 units
    static readonly (int T, int CT)[] Palettes =
    {
        (ApiColors.Orange, ApiColors.Blue), (ApiColors.Red, ApiColors.Teal),
        (ApiColors.Yellow, ApiColors.Green), (ApiColors.White, ApiColors.White),
    };

    readonly Dictionary<int, Glow> _glows = new();   // by bot slot
    readonly List<CBeam> _beams = new();
    string _beamsKey = "";
    bool _manual;                                     // J / menu
    int _auto;                                        // FakeMimic recordings and takes running
    IFakeMimicApi? _fm;
    int _tick;

    // settings
    bool _autoOn = true, _radar = true, _paths, _more;
    int _who, _range, _palette;

    bool Wanted => _manual || (_autoOn && _auto > 0);

    static string SettingsPath => Path.Combine(FakeDemoPaths.Root, "wallhack.txt");

    void LoadSettings()
    {
        try
        {
            var p = File.ReadAllText(SettingsPath).Split(' ').Select(int.Parse).ToArray();
            (_autoOn, _radar, _paths, _more) = (p[0] != 0, p[1] != 0, p[2] != 0, p[3] != 0);
            (_who, _range, _palette) = (Math.Clamp(p[4], 0, 3), Math.Clamp(p[5], 0, 3), Math.Clamp(p[6], 0, 3));
        }
        catch (Exception) { /* no file: defaults */ }
    }

    void SaveSettings()
    {
        Directory.CreateDirectory(FakeDemoPaths.Root);
        int B(bool v) => v ? 1 : 0;
        File.WriteAllText(SettingsPath, $"{B(_autoOn)} {B(_radar)} {B(_paths)} {B(_more)} {_who} {_range} {_palette}");
    }

    public override void Load(bool hotReload)
    {
        LoadSettings();
        if (hotReload) AddTimer(0.5f, Hook);
        RegisterListener<Listeners.OnMapStart>(_ => { _glows.Clear(); _beams.Clear(); _beamsKey = ""; _auto = 0; });
        RegisterListener<Listeners.OnTick>(() =>
        {
            if (++_tick % 8 == 0) Sync();
            if (_tick % 32 == 0) SyncPaths();
            if (_tick % 2 == 0) Fade();
            Spot();
        });
        RegisterListener<Listeners.CheckTransmit>(infos =>
        {
            if (_glows.Count == 0 && _beams.Count == 0) return;
            foreach (var (info, player) in infos)
            {
                if (player is { IsValid: true, IsBot: false, IsHLTV: false }) continue;   // the one who plays
                foreach (var g in _glows.Values)
                {
                    info.TransmitEntities.Remove(g.Copy);
                    info.TransmitEntities.Remove(g.Relay);
                }
                foreach (var b in _beams) info.TransmitEntities.Remove(b);
            }
        });
    }

    public override void OnAllPluginsLoaded(bool hotReload) => Hook();

    // into FakeMimic's menu and events, once per FakeMimic instance (a hot reload of this plugin alone
    // does not call OnAllPluginsLoaded, so Load hooks too)
    void Hook()
    {
        var fm = FakeMimic.Get();
        if (fm == null || ReferenceEquals(fm, _fm)) return;   // works without FakeMimic: J only
        _fm = fm;
        Logger.LogInformation("Wallhack screen added to the FakeMimic menu");
        if (fm.Version != IFakeMimicApi.CurrentVersion)
            Logger.LogWarning("FakeMimic API {Have}, FakeWallhack was built for {Want}: install matching versions", fm.Version, IFakeMimicApi.CurrentVersion);
        fm.AddMainMenuItem(() => new ApiMenuItem("Wallhack ›", Screen) { Value = Wanted ? "on" : "off", On = Wanted });
        fm.RecordingStarted += _ => _auto++;
        fm.RecordingStopped += _ => _auto = Math.Max(0, _auto - 1);
        fm.TakeStarted += _ => _auto++;
        fm.TakeStopped += _ => _auto = Math.Max(0, _auto - 1);
    }

    public override void Unload(bool hotReload)
    {
        foreach (var slot in _glows.Keys.ToList()) Remove(slot);
        ClearBeams();
    }

    void Toggle() => _manual = !_manual;

    // module screen in FakeMimic's menu: the main switch big on top, often changed below it,
    // set-once settings behind "Settings +"
    void Screen(CCSPlayerController p)
    {
        if (_fm == null) return;
        void Set(CCSPlayerController pl, Action change) { change(); SaveSettings(); Screen(pl); }
        var rows = new List<ApiMenuItem>
        {
            new("Bots through walls", pl => { Toggle(); Screen(pl); }) { Kind = ApiRowKind.BigToggle, On = _manual, Value = Wanted && !_manual ? "auto, J" : "J" },
            new("Movement paths", pl => Set(pl, () => _paths = !_paths)) { Kind = ApiRowKind.Toggle, On = _paths, Divider = true },
            new("Who", _ => { }) { Kind = ApiRowKind.Choice, Options = WhoNames, Selected = _who, Choose = (pl, i) => Set(pl, () => _who = i) },
            // the HUD font has no ▾; opened, the settings are one block with this row as its top
            new("Settings", pl => Set(pl, () => _more = !_more)) { Value = _more ? "-" : "+", Divider = true, Nested = _more },
        };
        if (_more)
            rows.AddRange(new ApiMenuItem[]
            {
                new("Range", _ => { }) { Kind = ApiRowKind.Choice, Options = RangeNames, Selected = _range, Choose = (pl, i) => Set(pl, () => _range = i), Nested = true },
                new("Colors T / CT", _ => { })
                {
                    Kind = ApiRowKind.Colors, Swatches = Palettes.Select(c => (c.T, c.CT)).ToList(), Selected = _palette,
                    Choose = (pl, i) => Set(pl, () => _palette = i), Nested = true,
                },
                new("Show on radar", pl => Set(pl, () => _radar = !_radar)) { Kind = ApiRowKind.Toggle, On = _radar, Nested = true },
                new("On when recording", pl => Set(pl, () => _autoOn = !_autoOn)) { Kind = ApiRowKind.Toggle, On = _autoOn, Nested = true },
            });
        _fm.ShowMenu(p, "Wallhack", rows, pl => _fm.OpenMainMenu(pl));
    }

    string Describe() => _manual ? "bots glow through walls (J to turn off)"
        : _autoOn ? "bots glow only while you record or a take runs" : "wallhack off";

    static CCSPlayerController? Human() =>
        Utilities.GetPlayers().FirstOrDefault(p => p is { IsValid: true, IsBot: false, IsHLTV: false });

    Color TeamColor(int team) => ApiColors.Rgb[team == 3 ? Palettes[_palette].CT : Palettes[_palette].T];

    HashSet<int> Recorded() => _fm?.Replays.Select(r => r.BotSlot).ToHashSet() ?? new();

    // "who" without the range: also decides whose paths are drawn
    bool Picked(CCSPlayerController bot, CCSPlayerController? human, HashSet<int> recorded) => _who switch
    {
        1 => human == null || bot.TeamNum != human.TeamNum,
        2 => human != null && bot.TeamNum == human.TeamNum,
        3 => recorded.Contains(bot.Slot),
        _ => true,
    };

    // a few times a second: glows follow the wanted state, the filters, the bots' lives and model changes
    void Sync()
    {
        var keep = new HashSet<int>();
        if (Wanted)
        {
            var human = Human();
            var eye = human?.PlayerPawn.Value?.AbsOrigin;
            var recorded = _who == 3 ? Recorded() : new();
            foreach (var bot in Utilities.GetPlayers().Where(p => p is { IsValid: true, IsBot: true, IsHLTV: false, PawnIsAlive: true }))
            {
                if (bot.PlayerPawn.Value is not { IsValid: true } pawn || !Picked(bot, human, recorded)) continue;
                if (AlphaAt(eye, pawn) == 0) continue;
                var model = pawn.CBodyComponent?.SceneNode?.GetSkeletonInstance().ModelState.ModelName ?? "";
                if (model.Length == 0) continue;
                keep.Add(bot.Slot);
                var color = TeamColor(bot.TeamNum);
                if (_glows.TryGetValue(bot.Slot, out var g) && g.Pawn.IsValid && g.Pawn.Index == pawn.Index && g.Model == model
                    && g.Color == color && g.Copy.IsValid && g.Relay.IsValid) continue;
                Remove(bot.Slot);
                var made = Make(pawn, model, color);
                if (made != null) _glows[bot.Slot] = made;
            }
        }
        foreach (var slot in _glows.Keys.Where(s => !keep.Contains(s)).ToList()) Remove(slot);
    }

    // with a range the outline fades out over its last FadePart instead of going off at the edge
    const float FadePart = 0.4f;

    int AlphaAt(Vector? eye, CCSPlayerPawn pawn)
    {
        if (_range == 0 || eye == null || pawn.AbsOrigin == null) return 255;
        var range = RangeUnits[_range];
        var t = (range - Distance(eye, pawn.AbsOrigin)) / (range * FadePart);
        return (int)(Math.Clamp(t, 0f, 1f) * 255);
    }

    // every other tick: the outlines' brightness follows the distance (a new glow is made by Sync)
    void Fade()
    {
        if (_glows.Count == 0) return;
        var eye = Human()?.PlayerPawn.Value?.AbsOrigin;
        foreach (var g in _glows.Values)
        {
            if (!g.Pawn.IsValid || !g.Copy.IsValid) continue;
            var a = _forceAlpha >= 0 ? _forceAlpha : AlphaAt(eye, g.Pawn);
            if (Math.Abs(a - g.Alpha) < 6 && a is not (0 or 255)) continue;
            if (a == g.Alpha) continue;
            g.Alpha = a;
            g.Copy.Glow.GlowColorOverride = Color.FromArgb(a, g.Color);
            // m_Glow is an embedded struct: name the field in it, at the struct's offset (the plain
            // "m_Glow" change was "not resolved" and never reached the client)
            Utilities.SetStateChanged(g.Copy, "CGlowProperty", "m_glowColorOverride", Schema.GetSchemaOffset("CBaseModelEntity", "m_Glow"));
        }
    }

    int _forceAlpha = -1;

    [ConsoleCommand("fw_alpha", "fw_alpha <0-255 | -1> - force the outlines' alpha (debug)")]
    public void CmdAlpha(CCSPlayerController? caller, CommandInfo cmd)
    {
        _forceAlpha = int.TryParse(cmd.ArgByIndex(1), out var a) ? Math.Clamp(a, -1, 255) : -1;
        cmd.ReplyToCommand($"[Wallhack] alpha {(_forceAlpha < 0 ? "by distance" : _forceAlpha)}");
    }

    static float Distance(Vector a, Vector b)
    {
        float x = a.X - b.X, y = a.Y - b.Y, z = a.Z - b.Z;
        return MathF.Sqrt(x * x + y * y + z * z);
    }

    static Glow? Make(CCSPlayerPawn pawn, string model, Color color)
    {
        var relay = Utilities.CreateEntityByName<CBaseModelEntity>("prop_dynamic");
        var copy = Utilities.CreateEntityByName<CBaseModelEntity>("prop_dynamic");
        if (relay == null || copy == null) return null;
        // SetModel after the spawn (before it the engine asserts; the spawn prints "no model name", harmless)
        relay.Spawnflags = 256u;   // no collisions
        relay.RenderMode = RenderMode_t.kRenderNone;
        relay.DispatchSpawn();
        relay.SetModel(model);
        copy.Spawnflags = 256u;
        copy.DispatchSpawn();
        copy.SetModel(model);
        // after the spawn: the spawn resets m_Glow
        copy.Glow.GlowColorOverride = color;
        copy.Glow.GlowRange = 5000;
        copy.Glow.GlowRangeMin = 0;
        copy.Glow.GlowTeam = -1;
        copy.Glow.GlowType = 3;    // outline through walls
        Utilities.SetStateChanged(copy, "CBaseModelEntity", "m_Glow");
        relay.AcceptInput("FollowEntity", pawn, relay, "!activator");
        copy.AcceptInput("FollowEntity", relay, copy, "!activator");
        return new Glow { Relay = relay, Copy = copy, Pawn = pawn, Model = model, Color = color };
    }

    void Remove(int slot)
    {
        if (!_glows.Remove(slot, out var g)) return;
        if (g.Copy.IsValid) g.Copy.Remove();
        if (g.Relay.IsValid) g.Relay.Remove();
    }

    // ---------------- movement paths ----------------
    const int MaxSegmentsPerPath = 80;

    // twice a second: redrawn only when the assignments, their edits, the filter or the colours change
    void SyncPaths()
    {
        var shown = new List<ApiReplay>();
        if (_paths && _fm != null)
        {
            var human = Human();
            var recorded = Recorded();
            foreach (var r in _fm.Replays)
                if (Utilities.GetPlayerFromSlot(r.BotSlot) is { IsValid: true } bot && Picked(bot, human, recorded) && r.Path.Count > 1)
                    shown.Add(r);
        }
        var key = string.Join("|", shown.Select(r => $"{r.Name}:{r.BotSlot}:{System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(r.Path)}")) + $"#{_palette}";
        if (key == _beamsKey) return;
        _beamsKey = key;
        ClearBeams();
        foreach (var r in shown)
        {
            var color = TeamColor(r.Team);
            var step = (r.Path.Count - 1 + MaxSegmentsPerPath - 1) / MaxSegmentsPerPath;
            var prev = r.Path[0];
            for (var i = step; i < r.Path.Count + step - 1; i += step)
            {
                var next = r.Path[Math.Min(i, r.Path.Count - 1)];
                Beam(prev, next, color);
                prev = next;
            }
            // the start stands out: a gold post where the bot begins
            var start = r.Path[0];
            Beam(start, start with { Z = start.Z + 72 }, Color.FromArgb(255, 228, 174, 57));
        }
    }

    void Beam(System.Numerics.Vector3 a, System.Numerics.Vector3 b, Color color)
    {
        var beam = Utilities.CreateEntityByName<CBeam>("beam");
        if (beam == null) return;
        beam.Render = color;
        beam.Width = 2.5f;
        beam.Teleport(new Vector(a.X, a.Y, a.Z + 4), new QAngle(0, 0, 0), new Vector(0, 0, 0));
        beam.EndPos.X = b.X;
        beam.EndPos.Y = b.Y;
        beam.EndPos.Z = b.Z + 4;
        beam.DispatchSpawn();
        _beams.Add(beam);
    }

    void ClearBeams()
    {
        foreach (var b in _beams.Where(b => b.IsValid)) b.Remove();
        _beams.Clear();
    }

    // every tick: the game clears "spotted" for bots out of sight, the radar would drop them
    void Spot()
    {
        if (!_radar) return;
        foreach (var g in _glows.Values)
        {
            if (!g.Pawn.IsValid) continue;
            var st = g.Pawn.EntitySpottedState;
            if (st.Spotted && st.SpottedByMask[0] == uint.MaxValue) continue;
            st.Spotted = true;
            st.SpottedByMask[0] = uint.MaxValue;
            st.SpottedByMask[1] = uint.MaxValue;
            // the fields live in an embedded struct: name them in it, at the struct's offset in the pawn
            var at = Schema.GetSchemaOffset("CCSPlayerPawn", "m_entitySpottedState");
            Utilities.SetStateChanged(g.Pawn, "EntitySpottedState_t", "m_bSpotted", at);
            Utilities.SetStateChanged(g.Pawn, "EntitySpottedState_t", "m_bSpottedByMask", at);
        }
    }

    [ConsoleCommand("fw_wallhack", "fw_wallhack - bots through walls on / off (key J)")]
    public void CmdWallhack(CCSPlayerController? caller, CommandInfo cmd)
    {
        Toggle();
        cmd.ReplyToCommand("[Wallhack] " + Describe());
        (caller ?? Human())?.PrintToCenter(_manual ? "Wallhack ON" : "Wallhack OFF");
    }

    [ConsoleCommand("fw_glows", "fw_glows - glowing copies and path beams (debug)")]
    public void CmdGlows(CCSPlayerController? caller, CommandInfo cmd)
    {
        foreach (var (slot, g) in _glows)
        {
            var o = g.Copy.AbsOrigin;
            cmd.ReplyToCommand($"[Wallhack] slot {slot}: copy #{g.Copy.Index} at {o?.X:0},{o?.Y:0},{o?.Z:0} glowtype={g.Copy.Glow.GlowType} alpha={g.Alpha}");
        }
        cmd.ReplyToCommand($"[Wallhack] {_glows.Count} glows, {_beams.Count} path beams, who={WhoNames[_who]} range={RangeNames[_range]}");
    }
}
