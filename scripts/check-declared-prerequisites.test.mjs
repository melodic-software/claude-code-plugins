import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, describe, test } from "node:test";
import { main, usesOf } from "./check-declared-prerequisites.mjs";

const TOOLS = ["jq", "gh", "node", "python3", "python", "uv", "claude", "go", "rg"];
const tools = (file, text) => usesOf(file, text, TOOLS).map((u) => `${u.tool}@${u.line}`);

describe("usesOf finds a run", () => {
  const cases = [
    ["a.sh", "jq -r .x file", ["jq@1"]],
    ["a.sh", "cat f | jq .", ["jq@1"]],
    ["a.sh", 'out="$(gh api user)"', ["gh@1"]],
    ["a.sh", "if ! command -v uv >/dev/null; then", ["uv@1"]],
    ["a.sh", "FOO=1 BAR='a b' node x.mjs", ["node@1"]],
    ["a.sh", "( cd a && rg x )", ["rg@1"]],
    ["a.sh", "python3 - <<'PY'\nimport os\njq = 1\nPY\ngo build", ["python3@1", "go@5"]],
    ["a.ps1", "if (Get-Command node -ErrorAction SilentlyContinue) {", ["node@1"]],
    ["a.ps1", "& gh pr list", ["gh@1"]],
    ["a.mjs", 'const r = spawnSync("gh", ["api"]);', ["gh@1"]],
    ["a.mjs", "execSync(`jq -r .x ${f}`)", ["jq@1"]],
    ["a.py", 'subprocess.run(["claude", "plugin", "list"])', ["claude@1"]],
    ["a.py", 'node = shutil.which("node")', ["node@1"]],
    ["a.sh", 'PWSH="$(command -v go)"', ["go@1"]],
    ["a.sh", "x=$(gh)", ["gh@1"]],
    ["a.sh", "x=$(which gh)", ["gh@1"]],
    ["a.sh", "y=$(command gh)", ["gh@1"]],
    ["a.ps1", "$p = (Get-Command node)", ["node@1"]],
    ["a.ts", 'spawnSync("gh", ["api"])', ["gh@1"]],
    ["a.mts", 'execFileSync(\n  "jq",\n  ["."],\n)', ["jq@2"]],
    ["a.js", 'const p = spawn(\n  "gh",\n  args,\n);', ["gh@2"]],
    ["skills/x/SKILL.md", "Text about jq.\n\n```bash\ngh pr view\n```\n\nRun: !`uv --version`", ["gh@4", "uv@7"]],
  ];
  for (const [file, text, want] of cases) {
    test(`${file}: ${JSON.stringify(text)}`, () => assert.deepEqual(tools(file, text), want));
  }
});

describe("usesOf ignores a mention", () => {
  const cases = [
    ["a.sh", "# jq is required here"],
    ["a.sh", 'echo "install jq first"'],
    ["a.sh", "  node | python | go)"],
    ["a.sh", "grep -E '^(go|node)$' f"],
    ["a.sh", "awk '/WebFetch|curl |gh api/ { print NR }' f"],
    ["a.sh", "RESERVED='anthropic claude'"],
    ["a.sh", "READERS=(go node python)"],
    ["a.sh", 'msg="guard did not run (claude --debug)."'],
    ["a.sh", "cat <<EOF\njq is how you read it\nEOF"],
    ["a.sh", "jq -r .x f # prereq-ok: test helper only"],
    ["a.ps1", "node   = $raw.node"],
    ["a.ps1", "<#\n`claude` is the folder\n#>"],
    ["a.mjs", '// spawnSync("gh")'],
    ["a.mjs", 'if (name.includes("node")) {}'],
    ["skills/x/SKILL.md", 'Run jq to read it.\n\n```json\n{"gh": 1}\n```'],
  ];
  for (const [file, text] of cases) {
    test(`${file}: ${JSON.stringify(text)}`, () => assert.deepEqual(tools(file, text), []));
  }
});

const work = mkdtempSync(path.join(tmpdir(), "declared-prereq-"));
after(() => rmSync(work, { recursive: true, force: true }));
let n = 0;

const jqEntry = {
  id: "jq",
  kind: "cli",
  need: "required",
  for: ["plugin"],
  detect: { any: ["jq"] },
  degrade: "Without jq nothing runs.",
  install: { docs: "https://jqlang.org/download/" },
  check: "/alpha:check",
};

// repo({ plugins: { name: { manifest, files } }, shared, baseline }) -> root
function repo({ plugins, shared = [], baseline = [] }) {
  const root = path.join(work, `repo${++n}`);
  mkdirSync(path.join(root, "scripts"), { recursive: true });
  writeFileSync(path.join(root, "scripts", "prerequisites-tools.txt"), "# tools\njq\ngh\n");
  writeFileSync(path.join(root, "scripts", "shared-copies.txt"), `${shared.join("\n")}\n`);
  writeFileSync(path.join(root, "scripts", "prerequisites-baseline.txt"), `# header\n${baseline.join("\n")}\n`);
  for (const [name, { manifest, files = {} }] of Object.entries(plugins)) {
    const dir = path.join(root, "plugins", name);
    mkdirSync(dir, { recursive: true });
    if (manifest) writeFileSync(path.join(dir, "prerequisites.json"), JSON.stringify(manifest));
    for (const [rel, text] of Object.entries(files)) {
      mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
      writeFileSync(path.join(dir, rel), text);
    }
  }
  return root;
}

const copies = (name) =>
  ["mjs", "sh", "ps1"].map((ext) => `lib/prerequisites.${ext} plugins/${name}/lib/prerequisites.${ext}`);

function gate(argv) {
  const lines = { log: [], error: [] };
  const code = main(argv, { log: (s) => lines.log.push(s), error: (s) => lines.error.push(s) });
  return { code, out: lines.log.join("\n"), err: lines.error.join("\n") };
}

describe("main", () => {
  test("passes a plugin that declares the tools it runs and carries the checker copies", () => {
    const root = repo({
      plugins: { alpha: { manifest: { requires: [jqEntry] }, files: { "hooks/a.sh": "jq .\n" } } },
      shared: copies("alpha"),
    });
    const r = gate(["--root", root]);
    assert.equal(r.code, 0, r.err);
    assert.match(r.out, /0 baselined gap/);
  });

  test("fails an undeclared tool with its file and line", () => {
    const root = repo({
      plugins: { alpha: { manifest: { requires: [jqEntry] }, files: { "scripts/a.sh": "jq .\ngh pr list\n" } } },
      shared: copies("alpha"),
    });
    const r = gate(["--root", root]);
    assert.equal(r.code, 1);
    assert.match(
      r.err,
      /plugins\/alpha runs gh but its prerequisites.json does not declare it: plugins\/alpha\/scripts\/a.sh:2/,
    );
  });

  test("a plugin with no prerequisites.json declares nothing", () => {
    const root = repo({ plugins: { beta: { files: { "skills/x/SKILL.md": "```bash\njq .\n```\n" } } } });
    const r = gate(["--root", root]);
    assert.equal(r.code, 1);
    assert.match(r.err, /plugins\/beta runs jq/);
  });

  test("does not scan test files, fixtures or evals", () => {
    const files = {
      "hooks/a.test.sh": "gh x\n",
      "tests/b.sh": "gh x\n",
      "skills/x/evals/c.sh": "gh x\n",
      "skills/x/fixtures/d.sh": "gh x\n",
    };
    const root = repo({ plugins: { beta: { files } } });
    assert.equal(gate(["--root", root]).code, 0);
  });

  test("a baselined gap passes and a baseline row with no gap behind it fails", () => {
    const files = { "a.sh": "gh x\n" };
    assert.equal(gate(["--root", repo({ plugins: { beta: { files } }, baseline: ["beta gh"] })]).code, 0);
    const r = gate(["--root", repo({ plugins: { beta: { files } }, baseline: ["beta gh", "beta jq"] })]);
    assert.equal(r.code, 1);
    assert.match(r.err, /"beta jq" no longer matches a gap/);
  });

  test("a manifest that fails the schema fails unless baselined as schema, and a schema row on a valid file is stale", () => {
    const legacy = { tools: [{ name: "jq", check: "/beta:check", install: "x" }] };
    const bad = gate(["--root", repo({ plugins: { beta: { manifest: legacy } } })]);
    assert.equal(bad.code, 1);
    assert.match(bad.err, /plugins\/beta\/prerequisites.json: manifest: unknown key "tools"/);
    assert.equal(
      gate(["--root", repo({ plugins: { beta: { manifest: legacy } }, baseline: ["beta schema"] })]).code,
      0,
    );
    const stale = gate([
      "--root",
      repo({
        plugins: { alpha: { manifest: { requires: [jqEntry] } } },
        shared: copies("alpha"),
        baseline: ["alpha schema"],
      }),
    ]);
    assert.equal(stale.code, 1);
    assert.match(stale.err, /"alpha schema" no longer matches a gap/);
  });

  test("a legacy manifest declares nothing", () => {
    const legacy = { tools: [{ name: "jq", check: "/beta:check", install: "x" }] };
    const r = gate([
      "--root",
      repo({ plugins: { beta: { manifest: legacy, files: { "a.sh": "jq .\n" } } }, baseline: ["beta schema"] }),
    ]);
    assert.equal(r.code, 1);
    assert.match(r.err, /plugins\/beta runs jq/);
  });

  test("a valid manifest without the registered checker copies fails", () => {
    const r = gate([
      "--root",
      repo({ plugins: { alpha: { manifest: { requires: [jqEntry] } } }, shared: copies("alpha").slice(0, 2) }),
    ]);
    assert.equal(r.code, 1);
    assert.match(
      r.err,
      /plugins\/alpha: declares prerequisites but scripts\/shared-copies.txt lacks "lib\/prerequisites.ps1 plugins\/alpha\/lib\/prerequisites.ps1"/,
    );
  });

  test("--write-baseline records every gap, then the gate passes", () => {
    const legacy = { tools: [] };
    const root = repo({ plugins: { beta: { manifest: legacy, files: { "a.sh": "gh x\njq .\n" } } } });
    const w = gate(["--root", root, "--write-baseline"]);
    assert.equal(w.code, 0, w.err);
    const rows = readFileSync(path.join(root, "scripts", "prerequisites-baseline.txt"), "utf8")
      .split("\n")
      .filter((l) => l && !l.startsWith("#"));
    assert.deepEqual(rows, ["beta gh", "beta jq", "beta schema"]);
    assert.equal(gate(["--root", root]).code, 0);
  });

  test("usage errors and unreadable inputs exit 2", () => {
    assert.equal(gate(["--bogus"]).code, 2);
    const root = repo({ plugins: {} });
    rmSync(path.join(root, "scripts", "prerequisites-tools.txt"));
    assert.equal(gate(["--root", root]).code, 2);
  });
});
