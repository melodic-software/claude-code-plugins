// The browser half of question-shape knowledge that both interview pages share, served by both servers (the shared
// page's server.py and the 1:1 page's surface/server.py): the id of a person's own option, the markdown both pages
// render, the composer kit every text box people write in uses, and the fit to the visual viewport that keeps an
// on-screen keyboard off the field being typed in. One classic script, one global: QuestionShape.
(() => {
  /** The option id of a person's own "Something else…" option (shared/session.py OTHER_OPTION). */
  const OTHER = "other";
  const MOD_KEY = /Mac|iPhone|iPad/.test(navigator.platform) ? "Cmd" : "Ctrl";
  /** The send key's hint for a multi-line field, as the composer shows it. */
  const keyHint = verb => `${MOD_KEY} + Enter to ${verb}`;
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
  const listen = (t, ev, fn, opt) => t.addEventListener(ev, fn, opt);
  const memory = () => { const m = {}; return { get: k => m[k], set: (k, v) => { if (v) m[k] = v; else delete m[k]; } }; };

  // ---------- safe markdown: the one dialect both pages render, built from elements and text nodes only ----------
  // Blocks: paragraphs (a blank line ends one, a line break stays one), "#" headings, "- " and "1." lists and "> "
  // quotes. Inline: `code`, **bold**, *emphasis*, [text](url) and bare http(s) links, owner/repo#N, and, when the
  // session names a repository, #N and repo-relative paths (a path links only with a commit too). A page passes:
  //   repo()         {repo, commit} the session names, either one empty or absent when it names none;
  //   text(p, s)     how it appends a plain run s to p (mentions, question ids), else as text;
  //   heading        the level of a "#" heading (## one lower, down to h6), else every heading is a bold line.
  const REPO = /^[A-Za-z0-9][A-Za-z0-9-]{0,38}\/(?!\.\.?$)[A-Za-z0-9._-]{1,100}$/, SHA = /^[0-9a-f]{40}$/;
  // *emphasis* opens only after a space, an opening bracket or a quote and hugs its text, so *.js and a URL's *x* stay text
  const SPAN = /(`[^`\n]+`|\*\*[^*\n]+?\*\*|(?<![^\s(\["'])\*[^*\s](?:[^*\n]*?[^*\s])?\*(?![*\w]))/;
  const LINK = /\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)|\bhttps?:\/\/[^\s<>"']+/g;
  /** owner/repo#N; `#N` not inside a word, an entity or a path; or a repo-relative path: a dot-free first folder of 2
   *  or more characters (a leading dot allowed, so never a host name or "w/e.g"), at least one slash and a file with
   *  a lowercase letter-led extension, optionally `:line` or `:line-line`. The repo rule is also in session.py.
   *  Never after a slash, dot, colon, ~ or @, so an absolute, home, drive or relative-to-parent path stays text. */
  const REF = /(?<![\w./:@~\\#-])([\w.-]+\/[\w.-]+)#([1-9]\d{0,6})(?![\w-])|(?<![\w&#/])#([1-9]\d{0,6})(?![\w-])|(?<![\w./:@~\\-])(\.?[\w-]{2,}(?:\/\.?[\w-][\w.-]*)*\/\.?[\w-][\w.-]*\.[a-z][a-z0-9]{0,9})(?::([1-9]\d{0,6})(?:-([1-9]\d{0,6}))?)?(?![\w/-]|\.\w)/g;
  function link(text, url) { const a = el("a", "vf-link", text); a.href = url; a.target = "_blank"; a.rel = "noopener noreferrer"; return a; }
  const web = url => { try { return ["http:", "https:"].includes(new URL(url).protocol); } catch { return false; } };
  /** One line's inline markdown appended to parent; bold and emphasis hold the rest of the dialect. */
  function inline(parent, line, o = {}) {
    String(line ?? "").split(SPAN).forEach((part, i) => {
      if (!part) return;
      if (!(i % 2)) links(parent, part, o);
      else if (part[0] === "`") parent.append(el("code", "vf-code", part.slice(1, -1)));
      else { const bold = part[1] === "*", e = el(bold ? "strong" : "em"); inline(e, bold ? part.slice(2, -2) : part.slice(1, -1), o); parent.append(e); }
    });
  }
  function links(parent, s, o) {
    let i = 0;
    for (const m of s.matchAll(LINK)) {
      const url = m[1] ? m[2] : m[0].replace(/[).,;:!?]+$/, "");
      if (m.index > i) refs(parent, s.slice(i, m.index), o);
      parent.append(web(url) ? link(m[1] ?? url, url) : m[1] ? m[0] : url);
      i = m.index + (m[1] ? m[0].length : url.length);
    }
    if (i < s.length) refs(parent, s.slice(i), o);
  }
  function refs(parent, s, o) {
    const plain = o.text || ((p, t) => p.append(t));
    if (!s.includes("#") && !s.includes("/")) { plain(parent, s); return; }
    const at = o.repo?.(), repo = at && REPO.test(at.repo) ? at.repo : "", commit = repo && SHA.test(at.commit) ? at.commit : "";
    let i = 0;
    for (const m of s.matchAll(REF)) {
      const url = m[1] ? `https://github.com/${m[1]}/issues/${m[2]}`
        : m[3] ? repo && `https://github.com/${repo}/issues/${m[3]}`
        : commit && `https://github.com/${repo}/blob/${commit}/${m[4]}${m[5] ? `#L${m[5]}${m[6] ? `-L${m[6]}` : ""}` : ""}`;
      if (!url) continue;
      if (m.index > i) plain(parent, s.slice(i, m.index));
      parent.append(link(m[0], url));
      i = m.index + m[0].length;
    }
    if (i < s.length) plain(parent, s.slice(i));
  }
  /** Text as markdown, a fragment of paragraphs, headings, lists and quotes. */
  function markdown(text, o = {}) {
    const f = document.createDocumentFragment();
    for (const block of String(text ?? "").replace(/\r/g, "").split(/\n\s*\n/)) {
      let p = null, list = null, quote = null, qp = null;
      for (const raw of block.split("\n")) {
        const h = raw.match(/^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/), q = raw.match(/^\s{0,3}>\s?(.*)$/), m = raw.match(/^\s*(?:[-*•]|(\d{1,9})[.)])\s+(.*)$/);
        if (h) {
          p = list = quote = null;
          const hd = o.heading ? el("h" + Math.min(6, o.heading + h[1].length - 1)) : el("p", "vf-mdh");
          inline(hd, h[2], o); f.append(hd);
        } else if (q) {
          p = list = null;
          if (!quote) { quote = el("blockquote"); f.append(quote); qp = null; }
          if (!q[1].trim()) qp = null; // an empty quote line starts the quote's next paragraph
          else { if (qp) qp.append(el("br")); else quote.append(qp = el("p")); inline(qp, q[1].trim(), o); }
        } else if (m) {
          p = quote = null;
          const tag = m[1] ? "ol" : "ul";
          if (list?.tagName.toLowerCase() !== tag) { list = el(tag, "vf-" + tag); f.append(list); }
          const li = el("li"); inline(li, m[2], o); list.append(li);
        } else if (raw.trim()) {
          list = quote = null;
          if (p) p.append(el("br")); else f.append(p = el("p"));
          inline(p, raw.trim(), o);
        }
      }
    }
    return f;
  }

  // ---------- the composer kit: one rule set for every field people write in ----------
  // send: Enter in a one-line field, Ctrl or Cmd + Enter in a multi-line one, with its hint shown beside it. Shift or
  // Alt + Enter never sends, and neither does a key an input method is composing with (isComposing, or keyCode 229,
  // which also marks the keys that open and close a composition: https://developer.mozilla.org/en-US/docs/Web/API/Element/keydown_event).
  // The counter (one class) shows from counterFrom, by default the last quarter of the field's maxLength. Escape runs
  // escape. mentions opens the page's @ picker; "claude" offers Claude first. draftKey() names whose unsent text the
  // field holds now (a question's): each key keeps its own in the page's draft store.
  /** One page's kit. Its host gives:
   *  pane(t)        the element whose height bounds textarea t: it grows with its text up to 40% of it, then scrolls;
   *  grew(t)        what the page does once t has grown (keep it in view while typing);
   *  drafts         {get(key), set(key, text)}, the unsent text per draftKey (an empty text drops the key);
   *  mentionOn(f)   true while the page's @ list is open on f, and closeMention() to close it;
   *  on(t, ev, fn, opt) how the page adds a listener it can take off again. */
  function kit({ pane, grew = () => {}, drafts = memory(), mentionOn = () => false, closeMention = () => {}, on = listen }) {
    const KIT = new WeakMap(), KITS = new Set();
    let booted = false; // fields made after start-up (list rows) paint their counter on input only
    // a field scrolls itself into view only while the person types in it, never on a render
    const TYPED = { el: null, at: 0 };
    const typing = f => !!f && TYPED.el === f && performance.now() - TYPED.at < 1000;

    function grow(t) {
      const max = Math.max(80, pane(t).clientHeight * 0.4);
      t.style.blockSize = "auto";
      const h = t.scrollHeight + 2;
      t.style.blockSize = Math.min(h, max) + "px";
      t.style.overflowY = h > max ? "auto" : "hidden";
      grew(t);
    }
    // cut: false leaves the field without a maxLength (and so without a counter), for text whose send checks its length.
    function composer(f, { send, counterFrom, escape, mentions, draftKey, verb = "send", cut = true } = {}) {
      if (cut && !(f.maxLength > 0)) f.maxLength = 2000;
      const oneLine = f.tagName === "INPUT" || f.rows === 1;
      const k = { f, send, escape, mentions, draftKey, oneLine, from: cut ? counterFrom ?? Math.ceil(f.maxLength * 0.75) : Infinity, key: null };
      k.count = el("span", "vf-count-txt"); k.count.setAttribute("aria-live", "polite");
      k.hint = send && !oneLine ? el("span", "vf-hint vf-keyhint", keyHint(verb)) : null;
      if (mentions) for (const [a, v] of [["aria-autocomplete", "list"], ["aria-haspopup", "listbox"], ["aria-expanded", "false"]]) f.setAttribute(a, v);
      KIT.set(f, k);
      if (!booted) KITS.add(k);
      return k;
    }
    function paint(k) {
      const n = k.f.value.length, t = n >= k.from ? `${n} / ${k.f.maxLength}` : "";
      if (k.count.textContent !== t) k.count.textContent = t;
    }
    /** Each keyed field keeps what was typed under its last key and shows what its key holds now. */
    function swap() {
      for (const k of KITS) {
        // a list row made before start-up leaves the set once its row is gone
        if (!k.draftKey) { if (k.f.isConnected) { k.seen = true; paint(k); } else if (k.seen) KITS.delete(k); continue; }
        const key = k.draftKey();
        if (key !== k.key) {
          if (k.key !== null) drafts.set(k.key, k.f.value);
          k.key = key; k.f.value = drafts.get(key) ?? "";
          if (k.f.tagName === "TEXTAREA") grow(k.f);
        }
        paint(k);
      }
    }
    /** Every shown keyed field's unsent text into the draft store. */
    function store() { for (const k of KITS) if (k.key !== null) drafts.set(k.key, k.f.value); }
    /** Clear a keyed field's text for a key it sent, shown or not. */
    function sent(f, key) {
      const k = KIT.get(f); drafts.set(key, "");
      if (k && k.key === key) { f.value = ""; if (f.tagName === "TEXTAREA") grow(f); paint(k); }
    }
    on(document, "input", e => {
      TYPED.el = e.target; TYPED.at = performance.now();
      const k = KIT.get(e.target); if (k) paint(k);
    }, true);
    // Runs first; an open @ list keeps its own keys (Enter and Tab pick, Escape closes it), and Ctrl or Cmd + Enter
    // closes it and sends. A send or an escape it runs is the field's: the page's own key handlers see it prevented.
    on(document, "keydown", e => {
      const k = KIT.get(e.target);
      if (!k || e.isComposing || e.keyCode === 229) return;
      const send = e.key === "Enter" && k.send && !e.shiftKey && !e.altKey;
      if (mentionOn(e.target)) { if (send && (e.ctrlKey || e.metaKey)) { e.preventDefault(); closeMention(); k.send(); } return; }
      if (send && (k.oneLine || e.ctrlKey || e.metaKey)) { e.preventDefault(); k.send(); }
      else if (e.key === "Escape" && k.escape) { e.preventDefault(); e.stopPropagation(); k.escape(); }
    }, true);
    return { composer, grow, typing, paint, swap, store, sent, get: f => KIT.get(f), fields: KITS, boot: () => { booted = true; } };
  }

  // ---------- the visual viewport ----------
  // Pin the page to the visual viewport: an on-screen keyboard (iOS ignores interactive-widget) shrinks the page from
  // the bottom instead of covering the focused field, and the page never pans. --vv-top and --vv-h are the visual
  // viewport's offset and height; a page sizes its root from them. --kb is the keyboard's height: what it takes from
  // the layout viewport, whose innerHeight a keyboard leaves alone while it shrinks the visual viewport
  // (https://developer.mozilla.org/en-US/docs/Web/API/VisualViewport). The pan iOS adds to reveal the field moves
  // offsetTop, not the height, so it never counts against the keyboard. Pinch-zoomed, WebKit shrinks innerWidth and
  // innerHeight with the visual viewport (https://bugs.webkit.org/show_bug.cgi?id=174362) where Chromium keeps them,
  // but in both the full height for the visual viewport's width is vv.width * innerHeight / innerWidth; what the
  // keyboard takes of it, times scale, is its height on screen, and a zoom alone takes nothing. A keyboard taller than
  // 80px sets data-kb on the root element. Fires "core-viewport" on window once the page is refitted.
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
  vv?.addEventListener("resize", refit);
  vv?.addEventListener("scroll", refit);
  fitViewport();

  window.QuestionShape = { OTHER, MOD_KEY, keyHint, markdown, inline, kit, fitViewport };
})();
