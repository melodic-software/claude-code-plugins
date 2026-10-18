#!/usr/bin/env node
// check-wip-cap.mjs: the issue lane's WIP cap, from three serial searches
// over the lanes App's pull requests in this repository: the open ones, the
// ones merged in the rolling window, and the ones opened in it.
//
// The cap is the merged count per hour times wip.target-lead-time-hours,
// rounded up and at least 1 (limits.wip-cap when the merged count cannot be
// read). Only open PRs that are not held count against it. A held PR (label
// needs-human or do-not-merge, or a body line exactly HOLD_LINE) counts
// against wip.held-cap instead, and one older than wip.held-alarm-hours
// raises the alarm. PRs opened in the window may be at most
// wip.admission-factor times those merged in it. Over a cap, or on the alarm,
// the check alerts; it pauses the lane (work-resolve-issue starts no run,
// work-unblock re-fires none) only over a cap on or after wip.pause-from. A
// read that fails never caps.
//
// As the action's step it writes `capped` (the pause) and `wip` (the status
// as one flat JSON object), and the same object to the step summary and log.
// Environment:
//   GITHUB_TOKEN        the job's own token (pull-requests: read)
//   GITHUB_REPOSITORY   owner/repo
//   GITHUB_API_URL
//   BASE_PATH           the default-branch checkout whose pr-pipeline.yaml
//                       sets limits and wip (resolve-config's wipFromBase)
//   LANES_BOT_LOGIN     the lanes App bot login (default melodic-automation-lanes[bot])
//   GITHUB_OUTPUT, GITHUB_STEP_SUMMARY
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { createGitHub } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { LIMIT_DEFAULTS, resolveWip } from "../../scripts/work-resolve-issue/limits.mjs";

const DEFAULT_BOT = "melodic-automation-lanes[bot]";
const HOUR_MS = 3_600_000;
export const HOLD_LABELS = new Set(["needs-human", "do-not-merge"]);
export const HOLD_LINE = "Hold: a human merges this";
// The search API returns at most 1000 results, 100 per page.
const PAGE = 100;
const MAX_PAGES = 10;

export const isHeld = (pr) =>
  (pr?.labels ?? []).some((label) => HOLD_LABELS.has(label?.name)) ||
  String(pr?.body ?? "")
    .split(/\r?\n/)
    .includes(HOLD_LINE);

const isoSecond = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
const isCount = (value) => Number.isSafeInteger(value) && value >= 0;

// The open lane PRs as { createdAt, held }, the merged and opened counts in
// the window; each null when its read fails. Reads run one at a time, and
// none starts once `remaining()` (the last x-ratelimit-remaining seen) is 0 or less.
export async function readLaneWip(github, { repo, bot = DEFAULT_BOT, now, windowHours, remaining = () => null }) {
  const author = `author:app/${bot.replace(/\[bot\]$/, "")}`;
  const since = isoSecond(now - windowHours * HOUR_MS);
  const search = async (q, page, perPage) => {
    const left = remaining();
    if (left !== null && left <= 0) {
      throw new Error("the rate limit has no requests left");
    }
    return github("GET", `/search/issues?q=${encodeURIComponent(q)}&per_page=${perPage}&page=${page}`);
  };
  const count = async (q) => {
    try {
      const total = (await search(q, 1, 1))?.total_count;
      return isCount(total) ? total : null;
    } catch {
      return null;
    }
  };
  let open = [];
  try {
    for (let page = 1; page <= MAX_PAGES; page += 1) {
      const items = (await search(`repo:${repo} is:pr is:open ${author}`, page, PAGE))?.items;
      if (!Array.isArray(items)) {
        throw new Error("the search answered no items");
      }
      open.push(...items.map((pr) => ({ createdAt: Date.parse(pr?.created_at), held: isHeld(pr) })));
      if (items.length < PAGE) {
        break;
      }
    }
  } catch {
    open = null;
  }
  const merged = await count(`repo:${repo} is:pr is:merged ${author} merged:>=${since}`);
  const admitted = await count(`repo:${repo} is:pr ${author} created:>=${since}`);
  return { open, merged, admitted };
}

const round = (value, places) => (value === null ? null : Number(value.toFixed(places)));

// The status as one flat object; the field names are a published contract
// (README.md, WIP cap).
export function wipStatus({ open, merged, admitted }, { limits, wip, now }) {
  const window = wip["merge-rate-window-hours"];
  const held = open?.filter((pr) => pr.held) ?? null;
  const ages = held?.map((pr) => (now - pr.createdAt) / HOUR_MS).filter(Number.isFinite) ?? [];
  const computed = merged !== null;
  const wipCap = computed ? Math.max(1, Math.ceil((merged * wip["target-lead-time-hours"]) / window - 1e-9)) : limits["wip-cap"];
  const admissionCap = computed ? Math.floor(wip["admission-factor"] * merged + 1e-9) : null;
  const countable = open === null ? null : open.length - held.length;
  const heldCount = held === null ? null : held.length;
  const heldOver24h = held === null ? null : ages.filter((age) => age > wip["held-alarm-hours"]).length;
  const wipOver = countable !== null && countable >= wipCap;
  const heldOver = heldCount !== null && heldCount >= wip["held-cap"];
  const admissionOver = admitted !== null && admissionCap !== null && admitted > admissionCap;
  const heldAlarm = heldOver24h !== null && heldOver24h > 0;
  const pauseFrom = wip["pause-from"];
  return {
    countable_lane_prs: countable,
    held_lane_prs: heldCount,
    held_oldest_age_hours: ages.length === 0 ? null : round(Math.max(...ages), 1),
    held_over_24h_count: heldOver24h,
    wip_cap: wipCap,
    wip_cap_source: computed ? "computed" : "config",
    held_cap: wip["held-cap"],
    held_alarm_hours: wip["held-alarm-hours"],
    merged_lane_prs_window: merged,
    merge_rate_per_hour: computed ? round(merged / window, 3) : null,
    merge_rate_window_hours: window,
    target_lead_time_hours: wip["target-lead-time-hours"],
    admitted_lane_prs_window: admitted,
    admission_cap: admissionCap,
    admission_factor: wip["admission-factor"],
    wip_over: wipOver,
    held_over: heldOver,
    admission_over: admissionOver,
    held_alarm: heldAlarm,
    alert: wipOver || heldOver || admissionOver || heldAlarm,
    pause_from: pauseFrom,
    paused: (wipOver || heldOver) && pauseFrom !== "" && now >= Date.parse(pauseFrom),
  };
}

// The status from the lanes App's PRs in `repo`, for the issue lane's check
// and work-unblock's sweep alike.
export async function checkWip(github, { repo, bot, now, limits, wip, remaining }) {
  const reads = await readLaneWip(github, { repo, bot, now, windowHours: wip["merge-rate-window-hours"], remaining });
  return wipStatus(reads, { limits, wip, now });
}

const escape = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

async function baseConfig(basePath, log) {
  try {
    const { wipFromBase } = await import(new URL("../resolve-config/resolve-config.mjs", import.meta.url).href);
    const { limits, wip } = wipFromBase({ BASE_PATH: basePath });
    return { limits, wip: resolveWip(wip) };
  } catch (error) {
    log(`::warning title=check-wip-cap::the base config could not be read (${escape(error?.message ?? error)}); the defaults apply`);
    return { limits: LIMIT_DEFAULTS, wip: resolveWip(undefined) };
  }
}

const alertText = (s) =>
  [
    s.wip_over && `${s.countable_lane_prs} countable lane PRs are at or over the WIP cap of ${s.wip_cap}`,
    s.held_over && `${s.held_lane_prs} held lane PRs are at or over the held cap of ${s.held_cap}`,
    s.admission_over && `${s.admitted_lane_prs_window} lane PRs opened in ${s.merge_rate_window_hours} h, over the admission cap of ${s.admission_cap}`,
    s.held_alarm && `${s.held_over_24h_count} held lane PRs are older than ${s.held_alarm_hours} h`,
  ]
    .filter(Boolean)
    .join("; ");

export async function main({ env = process.env, github, now = Date.now(), log = console.log } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  const { limits, wip } = await baseConfig(env.BASE_PATH || ".base", log);
  let remaining = null;
  github ??= createGitHub({
    token: env.GITHUB_TOKEN,
    apiUrl: env.GITHUB_API_URL || undefined,
    onResponse: (response) => {
      const left = Number.parseInt(response.headers?.get?.("x-ratelimit-remaining") ?? "", 10);
      remaining = Number.isSafeInteger(left) ? left : remaining;
    },
  });
  const valid = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo);
  const reads = valid
    ? await readLaneWip(github, { repo, bot: env.LANES_BOT_LOGIN || DEFAULT_BOT, now, windowHours: wip["merge-rate-window-hours"], remaining: () => remaining })
    : { open: null, merged: null, admitted: null };
  const status = wipStatus(reads, { limits, wip, now });
  const json = JSON.stringify(status);
  writeOutputs({ capped: String(status.paused), wip: json }, env.GITHUB_OUTPUT);
  if (env.GITHUB_STEP_SUMMARY) {
    appendFileSync(env.GITHUB_STEP_SUMMARY, `### Issue-lane WIP cap\n\n\`\`\`json\n${json}\n\`\`\`\n`);
  }
  if (status.countable_lane_prs === null) {
    log(`::warning title=check-wip-cap::the open lane PRs could not be listed, so the run starts (cap ${status.wip_cap})`);
  }
  if (status.alert) {
    log(
      `::warning title=check-wip-cap::${escape(alertText(status))}; ${status.paused ? "this run starts no work and work-unblock re-fires it once under the caps" : "the lane keeps running (pause-from not reached)"}`,
    );
  }
  log(`check-wip-cap: ${json}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
