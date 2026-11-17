// test-scope: .github/workflows/*.yml .github/actions/resolve-config/lane-rules.json
// Every lane workflow in lane-rules.json opens with one fixed summary block
// under its `name:` line: the lane id, what it does, its triggers and its
// stage. The stage is lane-rules.json's, and the trigger line names every
// event the file's `on:` lists, so the block cannot drift from either.
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

const RULES = JSON.parse(readFileSync(new URL("../../actions/resolve-config/lane-rules.json", import.meta.url), "utf8"));
const workflowUrl = (file) => new URL(`../../workflows/${file}`, import.meta.url);
// A lane's file is its id, or its id with `-hosted` for a review caller.
const fileOf = (lane) => [`${lane}.yml`, `${lane}-hosted.yml`].find((file) => existsSync(workflowUrl(file)));
const HEADER = /^name: .+\n\n# Lane: (\S+)\n# Does: (\S.*)\n# Trigger: (\S.*)\n# Stage: (\S+)\n\n/;

// The event names of the top-level `on:` block (two-space keys up to the next
// top-level key).
const events = (text) => {
  const block = /^on:\n((?:(?: {2}.*|\s*)\n)+)/m.exec(text)?.[1] ?? "";
  return [...block.matchAll(/^ {2}([a-z_]+):/gm)].map((match) => match[1]);
};

test("each lane workflow opens with its lane, purpose, triggers and stage", () => {
  const lanes = Object.keys(RULES).filter(fileOf);
  assert.ok(lanes.length >= 13, `found ${lanes.length} lane workflows`);
  for (const lane of lanes) {
    const text = readFileSync(workflowUrl(fileOf(lane)), "utf8");
    const header = HEADER.exec(text);
    assert.ok(header, `${fileOf(lane)} opens with the summary block`);
    const [, id, , trigger, stage] = header;
    assert.equal(id, lane, fileOf(lane));
    assert.equal(stage, RULES[lane].stage, `${fileOf(lane)}: the stage is lane-rules.json's`);
    // An event may carry a parenthesized detail, commas included.
    const named = new Set(trigger.replace(/ \([^)]*\)/g, "").split(", "));
    assert.deepEqual([...named].sort(), events(text).sort(), `${fileOf(lane)}: the trigger line names exactly the on: events`);
  }
});
