// grok-capture-spawn — TDD contracts for cwd/argv/session + bounded concurrency (no live grok).

import path from "node:path";

const ISOLATED_DIR_ERROR_PATTERN = /isolatedDir/;

import {
  buildGrokCaptureArgv,
  buildGrokInspectArgv,
  countGrokInspectInstructions,
  createIsolatedGrokCwd,
  formatGrokCwd,
  mapWithConcurrency,
  resolveGrokCaptureCwd,
  spikeMaxLiveCaptures,
  spikePauseMs,
} from "./lib/grok-capture-spawn.js";
import { buildGrokBatchCapturePrompt } from "./lib/grok-normalize.js";
import { createTestReporter } from "./lib/terminal.js";

const { ok, section, printResults } = createTestReporter();

section("formatGrokCwd / resolveGrokCaptureCwd");

ok(
  "win32 forward slashes when platform win32",
  process.platform !== "win32" || formatGrokCwd("D:\\repo\\scripts") === "D:/repo/scripts",
);

const isolated = createIsolatedGrokCwd("grok-spawn-test-");
ok("createIsolatedGrokCwd returns existing path", path.isAbsolute(isolated));

const isolatedCwd = resolveGrokCaptureCwd("isolated", { isolatedDir: isolated });
ok("isolated mode uses provided dir", isolatedCwd.includes("grok-spawn-test"));

ok(
  "isolated mode throws without isolatedDir",
  (() => {
    try {
      resolveGrokCaptureCwd("isolated");
      return false;
    } catch (e) {
      return ISOLATED_DIR_ERROR_PATTERN.test(e.message);
    }
  })(),
);

const skillCwd = resolveGrokCaptureCwd("skill-scripts", {
  skillScriptsDir: "/tmp/skill-scripts",
});
ok("skill-scripts mode resolves", skillCwd.endsWith("skill-scripts"));

section("buildGrokCaptureArgv");

const argv = buildGrokCaptureArgv({
  prompt: "search @xai",
  cwd: "/tmp/neutral",
  grokModel: "composer-2.5",
  sessionId: "sess-abc",
  resume: "sess-abc",
});

ok("argv ends with -p + prompt", argv.slice(-2).join(" ") === "-p search @xai");
ok("argv includes --cwd before -p", argv.indexOf("--cwd") < argv.indexOf("-p"));
ok("argv includes session flags", argv.includes("--session-id") && argv.includes("--resume"));
ok("argv includes model when set", argv.includes("-m") && argv.includes("composer-2.5"));
ok(
  "no -m when grokModel omitted",
  !buildGrokCaptureArgv({ prompt: "x", cwd: "/tmp" }).includes("-m"),
);

section("buildGrokInspectArgv + countGrokInspectInstructions");

const inspectArgv = buildGrokInspectArgv();
ok("inspect argv includes --json", inspectArgv.includes("--json"));
ok("inspect argv has no --cwd (unsupported on inspect)", !inspectArgv.includes("--cwd"));

const inspectCount = countGrokInspectInstructions(
  JSON.stringify({
    instructions: [{ path: "AGENTS.md" }, { path: "CLAUDE.md" }],
  }),
);
ok("counts instruction array length", inspectCount.instruction_count === 2);

section("buildGrokBatchCapturePrompt");

const batchPrompt = buildGrokBatchCapturePrompt({
  handles: ["@xai", "@cursor"],
  cutoffIso: "2026-06-01T00:00:00.000Z",
});
ok("batch prompt lists handles", batchPrompt.includes("@xai") && batchPrompt.includes("@cursor"));
ok("batch prompt requests by_handle JSON", batchPrompt.includes("by_handle"));

section("mapWithConcurrency");

const order = [];
const concurrent = await mapWithConcurrency(
  [1, 2, 3, 4],
  async (n) => {
    order.push(`start-${n}`);
    await Promise.resolve();
    order.push(`end-${n}`);
    return n * 2;
  },
  2,
);

ok("mapWithConcurrency returns mapped values", concurrent.join(",") === "2,4,6,8");
ok(
  "mapWithConcurrency respects cap (never 3+ simultaneous starts)",
  (() => {
    let maxActive = 0;
    let active = 0;
    for (const token of order) {
      if (token.startsWith("start-")) {
        active += 1;
        maxActive = Math.max(maxActive, active);
      } else {
        active -= 1;
      }
    }
    return maxActive <= 2;
  })(),
);

section("spike guardrails");

ok("default spike pause >= 5s", spikePauseMs() >= 5_000);
ok("default max live captures <= 3", spikeMaxLiveCaptures() <= 3);

const failCount = printResults();
process.exit(failCount > 0 ? 1 : 0);
