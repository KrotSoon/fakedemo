// Contract between FakeMimic and add-on plugins (FakeDirector and future modules).
// Deployed to addons/counterstrikesharp/shared/FakeMimicApi/FakeMimicApi.dll; add-ons reference it
// with Private=false and get the implementation through the "fakemimic:api" plugin capability.
using CounterStrikeSharp.API.Core;

namespace FakeMimicApi;

/// Where FakeDemo keeps user data: outside the game folder, so turning plugins off or
/// installing a new version never touches recordings, takes or menu settings.
public static class FakeDemoPaths
{
    public static string Root { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "FakeDemo");

    /// recordings/<map>/<folder>/<name>.fmr (+ .fme edits)
    public static string Recordings => Path.Combine(Root, "recordings");

    /// takes/<map>/<folder>/takes.json (FakeDirector)
    public static string Takes => Path.Combine(Root, "takes");
}

public record TakeBot(string Recording, string BotName, int Team);

public record TakeInfo(string Demo, string Map, string Folder, DateTime Started, DateTime? Stopped, IReadOnlyList<TakeBot> Bots);

public record ApiMenuItem(string Text, Action<CCSPlayerController> Pick, bool Accent = false);

public interface IFakeMimicApi
{
    const string Capability = "fakemimic:api";

    /// Bumped on every change of this contract; add-ons compare it with the one they were built with.
    const int CurrentVersion = 2;

    /// CurrentVersion of the FakeMimic that is loaded.
    int Version { get; }

    /// Current folder (one moment of the movie) on the current map.
    string Folder { get; }

    /// Fired when a take starts (bots + tv_record) and when it stops.
    event Action<TakeInfo>? TakeStarted;
    event Action<TakeInfo>? TakeStopped;

    /// Adds an entry to FakeMimic's main menu (one per add-on; the menu holds 8 rows).
    void AddMainMenuItem(string text, Action<CCSPlayerController> pick);

    /// Shows a screen in FakeMimic's in-game menu: up to 8 rows, row 9 is always Close.
    void ShowMenu(CCSPlayerController player, string title, IReadOnlyList<ApiMenuItem> items);

    void OpenMainMenu(CCSPlayerController player);

    /// Prints a [FM] line to the player's chat.
    void Say(CCSPlayerController player, string message);
}
