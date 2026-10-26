// The four-layer config resolver, against the fixture tree under fixtures/config-cascade and
// throwaway trees in the temp directory. Expected values are worked by hand from the fixture files.
import { strict as assert } from "node:assert";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
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
const userHome = join(fixtures, "no-user-home"); // absent on purpose: there is no user-global layer
const projectRoot = join(fixtures, "project");
const conventions = join(projectRoot, "docs/conventions");
const base = { plugin: "example", projectRoot, home: "docs/conventions", schema, defaults, teamOnly: ["routing"], userHome };
const layer = (result, name) => result.layers.find((l) => l.name === name);
// Symlinks need a privilege on Windows, and /dev/zero is POSIX.
const POSIX = process.platform !== "win32";

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

describe("the fixture tree, all four layers", () => {
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
    assert.equal(r.values.widget.limit, 10);
    assert.equal(r.values.widget.verbose, true);
    assert.equal(r.values.widget.note, null);
  });

  test("*.disable lists union across layers; other lists take the later layer's list", () => {
    assert.deepEqual(r.values.widget.disable, ["alpha", "gamma", "delta"]);
    assert.deepEqual(r.values.widget.tags, ["two"]);
  });

  test("provenance names the layer for each key, and every contributing layer for a union", () => {
    assert.deepEqual(r.provenance, {
      "widget.mode": "team",
      "widget.label": "local",
      "widget.limit": "defaults",
      "widget.verbose": "userConfig",
      "widget.note": "defaults",
      "widget.disable": ["defaults", "team", "local"],
      "widget.tags": "local",
      routing: "team",
    });
  });

  test("a team-only key is accepted in the team layer and rejected in the personal one", () => {
    assert.deepEqual(r.values.routing, [{ id: "r1" }]);
    const errors = layer(r, "local").errors;
    assert.ok(errors.some((e) => e.includes("routing") && e.includes("team")), errors.join("\n"));
  });

  test("an invalid personal value is dropped and the team value wins, with an error naming layer, path and key", () => {
    const local = layer(r, "local");
    assert.equal(local.state, "loaded");
    const e = local.errors.find((m) => m.includes("widget.mode"));
    assert.ok(e, local.errors.join("\n"));
    assert.ok(e.includes("local") && e.includes(join(conventions, "example.local.yaml")), e);
  });

  test("prose paths run team, personal", () => {
    assert.deepEqual(r.prose, [join(conventions, "example.md"), join(conventions, "example.local.md")]);
  });

  test("a .local.md section replaces the team section with the same heading and leaves the others", () => {
    assert.deepEqual(
      r.sections.map(({ heading, layer: from }) => [heading, from]),
      [[null, "team"], ["Rules", "local"], ["Notes", "team"], ["Tail", "team"], ["Mine", "local"]],
    );
    const text = (heading) => r.sections.find((s) => s.heading === heading).text;
    assert.match(text("Rules"), /Personal rules text/);
    assert.doesNotMatch(text("Rules"), /Team rules text/);
    // The fenced "## Rules" inside the team Notes section is code, not a heading.
    assert.match(text("Notes"), /Team notes text[\s\S]*## Rules/);
    assert.match(text(null), /Team preamble/);
    assert.ok(!r.sections.some((s) => /Personal preamble/.test(s.text)), "the personal preamble does not replace the team's");
  });

  test("layers are reported in order with their files", () => {
    assert.deepEqual(
      r.layers.map((l) => [l.name, l.state]),
      [["defaults", "loaded"], ["userConfig", "loaded"], ["team", "loaded"], ["local", "loaded"]],
    );
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
  test("the layer order is default < userConfig < team < personal", () => {
    const team = "project/docs/conventions/example.yaml";
    const local = "project/docs/conventions/example.local.yaml";
    const userConfig = { widget_label: "from userConfig" };

    const overDefault = resolve({ ...tree({}), userConfig });
    assert.equal(overDefault.values.widget.label, "from userConfig");
    assert.equal(overDefault.provenance["widget.label"], "userConfig");

    const overUserConfig = resolve({ ...tree({ [team]: "widget:\n  label: from team\n" }), userConfig });
    assert.equal(overUserConfig.values.widget.label, "from team");
    assert.equal(overUserConfig.provenance["widget.label"], "team");

    const overTeam = resolve(tree({ [team]: "widget:\n  label: from team\n", [local]: "widget:\n  label: from local\n" }));
    assert.equal(overTeam.values.widget.label, "from local");
    assert.equal(overTeam.provenance["widget.label"], "local");
  });

  test("minimum, maximum, minItems and maxItems are enforced; a breaking leaf keeps the lower layer's value", () => {
    const bounded = {
      type: "object",
      properties: {
        b: {
          type: "object",
          properties: {
            curve: { type: "array", items: { type: "number" }, minItems: 4, maxItems: 4 },
            ms: { type: "integer", minimum: 0, maximum: 1000 },
          },
        },
      },
    };
    const lower = { b: { curve: [0.1, 0.2, 0.3, 0.4], ms: 200 } };
    const team = "project/docs/conventions/example.yaml";
    const r = resolve({
      ...tree({ [team]: "b:\n  curve:\n    - 0.5\n  ms: -5\n" }),
      schema: bounded,
      defaults: lower,
      teamOnly: [],
    });
    assert.deepEqual(r.values.b, lower.b);
    const errors = layer(r, "team").errors.join("\n");
    assert.match(errors, /curve.*at least 4 items/);
    assert.match(errors, /ms.*at least 0/);

    const tooMany = resolve({ ...tree({ [team]: "b:\n  curve:\n    - 1\n    - 2\n    - 3\n    - 4\n    - 5\n" }), schema: bounded, defaults: lower, teamOnly: [] });
    assert.deepEqual(tooMany.values.b.curve, lower.b.curve);
    assert.match(layer(tooMany, "team").errors.join("\n"), /curve.*at most 4 items/);

    const tooBig = resolve({ ...tree({ [team]: "b:\n  ms: 1001\n" }), schema: bounded, defaults: lower, teamOnly: [] });
    assert.equal(tooBig.values.b.ms, lower.b.ms);
    assert.match(layer(tooBig, "team").errors.join("\n"), /ms.*1001 must be at most 1000/);

    const atMost = resolve({ ...tree({ [team]: "b:\n  ms: 1000\n" }), schema: bounded, defaults: lower, teamOnly: [] });
    assert.equal(atMost.values.b.ms, 1000);
    assert.deepEqual(layer(atMost, "team").errors, []);

    const ok = resolve({ ...tree({ [team]: "b:\n  curve:\n    - 1\n    - 2\n    - 3\n    - 4\n  ms: 0\n" }), schema: bounded, defaults: lower, teamOnly: [] });
    assert.deepEqual(ok.values.b, { curve: [1, 2, 3, 4], ms: 0 });
    assert.deepEqual(layer(ok, "team").errors, []);
  });

  test("a key containing a dot is rejected and the lower layer keeps the nested key", () => {
    const open = { type: "object", properties: { w: { type: "object", properties: { s: { type: "integer" } } } } };
    const t = tree({
      "project/docs/conventions/example.yaml": "w.s: 42\n",
    });
    const r = resolve({ ...t, schema: open, defaults: { w: { s: 1 } } });
    assert.deepEqual(r.values, { w: { s: 1 } });
    assert.deepEqual(r.provenance, { "w.s": "defaults" });
    const errors = layer(r, "team").errors;
    assert.equal(errors.length, 1, errors.join("\n"));
    assert.ok(errors[0].startsWith("team (") && errors[0].includes(join(t.projectRoot, "docs/conventions/example.yaml")), errors[0]);
    assert.ok(errors[0].includes('"w.s"'), errors[0]);
  });

  test("a __proto__, constructor or prototype key is rejected even where the schema allows any key", () => {
    const open = { type: "object", properties: { w: { type: "object", properties: {} } } };
    const yaml = "__proto__:\n  polluted: true\nw:\n  constructor: 1\n  prototype: 2\n  ok: 3\n";
    const r = resolve({ ...tree({ "project/docs/conventions/example.yaml": yaml }), schema: open, defaults: {} });
    const errors = layer(r, "team").errors;
    assert.equal(errors.length, 3, errors.join("\n"));
    assert.ok(errors.every((e) => e.includes("reserved")), errors.join("\n"));
    assert.deepEqual(Object.keys(r.values), ["w"]);
    assert.deepEqual(Object.keys(r.values.w), ["ok"]);
    assert.equal(Object.getPrototypeOf(Object.assign({}, r.values)), Object.prototype);
    assert.equal({}.polluted, undefined);
  });

  test("a legacy file is reported once when the project root is the user home", () => {
    const t = tree({ "user/.claude/example.yaml": "widget:\n  label: legacy\n" });
    const r = resolve({ ...t, projectRoot: t.userHome });
    assert.deepEqual(r.legacy, [{ path: join(t.userHome, ".claude/example.yaml"), kind: "claude-user" }]);
  });

  test("absent layers report absent and contribute nothing", () => {
    const r = resolve(tree({}));
    for (const name of ["team", "local"]) assert.equal(layer(r, name).state, "absent");
    assert.deepEqual(r.values, defaults);
    assert.deepEqual(r.prose, []);
    assert.deepEqual(r.legacy, []);
  });

  test("an unparsable file makes its layer invalid; other layers still apply", () => {
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

  test("a file under <userHome>/docs/conventions is not read", () => {
    const r = resolve(
      tree({
        "user/docs/conventions/example.yaml": "widget:\n  label: from user home\n  limit: 99\nrouting:\n  - id: mine\n",
        "user/docs/conventions/example.md": "# user prose\n\n## Rules\n\nuser rules\n",
      }),
    );
    assert.deepEqual(r.values, defaults);
    assert.deepEqual(r.prose, []);
    assert.deepEqual(r.sections, []);
    assert.deepEqual(r.layers.map((l) => l.name), ["defaults", "userConfig", "team", "local"]);
    assert.ok(!JSON.stringify(r).includes("from user home"));
  });

  test("an unknown key is rejected and the rest of the layer applies", () => {
    const r = resolve(tree({ "project/docs/conventions/example.yaml": "widget:\n  color: red\n  label: team\n" }));
    assert.equal(r.values.widget.label, "team");
    assert.equal(r.values.widget.color, undefined);
    assert.ok(layer(r, "team").errors[0].includes("widget.color"));
  });

  test("a reserved key nested inside an open object or list leaf is rejected", () => {
    const open = { type: "object", properties: { free: { type: "object" }, list: { type: "array" }, any: {} } };
    const yaml = "free:\n  a:\n    __proto__:\n      polluted: true\nlist:\n  - constructor: 1\nany:\n  prototype: 2\n";
    const r = resolve({ ...tree({ "project/docs/conventions/example.yaml": yaml }), schema: open, defaults: {} });
    const errors = layer(r, "team").errors;
    assert.equal(errors.length, 3, errors.join("\n"));
    assert.ok(errors.every((e) => e.includes("reserved")), errors.join("\n"));
    assert.deepEqual(r.values, {});
  });

  test("an open object leaf without reserved keys still applies", () => {
    const open = { type: "object", properties: { free: { type: "object" } } };
    const r = resolve({ ...tree({ "project/docs/conventions/example.yaml": "free:\n  a:\n    b: 1\n" }), schema: open, defaults: {} });
    assert.deepEqual(layer(r, "team").errors, []);
    assert.deepEqual(r.values, { free: { a: { b: 1 } } });
  });

  test("a __proto__ key under a closed mapping is rejected as reserved", () => {
    const r = resolve(tree({ "project/docs/conventions/example.yaml": "widget:\n  __proto__:\n    polluted: true\n" }));
    const errors = layer(r, "team").errors;
    assert.equal(errors.length, 1);
    assert.ok(errors[0].includes("reserved"), errors[0]);
    assert.equal({}.polluted, undefined);
    assert.equal(r.values.widget.polluted, undefined);
  });

  test("a rejected value is quoted once, as JSON", () => {
    const r = resolve(tree({ "project/docs/conventions/example.yaml": "widget:\n  mode: turbo\n" }));
    const e = layer(r, "team").errors.find((m) => m.includes("widget.mode"));
    assert.ok(e?.includes('"turbo"') && !e.includes('\\"'), e);
  });

  test("a disable list that adds nothing does not credit its layer", () => {
    const r = resolve(
      tree({
        "project/docs/conventions/example.yaml": "widget:\n  disable: [beta]\n",
        "project/docs/conventions/example.local.yaml": "widget:\n  disable: []\n",
      }),
    );
    assert.deepEqual(r.provenance["widget.disable"].includes("local"), false);
    assert.ok(r.provenance["widget.disable"].includes("team"));
  });

  test("a config block shown inside a tilde fence is not a legacy block", () => {
    const md = "# team\n\n~~~markdown\n```yaml config\nwidget:\n  mode: safe\n```\n~~~\n";
    assert.deepEqual(resolve(tree({ "project/docs/conventions/example.md": md })).legacy, []);
  });

  test("a repository layer refuses a symlinked file and does not read through it", { skip: !POSIX }, () => {
    const t = tree({ "secret.txt": "ghp_notarealtoken\n" });
    mkdirSync(join(t.projectRoot, "docs/conventions"), { recursive: true });
    symlinkSync(join(t.root, "secret.txt"), join(t.projectRoot, "docs/conventions/example.yaml"));
    symlinkSync(join(t.root, "secret.txt"), join(t.projectRoot, "docs/conventions/example.local.md"));
    const r = resolve(t);
    const team = layer(r, "team");
    assert.equal(team.state, "invalid");
    assert.ok(team.errors.some((e) => e.includes("symlink")), team.errors.join("\n"));
    assert.ok(!JSON.stringify(r).includes("ghp_"), "file contents leaked");
    assert.ok(layer(r, "local").errors.some((e) => e.includes("symlink")));
    assert.deepEqual(r.prose, []);
  });

  test("a refused Markdown file makes its layer invalid; the layer's YAML still applies", { skip: !POSIX }, () => {
    const t = tree({ "secret.txt": "x\n", "project/docs/conventions/example.yaml": "widget:\n  label: team\n" });
    symlinkSync(join(t.root, "secret.txt"), join(t.projectRoot, "docs/conventions/example.md"));
    symlinkSync(join(t.root, "secret.txt"), join(t.projectRoot, "docs/conventions/example.local.md"));
    const r = resolve(t);
    assert.equal(layer(r, "team").state, "invalid");
    assert.equal(layer(r, "local").state, "invalid");
    assert.equal(r.values.widget.label, "team");
    assert.deepEqual(r.prose, []);
  });

  test("a layer file that is not a regular file is refused without being read", { skip: !POSIX }, () => {
    const t = tree({});
    mkdirSync(join(t.projectRoot, "docs/conventions"), { recursive: true });
    mkdirSync(join(t.projectRoot, "docs/conventions/example.yaml"));
    const r = resolve(t);
    assert.equal(layer(r, "team").state, "invalid");
    assert.ok(layer(r, "team").errors[0].includes("not a regular file"), layer(r, "team").errors[0]);
  });

  test("a relative convention home that a symlink carries outside the project is refused", { skip: !POSIX }, () => {
    const t = tree({ "outside/example.yaml": "widget:\n  label: outside\n" });
    mkdirSync(join(t.projectRoot, "docs"), { recursive: true });
    symlinkSync(join(t.root, "outside"), join(t.projectRoot, "docs/conventions"));
    const r = resolve(t);
    assert.notEqual(r.values.widget.label, "outside");
    assert.equal(layer(r, "team").state, "invalid");
    assert.equal(layer(r, "local").state, "invalid");
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

describe("the invalid-value rule", () => {
  const team = "project/docs/conventions/example.yaml";
  const local = "project/docs/conventions/example.local.yaml";

  test("an invalid personal value is dropped and the team value wins", () => {
    const r = resolve(tree({ [team]: "widget:\n  mode: safe\n", [local]: "widget:\n  mode: turbo\n" }));
    assert.equal(r.values.widget.mode, "safe");
    assert.equal(r.provenance["widget.mode"], "team");
    const e = layer(r, "local").errors.find((m) => m.includes("widget.mode"));
    assert.ok(e?.startsWith("local (") && e.includes("example.local.yaml") && e.includes('"turbo"'), e);
  });

  test("an invalid team value falls to the default, never to a lower userConfig value", () => {
    const r = resolve({ ...tree({ [team]: "widget:\n  mode: turbo\n" }), userConfig: { widget_mode: "strict" } });
    assert.equal(r.values.widget.mode, "fast");
    assert.equal(r.provenance["widget.mode"], "defaults");
    assert.ok(layer(r, "team").errors.some((m) => m.includes("widget.mode")));
  });

  test("a valid personal value still wins over an invalid team one", () => {
    const r = resolve({ ...tree({ [team]: "widget:\n  mode: turbo\n", [local]: "widget:\n  mode: strict\n" }), userConfig: { widget_mode: "safe" } });
    assert.equal(r.values.widget.mode, "strict");
    assert.equal(r.provenance["widget.mode"], "local");
  });

  test("an invalid key does not take its valid siblings down", () => {
    const r = resolve({ ...tree({ [team]: "widget:\n  mode: turbo\n  label: kept\n" }), userConfig: { widget_mode: "strict" } });
    assert.equal(r.values.widget.label, "kept");
    assert.equal(r.values.widget.mode, "fast");
  });
});

describe("policy floors", () => {
  const floors = {
    "policy.locked": "team-only",
    "policy.ceiling": "lowest-value",
    "policy.audit": "any-layer-wins",
    "policy.level": "stricter-value",
    "policy.free": "no-floor",
  };
  const project = (kind) => join(fixtures, "floors", kind);
  const floored = (kind) => resolve({ ...base, projectRoot: project(kind), floors, defaults: {}, teamOnly: [] });

  describe("a personal value that loosens a floor key", () => {
    const r = floored("loose");

    for (const [key, team, personal] of [
      ["policy.locked", "fixed", "other"],
      ["policy.ceiling", 10, 20],
      ["policy.audit", true, false],
      ["policy.level", "medium", "low"],
    ]) {
      test(`${key} (${floors[key]}) is rejected and the team value stands`, () => {
        const [group, leaf] = key.split(".");
        assert.equal(r.values[group][leaf], team);
        assert.equal(r.provenance[key], "team");
        const e = layer(r, "local").errors.find((m) => m.includes(`"${key}"`));
        assert.ok(e, layer(r, "local").errors.join("\n"));
        assert.ok(e.startsWith("local (") && e.includes(join(project("loose"), "docs/conventions/example.local.yaml")) && e.includes(floors[key]), e);
        assert.ok(e.includes(JSON.stringify(personal)), e);
      });
    }

    test("a key marked no-floor keeps the ordinary precedence", () => {
      assert.equal(r.values.policy.free, 2);
      assert.equal(r.provenance["policy.free"], "local");
    });
  });

  describe("a personal value that tightens a floor key", () => {
    const r = floored("tight");

    for (const [key, personal] of [
      ["policy.locked", "fixed"],
      ["policy.ceiling", 5],
      ["policy.audit", "report"],
      ["policy.level", "high"],
    ]) {
      test(`${key} (${floors[key]}) is accepted`, () => {
        const [group, leaf] = key.split(".");
        assert.equal(r.values[group][leaf], personal);
        assert.equal(r.provenance[key], "local");
      });
    }

    test("no floor error is reported", () => {
      assert.deepEqual(layer(r, "local").errors, []);
    });
  });

  test("team-only lets a personal list add items but not drop a team item", () => {
    const open = { type: "object", properties: { gates: { type: "array", items: { type: "string" } } } };
    const run = (personal) =>
      resolve({
        ...tree({
          "project/docs/conventions/example.yaml": "gates:\n  - a\n  - b\n",
          "project/docs/conventions/example.local.yaml": personal,
        }),
        schema: open,
        defaults: {},
        teamOnly: [],
        floors: { gates: "team-only" },
      });
    assert.deepEqual(run("gates:\n  - a\n  - b\n  - c\n").values.gates, ["a", "b", "c"]);
    const dropped = run("gates:\n  - a\n");
    assert.deepEqual(dropped.values.gates, ["a", "b"]);
    assert.ok(layer(dropped, "local").errors.some((e) => e.includes('"gates"')));
  });

  test("a floor binds only a key the team layer set", () => {
    const r = resolve({
      ...tree({ "project/docs/conventions/example.local.yaml": "policy:\n  ceiling: 99\n" }),
      floors,
      defaults: { policy: { ceiling: 10 } },
      teamOnly: [],
    });
    assert.equal(r.values.policy.ceiling, 99);
  });

  test("stricter-value takes an explicit scale", () => {
    const run = (personal) =>
      resolve({
        ...tree({
          "project/docs/conventions/example.yaml": "widget:\n  mode: safe\n",
          "project/docs/conventions/example.local.yaml": `widget:\n  mode: ${personal}\n`,
        }),
        floors: { "widget.mode": { direction: "stricter-value", scale: ["strict", "safe", "fast"] } },
      });
    assert.equal(run("fast").values.widget.mode, "fast");
    assert.equal(run("strict").values.widget.mode, "safe");
  });

  test("stricter-value accepts a personal value equal to the team value even without a scale", () => {
    const open = { type: "object", properties: { grade: { type: "string" } } };
    const r = resolve({
      ...tree({ "project/docs/conventions/example.yaml": "grade: b\n", "project/docs/conventions/example.local.yaml": "grade: b\n" }),
      schema: open,
      defaults: {},
      teamOnly: [],
      floors: { grade: "stricter-value" },
    });
    assert.equal(r.values.grade, "b");
    assert.equal(r.provenance.grade, "local");
    assert.deepEqual(layer(r, "local").errors, []);
  });

  test("a convention home whose name starts with two dots is inside the project", () => {
    const t = tree({ "project/..conf/example.yaml": "widget:\n  label: dotted\n" });
    assert.equal(resolve({ ...t, home: "..conf" }).values.widget.label, "dotted");
  });

  test("an unknown Floor direction throws", () => {
    assert.throws(() => resolve({ ...tree({}), floors: { "widget.mode": "firmer" } }), /firmer/);
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
