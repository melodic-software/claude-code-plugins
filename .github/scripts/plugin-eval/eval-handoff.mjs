#!/usr/bin/env node
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const LEGS = { key: "api-key", subscription: "subscription", fallback: "fallback" };
const AUTH_FAILED_STATUS = 401;
const STOP_CLASSES = ["credit-stop", "auth", "rate-limit", "overloaded"];

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

export function judgeStream(text, exitCode, { leg, fallbackReady }, { judgeLeg, linesToMessages, isCreditStop, handoffReason }) {
  const dir = mkdtempSync(join(tmpdir(), "eval-handoff-"));
  try {
    const executionFile = join(dir, "execution.json");
    writeFileSync(executionFile, JSON.stringify(linesToMessages(text)));
    const judged = judgeLeg({ leg: { leg }, executionFile, exitCode, timedOut: false, maxTurns: "" });
    const status = judged.messages.at(-1)?.api_error_status;
    const reason = handoffReason({ leg }, judged.failureClass, Number.isInteger(status) ? status : null, {
      fallbackReady,
      limitStop: judged.failureClass === "rate-limit" && judged.resets !== null,
      creditStop: leg === "subscription" && isCreditStop(judged.messages, { exitCode }),
    });
    return { failureClass: judged.failureClass, reason };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

export function judgeLegStreams(streams, options, launcher) {
  let laneClass = "";
  for (const { text, exitCode } of streams) {
    const { failureClass, reason } = judgeStream(text, exitCode, options, launcher);
    if (reason !== "") return { handoff: true, reason, laneClass: failureClass };
    if (laneClass === "" && STOP_CLASSES.includes(failureClass)) laneClass = failureClass;
  }
  return { handoff: false, reason: "", laneClass };
}

function authFailed(result) {
  return result?.partial === true && result.partialReason === "auth_failed";
}

export function withPartials(verdict, results, { leg, fallbackReady }, { handoffReason }) {
  if (verdict.handoff || !results.some(authFailed)) return verdict;
  const reason = handoffReason({ leg }, "auth", AUTH_FAILED_STATUS, { fallbackReady });
  return { handoff: reason !== "", reason, laneClass: "auth" };
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

export const CONTRACT = ".github/actions/run-claude-cli/contract.cjs";
export const CONTRACT_FILES = ".github/actions/run-claude-cli/contract-files.txt";
export const contractFiles = (manifest) => manifest.split("\n").map((line) => line.trim()).filter(Boolean);

export function loadContract(root) {
  const dir = mkdtempSync(join(tmpdir(), "eval-handoff-contract-"));
  try {
    writeFileSync(join(dir, "package.json"), '{"type":"commonjs"}\n');
    for (const path of contractFiles(readFileSync(join(root, CONTRACT_FILES), "utf8"))) {
      mkdirSync(dirname(join(dir, path)), { recursive: true });
      copyFileSync(join(root, path), join(dir, path));
    }
    return createRequire(join(dir, "package.json"))(`./${CONTRACT}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function main(env) {
  const leg = LEGS[env.LEG];
  if (!leg) throw new Error(`LEG must be key, subscription or fallback, not ${JSON.stringify(env.LEG)}`);
  const launcher = loadContract(env.CI_WORKFLOWS ?? "");
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
  const verdict = withPartials(judgeLegStreams(streams, options, launcher), results, options, launcher);
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
