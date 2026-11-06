// The transcript sink: its layout, the metrics row read from one transcript,
// retention, and queries. Nothing here reads a key or prints transcript text.
import { existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, renameSync, rmdirSync, rmSync, truncateSync, writeFileSync } from "node:fs";
import path from "node:path";

import { JOB_ID } from "../../.github/actions/seal-lane-output/seal.mjs";

const DAY = 24 * 60 * 60 * 1000;
export const TRANSCRIPT_DAYS = 30;
export const METRICS_DAYS = 365;
export const CAP_BYTES = 5_000_000_000;
export const STALE_DAYS = 5;

export const ARTIFACT = /^lane-transcript-(.+)-([1-9][0-9]{0,4})$/;
const DATE = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
const SEGMENT = /^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/;

// `lane-transcript-<job-id>-<attempt>`, as upload-lane-transcript names it.
export function parseArtifactName(name) {
  const match = ARTIFACT.exec(String(name));
  if (!match || !JOB_ID.test(match[1])) return null;
  return { jobId: match[1], attempt: Number(match[2]) };
}

// The lane is the workflow file's stem: `.github/workflows/pr-verify.yml` is `pr-verify`.
export function laneOf(workflowPath) {
  const stem = path.basename(String(workflowPath ?? "")).replace(/\.ya?ml$/, "");
  return SEGMENT.test(stem) ? stem : "unknown";
}

const count = (value) => (Number.isInteger(value) && value >= 0 ? value : null);

// The metrics a transcript carries, from the CLI's messages: the init message's
// model, and the last result message's subtype, models and usage. A result with
// is_error true is an `error` outcome whatever its subtype says.
export function transcriptMetrics(messages) {
  if (!Array.isArray(messages)) return { model: null, models: [], outcome: "unreadable", subtype: null, is_error: null, api_error_status: null, num_turns: null, duration_ms: null, input_tokens: null, output_tokens: null };
  const init = messages.find((m) => m?.type === "system" && m?.subtype === "init");
  const result = messages.findLast((m) => m?.type === "result") ?? null;
  const usage = result?.usage ?? {};
  const modelUsage = result?.modelUsage && typeof result.modelUsage === "object" ? result.modelUsage : {};
  const subtype = typeof result?.subtype === "string" ? result.subtype : null;
  return {
    model: typeof init?.model === "string" ? init.model : null,
    models: Object.keys(modelUsage).sort(),
    outcome: result?.is_error === true ? "error" : (subtype ?? "no-result"),
    subtype,
    is_error: typeof result?.is_error === "boolean" ? result.is_error : null,
    api_error_status: count(result?.api_error_status),
    num_turns: count(result?.num_turns),
    duration_ms: count(result?.duration_ms),
    input_tokens: count(usage.input_tokens),
    output_tokens: count(usage.output_tokens),
  };
}

export const paths = (sink) => ({
  metrics: path.join(sink, "metrics.jsonl"),
  state: path.join(sink, "state.json"),
  transcripts: path.join(sink, "transcripts"),
  tmp: path.join(sink, ".tmp"),
});

export function ensureDir(dir) {
  mkdirSync(dir, { recursive: true, mode: 0o700 });
}

// The stored file's path relative to the sink.
export function transcriptPath({ date, lane, run_id: runId, run_attempt: attempt, job_id: jobId }) {
  if (!DATE.test(date) || !SEGMENT.test(lane) || !JOB_ID.test(jobId)) throw new Error("bad-input: the row does not name a storable transcript");
  return path.join("transcripts", date, lane, `${runId}-${attempt}-${jobId}.json.gz`);
}

// The rows every complete line holds. An append cut short (a full disk, a
// kill) leaves a last line with no newline: it is not a row, so its artifact
// is pulled again and the next append replaces it.
const completeText = (text) => text.slice(0, text.lastIndexOf("\n") + 1);

export function readRows(sink) {
  const file = paths(sink).metrics;
  if (!existsSync(file)) return [];
  return completeText(readFileSync(file, "utf8")).split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

function writeAtomic(file, text) {
  const next = `${file}.next`;
  writeFileSync(next, text, { mode: 0o600 });
  renameSync(next, file);
}

export const writeRows = (sink, rows) => writeAtomic(paths(sink).metrics, rows.map((row) => `${JSON.stringify(row)}\n`).join(""));

export function appendRow(sink, row) {
  const file = paths(sink).metrics;
  if (existsSync(file)) {
    const text = readFileSync(file, "utf8");
    if (!text.endsWith("\n") && text !== "") truncateSync(file, Buffer.byteLength(completeText(text)));
  }
  writeFileSync(paths(sink).metrics, `${JSON.stringify(row)}\n`, { flag: "a", mode: 0o600 });
}

export function readState(sink) {
  try {
    return JSON.parse(readFileSync(paths(sink).state, "utf8"));
  } catch {
    return {};
  }
}

export const writeState = (sink, state) => writeAtomic(paths(sink).state, `${JSON.stringify(state, null, 2)}\n`);

// Every regular file under dir, with its size and modification time.
function files(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true, recursive: true })) {
    if (!entry.isFile()) continue;
    const file = path.join(entry.parentPath, entry.name);
    const stat = lstatSync(file);
    out.push({ file, size: stat.size, mtimeMs: stat.mtimeMs });
  }
  return out;
}

export const sinkBytes = (sink) => files(sink).reduce((sum, f) => sum + f.size, 0);

function removeEmptyDirs(dir) {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const sub = path.join(dir, entry.name);
    removeEmptyDirs(sub);
    if (readdirSync(sub).length === 0) rmdirSync(sub);
  }
}

// Transcripts over 30 days go, then metrics rows over a year, then the oldest
// transcripts until every file under the sink fits in 5 GB. A file no row
// names ages by its modification time.
export function prune(sink, now = Date.now(), { capBytes = CAP_BYTES } = {}) {
  const rows = readRows(sink);
  const byPath = new Map(rows.filter((r) => r.transcript).map((r) => [path.join(sink, r.transcript), r]));
  const stored = files(paths(sink).transcripts).map((f) => ({ ...f, row: byPath.get(f.file), at: byPath.has(f.file) ? Date.parse(byPath.get(f.file).created_at) : f.mtimeMs }));
  const removed = { age: 0, cap: 0, rows: 0 };
  const drop = (entry, reason) => {
    rmSync(entry.file, { force: true });
    entry.gone = true;
    removed[reason]++;
    if (entry.row) Object.assign(entry.row, { transcript: null, pruned: reason });
  };
  for (const entry of stored) if (now - entry.at > TRANSCRIPT_DAYS * DAY) drop(entry, "age");
  // A row whose file is gone keeps its metrics but no path.
  for (const row of rows) if (row.transcript && !existsSync(path.join(sink, row.transcript))) Object.assign(row, { transcript: null, pruned: row.pruned ?? "missing" });
  const kept = rows.filter((row) => now - Date.parse(row.created_at) <= METRICS_DAYS * DAY);
  removed.rows = rows.length - kept.length;
  writeRows(sink, kept);
  let total = sinkBytes(sink);
  for (const entry of stored.filter((e) => !e.gone).sort((a, b) => a.at - b.at)) {
    if (total <= capBytes) break;
    drop(entry, "cap");
    total -= entry.size;
  }
  if (removed.cap > 0) writeRows(sink, kept);
  removeEmptyDirs(paths(sink).transcripts);
  return { ...removed, bytes: sinkBytes(sink) };
}

// A row is `error` when is_error is true, whatever an older row stored as its
// outcome. Its subtype still matches, except `success`, which an errored leg is
// not. An older row has no subtype field: its outcome is the subtype.
function hasOutcome(row, outcome) {
  if (row.is_error !== true) return row.outcome === outcome;
  return outcome === "error" || (outcome !== "success" && (row.subtype ?? row.outcome) === outcome);
}

// Rows matching every filter given: lane (or `lane/job-id`), model (any model
// the run used, as a substring), outcome, and a date range on the run's date.
export function query(rows, { lane, model, outcome, since, until } = {}) {
  for (const date of [since, until]) if (date !== undefined && !DATE.test(date)) throw new Error("bad-input: --since and --until take YYYY-MM-DD");
  return rows.filter(
    (row) =>
      (lane === undefined || row.lane === lane || `${row.lane}/${row.job_id}` === lane) &&
      (model === undefined || [row.model, ...(row.models ?? [])].some((m) => typeof m === "string" && m.includes(model))) &&
      (outcome === undefined || hasOutcome(row, outcome)) &&
      (since === undefined || row.date >= since) &&
      (until === undefined || row.date <= until),
  );
}

// The last successful pull, and whether it is more than 5 days old (or never
// happened), or a budget-stopped backlog's kept cutoff is.
export function staleness(state, now = Date.now()) {
  const days = (at) => {
    const ms = Date.parse(at ?? "");
    return Number.isNaN(ms) ? null : (now - ms) / DAY;
  };
  const round = (d) => (d === null ? null : Math.round(d * 10) / 10);
  const ageDays = days(state.last_success_at);
  const backlogDays = days(state.resume_cutoff_at);
  const backlogStale = backlogDays !== null && backlogDays > STALE_DAYS;
  return { last_success_at: state.last_success_at ?? null, age_days: round(ageDays), backlog_age_days: round(backlogDays), backlog_stale: backlogStale, stale: ageDays === null || ageDays > STALE_DAYS || backlogStale };
}
