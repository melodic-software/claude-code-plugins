import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { parseBriefing } from "../lib/parse-briefing.js";

/** Write `markdown` to a throwaway temp briefing, run `run(briefingPath)`, then
 *  delete the temp dir. Awaiting `run` inside the try is load-bearing: it keeps
 *  the dir alive until parsing finishes and lets assertion failures propagate. */
async function withBriefing(markdown, run) {
  const dir = await mkdtemp(path.join(tmpdir(), "ai-briefing-"));
  const briefingPath = path.join(dir, "meeting.md");
  await writeFile(briefingPath, markdown, "utf-8");
  try {
    return await run(briefingPath);
  } finally {
    await rm(dir, { force: true, recursive: true });
  }
}

test("parseBriefing strips metadata labels from bold header fields", async () => {
  await withBriefing(
    `# AI Briefing - Meeting #21

**Window:** 2026-05-01T00:00:00Z -> 2026-05-08T00:00:00Z (~7d)
**Sources:** 12 items across 3 feeds

## OpenAI
### HIGH
- **New model**: Useful launch detail. - https://example.com/model
`,
    async (briefingPath) => {
      const briefing = await parseBriefing(briefingPath);

      assert.equal(briefing.meta.meetingNumber, 21);
      assert.equal(briefing.meta.window, "2026-05-01T00:00:00Z -> 2026-05-08T00:00:00Z (~7d)");
      assert.equal(briefing.meta.sourcesLine, "12 items across 3 feeds");
    },
  );
});

test("parseBriefing tolerates malformed URLs in bullet sources", async () => {
  // Bare host without scheme would throw inside `new URL()` if dateFromUrl
  // did not guard. This shape is reachable because synthesize-agent emits
  // `urls` as `z.string().min(1)` — not strict URLs.
  await withBriefing(
    `# AI Briefing - Meeting #21

**Window:** 2026-05-01T00:00:00Z -> 2026-05-08T00:00:00Z (~7d)
**Sources:** 1 item across 1 feed

## OpenAI
### HIGH
- **Bad URL item**: should not crash build. - github.com/org/repo
  - not-a-url
`,
    async (briefingPath) => {
      const briefing = await parseBriefing(briefingPath);
      assert.equal(briefing.meta.meetingNumber, 21);
    },
  );
});
