"use strict";
{
    // =====================================================================
    //  fd_v3.js  -  FakeDemo + V3 (HLAE mirv-script, loaded by fd_hlae.cfg)
    //  The keys of fake mode and of V3 overlap, so they are never on together:
    //  a demo starts  -> your own binds (fd_unfake), then V3 ('exec v3; fe')
    //  the demo ends  -> V3 off ('reset' = v3_reset -> fd_unfake), then fake mode ('fake')
    //  fd_v3_off / fd_v3_on: stop / start doing this
    // =====================================================================
    const ID = 'fd_v3';

    if (globalThis[ID] !== undefined) {
        for (const c of globalThis[ID].commands) { try { c.unregister(); } catch (e) { } }
        delete globalThis[ID];
    }
    mirv.events.clientFrameStageNotify.off(ID);

    const msg = (s) => mirv.message('[FakeDemo] ' + s + '\n');
    const run = (s) => { try { mirv.exec(s); } catch (e) { mirv.warning('[FakeDemo] ' + s + ': ' + e + '\n'); } };

    // inDemo: V3 is on. waitTick: the demo was seen, V3 goes on once it really plays (its entities are there
    // only after the first ticks, and v3_attach.js looks for them)
    const st = { on: true, inDemo: false, waitTick: -1 };

    mirv.events.clientFrameStageNotify.on(ID, () => {
        if (!st.on) return;
        const playing = mirv.isPlayingDemo();
        if (playing && !st.inDemo) {
            const tick = mirv.getDemoTick();
            if (st.waitTick < 0) { st.waitTick = tick; return; }
            if (tick === st.waitTick) return;
            st.inDemo = true; st.waitTick = -1;
            run('exec fd_unfake; exec v3; fe');
            msg('demo: V3 keys on (fehelp). Fake mode keys come back when the demo ends');
        } else if (!playing) {
            st.waitTick = -1;
            if (st.inDemo) {
                st.inDemo = false;
                run('reset; fake');
                msg('demo ended: V3 keys off, fake mode keys back');
            }
        }
    });

    const commands = [];
    const reg = (name, help, fn) => {
        const c = new AdvancedfxConCommand(() => { try { fn(); } catch (e) { mirv.warning('[FakeDemo] ' + name + ': ' + e + '\n'); } });
        c.register(name, help);
        commands.push(c);
    };
    reg('fd_v3_off', 'FakeDemo: do not switch V3 on in demos', () => { st.on = false; msg('V3 is not switched on in demos (fd_v3_on)'); });
    reg('fd_v3_on', 'FakeDemo: switch V3 on in demos', () => { st.on = true; msg('V3 goes on in demos'); });
    // keep references, otherwise the commands get garbage collected
    globalThis[ID] = { commands, st };
    msg('V3 goes on by itself in demos');
}
