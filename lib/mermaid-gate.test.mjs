import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { PINNED_MMDC, extractBlocks, gate, structuralCheck } from "./mermaid-gate.mjs";

const SCRIPT = fileURLToPath(new URL("./mermaid-gate.mjs", import.meta.url));
const POSIX = process.platform !== "win32";

const dir = mkdtempSync(join(tmpdir(), "mermaid-gate-test-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const write = (name, text) => {
  const path = join(dir, name);
  writeFileSync(path, text);
  return path;
};

// A stand-in mmdc: reports `version`, fails with a parse error when the diagram contains BOOM,
// fails with a browser error when it contains NOBROWSER, otherwise writes an SVG.
function fakeMmdc(version) {
  const path = join(dir, `mmdc-${version}`);
  writeFileSync(
    path,
    `#!/usr/bin/env node
const fs = require("node:fs");
const a = process.argv.slice(2);
if (a[0] === "--version") { console.log("${version}"); process.exit(0); }
const src = fs.readFileSync(a[a.indexOf("-i") + 1], "utf8");
if (src.includes("BOOM")) { console.error("Error: Parse error on line 2:\\nExpecting 'SEMI', got 'BOOM'"); process.exit(1); }
if (src.includes("NOBROWSER")) { console.error("Could not find Chrome"); process.exit(1); }
fs.writeFileSync(a[a.indexOf("-o") + 1], "<svg>rendered</svg>");
`,
  );
  chmodSync(path, 0o755);
  return path;
}

const GOOD = "flowchart TD\n  A[Start] --> B{Ok?}\n  B -->|yes| C(Done)\n";
const doc = (body) => write(`doc-${Math.random().toString(36).slice(2)}.md`, `# T\n\n\`\`\`mermaid\n${body}\`\`\`\n`);

test("extractBlocks reads fences and whole diagram files", () => {
  const md = "text\n```mermaid\nflowchart TD\n  A-->B\n```\nmore\n~~~mermaid\npie\n~~~\n```js\nx\n```\n";
  const blocks = extractBlocks(md, false);
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0].line, 3);
  assert.equal(extractBlocks("graph LR", true).length, 1);
});

test("structuralCheck accepts valid heads and names each defect", () => {
  assert.equal(structuralCheck(GOOD), null);
  assert.equal(structuralCheck("%%{init: {}}%%\nsequenceDiagram\n  A->>B: hi (there\n"), null);
  assert.equal(structuralCheck("---\ntitle: t\n---\nxychart-beta\n  x-axis [a,b]\n"), null);
  assert.match(structuralCheck("flowcart TD\n  A-->B\n"), /line 1: unknown diagram type 'flowcart'/);
  assert.match(structuralCheck("flowchart TD\n  A[Start --> B\n"), /line 2: unbalanced '\['/);
  assert.match(structuralCheck("flowchart TD\n  A[\"x] --> B\n"), /line 2: unterminated double quote/);
  assert.equal(structuralCheck("flowchart TD\n  A>text] --> B\n  C[a>b] --> D\n"), null);
  assert.match(structuralCheck("flowchart TD\n  A>text --> B\n"), /line 2: unbalanced/);
  assert.equal(structuralCheck("flowchart TD\n  A-->|rate>5|B\n"), null);
  assert.match(structuralCheck("\n%% only a comment\n"), /empty/);
});

test("a syntax error is reported with its line, exit 1, and no mmdc needed", () => {
  const file = doc("flowchart TD\n  A[Start --> B\n");
  const report = gate([file], { mmdc: join(dir, "no-such-mmdc") });
  assert.equal(report.errors, 1);
  assert.equal(report.blocks[0].status, "error");
  assert.match(report.blocks[0].error, /unbalanced '\['/);
  const cli = spawnSync(process.execPath, [SCRIPT, "--mmdc", join(dir, "no-such-mmdc"), file], { encoding: "utf8" });
  assert.equal(cli.status, 1);
  assert.match(JSON.parse(cli.stdout).blocks[0].error, /line 2/);
});

test("mmdc absent keeps the source and says why", () => {
  const report = gate([doc(GOOD)], { svgDir: join(dir, "svg-none"), mmdc: join(dir, "no-such-mmdc") });
  const [block] = report.blocks;
  assert.equal(block.status, "ok");
  assert.equal(block.render, "source");
  assert.match(block.reason, new RegExp(`not installed.*${PINNED_MMDC}`));
  assert.equal(block.svg, undefined);
});

test("pinned mmdc present pre-renders to SVG", { skip: !POSIX }, () => {
  const svgDir = join(dir, "svg-ok");
  const report = gate([doc(GOOD)], { svgDir, mmdc: fakeMmdc(PINNED_MMDC) });
  const [block] = report.blocks;
  assert.equal(block.render, "svg");
  assert.ok(existsSync(block.svg));
  assert.equal(readFileSync(block.svg, "utf8"), "<svg>rendered</svg>");
});

test("pinned mmdc present but no --svg-dir parses only", { skip: !POSIX }, () => {
  const [block] = gate([doc(GOOD)], { mmdc: fakeMmdc(PINNED_MMDC) }).blocks;
  assert.equal(block.render, "source");
  assert.match(block.reason, /no --svg-dir/);
});

test("mmdc parse error is reported by name and fails the gate", { skip: !POSIX }, () => {
  const report = gate([doc("flowchart TD\n  A --> BOOM\n")], { svgDir: join(dir, "svg-bad"), mmdc: fakeMmdc(PINNED_MMDC) });
  assert.equal(report.errors, 1);
  assert.match(report.blocks[0].error, /Parse error on line 2/);
});

test("a wrong mmdc version is not used", { skip: !POSIX }, () => {
  const [block] = gate([doc(GOOD)], { svgDir: join(dir, "svg-ver"), mmdc: fakeMmdc("10.9.1") }).blocks;
  assert.equal(block.render, "source");
  assert.match(block.reason, new RegExp(`10\\.9\\.1.*${PINNED_MMDC} or newer is needed`));
});

test("a newer mmdc version is used, as the prerequisite check's minimum accepts it", { skip: !POSIX }, () => {
  const [block] = gate([doc(GOOD)], { svgDir: join(dir, "svg-newer"), mmdc: fakeMmdc("11.18.0") }).blocks;
  assert.equal(block.render, "svg");
});

test("two input files with the same name keep separate SVGs", { skip: !POSIX }, () => {
  const svgDir = join(dir, "svg-dup");
  const files = ["a", "b"].map((d) => {
    mkdirSync(join(dir, d), { recursive: true });
    return write(join(d, "design.mmd"), GOOD);
  });
  const report = gate(files, { svgDir, mmdc: fakeMmdc(PINNED_MMDC) });
  assert.equal(new Set(report.blocks.map((b) => b.svg)).size, 2);
});

test("an mmdc render failure that is not a parse error falls back to source", { skip: !POSIX }, () => {
  const [block] = gate([doc("flowchart TD\n  A --> NOBROWSER\n")], { svgDir: join(dir, "svg-nb"), mmdc: fakeMmdc(PINNED_MMDC) }).blocks;
  assert.equal(block.status, "ok");
  assert.equal(block.render, "source");
  assert.match(block.reason, /Could not find Chrome/);
});

test("the CLI refuses a call with no file", () => {
  const cli = spawnSync(process.execPath, [SCRIPT], { encoding: "utf8" });
  assert.equal(cli.status, 2);
});
