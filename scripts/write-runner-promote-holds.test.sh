#!/usr/bin/env bash
# Behavior test: the "Move the PR branch to the lane's commits" step in
# pr-run-activity-write.yml re-reads the PR's labels and draft flag right
# before it moves the PR branch, and drops the lane's commits (awaiting-human)
# when a do-not-merge or human-gated label, or a draft, was set during the run.
# A read it cannot complete moves nothing. Runs the step's github-script body
# with a stub `github`, `core` and `fetch`.
# test-scope: .github/workflows/pr-run-activity-write.yml .github/standards/runner-policy/package.json
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

results=$(
  cd "$ROOT" && node --input-type=module - <<'EOF'
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(`${process.cwd()}/.github/standards/runner-policy/package.json`);
const YAML = require("yaml");

const say = (good, text) => console.log(`${good ? "ok" : "fail"}\t${text}`);
const wf = YAML.parse(readFileSync(".github/workflows/pr-run-activity-write.yml", "utf8"));
const step = wf.jobs.run.steps.find((s) => s.name === "Move the PR branch to the lane's commits");
say(Boolean(step?.with?.script), "the run job has a promote step with a script");

const GATED = "a".repeat(40);
const LANE = "b".repeat(40);
const AsyncFunction = (async () => {}).constructor;

// pull: the GET pulls/<n> body; labels: label names; status and next shape
// the labels answer.
// holdLabels: the hold-label step's output, a JSON array.
async function run({ pull = { draft: false }, labels = [], labelsStatus = 200, labelsNext = false, holdLabels = '["do-not-merge","needs-human"]', headMovesOnRead = false } = {}) {
  const calls = { failed: [], info: [], outputs: {}, updated: [], deleted: [], fetched: [] };
  let head = GATED;
  const github = {
    request: async (_route, { ref }) => ({ data: { object: { sha: ref === "heads/lane" ? LANE : headMovesOnRead && head === GATED ? "c".repeat(40) : head } } }),
    rest: {
      git: {
        updateRef: async ({ ref, sha }) => {
          calls.updated.push(ref);
          head = sha;
        },
        deleteRef: async ({ ref }) => {
          calls.deleted.push(ref);
        },
      },
    },
  };
  const core = {
    info: (m) => calls.info.push(m),
    warning: () => {},
    setFailed: (m) => calls.failed.push(m),
    setOutput: (k, v) => {
      calls.outputs[k] = v;
    },
  };
  const fetch = async (url, { headers }) => {
    calls.fetched.push([url, headers.Authorization]);
    const isLabels = url.includes("/labels");
    const status = isLabels ? labelsStatus : 200;
    return {
      ok: status < 300,
      status,
      headers: { get: () => (isLabels && labelsNext ? '<https://x/?page=2>; rel="next"' : "") },
      json: async () => (isLabels ? labels.map((name) => ({ name })) : pull),
    };
  };
  Object.assign(process.env, {
    HEAD_SHA: GATED,
    HEAD_REF: "feature",
    LANE_BRANCH: "lane",
    MERGE_BASE: "false",
    COMMIT_OUTCOME: "",
    COMMIT_SHA: "",
    THREAD_FILE: "",
    PR_NUMBER: "42",
    HOLD_LABELS: holdLabels,
    READ_TOKEN: "read-only",
    GITHUB_API_URL: "https://api.github.com",
  });
  const context = { repo: { owner: "o", repo: "r" } };
  let threw = null;
  try {
    await new AsyncFunction("github", "core", "context", "fetch", "require", step.with.script)(github, core, context, fetch, require);
  } catch (e) {
    threw = e;
  }
  return { ...calls, threw };
}

let r = await run();
say(r.updated.length === 1 && r.failed.length === 0 && !r.threw && r.outputs["skip-reason"] === "",
  "no hold and not a draft: the PR branch moves to the lane's commits");
say(r.fetched.length === 2 && r.fetched.every(([, auth]) => auth === "Bearer read-only"),
  "the labels and the draft flag are read with the job's read-only token");

for (const label of ["do-not-merge", "needs-human"]) {
  r = await run({ labels: ["bug", label] });
  say(r.updated.length === 0 && r.outputs["skip-reason"] === "awaiting-human" && r.deleted.includes("heads/lane"),
    `a ${label} label added during the run: nothing moves, awaiting-human, the lane branch is deleted`);
}

r = await run({ labels: ["status: blocked-human"], holdLabels: '["do-not-merge","status: blocked-human"]' });
say(r.updated.length === 0 && r.outputs["skip-reason"] === "awaiting-human",
  "the base's own human-gated label is a hold");

r = await run({ labels: ["needs-human"], holdLabels: '["do-not-merge","status: blocked-human","needs-human"]' });
say(r.updated.length === 0 && r.outputs["skip-reason"] === "awaiting-human",
  "a label from the activity's labels-absent list is a hold beside a custom human-gated label");

r = await run({ labels: ["needs-human"], holdLabels: '["do-not-merge"]' });
say(r.updated.length === 1 && r.failed.length === 0 && r.outputs["skip-reason"] === "",
  "a needs-human label outside the hold list (address-feedback's) does not stop the move");

r = await run({ labels: ["do-not-merge"], holdLabels: "[]" });
say(r.updated.length === 0 && r.outputs["skip-reason"] === "awaiting-human",
  "do-not-merge is a hold even when the list omits it");

r = await run({ headMovesOnRead: true });
say(r.updated.length === 0 && r.failed.length === 1 && r.fetched.length === 2,
  "the PR head is re-read after the hold reads, and a moved head moves nothing");

r = await run({ pull: { draft: true } });
say(r.updated.length === 0 && r.outputs["skip-reason"] === "awaiting-human" && r.deleted.includes("heads/lane"),
  "a PR converted to a draft during the run: nothing moves, awaiting-human");

r = await run({ pull: {} });
say(r.updated.length === 0, "a PR whose draft flag does not read false moves nothing");

r = await run({ labelsStatus: 502 });
say(r.updated.length === 0 && (r.threw !== null || r.failed.length > 0) && r.deleted.includes("heads/lane"),
  "a labels read that fails moves nothing and fails the step");

r = await run({ labelsNext: true });
say(r.updated.length === 0 && (r.threw !== null || r.failed.length > 0),
  "more labels than one page moves nothing and fails the step");

r = await run({ holdLabels: "" });
say(r.updated.length === 0 && r.failed.length === 1, "no hold labels from the base moves nothing and fails the step");

r = await run({ holdLabels: "not json" });
say(r.updated.length === 0 && (r.threw !== null || r.failed.length > 0), "a malformed hold list moves nothing and fails the step");

// The hold-label step: its bash run with a resolved config naming the
// activity's labels-absent, from a directory with no .base tracker file, so
// the human-gated label is the needs-human default.
const { execFileSync } = await import("node:child_process");
const { mkdtempSync, writeFileSync, rmSync } = await import("node:fs");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const holdStep = wf.jobs.run.steps.find((s) => s.id === "hold-label");
// fixRequested: under the review-threads row, the caller's select job's
// fix-requested output (patch-fix-requested).
const holdLabelsFor = (fixRequested, labelsAbsent) => {
  const dir = mkdtempSync(join(tmpdir(), "hold-label-"));
  try {
    const resolved = join(dir, "resolved.json");
    const out = join(dir, "out");
    writeFileSync(resolved, JSON.stringify({ selected: { "applies-when": { "labels-absent": labelsAbsent } } }));
    writeFileSync(out, "");
    execFileSync("bash", ["-e", "-c", holdStep.run], { cwd: dir, env: { PATH: process.env.PATH, RESOLVED: resolved, FIX_REQUESTED: fixRequested, GITHUB_OUTPUT: out } });
    return JSON.parse(readFileSync(out, "utf8").replace(/^labels=/, ""));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};
say(String(holdStep?.env?.FIX_REQUESTED) === "${{ inputs.patch-prepare == 'review-threads' && inputs.patch-fix-requested || '' }}",
  "the hold-label step reads the select job's fix-requested only for a patch under the review-threads row");
let holds = holdLabelsFor("true", ["do-not-merge"]);
say(JSON.stringify(holds) === '["do-not-merge"]',
  `a write-access fix request on a needs-human PR lifts only the human-gated hold (${JSON.stringify(holds)})`);
holds = holdLabelsFor("true", ["needs-human"]);
say(holds.includes("do-not-merge") && holds.includes("needs-human"),
  "do-not-merge stays a hold beside a fix request, and a listed labels-absent label still holds");
for (const requested of ["false", "", "TRUE"]) {
  holds = holdLabelsFor(requested, ["do-not-merge"]);
  say(holds.includes("needs-human") && holds.includes("do-not-merge"),
    `with fix-requested ${JSON.stringify(requested)} the human-gated label stays a hold (${JSON.stringify(holds)})`);
}
EOF
)
if [[ -z "$results" ]]; then
  fail "the check printed nothing; is .github/standards/runner-policy installed?"
fi
while IFS=$'\t' read -r verdict text; do
  [[ -n "$verdict" ]] || continue
  if [[ "$verdict" == ok ]]; then ok "$text"; else fail "$text"; fi
done <<<"$results"

test_harness::report
