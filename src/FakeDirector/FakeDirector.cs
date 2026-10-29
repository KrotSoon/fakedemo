// FakeDirector - take log for FakeMimic (separate add-on plugin).
// Every take FakeMimic records (bots + tv_record) is written to Documents/FakeDemo/takes/<map>/<folder>/takes.json:
// demo name, when, how long, which recordings and bots played. FakeMimic's main menu gets
// "Takes": list per folder, mark the best take, print its playdemo command, delete a take's demo.
// Talks to FakeMimic only through FakeMimicApi ("fakemimic:api").
using System.Text.Json;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Capabilities;
using FakeMimicApi;
using Microsoft.Extensions.Logging;

namespace FakeDirector;

public class TakeRecord
{
    public string Demo { get; set; } = "";
    public DateTime Started { get; set; }
    public double Seconds { get; set; }
    public List<TakeBot> Bots { get; set; } = new();
    public bool Best { get; set; }
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

    public override void OnAllPluginsLoaded(bool hotReload)
    {
        _fm = FakeMimic.Get();
        if (_fm == null) { Logger.LogError("FakeMimic API not found: FakeDirector needs FakeMimic"); return; }
        if (_fm.Version != IFakeMimicApi.CurrentVersion)
            Logger.LogWarning("FakeMimic API {Have}, FakeDirector was built for {Want}: install matching versions", _fm.Version, IFakeMimicApi.CurrentVersion);
        _fm.TakeStopped += OnTakeStopped;
        _fm.AddMainMenuItem("Takes", p => TakesMenu(p));
    }

    // ---------------- storage ----------------

    string LogPath(string map, string folder)
    {
        var d = Path.Combine(FakeDemoPaths.Takes, map, folder);
        Directory.CreateDirectory(d);
        return Path.Combine(d, "takes.json");
    }

    string CurrentLog => LogPath(Server.MapName, _fm?.Folder ?? "default");

    List<TakeRecord> Load(string path) =>
        File.Exists(path) ? JsonSerializer.Deserialize<List<TakeRecord>>(File.ReadAllText(path)) ?? new() : new();

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

    static string Line(TakeRecord t) =>
        $"{(t.Best ? "★ " : "")}{t.Demo} · {t.Seconds:0.0} s · {t.Bots.Count} bots · {t.Started:HH:mm}";

    // ---------------- menus ----------------

    void TakesMenu(CCSPlayerController p, int page = 0)
    {
        if (_fm == null) return;
        var takes = Load(CurrentLog);
        takes.Reverse();   // newest first
        const int perPage = 6;
        var pages = Math.Max(1, (takes.Count + perPage - 1) / perPage);
        page = Math.Clamp(page, 0, pages - 1);
        var items = takes.Skip(page * perPage).Take(perPage)
            .Select(t => new ApiMenuItem(Line(t), pl => TakeMenu(pl, t.Demo))).ToList();
        if (pages > 1) items.Add(new($"More ({page + 1}/{pages})", pl => TakesMenu(pl, (page + 1) % pages)));
        items.Add(new("← Back", pl => _fm.OpenMainMenu(pl)));
        _fm.ShowMenu(p, takes.Count == 0 ? $"No takes in {_fm.Folder} yet" : $"Takes in {_fm.Folder}", items);
    }

    void TakeMenu(CCSPlayerController p, string demo)
    {
        if (_fm == null) return;
        var path = CurrentLog;
        var takes = Load(path);
        var t = takes.FirstOrDefault(x => x.Demo == demo);
        if (t == null) { TakesMenu(p); return; }
        var file = DemoFile(demo);
        _fm.ShowMenu(p, Line(t), new List<ApiMenuItem>
        {
            new(t.Best ? "Unmark best take" : "Mark as best take", pl =>
            {
                t.Best = !t.Best;
                Save(path, takes);
                _fm.Say(pl, t.Best ? $"'{demo}' marked as best" : $"'{demo}' unmarked");
                TakeMenu(pl, demo);
            }),
            new("Who played", pl =>
            {
                foreach (var b in t.Bots) _fm.Say(pl, $"{b.Recording} → {b.BotName} ({(b.Team == 2 ? "T" : "CT")})");
                if (t.Bots.Count == 0) _fm.Say(pl, "no bots in this take");
                TakeMenu(pl, demo);
            }),
            new("Print playdemo command", pl =>
            {
                _fm.Say(pl, file != null ? $"playdemo {demo}" : $"'{demo}.dem' is not in the game folder any more");
                Server.PrintToConsole($"playdemo {demo}");
                TakeMenu(pl, demo);
            }),
            new("Delete this take", pl => ConfirmDelete(pl, demo), Accent: true),
            new("← Back", pl => TakesMenu(pl)),
        });
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
                _fm!.Say(pl, file != null ? $"deleted {demo}.dem" : $"removed '{demo}' from the list (demo file was already gone)");
                TakesMenu(pl);
            }, Accent: true),
            new("Cancel", pl => TakeMenu(pl, demo)),
        });
    }
}
