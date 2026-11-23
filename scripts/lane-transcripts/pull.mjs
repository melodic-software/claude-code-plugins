// The lane transcript puller: copies each sealed lane-transcript artifact to
// the sink, opened with the private key, and keeps the sink's retention.
// README.md has the commands, the layout and the key setup.
//
// The private key comes only from LANE_TRANSCRIPT_PRIVATE_KEY, which vault-exec
// sets; it is read once and removed from the environment before any child
// process starts. Transcript text reaches only the sink's files: nothing here
// prints it, and an error names a kind, never a value.
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

import { OpenError, openRecord, parsePrivateKey } from "../../.github/actions/open-lane-output/open.mjs";
import {
  appendOutcome,
  appendRow,
  ensureDir,
  failureClassOf,
  laneOf,
  outcomesByTrace,
  parseArtifactName,
  paths,
  prune,
  query,
  readOutcomes,
  readRows,
  readState,
  sinkBytes,
  staleness,
  telemetryPath,
  telemetrySpans,
  traceIdOf,
  transcriptMetrics,
  transcriptPath,
  writeOutcomes,
  writeRows,
  writeState,
} from "./store.mjs";

export const REPO = "melodic-software/claude-code-plugins";
export const PAYLOAD = "transcript.json.gz";
export const ENTRY = `${PAYLOAD}.sealed`;
export const TELEMETRY_PAYLOAD = "otel.jsonl.gz";
export const TELEMETRY_ENTRY = `${TELEMETRY_PAYLOAD}.sealed`;
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const ARTIFACT_DAYS = 7;
const OVERLAP = 6 * HOUR;
const PER_PAGE = 100;
const MAX_SEALED = 64 * 1024 * 1024;
const MAX_PLAIN = 256 * 1024 * 1024;
const MAX_TELEMETRY_PLAIN = 64 * 1024 * 1024;
const UNEXTRACTED = Symbol("unextracted");
export const GH_ATTEMPTS = 5;
export const GH_LIST_ATTEMPTS = 10;
export const GH_DELAY_MS = 2000;
export const GH_MAX_DELAY_MS = 300_000;
// gh calls one pull may make, every retry counted: a fifth of the login's
// 5,000 REST requests an hour, so the other lanes on it keep their headroom.
export const GH_CALL_BUDGET = 1000;

// GitHub answers the repository-wide artifact listing with a 500 for this
// repository, so the pull lists each artifact name on its own instead. A name
// is lane-transcript-<job-id>-<run attempt> (upload-lane-transcript), so these
// are every job-id an upload step passes, by workflow file; a ci-workflows/
// key is a reusable workflow this repository calls with the transcript key.
const LEGS = ["", "-subscription", "-fallback"];
const legs = (job, suffixes = [""]) => LEGS.flatMap((leg) => suffixes.map((suffix) => `${job}${leg}${suffix}`));
const AUDIT_UNITS = ["a", "c", "d"].flatMap((group) => [1, 2, 3, 4, 5, 6, 7, 8].map((n) => `-${group}${n}`));
const VERIFY_LEGS = ["", ...Array.from({ length: 11 }, (_, i) => `-${i + 2}`), "-spec"];
const CHUNKS = ["", "-2", "-3", "-4"];
const REVIEW_CHUNKS = ["claude-review", "claude-security-review"].flatMap((lane) => CHUNKS.map((chunk) => `-${lane}${chunk}`));
export const TRANSCRIPT_JOB_IDS = {
  "intake-triage.yml": legs("refine-issue"),
  "maintenance-audit-lane-runs.yml": legs("assess-units", AUDIT_UNITS),
  "maintenance-measure-skill-edit.yml": ["generate-edit-key", "generate-edit", "generate-edit-fallback"],
  "maintenance-tidy-code-upkeep.yml": legs("sweep-areas"),
  "post-merge-test-mutation.yml": [...legs("generate"), ...legs("triage")],
  "pr-review-main.yml": legs("review", REVIEW_CHUNKS),
  "pr-run-activity-read.yml": [
    ...legs("reuse-summary"),
    ...["fix-docs", "resolve-issue", "resolve-conflicts", "review-dependency"].flatMap((activity) => legs(activity)),
    ...["address-feedback", "fix-ci"].flatMap((activity) => legs(activity, ["", "-rung-up"])),
  ],
  "pr-unblock.yml": ["0", "1", "2"].flatMap((n) => legs(`adjudicate-feedback-${n}`)),
  "pr-verify.yml": legs("check-intent", VERIFY_LEGS),
  "pr-rate-merge-risk.yml": legs("rate-merge-risk"),
  "upstream-apply-changelog.yml": [...legs("apply-changelog"), ...legs("verify-env-scrub")],
  // job-id `${{ inputs.lane }}-${{ github.job }}` and chunks -2 to -4.
  "ci-workflows/pr-review-cli.yml": ["code", "security"].flatMap((lane) => ["review-key", "review-subscription", "review-fallback"].flatMap((job) => CHUNKS.map((chunk) => `${lane}-${job}${chunk}`))),
  // job-id `intake-${{ github.job }}`.
  // The legs' job ids are triage-subscription and triage-fallback; runs from
  // before that rename uploaded the two shorter names.
  "ci-workflows/intake-triage.yml": ["intake-claude", "intake-triage-subscription", "intake-triage-fallback", "intake-subscription", "intake-fallback"],
};
// A re-run uploads under its own attempt number; attempts past 3 are not read.
export const ATTEMPTS = 3;
export const TRANSCRIPT_NAMES = [...new Set(Object.values(TRANSCRIPT_JOB_IDS).flatMap((ids) => ids.flatMap((id) => Array.from({ length: ATTEMPTS }, (_, i) => `lane-transcript-${id}-${i + 1}`))))];

/**
 * A reusable has no runs of its own: its uploads ride on its callers' runs.
 * pull-listing.test.mjs reads the workflows and fails when a caller is missing here.
 */
export const TRANSCRIPT_CALLERS = {
  "pr-run-activity-read.yml": ["pr-refine.yml", "pr-unblock.yml", "work-resolve-issue.yml"],
  "ci-workflows/pr-review-cli.yml": ["pr-review-hosted.yml", "pr-review-security-hosted.yml"],
  "ci-workflows/intake-triage.yml": ["intake-triage.yml"],
};
const runWorkflowsOf = (key) => TRANSCRIPT_CALLERS[key] ?? [key];
/** The workflows whose runs upload transcripts: the pull lists each one's newest runs. */
export const RUN_WORKFLOWS = [...new Set(Object.keys(TRANSCRIPT_JOB_IDS).flatMap(runWorkflowsOf))];
const SOURCES = new Map();
for (const [key, ids] of Object.entries(TRANSCRIPT_JOB_IDS)) {
  for (const id of ids) {
    for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
      const name = `lane-transcript-${id}-${attempt}`;
      if (!SOURCES.has(name)) SOURCES.set(name, { attempt, workflows: new Set() });
      for (const workflow of runWorkflowsOf(key)) SOURCES.get(name).workflows.add(workflow);
    }
  }
}

/**
 * The workflows whose runs write lane-outcome records: each runs
 * report-lane-outcome or run-claude-cli, a ci-workflows lane reusable, or a
 * local reusable that does. pull.test.mjs reads the workflows and fails when
 * this list and theirs differ. A reusable has no runs of its own, so only its
 * callers are here.
 */
export const LANE_WORKFLOWS = [
  "intake-triage.yml",
  "maintenance-audit-lane-runs.yml",
  "maintenance-measure-skill-edit.yml",
  "maintenance-tidy-code-upkeep.yml",
  "post-merge-test-mutation.yml",
  "pr-rate-merge-risk.yml",
  "pr-refine.yml",
  "pr-review-hosted.yml",
  "pr-review-main.yml",
  "pr-review-security-hosted.yml",
  "pr-run-plugin-evals.yml",
  "pr-unblock.yml",
  "pr-verify.yml",
  "upstream-apply-changelog.yml",
  "work-resolve-issue.yml",
];
/**
 * pull-outcomes' own gh call budget, apart from the transcript pull's, and how
 * far back its first run lists.
 */
export const OUTCOME_CALL_BUDGET = 1000;
const OUTCOME_FIRST_DAYS = 30;

const COMMANDS = ["pull", "pull-outcomes", "backfill", "status", "query", "prune"];
const USAGE = `usage: pull.mjs <${COMMANDS.join("|")}> [--sink DIR] [--repo OWNER/REPO]
  pull: [--run RUN-ID] pulls only that workflow run's transcripts and leaves the pull's cursors as they are
  query filters: [--lane LANE[/JOB]] [--model TEXT] [--outcome OUTCOME] [--class FAILURE-CLASS] [--trace TRACE-ID] [--since YYYY-MM-DD] [--until YYYY-MM-DD]`;

export class UsageError extends Error {}
// A failed pull whose message names a kind and a count, never a value.
export class PullError extends Error {}
// One artifact's call that still failed: the pull counts it and goes on. Its
// message is the call's kind, so the failed call's own text goes no further.
class FetchFailed extends Error {}
// The pull's gh call budget is spent: it stops fetching and keeps what it has.
class BudgetSpent extends Error {}

export function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (!COMMANDS.includes(command)) throw new UsageError(USAGE);
  const flags = {};
  const names = new Set(["sink", "repo", "run", "lane", "model", "outcome", "class", "trace", "since", "until"]);
  for (let i = 0; i < rest.length; i += 2) {
    const name = /^--([a-z]+)$/.exec(rest[i])?.[1];
    if (!names.has(name) || rest[i + 1] === undefined || name in flags) throw new UsageError(USAGE);
    flags[name] = rest[i + 1];
  }
  if ("run" in flags && (command !== "pull" || !/^[1-9]\d*$/.test(flags.run))) throw new UsageError(USAGE);
  return { command, flags };
}

// The one sink value: --sink, else LANE_TRANSCRIPT_SINK, else under XDG_DATA_HOME.
export function sinkOf(flags, env) {
  const sink = flags.sink ?? env.LANE_TRANSCRIPT_SINK ?? path.join(env.XDG_DATA_HOME || path.join(env.HOME ?? os.homedir(), ".local", "share"), "lane-transcripts");
  if (!path.isAbsolute(sink)) throw new UsageError("the sink must be an absolute directory path");
  return sink;
}

const json = (buffer) => JSON.parse(buffer.toString("utf8"));

function defaultDeps(env) {
  const run = (cmd) => (args) => execFileSync(cmd, args, { env, maxBuffer: MAX_SEALED * 2, stdio: ["ignore", "pipe", "pipe"] });
  return { gh: run("gh"), unzip: run("unzip"), now: () => Date.now(), sleep: (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms) };
}

// GitHub answers these calls with a passing 5xx, on some days for most calls
// to the artifact listing at any page. A listing page the pull cannot skip
// gets ten tries, the wait doubling up to 5 min (about 13.5 min in all), so it
// rides out a bad spell of several minutes. A zip or run read, whose failure
// the pull already tolerates (fetch_failed), keeps five tries (about 30 s). A
// rate limit stops the pull at once: every further call while limited spends
// the user's shared budget. Every attempt counts against the pull's call budget.
function ghRetried(deps, args, list = false) {
  const attempts = deps.ghAttempts ?? (list ? GH_LIST_ATTEMPTS : GH_ATTEMPTS);
  for (let attempt = 1; ; attempt++) {
    if (deps.meter.calls >= deps.meter.budget) throw new BudgetSpent();
    deps.meter.calls++;
    try {
      return deps.gh(args);
    } catch (error) {
      if (/rate limit|HTTP 429/i.test(String(error?.stderr))) throw new PullError("rate-limited: gh reported a rate limit");
      if (attempt >= attempts) throw error;
      deps.sleep(Math.min(2 ** (attempt - 1) * (deps.ghDelayMs ?? GH_DELAY_MS), GH_MAX_DELAY_MS));
    }
  }
}

function fetched(kind, call) {
  try {
    return call();
  } catch (error) {
    throw error instanceof PullError || error instanceof BudgetSpent ? error : new FetchFailed(kind);
  }
}

/**
 * A second sealed file the writer may add beside the transcript, such as the
 * leg's telemetry; the pull opens only the telemetry.
 */
const EXTRA_SEALED = /^[A-Za-z0-9][A-Za-z0-9._-]{0,99}\.sealed$/;

/**
 * The sealed records inside one artifact zip: the sealed transcript, and the
 * telemetry when it is the one other sealed file.
 */
function sealedRecords(deps, sink, zip) {
  const dir = mkdtempSync(path.join(paths(sink).tmp, "zip-"));
  try {
    const file = path.join(dir, "artifact.zip");
    writeFileSync(file, zip, { mode: 0o600 });
    const unzip = (args) => fetched("artifact-unzip", () => deps.unzip(args));
    const entries = unzip(["-Z1", file]).toString("utf8").split("\n").filter(Boolean);
    const extra = entries.filter((entry) => entry !== ENTRY);
    if (entries.length - extra.length !== 1 || extra.length > 1 || !extra.every((entry) => EXTRA_SEALED.test(entry))) return null;
    const transcript = unzip(["-p", file, ENTRY]);
    if (extra[0] !== TELEMETRY_ENTRY) return { transcript, telemetry: null };
    try {
      return { transcript, telemetry: deps.unzip(["-p", file, TELEMETRY_ENTRY]) };
    } catch {
      return { transcript, telemetry: UNEXTRACTED };
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/**
 * The newest page of runs of each workflow in RUN_WORKFLOWS, with no created
 * filter, so a re-run of an older run still shows: the highest attempt each
 * workflow reached, and the runs by id. A workflow whose listing fails counts
 * as re-run up to every attempt, so nothing is skipped.
 */
function recentRuns(deps, repo) {
  const attempts = new Map();
  const byId = new Map();
  for (const workflow of RUN_WORKFLOWS) {
    try {
      const { workflow_runs: runs = [] } = fetched("run-list", () => json(ghRetried(deps, ["api", `repos/${repo}/actions/workflows/${workflow}/runs?per_page=${PER_PAGE}`])));
      attempts.set(workflow, Math.max(1, ...runs.map((run) => (Number.isSafeInteger(run.run_attempt) ? run.run_attempt : 1))));
      for (const run of runs) if (run.id) byId.set(String(run.id), run);
    } catch (error) {
      if (!(error instanceof FetchFailed)) throw error;
      attempts.set(workflow, ATTEMPTS);
    }
  }
  return { attempts, byId };
}

function* listed(deps, repo, { due, cutoffOf, at, onListed }) {
  const start = Math.max(0, TRANSCRIPT_NAMES.indexOf(at.name));
  for (let i = 0; i < TRANSCRIPT_NAMES.length; i++) {
    const name = TRANSCRIPT_NAMES[(start + i) % TRANSCRIPT_NAMES.length];
    if (!due(name)) continue;
    at.name = name;
    const cutoff = cutoffOf(name);
    for (let page = 1; ; page++) {
      const { artifacts = [] } = json(ghRetried(deps, ["api", `repos/${repo}/actions/artifacts?name=${name}&per_page=${PER_PAGE}&page=${page}`], true));
      const fresh = artifacts.filter((artifact) => Date.parse(artifact.created_at) >= cutoff);
      yield* fresh;
      if (fresh.length < PER_PAGE) break;
    }
    onListed(name);
  }
}

export function pull({ sink, repo, recipient, deps, log }) {
  const meter = { calls: 0, budget: deps.ghCallBudget ?? GH_CALL_BUDGET };
  try {
    return pullWithin({ sink, repo, recipient, deps: { ...deps, meter }, log });
  } finally {
    log(`gh calls: ${meter.calls} of ${meter.budget}`);
  }
}

function pullWithin({ sink, repo, recipient, deps, log }) {
  const now = deps.now();
  for (const dir of [sink, paths(sink).transcripts, paths(sink).tmp]) ensureDir(dir);
  const state = readState(sink);
  const last = Date.parse(state.last_success_at ?? "");
  const resume = Date.parse(state.resume_cutoff_at ?? "");
  const since = Number.isNaN(resume) ? (Number.isNaN(last) ? 0 : last - OVERLAP) : resume;
  const floor = now - ARTIFACT_DAYS * DAY;
  const cursors = Object.fromEntries(TRANSCRIPT_NAMES.filter((name) => typeof state.cursors?.[name] === "string").map((name) => [name, state.cursors[name]]));
  const cutoffOf = (name) => {
    const cursor = Date.parse(cursors[name] ?? "");
    return Math.max(floor, Number.isNaN(cursor) ? since : cursor - OVERLAP);
  };
  const ctx = takeContext(sink, recipient, repo, deps, now);
  const { tally, failedKinds, failedNames } = ctx;
  let exhausted = false;
  const at = { name: state.resume_name ?? null };
  writeState(sink, { ...state, last_attempt_at: new Date(now).toISOString() });
  const dueWith = (attempts) => (name) => {
    const { attempt, workflows } = SOURCES.get(name);
    const listedAt = Date.parse(cursors[name] ?? "");
    return attempt === 1 || Number.isNaN(listedAt) || listedAt <= now - DAY || [...workflows].some((workflow) => attempts.get(workflow) >= attempt);
  };
  const onListed = (name) => {
    if (!failedNames.has(name)) cursors[name] = new Date(now).toISOString();
  };

  try {
    const recent = recentRuns(deps, repo);
    ctx.runs = recent.byId;
    for (const artifact of listed(deps, repo, { due: dueWith(recent.attempts), cutoffOf, at, onListed })) take(ctx, artifact);
  } catch (error) {
    if (!(error instanceof BudgetSpent)) throw error;
    exhausted = true;
  }
  failIfKeyMismatch(tally);
  const pruned = prune(sink, now);
  const finished = tally.fetch_failed > 0 ? { last_error: `fetch-failed: ${tally.fetch_failed} transcript(s) (${[...failedKinds].join(", ")})` } : { last_success_at: new Date(now).toISOString(), last_error: null, resume_cutoff_at: null };
  if (exhausted) finished.resume_cutoff_at = new Date(Math.min(...TRANSCRIPT_NAMES.map(cutoffOf))).toISOString();
  writeState(sink, { ...readState(sink), ...finished, cursors, last_tally: tally, budget_exhausted: exhausted, gh_calls: deps.meter.calls, resume_name: exhausted ? at.name : null });
  log(`pulled ${tally.pulled} transcript(s); skipped ${JSON.stringify(tally)}; pruned ${JSON.stringify(pruned)}${exhausted ? `; stopped at the gh call budget of ${deps.meter.budget}` : ""}`);
  return tally;
}

/** What taking an artifact reads and counts: the rows and outcomes held, the runs read, the tally. */
function takeContext(sink, recipient, repo, deps, now) {
  return {
    sink,
    repo,
    recipient,
    deps,
    now,
    known: new Set(readRows(sink).map((row) => row.artifact_id)),
    byTrace: outcomesByTrace(readOutcomes(sink)),
    runs: new Map(),
    tally: { pulled: 0, known: 0, fork: 0, expired: 0, unnamed: 0, too_large: 0, bad_zip: 0, sealed_mismatch: 0, fetch_failed: 0 },
    failedKinds: new Set(),
    failedNames: new Set(),
  };
}

/**
 * One listed artifact: skipped and counted, or stored. A fork's run is
 * skipped because the public key is public: it could seal a record of its own.
 */
function take(ctx, artifact) {
  const { tally, known } = ctx;
  const named = parseArtifactName(artifact.name);
  const wf = artifact.workflow_run ?? {};
  if (!named) tally.unnamed++;
  else if (known.has(artifact.id)) tally.known++;
  else if (artifact.expired) tally.expired++;
  else if (!wf.id || wf.head_repository_id !== wf.repository_id) tally.fork++;
  else if (artifact.size_in_bytes > MAX_SEALED) tally.too_large++;
  else {
    try {
      const outcome = store({ ...ctx, artifact, named });
      tally[outcome]++;
      if (outcome === "pulled") known.add(artifact.id);
    } catch (error) {
      if (!(error instanceof FetchFailed)) throw error;
      tally.fetch_failed++;
      ctx.failedKinds.add(error.message);
      ctx.failedNames.add(artifact.name);
    }
  }
}

/**
 * Every candidate sealed to another key and none opened: the vault key does
 * not match the repository variable, which must alert, not pass.
 */
function failIfKeyMismatch(tally) {
  if (tally.sealed_mismatch > 0 && tally.pulled === 0 && tally.known === 0) throw new PullError(`key-mismatch: ${tally.sealed_mismatch} transcript(s) did not open for this key and none did`);
}

/**
 * One workflow run's transcripts, listed from that run's own artifacts and
 * taken as a pull takes them. It writes no state and prunes nothing, so the
 * scheduled pull's cursors, resume point and last success stay as they were.
 */
export function pullRun({ sink, repo, recipient, deps, log, runId }) {
  const meter = { calls: 0, budget: deps.ghCallBudget ?? GH_CALL_BUDGET };
  try {
    return pullRunWithin({ sink, repo, recipient, deps: { ...deps, meter }, log, runId });
  } finally {
    log(`gh calls: ${meter.calls} of ${meter.budget}`);
  }
}

function pullRunWithin({ sink, repo, recipient, deps, log, runId }) {
  for (const dir of [sink, paths(sink).transcripts, paths(sink).tmp]) ensureDir(dir);
  const ctx = takeContext(sink, recipient, repo, deps, deps.now());
  try {
    for (let page = 1; ; page++) {
      const { artifacts = [] } = json(ghRetried(deps, ["api", `repos/${repo}/actions/runs/${runId}/artifacts?per_page=${PER_PAGE}&page=${page}`], true));
      for (const artifact of artifacts) if (String(artifact.name).startsWith("lane-transcript-")) take(ctx, artifact);
      if (artifacts.length < PER_PAGE) break;
    }
  } catch (error) {
    throw error instanceof BudgetSpent ? new PullError(`budget-spent: stopped at the gh call budget of ${deps.meter.budget}`) : error;
  }
  failIfKeyMismatch(ctx.tally);
  log(`pulled ${ctx.tally.pulled} transcript(s) from run ${runId}; skipped ${JSON.stringify(ctx.tally)}`);
  return ctx.tally;
}

function store({ sink, repo, recipient, deps, artifact, named, runs, byTrace, now }) {
  const runId = String(artifact.workflow_run.id);
  const records = sealedRecords(deps, sink, fetched("artifact-zip", () => ghRetried(deps, ["api", `repos/${repo}/actions/artifacts/${artifact.id}/zip`])));
  if (!records) return "bad_zip";
  let gz;
  try {
    gz = openRecord(recipient, [recipient.keyId], PAYLOAD, records.transcript, runId, named.jobId);
  } catch (error) {
    if (error instanceof OpenError) return "sealed_mismatch";
    throw error;
  }
  let messages = null;
  try {
    messages = JSON.parse(gunzipSync(gz, { maxOutputLength: MAX_PLAIN }).toString("utf8"));
  } catch {
    // An unreadable payload stays null: its row's outcome is `unreadable`.
  }
  if (!runs.has(runId)) runs.set(runId, fetched("run-read", () => json(ghRetried(deps, ["api", `repos/${repo}/actions/runs/${runId}`]))));
  const run = runs.get(runId);
  const asString = (value) => (typeof value === "string" ? value : null);
  const row = {
    provider: "github",
    run_ref: runId,
    run_url: `https://github.com/${repo}/actions/runs/${runId}/attempts/${named.attempt}`,
    leg_key: named.jobId,
    artifact_id: artifact.id,
    run_id: Number(runId),
    run_attempt: named.attempt,
    job_id: named.jobId,
    lane: laneOf(run.path),
    workflow: asString(run.name),
    event: asString(run.event),
    head_branch: asString(run.head_branch),
    run_conclusion: run.conclusion ?? run.status ?? null,
    created_at: artifact.created_at,
    date: artifact.created_at.slice(0, 10),
    ...transcriptMetrics(messages),
    trace_id: traceIdOf(Number(runId), named.attempt),
    transcript_bytes: gz.length,
    pulled_at: new Date(now).toISOString(),
  };
  Object.assign(row, failureClassOf(row.trace_id, byTrace, row.job_id));
  row.transcript = transcriptPath(row);
  const file = path.join(sink, row.transcript);
  ensureDir(path.dirname(file));
  writeFileSync(file, gz, { mode: 0o600 });
  const telemetry = openTelemetry(recipient, records.telemetry, runId, named.jobId, row.trace_id);
  Object.assign(row, telemetry.fields);
  if (telemetry.gz) {
    row.telemetry = telemetryPath(row);
    writeFileSync(path.join(sink, row.telemetry), telemetry.gz, { mode: 0o600 });
  }
  appendRow(sink, row);
  return "pulled";
}

const NO_TELEMETRY = { telemetry: null, telemetry_bytes: null, telemetry_spans: null, telemetry_joined_spans: null };

/**
 * The leg's telemetry, opened under its own payload name and the transcript's
 * run and job binding, and the row fields it gives. `telemetry_outcome` is
 * `none` (no file), `sealed_mismatch` (it did not open), `unreadable` (it
 * could not be extracted from the zip, or it opened but did not decompress
 * within its cap) or `stored`.
 */
function openTelemetry(recipient, record, runId, jobId, traceId) {
  if (!record) return { fields: { ...NO_TELEMETRY, telemetry_outcome: "none" } };
  if (record === UNEXTRACTED) return { fields: { ...NO_TELEMETRY, telemetry_outcome: "unreadable" } };
  let gz;
  try {
    gz = openRecord(recipient, [recipient.keyId], TELEMETRY_PAYLOAD, record, runId, jobId);
  } catch (error) {
    if (error instanceof OpenError) return { fields: { ...NO_TELEMETRY, telemetry_outcome: "sealed_mismatch" } };
    throw error;
  }
  try {
    const text = gunzipSync(gz, { maxOutputLength: MAX_TELEMETRY_PLAIN }).toString("utf8");
    return { gz, fields: { telemetry_bytes: gz.length, ...telemetrySpans(text, traceId), telemetry_outcome: "stored" } };
  } catch {
    return { fields: { ...NO_TELEMETRY, telemetry_outcome: "unreadable" } };
  }
}

/**
 * Each completed run of every lane workflow created since the cutoff, newest
 * first per workflow, starting at `at.workflow` (where a budget-stopped pull
 * stopped) and wrapping round.
 */
function* listedRuns(deps, repo, cutoff, at) {
  const created = encodeURIComponent(`>=${new Date(cutoff).toISOString()}`);
  const start = Math.max(0, LANE_WORKFLOWS.indexOf(at.workflow));
  for (let i = 0; i < LANE_WORKFLOWS.length; i++) {
    const workflow = LANE_WORKFLOWS[(start + i) % LANE_WORKFLOWS.length];
    at.workflow = workflow;
    for (let page = 1; ; page++) {
      const { workflow_runs: runs = [] } = json(ghRetried(deps, ["api", `repos/${repo}/actions/workflows/${workflow}/runs?created=${created}&status=completed&per_page=${PER_PAGE}&page=${page}`], true));
      yield* runs;
      if (runs.length < PER_PAGE) break;
    }
  }
}

function allPages(deps, kind, url, key) {
  const items = [];
  for (let page = 1; ; page++) {
    const body = fetched(kind, () => json(ghRetried(deps, ["api", `${url}${url.includes("?") ? "&" : "?"}per_page=${PER_PAGE}&page=${page}`])));
    const got = (key ? body?.[key] : body) ?? [];
    items.push(...got);
    if (got.length < PER_PAGE) return items;
  }
}

/**
 * One run's lane-outcome records, read from each job's check-run annotations
 * (report-lane-outcome writes one per credential attempt), one job at a time.
 * Each row names how many records its job holds, so heldOutcomes can drop a job
 * an interrupted pull left half written. A record whose own run id, attempt or
 * trace id names another run attempt is dropped. The record reader loads here, not at the top of
 * this file, so `pull` still runs from an export that holds only the files it needs.
 */
function copyRunOutcomes({ sink, repo, deps, run, known, tally }) {
  const { readRecord } = createRequire(import.meta.url)("../../.github/scripts/lib/lane-outcome.mjs");
  const jobs = allPages(deps, "jobs-read", `repos/${repo}/actions/runs/${run.id}/jobs?filter=all`, "jobs");
  for (const job of jobs) {
    if (known.has(job.id)) {
      tally.known_jobs++;
      continue;
    }
    if (job.conclusion === "skipped" || !job.completed_at || !Number.isSafeInteger(job.run_attempt)) continue;
    const traceId = traceIdOf(run.id, job.run_attempt);
    const annotations = allPages(deps, "annotations-read", `repos/${repo}/check-runs/${job.id}/annotations`, null);
    tally.jobs++;
    const rows = [];
    for (const annotation of annotations) {
      const record = readRecord(annotation?.message);
      if (!record) continue;
      if ((record.runId ?? run.id) !== run.id || (record.runAttempt ?? job.run_attempt) !== job.run_attempt || (record.traceId ?? traceId) !== traceId) {
        tally.mismatched++;
        continue;
      }
      rows.push({
        run_id: run.id,
        run_attempt: job.run_attempt,
        trace_id: traceId,
        check_run_id: job.id,
        job_name: typeof job.name === "string" ? job.name : null,
        lane: laneOf(run.path),
        workflow: typeof run.name === "string" ? run.name : null,
        created_at: job.completed_at,
        date: job.completed_at.slice(0, 10),
        record,
      });
    }
    for (const row of rows) {
      appendOutcome(sink, { ...row, job_records: rows.length });
      known.add(job.id);
      tally.records++;
    }
  }
}

/** The outcome rows held, first removing any job that has fewer rows than its `job_records`. */
function heldOutcomes(sink) {
  const held = readOutcomes(sink);
  const perJob = new Map();
  for (const { check_run_id: id } of held) perJob.set(id, (perJob.get(id) ?? 0) + 1);
  const whole = held.filter((o) => o.job_records === perJob.get(o.check_run_id));
  if (whole.length < held.length) writeOutcomes(sink, whole);
  return whole;
}

/**
 * Rewrites the metrics rows through `fill`, which sets fields on one row, and
 * each row's trace_id and failure class from the outcomes held. The file is
 * written only when a row changed; returns how many did.
 */
function refreshRows(sink, fill = () => {}) {
  const rows = readRows(sink);
  const byTrace = outcomesByTrace(readOutcomes(sink));
  let changed = 0;
  for (const row of rows) {
    const before = JSON.stringify(row);
    fill(row);
    row.trace_id = traceIdOf(row.run_id, row.run_attempt);
    Object.assign(row, failureClassOf(row.trace_id, byTrace, row.job_id));
    if (JSON.stringify(row) !== before) changed++;
  }
  if (changed > 0) writeRows(sink, rows);
  return changed;
}

export function pullOutcomes({ sink, repo, deps, log }) {
  const meter = { calls: 0, budget: deps.outcomeCallBudget ?? OUTCOME_CALL_BUDGET };
  try {
    return pullOutcomesWithin({ sink, repo, deps: { ...deps, meter }, log });
  } finally {
    log(`gh calls: ${meter.calls} of ${meter.budget}`);
  }
}

/**
 * The same cutoff, overlap, budget and resume rules as the transcript pull,
 * kept under the state's `outcomes` key. A run's fork check matches the
 * transcript pull's: a fork's run can write any annotation.
 */
function pullOutcomesWithin({ sink, repo, deps, log }) {
  const now = deps.now();
  ensureDir(sink);
  const state = readState(sink);
  const own = state.outcomes ?? {};
  const last = Date.parse(own.last_success_at ?? "");
  const resume = Date.parse(own.resume_cutoff_at ?? "");
  const cutoff = Number.isNaN(resume) ? (Number.isNaN(last) ? now - OUTCOME_FIRST_DAYS * 24 * HOUR : last - OVERLAP) : resume;
  const known = new Set(heldOutcomes(sink).map((o) => o.check_run_id));
  const read = { ...own.read_runs };
  const tally = { runs: 0, read_runs: 0, fork: 0, jobs: 0, known_jobs: 0, records: 0, mismatched: 0, fetch_failed: 0 };
  const failedKinds = new Set();
  const at = { workflow: own.resume_workflow ?? null };
  let exhausted = false;
  writeState(sink, { ...state, outcomes: { ...own, last_attempt_at: new Date(now).toISOString() } });
  try {
    for (const run of listedRuns(deps, repo, cutoff, at)) {
      if (!run.id || run.head_repository?.id !== run.repository?.id) {
        tally.fork++;
        continue;
      }
      const key = `${run.id}:${run.run_attempt}`;
      if (key in read) {
        tally.read_runs++;
        continue;
      }
      tally.runs++;
      try {
        copyRunOutcomes({ sink, repo, deps, run, known, tally });
        read[key] = run.created_at;
      } catch (error) {
        if (!(error instanceof FetchFailed)) throw error;
        tally.fetch_failed++;
        failedKinds.add(error.message);
      }
    }
  } catch (error) {
    if (!(error instanceof BudgetSpent)) throw error;
    exhausted = true;
  }
  const joined = refreshRows(sink);
  const finished = tally.fetch_failed > 0 ? { last_error: `fetch-failed: ${tally.fetch_failed} run(s) (${[...failedKinds].join(", ")})` } : { last_success_at: new Date(now).toISOString(), last_error: null, resume_cutoff_at: null };
  if (exhausted) finished.resume_cutoff_at = new Date(cutoff).toISOString();
  const nextCutoff = exhausted || tally.fetch_failed > 0 ? cutoff : now - OVERLAP;
  const readRuns = Object.fromEntries(Object.entries(read).filter(([, created]) => Date.parse(created) >= nextCutoff));
  const current = readState(sink);
  writeState(sink, { ...current, outcomes: { ...current.outcomes, ...finished, last_tally: tally, budget_exhausted: exhausted, gh_calls: deps.meter.calls, resume_workflow: exhausted ? at.workflow : null, read_runs: readRuns } });
  log(`copied ${tally.records} lane-outcome record(s); ${JSON.stringify(tally)}; ${joined} row(s) joined${exhausted ? `; stopped at the gh call budget of ${deps.meter.budget}` : ""}`);
  return tally;
}

/**
 * Fills what an older row lacks: trace_id, the failure class from the outcomes
 * held, and the cache, cost and model_usage fields read again from its stored
 * transcript, when it still has one. Running it twice changes nothing.
 */
export function backfill(sink) {
  const tally = { transcripts_read: 0, unreadable: 0 };
  tally.changed = refreshRows(sink, (row) => {
    const file = row.transcript && path.join(sink, row.transcript);
    if (!file || !existsSync(file)) return;
    let messages;
    try {
      messages = JSON.parse(gunzipSync(readFileSync(file), { maxOutputLength: MAX_PLAIN }).toString("utf8"));
    } catch {
      tally.unreadable++;
      return;
    }
    const metrics = transcriptMetrics(messages);
    for (const field of ["cache_read_input_tokens", "cache_creation_input_tokens", "total_cost_usd", "model_usage"]) row[field] = metrics[field];
    tally.transcripts_read++;
  });
  return tally;
}

export function status(sink, now = Date.now()) {
  const rows = readRows(sink);
  const state = readState(sink);
  const pull = staleness(state, now);
  const outcomes = state.outcomes ? staleness(state.outcomes, now) : { stale: false, backlog_stale: false };
  return {
    sink,
    ...pull,
    stale: pull.stale || outcomes.stale,
    pull_stale: pull.stale,
    outcomes_stale: outcomes.stale,
    outcomes_backlog_stale: outcomes.backlog_stale,
    budget_exhausted: state.budget_exhausted ?? false,
    resume_cutoff_at: state.resume_cutoff_at ?? null,
    rows: rows.length,
    transcripts: rows.filter((r) => r.transcript).length,
    outcome_records: readOutcomes(sink).length,
    outcomes_last_success_at: state.outcomes?.last_success_at ?? null,
    outcomes_budget_exhausted: state.outcomes?.budget_exhausted ?? false,
    outcomes_resume_cutoff_at: state.outcomes?.resume_cutoff_at ?? null,
    bytes: sinkBytes(sink),
  };
}

const pullAlert = (s) =>
  s.backlog_stale
    ? `ALERT: budget-stopped pulls have not drained the lane transcript backlog in 5 days (cutoff: ${s.resume_cutoff_at})`
    : `ALERT: no lane transcript pull has succeeded in the last 5 days (last: ${s.last_success_at ?? "never"})`;
const outcomesAlert = (s) =>
  s.outcomes_backlog_stale
    ? `ALERT: budget-stopped pull-outcomes passes have not drained the lane-outcome backlog in 5 days (cutoff: ${s.outcomes_resume_cutoff_at})`
    : `ALERT: no pull-outcomes pass has succeeded in the last 5 days (last: ${s.outcomes_last_success_at ?? "never"})`;

/** A kind, never a value: a failed listing call names its exit status only. */
const failureKind = (error, listing) => (error instanceof PullError ? error.message : error?.status !== undefined ? `${listing}: gh exited ${error.status}` : error?.name ?? "error");

// Exit codes: 0 done, 1 failed or stale, 2 usage.
export function main(argv = process.argv.slice(2), env = process.env, deps = undefined, io = { out: (s) => process.stdout.write(s), err: (s) => process.stderr.write(s) }) {
  let parsed;
  let sink;
  try {
    parsed = parseArgs(argv);
    sink = sinkOf(parsed.flags, env);
  } catch (error) {
    io.err(`${error.message}\n`);
    return 2;
  }
  const { command, flags } = parsed;
  // Read the key, then drop it, before anything can start a child process.
  const keyText = env.LANE_TRANSCRIPT_PRIVATE_KEY;
  delete env.LANE_TRANSCRIPT_PRIVATE_KEY;
  const d = deps ?? defaultDeps(env);
  // Alerts on a stale sink; the exit code is 1 when it is stale.
  const alertIfStale = (s) => {
    if (s.pull_stale) io.err(`${pullAlert(s)}\n`);
    if (s.outcomes_stale) io.err(`${outcomesAlert(s)}\n`);
    return s.stale ? 1 : 0;
  };
  if (command === "status") {
    const s = status(sink, d.now());
    io.out(`${JSON.stringify(s)}\n`);
    return alertIfStale(s);
  }
  if (command === "query") {
    try {
      for (const row of query(readRows(sink), flags)) io.out(`${JSON.stringify({ ...row, transcript: row.transcript && path.join(sink, row.transcript) })}\n`);
      return 0;
    } catch (error) {
      io.err(`${error.message}\n`);
      return 2;
    }
  }
  if (command === "prune") {
    io.out(`${JSON.stringify(prune(sink, d.now()))}\n`);
    return 0;
  }
  if (command === "backfill") {
    io.out(`${JSON.stringify(backfill(sink))}\n`);
    return 0;
  }
  if (command === "pull-outcomes") {
    try {
      pullOutcomes({ sink, repo: flags.repo ?? REPO, deps: d, log: (s) => io.out(`${s}\n`) });
      return 0;
    } catch (error) {
      const kind = failureKind(error, "run-list");
      try {
        const state = readState(sink);
        writeState(sink, { ...state, outcomes: { ...state.outcomes, last_error: kind } });
      } catch {}
      io.err(`pull-outcomes failed: ${kind}\n`);
      return 1;
    }
  }
  let recipient;
  try {
    recipient = parsePrivateKey(keyText);
  } catch (error) {
    io.err(`${error instanceof OpenError ? error.message : "no-key"}; set LANE_TRANSCRIPT_PRIVATE_KEY through vault-exec\n`);
    return 1;
  }
  if (flags.run) {
    try {
      return pullRun({ sink, repo: flags.repo ?? REPO, recipient, deps: d, log: (s) => io.out(`${s}\n`), runId: flags.run }).fetch_failed > 0 ? 1 : 0;
    } catch (error) {
      io.err(`pull failed: ${failureKind(error, "run-artifact-list")}\n`);
      return 1;
    }
  }
  try {
    // A complete pull is fresh; one that missed an artifact or stopped at its
    // budget is stale once its kept window is.
    pull({ sink, repo: flags.repo ?? REPO, recipient, deps: d, log: (s) => io.out(`${s}\n`) });
    const after = status(sink, d.now());
    alertIfStale(after);
    return after.pull_stale ? 1 : 0;
  } catch (error) {
    const kind = failureKind(error, "artifact-list");
    try {
      writeState(sink, { ...readState(sink), last_error: kind });
    } catch {
      // The sink itself may be the failure.
    }
    io.err(`pull failed: ${kind}\n`);
    alertIfStale(status(sink, d.now()));
    return 1;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = main();
