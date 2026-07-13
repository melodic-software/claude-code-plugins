// Normalize Grok headless JSON/text into chrome-extract-compatible tweet rows.

import { z } from "zod";

const TweetRowSchema = z.object({
  t: z.string().min(1),
  u: z.string().min(1),
  d: z.string().min(1),
});

const GrokPostsEnvelopeSchema = z.object({
  posts: z.array(TweetRowSchema).optional(),
  tw: z.array(TweetRowSchema).optional(),
});

const MARKDOWN_FENCE_OPEN_REGEX = /^```(?:json)?\s*/i;
const MARKDOWN_FENCE_CLOSE_REGEX = /\s*```$/i;
const AT_PREFIX_REGEX = /^@/;

export function bareHandle(handle) {
  return String(handle || "")
    .replace(AT_PREFIX_REGEX, "")
    .trim();
}

function stripFences(text) {
  return String(text)
    .trim()
    .replace(MARKDOWN_FENCE_OPEN_REGEX, "")
    .replace(MARKDOWN_FENCE_CLOSE_REGEX, "")
    .trim();
}

/** Extract JSON object or array from grok stdout (plain or json output-format). */
export function parseGrokJsonPayload(stdout) {
  const raw = String(stdout || "").trim();
  if (!raw) throw new Error("empty grok stdout");

  let outer;
  try {
    outer = JSON.parse(raw);
  } catch {
    outer = null;
  }

  if (outer && typeof outer === "object") {
    const text =
      outer.result ??
      outer.output ??
      outer.content ??
      outer.response ??
      outer.message ??
      outer.text ??
      null;
    if (typeof text === "string" && text.trim().startsWith("{")) {
      try {
        return JSON.parse(stripFences(text));
      } catch {
        /* fall through */
      }
    }
    if (Array.isArray(outer.posts) || Array.isArray(outer.tw)) {
      return outer;
    }
    if (typeof text === "string") {
      const inner = stripFences(text);
      const start = inner.indexOf("{");
      const end = inner.lastIndexOf("}");
      if (start >= 0 && end > start) {
        return JSON.parse(inner.substring(start, end + 1));
      }
    }
  }

  const candidate = stripFences(raw);
  const startObj = candidate.indexOf("{");
  const endObj = candidate.lastIndexOf("}");
  if (startObj >= 0 && endObj > startObj) {
    return JSON.parse(candidate.substring(startObj, endObj + 1));
  }
  throw new Error(`Could not parse JSON from grok output: ${raw.substring(0, 300)}`);
}

/** Session id from grok --output-format json (for --resume on follow-up calls). */
export function parseGrokSessionId(stdout) {
  const raw = String(stdout || "").trim();
  if (!raw) return null;
  try {
    const outer = JSON.parse(raw);
    return outer.sessionId ?? outer.session_id ?? null;
  } catch {
    return null;
  }
}

export function normalizeGrokPosts(parsed, handle) {
  const data = GrokPostsEnvelopeSchema.parse(parsed);
  const rows = data.posts ?? data.tw ?? [];
  const slug = bareHandle(handle);
  return rows.map((row) => ({
    t: String(row.t).replace(/\n/g, " ").trim().substring(0, 200),
    u: row.u,
    d: row.d,
    _source: "grok",
    _handle: slug,
  }));
}

/** Dedup tweets by status URL; prefer Chrome (non-grok) rows. */
export function mergeTweetLists(grokTweets, chromeTweets) {
  const byUrl = new Map();
  for (const tw of grokTweets || []) {
    if (tw?.u) byUrl.set(tw.u, tw);
  }
  for (const tw of chromeTweets || []) {
    if (tw?.u) byUrl.set(tw.u, tw);
  }
  return [...byUrl.values()].sort((a, b) => String(b.d).localeCompare(String(a.d)));
}

export function buildGrokCapturePrompt({ handle, cutoffIso }) {
  const slug = bareHandle(handle);
  const cutoffDate = String(cutoffIso).slice(0, 10);
  return `Use X search to find posts from @${slug} since ${cutoffDate}.

Return ONLY a JSON object (no markdown fences):
{"posts":[{"t":"tweet text","u":"https://x.com/${slug}/status/ID","d":"ISO-8601 datetime"}]}

Rules:
- Newest first, up to 50 posts in the date window.
- Every post needs a real x.com status URL in u.
- If no posts found, return {"posts":[]}.`;
}

/** Batch spike prompt — up to 20 handles per xAI allowed_x_handles (perf experiment). */
export function buildGrokBatchCapturePrompt({ handles, cutoffIso, maxPostsPerHandle = 10 }) {
  const slugs = (handles || []).map(bareHandle).filter(Boolean);
  if (!slugs.length) {
    throw new Error("handles required for batch capture prompt");
  }
  if (slugs.length > 20) {
    throw new Error("batch capture supports at most 20 handles (x_search allowed_x_handles)");
  }

  const cutoffDate = String(cutoffIso).slice(0, 10);
  const handleList = slugs.map((s) => `@${s}`).join(", ");
  const slugKeys = slugs.join(", ");

  return `Use X search to find posts from these accounts since ${cutoffDate}: ${handleList}.

Return ONLY a JSON object (no markdown fences):
{"by_handle":{"${slugs[0]}":{"posts":[{"t":"tweet text","u":"https://x.com/${slugs[0]}/status/ID","d":"ISO-8601 datetime"}]}}}

Rules:
- Top-level key by_handle; one entry per handle using bare slug keys: ${slugKeys}.
- Newest first per handle, up to ${maxPostsPerHandle} posts each in the date window.
- Every post needs a real x.com status URL in u.
- If a handle has no posts, use {"posts":[]}.`;
}
