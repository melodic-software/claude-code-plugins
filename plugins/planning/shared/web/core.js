// Identity, polling, heartbeat and actions: the only code that talks to the server. The page (app.js)
// reads the prototype's state names; toView() builds them from the contract snapshot, and each action
// below sends the contract route's body. The map: .work/shared-interview-ui/snapshot-map.md.
(() => {
  const SCHEMA_VERSION = 1; // the session file version this page was built for; another one reloads it
  const memory = new Map();
  const store = (() => { try { const s = window.localStorage; s.setItem("_t", "1"); s.removeItem("_t"); return s; } catch { return null; } })()
    || { getItem: k => memory.get(k) ?? null, setItem: (k, v) => memory.set(k, v), removeItem: k => memory.delete(k) };
  const get = k => { try { return store.getItem(k); } catch { return memory.get(k) ?? null; } };
  const put = (k, v) => { try { store.setItem(k, v); } catch { memory.set(k, v); } };
  const drop = k => { try { store.removeItem(k); } catch { /* storage gone */ } memory.delete(k); };

  // The guest secret lives under the prototype's key ("secret"), so a guest the import carried over
  // keeps their identity after the cutover reload. It leaves this browser only as a header.
  let secret = get("secret") || "";
  const hashParams = new URLSearchParams(location.hash.slice(1));
  const ownerToken = hashParams.get("owner") || "";
  const joinKey = hashParams.get("join") || "";
  // A personal link ("Use on another device") carries the person's secret in the fragment; adopt it,
  // then take it out of the address bar.
  const adopt = hashParams.get("me") || "";
  if (adopt && !ownerToken) {
    secret = adopt; put("secret", adopt); drop("pid"); drop("name");
    hashParams.delete("me");
    history.replaceState(null, "", location.pathname + location.search + (hashParams.toString() ? "#" + hashParams : ""));
  }
  if (ownerToken) secret = ""; // the owner link is the owner's only credential

  const listeners = new Set(), reloadHooks = new Set();
  let focusQ = "", typingUntil = 0, chatTypingUntil = 0, lastOk = 0, joining = null;
  let snap = null, rev = 0, etag = "", build = "", polling = false;
  const DEFAULTS = {
    questions: [], answers: {}, ideas: [], presence: [], locks: {}, suggestions: {}, chat: [], leaders: [], trusted: [],
    round: { current: 1, status: "open" }, rounds: [], title: "", people: {}, research: {}, requestCounts: { open: 0, byQ: {} }, requests: [],
    myRequests: [], ended: false, youRemoved: false, removed: [], guestKey: "", shareChanged: false, shareUrl: "",
    goal: "", uploads: [], myUploads: [], files: {}, mergeRequests: [], myMergeRequests: [], me: null, joinNeedsKey: false,
    settings: { voting: true, signoff: false, chat: true, follow: true, showNames: true, digestNames: false, uploads: false, hideClaude: true },
  };

  const PALETTE = ["#f472b6", "#60a5fa", "#34d399", "#fbbf24", "#a78bfa", "#f87171", "#22d3ee", "#fb923c", "#4ade80", "#e879f9"];
  const hash = s => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);

  // ---------- the contract snapshot as the prototype's state ----------
  // Confirm options are "yes"/"no" in the contract and "opt-yes"/"opt-no" on the page.
  const optIn = o => (o === "yes" || o === "no" ? "opt-" + o : o);
  const optOut = o => (o === "opt-yes" || o === "opt-no" ? o.slice(4) : o);
  const CLAUDE_CID = { rec: "claude", a: "claude-a", b: "claude-b", c: "claude-c" };
  const CLAUDE_KEY = Object.fromEntries(Object.entries(CLAUDE_CID).map(([k, v]) => [v, k]));
  /** The page's id for a card: a person's pid, Claude's "claude" or "claude-<key>", an option's id. */
  function cidOf(ref) {
    const [kind, id] = ref.split(":");
    return kind === "p" ? id : kind === "c" ? CLAUDE_CID[id] : optIn(id);
  }
  /** The contract's card ref for the page's id on question qid; a ref passes through. */
  function refOf(qid, target) {
    if (/^[pco]:/.test(target)) return target;
    if (CLAUDE_KEY[target]) return "c:" + CLAUDE_KEY[target];
    const opts = (qOf(Core.state.questions, qid)?.options || []).map(o => o.id);
    return opts.includes(target) ? "o:" + optOut(target) : "p:" + target;
  }
  const qOf = (qs, id) => qs.find(q => q.id === id);

  function toView(s) {
    const people = {}, nameOf = pid => (pid === "host" && !people.host ? "Host" : people[pid]?.name || "Someone");
    const roles = {};
    for (const p of [...(s.people || []), ...(s.removed || [])]) { people[p.pid] = { name: p.name, ts: p.joinedAt }; roles[p.pid] = p; }
    const live = (s.people || []);
    const rounds = s.rounds || [], last = rounds[rounds.length - 1];
    const settings = s.settings || {};
    const view = {
      ...DEFAULTS,
      schemaVersion: s.schemaVersion, rev: s.rev, title: s.title || "", goal: s.goal || "", ended: !!s.ended, serverTime: s.serverTime,
      settings: { ...settings, showNames: settings.names === "full", hideClaude: settings.claudeTake !== "always" },
      people, ownerPid: "host",
      leaders: live.filter(p => p.role === "leader").map(p => p.pid), trusted: live.filter(p => p.trusted && p.pid !== "host").map(p => p.pid),
      removed: (s.removed || []).map(p => p.pid),
      rounds: rounds.map(r => ({ n: r.n, status: r.status.kind })),
      round: last ? { current: last.n, status: last.status.kind, sentAt: last.status.sentAt,
        ...(last.status.ready ? { ready: { by: nameOf(last.status.ready.by), ts: last.status.ready.at } } : {}) } : { current: 1, status: "open" },
      requestCounts: s.requestCounts || DEFAULTS.requestCounts,
      shareUrl: s.share?.url || "", shareChanged: !!s.share?.changedAt, guestKey: s.guestKey || "",
    };
    const proposals = s.proposals || [];
    const reqText = new Map([...(s.requests || []), ...(s.myRequests || [])].map(r => [r.id, r]));
    view.questions = (s.questions || []).map(q => {
      const f = q.format || { kind: "text" }, flag = (q.needsReview || []).at(-1);
      const { format: _, ...rest } = q, out = { ...rest, purpose: q.purpose || "decide" };
      if (f.kind === "choice") { out.format = "choice"; out.options = f.options; }
      // TODO(Phase 7, Q98): prototype questions open their own page; until then their variants pick like options.
      else if (f.kind === "prototype") { out.format = "choice"; out.options = f.variants.map(v => ({ id: v.id, label: v.label })); out.variants = f.variants; }
      else if (f.kind === "confirm") { out.format = "confirm"; out.image = f.image; out.rect = f.rect; out.options = [{ id: "opt-yes", label: "Yes" }, { id: "opt-no", label: "No" }]; }
      // TODO(Phase 4b): multi, scale and rank formats get their own cards here.
      out.formatKind = f.kind;
      out.needsReview = flag ? { because: flag.because, ts: flag.at, ...(flag.why?.suggestion ? { suggestion: flag.why.suggestion } : {}) } : null;
      if (!flag) delete out.needsReview;
      if (q.origin?.kind === "proposal") { const p = proposals.find(x => x.id === q.origin.proposal); out.proposal = q.origin.proposal; if (p) out.from = nameOf(p.pid); }
      if (q.origin?.kind === "host") { out.proposal = q.origin.proposal; out.addedBy = nameOf(q.origin.by); out.byHost = q.origin.by === "host"; }
      return out;
    });
    const details = s.cardDetails || {};
    for (const [qid, cards] of Object.entries(s.cards || {})) {
      const q = qOf(view.questions, qid) || {};
      view.answers[qid] = cards.map(c => {
        const base = { cid: cidOf(c.ref), ref: c.ref, votes: c.votes || [], reactions: c.reactions || {} };
        if (c.kind === "claude") {
          const alt = (q.alternatives || []).find(a => a.key === c.key);
          return { ...base, claude: true, rec: c.key === "rec", name: "Claude", text: c.key === "rec" ? q.recommendation || "" : alt?.text || "", ts: c.at || 0,
            ...(c.key === "rec" && q.basis ? { basis: q.basis } : {}), ...(alt?.tradeoff ? { tradeoff: alt.tradeoff } : {}) };
        }
        if (c.kind === "option") {
          const o = (q.options || []).find(x => x.id === optIn(c.option));
          return { ...base, option: true, claude: false, name: "Option", text: o?.label || "", ts: 0 };
        }
        const d = details[qid]?.[c.ref], info = d?.deviceInfo;
        return { ...base, name: nameOf(c.pid), text: c.text || "", ts: c.at, cites: c.cites || [], device: c.device,
          ...(c.pick ? { pick: optIn(c.pick) } : {}), ...(c.editedAfterVotes ? { editedAfter: c.editedAfterVotes } : {}), ...(c.late ? { late: c.late } : {}),
          ...(d ? { ctx: { view: d.view, ...(info ? { device: info.kind, browser: info.browser, vw: info.screen?.w, vh: info.screen?.h } : {}) } } : {}) };
      });
    }
    const authorCid = (qid, ref) => (ref ? cidOf(ref) : "");
    for (const [qid, lk] of Object.entries(s.locks || {})) {
      const src = lk.source || {}, sug = src.kind === "suggestion" ? (s.suggestions?.[qid] || []).find(x => x.id === src.suggestion) : null;
      const ref = src.kind === "card" ? src.card : src.kind === "edited" && /^[pco]:/.test(src.from || "") ? src.from : sug ? "p:" + sug.pid : "";
      const kind = ref.split(":")[0];
      view.locks[qid] = { text: src.text, answerCid: authorCid(qid, ref), by: nameOf(lk.by), ts: lk.at, edited: src.kind === "edited",
        name: kind === "c" ? "Claude" : kind === "o" ? "Option" : kind === "p" ? nameOf(ref.split(":")[1]) : "" };
    }
    for (const [qid, lst] of Object.entries(s.suggestions || {})) {
      view.suggestions[qid] = lst.map(x => ({ id: x.id, cid: x.pid, name: nameOf(x.pid), text: x.text, note: x.note || "", ts: x.at, status: x.status.kind, votes: x.votes || [] }));
    }
    view.ideas = proposals.map(p => ({ id: p.id, cid: p.pid, name: nameOf(p.pid), text: p.text, ts: p.at,
      status: p.status.kind === "not-placed" ? "notplaced" : p.status.kind, qid: p.status.question || "", reason: p.status.reason || "",
      ...(p.via?.kind === "chat" ? { via: nameOf(p.via.by) } : {}) }));
    view.chat = (s.chat || []).map(m => ({ id: m.id, cid: m.pid, name: nameOf(m.pid), text: m.text, ts: m.at,
      ...(m.replyTo ? { replyTo: { id: m.replyTo.id, cid: m.replyTo.pid, name: nameOf(m.replyTo.pid), text: m.replyTo.excerpt } } : {}),
      ...(m.proposed ? { forwarded: m.proposed } : {}) }));
    for (const [qid, lst] of Object.entries(s.results || {})) {
      view.research[qid] = lst.map(x => {
        const r = x.request ? reqText.get(x.request) : null, by = x.by?.kind === "guest-claude" ? x.by.pid : r?.pid;
        return { id: x.id, kind: x.kind, summary: x.summary, sources: x.sources || [], report: x.report || "", ts: x.at, requestId: x.request || "",
          skill: (x.used || []).map(u => u.name).join(", ") || "Claude", why: x.why || "", published: x.published !== false,
          ...(r ? { ask: r.text } : {}), ...(by ? { byCid: by, by: nameOf(by) } : {}) };
      });
    }
    const req = r => ({ id: r.id, qid: r.qid, kind: r.kind, text: r.text, edited: r.edited, cid: r.pid, name: nameOf(r.pid), ts: r.at,
      status: r.status.kind, runner: r.runner, ...(r.status.reason ? { reason: r.status.reason } : {}) });
    view.requests = (s.requests || []).map(req);
    view.myRequests = (s.myRequests || []).map(req);
    view.mergeRequests = (s.mergeRequests || []).map(m => ({ id: m.id, from: m.from, to: m.to, fromName: nameOf(m.from), toName: nameOf(m.to), ts: m.at, status: m.status.kind }));
    view.myMergeRequests = (s.myMergeRequests || []).map(m => ({ id: m.id, status: m.status.kind, toName: nameOf(m.to) }));
    view.presence = (s.presence || []).map(p => ({ cid: p.pid, name: nameOf(p.pid), q: p.q, typing: p.typing, chatTyping: p.chatTyping,
      owner: p.pid === "host", leader: roles[p.pid]?.role === "leader", trusted: !!roles[p.pid]?.trusted }));
    // TODO(Phase 4b): presence states (active, idle, offline) from the heartbeat's visible and lastInput.
    if (s.me) {
      view.me = { ...s.me, notifications: (s.me.notifications || []).map(n => ({ ...n, ts: n.at, ...(n.by ? { byCid: n.by, by: nameOf(n.by) } : {}) })) };
      view.myReactions = s.me.reactions || {};
    }
    return view;
  }

  // ---------- error codes: the page shows these sentences, never a bare code ----------
  const MESSAGES = {
    "bad-json": "The page sent something the session could not read. Reload and try again.",
    empty: "Write something first.",
    "too-long": "That is too long.",
    "no-such-option": "That option is gone. Reload the page.",
    "cannot-vote-own": "You cannot vote for your own answer.",
    "unknown-session": "The session no longer knows this browser. Join again.",
    removed: "The host removed you from this session.",
    ended: "This session has ended.",
    "bad-guest-key": "This invite link is no longer valid. Ask the host for the new one.",
    "owner-only": "Only the host can do that.",
    "moderator-only": "Only the host or a leader can do that.",
    "uploads-off": "Uploads are off in this session.",
    "chat-off": "Chat is off in this session.",
    "voting-off": "Voting is off in this session.",
    locked: "This question was locked. Suggest a change instead.",
    "round-sent": "This round went to Claude, so it is read-only now.",
    "round-not-open": "This round has not opened yet.",
    "not-locked": "This question is not locked.",
    "no-votes": "No answer has a vote yet.",
    tie: "Answers are tied.",
    "round-full": "The next round is full.",
    "wrong-status": "That already changed. The page shows where it stands now.",
    "wrong-purpose": "That does not apply to this kind of question.",
    "body-too-large": "That is too large to send.",
    "slow-down": "You sent that a moment ago. Try again in a second.",
    "join-rate": "Too many people joined from your network just now. Wait a minute, then try again.",
    "too-many-pending": "You have 10 requests waiting already.",
    "state-invalid": "The session could not save that. Nothing was changed.",
    full: "This session is full right now. Try again later, or ask the host.",
    busy: "The session is busy. Try again in a moment.",
  };
  const errorText = e => MESSAGES[e?.error] || e?.message || (e?.status ? "The session refused that." : "The session is out of reach. Check your connection.");

  const Core = {
    // cid holds the public pid (the prototype's name for it).
    me: { cid: secret ? get("pid") || "" : ownerToken ? "host" : "", name: get("name") || "", isOwner: !!ownerToken, isLeader: false, isTrusted: false },
    state: structuredClone(DEFAULTS),
    live: false,
    errorText,

    /** fn(state, Core) runs after every poll and every local change. Returns an unsubscribe function. */
    subscribe(fn) { listeners.add(fn); fn(Core.state, Core); return () => listeners.delete(fn); },
    /** fn() runs just before the page reloads itself for a new version: save unsent text. */
    onReload(fn) { reloadHooks.add(fn); return () => reloadHooks.delete(fn); },

    colorFor: id => PALETTE[hash(id || "") % PALETTE.length],
    initials: name => (name || "?").trim().split(/\s+/).map(w => w[0]).join("").slice(0, 2).toUpperCase(),
    el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; },
    /** Round avatar element for a person (cid + name). */
    avatar(personCid, name, size = 28) {
      const a = Core.el("span", "core-avatar", Core.initials(name));
      a.style.setProperty("--av", Core.colorFor(personCid));
      a.style.width = a.style.height = size + "px";
      a.style.fontSize = Math.round(size * 0.4) + "px";
      a.title = name;
      return a;
    },

    answersFor: qid => Core.state.answers[qid] || [],
    myAnswer: qid => Core.answersFor(qid).find(a => a.cid === Core.me.cid && !a.claude && !a.option)?.text || "",
    /** People here right now other than me, optionally on one question. */
    others: qid => Core.state.presence.filter(p => p.cid !== Core.me.cid && (qid == null || p.q === qid)),
    owner: () => Core.state.presence.find(p => p.owner),

    /** Tell everyone which question I am on. Call when a question gains focus or is shown. */
    setFocus(qid) { focusQ = qid || ""; beat(); },
    /** Call on every keystroke in an answer or idea field. */
    setTyping() { const was = Date.now() < typingUntil; typingUntil = Date.now() + 3000; if (!was) beat(); },
    setChatTyping() { const was = Date.now() < chatTypingUntil; chatTypingUntil = Date.now() + 3000; if (!was) beat(); },

    canModerate: () => Core.me.isOwner || Core.me.isLeader,
    lockOf: qid => Core.state.locks[qid] || null,
    suggestionsFor: qid => Core.state.suggestions[qid] || [],

    // Each action rejects with {status, error, message, ...} from the server; errorText(e) words it.
    /** My one answer to a question, citing results; empty text clears it. Carries the view and device it was made on. */
    answerCiting: (qid, text, cites) => act("/api/answer", { qid, text, cites, ...where() }).then(r => { typingUntil = 0; return r; }),
    /** Choice, confirm, prototype or poll question: pick an option ("" clears it), with an optional comment. */
    // TODO(Phase 9, C44): attachments on a pick and its comment.
    pick: (qid, option, comment) => act("/api/pick", { qid, option: option ? optOut(option) : "", comment: comment || "", ...where() }),
    // TODO(Phase 4b): "Something else…" on choice questions, and the multi, scale and rank picks.
    idea: text => act("/api/propose", { text }).then(r => { typingUntil = 0; return r; }),
    /** A vote on an answer card (its ref, or the page's id) or on a suggestion of that question. */
    vote: (qid, target, on) => ((Core.state.suggestions[qid] || []).some(s => s.id === target)
      ? act("/api/vote", { qid, suggestion: target, on }) : act("/api/vote", { qid, card: refOf(qid, target), on })),
    /** Gather questions: thumbs, heart or idea on an answer; null clears mine. */
    // TODO(Phase 4b): the "down" reaction, and Disagree with a reason on Decide questions.
    react: (qid, target, reaction) => act("/api/react", { qid, card: refOf(qid, target), reaction }),
    REACTIONS: [["thumbs", "👍", "Agree"], ["heart", "❤️", "Love it"], ["idea", "💡", "Sparks an idea"]],
    myReaction: (qid, ref) => Core.state.myReactions?.[qid]?.[ref] || null,
    goWith: (qid, target) => act("/api/go-with", { qid, card: refOf(qid, target) }),
    lock: (qid, target) => act("/api/lock", { qid, ...(target ? { card: refOf(qid, target) } : {}) }).catch(e => {
      throw e?.error === "tie" ? { ...e, tied: (e.tied || []).map(cidOf) } : e;
    }),
    unlock: qid => act("/api/unlock", { qid }),
    suggest: (qid, text, note) => act("/api/suggest", { qid, text, note: note || "" }),
    useSuggestion: (qid, id) => act("/api/suggestion/act", { qid, id, action: "use" }),
    dismissSuggestion: (qid, id) => act("/api/suggestion/act", { qid, id, action: "dismiss" }),
    lockEdit: (qid, text, from) => act("/api/lock/edit", { qid, text, ...(from ? { from } : {}) }),
    chat: (text, replyTo) => act("/api/chat", { text, ...(replyTo ? { replyTo } : {}) }).then(r => { chatTypingUntil = 0; return r; }),
    readNotifications: ids => act("/api/notifications/read", ids === "all" ? { all: true } : { ids }),
    addReference: (qid, reference) => act("/api/question/reference", { qid, reference }),
    removeReference: (qid, index) => act("/api/question/reference", { qid, remove: index }),
    // TODO(Phase 9): the owner's own image reference; until then images come from Claude's add-asset.
    uploadAsset: () => Promise.reject({ error: "uploads-off", message: "Picture references come from Claude for now." }),
    forward: id => act("/api/chat/propose", { id }),
    setLeader: (pid, on) => act("/api/person/role", { pid, role: on ? "leader" : "guest" }),
    setTrusted: (pid, on) => act("/api/person/trust", { pid, on }),
    /** Owner: the page's settings names (showNames, hideClaude) become the contract's. */
    saveSettings: patch => {
      const out = { ...patch };
      if ("showNames" in out) { out.names = out.showNames ? "full" : "initials"; delete out.showNames; }
      if ("hideClaude" in out) { out.claudeTake = out.hideClaude ? "answerFirst" : "always"; delete out.hideClaude; }
      return act("/api/session/settings", out);
    },
    setPurpose: (qid, purpose) => act("/api/question/purpose", { qid, purpose }),
    sendRound: () => act("/api/round/send", {}),
    request: (qid, kind, text) => act("/api/request", { qid, kind, text }),
    later: (id, reason) => act("/api/proposal/act", { id, action: "later", reason }),
    /** Owner: edit | decline | fail | rerun one request, publish | discard a result; runRequests runs the given ids still pending. */
    requestAct: (id, action, text) => act("/api/request/act", { id, action, ...(text != null ? { text } : {}) }),
    runRequests: ids => act("/api/request/act", { action: "run", ids }),
    proposal: (id, action) => act("/api/proposal/act", { id, action }),
    setTitle: title => act("/api/session/title", { title }),
    merge: (from, to) => act("/api/person/merge", { from, to }),
    clearReview: qid => act("/api/review/clear", { qid }),
    markReady: on => act("/api/round/ready", { on }),
    cancelRound: () => act("/api/round/cancel", {}),
    rename: name => act("/api/rename", { name }).then(j => { Core.me.name = j.name; put("name", j.name); emit(); return j; }),
    removePerson: (pid, on) => act("/api/person/remove", { pid, on }),
    newGuestLink: () => act("/api/link/guest", {}),
    /** Owner: a new owner token; this page reloads on the new owner link. */
    newOwnerLink: () => act("/api/link/owner", {}).then(j => { location.hash = "owner=" + j.token; location.reload(); return j; }),
    endSession: on => act("/api/session/end", { on }),
    setGoal: goal => act("/api/session/goal", { goal }),
    /** My own view settings ({key: value}, null clears one); resolves to {prefs, ts}. */
    savePrefs: set => act("/api/prefs", { set }).then(j => ({ ...j, ts: j.at })),
    /** "Were you here before as <name>?" Yes asks the host to merge me into that person. */
    mergeRequest: to => act("/api/merge-request", { to }),
    mergeAct: (id, action) => act("/api/merge-request/act", { id, action }),
    // TODO(Phase 9): uploads (offer, accept, chunks) have no route yet.
    uploadOffer: () => Promise.reject({ error: "uploads-off" }),
    uploadAct: () => Promise.reject({ error: "uploads-off" }),
    uploadChunk: () => Promise.reject({ error: "uploads-off" }),
    /** A link that signs this person in on another device. It carries their secret: keep it private. */
    personalLink: () => {
      const base = `${(Core.state.shareUrl || location.origin).replace(/\/$/, "")}/`;
      return ownerToken ? `${base}#owner=${ownerToken}` : secret ? `${base}#me=${secret}` : "";
    },
    /** The guest link to share: the tunnel base, plus the join key once the owner made a new guest link. */
    guestLink: () => `${(Core.state.shareUrl || location.origin).replace(/\/$/, "")}/${Core.state.guestKey ? "#join=" + Core.state.guestKey : ""}`,
  };

  // ---------- where an answer was made (Q99): the view, and the device, never more ----------
  const BROWSERS = [[/SamsungBrowser\//, "samsung"], [/Edg\//, "edge"], [/(FBAN|FBAV|Instagram|Line\/|; wv\))/, "in-app"], [/Firefox\/|FxiOS\//, "firefox"], [/Chrome\/|CriOS\//, "chrome"], [/Safari\//, "safari"]];
  const deviceKind = () => (matchMedia("(pointer: coarse)").matches ? (matchMedia("(max-width: 720px)").matches ? "phone" : "tablet") : "computer");
  function where() {
    const c = Core.context?.() || {}, ua = navigator.userAgent;
    const view = ["focus", "compare", "tree", "host", "prototype"].includes(c.view) ? c.view : "focus";
    return { view, deviceInfo: { kind: deviceKind(), browser: BROWSERS.find(([re]) => re.test(ua))?.[1] || "other",
      screen: { w: Math.round(innerWidth), h: Math.round(innerHeight) } } };
  }

  const json = body => ({ method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const ident = () => (ownerToken ? { "X-Owner-Token": ownerToken } : secret ? { "X-Session-Secret": secret } : {});

  /** Get a fresh {pid, secret}. Concurrent callers share one request. The owner never joins: the link is the identity. */
  function join(name = Core.me.name) {
    const req = json({ name: name || "", key: joinKey, device: deviceKind() });
    return joining ||= fetch("/api/join", req).then(async r => {
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw { status: r.status, ...j };
      secret = j.secret; Core.me.cid = j.pid;
      put("secret", secret); put("pid", j.pid);
      if (j.name) { Core.me.name = j.name; put("name", j.name); }
      Core.joinedAs = j.was || null; // someone offline already used this name
      return j;
    }).finally(() => { joining = null; });
  }

  /** POST as me: the owner token or secret goes in a header, never the body. Re-joins once if the server forgot me. */
  async function send(path, body) {
    if (!ownerToken && !secret) await join();
    const go = () => fetch(path, { method: "POST", headers: { "Content-Type": "application/json", ...ident() }, body: JSON.stringify(body) });
    let r = await go();
    if (r.status === 401 && !ownerToken) { forget(); await join(); r = await go(); }
    return r;
  }
  function forget() { secret = ""; drop("secret"); drop("pid"); Core.me.cid = ""; }

  const act = (path, body) => send(path, body).then(async r => {
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw { status: r.status, ...j };
    await poll();
    return j;
  });

  const emit = () => listeners.forEach(fn => { try { fn(Core.state, Core); } catch (e) { console.error(e); } });

  function reload(why) {
    for (const fn of reloadHooks) { try { fn(why); } catch (e) { console.error(e); } }
    location.reload();
  }

  /** The state poll always carries ?since=<rev>: in a session imported from the prototype a poll with
   *  identity and no query is an old page, which gets only a reload notice. */
  async function poll() {
    if (polling) return;
    polling = true;
    try {
      const headers = { ...ident(), ...(etag ? { "If-None-Match": etag } : {}) };
      const r = await fetch(`/api/state?since=${rev}`, { headers });
      if (r.status === 304) { lastOk = Date.now(); return; }
      const s = await r.json().catch(() => ({}));
      if (r.status === 403 && s.error === "removed") { Core.state = { ...Core.state, youRemoved: true }; lastOk = Date.now(); return; }
      if (r.status === 401 && !ownerToken) { forget(); etag = ""; askName(errorText(s)); return; }
      if (!r.ok) return;
      if (s.outdated || (s.schemaVersion != null && s.schemaVersion !== SCHEMA_VERSION)) return reload("version");
      if (s.build) { if (build && s.build !== build) return reload("build"); build = s.build; }
      etag = r.headers.get("ETag") || "";
      lastOk = Date.now();
      if (!s.me) { // anonymous: only what the join dialog needs
        Core.state = { ...structuredClone(DEFAULTS), title: s.title || "", ended: !!s.ended, joinNeedsKey: !!s.joinNeedsKey };
        return;
      }
      snap = s; rev = s.rev;
      Core.state = toView(s);
      Core.me.cid = s.me.pid; Core.me.name = s.me.name;
      Core.me.isOwner = s.me.role === "owner"; Core.me.isLeader = s.me.role === "leader"; Core.me.isTrusted = !!s.me.trusted;
      if (!ownerToken) { put("pid", s.me.pid); put("name", s.me.name); }
    } catch { /* offline: the live dot says so */ } finally {
      polling = false;
      Core.live = Date.now() - lastOk < 5000;
      emit();
    }
  }
  Core.snapshot = () => snap;
  function beat() {
    if (!ownerToken && !secret) return;
    send("/api/heartbeat", { q: focusQ, typing: Date.now() < typingUntil, chatTyping: Date.now() < chatTypingUntil })
      .then(r => (r.ok ? r.json() : null)).then(r => {
        if (!r) return;
        if (r.pid && r.pid !== Core.me.cid) { Core.me.cid = r.pid; emit(); }
        if (r.name && r.name !== Core.me.name) { Core.me.name = r.name; if (!ownerToken) put("name", r.name); emit(); }
        Core.me.isOwner = r.role === "owner"; Core.me.isLeader = r.role === "leader"; Core.me.isTrusted = !!r.trusted;
      }).catch(() => {});
  }
  // TODO(Phase 4b): the heartbeat's visible and lastInput, a beat on every visibility change, and Away by hand.

  // Name prompt. It stays open until the join succeeds; Escape does not close it.
  function askName(notice = "") {
    if (document.querySelector("dialog.core-name")) return;
    const dlg = Core.el("dialog", "core-name");
    dlg.setAttribute("aria-labelledby", "core-name-h");
    const form = Core.el("form"), h = Core.el("h2", null, "Join the session"); h.id = "core-name-h";
    const label = Core.el("label", null, "What should everyone call you?"); label.htmlFor = "core-n";
    const input = Core.el("input"); Object.assign(input, { id: "core-n", name: "n", required: true, maxLength: 40, autocomplete: "nickname" });
    input.setAttribute("aria-describedby", "core-n-note core-n-err");
    const note = Core.el("p", "core-note", "Your answers are saved on the host's computer and read by Claude when a round is sent. The side chat is not sent to Claude. We note your device and view to fix problems.");
    note.id = "core-n-note";
    const err = Core.el("p", "core-err", notice); err.id = "core-n-err"; err.setAttribute("role", "alert");
    const go = Core.el("button", null, "Join");
    form.append(h, label, input, note, err, go); dlg.append(form);
    document.body.append(dlg);
    if (Core.state.joinNeedsKey && !joinKey) err.textContent = "This session needs the host's newest invite link. Ask them for it.";
    dlg.addEventListener("cancel", e => e.preventDefault());
    const done = () => { dlg.close(); dlg.remove(); beat(); poll(); };
    /** "Were you here before as <name>?" Yes asks the host to merge; either way the person continues now. */
    function askWas(was) {
      form.replaceChildren();
      const h2 = Core.el("h2", null, `Were you here before as ${was.name}?`); h2.id = "core-name-h";
      const p = Core.el("p", "core-note", `Someone called ${was.name} joined earlier and is not here now. If that was you, the host can join the two, so your earlier answers stay yours. You continue as ${Core.me.name} until they do.`);
      const row = Core.el("div", "core-row");
      const no = Core.el("button", "core-btn-quiet", "No, I am new"); no.type = "button";
      const yes = Core.el("button", null, "Yes, that was me"); yes.type = "button";
      const e2 = Core.el("p", "core-err"); e2.setAttribute("role", "alert");
      row.append(no, yes); form.append(h2, p, e2, row);
      no.onclick = done;
      yes.onclick = () => {
        yes.disabled = no.disabled = true; yes.textContent = "Asking…";
        Core.mergeRequest(was.pid).then(() => { Core.mergeAsked = was; done(); })
          .catch(x => { e2.textContent = `Could not ask: ${errorText(x)}`; yes.disabled = no.disabled = false; yes.textContent = "Try again"; });
      };
      yes.focus();
    }
    form.addEventListener("submit", async e => {
      e.preventDefault();
      const name = input.value.trim().slice(0, 40);
      if (!name) { err.textContent = "Enter a name to join."; input.focus(); return; }
      go.disabled = true; go.textContent = "Joining…"; err.textContent = "";
      try {
        if (!secret) await join(name);
        put("name", Core.me.name);
        if (Core.joinedAs) return askWas(Core.joinedAs);
        done();
      } catch (x) {
        err.textContent = errorText(x);
        go.disabled = false; go.textContent = "Try again"; input.focus();
      }
    });
    dlg.showModal();
  }

  window.Core = Core;
  // Pin the app to the visual viewport: an on-screen keyboard (iOS ignores interactive-widget) shrinks the app
  // from the bottom instead of covering the focused field, and the page never pans. --kb is the keyboard inset.
  const vv = window.visualViewport, docEl = document.documentElement;
  function fitViewport() {
    if (!vv) return;
    const kb = Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop));
    docEl.style.setProperty("--vv-top", vv.offsetTop + "px");
    docEl.style.setProperty("--vv-h", vv.height + "px");
    docEl.style.setProperty("--kb", kb + "px");
    if (kb > 80) docEl.dataset.kb = ""; else delete docEl.dataset.kb;
    if (window.scrollY || window.scrollX) window.scrollTo(0, 0);
  }
  Core.fitViewport = fitViewport;
  vv?.addEventListener("resize", fitViewport);
  vv?.addEventListener("scroll", fitViewport);
  fitViewport();
  /** A secret with no name beside it (a personal link, or a guest the import carried over): ask the server who it is. */
  async function adoptIdentity() {
    const r = await fetch("/api/heartbeat", { method: "POST", headers: { "Content-Type": "application/json", "X-Session-Secret": secret }, body: "{}" });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !j.pid) throw r.status;
    Core.me.cid = j.pid; Core.me.name = j.name; put("pid", j.pid); put("name", j.name);
    if (adopt) Core.adopted = j.name;
    emit();
  }
  window.addEventListener("DOMContentLoaded", () => {
    if (!ownerToken && secret && (adopt || !Core.me.name || !Core.me.cid)) {
      adoptIdentity().then(beat).catch(() => {
        forget(); drop("name"); Core.me.name = "";
        askName(adopt ? "That personal link no longer works. Join with your name; the host can merge you with your earlier self." : "");
      });
    } else if (!ownerToken && !secret) askName();
    poll(); beat();
    setInterval(poll, 1500); setInterval(beat, 2000);
  });
})();
