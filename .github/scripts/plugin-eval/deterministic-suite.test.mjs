import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { deterministicSuite } from "./deterministic-suite.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "deterministic-suite.mjs");

function withPlugin(files, run) {
  const dir = mkdtempSync(join(tmpdir(), "det-suite-"));
  try {
    for (const [path, text] of Object.entries(files)) {
      mkdirSync(dirname(join(dir, path)), { recursive: true });
      writeFileSync(join(dir, path), text);
    }
    return run(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const SUITE = {
  "evals/regex-only/prompt.md": "Say hi.\n",
  "evals/regex-only/graders/says-hi.md": "---\ntype: regex\npattern: hi\n---\n",
  "evals/judged/prompt.md": "Explain.\n",
  "evals/judged/graders/clear.md": "---\ntype: llm\n---\nThe answer is clear.\n",
  "evals/listed/case.yaml": 'schema_version: "1"\nname: listed\ngraders:\n  - {name: same, type: "baseline", baseline_file: b.md, criteria: x}\n',
  "evals/group/nested/prompt.md": "Use the tool.\n",
  "evals/group/nested/graders/used.md": "---\ntype: tool_used\ntool: Skill\n---\n",
  "evals/mocks/server.json": "{}\n",
  "evals/results/old/aggregate-result.json": "{}\n",
};

test("only the cases with deterministic graders are copied, with the suite's other files", () => {
  withPlugin(SUITE, (dir) => {
    const { evalDir, kept, dropped } = deterministicSuite(dir, "evals-deterministic");
    assert.equal(evalDir, "evals");
    assert.deepEqual(kept, ["group/nested", "regex-only"]);
    assert.deepEqual(dropped.sort(), ["judged", "listed"]);
    const out = join(dir, "evals-deterministic");
    assert.ok(existsSync(join(out, "regex-only/graders/says-hi.md")));
    assert.ok(existsSync(join(out, "group/nested/graders/used.md")));
    assert.ok(existsSync(join(out, "mocks/server.json")));
    assert.ok(!existsSync(join(out, "judged")));
    assert.ok(!existsSync(join(out, "listed")));
    assert.ok(!existsSync(join(out, "results")));
  });
});

const MIXED_YAML = [
  'schema_version: "1.1"',
  "name: mixed",
  "# graders below",
  "graders:",
  "  - name: says-hi",
  "    type: regex",
  "    pattern: hi",
  "",
  "  - name: kind",
  "    type: 'llm'",
  "    criteria: >-",
  "      The reply is kind.",
  "  - name: no-bash",
  "    type: tool_used",
  "    tool: Bash",
  "    max: 0",
  "# trailing comment",
  "runs: 2",
  "",
].join("\n");

const MIXED = {
  "evals/mixed/case.yaml": MIXED_YAML.replace("    criteria: >-\n      The reply is kind.", '    criteria: "The reply is kind."'),
  "evals/mixed/prompt.md": "Say hi.\n",
  "evals/mixed/samples/says-hi.json": "{}\n",
  "evals/mixed/samples/kind.json": "{}\n",
  "evals/md-mixed/prompt.md": "Use the tool.\n",
  "evals/md-mixed/graders/used.md": "---\ntype: tool_used\ntool: Skill\n---\n",
  "evals/md-mixed/graders/judged.md": "---\ntype: llm\n---\nThe answer is clear.\n",
  "evals/yaml-judged-md-kept/case.yaml": 'schema_version: "1"\nname: yaml-judged-md-kept\ngraders:\n  - name: kind\n    type: llm\n    criteria: x\nruns: 1\n',
  "evals/yaml-judged-md-kept/graders/used.md": "---\ntype: tool_used\ntool: Skill\n---\n",
  "evals/flow/case.yaml":
    'schema_version: "1"\nname: flow\ngraders: [{name: a, type: regex, pattern: x}, {name: b, type: llm, criteria: y}]\n',
};

test("a mixed case keeps its deterministic graders and loses the paid ones and their samples", () => {
  withPlugin(MIXED, (dir) => {
    const warnings = [];
    const result = deterministicSuite(dir, "evals-deterministic", (line) => warnings.push(line));
    assert.deepEqual(result.kept, ["md-mixed", "mixed", "yaml-judged-md-kept"]);
    assert.deepEqual(result.dropped, ["flow"]);
    assert.deepEqual(result.stripped, { "md-mixed": ["judged"], mixed: ["kind"], "yaml-judged-md-kept": ["kind"] });
    const out = join(dir, "evals-deterministic");
    assert.equal(
      readFileSync(join(out, "mixed/case.yaml"), "utf8"),
      'schema_version: "1.1"\nname: mixed\n# graders below\ngraders:\n  - name: says-hi\n    type: regex\n    pattern: hi\n\n' +
        "  - name: no-bash\n    type: tool_used\n    tool: Bash\n    max: 0\n# trailing comment\nruns: 2\n",
    );
    assert.ok(existsSync(join(out, "mixed/samples/says-hi.json")));
    assert.ok(!existsSync(join(out, "mixed/samples/kind.json")));
    assert.ok(existsSync(join(out, "md-mixed/graders/used.md")));
    assert.ok(!existsSync(join(out, "md-mixed/graders/judged.md")));
    assert.equal(
      readFileSync(join(out, "yaml-judged-md-kept/case.yaml"), "utf8"),
      'schema_version: "1"\nname: yaml-judged-md-kept\nruns: 1\n',
    );
    assert.ok(!existsSync(join(out, "flow")));
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /^deterministic-suite: flow dropped: /);
  });
});

test("a cut the parser cannot confirm drops the case", () => {
  withPlugin({ "evals/scalar/case.yaml": MIXED_YAML }, (dir) => {
    const warnings = [];
    const result = deterministicSuite(dir, "evals-deterministic", (line) => warnings.push(line));
    assert.deepEqual(result, { evalDir: "evals", kept: [], dropped: ["scalar"], stripped: {} });
    assert.match(warnings[0], /^deterministic-suite: scalar dropped: /);
  });
});

test("the source eval dir is left byte for byte", () => {
  withPlugin({ ...SUITE, ...MIXED }, (dir) => {
    deterministicSuite(dir, "evals-deterministic", () => {});
    for (const [path, text] of Object.entries({ ...SUITE, ...MIXED })) {
      assert.equal(readFileSync(join(dir, path), "utf8"), text, path);
    }
  });
});

test("the manifest's eval dir is read", () => {
  withPlugin(
    {
      ".claude-plugin/plugin.json": JSON.stringify({ name: "p", experimental: { evals: "suite" } }),
      "suite/one/prompt.md": "Hi.\n",
      "suite/one/graders/g.md": "---\ntype: file_exists\npath: x\n---\n",
    },
    (dir) => {
      assert.deepEqual(deterministicSuite(dir, "evals-deterministic"), { evalDir: "suite", kept: ["one"], dropped: [], stripped: {} });
    },
  );
});

test("the command prints the split as JSON and refuses a missing eval dir or a bad name", () => {
  withPlugin(SUITE, (dir) => {
    const ok = spawnSync(process.execPath, [SCRIPT, dir, "evals-deterministic"], { encoding: "utf8" });
    assert.equal(ok.status, 0, ok.stderr);
    assert.deepEqual(JSON.parse(ok.stdout).kept, ["group/nested", "regex-only"]);
    assert.equal(spawnSync(process.execPath, [SCRIPT, dir, "../x"], { encoding: "utf8" }).status, 2);
    assert.equal(spawnSync(process.execPath, [SCRIPT, dir, "evals"], { encoding: "utf8" }).status, 2);
    assert.equal(spawnSync(process.execPath, [SCRIPT, join(dir, "absent"), "evals-deterministic"], { encoding: "utf8" }).status, 2);
    assert.equal(readFileSync(join(dir, "evals/judged/prompt.md"), "utf8"), "Explain.\n");
  });
});
