// verify-cap.mjs: whether pr-verify's FAILs on a pull request are at the
// merge gate's cap (`verify:repeated-fail`), read by the gate's own reader,
// babysit_verify_evidence.py `evidence`, so the cap is counted in one place.
// The cap never clears for the pull request: a fix round's push could never
// merge, so feedback-dispatch.mjs and fix-ci-dispatch.mjs start no
// address-feedback or fix-ci round on it and post nothing; the pr-merge lane
// closes it for a fresh attempt at its issue (owner decision 2026-10-29). A
// FAIL run of another pull request for the same issue that cannot be read
// (`verify:unreadable` with the reader's SIBLING_UNREADABLE detail), or an
// artifact listing that does not fit in this caller's limit (a detail that
// starts with DEADLINE_UNREADABLE), may hide the cap, so each skips the round
// too, failing closed, for this run only.
//
// The reader runs with the dispatcher job's GITHUB_TOKEN (actions, contents
// and pull-requests read), for the one pull request about to be dispatched.
// It reads with no --lane-link, so it needs no issues read for this pull
// request's own FAILs. A read that fails, times out or answers for another
// head, and any other refusal, is not the cap: the round runs as before,
// with a warning naming it, unless the caller expects that refusal (a FAIL
// at the head of a round sent for that FAIL). Each read's stderr, the
// reader's `babysit-listing-miss` lines first, is logged on one line.
//
// The reader counts every FAIL in the repository, so each read needs a run
// record and a compare per FAIL and a download per untied FAIL: on 2026-10-31,
// 458 FAILs were 1,252 reads, and every read was killed at
// VERIFY_CAP_TIMEOUT_MS with its calls spent and no answer. The
// reads pr-merge carried answer them with no request: its listing
// (listing-carry.mjs), run cache (carry-run-cache.mjs) and head-ref map
// (head-ref-map.mjs), used as its gate uses them, only where they count a FAIL.
// They are fetched on the first read only, so a run that skips before any read
// spends none of their calls, and the run cache keeps what each read adds for
// the next.
//
// A count miss on the carried listing takes the reader's waits, about 45 s a
// read, and a read that ends in DEADLINE_UNREADABLE saves no listing, so the
// next pull request's read would wait from the same base. The dispatchers read
// one pull request after another inside a 10-minute job, so after one such
// answer the reader's later reads skip the waits (NO_INCREMENTAL_WAITS).
import { spawn as spawnChild } from "node:child_process";
import { fileURLToPath } from "node:url";

export const VERIFY_SCRIPT = ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py";
export const CAPPED = "verify:repeated-fail";
// babysit_verify_evidence.py SIBLING_UNREADABLE, the detail of the
// `verify:unreadable` refusal `_elsewhere` raises (verify-cap.test.mjs reads
// the reader to check they match).
export const SIBLING_UNREADABLE = "a FAIL run of a pull request for the same issue";
// babysit_verify_evidence.py DEADLINE_UNREADABLE, the start of the
// `verify:unreadable` detail when the listing does not fit in what
// VERIFY_CAP_TIMEOUT_MS leaves (verify-cap.test.mjs checks they match).
export const DEADLINE_UNREADABLE = "the artifact listing does not fit in the caller's limit";
// babysit_verify_evidence.py FAIL: a counted FAIL at the head.
export const FAIL = "verify:fail";
// babysit_verify_evidence.py LISTING_MISS_PREFIX: the stderr line of a
// listing read that missed GitHub's live artifact count.
export const LISTING_MISS_PREFIX = "babysit-listing-miss";
const UNREADABLE = "verify:unreadable";
const SHA = /^[0-9a-f]{40}$/;
// One full read lists every artifact of the repository; the dispatcher job's
// timeout-minutes (10) leaves room for a few (judgment).
export const VERIFY_CAP_TIMEOUT_MS = 2 * 60_000;
// babysit_verify_evidence.py NO_INCREMENTAL_WAITS_ENV: one incremental read, and
// a miss goes straight to the whole listing, which refuses before paging when
// it cannot fit.
export const NO_INCREMENTAL_WAITS = { BABYSIT_VERIFY_NO_INCREMENTAL_WAITS: "1" };

// spawnSync's result ({ status, stdout, stderr, error }) from a child that
// leaves the event loop running. A read blocked behind spawnSync for a minute
// or more left the job's idle keep-alive socket to GitHub unread: a reset on it
// went unseen, undici's own idle timer could not fire, and the dispatch POST
// sent on that socket next failed (`fetch failed`, ECONNRESET). A child past
// `timeout` is killed and answers spawnSync's ETIMEDOUT error.
export function spawnAsync(command, args, { timeout, encoding, ...options } = {}) {
  return new Promise((resolve) => {
    const child = spawnChild(command, args, { ...options, stdio: ["ignore", "pipe", "pipe"] });
    const out = { stdout: "", stderr: "" };
    let error;
    let settled = false;
    const settle = (status) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve({ status: error ? null : status, ...out, error });
      }
    };
    for (const stream of ["stdout", "stderr"]) {
      child[stream].setEncoding(encoding ?? "utf8").on("data", (chunk) => {
        out[stream] += chunk;
      });
    }
    child.on("error", (thrown) => {
      error ??= thrown;
    });
    child.on("close", settle);
    // A child the reader started (gh) can hold the pipes open past the kill.
    const timer =
      timeout > 0 &&
      setTimeout(() => {
        error = Object.assign(new Error(`spawn ${command} ETIMEDOUT`), { code: "ETIMEDOUT" });
        child.kill();
        child.stdout.destroy();
        child.stderr.destroy();
        child.unref();
        settle(null);
      }, timeout);
  });
}

// The children that fetch what pr-merge carried, in order, each with its own
// api-calls notice: every file the workflow names, under one job-scoped file of
// shared GET answers, so main's run listing and each compare are read once.
export const CARRY_TIMEOUT_MS = 2 * 60_000;
export function carrySteps(env) {
  const shared = { PR_MERGE_READS_PATH: `${env.RUNNER_TEMP}/verify-carry-reads.json` };
  const carriedFile = `${env.RUNNER_TEMP}/pr-merge-carried.json`;
  const steps = [{ script: "listing-carry.mjs", args: [], env: { ...shared, API_BUDGET_SCRIPT: "listing-carry" } }];
  if (env.BABYSIT_RUN_CACHE) {
    steps.push(
      { script: "carry-run-cache.mjs", args: ["read"], env: { ...shared, API_BUDGET_SCRIPT: "carry-run-cache", CARRY_TO: carriedFile } },
      // No requests. Its outputs are for pr-merge's steps, not the dispatch step's.
      { script: "carry-run-cache.mjs", args: [], env: { CARRY_FROM: carriedFile, CARRY_TO: env.BABYSIT_RUN_CACHE, GITHUB_OUTPUT: "" } },
    );
  }
  if (env.BABYSIT_VERIFY_HEAD_REFS) {
    steps.push({ script: "head-ref-map.mjs", args: ["read"], env: { ...shared, API_BUDGET_SCRIPT: "head-ref-map", HEAD_REFS_PATH: env.BABYSIT_VERIFY_HEAD_REFS } });
  }
  return steps;
}

// Each carry script warns and writes nothing on its own failures, so the
// reader then asks GitHub for that part alone; a child that dies is named.
async function fetchCarry(env) {
  const failed = [];
  for (const step of carrySteps(env)) {
    const done = await spawnAsync(process.execPath, [fileURLToPath(new URL(`../pr-merge/${step.script}`, import.meta.url)), ...step.args], {
      env: { ...env, ACTIONS_TOKEN: env.ACTIONS_TOKEN || env.GITHUB_TOKEN, ...step.env },
      timeout: CARRY_TIMEOUT_MS,
    });
    process.stdout.write(done.stdout ?? "");
    if (done.status !== 0) {
      failed.push(`${step.script}: ${oneLine(done.error?.message ?? String(done.stderr).trim().split("\n").at(-1)) || `exit ${done.status}`}`);
    }
  }
  if (failed.length > 0) {
    throw new Error(failed.join("; "));
  }
}

// Whether a verifyCapReader answer never clears for the head, so a
// dispatcher records the head as handled: the cap does, a sibling read that
// failed may clear next run.
export const final = (answer) => typeof answer === "string" && answer.startsWith(CAPPED);

// The workflow annotation for a skip because the listing did not fit in the
// caller's limit (a `verify:unreadable` whose detail starts with
// DEADLINE_UNREADABLE), else null: with no fresh carried listing that skip
// recurs every run, so it is surfaced rather than logged as a plain skip.
export function deadlineWarning(number, answer) {
  return typeof answer === "string" && answer.startsWith(`${UNREADABLE}: ${DEADLINE_UNREADABLE}`) ? `::warning title=verify-deadline-skip::#${number}: ${oneLine(answer, 1000)}` : null;
}

const oneLine = (text, max = 300) => String(text ?? "").replaceAll(/[\r\n%]/g, " ").trim().slice(0, max);

// One line for a read's stderr: its line count, then the listing-miss lines,
// else the last line; null when it wrote nothing.
function stderrSummary(stderr) {
  const lines = String(stderr ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  if (lines.length === 0) {
    return null;
  }
  const misses = lines.filter((line) => line.startsWith(LISTING_MISS_PREFIX));
  const shown = misses.length > 0 ? misses : [lines.at(-1)];
  return `${lines.length} line(s), ${misses.length} ${LISTING_MISS_PREFIX}: ${oneLine(shown.join(" | "), 1000)}`;
}

// A function of { number, head, base, expected } that returns the reader's cap refusal,
// `verify:repeated-fail` with its detail (the FAILed heads), the sibling
// read's or the caller limit's `verify:unreadable` with its detail, or null.
// Only the first never clears for the head (`final`).
// `base`: the pull request's base commit, so the reader takes the gate's
// merge.max-verify-fails (the lower of that commit's and main's).
// `expected`: refusals the round is sent for, which warn nothing.
// `carry`: fetches what pr-merge carried, before the first read only, when the
// job names BABYSIT_VERIFY_LISTING_CARRY; a failed fetch is no carry.
export function verifyCapReader(env, options) {
  const read = verifyReader(env, options);
  return async (request) => (await read(request)).cap;
}

// babysit_verify_evidence.py Evidence.report's field: a counted FAIL at the
// head the gate's `_superseded` gave way.
export const SUPERSEDED_AT_HEAD = "supersededAtHead";

// verifyCapReader's read, answering { cap, supersededAtHead }: `cap` as above,
// and `supersededAtHead` true only when the read at the head says so, so a
// failed read, an answer for another head or a reader without the field is
// not superseded.
export function verifyReader(env, { spawn = spawnAsync, log = (line) => console.log(line), carry = fetchCarry } = {}) {
  let carried = null;
  let deadlineMissed = false;
  return async ({ number, head, base, expected = [] }) => {
    if (env.BABYSIT_VERIFY_LISTING_CARRY) {
      carried ??= Promise.resolve()
        .then(() => carry(env))
        .catch((error) => log(`::warning::pr-merge's carried reads were not all fetched (${oneLine(error?.message ?? error)}); the reader asks GitHub for the rest`));
      await carried;
    }
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "evidence", "--repo", env.GITHUB_REPOSITORY];
    if (SHA.test(String(base ?? ""))) {
      args.push("--base-sha", base);
    }
    // The reader sizes its listing to this kill limit and names this caller
    // when a listing cannot fit (babysit_verify_evidence.py DEADLINE_ENV).
    const readerEnv = { ...env, ...(deadlineMissed && NO_INCREMENTAL_WAITS), BABYSIT_VERIFY_DEADLINE_SECONDS: String(VERIFY_CAP_TIMEOUT_MS / 1000), BABYSIT_VERIFY_CALLER: "verify-cap.mjs" };
    const done = await spawn("python3", [...args, String(number), head], { encoding: "utf8", env: readerEnv, timeout: VERIFY_CAP_TIMEOUT_MS });
    const said = stderrSummary(done.stderr);
    if (said) {
      log(`#${number}: the verifier reader's stderr: ${said}`);
    }
    let report;
    try {
      if (done.status !== 0) {
        throw new Error(oneLine(done.error?.message ?? String(done.stderr).trim().split("\n").at(-1)) || `exit ${done.status}`);
      }
      report = JSON.parse(String(done.stdout).trim().split("\n").at(-1));
      if (report?.head !== head) {
        throw new Error(`it answered for head ${oneLine(report?.head)}`);
      }
    } catch (error) {
      log(`::warning::#${number}: the verifier reader did not read its FAIL cap (${oneLine(error.message)}); the round runs under its own caps`);
      return { cap: null, supersededAtHead: false };
    }
    const answer = (cap) => ({ cap, supersededAtHead: report[SUPERSEDED_AT_HEAD] === true });
    if (report.refusal === UNREADABLE && report.detail === SIBLING_UNREADABLE) {
      return answer(`${UNREADABLE}: ${SIBLING_UNREADABLE}`);
    }
    if (report.refusal === UNREADABLE && String(report.detail ?? "").startsWith(DEADLINE_UNREADABLE)) {
      deadlineMissed = true;
      return answer(`${UNREADABLE}: ${oneLine(report.detail)}`);
    }
    if (report.refusal !== CAPPED) {
      if (report.refusal != null && !expected.includes(report.refusal)) {
        log(`::warning::#${number}: the verifier reader refused ${oneLine(report.refusal)} (${oneLine(report.detail)}), not its FAIL cap; the round runs under its own caps`);
      }
      return answer(null);
    }
    return answer(typeof report.detail === "string" && report.detail ? `${CAPPED}: ${oneLine(report.detail)}` : CAPPED);
  };
}
