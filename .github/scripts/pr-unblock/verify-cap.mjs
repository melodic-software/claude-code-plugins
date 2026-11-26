import { spawn as spawnChild } from "node:child_process";
import { fileURLToPath } from "node:url";

export const VERIFY_SCRIPT = ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py";
export const CAPPED = "verify:repeated-fail";
export const SIBLING_UNREADABLE = "a FAIL run of a pull request for the same issue";
export const DEADLINE_UNREADABLE = "the artifact listing does not fit in the caller's limit";
export const FAIL = "verify:fail";
export const EARLIER_FAIL = "verify:earlier-fail";
export const LISTING_MISS_PREFIX = "babysit-listing-miss";
const UNREADABLE = "verify:unreadable";
const SHA = /^[0-9a-f]{40}$/;
export const VERIFY_CAP_TIMEOUT_MS = 2 * 60_000;
export const NO_INCREMENTAL_WAITS = { BABYSIT_VERIFY_NO_INCREMENTAL_WAITS: "1" };

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

export const CARRY_TIMEOUT_MS = 2 * 60_000;
export function carrySteps(env) {
  const shared = { PR_MERGE_READS_PATH: `${env.RUNNER_TEMP}/verify-carry-reads.json` };
  const carriedFile = `${env.RUNNER_TEMP}/pr-merge-carried.json`;
  const steps = [];
  if (env.BABYSIT_RUN_CACHE) {
    steps.push(
      { script: "carry-run-cache.mjs", args: ["read"], env: { ...shared, API_BUDGET_SCRIPT: "carry-run-cache", CARRY_TO: carriedFile } },
      { script: "carry-run-cache.mjs", args: [], env: { CARRY_FROM: carriedFile, CARRY_TO: env.BABYSIT_RUN_CACHE, GITHUB_OUTPUT: "" } },
    );
  }
  if (env.BABYSIT_VERIFY_HEAD_REFS) {
    steps.push({ script: "head-ref-map.mjs", args: ["read"], env: { ...shared, API_BUDGET_SCRIPT: "head-ref-map", HEAD_REFS_PATH: env.BABYSIT_VERIFY_HEAD_REFS } });
  }
  return steps;
}

async function fetchCarry(env) {
  const failed = [];
  for (const step of carrySteps(env)) {
    const done = await spawnAsync(process.execPath, [fileURLToPath(new URL(`../pr-merge/${step.script}`, import.meta.url)), ...step.args], {
      env: { ...env, ACTIONS_TOKEN: env.ACTIONS_TOKEN || env.GITHUB_TOKEN, ...step.env },
      timeout: CARRY_TIMEOUT_MS,
    });
    process.stdout.write(done.stdout ?? "");
    if (done.status !== 0) {
      failed.push(`${step.script}: ${failureOf(done)}`);
    }
  }
  if (failed.length > 0) {
    throw new Error(failed.join("; "));
  }
}

export const final = (answer) => typeof answer === "string" && answer.startsWith(CAPPED);

export function deadlineWarning(number, answer) {
  return typeof answer === "string" && answer.startsWith(`${UNREADABLE}: ${DEADLINE_UNREADABLE}`) ? `::warning title=verify-deadline-skip::#${number}: ${oneLine(answer, 1000)}` : null;
}

const oneLine = (text, max = 300) => String(text ?? "").replaceAll(/[\r\n%]/g, " ").trim().slice(0, max);

const failureOf = (done) => oneLine(done.error?.message ?? String(done.stderr).trim().split("\n").at(-1)) || `exit ${done.status}`;

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

export function verifyCapReader(env, options) {
  const read = verifyReader(env, options);
  return async (request) => (await read(request)).cap;
}

export const SUPERSEDED_AT_HEAD = "supersededAtHead";

export const EARLIER_FAILS = "earlierFails";

export function verifyReader(env, { spawn = spawnAsync, log = (line) => console.log(line), carry = fetchCarry } = {}) {
  const unread = () => ({ cap: null, supersededAtHead: false, earlierFailHeads: [], readFailed: true });
  let carried = null;
  let deadlineMissed = false;
  return async ({ number, head, base, expected = [] }) => {
    if (carrySteps(env).length > 0) {
      carried ??= Promise.resolve()
        .then(() => carry(env))
        .catch((error) => log(`::warning::pr-merge's carried reads were not all fetched (${oneLine(error?.message ?? error)}); the reader asks GitHub for the rest`));
      await carried;
    }
    if (!SHA.test(String(base ?? ""))) {
      log(`::warning::#${number}: no base commit to read the verifier at (${oneLine(String(base))}); the round runs under its own caps`);
      return unread();
    }
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "evidence", "--repo", env.GITHUB_REPOSITORY, "--base-sha", base];
    const readerEnv = { ...env, ...(deadlineMissed && NO_INCREMENTAL_WAITS), BABYSIT_VERIFY_DEADLINE_SECONDS: String(VERIFY_CAP_TIMEOUT_MS / 1000), BABYSIT_VERIFY_CALLER: "verify-cap.mjs" };
    const done = await spawn("python3", [...args, String(number), head], { encoding: "utf8", env: readerEnv, timeout: VERIFY_CAP_TIMEOUT_MS });
    const said = stderrSummary(done.stderr);
    if (said) {
      log(`#${number}: the verifier reader's stderr: ${said}`);
    }
    let report;
    try {
      if (done.status !== 0) {
        throw new Error(failureOf(done));
      }
      report = JSON.parse(String(done.stdout).trim().split("\n").at(-1));
      if (report?.head !== head) {
        throw new Error(`it answered for head ${oneLine(report?.head)}`);
      }
    } catch (error) {
      log(`::warning::#${number}: the verifier reader did not read its FAIL cap (${oneLine(error.message)}); the round runs under its own caps`);
      return unread();
    }
    const answer = (cap) => ({ cap, supersededAtHead: report[SUPERSEDED_AT_HEAD] === true, earlierFailHeads: [] });
    if (report.refusal === EARLIER_FAIL) {
      const heads = Array.isArray(report[EARLIER_FAILS]) ? report[EARLIER_FAILS] : [];
      const earlierFailHeads = [...new Set(heads)].filter((sha) => SHA.test(String(sha)) && sha !== head);
      if (earlierFailHeads.length === 0 || earlierFailHeads.length !== heads.length) {
        log(`::warning::#${number}: the verifier reader refused ${EARLIER_FAIL} but its ${EARLIER_FAILS} (${oneLine(JSON.stringify(report[EARLIER_FAILS] ?? null))}) are not the FAILed heads; no round is sent for their notes`);
        return answer(null);
      }
      return { ...answer(null), earlierFailHeads };
    }
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
