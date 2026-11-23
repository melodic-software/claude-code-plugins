import assert from "node:assert/strict";
import { test } from "node:test";

import { specSource } from "./spec-source.mjs";

const NONE = { written: false, body: "issue body", splitChild: undefined, splitMarked: false, ownFiling: false, briefed: false, recurring: null, drift: null, incident: null };
const EVERY = { splitChild: "child body", ownFiling: true, briefed: true, recurring: "schedule row", drift: "drift spec", incident: "main red spec" };

const ROWS = [
  ["a written issue's own body wins over every other source", { written: true, ...EVERY }, { body: "issue body" }],
  ["a written issue whose body is not a string has no spec", { written: true, body: null, ownFiling: true, recurring: "schedule row", drift: "drift spec", incident: "main red spec" }, { body: null }],
  ["the split-child body wins over the own, briefed and generated sources", EVERY, { body: "child body" }],
  ["an own-agent filing's body is its spec", { ownFiling: true, briefed: true }, { body: "issue body" }],
  ["an own-agent filing with no body has the empty spec", { body: undefined, ownFiling: true }, { body: "" }],
  ["a briefed filing's body is its spec", { briefed: true }, { body: "issue body" }],
  ["an own or briefed body keeps the recurring row out", { briefed: true, recurring: "schedule row" }, { body: "issue body" }],
  ["a split-marked body is neither an own nor a briefed filing", { splitMarked: true, ownFiling: true, briefed: true, recurring: "schedule row" }, { source: "recurring-schedule", body: "schedule row" }],
  ["the recurring row wins over drift and incident", { recurring: "schedule row", drift: "drift spec", incident: "main red spec" }, { source: "recurring-schedule", body: "schedule row" }],
  ["the drift spec wins over the incident", { drift: "drift spec", incident: "main red spec" }, { source: "upstream-drift", body: "drift spec" }],
  ["a main-red incident alone takes the incident spec", { incident: "main red spec" }, { source: "main-red-incident", body: "main red spec" }],
  ["beside an own-agent body the drift spec still marks the source", { ownFiling: true, drift: "drift spec" }, { source: "upstream-drift", body: "issue body" }],
  ["beside a briefed body the incident still marks the source", { briefed: true, incident: "main red spec" }, { source: "main-red-incident", body: "issue body" }],
  ["an issue no source claims has no spec", {}, { body: null }],
];

for (const [name, facts, want] of ROWS) {
  test(`specSource: ${name}`, () => {
    assert.deepEqual(specSource({ ...NONE, ...facts }), want);
  });
}
