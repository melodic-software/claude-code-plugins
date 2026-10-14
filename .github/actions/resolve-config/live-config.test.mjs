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

// An agent-ready label event on a read-only issue. The
// lane went live at 2026-10-14T19:21:59Z, the labeled-after time in the live config.
const ISSUE = { event: "labeled", labels: ["agent-ready", "work-class: read-only"], labeledAt: "2026-10-20T00:00:00Z" };

test("live config: resolve-issue starts for a read-only issue labeled after the go-live time", () => {
  assert.equal(selected("work-resolve-issue", "resolve-issue", ISSUE).applies, true);
});

test("live config: resolve-issue starts nothing for an issue labeled before the go-live time", () => {
  assert.equal(
    skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labeledAt: "2026-10-14T19:21:58Z" }),
    "not-applicable",
  );
});

test("live config: resolve-issue starts for a mechanical issue", () => {
  assert.equal(
    selected("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: ["agent-ready", "work-class: mechanical"] }).applies,
    true,
  );
});

test("live config: resolve-issue admits read-only and mechanical issues only", () => {
  assert.equal(
    skipReason("work-resolve-issue", "resolve-issue", { ...ISSUE, labels: ["agent-ready", "work-class: scoped"] }),
    "not-applicable",
  );
});

// The run must pass the fragment format check before it reports done.
test("live config: resolve-issue may run the changelog fragment check", () => {
  assert.deepEqual(selected("work-resolve-issue", "resolve-issue", ISSUE).checks, [
    "scripts/check-changelog-fragments.sh --check",
  ]);
});

// Owner decision 2026-10-14: the run may read any web page.
test("live config: resolve-issue may read any domain; no other activity reads the web", () => {
  assert.deepEqual(selected("work-resolve-issue", "resolve-issue", ISSUE)["web-access"], { enabled: true, domains: "any" });
  const doc = parse(FILES.config);
  const others = Object.entries(doc.activities).filter(([name, a]) => name !== "resolve-issue" && a["web-access"]?.enabled);
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

test("live config: fix-docs applies to a Markdown change and waits on needs-human", () => {
  assert.equal(selected("pr-refine", "fix-docs").applies, true);
  assert.equal(
    skipReason("pr-refine", "fix-docs", { labels: ["needs-human"] }),
    "awaiting-human",
  );
});
