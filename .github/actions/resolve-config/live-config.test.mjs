// The repository's own pipeline config, resolved with the real schema,
// vocabulary and trust files. Expected values come from the pr-unblock
// contract (applies-when of resolve-conflicts, the report-escalation leaf) and
// the README's skip reasons, not from resolver output.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { resolve, resolveGrant } from "./resolve.mjs";

const read = (relative) =>
  readFileSync(new URL(relative, import.meta.url), "utf8");
const json = (relative) => JSON.parse(read(relative));
const CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const FILES = {
  config: read(`../../../${CONFIG_PATH}`),
  schema: json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
  vocabulary: json(
    "../../standards/github-actions-conventions/vocabulary.json",
  ),
  laneRules: json("./lane-rules.json"),
  effectGrants: json("./effect-grants.json"),
  activityRules: json("./activity-rules.json"),
};
// A conflicting, ready, unlabeled PR that changed one Markdown file.
const FACTS = {
  event: "dispatch",
  changedPaths: ["docs/guide.md"],
  changedTargets: ["docs/guide.md"],
  labels: [],
  workClasses: [],
  mergeable: "conflicting",
  draft: false,
};
const selected = (lane, activity, facts = {}) =>
  resolve(FILES, {
    lane,
    activity,
    configPath: CONFIG_PATH,
    basePath: ".base",
    facts: { ...FACTS, ...facts },
  }).selected;
const skipReason = (lane, activity, facts) => {
  const slot = selected(lane, activity, facts);
  assert.equal(slot.applies, false);
  return slot["skip-reason"];
};

test("live config: resolve-conflicts applies to a conflicting ready PR with prepare merge-base", () => {
  const slot = selected("pr-unblock", "resolve-conflicts");
  assert.equal(slot.applies, true);
  assert.equal(slot.prepare, "merge-base");
  assert.equal(slot.effect, "mutate-branch");
  assert.equal(slot.skill, "source-control:resolve-conflicts");
});

test("live config: resolve-conflicts waits for a human while a hold label is on the PR", () => {
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { labels: ["do-not-merge"] }),
    "awaiting-human",
  );
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { labels: ["needs-human"] }),
    "awaiting-human",
  );
});

test("live config: resolve-conflicts does not apply to a draft or a clean PR", () => {
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { draft: true }),
    "not-applicable",
  );
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { mergeable: "clean" }),
    "not-applicable",
  );
});

test("live config: resolve-conflicts skips prerequisite-missing on unknown mergeability", () => {
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { mergeable: null }),
    "prerequisite-missing",
  );
});

test("live config: report-escalation applies and is granted publish-artifact only", () => {
  assert.equal(selected("pr-unblock", "report-escalation").applies, true);
  assert.deepEqual(
    resolveGrant(FILES, {
      lane: "pr-unblock",
      activity: "report-escalation",
      configPath: CONFIG_PATH,
    }),
    {
      effect: "publish-artifact",
      grant: { contents: "read", "pull-requests": "write", issues: "write" },
    },
  );
});

// Expected values from #7032's acceptance criteria and effect-grants.json.
test("live config: pr-unblock runs its slots in order", () => {
  const { lane } = resolve(FILES, {
    lane: "pr-unblock",
    activity: "resolve-conflicts",
    configPath: CONFIG_PATH,
    basePath: ".base",
    facts: FACTS,
  });
  assert.deepEqual(
    lane.slots.map((slot) => slot.activity ?? slot.name),
    [
      "resolve-conflicts",
      "address-feedback",
      "publish-feedback",
      "review-dependency",
      "apply-dependency-verdict",
      "fix-ci",
      "apply-ci-fix",
      "report-escalation",
    ],
  );
});

test("live config: address-feedback applies to a ready PR with comments --ci and prepare review-threads", () => {
  const slot = selected("pr-unblock", "address-feedback", { mergeable: "clean" });
  assert.equal(slot.applies, true);
  assert.equal(slot["reads-untrusted"], true);
  assert.equal(slot.skill, "source-control:pull-request");
  assert.equal(slot.args, "comments --ci");
  assert.equal(slot.prepare, "review-threads");
  assert.deepEqual(
    resolveGrant(FILES, { lane: "pr-unblock", activity: "address-feedback", configPath: CONFIG_PATH }),
    { effect: "mutate-branch", grant: { contents: "write", "pull-requests": "read", issues: "read" } },
  );
});

test("live config: address-feedback waits for a human on do-not-merge and skips a draft", () => {
  for (const labels of [["do-not-merge"], ["do-not-merge", "needs-human"]]) {
    assert.equal(skipReason("pr-unblock", "address-feedback", { labels }), "awaiting-human");
  }
  assert.equal(skipReason("pr-unblock", "address-feedback", { draft: true }), "not-applicable");
});

// needs-human does not skip the slot: the review-threads select step holds a
// needs-human PR unless a write-access trusted person asked for the fix
// (address-feedback.mjs isFixRequest).
test("live config: address-feedback applies to a needs-human PR", () => {
  assert.equal(
    selected("pr-unblock", "address-feedback", { mergeable: "clean", labels: ["needs-human"] }).applies,
    true,
  );
});

test("live config: every other PR activity still waits on needs-human", () => {
  for (const [lane, activity, facts] of [
    ["pr-unblock", "resolve-conflicts", {}],
    ["pr-unblock", "review-dependency", { mergeable: "clean" }],
    ["pr-refine", "fix-docs", {}],
  ]) {
    assert.equal(skipReason(lane, activity, { ...facts, labels: ["needs-human"] }), "awaiting-human", activity);
  }
});

test("live config: publish-feedback runs the reply script after address-feedback, granted publish-artifact only", () => {
  const slot = selected("pr-unblock", "publish-feedback");
  assert.equal(slot.applies, true);
  // It reads the replies the model wrote.
  assert.equal(slot["reads-untrusted"], true);
  assert.equal(slot.script, ".github/scripts/pr-unblock/publish-feedback.mjs");
  assert.deepEqual(slot.needs, ["address-feedback"]);
  assert.deepEqual(
    resolveGrant(FILES, { lane: "pr-unblock", activity: "publish-feedback", configPath: CONFIG_PATH }),
    { effect: "publish-artifact", grant: { contents: "read", "pull-requests": "write", issues: "write" } },
  );
});

test("live config: report-escalation follows every other pr-unblock activity", () => {
  assert.deepEqual(selected("pr-unblock", "report-escalation").needs, [
    "resolve-conflicts",
    "address-feedback",
    "publish-feedback",
    "review-dependency",
    "apply-dependency-verdict",
    "fix-ci",
    "apply-ci-fix",
  ]);
});

test("live config: fix-ci holds no write token and its push job may only write its branch", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "pr-unblock", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("fix-ci"), { effect: "read", grant: { contents: "read", "pull-requests": "read", issues: "read" } });
  assert.deepEqual(grant("apply-ci-fix"), {
    effect: "mutate-branch",
    grant: { contents: "write", "pull-requests": "read", issues: "read" },
  });
  const fix = selected("pr-unblock", "fix-ci");
  assert.equal(fix.prepare, "ci-context");
  assert.equal(fix.args, "ci --ci");
  assert.equal(selected("pr-unblock", "apply-ci-fix").prepare, "apply-patch");
  assert.equal(selected("pr-unblock", "apply-ci-fix").applies, true);
  assert.equal(selected("pr-unblock", "fix-ci", { labels: ["needs-human"] }).applies, false);
});

test("live config: review-dependency may only write its branch; its verdict job may only write PRs and issues", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "pr-unblock", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("review-dependency"), {
    effect: "mutate-branch",
    grant: { contents: "write", "pull-requests": "read", issues: "read" },
  });
  assert.deepEqual(grant("apply-dependency-verdict"), {
    effect: "publish-artifact",
    grant: { contents: "read", "pull-requests": "write", issues: "write" },
  });
  const review = selected("pr-unblock", "review-dependency");
  assert.equal(review.prepare, "dependency-review");
  assert.equal(review.args, "dependency --ci");
  assert.equal(selected("pr-unblock", "apply-dependency-verdict").script, ".github/scripts/pr-unblock/apply-dependency-verdict.mjs");
});

// An agent-ready label event on an issue. The lane went live at
// 2026-10-14T19:21:59Z, the labeled-after time in the live config.
const ISSUE = {
  event: "labeled",
  labels: ["agent-ready"],
  labeledAt: "2026-10-20T00:00:00Z",
};

// Owner decision 2026-10-17: the agent-ready label alone admits the issue;
// no marker comment and no work-class label admits or refuses it.
test("live config: resolve-issue starts on the agent-ready label alone, whatever its work-class label", () => {
  for (const labels of [
    ["agent-ready"],
    ["agent-ready", "work-class: read-only"],
    ["agent-ready", "work-class: scoped"],
    ["agent-ready", "work-class: structural"],
  ]) {
    assert.equal(selected("work-resolve-issue", "resolve-issue", { ...ISSUE, labels }).applies, true, labels.join());
  }
});

// The holds stay: a person decides these, so the issue waits for them.
test("live config: resolve-issue starts nothing for an issue carrying a hold label", () => {
  for (const hold of ["needs-human", "needs-owner-decision", "status: needs-decision"]) {
    assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: ["agent-ready", hold] }), "awaiting-human", hold);
  }
});

// Codex P1 on #7780: the label alone admits, so its removal while a run waits
// stops the run; the labels are read when the run starts.
test("live config: resolve-issue starts nothing once agent-ready is gone from the issue", () => {
  assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: [] }), "not-applicable");
  assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: ["bug"] }), "not-applicable");
});

test("live config: resolve-issue still needs the agent-ready label event after the go-live time", () => {
  assert.equal(
    skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labeledAt: "2026-10-14T19:21:58Z" }),
    "not-applicable",
  );
  assert.equal(
    skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, event: "dispatch" }),
    "not-applicable",
  );
});

// The run must pass the fragment format check before it reports done.
test("live config: resolve-issue may run the changelog fragment check", () => {
  assert.deepEqual(selected("work-resolve-issue", "resolve-issue", ISSUE).checks, [
    "scripts/check-changelog-fragments.sh --check",
  ]);
});

// #7597: the issue's done-when runs the can't-fail scan, a read-only checker.
// #7685 and #7686: one test file at a time, and git mv and git rm, in the checkout.
// #7840 (owner decision 2026-10-17): skill-quality's two checks; check-skill.sh
// runs each skill's test scripts, without the GitHub token.
// Runs 39092789214 and 39092790956: the lane was denied new-changelog-fragment.sh.
test("live config: resolve-issue may run the can't-fail scan, one test file, git mv or rm, the shared-copy sync, skill-quality's checks and the fragment writer; no other activity lists verify-scripts", () => {
  assert.deepEqual(selected("work-resolve-issue", "resolve-issue", ISSUE)["verify-scripts"], [
    "plugins/testing/skills/audit/scripts/cant-fail-scan.sh",
    "scripts/run-test-file.sh",
    "scripts/git-mv-rm.sh",
    "plugins/skill-quality/scripts/check-skill.sh",
    "plugins/skill-quality/scripts/check-evals-quality.sh",
    "scripts/sync-shared-copies.sh",
    "scripts/new-changelog-fragment.sh",
  ]);
  const doc = parse(FILES.config);
  const others = Object.entries(doc.activities).filter(([name, a]) => name !== "resolve-issue" && a["verify-scripts"]);
  assert.deepEqual(others, []);
});

// Owner decision 2026-10-14: the run may read any web page.
test("live config: resolve-issue may read any domain; review-dependency reads release-note hosts; no other activity reads the web", () => {
  assert.deepEqual(selected("work-resolve-issue", "resolve-issue", ISSUE)["web-access"], { enabled: true, domains: "any" });
  const doc = parse(FILES.config);
  assert.deepEqual(doc.activities["review-dependency"]["web-access"], {
    enabled: true,
    domains: ["github.com", "raw.githubusercontent.com", "www.npmjs.com", "registry.npmjs.org", "pypi.org"],
  });
  const others = Object.entries(doc.activities).filter(
    ([name, a]) => !["resolve-issue", "review-dependency"].includes(name) && a["web-access"]?.enabled,
  );
  assert.deepEqual(others, []);
});

test("live config: resolve-issue may only write its branch; report-outcome may only write PRs and issues", () => {
  const grant = (activity) =>
    resolveGrant(FILES, { lane: "work-resolve-issue", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("resolve-issue"), {
    effect: "mutate-branch",
    grant: { contents: "write", "pull-requests": "read", issues: "read" },
  });
  assert.deepEqual(grant("report-outcome"), {
    effect: "publish-artifact",
    grant: { contents: "read", "pull-requests": "write", issues: "write" },
  });
});

test("live config: label-unblocked may only write issues", () => {
  assert.deepEqual(resolveGrant(FILES, { lane: "work-unblock", activity: "label-unblocked", configPath: CONFIG_PATH }), {
    effect: "mutate-tracker",
    grant: { contents: "read", "pull-requests": "read", issues: "write" },
  });
});

test("live config: fix-docs applies to a Markdown change and waits on needs-human", () => {
  assert.equal(selected("pr-refine", "fix-docs").applies, true);
  assert.equal(
    skipReason("pr-refine", "fix-docs", { labels: ["needs-human"] }),
    "awaiting-human",
  );
});

test("live config: fix-docs does not apply to a draft PR", () => {
  assert.equal(skipReason("pr-refine", "fix-docs", { draft: true }), "not-applicable");
});
