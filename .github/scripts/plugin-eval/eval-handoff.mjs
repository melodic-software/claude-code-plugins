#!/usr/bin/env node
// eval-handoff.mjs: whether one `claude plugin eval` leg hands off to the next
// credential, judged by run-claude-cli's own classifier.
//
// A leg is the policy probe (`claude -p --output-format stream-json`) plus the
// eval it guards, both on one credential. Each kept run trace is the session
// as stream-json, one message per line (code.claude.com/docs/en/plugin-evals,
// "What a grader can look at", the `trace` row), the same stream run-claude-cli
// writes as its execution file. So every errored run's trace and the probe's
// stream go through lane.cjs judgeLeg and classify.cjs isCreditStop from the
// ci-workflows checkout at the pin the lanes run (CI_WORKFLOWS), and the leg
// hands off on the rule lane.cjs handoffReason applies, restated below because
// lane.cjs does not export it:
//   key leg           a credit stop, or class auth with API status 401 or 402
//   subscription leg  with FALLBACK_READY true: a credit stop, a 401 or 402,
//                     or a limit stop (a rejected rate_limit_event with its reset)
//   fallback leg      never
// A run whose `error` is null ended normally and is not judged; the suite's
// exit code is not read, since a case below --threshold also exits 1.
// A results file marked partial with reason auth_failed ("your credential was
// rejected before or at the first run", plugin-evals' exit-code table) is a
// refused credential with no status to read, so it hands off as a 401 does
// when no stream already has; its runs may hold no trace a classifier can
// judge. The suite's other partial reasons, cost_ceiling and interrupted, are
// not the credential's stop.
//
// Env: LEG (key, subscription or fallback), FALLBACK_READY, CI_WORKFLOWS,
// RESULTS (the --json results, one path per line; a missing one is skipped),
// PROBE and PROBE_EXIT (the probe's stream and exit code; PROBE may be empty),
// LEG_RESULT (where to write the leg's execution file for report-lane-outcome:
// one result message carrying the suites' summed durationSeconds and costUsd,
// nothing a run wrote).
// Prints handoff, handoff-reason, lane-class and outcome as key=value lines.
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const LEGS = { key: "api-key", subscription: "subscription", fallback: "fallback" };
const REFUSED_STATUSES = [401, 402];
// The classes a run's trace can show that say the credential stopped, not the case.
const STOP_CLASSES = ["credit-stop", "auth", "rate-limit", "overloaded"];

export function handoffReason(leg, failureClass, status, { fallbackReady = false, limitStop = false, creditStop = false } = {}) {
  const refused = failureClass === "auth" && REFUSED_STATUSES.includes(status);
  if (leg === "api-key") {
    if (failureClass === "credit-stop") return "credit-stop";
    return refused ? "auth" : "";
  }
  if (leg !== "subscription" || !fallbackReady || failureClass === "") return "";
  if (creditStop) return "credit-stop";
  if (refused) return "auth";
  return failureClass === "rate-limit" && limitStop ? "limit-stop" : "";
}

// Every errored run's trace path, resolved as run-validity.py resolves it.
export function erroredTraces(result, base) {
  const traces = [];
  for (const kase of Array.isArray(result?.cases) ? result.cases : []) {
    for (const runs of Object.values(kase?.arms ?? {})) {
      for (const run of Array.isArray(runs) ? runs : []) {
        if (run?.error === null || run?.error === undefined) continue;
        const path = run.tracePath;
        if (typeof path === "string" && path !== "") traces.push(isAbsolute(path) ? path : join(base, path));
      }
    }
  }
  return traces;
}

// One stream's verdict: its class and why it hands off ("" when it does not).
export function judgeStream(text, exitCode, { leg, fallbackReady }, { judgeLeg, linesToMessages, isCreditStop }) {
  const dir = mkdtempSync(join(tmpdir(), "eval-handoff-"));
  try {
    const executionFile = join(dir, "execution.json");
    writeFileSync(executionFile, JSON.stringify(linesToMessages(text)));
    const judged = judgeLeg({ leg: { leg }, executionFile, exitCode, timedOut: false, maxTurns: "" });
    const status = judged.messages.at(-1)?.api_error_status;
    const reason = handoffReason(leg, judged.failureClass, Number.isInteger(status) ? status : null, {
      fallbackReady,
      limitStop: judged.failureClass === "rate-limit" && judged.resets !== null,
      creditStop: leg === "subscription" && isCreditStop(judged.messages, { exitCode }),
    });
    return { failureClass: judged.failureClass, reason };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// The leg's verdict over the probe and every errored run: the first stream
// that hands off decides; otherwise the first stop class any stream shows.
export function judgeLegStreams(streams, options, launcher) {
  let laneClass = "";
  for (const { text, exitCode } of streams) {
    const { failureClass, reason } = judgeStream(text, exitCode, options, launcher);
    if (reason !== "") return { handoff: true, reason, laneClass: failureClass };
    if (laneClass === "" && STOP_CLASSES.includes(failureClass)) laneClass = failureClass;
  }
  return { handoff: false, reason: "", laneClass };
}

// A suite the credential stopped before its runs finished.
function authFailed(result) {
  return result?.partial === true && result.partialReason === "auth_failed";
}

// The streams' verdict, overruled by a suite that ended auth_failed unless a
// stream already handed off.
export function withPartials(verdict, results, { leg, fallbackReady }) {
  if (verdict.handoff || !results.some(authFailed)) return verdict;
  const reason = handoffReason(leg, "auth", REFUSED_STATUSES[0], { fallbackReady });
  return { handoff: reason !== "", reason, laneClass: "auth" };
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

// The classifier's four files (lane.cjs and the three it requires), copied
// under a folder of their own whose package.json ends Node's package-scope
// lookup there. Required in place, the lookup climbs past the sparse checkout
// to the workspace root, and a package.json there that does not parse stops
// the require (run 42138674762).
export const CLASSIFIER_FILES = [
  ".github/actions/run-claude-cli/lane.cjs",
  ".github/actions/run-claude-cli/managed-settings.cjs",
  ".github/actions/report-lane-outcome/classify.cjs",
  ".github/scripts/resolve-npm-tool-version.cjs",
];
export function loadLauncher(root) {
  const dir = mkdtempSync(join(tmpdir(), "eval-handoff-classifier-"));
  try {
    writeFileSync(join(dir, "package.json"), '{"type":"commonjs"}\n');
    for (const path of CLASSIFIER_FILES) {
      mkdirSync(dirname(join(dir, path)), { recursive: true });
      copyFileSync(join(root, path), join(dir, path));
    }
    const require = createRequire(join(dir, CLASSIFIER_FILES[0]));
    const { judgeLeg, linesToMessages } = require("./lane.cjs");
    const { isCreditStop } = require("../report-lane-outcome/classify.cjs");
    return { judgeLeg, linesToMessages, isCreditStop };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function main(env) {
  const leg = LEGS[env.LEG];
  if (!leg) throw new Error(`LEG must be key, subscription or fallback, not ${JSON.stringify(env.LEG)}`);
  const launcher = loadLauncher(env.CI_WORKFLOWS ?? "");
  const streams = [];
  if (env.PROBE && existsSync(env.PROBE)) {
    const exitCode = Number.parseInt(env.PROBE_EXIT ?? "", 10);
    streams.push({ text: readFileSync(env.PROBE, "utf8"), exitCode: Number.isInteger(exitCode) ? exitCode : 1 });
  }
  let seconds = null;
  let cost = null;
  const results = [];
  const add = (sum, value) => (typeof value === "number" && value >= 0 ? (sum ?? 0) + value : sum);
  for (const file of (env.RESULTS ?? "").split("\n").filter(Boolean)) {
    const result = readJson(file);
    results.push(result);
    seconds = add(seconds, result?.durationSeconds);
    cost = add(cost, result?.costUsd);
    for (const trace of erroredTraces(result, dirname(file))) {
      if (existsSync(trace)) streams.push({ text: readFileSync(trace, "utf8"), exitCode: 1 });
    }
  }
  const options = { leg, fallbackReady: env.FALLBACK_READY === "true" };
  const verdict = withPartials(judgeLegStreams(streams, options, launcher), results, options);
  if (env.LEG_RESULT) {
    const message = {
      type: "result",
      subtype: verdict.laneClass === "" ? "success" : "error_during_execution",
      is_error: verdict.laneClass !== "",
      ...(seconds === null ? {} : { duration_ms: Math.round(seconds * 1000) }),
      ...(cost === null ? {} : { total_cost_usd: cost }),
    };
    writeFileSync(env.LEG_RESULT, `${JSON.stringify([message])}\n`);
  }
  return [
    `handoff=${verdict.handoff}`,
    `handoff-reason=${verdict.reason}`,
    `lane-class=${verdict.laneClass}`,
    `outcome=${verdict.laneClass === "" ? "success" : "failure"}`,
  ].join("\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    console.log(main(process.env));
  } catch (error) {
    console.error(`eval-handoff: ${error.message}`);
    process.exit(2);
  }
}
