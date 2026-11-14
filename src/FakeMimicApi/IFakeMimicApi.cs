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

    /// perf/<plugin>.csv, marks.txt (F6), the launcher's system.csv and lag_*.txt
    public static string Perf => Path.Combine(Root, "perf");
}

/// Named pieces of work that took SpikeMs or more, one line each in perf/spikes.csv (time, plugin, what, ms):
/// the launcher's lag check (F6) names them, so a stutter points at the piece of code behind it.
public static class PerfSpikes
{
    public const double SpikeMs = 4;

    // only while tools\perfwatch.ps1 runs (it keeps perf/on): a release does no timing at all. Looked at every 2 s
    static long _checkedAt = -1;
    static bool _on;
    public static bool Enabled
    {
        get
        {
            var now = Environment.TickCount64;
            if (_checkedAt < 0 || now - _checkedAt > 2000)
            {
                _checkedAt = now;
                try { _on = File.Exists(Path.Combine(FakeDemoPaths.Perf, "on")); } catch (Exception) { _on = false; }
            }
            return _on;
        }
    }

    public static void Time(string plugin, string what, Action work)
    {
        if (!Enabled) { work(); return; }
        var sw = System.Diagnostics.Stopwatch.StartNew();
        try { work(); }
        finally { Note(plugin, what, sw.Elapsed.TotalMilliseconds); }
    }

    public static void Note(string plugin, string what, double ms)
    {
        if (ms < SpikeMs || !Enabled) return;
        try
        {
            var path = Path.Combine(FakeDemoPaths.Perf, "spikes.csv");
            var c = System.Globalization.CultureInfo.InvariantCulture;
            File.AppendAllText(path, string.Format(c, "{0:HH:mm:ss.fff},{1},{2},{3:0.0}\n", DateTime.Now, plugin, what.Replace(',', ' '), ms));
        }
        catch (Exception) { }
    }
}

/// A plugin's tick work, one CSV line a second, for the launcher's lag check (F6): how long the plugin
/// took per tick (average, most), how many ticks, how many came late (the gap since the previous tick over
/// SlowGapMs: the server did not keep up) and the plugin's own counts (Extra). Started anew each load.
public sealed class PerfLog
{
    const double SlowGapMs = 23;   // a 64-tick server ticks every 15.6 ms
    readonly string _path;
    readonly System.Diagnostics.Stopwatch _work = new(), _gap = new();
    readonly Func<string> _extra;
    double _sum, _max, _gapMax;
    int _ticks, _slow;
    long _second = -1;

    readonly string _header;
    bool _started;

    public PerfLog(string name, string extraHeader, Func<string> extra)
    {
        _extra = extra;
        _path = Path.Combine(FakeDemoPaths.Perf, name + ".csv");
        _header = "time,ms_avg,ms_max,ticks,slow_ticks,gap_max_ms," + extraHeader + "\n";
    }

    public void Begin()
    {
        if (!PerfSpikes.Enabled) { _started = false; _gap.Reset(); return; }
        if (!_started)
        {
            _started = true;   // a new file each time perfwatch turns timing on
            try { Directory.CreateDirectory(FakeDemoPaths.Perf); File.WriteAllText(_path, _header); } catch (Exception) { }
        }
        if (_gap.IsRunning)
        {
            var g = _gap.Elapsed.TotalMilliseconds;
            if (g > SlowGapMs) _slow++;
            _gapMax = Math.Max(_gapMax, g);
        }
        _gap.Restart();
        _work.Restart();
    }

    public void End()
    {
        if (!_started) return;
        var ms = _work.Elapsed.TotalMilliseconds;
        (_sum, _max, _ticks) = (_sum + ms, Math.Max(_max, ms), _ticks + 1);
        var now = DateTime.Now;
        var sec = now.Ticks / TimeSpan.TicksPerSecond;
        if (_second < 0) _second = sec;
        if (sec == _second) return;
        _second = sec;
        var c = System.Globalization.CultureInfo.InvariantCulture;
        var line = string.Format(c, "{0:HH:mm:ss},{1:0.00},{2:0.00},{3},{4},{5:0},{6}\n", now, _sum / Math.Max(1, _ticks), _max, _ticks, _slow, _gapMax, _extra());
        (_sum, _max, _ticks, _slow, _gapMax) = (0, 0, 0, 0, 0);
        try { File.AppendAllText(_path, line); } catch (Exception) { }
    }
}

/// Every connected player controller. Use this, not Utilities.GetPlayers: that one only looks at the first
/// Server.MaxPlayers slots, and after a workshop map loaded over the main menu (map_workshop; the menu's
/// background server has maxplayers 1) CounterStrikeSharp still says 1, so the bots were not seen at all
/// ("bot was not added" on de_ravine).
/// Not before the game made its entity system (main menu, map loading): CounterStrikeSharp reads the entity
/// list once through a Lazy that keeps the first failure, and then every entity call failed for the whole
/// session (commands silent, the menu did not open, an exception every tick made the game stutter).
public static class FakeDemoPlayers
{
    static bool _entities;

    static bool EntitiesReady()
    {
        if (_entities) return true;
        try { _entities = NativeAPI.GetConcreteEntityListPointer() != IntPtr.Zero; }
        catch (NativeException) { }
        return _entities;
    }

    public static List<CCSPlayerController> All()
    {
        var list = new List<CCSPlayerController>();
        if (!EntitiesReady()) return list;
        for (var i = 1; i <= 64; i++)
        {
            var c = CounterStrikeSharp.API.Utilities.GetPlayerFromIndex(i);
            if (c is { IsValid: true, Connected: PlayerConnectedState.Connected }) list.Add(c);
        }
        return list;
    }
}

/// Model: the agent model the bot wore ("" = the team's default).
public record TakeBot(string Recording, string BotName, int Team, string Model = "");

/// Where a recording goes as it is set now (its edits applied): the route, a point every few ticks,
/// the view yaw at the start, the team it was recorded for and the model chosen for it.
/// Frames: position and yaw of every tick (64 per second), DelayTicks: how long the bot waits at its start
/// before it moves (a positive timing offset).
public record ApiRoute(IReadOnlyList<System.Numerics.Vector3> Path, float Yaw, int Team, string Model,
    IReadOnlyList<(System.Numerics.Vector3 Pos, float Yaw)> Frames, int DelayTicks);

/// A card in a Cards row: an agent portrait (model path or "" for the team default), two lines of text.
public record ApiCard(string Model, int Team, string Title, string Subtitle);

public enum ApiTone { None, Good, Ok, Bad, Gold }

/// Cancelled: stopped with Cancel (or the player died), its demo file is deleted: keep no record of it.
public record TakeInfo(string Demo, string Map, string Folder, DateTime Started, DateTime? Stopped, IReadOnlyList<TakeBot> Bots, bool Cancelled = false);

/// Stars: a rating, Options are the stars (up to 5), the ones up to Selected are lit; a click calls Choose.
public enum ApiRowKind { Button, Toggle, BigToggle, Choice, Colors, Primary, Info, Cards, Stars }

/// One menu row. Button: Pick on click / digit; Primary: the same, big and gold (red with Accent), the
/// screen's main action. Toggle, BigToggle: a switch drawn from On, Pick flips it.
/// On also colours a Button's Value gold (a module that is on).
/// Choice: Options as segments, Colors: Swatches (pairs of ApiColors) — a click on one calls Choose with
/// its index, the digit chooses the next one. Value: short text on the right (a key hint, ▾).
/// Choice, Colors and Cards rows show Text as a heading (not clickable) above the segments / swatches / cards;
/// Info is a line of plain text (not clickable). Tone colours the row's key (a verdict), Faded greys it out.
/// Nested rows next to each other are drawn as one darker block (a group, e.g. opened settings);
/// Divider puts a line above the row (a new section).
/// A screen shown again with the same title from one of its own rows is updated without the entrance.
public record ApiMenuItem(string Text, Action<CCSPlayerController> Pick, bool Accent = false)
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
    /// Choice / Colors / Cards: the lit one, -1 none
    public int Selected { get; init; }
    public Action<CCSPlayerController, int>? Choose { get; init; }
}

/// Colours the menu can draw in swatches (classes C0..C7 in fm_menu.css).
public static class ApiColors
{
    public const int Orange = 0, Blue = 1, Red = 2, Teal = 3, Yellow = 4, Green = 5, White = 6, Violet = 7;

    public static readonly IReadOnlyList<System.Drawing.Color> Rgb = new[]
    {
        System.Drawing.Color.FromArgb(255, 255, 150, 40), System.Drawing.Color.FromArgb(255, 90, 160, 255),
        System.Drawing.Color.FromArgb(255, 255, 90, 70), System.Drawing.Color.FromArgb(255, 60, 220, 200),
        System.Drawing.Color.FromArgb(255, 255, 210, 60), System.Drawing.Color.FromArgb(255, 140, 255, 110),
        System.Drawing.Color.FromArgb(255, 255, 255, 255), System.Drawing.Color.FromArgb(255, 210, 110, 255),
    };
}

/// A movement assigned to a bot. Path: where the bot will walk (edits applied), a point every few ticks.
/// The same Path instance comes back until the assignment or its edits change.
public record ApiReplay(string Name, int BotSlot, int Team, IReadOnlyList<System.Numerics.Vector3> Path);

public interface IFakeMimicApi
{
    const string Capability = "fakemimic:api";

    /// Bumped on every change of this contract; add-ons compare it with the one they were built with.
    const int CurrentVersion = 8;

    /// CurrentVersion of the FakeMimic that is loaded.
    int Version { get; }

    /// Current folder (one moment of the movie) on the current map.
    string Folder { get; }

    /// Fired when a take starts (bots + tv_record) and when it stops.
    event Action<TakeInfo>? TakeStarted;
    event Action<TakeInfo>? TakeStopped;
    /// Fired when the player starts and stops recording a movement (name of the recording).
    event Action<string>? RecordingStarted;
    event Action<string>? RecordingStopped;
    /// Fired when the player starts the bots (Bots play, fm_go); not for PlaySetup and not for a loop's next pass.
    event Action? BotsStarted;
    /// Fired just after the map was reset before a start (every pass of a loop too). The reset sends the
    /// player a round start, and the game then drops beams and glow outlines on its side although they
    /// still exist on the server: add-ons that draw such things make them again here.
    event Action? MapCleared;

    /// Adds an entry to FakeMimic's main menu (one per add-on; the menu holds 8 rows).
    void AddMainMenuItem(string text, Action<CCSPlayerController> pick);
    /// Same, with a text read each time the menu opens (e.g. "X-ray: on").
    void AddMainMenuItem(Func<string> text, Action<CCSPlayerController> pick);
    /// Same, the whole row read each time the menu opens (text, a Value badge such as a count or "on").
    void AddMainMenuItem(Func<ApiMenuItem> row);

    /// Shows a screen in FakeMimic's in-game menu: up to 8 rows, row 9 is always Close.
    void ShowMenu(CCSPlayerController player, string title, IReadOnlyList<ApiMenuItem> items);
    /// Same, row 9 is "← Back" and calls back.
    void ShowMenu(CCSPlayerController player, string title, IReadOnlyList<ApiMenuItem> items, Action<CCSPlayerController> back);

    /// Movements assigned to bots right now.
    IReadOnlyList<ApiReplay> Replays { get; }

    /// Which tick of its movement (an index into ApiRoute.Frames) the bot in that slot plays now: 0 while it
    /// waits at the start, the last one after the end, -1 when it plays nothing.
    int ReplayTick(int botSlot);

    /// A recording of the current map as it would play now; null when it is not there any more.
    ApiRoute? Route(string folder, string recording);

    /// Bots play these recordings of the folder in a loop (that folder becomes the current one). When other
    /// movements are assigned now, the bots are replaced (removed like Backspace, new ones added one by one).
    /// started runs once they move. Returns what happens, for the chat.
    string PlaySetup(string folder, IReadOnlyList<TakeBot> bots, Action? started);

    /// Stops all bots (Bots play > Off).
    void StopBots();

    void OpenMainMenu(CCSPlayerController player);

    /// Prints a [FM] line to the player's chat.
    void Say(CCSPlayerController player, string message);

    /// The player's next chat line (any text, kept out of the chat) goes to then; empty cancels.
    void Ask(CCSPlayerController player, string prompt, Action<CCSPlayerController, string> then);
}
