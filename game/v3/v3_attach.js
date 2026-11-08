"use strict";
{
    // =====================================================================
    //  v3_attach.js  -  camera attached to a player / object (HLAE mirv-script)
    //  Loaded by v3_attach.cfg. Commands: ac ac_list ac_p ac_o ac_look ac_off ac_rot ac_smooth ac_fov ac_preset ac_print ac_view ac_mode
    // =====================================================================
    const ID = 'v3_attach';
    const VIEW_ID = ID + '/view';

    // ---- clean reload ----
    if (globalThis[ID] !== undefined) {
        for (const c of globalThis[ID].commands) { try { c.unregister(); } catch (e) { } }
        delete globalThis[ID];
    }
    mirv.events.cViewRenderSetupView.off(VIEW_ID);
    mirv.events.cViewRenderSetupView.off(ID + '/sm');
    mirv.events.cViewRenderSetupView.off(ID + '/sens');

    const msg =(s) => mirv.message('[ac] ' + s + '\n');
    const warn = (s) => mirv.warning('[ac] ' + s + '\n');

    // ---- settings (what presets change) ----
    const OBJECTS = ['eye', 'body', 'hand', 'handl', 'gun', 'nade', 'drop', 'c4', 'ent'];
    const LOOKS = ['auto', 'obj', 'level', 'flat', 'eye', 'vel'];
    const AUTO_LOOK = { eye: 'eye', body: 'flat', hand: 'eye', handl: 'eye', gun: 'eye', nade: 'vel', drop: 'vel', c4: 'flat', ent: 'vel' };

    const cfg = {
        obj: 'gun', look: 'auto',
        off: [0, 0, 0],      // forward right up, in the camera frame of the chosen look
        rot: [0, 0, 0],      // extra pitch yaw roll, relative to that frame
        sPos: 0.05, sRot: 0.08, // smoothing time constants, seconds (0 = off)
        fov: 0,              // 0 = do not touch fov
        pmax: 89,            // max pitch (up/down tilt) the camera takes over from the object/player
        autoView: 1          // on ac on -> spec_mode 4 + r_drawviewmodel 0, so CS2 does not hide the body / draw the viewmodel near the eyes
    };
    // ---- runtime state ----
    const st = {
        active: false,
        player: 'spec',      // 'spec' or controller index
        entIndex: -1,        // for obj 'ent'
        has: false, pos: [0, 0, 0], q: null,
        lastCur: null, lastWall: null, lastTick: null,
        lastTarget: null,    // raw target position (for velocity / cut detection)
        vel: [1, 0, 0],
        recording: false,
        weaponHist: [],      // recent weapon handles of the player (for 'drop')
        lastWeapon: null,
        nadeIdx: -1, knownNades: new Set(), frame: 0,
        gunPoint: {},        // weapon class -> attachment name that works
        missing: false
    };

    // ---- math (Source conventions: x forward, y left, z up; angles pitch yaw roll in degrees) ----
    const D = Math.PI / 180;
    const basis = (p, y, r) => {
        const sp = Math.sin(p * D), cp = Math.cos(p * D), sy = Math.sin(y * D), cy = Math.cos(y * D), sr = Math.sin(r * D), cr = Math.cos(r * D);
        const f = [cp * cy, cp * sy, -sp];
        const rt = [-sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp];
        const u = [cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp];
        return { f, l: [-rt[0], -rt[1], -rt[2]], u };
    };
    const fromBasis = (b) => {
        const f = b.f, l = b.l, u = b.u;
        const xy = Math.sqrt(f[0] * f[0] + f[1] * f[1]);
        if (xy > 0.001) return [Math.atan2(-f[2], xy) / D, Math.atan2(f[1], f[0]) / D, Math.atan2(l[2], u[2]) / D];
        return [Math.atan2(-f[2], xy) / D, Math.atan2(-l[0], l[1]) / D, 0];
    };
    // rotate local vector v=(a,b,c) given in basis B (f,l,u) to world
    const toWorld = (B, a, b, c) => [B.f[0] * a + B.l[0] * b + B.u[0] * c, B.f[1] * a + B.l[1] * b + B.u[1] * c, B.f[2] * a + B.l[2] * b + B.u[2] * c];
    // compose: angles of (B * extra rotation in local frame)
    const compose = (ang, extra) => {
        if (!extra[0] && !extra[1] && !extra[2]) return ang;
        const B = basis(ang[0], ang[1], ang[2]), E = basis(extra[0], extra[1], extra[2]);
        return fromBasis({ f: toWorld(B, E.f[0], E.f[1], E.f[2]), l: toWorld(B, E.l[0], E.l[1], E.l[2]), u: toWorld(B, E.u[0], E.u[1], E.u[2]) });
    };
    const quat = (a) => AdvancedfxMathQuaternion.fromQREulerAngles(AdvancedfxMathQREulerAngles.fromQEulerAngles(new AdvancedfxMathQEulerAngles(a[0], a[1], a[2])));
    const qAngles = (q) => { const e = q.toQREulerAngles().toQEulerAngles(); return [e.pitch, e.yaw, e.roll]; };
    const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    const vecAngles = (v) => { const xy = Math.hypot(v[0], v[1]); return [Math.atan2(-v[2], xy) / D, Math.atan2(v[1], v[0]) / D, 0]; };
    const P3 = (o) => Array.isArray(o) ? [o[0], o[1], o[2]] : (typeof o === 'string' ? o.split(',').map(Number) : [o.x, o.y, o.z]);

    // ---- entities ----
    // entities can be half-destroyed during round restarts / spectator switches: always check isValid()
    const alive = (e) => { try { return !!e && e.isValid(); } catch (x) { return false; } };
    const ent = (h) => {
        if (h === undefined || h === null || !mirv.isHandleValid(h)) return null;
        const e = mirv.getEntityFromIndex(mirv.getHandleEntryIndex(h));
        return alive(e) ? e : null;
    };
    const controllers = () => {
        const res = [];
        for (let i = 1; i <= 64; i++) {
            const c = mirv.getEntityFromIndex(i);
            if (!alive(c) || !c.isPlayerController()) continue;
            const h = c.getPlayerPawnHandle();
            const pawn = ent(h);
            const ok = pawn && pawn.isPlayerPawn() && pawn.getHealth() > 0;
            res.push({ idx: i, name: c.getSanitizedPlayerName(), team: c.getTeam(), pawn: ok ? pawn : null, pawnIdx: ok ? mirv.getHandleEntryIndex(h) : -1 });
        }
        return res;
    };
    // entity index of the controller's current pawn (-1 = none)
    const ctrlPawnIdx = (i) => {
        const c = mirv.getEntityFromIndex(i);
        if (!alive(c) || !c.isPlayerController()) return -1;
        const h = c.getPlayerPawnHandle();
        return mirv.isHandleValid(h) ? mirv.getHandleEntryIndex(h) : -1;
    };
    // entity index of the watched player's pawn (-1 = none)
    const specPawnIdx = () => {
        const c = mirv.getEntityFromSplitScreenPlayer(0);
        const p = c ? ent(c.getPlayerPawnHandle()) : null;
        const h = p ? p.getObserverTargetHandle() : null;
        if (h !== null && mirv.isHandleValid(h)) {
            const idx = mirv.getHandleEntryIndex(h);
            if (st.lastSpecCtrl === undefined || ctrlPawnIdx(st.lastSpecCtrl) !== idx)
                for (let i = 1; i <= 64; i++) if (ctrlPawnIdx(i) === idx) { st.lastSpecCtrl = i; break; }
            return idx;
        }
        // free camera (F / autoView) has no watched player: keep the last player (his controller, the pawn
        // changes every round / respawn)
        return st.lastSpecCtrl !== undefined ? ctrlPawnIdx(st.lastSpecCtrl) : -1;
    };
    const playerPawnIdx = () => {
        if (st.player === 'spec') return specPawnIdx();
        return ctrlPawnIdx(st.player);
    };
    const playerPawn = () => {
        const i = playerPawnIdx();
        const p = i >= 0 ? mirv.getEntityFromIndex(i) : null;
        // dead players (ragdolls) are skipped: the camera holds its last view
        return alive(p) && p.isPlayerPawn() && p.getHealth() > 0 ? p : null;
    };
    const attAng = (a) => { const e = a.angles.toQREulerAngles().toQEulerAngles(); return [e.pitch, e.yaw, e.roll]; };
    const gunAttachment = (pawn) => {
        const w = ent(pawn.getActiveWeaponHandle());
        if (w) {
            const cls = w.getDebugName();
            const known = st.gunPoint[cls];
            const names = known ? [known] : ['muzzle_flash', 'muzzle', 'shell_eject', 'weapon_hand_r'];
            for (const n of names) {
                const a = w.getAttachment(n);
                if (a) { st.gunPoint[cls] = n; return a; }
            }
            st.gunPoint[cls] = undefined;
        }
        return pawn.getAttachment('weapon_hand_r'); // knife, R8 and others without a muzzle point
    };
    const trackWeapons = (pawn) => {
        const h = pawn.getActiveWeaponHandle();
        const key = mirv.isHandleValid(h) ? mirv.getHandleEntryIndex(h) + ':' + mirv.getHandleSerialNumber(h) : null;
        if (key !== st.lastWeapon) {
            if (st.lastWeapon !== null && st.lastWeaponH !== undefined) {
                st.weaponHist.unshift(st.lastWeaponH);
                if (st.weaponHist.length > 8) st.weaponHist.pop();
            }
            st.lastWeapon = key; st.lastWeaponH = h;
        }
    };
    // grenade in flight: class C_BaseGrenade, debug name hegrenade_projectile / smokegrenade_projectile / ...
    // (the held grenade is weapon_*grenade)
    const isNade = (e) => { try { return /_projectile$/i.test(e.getDebugName()); } catch (x) { return false; } };
    // a grenade's origin is not drawn-smooth, and players are drawn at curTime, so draw the grenade at curTime too:
    // - slow speed (several frames per tick): the origin wobbles inside every tick. One sample per demo tick, taken
    //   on the first frame of that tick (same phase every tick = same error, which does not shake), interpolated at
    //   render time in ticks = curTime * 64 - off, off = the largest (curTime * 64 - demo tick) seen.
    // - normal / fast speed: the origin changes once per tick (0 / 14 / 28 u per frame) and frames come unevenly.
    //   Fit a parabola (a flying grenade is one) to the last 0.25 s of positions by curTime and take it at curTime.
    // A big miss (bounce, wall) restarts the fit.
    const lerp3 = (a, b, f) => [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
    // least squares p = c0 + c1 x + c2 x^2, x = time - t, value at t is c0
    const parabolaAt = (pts, t) => {
        let s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0;
        const b = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
        for (const q of pts) {
            const x = q.t - t, x2 = x * x;
            s0 += 1; s1 += x; s2 += x2; s3 += x2 * x; s4 += x2 * x2;
            for (let k = 0; k < 3; k++) { b[0][k] += q.p[k]; b[1][k] += q.p[k] * x; b[2][k] += q.p[k] * x2; }
        }
        // solve [[s0 s1 s2] [s1 s2 s3] [s2 s3 s4]] c = b for c0 (Cramer)
        const det = s0 * (s2 * s4 - s3 * s3) - s1 * (s1 * s4 - s3 * s2) + s2 * (s1 * s3 - s2 * s2);
        if (Math.abs(det) < 1e-18) return null;
        return [0, 1, 2].map(k => (b[0][k] * (s2 * s4 - s3 * s3) - s1 * (b[1][k] * s4 - s3 * b[2][k]) + s2 * (b[1][k] * s3 - s2 * b[2][k])) / det);
    };
    // key: which object the history belongs to (a new key restarts it); lerpOnly: per-tick lerp at every speed
    const nadePos = (e, key, lerpOnly) => {
        const o = P3(e.getOrigin()), tick = mirv.getDemoTick(), ct = mirv.getCurTime() * 64;
        let h = st.nh;
        if (!h || h.idx !== key || tick < h.tick) h = st.nh = { idx: key, tick: -1, ct, fdt: 1, off: -1e9, pts: [], slow: false, out: o };
        if (ct === h.ct && h.pts.length) return h.out; // paused: nothing new
        h.fdt += (Math.min(ct - h.ct, 4) - h.fdt) * 0.2; // ticks per frame, smoothed
        h.ct = ct;
        const slow = lerpOnly || h.fdt < 0.4;
        if (slow !== h.slow) { h.slow = slow; h.pts = []; h.off = -1e9; }
        const pts = h.pts;
        // a dropped C4's origin is that of the demo tick of the previous frame (measured: it advances by the
        // previous frame's tick step), so with lerpOnly label the samples with that tick
        const sTick = lerpOnly && h.prevTick !== undefined ? h.prevTick : tick;
        h.prevTick = tick;
        if (slow) {
            h.off = Math.max(h.off, ct - sTick);
            if (sTick !== h.tick) { pts.push({ t: sTick, p: o }); if (pts.length > 8) pts.shift(); }
            h.tick = sTick;
            if (pts.length < 2) return (h.out = o);
            const t = ct - h.off;
            let i = pts.length - 1;
            while (i > 1 && pts[i - 1].t > t) i--;
            const a = pts[i - 1], b = pts[i];
            return (h.out = lerp3(a.p, b.p, Math.max(0, Math.min((t - a.t) / Math.max(b.t - a.t, 1), 1.5))));
        }
        h.tick = tick;
        if (pts.length >= 6) { const pr = parabolaAt(pts, ct); if (pr && dist(o, pr) > 30) pts.length = 0; } // bounce
        pts.push({ t: ct, p: o });
        while (pts.length > 3 && pts[0].t < ct - 16) pts.shift(); // 16 ticks = 0.25 s
        const r = pts.length >= 6 ? parabolaAt(pts, ct) : null;
        return (h.out = r || o);
    };
    const findNade = (pawnIdx) => {
        // no owner in the API: a new projectile belongs to the nearest player at the moment it appears
        st.frame++;
        if (st.frame % 8 === 0) {
            const hi = mirv.getHighestEntityIndex();
            const pawns = controllers().filter(c => c.pawn);
            for (let i = 65; i <= hi; i++) {
                if (st.knownNades.has(i)) continue;
                const e = mirv.getEntityFromIndex(i);
                if (!alive(e) || !isNade(e)) continue;
                st.knownNades.add(i);
                const o = P3(e.getOrigin());
                let best = -1, bd = 1e9;
                for (const c of pawns) { const d = dist(o, P3(c.pawn.getRenderEyeOrigin())); if (d < bd) { bd = d; best = c.pawnIdx; } }
                if (best === pawnIdx && bd < 160) st.nadeIdx = i;
            }
            for (const i of [...st.knownNades]) { const e = mirv.getEntityFromIndex(i); if (!alive(e) || !isNade(e)) st.knownNades.delete(i); }
        }
        const e = st.nadeIdx >= 0 ? mirv.getEntityFromIndex(st.nadeIdx) : null;
        return alive(e) && isNade(e) ? e : null;
    };
    // C_C4 (carried / dropped) or C_PlantedC4; the planted one wins while both exist
    const findC4 = () => {
        const hi = mirv.getHighestEntityIndex();
        let r = null;
        for (let i = 65; i <= hi; i++) {
            const e = mirv.getEntityFromIndex(i);
            if (!alive(e)) continue;
            const c = e.getClientClassName();
            if (/PlantedC4/.test(c)) return { e, i };
            if (!r && /C4/.test(c)) r = { e, i };
        }
        return r;
    };
    // the C4 has no 'c4' attachment and its origin moves once per tick (1.75 u steps at walking speed, 0 or 2 steps
    // per frame): followed directly it jerks, and the 'flat' yaw taken from those steps flips.
    // - carried: its origin is exactly the carrier's origin + 40 up. Ride the carrier's render eye (drawn-smooth)
    //   rigidly and take his eye yaw.
    // - dropped / planted: per-tick interpolation (as the grenade), yaw = last horizontal movement, else kept.
    const C4_UP = 40;
    const c4Sample = () => {
        const c = findC4();
        if (!c) return null;
        const o = P3(c.e.getOrigin());
        if (!/PlantedC4/.test(c.e.getClientClassName())) {
            for (const p of controllers()) {
                if (!p.pawn) continue;
                const po = P3(p.pawn.getOrigin());
                // exact at normal / slow speed; at fast speed the two update a frame apart (a lying C4 is ~0 up, not 40)
                if (Math.hypot(o[0] - po[0], o[1] - po[1]) > 32 || Math.abs(o[2] - po[2] - C4_UP) > 8) continue;
                const eyeA = P3(p.pawn.getRenderEyeAngles()); eyeA[2] = 0;
                const eo = P3(p.pawn.getRenderEyeOrigin());
                st.c4Yaw = eyeA[1]; st.c4Last = null;
                return { pos: [eo[0], eo[1], eo[2] - (64 - C4_UP)], ang: [0, eyeA[1], 0], eye: eyeA, anchor: eo };
            }
        }
        const pos = nadePos(c.e, 'c4:' + c.i, true);
        if (st.c4Last) {
            const dx = pos[0] - st.c4Last[0], dy = pos[1] - st.c4Last[1];
            if (Math.hypot(dx, dy) > 0.3) st.c4Yaw = Math.atan2(dy, dx) / D;
        }
        st.c4Last = pos;
        if (st.c4Yaw === undefined) { const a = c.e.getAttachment('c4'); st.c4Yaw = a ? attAng(a)[1] : 0; }
        return { pos, ang: [0, st.c4Yaw, 0], eye: null };
    };

    // returns { pos:[3], ang:[3]|null, eye:[3]|null } of the selected object or null
    const sample = () => {
        if (cfg.obj === 'ent') {
            const e = st.entIndex >= 0 ? mirv.getEntityFromIndex(st.entIndex) : null;
            return alive(e) ? { pos: P3(e.getOrigin()), ang: null, eye: null } : null;
        }
        if (cfg.obj === 'c4') return c4Sample();
        const pawn = playerPawn();
        if (!pawn) return null;
        const eyeA = P3(pawn.getRenderEyeAngles()); eyeA[2] = 0;
        const anchor = P3(pawn.getRenderEyeOrigin()); // moves exactly like the drawn player
        trackWeapons(pawn);
        switch (cfg.obj) {
            case 'eye': return { pos: P3(pawn.getRenderEyeOrigin()), ang: eyeA, eye: eyeA, anchor };
            case 'body': return { pos: P3(pawn.getOrigin()), ang: [0, eyeA[1], 0], eye: eyeA, anchor };
            case 'hand': case 'handl': {
                const a = pawn.getAttachment(cfg.obj === 'hand' ? 'weapon_hand_r' : 'weapon_hand_l');
                return a ? { pos: P3(a.position), ang: attAng(a), eye: eyeA, anchor } : null;
            }
            case 'gun': {
                const a = gunAttachment(pawn);
                return a ? { pos: P3(a.position), ang: attAng(a), eye: eyeA, anchor } : null;
            }
            case 'nade': {
                const e = findNade(playerPawnIdx());
                if (e) return { pos: nadePos(e, st.nadeIdx), ang: null, eye: eyeA };
                const a = pawn.getAttachment('weapon_hand_r'); // waiting for a throw: stay at the hand, look like the player
                return a ? { pos: P3(a.position), ang: attAng(a), eye: eyeA, anchor, wait: true } : null;
            }
            case 'drop': {
                // no owner in the API: a dropped weapon = a recent weapon of the player that is now away from him
                const eyeP = P3(pawn.getRenderEyeOrigin());
                for (const h of st.weaponHist) {
                    const w = ent(h);
                    if (!w || w === null || dist(P3(w.getOrigin()), eyeP) < 48) continue;
                    const a = w.getAttachment(st.gunPoint[w.getDebugName()] || 'muzzle_flash') || w.getAttachment('shell_eject');
                    return { pos: a ? P3(a.position) : P3(w.getOrigin()), ang: a ? attAng(a) : null, eye: null };
                }
                const a = pawn.getAttachment('weapon_hand_r'); // nothing dropped yet: stay at the hand
                return a ? { pos: P3(a.position), ang: attAng(a), eye: eyeA, anchor } : null;
            }
        }
        return null;
    };

    // ---- per frame ----
    mirv.events.cViewRenderSetupView.on(VIEW_ID, (e) => {
        if (!st.active) return;
        const s = sample();
        if (!s) {
            if (!st.missing) { st.missing = true; warn('object not found (' + cfg.obj + '), holding last view'); }
            if (!st.has) return;
            return out();
        }
        st.missing = false;

        // time step = game render time. The engine itself sometimes steps this time back a few ms and then forward
        // (seen in demos: -7 ms, +24 ms); players are drawn at this time, so the camera must follow the same clock,
        // otherwise smoothing (real time) and the drawn players disagree and the players seem to jerk
        const cur = mirv.getCurTime(), wall = Date.now() / 1000, tick = mirv.getDemoTick();
        const dCur = st.lastCur === null ? 0 : cur - st.lastCur;
        let cut = !st.has || dCur < -0.1 || (st.lastTick !== null && tick < st.lastTick - 2);
        const dt = Math.min(Math.max(dCur, 0), 0.1);
        st.lastCur = cur; st.lastWall = wall; st.lastTick = tick;

        // velocity (for look 'vel') and cut detection
        if (st.lastTarget) {
            const d = [s.pos[0] - st.lastTarget[0], s.pos[1] - st.lastTarget[1], s.pos[2] - st.lastTarget[2]];
            const len = Math.hypot(d[0], d[1], d[2]);
            if (len > 300) cut = true;
            else if (len > 0.05) st.vel = d;
        }
        st.lastTarget = s.pos;

        let look = cfg.look === 'auto' ? AUTO_LOOK[cfg.obj] : cfg.look;
        // the hand hardly moves: its 'velocity' is noise and spins the camera
        if (s.wait && look === 'vel') look = 'eye';
        let base;
        switch (look) {
            case 'obj': base = s.ang || s.eye || vecAngles(st.vel); break;
            case 'level': base = s.ang ? [s.ang[0], s.ang[1], 0] : (s.eye || vecAngles(st.vel)); break;
            case 'flat': base = s.ang ? [0, s.ang[1], 0] : [0, vecAngles(st.vel)[1], 0]; break;
            case 'eye': base = s.eye || s.ang || vecAngles(st.vel); break;
            default: base = vecAngles(st.vel); // vel
        }
        base = [Math.max(-cfg.pmax, Math.min(cfg.pmax, base[0])), base[1], base[2]];
        const tqb = quat(base);

        // the camera follows the player's movement rigidly (anchor). Only the base orientation (sRot) and the
        // object's own shake relative to the anchor (sPos) are smoothed; the offset and the view are both taken
        // from the same smoothed orientation, so the camera swings like a rigid boom and the player stays put in
        // the frame (smoothing offset and view separately made the player slide/jerk while turning)
        const anchor = s.anchor || s.pos;
        const loc = [s.pos[0] - anchor[0], s.pos[1] - anchor[1], s.pos[2] - anchor[2]];
        if (cut || !st.qb) { st.loc = loc; st.qb = tqb; st.has = true; }
        else {
            const ap = cfg.sPos > 0 ? 1 - Math.exp(-Math.max(dt, 0) / cfg.sPos) : 1;
            const ar = cfg.sRot > 0 ? 1 - Math.exp(-Math.max(dt, 0) / cfg.sRot) : 1;
            for (let i = 0; i < 3; i++) st.loc[i] += (loc[i] - st.loc[i]) * ap;
            // q and -q are the same rotation; slerp to the "wrong sign" turns the camera the long way round
            // (sudden swing away, then a slow return). Happens when the yaw crosses 180.
            const tq2 = st.qb.dot(tqb) < 0 ? new AdvancedfxMathQuaternion(-tqb.w, -tqb.x, -tqb.y, -tqb.z) : tqb;
            st.qb = ar >= 1 ? tq2 : st.qb.slerp(tq2, ar);
        }
        const sb = qAngles(st.qb);
        const B = basis(sb[0], sb[1], sb[2]);
        const o = toWorld(B, cfg.off[0], -cfg.off[1], cfg.off[2]); // right = -left
        st.q = quat(compose(sb, cfg.rot));
        st.pos = [anchor[0] + st.loc[0] + o[0], anchor[1] + st.loc[1] + o[1], anchor[2] + st.loc[2] + o[2]];
        return out();
    });
    const out = () => {
        const a = qAngles(st.q);
        const v = { x: st.pos[0], y: st.pos[1], z: st.pos[2], rX: a[0], rY: a[1], rZ: a[2] };
        if (cfg.fov > 0) v.fov = cfg.fov;
        return v;
    };
    const reset = () => { st.has = false; st.q = null; st.qb = null; st.lastCur = null; st.lastWall = null; st.lastTick = null; st.lastTarget = null; st.missing = false; st.ip = null; st.c4Last = null; };

    try { mirv.events.recordStart.on(ID + '/rs', () => { st.recording = true; reset(); }); } catch (e) { }
    try { mirv.events.recordEnd.on(ID + '/re', () => { st.recording = false; }); } catch (e) { }

    // ---- presets (look/offset/rotation/smoothing/fov + object; the player is not part of a preset) ----
    const PRESETS = {
        muzzle:   { obj: 'gun',  look: 'eye',   off: [4, 0, 1],     rot: [0, 0, 0],  sPos: 0.03, sRot: 0.06, fov: 0 },
        gunside:  { obj: 'gun',  look: 'obj',   off: [-35, 7.5, 3.7], rot: [4.8, 12.7, -10.1], sPos: 0, sRot: 0, fov: 48 },
        hand:     { obj: 'hand', look: 'eye',   off: [-39.1, 12.3, 2.8], rot: [-0.2, 5.1, -8.7], sPos: 0.05, sRot: 0.08, fov: 43 },
        shoulder: { obj: 'eye',  look: 'eye',   off: [-43.6, 24.7, -9.4], rot: [-2, 8.3, -0.3], sPos: 0.06, sRot: 0.1, fov: 60, pmax: 25 },
        chase:    { obj: 'body', look: 'flat',  off: [-90, 0, 70],  rot: [12, 0, 0], sPos: 0.15, sRot: 0.2,  fov: 0 },
        nade:     { obj: 'nade', look: 'vel',   off: [-22.4, 9.4, -1.2], rot: [-2.8, 16.4, -0.6], sPos: 0.03, sRot: 0.25, fov: 47 },
        c4:       { obj: 'c4',   look: 'flat',  off: [-40, 0, 25],  rot: [20, 0, 0], sPos: 0.1,  sRot: 0.1,  fov: 0 }
    };
    const order = () => Object.keys(PRESETS);
    let presetCur = null;
    const applyPreset = (name) => {
        const p = PRESETS[name];
        if (!p) { warn('no preset "' + name + '". Presets: ' + order().join(' ')); return false; }
        cfg.obj = p.obj; cfg.look = p.look; cfg.off = p.off.slice(); cfg.rot = p.rot.slice();
        cfg.sPos = p.sPos; cfg.sRot = p.sRot; cfg.fov = p.fov; cfg.pmax = p.pmax !== undefined ? p.pmax : 89;
        presetCur = name; reset();
        return true;
    };

    // ---- status line ----
    const who = () => {
        if (st.player === 'spec') {
            const sc = st.lastSpecCtrl !== undefined ? mirv.getEntityFromIndex(st.lastSpecCtrl) : null;
            return 'spec' + (alive(sc) && sc.isPlayerController() ? ' (' + sc.getSanitizedPlayerName() + ')' : '');
        }
        const c = mirv.getEntityFromIndex(st.player);
        return '#' + st.player + (alive(c) && c.isPlayerController() ? ' ' + c.getSanitizedPlayerName() : ' ?');
    };
    const n1 = (v) => +v.toFixed(3);
    const status = () => (st.active ? 'ON' : 'OFF') + ' | player ' + who() + ' | obj ' + cfg.obj + (cfg.obj === 'ent' ? ' ' + st.entIndex : '') +
        ' | look ' + cfg.look + ' | off ' + cfg.off.map(n1).join(' ') + ' | rot ' + cfg.rot.map(n1).join(' ') +
        ' | smooth ' + cfg.sPos + ' ' + cfg.sRot + ' | fov ' + (cfg.fov > 0 ? cfg.fov : 'game') + ' | pitch ' + cfg.pmax + (presetCur ? ' | preset ' + presetCur : '');

    // ---- commands ----
    const num = (s) => { const n = parseFloat(s); return isNaN(n) ? null : n; };
    const args = (a) => { const r = []; for (let i = 1; i < a.argC(); i++) r.push(a.argV(i)); return r; };
    const cmds = [];
    const reg = (name, help, fn) => {
        const c = new AdvancedfxConCommand((a) => { try { fn(args(a)); } catch (e) { warn(name + ': ' + e); } });
        c.register(name, help);
        cmds.push(c);
    };

    const exec = (s) => {
        if (typeof mirv.exec !== 'function') { warn('mirv.exec not available, cannot run: ' + s); return; }
        try { mirv.exec(s); } catch (e) { warn('exec ' + s + ': ' + e); }
    };
    // spec_mode only takes effect on the next demo tick. While paused (v3 pause = host_framerate 10000000) the view
    // stays in first person, and then CS2 hides the watched body and draws the viewmodel once the camera comes within
    // ~10 units of his eyes. So if the demo stands still, step it one tick (1/64 s) and pause again.
    const OBS_OF_SPEC = { 1: 2, 4: 4 }; // spec_mode -> observer mode of the local pawn
    const obsMode = () => { const c = mirv.getEntityFromSplitScreenPlayer(0); const p = c ? ent(c.getPlayerPawnHandle()) : null; return p ? p.getObserverMode() : null; };
    // CS2 also hides a player's body and draws his viewmodel when the camera is closer to his eyes than these cvars
    // (any spec mode). 0 for free camera / ac; defaults for POV, where 0 would draw his own head over the screen.
    const nearEye = (free) => {
        exec('cl_view_near_hud_player_eye_dist ' + (free ? 0 : 20));
        exec('cl_view_near_other_player_eye_dist ' + (free ? 0 : 16));
    };
    const specMode = (n) => {
        if (n === 4) specPawnIdx(); // cache the watched player: the free camera has none
        exec('spec_mode ' + n);
        // from the free camera CS2 picks some player for POV: go back to the one watched before
        if (n === 1 && obsMode() === 4 && st.lastSpecCtrl !== undefined && ctrlPawnIdx(st.lastSpecCtrl) >= 0) exec('spec_player ' + st.lastSpecCtrl);
        const want = OBS_OF_SPEC[n];
        if (want !== undefined) nearEye(n === 4);
        // ac on turned the viewmodel off; P / F use 'ac stop', so give the hands back on the way to POV
        if (n === 1 && st.vmOff) { exec('r_drawviewmodel 1'); st.vmOff = false; }
        mirv.events.cViewRenderSetupView.off(ID + '/sm');
        if (want === undefined || obsMode() === want) return;
        const tick0 = mirv.getDemoTick();
        let frame = 0;
        mirv.events.cViewRenderSetupView.on(ID + '/sm', () => {
            frame++;
            if (frame === 40) { // super slow (host_framerate 1800) needs ~28 frames per tick: frozen 40 frames = paused
                if (obsMode() === want || mirv.getDemoTick() !== tick0) { mirv.events.cViewRenderSetupView.off(ID + '/sm'); return; }
                if (mirv.isDemoPaused()) { mirv.events.cViewRenderSetupView.off(ID + '/sm'); warn('demo paused (demo_pause): spec_mode ' + n + ' applies after resume'); return; }
                exec('host_framerate 64'); // one frame = one tick
            } else if (frame === 41) {
                exec('host_framerate 10000000');
            } else if (frame === 45) { // the observer mode shows up a frame or two after the tick
                mirv.events.cViewRenderSetupView.off(ID + '/sm');
                if (obsMode() !== want) warn('spec_mode ' + n + ' did not apply');
            }
        });
    };
    reg('ac', 'attach camera: ac [on|off|stop] (no args = toggle; stop = off without restoring the view)', (a) => {
        const v = (a[0] || '').toLowerCase();
        const was = st.active;
        st.active = v === 'on' ? true : (v === 'off' || v === 'stop') ? false : !st.active;
        reset();
        if (cfg.autoView && !was && st.active) {
            specPawnIdx(); // cache the watched player before the free camera drops it
            exec('r_drawviewmodel 0'); st.vmOff = true;
            specMode(4);
        } else if (cfg.autoView && was && !st.active && v !== 'stop') {
            exec('r_drawviewmodel 1'); st.vmOff = false;
            specMode(1);
        }
        msg(status());
    });
    reg('ac_mode', 'spec_mode that also works while the demo is paused (steps 1 tick): ac_mode <1|4>', (a) => {
        const n = num(a[0]); if (n === null) { warn('usage: ac_mode <1|4>'); return; }
        specMode(n);
    });
    reg('ac_view', 'auto third person + no viewmodel while ac is on: ac_view <0|1>', (a) => {
        const n = num(a[0]); if (n !== null) cfg.autoView = n ? 1 : 0;
        msg('auto view ' + (cfg.autoView ? 'on' : 'off'));
    });
    reg('ac_list', 'list players and objects', () => {
        const lines = controllers().map(c => '  ' + c.idx + '  ' + c.name + '  team ' + c.team + (c.pawn ? '' : '  (no pawn)'));
        msg('players (ac_p <number | part of name | spec | next | prev>):\n' + lines.join('\n') +
            '\n  objects (ac_o): ' + OBJECTS.join(' ') + '   looks (ac_look): ' + LOOKS.join(' ') + '\n  presets (ac_preset): ' + order().join(' ') + '\n  now: ' + status());
    });
    reg('ac_p', 'select player: ac_p <number | name | spec | next | prev>', (a) => {
        const v = (a[0] || '').toLowerCase();
        const list = controllers().filter(c => c.pawn);
        if (v === '' ) { msg('player ' + who()); return; }
        if (v === 'spec') {
            st.player = 'spec';
            if (specPawnIdx() < 0) warn('no watched player (free camera after a reload?): press P / spec_mode 1 and pick a player, or use ac_p <number>');
        }
        else if (v === 'next' || v === 'prev') {
            if (!list.length) { warn('no players'); return; }
            let i = list.findIndex(c => c.idx === st.player);
            if (i < 0) { const sp = specPawnIdx(); i = list.findIndex(c => c.pawnIdx === sp); }
            i = (i + (v === 'next' ? 1 : -1) + list.length) % list.length;
            st.player = list[i].idx;
        } else {
            const n = num(v);
            const hit = n !== null ? list.find(c => c.idx === n) : list.find(c => c.name.toLowerCase().includes(v));
            if (!hit) { warn('player not found: ' + v + ' (see ac_list)'); return; }
            st.player = hit.idx;
        }
        st.weaponHist = []; st.lastWeapon = null; st.nadeIdx = -1; reset();
        msg('player ' + who());
    });
    reg('ac_o', 'select object: ac_o <eye|body|hand|handl|gun|nade|drop|c4|ent <index>|next>', (a) => {
        let v = (a[0] || '').toLowerCase();
        if (v === 'next') v = OBJECTS[(OBJECTS.indexOf(cfg.obj) + 1) % (OBJECTS.length - 1)]; // 'ent' is not in the cycle
        if (!OBJECTS.includes(v)) { warn('objects: ' + OBJECTS.join(' ')); return; }
        if (v === 'ent') { const n = num(a[1]); if (n === null) { warn('ac_o ent <entity index>'); return; } st.entIndex = n; }
        cfg.obj = v; presetCur = null; reset();
        msg('obj ' + v + (cfg.look === 'auto' ? ' (look auto = ' + AUTO_LOOK[v] + ')' : ''));
    });
    reg('ac_look', 'orientation: ac_look <auto|obj|level|flat|eye|vel>', (a) => {
        const v = (a[0] || '').toLowerCase();
        if (!LOOKS.includes(v)) { warn('looks: ' + LOOKS.join(' ') + '  (now ' + cfg.look + ')'); return; }
        cfg.look = v; presetCur = null; reset(); msg('look ' + v);
    });
    const triple = (name, key, a) => {
        if (a.length === 0) { msg(name + ' ' + cfg[key].map(n1).join(' ')); return; }
        if ((a[0] || '').toLowerCase() === 'add') { // relative: ac_off add 0 2 0
            const d = a.slice(1).map(num);
            for (let i = 0; i < 3; i++) cfg[key][i] += d[i] || 0;
        } else {
            for (let i = 0; i < 3; i++) { if (a[i] === '*' || a[i] === undefined) continue; const n = num(a[i]); if (n !== null) cfg[key][i] = n; }
        }
        presetCur = null; msg(name + ' ' + cfg[key].map(n1).join(' '));
    };
    reg('ac_off', 'offset: ac_off <forward> <right> <up>  (* = keep, "add" = relative)', (a) => triple('off', 'off', a));
    reg('ac_rot', 'extra rotation: ac_rot <pitch> <yaw> <roll>  (* = keep, "add" = relative)', (a) => triple('rot', 'rot', a));
    reg('ac_smooth', 'smoothing seconds: ac_smooth <position> [rotation]  (0 = off)', (a) => {
        const p = num(a[0]), r = num(a[1]);
        if (p !== null) cfg.sPos = Math.max(0, p);
        if (r !== null) cfg.sRot = Math.max(0, r); else if (p !== null && a.length === 1) cfg.sRot = cfg.sPos;
        presetCur = null; msg('smooth ' + cfg.sPos + ' ' + cfg.sRot);
    });
    reg('ac_fov', 'fov of the attached camera: ac_fov <number | 0 = game fov>', (a) => {
        const n = num(a[0]); if (n !== null) cfg.fov = Math.max(0, Math.min(170, n));
        presetCur = null; msg('fov ' + (cfg.fov > 0 ? cfg.fov : 'game'));
    });
    reg('ac_pitch', 'limit the up/down tilt taken from the player/object: ac_pitch <0..89>', (a) => {
        const n = num(a[0]); if (n !== null) cfg.pmax = Math.max(0, Math.min(89, n));
        presetCur = null; msg('pitch limit ' + cfg.pmax);
    });
    reg('ac_preset', 'ac_preset <name | next | prev> | ac_preset save <name>', (a) => {
        const v = (a[0] || '').toLowerCase();
        const names = order();
        if (v === '') { msg('presets: ' + names.join(' ') + (presetCur ? '  (now ' + presetCur + ')' : '')); return; }
        if (v === 'save') {
            const n = (a[1] || '').toLowerCase();
            if (!n) { warn('ac_preset save <name>'); return; }
            PRESETS[n] = { obj: cfg.obj, look: cfg.look, off: cfg.off.slice(), rot: cfg.rot.slice(), sPos: cfg.sPos, sRot: cfg.sRot, fov: cfg.fov, pmax: cfg.pmax };
            presetCur = n; msg('saved preset ' + n + ' (until game restart; ac_print gives a line for v3_attach.cfg)'); return;
        }
        let name = v;
        if (v === 'next' || v === 'prev') { const i = names.indexOf(presetCur); name = names[(i + (v === 'next' ? 1 : -1) + names.length) % names.length]; }
        if (applyPreset(name)) msg('preset ' + name + ' | ' + status());
    });
    reg('ac_def', 'define a preset (used in v3_attach.cfg): ac_def <name> <obj> <look> <f r u> <pitch yaw roll> <smoothPos> <smoothRot> <fov> [pitchMax]', (a) => {
        if (a.length < 12) { warn('ac_def <name> <obj> <look> <f> <r> <u> <pitch> <yaw> <roll> <smoothPos> <smoothRot> <fov> [pitchMax]'); return; }
        const n = a.map((x, i) => i >= 3 ? num(x) : x);
        if (!OBJECTS.includes(n[1].toLowerCase()) || !LOOKS.includes(n[2].toLowerCase()) || n.slice(3, 12).some(x => x === null)) { warn('ac_def ' + a[0] + ': bad values'); return; }
        PRESETS[n[0].toLowerCase()] = { obj: n[1].toLowerCase(), look: n[2].toLowerCase(), off: n.slice(3, 6), rot: n.slice(6, 9), sPos: n[9], sRot: n[10], fov: n[11], pmax: a.length > 12 && num(a[12]) !== null ? num(a[12]) : 89 };
    });
    reg('ac_print', 'print current settings as a preset line', () => {
        msg('ac_def mypreset ' + cfg.obj + ' ' + cfg.look + ' ' + cfg.off.map(n1).join(' ') + ' ' + cfg.rot.map(n1).join(' ') + ' ' + cfg.sPos + ' ' + cfg.sRot + ' ' + cfg.fov + ' ' + cfg.pmax +
            '\n     (copy into v3_attach.cfg, rename "mypreset")\n  ' + status());
    });

    // ---- free camera sensitivity, the same at any FPS and any playback speed ----
    // HLAE multiplies keys and mouse by its frame time (e.absTime), and that time shrinks with the playback speed
    // (x0.33 on Slow, 1e-7 on pause) and follows the FPS. Both sensitivities are recalculated from it:
    //   mouse: msens * absTime stays 0.024 / 120; keys: ksens * absTime * FPS stays 0.36 (the values the camera was tuned for).
    // HLAE stores ksens when a key goes down, so a key held through a speed change keeps the old value until released.
    const sens = { on: true, last: 0, wall: 1 / 120, abs: 0, k: 0, m: 0 };
    const MOUSE_AT_120 = 0.024 / 120, KEYS = 0.36;
    const changed = (a, b) => b === 0 || Math.abs(a - b) / b > 0.05;
    mirv.events.cViewRenderSetupView.on(ID + '/sens', (e) => {
        if (!sens.on || st.recording) { sens.last = 0; sens.abs = 0; sens.k = 0; sens.m = 0; return undefined; }
        const now = Date.now() / 1000, abs = e.absTime;
        if (sens.last > 0 && abs > 0) {
            const dt = now - sens.last;
            if (dt > 0.001 && dt < 0.25) sens.wall += (dt - sens.wall) * 0.1;
            // a new speed changes abs at once, so it is followed fast
            sens.abs = sens.abs === 0 || changed(abs, sens.abs) ? abs : sens.abs + (abs - sens.abs) * 0.25;
            const k = KEYS * sens.wall / sens.abs, m = MOUSE_AT_120 / sens.abs;
            if (changed(k, sens.k) || changed(m, sens.m)) {
                sens.k = k; sens.m = m;
                exec('mirv_input cfg ksens ' + k.toFixed(5) + '; mirv_input cfg msens ' + m.toFixed(5));
            }
        }
        sens.last = now;
        return undefined;
    });
    reg('v3sens', 'v3sens 1|0 - keep the free camera sensitivity the same at any FPS and playback speed (default 1)', (a) => {
        sens.on = a[0] !== '0';
        sens.last = 0; sens.abs = 0; sens.k = 0; sens.m = 0;
    });

    globalThis[ID] = { commands: cmds, st, sens }; // keep references, otherwise the commands get garbage collected (st: for debug probes)
    // last expression = what mirv_script_load prints (otherwise it prints "undefined")
    '[ac] loaded. ac_list = players/objects, ac = on/off, h_att = help';
}
