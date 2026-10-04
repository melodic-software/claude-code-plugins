import assert from "node:assert/strict";
import { test } from "node:test";

import { applies, factsFor, MissingFact, pipelineEvent } from "./predicate.mjs";

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
