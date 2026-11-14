// A bot right after recording (krot: "после записи мувмента сразу бот добавляется", with presets of the standard
// bots: standard, random, in order from the factions without repeats). A new movement is assigned at once to a bot
// of the team it was recorded for, with the model the preset picks; a model already chosen for it stays.
// The preset is a row of Movements, kept in Documents\FakeDemo\autobot.txt.
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using FakeMimicApi;

namespace FakeMimic;

public partial class FakeMimic
{
    static readonly string[] AutoBotNames = { "Off", "Standard", "Random", "In order" };
    int _autoBot;

    static string AutoBotPath => Path.Combine(FakeDemoPaths.Root, "autobot.txt");

    void LoadAutoBot()
    {
        try { _autoBot = Math.Clamp(int.Parse(File.ReadAllText(AutoBotPath).Trim()), 0, AutoBotNames.Length - 1); }
        catch (Exception) { /* no file: off */ }
    }

    void SetAutoBot(int preset)
    {
        _autoBot = preset;
        try { Directory.CreateDirectory(FakeDemoPaths.Root); File.WriteAllText(AutoBotPath, preset.ToString()); }
        catch (Exception) { /* the choice holds for this session */ }
    }

    MenuItem AutoBotRow() => new("Bot after recording", _ => { })
    {
        Kind = ApiRowKind.Choice, Options = AutoBotNames, Selected = _autoBot, Divider = true,
        Choose = (pl, i) => { SetAutoBot(i); RecordingsMenu(pl); },
    };

    // after a new movement is saved (not a re-recording: it keeps its bot)
    void AutoBot(string name, int team)
    {
        if (_autoBot == 0 || team is not (2 or 3)) return;
        var t = team == 3 ? "ct" : "t";
        var e = EditsOf(name);
        if (string.IsNullOrEmpty(e.Model) && PresetModel(t) is { Length: > 0 } model)
        {
            e.Model = model;
            e.Save(EditsPathOf(name));
        }
        Assign(name, t, s => { if (LocalHuman() is { } p) Say(p, s); });
    }

    // "" = the team's own model
    string PresetModel(string team)
    {
        if (_autoBot == 1) return "";
        var models = _models.Where(m => FactionFits(FactionOf(m), team)).ToList();
        if (models.Count == 0) return "";
        if (_autoBot == 2) return models[Random.Shared.Next(models.Count)];
        // in order (models.txt goes faction by faction), skipping the ones the assigned bots already wear
        var worn = _replays.Select(r => r.Edits.Model).ToHashSet();
        return models.FirstOrDefault(m => !worn.Contains(m)) ?? models[0];
    }
}
