// Identity, polling, heartbeat and actions: the only code that talks to the server. The page (app.js)
// reads the prototype's state names; toView() builds them from the contract snapshot, and each action
// below sends the contract route's body. The map: .work/shared-interview-ui/snapshot-map.md.
(() => {
  const SCHEMA_VERSION = 2; // the session file version this page was built for; another one reloads it
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
  const unhash = key => {
    hashParams.delete(key);
    history.replaceState(null, "", location.pathname + location.search + (hashParams.toString() ? "#" + hashParams : ""));
  };
  const joinKey = hashParams.get("join") || "";
  // A personal link ("Use on another device") carries the person's secret in the fragment.
  const adopt = hashParams.get("me") || "";
  // The owner link carries the owner token in the fragment. This tab keeps it in sessionStorage and takes it out of
  // the address bar, so a reload or Back in this tab finds it again; a page opened fresh without it is a guest's.
  const ownerToken = (() => {
    const tab = (() => { try { return window.sessionStorage; } catch { return null; } })();
    const fromHash = hashParams.get("owner") || "";
    if (fromHash) {
      try { tab.setItem("owner", fromHash); if (tab.getItem("owner") === fromHash) unhash("owner"); } catch { /* no storage: it stays in the address */ }
      return fromHash;
    }
    const nav = performance.getEntriesByType?.("navigation")?.[0]?.type;
    if (adopt || (nav !== "reload" && nav !== "back_forward")) return "";
    try { return tab.getItem("owner") || ""; } catch { return ""; }
  })();
  if (adopt && !ownerToken) {
    secret = adopt; put("secret", adopt); drop("pid"); drop("name");
    unhash("me");
  }
  if (ownerToken) secret = ""; // the owner link is the owner's only credential

  const listeners = new Set(), reloadHooks = new Set();
  let focusQ = "", typingUntil = 0, chatTypingUntil = 0, lastOk = 0, joining = null;
  let snap = null, rev = 0, etag = "", build = "";
  const DEFAULTS = {
    questions: [], answers: {}, ideas: [], presence: [], locks: {}, disagreements: {}, suggestions: {}, chat: [], leaders: [], trusted: [],
    round: { current: 1, status: "open" }, rounds: [], title: "", people: {}, research: {}, requestCounts: { open: 0, byQ: {} }, requests: [],
    myRequests: [], ended: false, youRemoved: false, youWaiting: false, removed: [], joinRequests: [], cleared: [], guestKey: "", shareChanged: false, shareUrl: "",
    goal: "", intro: "", annotations: [], uploads: [], myUploads: [], files: {}, mergeRequests: [], myMergeRequests: [], me: null, joinNeedsKey: false,
    settings: { voting: true, signoff: false, chat: true, follow: true, showNames: true, digestNames: false, uploads: false, hideClaude: true },
  };

  // C40: a person's color is one of ten ids (Person.color); core.css draws each per theme (--pc-c1..--pc-c10).
  const COLORS = ["c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "c9", "c10"];
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
  /** A pick's fields with the page's option ids turned back into the contract's. */
  const contractPick = f => ("option" in f ? { option: f.option ? optOut(f.option) : "" } : "options" in f ? { options: f.options.map(optOut) }
    : "order" in f ? { order: f.order.map(optOut) } : f);

  function toView(s) {
    const people = {}, nameOf = pid => (pid === "host" && !people.host ? "Host" : people[pid]?.name || "Someone");
    const roles = {};
    for (const p of [...(s.people || []), ...(s.removed || [])]) { people[p.pid] = { name: p.name, ts: p.joinedAt, color: p.color, ...(s.lastSeen?.[p.pid] ? { seen: s.lastSeen[p.pid] } : {}) }; roles[p.pid] = p; }
    const live = (s.people || []);
    const rounds = s.rounds || [], last = rounds[rounds.length - 1];
    const settings = s.settings || {};
    const view = {
      ...DEFAULTS,
      schemaVersion: s.schemaVersion, rev: s.rev, title: s.title || "", goal: s.goal || "", intro: s.intro || "", ended: !!s.ended, serverTime: s.serverTime,
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
      // Q98: a prototype's variants pick like options here; the question links its own page (/proto/<qid>) to try them.
      else if (f.kind === "prototype") { out.format = "choice"; out.options = f.variants.map(v => ({ id: v.id, label: v.label })); out.variants = f.variants; }
      else if (f.kind === "confirm") { out.format = "confirm"; out.image = f.image; out.rect = f.rect; out.options = [{ id: "opt-yes", label: "Yes" }, { id: "opt-no", label: "No" }]; }
      else if (f.kind === "multi" || f.kind === "rank") { out.format = f.kind; out.options = f.options.map(o => ({ ...o, id: optIn(o.id) })); }
      else if (f.kind === "scale") {
        out.format = "scale"; out.min = f.min; out.max = f.max; out.labels = f.labels || {};
        out.options = Array.from({ length: f.max - f.min + 1 }, (_, i) => ({ id: String(f.min + i), label: String(f.min + i) }));
      }
      out.formatKind = f.kind;
      out.needsReview = flag ? { because: flag.because, ts: flag.at, ...(flag.why?.suggestion ? { suggestion: flag.why.suggestion } : {}) } : null;
      if (!flag) delete out.needsReview;
      if (q.origin?.kind === "proposal") { const p = proposals.find(x => x.id === q.origin.proposal); out.proposal = q.origin.proposal; if (p) out.from = nameOf(p.pid); }
      if (q.origin?.kind === "host") { out.proposal = q.origin.proposal; out.addedBy = nameOf(q.origin.by); out.byHost = q.origin.by === "host"; }
      return out;
    });
    const details = s.cardDetails || {};
    // Who stands behind an option of a multi, scale or rank question: the people whose pick holds it (ranked
    // first, on a rank), masked the way the server masks votes for this viewer. Rank options also carry their
    // Borda points (n options: first n-1, last 0; a person's own option is left out).
    const masked = settings.names !== "full" && !["owner", "leader"].includes(s.me?.role);
    const shownPid = pid => (masked && pid !== s.me?.pid ? "" : pid);
    function backers(q, cards) {
      const by = {}, points = {};
      for (const c of cards) {
        if (c.kind !== "person") continue;
        const ranked = (c.order || []).filter(o => o !== "other");
        const ids = q.format === "multi" ? c.picks || [] : q.format === "scale" ? ("value" in c ? [String(c.value)] : []) : ranked.slice(0, 1);
        for (const o of ids) (by[o] ||= []).push(shownPid(c.pid));
        ranked.forEach((o, i) => { points[o] = (points[o] || 0) + ranked.length - 1 - i; });
      }
      return { by, points };
    }
    for (const [qid, cards] of Object.entries(s.cards || {})) {
      const q = qOf(view.questions, qid) || {};
      const formatted = ["multi", "scale", "rank"].includes(q.format) ? backers(q, cards) : null;
      view.answers[qid] = cards.map(c => {
        const base = { cid: cidOf(c.ref), ref: c.ref, votes: c.votes || [], reactions: c.reactions || {} };
        if (c.kind === "claude") {
          const alt = (q.alternatives || []).find(a => a.key === c.key);
          return { ...base, claude: true, rec: c.key === "rec", name: "Claude", text: c.key === "rec" ? q.recommendation || "" : alt?.text || "", ts: c.at || 0,
            ...(c.key === "rec" && q.basis ? { basis: q.basis } : {}), ...(alt?.tradeoff ? { tradeoff: alt.tradeoff } : {}) };
        }
        if (c.kind === "option") {
          const o = (q.options || []).find(x => x.id === optIn(c.option));
          const extra = formatted ? { votes: formatted.by[c.option] || [], ...(q.format === "rank" ? { points: formatted.points[c.option] || 0 } : {}) } : {};
          return { ...base, option: true, claude: false, name: "Option", text: o?.label || "", ts: 0, ...extra };
        }
        const d = details[qid]?.[c.ref], info = d?.deviceInfo;
        // A person's own "Something else…" option: their pick, picks or order holds it, and their text is it.
        const other = c.pick === "other" || (c.picks || []).includes("other") || (c.order || []).includes("other");
        return { ...base, name: nameOf(c.pid), text: c.text || "", ts: c.at, cites: c.cites || [], device: c.device,
          // C44: the files an answer or pick carries, each an upload the owner accepted.
          ...(c.attachments ? { att: c.attachments.map(id => ({ kind: "file", upload: id })) } : {}),
          ...(c.pick ? { pick: optIn(c.pick) } : {}), ...(c.picks ? { picks: c.picks.map(optIn) } : {}), ...("value" in c ? { value: c.value } : {}),
          ...(c.order ? { order: c.order.map(optIn) } : {}), ...(other ? { other: true } : {}),
          ...(c.editedAfterVotes ? { editedAfter: c.editedAfterVotes } : {}), ...(c.late ? { late: c.late } : {}),
          // Phase 4c: hidden by the owner (only its author and the owner get it), edited by the owner, and how many
          // earlier versions it has (the owner's snapshot only; Core.cardHistory fetches them).
          ...(c.hidden ? { hidden: { ts: c.hidden.at, reason: c.hidden.reason || "" } } : {}), ...(c.edited ? { hostEdited: { ts: c.edited.at } } : {}),
          ...(c.versions ? { versions: c.versions } : {}),
          ...(d ? { ctx: { view: d.view, ...(info ? { device: info.kind, browser: info.browser, vw: info.screen?.w, vh: info.screen?.h } : {}) } } : {}) };
      });
    }
    const authorCid = (qid, ref) => (ref ? cidOf(ref) : "");
    for (const [qid, lk] of Object.entries(s.locks || {})) {
      const src = lk.source || {}, sug = src.kind === "suggestion" ? (s.suggestions?.[qid] || []).find(x => x.id === src.suggestion) : null;
      const ref = src.kind === "card" ? src.card : src.kind === "edited" && /^[pco]:/.test(src.from || "") ? src.from : sug ? "p:" + sug.pid : "";
      const kind = ref.split(":")[0];
      view.locks[qid] = { text: src.text || "", answerCid: authorCid(qid, ref), by: nameOf(lk.by), ts: lk.at, edited: src.kind === "edited", hostEdited: !!src.editedBy,
        name: kind === "c" ? "Claude" : kind === "o" ? "Option" : kind === "p" ? nameOf(ref.split(":")[1]) : "", poll: src.kind === "poll" };
    }
    for (const [qid, lst] of Object.entries(s.suggestions || {})) {
      view.suggestions[qid] = lst.map(x => ({ id: x.id, cid: x.pid, name: nameOf(x.pid), text: x.text, note: x.note || "", ts: x.at, status: x.status.kind, votes: x.votes || [] }));
    }
    view.ideas = proposals.map(p => ({ id: p.id, cid: p.pid, name: nameOf(p.pid), text: p.text, ts: p.at,
      status: p.status.kind === "not-placed" ? "notplaced" : p.status.kind, qid: p.status.question || "", reason: p.status.reason || "",
      ...(p.via?.kind === "chat" ? { via: nameOf(p.via.by) } : {}) }));
    view.chat = (s.chat || []).map(m => ({ id: m.id, cid: m.pid, name: nameOf(m.pid), text: m.text, ts: m.at,
      ...(m.replyTo ? { replyTo: { id: m.replyTo.id, cid: m.replyTo.pid, name: nameOf(m.replyTo.pid), text: m.replyTo.excerpt } } : {}),
      ...(m.proposed ? { forwarded: m.proposed } : {}), reactions: m.reactions || {} }));
    // Q98: notes pinned on prototype variants, oldest first.
    view.annotations = (s.annotations || []).map(a => ({ id: a.id, cid: a.pid, name: nameOf(a.pid), qid: a.qid, variant: a.variant, text: a.text, ts: a.at,
      selector: a.anchor?.selector || "", rect: a.anchor?.rect || null }));
    view.joinRequests = (s.joinRequests || []).map(j => ({ pid: j.pid, name: j.name, ts: j.at, n: j.n, device: j.device || "", browser: j.browser || "" }));
    // Answers their authors cleared after the owner hid or edited them (owner only); Core.cardHistory reads one.
    view.cleared = Object.entries(s.cleared || {}).flatMap(([qid, lst]) => lst.map(t => ({ qid, ref: t.ref, cid: t.pid, name: nameOf(t.pid), ts: t.clearedAt, hidden: t.hidden })));
    for (const [qid, lst] of Object.entries(s.results || {})) {
      view.research[qid] = lst.map(x => {
        const r = x.request ? reqText.get(x.request) : null, by = x.by?.kind === "guest-claude" ? x.by.pid : r?.pid;
        return { id: x.id, kind: x.kind, summary: x.summary, sources: x.sources || [], report: x.report || "", ts: x.at, requestId: x.request || "",
          // A guest's own Claude names its own tools in `used`; the label never repeats them.
          skill: x.by?.kind === "guest-claude" ? "their own Claude" : (x.used || []).map(u => u.name).join(", ") || "Claude", why: x.why || "", published: x.published !== false,
          own: x.by?.kind === "guest-claude", // the requester's own Claude answered it (Connect your Claude), not the host's
          ...(r ? { ask: r.text } : {}), ...(by ? { byCid: by, by: nameOf(by) } : {}) };
      });
    }
    const req = r => ({ id: r.id, qid: r.qid, kind: r.kind, text: r.text, edited: r.edited, cid: r.pid, name: nameOf(r.pid), ts: r.at,
      status: r.status.kind, runner: r.runner, ...(r.status.reason ? { reason: r.status.reason } : {}) });
    view.requests = (s.requests || []).map(req);
    view.myRequests = (s.myRequests || []).map(req);
    view.mergeRequests = (s.mergeRequests || []).map(m => ({ id: m.id, from: m.from, to: m.to, fromName: nameOf(m.from), toName: nameOf(m.to), ts: m.at, status: m.status.kind }));
    view.myMergeRequests = (s.myMergeRequests || []).map(m => ({ id: m.id, status: m.status.kind, toName: nameOf(m.to) }));
    // Uploads: my own files, everyone's for the owner (with a picture's preview), and what everyone reads of the
    // files answers carry. No path ever reaches the page.
    const upView = u => ({ id: u.id, cid: u.pid, by: nameOf(u.pid), qid: u.qid || "", file: u.file, ext: u.ext, size: u.size, ts: u.at,
      total: u.chunks, chunkSize: u.chunkSize, status: u.status.kind, received: u.status.received || 0, bytes: u.status.bytes || 0,
      ...(u.status.reason ? { reason: u.status.reason } : {}), ...(u.thumb ? { thumb: u.thumb } : {}) });
    view.myUploads = (s.myUploads || []).map(upView);
    view.uploads = (s.uploads || []).map(upView);
    view.files = s.files || {};
    // Present people are active or away (with since when); a person with no heartbeat for a while is absent: offline.
    view.presence = (s.presence || []).map(p => ({ cid: p.pid, name: nameOf(p.pid), q: p.q, typing: p.typing, chatTyping: p.chatTyping,
      away: p.state === "away", ...(p.state === "away" ? { awaySince: p.since } : {}),
      owner: p.pid === "host", leader: roles[p.pid]?.role === "leader", trusted: !!roles[p.pid]?.trusted }));
    view.disagreements = {};
    for (const [qid, lst] of Object.entries(s.disagreements || {})) {
      view.disagreements[qid] = lst.map(d => ({ cid: d.pid, card: d.card, reason: d.reason, ts: d.at, name: d.pid ? nameOf(d.pid) : "Someone" }));
    }
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
    "merged-into-owner": "This browser was merged into the owner. Open your owner link here.",
    removed: "The host removed you from this session.",
    waiting: "The host has not let you in yet. This page opens by itself once they do.",
    "reaction-cap": "That message has as many reactions as it takes.",
    "notes-full": "This session holds as many notes as it takes, so this one was not pinned.",
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
    "no-such-upload": "That file is gone. The page shows what is there now.",
    "file-type": "Guests can send pictures, PDF, text, CSV and Office files.",
    "upload-too-large": "That is more than this session takes. Guests can send up to 100 MB in all.",
    "hash-mismatch": "The file did not arrive intact. Offer it again.",
    "chunk-gap": "A piece went missing on the way. It is sent again.",
    "bytes-required": "The page sent something the session could not read. Reload and try again.",
    "state-invalid": "The session could not save that. Nothing was changed.",
    full: "This session is full right now. Try again later, or ask the host.",
    busy: "The session is busy. Try again in a moment.",
    "bad-action": "That does not work on this question. Reload the page to see how it takes answers now.",
    "bad-field": "The page sent something the session does not take. Reload and try again.",
    "bad-request": "The page sent something the session could not read. Reload and try again.",
    "json-required": "The page sent something the session could not read. Reload and try again.",
    "bad-host": "This address does not serve the session. Open the link the host shared.",
    "body-timeout": "That took too long to arrive. Check your connection and try again.",
    "no-such-card": "That answer is gone. The page shows what is there now.",
    "no-such-question": "That question is gone. Reload the page.",
    "no-such-proposal": "That proposal is gone. The page shows what is there now.",
    "no-such-request": "That request is gone. The page shows what is there now.",
    "not-found": "That is gone. The page shows what is there now.",
    "not-agreed": "Not everyone here has voted for that answer yet.",
  };
  // A few codes read better with the field they name.
  const FIELD_MESSAGES = {
    "empty:other": "Write your own option first.",
    "empty:reason": "Say why you disagree first.",
    "too-long:reason": "Keep the reason to 200 characters or fewer.",
    "too-long:other": "Your own option is too long.",
    "too-long:comment": "That comment is too long.",
    "too-many-pending:file": "You have 10 files waiting already.",
    "upload-too-large:accept": "This session holds 5 GB of files at most, and this one would pass that. Decline it, or a file still on its way.",
    "too-long:attachments": "An answer carries four files at most.",
    "file-type:file": "That file's contents are not what its name says.",
  };
  // Codes whose sentence above only says the page sent something wrong: a 4xx carrying the server's own message shows
  // that instead, since it says what was refused (bad-field: "The owner's own role, trust and presence cannot change.").
  const GENERIC = new Set(["bad-json", "bytes-required", "bad-field", "bad-request", "json-required"]);
  const errorText = e => FIELD_MESSAGES[`${e?.error}:${e?.field}`]
    || (GENERIC.has(e?.error) && e?.status < 500 && e?.message) || MESSAGES[e?.error] || e?.message
    || (e?.status ? "The session refused that." : "The session is out of reach. Check your connection.");

  const OPPOSITE = { thumbs: "down", down: "thumbs" }; // one person never holds both on one answer
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

    COLORS,
    /** The color id a person chose or was given, else one picked from their id. */
    colorIdOf: id => (COLORS.includes(Core.state.people?.[id]?.color) ? Core.state.people[id].color : COLORS[hash(id || "") % COLORS.length]),
    colorFor: id => `var(--pc-${Core.colorIdOf(id)})`,
    /** Up to two initials, letters and digits only: "Kyle (Admin)" is KA. */
    initials: name => ((name || "").match(/[\p{L}\p{N}]+/gu) || ["?"]).map(w => [...w][0]).join("").slice(0, 2).toUpperCase(),
    el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; },
    /** Round avatar element for a person (cid + name). */
    avatar(personCid, name, size = 28) {
      const a = Core.el("span", "core-avatar", Core.initials(name));
      a.style.setProperty("--av", Core.colorFor(personCid));
      a.dataset.who = personCid || "";
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
    /** extra.attachments (C44), when given, replaces the upload ids the answer carries; left out, it keeps them. */
    answerCiting: (qid, text, cites, extra) => act("/api/answer", { qid, text, cites, ...(extra?.attachments ? { attachments: extra.attachments } : {}), ...where() })
      .then(r => { typingUntil = 0; return r; }),
    /** Choice, confirm, prototype or poll question: pick an option ("" clears it), with an optional comment.
     *  Picking "other" (Something else…) needs opts.other, the person's own option, which takes the comment's place. */
    pick: (qid, option, comment, opts) => Core.pickWith(qid, { option: option || "" }, { comment, other: opts?.other }),
    /** Any format's pick: fields is {option}, {options: [...]} (multi), {value} (scale) or {order: [...]} (rank); an
     *  empty list or a null value clears it. `other` is the person's own option when the pick holds "other".
     *  `attachments`, when given, replaces the upload ids the pick carries (C44); left out, it keeps them. */
    pickWith: (qid, fields, { comment, other, attachments } = {}) => {
      const body = { qid, ...contractPick(fields), ...(other != null ? { other } : { comment: comment || "" }), ...(attachments ? { attachments } : {}), ...where() };
      return act("/api/pick", body, { key: "pick:" + qid, patch: (s, pid) => patchPick(s, pid, qid, body) }).then(r => { typingUntil = 0; return r; });
    },
    idea: text => act("/api/propose", { text }).then(r => { typingUntil = 0; return r; }),
    /** A vote on an answer card (its ref, or the page's id) or on a suggestion of that question. */
    vote: (qid, target, on) => {
      if ((Core.state.suggestions[qid] || []).some(s => s.id === target)) {
        return act("/api/vote", { qid, suggestion: target, on }, { key: "svote:" + qid, patch: (s, pid) => {
          const list = s.suggestions?.[qid] || [];
          for (const x of list) if (on || x.id === target) x.votes = without(x.votes, pid);
          const x = on && list.find(y => y.id === target);
          if (x) x.votes = [...without(x.votes, pid), pid];
        } });
      }
      const card = refOf(qid, target), multi = qOf(Core.state.questions, qid)?.format === "multi";
      return act("/api/vote", { qid, card, on }, { key: multi ? `vote:${qid}:${card}` : "vote:" + qid, patch: (s, pid) => patchVote(s, pid, qid, card, on) });
    },
    /** Gather questions: turn one of thumbs, down, heart or idea on or off on an answer. I may hold several at once,
     *  but thumbs and down exclude each other: turning one on turns the other off (as the server does). */
    react: (qid, target, reaction, on = true) => {
      const card = refOf(qid, target);
      return act("/api/react", { qid, card, reaction, on }, { key: `react:${qid}:${card}:${reaction}`, patch: s => {
        s.me.reactions ||= {};
        s.me.reactions[qid] ||= {};
        const mine = s.me.reactions[qid], was = mine[card] || [], c = cardsOf(s, qid).find(x => x.ref === card);
        const now = Core.REACTIONS.map(([r]) => r).filter(r => (r === reaction ? on : was.includes(r) && !(on && r === OPPOSITE[reaction])));
        if (c) {
          c.reactions ||= {};
          for (const [r] of Core.REACTIONS) c.reactions[r] = Math.max(0, (c.reactions[r] || 0) - was.includes(r) + now.includes(r));
        }
        if (now.length) mine[card] = now; else delete mine[card];
      } });
    },
    REACTIONS: [["thumbs", "👍", "Agree"], ["down", "👎", "Disagree"], ["heart", "❤️", "Love it"], ["idea", "💡", "Sparks an idea"]],
    myReactions: (qid, ref) => Core.state.myReactions?.[qid]?.[ref] || [],
    /** Decide questions: why I disagree with one answer (1..200 characters; a new reason replaces mine); on=false takes it back. */
    disagree: (qid, target, reason, on = true) => {
      const card = refOf(qid, target);
      return act("/api/disagree", { qid, card, on, ...(on ? { reason } : {}) }, { key: `disagree:${qid}:${card}`, patch: (s, pid) => {
        s.disagreements ||= {};
        const kept = (s.disagreements[qid] || []).filter(d => !(d.pid === pid && d.card === card));
        if (on) kept.push({ pid, card, reason, at: s.serverTime });
        s.disagreements[qid] = kept;
      } });
    },
    disagreementsOn: (qid, ref) => (Core.state.disagreements[qid] || []).filter(d => d.card === ref),
    goWith: (qid, target) => act("/api/go-with", { qid, card: refOf(qid, target) }),
    lock: (qid, target) => act("/api/lock", { qid, ...(target ? { card: refOf(qid, target) } : {}) }).catch(e => {
      throw e?.error === "tie" ? { ...e, tied: (e.tied || []).map(cidOf) } : e;
    }),
    unlock: qid => act("/api/unlock", { qid }),
    suggest: (qid, text, note) => act("/api/suggest", { qid, text, note: note || "" }),
    useSuggestion: (qid, id) => act("/api/suggestion/act", { qid, id, action: "use" }),
    dismissSuggestion: (qid, id) => act("/api/suggestion/act", { qid, id, action: "dismiss" }),
    lockEdit: (qid, text, from) => act("/api/lock/edit", { qid, text, ...(from ? { from } : {}) }),
    /** My message shows at once; the server's copy (a message of mine with this text it did not hold before) replaces it. */
    chat: (text, replyTo) => {
      const before = new Set((snap?.chat || []).map(m => m.id)), id = `sending-${++sends}`;
      return act("/api/chat", { text, ...(replyTo ? { replyTo } : {}) }, { key: "chat:" + id, patch: (s, pid) => {
        s.chat ||= [];
        const chat = s.chat;
        if (chat.some(m => m.pid === pid && m.text === text && !before.has(m.id))) return;
        const to = replyTo && chat.find(m => m.id === replyTo);
        chat.push({ id, pid, text, at: s.serverTime, ...(to ? { replyTo: { id: to.id, pid: to.pid, excerpt: to.text } } : {}) });
      } }).then(r => { chatTypingUntil = 0; return r; });
    },
    readNotifications: ids => act("/api/notifications/read", ids === "all" ? { all: true } : { ids }),
    addReference: (qid, reference) => act("/api/question/reference", { qid, reference }),
    removeReference: (qid, index) => act("/api/question/reference", { qid, remove: index }),
    forward: id => act("/api/chat/propose", { id }),
    /** One of my emoji on a chat message, on or off (the server takes only its fixed set). */
    chatReact: (id, emoji, on) => act("/api/chat/react", { id, emoji, on }, { key: `chatreact:${id}:${emoji}`, patch: (s, pid) => {
      const m = (s.chat || []).find(x => x.id === id);
      if (!m) return;
      m.reactions ||= {};
      const r = m.reactions, pids = without(r[emoji], pid);
      if (on) pids.push(pid);
      if (pids.length) r[emoji] = pids; else delete r[emoji];
    } }),
    /** Owner: hide an answer from everyone else and the digest (reversible), or replace its text. */
    hideCard: (qid, target, on, reason) => act("/api/card/hide", { qid, card: refOf(qid, target), on, ...(reason ? { reason } : {}) }),
    editCard: (qid, target, text) => act("/api/card/edit", { qid, card: refOf(qid, target), text }),
    /** Owner: one answer's earlier versions (oldest first), or a cleared answer's last text and versions. */
    cardHistory: async (qid, target) => {
      const r = await fetch(`/api/card/history?${new URLSearchParams({ qid, card: refOf(qid, target) })}`, { headers: ident() });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw { status: r.status, ...j };
      const nameOf = pid => (pid === "host" ? "Host" : Core.state.people[pid]?.name || "Someone");
      return { ...j, history: (j.history || []).map(v => ({ text: v.text, cid: v.by, name: nameOf(v.by), ts: v.at })) };
    },
    /** Owner: admit or decline one person waiting under Approve new joins. */
    joinAct: (pid, action) => act("/api/join/act", { pid, action }),
    /** Owner: "Why you're here" (empty removes it). */
    setIntro: intro => act("/api/session/intro", { intro }),
    setColor: color => act("/api/color", { color }),
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
    /** runner "self": the request runs on my own Claude (Connect your Claude); only I see it. */
    request: (qid, kind, text, _extra, runner) => act("/api/request", { qid, kind, text, ...(runner === "self" ? { runner } : {}) }),
    /** My own Claude's side of a self request: claim it, post its answer ({summary, sources, report, used, why}), or give up. */
    myClaim: id => act("/api/mine/requests/claim", { id }),
    myResult: (id, body) => act("/api/mine/requests/result", { id, ...body }),
    myFail: (id, reason) => act("/api/mine/requests/fail", { id, reason }),
    /** A new watcher key for my own Claude (it replaces any earlier one); it reads and answers my own requests and
     *  nothing else. My session secret never leaves this page. Resolves to the key. */
    newWatcherKey: () => act("/api/watcher", {}).then(j => j.token),
    revokeWatcher: () => act("/api/watcher/revoke", {}),
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
    /** Offer a file ({file, size, type, qid?, thumb?}); resolves to {id, status, chunks, chunkSize}. The bytes wait
     *  in this browser until the owner accepts (the owner's own are accepted at once). */
    uploadOffer: body => act("/api/upload/offer", body),
    /** Owner: accept or decline; the uploader: withdraw. */
    uploadAct: (id, action) => act("/api/upload/act", { id, action }),
    /** One piece of an accepted upload, as raw bytes; `whole` is the whole file's sha256, sent with the last piece.
     *  Resolves to {received}; rejects with {status, error, received?} (409 chunk-gap names the next piece). */
    uploadChunk: (id, index, total, bytes, sha, whole) => spaced("/api/upload/chunk", async () => {
      const headers = { "Content-Type": "application/octet-stream", ...ident(), "X-Upload-Id": id, "X-Chunk-Index": String(index),
        "X-Chunk-Total": String(total), "X-Chunk-Sha256": sha, ...(whole ? { "X-File-Sha256": whole } : {}) };
      const r = await fetch("/api/upload/chunk", { method: "POST", headers, body: bytes });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw { status: r.status, ...j };
      return j;
    }).then(async j => { await poll(); return j; }),
    /** A link that signs this person in on another device. It carries their secret: keep it private. */
    personalLink: () => {
      const base = `${(Core.state.shareUrl || location.origin).replace(/\/$/, "")}/`;
      return ownerToken ? `${base}#owner=${ownerToken}` : secret ? `${base}#me=${secret}` : "";
    },
    /** Q98: a note pinned to an element of one prototype variant. anchor is {selector, rect} from the pin helper. */
    annotate: (qid, variant, anchor, text) => act("/api/annotate", { qid, variant, anchor, text }),
    /** A page of this session, `params` in the fragment. It never holds a credential: a guest's secret stays in this
     *  browser's storage, and the owner's token joins the address only when the owner follows the link. */
    pageLink: (path, params = {}) => {
      const h = new URLSearchParams(params);
      return path + (h.toString() ? "#" + h : "");
    },
    /** The guest link to share: the tunnel base, plus the join key once the owner made a new guest link. */
    guestLink: () => `${(Core.state.shareUrl || location.origin).replace(/\/$/, "")}/${Core.state.guestKey ? "#join=" + Core.state.guestKey : ""}`,
  };

  // ---------- where an answer was made (Q99): the view, and the device, never more ----------
  const BROWSERS = [[/SamsungBrowser\//, "samsung"], [/Edg\//, "edge"], [/(FBAN|FBAV|Instagram|Line\/|; wv\))/, "in-app"], [/Firefox\/|FxiOS\//, "firefox"], [/Chrome\/|CriOS\//, "chrome"], [/Safari\//, "safari"]];
  const deviceKind = () => (matchMedia("(pointer: coarse)").matches ? (matchMedia("(max-width: 720px)").matches ? "phone" : "tablet") : "computer");
  const browserKind = () => BROWSERS.find(([re]) => re.test(navigator.userAgent))?.[1] || "other";
  function where() {
    const c = Core.context?.() || {};
    const view = ["focus", "compare", "tree", "host", "prototype"].includes(c.view) ? c.view : "focus";
    return { view, deviceInfo: { kind: deviceKind(), browser: browserKind(),
      screen: { w: Math.round(innerWidth), h: Math.round(innerHeight) } } };
  }

  const json = body => ({ method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const ident = () => (ownerToken ? { "X-Owner-Token": ownerToken } : secret ? { "X-Session-Secret": secret } : {});

  // The owner following a link to another page of this session (pageLink): the token goes in the fragment of the
  // address opened, never in the link, and a new tab gets no handle on this one. A link within this page (a skip
  // link) is left alone.
  const SESSION_PAGE = /^\/(?:proto\/Q[1-9][0-9]{0,5})?$/;
  function followAsOwner(e) {
    if (!ownerToken || e.defaultPrevented || e.button !== (e.type === "auxclick" ? 1 : 0)) return;
    const a = e.target.closest?.("a[href]"), u = a && new URL(a.href);
    if (!u || u.origin !== location.origin || !SESSION_PAGE.test(u.pathname) || (u.pathname === location.pathname && a.target !== "_blank")) return;
    e.preventDefault();
    const h = new URLSearchParams(u.hash.slice(1));
    h.set("owner", ownerToken);
    const url = `${u.pathname}#${h}`;
    if (a.target === "_blank" || e.type === "auxclick" || e.ctrlKey || e.metaKey || e.shiftKey) window.open(url, "_blank", "noopener");
    else location.assign(url);
  }
  document.addEventListener("click", followAsOwner);
  document.addEventListener("auxclick", followAsOwner);

  /** Get a fresh {pid, secret}. Concurrent callers share one request. The owner never joins: the link is the identity. */
  function join(name = Core.me.name) {
    const req = json({ name: name || "", key: joinKey, device: deviceKind(), browser: browserKind() });
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

  // The server takes one write a second per person on each of these routes (session.py _throttle, WRITE_INTERVAL;
  // a chat reaction per message) and answers a faster one 429. Writes to one route go out one at a time, the next a
  // second after the last answer came back: the server stamps a write before it answers, so that gap is never shorter
  // than a second there.
  const SPACED = new Set(["/api/answer", "/api/pick", "/api/propose", "/api/chat", "/api/suggest", "/api/request", "/api/merge-request",
    "/api/annotate", "/api/rename", "/api/color", "/api/prefs", "/api/about-you", "/api/vote", "/api/react", "/api/disagree",
    "/api/go-with", "/api/notifications/read", "/api/chat/react", "/api/mine/requests/claim", "/api/mine/requests/result", "/api/mine/requests/fail",
    "/api/upload/offer", "/api/upload/act", "/api/upload/chunk"]);
  const GAP = 1050; // ms: the server's one-a-second limit, plus a margin for clock rounding
  const lanes = new Map(); // path -> {tail: promise of the last write, done: when it answered}
  const wait = ms => new Promise(res => setTimeout(res, Math.max(0, ms)));
  function spaced(path, run) {
    if (!SPACED.has(path)) return run();
    const lane = lanes.get(path) || { tail: Promise.resolve(), done: -Infinity };
    lanes.set(path, lane);
    const mine = lane.tail.then(() => wait(lane.done + GAP - Date.now())).then(run).finally(() => { lane.done = Date.now(); });
    lane.tail = mine.catch(() => {});
    return mine;
  }

  /** POST as me: the owner token or secret goes in a header, never the body. Re-joins once if the server forgot me. */
  function send(path, body) {
    return spaced(path, async () => {
      if (!ownerToken && !secret && merged) throw { status: 401, error: "merged-into-owner" };
      if (!ownerToken && !secret) await join();
      const go = () => fetch(path, { method: "POST", headers: { "Content-Type": "application/json", ...ident() }, body: JSON.stringify(body) });
      let r;
      try {
        r = await go();
        if (r.status === 401 && !ownerToken && await mergedIntoOwner(r)) return r;
        if (r.status === 401 && !ownerToken) { forget(); await join(); r = await go(); }
      } catch (e) {
        if (e instanceof TypeError) reportError("api", e.message, { route: path, code: "network" });
        throw e;
      }
      if (!r.ok) r.clone().json().catch(() => ({})).then(j => reportError("api", `HTTP ${r.status}: ${j.message || r.statusText}`, { route: path, code: String(j.error || r.status) }));
      return r;
    });
  }
  function forget() { secret = ""; drop("secret"); drop("pid"); Core.me.cid = ""; }
  /** A merge into the owner ended this browser's guest identity: forget it and say so, never joining again (owner
   *  rights come only with the owner link). Kept across reloads; the owner link clears it. */
  let merged = !ownerToken && get("merged") === "1";
  if (ownerToken) drop("merged");
  function markMerged() {
    forget(); merged = true; put("merged", "1");
    Core.state = { ...Core.state, youMerged: true };
    emit();
  }
  async function mergedIntoOwner(r) {
    const j = await r.clone().json().catch(() => ({}));
    if (j.error !== "merged-into-owner") return false;
    markMerged();
    return true;
  }

  // ---------- error reports: what went wrong in this page reaches server.log as a client entry (README "Logs") ----------
  // Script errors, unhandled rejections, and every action the server refused or never answered (send above). Only once
  // joined: the server refuses an anonymous report. Never answer or chat text, the address's fragment, or a credential.
  const cut = (text, n) => Array.from(String(text)).slice(0, n).join(""); // by code point, as the server counts
  function reportError(kind, message, extra = {}) {
    if (!ownerToken && !secret) return;
    const body = { kind, message: cut(message || kind, 500), route: cut(location.pathname, 200), ua: `${browserKind()} ${deviceKind()}`, ...extra };
    fetch("/api/client-log", { method: "POST", headers: { "Content-Type": "application/json", ...ident() }, body: JSON.stringify(body), keepalive: true }).catch(() => {});
  }
  addEventListener("error", e => reportError("error", e.message, e.filename ? { source: cut(`${new URL(e.filename, location.href).pathname}:${e.lineno}`, 200) } : {}));
  addEventListener("unhandledrejection", e => reportError("rejection", e.reason?.message || e.reason?.error || String(e.reason)));

  // ---------- optimistic actions: shown at once, reconciled with the server in the background ----------
  // An action given a patch shows before its request goes out: patch(snapshot, myPid) edits a copy of the server's
  // last snapshot, and every snapshot after it, until a poll that started after the server accepted the action
  // returns (that snapshot holds the change). A refusal or a network error drops the patch, so the page shows the
  // server's state again, and the caller's catch shows the error. A patch sets state, never toggles it, so applying
  // it to a snapshot that already holds the change changes nothing. One key holds one pending action: a newer
  // action under the same key replaces the older one's patch, and the older one's answer no longer touches it.
  const pending = new Map(); // key -> {patch, after: the poll count when the server accepted it, or null}
  let polls = 0; // polls started so far
  function withPending(s) {
    if (!pending.size || !s?.me) return s;
    const out = structuredClone(s);
    for (const p of pending.values()) { try { p.patch(out, out.me.pid); } catch (e) { console.error(e); } }
    return out;
  }
  const repaint = () => { if (snap) { Core.state = toView(withPending(snap)); emit(); } };
  function act(path, body, opt) {
    const entry = opt && { patch: opt.patch, after: null };
    const mine = () => !!entry && pending.get(opt.key) === entry;
    const drop = () => { if (mine()) { pending.delete(opt.key); repaint(); } };
    if (entry) { pending.delete(opt.key); pending.set(opt.key, entry); repaint(); }
    return send(path, body).then(async r => {
      const j = await r.json().catch(() => ({}));
      if (!r.ok) { drop(); throw { status: r.status, ...j }; }
      if (mine()) entry.after = polls;
      await poll();
      return j;
    }, e => { drop(); throw e; });
  }
  function cardsOf(s, qid) {
    s.cards ||= {};
    s.cards[qid] ||= [];
    return s.cards[qid];
  }
  const without = (list, x) => (list || []).filter(v => v !== x);
  const fmtOf = (s, qid) => qOf(s.questions || [], qid)?.format || {};
  /** My vote on card `ref` of qid, on or off. Off a multi question a person holds one vote per question. */
  function patchVote(s, pid, qid, ref, on) {
    const cards = cardsOf(s, qid), multi = fmtOf(s, qid).kind === "multi";
    if (on && !multi) for (const c of cards) c.votes = without(c.votes, pid);
    const c = cards.find(x => x.ref === ref);
    if (c) c.votes = on ? [...without(c.votes, pid), pid] : without(c.votes, pid);
    // On choice, backing someone's own option moves my one pick there (session.py vote).
    if (on && fmtOf(s, qid).kind === "choice") {
      s.cards[qid] = cards.filter(x => !(x.kind === "person" && x.pid === pid && (x.pick === "other" || !x.text)));
      for (const x of s.cards[qid]) if (x.kind === "person" && x.pid === pid) delete x.pick;
    }
  }
  const isOther = c => c.pick === "other" || (c.picks || []).includes("other") || (c.order || []).includes("other");
  /** My pick on qid as /api/pick takes it (contract option ids), the way session.py pick writes my card and vote. */
  function patchPick(s, pid, qid, body) {
    const kind = fmtOf(s, qid).kind, cards = cardsOf(s, qid), device = body.device;
    const ids = (fmtOf(s, qid).options || []).map(o => o.id).filter(id => id !== "other");
    const fields = "option" in body ? (body.option ? { pick: body.option } : {})
      : "options" in body ? (body.options.length ? { picks: [...ids, "other"].filter(id => body.options.includes(id)) } : {})
      : "value" in body ? (body.value == null ? {} : { value: body.value })
      : body.order?.length ? { order: body.order } : {};
    const i = cards.findIndex(c => c.kind === "person" && c.pid === pid && (c.device || "") === (device || ""));
    const mine = cards[i], chose = isOther(fields);
    if ("option" in body) {
      for (const c of cards) if (kind !== "text" || c.kind === "option") c.votes = without(c.votes, pid);
      const o = fields.pick && !chose && cards.find(c => c.ref === "o:" + fields.pick);
      if (o) o.votes = [...without(o.votes, pid), pid];
    }
    const text = body.other ?? body.comment ?? "";
    if (!Object.keys(fields).length && !text) { if (mine) cards.splice(i, 1); return; }
    const card = { kind: "person", pid, ...(device ? { device } : {}), ref: `p:${pid}${device ? ":" + device : ""}`, text, at: mine?.at ?? s.serverTime,
      cites: mine?.cites || [], votes: mine && (chose || !isOther(mine)) ? mine.votes || [] : [], reactions: mine?.reactions || {},
      ...(body.attachments ? { attachments: body.attachments } : mine?.attachments ? { attachments: mine.attachments } : {}), ...fields };
    if (mine) cards[i] = card; else cards.push(card);
  }
  let sends = 0;

  const emit = () => listeners.forEach(fn => { try { fn(Core.state, Core); } catch (e) { console.error(e); } });

  function reload(why) {
    for (const fn of reloadHooks) { try { fn(why); } catch (e) { console.error(e); } }
    location.reload();
  }

  /** The state poll always carries ?since=<rev>: in a session imported from the prototype a poll with
   *  identity and no query is an old page, which gets only a reload notice. */
  // A poll asked for while one runs runs once more after it, so an action's poll always starts after its answer.
  let polling = null, pollNext = null;
  function poll() {
    if (!polling) {
      polling = pollOnce().finally(() => { polling = null; });
      return polling;
    }
    pollNext ||= polling.then(() => { pollNext = null; return poll(); });
    return pollNext;
  }
  /** Drop the patches of actions the server accepted before poll number `seq` started: its snapshot holds them. */
  function settle(seq) {
    const n = pending.size;
    for (const [k, e] of pending) if (e.after != null && seq > e.after) pending.delete(k);
    return pending.size !== n;
  }
  async function pollOnce() {
    const seq = ++polls;
    try {
      const headers = { ...ident(), ...(etag ? { "If-None-Match": etag } : {}) };
      const r = await fetch(`/api/state?since=${rev}`, { headers });
      if (r.status === 304) { lastOk = Date.now(); if (settle(seq) && snap) Core.state = toView(withPending(snap)); return; }
      const s = await r.json().catch(() => ({}));
      if (r.status === 403 && s.error === "removed") { Core.state = { ...Core.state, youRemoved: true, youWaiting: false }; lastOk = Date.now(); return; }
      // Approve new joins: the person waits until the owner lets them in; the poll keeps asking.
      if (r.status === 403 && s.error === "waiting") { Core.state = { ...structuredClone(DEFAULTS), title: Core.state.title, youWaiting: true }; lastOk = Date.now(); return; }
      if (r.status === 401 && !ownerToken && s.error === "merged-into-owner") { etag = ""; markMerged(); return; }
      if (r.status === 401 && !ownerToken) { forget(); etag = ""; askName(errorText(s)); return; }
      if (!r.ok) return;
      if (s.outdated || (s.schemaVersion != null && s.schemaVersion !== SCHEMA_VERSION)) return reload("version");
      if (s.build) { if (build && s.build !== build) return reload("build"); build = s.build; }
      etag = r.headers.get("ETag") || "";
      lastOk = Date.now();
      if (!s.me) { // anonymous: only what the join dialog needs
        Core.state = { ...structuredClone(DEFAULTS), title: s.title || "", ended: !!s.ended, joinNeedsKey: !!s.joinNeedsKey, youMerged: merged };
        return;
      }
      snap = s; rev = s.rev;
      if (merged) { merged = false; drop("merged"); } // a working identity again (a personal link of someone else)
      settle(seq);
      Core.state = toView(withPending(s));
      Core.me.cid = s.me.pid; Core.me.name = s.me.name;
      Core.me.isOwner = s.me.role === "owner"; Core.me.isLeader = s.me.role === "leader"; Core.me.isTrusted = !!s.me.trusted;
      if (!ownerToken) { put("pid", s.me.pid); put("name", s.me.name); }
    } catch { /* offline: the live dot says so */ } finally {
      Core.live = Date.now() - lastOk < 5000;
      emit();
    }
  }
  Core.snapshot = () => snap;

  // ---------- heartbeat: where I am, whether the tab is visible, how long since my last input, Away by hand ----------
  // The server takes one beat a second (HEARTBEAT_INTERVAL) and answers a faster one 429. A beat that changes `visible`
  // or `away` skips that limit, under its own one a second. So beats never overlap: each waits a GAP after the last
  // one answered (a change beat, after the last change beat only), and many asks in that wait send one beat, built
  // from the state when it goes out.
  // Each tab beats under its own id (kept across reloads of the tab), so the server keeps one presence per tab and a
  // person's other tabs and devices never take their beats: the person is Away only when every tab is.
  const TAB = (() => {
    const fresh = [...crypto.getRandomValues(new Uint8Array(12))].map(b => b.toString(16).padStart(2, "0")).join("");
    try { const t = sessionStorage.getItem("tab"); if (/^[0-9a-f]{24}$/.test(t || "")) return t; sessionStorage.setItem("tab", fresh); } catch { /* storage off */ }
    return fresh;
  })();
  const HB = { busy: false, timer: 0, wanted: false, done: -Infinity, changeDone: -Infinity, visible: null, away: null };
  let away = false, lastInputAt = Date.now();
  const visibleNow = () => document.visibilityState !== "hidden";
  function beat() { HB.wanted = true; pumpBeat(); }
  function pumpBeat() {
    if (HB.busy || HB.timer || !HB.wanted || (!ownerToken && !secret)) return;
    const visible = visibleNow(), change = HB.visible !== null && (visible !== HB.visible || away !== HB.away);
    const due = (change ? HB.changeDone : HB.done) + GAP - Date.now();
    if (due > 0) { HB.timer = setTimeout(() => { HB.timer = 0; pumpBeat(); }, due); return; }
    HB.wanted = false; HB.busy = true;
    const body = { q: focusQ, typing: Date.now() < typingUntil, chatTyping: Date.now() < chatTypingUntil,
      visible, lastInput: Math.max(0, Math.round((Date.now() - lastInputAt) / 1000)), away, tab: TAB };
    send("/api/heartbeat", body).then(r => {
      if (r.ok) { HB.visible = visible; HB.away = away; }
      return r.ok ? r.json() : null;
    }).then(r => {
      if (!r) return;
      if (r.pid && r.pid !== Core.me.cid) { Core.me.cid = r.pid; emit(); }
      if (r.name && r.name !== Core.me.name) { Core.me.name = r.name; if (!ownerToken) put("name", r.name); emit(); }
      Core.me.isOwner = r.role === "owner"; Core.me.isLeader = r.role === "leader"; Core.me.isTrusted = !!r.trusted;
    }).catch(() => {}).finally(() => {
      HB.busy = false; HB.done = Date.now(); if (change) HB.changeDone = HB.done;
      pumpBeat();
    });
  }
  /** Away by hand (the snooze): shown as Away to everyone until my next key, click or touch. */
  Core.setAway = on => { away = !!on; emit(); beat(); };
  Core.isAway = () => away;
  const input = () => {
    lastInputAt = Date.now();
    if (away) { away = false; emit(); beat(); }
  };
  for (const ev of ["keydown", "pointerdown", "touchstart"]) window.addEventListener(ev, input, { capture: true, passive: true });
  document.addEventListener("visibilitychange", beat);
  // iOS freezes a background tab's timers: catch up at once when the page shows again (triage 24).
  const catchUp = () => { if (visibleNow()) poll(); };
  document.addEventListener("visibilitychange", catchUp);
  window.addEventListener("pageshow", catchUp);
  document.addEventListener("resume", catchUp); // Page Lifecycle: a frozen tab thawed (Chrome on Android)
  window.addEventListener("focus", catchUp);

  // Name prompt. It stays open until the join succeeds; Escape does not close it.
  function askName(notice = "") {
    if (document.querySelector("dialog.core-name")) return;
    const dlg = Core.el("dialog", "core-name");
    dlg.setAttribute("aria-labelledby", "core-name-h");
    const form = Core.el("form"), h = Core.el("h2", null, "Join the session"); h.id = "core-name-h";
    // The session's title, so a guest arriving from a bare link knows what they were invited to.
    const sub = Core.el("p", "core-sub"); sub.id = "core-name-sub";
    const paintSub = () => { sub.textContent = Core.state.title ? `You are invited to answer a few questions: ${Core.state.title}` : ""; };
    paintSub();
    const unsub = Core.subscribe(paintSub);
    const label = Core.el("label", null, "What should everyone call you?"); label.htmlFor = "core-n";
    const input = Core.el("input"); Object.assign(input, { id: "core-n", name: "n", required: true, maxLength: 40, autocomplete: "nickname" });
    input.setAttribute("aria-describedby", "core-n-note core-n-err");
    const note = Core.el("p", "core-note", "Your answers are saved on the host's computer and read by Claude when a round is sent. The side chat is not sent to Claude. We note your device and view to fix problems.");
    note.id = "core-n-note";
    const err = Core.el("p", "core-err", notice); err.id = "core-n-err"; err.setAttribute("role", "alert");
    const go = Core.el("button", null, "Join");
    form.append(h, sub, label, input, note, err, go); dlg.append(form);
    document.body.append(dlg);
    if (Core.state.joinNeedsKey && !joinKey) err.textContent = "This session needs the host's newest invite link. Ask them for it.";
    dlg.addEventListener("cancel", e => e.preventDefault());
    // Tab cycles inside the dialog instead of leaving for the browser's own toolbar.
    dlg.addEventListener("keydown", e => {
      if (e.key !== "Tab") return;
      const f = [...dlg.querySelectorAll("input, button")].filter(x => !x.disabled), i = f.indexOf(document.activeElement);
      if (!f.length) return;
      e.preventDefault();
      f[(i + (e.shiftKey ? -1 : 1) + f.length) % f.length].focus();
    });
    const done = () => { unsub(); dlg.close(); dlg.remove(); beat(); poll(); };
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
  // from the bottom instead of covering the focused field, and the page never pans. --kb is the keyboard's height:
  // what it takes from the layout viewport, whose innerHeight a keyboard leaves alone while it shrinks the visual
  // viewport (https://developer.mozilla.org/en-US/docs/Web/API/VisualViewport). The pan iOS adds to reveal the field
  // moves offsetTop, not the height, so it never counts against the keyboard. Pinch-zoomed, WebKit shrinks innerWidth
  // and innerHeight with the visual viewport (https://bugs.webkit.org/show_bug.cgi?id=174362) where Chromium keeps
  // them, but in both the full height for the visual viewport's width is vv.width * innerHeight / innerWidth; what the
  // keyboard takes of it, times scale, is its height on screen, and a zoom alone takes nothing.
  // Fires "core-viewport" on window once the app is refitted.
  const vv = window.visualViewport, docEl = document.documentElement;
  function fitViewport() {
    if (!vv || !window.innerWidth) return;
    const kb = Math.max(0, Math.round(vv.scale * (vv.width * window.innerHeight / window.innerWidth - vv.height)));
    docEl.style.setProperty("--vv-top", vv.offsetTop + "px");
    docEl.style.setProperty("--vv-h", vv.height + "px");
    docEl.style.setProperty("--kb", kb + "px");
    if (kb > 80) docEl.dataset.kb = ""; else delete docEl.dataset.kb;
    if (window.scrollY || window.scrollX) window.scrollTo(0, 0);
    window.dispatchEvent(new Event("core-viewport"));
  }
  // iOS can hand a resize handler an offsetTop of 0 that reads right a moment later
  // (https://bugs.webkit.org/show_bug.cgi?id=237851), and may send no event after it: measure again two frames on.
  const refit = () => { fitViewport(); requestAnimationFrame(() => requestAnimationFrame(fitViewport)); };
  Core.fitViewport = fitViewport;
  vv?.addEventListener("resize", refit);
  vv?.addEventListener("scroll", refit);
  fitViewport();
  /** A secret with no name beside it (a personal link, or a guest the import carried over): ask the server who it is.
   *  Only the server's refusal of the secret (401) forgets it, rejecting with 401; a removed person (403) keeps it and
   *  rejects with 403. Anything else (429, a server error, no network, as when every tab reloads at once) keeps the
   *  secret and asks again, waiting longer each time. */
  async function adoptIdentity() {
    HB.busy = true; // this is a beat too: the next one waits its turn
    try {
      for (let tries = 0; ; tries++) {
        const visible = visibleNow();
        const r = await fetch("/api/heartbeat", { method: "POST", headers: { "Content-Type": "application/json", "X-Session-Secret": secret },
          body: JSON.stringify({ visible, tab: TAB }) }).catch(() => null);
        HB.done = Date.now();
        if (r?.status === 401 && await mergedIntoOwner(r)) throw "merged";
        if (r?.status === 401 || r?.status === 403) throw r.status;
        const j = r?.ok ? await r.json().catch(() => ({})) : {};
        if (j.pid) {
          HB.visible = visible; HB.away = false;
          Core.me.cid = j.pid; Core.me.name = j.name; put("pid", j.pid); put("name", j.name);
          if (adopt) Core.adopted = j.name;
          emit();
          return;
        }
        await wait(Math.min(GAP * 2 ** tries, 15000) + Math.random() * 500);
      }
    } finally { HB.busy = false; }
  }
  window.addEventListener("DOMContentLoaded", () => {
    if (!ownerToken && secret && (adopt || !Core.me.name || !Core.me.cid)) {
      adoptIdentity().then(beat).catch(status => {
        if (status !== 401) return; // removed: the state poll shows it, and the owner can restore the same secret
        forget(); drop("name"); Core.me.name = "";
        askName(adopt ? "That personal link no longer works. Join with your name; the host can merge you with your earlier self." : "");
      });
    } else if (!ownerToken && !secret && !merged) askName();
    else beat();
    poll();
    setInterval(poll, 1500); setInterval(beat, 2000);
  });
})();
