#!/usr/bin/env node
// Parse every Mermaid block in the given files; pre-render to SVG when the pinned mmdc is present.
// Usage: mermaid-gate.mjs [--svg-dir <dir>] [--mmdc <path>] <file>...
// A .mmd or .mermaid file is one block; any other file contributes its ```mermaid fences.
// Stdout is one JSON report. Exit 0 when every block parses, 1 on a syntax error, 2 on a usage error.
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";

export const PINNED_MMDC = "11.17.0";

const DIAGRAM_TYPES = [
  "flowchart", "graph", "sequenceDiagram", "classDiagram", "stateDiagram", "stateDiagram-v2",
  "erDiagram", "journey", "gantt", "pie", "quadrantChart", "requirementDiagram", "gitGraph",
  "mindmap", "timeline", "sankey", "xychart", "block", "packet", "architecture", "kanban",
  "radar", "treemap", "zenuml", "C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment",
];

export function extractBlocks(text, isDiagramFile) {
  if (isDiagramFile) return [{ source: text, line: 1 }];
  const blocks = [];
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const open = /^\s*(`{3,}|~{3,})\s*mermaid\s*$/.exec(lines[i]);
    if (!open) continue;
    const body = [];
    let j = i + 1;
    while (j < lines.length && !lines[j].trim().startsWith(open[1])) body.push(lines[j++]);
    blocks.push({ source: body.join("\n"), line: i + 2 });
    i = j;
  }
  return blocks;
}

function bodyLines(source) {
  const lines = source.split("\n");
  let start = 0;
  if (lines[0]?.trim() === "---") {
    const end = lines.findIndex((l, i) => i > 0 && l.trim() === "---");
    if (end > 0) start = end + 1;
  }
  return lines
    .map((text, i) => ({ text, n: i + 1 }))
    .slice(start)
    .filter(({ text }) => text.trim() && !text.trim().startsWith("%%"));
}

// Without mmdc there is no real parser, so this catches only what is certain: an unknown diagram
// type, an unterminated quote, or unbalanced brackets in a flowchart.
export function structuralCheck(source) {
  const lines = bodyLines(source);
  if (!lines.length) return "the block is empty";
  const first = lines[0].text.trim().split(/[\s;]/)[0];
  const head = first.replace(/-beta$/, "");
  if (!DIAGRAM_TYPES.includes(head)) return `line ${lines[0].n}: unknown diagram type '${first}'`;
  const flow = head === "flowchart" || head === "graph";
  for (const { text, n } of lines.slice(1)) {
    if ((text.match(/"/g) ?? []).length % 2) return `line ${n}: unterminated double quote`;
    if (!flow) continue;
    const bare = text.replace(/"[^"]*"/g, "");
    for (const [open, close] of ["[]", "()", "{}"]) {
      const delta = bare.split(open).length - bare.split(close).length;
      if (delta) return `line ${n}: unbalanced '${delta > 0 ? open : close}'`;
    }
  }
  return null;
}

function run(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: "utf8", timeout: 120000 });
  return { ...r, out: `${r.stdout ?? ""}${r.stderr ?? ""}`.trim() };
}

export function resolveMmdc(explicit) {
  const cmd = explicit ?? "mmdc";
  const v = run(cmd, ["--version"]);
  if (v.error) return { reason: `mmdc is not installed (pinned ${PINNED_MMDC}), so the Mermaid source is kept` };
  const version = /(\d+\.\d+\.\d+)/.exec(v.out)?.[1];
  if (version !== PINNED_MMDC) {
    return { reason: `mmdc ${version ?? "of unknown version"} is installed but ${PINNED_MMDC} is pinned, so the Mermaid source is kept` };
  }
  return { cmd };
}

const PARSE_ERROR = /(parse error|lexical error|syntax error)/i;

function render(mmdc, source, work, name) {
  const input = join(work, `${name}.mmd`);
  const output = join(work, `${name}.svg`);
  writeFileSync(input, source);
  const r = run(mmdc, ["-q", "-i", input, "-o", output]);
  if (r.status === 0) return { svg: readFileSync(output, "utf8") };
  const message = r.out.split("\n").find((l) => PARSE_ERROR.test(l)) ?? r.out.split("\n")[0];
  if (PARSE_ERROR.test(r.out)) return { error: message };
  return { reason: `mmdc could not render (${message || "no output"}), so the Mermaid source is kept` };
}

export function gate(files, { svgDir, mmdc: explicitMmdc } = {}) {
  const mmdc = resolveMmdc(explicitMmdc);
  const work = mkdtempSync(join(tmpdir(), "mermaid-gate-"));
  if (svgDir) mkdirSync(svgDir, { recursive: true });
  const blocks = [];
  try {
    for (const file of files) {
      const found = extractBlocks(readFileSync(file, "utf8"), /\.(mmd|mermaid)$/.test(file));
      found.forEach(({ source, line }, i) => {
        const name = `${basename(file).replace(/\.[^.]*$/, "")}-${i + 1}`;
        const block = { file, line, status: "ok", render: "source", reason: mmdc.reason };
        const structural = structuralCheck(source);
        if (structural) {
          Object.assign(block, { status: "error", error: structural, reason: undefined });
        } else if (mmdc.cmd) {
          const r = render(mmdc.cmd, source, work, name);
          if (r.error) Object.assign(block, { status: "error", error: r.error, reason: undefined });
          else if (r.svg && svgDir) {
            const svg = join(svgDir, `${name}.svg`);
            writeFileSync(svg, r.svg);
            Object.assign(block, { render: "svg", svg, reason: undefined });
          } else if (r.svg) block.reason = "no --svg-dir given, so the Mermaid source is kept";
          else block.reason = r.reason;
        }
        blocks.push(block);
      });
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
  return { pinned: PINNED_MMDC, blocks, errors: blocks.filter((b) => b.status === "error").length };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const opts = {};
  const files = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--svg-dir") opts.svgDir = args[++i];
    else if (args[i] === "--mmdc") opts.mmdc = args[++i];
    else files.push(args[i]);
  }
  if (!files.length) {
    console.error("usage: mermaid-gate.mjs [--svg-dir <dir>] [--mmdc <path>] <file>...");
    process.exit(2);
  }
  const report = gate(files, opts);
  console.log(JSON.stringify(report, null, 2));
  process.exit(report.errors ? 1 : 0);
}
