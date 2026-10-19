import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const SCRIPT = new URL("./log-api-budget.sh", import.meta.url).pathname;

// A `gh` that answers `api -i rate_limit` with the response `gh api -i` prints
// (status line, headers, blank line, body), its used count read per call from
// a file so a test can move it between phases.
function run({ phase, tokens, used, reset = 1792378942, dir }) {
  writeFileSync(join(dir, "used"), String(used));
  writeFileSync(
    join(dir, "gh"),
    `#!/usr/bin/env bash
[[ "$*" == "api -i rate_limit" && -n $GH_TOKEN ]] || exit 9
u=$(cat "${dir}/used")
printf 'HTTP/2.0 200 OK\\r\\nX-Ratelimit-Limit: 5000\\r\\nX-Ratelimit-Remaining: %s\\r\\nX-Ratelimit-Reset: ${reset}\\r\\nX-Ratelimit-Resource: core\\r\\nX-Ratelimit-Used: %s\\r\\n\\r\\n{"resources":{"graphql":{"remaining":4990}}}\\n' $((5000 - u)) "$u"
`,
  );
  chmodSync(join(dir, "gh"), 0o755);
  const summary = join(dir, "summary");
  writeFileSync(summary, "", { flag: "a" });
  const stdout = execFileSync("bash", [SCRIPT], {
    env: { PATH: `${dir}:${process.env.PATH}`, PHASE: phase, TOKENS: tokens, STATE_DIR: join(dir, "state"), GITHUB_STEP_SUMMARY: summary },
    encoding: "utf8",
  });
  return { stdout, summary: readFileSync(summary, "utf8") };
}

test("prints pr-merge's rate line per token and the cost since start", () => {
  const dir = mkdtempSync(join(tmpdir(), "log-api-budget-"));
  try {
    const start = run({ phase: "start", tokens: "github-token t0ken", used: 120, dir });
    assert.equal(
      start.stdout,
      "::notice title=api-budget::start github-token core remaining=4880 used=120 limit=5000 reset=2026-10-19T03:02:22Z graphql remaining=4990\n",
    );
    writeFileSync(join(dir, "summary"), "");
    const end = run({ phase: "end", tokens: "github-token t0ken", used: 135, dir });
    assert.match(end.stdout, / used-since-start=15\n$/);
    assert.equal(
      end.summary,
      "api-budget: end github-token core remaining=4865 used=135 limit=5000 reset=2026-10-19T03:02:22Z graphql remaining=4990 used-since-start=15\ngithub-token-cost=15\n",
    );
    writeFileSync(join(dir, "summary"), "");
    const rolled = run({ phase: "end", tokens: "github-token t0ken", used: 3, reset: 1792382542, dir });
    assert.match(rolled.stdout, / used-since-start=window-rolled\n$/);
    assert.match(rolled.summary, /\ngithub-token-cost=unknown\n$/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("skips an entry with no token or a bad name, and still exits 0", () => {
  const dir = mkdtempSync(join(tmpdir(), "log-api-budget-"));
  try {
    const { stdout } = run({ phase: "start", tokens: "github-token\nBad_Name t0ken", used: 1, dir });
    assert.equal(stdout, "::warning::api-budget: skipped a token entry with no usable name or token\n".repeat(2));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
