// "fakemimic:api" for add-on plugins (FakeDirector, ...): main-menu entries, the in-game menu,
// chat lines and take events. Add-ons stay separate plugins; FakeMimic only knows this contract.
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Capabilities;
using FakeMimicApi;

namespace FakeMimic;

public partial class FakeMimic
{
    static readonly PluginCapability<IFakeMimicApi> ApiCapability = new(IFakeMimicApi.Capability);

    readonly List<Func<ApiMenuItem>> _addonItems = new();
    TakeInfo? _takeInfo;
    Api? _api;

    static MenuItem FromApi(ApiMenuItem i) => new(i.Text, i.Pick, i.Accent)
    {
        Kind = i.Kind, Nested = i.Nested, Divider = i.Divider, On = i.On, Value = i.Value, Options = i.Options?.Take(RowOptions).ToList(),
        Swatches = i.Swatches?.Take(RowSwatches).ToList(), Cards = i.Cards?.Take(RowCards).ToList(),
        Tone = i.Tone, Faded = i.Faded, Selected = i.Selected, Choose = i.Choose,
    };

    void RegisterApi()
    {
        _api = new Api(this);
        Capabilities.RegisterPluginCapability(ApiCapability, () => _api);
    }

    TakeInfo NewTakeInfo(string demo) => new(demo, CounterStrikeSharp.API.Server.MapName, _category, DateTime.Now, null,
        _replays.Where(r => r.Bot is { IsValid: true })
            .Select(r => new TakeBot(r.Name, r.Bot!.PlayerName, r.Bot.TeamNum, WornModel(r))).ToList());

    // the chosen model, or the one the game gave the bot (the map's default agent)
    static string WornModel(Replay r) => !string.IsNullOrEmpty(r.Edits.Model) ? r.Edits.Model
        : r.Bot?.PlayerPawn.Value?.CBodyComponent?.SceneNode?.GetSkeletonInstance().ModelState.ModelName ?? "";

    void FireTakeStarted(string demo)
    {
        _takeInfo = NewTakeInfo(demo);
        _api?.RaiseStarted(_takeInfo);
    }

    void FireTakeStopped()
    {
        if (_takeInfo == null) return;
        var info = _takeInfo with { Stopped = DateTime.Now };
        _takeInfo = null;
        _api?.RaiseStopped(info);
    }

    sealed class Api(FakeMimic plugin) : IFakeMimicApi
    {
        public int Version => IFakeMimicApi.CurrentVersion;
        public string Folder => plugin._category;

        public event Action<TakeInfo>? TakeStarted;
        public event Action<TakeInfo>? TakeStopped;
        public event Action<string>? RecordingStarted;
        public event Action<string>? RecordingStopped;
        public void RaiseRecording(string name, bool started) => (started ? RecordingStarted : RecordingStopped)?.Invoke(name);

        public void RaiseStarted(TakeInfo info) => TakeStarted?.Invoke(info);
        public void RaiseStopped(TakeInfo info) => TakeStopped?.Invoke(info);

        public void AddMainMenuItem(string text, Action<CCSPlayerController> pick) => AddMainMenuItem(() => text, pick);

        public void AddMainMenuItem(Func<string> text, Action<CCSPlayerController> pick) => AddMainMenuItem(() => new ApiMenuItem(text(), pick));

        public void AddMainMenuItem(Func<ApiMenuItem> row) => plugin._addonItems.Add(row);

        public void ShowMenu(CCSPlayerController player, string title, IReadOnlyList<ApiMenuItem> items) =>
            plugin.Show(player, new Menu(title, Rows(items)));

        public void ShowMenu(CCSPlayerController player, string title, IReadOnlyList<ApiMenuItem> items, Action<CCSPlayerController> back) =>
            plugin.Show(player, new Menu(title, Rows(items), Back: back));

        static List<MenuItem> Rows(IReadOnlyList<ApiMenuItem> items) => items.Take(8).Select(FromApi).ToList();

        // routes are computed once per assignment / edit (Reload and Assign put in new Edits objects)
        readonly System.Runtime.CompilerServices.ConditionalWeakTable<RecordingEdits, IReadOnlyList<System.Numerics.Vector3>> _paths = new();

        public IReadOnlyList<ApiReplay> Replays => plugin._replays.Where(r => r.Bot is { IsValid: true })
            .Select(r => new ApiReplay(r.Name, r.Bot!.Slot, r.Rec.Team, _paths.GetValue(r.Edits, _ => Points(Prepare(r.Rec, r.Edits))))).ToList();

        public string PlaySetup(string folder, IReadOnlyList<TakeBot> bots, Action? started) => plugin.PlaySetup(folder, bots, started);

        public void StopBots() => plugin.Halt();

        public ApiRoute? Route(string folder, string recording)
        {
            var dir = Path.Combine(plugin.MapRoot, folder);
            var file = Path.Combine(dir, recording + Ext);
            if (!File.Exists(file)) return null;
            var edits = RecordingEdits.Load(Path.Combine(dir, recording + ".fme"));
            var rec = Prepare(Recording.Load(file), edits);
            if (rec.Ticks.Length == 0) return null;
            var frames = rec.Ticks.Select(t => (new System.Numerics.Vector3(t.Pre.OriginX, t.Pre.OriginY, t.Pre.OriginZ), t.Pre.Yaw)).ToList();
            return new ApiRoute(Points(rec), rec.Ticks[0].Pre.Yaw, rec.Team, edits.Model, frames, Math.Max(0, edits.OffsetTicks));
        }

        static IReadOnlyList<System.Numerics.Vector3> Points(Recording rec)
        {
            var ticks = rec.Ticks;
            var pts = new List<System.Numerics.Vector3>();
            foreach (var t in ticks)
            {
                var v = new System.Numerics.Vector3(t.Pre.OriginX, t.Pre.OriginY, t.Pre.OriginZ);
                // a point every 48 units of the way, so standing still adds nothing
                if (pts.Count == 0 || System.Numerics.Vector3.Distance(pts[^1], v) >= 48) pts.Add(v);
            }
            if (ticks.Length > 0)
            {
                var end = ticks[^1].Pre;
                pts.Add(new(end.OriginX, end.OriginY, end.OriginZ));
            }
            return pts;
        }

        public void OpenMainMenu(CCSPlayerController player) => plugin.MainMenu(player);

        public void Say(CCSPlayerController player, string message) => plugin.Say(player, message);

        public void Ask(CCSPlayerController player, string prompt, Action<CCSPlayerController, string> then) =>
            plugin.AskText(player, prompt, then, raw: true);
    }
}
