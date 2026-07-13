// Synthesize + categorize contract tests — dry-run path, zod schema parsing,
// apolitical filter behavior. Live `claude -p` invocation is not exercised here.

import {
  categorize,
  ItemsArraySchema,
  VALID_BUCKETS,
  VALID_TIERS,
} from "./lib/categorize-agent.js";
import { CandidatesArraySchema, synthesize } from "./lib/synthesize-agent.js";
import { createTestReporter } from "./lib/terminal.js";

const { ok, section, printResults, fail } = createTestReporter();

// Assert a zod schema parses a well-formed value to the expected length.
function expectParses(label, schema, value, expectedLength) {
  try {
    const parsed = schema.parse(value);
    ok(label, parsed.length === expectedLength);
  } catch (e) {
    ok(label, false, e.message);
  }
}

// Assert a zod schema rejects a malformed value (synchronous .parse() throws).
function expectRejects(label, schema, value) {
  let threw = false;
  try {
    schema.parse(value);
  } catch {
    threw = true;
  }
  ok(label, threw);
}

section("synthesize contract\n");

// 4a: dry-run returns empty array
{
  const result = await synthesize({
    handle: "@bcherny",
    priorityBucket: "high_signal_required",
    posts: [{ t: "fake", u: "https://x.com/bcherny/status/1", d: "2026-05-01T00:00" }],
    replies: [],
    seenUrls: new Set(),
    dryRun: true,
  });
  ok("dry-run returns empty array", Array.isArray(result) && result.length === 0);
}

// 4b: synthesize returns [] when posts + replies empty (skip subagent call)
{
  const result = await synthesize({
    handle: "@bcherny",
    priorityBucket: "high_signal_required",
    posts: [],
    replies: [],
    seenUrls: new Set(),
    dryRun: false, // not dry-run, but should short-circuit on empty content
  });
  ok(
    "empty content returns [] without spawning claude",
    Array.isArray(result) && result.length === 0,
  );
}

// 4c: schema accepts well-formed candidates
expectParses(
  "schema parses well-formed candidate",
  CandidatesArraySchema,
  [
    {
      title: "Claude Code v2.1.130 ships",
      summary: "Adds /channels research preview and inline editor for slash commands.",
      urls: ["https://x.com/anthropicai/status/9999"],
      date: "2026-05-02",
      tierHint: "HIGH",
      bucketHint: "anthropic",
    },
  ],
  1,
);

// 4d: schema rejects missing required field (no urls, no date)
expectRejects("schema rejects candidate missing urls", CandidatesArraySchema, [
  { title: "x", summary: "y" },
]);

// 4d2: schema rejects missing date (REQUIRED)
expectRejects("schema rejects candidate missing date", CandidatesArraySchema, [
  { title: "x", summary: "y", urls: ["https://x.com/a/status/1"], tierHint: "HIGH" },
]);

// 4d3: schema rejects malformed date (not ISO YYYY-MM-DD)
expectRejects(
  "schema rejects candidate with non-ISO date (e.g. range form)",
  CandidatesArraySchema,
  [
    {
      title: "x",
      summary: "y",
      urls: ["https://x.com/a/status/1"],
      date: "2026-05-01..2026-05-02",
    },
  ],
);

// 4e: schema rejects invalid tierHint
expectRejects("schema rejects invalid tierHint", CandidatesArraySchema, [
  { title: "x", summary: "y", urls: ["z"], date: "2026-05-01", tierHint: "EXTREME" },
]);

// 4f: empty array is valid (0-K candidates allowed)
expectParses("empty candidates array is valid", CandidatesArraySchema, [], 0);

section("\ncategorize contract\n");

// 5a: dry-run returns empty array
{
  const result = await categorize([{ title: "x", summary: "y", urls: ["z"] }], { dryRun: true });
  ok("dry-run returns empty array", Array.isArray(result) && result.length === 0);
}

// 5b: empty input returns []
{
  const result = await categorize([], { dryRun: false });
  ok(
    "empty input returns [] without spawning claude",
    Array.isArray(result) && result.length === 0,
  );
}

// 5c: schema accepts well-formed item
expectParses(
  "schema parses well-formed item",
  ItemsArraySchema,
  [
    {
      title: "Cursor 0.46 ships Multi-root",
      summary: "IDE adds multi-root workspaces.",
      urls: ["https://x.com/cursor_ai/status/1"],
      date: "2026-05-04",
      bucket: "cursor",
      tier: "HIGH",
    },
  ],
  1,
);

// 5d: schema rejects invalid bucket
expectRejects("schema rejects invalid bucket", ItemsArraySchema, [
  { title: "x", summary: "y", urls: ["z"], date: "2026-05-01", bucket: "invalid", tier: "HIGH" },
]);

// 5e: schema rejects invalid tier
expectRejects("schema rejects invalid tier", ItemsArraySchema, [
  {
    title: "x",
    summary: "y",
    urls: ["z"],
    date: "2026-05-01",
    bucket: "anthropic",
    tier: "CRITICAL",
  },
]);

// 5e2: schema rejects item missing date (REQUIRED)
expectRejects("schema rejects item missing date", ItemsArraySchema, [
  { title: "x", summary: "y", urls: ["z"], bucket: "anthropic", tier: "HIGH" },
]);

// 5f: every valid bucket value is enumerated
{
  const expected = [
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
  const sorted = [...VALID_BUCKETS].sort().join(",");
  const expSorted = expected.sort().join(",");
  ok("VALID_BUCKETS matches plan", sorted === expSorted, `got ${sorted}`);
}

// 5g: every valid tier value is enumerated
{
  const sorted = [...VALID_TIERS].sort().join(",");
  ok("VALID_TIERS matches HIGH/MED/LOW", sorted === "HIGH,LOW,MED", `got ${sorted}`);
}

// ─── Live (non-dry-run) smoke tests — verify claude -p path works for non-MCP tasks ───
// Each spawns a real `claude -p` subprocess (~1 burst request each). Skip via env var
// if running in tight burst-budget contexts: AI_BRIEFING_SKIP_LIVE=1.

const skipLive = process.env.AI_BRIEFING_SKIP_LIVE === "1";

if (skipLive) {
  section("\nLive tests SKIPPED (AI_BRIEFING_SKIP_LIVE=1)");
} else {
  section("\nLive smoke tests (spawns `claude -p` — ~2 burst requests)\n");
  try {
    const result = await synthesize({
      handle: "@AnthropicAI",
      priorityBucket: "high_signal_required",
      posts: [
        {
          t: "Claude Code v2.1.131 ships /channels research preview and inline editor for slash commands.",
          u: "https://x.com/anthropicai/status/9001",
          d: "2026-05-04T15:00",
        },
      ],
      replies: [],
      seenUrls: new Set(),
      dryRun: false,
      timeoutMs: 180_000,
    });
    ok(
      "live synthesize returns array (no exception)",
      Array.isArray(result),
      `typeof=${typeof result}`,
    );
    ok(
      "live synthesize output zod-parses",
      !!CandidatesArraySchema.safeParse(result).success,
      JSON.stringify(result).substring(0, 200),
    );
  } catch (e) {
    ok("live synthesize returns array (no exception)", false, e.message);
  }
  try {
    const result = await categorize(
      [
        {
          title: "Claude Code v2.1.131 ships /channels research preview",
          summary:
            "New /channels feature lets sessions react to GitHub PR webhook events without polling.",
          urls: ["https://x.com/anthropicai/status/9001"],
          date: "2026-05-04",
          tierHint: "HIGH",
          bucketHint: "anthropic",
        },
      ],
      { dryRun: false, timeoutMs: 120_000 },
    );
    ok("live categorize returns array (no exception)", Array.isArray(result));
    ok(
      "live categorize output zod-parses",
      !!ItemsArraySchema.safeParse(result).success,
      JSON.stringify(result).substring(0, 200),
    );
  } catch (e) {
    ok("live categorize returns array (no exception)", false, e.message);
  }
}

printResults();
process.exit(fail > 0 ? 1 : 0);
