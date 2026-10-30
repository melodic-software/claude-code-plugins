// verify-cap.mjs: whether pr-verify's FAILs on a pull request are at the
// merge gate's cap (`verify:repeated-fail`), read by the gate's own reader,
// babysit_verify_evidence.py `evidence`, so the cap is counted in one place.
// The cap never clears for the pull request: a fix round's push could never
// merge, so feedback-dispatch.mjs and fix-ci-dispatch.mjs start no
// address-feedback or fix-ci round on it and post nothing; the pr-merge lane
// closes it for a fresh attempt at its issue (owner decision 2026-10-29). A
// FAIL run of another pull request for the same issue that cannot be read
// (`verify:unreadable` with the reader's SIBLING_UNREADABLE detail) may hide
// the cap, so it skips the round too, failing closed, for this run only.
//
// The reader runs with the dispatcher job's GITHUB_TOKEN (actions, contents
// and pull-requests read), for the one pull request about to be dispatched.
// It reads with no --lane-link, so it needs no issues read for this pull
// request's own FAILs. A read that fails, times out or answers for another
// head is not the cap: the round runs as before, with a warning.
import { spawnSync } from "node:child_process";

export const VERIFY_SCRIPT = ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py";
export const CAPPED = "verify:repeated-fail";
// babysit_verify_evidence.py SIBLING_UNREADABLE, the detail of the
// `verify:unreadable` refusal `_elsewhere` raises (verify-cap.test.mjs reads
// the reader to check they match).
export const SIBLING_UNREADABLE = "a FAIL run of a pull request for the same issue";
const UNREADABLE = "verify:unreadable";
const SHA = /^[0-9a-f]{40}$/;
// One full read lists every artifact of the repository; the dispatcher job's
// timeout-minutes (10) leaves room for a few (judgment).
export const VERIFY_CAP_TIMEOUT_MS = 2 * 60_000;

// Whether a verifyCapReader answer never clears for the head, so a
// dispatcher records the head as handled: the cap does, a sibling read that
// failed may clear next run.
export const final = (answer) => typeof answer === "string" && answer.startsWith(CAPPED);

const oneLine = (text) => String(text ?? "").replaceAll(/[\r\n%]/g, " ").trim().slice(0, 300);

// A function of { number, head, base } that returns the reader's cap refusal,
// `verify:repeated-fail` with its detail (the FAILed heads), the sibling
// read's `verify:unreadable` with its detail, or null. Only the first never
// clears for the head (`final`).
// `base`: the pull request's base commit, so the reader takes the gate's
// merge.max-verify-fails (the lower of that commit's and main's).
export function verifyCapReader(env, { spawn = spawnSync, log = (line) => console.log(line) } = {}) {
  return ({ number, head, base }) => {
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "evidence", "--repo", env.GITHUB_REPOSITORY];
    if (SHA.test(String(base ?? ""))) {
      args.push("--base-sha", base);
    }
    const done = spawn("python3", [...args, String(number), head], { encoding: "utf8", env, timeout: VERIFY_CAP_TIMEOUT_MS });
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
    if (report.refusal !== CAPPED) {
      return null;
    }
    return typeof report.detail === "string" && report.detail ? `${CAPPED}: ${oneLine(report.detail)}` : CAPPED;
  };
}
