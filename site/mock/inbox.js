/* One inbox, as a flow (site/mock/inbox.css), comes alive on top of mock.js (window.GM).

   - The wires are drawn here, from where things stand on the page: one from each network's row to a fork, and from
     the fork to the computer's window and to the phone. Drawn again whenever the board is another size. Where the
     panel stands over the devices (a narrow screen) every network shares one wire down.
   - While it is on screen it plays through, over and over: a network is signed in to in Chrome and the Uplink keys
     extension hands that sign-in, sealed, to both devices; then each network in turn sends a chat down its wire, and
     the same row comes to the top of the list on the computer and on the phone; then an answer written on the
     computer shows on the phone, and what is read on one is read on the other.
   - Nothing moves by itself under prefers-reduced-motion (GM.loop never starts): the markup is the still picture,
     with its wires. FlowMock.wire() again after injecting the markup. */
(() => {
  'use strict';
  const $$ = (sel, root) => Array.from(root.querySelectorAll(sel));
  const NS = 'http://www.w3.org/2000/svg';
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

  // Who writes, and on which network: [name, the face's letters, its hue, the network].
  const PEOPLE = {
    noor: ['Noor Haddad', 'NH', 'orange', 'instagram'],
    crew: ['Weekend crew', 'WC', 'slate', 'whatsapp'],
    sam: ['Sam Rivera', 'SR', 'blue', 'discord'],
    riley: ['Riley Fox', 'RF', 'indigo', 'signal'],
    priya: ['Priya Natarajan', 'PN', 'green', 'slack'],
    alex: ['Alex Kim', 'AK', 'rose', 'messenger'],
    kofi: ['Kofi Mensah', 'KM', 'cyan', 'x'],
    lena: ['Lena Novak', 'LN', 'purple', 'matrix'],
    maya: ['Maya Chen', 'MC', 'magenta', 'rcs'],
    dad: ['Dad', 'D', 'coral', 'texts'],
    jo: ['Jo Park', 'JP', 'amber', 'telegram'],
  };
  const NAMES = { texts: 'Texts', rcs: 'Google Messages', whatsapp: 'WhatsApp', telegram: 'Telegram', signal: 'Signal', discord: 'Discord', messenger: 'Messenger', instagram: 'Instagram', slack: 'Slack', x: 'X', matrix: 'Matrix' };
  // What comes in, in turn: one chat from every network. Jo's is last, into the conversation the computer has open.
  const CHATS = [
    ['noor', 'that sunset though 😍'],
    ['crew', "Ana: who's bringing the stove?"],
    ['sam', 'count me in for Saturday'],
    ['riley', 'running ten minutes late'],
    ['priya', 'the new build is up'],
    ['alex', 'happy birthday!! 🎉'],
    ['kofi', 'saw your post, nice one'],
    ['lena', 'the patch is merged'],
    ['maya', 'Bring the projector cable?'],
    ['dad', 'Call me when you land'],
    ['jo', 'starts at 8, bring a blanket'],
  ];
  const LINKED = 'instagram';   // the network the walkthrough signs in to through the extension

  const badge = (net, small) => `<span class="fl-badge${small ? ' fl-badge--sm' : ''}" data-net="${net}"><svg viewBox="0 0 24 24"><use href="#n-${net}"/></svg></span>`;
  function rowOf(id, text, time, unread) {
    const [name, letters, hue, net] = PEOPLE[id];
    const row = document.createElement('div');
    row.className = 'gm-row' + (unread ? ' is-unread' : '');
    row.dataset.id = id; row.dataset.net = net;
    row.innerHTML = `<div class="gm-row__in"><span class="gm-av" data-hue="${hue}">${letters}${badge(net)}</span><div class="gm-row__main">` +
      `<div class="gm-row__top"><span class="gm-row__name">${esc(name)}</span><span class="gm-row__fill"></span><span class="gm-row__time">${esc(time)}</span></div>` +
      `<div class="gm-row__bottom"><span class="gm-row__snip">${esc(text)}</span><span class="gm-row__dot"></span></div></div></div>`;
    return row;
  }

  function flow(root) {
    if (root.__fl) return; root.__fl = 1;
    const GM = window.GM;
    const board = root.querySelector('.fl-board'), wires = root.querySelector('.fl-wires');
    const panel = root.querySelector('.fl-panel'), desk = root.querySelector('.fl-desk'), phone = root.querySelector('.fl-phone');
    const sync = root.querySelector('.fl-sync'), steps = $$('.fl-steps li', root);
    const nets = $$('.fl-net[data-net]', root), lists = $$('[data-fl-list]', root);
    const thread = root.querySelector('.js-fl-thread'), composer = root.querySelector('.js-fl-composer');
    const toasts = $$('.fl-toast', root), ext = root.querySelector('.fl-ext'), tab = root.querySelector('.fl-tab span');
    if (!board || !wires || !panel || !desk || !phone) return;
    const netRow = (net) => nets.find((n) => n.dataset.net === net);

    /* --- the wires ------------------------------------------------------------------------------------------ */
    const paths = {};   // net -> its wire's path to the fork; and 'desk', 'phone' from the fork on
    const drawn = {};   // the same, as the <path> elements
    const can = !!(window.CSS && CSS.supports && CSS.supports('offset-path', 'path("M0 0L1 1")'));
    function layout() {
      const B = board.getBoundingClientRect();
      if (!B.width || !board.offsetWidth) return;
      // In the board's own pixels, whatever it is scaled by on the page.
      const k = B.width / board.offsetWidth;
      const box = (el) => { const r = el.getBoundingClientRect(); return { l: (r.left - B.left) / k, t: (r.top - B.top) / k, r: (r.right - B.left) / k, b: (r.bottom - B.top) / k, w: r.width / k, h: r.height / k }; };
      const P = box(panel), D = box(desk), H = box(phone);
      const stacked = D.t >= P.b - 2;
      const f = (n) => n.toFixed(1);
      wires.setAttribute('viewBox', `0 0 ${f(B.width / k)} ${f(B.height / k)}`);
      wires.replaceChildren();
      const add = (tag, attrs) => { const el = document.createElementNS(NS, tag); for (const k in attrs) el.setAttribute(k, attrs[k]); wires.append(el); return el; };
      let fx, fy;
      const py = Math.min(H.b - 18, (D.b + H.b) / 2 + 6);   // where the phone's wire comes in: under the window
      if (!stacked) {
        // Beside each other: every wire leaves its row at the panel's edge and bends in to the fork, just short of the
        // window. From there one goes on into the window and one drops past it and runs under it to the phone.
        fx = D.l - Math.max(18, Math.min(36, (D.l - P.r) * 0.24)); fy = D.t + D.h * 0.47;
        for (const n of nets) {
          const r = box(n), sx = P.r, sy = (r.t + r.b) / 2, dx = (fx - sx) * 0.55, net = n.dataset.net;
          paths[net] = `M${f(sx)} ${f(sy)}C${f(sx + dx)} ${f(sy)} ${f(fx - dx)} ${f(fy)} ${f(fx)} ${f(fy)}`;
          drawn[net] = add('path', { class: 'fl-wire' + (n.classList.contains('is-unlinked') ? ' is-off' : ''), 'data-net': net, d: paths[net] });
        }
        for (const n of nets) { const r = box(n); add('circle', { class: 'fl-jack' + (n.classList.contains('is-unlinked') ? ' is-off' : ''), 'data-net': n.dataset.net, cx: f(P.r), cy: f((r.t + r.b) / 2), r: 4.5 }); }
        paths.desk = `M${f(fx)} ${f(fy)}L${f(D.l)} ${f(fy)}`;
        const turn = Math.min(16, (py - fy) / 2);
        paths.phone = `M${f(fx)} ${f(fy)}L${f(fx)} ${f(py - turn)}Q${f(fx)} ${f(py)} ${f(fx + turn)} ${f(py)}L${f(H.l)} ${f(py)}`;
      } else {
        // The panel over the devices: one wire for them all, from the panel's foot to the fork, then on down into the
        // window; the phone's goes out to the side, down past the window and in under it.
        const sx = (P.l + P.r) / 2, sy = P.b;
        fx = sx; fy = (P.b + D.t) / 2;
        const trunk = `M${f(sx)} ${f(sy)}L${f(fx)} ${f(fy)}`;
        for (const n of nets) paths[n.dataset.net] = trunk;
        add('path', { class: 'fl-wire fl-wire--out', d: trunk });
        for (const n of nets) drawn[n.dataset.net] = null;
        paths.desk = `M${f(fx)} ${f(fy)}L${f(fx)} ${f(D.t)}`;
        const wx = Math.max(6, D.l - Math.max(8, (D.l - Math.min(H.l, D.l)) / 2) - 10), turn = 12;
        const side = Math.max(4, Math.min(wx, D.l - 7));
        paths.phone = `M${f(fx)} ${f(fy)}L${f(side + turn)} ${f(fy)}Q${f(side)} ${f(fy)} ${f(side)} ${f(fy + turn)}L${f(side)} ${f(py - turn)}Q${f(side)} ${f(py)} ${f(side + turn)} ${f(py)}L${f(Math.max(H.l, side + turn))} ${f(py)}`;
      }
      drawn.desk = add('path', { class: 'fl-wire fl-wire--out', d: paths.desk });
      drawn.phone = add('path', { class: 'fl-wire fl-wire--out', d: paths.phone });
      add('circle', { class: 'fl-fork', cx: f(fx), cy: f(fy), r: 3.5 });
      // "In sync" sits on the phone's wire, where it runs under the window.
      if (sync) {
        const D2 = box(root.querySelector('.fl-devs'));
        const sxm = stacked ? (D.l + H.l) / 2 + 8 : (fx + H.l) / 2;
        sync.style.left = f(sxm - D2.l) + 'px'; sync.style.top = f(py - D2.t) + 'px';
      }
    }
    const ro = 'ResizeObserver' in window ? new ResizeObserver(() => layout()) : null;
    ro && [board, panel, desk, phone].forEach((el) => ro.observe(el));
    addEventListener('resize', layout);
    document.fonts && document.fonts.ready.then(layout);
    layout();

    /* --- something going down a wire: a chat (a dot in its network's colour) or a sign-in (a sealed square) ------ */
    function fly(d, net, ms, key) {
      if (!can || !d) return GM.sleep(ms);
      const p = document.createElement('i');
      p.className = 'fl-pkt' + (key ? ' fl-pkt--key' : ''); p.dataset.net = net;
      p.style.offsetPath = `path("${d}")`;
      board.append(p);
      p.animate([{ offsetDistance: '0%' }, { offsetDistance: '100%' }], { duration: ms, easing: 'cubic-bezier(.45, 0, .3, 1)', fill: 'forwards' });
      // Timed by the clock, not by the browser saying the animation is over: a page that is not being drawn says so late.
      return GM.sleep(ms).then(() => p.remove());
    }
    async function send(net, key) {
      const row = netRow(net), outs = [drawn.desk, drawn.phone];
      row && row.classList.add('is-live');
      drawn[net] && drawn[net].classList.add('is-live');
      await fly(paths[net], net, 640, key);
      for (const o of outs) if (o) { o.dataset.net = net; o.classList.add('is-live'); }
      await Promise.all([GM.sleep(170).then(() => fly(paths.desk, net, 250, key)), fly(paths.phone, net, 420, key)]);
      row && row.classList.remove('is-live');
      drawn[net] && drawn[net].classList.remove('is-live');
      for (const o of outs) if (o) o.classList.remove('is-live');
    }

    /* --- the list, the same on both devices ------------------------------------------------------------------ */
    const first = lists.map((l) => l.innerHTML), firstThread = thread ? thread.innerHTML : '';
    let minute = 41;
    const clock = () => `11:${String(minute).padStart(2, '0')} PM`;
    // A row comes to the top of a list (made if it is not there), the rest moving down to let it; the last falls off.
    function toTop(list, id, text, time) {
      const max = +list.dataset.max || 5, rows = $$(':scope > .gm-row', list);
      const before = new Map(rows.map((r) => [r, r.getBoundingClientRect().top]));
      let row = rows.find((r) => r.dataset.id === id);
      const made = !row;
      if (made) row = rowOf(id, text, time, true);
      else {
        row.querySelector('.gm-row__snip').textContent = text;
        row.querySelector('.gm-row__time').textContent = time;
        row.classList.add('is-unread');
      }
      list.prepend(row);
      for (const extra of $$(':scope > .gm-row', list).slice(max)) extra.remove();
      const k = list.getBoundingClientRect().height / (list.offsetHeight || 1) || 1;
      for (const r of rows) {
        if (r === row || !r.isConnected) continue;
        const dy = (before.get(r) - r.getBoundingClientRect().top) / k;
        if (Math.abs(dy) > 0.5) r.animate([{ transform: `translateY(${dy}px)` }, { transform: 'none' }], { duration: 520, easing: 'cubic-bezier(0.16, 1, 0.3, 1)' });
      }
      row.classList.remove('fl-new', 'fl-in'); row.offsetWidth; row.classList.add(made ? 'fl-in' : 'fl-new');
    }
    const eachRow = (id, fn) => { for (const l of lists) for (const r of $$(':scope > .gm-row', l)) if (!id || r.dataset.id === id) fn(r); };
    const beat = () => { if (!sync) return; sync.classList.remove('is-pulse'); sync.offsetWidth; sync.classList.add('is-pulse'); setTimeout(() => sync.classList.remove('is-pulse'), 1100); };
    const step = (n) => steps.forEach((li, i) => { li.classList.toggle('is-on', i === n); li.classList.toggle('is-done', i < n); });
    const toast = (net, words) => { for (const t of toasts) { t.innerHTML = badge(net) + esc(words); t.classList.add('is-on'); } };
    const untoast = () => toasts.forEach((t) => t.classList.remove('is-on'));
    // How the linked network stands in the extension's list: not synced yet ('here'), going ('sync'), or synced.
    function linked(state) {
      const row = netRow(LINKED), pill = row && row.querySelector('.fl-pill');
      if (!row || !pill) return;
      row.classList.toggle('is-unlinked', state !== 'done');
      if (state === 'done') { delete pill.dataset.state; pill.textContent = 'Synced'; } else { pill.dataset.state = state; pill.textContent = state === 'sync' ? 'Syncing…' : 'Signed in here'; }
      const wire = drawn[LINKED]; wire && wire.classList.toggle('is-off', state !== 'done');
      for (const j of $$(`.fl-jack[data-net="${LINKED}"]`, wires)) j.classList.toggle('is-off', state !== 'done');
    }

    if (!GM || GM.still.matches) return;
    root.dataset.run = '';
    GM.loop(root, async ({ wait, isOn }) => {
      // From the top: the lists as they were written, and the one network not linked yet.
      minute = 41; untoast(); linked('here'); step(0);
      if (tab) tab.textContent = `${LINKED}.com`;
      await wait(1500);

      // 1. Signed in to in Chrome: the extension seals the sign-in and both devices take it.
      ext && ext.classList.add('is-busy');
      linked('sync');
      await wait(650);
      await send(LINKED, true);
      ext && ext.classList.remove('is-busy');
      linked('done');
      toast(LINKED, `${NAMES[LINKED]} signed in`);
      beat();
      await wait(1700);
      untoast();
      await wait(350);

      // 2. A chat from each network in turn, into the same list on both.
      step(1);
      for (const [id, text] of CHATS) {
        const net = PEOPLE[id][3];
        await send(net);
        minute++;
        for (const l of lists) toTop(l, id, text, clock());
        if (id === 'jo' && thread) { GM.say(thread, { text, out: false, meta: clock() }); GM.trim(thread, 5); }
        beat();
        await wait(id === 'jo' ? 900 : 560);
      }

      // 3. Answered on the computer: the phone has it too, and what is read on one is read on both.
      step(2);
      await wait(500);
      if (composer && thread) {
        await GM.type(composer, "I'm in! See you there 🙌", { speed: 30, send: true, isOn });
        GM.trim(thread, 5);
      }
      eachRow('jo', (r) => { r.querySelector('.gm-row__snip').textContent = "You: I'm in! See you there 🙌"; r.classList.remove('is-unread', 'fl-new', 'fl-in'); r.offsetWidth; r.classList.add('fl-new'); });
      beat();
      await wait(1500);
      eachRow(null, (r) => r.classList.remove('is-unread'));
      beat();
      await wait(3000);

      // Back to the start, faded through so nothing jumps.
      lists.forEach((l) => l.classList.add('is-fading')); thread && thread.classList.add('is-fading');
      await wait(340);
      lists.forEach((l, i) => { l.innerHTML = first[i]; l.classList.remove('is-fading'); });
      if (thread) { thread.innerHTML = firstThread; thread.classList.remove('is-fading'); }
      step(-1);
    }, { gap: 500 });
  }

  function wire(root = document) {
    $$('[data-flow]', root).forEach(flow);
  }
  window.FlowMock = { wire };
  const go = () => (window.GM ? wire() : setTimeout(go, 50));
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', go);
  else go();
})();
