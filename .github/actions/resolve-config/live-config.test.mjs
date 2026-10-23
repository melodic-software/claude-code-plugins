// The repository's own pipeline config, resolved with the real schema,
// vocabulary and trust files. Expected values come from the pr-unblock
// contract (applies-when of resolve-conflicts, the report-escalation leaf) and
// the README's skip reasons, not from resolver output.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { checkPatchRules } from "./patch-rules.mjs";
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
  trustedActors: json("../../standards/trusted-actors/trusted-actors.json"),
};
// A conflicting, ready, unlabeled PR that changed one Markdown file; as an
// issue, a listed human set it Small, Low and Known (the org's option ids).
const FACTS = {
  event: "dispatch",
  changedPaths: ["docs/guide.md"],
  changedTargets: ["docs/guide.md"],
  labels: [],
  workClasses: [],
  mergeable: "conflicting",
  draft: false,
  fieldValues: [
    { field: 15462270, option: 27053568 },
    { field: 48625720, option: 85127651 },
    { field: 48625721, option: 85127654 },
  ],
  fieldSetters: { 15462270: 153232337, 48625720: 153232337, 48625721: 153232337 },
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
test("live config: pr-refine is the refine stage: fix-docs, then its push job", () => {
  const { lane } = resolve(FILES, { lane: "pr-refine", activity: "fix-docs", configPath: CONFIG_PATH, basePath: ".base", facts: FACTS });
  assert.equal(lane.stage, "refine");
  assert.deepEqual(lane.slots.map((slot) => slot.activity ?? slot.name), ["fix-docs", "apply-patch"]);
  assert.deepEqual(selected("pr-unblock", "apply-patch").needs, ["fix-ci"]);
});

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
      "apply-feedback-patch",
      "publish-feedback",
      "review-dependency",
      "apply-dependency-patch",
      "apply-dependency-verdict",
      "fix-ci",
      "apply-patch",
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
  // The read runner's model job holds no write token: its fix leaves as a
  // patch, its replies for the reply job.
  assert.deepEqual(
    resolveGrant(FILES, { lane: "pr-unblock", activity: "address-feedback", configPath: CONFIG_PATH }),
    { effect: "read", grant: { contents: "read", "pull-requests": "read", issues: "read" } },
  );
  assert.deepEqual(slot["applied-by"], { patch: "apply-feedback-patch", "feedback-replies": "publish-feedback" });
});

// The push job runs apply-patch.mjs under the review-threads row, may only
// write the branch, and holds a needs-human PR as address-feedback does.
test("live config: apply-feedback-patch pushes address-feedback's patch, granted mutate-branch only", () => {
  const slot = selected("pr-unblock", "apply-feedback-patch");
  assert.equal(slot.applies, true);
  assert.equal(slot.script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(slot.prepare, "apply-patch");
  assert.deepEqual(slot.needs, ["address-feedback"]);
  assert.deepEqual(
    resolveGrant(FILES, { lane: "pr-unblock", activity: "apply-feedback-patch", configPath: CONFIG_PATH }),
    { effect: "mutate-branch", grant: { contents: "write", "pull-requests": "read", issues: "read" } },
  );
  assert.equal(selected("pr-unblock", "apply-feedback-patch", { labels: ["needs-human"] }).applies, true);
  assert.equal(skipReason("pr-unblock", "apply-feedback-patch", { labels: ["do-not-merge"] }), "awaiting-human");
  assert.equal(skipReason("pr-unblock", "apply-feedback-patch", { draft: true }), "not-applicable");
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
  // After the push, so its replies can name the pushed commit.
  assert.deepEqual(slot.needs, ["address-feedback", "apply-feedback-patch"]);
  assert.deepEqual(
    resolveGrant(FILES, { lane: "pr-unblock", activity: "publish-feedback", configPath: CONFIG_PATH }),
    { effect: "publish-artifact", grant: { contents: "read", "pull-requests": "write", issues: "write" } },
  );
});

test("live config: report-escalation follows every pr-unblock activity", () => {
  assert.deepEqual(selected("pr-unblock", "report-escalation").needs, [
    "resolve-conflicts",
    "address-feedback",
    "publish-feedback",
    "review-dependency",
    "apply-dependency-verdict",
    "fix-ci",
    "apply-patch",
  ]);
});

test("live config: fix-ci holds no write token and its push job may only write its branch", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "pr-unblock", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("fix-ci"), { effect: "read", grant: { contents: "read", "pull-requests": "read", issues: "read" } });
  assert.deepEqual(grant("apply-patch"), {
    effect: "mutate-branch",
    grant: { contents: "write", "pull-requests": "read", issues: "read" },
  });
  const fix = selected("pr-unblock", "fix-ci");
  assert.equal(fix.prepare, "ci-context");
  assert.equal(fix.args, "ci --ci");
  assert.deepEqual(fix["applied-by"], { patch: "apply-patch" });
  assert.equal(selected("pr-unblock", "apply-patch").prepare, "apply-patch");
  assert.equal(selected("pr-unblock", "apply-patch").script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(selected("pr-unblock", "apply-patch").applies, true);
  assert.equal(selected("pr-unblock", "fix-ci", { labels: ["needs-human"] }).applies, false);
});

test("live config: review-dependency holds no write token; its push job may only write its branch, its verdict job only PRs and issues", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "pr-unblock", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("review-dependency"), { effect: "read", grant: { contents: "read", "pull-requests": "read", issues: "read" } });
  assert.deepEqual(grant("apply-dependency-patch"), {
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
  assert.deepEqual(review["applied-by"], { patch: "apply-dependency-patch", "dependency-verdict": "apply-dependency-verdict" });
  const push = selected("pr-unblock", "apply-dependency-patch");
  assert.equal(push.script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(push.prepare, "apply-patch");
  assert.deepEqual(push.needs, ["review-dependency"]);
  assert.equal(selected("pr-unblock", "apply-dependency-patch", { labels: ["needs-human"] }).applies, false);
  const verdict = selected("pr-unblock", "apply-dependency-verdict");
  assert.equal(verdict.script, ".github/scripts/pr-unblock/apply-dependency-verdict.mjs");
  // After the push, so the verdict judges what landed.
  assert.deepEqual(verdict.needs, ["review-dependency", "apply-dependency-patch"]);
});

// An agent-ready label event on an issue.
const ISSUE = {
  event: "labeled",
  labels: ["agent-ready"],
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
  for (const hold of ["needs-human", "needs-owner-decision", "status: needs-decision", "status: needs-info"]) {
    assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: ["agent-ready", hold] }), "awaiting-human", hold);
  }
});

// Codex P1 on #7780: the label alone admits, so its removal while a run waits
// stops the run; the labels are read when the run starts.
test("live config: resolve-issue starts nothing once agent-ready is gone from the issue", () => {
  assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: [] }), "not-applicable");
  assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: ["bug"] }), "not-applicable");
});

// No go-live cutoff: an issue labeled agent-ready at any time starts a run.
test("live config: resolve-issue starts on an agent-ready label event, with no label-time cutoff", () => {
  assert.equal(selected("work-resolve-issue", "resolve-issue", { ...ISSUE, labeledAt: "2026-10-14T19:21:58Z" }).applies, true);
});

test("live config: resolve-issue still needs the agent-ready label event", () => {
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

// #8310 (owner decision: option a): the run's own advisory check-affected over
// its uncommitted work, which the runner's run-checks job never reruns.
test("live config: resolve-issue self-checks its uncommitted work with check-affected", () => {
  const leaf = selected("work-resolve-issue", "resolve-issue", ISSUE);
  assert.deepEqual(leaf["self-checks"], ["scripts/check-affected.sh --uncommitted"]);
  assert.ok(!leaf.checks.includes("scripts/check-affected.sh --uncommitted"), leaf.checks.join(" | "));
});

// Code a verify-script runs can read the lane's token from any same-user
// process's /proc/<pid>/environ, so no listed script runs checkout code.
const RUNS_CHECKOUT_CODE = ["scripts/run-test-file.sh", "plugins/skill-quality/scripts/check-skill.sh"];
test("live config: resolve-issue may run the can't-fail scan, git mv or rm, the evals check, the shared-copy sync and the fragment writer, and no script that runs checkout code; no other activity lists verify-scripts", () => {
  const scripts = selected("work-resolve-issue", "resolve-issue", ISSUE)["verify-scripts"];
  assert.deepEqual(scripts, [
    "plugins/testing/skills/audit/scripts/cant-fail-scan.sh",
    "scripts/git-mv-rm.sh",
    "plugins/skill-quality/scripts/check-evals-quality.sh",
    "scripts/sync-shared-copies.sh",
    "scripts/new-changelog-fragment.sh",
  ]);
  for (const script of RUNS_CHECKOUT_CODE) assert.ok(!scripts.includes(script), script);
  const doc = parse(FILES.config);
  const others = Object.entries(doc.activities).filter(([name, a]) => name !== "resolve-issue" && a["verify-scripts"]);
  assert.deepEqual(others, []);
});

// A domain list, not `any`, for resolve-issue: on the write path `any` also
// grants the curl-based docs scripts. fix-docs reads any host from a job with
// no write token, and the launcher stages no docs script.
test("live config: resolve-issue reads official docs hosts only; review-dependency reads release-note hosts; no other activity, fix-docs included, reads the web", () => {
  const web = selected("work-resolve-issue", "resolve-issue", ISSUE)["web-access"];
  assert.notEqual(web.domains, "any");
  assert.deepEqual(web, {
    enabled: true,
    domains: ["code.claude.com", "platform.claude.com", "docs.anthropic.com", "docs.github.com", "nodejs.org", "docs.python.org"],
  });
  const doc = parse(FILES.config);
  assert.deepEqual(doc.activities["review-dependency"]["web-access"], {
    enabled: true,
    domains: ["github.com", "raw.githubusercontent.com", "www.npmjs.com", "registry.npmjs.org", "pypi.org"],
  });
  assert.notEqual(selected("pr-refine", "fix-docs")["web-access"]?.enabled, true);
  const others = Object.entries(doc.activities).filter(
    ([name, a]) => !["resolve-issue", "review-dependency"].includes(name) && a["web-access"]?.enabled,
  );
  assert.deepEqual(others, []);
});

// The model run holds no write token; only the script that
// commits its patch may write a branch.
test("live config: resolve-issue holds no write token; apply-issue-patch may only write its branch; report-outcome may only write PRs and issues", () => {
  const grant = (activity) =>
    resolveGrant(FILES, { lane: "work-resolve-issue", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("resolve-issue"), {
    effect: "read",
    grant: { contents: "read", "pull-requests": "read", issues: "read" },
  });
  assert.deepEqual(grant("apply-issue-patch"), {
    effect: "mutate-branch",
    grant: { contents: "write", "pull-requests": "read", issues: "read" },
  });
  assert.deepEqual(grant("report-outcome"), {
    effect: "publish-artifact",
    grant: { contents: "read", "pull-requests": "write", issues: "write" },
  });
});

// activity-rules.json is trust-root data: a config that gives resolve-issue a
// write effect again is refused.
test("live config: resolve-issue with a write effect is refused", () => {
  const writes = FILES.config.replace(
    "effect: read\n    applied-by:\n      patch: apply-issue-patch\n      work-outcome: report-outcome\n",
    "effect: mutate-branch\n",
  );
  assert.notEqual(writes, FILES.config);
  assert.throws(
    () => resolve({ ...FILES, config: writes }, { lane: "work-resolve-issue", activity: "resolve-issue", configPath: CONFIG_PATH, basePath: ".base", facts: { ...FACTS, ...ISSUE } }),
    (error) => error.code === "forbidden-by-activity",
  );
});

test("live config: work-resolve-issue runs resolve-issue, then apply-issue-patch, then report-outcome", () => {
  const { lane } = resolve(FILES, {
    lane: "work-resolve-issue",
    activity: "resolve-issue",
    configPath: CONFIG_PATH,
    basePath: ".base",
    facts: { ...FACTS, ...ISSUE },
  });
  assert.deepEqual(
    lane.slots.map((slot) => [slot.activity ?? slot.name, slot.needs ?? []]),
    [
      ["resolve-issue", []],
      ["apply-issue-patch", ["resolve-issue"]],
      ["report-outcome", ["resolve-issue", "apply-issue-patch"]],
    ],
  );
});

test("live config: apply-issue-patch runs apply-patch.mjs and holds on the issue's holds and a missing agent-ready", () => {
  const slot = selected("work-resolve-issue", "apply-issue-patch", ISSUE);
  assert.equal(slot.applies, true);
  assert.equal(slot.script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(slot.prepare, "apply-patch");
  assert.deepEqual(slot.needs, ["resolve-issue"]);
  // Every hold that keeps resolve-issue from starting also drops its patch,
  // and the patch needs the label resolve-issue needs.
  const { activities } = parse(FILES.config);
  const holds = activities["resolve-issue"]["applies-when"]["labels-absent"];
  const applyHolds = new Set(activities["apply-issue-patch"]["applies-when"]["labels-absent"]);
  assert.ok(holds.length > 0);
  assert.deepEqual(holds.filter((hold) => !applyHolds.has(hold)), [], "apply-issue-patch's labels-absent covers resolve-issue's");
  assert.deepEqual(activities["apply-issue-patch"]["applies-when"].labels, activities["resolve-issue"]["applies-when"].labels);
  for (const hold of applyHolds) {
    assert.equal(skipReason("work-resolve-issue", "apply-issue-patch", { ...ISSUE, labels: ["agent-ready", hold] }), "awaiting-human", hold);
  }
  assert.equal(skipReason("work-resolve-issue", "apply-issue-patch", { ...ISSUE, labels: [] }), "not-applicable");
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

// The model run holds no write token; only the script that pushes its patch
// may write the branch, from its own job in pr-refine.
test("live config: fix-docs holds no write token and its push job in pr-refine may only write its branch", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "pr-refine", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("fix-docs"), { effect: "read", grant: { contents: "read", "pull-requests": "read", issues: "read" } });
  assert.deepEqual(grant("apply-patch"), {
    effect: "mutate-branch",
    grant: { contents: "write", "pull-requests": "read", issues: "read" },
  });
  const fix = selected("pr-refine", "fix-docs");
  assert.equal(fix.prepare, undefined, "no prepare mode: apply-patch takes the default row");
  assert.deepEqual(fix["applied-by"], { patch: "apply-patch" });
  const apply = selected("pr-refine", "apply-patch");
  assert.deepEqual(apply.needs, ["fix-docs"]);
  assert.equal(apply.script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(apply.prepare, "apply-patch");
});

// Under run-claude-cli's env scrub the CLI forces the default mode for
// auto, so no activity asks for it; fix-docs takes the dontAsk default and
// runs only what the stage's allow rules name.
test("live config: no activity sets permission-mode", () => {
  assert.equal(selected("pr-refine", "fix-docs")["permission-mode"], undefined);
  const { activities } = parse(FILES.config);
  assert.deepEqual(Object.keys(activities).filter((name) => Object.hasOwn(activities[name], "permission-mode")), []);
});

// fix-docs hands on a patch, so its targets leave out instruction surfaces
// and CODEOWNERS paths, as a write activity's do.
test("live config: fix-docs is not asked to fix an instruction surface", () => {
  const slot = selected("pr-refine", "fix-docs", { changedTargets: ["docs/guide.md", "CLAUDE.md", "plugins/p/skills/s/SKILL.md"] });
  assert.deepEqual(slot["changed-paths"], ["docs/guide.md"]);
});

// activity-rules.json is trust-root data: a config that gives fix-docs a
// write effect again is refused.
test("live config: fix-docs with a write effect is refused", () => {
  const writes = FILES.config.replace("effect: read\n    applied-by:\n      patch: apply-patch\n", "effect: mutate-branch\n");
  assert.notEqual(writes, FILES.config);
  assert.throws(
    () => resolve({ ...FILES, config: writes }, { lane: "pr-refine", activity: "fix-docs", configPath: CONFIG_PATH, basePath: ".base", facts: FACTS }),
    (error) => error.code === "forbidden-by-activity",
  );
});

// Each activity's applied-by lands with the phase that moves it to the read
// runner, after the broker serves a reader that knows the field; fix-docs,
// address-feedback, review-dependency, fix-ci and resolve-issue so far.
test("live config: only fix-docs, address-feedback, review-dependency, fix-ci and resolve-issue set applied-by, each to its own appliers", () => {
  const { activities } = parse(FILES.config);
  assert.deepEqual(
    Object.entries(activities)
      .filter(([, activity]) => Object.hasOwn(activity, "applied-by"))
      .map(([name, activity]) => [name, activity["applied-by"]]),
    [
      ["fix-docs", { patch: "apply-patch" }],
      ["address-feedback", { patch: "apply-feedback-patch", "feedback-replies": "publish-feedback" }],
      ["review-dependency", { patch: "apply-dependency-patch", "dependency-verdict": "apply-dependency-verdict" }],
      ["fix-ci", { patch: "apply-patch" }],
      ["resolve-issue", { patch: "apply-issue-patch", "work-outcome": "report-outcome" }],
    ],
  );
  assert.equal(selected("work-resolve-issue", "resolve-issue", ISSUE).effect, "read");
});

test("live config: the shipped patch rules pass against the live activities", () => {
  const rules = json("./patch-rules.json");
  assert.equal(checkPatchRules(rules, json("./patch-rules.schema.json"), parse(FILES.config).activities), rules);
});
