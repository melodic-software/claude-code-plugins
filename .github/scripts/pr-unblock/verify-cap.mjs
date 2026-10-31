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
// The reader runs as a child process the event loop keeps serving. Under
// spawnSync a read killed at the limit was followed by a dispatch POST that
// failed with `fetch failed` (suspected: idle connections the blocked loop
// left unserved), so the next run at that head paid for the read again.
// The listing pr-merge carried (listing-carry.mjs) is fetched on the first
// read only, so a run that skips before any read spends none of its calls.
import { execFile } from "node:child_process";

import { main as carryListing } from "../pr-merge/listing-carry.mjs";

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
// The reader's stdout and stderr, kept whole (judgment: a report line and a
// few log lines, far below this).
const MAX_BUFFER = 64 * 1024 * 1024;

// `command` run as a child process, answered in spawnSync's shape (status,
// stdout, stderr, error) without blocking the event loop; past `timeout` ms
// it is killed, and the error names ETIMEDOUT as spawnSync's does.
export function spawnReader(command, args, { env, timeout }) {
  return new Promise((resolve) => {
    execFile(command, args, { encoding: "utf8", env, timeout, killSignal: "SIGTERM", maxBuffer: MAX_BUFFER }, (error, stdout, stderr) => {
      if (!error) {
        resolve({ status: 0, stdout, stderr });
        return;
      }
      const status = typeof error.code === "number" ? error.code : null;
      const timedOut = error.killed === true && error.signal === "SIGTERM";
      resolve({ status, stdout, stderr, error: timedOut ? new Error(`${command} ETIMEDOUT after ${timeout} ms`) : status === null ? error : undefined });
    });
  });
}

// listing-carry.mjs, run in this process with the job's token, once: it
// writes BABYSIT_VERIFY_LISTING_CARRY or warns and writes nothing.
const fetchCarry = (env) => carryListing({ env: { ...env, ACTIONS_TOKEN: env.ACTIONS_TOKEN || env.GITHUB_TOKEN } });

// The reader's waits between incremental reads of a carried listing
// (babysit_verify_evidence.py INCREMENTAL_WAITS) and the whole listing after
// them do not fit in that limit, and a killed read is not the cap, so a miss
// goes straight to the whole listing (NO_INCREMENTAL_WAITS_ENV).
export const NO_INCREMENTAL_WAITS = { BABYSIT_VERIFY_NO_INCREMENTAL_WAITS: "1" };

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
// `carry`: fetches the listing pr-merge carried, before the first read only,
// when the job names BABYSIT_VERIFY_LISTING_CARRY; a failed fetch is no carry.
export function verifyCapReader(env, { spawn = spawnReader, log = (line) => console.log(line), carry = fetchCarry } = {}) {
  env = { ...env, ...NO_INCREMENTAL_WAITS };
  let carried = null;
  return async ({ number, head, base, expected = [] }) => {
    if (env.BABYSIT_VERIFY_LISTING_CARRY) {
      carried ??= Promise.resolve()
        .then(() => carry(env))
        .catch((error) => log(`::warning::the carried artifact listing was not fetched (${oneLine(error?.message ?? error)}); the reader lists every page`));
      await carried;
    }
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "evidence", "--repo", env.GITHUB_REPOSITORY];
    if (SHA.test(String(base ?? ""))) {
      args.push("--base-sha", base);
    }
    // The reader sizes its listing to this kill limit and names this caller
    // when a listing cannot fit (babysit_verify_evidence.py DEADLINE_ENV).
    const readerEnv = { ...env, BABYSIT_VERIFY_DEADLINE_SECONDS: String(VERIFY_CAP_TIMEOUT_MS / 1000), BABYSIT_VERIFY_CALLER: "verify-cap.mjs" };
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
      return null;
    }
    if (report.refusal === UNREADABLE && report.detail === SIBLING_UNREADABLE) {
      return `${UNREADABLE}: ${SIBLING_UNREADABLE}`;
    }
    if (report.refusal === UNREADABLE && String(report.detail ?? "").startsWith(DEADLINE_UNREADABLE)) {
      return `${UNREADABLE}: ${oneLine(report.detail)}`;
    }
    if (report.refusal !== CAPPED) {
      if (report.refusal != null && !expected.includes(report.refusal)) {
        log(`::warning::#${number}: the verifier reader refused ${oneLine(report.refusal)} (${oneLine(report.detail)}), not its FAIL cap; the round runs under its own caps`);
      }
      return null;
    }
    return typeof report.detail === "string" && report.detail ? `${CAPPED}: ${oneLine(report.detail)}` : CAPPED;
  };
}
