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
using CounterStrikeSharp.API.Modules.Memory.DynamicFunctions;
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
    // what was bought while recording: the tick from the start and the item to give ("weapon_ak47")
    public List<(int Tick, string Item)> Buys = new();
    // CS2-Bot-Controller's input history (0.8.0+, opaque bytes): each command's random seed, attack timing
    // and interpolation, so the bot's bullets spread like the player's and the server rewinds the others
    // the way the player saw them. Empty for older recordings: the bot then shoots with its own spread.
    public byte[] History = Array.Empty<byte>();

    // FMR2 = FMR1 + the byte size of each CS2-Bot-Controller struct, so a recording made with
    // another BotController version is refused instead of replaying garbage. Optional sections follow at
    // the end, each after its mark: "BUYS" (purchases), then "HIST" (input history). Older FakeMimic
    // versions stop reading at the first mark they do not know.
    const string Magic = "FMR2", MagicV1 = "FMR1", BuysMark = "BUYS", HistoryMark = "HIST";

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
        if (Buys.Count > 0)
        {
            w.Write(BuysMark);
            w.Write(Buys.Count);
            foreach (var (tick, item) in Buys) { w.Write(tick); w.Write(item); }
        }
        if (History.Length > 0)
        {
            w.Write(HistoryMark);
            w.Write(History.Length);
            w.Write(History);
        }
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
        while (r.BaseStream.Position < r.BaseStream.Length)
        {
            var mark = r.ReadString();
            if (mark == BuysMark)
                for (int i = r.ReadInt32(); i > 0; i--) rec.Buys.Add((r.ReadInt32(), r.ReadString()));
            else if (mark == HistoryMark) rec.History = r.ReadBytes(r.ReadInt32());
            else break;   // a section of a newer FakeMimic
        }
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
    public int WrongWeapon;   // ticks the bot has held another weapon than the recording
    public List<(int Tick, string Item)> Buys = new();   // of the prepared recording
    public int NextBuy;
    public bool Ended;        // played to the end since the last start
    public int Length;        // ticks of the prepared recording
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
        LoadBotsPrefs();
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
        FakeDemoPlayers.All().FirstOrDefault(p => p is { IsValid: true, IsBot: false, IsHLTV: false });

    // replay drives movement, view, buttons and weapon switches; purchases are given here (and a wrong
    // weapon fixed), and a bot that reached the end is frozen in place (otherwise its AI walks away)
    void OnTick()
    {
        CheckOverlay();
        WaitCapture();
        ShowGiven();
        if (_bc == null) return;
        foreach (var r in _replays)
        {
            if (!r.Running || r.Bot is not { IsValid: true }) continue;
            var slot = r.Bot.Slot;
            if (!_bc.IsReplaying(slot))
            {
                r.Running = false;
                r.Ended = true;
                OnReplayEnd(r);
                continue;
            }
            // purchases BuyLeadTicks before the recorded one: the player had the weapon in hand a tick before
            // item_purchase came, and CS2-Bot-Controller picks up the recorded weapon only in the tick it changed
            // (a weapon given later stayed in the bag: the bot shot the whole movement with its pistol)
            if (r.NextBuy < r.Buys.Count)
            {
                var at = _bc.ReplayCursor(slot) + BuyLeadTicks;
                while (r.NextBuy < r.Buys.Count && r.Buys[r.NextBuy].Tick <= at) Buy(r.Bot, r.Buys[r.NextBuy++].Item);
            }
            KeepWeapon(r, slot);
        }
    }

    // a given weapon reaches the inventory a tick later; the recorded switch must find it there
    const int BuyLeadTicks = 6;
    // a switch later than the recording's delays every shot of that weapon by as much (it is being drawn)
    const int WrongWeaponTicks = 1, SelectTries = 128;

    // The replay selects the recorded weapon itself in the tick the recording changed it, but a weapon bought
    // during the replay stayed in the bag (the bot shot the whole movement with its pistol), and
    // SwitchBotWeapon and a "use" command are refused while replaying. A bot still holding another weapon a
    // few ticks later gets it through the game's own CCSPlayer_WeaponServices::SelectItem, the function
    // CS2-Bot-Controller switches with (signature from its gamedata.json, kept up to date with CS2).
    void KeepWeapon(Replay r, int slot)
    {
        if (!_bc!.TryGetReplayTick(slot, out var tick) || tick.WeaponDefIndex <= 0 || _bc.BotActiveWeaponDef(slot) == tick.WeaponDefIndex)
        {
            r.WrongWeapon = 0;
            return;
        }
        if (++r.WrongWeapon < WrongWeaponTicks) return;
        // a bought weapon reaches the bot's inventory some ticks after it was given: looked for every tick
        var ws = r.Bot!.PlayerPawn.Value?.WeaponServices;
        var weapon = ws?.MyWeapons.Select(h => h.Value)
            .FirstOrDefault(w => w is { IsValid: true } && w.AttributeManager.Item.ItemDefinitionIndex == tick.WeaponDefIndex);
        if (ws == null || r.WrongWeapon > WrongWeaponTicks + SelectTries) return;
        // the recording holds a gun the bot never got: a purchase without item_purchase or a weapon picked up
        // from the ground. Given once, as a purchase; the next ticks select it
        if (weapon == null)
        {
            if (r.WrongWeapon == WrongWeaponTicks && GunName(tick.WeaponDefIndex) is { } name) Buy(r.Bot, name);
            return;
        }
        SelectItem(ws, weapon);
    }

    // item definition index -> gun (CsItem does not follow the indexes: its 9 is the bump mine)
    static readonly Dictionary<int, string> Guns = new()
    {
        [1] = "deagle", [2] = "elite", [3] = "fiveseven", [4] = "glock", [7] = "ak47", [8] = "aug", [9] = "awp",
        [10] = "famas", [11] = "g3sg1", [13] = "galilar", [14] = "m249", [16] = "m4a1", [17] = "mac10", [19] = "p90",
        [23] = "mp5sd", [24] = "ump45", [25] = "xm1014", [26] = "bizon", [27] = "mag7", [28] = "negev", [29] = "sawedoff",
        [30] = "tec9", [32] = "hkp2000", [33] = "mp7", [34] = "mp9", [35] = "nova", [36] = "p250", [38] = "scar20",
        [39] = "sg556", [40] = "ssg08", [60] = "m4a1_silencer", [61] = "usp_silencer", [63] = "cz75a", [64] = "revolver",
    };

    static string? GunName(int def) => Guns.TryGetValue(def, out var n) ? "weapon_" + n : null;

    // the purchases plus a purchase for every gun the recording takes in hand without having it (bought
    // without item_purchase, picked up), so it is given BuyLeadTicks early like a purchase
    static List<(int Tick, string Item)> WithMissingGuns(Recording rec)
    {
        var have = rec.Weapons.ToHashSet();
        var buys = rec.Buys.ToList();
        for (int i = 0, next = 0, last = -1; i < rec.Ticks.Length; i++)
        {
            for (; next < rec.Buys.Count && rec.Buys[next].Tick <= i; next++) have.Add(rec.Buys[next].Item);
            var def = rec.Ticks[i].WeaponDefIndex;
            if (def == last) continue;
            last = def;
            if (GunName(def) is { } name && have.Add(name)) buys.Add((i, name));
        }
        return buys.OrderBy(b => b.Tick).ToList();
    }

    static MemoryFunctionVoid<nint, nint, int>? _selectItem;
    static bool _selectItemFailed;

    void SelectItem(CPlayer_WeaponServices ws, CBasePlayerWeapon weapon)
    {
        if (_selectItemFailed) return;
        try
        {
            _selectItem ??= new MemoryFunctionVoid<nint, nint, int>(SelectItemSignature());
            _selectItem.Invoke(ws.Handle, weapon.Handle, 0);
        }
        catch (Exception e)
        {
            _selectItemFailed = true;   // once: a wrong signature after a CS2 update must not repeat every tick
            Logger.LogError("weapon switch during replay unavailable: {Error}", e.Message);
        }
    }

    // "CCSPlayer_WeaponServices::SelectItem" from addons/BotController/gamedata.json
    static string SelectItemSignature()
    {
        var gamedata = Path.Combine(Server.GameDirectory, "csgo", "addons", "BotController", "gamedata.json");
        using var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(gamedata));
        return doc.RootElement.GetProperty("CCSPlayer_WeaponServices::SelectItem").GetProperty("signatures").GetProperty("windows").GetString()!;
    }

    // ---------------- purchases ----------------
    // Recorded from item_purchase while the player records; on replay the bot gets the item at the same
    // tick. A rifle or pistol replaces the one in its slot, as buying does (the old one is removed, not dropped).
    static readonly HashSet<string> Pistols = new()
    {
        "weapon_glock", "weapon_hkp2000", "weapon_usp_silencer", "weapon_p250", "weapon_fiveseven", "weapon_tec9",
        "weapon_cz75a", "weapon_deagle", "weapon_elite", "weapon_revolver",
    };

    static bool Primary(string w) => w.StartsWith("weapon_") && !Pistols.Contains(w) && !w.Contains("knife") && !w.Contains("bayonet")
        && w is not ("weapon_taser" or "weapon_c4" or "weapon_hegrenade" or "weapon_flashbang" or "weapon_smokegrenade"
            or "weapon_molotov" or "weapon_incgrenade" or "weapon_decoy");

    int _recStartTick;
    List<(int Tick, string Item)>? _recBuys;

    [GameEventHandler]
    public HookResult OnPurchase(EventItemPurchase ev, GameEventInfo info)
    {
        if (_recName == null || _recBuys == null || ev.Userid != _recPlayer) return HookResult.Continue;
        var item = ev.Weapon.StartsWith("weapon_") || ev.Weapon.StartsWith("item_") ? ev.Weapon : "weapon_" + ev.Weapon;
        _recBuys.Add((Server.TickCount - _recStartTick, item));
        Server.PrintToConsole($"[FM] recorded purchase '{ev.Weapon}' -> {item} at tick {_recBuys[^1].Tick}");
        return HookResult.Continue;
    }

    // fm_impacts 1: where every bullet lands, with the shooter's replay tick (checks that a replay spreads like the recording)
    bool _impacts;

    [ConsoleCommand("fm_impacts", "fm_impacts <0|1> - print where bullets land (debug)")]
    public void CmdImpacts(CCSPlayerController? caller, CommandInfo cmd) => _impacts = cmd.ArgByIndex(1) != "0";

    [GameEventHandler]
    public HookResult OnImpact(EventBulletImpact ev, GameEventInfo info)
    {
        if (!_impacts || ev.Userid is not { IsValid: true } p) return HookResult.Continue;
        var tick = _recName != null && p == _recPlayer ? Server.TickCount - _recStartTick : _bc?.IsReplaying(p.Slot) == true ? _bc.ReplayCursor(p.Slot) : -1;
        Server.PrintToConsole($"[FM] impact {p.PlayerName} tick={tick} at {ev.X:0.0} {ev.Y:0.0} {ev.Z:0.0}");
        return HookResult.Continue;
    }

    void Buy(CCSPlayerController bot, string item)
    {
        if (bot.PlayerPawn.Value?.WeaponServices is not { } ws) return;
        bool Same(string held) => Primary(item) ? Primary(held) : Pistols.Contains(item) && Pistols.Contains(held);
        // removed at once: RemoveItemByDesignerName took 7 ticks, and meanwhile the new weapon lay on the
        // ground (hanging in the air in front of the bot, "[F] swap to AWP" for the player near it) until the
        // slot was free
        foreach (var held in ws.MyWeapons.Select(h => h.Value).Where(w => w is { IsValid: true } && Same(w.DesignerName)).ToList())
            held!.Remove();
        var given = bot.GiveNamedItem(item);
        if (given == 0) return;
        // it still reaches the inventory a tick later: invisible until it is in the bot's weapons
        var weapon = new CBasePlayerWeapon(given);
        weapon.RenderMode = RenderMode_t.kRenderTransAlpha;
        weapon.Render = System.Drawing.Color.FromArgb(0, weapon.Render);
        Utilities.SetStateChanged(weapon, "CBaseModelEntity", "m_nRenderMode");
        Utilities.SetStateChanged(weapon, "CBaseModelEntity", "m_clrRender");
        _hiddenGiven.Add(new HiddenGiven(bot, weapon, Server.TickCount));
    }

    class HiddenGiven(CCSPlayerController bot, CBasePlayerWeapon weapon, int tick)
    {
        public CCSPlayerController Bot = bot;
        public CBasePlayerWeapon Weapon = weapon;
        public int Tick = tick, Owned = -1;
    }

    readonly List<HiddenGiven> _hiddenGiven = new();
    // shown some ticks after it reached the bot: right away it still flashed for a frame where it was made
    const int HiddenGivenMaxTicks = 32, ShowGivenAfterTicks = 3;

    void ShowGiven()
    {
        _hiddenGiven.RemoveAll(h =>
        {
            if (!h.Weapon.IsValid) return true;
            if (h.Owned < 0 && h.Bot.IsValid && h.Bot.PlayerPawn.Value?.WeaponServices?.MyWeapons.Any(w => w.Value?.Handle == h.Weapon.Handle) == true)
                h.Owned = Server.TickCount;
            var ready = h.Owned >= 0 && Server.TickCount - h.Owned >= ShowGivenAfterTicks;
            if (!ready && Server.TickCount - h.Tick < HiddenGivenMaxTicks) return false;
            h.Weapon.RenderMode = RenderMode_t.kRenderNormal;
            h.Weapon.Render = System.Drawing.Color.FromArgb(255, h.Weapon.Render);
            Utilities.SetStateChanged(h.Weapon, "CBaseModelEntity", "m_nRenderMode");
            Utilities.SetStateChanged(h.Weapon, "CBaseModelEntity", "m_clrRender");
            return true;
        });
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
        _recStartTick = Server.TickCount;
        _recBuys = new();
        _api?.RaiseRecording(name, true);
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
            Buys = _recBuys ?? new(), History = _bc.GetRecordedInputHistory(slot),
        };
        rec.Save(PathOf(_recName));
        var msg = $"saved '{_recName}': {rec.Seconds:0.0} s" + (rec.Buys.Count > 0 ? $", {rec.Buys.Count} purchase(s)" : "");
        _recBuys = null;
        _api?.RaiseRecording(_recName, false);
        _recName = null;
        return msg;
    }

    // adds a bot of the team; the result arrives later through report
    void Assign(string name, string team, Action<string> report)
    {
        if (!File.Exists(PathOf(name))) { report($"no recording '{name}'"); return; }
        var rec = Recording.Load(PathOf(name));
        var before = FakeDemoPlayers.All().Where(p => p.IsBot).Select(p => p.Slot).ToHashSet();
        // bot_add raises bot_quota by 2 in CS2 (see fd_actions.cfg), lower it back by 1
        Server.ExecuteCommand($"bot_add_{team}; incrementvar bot_quota 0 64 -1");
        AddTimer(0.5f, () =>
        {
            var bot = FakeDemoPlayers.All().FirstOrDefault(p => p.IsBot && !p.IsHLTV && !before.Contains(p.Slot));
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

    // ---------------- playing: once or in a loop ----------------
    // A setting of the start, not of a movement: in a loop every bot starts again together, after the
    // longest movement (with its timing offset) has ended and LoopPause has passed. Takes and recording
    // over the bots always run once (Go). Kept in Documents\FakeDemo\bots.txt.
    const float LoopPause = 1f;
    bool _loop;
    int _loopGen;        // a newer start / stop cancels the pending restart
    bool _looping;       // between two passes the bots stand, but playing is still on
    bool _starting;      // Go was called, the replays start after StartDelay

    string BotsPrefsPath => Path.Combine(FakeDemoPaths.Root, "bots.txt");

    void LoadBotsPrefs()
    {
        try { _loop = File.ReadAllText(BotsPrefsPath).Trim() == "loop"; }
        catch (Exception) { /* no file: once */ }
    }

    void SetLoop(bool loop)
    {
        _loop = loop;
        Directory.CreateDirectory(FakeDemoPaths.Root);
        File.WriteAllText(BotsPrefsPath, loop ? "loop" : "once");
    }

    string Play(Action? onStarted = null)
    {
        var msg = Go(onStarted);
        if (!_loop || _replays.Count == 0) return msg;
        var gen = _loopGen;
        _looping = true;
        var seconds = _replays.Max(r => (Math.Max(0, r.Edits.OffsetTicks) + Prepare(r.Rec, r.Edits).Ticks.Length) / (float)TicksPerSecond);
        AddTimer(StartDelay + seconds + LoopPause, () =>
        {
            if (gen != _loopGen || !_loop) return;
            var p = LocalHuman();
            Play(p == null ? null : () => Reshow(p, "FakeMimic", MainMenu));
        });
        return msg + $", in a loop every {seconds + LoopPause:0.0} s";
    }

    // a take's set of bots again, in a loop (Takes > Preview): the same assignments only start; otherwise
    // the bots are replaced, one assignment after the other (two at once land on the same new bot)
    string PlaySetup(string folder, IReadOnlyList<TakeBot> bots, Action? started)
    {
        if (_bc == null) return "CS2-Bot-Controller is not installed";
        if (folder != _category) SetFolder(folder);
        static string Key(IEnumerable<(string Name, int Team)> set) => string.Join("|", set.Select(x => $"{x.Name}:{x.Team}").Order());
        var now = Key(_replays.Where(r => r.Bot is { IsValid: true }).Select(r => (r.Name, (int)r.Bot!.TeamNum)));
        _loop = true;   // for this run only: the saved Bots play mode stays
        if (now == Key(bots.Select(b => (b.Recording, b.Team)))) return Play(started);

        Halt();
        _replays.Clear();
        Server.ExecuteCommand("fd_botkick");
        var gen = ++_loopGen;
        void Next(int i)
        {
            if (gen != _loopGen) return;   // stopped or started otherwise meanwhile
            if (i == bots.Count) { Play(started); return; }
            Assign(bots[i].Recording, bots[i].Team == 3 ? "ct" : "t", _ => AddTimer(0.3f, () => Next(i + 1)));
        }
        AddTimer(0.5f, () => Next(0));
        return $"setting up {bots.Count} bot(s) of this demo, then they play it in a loop";
    }

    string Go(Action? onStarted = null)
    {
        if (_bc == null) return "CS2-Bot-Controller is not installed";
        _loopGen++;
        _looping = false;
        _starting = true;
        _replays.RemoveAll(r => r.Bot is not { IsValid: true });
        ClearPaths();
        ClearMap();   // the map as it was before the last run
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
            _starting = false;
            foreach (var r in replays)
            {
                var bot = r.Bot!;
                var pawn = bot.PlayerPawn.Value;
                if (bot is not { IsValid: true } || pawn == null) continue;
                r.WrongWeapon = 0;
                var rec = Prepare(r.Rec, r.Edits);
                (r.Buys, r.NextBuy, r.Ended, r.Length) = (WithMissingGuns(rec), 0, false, rec.Ticks.Length);
                // without the history if this CS2-Bot-Controller does not take it (another build than the recording's)
                if (!_bc.SetReplayPawn(bot.Slot, pawn.Handle))
                {
                    Server.PrintToConsole($"[FM] replay '{r.Name}' did not load on {bot.PlayerName}");
                    continue;
                }
                var withHistory = rec.History.Length > 0 && _bc.LoadReplay(bot.Slot, rec.Ticks, rec.Subs, rec.Commands, rec.History);
                if (!withHistory && !_bc.LoadReplay(bot.Slot, rec.Ticks, rec.Subs, rec.Commands))
                {
                    Server.PrintToConsole($"[FM] replay '{r.Name}' did not load on {bot.PlayerName}");
                    continue;
                }
                if (rec.History.Length > 0 && !withHistory) Server.PrintToConsole($"[FM] '{r.Name}': input history not taken");
                // the weapons were given a moment ago and are still being drawn: a shot in the first second was lost
                foreach (var h in pawn.WeaponServices?.MyWeapons.ToList() ?? new())
                {
                    if (h.Value is not { IsValid: true } w) continue;
                    w.NextPrimaryAttackTick = Server.TickCount;
                    w.NextSecondaryAttackTick = Server.TickCount;
                    Utilities.SetStateChanged(w, "CBasePlayerWeapon", "m_nNextPrimaryAttackTick");
                    Utilities.SetStateChanged(w, "CBasePlayerWeapon", "m_nNextSecondaryAttackTick");
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
        _loopGen++;
        _looping = false;
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
        _loopGen++;
        _looping = false;
        // their bots go too
        var bots = _replays.Where(r => r.Bot is { IsValid: true }).Select(r => r.Bot!).ToList();
        Kick(bots);
        _replays.Clear();
        return bots.Count > 0 ? $"assignments cleared, {bots.Count} bot(s) removed" : "assignments cleared";
    }

    string Delete(string name)
    {
        if (!File.Exists(PathOf(name))) return $"no recording '{name}'";
        File.Delete(PathOf(name));
        File.Delete(EditsPathOf(name));
        // the bot that played it goes too
        var bots = _replays.Where(r => r.Name == name && r.Bot is { IsValid: true }).Select(r => r.Bot!).ToList();
        _replays.RemoveAll(r => r.Name == name);
        Kick(bots);
        return $"deleted '{name}'" + (bots.Count > 0 ? " and its bot" : "");
    }

    // bot_kick "<name>" skipped some bots without a word, and kickid lowers bot_quota only sometimes (the
    // game then adds a new bot in the kicked one's place): kickid, then the quota set to the bots that stay
    void Kick(List<CCSPlayerController> bots)
    {
        if (bots.Count == 0) return;
        foreach (var b in bots) _bc?.StopReplay(b.Slot);
        var kicked = bots.Select(b => b.Slot).ToHashSet();
        var stay = FakeDemoPlayers.All().Count(p => p is { IsValid: true, IsBot: true, IsHLTV: false } && !kicked.Contains(p.Slot));
        Server.ExecuteCommand(string.Join("; ", bots.Select(b => $"kickid {b.UserId}")) + $"; bot_quota {stay}");
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

    // Accent: salmon row (stop, delete); the rest as in ApiMenuItem
    record MenuItem(string Text, Action<CCSPlayerController> Pick, bool Accent = false)
    {
        public ApiRowKind Kind { get; init; }
        public bool Nested { get; init; }
        public bool Divider { get; init; }
        public bool On { get; init; }
        public string? Value { get; init; }
        public IReadOnlyList<string>? Options { get; init; }
        public IReadOnlyList<(int A, int B)>? Swatches { get; init; }
        public IReadOnlyList<ApiCard>? Cards { get; init; }
        public ApiTone Tone { get; init; }
        public bool Faded { get; init; }
        public int Selected { get; init; }
        public Action<CCSPlayerController, int>? Choose { get; init; }
        public int Count => Kind switch
        {
            ApiRowKind.Choice or ApiRowKind.Stars => Options?.Count ?? 0,
            ApiRowKind.Colors => Swatches?.Count ?? 0,
            ApiRowKind.Cards => Cards?.Count ?? 0,
            _ => 0,
        };
    }
    // Close (9) on the main menu, "← Back" when Back is set
    record Menu(string Title, List<MenuItem> Items, bool Main = false, Action<CCSPlayerController>? Back = null);

    const int RowOptions = 5;   // segments (stars) per row in the layout
    const int RowSwatches = 4;  // colour swatches per row
    const int RowCards = 4;     // portrait cards per row

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
        foreach (var k in _applied.Keys.ToList())
        {
            if (k[0] is 'w' or 'c') _applied.Remove(k);   // swatch colours, portraits: none in a new layout
            else _applied[k] = k switch { "posx" => "X100", "posy" => "Y100", "poss" => "S0", _ => "V0" };
        }
        _cls.Clear();
        var kv = new CEntityKeyValues();
        kv.SetString("layout", HudLayout);
        _hud.DispatchSpawn(kv);
        return _hud;
    }

    static string Plain(string text) => System.Text.RegularExpressions.Regex.Replace(text, "<[^>]+>", "");

    void Show(CCSPlayerController p, Menu m)
    {
        // the same screen shown again from one of its rows (a switch flipped): no entrance
        var update = _picking != null && _picking == m.Title && !_settingsOpen;
        _menu = m;
        SetDigits(true);
        var hud = Hud();
        if (hud == null) { Say(p, "custom HUD could not be created"); return; }
        hud.SetDialogVariableString("menu", "title", Plain(m.Title));
        for (var i = 1; i <= 9; i++)
        {
            var item = i < 9 && i <= m.Items.Count ? m.Items[i - 1] : null;
            // digits are drawn as key hints by the layout, so the text has no number
            var text = i == 9 ? (m.Main ? "Close" : m.Back != null ? "← Back" : "") : item != null ? Plain(item.Text) : "";
            hud.SetDialogVariableString("menu", $"t{i}", text);
            Cls(hud, $"b{i}", "Empty", text.Length == 0);
            Cls(hud, $"b{i}", "Accent", item?.Accent == true);
            if (i == 9) continue;
            var kind = item?.Kind ?? ApiRowKind.Button;
            Cls(hud, $"r{i}", "Tog", kind is ApiRowKind.Toggle or ApiRowKind.BigToggle);
            Cls(hud, $"r{i}", "Big", kind is ApiRowKind.BigToggle or ApiRowKind.Primary);
            Cls(hud, $"r{i}", "Prim", kind == ApiRowKind.Primary);
            Cls(hud, $"r{i}", "On", item?.On == true);
            Cls(hud, $"r{i}", "Seg", kind is ApiRowKind.Choice or ApiRowKind.Stars);
            Cls(hud, $"r{i}", "Stars", kind == ApiRowKind.Stars);
            Cls(hud, $"r{i}", "Pal", kind == ApiRowKind.Colors);
            Cls(hud, $"r{i}", "Crd", kind == ApiRowKind.Cards);
            Cls(hud, $"r{i}", "Info", kind == ApiRowKind.Info);
            Cls(hud, $"r{i}", "Faded", item?.Faded == true);
            foreach (var tone in new[] { ApiTone.Good, ApiTone.Ok, ApiTone.Bad, ApiTone.Gold })
                Cls(hud, $"r{i}", $"T{tone}", item?.Tone == tone);
            for (var k = 0; k < RowCards; k++)
            {
                var card = kind == ApiRowKind.Cards && item!.Cards != null && k < item.Cards.Count ? item.Cards[k] : null;
                Cls(hud, $"c{i}_{k}", "Empty", card == null);
                if (card == null) continue;
                Cls(hud, $"c{i}_{k}", "Sel", item!.Selected == k);
                Cls(hud, $"c{i}_{k}", "CT", card.Team == 3);
                hud.SetDialogVariableString("menu", $"cn{i}_{k}", card.Title);
                hud.SetDialogVariableString("menu", $"cs{i}_{k}", card.Subtitle);
                SetOnly(hud, $"c{i}_{k}p", "P_" + Portrait(card.Model, card.Team));
            }
            bool NestedAt(int n) => n >= 1 && n <= Math.Min(8, m.Items.Count) && m.Items[n - 1].Nested;
            var nested = NestedAt(i);
            Cls(hud, $"r{i}", "Sub", nested);
            Cls(hud, $"r{i}", "SubFirst", nested && !NestedAt(i - 1));
            Cls(hud, $"r{i}", "SubLast", nested && !NestedAt(i + 1));
            Cls(hud, $"r{i}", "Divider", item?.Divider == true);
            hud.SetDialogVariableString("menu", $"val{i}", item?.Value ?? "");
            Cls(hud, $"r{i}", "HasVal", !string.IsNullOrEmpty(item?.Value));
            for (var k = 0; k < RowOptions; k++)
            {
                var used = item != null && k < item.Count;
                var segs = kind is ApiRowKind.Choice or ApiRowKind.Stars;
                if (segs) hud.SetDialogVariableString("menu", $"o{i}_{k}", used ? item!.Options![k] : "");
                Cls(hud, $"o{i}_{k}", "Empty", !used || !segs);
                Cls(hud, $"o{i}_{k}", "Sel", used && kind == ApiRowKind.Choice && item!.Selected == k);
                Cls(hud, $"o{i}_{k}", "Lit", used && kind == ApiRowKind.Stars && k <= item!.Selected);
                if (k >= RowSwatches) continue;
                Cls(hud, $"w{i}_{k}", "Empty", !used || kind != ApiRowKind.Colors);
                Cls(hud, $"w{i}_{k}", "Sel", used && item!.Selected == k);
                if (used && kind == ApiRowKind.Colors)
                {
                    SetOnly(hud, $"w{i}_{k}a", $"C{item!.Swatches![k].A}");
                    SetOnly(hud, $"w{i}_{k}b", $"C{item.Swatches[k].B}");
                }
            }
        }
        ApplyMenuPrefs(hud);
        if (!update) Swap(hud);   // replay the rows' entrance: opening and switching look the same
        _settingsOpen = false;
        hud.SetHasClass("menu", "Settings", false);
        _inOverlay = Overlay;
        hud.SetHasClass("menu", "Hidden", _inOverlay);
        StartCapture(p);   // with the overlay too: the game frees the cursor
        if (_inOverlay) Emit(m);
    }

    // ---------------- overlay ----------------
    // The menu is drawn by FakeDemoOverlay.exe, a window over the game that the launcher starts, instead of
    // the HUD. Each screen goes to the console as JSON in chunks ("FMUI+ part" ... "FMUI. last part"), which
    // the overlay reads over netcon; its clicks come back as the same fm_click / fm_k commands.
    // The overlay sends fm_overlay 1 every few seconds; without it for OverlayTimeout the menu goes back
    // into the HUD (the window was closed or crashed: an open menu would have been invisible).
    bool _overlayWanted, _inOverlay;
    long _overlaySeen = -1;
    const int OverlayTimeoutMs = 10000;
    const int ChunkLength = 400;

    bool Overlay => _overlayWanted && _overlaySeen >= 0 && Environment.TickCount64 - _overlaySeen < OverlayTimeoutMs;

    // every tick: an open menu shown in a window that stopped answering comes back in the HUD
    void CheckOverlay()
    {
        if (!_inOverlay || Overlay) return;
        _inOverlay = false;
        if (_menu != null && LocalHuman() is { } p) Show(p, _menu);
    }

    void Emit(Menu m)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(new
        {
            title = Plain(m.Title),
            close = m.Main ? "Close" : m.Back != null ? "← Back" : "",
            x = _menuX, y = _menuY, s = _menuS,
            rows = m.Items.Take(8).Select(i => new
            {
                t = Plain(i.Text), kind = i.Kind.ToString(), accent = i.Accent, on = i.On, val = i.Value,
                opts = i.Options, sel = i.Selected, sub = i.Nested, div = i.Divider, faded = i.Faded, tone = i.Tone.ToString(),
                sw = i.Swatches?.Select(w => new[] { w.A, w.B }),
                cards = i.Cards?.Take(RowCards).Select(c => new { t = c.Title, s = c.Subtitle, p = Portrait(c.Model, c.Team), ct = c.Team == 3 }),
            }),
        });
        EmitRaw(json);
    }

    static void EmitRaw(string json)
    {
        for (var i = 0; i < json.Length; i += ChunkLength)
            Server.PrintToConsole((i + ChunkLength >= json.Length ? "FMUI. " : "FMUI+ ") + json.Substring(i, Math.Min(ChunkLength, json.Length - i)));
    }

    [ConsoleCommand("fm_overlay", "fm_overlay <0|1> - draw the menu in the overlay window instead of the HUD")]
    public void CmdOverlay(CCSPlayerController? caller, CommandInfo cmd)
    {
        var was = Overlay;
        _overlayWanted = cmd.ArgByIndex(1) != "0";
        _overlaySeen = Environment.TickCount64;
        if (Overlay == was) return;   // the overlay's regular hello: nothing changes
        cmd.ReplyToCommand($"[FM] overlay {(Overlay ? "on" : "off")}");
        var p = caller ?? LocalHuman();
        if (_menu != null && p != null) Show(p, _menu);
    }

    [ConsoleCommand("fm_menupos", "fm_menupos <x> <y> - menu position, 0..200 each (100 = crosshair)")]
    public void CmdMenuPos(CCSPlayerController? caller, CommandInfo cmd)
    {
        if (!int.TryParse(cmd.ArgByIndex(1), out var x) || !int.TryParse(cmd.ArgByIndex(2), out var y)) return;
        (_menuX, _menuY) = (Math.Clamp(x, 0, PosSteps), Math.Clamp(y, 0, PosSteps));
        SaveMenuPrefs();
        if (_hud is { IsValid: true }) ApplyMenuPrefs(_hud);
    }

    [ConsoleCommand("fm_menusize", "fm_menusize <0..40> - menu size (0 = compact)")]
    public void CmdMenuSize(CCSPlayerController? caller, CommandInfo cmd)
    {
        if (!int.TryParse(cmd.ArgByIndex(1), out var s)) return;
        _menuS = Math.Clamp(s, MinOverlaySize, SliderSteps);
        SaveMenuPrefs();
        if (_hud is { IsValid: true }) ApplyMenuPrefs(_hud);
    }

    // portrait class of a model: agents/models/tm_leet/tm_leet_varianta.vmdl -> tm_leet_varianta (fm_menu.css
    // has P_<name> for every agent with a portrait in the game), the team's default without a model
    // a model without a portrait (or none known) takes the first agent of its faction, then of its team
    const string DefaultPortrait = "default";   // the game's "map-based agent" picture, for the Default choice

    string Portrait(string model, int team)
    {
        if (model == DefaultPortrait) return team == 3 ? "ct_map_based" : "t_map_based";
        var name = string.IsNullOrEmpty(model) ? "" : Path.GetFileNameWithoutExtension(model);
        var names = _models.Select(Path.GetFileNameWithoutExtension).OfType<string>().Where(n => n != "tm_leet_variantk").ToList();
        if (names.Contains(name)) return name;
        var faction = name.Length > 0 ? names.FirstOrDefault(n => n.StartsWith(name.Split("_variant")[0])) : null;
        return faction ?? names.FirstOrDefault(n => n.StartsWith(team == 3 ? "ctm_" : "tm_")) ?? (team == 3 ? "ct_map_based" : "t_map_based");
    }

    // classes on the layout as last sent: a screen update sends only what changed
    readonly Dictionary<(string, string), bool> _cls = new();

    void Cls(CCSCustomHudLayout hud, string panel, string cls, bool on)
    {
        if (_cls.TryGetValue((panel, cls), out var was) && was == on) return;
        hud.SetHasClass(panel, cls, on);
        _cls[(panel, cls)] = on;
    }

    // The layout replays the rows' entrance (keyframes) whenever the class on #menu switches between
    // SwapA and SwapB, in the same tick as the new texts: on every opening and every screen change.
    void Swap(CCSCustomHudLayout hud)
    {
        _swapB = !_swapB;
        hud.SetHasClass("menu", "SwapA", !_swapB);
        hud.SetHasClass("menu", "SwapB", _swapB);
    }

    // A mouse still moving when H was pressed turned the view by 1-11° when the menu closed (or later): the
    // game holds back the movement that was under way when the cursor was freed and applies it when the
    // mouse comes back. The menu shows at once, but the cursor is freed only when the view stopped turning
    // (the mouse is still), at most CaptureWaitMs later; until then the mouse still turns the view.
    // Real milliseconds, not ticks: in slow motion 20 ticks were over a second
    CCSPlayerController? _captureFor;
    QAngle? _captureView;
    long _captureSince, _stillSince;
    const int CaptureWaitMs = 120, CaptureStillMs = 25;
    const float StillDegrees = 0.01f;

    void StartCapture(CCSPlayerController p)
    {
        if (_captureFor != null) return;   // already waiting; the menu was only redrawn
        if (_capturing) { _hud?.SetInputCaptureEnabled(p, true); return; }
        (_captureFor, _captureView, _captureSince, _stillSince) = (p, null, Environment.TickCount64, -1);
    }

    bool _capturing;

    void WaitCapture()
    {
        if (_captureFor is not { } p) return;
        if (!p.IsValid || _menu == null || _hud is not { IsValid: true } hud) { _captureFor = null; return; }
        var v = p.PlayerPawn.Value?.V_angle;
        var still = v != null && _captureView != null
            && Math.Abs(v.X - _captureView.X) < StillDegrees && Math.Abs(v.Y - _captureView.Y) < StillDegrees;
        var now = Environment.TickCount64;
        if (!still) _stillSince = -1;
        else if (_stillSince < 0) _stillSince = now;
        if (v != null) _captureView = new QAngle(v.X, v.Y, v.Z);
        if ((_stillSince < 0 || now - _stillSince < CaptureStillMs) && now - _captureSince < CaptureWaitMs) return;
        hud.SetInputCaptureEnabled(p, true);
        _capturing = true;
        _captureFor = null;
    }

    void CloseMenu(CCSPlayerController p)
    {
        _captureFor = null;
        _capturing = false;
        _menu = null;
        if (_grid != 0) SetGrid(0);
        SetDigits(false);
        var overlay = _inOverlay;
        if (overlay) EmitRaw("{\"closed\":true}");
        _inOverlay = false;
        if (_hud is not { IsValid: true }) return;
        _hud.SetHasClass("menu", "Hidden", true);
        if (!overlay) { _hud.SetInputCaptureEnabled(p, false); return; }
        // the overlay puts the cursor in the middle of the game first (after an alt-tab it was elsewhere,
        // and the game turned the view by the distance when it took the mouse back)
        Task.Delay(OverlayCenterMs).ContinueWith(_ => Server.NextFrame(() =>
        {
            if (_menu == null && p.IsValid && _hud is { IsValid: true } hud) hud.SetInputCaptureEnabled(p, false);
        }));
    }

    const int OverlayCenterMs = 40;

    // Layout development: a changed vxml_c / vcss_c is never read again while the game runs (not on a
    // map load, not with resource_repeated_reload), so each build gets a new file name
    // (tools\build_hud.ps1 -Name fm_menuN -Live) and this points the plugin at it for the next map load.
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
            case "bm": SetGrid(_grid == 1 ? 0 : 1); return;     // move: the grid of cells over the screen
            case "bz": SetGrid(_grid == 2 ? 0 : 2); return;     // size
        }
        // grid cells g<col>_<row>
        if (buttonId.Length >= 4 && buttonId[0] == 'g' && buttonId.IndexOf('_') is > 1 and var u
            && int.TryParse(buttonId[1..u], out var col) && int.TryParse(buttonId[(u + 1)..], out var row))
        {
            GridClick(col, row);
            return;
        }
        // slider segments: sx0..sx40, sy0..sy40, ss0..ss40 (a position step is 1/5 of a slider step)
        if (buttonId.Length >= 3 && buttonId[0] == 's' && int.TryParse(buttonId[2..], out var v))
        {
            switch (buttonId[1])
            {
                case 'x': _menuX = v * PosPerSlider; break;
                case 'y': _menuY = v * PosPerSlider; break;
                case 's': _menuS = v; break;
                default: return;
            }
            SaveMenuPrefs();
            ApplyMenuPrefs(_hud);
            return;
        }
        // segments o<row>_<n>, swatches w<row>_<n>
        if (buttonId.Length == 4 && buttonId[0] is 'o' or 'w' or 'c' && buttonId[2] == '_')
        {
            Choose(player, buttonId[1] - '0', buttonId[3] - '0');
            return;
        }
        // menu rows are b1..b9; the heading of a choice is not a button (its digit still picks the next one)
        if (buttonId.Length == 2 && buttonId[0] == 'b')
        {
            var n = buttonId[1] - '0';
            if (_menu != null && n >= 1 && n <= Math.Min(8, _menu.Items.Count)
                && (_menu.Items[n - 1].Count > 0 || _menu.Items[n - 1].Kind == ApiRowKind.Info)) return;
            Pick(player, n);
        }
    }

    // ---------------- window position / size (Settings screen, remembered between sessions) ----------------
    // The HUD reports clicks only (no drag, no scripts), so each slider is a bar + knob with SliderSteps+1
    // invisible buttons over it (sx0..sx40 ...): a click jumps the knob there. The CSS has a class
    // per step: X0..X200 / Y0..Y200 move wrapper panels (0.5% of the screen each, 100 = crosshair),
    // S0..S40 scale, V0..V40 on the slider itself draws fill and knob. Move / Size in the header: StartDrag.

    const int SliderSteps = 40, PosSteps = 200, PosPerSlider = PosSteps / SliderSteps;
    const string PrefsVersion = "v3", PrefsVersion2 = "v2";
    int _menuX = 100, _menuY = 100, _menuS = 0;   // default: top-left corner on the crosshair, compact
    // the overlay goes smaller than the HUD (40% instead of 70%): below 0 the HUD stays at its smallest
    const int MinOverlaySize = -20;
    bool _settingsOpen;

    // classes currently on each panel, so only the changed ones are switched (the layout starts with these)
    readonly Dictionary<string, string> _applied = new()
    {
        ["posx"] = "X100", ["posy"] = "Y100", ["poss"] = "S0", ["slx"] = "V0", ["sly"] = "V0", ["sls"] = "V0",
    };

    string PrefsPath => Path.Combine(FakeDemoPaths.Root, "menu.txt");

    void LoadMenuPrefs()
    {
        try
        {
            var p = File.ReadAllText(PrefsPath).Split(' ');
            // v2 had 40 position steps; older 11-step files keep the defaults
            var k = p[0] == PrefsVersion ? 1 : p[0] == PrefsVersion2 ? PosPerSlider : 0;
            if (k == 0) return;
            int P(string s) => Math.Clamp(int.Parse(s) * k, 0, PosSteps);
            (_menuX, _menuY, _menuS) = (P(p[1]), P(p[2]), Math.Clamp(int.Parse(p[3]), MinOverlaySize, SliderSteps));
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
        foreach (var (key, value, wrapper, cls, per) in new[] { ('x', _menuX, "posx", "X", PosPerSlider), ('y', _menuY, "posy", "Y", PosPerSlider), ('s', Math.Max(0, _menuS), "poss", "S", 1) })
        {
            SetOnly(hud, wrapper, $"{cls}{value}");
            SetOnly(hud, $"sl{key}", $"V{(value + per / 2) / per}");
            hud.SetDialogVariableString("menu", $"v{key}", per == 1 ? $"{value * 2.5:0.#}%" : $"{value * 0.5:0.#}%");
        }
        SetOnly(hud, "grid", $"S{Math.Max(0, _menuS)}");   // the outline shown while moving has the menu's size
    }

    // ---------------- Move / Size by a click ----------------
    // The HUD reports clicks only, so Move / Size in the header show 20 x 20 invisible cells over the screen
    // (g<col>_<row>, 96 x 54 px = 10 position steps each): Move puts the menu's top-left corner on the
    // clicked cell, Size scales the menu so its right edge reaches it. The same header button again cancels.
    int _grid;   // 0 none, 1 moving, 2 sizing

    void SetGrid(int mode)
    {
        _grid = mode;
        if (_hud is not { IsValid: true }) return;
        _hud.SetHasClass("root", "Moving", mode == 1);
        _hud.SetHasClass("root", "Sizing", mode == 2);
        _hud.SetDialogVariableString("root", "gridhint", mode == 1 ? "Click where the menu's top-left corner goes  ·  the same button again cancels"
            : mode == 2 ? "Click where the menu's right edge goes  ·  the same button again cancels" : "");
    }

    void GridClick(int col, int row)
    {
        if (_hud is not { IsValid: true }) return;
        if (_grid == 1) (_menuX, _menuY) = (Math.Clamp(col * 10, 0, PosSteps), Math.Clamp(row * 10, 0, PosSteps));
        else if (_grid == 2)
        {
            // the right edge of the clicked cell becomes the menu's right edge (9.6 px a step, 460 px at scale 1)
            var width = (col + 1) * 96f - _menuX * 9.6f;
            _menuS = Math.Clamp((int)MathF.Round((width / 460f - 0.7f) / 0.015f), 0, SliderSteps);
        }
        SaveMenuPrefs();
        ApplyMenuPrefs(_hud);
        SetGrid(0);
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
        if (n == 9)
        {
            if (_menu.Main) CloseMenu(p);
            else if (_menu.Back != null) Run(p, _menu.Back);
            return;
        }
        if (n > _menu.Items.Count) return;
        var item = _menu.Items[n - 1];
        if (item.Kind == ApiRowKind.Info) return;
        if (item.Count > 0) Choose(p, n, (item.Selected + 1) % item.Count);   // a digit on a choice: the next one
        else Run(p, item.Pick);
    }

    void Choose(CCSPlayerController p, int n, int option)
    {
        if (_menu == null || n < 1 || n > _menu.Items.Count) return;
        var item = _menu.Items[n - 1];
        if (item.Choose == null || option < 0 || option >= item.Count) return;
        Run(p, pl => item.Choose(pl, option));
    }

    string? _picking;   // title of the screen whose row is being run

    // the action may open another screen (Show keeps the menu and replays the entrance) or the same one
    // again (updated in place); if it shows none (an action, a name asked in chat), the menu closes
    void Run(CCSPlayerController p, Action<CCSPlayerController> action)
    {
        _picking = _menu?.Title;
        _menu = null;
        _awaitText = null;   // a chat question belongs to the screen it was asked on
        try { action(p); }
        finally { _picking = null; }
        if (_menu == null) CloseMenu(p);
    }

    bool _awaitRaw;   // free text (a note), not a name

    void AskText(CCSPlayerController p, string prompt, Action<CCSPlayerController, string> then, bool raw = false)
    {
        _awaitText = then;
        _awaitRaw = raw;
        Say(p, prompt + " (type it in chat, empty = cancel)");
    }

    HookResult OnSay(CCSPlayerController? p, CommandInfo cmd)
    {
        if (_awaitText == null || p == null) return HookResult.Continue;
        // the whole line: "say a b" from the console arrives as two arguments, from the chat as one quoted
        var text = cmd.ArgString.Trim().Trim('"').Trim();
        var then = _awaitText;
        _awaitText = null;
        // names: only latin letters, digits, _ and - (also used as file and folder names)
        var clean = _awaitRaw ? text : new string(text.Where(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-').ToArray());
        if (clean.Length == 0) Say(p, "cancelled");
        else then(p, clean);
        return HookResult.Handled;   // the name does not appear in chat
    }

    // Folder on top (recent folders as segments), then one big button for what to do now (record, or stop
    // the recording / take that runs), the bots, the take, and the modules below a line
    void MainMenu(CCSPlayerController p)
    {
        var recent = RecentFolders();
        var many = recent.Count > ShownFolders;
        var shown = recent.Take(ShownFolders).ToList();
        var items = new List<MenuItem>
        {
            new("Folder", _ => { })
            {
                Kind = ApiRowKind.Choice, Options = shown.Append(many ? "All ›" : "+ New").ToList(), Selected = 0,
                Choose = (pl, i) =>
                {
                    if (i < shown.Count) { SetFolder(shown[i]); Say(pl, $"folder: {shown[i]}"); MainMenu(pl); }
                    else if (many) CategoriesMenu(pl);
                    else NewFolder(pl);
                },
            },
        };
        if (_take != null)
            items.Add(new($"Stop demo '{_take}'", pl => { Say(pl, StopTake()); MainMenu(pl); }, Accent: true) { Kind = ApiRowKind.Primary, Value = "REC" });
        else if (_recName != null)
            items.Add(new($"Stop and save '{_recName}'", pl => { Say(pl, StopRec()); MainMenu(pl); }, Accent: true) { Kind = ApiRowKind.Primary, Value = "REC" });
        else
            // with bots assigned they start in the same tick as the recording, so it lines up with them later
            items.Add(new("Record new movement", NewMovementMenu) { Kind = ApiRowKind.Primary });
        items.Add(new("Movements ›", RecordingsMenu) { Value = Names().Count().ToString() });

        // Off / Once / Loop: starting and how, in one row; the segment of what plays now is lit
        var assigned = _replays.Count(r => r.Bot is { IsValid: true });
        var playing = _replays.Any(r => r.Running) || _looping || _starting;
        items.Add(new("Bots play", _ => { })
        {
            Kind = ApiRowKind.Choice, Options = new[] { "Off", "Once", "Loop" }, Selected = !playing ? 0 : _loop ? 2 : 1,
            Value = $"{assigned} assigned", Divider = true,
            Choose = (pl, i) =>
            {
                if (i == 0) Say(pl, Halt());
                else if (assigned == 0) Say(pl, "no bots assigned: Movements › a movement › Play on T/CT bot");
                else
                {
                    SetLoop(i == 2);
                    // the bots start half a second later: the menu stays and shows it then
                    Say(pl, Play(() => Reshow(pl, "FakeMimic", MainMenu)));
                    _api?.RaiseBotsStarted();
                }
                MainMenu(pl);
            },
        });
        items.Add(new("Clear assignments", pl => { Say(pl, Clear()); MainMenu(pl); }));
        if (_take == null)
            items.Add(new("Record demo (bots play)", pl => Say(pl, StartTake())));
        else
            items.Add(new("Demo is recording", pl => { Say(pl, StopTake()); MainMenu(pl); }) { Value = "REC", On = true });

        // modules (FakeDirector, FakeWallhack, ...): one row each, each opens its own screen;
        // more than fit go behind one "Modules" row
        var free = 8 - items.Count;
        var modules = _addonItems.Count <= free ? _addonItems.Select(a => FromApi(a())).ToList() : new() { new("Modules ›", ModulesMenu) };
        if (modules.Count > 0) modules[0] = modules[0] with { Divider = true };
        items.AddRange(modules);
        Show(p, new Menu("FakeMimic", items, Main: true));
    }

    void ModulesMenu(CCSPlayerController p)
    {
        var items = _addonItems.Take(8).Select(a => FromApi(a())).ToList();
        Show(p, new Menu("Modules", items, Back: MainMenu));
    }

    // ---------------- folders ----------------
    // The main menu shows the current folder and the ones used before it (Documents\FakeDemo\recordings\<map>\recent.txt);
    // with more folders than fit, the last segment opens all of them.
    const int ShownFolders = 3;

    string RecentPath => Path.Combine(MapRoot, "recent.txt");

    // every folder of the map, the current one first, then by last use, then the rest by name
    List<string> RecentFolders()
    {
        var all = Categories().ToList();
        var list = new List<string> { _category };
        try { list.AddRange(File.ReadAllLines(RecentPath).Where(all.Contains)); }
        catch (Exception) { /* no file yet */ }
        list.AddRange(all);
        return list.Distinct().ToList();
    }

    void SetFolder(string folder)
    {
        _category = folder;
        Directory.CreateDirectory(MapDir);
        File.WriteAllLines(RecentPath, RecentFolders());
    }

    void NewFolder(CCSPlayerController p) => AskText(p, "folder name (one moment = one folder)",
        (pl, n) => { SetFolder(n); Say(pl, $"folder: {n}"); MainMenu(pl); });

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

    // all folders of the map, by name, 6 per page
    void CategoriesMenu(CCSPlayerController p) => CategoriesMenu(p, 0);

    void CategoriesMenu(CCSPlayerController p, int page)
    {
        var entries = new List<MenuItem> { new("+ New folder", NewFolder) };
        entries.AddRange(Categories().Select(c => new MenuItem(c, pl => { SetFolder(c); Say(pl, $"folder: {c}"); MainMenu(pl); })
            { Value = c == _category ? "current" : null, On = c == _category }));
        ShowPaged(p, $"Folders on {Server.MapName}", entries, page, CategoriesMenu, MainMenu);
    }

    string RecordingsTitle => $"Movements in {_category}";

    void RecordingsMenu(CCSPlayerController p)
    {
        var items = Names().Take(7).Select(n => new MenuItem(Describe(n), pl => RecordingMenu(pl, n))).ToList();
        items.Add(new("← Back", MainMenu));
        Show(p, new Menu(RecordingsTitle, items));
    }

    // something finished later (a bot joined, bots started): update the screen in place if it is still open
    void Reshow(CCSPlayerController p, string title, Action<CCSPlayerController> screen)
    {
        if (_menu?.Title != title || p is not { IsValid: true }) return;
        _picking = title;
        try { screen(p); }
        finally { _picking = null; }
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
    public void CmdGo(CCSPlayerController? caller, CommandInfo cmd)
    {
        cmd.ReplyToCommand("[FM] " + Play());
        _api?.RaiseBotsStarted();
    }

    // ---------------- one key per action (keys are set in the launcher) ----------------

    void Tell(CCSPlayerController? caller, string center, string chat)
    {
        var p = caller ?? LocalHuman();
        if (p == null) return;
        p.PrintToCenter(center);
        Say(p, chat);
    }

    [ConsoleCommand("fm_rectoggle", "fm_rectoggle - record a movement under the next free name / stop and save it")]
    public void CmdRecToggle(CCSPlayerController? caller, CommandInfo cmd)
    {
        if (_recName != null) { Tell(caller, "Movement saved", StopRec()); return; }
        var name = NextName();
        // over bots the recording starts with them, half a second later
        if (_replays.Count > 0) { Tell(caller, $"REC {name}", RecordOver(name)); return; }
        var msg = StartRec(name);
        Tell(caller, _recName != null ? $"REC {name}" : "Not recording", msg);
    }

    [ConsoleCommand("fm_bots", "fm_bots - start the assigned bots (Once / Loop as set) or stop them")]
    public void CmdBots(CCSPlayerController? caller, CommandInfo cmd)
    {
        if (_replays.Any(r => r.Running) || _looping || _starting) { Tell(caller, "Bots stopped", Halt()); return; }
        if (!_replays.Any(r => r.Bot is { IsValid: true })) { Tell(caller, "No bots assigned", "no bots assigned: Movements › a movement › Play on T/CT bot"); return; }
        Tell(caller, _loop ? "Bots: loop" : "Bots: once", Play());
        _api?.RaiseBotsStarted();
    }

    [ConsoleCommand("fm_loop", "fm_loop - bots play once / in a loop (restarts them if they play)")]
    public void CmdLoop(CCSPlayerController? caller, CommandInfo cmd)
    {
        SetLoop(!_loop);
        var playing = _replays.Any(r => r.Running) || _looping || _starting;
        Tell(caller, _loop ? "Bots play: Loop" : "Bots play: Once", playing ? Play() : $"bots will play {(_loop ? "in a loop" : "once")}");
    }

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
        foreach (var b in FakeDemoPlayers.All().Where(p => p is { IsValid: true, IsBot: true, IsHLTV: false }))
            b.Disconnect(NetworkDisconnectionReason.NETWORK_DISCONNECT_KICKED);
    }

    [ConsoleCommand("fm_where", "fm_where - positions of all players (debug)")]
    public void CmdWhere(CCSPlayerController? caller, CommandInfo cmd)
    {
        foreach (var p in FakeDemoPlayers.All().Where(p => p is { IsValid: true, IsHLTV: false }))
        {
            var o = p.PlayerPawn.Value?.AbsOrigin;
            var r = _replays.FirstOrDefault(x => x.Bot == p);
            var wpn = p.PlayerPawn.Value?.WeaponServices?.ActiveWeapon.Value;
            cmd.ReplyToCommand($"[FM] {p.PlayerName} alive={p.PawnIsAlive} hp={p.PlayerPawn.Value?.Health} speed={p.PlayerPawn.Value?.AbsVelocity.Length2D():0} pos={o?.X:0},{o?.Y:0},{o?.Z:0} weapon={wpn?.DesignerName}:{wpn?.Clip1}" +
                               (r != null && _bc != null ? $" replay={r.Name} {_bc.ReplayCursor(p.Slot)}/{_bc.ReplayTotal(p.Slot)}" : ""));
        }
    }

    [ConsoleCommand("fm_slots", "fm_slots - every player controller slot and what CounterStrikeSharp says of it (debug)")]
    public void CmdSlots(CCSPlayerController? caller, CommandInfo cmd)
    {
        cmd.ReplyToCommand($"[FM] MaxPlayers={Server.MaxPlayers} GetPlayers={Utilities.GetPlayers().Count} All={FakeDemoPlayers.All().Count}");
        for (var i = 1; i <= 64; i++)
        {
            var c = Utilities.GetPlayerFromIndex(i);
            if (c == null) continue;
            cmd.ReplyToCommand($"[FM] index {i} valid={c.IsValid} slot={c.Slot} '{c.PlayerName}' bot={c.IsBot} hltv={c.IsHLTV} connected={c.Connected} userid={c.UserId}");
        }
    }
}
