import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { compareVersions, KINDS, loadManifest, main, NEEDS, report, validateManifest } from "./prerequisites.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const checker = path.join(here, "prerequisites.mjs");
const schemaFile = path.join(here, "..", "docs", "conventions", "prerequisites", "prerequisites.schema.json");
const posix = process.platform !== "win32";
const work = mkdtempSync(path.join(tmpdir(), "prereq-test-"));
after(() => rmSync(work, { recursive: true, force: true }));

let counter = 0;
function plugin(requires, name = `p${++counter}`) {
  const root = path.join(work, name);
  mkdirSync(path.join(root, ".claude-plugin"), { recursive: true });
  writeFileSync(path.join(root, ".claude-plugin", "plugin.json"), JSON.stringify({ name }));
  if (requires !== undefined) writeFileSync(path.join(root, "prerequisites.json"), JSON.stringify({ requires }));
  return root;
}

// A bin directory of shell scripts standing in for real tools.
function bin(scripts) {
  const dir = path.join(work, `bin${++counter}`);
  mkdirSync(dir);
  for (const [name, body] of Object.entries(scripts)) {
    const file = path.join(dir, name);
    writeFileSync(file, `#!/bin/sh\n${body}\n`);
    chmodSync(file, 0o755);
  }
  return dir;
}

function entry(over = {}) {
  return {
    id: "jq",
    kind: "cli",
    need: "required",
    for: ["plugin"],
    detect: { any: ["jq"] },
    degrade: "Without jq the hooks skip their edit.",
    install: { brew: "jq", docs: "https://jqlang.org/download/" },
    check: "/demo:check",
    ...over,
  };
}

function runMain(argv, ctx = {}) {
  const lines = { stdout: [], stderr: [] };
  const code = main(
    argv,
    { env: { PATH: "" }, cwd: work, stdin: () => "", ...ctx },
    {
      stdout: (s) => lines.stdout.push(s),
      stderr: (s) => lines.stderr.push(s),
    },
  );
  return { code, out: lines.stdout.join("\n"), err: lines.stderr.join("\n") };
}

describe("validateManifest", () => {
  test("accepts one entry of every kind", () => {
    const manifest = {
      $schema: "../schema.json",
      requires: [
        entry(),
        entry({
          id: "python",
          kind: "runtime",
          detect: {
            any: ["python3", "python", "py"],
            version: { args: ["--version"], pattern: "Python ([0-9.]+)", min: "3.12" },
          },
        }),
        entry({
          id: "libx264",
          kind: "system-lib",
          detect: { probe: { args: ["ffmpeg", "-hide_banner", "-encoders"], pattern: "libx264" } },
        }),
        entry({ id: "numpy", kind: "python-pkg", detect: { any: ["python3"], import: "numpy" } }),
        entry({
          id: "playwright-core",
          kind: "node-pkg",
          detect: { module: "playwright-core", paths: ["${CLAUDE_PLUGIN_DATA}/node_modules", "node_modules"] },
        }),
        entry({
          id: "api-key",
          kind: "env",
          need: "optional",
          for: ["skill:lookup"],
          detect: { name: "DEMO_API_KEY" },
        }),
        entry({
          id: "context7",
          kind: "mcp",
          need: "optional",
          for: ["skill:lookup", "hook:probe.sh"],
          detect: { server: "context7" },
        }),
      ],
    };
    assert.deepEqual(validateManifest(manifest), []);
  });

  const cases = [
    ["a version key", { schemaVersion: 2, requires: [entry()] }, /unknown key "schemaVersion"/],
    ["the legacy tools shape", { tools: [{ name: "jq", check: "/demo:check", install: "x" }] }, /unknown key "tools"/],
    ["an empty requires", { requires: [] }, /requires must be a non-empty list/],
    ["a plugin kind", { requires: [entry({ kind: "plugin" })] }, /kind must be one of/],
    ["an unknown need", { requires: [entry({ need: "soft" })] }, /need must be one of/],
    ["a duplicate id", { requires: [entry(), entry()] }, /declared twice/],
    ["a bad id", { requires: [entry({ id: "Has Space" })] }, /id must match/],
    [
      "a missing degrade",
      { requires: [{ ...entry(), degrade: undefined }].map(({ degrade, ...rest }) => rest) },
      /degrade is required/,
    ],
    ["a blank degrade", { requires: [entry({ degrade: "  " })] }, /degrade must say/],
    ["an empty install", { requires: [entry({ install: {} })] }, /at least one hint/],
    [
      "an install that is a command string",
      { requires: [entry({ install: "brew install jq" })] },
      /install must be an object/,
    ],
    ["a bad scope", { requires: [entry({ for: ["agent:x"] })] }, /must be plugin, skill/],
    ["a repeated scope", { requires: [entry({ for: ["plugin", "plugin"] })] }, /repeats a scope/],
    ["a check that is not a skill", { requires: [entry({ check: "run jq --version" })] }, /check must name a skill/],
    [
      "a detect key from another kind",
      { requires: [entry({ detect: { any: ["jq"], name: "X" } })] },
      /unknown key "name"/,
    ],
    ["a cli without any", { requires: [entry({ detect: { local_bin: ["bin/jq"] } })] }, /any is required/],
    [
      "an absolute local_bin",
      { requires: [entry({ detect: { any: ["jq"], local_bin: ["/usr/bin/jq"] } })] },
      /must be relative/,
    ],
    [
      "a local_bin leaving its base",
      { requires: [entry({ detect: { any: ["jq"], local_bin: ["../jq"] } })] },
      /must be relative/,
    ],
    [
      "a version pattern with no group",
      { requires: [entry({ detect: { any: ["jq"], version: { args: [], pattern: "jq-1", min: "1.6" } } })] },
      /capture group/,
    ],
    [
      "a version pattern that does not compile",
      { requires: [entry({ detect: { any: ["jq"], version: { args: [], pattern: "(", min: "1.6" } } })] },
      /not a valid regular expression/,
    ],
    [
      "a non-numeric floor",
      { requires: [entry({ detect: { any: ["jq"], version: { args: [], pattern: "(.*)", min: "v1" } } })] },
      /dotted number/,
    ],
    ["a bad env name", { requires: [entry({ kind: "env", detect: { name: "A-B" } })] }, /environment variable name/],
    [
      "a node-pkg path outside the plugin",
      { requires: [entry({ kind: "node-pkg", detect: { module: "x", paths: ["${CLAUDE_PLUGIN_DATA}/../x"] } })] },
      /must be relative/,
    ],
    [
      "a python import with code in it",
      { requires: [entry({ kind: "python-pkg", detect: { any: ["python3"], import: "os; os.remove('x')" } })] },
      /Python module name/,
    ],
  ];
  for (const [name, manifest, expected] of cases) {
    test(`rejects ${name}`, () => {
      const errors = validateManifest(manifest);
      assert.ok(
        errors.some((e) => expected.test(e)),
        `expected ${expected} in ${JSON.stringify(errors)}`,
      );
    });
  }

  test("the JSON schema file lists the same kinds, needs and entry keys", () => {
    const schema = JSON.parse(readFileSync(schemaFile, "utf8"));
    const e = schema.$defs.entry;
    assert.deepEqual(e.properties.kind.enum, KINDS);
    assert.deepEqual(e.properties.need.enum, NEEDS);
    assert.deepEqual([...e.required].sort(), Object.keys(entry()).sort());
    assert.deepEqual(schema.required, ["requires"]);
    assert.equal(schema.additionalProperties, false);
  });

  test("the schema's node-package path pattern accepts and rejects what validateManifest does", () => {
    const schema = JSON.parse(readFileSync(schemaFile, "utf8"));
    const nodePkg = schema.$defs.entry.allOf.find((c) => c.if.properties.kind.const === "node-pkg");
    const re = new RegExp(nodePkg.then.properties.detect.properties.paths.items.pattern);
    const paths = [
      ["node_modules", true],
      ["${CLAUDE_PLUGIN_DATA}", true],
      ["${CLAUDE_PLUGIN_DATA}/node_modules", true],
      ["/tmp/node_modules", false],
      ["${CLAUDE_PLUGIN_DATA}/../outside", false],
      ["a/../b", false],
    ];
    for (const [p, ok] of paths) {
      const detect = { module: "playwright-core", paths: [p] };
      assert.equal(re.test(p), ok, p);
      assert.equal(validateManifest({ requires: [entry({ id: "playwright-core", kind: "node-pkg", detect })] }).length === 0, ok, p);
    }
  });
});

test("compareVersions compares dotted numbers numerically", () => {
  assert.equal(compareVersions("2.10.0", "2.9"), 1);
  assert.equal(compareVersions("2.94", "2.94.0"), 0);
  assert.equal(compareVersions("2026.6", "2026.06.10"), -1);
});

describe("usage", () => {
  for (const argv of [
    [],
    ["install"],
    ["check"],
    ["check", "/no/such/dir"],
    ["report"],
    ["check", work, "--for", "bogus"],
    ["probe", work, "--extra"],
  ]) {
    test(`exits 2 for ${JSON.stringify(argv)}`, () => {
      const r = runMain(argv);
      assert.equal(r.code, 2);
      assert.match(r.err, /usage:/);
    });
  }

  test("a manifest that fails the schema exits 2 in every mode", () => {
    const root = plugin([entry({ kind: "plugin" })]);
    for (const argv of [
      ["check", root],
      ["probe", root],
      ["report", "--plugin-root", root],
    ]) {
      const r = runMain(argv);
      assert.equal(r.code, 2, argv.join(" "));
      assert.match(r.err, /fails the schema/);
    }
  });

  test("a plugin with no prerequisites.json declares nothing and passes", () => {
    const r = runMain(["check", plugin(undefined)]);
    assert.equal(r.code, 0);
    assert.match(r.out, /declares no external dependency/);
  });
});

describe("check", { skip: !posix && "the stub tools are POSIX shell scripts" }, () => {
  test("passes when every required entry resolves", () => {
    const dir = bin({ jq: "exit 0" });
    const r = runMain(["check", plugin([entry()])], { env: { PATH: dir } });
    assert.equal(r.code, 0);
    assert.match(r.out, /^PASS {2}jq \(cli, required\)/m);
    assert.match(r.out, /failed=0 warned=0 passed=1/);
  });

  test("fails a missing required entry with its degrade, install hints and check", () => {
    const r = runMain(["check", plugin([entry()])]);
    assert.equal(r.code, 1);
    assert.match(
      r.out,
      /^FAIL {2}jq \(cli, required\): jq was not found on PATH\. Without jq the hooks skip their edit\. Install \(brew: jq; docs: https:\/\/jqlang\.org\/download\/\)\. Then run \/demo:check\./m,
    );
  });

  test("warns but passes when only an optional entry is missing", () => {
    const r = runMain(["check", plugin([entry({ need: "optional" })])]);
    assert.equal(r.code, 0);
    assert.match(r.out, /^WARN {2}jq \(cli, optional\)/m);
  });

  test("the first name in any that resolves wins", () => {
    const dir = bin({ python: "exit 0" });
    const r = runMain(
      ["check", plugin([entry({ id: "python", kind: "runtime", detect: { any: ["python3", "python"] } })])],
      { env: { PATH: dir } },
    );
    assert.equal(r.code, 0);
    assert.match(r.out, new RegExp(`PASS {2}python \\(runtime, required\\): ${path.join(dir, "python")}`));
  });

  test("finds a local_bin by walking up from the working directory", () => {
    const repo = path.join(work, "repo");
    mkdirSync(path.join(repo, "node_modules", ".bin"), { recursive: true });
    mkdirSync(path.join(repo, "a", "b"), { recursive: true });
    const tool = path.join(repo, "node_modules", ".bin", "biome");
    writeFileSync(tool, "#!/bin/sh\n");
    chmodSync(tool, 0o755);
    const root = plugin([entry({ id: "biome", detect: { any: ["biome"], local_bin: ["node_modules/.bin/biome"] } })]);
    const r = runMain(["check", root], { cwd: path.join(repo, "a", "b") });
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /PASS {2}biome/);
  });

  const versioned = (min) =>
    entry({
      id: "gh",
      detect: { any: ["gh"], version: { args: ["--version"], pattern: "gh version ([0-9.]+)", min } },
    });
  test("fails a required tool below its version floor", () => {
    const dir = bin({ gh: 'echo "gh version 2.45.0 (2024-03-01)"' });
    const r = runMain(["check", plugin([versioned("2.94.0")])], { env: { PATH: dir } });
    assert.equal(r.code, 1);
    assert.match(r.out, /FAIL {2}gh .*is 2\.45\.0; 2\.94\.0 or newer is needed/);
  });

  test("passes a tool at or above its version floor", () => {
    const dir = bin({ gh: 'echo "gh version 2.94.0 (2026-09-01)"' });
    const r = runMain(["check", plugin([versioned("2.94")])], { env: { PATH: dir } });
    assert.equal(r.code, 0);
    assert.match(r.out, /PASS {2}gh .* 2\.94\.0/);
  });

  test("warns, without failing, when the version cannot be read", () => {
    const dir = bin({ gh: "echo garbage" });
    const r = runMain(["check", plugin([versioned("2.94")])], { env: { PATH: dir } });
    assert.equal(r.code, 0);
    assert.match(r.out, /WARN {2}gh .*could not read a version/);
  });

  test("a system-lib passes only when its probe output matches", () => {
    const lib = entry({
      id: "libx264",
      kind: "system-lib",
      detect: { probe: { args: ["ffmpeg", "-encoders"], pattern: "libx264" } },
    });
    const yes = bin({ ffmpeg: 'echo " V..... libx264 H.264"' });
    const no = bin({ ffmpeg: 'echo " V..... mpeg4"' });
    assert.equal(runMain(["check", plugin([lib])], { env: { PATH: yes } }).code, 0);
    const r = runMain(["check", plugin([lib])], { env: { PATH: no } });
    assert.equal(r.code, 1);
    assert.match(r.out, /did not report libx264/);
  });

  test("a python-pkg passes only when the interpreter imports the module", () => {
    const pkg = (mod) => entry({ id: "mod", kind: "python-pkg", detect: { any: ["python3"], import: mod } });
    const dir = bin({ python3: '[ "$2" = "import present_mod" ]' });
    assert.equal(runMain(["check", plugin([pkg("present_mod")])], { env: { PATH: dir } }).code, 0);
    const r = runMain(["check", plugin([pkg("absent_mod")])], { env: { PATH: dir } });
    assert.equal(r.code, 1);
    assert.match(r.out, /cannot import absent_mod/);
  });

  test("a node-pkg resolves under the plugin data directory", () => {
    const data = path.join(work, "data-node-pkg");
    mkdirSync(path.join(data, "node_modules", "playwright-core"), { recursive: true });
    writeFileSync(path.join(data, "node_modules", "playwright-core", "package.json"), "{}");
    const root = plugin([
      entry({
        id: "pw",
        kind: "node-pkg",
        detect: { module: "playwright-core", paths: ["${CLAUDE_PLUGIN_DATA}/node_modules"] },
      }),
    ]);
    assert.equal(runMain(["check", root], { env: { PATH: "", CLAUDE_PLUGIN_DATA: data } }).code, 0);
    assert.equal(runMain(["check", root, "--data-dir", data]).code, 0);
    const empty = path.join(work, "data-empty");
    mkdirSync(empty);
    assert.equal(runMain(["check", root, "--data-dir", empty]).code, 1);
    const unknown = runMain(["check", root]);
    assert.equal(unknown.code, 0);
    assert.match(unknown.out, /WARN {2}pw .*data directory is unknown here; pass --data-dir/);
  });

  test("an env entry reports presence and never prints the value", () => {
    const root = plugin([entry({ id: "key", kind: "env", detect: { name: "DEMO_API_KEY" } })]);
    const set = runMain(["check", root], { env: { PATH: "", DEMO_API_KEY: "hunter2-secret" } });
    assert.equal(set.code, 0);
    assert.match(set.out, /DEMO_API_KEY is set/);
    assert.doesNotMatch(set.out + set.err, /hunter2/);
    const unset = runMain(["check", root], { env: { PATH: "", DEMO_API_KEY: "" } });
    assert.equal(unset.code, 1);
    assert.match(unset.out, /DEMO_API_KEY is not set/);
  });

  test("an mcp entry is left to the agent and never fails the run", () => {
    const root = plugin([entry({ id: "c7", kind: "mcp", detect: { server: "context7" } })]);
    const r = runMain(["check", root]);
    assert.equal(r.code, 0);
    assert.match(
      r.out,
      /^INFO {2}c7 \(mcp, required\): only the agent can see whether MCP server context7 is connected/m,
    );
  });

  test("--for keeps the plugin-wide entries and the named scope only", () => {
    const root = plugin([
      entry({ id: "jq" }),
      entry({ id: "gh", for: ["skill:work"] }),
      entry({ id: "uv", for: ["skill:other"] }),
    ]);
    const r = runMain(["check", root, "--for", "skill:work"]);
    assert.match(r.out, /jq \(cli/);
    assert.match(r.out, /gh \(cli/);
    assert.doesNotMatch(r.out, /uv \(cli/);
  });
});

describe("report", { skip: !posix && "the stub tools are POSIX shell scripts" }, () => {
  test("prints one TSV row per entry across plugins and exits 1 on a missing required entry", () => {
    const dir = bin({ jq: "exit 0" });
    const a = plugin([entry()], "alpha");
    const b = plugin(
      [entry({ id: "gh", detect: { any: ["gh"] } }), entry({ id: "uv", need: "optional", detect: { any: ["uv"] } })],
      "beta",
    );
    const none = plugin(undefined, "gamma");
    const r = runMain(["report", "--plugin-root", a, "--plugin-root", b, "--plugin-root", none], {
      env: { PATH: dir },
    });
    assert.equal(r.code, 1);
    const rows = r.out.split("\n");
    assert.deepEqual(rows[0].split("\t"), ["plugin", "id", "kind", "need", "status", "check", "install"]);
    assert.deepEqual(rows[1].split("\t").slice(0, 5), ["alpha", "jq", "cli", "required", "present"]);
    assert.deepEqual(rows[2].split("\t").slice(0, 5), ["beta", "gh", "cli", "required", "missing"]);
    assert.deepEqual(rows[3].split("\t").slice(0, 5), ["beta", "uv", "cli", "optional", "missing"]);
    assert.equal(rows.at(-1), "missing=2 present=1");
  });

  test("exits 0 when only optional entries are missing", () => {
    const r = runMain(["report", "--plugin-root", plugin([entry({ need: "optional" })])]);
    assert.equal(r.code, 0);
  });
});

describe("probe", { skip: !posix && "the stub tools are POSIX shell scripts" }, () => {
  const hookInput = (id) => () => JSON.stringify({ session_id: id, hook_event_name: "SessionStart" });

  test("notifies on both channels for a missing hook dependency and exits 0", () => {
    const root = plugin([entry({ for: ["hook:format.sh"] })], "probe-a");
    const r = runMain(["probe", root], { stdin: hookInput("s1") });
    assert.equal(r.code, 0);
    const doc = JSON.parse(r.out);
    assert.equal(doc.hookSpecificOutput.hookEventName, "SessionStart");
    assert.equal(doc.systemMessage, doc.hookSpecificOutput.additionalContext);
    assert.match(
      doc.systemMessage,
      /^probe-a: jq was not found on PATH\. Hooks that need jq skip until it is installed\. .*Then run \/demo:check\. It does not install\.$/,
    );
  });

  test("stays silent about a dependency only a skill needs", () => {
    const root = plugin([entry({ for: ["skill:audit"] }), entry({ id: "plug", for: ["plugin"] })]);
    const r = runMain(["probe", root], { stdin: hookInput("s1") });
    assert.equal(r.code, 0);
    assert.equal(r.out, "");
  });

  test("stays silent when the hook dependency resolves", () => {
    const dir = bin({ jq: "exit 0" });
    const r = runMain(["probe", plugin([entry({ for: ["hook:a.sh"] })])], {
      env: { PATH: dir },
      stdin: hookInput("s1"),
    });
    assert.equal(r.out, "");
  });

  test("notifies once per session when the plugin data directory is set", () => {
    const data = path.join(work, "data-probe");
    const root = plugin([entry({ for: ["hook:a.sh"] })], "probe-b");
    const env = { PATH: "", CLAUDE_PLUGIN_DATA: data };
    assert.notEqual(runMain(["probe", root], { env, stdin: hookInput("s1") }).out, "");
    assert.ok(existsSync(path.join(data, "skip-notices", "probe-b-jq.s1.session")));
    assert.equal(runMain(["probe", root], { env, stdin: hookInput("s1") }).out, "");
    assert.notEqual(runMain(["probe", root], { env, stdin: hookInput("s2") }).out, "");
  });

  test("notifies every time without a plugin data directory", () => {
    const root = plugin([entry({ for: ["hook:a.sh"] })]);
    assert.notEqual(runMain(["probe", root], { stdin: hookInput("s1") }).out, "");
    assert.notEqual(runMain(["probe", root], { stdin: hookInput("s1") }).out, "");
  });
});

describe("probe option gate", { skip: !posix && "the stub tools are POSIX shell scripts" }, () => {
  const input = () => JSON.stringify({ session_id: "g1" });
  const root = plugin([entry({ for: ["hook:a.sh"] })], "gated");
  const run = (value) =>
    runMain(["probe", root, "--run-if-unset-or-true", "GATED_ENABLED"], {
      env: value === undefined ? { PATH: "" } : { PATH: "", CLAUDE_PLUGIN_OPTION_GATED_ENABLED: value },
      stdin: input,
    });

  test("probes when the option is unset, empty or true", () => {
    for (const value of [undefined, "", "true"]) assert.notEqual(run(value).out, "", String(value));
  });

  test("stays silent and exits 0 when the option is set to anything else", () => {
    for (const value of ["false", "0", "no"]) {
      const r = run(value);
      assert.equal(r.code, 0, value);
      assert.equal(r.out, "", value);
    }
  });

  test("rejects a gate name that is not an option name", () => {
    for (const argv of [
      ["probe", root, "--run-if-unset-or-true"],
      ["probe", root, "--run-if-unset-or-true", "lower"],
      ["check", root, "--run-if-unset-or-true", "GATED_ENABLED"],
    ]) {
      assert.equal(runMain(argv).code, 2, argv.join(" "));
    }
  });
});

describe("report with no plugin roots", () => {
  test("prints an empty table and exits 0", () => {
    const lines = [];
    const ctx = { env: {}, platform: process.platform, cwd: work };
    const code = report([], ctx, { stdout: (s) => lines.push(s), stderr() {} });
    assert.equal(code, 0);
    assert.deepEqual(lines, ["plugin\tid\tkind\tneed\tstatus\tcheck\tinstall", "missing=0 present=0"]);
  });
});

// Every plugin's own prerequisites.json, read as the shipped checker reads it.
describe("shipped plugin manifests", { skip: !posix && "the stub tools are POSIX shell scripts" }, () => {
  const pluginsDir = path.join(here, "..", "plugins");
  const roots = readdirSync(pluginsDir)
    .map((name) => path.join(pluginsDir, name))
    .filter((root) => existsSync(path.join(root, "prerequisites.json")));
  const emptyBin = bin({});
  const input = () => JSON.stringify({ session_id: "m1" });

  test("at least one plugin declares prerequisites", () => {
    assert.ok(roots.length > 0);
  });

  for (const root of roots) {
    const name = path.basename(root);
    const { manifest, errors } = loadManifest(root);

    test(`${name}: prerequisites.json passes the schema and carries the checker copies`, () => {
      assert.deepEqual(errors, []);
      for (const file of ["prerequisites.mjs", "prerequisites.sh", "prerequisites.ps1"]) {
        assert.ok(existsSync(path.join(root, "lib", file)), `lib/${file}`);
      }
    });

    if (errors.length) continue;
    const hookEntries = manifest.requires.filter((e) => e.for.some((s) => s.startsWith("hook:")));

    test(`${name}: probe names each missing hook dependency's id, check and install hints`, () => {
      const data = path.join(work, `data-manifest-${name}`);
      const r = runMain(["probe", root], { env: { PATH: emptyBin, CLAUDE_PLUGIN_DATA: data }, stdin: input });
      assert.equal(r.code, 0);
      if (hookEntries.length === 0) {
        assert.equal(r.out, "");
        return;
      }
      assert.equal(r.out.split("\n").length, 1, "one hook document");
      const message = JSON.parse(r.out).systemMessage;
      for (const entry of hookEntries) {
        assert.ok(message.includes(`Hooks that need ${entry.id} skip`), `${entry.id} is reported`);
        assert.ok(message.includes(entry.check), `${entry.id}: ${entry.check}`);
        for (const hint of Object.values(entry.install)) assert.ok(message.includes(hint), `${entry.id}: ${hint}`);
      }
    });

    test(`${name}: probe is silent when every declared binary is on PATH`, () => {
      const names = manifest.requires.flatMap((e) => e.detect.any ?? []);
      const stubs = bin(Object.fromEntries(names.map((n) => [n, "exit 0"])));
      const r = runMain(["probe", root], {
        env: { PATH: stubs, CLAUDE_PLUGIN_DATA: path.join(work, `data-silent-${name}`) },
        stdin: input,
      });
      assert.equal(r.out, "");
    });
  }
});

describe("command line", () => {
  test("the process exit code follows main()", () => {
    const root = plugin([entry({ id: "definitely-absent-tool", detect: { any: ["definitely-absent-tool-x9"] } })]);
    const r = spawnSync(process.execPath, [checker, "check", root], { encoding: "utf8" });
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stdout, /FAIL {2}definitely-absent-tool/);
    assert.equal(spawnSync(process.execPath, [checker], { encoding: "utf8" }).status, 2);
  });

  test("the checker source holds no install command", () => {
    const source = readFileSync(checker, "utf8");
    assert.doesNotMatch(
      source,
      /\b(npm|pnpm|yarn|pip|pipx|uv|brew|winget|scoop|choco|apt|apt-get|dnf)\s+(i|install|add)\b/,
    );
  });
});
