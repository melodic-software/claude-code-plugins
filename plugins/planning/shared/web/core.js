// Identity, polling, heartbeat and actions: the only code that talks to the server. The page (app.js)
// reads the prototype's state names; toView() builds them from the contract snapshot, and each action
// below sends the contract route's body. The map: .work/shared-interview-ui/snapshot-map.md.
(() => {
  const memory = new Map();
  const store = (() => { try { const s = window.localStorage; s.setItem("_t", "1"); s.removeItem("_t"); return s; } catch { return null; } })()
    || { getItem: k => memory.get(k) ?? null, setItem: (k, v) => memory.set(k, v), removeItem: k => memory.delete(k) };
  const get = k => { try { return store.getItem(k); } catch { return memory.get(k) ?? null; } };
  const put = (k, v) => { try { store.setItem(k, v); } catch { memory.set(k, v); } };
  const drop = k => { try { store.removeItem(k); } catch { /* storage gone */ } memory.delete(k); };
  /** A record's upload ids as the page's attachment list, and what a write sends of one (nothing for none). */
  const attOf = x => (x.attachments ? { att: x.attachments.map(id => ({ kind: "file", upload: id })) } : {});
  const withAtt = extra => (extra?.attachments?.length ? { attachments: extra.attachments } : {});

  // The guest secret lives under the prototype's key ("secret"), so a guest the import carried over
  // keeps their identity after the cutover reload. It leaves this browser only as a header.
  let secret = get("secret") || "";
  const hashParams = new URLSearchParams(location.hash.slice(1));
  const unhash = key => {
    hashParams.delete(key);
    history.replaceState(null, "", location.pathname + location.search + (hashParams.toString() ? "#" + hashParams : ""));
  };
  const joinKey = hashParams.get("join") || "";
  // The host's one-time code for signing this device in as the host ("Sign in on another device"), from its QR code.
  const pairCode = hashParams.get("pair") || "";
  if (pairCode) unhash("pair");
  // A personal link ("Use on another device") carries the person's secret in the fragment.
  let adopt = hashParams.get("me") || "";
  // The owner link carries the owner token in the fragment. This tab keeps it in sessionStorage and takes it out of
  // the address bar, so a reload or Back in this tab finds it again; a page opened fresh without it is a guest's.
  // A device the host signed in with a code keeps its own credential in localStorage ("ownerDevice") until signed out.
  const ownerToken = (() => {
    const tab = (() => { try { return window.sessionStorage; } catch { return null; } })();
    const fromHash = hashParams.get("owner") || "";
    if (fromHash) {
      try { tab.setItem("owner", fromHash); if (tab.getItem("owner") === fromHash) unhash("owner"); } catch { /* no storage: it stays in the address */ }
      return fromHash;
    }
    if (adopt) return "";
    const nav = performance.getEntriesByType?.("navigation")?.[0]?.type;
    let kept = "";
    if (nav === "reload" || nav === "back_forward") try { kept = tab.getItem("owner") || ""; } catch { /* no storage */ }
    return kept || get("ownerDevice") || "";
  })();
  // A personal link for someone else never replaces who this browser already is without a yes (askSwitch): a link
  // handed over must not sign this device in as its sender. With no secret stored, the link is adopted at once.
  const switchTo = adopt && !ownerToken && secret && secret !== adopt ? adopt : "";
  if (adopt && !ownerToken) {
    if (switchTo) adopt = "";
    else { secret = adopt; put("secret", adopt); drop("pid"); drop("name"); }
    unhash("me");
  }
  if (ownerToken) secret = ""; // the owner link is the owner's only credential
  const ownerDevice = !!ownerToken && ownerToken === get("ownerDevice");

  const listeners = new Set(), reloadHooks = new Set();
  let focusQ = "", typingUntil = 0, chatTypingUntil = 0, lastOk = 0, shownAt = null, joining = null;
  let snap = null, rev = 0, etag = "", build = "";
  const DEFAULTS = {
    questions: [], answers: {}, ideas: [], presence: [], locks: {}, disagreements: {}, suggestions: {}, chat: [], leaders: [], trusted: [],
    round: { current: 1, status: "open" }, rounds: [], title: "", people: {}, research: {}, requestCounts: { open: 0, byQ: {} }, requests: [],
    myRequests: [], ended: false, youRemoved: false, youWaiting: false, removed: [], joinRequests: [], cleared: [], guestKey: "", shareChanged: false, shareUrl: "",
    goal: "", intro: "", annotations: [], uploads: [], reports: [], myReports: [], passes: {}, myUploads: [], files: {}, questionPics: {}, mergeRequests: [], myMergeRequests: [], inbox: [], discussions: {}, discussionSeen: {}, me: null, joinNeedsKey: false,
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

  // ---------- mentions: the server stores <@pid>; the page only ever shows and sends "@Name" ----------
  const TOKEN = /<@([A-Za-z0-9_-]{1,32})>/g;
  const initialsOf = name => ((name || "").match(/[\p{L}\p{N}]+/gu) || ["?"]).map(w => [...w][0]).join("").slice(0, 2).toUpperCase();
  /** "@Name" text of the people a label map holds ([[label, pid]], longest first), as a pattern; null for none. */
  const labelRe = labels => (labels.length ? new RegExp(`(^|[^\\p{L}\\p{N}])@(${labels.map(([l]) => l.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})(?![\\p{L}\\p{N}_])`, "giu") : null);
  let MENTIONS = { live: [], all: [], label: () => "someone" };

  function toView(s) {
    const people = {}, nameOf = pid => (pid === "host" && !people.host ? "Host" : people[pid]?.name || "Someone");
    const roles = {};
    for (const p of [...(s.people || []), ...(s.removed || [])]) { people[p.pid] = { name: p.name, ts: p.joinedAt, color: p.color, ...(s.lastSeen?.[p.pid] ? { seen: s.lastSeen[p.pid] } : {}) }; roles[p.pid] = p; }
    const live = (s.people || []);
    const rounds = s.rounds || [], last = rounds[rounds.length - 1];
    const settings = s.settings || {};
    // How a mention reads: the name as the page shows names (initials unless names are full; "someone" where the
    // server hides them), a removed person's last name, and "someone" for anyone else.
    const shown = n => (settings.names === "full" ? n : n === "Someone" ? "someone" : initialsOf(n));
    const label = pid => (people[pid] ? shown(people[pid].name) : s.mentions?.[pid] ? shown(s.mentions[pid]) : "someone");
    const labels = pids => {
      const by = new Map();
      for (const p of pids) { const l = label(p), k = l.toLowerCase(); by.set(k, by.has(k) && by.get(k)[1] !== p ? [l, ""] : [l, p]); }
      return [...by.values()].sort((a, b) => b[0].length - a[0].length);
    };
    MENTIONS = { live: labels(live.map(p => p.pid)), all: labels([...Object.keys(people), ...Object.keys(s.mentions || {})]), label };
    const plain = t => (typeof t === "string" && t.includes("<@") ? t.replace(TOKEN, (_, p) => "@" + label(p)) : t);
    const view = {
      ...structuredClone(DEFAULTS), // its own maps: a question whose last answer, lock, suggestion or result went must lose its key
      rev: s.rev, title: s.title || "", goal: s.goal || "", intro: s.intro || "", ended: !!s.ended, serverTime: s.serverTime,
      // reviewAnswers: absent (a session from before the setting) reviews every answer, as those sessions always did.
      settings: { ...settings, showNames: settings.names === "full", hideClaude: settings.claudeTake !== "always", reviewAnswers: settings.reviewAnswers !== false },
      people, ownerPid: "host",
      leaders: live.filter(p => p.role === "leader").map(p => p.pid), trusted: live.filter(p => p.trusted && p.pid !== "host").map(p => p.pid),
      removed: (s.removed || []).map(p => p.pid),
      rounds: rounds.map(r => ({ n: r.n, status: r.status.kind })),
      round: last ? { current: last.n, status: last.status.kind, sentAt: last.status.sentAt, ackAt: last.status.ackAt,
        ...(last.status.ready ? { ready: { by: nameOf(last.status.ready.by), cid: last.status.ready.by, ts: last.status.ready.at } } : {}) } : { current: 1, status: "open" },
      requestCounts: s.requestCounts || DEFAULTS.requestCounts, behind: s.behind || {}, aboutYou: s.aboutYou || {}, myAbout: s.me?.aboutYou || null,
      shareUrl: s.share?.url || "", shareChanged: !!s.share?.changedAt, guestKey: s.guestKey || "", ownerDevices: s.ownerDevices || [],
    };
    const proposals = s.proposals || [];
    const reqText = new Map([...(s.requests || []), ...(s.myRequests || [])].map(r => [r.id, r]));
    view.questions = (s.questions || []).map(q => {
      const f = q.format || { kind: "text" }, flag = (q.needsReview || []).at(-1);
      const { format: _, ...rest } = q, out = { ...rest, text: plain(q.text), purpose: q.purpose || "decide" };
      if (f.kind === "choice") { out.format = "choice"; out.options = f.options; }
      // Q98: a prototype's variants pick like options here; the question links its own page (/proto/<qid>) to try them.
      else if (f.kind === "prototype") { out.format = "choice"; out.options = f.variants.map(v => ({ id: v.id, label: v.label })); out.variants = f.variants; }
      else if (f.kind === "confirm") { out.format = "confirm"; out.image = f.image; out.rect = f.rect; out.options = [{ id: "opt-yes", label: "Yes" }, { id: "opt-no", label: "No" }]; }
      else if (f.kind === "multi" || f.kind === "rank") { out.format = f.kind; out.options = f.options.map(o => ({ ...o, id: optIn(o.id) })); }
      else if (f.kind === "scale") {
        out.format = "scale"; out.min = f.min; out.max = f.max; out.labels = f.labels || {};
        out.options = Array.from({ length: f.max - f.min + 1 }, (_, i) => ({ id: String(f.min + i), label: String(f.min + i) }));
      }
      if (q.context) out.context = plain(q.context); // a mention in it reads as @Name, as the question's text does
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
        return { ...base, name: nameOf(c.pid), text: plain(c.text || ""), ts: c.at, cites: c.cites || [], device: c.device,
          // C44: the files an answer or pick carries, each an upload the owner accepted.
          ...attOf(c),
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
      view.locks[qid] = { text: plain(src.text || ""), answerCid: authorCid(qid, ref), by: nameOf(lk.by), ts: lk.at, edited: src.kind === "edited", hostEdited: !!src.editedBy,
        name: kind === "c" ? "Claude" : kind === "o" ? "Option" : kind === "p" ? nameOf(ref.split(":")[1]) : "", poll: src.kind === "poll" };
    }
    for (const [qid, lst] of Object.entries(s.suggestions || {})) {
      view.suggestions[qid] = lst.map(x => ({ id: x.id, cid: x.pid, name: nameOf(x.pid), text: plain(x.text), note: plain(x.note || ""), ts: x.at, status: x.status.kind, votes: x.votes || [], ...attOf(x) }));
    }
    view.ideas = proposals.map(p => ({ id: p.id, cid: p.pid, name: nameOf(p.pid), text: plain(p.text), ts: p.at,
      status: p.status.kind === "not-placed" ? "notplaced" : p.status.kind, qid: p.status.question || "", reason: p.status.reason || "",
      ...(p.via?.kind === "chat" ? { via: nameOf(p.via.by) } : {}), ...attOf(p) }));
    // Claude's shared answer to a request about the whole session is the host's message marked `claude`: it shows as Claude's.
    const byClaude = new Set((s.chat || []).filter(m => m.claude).map(m => m.id));
    const who = (pid, claude) => (claude ? { cid: "claude", name: "Claude" } : { cid: pid, name: nameOf(pid) });
    view.chat = (s.chat || []).map(m => ({ id: m.id, ...who(m.pid, m.claude), text: plain(m.text), ts: m.at, ...(m.gapAbove ? { gapAbove: true } : {}),
      ...(m.replyTo ? { replyTo: { id: m.replyTo.id, ...who(m.replyTo.pid, m.replyTo.claude || byClaude.has(m.replyTo.id)), text: plain(m.replyTo.excerpt) } } : {}),
      ...(m.proposed ? { forwarded: m.proposed } : {}), ...(m.claude ? { claude: true, result: m.claude.result } : {}), ...(m.request ? { request: m.request } : {}),
      reactions: m.reactions || {}, ...attOf(m) }));
    // Each question's Discussion, oldest first; `seen` is when I last opened it, so others' comments after it are new.
    view.discussions = Object.fromEntries(Object.entries(s.discussions || {}).map(([qid, lst]) => [qid, lst.map(c => ({ id: c.id, cid: c.pid, name: nameOf(c.pid),
      text: plain(c.text), ts: c.at, edited: !!c.edited, hidden: !!c.hidden, request: c.request || "", reactions: c.reactions || {}, ...attOf(c) }))]));
    view.discussionSeen = s.me?.discussionSeen || {};
    // Q98: notes pinned on prototype variants, oldest first.
    view.annotations = (s.annotations || []).map(a => ({ id: a.id, cid: a.pid, name: nameOf(a.pid), qid: a.qid, variant: a.variant, text: plain(a.text), ts: a.at,
      selector: a.anchor?.selector || "", rect: a.anchor?.rect || null }));
    view.joinRequests = (s.joinRequests || []).map(j => ({ pid: j.pid, name: j.name, ts: j.at, n: j.n, device: j.device || "", browser: j.browser || "" }));
    // Answers their authors cleared after the owner hid or edited them (owner only); Core.cardHistory reads one.
    view.cleared = Object.entries(s.cleared || {}).flatMap(([qid, lst]) => lst.map(t => ({ qid, ref: t.ref, cid: t.pid, name: nameOf(t.pid), ts: t.clearedAt, hidden: t.hidden })));
    for (const [qid, lst] of Object.entries(s.results || {})) {
      view.research[qid] = lst.map(x => {
        const r = x.request ? reqText.get(x.request) : null, by = x.by?.kind === "guest-claude" ? x.by.pid : r?.pid;
        return { id: x.id, kind: x.kind, summary: x.summary, msg: x.msg || "", sources: x.sources || [], report: x.report || "", ts: x.at, requestId: x.request || "",
          // A guest's own Claude names its own tools in `used`; the label never repeats them.
          skill: x.by?.kind === "guest-claude" ? "their own Claude" : (x.used || []).map(u => u.name).join(", "), why: x.why || "", published: x.published !== false,
          own: x.by?.kind === "guest-claude", // the requester's own Claude answered it (Connect your Claude), not the host's
          // Unshared and out to its asker (a Just me answer, or one the owner took down), and taken down by the owner.
          private: !!x.private, takenDown: !!x.takenDown, ...(r?.audience === "me" ? { justMe: true } : {}),
          ...(r ? { ask: plain(r.text) } : {}), ...(by ? { byCid: by, by: nameOf(by) } : {}) };
      });
    }
    const req = r => ({ id: r.id, qid: r.qid || "", kind: r.kind, text: plain(r.text), edited: r.edited, cid: r.pid, name: nameOf(r.pid), ts: r.at,
      status: r.status.kind, runner: r.runner, ...(r.audience === "me" ? { justMe: true } : {}), ...(r.status.reason ? { reason: r.status.reason } : {}), ...attOf(r) });
    view.requests = (s.requests || []).map(req);
    view.myRequests = (s.myRequests || []).map(req);
    // The Inbox: my own requests with the status I see, and for the owner what waits on them; the server decides both.
    // A person asking to join is not in people yet: their name comes from joinRequests.
    const joinName = pid => (s.joinRequests || []).find(j => j.pid === pid)?.name;
    view.inbox = (s.inbox || []).map(i => ({ ...i, ts: i.at, changedTs: i.changed, ...(i.by ? { byCid: i.by, by: people[i.by] ? nameOf(i.by) : joinName(i.by) || nameOf(i.by) } : {}) }));
    view.mergeRequests = (s.mergeRequests || []).map(m => ({ id: m.id, from: m.from, to: m.to, fromName: nameOf(m.from), toName: nameOf(m.to), ts: m.at, status: m.status.kind }));
    view.myMergeRequests = (s.myMergeRequests || []).map(m => ({ id: m.id, status: m.status.kind, toName: nameOf(m.to) }));
    // Uploads: my own files, everyone's for the owner (with a picture's preview), and what everyone reads of the
    // files answers carry. No path ever reaches the page.
    const upView = u => ({ id: u.id, cid: u.pid, by: nameOf(u.pid), qid: u.qid || "", file: u.file, ext: u.ext, size: u.size, ts: u.at,
      total: u.chunks, chunkSize: u.chunkSize, status: u.status.kind, received: u.status.received || 0, bytes: u.status.bytes || 0,
      ...(u.status.reason ? { reason: u.status.reason } : {}), ...(u.thumb ? { thumb: u.thumb } : {}), ...(u.image ? { image: true } : {}), ...(u.shown ? { shown: true } : {}), ...(u.carried ? { carried: true } : {}) });
    view.myUploads = (s.myUploads || []).map(upView);
    view.uploads = (s.uploads || []).map(upView);
    // Problem reports (owner only): the picture itself comes from Core.reportImage when the owner opens one.
    view.reports = (s.reports || []).map(r => ({ id: r.id, cid: r.by, name: nameOf(r.by), text: r.text, ctx: r.ctx, image: r.image, status: r.status, asked: !!r.asked, ts: r.ts, adds: r.adds || [] }));
    // My own problem reports (Your reports): their words, additions and status, never the page context.
    view.myReports = (s.myReports || []).map(r => ({ id: r.id, text: r.text, image: r.image, status: r.status, ts: r.ts, adds: r.adds || [] }));
    view.files = { ...held.files, ...(s.files || {}) };
    // Follow-up 32: qid -> received pictures offered on it that nothing carries, as far as this viewer may see them.
    view.questionPics = s.questionPics || {};
    // Passes and their reasons (owner only): qid -> pid -> {reason?, ts}.
    view.passes = s.passes || {};
    // Present people are active or away (with since when); a person with no heartbeat for a while is absent: offline.
    view.presence = (s.presence || []).map(p => ({ cid: p.pid, name: nameOf(p.pid), q: p.q, typing: p.typing, chatTyping: p.chatTyping,
      away: p.state === "away", ...(p.state === "away" ? { awaySince: p.since } : {}),
      owner: p.pid === "host", leader: roles[p.pid]?.role === "leader", trusted: !!roles[p.pid]?.trusted }));
    view.disagreements = {};
    for (const [qid, lst] of Object.entries(s.disagreements || {})) {
      view.disagreements[qid] = lst.map(d => ({ cid: d.pid, card: d.card, reason: d.reason, ts: d.at, name: d.pid ? nameOf(d.pid) : "Someone" }));
    }
    if (s.me) {
      view.me = { ...s.me, notifications: (s.me.notifications || []).map(n => ({ ...n, ...(n.body ? { body: plain(n.body) } : {}), ts: n.at, ...(n.by ? { byCid: n.by, by: nameOf(n.by) } : {}) })) };
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
    "no-such-person": "That person is not in this session.",
    waiting: "The host has not let you in yet. This page opens by itself once they do.",
    "reaction-cap": "That message has as many reactions as it takes.",
    "notes-full": "This session holds as many notes as it takes, so this one was not pinned.",
    ended: "This session has ended.",
    "bad-guest-key": "This invite link is no longer valid. Ask the host for the new one.",
    "bad-pair-code": "That code is wrong or has expired. Make a new one on your first device.",
    "host-device-only": "Do that on the device where you opened your owner link.",
    "devices-full": "As many other devices as a session takes are signed in. Sign one out first.",
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
    "too-many-reports": "This session holds as many problem reports as it takes.",
    "too-many-proposals": "This session holds as many proposals as it takes.",
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
    "too-many-pending:text": "You have 10 proposals waiting already.",
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
    /** A request about the whole session has no question: the page files it, and finds its results, under this key. */
    GENERAL: "session",
    // cid holds the public pid (the prototype's name for it).
    me: { cid: secret ? get("pid") || "" : ownerToken ? "host" : "", name: get("name") || "", isOwner: !!ownerToken, isLeader: false, isTrusted: false },
    state: structuredClone(DEFAULTS),
    live: false,
    errorText,
    /** The time since ts (server seconds): "5 min", "2 h", "3 d", or "" under a minute. */
    span(ts) {
      const s = Math.max(0, Math.round((Core.state.serverTime || Date.now() / 1000) - ts));
      return s < 60 ? "" : s < 3600 ? `${Math.floor(s / 60)} min` : s < 86400 ? `${Math.floor(s / 3600)} h` : `${Math.floor(s / 86400)} d`;
    },
    /** When ts was, as the page writes it everywhere: "just now", "5 min ago". */
    since(ts) { const d = Core.span(ts); return d ? `${d} ago` : "just now"; },

    /** fn(state, Core) runs after every poll and every local change. Returns an unsubscribe function. */
    subscribe(fn) { listeners.add(fn); fn(Core.state, Core); return () => listeners.delete(fn); },
    /** fn() runs just before the page reloads itself for a new version: save unsent text. */
    onReload(fn) { reloadHooks.add(fn); return () => reloadHooks.delete(fn); },

    COLORS,
    /** The color id a person chose or was given, else one picked from their id. */
    colorIdOf: id => (COLORS.includes(Core.state.people?.[id]?.color) ? Core.state.people[id].color : COLORS[hash(id || "") % COLORS.length]),
    colorFor: id => `var(--pc-${Core.colorIdOf(id)})`,
    /** Up to two initials, letters and digits only: "Kyle (Admin)" is KA. */
    initials: initialsOf,
    /** Text with each <@pid> as "@Name", the way this page shows that person. */
    plain: t => (typeof t === "string" ? t.replace(TOKEN, (_, p) => "@" + MENTIONS.label(p)) : t),
    /** How "@Name" reads for this person on this page: what the mention picker inserts and tokenize maps back. */
    mentionLabel: pid => MENTIONS.label(pid),
    /** [[label, pid]] of everyone a mention can name here, longest first; pid "" where two people read alike. */
    mentionLabels: () => MENTIONS.all,
    /** Written text with each "@Name" of someone here (one person reads that way) as <@pid>, as the server stores it. */
    tokenize: t => {
      const re = typeof t === "string" && t.includes("@") ? labelRe(MENTIONS.live.filter(([, p]) => p)) : null;
      if (!re) return t;
      const by = new Map(MENTIONS.live.map(([l, p]) => [l.toLowerCase(), p]));
      return t.split(/(<@[A-Za-z0-9_-]{1,32}>)/).map((part, i) => (i % 2 ? part : part.replace(re, (m, pre, l) => (by.get(l.toLowerCase()) ? `${pre}<@${by.get(l.toLowerCase())}>` : m)))).join("");
    },
    labelRe,
    el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; },
    /** Round avatar element for a person (cid + name). */
    avatar(personCid, name, size = 28) {
      const a = Core.el("span", "core-avatar", Core.initials(name));
      a.style.setProperty("--av", Core.colorFor(personCid));
      a.dataset.who = personCid || "";
      a.style.width = a.style.height = size + "px";
      a.style.fontSize = Math.max(9, Math.round(size * 0.4)) + "px"; // initials never below 9 px
      a.title = name;
      return a;
    },

    answersFor: qid => Core.state.answers[qid] || [],
    /** My own answer record on qid: on a question asked once per device, this device's record only, so every read of
     *  my pick, text, cites and attachments is about the answer this device sends. */
    myRecord: qid => { const d = scopeOf(qid).device; return Core.answersFor(qid).find(a => a.cid === Core.me.cid && !a.claude && !a.option && (!d || a.device === d)); },
    myAnswer: qid => Core.myRecord(qid)?.text || "",
    /** Follow-up 47: on a question asked once per device, the device kinds I answered from other than this one. */
    myOtherDevices: qid => { const d = scopeOf(qid).device; return d ? [...new Set(Core.answersFor(qid).filter(a => a.cid === Core.me.cid && !a.claude && !a.option && a.device && a.device !== d).map(a => a.device))] : []; },
    thisDevice: () => deviceKind(),
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
    answerCiting: (qid, text, cites, extra) => act("/api/answer", { qid, text, cites, ...(extra?.attachments ? { attachments: extra.attachments } : {}), ...where(), ...scopeOf(qid) })
      .then(r => { typingUntil = 0; return r; }),
    /** Choice, confirm, prototype or poll question: pick an option ("" clears it), with an optional comment.
     *  Picking "other" (Something else…) needs opts.other, the person's own option, which takes the comment's place. */
    pick: (qid, option, comment, opts) => Core.pickWith(qid, { option: option || "" }, { comment, other: opts?.other }),
    /** Any format's pick: fields is {option}, {options: [...]} (multi), {value} (scale) or {order: [...]} (rank); an
     *  empty list or a null value clears it. `other` is the person's own option when the pick holds "other".
     *  `attachments`, when given, replaces the upload ids the pick carries (C44); left out, it keeps them. */
    pickWith: (qid, fields, { comment, other, attachments } = {}) => {
      const body = { qid, ...contractPick(fields), ...(other != null ? { other } : { comment: comment || "" }), ...(attachments ? { attachments } : {}), ...where(), ...scopeOf(qid) };
      return act("/api/pick", body, { key: "pick:" + qid, patch: (s, pid) => patchPick(s, pid, qid, body) }).then(r => { typingUntil = 0; return r; });
    },
    idea: (text, extra) => act("/api/propose", { text, ...withAtt(extra) }).then(r => { typingUntil = 0; return r; }),
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
    /** Pass on a question, any purpose: no view to give. The reason is optional (0..200), required when it is asked of me;
     *  on=false takes it back. */
    pass: (qid, reason, on = true) => act("/api/pass", { qid, on, ...(on && reason ? { reason } : {}) }, { key: "pass:" + qid, patch: s => {
      s.me.passes ||= {};
      if (on) s.me.passes[qid] = { ...(reason ? { reason } : {}), ts: s.serverTime }; else delete s.me.passes[qid];
    } }),
    myPass: qid => Core.state.me?.passes?.[qid] || null,
    /** The people a question is asked of (its `for`), as pids; empty asks everyone. */
    askedOf: qid => qOf(Core.state.questions, qid)?.for || [],
    /** The server's one rule for taking part (session.py _took_part): my own answer, a vote, a back, any reaction, a
     *  Disagree or a Pass. On a question asked of me only my answer, a vote or a Pass counts. */
    tookPart: qid => {
      const me = Core.state.me, pid = Core.me.cid;
      if (!me || !pid) return false;
      const answers = Core.answersFor(qid);
      const mine = Core.myRecord(qid);
      if ((mine && !mine.hidden) || answers.some(a => (a.votes || []).includes(pid))) return true;
      if (qid in (me.votes || {}) || qid in (me.backs || {}) || qid in (me.passes || {})) return true;
      if (Core.askedOf(qid).includes(pid)) return false;
      return Object.keys(me.reactions?.[qid] || {}).length > 0 || (Core.state.disagreements[qid] || []).some(d => d.cid === pid);
    },
    /** Who owns the answer: the owner sets the people a question is asked of ([] asks everyone). */
    setFor: (qid, pids) => act("/api/question/for", { qid, for: pids }),
    goWith: (qid, target) => act("/api/go-with", { qid, card: refOf(qid, target) }),
    lock: (qid, target) => act("/api/lock", { qid, ...(target ? { card: refOf(qid, target) } : {}) }).catch(e => {
      throw e?.error === "tie" ? { ...e, tied: (e.tied || []).map(cidOf) } : e;
    }),
    unlock: qid => act("/api/unlock", { qid }),
    suggest: (qid, text, note, extra) => act("/api/suggest", { qid, text, note: note || "", ...withAtt(extra) }),
    useSuggestion: (qid, id) => act("/api/suggestion/act", { qid, id, action: "use" }),
    dismissSuggestion: (qid, id) => act("/api/suggestion/act", { qid, id, action: "dismiss" }),
    lockEdit: (qid, text, from) => act("/api/lock/edit", { qid, text, ...(from ? { from } : {}) }),
    /** My message shows at once; the server's copy (a message of mine with this text it did not hold before) replaces it. */
    chat: (text, replyTo, extra) => {
      const before = new Set((withChat(snap)?.chat || []).map(m => m.id)), id = `sending-${++sends}`, body = { text, ...(replyTo ? { replyTo } : {}), ...withAtt(extra) };
      return act("/api/chat", body, { key: "chat:" + id, patch: (s, pid) => {
        s.chat ||= [];
        const chat = s.chat, text = body.text; // as act sent it: its mentions as tokens
        if (chat.some(m => m.pid === pid && m.text === text && !before.has(m.id))) return;
        const to = replyTo && chat.find(m => m.id === replyTo);
        chat.push({ id, pid, text, at: s.serverTime, ...(to ? { replyTo: { id: to.id, pid: to.pid, excerpt: to.text } } : {}), ...withAtt(extra) });
      } }).then(r => { chatTypingUntil = 0; return r; });
    },
    /** Inbox items I opened, by key: each reads at the status in `saw` (what the page showed), else at its status now. */
    readInbox: (keys, saw) => act("/api/inbox/read", { keys, ...(saw ? { saw } : {}) }, { key: "inbox:" + keys.join(","),
      patch: s => { for (const i of s.inbox || []) if (keys.includes(i.key) && (!saw || saw[i.key] === i.status)) i.unread = false; } }),
    readNotifications: ids => act("/api/notifications/read", ids === "all" ? { all: true } : { ids }),
    addReference: (qid, reference) => act("/api/question/reference", { qid, reference }),
    removeReference: (qid, index) => act("/api/question/reference", { qid, remove: index }),
    forward: id => act("/api/chat/propose", { id }, { ok: j => patchKept(id, m => { m.proposed = j.proposal; }) }),
    /** The Discussion under a question: add, edit or delete my comment, the owner's Hide, an emoji, and having read it up to `at`. */
    comment: (qid, text, extra) => act("/api/discussion", { qid, text, ...withAtt(extra) }),
    editComment: (qid, id, text) => act("/api/discussion/edit", { qid, id, text }),
    deleteComment: (qid, id) => act("/api/discussion/delete", { qid, id }, { key: "disc-del:" + id, patch: s => {
      if (s.discussions?.[qid]) s.discussions[qid] = s.discussions[qid].filter(c => c.id !== id);
    } }),
    hideComment: (qid, id, on) => act("/api/discussion/hide", { qid, id, on }),
    reactComment: (qid, id, emoji, on) => act("/api/discussion/react", { qid, id, emoji, on }, { key: `discreact:${id}:${emoji}`, patch: (s, pid) => {
      const c = (s.discussions?.[qid] || []).find(x => x.id === id);
      if (!c) return;
      c.reactions ||= {};
      const pids = without(c.reactions[emoji], pid);
      if (on) pids.push(pid);
      if (pids.length) c.reactions[emoji] = pids; else delete c.reactions[emoji];
    } }),
    readDiscussion: (qid, at) => act("/api/discussion/read", { qid, at }, { key: "discread:" + qid, patch: s => {
      if (s.me) s.me.discussionSeen = { ...s.me.discussionSeen, [qid]: Math.max(at, s.me.discussionSeen?.[qid] || 0) };
    } }),
    /** One of my emoji on a chat message, on or off (the server takes only its fixed set). */
    chatReact: (id, emoji, on) => {
      const react = (m, pid) => {
        m.reactions ||= {};
        const r = m.reactions, pids = without(r[emoji], pid);
        if (on) pids.push(pid);
        if (pids.length) r[emoji] = pids; else delete r[emoji];
        if (!Object.keys(r).length) delete m.reactions;
      };
      return act("/api/chat/react", { id, emoji, on }, { key: `chatreact:${id}:${emoji}`, patch: (s, pid) => {
        const m = (s.chat || []).find(x => x.id === id);
        if (m) react(m, pid);
      }, ok: () => patchKept(id, m => react(m, Core.me.cid)) });
    },
    /** Owner: hide an answer from everyone else and the digest (reversible), or replace its text. */
    hideCard: (qid, target, on, reason) => act("/api/card/hide", { qid, card: refOf(qid, target), on, ...(reason ? { reason } : {}) }),
    editCard: (qid, target, text) => act("/api/card/edit", { qid, card: refOf(qid, target), text }),
    /** Owner: one answer's earlier versions (oldest first), or a cleared answer's last text and versions. */
    cardHistory: async (qid, target) => {
      const r = await fetch(`/api/card/history?${new URLSearchParams({ qid, card: refOf(qid, target) })}`, { headers: ident() });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw { status: r.status, ...j };
      const nameOf = pid => (pid === "host" ? "Host" : Core.state.people[pid]?.name || "Someone");
      return { ...j, ...(j.text ? { text: Core.plain(j.text) } : {}), history: (j.history || []).map(v => ({ text: Core.plain(v.text), cid: v.by, name: nameOf(v.by), ts: v.at })) };
    },
    /** Report a problem: text, the page context (Core.reportContext) and at most one picture, a data: URL. */
    report: (text, ctx, image) => act("/api/report", { text, ctx, ...(image ? { image } : {}) }),
    /** Owner: mark a report seen or resolved; either tells the reporter. */
    /** Owner: seen | resolved tell the reporter; ask hands a report to Claude once (a report alone never reaches it). */
    reportAct: (id, action) => act("/api/report/act", { id, action }),
    /** The reporter: a line, a screenshot (a data: URL) or both added to their own report while it is not fixed. */
    addToReport: (id, text, image) => act("/api/report/add", { id, ...(text ? { text } : {}), ...(image ? { image } : {}) }),
    /** A received picture an answer, message, request, suggestion, proposal or comment I can see carries, as a data: URL. */
    uploadImage: async id => {
      const r = await fetch(`/api/upload/image?${new URLSearchParams({ id })}`, { headers: ident() });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw { status: r.status, ...j };
      return j.image;
    },
    /** Owner: one report's picture, or its Nth addition's, as a data: URL. */
    reportImage: async (id, add) => {
      const r = await fetch(`/api/report/image?${new URLSearchParams({ id, ...(add ? { add } : {}) })}`, { headers: ident() });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw { status: r.status, ...j };
      return j.image;
    },
    /** Owner: admit or decline one person waiting under Approve new joins. */
    joinAct: (pid, action) => act("/api/join/act", { pid, action }),
    /** Owner: "Why you're here" (empty removes it). */
    setIntro: intro => act("/api/session/intro", { intro }),
    setColor: color => act("/api/color", { color }),
    /** Follow-up 46: how comfortable I am with tech (low, ok, high) and an optional note; only the owner reads them. */
    setAboutYou: (techComfort, note) => act("/api/about-you", { techComfort, ...(note ? { note } : {}) }),
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
    /** runner "self": the request runs on my own Claude (Connect your Claude); only I see it. audience "me" (Just me):
     *  its answer shows to me and the host until one of us shares it. */
    request: (qid, kind, text, extra, runner, audience) => act("/api/request", { ...(qid === Core.GENERAL ? { scope: qid } : { qid }), kind, text,
      ...(runner === "self" ? { runner } : {}), ...(audience === "me" ? { audience } : {}), ...withAtt(extra) }),
    /** My own Just me answer, shared with everyone (the owner may share any). */
    shareResult: id => act("/api/result/share", { id }),
    /** My own Claude's side of a self request: claim it, post its answer ({summary, sources, report, used, why}), or give up. */
    myClaim: id => act("/api/mine/requests/claim", { id }),
    myResult: (id, body) => act("/api/mine/requests/result", { id, ...body }),
    myFail: (id, reason) => act("/api/mine/requests/fail", { id, reason }),
    /** A new watcher key for my own Claude (it replaces any earlier one); it reads and answers my own requests and
     *  nothing else. My session secret never leaves this page. Resolves to the key. */
    newWatcherKey: () => act("/api/watcher", {}).then(j => j.token),
    revokeWatcher: () => act("/api/watcher/revoke", {}),
    later: (id, reason) => act("/api/proposal/act", { id, action: "later", reason }),
    /** Owner: edit | decline | fail | rerun one request, publish | discard | takedown a result; runRequests runs the given ids still pending. */
    requestAct: (id, action, text) => (action === "run" ? Core.runRequests([id])
      : act("/api/request/act", { id, action, ...(text != null ? { text } : {}) })),
    /** The given ids still waiting show as running at once; a refusal puts them back. */
    runRequests: ids => act("/api/request/act", { action: "run", ids }, { key: "run:" + ids.join(), patch: s => {
      for (const r of [...(s.requests || []), ...(s.myRequests || [])]) {
        if (ids.includes(r.id) && r.status.kind === "pending") r.status = { kind: "running", since: s.serverTime };
      }
    } }),
    proposal: (id, action) => act("/api/proposal/act", { id, action }),
    setTitle: title => act("/api/session/title", { title }),
    merge: (from, to) => act("/api/person/merge", { from, to }),
    clearReview: qid => act("/api/review/clear", { qid }),
    markReady: on => act("/api/round/ready", { on }),
    cancelRound: () => act("/api/round/cancel", {}),
    /** Owner: a round stuck with Claude working goes back to open; Claude's late preparation is refused. */
    resetRound: () => act("/api/round/reset", {}),
    rename: name => act("/api/rename", { name }).then(j => { Core.me.name = j.name; put("name", j.name); emit(); return j; }),
    /** Owner: give another person a new name; resolves to {pid, name}, the name made unique as a self-rename is. */
    renamePerson: (pid, name) => act("/api/rename", { pid, name }),
    removePerson: (pid, on) => act("/api/person/remove", { pid, on }),
    newGuestLink: () => act("/api/link/guest", {}),
    /** Owner: a new owner token; this page reloads on the new owner link. */
    newOwnerLink: () => act("/api/link/owner", {}).then(j => { location.hash = "owner=" + j.token; location.reload(); return j; }),
    /** Owner, on the device that opened the owner link: a one-time code another device signs in with; {code, expiresIn}. */
    pairDevice: () => act("/api/owner/pair", {}),
    /** Owner: sign one device out; signing out this one makes this page a guest's. */
    revokeDevice: id => act("/api/owner/devices/revoke", { id }).then(j => { if (id === get("ownerDeviceId")) signedOut(); return j; }),
    /** This device is one the host signed in with a code, and its id. */
    ownerDevice: () => (ownerDevice ? get("ownerDeviceId") || "" : null),
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
    /** A guest's link that signs them in on another device. It carries their secret: keep it private. The host signs
     *  in elsewhere with a one-time code instead, so the owner link stays where it was opened. */
    personalLink: () => (secret && !ownerToken ? `${(Core.state.shareUrl || location.origin).replace(/\/$/, "")}/#me=${secret}` : ""),
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
  // A touch screen's short side, which a rotation leaves alone, tells a phone from a tablet: a phone in landscape is still a phone.
  const deviceKind = () => (matchMedia("(pointer: coarse)").matches ? (Math.min(screen.width, screen.height) < 600 ? "phone" : "tablet") : "computer");
  const browserKind = () => BROWSERS.find(([re]) => re.test(navigator.userAgent))?.[1] || "other";
  /** A question asked once per device (answerScope device) takes the device kind with each answer and pick. */
  const scopeOf = qid => (Core.state.questions.find(q => q.id === qid)?.answerScope === "device" ? { device: deviceKind() } : {});
  /** Follow-up 45: {app, open}, the social app whose built-in browser shows this page and the browser to open it in
   *  instead; null in any other browser. */
  Core.inApp = () => {
    const ua = navigator.userAgent;
    const app = /Instagram/.test(ua) ? "Instagram" : /Messenger|FB_IAB\/MESSENGER|FB_IAB\/Orca-Android|FBAN\/MessengerForiOS/i.test(ua) ? "Messenger" : /FBAN|FBAV|FB_IAB/.test(ua) ? "Facebook" : "";
    return app ? { app, open: /iPhone|iPad|iPod/.test(ua) ? "Safari" : "Chrome" } : null;
  };
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
    if (!ownerToken || ownerDevice || e.defaultPrevented || e.button !== (e.type === "auxclick" ? 1 : 0)) return;
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
      // the server makes a name unique ("Ivy 2"): the page says so, so nobody is renamed silently
      Core.renamedFrom = name && j.name && j.name !== name.trim() ? name.trim() : null;
      if (j.name) { Core.me.name = j.name; put("name", j.name); }
      Core.joinedAs = j.was || null; // someone offline already used this name
      return j;
    }).finally(() => { joining = null; });
  }

  // The server takes one write a second per person on each of these routes (session.py _throttle, WRITE_INTERVAL;
  // a chat reaction per message) and answers a faster one 429. Writes to one route go out one at a time, the next a
  // second after the last answer came back: the server stamps a write before it answers, so that gap is never shorter
  // than a second there. The limit is per person and this spacing per page, so a write the same person just made from
  // another tab or device can still refuse one: send() tries that once more a gap later.
  const SPACED = new Set(["/api/answer", "/api/pick", "/api/propose", "/api/chat", "/api/suggest", "/api/request", "/api/merge-request",
    "/api/annotate", "/api/rename", "/api/color", "/api/prefs", "/api/about-you", "/api/vote", "/api/react", "/api/disagree", "/api/pass",
    "/api/go-with", "/api/notifications/read", "/api/inbox/read", "/api/chat/react", "/api/mine/requests/claim", "/api/mine/requests/result", "/api/mine/requests/fail",
    "/api/upload/offer", "/api/upload/act", "/api/upload/chunk", "/api/discussion", "/api/discussion/edit", "/api/discussion/delete",
    "/api/discussion/hide", "/api/discussion/react", "/api/discussion/read", "/api/result/share"]);
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
        if (r.status === 429 && SPACED.has(path) && (await r.clone().json().catch(() => ({}))).error === "slow-down") { await wait(GAP); r = await go(); }
      } catch (e) {
        if (e instanceof TypeError) fault("api", e.message, { route: path, code: "network" });
        throw e;
      }
      // A refusal the server logged itself is kept here for a problem report only; an answer that is not the server's
      // (no X-Shared-Build: the tunnel's own error page) is a fault.
      if (!r.ok) r.clone().json().catch(() => ({})).then(j => {
        noteError("api", String(j.error || r.status), `HTTP ${r.status}: ${j.message || r.statusText}`);
        if (!r.headers.has("X-Shared-Build")) fault("api", `HTTP ${r.status}`, { route: path, code: "no-answer", noted: true });
      });
      return r;
    });
  }
  function forget() { secret = ""; drop("secret"); drop("pid"); Core.me.cid = ""; }
  /** Trade the host's one-time code for this device's own host credential, then reload as the host. */
  async function redeemPair(code) {
    const r = await fetch("/api/owner/pair/redeem", json({ code, device: deviceKind(), browser: browserKind() }));
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw { status: r.status, ...j };
    put("ownerDevice", j.token); put("ownerDeviceId", j.id); drop("signedOut");
    location.reload();
  }
  /** This device's host credential is gone: forget it, and the reloaded page asks to join, saying why. */
  function signedOut() { drop("ownerDevice"); drop("ownerDeviceId"); put("signedOut", "1"); location.reload(); }
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

  // ---------- telemetry: what this page records so the host can fix problems (README "Logs") ----------
  // Faults go to server.log under this person's pid the first time each fingerprint shows: script errors, unhandled
  // rejections, actions that never reached the server (send above; the server logs its own refusals), and layout
  // anomalies. Repeats, action timings and rollbacks, reconnect gaps, INP and LCP wait for one summary, sent with no
  // pid when the page hides. Only once joined: the server refuses an anonymous entry. Never typed text, answers, chat,
  // names, the address or its fragment, text on the page, or a credential. There is no switch: it always runs.
  const cut = (text, n) => Array.from(String(text)).slice(0, n).join(""); // by code point, as the server counts
  const recentErrors = []; // the last few this page saw, which a problem report carries
  const LAT_EDGES = [100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000]; // ms, upper bucket edges; share.py LAT_EDGES
  const SUMMARY_MAX = 500; // the server's message limit: what does not fit waits for the next summary
  const tel = {
    seen: new Set(), rep: new Map(), lat: new Map(), rb: new Map(), gaps: [], layout: new Set(),
    pv: [...crypto.getRandomValues(new Uint8Array(4))].map(b => b.toString(16).padStart(2, "0")).join(""), // this page view, no one's id
    inp: "", lcp: "", sentInp: "", sentLcp: "", missing: "", sentMissing: false, vitals: false,
  };
  const joined = () => !!(ownerToken || secret);
  const ua = () => `${browserKind()} ${deviceKind()}`;
  const bump = (m, k, n = 1) => m.set(k, (m.get(k) || 0) + n);
  const fnv = text => { let h = 0x811c9dc5; for (const c of text) h = Math.imul(h ^ c.codePointAt(0), 16777619) >>> 0; return h.toString(16).padStart(8, "0"); };
  function post(body) {
    if (!joined()) return Promise.reject(new Error("not sent"));
    return fetch("/api/client-log", { method: "POST", headers: { "Content-Type": "application/json", ...ident() }, body: JSON.stringify(body), keepalive: true })
      .then(r => { if (!r.ok) throw new Error(`HTTP ${r.status}`); });
  }
  function noteError(kind, code, message) {
    recentErrors.push(cut(`${kind}${code ? " " + code : ""}: ${message}`, 300));
    recentErrors.splice(0, recentErrors.length - 5);
  }
  /** A fault, sent the first time its fingerprint (`key`, else kind, message, source and an API route) shows; after
   *  that each repeat is a count in the next summary. One that did not arrive is sent again the next time. */
  function fault(kind, message, extra = {}, key = "") {
    const body = { kind, message: cut(message || kind, 500), route: cut(location.pathname, 200), ua: ua(), ...extra };
    if (kind !== "layout" && !extra.noted) noteError(kind, extra.code, body.message);
    delete body.noted;
    if (!joined()) return;
    const fp = fnv(key || [kind, body.message, body.source || "", kind === "api" ? body.route : ""].join("|"));
    if (tel.seen.has(fp)) { bump(tel.rep, fp); return; }
    tel.seen.add(fp);
    post({ ...body, fp }).catch(() => tel.seen.delete(fp));
  }
  /** An action's tap-to-answer time on its route, in LAT_EDGES buckets. */
  function timed(route, ms) {
    const b = tel.lat.get(route) || Array(LAT_EDGES.length + 1).fill(0), i = LAT_EDGES.findIndex(e => ms <= e);
    b[i < 0 ? LAT_EDGES.length : i]++;
    tel.lat.set(route, b);
  }
  /** One summary line of what waited, as `name=value` tokens; whatever does not fit in SUMMARY_MAX stays for the next. */
  function flush() {
    if (!joined()) return;
    const base = `pv=${tel.pv}${ownerToken ? " owner=1" : ""}`, items = [];
    const missing = tel.missing || (tel.vitals ? [!tel.hasInp && "inp=missing", !tel.hasLcp && "lcp=missing"].filter(Boolean).join(" ") : "");
    if (missing && !tel.sentMissing) items.push([missing, () => { tel.sentMissing = true; }]);
    if (tel.inp && tel.inp !== tel.sentInp) { const v = tel.inp; items.push([`inp=${v}`, () => { tel.sentInp = v; }]); }
    if (tel.lcp && tel.lcp !== tel.sentLcp) { const v = tel.lcp; items.push([`lcp=${v}`, () => { tel.sentLcp = v; }]); }
    if (tel.gaps.length) { const g = tel.gaps.splice(0); items.push([`gap=${g.join(",")}`, () => {}, () => tel.gaps.unshift(...g)]); }
    for (const [route, b] of tel.lat) { const n = b.findLastIndex(x => x > 0); items.push([`lat:${route}=${b.slice(0, n + 1).join(",")}`, () => tel.lat.delete(route)]); }
    for (const [route, n] of tel.rb) items.push([`rb:${route}=${n}`, () => tel.rb.delete(route)]);
    for (const [fp, n] of tel.rep) items.push([`rep:${fp}=${n}`, () => tel.rep.delete(fp)]);
    let message = base;
    for (const [t, sent, keep] of items) {
      if (message.length + 1 + t.length <= SUMMARY_MAX) { message += " " + t; sent(); } else keep?.();
    }
    if (message !== base) post({ kind: "summary", message, ua: ua() }).catch(() => {});
  }
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") flush(); });
  addEventListener("pagehide", flush);

  /** The component an element belongs to: its nearest vf- or core- class, never its text. */
  function componentOf(node) {
    for (let el = node?.nodeType === 1 ? node : node?.parentElement; el && el !== document.body; el = el.parentElement) {
      const c = [...el.classList].find(x => /^(?:vf|core)-[\w-]+$/.test(x));
      if (c) return c;
    }
    return node ? String(node.nodeName || "node").toLowerCase() : "none";
  }
  /** INP and LCP from the vendored web-vitals attribution build (web/web-vitals.attribution.iife.js), on this origin;
   *  a page without it, or without the browser APIs it reads, says which is missing. */
  function loadVitals() {
    if (tel.vitals || tel.loading) return;
    tel.loading = true;
    const s = document.createElement("script");
    s.src = "/web-vitals.attribution.iife.js";
    s.onload = () => {
      const wv = window.webVitals;
      if (!wv?.onINP) { tel.missing = "vitals=missing"; return; }
      tel.vitals = true;
      tel.hasInp = !!(window.PerformanceEventTiming && "interactionId" in PerformanceEventTiming.prototype);
      tel.hasLcp = !!window.PerformanceObserver?.supportedEntryTypes?.includes("largest-contentful-paint");
      // A target web-vitals did not get from componentOf (its INP targetSelector, its LCP `#id`) is sent as "-".
      const named = new Set(), target = el => { const c = componentOf(el); named.add(c); return c; };
      const only = t => named.has(t) ? t : "-";
      const opts = { generateTarget: target };
      wv.onINP(m => { tel.inp = `${Math.round(m.value)}:${m.attribution?.interactionType || "-"}:${only(m.attribution?.interactionTarget)}`; }, opts);
      wv.onLCP(m => { tel.lcp = `${Math.round(m.value)}:${only(m.attribution?.target)}`; }, opts);
    };
    s.onerror = () => { tel.missing = "vitals=missing"; s.remove(); };
    document.head.append(s);
  }

  // Layout anomalies, each logged when it appears: a page wider than the screen or a vertical pane that scrolls
  // sideways, a focused field outside what the keyboard leaves visible, the header pushed off screen.
  const FIELD = "input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]), textarea, select, [contenteditable=true]";
  function layoutNow() {
    const out = new Map(), vv = window.visualViewport, bandTop = vv ? vv.offsetTop : 0, bandBottom = bandTop + (vv ? vv.height : innerHeight);
    const kb = getComputedStyle(document.documentElement).getPropertyValue("--kb").trim() || "0px";
    const app = document.getElementById("app");
    for (const c of app ? [app, ...app.querySelectorAll("*")] : []) {
      if (c.closest("pre, table, textarea") || c.scrollWidth <= c.clientWidth + 1) continue;
      const cs = getComputedStyle(c);
      if (c !== app && !(/auto|scroll/.test(cs.overflowY) && /hidden|clip|auto/.test(cs.overflowX))) continue;
      const right = c.getBoundingClientRect().right;
      let widest = null, max = right + 1;
      for (const d of c.querySelectorAll("*")) { const r = d.getBoundingClientRect().right; if (r > max) { max = r; widest = d; } }
      const at = componentOf(c), el = widest ? componentOf(widest) : "-";
      out.set(`overflow|${at}|${el}`, `anomaly=overflow at=${at} el=${el} w=${c.clientWidth} sw=${c.scrollWidth} vw=${innerWidth}`);
    }
    const f = document.activeElement;
    if (f?.matches?.(FIELD)) {
      const r = f.getBoundingClientRect();
      if (r.height && (r.top >= bandBottom - 4 || r.bottom <= bandTop + 4)) {
        const at = componentOf(f);
        out.set(`field-hidden|${at}`, `anomaly=field-hidden at=${at} top=${Math.round(r.top)} bottom=${Math.round(r.bottom)} vvTop=${Math.round(bandTop)} vvH=${Math.round(bandBottom - bandTop)} kb=${kb}`);
      }
    }
    const h = app?.querySelector("header");
    if (h?.offsetParent) {
      const r = h.getBoundingClientRect();
      if (r.top < bandTop - 2 || r.bottom <= bandTop) out.set(`header-off|${componentOf(h)}`, `anomaly=header-off at=${componentOf(h)} top=${Math.round(r.top)} bottom=${Math.round(r.bottom)} vvTop=${Math.round(bandTop)} kb=${kb}`);
    }
    return out;
  }
  let layoutTimer = 0, layoutAt = -Infinity;
  function checkLayout() {
    layoutTimer = 0;
    // A finite animation still running (the chat button's bump, a sheet sliding in) is a passing frame, not the layout:
    // the bump scales the phone's chat button past the screen's edge. Check again once it has settled.
    if (document.getAnimations().some(a => a.playState === "running" && a.effect?.getTiming().iterations !== Infinity)) return layoutSoon();
    layoutAt = performance.now();
    if (!joined()) return;
    const now = layoutNow();
    for (const [key, message] of now) if (!tel.layout.has(key)) fault("layout", message, {}, key);
    tel.layout = new Set(now.keys());
  }
  /** Check the layout soon after a change (a new snapshot, a tap, a resize, the keyboard, a focused field): 800 ms
   *  after it, at most every 2 s. */
  function layoutSoon() {
    if (!layoutTimer) layoutTimer = setTimeout(checkLayout, Math.max(800, layoutAt + 2000 - performance.now()));
  }
  for (const ev of ["resize", "orientationchange", "core-viewport"]) addEventListener(ev, layoutSoon);
  document.addEventListener("focusin", layoutSoon);
  document.addEventListener("click", layoutSoon, true);

  /** What a problem report says about this page: the view and tab, question, round, device, browser, viewport, build
   *  and the last five errors this page saw, never an answer, chat, the address or its fragment, or a credential. */
  Core.reportContext = () => {
    const c = Core.context?.() || {}, w = where(), v = window.visualViewport, n = x => Math.round(x * 100) / 100;
    return { view: w.view, ...(c.tab ? { tab: c.tab } : {}), ...(c.qid ? { qid: c.qid } : {}), ...(c.round != null ? { round: c.round } : {}),
      device: w.deviceInfo.kind, browser: w.deviceInfo.browser, viewport: w.deviceInfo.screen,
      ...(v ? { visualViewport: { w: n(v.width), h: n(v.height), scale: n(v.scale) } } : {}), ...(build ? { build } : {}), errors: [...recentErrors] };
  };
  /** A layout readout (kind layout) as one `name=value` line: numbers and CSS values only, never text anyone wrote. */
  Core.reportLayout = fields => post({ kind: "layout", message: cut(Object.entries(fields).map(([k, v]) => `${k}=${String(v).replace(/\s+/g, "")}`).join(" "), 500),
    route: cut(location.pathname, 200), ua: ua() }).catch(() => {});
  addEventListener("error", e => fault("error", e.message, e.filename ? { source: cut(`${new URL(e.filename, location.href).pathname}:${e.lineno}`, 200) } : {}));
  // A server refusal ({status, error, message}) sends its code and status only: its message can quote typed text.
  addEventListener("unhandledrejection", e => { const r = e.reason;
    fault("rejection", r && !(r instanceof Error) && r.error ? `${r.error} ${r.status ?? ""}`.trim() : r?.message || String(r)); });

  // The notice in Help: one line and a "What this page records" link to the plain list.
  const REC_LINE = "This page records errors, slow or failed actions and layout problems on this device, so the host can fix them. It never records what you type.";
  const RECORDED = ["Script errors on this page, and actions that never reached the host", "How long each action takes to get an answer, and how often one is undone",
    "How long the page takes to catch up when you come back to it", "Layout problems: something too wide for the screen, a field the keyboard covers, the header pushed off screen",
    "How fast the page answers a tap and shows its main content", "Your device type and browser family, such as phone and Safari"];
  const NEVER = ["What you type: your answers, chat and requests", "Your name, or this page's address", "Any text shown on the page"];
  const REC_IDS = "Errors are filed under your session id, so the host can match them to what happened; timings and counts carry no id. It all stays on the host's computer.";
  function openRecords() {
    const dlg = Core.el("dialog", "core-records"), h = Core.el("h2", null, "What this page records");
    h.id = "core-records-h"; dlg.setAttribute("aria-labelledby", h.id);
    const list = (title, items) => { const ul = Core.el("ul"); for (const t of items) ul.append(Core.el("li", null, t)); return [Core.el("h3", null, title), ul]; };
    const close = Core.el("button", null, "Close"); close.type = "button";
    close.onclick = () => dlg.close();
    dlg.append(h, ...list("Recorded", RECORDED), ...list("Never recorded", NEVER), Core.el("p", "core-note", REC_IDS), close);
    dlg.addEventListener("close", () => dlg.remove());
    document.body.append(dlg);
    dlg.showModal();
    close.focus();
    return dlg;
  }
  /** The notice line with its link; `cls` styles it where it sits. */
  function notice(cls = "core-rec") {
    const box = Core.el("div", cls), p = Core.el("p", "core-rec-line", REC_LINE + " "), a = Core.el("a", "core-rec-link", "What this page records");
    a.href = "#records";
    a.addEventListener("click", e => { e.preventDefault(); openRecords(); });
    p.append(a);
    box.append(p);
    return box;
  }
  Core.telemetry = { notice, openRecords };
  loadVitals();

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
  const view = () => toView(withPending(withChat(snap)));
  const repaint = () => { if (snap) { Core.state = view(); emit(); } };
  // The routes whose text can mention people: their "@Name" go out as <@pid> (Core.tokenize); the server does the same
  // for full names, so a name the page shows masked still reaches the person it names.
  const MENTION_ROUTES = new Set(["/api/answer", "/api/pick", "/api/card/edit", "/api/suggest", "/api/lock/edit", "/api/propose", "/api/chat", "/api/annotate", "/api/request", "/api/request/act",
    "/api/discussion", "/api/discussion/edit"]);
  function act(path, body, opt) {
    if (MENTION_ROUTES.has(path)) for (const k of ["text", "comment", "other", "note"]) if (typeof body[k] === "string") body[k] = Core.tokenize(body[k]);
    const entry = opt?.patch && { patch: opt.patch, after: null }, t0 = performance.now();
    const mine = () => !!entry && pending.get(opt.key) === entry;
    const drop = () => { if (mine()) { pending.delete(opt.key); repaint(); bump(tel.rb, path); } }; // a rollback
    if (entry) { pending.delete(opt.key); pending.set(opt.key, entry); repaint(); }
    return send(path, body).then(async r => {
      if (r.headers.has("X-Shared-Build")) timed(path, performance.now() - t0);
      const j = await r.json().catch(() => ({}));
      if (!r.ok) { drop(); throw { status: r.status, ...j }; }
      if (mine()) entry.after = polls;
      opt?.ok?.(j);
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

  // ---------- chat beyond the snapshot's window: the snapshot carries the newest 50, GET /api/chat the rest ----------
  // Every message this page has read stays while it is open, so one that leaves the window stays under a reader
  // scrolled up to it. `linked` holds the ids whose next older message is loaded too (or that have none); a message
  // outside it shows a Load earlier control above it. A change of name masking or role starts over.
  const held = { chat: new Map(), linked: new Set(), key: "", touched: 0, files: {} }; // files: what held older messages carry
  const seqOf = id => Number(String(id).replace(/\D+/g, "")) || 0;
  function keepChat(run, before, below) {
    run.forEach((m, i) => { held.chat.set(m.id, m); if (i || !before) held.linked.add(m.id); });
    if (below) held.linked.add(below);
  }
  async function chatPage(query) {
    const r = await fetch(`/api/chat?${new URLSearchParams(query)}`, { headers: ident() });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw { status: r.status, ...j };
    Object.assign(held.files, j.files || {});
    return j;
  }
  /** held.files keeps only what the held messages still carry (a removed upload leaves them when they are read again). */
  function pruneFiles() {
    const carried = new Set([...held.chat.values()].flatMap(m => m.attachments || []));
    for (const id of Object.keys(held.files)) if (!carried.has(id)) delete held.files[id];
  }
  function keepWindow(s) {
    const key = `${s.settings?.names}|${s.me.role}`;
    if (key !== held.key) { held.chat.clear(); held.linked.clear(); held.files = {}; held.key = key; }
    const win = s.chat || [], skipped = !!s.chatBefore && win.length > 0 && held.chat.size > 0 && !held.chat.has(win[0].id);
    const touched = (s.chatTouched || 0) !== held.touched && held.chat.size > win.length;
    held.touched = s.chatTouched || 0;
    keepChat(win, s.chatBefore);
    if (skipped) fillChat(win[0].id).catch(() => {});
    else if (touched && win.length) refreshChat(win[0].id).catch(() => {});
  }
  /** Someone reacted to or forwarded a message older than the window: read the held ones again, back to the oldest. */
  async function refreshChat(id) {
    const oldest = Math.min(...[...held.chat.keys()].map(seqOf));
    for (let n = 0; n < 20 && id; n++) {
      const j = await chatPage({ before: id, limit: 100 });
      for (const m of j.chat) if (held.chat.has(m.id)) held.chat.set(m.id, m);
      id = j.chat.length && seqOf(j.chat[0].id) > oldest ? j.before : "";
    }
    pruneFiles();
    repaint();
  }
  /** More than a window arrived between two polls: read back to the messages this page already holds. */
  async function fillChat(id) {
    for (let n = 0; n < 20 && id; n++) {
      const j = await chatPage({ before: id, limit: 100 }), joined = j.chat.some(m => held.chat.has(m.id));
      keepChat(j.chat, j.before, id);
      id = joined ? "" : j.before;
    }
    repaint();
  }
  /** The snapshot with every message this page holds, oldest first, from people still in. */
  function withChat(s) {
    if (!s?.me || !held.chat.size) return s;
    const live = new Set((s.people || []).map(p => p.pid)), win = new Map((s.chat || []).map(m => [m.id, m]));
    const all = [...[...held.chat.values()].filter(m => !win.has(m.id) && live.has(m.pid)), ...win.values()];
    all.sort((a, b) => a.at - b.at || seqOf(a.id) - seqOf(b.id));
    return { ...s, chat: all.map(m => (held.chat.has(m.id) && !held.linked.has(m.id) ? { ...m, gapAbove: true } : m)) };
  }
  /** Read the messages just older than message `id`; resolves how many came. */
  Core.chatEarlier = async id => {
    const j = await chatPage({ before: id });
    keepChat(j.chat, j.before, id);
    repaint();
    return j.chat.length;
  };
  /** Make sure message `id` is loaded (a notification or a reply can point outside the window); resolves whether it is. */
  Core.chatAround = async id => {
    if (!held.chat.has(id)) {
      const j = await chatPage({ around: id }).catch(e => { if (e?.status === 404) return { chat: [] }; throw e; });
      keepChat(j.chat, j.before);
      repaint();
    }
    return held.chat.has(id);
  };
  /** An action on a message outside the window: its copy here takes the change, as no snapshot will carry it. */
  function patchKept(id, fn) {
    const m = held.chat.get(id);
    if (m && !(snap?.chat || []).some(x => x.id === id)) { const c = structuredClone(m); fn(c); held.chat.set(id, c); }
  }

  /** The state poll always carries ?since=<rev>: in a session imported from the prototype a poll with
   *  identity and no query is an old page, which gets only a reload notice. */
  // A poll asked for while one runs runs once more after it, so an action's poll always starts after its answer.
  let polling = null, pollNext = null;
  let waitPolled = 0;
  function poll() {
    // waiting to be let in, the page asks every 5 s, not every 1.5 s: each ask is a 403 the console logs (sweep S31)
    if (Core.state.youWaiting && !polling) { if (Date.now() - waitPolled < 5000) return Promise.resolve(); waitPolled = Date.now(); }
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
  /** A poll the server answered; the first after the page shows again ends a reconnect gap (performance.now). */
  function good() {
    lastOk = Date.now();
    if (shownAt != null) { tel.gaps.push(Math.round(performance.now() - shownAt)); tel.gaps.splice(0, tel.gaps.length - 20); shownAt = null; }
  }
  async function pollOnce() {
    const seq = ++polls;
    try {
      const headers = { ...ident(), ...(etag ? { "If-None-Match": etag } : {}) };
      const r = await fetch(`/api/state?since=${rev}`, { headers });
      if (r.status === 304) { good(); if (settle(seq) && snap) Core.state = view(); return; }
      const s = await r.json().catch(() => ({}));
      if (r.status === 403 && s.error === "removed") { Core.state = { ...Core.state, youRemoved: true, youWaiting: false }; good(); return; }
      // Approve new joins: the person waits until the owner lets them in; the poll keeps asking.
      if (r.status === 403 && s.error === "waiting") { Core.state = { ...structuredClone(DEFAULTS), title: s.title ?? Core.state.title, intro: s.intro || "", youWaiting: true }; good(); return; }
      if (r.status === 401 && !ownerToken && s.error === "merged-into-owner") { etag = ""; markMerged(); return; }
      if (r.status === 401 && !ownerToken) { forget(); etag = ""; askName(errorText(s)); return; }
      if (r.status === 401 && ownerDevice) return signedOut();
      if (!r.ok) return;
      if (s.build) { if (build && s.build !== build) return reload("build"); build = s.build; }
      etag = r.headers.get("ETag") || "";
      good();
      // Only presence or the clock moved: the rest of my last snapshot still holds.
      if (s.presenceOnly) {
        if (!snap) { etag = ""; return; }
        snap = { ...snap, serverTime: s.serverTime, presence: s.presence, lastSeen: s.lastSeen };
        settle(seq);
        Core.state = view();
        return;
      }
      if (!s.me) { // anonymous: only what the join dialog needs
        Core.state = { ...structuredClone(DEFAULTS), title: s.title || "", ended: !!s.ended, joinNeedsKey: !!s.joinNeedsKey, youMerged: merged };
        return;
      }
      snap = s; rev = s.rev;
      layoutSoon();
      if (merged) { merged = false; drop("merged"); } // a working identity again (a personal link of someone else)
      keepWindow(s);
      settle(seq);
      Core.state = view();
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
    // a person still waiting to be let in has no presence to send: the server refuses it (403) every beat (sweep S31)
    if (HB.busy || HB.timer || !HB.wanted || (!ownerToken && !secret) || Core.state.youWaiting) return;
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
  // iOS freezes a background tab's timers: catch up at once when the page shows again (triage 24). The time from
  // showing again to the first good poll is the reconnect gap.
  let hidden = !visibleNow();
  const catchUp = e => {
    if (!visibleNow()) { hidden = true; return; }
    if (hidden || e?.persisted) { shownAt ??= performance.now(); hidden = false; }
    poll();
  };
  document.addEventListener("visibilitychange", catchUp);
  window.addEventListener("pageshow", catchUp);
  document.addEventListener("resume", catchUp); // Page Lifecycle: a frozen tab thawed (Chrome on Android)
  window.addEventListener("focus", catchUp);

  /** Ask before a personal link replaces this browser's own secret: Keep (the default, and Escape) leaves it; Switch
   *  stores the link's secret and reloads as that person. */
  function askSwitch(other) {
    const dlg = Core.el("dialog", "core-switch"), h = Core.el("h2", null, "This link signs you in as someone else on this device. Switch?");
    h.id = "core-switch-h"; dlg.setAttribute("aria-labelledby", h.id); dlg.setAttribute("role", "alertdialog");
    const row = Core.el("div", "core-row"), keep = Core.el("button", null, "Keep"), change = Core.el("button", "core-btn-quiet", "Switch");
    keep.type = change.type = "button";
    keep.onclick = () => dlg.close();
    change.onclick = () => { put("secret", other); drop("pid"); drop("name"); Core.switching = true; location.reload(); };
    row.append(change, keep);
    dlg.append(h, row);
    dlg.addEventListener("close", () => dlg.remove());
    document.body.append(dlg);
    dlg.showModal();
    keep.focus();
  }

  // Name prompt. It stays open until the join succeeds; Escape does not close it. `codeErr`, when given, opens it on
  // the host's code entry with that error.
  function askName(notice = "", codeErr = null) {
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
    input.setAttribute("aria-describedby", "core-n-err");
    const err = Core.el("p", "core-err", notice); err.id = "core-n-err"; err.setAttribute("role", "alert");
    const go = Core.el("button", null, "Join");
    const host = Core.el("a", "core-host-code", "Are you the host? Sign in with a code"); host.href = "#";
    host.onclick = e => { e.preventDefault(); askCode(""); };
    form.append(h, sub, label, input, err, go, host); dlg.append(form);
    document.body.append(dlg);
    if (Core.state.joinNeedsKey && !joinKey) err.textContent = "This session needs the host's newest invite link. Ask them for it.";
    dlg.addEventListener("cancel", e => e.preventDefault());
    // Tab cycles inside the dialog instead of leaving for the browser's own toolbar.
    dlg.addEventListener("keydown", e => {
      if (e.key !== "Tab") return;
      const f = [...dlg.querySelectorAll("input, button, a[href]")].filter(x => !x.disabled), i = f.indexOf(document.activeElement);
      if (!f.length) return;
      e.preventDefault();
      f[(i + (e.shiftKey ? -1 : 1) + f.length) % f.length].focus();
    });
    const done = () => { unsub(); dlg.close(); dlg.remove(); beat(); poll(); };
    /** The host's code entry: the code from "Sign in on another device" signs this device in as the host. */
    function askCode(msg) {
      const f = Core.el("form"), h2 = Core.el("h2", null, "Sign in as the host"); h2.id = "core-name-h";
      const p = Core.el("p", "core-note", "On the device where you opened your owner link, open your menu and choose Sign in on another device. Type the code it shows.");
      const l = Core.el("label", null, "Code"); l.htmlFor = "core-code";
      const code = Core.el("input"); Object.assign(code, { id: "core-code", required: true, maxLength: 12, autocomplete: "one-time-code", autocapitalize: "characters", spellcheck: false });
      const e2 = Core.el("p", "core-err", msg); e2.id = "core-code-err"; e2.setAttribute("role", "alert"); code.setAttribute("aria-describedby", e2.id);
      const row = Core.el("div", "core-row"), back = Core.el("button", "core-btn-quiet", "Back"), ok = Core.el("button", null, "Sign in");
      back.type = "button"; back.onclick = () => { f.replaceWith(form); input.focus(); };
      row.append(back, ok); f.append(h2, p, l, code, e2, row);
      f.addEventListener("submit", ev => {
        ev.preventDefault();
        ok.disabled = true; ok.textContent = "Signing in…"; e2.textContent = "";
        redeemPair(code.value.trim()).catch(x => { e2.textContent = errorText(x); ok.disabled = false; ok.textContent = "Sign in"; code.focus(); });
      });
      form.replaceWith(f);
      code.focus();
    }
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
    if (codeErr != null) askCode(codeErr);
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
    const wasSignedOut = get("signedOut") === "1";
    drop("signedOut");
    if (pairCode && (!ownerToken || ownerDevice)) { // a device signed in before takes the new code, replacing its own
      redeemPair(pairCode).catch(x => { askName("", errorText(x)); if (secret) beat(); });
    } else if (!ownerToken && secret && (adopt || !Core.me.name || !Core.me.cid)) {
      adoptIdentity().then(beat).catch(status => {
        if (status !== 401) return; // removed: the state poll shows it, and the owner can restore the same secret
        forget(); drop("name"); Core.me.name = "";
        askName(adopt ? "That personal link no longer works. Join with your name; the host can merge you with your earlier self." : "");
      });
    } else if (!ownerToken && !secret && !merged) askName(wasSignedOut ? "This device was signed out as the host. Join as a guest, or sign in again with a new code." : "");
    else beat();
    if (switchTo) askSwitch(switchTo);
    poll();
    setInterval(poll, 1500); setInterval(beat, 2000);
  });
})();
