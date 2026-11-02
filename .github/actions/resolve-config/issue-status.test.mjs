// models.issue-status: the label collapse and the Work status field reader,
// over the live config. The option ids, labels and collapse order expected
// here are written by hand from the org field as read on 2026-11-01.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { collapseStatus, issueStatus, statusOption } from "./issue-status.mjs";
import { Rejection } from "./resolve.mjs";

const CONFIG = parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8")).models[
  "issue-status"
];
const FIELD = 48484079;
const OPTIONS = {
  "needs-triage": 84879216,
  "needs-reporter-info": 84879217,
  "needs-owner-decision": 84879218,
  "needs-spec": 84879219,
  "agent-ready": 84879220,
  confirmed: 86380002,
  ready: 86380003,
  deferred: 86380004,
  "needs-human": 86380005,
};

for (const [label, state] of [
  ["needs-triage", "needs-triage"],
  ["status: needs-info", "needs-reporter-info"],
  ["status: needs-decision", "needs-owner-decision"],
  ["needs-spec", "needs-spec"],
  ["agent-ready", "agent-ready"],
  ["status: confirmed", "confirmed"],
  ["status: ready", "ready"],
  ["admission-deferred", "deferred"],
  ["needs-human", "needs-human"],
]) {
  test(`collapse: \`${label}\` alone is ${state}`, () => {
    assert.equal(collapseStatus([label], CONFIG), state);
  });
}

for (const [why, labels, state] of [
  ["no label", [], "needs-triage"],
  ["only labels that are no state", ["bug", "priority: high", "needs-owner-decision"], "needs-triage"],
  ["status: ready with agent-ready", ["status: ready", "agent-ready"], "agent-ready"],
  ["needs-human with every other state", ["needs-triage", "status: confirmed", "status: ready", "admission-deferred", "agent-ready", "status: needs-info", "needs-spec", "status: needs-decision", "needs-human"], "needs-human"],
  ["needs-human with agent-ready", ["agent-ready", "needs-human"], "needs-human"],
  ["needs-decision over needs-spec and needs-info", ["status: needs-info", "needs-spec", "status: needs-decision"], "needs-owner-decision"],
  ["needs-spec over needs-info", ["status: needs-info", "needs-spec"], "needs-spec"],
  ["needs-info over agent-ready", ["agent-ready", "status: needs-info"], "needs-reporter-info"],
  ["agent-ready over admission-deferred", ["admission-deferred", "agent-ready"], "agent-ready"],
  ["admission-deferred over status: ready", ["status: ready", "admission-deferred"], "deferred"],
  ["status: ready over status: confirmed", ["status: confirmed", "status: ready"], "ready"],
  ["status: confirmed over needs-triage", ["needs-triage", "status: confirmed"], "confirmed"],
]) {
  test(`collapse: ${why} is ${state}`, () => {
    assert.equal(collapseStatus(labels, CONFIG), state);
  });
}

test("collapse: REST label objects read as their names", () => {
  assert.equal(collapseStatus([{ name: "status: ready" }, { name: "agent-ready" }], CONFIG), "agent-ready");
});

for (const [state, option] of Object.entries(OPTIONS)) {
  test(`read: option ${option} is ${state}, and ${state} writes as it`, () => {
    assert.equal(issueStatus([{ field: 15462270, option: 27053568 }, { field: FIELD, option }], CONFIG), state);
    assert.equal(statusOption(state, CONFIG), option);
  });
}

test("read: an option the config does not map fails closed", () => {
  assert.throws(
    () => issueStatus([{ field: FIELD, option: 99999999 }], CONFIG),
    (error) => error instanceof Rejection && error.code === "unmapped-status" && error.message.includes("99999999"),
  );
});

test("read: an issue with no Work status value reads null", () => {
  assert.equal(issueStatus([], CONFIG), null);
  assert.equal(issueStatus([{ field: 15462270, option: 27053568 }], CONFIG), null);
  assert.equal(issueStatus([{ field: FIELD, option: null }], CONFIG), null);
});

test("write: a state no option maps is rejected", () => {
  assert.throws(() => statusOption("blocked", CONFIG), (error) => error instanceof Rejection && error.code === "undefined-status");
});
