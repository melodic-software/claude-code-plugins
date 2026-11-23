import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import { visit } from "unist-util-visit";
import fs from "node:fs/promises";

function flattenInline(nodes) {
  let out = "";
  for (const n of nodes ?? []) {
    if (n.type === "text" || n.type === "inlineCode") out += n.value;
    else if (n.type === "break") out += "\n";
    else if (n.children) out += flattenInline(n.children);
  }
  return out;
}

function stripMetadataLabel(text, label) {
  return text.replace(new RegExp(`^${label}:\\s*`, "i"), "").trim();
}

function parseBulletParagraph(paragraph) {
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

  let headline = "";
  let bodyStart = 0;
  if (segs[0]?.type === "strong") {
    headline = segs[0].value.trim();
    bodyStart = 1;
  }

  const rest = segs
    .slice(bodyStart)
    .map((s) => (s.type === "link" ? s.url : s.value))
    .join("");

  const linkSet = new Set();
  visit(paragraph, "link", (n) => linkSet.add(n.url));
  const allLinks = [...linkSet];

  let body = rest;
  const dashSplit = rest.split(/\s+—\s+/);
  if (dashSplit.length > 1 && /https?:\/\//.test(dashSplit[dashSplit.length - 1])) {
    body = dashSplit.slice(0, -1).join(" — ").trim();
  }

  body = body.replace(/https?:\/\/\S+/g, "").replace(/\s+·\s+(?=$|\s)/g, " ").trim();

  body = body.replace(/^[—–\-:\s]+/, "").trim();
  body = body.replace(/^\(([^)]+)\):\s*/, "($1) ");
  body = body.replace(/\s+/g, " ").trim();
  body = body.replace(/\s*\.\s*$/, ".");

  const BODY_CAP = 500;
  if (body.length > BODY_CAP) {
    body = body.slice(0, BODY_CAP).replace(/\s+\S*$/, "") + "…";
  }

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

function isReasonablePubDate(ms) {
  if (ms == null || !Number.isFinite(ms)) return false;
  const now = Date.now();
  const thirtyDaysFuture = now + 30 * 24 * 3600 * 1000;
  const fiveYearsPast = now - 5 * 365 * 24 * 3600 * 1000;
  return ms > fiveYearsPast && ms < thirtyDaysFuture;
}

function monthNameMatchToMs(match) {
  if (!match) return null;
  const monthName = match[1].toLowerCase();
  if (!(monthName in MONTHS)) return null;
  const day = parseInt(match[2], 10);
  const year = match[3] ? parseInt(match[3], 10) : new Date().getUTCFullYear();
  const ms = Date.UTC(year, MONTHS[monthName], day);
  return isReasonablePubDate(ms) ? ms : null;
}

function extractDate(body, headline) {
  const text = `${headline} ${body}`;

  const paren = monthNameMatchToMs(
    headline.match(/\(([A-Za-z]+)\s+(\d{1,2})(?:[\s-–]+\d{1,2})?(?:,\s*(\d{4}))?\)/),
  );
  if (paren != null) return paren;

  const named = monthNameMatchToMs(
    text.match(/\b(January|February|March|April|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.?\s+(\d{1,2})(?:[\s-–]+\d{1,2})?(?:,\s*(\d{4}))?\b/i),
  );
  if (named != null) return named;

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

  const iso = text.match(ISO_DATE);
  if (iso) {
    const ms = ymdMatchToMs(iso);
    if (isReasonablePubDate(ms)) return ms;
  }

  return null;
}

const ISO_DATE = /(?<![\w-])(\d{4})-(\d{2})-(\d{2})(?![\w-])/;

function ymdMatchToMs(match) {
  return Date.UTC(parseInt(match[1], 10), parseInt(match[2], 10) - 1, parseInt(match[3], 10));
}

function dateFromUrl(url) {
  if (!url) return null;
  const pathDate = url.match(/\/(\d{4})\/(\d{2})\/(\d{2})(?:\/|$)/);
  if (pathDate) return ymdMatchToMs(pathDate);
  // ISO date in path (not in domain). Guard against malformed URLs — `item.urls`
  // is validated only as non-empty strings upstream, so a bad LLM artifact (no
  // scheme, bare host) would otherwise throw and abort the entire deck build.
  let u;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  const isoInPath = u.pathname.match(ISO_DATE);
  return isoInPath ? ymdMatchToMs(isoInPath) : null;
}

function firstUrlDate(urls, dateOf) {
  for (const u of urls) {
    const date = dateOf(u);
    if (date != null) return date;
  }
  return null;
}

function parseBucketSection(nodes) {
  const tiers = {};
  let currentTier = null;
  for (const n of nodes) {
    if (n.type === "heading" && n.depth === 3) {
      currentTier = flattenInline(n.children).trim();
      tiers[currentTier] = [];
    } else if (n.type === "list") {
      const tierKey = currentTier || "_items";
      tiers[tierKey] ??= [];
      for (const item of n.children) {
        const para = item.children.find((c) => c.type === "paragraph");
        if (!para) continue;
        const parsed = parseBulletParagraph(para);
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

  const buckets = {};
  let currentBucket = null;
  let bucketChildren = [];
  const flushBucket = () => {
    if (currentBucket) buckets[currentBucket] = parseBucketSection(bucketChildren);
    currentBucket = null;
    bucketChildren = [];
  };
  for (let i = bucketStart; i < tree.children.length; i++) {
    const n = tree.children[i];
    if (n.type === "heading" && n.depth === 2) {
      flushBucket();
      currentBucket = flattenInline(n.children).trim();
    } else if (n.type === "thematicBreak") {
      flushBucket();
    } else if (currentBucket) {
      bucketChildren.push(n);
    }
  }
  flushBucket();

  const { seenUrlDateMap } = opts;
  for (const bucket of Object.values(buckets)) {
    for (const tier of Object.values(bucket)) {
      for (const item of tier) {
        item.date ??= firstUrlDate(item.urls, dateFromUrl);
        if (seenUrlDateMap) item.date ??= firstUrlDate(item.urls, (u) => seenUrlDateMap.get(u));
      }
    }
  }

  return { meta, buckets };
}
