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

// No key reads a work class, so a class decides nothing.
test("an issue with no work class and a structural one get the same answer", () => {
  const predicate = { events: ["labeled"], labels: ["agent-ready"], "labels-absent": ["needs-human"] };
  for (const labels of [["agent-ready"], ["agent-ready", "work-class: structural"]]) {
    assert.deepEqual(applies(predicate, { event: "labeled", labels }), { applies: true, skipReason: null }, labels.join());
  }
});

test("admission and work-classes are no predicate keys, so they read no fact", () => {
  assert.deepEqual(factsFor({ admission: { classes: ["work-class: read-only"] } }), []);
  assert.deepEqual(factsFor({ "work-classes": ["C2"] }), []);
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
});

test("factsFor names the facts a predicate reads", () => {
  assert.deepEqual(factsFor(undefined), []);
  assert.deepEqual(
    factsFor({ paths: ["a"], labels: ["b"], events: ["push"] }).sort(),
    ["changedPaths", "labels"],
  );
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
