#!/usr/bin/env node
// check-wip-cap.mjs: the issue lane's WIP cap, from three serial searches
// over the lanes App's pull requests in this repository: the open ones, the
// ones merged in the rolling window, and the ones opened in it.
//
// The cap is the merged count per hour times wip.target-lead-time-hours,
// rounded up and at least wip.min-cap (limits.wip-cap when the merged count
// cannot be read). Only open PRs that are not held count against it. A held PR (label
// needs-human or do-not-merge, or a body line exactly HOLD_LINE) counts
// against wip.held-cap instead, and one older than wip.held-alarm-hours
// raises the alarm. PRs opened in the window may be at most
// wip.opened-to-merged-ratio times those merged in it. Over a cap, or on the alarm,
// the check alerts; over the WIP cap or the held cap, on or after
// wip.pause-from, it pauses the lane (work-resolve-issue starts no run,
// work-unblock re-fires none) and logs one `admission paused: reason=...`
// line. When a read fails (the open listing, the base config) the lane keeps
// the last known pause, the status work-unblock's hourly sweep last saved in
// WIP_STATE; with none it fails open.
//
// As the action's step it writes `capped` (the pause), `wip` (the status
// as one flat JSON object) and `state-saved` (`true` when a read that
// succeeded wrote its status to WIP_STATE), and the status to the step
// summary and log.
// Environment:
//   GITHUB_TOKEN        the job's own token (pull-requests: read)
//   GITHUB_REPOSITORY   owner/repo
//   GITHUB_API_URL
//   BASE_PATH           the default-branch checkout whose pr-pipeline.yaml
//                       sets limits and wip (resolve-config's wipFromBase)
//   LANES_BOT_LOGIN     the lanes App bot login (default melodic-automation-lanes[bot])
//   WIP_STATE           the last known state file (optional), read then rewritten
//   GITHUB_OUTPUT, GITHUB_STEP_SUMMARY
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
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
    const answer = await github("GET", `/search/issues?q=${encodeURIComponent(q)}&per_page=${perPage}&page=${page}`);
    if (answer?.incomplete_results !== false) {
      throw new Error("the search answered incomplete results");
    }
    return answer;
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
  const wipCap = computed ? Math.max(wip["min-cap"], Math.ceil((merged * wip["target-lead-time-hours"]) / window - 1e-9)) : limits["wip-cap"];
  const admissionCap = computed ? Math.floor(wip["opened-to-merged-ratio"] * merged + 1e-9) : null;
  const countable = open === null ? null : open.length - held.length;
  const heldCount = held === null ? null : held.length;
  const heldOverAlarm = held === null ? null : ages.filter((age) => age > wip["held-alarm-hours"]).length;
  const wipOver = countable !== null && countable >= wipCap;
  const heldOver = heldCount !== null && heldCount >= wip["held-cap"];
  const admissionOver = admitted !== null && admissionCap !== null && admitted > admissionCap;
  const heldAlarm = heldOverAlarm !== null && heldOverAlarm > 0;
  const pauseFrom = wip["pause-from"];
  const pausing = pauseFrom !== "" && now >= Date.parse(pauseFrom);
  const reasons = [wipOver && "wip", heldOver && "held-cap"].filter(Boolean);
  return {
    countable_lane_prs: countable,
    held_lane_prs: heldCount,
    held_oldest_age_hours: ages.length === 0 ? null : round(Math.max(...ages), 1),
    held_over_alarm_count: heldOverAlarm,
    wip_cap: wipCap,
    wip_cap_source: computed ? "computed" : "config",
    wip_min_cap: wip["min-cap"],
    held_cap: wip["held-cap"],
    held_alarm_hours: wip["held-alarm-hours"],
    merged_lane_prs_window: merged,
    merge_rate_per_hour: computed ? round(merged / window, 3) : null,
    merge_rate_window_hours: window,
    target_lead_time_hours: wip["target-lead-time-hours"],
    admitted_lane_prs_window: admitted,
    admission_cap: admissionCap,
    opened_to_merged_ratio: wip["opened-to-merged-ratio"],
    wip_over: wipOver,
    held_over: heldOver,
    admission_over: admissionOver,
    held_alarm: heldAlarm,
    alert: wipOver || heldOver || admissionOver || heldAlarm,
    pause_from: pauseFrom,
    paused: pausing && reasons.length > 0,
    pause_reason: pausing && reasons.length > 0 ? reasons.join(",") : null,
  };
}

// The status from the lanes App's PRs in `repo`, for the issue lane's check
// and work-unblock's sweep alike.
export async function checkWip(github, { repo, bot, now, limits, wip, remaining }) {
  const reads = await readLaneWip(github, { repo, bot, now, windowHours: wip["merge-rate-window-hours"], remaining });
  return wipStatus(reads, { limits, wip, now });
}

// The last x-ratelimit-remaining a search response carried, for readLaneWip's
// stop; a response counted against another rate-limit resource leaves it as is.
export function searchRateLimit() {
  let left = null;
  return {
    onResponse: (response) => {
      const value = Number.parseInt(response.headers?.get?.("x-ratelimit-remaining") ?? "", 10);
      if ((response.headers?.get?.("x-ratelimit-resource") ?? "search") === "search" && Number.isSafeInteger(value)) {
        left = value;
      }
    },
    remaining: () => left,
  };
}

const PAUSE_REASONS = new Set(["wip", "held-cap", "wip,held-cap"]);

// The last known state: a previous run's status, or null when there is none
// or it names a pause reason wipStatus never writes.
function lastState(path) {
  try {
    const prior = JSON.parse(readFileSync(path, "utf8"));
    const valid = prior?.paused === false || (prior?.paused === true && PAUSE_REASONS.has(prior.pause_reason));
    return valid ? prior : null;
  } catch {
    return null;
  }
}

// The status with `pause_basis`: `read`, or on a failed read the last known
// pause (`last-state`), or with none the open lane (`fail-open`). A config
// that was read and no longer pauses (`pausing` false) ends a kept pause.
export function keepLastState(status, { readError, prior, pausing = true }) {
  if (!readError) {
    return { ...status, pause_basis: "read" };
  }
  if (prior === null) {
    return { ...status, pause_basis: "fail-open" };
  }
  const paused = prior.paused && pausing;
  const reason = paused ? prior.pause_reason : null;
  return { ...status, paused, pause_reason: reason, pause_basis: "last-state" };
}

const escape = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

async function baseConfig(basePath, log) {
  try {
    const { wipFromBase } = await import(new URL("../resolve-config/resolve-config.mjs", import.meta.url).href);
    const { limits, wip } = wipFromBase({ BASE_PATH: basePath });
    return { limits, wip: resolveWip(wip), configError: false };
  } catch (error) {
    log(`::warning title=check-wip-cap::the base config could not be read (${escape(error?.message ?? error)}); the defaults apply`);
    return { limits: LIMIT_DEFAULTS, wip: resolveWip(undefined), configError: true };
  }
}

const alertText = (s) =>
  [
    s.wip_over && `${s.countable_lane_prs} countable lane PRs are at or over the WIP cap of ${s.wip_cap}`,
    s.held_over && `${s.held_lane_prs} held lane PRs are at or over the held cap of ${s.held_cap}`,
    s.admission_over && `${s.admitted_lane_prs_window} lane PRs opened in ${s.merge_rate_window_hours} h, over the admission cap of ${s.admission_cap}`,
    s.held_alarm && `${s.held_over_alarm_count} held lane PRs are older than ${s.held_alarm_hours} h`,
  ]
    .filter(Boolean)
    .join("; ");

export async function main({ env = process.env, github, now = Date.now(), log = console.log } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  const { limits, wip, configError } = await baseConfig(env.BASE_PATH || ".base", log);
  const rate = searchRateLimit();
  github ??= createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse: rate.onResponse });
  const read = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)
    ? await checkWip(github, { repo, bot: env.LANES_BOT_LOGIN || DEFAULT_BOT, now, limits, wip, remaining: rate.remaining })
    : wipStatus({ open: null, merged: null, admitted: null }, { limits, wip, now });
  const readError = configError || read.countable_lane_prs === null;
  const pausing = configError || (wip["pause-from"] !== "" && now >= Date.parse(wip["pause-from"]));
  const status = keepLastState(read, { readError, prior: readError && env.WIP_STATE ? lastState(env.WIP_STATE) : null, pausing });
  const json = JSON.stringify(status);
  const saved = !readError && Boolean(env.WIP_STATE);
  if (saved) {
    writeFileSync(env.WIP_STATE, json);
  }
  writeOutputs({ capped: String(status.paused), wip: json, "state-saved": String(saved) }, env.GITHUB_OUTPUT);
  if (env.GITHUB_STEP_SUMMARY) {
    appendFileSync(env.GITHUB_STEP_SUMMARY, `### Issue-lane WIP cap\n\n\`\`\`json\n${json}\n\`\`\`\n`);
  }
  if (readError) {
    log(
      `::warning title=check-wip-cap::${read.countable_lane_prs === null ? "the open lane PRs could not be listed" : "the base config could not be read"}, so ${status.pause_basis === "last-state" ? `the last known state applies (paused ${status.paused})` : "with no last known state the run starts"}`,
    );
  }
  if (status.alert) {
    log(
      `::warning title=check-wip-cap::${escape(alertText(status))}; ${status.paused ? "this run starts no work and work-unblock re-fires it once under both caps" : `the lane keeps running (${status.wip_over || status.held_over ? "pause-from not reached" : "only the WIP and held caps pause it"})`}`,
    );
  }
  if (status.paused) {
    const line =
      status.pause_basis === "last-state"
        ? `admission paused: reason=${status.pause_reason} (read-error, kept last state)`
        : `admission paused: reason=${status.pause_reason} countable=${status.countable_lane_prs} wip_cap=${status.wip_cap} held=${status.held_lane_prs} held_cap=${status.held_cap}`;
    log(`::notice title=admission paused::${escape(line)}`);
    if (env.GITHUB_STEP_SUMMARY) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `\n${line}\n`);
    }
  }
  log(`check-wip-cap: ${json}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
