#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { accessSync, constants, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "./operator-options.mjs";

export const OPTION_KEYS = [
  "promotion_evidence_binding",
  "promotion_evidence_root",
  "promotion_evidence_source",
  "promotion_evidence_checker",
  "promotion_evidence_credential_roots",
  "promotion_evidence_max_age_hours",
];
const MAX_AGE = "promotion_evidence_max_age_hours";
const HOUR_MS = 3_600_000;
const CLOCK_SKEW_MS = 300_000;

const PROMOTABLE_CELLS = ["C2-auto-merge", "C3-auto-merge", "C3-ai-review-blocking"];
const BLOCK_HEADER = "Effective promotion state (evaluation mode):";
const CELL_LINE = /^- ([A-Za-z0-9][A-Za-z0-9-]*): bound (\S+) -> effective (promoted|unpromoted)(?=$|[\s(])/;
const TIMEOUT_MS = 60_000;
const CHECKER_ENV_KEYS = ["PATH", "SystemRoot"];

let options = {};
let source = null;

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

function canWrite(path) {
  try {
    accessSync(path, constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

export function laneWritable(path, { access = canWrite, stat = statSync, uid = process.getuid?.() } = {}) {
  const given = isAbsolute(path) ? path : `${process.cwd()}${sep}${path}`;
  for (const candidate of new Set([given, resolve(path), realpathSync.native(path)])) {
    for (let node = candidate; ; node = dirname(node)) {
      if (access(node)) return true;
      if (uid !== undefined && stat(node).uid === uid) return true;
      if (dirname(node) === node) break;
    }
  }
  return false;
}

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

function refuseLaneWritable(label, path, judge) {
  let writable;
  try {
    writable = laneWritable(path, judge);
  } catch (error) {
    emit(source, `writability-unverifiable:${label} (${error.code ?? error.message})`);
  }
  if (writable) emit(source, `lane-writable:${label}`);
}

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

const restartEvents = (events, at) => [...events, ...PROMOTABLE_CELLS.map((cell) => ({ cell, event: "gate-failure", at }))];

function requireFresh(path, text, judge) {
  const bound = options[MAX_AGE]?.value?.trim();
  if (!bound) emit(source, `${MAX_AGE} not set in managed or user settings, so a re-earn cannot be read`);
  if (!/^[1-9]\d{0,5}$/.test(bound)) emit(source, `${MAX_AGE} ${JSON.stringify(bound)} is not a whole number of hours from 1 to 999999`);
  refuseLaneWritable(options[MAX_AGE].file, options[MAX_AGE].file, judge);
  const sidecar = `${path.replace(/\.json$/, "")}.meta.json`;
  let meta;
  try {
    meta = JSON.parse(readFileSync(sidecar, "utf8"));
  } catch (error) {
    emit(source, `promotion_evidence_source ${path} has no readable sidecar ${sidecar} (${error.code ?? error.message})`);
  }
  refuseLaneWritable(sidecar, sidecar, judge);
  if (meta?.sha256 !== createHash("sha256").update(text).digest("hex")) {
    emit(source, `the sidecar ${sidecar} does not hold the sha256 of promotion_evidence_source ${path}`);
  }
  const generatedAt = meta.generated_at;
  if (typeof generatedAt !== "string" || !isStrictIso(generatedAt)) {
    emit(source, `the sidecar ${sidecar} has no ISO 8601 generated_at: ${JSON.stringify(generatedAt)}`);
  }
  const age = Date.now() - Date.parse(generatedAt);
  if (age < -CLOCK_SKEW_MS) emit(source, `the sidecar ${sidecar} has a generated_at ${generatedAt} in the future`);
  if (age > Number(bound) * HOUR_MS) {
    emit(source, `promotion_evidence_source ${path} is stale: generated_at ${generatedAt} is older than ${MAX_AGE} ${bound}`);
  }
}

function checkedSource(path, judge) {
  let text;
  let events;
  try {
    text = readFileSync(path, "utf8");
    events = JSON.parse(text);
  } catch {
    return path;
  }
  if (Array.isArray(events) && events.some((event) => event?.event === "re-earned")) requireFresh(path, text, judge);
  return path;
}

function restartedCopy(path, at, roots, judge) {
  if (!isStrictIso(at)) emit(source, `--window-start ${JSON.stringify(at)} is not an ISO 8601 date-time with an offset`);
  let text;
  let events;
  try {
    text = readFileSync(path, "utf8");
    events = JSON.parse(text);
  } catch (error) {
    emit(source, `promotion_evidence_source ${path} cannot be read as JSON (${error.code ?? error.message})`);
  }
  if (!Array.isArray(events)) emit(source, `promotion_evidence_source ${path} is not a JSON array`);
  requireFresh(path, text, judge);
  const dir = realpathSync.native(mkdtempSync(join(tmpdir(), "promotion-evidence-")));
  process.on("exit", () => rmSync(dir, { recursive: true, force: true }));
  for (const root of roots) {
    if (isInside(dir, root) || isInside(root, dir)) emit(source, `the --window-start copy ${dir} would sit inside or contain ${root}`);
  }
  const copy = join(dir, "evidence.json");
  writeFileSync(copy, JSON.stringify(restartEvents(events, at)));
  return copy;
}

function hostPath(value) {
  const slashed = value.replaceAll("\\", "/");
  const drive = /^[A-Za-z]:\//.test(slashed);
  if (slashed.startsWith("//") || (!drive && !slashed.startsWith("/"))) return null;
  const segments = slashed.slice(drive ? 3 : 1).split("/").filter((s) => s !== "" && s !== ".");
  return drive ? { anchor: slashed.slice(0, 2).toLowerCase(), segments: segments.map((s) => s.toLowerCase()) } : { anchor: "", segments };
}

const EPHEMERAL_SEGMENTS = new Set(["tmp", "temp", "shm"]);

function credentialRootsArgs(value, roots) {
  if (value === undefined || value.trim() === "") return [];
  const label = "promotion_evidence_credential_roots";
  for (const entry of value.split(",").map((e) => e.trim())) {
    if (entry === "") emit(source, `${label} has an empty entry`);
    const named = `${label} entry ${JSON.stringify(entry)}`;
    const path = hostPath(entry);
    if (path === null) emit(source, `${named} is not an absolute path`);
    if (path.segments.includes("..")) emit(source, `${named} has a '..' segment`);
    if (path.segments.length === 0) emit(source, `${named} names a filesystem root`);
    for (const root of roots) {
      const lane = hostPath(root);
      if (lane?.anchor === path.anchor && lane.segments.every((s, n) => path.segments[n] === s)) {
        emit(source, `${named} is inside ${root}`);
      }
    }
    if (path.segments.some((s) => EPHEMERAL_SEGMENTS.has(s.toLowerCase()))) {
      emit(source, `${named} sits under an ephemeral base (tmp, temp, shm)`);
    }
  }
  return ["--credential-roots", value];
}

export function main({ platform = process.platform, ...judge } = {}) {
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

  const pluginRoot = resolve(dirname(realpathSync.native(fileURLToPath(import.meta.url))), "..", "..", "..");
  try {
    options = readOperatorOptions(resolveInstall(pluginRoot), managedSettingsFiles(), OPTION_KEYS);
  } catch (error) {
    if (!(error instanceof OptionsError)) throw error;
    emit(null, error.message);
  }
  source = options.promotion_evidence_source?.value || null;
  if (platform === "win32") emit(source, "writability-unverifiable-on-win32");

  const option = (key, roots) => {
    const real = resolveInput(key, options[key]?.value, roots);
    refuseLaneWritable(key, options[key].value, judge);
    refuseLaneWritable(options[key].file, options[key].file, judge);
    return real;
  };

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
    values["window-start"] === undefined ? checkedSource(sourcePath, judge) : restartedCopy(sourcePath, values["window-start"], roots, judge);
  const credentialSetting = options.promotion_evidence_credential_roots;
  if (credentialSetting) refuseLaneWritable(credentialSetting.file, credentialSetting.file, judge);
  const credentialRoots = credentialRootsArgs(credentialSetting?.value, roots);
  emitVerdict(runChecker(checker, [binding, "--evidence", evidence, "--probe-evidence-root", probeRoot, ...credentialRoots]));
}

function runChecker(checker, args) {
  const checkerEnv = Object.fromEntries(
    CHECKER_ENV_KEYS.filter((key) => key in process.env).map((key) => [key, process.env[key]]),
  );
  return spawnSync(process.execPath, [checker, ...args], {
    cwd: dirname(checker),
    env: checkerEnv,
    encoding: "utf8",
    shell: false,
    timeout: TIMEOUT_MS,
    maxBuffer: 16 * 1024 * 1024,
  });
}

function emitVerdict(run) {
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
}

function isEntry() {
  try {
    return realpathSync.native(process.argv[1]) === realpathSync.native(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}
if (isEntry()) main();
