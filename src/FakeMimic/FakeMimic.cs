// FakeMimic - Bot Mimic for CS2 fake demos.
// Records the local player and replays recordings on bots, all starting on the same tick,
// so enemies come out exactly on time. Recording and replay run on CS2-Bot-Controller
// (engine level: movement, view, buttons incl. shooting, subtick input); FakeMimic adds
// files, folders, weapon switching, the shared start and the menu.
//
// H opens the menu (fm_menu); while it is open, 1-9 pick items (aliases fm_d1..fm_d9).
// Console:
//   fm_rec [name]            start recording yourself (default name m1, m2, ...)
//   fm_stop                  stop recording and save (data/<map>/<folder>/<name>.fmr)
//   fm_list                  recordings in the current folder and which bot plays them
//   fm_assign <name> <t|ct>  add a bot of that team that will play <name>
//   fm_go                    respawn every assigned bot and start all replays together
//   fm_halt                  stop all replays (bots freeze where they are)
//   fm_clear                 forget all assignments
//   fm_kickall               remove every bot, GOTV stays (BACKSPACE runs it)
//   fm_del <name>            delete a recording
//   fm_take                  start a take (bots + demo), again to stop; fm_path <name> shows a route
// Takes, timing, path preview, recording over replays, path transform and deaths: FakeMimic.Features.cs
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;
using BotControllerApi;
using FakeMimicApi;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Core.Capabilities;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Extensions;
using CounterStrikeSharp.API.Modules.Utils;
using CounterStrikeSharp.API.ValveConstants.Protobuf;

namespace FakeMimic;

// one recording as stored on disk: CS2-Bot-Controller buffers plus what the bot must carry
public class Recording
{
    public int Team;
    public List<string> Weapons = new();
    public ReplayTick[] Ticks = Array.Empty<ReplayTick>();
    public SubtickMove[] Subs = Array.Empty<SubtickMove>();
    public ReplayCommandFrame[] Commands = Array.Empty<ReplayCommandFrame>();

    // FMR2 = FMR1 + the byte size of each CS2-Bot-Controller struct, so a recording made with
    // another BotController version is refused instead of replaying garbage
    const string Magic = "FMR2", MagicV1 = "FMR1";

    static int[] StructSizes() => [Unsafe.SizeOf<ReplayTick>(), Unsafe.SizeOf<SubtickMove>(), Unsafe.SizeOf<ReplayCommandFrame>()];

    public void Save(string path)
    {
        using var w = new BinaryWriter(File.Create(path));
        w.Write(Magic);
        foreach (var size in StructSizes()) w.Write(size);
        w.Write(Team);
        w.Write(Weapons.Count);
        foreach (var s in Weapons) w.Write(s);
        Write(w, Ticks);
        Write(w, Subs);
        Write(w, Commands);
    }

    public static Recording Load(string path)
    {
        using var r = new BinaryReader(File.OpenRead(path));
        var magic = r.ReadString();
        if (magic == Magic)
        {
            var sizes = StructSizes();
            foreach (var size in sizes)
                if (r.ReadInt32() != size)
                    throw new InvalidDataException($"{Path.GetFileName(path)}: recorded with another CS2-Bot-Controller version, re-record it");
        }
        else if (magic != MagicV1) throw new InvalidDataException($"{path}: not a FakeMimic recording");
        var rec = new Recording { Team = r.ReadInt32() };
        for (int i = r.ReadInt32(); i > 0; i--) rec.Weapons.Add(r.ReadString());
        rec.Ticks = Read<ReplayTick>(r);
        rec.Subs = Read<SubtickMove>(r);
        rec.Commands = Read<ReplayCommandFrame>(r);
        return rec;
    }

    // the structs are blittable (sequential, Pack = 4), so they go to disk as raw bytes
    static void Write<T>(BinaryWriter w, T[] items) where T : struct
    {
        w.Write(items.Length);
        w.Write(MemoryMarshal.AsBytes(items.AsSpan()));
    }

    static T[] Read<T>(BinaryReader r) where T : struct
    {
        var items = new T[r.ReadInt32()];
        r.BaseStream.ReadExactly(MemoryMarshal.AsBytes(items.AsSpan()));
        return items;
    }

    public float Seconds => Ticks.Length / 64f;
}

class Replay
{
    public required string Name;
    public required Recording Rec;
    public RecordingEdits Edits = new();   // timing, path transform, deaths (FakeMimic.Features.cs)
    public CCSPlayerController? Bot;
    public bool Running;      // StartReplay was called and the end was not reached yet
    public int LastWeaponDef;
}

public partial class FakeMimic : BasePlugin
{
    public override string ModuleName => "FakeMimic";
    // package version from VERSION (Directory.Build.props)
    public override string ModuleVersion => GetType().Assembly.GetName().Version?.ToString(3) ?? "?";
    public override string ModuleAuthor => "fakedemo";
    public override string ModuleDescription => "Record your movement and replay it on bots";

    const string Ext = ".fmr";
    static readonly PluginCapability<IBotControllerApi> BotController = new("botcontroller:api");
    IBotControllerApi? _bc;

    string? _recName;
    CCSPlayerController? _recPlayer;
    List<string>? _recWeapons;
    readonly List<Replay> _replays = new();

    // recordings live in Documents/FakeDemo/recordings/<map>/<folder>/<name>.fmr; a folder is one moment of the movie
    string _category = "default";

    string MapRoot
    {
        get
        {
            var d = Path.Combine(FakeDemoPaths.Recordings, Server.MapName);
            Directory.CreateDirectory(d);
            return d;
        }
    }

    string MapDir
    {
        get
        {
            var d = Path.Combine(MapRoot, _category);
            Directory.CreateDirectory(d);
            return d;
        }
    }

    IEnumerable<string> Categories() =>
        Directory.GetDirectories(MapRoot).Select(Path.GetFileName).OfType<string>().Append(_category).Distinct().Order();

    public override void Load(bool hotReload)
    {
        RegisterListener<Listeners.OnTick>(OnTick);
        RegisterListener<Listeners.OnMapStart>(_ =>
        {
            _recName = null; _replays.Clear(); _menu = null; _hud = null;
            // create the (hidden) HUD while the map loads: the first creation loads the panorama
            // layout and froze the game for ~0.5 s when it happened on the first H press
            AddTimer(2f, () => Hud());
            // after fd_fake.cfg (gamemode_custom_server.cfg) has set the respawn cvars
            AddTimer(3f, TakeOverRespawn);
        });
        RegisterListener<Listeners.OnCustomHudClicked>(OnHudClicked);
        LoadMenuPrefs();
        LoadModels();
        if (hotReload)
        {
            AddTimer(1f, TakeOverRespawn);   // no map start after a hot reload
            // the menu panel of the previous instance would stay on screen with nobody driving it
            foreach (var old in Utilities.FindAllEntitiesByDesignerName<CCSCustomHudLayout>("custom_hud_layout")) old.Remove();
        }
        RegisterApi();
        // the layout is a resource: it must be precached on map load or the entity rejects it
        RegisterListener<Listeners.OnServerPrecacheResources>(m =>
        {
            m.AddResource(HudLayout);
            foreach (var model in _models) m.AddResource(model);
            Logger.LogInformation("precached HUD layout and {Count} character models", _models.Count);
        });
        AddCommandListener("say", OnSay);
        AddCommandListener("say_team", OnSay);
    }

    public override void OnAllPluginsLoaded(bool hotReload)
    {
        _bc = BotController.Get();
        if (_bc == null) Logger.LogError("CS2-Bot-Controller API not found: turn plugins on with the FakeDemo launcher");
        Logger.LogInformation("FakeMimic {Version}, data in {Root}", ModuleVersion, FakeDemoPaths.Root);
    }

    static CCSPlayerController? LocalHuman() =>
        Utilities.GetPlayers().FirstOrDefault(p => p is { IsValid: true, IsBot: false, IsHLTV: false });

    // replay drives movement, view and buttons; weapons are switched here from the replayed tick,
    // and a bot that reached the end is frozen in place (otherwise its AI walks away)
    void OnTick()
    {
        if (_bc == null) return;
        foreach (var r in _replays)
        {
            if (!r.Running || r.Bot is not { IsValid: true }) continue;
            var slot = r.Bot.Slot;
            if (!_bc.IsReplaying(slot))
            {
                r.Running = false;
                OnReplayEnd(r);
                continue;
            }
            if (_bc.TryGetReplayTick(slot, out var tick) && tick.WeaponDefIndex > 0 && tick.WeaponDefIndex != r.LastWeaponDef
                && _bc.BotActiveWeaponDef(slot) != tick.WeaponDefIndex)
            {
                r.LastWeaponDef = tick.WeaponDefIndex;
                _bc.SwitchBotWeapon(slot, tick.WeaponDefIndex);
            }
        }
    }

    // ---------------- actions (shared by console commands and the menu) ----------------

    string PathOf(string name) => Path.Combine(MapDir, name + Ext);

    IEnumerable<string> Names() =>
        Directory.GetFiles(MapDir, "*" + Ext).Select(Path.GetFileNameWithoutExtension).OfType<string>().Order();

    string NextName()
    {
        var names = Names().ToHashSet();
        var i = 1;
        while (names.Contains($"m{i}")) i++;
        return $"m{i}";
    }

    string StartRec(string name)
    {
        if (_bc == null) return "CS2-Bot-Controller is not installed";
        if (_recName != null) return $"already recording '{_recName}'";
        var p = LocalHuman();
        var pawn = p?.PlayerPawn.Value;
        if (p == null || pawn == null || !p.PawnIsAlive) return "you must be alive";

        _recWeapons = pawn.WeaponServices!.MyWeapons.Select(h => h.Value?.DesignerName).OfType<string>().ToList();
        if (!_bc.SetReplayPawn(p.Slot, pawn.Handle) || !_bc.StartRecord(p.Slot)) return "recording did not start";
        _recName = name;
        _recPlayer = p;
        return $"recording '{name}'...";
    }

    string StopRec()
    {
        if (_recName == null || _bc == null) return "not recording";
        var slot = _recPlayer!.Slot;
        _bc.StopRecord(slot);
        var (ticks, subs, commands) = _bc.GetRecordedMotionExtended(slot);
        var rec = new Recording
        {
            Team = _recPlayer.TeamNum, Weapons = _recWeapons ?? new(), Ticks = ticks, Subs = subs, Commands = commands,
        };
        rec.Save(PathOf(_recName));
        var msg = $"saved '{_recName}': {rec.Seconds:0.0} s";
        _recName = null;
        return msg;
    }

    // adds a bot of the team; the result arrives later through report
    void Assign(string name, string team, Action<string> report)
    {
        if (!File.Exists(PathOf(name))) { report($"no recording '{name}'"); return; }
        var rec = Recording.Load(PathOf(name));
        var before = Utilities.GetPlayers().Where(p => p.IsBot).Select(p => p.Slot).ToHashSet();
        // bot_add raises bot_quota by 2 in CS2 (see fd_actions.cfg), lower it back by 1
        Server.ExecuteCommand($"bot_add_{team}; incrementvar bot_quota 0 64 -1");
        AddTimer(0.5f, () =>
        {
            var bot = Utilities.GetPlayers().FirstOrDefault(p => p.IsBot && !p.IsHLTV && !before.Contains(p.Slot));
            if (bot == null) { report("bot was not added"); return; }
            _bc?.Lock(bot.Slot, LockKind.All);   // stands still until fm_go
            _replays.RemoveAll(x => x.Name == name);
            _replays.Add(new Replay { Name = name, Rec = rec, Edits = EditsOf(name), Bot = bot });
            report($"{bot.PlayerName} ({team.ToUpper()}) plays '{name}'");
        });
    }

    // Respawn every assigned bot, then (all bots in the same steps): model, weapons, replay start.
    // Weapons go on after the model has settled: given in the respawn tick, holstered weapons sat
    // wrong on a T bot playing a CT recording until it dropped and picked them up again.
    const float ModelDelay = 0.2f, WeaponsDelay = 0.35f, StartDelay = 0.5f;

    string Go(Action? onStarted = null)
    {
        if (_bc == null) return "CS2-Bot-Controller is not installed";
        _replays.RemoveAll(r => r.Bot is not { IsValid: true });
        ClearPaths();
        foreach (var r in _replays)
        {
            _bc.StopReplay(r.Bot!.Slot);
            r.Running = false;
            r.Bot.Respawn();
            _bc.Lock(r.Bot.Slot, LockKind.All);   // stands at the spawn until the start
        }
        var replays = _replays.ToList();
        AddTimer(ModelDelay, () => { foreach (var r in replays) ApplyModel(r.Bot!, r.Edits); });
        AddTimer(WeaponsDelay, () =>
        {
            foreach (var r in replays.Where(r => r.Bot is { IsValid: true }))
            {
                r.Bot!.RemoveWeapons();
                foreach (var w in r.Rec.Weapons) r.Bot.GiveNamedItem(w);
            }
        });
        AddTimer(StartDelay, () =>
        {
            foreach (var r in replays)
            {
                var bot = r.Bot!;
                var pawn = bot.PlayerPawn.Value;
                if (bot is not { IsValid: true } || pawn == null) continue;
                r.LastWeaponDef = 0;
                var rec = Prepare(r.Rec, r.Edits);
                if (!_bc.SetReplayPawn(bot.Slot, pawn.Handle) || !_bc.LoadReplay(bot.Slot, rec.Ticks, rec.Subs, rec.Commands))
                {
                    Server.PrintToConsole($"[FM] replay '{r.Name}' did not load on {bot.PlayerName}");
                    continue;
                }
                // a later start keeps the bot frozen at its spawn until its time comes
                void Start()
                {
                    if (bot is not { IsValid: true }) return;
                    _bc.Unlock(bot.Slot, LockKind.All);
                    r.Running = _bc.StartReplay(bot.Slot);
                    if (!r.Running) Server.PrintToConsole($"[FM] replay '{r.Name}' did not start on {bot.PlayerName}");
                }
                if (r.Edits.OffsetTicks > 0) AddTimer(r.Edits.OffsetTicks / (float)TicksPerSecond, Start);
                else Start();
            }
            onStarted?.Invoke();
        });
        return $"go: {_replays.Count} replays";
    }

    string Halt()
    {
        foreach (var r in _replays.Where(r => r.Bot is { IsValid: true }))
        {
            _bc?.StopReplay(r.Bot!.Slot);
            _bc?.Lock(r.Bot!.Slot, LockKind.All);
            r.Running = false;
        }
        return "replays stopped";
    }

    string Clear()
    {
        foreach (var r in _replays.Where(r => r.Bot is { IsValid: true }))
        {
            _bc?.StopReplay(r.Bot!.Slot);
            _bc?.Unlock(r.Bot!.Slot, LockKind.All);
        }
        _replays.Clear();
        return "assignments cleared";
    }

    string Delete(string name)
    {
        if (!File.Exists(PathOf(name))) return $"no recording '{name}'";
        File.Delete(PathOf(name));
        File.Delete(EditsPathOf(name));
        _replays.RemoveAll(r => r.Name == name);
        return $"deleted '{name}'";
    }

    string Rename(string from, string to)
    {
        if (!File.Exists(PathOf(from))) return $"no recording '{from}'";
        if (File.Exists(PathOf(to))) return $"'{to}' already exists";
        File.Move(PathOf(from), PathOf(to));
        if (File.Exists(EditsPathOf(from))) File.Move(EditsPathOf(from), EditsPathOf(to));
        foreach (var r in _replays.Where(r => r.Name == from)) r.Name = to;
        return $"renamed to '{to}'";
    }

    string Describe(string name)
    {
        var r = _replays.FirstOrDefault(x => x.Name == name);
        return r?.Bot is { IsValid: true } b ? $"{name} -> {b.PlayerName}" : name;
    }

    // ---------------- menu (H) ----------------
    // Valve custom HUD (custom_hud_layout, Aug 2026): panorama/layout/custom_game/fm_menu.vxml
    // (source in src/hud_source, compiled with Workshop Tools, installed by plugins_on.ps1).
    // While the menu is open the player gets a mouse cursor and clicks arrive in OnCustomHudClicked.
    // Digits work too: fd_user.cfg binds 1-9 to aliases fm_d1..fm_d9, which the plugin points to
    // fm_k1..fm_k9 while the menu is open and back to slot1..slot9 after (on a listen server the
    // plugin and the client share one console).

    // the entity takes the source name (.xml); ".vxml" is rejected as an invalid resource name
    // fm_hud_file switches it for layout development (a new file name is never a cached one)
    static string HudLayout = "panorama/layout/custom_game/fm_menu.xml";

    record MenuItem(string Text, Action<CCSPlayerController> Pick, bool Accent = false);   // Accent: salmon row (stop, delete)
    record Menu(string Title, List<MenuItem> Items, bool Main = false);   // Close (9) only on the main menu

    Menu? _menu;
    CCSCustomHudLayout? _hud;
    bool _swapB;
    Action<CCSPlayerController, string>? _awaitText;   // next chat line goes here (names)

    void Say(CCSPlayerController p, string msg) => p.PrintToChat($" {ChatColors.Green}[FM]{ChatColors.Default} {msg}");

    void SetDigits(bool menu)
    {
        var cmds = Enumerable.Range(1, 9).Select(i => $"alias fm_d{i} {(menu ? "fm_k" : "slot")}{i}");
        Server.ExecuteCommand(string.Join("; ", cmds));
    }

    // one HUD entity per map, created on first use
    CCSCustomHudLayout? Hud()
    {
        if (_hud is { IsValid: true }) return _hud;
        _hud = Utilities.CreateEntityByName<CCSCustomHudLayout>("custom_hud_layout");
        if (_hud == null) return null;
        foreach (var k in _applied.Keys.ToList()) _applied[k] = k switch { "posx" => "X20", "posy" => "Y20", "poss" => "S0", _ => "V0" };
        var kv = new CEntityKeyValues();
        kv.SetString("layout", HudLayout);
        _hud.DispatchSpawn(kv);
        return _hud;
    }

    static string Plain(string text) => System.Text.RegularExpressions.Regex.Replace(text, "<[^>]+>", "");

    void Show(CCSPlayerController p, Menu m)
    {
        _menu = m;
        SetDigits(true);
        var hud = Hud();
        if (hud == null) { Say(p, "custom HUD could not be created"); return; }
        hud.SetDialogVariableString("menu", "title", Plain(m.Title));
        for (var i = 1; i <= 9; i++)
        {
            var item = i <= m.Items.Count ? m.Items[i - 1] : null;
            // digits are drawn as key hints by the layout, so the text has no number
            var text = i == 9 ? (m.Main ? "Close" : "") : item != null ? Plain(item.Text) : "";
            hud.SetDialogVariableString("menu", $"t{i}", text);
            hud.SetHasClass($"b{i}", "Empty", text.Length == 0);
            hud.SetHasClass($"b{i}", "Accent", i != 9 && item?.Accent == true);
        }
        ApplyMenuPrefs(hud);
        Swap(hud);   // replay the rows' entrance: opening and switching look the same
        _settingsOpen = false;
        hud.SetHasClass("menu", "Settings", false);
        hud.SetHasClass("menu", "Hidden", false);
        hud.SetInputCaptureEnabled(p, true);
    }

    // The layout replays the rows' entrance (keyframes) whenever the class on #menu switches between
    // SwapA and SwapB, in the same tick as the new texts: on every opening and every screen change.
    void Swap(CCSCustomHudLayout hud)
    {
        _swapB = !_swapB;
        hud.SetHasClass("menu", "SwapA", !_swapB);
        hud.SetHasClass("menu", "SwapB", _swapB);
    }

    void CloseMenu(CCSPlayerController p)
    {
        _menu = null;
        SetDigits(false);
        if (_hud is not { IsValid: true }) return;
        _hud.SetHasClass("menu", "Hidden", true);
        _hud.SetInputCaptureEnabled(p, false);
    }

    // Layout development: a changed vxml_c / vcss_c is never read again while the game runs (not on a
    // map load, not with resource_repeated_reload), so each build gets a new file name
    // (toolsuild_hud.ps1 -Name fm_menuN -Live) and this points the plugin at it for the next map load.
    [ConsoleCommand("fm_hud_file", "fm_hud_file <name> - use panorama/layout/custom_game/<name>.xml from the next map load (development)")]
    public void CmdHudFile(CCSPlayerController? caller, CommandInfo cmd)
    {
        HudLayout = $"panorama/layout/custom_game/{cmd.ArgByIndex(1)}.xml";
        cmd.ReplyToCommand($"[FM] menu layout {HudLayout} from the next map load");
    }

    [ConsoleCommand("fm_cls", "fm_cls <panel id> <class> <0|1> - set a class on the menu layout (debug)")]
    public void CmdCls(CCSPlayerController? caller, CommandInfo cmd)
    {
        if (_hud is not { IsValid: true }) { cmd.ReplyToCommand("[FM] no HUD entity"); return; }
        _hud.SetHasClass(cmd.ArgByIndex(1), cmd.ArgByIndex(2), cmd.ArgByIndex(3) != "0");
        cmd.ReplyToCommand($"[FM] {cmd.ArgByIndex(1)}.{cmd.ArgByIndex(2)} = {cmd.ArgByIndex(3) != "0"}");
    }

    [ConsoleCommand("fm_click", "fm_click <button id> - click a menu button, e.g. bg (gear), sb, sx12 (debug)")]
    public void CmdClick(CCSPlayerController? caller, CommandInfo cmd)
    {
        var p = caller ?? LocalHuman();
        if (p == null || _hud is not { IsValid: true }) { cmd.ReplyToCommand("[FM] no player or HUD"); return; }
        OnHudClicked(p, _hud, cmd.ArgByIndex(1));
    }

    [ConsoleCommand("fm_hudinfo", "fm_hudinfo - state of the menu HUD entity (debug)")]
    public void CmdHudInfo(CCSPlayerController? caller, CommandInfo cmd)
    {
        var h = _hud;
        if (h is not { IsValid: true }) { cmd.ReplyToCommand("[FM] no HUD entity"); return; }
        var g = h.GlobalLayoutState;
        cmd.ReplyToCommand($"[FM] hud #{h.Index} " +
                           $"classes={g.HasClasses.Count} vars={g.DialogVariableStrings.Count} players={h.PlayerLayoutStates.Count}");
    }

    void OnHudClicked(CCSPlayerController player, CCSCustomHudLayout layout, string buttonId)
    {
        if (_hud == null || layout.Index != _hud.Index) return;
        switch (buttonId)
        {
            case "bg": ShowSettings(!_settingsOpen); return;   // gear in the header
            case "sb": ShowSettings(false); return;            // Back on the settings screen
        }
        // slider segments: sx0..sx10, sy0..sy10, ss0..ss10
        if (buttonId.Length >= 3 && buttonId[0] == 's' && int.TryParse(buttonId[2..], out var v))
        {
            switch (buttonId[1])
            {
                case 'x': _menuX = v; break;
                case 'y': _menuY = v; break;
                case 's': _menuS = v; break;
                default: return;
            }
            SaveMenuPrefs();
            ApplyMenuPrefs(_hud);
            return;
        }
        // menu rows are b1..b9
        if (buttonId.Length == 2 && buttonId[0] == 'b') Pick(player, buttonId[1] - '0');
    }

    // ---------------- window position / size (Settings screen, remembered between sessions) ----------------
    // The HUD reports clicks only (no drag), so each slider is a bar + knob with SliderSteps+1
    // invisible buttons over it (sx0..sx40 ...): a click jumps the knob there. The CSS has a class
    // per step: X0..X40 / Y0..Y40 move wrapper panels (2.5% of the screen each, 20 = crosshair),
    // S0..S40 scale, V0..V40 on the slider itself draws fill and knob.

    const int SliderSteps = 40;
    const string PrefsVersion = "v2";
    int _menuX = 20, _menuY = 20, _menuS = 0;   // default: top-left corner on the crosshair, compact
    bool _settingsOpen;

    // classes currently on each panel, so only the changed ones are switched (the layout starts with these)
    readonly Dictionary<string, string> _applied = new()
    {
        ["posx"] = "X20", ["posy"] = "Y20", ["poss"] = "S0", ["slx"] = "V0", ["sly"] = "V0", ["sls"] = "V0",
    };

    string PrefsPath => Path.Combine(FakeDemoPaths.Root, "menu.txt");

    void LoadMenuPrefs()
    {
        try
        {
            var p = File.ReadAllText(PrefsPath).Split(' ');
            if (p[0] != PrefsVersion) return;   // older 11-step file: keep the defaults
            int V(string s) => Math.Clamp(int.Parse(s), 0, SliderSteps);
            (_menuX, _menuY, _menuS) = (V(p[1]), V(p[2]), V(p[3]));
        }
        catch (Exception) { /* no file: defaults */ }
    }

    void SaveMenuPrefs()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(PrefsPath)!);
        File.WriteAllText(PrefsPath, $"{PrefsVersion} {_menuX} {_menuY} {_menuS}");
    }

    void SetOnly(CCSCustomHudLayout hud, string panel, string cls)
    {
        if (_applied.TryGetValue(panel, out var old) && old == cls) return;
        if (old != null) hud.SetHasClass(panel, old, false);
        hud.SetHasClass(panel, cls, true);
        _applied[panel] = cls;
    }

    void ApplyMenuPrefs(CCSCustomHudLayout hud)
    {
        foreach (var (key, value, wrapper, cls) in new[] { ('x', _menuX, "posx", "X"), ('y', _menuY, "posy", "Y"), ('s', _menuS, "poss", "S") })
        {
            SetOnly(hud, wrapper, $"{cls}{value}");
            SetOnly(hud, $"sl{key}", $"V{value}");
            hud.SetDialogVariableString("menu", $"v{key}", $"{value * 2.5:0.#}%");
        }
    }

    void ShowSettings(bool open)
    {
        if (_hud is not { IsValid: true }) return;
        Swap(_hud);
        _settingsOpen = open;
        _hud.SetHasClass("menu", "Settings", open);
        _hud.SetDialogVariableString("menu", "title", open ? "Settings" : Plain(_menu?.Title ?? ""));
    }

    void Pick(CCSPlayerController p, int n)
    {
        if (_menu == null) return;
        if (n == 9 || n > _menu.Items.Count) { if (n == 9 && _menu.Main) CloseMenu(p); return; }
        var item = _menu.Items[n - 1];
        // the pick may open another screen (Show keeps the menu and replays the entrance); if it does
        // not (an action, a name asked in chat), the menu closes
        _menu = null;
        _awaitText = null;   // a chat question belongs to the screen it was asked on
        item.Pick(p);
        if (_menu == null) CloseMenu(p);
    }

    void AskText(CCSPlayerController p, string prompt, Action<CCSPlayerController, string> then)
    {
        _awaitText = then;
        Say(p, prompt + " (type it in chat, empty = cancel)");
    }

    HookResult OnSay(CCSPlayerController? p, CommandInfo cmd)
    {
        if (_awaitText == null || p == null) return HookResult.Continue;
        var text = cmd.GetArg(1).Trim();
        var then = _awaitText;
        _awaitText = null;
        // only latin letters, digits, _ and - (also used as file and folder names)
        var clean = new string(text.Where(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-').ToArray());
        if (clean.Length == 0) Say(p, "cancelled");
        else then(p, clean);
        return HookResult.Handled;   // the name does not appear in chat
    }

    void MainMenu(CCSPlayerController p)
    {
        var items = new List<MenuItem>();
        // most used first: movements and folder right under recording
        if (_recName == null)
            // with bots assigned they start in the same tick as the recording, so it lines up with them later
            items.Add(new("Record new movement", NewMovementMenu));
        else
            items.Add(new($"Stop and save '{_recName}'", pl => { Say(pl, StopRec()); MainMenu(pl); }, Accent: true));
        items.Add(new("Movements in this folder", RecordingsMenu));
        items.Add(new($"Folder: <font color='#ffd27f'>{_category}</font>", CategoriesMenu));
        if (_take == null)
            items.Add(new("Start take (bots + demo)", pl => Say(pl, StartTake())));
        else
            items.Add(new($"Stop take '{_take}'", pl => { Say(pl, StopTake()); MainMenu(pl); }, Accent: true));
        items.Add(new("Start all bots", pl => Say(pl, Go())));
        items.Add(new("Stop all bots", pl => { Say(pl, Halt()); MainMenu(pl); }));
        // add-on plugins (FakeDirector, ...) through the API; "Clear" stays last, away from the common rows
        items.AddRange(_addonItems.Take(Math.Max(0, 7 - items.Count)));
        items.Add(new("Clear bot assignments", pl => { Say(pl, Clear()); MainMenu(pl); }));
        Show(p, new Menu("FakeMimic", items, Main: true));
    }

    // a name is optional: 1 records under the next free default name (m1, m2, ...), or a name typed in
    // chat while this screen is open starts the recording under that name
    void NewMovementMenu(CCSPlayerController p)
    {
        var name = NextName();
        void Record(CCSPlayerController pl, string n)
        {
            Say(pl, _replays.Count > 0 ? RecordOver(n) : StartRec(n) + " H > 1 to stop");
            if (_menu != null) CloseMenu(pl);   // typed in chat: the menu is still open
        }
        Show(p, new Menu("New movement", new List<MenuItem>
        {
            new($"Record as '{name}'", pl => Record(pl, name)),
            new("← Back", MainMenu),
        }));
        _awaitText = Record;
        Say(p, $"1 = record as '{name}', or type your own name in chat");
    }

    void CategoriesMenu(CCSPlayerController p)
    {
        var items = Categories().Take(6).Select(c => new MenuItem(c == _category ? $"<font color='#ffd27f'>{c}</font>" : c,
            pl => { _category = c; Say(pl, $"folder: {c}"); MainMenu(pl); })).ToList();
        items.Add(new("New folder", pl => AskText(pl, "folder name (one moment = one folder)",
            (pl2, n) => { _category = n; Directory.CreateDirectory(MapDir); Say(pl2, $"folder: {n}"); MainMenu(pl2); })));
        items.Add(new("← Back", MainMenu));
        Show(p, new Menu($"Folders on {Server.MapName}", items));
    }

    void RecordingsMenu(CCSPlayerController p)
    {
        var items = Names().Take(7).Select(n => new MenuItem(Describe(n), pl => RecordingMenu(pl, n))).ToList();
        items.Add(new("← Back", MainMenu));
        Show(p, new Menu($"Movements in {_category}", items));
    }

    void RecordingMenu(CCSPlayerController p, string name)
    {
        Show(p, new Menu(Describe(name), new List<MenuItem>
        {
            new("Play on a bot (T / CT, model)", pl => PlayOnBotMenu(pl, name)),
            new($"Timing: {DescribeOffset(EditsOf(name).OffsetTicks)}", pl => TimingMenu(pl, name)),
            new("Path and death", pl => PathMenu(pl, name)),
            new("Rename", pl => AskText(pl, "new name", (pl2, n) => { Say(pl2, Rename(name, n)); RecordingsMenu(pl2); })),
            new("Delete", pl => { Say(pl, Delete(name)); RecordingsMenu(pl); }, Accent: true),
            new("← Back", RecordingsMenu),
        }));
    }

    [ConsoleCommand("fm_menu", "fm_menu - open / close the FakeMimic menu")]
    public void CmdMenu(CCSPlayerController? caller, CommandInfo cmd)
    {
        var p = caller ?? LocalHuman();
        if (p == null) return;
        if (_menu != null) { _awaitText = null; CloseMenu(p); } else MainMenu(p);
    }

    [ConsoleCommand("fm_k1", "")] public void K1(CCSPlayerController? c, CommandInfo _) => PickFor(c, 1);
    [ConsoleCommand("fm_k2", "")] public void K2(CCSPlayerController? c, CommandInfo _) => PickFor(c, 2);
    [ConsoleCommand("fm_k3", "")] public void K3(CCSPlayerController? c, CommandInfo _) => PickFor(c, 3);
    [ConsoleCommand("fm_k4", "")] public void K4(CCSPlayerController? c, CommandInfo _) => PickFor(c, 4);
    [ConsoleCommand("fm_k5", "")] public void K5(CCSPlayerController? c, CommandInfo _) => PickFor(c, 5);
    [ConsoleCommand("fm_k6", "")] public void K6(CCSPlayerController? c, CommandInfo _) => PickFor(c, 6);
    [ConsoleCommand("fm_k7", "")] public void K7(CCSPlayerController? c, CommandInfo _) => PickFor(c, 7);
    [ConsoleCommand("fm_k8", "")] public void K8(CCSPlayerController? c, CommandInfo _) => PickFor(c, 8);
    [ConsoleCommand("fm_k9", "")] public void K9(CCSPlayerController? c, CommandInfo _) => PickFor(c, 9);

    void PickFor(CCSPlayerController? c, int n)
    {
        var p = c ?? LocalHuman();
        if (p != null) Pick(p, n);
    }

    // ---------------- console commands ----------------

    [ConsoleCommand("fm_rec", "fm_rec [name] - start recording yourself")]
    public void CmdRec(CCSPlayerController? caller, CommandInfo cmd)
    {
        var name = cmd.ArgByIndex(1);
        cmd.ReplyToCommand("[FM] " + StartRec(string.IsNullOrWhiteSpace(name) ? NextName() : name));
    }

    [ConsoleCommand("fm_stop", "fm_stop - stop recording and save")]
    public void CmdStop(CCSPlayerController? caller, CommandInfo cmd) => cmd.ReplyToCommand("[FM] " + StopRec());

    [ConsoleCommand("fm_list", "fm_list - recordings for this map")]
    public void CmdList(CCSPlayerController? caller, CommandInfo cmd)
    {
        foreach (var n in Names()) cmd.ReplyToCommand("[FM] " + Describe(n));
    }

    [ConsoleCommand("fm_assign", "fm_assign <name> <t|ct> - a new bot will play the recording")]
    public void CmdAssign(CCSPlayerController? caller, CommandInfo cmd)
    {
        var team = cmd.ArgByIndex(2).ToLowerInvariant();
        if (team != "t" && team != "ct") { cmd.ReplyToCommand("usage: fm_assign <name> <t|ct>"); return; }
        Assign(cmd.ArgByIndex(1), team, s => Server.PrintToConsole("[FM] " + s));
    }

    [ConsoleCommand("fm_go", "fm_go - respawn assigned bots and start all replays")]
    public void CmdGo(CCSPlayerController? caller, CommandInfo cmd) => cmd.ReplyToCommand("[FM] " + Go());

    [ConsoleCommand("fm_halt", "fm_halt - stop all replays")]
    public void CmdHalt(CCSPlayerController? caller, CommandInfo cmd) => cmd.ReplyToCommand("[FM] " + Halt());

    [ConsoleCommand("fm_clear", "fm_clear - forget all assignments")]
    public void CmdClear(CCSPlayerController? caller, CommandInfo cmd) => cmd.ReplyToCommand("[FM] " + Clear());

    [ConsoleCommand("fm_del", "fm_del <name> - delete a recording")]
    public void CmdDel(CCSPlayerController? caller, CommandInfo cmd) => cmd.ReplyToCommand("[FM] " + Delete(cmd.ArgByIndex(1)));

    // BACKSPACE (fd_botkick) kicks the cfg's named bots, then this, then bot_quota 0. FakeMimic's bots get
    // random names, and lowering bot_quota while any bot is left kicks GOTV too, so they go here at once
    [ConsoleCommand("fm_kickall", "fm_kickall - remove every bot (GOTV stays)")]
    public void CmdKickAll(CCSPlayerController? caller, CommandInfo cmd)
    {
        _replays.Clear();
        foreach (var b in Utilities.GetPlayers().Where(p => p is { IsValid: true, IsBot: true, IsHLTV: false }))
            b.Disconnect(NetworkDisconnectionReason.NETWORK_DISCONNECT_KICKED);
    }

    [ConsoleCommand("fm_where", "fm_where - positions of all players (debug)")]
    public void CmdWhere(CCSPlayerController? caller, CommandInfo cmd)
    {
        foreach (var p in Utilities.GetPlayers().Where(p => p is { IsValid: true, IsHLTV: false }))
        {
            var o = p.PlayerPawn.Value?.AbsOrigin;
            var r = _replays.FirstOrDefault(x => x.Bot == p);
            var wpn = p.PlayerPawn.Value?.WeaponServices?.ActiveWeapon.Value;
            cmd.ReplyToCommand($"[FM] {p.PlayerName} alive={p.PawnIsAlive} pos={o?.X:0},{o?.Y:0},{o?.Z:0} weapon={wpn?.DesignerName}:{wpn?.Clip1}" +
                               (r != null && _bc != null ? $" replay={r.Name} {_bc.ReplayCursor(p.Slot)}/{_bc.ReplayTotal(p.Slot)}" : ""));
        }
    }
}
