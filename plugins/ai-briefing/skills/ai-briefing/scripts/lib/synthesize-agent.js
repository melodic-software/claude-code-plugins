// S3 Synthesize — spawn `claude -p` with raw captures + seen URLs + tier table.
// Output: validated zod schema of candidate briefing items.

import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";

import { z } from "zod";

import { BRIEFING_AGENT_MODEL } from "./models.js";

export const CandidateSchema = z.object({
  title: z.string().min(1),
  summary: z.string().min(1),
  urls: z.array(z.string()).min(1),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "must be ISO YYYY-MM-DD"),
  tierHint: z.enum(["HIGH", "MED", "LOW"]).optional(),
  bucketHint: z.string().optional(),
});

export const CandidatesArraySchema = z.array(CandidateSchema);

const MARKDOWN_FENCE_OPEN_REGEX = /^```(?:json)?\s*/i;
const MARKDOWN_FENCE_CLOSE_REGEX = /\s*```$/i;

const TIER_TABLE_BRIEF = `
HIGH = product/IDE/CLI/SDK/plugin updates, model releases that change cost-economics, real-world deployments at scale, material legal rulings.
MED = API/SDK changes without immediate user-facing feature, alignment papers, valuation rounds, conference promos with substance.
LOW = roadmap promises, partner showcases, accelerator winners, sponsored content, vibe takes.
Apolitical filter: drop partisan-only items (politician deepfakes, campaign noise). Keep industry-controversies that name politicians ONLY if removing the political angle still leaves a clear AI-industry impact (e.g. Anthropic-DoD supply-chain dispute, Musk v Altman trial).
`;

const BUCKET_HINTS = `anthropic | openai | google | cursor | xai | meta | deepseek | other | extras`;

/**
 * Slim a tweet for the S3 prompt.
 *
 * The raw extractor output (`{t, u, d, external_links?, card?, quoted_tweet?, metrics?}`)
 * is too verbose to dump 50× into the prompt. This helper:
 *   - keeps `t/u/d` (always)
 *   - top 1 `external_links` href only (drop display text — S3 only needs the URL)
 *   - card → `{url, title (≤60 chars)}` only
 *   - metrics → packed string "L/R/Re" e.g. "1234/56/12" or "1234/-/12"
 *   - INTENTIONALLY OMITS `quoted_tweet` body — quoter's tweet text is already in `t`
 *
 * Result: ~+50 bytes per tweet at most vs raw bloat (~+700 bytes).
 */
function slimForPrompt(tw) {
  if (!tw) return tw;
  const out = { t: tw.t, u: tw.u, d: tw.d };
  if (Array.isArray(tw.external_links) && tw.external_links.length > 0) {
    // Top 1 link only — drop text, keep href (S3 uses href for primary-URL pairing)
    out.links = tw.external_links
      .slice(0, 1)
      .map((l) => l.href)
      .filter(Boolean);
    if (out.links.length === 0) out.links = undefined;
  }
  if (tw.card && (tw.card.url || tw.card.title)) {
    out.card = {};
    if (tw.card.url) out.card.url = tw.card.url;
    if (tw.card.title) out.card.title = String(tw.card.title).substring(0, 60);
  }
  if (tw.metrics) {
    const m = tw.metrics;
    const fmt = (n) => (n == null ? "-" : String(n));
    // Only emit when at least one count present (extractor already gates this, but defensive)
    if (m.likes != null || m.reposts != null || m.replies != null) {
      out.m = `${fmt(m.likes)}/${fmt(m.reposts)}/${fmt(m.replies)}`;
    }
  }
  return out;
}

function buildSynthesizePrompt({ handle, priorityBucket, posts, replies, seenUrls }) {
  const seenList = [...seenUrls]
    .slice(0, 100)
    .map((u) => `  ${u}`)
    .join("\n");
  const totalSeen = seenUrls.size;
  const postsTrimmed = (posts || []).slice(0, 50).map(slimForPrompt);
  const repliesTrimmed = (replies || []).slice(0, 50).map(slimForPrompt);

  return `You are condensing raw Twitter/X captures for ${handle} into briefing candidates for an internal AI engineering meeting.

Priority bucket: ${priorityBucket}

Tier rules:
${TIER_TABLE_BRIEF}

Bucket router (assign hint per item):
${BUCKET_HINTS}

Total seen-items in registry: ${totalSeen} URLs (sample of first 100):
${seenList || "  (none)"}

Per-tweet shape:
- t/u/d: text / tweet-status URL / datetime
- links: top external link from tweet body when present (e.g. blog/GH/docs URL — prefer this for primary-source pairing)
- card: link-preview metadata { url, title } when tweet has a link card
- m: engagement string "likes/reposts/replies" (e.g. "1234/56/12"; "-" = missing). High engagement on tooling/release tweets boosts tier from MED to HIGH.

Posts (newest first), ${postsTrimmed.length}:
${JSON.stringify(postsTrimmed, null, 2)}

With_replies (newest first), ${repliesTrimmed.length}:
${JSON.stringify(repliesTrimmed, null, 2)}

Task:
1. Drop near-duplicates of seen-items (same URL or substantively the same news already captured).
2. Apolitical filter: drop partisan-only items. Keep industry-controversy items per rules above.
3. Group related tweets from same handle into single candidates (e.g. multi-tweet thread = 1 candidate).
4. For each candidate produce: { title (≤80 chars), summary (1-2 sentences, factual), urls (1+; PREFER official-domain links from \`links\` or \`card.url\` over the bare tweet URL when both are available — those are the canonical primary sources), date (REQUIRED, ISO YYYY-MM-DD = the newest tweet's date in the group; take the \`d\` field's date portion), tierHint (HIGH|MED|LOW), bucketHint (one of the bucket router values) }.
5. Use \`m\` (engagement) as a ranking signal: high likes/reposts on tooling tweets supports HIGH tier.
6. Output 0..K candidates. Quality over quantity. If nothing meaningful, output [].

Forbidden:
- Do NOT emit any candidate without a valid \`date\` field (ISO YYYY-MM-DD). If you cannot determine a date for a candidate, DROP it.
- Do NOT emit \`dateRange\` — use single ISO \`date\` instead.

Output ONLY a JSON array. No prose, no markdown fences. The first character of your response must be '['.
`;
}

// Exported for tests.
export { slimForPrompt };

function parseClaudeOutput(stdout) {
  let outer;
  try {
    outer = JSON.parse(stdout);
  } catch {
    outer = null;
  }
  const text = outer?.result ?? stdout;
  const trimmed = String(text).trim();

  // Strip markdown fences if present
  const candidate = trimmed
    .replace(MARKDOWN_FENCE_OPEN_REGEX, "")
    .replace(MARKDOWN_FENCE_CLOSE_REGEX, "")
    .trim();
  if (candidate.startsWith("[")) {
    try {
      return JSON.parse(candidate);
    } catch {
      /* fall through */
    }
  }
  // Find first [ to last ]
  const start = candidate.indexOf("[");
  const end = candidate.lastIndexOf("]");
  if (start >= 0 && end > start) {
    try {
      return JSON.parse(candidate.substring(start, end + 1));
    } catch {
      /* fall */
    }
  }
  throw new Error(`Could not parse JSON array from output: ${trimmed.substring(0, 300)}`);
}

export async function synthesize({
  handle,
  priorityBucket,
  posts,
  replies,
  seenUrls,
  claudeBin = "claude",
  model = BRIEFING_AGENT_MODEL,
  timeoutMs = 180_000,
  dryRun = false,
}) {
  if (dryRun) return [];

  // Skip synthesis if there's nothing to synthesize
  const hasContent = posts?.length || replies?.length;
  if (!hasContent) return [];

  const prompt = buildSynthesizePrompt({ handle, priorityBucket, posts, replies, seenUrls });

  const tmpDir = path.join(os.tmpdir(), "ai-briefing-runner");
  await fs.mkdir(tmpDir, { recursive: true });
  const promptFile = path.join(tmpDir, `synth-${randomBytes(6).toString("hex")}.md`);
  await fs.writeFile(promptFile, prompt, "utf-8");

  try {
    const r = spawnSync(
      claudeBin,
      ["-p", `@${promptFile}`, "--model", model, "--output-format", "json"],
      {
        encoding: "utf-8",
        timeout: timeoutMs,
        maxBuffer: 50 * 1024 * 1024,
      },
    );

    if (r.status !== 0) {
      throw new Error(
        `claude -p (synthesize) exit ${r.status}: ${(r.stderr || "").substring(0, 500)}`,
      );
    }

    const raw = parseClaudeOutput(r.stdout);
    return CandidatesArraySchema.parse(raw);
  } finally {
    try {
      await fs.unlink(promptFile);
    } catch {
      /* ignore */
    }
  }
}
