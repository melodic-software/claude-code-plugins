#!/usr/bin/env node

// Runs check-security-binding.mjs evaluation mode through the promotion-evidence
// bootstrap and prints each promotable cell's effective state as JSON.
//
// Usage: node resolve-promotion-evidence.mjs --checkout <dir> [--worktree-root <dir> ...]
//          [--window-start <ISO 8601 date-time with an offset>]
//
// --window-start restarts the evidence window after a demotion: the checker reads a copy of the
// evidence source, written to a fresh temporary directory outside the checkout and every
// worktree root and removed on exit, with one gate-failure event per promotable cell at that
// instant appended, so a cell stays unpromoted until it is re-ratified after it. An empty or
// malformed value, or a source that cannot be read as a JSON array, fails closed.
//
// The four bootstrap values (promotion_evidence_binding, promotion_evidence_root,
// promotion_evidence_source, promotion_evidence_checker) are not arguments: the helper reads
// them from the operator's own managed and user settings (operator-options.mjs, channel F
// of docs/conventions/hook-config-delivery), so a path the caller chose cannot stand in for
// one, and the CLAUDE_PLUGIN_OPTION_* mirror and repository files are never read for them.
// Prints {source, failClosedReason, options: {<option>: {value, scope, file}}, cells:
// {<cell>: {bound, effective, line}}} and exits 0, fail-closed results included.
// Fail-closed means failClosedReason is set and every promotable cell is effective
// "unpromoted". It fails closed on an unknown argument (the retired --binding,
// --probe-evidence-root, --evidence and --checker included); an option no readable source
// sets, or a settings source that cannot be read; a relative or unresolvable path; a surface
// or checker that is inside the checkout or a worktree root, or contains one, before or after
// symlinks resolve; a checker that exits non-zero, times out, or prints no evaluation block;
// and any line in that block that does not parse. The checker runs with an allowlisted
// environment (PATH and SystemRoot only), so NODE_OPTIONS, NODE_PATH, LD_PRELOAD and GIT_*
// values from a repository's settings env block never reach it. It reports only what the
// checker printed and never re-derives the resolution algorithm. It writes no file but the
// --window-start copy and reads nothing in the checkout.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "./operator-options.mjs";

const PROMOTABLE_CELLS = ["C2-auto-merge", "C3-auto-merge", "C3-ai-review-blocking"];
const BLOCK_HEADER = "Effective promotion state (evaluation mode):";
const CELL_LINE = /^- ([A-Za-z0-9][A-Za-z0-9-]*): bound (\S+) -> effective (promoted|unpromoted)(?=$|[\s(])/;
const TIMEOUT_MS = 60_000;
const CHECKER_ENV_KEYS = ["PATH", "SystemRoot"];

let options = {};

function emit(source, failClosedReason, printed = {}) {
  const cells = failClosedReason === null ? { ...printed } : {};
  for (const cell of PROMOTABLE_CELLS) cells[cell] ??= { bound: null, effective: "unpromoted", line: null };
  process.stdout.write(`${JSON.stringify({ source, failClosedReason, options, cells }, null, 2)}\n`);
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
      checkout: { type: "string" },
      "worktree-root": { type: "string", multiple: true, default: [] },
      "window-start": { type: "string" },
    },
    strict: true,
    allowPositionals: false,
  }));
} catch (error) {
  emit(null, `usage: ${error.message}`);
}

// This install's root, from the helper's own real path (skills/babysit-loop/scripts/ below it),
// never from the environment.
const pluginRoot = resolve(dirname(realpathSync.native(fileURLToPath(import.meta.url))), "..", "..", "..");
try {
  options = readOperatorOptions(resolveInstall(pluginRoot), managedSettingsFiles());
} catch (error) {
  if (!(error instanceof OptionsError)) throw error;
  emit(null, error.message);
}
const source = options.promotion_evidence_source?.value || null;

// Returns the realpath, or fails closed with a reason naming the option or argument.
function resolveInput(label, value, roots) {
  if (!value) emit(source, `${label} not set${label.startsWith("--") ? "" : " in managed or user settings"}`);
  if (!isAbsolute(value)) emit(source, `${label} ${value} is not an absolute path`);
  let real;
  try {
    real = realpathSync.native(value);
  } catch (error) {
    emit(source, `${label} ${value} cannot be resolved (${error.code ?? error.message})`);
  }
  for (const root of roots) {
    for (const candidate of [resolve(value), real]) {
      if (isInside(candidate, root)) emit(source, `${label} ${value} is inside ${root}`);
      if (isInside(root, candidate)) emit(source, `${label} ${value} contains ${root}`);
    }
  }
  return real;
}
const option = (key, roots) => resolveInput(key, options[key]?.value, roots);

// A root that does not exist yet is canonicalized through its longest existing prefix, so a
// symlinked parent cannot hide where the root will land.
function canonical(path) {
  const missing = [];
  let existing = path;
  for (;;) {
    try {
      return resolve(realpathSync.native(existing), ...missing);
    } catch {
      const parent = dirname(existing);
      if (parent === existing) return path;
      missing.unshift(basename(existing));
      existing = parent;
    }
  }
}

// The checker's strict form: an explicit offset, at most millisecond precision, and a calendar
// date that survives a round trip, so the instant cannot shift across a ratification.
const ISO_DATE_TIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,3})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/;
function isStrictIso(value) {
  const match = ISO_DATE_TIME.exec(value);
  if (!match) return false;
  const [, year, month, day, hour, minute, second] = match.map(Number);
  const utc = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  return (
    utc.getUTCFullYear() === year &&
    utc.getUTCMonth() === month - 1 &&
    utc.getUTCDate() === day &&
    utc.getUTCHours() === hour &&
    utc.getUTCMinutes() === minute &&
    utc.getUTCSeconds() === second
  );
}

// The source's events plus one gate-failure per promotable cell at `at`, written outside every
// root and removed on exit.
function restartedCopy(path, at, roots) {
  if (!isStrictIso(at)) emit(source, `--window-start ${JSON.stringify(at)} is not an ISO 8601 date-time with an offset`);
  let events;
  try {
    events = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    emit(source, `promotion_evidence_source ${path} cannot be read as JSON (${error.code ?? error.message})`);
  }
  if (!Array.isArray(events)) emit(source, `promotion_evidence_source ${path} is not a JSON array`);
  const dir = realpathSync.native(mkdtempSync(join(tmpdir(), "promotion-evidence-")));
  process.on("exit", () => rmSync(dir, { recursive: true, force: true }));
  for (const root of roots) {
    if (isInside(dir, root) || isInside(root, dir)) emit(source, `the --window-start copy ${dir} would sit inside or contain ${root}`);
  }
  const copy = join(dir, "evidence.json");
  writeFileSync(copy, JSON.stringify([...events, ...PROMOTABLE_CELLS.map((cell) => ({ cell, event: "gate-failure", at }))]));
  return copy;
}

const checkout = resolveInput("--checkout", values.checkout, []);
const roots = [resolve(values.checkout), checkout];
for (const root of values["worktree-root"]) {
  if (!isAbsolute(root)) emit(source, `--worktree-root ${root} is not an absolute path`);
  roots.push(resolve(root), canonical(resolve(root)));
}

const checker = option("promotion_evidence_checker", roots);
const binding = option("promotion_evidence_binding", roots);
const probeRoot = option("promotion_evidence_root", roots);
const sourcePath = option("promotion_evidence_source", roots);
const evidence =
  values["window-start"] === undefined ? sourcePath : restartedCopy(sourcePath, values["window-start"], roots);

const checkerEnv = Object.fromEntries(
  CHECKER_ENV_KEYS.filter((key) => key in process.env).map((key) => [key, process.env[key]]),
);
const run = spawnSync(
  process.execPath,
  [checker, binding, "--evidence", evidence, "--probe-evidence-root", probeRoot],
  { cwd: dirname(checker), env: checkerEnv, encoding: "utf8", shell: false, timeout: TIMEOUT_MS, maxBuffer: 16 * 1024 * 1024 },
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
