#!/usr/bin/env node
// admission-window.mjs: whether the issue lane's admissions are open. The
// admitted backlog (open issues labeled agent-ready) may hold
// `limits.admission-window-hours` of admissions, admitted at ADMISSION_FACTOR
// times the lane's merge rate over the last 24 hours:
//
//   hourly        = lane PRs merged in the last 24 h / 24
//   release_point = ADMISSION_FACTOR * hourly * admission-window-hours
//   open          = admitted < release_point
//
// Prints one line and exits 0 open, 1 held, 2 on error. Reads the window from
// this checkout's pr-pipeline.yaml through resolve-config (run `npm ci` in
// .github/actions/resolve-config once) and the counts through `gh`.
//
//   node .github/scripts/work-resolve-issue/admission-window.mjs [--repo owner/repo]
import { execFileSync } from "node:child_process";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

// Admissions at or below 0.8 times the merge rate; pr-pipeline.yaml sets no factor.
export const ADMISSION_FACTOR = 0.8;
const LANES_APP = "app/melodic-automation-lanes";
const DAY_MS = 86_400_000;

const gh = (args) => execFileSync("gh", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

// One search's total_count; throws when the answer is no count.
function searchCount(run, q) {
  const answer = run(["api", "-X", "GET", "search/issues", "-f", `q=${q}`, "-f", "per_page=1", "--jq", ".total_count"]);
  if (!/^\d+$/.test(answer)) {
    throw new Error(`search for \`${q}\` answered no count`);
  }
  return Number(answer);
}

export function counts(run, { repo, now }) {
  const since = new Date(now - DAY_MS).toISOString().replace(/\.\d{3}Z$/, "Z");
  return {
    merged24h: searchCount(run, `repo:${repo} is:pr is:merged author:${LANES_APP} merged:>=${since}`),
    admitted: searchCount(run, `repo:${repo} is:issue is:open label:agent-ready`),
  };
}

export function decide({ merged24h, admitted, windowHours, factor = ADMISSION_FACTOR }) {
  const hourly = merged24h / 24;
  const releasePoint = factor * hourly * windowHours;
  return { merged24h, hourly, admitted, releasePoint, open: admitted < releasePoint, allowedPerHour: factor * hourly };
}

const fmt = (x) => String(Number(x.toFixed(2)));

export const formatLine = (d) =>
  `merged24h=${d.merged24h} hourly=${fmt(d.hourly)} admitted=${d.admitted} release_point=${fmt(d.releasePoint)} admissions=${d.open ? "open" : "held"} allowed_per_hour=${fmt(d.allowedPerHour)}`;

async function windowFromConfig() {
  const { limitsFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
  return limitsFromBase({ BASE_PATH: fileURLToPath(new URL("../../../", import.meta.url)) })["admission-window-hours"];
}

export async function main({ argv = process.argv.slice(2), run = gh, loadWindow = windowFromConfig, now = Date.now(), out = console.log, err = console.error } = {}) {
  try {
    const at = argv.indexOf("--repo");
    const repo = at >= 0 ? argv[at + 1] : run(["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]);
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? "")) {
      throw new Error(`no owner/repo (got \`${repo}\`)`);
    }
    const windowHours = await loadWindow();
    const decision = decide({ ...counts(run, { repo, now }), windowHours });
    out(formatLine(decision));
    return decision.open ? 0 : 1;
  } catch (error) {
    err(`admission-window: ${String(error?.message ?? error).split("\n")[0]}`);
    return 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
