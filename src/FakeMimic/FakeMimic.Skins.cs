// Skins: weapon paints, knives, gloves (and the agent for the player; bots have theirs in "Play on a bot"),
// inside the fake session only (-insecure). The player's choice is Documents\FakeDemo\skins_you.txt, a bot's is
// in the recording's .fme (skins=...), like its model.
// How CS2 takes them (the method of cs2-WeaponPaints, written anew here): the item gets an own item id, the paint
// goes into the Fallback* fields and into the item's two attribute lists ("set item texture prefab/seed/wear",
// added by the game's CAttributeList::SetOrAddAttributeValueByName, found by signature). A knife changes its kind
// with the ChangeSubclass input, gloves are the pawn's EconGloves. The client draws a weapon as it was when it
// appeared, so all of it happens the moment a weapon is created; a change re-gives the weapon.
// skins.txt (next to the plugin, made by the launcher out of the game's items_game.txt) lists what can be chosen.
using System.Globalization;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Memory.DynamicFunctions;
using FakeMimicApi;
using Microsoft.Extensions.Logging;

namespace FakeMimic;

public partial class FakeMimic
{
    // CAttributeList::SetOrAddAttributeValueByName(list, name, value), server.dll, Windows. Breaks with CS2
    // updates now and then: skins_signature.txt next to the plugin overrides it
    const string SetAttributeSignature = "48 89 4C 24 ? 53 41 55 41 56";

    static MemoryFunctionVoid<nint, string, float>? _setAttribute;
    bool _setAttributeFailed;

    // the game takes items with ids above this as ours (real inventory ids are lower)
    ulong _nextItemId = 65578;

    bool SetAttribute(nint list, string name, float value)
    {
        if (_setAttributeFailed) return false;
        try
        {
            if (_setAttribute == null)
            {
                var own = Path.Combine(ModuleDirectory, "skins_signature.txt");
                var sig = File.Exists(own) ? File.ReadAllText(own).Trim() : SetAttributeSignature;
                _setAttribute = new MemoryFunctionVoid<nint, string, float>(sig);
            }
            _setAttribute.Invoke(list, name, value);
            return true;
        }
        catch (Exception e)
        {
            _setAttributeFailed = true;   // once: a wrong signature after a CS2 update must not repeat on every weapon
            Logger.LogError("skins unavailable (signature of SetOrAddAttributeValueByName): {Error}", e.Message);
            return false;
        }
    }

    void NewItemId(CEconItemView item)
    {
        var id = _nextItemId++;
        item.ItemID = id;
        item.ItemIDLow = (uint)(id & 0xFFFFFFFF);
        item.ItemIDHigh = (uint)(id >> 32);
    }

    // paint, seed and wear into both attribute lists of the item (the networked one is what the clients draw)
    void PaintItem(CEconItemView item, int paint, int seed, float wear)
    {
        item.NetworkedDynamicAttributes.Attributes.RemoveAll();
        item.AttributeList.Attributes.RemoveAll();
        foreach (var list in new[] { item.NetworkedDynamicAttributes.Handle, item.AttributeList.Handle })
        {
            SetAttribute(list, "set item texture prefab", paint);
            SetAttribute(list, "set item texture seed", seed);
            SetAttribute(list, "set item texture wear", wear);
        }
    }

    // stat: the StatTrak counter, -1 = no StatTrak
    void PaintWeapon(CBasePlayerWeapon weapon, int paint, float wear, ulong owner, int stat = -1)
    {
        var item = weapon.AttributeManager.Item;
        NewItemId(item);
        item.AccountID = (uint)owner;
        weapon.FallbackPaintKit = paint;
        weapon.FallbackSeed = 0;
        weapon.FallbackWear = wear;
        weapon.FallbackStatTrak = stat;
        PaintItem(item, paint, 0, wear);
        if (stat >= 0)
        {
            // a knife keeps its star quality (3), a gun becomes StatTrak (9); the counter is an int read as float bits
            if (!IsKnife(weapon.DesignerName)) item.EntityQuality = 9;
            foreach (var list in new[] { item.NetworkedDynamicAttributes.Handle, item.AttributeList.Handle })
            {
                SetAttribute(list, "kill eater", BitConverter.Int32BitsToSingle(stat));
                SetAttribute(list, "kill eater score type", 0);
            }
        }
        // painted weapons of the old kind use the other mesh of the model
        weapon.AcceptInput("SetBodygroup", value: $"body,{(_legacyPaints.Contains(paint) ? 1 : 0)}");
    }

    void MakeKnife(CBasePlayerWeapon weapon, ushort defIndex)
    {
        var item = weapon.AttributeManager.Item;
        if (item.ItemDefinitionIndex != defIndex) weapon.AcceptInput("ChangeSubclass", value: defIndex.ToString());
        item.ItemDefinitionIndex = defIndex;
        item.EntityQuality = 3;   // the star of a knife
    }

    void PutGloves(CCSPlayerController p, SkinSet set)
    {
        if (set.Gloves == 0 || p.PlayerPawn.Value is not { IsValid: true } pawn) return;
        var item = pawn.EconGloves;
        item.NetworkedDynamicAttributes.Attributes.RemoveAll();
        item.AttributeList.Attributes.RemoveAll();
        // the game redraws gloves only when the model changes: in third person for a moment, then back
        AddTimer(0.08f, () =>
        {
            if (!p.IsValid || !pawn.IsValid) return;
            item.ItemDefinitionIndex = set.Gloves;
            NewItemId(item);
            PaintItem(item, set.GlovesPaint, 0, set.GlovesWear);
            item.Initialized = true;
            pawn.AcceptInput("SetBodygroup", value: "first_or_third_person,0");
            AddTimer(0.2f, () => { if (pawn.IsValid) pawn.AcceptInput("SetBodygroup", value: "first_or_third_person,1"); });
        });
    }

    // ---------------- the list (skins.txt) ----------------

    record SkinItem(ushort Def, string Weapon, string Name);
    record SkinPaint(int Kit, string Name, string Code, string Only);   // Only: the one knife it was made for

    readonly List<SkinItem> _guns = new(), _knives = new(), _gloves = new();
    readonly Dictionary<ushort, List<SkinPaint>> _gunPaints = new(), _glovePaints = new();
    readonly List<SkinPaint> _knifePaints = new();
    readonly HashSet<int> _legacyPaints = new();
    readonly Dictionary<int, string> _paintNames = new();

    void LoadSkinsList()
    {
        var path = Path.Combine(ModuleDirectory, "skins.txt");
        if (!File.Exists(path)) return;
        foreach (var line in File.ReadAllLines(path))
        {
            var f = line.Split('\t');
            string F(int i) => i < f.Length ? f[i] : "";
            ushort U(int i) => ushort.TryParse(F(i), out var v) ? v : (ushort)0;
            int I(int i) => int.TryParse(F(i), out var v) ? v : 0;
            switch (f[0])
            {
                case "WN": _guns.Add(new(U(1), F(2), F(3))); break;
                case "W":
                    (_gunPaints.TryGetValue(U(1), out var l) ? l : _gunPaints[U(1)] = new()).Add(new(I(3), F(5), F(6), ""));
                    if (F(4) == "1") _legacyPaints.Add(I(3));
                    _paintNames[I(3)] = F(5);
                    break;
                case "K": _knives.Add(new(U(1), F(2), F(3))); break;
                case "KP":
                    _knifePaints.Add(new(I(1), F(3), F(4), F(5)));
                    if (F(2) == "1") _legacyPaints.Add(I(1));
                    _paintNames[I(1)] = F(3);
                    break;
                case "G": _gloves.Add(new(U(1), "", F(2))); break;
                case "GP":
                    (_glovePaints.TryGetValue(U(2), out var g) ? g : _glovePaints[U(2)] = new()).Add(new(I(1), F(3), F(4), ""));
                    _paintNames[I(1)] = F(3);
                    break;
            }
        }
        foreach (var l in _gunPaints.Values.Concat(_glovePaints.Values).Append(_knifePaints)) l.Sort((a, b) => string.CompareOrdinal(a.Name, b.Name));
        Logger.LogInformation("skins: {Guns} weapons, {Knives} knives, {Gloves} gloves", _guns.Count, _knives.Count, _gloves.Count);
    }

    // "Doppler" of phase 2 and "Doppler" of the Black Pearl: the paint's own name tells them apart
    static List<(SkinPaint P, string Shown)> Shown(IEnumerable<SkinPaint> paints)
    {
        var list = paints.ToList();
        var twice = list.GroupBy(p => p.Name).Where(g => g.Count() > 1).Select(g => g.Key).ToHashSet();
        return list.Select(p => (p, twice.Contains(p.Name) ? $"{p.Name} ({Variant(p.Code)})" : p.Name)).ToList();
    }

    static string Variant(string code)
    {
        foreach (var (k, v) in new[] { ("ruby", "Ruby"), ("sapphire", "Sapphire"), ("blackpearl", "Black Pearl"), ("emerald", "Emerald"),
                     ("phase1", "Phase 1"), ("phase2", "Phase 2"), ("phase3", "Phase 3"), ("phase4", "Phase 4"), ("_90", "90") })
            if (code.Contains(k)) return v;
        return code;
    }

    // ---------------- what each one wears ----------------

    class SkinSet
    {
        public Dictionary<ushort, int> Guns = new();   // item definition index -> paint
        public ushort Knife;                           // 0 = the team's own knife
        public int KnifePaint;
        public ushort Gloves;                          // 0 = the agent's own gloves
        public int GlovesPaint;
        public Dictionary<ushort, float> GunWear = new();   // each its own wear (Factory New when missing)
        public float KnifeWear = NewWear, GlovesWear = NewWear;
        public Dictionary<ushort, int> GunStat = new();     // StatTrak counter of a gun (missing = no StatTrak)
        public int KnifeStat = -1;
        public string AgentT = "", AgentCT = "";       // the player's agent ("" = the map's own)

        public bool Empty => Guns.Count == 0 && Knife == 0 && Gloves == 0 && AgentT == "" && AgentCT == "";

        public float WearOf(ushort gun) => GunWear.TryGetValue(gun, out var w) ? w : NewWear;
        public int StatOf(ushort gun) => GunStat.TryGetValue(gun, out var c) ? c : -1;

        // what a bot of a new recording wears: all of it but the agent (a bot's model is chosen in Play on a bot)
        public SkinSet ForBot()
        {
            var b = Parse(ToString());
            (b.AgentT, b.AgentCT) = ("", "");
            return b;
        }

        static string W(float w) => w.ToString(CultureInfo.InvariantCulture);

        // "knife=507:38:0.4[:stat];gloves=5030:10018:0.01;7=282@0.25[@stat];9=344@0.01;agent_t=...;agent_ct=..."
        public override string ToString()
        {
            var parts = new List<string>();
            if (Knife != 0) parts.Add($"knife={Knife}:{KnifePaint}:{W(KnifeWear)}" + (KnifeStat >= 0 ? $":{KnifeStat}" : ""));
            if (Gloves != 0) parts.Add($"gloves={Gloves}:{GlovesPaint}:{W(GlovesWear)}");
            if (AgentT != "") parts.Add($"agent_t={AgentT}");
            if (AgentCT != "") parts.Add($"agent_ct={AgentCT}");
            parts.AddRange(Guns.Select(g => $"{g.Key}={g.Value}@{W(WearOf(g.Key))}" + (StatOf(g.Key) >= 0 ? $"@{StatOf(g.Key)}" : "")));
            return string.Join(";", parts);
        }

        public static SkinSet Parse(string text)
        {
            var s = new SkinSet();
            float? all = null;   // "wear=" of the first version: one wear for everything
            float F(string t) => float.TryParse(t, NumberStyles.Float, CultureInfo.InvariantCulture, out var x) ? x : NewWear;
            foreach (var part in text.Split(';', StringSplitOptions.RemoveEmptyEntries))
            {
                var kv = part.Split('=', 2);
                if (kv.Length != 2) continue;
                var v = kv[1].Split(':');
                ushort U(int i) => i < v.Length && ushort.TryParse(v[i], out var x) ? x : (ushort)0;
                int I(int i) => i < v.Length && int.TryParse(v[i], out var x) ? x : 0;
                switch (kv[0])
                {
                    case "knife":
                        (s.Knife, s.KnifePaint, s.KnifeWear) = (U(0), I(1), v.Length > 2 ? F(v[2]) : all ?? NewWear);
                        s.KnifeStat = v.Length > 3 ? I(3) : -1;
                        break;
                    case "gloves": (s.Gloves, s.GlovesPaint, s.GlovesWear) = (U(0), I(1), v.Length > 2 ? F(v[2]) : all ?? NewWear); break;
                    case "wear": all = F(kv[1]); break;
                    case "agent_t": s.AgentT = kv[1]; break;
                    case "agent_ct": s.AgentCT = kv[1]; break;
                    default:
                        var kw = kv[1].Split('@');
                        if (!ushort.TryParse(kv[0], out var def) || !int.TryParse(kw[0], out var kit)) break;
                        s.Guns[def] = kit;
                        if (kw.Length > 1) s.GunWear[def] = F(kw[1]); else if (all is { } a) s.GunWear[def] = a;
                        if (kw.Length > 2 && int.TryParse(kw[2], out var st)) s.GunStat[def] = st;
                        break;
                }
            }
            return s;
        }
    }

    SkinSet _you = new();
    readonly Dictionary<int, SkinSet> _botSkins = new();   // bot slot -> the set of the recording it plays

    static string YouPath => Path.Combine(FakeDemoPaths.Root, "skins_you.txt");

    // a new recording takes your skins for its bot (Skins › Bots get my skins); off: the bot plays in the
    // standard ones. Kept in skins_bots.txt ("0" = off)
    static string CopyPath => Path.Combine(FakeDemoPaths.Root, "skins_bots.txt");
    bool _copySkins = true;

    // StopRec: the bot of the saved recording wears what you wore while recording it
    string RememberSkins(string rec)
    {
        var bot = _you.ForBot();
        var e = EditsOf(rec);
        e.Skins = _copySkins && !bot.Empty ? bot.ToString() : "";
        e.Save(EditsPathOf(rec));
        return e.Skins == "" ? "" : ", with your skins";
    }

    SkinSet? SetOf(CCSPlayerController p) => !p.IsBot ? _you : _botSkins.TryGetValue(p.Slot, out var s) ? s : null;

    static bool IsKnife(string designer) => designer.Contains("knife") || designer.Contains("bayonet");

    void InitSkins()
    {
        LoadSkinsList();
        try { if (File.Exists(YouPath)) _you = SkinSet.Parse(File.ReadAllText(YouPath).Trim()); } catch { }
        try { _copySkins = !File.Exists(CopyPath) || File.ReadAllText(CopyPath).Trim() != "0"; } catch { }
        RegisterEventHandler<EventPlayerDeath>((ev, _) => { CountKill(ev.Attacker, ev.Userid); return HookResult.Continue; });
        RegisterListener<Listeners.OnEntitySpawned>(entity =>
        {
            if ((_you.Empty && _botSkins.Count == 0) || entity.DesignerName?.StartsWith("weapon_") != true) return;
            // the owner is set right after the spawn. Looked up again by index then, not through the pointer:
            // while a map loads many weapons are gone by the next update, and reading a freed one crashed the game
            var index = entity.Index;
            var designer = entity.DesignerName;
            Server.NextWorldUpdate(() =>
            {
                var weapon = Utilities.GetEntityFromIndex<CBasePlayerWeapon>((int)index);
                if (weapon is not { IsValid: true } || weapon.DesignerName != designer) return;
                if (weapon.OwnerEntity.Value?.As<CCSPlayerPawn>() is not { IsValid: true } pawn) return;
                if (pawn.Controller.Value?.As<CCSPlayerController>() is { IsValid: true } p) DressWeapon(p, weapon);
            });
        });
        RegisterEventHandler<EventPlayerSpawn>((ev, _) =>
        {
            // bots get theirs from Go(), with the recording's model
            if (ev.Userid is { IsValid: true, IsBot: false } p) AddTimer(ModelDelay, () => { if (p.IsValid) { PutGloves(p, _you); PutAgent(p); } });
            return HookResult.Continue;
        });
    }

    void DressWeapon(CCSPlayerController p, CBasePlayerWeapon weapon)
    {
        if (SetOf(p) is not { } set) return;
        if (IsKnife(weapon.DesignerName))
        {
            if (set.Knife == 0) return;
            MakeKnife(weapon, set.Knife);
            if (set.KnifePaint != 0) PaintWeapon(weapon, set.KnifePaint, set.KnifeWear, p.SteamID, set.KnifeStat);
            else NewItemId(weapon.AttributeManager.Item);
        }
        else if (set.Guns.TryGetValue(weapon.AttributeManager.Item.ItemDefinitionIndex, out var paint))
        {
            // a plain item: with the quality it came with the HUD called the gun "StatTrak™"
            weapon.AttributeManager.Item.EntityQuality = 0;
            var def = weapon.AttributeManager.Item.ItemDefinitionIndex;
            PaintWeapon(weapon, paint, set.WearOf(def), p.SteamID, set.StatOf(def));
        }
    }

    // StatTrak counts: a kill with the gun or knife in hand that has one adds 1 on the weapon at once (the
    // attribute is networked, the counter on the model follows). Yours is saved; a bot's starts each run from
    // its recording's number, so every take shows the same
    void CountKill(CCSPlayerController? attacker, CCSPlayerController? victim)
    {
        if (attacker is not { IsValid: true } || attacker == victim || SetOf(attacker) is not { } set) return;
        var weapon = attacker.PlayerPawn.Value?.WeaponServices?.ActiveWeapon.Value;
        if (weapon is not { IsValid: true }) return;
        int count;
        if (IsKnife(weapon.DesignerName))
        {
            if (set.Knife == 0 || set.KnifeStat < 0) return;
            count = ++set.KnifeStat;
        }
        else
        {
            var def = weapon.AttributeManager.Item.ItemDefinitionIndex;
            if (!set.Guns.ContainsKey(def) || set.StatOf(def) < 0) return;
            count = set.GunStat[def] = set.StatOf(def) + 1;
        }
        weapon.FallbackStatTrak = count;
        var item = weapon.AttributeManager.Item;
        foreach (var list in new[] { item.NetworkedDynamicAttributes.Handle, item.AttributeList.Handle })
            SetAttribute(list, "kill eater", BitConverter.Int32BitsToSingle(count));
        if (!attacker.IsBot) Save(null, set);
    }

    // a bot of a recording: its set before it gets its weapons (Go: ModelDelay, then WeaponsDelay)
    void ApplySkins(CCSPlayerController bot, RecordingEdits e)
    {
        if (!bot.IsValid) return;
        if (string.IsNullOrEmpty(e.Skins)) { _botSkins.Remove(bot.Slot); return; }
        var set = _botSkins[bot.Slot] = SkinSet.Parse(e.Skins);
        PutGloves(bot, set);
    }

    void PutAgent(CCSPlayerController p)
    {
        var model = p.TeamNum == 3 ? _you.AgentCT : _you.AgentT;
        if (model != "" && p.PlayerPawn.Value is { IsValid: true } pawn) pawn.SetModel(model);
    }

    // the weapon again, so it is created with the paint (and stays in hand when it was)
    void Regive(CCSPlayerController p, CBasePlayerWeapon weapon)
    {
        var ws = p.PlayerPawn.Value?.WeaponServices;
        var active = ws?.ActiveWeapon.Value?.Handle == weapon.Handle;
        var name = IsKnife(weapon.DesignerName) ? (p.TeamNum == 3 ? "weapon_knife" : "weapon_knife_t") : weapon.DesignerName;
        var clip = weapon.Clip1;
        weapon.Remove();
        var given = p.GiveNamedItem(name);
        Server.NextFrame(() =>
        {
            if (!p.IsValid) return;
            var w = given != 0 ? new CBasePlayerWeapon(given) : null;
            if (w is { IsValid: true } && !IsKnife(name)) w.Clip1 = clip;
            if (active) p.ExecuteClientCommand(IsKnife(name) ? "slot3" : Pistols.Contains(name) ? "slot2" : "slot1");
        });
    }

    // a change shows at once on whoever wears this set now: you, or the bot that plays the recording
    void Refresh(string? rec, Func<CBasePlayerWeapon, bool> which, bool gloves = false)
    {
        var who = rec == null
            ? new[] { LocalHuman() }
            : _replays.Where(r => r.Name == rec).Select(r => r.Bot).ToArray();
        foreach (var p in who)
        {
            if (p is not { IsValid: true, PawnIsAlive: true }) continue;
            if (rec != null) ApplySkins(p, EditsOf(rec));
            if (gloves) PutGloves(p, SetOf(p) ?? new SkinSet());
            var weapons = p.PlayerPawn.Value?.WeaponServices?.MyWeapons.Select(h => h.Value).Where(w => w is { IsValid: true } && which(w!)).ToList();
            foreach (var w in weapons ?? new()) Regive(p, w!);
        }
    }

    SkinSet Load(string? rec) => rec == null ? _you : SkinSet.Parse(EditsOf(rec).Skins);

    void Save(string? rec, SkinSet set)
    {
        if (rec == null)
        {
            _you = set;
            Directory.CreateDirectory(FakeDemoPaths.Root);
            File.WriteAllText(YouPath, set.ToString());
            return;
        }
        var e = EditsOf(rec);
        e.Skins = set.Empty ? "" : set.ToString();
        e.Save(EditsPathOf(rec));
        Reload(rec);
    }

    // ---------------- menus ----------------
    // Skins (yours from the main menu, a bot's from its movement): weapons, knife, gloves, wear, your agent

    // plain words on the buttons (FN / MW ... read as nothing to someone new), the game's own name of the chosen one beside the title
    static readonly (string Name, string Full, float Wear)[] Wears =
    {
        ("New", "Factory New", 0.01f), ("Light", "Minimal Wear", 0.1f), ("Used", "Field-Tested", 0.25f),
        ("Worn", "Well-Worn", 0.4f), ("Scarred", "Battle-Scarred", 0.7f),
    };
    const float NewWear = 0.01f;

    static int WearIndex(float wear) => Math.Max(0, Array.FindIndex(Wears, w => Math.Abs(w.Wear - wear) < 0.001f));

    // StatTrak: Off / On, and the number on the counter (asked when it is switched on or the value is clicked)
    MenuItem StatRow(int stat, Action<CCSPlayerController, int> set) => new("StatTrak™", _ => { })
    {
        Kind = ApiRowKind.Choice, Options = new[] { "Off", "On" }, Selected = stat >= 0 ? 1 : 0,
        Value = stat >= 0 ? $"{stat} kills" : "",
        Choose = (pl, i) =>
        {
            if (i == 0) { set(pl, -1); return; }
            AskText(pl, "kills on the counter (0-999999)", (pl2, t) => set(pl2, int.TryParse(t, out var n) ? Math.Clamp(n, 0, 999999) : 0));
        },
    };

    // on the screen of one weapon / knife / gloves, once it has a skin
    static MenuItem WearRow(float wear, Action<CCSPlayerController, float> pick) => new("Skin wear", _ => { })
    {
        Kind = ApiRowKind.Choice, Options = Wears.Select(w => w.Name).ToList(), Selected = WearIndex(wear),
        Value = Wears[WearIndex(wear)].Full, Divider = true,
        Choose = (pl, i) => pick(pl, Wears[i].Wear),
    };

    string Whose(string? rec) => rec == null ? "your" : $"'{rec}'";

    void SkinsMenu(CCSPlayerController p, string? rec)
    {
        if (_guns.Count == 0) { Say(p, "no skins list (skins.txt): start the game from the FakeDemo launcher"); return; }
        if (_setAttributeFailed) Say(p, "skins do not work in this CS2 version yet (signature), see the log");
        var set = Load(rec);
        var items = new List<MenuItem>();
        // yours: a row for each gun you carry, the one in hand first (the whole list is behind "All weapons");
        // a bot has nothing to look at, it gets the list
        if (rec == null)
        {
            var carried = GunsCarried(p);
            foreach (var gun in carried)
                items.Add(new($"{gun.Name} ›", pl => GunPaintsMenu(pl, rec, gun, 0, inHand: true)) { Value = GunValue(set, gun) });
            if (carried.Count == 0)
                items.Add(new("No guns on you", pl => Say(pl, "pick up or buy a gun and open Skins again; or All weapons")) { Faded = true });
        }
        items.Add(new(rec == null ? "All weapons ›" : "Weapons ›", pl => GunsMenu(pl, rec, 0))
        {
            Value = set.Guns.Count > 0 ? $"{set.Guns.Count} set" : "", Divider = rec == null,
        });
        items.Add(new("Knife ›", pl => KnivesMenu(pl, rec, 0)) { Value = set.Knife == 0 ? "default" : KnifeName(set) });
        items.Add(new("Gloves ›", pl => GlovesMenu(pl, rec)) { Value = set.Gloves == 0 ? "default" : GlovesName(set) });
        if (rec == null)
        {
            items.Add(new("Agent ›", pl => AgentTeamMenu(pl)) { Value = set.AgentT == "" && set.AgentCT == "" ? "default" : "set" });
            items.Add(new("Bots get my skins", _ => { })
            {
                Kind = ApiRowKind.Choice, Options = new[] { "Off", "On" }, Selected = _copySkins ? 1 : 0, Value = "new movements",
                Choose = (pl, i) =>
                {
                    _copySkins = i == 1;
                    try { Directory.CreateDirectory(FakeDemoPaths.Root); File.WriteAllText(CopyPath, _copySkins ? "1" : "0"); } catch { }
                    Say(pl, _copySkins ? "a new movement's bot wears your skins (weapons, knife, gloves)" : "a new movement's bot wears the standard skins");
                    SkinsMenu(pl, rec);
                },
            });
        }
        items.Add(new("Reset all", pl =>
        {
            Save(rec, new SkinSet());
            Refresh(rec, _ => true, gloves: true);
            Say(pl, $"{Whose(rec)} skins reset (gloves and agent: on the next spawn)");
            SkinsMenu(pl, rec);
        }, Accent: true));
        Show(p, new Menu(rec == null ? "Your skins" : $"Skins of '{rec}'", items, Back: rec == null ? MainMenu : pl => RecordingMenu(pl, rec)));
    }

    string KnifeName(SkinSet s) =>
        (_knives.FirstOrDefault(k => k.Def == s.Knife)?.Name ?? s.Knife.ToString()) + (s.KnifePaint != 0 && _paintNames.TryGetValue(s.KnifePaint, out var n) ? $" | {n}" : "");

    string GlovesName(SkinSet s) =>
        (_gloves.FirstOrDefault(g => g.Def == s.Gloves)?.Name ?? s.Gloves.ToString()) + (_paintNames.TryGetValue(s.GlovesPaint, out var n) ? $" | {n}" : "");

    // the guns with skins that the player has, in slot order: main gun, then pistol (or Zeus); two, so the screen fits
    List<SkinItem> GunsCarried(CCSPlayerController p)
    {
        var ws = p.PlayerPawn.Value?.WeaponServices;
        if (ws == null) return new();
        return ws.MyWeapons.Select(h => h.Value).Where(w => w is { IsValid: true })
            .Select(w => _guns.FirstOrDefault(g => g.Def == w!.AttributeManager.Item.ItemDefinitionIndex))
            .OfType<SkinItem>().DistinctBy(g => g.Def)
            .OrderBy(g => g.Weapon == "weapon_taser" ? 2 : Pistols.Contains(g.Weapon) ? 1 : 0)
            .Take(2).ToList();
    }

    // "Redline · Worn"
    string GunValue(SkinSet set, SkinItem g) =>
        set.Guns.TryGetValue(g.Def, out var kit) && _paintNames.TryGetValue(kit, out var n) ? $"{n} · {Wears[WearIndex(set.WearOf(g.Def))].Name}" : "default";

    void GunsMenu(CCSPlayerController p, string? rec, int page)
    {
        var set = Load(rec);
        var entries = _guns.Select(g => new MenuItem($"{g.Name} ›", pl => GunPaintsMenu(pl, rec, g, 0))
        {
            Value = set.Guns.ContainsKey(g.Def) ? GunValue(set, g) : "",
        }).ToList();
        ShowPaged(p, $"Weapons: {Whose(rec)}", entries, page, (pl, pg) => GunsMenu(pl, rec, pg), pl => SkinsMenu(pl, rec));
    }

    void SetGun(CCSPlayerController p, string? rec, SkinItem gun, int kit)
    {
        var set = Load(rec);
        if (kit == 0) { set.Guns.Remove(gun.Def); set.GunWear.Remove(gun.Def); set.GunStat.Remove(gun.Def); } else set.Guns[gun.Def] = kit;
        Save(rec, set);
        Refresh(rec, w => w.AttributeManager.Item.ItemDefinitionIndex == gun.Def);
        Say(p, $"{gun.Name}: {(kit == 0 ? "default" : _paintNames.GetValueOrDefault(kit, kit.ToString()))}");
    }

    // the skins of one gun: wear (once it has one), search in them, Default, then the skins.
    // inHand: opened from "In hand" (Back goes to Skins, not to the list); text: only the skins with it
    void GunPaintsMenu(CCSPlayerController p, string? rec, SkinItem gun, int page, bool inHand = false, string text = "")
    {
        var set = Load(rec);
        var cur = set.Guns.GetValueOrDefault(gun.Def);
        void Again(CCSPlayerController pl, int pg) => GunPaintsMenu(pl, rec, gun, pg, inHand, text);
        var entries = new List<MenuItem>();
        if (cur != 0)
            entries.Add(WearRow(set.WearOf(gun.Def), (pl, w) =>
            {
                var s = Load(rec); s.GunWear[gun.Def] = w; Save(rec, s);
                Refresh(rec, x => x.AttributeManager.Item.ItemDefinitionIndex == gun.Def);
                Again(pl, 0);
            }));
        if (cur != 0)
            entries.Add(StatRow(set.StatOf(gun.Def), (pl, c) =>
            {
                var s = Load(rec);
                if (c < 0) s.GunStat.Remove(gun.Def); else s.GunStat[gun.Def] = c;
                Save(rec, s);
                Refresh(rec, x => x.AttributeManager.Item.ItemDefinitionIndex == gun.Def);
                Again(pl, 0);
            }));
        var paints = Shown(_gunPaints.GetValueOrDefault(gun.Def) ?? new())
            .Where(x => text == "" || x.Shown.Contains(text, StringComparison.OrdinalIgnoreCase)).ToList();
        entries.Add(text == ""
            ? new("Search…", pl => AskText(pl, $"{gun.Name} skin (part of the name)", (pl2, t) => GunPaintsMenu(pl2, rec, gun, 0, inHand, t), raw: true))
            : new($"Search: '{text}' ({paints.Count}) ✕", pl => GunPaintsMenu(pl, rec, gun, 0, inHand)));
        if (text == "") entries.Add(new("Default", pl => { SetGun(pl, rec, gun, 0); Again(pl, page); }) { On = cur == 0 });
        entries.AddRange(paints.Select(x => new MenuItem(x.Shown, pl => { SetGun(pl, rec, gun, x.P.Kit); Again(pl, page); }) { On = cur == x.P.Kit }));
        ShowPaged(p, $"{gun.Name}: {Whose(rec)}", entries, page, Again, inHand ? pl => SkinsMenu(pl, rec) : pl => GunsMenu(pl, rec, 0));
    }

    void KnivesMenu(CCSPlayerController p, string? rec, int page)
    {
        var set = Load(rec);
        var entries = new List<MenuItem>
        {
            new("Default", pl =>
            {
                var s = Load(rec); (s.Knife, s.KnifePaint) = (0, 0); Save(rec, s);
                Refresh(rec, w => IsKnife(w.DesignerName));
                KnivesMenu(pl, rec, page);
            }) { On = set.Knife == 0 },
        };
        entries.AddRange(_knives.Select(k => new MenuItem($"{k.Name} ›", pl => KnifePaintsMenu(pl, rec, k, 0)) { On = set.Knife == k.Def }));
        ShowPaged(p, $"Knife: {Whose(rec)}", entries, page, (pl, pg) => KnivesMenu(pl, rec, pg), pl => SkinsMenu(pl, rec));
    }

    void KnifePaintsMenu(CCSPlayerController p, string? rec, SkinItem knife, int page)
    {
        var set = Load(rec);
        void Pick(CCSPlayerController pl, int kit)
        {
            var s = Load(rec); (s.Knife, s.KnifePaint) = (knife.Def, kit); Save(rec, s);
            Refresh(rec, w => IsKnife(w.DesignerName));
            Say(pl, $"knife: {KnifeName(s)}");
            KnifePaintsMenu(pl, rec, knife, page);
        }
        var mine = set.Knife == knife.Def;
        var entries = new List<MenuItem>();
        if (mine && set.KnifePaint != 0)
            entries.Add(WearRow(set.KnifeWear, (pl, w) =>
            {
                var s = Load(rec); s.KnifeWear = w; Save(rec, s);
                Refresh(rec, x => IsKnife(x.DesignerName));
                KnifePaintsMenu(pl, rec, knife, 0);
            }));
        if (mine && set.KnifePaint != 0)
            entries.Add(StatRow(set.KnifeStat, (pl, c) =>
            {
                var s = Load(rec); s.KnifeStat = c; Save(rec, s);
                Refresh(rec, x => IsKnife(x.DesignerName));
                KnifePaintsMenu(pl, rec, knife, 0);
            }));
        entries.Add(new("Vanilla", pl => Pick(pl, 0)) { On = mine && set.KnifePaint == 0 });
        // the classic finishes, then the ones made for this knife
        entries.AddRange(Shown(_knifePaints.Where(k => k.Only == "" || k.Only == knife.Weapon))
            .OrderBy(x => x.P.Only == "" ? 0 : 1).ThenBy(x => x.Shown)
            .Select(x => new MenuItem(x.Shown, pl => Pick(pl, x.P.Kit)) { On = mine && set.KnifePaint == x.P.Kit }));
        ShowPaged(p, knife.Name, entries, page, (pl, pg) => KnifePaintsMenu(pl, rec, knife, pg), pl => KnivesMenu(pl, rec, 0));
    }

    void GlovesMenu(CCSPlayerController p, string? rec)
    {
        var set = Load(rec);
        var entries = new List<MenuItem>
        {
            new("Default", pl =>
            {
                var s = Load(rec); (s.Gloves, s.GlovesPaint) = (0, 0); Save(rec, s);
                Say(pl, "gloves: the agent's own from the next spawn");
                GlovesMenu(pl, rec);
            }) { On = set.Gloves == 0 },
        };
        entries.AddRange(_gloves.Select(g => new MenuItem($"{g.Name} ›", pl => GlovePaintsMenu(pl, rec, g, 0)) { On = set.Gloves == g.Def }));
        ShowPaged(p, $"Gloves: {Whose(rec)}", entries, 0, (pl, _) => GlovesMenu(pl, rec), pl => SkinsMenu(pl, rec));
    }

    void GlovePaintsMenu(CCSPlayerController p, string? rec, SkinItem glove, int page)
    {
        var set = Load(rec);
        var entries = new List<MenuItem>();
        if (set.Gloves == glove.Def)
            entries.Add(WearRow(set.GlovesWear, (pl, w) =>
            {
                var s = Load(rec); s.GlovesWear = w; Save(rec, s);
                Refresh(rec, _ => false, gloves: true);
                GlovePaintsMenu(pl, rec, glove, 0);
            }));
        entries.AddRange(Shown(_glovePaints.GetValueOrDefault(glove.Def) ?? new()).Select(x => new MenuItem(x.Shown, pl =>
        {
            var s = Load(rec); (s.Gloves, s.GlovesPaint) = (glove.Def, x.P.Kit); Save(rec, s);
            Refresh(rec, _ => false, gloves: true);
            Say(pl, $"gloves: {GlovesName(s)}");
            GlovePaintsMenu(pl, rec, glove, page);
        }) { On = set.Gloves == glove.Def && set.GlovesPaint == x.P.Kit }));
        ShowPaged(p, glove.Name, entries, page, (pl, pg) => GlovePaintsMenu(pl, rec, glove, pg), pl => GlovesMenu(pl, rec));
    }

    // your agent: one for each team (the bots' models are in Movements › a movement › Play on a bot)
    void AgentTeamMenu(CCSPlayerController p)
    {
        Show(p, new Menu("Your agent", new List<MenuItem>
        {
            new("Terrorist ›", pl => AgentFactionsMenu(pl, "t")) { Value = _you.AgentT == "" ? "default" : ModelName(_you.AgentT) },
            new("Counter-Terrorist ›", pl => AgentFactionsMenu(pl, "ct")) { Value = _you.AgentCT == "" ? "default" : ModelName(_you.AgentCT) },
        }, Back: pl => SkinsMenu(pl, null)));
    }

    void SetAgent(CCSPlayerController p, string team, string model)
    {
        var s = Load(null);
        if (team == "t") s.AgentT = model; else s.AgentCT = model;
        Save(null, s);
        if (model == "") Say(p, "agent: the map's own from the next spawn");
        else { PutAgent(p); Say(p, $"agent ({team.ToUpper()}): {ModelName(model)}"); }
        AgentTeamMenu(p);
    }

    void AgentFactionsMenu(CCSPlayerController p, string team)
    {
        var teamNum = team == "t" ? 2 : 3;
        var cards = new List<(ApiCard, Action<CCSPlayerController>)> { (new ApiCard(DefaultPortrait, teamNum, "Default", "map's own"), pl => SetAgent(pl, team, "")) };
        foreach (var f in _models.Select(FactionOf).Distinct().Where(f => FactionFits(f, team)))
        {
            var variants = _models.Where(m => FactionOf(m) == f).ToList();
            cards.Add((new ApiCard(variants[0], teamNum, FactionName(f), $"{variants.Count} variants"), pl => AgentVariantsMenu(pl, team, f)));
        }
        Show(p, new Menu($"Your {(team == "t" ? "T" : "CT")} agent", CardRows(cards), Back: AgentTeamMenu));
    }

    void AgentVariantsMenu(CCSPlayerController p, string team, string faction)
    {
        var teamNum = team == "t" ? 2 : 3;
        var cards = _models.Where(m => FactionOf(m) == faction)
            .Select(m => (new ApiCard(m, teamNum, ModelName(m), ""), (Action<CCSPlayerController>)(pl => SetAgent(pl, team, m)))).ToList();
        Show(p, new Menu(FactionName(faction), CardRows(cards), Back: pl => AgentFactionsMenu(pl, team)));
    }

    [ConsoleCommand("fm_skins", "fm_skins - your skins menu")]
    public void CmdSkins(CCSPlayerController? caller, CommandInfo cmd)
    {
        if ((caller ?? LocalHuman()) is { } p) SkinsMenu(p, null);
    }
}
