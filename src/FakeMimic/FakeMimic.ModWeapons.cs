// Weapons of a workshop mod (NewGuns: a crossbow, a minigun, an RPG... as subclasses in its weapons.vdata) in the
// H menu: Modules > Mod weapons, by category, a click gives it. The lists are modweapons_<item id>.txt next to the
// plugin, put there by the launcher for the mods that are on (from game\mods\<id>.txt, one per known mod):
//   category|vdata name|name in the menu|the game's class it is made on
// GiveNamedItem does not take a subclass name ("weapon_crossbow" gave nothing): the class it is made on is given
// and turned into the subclass with the ChangeSubclass input, the way knives are.
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Core.Attributes.Registration;

namespace FakeMimic;

public partial class FakeMimic
{
    record ModWeapon(string Category, string Name, string Title, string Base);

    readonly List<ModWeapon> _modWeapons = new();

    // sound event files of the mods ("sounds|soundevents/x.vsndevts" lines of the lists): on a map that is not the
    // mod's own the game does not load them, and the guns that use the mod's sounds (NewGuns' AR2, plasma pistol,
    // flamethrower) fired silently. Precached with the map, as the models are
    readonly List<string> _modResources = new();

    void LoadModWeapons()
    {
        foreach (var f in Directory.GetFiles(ModuleDirectory, "modweapons_*.txt"))
            foreach (var line in File.ReadAllLines(f))
            {
                if (line.StartsWith('#')) continue;
                var parts = line.Split('|');
                if (parts is ["sounds", var res]) { _modResources.Add(res.Trim()); continue; }
                if (parts is not [var cat, var name, var title, var bas]) continue;
                if (!_modWeapons.Any(w => w.Name == name.Trim())) _modWeapons.Add(new(cat.Trim(), name.Trim(), title.Trim(), bas.Trim()));
            }
        if (_modResources.Count > 0)
            RegisterListener<Listeners.OnServerPrecacheResources>(m => { foreach (var r in _modResources) m.AddResource(r); });
    }

    [ConsoleCommand("fm_weapons", "fm_weapons - your weapons: class and subclass (debug)")]
    public void CmdWeapons(CCSPlayerController? caller, CommandInfo cmd)
    {
        if ((caller ?? LocalHuman())?.PlayerPawn.Value?.WeaponServices is not { } ws) return;
        foreach (var w in ws.MyWeapons.Select(h => h.Value).Where(w => w is { IsValid: true }))
        {
            // the model tells the subclass (VData.Name is the base class's name in a subclass too)
            var v = w!.As<CCSWeaponBase>().VData;
            var model = w.CBodyComponent?.SceneNode?.GetSkeletonInstance()?.ModelState.ModelName ?? "?";
            cmd.ReplyToCommand($"[FM] {w.DesignerName} slot {v?.GearSlot} model {model}{(ws.ActiveWeapon.Value?.Handle == w.Handle ? " (in hand)" : "")}");
        }
    }

    void GiveModWeapon(CCSPlayerController p, ModWeapon w)
    {
        void Tell(string m) { Say(p, m); Server.PrintToConsole("[FM] " + m); }
        if (p.PlayerPawn.Value is not { IsValid: true } pawn || !p.PawnIsAlive) { Tell("you must be alive"); return; }
        // one main gun and one pistol (grenades and the rest stack): what is in the slot goes, before the gift for the
        // base class's slot (or the game drops the new one), after the subclass change for the slot it really has
        // (NewGuns' sawed-off is made on the shotgun but is a pistol)
        void Clear(gear_slot_t slot, nint keep)
        {
            if (slot is not (gear_slot_t.GEAR_SLOT_RIFLE or gear_slot_t.GEAR_SLOT_PISTOL)) return;
            foreach (var old in pawn.WeaponServices?.MyWeapons.Select(h => h.Value).ToList() ?? new())
                if (old is { IsValid: true } && old.Handle != keep && old.As<CCSWeaponBase>().VData?.GearSlot == slot) old.Remove();
        }
        // the game keeps one of a class (a grenade, the knife): the one there would make the gift fail
        // (the car bomb is an incendiary, the defibrillator a knife)
        if (w.Base == "weapon_c4" && p.TeamNum == 3) { Tell($"{w.Title}: terrorists only (the game takes C4 things off a CT)"); return; }
        foreach (var old in pawn.WeaponServices?.MyWeapons.Select(h => h.Value).ToList() ?? new())
            if (old is { IsValid: true } && (old.DesignerName == w.Base || w.Base == "weapon_knife" && IsKnife(old.DesignerName))) old.Remove();
        Clear(Pistols.Contains(w.Base) ? gear_slot_t.GEAR_SLOT_PISTOL : Primary(w.Base) ? gear_slot_t.GEAR_SLOT_RIFLE : gear_slot_t.GEAR_SLOT_INVALID, 0);
        // the removed ones go only at the end of the frame: given right away, a fourth grenade was over the limit
        // and the game took it back
        Server.NextFrame(() => { if (p.IsValid && pawn.IsValid) Give(p, pawn, w, Tell, Clear); });
    }

    void Give(CCSPlayerController p, CCSPlayerPawn pawn, ModWeapon w, Action<string> Tell, Action<gear_slot_t, nint> Clear)
    {
        var given = p.GiveNamedItem(w.Base);
        if (given == 0) { Tell($"{w.Title}: {w.Base} not given"); return; }
        var weapon = new CCSWeaponBase(given);
        // the skins leave it alone: they would turn the defibrillator back into the chosen knife
        _modGiven.Add(weapon.Index);
        weapon.AcceptInput("ChangeSubclass", value: w.Name);
        _modOf[weapon.Index] = w;
        // recording a movement: the bot gets this one, not the class it is made on (it was given the plain negev
        // for the minigun: the recording only had the weapon's definition, the base class's)
        if (_recBuys != null && _recPlayer is { IsValid: true } rp && rp.Slot == p.Slot)
            _recBuys.Add((Server.TickCount - _recStartTick, $"{w.Base}:{w.Name}"));
        // into the hand a moment later, the way the replays switch weapons (right after the subclass change a grenade
        // did not go; slot4 took the first grenade of the belt, "use" from the server did nothing)
        AddTimer(0.15f, () =>
        {
            if (!p.IsValid || !pawn.IsValid || !weapon.IsValid) { Tell($"{w.Title}: the game took it back"); return; }
            var slot = weapon.VData?.GearSlot ?? gear_slot_t.GEAR_SLOT_INVALID;
            Clear(slot, given);
            if (slot == gear_slot_t.GEAR_SLOT_GRENADES) PickGrenade(p, pawn, given, 8);
            else if (pawn.WeaponServices is { } ws) SelectItem(ws, weapon);
            Tell(w.Title);
        });
    }

    // a grenade goes into the hand as a player picks one: slot4 again and again (it steps through the belt) until it
    // is the one (SelectItem did not take grenades)
    void PickGrenade(CCSPlayerController p, CCSPlayerPawn pawn, nint grenade, int tries)
    {
        if (!p.IsValid || !pawn.IsValid || tries == 0 || pawn.WeaponServices?.ActiveWeapon.Value?.Handle == grenade) return;
        p.ExecuteClientCommand("slot4");
        AddTimer(0.35f, () => PickGrenade(p, pawn, grenade, tries - 1));
    }

    // entity indexes of weapons given from this menu (the skins skip them)
    readonly HashSet<uint> _modGiven = new();

    // ---- mod weapons in recordings ----
    // A recording keeps a mod weapon as "<class>:<subclass>" (weapon_negev:minigun), in the weapons carried at the
    // start and as a purchase when the menu gave it while recording; the bot gets the class turned into the
    // subclass. Which weapon is which mod one: by entity index of what was given (the subclass is not readable
    // back: VData.Name is the base class's), checked against the class in case the index was reused.
    readonly Dictionary<uint, ModWeapon> _modOf = new();

    static (string Base, string? Sub) SplitItem(string item)
    {
        var i = item.IndexOf(':');
        return i < 0 ? (item, null) : (item[..i], item[(i + 1)..]);
    }

    string ItemOf(CBasePlayerWeapon w) =>
        _modOf.TryGetValue(w.Index, out var m) && w.DesignerName == m.Base ? $"{m.Base}:{m.Name}" : w.DesignerName;

    // gives an item of a recording; 0 when the game did not
    nint GiveItem(CCSPlayerController p, string item)
    {
        var (bas, sub) = SplitItem(item);
        var given = p.GiveNamedItem(bas);
        if (given == 0 || sub == null) return given;
        var weapon = new CBasePlayerWeapon(given);
        _modGiven.Add(weapon.Index);
        weapon.AcceptInput("ChangeSubclass", value: sub);
        _modOf[weapon.Index] = _modWeapons.FirstOrDefault(w => w.Name == sub) ?? new ModWeapon("", sub, sub, bas);
        return given;
    }

    void ModWeaponsMenu(CCSPlayerController p)
    {
        var cats = _modWeapons.Select(w => w.Category).Distinct().ToList();
        Show(p, new Menu("Mod weapons", cats.Select(c => new MenuItem($"{c} ›", pl => ModCategoryMenu(pl, c, 0))
        {
            Value = _modWeapons.Count(w => w.Category == c).ToString(),
        }).ToList(), Back: ModulesMenu));
    }

    void ModCategoryMenu(CCSPlayerController p, string category, int page)
    {
        var entries = _modWeapons.Where(w => w.Category == category)
            .Select(w => new MenuItem(w.Title, pl => { GiveModWeapon(pl, w); ModCategoryMenu(pl, category, page); })).ToList();
        ShowPaged(p, category, entries, page, (pl, pg) => ModCategoryMenu(pl, category, pg), ModWeaponsMenu);
    }

    [ConsoleCommand("fm_modgive", "fm_modgive <vdata name> [class it is made on] - give a weapon of a mod (e.g. minigun)")]
    public void CmdModGive(CCSPlayerController? caller, CommandInfo cmd)
    {
        if ((caller ?? LocalHuman()) is not { } p) return;
        var name = cmd.ArgByIndex(1);
        var w = _modWeapons.FirstOrDefault(x => x.Name == name) ?? new ModWeapon("", name, name, cmd.ArgByIndex(2));
        GiveModWeapon(p, w);
    }
}
