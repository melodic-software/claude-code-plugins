#!/usr/bin/env node
// check-wip-cap.mjs: whether the lanes App has `limits.wip-cap` or more pull
// requests open in this repository, from one search call. work-resolve-issue
// starts no run at the cap, and work-unblock's sweep re-fires none. A count
// that cannot be read never caps: lane work is not blocked by a read error,
// and the sweep keeps restarts bounded.
//
// As the action's step it writes the `capped` output. Environment:
//   GITHUB_TOKEN        the job's own token (pull-requests: read)
//   GITHUB_REPOSITORY   owner/repo
//   GITHUB_API_URL
//   BASE_PATH           the default-branch checkout whose pr-pipeline.yaml
//                       sets the cap (resolve-config's limitsFromBase)
//   LANES_BOT_LOGIN     the lanes App bot login (default melodic-automation-lanes[bot])
//   GITHUB_OUTPUT
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { createGitHub } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { LIMIT_DEFAULTS } from "../../scripts/work-resolve-issue/limits.mjs";

const DEFAULT_BOT = "melodic-automation-lanes[bot]";

// The open pull requests `bot` authored in `repo`, or null when the search
// fails or answers something other than a count.
export async function openLanePrs(github, { repo, bot = DEFAULT_BOT }) {
  const q = encodeURIComponent(`repo:${repo} is:pr is:open author:app/${bot.replace(/\[bot\]$/, "")}`);
  try {
    const count = (await github("GET", `/search/issues?q=${q}&per_page=1`))?.total_count;
    return Number.isSafeInteger(count) && count >= 0 ? count : null;
  } catch {
    return null;
  }
}

// At or over the cap; an unread count is under it.
export const atCap = (count, limits) => count !== null && count >= limits["wip-cap"];

async function baseLimits(basePath) {
  try {
    const { limitsFromBase } = await import(new URL("../resolve-config/resolve-config.mjs", import.meta.url).href);
    return limitsFromBase({ BASE_PATH: basePath });
  } catch (error) {
    console.log(`::warning title=check-wip-cap::the base config's limits could not be read (${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}); the default cap applies`);
    return LIMIT_DEFAULTS;
  }
}

export async function main({ env = process.env, github } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  const limits = await baseLimits(env.BASE_PATH || ".base");
  github ??= createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
  const count = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) ? await openLanePrs(github, { repo, bot: env.LANES_BOT_LOGIN || DEFAULT_BOT }) : null;
  const capped = atCap(count, limits);
  writeOutputs({ capped: String(capped) }, env.GITHUB_OUTPUT);
  console.log(
    count === null
      ? `::warning title=check-wip-cap::the open lane PRs could not be counted, so the run starts (cap ${limits["wip-cap"]})`
      : capped
        ? `::notice title=check-wip-cap::${count} lane PRs are open, at or over the WIP cap of ${limits["wip-cap"]}; this run starts no work and work-unblock re-fires it once fewer are open`
        : `check-wip-cap: ${count} lane PRs are open, under the WIP cap of ${limits["wip-cap"]}`,
  );
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
