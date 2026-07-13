// Chrome extraction — exposes posts / replies / selector-probe templates + URL/JS builders
// for the main CC session to drive chrome-in-chrome MCP directly.
//
// Architecture (Option A): the main interactive Claude Code session executes
// chrome MCP calls (browser_batch + javascript_tool). Plugin-defined MCP servers
// (claude-in-chrome) are NOT loaded by `claude -p` subprocesses per
// code.claude.com/docs/en/mcp-servers#plugin-provided-mcp-servers — so S1 capture
// must happen in the active session's WebSocket. This module is the data layer:
// it produces extractor JS strings + canonical URLs the session feeds to MCP,
// and validates the JSON the extractor returns.
//
// Pure functions only — no subprocesses, no I/O, no state.

import { z } from "zod";

// ───── Extractor templates ────────────────────────────────────────────────

export const POSTS_EXTRACTOR_TEMPLATE = `(async () => {
  const cutoff = new Date('__CUTOFF__');
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await sleep(3000);
  const seen = new Set();
  const results = [];
  let stable = 0;
  let oldest = new Date();

  // Inline parseAbbreviated for metrics — extractor runs in page context, no module imports.
  const parseAbbrev = (s) => {
    if (s == null) return null;
    const str = String(s).trim();
    if (!str) return null;
    const m = str.replace(/,/g, '').match(/^([\\d.]+)\\s*([KMB])?\\b/i);
    if (!m) return null;
    const n = parseFloat(m[1]);
    if (!Number.isFinite(n)) return null;
    const mult = ({K: 1e3, M: 1e6, B: 1e9})[(m[2] || '').toUpperCase()] || 1;
    return Math.round(n * mult);
  };

  for (let i = 0; i < 12; i++) {
    const tweets = document.querySelectorAll('[data-testid="tweetText"]');
    let newC = 0;
    tweets.forEach(tw => {
      const art = tw.closest('article');
      if (!art) return;
      const sl = art.querySelectorAll('a[href*="/status/"]');
      const url = sl.length > 0 ? 'https://x.com' + sl[0].getAttribute('href') : '';
      const t = art.querySelector('time');
      if (!t) return;
      const ts = new Date(t.getAttribute('datetime'));
      if (ts < cutoff) return;
      const txt = tw.textContent.replace(/\\n/g, ' ').trim().substring(0, 200);
      const dedupKey = url + '::' + txt.substring(0, 60);
      if (seen.has(dedupKey)) return;
      seen.add(dedupKey);

      // External links — cap 2 per tweet for byte budget, skip self-references.
      const links = [];
      tw.querySelectorAll('a[href*="t.co"]').forEach(a => {
        if (links.length >= 2) return;
        const href = a.getAttribute('href');
        const text = a.textContent.trim();
        if (href && !href.includes('twitter.com') && !href.includes('x.com')) {
          links.push({href, text});
        }
      });

      // Link preview card — best-effort, stripped of nulls.
      let card = null;
      const cw = art.querySelector('[data-testid="card.wrapper"]');
      if (cw) {
        const cardLink = cw.querySelector('a[href]');
        const cardImg = cw.querySelector('img[src]');
        const cardDetail = cw.querySelector('[data-testid="card.layoutLarge.detail"]');
        const cardText = cardDetail ? cardDetail.textContent : cw.textContent;
        const cardTitle = cardText ? cardText.trim().substring(0, 100) : null;
        const cardHref = cardLink ? cardLink.getAttribute('href') : null;
        let cardDomain = null;
        if (cardHref) {
          try { cardDomain = new URL(cardHref, location.origin).hostname; } catch {}
        }
        const raw = {
          url: cardHref,
          title: cardTitle,
          image: cardImg ? cardImg.getAttribute('src') : null,
          domain: cardDomain
        };
        const filtered = Object.fromEntries(Object.entries(raw).filter(([_, v]) => v != null));
        if (Object.keys(filtered).length > 0) card = filtered;
      }

      // Quoted tweet — single-level recursion via nested article.
      let quoted = null;
      const inner = art.querySelector('[data-testid="tweet"]');
      if (inner && inner !== art) {
        const innerTextEl = inner.querySelector('[data-testid="tweetText"]');
        const innerText = innerTextEl ? innerTextEl.textContent.trim().substring(0, 100) : null;
        const innerLink = inner.querySelector('a[href*="/status/"]');
        const innerHref = innerLink ? innerLink.getAttribute('href') : null;
        const innerHandleMatch = innerHref ? innerHref.match(/^\\/(\\w+)\\/status\\//) : null;
        const raw = {
          handle: innerHandleMatch ? '@' + innerHandleMatch[1] : null,
          text: innerText,
          url: innerHref ? 'https://x.com' + innerHref : null
        };
        const filtered = Object.fromEntries(Object.entries(raw).filter(([_, v]) => v != null));
        if (Object.keys(filtered).length > 0) quoted = filtered;
      }

      // Engagement metrics. testid is "retweet" NOT "repost" despite UI rebrand —
      // verified across multiple OSS scrapers + manual DOM inspection.
      const readMetric = (selectorVal) => {
        const el = art.querySelector('[data-testid="' + selectorVal + '"]');
        if (!el) return null;
        const innerSpan = el.querySelector('[data-testid="app-text-transition-container"] span');
        let raw = innerSpan ? innerSpan.textContent.trim() : null;
        if (!raw) {
          const aria = el.getAttribute('aria-label') || '';
          const match = aria.match(/^([\\d.,KMB]+)/i);
          raw = match ? match[1] : null;
        }
        return parseAbbrev(raw);
      };
      const metrics = {
        likes: readMetric('like'),
        reposts: readMetric('retweet'),
        replies: readMetric('reply')
      };
      const hasMetrics = metrics.likes != null || metrics.reposts != null || metrics.replies != null;

      const item = {t: txt, u: url, d: t.getAttribute('datetime')};
      if (links.length) item.external_links = links;
      if (card) item.card = card;
      if (quoted) item.quoted_tweet = quoted;
      if (hasMetrics) item.metrics = metrics;
      results.push(item);
      newC++;
      if (ts < oldest) oldest = ts;
    });

    let past = false;
    document.querySelectorAll('article time').forEach(t => {
      if (new Date(t.getAttribute('datetime')) < cutoff) past = true;
    });
    if (past && i >= 2) break;
    if (newC === 0) stable++; else stable = 0;
    if (stable >= 3) break;

    window.scrollBy(0, window.innerHeight * 2);
    await sleep(1300);
  }
  // Stash full result on window for chunked retrieval; return small summary.
  // MCP javascript_tool truncates responses at ~1500-2000 chars regardless of
  // full data in JS context — main session reads window.__capPosts.tw in
  // CHUNK_SIZE-tweet slices via buildChunkReaderJs.
  window.__capPosts = {a: '@__HANDLE__', n: results.length, oldest: oldest.toISOString().substring(0, 16), stable_iterations: stable, tw: results};
  return JSON.stringify({n: results.length, oldest: window.__capPosts.oldest, stable_iterations: stable});
})()`;

export const REPLIES_EXTRACTOR_TEMPLATE = `(async () => {
  const cutoff = new Date('__CUTOFF__');
  const handle = '__HANDLE__';
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await sleep(3000);
  const seen = new Set();
  const results = [];
  let stable = 0;

  // Inline parseAbbreviated for metrics — see Posts template note.
  const parseAbbrev = (s) => {
    if (s == null) return null;
    const str = String(s).trim();
    if (!str) return null;
    const m = str.replace(/,/g, '').match(/^([\\d.]+)\\s*([KMB])?\\b/i);
    if (!m) return null;
    const n = parseFloat(m[1]);
    if (!Number.isFinite(n)) return null;
    const mult = ({K: 1e3, M: 1e6, B: 1e9})[(m[2] || '').toUpperCase()] || 1;
    return Math.round(n * mult);
  };

  for (let i = 0; i < 16; i++) {
    const tweets = document.querySelectorAll('[data-testid="tweetText"]');
    let newC = 0;
    tweets.forEach(tw => {
      const art = tw.closest('article');
      if (!art) return;
      const authored = art.querySelector(\`a[href^="/\${handle}/status/"]\`);
      if (!authored) return;
      const url = 'https://x.com' + authored.getAttribute('href');
      const t = art.querySelector('time');
      if (!t) return;
      const ts = new Date(t.getAttribute('datetime'));
      if (ts < cutoff) return;
      if (seen.has(url)) return;
      seen.add(url);
      const txt = tw.textContent.replace(/\\n/g, ' ').trim().substring(0, 200);

      // External links — cap 2 per tweet.
      const links = [];
      tw.querySelectorAll('a[href*="t.co"]').forEach(a => {
        if (links.length >= 2) return;
        const href = a.getAttribute('href');
        const text = a.textContent.trim();
        if (href && !href.includes('twitter.com') && !href.includes('x.com')) {
          links.push({href, text});
        }
      });

      // Link preview card.
      let card = null;
      const cw = art.querySelector('[data-testid="card.wrapper"]');
      if (cw) {
        const cardLink = cw.querySelector('a[href]');
        const cardImg = cw.querySelector('img[src]');
        const cardDetail = cw.querySelector('[data-testid="card.layoutLarge.detail"]');
        const cardText = cardDetail ? cardDetail.textContent : cw.textContent;
        const cardTitle = cardText ? cardText.trim().substring(0, 100) : null;
        const cardHref = cardLink ? cardLink.getAttribute('href') : null;
        let cardDomain = null;
        if (cardHref) {
          try { cardDomain = new URL(cardHref, location.origin).hostname; } catch {}
        }
        const raw = {
          url: cardHref,
          title: cardTitle,
          image: cardImg ? cardImg.getAttribute('src') : null,
          domain: cardDomain
        };
        const filtered = Object.fromEntries(Object.entries(raw).filter(([_, v]) => v != null));
        if (Object.keys(filtered).length > 0) card = filtered;
      }

      // Quoted tweet — single-level recursion via nested article.
      let quoted = null;
      const inner = art.querySelector('[data-testid="tweet"]');
      if (inner && inner !== art) {
        const innerTextEl = inner.querySelector('[data-testid="tweetText"]');
        const innerText = innerTextEl ? innerTextEl.textContent.trim().substring(0, 100) : null;
        const innerLink = inner.querySelector('a[href*="/status/"]');
        const innerHref = innerLink ? innerLink.getAttribute('href') : null;
        const innerHandleMatch = innerHref ? innerHref.match(/^\\/(\\w+)\\/status\\//) : null;
        const raw = {
          handle: innerHandleMatch ? '@' + innerHandleMatch[1] : null,
          text: innerText,
          url: innerHref ? 'https://x.com' + innerHref : null
        };
        const filtered = Object.fromEntries(Object.entries(raw).filter(([_, v]) => v != null));
        if (Object.keys(filtered).length > 0) quoted = filtered;
      }

      // Engagement metrics. testid="retweet" NOT "repost" (UI rebrand only).
      const readMetric = (selectorVal) => {
        const el = art.querySelector('[data-testid="' + selectorVal + '"]');
        if (!el) return null;
        const innerSpan = el.querySelector('[data-testid="app-text-transition-container"] span');
        let raw = innerSpan ? innerSpan.textContent.trim() : null;
        if (!raw) {
          const aria = el.getAttribute('aria-label') || '';
          const match = aria.match(/^([\\d.,KMB]+)/i);
          raw = match ? match[1] : null;
        }
        return parseAbbrev(raw);
      };
      const metrics = {
        likes: readMetric('like'),
        reposts: readMetric('retweet'),
        replies: readMetric('reply')
      };
      const hasMetrics = metrics.likes != null || metrics.reposts != null || metrics.replies != null;

      const item = {t: txt, u: url, d: t.getAttribute('datetime')};
      if (links.length) item.external_links = links;
      if (card) item.card = card;
      if (quoted) item.quoted_tweet = quoted;
      if (hasMetrics) item.metrics = metrics;
      results.push(item);
      newC++;
    });

    let past = false;
    document.querySelectorAll('article time').forEach(t => {
      if (new Date(t.getAttribute('datetime')) < cutoff) past = true;
    });
    if (past && i >= 2) break;
    if (newC === 0) stable++; else stable = 0;
    if (stable >= 3) break;

    window.scrollBy(0, window.innerHeight * 2);
    await sleep(1300);
  }
  // Stash to window.__capReplies for chunked retrieval — see Posts template.
  window.__capReplies = {a: '@' + handle, surface: 'with_replies', n: results.length, stable_iterations: stable, tw: results};
  return JSON.stringify({n: results.length, stable_iterations: stable});
})()`;

export const SELECTOR_PROBE = `(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  await sleep(2500);
  const tweetCount = document.querySelectorAll('[data-testid="tweetText"]').length;
  const articleCount = document.querySelectorAll('article[data-testid="tweet"]').length;
  return JSON.stringify({tweetCount, articleCount, ok: tweetCount > 0 || articleCount > 0});
})()`;

// ───── URL + JS builders ──────────────────────────────────────────────────

const VALID_SURFACES = new Set(["posts", "with_replies"]);
const LEADING_AT_REGEX = /^@/;
const JSON_OBJECT_BODY_REGEX = /\{[\s\S]*\}/;
const COMMA_REGEX = /,/g;
const ABBREVIATED_COUNT_REGEX = /^([\d.]+)\s*([KMB])?\b/i;

function bareHandle(handle) {
  return String(handle || "").replace(LEADING_AT_REGEX, "");
}

// Escape a value for interpolation into a single-quoted JS string literal in the
// extractor templates. Backslash first, then single-quote, so an untrusted
// following-list handle (or a malformed cutoff) cannot break out of the literal
// and inject script into the browser session.
function escapeForSingleQuotedJs(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/'/g, "\\'");
}

export function profileUrl(handle, surface = "posts") {
  if (!VALID_SURFACES.has(surface)) {
    throw new Error(`Unknown surface "${surface}" — expected posts | with_replies`);
  }
  const h = bareHandle(handle);
  if (!h) throw new Error("handle required");
  return surface === "with_replies" ? `https://x.com/${h}/with_replies` : `https://x.com/${h}`;
}

/**
 * Build an extractor invocation for the main CC session to feed to chrome MCP.
 *
 * Returns `{ js, url }`:
 *   - `url` — pass to `mcp__claude-in-chrome__browser_batch` navigate action
 *   - `js`  — pass to `mcp__claude-in-chrome__javascript_tool` after navigation+sleep
 *
 * @param {object} params
 * @param {string} params.handle      Twitter/X handle (with or without @)
 * @param {string} [params.surface]   'posts' (timeline) or 'with_replies' (replies)
 * @param {string} params.cutoffIso   ISO timestamp; tweets older than this are skipped
 */
export function buildExtractorJs({ handle, surface = "posts", cutoffIso }) {
  if (!cutoffIso) throw new Error("cutoffIso required");
  const url = profileUrl(handle, surface);
  const tmpl = surface === "with_replies" ? REPLIES_EXTRACTOR_TEMPLATE : POSTS_EXTRACTOR_TEMPLATE;
  const h = bareHandle(handle);
  // Function replacers, so a `$` in the escaped value is inserted literally and
  // never interpreted as a replacement pattern (`$&`, `$1`, …).
  const cutoffLiteral = escapeForSingleQuotedJs(cutoffIso);
  const handleLiteral = escapeForSingleQuotedJs(h);
  const js = tmpl.replace(/__CUTOFF__/g, () => cutoffLiteral).replace(/__HANDLE__/g, () => handleLiteral);
  return { js, url };
}

// ───── Chunked retrieval ──────────────────────────────────────────────────

// MCP javascript_tool response is truncated at ~1500-2000 chars regardless of how
// much data the JS captured. The extractor templates above stash the full result on
// `window.__capPosts` / `window.__capReplies` and return only `{n, oldest?, stable_iterations}`.
// Main session then reads `tw[]` in CHUNK_SIZE-tweet slices via separate
// `javascript_tool` calls and reassembles via `assembleChunks`.

// Per-tweet bytes ≈ 700-1000 with current TweetSchema (text + url + datetime +
// external_links + card + quoted_tweet + metrics). 2 × ~700 = ~1400 fits the
// ~1500-2000 char MCP javascript_tool response cap with ~30% headroom.
// Raising requires byte-budget recalc.
export const CHUNK_SIZE = 2;

const STASH_KEY_BY_SURFACE = Object.freeze({
  posts: "__capPosts",
  with_replies: "__capReplies",
});

/**
 * Build a `javascript_tool` payload that reads a slice of the stashed extractor
 * output. The main session loops `for s in 0..summary.n step CHUNK_SIZE` and
 * collects each chunk's parsed JSON array.
 *
 * @param {'posts' | 'with_replies'} surface
 * @param {number} start  inclusive start index (>= 0)
 * @param {number} end    exclusive end index   (>= start)
 * @returns {string}      JS source ready for `mcp__claude-in-chrome__javascript_tool`
 */
export function buildChunkReaderJs(surface, start, end) {
  const stashKey = STASH_KEY_BY_SURFACE[surface];
  if (!stashKey) {
    throw new Error(`Unknown surface "${surface}" — expected posts | with_replies`);
  }
  const s = Number(start);
  const e = Number(end);
  if (!Number.isInteger(s) || s < 0) throw new Error("start must be a non-negative integer");
  if (!Number.isInteger(e) || e < s) throw new Error("end must be an integer >= start");
  return `JSON.stringify(window.${stashKey}.tw.slice(${s}, ${e}))`;
}

/**
 * Reconstruct the full extractor output from a stash-mode summary plus the
 * array of `tw[]` chunks read via `buildChunkReaderJs`. Validates the result
 * via `validateExtractorOutput` so downstream commit-s1 sees the same shape
 * the in-page extractor would have produced for a single javascript_tool call.
 *
 * @param {{n: number, oldest?: string, stable_iterations?: number}} summary
 * @param {Array<Array | string>} chunks  parsed arrays OR JSON strings of arrays
 * @param {{handle: string, surface?: 'posts' | 'with_replies'}} opts
 */
export function assembleChunks(summary, chunks, { handle, surface = "posts" } = {}) {
  if (!summary || typeof summary !== "object") throw new Error("summary required");
  if (!Array.isArray(chunks)) throw new Error("chunks must be an array");
  if (!handle) throw new Error("handle required for assembly");
  if (!STASH_KEY_BY_SURFACE[surface]) {
    throw new Error(`Unknown surface "${surface}" — expected posts | with_replies`);
  }
  const tw = [];
  for (const chunk of chunks) {
    const arr = typeof chunk === "string" ? JSON.parse(chunk) : chunk;
    if (!Array.isArray(arr)) throw new Error("each chunk must be an array (or JSON string of one)");
    for (const t of arr) tw.push(t);
  }
  if (tw.length !== summary.n) {
    throw new Error(`assembleChunks: chunk total ${tw.length} !== summary.n ${summary.n}`);
  }
  const h = bareHandle(handle);
  const stable = summary.stable_iterations ?? 0;
  const assembled =
    surface === "with_replies"
      ? { a: `@${h}`, surface: "with_replies", n: summary.n, stable_iterations: stable, tw }
      : { a: `@${h}`, n: summary.n, oldest: summary.oldest ?? null, stable_iterations: stable, tw };
  return validateExtractorOutput(assembled);
}

// ───── Output validation ──────────────────────────────────────────────────

const ExternalLinkSchema = z.object({
  href: z.string(),
  text: z.string(),
});

const CardSchema = z.object({
  domain: z.string().optional(),
  title: z.string().optional(),
  image: z.string().optional(),
  url: z.string().optional(),
});

const QuotedTweetSchema = z.object({
  handle: z.string().optional(),
  text: z.string().optional(),
  url: z.string().optional(),
});

const MetricsSchema = z.object({
  likes: z.number().int().nullable().optional(),
  reposts: z.number().int().nullable().optional(),
  replies: z.number().int().nullable().optional(),
});

const TweetSchema = z.object({
  t: z.string(),
  u: z.string(),
  d: z.string(),
  external_links: z.array(ExternalLinkSchema).optional(),
  card: CardSchema.optional(),
  quoted_tweet: QuotedTweetSchema.optional(),
  metrics: MetricsSchema.optional(),
});

const ExtractorOutputSchema = z.object({
  a: z.string().optional(),
  surface: z.string().optional(),
  n: z.number().int().nonnegative(),
  oldest: z.string().nullable().optional(),
  stable_iterations: z.number().int().nonnegative().optional(),
  tw: z.array(TweetSchema),
  fallback_tier: z.string().nullable().optional(),
});

/**
 * Parse + validate the JSON string returned by the in-page extractor.
 * Accepts either a raw JSON string or an already-parsed object.
 * Throws on shape mismatch.
 */
export function validateExtractorOutput(raw) {
  let parsed;
  if (typeof raw === "string") {
    const s = raw.trim();
    if (s.startsWith("{")) {
      parsed = JSON.parse(s);
    } else {
      const m = s.match(JSON_OBJECT_BODY_REGEX);
      if (!m)
        throw new Error(`Could not locate JSON object in extractor output: ${s.substring(0, 200)}`);
      parsed = JSON.parse(m[0]);
    }
  } else if (raw && typeof raw === "object") {
    parsed = raw;
  } else {
    throw new Error(`validateExtractorOutput: expected string or object, got ${typeof raw}`);
  }
  return ExtractorOutputSchema.parse(parsed);
}

// ───── Fallback ladder reference ──────────────────────────────────────────

/**
 * Cookie-filter fallback ladder. Main CC session walks tier-by-tier when
 * Tier 1 returns "[BLOCKED: Cookie/query string data]". Tier 4 = give up
 * with a synthetic empty payload tagged `fallback_tier: 'unreachable'`.
 *
 * Source: references/chrome-extraction.md "Fallback ladder for cookie-blocked".
 */
export const FALLBACK_LADDER = Object.freeze({
  tier1: "javascript_tool",
  tier2: "get_page_text",
  tier3: "read_page",
  tier4: "screenshot",
});

// ───── parseAbbreviated (metrics helper) ──────────────────────────────────

/**
 * Parse X engagement count strings to integers. Handles abbreviated forms
 * X uses in the DOM ("1.2K", "12.4K", "1.2M") and aria-label fallback
 * ("1,234 likes" → 1234).
 *
 * @param {string|null|undefined} raw  count string (or aria-label leading number)
 * @returns {number|null}              integer count, or null on empty/invalid
 *
 * Examples:
 *   parseAbbreviated('1.2K')          → 1200
 *   parseAbbreviated('12.4K')         → 12400
 *   parseAbbreviated('1.2M')          → 1200000
 *   parseAbbreviated('1,234')         → 1234
 *   parseAbbreviated('1,234 likes')   → 1234   (aria-label form, trailing word stripped)
 *   parseAbbreviated('0')             → 0
 *   parseAbbreviated('')              → null
 *   parseAbbreviated(null)            → null
 *   parseAbbreviated('abc')           → null
 */
export function parseAbbreviated(raw) {
  if (raw == null) return null;
  const s = String(raw).trim();
  if (!s) return null;
  // Strip commas, then match leading number + optional K/M/B suffix.
  // Trailing words (e.g. " likes" from aria-label) are ignored by the regex anchor.
  const m = s.replace(COMMA_REGEX, "").match(ABBREVIATED_COUNT_REGEX);
  if (!m) return null;
  const n = Number.parseFloat(m[1]);
  if (!Number.isFinite(n)) return null;
  const mult = { K: 1e3, M: 1e6, B: 1e9 }[(m[2] || "").toUpperCase()] || 1;
  return Math.round(n * mult);
}
