import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const script = path.join(path.dirname(fileURLToPath(import.meta.url)), "probe-state-issue.mjs");

function repo({ team, personal } = {}) {
  const dir = tempDir("probe-state-issue-");
  spawnSync("git", ["-C", dir, "init", "-q"]);
  mkdirSync(path.join(dir, "docs", "conventions"), { recursive: true });
  if (team !== undefined) writeFileSync(path.join(dir, "docs", "conventions", "harness-ops.yaml"), team);
  if (personal !== undefined) writeFileSync(path.join(dir, "docs", "conventions", "harness-ops.local.yaml"), personal);
  return dir;
}

function run(project, ...extra) {
  const r = spawnSync("node", [script, "--project", project, ...extra], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}

test("no layer sets it: null, so the cloud-routine case is skipped", () => {
  assert.deepEqual(run(repo()), { probe_state_issue: null, layer: "default", errors: [] });
});

test("an empty option or an unrendered placeholder is unset", () => {
  for (const value of ["", "${user_config.probe_state_issue}"]) {
    assert.equal(run(repo(), "--user-value", value).probe_state_issue, null, value);
  }
});

test("the option sets it when no repository file does", () => {
  assert.deepEqual(run(repo(), "--user-value", "acme/widgets#7"), { probe_state_issue: "acme/widgets#7", layer: "userConfig", errors: [] });
});

test("the team file beats the option, and the personal file beats the team file", () => {
  const team = repo({ team: "probe_state_issue: acme/team#1\n" });
  assert.deepEqual(run(team, "--user-value", "acme/widgets#7"), { probe_state_issue: "acme/team#1", layer: "team", errors: [] });
  const personal = repo({ team: "probe_state_issue: acme/team#1\n", personal: "probe_state_issue: me/mine#2\n" });
  assert.equal(run(personal).probe_state_issue, "me/mine#2");
  assert.equal(run(personal).layer, "local");
});

test("a value with a quote or any other off-shape character prints as null from every layer", () => {
  const bad = "acme/w';touch x;'#1";
  const yaml = `probe_state_issue: "${bad.replaceAll('"', '\\"')}"\n`;
  for (const [label, out] of [
    ["option", run(repo(), "--user-value", bad)],
    ["team", run(repo({ team: yaml }))],
    ["personal", run(repo({ team: "probe_state_issue: acme/team#1\n", personal: yaml }))],
    ["option zero", run(repo(), "--user-value", "acme/widgets#07")],
  ]) {
    assert.equal(out.probe_state_issue, null, label);
    assert.equal(out.layer, "default", label);
    assert.match(out.errors.join("\n"), /is not <owner>\/<repo>#<number>/, label);
    assert.doesNotMatch(JSON.stringify(out), /touch x/, label);
  }
});

test("a team value that is not a string is named and dropped", () => {
  const out = run(repo({ team: "probe_state_issue: [a, b]\n" }));
  assert.equal(out.probe_state_issue, null);
  assert.match(out.errors.join("\n"), /probe_state_issue/);
});
