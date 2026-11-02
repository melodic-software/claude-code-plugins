// models.issue-status: the label collapse and the Work status field reader,
// over the live config. Expected values are written by hand: the option ids
// from the org field as read on 2026-11-01, and the label table and collapse
// order from the owner decision Q-WS (architecture owner-decisions; Refs #7577).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { collapseStatus, issueStatus as readStatus, statusOption } from "./issue-status.mjs";
import { Rejection } from "./resolve.mjs";

const CONFIG = parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8")).models[
  "issue-status"
];
const FIELD = 48484079;
// A listed human in the live trusted-actor list, an account not on it, and
// the lanes App.
const TRUSTED = JSON.parse(readFileSync(new URL("../../standards/trusted-actors/trusted-actors.json", import.meta.url), "utf8"));
const LISTED = 153232337;
const UNLISTED = 42;
const issueStatus = (fieldValues, setter = LISTED) =>
  readStatus({ fieldValues, fieldSetters: Object.fromEntries(fieldValues.map(({ field }) => [field, setter])) }, CONFIG, TRUSTED);
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
  ["needs-owner-decision", "needs-owner-decision"],
]) {
  test(`collapse: \`${label}\` alone is ${state}`, () => {
    assert.equal(collapseStatus([label], CONFIG), state);
  });
}

for (const [why, labels, state] of [
  ["no label", [], "needs-triage"],
  ["only labels that are no state", ["bug", "priority: high", "host-run"], "needs-triage"],
  ["needs-owner-decision with agent-ready", ["agent-ready", "needs-owner-decision"], "needs-owner-decision"],
  ["mixed-case labels", ["Status: Ready", "Agent-Ready"], "agent-ready"],
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
    assert.equal(issueStatus([{ field: 15462270, option: 27053568 }, { field: FIELD, option }]), state);
    assert.equal(statusOption(state, CONFIG), option);
  });
}

test("read: an option the config does not map fails closed", () => {
  assert.throws(
    () => issueStatus([{ field: FIELD, option: 99999999 }]),
    (error) => error instanceof Rejection && error.code === "unmapped-status" && error.message.includes("99999999"),
  );
});

test("read: an issue with no Work status value reads null", () => {
  assert.equal(issueStatus([]), null);
  assert.equal(issueStatus([{ field: 15462270, option: 27053568 }]), null);
});

// A row with no option fails like issueDimensions does with one.
test("read: a trusted row with no option fails closed", () => {
  assert.throws(() => issueStatus([{ field: FIELD, option: null }]), (error) => error instanceof Rejection && error.code === "unmapped-status");
});

test("read: a value no trusted account set reads null, mapped or not", () => {
  assert.equal(issueStatus([{ field: FIELD, option: 84879220 }], UNLISTED), null);
  assert.equal(issueStatus([{ field: FIELD, option: 99999999 }], UNLISTED), null);
  assert.equal(issueStatus([{ field: FIELD, option: 84879220 }], null), null);
});

test("write: a state no option maps is rejected", () => {
  assert.throws(() => statusOption("blocked", CONFIG), (error) => error instanceof Rejection && error.code === "undefined-status");
});
