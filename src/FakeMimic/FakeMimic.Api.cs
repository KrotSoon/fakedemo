// "fakemimic:api" for add-on plugins (FakeDirector, ...): main-menu entries, the in-game menu,
// chat lines and take events. Add-ons stay separate plugins; FakeMimic only knows this contract.
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Capabilities;
using FakeMimicApi;

namespace FakeMimic;

public partial class FakeMimic
{
    static readonly PluginCapability<IFakeMimicApi> ApiCapability = new(IFakeMimicApi.Capability);

    readonly List<MenuItem> _addonItems = new();
    TakeInfo? _takeInfo;
    Api? _api;

    void RegisterApi()
    {
        _api = new Api(this);
        Capabilities.RegisterPluginCapability(ApiCapability, () => _api);
    }

    TakeInfo NewTakeInfo(string demo) => new(demo, CounterStrikeSharp.API.Server.MapName, _category, DateTime.Now, null,
        _replays.Where(r => r.Bot is { IsValid: true })
            .Select(r => new TakeBot(r.Name, r.Bot!.PlayerName, r.Bot.TeamNum)).ToList());

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

        public void RaiseStarted(TakeInfo info) => TakeStarted?.Invoke(info);
        public void RaiseStopped(TakeInfo info) => TakeStopped?.Invoke(info);

        public void AddMainMenuItem(string text, Action<CCSPlayerController> pick) =>
            plugin._addonItems.Add(new MenuItem(text, pick));

        public void ShowMenu(CCSPlayerController player, string title, IReadOnlyList<ApiMenuItem> items) =>
            plugin.Show(player, new Menu(title, items.Take(8).Select(i => new MenuItem(i.Text, i.Pick, i.Accent)).ToList()));

        public void OpenMainMenu(CCSPlayerController player) => plugin.MainMenu(player);

        public void Say(CCSPlayerController player, string message) => plugin.Say(player, message);
    }
}
