// S4 Categorize — assign final {bucket, tier} per candidate.
// Apolitical filter applied first (drop partisan-only).
// Bucket ∈ {anthropic, openai, google, cursor, xai, meta, deepseek, other, extras}
// Tier ∈ {HIGH, MED, LOW}

import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";

import { z } from "zod";

export const VALID_BUCKETS = [
  "anthropic",
  "openai",
  "google",
  "cursor",
  "xai",
  "meta",
  "deepseek",
  "other",
  "extras",
];
export const VALID_TIERS = ["HIGH", "MED", "LOW"];

const MARKDOWN_FENCE_OPEN_REGEX = /^```(?:json)?\s*/i;
const MARKDOWN_FENCE_CLOSE_REGEX = /\s*```$/i;

export const ItemSchema = z.object({
  title: z.string().min(1),
  summary: z.string().min(1),
  urls: z.array(z.string()).min(1),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "must be ISO YYYY-MM-DD"),
  bucket: z.enum(VALID_BUCKETS),
  tier: z.enum(VALID_TIERS),
});

export const ItemsArraySchema = z.array(ItemSchema);

const CATEGORIZE_RULES = `
APOLITICAL FILTER (apply first — DROP these, do not output):
- Politician deepfakes / AI political memes (Trump-Mandalorian, Biden-Sora etc.) UNLESS the AI-industry impact is the core story
- Campaign-AI noise, partisan policy debates, politician's tweets about AI as commentary
- Keep: Anthropic-DoD supply-chain dispute, Musk v Altman trial, EU AI Act enforcement, copyright suits with industry-wide impact

BUCKET ROUTER (mutually exclusive, pick the most specific):
- anthropic: Claude / Claude Code / Claude.ai / Anthropic SDK / Anthropic team / Anthropic safety research
- openai: GPT / Codex / ChatGPT / Sora / OpenAI Agents SDK / OpenAI team / OpenAI brand
- google: Gemini / AI Studio / DeepMind / Google AI / Workspace Agents / TPU
- cursor: Cursor IDE / Anysphere / Cursor SDK / Cloud Agents / leerob (when about Cursor)
- xai: Grok / xAI / Colossus / Grok Voice / X ad platform AI
- meta: Llama / Meta AI / WhatsApp/IG AI / open-weight Meta releases
- deepseek: DeepSeek V/R series / DeepSeek terminal agents
- other: Microsoft / Visual Studio 2026 / VS Code / GitHub Copilot / Augment Code / Cognition Devin / Bun / LangChain / Vercel AI / Firecrawl / Replit / Compute & Infrastructure (NVIDIA chip launches etc.) / Real-world AI / Legal & regulatory (when not provider-specific)
- extras: Robotics / brain emulation / games / science+AI / Flair (viral funny AI items)

TIER RULES (per Standing default #16):
- HIGH = product / IDE / CLI / SDK / plugin updates the engineering team can install/call/configure within a week. Plus: model releases that drop $/token. Plus: real-world deployments at scale. Plus: material legal rulings (verdicts, injunctions, settlements).
- MED = API/SDK changes without immediate user-facing feature, alignment research, valuation rounds, conference substance, JVs, geographic expansion.
- LOW = roadmap promises, partner showcases, accelerator winners, sponsored content, vibe takes, financial projections without dates.
`;

function buildCategorizePrompt(candidates) {
  return `You are categorizing AI-news briefing candidates for an internal engineering meeting.

${CATEGORIZE_RULES}

Input candidates (${candidates.length}):
${JSON.stringify(candidates, null, 2)}

Task:
1. Drop apolitical-filtered items entirely (do not include in output).
2. For each remaining candidate, assign:
   - bucket: one of [${VALID_BUCKETS.join(", ")}]
   - tier: one of [${VALID_TIERS.join(", ")}]
3. Preserve title, summary, urls, date unchanged. \`date\` is REQUIRED ISO YYYY-MM-DD on every output item.

Output ONLY a JSON array of objects with keys: title, summary, urls, date, bucket, tier. No prose, no markdown fences.
First character of response must be '['.
`;
}

function parseClaudeOutput(stdout) {
  let outer;
  try {
    outer = JSON.parse(stdout);
  } catch {
    outer = null;
  }
  const text = outer?.result ?? stdout;
  const trimmed = String(text).trim();
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
  const start = candidate.indexOf("[");
  const end = candidate.lastIndexOf("]");
  if (start >= 0 && end > start) {
    try {
      return JSON.parse(candidate.substring(start, end + 1));
    } catch {
      /* fall through */
    }
  }
  throw new Error(`Could not parse JSON array from output: ${trimmed.substring(0, 300)}`);
}

export async function categorize(
  candidates,
  { claudeBin = "claude", timeoutMs = 120_000, dryRun = false } = {},
) {
  if (dryRun) return [];
  if (!candidates || candidates.length === 0) return [];

  const prompt = buildCategorizePrompt(candidates);

  const tmpDir = path.join(os.tmpdir(), "ai-briefing-runner");
  await fs.mkdir(tmpDir, { recursive: true });
  const promptFile = path.join(tmpDir, `cat-${randomBytes(6).toString("hex")}.md`);
  await fs.writeFile(promptFile, prompt, "utf-8");

  try {
    const r = spawnSync(
      claudeBin,
      ["-p", `@${promptFile}`, "--model", "claude-sonnet-4-6", "--output-format", "json"],
      {
        encoding: "utf-8",
        timeout: timeoutMs,
        maxBuffer: 50 * 1024 * 1024,
      },
    );

    if (r.status !== 0) {
      throw new Error(
        `claude -p (categorize) exit ${r.status}: ${(r.stderr || "").substring(0, 500)}`,
      );
    }

    const raw = parseClaudeOutput(r.stdout);
    return ItemsArraySchema.parse(raw);
  } finally {
    try {
      await fs.unlink(promptFile);
    } catch {
      /* ignore */
    }
  }
}
