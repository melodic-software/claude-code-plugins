// The lane transcript puller: copies each sealed lane-transcript artifact to
// the sink, opened with the private key, and keeps the sink's retention.
// README.md has the commands, the layout and the key setup.
//
// The private key comes only from LANE_TRANSCRIPT_PRIVATE_KEY, which vault-exec
// sets; it is read once and removed from the environment before any child
// process starts. Transcript text reaches only the sink's files: nothing here
// prints it, and an error names a kind, never a value.
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

import { OpenError, openRecord, parsePrivateKey } from "../../.github/actions/open-lane-output/open.mjs";
import {
  appendRow,
  ensureDir,
  laneOf,
  parseArtifactName,
  paths,
  prune,
  query,
  readRows,
  readState,
  sinkBytes,
  staleness,
  transcriptMetrics,
  transcriptPath,
  writeState,
} from "./store.mjs";

export const REPO = "melodic-software/claude-code-plugins";
export const PAYLOAD = "transcript.json.gz";
export const ENTRY = `${PAYLOAD}.sealed`;
const HOUR = 60 * 60 * 1000;
const ARTIFACT_DAYS = 7;
const OVERLAP = 6 * HOUR;
const PER_PAGE = 100;
const MAX_SEALED = 64 * 1024 * 1024;
const MAX_PLAIN = 256 * 1024 * 1024;
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
// pull.test.mjs reads the workflows and fails when a workflow, a local
// job-id, or a reusable's caller is missing here.
const LEGS = ["", "-subscription", "-fallback"];
const legs = (job, suffixes = [""]) => LEGS.flatMap((leg) => suffixes.map((suffix) => `${job}${leg}${suffix}`));
const AUDIT_UNITS = ["a", "c", "d"].flatMap((group) => [1, 2, 3, 4, 5, 6, 7, 8].map((n) => `-${group}${n}`));
const VERIFY_LEGS = ["", ...Array.from({ length: 11 }, (_, i) => `-${i + 2}`), "-spec"];
const REVIEW_CHUNKS = ["claude-review", "claude-security-review"].flatMap((lane) => ["", "-2", "-3", "-4"].map((chunk) => `-${lane}${chunk}`));
export const TRANSCRIPT_JOB_IDS = {
  "intake-triage.yml": legs("refine-issue"),
  "maintenance-audit-lane-runs.yml": legs("judge", AUDIT_UNITS),
  "maintenance-measure-skill-edit.yml": ["propose-key", "propose", "propose-fallback"],
  "maintenance-tidy-code-upkeep.yml": legs("model"),
  "post-merge-test-mutation.yml": [...legs("generate"), ...legs("triage")],
  "pr-review-main.yml": legs("review", REVIEW_CHUNKS),
  // Its job-id holds the issue number, which no fixed list can name, so the
  // pull does not reach these transcripts.
  "pr-run-activity-read.yml": [],
  "pr-unblock.yml": ["0", "1", "2"].flatMap((n) => [`adjudicate-feedback-${n}`, `adjudicate-feedback-${n}-subscription`, `adjudicate-feedback-${n}-fallback`]),
  "pr-verify.yml": legs("check-intent", VERIFY_LEGS),
  "pr-verify-capture.yml": legs("capture", ["-probe", ""]),
  "pr-rate-merge-risk.yml": ["rate-merge-risk"],
  "upstream-apply-changelog.yml": [...legs("model"), ...legs("scrub-probe")],
  // job-id `${{ inputs.lane }}-${{ github.job }}` and chunks -2 to -4.
  "ci-workflows/pr-review-cli.yml": ["code", "security"].flatMap((lane) => ["review-key", "review-subscription", "review-fallback"].flatMap((job) => ["", "-2", "-3", "-4"].map((chunk) => `${lane}-${job}${chunk}`))),
  // job-id `intake-${{ github.job }}`.
  "ci-workflows/intake-triage.yml": ["intake-claude", "intake-subscription", "intake-fallback"],
};
// A re-run uploads under its own attempt number; attempts past 3 are not read.
// Two workflows can share a job-id (model), so each name is listed once.
export const ATTEMPTS = 3;
export const TRANSCRIPT_NAMES = [...new Set(Object.values(TRANSCRIPT_JOB_IDS).flatMap((ids) => ids.flatMap((id) => Array.from({ length: ATTEMPTS }, (_, i) => `lane-transcript-${id}-${i + 1}`))))];
// Listing calls one pull may spend: two pages a name plus 25%, and never under
// 400, out of the user token's 5,000 REST requests an hour. Reaching it before
// every name reaches the cutoff fails the pull, so the window stays.
export const MAX_LIST_CALLS = Math.max(400, Math.ceil(TRANSCRIPT_NAMES.length * 2 * 1.25));

const USAGE = `usage: pull.mjs <pull|status|query|prune> [--sink DIR] [--repo OWNER/REPO]
  query filters: [--lane LANE[/JOB]] [--model TEXT] [--outcome OUTCOME] [--since YYYY-MM-DD] [--until YYYY-MM-DD]`;

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
  if (!["pull", "status", "query", "prune"].includes(command)) throw new UsageError(USAGE);
  const flags = {};
  const names = new Set(["sink", "repo", "lane", "model", "outcome", "since", "until"]);
  for (let i = 0; i < rest.length; i += 2) {
    const name = /^--([a-z]+)$/.exec(rest[i])?.[1];
    if (!names.has(name) || rest[i + 1] === undefined || name in flags) throw new UsageError(USAGE);
    flags[name] = rest[i + 1];
  }
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

// The sealed record inside one artifact zip: exactly one entry, the sealed file.
function sealedRecord(deps, sink, zip) {
  const dir = mkdtempSync(path.join(paths(sink).tmp, "zip-"));
  try {
    const file = path.join(dir, "artifact.zip");
    writeFileSync(file, zip, { mode: 0o600 });
    const unzip = (args) => fetched("artifact-unzip", () => deps.unzip(args));
    const entries = unzip(["-Z1", file]).toString("utf8").split("\n").filter(Boolean);
    if (entries.length !== 1 || entries[0] !== ENTRY) return null;
    return unzip(["-p", file, ENTRY]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Each transcript artifact created since the cutoff: every name's listing,
// newest first, paged until an artifact older than the cutoff or a short page.
// The cutoff is by artifact created_at, so a re-run attempt of an older run is
// still reached.
function* listed(deps, repo, cutoff) {
  const maxCalls = deps.maxListCalls ?? MAX_LIST_CALLS;
  let calls = 0;
  for (const name of TRANSCRIPT_NAMES) {
    for (let page = 1; ; page++) {
      // Stopping short of the cutoff would record a success that skipped
      // artifacts, so it fails and the window stays.
      if (++calls > maxCalls) throw new PullError(`call-cap: ${maxCalls} listing calls did not reach the last pull's cutoff`);
      const { artifacts = [] } = json(ghRetried(deps, ["api", `repos/${repo}/actions/artifacts?name=${name}&per_page=${PER_PAGE}&page=${page}`], true));
      const fresh = artifacts.filter((artifact) => Date.parse(artifact.created_at) >= cutoff);
      yield* fresh;
      if (fresh.length < PER_PAGE) break;
    }
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
  ensureDir(sink);
  ensureDir(paths(sink).transcripts);
  ensureDir(paths(sink).tmp);
  const state = readState(sink);
  const last = Date.parse(state.last_success_at ?? "");
  // A pull stopped at its budget leaves its own cutoff, so the next pull still
  // reaches the artifacts it did not get to.
  const resume = Date.parse(state.resume_cutoff_at ?? "");
  const since = Number.isNaN(resume) ? (Number.isNaN(last) ? 0 : last - OVERLAP) : resume;
  const cutoff = Math.max(now - ARTIFACT_DAYS * 24 * HOUR, since);
  const known = new Set(readRows(sink).map((row) => row.artifact_id));
  const runs = new Map();
  const tally = { pulled: 0, known: 0, fork: 0, expired: 0, unnamed: 0, too_large: 0, bad_zip: 0, sealed_mismatch: 0, fetch_failed: 0 };
  const failedKinds = new Set();
  let exhausted = false;
  writeState(sink, { ...state, last_attempt_at: new Date(now).toISOString() });

  try {
    for (const artifact of listed(deps, repo, cutoff)) {
      const named = parseArtifactName(artifact.name);
      const wf = artifact.workflow_run ?? {};
      if (!named) tally.unnamed++;
      else if (known.has(artifact.id)) tally.known++;
      else if (artifact.expired) tally.expired++;
      // The public key is public: a fork's run could seal a record of its own.
      else if (!wf.id || wf.head_repository_id !== wf.repository_id) tally.fork++;
      else if (artifact.size_in_bytes > MAX_SEALED) tally.too_large++;
      else {
        try {
          const outcome = store({ sink, repo, recipient, deps, artifact, named, runs, now });
          tally[outcome]++;
          if (outcome === "pulled") known.add(artifact.id);
        } catch (error) {
          if (!(error instanceof FetchFailed)) throw error;
          tally.fetch_failed++;
          failedKinds.add(error.message);
        }
      }
    }
  } catch (error) {
    if (!(error instanceof BudgetSpent)) throw error;
    exhausted = true;
  }
  // Every candidate sealed to another key and none opened: the vault key does
  // not match the repository variable, which must alert, not pass.
  if (tally.sealed_mismatch > 0 && tally.pulled === 0 && tally.known === 0) throw new PullError(`key-mismatch: ${tally.sealed_mismatch} transcript(s) did not open for this key and none did`);
  const pruned = prune(sink, now);
  // A pull that missed an artifact keeps the last success, so the next pull's
  // cutoff still reaches it; the artifact's 7-day expiry bounds how long.
  // A pull stopped at its budget is a success that keeps its cutoff for the next.
  const finished = tally.fetch_failed > 0 ? { last_error: `fetch-failed: ${tally.fetch_failed} transcript(s) (${[...failedKinds].join(", ")})` } : { last_success_at: new Date(now).toISOString(), last_error: null, resume_cutoff_at: null };
  if (exhausted) finished.resume_cutoff_at = new Date(cutoff).toISOString();
  writeState(sink, { ...readState(sink), ...finished, last_tally: tally, budget_exhausted: exhausted, gh_calls: deps.meter.calls });
  log(`pulled ${tally.pulled} transcript(s); skipped ${JSON.stringify(tally)}; pruned ${JSON.stringify(pruned)}${exhausted ? `; stopped at the gh call budget of ${deps.meter.budget}` : ""}`);
  return tally;
}

function store({ sink, repo, recipient, deps, artifact, named, runs, now }) {
  const runId = String(artifact.workflow_run.id);
  const record = sealedRecord(deps, sink, fetched("artifact-zip", () => ghRetried(deps, ["api", `repos/${repo}/actions/artifacts/${artifact.id}/zip`])));
  if (!record) return "bad_zip";
  let gz;
  try {
    gz = openRecord(recipient, [recipient.keyId], PAYLOAD, record, runId, named.jobId);
  } catch (error) {
    if (error instanceof OpenError) return "sealed_mismatch";
    throw error;
  }
  let messages = null;
  try {
    messages = JSON.parse(gunzipSync(gz, { maxOutputLength: MAX_PLAIN }).toString("utf8"));
  } catch {
    messages = null;
  }
  if (!runs.has(runId)) runs.set(runId, fetched("run-read", () => json(ghRetried(deps, ["api", `repos/${repo}/actions/runs/${runId}`]))));
  const run = runs.get(runId);
  const row = {
    artifact_id: artifact.id,
    run_id: Number(runId),
    run_attempt: named.attempt,
    job_id: named.jobId,
    lane: laneOf(run.path),
    workflow: typeof run.name === "string" ? run.name : null,
    event: typeof run.event === "string" ? run.event : null,
    head_branch: typeof run.head_branch === "string" ? run.head_branch : null,
    run_conclusion: run.conclusion ?? run.status ?? null,
    created_at: artifact.created_at,
    date: artifact.created_at.slice(0, 10),
    ...transcriptMetrics(messages),
    transcript_bytes: gz.length,
    pulled_at: new Date(now).toISOString(),
  };
  row.transcript = transcriptPath(row);
  const file = path.join(sink, row.transcript);
  ensureDir(path.dirname(file));
  writeFileSync(file, gz, { mode: 0o600 });
  appendRow(sink, row);
  return "pulled";
}

export function status(sink, now = Date.now()) {
  const rows = readRows(sink);
  const state = readState(sink);
  return { sink, ...staleness(state, now), budget_exhausted: state.budget_exhausted ?? false, resume_cutoff_at: state.resume_cutoff_at ?? null, rows: rows.length, transcripts: rows.filter((r) => r.transcript).length, bytes: sinkBytes(sink) };
}

const alert = (s) => `ALERT: no lane transcript pull has succeeded in the last 5 days (last: ${s.last_success_at ?? "never"})`;

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
  if (command === "status") {
    const s = status(sink, d.now());
    io.out(`${JSON.stringify(s)}\n`);
    if (s.stale) io.err(`${alert(s)}\n`);
    return s.stale ? 1 : 0;
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
  let recipient;
  try {
    recipient = parsePrivateKey(keyText);
  } catch (error) {
    io.err(`${error instanceof OpenError ? error.message : "no-key"}; set LANE_TRANSCRIPT_PRIVATE_KEY through vault-exec\n`);
    return 1;
  }
  try {
    const tally = pull({ sink, repo: flags.repo ?? REPO, recipient, deps: d, log: (s) => io.out(`${s}\n`) });
    if (tally.fetch_failed === 0) return 0;
    const s = status(sink, d.now());
    if (s.stale) io.err(`${alert(s)}\n`);
    return s.stale ? 1 : 0;
  } catch (error) {
    // A kind, never a value: a failed listing call names its exit status only.
    const kind = error instanceof PullError ? error.message : error?.status !== undefined ? `artifact-list: gh exited ${error.status}` : error?.name ?? "error";
    try {
      writeState(sink, { ...readState(sink), last_error: kind });
    } catch {
      // The sink itself may be the failure.
    }
    io.err(`pull failed: ${kind}\n`);
    const s = status(sink, d.now());
    if (s.stale) io.err(`${alert(s)}\n`);
    return 1;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = main();
