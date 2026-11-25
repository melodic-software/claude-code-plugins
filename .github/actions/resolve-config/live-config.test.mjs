// test-scope: .github/actions/resolve-config/package.json
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { parse, stringify } from "yaml";

import { OUTSIDE_ACTOR_LABEL } from "../../scripts/pr-merge/merge-holds.mjs";
import { planPasses } from "../../scripts/pr-refine/plan-passes.mjs";
import { decide } from "../../scripts/lib/lane-level.mjs";
import { checkPatchRules } from "./patch-rules.mjs";
import { statusBotSetters } from "./issue-status.mjs";
import { configFromBase, ownedBranchesFromBase, postMergeFromBase, refineDispatchActivitiesFromBase, testScopeFromBase } from "./resolve-config.mjs";
import { laneSlots, resolve, resolveGrant, resolveLimits, slotTargets } from "./resolve.mjs";
import { STANDARDS_FIXTURE } from "../../scripts/lib/trusted-actors.fixtures.mjs";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const read = (relative) =>
  readFileSync(new URL(relative, import.meta.url), "utf8");
const json = (relative) => JSON.parse(read(relative));
const CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const EXAMPLE_PATH = "docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml";
const FILES = {
  config: read(`../../../${CONFIG_PATH}`),
  schema: json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
  vocabulary: json(
    "../../scripts/lib/fixtures/standards/components/github-actions-conventions/vocabulary.json",
  ),
  laneRules: json("./lane-rules.json"),
  effectGrants: json("./effect-grants.json"),
  activityRules: json("./activity-rules.json"),
  trustedActors: json("../../scripts/lib/fixtures/standards/components/trusted-actors/trusted-actors.json"),
};
const FACTS = {
  event: "dispatch",
  changedPaths: ["docs/guide.md"],
  changedTargets: ["docs/guide.md"],
  labels: [],
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

test("live config: resolve-conflicts applies to a conflicting ready PR with prepare merge-base, as a read skill that hands on a patch", () => {
  const slot = selected("pr-unblock", "resolve-conflicts");
  assert.equal(slot.applies, true);
  assert.equal(slot.prepare, "merge-base");
  assert.equal(slot.effect, "read");
  assert.deepEqual(slot["applied-by"], { patch: "apply-conflict-patch" });
  assert.equal(slot.skill, "source-control:pull-request");
  assert.equal(slot.args, "conflicts --ci --unattended");
});

test("live config: resolve-conflicts holds no write token; its push job may only write its branch", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "pr-unblock", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("resolve-conflicts"), { effect: "read", grant: { contents: "read", "pull-requests": "read", issues: "read" } });
  assert.deepEqual(grant("apply-conflict-patch"), { effect: "mutate-branch", grant: { contents: "write", "pull-requests": "read", issues: "read" } });
  const push = selected("pr-unblock", "apply-conflict-patch");
  assert.equal(push.script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(push.prepare, "apply-patch");
  assert.deepEqual(push.needs, ["resolve-conflicts"]);
  assert.equal(selected("pr-unblock", "apply-conflict-patch", { labels: ["do-not-merge"] }).applies, false);
  assert.equal(selected("pr-unblock", "apply-conflict-patch", { labels: ["needs-human"] }).applies, true);
  assert.equal(selected("pr-unblock", "apply-conflict-patch", { draft: true }).applies, false);
});

test("live config: resolve-conflicts waits for a human while do-not-merge is on the PR, and leaves needs-human to the select job", () => {
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { labels: ["do-not-merge"] }),
    "awaiting-human",
  );
  assert.equal(selected("pr-unblock", "resolve-conflicts", { labels: ["needs-human"] }).applies, true);
});

test("live config: resolve-conflicts applies to a clean ready PR, and not to a draft", () => {
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { draft: true }),
    "not-applicable",
  );
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { draft: true, mergeable: "clean" }),
    "not-applicable",
  );
  assert.equal(selected("pr-unblock", "resolve-conflicts", { mergeable: "clean" }).applies, true);
  assert.equal(
    skipReason("pr-unblock", "resolve-conflicts", { mergeable: "clean", labels: ["do-not-merge"] }),
    "awaiting-human",
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
      "apply-conflict-patch",
      "address-feedback",
      "apply-feedback-patch",
      "publish-feedback",
      "resolve-feedback-threads",
      "review-dependency",
      "apply-dependency-patch",
      "apply-dependency-verdict",
      "fix-ci",
      "apply-patch",
      "sync-shared-copies",
      "apply-shared-copies",
      "fix-test-scope",
      "apply-test-scope",
      "report-escalation",
    ],
  );
});

test("live config: address-feedback applies to a ready PR with comments --ci and prepare review-threads", () => {
  const slot = selected("pr-unblock", "address-feedback", { mergeable: "clean" });
  assert.equal(slot.applies, true);
  assert.equal(slot["reads-untrusted"], true);
  assert.equal(slot.skill, "source-control:pull-request");
  assert.equal(slot.args, "comments --ci --unattended");
  assert.equal(slot.prepare, "review-threads");
  assert.deepEqual(
    resolveGrant(FILES, { lane: "pr-unblock", activity: "address-feedback", configPath: CONFIG_PATH }),
    { effect: "read", grant: { contents: "read", "pull-requests": "read", issues: "read" } },
  );
  assert.deepEqual(slot["applied-by"], { patch: "apply-feedback-patch", "feedback-replies": "publish-feedback" });
});

const takesUnattended = (skill) => {
  const [plugin, name] = skill.split(":");
  const path = `../../../plugins/${plugin}/skills/${name}/SKILL.md`;
  assert.ok(existsSync(new URL(path, import.meta.url)), `${skill} has no SKILL.md at ${path}`);
  const frontmatter = read(path).split(/^---$/m)[1] ?? "";
  return /^argument-hint:.*--unattended/m.test(frontmatter);
};

test("live config: every lane call of a skill that takes --unattended passes it", () => {
  const configs = [
    [CONFIG_PATH, FILES.config],
    [EXAMPLE_PATH, read(`../../../${EXAMPLE_PATH}`)],
  ];
  const checked = [];
  for (const [path, text] of configs) {
    for (const [activity, spec] of Object.entries(parse(text).activities)) {
      if (spec.skill === undefined || !takesUnattended(spec.skill)) continue;
      checked.push(`${path}#${activity}`);
      const args = (spec.args ?? "").split(/\s+/);
      assert.ok(args.includes("--unattended"), `${path}: ${activity} calls ${spec.skill} with args "${spec.args ?? ""}", without --unattended`);
    }
  }
  for (const activity of [
    `${CONFIG_PATH}#resolve-conflicts`,
    `${EXAMPLE_PATH}#resolve-conflicts`,
    `${CONFIG_PATH}#address-feedback`,
    `${CONFIG_PATH}#review-dependency`,
    `${CONFIG_PATH}#fix-ci`,
    `${EXAMPLE_PATH}#simplify`,
    `${EXAMPLE_PATH}#check-intent`,
  ]) {
    assert.ok(checked.includes(activity), `${activity} was not checked`);
  }
});

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

test("live config: address-feedback applies to a needs-human PR", () => {
  assert.equal(
    selected("pr-unblock", "address-feedback", { mergeable: "clean", labels: ["needs-human"] }).applies,
    true,
  );
});

test("live config: every other PR activity still waits on needs-human", () => {
  for (const [lane, activity, facts] of [
    ["pr-unblock", "review-dependency", { mergeable: "clean" }],
    ["pr-unblock", "apply-dependency-patch", {}],
  ]) {
    assert.equal(skipReason(lane, activity, { ...facts, labels: ["needs-human"] }), "awaiting-human", activity);
  }
  for (const [lane, activity] of [
    ["pr-unblock", "resolve-conflicts"],
    ["pr-unblock", "apply-conflict-patch"],
    ["pr-unblock", "fix-ci"],
    ["pr-unblock", "apply-patch"],
    ["pr-refine", "fix-docs"],
    ["pr-refine", "apply-patch"],
  ]) {
    assert.equal(skipReason(lane, activity, { labels: ["do-not-merge"] }), "awaiting-human", activity);
    assert.equal(selected(lane, activity, { labels: ["needs-human"] }).applies, true, activity);
  }
});

test("live config: review-dependency and its push job wait on needs-session", () => {
  for (const [activity, facts] of [
    ["review-dependency", { mergeable: "clean" }],
    ["apply-dependency-patch", {}],
  ]) {
    assert.equal(skipReason("pr-unblock", activity, { ...facts, labels: ["needs-session"] }), "awaiting-human", activity);
    assert.equal(selected("pr-unblock", activity, { ...facts, labels: [] }).applies, true, activity);
  }
});

test("live config: every PR activity waits on security: outside-actor", () => {
  const config = parse(FILES.config);
  const prLanes = Object.entries(config.lanes).filter(([lane]) => lane.startsWith("pr-"));
  const slots = new Map();
  for (const [lane, { slots: laneSlots }] of prLanes) {
    for (const slot of laneSlots) slots.set(`${lane}/${slot.activity}`, { lane, activity: slot.activity, needs: slot.needs ?? [] });
  }
  const inLanes = new Set([...slots.values()].map(({ activity }) => activity));
  for (const [activity, spec] of Object.entries(config.activities)) {
    if ((spec.inputs ?? []).includes("pr")) assert.ok(inLanes.has(activity), `${activity} takes a pr input but sits in no pr-* lane`);
  }
  const mergeHoldReaders = new Set(["merge-pr", "enable-auto-merge"]);
  const lists = (activity) => (config.activities[activity]["applies-when"]?.["labels-absent"] ?? []).includes(OUTSIDE_ACTOR_LABEL);
  const gated = (lane, activity) => {
    const { needs } = slots.get(`${lane}/${activity}`);
    return lists(activity) || (config.activities[activity]["applies-when"] === undefined && needs.length > 0 && needs.every((need) => gated(lane, need)));
  };
  const checked = [];
  for (const { lane, activity } of slots.values()) {
    if (mergeHoldReaders.has(activity)) continue;
    assert.ok(gated(lane, activity), `${lane}/${activity} neither lists ${OUTSIDE_ACTOR_LABEL} in labels-absent nor runs only after activities that do`);
    if (!lists(activity)) continue;
    checked.push(`${lane}/${activity}`);
    assert.equal(skipReason(lane, activity, { mergeable: "clean", labels: [OUTSIDE_ACTOR_LABEL] }), "awaiting-human", `${lane}/${activity}`);
  }
  for (const slot of ["pr-refine/fix-docs", "pr-refine/apply-patch", "pr-unblock/resolve-conflicts", "pr-unblock/apply-conflict-patch", "pr-unblock/address-feedback", "pr-unblock/apply-feedback-patch", "pr-unblock/fix-ci", "pr-unblock/apply-patch"]) {
    assert.ok(checked.includes(slot), `${slot} was not checked`);
  }
});

test("live config: publish-feedback runs the reply script after address-feedback, granted publish-artifact only", () => {
  const slot = selected("pr-unblock", "publish-feedback");
  assert.equal(slot.applies, true);
  assert.equal(slot["reads-untrusted"], true);
  assert.equal(slot.script, ".github/scripts/pr-unblock/publish-feedback.mjs");
  assert.deepEqual(slot.needs, ["address-feedback", "apply-feedback-patch"]);
  assert.deepEqual(
    resolveGrant(FILES, { lane: "pr-unblock", activity: "publish-feedback", configPath: CONFIG_PATH }),
    { effect: "publish-artifact", grant: { contents: "read", "pull-requests": "write", issues: "write" } },
  );
});

test("live config: resolve-feedback-threads resolves after publish-feedback with mutate-branch and no head checkout", () => {
  const slot = selected("pr-unblock", "resolve-feedback-threads");
  assert.equal(slot.applies, true);
  assert.equal(slot.kind, "script");
  assert.equal(slot.script, ".github/scripts/pr-unblock/resolve-threads.mjs");
  assert.equal(slot.checkout, "base");
  assert.equal(slot["reads-untrusted"], true);
  assert.deepEqual(slot.needs, ["publish-feedback"]);
  assert.deepEqual(
    resolveGrant(FILES, { lane: "pr-unblock", activity: "resolve-feedback-threads", configPath: CONFIG_PATH }),
    { effect: "mutate-branch", grant: { contents: "write", "pull-requests": "read", issues: "read" } },
  );
});

test("live config: report-escalation follows every pr-unblock activity", () => {
  assert.deepEqual(selected("pr-unblock", "report-escalation").needs, [
    "resolve-conflicts",
    "apply-conflict-patch",
    "address-feedback",
    "publish-feedback",
    "review-dependency",
    "apply-dependency-verdict",
    "fix-ci",
    "apply-patch",
    "sync-shared-copies",
    "apply-shared-copies",
    "fix-test-scope",
    "apply-test-scope",
  ]);
});

test("live config: sync-shared-copies holds no write token; apply-shared-copies may only write its branch", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "pr-unblock", activity, configPath: CONFIG_PATH });
  assert.equal(grant("sync-shared-copies").effect, "read");
  assert.equal(grant("sync-shared-copies").grant.contents, "read");
  assert.deepEqual(grant("apply-shared-copies"), { effect: "mutate-branch", grant: { contents: "write", "pull-requests": "read", issues: "read" } });
  const sync = selected("pr-unblock", "sync-shared-copies", { mergeable: "clean" });
  assert.equal(sync.script, ".github/scripts/pr-unblock/sync-shared-copies.sh");
  const push = selected("pr-unblock", "apply-shared-copies");
  assert.equal(push.script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(push.prepare, "apply-patch");
  assert.deepEqual(push.needs, ["sync-shared-copies"]);
  for (const activity of ["sync-shared-copies", "apply-shared-copies"]) {
    assert.equal(selected("pr-unblock", activity, { labels: ["needs-human"] }).applies, true, activity);
    assert.equal(skipReason("pr-unblock", activity, { labels: ["do-not-merge"] }), "awaiting-human", activity);
    assert.equal(skipReason("pr-unblock", activity, { draft: true }), "not-applicable", activity);
  }
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
  assert.equal(fix.args, "ci --ci --unattended");
  assert.deepEqual(fix["applied-by"], { patch: "apply-patch" });
  assert.equal(selected("pr-unblock", "apply-patch").prepare, "apply-patch");
  assert.equal(selected("pr-unblock", "apply-patch").script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(selected("pr-unblock", "apply-patch").applies, true);
  assert.equal(selected("pr-unblock", "fix-ci", { labels: ["do-not-merge"] }).applies, false);
  assert.equal(selected("pr-unblock", "fix-ci", { labels: ["needs-human"] }).applies, true);
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
  assert.equal(review.args, "dependency --ci --unattended");
  assert.deepEqual(review["applied-by"], { patch: "apply-dependency-patch", "dependency-verdict": "apply-dependency-verdict" });
  const push = selected("pr-unblock", "apply-dependency-patch");
  assert.equal(push.script, ".github/scripts/apply-patch/apply-patch.mjs");
  assert.equal(push.prepare, "apply-patch");
  assert.deepEqual(push.needs, ["review-dependency"]);
  assert.equal(selected("pr-unblock", "apply-dependency-patch", { labels: ["needs-human"] }).applies, false);
  const verdict = selected("pr-unblock", "apply-dependency-verdict");
  assert.equal(verdict.script, ".github/scripts/pr-unblock/apply-dependency-verdict.mjs");
  assert.deepEqual(verdict.needs, ["review-dependency", "apply-dependency-patch"]);
});

const ISSUE = {
  event: "field_added",
  labels: ["agent-ready"],
};

test("live config: resolve-issue starts on agent-ready alone, whatever its work-class label", () => {
  for (const labels of [
    ["agent-ready"],
    ["agent-ready", "work-class: read-only"],
    ["agent-ready", "work-class: scoped"],
    ["agent-ready", "work-class: structural"],
  ]) {
    assert.equal(selected("work-resolve-issue", "resolve-issue", { ...ISSUE, labels }).applies, true, labels.join());
  }
});

test("live config: resolve-issue starts nothing for an issue carrying a hold label", () => {
  for (const hold of ["needs-human", "needs-owner-decision", "needs-reporter-info"]) {
    assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: ["agent-ready", hold] }), "awaiting-human", hold);
  }
});

test("live config: resolve-issue starts nothing once agent-ready is gone from the issue", () => {
  assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: [] }), "not-applicable");
  assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: ["bug"] }), "not-applicable");
});

test("live config: resolve-issue starts on a Work status field event, with no label-time cutoff", () => {
  assert.equal(selected("work-resolve-issue", "resolve-issue", { ...ISSUE, labeledAt: "2026-10-14T19:21:58Z" }).applies, true);
});

test("live config: resolve-issue needs the Work status field event, not a label event", () => {
  for (const event of ["dispatch", "labeled"]) {
    assert.equal(skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, event }), "not-applicable", event);
  }
});

test("live config: resolve-issue runs the changelog fragment and changed-skills checks", () => {
  assert.deepEqual(selected("work-resolve-issue", "resolve-issue", ISSUE).checks, [
    "scripts/check-changelog-fragments.sh --check",
    "scripts/check-changed-skills.sh --merge-base",
  ]);
});

test("live config: resolve-issue self-checks its uncommitted work with check-affected", () => {
  const leaf = selected("work-resolve-issue", "resolve-issue", ISSUE);
  assert.deepEqual(leaf["self-checks"], ["scripts/check-affected.sh --uncommitted"]);
  assert.ok(!leaf.checks.includes("scripts/check-affected.sh --uncommitted"), leaf.checks.join(" | "));
});

test("live config: address-feedback and fix-ci self-check their uncommitted work with check-affected", () => {
  for (const leaf of [selected("pr-unblock", "address-feedback", { mergeable: "clean" }), selected("pr-unblock", "fix-ci")]) {
    assert.deepEqual(leaf["self-checks"], ["scripts/check-affected.sh --uncommitted"]);
    assert.ok(!(leaf.checks ?? []).includes("scripts/check-affected.sh --uncommitted"), (leaf.checks ?? []).join(" | "));
  }
});

const RUNS_CHECKOUT_CODE = [
  "scripts/run-test-file.sh",
  "plugins/skill-quality/scripts/check-skill.sh",
  "plugins/planning/tests/repin.sh",
];
test("live config: resolve-issue may run the can't-fail scan, git mv or rm, the evals check, the shared-copy sync, the fragment writer and the data-only digest repin, and no script that runs checkout code; no other activity lists verify-scripts", () => {
  const scripts = selected("work-resolve-issue", "resolve-issue", ISSUE)["verify-scripts"];
  assert.deepEqual(scripts, [
    "plugins/testing/skills/audit/scripts/cant-fail-scan.sh",
    "scripts/git-mv-rm.sh",
    "plugins/skill-quality/scripts/check-evals-quality.sh",
    "scripts/sync-shared-copies.sh",
    "scripts/new-changelog-fragment.sh",
    "plugins/planning/scripts/repin-digests.sh",
  ]);
  for (const script of RUNS_CHECKOUT_CODE) assert.ok(!scripts.includes(script), script);
  const doc = parse(FILES.config);
  const others = Object.entries(doc.activities).filter(([name, a]) => !["resolve-issue", "fix-ci"].includes(name) && a["verify-scripts"]);
  assert.deepEqual(others, []);
  assert.deepEqual(doc.activities["fix-ci"]["verify-scripts"], ["plugins/planning/scripts/repin-digests.sh"]);
});

test("live config: resolve-issue reads any host; review-dependency reads release-note hosts; no other activity, fix-docs included, reads the web", () => {
  assert.deepEqual(selected("work-resolve-issue", "resolve-issue", ISSUE)["web-access"], { enabled: true, domains: "any" });
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

test("live config: resolve-issue tidies within the small single-area cutoffs with the named quality skills; no other activity tidies", () => {
  const tidy = selected("work-resolve-issue", "resolve-issue", ISSUE).tidy;
  assert.equal(tidy.entry, "code-tidying:tidy-diff");
  assert.deepEqual(tidy.passes, ["docs-hygiene:write-for-agents", "docs-hygiene:write-for-humans", "ai-slop:audit"]);
  assert.equal(tidy["turn-share"], 25);
  assert.deepEqual(
    { files: tidy.cutoffs["max-files"], lines: tidy.cutoffs["max-lines"], areas: tidy.cutoffs["max-areas"] },
    { files: 10, lines: 300, areas: 1 },
  );
  for (const path of [".github/", "scripts/", "docs/conventions/"]) assert.ok(tidy.cutoffs["shared-paths"].includes(path), path);
  const doc = parse(FILES.config);
  assert.deepEqual(
    Object.keys(doc.activities).filter((name) => name !== "resolve-issue" && doc.activities[name].tidy),
    [],
  );
});

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

test("live config: resolve-issue with a write effect is refused", () => {
  const writes = FILES.config
    .replace(
      "effect: read\n    applied-by:\n      patch: apply-issue-patch\n      work-outcome: report-outcome\n",
      "effect: mutate-branch\n",
    )
    .replace(/^    tidy:\n(?: {6}.*\n)+/m, "");
  assert.notEqual(writes, FILES.config);
  assert.throws(
    () => resolve({ ...FILES, config: writes }, { lane: "work-resolve-issue", activity: "resolve-issue", configPath: CONFIG_PATH, basePath: ".base", facts: { ...FACTS, ...ISSUE } }),
    (error) => error.code === "invalid-config",
  );
});

const FLOOR_ROW = '      - glob: ".github/actions/check-trusted-trigger/**"\n        class: trust\n';
for (const [name, row] of Object.entries({
  "a plain string": '      - ".github/actions/check-trusted-trigger/**"\n',
  "author-lift on a trust row": `${FLOOR_ROW}        author-lift: false\n`,
  "a misspelled field": `${FLOOR_ROW}        author_lift: false\n`,
})) {
  test(`live config: a floor-paths row with ${name} is refused`, () => {
    assert.ok(FILES.config.includes(FLOOR_ROW));
    assert.throws(
      () => resolve({ ...FILES, config: FILES.config.replace(FLOOR_ROW, row) }, { lane: "work-resolve-issue", activity: "resolve-issue", configPath: CONFIG_PATH, basePath: ".base", facts: { ...FACTS, ...ISSUE } }),
      /fails the schema/,
    );
  });
}

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
  const { activities } = parse(FILES.config);
  const holds = activities["resolve-issue"]["applies-when"]["labels-absent"];
  const applyHolds = new Set(activities["apply-issue-patch"]["applies-when"]["labels-absent"]);
  assert.ok(holds.length > 0);
  assert.ok(holds.includes("attended"), "resolve-issue holds on attended");
  assert.deepEqual(holds.filter((hold) => !applyHolds.has(hold)), [], "apply-issue-patch's labels-absent covers resolve-issue's");
  assert.deepEqual(activities["apply-issue-patch"]["applies-when"].labels, activities["resolve-issue"]["applies-when"].labels);
  for (const hold of applyHolds) {
    assert.equal(skipReason("work-resolve-issue", "apply-issue-patch", { ...ISSUE, labels: ["agent-ready", hold] }), "awaiting-human", hold);
  }
  assert.equal(skipReason("work-resolve-issue", "apply-issue-patch", { ...ISSUE, labels: [] }), "not-applicable");
});

test("live config: label-unblocked and sync-status may only write issues", () => {
  for (const activity of ["label-unblocked", "sync-status"]) {
    assert.deepEqual(resolveGrant(FILES, { lane: "work-unblock", activity, configPath: CONFIG_PATH }), {
      effect: "mutate-tracker",
      grant: { contents: "read", "pull-requests": "read", issues: "write" },
    }, activity);
  }
});

test("live config: upstream-apply-changelog pushes with contents write only and publishes without it", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "upstream-apply-changelog", activity, configPath: CONFIG_PATH });
  for (const activity of ["apply-changelog-branches", "push-native-baseline-branch"]) {
    assert.deepEqual(grant(activity), {
      effect: "mutate-branch",
      grant: { contents: "write", "pull-requests": "read", issues: "read" },
    }, activity);
  }
  for (const activity of ["publish-changelog-intake", "publish-native-baseline-pr"]) {
    assert.deepEqual(grant(activity), {
      effect: "publish-artifact",
      grant: { contents: "read", "pull-requests": "write", issues: "write" },
    }, activity);
  }
});

test("live config: the skill-edit lane pushes with contents write only, publishes without it, and may not merge or label (AL-Q11)", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "maintenance-measure-skill-edit", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("apply-skill-edit-branch"), {
    effect: "mutate-branch",
    grant: { contents: "write", "pull-requests": "read", issues: "read" },
  });
  assert.deepEqual(grant("publish-skill-edit-pr"), {
    effect: "publish-artifact",
    grant: { contents: "read", "pull-requests": "write", issues: "write" },
  });
  const rules = JSON.parse(readFileSync(new URL("./lane-rules.json", import.meta.url), "utf8"))["maintenance-measure-skill-edit"];
  assert.deepEqual(rules["forbidden-effects"], ["mutate-tracker", "merge"]);
  assert.match(rules.never, /chore\/hill-climb-<plugin>-<skill>-<run id>/);
});

test("live config: the code-tidying upkeep lane pushes with contents write only and publishes without it", () => {
  const grant = (activity) => resolveGrant(FILES, { lane: "maintenance-tidy-code-upkeep", activity, configPath: CONFIG_PATH });
  assert.deepEqual(grant("apply-upkeep-branches"), {
    effect: "mutate-branch",
    grant: { contents: "write", "pull-requests": "read", issues: "read" },
  });
  assert.deepEqual(grant("publish-upkeep-prs"), {
    effect: "publish-artifact",
    grant: { contents: "read", "pull-requests": "write", issues: "write" },
  });
});

test("live config: fix-docs applies to a Markdown change and waits on do-not-merge", () => {
  assert.equal(selected("pr-refine", "fix-docs").applies, true);
  assert.equal(
    skipReason("pr-refine", "fix-docs", { labels: ["do-not-merge"] }),
    "awaiting-human",
  );
});

const PLAN_CONFIG = configFromBase({ BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), STANDARDS_DIR: STANDARDS_FIXTURE });

test("live config: fix-docs skips a PR whose only Markdown is a changelog fragment, and the planner agrees", () => {
  const fragmentOnly = { changedPaths: [".changes/pr-pipeline/x.md", "src/a.js"], changedTargets: [".changes/pr-pipeline/x.md", "src/a.js"] };
  assert.equal(skipReason("pr-refine", "fix-docs", fragmentOnly), "not-applicable-paths");
  const withDoc = { changedPaths: [".changes/pr-pipeline/x.md", "docs/guide.md"], changedTargets: [".changes/pr-pipeline/x.md", "docs/guide.md"] };
  const slot = selected("pr-refine", "fix-docs", withDoc);
  assert.equal(slot.applies, true);
  assert.deepEqual(slot["changed-paths"], ["docs/guide.md"]);
  const slots = laneSlots(PLAN_CONFIG, "pr-refine");
  assert.deepEqual(planPasses({ slots, changedPaths: fragmentOnly.changedPaths }).batches, []);
  assert.deepEqual(planPasses({ slots, changedPaths: withDoc.changedPaths }).batches, [["fix-docs"]]);
});

test("live config: the Refine plan agrees with resolve's applies for every pr-refine pass", () => {
  const slots = laneSlots(PLAN_CONFIG, "pr-refine");
  const refine = slots.filter((slot) => slot.activity.stage === "refine").map((slot) => slot.name);
  assert.ok(refine.includes("fix-docs"));
  const targetsOf = (slot, paths) => ((slot.activity.inputs ?? []).includes("changed-paths") ? slotTargets(slot, paths, undefined) : null);
  for (const paths of [["docs/guide.md"], ["src/a.js"], [".changes/x/a.md"], [".changes/x/a.md", "README.md"], ["CLAUDE.md"], ["CLAUDE.md", "docs/a.md"], ["a.md", "b.yaml", "c.js"]]) {
    const planned = planPasses({ slots, changedPaths: paths, targetsOf }).passes.map((pass) => pass.name);
    for (const name of refine) {
      const { applies } = selected("pr-refine", name, { changedPaths: paths, changedTargets: paths });
      assert.equal(planned.includes(name), applies, `${name} on ${paths.join(",")}`);
    }
  }
});

test("live config: a Refine pass missing its order or group, or one off the refine stage, is refused", () => {
  const edited = (edit) => {
    const doc = parse(FILES.config);
    edit(doc.activities["fix-docs"]);
    return { ...FILES, config: stringify(doc) };
  };
  const run = (files) => resolve(files, { lane: "pr-refine", activity: "fix-docs", configPath: CONFIG_PATH, basePath: ".base", facts: FACTS });
  assert.equal(run(edited(() => {})).selected.applies, true, "the unedited copy resolves");
  for (const [why, edit] of [
    ["no order", (a) => delete a.order],
    ["no group", (a) => delete a.group],
    ["no stage", (a) => delete a.stage],
    ["another stage", (a) => (a.stage = "verify")],
    ["a fractional order", (a) => (a.order = 1.5)],
    ["an empty paths-ignore", (a) => (a["applies-when"]["paths-ignore"] = [])],
  ]) {
    assert.throws(() => run(edited(edit)), /schema|invalid/i, why);
  }
});

test("live config: CI fix-docs is on, fix-docs-per-run 2 (#13717 issuecomment-6692723687)", () => {
  const { limits } = resolve(FILES, { lane: "pr-refine", activity: "fix-docs", configPath: CONFIG_PATH, basePath: ".base", facts: FACTS });
  assert.equal(limits["fix-docs-per-run"], 2);
});

test("live config: fix-docs does not apply to a draft PR", () => {
  assert.equal(skipReason("pr-refine", "fix-docs", { draft: true }), "not-applicable");
});

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

test("live config: no activity sets permission-mode", () => {
  assert.equal(selected("pr-refine", "fix-docs")["permission-mode"], undefined);
  const { activities } = parse(FILES.config);
  assert.deepEqual(Object.keys(activities).filter((name) => Object.hasOwn(activities[name], "permission-mode")), []);
});

test("live config: fix-docs is not asked to fix an instruction surface", () => {
  const slot = selected("pr-refine", "fix-docs", { changedTargets: ["docs/guide.md", "CLAUDE.md", "plugins/p/skills/s/SKILL.md"] });
  assert.deepEqual(slot["changed-paths"], ["docs/guide.md"]);
});

test("live config: fix-docs with a write effect is refused", () => {
  const writes = FILES.config.replace("effect: read\n    applied-by:\n      patch: apply-patch\n", "effect: mutate-branch\n");
  assert.notEqual(writes, FILES.config);
  assert.throws(
    () => resolve({ ...FILES, config: writes }, { lane: "pr-refine", activity: "fix-docs", configPath: CONFIG_PATH, basePath: ".base", facts: FACTS }),
    (error) => error.code === "invalid-config",
  );
});

test("live config: only fix-docs, resolve-conflicts, address-feedback, review-dependency, fix-ci and resolve-issue set applied-by, each to its own appliers", () => {
  const { activities } = parse(FILES.config);
  assert.deepEqual(
    Object.entries(activities)
      .filter(([, activity]) => Object.hasOwn(activity, "applied-by"))
      .map(([name, activity]) => [name, activity["applied-by"]]),
    [
      ["fix-docs", { patch: "apply-patch" }],
      ["resolve-conflicts", { patch: "apply-conflict-patch" }],
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

test("live config: no live slot resolves an actions permission", () => {
  const doc = parse(FILES.config);
  for (const lane of Object.keys(doc.lanes)) {
    const { lane: resolved } = resolve(FILES, { lane, configPath: CONFIG_PATH, basePath: ".base", facts: FACTS });
    for (const slot of resolved.slots) {
      assert.equal(slot.grant.actions, undefined, `${lane}/${slot.name}`);
    }
  }
  assert.equal(
    resolveGrant(FILES, { lane: "pr-merge", activity: "merge-pr", configPath: CONFIG_PATH }).grant.actions,
    undefined,
  );
});

test("live config: only work-unblock's publish-lane-level resolves Variables write, with every other scope read", () => {
  const doc = parse(FILES.config);
  const holders = [];
  for (const lane of Object.keys(doc.lanes)) {
    const { lane: resolved } = resolve(FILES, { lane, configPath: CONFIG_PATH, basePath: ".base", facts: FACTS });
    for (const slot of resolved.slots) {
      if (slot.grant["actions-variables"] !== undefined) holders.push(`${lane}/${slot.name}`);
    }
  }
  assert.deepEqual(holders, ["work-unblock/publish-lane-level"]);
  assert.deepEqual(resolveGrant(FILES, { lane: "work-unblock", activity: "publish-lane-level", configPath: CONFIG_PATH }), {
    effect: "mutate-variable",
    grant: { contents: "read", "pull-requests": "read", issues: "read", "actions-variables": "write" },
  });
});

test("live config: pr-merge's re-fire step skips the release branch release-publish-plugins.yml rebuilds", () => {
  const { merge } = resolve(FILES, { lane: "pr-merge", activity: "merge-pr", configPath: CONFIG_PATH, basePath: ".base", facts: FACTS });
  assert.ok(merge["refire-skip-branches"].includes("release/plugins"), JSON.stringify(merge["refire-skip-branches"]));
});

test("live config: fix-ci reads the owned branches, the release branch among them, from the base", () => {
  const branches = ownedBranchesFromBase({ BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), STANDARDS_DIR: STANDARDS_FIXTURE });
  assert.ok(branches.includes("release/plugins"), JSON.stringify(branches));
});

test("live config: the refine job dispatches no configured activity", () => {
  assert.deepEqual(refineDispatchActivitiesFromBase({ BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), STANDARDS_DIR: STANDARDS_FIXTURE }), []);
});

test("live config: post-merge records the owner login's agent merges on the owner-agent path, record only", () => {
  const { paths, agentIdentity } = postMergeFromBase({ BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), STANDARDS_DIR: STANDARDS_FIXTURE });
  assert.deepEqual(paths, { "owner-agent": { mode: "record", enqueuers: ["kyle-sexton"] } });
  assert.equal(agentIdentity, "melodic-automation-lanes[bot]");
});

test("live config: models.issue-status bot-setters are github-actions[bot] and the listed melodic- Apps but the lanes App", () => {
  assert.equal(Object.hasOwn(parse(FILES.config).models["issue-status"], "bot-setters"), false);
  const setters = statusBotSetters(FILES.trustedActors);
  const melodic = FILES.trustedActors.actors
    .filter((actor) => actor.kind === "bot" && actor.login.startsWith("melodic-") && actor.login !== "melodic-automation-lanes[bot]")
    .map(({ id, login }) => ({ id, login }));
  assert.ok(melodic.length > 0);
  assert.deepEqual(setters, [{ id: 41898282, login: "github-actions[bot]" }, ...melodic]);
  for (const login of ["claude[bot]", "cursor[bot]", "cursoragent", "dependabot[bot]", "melodic-automation-lanes[bot]"]) {
    assert.equal(setters.some((entry) => entry.login === login), false, login);
  }
});

test("live config: models.issue-status field-events-since loads as the S2a cutover time", () => {
  assert.equal(PLAN_CONFIG.models["issue-status"]["field-events-since"], "2026-11-07T09:45:00Z");
});

test("live config: decide() on the resolved limits steps a quiet busy lane from 3 to 4 after two clean windows", () => {
  const limits = resolveLimits(FILES, { configPath: CONFIG_PATH });
  const window = (at) => ({ at, pools: { "lanes-app": { used: 100, limit: 5000 } }, signals: [] });
  const demand = { waiting: 5, running: 3 };
  const first = decide(null, window(1794340800), demand, limits);
  assert.deepEqual(first, { level: 3, streak: 1, holdUntil: 0, reason: "streak" }, "the first clean busy window counts, not missing-data");
  assert.deepEqual(decide(first, window(1794344400), demand, limits), { level: 4, streak: 0, holdUntil: 0, reason: "step-up" });
});

test("the live pr-pipeline.yaml stays inside the merge lane's YAML subset", () => {
  const awk = fileURLToPath(new URL("../../../plugins/source-control/lib/yaml-subset.awk", import.meta.url));
  const config = fileURLToPath(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url));
  const errors = execFileSync("awk", ["-f", awk, config], { encoding: "utf8" })
    .split("\n")
    .filter((line) => line.startsWith("error\t"));
  assert.deepEqual(errors, []);
});

test("live config: test-scope.apply is off, so fix-test-scope uploads its patch and apply-test-scope never runs", () => {
  assert.deepEqual(testScopeFromBase({ BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), STANDARDS_DIR: STANDARDS_FIXTURE }), { apply: false });
  const grant = (activity) => resolveGrant(FILES, { lane: "pr-unblock", activity, configPath: CONFIG_PATH });
  assert.equal(grant("fix-test-scope").effect, "read");
  assert.deepEqual(grant("apply-test-scope"), { effect: "mutate-branch", grant: { contents: "write", "pull-requests": "read", issues: "read" } });
});
