using System.Drawing;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Memory;
using CounterStrikeSharp.API.Modules.Utils;

namespace FakeMimic;

// ---------------- x-ray: replay bots seen through walls ----------------
// Recording a movement over running bots needs to know where they are. Each replay bot gets a glowing
// copy of its own model (the outline shows through walls, T orange / CT blue) and is kept "spotted"
// so the radar shows it (CS2 has no mp_radar_showall). The copy follows the bot through a hidden relay prop (FollowEntity on the copy itself
// does not take the animation). Only the human player is sent these props: GOTV never gets them, so
// the demo shows ordinary bots.
// On by itself while a movement is recorded over running bots or a take runs (can be switched off on the
// New movement screen); fm_xray keeps it on all the time, e.g. to watch the bots run.

public partial class FakeMimic
{
    sealed class Glow
    {
        public required CBaseModelEntity Relay;
        public required CBaseModelEntity Copy;
        public required CCSPlayerPawn Pawn;
        public required string Model;
    }

    readonly Dictionary<int, Glow> _glows = new();   // by bot slot
    bool _xrayWhileRecording = true;                  // menu prefs file
    bool _xrayAlways;                                 // fm_xray

    static readonly Color GlowT = Color.FromArgb(255, 255, 150, 40);
    static readonly Color GlowCT = Color.FromArgb(255, 90, 160, 255);

    bool XrayWanted => _xrayAlways || (_xrayWhileRecording && (_recName != null || _take != null) && _replays.Any(r => r.Running));

    void LoadXray()
    {
        RegisterListener<Listeners.CheckTransmit>(infos =>
        {
            if (_glows.Count == 0) return;
            foreach (var (info, player) in infos)
            {
                if (player is { IsValid: true, IsBot: false, IsHLTV: false }) continue;   // the one who records
                foreach (var g in _glows.Values)
                {
                    info.TransmitEntities.Remove(g.Copy);
                    info.TransmitEntities.Remove(g.Relay);
                }
            }
        });
    }

    // OnTick, a few times a second: glows follow the wanted state, the bots' lives and model changes
    void SyncXray()
    {
        var on = XrayWanted;
        var keep = new HashSet<int>();
        if (on)
            foreach (var r in _replays)
            {
                if (r.Bot is not { IsValid: true } bot || bot.PlayerPawn.Value is not { IsValid: true } pawn || !bot.PawnIsAlive) continue;
                var model = pawn.CBodyComponent?.SceneNode?.GetSkeletonInstance().ModelState.ModelName ?? "";
                if (model.Length == 0) continue;
                keep.Add(bot.Slot);
                if (_glows.TryGetValue(bot.Slot, out var g) && g.Pawn.IsValid && g.Pawn.Index == pawn.Index && g.Model == model && g.Copy.IsValid && g.Relay.IsValid) continue;
                RemoveGlow(bot.Slot);
                var made = MakeGlow(pawn, model, bot.TeamNum == 3 ? GlowCT : GlowT);
                if (made != null) _glows[bot.Slot] = made;
            }
        foreach (var slot in _glows.Keys.Where(s => !keep.Contains(s)).ToList()) RemoveGlow(slot);
    }

    static Glow? MakeGlow(CCSPlayerPawn pawn, string model, Color color)
    {
        var relay = Utilities.CreateEntityByName<CBaseModelEntity>("prop_dynamic");
        var copy = Utilities.CreateEntityByName<CBaseModelEntity>("prop_dynamic");
        if (relay == null || copy == null) return null;
        // the model goes on right after the spawn: SetModel before it asserts (entity still in staging);
        // the spawn itself prints "prop_dynamic has no model name", harmless. Spawning with a model key
        // instead left the copy without a visible glow.
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

    void RemoveGlow(int slot)
    {
        if (!_glows.Remove(slot, out var g)) return;
        if (g.Copy.IsValid) g.Copy.Remove();
        if (g.Relay.IsValid) g.Relay.Remove();
    }

    // every tick: the game clears "spotted" for bots out of sight, the radar would drop them
    void SpotGlowing()
    {
        if (_glows.Count == 0) return;
        foreach (var r in _replays)
        {
            if (r.Bot is not { IsValid: true } bot || !_glows.ContainsKey(bot.Slot) || bot.PlayerPawn.Value is not { IsValid: true } pawn) continue;
            var st = pawn.EntitySpottedState;
            if (st.Spotted && st.SpottedByMask[0] == uint.MaxValue) continue;
            st.Spotted = true;
            st.SpottedByMask[0] = uint.MaxValue;
            st.SpottedByMask[1] = uint.MaxValue;
            // the fields live in an embedded struct: name them in it, at the struct's offset in the pawn
            var at = Schema.GetSchemaOffset("CCSPlayerPawn", "m_entitySpottedState");
            Utilities.SetStateChanged(pawn, "EntitySpottedState_t", "m_bSpotted", at);
            Utilities.SetStateChanged(pawn, "EntitySpottedState_t", "m_bSpottedByMask", at);
        }
    }

    // map change: the entities are gone with the map
    void ForgetXray() => _glows.Clear();

    [ConsoleCommand("fm_glows", "fm_glows - glowing copies: where they are (debug)")]
    public void CmdGlows(CCSPlayerController? caller, CommandInfo cmd)
    {
        foreach (var (slot, g) in _glows)
        {
            var o = g.Copy.AbsOrigin; var ro = g.Relay.AbsOrigin;
            var m = g.Copy.CBodyComponent?.SceneNode?.GetSkeletonInstance().ModelState.ModelName;
            cmd.ReplyToCommand($"[FM] slot {slot}: copy #{g.Copy.Index} at {o?.X:0},{o?.Y:0},{o?.Z:0} model={m} glowtype={g.Copy.Glow.GlowType} relay at {ro?.X:0},{ro?.Y:0},{ro?.Z:0}");
        }
        if (_glows.Count == 0) cmd.ReplyToCommand("[FM] no glows");
    }

    [ConsoleCommand("fm_xray", "fm_xray - see the replay bots through walls all the time (again: only while recording over them)")]
    public void CmdXray(CCSPlayerController? caller, CommandInfo cmd)
    {
        _xrayAlways = !_xrayAlways;
        cmd.ReplyToCommand(_xrayAlways ? "[FM] x-ray on: replay bots glow through walls" : "[FM] x-ray only while you record over the bots");
    }
}
