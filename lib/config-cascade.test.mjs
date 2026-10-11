// The five-layer config resolver, against the fixture tree under fixtures/config-cascade and
// throwaway trees in the temp directory. Expected values are worked by hand from the fixture files.
import { strict as assert } from "node:assert";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const { resolve } = await import("./config-cascade.mjs");
const { parse } = await import("./yaml-subset.mjs");

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, "fixtures/config-cascade");
const schema = JSON.parse(readFileSync(join(fixtures, "schema.json"), "utf8"));
const defaults = parse(readFileSync(join(fixtures, "defaults.yaml"), "utf8"));
const userHome = join(fixtures, "user");
const projectRoot = join(fixtures, "project");
const conventions = join(projectRoot, "docs/conventions");
const base = { plugin: "example", projectRoot, home: "docs/conventions", schema, defaults, teamOnly: ["routing"], userHome };
const layer = (result, name) => result.layers.find((l) => l.name === name);

const scratch = [];
after(() => scratch.forEach((d) => rmSync(d, { recursive: true, force: true })));
/** A temp tree: { "relative/path": "content" } under a fresh directory with user/ and project/. */
function tree(files) {
  const root = mkdtempSync(join(tmpdir(), "config-cascade-"));
  scratch.push(root);
  mkdirSync(join(root, "user"));
  mkdirSync(join(root, "project"));
  for (const [path, content] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), content);
  }
  return { ...base, userHome: join(root, "user"), projectRoot: join(root, "project"), root };
}

describe("the fixture tree, all five layers", () => {
  const userConfig = {
    widget_label: "uc label",
    widget_verbose: "true",
    widget_limit: "${user_config.widget_limit}",
    widget_mode: "",
  };
  const r = resolve({ ...base, userConfig });

  test("later layers win per scalar key", () => {
    assert.equal(r.values.widget.mode, "safe");
    assert.equal(r.values.widget.label, "local label");
    assert.equal(r.values.widget.limit, 20);
    assert.equal(r.values.widget.verbose, true);
    assert.equal(r.values.widget.note, null);
  });

  test("*.disable lists union across layers; other lists take the later layer's list", () => {
    assert.deepEqual(r.values.widget.disable, ["alpha", "beta", "gamma", "delta"]);
    assert.deepEqual(r.values.widget.tags, ["two"]);
  });

  test("provenance names the layer for each key, and every contributing layer for a union", () => {
    assert.deepEqual(r.provenance, {
      "widget.mode": "team",
      "widget.label": "local",
      "widget.limit": "user",
      "widget.verbose": "userConfig",
      "widget.note": "defaults",
      "widget.disable": ["defaults", "user", "team", "local"],
      "widget.tags": "local",
      routing: "team",
    });
  });

  test("a team-only key is accepted in the team layer and rejected in the personal one", () => {
    assert.deepEqual(r.values.routing, [{ id: "r1" }]);
    const errors = layer(r, "local").errors;
    assert.ok(errors.some((e) => e.includes("routing") && e.includes("team")), errors.join("\n"));
  });

  test("a value valid in layer 4 and invalid in layer 5 keeps layer 4's value, with an error naming layer, path and key", () => {
    const local = layer(r, "local");
    assert.equal(local.state, "loaded");
    const e = local.errors.find((m) => m.includes("widget.mode"));
    assert.ok(e, local.errors.join("\n"));
    assert.ok(e.includes("local") && e.includes(join(conventions, "example.local.yaml")), e);
  });

  test("prose paths run user, team, personal", () => {
    assert.deepEqual(r.prose, [
      join(userHome, "docs/conventions/example.md"),
      join(conventions, "example.md"),
      join(conventions, "example.local.md"),
    ]);
  });

  test("layers are reported in order with their files", () => {
    assert.deepEqual(
      r.layers.map((l) => [l.name, l.state]),
      [["defaults", "loaded"], ["userConfig", "loaded"], ["user", "loaded"], ["team", "loaded"], ["local", "loaded"]],
    );
    assert.equal(layer(r, "user").path, join(userHome, "docs/conventions/example.yaml"));
    assert.equal(layer(r, "team").path, join(conventions, "example.yaml"));
    assert.deepEqual(layer(r, "team").errors, []);
  });

  test("legacy locations and the fenced config block are reported, not read", () => {
    // Every legacy file sets mode strict and a "legacy ... label"; neither resolves from any layer.
    assert.notEqual(r.values.widget.mode, "strict");
    assert.doesNotMatch(r.values.widget.label, /legacy|other plugin/);
    const legacy = [...r.legacy].sort((a, b) => a.path.localeCompare(b.path));
    assert.deepEqual(legacy, [
      { path: join(conventions, "example.md"), kind: "fenced-block" },
      { path: join(projectRoot, ".claude/example.json"), kind: "claude-project" },
      { path: join(projectRoot, ".claude/example.local.md"), kind: "claude-local" },
      { path: join(userHome, ".claude/example.yaml"), kind: "claude-user" },
    ].sort((a, b) => a.path.localeCompare(b.path)));
  });
});

describe("userConfig", () => {
  test("an empty string or an unrendered placeholder is unset", () => {
    const r = resolve({ ...tree({}), userConfig: { widget_label: "", widget_mode: "${user_config.widget_mode}" } });
    assert.equal(r.values.widget.label, "default label");
    assert.equal(r.values.widget.mode, "fast");
    assert.equal(r.provenance["widget.mode"], "defaults");
    assert.deepEqual(layer(r, "userConfig").errors, []);
  });

  test("a value with shell metacharacters is just a string", () => {
    const label = "$(touch pwned); `id` | rm -rf ~ && echo '\"'";
    const r = resolve({ ...tree({}), userConfig: { widget_label: label } });
    assert.equal(r.values.widget.label, label);
    assert.equal(r.provenance["widget.label"], "userConfig");
  });

  test("string forms of integers and booleans take the schema's type", () => {
    const r = resolve({ ...tree({}), userConfig: { widget_limit: "7", widget_verbose: "false" } });
    assert.equal(r.values.widget.limit, 7);
    assert.equal(r.values.widget.verbose, false);
    assert.equal(r.provenance["widget.verbose"], "userConfig");
  });

  test("a list key or a team-only key is rejected; the rest still applies", () => {
    const r = resolve({ ...tree({}), userConfig: { widget_disable: "zeta", routing: "x", widget_label: "kept" } });
    const errors = layer(r, "userConfig").errors;
    assert.equal(errors.length, 2, errors.join("\n"));
    assert.ok(errors.some((e) => e.includes("widget.disable")));
    assert.ok(errors.some((e) => e.includes("routing")));
    assert.deepEqual(r.values.widget.disable, ["alpha"]);
    assert.equal(r.values.routing, undefined);
    assert.equal(r.values.widget.label, "kept");
  });

  test("an invalid value keeps the default", () => {
    const r = resolve({ ...tree({}), userConfig: { widget_mode: "turbo", widget_limit: "many" } });
    assert.equal(r.values.widget.mode, "fast");
    assert.equal(r.values.widget.limit, 10);
    assert.equal(layer(r, "userConfig").errors.length, 2);
  });

  test("an absent userConfig is an absent layer", () => {
    assert.equal(layer(resolve(tree({})), "userConfig").state, "absent");
  });

  test("a flattened-name collision in the schema throws", () => {
    const clash = {
      type: "object",
      properties: {
        a_b: { type: "string" },
        a: { type: "object", properties: { b: { type: "string" } } },
      },
    };
    assert.throws(() => resolve({ ...tree({}), schema: clash, defaults: {} }), /a_b/);
  });
});

describe("file layers", () => {
  test("each later file layer beats the one before it on a valid scalar", () => {
    const user = "user/docs/conventions/example.yaml";
    const team = "project/docs/conventions/example.yaml";
    const local = "project/docs/conventions/example.local.yaml";
    const userConfig = { widget_label: "from userConfig" };

    const overUserConfig = resolve({ ...tree({ [user]: "widget:\n  label: from user\n" }), userConfig });
    assert.equal(overUserConfig.values.widget.label, "from user");
    assert.equal(overUserConfig.provenance["widget.label"], "user");

    const overUser = resolve({ ...tree({ [user]: "widget:\n  label: from user\n", [team]: "widget:\n  label: from team\n" }), userConfig });
    assert.equal(overUser.values.widget.label, "from team");
    assert.equal(overUser.provenance["widget.label"], "team");

    const overTeam = resolve(tree({ [team]: "widget:\n  label: from team\n", [local]: "widget:\n  label: from local\n" }));
    assert.equal(overTeam.values.widget.label, "from local");
    assert.equal(overTeam.provenance["widget.label"], "local");
  });

  test("a key containing a dot is rejected and the lower layer keeps the nested key", () => {
    const open = { type: "object", properties: { w: { type: "object", properties: { s: { type: "integer" } } } } };
    const t = tree({
      "user/docs/conventions/example.yaml": "w:\n  s: 1\n",
      "project/docs/conventions/example.yaml": "w.s: 42\n",
    });
    const r = resolve({ ...t, schema: open, defaults: {} });
    assert.deepEqual(r.values, { w: { s: 1 } });
    assert.deepEqual(r.provenance, { "w.s": "user" });
    const errors = layer(r, "team").errors;
    assert.equal(errors.length, 1, errors.join("\n"));
    assert.ok(errors[0].startsWith("team (") && errors[0].includes(join(t.projectRoot, "docs/conventions/example.yaml")), errors[0]);
    assert.ok(errors[0].includes('"w.s"'), errors[0]);
  });

  test("a __proto__ key a schema allows lands as an own property, never a prototype", () => {
    const open = { type: "object", properties: { w: { type: "object", properties: {} } } };
    const yaml = "__proto__:\n  polluted: true\nw:\n  __proto__:\n    polluted: true\n";
    const r = resolve({ ...tree({ "project/docs/conventions/example.yaml": yaml }), schema: open, defaults: {} });
    assert.deepEqual(layer(r, "team").errors, []);
    assert.equal(Object.getPrototypeOf(r.values), Object.prototype);
    assert.equal(Object.getPrototypeOf(r.values.w), Object.prototype);
    assert.equal(r.values.polluted, undefined);
    assert.equal(r.values.w.polluted, undefined);
    assert.equal({}.polluted, undefined);
    assert.ok(Object.hasOwn(r.values, "__proto__") && Object.hasOwn(r.values.w, "__proto__"));
    assert.equal(r.provenance.polluted, undefined);
    assert.ok(Object.hasOwn(r.provenance, "__proto__"));
  });

  test("a legacy file is reported once when the project root is the user home", () => {
    const t = tree({ "user/.claude/example.yaml": "widget:\n  label: legacy\n" });
    const r = resolve({ ...t, projectRoot: t.userHome });
    assert.deepEqual(r.legacy, [{ path: join(t.userHome, ".claude/example.yaml"), kind: "claude-user" }]);
  });

  test("absent layers report absent and contribute nothing", () => {
    const r = resolve(tree({}));
    for (const name of ["user", "team", "local"]) assert.equal(layer(r, name).state, "absent");
    assert.deepEqual(r.values, defaults);
    assert.deepEqual(r.prose, []);
    assert.deepEqual(r.legacy, []);
  });

  test("an unparseable file makes its layer invalid; other layers still apply", () => {
    const t = tree({
      "project/docs/conventions/example.yaml": "widget:\n  mode: {fast: 1}\n",
      "project/docs/conventions/example.local.yaml": "widget:\n  label: mine\n",
    });
    const r = resolve(t);
    const team = layer(r, "team");
    assert.equal(team.state, "invalid");
    assert.equal(team.errors.length, 1);
    assert.ok(team.errors[0].includes(join(t.projectRoot, "docs/conventions/example.yaml")), team.errors[0]);
    assert.ok(team.errors[0].includes("line 2"), team.errors[0]);
    assert.equal(r.values.widget.mode, "fast");
    assert.equal(r.values.widget.label, "mine");
  });

  test("a top level that is not a mapping is invalid", () => {
    const r = resolve(tree({ "project/docs/conventions/example.yaml": "- widget\n" }));
    assert.equal(layer(r, "team").state, "invalid");
  });

  test("empty and comment-only files load and contribute nothing", () => {
    const r = resolve(tree({
      "project/docs/conventions/example.yaml": "",
      "project/docs/conventions/example.local.yaml": "# nothing set yet\n\n",
    }));
    assert.equal(layer(r, "team").state, "loaded");
    assert.equal(layer(r, "local").state, "loaded");
    assert.deepEqual(layer(r, "local").errors, []);
    assert.deepEqual(r.values, defaults);
  });

  test("a team-only key is rejected in the user-global layer", () => {
    const r = resolve(tree({ "user/docs/conventions/example.yaml": "routing:\n  - id: mine\n" }));
    assert.equal(r.values.routing, undefined);
    assert.equal(layer(r, "user").errors.length, 1);
  });

  test("an unknown key is rejected and the rest of the layer applies", () => {
    const r = resolve(tree({ "project/docs/conventions/example.yaml": "widget:\n  colour: red\n  label: team\n" }));
    assert.equal(r.values.widget.label, "team");
    assert.equal(r.values.widget.colour, undefined);
    assert.ok(layer(r, "team").errors[0].includes("widget.colour"));
  });

  test("a __proto__ key is data, never a prototype", () => {
    const r = resolve(tree({ "project/docs/conventions/example.yaml": "widget:\n  __proto__:\n    polluted: true\n" }));
    assert.equal(layer(r, "team").errors.length, 1);
    assert.equal({}.polluted, undefined);
    assert.equal(r.values.widget.polluted, undefined);
  });

  test("a layer with only a Markdown file loads and supplies prose", () => {
    const t = tree({ "project/docs/conventions/example.md": "# team\n" });
    const r = resolve(t);
    assert.equal(layer(r, "team").state, "loaded");
    assert.deepEqual(r.prose, [join(t.projectRoot, "docs/conventions/example.md")]);
  });

  test("a config block shown inside a longer fence is not a legacy block", () => {
    const md = "# team\n\n````markdown\n```yaml config\nwidget:\n  mode: safe\n```\n````\n";
    assert.deepEqual(resolve(tree({ "project/docs/conventions/example.md": md })).legacy, []);
  });

  test("an absolute home is used as given", () => {
    const t = tree({ "elsewhere/example.yaml": "widget:\n  label: abs\n" });
    const r = resolve({ ...t, home: join(t.root, "elsewhere") });
    assert.equal(r.values.widget.label, "abs");
  });
});

describe("contract", () => {
  test("an unsafe plugin name throws", () => {
    assert.throws(() => resolve({ ...tree({}), plugin: "../example" }), /plugin/);
  });

  test("the module never spawns a process", () => {
    const source = readFileSync(join(here, "config-cascade.mjs"), "utf8");
    assert.doesNotMatch(source, /child_process|spawn|execFile/);
  });
});
