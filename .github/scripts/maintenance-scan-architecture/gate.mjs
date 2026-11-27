import { execFileSync } from "node:child_process";
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { budgetedClient } from "../lib/github-rest.mjs";
import { countOpen, LANE, openItemCap, SOURCE_LABEL } from "./lane.mjs";

export const WORKFLOW = `${LANE}.yml`;
export const SCAN_DONE_JOB = "Scan";
export const DEFAULT_EVERY_DAYS = 1;
const RUNS_PAGE = 100;
const CALL_BUDGET = 1000;
const DAY_MS = 86_400_000;
const PROMPT_TEMPLATE = fileURLToPath(new URL("./prompt.md", import.meta.url));

const dayOf = (ms) => Math.floor(ms / DAY_MS);

export function laneSettings(doc, lane = LANE) {
  const section = doc?.lanes?.[lane];
  if (section === undefined) throw new Error(`pr-pipeline.yaml has no lane ${lane}`);
  return { enabled: section.enabled ?? true, everyDays: section["every-days"] ?? DEFAULT_EVERY_DAYS };
}

export function decide({ enabled, everyDays, cap, open, lastScan, merges, now, force = false }) {
  const stop = (reason) => ({ run: false, reason, room: Math.max(0, cap - open) });
  if (!enabled && !force) return stop("lane-off");
  if (open >= cap) return stop("at-cap");
  if (lastScan !== null && !force && dayOf(now) - dayOf(lastScan.at) < everyDays) return stop("not-due");
  if (lastScan !== null && merges === 0) return stop("no-merges");
  return { run: true, reason: lastScan === null ? "first-scan" : "due", room: cap - open };
}

export function configStop({ enabled, cap, force = false }) {
  if (!enabled && !force) return "lane-off";
  if (cap === 0) return "at-cap";
  return null;
}

export async function lastScan(call, repository, { workflow = WORKFLOW, perPage = RUNS_PAGE } = {}) {
  for (let page = 1; ; page += 1) {
    const listing = await call("GET", `/repos/${repository}/actions/workflows/${workflow}/runs?branch=main&status=completed&per_page=${perPage}&page=${page}`);
    const runs = listing?.workflow_runs ?? [];
    for (const run of runs) {
      const jobs = (await call("GET", `/repos/${repository}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs ?? [];
      if (jobs.some((job) => job.name === SCAN_DONE_JOB && job.conclusion === "success")) {
        return { at: Date.parse(run.created_at), sha: run.head_sha, run: run.id };
      }
    }
    if (runs.length < perPage) return null;
  }
}

const git = (root, args) => execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

export function mergesSince(root, scan) {
  try {
    return Number(git(root, ["rev-list", "--count", "--first-parent", `${scan.sha}..HEAD`]));
  } catch {
    return Number(git(root, ["rev-list", "--count", "--first-parent", `--since=${new Date(scan.at).toISOString()}`, "HEAD"]));
  }
}

const REASONS = {
  "lane-off": `the lane is off (lanes.${LANE}.enabled in docs/conventions/pr-pipeline.yaml)`,
  "at-cap": `the open \`${SOURCE_LABEL}\` issues are at or above find_open_item_cap`,
  "not-due": `fewer days than lanes.${LANE}.every-days passed since the last scan`,
  "no-merges": "nothing merged to main since the last scan",
  "first-scan": "no earlier scan was found",
  due: "the cadence has passed and main moved since the last scan",
};
export const explain = (reason) => REASONS[reason];

export async function readLaneSettings(root, standardsDir) {
  const { configFromBase } = await import("../../actions/resolve-config/resolve-config.mjs");
  return laneSettings(configFromBase({ BASE_PATH: root, STANDARDS_DIR: standardsDir }));
}

export async function gate({ root, env, call, now = Date.now() }) {
  const settings = await readLaneSettings(root, env.STANDARDS_DIR);
  const capping = openItemCap(root);
  const force = env.EVENT_NAME === "workflow_dispatch" && env.FORCE === "true";
  const unread = { force, open: null, cap: capping.cap, capSource: capping.source, warnings: capping.warnings, ...settings, lastScan: null, merges: null };
  const early = configStop({ ...settings, cap: capping.cap, force });
  if (early !== null) return { run: false, reason: early, room: 0, ...unread };
  const open = await countOpen(call, env.REPOSITORY, SOURCE_LABEL, capping.cap);
  const scan = await lastScan(call, env.REPOSITORY);
  const merges = scan === null ? null : mergesSince(root, scan);
  const result = decide({ ...settings, cap: capping.cap, open, lastScan: scan, merges, now, force });
  return { ...result, force, open, cap: capping.cap, capSource: capping.source, warnings: capping.warnings, ...settings, lastScan: scan, merges };
}

export function promptText(room) {
  if (!Number.isSafeInteger(room) || room < 1) throw new Error(`room ${JSON.stringify(room)} is not a positive integer`);
  return readFileSync(PROMPT_TEMPLATE, "utf8").replaceAll("ROOM", String(room)).replaceAll("SOURCE_LABEL", SOURCE_LABEL);
}

const MODEL_TOOLS = fileURLToPath(new URL("./model-tools.json", import.meta.url));

export function modelTools(workspace) {
  if (!/^\/[^\s*()]+$/.test(workspace ?? "")) throw new Error(`the workspace ${JSON.stringify(workspace)} is no absolute path without spaces, stars or parentheses`);
  const { allowed, disallowed } = JSON.parse(readFileSync(MODEL_TOOLS, "utf8"));
  const fill = (rules) => rules.map((rule) => rule.replaceAll("WORKSPACE", workspace));
  return { allowed: fill(allowed), disallowed: fill(disallowed) };
}

const multiline = (name, lines) => `${name}<<TOOLS_EOF\n${lines.join("\n")}\nTOOLS_EOF\n`;

export function statusLine(result) {
  const merges = result.merges ?? "n/a";
  const open = result.open ?? "n/a";
  const forced = result.force ? ", forced" : "";
  return `${result.run ? "scan" : "stop"} ${result.reason}: ${explain(result.reason)} (open ${open} of cap ${result.cap} from the ${result.capSource} layer, every ${result.everyDays} day(s), merges since the last scan ${merges}${forced})`;
}

async function main(argv, env) {
  const [command] = argv;
  if (command === "prompt") {
    writeFileSync(env.PROMPT_FILE, promptText(Number(env.ROOM)));
    const { allowed, disallowed } = modelTools(env.GITHUB_WORKSPACE);
    appendFileSync(env.GITHUB_OUTPUT, multiline("allowed-tools", allowed) + multiline("disallowed-tools", disallowed));
    return 0;
  }
  if (command !== "gate") {
    console.error("usage: gate.mjs gate | prompt");
    return 2;
  }
  const call = budgetedClient(env, { budget: CALL_BUDGET });
  const result = await gate({ root: env.BASE_DIR, env, call });
  for (const warning of result.warnings) console.log(`::warning::${warning}`);
  const line = statusLine(result);
  console.log(`::group::gate result: ${result.run ? "scan" : `stop ${result.reason}`}`);
  console.log(JSON.stringify(result, null, 2));
  console.log("::endgroup::");
  console.log(`::notice::${line}`);
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `Architecture scan gate: ${line}\n`);
  if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `run=${result.run}\nreason=${result.reason}\nroom=${result.room}\ncap=${result.cap}\nenabled=${result.enabled}\n`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2), process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::architecture scan gate: ${String(error.message).split("\n")[0]}`);
      process.exitCode = 1;
    },
  );
}
