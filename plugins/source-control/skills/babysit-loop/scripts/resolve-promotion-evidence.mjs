#!/usr/bin/env node

// Runs check-security-binding.mjs evaluation mode through the promotion-evidence
// bootstrap and prints each promotable cell's effective state as JSON.
//
// Usage: node resolve-promotion-evidence.mjs --binding <file> --probe-evidence-root <dir>
//          --evidence <file> --checkout <dir> [--worktree-root <dir> ...] --checker <file>
//
// Prints {source, failClosedReason, cells: {<cell>: {bound, effective, line}}} and
// exits 0, fail-closed results included. Fail-closed means failClosedReason is set
// and every promotable cell is effective "unpromoted". It fails closed on a
// missing, relative, or unresolvable path; a bootstrap path or checker that is
// inside the checkout or a worktree root, before or after symlinks resolve; a
// checker that exits non-zero, times out, or prints no evaluation block; and any
// line in that block that does not parse. It reports only what the checker
// printed and never re-derives the resolution algorithm. It writes no file and
// reads nothing in the checkout.

import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import process from "node:process";
import { parseArgs } from "node:util";

const PROMOTABLE_CELLS = ["C2-auto-merge", "C3-auto-merge", "C3-ai-review-blocking"];
const BLOCK_HEADER = "Effective promotion state (evaluation mode):";
const CELL_LINE = /^- ([A-Za-z0-9][A-Za-z0-9-]*): bound (\S+) -> effective (promoted|unpromoted)(?=$|[\s(])/;
const TIMEOUT_MS = 60_000;

function emit(source, failClosedReason, printed = {}) {
  const cells = failClosedReason === null ? { ...printed } : {};
  for (const cell of PROMOTABLE_CELLS) cells[cell] ??= { bound: null, effective: "unpromoted", line: null };
  process.stdout.write(`${JSON.stringify({ source, failClosedReason, cells }, null, 2)}\n`);
  process.exit(0);
}

function isInside(child, root) {
  const rel = relative(root, child);
  return rel === "" || (rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
}

let values;
try {
  ({ values } = parseArgs({
    options: {
      binding: { type: "string" },
      "probe-evidence-root": { type: "string" },
      evidence: { type: "string" },
      checkout: { type: "string" },
      "worktree-root": { type: "string", multiple: true, default: [] },
      checker: { type: "string" },
    },
    strict: true,
    allowPositionals: false,
  }));
} catch (error) {
  emit(null, `usage: ${error.message}`);
}
const source = values.evidence ?? null;

// Returns the realpath, or fails closed with a reason naming the option.
function resolveInput(option, value, roots) {
  if (!value) emit(source, `--${option} not set`);
  if (!isAbsolute(value)) emit(source, `--${option} ${value} is not an absolute path`);
  let real;
  try {
    real = realpathSync.native(value);
  } catch (error) {
    emit(source, `--${option} ${value} cannot be resolved (${error.code ?? error.message})`);
  }
  for (const root of roots) {
    for (const candidate of [resolve(value), real]) {
      if (isInside(candidate, root)) emit(source, `--${option} ${value} is inside ${root}`);
    }
  }
  return real;
}

const checkout = resolveInput("checkout", values.checkout, []);
const roots = [resolve(values.checkout), checkout];
for (const root of values["worktree-root"]) {
  if (!isAbsolute(root)) emit(source, `--worktree-root ${root} is not an absolute path`);
  roots.push(resolve(root));
  try {
    roots.push(realpathSync.native(root));
  } catch {
    // A root that does not exist yet still bounds paths lexically.
  }
}

const checker = resolveInput("checker", values.checker, roots);
const binding = resolveInput("binding", values.binding, roots);
const probeRoot = resolveInput("probe-evidence-root", values["probe-evidence-root"], roots);
const evidence = resolveInput("evidence", values.evidence, roots);

const run = spawnSync(
  process.execPath,
  [checker, binding, "--evidence", evidence, "--probe-evidence-root", probeRoot],
  { cwd: dirname(checker), encoding: "utf8", shell: false, timeout: TIMEOUT_MS, maxBuffer: 16 * 1024 * 1024 },
);
if (run.error) emit(source, `checker did not complete (${run.error.code ?? run.error.message})`);
if (run.status !== 0) {
  const detail = (run.stderr ?? "").trim().split(/\r?\n/)[0].slice(0, 500);
  emit(source, `checker exited ${run.status ?? `on signal ${run.signal}`}${detail ? `: ${detail}` : ""}`);
}

const lines = run.stdout.split(/\r?\n/);
const start = lines.indexOf(BLOCK_HEADER);
if (start === -1) emit(source, "checker printed no 'Effective promotion state' block");

const printed = {};
for (const line of lines.slice(start + 1)) {
  if (line === "") continue;
  const match = CELL_LINE.exec(line);
  if (!match) emit(source, `checker line did not parse: ${line.slice(0, 500)}`);
  const [, cell, bound, effective] = match;
  if (Object.hasOwn(printed, cell)) emit(source, `checker printed ${cell} twice`);
  printed[cell] = { bound, effective, line: line.slice(2) };
}
emit(source, null, printed);
