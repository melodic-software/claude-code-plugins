import assert from "node:assert/strict";
import { test } from "node:test";

import {
  applies,
  appliesAll,
  factsFor,
  MissingFact,
  pipelineEvent,
} from "./predicate.mjs";

const facts = {
  event: "synchronize",
  changedPaths: ["src/app.js", "docs/guide.md"],
  labels: ["C2", "area:docs"],
  workClasses: ["C2"],
};

test("no predicate applies, with no skip reason", () => {
  assert.deepEqual(applies(undefined, {}), { applies: true, skipReason: null });
});

test("a paths predicate applies when any changed path matches any glob", () => {
  assert.deepEqual(applies({ paths: ["**/*.md"] }, facts), {
    applies: true,
    skipReason: null,
  });
});

test("a paths miss gives not-applicable-paths", () => {
  assert.deepEqual(applies({ paths: ["infra/**"] }, facts), {
    applies: false,
    skipReason: "not-applicable-paths",
  });
});

test("a labels miss gives not-applicable", () => {
  assert.deepEqual(applies({ labels: ["security"] }, facts), {
    applies: false,
    skipReason: "not-applicable",
  });
  assert.equal(applies({ labels: ["area:docs"] }, facts).applies, true);
});

test("an events miss gives not-applicable, and an unmapped event misses", () => {
  assert.equal(
    applies({ events: ["push"] }, facts).skipReason,
    "not-applicable",
  );
  assert.equal(applies({ events: ["synchronize"] }, facts).applies, true);
  assert.equal(
    applies({ events: ["push"] }, { ...facts, event: null }).skipReason,
    "not-applicable",
  );
});

test("a work-classes miss gives not-applicable", () => {
  assert.equal(
    applies({ "work-classes": ["C3"] }, facts).skipReason,
    "not-applicable",
  );
  assert.equal(applies({ "work-classes": ["C2", "C3"] }, facts).applies, true);
});

test("admission admits a listed class, and refuses any other class beside it", () => {
  const admission = { classes: ["work-class: read-only", "work-class: mechanical"] };
  const issue = (labels, ratified) => ({ event: "labeled", labels, ratified });
  assert.equal(applies({ admission }, issue(["agent-ready", "work-class: mechanical"])).applies, true);
  assert.equal(
    applies({ admission }, issue(["work-class: mechanical", "work-class: scoped"])).skipReason,
    "not-applicable",
  );
  assert.equal(applies({ admission }, issue(["agent-ready"])).skipReason, "not-applicable");
});

test("admission refuses a held class however its label is cased or spaced", () => {
  const admission = { classes: ["work-class: mechanical"] };
  for (const held of ["Work-class: scoped", "work-class:scoped", "WORK-CLASS :  scoped"]) {
    assert.equal(
      applies({ admission }, { labels: ["work-class: mechanical", held] }).skipReason,
      "not-applicable",
      held,
    );
  }
  // A listed class written another way is still that class, not a held one.
  assert.equal(applies({ admission }, { labels: ["work-class: mechanical", "Work-Class:mechanical"] }).applies, true);
});

test("admission with ratified also admits a ratified issue with no class, never one with a held class", () => {
  const admission = { classes: ["work-class: read-only"], ratified: true };
  const issue = (labels, ratified) => ({ event: "labeled", labels, ratified });
  assert.equal(applies({ admission }, issue(["agent-ready"], true)).applies, true);
  assert.equal(applies({ admission }, issue(["agent-ready"], false)).skipReason, "not-applicable");
  assert.equal(
    applies({ admission }, issue(["agent-ready", "work-class: scoped"], true)).skipReason,
    "not-applicable",
  );
  assert.throws(() => applies({ admission }, { event: "labeled", labels: [] }), MissingFact);
  // Labels are read now, so a held class added while the run waits still refuses it.
  assert.deepEqual(factsFor({ admission }).sort(), ["freshLabels", "labels", "ratified"]);
  assert.deepEqual(factsFor({ admission: { classes: ["work-class: read-only"] } }).sort(), ["freshLabels", "labels"]);
});

test("every listed key must match: a paths miss wins over another miss", () => {
  assert.equal(
    applies({ paths: ["src/**"], labels: ["security"] }, facts).skipReason,
    "not-applicable",
  );
  assert.equal(
    applies({ paths: ["infra/**"], labels: ["security"] }, facts).skipReason,
    "not-applicable-paths",
  );
});

test("a predicate over a fact nobody supplied throws instead of guessing", () => {
  assert.throws(
    () => applies({ paths: ["src/**"] }, { event: "push" }),
    MissingFact,
  );
  assert.throws(
    () => applies({ "work-classes": ["C2"] }, { event: "push" }),
    MissingFact,
  );
});

test("factsFor names the facts a predicate reads", () => {
  assert.deepEqual(factsFor(undefined), []);
  assert.deepEqual(
    factsFor({ paths: ["a"], labels: ["b"], events: ["push"] }).sort(),
    ["changedPaths", "labels"],
  );
  assert.deepEqual(factsFor({ "work-classes": ["C2"] }), ["workClasses"]);
});

test("pipelineEvent maps GitHub events onto the predicate's event names", () => {
  assert.equal(
    pipelineEvent("pull_request", { action: "ready_for_review" }),
    "ready",
  );
  assert.equal(
    pipelineEvent("pull_request", {
      action: "opened",
      pull_request: { draft: false },
    }),
    "ready",
  );
  assert.equal(
    pipelineEvent("pull_request", {
      action: "opened",
      pull_request: { draft: true },
    }),
    null,
  );
  assert.equal(
    pipelineEvent("pull_request", { action: "synchronize" }),
    "synchronize",
  );
  assert.equal(pipelineEvent("pull_request", { action: "labeled" }), "labeled");
  assert.equal(
    pipelineEvent("pull_request", { action: "unlabeled" }),
    "unlabeled",
  );
  assert.equal(
    pipelineEvent("pull_request", { action: "dequeued" }),
    "dequeued",
  );
  assert.equal(pipelineEvent("pull_request", { action: "closed" }), null);
  assert.equal(pipelineEvent("push", {}), "push");
  assert.equal(pipelineEvent("schedule", {}), "schedule");
  assert.equal(pipelineEvent("workflow_dispatch", {}), "dispatch");
  assert.equal(pipelineEvent("workflow_run", {}), "workflow-run");
  assert.equal(pipelineEvent("issues", {}), null);
});

// mergeable, labels-absent and draft

const pullFacts = { ...facts, mergeable: "conflicting", draft: false };

test("a mergeable predicate matches the PR's mergeability", () => {
  assert.deepEqual(applies({ mergeable: ["conflicting"] }, pullFacts), {
    applies: true,
    skipReason: null,
  });
  assert.deepEqual(
    applies(
      { mergeable: ["conflicting"] },
      { ...pullFacts, mergeable: "clean" },
    ),
    { applies: false, skipReason: "not-applicable" },
  );
  assert.equal(
    applies({ mergeable: ["clean"] }, { ...pullFacts, mergeable: "clean" })
      .applies,
    true,
  );
});

test("unknown mergeability never matches and skips with prerequisite-missing", () => {
  for (const listed of [["conflicting"], ["clean"], ["conflicting", "clean"]]) {
    assert.deepEqual(
      applies({ mergeable: listed }, { ...pullFacts, mergeable: null }),
      { applies: false, skipReason: "prerequisite-missing" },
    );
  }
});

test("a labels-absent label on the PR skips with awaiting-human, not not-applicable", () => {
  assert.deepEqual(
    applies(
      { "labels-absent": ["do-not-merge", "needs-human"] },
      { ...pullFacts, labels: ["C2", "needs-human"] },
    ),
    { applies: false, skipReason: "awaiting-human" },
  );
});

test("labels-absent matches when none of its labels is on the PR", () => {
  assert.deepEqual(
    applies({ "labels-absent": ["do-not-merge", "needs-human"] }, pullFacts),
    { applies: true, skipReason: null },
  );
});

test("draft: [false] does not match a draft PR and skips with not-applicable", () => {
  assert.deepEqual(applies({ draft: [false] }, { ...pullFacts, draft: true }), {
    applies: false,
    skipReason: "not-applicable",
  });
  assert.equal(applies({ draft: [false] }, pullFacts).applies, true);
});

test("awaiting-human wins over a not-applicable or unknown-mergeability miss", () => {
  assert.equal(
    applies(
      {
        mergeable: ["conflicting"],
        "labels-absent": ["do-not-merge"],
        draft: [false],
      },
      { ...pullFacts, labels: ["do-not-merge"], draft: true, mergeable: null },
    ).skipReason,
    "awaiting-human",
  );
});

test("a decided miss wins over unknown mergeability", () => {
  assert.equal(
    applies(
      { mergeable: ["conflicting"], draft: [false] },
      { ...pullFacts, mergeable: null, draft: true },
    ).skipReason,
    "not-applicable",
  );
});

test("a mergeable, labels-absent or draft predicate with no fact throws", () => {
  assert.throws(
    () => applies({ mergeable: ["conflicting"] }, facts),
    MissingFact,
  );
  assert.throws(
    () => applies({ "labels-absent": ["needs-human"] }, { event: "push" }),
    MissingFact,
  );
  assert.throws(() => applies({ draft: [false] }, facts), MissingFact);
});

test("factsFor names mergeable, draft and the labels labels-absent reads, once each", () => {
  assert.deepEqual(
    factsFor({
      mergeable: ["conflicting"],
      labels: ["a"],
      "labels-absent": ["needs-human"],
      draft: [false],
    }).sort(),
    ["draft", "freshLabels", "labels", "mergeable"],
  );
});

test("appliesAll needs every predicate to match, with one predicate's precedence", () => {
  assert.deepEqual(appliesAll([], facts), { applies: true, skipReason: null });
  assert.deepEqual(
    appliesAll([{ events: ["synchronize"] }, { labels: ["C2"] }], facts),
    { applies: true, skipReason: null },
  );
  const held = { ...pullFacts, labels: ["needs-human"] };
  assert.equal(
    appliesAll(
      [{ events: ["push"] }, { "labels-absent": ["needs-human"] }],
      held,
    ).skipReason,
    "awaiting-human",
  );
  assert.equal(
    appliesAll([{ labels: ["security"] }, { paths: ["infra/**"] }], facts)
      .skipReason,
    "not-applicable-paths",
  );
});
