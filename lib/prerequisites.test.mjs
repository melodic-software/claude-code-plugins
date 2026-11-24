import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import process from "node:process";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  compareVersions,
  detectEntry,
  KINDS,
  loadManifest,
  main,
  NEEDS,
  report,
  validateManifest,
  which,
} from "./prerequisites.mjs";
import { tempDir } from "./test-tmp.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const checker = path.join(here, "prerequisites.mjs");
const schemaFile = ["contracts", "conventions"]
  .map((home) => path.join(here, "..", "docs", home, "prerequisites", "prerequisites.schema.json"))
  .find((p) => existsSync(p));
const posix = process.platform !== "win32";
const work = tempDir("prereq-test-");
after(() => rmSync(work, { recursive: true, force: true }));

let counter = 0;
function plugin(requires, name = `p${++counter}`) {
  const root = path.join(work, name);
  mkdirSync(path.join(root, ".claude-plugin"), { recursive: true });
  writeFileSync(path.join(root, ".claude-plugin", "plugin.json"), JSON.stringify({ name }));
  if (requires !== undefined) writeFileSync(path.join(root, "prerequisites.json"), JSON.stringify({ requires }));
  return root;
}

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

  test("accepts a session_probe with or without a gate option", () => {
    assert.deepEqual(validateManifest({ session_probe: {}, requires: [entry()] }), []);
    assert.deepEqual(validateManifest({ session_probe: { run_if_unset_or_true: "DEMO_ENABLED" }, requires: [entry()] }), []);
  });

  const cases = [
    ["a session_probe that is not an object", { session_probe: true, requires: [entry()] }, /session_probe must be an object/],
    [
      "a session_probe gate in lower case",
      { session_probe: { run_if_unset_or_true: "demo_enabled" }, requires: [entry()] },
      /run_if_unset_or_true must be an option name in capitals/,
    ],
    ["an unknown session_probe key", { session_probe: { gate: "X" }, requires: [entry()] }, /session_probe: unknown key "gate"/],
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
      "a reject_store_alias that is not a boolean",
      { requires: [entry({ detect: { any: ["jq"], reject_store_alias: "yes" } })] },
      /reject_store_alias must be true or false/,
    ],
    [
      "a reject_store_alias on a kind that does not search PATH",
      { requires: [entry({ kind: "env", detect: { name: "X", reject_store_alias: true } })] },
      /unknown key "reject_store_alias"/,
    ],
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
    [
      "a non-numeric below",
      { requires: [entry({ detect: { any: ["jq"], version: { args: [], pattern: "(.*)", min: "1.6", below: "v2" } } })] },
      /below must be a dotted number/,
    ],
    [
      "a below equal to min",
      { requires: [entry({ detect: { any: ["jq"], version: { args: [], pattern: "(.*)", min: "1.6", below: "1.6.0" } } })] },
      /below must be greater than/,
    ],
    [
      "a latest source that is not npm or github",
      { requires: [entry({ detect: { any: ["jq"], version: { args: [], pattern: "(.*)", min: "1.6", latest: "https://example.test" } } })] },
      /latest must be npm:<package> or github:<owner>\/<repo>/,
    ],
    [
      "a below under min",
      { requires: [entry({ detect: { any: ["jq"], version: { args: [], pattern: "(.*)", min: "2.0", below: "1.9" } } })] },
      /below must be greater than/,
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
    assert.deepEqual([...e.required, "check"].sort(), Object.keys(entry()).sort());
    assert.deepEqual(Object.keys(e.properties).sort(), [...Object.keys(entry()), "when"].sort());
    assert.deepEqual(e.properties.when.required, ["config_any"]);
    assert.deepEqual(schema.required, ["requires"]);
    assert.equal(schema.additionalProperties, false);
    assert.deepEqual(Object.keys(schema.properties).sort(), ["$schema", "requires", "session_probe"]);
    assert.deepEqual(Object.keys(schema.properties.session_probe.properties), ["run_if_unset_or_true"]);
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

  test("an entry without check is valid and asks for this check again", () => {
    const { check, ...noCheck } = entry();
    const r = runMain(["check", plugin([noCheck])]);
    assert.equal(r.code, 1);
    assert.match(r.out, /^FAIL {2}jq \(cli, required\): .*\)\. Then run this check again\.$/m);
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

  const ranged = () =>
    entry({
      id: "gh",
      detect: {
        any: ["gh"],
        version: { args: ["--version"], pattern: "gh version ([0-9.]+)", min: "2.94.0", below: "3.0.0" },
      },
    });
  const atVersion = (v) => runMain(["check", plugin([ranged()])], { env: { PATH: bin({ gh: `echo "gh version ${v}"` }) } });
  test("fails a version below the range when below is set", () => {
    const r = atVersion("2.45.0");
    assert.equal(r.code, 1);
    assert.match(r.out, /is 2\.45\.0; 2\.94\.0 or newer is needed/);
  });
  test("passes a version inside the range when below is set", () => {
    const r = atVersion("2.99.1");
    assert.equal(r.code, 0);
    assert.match(r.out, /PASS {2}gh .* 2\.99\.1/);
  });
  test("fails a version exactly at below", () => {
    const r = atVersion("3.0.0");
    assert.equal(r.code, 1);
    assert.match(r.out, /FAIL {2}gh .*is 3\.0\.0; the supported range is >= 2\.94\.0, < 3\.0\.0/);
  });
  test("fails a version above below", () => {
    const r = atVersion("3.4.0");
    assert.equal(r.code, 1);
    assert.match(r.out, /the supported range is >= 2\.94\.0, < 3\.0\.0/);
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

  test("a python-pkg resolves from the plugin's installed set under the plugin data directory", () => {
    const pkg = entry({ id: "datapkg", kind: "python-pkg", detect: { any: ["python3"], import: "datapkg" } });
    // Imports datapkg only through PYTHONPATH with -S, the way a plugin's launcher runs its set.
    const dir = bin({
      python3: [
        'case "$*" in',
        '  "-c import sys; print(sys.implementation.cache_tag)") echo cpython-312 ;;',
        '  "-S -c import datapkg") [ -f "$PYTHONPATH/datapkg.py" ] ;;',
        "  *) exit 1 ;;",
        "esac",
      ].join("\n"),
    });
    const lock = "datapkg==1.0 --hash=sha256:00\n";
    const root = plugin([pkg], "pypkg");
    writeFileSync(path.join(root, "requirements.txt"), lock);
    const key = "66d3c666c384"; // first 12 hex of sha256sum of the lock above
    const data = path.join(work, "data", "pypkg-marketplace");
    const set = path.join(data, "python", `${key}-cpython-312`);
    mkdirSync(set, { recursive: true });
    writeFileSync(path.join(set, "datapkg.py"), "");

    const viaFlag = runMain(["check", root, "--data-dir", data], { env: { PATH: dir } });
    assert.equal(viaFlag.code, 0);
    assert.ok(viaFlag.out.includes(`imports datapkg from ${set}`), viaFlag.out);
    assert.equal(runMain(["check", root], { env: { PATH: dir, CLAUDE_PLUGIN_DATA: data } }).code, 0);

    const stale = path.join(work, "data-python-stale");
    mkdirSync(path.join(stale, "python", "000000000000-cpython-312"), { recursive: true });
    writeFileSync(path.join(stale, "python", "000000000000-cpython-312", "datapkg.py"), "");
    const missing = runMain(["check", root, "--data-dir", stale], { env: { PATH: dir } });
    assert.equal(missing.code, 1);
    assert.match(missing.out, /cannot import datapkg on its own or from /);

    const unknown = runMain(["check", root], { env: { PATH: dir } });
    assert.equal(unknown.code, 0);
    assert.match(unknown.out, /WARN {2}datapkg .*data directory is unknown here; pass --data-dir/);

    const noLock = runMain(["check", plugin([pkg]), "--data-dir", data], { env: { PATH: dir } });
    assert.equal(noLock.code, 1);
    assert.match(noLock.out, /cannot import datapkg\. /);
  });

  test("a python-pkg finds the set installed for any listed interpreter, not only the first", () => {
    const pkg = entry({ id: "datapkg", kind: "python-pkg", detect: { any: ["python3", "python3.13"], import: "datapkg" } });
    const stub = (tag) =>
      [
        'case "$*" in',
        `  "-c import sys; print(sys.implementation.cache_tag)") echo ${tag} ;;`,
        '  "-S -c import datapkg") [ -f "$PYTHONPATH/datapkg.py" ] ;;',
        "  *) exit 1 ;;",
        "esac",
      ].join("\n");
    // python3.13 reads its tag from the injected environment and also writes a startup
    // warning to stderr; only its stdout is the tag.
    const dir = bin({
      python3: stub("cpython-314"),
      "python3.13": stub("\"$STUB_TAG\"; echo 'Invalid -W option ignored' >&2"),
    });
    const lock = "datapkg==1.0 --hash=sha256:00\n";
    const root = plugin([pkg]);
    writeFileSync(path.join(root, "requirements.txt"), lock);
    const data = path.join(work, "data-python-multi");
    const set = path.join(data, "python", "66d3c666c384-cpython-313");
    mkdirSync(set, { recursive: true });
    writeFileSync(path.join(set, "datapkg.py"), "");

    const r = runMain(["check", root, "--data-dir", data], { env: { PATH: dir, STUB_TAG: "cpython-313" } });
    assert.equal(r.code, 0, r.out);
    assert.ok(r.out.includes(`python3.13 imports datapkg from ${set}`), r.out);
  });

  test("a node-pkg resolves under the plugin data directory", () => {
    const data = path.join(work, "data", "nodepkg-marketplace");
    mkdirSync(path.join(data, "node_modules", "playwright-core"), { recursive: true });
    writeFileSync(path.join(data, "node_modules", "playwright-core", "package.json"), "{}");
    const root = plugin(
      [
        entry({
          id: "pw",
          kind: "node-pkg",
          detect: { module: "playwright-core", paths: ["${CLAUDE_PLUGIN_DATA}/node_modules"] },
        }),
      ],
      "nodepkg",
    );
    assert.equal(runMain(["check", root], { env: { PATH: "", CLAUDE_PLUGIN_DATA: data } }).code, 0);
    const other = path.join(work, "data", "otherplugin-marketplace");
    mkdirSync(other, { recursive: true });
    for (const value of [other, "${CLAUDE_PLUGIN_DATA}"]) {
      const r = runMain(["check", root], { env: { PATH: "", CLAUDE_PLUGIN_DATA: value } });
      assert.equal(r.code, 0, r.out);
      assert.match(r.out, /WARN {2}pw .*data directory is unknown here; pass --data-dir/);
      assert.doesNotMatch(r.out, /FAIL/);
    }
    const fleet = runMain(["report", "--plugin-root", root], { env: { PATH: "", CLAUDE_PLUGIN_DATA: other } });
    assert.match(fleet.out, /nodepkg\tpw\tnode-pkg\trequired\tunverified\t/);
    assert.equal(runMain(["check", root, "--data-dir", "${CLAUDE_PLUGIN_DATA}"], { env: { PATH: "" } }).code, 0);
    const bare = path.join(work, "data", "nodepkg");
    mkdirSync(path.join(bare, "node_modules", "playwright-core"), { recursive: true });
    writeFileSync(path.join(bare, "node_modules", "playwright-core", "package.json"), "{}");
    assert.match(runMain(["check", root], { env: { PATH: "", CLAUDE_PLUGIN_DATA: bare } }).out, /PASS {2}pw/);
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

  // The user line hook::prereq_notice_to renders for the same entry, written
  // out by hand: the model hears of a missing tool at the hook's first skip,
  // where it is relevant, so the probe tells only the user.
  test("notifies the user only for a missing hook dependency and exits 0", () => {
    const root = plugin([entry({ for: ["hook:format.sh"] })], "probe-a");
    const r = runMain(["probe", root], { stdin: hookInput("s1") });
    assert.equal(r.code, 0);
    assert.deepEqual(JSON.parse(r.out), {
      systemMessage: `probe-a: jq not on the hook PATH. Without jq the hooks skip their edit. Install (brew: jq; docs: https://jqlang.org/download/). Hooks read Claude Code's PATH, not your shell profile. No further notice this session; diagnose with: node "${root}/lib/prerequisites.mjs" check "${root}"`,
    });
  });

  test("names each detect.local_bin path where the hook also looks", () => {
    const biome = entry({
      id: "biome",
      for: ["hook:format.sh"],
      detect: { any: ["biome"], local_bin: ["node_modules/.bin/biome"] },
    });
    const r = runMain(["probe", plugin([biome], "probe-l")], { stdin: hookInput("s1") });
    assert.match(
      JSON.parse(r.out).systemMessage,
      /^probe-l: biome not on the hook PATH or at node_modules\/\.bin\/biome\. /,
    );
  });

  test("renders the user line hook::prereq_notice_to renders", () => {
    const biome = entry({
      id: "biome",
      for: ["hook:format.sh"],
      detect: { any: ["biome"], local_bin: ["node_modules/.bin/biome", ".venv/bin/biome"] },
      degrade: 'Without biome, "edits" go through unformatted.',
      install: { npm: "npm i -D @biomejs/biome", docs: "https://biomejs.dev/" },
    });
    const root = plugin([biome], "probe-parity");
    const probe = JSON.parse(runMain(["probe", root], { stdin: hookInput("s1") }).out).systemMessage;
    const bash = spawnSync(
      "bash",
      [
        "-c",
        'source "$1"; hook::prereq_notice_to m u biome \'{"session_id":"s1"}\' 2>/dev/null; printf %s "$u"',
        "bash",
        path.join(here, "hook-utils.sh"),
      ],
      { env: { ...process.env, CLAUDE_PLUGIN_ROOT: root, CLAUDE_PLUGIN_DATA: "" }, encoding: "utf8" },
    );
    assert.equal(bash.stdout, probe);
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
    // The user marker hook::notice_once reads, so the hook's first skip does
    // not repeat this notice to the user.
    assert.ok(existsSync(path.join(data, "skip-notices", "probe-b-jq.s1.user")));
    assert.equal(runMain(["probe", root], { env, stdin: hookInput("s1") }).out, "");
    assert.notEqual(runMain(["probe", root], { env, stdin: hookInput("s2") }).out, "");
  });

  test("notifies every time without a plugin data directory", () => {
    const root = plugin([entry({ for: ["hook:a.sh"] })]);
    assert.notEqual(runMain(["probe", root], { stdin: hookInput("s1") }).out, "");
    assert.notEqual(runMain(["probe", root], { stdin: hookInput("s1") }).out, "");
  });
});

describe("when: an adapter tool is needed only where its config is", { skip: !posix && "the stub tools are POSIX shell scripts" }, () => {
  const hookInput = () => JSON.stringify({ session_id: "w1", hook_event_name: "SessionStart" });
  const ruff = entry({
    id: "ruff",
    for: ["hook:format.sh"],
    detect: { any: ["ruff"] },
    when: { config_any: ["ruff.toml", { file: "pyproject.toml", pattern: "^\\s*\\[tool\\.ruff" }] },
  });
  function tree(files) {
    const top = path.join(work, `when${++counter}`);
    const deep = path.join(top, "pkg", "sub");
    mkdirSync(deep, { recursive: true });
    for (const [rel, text] of Object.entries(files)) writeFileSync(path.join(top, rel), text);
    return { top, deep };
  }

  test("validateManifest accepts when.config_any of file names and file-pattern pairs", () => {
    assert.deepEqual(validateManifest({ requires: [ruff] }), []);
  });

  test("validateManifest accepts repository-relative paths and globs", () => {
    const configs = [
      ".github/actionlint.yaml",
      ".github/workflows/*.yml",
      "**/.github/workflows/*.yaml",
      "mod/PSScriptAnalyzerSettings.psd1",
      "src/**/conf?.json",
      { file: "**/pyproject.toml", pattern: "^\\[tool\\.ruff" },
    ];
    assert.deepEqual(validateManifest({ requires: [entry({ when: { config_any: configs } })] }), []);
  });

  test("validateManifest rejects a malformed when", () => {
    for (const when of [
      "ruff.toml",
      {},
      { config_any: [] },
      { config_any: ["../ruff.toml"] },
      { config_any: [".."] },
      { config_any: ["."] },
      { config_any: ["a/../b"] },
      { config_any: ["a/./b"] },
      { config_any: ["/etc/ruff.toml"] },
      { config_any: ["C:/ruff.toml"] },
      { config_any: ["a\\b"] },
      { config_any: ["a//b"] },
      { config_any: ["a/"] },
      { config_any: [":(exclude)x"] },
      { config_any: ["*.toml"] },
      { config_any: ["ruff toml"] },
      { config_any: [{ file: "pyproject.toml" }] },
      { config_any: [{ file: "pyproject.toml", pattern: "(" }] },
      { config_any: [{ file: "../pyproject.toml", pattern: "x" }] },
      { config_any: ["ruff.toml"], other: true },
    ]) {
      assert.ok(validateManifest({ requires: [entry({ when })] }).some((e) => e.includes("when")), JSON.stringify(when));
    }
  });

  test("the schema's config pattern accepts and rejects what validateManifest does", () => {
    const schema = JSON.parse(readFileSync(schemaFile, "utf8"));
    const items = schema.$defs.entry.properties.when.properties.config_any.items.oneOf;
    const nameRe = new RegExp(items[0].pattern);
    const fileRe = new RegExp(items[1].properties.file.pattern);
    for (const [config, ok] of [
      ["ruff.toml", true],
      [".ruff.toml", true],
      [".github/workflows/*.yml", true],
      ["**/PSScriptAnalyzerSettings.psd1", true],
      ["..", false],
      ["a/../b", false],
      ["/abs", false],
      ["*.toml", false],
      ["a//b", false],
      ["a/", false],
    ]) {
      assert.equal(nameRe.test(config), ok, config);
      assert.equal(fileRe.test(config), ok, config);
      assert.equal(validateManifest({ requires: [entry({ when: { config_any: [config] } })] }).length === 0, ok, config);
    }
  });

  test("probe: no config at or above the project directory, so no line for the tool", () => {
    const { deep } = tree({});
    const r = runMain(["probe", plugin([ruff])], { cwd: deep, stdin: hookInput });
    assert.equal(r.out, "");
  });

  test("probe: a config file above the project directory makes the missing tool a notice", () => {
    const { deep } = tree({ "ruff.toml": "line-length = 88\n" });
    const r = runMain(["probe", plugin([ruff], "when-hit")], { cwd: deep, stdin: hookInput });
    assert.match(JSON.parse(r.out).systemMessage, /^when-hit: ruff not on the hook PATH\. /);
  });

  test("probe: a file counts only when its pattern matches", () => {
    const plain = tree({ "pyproject.toml": "[project]\nname = 't'\n" });
    assert.equal(runMain(["probe", plugin([ruff])], { cwd: plain.deep, stdin: hookInput }).out, "");
    const tooled = tree({ "pyproject.toml": "[project]\n\n[tool.ruff]\nline-length = 88\n" });
    assert.notEqual(runMain(["probe", plugin([ruff])], { cwd: tooled.deep, stdin: hookInput }).out, "");
  });

  test("probe: CLAUDE_PROJECT_DIR is where the walk starts", () => {
    const { top } = tree({ "ruff.toml": "x\n" });
    const r = runMain(["probe", plugin([ruff])], { cwd: work, env: { PATH: "", CLAUDE_PROJECT_DIR: top }, stdin: hookInput });
    assert.notEqual(r.out, "");
  });

  test("check: an entry whose config is absent is INFO, never FAIL", () => {
    const { deep } = tree({});
    const r = runMain(["check", plugin([ruff])], { cwd: deep });
    assert.equal(r.code, 0);
    assert.match(r.out, /^INFO {2}ruff \(cli, required\): not needed here: no ruff\.toml or pyproject\.toml matching /m);
    assert.match(r.out, /at or above .*, and none tracked in its git repository$/m);
  });
});

const realGit = which("git");
describe("when: a config git tracks anywhere in the repository", { skip: (!posix || !realGit) && "needs POSIX stub tools and git" }, () => {
  const hookInput = () => JSON.stringify({ session_id: "t1", hook_event_name: "SessionStart" });
  const tool = (configs) =>
    entry({ id: "ruff", for: ["hook:format.sh"], detect: { any: ["ruff"] }, when: { config_any: configs } });
  const gitEnv = { HOME: work, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: path.join(work, "no-gitconfig") };
  writeFileSync(gitEnv.GIT_CONFIG_GLOBAL, "");
  const gitOnlyBin = bin({ git: `exec "${realGit}" "$@"` });

  function repoWithTracked(tracked, untracked = {}) {
    const top = path.join(work, `repo${++counter}`);
    mkdirSync(top, { recursive: true });
    const git = (...args) => assert.equal(spawnSync(realGit, ["-C", top, ...args], { env: { ...process.env, ...gitEnv } }).status, 0, args.join(" "));
    git("init", "-q");
    for (const [rel, text] of Object.entries({ "README.md": "x\n", ...tracked, ...untracked })) {
      mkdirSync(path.dirname(path.join(top, rel)), { recursive: true });
      writeFileSync(path.join(top, rel), text);
    }
    git("add", "--", "README.md", ...Object.keys(tracked));
    return top;
  }
  const probe = (configs, top, PATH = gitOnlyBin, name = undefined) =>
    runMain(["probe", plugin([tool(configs)], name)], { cwd: work, env: { ...gitEnv, PATH, CLAUDE_PROJECT_DIR: top }, stdin: hookInput });

  test("a config tracked only in a subdirectory meets when", () => {
    const top = repoWithTracked({ "mod/sub/ruff.toml": "x\n" });
    const r = probe(["ruff.toml"], top, gitOnlyBin, "nested-hit");
    assert.match(JSON.parse(r.out).systemMessage, /^nested-hit: ruff not on the hook PATH\. /);
  });

  test("a subdirectory config counts from a project directory below the repository root", () => {
    const top = repoWithTracked({ "a/ruff.toml": "x\n", "b/c/keep.txt": "x\n" });
    assert.notEqual(probe(["ruff.toml"], path.join(top, "b", "c")).out, "");
  });

  test("a path glob meets when", () => {
    const top = repoWithTracked({ ".github/workflows/ci.yml": "on: push\n" });
    assert.notEqual(probe([".github/workflows/*.yml"], top).out, "");
    assert.equal(probe([".github/workflows/*.yaml"], top).out, "");
  });

  test("a leading ** segment matches at the root and below it", () => {
    const glob = ["**/.github/workflows/*.yml"];
    assert.notEqual(probe(glob, repoWithTracked({ ".github/workflows/ci.yml": "x\n" })).out, "");
    assert.notEqual(probe(glob, repoWithTracked({ "svc/.github/workflows/ci.yml": "x\n" })).out, "");
    assert.equal(probe(glob, repoWithTracked({ "svc/.github/ci.yml": "x\n" })).out, "");
  });

  test("a path is anchored at the repository root", () => {
    const top = repoWithTracked({ "svc/.github/workflows/ci.yml": "x\n" });
    assert.equal(probe([".github/workflows/*.yml"], top).out, "");
  });

  test("a wildcard-free path is anchored at the repository root and must be tracked", () => {
    const top = repoWithTracked({ "svc/keep.txt": "x\n" }, { "svc/.github/actionlint.yaml": "x\n" });
    assert.equal(probe([".github/actionlint.yaml"], path.join(top, "svc")).out, "");
    const hit = repoWithTracked({ ".github/actionlint.yaml": "x\n", "svc/keep.txt": "x\n" });
    assert.notEqual(probe([".github/actionlint.yaml"], path.join(hit, "svc")).out, "");
  });

  test("a pattern is tested against a nested tracked file's text", () => {
    const item = { file: "pyproject.toml", pattern: "^\\[tool\\.ruff" };
    assert.notEqual(probe([item], repoWithTracked({ "pkg/pyproject.toml": "[tool.ruff]\n" })).out, "");
    assert.equal(probe([item], repoWithTracked({ "pkg/pyproject.toml": "[project]\n" })).out, "");
  });

  test("no matching config leaves the probe quiet", () => {
    const top = repoWithTracked({ "src/main.py": "x\n" }, { "scratch/ruff.toml": "x\n" });
    assert.equal(probe(["ruff.toml", ".github/workflows/*.yml"], top).out, "");
  });

  test("a git failure fails toward reporting", () => {
    const top = repoWithTracked({ "src/main.py": "x\n" });
    assert.notEqual(probe(["ruff.toml"], top, bin({ git: "exit 1" })).out, "");
    assert.notEqual(probe(["ruff.toml"], top, bin({ git: `exec "${which("sleep")}" 30` })).out, "");
    assert.notEqual(probe(["ruff.toml"], top, bin({})).out, "");
  });

  test("outside a repository nothing runs git and the probe stays quiet", () => {
    const top = path.join(work, `plain${++counter}`);
    mkdirSync(path.join(top, "mod"), { recursive: true });
    writeFileSync(path.join(top, "mod", "ruff.toml"), "x\n");
    assert.equal(probe(["ruff.toml"], top, bin({ git: "exit 1" })).out, "");
  });

  test("a config at or above the project directory needs no git call", () => {
    const top = repoWithTracked({ "ruff.toml": "x\n" });
    assert.notEqual(probe(["ruff.toml"], top, bin({ git: "exit 1" })).out, "");
  });

  test("one git call serves every entry of a probe", () => {
    const top = repoWithTracked({ "src/main.py": "x\n" });
    const calls = path.join(work, `git-calls${++counter}`);
    const counting = bin({ git: `echo x >>"${calls}"\nexec "${realGit}" "$@"` });
    const second = entry({ id: "biome", for: ["hook:format.sh"], detect: { any: ["biome"] }, when: { config_any: ["biome.json"] } });
    const r = runMain(["probe", plugin([tool(["ruff.toml"]), second])], {
      cwd: work,
      env: { ...gitEnv, PATH: counting, CLAUDE_PROJECT_DIR: top },
      stdin: hookInput,
    });
    assert.equal(r.out, "");
    assert.equal(readFileSync(calls, "utf8"), "x\n");
  });

  test("check: a nested tracked config makes the entry FAIL, not INFO", () => {
    const top = repoWithTracked({ "mod/ruff.toml": "x\n" });
    const r = runMain(["check", plugin([tool(["ruff.toml"])])], { cwd: work, env: { ...gitEnv, PATH: gitOnlyBin, CLAUDE_PROJECT_DIR: top } });
    assert.equal(r.code, 1);
    assert.match(r.out, /^FAIL {2}ruff \(cli, required\): /m);
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

// A Windows App Execution Alias cannot be created in a test, so these feed the
// checker an injected fs. files maps a path to "file" (a plain executable) or to
// { target } (an alias reparse point: stat fails with EACCES, lstat reports a
// link, readlink returns target, or fails when target is null).
function fakeFs(files) {
  const fail = (code) => Object.assign(new Error(code), { code });
  return {
    statSync(p) {
      if (!(p in files)) throw fail("ENOENT");
      if (files[p] !== "file") throw fail("EACCES");
      return { isFile: () => true };
    },
    lstatSync(p) {
      if (!(p in files)) throw fail("ENOENT");
      return { isSymbolicLink: () => files[p] !== "file" };
    },
    readlinkSync(p) {
      if (!files[p]?.target) throw fail("EINVAL");
      return files[p].target;
    },
    accessSync() {},
  };
}

describe("Windows App Execution Aliases", () => {
  const apps = path.join(work, "Local", "Microsoft", "WindowsApps");
  const programs = path.join(work, "Programs", "Python");
  const pkg = "C:\\Program Files\\WindowsApps";
  const pwshAlias = { target: `${pkg}\\Microsoft.PowerShell_7.6.6.0_x64__8wekyb3d8bbwe\\pwsh.exe` };
  const wingetAlias = { target: `${pkg}\\Microsoft.DesktopAppInstaller_1.29.380.0_x64__8wekyb3d8bbwe\\winget.exe` };
  const pythonStub = {
    target: `${pkg}\\Microsoft.DesktopAppInstaller_1.17.106910_x64__8wekyb3d8bbwe\\AppInstallerPythonRedirector.exe`,
  };
  const winCtx = (files, PATH = apps) => ({ platform: "win32", env: { PATH, PATHEXT: ".EXE" }, fs: fakeFs(files) });
  const python = entry({ id: "python", kind: "runtime", detect: { any: ["python3", "python"] } });

  test("a Store pwsh alias is found, and the probe stays quiet about it", () => {
    const files = { [path.join(apps, "pwsh.EXE")]: pwshAlias };
    const pwsh = entry({ id: "pwsh", for: ["hook:powershell-format.sh"], detect: { any: ["pwsh"] } });
    const r = runMain(["probe", plugin([pwsh])], {
      ...winCtx(files),
      stdin: () => JSON.stringify({ session_id: "s1", hook_event_name: "SessionStart" }),
    });
    assert.equal(r.code, 0);
    assert.equal(r.out, "");
    assert.equal(which("pwsh", winCtx(files).env, "win32", fakeFs(files)), path.join(apps, "pwsh.EXE"));
  });

  test("a runnable lookup skips an extensionless shim for its PATHEXT sibling", () => {
    const files = { [path.join(apps, "firecrawl")]: "file", [path.join(apps, "firecrawl.CMD")]: "file" };
    const env = { PATH: apps, PATHEXT: ".EXE;.CMD" };
    assert.equal(which("firecrawl", env, "win32", fakeFs(files)), path.join(apps, "firecrawl"));
    assert.equal(which("firecrawl", env, "win32", fakeFs(files), false, true), path.join(apps, "firecrawl.CMD"));
  });

  test("an alias to something other than the Python stub is found, winget included", () => {
    const files = { [path.join(apps, "winget.EXE")]: wingetAlias };
    const r = runMain(["check", plugin([entry({ id: "winget", detect: { any: ["winget"] } })])], winCtx(files));
    assert.equal(r.code, 0);
    assert.match(r.out, /^PASS {2}winget \(cli, required\)/m);
  });

  test("the Python install stub stays missing", () => {
    const files = { [path.join(apps, "python3.EXE")]: pythonStub, [path.join(apps, "python.EXE")]: pythonStub };
    const r = runMain(["check", plugin([python])], winCtx(files));
    assert.equal(r.code, 1);
    assert.match(r.out, /^FAIL {2}python \(runtime, required\): python3 or python was not found on PATH/m);
  });

  test("a stub python3 ahead of a real python resolves to the real python", () => {
    const real = path.join(programs, "python.EXE");
    const files = { [path.join(apps, "python3.EXE")]: pythonStub, [real]: "file" };
    const r = runMain(["check", plugin([python])], winCtx(files, [apps, programs].join(path.delimiter)));
    assert.equal(r.code, 0);
    assert.ok(r.out.includes(`PASS  python (runtime, required): ${real}`), r.out);
  });

  test("an unreadable alias target falls back to rejecting the python and python3 names only", () => {
    const files = { [path.join(apps, "python3.EXE")]: { target: null }, [path.join(apps, "pwsh.EXE")]: { target: null } };
    const ctx = winCtx(files);
    assert.equal(which("python3", ctx.env, "win32", ctx.fs), null);
    assert.equal(which("pwsh", ctx.env, "win32", ctx.fs), path.join(apps, "pwsh.EXE"));
  });

  test("a link outside a WindowsApps directory is not an alias", () => {
    const elsewhere = path.join(work, "bin-links");
    const files = { [path.join(elsewhere, "pwsh.EXE")]: pwshAlias };
    const ctx = winCtx(files, elsewhere);
    assert.equal(which("pwsh", ctx.env, "win32", ctx.fs), null);
  });

  test("only win32 reads an alias", () => {
    const files = { [path.join(apps, "pwsh")]: pwshAlias };
    assert.equal(which("pwsh", { PATH: apps }, "linux", fakeFs(files)), null);
  });

  const storePython = {
    target: `${pkg}\\PythonSoftwareFoundation.Python.3.13_3.13.2032.0_x64__qbz5n2kfra8p0\\python.exe`,
  };
  const strictPython = entry({
    id: "python",
    kind: "runtime",
    detect: { any: ["python3", "python"], reject_store_alias: true },
  });

  test("without reject_store_alias, a Store Python alias is found", () => {
    const alias = path.join(apps, "python.EXE");
    const r = runMain(["check", plugin([python])], winCtx({ [alias]: storePython }));
    assert.equal(r.code, 0);
    assert.ok(r.out.includes(`PASS  python (runtime, required): ${alias}`), r.out);
  });

  test("with reject_store_alias, a Store Python alias is skipped for a later real python", () => {
    const real = path.join(programs, "python.EXE");
    const files = { [path.join(apps, "python3.EXE")]: storePython, [path.join(apps, "python.EXE")]: storePython, [real]: "file" };
    const r = runMain(["check", plugin([strictPython])], winCtx(files, [apps, programs].join(path.delimiter)));
    assert.equal(r.code, 0);
    assert.ok(r.out.includes(`PASS  python (runtime, required): ${real}`), r.out);
  });

  test("with reject_store_alias and only a Store Python alias, python is missing", () => {
    const files = { [path.join(apps, "python3.EXE")]: storePython, [path.join(apps, "python.EXE")]: storePython };
    const r = runMain(["check", plugin([strictPython])], winCtx(files));
    assert.equal(r.code, 1);
    assert.match(r.out, /^FAIL {2}python \(runtime, required\): python3 or python was not found on PATH/m);
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

    test(`${name}: probe names each missing hook dependency's id, install hints and the checker`, () => {
      const data = path.join(work, `data-manifest-${name}`);
      const r = runMain(["probe", root], { env: { PATH: emptyBin, CLAUDE_PLUGIN_DATA: data }, stdin: input });
      assert.equal(r.code, 0);
      const reported = hookEntries.filter((e) => !e.when);
      if (reported.length === 0) {
        assert.equal(r.out, "");
        return;
      }
      assert.equal(r.out.split("\n").length, 1, "one hook document");
      const doc = JSON.parse(r.out);
      assert.equal(doc.hookSpecificOutput, undefined, "user channel only");
      const message = doc.systemMessage;
      for (const entry of hookEntries.filter((e) => e.when)) {
        assert.ok(!message.includes(`${name}: ${entry.id} not on the hook PATH`), `${entry.id} is silent without its config`);
      }
      for (const entry of reported) {
        assert.ok(message.includes(`${name}: ${entry.id} not on the hook PATH`), `${entry.id} is reported`);
        assert.ok(message.includes(`node "${root}/lib/prerequisites.mjs" check "${root}"`), `${entry.id}: checker`);
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

  // explainer-video's launcher runs only the Pythons its scripts/pydeps.json lists (3.12 and 3.13).
  test("explainer-video: the python entry passes 3.13 and reports 3.14 outdated", () => {
    const { manifest } = loadManifest(path.join(pluginsDir, "explainer-video"));
    const python = manifest.requires.find((e) => e.id === "python");
    const at = (v) =>
      detectEntry(python, { env: { PATH: bin({ python3: `echo "Python ${v}"` }) }, platform: process.platform, cwd: work });
    assert.equal(at("3.13.5").status, "present");
    assert.equal(at("3.14.0").status, "outdated");
  });

  // The owner set the floor for the shfmt the Bash guards read commands through at v3.14.1:
  // under 3.13.1 they let here-doc-hidden git commands through. 3.9.0 sorts above 3.14.1 as a string.
  test("guardrails: /guardrails:setup check fails a shfmt below v3.14.1 and passes one at or above it", () => {
    const root = path.join(pluginsDir, "guardrails");
    const check = (v) => {
      const PATH = bin({ shfmt: `echo v${v}`, jq: "echo jq-1.7.1", node: "exit 0" });
      return runMain(["check", root, "--for", "hook:run-guards.sh"], { env: { PATH } });
    };
    for (const v of ["3.13.1", "3.9.0"]) {
      const r = check(v);
      assert.equal(r.code, 1, `${v} must fail the check:\n${r.out}`);
      const fail = r.out.split("\n").find((l) => l.startsWith("FAIL  shfmt (cli, required): "));
      assert.ok(fail, `${v} must give a shfmt FAIL line:\n${r.out}`);
      assert.ok(fail.includes(`/shfmt is ${v}; 3.14.1 or newer is needed`), `names ${v} and the floor: ${fail}`);
      assert.ok(fail.includes("https://github.com/mvdan/sh#shfmt"), `names where to get shfmt: ${fail}`);
    }
    for (const v of ["3.14.1", "3.15.0"]) {
      const r = check(v);
      assert.equal(r.code, 0, `${v} must pass the check:\n${r.out}`);
      assert.ok(r.out.split("\n").some((l) => l.startsWith("PASS  shfmt (cli, required): ")), `${v}:\n${r.out}`);
    }
  });
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

describe("latest", { skip: !posix && "the stub tools are POSIX shell scripts" }, () => {
  const version = { args: ["--version"], pattern: "([0-9.]+)", min: "0", latest: "npm:demo-cli" };
  const demo = (over = {}) => entry({ id: "demo-cli", for: ["skill:demo"], detect: { any: ["demo-cli"], version }, ...over });
  function fakeFetch(latest) {
    const calls = [];
    const fetch = async (url) => {
      calls.push(url);
      return { ok: true, status: 200, json: async () => ({ version: latest }) };
    };
    return { fetch, calls };
  }
  async function latest(argv, ctx) {
    const lines = { stdout: [], stderr: [] };
    const code = await main(argv, { cwd: work, stdin: () => "", ...ctx }, {
      stdout: (s) => lines.stdout.push(s),
      stderr: (s) => lines.stderr.push(s),
    });
    return { code, out: lines.stdout.join("\n"), err: lines.stderr.join("\n") };
  }
  const runLatest = (root, PATH, fetch) =>
    latest(["latest", root, "--for", "skill:demo", "--data-dir", path.join(work, `data${++counter}`)], { env: { PATH }, fetch });

  test("a CLI behind its latest release prints one line, then nothing for the rest of the day", async () => {
    const root = plugin([demo()]);
    const PATH = bin({ "demo-cli": "echo 1.2.0" });
    const { fetch, calls } = fakeFetch("1.3.0");
    const data = path.join(work, `data${++counter}`);
    const run = () => latest(["latest", root, "--data-dir", data], { env: { PATH }, fetch });
    const first = await run();
    assert.equal(first.code, 0);
    assert.equal(first.out, "demo-cli 1.2.0 is behind 1.3.0.");
    assert.deepEqual(calls, ["https://registry.npmjs.org/demo-cli/latest"]);
    const second = await run();
    assert.equal(second.code, 0);
    assert.equal(second.out, "");
    assert.equal(calls.length, 1);
  });

  test("a current CLI prints nothing", async () => {
    const r = await runLatest(plugin([demo()]), bin({ "demo-cli": "echo 1.3.0" }), fakeFetch("1.3.0").fetch);
    assert.equal(r.code, 0);
    assert.equal(r.out, "");
  });

  test("a missing CLI is reported without a lookup", async () => {
    const { fetch, calls } = fakeFetch("1.3.0");
    const r = await runLatest(plugin([demo()]), bin({}), fetch);
    assert.equal(r.out, "demo-cli is not installed or printed no version.");
    assert.equal(calls.length, 0);
  });

  test("entries with no latest source, or outside the scope, are not looked up", async () => {
    const plain = demo({ detect: { any: ["demo-cli"] } });
    const other = demo({ id: "other-cli", for: ["skill:other"] });
    const { fetch, calls } = fakeFetch("9.0.0");
    const r = await runLatest(plugin([plain, other]), bin({ "demo-cli": "echo 1.0.0" }), fetch);
    assert.equal(r.code, 0);
    assert.equal(r.out, "");
    assert.equal(calls.length, 0);
  });

  test("an unknown data directory is a usage error", async () => {
    const r = await latest(["latest", plugin([demo()])], { env: { PATH: "" } });
    assert.equal(r.code, 2);
    assert.match(r.err, /data directory is unknown/);
  });
});
