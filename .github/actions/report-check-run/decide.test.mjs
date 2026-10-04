import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { decide } from "./decide.mjs";

const HEAD = "a".repeat(40);
const OTHER = "b".repeat(40);
const FALLBACK = "f".repeat(40);
// The enum and map from contract-spec SkipReason and GateSkipReasons, typed
// out by hand so the table is tested against the contract, not the files.
const SKIP_REASONS = [
  "not-applicable-paths",
  "not-applicable",
  "prerequisite-missing",
  "cost-gated",
  "awaiting-human",
  "superseded-sha",
  "disabled-by-config",
  "untrusted-trigger",
];
const GATE_SKIP_REASONS = {
  "kill-switch": "prerequisite-missing",
  "list-unreadable": "prerequisite-missing",
  fork: "untrusted-trigger",
  "no-pr": "untrusted-trigger",
  "untrusted-actor": "untrusted-trigger",
  "untrusted-author": "untrusted-trigger",
};

const PROCEED = { proceed: "true", reason: "ok" };

function verdict(overrides = {}) {
  return {
    version: 1,
    lane: "pr-refine",
    activity: "simplify",
    "run-url": "https://github.com/o/r/actions/runs/1",
    "head-sha": HEAD,
    gates: { "kill-switch": PROCEED, trigger: PROCEED },
    config: "valid",
    "skip-reason": null,
    outcome: "success",
    "dirty-tree": null,
    ...overrides,
  };
}

function inputs(overrides = {}) {
  return {
    lane: "pr-refine",
    activity: "simplify",
    runResult: "success",
    actOutcome: "success",
    gateReason: "",
    headSha: HEAD,
    signedCommits: { all_verified: true },
    headShaFallback: FALLBACK,
    gateSkipReasons: GATE_SKIP_REASONS,
    skipReasons: SKIP_REASONS,
    ...overrides,
  };
}

function gateStop(reason, gate = "trigger") {
  return {
    "kill-switch":
      gate === "kill-switch" ? { proceed: "false", reason } : PROCEED,
    trigger: gate === "kill-switch" ? null : { proceed: "false", reason },
  };
}

// A gate stop as both the run job's outputs (env) and the verdict copy see it.
function stoppedAt(reason, { gate = "trigger", headSha = HEAD } = {}) {
  return {
    verdict: verdict({
      gates: gateStop(reason, gate),
      "head-sha": headSha || null,
      config: "not-read",
      outcome: "not-run",
    }),
    inputs: inputs({ gateReason: reason, headSha, actOutcome: "skipped" }),
  };
}

const posted = (decision) => {
  assert.equal(decision.kind, "post");
  return decision.report;
};

test("success posts a completed success check named lane / activity on the env head", () => {
  const report = posted(decide(verdict(), inputs()));
  assert.equal(report.name, "pr-refine / simplify");
  assert.equal(report.head_sha, HEAD);
  assert.equal(report.status, "completed");
  assert.equal(report.conclusion, "success");
  assert.equal(typeof report.output.title, "string");
  assert.equal(typeof report.output.summary, "string");
});

test("success needs no signed-commit result when the activity cannot commit", () => {
  const report = posted(decide(verdict(), inputs({ signedCommits: null })));
  assert.equal(report.conclusion, "success");
});

test("a cancelled run with a newer PR head posts neutral superseded-sha even over a success verdict", () => {
  const report = posted(
    decide(verdict(), inputs({ runResult: "cancelled", prHeadSha: OTHER })),
  );
  assert.equal(report.conclusion, "neutral");
  assert.equal(report.head_sha, HEAD);
  assert.match(report.output.summary, /superseded-sha/);
});

test("a cancelled run with no verdict and no env head posts neutral superseded-sha on the fallback head", () => {
  const report = posted(
    decide(
      null,
      inputs({
        runResult: "cancelled",
        actOutcome: "",
        headSha: "",
        prHeadSha: OTHER,
      }),
    ),
  );
  assert.equal(report.conclusion, "neutral");
  assert.equal(report.head_sha, FALLBACK);
  assert.match(report.output.summary, /superseded-sha/);
});

const NOT_SUPERSEDED = "The run was cancelled and no newer head superseded it.";

test("a cancelled run whose PR head is still the run's head posts failure", () => {
  const report = posted(
    decide(verdict(), inputs({ runResult: "cancelled", prHeadSha: HEAD })),
  );
  assert.equal(report.conclusion, "failure");
  assert.equal(report.head_sha, HEAD);
  assert.equal(report.output.summary, NOT_SUPERSEDED);
});

test("a cancelled run with no PR head posts failure", () => {
  for (const prHeadSha of ["", undefined]) {
    const report = posted(
      decide(verdict(), inputs({ runResult: "cancelled", prHeadSha })),
    );
    assert.equal(report.conclusion, "failure");
    assert.equal(report.output.summary, NOT_SUPERSEDED);
  }
});

test("a cancelled run with a PR head that is not 40 hex posts failure", () => {
  for (const prHeadSha of ["abc", OTHER.toUpperCase(), `${OTHER}0`]) {
    const report = posted(
      decide(verdict(), inputs({ runResult: "cancelled", prHeadSha })),
    );
    assert.equal(report.conclusion, "failure");
  }
});

test("no verdict artifact posts failure on the env head", () => {
  const report = posted(decide(null, inputs()));
  assert.equal(report.conclusion, "failure");
  assert.equal(report.head_sha, HEAD);
});

test("no verdict artifact and no env head posts failure on the fallback head", () => {
  const report = posted(decide(null, inputs({ headSha: "" })));
  assert.equal(report.conclusion, "failure");
  assert.equal(report.head_sha, FALLBACK);
});

test("a malformed verdict posts failure on the env head", () => {
  for (const bad of [
    "not json",
    [],
    verdict({ version: 2 }),
    verdict({ outcome: "great" }),
    verdict({ config: "maybe" }),
    verdict({ gates: null }),
    verdict({ gates: { trigger: { proceed: true } } }),
    verdict({ "head-sha": 42 }),
    verdict({ "dirty-tree": "no" }),
  ]) {
    const report = posted(decide(bad, inputs()));
    assert.equal(report.conclusion, "failure", JSON.stringify(bad));
    assert.equal(report.head_sha, HEAD);
  }
});

test("config: invalid posts failure", () => {
  const report = posted(
    decide(verdict({ config: "invalid", outcome: "not-run" }), inputs()),
  );
  assert.equal(report.conclusion, "failure");
});

test("a verdict lane mismatch with the inputs posts failure under the input name", () => {
  const report = posted(decide(verdict({ lane: "pr-merge" }), inputs()));
  assert.equal(report.conclusion, "failure");
  assert.equal(report.name, "pr-refine / simplify");
});

test("a verdict activity mismatch with the inputs posts failure under the input name", () => {
  const report = posted(decide(verdict({ activity: "explain" }), inputs()));
  assert.equal(report.conclusion, "failure");
  assert.equal(report.name, "pr-refine / simplify");
});

test("a verdict head-sha mismatch with env posts failure on the env head", () => {
  const report = posted(decide(verdict({ "head-sha": OTHER }), inputs()));
  assert.equal(report.conclusion, "failure");
  assert.equal(report.head_sha, HEAD);
});

test("a verdict with no head-sha while env has one is a mismatch: failure", () => {
  const report = posted(decide(verdict({ "head-sha": null }), inputs()));
  assert.equal(report.conclusion, "failure");
  assert.equal(report.head_sha, HEAD);
});

test("a verdict claiming a no-pr gate stop while the env reason is empty is a mismatch: failure posts", () => {
  const forged = verdict({ gates: gateStop("no-pr"), "head-sha": null });
  const report = posted(decide(forged, inputs({ headSha: "" })));
  assert.equal(report.conclusion, "failure");
  assert.equal(report.head_sha, FALLBACK);
});

test("a verdict whose gates all proceed while env has a gate reason is a mismatch: failure", () => {
  const report = posted(
    decide(verdict(), inputs({ gateReason: "fork", actOutcome: "skipped" })),
  );
  assert.equal(report.conclusion, "failure");
});

// The gate clears head-sha on every stop, so a no-pr stop on pull_request
// reaches the report with only the event's head SHA as the fallback.
test("a no-pr gate stop with no env head SHA posts neutral untrusted-trigger on the fallback head", () => {
  const { verdict: v, inputs: i } = stoppedAt("no-pr", { headSha: "" });
  const report = posted(decide(v, i));
  assert.equal(report.conclusion, "neutral");
  assert.equal(report.head_sha, FALLBACK);
  assert.equal(report.output.summary, "Skip reason: untrusted-trigger");
});

test("an empty env head SHA with a reason other than no-pr posts on the fallback head", () => {
  const { verdict: v, inputs: i } = stoppedAt("fork", { headSha: "" });
  const report = posted(decide(v, i));
  assert.equal(report.conclusion, "neutral");
  assert.equal(report.head_sha, FALLBACK);
  assert.match(report.output.summary, /untrusted-trigger/);
});

test("each gate reason maps to its contract skip reason", () => {
  const expected = [
    ["kill-switch", "kill-switch", "prerequisite-missing"],
    ["trigger", "list-unreadable", "prerequisite-missing"],
    ["trigger", "fork", "untrusted-trigger"],
    ["trigger", "untrusted-actor", "untrusted-trigger"],
    ["trigger", "untrusted-author", "untrusted-trigger"],
  ];
  for (const [gate, reason, skip] of expected) {
    const { verdict: v, inputs: i } = stoppedAt(reason, { gate });
    const report = posted(decide(v, i));
    assert.equal(report.conclusion, "neutral", reason);
    assert.match(report.output.summary, new RegExp(skip), reason);
  }
});

test("an unmapped or prototype-named gate reason posts failure", () => {
  for (const reason of [
    "workflow-change",
    "__proto__",
    "constructor",
    "toString",
  ]) {
    const { verdict: v, inputs: i } = stoppedAt(reason);
    const report = posted(decide(v, i));
    assert.equal(report.conclusion, "failure", reason);
  }
});

test("a verdict gate stop with an empty reason posts failure", () => {
  const report = posted(
    decide(verdict({ gates: gateStop("") }), inputs({ actOutcome: "skipped" })),
  );
  assert.equal(report.conclusion, "failure");
});

test("a gate reason mapped outside the skip-reason enum posts failure", () => {
  const { verdict: v, inputs: i } = stoppedAt("fork");
  const report = posted(
    decide(v, { ...i, gateSkipReasons: { fork: "looks-fine" } }),
  );
  assert.equal(report.conclusion, "failure");
});

test("a skip-reason set posts neutral with that reason in the summary", () => {
  const report = posted(
    decide(
      verdict({ "skip-reason": "disabled-by-config", outcome: "not-run" }),
      inputs({ actOutcome: "skipped" }),
    ),
  );
  assert.equal(report.conclusion, "neutral");
  assert.match(report.output.summary, /disabled-by-config/);
});

test("a skip-reason with an act step that succeeded (script exit 0 with a reason) posts neutral", () => {
  const report = posted(
    decide(verdict({ "skip-reason": "cost-gated" }), inputs()),
  );
  assert.equal(report.conclusion, "neutral");
  assert.match(report.output.summary, /cost-gated/);
});

test("a skip-reason never neutralizes a failed act step", () => {
  const report = posted(
    decide(
      verdict({ "skip-reason": "cost-gated" }),
      inputs({ actOutcome: "failure" }),
    ),
  );
  assert.equal(report.conclusion, "failure");
});

test("a skip-reason never neutralizes an unverified commit", () => {
  const report = posted(
    decide(
      verdict({ "skip-reason": "cost-gated" }),
      inputs({ signedCommits: { all_verified: false } }),
    ),
  );
  assert.equal(report.conclusion, "failure");
});

test("a skip-reason never neutralizes a dirty tree", () => {
  const report = posted(
    decide(
      verdict({ "skip-reason": "cost-gated", "dirty-tree": true }),
      inputs(),
    ),
  );
  assert.equal(report.conclusion, "failure");
});

test("a skip-reason with an act outcome that is neither success nor skipped posts failure", () => {
  for (const actOutcome of ["", "cancelled"]) {
    const report = posted(
      decide(verdict({ "skip-reason": "cost-gated" }), inputs({ actOutcome })),
    );
    assert.equal(report.conclusion, "failure", actOutcome);
  }
});

test("a skip-reason never neutralizes a run job that did not succeed", () => {
  for (const [runResult, actOutcome] of [
    ["failure", "success"],
    ["failure", "skipped"],
    ["skipped", "skipped"],
  ]) {
    const report = posted(
      decide(
        verdict({ "skip-reason": "cost-gated" }),
        inputs({ runResult, actOutcome }),
      ),
    );
    assert.equal(report.conclusion, "failure", `${runResult}|${actOutcome}`);
  }
});

test("a run job that did not succeed posts failure even when the act step succeeded", () => {
  const report = posted(decide(verdict(), inputs({ runResult: "failure" })));
  assert.equal(report.conclusion, "failure");
});

test("every key of the shipped gate-skip-reasons.json posts neutral with its mapped reason", () => {
  const shipped = JSON.parse(
    readFileSync(
      fileURLToPath(new URL("./gate-skip-reasons.json", import.meta.url)),
      "utf8",
    ),
  );
  assert.deepEqual(shipped, GATE_SKIP_REASONS);
  for (const [reason, skip] of Object.entries(shipped)) {
    const { verdict: v, inputs: i } = stoppedAt(reason);
    const report = posted(decide(v, { ...i, gateSkipReasons: shipped }));
    assert.equal(report.conclusion, "neutral", reason);
    assert.equal(report.output.summary, `Skip reason: ${skip}`, reason);
  }
});

test("a skip-reason outside the enum posts failure", () => {
  for (const reason of ["looks-fine", ""]) {
    const report = posted(decide(verdict({ "skip-reason": reason }), inputs()));
    assert.equal(report.conclusion, "failure", reason);
  }
});

test("an unreadable enum (empty list) turns every neutral into failure", () => {
  const report = posted(
    decide(
      verdict(),
      inputs({ runResult: "cancelled", prHeadSha: OTHER, skipReasons: [] }),
    ),
  );
  assert.equal(report.conclusion, "failure");
});

test("actOutcome failure posts failure even when the verdict says success", () => {
  const report = posted(decide(verdict(), inputs({ actOutcome: "failure" })));
  assert.equal(report.conclusion, "failure");
});

test("dirty-tree true posts failure", () => {
  const report = posted(decide(verdict({ "dirty-tree": true }), inputs()));
  assert.equal(report.conclusion, "failure");
});

test("signedCommits all_verified false posts failure", () => {
  const report = posted(
    decide(verdict(), inputs({ signedCommits: { all_verified: false } })),
  );
  assert.equal(report.conclusion, "failure");
});

test("an act step that did not succeed with no skip to explain it posts failure", () => {
  for (const actOutcome of ["skipped", "", "cancelled"]) {
    const report = posted(decide(verdict(), inputs({ actOutcome })));
    assert.equal(report.conclusion, "failure", actOutcome);
  }
});

test("the verdict outcome field cannot turn a failed act step green", () => {
  const report = posted(
    decide(
      verdict({ outcome: "success" }),
      inputs({ actOutcome: "failure", runResult: "failure" }),
    ),
  );
  assert.equal(report.conclusion, "failure");
});

test("a ci-status lane part is refused", () => {
  const decision = decide(
    verdict({ lane: "ci-status" }),
    inputs({ lane: "ci-status" }),
  );
  assert.equal(decision.kind, "refuse");
});

test("a ci-status activity part is refused", () => {
  const decision = decide(
    verdict({ activity: "ci-status" }),
    inputs({ activity: "ci-status" }),
  );
  assert.equal(decision.kind, "refuse");
});

test("a ci-status name is refused even for a cancelled run with no verdict", () => {
  const decision = decide(
    null,
    inputs({ activity: "ci-status", runResult: "cancelled", prHeadSha: OTHER }),
  );
  assert.equal(decision.kind, "refuse");
});

test("a lane or activity that is not a convention name is refused", () => {
  for (const [lane, activity] of [
    ["Pr-Refine", "simplify"],
    ["pr-refine", "simplify / x"],
    ["", "simplify"],
  ]) {
    assert.equal(
      decide(null, inputs({ lane, activity })).kind,
      "refuse",
      `${lane}|${activity}`,
    );
  }
});

test("no output field echoes verdict or gate text", () => {
  const marker = "INJECTED-MARKER";
  const { verdict: v, inputs: i } = stoppedAt(marker);
  v["run-url"] = marker;
  const report = posted(decide(v, i));
  assert.doesNotMatch(JSON.stringify(report), new RegExp(marker));
});
