// Run: node --test plugins/prototype/lib/prototype-settings.test.mjs
// test-scope: plugins/prototype/schemas/prototype.schema.json plugins/prototype/reference/levels.default.yaml plugins/prototype/lib/config-cascade.mjs plugins/prototype/lib/resolve-convention-home.sh
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, describe, it } from "node:test";

import { reportLine, resolveLevel } from "./prototype-settings.mjs";

const CLI = path.join(import.meta.dirname, "prototype-settings.mjs");
const base = realpathSync(mkdtempSync(path.join(os.tmpdir(), "prototype-settings-test-")));
after(() => rmSync(base, { recursive: true, force: true }));

let n = 0;
/** A new project directory holding the given files under docs/conventions; `git` makes it a repository. */
function project(files = {}, { git = false } = {}) {
  const root = path.join(base, `p${++n}`);
  mkdirSync(path.join(root, "docs/conventions"), { recursive: true });
  for (const [name, text] of Object.entries(files)) writeFileSync(path.join(root, "docs/conventions", name), text);
  if (git) spawnSync("git", ["init", "-q", root], { encoding: "utf8" });
  return root;
}
const team = (text) => ({ "prototype.yaml": text });
const run = (root, request = {}) => resolveLevel({ projectRoot: root, home: "docs/conventions", ...request });
const UNSET = "${user_config.level}";

describe("each layer", () => {
  it("resolves the default with nothing set", () => {
    const r = run(project(), { userConfig: UNSET });
    assert.equal(r.level, "standard");
    assert.equal(r.layer, "default");
    assert.deepEqual(r.notices, []);
  });

  it("takes the userConfig option over the default", () => {
    const r = run(project(), { userConfig: "sketch" });
    assert.deepEqual([r.level, r.layer], ["sketch", "userConfig"]);
  });

  it("takes the team file over userConfig and names the file", () => {
    const r = run(project(team("level: full\n")), { userConfig: "sketch" });
    assert.deepEqual([r.level, r.layer, r.path], ["full", "team", "docs/conventions/prototype.yaml"]);
  });

  it("takes the personal override over the team file", () => {
    const r = run(project({ ...team("level: full\n"), "prototype.local.yaml": "level: sketch\n" }));
    assert.deepEqual([r.level, r.layer, r.path], ["sketch", "personal", "docs/conventions/prototype.local.yaml"]);
  });

  it("takes a level the prompt names over every file", () => {
    const r = run(project({ ...team("level: sketch\n"), "prototype.local.yaml": "level: sketch\n" }), { prompt: "full" });
    assert.deepEqual([r.level, r.layer, r.path], ["full", "prompt", null]);
  });

  it("takes the --level argument over the prompt", () => {
    const r = run(project(), { prompt: "full", argument: "sketch" });
    assert.deepEqual([r.level, r.layer], ["sketch", "argument"]);
  });

  it("reads no file layer when no convention home applies", () => {
    const r = resolveLevel({ projectRoot: project(team("level: full\n")), home: null });
    assert.deepEqual([r.level, r.layer], ["standard", "default"]);
  });
});

describe("an invalid value drops its layer", () => {
  it("falls to the default, not to userConfig, when the team value names no level", () => {
    const r = run(project(team("level: huge\n")), { userConfig: "sketch" });
    assert.deepEqual([r.level, r.layer], ["standard", "default"]);
    assert.equal(r.notices.length, 1);
    assert.match(r.notices[0], /^team \(.*docs\/conventions\/prototype\.yaml\): "level": "huge" is not one of "sketch", "standard", "full"$/);
  });

  it("keeps the team value under an invalid personal value", () => {
    const r = run(project({ ...team("level: full\n"), "prototype.local.yaml": "level: huge\n" }));
    assert.deepEqual([r.level, r.layer], ["full", "team"]);
    assert.match(r.notices.join("\n"), /local \(.*prototype\.local\.yaml\): "level": "huge" is not one of/);
  });

  it("falls to the default for an invalid userConfig value", () => {
    const r = run(project(), { userConfig: "huge" });
    assert.deepEqual([r.level, r.layer], ["standard", "default"]);
    assert.match(r.notices.join("\n"), /userConfig: "level": "huge" is not one of/);
  });

  it("drops an invalid dimension value to the shipped one", () => {
    const r = run(project(team("level: full\nlevels:\n  full:\n    variants: 9\n")));
    assert.equal(r.definition.variants, 5);
    assert.match(r.notices.join("\n"), /"levels\.full\.variants": 9 must be at most 5/);
  });

  it("ignores a prompt or argument that names no level", () => {
    const r = run(project(), { prompt: "huge", argument: "Huge" });
    assert.deepEqual([r.level, r.layer], ["standard", "default"]);
    assert.equal(r.notices.length, 2);
    assert.match(r.notices[0], /^prompt level "huge" is not one of sketch, standard, full; ignored$/);
  });
});

describe("the levels map is open", () => {
  const added = "level: design-system\nlevels:\n  design-system:\n    variants: 4\n    screens: one\n    states: planned\n    evidence: per-state\n    phrases: [design system]\n";

  it("accepts a level the team file adds and keeps the shipped three", () => {
    const r = run(project(team(added)));
    assert.deepEqual([r.level, r.layer], ["design-system", "team"]);
    assert.deepEqual(r.definition, { variants: 4, screens: "one", states: "planned", evidence: "per-state", extra_states: [], offers: [], phrases: ["design system"] });
    assert.deepEqual(Object.keys(r.phrases), ["sketch", "standard", "full", "design-system"]);
    assert.deepEqual(r.notices, []);
  });

  it("lets the prompt select a team-added level", () => {
    const r = run(project(team(added.replace("level: design-system\n", ""))), { prompt: "design-system" });
    assert.deepEqual([r.level, r.layer], ["design-system", "prompt"]);
  });

  it("refines a shipped level dimension by dimension", () => {
    const r = run(project(team("level: full\nlevels:\n  full:\n    variants: 4\n")));
    assert.equal(r.definition.variants, 4);
    assert.deepEqual(r.definition.extra_states, ["narrow-viewport", "dark-scheme", "reduced-motion"]);
  });

  it("refuses an incomplete added level, so a level naming it drops its layer", () => {
    const r = run(project(team("level: thin\nlevels:\n  thin:\n    variants: 2\n")));
    assert.deepEqual([r.level, r.layer], ["standard", "default"]);
    assert.match(r.notices.join("\n"), /level thin: sets no screens, states, evidence; not a level/);
    assert.match(r.notices.join("\n"), /"level": "thin" is not one of/);
  });

  it("refuses a level name outside the name pattern", () => {
    const r = run(project(team("levels:\n  Big_One:\n    variants: 2\n    screens: one\n    states: core\n    evidence: per-variant\n")));
    assert.match(r.notices.join("\n"), /level "Big_One": a level name is lowercase/);
    assert.equal(Object.hasOwn(r.phrases, "Big_One"), false);
  });
});

describe("the shipped data", () => {
  it("defines sketch, standard and full completely and without error", () => {
    const r = run(project());
    assert.deepEqual(Object.keys(r.phrases), ["sketch", "standard", "full"]);
    assert.deepEqual(r.notices, []);
  });

  it("makes standard the run the skill text describes", () => {
    const r = run(project());
    assert.deepEqual(r.definition, { variants: 3, screens: "flow", states: "planned", extra_states: [], evidence: "per-state", offers: ["review-mode", "real-stack"], phrases: [] });
  });
});

describe("the report line", () => {
  it("names the level and the layer", () => {
    assert.equal(reportLine({ level: "full", layer: "prompt" }), "level: full (prompt)");
    assert.equal(reportLine(run(project(), { userConfig: "" })), "level: standard (default)");
  });

  it("is printed by the CLI after the JSON, reading the team file in a repository", () => {
    const root = project(team("level: sketch\n"), { git: true });
    const out = spawnSync("node", [CLI, "resolve", "--option", UNSET], { cwd: root, encoding: "utf8" });
    assert.equal(out.status, 0, out.stderr);
    const [json, line] = out.stdout.trimEnd().split("\n");
    assert.equal(JSON.parse(json).definition.variants, 2);
    assert.equal(line, "level: sketch (team)");
  });

  it("says why no file is read outside a repository", () => {
    const root = project(team("level: sketch\n"));
    const out = spawnSync("node", [CLI, "resolve", "--option", "", "--project", root], { cwd: root, encoding: "utf8", env: { ...process.env, GIT_CEILING_DIRECTORIES: base } });
    assert.equal(out.status, 0, out.stderr);
    const lines = out.stdout.trimEnd().split("\n");
    assert.equal(lines[1], "level: standard (default)");
    assert.match(lines[2], /^notice: no convention home applies to this project, so no settings file is read$/);
  });

  it("exits 2 on a usage error", () => {
    const out = spawnSync("node", [CLI, "resolve"], { encoding: "utf8" });
    assert.equal(out.status, 2);
  });
});
