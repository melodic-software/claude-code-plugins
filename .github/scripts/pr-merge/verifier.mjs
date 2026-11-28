import { spawnSync } from "node:child_process";

import { lines as bodyLines } from "../pr-unblock/gate-source.mjs";

export const SHA = /^[0-9a-f]{40}$/;
export const VERIFY_SCRIPT = ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py";
export const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

export const VERIFY_FINAL = Object.freeze(["verify:repeated-fail"]);

export const READER_HOLDS = Object.freeze({
  link: "pr-merge's lane does not take its issue link (",
  verdict: "pr-merge's gate refuses its verifier verdict (",
  risk: "pr-merge's gate holds it on its risk score (",
});

export function verifyHold(evidence, head) {
  if (evidence === null || typeof evidence !== "object" || !("refusal" in evidence)) {
    return "its verifier verdict could not be read";
  }
  if (evidence.head !== head) {
    return "its verifier verdict was read at another head";
  }
  if (typeof evidence.ineligible === "string") {
    return `${READER_HOLDS.link}${escapeCommand(evidence.ineligible)})`;
  }
  if (evidence.refusal !== null) {
    const detail = VERIFY_FINAL.includes(evidence.refusal) && typeof evidence.detail === "string" && evidence.detail ? `: ${escapeCommand(evidence.detail)}` : "";
    return `${READER_HOLDS.verdict}${escapeCommand(evidence.refusal)}${detail})`;
  }
  if (evidence.ineligible !== null) {
    return "its issue link could not be read";
  }
  if (typeof evidence.reviews === "string") {
    return `${READER_HOLDS.risk}${escapeCommand(evidence.reviews)})`;
  }
  return evidence.reviews === null ? null : "its risk score could not be read";
}

export const READER_RATE_LIMIT_EXIT = 75;
export const GUARD_ERROR = "::error title=GitHub rate limit::";
export const SERVER_ERROR = "::error title=GitHub server error::";

export class ReaderRateLimited extends Error {
  constructor(what, stderr) {
    const line = String(stderr ?? "")
      .split("\n")
      .find((text) => text.startsWith(GUARD_ERROR) || text.startsWith(SERVER_ERROR));
    const serverError = line?.startsWith(SERVER_ERROR) === true;
    const cause = serverError ? "a GitHub server error hold" : "a GitHub rate limit";
    super(`${what} stopped on ${cause}: ${line ? line.slice((serverError ? SERVER_ERROR : GUARD_ERROR).length) : `it exited ${READER_RATE_LIMIT_EXIT}`}`);
    this.name = "ReaderRateLimited";
    this.serverError = serverError;
  }
}

export const GH_CALLS_PREFIX = "babysit-gh-calls ";
function ghCallsPayload(stderr) {
  const line = bodyLines(stderr).findLast((text) => text.startsWith(GH_CALLS_PREFIX));
  try {
    return line === undefined ? null : JSON.parse(line.slice(GH_CALLS_PREFIX.length));
  } catch {
    return null;
  }
}

export function ghCallsLine(stderr) {
  const payload = ghCallsPayload(stderr);
  return payload === null || typeof payload !== "object" ? null : `${GH_CALLS_PREFIX}${JSON.stringify(payload)}`;
}

export const LISTING_MISS_PREFIX = "babysit-listing-miss ";
export function listingMissLines(stderr) {
  return bodyLines(stderr).filter((text) => text.startsWith(LISTING_MISS_PREFIX));
}

export function ghCalls(stderr) {
  const payload = ghCallsPayload(stderr);
  const calls = payload?.calls;
  if (!Number.isSafeInteger(payload?.total) || calls === null || typeof calls !== "object") {
    return null;
  }
  const sum = (match) => Object.entries(calls).reduce((n, [kind, count]) => n + (match(kind) && Number.isSafeInteger(count) ? count : 0), 0);
  return { total: payload.total, githubToken: sum((kind) => kind.startsWith("override ")), paginated: sum((kind) => kind.endsWith("+paginate")) };
}

export const costLine = ({ number, calls, ms }) =>
  `#${number} ${calls === null ? "calls=unknown" : `calls=${calls.total} github-token=${calls.githubToken} paginated=${calls.paginated}`} ms=${ms}`;

export const readerEnv = (env, timeoutMs) => ({ ...env, BABYSIT_VERIFY_DEADLINE_SECONDS: String(timeoutMs / 1000), BABYSIT_VERIFY_CALLER: "enable-auto-merge.mjs" });

export function pythonVerify(env, { spawn = spawnSync, clock = Date.now, lane = true } = {}) {
  const verify = async ({ number, headRefOid: head, baseRefOid: base }, rung) => {
    if (!SHA.test(String(base))) {
      throw new Error("its base commit is not a commit SHA");
    }
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "evidence", ...(lane ? ["--lane-link", "--lane-reviews", "--lane-queue"] : []), "--shared-listing", "--repo", env.GITHUB_REPOSITORY, "--base-sha", base];
    if (lane && typeof rung === "string") {
      args.push("--rung", rung);
    }
    const started = clock();
    const done = spawn("python3", [...args, String(number), head], { encoding: "utf8", env: readerEnv(env, VERIFY_TIMEOUT_MS), timeout: VERIFY_TIMEOUT_MS });
    const cost = { number, calls: ghCalls(done.stderr), ms: clock() - started };
    let evidence;
    if (done.status === 0) {
      try {
        evidence = JSON.parse(String(done.stdout).trim().split("\n").at(-1));
      } catch (error) {
        evidence = error;
      }
    }
    verify.costs.push(cost);
    console.log(`enable-auto-merge: ${costLine(cost)}`);
    const calls = ghCallsLine(done.stderr);
    if (calls !== null) {
      console.log(calls);
    }
    for (const miss of listingMissLines(done.stderr)) {
      console.log(miss);
    }
    if (done.status === READER_RATE_LIMIT_EXIT) {
      throw new ReaderRateLimited(`#${number}'s verifier read`, done.stderr);
    }
    if (done.status !== 0) {
      const said = String(done.stderr ?? "")
        .trim()
        .split("\n")
        .filter((text) => !text.startsWith(GH_CALLS_PREFIX) && !text.startsWith(LISTING_MISS_PREFIX))
        .at(-1);
      throw new Error(`babysit_verify_evidence.py exited ${done.status ?? done.signal}: ${said ?? ""}`);
    }
    if (evidence instanceof Error) {
      throw evidence;
    }
    return evidence;
  };
  verify.costs = [];
  return verify;
}

export const VERIFY_TIMEOUT_MS = 4 * 60_000;

export function rotated(pulls, runNumber) {
  const start = Number.isSafeInteger(runNumber) && pulls.length > 0 ? ((runNumber % pulls.length) + pulls.length) % pulls.length : 0;
  return [...pulls.slice(start), ...pulls.slice(0, start)];
}
