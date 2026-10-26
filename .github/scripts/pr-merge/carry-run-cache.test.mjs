// carry-run-cache.mjs: only reads that cannot change reach the next pr-merge
// run, each under a carried-* name the reader uses only to count a FAIL. The kept and dropped sections follow
// babysit_run_cache.py's readers (babysit_verify_evidence.py: run-record,
// fail-head-ref, on-branch; babysit_merge*.py: the MAX_AGE-bounded and
// credential-keyed ones); record shapes follow GET .../actions/runs/{id}.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { carry, main } from "./carry-run-cache.mjs";

const REPO = "example-org/example-repo";
const NOW = Date.parse("2026-10-19T12:00:00+00:00");
const AT = "2026-10-19T11:00:00+00:00";
const MAIN_SHA = "c".repeat(40);
const opts = { repo: REPO, branch: "main", now: NOW };
const entry = (value, at = AT) => ({ at, value });
const origin = (id, overrides = {}) => ({
  id,
  path: ".github/workflows/pr-verify.yml",
  event: "workflow_run",
  head_branch: "main",
  head_sha: MAIN_SHA,
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  status: "completed",
  conclusion: "failure",
  run_attempt: 1,
  run_started_at: "2026-10-19T10:00:00Z",
  ...overrides,
});

test("keeps origin run records, FAIL head refs and run heads on main, each under a carried name", () => {
  const kept = carry(
    {
      "run-record": { [`${REPO}|7`]: entry(origin(7)) },
      "carried-run-record": { [`${REPO}|6`]: entry(origin(6)) },
      "fail-head-ref": { [`${REPO}|70`]: entry({ head_ref: "feat/x" }) },
      "carried-fail-head-ref": { [`${REPO}|60`]: entry({ head_ref: "feat/y" }) },
      "on-branch": { [`${REPO}|${MAIN_SHA}...main`]: entry(true) },
      "carried-on-branch": { [`${REPO}|${"e".repeat(40)}...main`]: entry(true) },
    },
    opts,
  );
  assert.deepEqual(kept, {
    "carried-run-record": { [`${REPO}|6`]: entry(origin(6)), [`${REPO}|7`]: entry(origin(7)) },
    "carried-fail-head-ref": {
      [`${REPO}|60`]: entry({ head_ref: "feat/y" }),
      [`${REPO}|70`]: entry({ head_ref: "feat/x" }),
    },
    "carried-on-branch": {
      [`${REPO}|${"e".repeat(40)}...main`]: entry(true),
      [`${REPO}|${MAIN_SHA}...main`]: entry(true),
    },
  });
});

test("trims a run record's repositories to their names, keeping every other field", () => {
  const full = { full_name: REPO, id: 1, owner: { login: "o" }, description: "x".repeat(99) };
  const kept = carry(
    {
      "run-record": { [`${REPO}|7`]: entry(origin(7, { repository: full, head_repository: { ...full } })) },
      "carried-run-record": { [`${REPO}|6`]: entry(origin(6)) },
    },
    opts,
  );
  assert.deepEqual(kept["carried-run-record"], {
    [`${REPO}|6`]: entry(origin(6)),
    [`${REPO}|7`]: entry(origin(7)),
  });
});

test("drops every section that can change between runs", () => {
  const sections = [
    "permission",
    "default-branch",
    "max-in-flight",
    "acting-login",
    "identity-only",
    "human-gated-label",
    "branch-rules",
    "queue-sweep",
    "trusted-humans",
  ];
  const restored = Object.fromEntries(sections.map((s) => [s, { [REPO]: entry("x") }]));
  // A section the reader trusts is never restored under its name: the
  // restored entry may come from any job in the default branch's scope.
  for (const s of ["on-branch", "run-record", "fail-head-ref"]) restored[s] = {};
  restored["on-branch"][`${REPO}|${MAIN_SHA}...main`] = entry(true);
  restored["run-record"][`${REPO}|7`] = entry(origin(7));
  restored["fail-head-ref"][`${REPO}|70`] = entry({ head_ref: "feat/x" });
  const kept = carry(restored, opts);
  assert.deepEqual(Object.keys(kept).sort(), ["carried-fail-head-ref", "carried-on-branch", "carried-run-record"]);
});

test("drops a run record that would turn a FAIL away", () => {
  const forgeries = {
    "another workflow": { path: ".github/workflows/pr-require-checks.yml" },
    "a pull_request run": { event: "pull_request" },
    "a branch other than main": { head_branch: "feat/x" },
    "another repository": { repository: { full_name: "someone/fork" } },
    "a fork head": { head_repository: { full_name: "someone/fork" } },
    "a malformed run head": { head_sha: "c".repeat(39) },
    "another run's record": { id: 8 },
  };
  for (const [label, overrides] of Object.entries(forgeries)) {
    const kept = carry({ "run-record": { [`${REPO}|7`]: entry(origin(7, overrides)) } }, opts);
    assert.deepEqual(kept["carried-run-record"], {}, label);
  }
  const otherRepo = carry({ "run-record": { "someone/fork|7": entry(origin(7)) } }, opts);
  assert.deepEqual(otherRepo["carried-run-record"], {});
});

test("drops a head ref or run head of no known shape", () => {
  const kept = carry(
    {
      "fail-head-ref": {
        [`${REPO}|None`]: entry({ head_ref: "feat/x" }),
        [`${REPO}|71`]: entry({ head_ref: null }),
        [`${REPO}|72`]: entry("feat/x"),
      },
      "on-branch": {
        [`${REPO}|${MAIN_SHA}...feat/x`]: entry(true),
        [`someone/fork|${MAIN_SHA}...main`]: entry(true),
        [`${REPO}|${"d".repeat(40)}...main`]: entry(false),
      },
    },
    opts,
  );
  assert.deepEqual(kept["carried-fail-head-ref"], {});
  assert.deepEqual(kept["carried-on-branch"], {});
});

test("drops an entry dated in the future, with no zone, or past the 90-day retention", () => {
  const key = `${REPO}|${MAIN_SHA}...main`;
  for (const at of ["2026-10-19T13:00:00+00:00", "2026-10-19T11:00:00", "2026-07-20T11:59:00+00:00"]) {
    assert.deepEqual(carry({ "on-branch": { [key]: entry(true, at) } }, opts)["carried-on-branch"], {}, at);
  }
  // 89 days old is still inside the retention.
  assert.deepEqual(
    Object.keys(carry({ "on-branch": { [key]: entry(true, "2026-07-22T12:00:00+00:00") } }, opts)["carried-on-branch"]),
    [key],
  );
});

test("carries file to file, and writes nothing when the file is missing or unreadable", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "carry-run-cache-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const from = join(dir, "from.json");
  const to = join(dir, "to.json");
  const output = join(dir, "output");
  const env = { CARRY_FROM: from, CARRY_TO: to, GITHUB_REPOSITORY: REPO, GITHUB_OUTPUT: output };
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(line));

  main(env, NOW);
  assert.equal(existsSync(to), false);
  writeFileSync(from, "{not json");
  main(env, NOW);
  assert.equal(existsSync(to), false);
  assert.match(logs.at(-1), /^::warning::the run cache was not carried: /);
  assert.equal(existsSync(output), false);

  writeFileSync(from, JSON.stringify({ "trusted-humans": { [REPO]: entry([1]) }, "run-record": { [`${REPO}|7`]: entry(origin(7)) } }));
  main(env, NOW);
  assert.deepEqual(JSON.parse(readFileSync(to, "utf8")), {
    "carried-run-record": { [`${REPO}|7`]: entry(origin(7)) },
    "carried-fail-head-ref": {},
    "carried-on-branch": {},
  });
  assert.equal(logs.at(-1), "carried-run-record=1 carried-fail-head-ref=0 carried-on-branch=0");
  assert.equal(readFileSync(output, "utf8"), "carried=true\n");
});
