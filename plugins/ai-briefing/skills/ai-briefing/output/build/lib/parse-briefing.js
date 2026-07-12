// Parse output/meetings/meeting-{N}.md into structured items via remark AST.
//
// Briefing markdown shape:
//   # AI Briefing — Meeting #N
//   **Window:** ISO → ISO (~Nd)
//   **Next meeting:** YYYY-MM-DD HH:MM TZ
//   ...
//   ## Anthropic
//   ### HIGH
//   - **Title** (date opt): body. — URL · URL
//   ### MED
//   - **Title**: body. — URL
//   ### LOW
//   - body. — URL
//   ---
//   ## OpenAI
//   ...
//
// Output:
//   { meta: { meetingNumber, window, items_count, sources_line }, buckets: { Anthropic: { HIGH:[…], MED:[…], LOW:[…] }, ... } }

import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import { visit } from "unist-util-visit";
import fs from "node:fs/promises";

/** Extract plain text from an mdast inline node array. */
function flattenInline(nodes) {
  let out = "";
  for (const n of nodes ?? []) {
    if (n.type === "text") out += n.value;
    else if (n.type === "break") out += "\n";
    else if (n.type === "inlineCode") out += n.value;
    else if (n.type === "strong" || n.type === "emphasis") out += flattenInline(n.children);
    else if (n.type === "link") out += flattenInline(n.children);
    else if (n.children) out += flattenInline(n.children);
  }
  return out;
}

/** Collect all link nodes inside a subtree. */
function collectLinks(node) {
  const urls = [];
  visit(node, "link", (n) => urls.push(n.url));
  return urls;
}

function stripMetadataLabel(text, label) {
  return text.replace(new RegExp(`^${label}:\\s*`, "i"), "").trim();
}

/**
 * Split a bullet's text on the ' — ' (em-dash space) sentinel that separates
 * body from URL list. Returns { headline, body, urls }.
 *
 * Heuristics:
 *   - First child of listItem is paragraph; first inline run typically begins
 *     with **strong** title, then ":" or " (date):" or just " — "
 *   - URLs come after the LAST " — " segment
 */
function parseBulletParagraph(paragraph) {
  // Build segments: { type: "strong"|"text"|..., value, url? }
  const segs = [];
  for (const child of paragraph.children ?? []) {
    if (child.type === "strong") {
      segs.push({ type: "strong", value: flattenInline(child.children) });
    } else if (child.type === "text") {
      segs.push({ type: "text", value: child.value });
    } else if (child.type === "inlineCode") {
      segs.push({ type: "text", value: `\`${child.value}\`` });
    } else if (child.type === "link") {
      segs.push({ type: "link", value: flattenInline(child.children), url: child.url });
    } else if (child.type === "emphasis") {
      segs.push({ type: "text", value: flattenInline(child.children) });
    }
  }

  // Headline = first strong segment if it leads, else first sentence chunk
  let headline = "";
  let bodyStart = 0;
  if (segs[0]?.type === "strong") {
    headline = segs[0].value.trim();
    bodyStart = 1;
  }

  // Reconstruct remaining as text — links replaced by their URL inline
  let rest = "";
  for (let i = bodyStart; i < segs.length; i++) {
    const s = segs[i];
    if (s.type === "link") rest += s.url;
    else rest += s.value;
  }

  // URLs collected from raw link nodes — dedup (GFM autolink can create duplicates)
  const linkSet = new Set();
  visit(paragraph, "link", (n) => linkSet.add(n.url));
  const allLinks = [...linkSet];

  // Body = text before final " — URL" tail
  // Find last " — " followed by url-ish content
  let body = rest;
  const dashSplit = rest.split(/\s+—\s+/);
  if (dashSplit.length > 1) {
    // Last chunk likely contains URLs separated by ' · '
    const lastChunk = dashSplit[dashSplit.length - 1];
    const looksLikeUrls = /https?:\/\//.test(lastChunk);
    if (looksLikeUrls) {
      body = dashSplit.slice(0, -1).join(" — ").trim();
    }
  }

  // Strip ALL urls inline that survived (defensive — autolink puts them as link nodes,
  // but they may bleed into body if the dash-split heuristic missed them)
  body = body.replace(/https?:\/\/\S+/g, "").replace(/\s+·\s+(?=$|\s)/g, " ").trim();

  // Strip leading punctuation/whitespace; promote leading "(date)" prefix
  // Also strip leading em-dash / hyphen separator (covers "**Title** — Body" pattern).
  body = body.replace(/^[—–\-:\s]+/, "").trim();
  body = body.replace(/^\(([^)]+)\):\s*/, "($1) ");
  body = body.replace(/\s+/g, " ").trim();
  body = body.replace(/\s*\.\s*$/, ".");

  // Cap body length for slide density. Tail-ellipsis preserves URL coverage; no
  // overflow at desktop/laptop/tablet/mobile viewports at this cap.
  const BODY_CAP = 500;
  if (body.length > BODY_CAP) {
    body = body.slice(0, BODY_CAP).replace(/\s+\S*$/, "") + "…";
  }

  // If headline empty, use first sentence of body
  if (!headline) {
    const firstSent = body.split(/(?<=\.)\s+/)[0];
    headline = firstSent.replace(/[.!?]+$/, "").slice(0, 80);
    body = body.slice(headline.length).replace(/^[.\s]+/, "").trim();
  }

  return { headline, body, urls: allLinks, date: extractDate(body, headline) };
}

const MONTHS = {
  jan:0, january:0, feb:1, february:1, mar:2, march:2, apr:3, april:3,
  may:4, jun:5, june:5, jul:6, july:6, aug:7, august:7, sep:8, sept:8, september:8,
  oct:9, october:9, nov:10, november:10, dec:11, december:11,
};

/** Reject implausible publish dates: more than 30 days in the future
 *  (catches "retire July 24 2026" in body text being mis-parsed as a pub date)
 *  or more than 5 years in the past. */
function isReasonablePubDate(ms) {
  if (ms == null || !Number.isFinite(ms)) return false;
  const now = Date.now();
  const thirtyDaysFuture = now + 30 * 24 * 3600 * 1000;
  const fiveYearsPast = now - 5 * 365 * 24 * 3600 * 1000;
  return ms > fiveYearsPast && ms < thirtyDaysFuture;
}

/** Extract a sortable timestamp (ms-since-epoch) from item body / headline.
 *  Supports "Apr 28", "May 6, 2026", "(May 6-7)", "2026-05-06", "5/13", "5/13/26".
 *  Returns null when no date pattern is found — caller treats null as
 *  "undated, leave in source order".
 *
 *  Priority order (highest → lowest):
 *    1. Parenthetical (Month Day) in HEADLINE — author's explicit intent
 *    2. "Mon DD" / "Mon DD, YYYY" anywhere in headline/body
 *    3. "M/D" or "M/D/YY" anywhere — covers SDK-bump shorthand
 *    4. ISO YYYY-MM-DD that is NOT inside a hyphenated compound token
 *       (e.g. `fast-mode-2026-02-01` beta header should NOT match)
 *    5. URL-based inference (Twitter snowflake ID → tweet timestamp; GH release URL)
 *       — caller applies via the urlDateMap pass, not here
 */
function extractDate(body, headline) {
  const text = `${headline} ${body}`;

  // Priority 1: (Month Day) parenthetical in headline. Author signal.
  const paren = headline.match(/\(([A-Za-z]+)\s+(\d{1,2})(?:[\s-–]+\d{1,2})?(?:,\s*(\d{4}))?\)/);
  if (paren) {
    const monthName = paren[1].toLowerCase();
    if (monthName in MONTHS) {
      const month = MONTHS[monthName];
      const day = parseInt(paren[2], 10);
      const year = paren[3] ? parseInt(paren[3], 10) : new Date().getUTCFullYear();
      const ms = Date.UTC(year, month, day);
      if (isReasonablePubDate(ms)) return ms;
    }
  }

  // Priority 2: "Mon DD" / "Mon DD, YYYY" / "Mon DD-DD" anywhere
  const m = text.match(/\b(January|February|March|April|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.?\s+(\d{1,2})(?:[\s-–]+\d{1,2})?(?:,\s*(\d{4}))?\b/i);
  if (m) {
    const month = MONTHS[m[1].toLowerCase()];
    const day = parseInt(m[2], 10);
    const year = m[3] ? parseInt(m[3], 10) : new Date().getUTCFullYear();
    const ms = Date.UTC(year, month, day);
    if (isReasonablePubDate(ms)) return ms;
  }

  // Priority 3: "M/D" or "M/D/YY" or "M/D/YYYY" — SDK-bump shorthand like "(5/13)"
  const slash = text.match(/(?<![\w/])(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?(?![\w/])/);
  if (slash) {
    const month = parseInt(slash[1], 10) - 1;
    const day = parseInt(slash[2], 10);
    let year = new Date().getUTCFullYear();
    if (slash[3]) {
      year = parseInt(slash[3], 10);
      if (year < 100) year += 2000;
    }
    if (month >= 0 && month <= 11 && day >= 1 && day <= 31) {
      const ms = Date.UTC(year, month, day);
      if (isReasonablePubDate(ms)) return ms;
    }
  }

  // Priority 4: ISO YYYY-MM-DD — but NOT inside a hyphenated compound token.
  // `fast-mode-2026-02-01` should fail; ` 2026-05-15 ` or `(2026-05-15)` should match.
  // Lookbehind/ahead require non-`-` non-word character (or start/end of string).
  const iso = text.match(/(?<![\w-])(\d{4})-(\d{2})-(\d{2})(?![\w-])/);
  if (iso) {
    const year = parseInt(iso[1], 10);
    const month = parseInt(iso[2], 10) - 1;
    const day = parseInt(iso[3], 10);
    const ms = Date.UTC(year, month, day);
    if (isReasonablePubDate(ms)) return ms;
  }

  return null;
}

/** Decode a Twitter/X snowflake ID to its ms-since-epoch timestamp.
 *  Twitter epoch: 2010-11-04T01:42:54.657Z (1288834974657 ms).
 *  Snowflake shift: 22 bits. Returns null if ID isn't a valid snowflake. */
function snowflakeToMs(snowflakeStr) {
  if (!/^\d{15,20}$/.test(snowflakeStr)) return null;
  try {
    const id = BigInt(snowflakeStr);
    const epoch = 1288834974657n;
    const ms = Number((id >> 22n) + epoch);
    if (ms < epoch || ms > Date.now() + 365 * 24 * 3600 * 1000) return null;
    return ms;
  } catch {
    return null;
  }
}

/** Infer a date from a URL when extractDate returned null.
 *  Supported:
 *    - x.com/{user}/status/{snowflake} → snowflake decode
 *    - github.com/{owner}/{repo}/releases/tag/v{tag} → null (no date in URL)
 *    - any URL with /YYYY/MM/DD/ path segment → that date
 *    - any URL with YYYY-MM-DD in path → that date (not in domain)
 *  Returns ms-since-epoch or null. */
function dateFromUrl(url) {
  if (!url) return null;
  // x.com/{user}/status/{id} → snowflake
  const xMatch = url.match(/^https?:\/\/(?:x\.com|twitter\.com)\/[^/]+\/status\/(\d+)/i);
  if (xMatch) {
    const ms = snowflakeToMs(xMatch[1]);
    if (ms) return ms;
  }
  // /YYYY/MM/DD/ path
  const pathDate = url.match(/\/(\d{4})\/(\d{2})\/(\d{2})(?:\/|$)/);
  if (pathDate) {
    return Date.UTC(parseInt(pathDate[1], 10), parseInt(pathDate[2], 10) - 1, parseInt(pathDate[3], 10));
  }
  // ISO date in path (not in domain). Guard against malformed URLs — `item.urls`
  // is validated only as non-empty strings upstream, so a bad LLM artifact (no
  // scheme, bare host) would otherwise throw and abort the entire deck build.
  let u;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  const isoInPath = u.pathname.match(/(?<![\w-])(\d{4})-(\d{2})-(\d{2})(?![\w-])/);
  if (isoInPath) {
    return Date.UTC(parseInt(isoInPath[1], 10), parseInt(isoInPath[2], 10) - 1, parseInt(isoInPath[3], 10));
  }
  return null;
}

/** Parse a single ## bucket section's H3 children. Buckets without H3 tiers
 *  (e.g. ## Patterns, ## Breaking & Deprecated) collect their bullets under
 *  the synthetic "_items" tier. */
function parseBucketSection(nodes) {
  const tiers = {};
  let currentTier = null;
  for (const n of nodes) {
    if (n.type === "heading" && n.depth === 3) {
      currentTier = flattenInline(n.children).trim();
      tiers[currentTier] = [];
    } else if (n.type === "list") {
      const tierKey = currentTier || "_items";
      tiers[tierKey] = tiers[tierKey] || [];
      for (const item of n.children) {
        const para = item.children.find((c) => c.type === "paragraph");
        if (!para) continue;
        const parsed = parseBulletParagraph(para);
        // Also walk nested list (sub-bullets) for additional URLs — our briefing
        // pattern puts source URLs as nested `- <url>` items beneath the headline.
        const nestedList = item.children.find((c) => c.type === "list");
        if (nestedList) {
          const nestedUrls = new Set(parsed.urls);
          visit(nestedList, "link", (lk) => nestedUrls.add(lk.url));
          parsed.urls = [...nestedUrls];
        }
        if (parsed.headline || parsed.body) tiers[tierKey].push(parsed);
      }
    }
  }
  return tiers;
}

/** Main entry — read briefing.md, return structured shape.
 *  @param {string} briefingPath - path to meeting-{N}.md
 *  @param {object} [opts]
 *  @param {Map<string,number>} [opts.seenUrlDateMap] - URL → ms-epoch lookup from
 *    seen-items.json `first_seen` field. Used as final fallback for items whose
 *    publish date can't be extracted from markdown or URL. */
export async function parseBriefing(briefingPath, opts = {}) {
  const raw = await fs.readFile(briefingPath, "utf-8");
  const tree = unified().use(remarkParse).use(remarkGfm).parse(raw);

  // Extract meta from header paragraphs
  const meta = { meetingNumber: null, window: null, sourcesLine: "" };
  let bucketStart = -1;
  for (let i = 0; i < tree.children.length; i++) {
    const n = tree.children[i];
    if (n.type === "heading" && n.depth === 1) {
      const t = flattenInline(n.children);
      const m = t.match(/Meeting\s*#?(\d+)/i);
      if (m) meta.meetingNumber = parseInt(m[1], 10);
    }
    if (n.type === "paragraph") {
      const t = flattenInline(n.children);
      for (const line of t.split(/\r?\n/)) {
        const trimmed = line.trim();
        if (/^Window:/i.test(trimmed)) meta.window = stripMetadataLabel(trimmed, "Window");
        if (/^Sources:/i.test(trimmed)) meta.sourcesLine = stripMetadataLabel(trimmed, "Sources");
      }
    }
    if (n.type === "heading" && n.depth === 2) { bucketStart = i; break; }
  }

  // Walk siblings — group H2 sections
  const buckets = {};
  let currentBucket = null;
  let bucketChildren = [];
  for (let i = bucketStart; i < tree.children.length; i++) {
    const n = tree.children[i];
    if (n.type === "heading" && n.depth === 2) {
      if (currentBucket) buckets[currentBucket] = parseBucketSection(bucketChildren);
      currentBucket = flattenInline(n.children).trim();
      bucketChildren = [];
    } else if (n.type === "thematicBreak") {
      // section separator — flush current
      if (currentBucket) {
        buckets[currentBucket] = parseBucketSection(bucketChildren);
        currentBucket = null;
        bucketChildren = [];
      }
    } else if (currentBucket) {
      bucketChildren.push(n);
    }
  }
  if (currentBucket) buckets[currentBucket] = parseBucketSection(bucketChildren);

  // Build URL→date map from the "Per-profile runner deltas" bucket, then
  // back-fill any null `date` on bullets whose URLs match. Runner deltas carry
  // authoritative `Date range: YYYY-MM-DD` per item; main-bucket bullets often
  // omit explicit month/year and would otherwise stay undated.
  // URL→date map is authoritative (announcement date from source tweet); extractDate
  // heuristic often hits dates mentioned in body ("through July 13") that aren't the
  // announcement date. Override any heuristic date when a URL match exists.
  const urlDateMap = buildUrlDateMap(raw);
  for (const bucket of Object.values(buckets)) {
    for (const tier of Object.values(bucket)) {
      for (const item of tier) {
        // Pass 1: deltas URL→date map (authoritative for runner-captured tweets)
        for (const u of item.urls || []) {
          if (urlDateMap.has(u)) { item.date = urlDateMap.get(u); break; }
        }
        // Pass 2: URL-based inference for items still undated
        // (Twitter snowflake decode, /YYYY/MM/DD/ path segments, ISO in URL path)
        if (item.date == null) {
          for (const u of item.urls || []) {
            const inferred = dateFromUrl(u);
            if (inferred != null) { item.date = inferred; break; }
          }
        }
        // Pass 3: seen-items.json first_seen fallback (caller-provided map).
        // Final resort when markdown encodes no date and URL has no embedded date.
        if (item.date == null && opts.seenUrlDateMap) {
          for (const u of item.urls || []) {
            if (opts.seenUrlDateMap.has(u)) {
              item.date = opts.seenUrlDateMap.get(u);
              break;
            }
          }
        }
      }
    }
  }

  return { meta, buckets };
}

/** Scan raw markdown for `URLs: <url>, <url>` + `Date: YYYY-MM-DD` (or legacy
 *  `Date range: YYYY-MM-DD`) pairs (the briefing-deltas.md format) and return a
 *  URL→epoch-ms map. Backward-compat for deltas from prior runs that emitted
 *  `Date range: <range>` before the schema tightened to single ISO `date`. */
function buildUrlDateMap(raw) {
  const map = new Map();
  const lines = raw.split(/\r?\n/);
  let pendingUrls = [];
  for (const line of lines) {
    const urlMatch = line.match(/^URLs?:\s*(.+)$/i);
    if (urlMatch) {
      pendingUrls = urlMatch[1].split(/[,\s]+/).filter((s) => /^https?:\/\//.test(s));
      continue;
    }
    const dateMatch = line.match(/^Date(?:\s*range)?:\s*(\d{4})-(\d{2})-(\d{2})/i);
    if (dateMatch && pendingUrls.length > 0) {
      const ts = Date.UTC(+dateMatch[1], +dateMatch[2] - 1, +dateMatch[3]);
      for (const u of pendingUrls) {
        if (!map.has(u)) map.set(u, ts);
      }
      pendingUrls = [];
    }
  }
  return map;
}
