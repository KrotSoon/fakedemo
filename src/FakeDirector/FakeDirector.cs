// FakeDirector - take log for FakeMimic (separate add-on plugin).
// Every take FakeMimic records (bots + tv_record) is written to Documents/FakeDemo/takes/<map>/<folder>/takes.json:
// demo name, when, how long, which recordings, bots and models played, a verdict and a note.
// FakeMimic's main menu gets "Takes ›": the takes of a folder (filter by verdict), and a card per take with the
// bots' portraits, Watch, the verdict, a preview on the map (glowing bots at their starts + their routes,
// only for the player, never in a demo), a jump to a bot's start, a note, Show in folder and Delete.
// Talks to FakeMimic only through FakeMimicApi ("fakemimic:api").
using System.Diagnostics;
using System.Drawing;
using System.Text.Json;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Capabilities;
using CounterStrikeSharp.API.Modules.Utils;
using FakeMimicApi;
using Microsoft.Extensions.Logging;
using Vector = CounterStrikeSharp.API.Modules.Utils.Vector;

namespace FakeDirector;

public class TakeRecord
{
    public string Demo { get; set; } = "";
    public DateTime Started { get; set; }
    public double Seconds { get; set; }
    public List<TakeBot> Bots { get; set; } = new();
    public int Stars { get; set; }               // 0 = not rated, 1..5
    public string Note { get; set; } = "";
    // the first take log of 0.6.1 builds had a verdict instead of stars: read, turned into stars, not written
    [System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingDefault)]
    public bool Best { get; set; }
    [System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingDefault)]
    public string? Verdict { get; set; }
}

public class FakeDirector : BasePlugin
{
    public override string ModuleName => "FakeDirector";
    public override string ModuleVersion => GetType().Assembly.GetName().Version?.ToString(3) ?? "?";
    public override string ModuleAuthor => "fakedemo";
    public override string ModuleDescription => "Take log for FakeMimic";

    static readonly PluginCapability<IFakeMimicApi> FakeMimic = new(IFakeMimicApi.Capability);
    static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    IFakeMimicApi? _fm;

    public override void Load(bool hotReload)
    {
        if (hotReload) AddTimer(0.5f, Hook);
        RegisterListener<Listeners.OnMapStart>(_ => { _ghosts.Clear(); _preview = null; _folder = null; });
        // the preview is only for the player: GOTV and bots never get it
        RegisterListener<Listeners.CheckTransmit>(infos =>
        {
            if (_ghosts.Count == 0) return;
            foreach (var (info, player) in infos)
            {
                if (player is { IsValid: true, IsBot: false, IsHLTV: false }) continue;
                foreach (var e in _ghosts) info.TransmitEntities.Remove(e);
            }
        });
    }

    public override void OnAllPluginsLoaded(bool hotReload) => Hook();

    // once per FakeMimic instance; a hot reload of this plugin alone does not call OnAllPluginsLoaded, so Load hooks too
    void Hook()
    {
        var fm = FakeMimic.Get();
        if (fm != null && ReferenceEquals(fm, _fm)) return;
        _fm = fm;
        if (_fm == null) { Logger.LogError("FakeMimic API not found: FakeDirector needs FakeMimic"); return; }
        if (_fm.Version != IFakeMimicApi.CurrentVersion)
            Logger.LogWarning("FakeMimic API {Have}, FakeDirector was built for {Want}: install matching versions", _fm.Version, IFakeMimicApi.CurrentVersion);
        _fm.TakeStarted += _ => ClearPreview();
        _fm.TakeStopped += OnTakeStopped;
        _fm.AddMainMenuItem(() => new ApiMenuItem("Takes ›", p => { _folder = null; TakesMenu(p); }) { Value = Load(LogPath(Server.MapName, _fm.Folder)).Count.ToString() });
    }

    public override void Unload(bool hotReload) => ClearPreview();

    // ---------------- storage ----------------

    static string MapTakes => Path.Combine(FakeDemoPaths.Takes, Server.MapName);

    string LogPath(string map, string folder)
    {
        var d = Path.Combine(FakeDemoPaths.Takes, map, folder);
        Directory.CreateDirectory(d);
        return Path.Combine(d, "takes.json");
    }

    // the folder the Takes screens show: FakeMimic's current one until another is picked there
    string? _folder;
    string Folder => _folder ?? _fm?.Folder ?? "default";
    string CurrentLog => LogPath(Server.MapName, Folder);

    List<TakeRecord> Load(string path)
    {
        var takes = File.Exists(path) ? JsonSerializer.Deserialize<List<TakeRecord>>(File.ReadAllText(path)) ?? new() : new();
        foreach (var t in takes.Where(t => t.Stars == 0 && (t.Best || !string.IsNullOrEmpty(t.Verdict))))
            t.Stars = t.Best ? 5 : t.Verdict switch { "good" => 4, "ok" => 3, "bad" => 1, _ => 0 };
        foreach (var t in takes) (t.Best, t.Verdict) = (false, null);
        return takes;
    }

    void Save(string path, List<TakeRecord> takes) => File.WriteAllText(path, JsonSerializer.Serialize(takes, Json));

    void OnTakeStopped(TakeInfo info)
    {
        var path = LogPath(info.Map, info.Folder);
        var takes = Load(path);
        takes.Add(new TakeRecord
        {
            Demo = info.Demo,
            Started = info.Started,
            Seconds = ((info.Stopped ?? DateTime.Now) - info.Started).TotalSeconds,
            Bots = info.Bots.ToList(),
        });
        Save(path, takes);
    }

    // tv_record writes the demo into the game's csgo folder
    string? DemoFile(string demo)
    {
        foreach (var dir in new[] { Path.Combine(Server.GameDirectory, "csgo"), Server.GameDirectory })
        {
            var f = Path.Combine(dir, demo + ".dem");
            if (File.Exists(f)) return f;
        }
        return null;
    }

    // folders of this map that have takes, the shown one first
    List<string> Folders()
    {
        var list = new List<string> { Folder };
        if (Directory.Exists(MapTakes))
            list.AddRange(Directory.GetDirectories(MapTakes).Select(Path.GetFileName).OfType<string>()
                .Where(f => Load(LogPath(Server.MapName, f)).Count > 0).Order());
        if (_fm != null) list.Add(_fm.Folder);
        return list.Distinct().ToList();
    }

    static ApiTone Tone(TakeRecord t) => t.Stars switch
    {
        5 => ApiTone.Gold, 4 => ApiTone.Good, 3 => ApiTone.Ok, 1 or 2 => ApiTone.Bad, _ => ApiTone.None,
    };

    static string StarText(int stars) => stars > 0 ? new string('★', stars) + " " : "";

    string Short(string demo) => demo.StartsWith(Folder + "_") ? demo[(Folder.Length + 1)..] : demo;

    // ---------------- list ----------------
    static readonly string[] Sorts = { "Newest", "Most ★" };
    int _sort;
    const int PerPage = 5;
    const int ShownFolders = 3;

    void TakesMenu(CCSPlayerController p, int page = 0)
    {
        if (_fm == null) return;
        var folders = Folders();
        var many = folders.Count > ShownFolders;
        var shown = folders.Take(ShownFolders).ToList();
        var takes = Load(CurrentLog);
        takes.Reverse();   // newest first
        if (_sort == 1) takes = takes.OrderByDescending(t => t.Stars).ToList();   // stable: newest first among equal
        var pages = Math.Max(1, (takes.Count + PerPage - 1) / PerPage);
        page = Math.Clamp(page, 0, pages - 1);

        var items = new List<ApiMenuItem>
        {
            new("Folder", _ => { })
            {
                Kind = ApiRowKind.Choice, Options = shown.Append(many ? "All ›" : "").Where(o => o != "").ToList(), Selected = 0,
                Choose = (pl, i) => { if (i < shown.Count) { _folder = shown[i]; TakesMenu(pl); } else FoldersMenu(pl); },
            },
            new("Sort", _ => { })
            {
                Kind = ApiRowKind.Choice, Options = Sorts, Selected = _sort,
                Choose = (pl, i) => { _sort = i; TakesMenu(pl); },
            },
        };
        foreach (var t in takes.Skip(page * PerPage).Take(PerPage))
            items.Add(new ApiMenuItem($"{StarText(t.Stars)}{Short(t.Demo)} · {t.Started:HH:mm}", pl => { _bot = -1; TakeMenu(pl, t.Demo); })
            {
                Value = $"{t.Seconds:0.0} s", Tone = Tone(t), Faded = DemoFile(t.Demo) == null,
            });
        if (takes.Count == 0)
            items.Add(new("No takes here yet: Start take on the main screen", _ => { }) { Kind = ApiRowKind.Info });
        if (pages > 1) items.Add(new($"More ({page + 1}/{pages})", pl => TakesMenu(pl, (page + 1) % pages)));
        _fm.ShowMenu(p, "Takes", items, pl => _fm.OpenMainMenu(pl));
    }

    void FoldersMenu(CCSPlayerController p, int page = 0)
    {
        if (_fm == null) return;
        var folders = Folders().Order().ToList();
        const int perPage = 7;
        var pages = Math.Max(1, (folders.Count + perPage - 1) / perPage);
        page = Math.Clamp(page, 0, pages - 1);
        var items = folders.Skip(page * perPage).Take(perPage).Select(f => new ApiMenuItem(f, pl => { _folder = f; TakesMenu(pl); })
        {
            Value = Load(LogPath(Server.MapName, f)).Count.ToString(), On = f == Folder,
        }).ToList();
        if (pages > 1) items.Add(new($"More ({page + 1}/{pages})", pl => FoldersMenu(pl, (page + 1) % pages)));
        _fm.ShowMenu(p, $"Takes on {Server.MapName}", items, pl => TakesMenu(pl));
    }

    // ---------------- one take ----------------
    int _bot = -1;   // the bot picked on the card

    void TakeMenu(CCSPlayerController p, string demo)
    {
        if (_fm == null) return;
        var path = CurrentLog;
        var takes = Load(path);
        var t = takes.FirstOrDefault(x => x.Demo == demo);
        if (t == null) { TakesMenu(p); return; }
        var file = DemoFile(demo);
        if (_bot >= t.Bots.Count) _bot = -1;
        void Change(CCSPlayerController pl, Action change) { change(); Save(path, takes); TakeMenu(pl, demo); }
        var bytes = file != null ? new FileInfo(file).Length : 0;
        var size = file == null ? "demo file is gone" : bytes < 1048576 ? $"{bytes / 1024} KB" : $"{bytes / 1048576.0:0.#} MB";
        var picked = _bot >= 0 ? t.Bots[_bot] : null;

        var items = new List<ApiMenuItem>
        {
            new("Bots", _ => { })
            {
                Kind = ApiRowKind.Cards, Selected = _bot,
                Cards = t.Bots.Select(b => new ApiCard(b.Model, b.Team, b.BotName, b.Recording)).ToList(),
                Choose = (pl, i) => { _bot = _bot == i ? -1 : i; TakeMenu(pl, demo); },
            },
            new($"{t.Started:dd.MM HH:mm} · {t.Seconds:0.0} s · {size}", _ => { }) { Kind = ApiRowKind.Info },
            new("▶ Watch", pl => { if (file != null) WatchMenu(pl, demo); else { _fm.Say(pl, $"'{demo}.dem' is not in the game folder any more"); TakeMenu(pl, demo); } })
            {
                Kind = ApiRowKind.Primary, Faded = file == null,
            },
            new("Rating", _ => { })
            {
                Kind = ApiRowKind.Stars, Options = Enumerable.Repeat("★", 5).ToList(), Selected = t.Stars - 1,
                // the last lit star again: not rated
                Choose = (pl, i) => Change(pl, () => t.Stars = t.Stars == i + 1 ? 0 : i + 1),
            },
            new("Preview: bots play it", pl => { if (_preview == demo) StopPreview(); else Preview(pl, t); TakeMenu(pl, demo); })
            {
                Kind = ApiRowKind.Toggle, On = _preview == demo, Divider = true,
            },
            new("Go to the bot's start", pl =>
            {
                if (picked != null) GoToStart(pl, picked);
                else _fm.Say(pl, "pick a bot in the row above first");
                TakeMenu(pl, demo);
            }) { Faded = picked == null, Value = picked?.BotName ?? "pick a bot" },
            new(t.Note.Length > 0 ? $"Note: {t.Note}" : "Add a note", pl => _fm.Ask(pl, "note for this take", (pl2, text) =>
            {
                var all = Load(path);
                var x = all.FirstOrDefault(y => y.Demo == demo);
                if (x == null) return;
                x.Note = text.Length > 60 ? text[..60] : text;
                Save(path, all);
                _fm.Say(pl2, $"note saved: {x.Note}");
                TakeMenu(pl2, demo);
            })) { Value = "chat" },
            new("Files ›", pl => FilesMenu(pl, demo)),
        };
        _fm.ShowMenu(p, demo, items, pl => TakesMenu(pl));
    }

    void WatchMenu(CCSPlayerController p, string demo)
    {
        _fm?.ShowMenu(p, $"Watch {demo}?", new List<ApiMenuItem>
        {
            new("Leaves the map, the bots are reset", _ => { }) { Kind = ApiRowKind.Info },
            new("▶ Watch now", pl => { ClearPreview(); Watch(pl, demo); }) { Kind = ApiRowKind.Primary },
        }, pl => TakeMenu(pl, demo));
    }

    // playdemo has to come from the game's own console: from the server's command buffer (also after a
    // disconnect) the server shut down and the game dropped the request, ExecuteClientCommand is refused
    // ("missing required FCVAR flag"). The launcher starts the game with netcon (-netconport / -netconpassword),
    // so the command goes in there, from a worker thread (netcon is served by the game's main loop).
    void Watch(CCSPlayerController p, string demo)
    {
        var args = Environment.GetCommandLineArgs();
        string? Arg(string name) { var i = Array.IndexOf(args, name); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }
        if (!int.TryParse(Arg("-netconport"), out var port) || port <= 0)
        {
            _fm?.Say(p, $"start CS2 from the FakeDemo launcher to watch from here, or type in the console: playdemo {demo}");
            return;
        }
        var pass = Arg("-netconpassword");
        Task.Run(() =>
        {
            try
            {
                using var c = new System.Net.Sockets.TcpClient("127.0.0.1", port);
                var s = c.GetStream();
                var text = System.Text.Encoding.UTF8.GetBytes((pass != null ? $"PASS {pass}\n" : "") + $"playdemo {demo}\n");
                s.Write(text, 0, text.Length);
                Thread.Sleep(500);
            }
            catch (Exception e) { Logger.LogWarning("playdemo over netcon failed: {Message}", e.Message); }
        });
    }

    void FilesMenu(CCSPlayerController p, string demo)
    {
        if (_fm == null) return;
        var file = DemoFile(demo);
        _fm.ShowMenu(p, demo, new List<ApiMenuItem>
        {
            new(file != null ? Path.GetFileName(file) : "demo file is gone", _ => { }) { Kind = ApiRowKind.Info },
            new("Show in folder", pl =>
            {
                if (file != null) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{file}\"") { UseShellExecute = true });
                else _fm.Say(pl, "the demo file is gone");
                FilesMenu(pl, demo);
            }) { Faded = file == null },
            new("Delete this take", pl => ConfirmDelete(pl, demo), Accent: true) { Divider = true },
        }, pl => TakeMenu(pl, demo));
    }

    void ConfirmDelete(CCSPlayerController p, string demo)
    {
        _fm?.ShowMenu(p, $"Delete {demo}.dem?", new List<ApiMenuItem>
        {
            new($"Yes, delete {demo}.dem", pl =>
            {
                var path = CurrentLog;
                var takes = Load(path);
                takes.RemoveAll(x => x.Demo == demo);
                Save(path, takes);
                var file = DemoFile(demo);
                if (file != null) File.Delete(file);
                if (_preview == demo) StopPreview();
                _fm!.Say(pl, file != null ? $"deleted {demo}.dem" : $"removed '{demo}' from the list (demo file was already gone)");
                TakesMenu(pl);
            }, Accent: true),
        }, pl => FilesMenu(pl, demo));
    }

    // ---------------- preview on the map ----------------
    // The take's bots play it again, in a loop, with all their animations (FakeMimic replaces the bots when
    // other movements are assigned now), and the routes are drawn as beams only the player sees, a gold post
    // at each start. Through walls: Wallhack (J). (Props walking the frames slid in one pose: dropped.)
    readonly List<CBaseEntity> _ghosts = new();
    string? _preview;
    const int MaxSegments = 60;
    static readonly Color RouteT = Color.FromArgb(255, 255, 150, 40), RouteCT = Color.FromArgb(255, 90, 160, 255);
    static readonly Color StartPost = Color.FromArgb(255, 228, 174, 57);

    void Preview(CCSPlayerController p, TakeRecord t)
    {
        ClearPreview();
        var missing = 0;
        var playable = new List<TakeBot>();
        foreach (var b in t.Bots)
        {
            var route = _fm?.Route(Folder, b.Recording);
            if (route == null || route.Path.Count == 0) { missing++; continue; }
            playable.Add(b);
            var color = b.Team == 3 ? RouteCT : RouteT;
            var step = Math.Max(1, (route.Path.Count + MaxSegments - 1) / MaxSegments);
            var prev = route.Path[0];
            for (var i = step; i < route.Path.Count + step - 1; i += step)
            {
                var next = route.Path[Math.Min(i, route.Path.Count - 1)];
                Beam(prev, next, color);
                prev = next;
            }
            Beam(route.Path[0], route.Path[0] with { Z = route.Path[0].Z + 72 }, StartPost);
        }
        _preview = t.Demo;
        if (_fm == null || playable.Count == 0) { _fm?.Say(p, "the recordings of this take are gone"); return; }
        var demo = t.Demo;
        _fm.Say(p, _fm.PlaySetup(Folder, playable, () => _fm.Say(p, $"preview of {demo}: the bots play it in a loop, J to see them through walls"))
            + (missing > 0 ? $"; {missing} recording(s) are gone" : ""));
    }

    void StopPreview()
    {
        if (_preview != null) _fm?.StopBots();
        ClearPreview();
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
        _ghosts.Add(beam);
    }

    void ClearPreview()
    {
        foreach (var e in _ghosts.Where(e => e.IsValid)) e.Remove();
        _ghosts.Clear();
        _preview = null;
    }

    void GoToStart(CCSPlayerController p, TakeBot b)
    {
        var route = _fm?.Route(Folder, b.Recording);
        if (route == null || route.Path.Count == 0) { _fm?.Say(p, $"'{b.Recording}' is gone"); return; }
        if (p.PlayerPawn.Value is not { IsValid: true } pawn || !p.PawnIsAlive) { _fm?.Say(p, "you must be alive"); return; }
        var at = route.Path[0];
        pawn.Teleport(new Vector(at.X, at.Y, at.Z), new QAngle(0, route.Yaw, 0), new Vector(0, 0, 0));
        _fm?.Say(p, $"at the start of '{b.Recording}' ({b.BotName})");
    }
}
