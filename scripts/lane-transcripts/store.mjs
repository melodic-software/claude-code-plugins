// The transcript sink: its layout, the metrics row read from one transcript,
// retention, and queries. Nothing here reads a key or prints transcript text.
import { createHash } from "node:crypto";
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
const amount = (value) => (typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null);
const asString = (value) => (typeof value === "string" ? value : null);
export const OMITTED_REASONS = ["too-large", "credential"];

/**
 * The trace id every lane-outcome record of one run attempt carries, so a row joins its records
 * and spans: https://github.com/melodic-software/ci-workflows/blob/main/docs/lane-outcome.md#run-context
 */
export function traceIdOf(runId, attempt) {
  if (!Number.isSafeInteger(runId) || runId < 1 || !Number.isSafeInteger(attempt) || attempt < 1) return null;
  return createHash("sha256").update(`lane-outcome:${runId}:${attempt}`).digest("hex").slice(0, 32);
}

const modelShare = (u) => ({
  input_tokens: count(u?.inputTokens),
  output_tokens: count(u?.outputTokens),
  cache_read_input_tokens: count(u?.cacheReadInputTokens),
  cache_creation_input_tokens: count(u?.cacheCreationInputTokens),
  cost_usd: amount(u?.costUSD),
});

/**
 * The metrics a transcript carries, from the CLI's messages: the init message's
 * model, and the last result message's subtype, models and usage. A result with
 * is_error true is an `error` outcome whatever its subtype says. The token
 * counts are the top-level loop's (`usage`); total_cost_usd and model_usage
 * also count subagents. total_cost_usd is the CLI's own estimate, not a bill.
 */
export function transcriptMetrics(messages) {
  const empty = {
    model: null,
    models: [],
    subtype: null,
    is_error: null,
    api_error_status: null,
    num_turns: null,
    duration_ms: null,
    input_tokens: null,
    output_tokens: null,
    cache_read_input_tokens: null,
    cache_creation_input_tokens: null,
    total_cost_usd: null,
    model_usage: null,
  };
  if (!Array.isArray(messages)) return { ...empty, outcome: "unreadable" };
  const [marker] = messages;
  if (messages.length === 1 && marker?.type === "system" && marker?.subtype === "transcript_omitted") {
    return { ...empty, outcome: "omitted", omitted_reason: OMITTED_REASONS.includes(marker.reason) ? marker.reason : "unknown", omitted_bytes: count(marker.bytes) };
  }
  const init = messages.find((m) => m?.type === "system" && m?.subtype === "init");
  const result = messages.findLast((m) => m?.type === "result") ?? null;
  const usage = result?.usage ?? {};
  const modelUsage = result?.modelUsage && typeof result.modelUsage === "object" ? result.modelUsage : {};
  const subtype = asString(result?.subtype);
  return {
    model: asString(init?.model),
    models: Object.keys(modelUsage).sort(),
    outcome: result?.is_error === true ? "error" : (subtype ?? "no-result"),
    subtype,
    is_error: typeof result?.is_error === "boolean" ? result.is_error : null,
    api_error_status: count(result?.api_error_status),
    num_turns: count(result?.num_turns),
    duration_ms: count(result?.duration_ms),
    input_tokens: count(usage.input_tokens),
    output_tokens: count(usage.output_tokens),
    cache_read_input_tokens: count(usage.cache_read_input_tokens),
    cache_creation_input_tokens: count(usage.cache_creation_input_tokens),
    total_cost_usd: amount(result?.total_cost_usd),
    model_usage: result ? Object.fromEntries(Object.keys(modelUsage).sort().map((name) => [name, modelShare(modelUsage[name])])) : null,
  };
}

export const paths = (sink) => ({
  metrics: path.join(sink, "metrics.jsonl"),
  outcomes: path.join(sink, "outcomes.jsonl"),
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

export const telemetryPath = (row) => transcriptPath(row).replace(/\.json\.gz$/, ".otel.jsonl.gz");

export function telemetrySpans(text, traceId) {
  let spans = 0;
  let joined = 0;
  for (const line of text.split("\n")) {
    let request;
    try {
      request = JSON.parse(line);
    } catch {
      continue;
    }
    for (const resource of Array.isArray(request?.resourceSpans) ? request.resourceSpans : []) {
      for (const scope of Array.isArray(resource?.scopeSpans) ? resource.scopeSpans : []) {
        for (const span of Array.isArray(scope?.spans) ? scope.spans : []) {
          spans++;
          if (typeof span?.traceId === "string" && span.traceId.toLowerCase() === traceId) joined++;
        }
      }
    }
  }
  return { telemetry_spans: spans, telemetry_joined_spans: joined };
}

// The rows every complete line holds. An append cut short (a full disk, a
// kill) leaves a last line with no newline: it is not a row, so its artifact
// is pulled again and the next append replaces it.
const completeText = (text) => text.slice(0, text.lastIndexOf("\n") + 1);

function readJsonl(file) {
  if (!existsSync(file)) return [];
  return completeText(readFileSync(file, "utf8")).split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

export const readRows = (sink) => readJsonl(paths(sink).metrics);
export const readOutcomes = (sink) => readJsonl(paths(sink).outcomes);

function writeAtomic(file, text) {
  const next = `${file}.next`;
  writeFileSync(next, text, { mode: 0o600 });
  renameSync(next, file);
}

const jsonl = (rows) => rows.map((row) => `${JSON.stringify(row)}\n`).join("");
export const writeRows = (sink, rows) => writeAtomic(paths(sink).metrics, jsonl(rows));
export const writeOutcomes = (sink, rows) => writeAtomic(paths(sink).outcomes, jsonl(rows));

function appendJsonl(file, row) {
  if (existsSync(file)) {
    const text = readFileSync(file, "utf8");
    if (!text.endsWith("\n") && text !== "") truncateSync(file, Buffer.byteLength(completeText(text)));
  }
  writeFileSync(file, `${JSON.stringify(row)}\n`, { flag: "a", mode: 0o600 });
}

export const appendRow = (sink, row) => appendJsonl(paths(sink).metrics, row);
export const appendOutcome = (sink, row) => appendJsonl(paths(sink).outcomes, row);

/**
 * A row's failure class from the lane-outcome records of its run attempt: set
 * only when every record of that attempt names the same class (a success
 * record names none), since a record names its lane and credential but not the
 * leg's upload job-id. `failure_class_source` says which case held:
 * `lane-outcome` (the records agree; the class is null when all succeeded),
 * `disagree` (they differ, so the class is null) or `none` (no record held).
 */
export function failureClassOf(traceId, outcomesByTrace) {
  const records = outcomesByTrace.get(traceId) ?? [];
  if (records.length === 0) return { failure_class: null, failure_class_source: "none" };
  const classes = new Set(records.map((o) => o.record?.class ?? null));
  if (classes.size > 1) return { failure_class: null, failure_class_source: "disagree" };
  return { failure_class: [...classes][0], failure_class_source: "lane-outcome" };
}

export function outcomesByTrace(outcomes) {
  const byTrace = new Map();
  for (const outcome of outcomes) {
    if (!byTrace.has(outcome.trace_id)) byTrace.set(outcome.trace_id, []);
    byTrace.get(outcome.trace_id).push(outcome);
  }
  return byTrace;
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

/**
 * Transcripts over 30 days go, then metrics and outcome rows over a year, then
 * the oldest transcripts until every file under the sink fits in 5 GB. A file
 * no row names ages by its modification time.
 */
export function prune(sink, now = Date.now(), { capBytes = CAP_BYTES } = {}) {
  const outcomes = readOutcomes(sink);
  const keptOutcomes = outcomes.filter((o) => now - Date.parse(o.created_at) <= METRICS_DAYS * DAY);
  if (keptOutcomes.length < outcomes.length) writeOutcomes(sink, keptOutcomes);
  const rows = readRows(sink);
  const byPath = new Map(rows.flatMap((row) => ["transcript", "telemetry"].filter((field) => row[field]).map((field) => [path.join(sink, row[field]), { row, field }])));
  const stored = files(paths(sink).transcripts).map((f) => {
    const { row, field } = byPath.get(f.file) ?? {};
    return { ...f, row, field, at: row ? Date.parse(row.created_at) : f.mtimeMs };
  });
  const removed = { age: 0, cap: 0, rows: 0, outcomes: outcomes.length - keptOutcomes.length };
  const drop = (entry, reason) => {
    rmSync(entry.file, { force: true });
    entry.gone = true;
    removed[reason]++;
    if (entry.field === "transcript") Object.assign(entry.row, { transcript: null, pruned: reason });
    else if (entry.field === "telemetry") entry.row.telemetry = null;
  };
  for (const entry of stored) if (now - entry.at > TRANSCRIPT_DAYS * DAY) drop(entry, "age");
  // A row whose file is gone keeps its metrics but no path.
  for (const row of rows) {
    if (row.transcript && !existsSync(path.join(sink, row.transcript))) Object.assign(row, { transcript: null, pruned: row.pruned ?? "missing" });
    if (row.telemetry && !existsSync(path.join(sink, row.telemetry))) row.telemetry = null;
  }
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

/**
 * Rows matching every filter given: lane (or `lane/job-id`), model (any model
 * the run used, as a substring), outcome, failure class, trace id, and a date
 * range on the run's date.
 */
export function query(rows, { lane, model, outcome, class: failureClass, trace, since, until } = {}) {
  for (const date of [since, until]) if (date !== undefined && !DATE.test(date)) throw new Error("bad-input: --since and --until take YYYY-MM-DD");
  return rows.filter(
    (row) =>
      (lane === undefined || row.lane === lane || `${row.lane}/${row.job_id}` === lane) &&
      (model === undefined || [row.model, ...(row.models ?? [])].some((m) => typeof m === "string" && m.includes(model))) &&
      (outcome === undefined || hasOutcome(row, outcome)) &&
      (failureClass === undefined || row.failure_class === failureClass) &&
      (trace === undefined || row.trace_id === trace) &&
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
