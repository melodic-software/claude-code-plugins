// The shared interview page: top bar, question rail and a Focus | Compare | Tree | Host center, with votes,
// reactions, locks and suggestions, Claude's cards, requests, roles, owner settings, per-viewer themes and a
// floating side chat. It reads the state core.js builds (the prototype's names) and acts only through Core.
(() => {
    const Core = window.Core, root = document.getElementById("app");
    const E = Core.el;
    const phone = matchMedia("(max-width: 720px)");
    const drawerSheet = matchMedia("(max-width: 1023px)"); // the Ask Claude panel is a bottom sheet below this
    const lightOS = matchMedia("(prefers-color-scheme: light)");
    const store = {
      get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch { return d; } },
      put(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} },
    };
    const ui = {
      cur: "", mode: "focus", tab: "answer", drafts: {}, dirty: false,
      chatOpen: false, seenChat: null, pop: null, suggestOpen: false, editFrom: null,
      round: null, rstat: null, freshRound: 0, cmpRound: null, lastUnread: 0,
      order: store.get("vf-order", "new"), seen: store.get("vf-seen", {}), seenAt: null,
      propFilter: "new", reqSeen: new Set(), reqEditing: new Set(),
      resClosed: new Set(), askOpen: false, askKind: "ask", exp: new Set(), pcard: null, mergeFrom: "", mergeTo: "",
      bumped: false, heard: {}, renaming: false, tie: null,
      // round 8
      revealed: new Set(), clOpen: new Map(), cites: {}, hostFilter: "all", treeClosed: new Set(),
      askPanel: false, askMode: "ask", askQ: "", askSelf: false, picks: {}, goalEditing: false, notified: {}, msgMenu: null,
      more: {}, peopleFilter: "all", peopleFind: "", unreadOnly: false, ixTab: "all",
    };
    // Unsent text saved by the last reload for a new version (Core.onReload, at the end): answer drafts and the chat field.
    const UNSENT = "vf-unsent";
    const unsent = (() => { try { const v = JSON.parse(sessionStorage.getItem(UNSENT) || "null"); sessionStorage.removeItem(UNSENT); return v; } catch { return null; } })();
    if (unsent) { Object.assign(ui.drafts, unsent.drafts || {}); ui.restoreCur = unsent.cur || ""; }
    const smooth = () => (matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth");
    /** Ring an element briefly; the class comes off again so a reduced-motion ring (no animation) never lingers. */
    const ring = el => {
      el.classList.remove("vf-hl"); void el.offsetWidth; el.classList.add("vf-hl");
      clearTimeout(el._hlT); el._hlT = setTimeout(() => el.classList.remove("vf-hl"), 1200);
    };
    const roundOf = q => q.round || 1;
    const curRound = () => Core.state.round || { current: 1, status: "open" };
    /** Goal, explore requests, citations and Later: always on (the prototype gated them for an older server). */
    const v8 = () => true;
    /** Sent to Claude: "sent" (Cancel works) or "working". */
    const isSentStatus = s => s === "sent" || s === "working";
    /** A round's own status: open, sent, working or closed (an earlier round, still open to late answers). */
    const roundStatus = n => (Core.state.rounds || []).find(r => r.n === n)?.status || (n < curRound().current ? "closed" : curRound().status);
    /** The confirm question's written answer: named apart from the "Something else…" option of choice questions. */
    const CONFIRM_OTHER = "Not exactly";
    // Chat reactions (Phase 4c): the quick row, then the More picker's general set. session.py takes exactly these
    // (CHAT_EMOJI there; test_session.py checks the two match). Plain Unicode: no library, no network.
    const CHAT_EMOJI = ["👍", "👎", "😂", "❤️", "🎉", "😮",
      "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "🙂", "🙃", "😉", "😊", "😇", "🥰", "😍",
      "🤩", "😘", "😋", "😛", "😜", "🤪", "🤗", "🤭", "🤫", "🤔", "🤐", "🤨", "😐", "😑",
      "😶", "😏", "😒", "🙄", "😬", "😌", "😔", "😪", "😴", "😷", "🤒", "🤯", "🥳", "😎",
      "🤓", "🧐", "😕", "😟", "🙁", "😯", "😲", "😳", "🥺", "😢", "😭", "😱", "😤", "😡",
      "👏", "🙌", "👀", "🙏", "💪", "👋", "🤝", "✅", "❌", "💯", "🔥", "✨", "⭐", "💡",
      "🚀", "🎯", "📌", "⚠️"];
    const QUICK_EMOJI = CHAT_EMOJI.slice(0, 6);
    const PURPOSE = { decide: ["Decide", "Vote, then a moderator locks the answer"], gather: ["Gather", "Every answer stands; react to the ones you like"],
      poll: ["Poll", "Pick one; results show once you pick, and the host closes it"] };
    // ---------- my preferences: the server's copy (state.me.prefs) once I have joined, this browser's copy before ----------
    const PK = { pending: {}, out: {}, timer: 0, migrated: false };
    const localKey = () => "vf-prefs:" + (Core.me.cid || "anon");
    /** This browser's copy, over the per-key stores pages used before preferences moved to the server. */
    function localPrefs() {
      const who = Core.me.cid || "anon", th = store.get("vf-theme", {}), t = store.get("vf-tb:" + who, {}), c = store.get("vf-claude:" + who, "");
      const old = { theme: th.mode, accent: th.accent, sort: t.sort, filter: t.filter, round: t.round, claudeTake: c === "session" ? undefined : c || undefined };
      return { ...Object.fromEntries(Object.entries(old).filter(([, v]) => v !== undefined)), ...store.get(localKey(), {}) };
    }
    function prefs() {
      const now = Core.state.serverTime || 0;
      for (const [k, p] of Object.entries(PK.pending)) if (p.ack && now > p.ack) delete PK.pending[k];
      const out = { ...(Core.state.me?.prefs || localPrefs()) };
      for (const [k, p] of Object.entries(PK.pending)) out[k] = p.value;
      return out;
    }
    const pref = (k, d) => prefs()[k] ?? d;
    /** Save now in this browser, and on the server 500 ms after the last change. */
    function setPrefs(patch) {
      for (const [k, v] of Object.entries(patch)) { PK.pending[k] = { value: v }; PK.out[k] = v; }
      store.put(localKey(), { ...store.get(localKey(), {}), ...patch });
      clearTimeout(PK.timer); PK.timer = setTimeout(flushPrefs, 500);
    }
    function flushPrefs() {
      if (dead || !Object.keys(PK.out).length) return;
      if (!Core.state.me) { PK.timer = setTimeout(flushPrefs, 1500); return; } // not joined yet: send once the server knows me
      const set = PK.out; PK.out = {};
      Core.savePrefs(set).then(j => {
        for (const [k, v] of Object.entries(set)) if (PK.pending[k] && JSON.stringify(PK.pending[k].value) === JSON.stringify(v)) PK.pending[k].ack = j.ts;
      }).catch(x => {
        if (x?.status === 400) { for (const k of Object.keys(set)) if (!(k in PK.out)) delete PK.pending[k]; render(); return; }
        PK.out = { ...set, ...PK.out }; clearTimeout(PK.timer); PK.timer = setTimeout(flushPrefs, 3000);
      });
    }
    /** First load after preferences moved to the server: upload this browser's copy when the server has none for me. */
    function migratePrefs() {
      const me = Core.state.me;
      if (PK.migrated || !me) return;
      PK.migrated = true;
      if (Object.keys(me.prefs || {}).length) return;
      const local = localPrefs();
      if (Object.keys(local).length) setPrefs(local);
    }
    // ---------- toolbar: sort, filters, round, remembered per person ----------
    function tb() {
      const p = prefs(), t = { sort: p.sort || "new", filter: p.filter || "all", round: p.round || "all" };
      ui.order = t.sort === "votes" ? "votes" : "new";
      return t;
    }
    function setTb(patch) { setPrefs(patch); render(); }
    const claudePref = () => pref("claudeTake", "session");
    const myTheme = () => { const p = prefs(); return { ...(p.theme ? { mode: p.theme } : {}), ...(p.accent ? { accent: p.accent } : {}) }; };
    const openRounds = () => new Set(pref("expandedRounds", []));
    const setOpenRounds = set => { setPrefs({ expandedRounds: [...set].sort((a, b) => a - b) }); render(); };
    const following = () => !!pref("follow", false) && Core.state.settings.follow !== false;

    // ---------- icons: inline SVG built with createElementNS, never parsed markup ----------
    const SVG = "http://www.w3.org/2000/svg";
    const PATHS = {
      gear: ["M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4z", "M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"],
      thumb: ["M7.5 10.5 11 3.5a2.5 2.5 0 0 1 2.5 2.5v3.5h5a2 2 0 0 1 2 2.3l-1.2 7a2 2 0 0 1-2 1.7H7.5z", "M7.5 10.5h-3a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3"],
      lock: ["M6 11h12a1 1 0 0 1 1 1v7.5a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V12a1 1 0 0 1 1-1z", "M8 11V7.5a4 4 0 0 1 8 0V11"],
      x: ["M7 7l10 10M17 7 7 17"],
      check: ["M5 12.5 9.5 17 19 7.5"],
      chevL: ["M14.5 6 8.5 12l6 6"],
      chevR: ["M9.5 6l6 6-6 6"],
      chevD: ["M6 9.5l6 6 6-6"],
      chevU: ["M6 14.5l6-6 6 6"],
      grip: ["M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01"],
      pencil: ["M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16z", "M13.5 6.5l4 4"],
      sparkle: ["M12 3.5l1.8 5.2 5.2 1.8-5.2 1.8L12 17.5l-1.8-5.2L5 10.5l5.2-1.8z", "M18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"],
      search: ["M10.5 17.5a7 7 0 1 0 0-14 7 7 0 0 0 0 14z", "M20 20l-4.5-4.5"],
      open: ["M14 4h6v6", "M20 4l-8 8", "M10 5H6a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-4"],
      alert: ["M10.3 4.3 2.8 17.5A2 2 0 0 0 4.5 20.5h15a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0z", "M12 9.5v4M12 17h.01"],
      forward: ["M5 12h13", "M13 6.5l5.5 5.5-5.5 5.5"],
      restore: ["M4.5 12a7.5 7.5 0 1 0 2.2-5.3L4.5 9", "M4.5 4.5V9H9"],
      play: ["M8 5.5v13l10.5-6.5z"],
      doc: ["M7 3h7l5 5v12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z", "M14 3v5h5", "M9 13h6M9 17h6"],
      link: ["M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1", "M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"],
      keys: ["M4 6.5h16a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1z", "M7 10h.01M10 10h.01M13 10h.01M16 10h.01M8 14h8"],
      merge: ["M6 4v4a6 6 0 0 0 6 6h0a6 6 0 0 1 6 6", "M18 4v4a6 6 0 0 1-3 5.2", "M15 17l3 3 3-3"],
      chat: ["M6 4.5h12A2.5 2.5 0 0 1 20.5 7v7.5A2.5 2.5 0 0 1 18 17h-6.2l-4.3 3.4c-.5.4-1.2 0-1.2-.6V17H6a2.5 2.5 0 0 1-2.5-2.5V7A2.5 2.5 0 0 1 6 4.5z", "M8.5 10.8h.01M12 10.8h.01M15.5 10.8h.01"],
      more: ["M6.5 12h.01M12 12h.01M17.5 12h.01"],
      list: ["M9 6.5h11M9 12h11M9 17.5h11", "M4.5 6.5h.01M4.5 12h.01M4.5 17.5h.01"],
      columns: ["M4.5 4.5h6v15h-6z", "M13.5 4.5h6v15h-6z"],
      tree: ["M5 4.5h6v4H5z", "M13 10h6v4h-6z", "M13 16h6v4h-6z", "M8 8.5V18h5M8 12h5"],
      clip: ["M19.5 11.2l-7.6 7.6a4.8 4.8 0 0 1-6.8-6.8l8-8a3.2 3.2 0 0 1 4.5 4.5l-8 8a1.6 1.6 0 0 1-2.3-2.3l7.3-7.3"],
      copy: ["M9 9h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V10a1 1 0 0 1 1-1z", "M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"],
      monitor: ["M3.5 5h17a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-17a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z", "M9 20.5h6", "M12 17v3.5"],
      device: ["M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z", "M11 18h2"],
      code: ["M8.5 8 4.5 12l4 4", "M15.5 8l4 4-4 4", "M13.5 5.5l-3 13"],
      host: ["M4 13.5l2.6-7.2A1.5 1.5 0 0 1 8 5.3h8a1.5 1.5 0 0 1 1.4 1l2.6 7.2V18a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18z", "M4 13.5h4.5l1 2h5l1-2H20"],
      cite: ["M6 17.5h4.5V13H7.2c0-2.3.8-3.6 3-4.2L9.6 7C7 7.8 6 9.8 6 13z", "M13.5 17.5H18V13h-3.3c0-2.3.8-3.6 3-4.2L17.1 7c-2.6.8-3.6 2.8-3.6 6z"],
      file: ["M7 3h7l5 5v12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z", "M14 3v5h5"],
      bell: ["M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2H4.5z", "M10 20.5a2.2 2.2 0 0 0 4 0"],
      sun: ["M12 16.5a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9z", "M12 2.5v2M12 19.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4"],
      moon: ["M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z"],
      system: ["M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z", "M9 20.5h6M12 17v3.5", "M12 5v12"],
      send: ["M12 19V5.5", "M6 11.5l6-6 6 6"],
      reply: ["M9.5 7 4.5 12l5 5", "M4.5 12H14a5.5 5.5 0 0 1 5.5 5.5V19"],
      image: ["M4.5 4.5h15a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-13a1 1 0 0 1 1-1z", "M3.5 16l5-5 4 4 2.5-2.5 5.5 5.5", "M15.5 9.5h.01"],
      plus: ["M12 5v14M5 12h14"],
      at: ["M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0z", "M16 12v1.5a2.5 2.5 0 0 0 5 0V12a9 9 0 1 0-3.6 7.2"],
      help: ["M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z", "M9.5 9.3a2.6 2.6 0 0 1 5 .9c0 1.7-2.5 2.3-2.5 3.8", "M12 17h.01"],
    };
    function icon(name, cls = "vf-i") {
      const s = document.createElementNS(SVG, "svg");
      s.setAttribute("viewBox", "0 0 24 24"); s.setAttribute("class", cls); s.setAttribute("aria-hidden", "true");
      for (const d of PATHS[name]) { const p = document.createElementNS(SVG, "path"); p.setAttribute("d", d); s.append(p); }
      return s;
    }

    const offs = []; let dead = false;
    const on = (t, ev, fn, opt) => { t.addEventListener(ev, fn, opt); offs.push(() => t.removeEventListener(ev, fn, opt)); };
    const btn = (cls, text) => { const b = E("button", cls, text); b.type = "button"; return b; };
    /** Icon-only button with an accessible name. */
    const ibtn = (cls, name, label) => { const b = btn(cls); b.append(icon(name)); b.setAttribute("aria-label", label); b.title = label; return b; };
    /** Icon and label button. */
    const lbtn = (cls, name, text) => { const b = btn(cls); b.append(icon(name), E("span", null, text)); return b; };
    /** The "View larger" badge drawn over a picture that opens the picture viewer. */
    // ---------- where an answer was made: sent with answers, picks, votes and suggestions; only the host sees it ----------
    const browserName = () => {
      const u = navigator.userAgent;
      const b = /Edg\//.test(u) ? "Edge" : /OPR\//.test(u) ? "Opera" : /Firefox\//.test(u) ? "Firefox" : /Chrome\//.test(u) ? "Chrome" : /Safari\//.test(u) ? "Safari" : "another browser";
      const os = /iPhone|iPad/.test(u) ? "iOS" : /Android/.test(u) ? "Android" : /Windows/.test(u) ? "Windows" : /Mac OS X/.test(u) ? "macOS" : /Linux/.test(u) ? "Linux" : "";
      return os ? `${b} on ${os}` : b;
    };
    Core.context = () => {
      const coarse2 = matchMedia("(pointer: coarse)").matches, small = matchMedia("(max-width: 720px)").matches;
      return { view: ui.mode, device: coarse2 ? (small ? "phone" : "tablet") : "computer", browser: browserName(), vw: innerWidth, vh: innerHeight,
        tab: phone.matches ? ui.tab : "", qid: ui.cur || "", round: Core.state.questions.length ? curRound().current : null };
    };
    const VIEW_NAME = { focus: "Focus", compare: "Compare", tree: "Tree", host: "Host" };
    const ctxText = c => `${{ phone: "On a phone", tablet: "On a tablet", computer: "On a computer" }[c.device] || "Device unknown"}${c.browser ? `, ${c.browser}` : ""}${c.vw ? `, ${c.vw}×${c.vh}` : ""}${c.view ? `, in ${VIEW_NAME[c.view] || c.view}` : ""}`;
    /** A small device icon with the full context as its tooltip and accessible name. */
    function ctxBadge(el, c) {
      el.hidden = !c;
      if (!c) return;
      const key = JSON.stringify(c);
      if (el._k === key) return;
      el._k = key;
      el.replaceChildren(icon(c.device === "computer" ? "monitor" : "device"));
      el.title = ctxText(c); el.setAttribute("aria-label", ctxText(c)); el.setAttribute("role", "img");
    }
    const dlgOpen = () => !!root.querySelector("dialog.vf-dlg[open]");
    const radioDot = () => { const s = E("span", "vf-radio"); s.setAttribute("aria-hidden", "true"); return s; };
    // ---------- confirmations for actions that are hard to take back ----------
    // A modal dialog: it names the consequence, Cancel has focus, Escape cancels, and the risky button looks risky.
    const cdlg = E("dialog", "vf-dlg vf-cdlg"); cdlg.setAttribute("role", "alertdialog");
    const cdTitle = E("h2", "vf-dlg-title"), cdBody = E("p", "vf-dlg-body");
    cdTitle.id = "vf-cd-title"; cdBody.id = "vf-cd-body";
    cdlg.setAttribute("aria-labelledby", cdTitle.id); cdlg.setAttribute("aria-describedby", cdBody.id);
    const cdRow = E("div", "vf-crow vf-dlg-row");
    const cdNo = btn("vf-btn vf-btn-ghost", "Cancel"), cdYes = btn("vf-btn vf-btn-danger-solid");
    cdRow.append(E("span", "vf-spacer"), cdNo, cdYes);
    cdlg.append(cdTitle, cdBody, cdRow);
    root.append(cdlg);
    let cdDone = null;
    /** Ask before a critical action. Resolves true only on the action button. */
    function confirmAct({ title, body, ok, safe = "Cancel", danger = true }) {
      if (cdlg.open) return Promise.resolve(false);
      const from = document.activeElement;
      cdTitle.textContent = title; cdBody.textContent = body; cdYes.textContent = ok; cdNo.textContent = safe;
      cdYes.className = `vf-btn ${danger ? "vf-btn-danger-solid" : "vf-btn-primary"}`;
      cdlg.showModal(); cdNo.focus();
      return new Promise(res => {
        cdDone = v => { cdDone = null; if (cdlg.open) cdlg.close(); if (from?.isConnected) from.focus({ preventScroll: true }); res(v); };
      });
    }
    cdYes.onclick = () => cdDone?.(true);
    cdNo.onclick = () => cdDone?.(false);
    cdlg.addEventListener("close", () => cdDone?.(false)); // Escape
    const REPORT_ASK = { title: "Ask Claude about this report?", body: "Claude reads the report and its screenshot as the reporter's words, works out what likely went wrong and proposes a fix to you in the terminal. It never acts on the report itself.", ok: "Ask Claude" };
    const removeAsk = name => ({ title: `Remove ${disp(name)}?`, ok: "Remove", body: `${disp(name)}'s link stops working and their answers, votes, chat and suggestions are hidden from everyone. You can restore them from Settings.` });
    const PARK_ASK = { title: "Park this proposal?", ok: "Park", body: "It stays out of the round, so Claude does not see it when the round is sent. You can restore it from Parked." };
    const LATER_ASK = { title: "Move this proposal to Later?", ok: "Move to Later", body: "It leaves this round and becomes a tracker item when the session ends. You can restore it before then." };
    /** Wrap a click handler so it runs only after the person confirms. */
    const guarded = (opts, run) => async e => { const o = typeof opts === "function" ? opts() : opts; if (o && !(await confirmAct(o))) return; run(e); };

    const zoomTag = () => { const t = E("span", "vf-zoomtag"); t.setAttribute("aria-hidden", "true"); t.append(icon("search"), E("span", null, "View larger")); return t; };
    const st = () => Core.state.settings;
    const disp = name => (st().showNames ? name : Core.initials(name));
    /** Avatar for a person. data-pid makes it open the person card; focusable avatars sit outside buttons. */
    const av = (cid, name, size, focusable = false) => {
      const a = Core.avatar(cid, name, size);
      a.title = ""; a.dataset.pid = cid; a.dataset.name = name;
      if (focusable) { a.tabIndex = 0; a.setAttribute("role", "button"); a.setAttribute("aria-label", `${disp(name)}, show details`); }
      return a;
    };
    const claudeAv = size => { const a = E("span", "core-avatar vf-claude-av"); a.style.cssText = `width:${size}px;height:${size}px`; a.append(icon("sparkle")); a.title = "Claude"; return a; };
    const isMe = c => c === Core.me.cid;
    function dots() { const d = E("span", "vf-dots"); d.setAttribute("aria-hidden", "true"); d.append(E("i"), E("i"), E("i")); return d; }
    function ago(ts) {
      const s = Math.max(0, (Core.state.serverTime || Date.now() / 1000) - ts);
      return s < 45 ? "now" : s < 3600 ? Math.round(s / 60) + "m" : s < 86400 ? Math.round(s / 3600) + "h" : Math.round(s / 86400) + "d";
    }
    /** How long a present person has been Away, as " 4m"; "" just now or while active. */
    const awayFor = p => { const a = p?.awaySince ? ago(p.awaySince) : "now"; return a === "now" ? "" : ` ${a}`; };
    function names(list) {
      const n = list.map(p => disp(p.name));
      return n.length <= 2 ? n.join(" and ") : `${n[0]} and ${n.length - 1} others`;
    }
    /** Keyed list sync: reuses nodes by key, creates missing ones, removes stale ones, keeps order. */
    function sync(list, items, key, create, update) {
      const map = list._map || (list._map = new Map());
      const keep = new Set();
      let prev = null;
      for (const it of items) {
        const k = key(it); keep.add(k);
        let node = map.get(k);
        if (!node) {
          node = create(it); map.set(k, node);
          if (list._primed) {
            // Entrance plays once: without this, moving the node (a reorder) would replay it.
            node.classList.add("vf-in");
            const done = e => { if (e.target === node) { node.classList.remove("vf-in"); node.removeEventListener("animationend", done); } };
            node.addEventListener("animationend", done);
          }
        }
        update(node, it);
        const want = prev ? prev.nextSibling : list.firstChild;
        if (want !== node) list.insertBefore(node, want);
        prev = node;
      }
      for (const [k, node] of map) if (!keep.has(k)) { node.remove(); map.delete(k); }
      list._primed = true;
    }
    function resetList(list) { list.replaceChildren(); list._map = null; list._primed = false; }
    /** A long list's first `def` items, then a Show more control under it (`all`: one Show all (N) instead). How far
     *  a list was opened lives in ui.more under the key `page` is given, so a filter keys its own. Show more moves
     *  focus to the first item it reveals. Returns {foot, page(items, list, key)}: put foot after the list. */
    function showMore(listKey, def, { all = false } = {}) {
      const foot = E("div", "vf-more-foot"), note = E("span", "vf-meta"), b = btn("vf-btn vf-btn-ghost vf-btn-sm");
      foot.append(note, b); foot.hidden = true;
      let list = null, key = listKey, n = def;
      b.onclick = () => {
        const from = n;
        ui.more[key] = all ? Infinity : n + def;
        render();
        const li = list?.children[from], f = li && (li.querySelector("button:not([hidden]), [tabindex='0']") || li);
        if (f === li) li.tabIndex = -1;
        f?.focus();
      };
      return {
        foot,
        page(items, el, k = listKey) {
          list = el; key = k; n = Math.min(items.length, ui.more[k] ?? def);
          foot.hidden = items.length <= n;
          note.textContent = `Showing ${n} of ${items.length}`;
          b.textContent = all ? `Show all (${items.length})` : "Show more";
          return items.slice(0, n);
        },
      };
    }
    /** Active, away or offline, from a presence entry (none: offline), and how a label says it. */
    const presState = h => (!h ? "offline" : h.away ? "away" : "active");
    const presWord = h => (!h ? "offline" : h.away ? `away${awayFor(h)}` : "active");
    /** The presence dot at an avatar's bottom-right; aria-hidden, as the state is in the label beside or on it. */
    function presDot(a, h) {
      a.dataset.presence = presState(h);
      if (!a.querySelector(".vf-pres")) { const d = E("span", "vf-pres"); d.setAttribute("aria-hidden", "true"); a.append(d); }
      return a;
    }
    /** Avatars in a row; `presence` true: the people are presence entries, each shown with its dot and named with its state. */
    function avStack(holder, people, max, size = 20, presence = false) {
      const one = p => {
        const a = av(p.cid, p.name, size);
        if (presence) { presDot(a, p); a.setAttribute("role", "img"); a.setAttribute("aria-label", `${disp(p.name)}, ${presWord(p)}`); }
        return a;
      };
      holder.replaceChildren(...people.slice(0, max).map(one));
      if (people.length > max) holder.append(E("span", "vf-more", "+" + (people.length - max)));
    }
    const votesOf = a => a.votes?.length || 0;
    // Most votes first; on a tie Claude's recommendation first, then the earliest.
    const byVotes = list => list.slice().sort((a, b) => votesOf(b) - votesOf(a) || !!b.rec - !!a.rec || a.ts - b.ts);
    /** The single answer with the most votes; none while two or more tie. */
    const leadOf = qid => { const [top, next] = byVotes(Core.answersFor(qid)); return top && votesOf(top) && (!next || votesOf(next) < votesOf(top)) ? top.cid : ""; };
    /** Display order: the locked answer first, then newest or most votes as this viewer chose. */
    function ordered(qid) {
      const lk = Core.lockOf(qid);
      tb();
      const all = Core.answersFor(qid).filter(a => !a.option);
      const list = ui.order === "votes" ? byVotes(all) : all.slice().sort((a, b) => b.ts - a.ts);
      const i = lk ? list.findIndex(a => a.cid === lk.answerCid) : -1;
      if (i > 0) list.unshift(...list.splice(i, 1));
      return list;
    }
    const agreeing = a => Core.state.presence.filter(p => p.cid === a.cid || (a.votes || []).includes(p.cid)).length;
    const openSugs = qid => Core.suggestionsFor(qid).filter(s => s.status === "open");
    const qById = id => Core.state.questions.find(q => q.id === id);
    /** Read-only once its round went to Claude (an earlier round, or the current one while preparing), or the session ended. */
    const isSent = q => isSentStatus(roundStatus(roundOf(q)));
    /** Placed in a round that has not opened yet: shown, read-only. */
    const notOpenYet = q => roundOf(q) > curRound().current;
    const readOnly = q => !!q && (isSent(q) || notOpenYet(q) || (!!Core.state.ended && !Core.me.isOwner) || !!Core.state.youRemoved);
    /** My answer record: text, or a pick on a choice question, or both. */
    const myRec = qid => Core.answersFor(qid).find(a => a.cid === Core.me.cid && !a.option && !a.claude);
    const hasAnswered = qid => !!myRec(qid);
    const askedOfMe = qid => Core.askedOf(qid).includes(Core.me.cid);
    /** Someone else's answer (not Claude's, not an option): one makes a question not asked of me by name optional. */
    const otherAnswer = qid => Core.answersFor(qid).find(a => !a.claude && !a.option && a.cid !== Core.me.cid);
    /** Where a question stands for me (triage row 42): answered (my own answer), took (I voted, reacted, disagreed or
     *  passed: Core.tookPart), soft (someone else answered and it is not asked of me, so it is optional), or open. Only
     *  open counts as not answered, as the server's behind count does (session.py _owes). */
    function myState(qid) {
      if (hasAnswered(qid)) return "answered";
      if (Core.tookPart(qid)) return "took";
      return !askedOfMe(qid) && otherAnswer(qid) ? "soft" : "open";
    }
    /** Not yet taken part in, optional or not: where landing, Next and Start here go. Counts use myState "open" only. */
    const isOpenForMe = id => { const q = qById(id); return !!q && ["open", "soft"].includes(myState(id)) && !Core.lockOf(id) && !readOnly(q); };
    /** Triage row 43 (Q100): the earliest closed round with unlocked questions I have not taken part in, and those
     *  questions; answers there still go to Claude, marked late. Null when there is none, or for the owner. */
    function catchUp() {
      const S = Core.state;
      if (Core.me.isOwner || !S.me || S.ended || S.youRemoved) return null;
      const behind = S.questions.filter(q => roundStatus(roundOf(q)) === "closed" && !Core.lockOf(q.id) && ["open", "soft"].includes(myState(q.id)));
      if (!behind.length) return null;
      const n = Math.min(...behind.map(roundOf)), qs = behind.filter(q => roundOf(q) === n);
      return { n, qs, text: `Round ${n} has ${qs.length} question${qs.length === 1 ? "" : "s"} you haven't answered. Answers there still go to Claude, marked late.` };
    }
    /** The catch-up line: what is behind, and a link that opens its first question. */
    function catchUpEl(onGo) {
      const p = E("p", "vf-catchup"), t = E("span", "vf-catchup-t"), go = btn("vf-linkbtn vf-catchup-go");
      p.append(t, " ", go);
      go.onclick = () => { const id = p._q; if (!id) return; onGo?.(); focusQuestion(id); };
      p._paint = cu => { p.hidden = !cu; if (!cu) return; t.textContent = cu.text; go.textContent = `Catch up on round ${cu.n}`; p._q = cu.qs[0].id; };
      return p;
    }
    const optionsOf = q => q?.options || [];
    /** A question that takes a pick (its options are the vote), not a written answer. */
    const isChoice = q => ["choice", "confirm", "multi", "scale", "rank"].includes(q?.format);
    const isFormat = q => ["multi", "scale", "rank"].includes(q?.format);
    /** The server-added "Something else…" option, where the question has one. */
    const otherOf = q => optionsOf(q).find(o => o.other) || null;
    const realOptions = q => optionsOf(q).filter(o => !o.other);
    /** My saved pick as the fields /api/pick takes, or null with none. */
    function savedPick(q, rec) {
      if (!q || !rec) return null;
      if (q.format === "multi") return rec.picks?.length ? { options: rec.picks } : null;
      if (q.format === "scale") return rec.value != null ? { value: rec.value } : null;
      if (q.format === "rank") return rec.order?.length ? { order: rec.order } : null;
      return rec.pick ? { option: rec.pick } : null;
    }
    const pickLabel = (q, id) => optionsOf(q).find(o => o.id === id)?.label || id;
    /** What a person card picked, in words: "Picked: Card", "Picked: A, B", "Chose 4 of 5", "Ranked: A > B > C". */
    function pickedText(q, a) {
      if (!q || a.claude || a.option) return "";
      const own = `${isMe(a.cid) ? "your" : "their"} own option`;
      if (a.picks?.length) return `Picked: ${a.picks.filter(o => o !== "other").map(o => pickLabel(q, o)).join(", ")}${a.other ? `${a.picks.length > 1 ? ", and " : ""}${own}` : ""}`;
      if (a.value != null) { const end = a.value === q.min ? q.labels?.min : a.value === q.max ? q.labels?.max : ""; return `Chose ${a.value} of ${q.max}${end ? ` (${end})` : ""}`; }
      if (a.order?.length) return `Ranked: ${a.order.map(o => (o === "other" ? own : pickLabel(q, o))).join(" > ")}`;
      if (a.pick === "other") return own[0].toUpperCase() + own.slice(1);
      const opt = a.pick && optionsOf(q).find(o => o.id === a.pick);
      if (opt) return `Picked: ${opt.label}`;
      return q.format === "confirm" ? CONFIRM_OTHER : "";
    }
    const assetUrl = id => "/assets/" + encodeURIComponent(id);
    /** People's answers and Claude's cards; a choice question's options render as their own cards above. */
    const peopleAnswers = qid => Core.answersFor(qid).filter(a => !a.option);
    const iVoted = qid => Core.answersFor(qid).some(a => (a.votes || []).includes(Core.me.cid));
    /** C26: Claude's cards wait until I answered or voted, unless I chose Always show (session default from ⚙). */
    function claudeHidden(qid) {
      const pref = claudePref(), want = pref === "session" ? st().hideClaude !== false : pref === "answerFirst";
      return want && !ui.revealed.has(qid) && !hasAnswered(qid) && !iVoted(qid);
    }
    /** ux-review-2 #5: under Answer first, a guest sees no one's picks (counts, Leading, avatars, pick cards) until they
     *  answered or voted, so the first voter does not steer them. A poll always waits for a pick; the owner, moderators
     *  and a locked question see everything. */
    function resultsWait(q) {
      if (!q || Core.me.isOwner || Core.lockOf(q.id)) return false;
      if (q.purpose === "poll") return !savedPick(q, myRec(q.id));
      const pref = claudePref(), want = pref === "session" ? st().hideClaude !== false : pref === "answerFirst";
      // Picks only: on a written question, voting for someone else's answer is how a guest takes part.
      return want && isChoice(q) && !Core.canModerate() && !ui.revealed.has(q.id) && !hasAnswered(q.id) && !iVoted(q.id);
    }
    /** Why a Claude card shows while the others wait: chosen already. */
    function claudeChosen(a, qid, lead) {
      const lk = Core.lockOf(qid);
      if (lk && lk.answerCid === a.cid) return "locked";
      if (lead === a.cid) return "leading";
      if (votesOf(a)) return "voted";
      return "";
    }

    // ---------- safe rich text: paragraphs, "- " lists and bare http(s) links, built as DOM nodes ----------
    const LINK = /\bhttps?:\/\/[^\s<>"']+/g;
    function inline(parent, line) {
      let i = 0;
      for (const m of line.matchAll(LINK)) {
        const url = m[0].replace(/[).,;:!?]+$/, "");
        if (m.index > i) withMentions(parent, line.slice(i, m.index));
        let ok = false;
        try { ok = ["http:", "https:"].includes(new URL(url).protocol); } catch {}
        if (ok) { const a = E("a", "vf-link", url); a.href = url; a.target = "_blank"; a.rel = "noopener noreferrer"; parent.append(a); }
        else parent.append(url);
        i = m.index + url.length;
      }
      if (i < line.length) withMentions(parent, line.slice(i));
    }
    // ---------- @mentions: Core turns the server's <@pid> into "@Name" as this page shows that person; each renders as a chip ----------
    const MN = { labels: null, re: null };
    function mentionRe() {
      const labels = Core.mentionLabels();
      if (labels !== MN.labels) { MN.labels = labels; MN.re = Core.labelRe([...labels, ["someone", ""]]); }
      return MN.re;
    }
    function withMentions(parent, s) {
      const re = s.includes("@") ? mentionRe() : null;
      if (!re) { parent.append(s); return; }
      const by = new Map(Core.mentionLabels().map(([l, p]) => [l.toLowerCase(), p]));
      let i = 0;
      for (const m of s.matchAll(re)) {
        const at = m.index + m[1].length, pid = by.get(m[2].toLowerCase()) || "";
        if (at > i) parent.append(s.slice(i, at));
        parent.append(E("span", "vf-mention" + (pid && isMe(pid) ? " vf-mention-me" : ""), "@" + m[2]));
        i = at + 1 + m[2].length;
      }
      if (i < s.length) parent.append(s.slice(i));
    }
    function rich(text) {
      const f = document.createDocumentFragment();
      for (const block of String(text || "").replace(/\r/g, "").split(/\n\s*\n/)) {
        let p = null, ul = null;
        for (const raw of block.split("\n")) {
          const m = raw.match(/^\s*[-*•]\s+(.*)$/);
          if (m) { p = null; if (!ul) { ul = E("ul", "vf-ul"); f.append(ul); } const li = E("li"); inline(li, m[1]); ul.append(li); }
          else if (raw.trim()) { ul = null; if (p) p.append(E("br")); else { p = E("p"); f.append(p); } inline(p, raw); }
        }
      }
      return f;
    }
    function setRich(el, text) { if (el._t !== text) { el._t = text; el.replaceChildren(rich(text)); } }

    // ---------- clamped text: ~6 lines, Show more expands in place, Open shows it in the reader ----------
    function clampBox(cls = "") {
      const box = E("div", ("vf-cbox " + cls).trim());
      const body = E("div", "vf-rich vf-clamp");
      const ctl = E("div", "vf-cctl"); ctl.hidden = true;
      const more = btn("vf-lbtn"), open = lbtn("vf-lbtn", "open", "Open");
      ctl.append(more, open);
      box.append(body, ctl);
      more.onclick = () => { ui.exp.has(box._key) ? ui.exp.delete(box._key) : ui.exp.add(box._key); paintClamp(box); measure(box); };
      open.onclick = () => openReader(box._title, box._meta, body._t, open);
      Object.assign(box, { _body: body, _more: more, _ctl: ctl });
      return box;
    }
    function fillClamp(box, key, text, title, meta) {
      Object.assign(box, { _key: key, _title: title, _meta: meta });
      setRich(box._body, text); paintClamp(box);
    }
    function paintClamp(box) {
      const x = ui.exp.has(box._key);
      box._body.classList.toggle("vf-exp", x);
      box._more.textContent = x ? "Show less" : "Show more";
      box._more.setAttribute("aria-expanded", String(x));
    }
    function measure(box) {
      if (!box.offsetParent) return;
      const b = box._body;
      if (ui.exp.has(box._key)) { box._ctl.hidden = false; b.classList.remove("vf-over"); return; }
      const over = b.scrollHeight > b.clientHeight + 1;
      b.classList.toggle("vf-over", over);
      box._ctl.hidden = !over;
    }
    const measureAll = () => root.querySelectorAll(".vf-cbox").forEach(measure);

    /** Textareas grow with their text up to ~40% of the pane they sit in, then scroll inside. */
    function grow(t) {
      const pane = t.closest(".vf-center, .vf-chat, .vf-pop, .vf-rail") || root;
      const max = Math.max(80, pane.clientHeight * 0.4);
      t.style.blockSize = "auto";
      const h = t.scrollHeight + 2;
      t.style.blockSize = Math.min(h, max) + "px";
      t.style.overflowY = h > max ? "auto" : "hidden";
      // Triage 23: a field growing while I type stays in view, with its form's send button when the form fits.
      if (document.activeElement === t && !t.closest(".vf-composer-sheet")) reveal(t.closest("form") || t, t);
    }
    /** The nearest scrolling ancestor of el, never #app or the page. */
    function scroller(el) {
      let sc = el.parentElement;
      while (sc && sc !== root && !(/auto|scroll/.test(getComputedStyle(sc).overflowY) && sc.scrollHeight > sc.clientHeight)) sc = sc.parentElement;
      return sc && sc !== root ? sc : null;
    }
    /** The part of scroller sc a person sees: its box inside the visual viewport, less the sticky or fixed rows in it
     *  that sit in keep's column without holding it or being held by it, since they cover what scrolls under them. */
    function seenBand(sc, keep) {
      const S = sc.getBoundingClientRect(), K = keep.getBoundingClientRect(), vv = window.visualViewport;
      let top = Math.max(S.top, vv ? vv.offsetTop : 0), bottom = Math.min(S.bottom, vv ? vv.offsetTop + vv.height : innerHeight);
      for (const s of sc.querySelectorAll("*")) {
        const cs = getComputedStyle(s);
        if ((cs.position !== "sticky" && cs.position !== "fixed") || keep.contains(s) || s.contains(keep)) continue;
        const r = s.getBoundingClientRect(), h = r.height;
        if (!h || r.right <= K.left || r.left >= K.right) continue;
        if (cs.insetBlockEnd !== "auto") bottom -= h; else top += h;
      }
      return { top, bottom };
    }
    /** Scroll sc by the least that brings the range top..bottom inside band, its top first. */
    function scrollInto(sc, top, bottom, band) {
      if (top < band.top) sc.scrollTop -= band.top - top + 4;
      else if (bottom > band.bottom) sc.scrollTop += Math.min(bottom - band.bottom + 4, top - band.top);
    }
    /** Scroll the nearest scrolling ancestor so el is in view; if el does not fit, keep must in view. Sticky rows count
     *  as covering. */
    function reveal(el, must = el) {
      const sc = scroller(must);
      if (!sc) return;
      let band = seenBand(sc, el);
      const fits = el.getBoundingClientRect().height <= band.bottom - band.top;
      if (!fits) band = seenBand(sc, must);
      const r = (fits ? el : must).getBoundingClientRect();
      scrollInto(sc, r.top, r.bottom, band);
    }

    // ---------- toast ----------
    // The toast is a live region from load; text goes in a frame after it is cleared, so screen readers announce it.
    const toast = E("div", "vf-toast"); toast.setAttribute("role", "status");
    const toastTxt = E("span"), toastAct = btn("vf-toast-act");
    toastAct.hidden = true;
    toast.append(toastTxt, toastAct);
    // A second, visually hidden polite region for content that arrives (new answers), never the answer list itself.
    const srLive = E("div", "vf-sr"); srLive.setAttribute("aria-live", "polite");
    let toastT = 0, clearT = 0, toastPaint = 0;
    const toastQ = [];
    function flash(msg, action) {
      // A second message in the same pass (a new round and a placed proposal) waits its turn instead of
      // overwriting the first before it paints.
      if (toastPaint) { toastQ.push([msg, action]); return; }
      clearTimeout(toastT); clearTimeout(clearT);
      toastTxt.textContent = ""; toastAct.hidden = true;
      toastPaint = requestAnimationFrame(() => {
        toastPaint = 0;
        toastTxt.textContent = msg;
        toastAct.hidden = !action;
        if (action) { toastAct.textContent = action.label; toastAct.onclick = () => { hideToast(); action.run(); }; }
        placeToast();
        toast.classList.add("vf-on");
      });
      toastT = setTimeout(() => (toastQ.length ? flash(...toastQ.shift()) : hideToast()), action ? 9000 : 3200);
    }
    /** Centered on the center pane (the part the chat leaves uncovered; the whole page when the pane is hidden),
     *  12px above whatever is docked at the bottom under it: tab bar, chat button, panel or the phone edit sheet. */
    function placeToast() {
      const R = root.getBoundingClientRect(), C = center.getBoundingClientRect(), side = !chat.hidden ? chat : askPanel.isConnected && !askPanel.hidden && !drawerSheet.matches ? askPanel : null, ch = side ? side.getBoundingClientRect() : null;
      let L = C.width ? C.left : R.left, Rt = C.width ? C.right : R.right;
      const fit = () => {
        toast.style.insetInlineStart = (L + Rt) / 2 - R.left + "px";
        toast.style.setProperty("--toast-room", Rt - L - 32 + "px");
        return toast.offsetWidth;
      };
      let w = fit();
      // only when the open chat panel would sit under it, center it on the part of the pane the chat leaves
      if (ch && ch.left > L + 200 && ch.left < (L + Rt) / 2 + w / 2) { Rt = ch.left - 8; w = fit(); }
      const l = (L + Rt) / 2 - w / 2, r = l + w;
      let bottom = R.bottom - 16;
      for (const el of root.querySelectorAll(".vf-tabs, .vf-fab, .vf-chat, .vf-panel, .vf-drawer, .vf-composer-sheet")) {
        const b = el.getBoundingClientRect();
        if (!b.height || el.closest("[hidden]") || getComputedStyle(el).visibility === "hidden" || b.right <= l || b.left >= r || b.bottom < R.bottom - 160) continue;
        bottom = Math.min(bottom, b.top - 12);
      }
      // A tall panel under it: drop in under the top bar instead of floating mid-page.
      const high = bottom < R.top + R.height / 2;
      toast.style.insetBlockEnd = high ? "auto" : Math.max(8, R.bottom - bottom) + "px";
      toast.style.insetBlockStart = high ? top.getBoundingClientRect().bottom - R.top + 8 + "px" : "";
    }
    function hideToast() {
      toast.classList.remove("vf-on");
      clearT = setTimeout(() => { toastTxt.textContent = ""; toastAct.hidden = true; }, 250);
    }
    function announce(msg) { srLive.textContent = ""; requestAnimationFrame(() => { srLive.textContent = msg; }); }
    const fail = e => {
      if (e?.agree != null) return flash(`Not everyone agrees yet: ${e.agree} of ${e.total} have voted for it.`);
      flash(`Not saved: ${Core.errorText(e)}`, { label: "Report this", run: () => openReport() });
    };

    // ---------- top bar ----------
    const top = E("header", "vf-top");
    const brand = E("div", "vf-brand");
    const titleTxt = E("span", "vf-title");
    const titleEdit = ibtn("vf-tbtn vf-tbtn-quiet vf-pencil", "pencil", "Rename this session");
    const titleInput = E("input", "vf-input vf-title-input"); titleInput.maxLength = 80; titleInput.hidden = true; titleInput.setAttribute("aria-label", "Session title");
    // The goal: one line under the title for everyone; the owner sets it with the pencil.
    const titles = E("div", "vf-titles"), titleRow = E("div", "vf-titlerow"), goalRow = E("div", "vf-goalrow");
    const goalTxt = E("span", "vf-goal");
    const goalEdit = ibtn("vf-tbtn vf-tbtn-quiet vf-pencil vf-goal-pencil", "pencil", "Set the session goal");
    const goalAdd = btn("vf-goal-add", "Add a goal");
    const goalInput = E("input", "vf-input vf-goal-input"); goalInput.maxLength = 200; goalInput.hidden = true;
    goalInput.setAttribute("aria-label", "Session goal"); goalInput.placeholder = "What this session should settle";
    titleRow.append(titleTxt, titleInput, titleEdit);
    goalRow.append(goalTxt, goalAdd, goalInput, goalEdit);
    titles.append(titleRow, goalRow);
    brand.append(E("span", "vf-mark"), titles);
    const live = E("span", "vf-live"); live.setAttribute("role", "status");
    const liveTxt = E("span", "vf-live-txt");
    live.append(E("span", "vf-live-dot"), liveTxt);
    const people = E("div", "vf-people"); people.setAttribute("aria-label", "People here");
    const hereCount = E("span", "vf-here");
    const shareBtn = lbtn("vf-tbtn vf-sharebtn", "link", "Share"); shareBtn.setAttribute("aria-haspopup", "dialog");
    const shareTxt = shareBtn.lastChild;
    const follow = btn("vf-follow"); follow.setAttribute("aria-pressed", "false");
    const followTxt = E("span", "vf-follow-txt");
    follow.append(E("span", "vf-switch"), followTxt);
    const keysBtn = ibtn("vf-tbtn vf-icon-btn vf-keysbtn", "help", "Help: the tour and keyboard shortcuts (?)"); keysBtn.setAttribute("aria-haspopup", "dialog");
    const gear = ibtn("vf-tbtn vf-icon-btn vf-gear", "gear", "Session settings"); gear.setAttribute("aria-haspopup", "dialog");
    // Ask Claude: the session panel; the 💬 bubble is people chat only.
    const askTop = lbtn("vf-tbtn vf-asktop", "sparkle", "Ask Claude"); askTop.setAttribute("aria-haspopup", "dialog"); askTop.setAttribute("aria-expanded", "false");
    askTop.setAttribute("aria-label", "Ask Claude");
    // Q87: one tap cycles System, Light, Dark; saved with my preferences.
    const themeBtn = btn("vf-tbtn vf-icon-btn vf-themebtn");
    // Item 11: the Inbox in the bell's place: my requests, what waits on the host, and every notification, with one unread count.
    const bellBtn = btn("vf-tbtn vf-bell vf-inboxbtn"); bellBtn.setAttribute("aria-haspopup", "dialog"); bellBtn.setAttribute("aria-expanded", "false");
    const bellBadge = E("span", "vf-bell-n");
    bellBtn.append(icon("host"), E("span", "vf-inbox-l", "Inbox"), bellBadge);
    top.append(brand, live, E("div", "vf-spacer"), people, hereCount, askTop, shareBtn, follow, keysBtn, themeBtn, bellBtn, gear);

    // ---------- rail ----------
    const body = E("main", "vf-body");
    const rail = E("aside", "vf-rail");
    const railHead = E("div", "vf-head");
    const railMeta = E("span", "vf-meta");
    railHead.append(E("h2", "vf-h2", "Questions"), railMeta);
    const rounds = E("div", "vf-rounds");
    const groups = E("div", "vf-groups");
    const nextBox = E("div", "vf-next"); nextBox.setAttribute("role", "status");
    const nextTxt = E("span", "vf-next-txt");
    const cancelSend = btn("vf-btn vf-btn-ghost vf-btn-sm vf-cancel-send", "Cancel sending");
    cancelSend.hidden = true;
    cancelSend.onclick = guarded(() => ({ title: `Cancel sending round ${curRound().current}?`, body: "Claude will not pick this round up. It goes back to open, so people can answer and vote again until you send it.", ok: "Cancel sending", safe: "Keep it sent" }),
      () => Core.cancelRound().then(() => flash("Round reopened. Send it again when it is ready.")).catch(fail));
    /** Q78: after Send, the same three steps for everyone. A real sequence, so it is an ordered list. */
    function makeStepper() {
      const ol = E("ol", "vf-steps");
      ol._items = ["sent", "working", "here"].map(k => { const li = E("li", "vf-step"); li.dataset.k = k; li.append(E("span", "vf-step-dot"), E("span", "vf-step-txt")); ol.append(li); return li; });
      return ol;
    }
    function fillStepper(ol, R) {
      const st2 = R.status === "working" ? 1 : 0, n = R.current + 1;
      const labels = ["Waiting for Claude", "Claude is working", `Round ${n} is here`];
      ol._items.forEach((li, i) => {
        li.lastChild.textContent = labels[i];
        li.dataset.state = i < st2 ? "done" : i === st2 ? "now" : "todo";
        if (i === st2) li.setAttribute("aria-current", "step"); else li.removeAttribute("aria-current");
      });
      ol.setAttribute("aria-label", `Round ${R.current} went to Claude: ${labels[st2]}`);
    }
    const railSteps = makeStepper();
    const stepNote = E("p", "vf-step-note");
    nextBox.append(nextTxt, railSteps, stepNote, cancelSend);
    const railEmpty = E("p", "vf-empty vf-empty-sm vf-rail-empty", "No questions yet. Round 1 lists here as soon as it opens.");
    rounds.append(railEmpty, groups, nextBox);
    const railFoot = E("div", "vf-railfoot");
    function railRow(label) {
      const b = btn("vf-proprow"); b.setAttribute("aria-haspopup", "dialog"); b.setAttribute("aria-expanded", "false");
      const count = E("span", "vf-count");
      b.append(E("span", "vf-proprow-label", label), count, icon("chevR", "vf-i vf-chev"));
      b._count = count;
      return b;
    }
    const propRow = railRow("Proposed");
    const reqRow = railRow("Requests");
    const myProp = E("ul", "vf-myprops"); myProp.setAttribute("aria-label", "Your proposals");
    const proposeBtn = lbtn("vf-btn vf-btn-ghost vf-propose", "plus", "Propose a question");
    proposeBtn.setAttribute("aria-haspopup", "dialog"); proposeBtn.setAttribute("aria-expanded", "false");
    railFoot.append(reqRow, propRow, myProp, proposeBtn);
    rail.append(railHead, rounds, railFoot);

    // Propose a question: anyone; it goes to Proposed, and Claude places it with the next round or says why not. The one
    // Propose form: every way in opens it, beside this button on a wide screen and as a bottom sheet on a phone.
    const proposePop = E("form", "vf-pop vf-proposepop"); proposePop.setAttribute("role", "dialog"); proposePop.setAttribute("aria-label", "Propose a question"); proposePop.hidden = true;
    const propTa = E("textarea", "vf-ta"); propTa.rows = 3; propTa.maxLength = 2000; propTa.id = "vf-prop-ta";
    const propLabel = E("label", "vf-asklabel", "What should the group be asked?"); propLabel.htmlFor = propTa.id;
    const propRowB = E("div", "vf-crow");
    const propCancel = btn("vf-btn vf-btn-ghost", "Cancel");
    const propSend = E("button", "vf-btn vf-btn-primary", "Propose"); propSend.type = "submit";
    propRowB.append(propCancel, propSend);
    proposePop.append(E("h2", "vf-pop-title", "Propose a question"), propLabel, propTa,
      E("p", "vf-pop-note", "It goes to Proposed. Claude places it in the next round or says why not."), propRowB);

    // Report a problem: from More, Help or a refused action's toast, placed as the Propose form is (a bottom sheet on a
    // phone, so it sits right on the keyboard). "Sent with this report" lists everything that goes with it before Send.
    const reportPop = E("form", "vf-pop vf-reportpop"); reportPop.setAttribute("role", "dialog"); reportPop.setAttribute("aria-label", "Report a problem"); reportPop.hidden = true;
    const repTa = E("textarea", "vf-ta"); repTa.rows = 3; repTa.maxLength = 2000; repTa.id = "vf-rep-ta"; repTa.required = true;
    const repLabel = E("label", "vf-asklabel", "What went wrong?"); repLabel.htmlFor = repTa.id;
    const repCount = E("span", "vf-rep-count", "0 / 2000");
    const repFile = E("input", "vf-rep-file"); repFile.type = "file"; repFile.accept = "image/png,image/jpeg,image/webp"; repFile.id = "vf-rep-file";
    const repFileLabel = E("label", "vf-btn vf-btn-ghost vf-btn-sm vf-rep-add", "Add a screenshot"); repFileLabel.htmlFor = repFile.id;
    const repShot = E("img", "vf-rep-shot"); repShot.alt = "Your screenshot"; repShot.hidden = true;
    const repDrop = btn("vf-btn vf-btn-ghost vf-btn-sm vf-rep-drop", "Remove screenshot"); repDrop.hidden = true;
    const repShotRow = E("div", "vf-crow vf-rep-shotrow"); repShotRow.append(repFileLabel, repDrop);
    const repSent = E("ul", "vf-rep-sent"); repSent.setAttribute("aria-label", "Sent with this report");
    const repErr = E("p", "vf-rep-err"); repErr.setAttribute("role", "alert");
    const repRow = E("div", "vf-crow"), repCancel = btn("vf-btn vf-btn-ghost", "Cancel");
    const repSend = E("button", "vf-btn vf-btn-primary", "Send report"); repSend.type = "submit";
    repRow.append(repCount, E("span", "vf-spacer"), repCancel, repSend);
    reportPop.append(E("h2", "vf-pop-title", "Report a problem"), repLabel, repTa, repRow, repShotRow, repFile,
      E("p", "vf-pop-note", "Take a screenshot first, then add it here. Only the host and Claude see your report."), repShot,
      E("h3", "vf-pop-sub", "Sent with this report"), repSent, repErr);

    // Follow-up item 3: Your reports, the person's own problem reports in this session with where each stands. While one
    // is not fixed they can add a line or a screenshot to it (the same screenshot path and caps). Only they and the host
    // see a report.
    const myRepPop = E("div", "vf-pop vf-reportpop vf-myreps"); myRepPop.setAttribute("role", "dialog"); myRepPop.setAttribute("aria-label", "Your reports"); myRepPop.hidden = true;
    const myRepList = E("ul", "vf-plist vf-myrep-list"); myRepList.setAttribute("role", "list");
    const myRepDone = btn("vf-btn vf-btn-ghost", "Done");
    const myRepRow = E("div", "vf-crow"); myRepRow.append(E("span", "vf-spacer"), myRepDone);
    myRepPop.append(E("h2", "vf-pop-title", "Your reports"), E("p", "vf-pop-note", "Only you and the host see these."), myRepList, myRepRow);
    const REP_WORD = { open: "Sent", seen: "Seen by the host", resolved: "Fixed" };

    // Wide panels: beside the rail when there is room, over the center pane when not, a bottom sheet on phones.
    function panel(title, label) {
      const pop = E("div", "vf-pop vf-panel"); pop.setAttribute("role", "dialog"); pop.setAttribute("aria-label", label); pop.hidden = true;
      const head = E("div", "vf-pp-head");
      const close = ibtn("vf-tbtn vf-icon-btn", "x", `Close ${label.toLowerCase()}`);
      const tools = E("div", "vf-pp-tools");
      head.append(E("h2", "vf-pop-title", title), tools, close);
      const note = E("p", "vf-pop-note");
      const list = E("ul", "vf-plist"); list.setAttribute("role", "list");
      const empty = E("p", "vf-empty vf-empty-sm");
      const sc = E("div", "vf-pscroll"); sc.append(list, empty);
      pop.append(head, note, sc);
      close.onclick = () => { const a = pop._anchor; closePop(); a?.focus(); };
      return { pop, tools, note, list, empty };
    }
    const PP = panel("Proposed questions", "Proposed questions");
    const propSeg = E("div", "vf-seg vf-seg-sm"); propSeg.setAttribute("role", "group"); propSeg.setAttribute("aria-label", "Show");
    const propNewBtn = btn("vf-seg-btn"), propNotBtn = btn("vf-seg-btn"), propParkBtn = btn("vf-seg-btn");
    propSeg.append(propNewBtn, propNotBtn, propParkBtn);
    PP.tools.append(propSeg);
    const propMore = showMore("proposals", 20);
    PP.list.after(propMore.foot);
    propNewBtn.onclick = () => { ui.propFilter = "new"; render(); };
    propNotBtn.onclick = () => { ui.propFilter = "notplaced"; render(); };
    propParkBtn.onclick = () => { ui.propFilter = "parked"; render(); };

    const RQ = panel("Requests for Claude", "Requests for Claude");
    const runAllBtn = lbtn("vf-btn vf-btn-primary vf-btn-sm", "play", "Run all shown");
    RQ.tools.append(runAllBtn);
    RQ.note.textContent = "Nothing runs until you press Run. Run all shown runs exactly the requests you can see now.";

    // Confirm before sending a round that still has open questions.
    const confirmPop = E("div", "vf-pop vf-confirm"); confirmPop.setAttribute("role", "dialog"); confirmPop.setAttribute("aria-label", "Send round"); confirmPop.hidden = true;
    const confirmTxt = E("p", "vf-confirm-txt");
    const confirmRow = E("div", "vf-crow");
    const confirmNo = btn("vf-btn vf-btn-ghost", "Keep answering");
    const confirmYes = btn("vf-btn vf-btn-primary", "Send anyway");
    confirmRow.append(confirmNo, confirmYes);
    confirmPop.append(confirmTxt, confirmRow);

    // A vote tie on Lock top answer: the moderator picks which answer to lock.
    const tiePop = E("div", "vf-pop vf-tiepop"); tiePop.setAttribute("role", "dialog"); tiePop.setAttribute("aria-label", "Pick the answer to lock"); tiePop.hidden = true;
    const tieList = E("ul", "vf-tielist"); tieList.setAttribute("role", "list");
    tiePop.append(E("h2", "vf-pop-title", "Tied on votes"), E("p", "vf-pop-note", "Pick the one to lock. Claude's recommendation is listed first."), tieList);

    // ---------- center ----------
    const center = E("section", "vf-center");
    // Session-wide notice: ended, removed, or (owner) a new guest link to share.
    const banner = E("div", "vf-banner"); banner.setAttribute("role", "status"); banner.hidden = true;
    const bannerTxt = E("span", "vf-banner-txt"), bannerAct = btn("vf-btn vf-btn-ghost vf-btn-sm");
    banner.append(icon("alert"), bannerTxt, bannerAct);
    const bar = E("div", "vf-bar");
    const seg = E("div", "vf-seg"); seg.setAttribute("role", "group"); seg.setAttribute("aria-label", "View");
    const segBtns = {};
    for (const [k, label] of [["focus", "Focus"], ["compare", "Compare"], ["tree", "Tree"], ["host", "Host"]]) {
      const b = btn("vf-seg-btn", label); b.onclick = () => setMode(k); seg.append(b); segBtns[k] = b;
    }
    // One toolbar for Focus, Compare and Tree (Q72): sort, filter chips, round, expand or collapse every round.
    const toolbar = E("div", "vf-toolbar"); toolbar.setAttribute("role", "toolbar"); toolbar.setAttribute("aria-label", "Sort and filter questions");
    const selWrap = (label, opts) => {
      const w = E("label", "vf-selwrap"), s = E("select", "vf-select");
      w.append(E("span", "vf-sel-l", label), s);
      for (const [v, t] of opts) { const o = E("option", null, t); o.value = v; s.append(o); }
      return { w, s };
    };
    const sortSel = selWrap("Sort", [["new", "Newest"], ["votes", "Most votes"], ["unanswered", "Unanswered first"]]);
    sortSel.s.onchange = () => setTb({ sort: sortSel.s.value });
    const chips = E("div", "vf-chips"); chips.setAttribute("role", "group"); chips.setAttribute("aria-label", "Show questions");
    const chipBtns = {};
    for (const [k, label] of [["all", "All"], ["open", "Open"], ["locked", "Locked"], ["review", "Needs review"], ["mine", "Mine"], ["research", "Has research"]]) {
      const b = btn("vf-fchip", label); b.onclick = () => setTb({ filter: k }); chips.append(b); chipBtns[k] = b;
    }
    const roundSel = selWrap("Round", [["all", "All rounds"]]);
    roundSel.s.onchange = () => { setTb({ round: roundSel.s.value }); board.scrollLeft = 0; };
    const expandBtn = btn("vf-btn vf-btn-ghost vf-btn-sm vf-expand");
    toolbar.append(sortSel.w, chips, roundSel.w, expandBtn);
    /** Does a question pass the toolbar's filter and round? */
    /** A guest's simple view: no view switch, sort or filters, so every question shows in round order. */
    const simpleView = () => !Core.canModerate() && pref("toolbar", "simple") !== "full";
    function passes(q) {
      if (simpleView()) return true;
      const t = tb();
      if (t.round !== "all" && String(roundOf(q)) !== t.round) return false;
      const lk = Core.lockOf(q.id);
      switch (t.filter) {
        case "open": return !lk;
        case "locked": return !!lk;
        case "review": return !!q.needsReview;
        case "mine": return hasAnswered(q.id) || Core.state.ideas.some(i => isMe(i.cid) && i.qid === q.id);
        case "research": return !!(Core.state.research?.[q.id] || []).length;
        default: return true;
      }
    }
    const totalVotes = qid => Core.answersFor(qid).reduce((n, a) => n + votesOf(a), 0);
    /** Questions in round order, filtered, and sorted inside each round as the toolbar says. */
    function shownQuestions() {
      const t = tb(), qs = Core.state.questions.filter(passes), pos = new Map(Core.state.questions.map((q, i) => [q.id, i]));
      const key = q => simpleView() ? 0 : t.sort === "votes" ? -totalVotes(q.id) : t.sort === "unanswered" ? +(myState(q.id) !== "open") : 0;
      return qs.sort((a, b) => roundOf(a) - roundOf(b) || key(a) - key(b) || pos.get(a.id) - pos.get(b.id));
    }
    const barInfo = E("span", "vf-meta");
    const barNav = E("div", "vf-barnav");
    const prevQ = ibtn("vf-tbtn vf-icon-btn", "chevL", "Previous question");
    const nextQ = ibtn("vf-tbtn vf-icon-btn", "chevR", "Next question");
    barNav.append(prevQ, nextQ);
    const pick = E("div", "vf-pick"); pick.setAttribute("role", "group"); pick.setAttribute("aria-label", "Round to compare");
    // ux-review-2 #4: a guest starts with one question at a time; views, sort and filters wait behind View options.
    const viewOpts = btn("vf-btn vf-btn-ghost vf-btn-sm vf-viewopts"); viewOpts.setAttribute("aria-expanded", "false");
    viewOpts.onclick = () => {
      const full = pref("toolbar", "simple") !== "full";
      setPrefs({ toolbar: full ? "full" : "simple" });
      if (!full) setMode("focus");
      render();
    };
    bar.append(seg, viewOpts, barInfo, pick, barNav);

    // Focus view
    const focusV = E("div", "vf-focus");
    const scroll = E("div", "vf-scroll");
    const qMeta = E("div", "vf-qmeta");
    const qPos = E("span"), qFrom = E("span", "vf-qfrom"), qSug = E("span", "vf-chip vf-chip-brass"), qDeps = E("span", "vf-chip vf-chip-quiet");
    const qHost = E("span", "vf-chip vf-chip-quiet");
    // Q97: the question's purpose; the owner overrides the one Claude inferred.
    const qPurpose = E("span", "vf-chip vf-chip-quiet vf-purpose");
    const purposeSel = selWrap("Purpose", Object.entries(PURPOSE).map(([k, [l]]) => [k, l]));
    purposeSel.w.classList.add("vf-purposesel");
    purposeSel.s.onchange = () => Core.setPurpose(ui.cur, purposeSel.s.value).then(() => flash(`${qById(ui.cur)?.id} is now a ${PURPOSE[purposeSel.s.value][0]} question.`)).catch(e => { fail(e); render(); });
    // Triage row 42: who a question is asked of (`for`). Claude sets it from "@name"; the owner changes it here, as the purpose.
    const qFor = E("span", "vf-chip vf-chip-brass vf-forchip");
    const forBtn = btn("vf-btn vf-btn-ghost vf-btn-sm vf-forbtn"); forBtn.setAttribute("aria-expanded", "false");
    const forBox = E("fieldset", "vf-forbox"); forBox.hidden = true; forBox.id = "vf-forbox"; forBtn.setAttribute("aria-controls", forBox.id);
    const forLegend = E("legend", null, "Who must answer (no one ticked asks everyone)"), forList = E("div", "vf-forlist");
    forBox.append(forLegend, forList);
    forBtn.onclick = () => { ui.forOpen = ui.forOpen === ui.cur ? "" : ui.cur; render(); };
    qMeta.append(qPos, qPurpose, purposeSel.w, qFor, forBtn, qFrom, qDeps, qSug, qHost);
    const qText = E("h1", "vf-qtext"); qText.tabIndex = -1;
    const reviewRow = E("div", "vf-reviewrow");
    const reviewTag = E("span", "vf-review"); const reviewTxt = E("span");
    reviewTag.append(icon("alert"), reviewTxt);
    const reviewClear = btn("vf-btn vf-btn-ghost vf-btn-sm", "Mark reviewed");
    reviewRow.append(reviewTag, reviewClear);
    const onIt = E("div", "vf-onit");
    const onItAv = E("span", "vf-avrow"), onItTxt = E("span"), onItDots = dots();
    onIt.append(onItAv, onItTxt, onItDots);
    // Triage 3: a guest's first view says why they are here, what the host asks, and where to start.
    const orient = E("section", "vf-orient"); orient.setAttribute("aria-labelledby", "vf-orient-h");
    const orH = E("h2", "vf-orient-h"); orH.id = "vf-orient-h";
    const orGoal = E("p", "vf-orient-goal"), orAsk = E("p", "vf-orient-ask");
    const orRow = E("div", "vf-orient-row");
    const orStart = btn("vf-btn vf-btn-primary vf-orient-start"), orTour = btn("vf-btn vf-btn-ghost vf-orient-tour", "Show me around");
    // Phase 4c: "Why you're here", the intro the owner confirmed. Open on a wide screen's first view; on a phone, and on
    // later visits, it folds behind its toggle so the question, "Something else…" and the answer box stay on screen.
    const orWhyBtn = btn("vf-btn vf-btn-ghost vf-orient-whybtn", "Why you're here"); orWhyBtn.setAttribute("aria-expanded", "false");
    const orWhy = E("div", "vf-orient-why"); orWhy.id = "vf-orient-why"; orWhyBtn.setAttribute("aria-controls", orWhy.id);
    const orIntro = E("p", "vf-orient-intro"), orHow = E("p", "vf-orient-how");
    orWhy.append(orIntro, orHow);
    orRow.append(orStart, orWhyBtn, orTour);
    const orHide = ibtn("vf-tbtn vf-icon-btn vf-orient-x", "x", "Hide this introduction");
    const orCatch = catchUpEl(() => { ui.orientHidden = true; });
    orient.append(orHide, orH, orGoal, orAsk, orCatch, orRow, orWhy);
    orWhyBtn.onclick = () => { ui.introOpen = !introOpen(); render(); };
    orHide.onclick = () => { ui.orientHidden = true; render(); qText.focus({ preventScroll: true }); };
    const introOpen = () => !!ui.introOpen;
    const INTRO_SEEN = () => "vf-intro-seen:" + (Core.me.cid || "anon");

    // Research and ask requests
    const tools = E("div", "vf-qtools");
    // "Ask Claude ▾" (Ask / Research), the same words everywhere.
    const askBtn = btn("vf-btn vf-btn-ghost vf-btn-sm vf-askbtn"); askBtn.append(icon("sparkle"), E("span", null, "Ask Claude"), icon("chevD", "vf-i vf-chev"));
    askBtn.setAttribute("aria-haspopup", "menu"); askBtn.setAttribute("aria-expanded", "false");
    const askMenu = E("div", "vf-pop vf-menu vf-askmenu"); askMenu.setAttribute("role", "menu"); askMenu.setAttribute("aria-label", "Ask Claude"); askMenu.hidden = true;
    for (const [k, label, desc] of [["ask", "Ask", "A question Claude answers here"], ["research", "Research", "Look up, compare or verify"]]) {
      const b = btn("vf-menu-item vf-menu-plain vf-menu-2"); b.setAttribute("role", "menuitem");
      b.append(E("span", "vf-sw-label", label), E("span", "vf-sw-desc", desc));
      b.onclick = () => { closePop(); ui.askKind = k; ui.askOpen = true; renderAsk(); askTa.focus(); };
      askMenu.append(b);
    }
    const reqChip = E("span", "vf-meta vf-reqchip");
    tools.append(askBtn);
    const askForm = E("form", "vf-askform"); askForm.hidden = true;
    const askHead = E("div", "vf-askhead");
    const askSeg = E("div", "vf-seg vf-seg-sm"); askSeg.setAttribute("role", "group"); askSeg.setAttribute("aria-label", "Kind of request");
    const askKinds = {};
    for (const [k, label] of [["ask", "Ask"], ["research", "Research"]]) {
      const b = btn("vf-seg-btn", label); b.onclick = () => { ui.askKind = k; renderAsk(); }; askSeg.append(b); askKinds[k] = b;
    }
    // Follow-up item 2: a guest asks in one box, and Claude works out the kind of request and says what it did; "Use the
    // web" sends it as research. The owner keeps the kind picker.
    const webChip = () => { const b = btn("vf-btn vf-btn-ghost vf-btn-sm vf-toggle vf-webchip", "Use the web"); b.setAttribute("aria-pressed", "false"); return b; };
    const askWeb = webChip();
    askWeb.onclick = () => { ui.askWeb = !ui.askWeb; renderAsk(); };
    const askLabel = E("label", "vf-asklabel", "What should Claude find out?");
    askHead.append(askLabel, askSeg, askWeb);
    const askTa = E("textarea", "vf-ta"); askTa.rows = 2; askTa.id = "vf-ask-ta"; askLabel.htmlFor = askTa.id; askTa.maxLength = 2000;
    const askRow = E("div", "vf-crow");
    const askCancel = btn("vf-btn vf-btn-ghost", "Cancel");
    const askSend = E("button", "vf-btn vf-btn-primary", "Send request"); askSend.type = "submit";
    askRow.append(askCancel, askSend);
    askForm.append(askHead, askTa,
      E("p", "vf-pop-note vf-asknote", "The host runs it; the result lands on this question. Your request text shows on the result for everyone."), askRow);
    // Q77: the question's Claude thread, requests and results in time order.
    const thList = E("ul", "vf-thlist"); thList.setAttribute("role", "list"); thList.setAttribute("aria-label", "Claude thread");
    const thEmpty = E("p", "vf-empty vf-empty-sm", "Nothing asked yet. Ask Claude about this question, or have it research something.");
    const myReqs = thList, resList = thList; // kept names: both now live in the thread

    // Locked block
    const lockBox = E("section", "vf-lock"); lockBox.setAttribute("aria-label", "Locked answer");
    const lockTop = E("div", "vf-lock-top");
    const lockBadge = E("span", "vf-lock-badge"); lockBadge.append(icon("lock"), E("span", null, "Locked"));
    const lockBy = E("span", "vf-meta");
    const unlockBtn = btn("vf-btn vf-btn-ghost vf-btn-sm", "Unlock");
    const editBtn = btn("vf-btn vf-btn-ghost vf-btn-sm", "Edit");
    lockTop.append(lockBadge, lockBy, E("span", "vf-spacer"), editBtn, unlockBtn);
    const lockText = clampBox("vf-lock-text");
    const lockFrom = E("div", "vf-lock-from");
    const editForm = E("form", "vf-edit"); editForm.hidden = true;
    const editTa = E("textarea", "vf-ta"); editTa.rows = 3; editTa.setAttribute("aria-label", "Locked answer text"); editTa.maxLength = 2000;
    const editRow = E("div", "vf-crow");
    const editCancel = btn("vf-btn vf-btn-ghost", "Cancel");
    const editSave = E("button", "vf-btn vf-btn-primary", "Save locked answer"); editSave.type = "submit";
    editRow.append(E("span", "vf-hint", "The question stays locked"), editCancel, editSave);
    editForm.append(editTa, editRow);
    const sugHead = E("div", "vf-subhead");
    const sugTitle = E("h2", "vf-h2");
    const sugBtn = btn("vf-btn vf-btn-ghost vf-btn-sm", "Suggest a change");
    sugHead.append(sugTitle, sugBtn);
    const sugForm = E("form", "vf-sugform"); sugForm.hidden = true;
    const sugTa = E("textarea", "vf-ta"); sugTa.rows = 3; sugTa.placeholder = "Your suggested answer"; sugTa.setAttribute("aria-label", "Suggested answer"); sugTa.maxLength = 2000;
    const sugNote = E("input", "vf-input"); sugNote.maxLength = 200; sugNote.placeholder = "Why? (optional)"; sugNote.setAttribute("aria-label", "Note for the host");
    const sugRow = E("div", "vf-crow");
    const sugCancel = btn("vf-btn vf-btn-ghost", "Cancel");
    const sugSend = E("button", "vf-btn vf-btn-primary", "Send suggestion"); sugSend.type = "submit";
    sugRow.append(E("span", "vf-hint", "The host or a leader decides"), sugCancel, sugSend);
    sugForm.append(sugTa, sugNote, sugRow);
    const sList = E("ul", "vf-slist"); sList.setAttribute("role", "list");
    const sugMore = showMore("sugs", 10);
    lockBox.append(lockTop, lockText, lockFrom, editForm, sugHead, sugForm, sList, sugMore.foot);

    const ansHead = E("div", "vf-anshead");
    const ansTitle = E("h2", "vf-h2", "Answers"), ansCount = E("span", "vf-meta");
    const agreeTxt = E("span", "vf-agree");
    const lockBtn = btn("vf-btn vf-btn-brass vf-btn-sm", "Lock top answer");
    ansHead.append(ansTitle, ansCount, E("span", "vf-spacer"), agreeTxt, lockBtn);
    // C26: Claude's take waits behind this bar until the person answered or voted.
    const claudeBar = btn("vf-claudebar"); claudeBar.append(claudeAv(20), E("span", "vf-claudebar-t"), E("span", "vf-claudebar-n"));
    claudeBar.onclick = () => { ui.revealed.add(ui.cur); render(); };
    const aList = E("ul", "vf-alist"); aList.setAttribute("role", "list");
    const aEmpty = E("p", "vf-empty", "No answers yet. Yours can be the first.");
    // Suggestions an Unlock closed: kept and shown, never deleted.
    const closedBox = E("section", "vf-closed"); closedBox.setAttribute("aria-label", "Suggestions closed by unlock");
    const closedList = E("ul", "vf-slist"); closedList.setAttribute("role", "list");
    closedBox.append(E("h2", "vf-h2", "Suggestions closed by unlock"), closedList);
    // Q76: a choice question's options, or a screenshot with a marked area for "Did you mean this?"
    const fmtBox = E("section", "vf-fmt"); fmtBox.setAttribute("aria-label", "Options");
    const fmtHint = E("p", "vf-fmt-hint");
    const optGrid = E("ul", "vf-opts"); optGrid.setAttribute("role", "list");
    const confirmFig = E("figure", "vf-confirm-fig");
    const confirmImg = E("img", "vf-confirm-img"); confirmImg.alt = "Screenshot";
    const confirmMark = E("span", "vf-confirm-mark"); confirmMark.setAttribute("aria-hidden", "true");
    // The canvas holds the whole picture; the box shows it at full width and crops a tall one around the mark.
    const confirmCanvas = E("span", "vf-confirm-canvas"); confirmCanvas.append(confirmImg, confirmMark);
    const confirmImgBox = E("span", "vf-confirm-box"); confirmImgBox.append(confirmCanvas, zoomTag());
    const confirmView = btn("vf-imgbtn"); confirmView.append(confirmImgBox);
    confirmFig.append(confirmView);
    confirmImg.onload = () => { if (confirmImg.naturalWidth && confirmImg.naturalHeight) confirmView.style.setProperty("--ar", String(confirmImg.naturalWidth / confirmImg.naturalHeight)); };
    const cfRow = E("div", "vf-confirm-row"); cfRow.setAttribute("role", "group"); cfRow.setAttribute("aria-label", "Your answer");
    const yesBtn = btn("vf-pickbtn"), noBtn = btn("vf-pickbtn"), elseBtn = btn("vf-pickbtn");
    for (const [b, label] of [[yesBtn, "Yes"], [noBtn, "No"], [elseBtn, CONFIRM_OTHER]]) b.append(E("span", "vf-pick-l", label), E("span", "vf-pick-n"));
    const cfUndo = btn("vf-btn vf-btn-ghost vf-btn-sm vf-optundo", "Undo");
    cfRow.append(yesBtn, noBtn, elseBtn, cfUndo);
    const fmtNote = E("p", "vf-fmt-note");
    // Phase 4b formats. multi: checkboxes, any subset of at least one. scale: one value from min to max. rank: every
    // option in order, by dragging its handle (mouse or touch), its Up and Down buttons, or the arrow keys on its handle.
    const multiList = E("ul", "vf-multilist"); multiList.setAttribute("role", "list");
    const scaleBox = E("div", "vf-scale");
    const scaleRow = E("div", "vf-scale-row"); scaleRow.setAttribute("role", "radiogroup");
    const scaleEnds = E("div", "vf-scale-ends");
    const scaleMin = E("span", "vf-scale-end"), scaleMid = E("span", "vf-scale-end vf-scale-mid"), scaleMax = E("span", "vf-scale-end vf-scale-max");
    scaleEnds.append(scaleMin, scaleMid, scaleMax);
    scaleBox.append(scaleRow, scaleEnds);
    const rankList = E("ol", "vf-rank"); rankList.setAttribute("aria-label", "Your ranking, best first");
    // "Something else…": the person's own option, written here; it becomes a card others can back.
    const otherBox = E("div", "vf-otherbox");
    const otherLbl = E("label", "vf-otherlbl", "Your own option"); otherLbl.htmlFor = "vf-other";
    const otherTa = E("textarea", "vf-ta vf-other-ta"); otherTa.id = "vf-other"; otherTa.rows = 2; otherTa.maxLength = 2000;
    otherTa.placeholder = "Say what you would pick instead";
    const otherRow = E("div", "vf-crow");
    const otherCancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel");
    const otherSave = btn("vf-btn vf-btn-primary vf-btn-sm vf-other-save", "Add my option");
    otherRow.append(E("span", "vf-spacer"), otherCancel, otherSave);
    otherBox.append(otherLbl, otherTa, otherRow);
    const fmtActs = E("div", "vf-fmtacts");
    const fmtSave = btn("vf-btn vf-btn-primary vf-btn-sm vf-fmt-save"), fmtClear = btn("vf-btn vf-btn-ghost vf-btn-sm vf-fmt-clear");
    fmtActs.append(fmtClear, E("span", "vf-spacer"), fmtSave);
    // Results where the options are: counts (multi, scale with mean and median), Borda points (rank).
    const fmtRes = E("section", "vf-fmtres"); fmtRes.setAttribute("aria-label", "Results");
    const fmtResHead = E("h3", "vf-fmtres-h"), fmtResSum = E("p", "vf-fmtres-sum"), fmtResList = E("ol", "vf-fmtres-list");
    fmtRes.append(fmtResHead, fmtResSum, fmtResList);
    // Q98: a prototype question shows a preview tile and opens its own page, where the variants run and take notes.
    const protoBox = E("section", "vf-proto"); protoBox.setAttribute("aria-label", "Prototype");
    const protoTile = E("div", "vf-proto-tile"), protoInfo = E("div", "vf-proto-info");
    const protoMeta = E("p", "vf-proto-meta"), protoOpen = E("a", "vf-btn vf-btn-primary vf-btn-sm vf-proto-open", "Open prototype");
    protoOpen.target = "_blank"; protoOpen.rel = "noopener noreferrer";
    protoInfo.append(protoMeta, protoOpen);
    protoBox.append(protoTile, protoInfo);
    fmtBox.append(fmtHint, protoBox, optGrid, multiList, scaleBox, rankList, confirmFig, cfRow, otherBox, fmtActs, fmtNote, fmtRes);
    // Layout A: Answers, then "Claude on this question", one column at every width. The Claude section starts folded to its
    // head and opens by itself when this person has a new result on the question; opening pushes the page, hiding nothing.
    const ansPane = E("section", "vf-anspane"); ansPane.setAttribute("aria-label", "Answers"); ansPane.id = "vf-anspane";
    const ansMore = showMore("ans", 12, { all: true });
    ansPane.append(lockBox, ansHead, claudeBar, aList, ansMore.foot, aEmpty, closedBox);
    const clSec = E("section", "vf-clsec"); clSec.setAttribute("aria-label", "Claude on this question");
    const clHead = E("div", "vf-clhead"), clH = E("h2", "vf-h2 vf-clh");
    const clToggle = btn("vf-cltoggle"); clToggle.setAttribute("aria-controls", "vf-clbody");
    const clNew = E("span", "vf-chip vf-chip-new vf-clnew"), clCounts = E("span", "vf-meta vf-clcounts");
    clToggle.append(claudeAv(20), E("span", "vf-cltitle", "Claude on this question"), clNew, clCounts, icon("chevD", "vf-i vf-chev"));
    clH.append(clToggle);
    clHead.append(clH, reqChip, tools);
    const clBody = E("div", "vf-clbody"); clBody.id = "vf-clbody";
    clBody.append(thList, thEmpty, askForm);
    clSec.append(clHead, clBody);
    const clIsOpen = () => !!ui.cur && ui.clOpen.get(ui.cur) === true;
    function paintCl() {
      const open = clIsOpen();
      clSec.dataset.open = String(open); clBody.hidden = !open;
      clToggle.setAttribute("aria-expanded", String(open));
    }
    /** Opening keeps the section in view: its head moves to the top of the scroll area, the answers stay above it. */
    function keepClInView() { requestAnimationFrame(() => clSec.scrollIntoView({ block: "start", behavior: smooth() })); }
    clToggle.onclick = () => { const open = !clIsOpen(); ui.clOpen.set(ui.cur, open); if (!open) ui.askOpen = false; render(); if (open) keepClInView(); };
    // Item 10: the question's Discussion, below the Claude section and folded by default. Its head counts the comments and
    // the ones new to me (others' since I last opened it); opening it marks them read on the server, on every device.
    const discSec = E("section", "vf-disc"); discSec.setAttribute("aria-label", "Discussion");
    const discToggle = btn("vf-disc-head"); discToggle.setAttribute("aria-controls", "vf-discbody");
    const discCount = E("span", "vf-meta vf-disc-count"), discNew = E("span", "vf-chip vf-chip-new vf-disc-new");
    discToggle.append(icon("chat"), E("span", "vf-disc-title", "Discussion"), discCount, discNew, icon("chevD", "vf-i vf-chev"));
    const discH = E("h2", "vf-h2 vf-disc-h"); discH.append(discToggle);
    const discBody = E("div", "vf-disc-body"); discBody.id = "vf-discbody";
    const discList = E("ul", "vf-disc-list"); discList.setAttribute("role", "list");
    const discEmpty = E("p", "vf-empty", "No comments yet.");
    const discForm = E("form", "vf-disc-form");
    const discTa = E("textarea", "vf-ta vf-disc-ta"); discTa.rows = 2; discTa.maxLength = 2000; discTa.id = "vf-disc-ta";
    discTa.placeholder = "Add a comment"; discTa.setAttribute("aria-label", "Add a comment");
    const discHint = E("span", "vf-hint vf-disc-hint", "Type @Claude to send it to Claude."); discHint.id = "vf-disc-hint";
    discTa.setAttribute("aria-describedby", discHint.id);
    const discPost = E("button", "vf-btn vf-btn-primary vf-btn-sm vf-disc-post", "Post"); discPost.type = "submit";
    const discRow = E("div", "vf-crow"); discRow.append(discHint, E("span", "vf-spacer"), discPost);
    discForm.append(discTa, discRow);
    discBody.append(discList, discEmpty, discForm);
    discSec.append(discH, discBody);
    ui.discOpen = new Map(); ui.discFrom = new Map(); ui.discEdit = ""; ui.discDrafts = new Map(); // qid -> the unsent comment typed on it
    const discIsOpen = () => !!ui.cur && ui.discOpen.get(ui.cur) === true;
    /** Opening: the new dots stay on what was new when I opened it, while the server marks it all read. */
    function setDisc(qid, open) {
      if (open && !ui.discOpen.get(qid)) ui.discFrom.set(qid, Core.state.discussionSeen?.[qid] || 0);
      ui.discOpen.set(qid, open);
    }
    discToggle.onclick = () => { const open = !discIsOpen(); setDisc(ui.cur, open); render(); if (open) requestAnimationFrame(() => discSec.scrollIntoView({ block: "nearest", behavior: smooth() })); };
    discTa.addEventListener("input", () => { ui.discDrafts.set(ui.cur, discTa.value); grow(discTa); });
    discTa.addEventListener("keydown", e => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); discForm.requestSubmit(); } });
    discForm.onsubmit = e => {
      e.preventDefault();
      const qid = ui.cur, text = discTa.value.trim();
      if (!qid || !text || discPost.disabled) return;
      discPost.disabled = true;
      Core.comment(qid, text).then(j => {
        ui.discDrafts.delete(qid);
        if (ui.cur === qid) { discTa.value = ""; grow(discTa); } // a question switched to meanwhile keeps its own draft
        if (j.request) flash("Posted, and sent to Claude."); else if (j.requestRefused) flash(j.message); })
        .catch(fail).finally(() => { discPost.disabled = false; });
    };
    // Q84: References under the question: screenshots with a marked area, quoted excerpts with their source, titled links.
    const refBox = E("section", "vf-refs"); refBox.setAttribute("aria-label", "References");
    const refHead = E("div", "vf-refs-head");
    const refAdd = lbtn("vf-lbtn vf-refadd", "plus", "Add reference"); refAdd.setAttribute("aria-haspopup", "dialog"); refAdd.setAttribute("aria-expanded", "false");
    refHead.append(E("h2", "vf-h2", "References"), refAdd);
    const refList = E("ul", "vf-reflist"); refList.setAttribute("role", "list");
    refBox.append(refHead, refList);
    // Q86 / content first: on phones the question's own row carries previous and next.
    const qNav = E("span", "vf-qnav");
    const qPrev = ibtn("vf-tbtn vf-icon-btn vf-qnav-btn", "chevL", "Previous question"), qNext = ibtn("vf-tbtn vf-icon-btn vf-qnav-btn", "chevR", "Next question");
    qNav.append(qPrev, qNext);
    // On phones the on-it avatars sit in this row, before the arrows, so presence costs the question no height.
    const qOnIt = E("span", "vf-qonit"), qOnItAv = E("span", "vf-avrow");
    qOnIt.setAttribute("role", "img"); qOnIt.append(qOnItAv);
    qMeta.append(qOnIt, qNav);
    const composer = E("form", "vf-composer");
    const ta = E("textarea", "vf-ta"); ta.rows = 3; ta.setAttribute("aria-label", "Your answer"); ta.maxLength = 2000; ta.id = "vf-answer";
    const cRow = E("div", "vf-crow");
    const cHint = E("span", "vf-hint", "Ctrl + Enter to send");
    const cCount = E("span", "vf-count-txt"); cCount.setAttribute("aria-live", "polite");
    cRow.append(cCount);
    const clearBtn = btn("vf-btn vf-btn-ghost", "Clear");
    // On phones the send button is a round icon inside the field's end; the label stays as its accessible name.
    const sendBtn = E("button", "vf-btn vf-btn-primary vf-sendbtn"); sendBtn.type = "submit";
    const sendLbl = E("span", "vf-send-l", "Answer");
    sendBtn.append(icon("send", "vf-i vf-send-i"), sendLbl);
    // Cite one of this question's Claude results; attach a file (uploads on).
    const citeBtn = btn("vf-btn vf-btn-ghost vf-btn-sm vf-citebtn"); citeBtn.append(icon("cite"), E("span", null, "Cite"));
    citeBtn.setAttribute("aria-haspopup", "dialog"); citeBtn.setAttribute("aria-expanded", "false");
    const attachBtn = ibtn("vf-btn vf-btn-ghost vf-btn-sm vf-attach", "clip", "Attach a file");
    const citeChips = E("ul", "vf-citechips"); citeChips.setAttribute("aria-label", "Cited results");
    const upStrip = E("ul", "vf-upstrip"); upStrip.setAttribute("aria-label", "Your files on this question");
    cRow.append(attachBtn, citeBtn, cHint, clearBtn, sendBtn);
    // The phone sheet's head (triage 18): Cancel, what is being answered, Save. Hidden outside the sheet.
    const sheetHead = E("div", "vf-sheethead");
    const sheetCancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel"), sheetTitle = E("span", "vf-sheettitle");
    const sheetSave = E("button", "vf-btn vf-btn-primary vf-btn-sm vf-sheetsave", "Save"); sheetSave.type = "submit";
    sheetHead.append(sheetCancel, sheetTitle, sheetSave);
    composer.append(sheetHead, upStrip, citeChips, ta, cRow);
    function closeSheet() {
      if (!composer.classList.contains("vf-composer-sheet")) return;
      composer.classList.remove("vf-composer-sheet"); delete root.dataset.sheet;
      ui.sheetFrom = null;
      grow(ta);
    }
    const citePop = E("div", "vf-pop vf-citepop"); citePop.setAttribute("role", "dialog"); citePop.setAttribute("aria-label", "Cite a result"); citePop.hidden = true;
    const citeList = E("ul", "vf-citelist"); citeList.setAttribute("role", "list");
    citePop.append(E("h2", "vf-pop-title", "Cite a result"), E("p", "vf-pop-note", "Your answer links to it, and the result shows who cited it."), citeList);
    // Triage row 42: once someone else answered a question not asked of me by name, a line says so (optional now), and
    // Pass, on every purpose, says I have no view to give. Pass is a quiet button under the answer box, never the default.
    const passBox = E("div", "vf-passbox");
    const passNote = E("p", "vf-passnote"), passWho = E("p", "vf-passwho");
    const passBtn = btn("vf-btn vf-btn-ghost vf-btn-sm vf-passbtn", "Pass"); passBtn.setAttribute("aria-expanded", "false");
    const passUndo = btn("vf-btn vf-btn-ghost vf-btn-sm vf-passundo", "Undo pass");
    const passForm = E("form", "vf-passform"); passForm.hidden = true; passForm.id = "vf-passform"; passBtn.setAttribute("aria-controls", passForm.id);
    const passLbl = E("label", "vf-passlbl"), passIn = E("input", "vf-input vf-pass-input");
    passIn.id = "vf-pass-reason"; passIn.maxLength = 200; passLbl.htmlFor = passIn.id;
    const passSave = E("button", "vf-btn vf-btn-ghost vf-btn-sm", "Pass"); passSave.type = "submit";
    const passCancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel");
    const passErr = E("p", "vf-passerr"); passErr.setAttribute("role", "alert");
    const passRow = E("div", "vf-passrow"); passRow.append(passIn, passSave, passCancel);
    passForm.append(passLbl, passRow, passErr);
    const passLine = E("div", "vf-passline"); passLine.append(passNote, passBtn, passUndo);
    passBox.append(passLine, passForm, passWho);
    passBtn.onclick = () => { ui.passOpen = ui.cur; passErr.textContent = ""; render(); passIn.focus(); };
    passCancel.onclick = () => { ui.passOpen = ""; render(); passBtn.focus(); };
    passForm.onsubmit = e => {
      e.preventDefault();
      const qid = ui.cur, reason = passIn.value.trim();
      if (!reason && askedOfMe(qid)) { passErr.textContent = "This question is asked of you: say why you pass."; passIn.focus(); return; }
      passSave.disabled = true;
      Core.pass(qid, reason).then(() => { ui.passOpen = ""; passIn.value = ""; flash("You passed. Undo it while the round is open."); })
        .catch(x => { passErr.textContent = `Not passed: ${Core.errorText(x)}`; }).finally(() => { passSave.disabled = false; render(); });
    };
    passUndo.onclick = () => Core.pass(ui.cur, "", false).then(() => flash("Pass taken back.")).catch(fail);
    // Follow-up item 1: "Go to the next question after I answer" (the autoAdvance pref, off by default). One pick, a
    // confirm or a scale value with the comment box empty moves on in 2 s unless Stay; never pick-many, rank or text.
    const ADV = { timer: 0, qid: "" };
    const advBar = E("p", "vf-advance"); advBar.setAttribute("role", "status"); advBar.hidden = true;
    const advStay = btn("vf-btn vf-btn-ghost vf-btn-sm vf-advance-stay", "Stay");
    advBar.append(E("span", null, "Next question in 2 s"), E("span", "vf-advance-sep", "·"), advStay);
    // Triage 13: the answer box sits right under the question and its options, never at the pane's foot.
    scroll.append(orient, qMeta, forBox, qText, refBox, reviewRow, onIt, fmtBox, advBar, composer, passBox, ansPane, clSec, discSec);
    focusV.append(scroll);

    // Compare view
    const cmp = E("div", "vf-cmp");
    const board = E("div", "vf-board"); board.setAttribute("aria-label", "All questions side by side");
    const fadeL = E("div", "vf-fade vf-fade-l"), fadeR = E("div", "vf-fade vf-fade-r");
    const arrL = ibtn("vf-edge vf-edge-l", "chevL", "Scroll to earlier questions");
    const arrR = btn("vf-edge vf-edge-r"); arrR.setAttribute("aria-label", "Scroll to more questions");
    const arrRTxt = E("span");
    arrR.append(arrRTxt, icon("chevR"));
    cmp.append(board, fadeL, fadeR, arrL, arrR);

    // Tree view
    const treeV = E("div", "vf-treev");
    const tree = E("div", "vf-tree"); tree.setAttribute("aria-label", "Decision tree");
    treeV.append(tree);

    // Host view (Q73): owner and leaders. People, one combined queue, round status, links, settings, goal and Later.
    const hostV = E("div", "vf-hostv");
    const hostGrid = E("div", "vf-hostgrid");
    const hsec = (title, cls) => { const s = E("section", "vf-hsec " + (cls || "")); const h = E("div", "vf-hsec-head"); const t = E("h2", "vf-hsec-title", title); const m = E("span", "vf-meta"); h.append(t, m); s.append(h); s._h = h; s._t = t; s._m = m; return s; };
    const hRound = hsec("Round", "vf-hs-round"), hQueue = hsec("Queue", "vf-hs-queue"), hPeople = hsec("People", "vf-hs-people");
    const hLinks = hsec("Links and settings", "vf-hs-links"), hLater = hsec("Later", "vf-hs-later");
    // round
    const hRoundName = E("p", "vf-hround-name"), hSteps = makeStepper(), hRoundNote = E("p", "vf-pop-note vf-hround-note");
    const hRoundRow = E("div", "vf-crow vf-hround-row");
    const hSend = btn("vf-btn vf-btn-primary vf-btn-sm", "Send round to Claude"), hCancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel sending");
    const hReset = btn("vf-btn vf-btn-ghost vf-btn-sm vf-reset-round", "Reset round");
    hRoundRow.append(hCancel, hReset, hSend);
    const hGoalLabel = E("h3", "vf-pop-sub", "Goal"), hGoal = E("p", "vf-hgoal"), hGoalEdit = btn("vf-btn vf-btn-ghost vf-btn-sm", "Edit goal");
    const hGoalRow = E("div", "vf-hgoal-row"); hGoalRow.append(hGoal, hGoalEdit);
    // Phase 4c: the owner edits "Why you're here" here; Claude drafts the first one in the terminal.
    const hIntroLabel = E("label", "vf-pop-sub vf-hintro-l", "Why you're here"); hIntroLabel.htmlFor = "vf-hintro";
    const hIntroIn = E("textarea", "vf-ta vf-hintro"); hIntroIn.id = "vf-hintro"; hIntroIn.maxLength = 600; hIntroIn.rows = 3;
    hIntroIn.placeholder = "Who is asking, why, about how long it takes, and what happens to the answers";
    const hIntroRow = E("div", "vf-crow"), hIntroCount = E("span", "vf-count-txt");
    const hIntroSave = btn("vf-btn vf-btn-primary vf-btn-sm", "Save introduction");
    hIntroRow.append(hIntroCount, E("span", "vf-spacer"), hIntroSave);
    const hIntroShown = E("p", "vf-hgoal vf-hintro-shown");
    hRound.append(hRoundName, hSteps, hRoundNote, hRoundRow, hGoalLabel, hGoalRow, hIntroLabel, hIntroShown, hIntroIn, hIntroRow);
    // queue
    const qFilters = E("div", "vf-chips vf-qfilters"); qFilters.setAttribute("role", "group"); qFilters.setAttribute("aria-label", "Show in the queue");
    const qfBtns = {};
    for (const [k, label] of [["all", "All"], ["request", "Requests"], ["proposal", "Proposals"], ["suggestion", "Suggestions"], ["merge", "Merges"], ["upload", "Uploads"], ["report", "Problems"], ["ready", "Ready"]]) {
      const b = btn("vf-fchip"); b.append(E("span", null, label), E("span", "vf-fchip-n")); b.onclick = () => { ui.hostFilter = k; render(); }; qFilters.append(b); qfBtns[k] = b;
    }
    const queueList = E("ul", "vf-queue"); queueList.setAttribute("role", "list");
    const queueEmpty = E("p", "vf-empty vf-empty-sm");
    const queueMore = showMore("queue", 20);
    hQueue.append(qFilters, queueList, queueMore.foot, queueEmpty);
    // people
    // Filter chips by presence (and Removed, the owner's), a name search once the list passes 12, then 25 at a time.
    const pFilters = E("div", "vf-chips vf-pfilters"); pFilters.setAttribute("role", "group"); pFilters.setAttribute("aria-label", "Show people");
    const pfBtns = {};
    for (const [k, label] of [["all", "All"], ["here", "Here"], ["away", "Away"], ["offline", "Offline"], ["removed", "Removed"]]) {
      const b = btn("vf-fchip"); b.append(E("span", null, label), E("span", "vf-fchip-n")); b.onclick = () => { ui.peopleFilter = k; render(); }; pFilters.append(b); pfBtns[k] = b;
    }
    const pFind = E("input", "vf-input vf-pfind"); pFind.type = "search"; pFind.placeholder = "Find a person"; pFind.setAttribute("aria-label", "Find a person by name");
    on(pFind, "input", () => { ui.peopleFind = pFind.value; render(); });
    const peopleList = E("ul", "vf-hpeople"); peopleList.setAttribute("role", "list");
    const peopleEmpty = E("p", "vf-empty vf-empty-sm"), peopleMore = showMore("people", 25);
    hPeople.append(pFilters, pFind, peopleList, peopleMore.foot, peopleEmpty);
    // links and settings
    const hShare = lbtn("vf-btn vf-btn-ghost vf-btn-sm", "link", "Share the guest link");
    const hNewGuest = btn("vf-btn vf-btn-ghost vf-btn-sm", "New guest link"), hNewOwner = btn("vf-btn vf-btn-ghost vf-btn-sm", "New owner link");
    const hSettings = lbtn("vf-btn vf-btn-ghost vf-btn-sm", "gear", "Session settings");
    const hLinkRow = E("div", "vf-hlinks"); hLinkRow.append(hShare, hNewGuest, hNewOwner, hSettings);
    const hEnd = btn("vf-btn vf-btn-ghost vf-btn-sm vf-btn-danger");
    const hEndNote = E("p", "vf-pop-note");
    hLinks.append(hLinkRow, hEndNote, hEnd);
    // later
    const laterNote = E("p", "vf-pop-note");
    const laterList = E("ul", "vf-plist vf-laterlist"); laterList.setAttribute("role", "list");
    const laterEmpty = E("p", "vf-empty vf-empty-sm", "Nothing parked for later. Proposals that are off the goal land here.");
    const laterMore = showMore("later", 10);
    hLater.append(laterNote, laterList, laterMore.foot, laterEmpty);
    const hColA = E("div", "vf-hcol"), hColB = E("div", "vf-hcol");
    hColA.append(hRound, hPeople, hLinks); hColB.append(hQueue, hLater);
    hostGrid.append(hColA, hColB);
    hostV.append(hostGrid);

    // A fresh session, no questions yet: the host starts with a goal and the link; guests see that the host is setting up.
    const emptyV = E("div", "vf-emptyv");
    const ev = E("div", "vf-ev");
    const evTitle = E("h1", "vf-ev-title"), evNote = E("p", "vf-ev-note");
    const evGoal = E("form", "vf-ev-goal");
    const evGoalIn = E("input", "vf-input"); evGoalIn.maxLength = 200; evGoalIn.id = "vf-ev-goal"; evGoalIn.placeholder = "Settle the co-op loot rules for the first playable";
    const evGoalLbl = E("label", "vf-asklabel", "What should this session settle?"); evGoalLbl.htmlFor = evGoalIn.id;
    const evGoalSave = E("button", "vf-btn vf-btn-primary", "Save goal"); evGoalSave.type = "submit";
    const evGoalRow = E("div", "vf-ev-row"); evGoalRow.append(evGoalIn, evGoalSave);
    evGoal.append(evGoalLbl, evGoalRow);
    const evGoalNow = E("p", "vf-ev-goalnow");
    const evShare = E("div", "vf-ev-share");
    const evShareIn = E("input", "vf-input vf-share-url"); evShareIn.readOnly = true; evShareIn.id = "vf-ev-share";
    const evShareLbl = E("label", "vf-asklabel", "Invite people with this link"); evShareLbl.htmlFor = evShareIn.id;
    const evCopy = btn("vf-btn vf-btn-primary", "Copy link");
    const evShareRow = E("div", "vf-ev-row"); evShareRow.append(evShareIn, evCopy);
    evShare.append(evShareLbl, evShareRow);
    const evHere = E("div", "vf-ev-here"), evHereAv = E("span", "vf-avrow"), evHereTxt = E("span");
    evHere.append(evHereAv, evHereTxt);
    const evNext = E("p", "vf-ev-next");
    const evPropose = lbtn("vf-btn vf-btn-ghost", "plus", "Propose a question"); evPropose.setAttribute("aria-haspopup", "dialog");
    ev.append(evTitle, evNote, evGoalNow, evGoal, evShare, evHere, evNext, evPropose);
    emptyV.append(ev);
    center.append(banner, bar, toolbar, focusV, cmp, treeV, hostV, emptyV);
    const skip = E("a", "vf-skip", "Skip to your answer"); skip.href = "#vf-answer";
    body.append(skip, rail, center);

    // Phone tabs
    const tabs = E("nav", "vf-tabs"); tabs.setAttribute("aria-label", "Sections");
    const tabBtns = {};
    // Q86: Questions, Answer, Compare, Tree, More; More opens a sheet with everything else. No hamburger.
    for (const [k, label] of [["questions", "Questions"], ["answer", "Answer"], ["compare", "Compare"], ["tree", "Tree"], ["more", "More"]]) {
      // Icon over a short label; the count badge hangs off the icon, so it never crowds the next tab.
      const b = btn("vf-tab"), ico = E("span", "vf-tab-ico"), l = E("span", "vf-tab-l", label);
      b._badge = E("span", "vf-badge");
      ico.append(icon({ questions: "list", answer: "pencil", compare: "columns", tree: "tree", more: "more" }[k]), b._badge);
      b.append(ico, l);
      b.onclick = () => (k === "more" ? toggleMore() : setTab(k)); tabs.append(b); tabBtns[k] = b;
    }
    tabBtns.more.setAttribute("aria-haspopup", "dialog"); tabBtns.more.setAttribute("aria-expanded", "false");

    // Chat
    const fab = btn("vf-fab"); fab.setAttribute("aria-label", "Open chat"); fab.setAttribute("aria-expanded", "false");
    const fabBadge = E("span", "vf-fab-badge");
    const chatIco = icon("chat", "vf-ico vf-ico-chat"); chatIco.lastChild.setAttribute("class", "vf-ico-dots");
    fab.append(chatIco, icon("x", "vf-ico vf-ico-x"), fabBadge);
    on(fab, "animationend", e => { if (e.target === fab || e.target === fabBadge) fab.classList.remove(e.target === fab ? "vf-bump" : "vf-badge-pop"); });
    const chat = E("section", "vf-chat"); chat.setAttribute("aria-label", "Chat"); chat.hidden = true;
    const chatHead = E("div", "vf-chat-head");
    const chatMeta = E("span", "vf-meta");
    const chatClose = ibtn("vf-tbtn vf-icon-btn", "x", "Close chat");
    const chatTitle = E("div", "vf-chat-title"); chatTitle.append(E("h2", "vf-h2", "Chat"), chatMeta);
    chatHead.append(chatTitle, chatClose);
    const mScroll = E("div", "vf-mscroll");
    const mList = E("ul", "vf-mlist"); mList.setAttribute("role", "log");
    const mEmpty = E("p", "vf-empty vf-empty-sm", "No messages yet. Say hi, or float an idea.");
    mScroll.append(mList, mEmpty);
    // Triage 24: scrolled up when messages arrive, the chat says how many are new instead of jumping.
    const mNew = btn("vf-mnew"); mNew.hidden = true;
    mNew.onclick = () => { mScroll.scrollTo({ top: mScroll.scrollHeight, behavior: smooth() }); mNew.hidden = true; ui.mNewFrom = null; };
    // A reader at the newest message stays there when the list or its box changes size: an on-screen keyboard opening
    // or closing, the message field growing a line, a message arriving. Shrinking a box never fires scroll, so the
    // last scroll decides.
    const mGap = () => mScroll.scrollHeight - mScroll.scrollTop - mScroll.clientHeight;
    let mStick = true;
    on(mScroll, "scroll", () => { mStick = mGap() < 40; if (mStick) { mNew.hidden = true; ui.mNewFrom = null; } if (mScroll.scrollTop < EARLIER_PX) loadTop(); });
    // ---------- older chat: loaded when the reader nears the top, or from a Load earlier button ----------
    const EARLIER_PX = 300; // judgment: about five messages above the top edge
    /** A place in the chat: a message's id and time; `after` gives the messages newer than it. */
    const mark = m => (m ? { id: m.id, ts: m.ts } : { id: "", ts: 0 });
    function after(msgs, at) {
      if (!at) return [];
      const i = at.id ? msgs.findIndex(m => m.id === at.id) : -1;
      return i >= 0 ? msgs.slice(i + 1) : msgs.filter(m => m.ts > at.ts);
    }
    function loadTop() {
      const top = mList.firstElementChild;
      if (ui.chatOpen && mScroll.scrollTop < EARLIER_PX && top?.classList.contains("vf-mgap") && Date.now() > (ui.mRetry || 0)) loadEarlier(top._below, top._b);
    }
    /** Read the messages older than message `id` into the chat, keeping what the reader sees where it is. */
    async function loadEarlier(id, button) {
      if (ui.mLoading || !id) return;
      ui.mLoading = true;
      const hadFocus = document.activeElement === button;
      const anchor = [...mList.querySelectorAll(":scope > .vf-msg")].find(li => li.getBoundingClientRect().bottom > mScroll.getBoundingClientRect().top);
      const was = anchor?.getBoundingClientRect().top;
      try {
        const n = await Core.chatEarlier(id);
        // Hold the anchor for a few frames: messages drawn as they come into view (content-visibility) settle their height.
        for (let f = 0, still = 0; f < 12 && still < 3 && anchor?.isConnected; f++) {
          const d = anchor.getBoundingClientRect().top - was;
          still = Math.abs(d) < 0.5 ? still + 1 : 0;
          mScroll.scrollTop += d;
          await new Promise(r => requestAnimationFrame(r));
        }
        announce(n ? `${n} earlier message${n === 1 ? "" : "s"} loaded.` : "This is the start of the chat.");
        if (hadFocus && !button.isConnected) mList.querySelector(".vf-msgmore")?.focus({ preventScroll: true });
      } catch (e) { ui.mRetry = Date.now() + 10000; fail(e); } finally { ui.mLoading = false; }
    }
    /** Open the chat at one message, reading it from the server when it is outside what the page holds. */
    /** `gone`, when given, runs in place of the "no longer in the chat" notice. */
    async function goMsg(id, gone) {
      if (!mList._map?.has(id) && !(await Core.chatAround(id).catch(() => false))) return gone ? gone() : flash("That message is no longer in the chat.");
      // At once, not smoothly: a poll's render during a smooth scroll would still see the reader at the newest message.
      // Off the newest now, so nothing pins the chat back to it before this scroll's own event says so.
      requestAnimationFrame(() => { const li = mList._map?.get(id); if (li) { li.scrollIntoView({ block: "center" }); mStick = false; ring(li); } });
    }
    const mPin = new ResizeObserver(() => { if (ui.chatOpen && mStick && mGap() > 0) mScroll.scrollTop = mScroll.scrollHeight; });
    mPin.observe(mScroll); mPin.observe(mList); offs.push(() => mPin.disconnect());
    const mTyping = E("div", "vf-mtyping"); const mTypingTxt = E("span");
    mTyping.append(dots(), mTypingTxt);
    const mForm = E("form", "vf-mform");
    const mInput = E("textarea", "vf-ta vf-minput"); mInput.rows = 1; mInput.placeholder = "Message everyone"; mInput.setAttribute("aria-label", "Chat message"); mInput.maxLength = 2000;
    const mSend = E("button", "vf-btn vf-btn-primary", "Send"); mSend.type = "submit";
    const mCount = E("span", "vf-count-txt vf-mcount"); mCount.setAttribute("aria-live", "polite");
    mForm.append(mInput, mSend);
    // As in a Discussion: "@Claude" in a message also asks Claude, here about the whole session.
    const mHint = E("p", "vf-mhint", "Type @Claude to send it to Claude."); mHint.id = "vf-mhint";
    mInput.setAttribute("aria-describedby", mHint.id);
    // Replying to: the quoted message rides above the field until it is sent or cancelled.
    const mReply = E("div", "vf-mreply"); mReply.hidden = true;
    const mReplyTxt = E("span", "vf-mreply-txt"), mReplyX = ibtn("vf-tbtn vf-icon-btn vf-mreply-x", "x", "Cancel the reply");
    mReply.append(icon("reply"), mReplyTxt, mReplyX);
    chat.append(chatHead, mScroll, mNew, mTyping, mCount, mReply, mHint, mForm);
    // @mention suggestions: one list, under (or over) whichever field is being typed in.
    const mentionBox = E("ul", "vf-pop vf-mentions"); mentionBox.setAttribute("role", "listbox"); mentionBox.id = "vf-mentions"; mentionBox.hidden = true;
    mentionBox.setAttribute("aria-label", "People to mention");

    // Person card: hover or focus shows it, a tap or click pins it (then it holds the owner's actions).
    const pcard = E("div", "vf-pop vf-pcard"); pcard.setAttribute("role", "dialog"); pcard.setAttribute("aria-label", "Person"); pcard.hidden = true;

    const settingsPop = E("div", "vf-pop vf-settings"); settingsPop.setAttribute("role", "dialog"); settingsPop.setAttribute("aria-label", "Session settings"); settingsPop.hidden = true;
    settingsPop.append(E("h2", "vf-pop-title", "Session settings"), E("p", "vf-pop-note", "Changes apply to everyone right away."));
    const switches = {};
    for (const [k, label, desc] of [
      ["voting", "Voting", "Votes on answers; the most voted leads"],
      ["signoff", "Sign-off to lock", "Everyone here must vote for the answer"],
      ["chat", "Chat", "Side chat for everyone"],
      ["follow", "Follow host", "Guests can follow your question"],
      ["showNames", "Show names", "Off shows initials and vote counts only"],
      ["digestNames", "Names to Claude", "Send who answered along with the round, except people a question is aimed at, who are always named"],
      ["uploads", "Uploads", "Let people offer files; you accept each one"],
      ["hideClaude", "Answer first", "Claude's cards show once a person answered or voted; each person can change it"],
      ["approveJoins", "Approve new joins", "New people wait in the queue until you let them in; people already here are not affected"],
    ]) {
      const b = btn("vf-sw-row"); b.setAttribute("role", "switch");
      const txt = E("span", "vf-sw-txt"); txt.append(E("span", "vf-sw-label", label), E("span", "vf-sw-desc", desc));
      b.append(txt, E("span", "vf-switch"));
      b.onclick = () => Core.saveSettings({ [k]: !st()[k] }).catch(fail);
      settingsPop.append(b); switches[k] = b;
    }
    const MODES = [["system", "System"], ["light", "Light"], ["dark", "Dark"]];
    const ACCENTS = [["teal", "Teal"], ["indigo", "Indigo"], ["violet", "Violet"], ["amber", "Amber"]];
    /** Theme picker: mode buttons and accent swatches; get() returns the current choice, set(patch) saves. */
    function themePicker(get, set) {
      const wrap = E("div", "vf-theme");
      const modes = E("div", "vf-seg vf-seg-sm"); modes.setAttribute("role", "group"); modes.setAttribute("aria-label", "Theme");
      const sw = E("div", "vf-swatches"); sw.setAttribute("role", "group"); sw.setAttribute("aria-label", "Accent color");
      const mb = MODES.map(([k, l]) => { const b = btn("vf-seg-btn", l); b.onclick = () => set({ mode: k }); modes.append(b); return [k, b]; });
      const ab = ACCENTS.map(([k, l]) => { const b = btn("vf-swatch"); b.dataset.accent = k; b.setAttribute("aria-label", `${l} accent`); b.title = l; b.onclick = () => set({ accent: k }); sw.append(b); return [k, b]; });
      wrap.append(modes, sw);
      wrap._paint = () => { const c = get(); for (const [k, b] of mb) b.setAttribute("aria-pressed", String(c.mode === k)); for (const [k, b] of ab) b.setAttribute("aria-pressed", String(c.accent === k)); };
      return wrap;
    }
    const sessionTheme = () => ({ mode: "system", accent: "teal", ...(st().theme || {}) });
    const ownerTheme = themePicker(sessionTheme, patch => Core.saveSettings({ theme: patch }).catch(fail));
    settingsPop.append(E("h3", "vf-pop-sub", "Default theme for everyone"), ownerTheme);
    const newGuestBtn = btn("vf-menu-item vf-menu-plain", "New guest link");
    const newOwnerBtn = btn("vf-menu-item vf-menu-plain", "New owner link");
    const endBtn = btn("vf-menu-item", "End session");
    const endNote = E("p", "vf-pop-note vf-sub-note");
    const removedHead = E("h3", "vf-pop-sub", "Removed people");
    const removedList = E("ul", "vf-removed"); removedList.setAttribute("aria-label", "Removed people");
    settingsPop.append(E("h3", "vf-pop-sub", "Links and session"),
      E("p", "vf-pop-note vf-sub-note", "A new guest link stops the old one letting new people in; people already here stay. A new owner link reloads this page on it."),
      newGuestBtn, newOwnerBtn, endBtn, endNote, removedHead, removedList);

    const sharePop = E("div", "vf-pop vf-share"); sharePop.setAttribute("role", "dialog"); sharePop.setAttribute("aria-label", "Invite people"); sharePop.hidden = true;
    const shareField = E("input", "vf-input vf-share-url"); shareField.readOnly = true; shareField.setAttribute("aria-label", "Guest link");
    const shareRow = E("div", "vf-crow");
    const copyBtn = btn("vf-btn vf-btn-primary", "Copy link");
    const nativeShare = btn("vf-btn vf-btn-ghost", "Share…");
    shareRow.append(nativeShare, copyBtn);
    const shareNew = E("p", "vf-share-new"); shareNew.hidden = true;
    sharePop.append(E("h2", "vf-pop-title", "Invite people"), shareNew, shareField, shareRow,
      E("p", "vf-pop-note", "Anyone with this link can join. The link changes if the tunnel restarts."));

    const keysPop = E("div", "vf-pop vf-keys"); keysPop.setAttribute("role", "dialog"); keysPop.setAttribute("aria-label", "Help"); keysPop.hidden = true;
    keysPop.tabIndex = -1;
    const keyList = E("dl", "vf-keylist");
    for (const [k, d] of [["← →", "Previous or next question"], ["↑ ↓", "Move between answers"], ["V", "Vote for the selected answer"], ["Enter", "Write your answer"], ["?", "Show this help"], ["Esc", "Close a panel or the reader"]]) {
      const dt = E("dt"); for (const part of k.split(" ")) dt.append(E("kbd", null, part));
      keyList.append(dt, E("dd", null, d));
    }
    const helpTour = btn("vf-btn vf-btn-primary vf-btn-sm vf-help-tour", "Show me around");
    const helpIntro = btn("vf-btn vf-btn-ghost vf-btn-sm vf-help-intro", "Why you're here");
    const helpReport = btn("vf-btn vf-btn-ghost vf-btn-sm vf-help-report", "Report a problem");
    const helpMyReps = btn("vf-btn vf-btn-ghost vf-btn-sm vf-help-myreps", "Your reports");
    keysPop.append(E("h2", "vf-pop-title", "Help"), E("p", "vf-pop-note", "A one-minute tour of the questions, your answer, other people's answers and the chat."), helpTour, helpIntro, helpReport, helpMyReps,
      Core.telemetry.notice("core-rec vf-help-rec"), E("h3", "vf-pop-sub", "Keyboard shortcuts"), keyList, E("p", "vf-pop-note", "They work when you are not typing in a field."));

    // Phase 4c: "Why you're here", reopened from the header (or More on a phone) after the first view.
    const introPop = E("div", "vf-pop vf-intropop"); introPop.setAttribute("role", "dialog"); introPop.setAttribute("aria-labelledby", "vf-intropop-h"); introPop.hidden = true;
    const ipH = E("h2", "vf-pop-title", "Why you're here"); ipH.id = "vf-intropop-h";
    const ipText = E("p", "vf-intropop-t"), ipGoal = E("p", "vf-pop-note vf-intropop-goal");
    const ipEdit = btn("vf-btn vf-btn-ghost vf-btn-sm", "Edit in Host view");
    introPop.append(ipH, ipText, ipGoal, ipEdit);
    const introBtn = ibtn("vf-tbtn vf-icon-btn vf-introbtn", "doc", "Why you're here"); introBtn.setAttribute("aria-haspopup", "dialog");

    // Phase 4c: the owner edits one answer's text; every earlier version, with who and when, shows only here.
    const editPop = E("div", "vf-pop vf-editpop"); editPop.setAttribute("role", "dialog"); editPop.setAttribute("aria-labelledby", "vf-editpop-h"); editPop.hidden = true;
    const epH = E("h2", "vf-pop-title", "Edit this answer"); epH.id = "vf-editpop-h";
    const epNote = E("p", "vf-pop-note", "Everyone sees \"Edited by the host\" on it. Earlier versions stay here, for you only.");
    const epTa = E("textarea", "vf-ta vf-edit-ta"); epTa.maxLength = 2000; epTa.rows = 4; epTa.setAttribute("aria-label", "Answer text");
    const epRow = E("div", "vf-crow"), epCancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel"), epSave = btn("vf-btn vf-btn-primary vf-btn-sm", "Save edit");
    epRow.append(E("span", "vf-spacer"), epCancel, epSave);
    const epHistH = E("h3", "vf-pop-sub", "Earlier versions"), epHist = E("ol", "vf-history"); epHist.setAttribute("aria-label", "Earlier versions");
    editPop.append(epH, epNote, epTa, epRow, epHistH, epHist);
    /** The history list: oldest first, each with who wrote it and when. */
    function fillHistory(ol, history) {
      ol.replaceChildren(...(history || []).map(v => {
        const li = E("li", "vf-hist");
        li.append(E("span", "vf-hist-who", `${v.cid === "host" ? "The host" : disp(v.name)}, ${ago(v.ts)} ago`), E("span", "vf-hist-t", v.text));
        return li;
      }));
    }
    function openEdit(qid, a, anchor) {
      ui.editing = { qid, ref: a.ref, cid: a.cid };
      epTa.value = a.text || "";
      epHist.replaceChildren();
      epHistH.hidden = epHist.hidden = !a.versions;
      // The versions are not in the snapshot: fetch them for this answer when the list opens.
      if (a.versions) Core.cardHistory(qid, a.ref).then(h => { if (ui.editing?.ref === a.ref) fillHistory(epHist, h.history); }).catch(fail);
      openPop(editPop, anchor);
      requestAnimationFrame(() => epTa.focus());
    }
    epCancel.onclick = () => closePop();
    epSave.onclick = () => {
      const e = ui.editing, text = epTa.value.trim();
      if (!e) return;
      if (!text) { epTa.focus(); return flash("An edit needs text. To take an answer away from everyone, hide it instead."); }
      epSave.disabled = true;
      Core.editCard(e.qid, e.ref, text).then(() => { closePop(); flash("Edited. Everyone sees \"Edited by the host\" on it."); }).catch(fail).finally(() => { epSave.disabled = false; });
    };
    /** Hide or show one answer again (owner). */
    const toggleHidden = (qid, a) => Core.hideCard(qid, a.ref, !a.hidden)
      .then(() => flash(a.hidden ? "Shown again to everyone." : "Hidden from everyone else and from Claude's digest. Its author still sees it, marked."))
      .catch(fail);

    // Phase 4c: one person at a glance for the owner: every answer, pick, vote, request and chat line, with Hide, Edit
    // beside each answer and Remove for the person.
    const personPop = E("div", "vf-pop vf-panel vf-personpop"); personPop.setAttribute("role", "dialog"); personPop.setAttribute("aria-labelledby", "vf-personpop-h"); personPop.hidden = true;
    const ppvHead = E("div", "vf-pp-head"), ppvH = E("h2", "vf-pop-title"); ppvH.id = "vf-personpop-h";
    const ppvClose = ibtn("vf-tbtn vf-icon-btn", "x", "Close");
    ppvHead.append(ppvH, ppvClose);
    const ppvRemove = btn("vf-btn vf-btn-ghost vf-btn-sm vf-btn-danger");
    const ppvBody = E("div", "vf-pscroll vf-ppv-body");
    personPop.append(ppvHead, ppvRemove, ppvBody);
    ppvClose.onclick = () => closePop();
    ppvRemove.onclick = guarded(() => !(Core.state.removed || []).includes(ui.personView) && removeAsk(nameOf(ui.personView)), () => {
      const pid = ui.personView, out = (Core.state.removed || []).includes(pid);
      Core.removePerson(pid, !out).then(() => flash(out ? "Restored. Their content shows again." : `${disp(nameOf(pid))} was removed. Their content is hidden.`)).catch(fail);
    });
    function openPersonView(pid, anchor) { ui.personView = pid; ppvBody._sig = ""; fillPersonView(); openPanel(personPop, anchor); }
    /** The person view's sections, rebuilt only when what they show changed, so focus stays put across polls. */
    function fillPersonView() {
      const S = Core.state, pid = ui.personView;
      if (!pid) return;
      const name = nameOf(pid), gone = (S.removed || []).includes(pid);
      ppvH.textContent = `${disp(name)}: everything they did`;
      ppvRemove.textContent = gone ? `Restore ${disp(name)}` : `Remove ${disp(name)}`;
      ppvRemove.hidden = pid === "host";
      const answers = [], votes = [];
      for (const q of S.questions) {
        for (const a of Core.answersFor(q.id)) {
          if (a.cid === pid && !a.claude && !a.option) answers.push([q, a]);
          else if ((a.votes || []).includes(pid)) votes.push([q, a]);
        }
      }
      const reqs = (S.requests || []).filter(r => r.cid === pid), msgs = S.chat.filter(m => m.cid === pid);
      const cleared = (S.cleared || []).filter(t => t.cid === pid);
      const sig = JSON.stringify([name, gone, answers.map(([q, a]) => [q.id, a.ref, a.text, a.pick, a.picks, a.value, a.order, !!a.hidden, !!a.hostEdited, a.versions || 0]),
        votes.map(([q, a]) => [q.id, a.ref, a.text]), reqs.map(r => [r.id, r.status, r.text]), msgs.map(m => [m.id, m.text]), cleared.map(t => [t.qid, t.ref, t.ts])]);
      if (ppvBody._sig === sig) return;
      ppvBody._sig = sig;
      const section = (title, rows, empty) => {
        const s = E("section", "vf-ppv-sec"), ul = E("ul", "vf-ppv-list");
        s.append(E("h3", "vf-pop-sub", `${title} (${rows.length})`));
        if (rows.length) { ul.append(...rows); s.append(ul); } else s.append(E("p", "vf-pop-note", empty));
        return s;
      };
      const row = (head, text, ...acts) => {
        const li = E("li", "vf-ppv-item"), top2 = E("div", "vf-ppv-head");
        top2.append(E("span", "vf-ppv-q", head));
        li.append(top2, E("p", "vf-ppv-t", text));
        if (acts.length) { const r = E("div", "vf-acts"); r.append(...acts); li.append(r); }
        return li;
      };
      const ansRows = answers.map(([q, a]) => {
        const said = [a.text, pickedText(q, a)].filter(Boolean).join(" | ") || "(no text)";
        const marks = [a.hidden ? "hidden" : "", a.hostEdited ? "edited by you" : "", a.versions ? `${a.versions} earlier version${a.versions === 1 ? "" : "s"}` : ""].filter(Boolean);
        const hide = btn("vf-btn vf-btn-ghost vf-btn-sm", a.hidden ? "Show" : "Hide");
        hide.setAttribute("aria-label", `${a.hidden ? "Show" : "Hide"} ${disp(name)}'s answer on ${q.id}`);
        hide.onclick = () => toggleHidden(q.id, a);
        const edit = btn("vf-btn vf-btn-ghost vf-btn-sm", "Edit");
        edit.setAttribute("aria-label", `Edit ${disp(name)}'s answer on ${q.id}`);
        edit.onclick = () => openEdit(q.id, a, edit);
        return row(`${q.id}${marks.length ? ` (${marks.join(", ")})` : ""}`, said, hide, edit);
      });
      const voteRows = votes.map(([q, a]) => row(q.id, a.option ? `Picked: ${a.text}` : a.claude ? `Voted for Claude's card: ${a.text}` : `Voted for ${disp(a.name)}'s answer: ${a.text}`));
      const reqRows = reqs.map(r => row(`${r.qid}, ${r.status}`, `${KIND_REQ[r.kind] || "Request"}: ${r.text}`));
      const chatRows = msgs.map(m => row(`${ago(m.ts)} ago`, m.text));
      // An answer they cleared after you hid or edited it: its last text and versions, fetched when asked.
      const clearedRows = cleared.map(t => {
        const show = btn("vf-btn vf-btn-ghost vf-btn-sm", "Show what it said");
        show.setAttribute("aria-label", `Show what ${disp(name)}'s cleared answer on ${t.qid} said`);
        const li = row(`${t.qid}, cleared ${ago(t.ts)} ago${t.hidden ? " (hidden)" : ""}`, "", show), out = li.querySelector(".vf-ppv-t"), ol = E("ol", "vf-history");
        li.append(ol);
        show.onclick = () => Core.cardHistory(t.qid, t.ref).then(h => {
          out.textContent = h.text || "(no text)";
          fillHistory(ol, h.history);
          show.hidden = true;
        }).catch(fail);
        return li;
      });
      ppvBody.replaceChildren(section("Answers and picks", ansRows, "No answers."), section("Votes", voteRows, "No votes."),
        section("Requests to Claude", reqRows, "No requests."), section("Chat", chatRows, "No chat messages."),
        ...(clearedRows.length ? [section("Cleared after you hid or edited them", clearedRows, "")] : []));
    }

    // Reader: one text at full width.
    const reader = E("div", "vf-reader"); reader.setAttribute("role", "dialog"); reader.setAttribute("aria-modal", "true"); reader.hidden = true;
    const rdHead = E("header", "vf-rd-head");
    const rdTitles = E("div", "vf-rd-titles");
    const rdTitle = E("h2", "vf-rd-title"), rdMeta = E("p", "vf-rd-meta");
    rdTitles.append(rdTitle, rdMeta);
    const rdClose = ibtn("vf-tbtn vf-icon-btn", "x", "Close reader");
    rdHead.append(rdTitles, rdClose);
    const rdBody = E("div", "vf-rd-body");
    const rdText = E("div", "vf-rich vf-rd-text");
    rdBody.append(rdText);
    reader.append(rdHead, rdBody);
    reader.setAttribute("aria-labelledby", rdTitle.id = "vf-rd-title");

    // Picture viewer: one picture as large as the screen allows, ← → through the set, pinch or double-tap to zoom,
    // and the pick controls for a choice or confirm question right under it.
    const lb = E("div", "vf-lb"); lb.setAttribute("role", "dialog"); lb.setAttribute("aria-modal", "true"); lb.hidden = true; lb.tabIndex = -1;
    const lbHead = E("header", "vf-lb-head"), lbTitles = E("div", "vf-lb-titles");
    const lbTitle = E("h2", "vf-lb-title"), lbMeta = E("p", "vf-lb-meta");
    lbTitles.append(lbTitle, lbMeta);
    const lbClose = lbtn("vf-btn vf-btn-ghost vf-lb-close", "x", "Close");
    lbClose.setAttribute("aria-label", "Close the picture");
    lbHead.append(lbTitles, lbClose);
    const lbStage = E("div", "vf-lb-stage");
    const lbFrame = E("div", "vf-lb-frame"), lbImg = E("img", "vf-lb-img"), lbMark = E("span", "vf-confirm-mark");
    lbImg.draggable = false; lbMark.setAttribute("aria-hidden", "true"); lbFrame.append(lbImg, lbMark);
    lbImg.onload = () => { if (lbImg.naturalWidth && lbImg.naturalHeight) lbFrame.style.setProperty("--ar", String(lbImg.naturalWidth / lbImg.naturalHeight)); };
    const lbPrev = ibtn("vf-lb-nav vf-lb-prev", "chevL", "Previous picture"), lbNext = ibtn("vf-lb-nav vf-lb-next", "chevR", "Next picture");
    lbStage.append(lbFrame, lbPrev, lbNext);
    const lbFoot = E("footer", "vf-lb-foot"), lbInfo = E("div", "vf-lb-info");
    const lbCount = E("span", "vf-lb-count"), lbVoters = E("span", "vf-avrow vf-voters"), lbPicks = E("span", "vf-lb-picks");
    lbInfo.append(lbCount, lbVoters, lbPicks);
    const lbActs = E("div", "vf-lb-acts");
    const lbChoose = btn("vf-btn vf-lb-choose"), lbYes = btn("vf-btn vf-lb-yn", "Yes"), lbNo = btn("vf-btn vf-lb-yn", "No");
    const lbUndo = btn("vf-btn vf-btn-ghost vf-btn-sm vf-optundo vf-lb-undo", "Undo");
    const lbZoom = E("p", "vf-lb-zoomhint");
    lbActs.append(lbChoose, lbYes, lbNo, lbUndo);
    lbFoot.append(lbInfo, lbActs, lbZoom);
    lb.append(lbHead, lbStage, lbFoot);
    lb.setAttribute("aria-labelledby", lbTitle.id = "vf-lb-title");

    // Per-message menu in chat.
    const msgMenu = E("div", "vf-pop vf-menu vf-msgmenu"); msgMenu.setAttribute("role", "menu"); msgMenu.setAttribute("aria-label", "Message actions"); msgMenu.hidden = true;
    const mmPropose = lbtn("vf-menu-item vf-menu-plain", "forward", "Propose as question");
    const mmAsk = lbtn("vf-menu-item vf-menu-plain", "sparkle", "Ask Claude about this");
    const mmCopy = lbtn("vf-menu-item vf-menu-plain", "copy", "Copy");
    const mmReply = lbtn("vf-menu-item vf-menu-plain", "reply", "Reply");
    const mmReact = btn("vf-menu-item vf-menu-plain"); mmReact.append(E("span", "vf-mm-face", "🙂"), E("span", null, "React"));
    for (const b of [mmReply, mmReact, mmPropose, mmAsk, mmCopy]) { b.setAttribute("role", "menuitem"); msgMenu.append(b); }

    // ---------- Q82: notifications ----------
    const NOTE_KINDS = [["mention", "Mentions of me", "at"], ["reply", "Replies to my messages", "reply"], ["request", "My requests to Claude", "sparkle"],
      ["proposal", "My proposals placed or not", "forward"], ["round", "New rounds", "list"], ["merge", "Merges I asked for", "merge"],
      ["role", "Made leader or trusted", "host"], ["votes", "Agreement with my answers, once an hour", "thumb"],
      ["reaction", "Reactions to my chat messages", "chat"], ["discussion", "New comments in Discussions I am in", "chat"],
      ["queue", "New items in the host queue", "host"], ["ready", "A round marked ready", "check"], ["report", "The host read my problem reports", "help"]];
    const bellPop = E("div", "vf-pop vf-bellpop vf-inboxpop"); bellPop.setAttribute("role", "dialog"); bellPop.setAttribute("aria-labelledby", "vf-inbox-h"); bellPop.hidden = true;
    const bpHead = E("div", "vf-pp-head");
    const bpAll = btn("vf-btn vf-btn-ghost vf-btn-sm", "Mark all read");
    const bpClose = ibtn("vf-tbtn vf-icon-btn", "x", "Close the Inbox");
    const ixTitle = E("h2", "vf-pop-title", "Inbox"); ixTitle.id = "vf-inbox-h";
    const ixCount = E("span", "vf-chip vf-chip-new vf-ixcount");
    const IX_TABS = [["all", "All"], ["mine", "Mine"], ["waiting", "Waiting on you"], ["notes", "Notifications"]];
    const ixTabs = E("div", "vf-seg vf-seg-sm vf-ixtabs"); ixTabs.setAttribute("role", "group"); ixTabs.setAttribute("aria-label", "Show in the Inbox");
    const ixTabBtn = {};
    for (const [k, label] of IX_TABS) { const b = btn("vf-seg-btn", label); b.dataset.k = k; b.onclick = () => { ui.ixTab = k; render(); }; ixTabs.append(b); ixTabBtn[k] = b; }
    const ixSec = (cls, title) => {
      const sec = E("section", "vf-ixsec " + cls), h = E("h3", "vf-ixh");
      sec.append(h); sec._h = h; sec._title = title;
      return sec;
    };
    const ixMine = ixSec("vf-ixmine", "Your requests"), ixWait = ixSec("vf-ixwait", "Waiting on you"), ixNotes = ixSec("vf-ixnotes", "Notifications");
    const ixMineList = E("ul", "vf-ixlist"); ixMineList.setAttribute("role", "list");
    const ixMineEmpty = E("p", "vf-empty vf-empty-sm", "No requests yet. Ask Claude on a question and it shows here, with its status, until you open the answer.");
    ixMine.append(ixMineList, ixMineEmpty);
    // What waits on the owner, one group per kind, each item linking to where it is handled.
    const IX_WAIT = [["run", "Requests to run"], ["share", "Results to share"], ["report", "Problem reports"], ["merge", "Merge requests"], ["join", "Join requests"]];
    const ixWaitLists = {};
    for (const [k, label] of IX_WAIT) {
      const g = E("div", "vf-ixgroup"), h = E("h4", "vf-ixgh"), ul = E("ul", "vf-ixlist"); ul.setAttribute("role", "list");
      g.append(h, ul); ixWait.append(g); ixWaitLists[k] = { g, h, ul, label };
    }
    const bpUnread = btn("vf-btn vf-btn-ghost vf-btn-sm vf-toggle", "Unread only");
    bpUnread.onclick = () => { ui.unreadOnly = !ui.unreadOnly; render(); };
    bpHead.append(ixTitle, ixCount, bpAll, bpClose);
    const bpTools = E("div", "vf-bptools"); bpTools.append(bpUnread);
    const nList = E("ul", "vf-nlist"); nList.setAttribute("role", "list");
    const NO_NOTES = "Nothing new. You hear here when someone mentions you or replies to you, when your requests and proposals move, and when a round opens.";
    const nEmpty = E("p", "vf-empty vf-empty-sm", NO_NOTES);
    const muteBtn = btn("vf-lbtn vf-mutebtn"); muteBtn.setAttribute("aria-expanded", "false");
    const muteBox = E("div", "vf-mutebox"); muteBox.hidden = true;
    const muteRows = {};
    for (const [k, label] of NOTE_KINDS) {
      const b = btn("vf-sw-row"); b.setAttribute("role", "switch");
      b.append(E("span", "vf-sw-txt", label), E("span", "vf-switch"));
      b.querySelector(".vf-sw-txt").classList.add("vf-sw-label");
      b.onclick = () => { const m = new Set(pref("mute", [])); m.has(k) ? m.delete(k) : m.add(k); setPrefs({ mute: [...m] }); render(); };
      muteBox.append(b); muteRows[k] = b;
    }
    const noteMore = showMore("notes", 20);
    ixNotes.append(bpTools, nList, noteMore.foot, nEmpty, muteBtn, muteBox);
    const bpScroll = E("div", "vf-pscroll vf-bpscroll"); bpScroll.append(ixTabs, ixMine, ixWait, ixNotes);
    bellPop.append(bpHead, bpScroll);

    // ---------- Q86: the phone More sheet ----------
    const moreSheet = E("div", "vf-pop vf-panel vf-moresheet"); moreSheet.setAttribute("role", "dialog"); moreSheet.setAttribute("aria-label", "More"); moreSheet.hidden = true;
    const msHead = E("div", "vf-pp-head");
    const msClose = ibtn("vf-tbtn vf-icon-btn", "x", "Close more");
    msHead.append(E("h2", "vf-pop-title", "More"), msClose);
    const msList = E("div", "vf-mslist");
    const msItem = (ico, label) => { const b = btn("vf-msitem"); const t = E("span", "vf-ms-l", label), d = E("span", "vf-ms-d"); b.append(icon(ico), t, d); b._d = d; b._l = t; msList.append(b); return b; };
    const msAsk = msItem("sparkle", "Ask Claude"), msBell = msItem("host", "Inbox"), msTheme = msItem("system", "Theme");
    const msFollow = msItem("forward", "Follow host"), msShare = msItem("link", "Share"), msSettings = msItem("gear", "Settings"), msHost = msItem("host", "Host view");
    const msTour = msItem("help", "Show me around"); msTour._d.textContent = "A one-minute tour";
    const msIntro = msItem("doc", "Why you're here");
    const msReport = msItem("alert", "Report a problem"); msReport._d.textContent = "Tell the host something is broken";
    const msMyReps = msItem("doc", "Your reports"); msMyReps._d.textContent = "What you reported and where it stands";
    const msRecords = msItem("doc", "What this page records");
    moreSheet.append(msHead, msList);

    // ---------- Triage 4: an optional first-visit tour, skippable, re-opened from Help; the `tour` pref remembers it ----------
    const tour = E("div", "vf-tour"); tour.hidden = true;
    const tourRing = E("div", "vf-tour-ring"); tourRing.setAttribute("aria-hidden", "true");
    const tourCard = E("div", "vf-tour-card"); tourCard.setAttribute("role", "dialog"); tourCard.setAttribute("aria-modal", "true");
    tourCard.setAttribute("aria-labelledby", "vf-tour-h"); tourCard.setAttribute("aria-describedby", "vf-tour-t");
    const tourN = E("p", "vf-tour-n"), tourH = E("h2", "vf-tour-h"), tourT = E("p", "vf-tour-t");
    tourH.id = "vf-tour-h"; tourT.id = "vf-tour-t";
    const tourRow = E("div", "vf-crow vf-tour-row");
    const tourSkip = btn("vf-btn vf-btn-ghost vf-btn-sm", "Skip tour"), tourBack = btn("vf-btn vf-btn-ghost vf-btn-sm", "Back"), tourNext = btn("vf-btn vf-btn-primary vf-btn-sm");
    tourRow.append(tourSkip, E("span", "vf-spacer"), tourBack, tourNext);
    tourCard.append(tourN, tourH, tourT, tourRow);
    tour.append(tourRing, tourCard);
    const shown = el => !!el && el.isConnected && !el.closest("[hidden]") && el.getClientRects().length > 0;
    const TOUR = [
      { h: "The questions", t: "Every question in this round is listed here. A tick marks each one you answered.",
        at: () => (phone.matches ? tabBtns.questions : rail) },
      { h: "Answer here", t: "Read the question, then pick an option. Where a question has no options, type your answer instead.",
        at: () => (fmtBox.hidden ? qText : fmtBox) },
      { h: "Your answer box", t: "Type your answer, or a comment on your pick, right under the question, then send it. You can change it until the host locks the question.",
        at: () => composer },
      { h: "Everyone's answers", t: "Once you have answered, other people's answers show here, and you can vote for the ones you agree with.",
        at: () => ansPane },
      { h: "Chat with people", t: "The chat is for talking with the others here. It is not sent to Claude and does not count as an answer.",
        at: () => fab },
      { h: "Help is here", t: "Open Help to take this tour again or see the keyboard shortcuts.",
        at: () => (phone.matches ? tabBtns.more : keysBtn) },
    ];
    const TT = { i: 0, from: null, steps: [] };
    function startTour(from) {
      closePop(); hideCard(); if (ui.chatOpen) setChat(false);
      setMode("focus"); if (phone.matches) setTab("answer");
      TT.from = from || null;
      TT.steps = TOUR.filter(s => shown(s.at()));
      if (!TT.steps.length) return;
      TT.i = 0; tour.hidden = false; root.dataset.tour = "";
      for (const el of [top, body, tabs, fab, chat]) el.inert = true;
      paintTour();
    }
    function endTour(how) {
      if (tour.hidden) return;
      tour.hidden = true; delete root.dataset.tour;
      for (const el of [top, body, tabs, fab, chat]) el.inert = false;
      syncModal();
      setPrefs({ tour: how });
      const back = TT.from && shown(TT.from) ? TT.from : qText;
      back.focus({ preventScroll: true });
      announce(how === "done" ? "Tour finished. Help has it again any time." : "Tour skipped. Help has it any time.");
      render();
    }
    function paintTour() {
      const s = TT.steps[TT.i], el = s.at(), last = TT.i === TT.steps.length - 1;
      tourN.textContent = `${TT.i + 1} of ${TT.steps.length}`;
      tourH.textContent = s.h; tourT.textContent = s.t;
      tourBack.hidden = TT.i === 0;
      tourNext.textContent = last ? "Done" : "Next";
      el.scrollIntoView({ block: "nearest", behavior: "auto" });
      const R = root.getBoundingClientRect(), r = el.getBoundingClientRect();
      const box = { l: Math.max(R.left + 4, r.left - 4), t: Math.max(R.top + 4, r.top - 4), r: Math.min(R.right - 4, r.right + 4), b: Math.min(R.bottom - 4, r.bottom + 4) };
      // Moved with translate (composited); its size changes without a transition.
      Object.assign(tourRing.style, { translate: `${box.l - R.left}px ${box.t - R.top}px`, inlineSize: box.r - box.l + "px", blockSize: box.b - box.t + "px" });
      // The card sits below the target when it fits there, else above it, else over the bottom of the page.
      const cs = tourCard.style; cs.insetBlockStart = cs.insetBlockEnd = cs.insetInlineStart = "";
      const w = Math.min(360, R.width - 24), h = tourCard.offsetHeight || 180;
      cs.inlineSize = w + "px";
      cs.insetInlineStart = Math.min(Math.max(12, (box.l + box.r) / 2 - R.left - w / 2), R.width - w - 12) + "px";
      if (box.b + 12 + h <= R.bottom - 12) cs.insetBlockStart = box.b - R.top + 12 + "px";
      else if (box.t - 12 - h >= R.top + 12) cs.insetBlockStart = box.t - R.top - 12 - h + "px";
      else cs.insetBlockEnd = "12px";
      tourNext.focus({ preventScroll: true });
    }
    tourNext.onclick = () => { if (TT.i >= TT.steps.length - 1) return endTour("done"); TT.i++; paintTour(); };
    tourBack.onclick = () => { if (TT.i > 0) { TT.i--; paintTour(); } };
    tourSkip.onclick = () => endTour("skipped");
    on(tourCard, "keydown", e => {
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); endTour("skipped"); return; }
      if (e.key !== "Tab") return;
      const f = [tourSkip, tourBack, tourNext].filter(b => !b.hidden), i = f.indexOf(document.activeElement);
      e.preventDefault(); e.stopPropagation();
      f[(i + (e.shiftKey ? -1 : 1) + f.length) % f.length].focus();
    });
    // A click outside the card does nothing: the tour ends only by Skip, Done or Escape.
    on(tour, "pointerdown", e => { if (!tourCard.contains(e.target)) e.preventDefault(); });
    const tourMove = () => { if (!tour.hidden) paintTour(); };
    on(window, "resize", tourMove);

    // Ask Claude: right drawer on desktop, bottom sheet on phones.
    const askPanel = E("div", "vf-pop vf-drawer"); askPanel.setAttribute("role", "dialog"); askPanel.setAttribute("aria-label", "Ask Claude"); askPanel.hidden = true;
    const apHead = E("div", "vf-pp-head");
    const apClose = ibtn("vf-tbtn vf-icon-btn", "x", "Close Ask Claude");
    const apTitle = E("h2", "vf-pop-title vf-ap-title"); apTitle.append(claudeAv(20), E("span", null, "Ask Claude"));
    apHead.append(apTitle, apClose);
    const apModes = E("div", "vf-seg vf-seg-sm vf-apmodes"); apModes.setAttribute("role", "tablist"); apModes.setAttribute("aria-label", "What to ask for");
    const apModeBtns = {};
    for (const [k, label] of [["ask", "Ask"], ["research", "Research"], ["explore", "Explore"]]) {
      const b = btn("vf-seg-btn", label); b.setAttribute("role", "tab"); b.onclick = () => { ui.askMode = k; render(); apTa.focus(); }; apModes.append(b); apModeBtns[k] = b;
    }
    // A proposed question goes to the group, not to Claude, so it is not one of these tabs; this points to its form.
    const apPropose = btn("vf-lbtn vf-ap-propose", "Propose a question"); apPropose.setAttribute("aria-haspopup", "dialog");
    const apPointer = E("p", "vf-pop-note vf-ap-pointer", "Want the group asked something? "); apPointer.append(apPropose);
    const apForm = E("form", "vf-apform");
    const apQWrap = selWrap("About", []);
    apQWrap.w.classList.add("vf-apq");
    apQWrap.s.onchange = () => { ui.askQ = apQWrap.s.value; render(); };
    const apLabel = E("label", "vf-asklabel"); const apTa = E("textarea", "vf-ta"); apTa.rows = 3; apTa.maxLength = 2000; apTa.id = "vf-ap-ta"; apLabel.htmlFor = apTa.id;
    const apNote = E("p", "vf-pop-note");
    // Connect your Claude (R2-12): a guest's request can run on their own Claude, never the host's.
    const apSelf = btn("vf-sw-row vf-apself"); apSelf.setAttribute("role", "switch");
    apSelf.append(E("span", "vf-sw-txt vf-sw-label", "Run it on my own Claude"), E("span", "vf-switch"));
    apSelf.onclick = () => { ui.askSelf = !ui.askSelf; render(); };
    const apRow = E("div", "vf-crow");
    const apAttach = ibtn("vf-btn vf-btn-ghost vf-btn-sm vf-attach", "clip", "Attach a file");
    const apSend = E("button", "vf-btn vf-btn-primary", "Send request"); apSend.type = "submit";
    apRow.append(apAttach, E("span", "vf-spacer"), apSend);
    const apWeb = webChip();
    apWeb.onclick = () => { ui.apWeb = !ui.apWeb; render(); };
    apForm.append(apQWrap.w, apLabel, apTa, apWeb, apSelf, apNote, apRow);
    const apConnect = E("section", "vf-apconnect"); apConnect.setAttribute("aria-labelledby", "vf-apc-h");
    const apcHead = E("h3", "vf-pop-sub", "Connect your Claude"); apcHead.id = "vf-apc-h";
    const apcLinks = E("div", "vf-acts vf-apc-links");
    const apcCode = E("a", "vf-btn vf-btn-ghost vf-btn-sm vf-apc-code", "Open in Claude Code");
    const apcDesk = E("a", "vf-btn vf-btn-ghost vf-btn-sm vf-apc-desk", "Open in Claude Desktop (Code)");
    const apcCopyW = btn("vf-btn vf-btn-ghost vf-btn-sm vf-apc-copyw", "Copy watch prompt");
    const apcKey = btn("vf-btn vf-btn-ghost vf-btn-sm vf-apc-key", "Copy watcher key");
    const apcRevoke = btn("vf-btn vf-btn-ghost vf-btn-sm vf-apc-revoke", "Revoke watcher key");
    apcLinks.append(apcCode, apcDesk, apcCopyW, apcKey, apcRevoke);
    apConnect.append(apcHead,
      E("p", "vf-pop-note", "Your own Claude, on your own plan, runs these requests; the host's Claude never sees them. The host reviews each answer before anyone else sees it, marked as from your Claude."),
      E("p", "vf-pop-note", "Let Claude Code answer them as they come: open it with the prompt filled in, read it, and press Enter. It asks for your watcher key."),
      apcLinks,
      E("p", "vf-meta", "A watcher key only reads and answers your own requests. Copying one replaces the last; revoke it when you are done. Or run one request at a time: copy its prompt below and paste the answer back."));
    const apScroll = E("div", "vf-pscroll vf-apscroll");
    const apReqHead = E("h3", "vf-pop-sub", "Your requests");
    const apReqs = E("ul", "vf-plist vf-apreqs"); apReqs.setAttribute("role", "list");
    const apReqEmpty = E("p", "vf-empty vf-empty-sm", "No requests yet. What you ask shows here with where it stands.");
    const apFileHead = E("h3", "vf-pop-sub", "Your files");
    const apFiles = E("ul", "vf-upstrip vf-apfiles"); apFiles.setAttribute("aria-label", "Your files");
    // About the whole session: Claude's answers to general asks, the owner's to share; once shared each is also in chat.
    const apGenHead = E("h3", "vf-pop-sub", "Claude's answers about the session");
    const apGen = E("ul", "vf-thlist vf-apgen"); apGen.setAttribute("role", "list");
    apScroll.append(apForm, apConnect, apGenHead, apGen, apReqHead, apReqs, apReqEmpty, apFileHead, apFiles);
    askPanel.append(apHead, apModes, apPointer, apScroll);

    // Use on another device: a personal link and its QR code.
    const devicePop = E("div", "vf-pop vf-devicepop"); devicePop.setAttribute("role", "dialog"); devicePop.setAttribute("aria-label", "Use on another device"); devicePop.hidden = true;
    const qrBox = E("div", "vf-qr");
    const devField = E("input", "vf-input vf-share-url"); devField.readOnly = true; devField.setAttribute("aria-label", "Your personal link");
    const devRow = E("div", "vf-crow");
    const devCopy = btn("vf-btn vf-btn-primary", "Copy link");
    const devClose = btn("vf-btn vf-btn-ghost", "Done");
    devRow.append(devClose, devCopy);
    const devWarn = E("p", "vf-devwarn");
    devicePop.append(E("h2", "vf-pop-title", "Use on another device"), E("p", "vf-pop-note", "Scan this on your phone, or open the link in another browser. You stay the same person there, with your answers and votes."), qrBox, devField, devRow, devWarn);

    keysBtn.before(introBtn);
    root.append(top, body, tabs, fab, chat, pcard, settingsPop, sharePop, keysPop, introPop, editPop, personPop, PP.pop, RQ.pop, confirmPop, tiePop, proposePop, reportPop, myRepPop, askMenu, citePop, msgMenu, askPanel, devicePop,
      bellPop, moreSheet, mentionBox, reader, lb, toast, srLive, tour);

    // ---------- actions ----------
    function applyTheme() {
      const d = sessionTheme(), t = myTheme(), mode = t.mode || d.mode, accent = t.accent || d.accent;
      root.dataset.theme = mode === "system" ? (lightOS.matches ? "light" : "dark") : mode;
      root.dataset.accent = accent;
    }
    /** The Host view has no tab of its own on phones: More stands for it. */
    const paintTabs = () => { for (const [t, b] of Object.entries(tabBtns)) b.setAttribute("aria-current", t === (ui.tab === "host" ? "more" : ui.tab) ? "page" : "false"); };
    function setTab(k) {
      ui.tab = k; body.dataset.tab = k;
      paintTabs();
      if (k === "answer") setMode("focus"); else if (k === "compare" || k === "tree" || k === "host") setMode(k);
    }
    function setMode(m) {
      if (m === "host" && !Core.canModerate()) m = "focus";
      ui.mode = m; center.dataset.mode = m;
      for (const [k, b] of Object.entries(segBtns)) b.setAttribute("aria-pressed", String(k === m));
      if (phone.matches && ui.tab !== "questions") { ui.tab = m === "focus" ? "answer" : m; body.dataset.tab = ui.tab; paintTabs(); }
      render();
      if (m === "compare") requestAnimationFrame(() => { revealCol(ui.cur); edges(); });
    }
    function markSeen(qid) {
      if (!qid) return;
      ui.seen[qid] = Core.state.serverTime || Date.now() / 1000;
      store.put("vf-seen", ui.seen);
    }
    function select(qid, { manual = false } = {}) {
      if (manual && following() && Core.owner() && Core.owner().q !== qid) { setFollow(false); flash(`Stopped following ${disp(Core.owner().name)}.`); }
      if (qid === ui.cur) return;
      stopAdvance();
      closeSheet();
      if (ui.cur) { ui.drafts[ui.cur] = ta.value; ui.discDrafts.set(ui.cur, discTa.value); markSeen(ui.cur); }
      ui.cur = qid;
      discTa.value = ui.discDrafts.get(qid) ?? ""; grow(discTa);
      ui.seenAt = ui.seen[qid] ?? null;
      ta.value = ui.drafts[qid] ?? Core.myAnswer(qid);
      ui.dirty = qid in ui.drafts && ui.drafts[qid] !== Core.myAnswer(qid);
      ui.suggestOpen = false; ui.editFrom = null; ui.askOpen = false; sugForm.hidden = true; editForm.hidden = true;
      if (!(qid in ui.cites)) ui.cites[qid] = [...(myRec(qid)?.cites || [])];
      scroll.scrollTop = 0;
      Core.setFocus(qid);
      render();
      grow(ta);
      if (ui.mode === "compare") revealCol(qid);
    }
    /** Previous goes back one in round order; Next goes to the next question still open for me, else the next one. */
    function step(d) {
      const shown = shownQuestions().map(q => q.id);
      const ids = shown.length ? (shown.includes(ui.cur) ? shown : [ui.cur, ...shown]) : Core.state.questions.map(q => q.id), i = ids.indexOf(ui.cur);
      if (!ids.length) return;
      if (d > 0) {
        for (let j = 1; j < ids.length; j++) {
          const id = ids[(i + j) % ids.length];
          if (isOpenForMe(id)) return select(id, { manual: true });
        }
      }
      select(ids[(i + d + ids.length) % ids.length], { manual: true });
    }
    function stopAdvance() { clearTimeout(ADV.timer); ADV.timer = 0; ADV.qid = ""; advBar.hidden = true; }
    /** After my own single pick on the question in view: with the switch on, the comment box empty and another
     *  question still open for me, Next in 2 s. */
    function armAdvance(qid) {
      const q = qById(qid);
      if (!pref("autoAdvance", false) || ui.cur !== qid || !["choice", "confirm", "prototype", "scale"].includes(q?.format) || ta.value.trim()) return;
      if (!Core.state.questions.some(x => x.id !== qid && isOpenForMe(x.id))) return;
      stopAdvance();
      ADV.qid = qid; advBar.hidden = false;
      ADV.timer = setTimeout(() => { const go = ADV.qid === ui.cur; stopAdvance(); if (go) step(1); }, 2000);
    }
    advStay.onclick = () => { stopAdvance(); (ta.disabled ? qText : ta).focus({ preventScroll: true }); };
    function focusQuestion(qid) { select(qid, { manual: true }); setMode("focus"); if (phone.matches) setTab("answer"); }
    function setFollow(v) { setPrefs({ follow: v }); follow.setAttribute("aria-pressed", String(v)); render(); }
    const sameCites = qid => JSON.stringify(ui.cites[qid] || []) === JSON.stringify(myRec(qid)?.cites || []);
    async function submit() {
      const text = ta.value.trim(), qid = ui.cur, q = qById(qid), rec = myRec(qid);
      if (!qid || Core.lockOf(qid) || readOnly(q) || (text === Core.myAnswer(qid) && sameCites(qid) && sameAtt(qid))) return;
      sendBtn.disabled = true;
      const extra = attExtra(cSlot);
      try {
        // A question that takes a pick (or a poll): the text is a comment on my pick. Without a pick (or on confirm) it is my own answer.
        const fields = savedPick(q, rec);
        if (fields && (q.format === "choice" || isFormat(q) || q.purpose === "poll")) await Core.pickWith(qid, fields, { comment: text, ...extra });
        else await Core.answerCiting(qid, text, ui.cites[qid] || [], extra);
        delete ui.drafts[qid]; delete ui.attDraft[qid]; ui.dirty = false; ta.value = Core.myAnswer(qid); grow(ta);
        closeSheet();
        announce(fields && (q.format === "choice" || isFormat(q) || q.purpose === "poll") ? "Your comment is saved." : "Your answer is saved.");
        if (phone.matches) ta.blur(); // the one-line composer folds back once sent
      }
      catch (e) {
        if (e?.status) fail(e);
        else flash("Not saved: the session is out of reach. Your draft is kept; try again.");
      }
      finally { sendBtn.disabled = false; render(); }
    }
    function revealCol(qid) {
      const col = board._map?.get(qid);
      if (!col) return;
      // ux-review-2 #15: the first columns stay at the start when the current one fits; otherwise a slice of the
      // previous column stays in view, so it is plain that more columns are to the left.
      const fits = col.offsetLeft + col.offsetWidth <= board.clientWidth - 12;
      board.scrollTo({ left: fits ? 0 : Math.max(0, col.offsetLeft - 64), behavior: smooth() });
    }
    function edges() {
      const max = board.scrollWidth - board.clientWidth;
      const l = board.scrollLeft > 2, r = board.scrollLeft < max - 2;
      fadeL.classList.toggle("vf-on", l); arrL.hidden = !l;
      fadeR.classList.toggle("vf-on", r); arrR.hidden = !r;
      const hiddenCount = [...board.children].filter(c => c.offsetLeft >= board.scrollLeft + board.clientWidth - 8).length;
      arrRTxt.textContent = hiddenCount ? `${hiddenCount} more` : "";
    }
    const colStep = () => (board.firstChild?.offsetWidth || 300) + 12;

    /** Place a popover under its anchor (above when there is no room), inside the app. */
    function placeNear(pop, anchor) {
      const r = anchor.getBoundingClientRect(), R = root.getBoundingClientRect(), ps = pop.style;
      ps.insetBlockEnd = ps.maxBlockSize = ps.overflowY = ""; ps.insetInlineStart = "0px"; ps.insetBlockStart = "0px";
      const w = pop.offsetWidth, h = pop.offsetHeight;
      const left = Math.min(Math.max(8, r.left - R.left + r.width / 2 - w / 2), R.width - w - 8);
      // Below the anchor, else above it; when it fits neither, the roomier side, scrolling, so it never covers the anchor.
      const below = R.height - (r.bottom - R.top) - 16, above = r.top - R.top - 16;
      let topY = r.bottom - R.top + 8;
      if (h > below && h <= above) topY = r.top - R.top - h - 8;
      else if (h > below) {
        ps.maxBlockSize = Math.max(below, above) + "px"; ps.overflowY = "auto";
        topY = below >= above ? topY : 8;
      }
      ps.insetInlineStart = left + "px"; ps.insetBlockStart = topY + "px";
    }
    function openPop(pop, anchor) {
      closePop(); hideCard();
      ui.pop = pop; pop.hidden = false; pop._return = null;
      if (phone.matches && (pop === proposePop || pop === reportPop || pop === myRepPop)) pop.removeAttribute("style"); // a sheet: the stylesheet places it
      else placeNear(pop, anchor);
      anchor.setAttribute("aria-expanded", "true"); pop._anchor = anchor;
      render();
      (pop.querySelector("textarea, button, input") || pop).focus({ preventScroll: true });
    }
    function placePanel(pop) {
      const ps = pop.style;
      ps.insetInlineStart = ps.insetBlockStart = ps.insetBlockEnd = ps.inlineSize = ps.blockSize = "";
      pop.dataset.place = "sheet";
      if (phone.matches) return;
      const R = root.getBoundingClientRect(), rr = rail.getBoundingClientRect(), cr = center.getBoundingClientRect();
      const avail = R.right - rr.right - 24;
      if (avail >= 560) {
        pop.dataset.place = "side";
        ps.insetInlineStart = (rr.right - R.left + 8) + "px";
        ps.insetBlockEnd = Math.max(8, R.bottom - pop._anchor.getBoundingClientRect().bottom) + "px";
        ps.inlineSize = Math.min(720, avail) + "px";
      } else {
        pop.dataset.place = "center";
        ps.insetInlineStart = (cr.left - R.left) + "px"; ps.insetBlockStart = (cr.top - R.top) + "px";
        ps.inlineSize = cr.width + "px"; ps.blockSize = cr.height + "px";
      }
    }
    function openPanel(pop, anchor) {
      closePop(); hideCard();
      ui.pop = pop; pop._anchor = anchor; pop.hidden = false;
      anchor.setAttribute("aria-expanded", "true");
      if (pop === RQ.pop) ui.reqSeen = new Set((Core.state.requests || []).filter(r => r.status === "pending").map(r => r.id));
      placePanel(pop);
      render();
      syncModal();
      pop.querySelector("button")?.focus({ preventScroll: true });
    }
    function closePop() {
      if (!ui.pop) return;
      if (ui.pop === pcard) { ui.pcard = null; ui.renaming = false; }
      ui.pop.hidden = true; ui.pop._anchor?.setAttribute?.("aria-expanded", "false");
      ui.pop._kbRead = false; // the next open logs its keyboard readout again
      ui.pop = null;
      syncModal();
    }
    /** On a phone a chat or panel sheet covers the page: everything behind it goes inert, and Tab stays inside. */
    const activeSheet = () => (phone.matches ? (ui.chatOpen ? chat : ui.pop?.matches(".vf-panel, .vf-drawer, .vf-proposepop, .vf-reportpop, .vf-bellpop[data-place='sheet']") ? ui.pop : null) : null);
    function syncModal() {
      const sheet = activeSheet();
      for (const el of [top, body, tabs, fab]) el.inert = !!sheet;
      if (toast.classList.contains("vf-on")) placeToast(); // a chat or panel opened or closed under it
    }
    function setChat(open) {
      ui.chatOpen = open; chat.hidden = !open; fab.setAttribute("aria-expanded", String(open));
      fab.setAttribute("aria-label", open ? "Close chat" : "Open chat");
      // On a touch screen, focus goes to the close button, not the message box: focusing the box would raise the phone
      // keyboard before anyone asked to type. The keyboard comes up when the box is tapped.
      if (open) { ui.bumped = false; closePop(); render(); mScroll.scrollTop = mScroll.scrollHeight; (matchMedia("(pointer: coarse)").matches ? chatClose : mInput).focus({ preventScroll: true }); }
      else render();
      syncModal();
    }
    function openReader(title, meta, text, from) {
      rdTitle.textContent = title || "Full text";
      rdMeta.textContent = meta || ""; rdMeta.hidden = !meta;
      rdText._t = null; setRich(rdText, text);
      reader._from = from; reader.hidden = false; rdBody.scrollTop = 0;
      rdClose.focus({ preventScroll: true });
    }
    function closeReader() { reader.hidden = true; reader._from?.focus({ preventScroll: true }); }

    // ---------- picture viewer ----------
    // kind: "choice" (the question's option pictures), "confirm" (its screenshot), "ref" (its image references)
    // or "att" (the pictures attached to one answer, message, request or suggestion, passed in as items).
    const LB = { kind: null, qid: null, i: 0, s: 1, x: 0, y: 0, from: null, vKey: null, cur: null, items: null, meta: "" };
    const optCard = (qid, id) => Core.answersFor(qid).find(a => a.option && a.cid === id);
    const chose = n => (n ? `${n} ${n === 1 ? "person" : "people"} chose this` : "No picks yet");
    function lbItems() {
      if (LB.kind === "att") return LB.items || [];
      const q = qById(LB.qid);
      if (!q) return [];
      if (LB.kind === "choice") return optionsOf(q).filter(o => o.image).map(o => ({ asset: o.image, title: o.label, opt: o.id }));
      if (LB.kind === "confirm") return q.image ? [{ asset: q.image, title: "Did you mean this?", rect: q.rect || null }] : [];
      return (q.references || []).map(r => attAsset(r) && { asset: attAsset(r), title: r.caption || (r.upload ? Core.state.files?.[r.upload]?.file : "") || (r.kind === "diagram" ? "Diagram" : "Screenshot"),
        rect: r.rect, ...(r.kind === "diagram" ? { alt: r.alt } : {}) }).filter(Boolean);
    }
    function openLb(kind, qid, i, from, items = null, meta = "") {
      Object.assign(LB, { kind, qid, i: Math.max(0, i), from, vKey: null, cur: ui.cur, items, meta });
      lb.hidden = false; lbZoomTo(1); paintLb();
      lbClose.focus({ preventScroll: true });
    }
    function closeLb() {
      if (lb.hidden) return;
      lb.hidden = true; LB.kind = null;
      if (LB.from?.isConnected) LB.from.focus({ preventScroll: true });
    }
    function lbGo(d) {
      const n = lbItems().length;
      if (n < 2) return;
      LB.i = (LB.i + d + n) % n; LB.vKey = null; lbZoomTo(1); paintLb();
    }
    function paintLb() {
      const items = lbItems(), q = qById(LB.qid);
      if (!items.length || LB.cur !== ui.cur || (LB.kind !== "att" && !q)) return closeLb();
      LB.i = Math.min(LB.i, items.length - 1);
      const it = items[LB.i], many = items.length > 1;
      if (lbImg._src !== (it.src || it.asset)) { lbImg._src = it.src || it.asset; lbImg.src = it.src || assetUrl(it.asset); }
      lbImg.alt = it.alt || (it.rect ? `${it.title}, with the area in question marked` : it.title);
      lbFrame.classList.toggle("vf-lb-diagram", !!it.alt);
      markRect(lbMark, it.rect);
      lbTitle.textContent = it.title;
      lbMeta.textContent = LB.kind === "att" ? LB.meta : `${q.id}: ${q.text}`;
      lbMeta.hidden = !lbMeta.textContent;
      lbPrev.hidden = lbNext.hidden = !many;
      lbCount.textContent = many ? `Picture ${LB.i + 1} of ${items.length}` : ""; lbCount.hidden = !many;
      const rec = q && myRec(q.id), ro = !q || readOnly(q) || !!Core.lockOf(q.id);
      lbChoose.hidden = LB.kind !== "choice";
      lbYes.hidden = lbNo.hidden = LB.kind !== "confirm";
      lbUndo.hidden = true;
      let voters = [], picks = "";
      if (LB.kind === "choice") {
        const mine = rec?.pick === it.opt, votes = optCard(q.id, it.opt)?.votes || [];
        const label = mine ? "Your choice" : rec?.pick ? "Choose this instead" : "Choose this";
        if (lbChoose._mine !== mine) { lbChoose._mine = mine; lbChoose.replaceChildren(radioDot(), E("span")); }
        lbChoose.lastChild.textContent = label;
        lbChoose.setAttribute("aria-pressed", String(mine));
        lbChoose.setAttribute("aria-label", mine ? `Your choice: ${it.title}` : `${label}: ${it.title}`);
        lbChoose.disabled = ro;
        lbUndo.hidden = !mine || ro;
        if (!resultsWait(q)) { voters = votes; picks = chose(votes.length); }
      } else if (LB.kind === "confirm") {
        const n = id => optCard(q.id, id)?.votes?.length || 0;
        for (const [b, id] of [[lbYes, "opt-yes"], [lbNo, "opt-no"]]) { b.setAttribute("aria-pressed", String(rec?.pick === id)); b.disabled = ro; }
        lbUndo.hidden = !rec?.pick || ro;
        if (!resultsWait(q)) picks = `Yes ${n("opt-yes")}, No ${n("opt-no")}`;
      }
      const vk = (st().showNames ? voters.filter(Boolean) : []).join(",");
      if (LB.vKey !== vk) { LB.vKey = vk; avStack(lbVoters, (vk ? vk.split(",") : []).map(c => ({ cid: c, name: nameOf(c) })), 4, 20); }
      lbPicks.textContent = picks; lbPicks.hidden = !picks;
      lbInfo.hidden = !many && !picks;
      lbZoom.textContent = coarse.matches ? `Pinch or double-tap to zoom.${many ? " Swipe for the next picture." : ""}` : `Double-click to zoom.${many ? " Use ← and → for the next picture." : ""} Esc closes.`;
    }
    const coarse = matchMedia("(pointer: coarse)");
    // Zoom keeps the point under the finger or cursor in place; the frame is centered, so offsets are from the stage center.
    function lbApply() {
      const fw = lbFrame.offsetWidth * LB.s, fh = lbFrame.offsetHeight * LB.s;
      const mx = Math.max(0, (fw - lbStage.clientWidth) / 2), my = Math.max(0, (fh - lbStage.clientHeight) / 2);
      LB.x = Math.min(mx, Math.max(-mx, LB.x)); LB.y = Math.min(my, Math.max(-my, LB.y));
      lbFrame.style.transform = LB.s === 1 ? "" : `translate(${LB.x}px, ${LB.y}px) scale(${LB.s})`;
      lb.classList.toggle("vf-lb-zoomed", LB.s > 1);
    }
    function lbZoomTo(s, cx = 0, cy = 0) {
      s = Math.min(5, Math.max(1, s));
      if (s === 1) LB.x = LB.y = 0;
      else { LB.x = cx - (cx - LB.x) * s / LB.s; LB.y = cy - (cy - LB.y) * s / LB.s; }
      LB.s = s; lbApply();
    }
    const fromCenter = (x, y) => { const r = lbStage.getBoundingClientRect(); return [x - r.left - r.width / 2, y - r.top - r.height / 2]; };
    const ptrs = new Map();
    let pinch = null, drag = null, lastTap = 0;
    on(lbStage, "pointerdown", e => {
      if (e.target.closest(".vf-lb-nav") || (e.pointerType === "mouse" && e.button !== 0)) return;
      try { lbStage.setPointerCapture(e.pointerId); } catch { /* pointer already gone */ }
      ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (ptrs.size === 2) { const [a, b] = [...ptrs.values()]; pinch = { d: Math.hypot(a.x - b.x, a.y - b.y) || 1, s: LB.s }; drag = null; }
      else if (ptrs.size === 1) drag = { x: e.clientX, y: e.clientY, tx: LB.x, ty: LB.y, t: Date.now() };
    });
    on(lbStage, "pointermove", e => {
      if (!ptrs.has(e.pointerId)) return;
      ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pinch && ptrs.size === 2) {
        const [a, b] = [...ptrs.values()];
        lbZoomTo(pinch.s * Math.hypot(a.x - b.x, a.y - b.y) / pinch.d, ...fromCenter((a.x + b.x) / 2, (a.y + b.y) / 2));
      } else if (drag && LB.s > 1) { LB.x = drag.tx + e.clientX - drag.x; LB.y = drag.ty + e.clientY - drag.y; lbApply(); }
    });
    const lbUp = e => {
      if (!ptrs.delete(e.pointerId)) return;
      if (ptrs.size < 2) pinch = null;
      if (!drag || ptrs.size) return;
      const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (e.type === "pointerup" && LB.s === 1 && Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) lbGo(dx < 0 ? 1 : -1);
      else if (e.type === "pointerup" && Date.now() - drag.t < 300 && Math.hypot(dx, dy) < 10) { // two quick taps toggle zoom
        if (Date.now() - lastTap < 350) { lastTap = 0; LB.s > 1 ? lbZoomTo(1) : lbZoomTo(2.5, ...fromCenter(e.clientX, e.clientY)); }
        else lastTap = Date.now();
      }
      drag = null;
    };
    on(lbStage, "pointerup", lbUp); on(lbStage, "pointercancel", lbUp);
    on(lbStage, "wheel", e => {
      if (e.ctrlKey) lbZoomTo(LB.s * Math.exp(-e.deltaY / 100), ...fromCenter(e.clientX, e.clientY)); // trackpad pinch
      else if (LB.s > 1) { LB.x -= e.deltaX; LB.y -= e.deltaY; lbApply(); }
      else return;
      e.preventDefault();
    }, { passive: false });
    on(lb, "keydown", e => {
      if (e.key === "Escape") closeLb();
      else if (e.key === "ArrowLeft" || e.key === "ArrowRight") lbGo(e.key === "ArrowLeft" ? -1 : 1);
      else if (e.key === "+" || e.key === "=") lbZoomTo(LB.s * 1.5);
      else if (e.key === "-") lbZoomTo(LB.s / 1.5);
      else if (e.key === "0") lbZoomTo(1);
      else if (e.key === "Tab") { // keep Tab inside the viewer
        const f = [...lb.querySelectorAll("button")].filter(b => !b.disabled && b.offsetParent);
        const i = f.indexOf(document.activeElement), last = f.length - 1;
        if (e.shiftKey && i <= 0) f[last]?.focus(); else if (!e.shiftKey && (i === last || i < 0)) f[0]?.focus(); else return e.stopPropagation();
      } else return;
      e.preventDefault(); e.stopPropagation();
    });
    lbClose.onclick = closeLb;
    lbPrev.onclick = () => lbGo(-1);
    lbNext.onclick = () => lbGo(1);
    lbChoose.onclick = () => { const it = lbItems()[LB.i]; if (it?.opt) pickOpt(it.opt, LB.qid); };
    lbYes.onclick = () => pickOpt("opt-yes", LB.qid);
    lbNo.onclick = () => pickOpt("opt-no", LB.qid);
    lbUndo.onclick = () => { (LB.kind === "choice" ? lbChoose : lbYes).focus({ preventScroll: true }); clearPick(LB.qid); };
    on(window, "resize", () => { if (!lb.hidden) lbApply(); });
    function sendRound(anchor) {
      const n = curRound().current;
      const open = Core.state.questions.filter(q => roundOf(q) === n && !Core.lockOf(q.id)).length;
      if (!open) return doSend();
      const props = Core.state.ideas.filter(i => i.status === "new").length;
      confirmTxt.textContent = `${open} question${open > 1 ? "s are" : " is"} still open in round ${n}. Send anyway?${props ? ` ${props} pending proposal${props > 1 ? "s go" : " goes"} along.` : ""}`;
      openPop(confirmPop, anchor);
    }
    function doSend() { closePop(); Core.sendRound().catch(fail); }
    /** The round button: the owner sends (with a confirm if questions are open); a leader marks the round ready. */
    function roundAction(anchor) {
      if (!Core.me.isOwner) {
        const on = !curRound().ready;
        return Core.markReady(on).then(() => flash(on ? "Marked ready. The host sends it to Claude." : "No longer marked ready.")).catch(fail);
      }
      return ui.pop === confirmPop ? closePop() : sendRound(anchor);
    }
    function lockTopAnswer() {
      Core.lock(ui.cur).catch(e => {
        if (e?.error !== "tie") return fail(e);
        const by = Object.fromEntries(Core.answersFor(ui.cur).map(a => [a.cid, a]));
        tieList.replaceChildren(...e.tied.filter(c => by[c]).map(c => {
          const a = by[c], li = E("li", "vf-tieitem");
          const who = a.claude ? (a.rec ? "Claude, recommended" : "Claude") : disp(a.name);
          const pickB = btn("vf-btn vf-btn-brass vf-btn-sm", "Lock this one");
          pickB.setAttribute("aria-label", `Lock the answer from ${who}`);
          pickB.onclick = () => { closePop(); Core.lock(ui.cur, c).then(() => flash("Locked.")).catch(fail); };
          li.append(E("span", "vf-card-name", who), (() => { const t = clampBox("vf-tietxt"); fillClamp(t, "tie:" + c, a.text, `Answer from ${who}`, ""); return t; })(), pickB);
          return li;
        }));
        openPop(tiePop, lockBtn);
      });
    }
    function typingNow() {
      const a = document.activeElement;
      return !!a && root.contains(a) && a.matches("textarea, input:not([readonly])") && !a.disabled;
    }
    /** The spring plays once per closed period; later messages only pop the badge. */
    function bumpFab() {
      const cls = ui.bumped ? "vf-badge-pop" : "vf-bump";
      ui.bumped = true;
      fab.classList.remove("vf-bump", "vf-badge-pop");
      void fab.offsetWidth; // restart the animation
      fab.classList.add(cls);
    }
    async function sendChat() {
      const text = mInput.value.trim(); if (!text) return;
      // The message shows at once and the box empties; a refusal puts the text back.
      const reply = ui.replyTo, sent = Core.chat(text, reply?.id, attExtra(chatSlot));
      mInput.value = ""; mCount.textContent = ""; grow(mInput); mScroll.scrollTop = mScroll.scrollHeight;
      ui.replyTo = null; paintReply();
      try {
        const j = await sent;
        chatSlot.clear();
        if (j?.request) flash(Core.me.isOwner ? "Sent, and sent to Claude. Its answer replies here." : "Sent, and sent to Claude. It runs once the host presses Run.");
        else if (j?.requestRefused) flash(j.message);
      } catch (e) {
        if (!mInput.value) {
          mInput.value = text; grow(mInput);
          if (reply && e?.status !== 404 && !ui.replyTo) { ui.replyTo = reply; paintReply(); }
        }
        fail(e);
      }
    }
    function startTitleEdit() {
      titleInput.value = Core.state.title || "Interview";
      titleInput.hidden = false; titleTxt.hidden = true; titleEdit.hidden = true;
      titleInput.focus(); titleInput.select();
    }
    function endTitleEdit(save) {
      if (titleInput.hidden) return;
      const v = titleInput.value.trim();
      titleInput.hidden = true; titleTxt.hidden = false; titleEdit.hidden = false;
      if (save && v && v !== (Core.state.title || "Interview")) Core.setTitle(v).then(() => flash("Title saved.")).catch(fail);
      render();
    }

    // ---------- goal ----------
    function startGoalEdit() {
      goalInput.value = Core.state.goal || "";
      ui.goalEditing = true; render();
      goalInput.focus(); goalInput.select();
    }
    function endGoalEdit(save) {
      if (!ui.goalEditing) return;
      ui.goalEditing = false;
      const v = goalInput.value.trim();
      if (save && v !== (Core.state.goal || "")) Core.setGoal(v).then(() => flash(v ? "Goal saved." : "Goal cleared.")).catch(fail);
      render();
    }

    // ---------- Ask Claude panel ----------
    function openAskPanel(mode, qid, text) {
      if (mode) ui.askMode = mode;
      ui.askQ = qid || ui.cur;
      if (text != null) apTa.value = text;
      closePop(); hideCard();
      if (ui.chatOpen) setChat(false);
      ui.pop = askPanel; askPanel._anchor = askTop; askPanel.hidden = false;
      askTop.setAttribute("aria-expanded", "true");
      render(); syncModal();
      grow(apTa);
      apTa.focus({ preventScroll: true });
      if (text) apTa.setSelectionRange(apTa.value.length, apTa.value.length);
    }
    apClose.onclick = () => { closePop(); askTop.focus(); };
    askTop.onclick = () => (ui.pop === askPanel ? closePop() : openAskPanel());
    apForm.onsubmit = e => {
      e.preventDefault();
      const text = apTa.value.trim(); if (!text) return apTa.focus();
      const mode = guestKind(ui.askMode, ui.apWeb), qid = apQWrap.s.value || ui.cur || Core.GENERAL, own = selfAsk();
      apSend.disabled = true;
      Core.request(qid, mode, text, attExtra(apSlot), own ? "self" : "host").then(() => {
        apTa.value = ""; grow(apTa); apSlot.clear(); ui.apWeb = false;
        flash(own ? "Added to your requests. Run it on your own Claude from there."
          : Core.me.isOwner ? `Sent to Claude. The answer shows ${qid === Core.GENERAL ? genWhere() : "on the question"} and in your Inbox.` : "Sent to the host. It runs once they press Run.");
        render();
      }).catch(fail).finally(() => { apSend.disabled = false; });
    };
    on(apTa, "keydown", e => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); apForm.requestSubmit(); } });

    // ---------- Connect your Claude (R2-12, AC 70) ----------
    // A guest's `runner: self` request runs on their own Claude: a watcher in Claude Code or Desktop's Code tab, or one
    // prompt copied (or opened in Desktop chat) with the answer pasted back. Prompts and links come from connect.js.
    const askGeneral = () => (apQWrap.s.value || ui.askQ) === Core.GENERAL;
    /** The kind a request goes as: the owner's pick, else ask, or research with "Use the web" on. */
    const guestKind = (picked, web) => (Core.me.isOwner ? picked : web ? "research" : "ask");
    const selfAsk = () => !Core.me.isOwner && !!ui.askSelf && !askGeneral(); // a general ask runs on the host's Claude only
    const sessionBase = () => location.origin; // the address this guest reaches the session at; their Claude runs beside them
    async function copyOut(text, done, title, from) {
      try { await navigator.clipboard.writeText(text); flash(done); }
      catch { openReader(title, "Select it and copy it.", text, from); }
    }
    apcCopyW.onclick = () => copyOut(Connect.watcherPrompt(sessionBase()), "Watch prompt copied. Paste it into Claude Code; it asks for your watcher key.", "Watch prompt", apcCopyW);
    // A fresh watcher key per copy: it only reads and answers my own requests, and my session secret stays on this page.
    apcKey.onclick = () => Core.newWatcherKey()
      .then(key => copyOut(key, "Watcher key copied. It replaces any earlier one; paste it only into your own Claude.", "Your watcher key", apcKey)).catch(fail);
    apcRevoke.onclick = () => Core.revokeWatcher().then(() => flash("Watcher key revoked. Your Claude can no longer read your requests.")).catch(fail);
    let selfSeq = 0;
    /** Copy prompt, Open in Claude Desktop, Paste answer and Cancel for one of my own self requests. */
    function makeSelfActs() {
      const box = E("div", "vf-selfacts"), row = E("div", "vf-acts");
      const copyP = lbtn("vf-btn vf-btn-ghost vf-btn-sm vf-self-copy", "doc", "Copy prompt");
      const chat = E("a", "vf-btn vf-btn-ghost vf-btn-sm vf-self-chat", "Open in Claude Desktop");
      const paste = lbtn("vf-btn vf-btn-primary vf-btn-sm vf-self-paste", "reply", "Paste answer");
      const cancel = btn("vf-btn vf-btn-ghost vf-btn-sm vf-self-cancel", "Cancel request");
      row.append(copyP, chat, paste, cancel);
      const form = E("form", "vf-selfform"); form.hidden = true;
      const ta = E("textarea", "vf-ta"); ta.rows = 5; ta.id = `vf-self-ta-${++selfSeq}`;
      const lab = E("label", "vf-asklabel", "Your Claude's answer"); lab.htmlFor = ta.id;
      const post = E("button", "vf-btn vf-btn-primary vf-btn-sm", "Post answer"); post.type = "submit";
      const notNow = btn("vf-btn vf-btn-ghost vf-btn-sm", "Not now");
      const frow = E("div", "vf-acts"); frow.append(post, notNow);
      form.append(lab, ta, E("p", "vf-meta", "Sources on the last lines, as \"Title - https://...\", show as links. Only you and the host see the answer until the host shares it."), frow);
      box.append(row, form);
      const prompt = () => Connect.requestPrompt({ qid: box._q.id, question: box._q.text, kind: box._r.kind, text: box._r.text });
      copyP.onclick = () => copyOut(prompt(), "Prompt copied. Paste it into your Claude, then paste its answer back here.", "Prompt for your Claude", copyP);
      paste.onclick = () => { form.hidden = false; ta.focus(); };
      notNow.onclick = () => { form.hidden = true; paste.focus(); };
      cancel.onclick = guarded({ title: "Cancel this request?", ok: "Cancel request", body: "It stays in your list as failed. Nobody else saw it." },
        () => Core.myFail(box._r.id, "Cancelled by me.").then(() => flash("Request cancelled.")).catch(fail));
      form.onsubmit = e => {
        e.preventDefault();
        const { summary, sources } = Connect.parseReply(ta.value), r = box._r;
        if (!summary) { flash("Paste your Claude's answer first."); return ta.focus(); }
        if (summary.length > Connect.MAX_SUMMARY) { flash(`Shorten it to ${Connect.MAX_SUMMARY} characters; it has ${summary.length}.`); return ta.focus(); }
        post.disabled = true;
        (r.status === "pending" ? Core.myClaim(r.id) : Promise.resolve())
          .then(() => Core.myResult(r.id, { summary, sources, report: "", used: [], why: "Pasted back from my own Claude." }))
          .then(() => { ta.value = ""; form.hidden = true; flash("Posted. Only you and the host see this until the host shares it."); })
          .catch(fail).finally(() => { post.disabled = false; });
      };
      box._k = { chat, form };
      return box;
    }
    function fillSelfActs(box, r, q) {
      const open = !!q && (r.status === "pending" || r.status === "running");
      box.hidden = !open;
      if (!open) { box._k.form.hidden = true; return; }
      box._r = r; box._q = q;
      const href = Connect.link("desktopChat", Connect.requestPrompt({ qid: q.id, question: q.text, kind: r.kind, text: r.text }));
      box._k.chat.hidden = !href;
      if (href) box._k.chat.href = href;
    }

    // ---------- Phase 4c: chat reactions ----------
    const reactPop = E("div", "vf-pop vf-reactpop"); reactPop.setAttribute("role", "dialog"); reactPop.setAttribute("aria-label", "Add a reaction"); reactPop.hidden = true;
    const rpQuick = E("div", "vf-rp-quick"); rpQuick.setAttribute("role", "group"); rpQuick.setAttribute("aria-label", "Quick reactions");
    const rpMore = btn("vf-btn vf-btn-ghost vf-btn-sm vf-rp-more", "More"); rpMore.setAttribute("aria-expanded", "false");
    const rpGrid = E("div", "vf-rp-grid"); rpGrid.setAttribute("role", "group"); rpGrid.setAttribute("aria-label", "More reactions"); rpGrid.hidden = true;
    const emojiBtn = e => {
      const b = btn("vf-rp-e", e); b.dataset.e = e; b.setAttribute("aria-label", `React with ${e}`);
      b.onclick = () => {
        const m = ui.reactMsg; if (!m) return;
        const mine = (m.reactions?.[e] || []).includes(Core.me.cid);
        closePop(); (ui.reactFn || Core.chatReact)(m.id, e, !mine).catch(fail);
      };
      return b;
    };
    rpQuick.append(...QUICK_EMOJI.map(emojiBtn), rpMore);
    rpGrid.append(...CHAT_EMOJI.slice(QUICK_EMOJI.length).map(emojiBtn));
    rpMore.onclick = () => { rpGrid.hidden = !rpGrid.hidden; rpMore.setAttribute("aria-expanded", String(!rpGrid.hidden)); if (!rpGrid.hidden) rpGrid.firstChild.focus(); };
    reactPop.append(rpQuick, rpGrid);
    root.append(reactPop);
    /** react(id, emoji, on): a Discussion comment passes its own; a chat message uses Core.chatReact. */
    function openReactPop(m, anchor, react = null) {
      if (!m) return;
      ui.reactMsg = m; ui.reactFn = react; rpGrid.hidden = true; rpMore.setAttribute("aria-expanded", "false");
      for (const b of reactPop.querySelectorAll(".vf-rp-e")) b.setAttribute("aria-pressed", String((m.reactions?.[b.dataset.e] || []).includes(Core.me.cid)));
      openPop(reactPop, anchor);
    }
    const cantReact = () => (!!Core.state.ended && !Core.me.isOwner) || !!Core.state.youRemoved;
    /** A message's reaction chips: emoji, count and who (as Show names allows); a tap adds or takes back mine. */
    function fillReactChips(k, m, react = Core.chatReact) {
      const entries = Object.entries(m.reactions || {});
      const sig = JSON.stringify(entries) + Core.me.cid + st().showNames;
      k.reactAdd.hidden = cantReact();
      k.reactRow.hidden = !entries.length;
      if (k.reactRow._sig === sig) return;
      k.reactRow._sig = sig;
      k.reactRow.replaceChildren(...entries.map(([e, pids]) => {
        const mine = pids.includes(Core.me.cid), b = btn("vf-mreact");
        b.append(E("span", "vf-mreact-e", e), E("span", "vf-mreact-n", String(pids.length)));
        const who = pids.map(p => (isMe(p) ? "you" : p ? disp(nameOf(p)) : "someone"));
        b.setAttribute("aria-pressed", String(mine));
        b.setAttribute("aria-label", `${e} ${pids.length}, from ${who.join(", ")}. ${mine ? "Take yours back" : "Add yours"}`);
        b.title = who.join(", ");
        b.onclick = () => react(m.id, e, !mine).catch(fail);
        return b;
      }));
    }

    // ---------- chat message menu ----------
    function openMsgMenu(m, anchor) {
      if (!m) return;
      ui.msgMenu = m;
      mmPropose.hidden = !!m.forwarded || !!m.claude || (!!Core.state.ended && !Core.me.isOwner) || !!Core.state.youRemoved;
      mmReact.hidden = cantReact();
      openPop(msgMenu, anchor);
    }
    mmReact.onclick = () => { const m = ui.msgMenu, at = msgMenu._anchor; closePop(); if (m && at) openReactPop(m, at); };
    // A moderator forwards the message itself (it shows as proposed in the chat); anyone else gets the Propose form
    // with its text, to edit before sending.
    mmPropose.onclick = () => {
      const m = ui.msgMenu; closePop(); if (!m) return;
      if (!Core.canModerate()) return openPropose(m.text);
      Core.forward(m.id).then(() => flash("Added to Proposed.")).catch(fail);
    };
    mmAsk.onclick = () => {
      const m = ui.msgMenu; closePop(); if (!m) return;
      openAskPanel("ask", ui.cur, `About this chat message from ${isMe(m.cid) ? "me" : disp(m.name)}: "${m.text}"\n\n`);
    };
    mmCopy.onclick = async () => {
      const m = ui.msgMenu; closePop(); if (!m) return;
      try { await navigator.clipboard.writeText(m.text); flash("Copied."); } catch { flash("Could not copy here. Select the text and copy it instead."); }
    };
    mmReply.onclick = () => { const m = ui.msgMenu; closePop(); if (!m) return; ui.replyTo = m; paintReply(); mInput.focus(); };
    function paintReply() {
      const m = ui.replyTo; mReply.hidden = !m;
      if (m) mReplyTxt.textContent = `Replying to ${isMe(m.cid) ? "yourself" : disp(m.name)}: ${m.text.replace(/\s+/g, " ").slice(0, 120)}`;
    }
    mReplyX.onclick = () => { ui.replyTo = null; paintReply(); mInput.focus(); };

    /** A marked area in percent over an image, clamped inside it (a rect stored before the server checked the unit
     *  can be pixel-sized); none hides the mark. Returns the area drawn. */
    function markRect(el, r) {
      el.hidden = !r;
      if (!r) return null;
      const n = v => Math.max(0, Number(v) || 0), w = Math.min(n(r.w), 100), h = Math.min(n(r.h), 100);
      const c = { x: Math.min(n(r.x), 100 - w), y: Math.min(n(r.y), 100 - h), w, h };
      el.style.cssText = `inset-inline-start:${c.x}%;inset-block-start:${c.y}%;inline-size:${c.w}%;block-size:${c.h}%`;
      return c;
    }

    // ---------- Q87: theme, one tap cycles System, Light, Dark ----------
    const THEME_NEXT = { system: "light", light: "dark", dark: "system" }, THEME_LABEL = { system: "System", light: "Light", dark: "Dark" };
    const myMode = () => myTheme().mode || sessionTheme().mode || "system";
    function cycleTheme() {
      const next = THEME_NEXT[myMode()] || "system";
      setPrefs({ theme: next }); applyTheme(); render();
      announce(`Theme: ${THEME_LABEL[next]}${next === "system" ? ", following this device" : ""}.`);
    }
    function paintTheme() {
      const m = myMode();
      if (themeBtn._m !== m) { themeBtn._m = m; themeBtn.replaceChildren(icon(m === "light" ? "sun" : m === "dark" ? "moon" : "system")); }
      const label = `Theme: ${THEME_LABEL[m]}. Switch to ${THEME_LABEL[THEME_NEXT[m]]}`;
      themeBtn.setAttribute("aria-label", label); themeBtn.title = label;
      msTheme._d.textContent = `${THEME_LABEL[m]}, tap for ${THEME_LABEL[THEME_NEXT[m]]}`;
    }
    themeBtn.onclick = cycleTheme;

    // ---------- Q82: the bell ----------
    const notes = () => Core.state.me?.notifications || [];
    const KIND_ICON = Object.fromEntries(NOTE_KINDS.map(([k, , i]) => [k, i]));
    /** On a phone the bell opens as a bottom sheet; on wider screens it drops from its button. */
    function openBell(anchor) {
      if (ui.pop === bellPop) return closePop();
      ui.muteOpen = false;
      openPop(bellPop, anchor);
      if (phone.matches) { bellPop.style.cssText = ""; bellPop.dataset.place = "sheet"; } else delete bellPop.dataset.place;
      syncModal();
    }
    function goNote(n) {
      closePop();
      if (!n.read) Core.readNotifications([n.id]).catch(() => {});
      if (n.comment && n.qid && qById(n.qid)) return openComment(n.qid, n.comment);
      if (n.msg && st().chat) {
        setChat(true);
        goMsg(n.msg);
        return;
      }
      if (n.qid && qById(n.qid)) return focusQuestion(n.qid);
      if ((n.kind === "queue" || n.kind === "ready") && Core.canModerate()) { setMode("host"); if (phone.matches) setTab("host"); }
    }
    // ---------- Item 11: the Inbox ----------
    const inbox = () => Core.state.inbox || [];
    const IX_STAT = { waiting: "Waiting", running: "Running", answered: "Answered", unshared: "Answered", shared: "Shared", declined: "Declined", failed: "Failed" };
    /** A count that is news: unread Inbox items, plus unread notifications other than a request's own notices, which
     *  are its items. The queue line counts only what has no item: proposals, suggestions and offers. */
    function inboxUnread() {
      return inbox().filter(i => i.unread).length + notes().filter(n => !n.read && n.kind !== "request").length;
    }
    const qLabel = qid => { const q = qById(qid); return q ? `${q.id} · ${q.text}` : qid || ""; };
    /** A request about the whole session has no question: it shows under this label, and opens in Ask Claude or chat. */
    const GEN_LABEL = "General", GEN_Q = { id: GEN_LABEL, text: "about the whole session" };
    const ixWhere = i => (i.qid ? `on ${i.qid}` : "about the session");
    /** Where everyone reads a shared general answer: chat, or with chat off only Ask Claude's General list. */
    const genWhere = () => (Core.state.settings?.chat ? "in chat" : "in Ask Claude, About the whole session");
    /** The request a chat message's @Claude filed, as this viewer knows it, as discReq does for a comment. */
    function genReq(S, rid) {
      const x = (S.research?.[Core.GENERAL] || []).find(r => r.requestId === rid);
      const r = (Core.me.isOwner ? S.requests || [] : []).concat(S.myRequests || []).find(r2 => r2.id === rid);
      return { x, r, label: x ? (x.published === false ? "Answered, waiting for the host to share" : "Answered") : r ? rstat(r) : "" };
    }
    /** Ask Claude on "About the whole session", with one answer ("x:<id>") or request ("r:<id>") of it in view. */
    function openGeneral(key) {
      if (key?.startsWith("x:")) ui.resClosed.delete(key.slice(2));
      openAskPanel(null, Core.GENERAL);
      requestAnimationFrame(() => {
        const li = (key?.startsWith("x:") ? apGen : apReqs)._map?.get(key.startsWith("x:") ? key : key.slice(2)); if (!li) return;
        li.scrollIntoView({ block: "nearest", behavior: smooth() });
        ring(li);
      });
    }
    /** My request, open: its answer when I can see it, else its card, in that question's Claude section. */
    function showRequest(qid, rid) {
      ui.clOpen.set(qid, true);
      if (ui.cur !== qid) select(qid, { manual: true });
      setMode("focus"); if (phone.matches) setTab("answer");
      render();
      requestAnimationFrame(() => {
        const li = thList._map?.get("r:" + rid); if (!li) return;
        li.scrollIntoView({ block: "nearest", behavior: smooth() });
        ring(li);
      });
    }
    function openInboxItem(i) {
      closePop();
      if (i.unread) Core.readInbox([i.key], { [i.key]: i.status }).catch(() => {});
      const host = () => { setMode("host"); if (phone.matches) setTab("host"); };
      if (!i.qid && i.scope) { // about the whole session: a shared answer is in chat, the rest in Ask Claude
        const xid = i.kind === "share" ? i.id : i.result, x = xid && (Core.state.research?.[Core.GENERAL] || []).find(y => y.id === xid);
        if (x?.msg && x.published !== false && st().chat) { setChat(true); return goMsg(x.msg, () => openGeneral("x:" + xid)); } // a message chat dropped: the answer is still in Ask Claude
        if (i.kind === "run") return host();
        return openGeneral(xid ? "x:" + xid : "r:" + i.id);
      }
      if (i.kind === "request" || i.kind === "run") {
        if (!qById(i.qid)) return;
        if (i.result) { setMode("focus"); if (phone.matches) setTab("answer"); return showResult(i.qid, i.result); }
        return showRequest(i.qid, i.id);
      }
      if (i.kind === "share" && qById(i.qid)) { setMode("focus"); if (phone.matches) setTab("answer"); return showResult(i.qid, i.id); }
      host();
    }
    /** One Inbox row: the question, what was asked or what waits, a status chip, when, and an unread dot. */
    function makeIx() {
      const li = E("li"), b = btn("vf-ixitem");
      const q = E("span", "vf-ixq"), chip = E("span", "vf-chip vf-ixchip"), what = E("span", "vf-ixwhat"), sub = E("span", "vf-ixsub"), tm = E("span", "vf-card-time vf-ixtime"), dot = E("span", "vf-ndot");
      b.append(q, chip, what, tm, sub, dot); li.append(b);
      b.onclick = () => openInboxItem(li._i);
      li._k = { b, q, chip, what, sub, tm, dot };
      return li;
    }
    function ixText(i, S) {
      if (i.kind === "request") return (S.myRequests || []).find(r => r.id === i.id)?.text || "";
      if (i.kind === "run") { const r = (S.requests || []).find(x => x.id === i.id); return r ? `${disp(i.by || r.name)}: ${r.text}` : ""; }
      if (i.kind === "share") { const x = (S.research?.[i.qid || Core.GENERAL] || []).find(y => y.id === i.id); return x ? x.summary : "A result"; }
      if (i.kind === "report") { const f = (S.reports || []).find(y => y.id === i.id); return f ? `${disp(i.by || f.name)}: ${f.text}` : "A problem report"; }
      if (i.kind === "merge") { const m = (S.mergeRequests || []).find(y => y.id === i.id); return m ? `${disp(m.fromName)} says they were ${disp(m.toName)} before` : "A merge request"; }
      if (i.kind === "join") return `${disp(i.by || "Someone")} asks to join`;
      return "";
    }
    function fillIx(li, i, S) {
      const k = li._k; li._i = i;
      const mine = i.group === "mine";
      k.q.textContent = i.qid ? qLabel(i.qid) : i.scope ? GEN_LABEL : ""; k.q.hidden = !i.qid && !i.scope;
      k.q.classList.toggle("vf-ixgen", !i.qid && !!i.scope);
      k.chip.hidden = !mine;
      if (mine) { k.chip.textContent = IX_STAT[i.status] || i.status; k.chip.dataset.stat = i.status; }
      k.what.textContent = ixText(i, S);
      const sub = i.status === "unshared" ? "Waiting for the host to share" : i.status === "failed" ? i.reason || "" : i.status === "answered" && !Core.me.isOwner ? "Only you see it until the host shares it" : "";
      k.sub.textContent = sub; k.sub.hidden = !sub;
      k.tm.textContent = ago(mine ? i.changedTs : i.ts);
      k.dot.hidden = !i.unread;
      k.b.classList.toggle("vf-nunread", !!i.unread);
      li.dataset.key = i.key; li.dataset.stat = i.status;
      const where = i.qid ? `${i.qid}. ` : i.scope ? `${GEN_LABEL}. ` : "";
      k.b.setAttribute("aria-label", `${i.unread ? "Unread. " : ""}${where}${k.what.textContent}. ${mine ? (i.status === "unshared" ? "Answered, waiting for the host to share" : IX_STAT[i.status]) + (sub && i.status !== "unshared" ? `: ${sub}` : "") + ". " : ""}${k.tm.textContent === "now" ? "Just now" : k.tm.textContent + " ago"}.`);
    }
    bellBtn.onclick = () => openBell(bellBtn);
    bpClose.onclick = () => { const a = bellPop._anchor; closePop(); a?.focus?.(); };
    bpAll.onclick = () => {
      const items = inbox().filter(i => i.unread);
      for (let n = 0; n < items.length; n += 100) { // the server takes 100 a read
        const part = items.slice(n, n + 100);
        Core.readInbox(part.map(i => i.key), Object.fromEntries(part.map(i => [i.key, i.status]))).catch(fail);
      }
      if (notes().some(n => !n.read)) Core.readNotifications("all").catch(fail);
    };
    muteBtn.onclick = () => { ui.muteOpen = !ui.muteOpen; render(); if (ui.muteOpen) muteBox.scrollIntoView({ block: "nearest", behavior: smooth() }); };
    function renderBell(S, mod) {
      const list = notes().slice().reverse(), unread = inboxUnread();
      bellBadge.textContent = unread ? String(unread > 99 ? "99+" : unread) : "";
      if (unread > (ui.lastBell ?? unread)) { bellBadge.classList.remove("vf-badge-pop"); void bellBadge.offsetWidth; bellBadge.classList.add("vf-badge-pop"); }
      ui.lastBell = unread;
      bellBtn.setAttribute("aria-label", unread ? `Inbox, ${unread} unread` : "Inbox");
      bellBtn.title = bellBtn.getAttribute("aria-label");
      bellBtn.hidden = !S.me;
      tabBtns.more._badge.textContent = ""; // ux-review-2 #8: a notification is badged once, on the Inbox
      msBell._d.textContent = unread ? `${unread} unread` : "All read";
      if (ui.pop !== bellPop) return;
      bpAll.hidden = !unread;
      ixCount.textContent = unread ? String(unread) : ""; ixCount.hidden = !unread;
      const owner = Core.me.isOwner, tab = ui.ixTab === "waiting" && !owner ? "all" : ui.ixTab || "all";
      ixTabBtn.waiting.hidden = !owner;
      for (const [k, b] of Object.entries(ixTabBtn)) b.setAttribute("aria-pressed", String(k === tab));
      const mine = inbox().filter(i => i.group === "mine").sort((a, b) => b.ts - a.ts);
      const waiting = owner ? inbox().filter(i => i.group === "waiting").sort((a, b) => b.ts - a.ts) : [];
      ixMine.hidden = !(tab === "all" || tab === "mine");
      ixWait.hidden = !owner || !(tab === "all" || tab === "waiting");
      ixNotes.hidden = !(tab === "all" || tab === "notes");
      ixMine._h.textContent = `${ixMine._title} · ${mine.length}`;
      ixWait._h.textContent = `${ixWait._title} · ${waiting.length}`;
      ixNotes._h.textContent = ixNotes._title;
      sync(ixMineList, mine, i => i.key, makeIx, (li, i) => fillIx(li, i, S));
      ixMineEmpty.hidden = mine.length > 0;
      for (const [k, w] of Object.entries(ixWaitLists)) {
        const items = waiting.filter(i => i.kind === k);
        w.h.textContent = `${w.label} · ${items.length}`;
        w.g.hidden = !items.length;
        sync(w.ul, items, i => i.key, makeIx, (li, i) => fillIx(li, i, S));
      }
      bpUnread.setAttribute("aria-pressed", String(ui.unreadOnly));
      const kept = ui.unreadOnly ? list.filter(n => !n.read) : list;
      sync(nList, noteMore.page(kept, nList, `notes:${ui.unreadOnly}`), n => n.id, () => {
        const li = E("li"), b = btn("vf-nitem");
        const lead = E("span", "vf-nlead"), txt = E("span", "vf-ntxt"), title = E("span", "vf-ntitle"), bodyT = E("span", "vf-nbody"), tm = E("span", "vf-card-time"), dot = E("span", "vf-ndot");
        txt.append(title, bodyT); b.append(lead, txt, tm, dot); li.append(b);
        b.onclick = () => goNote(li._n);
        li._k = { b, lead, title, bodyT, tm, dot };
        return li;
      }, (li, n) => {
        const k = li._k; li._n = n;
        const key = n.byCid ? "p:" + n.byCid + (n.by || "") : "k:" + n.kind;
        if (k.lead._key !== key) { k.lead._key = key; k.lead.replaceChildren(n.byCid ? Core.avatar(n.byCid, n.by || "?", 24) : icon(KIND_ICON[n.kind] || "bell")); }
        k.title.textContent = n.by ? `${disp(n.by)} ${n.title}` : n.title;
        k.bodyT.textContent = n.body || ""; k.bodyT.hidden = !n.body;
        k.tm.textContent = ago(n.ts);
        k.dot.hidden = n.read;
        k.b.classList.toggle("vf-nunread", !n.read);
        k.b.setAttribute("aria-label", `${n.read ? "" : "Unread. "}${k.title.textContent}${n.body ? ": " + n.body : ""}. ${ago(n.ts) === "now" ? "Just now" : ago(n.ts) + " ago"}.`);
      });
      nEmpty.hidden = kept.length > 0;
      nEmpty.textContent = ui.unreadOnly && list.length ? "No unread notifications." : NO_NOTES;
      const muted = new Set(pref("mute", []));
      muteBtn.textContent = muted.size ? `Notify me about: ${NOTE_KINDS.length - muted.size} of ${NOTE_KINDS.filter(([kk]) => mod || !["queue", "ready"].includes(kk)).length} kinds` : "Choose what notifies you";
      muteBtn.setAttribute("aria-expanded", String(!!ui.muteOpen));
      muteBox.hidden = !ui.muteOpen;
      for (const [kk, b] of Object.entries(muteRows)) { b.hidden = !mod && (kk === "queue" || kk === "ready"); b.setAttribute("aria-checked", String(!muted.has(kk))); }
    }

    // ---------- Q86: the phone More sheet ----------
    function toggleMore() { if (ui.pop === moreSheet) return closePop(); openPanel(moreSheet, tabBtns.more); }
    msClose.onclick = () => { closePop(); tabBtns.more.focus(); };
    msAsk.onclick = () => { closePop(); openAskPanel(); };
    msBell.onclick = () => { closePop(); openBell(tabBtns.more); };
    msTour.onclick = () => startTour(tabBtns.more);
    function openIntro(anchor) {
      const S = Core.state;
      ipText.textContent = S.intro || "The host has not written an introduction yet.";
      ipGoal.textContent = S.goal ? `Goal: ${S.goal}` : ""; ipGoal.hidden = !S.goal;
      ipEdit.hidden = !Core.me.isOwner;
      openPop(introPop, anchor);
    }
    introBtn.onclick = () => (ui.pop === introPop ? closePop() : openIntro(introBtn));
    msIntro.onclick = () => { closePop(); openIntro(tabBtns.more.offsetParent ? tabBtns.more : top); };
    helpIntro.onclick = () => { closePop(); openIntro(keysBtn.offsetParent ? keysBtn : gear.offsetParent ? gear : top); };
    helpReport.onclick = () => openReport(keysBtn);
    msReport.onclick = () => openReport(tabBtns.more);
    helpMyReps.onclick = () => openPop(myRepPop, keysBtn);
    msMyReps.onclick = () => openPop(myRepPop, tabBtns.more);
    myRepDone.onclick = () => { const a = myRepPop._anchor; closePop(); if (a?.isConnected && a.offsetParent) a.focus({ preventScroll: true }); };
    msRecords.onclick = () => { closePop(); Core.telemetry.openRecords(); };
    on(hIntroIn, "input", () => { ui.introDirty = hIntroIn.value.trim() !== (Core.state.intro || ""); counter(hIntroCount, hIntroIn, 500); hIntroSave.disabled = !ui.introDirty; });
    hIntroSave.onclick = () => {
      hIntroSave.disabled = true;
      Core.setIntro(hIntroIn.value.trim()).then(() => { ui.introDirty = false; flash("Introduction saved. Guests see it before question 1."); render(); })
        .catch(e => { hIntroSave.disabled = false; fail(e); });
    };
    ipEdit.onclick = () => { closePop(); setMode("host"); if (phone.matches) setTab("host"); requestAnimationFrame(() => hIntroIn.focus()); };
    helpTour.onclick = () => startTour(keysBtn.offsetParent ? keysBtn : null);
    orTour.onclick = () => startTour(orTour);
    orStart.onclick = () => {
      const id = orStart._q; ui.orientHidden = true;
      if (id) focusQuestion(id); else render();
      requestAnimationFrame(() => {
        const q = qById(ui.cur), sel = { choice: ".vf-optchoose:not(:disabled)", confirm: ".vf-pickbtn:not(:disabled)", multi: ".vf-check-box:not(:disabled)",
          scale: ".vf-scale-btn[tabindex='0']", rank: "button:not(:disabled)" }[q?.format];
        const first = (sel && fmtBox.querySelector(sel)) || (ta.disabled ? qText : ta);
        first.scrollIntoView({ block: "center", behavior: smooth() });
        first.focus({ preventScroll: true });
      });
    };
    msTheme.onclick = cycleTheme;
    msFollow.onclick = () => setFollow(!following());
    msShare.onclick = () => { closePop(); openPop(sharePop, tabBtns.more); };
    msHost.onclick = () => { closePop(); setTab("host"); };
    msSettings.onclick = () => {
      closePop();
      if (Core.me.isOwner) return openPop(settingsPop, tabBtns.more);
      // Everyone else: my own card holds my name, theme accent, Claude's take and other devices.
      let a = people.querySelector(".vf-person-me");
      if (!a) { a = tabBtns.more; a.dataset.pid = Core.me.cid; a.dataset.name = Core.me.name; }
      showCard(a, true);
      if (a === tabBtns.more) { delete a.dataset.pid; delete a.dataset.name; }
    };
    function renderMore(S, mod) {
      msAsk.hidden = askTop.hidden;
      msShare.hidden = !mod;
      msHost.hidden = !mod;
      msFollow.hidden = Core.me.isOwner || !S.settings.follow;
      msFollow._l.textContent = Core.owner() ? `Follow ${disp(Core.owner().name)}` : "Follow host";
      msFollow._d.textContent = following() ? "On" : "Off";
      msFollow.setAttribute("aria-pressed", String(following()));
      msSettings._d.textContent = Core.me.isOwner ? "Session settings for everyone" : "Your name, accent and devices";
      const waitingQ = mod ? queueItems(S).length : 0;
      msHost._d.textContent = waitingQ ? `${waitingQ} waiting in the queue` : "Run the session";
      tabBtns.more.setAttribute("aria-expanded", String(ui.pop === moreSheet));
    }

    // ---------- Q82: @mention suggestions in every field people write in ----------
    const MQ = /(?:^|[^\p{L}\p{N}])@([^\s@][^@\n]{0,39}|)$/u;
    const mentionFields = [ta, mInput, sugTa, sugNote, propTa, apTa, askTa];
    for (const f of mentionFields) { f.setAttribute("aria-autocomplete", "list"); f.setAttribute("aria-haspopup", "listbox"); f.setAttribute("aria-expanded", "false"); }
    function closeMention() {
      const M = ui.mention; if (!M) return;
      ui.mention = null; mentionBox.hidden = true;
      M.field.setAttribute("aria-expanded", "false"); M.field.removeAttribute("aria-activedescendant"); M.field.removeAttribute("aria-controls");
    }
    function mentionCheck(f) {
      const pos = f.selectionStart;
      if (pos !== f.selectionEnd || readOnlyField(f)) return closeMention();
      const m = f.value.slice(0, pos).match(MQ);
      if (!m) return closeMention();
      const q = m[1].toLowerCase(), gone = new Set(Core.state.removed || []), hereNow = new Set(Core.state.presence.map(p => p.cid));
      const items = Object.entries(Core.state.people || {}).filter(([p]) => !isMe(p) && !gone.has(p) && Core.mentionLabel(p).toLowerCase().startsWith(q))
        .map(([pid, v]) => ({ pid, name: v.name, label: Core.mentionLabel(pid), here: hereNow.has(pid) }))
        .sort((a, b) => b.here - a.here || a.name.localeCompare(b.name)).slice(0, 6);
      if (!items.length) return closeMention();
      const prev = ui.mention;
      ui.mention = { field: f, start: pos - m[1].length - 1, end: pos, items, sel: prev?.field === f ? Math.min(prev.sel, items.length - 1) : 0 };
      paintMention();
    }
    const readOnlyField = f => f.disabled || f.readOnly;
    function paintMention() {
      const M = ui.mention, f = M.field;
      mentionBox.replaceChildren(...M.items.map((p, i) => {
        const li = E("li", "vf-mopt"); li.id = "vf-mopt-" + i; li.setAttribute("role", "option"); li.setAttribute("aria-selected", String(i === M.sel));
        li.append(Core.avatar(p.pid, p.name, 22), E("span", "vf-mopt-n", disp(p.name)), E("span", "vf-meta", p.here ? "here" : ""));
        // keep focus in the field, and keep an open popover or panel (Propose, Ask Claude) from closing
        li.addEventListener("pointerdown", e => { e.preventDefault(); e.stopPropagation(); pickMention(i); });
        return li;
      }));
      mentionBox.hidden = false;
      f.setAttribute("aria-expanded", "true"); f.setAttribute("aria-controls", mentionBox.id); f.setAttribute("aria-activedescendant", "vf-mopt-" + M.sel);
      // over the field when it sits low (composer, chat), under it otherwise; never wider than the field
      const R = root.getBoundingClientRect(), r = f.getBoundingClientRect(), ps = mentionBox.style;
      ps.inlineSize = Math.min(300, Math.max(220, r.width)) + "px";
      ps.insetInlineStart = Math.max(8, Math.min(r.left - R.left, R.width - mentionBox.offsetWidth - 8)) + "px";
      // a field with no room above or below it (the phone's full-height answer sheet): over the field's lower half
      if (r.top - R.top - 14 < 88 && R.bottom - r.bottom - 14 < 88) {
        ps.insetBlockStart = ""; ps.insetBlockEnd = R.bottom - r.bottom + 8 + "px"; ps.maxBlockSize = Math.max(88, r.height / 2) + "px";
        return;
      }
      const above = r.top - R.top > R.height / 2;
      ps.maxBlockSize = Math.max(88, above ? r.top - R.top - 14 : R.bottom - r.bottom - 14) + "px";
      ps.insetBlockStart = above ? "" : r.bottom - R.top + 6 + "px";
      ps.insetBlockEnd = above ? R.bottom - r.top + 6 + "px" : "";
    }
    function pickMention(i) {
      const M = ui.mention; if (!M) return;
      const f = M.field, ins = "@" + M.items[i].label + " ";
      f.value = f.value.slice(0, M.start) + ins + f.value.slice(M.end);
      const at = M.start + ins.length;
      closeMention();
      f.focus({ preventScroll: true }); f.setSelectionRange(at, at);
      f.dispatchEvent(new Event("input", { bubbles: true }));
    }
    on(root, "input", e => { if (mentionFields.includes(e.target) && !e.isComposing) mentionCheck(e.target); });
    on(document, "selectionchange", () => { const M = ui.mention; if (M && document.activeElement === M.field) mentionCheck(M.field); });
    on(root, "focusout", e => { if (ui.mention?.field === e.target) closeMention(); });
    // Runs before the fields' own keys (Enter sends chat, Ctrl + Enter sends an answer) while the list is open.
    on(root, "keydown", e => {
      const M = ui.mention;
      if (!M || e.target !== M.field || e.isComposing) return;
      const n = M.items.length;
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { M.sel = (M.sel + (e.key === "ArrowDown" ? 1 : -1) + n) % n; paintMention(); }
      else if ((e.key === "Enter" && !e.shiftKey && !e.ctrlKey && !e.metaKey) || e.key === "Tab") pickMention(M.sel);
      else if (e.key === "Escape") closeMention();
      else return;
      e.preventDefault(); e.stopPropagation();
    }, true);

    // ---------- attachments: one picker and one renderer for answers, chat, requests, suggestions, proposals and references ----------
    const httpUrl = u => { try { return ["http:", "https:"].includes(new URL(u).protocol) ? u : ""; } catch { return ""; } };
    const domainOf = u => { try { return new URL(u).hostname.replace(/^www\./, ""); } catch { return ""; } };
    // C44: an answer or pick carries files (uploads the owner accepted). Chat, requests, suggestions and proposals have
    // no attachment field in the contract, so their attach buttons stay hidden.
    const fileOf = a => (a?.upload && (Core.state.files?.[a.upload] || [...(Core.state.myUploads || []), ...(Core.state.uploads || [])].find(u => u.id === a.upload))) || null;
    // A diagram reference is an SVG Claude made, shown like a picture, with its required alt text on the image.
    const attAsset = a => (a?.kind === "image" ? a.asset || fileOf(a)?.asset || "" : a?.kind === "diagram" ? a.asset || "" : "");
    const attTitle = a => a.caption || fileOf(a)?.file || (a.kind === "diagram" ? "Diagram" : "Picture");
    const attKey = list => JSON.stringify((list || []).map(a => [a, fileOf(a)?.status || "", attAsset(a)]));
    const ATT_STAT = { offered: "Waiting for the host to accept", accepted: "Accepted, sending", uploading: "Sending", done: "Received by the host",
      declined: "Not accepted", withdrawn: "Withdrawn", failed: "Failed" };
    /** One attachment, drawn the same everywhere. open(from) shows an inline picture in the viewer. */
    function attNode(a, open) {
      const li = E("li", "vf-ref"), asset = attAsset(a);
      const diagram = a.kind === "diagram";
      li.dataset.kind = asset ? (diagram ? "diagram" : "image") : a.kind === "image" ? "file" : a.kind;
      if (asset) {
        const b = btn("vf-ref-img"), thumb = E("span", "vf-ref-thumb"), img = E("img"), mark = E("span", "vf-confirm-mark");
        img.src = assetUrl(asset); img.alt = diagram ? a.alt || "" : ""; img.loading = "lazy"; mark.setAttribute("aria-hidden", "true"); markRect(mark, a.rect);
        thumb.append(img, mark, zoomTag());
        b.append(thumb, E("span", "vf-ref-cap", attTitle(a)));
        // A diagram's button is named by its alt text and caption; a picture's by its caption alone.
        b.setAttribute("aria-label", diagram ? `View larger: ${attTitle(a)}. ${a.alt || ""}`.trim() : `View larger: ${attTitle(a)}${a.rect ? ", with a marked area" : ""}`);
        b.onclick = () => open(b);
        li.append(b);
      } else if (a.kind === "file" || a.kind === "image") {
        const f = fileOf(a), box = E("div", "vf-ref-file"), t = E("span", "vf-ref-lt");
        t.append(icon(a.kind === "image" ? "image" : "file"), E("span", "vf-ref-title", f?.file || (a.kind === "image" ? "A picture" : "A file")));
        box.append(t, E("span", "vf-ref-dom", [f?.size ? sizeTxt(f.size) : "", ATT_STAT[f?.status] || "No longer offered",
          a.kind === "image" && f?.status !== "done" ? "shows once accepted" : ""].filter(Boolean).join(" · ")));
        box.dataset.stat = f?.status || "gone";
        li.append(box);
      } else if (a.kind === "quote") {
        const box = E("div", "vf-ref-quote"), bq = E("blockquote", "vf-ref-qt", a.text), foot = E("div", "vf-ref-foot");
        const url = httpUrl(a.url || "");
        const src = url ? E("a", "vf-ref-src vf-link", a.source) : E("span", "vf-ref-src", a.source);
        if (url) { src.href = url; src.target = "_blank"; src.rel = "noopener noreferrer"; }
        const read = btn("vf-lbtn", "Read"); read.setAttribute("aria-label", `Read the quote from ${a.source}`);
        read.onclick = () => openReader("Quote", a.source, a.text, read);
        foot.append(icon("cite"), src, read);
        box.append(bq, foot); li.append(box);
      } else {
        const url = httpUrl(a.url);
        const link = E(url ? "a" : "span", "vf-ref-link");
        if (url) { link.href = url; link.target = "_blank"; link.rel = "noopener noreferrer"; }
        const t = E("span", "vf-ref-lt"); t.append(icon("link"), E("span", "vf-ref-title", a.title || domainOf(a.url) || a.url));
        link.append(t, E("span", "vf-ref-dom", domainOf(a.url)));
        li.append(link);
      }
      return li;
    }
    /** A record's attachments into a list; meta names the record in the picture viewer. */
    function fillAtts(ul, atts, meta) {
      atts = atts || [];
      ul.hidden = !atts.length;
      const key = attKey(atts);
      if (ul._key === key) return;
      ul._key = key;
      const pics = atts.filter(attAsset), items = pics.map(p => ({ asset: attAsset(p), title: attTitle(p), rect: p.rect || null }));
      ul.replaceChildren(...atts.map(a => attNode(a, from => openLb("att", null, pics.indexOf(a), from, items, meta))));
    }
    const attRowEl = () => { const ul = E("ul", "vf-reflist vf-attlist"); ul.setAttribute("aria-label", "Attachments"); ul.hidden = true; return ul; };

    // References under the question: the host adds them through the same picker.
    function makeRef(r) {
      const li = attNode(r, from => openLb("ref", ui.cur, (qById(ui.cur)?.references || []).slice(0, li._i).filter(attAsset).length, from));
      if (Core.me.isOwner) {
        const x = ibtn("vf-tbtn vf-icon-btn vf-ref-x", "x", "Remove this reference");
        x.onclick = guarded({ title: "Remove this reference?", body: "It disappears from this question for everyone. You can add it again later.", ok: "Remove reference" },
          () => Core.removeReference(ui.cur, li._i).then(() => flash("Reference removed.")).catch(fail));
        li.append(x);
      }
      return li;
    }
    function renderRefs(q) {
      const refs = q.references || [], owner = Core.me.isOwner;
      refBox.hidden = !refs.length && !owner;
      refAdd.hidden = !owner || refs.length >= 8;
      refList.hidden = !refs.length;
      refHead.firstChild.hidden = !refs.length; // with none yet, the host sees only Add reference
      if (refList._q !== q.id) { resetList(refList); refList._q = q.id; }
      sync(refList, refs.map((r, i) => ({ r, i })), x => x.i + ":" + attKey([x.r]), x => makeRef(x.r), (li, x) => { li._i = x.i; });
    }
    refAdd.onclick = () => { const qid = ui.cur; openAttach({ qid, ref: true, from: refAdd, onAdd: att => Core.addReference(qid, att).then(() => flash("Reference added.")) }); };

    // The picker: Upload a file, Image, Link or Quote. A modal dialog, so it opens over any panel or sheet.
    const attDlg = E("dialog", "vf-dlg vf-attdlg");
    const adForm = E("form", "vf-attform"); adForm.noValidate = true;
    const adTitle = E("h2", "vf-dlg-title"); adTitle.id = "vf-att-title"; attDlg.setAttribute("aria-labelledby", adTitle.id);
    const adSeg = E("div", "vf-seg vf-seg-sm vf-attseg"); adSeg.setAttribute("role", "group"); adSeg.setAttribute("aria-label", "What to attach");
    const adKinds = {};
    for (const [k, l] of [["file", "Upload a file"], ["image", "Image"], ["link", "Link"], ["quote", "Quote"]]) {
      const b = btn("vf-seg-btn", l); b.onclick = () => { AD.kind = k; adErr.textContent = ""; paintAttach(); }; adSeg.append(b); adKinds[k] = b;
    }
    const adFile = E("input", "vf-input vf-filein"); adFile.type = "file";
    const adImg = E("input", "vf-input vf-filein"); adImg.type = "file"; adImg.accept = "image/png,image/jpeg,image/webp";
    const adCap = E("input", "vf-input"); adCap.maxLength = 200;
    const adUrl = E("input", "vf-input"); adUrl.type = "url"; adUrl.maxLength = 2000; adUrl.placeholder = "https://";
    const adLTitle = E("input", "vf-input"); adLTitle.maxLength = 200;
    const adQText = E("textarea", "vf-ta"); adQText.rows = 3; adQText.maxLength = 1000;
    const adQSrc = E("input", "vf-input"); adQSrc.maxLength = 200; adQSrc.placeholder = "PRD v2, section 3";
    const adQUrl = E("input", "vf-input"); adQUrl.type = "url"; adQUrl.maxLength = 2000; adQUrl.placeholder = "https://";
    const adField = (label, el) => { const w = E("label", "vf-rpfield"); w.append(E("span", "vf-sel-l", label), el); return w; };
    const adF = { file: adField("File", adFile), image: adField("Image (PNG, JPEG or WebP)", adImg), cap: adField("Caption (optional)", adCap),
      url: adField("Link", adUrl), ltitle: adField("Title (optional)", adLTitle), qtext: adField("Quoted text", adQText),
      qsrc: adField("Source", adQSrc), qurl: adField("Link to the source (optional)", adQUrl) };
    // C44: files I sent that the host accepted, ready to attach to this answer.
    const adMine = E("ul", "vf-reflist vf-attmine"); adMine.setAttribute("aria-label", "Your files the host accepted");
    const adMineHead = E("p", "vf-sel-l", "Or attach a file the host accepted");
    const adNote = E("p", "vf-pop-note vf-att-note");
    const adErr = E("p", "vf-att-err"); adErr.setAttribute("role", "alert");
    const adRow = E("div", "vf-crow vf-dlg-row");
    const adCancel = btn("vf-btn vf-btn-ghost", "Cancel");
    const adOk = E("button", "vf-btn vf-btn-primary"); adOk.type = "submit";
    adRow.append(E("span", "vf-spacer"), adCancel, adOk);
    adForm.append(adTitle, adSeg, ...Object.values(adF), adNote, adMineHead, adMine, adErr, adRow);
    attDlg.append(adForm);
    root.append(attDlg);
    const AD = { kind: "link", qid: "", ref: false, files: false, taken: [], onAdd: null, from: null };
    /** Which tabs the picker shows. A reference takes a link or a quote. An answer or pick (files) takes an upload,
     *  and only while Uploads is on; every other form takes nothing yet. Pictures come from Claude's add-asset. */
    function attKinds(ref, files) {
      if (ref) return { file: false, image: false, link: true, quote: true };
      return { file: !!files && !!st().uploads, image: false, link: false, quote: false };
    }
    /** My uploads the host accepted (the owner's own are accepted at once), newest first, not already attached. */
    const acceptedMine = taken => (Core.state.myUploads || []).filter(u => ["accepted", "uploading", "done"].includes(u.status) && !taken.includes(u.id))
      .sort((a, b) => b.ts - a.ts);
    const adFirst = () => ({ file: adFile, image: adImg, link: adUrl, quote: adQText })[AD.kind];
    function openAttach(o) {
      Object.assign(AD, { qid: "", ref: false, files: false, taken: [], onAdd: null, from: null }, o);
      const ok = attKinds(AD.ref, AD.files);
      if (!ok[AD.kind]) AD.kind = Object.keys(ok).find(k => ok[k]) || "link";
      for (const x of [adFile, adImg, adCap, adUrl, adLTitle, adQText, adQSrc, adQUrl]) x.value = "";
      adErr.textContent = "";
      paintAttach();
      attDlg.showModal();
      adFirst()?.focus();
    }
    function paintAttach() {
      const ok = attKinds(AD.ref, AD.files), k = AD.kind, owner = Core.me.isOwner, trusted = owner || Core.me.isTrusted;
      adTitle.textContent = AD.ref ? "Add a reference" : "Attach to this";
      for (const [kk, b] of Object.entries(adKinds)) { b.hidden = !ok[kk]; b.setAttribute("aria-pressed", String(kk === k)); }
      adSeg.hidden = Object.values(ok).filter(Boolean).length < 2;
      adF.file.hidden = k !== "file"; adF.image.hidden = adF.cap.hidden = k !== "image";
      adF.url.hidden = adF.ltitle.hidden = k !== "link";
      adF.qtext.hidden = adF.qsrc.hidden = adF.qurl.hidden = k !== "quote";
      adFile.accept = trusted ? "" : [...GUEST_EXT].map(x => "." + x).join(",");
      adNote.textContent = {
        file: owner ? "Any kind of file. It is saved on your computer, for Claude. Attach it once it is sent."
          : (trusted ? "Any kind of file, zip included, up to 100 MB in all." : "Pictures, PDF, text, CSV and Office files, up to 100 MB in all.")
            + " The host accepts it first; until then it stays on this device. Attach it here once they do.",
        image: "Shows in place.",
        link: "Shows as a titled link that opens in a new tab.",
        quote: "Shows the quoted words and where they come from.",
      }[k];
      const mine = k === "file" && !AD.ref ? acceptedMine(AD.taken) : [];
      adMineHead.hidden = adMine.hidden = !mine.length;
      adMine.replaceChildren(...mine.map(u => {
        const li = E("li", "vf-ref"), b = btn("vf-btn vf-btn-ghost vf-btn-sm vf-attpick");
        b.append(icon("file"), E("span", "vf-ref-title", u.file), E("span", "vf-ref-dom", sizeTxt(u.size)));
        b.setAttribute("aria-label", `Attach ${u.file}`);
        b.onclick = async () => { try { await AD.onAdd?.({ kind: "file", upload: u.id }); attDlg.close(); } catch (x) { adErr.textContent = `Not added: ${Core.errorText(x)}`; } };
        li.append(b); return li;
      }));
      adOk.textContent = AD.ref ? "Add reference" : k === "file" ? "Offer file" : "Attach";
    }
    adForm.onsubmit = async e => {
      e.preventDefault();
      const k = AD.kind, bad = (error, field) => ({ error, field });
      adErr.textContent = "";
      adOk.disabled = true;
      try {
        let att;
        if (k === "link") {
          const url = httpUrl(adUrl.value.trim()), title = adLTitle.value.trim();
          if (!url) throw bad("Enter a link that starts with http:// or https://.", adUrl);
          att = { kind: "link", url, ...(title ? { title } : {}) };
        } else if (k === "quote") {
          const text = adQText.value.trim(), source = adQSrc.value.trim(), u = adQUrl.value.trim();
          if (!text) throw bad("Enter the quoted words.", adQText);
          if (!source) throw bad("Say where the quote comes from.", adQSrc);
          if (u && !httpUrl(u)) throw bad("The source link must start with http:// or https://.", adQUrl);
          att = { kind: "quote", text, source, ...(u ? { url: u } : {}) };
        } else {
          // Offering a file is all this does: it stays on this device until the host accepts it, and is attached
          // from the list above once they do (the owner's own is accepted at once, so it attaches now).
          const f = adFile.files?.[0];
          if (!f) throw bad("Choose a file first.", adFile);
          const r = await offerFile(f, AD.qid).catch(x => { throw x?.status ? x : bad(x.error, adFile); });
          if (r.status === "accepted") att = { kind: "file", upload: r.id };
        }
        if (att) await AD.onAdd?.(att);
        attDlg.close();
      } catch (x) {
        adErr.textContent = x?.field ? x.error : `Not added: ${Core.errorText(x)}`;
        x?.field?.focus();
      } finally { adOk.disabled = false; }
    };
    adCancel.onclick = () => attDlg.close();
    attDlg.addEventListener("close", () => { if (AD.from?.isConnected) AD.from.focus({ preventScroll: true }); });

    /** A form's attachments before it is sent: chips with a remove button, and the button that opens the picker.
     *  store.get/set keep the list somewhere else (the answer composer keeps one per question). */
    function attSlot(getQid, btnEl, store, files = false) {
      const b = btnEl || ibtn("vf-btn vf-btn-ghost vf-btn-sm vf-attach", "clip", "Attach");
      b.setAttribute("aria-label", files ? "Attach a file" : "Attach a file, image, link or quote"); b.title = "Attach"; b.setAttribute("aria-haspopup", "dialog");
      const chips = E("ul", "vf-reflist vf-attlist vf-attdraft"); chips.setAttribute("aria-label", "Attached, not sent yet"); chips.hidden = true;
      let own = [];
      const slot = { btn: b, chips, files, get: store?.get || (() => own), set: store?.set || (l => { own = l; }) };
      slot.put = l => { slot.set(l); paintSlot(slot); };
      slot.clear = () => slot.put([]);
      b.onclick = () => {
        if (slot.get().length >= 4) return flash("An answer carries four files at most.");
        openAttach({ qid: getQid(), files, taken: slot.get().map(a => a.upload), from: b, onAdd: att => slot.put([...slot.get(), att]) });
      };
      return slot;
    }
    function paintSlot(slot, ro = false) {
      const list = slot.get(), full = list.length >= 4;
      slot.btn.hidden = ro || !Object.values(attKinds(false, slot.files)).some(Boolean);
      slot.btn.setAttribute("aria-disabled", String(full));
      slot.btn.title = full ? "Four attachments at most" : "Attach";
      slot.chips.hidden = ro || !list.length;
      const key = attKey(list);
      if (slot.chips._key === key) return;
      slot.chips._key = key;
      const pics = list.filter(attAsset), items = pics.map(p => ({ asset: attAsset(p), title: attTitle(p), rect: null }));
      slot.chips.replaceChildren(...list.map((a, i) => {
        const li = attNode(a, from => openLb("att", null, pics.indexOf(a), from, items, "Not sent yet"));
        const x = ibtn("vf-tbtn vf-icon-btn vf-ref-x", "x", "Remove this attachment");
        x.onclick = () => { const l = slot.get().slice(); l.splice(i, 1); slot.put(l); (slot.chips.querySelector(".vf-ref-x") || slot.btn).focus(); };
        li.append(x); return li;
      }));
    }
    /** What a send carries: the upload ids of an answer's or pick's files; nothing for forms with no attachment field. */
    const attExtra = slot => (slot.files ? { attachments: slot.get().map(a => a.upload).filter(Boolean) } : undefined);

    // ---------- QR code: byte mode, error correction M, versions 1 to 10, built here with no library ----------
    function qrMatrix(text) {
      const data = new TextEncoder().encode(text);
      const ECC = [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26], BLK = [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5];
      const rawMods = v => { let r = (16 * v + 128) * v + 64; if (v >= 2) { const n = Math.floor(v / 7) + 2; r -= (25 * n - 10) * n - 55; if (v >= 7) r -= 36; } return r; };
      const cap = v => Math.floor(rawMods(v) / 8) - ECC[v] * BLK[v];
      let ver = 1;
      while (ver <= 10 && 4 + (ver < 10 ? 8 : 16) + data.length * 8 > cap(ver) * 8) ver++;
      if (ver > 10) return null;
      const bits = [], put = (v, n) => { for (let i = n - 1; i >= 0; i--) bits.push((v >>> i) & 1); };
      put(4, 4); put(data.length, ver < 10 ? 8 : 16); for (const b of data) put(b, 8);
      const capBits = cap(ver) * 8;
      put(0, Math.min(4, capBits - bits.length)); put(0, (8 - bits.length % 8) % 8);
      for (let p = 0xEC; bits.length < capBits; p ^= 0xEC ^ 0x11) put(p, 8);
      const cw0 = []; for (let i = 0; i < bits.length; i += 8) { let b = 0; for (let j = 0; j < 8; j++) b = (b << 1) | bits[i + j]; cw0.push(b); }
      const mul = (x, y) => { let z = 0; for (let i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >>> 7) * 0x11D); z ^= ((y >>> i) & 1) * x; } return z; };
      const ecl = ECC[ver], nb = BLK[ver], raw = Math.floor(rawMods(ver) / 8), nShort = nb - raw % nb, shortLen = Math.floor(raw / nb);
      const div = Array(ecl).fill(0); div[ecl - 1] = 1;
      for (let i = 0, root = 1; i < ecl; i++, root = mul(root, 2)) for (let j = 0; j < ecl; j++) { div[j] = mul(div[j], root); if (j + 1 < ecl) div[j] ^= div[j + 1]; }
      const rem = d => { const r = Array(ecl).fill(0); for (const b of d) { const f = b ^ r.shift(); r.push(0); div.forEach((c, i) => { r[i] ^= mul(c, f); }); } return r; };
      const blocks = [];
      for (let i = 0, k = 0; i < nb; i++) {
        const dat = cw0.slice(k, k + shortLen - ecl + (i < nShort ? 0 : 1)); k += dat.length;
        const ecc = rem(dat); if (i < nShort) dat.push(0); blocks.push(dat.concat(ecc));
      }
      const cw = [];
      for (let i = 0; i < blocks[0].length; i++) blocks.forEach((b, j) => { if (i !== shortLen - ecl || j >= nShort) cw.push(b[i]); });
      const size = ver * 4 + 17, M = Array.from({ length: size }, () => Array(size).fill(false)), F = Array.from({ length: size }, () => Array(size).fill(false));
      const set = (x, y, d) => { M[y][x] = d; F[y][x] = true; };
      for (let i = 0; i < size; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
      for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]]) for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx, y = cy + dy, d = Math.max(Math.abs(dx), Math.abs(dy));
        if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, d !== 2 && d !== 4);
      }
      if (ver > 1) {
        const n = Math.floor(ver / 7) + 2, stp = Math.ceil((ver * 4 + 4) / (n * 2 - 2)) * 2, pos = [6];
        for (let p = size - 7; pos.length < n; p -= stp) pos.splice(1, 0, p);
        pos.forEach((a, i) => pos.forEach((b, j) => {
          if ((i === 0 && j === 0) || (i === 0 && j === n - 1) || (i === n - 1 && j === 0)) return;
          for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(a + dx, b + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
        }));
      }
      const fmt = mask => {
        const d = mask; let r = d; for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537);
        const b = ((d << 10) | r) ^ 0x5412, bit = i => ((b >>> i) & 1) === 1; // M is 00
        for (let i = 0; i <= 5; i++) set(8, i, bit(i));
        set(8, 7, bit(6)); set(8, 8, bit(7)); set(7, 8, bit(8));
        for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
        for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i));
        for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i));
        set(8, size - 8, true);
      };
      fmt(0);
      if (ver >= 7) {
        let r = ver; for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1F25);
        const b = (ver << 12) | r;
        for (let i = 0; i < 18; i++) { const d = ((b >>> i) & 1) === 1, a = size - 11 + i % 3, c = Math.floor(i / 3); set(a, c, d); set(c, a, d); }
      }
      let i = 0;
      for (let right = size - 1; right >= 1; right -= 2) {
        if (right === 6) right = 5;
        for (let v = 0; v < size; v++) for (let j = 0; j < 2; j++) {
          const x = right - j, up = ((right + 1) & 2) === 0, y = up ? size - 1 - v : v;
          if (!F[y][x] && i < cw.length * 8) { M[y][x] = ((cw[i >>> 3] >>> (7 - (i & 7))) & 1) === 1; i++; }
        }
      }
      const MASKS = [(x, y) => (x + y) % 2 === 0, (x, y) => y % 2 === 0, x => x % 3 === 0, (x, y) => (x + y) % 3 === 0,
        (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0, (x, y) => (x * y) % 2 + (x * y) % 3 === 0,
        (x, y) => ((x * y) % 2 + (x * y) % 3) % 2 === 0, (x, y) => ((x + y) % 2 + (x * y) % 3) % 2 === 0];
      const apply = m => { for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (!F[y][x] && MASKS[m](x, y)) M[y][x] = !M[y][x]; };
      const penalty = () => { // runs of five or more, 2x2 blocks, dark balance
        let p = 0, dark = 0;
        for (let a = 0; a < size; a++) for (const row of [0, 1]) {
          let run = 1;
          for (let b = 1; b < size; b++) {
            const c = row ? M[a][b] : M[b][a], prev = row ? M[a][b - 1] : M[b - 1][a];
            if (c === prev) { run++; if (run === 5) p += 3; else if (run > 5) p++; } else run = 1;
          }
        }
        for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
          if (M[y][x]) dark++;
          if (x < size - 1 && y < size - 1 && M[y][x] === M[y][x + 1] && M[y][x] === M[y + 1][x] && M[y][x] === M[y + 1][x + 1]) p += 3;
        }
        return p + Math.floor(Math.abs(dark * 20 - size * size * 10) / (size * size)) * 10;
      };
      let best = 0, bestP = Infinity;
      for (let m = 0; m < 8; m++) { apply(m); fmt(m); const p = penalty(); if (p < bestP) { bestP = p; best = m; } apply(m); }
      apply(best); fmt(best);
      return M;
    }
    function qrSvg(text) {
      const M = qrMatrix(text); if (!M) return E("p", "vf-pop-note", "The link is too long for a QR code. Copy it instead.");
      const n = M.length + 8, s = document.createElementNS(SVG, "svg");
      s.setAttribute("viewBox", `0 0 ${n} ${n}`); s.setAttribute("role", "img"); s.setAttribute("aria-label", "QR code of your personal link");
      s.setAttribute("shape-rendering", "crispEdges");
      const bg = document.createElementNS(SVG, "rect"); bg.setAttribute("width", n); bg.setAttribute("height", n); bg.setAttribute("fill", "#fff");
      let d = ""; M.forEach((row, y) => row.forEach((on2, x) => { if (on2) d += `M${x + 4} ${y + 4}h1v1h-1z`; }));
      const p = document.createElementNS(SVG, "path"); p.setAttribute("d", d); p.setAttribute("fill", "#000");
      s.append(bg, p);
      return s;
    }
    function openDevice() {
      const link = Core.personalLink();
      if (!link) return flash("Join first, then you can take this to another device.");
      devField.value = link;
      qrBox.replaceChildren(qrSvg(link));
      devWarn.replaceChildren(icon("alert"), E("span", null, Core.me.isOwner
        ? "Keep this private: this is your owner link, and anyone with it can run this session."
        : "Keep this private: anyone with this link can answer, vote and chat as you."));
      const anchor = people.querySelector(".vf-person-me") || (gear.offsetParent ? gear : askTop);
      openPop(devicePop, anchor);
      devCopy.focus({ preventScroll: true });
    }
    devCopy.onclick = async () => {
      try { await navigator.clipboard.writeText(devField.value); devCopy.textContent = "Copied"; } catch { devField.focus(); devField.select(); devCopy.textContent = "Press Ctrl+C"; }
      setTimeout(() => { devCopy.textContent = "Copy link"; }, 1800);
    };
    devClose.onclick = () => closePop();

    // ---------- uploads: the file waits in this browser until the host accepts ----------
    const CHUNK_MAX = 8 * 1024 * 1024, GUEST_MAX = 100 * 1024 * 1024; // the server names its chunk size on each upload
    const GUEST_EXT = new Set("png jpg jpeg gif webp pdf txt md csv tsv log rtf doc docx xls xlsx ppt pptx odt ods odp".split(" "));
    const up = { files: new Map(), running: new Set(), sent: {}, retryAt: {}, memOnly: new Set(), loaded: false, noIdb: false };
    const idb = (() => {
      let dbp = null;
      const open = () => (dbp ||= new Promise((res, rej) => {
        try { const r = indexedDB.open("vf-uploads", 1); r.onupgradeneeded = () => r.result.createObjectStore("files"); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); }
        catch (e) { rej(e); }
      }));
      const tx = (mode, fn) => open().then(db => new Promise((res, rej) => {
        const t = db.transaction("files", mode), req = fn(t.objectStore("files"));
        t.oncomplete = () => res(req?.result); t.onerror = () => rej(t.error); t.onabort = () => rej(t.error);
      }));
      return { put: (k, v) => tx("readwrite", s => s.put(v, k)), get: k => tx("readonly", s => s.get(k)), del: k => tx("readwrite", s => s.delete(k)), keys: () => tx("readonly", s => s.getAllKeys()) };
    })();
    (async () => {
      try { for (const k of await idb.keys()) { const f = await idb.get(k); if (f) up.files.set(k, f); } }
      catch { up.noIdb = true; }
      up.loaded = true;
      if (!dead) render();
    })();
    /** SHA-256 in plain JS, fed piece by piece, for the whole-file check (WebCrypto has no streaming digest). */
    function sha256() {
      const K = [], H = [], isC = {};
      for (let c = 2, n = 0; n < 64; c++) if (!isC[c]) { for (let i = 0; i < 313; i += c) isC[i] = c; if (n < 8) H[n] = (Math.pow(c, 0.5) * 4294967296) | 0; K[n++] = (Math.pow(c, 1 / 3) * 4294967296) | 0; }
      const h = Int32Array.from(H), w = new Int32Array(64), buf = new Uint8Array(64);
      let fill = 0, total = 0;
      const rot = (x, n) => (x >>> n) | (x << (32 - n));
      const block = (b, o) => {
        for (let j = 0; j < 16; j++) w[j] = (b[o + 4 * j] << 24) | (b[o + 4 * j + 1] << 16) | (b[o + 4 * j + 2] << 8) | b[o + 4 * j + 3];
        for (let j = 16; j < 64; j++) {
          const a = w[j - 15], c = w[j - 2];
          w[j] = (w[j - 16] + (rot(a, 7) ^ rot(a, 18) ^ (a >>> 3)) + w[j - 7] + (rot(c, 17) ^ rot(c, 19) ^ (c >>> 10))) | 0;
        }
        let [a, b2, c, d, e, f, g, hh] = h;
        for (let j = 0; j < 64; j++) {
          const t1 = (hh + (rot(e, 6) ^ rot(e, 11) ^ rot(e, 25)) + ((e & f) ^ (~e & g)) + K[j] + w[j]) | 0;
          const t2 = ((rot(a, 2) ^ rot(a, 13) ^ rot(a, 22)) + ((a & b2) ^ (a & c) ^ (b2 & c))) | 0;
          hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b2; b2 = a; a = (t1 + t2) | 0;
        }
        h[0] += a; h[1] += b2; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
      };
      return {
        update(d) {
          total += d.length; let i = 0;
          if (fill) { const n = Math.min(64 - fill, d.length); buf.set(d.subarray(0, n), fill); fill += n; i = n; if (fill === 64) { block(buf, 0); fill = 0; } }
          for (; i + 64 <= d.length; i += 64) block(d, i);
          if (i < d.length) { buf.set(d.subarray(i), 0); fill = d.length - i; }
        },
        hex() {
          const bitsHi = Math.floor(total / 0x20000000), bitsLo = (total * 8) >>> 0;
          const pad = new Uint8Array(((fill < 56 ? 56 : 120) - fill) + 8); pad[0] = 0x80;
          const dv = new DataView(pad.buffer); dv.setUint32(pad.length - 8, bitsHi); dv.setUint32(pad.length - 4, bitsLo);
          this.update(pad);
          return [...h].map(x => (x >>> 0).toString(16).padStart(8, "0")).join("");
        },
      };
    }
    async function pieceSha(buf) {
      if (crypto?.subtle) { try { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", buf))].map(b => b.toString(16).padStart(2, "0")).join(""); } catch {} }
      const s = sha256(); s.update(buf); return s.hex();
    }
    const sizeTxt = n => n >= 1073741824 ? (n / 1073741824).toFixed(1) + " GB" : n >= 1048576 ? (n / 1048576).toFixed(n >= 104857600 ? 0 : 1) + " MB" : n >= 1024 ? Math.round(n / 1024) + " KB" : n + " B";
    async function makeThumb(file) {
      try {
        const bmp = await createImageBitmap(file), k = Math.min(1, 240 / Math.max(bmp.width, bmp.height));
        const c = document.createElement("canvas"); c.width = Math.max(1, Math.round(bmp.width * k)); c.height = Math.max(1, Math.round(bmp.height * k));
        c.getContext("2d").drawImage(bmp, 0, 0, c.width, c.height); bmp.close?.();
        for (const q of [0.8, 0.6, 0.4, 0.25]) { const u = c.toDataURL("image/jpeg", q); if (u.length <= 60000) return u; }
      } catch {}
      return "";
    }
    /** Offer a file to the host; resolves to {id, status}, rejects with {error} or the server's refusal. */
    async function offerFile(file, qid) {
      const ext = (file.name.split(".").pop() || "").toLowerCase(), owner = Core.me.isOwner, trusted = owner || Core.me.isTrusted;
      if (!trusted && !GUEST_EXT.has(ext)) throw { error: "Guests can send pictures, PDF, text, CSV and Office files. Ask the host to trust you for other kinds." };
      if (!owner && file.size > GUEST_MAX) throw { error: `That file is ${sizeTxt(file.size)}. Guests can send up to 100 MB in all.` };
      if (!file.size) throw { error: "That file is empty." };
      const thumb = /^image\/(png|jpeg|webp|gif)$/.test(file.type) ? await makeThumb(file) : "";
      const r = await Core.uploadOffer({ file: file.name, size: file.size, type: file.type.slice(0, 200), ...(qid ? { qid } : {}), ...(thumb ? { thumb } : {}) });
      up.files.set(r.id, file);
      try { await idb.put(r.id, file); flash(owner ? "Sending the file to your computer." : "Offered to the host. The file stays on this device until they accept."); }
      catch { up.memOnly.add(r.id); flash("Offered. This browser cannot keep files (private mode?), so keep this tab open until it is sent."); }
      render();
      return r;
    }
    function forget(id) { up.files.delete(id); up.memOnly.delete(id); idb.del(id).catch(() => {}); }
    /** Start or resume every accepted upload this browser still holds. Called on each render. */
    function pumpUploads() {
      for (const u of Core.state.myUploads || []) {
        if (["declined", "withdrawn", "failed", "done"].includes(u.status)) { if (up.files.has(u.id)) forget(u.id); continue; }
        const f = up.files.get(u.id);
        if ((u.status === "accepted" || u.status === "uploading") && f && !up.running.has(u.id) && !(Date.now() < (up.retryAt[u.id] || 0))) runUpload(u, f);
      }
    }
    async function runUpload(u, file) {
      up.running.add(u.id);
      const hasher = sha256(), CHUNK = u.chunkSize || CHUNK_MAX;
      try {
        for (let i = 0; i < u.total; i++) {
          const buf = new Uint8Array(await file.slice(i * CHUNK, Math.min(file.size, (i + 1) * CHUNK)).arrayBuffer());
          hasher.update(buf);
          if (i < u.received) continue; // the server has it already: only the running hash needs it
          const sha = await pieceSha(buf), last = i === u.total - 1, whole = last ? hasher.hex() : "";
          for (let attempt = 0; ; attempt++) {
            try { await Core.uploadChunk(u.id, i, u.total, buf, sha, whole); break; }
            catch (e) {
              if (e?.status || attempt >= 4) throw e; // the server said no: do not hammer it
              await new Promise(r => setTimeout(r, 800 * (attempt + 1)));
            }
          }
          up.sent[u.id] = Math.min(file.size, (i + 1) * CHUNK);
          paintUploads();
          if (dead) return;
        }
      } catch (e) {
        up.retryAt[u.id] = Date.now() + 4000;
        // a gap resumes from the server's count; too fast waits a moment; the next poll shows a decline or a failure
        if ((e?.status === 409 && e.received != null) || e?.status === 429) up.retryAt[u.id] = Date.now() + 1600;
        else if (e?.status && e.status !== 409) flash(`Upload stopped: ${Core.errorText(e)}`);
      } finally { up.running.delete(u.id); }
    }
    const UPSTAT = { offered: "Waiting for the host. The file stays on this device.", accepted: "Accepted, starting", uploading: "Sending",
      done: "Sent", declined: "Not accepted", withdrawn: "Withdrawn", failed: "Failed" };
    function makeUpRow(host) {
      const li = E("li", "vf-uprow");
      // the host sees an offered picture before accepting it: the thumbnail opens the viewer
      const thumbImg = E("img"); thumbImg.alt = "";
      const thumb = btn("vf-imgbtn vf-upthumb"); thumb.append(thumbImg); thumb.hidden = true;
      thumb.onclick = () => openLb("att", null, 0, thumb, [{ src: li._u.thumb, title: li._u.file }], `Offered by ${disp(li._u.by)}, not accepted yet`);
      const ico = E("span", "vf-upico"); ico.append(icon("file"));
      const mid = E("div", "vf-upmid");
      const name = E("span", "vf-upname"), stat = E("span", "vf-upstat");
      const bar2 = E("div", "vf-upbar"); bar2.append(E("span"));
      bar2.setAttribute("role", "progressbar"); bar2.setAttribute("aria-valuemin", "0"); bar2.setAttribute("aria-valuemax", "100");
      mid.append(name, stat, bar2);
      const acts = E("div", "vf-upacts");
      const accept = btn("vf-btn vf-btn-primary vf-btn-sm", "Accept"), decline = btn("vf-btn vf-btn-ghost vf-btn-sm", "Decline");
      const withdraw = btn("vf-btn vf-btn-ghost vf-btn-sm", "Withdraw");
      acts.append(withdraw, decline, accept);
      li.append(thumb, ico, mid, acts);
      accept.onclick = () => Core.uploadAct(li._u.id, "accept").then(() => flash("Accepted. Their browser sends it now.")).catch(fail);
      decline.onclick = guarded(() => ({ title: `Decline ${li._u.file}?`, ok: "Decline file", body: `The file is not sent, and ${isMe(li._u.cid) ? "your" : disp(li._u.by) + "'s"} browser deletes its copy. ${li._u.status === "offered" ? "" : "What arrived so far is deleted. "}They can offer it again.` }),
        () => Core.uploadAct(li._u.id, "decline").then(() => flash("Declined. Their browser deletes it.")).catch(fail));
      withdraw.onclick = () => Core.uploadAct(li._u.id, "withdraw").then(() => { forget(li._u.id); flash("Withdrawn."); }).catch(fail);
      li._k = { thumb, thumbImg, ico, name, stat, bar2, accept, decline, withdraw, host };
      return li;
    }
    function fillUpRow(li, u) {
      const k = li._k, host = k.host, mine = isMe(u.cid);
      li._u = u;
      const bytes = Math.max(u.bytes || 0, mine ? up.sent[u.id] || 0 : 0), pct = u.size ? Math.floor((bytes / u.size) * 100) : 0;
      // the host decides on the server's extension, not on a name that may hide one
      k.name.textContent = `${u.file} · ${host ? (u.ext ? u.ext.toUpperCase() : "no extension") + " · " : ""}${sizeTxt(u.size)}`;
      if (host && u.thumb) { if (k.thumbImg.src !== u.thumb) k.thumbImg.src = u.thumb; k.thumb.hidden = false; k.ico.hidden = true; k.thumb.setAttribute("aria-label", `View larger: ${u.file}`); }
      else { k.thumb.hidden = true; k.ico.hidden = false; }
      const q = u.qid && qById(u.qid);
      const where = q ? ` · ${q.id}` : "";
      let s = UPSTAT[u.status] || u.status;
      if (u.status === "uploading" || (u.status === "accepted" && bytes)) s = `Sending, ${pct}%`;
      if (u.status === "failed" && u.reason) s = `Failed: ${u.reason}`;
      if (mine && u.status === "offered" && up.loaded && !up.files.has(u.id)) s = "This browser no longer has the file. Withdraw it and offer it again.";
      if (mine && (u.status === "accepted" || u.status === "uploading") && up.loaded && !up.files.has(u.id)) s = "Open this session in the browser that offered it to send it.";
      if (mine && up.memOnly.has(u.id) && u.status === "offered") s = "Waiting for the host. Keep this tab open: this browser cannot store it.";
      if (host && !mine) s = `${disp(u.by)}${where} · ${u.status === "done" ? "Saved on the host's computer" : s}`;
      else if (where) s += where;
      k.stat.textContent = s;
      const moving = u.status === "uploading" || u.status === "accepted";
      k.bar2.hidden = !(moving || u.status === "done");
      k.bar2.firstChild.style.transform = `scaleX(${u.status === "done" ? 1 : pct / 100})`;
      k.bar2.setAttribute("aria-valuenow", String(u.status === "done" ? 100 : pct)); k.bar2.setAttribute("aria-label", `${u.file} sent`);
      li.dataset.stat = u.status;
      k.accept.hidden = !(host && Core.me.isOwner && u.status === "offered");
      k.decline.hidden = !(host && Core.me.isOwner && ["offered", "accepted", "uploading"].includes(u.status));
      k.withdraw.hidden = !(mine && ["offered", "accepted", "uploading"].includes(u.status));
    }
    /** Progress moves between polls: repaint just the rows. */
    function paintUploads() {
      for (const list of [upStrip, apFiles, queueList]) for (const li of list.children) if (li._u) fillUpRow(li._k ? li : li, li._u);
    }
    // One attach picker on every form; the answer keeps a draft list per question, prefilled from my answer.
    ui.attDraft = {};
    const cSlot = attSlot(() => ui.cur, attachBtn, { get: () => ui.attDraft[ui.cur] ?? (myRec(ui.cur)?.att || []), set: l => { ui.attDraft[ui.cur] = l; } }, true);
    composer.insertBefore(cSlot.chips, ta);
    const apSlot = attSlot(() => (askGeneral() ? "" : apQWrap.s.value || ui.cur), apAttach);
    apForm.insertBefore(apSlot.chips, apNote);
    const askSlot = attSlot(() => ui.cur);
    askRow.prepend(askSlot.btn); askForm.insertBefore(askSlot.chips, askForm.querySelector(".vf-asknote"));
    const sugSlot = attSlot(() => ui.cur);
    sugRow.prepend(sugSlot.btn); sugForm.insertBefore(sugSlot.chips, sugRow);
    const chatSlot = attSlot(() => "");
    mForm.prepend(chatSlot.btn); chat.insertBefore(chatSlot.chips, mForm);
    const sameAtt = qid => attKey(ui.attDraft[qid] ?? (myRec(qid)?.att || [])) === attKey(myRec(qid)?.att || []);

    // ---------- notices for changes that concern me ----------
    function notices(S) {
      if (!Core.live || !Core.me.cid) return; // prime on real state, not the empty one before the first poll
      const seen = ui.notified, first = !seen._primed;
      const note = (key, val, msg, action) => { if (seen[key] === val) return; const had = key in seen; seen[key] = val; if (!first && (had || action?.isNew) && msg) flash(msg, action?.run ? action : null); };
      for (const u of S.myUploads || []) {
        note("u:" + u.id, u.status, u.status === "declined" ? `Not accepted: ${u.file}. It was deleted from this device.` : u.status === "done" ? `Sent: ${u.file}.` : u.status === "accepted" ? `The host accepted ${u.file}. Sending it now.` : "");
      }
      for (const m of S.myMergeRequests || []) {
        note("g:" + m.id, m.status, m.status === "approved" ? `The host joined you with ${m.toName}. Your earlier answers are yours again.` : m.status === "declined" ? `The host kept you as a new person.` : "");
      }
      const PL = { placed: "became a question", merged: "was merged into", suggested: "became a suggested change on", later: "was parked for later", notplaced: "was not placed", question: "became a question" };
      for (const i of S.ideas || []) if (isMe(i.cid)) note("i:" + i.id, i.status, PL[i.status] ? `Your proposal ${PL[i.status]}${i.qid && i.status !== "later" && i.status !== "notplaced" ? " " + i.qid : ""}${i.reason ? `: ${i.reason}` : "."}` : "");
      if (Core.me.isOwner) {
        for (const m of S.mergeRequests || []) note("gm:" + m.id, "seen", `${disp(m.fromName)} says they were ${disp(m.toName)} before. Approve it in Host.`, { label: "Open Host", run: () => { setMode("host"); if (phone.matches) setTab("host"); }, isNew: true });
        for (const u of S.uploads || []) if (u.status === "offered" && !isMe(u.cid)) note("uo:" + u.id, "seen", `${disp(u.by)} offered a file: ${u.file}.`, { label: "Open Host", run: () => { setMode("host"); if (phone.matches) setTab("host"); }, isNew: true });
        // What waits on me pops up once when it arrives; merges have their own line above.
        const WAIT = { join: i => `${disp(i.by)} asks to join.`, run: i => `${disp(i.by)} asked Claude ${ixWhere(i)}. Run it from the Inbox.`,
          share: i => `Claude answered ${ixWhere(i)}. Share it from the Inbox.`, report: i => `${disp(i.by)} reported a problem.` };
        for (const i of S.inbox || []) if (i.group === "waiting" && WAIT[i.kind]) note("iw:" + i.key, "seen", WAIT[i.kind](i), { label: "Open", run: () => openInboxItem(i), isNew: true });
      }
      // Item 11: a toast when Claude answers one of my requests, once I can open the answer.
      for (const i of S.inbox || []) {
        if (i.group !== "mine") continue;
        const open = i.status === "answered" || i.status === "shared";
        note("ix:" + i.key, i.status, open ? `Claude answered your request ${ixWhere(i)}` : "", open ? { label: "Open", run: () => openInboxItem(i) } : null);
      }
      if (Core.adopted && !seen._adopted) { seen._adopted = true; flash(`Signed in as ${Core.adopted} on this device.`); }
      if (Core.mergeAsked && !seen._asked) { seen._asked = true; flash(`Asked the host to join you with ${Core.mergeAsked.name}. You continue as ${Core.me.name} until they do.`); }
      seen._primed = true;
    }

    // ---------- empty session ----------
    evGoal.onsubmit = e => {
      e.preventDefault();
      const v = evGoalIn.value.trim(); if (!v) return evGoalIn.focus();
      evGoalSave.disabled = true;
      Core.setGoal(v).then(() => { evGoalIn.value = ""; ui.evGoalEdit = false; flash("Goal saved. Everyone sees it under the title."); }).catch(fail).finally(() => { evGoalSave.disabled = false; });
    };
    evCopy.onclick = async () => {
      store.put("vf-share-ack", evShareIn.value);
      try { await navigator.clipboard.writeText(evShareIn.value); flash("Link copied. Send it to the people you want to ask."); }
      catch { evShareIn.focus(); evShareIn.select(); flash("Press Ctrl+C to copy the selected link."); }
    };
    evPropose.onclick = () => openPropose();
    function renderEmpty(S) {
      const owner = Core.me.isOwner, mod = Core.canModerate(), goal = S.goal || "", here = S.presence.filter(p => !isMe(p.cid));
      emptyV.dataset.who = owner ? "host" : "guest";
      evTitle.textContent = owner ? (goal ? "Invite people, then open round 1" : "Start with a goal") : "Waiting for the host to start the first round";
      evNote.textContent = owner ? (goal ? "Your goal is set. Share the link; round 1 opens when Claude publishes its first questions."
        : "One line on what this session should settle. Everyone sees it under the title, and Claude reads it with every round.")
        : "Questions show here as soon as round 1 opens. Nothing to do until then, unless you have a question to propose.";
      evGoal.hidden = !owner || (!!goal && !ui.evGoalEdit) || !v8();
      evGoalNow.hidden = !goal;
      evGoalNow.textContent = goal ? `Goal: ${goal}` : "";
      evShare.hidden = !mod;
      const url = Core.guestLink();
      if (evShareIn.value !== url) evShareIn.value = url;
      avStack(evHereAv, here, 6, 24, true);
      evHereTxt.textContent = here.length ? `${names(here)} ${here.length > 1 ? "are" : "is"} here` : owner ? "Nobody else here yet" : "";
      evHere.hidden = !here.length && !owner;
      evNext.hidden = owner;
      evNext.textContent = Core.owner() ? `${disp(Core.owner().name)} is here and setting up.` : "The host is not here right now.";
      evPropose.hidden = (!!S.ended && !owner) || !!S.youRemoved;
      if (S.youWaiting) { // Approve new joins: nothing to read or do until the host lets this person in
        evTitle.textContent = "Waiting for the host to let you in";
        evNote.textContent = "The host approves each new person. This page opens by itself once they do; keep it open.";
        evNext.hidden = evPropose.hidden = evHere.hidden = true;
      }
    }

    // ---------- events ----------
    qPrev.onclick = () => step(-1);
    qNext.onclick = () => step(1);
    goalEdit.onclick = startGoalEdit; goalAdd.onclick = startGoalEdit; hGoalEdit.onclick = () => { if (!titles.offsetParent) return; startGoalEdit(); };
    on(goalInput, "keydown", e => { if (e.key === "Enter") { e.preventDefault(); endGoalEdit(true); } if (e.key === "Escape") { e.stopPropagation(); endGoalEdit(false); goalEdit.focus(); } });
    on(goalInput, "blur", () => endGoalEdit(true));
    expandBtn.onclick = () => {
      const nums = [...new Set([...Core.state.questions.map(roundOf), curRound().current])];
      if (expandBtn._open) { ui.treeClosed = new Set(nums); setOpenRounds([]); }
      else { ui.treeClosed.clear(); setOpenRounds(nums); }
      render();
    };
    askBtn.onclick = () => (ui.pop === askMenu ? closePop() : openPop(askMenu, askBtn));
    citeBtn.onclick = () => (ui.pop === citePop ? closePop() : openPop(citePop, citeBtn));
    // Picking another option moves my pick (one vote per question); only Undo clears it. Pressing my own pick does nothing.
    // A comment rides along with a new pick; my own option's text does not (it was the option, not a comment).
    const keptComment = (q, rec) => (q.format === "choice" && !rec?.other ? rec?.text || "" : "");
    const pickOpt = (optId, qid = ui.cur) => {
      const rec = myRec(qid), q = qById(qid);
      if (!q || readOnly(q) || Core.lockOf(qid) || rec?.pick === optId) return;
      if (optionsOf(q).find(x => x.id === optId)?.other) return openOther(qid);
      const label = optionsOf(q).find(x => x.id === optId)?.label || "it";
      Core.pick(qid, optId, keptComment(q, rec)).then(() => { announce(rec?.pick ? `Your choice moved to ${label}.` : `You picked ${label}.`); armAdvance(qid); }).catch(fail);
    };
    const clearPick = (qid = ui.cur) => {
      const rec = myRec(qid), q = qById(qid);
      if (!q || !rec?.pick || readOnly(q) || Core.lockOf(qid)) return;
      Core.pick(qid, "", keptComment(q, rec)).then(() => announce("Your choice is cleared.")).catch(fail);
    };
    confirmView.onclick = () => openLb("confirm", ui.cur, 0, confirmView);
    yesBtn.onclick = () => pickOpt("opt-yes");
    noBtn.onclick = () => pickOpt("opt-no");
    cfUndo.onclick = () => { (myRec(ui.cur)?.pick === "opt-no" ? noBtn : yesBtn).focus({ preventScroll: true }); clearPick(); };
    elseBtn.onclick = () => { if (ta.disabled) return; if (phone.matches) setTab("answer"); ta.focus(); };
    hSend.onclick = () => roundAction(hSend);
    hCancel.onclick = () => cancelSend.click();
    hReset.onclick = guarded(() => ({ title: `Reset round ${curRound().current}?`, body: "Use this only if Claude stopped responding. The round reopens for answers and votes, and whatever Claude is still preparing for it will be refused. Send it again when it is ready.", ok: "Reset round", safe: "Keep waiting" }),
      () => Core.resetRound().then(() => flash("Round reopened. Send it again when it is ready.")).catch(fail));
    hShare.onclick = () => openPop(sharePop, hShare);
    hSettings.onclick = () => openPop(settingsPop, hSettings);
    hNewGuest.onclick = () => newGuestBtn.click();
    hNewOwner.onclick = () => newOwnerBtn.click();
    hEnd.onclick = () => endBtn.click();
    follow.onclick = () => setFollow(!following());
    prevQ.onclick = () => step(-1);
    nextQ.onclick = () => step(1);
    titleEdit.onclick = startTitleEdit;
    on(titleInput, "keydown", e => { if (e.key === "Enter") { e.preventDefault(); endTitleEdit(true); } if (e.key === "Escape") { e.stopPropagation(); endTitleEdit(false); titleEdit.focus(); } });
    on(titleInput, "blur", () => endTitleEdit(true));
    composer.onsubmit = e => { e.preventDefault(); submit(); };
    clearBtn.onclick = () => { ta.value = ""; ui.dirty = true; ui.drafts[ui.cur] = ""; Core.setTyping(); grow(ta); render(); ta.focus(); };
    on(ta, "input", () => {
      ui.dirty = true; ui.drafts[ui.cur] = ta.value; Core.setTyping(); renderComposer(); stopAdvance(); // writing a comment stays
      // in the phone sheet, writing at the end keeps the last line (the caret) in view
      if (composer.classList.contains("vf-composer-sheet") && ta.selectionEnd === ta.value.length) ta.scrollTop = ta.scrollHeight;
    });
    on(ta, "keydown", e => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); submit(); } });
    // Triage 18: on a phone, writing opens the answer as a full-height sheet: the text pre-filled, Cancel and Save on
    // top, and the field filling the visual viewport, so the keyboard never covers it.
    on(ta, "focus", () => {
      if (!phone.matches || ta.disabled || composer.classList.contains("vf-composer-sheet")) return;
      ui.sheetFrom = ta.value;
      sheetTitle.textContent = Core.myAnswer(ui.cur) ? "Edit your answer" : qById(ui.cur)?.text || "Your answer";
      composer.classList.add("vf-composer-sheet"); root.dataset.sheet = "";
      renderComposer();
      requestAnimationFrame(() => ta.setSelectionRange(ta.value.length, ta.value.length));
    });
    // Triage 21: on a touch screen a sideways swipe in Focus moves to the previous or next question; not from inside
    // a field, the ranking (it drags) or anything that scrolls sideways.
    const SW = { x: 0, y: 0, t: 0, ok: false };
    on(scroll, "touchstart", e => {
      const t = e.touches[0], el = e.target;
      SW.ok = e.touches.length === 1 && !el.closest("input, textarea, select, .vf-rank, .vf-reflist, .vf-scale-row, [data-noswipe]");
      for (let p = el; SW.ok && p && p !== scroll; p = p.parentElement) if (p.scrollWidth > p.clientWidth + 1 && /auto|scroll/.test(getComputedStyle(p).overflowX)) SW.ok = false;
      Object.assign(SW, { x: t.clientX, y: t.clientY, t: Date.now() });
    }, { passive: true });
    on(scroll, "touchend", e => {
      if (!SW.ok || ui.mode !== "focus") return;
      const t = e.changedTouches[0], dx = t.clientX - SW.x, dy = t.clientY - SW.y;
      if (Math.abs(dx) > 70 && Math.abs(dx) > 2 * Math.abs(dy) && Date.now() - SW.t < 700) step(dx < 0 ? 1 : -1);
    }, { passive: true });
    sheetCancel.onclick = () => {
      ta.value = ui.sheetFrom ?? ta.value; ui.drafts[ui.cur] = ta.value; ui.dirty = ta.value !== Core.myAnswer(ui.cur);
      closeSheet(); ta.blur(); render();
    };
    on(composer, "keydown", e => {
      if (!composer.classList.contains("vf-composer-sheet")) return;
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); sheetCancel.click(); return; }
      if (e.key !== "Tab") return;
      const f = [...composer.querySelectorAll("button, textarea")].filter(x => !x.disabled && x.offsetParent), i = f.indexOf(document.activeElement);
      if (!f.length) return;
      e.preventDefault(); e.stopPropagation();
      f[(i + (e.shiftKey ? -1 : 1) + f.length) % f.length].focus();
    });
    on(root, "input", e => { if (e.target.matches?.("textarea.vf-ta")) grow(e.target); });
    lockBtn.onclick = () => {
      if (lockBtn.getAttribute("aria-disabled") === "true") return flash(lockBtn.title);
      lockTopAnswer();
    };
    unlockBtn.onclick = guarded(() => {
      const n = openSugs(ui.cur).length;
      return { title: `Unlock ${ui.cur}?`, ok: "Unlock", body: `The decided answer opens up again and people can vote and answer.${n ? ` ${n} open suggestion${n > 1 ? "s" : ""} will be closed: kept and shown, but no longer open.` : ""} Questions that build on this one are flagged for review.` };
    }, () => Core.unlock(ui.cur).then(r => {
      const bits = [r.closed ? `${r.closed} open suggestion${r.closed > 1 ? "s" : ""} kept as closed` : "", r.flagged?.length ? `${r.flagged.join(", ")} flagged for review` : ""].filter(Boolean);
      flash(`Unlocked.${bits.length ? " " + bits.join("; ") + "." : ""}`);
    }).catch(fail));
    editBtn.onclick = () => { ui.editFrom = null; editTa.value = Core.lockOf(ui.cur)?.text || ""; editForm.hidden = false; grow(editTa); editTa.focus(); };
    editCancel.onclick = () => { editForm.hidden = true; ui.editFrom = null; };
    editForm.onsubmit = e => {
      e.preventDefault();
      const text = editTa.value.trim(); if (!text) return;
      editSave.disabled = true;
      Core.lockEdit(ui.cur, text, ui.editFrom || undefined).then(() => { editForm.hidden = true; ui.editFrom = null; }).catch(fail).finally(() => { editSave.disabled = false; });
    };
    on(editTa, "input", () => Core.setTyping());
    sugBtn.onclick = () => { ui.suggestOpen = true; sugForm.hidden = false; sugTa.value ||= Core.lockOf(ui.cur)?.text || ""; grow(sugTa); sugTa.focus(); };
    sugCancel.onclick = () => { ui.suggestOpen = false; sugForm.hidden = true; };
    on(sugTa, "input", () => Core.setTyping());
    sugForm.onsubmit = e => {
      e.preventDefault();
      const text = sugTa.value.trim(); if (!text) return;
      sugSend.disabled = true;
      Core.suggest(ui.cur, text, sugNote.value.trim(), attExtra(sugSlot)).then(() => {
        sugTa.value = ""; sugNote.value = ""; sugSlot.clear(); sugForm.hidden = true; ui.suggestOpen = false; flash("Suggestion sent.");
      }).catch(fail).finally(() => { sugSend.disabled = false; });
    };
    reviewClear.onclick = () => Core.clearReview(ui.cur).then(() => flash("Marked reviewed.")).catch(fail);
    askBtn.onclick = () => { ui.askOpen = !ui.askOpen; renderAsk(); if (ui.askOpen) askTa.focus(); };
    askCancel.onclick = () => { ui.askOpen = false; renderAsk(); askBtn.focus(); };
    askForm.onsubmit = e => {
      e.preventDefault();
      const text = askTa.value.trim(); if (!text) return askTa.focus();
      askSend.disabled = true;
      Core.request(ui.cur, guestKind(ui.askKind, ui.askWeb), text, attExtra(askSlot)).then(() => {
        askTa.value = ""; askSlot.clear(); ui.askOpen = false; ui.askWeb = false; renderAsk();
        flash(Core.me.isOwner ? "Sent to Claude. The answer shows on the question and in your Inbox." : "Sent to the host. It runs once they press Run.");
      }).catch(fail).finally(() => { askSend.disabled = false; });
    };
    on(board, "scroll", edges, { passive: true });
    on(window, "resize", () => { edges(); if (toast.classList.contains("vf-on")) placeToast(); if (ui.pop === PP.pop || ui.pop === RQ.pop) placePanel(ui.pop); measureAll(); });
    arrL.onclick = () => board.scrollBy({ left: -colStep(), behavior: smooth() });
    arrR.onclick = () => board.scrollBy({ left: colStep(), behavior: smooth() });
    fab.onclick = () => setChat(!ui.chatOpen);
    chatClose.onclick = () => { setChat(false); fab.focus(); };
    mForm.onsubmit = e => { e.preventDefault(); sendChat(); };
    const counter = (el, field, from) => { const n = field.value.length; el.textContent = n >= from ? `${n} / ${field.maxLength}` : ""; };
    on(mInput, "input", () => { Core.setChatTyping(); counter(mCount, mInput, 1500); });
    /** The Propose form, from any way in; `text` prefills it. Focus goes back where it came from, else to the rail's button. */
    function openPropose(text) {
      const from = document.activeElement;
      if (ui.chatOpen) setChat(false);
      if (text != null) propTa.value = text;
      openPop(proposePop, proposeBtn);
      proposePop._return = from;
    }
    const propBack = () => { const r = proposePop._return; closePop(); (r?.isConnected && r.offsetParent ? r : proposeBtn).focus({ preventScroll: true }); };
    proposeBtn.onclick = () => (ui.pop === proposePop ? closePop() : openPropose());
    apPropose.onclick = () => openPropose();
    propCancel.onclick = propBack;
    proposePop.onsubmit = e => {
      e.preventDefault();
      const text = propTa.value.trim(); if (!text) return propTa.focus();
      propSend.disabled = true;
      Core.idea(text).then(() => { propTa.value = ""; propBack(); flash("Proposed. You can see it under Your proposals."); })
        .catch(fail).finally(() => { propSend.disabled = false; });
    };
    // ---------- Report a problem ----------
    const REP = { ctx: null, image: "", size: null };
    const VIEW_WORD = { focus: "Focus", compare: "Compare", tree: "Tree", host: "Host", prototype: "Prototype" };
    function paintSent() {
      const c = REP.ctx, v = c.visualViewport, x = n => Math.round(n);
      const rows = [`View: ${VIEW_WORD[c.view] || c.view}${c.tab ? `, ${c.tab} tab` : ""}`,
        ...(c.qid ? [`Question: ${c.qid}${c.round != null ? `, round ${c.round}` : ""}`] : []),
        `Device: ${c.device}, ${BROWSER_NAME[c.browser] || "other browser"}`,
        `Screen: ${c.viewport.w} × ${c.viewport.h}${v ? `; visible ${x(v.w)} × ${x(v.h)} at ${v.scale}×` : ""}`,
        ...(c.build ? [`Page version: ${c.build}`] : []),
        c.errors.length ? `Recent errors: ${c.errors.join("; ")}` : "Recent errors: none",
        ...(REP.image ? [`Your screenshot, ${REP.size.w} × ${REP.size.h}`] : []),
        "Not sent: your answers, the chat, this page's address or your sign-in"];
      repSent.replaceChildren(...rows.map(t => E("li", null, t)));
    }
    function openReport(anchor) {
      REP.ctx = Core.reportContext(); // where the page was when the problem showed, before this form opened
      repErr.textContent = "";
      paintSent();
      openPop(reportPop, anchor || (keysBtn.offsetParent ? keysBtn : tabBtns.more.offsetParent ? tabBtns.more : top));
    }
    /** A screenshot re-encoded in this browser: at most 1600 px on its long edge and 512 KB, WebP where the browser
     *  writes it, else JPEG. */
    async function shrinkShot(file) {
      const bmp = await createImageBitmap(file), k = Math.min(1, 1600 / Math.max(bmp.width, bmp.height));
      const c = E("canvas"); c.width = Math.max(1, Math.round(bmp.width * k)); c.height = Math.max(1, Math.round(bmp.height * k));
      c.getContext("2d").drawImage(bmp, 0, 0, c.width, c.height); bmp.close?.();
      for (const [type, q] of [["image/webp", 0.85], ["image/webp", 0.6], ["image/jpeg", 0.7], ["image/jpeg", 0.45], ["image/jpeg", 0.3]]) {
        const url = c.toDataURL(type, q), head = `data:${type};base64,`;
        if (url.startsWith(head) && (url.length - head.length) * 3 / 4 <= 512 * 1024) return { url, w: c.width, h: c.height };
      }
      throw new Error("too large");
    }
    const dropShot = () => { REP.image = ""; REP.size = null; repFile.value = ""; repShot.hidden = repDrop.hidden = true; repShot.removeAttribute("src"); repFileLabel.textContent = "Add a screenshot"; paintSent(); };
    on(repFile, "change", async () => {
      const f = repFile.files?.[0]; if (!f) return;
      repErr.textContent = "";
      try {
        if (!["image/png", "image/jpeg", "image/webp"].includes(f.type)) throw new Error("type");
        const s = await shrinkShot(f);
        REP.image = s.url; REP.size = { w: s.w, h: s.h };
        repShot.src = s.url; repShot.hidden = repDrop.hidden = false; repFileLabel.textContent = "Change screenshot";
        paintSent();
      } catch { dropShot(); repErr.textContent = "That picture could not be added. Use a PNG, JPEG or WebP screenshot."; }
    });
    repDrop.onclick = dropShot;
    on(repTa, "input", () => { repCount.textContent = `${repTa.value.length} / ${repTa.maxLength}`; });
    const repBack = () => { const r = reportPop._return || reportPop._anchor; closePop(); if (r?.isConnected && r.offsetParent) r.focus({ preventScroll: true }); };
    repCancel.onclick = repBack;
    reportPop.onsubmit = e => {
      e.preventDefault();
      const text = repTa.value.trim(); if (!text) return repTa.focus();
      repSend.disabled = true; repErr.textContent = "";
      Core.report(text, REP.ctx, REP.image).then(() => { repTa.value = ""; repCount.textContent = `0 / ${repTa.maxLength}`; dropShot(); repBack(); flash("Report sent. The host and Claude will look at it."); })
        .catch(x => { repErr.textContent = `Not sent: ${x?.message || Core.errorText(x)}`; }).finally(() => { repSend.disabled = false; });
    };
    function makeMyRep() {
      const li = E("li", "vf-pitem vf-myrep");
      const head = E("div", "vf-rhead2"), status = E("span", "vf-chip vf-myrep-status"), when = E("span", "vf-meta");
      head.append(status, E("span", "vf-spacer"), when);
      const text = E("p", "vf-myrep-text"), adds = E("ul", "vf-myrep-adds"); adds.setAttribute("role", "list");
      const form = E("form", "vf-myrep-add"), ta = E("textarea", "vf-ta"), file = E("input", "vf-rep-file");
      ta.rows = 2; ta.maxLength = 2000; ta.setAttribute("aria-label", "Add a line to this report"); ta.placeholder = "Add a line";
      file.type = "file"; file.accept = "image/png,image/jpeg,image/webp"; file.id = "vf-myrep-file-" + Math.random().toString(36).slice(2, 10);
      const pick = E("label", "vf-btn vf-btn-ghost vf-btn-sm vf-rep-add", "Add a screenshot"); pick.htmlFor = file.id;
      const shot = E("img", "vf-rep-shot"); shot.alt = "Your screenshot"; shot.hidden = true;
      const send = E("button", "vf-btn vf-btn-primary vf-btn-sm", "Add"); send.type = "submit";
      const err = E("p", "vf-rep-err"); err.setAttribute("role", "alert");
      const row = E("div", "vf-crow"); row.append(pick, E("span", "vf-spacer"), send);
      form.append(ta, file, row, shot, err);
      li.append(head, text, adds, form);
      li._k = { status, when, text, adds, form, ta, file, pick, shot, send, err, image: "" };
      const k = li._k;
      on(file, "change", async () => {
        const f = file.files?.[0]; if (!f) return;
        err.textContent = "";
        try {
          if (!["image/png", "image/jpeg", "image/webp"].includes(f.type)) throw new Error("type");
          const sh = await shrinkShot(f);
          k.image = sh.url; shot.src = sh.url; shot.hidden = false; pick.textContent = "Change screenshot";
        } catch { k.image = ""; file.value = ""; shot.hidden = true; err.textContent = "That picture could not be added. Use a PNG, JPEG or WebP screenshot."; }
      });
      form.onsubmit = e => {
        e.preventDefault();
        const t = ta.value.trim();
        if (!t && !k.image) return ta.focus();
        send.disabled = true; err.textContent = "";
        Core.addToReport(li._r.id, t, k.image).then(() => {
          ta.value = ""; k.image = ""; file.value = ""; shot.hidden = true; shot.removeAttribute("src"); pick.textContent = "Add a screenshot";
          flash("Added to your report. The host sees it.");
        }).catch(x => { err.textContent = `Not added: ${x?.message || Core.errorText(x)}`; }).finally(() => { send.disabled = false; });
      };
      return li;
    }
    function fillMyRep(li, r) {
      const k = li._k;
      li._r = r; li.dataset.status = r.status;
      k.status.textContent = REP_WORD[r.status] || r.status;
      k.when.textContent = ago(r.ts) === "now" ? "just now" : `${ago(r.ts)} ago`;
      k.text.textContent = r.text;
      const lines = r.adds.map(a => E("li", null, [a.text, a.image ? "Screenshot added" : ""].filter(Boolean).join(" · ")));
      if (k.adds.childElementCount !== lines.length || [...k.adds.children].some((c, i) => c.textContent !== lines[i].textContent)) k.adds.replaceChildren(...lines);
      k.adds.hidden = !lines.length;
      k.form.hidden = r.status === "resolved";
    }
    function renderMyReps(S) {
      const mine = (S.myReports || []).slice().sort((a, b) => b.ts - a.ts);
      msMyReps.hidden = helpMyReps.hidden = !mine.length;
      if (myRepPop.hidden) return;
      sync(myRepList, mine, r => r.id, makeMyRep, fillMyRep);
    }
    newGuestBtn.onclick = guarded({ title: "Make a new guest link?", body: "The guest link you shared stops working: nobody new can join with it. People already here stay. You share the new link again.", ok: "Make new guest link" },
      () => Core.newGuestLink().then(() => { openPop(sharePop, shareBtn.offsetParent ? shareBtn : gear); flash("New guest link made. Share it again."); }).catch(fail));
    newOwnerBtn.onclick = guarded({ title: "Make a new owner link?", body: "Your current owner link stops working everywhere, including other devices and tabs that use it. This page reloads with the new one: save it, or you lose host access.", ok: "Make new owner link" },
      () => Core.newOwnerLink().catch(fail));
    const laterItems = () => Core.state.ideas.filter(i => i.status === "later");
    const laterLine = n => `${n} Later item${n === 1 ? "" : "s"} will become tracker item${n === 1 ? "" : "s"}`;
    endBtn.onclick = guarded(() => !Core.state.ended && { title: "End the session?", ok: "End session", body: `Guests can no longer answer, vote, chat or post; they see the final tree. You can reopen it later.${laterItems().length ? " " + laterLine(laterItems().length) + "." : ""}` }, () => {
      const on = !Core.state.ended, n = laterItems().length;
      Core.endSession(on).then(() => { closePop(); flash(on ? `Session ended. Guests now see the final tree.${n ? " " + laterLine(n) + "." : ""}` : "Session reopened."); }).catch(fail);
    });
    skip.onclick = e => { e.preventDefault(); if (phone.matches) setTab("answer"); setMode("focus"); (ta.disabled ? qText : ta).focus(); };
    on(mInput, "keydown", e => { if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); sendChat(); } });
    gear.onclick = () => (ui.pop === settingsPop ? closePop() : openPop(settingsPop, gear));
    shareBtn.onclick = () => (ui.pop === sharePop ? closePop() : openPop(sharePop, shareBtn));
    keysBtn.onclick = () => (ui.pop === keysPop ? closePop() : openPop(keysPop, keysBtn));
    propRow.onclick = () => (ui.pop === PP.pop ? closePop() : openPanel(PP.pop, propRow));
    reqRow.onclick = () => (ui.pop === RQ.pop ? closePop() : openPanel(RQ.pop, reqRow));
    runAllBtn.onclick = runAllShown;
    confirmYes.onclick = doSend;
    confirmNo.onclick = () => { const a = confirmPop._anchor; closePop(); a?.focus(); };
    rdClose.onclick = closeReader;
    copyBtn.onclick = async () => {
      store.put("vf-share-ack", shareField.value);
      try { await navigator.clipboard.writeText(shareField.value); copyBtn.textContent = "Copied"; }
      catch { shareField.focus(); shareField.select(); copyBtn.textContent = "Press Ctrl+C"; }
      render();
      setTimeout(() => { copyBtn.textContent = "Copy link"; }, 1800);
    };
    nativeShare.onclick = () => navigator.share?.({ title: "Join the interview", url: shareField.value }).catch(() => {});
    on(document, "pointerdown", e => {
      if (ui.pop && !dlgOpen() && !ui.pop.contains(e.target) && !ui.pop._anchor?.contains(e.target) && !e.target.closest?.("[data-pid]")) closePop();
    });
    const vis = () => { if (document.visibilityState === "hidden") markSeen(ui.cur); };
    on(document, "visibilitychange", vis);
    // An on-screen keyboard is up (core.js measures it): phones give its room to the field, not the tab bar.
    const kbSync = () => {
      const was = root.hasAttribute("data-kb"), now = "kb" in document.documentElement.dataset;
      root.toggleAttribute("data-kb", now);
      if (was !== now) { syncModal(); if (ui.mention) paintMention(); }
      revealAskField(now && !was);
      if (now && !was && ui.pop && !ui.pop._kbRead && coarse.matches) { ui.pop._kbRead = true; kbReadout(ui.pop); }
    };
    // Once per sheet open, the keyboard coming up on a touch device logs where the viewport, the app and the sheet
    // sit (server.log, kind layout), so a gap seen on a real phone can be measured.
    function kbReadout(sheet) {
      const vv = window.visualViewport, de = document.documentElement, dcs = getComputedStyle(de), cs = getComputedStyle(sheet), r = sheet.getBoundingClientRect();
      const probe = E("div"); probe.style.cssText = "position:fixed;visibility:hidden;padding-bottom:env(safe-area-inset-bottom,0px)";
      document.body.append(probe);
      const safe = getComputedStyle(probe).paddingBottom;
      probe.remove();
      const n = v => Math.round(v * 100) / 100;
      Core.reportLayout({ sheet: [...sheet.classList].find(c => c !== "vf-pop") || "pop", innerWidth: innerWidth, innerHeight: innerHeight,
        vvWidth: n(vv?.width), vvHeight: n(vv?.height), vvOffsetTop: n(vv?.offsetTop), vvPageTop: n(vv?.pageTop), vvScale: n(vv?.scale),
        clientHeight: de.clientHeight, kb: dcs.getPropertyValue("--kb").trim(), vvTop: dcs.getPropertyValue("--vv-top").trim(), vvH: dcs.getPropertyValue("--vv-h").trim(),
        dataKb: "kb" in de.dataset, sheetTop: n(r.top), sheetBottom: n(r.bottom), sheetHeight: n(r.height), paddingBottom: cs.paddingBottom,
        marginBottom: cs.marginBottom, bottom: cs.bottom, transform: cs.transform, safeBottom: safe, screenHeight: screen.height });
    }
    // In the Ask Claude sheet, focusing its field or the keyboard coming up puts the sheet at its top: the label and the
    // field first, the Send row sticky under them. After that, as the keyboard moves or the field grows, the
    // label and the field's first 3 lines stay seen above that row; where even that does not fit, the field's top does.
    const revealAskField = toTop => {
      const f = document.activeElement;
      if (!f?.matches?.("textarea") || !apForm.contains(f)) return;
      if (toTop) apScroll.scrollTop = 0;
      const band = seenBand(apScroll, f), cs = getComputedStyle(f), fr = f.getBoundingClientRect(), lr = apLabel.getBoundingClientRect();
      const lines = parseFloat(cs.paddingTop) + parseFloat(cs.borderTopWidth) + 3 * (parseFloat(cs.lineHeight) || 1.5 * parseFloat(cs.fontSize));
      const top = Math.min(lr.top, fr.top), bottom = Math.min(fr.bottom, fr.top + lines);
      if (bottom - top <= band.bottom - band.top) scrollInto(apScroll, top, bottom, band);
      else scrollInto(apScroll, fr.top, fr.top + band.bottom - band.top, band);
    };
    on(askPanel, "focusin", e => { if (e.target === apTa) revealAskField(true); });
    on(window, "core-viewport", kbSync);
    const sysTheme = () => applyTheme();
    lightOS.addEventListener("change", sysTheme); offs.push(() => lightOS.removeEventListener("change", sysTheme));

    // person cards
    let hoverT = 0, hideT = 0;
    const pidEl = t => t?.closest?.("[data-pid]");
    function showCard(el, pinned) {
      clearTimeout(hoverT); clearTimeout(hideT);
      if (pinned) closePop();
      ui.pcard = { pid: el.dataset.pid, name: el.dataset.name || "", anchor: el, pinned, sig: "" };
      ui.mergeFrom = ""; ui.mergeTo = "";
      pcard.hidden = false;
      fillPcard();
      placeNear(pcard, el);
      if (pinned) { ui.pop = pcard; pcard._anchor = el; pcard.querySelector("button")?.focus({ preventScroll: true }); }
    }
    function hideCard() {
      clearTimeout(hoverT);
      if (!ui.pcard) return;
      if (ui.pop === pcard) closePop(); else { pcard.hidden = true; ui.pcard = null; }
    }
    on(root, "pointerover", e => {
      if (e.pointerType !== "mouse" || (ui.pop && ui.pop !== pcard) || ui.pcard?.pinned) return;
      if (e.target.closest(".vf-pcard")) { clearTimeout(hideT); return; }
      const el = pidEl(e.target); if (!el) return;
      clearTimeout(hideT);
      if (ui.pcard?.anchor === el) return;
      clearTimeout(hoverT); hoverT = setTimeout(() => showCard(el, false), 280);
    });
    on(root, "pointerout", e => {
      if (e.pointerType !== "mouse") return;
      const from = pidEl(e.target) || e.target.closest(".vf-pcard"); if (!from) return;
      const to = e.relatedTarget;
      if (to && (from.contains(to) || pcard.contains(to) || ui.pcard?.anchor?.contains(to))) return;
      clearTimeout(hoverT);
      if (ui.pcard && !ui.pcard.pinned) hideT = setTimeout(hideCard, 160);
    });
    on(root, "focusin", e => {
      const el = e.target;
      if (el.dataset?.pid && !ui.pop && !el.closest(".vf-pcard") && el.matches(":focus-visible")) showCard(el, false);
    });
    on(root, "focusout", e => { if (ui.pcard && !ui.pcard.pinned && e.target.dataset?.pid) hideCard(); });
    on(root, "click", e => {
      const el = pidEl(e.target);
      if (!el || el.closest(".vf-pcard")) return;
      const host = el.closest("button");
      if (host && !host.classList.contains("vf-person")) return; // avatars inside other buttons belong to that button
      e.preventDefault();
      if (ui.pop === pcard && ui.pcard?.pid === el.dataset.pid) return closePop();
      showCard(el, true);
    });
    on(root, "keydown", e => {
      if ((e.key === "Enter" || e.key === " ") && e.target.dataset?.pid && e.target.getAttribute("role") === "button") { e.preventDefault(); showCard(e.target, true); }
    });

    function roleOf(pid) {
      const S = Core.state;
      if ((S.ownerPid && pid === S.ownerPid) || S.presence.some(p => p.cid === pid && p.owner)) return "Host";
      if (S.leaders.includes(pid)) return "Leader";
      if (S.trusted.includes(pid)) return "Trusted";
      return "Guest";
    }
    const COLOR_NAMES = ["Pink", "Blue", "Green", "Amber", "Violet", "Red", "Cyan", "Orange", "Lime", "Magenta"];
    const nameOf = (pid, fallback = "") => Core.state.people?.[pid]?.name || Core.state.presence.find(p => p.cid === pid)?.name || fallback || "Someone";
    function fillPcard() {
      const c = ui.pcard; if (!c) return;
      const S = Core.state, pid = c.pid, name = nameOf(pid, c.name), here = S.presence.find(p => p.cid === pid);
      const role = roleOf(pid), joined = S.people?.[pid]?.ts, me = isMe(pid), owner = Core.me.isOwner;
      const q = here?.q && qById(here.q);
      const sig = JSON.stringify([pid, name, role, here?.q, q?.text, here?.away, here && awayFor(here), me && Core.isAway(), joined, c.pinned, ui.mergeFrom, ui.mergeTo, me && [myTheme(), sessionTheme(), ui.renaming, claudePref(), st().hideClaude, !!prefs().autoAdvance], Core.colorIdOf(pid), owner, S.leaders, S.trusted, owner && ui.mergeFrom && Object.keys(S.people || {})]);
      if (c.sig === sig) return;
      const refocus = pcard.contains(document.activeElement) ? document.activeElement.dataset.k : null;
      c.sig = sig;
      const head = E("div", "vf-pc-head");
      const who = E("div", "vf-pc-who");
      who.append(E("span", "vf-pc-name", disp(name) + (me ? " (you)" : "")), E("span", `vf-role vf-role-${role.toLowerCase()}`, role));
      const big = Core.avatar(pid, name, 34);
      head.append(big, who);
      const facts = E("dl", "vf-pc-facts");
      const fact = (k, v) => facts.append(E("dt", null, k), E("dd", null, v));
      fact("Now", here ? `${here.away ? `Away${awayFor(here)}. ` : ""}${q ? `${q.id}: ${q.text}` : "Here, between questions"}` : "Offline: not here right now");
      if (joined) fact("Joined", ago(joined) === "now" ? "just now" : `${ago(joined)} ago`);
      const parts = [head, facts];
      const k = (b, key) => { b.dataset.k = key; return b; };
      if (me) {
        const t = themePicker(() => ({ ...sessionTheme(), ...myTheme() }), patch => { setPrefs({ ...(patch.mode ? { theme: patch.mode } : {}), ...(patch.accent ? { accent: patch.accent } : {}) }); applyTheme(); fillPcard(); });
        t._paint();
        t.querySelectorAll("button").forEach((b, i) => k(b, "t" + i));
        parts.push(E("h3", "vf-pop-sub", "Theme, just for you"), t);
        // C40: my color, one of ten; everyone sees it on my avatar.
        const mine = Core.colorIdOf(pid), colors = E("div", "vf-pcolors"); colors.setAttribute("role", "group"); colors.setAttribute("aria-label", "Your color");
        Core.COLORS.forEach((id, i) => {
          const nm = COLOR_NAMES[i], b = k(btn("vf-pcolor"), "pc" + id);
          b.style.setProperty("--av", `var(--pc-${id})`); b.title = nm;
          b.setAttribute("aria-label", nm); b.setAttribute("aria-pressed", String(mine === id));
          b.onclick = () => Core.setColor(id).then(() => flash(`Your color is now ${nm.toLowerCase()}.`)).catch(fail);
          colors.append(b);
        });
        parts.push(E("h3", "vf-pop-sub", "Your color"), colors);
        // C26 / Q79: see Claude's cards before or after answering. "Session default" follows the host's setting.
        const pref = claudePref(), sessWant = st().hideClaude !== false ? "answerFirst" : "always";
        const eff = pref === "session" ? sessWant : pref;
        const cseg = E("div", "vf-seg vf-seg-sm"); cseg.setAttribute("role", "group"); cseg.setAttribute("aria-label", "Claude's take");
        for (const [v, l] of [["answerFirst", "Answer first"], ["always", "Always show"]]) {
          const b = k(btn("vf-seg-btn", l), "cp" + v); b.setAttribute("aria-pressed", String(eff === v));
          b.onclick = () => { setPrefs({ claudeTake: v }); fillPcard(); render(); };
          cseg.append(b);
        }
        parts.push(E("h3", "vf-pop-sub", "Claude's take"), cseg);
        const advOn = !!prefs().autoAdvance, adv = k(btn("vf-sw-row vf-advsw"), "adv");
        adv.setAttribute("role", "switch"); adv.setAttribute("aria-checked", String(advOn));
        adv.append(E("span", "vf-sw-txt vf-sw-label", "Go to the next question after I answer"), E("span", "vf-switch"));
        adv.onclick = () => { setPrefs({ autoAdvance: !advOn }); if (advOn) stopAdvance(); fillPcard(); };
        parts.push(adv);
        if (c.pinned) {
          // Away by hand (the snooze): others see me as Away until my next key, click or touch.
          const awayB = k(lbtn("vf-menu-item vf-menu-plain vf-away-btn", "moon", Core.isAway() ? "You show as Away. Any key or tap ends it" : "Show me as Away"), "away");
          awayB.setAttribute("aria-pressed", String(Core.isAway()));
          // Pressed means this click is the input that ended Away (core.js clears it on pointerdown or keydown).
          awayB.onclick = () => { if (awayB.getAttribute("aria-pressed") === "true" || Core.isAway()) return; Core.setAway(true); flash("You show as Away until you next type, click or tap."); fillPcard(); };
          const dev = k(lbtn("vf-menu-item vf-menu-plain", "device", "Use on another device"), "device");
          dev.onclick = openDevice;
          parts.push(awayB, dev);
        }
        if (ui.renaming) {
          const f = E("form", "vf-rename");
          const inp = E("input", "vf-input"); inp.maxLength = 40; inp.value = ui.renameDraft ?? Core.me.name; inp.setAttribute("aria-label", "Your name"); k(inp, "rn");
          inp.oninput = () => { ui.renameDraft = inp.value; };
          const row = E("div", "vf-crow");
          const cancel = k(btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel"), "rc");
          const save = k(E("button", "vf-btn vf-btn-primary vf-btn-sm", "Save name"), "rs"); save.type = "submit";
          row.append(cancel, save); f.append(inp, row);
          cancel.onclick = () => { ui.renaming = false; ui.renameDraft = null; fillPcard(); pcard.querySelector('[data-k="rename"]')?.focus(); };
          f.onsubmit = e => {
            e.preventDefault();
            const v = inp.value.trim(); if (!v) return inp.focus();
            save.disabled = true;
            Core.rename(v).then(j => { ui.renaming = false; ui.renameDraft = null; flash(j.name !== v ? `Someone already uses that name, so you are ${j.name}.` : `You are now ${j.name}.`); fillPcard(); })
              .catch(fail).finally(() => { save.disabled = false; });
          };
          parts.push(f);
        } else if (c.pinned) {
          const rn = k(lbtn("vf-menu-item vf-menu-plain", "pencil", "Change my name"), "rename");
          rn.onclick = () => { ui.renaming = true; fillPcard(); const i = pcard.querySelector('[data-k="rn"]'); i?.focus(); i?.select(); };
          parts.push(rn);
        }
      }
      if (owner && c.pinned && !me && role !== "Host" && S.people) {
        const known = pid in S.people; // records from before identities have no people entry: they can only be merged
        const acts = E("div", "vf-pc-acts");
        const lead = k(btn("vf-menu-item", S.leaders.includes(pid) ? "Remove leader" : "Make leader"), "lead");
        const trust = k(btn("vf-menu-item", S.trusted.includes(pid) ? "Untrust" : "Trust"), "trust");
        const merge = k(lbtn("vf-menu-item", "merge", "Merge into…"), "merge");
        merge.setAttribute("aria-expanded", String(ui.mergeFrom === pid));
        lead.onclick = () => { const was = S.leaders.includes(pid); Core.setLeader(pid, !was).then(() => flash(was ? "Leader removed." : "Leader added.")).catch(fail); };
        trust.onclick = () => { const was = S.trusted.includes(pid); Core.setTrusted(pid, !was).then(() => flash(was ? "Trust removed." : "Trusted.")).catch(fail); };
        merge.onclick = () => { ui.mergeFrom = ui.mergeFrom === pid ? "" : pid; ui.mergeTo = ""; fillPcard(); };
        const remove = k(btn("vf-menu-item vf-menu-danger", "Remove from session"), "remove");
        remove.onclick = guarded(removeAsk(name), () => Core.removePerson(pid, true).then(() => { closePop(); flash(`${disp(name)} was removed. Their content is hidden; restore them from Settings.`); }).catch(fail));
        lead.hidden = trust.hidden = remove.hidden = !known;
        acts.append(lead, trust, merge, remove);
        parts.push(acts);
        if (ui.mergeFrom === pid) {
          const box = E("div", "vf-merge");
          if (ui.mergeTo) {
            // Into the owner: a second identity of the owner's own (another device) folds into the owner.
            const toMe = isMe(ui.mergeTo), toName = toMe ? "me (owner)" : disp(nameOf(ui.mergeTo)), toWhom = toMe ? "you" : toName;
            const row = E("div", "vf-crow");
            const cancel = k(btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel"), "mc");
            const go = k(btn("vf-btn vf-btn-primary vf-btn-sm", `Merge into ${toName}`), "mg");
            const moves = `${disp(name)}'s answers, votes, chat and suggestions move to ${toWhom}, and ${disp(name)} goes away. This cannot be undone.`;
            cancel.onclick = () => { ui.mergeTo = ""; fillPcard(); };
            // The server's own sentence: a refused merge says why (the owner is never merged away, for one).
            go.onclick = guarded({ title: `Merge ${disp(name)} into ${toName}?`, ok: "Merge", body: moves },
              () => { go.disabled = true; Core.merge(pid, ui.mergeTo).then(() => { flash(`Merged ${disp(name)} into ${toName}.`); closePop(); }).catch(e => { go.disabled = false; flash(`Not merged: ${e?.message || Core.errorText(e)}`); }); });
            row.append(cancel, go);
            box.append(E("p", "vf-pop-note", moves), row);
          } else {
            const others = Object.entries(S.people || {}).filter(([p]) => p !== pid).sort((a, b) => isMe(b[0]) - isMe(a[0]) || a[1].name.localeCompare(b[1].name));
            const ul = E("ul", "vf-merge-list"); ul.setAttribute("aria-label", `Merge ${disp(name)} into`);
            for (const [p, v] of others) {
              const b = k(btn("vf-merge-item"), "m:" + p);
              const a = Core.avatar(p, v.name, 20);
              b.append(a, E("span", null, isMe(p) ? "Me (owner)" : disp(v.name)), E("span", "vf-card-time", ago(v.ts)));
              b.onclick = () => { ui.mergeTo = p; fillPcard(); };
              const li = E("li"); li.append(b); ul.append(li);
            }
            box.append(E("p", "vf-pop-note", `Pick who ${disp(name)} really is.`), others.length ? ul : E("p", "vf-empty vf-empty-sm", "No one else to merge into."));
          }
          parts.push(box);
        }
      }
      pcard.replaceChildren(...parts);
      pcard.setAttribute("aria-label", disp(name));
      if (refocus) pcard.querySelector(`[data-k="${CSS.escape(refocus)}"]`)?.focus({ preventScroll: true });
    }

    // keyboard: only when no field has focus; the switcher keeps Alt + arrows
    on(document, "keydown", e => {
      if (dlgOpen() || !tour.hidden) return; // a confirm or attach dialog, or the tour, handles its own keys
      // Tab stays inside an open phone sheet, and inside an open panel or the chat while focus is in it.
      const inside = el => !!el && !el.hidden && el.contains(document.activeElement) && el;
      const sheet = e.key === "Tab" && (activeSheet() || inside(ui.pop) || (ui.chatOpen && inside(chat)));
      if (sheet) { // keep Tab inside the phone sheet
        const f = [...sheet.querySelectorAll("button, textarea, input, a[href], [tabindex]:not([tabindex='-1'])")].filter(x => !x.disabled && x.offsetParent);
        if (!f.length) return;
        const i = f.indexOf(document.activeElement), last = f.length - 1;
        if (e.shiftKey && i <= 0) { e.preventDefault(); f[last].focus(); }
        else if (!e.shiftKey && (i === last || i < 0)) { e.preventDefault(); f[0].focus(); }
        return;
      }
      if (e.key === "Escape") {
        if (!lb.hidden) { closeLb(); return; }
        if (!reader.hidden) { closeReader(); return; }
        if (ui.pop) { const r = ui.pop._return, a = r?.isConnected && r !== document.body ? r : ui.pop._anchor; closePop(); a?.focus?.(); return; }
        if (ui.pcard) { hideCard(); return; }
        if (ui.chatOpen) { setChat(false); fab.focus(); }
        return;
      }
      if (e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey || e.isComposing) return;
      const t = e.target;
      if (t.closest?.("input, textarea, select, [contenteditable]") || !reader.hidden || !lb.hidden) return;
      if (e.key === "?") {
        e.preventDefault();
        if (ui.pop === keysPop) return closePop();
        const from = document.activeElement; // Escape returns here, where "?" was pressed
        openPop(keysPop, keysBtn.offsetParent ? keysBtn : gear.offsetParent ? gear : top); keysPop._return = from;
        return;
      }
      if (ui.pop) return;
      if (e.key === "ArrowLeft" || e.key === "ArrowRight") { e.preventDefault(); step(e.key === "ArrowLeft" ? -1 : 1); return; }
      if ((e.key === "ArrowDown" || e.key === "ArrowUp") && ui.mode === "focus" && center.offsetParent) {
        const cards = [...aList.children];
        if (!cards.length) return;
        e.preventDefault();
        const i = cards.indexOf(t.closest?.(".vf-card"));
        const n = i < 0 ? (e.key === "ArrowDown" ? 0 : cards.length - 1) : Math.min(cards.length - 1, Math.max(0, i + (e.key === "ArrowDown" ? 1 : -1)));
        cards[n].focus(); cards[n].scrollIntoView({ block: "nearest" });
        return;
      }
      if ((e.key === "v" || e.key === "V")) {
        const c = t.closest?.(".vf-card, .vf-mini");
        if (c && !c._k.vote.hidden && !c._k.vote.disabled) { e.preventDefault(); c._k.vote.click(); }
        return;
      }
      if (e.key === "Enter" && (t === document.body || t === root || t.matches?.(".vf-card, .vf-mini, .vf-qtext")) && ui.mode === "focus" && !ta.disabled) {
        e.preventDefault(); ta.focus();
      }
    });

    on(rounds, "keydown", e => {
      if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
      const items = [...rounds.querySelectorAll(".vf-q")].filter(b => b.offsetParent);
      const i = items.indexOf(document.activeElement); if (i < 0) return;
      e.preventDefault();
      items[(i + (e.key === "ArrowDown" ? 1 : -1) + items.length) % items.length].focus();
    });
    const mqOff = () => { closePop(); closeSheet(); render(); syncModal(); };
    phone.addEventListener("change", mqOff); offs.push(() => phone.removeEventListener("change", mqOff));

    // ---------- requests ----------
    async function saveOpenEdit(li) {
      const r = li._r, val = li._ta.value.trim();
      if (ui.reqEditing.has(r.id) && val && val !== r.text) await Core.requestAct(r.id, "edit", val);
      ui.reqEditing.delete(r.id);
    }
    // A refused run says why in the session's own words ("None of these requests is still waiting.").
    const runFail = e => (e?.error === "wrong-status" && e.message ? flash(`Not run: ${e.message}`) : fail(e));
    async function runAllShown() {
      const items = [...RQ.list.children].filter(li => li._r?.status === "pending" && ui.reqSeen.has(li._r.id));
      if (!items.length) return;
      runAllBtn.disabled = true;
      try {
        for (const li of items) await saveOpenEdit(li);
        const ids = items.map(li => li._r.id);
        const r = await Core.runRequests(ids);
        flash(`Running ${r.ran?.length ?? ids.length} request${ids.length > 1 ? "s" : ""}.`);
      } catch (e) { runFail(e); }
      finally { runAllBtn.disabled = false; render(); }
    }
    function makeReq() {
      const li = E("li", "vf-pitem vf-ritem");
      const head = E("div", "vf-rhead2");
      const kind = E("span", "vf-chip");
      const qref = btn("vf-qref vf-qref-wrap");
      const who = E("span", "vf-pfrom");
      const status = E("span", "vf-rstat");
      head.append(kind, qref, E("span", "vf-spacer"), status);
      const text = clampBox();
      const tarea = E("textarea", "vf-ta"); tarea.rows = 2; tarea.hidden = true; tarea.setAttribute("aria-label", "Request text");
      const fresh = E("div", "vf-fresh");
      const include = btn("vf-btn vf-btn-ghost vf-btn-sm", "Include in Run all");
      fresh.append(E("span", "vf-newmark", "New since you opened"), include);
      const acts = E("div", "vf-acts");
      const edit = btn("vf-btn vf-btn-ghost vf-btn-sm", "Edit");
      const save = btn("vf-btn vf-btn-ghost vf-btn-sm", "Save");
      const cancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel");
      const decline = btn("vf-btn vf-btn-ghost vf-btn-sm", "Decline");
      const run = lbtn("vf-btn vf-btn-primary vf-btn-sm", "play", "Run");
      const failB = btn("vf-btn vf-btn-ghost vf-btn-sm", "Mark failed");
      const rerun = lbtn("vf-btn vf-btn-ghost vf-btn-sm", "restore", "Run again");
      acts.append(edit, save, cancel, decline, run, failB, rerun);
      li.append(head, who, text, tarea, fresh, acts);
      li._att = attRowEl(); text.after(li._att);
      Object.assign(li, { _ta: tarea, _k: { kind, qref, who, status, text, tarea, fresh, edit, save, cancel, decline, run, failB, rerun, acts } });
      failB.onclick = () => Core.requestAct(li._r.id, "fail").then(() => flash("Marked failed. The requester sees it.")).catch(fail);
      rerun.onclick = () => Core.requestAct(li._r.id, "rerun").then(() => flash("Running again.")).catch(fail);
      qref.onclick = () => { if (!li._r.qid) return openGeneral("r:" + li._r.id); focusQuestion(li._r.qid); closePop(); };
      include.onclick = () => { ui.reqSeen.add(li._r.id); render(); };
      edit.onclick = () => { ui.reqEditing.add(li._r.id); tarea.value = li._r.text; render(); grow(tarea); tarea.focus(); };
      cancel.onclick = () => { ui.reqEditing.delete(li._r.id); render(); };
      save.onclick = () => { saveOpenEdit(li).then(() => flash("Request updated.")).catch(fail).finally(render); };
      decline.onclick = () => { Core.requestAct(li._r.id, "decline").then(() => flash("Request declined.")).catch(fail); };
      run.onclick = async () => {
        run.disabled = true;
        try { await saveOpenEdit(li); await Core.runRequests([li._r.id]); flash("Running. The result shows on the question."); } catch (e) { runFail(e); }
        finally { run.disabled = false; render(); }
      };
      return li;
    }
    function fillReq(li, r) {
      const k = li._k, q = qById(r.qid), failed = r.status === "failed", running = r.status === "running" || failed, editing = ui.reqEditing.has(r.id) && !running;
      li._r = r;
      k.kind.textContent = r.kind === "ask" ? "Ask Claude" : "Research";
      k.kind.className = "vf-chip " + (r.kind === "ask" ? "vf-chip-quiet" : "vf-chip-accent");
      k.qref.textContent = q ? `${q.id}: ${q.text}` : r.qid || `${GEN_LABEL}: ${GEN_Q.text}`;
      k.who.replaceChildren(av(r.cid, r.name, 16), E("span", null, `${disp(r.name)}${isMe(r.cid) ? " (you)" : ""}`), E("span", "vf-card-time", ago(r.ts)));
      k.status.textContent = failed ? "Failed" : running ? `Running, ${ago(r.ts) === "now" ? "just started" : "asked " + ago(r.ts) + " ago"}` : "";
      k.status.hidden = !running;
      k.status.classList.toggle("vf-rstat-fail", failed);
      fillClamp(k.text, "r:" + r.id, r.text, `${r.kind === "ask" ? "Ask Claude" : "Research"} request from ${disp(r.name)}`, q ? `${q.id}: ${q.text}` : "");
      fillAtts(li._att, r.att, `Request from ${disp(r.name)}`);
      k.text.hidden = editing; k.tarea.hidden = !editing;
      const fresh = !running && !ui.reqSeen.has(r.id);
      li.classList.toggle("vf-ritem-fresh", fresh);
      k.fresh.hidden = !fresh;
      k.edit.hidden = editing || running; k.save.hidden = k.cancel.hidden = !editing;
      k.decline.hidden = k.run.hidden = running;
      k.failB.hidden = r.status !== "running"; k.rerun.hidden = !running;
    }

    // ---------- answer card ----------
    function buildCard(compact) {
      const li = E("li", compact ? "vf-mini" : "vf-card");
      li.tabIndex = -1;
      const head = E("div", "vf-card-head");
      head.append(E("span", "vf-card-av"), E("span", "vf-card-name"), E("span", "vf-tag"), E("span", "vf-newdot"), E("span", "vf-card-time"));
      const ctxB = E("span", "vf-ctx"); ctxB.hidden = true; head.insertBefore(ctxB, head.lastChild);
      const text = clampBox();
      // A pick shows its option, with the option's picture as a button that opens the viewer (it never picks).
      const pickChip = E("div", "vf-pickchip"), pickThumb = btn("vf-imgbtn vf-pickthumb"), pickImg = E("img"), pickTxt = E("span", "vf-pickchip-t");
      pickImg.alt = ""; pickImg.loading = "lazy"; pickThumb.append(pickImg); pickChip.append(pickThumb, pickTxt);
      pickThumb.onclick = () => { const q = qById(k.qid); openLb("choice", k.qid, optionsOf(q).filter(o => o.image).findIndex(o => o.id === k.pick), pickThumb); };
      const why = E("p", "vf-why vf-shownwhy");
      const basis = E("p", "vf-basis");
      const edited = E("p", "vf-edited");
      const citeRow = E("ul", "vf-citechips vf-card-cites"); citeRow.setAttribute("aria-label", "Cites");
      const foot = E("div", "vf-card-foot");
      const voters = E("span", "vf-avrow vf-voters"); voters.setAttribute("aria-hidden", "true");
      const vote = btn("vf-vote"); vote.append(icon("thumb"), E("span", "vf-vote-n"), voters);
      // Gather questions (Q97): reactions instead of a vote; every answer stands.
      const reacts = E("span", "vf-reacts"); reacts.setAttribute("role", "group"); reacts.setAttribute("aria-label", "React");
      const reactBtns = Core.REACTIONS.map(([r, glyph, label]) => {
        const b = btn("vf-react"); b.dataset.r = r; b.append(E("span", "vf-react-g", glyph), E("span", "vf-react-n"));
        b._label = label;
        b.onclick = () => Core.react(k.qid, k.ref, r, !Core.myReactions(k.qid, k.ref).includes(r)).catch(fail);
        reacts.append(b); return b;
      });
      foot.append(vote, reacts);
      // Phase 4c: "Hidden by the host" (the author and the owner see the card) and "Edited by the host" (everyone).
      const modNote = E("p", "vf-modnote");
      li.append(head, pickChip, text, why, basis, edited, modNote, citeRow, foot);
      const attRow = E("ul", "vf-reflist vf-attlist"); attRow.setAttribute("aria-label", "Attachments");
      li.insertBefore(attRow, citeRow);
      const k = { li, head, ctxB, text, basis, edited, modNote, voters, vote, reacts, reactBtns, pickChip, pickThumb, pickImg, pickTxt, why, citeRow, attRow, avKey: "", vKey: "", cKey: "" };
      if (!compact) {
        k.modHide = btn("vf-btn vf-btn-ghost vf-btn-sm vf-mod-hide"); k.modEdit = btn("vf-btn vf-btn-ghost vf-btn-sm vf-mod-edit", "Edit");
        k.modHide.onclick = () => toggleHidden(k.qid, k.a);
        k.modEdit.onclick = () => openEdit(k.qid, k.a, k.modEdit);
      }
      if (!compact) {
        k.agree = E("span", "vf-agree");
        k.goWith = btn("vf-btn vf-btn-ghost vf-btn-sm", "Go with this");
        k.lockThis = btn("vf-btn vf-btn-ghost vf-btn-sm vf-btn-brass-ghost", "Lock this one");
        // Decide questions: Disagree, with a reason of 1 to 200 characters. It never changes the vote count.
        k.disBtn = btn("vf-btn vf-btn-ghost vf-btn-sm vf-disagree-btn", "Disagree");
        k.disBtn.setAttribute("aria-expanded", "false");
        foot.append(k.agree, E("span", "vf-spacer"), k.disBtn, k.goWith, k.lockThis, k.modHide, k.modEdit);
        k.goWith.onclick = () => Core.goWith(k.qid, k.ref).then(() => { delete ui.drafts[k.qid]; ui.dirty = false; ta.value = ""; grow(ta); flash("Your answer was withdrawn and your vote moved."); }).catch(fail);
        k.lockThis.onclick = () => Core.lock(k.qid, k.ref).catch(fail);
        const disForm = E("form", "vf-disform"); disForm.hidden = true;
        const disIn = E("input", "vf-input vf-dis-in"); disIn.maxLength = 200;
        disIn.placeholder = "Why do you disagree? (up to 200 characters)"; disIn.setAttribute("aria-label", "Why you disagree");
        const disCancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel");
        const disSend = E("button", "vf-btn vf-btn-primary vf-btn-sm vf-dis-send", "Send"); disSend.type = "submit";
        const disRow = E("div", "vf-crow"); disRow.append(E("span", "vf-count-txt vf-dis-count"), E("span", "vf-spacer"), disCancel, disSend);
        disForm.append(disIn, disRow);
        const disList = E("ul", "vf-dislist"); disList.setAttribute("aria-label", "Disagreements");
        li.append(disForm, disList);
        Object.assign(k, { disForm, disIn, disList, disCount: disRow.firstChild });
        const closeDis = () => { disForm.hidden = true; k.disBtn.setAttribute("aria-expanded", "false"); };
        k.disBtn.onclick = () => {
          const open = disForm.hidden;
          disForm.hidden = !open; k.disBtn.setAttribute("aria-expanded", String(open));
          if (open) { disIn.value = k.myDis?.reason || ""; disIn.focus(); }
        };
        disCancel.onclick = () => { closeDis(); k.disBtn.focus(); };
        on(disIn, "input", () => { const n = disIn.value.length; k.disCount.textContent = n >= 150 ? `${n} / 200` : ""; });
        on(disIn, "keydown", e => { if (e.key === "Escape") { e.stopPropagation(); closeDis(); k.disBtn.focus(); } });
        disForm.onsubmit = e => {
          e.preventDefault();
          const reason = disIn.value.trim();
          if (!reason) { disIn.focus(); return flash("Say why you disagree first."); }
          // It shows in the list at once; a refusal takes it out again and reopens the form with the reason.
          closeDis();
          Core.disagree(k.qid, k.ref, reason).then(() => flash("Your disagreement is noted with your reason. Votes stay as they are."))
            .catch(e => { if (disForm.hidden && !k.disBtn.hidden) { disForm.hidden = false; k.disBtn.setAttribute("aria-expanded", "true"); disIn.value = reason; } fail(e); });
        };
      }
      vote.onclick = () => { const was = k.mine; return Core.vote(k.qid, k.ref, !was).then(r => {
        const q = qById(k.qid);
        if (k.other && q?.format === "choice" && !was) flash("You back this option now. It is your pick.");
        else if (r?.moved) flash("Your vote moved here. One vote per question.");
      }).catch(fail); };
      li._k = k;
      return li;
    }
    function fillCard(li, a, qid, lead, compact) {
      const k = li._k, me = Core.me, s = st(), lk = Core.lockOf(qid), locked = !!lk, bot = !!a.claude;
      k.qid = qid; k.cid = a.cid; k.ref = a.ref || a.cid; k.a = a;
      const person = !bot && !a.option;
      // A hidden answer's picks leave the tally with its text (session.py _tally counts shown cards only).
      const uncounted = a.hidden && (a.other || ["multi", "scale", "rank"].includes(qById(qid)?.format));
      const modTxt = a.hidden ? (isMe(a.cid) ? `Hidden by the host${a.hidden.reason ? `: ${a.hidden.reason}` : ""}. Only you and the host see it.${uncounted ? " Your pick is not counted while it is hidden." : ""}`
        : `Hidden by ${me.isOwner ? "you" : "the host"}${a.hidden.reason ? `: ${a.hidden.reason}` : ""}. Only you and its author see it.${uncounted ? " Its pick is not counted while it is hidden." : ""}`)
        : a.hostEdited ? "Edited by the host" : "";
      k.modNote.textContent = modTxt; k.modNote.hidden = !modTxt;
      li.classList.toggle("vf-hiddencard", !!a.hidden);
      if (k.modHide) {
        k.modHide.hidden = k.modEdit.hidden = !me.isOwner || !person || isMe(a.cid);
        k.modHide.textContent = a.hidden ? "Show" : "Hide";
        k.modHide.setAttribute("aria-label", `${a.hidden ? "Show" : "Hide"} ${disp(a.name)}'s answer`);
        k.modEdit.setAttribute("aria-label", `Edit ${disp(a.name)}'s answer${a.versions ? `, ${a.versions} earlier version${a.versions === 1 ? "" : "s"}` : ""}`);
        k.modEdit.hidden ||= !a.text;
      }
      const [avBox, nm, tag, dot, , tm] = k.head.children;
      ctxBadge(k.ctxB, Core.me.isOwner ? a.ctx : null);
      const who = bot ? "Claude" : disp(a.name);
      const key = a.cid + "|" + who;
      if (k.avKey !== key) { avBox.replaceChildren(bot ? claudeAv(22) : av(a.cid, a.name, 22, true)); k.avKey = key; }
      nm.textContent = (isMe(a.cid) ? `${who} (you)` : who) + (a.device && !bot ? `, ${a.device}` : "");
      const isLocked = locked && lk.answerCid === a.cid;
      const tagTxt = isLocked ? "Locked" : a.rec ? "Claude recommends" : lead && s.voting ? "Leading" : a.late ? "Late" : "";
      tag.textContent = tagTxt; tag.hidden = !tagTxt;
      tag.className = "vf-tag" + (a.rec && !isLocked ? " vf-tag-rec" : "");
      const fresh = ui.seenAt != null && qid === ui.cur && a.ts > ui.seenAt && !isMe(a.cid);
      dot.hidden = !fresh; dot.title = fresh ? "New since you last looked" : "";
      tm.textContent = ago(a.ts);
      const q = qById(qid);
      fillClamp(k.text, (compact ? "c:" : "a:") + qid + ":" + a.cid, a.text, `Answer from ${who}`, q ? `${q.id}: ${q.text}` : "");
      k.basis.textContent = a.basis ? `Basis: ${a.basis}` : ""; k.basis.hidden = !a.basis || compact;
      k.edited.textContent = a.editedAfter ? `Edited after ${a.editedAfter} vote${a.editedAfter > 1 ? "s" : ""}` : ""; k.edited.hidden = !a.editedAfter;
      const opt = a.pick && optionsOf(q).find(o => o.id === a.pick && !o.other);
      k.pick = a.pick;
      k.pickTxt.textContent = pickedText(q, a);
      k.pickChip.hidden = !k.pickTxt.textContent;
      k.pickThumb.hidden = !opt?.image;
      if (opt?.image && k.pickImg._src !== opt.image) { k.pickImg._src = opt.image; k.pickImg.src = assetUrl(opt.image); }
      if (opt?.image) k.pickThumb.setAttribute("aria-label", `View larger: ${opt.label}`);
      fillAtts(k.attRow, a.att, `${who}'s answer${q ? ` on ${q.id}` : ""}`);
      k.text.hidden = !a.text;
      // C26: a Claude card that shows while the others wait says why.
      const chosen = bot && claudeHidden(qid) ? claudeChosen(a, qid, lead ? a.cid : "") : "";
      k.why.textContent = chosen ? `Shown because it is ${chosen}` : ""; k.why.hidden = !chosen;
      // Q77: cite chips link to the result in the Claude thread.
      const cites = (a.cites || []).filter(id => (Core.state.research?.[qid] || []).some(x => x.id === id));
      const cKey = cites.join(",") + (compact ? "c" : "");
      if (k.cKey !== cKey) {
        k.cKey = cKey;
        k.citeRow.replaceChildren(...cites.map(id => {
          const x = (Core.state.research[qid] || []).find(r => r.id === id), li2 = E("li"), b = btn("vf-citechip");
          b.append(icon("cite"), E("span", null, `${KIND_LABEL[x.kind] || "Research"} ${id}`));
          b.setAttribute("aria-label", `Cites ${KIND_LABEL[x.kind] || "Research"} ${id}: show it in the Claude thread`);
          b.onclick = () => showResult(qid, id);
          li2.append(b); return li2;
        }));
      }
      k.citeRow.hidden = !cites.length;
      li.classList.toggle("vf-mine", isMe(a.cid));
      li.classList.toggle("vf-bot", bot);
      li.classList.toggle("vf-lead", !!lead && s.voting && !isLocked);
      li.classList.toggle("vf-pinned", isLocked);
      const votes = a.votes || [], ro = readOnly(qById(qid)), gather = q?.purpose === "gather";
      k.mine = votes.includes(me.cid);
      k.other = !!a.other;
      // On a question that takes a pick, the pick is the vote; a person's own "Something else…" option is backed with one.
      k.vote.hidden = !s.voting || (isChoice(q) && !k.other) || gather;
      k.vote.classList.toggle("vf-vote-back", k.other);
      k.reacts.hidden = !gather || !!a.option;
      if (gather) {
        const mineR = Core.myReactions(qid, k.ref);
        for (const b of k.reactBtns) {
          const r = b.dataset.r, n = a.reactions?.[r] || 0;
          b.lastChild.textContent = n ? String(n) : "";
          b.setAttribute("aria-pressed", String(mineR.includes(r)));
          b.disabled = isMe(a.cid) || ro;
          b.setAttribute("aria-label", `${b._label}: ${n}`); // aria-pressed says whether it is yours
          b.title = isMe(a.cid) ? "Your answer" : b._label;
        }
      }
      k.vote.children[1].textContent = String(votes.length);
      // Voters' faces on the thumb while names show; with names off the server sends counts only.
      const named = s.showNames ? votes.filter(Boolean) : [];
      const vKey = named.join(",");
      if (k.vKey !== vKey) { k.vKey = vKey; avStack(k.voters, named.map(c => ({ cid: c, name: nameOf(c) })), 3, 16); }
      k.vote.setAttribute("aria-pressed", String(k.mine));
      k.vote.disabled = isMe(a.cid) || locked || ro;
      k.vote.title = isMe(a.cid) ? "Your answer" : ro ? "This round went to Claude"
        : k.other ? (k.mine ? "Stop backing this option" : q?.format === "choice" ? "Back this option: it becomes your pick" : "Back this option")
        : k.mine ? "Remove your vote" : "Vote for this answer";
      const voterNames = named.length ? `: ${names(named.map(c => ({ name: nameOf(c) })))}` : "";
      const noun = k.other ? "backer" : "vote";
      k.vote.setAttribute("aria-label", `${k.other && !isMe(a.cid) ? (k.mine ? "Backing this option. " : "Back this option. ") : ""}${votes.length} ${noun}${votes.length === 1 ? "" : "s"}${k.mine ? ", including you" : ""}${voterNames}`);
      li.setAttribute("aria-label", `${who}${tagTxt ? ", " + tagTxt.toLowerCase() : ""}, ${votes.length} ${noun}s`);
      if (k.goWith) {
        k.goWith.hidden = !s.voting || locked || ro || isMe(a.cid) || !Core.myAnswer(qid) || isChoice(q) || gather;
        // On a question with options, Lock this one sits on the option itself; a person's own option is a card, so it locks here.
        // A poll closes only as a whole (Close poll), never by locking one answer.
        k.lockThis.hidden = locked || !Core.canModerate() || (isChoice(q) && q.format !== "confirm" && !k.other) || gather || q?.purpose === "poll";
        // Disagree: decide questions only, never on my own answer.
        const dis = Core.disagreementsOn(qid, k.ref);
        k.myDis = dis.find(d => d.cid && isMe(d.cid)) || null;
        k.disBtn.hidden = q?.purpose !== "decide" || isMe(a.cid) || locked || ro || !!Core.state.youRemoved;
        k.disBtn.textContent = k.myDis ? "Change why I disagree" : "Disagree";
        if (k.disBtn.hidden) k.disForm.hidden = true;
        const dKey = JSON.stringify(dis.map(d => [d.cid, d.name, d.reason]));
        if (k.disList._k !== dKey) {
          k.disList._k = dKey;
          k.disList.replaceChildren(...dis.map(d => {
            const li2 = E("li", "vf-dis"), mineD = !!d.cid && isMe(d.cid);
            li2.append(E("span", "vf-dis-who", mineD ? "You disagree:" : `${d.cid ? disp(d.name) : "Someone"} disagrees:`), E("span", "vf-dis-why", d.reason));
            if (mineD && !ro && !locked) {
              const back = btn("vf-lbtn vf-dis-back", "Take back");
              back.setAttribute("aria-label", "Take back your disagreement");
              back.onclick = () => Core.disagree(qid, k.ref, "", false).then(() => flash("Disagreement taken back.")).catch(fail);
              li2.append(back);
            }
            return li2;
          }));
        }
        k.disList.hidden = !dis.length;
        const n = agreeing(a), total = Core.state.presence.length;
        k.agree.textContent = s.signoff && !locked ? `${n} of ${total} agree` : "";
        k.agree.classList.toggle("vf-agree-all", n === total);
      }
    }

    // ---------- render ----------
    function renderComposer() {
      const qid = ui.cur, q = qById(qid), mine = Core.myAnswer(qid), S = Core.state;
      const rec = myRec(qid), picked = !!savedPick(q, rec);
      // A pick comes first where the question takes one: polls, multi, scale and rank, and a choice with "Something else…"
      // (writing your own option goes there). My own option is my card's text, so it takes no comment.
      const pickFirst = q?.purpose === "poll" || isFormat(q) || (q?.format === "choice" && !!otherOf(q));
      const lockedQ = !!Core.lockOf(qid), ro = readOnly(q), pollWait = pickFirst && !picked, ownOpt = !!rec?.other;
      const locked = lockedQ || ro || pollWait || ownOpt;
      ta.disabled = !qid || locked;
      if (ta.disabled) closeSheet();
      ta.placeholder = S.youRemoved ? "The host removed you from this session."
        : S.ended && !Core.me.isOwner ? "This session has ended."
        : q && notOpenYet(q) ? `Round ${roundOf(q)} opens after round ${curRound().current}. You can answer then.`
        : ro ? `Round ${roundOf(q)} went to Claude, so this question is read-only.${lockedQ && !Core.canModerate() ? " Suggest a change above." : ""}`
        : lockedQ ? (Core.canModerate() ? "This question is locked. Edit or unlock it above." : "This question is locked. Suggest a change above.")
        : ownOpt ? "Your own option is your answer here. Change it above."
        // A phone's composer is one line: the first half alone, so it is never cut mid-word.
        : pollWait ? (q?.format === "choice" && otherOf(q) ? "Pick an option first" : q?.format === "rank" ? "Save your ranking first" : "Pick first")
          + (phone.matches ? "" : ", then add a comment if you like.")
        : q?.format === "choice" ? (picked ? "Add a comment (optional)…" : "Pick an option, or write your own answer…")
        : isFormat(q) ? "Add a comment (optional)…"
        : q?.format === "confirm" ? (picked && q.purpose === "poll" ? "Add a comment (optional)…" : "Not exactly? Say what you meant…")
        : "Write your answer…";
      composer.classList.toggle("vf-composer-locked", locked);
      const commenting = (q?.format === "choice" || isFormat(q) || q?.purpose === "poll") && picked;
      if (!sendBtn.disabled) { sendLbl.textContent = commenting ? (mine ? "Update comment" : "Comment") : mine ? "Update" : "Answer"; sendBtn.setAttribute("aria-label", sendLbl.textContent); }
      ta.setAttribute("aria-label", commenting ? "Comment on your pick" : q?.format === "confirm" ? "Not exactly: what you meant" : "Your answer");
      sendBtn.setAttribute("aria-disabled", String(locked || (ta.value.trim() === mine && sameCites(qid) && sameAtt(qid)) || !qid));
      clearBtn.hidden = !ta.value || locked;
      cRow.hidden = locked;
      counter(cCount, ta, 1);
    }
    function renderAsk() {
      if (ui.askOpen && ui.cur && !clIsOpen()) { ui.clOpen.set(ui.cur, true); paintCl(); }
      askForm.hidden = !ui.askOpen;
      askBtn.setAttribute("aria-expanded", String(ui.askOpen));
      for (const [k, b] of Object.entries(askKinds)) b.setAttribute("aria-pressed", String(k === ui.askKind));
      const kind = guestKind(ui.askKind, ui.askWeb);
      askSeg.hidden = !Core.me.isOwner; askWeb.hidden = Core.me.isOwner;
      askWeb.setAttribute("aria-pressed", String(!!ui.askWeb));
      askTa.placeholder = kind === "ask" ? "A question for Claude about this, answered on the question" : "What to look up, compare or verify";
      askLabel.textContent = kind === "ask" ? "What should Claude answer?" : "What should Claude find out?";
      const askNote = askForm.querySelector(".vf-asknote");
      if (askNote) askNote.textContent = Core.me.isOwner ? "Claude runs it now; the result lands on this question for everyone, with your request text."
        : `The host runs it; Claude works out how to answer${ui.askWeb ? ", looking on the web," : ""} and says what it did. The result lands on this question, with your request text, for everyone.`;
      if (ui.askOpen) grow(askTa);
    }
    function reviewText(q) { return q.needsReview ? `Needs review: ${q.needsReview.because} changed` : ""; }

    function renderTree(S, mod, cur) {
      const parked = mod ? S.ideas.filter(i => i.status === "parked") : [];
      const later = S.ideas.filter(i => i.status === "later");
      const shownT = shownQuestions(), T = tb();
      const sig = JSON.stringify([S.questions.map(q => [q.id, q.text, roundOf(q), q.needsReview?.because, Core.lockOf(q.id)?.text, Core.answersFor(q.id).length]), parked.map(i => [i.id, i.text]),
        later.map(i => [i.id, i.text, i.reason]), ui.cur, cur, st().showNames, shownT.map(q => q.id), [...ui.treeClosed], T.round]);
      if (tree._sig === sig) return;
      tree._sig = sig;
      const focusKey = tree.contains(document.activeElement) ? document.activeElement.dataset.tkey : null;
      const node = (tag, cls, key) => { const n = tag === "button" ? btn(cls) : E(tag, cls); if (key) n.dataset.tkey = key; return n; };
      const rootUl = E("ul", "vf-tree-ul"); rootUl.setAttribute("role", "list");
      const nums = [...new Set([...S.questions.map(roundOf), cur])].sort((a, b) => a - b).filter(n => T.round === "all" || String(n) === T.round);
      for (const n of nums) {
        const all = S.questions.filter(q => roundOf(q) === n), qs = shownT.filter(q => roundOf(q) === n);
        if (!qs.length && all.length) continue; // filtered out entirely
        const decided = all.filter(q => Core.lockOf(q.id)).length, closed = ui.treeClosed.has(n);
        const rLi = E("li", "vf-tn");
        const rNode = node(all.length ? "button" : "div", "vf-tnode vf-tround", "r:" + n);
        rNode.append(E("span", "vf-tlabel", `Round ${n}`), E("span", "vf-meta", !all.length ? "Not opened yet" : qs.length < all.length ? `${qs.length} of ${all.length} shown` : `${decided} of ${all.length} decided`));
        if (all.length) {
          rNode.append(icon("chevD", "vf-i vf-chev vf-tchev"));
          rNode.setAttribute("aria-expanded", String(!closed));
          rNode.onclick = () => { closed ? ui.treeClosed.delete(n) : ui.treeClosed.add(n); render(); };
        }
        rLi.append(rNode);
        const qUl = E("ul", "vf-tree-ul");
        for (const q of closed ? [] : qs) {
          const lk = Core.lockOf(q.id), qLi = E("li", "vf-tn");
          const qNode = node("button", "vf-tnode vf-tq", "q:" + q.id);
          qNode.classList.toggle("vf-tcur", q.id === ui.cur);
          const stat = E("span", "vf-tstat"); stat.dataset.stat = lk ? "locked" : "open"; stat.append(icon(lk ? "lock" : "chevR"));
          const lbl = E("span", "vf-tlabel"); lbl.append(E("span", "vf-tid", q.id), E("span", "vf-ttxt", q.text));
          qNode.append(stat, lbl);
          if (q.needsReview) { const r = E("span", "vf-review vf-review-sm"); r.append(icon("alert"), E("span", null, reviewText(q))); qNode.append(r); }
          qNode.onclick = () => focusQuestion(q.id);
          qNode.setAttribute("aria-current", q.id === ui.cur ? "true" : "false");
          qLi.append(qNode);
          const aUl = E("ul", "vf-tree-ul"), aLi = E("li", "vf-tn");
          const aNode = node("button", "vf-tnode vf-tleaf " + (lk ? "vf-tlocked" : "vf-topen"), "a:" + q.id);
          const n2 = peopleAnswers(q.id).filter(a => !a.claude).length;
          const from = lk ? (lk.poll ? "counts final" : lk.name === "Claude" ? "from Claude" : lk.name === "Option" ? "the group's pick" : `from ${disp(lk.name)}`) : "";
          if (lk) aNode.append(E("span", "vf-ttxt", lk.poll ? "Poll closed" : lk.text), E("span", "vf-meta", from));
          else aNode.append(E("span", "vf-ttxt", notOpenYet(q) ? "Not open yet" : "Open"), E("span", "vf-meta", n2 ? `${n2} answer${n2 > 1 ? "s" : ""}` : "no answers yet"));
          aNode.onclick = () => focusQuestion(q.id);
          aLi.append(aNode); aUl.append(aLi); qLi.append(aUl);
          qUl.append(qLi);
        }
        if (qs.length && !closed) rLi.append(qUl);
        rootUl.append(rLi);
      }
      if (parked.length) {
        const pLi = E("li", "vf-tn vf-tparked");
        const pNode = node("div", "vf-tnode vf-tround");
        pNode.append(E("span", "vf-tlabel", "Parked"), E("span", "vf-meta", `${parked.length} proposal${parked.length > 1 ? "s" : ""}`));
        const pUl = E("ul", "vf-tree-ul");
        for (const i of parked) {
          const li = E("li", "vf-tn"), b = node("button", "vf-tnode vf-tleaf vf-tgrey", "p:" + i.id);
          b.append(E("span", "vf-ttxt", i.text), E("span", "vf-meta", `from ${disp(i.name)}`));
          b.onclick = () => { ui.propFilter = "parked"; openPanel(PP.pop, propRow.offsetParent ? propRow : b); };
          li.append(b); pUl.append(li);
        }
        pLi.append(pNode, pUl); rootUl.append(pLi);
      }
      // Later: off-goal proposals, filed as tracker items when the session ends.
      if (later.length) {
        const lLi = E("li", "vf-tn vf-tparked vf-tlater");
        const lNode = node("div", "vf-tnode vf-tround");
        lNode.append(E("span", "vf-tlabel", "Later"), E("span", "vf-meta", `${later.length} item${later.length > 1 ? "s" : ""}, for the tracker`));
        const lUl = E("ul", "vf-tree-ul");
        for (const i of later) {
          const li = E("li", "vf-tn"), b = node(mod ? "button" : "div", "vf-tnode vf-tleaf vf-tgrey", "l:" + i.id);
          b.append(E("span", "vf-ttxt", i.text), E("span", "vf-meta", i.reason ? i.reason : `from ${disp(i.name)}`));
          if (mod) b.onclick = () => { setMode("host"); if (phone.matches) setTab("host"); };
          li.append(b); lUl.append(li);
        }
        lLi.append(lNode, lUl); rootUl.append(lLi);
      }
      tree.replaceChildren(rootUl);
      if (S.questions.length && !shownT.length) tree.append(E("p", "vf-empty", "No questions match these filters. Choose All to see every question."));
      if (!S.questions.length) tree.append(E("p", "vf-empty", "No questions yet. The tree grows as rounds open."));
      if (focusKey) tree.querySelector(`[data-tkey="${CSS.escape(focusKey)}"]`)?.focus({ preventScroll: true });
    }

    // ---------- Claude thread (Q77) ----------
    const KIND_LABEL = { ask: "Answer", research: "Research", explore: "Explore", design: "Design", prototype: "Prototype" };
    const KIND_REQ = { ask: "Ask", research: "Research", explore: "Explore", design: "Design", prototype: "Prototype" };
    const RSTAT = { pending: "Waiting for the host", running: "Running", declined: "Declined", done: "Done", failed: "Failed" };
    const RSTAT_SELF = { pending: "Waiting for your Claude", running: "Your Claude is on it" };
    const rstat = r => (r.runner === "self" && RSTAT_SELF[r.status]) || RSTAT[r.status] || r.status;
    function threadItems(S, q) {
      const res = (S.research?.[q.id] || []).map(x => ({ t: "res", id: "x:" + x.id, ts: x.ts, x }));
      const reqs = new Map();
      if (Core.me.isOwner) for (const r of S.requests || []) if (r.qid === q.id) reqs.set(r.id, r);
      for (const r of S.myRequests || []) if (r.qid === q.id && !reqs.has(r.id)) reqs.set(r.id, { ...r, cid: Core.me.cid, name: Core.me.name });
      const answered = new Set(res.map(i => i.x.requestId).filter(Boolean));
      const rq = [...reqs.values()].filter(r => !answered.has(r.id)).map(r => ({ t: "req", id: "r:" + r.id, ts: r.ts, r }));
      const notes = (S.annotations || []).filter(a => a.qid === q.id).map(a => ({ t: "note", id: "a:" + a.id, ts: a.ts, a }));
      return [...rq, ...res, ...notes].sort((a, b) => a.ts - b.ts);
    }
    /** New to me: the answer to my own request while its "is done" notice is unread, or anyone else's result since my last visit. */
    const doneUnread = qid => notes().some(n => !n.read && n.kind === "request" && n.qid === qid && / is done\.$/.test(n.title || ""));
    const ixUnread = rid => inbox().some(i => i.group === "mine" && i.unread && i.id === rid && (i.status === "answered" || i.status === "shared"));
    const resNew = (x, q) => (isMe(x.byCid) ? (x.requestId ? ixUnread(x.requestId) : doneUnread(q.id)) : ui.seenAt != null && x.ts > ui.seenAt);
    /** Q98: a note someone pinned on a variant of this prototype, with a link to it on the prototype's page. */
    function makeThNote() {
      const li = E("li", "vf-thnote");
      const head = E("div", "vf-thnote-head"), text = E("p", "vf-thnote-text"), go = E("a", "vf-thnote-go", "Show it on the prototype");
      go.target = "_blank"; go.rel = "noopener noreferrer";
      li.append(head, text, go);
      li._k = { head, text, go };
      return li;
    }
    function fillThNote(li, a, q) {
      const k = li._k, v = (q.variants || []).find(x => x.id === a.variant), who = isMe(a.cid) ? "You" : disp(a.name);
      const hk = [a.cid, a.name, v?.label, a.ts].join("|");
      if (k.head._k !== hk) {
        k.head._k = hk;
        k.head.replaceChildren(E("span", "vf-chip vf-chip-quiet", "Note"), av(a.cid, a.name, 16), E("span", null, `${who} on ${v ? v.label : "a variant"}`), E("span", "vf-card-time", ago(a.ts)));
      }
      k.text.textContent = a.text;
      k.go.href = Core.pageLink(`/proto/${q.id}`, { v: a.variant, n: a.id });
      k.go.setAttribute("aria-label", `Show ${who === "You" ? "your" : `${who}'s`} note on the prototype, in a new tab`);
    }
    function makeRes() {
      const li = E("li", "vf-res");
      const head = btn("vf-res-head");
      const ttl = E("span", "vf-res-title"), via = E("span", "vf-via"), tm = E("span", "vf-card-time");
      const isNew = E("span", "vf-chip vf-chip-new vf-res-new", "New");
      head.append(icon("search"), ttl, via, isNew, tm, icon("chevD", "vf-i vf-chev"));
      const bodyR = E("div", "vf-res-body");
      const fromDisc = btn("vf-lbtn vf-fromdisc", "from Discussion");
      // Soft rule: "<Name> asked" and the ask, a thin line, then "Claude" and the answer, both at one text size.
      const ask = E("div", "vf-res-ask vf-qa-ask");
      const ans = E("div", "vf-qa-ans"), ansLbl = E("div", "vf-qa-lbl");
      ansLbl.append(claudeAv(18), E("span", null, "Claude"));
      const sum = clampBox("vf-qa-txt");
      const srcs = E("ul", "vf-sources"); srcs.setAttribute("aria-label", "Sources");
      const full = lbtn("vf-btn vf-btn-ghost vf-btn-sm", "doc", "Full report");
      const citedBy = E("div", "vf-citedby");
      // Results wait for the owner: Share shows it to everyone, Discard drops it and tells the requester.
      const share = E("div", "vf-acts vf-res-share");
      const shareNote = E("span", "vf-meta", "Only you see this until you share it.");
      const discard = btn("vf-btn vf-btn-ghost vf-btn-sm", "Discard"), publish = btn("vf-btn vf-btn-primary vf-btn-sm", "Share with everyone");
      // A guest's own Claude's answer the owner shared can still come down; the host's own Claude's cannot.
      const takeDown = btn("vf-btn vf-btn-ghost vf-btn-sm vf-res-takedown", "Take down");
      share.append(shareNote, E("span", "vf-spacer"), discard, publish, takeDown);
      publish.onclick = () => Core.requestAct(li._x.id, "publish").then(() => flash(`Shared. Everyone sees it ${li._q === GEN_Q ? genWhere() : "on the question"}.`)).catch(fail);
      discard.onclick = guarded({ title: "Discard this result?", ok: "Discard", body: "Nobody else sees it, and the person who asked hears it was not shared." },
        () => Core.requestAct(li._x.id, "discard").then(() => flash("Discarded.")).catch(fail));
      takeDown.onclick = guarded({ title: "Take this answer down?", ok: "Take down", body: "Nobody sees it any more, and the person whose Claude wrote it hears it was not shared." },
        () => Core.requestAct(li._x.id, "discard").then(() => flash("Taken down.")).catch(fail));
      ans.append(ansLbl, sum, srcs, full, citedBy);
      bodyR.append(share, ask, ans);
      ask.after(fromDisc);
      li.append(head, bodyR);
      head.onclick = () => { const id = li._x.id; ui.resClosed.has(id) ? ui.resClosed.delete(id) : ui.resClosed.add(id); render(); };
      full.onclick = () => openReader(`${KIND_LABEL[li._x.kind] || "Research"} report`, `${li._x.skill}, ${li._q.id}: ${li._q.text}`, li._x.report, full);
      li._k = { head, ttl, via, isNew, tm, bodyR, ask, sum, srcs, full, citedBy, share, shareNote, discard, publish, takeDown, fromDisc };
      return li;
    }
    function fillRes(li, x, q) {
      const k = li._k, open = !ui.resClosed.has(x.id);
      li._x = x; li._q = q;
      if (!k.bodyR.id) { k.bodyR.id = "vf-res-" + x.id; k.head.setAttribute("aria-controls", k.bodyR.id); }
      // Connect your Claude: a result the requester's own Claude wrote says whose Claude it was.
      k.ttl.textContent = x.own ? `${x.kind === "ask" ? "Answer" : KIND_LABEL[x.kind] || "Answer"} from ${isMe(x.byCid) ? "your" : `${disp(x.by || "someone")}'s`} own Claude`
        : x.kind === "ask" ? "Claude's answer" : KIND_LABEL[x.kind] || "Research";
      li.classList.toggle("vf-res-own", !!x.own);
      k.via.textContent = `via ${x.skill}`;
      k.via.title = x.why || ""; // C37: why Claude routed it there
      // Every result waits for the owner's Share (PLAN.md Decisions, h2), a guest's own Claude's too: until then only
      // the owner and, for their own Claude's answer, the requester see it.
      const draft = x.published === false, owner = Core.me.isOwner, mine = x.own && isMe(x.byCid);
      k.share.hidden = !(owner ? draft || x.own : draft && mine);
      k.shareNote.textContent = !owner ? "Only you and the host see this until the host shares it."
        : !draft ? `From ${disp(x.by || "someone")}'s own Claude. Everyone sees it.`
        : x.own ? `Only you and ${disp(x.by || "the person who asked")} see this until you share it.` : "Only you see this until you share it.";
      k.discard.hidden = k.publish.hidden = !(owner && draft);
      k.takeDown.hidden = !(owner && !draft && x.own);
      li.classList.toggle("vf-res-draft", draft);
      k.tm.textContent = ago(x.ts);
      k.isNew.hidden = !resNew(x, q);
      k.head.setAttribute("aria-expanded", String(open));
      k.bodyR.hidden = !open;
      const askKey = [x.ask, x.by, x.byCid].join("|");
      if (k.ask._key !== askKey) {
        k.ask._key = askKey;
        k.ask.replaceChildren();
        if (x.ask) {
          const who = E("div", "vf-res-who vf-qa-lbl");
          if (x.byCid) who.append(av(x.byCid, x.by || "Someone", 18, true));
          who.append(E("span", null, x.by ? `${disp(x.by)}${isMe(x.byCid) ? " (you)" : ""} asked` : "Asked"));
          const t = clampBox("vf-res-asktxt vf-qa-txt"); fillClamp(t, "xa:" + x.id, x.ask, `What ${x.by ? disp(x.by) : "someone"} asked`, `${q.id}: ${q.text}`);
          k.ask.append(who, t);
        }
      }
      k.ask.hidden = !x.ask;
      fillFromDisc(k.fromDisc, Core.state, q, x.requestId);
      li.classList.toggle("vf-qa-noask", !x.ask);
      fillClamp(k.sum, "x:" + x.id, x.summary, k.ttl.textContent, `${x.skill}, ${q.id}: ${q.text}`);
      const sk = JSON.stringify(x.sources);
      if (k.srcs._sk !== sk) {
        k.srcs._sk = sk;
        k.srcs.replaceChildren(...(x.sources || []).filter(s2 => /^https?:\/\//i.test(s2.url)).map(s2 => {
          const a = E("a", "vf-src"); a.href = s2.url; a.target = "_blank"; a.rel = "noopener noreferrer";
          let hostName = ""; try { hostName = new URL(s2.url).hostname.replace(/^www\./, ""); } catch {}
          a.append(icon("link"), E("span", "vf-src-t", s2.title || s2.url), E("span", "vf-src-h", hostName));
          const sli = E("li"); sli.append(a); return sli;
        }));
      }
      k.srcs.hidden = !x.sources?.length;
      k.full.hidden = !x.report;
      // cited by: the answers that cite this result, each a link back to the answer
      const by = Core.answersFor(q.id).filter(a => (a.cites || []).includes(x.id));
      const ck = by.map(a => a.cid + ":" + a.name).join(",");
      if (k.citedBy._ck !== ck) {
        k.citedBy._ck = ck;
        k.citedBy.replaceChildren();
        if (by.length) {
          k.citedBy.append(E("span", "vf-meta", "Cited by"));
          for (const a of by) {
            const b = btn("vf-citechip"); b.append(av(a.cid, a.name, 16), E("span", null, isMe(a.cid) ? "You" : disp(a.name)));
            b.setAttribute("aria-label", `Cited by ${isMe(a.cid) ? "you" : disp(a.name)}: show the answer`);
            b.onclick = () => focusAnswer(q.id, a.ref || a.cid);
            k.citedBy.append(b);
          }
        }
      }
      k.citedBy.hidden = !by.length;
    }
    function makeThReq() {
      const li = E("li", "vf-threq");
      const head = E("div", "vf-rhead2");
      const kind = E("span", "vf-chip"), who = E("span", "vf-pfrom"), status = E("span", "vf-thstat");
      head.append(kind, E("span", "vf-spacer"), status);
      const text = clampBox("vf-qa-txt");
      // Under the ask: Claude's label row and, while it waits or runs, the progress line.
      const ans = E("div", "vf-qa-ans"), ansLbl = E("div", "vf-qa-lbl"), prog = E("div", "vf-runline");
      ansLbl.append(claudeAv(18), E("span", null, "Claude"));
      const progTxt = E("span", "vf-runline-t");
      prog.append(E("span", "vf-runbar"), progTxt);
      ans.append(ansLbl, prog);
      const acts = E("div", "vf-acts");
      const run = lbtn("vf-btn vf-btn-primary vf-btn-sm", "play", "Run"), decline = btn("vf-btn vf-btn-ghost vf-btn-sm", "Decline");
      const failB = btn("vf-btn vf-btn-ghost vf-btn-sm", "Mark failed"), rerun = lbtn("vf-btn vf-btn-ghost vf-btn-sm", "restore", "Run again");
      acts.append(decline, run, failB, rerun);
      li._self = makeSelfActs();
      who.classList.add("vf-qa-lbl");
      const fromDisc = btn("vf-lbtn vf-fromdisc", "from Discussion");
      const askPart = E("div", "vf-qa-ask"); askPart.append(who, text, fromDisc);
      li.append(head, askPart, ans, acts, li._self);
      li._att = attRowEl(); text.after(li._att);
      run.onclick = () => Core.requestAct(li._r.id, "run").then(() => flash("Running. The result shows here.")).catch(runFail);
      decline.onclick = () => Core.requestAct(li._r.id, "decline").then(() => flash("Request declined.")).catch(fail);
      failB.onclick = () => Core.requestAct(li._r.id, "fail").then(() => flash("Marked failed. The requester sees it.")).catch(fail);
      rerun.onclick = () => Core.requestAct(li._r.id, "rerun").then(() => flash("Running again.")).catch(fail);
      li._k = { kind, who, status, text, ans, prog, progTxt, acts, run, decline, failB, rerun, fromDisc };
      return li;
    }
    function fillThReq(li, r, q) {
      const k = li._k, owner = Core.me.isOwner;
      li._r = r;
      k.kind.textContent = KIND_REQ[r.kind] || r.kind;
      k.kind.className = "vf-chip " + (r.kind === "research" ? "vf-chip-accent" : "vf-chip-quiet");
      const wk = r.cid + "|" + r.name + "|" + r.ts;
      if (k.who._k !== wk) { k.who._k = wk; k.who.replaceChildren(av(r.cid, r.name, 18), E("span", null, `${isMe(r.cid) ? "You" : disp(r.name)} asked`), E("span", "vf-card-time", ago(r.ts))); }
      k.status.textContent = `${rstat(r)}${r.edited ? ", edited by host" : ""}${r.reason ? `: ${r.reason}` : ""}`;
      li.dataset.stat = r.status;
      k.ans.hidden = r.status !== "running" && r.status !== "pending";
      k.progTxt.textContent = rstat(r);
      k.prog.dataset.run = String(r.status === "running");
      if (r.runner === "self" && isMe(r.cid)) fillSelfActs(li._self, r, q); else li._self.hidden = true;
      fillFromDisc(k.fromDisc, Core.state, q, r.id);
      fillClamp(k.text, "tr:" + r.id, r.text, `${KIND_REQ[r.kind] || "Request"} from ${isMe(r.cid) ? "you" : disp(r.name)}`, `${q.id}: ${q.text}`);
      fillAtts(li._att, r.att || (Core.state.myRequests || []).find(x => x.id === r.id)?.att, `Request from ${isMe(r.cid) ? "you" : disp(r.name)}`);
      k.run.hidden = k.decline.hidden = !(owner && r.status === "pending");
      k.failB.hidden = !(owner && r.status === "running");
      k.rerun.hidden = !(owner && (r.status === "running" || r.status === "failed"));
      k.acts.hidden = k.run.hidden && k.failB.hidden && k.rerun.hidden;
    }
    function renderThread(S, q) {
      const items = threadItems(S, q);
      if (thList._q !== q.id) { resetList(thList); thList._q = q.id; }
      sync(thList, items, i => i.id, i => (i.t === "res" ? makeRes() : i.t === "note" ? makeThNote() : makeThReq()),
        (li, i) => (i.t === "res" ? fillRes(li, i.x, q) : i.t === "note" ? fillThNote(li, i.a, q) : fillThReq(li, i.r, q)));
      thEmpty.hidden = items.length > 0;
      const mineOpen = (S.myRequests || []).filter(r => r.qid === q.id && r.runner !== "self" && (r.status === "pending" || r.status === "running")).length;
      const others = Math.max(0, (S.requestCounts?.byQ?.[q.id] || 0) - (Core.me.isOwner ? (S.requests || []).filter(r => r.qid === q.id && (r.status === "pending" || r.status === "running")).length : mineOpen));
      reqChip.textContent = others ? `${others} more open with the host` : "";
      reqChip.hidden = !others;
      const res = items.filter(i => i.t === "res"), reqs = items.filter(i => i.t === "req"), nNotes = items.length - res.length - reqs.length;
      const nNew = res.filter(i => resNew(i.x, q)).length;
      const nRun = reqs.filter(i => i.r.status === "running").length, nWait = reqs.filter(i => i.r.status === "pending").length;
      const plural = (n, w) => `${n} ${w}${n === 1 ? "" : "s"}`;
      clNew.textContent = nNew ? `${nNew} new` : ""; clNew.hidden = !nNew;
      clCounts.textContent = [res.length && plural(res.length, "answer"), nRun && `${nRun} running`, nWait && `${nWait} waiting`, nNotes && plural(nNotes, "note")]
        .filter(Boolean).join(" · ") || "Nothing asked yet";
      return nNew;
    }
    function showResult(qid, xid) {
      ui.resClosed.delete(xid); ui.clOpen.set(qid, true);
      if (ui.cur !== qid) select(qid, { manual: true });
      render();
      requestAnimationFrame(() => {
        const li = thList._map?.get("x:" + xid); if (!li) return;
        li.scrollIntoView({ block: "nearest", behavior: smooth() });
        ring(li);
        li._k.head.focus({ preventScroll: true });
      });
    }
    // ---------- item 10: the Discussion ----------
    /** The request a comment's @Claude filed, as this viewer knows it: its result if it shows here, else its card;
     * someone who sees neither (not the owner, not the requester) gets no status. */
    function discReq(S, q, c) {
      const x = (S.research?.[q.id] || []).find(r => r.requestId === c.request);
      const r = (Core.me.isOwner ? S.requests || [] : []).concat(S.myRequests || []).find(r2 => r2.id === c.request);
      return { x, r, label: x ? (x.published === false ? "Answered, waiting for the host to share" : "Answered") : r ? rstat(r) : "" };
    }
    /** Show a comment: the question, its Discussion open, the comment in view. */
    function openComment(qid, id) {
      setDisc(qid, true);
      if (ui.cur !== qid) select(qid, { manual: true });
      setMode("focus"); if (phone.matches) setTab("answer");
      render();
      requestAnimationFrame(() => { const li = discList._map?.get(id); if (!li) return; li.scrollIntoView({ block: "nearest", behavior: smooth() }); ring(li); });
    }
    function makeComment() {
      const li = E("li", "vf-cm");
      const col = E("div", "vf-cm-col"), head = E("div", "vf-cm-head");
      const name = E("b", "vf-cm-name"), tm = E("span", "vf-card-time"), edited = E("span", "vf-meta vf-cm-edited", "edited");
      const hid = E("span", "vf-chip vf-chip-quiet vf-cm-hidden", "Hidden"), dot = E("span", "vf-ndot vf-cm-new"); dot.setAttribute("aria-label", "New");
      head.append(name, tm, edited, hid, dot);
      const text = E("div", "vf-rich vf-cm-txt");
      const ed = E("form", "vf-cm-edit"); ed.hidden = true;
      const edTa = E("textarea", "vf-ta"); edTa.rows = 2; edTa.maxLength = 2000; edTa.setAttribute("aria-label", "Edit your comment");
      const edSave = E("button", "vf-btn vf-btn-primary vf-btn-sm", "Save"); edSave.type = "submit";
      const edCancel = btn("vf-btn vf-btn-ghost vf-btn-sm", "Cancel");
      const edRow = E("div", "vf-crow"); edRow.append(E("span", "vf-spacer"), edCancel, edSave); ed.append(edTa, edRow);
      const became = E("div", "vf-cm-became"), becameTxt = E("span", "vf-cm-became-t"), view = btn("vf-lbtn vf-cm-view", "View");
      became.append(claudeAv(16), becameTxt, view);
      const reactRow = E("div", "vf-mreacts"); reactRow.setAttribute("role", "group"); reactRow.setAttribute("aria-label", "Reactions");
      const reactAdd = btn("vf-mreact-add vf-cm-react"); reactAdd.append(E("span", "vf-mreact-plus", "+"), E("span", "vf-mreact-face", "🙂"));
      reactAdd.setAttribute("aria-haspopup", "dialog"); reactAdd.setAttribute("aria-label", "Add a reaction"); reactAdd.title = "Add a reaction";
      const acts = E("div", "vf-cm-acts");
      const edit = btn("vf-lbtn", "Edit"), del = btn("vf-lbtn", "Delete"), hide = btn("vf-lbtn vf-cm-hide");
      acts.append(reactAdd, edit, del, hide);
      col.append(head, text, ed, became, reactRow, acts);
      li.append(E("span", "vf-cm-av"), col);
      const react = (id, e, on) => Core.reactComment(li._q, id, e, on);
      reactAdd.onclick = () => (ui.pop === reactPop && ui.reactMsg?.id === li._c?.id ? closePop() : openReactPop(li._c, reactAdd, react));
      edit.onclick = () => { ui.discEdit = li._c.id; edTa.value = li._c.text; render(); requestAnimationFrame(() => { grow(edTa); edTa.focus(); }); };
      edCancel.onclick = () => { ui.discEdit = ""; render(); edit.focus(); };
      ed.onsubmit = e => {
        e.preventDefault();
        const t = edTa.value.trim(); if (!t || edSave.disabled) return;
        edSave.disabled = true;
        Core.editComment(li._q, li._c.id, t).then(() => { ui.discEdit = ""; render(); }).catch(fail).finally(() => { edSave.disabled = false; });
      };
      edTa.addEventListener("input", () => grow(edTa));
      del.onclick = guarded({ title: "Delete your comment?", ok: "Delete", body: "It leaves the Discussion for everyone. A request it sent to Claude stays as it is." },
        () => Core.deleteComment(li._q, li._c.id).then(() => flash("Comment deleted.")).catch(fail));
      hide.onclick = () => { const on = !li._c.hidden; Core.hideComment(li._q, li._c.id, on).then(() => flash(on ? "Hidden. Only you and its author see it." : "Shown to everyone again.")).catch(fail); };
      view.onclick = () => { const k = li._req; if (k?.x) showResult(li._q, k.x.id); else { ui.clOpen.set(li._q, true); render(); keepClInView(); } };
      li._k = { name, tm, edited, hid, dot, text, ed, edTa, became, becameTxt, reactRow, reactAdd, acts, edit, del, hide };
      return li;
    }
    function fillComment(li, c, q, S, from) {
      const k = li._k, mine = isMe(c.cid), owner = Core.me.isOwner, ro = (!!S.ended && !owner) || !!S.youRemoved;
      li._c = c; li._q = q.id;
      const key = c.cid + "|" + disp(c.name);
      if (li._av !== key) { li.firstChild.replaceChildren(av(c.cid, c.name, 22, true)); li._av = key; }
      k.name.textContent = mine ? "You" : disp(c.name);
      k.tm.textContent = ago(c.ts);
      k.edited.hidden = !c.edited;
      k.hid.hidden = !c.hidden;
      li.classList.toggle("vf-cm-ishidden", c.hidden);
      k.dot.hidden = mine || c.ts <= from;
      setRich(k.text, c.text);
      const editing = ui.discEdit === c.id && mine && !ro;
      k.text.hidden = editing; k.ed.hidden = !editing;
      li._req = c.request ? discReq(S, q, c) : null;
      k.became.hidden = !li._req;
      if (li._req) k.becameTxt.textContent = li._req.label ? `Sent to Claude · ${li._req.label}` : "Sent to Claude";
      fillReactChips(k, c, (id, e, on) => Core.reactComment(q.id, id, e, on));
      k.reactAdd.hidden = ro || c.hidden;
      k.edit.hidden = k.del.hidden = !mine || ro || editing;
      k.edit.hidden ||= !!c.request; // its text went to Claude as sent: Delete only
      k.hide.hidden = !owner || ro;
      k.hide.textContent = c.hidden ? "Show" : "Hide";
      k.acts.hidden = k.reactAdd.hidden && k.edit.hidden && k.del.hidden && k.hide.hidden;
    }
    function renderDisc(S, q) {
      const list = S.discussions?.[q.id] || [], seen = S.discussionSeen?.[q.id] || 0, open = discIsOpen();
      const fresh = list.filter(c => !isMe(c.cid) && c.ts > seen).length;
      discCount.textContent = list.length ? `${list.length} comment${list.length === 1 ? "" : "s"}` : "No comments yet";
      discNew.textContent = fresh ? `${fresh} new` : ""; discNew.hidden = !fresh;
      discSec.dataset.open = String(open); discBody.hidden = !open;
      discToggle.setAttribute("aria-expanded", String(open));
      discToggle.setAttribute("aria-label", `Discussion, ${discCount.textContent}${fresh ? `, ${fresh} new` : ""}`);
      if (!open) return;
      const newest = list.reduce((m, c) => Math.max(m, c.ts), 0);
      if (newest > seen && ui.discSent?.[q.id] !== newest && !S.youRemoved) {
        (ui.discSent ||= {})[q.id] = newest;
        Core.readDiscussion(q.id, newest).catch(() => { delete ui.discSent[q.id]; });
      }
      if (discList._q !== q.id) { resetList(discList); discList._q = q.id; }
      const from = ui.discFrom.get(q.id) ?? seen;
      sync(discList, list, c => c.id, makeComment, (li, c) => fillComment(li, c, q, S, from));
      discEmpty.hidden = list.length > 0;
      discForm.hidden = (!!S.ended && !Core.me.isOwner) || !!S.youRemoved || notOpenYet(q);
    }
    /** "from Discussion" on a Claude card whose request a comment's @Claude filed. */
    function fillFromDisc(b, S, q, rid) {
      const c = rid && (S.discussions?.[q.id] || []).find(x => x.request === rid);
      b.hidden = !c;
      if (c) b.onclick = () => openComment(q.id, c.id);
    }
    function focusAnswer(qid, cid) {
      if (claudeHidden(qid)) ui.revealed.add(qid);
      render();
      requestAnimationFrame(() => {
        const li = aList._map?.get(cid); if (!li) return;
        li.scrollIntoView({ block: "nearest", behavior: smooth() });
        ring(li);
        li.focus({ preventScroll: true });
      });
    }
    function renderCite(S, q) {
      const res = (S.research?.[q.id] || []).filter(x => x.published !== false), picked = ui.cites[q.id] || [];
      const ro = readOnly(q) || !!Core.lockOf(q.id);
      citeBtn.hidden = !v8() || !res.length || ro;
      if (citeBtn.hidden && ui.pop === citePop) closePop();
      citeBtn.lastChild.textContent = picked.length ? `Cite (${picked.length})` : "Cite";
      sync(citeList, res, x => x.id, () => {
        const li = E("li"), b = btn("vf-citeopt"); b.append(E("span", "vf-citeopt-t"), E("span", "vf-citeopt-s"));
        b.onclick = () => { const cur = ui.cites[ui.cur] ||= []; const i = cur.indexOf(li._x.id); if (i >= 0) cur.splice(i, 1); else cur.push(li._x.id); ui.dirty = true; render(); };
        li.append(b); return li;
      }, (li, x) => {
        li._x = x;
        const b = li.firstChild, on2 = (ui.cites[q.id] || []).includes(x.id);
        b.setAttribute("aria-pressed", String(on2));
        b.firstChild.textContent = `${KIND_LABEL[x.kind] || "Research"} ${x.id}${x.by ? `, asked by ${isMe(x.byCid) ? "you" : disp(x.by)}` : ""}`;
        b.lastChild.textContent = `via ${x.skill}, ${ago(x.ts) === "now" ? "just now" : ago(x.ts) + " ago"}`;
      });
      const shown = picked.filter(id => res.some(x => x.id === id));
      sync(citeChips, ro ? [] : shown, id => id, id => {
        const li = E("li"), b = btn("vf-citechip vf-citechip-x");
        b.append(icon("cite"), E("span"), icon("x"));
        b.onclick = () => { const cur = ui.cites[ui.cur] || []; ui.cites[ui.cur] = cur.filter(c => c !== id); ui.dirty = true; render(); };
        li.append(b); return li;
      }, (li, id) => {
        const x = res.find(r => r.id === id), b = li.firstChild;
        b.children[1].textContent = `${KIND_LABEL[x.kind] || "Research"} ${id}`;
        b.setAttribute("aria-label", `Remove the citation of ${KIND_LABEL[x.kind] || "Research"} ${id}`);
      });
      citeChips.hidden = !citeChips.children.length;
    }

    /** Q98: the preview tile (the first picture variant, else a plain tile) and the link to the prototype's own page. */
    function renderProtoTile(q) {
      protoBox.hidden = q.formatKind !== "prototype";
      if (protoBox.hidden) return;
      const vs = q.variants || [], pic = vs.find(v => !/\.html$/.test(v.asset));
      const key = `${q.id}|${pic?.asset || ""}`;
      if (protoTile._key !== key) {
        protoTile._key = key;
        if (pic) { const im = E("img"); im.alt = ""; im.loading = "lazy"; im.src = assetUrl(pic.asset); protoTile.replaceChildren(im); }
        else protoTile.replaceChildren(E("span", null, "Interactive prototype"));
      }
      const n = (Core.state.annotations || []).filter(a => a.qid === q.id).length;
      protoMeta.textContent = `${vs.length} variants: ${vs.map(v => v.label).join(", ")}. ${n ? `${n} note${n === 1 ? "" : "s"} pinned so far.` : "Try them and pin notes on any part."}`;
      protoOpen.href = Core.pageLink(`/proto/${q.id}`);
      protoOpen.setAttribute("aria-label", `Open prototype for ${q.id} in a new tab`);
    }

    // ---------- choice and confirm questions (Q76) ----------
    function renderFormat(S, q) {
      const show = isChoice(q);
      fmtBox.hidden = !show;
      if (!show) return;
      const fmt = q.format, rec = myRec(q.id), lk = Core.lockOf(q.id), ro = readOnly(q) || !!lk;
      // A poll shows its results once the person picked (the owner always sees them), as Claude's take waits (Q97).
      const hideResults = resultsWait(q), lead = hideResults ? "" : leadOf(q.id);
      const byId = hideResults ? {} : Object.fromEntries(Core.answersFor(q.id).filter(a => a.option).map(a => [a.cid, a]));
      const owns = hideResults ? [] : peopleAnswers(q.id).filter(a => a.other); // people's own options
      fmtBox.dataset.fmt = fmt;
      optGrid.hidden = fmt !== "choice"; confirmFig.hidden = cfRow.hidden = fmt !== "confirm";
      multiList.hidden = fmt !== "multi"; scaleBox.hidden = fmt !== "scale"; rankList.hidden = fmt !== "rank";
      fmtActs.hidden = true;
      renderProtoTile(q);
      renderOther(q, rec, ro);
      renderResults(q, hideResults);
      if (isFormat(q)) return renderPicks(q, rec, ro, hideResults);
      const voterKey = a => (st().showNames ? (a?.votes || []).filter(Boolean) : []).join(",");
      if (fmt === "choice") {
        if (optGrid._q !== q.id) { resetList(optGrid); optGrid._q = q.id; }
        // Each card: the picture (or its label) opens the viewer and never picks; the radio button below is the one pick control.
        sync(optGrid, optionsOf(q), o => o.id, o => {
          const li = E("li", "vf-opt");
          const view = btn("vf-imgbtn vf-optview"), media = E("span", "vf-optmedia");
          const img = E("img", "vf-optimg"); img.alt = ""; img.loading = "lazy"; img.decoding = "async";
          media.append(img, zoomTag()); view.append(media); // the chosen card's picture carries a "Your choice" mark (CSS)
          view.onclick = () => openLb("choice", ui.cur, optionsOf(qById(ui.cur)).filter(x => x.image).findIndex(x => x.id === li._o.id), view);
          const lab = E("span", "vf-optlabel"), foot = E("span", "vf-optfoot");
          const tag = E("span", "vf-tag"), voters = E("span", "vf-avrow vf-voters"), n = E("span", "vf-optn");
          foot.append(voters, n, E("span", "vf-spacer"), tag);
          const acts = E("div", "vf-optacts");
          const choose = btn("vf-btn vf-optchoose"), undo = btn("vf-btn vf-btn-ghost vf-btn-sm vf-optundo", "Undo");
          choose.onclick = () => (li._o.other ? openOther(ui.cur) : pickOpt(li._o.id));
          lab.onclick = () => { if (!choose.disabled && choose.getAttribute("aria-pressed") !== "true") choose.click(); }; // the name picks too
          undo.onclick = () => { choose.focus({ preventScroll: true }); clearPick(); };
          acts.append(choose, undo);
          const lockB = btn("vf-btn vf-btn-ghost vf-btn-sm vf-btn-brass-ghost vf-optlock", "Lock this one");
          lockB.onclick = () => Core.lock(ui.cur, li._o.id).catch(fail);
          li.append(view, lab, foot, acts, lockB);
          li._k = { view, img, lab, foot, tag, voters, n, choose, undo, lockB, vKey: null, mine: null };
          return li;
        }, (li, o) => {
          const k = li._k, a = byId[o.id], votes = a?.votes || [], mine = rec?.pick === o.id;
          li._o = o;
          k.view.hidden = !o.image;
          if (o.image && k.img._src !== o.image) { k.img._src = o.image; k.img.src = assetUrl(o.image); }
          k.view.setAttribute("aria-label", `View larger: ${o.label}`);
          k.lab.textContent = o.label;
          const isLocked = lk && lk.answerCid === o.id;
          k.tag.textContent = isLocked ? "Locked" : lead === o.id && st().voting ? "Leading" : "";
          // "Something else…" has no card of its own: each person who picks it writes their own option, a card in Answers.
          k.n.textContent = o.other ? (owns.length ? `${owns.length} wrote their own, in Answers` : "Write your own option") : hideResults ? "" : chose(votes.length);
          const vk = o.other ? "" : voterKey(a);
          if (k.vKey !== vk) { k.vKey = vk; avStack(k.voters, (vk ? vk.split(",") : []).map(c => ({ cid: c, name: nameOf(c) })), 3, 20); }
          // Item 12: the foot always takes its row, so every Choose button in a grid row lines up; empty (Answer first) it stays
          // blank, and on a phone, one card per row, an empty foot takes no room.
          k.foot.dataset.empty = String(!k.n.textContent && !k.tag.textContent && !vk);
          const label = o.other ? (mine ? "Your own option: edit it" : rec?.pick ? "Write your own instead" : "Write your own")
            : mine ? "Your choice" : rec?.pick ? "Choose this instead" : "Choose this";
          if (k.mine !== mine) { k.mine = mine; k.choose.replaceChildren(radioDot(), E("span", null, label)); }
          else k.choose.lastChild.textContent = label;
          k.choose.setAttribute("aria-pressed", String(mine));
          k.choose.setAttribute("aria-label", o.other ? (mine ? "Your choice is your own option: edit it" : `Something else: write your own option${rec?.pick ? " instead" : ""}`)
            : mine ? `Your choice: ${o.label}` : `Choose ${o.label}${rec?.pick ? " instead" : ""}`);
          if (o.other) k.choose.setAttribute("aria-expanded", String(!otherBox.hidden)); else k.choose.removeAttribute("aria-expanded");
          k.choose.disabled = ro;
          k.undo.hidden = !mine || ro;
          k.undo.setAttribute("aria-label", o.other ? "Undo: take back your own option" : `Undo: clear your choice of ${o.label}`);
          li.dataset.state = mine ? "mine" : votes.length ? "picked" : "none";
          li.classList.toggle("vf-opt-other", !!o.other);
          li.classList.toggle("vf-opt-lead", lead === o.id && !lk);
          li.classList.toggle("vf-opt-locked", !!isLocked);
          // Lock this one never sits on "Something else…": a person's own option is locked from its card in Answers.
          k.lockB.hidden = !!o.other || !!lk || !Core.canModerate() || q.purpose === "gather" || q.purpose === "poll";
        });
        const picked = optionsOf(q).find(o => o.id === rec?.pick);
        fmtHint.textContent = (optionsOf(q).some(o => o.image) ? "Tap a picture to see it bigger. " : "") + "Pick one option. You can change your pick later.";
        fmtHint.hidden = ro;
        fmtNote.textContent = lk ? (q.purpose === "poll" ? "The poll is closed." : "Locked. The choice is decided.") : ro ? "Read-only now."
          : picked?.other ? "You wrote your own option. It shows in Answers, where others can back it."
          : picked ? `You chose ${picked.label}. Add a comment below if you like.`
          : hideResults ? "Pick one to see how everyone voted." : "Your choice is your vote. You can add a comment below.";
      } else {
        fmtHint.textContent = "Tap the picture to see it bigger.";
        fmtHint.hidden = false;
        if (confirmImg._src !== q.image) { confirmImg._src = q.image; confirmImg.src = assetUrl(q.image); }
        const r = markRect(confirmMark, q.rect || { x: 0, y: 0, w: 100, h: 100 });
        confirmImgBox.style.setProperty("--my", String((r.y + r.h / 2) / 100));
        confirmImg.alt = `Screenshot with the area in question marked: ${q.text}`;
        confirmView.setAttribute("aria-label", "View the screenshot larger");
        const n = id => byId[id]?.votes?.length || 0, els = peopleAnswers(q.id).filter(a => !a.claude && !a.pick && a.text).length;
        const somethingElse = !!rec && !rec.pick && !!rec.text;
        for (const [b, id, cnt] of [[yesBtn, "opt-yes", n("opt-yes")], [noBtn, "opt-no", n("opt-no")], [elseBtn, "", els]]) {
          const mine = id ? rec?.pick === id : somethingElse;
          b.setAttribute("aria-pressed", String(mine));
          b.disabled = ro;
          b.lastChild.textContent = hideResults ? "" : String(cnt);
          b.hidden = !id && q.purpose === "poll"; // a poll takes a pick, not a written answer
          b.dataset.lead = String(!!id && lead === id);
          b.dataset.locked = String(!!id && lk?.answerCid === id);
        }
        cfUndo.hidden = !rec?.pick || ro;
        fmtNote.textContent = lk ? "Locked." : somethingElse ? "Your answer is below. Edit it there." : "Yes or No counts as your vote. Not exactly: write what you meant below.";
      }
    }

    // ---------- multi, scale and rank; "Something else…"; their results ----------
    // A draft is my pick while I change it (multi and rank save with a button; scale sends itself a moment after the
    // last change). ui.otherText holds my own option's text while I write it.
    Object.assign(ui, { fdraft: {}, otherOpen: {}, otherText: {} });
    const FMT = { timer: 0, drag: null };
    const sameList = (a, b) => JSON.stringify(a || []) === JSON.stringify(b || []);
    /** My working pick: the draft, else what I saved, else none (a rank starts from the order given). */
    function draftOf(q, rec = myRec(q.id)) {
      const d = ui.fdraft[q.id];
      if (q.format === "multi") return d?.options ?? rec?.picks ?? [];
      if (q.format === "rank") return d?.order ?? rec?.order ?? realOptions(q).map(o => o.id);
      if (q.format === "scale") return d?.value ?? rec?.value ?? null;
      return null;
    }
    const ownText = (q, rec = myRec(q.id)) => ui.otherText[q.id] ?? (rec?.other ? rec.text : "");
    const ownChanged = (q, rec) => (ui.otherText[q.id] ?? null) !== null && ui.otherText[q.id].trim() !== (rec?.other ? rec.text : "");
    /** Choosing "Something else…" opens the box for my own option (with what I wrote before, if I did). */
    function openOther(qid) {
      const q = qById(qid);
      if (!q || readOnly(q) || Core.lockOf(qid) || !otherOf(q)) return;
      ui.otherOpen[qid] = true;
      ui.otherText[qid] = ownText(q);
      if (q.format === "multi" && !draftOf(q).includes("other")) ui.fdraft[qid] = { options: [...draftOf(q), "other"] };
      otherBox._q = null;
      render();
      if (phone.matches) setTab("answer");
      otherTa.focus({ preventScroll: true }); otherTa.scrollIntoView?.({ block: "nearest" });
    }
    function renderOther(q, rec, ro) {
      const open = !!otherOf(q) && !ro && (!!ui.otherOpen[q.id] || (q.format === "multi" && draftOf(q, rec).includes("other")));
      otherBox.hidden = !open;
      if (!open) return;
      if (otherBox._q !== q.id) { otherBox._q = q.id; otherTa.value = ownText(q, rec); grow(otherTa); }
      otherLbl.textContent = q.format === "multi" ? "Your own option, saved with your picks" : "Your own option";
      otherSave.hidden = q.format === "multi";
      otherSave.textContent = q.format === "rank" ? (draftOf(q, rec).includes("other") ? "Update in my ranking" : "Add to my ranking") : rec?.other ? "Save my option" : "Add my option";
    }
    otherSave.onclick = () => {
      const qid = ui.cur, q = qById(qid), text = otherTa.value.trim();
      if (!q) return;
      if (!text) { otherTa.focus(); return flash("Write your own option first."); }
      if (q.format === "rank") {
        ui.otherText[qid] = text;
        const cur = draftOf(q);
        ui.fdraft[qid] = { order: cur.includes("other") ? cur : [...cur, "other"] };
        ui.otherOpen[qid] = false;
        render();
        announce("Your own option is in your ranking. Move it where it belongs, then save your ranking.");
        return fmtSave.focus({ preventScroll: true });
      }
      // It shows in Answers at once; a refusal reopens the box with the text.
      delete ui.otherText[qid]; ui.otherOpen[qid] = false;
      Core.pick(qid, "other", "", { other: text }).then(() => flash("Your own option is in Answers, where others can back it."))
        .catch(e => { if (ui.otherText[qid] == null) { ui.otherText[qid] = text; ui.otherOpen[qid] = true; } fail(e); render(); });
    };
    otherCancel.onclick = () => {
      const qid = ui.cur, q = qById(qid);
      if (!q) return;
      if (q.format === "multi") ui.fdraft[qid] = { options: draftOf(q).filter(o => o !== "other") };
      delete ui.otherText[qid]; ui.otherOpen[qid] = false; otherBox._q = null;
      render();
    };
    on(otherTa, "input", () => { ui.otherText[ui.cur] = otherTa.value; Core.setTyping(); const q = qById(ui.cur); if (q) paintFmtActs(q, myRec(q.id), readOnly(q) || !!Core.lockOf(q.id)); });
    on(otherTa, "keydown", e => {
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); (otherSave.hidden ? fmtSave : otherSave).click(); }
      else if (e.key === "Escape") { e.stopPropagation(); otherCancel.click(); }
    });

    /** The pick controls of a multi, scale or rank question. */
    function renderPicks(q, rec, ro, hideResults) {
      const lk = Core.lockOf(q.id);
      if (q.format === "multi") {
        const cur = draftOf(q, rec);
        if (multiList._q !== q.id) { resetList(multiList); multiList._q = q.id; }
        sync(multiList, optionsOf(q), o => o.id, () => {
          const li = E("li", "vf-check-row"), lab = E("label", "vf-check"), box = E("input", "vf-check-box"); box.type = "checkbox";
          lab.append(box, E("span", "vf-check-l"));
          li.append(lab);
          box.onchange = () => toggleMulti(li._o, box.checked);
          li._box = box;
          return li;
        }, (li, o) => {
          li._o = o;
          li._box.checked = cur.includes(o.id); li._box.disabled = ro;
          li.firstChild.lastChild.textContent = o.label;
          li.classList.toggle("vf-check-other", !!o.other);
          li.dataset.on = String(li._box.checked);
        });
        fmtHint.textContent = "Pick every option that fits, then save. Your picks are your vote.";
        fmtNote.textContent = lk ? (q.purpose === "poll" ? "The poll is closed." : "Locked. The choice is decided.") : ro ? "Read-only now."
          : rec?.picks?.length ? `You picked ${rec.picks.length}. Add a comment below if you like.` : hideResults ? "Pick to see how everyone voted." : "";
      } else if (q.format === "scale") {
        const v = draftOf(q, rec), labels = q.labels || {}, mid = (q.min + q.max) % 2 === 0 ? (q.min + q.max) / 2 : null;
        const named = n => (n === q.min ? labels.min : n === q.max ? labels.max : n === mid ? labels.mid : "") || "";
        scaleRow.setAttribute("aria-label", `Your rating, ${q.min} (${labels.min}) to ${q.max} (${labels.max})`);
        if (scaleRow._q !== q.id) { resetList(scaleRow); scaleRow._q = q.id; }
        sync(scaleRow, optionsOf(q), o => o.id, () => {
          const b = btn("vf-scale-btn"); b.setAttribute("role", "radio");
          b.onclick = () => pickScale(+b._o.id, true);
          return b;
        }, (b, o) => {
          const n = +o.id, mine = v === n;
          b._o = o; b.textContent = o.id;
          b.setAttribute("aria-checked", String(mine));
          b.tabIndex = mine || (v == null && n === q.min) ? 0 : -1;
          b.disabled = ro;
          b.setAttribute("aria-label", named(n) ? `${n}, ${named(n)}` : String(n));
        });
        scaleMin.textContent = `${q.min}: ${labels.min}`; scaleMax.textContent = `${q.max}: ${labels.max}`;
        scaleMid.textContent = labels.mid ? (mid != null ? `${mid}: ${labels.mid}` : labels.mid) : ""; // kept empty, it holds the middle column
        fmtHint.textContent = `Tap a number from ${q.min} to ${q.max}, or use the arrow keys. It saves by itself.`;
        fmtNote.textContent = lk ? (q.purpose === "poll" ? "The poll is closed." : "Locked. The choice is decided.") : ro ? "Read-only now."
          : rec?.value != null ? `You chose ${rec.value}. Add a comment below if you like.` : hideResults ? "Choose to see how everyone voted." : "";
      } else {
        const order = draftOf(q, rec), n = order.length;
        if (rankList._q !== q.id) { resetList(rankList); rankList._q = q.id; }
        sync(rankList, order, id => id, buildRankItem, (li, id) => {
          const k = li._k, i = order.indexOf(id), own = id === "other";
          const label = own ? ownText(q, rec) || "Your own option" : optionsOf(q).find(o => o.id === id)?.label || id;
          li._id = id;
          k.pos.textContent = String(i + 1);
          k.lab.textContent = own ? `Your own: ${label}` : label;
          k.grip.setAttribute("aria-label", `${label}, position ${i + 1} of ${n}. Press up or down arrow to move it.`);
          k.up.setAttribute("aria-label", `Move ${label} up`); k.down.setAttribute("aria-label", `Move ${label} down`);
          k.up.disabled = ro || i === 0; k.down.disabled = ro || i === n - 1; k.grip.disabled = ro;
          k.edit.hidden = k.rm.hidden = !own || ro;
          li.classList.toggle("vf-rank-own", own);
        });
        rankList.classList.toggle("vf-rank-ro", ro);
        fmtHint.textContent = "Put every option in order, best first: drag the handle, or use the arrows. Then save your ranking.";
        const saved = !!rec?.order?.length, dirty = !sameList(order, rec?.order) || ownChanged(q, rec);
        fmtNote.textContent = lk ? (q.purpose === "poll" ? "The poll is closed." : "Locked. The order is decided.") : ro ? "Read-only now."
          : saved && !dirty ? "Your ranking is saved. Add a comment below if you like." : saved ? "Not saved yet: save to update your ranking."
          : hideResults ? "Save your ranking to see everyone's." : "Not saved yet.";
      }
      fmtHint.hidden = ro;
      paintFmtActs(q, rec, ro);
    }
    /** Save and Clear under the picks: multi and rank save with the button; scale saves itself. */
    function paintFmtActs(q, rec, ro) {
      const saved = !!savedPick(q, rec);
      fmtActs.hidden = !isFormat(q) || ro;
      if (fmtActs.hidden) return;
      fmtSave.hidden = q.format === "scale";
      fmtOwn.hidden = q.format !== "rank" || !otherOf(q) || draftOf(q, rec).includes("other") || !!ui.otherOpen[q.id];
      if (q.format === "multi") {
        const cur = draftOf(q, rec), dirty = !sameList([...cur].sort(), [...(rec?.picks || [])].sort()) || (cur.includes("other") && ownChanged(q, rec));
        fmtSave.textContent = saved ? "Update my picks" : "Save my picks";
        fmtSave.setAttribute("aria-disabled", String(!cur.length || !dirty));
        fmtClear.textContent = "Clear my picks";
      } else if (q.format === "rank") {
        const dirty = !sameList(draftOf(q, rec), rec?.order) || ownChanged(q, rec);
        fmtSave.textContent = saved ? "Update my ranking" : "Save my ranking";
        fmtSave.setAttribute("aria-disabled", String(saved && !dirty));
        fmtClear.textContent = "Clear my ranking";
      } else fmtClear.textContent = "Clear my choice";
      fmtClear.hidden = !saved;
    }
    const fmtOwn = btn("vf-btn vf-btn-ghost vf-btn-sm vf-fmt-own", "Add your own option");
    fmtActs.insertBefore(fmtOwn, fmtActs.children[1]);
    fmtOwn.onclick = () => openOther(ui.cur);
    function toggleMulti(o, checked) {
      const q = qById(ui.cur); if (!q) return;
      if (o.other) { if (checked) return openOther(q.id); return otherCancel.click(); }
      const cur = new Set(draftOf(q)); checked ? cur.add(o.id) : cur.delete(o.id);
      ui.fdraft[q.id] = { options: optionsOf(q).map(x => x.id).filter(id => cur.has(id)) };
      render();
    }
    /** The comment my pick keeps when I change it; my own option is its card's text, never a comment. */
    const commentOf = rec => (rec?.other ? "" : rec?.text || "");
    fmtSave.onclick = () => {
      const qid = ui.cur, q = qById(qid), rec = myRec(qid);
      if (!q || fmtSave.getAttribute("aria-disabled") === "true") {
        if (q?.format === "multi" && !draftOf(q, rec).length) flash("Pick at least one option first.");
        return;
      }
      const list = draftOf(q, rec), own = list.includes("other") ? ownText(q, rec).trim() : null;
      if (own === "") { openOther(qid); return flash("Write your own option first."); }
      const fields = q.format === "multi" ? { options: list } : { order: list };
      // The saved pick shows at once; a refusal puts the draft back.
      const draft = ui.fdraft[qid], ownDraft = ui.otherText[qid];
      delete ui.fdraft[qid]; delete ui.otherText[qid]; ui.otherOpen[qid] = false; otherBox._q = null;
      Core.pickWith(qid, fields, own != null ? { other: own } : { comment: commentOf(rec) })
        .then(() => flash(q.format === "multi" ? "Your picks are saved." : "Your ranking is saved."))
        .catch(e => { if (draft && !ui.fdraft[qid]) ui.fdraft[qid] = draft; if (ownDraft != null && ui.otherText[qid] == null) ui.otherText[qid] = ownDraft; fail(e); render(); });
    };
    fmtClear.onclick = () => {
      const qid = ui.cur, q = qById(qid), rec = myRec(qid);
      if (!q || !savedPick(q, rec)) return;
      const fields = q.format === "multi" ? { options: [] } : q.format === "rank" ? { order: [] } : { value: null };
      clearTimeout(FMT.timer);
      Core.pickWith(qid, fields, { comment: commentOf(rec) }).then(() => {
        delete ui.fdraft[qid]; delete ui.otherText[qid]; ui.otherOpen[qid] = false; otherBox._q = null;
        flash(q.format === "rank" ? "Your ranking is cleared." : "Your pick is cleared.");
      }).catch(fail).finally(render);
    };
    /** A scale value: a tap saves it at once; arrowing sends a moment after the last key, so arrowing across sends one pick. */
    function pickScale(n, now) {
      const qid = ui.cur, q = qById(qid);
      if (!q || readOnly(q) || Core.lockOf(qid) || n < q.min || n > q.max) return;
      ui.fdraft[qid] = { value: n };
      render();
      scaleRow._map?.get(String(n))?.focus({ preventScroll: true });
      clearTimeout(FMT.timer);
      const save = () => {
        const rec = myRec(qid);
        delete ui.fdraft[qid];
        if (rec?.value === n) return render();
        Core.pickWith(qid, { value: n }, { comment: commentOf(rec) }).then(() => { announce(`You chose ${n}.`); armAdvance(qid); }).catch(fail).finally(render);
      };
      if (now) save(); else FMT.timer = setTimeout(save, 450);
    }
    on(scaleRow, "keydown", e => {
      const q = qById(ui.cur); if (!q || q.format !== "scale") return;
      // From the focused value (with nothing chosen yet, focus sits on the first), as a radio group moves.
      const v = e.target.closest?.(".vf-scale-btn")?._o ? +e.target.closest(".vf-scale-btn")._o.id : draftOf(q) ?? q.min;
      const to = { ArrowRight: v + 1, ArrowUp: v + 1, ArrowLeft: v - 1, ArrowDown: v - 1, Home: q.min, End: q.max }[e.key];
      if (to == null) return;
      e.preventDefault(); e.stopPropagation();
      pickScale(Math.min(q.max, Math.max(q.min, to)));
    });
    // ---------- rank: drag with mouse or touch on the handle, or move with the arrows ----------
    function buildRankItem() {
      const li = E("li", "vf-rank-item");
      const grip = btn("vf-rank-grip"); grip.append(icon("grip"));
      const pos = E("span", "vf-rank-pos"), lab = E("span", "vf-rank-l");
      const edit = btn("vf-lbtn vf-rank-edit", "Edit");
      const rm = ibtn("vf-tbtn vf-icon-btn vf-rank-rm", "x", "Take your own option out");
      const up = ibtn("vf-tbtn vf-icon-btn vf-rank-up", "chevU", "Move up"), down = ibtn("vf-tbtn vf-icon-btn vf-rank-down", "chevD", "Move down");
      li.append(grip, pos, lab, edit, rm, up, down);
      li._k = { grip, pos, lab, edit, rm, up, down };
      up.onclick = () => moveRank(li._id, -1, "up");
      down.onclick = () => moveRank(li._id, 1, "down");
      grip.onkeydown = e => {
        if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return;
        e.preventDefault(); e.stopPropagation();
        moveRank(li._id, e.key === "ArrowUp" ? -1 : 1, "grip");
      };
      edit.onclick = () => openOther(ui.cur);
      rm.onclick = () => {
        const q = qById(ui.cur); if (!q) return;
        ui.fdraft[q.id] = { order: draftOf(q).filter(o => o !== "other") };
        render(); fmtSave.focus({ preventScroll: true });
      };
      grip.onpointerdown = e => {
        if ((e.pointerType === "mouse" && e.button !== 0) || grip.disabled) return;
        e.preventDefault();
        FMT.drag = { id: li._id, pointer: e.pointerId, moved: false };
        try { rankList.setPointerCapture(e.pointerId); } catch { /* the pointer is gone */ }
        li.classList.add("vf-dragging");
      };
      return li;
    }
    function moveRank(id, d, refocus) {
      const q = qById(ui.cur); if (!q || readOnly(q) || Core.lockOf(q.id)) return;
      const order = [...draftOf(q)], i = order.indexOf(id), j = i + d;
      if (i < 0 || j < 0 || j >= order.length) return;
      order.splice(j, 0, ...order.splice(i, 1));
      ui.fdraft[q.id] = { order };
      render();
      const k = rankList._map?.get(id)?._k;
      const to = refocus === "up" && j === 0 ? k?.down : refocus === "down" && j === order.length - 1 ? k?.up : k?.[refocus];
      to?.focus({ preventScroll: true });
      announce(`Moved to position ${j + 1} of ${order.length}.`);
    }
    on(rankList, "pointermove", e => {
      const dr = FMT.drag; if (!dr || e.pointerId !== dr.pointer) return;
      const q = qById(ui.cur); if (!q) return;
      const order = [...draftOf(q)], from = order.indexOf(dr.id);
      // Where the pointer is among the other items' middles.
      let to = 0;
      for (const li of rankList.children) {
        if (li._id === dr.id) continue;
        const r = li.getBoundingClientRect();
        if (e.clientY > r.top + r.height / 2) to++;
      }
      if (from < 0 || to === from) return;
      order.splice(to, 0, ...order.splice(from, 1));
      ui.fdraft[q.id] = { order }; dr.moved = true;
      render();
    });
    const endDrag = e => {
      const dr = FMT.drag; if (!dr || e.pointerId !== dr.pointer) return;
      FMT.drag = null;
      try { rankList.releasePointerCapture(e.pointerId); } catch { /* released */ }
      const li = rankList._map?.get(dr.id);
      li?.classList.remove("vf-dragging");
      if (dr.moved) { const q = qById(ui.cur); announce(`Moved to position ${draftOf(q).indexOf(dr.id) + 1}. Save your ranking when it is right.`); }
    };
    on(rankList, "pointerup", endDrag); on(rankList, "pointercancel", endDrag);

    /** Results where the options are: counts per option (multi), per value with the mean and median (scale), Borda points (rank). */
    function renderResults(q, hide) {
      const show = isFormat(q) && !hide;
      fmtRes.hidden = !show;
      if (!show) return;
      const people = peopleAnswers(q.id).filter(a => !a.claude);
      const count = id => (optCard(q.id, id)?.votes || []).length;
      let rows, total, sum;
      if (q.format === "multi") {
        total = people.filter(a => a.picks?.length).length;
        rows = realOptions(q).map(o => ({ id: o.id, label: o.label, n: count(o.id), text: `${count(o.id)} picked` }));
        fmtResHead.textContent = "Picks so far";
        sum = `${total} ${total === 1 ? "person" : "people"} picked.`;
      } else if (q.format === "scale") {
        const vals = people.filter(a => a.value != null).map(a => a.value).sort((a, b) => a - b), m = vals.length;
        const mean = m ? vals.reduce((s, x) => s + x, 0) / m : null, median = m ? (m % 2 ? vals[(m - 1) / 2] : (vals[m / 2 - 1] + vals[m / 2]) / 2) : null;
        total = m;
        const end = n => (n === q.min ? q.labels?.min : n === q.max ? q.labels?.max : "");
        rows = optionsOf(q).map(o => ({ id: o.id, label: end(+o.id) ? `${o.id}, ${end(+o.id)}` : o.id, n: count(o.id), text: `${count(o.id)} ${count(o.id) === 1 ? "person" : "people"}` }));
        fmtResHead.textContent = "Ratings so far";
        const num = x => String(Math.round(x * 100) / 100);
        sum = m ? `Mean ${num(mean)}, median ${num(median)}, from ${m} ${m === 1 ? "person" : "people"}.` : "No one has rated it yet.";
      } else {
        const opts = realOptions(q);
        total = people.filter(a => a.order?.length).length;
        rows = opts.map((o, i) => ({ id: o.id, i, label: o.label, n: optCard(q.id, o.id)?.points || 0 }))
          .sort((a, b) => b.n - a.n || a.i - b.i).map(r => ({ ...r, text: `${r.n} point${r.n === 1 ? "" : "s"}` }));
        total = Math.max(total, 0);
        fmtResHead.textContent = "Ranking so far";
        sum = `Borda points from ${total} ranking${total === 1 ? "" : "s"}: first place gets ${opts.length - 1}, last gets 0.`;
      }
      fmtResSum.textContent = sum;
      const top = Math.max(1, ...rows.map(r => r.n));
      if (fmtResList._q !== q.id) { resetList(fmtResList); fmtResList._q = q.id; }
      sync(fmtResList, rows, r => r.id, () => {
        const li = E("li", "vf-fmtres-row"), bar = E("span", "vf-fmtres-bar"); bar.setAttribute("aria-hidden", "true"); bar.append(E("span"));
        li.append(E("span", "vf-fmtres-l"), E("span", "vf-fmtres-n"), bar);
        return li;
      }, (li, r) => {
        li.dataset.k = r.id;
        li.children[0].textContent = r.label;
        li.children[1].textContent = r.text;
        li.children[2].firstChild.style.inlineSize = `${Math.round((r.n / top) * 100)}%`;
      });
    }

    /** Compact options for a Compare column. */
    function fillColFormat(holder, q) {
      holder.hidden = !isChoice(q);
      if (!isChoice(q)) return;
      const wait = resultsWait(q);
      const byId = wait ? {} : Object.fromEntries(Core.answersFor(q.id).filter(a => a.option).map(a => [a.cid, a])), lk = Core.lockOf(q.id);
      // Counts: votes on an option (picks on multi, people per value on scale), Borda points on rank, own options written.
      const rows = q.format === "confirm"
        ? [{ id: "opt-yes", label: "Yes" }, { id: "opt-no", label: "No" }, { id: "", label: CONFIRM_OTHER, n: peopleAnswers(q.id).filter(a => !a.claude && !a.pick && a.text).length }]
        : optionsOf(q).map(o => (o.other ? { ...o, id: "", n: peopleAnswers(q.id).filter(a => a.other).length }
          : q.format === "rank" ? { ...o, n: byId[o.id]?.points || 0 } : o));
      const sig = JSON.stringify([q.format, q.image, wait, rows.map(o => [o.id, o.label, o.image, o.n ?? byId[o.id]?.votes?.length, lk?.answerCid === o.id])]);
      if (holder._sig === sig) return;
      holder._sig = sig;
      holder.replaceChildren();
      if (q.format === "confirm") {
        const box = E("div", "vf-confirm-box vf-confirm-box-sm"), img = E("img", "vf-confirm-img"), mark = E("span", "vf-confirm-mark");
        img.src = assetUrl(q.image); img.alt = "Screenshot with the area in question marked"; mark.setAttribute("aria-hidden", "true");
        markRect(mark, q.rect || { x: 0, y: 0, w: 100, h: 100 });
        box.append(img, mark, zoomTag());
        const b = btn("vf-imgbtn vf-colconfirm-view"); b.append(box); b.setAttribute("aria-label", "View the screenshot larger");
        b.onclick = () => openLb("confirm", q.id, 0, b);
        holder.append(b);
      }
      const ul = E("ul", "vf-colopts"); ul.setAttribute("role", "list");
      const withImg = rows.filter(r => r.image);
      for (const o of rows) {
        const li = E("li", "vf-colopt" + (lk?.answerCid === o.id && o.id ? " vf-colopt-locked" : ""));
        if (o.image) { // looking, never picking: the picture opens the viewer
          const b = btn("vf-imgbtn vf-colopt-view"), im = E("img", "vf-colopt-img"); im.src = assetUrl(o.image); im.alt = ""; b.append(im);
          b.setAttribute("aria-label", `View larger: ${o.label}`);
          b.onclick = () => openLb("choice", q.id, withImg.indexOf(o), b);
          li.append(b);
        } else if (withImg.length) li.append(E("span", "vf-colopt-img vf-colopt-noimg"));
        const n = o.n ?? byId[o.id]?.votes?.length ?? 0;
        li.append(E("span", "vf-colopt-l", o.label), E("span", "vf-colopt-n", wait ? "" : String(n)));
        ul.append(li);
      }
      holder.append(ul);
    }

    // ---------- Ask Claude panel ----------
    function renderAskPanel(S) {
      ui.askMode = !v8() && ui.askMode === "explore" ? "ask" : ui.askMode;
      const mode = guestKind(ui.askMode, ui.apWeb);
      for (const [k, b] of Object.entries(apModeBtns)) { b.setAttribute("aria-selected", String(k === mode)); b.setAttribute("aria-pressed", String(k === mode)); }
      apModeBtns.explore.hidden = !v8();
      apModes.hidden = !Core.me.isOwner; apWeb.hidden = Core.me.isOwner;
      apWeb.setAttribute("aria-pressed", String(!!ui.apWeb));
      const qs = S.questions;
      const want = ui.askQ === Core.GENERAL || qs.some(q => q.id === ui.askQ) ? ui.askQ : ui.cur || Core.GENERAL;
      const qk = qs.map(q => q.id + q.text).join("|");
      if (apQWrap.s._k !== qk) {
        apQWrap.s._k = qk;
        const gen = E("option", null, "About the whole session"); gen.value = Core.GENERAL; // pinned first: no question needed
        apQWrap.s.replaceChildren(gen, ...qs.map(q => { const o = E("option", null, `${q.id}: ${q.text.length > 70 ? q.text.slice(0, 70).trimEnd() + "…" : q.text}`); o.value = q.id; return o; }));
      }
      if (apQWrap.s.value !== want && document.activeElement !== apQWrap.s) apQWrap.s.value = want;
      const general = askGeneral();
      apLabel.textContent = { ask: "What should Claude answer?", research: "What should Claude find out?", explore: "What should Claude look for in this session?" }[mode];
      apTa.placeholder = general && mode !== "explore" ? "A question about the whole session" : { ask: "A question Claude answers on the question", research: "What to look up, compare or verify", explore: "Something in the answers, the chat or the linked project" }[mode];
      const own = selfAsk();
      apSelf.hidden = Core.me.isOwner || general;
      apSelf.setAttribute("aria-checked", String(!!ui.askSelf));
      apNote.textContent = own ? "Only you see this request. Your own Claude runs it; the host reviews its answer before anyone else sees it."
        : general ? (Core.me.isOwner ? `Claude runs it now and the answer shows ${genWhere()} for everyone.` : `The host runs it; Claude works out how to answer and says what it did. Once the host shares the answer, it shows ${genWhere()} for everyone.`)
        : Core.me.isOwner ? "Claude runs it now and the answer shows on the question's Claude thread for everyone."
        : "The host runs it; Claude works out how to answer and says what it did. The result lands on the question's Claude thread, with your request text, for everyone.";
      const selfOpen = (S.myRequests || []).some(r => r.runner === "self" && (r.status === "pending" || r.status === "running"));
      apConnect.hidden = Core.me.isOwner || !(own || selfOpen);
      if (!apConnect.hidden) {
        const wp = Connect.watcherPrompt(sessionBase());
        for (const [a, kind] of [[apcCode, "code"], [apcDesk, "desktopCode"]]) { const href = Connect.link(kind, wp); a.hidden = !href; if (href) a.href = href; }
        apcRevoke.hidden = !S.me?.watcher;
      }
      const ro = (!!S.ended && !Core.me.isOwner) || !!S.youRemoved;
      apSend.disabled = ro; apTa.disabled = ro; apPointer.hidden = ro;
      paintSlot(apSlot, ro);
      const mine = (S.myRequests || []).slice().sort((a, b) => b.ts - a.ts);
      sync(apReqs, mine, r => r.id, () => {
        const li = E("li", "vf-pitem vf-apreq");
        const head = E("div", "vf-rhead2");
        const kind = E("span", "vf-chip"), status = E("span", "vf-thstat");
        head.append(kind, E("span", "vf-spacer"), status);
        const qref = btn("vf-qref vf-qref-wrap");
        const text = clampBox();
        li._self = makeSelfActs();
        li.append(head, qref, text, li._self);
        li._att = attRowEl(); text.after(li._att);
        qref.onclick = () => { const r = li._r; if (!r.qid) return openGeneral("r:" + r.id); closePop(); ui.clOpen.set(r.qid, true); focusQuestion(r.qid); };
        li._k = { kind, status, qref, text };
        return li;
      }, (li, r) => {
        const k = li._k, q = qById(r.qid);
        li._r = r;
        k.kind.textContent = KIND_REQ[r.kind] || r.kind;
        k.kind.className = "vf-chip " + (r.kind === "research" ? "vf-chip-accent" : "vf-chip-quiet");
        k.status.textContent = `${rstat(r)}${r.edited ? ", edited by host" : ""}${r.reason ? `: ${r.reason}` : ""}`;
        li.dataset.stat = r.status;
        if (r.runner === "self") fillSelfActs(li._self, r, q); else li._self.hidden = true;
        k.qref.textContent = q ? `${q.id}: ${q.text}` : r.qid || GEN_LABEL;
        k.qref.setAttribute("aria-label", r.qid ? `Open ${q ? q.id : r.qid} and its Claude thread` : "General: about the whole session");
        fillClamp(k.text, "ar:" + r.id, r.text, `Your ${KIND_REQ[r.kind] || "request"}`, q ? `${q.id}: ${q.text}` : "");
        fillAtts(li._att, r.att, "Your request");
      });
      apReqEmpty.hidden = mine.length > 0;
      const gen = general ? (S.research?.[Core.GENERAL] || []).slice().sort((a, b) => b.ts - a.ts) : [];
      sync(apGen, gen, x => "x:" + x.id, makeRes, (li, x) => fillRes(li, x, GEN_Q));
      apGenHead.hidden = apGen.hidden = !gen.length;
      const files = (S.myUploads || []).slice().sort((a, b) => b.ts - a.ts);
      sync(apFiles, files, u => u.id, () => makeUpRow(false), fillUpRow);
      apFileHead.hidden = apFiles.hidden = !files.length;
    }

    // ---------- Host view (Q73) ----------
    function queueItems(S) {
      const R = curRound(), out = [], owner = Core.me.isOwner;
      if (owner) for (const r of S.requests || []) out.push({ t: "request", id: "r:" + r.id, ts: r.ts, r });
      for (const i of S.ideas) if (i.status === "new") out.push({ t: "proposal", id: "p:" + i.id, ts: i.ts, i });
      for (const [qid, lst] of Object.entries(S.suggestions || {})) if (Core.lockOf(qid)) for (const x of lst) if (x.status === "open") out.push({ t: "suggestion", id: "s:" + x.id, ts: x.ts, x, qid });
      if (owner) for (const m of S.mergeRequests || []) out.push({ t: "merge", id: "m:" + m.id, ts: m.ts, m });
      if (owner) for (const j of S.joinRequests || []) out.push({ t: "join", id: "j:" + j.pid, ts: j.ts, j });
      if (owner) for (const u of S.uploads || []) if (["offered", "accepted", "uploading"].includes(u.status)) out.push({ t: "upload", id: "u:" + u.id, ts: u.ts, u });
      if (owner) for (const f of S.reports || []) out.push({ t: "report", id: "f:" + f.id, ts: f.ts, f });
      if (R.ready && R.status === "open") out.push({ t: "ready", id: "ready:" + R.current, ts: R.ready.ts, ready: R.ready });
      return out.sort((a, b) => a.ts - b.ts);
    }
    const QT = { request: "Request", proposal: "Proposal", suggestion: "Suggestion", merge: "Merge", upload: "Upload", ready: "Ready to send", join: "Join", report: "Problem" };
    const BROWSER_NAME = { chrome: "Chrome", safari: "Safari", firefox: "Firefox", edge: "Edge", samsung: "Samsung Internet", "in-app": "an in-app browser" };
    const ordinal = n => n + (n % 100 >= 11 && n % 100 <= 13 ? "th" : ["th", "st", "nd", "rd"][n % 10] || "th"); // spellchecker:disable-line
    /** " (2nd waiting; phone · Safari)": the join order and what the join said about its device, never more. */
    const joinHint = j => {
      const hint = [j.device, BROWSER_NAME[j.browser]].filter(Boolean).join(" · ");
      return j.n ? ` (${ordinal(j.n)} waiting${hint ? `; ${hint}` : ""})` : "";
    };
    function makeQItem(it) {
      const li = E("li", "vf-qitem");
      li.dataset.t = it.t;
      const head = E("div", "vf-rhead2");
      const chip = E("span", "vf-chip"), who = E("span", "vf-pfrom"), qref = btn("vf-qref");
      head.append(chip, E("span", "vf-spacer"), qref);
      const text = clampBox();
      const extra = E("div", "vf-qextra");
      const acts = E("div", "vf-acts");
      const att = attRowEl();
      li.append(head, who, text, att, extra, acts);
      qref.onclick = () => { if (li._it.qid || li._it.r?.qid) focusQuestion(li._it.qid || li._it.r.qid); else if (li._it.r) openGeneral("r:" + li._it.r.id); };
      li._k = { chip, who, qref, text, att, extra, acts, sig: "" };
      if (it.t === "upload") { const row = makeUpRow(true); row.classList.add("vf-uprow-q"); extra.append(row); li._k.up = row; }
      if (it.t === "report") {
        // The reporter's words and context are their data. The picture loads only when the owner asks for it.
        const ctx = E("ul", "vf-rep-sent"), show = btn("vf-btn vf-btn-ghost vf-btn-sm", "Show screenshot"), img = E("img", "vf-rep-shot");
        img.alt = "The reporter's screenshot"; img.hidden = true;
        show.onclick = () => { show.disabled = true; Core.reportImage(li._it.f.id).then(src => { img.src = src; img.hidden = false; show.hidden = true; }).catch(e => { show.disabled = false; fail(e); }); };
        const adds = E("ul", "vf-myrep-adds vf-rep-adds"); adds.setAttribute("aria-label", "Added by the reporter");
        extra.append(ctx, show, img, adds);
        li._k.rep = { ctx, show, adds };
      }
      return li;
    }
    function qAct(label, cls, run) { const b = btn(`vf-btn vf-btn-sm ${cls}`, label); b.onclick = run; return b; }
    function fillQItem(li, it) {
      const k = li._k, S = Core.state, owner = Core.me.isOwner;
      li._it = it;
      k.chip.textContent = QT[it.t];
      k.chip.className = "vf-chip " + ({ request: "vf-chip-accent", ready: "vf-chip-brass", merge: "vf-chip-quiet", upload: "vf-chip-quiet" }[it.t] || "vf-chip-quiet");
      const person = it.r ? [it.r.cid, it.r.name] : it.i ? [it.i.cid, it.i.name] : it.x ? [it.x.cid, it.x.name] : it.m ? [it.m.from, it.m.fromName] : it.u ? [it.u.cid, it.u.by] : it.f ? [it.f.cid, it.f.name]
        : it.j ? [it.j.pid, it.j.name] : [null, it.ready.by];
      const wk = person.join("|") + it.ts;
      if (k.who._k !== wk) {
        k.who._k = wk;
        k.who.replaceChildren(...(person[0] ? [av(person[0], person[1], 16, true)] : []), E("span", null, isMe(person[0]) ? "You" : disp(person[1] || "Someone")), E("span", "vf-card-time", ago(it.ts)));
      }
      const qid = it.qid || it.r?.qid || it.u?.qid || it.f?.ctx.qid || "", q = qid && qById(qid);
      const general = !!it.r && !it.r.qid; // a request about the whole session
      k.qref.hidden = !q && !general; if (q || general) k.qref.textContent = q ? q.id : GEN_LABEL;
      if (q || general) k.qref.setAttribute("aria-label", q ? `Open ${q.id}: ${q.text}` : "General: about the whole session");
      const txt = it.r ? `${KIND_REQ[it.r.kind] || "Request"}: ${it.r.text}` : it.i ? it.i.text : it.x ? it.x.text + (it.x.note ? `\n\nWhy: ${it.x.note}` : "")
        : it.m ? `${it.m.fromName} says they were ${it.m.toName} before. Approve to join them: ${it.m.fromName}'s answers and votes move to ${it.m.toName}.`
        : it.ready ? `${it.ready.by} marked round ${curRound().current} ready to send.`
        : it.j ? `Wants to join: ${it.j.name}${joinHint(it.j)}` : it.f ? `${it.f.status === "seen" ? "Seen. " : ""}${it.f.asked ? "Asked Claude. " : ""}${it.f.text}` : "";
      k.text.hidden = !txt;
      if (txt) fillClamp(k.text, "q:" + it.id, txt, `${QT[it.t]} from ${disp(person[1] || "someone")}`, q ? `${q.id}: ${q.text}` : "");
      if (k.up) fillUpRow(k.up, it.u);
      if (k.rep) {
        const c = it.f.ctx, v = c.visualViewport;
        k.rep.ctx.replaceChildren(...[`${VIEW_WORD[c.view] || c.view} view${c.tab ? `, ${c.tab} tab` : ""}${c.round != null ? `, round ${c.round}` : ""}`,
          `${c.device}, ${BROWSER_NAME[c.browser] || "other browser"}, ${c.viewport.w} × ${c.viewport.h}${v ? ` (visible ${Math.round(v.w)} × ${Math.round(v.h)} at ${v.scale}×)` : ""}`,
          ...(c.build ? [`Page version ${c.build}`] : []), ...c.errors.map(e => `Error: ${e}`)].map(t => E("li", null, t)));
        k.rep.show.hidden = !it.f.image || !!k.rep.show.nextSibling.getAttribute("src");
        // What the reporter added since: each line, and a screenshot that loads only when the owner asks.
        const sig = JSON.stringify(it.f.adds);
        if (k.rep.adds._sig !== sig) {
          k.rep.adds._sig = sig;
          k.rep.adds.replaceChildren(...it.f.adds.map((a, i) => {
            const row = E("li", null, `Added: ${a.text || "a screenshot"}`);
            if (a.image) {
              const b = btn("vf-lbtn", "Show screenshot"), im = E("img", "vf-rep-shot"); im.alt = "The reporter's added screenshot"; im.hidden = true;
              b.onclick = () => { b.disabled = true; Core.reportImage(li._it.f.id, i + 1).then(src => { im.src = src; im.hidden = false; b.hidden = true; }).catch(e => { b.disabled = false; fail(e); }); };
              row.append(" ", b, im);
            }
            return row;
          }));
        }
        k.rep.adds.hidden = !it.f.adds.length;
      }
      fillAtts(k.att, (it.r || it.i || it.x)?.att, `${QT[it.t]} from ${disp(person[1] || "someone")}`);
      const sig = [it.t, it.r?.status, it.u?.status, it.f?.status, it.f?.asked, owner, Core.canModerate()].join("|");
      if (k.sig === sig) return;
      k.sig = sig;
      const a = [];
      if (it.t === "request" && owner) {
        if (it.r.status === "pending") a.push(qAct("Decline", "vf-btn-ghost", () => Core.requestAct(it.r.id, "decline").then(() => flash("Request declined.")).catch(fail)),
          qAct("Run", "vf-btn-primary", () => Core.requestAct(li._it.r.id, "run").then(() => flash("Running. The result shows on the question.")).catch(runFail)));
        else if (it.r.status === "running") a.push(qAct("Mark failed", "vf-btn-ghost", () => Core.requestAct(li._it.r.id, "fail").catch(fail)));
        else a.push(qAct("Run again", "vf-btn-ghost", () => Core.requestAct(li._it.r.id, "rerun").catch(fail)));
        a.push(qAct("Edit in Requests", "vf-btn-ghost", () => openPanel(RQ.pop, reqRow.offsetParent ? reqRow : li)));
      }
      if (it.t === "proposal") a.push(
        qAct("Park", "vf-btn-ghost", guarded(PARK_ASK, () => Core.proposal(li._it.i.id, "park").then(() => flash("Parked.")).catch(fail))),
        ...(v8() ? [qAct("Later", "vf-btn-ghost", guarded(LATER_ASK, () => Core.later(li._it.i.id, "Off this session's goal").then(() => flash("Moved to Later. It becomes a tracker item when the session ends.")).catch(fail)))] : []),
        qAct("Make it a question", "vf-btn-primary", () => Core.proposal(li._it.i.id, "question").then(r => flash(`Added to round ${r.round ?? curRound().current + 1}.`)).catch(fail)));
      if (it.t === "suggestion") a.push(
        qAct("Dismiss", "vf-btn-ghost", () => Core.dismissSuggestion(li._it.qid, li._it.x.id).catch(fail)),
        qAct("Use this", "vf-btn-brass", () => Core.useSuggestion(li._it.qid, li._it.x.id).then(() => flash("Locked answer replaced.")).catch(fail)));
      if (it.t === "merge" && owner) a.push(
        qAct("Decline", "vf-btn-ghost", () => Core.mergeAct(li._it.m.id, "decline").then(() => flash("Kept apart.")).catch(fail)),
        qAct("Approve", "vf-btn-primary", guarded(() => ({ title: `Join ${li._it.m.fromName} and ${li._it.m.toName}?`, ok: "Join them", body: `${li._it.m.fromName}'s answers, votes, chat and suggestions move to ${li._it.m.toName}. This cannot be undone.` }),
          () => Core.mergeAct(li._it.m.id, "approve").then(() => flash("Joined.")).catch(fail))));
      if (it.t === "report" && owner) a.push(
        ...(!it.f.asked ? [qAct("Ask Claude about this report", "vf-btn-ghost vf-rep-ask", guarded(REPORT_ASK, () => Core.reportAct(li._it.f.id, "ask").then(() => flash("Asked. Claude proposes a fix in the terminal.")).catch(fail)))] : []),
        ...(it.f.status === "open" ? [qAct("Seen", "vf-btn-ghost", () => Core.reportAct(li._it.f.id, "seen").then(() => flash("Marked seen. The reporter is told.")).catch(fail))] : []),
        qAct("Resolved", "vf-btn-primary", () => Core.reportAct(li._it.f.id, "resolved").then(() => flash("Resolved. The reporter is told.")).catch(fail)));
      if (it.t === "ready" && owner) a.push(qAct("Send round to Claude", "vf-btn-primary", e => roundAction(e.currentTarget)));
      if (it.t === "join" && owner) a.push(
        qAct("Decline", "vf-btn-ghost", () => Core.joinAct(li._it.j.pid, "decline").then(() => flash(`${li._it.j.name} was not let in. Restore them from Settings if that was a mistake.`)).catch(fail)),
        qAct("Let in", "vf-btn-primary", () => Core.joinAct(li._it.j.pid, "admit").then(() => flash(`${li._it.j.name} is in.`)).catch(fail)));
      k.acts.replaceChildren(...a);
      k.acts.hidden = !a.length;
    }
    function renderHost(S) {
      const R = curRound(), owner = Core.me.isOwner, mod = Core.canModerate();
      // round
      const n = R.current, rq = S.questions.filter(q => roundOf(q) === n), decided = rq.filter(q => Core.lockOf(q.id)).length;
      const sent = isSentStatus(R.status);
      hRoundName.textContent = `Round ${n}: ${sent ? (R.status === "working" ? "Claude is working on it" : "waiting for Claude") : `${decided} of ${rq.length} decided`}`;
      hSteps.hidden = !sent; if (sent) fillStepper(hSteps, R);
      const props = S.ideas.filter(i => i.status === "new").length;
      hRoundNote.textContent = sent ? (R.status === "working" ? "If Claude stopped responding, you can reset the round. Otherwise message Claude in the terminal." : "You can still cancel sending until Claude picks it up.")
        : `${props} proposal${props === 1 ? "" : "s"} go${props === 1 ? "es" : ""} with it. ${R.ready ? `${disp(R.ready.by)} marked it ready.` : ""}`.trim();
      hSend.hidden = !mod || sent || !!S.ended;
      hSend.textContent = owner ? "Send round to Claude" : R.ready ? "Marked ready: undo" : "Mark round ready";
      hCancel.hidden = !(owner && (R.status === "sent" || R.status === "preparing"));
      hReset.hidden = !(owner && R.status === "working");
      hRoundRow.hidden = hSend.hidden && hCancel.hidden && hReset.hidden;
      hGoal.textContent = S.goal || "No goal yet. One goal keeps the session small: one ticket or one slice.";
      hGoal.classList.toggle("vf-hgoal-empty", !S.goal);
      hGoalEdit.hidden = !owner || !v8(); hGoalEdit.textContent = S.goal ? "Edit goal" : "Set a goal";
      hGoalLabel.hidden = hGoalRow.hidden = !v8();
      // why you're here: the owner edits it; a leader reads it
      hIntroIn.hidden = hIntroRow.hidden = !owner;
      hIntroShown.hidden = owner;
      hIntroShown.textContent = S.intro || "No introduction yet.";
      if (owner && document.activeElement !== hIntroIn && !ui.introDirty && hIntroIn.value !== S.intro) hIntroIn.value = S.intro;
      counter(hIntroCount, hIntroIn, 500);
      hIntroSave.disabled = !ui.introDirty;
      // queue
      const items = queueItems(S), counts = {};
      for (const it of items) counts[it.t] = (counts[it.t] || 0) + 1;
      for (const [k, b] of Object.entries(qfBtns)) {
        const c = k === "all" ? items.length : counts[k] || 0;
        b.setAttribute("aria-pressed", String(ui.hostFilter === k));
        b.lastChild.textContent = c ? String(c) : "";
        b.hidden = !owner && ["request", "merge", "upload", "report"].includes(k);
      }
      const shown = ui.hostFilter === "all" ? items : items.filter(i => i.t === ui.hostFilter);
      sync(queueList, queueMore.page(shown, queueList, "queue:" + ui.hostFilter), i => i.id, makeQItem, fillQItem);
      queueEmpty.hidden = shown.length > 0;
      queueEmpty.textContent = ui.hostFilter === "all" ? "All clear. New requests, proposals, suggestions, merges and files show up here." : `No ${QT[ui.hostFilter]?.toLowerCase() || "items"} waiting.`;
      hQueue._m.textContent = `${items.length} waiting`;
      // people
      const here = new Map(S.presence.map(p => [p.cid, p])), gone = new Set(S.removed || []);
      // You first, then Active, Away, Offline (the most recently seen first), the owner first within each, then by name.
      const rank = p => ["active", "away", "offline"].indexOf(presState(here.get(p.pid)));
      const ppl = Object.entries(S.people || {}).map(([pid, v]) => ({ pid, ...v })).filter(p => owner || !gone.has(p.pid))
        .sort((a, b) => isMe(b.pid) - isMe(a.pid) || rank(a) - rank(b) || (rank(a) === 2 && (b.seen || 0) - (a.seen || 0))
          || (b.pid === S.ownerPid) - (a.pid === S.ownerPid) || a.name.localeCompare(b.name));
      const answeredBy = {};
      for (const lst of Object.values(S.answers)) for (const a of lst) if (!a.claude && !a.option) answeredBy[a.cid] = (answeredBy[a.cid] || 0) + 1;
      const lastCtx = {}, lastTs = {}; // each person's newest recorded context: answers and suggestions carry one
      for (const r of [...Object.values(S.answers).flat(), ...Object.values(S.suggestions || {}).flat()]) if (r.ctx && !(lastTs[r.cid] > r.ts)) { lastCtx[r.cid] = r.ctx; lastTs[r.cid] = r.ts; }
      const pres = p => (gone.has(p.pid) ? "removed" : presState(here.get(p.pid)));
      const inFilter = { all: () => true, here: p => ["active", "away"].includes(pres(p)), away: p => pres(p) === "away", offline: p => pres(p) === "offline", removed: p => pres(p) === "removed" };
      const noRemoved = !owner || !ppl.some(inFilter.removed);
      if (noRemoved && ui.peopleFilter === "removed") ui.peopleFilter = "all";
      for (const [k, b] of Object.entries(pfBtns)) {
        b.setAttribute("aria-pressed", String(ui.peopleFilter === k));
        b.lastChild.textContent = String(ppl.filter(inFilter[k]).length);
        b.hidden = k === "removed" && noRemoved;
      }
      pFind.hidden = ppl.length <= 12;
      const find = pFind.hidden ? "" : ui.peopleFind.trim().toLowerCase();
      const pShown = ppl.filter(p => inFilter[ui.peopleFilter](p) && (!find || disp(p.name).toLowerCase().includes(find)));
      peopleEmpty.hidden = pShown.length > 0;
      peopleEmpty.textContent = find ? `No one named “${ui.peopleFind.trim()}” here.` : "No one to show.";
      // A name more than one person holds (names hidden from guests let it repeat): each gets its join-order number here.
      const nth = {}, byName = {};
      for (const p of [...ppl].sort((a, b) => a.ts - b.ts)) (byName[p.name.toLowerCase()] ||= []).push(p.pid);
      for (const pids of Object.values(byName)) if (pids.length > 1) pids.forEach((pid, i) => { nth[pid] = i + 1; });
      sync(peopleList, peopleMore.page(pShown, peopleList, "people:" + ui.peopleFilter), p => p.pid, () => {
        const li = E("li", "vf-hperson");
        const avBox = E("span", "vf-hp-av"), mid = E("div", "vf-hp-mid"), nm = E("span", "vf-hp-name"), meta = E("span", "vf-hp-meta");
        const role = E("span", "vf-role"), ctxB = E("span", "vf-ctx"); ctxB.hidden = true;
        const nameRow = E("span", "vf-hp-namerow"); nameRow.append(nm, role, ctxB);
        mid.append(nameRow, meta);
        const acts = E("div", "vf-hp-acts");
        const lead = btn("vf-btn vf-btn-ghost vf-btn-sm vf-toggle", "Leader"), trust = btn("vf-btn vf-btn-ghost vf-btn-sm vf-toggle", "Trusted");
        const merge = btn("vf-btn vf-btn-ghost vf-btn-sm", "Merge…"), remove = btn("vf-btn vf-btn-ghost vf-btn-sm vf-btn-danger", "Remove");
        const view = btn("vf-btn vf-btn-ghost vf-btn-sm vf-hp-view", "View all");
        acts.append(view, lead, trust, merge, remove);
        li.append(avBox, mid, acts);
        view.onclick = () => openPersonView(li._p.pid, view);
        lead.onclick = () => { const p = li._p, was = Core.state.leaders.includes(p.pid); Core.setLeader(p.pid, !was).then(() => flash(was ? "Leader removed." : "Leader added.")).catch(fail); };
        trust.onclick = () => { const p = li._p, was = Core.state.trusted.includes(p.pid); Core.setTrusted(p.pid, !was).then(() => flash(was ? "Trust removed." : "Trusted.")).catch(fail); };
        merge.onclick = () => { const a = avBox.firstChild; showCard(a, true); ui.mergeFrom = li._p.pid; ui.mergeTo = ""; fillPcard(); };
        remove.onclick = guarded(() => !(Core.state.removed || []).includes(li._p.pid) && removeAsk(li._p.name), () => { const p = li._p, out = (Core.state.removed || []).includes(p.pid); Core.removePerson(p.pid, !out).then(() => flash(out ? "Restored. Their content shows again." : `${disp(p.name)} was removed. Their content is hidden.`)).catch(fail); });
        li._k = { avBox, nm, meta, role, ctxB, lead, trust, merge, remove, view, acts, avKey: "" };
        return li;
      }, (li, p) => {
        const k = li._k, h = here.get(p.pid), rl = roleOf(p.pid), isGone = gone.has(p.pid), me2 = isMe(p.pid);
        li._p = p;
        const key = p.pid + "|" + p.name;
        if (k.avKey !== key) { k.avKey = key; k.avBox.replaceChildren(av(p.pid, p.name, 26, true)); }
        presDot(k.avBox.firstChild, h).setAttribute("aria-label", `${disp(p.name)}, ${presWord(h)}, show details`);
        k.nm.textContent = disp(p.name) + (nth[p.pid] && Core.canModerate() ? ` (${nth[p.pid]})` : "") + (me2 ? " (you)" : "");
        k.role.textContent = isGone ? "Removed" : rl; k.role.className = `vf-role vf-role-${isGone ? "removed" : rl.toLowerCase()}`;
        const hq = h?.q && qById(h.q);
        // Active, Away (with how long), or offline: no heartbeat for a while, so not in presence at all.
        const last = h ? (h.away ? `Away${awayFor(h)}` : hq ? `Active, on ${hq.id}` : "Active") : p.seen ? `Offline, last active ${ago(p.seen)} ago` : `Offline, joined ${ago(p.ts)} ago`;
        const na = answeredBy[p.pid] || 0;
        k.meta.textContent = `${last}. ${na} answered${h?.typing ? ", typing" : ""}`;
        ctxBadge(k.ctxB, owner ? lastCtx[p.pid] : null);
        li.dataset.here = String(!!h);
        li.dataset.presence = presState(h);
        li.classList.toggle("vf-hperson-gone", isGone);
        const can = owner && !me2 && rl !== "Host";
        k.acts.hidden = !can;
        k.lead.setAttribute("aria-pressed", String(S.leaders.includes(p.pid))); k.trust.setAttribute("aria-pressed", String(S.trusted.includes(p.pid)));
        k.lead.hidden = k.trust.hidden = isGone;
        k.remove.textContent = isGone ? "Restore" : "Remove";
        k.lead.setAttribute("aria-label", `Leader: ${disp(p.name)}`); k.trust.setAttribute("aria-label", `Trusted: ${disp(p.name)}`);
        k.merge.setAttribute("aria-label", `Merge ${disp(p.name)} into someone`); k.remove.setAttribute("aria-label", `${isGone ? "Restore" : "Remove"} ${disp(p.name)}`);
        k.view.setAttribute("aria-label", `View everything ${disp(p.name)} did`);
      });
      if (ui.pop === personPop) fillPersonView();
      const nAway = S.presence.filter(p => p.away).length;
      hPeople._m.textContent = `${S.presence.length} here${nAway ? ` (${nAway} away)` : ""}, ${ppl.filter(p => !gone.has(p.pid)).length} joined`;
      // links and settings
      hNewGuest.hidden = hNewOwner.hidden = hSettings.hidden = hEnd.hidden = !owner;
      const nl = laterItems().length;
      hEnd.textContent = S.ended ? "Reopen session" : "End session";
      hEndNote.textContent = owner && !S.ended ? (nl ? `Ending makes the page read-only for guests. ${laterLine(nl)}.` : "Ending makes the page read-only for guests, with the final tree.") : "";
      hEndNote.hidden = !hEndNote.textContent;
      hLinks._t.textContent = owner ? "Links and settings" : "Links";
      // later
      const later = laterItems().sort((a, b) => a.ts - b.ts);
      hLater.hidden = !v8() && !later.length;
      hLater._m.textContent = later.length ? String(later.length) : "";
      laterNote.textContent = later.length ? `${laterLine(later.length)} when the session ends.` : "";
      laterNote.hidden = !later.length;
      sync(laterList, laterMore.page(later, laterList), i => i.id, () => {
        const li = E("li", "vf-pitem");
        const t = clampBox(), why = E("p", "vf-why"), from = E("div", "vf-pfrom"), acts = E("div", "vf-acts");
        const back = lbtn("vf-btn vf-btn-ghost vf-btn-sm", "restore", "Back to Proposed");
        const make = btn("vf-btn vf-btn-ghost vf-btn-sm", "Make it a question");
        back.onclick = () => Core.proposal(li._i.id, "restore").then(() => flash("Back in Proposed.")).catch(fail);
        make.onclick = () => Core.proposal(li._i.id, "question").then(r => flash(`Added to round ${r.round ?? curRound().current + 1}.`)).catch(fail);
        acts.append(back, make);
        li.append(t, why, from, acts);
        li._k = { t, why, from, acts };
        return li;
      }, (li, i) => {
        const k = li._k; li._i = i;
        fillClamp(k.t, "lt:" + i.id, i.text, `Later, from ${disp(i.name)}`, "");
        k.why.textContent = i.reason ? `Why later: ${i.reason}` : ""; k.why.hidden = !i.reason;
        const fk = i.cid + i.name;
        if (k.from._k !== fk) { k.from._k = fk; k.from.replaceChildren(av(i.cid, i.name, 16), E("span", null, disp(i.name)), E("span", "vf-card-time", ago(i.ts))); }
        k.acts.hidden = !mod;
      });
      laterEmpty.hidden = later.length > 0;
    }

    function render() {
      if (dead) return;
      const S = Core.state, me = Core.me, s = S.settings, mod = Core.canModerate();
      // The rail keeps round order (S.questions); answered ones carry a mark instead of moving.
      const qs = S.questions, owner = Core.owner(), here = S.presence;
      // ux-review-2 #7: the viewer counts as here from the moment the page loads, before their first heartbeat lands.
      const hereN = here.length + (here.some(p => isMe(p.cid)) ? 0 : 1);
      migratePrefs(); follow.setAttribute("aria-pressed", String(following()));
      if (following() && owner && !isMe(owner.cid) && owner.q && owner.q !== ui.cur && S.questions.some(q => q.id === owner.q)) { select(owner.q); return; }
      const R = curRound(), cur = R.current;
      if (!S.questions.some(q => q.id === ui.cur) && qs.length) {
        const inCur = S.questions.filter(q => roundOf(q) === cur), back = qById(ui.restoreCur);
        ui.restoreCur = "";
        select((back || inCur.find(q => isOpenForMe(q.id)) || inCur[0] || S.questions[0]).id); return;
      }
      applyTheme();
      paintTheme();

      // round changes: a toast with a way to go there; the view moves only for people following the host
      if (Core.live) {
        if (ui.round == null) { ui.round = cur; ui.rstat = R.status; }
        else if (cur > ui.round) {
          ui.round = cur; ui.rstat = R.status; ui.freshRound = cur; ui.cmpRound = null;
          const first = S.questions.find(q => roundOf(q) === cur);
          flash(`Round ${cur} is here.`, first && first.id !== ui.cur ? { label: `Go to round ${cur}`, run: () => focusQuestion(first.id) } : null);
        } else if (R.status !== ui.rstat) {
          const was = ui.rstat; ui.rstat = R.status;
          if (R.status === "sent" || R.status === "preparing") flash(`Round ${cur} went to Claude. It is read-only now; waiting for Claude to pick it up.`);
          else if (R.status === "working") flash(`Claude is working on round ${cur + 1}.`);
          else if (was === "working" && R.status === "open") flash(`The host reset round ${cur}. It is open again.`);
          else if (isSentStatus(was) && R.status === "open") flash(`Sending round ${cur} was cancelled. It is open again.`);
        }
      }
      notices(S);
      pumpUploads();
      // New answers from others on the question I am on: one polite summary, never the list itself.
      const heardQ = ui.cur, others0 = Core.answersFor(heardQ).filter(a => !isMe(a.cid)).length;
      if (ui.heard.q === heardQ && others0 > ui.heard.n) announce(`${others0 - ui.heard.n} new answer${others0 - ui.heard.n > 1 ? "s" : ""} on ${heardQ}`);
      ui.heard = { q: heardQ, n: others0 };
      if (R.status !== "open" && ui.pop === confirmPop) closePop();

      // top bar
      const title = S.title || "Interview";
      if (titleTxt.textContent !== title) titleTxt.textContent = title;
      titleEdit.hidden = !me.isOwner || !titleInput.hidden;
      const goal = S.goal || "";
      if (goalTxt.textContent !== goal) goalTxt.textContent = goal;
      goalTxt.title = goal;
      goalInput.hidden = !ui.goalEditing;
      goalTxt.hidden = ui.goalEditing || !goal;
      goalAdd.hidden = ui.goalEditing || !!goal || !me.isOwner || !v8();
      goalEdit.hidden = ui.goalEditing || !goal || !me.isOwner || !v8();
      goalRow.hidden = !ui.goalEditing && !goal && goalAdd.hidden;
      askTop.hidden = (!!S.ended && !me.isOwner) || !!S.youRemoved;
      if (askTop.hidden && ui.pop === askPanel) closePop();
      root.dataset.live = Core.live ? "on" : "off";
      liveTxt.textContent = Core.live ? "Live" : "Reconnecting…";
      const ppl = [...here].sort((a, b) => isMe(b.cid) - isMe(a.cid) || !!a.away - !!b.away);
      sync(people, ppl.slice(0, 7), p => p.cid, p => {
        const b = btn("vf-person vf-person-act");
        b.append(av(p.cid, p.name, 26));
        return b;
      }, (b, p) => {
        const role = p.owner ? "host" : p.leader ? "leader" : "";
        const label = `${disp(p.name)}${isMe(p.cid) ? " (you)" : ""}${role ? ", " + role : ""}, ${presWord(p)}. Show details`;
        b.setAttribute("aria-label", label);
        b.dataset.role = role;
        b.dataset.presence = presState(p);
        b.title = p.away ? `${disp(p.name)}: away${awayFor(p)}` : "";
        // data-pid on the button itself, so Enter and Space (which click the button, not the avatar) open the card
        b.dataset.pid = p.cid; b.dataset.name = p.name;
        b.classList.toggle("vf-person-me", isMe(p.cid));
        const a = b.firstChild;
        if (a.textContent !== Core.initials(p.name) || a.dataset.name !== p.name) b.replaceChildren(av(p.cid, p.name, 26));
        presDot(b.firstChild, p);
      });
      hereCount.textContent = here.length > 7 ? `+${here.length - 7}` : `${hereN} here`;
      follow.hidden = me.isOwner || !s.follow;
      followTxt.textContent = owner ? `Follow ${disp(owner.name)}` : "Follow host";
      follow.classList.toggle("vf-dim", !owner);
      gear.hidden = !me.isOwner;
      shareBtn.hidden = !mod; // owner and leaders: the guest link carries no owner rights
      if (!mod && ui.pop === sharePop) closePop();
      if (!me.isOwner && ui.pop === settingsPop) closePop();
      if (ui.pcard) fillPcard();

      // popovers
      for (const [k, b] of Object.entries(switches)) b.setAttribute("aria-checked", String(k === "hideClaude" ? s[k] !== false : !!s[k]));
      switches.signoff.disabled = !s.voting;
      switches.hideClaude.hidden = !v8();
      const nLater = laterItems().length;
      endNote.textContent = !S.ended && nLater ? `${laterLine(nLater)}.` : "";
      endNote.hidden = !endNote.textContent;
      ownerTheme._paint();
      const url = Core.guestLink();
      if (shareField.value !== url) shareField.value = url;
      nativeShare.hidden = !(navigator.share && phone.matches);
      // A new tunnel address since the last start: the old guest link is dead until shared again.
      const reshare = mod && !!S.shareChanged && store.get("vf-share-ack", "") !== url;
      shareNew.hidden = !reshare;
      shareNew.textContent = "New guest link, share again: the link people have from before no longer works.";
      shareBtn.classList.toggle("vf-tbtn-alert", reshare);
      shareTxt.textContent = reshare ? "Share again" : "Share";
      shareBtn.setAttribute("aria-label", reshare ? "New guest link, share again" : "Share the guest link");
      endBtn.textContent = S.ended ? "Reopen session" : "End session";
      const gone = S.removed || [];
      removedHead.hidden = removedList.hidden = !gone.length;
      sync(removedList, gone, p => p, p => {
        const li = E("li", "vf-removed-item"), restore = btn("vf-btn vf-btn-ghost vf-btn-sm", "Restore");
        li.append(E("span", "vf-removed-name"), restore);
        restore.onclick = () => Core.removePerson(p, false).then(() => flash("Restored. Their content shows again.")).catch(fail);
        return li;
      }, (li, p) => { li.firstChild.textContent = disp(nameOf(p)); li.lastChild.setAttribute("aria-label", `Restore ${disp(nameOf(p))}`); });

      // session banner: removed, ended, or a link to share again
      const bn = S.youMerged ? ["This browser was merged into the owner. Open your owner link here.", null]
        : S.youWaiting ? ["Waiting for the host to let you in.", null]
        : S.youRemoved ? ["The host removed you from this session. You can still read it.", null]
        : S.ended ? [me.isOwner ? "You ended this session. Guests see it read-only, with the final tree." : "This session has ended. Here is what it decided.",
          me.isOwner ? ["Reopen", () => Core.endSession(false).catch(fail)] : ["Show the tree", () => setMode("tree")]]
        : reshare ? ["New guest link, share again: the old link no longer works.", ["Share", () => openPop(sharePop, shareBtn.offsetParent ? shareBtn : bannerAct)]]
        : null;
      banner.hidden = !bn;
      if (bn) {
        bannerTxt.textContent = bn[0];
        bannerAct.hidden = !bn[1];
        if (bn[1]) { bannerAct.textContent = bn[1][0]; bannerAct.onclick = bn[1][1]; }
      }
      if (S.ended && !me.isOwner && !ui.endedShown) { ui.endedShown = true; setMode("tree"); if (phone.matches) setTab("tree"); return; }
      if (!S.ended) ui.endedShown = false;

      // rail
      const answered = S.questions.filter(q => myState(q.id) !== "open" || Core.lockOf(q.id)).length;
      railMeta.textContent = `${S.questions.filter(q => myState(q.id) !== "open").length} of ${S.questions.length} answered`;
      const byRound = new Map(), shownQs = shownQuestions(), cuNow = catchUp();
      for (const x of shownQs) { const r = roundOf(x); if (!byRound.has(r)) byRound.set(r, []); byRound.get(r).push(x); }
      const roundNums = [...new Set([...qs.map(roundOf), cur])].sort((a, b) => a - b);
      const railNums = roundNums.filter(n => byRound.has(n) || (n === cur && (tb().round === "all" || tb().round === String(n))));
      sync(groups, railNums, n => n, n => {
        const g = E("section", "vf-round");
        const head = E("div", "vf-rhead");
        const toggle = btn("vf-rtoggle");
        const tLabel = E("span", "vf-rlabel");
        const check = E("span", "vf-rcheck"); check.append(icon("check"));
        toggle.append(check, tLabel, icon("chevR", "vf-i vf-chev"));
        toggle.onclick = () => { const o = openRounds(); o.has(n) ? o.delete(n) : o.add(n); setOpenRounds(o); };
        const curHead = E("div", "vf-rcur");
        const title2 = E("div", "vf-rtitle");
        const name = E("h2", "vf-rname"), meta = E("span", "vf-meta");
        title2.append(name, meta);
        const prog = E("div", "vf-rprog"); prog.append(E("span"));
        const send = btn("vf-btn vf-btn-sm vf-send", "Send round to Claude");
        send.onclick = () => roundAction(send);
        const readyNote = E("p", "vf-ready");
        curHead.append(title2, prog, send, readyNote);
        head.append(toggle, curHead);
        const ul = E("ul", "vf-qlist"); ul.setAttribute("role", "list");
        if (ui.freshRound === n) ul._primed = true; // a round that opened while we watched animates its questions in
        const cu = catchUpEl(); // shown above the current round only
        g.append(cu, head, ul);
        g._k = { toggle, tLabel, check, curHead, name, meta, prog, send, readyNote, ul, cu };
        return g;
      }, (g, n) => {
        const k = g._k, list = byRound.get(n) || [], isCur = n === cur, inRound = qs.filter(x => roundOf(x) === n);
        const decided = inRound.filter(x => Core.lockOf(x.id)).length, all = inRound.length > 0 && decided === inRound.length;
        const expanded = isCur || openRounds().has(n);
        g.classList.toggle("vf-round-cur", isCur);
        k.cu._paint(isCur ? cuNow : null);
        k.toggle.hidden = isCur; k.curHead.hidden = !isCur;
        k.toggle.setAttribute("aria-expanded", String(expanded));
        // ux-review-2 #7: guests count what they answered; "decided" is the moderators' word.
        const done = mod ? decided : inRound.filter(x => myState(x.id) !== "open").length, word = mod ? "decided" : "answered";
        k.tLabel.textContent = n > cur ? `Round ${n}, opens after round ${cur}` : `Round ${n}, ${done} of ${inRound.length} ${word}`;
        k.check.hidden = !done;
        k.name.textContent = `Round ${n}`;
        k.meta.textContent = list.length < inRound.length ? `${list.length} of ${inRound.length} shown` : `${done} of ${inRound.length} ${word}`;
        k.prog.firstChild.style.transform = `scaleX(${inRound.length ? done / inRound.length : 0})`;
        k.prog.classList.toggle("vf-full", all);
        const ready = R.ready, owner1 = me.isOwner;
        k.send.hidden = !mod || R.status !== "open" || !!S.ended || !inRound.length;
        k.send.textContent = owner1 ? "Send round to Claude" : ready ? "Marked ready: undo" : "Mark round ready";
        k.send.classList.toggle("vf-btn-primary", owner1 ? all || !!ready : !ready);
        k.send.classList.toggle("vf-btn-ghost", !k.send.classList.contains("vf-btn-primary"));
        k.send.title = owner1 ? (all ? "Every question is decided. Hand the round to Claude." : "Some questions are still open")
          : "Only the host sends a round to Claude. Mark it ready to tell them.";
        k.readyNote.hidden = !(isCur && ready && R.status === "open");
        k.readyNote.textContent = ready ? `${ready.by === me.name ? "You" : disp(ready.by)} marked this round ready ${ago(ready.ts) === "now" ? "just now" : ago(ready.ts) + " ago"}.` : "";
        k.ul.hidden = !expanded;
        sync(k.ul, list, x => x.id, makeQ, (li, x) => {
          fillQ(li, x);
          if (li.classList.contains("vf-in") && !li._delayed) { li.style.animationDelay = `${Math.min(list.indexOf(x), 6) * 40}ms`; li._delayed = true; }
        });
      });
      const nextN = cur + 1, preparing = isSentStatus(R.status);
      nextBox.classList.toggle("vf-preparing", preparing);
      const sentAgo = R.sentAt ? ago(R.sentAt) : "";
      nextTxt.hidden = preparing;
      nextTxt.textContent = `Round ${nextN}: Claude prepares it when the host sends this round`;
      railSteps.hidden = !preparing;
      if (preparing) fillStepper(railSteps, R);
      stepNote.hidden = !preparing;
      stepNote.textContent = R.status === "working" ? (me.isOwner ? "If Claude stopped responding, reset the round from the Host view." : "The host can message Claude in the terminal.")
        : `Sent${sentAgo && sentAgo !== "now" ? ` ${sentAgo} ago` : " just now"}.${me.isOwner ? " You can cancel until Claude picks it up." : ""}`;
      cancelSend.hidden = !((R.status === "sent" || R.status === "preparing") && me.isOwner);

      // proposed
      const props = S.ideas.filter(i => i.status === "new").sort((a, b) => b.ts - a.ts);
      const notPlaced = S.ideas.filter(i => i.status === "notplaced").sort((a, b) => b.ts - a.ts);
      const parked = S.ideas.filter(i => i.status === "parked").sort((a, b) => b.ts - a.ts);
      propRow.hidden = !mod;
      propRow._count.textContent = String(props.length);
      propRow.classList.toggle("vf-has", props.length > 0);
      propRow.setAttribute("aria-label", `Proposed questions, ${props.length} waiting`);
      if (!mod && ui.pop === PP.pop) closePop();
      propNewBtn.textContent = `New ${props.length}`; propNotBtn.textContent = `Not placed ${notPlaced.length}`; propParkBtn.textContent = `Parked ${parked.length}`;
      propNewBtn.setAttribute("aria-pressed", String(ui.propFilter === "new"));
      propNotBtn.setAttribute("aria-pressed", String(ui.propFilter === "notplaced"));
      propParkBtn.setAttribute("aria-pressed", String(ui.propFilter === "parked"));
      const joins = v8() ? nextN : preparing ? nextN : cur;
      PP.note.textContent = ui.propFilter === "new"
        ? `These go to Claude with round ${cur}${preparing ? " (already sent; they wait for the next send)" : ""}. Claude places each one. A question you make now joins round ${joins}.`
        : ui.propFilter === "notplaced" ? "Claude did not place these and said why. Restore one to send it again."
        : "Parked proposals stay out of the round. Restore one to put it back in New.";
      const shown = !mod ? [] : ui.propFilter === "new" ? props : ui.propFilter === "notplaced" ? notPlaced : parked;
      sync(PP.list, propMore.page(shown, PP.list, "proposals:" + ui.propFilter), i => i.id, i => {
        const li = E("li", "vf-pitem");
        const t = clampBox(), from = E("div", "vf-pfrom");
        const acts = E("div", "vf-acts");
        const yes = btn("vf-btn vf-btn-primary vf-btn-sm", "Make it a question");
        const no = btn("vf-btn vf-btn-ghost vf-btn-sm", "Park");
        const back = lbtn("vf-btn vf-btn-ghost vf-btn-sm", "restore", "Restore");
        const why = E("p", "vf-why");
        yes.onclick = () => Core.proposal(i.id, "question").then(r => flash(`Added to round ${r.round ?? curRound().current + 1}.`)).catch(fail);
        no.onclick = guarded(PARK_ASK, () => Core.proposal(i.id, "park").then(() => flash("Parked.")).catch(fail));
        back.onclick = () => Core.proposal(i.id, "restore").then(() => flash("Restored to New.")).catch(fail);
        acts.append(yes, back, no);
        const att = attRowEl();
        li.append(t, why, from, att, acts);
        li._k = { t, att, why, from, yes, no, back };
        return li;
      }, (li, i) => {
        const k = li._k;
        fillClamp(k.t, "p:" + i.id, i.text, `Proposal from ${disp(i.name)}`, "");
        fillAtts(k.att, i.att, `Proposal from ${disp(i.name)}`);
        k.why.textContent = i.reason ? `Claude: ${i.reason}` : ""; k.why.hidden = !i.reason;
        k.from.replaceChildren(av(i.cid, i.name, 16), E("span", null, `${disp(i.name)}${i.via ? ", from chat" : ""}`), E("span", "vf-card-time", ago(i.ts)));
        k.no.hidden = i.status === "parked"; k.back.hidden = i.status === "new";
        li.classList.toggle("vf-pitem-parked", i.status === "parked");
      });
      PP.empty.hidden = shown.length > 0;
      PP.empty.textContent = ui.propFilter === "new" ? "Nothing proposed yet. Anyone can use Propose a question; a moderator can also propose a chat message."
        : ui.propFilter === "notplaced" ? "Claude placed everything so far." : "Nothing parked.";
      // My own proposals and where each stands; the newest few.
      const host = owner ? disp(owner.name) : "the host";
      const mine = S.ideas.filter(i => isMe(i.cid)).sort((a, b) => b.ts - a.ts).slice(0, 4);
      const PSTAT = { new: `Waiting: goes to Claude with round ${preparing ? nextN : cur}`, notplaced: "Not placed", parked: `Parked by ${host}`,
        question: "Became a question", placed: "Placed by Claude", merged: "Merged into", suggested: "A suggested change on", later: "Later" };
      myProp.hidden = !mine.length;
      sync(myProp, mine, i => i.id, () => { const li = E("li", "vf-mp"); li._att = attRowEl(); li.append(clampBox("vf-mp-txt"), li._att, E("span", "vf-mp-stat")); return li; }, (li, i) => {
        fillClamp(li.firstChild, "mp:" + i.id, i.text, "Your proposal", "");
        fillAtts(li._att, i.att, "Your proposal");
        const asQ = i.qid && !["merged", "suggested"].includes(i.status) ? ` as ${i.qid}` : i.qid ? ` ${i.qid}` : "";
        li.lastChild.textContent = PSTAT[i.status] ? `${PSTAT[i.status]}${asQ}${i.reason ? `: ${i.reason}` : ""}` : i.status;
        li.dataset.stat = i.status;
      });

      // requests (owner only; everyone else sees counts)
      const reqs = (S.requests || []).slice().sort((a, b) => a.ts - b.ts);
      const pending = reqs.filter(r => r.status === "pending");
      reqRow.hidden = !me.isOwner;
      reqRow._count.textContent = String(pending.length);
      reqRow.classList.toggle("vf-has", pending.length > 0);
      reqRow.setAttribute("aria-label", `Requests for Claude, ${pending.length} waiting`);
      if (!me.isOwner && ui.pop === RQ.pop) closePop();
      sync(RQ.list, me.isOwner ? reqs : [], r => r.id, makeReq, fillReq);
      RQ.empty.hidden = reqs.length > 0;
      RQ.empty.textContent = "No requests. People ask from Ask Claude, on a question or in the top bar.";
      const runnable = pending.filter(r => ui.reqSeen.has(r.id)).length;
      runAllBtn.lastChild.textContent = `Run all shown (${runnable})`;
      runAllBtn.setAttribute("aria-disabled", String(!runnable));
      runAllBtn.disabled = !runnable;
      runAllBtn.hidden = !pending.length;
      proposeBtn.hidden = (!!S.ended && !me.isOwner) || !!S.youRemoved;
      if (proposeBtn.hidden && ui.pop === proposePop) closePop();
      railFoot.hidden = propRow.hidden && myProp.hidden && reqRow.hidden && proposeBtn.hidden;

      function makeQ(q) {
        const li = E("li");
        const b = btn("vf-q"); b.dataset.qid = q.id;
        // The marker shows the id number (hidden from screen readers: the aria-label says it).
        const stat = E("span", "vf-qstat"), num = E("span", "vf-qnum", q.id.slice(1)), badge = E("span", "vf-qlock");
        stat.setAttribute("aria-hidden", "true"); stat.dataset.long = String(num.textContent.length > 2);
        badge.append(icon("lock")); stat.append(num, badge);
        const mid = E("span", "vf-qmid"); mid.append(E("span", "vf-qtxt"), E("span", "vf-chip vf-chip-brass"), E("span", "vf-review vf-review-sm"));
        mid.lastChild.append(icon("alert"), E("span"));
        const side = E("span", "vf-qside"); side.append(E("span", "vf-avrow"), dots(), E("span", "vf-newdot"));
        b.append(stat, mid, side);
        b.onclick = () => { select(q.id, { manual: true }); if (phone.matches) setTab(ui.mode === "compare" ? "compare" : "answer"); };
        li.append(b); return li;
      }
      function fillQ(li, q) {
        const b = li.firstChild, [, mid, side] = b.children;
        const mine = myState(q.id), lk = Core.lockOf(q.id), others = Core.others(q.id), typing = others.some(p => p.typing);
        const nSug = openSugs(q.id).length;
        b.classList.toggle("vf-q-cur", q.id === ui.cur);
        b.setAttribute("aria-current", q.id === ui.cur ? "true" : "false");
        b.dataset.stat = lk ? "locked" : { answered: "done", took: "took", soft: "soft" }[mine] || "";
        b.title = lk ? "Locked" : { answered: "Answered", took: "Took part", soft: "Optional: someone answered" }[mine] || "Open";
        mid.children[0].textContent = q.text;
        mid.children[1].textContent = mod && lk && nSug ? `${nSug} suggestion${nSug > 1 ? "s" : ""}` : "";
        mid.children[1].hidden = !mid.children[1].textContent;
        const rv = reviewText(q);
        mid.children[2].lastChild.textContent = rv; mid.children[2].hidden = !rv;
        avStack(side.firstChild, others, 3, 18);
        side.children[1].classList.toggle("vf-on", typing);
        const seenTs = ui.seen[q.id];
        const fresh = q.id !== ui.cur && seenTs != null && Core.answersFor(q.id).some(a => a.ts > seenTs && !isMe(a.cid));
        side.lastChild.hidden = !fresh;
        const qt = q.text.trim(), qEnd = /[.?!]$/.test(qt) ? "" : ".";
        b.setAttribute("aria-label", `Question ${q.id.slice(1)}: ${qt}${qEnd} ${lk ? "Locked." : { answered: "You answered.", took: "You took part.", soft: "Optional: someone answered." }[mine] || "Not answered."}${rv ? " " + rv + "." : ""}${fresh ? " New answers." : ""}${others.length ? " " + names(others) + " here." : ""}${typing ? " Someone is typing." : ""}`);
      }

      // center bar
      const cmpQs = shownQs;
      if (!mod && ui.mode === "host") setMode("focus");
      segBtns.host.hidden = !mod;
      for (const [k, b] of Object.entries(segBtns)) b.setAttribute("aria-pressed", String(k === ui.mode));
      barInfo.textContent = ui.mode === "compare" ? `${cmpQs.length} question${cmpQs.length === 1 ? "" : "s"} side by side` : ui.mode === "tree" ? "Every round and what it decided" : ui.mode === "host" ? "Run the session" : "";
      barNav.hidden = ui.mode !== "focus";
      center.classList.toggle("vf-multi", roundNums.length > 1);
      pick.hidden = true;
      // toolbar
      const T = tb();
      const simple = simpleView();
      seg.hidden = simple;
      viewOpts.hidden = mod;
      viewOpts.textContent = simple ? "View options" : "Fewer options";
      viewOpts.setAttribute("aria-expanded", String(!simple));
      chipBtns.review.hidden = chipBtns.research.hidden = !mod;
      toolbar.hidden = ui.mode === "host" || simple;
      if (sortSel.s.value !== T.sort) sortSel.s.value = T.sort;
      for (const [k, b] of Object.entries(chipBtns)) b.setAttribute("aria-pressed", String(T.filter === k));
      const rk = roundNums.join(",");
      if (roundSel.s._k !== rk) {
        roundSel.s._k = rk;
        roundSel.s.replaceChildren(...[["all", "All rounds"], ...roundNums.map(n => [String(n), `Round ${n}`])].map(([v, t]) => { const o = E("option", null, t); o.value = v; return o; }));
      }
      if (T.round !== "all" && !roundNums.includes(+T.round)) T.round = "all";
      if (roundSel.s.value !== T.round) roundSel.s.value = T.round;
      roundSel.w.hidden = roundNums.length < 2;
      const allOpen = roundNums.every(n => n === cur || openRounds().has(n)) && !ui.treeClosed.size;
      expandBtn._open = allOpen;
      expandBtn.textContent = allOpen ? "Collapse all rounds" : "Expand all rounds";
      expandBtn.hidden = roundNums.length < 2 || ui.mode === "compare";

      // focus view
      const q = S.questions.find(x => x.id === ui.cur);
      const lk = q && Core.lockOf(q.id);
      center.classList.toggle("vf-noq", !q);
      railEmpty.hidden = qs.length > 0;
      if (!qs.length) renderEmpty(S);
      // Triage 3: until a guest answers anything, the Focus view opens with the goal, the host's ask and where to start.
      orient.hidden = !q || me.isOwner || !S.me || !!S.ended || !!S.youRemoved || !!ui.orientHidden || S.questions.some(x => ["answered", "took"].includes(myState(x.id)));
      introBtn.hidden = !S.intro && !me.isOwner; msIntro.hidden = helpIntro.hidden = introBtn.hidden;
      if (!orient.hidden) {
        const inCur = S.questions.filter(x => roundOf(x) === cur), target = inCur.find(x => isOpenForMe(x.id)) || inCur[0] || S.questions[0];
        const nQ = inCur.length || S.questions.length, hostName = disp(nameOf(S.ownerPid, "The host"));
        orH.textContent = me.name ? `Welcome, ${me.name}` : "Welcome";
        orGoal.textContent = S.goal ? `Goal: ${S.goal}` : ""; orGoal.hidden = !S.goal;
        const how = "On each one, pick an option, or type your answer in the box under the question. The chat is only for talking with people.";
        // On a phone the how-to sentence folds in with the intro, so the card stays short.
        orAsk.textContent = `${hostName} asks you to answer ${nQ} question${nQ === 1 ? "" : "s"}.${phone.matches ? "" : " " + how}`;
        orStart.textContent = `Start here: question ${Math.max(1, inCur.indexOf(target) + 1)}`; orStart._q = target?.id;
        orCatch._paint(catchUp());
        if (ui.introOpen == null) { ui.introOpen = !phone.matches && !store.get(INTRO_SEEN(), false); store.put(INTRO_SEEN(), true); }
        const hasWhy = !!S.intro || phone.matches;
        orIntro.textContent = S.intro; orIntro.hidden = !S.intro;
        orHow.textContent = how; orHow.hidden = !phone.matches;
        orWhyBtn.hidden = !hasWhy;
        orWhyBtn.textContent = S.intro ? "Why you're here" : "How it works";
        orWhyBtn.setAttribute("aria-expanded", String(introOpen()));
        orWhy.hidden = !hasWhy || !introOpen();
        orient.classList.toggle("vf-orient-open", !orWhy.hidden);
        orTour.hidden = !!pref("tour", "") || (phone.matches && !introOpen());
        if (phone.matches && !orTour.hidden) orWhy.append(orTour); else if (orTour.parentNode !== orRow) orRow.append(orTour);
      }
      if (q) {
        renderRefs(q);
        const inRound = S.questions.filter(x => roundOf(x) === roundOf(q));
        qPos.textContent = `${q.id}, round ${roundOf(q)}, question ${inRound.indexOf(q) + 1} of ${inRound.length}`;
        qFrom.textContent = q.from ? `Suggested by ${disp(q.from)}` : "";
        const noRec = q.addedBy && !Core.answersFor(q.id).some(a => a.claude);
        qHost.textContent = noRec ? `Added by ${q.byHost ? "the host" : disp(q.addedBy)}, no recommendation yet` : ""; qHost.hidden = !noRec;
        const pur = PURPOSE[q.purpose] || PURPOSE.decide;
        qPurpose.textContent = pur[0]; qPurpose.title = pur[1]; qPurpose.hidden = me.isOwner;
        purposeSel.w.hidden = !me.isOwner;
        if (purposeSel.s.value !== q.purpose && document.activeElement !== purposeSel.s) purposeSel.s.value = q.purpose || "decide";
        purposeSel.s.title = pur[1];
        const asked = Core.askedOf(q.id).filter(p => S.people[p] && !(S.removed || []).includes(p));
        const askedNames = asked.map(p => (isMe(p) ? "you" : disp(nameOf(p))));
        qFor.textContent = asked.length ? `Asked of ${askedNames.join(", ")}` : ""; qFor.hidden = !asked.length;
        forBtn.hidden = !me.isOwner || readOnly(q);
        forBtn.textContent = asked.length ? "Change who" : "Ask someone";
        forBtn.setAttribute("aria-expanded", String(ui.forOpen === q.id));
        forBox.hidden = forBtn.hidden || ui.forOpen !== q.id;
        if (!forBox.hidden) {
          const people = Object.keys(S.people).filter(p => !(S.removed || []).includes(p));
          sync(forList, people, p => p, p => {
            const l = E("label"), cb = E("input"); cb.type = "checkbox";
            cb.onchange = () => {
              const now = Core.askedOf(ui.cur).filter(x => x !== p);
              Core.setFor(ui.cur, cb.checked ? [...now, p] : now).catch(e => { fail(e); render(); });
            };
            l.append(cb, E("span")); l._cb = cb; return l;
          }, (l, p) => { l._cb.checked = asked.includes(p); l.lastChild.textContent = isMe(p) ? `${disp(nameOf(p))} (you)` : disp(nameOf(p)); });
        }
        // Pass, and the optional line once someone else answered (myState soft); only open counts as not answered.
        const mineNow = myState(q.id), myPass = Core.myPass(q.id), canPass = !readOnly(q) && !lk, other = otherAnswer(q.id);
        passNote.textContent = myPass ? `You passed${myPass.reason ? `: ${myPass.reason}` : "."}`
          : !canPass ? ""
          : mineNow === "soft" ? (q.purpose === "poll" ? `${disp(other.name)} answered. Pick if you have a view, or Pass.` : `${disp(other.name)} answered. 👍 if you agree, or Pass.`)
          : mineNow === "open" && askedOfMe(q.id) ? "This question is asked of you." : "";
        passBtn.hidden = !canPass || !!myPass || mineNow === "answered" || mineNow === "took";
        passUndo.hidden = !canPass || !myPass;
        passForm.hidden = passBtn.hidden || ui.passOpen !== q.id;
        passBtn.setAttribute("aria-expanded", String(!passForm.hidden));
        passLbl.textContent = askedOfMe(q.id) ? "Why you pass (needed: it is asked of you)" : "Why you pass (optional)";
        const passed = me.isOwner ? Object.entries(S.passes[q.id] || {}) : [];
        passWho.textContent = passed.length ? `Passed: ${passed.map(([p, r]) => disp(nameOf(p)) + (r.reason ? ` (${r.reason})` : "")).join(", ")}` : "";
        passWho.hidden = !passed.length;
        passBox.hidden = !passNote.textContent && passBtn.hidden && passUndo.hidden && passWho.hidden;
        qDeps.textContent = q.dependsOn?.length ? `Depends on ${q.dependsOn.join(", ")}` : ""; qDeps.hidden = !qDeps.textContent;
        const nSug = openSugs(q.id).length;
        qSug.textContent = mod && lk && nSug ? `${nSug} suggestion${nSug > 1 ? "s" : ""}` : ""; qSug.hidden = !qSug.textContent;
        if (qText.textContent !== q.text) qText.textContent = q.text;
        reviewTxt.textContent = reviewText(q);
        reviewRow.hidden = !q.needsReview;
        reviewClear.hidden = !mod;
        const others = Core.others(q.id), typers = others.filter(p => p.typing);
        avStack(onItAv, others, 5);
        onItTxt.textContent = typers.length ? `${names(typers)} ${typers.length > 1 ? "are" : "is"} typing` : others.length ? `${names(others)} ${others.length > 1 ? "are" : "is"} on this question` : "";
        onIt.hidden = !others.length;
        onItDots.classList.toggle("vf-on", typers.length > 0);
        avStack(qOnItAv, others, 3);
        qOnIt.setAttribute("aria-label", onItTxt.textContent);
        if (others.length) qOnIt.removeAttribute("aria-hidden"); else qOnIt.setAttribute("aria-hidden", "true");

        // format, Claude thread, citations
        renderFormat(S, q);
        if (!lb.hidden) paintLb();
        askBtn.hidden = (!!S.ended && !me.isOwner) || !!S.youRemoved;
        if (askBtn.hidden && ui.pop === askMenu) closePop();
        renderAsk();
        // A new result for me on this question opens the Claude section once; after that it stays as the person left it.
        if (renderThread(S, q) && !ui.clOpen.has(q.id)) ui.clOpen.set(q.id, true);
        paintCl();
        renderDisc(S, q);
        renderCite(S, q);
        ansPane.hidden = false; clSec.hidden = false; discSec.hidden = false;
        // my files on this question
        const myUps = (S.myUploads || []).filter(u => u.qid === q.id && !["withdrawn"].includes(u.status)).sort((a, b) => a.ts - b.ts);
        sync(upStrip, myUps, u => u.id, () => makeUpRow(false), fillUpRow);
        upStrip.hidden = !myUps.length;
        paintSlot(cSlot, readOnly(q) || !!Core.lockOf(q.id));
        paintSlot(askSlot, readOnly(q));
        paintSlot(sugSlot);

        // lock block
        lockBox.hidden = !lk;
        if (lk) {
          lockBy.textContent = `by ${disp(lk.by)}, ${ago(lk.ts)}${lk.edited ? ", edited" : ""}`;
          const lname = lk.name === "Claude" && String(lk.answerCid).startsWith("claude") ? "Claude" : disp(lk.name);
          // A closed poll chose no answer: it names no author and has no locked text to edit.
          fillClamp(lockText, "l:" + q.id, lk.poll ? "The poll is closed. The counts are final." : lk.text, lk.poll ? "Closed poll" : `Locked answer`, `${q.id}: ${q.text}`);
          const lkey = lk.poll ? "poll" : lk.answerCid + "|" + lname + "|" + lk.hostEdited;
          if (lockFrom._k !== lkey) {
            lockFrom._k = lkey;
            lockFrom.replaceChildren(...(lk.poll ? [] : [lname === "Claude" ? claudeAv(18) : av(lk.answerCid, lk.name, 18, true), E("span", null, `Answer from ${lname}${lk.hostEdited ? ", edited by the host" : ""}`)]));
          }
          lockFrom.hidden = !!lk.poll;
          unlockBtn.hidden = !mod;
          editBtn.hidden = !mod || !!lk.poll;
          if (!mod) editForm.hidden = true;
          const sugs = openSugs(q.id).sort((a, b) => b.votes.length - a.votes.length || a.ts - b.ts);
          sugTitle.textContent = sugs.length ? `Suggestions (${sugs.length})` : "Suggestions";
          sugBtn.hidden = mod || ui.suggestOpen || (!!S.ended && !me.isOwner) || !!S.youRemoved;
          sync(sList, sugMore.page(sugs, sList, "sugs:" + q.id), x => x.id, x => {
            const li = E("li", "vf-sug");
            const head = E("div", "vf-card-head");
            head.append(E("span", "vf-card-av"), E("span", "vf-card-name"), E("span", "vf-card-time"));
            const text = clampBox(), note = E("p", "vf-sug-note");
            const foot = E("div", "vf-card-foot");
            const vote = btn("vf-vote"); vote.append(icon("thumb"), E("span", "vf-vote-n"));
            const use = btn("vf-btn vf-btn-brass vf-btn-sm", "Use this");
            const edit = btn("vf-btn vf-btn-ghost vf-btn-sm", "Edit in");
            const dismiss = btn("vf-btn vf-btn-ghost vf-btn-sm", "Dismiss");
            foot.append(vote, E("span", "vf-spacer"), use, edit, dismiss);
            const att = attRowEl();
            li.append(head, text, note, att, foot);
            li._k = { head, text, note, att, vote, use, edit, dismiss };
            vote.onclick = () => Core.vote(ui.cur, x.id, !li._mine).catch(fail);
            use.onclick = () => Core.useSuggestion(ui.cur, x.id).then(() => flash("Locked answer replaced.")).catch(fail);
            dismiss.onclick = () => Core.dismissSuggestion(ui.cur, x.id).catch(fail);
            edit.onclick = () => {
              const curText = Core.lockOf(ui.cur)?.text || "";
              ui.editFrom = x.id; editTa.value = `${curText}\n\n${li._text}`; editForm.hidden = false;
              grow(editTa); editTa.focus(); editTa.setSelectionRange(editTa.value.length, editTa.value.length);
            };
            return li;
          }, (li, x) => {
            const k = li._k, [avBox, nm, tm] = k.head.children;
            const key = x.cid + "|" + disp(x.name);
            if (li._av !== key) { avBox.replaceChildren(av(x.cid, x.name, 20, true)); li._av = key; }
            nm.textContent = isMe(x.cid) ? `${disp(x.name)} (you)` : disp(x.name);
            tm.textContent = ago(x.ts);
            fillClamp(k.text, "s:" + x.id, x.text, `Suggestion from ${disp(x.name)}`, `${q.id}: ${q.text}`); li._text = x.text;
            k.note.textContent = x.note ? `“${x.note}”` : ""; k.note.hidden = !x.note;
            fillAtts(k.att, x.att, `Suggestion from ${disp(x.name)}`);
            li._mine = x.votes.includes(me.cid);
            k.vote.hidden = !s.voting;
            k.vote.lastChild.textContent = String(x.votes.length);
            k.vote.setAttribute("aria-pressed", String(li._mine));
            k.vote.disabled = isMe(x.cid);
            k.vote.title = isMe(x.cid) ? "Your suggestion" : "Vote for this suggestion";
            k.use.hidden = k.edit.hidden = !mod || !!lk.poll; // a closed poll's counts are never replaced
            k.dismiss.hidden = !mod;
          });
          sList.hidden = sugs.length === 0;
          sugHead.hidden = mod && sugs.length === 0;
        }

        // answers
        const lead = leadOf(q.id), all = ordered(q.id);
        // C26: Claude's cards wait behind a bar until I answered or voted; a chosen one (voted, leading, locked) shows.
        const hideOn = claudeHidden(q.id), pw = resultsWait(q);
        // ux-review-2 #5: under Answer first everyone else's cards wait too; a poll's wait for a pick has no bar.
        const waitingC = all.filter(a => (a.claude && (pw || (hideOn && !claudeChosen(a, q.id, lead)))) || (pw && !a.claude && !isMe(a.cid)));
        const ans = all.filter(a => !waitingC.includes(a));
        const nC = waitingC.filter(a => a.claude).length, nP = waitingC.length - nC;
        claudeBar.hidden = !waitingC.length || (pw && q.purpose === "poll");
        claudeBar.children[1].textContent = nP ? `Show answers (${waitingC.length})` : `Show Claude's take (${nC})`;
        claudeBar.children[2].textContent = "Answer or vote first to see them without asking";
        claudeBar.setAttribute("aria-label", nP ? `Show the answers so far: ${waitingC.length}. They show by themselves once you answer or vote.`
          : `Show Claude's take: ${nC} card${nC === 1 ? "" : "s"}. They show by themselves once you answer or vote.`);
        ansTitle.textContent = lk ? "All answers" : "Answers";
        // Answered counts everyone who joined (Claude's cards are not people); who is here is a separate number.
        const joinedN = Math.max(Object.keys(S.people || {}).filter(p => !(S.removed || []).includes(p)).length, here.length);
        const answeredN = all.filter(a => !a.claude).length;
        ansCount.textContent = `${answeredN} of ${joinedN} answered, ${hereN} here`;
        // Suggestions an unlock closed, shown while the question is open again.
        const closed = lk ? [] : Core.suggestionsFor(q.id).filter(x => x.status === "closed");
        closedBox.hidden = !closed.length;
        if (closedList._q !== q.id) { resetList(closedList); closedList._q = q.id; }
        sync(closedList, closed, x => x.id, () => {
          const li = E("li", "vf-sug vf-sug-closed");
          li.append(E("div", "vf-card-head"), E("p", "vf-closed-txt"));
          li.firstChild.append(E("span", "vf-card-name"), E("span", "vf-tag", "Closed by unlock"), E("span", "vf-card-time"));
          return li;
        }, (li, x) => {
          const [nm, , tm] = li.firstChild.children;
          nm.textContent = disp(x.name); tm.textContent = ago(x.ts);
          li.lastChild.textContent = x.text;
        });
        if (aList._q !== q.id) { resetList(aList); aList._q = q.id; }
        sync(aList, ansMore.page(ans, aList, "ans:" + q.id), a => a.ref || a.cid, () => buildCard(false), (li, a) => fillCard(li, a, q.id, a.cid === lead, false));
        aList.classList.toggle("vf-alist-locked", !!lk);
        aEmpty.hidden = ans.length > 0 || (waitingC.length > 0 && !claudeBar.hidden);
        aEmpty.textContent = waitingC.length ? "Pick one to see what others said." : isChoice(q) ? "No comments yet." : "No answers yet. Yours can be the first.";
        const lockable = Core.answersFor(q.id).filter(a => !waitingC.includes(a));
        // Gather answers stand (no lock); only the owner closes a poll (Q97).
        // A poll closes as a tally: always open to the owner, ties and no votes included, with no winner chosen.
        const poll = q.purpose === "poll";
        lockBtn.hidden = !mod || !!lk || (!lockable.length && !poll) || q.purpose === "gather" || (poll && !me.isOwner);
        lockBtn.textContent = poll ? "Close poll" : isChoice(q) ? "Lock top pick" : "Lock top answer";
        const topA = byVotes(lockable)[0];
        const anyVotes = lockable.some(a => votesOf(a) > 0);
        const agreeN = topA ? agreeing(topA) : 0;
        const blocked = s.signoff && topA && agreeN < here.length;
        lockBtn.setAttribute("aria-disabled", String(!poll && (!anyVotes || !!blocked)));
        lockBtn.title = poll ? "Freeze the counts; no answer is chosen" : !anyVotes ? "No answer has a vote yet. Vote first, or use Lock this one on a card to pick one yourself."
          : blocked ? "Everyone here has to vote for it first" : "Freeze the most voted answer";
        agreeTxt.textContent = s.signoff && !lk && topA && !poll ? `${agreeN} of ${here.length} agree` : "";
        agreeTxt.classList.toggle("vf-agree-all", !!topA && agreeN === here.length);
      } else {
        qPos.textContent = qFrom.textContent = ""; qSug.hidden = qDeps.hidden = qHost.hidden = closedBox.hidden = qPurpose.hidden = purposeSel.w.hidden = true; qText.textContent = "No questions yet";
        qFor.hidden = forBtn.hidden = forBox.hidden = passBox.hidden = true;
        onItTxt.textContent = ""; ansCount.textContent = ""; aEmpty.hidden = true; lockBox.hidden = true; lockBtn.hidden = true;
        reviewRow.hidden = true; tools.hidden = true; fmtBox.hidden = true; ansPane.hidden = clSec.hidden = discSec.hidden = true; claudeBar.hidden = true; refBox.hidden = true;
      }
      tools.hidden = !q;
      if (!ui.dirty && document.activeElement !== ta && q && ta.value !== Core.myAnswer(q.id)) { ta.value = Core.myAnswer(q.id); grow(ta); }
      renderComposer();

      // compare view
      if (ui.mode === "compare") sync(board, cmpQs, x => x.id, x => {
        const col = E("section", "vf-col");
        const head = E("header", "vf-col-head");
        const title2 = btn("vf-col-q");
        const meta = E("div", "vf-col-meta");
        const badge = E("span", "vf-lock-badge vf-lock-badge-sm"); badge.append(icon("lock"), E("span", null, "Locked"));
        meta.append(E("span", "vf-meta"), badge, E("span", "vf-review vf-review-sm"), E("span", "vf-avrow"), dots());
        meta.children[2].append(icon("alert"), E("span"));
        head.append(title2, meta);
        const pin = E("div", "vf-col-pin");
        const pinText = clampBox("vf-lock-text vf-lock-text-sm"), pinFrom = E("div", "vf-lock-from");
        pin.append(pinText, pinFrom);
        const cards = E("ul", "vf-col-cards"); cards.setAttribute("role", "list");
        const empty = E("p", "vf-empty vf-empty-sm", "No answers yet.");
        const opts = E("div", "vf-col-fmt");
        const cbar = btn("vf-claudebar vf-claudebar-sm"); cbar.append(claudeAv(16), E("span", "vf-claudebar-t"));
        cbar.onclick = () => { ui.revealed.add(x.id); render(); };
        const foot = E("div", "vf-col-foot");
        const open = btn("vf-btn vf-btn-ghost vf-btn-sm", "Open in Focus");
        foot.append(open);
        const more = showMore("ans", 12, { all: true });
        const sc = E("div", "vf-col-scroll"); sc.append(pin, opts, cbar, cards, more.foot, empty);
        col.append(head, sc, foot);
        col._k = { title2, meta, pin, pinText, pinFrom, cards, empty, open, opts, cbar, more };
        const go = () => focusQuestion(x.id);
        title2.onclick = go; open.onclick = go;
        return col;
      }, (col, x) => {
        const k = col._k, [cnt, badge, rv, avs, dts] = k.meta.children;
        const all = ordered(x.id), xl = Core.lockOf(x.id), lead = leadOf(x.id);
        const hideOn = claudeHidden(x.id), pw = resultsWait(x);
        const waitingC = all.filter(a => (a.claude && (pw || (hideOn && !claudeChosen(a, x.id, lead)))) || (pw && !a.claude && !isMe(a.cid)));
        const ans = all.filter(a => !waitingC.includes(a));
        k.cbar.hidden = !waitingC.length || (pw && x.purpose === "poll");
        k.cbar.lastChild.textContent = waitingC.some(a => !a.claude) ? `Show answers (${waitingC.length})` : `Show Claude's take (${waitingC.length})`;
        fillColFormat(k.opts, x);
        const others = Core.others(x.id);
        k.title2.textContent = x.text;
        col.classList.toggle("vf-col-cur", x.id === ui.cur);
        col.classList.toggle("vf-col-locked", !!xl);
        const nPeople = all.filter(a => !a.claude).length;
        cnt.textContent = isChoice(x) ? `${nPeople} answered` : `${nPeople} answer${nPeople === 1 ? "" : "s"}`;
        badge.hidden = !xl;
        rv.lastChild.textContent = reviewText(x); rv.hidden = !x.needsReview;
        avStack(avs, others, 3, 18);
        dts.classList.toggle("vf-on", others.some(p => p.typing));
        k.pin.hidden = !xl;
        if (xl) { fillClamp(k.pinText, "cl:" + x.id, xl.text, "Locked answer", `${x.id}: ${x.text}`); k.pinFrom.textContent = `Locked, from ${xl.name === "Claude" ? "Claude" : disp(xl.name)}`; }
        sync(k.cards, k.more.page(ans.filter(a => !xl || a.cid !== xl.answerCid), k.cards, "ans:" + x.id), a => a.ref || a.cid, () => buildCard(true), (li, a) => fillCard(li, a, x.id, a.cid === lead, true));
        k.empty.hidden = ans.length > 0 || waitingC.length > 0 || isChoice(x);
        k.open.textContent = xl ? "Open in Focus" : hasAnswered(x.id) ? "Edit my answer" : "Answer in Focus";
      });
      if (ui.mode === "compare") requestAnimationFrame(edges);
      if (ui.mode === "tree") renderTree(S, mod, cur);
      if (ui.mode === "host" && mod) renderHost(S);
      if (ui.pop === askPanel) renderAskPanel(S);
      if (ui.pop === citePop && !citeList.children.length) closePop();

      // chat
      chat.classList.toggle("vf-off", !s.chat);
      fab.hidden = !s.chat;
      if (!s.chat && ui.chatOpen) { ui.chatOpen = false; chat.hidden = true; }
      const msgs = S.chat, newest = mark(msgs.at(-1));
      if (ui.seenChat === null && Core.live) ui.seenChat = newest;
      if (ui.chatOpen) ui.seenChat = newest;
      // ux-review-2 #8: a message that mentions me is badged on the bell, not again here.
      const belled = new Set(notes().filter(n => n.msg && !n.read).map(n => n.msg));
      const unread = after(msgs, ui.seenChat).filter(m => !isMe(m.cid) && !belled.has(m.id)).length;
      // Triage 2: a message for a host whose chat is closed (or whose tab is in the background) shows in the tab title too.
      document.title = unread && !ui.chatOpen ? `(${unread}) ${title}` : title;
      fabBadge.textContent = unread ? String(unread > 9 ? "9+" : unread) : "";
      if (!ui.chatOpen && unread > ui.lastUnread) bumpFab();
      ui.lastUnread = unread;
      fab.setAttribute("aria-label", ui.chatOpen ? "Close chat" : unread ? `Open chat, ${unread} unread` : "Open chat");
      chatMeta.textContent = `${here.length} here`;
      mForm.hidden = (!!S.ended && !me.isOwner) || !!S.youRemoved;
      mHint.hidden = mForm.hidden;
      paintSlot(chatSlot, mForm.hidden);
      if (ui.chatOpen) {
        const atBottom = mStick || mGap() < 40;
        // A Load earlier row sits above each message whose next older one is not loaded; the top one keeps its node,
        // so its button keeps focus while there is more to load.
        const rows = msgs.flatMap((m, i) => (m.gapAbove ? [{ id: i ? "gap:" + m.id : "gap-top", gap: m.id }, m] : [m]));
        const added = rows.filter(r => !mList._map?.has(r.id)).length;
        if (added > 1) { mList.setAttribute("aria-busy", "true"); requestAnimationFrame(() => mList.removeAttribute("aria-busy")); } // a batch is not read out
        sync(mList, rows, m => m.id, m => {
          if (m.gap) {
            const li = E("li", "vf-mgap"), b = btn("vf-btn vf-btn-ghost vf-btn-sm", "Load earlier messages");
            b.onclick = () => loadEarlier(li._below, b);
            li.append(b); li._b = b;
            return li;
          }
          const li = E("li", "vf-msg");
          const col = E("div", "vf-msg-col");
          const meta = E("div", "vf-msg-meta");
          meta.append(E("span", "vf-msg-name"), E("span", "vf-card-time"));
          const bubble = E("div", "vf-bubble"); const btext = clampBox();
          // a reply quotes the message it answers; tapping the quote goes to it
          const quote = btn("vf-mquote"); const qName = E("span", "vf-mquote-n"), qTxt = E("span", "vf-mquote-t"); quote.append(qName, qTxt);
          quote.onclick = () => { if (li._m?.replyTo) goMsg(li._m.replyTo.id); };
          const batt = attRowEl();
          bubble.append(btext, batt);
          const tools2 = E("div", "vf-msg-tools");
          // Actions live behind ⋯ (hover, focus or long-press): Propose as question, Ask Claude about this, Copy.
          const more = ibtn("vf-msgmore", "more", "Message actions");
          more.setAttribute("aria-haspopup", "menu"); more.setAttribute("aria-expanded", "false");
          more.onclick = () => openMsgMenu(li._m, more);
          let pressT = 0;
          bubble.addEventListener("pointerdown", e => { if (e.pointerType === "mouse") return; clearTimeout(pressT); pressT = setTimeout(() => { pressT = -1; openMsgMenu(li._m, more); }, 500); });
          for (const ev of ["pointerup", "pointercancel", "pointerleave"]) bubble.addEventListener(ev, () => { if (pressT !== -1) clearTimeout(pressT); });
          bubble.addEventListener("contextmenu", e => { if (pressT === -1) { e.preventDefault(); pressT = 0; } });
          const done = E("span", "vf-fwd-done"); done.append(icon("check"), E("span", null, "Proposed"));
          tools2.append(done);
          // A message whose "@Claude" filed a request says so, with where it stands for the owner and its asker; Claude's
          // own message opens its full answer.
          const sent = btn("vf-lbtn vf-msent"), sentT = E("span");
          sent.append(claudeAv(14), sentT);
          sent.onclick = () => { const x = li._gq?.x; if (li._m?.claude || !x?.msg || x.published === false) openGeneral(x ? "x:" + x.id : "r:" + li._m?.request); else goMsg(x.msg, () => openGeneral("x:" + x.id)); };
          // Emoji reactions: chips under the bubble only when there are some. Add sits beside ⋯ (hover or focus on a
          // fine pointer); on touch it is React in the long-press menu.
          const reactAdd = btn("vf-mreact-add"); reactAdd.append(E("span", "vf-mreact-plus", "+"), E("span", "vf-mreact-face", "🙂"));
          reactAdd.setAttribute("aria-haspopup", "dialog"); reactAdd.setAttribute("aria-label", "Add a reaction"); reactAdd.title = "Add a reaction";
          reactAdd.onclick = () => (ui.pop === reactPop && ui.reactMsg?.id === li._m?.id ? closePop() : openReactPop(li._m, reactAdd));
          const bubRow = E("div", "vf-bubrow"); bubRow.append(bubble, reactAdd, more);
          const reactRow = E("div", "vf-mreacts"); reactRow.setAttribute("role", "group"); reactRow.setAttribute("aria-label", "Reactions");
          col.append(meta, quote, bubRow, sent, reactRow, tools2);
          li.append(E("span", "vf-msg-av"), col);
          li._k = { meta, btext, batt, tools2, done, more, quote, qName, qTxt, reactRow, reactAdd, sent, sentT };
          return li;
        }, (li, m) => {
          if (m.gap) { li._below = m.gap; return; }
          const i = msgs.indexOf(m), prev = msgs[i - 1], k = li._k;
          const cont = prev && !m.gapAbove && prev.cid === m.cid && m.ts - prev.ts < 120 && !m.replyTo; // a reply always shows who and what it answers
          li.classList.toggle("vf-msg-mine", isMe(m.cid));
          li.classList.toggle("vf-msg-cont", !!cont);
          const avBox = li.firstChild, key = m.cid + "|" + disp(m.name);
          if (li._av !== key) { avBox.replaceChildren(m.claude ? claudeAv(26) : av(m.cid, m.name, 26, true)); li._av = key; }
          li.classList.toggle("vf-msg-claude", !!m.claude);
          k.meta.firstChild.textContent = m.claude ? "Claude" : isMe(m.cid) ? "You" : disp(m.name);
          li._gq = m.request ? genReq(S, m.request) : m.claude ? { x: (S.research?.[Core.GENERAL] || []).find(x => x.id === m.result) } : null;
          k.sent.hidden = !li._gq || (m.claude && !li._gq.x);
          if (li._gq) k.sentT.textContent = m.claude ? "Full answer" : li._gq.label ? `Sent to Claude · ${li._gq.label}` : "Sent to Claude";
          k.meta.lastChild.textContent = ago(m.ts);
          fillClamp(k.btext, "m:" + m.id, m.text, `Message from ${disp(m.name)}`, "");
          k.btext.hidden = !m.text;
          fillAtts(k.batt, m.att, `Message from ${isMe(m.cid) ? "you" : disp(m.name)}`);
          li._m = m;
          const rt = m.replyTo;
          k.quote.hidden = !rt;
          if (rt) {
            k.qName.textContent = isMe(rt.cid) ? "You" : disp(rt.name); k.qTxt.textContent = rt.text;
            k.quote.setAttribute("aria-label", `In reply to ${isMe(rt.cid) ? "you" : disp(rt.name)}: ${rt.text}. Go to that message`);
          }
          k.done.hidden = !m.forwarded;
          k.tools2.hidden = k.done.hidden;
          fillReactChips(k, m);
          k.more.setAttribute("aria-label", `Actions for the message from ${isMe(m.cid) ? "you" : disp(m.name)}`);
        });
        mEmpty.hidden = msgs.length > 0;
        if (atBottom) { mScroll.scrollTop = mScroll.scrollHeight; ui.mNewFrom = null; }
        else ui.mNewFrom ??= ui.mSeenN ?? newest;
        const nNew = after(msgs, ui.mNewFrom).filter(m => !isMe(m.cid)).length;
        mNew.hidden = !nNew;
        mNew.textContent = `${nNew} new message${nNew === 1 ? "" : "s"} ↓`;
        ui.mSeenN = newest;
        if (mScroll.scrollTop < EARLIER_PX) requestAnimationFrame(loadTop);
        const typers = here.filter(p => p.chatTyping && !isMe(p.cid));
        mTyping.classList.toggle("vf-on", typers.length > 0);
        mTypingTxt.textContent = typers.length ? `${names(typers)} ${typers.length > 1 ? "are" : "is"} typing` : "";
      }

      // tab badges
      // ux-review-2 #8: an unlabeled count on Questions read as another notification; the rail says how many are answered.
      tabBtns.questions._badge.textContent = "";
      const left = S.questions.length - answered;
      tabBtns.questions.setAttribute("aria-label", left ? `Questions, ${left} not answered yet` : "Questions");
      tabBtns.answer._badge.textContent = "";
      tabBtns.compare._badge.textContent = "";
      const reviews = S.questions.filter(x => x.needsReview).length;
      tabBtns.tree._badge.textContent = reviews ? String(reviews) : "";
      if (!mod && ui.tab === "host") setTab("answer");
      tabs.style.setProperty("--tabs-n", "5");
      renderBell(S, mod);
      renderMore(S, mod);
      renderMyReps(S);

      // a color someone just chose: repaint their avatars wherever they are
      for (const a of root.querySelectorAll(".core-avatar[data-who]")) { const c = Core.colorFor(a.dataset.who); if (a.style.getPropertyValue("--av") !== c) a.style.setProperty("--av", c); }
      requestAnimationFrame(() => { measureAll(); if (toast.classList.contains("vf-on")) placeToast(); });
    }

    applyTheme();
    setTab("answer");
    setMode("focus");
    const sendPrefsNow = () => { clearTimeout(PK.timer); flushPrefs(); };
    on(window, "pagehide", sendPrefsNow);
    // A new version reloads the page (core.js); unsent text rides across it in this tab's sessionStorage.
    Core.onReload(() => {
      if (ui.cur) ui.drafts[ui.cur] = ta.value;
      const drafts = Object.fromEntries(Object.entries(ui.drafts).filter(([q, t]) => t && t !== Core.myAnswer(q)));
      try { sessionStorage.setItem(UNSENT, JSON.stringify({ drafts, chat: mInput.value, cur: ui.cur })); } catch { /* storage off */ }
      markSeen(ui.cur); sendPrefsNow();
    });
    Core.subscribe(() => render());
})();
