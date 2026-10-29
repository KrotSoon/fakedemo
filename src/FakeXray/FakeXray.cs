// FakeXray: bots seen through walls, for practising a move and for recording over running bots.
// Every bot gets a glowing copy of its model (T orange, CT blue) that follows it through a hidden relay
// prop, and is kept "spotted" so the radar shows it. Only the human player is sent the copies: GOTV
// never gets them, so demos show ordinary bots.
// On: J (fx_xray) or the row in FakeMimic's menu; by itself while FakeMimic records a movement or a take.
using System.Drawing;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Core.Capabilities;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Memory;
using CounterStrikeSharp.API.Modules.Utils;
using FakeMimicApi;
using Microsoft.Extensions.Logging;

namespace FakeXray;

public class FakeXray : BasePlugin
{
    public override string ModuleName => "FakeXray";
    public override string ModuleVersion => GetType().Assembly.GetName().Version?.ToString(3) ?? "?";
    public override string ModuleAuthor => "fakedemo";
    public override string ModuleDescription => "Bots seen through walls (not in demos)";

    static readonly PluginCapability<IFakeMimicApi> FakeMimic = new(IFakeMimicApi.Capability);

    sealed class Glow
    {
        public required CBaseModelEntity Relay;
        public required CBaseModelEntity Copy;
        public required CCSPlayerPawn Pawn;
        public required string Model;
    }

    readonly Dictionary<int, Glow> _glows = new();   // by bot slot
    bool _manual;                                     // J / menu row
    int _auto;                                        // FakeMimic recordings and takes running
    int _tick;

    static readonly Color GlowT = Color.FromArgb(255, 255, 150, 40);
    static readonly Color GlowCT = Color.FromArgb(255, 90, 160, 255);

    bool Wanted => _manual || _auto > 0;

    public override void Load(bool hotReload)
    {
        RegisterListener<Listeners.OnMapStart>(_ => { _glows.Clear(); _auto = 0; });
        RegisterListener<Listeners.OnTick>(() =>
        {
            if (++_tick % 8 == 0) Sync();
            Spot();
        });
        RegisterListener<Listeners.CheckTransmit>(infos =>
        {
            if (_glows.Count == 0) return;
            foreach (var (info, player) in infos)
            {
                if (player is { IsValid: true, IsBot: false, IsHLTV: false }) continue;   // the one who plays
                foreach (var g in _glows.Values)
                {
                    info.TransmitEntities.Remove(g.Copy);
                    info.TransmitEntities.Remove(g.Relay);
                }
            }
        });
    }

    public override void OnAllPluginsLoaded(bool hotReload)
    {
        var fm = FakeMimic.Get();
        if (fm == null) return;   // works without FakeMimic: J only
        if (fm.Version != IFakeMimicApi.CurrentVersion)
            Logger.LogWarning("FakeMimic API {Have}, FakeXray was built for {Want}: install matching versions", fm.Version, IFakeMimicApi.CurrentVersion);
        fm.AddMainMenuItem(() => $"See bots through walls: {(_manual ? "on" : "off")}", p =>
        {
            Toggle();
            fm.Say(p, Describe());
            fm.OpenMainMenu(p);
        });
        fm.RecordingStarted += _ => _auto++;
        fm.RecordingStopped += _ => _auto = Math.Max(0, _auto - 1);
        fm.TakeStarted += _ => _auto++;
        fm.TakeStopped += _ => _auto = Math.Max(0, _auto - 1);
    }

    public override void Unload(bool hotReload)
    {
        foreach (var slot in _glows.Keys.ToList()) Remove(slot);
    }

    void Toggle() => _manual = !_manual;

    string Describe() => _manual ? "bots glow through walls (J to turn off)" : "bots glow only while you record or a take runs";

    // a few times a second: glows follow the wanted state, the bots' lives and model changes
    void Sync()
    {
        var keep = new HashSet<int>();
        if (Wanted)
            foreach (var bot in Utilities.GetPlayers().Where(p => p is { IsValid: true, IsBot: true, IsHLTV: false, PawnIsAlive: true }))
            {
                if (bot.PlayerPawn.Value is not { IsValid: true } pawn) continue;
                var model = pawn.CBodyComponent?.SceneNode?.GetSkeletonInstance().ModelState.ModelName ?? "";
                if (model.Length == 0) continue;
                keep.Add(bot.Slot);
                if (_glows.TryGetValue(bot.Slot, out var g) && g.Pawn.IsValid && g.Pawn.Index == pawn.Index && g.Model == model
                    && g.Copy.IsValid && g.Relay.IsValid) continue;
                Remove(bot.Slot);
                var made = Make(pawn, model, bot.TeamNum == 3 ? GlowCT : GlowT);
                if (made != null) _glows[bot.Slot] = made;
            }
        foreach (var slot in _glows.Keys.Where(s => !keep.Contains(s)).ToList()) Remove(slot);
    }

    static Glow? Make(CCSPlayerPawn pawn, string model, Color color)
    {
        var relay = Utilities.CreateEntityByName<CBaseModelEntity>("prop_dynamic");
        var copy = Utilities.CreateEntityByName<CBaseModelEntity>("prop_dynamic");
        if (relay == null || copy == null) return null;
        // SetModel after the spawn (before it the engine asserts; the spawn prints "no model name", harmless)
        relay.Spawnflags = 256u;   // no collisions
        relay.RenderMode = RenderMode_t.kRenderNone;
        relay.DispatchSpawn();
        relay.SetModel(model);
        copy.Spawnflags = 256u;
        copy.DispatchSpawn();
        copy.SetModel(model);
        // after the spawn: the spawn resets m_Glow
        copy.Glow.GlowColorOverride = color;
        copy.Glow.GlowRange = 5000;
        copy.Glow.GlowRangeMin = 0;
        copy.Glow.GlowTeam = -1;
        copy.Glow.GlowType = 3;    // outline through walls
        Utilities.SetStateChanged(copy, "CBaseModelEntity", "m_Glow");
        relay.AcceptInput("FollowEntity", pawn, relay, "!activator");
        copy.AcceptInput("FollowEntity", relay, copy, "!activator");
        return new Glow { Relay = relay, Copy = copy, Pawn = pawn, Model = model };
    }

    void Remove(int slot)
    {
        if (!_glows.Remove(slot, out var g)) return;
        if (g.Copy.IsValid) g.Copy.Remove();
        if (g.Relay.IsValid) g.Relay.Remove();
    }

    // every tick: the game clears "spotted" for bots out of sight, the radar would drop them
    void Spot()
    {
        foreach (var g in _glows.Values)
        {
            if (!g.Pawn.IsValid) continue;
            var st = g.Pawn.EntitySpottedState;
            if (st.Spotted && st.SpottedByMask[0] == uint.MaxValue) continue;
            st.Spotted = true;
            st.SpottedByMask[0] = uint.MaxValue;
            st.SpottedByMask[1] = uint.MaxValue;
            // the fields live in an embedded struct: name them in it, at the struct's offset in the pawn
            var at = Schema.GetSchemaOffset("CCSPlayerPawn", "m_entitySpottedState");
            Utilities.SetStateChanged(g.Pawn, "EntitySpottedState_t", "m_bSpotted", at);
            Utilities.SetStateChanged(g.Pawn, "EntitySpottedState_t", "m_bSpottedByMask", at);
        }
    }

    [ConsoleCommand("fx_xray", "fx_xray - bots through walls on / off (key J)")]
    public void CmdXray(CCSPlayerController? caller, CommandInfo cmd)
    {
        Toggle();
        cmd.ReplyToCommand("[X-ray] " + Describe());
        var p = caller ?? Utilities.GetPlayers().FirstOrDefault(x => x is { IsValid: true, IsBot: false, IsHLTV: false });
        p?.PrintToCenter(_manual ? "X-ray ON" : "X-ray OFF");
    }

    [ConsoleCommand("fx_glows", "fx_glows - glowing copies: where they are (debug)")]
    public void CmdGlows(CCSPlayerController? caller, CommandInfo cmd)
    {
        foreach (var (slot, g) in _glows)
        {
            var o = g.Copy.AbsOrigin;
            cmd.ReplyToCommand($"[X-ray] slot {slot}: copy #{g.Copy.Index} at {o?.X:0},{o?.Y:0},{o?.Z:0} glowtype={g.Copy.Glow.GlowType}");
        }
        if (_glows.Count == 0) cmd.ReplyToCommand("[X-ray] no glows");
    }
}
