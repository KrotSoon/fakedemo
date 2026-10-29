// Character model for the bot that plays a recording.
// models.txt (next to the plugin) lists the agent models under agents/models/ in pak01_dir.vpk (the old
// characters/models/ copies render as error cubes); regenerate it with
// src/list_models.py after a CS2 update adds agents. All of them are precached on map load so a bot
// can switch to any of them; the choice is stored in the recording's .fme (model=...).
using CounterStrikeSharp.API.Core;

namespace FakeMimic;

public partial class FakeMimic
{
    // faction folder -> display name; folders missing here show their folder name
    static readonly Dictionary<string, string> FactionNames = new()
    {
        ["ctm_diver"] = "SEAL Frogman", ["ctm_fbi"] = "FBI", ["ctm_gendarmerie"] = "Gendarmerie",
        ["ctm_heavy"] = "CT Heavy", ["ctm_sas"] = "SAS", ["ctm_st6"] = "SEAL Team 6", ["ctm_swat"] = "SWAT",
        ["tm_balkan"] = "Balkan", ["tm_jumpsuit"] = "Jumpsuit", ["tm_jungle_raider"] = "Guerrilla",
        ["tm_leet"] = "Elite Crew", ["tm_phoenix"] = "Phoenix", ["tm_phoenix_heavy"] = "T Heavy",
        ["tm_professional"] = "Professionals",
    };

    List<string> _models = new();

    void LoadModels()
    {
        var path = Path.Combine(ModuleDirectory, "models.txt");
        _models = File.Exists(path)
            ? File.ReadAllLines(path).Select(l => l.Trim()).Where(l => l.EndsWith(".vmdl")).ToList()
            : new();
    }

    static string FactionOf(string model) => model.Split('/')[2];   // agents/models/<faction>/...

    static string FactionName(string faction) => FactionNames.TryGetValue(faction, out var n) ? n : faction;

    // "characters/models/tm_leet/tm_leet_variantf.vmdl" -> "Elite Crew f"
    static string ModelName(string model)
    {
        if (string.IsNullOrEmpty(model)) return "default";
        var faction = FactionOf(model);
        var file = Path.GetFileNameWithoutExtension(model);
        var variant = file.Length > faction.Length ? file[faction.Length..].TrimStart('_').Replace("variant", "").Replace("var", "") : "";
        return variant.Length == 0 ? FactionName(faction) : $"{FactionName(faction)} {variant}";
    }

    string SetModel(string name, string model)
    {
        var e = EditsOf(name);
        e.Model = model;
        e.Save(EditsPathOf(name));
        Reload(name);
        return $"'{name}' is played by: {ModelName(model)} (applies on the next start)";
    }

    // Go() calls this a moment after the respawn: the game sets the team model during spawn and
    // would overwrite one set earlier
    static void ApplyModel(CCSPlayerController bot, RecordingEdits e)
    {
        if (string.IsNullOrEmpty(e.Model)) return;
        // recordings edited before the switch to agents/models keep the old path: map it over
        var model = e.Model.Replace("characters/models/", "agents/models/");
        if (bot is { IsValid: true } && bot.PlayerPawn.Value is { IsValid: true } pawn) pawn.SetModel(model);
    }


    static bool FactionFits(string faction, string team) =>
        team == "ct" ? faction.StartsWith("ctm_") : faction.StartsWith("tm_");

    // ---------------- menus ----------------
    // "Play on a bot": who plays it (T / CT) -> faction of that team or team default -> variant,
    // and the bot is added with that model.

    // up to 6 entries per page, then "More" and "Back"
    void ShowPaged(CCSPlayerController p, string title, List<MenuItem> entries, int page, Action<CCSPlayerController, int> reopen, Action<CCSPlayerController> back)
    {
        const int perPage = 6;
        var pages = Math.Max(1, (entries.Count + perPage - 1) / perPage);
        page = Math.Clamp(page, 0, pages - 1);
        var items = entries.Skip(page * perPage).Take(perPage).ToList();
        if (pages > 1) items.Add(new($"More ({page + 1}/{pages})", pl => reopen(pl, (page + 1) % pages)));
        items.Add(new("← Back", back));
        Show(p, new Menu(title, items));
    }

    void PlayOnBotMenu(CCSPlayerController p, string name)
    {
        Show(p, new Menu($"Who plays '{name}'?", new List<MenuItem>
        {
            new("Terrorist", pl => FactionsMenu(pl, name, "t")),
            new("Counter-Terrorist", pl => FactionsMenu(pl, name, "ct")),
            new("← Back", pl => RecordingMenu(pl, name)),
        }));
    }

    void AssignWithModel(CCSPlayerController p, string name, string team, string model)
    {
        SetModel(name, model);
        Assign(name, team, s => { Say(p, $"{s}, model: {ModelName(model)}"); RecordingsMenu(p); });
    }

    void FactionsMenu(CCSPlayerController p, string name, string team, int page = 0)
    {
        var entries = new List<MenuItem> { new("Default team model", pl => AssignWithModel(pl, name, team, "")) };
        entries.AddRange(_models.Select(FactionOf).Distinct().Where(f => FactionFits(f, team))
            .Select(f => new MenuItem(FactionName(f), pl => VariantsMenu(pl, name, team, f))));
        ShowPaged(p, $"{(team == "t" ? "T" : "CT")} model for '{name}'", entries, page,
            (pl, pg) => FactionsMenu(pl, name, team, pg), pl => PlayOnBotMenu(pl, name));
    }

    void VariantsMenu(CCSPlayerController p, string name, string team, string faction, int page = 0)
    {
        var entries = _models.Where(m => FactionOf(m) == faction)
            .Select(m => new MenuItem(ModelName(m), pl => AssignWithModel(pl, name, team, m))).ToList();
        ShowPaged(p, FactionName(faction), entries, page,
            (pl, pg) => VariantsMenu(pl, name, team, faction, pg), pl => FactionsMenu(pl, name, team));
    }
}