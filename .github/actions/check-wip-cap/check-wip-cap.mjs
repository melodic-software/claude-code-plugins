#!/usr/bin/env node
// check-wip-cap.mjs: the issue lane's WIP cap and admission pace, from three
// serial searches for the lanes App's pull requests in this repository (the
// open ones, the ones merged in the rolling window, and the ones opened in it),
// then the open agent-ready issues, oldest first, with hold labels left out:
// from one Work status listing (listedStatusOf), where the field decides
// agent-ready and adds a hold the labels lack, or, with models.issue-status
// unset, the repository issues listing by the agent-ready label, pull requests
// left out; and one pull request read per open lane PR whose first body line
// names no issue.
//
// The cap is the merged count per hour times wip.target-lead-time-hours,
// rounded up and at least wip.min-cap (limits.wip-cap when the merged count
// cannot be read). Only open PRs that are not held count against it. A held PR (label
// needs-human or do-not-merge in any case, or a body line exactly HOLD_LINE) counts
// against wip.held-cap instead, and one older than wip.held-alarm-hours
// raises the alarm. PRs opened in the window may be at most
// wip.opened-to-merged-ratio times those merged in it. Over a cap, or on the alarm,
// the check alerts; over the WIP cap or the held cap, on or after
// wip.pause-from, it pauses the lane (work-resolve-issue starts no run,
// work-unblock re-fires none) and logs one `admission paused: reason=...`
// line. When a read the pause depends on fails (the open listing, the base
// config) the pause is unknown and the run holds: `capped` is
// `true`,`pause_basis` is `unknown`, and one `::notice` names the hold. No
// earlier state decides it; work-unblock's next sweep re-fires the run, which
// reads again. A base config that cannot be read also closes admissions,
// whatever wip.pause-from says.
//
// Queued work is the agent-ready issues no open lane PR names, on its first
// body line or else by its lane branch, and no blocker still blocks (at most
// BLOCKER_READS blocker reads), plus the held lane PRs. At or over the queued cap,
// max(limits.admission-factor x lane merges per hour, limits.admission-min-per-hour)
// x wip.merge-rate-window-hours, on or after wip.pause-from, new admissions
// (work-unblock adding agent-ready) pause; runs never pause on it, since a
// queued issue leaves the count only by running. A search that answers
// incomplete_results: true closes admissions whatever wip.pause-from says. A
// failed queued listing leaves admissions open here (`admission_basis`
// `fail-open`), which admit.mjs and work-unblock treat as no room.
//
// With `pauseOnly` (WIP_READS=pause) it makes only the open listing and the
// merged count, the two reads the run pause depends on, and leaves the
// admission fields unread (`admission_basis` `not-read`, admissions open, unless
// a search answered incomplete or the base config could not be read).
//
// As the action's step it writes `capped` (the run pause, or a hold on an
// unknown pause), `admission-open` and `wip` (the status as one flat JSON
// object), and the status to the step summary and log.
// Environment:
//   GITHUB_TOKEN        the job's own token (pull-requests: read, issues: read)
//   GITHUB_REPOSITORY   owner/repo
//   GITHUB_API_URL
//   BASE_PATH           the default-branch checkout whose pr-pipeline.yaml
//                       sets limits and wip (resolve-config's wipFromBase)
//   LANES_BOT_LOGIN     the lanes App bot login (default melodic-automation-lanes[bot])
//   WIP_READS           `pause` for the pause reads alone; anything else reads all
//   GITHUB_OUTPUT, GITHUB_STEP_SUMMARY
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { createGitHub } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { loadTrustedActors, StatusReadError, statusLabels } from "../resolve-config/read-status.mjs";
import { blockersOf, stillBlocking } from "../../scripts/intake-triage/admit.mjs";
import { LIMIT_DEFAULTS, resolveAdmission, resolveWip } from "../../scripts/work-resolve-issue/limits.mjs";
import { laneBranchIssue } from "../../scripts/work-resolve-issue/report-outcome.mjs";

const DEFAULT_BOT = "melodic-automation-lanes[bot]";
const HOUR_MS = 3_600_000;
export const HOLD_LABELS = new Set(["needs-human", "do-not-merge"]);
export const HOLD_LINE = "Hold: a human merges this";
// Issue labels that keep an issue off the issue lane: those a person decides,
// and host-run and attended, whose Work status stays agent-ready while a host
// session or the owner takes the step. An issue carrying one, in any case, is
// not queued work.
const ISSUE_HOLDS = new Set(["needs-human", "needs-owner-decision", "needs-reporter-info", "host-run", "attended"]);
const lowered = (names) => names.filter((name) => typeof name === "string").map((name) => name.toLowerCase());
// Whether label names (with the Work status field's hold added, read-status.mjs)
// make a listed issue queued work: agent-ready and no hold.
const isQueued = (names) => {
  const labels = lowered(names);
  return labels.includes("agent-ready") && !labels.some((name) => ISSUE_HOLDS.has(name));
};
// The issue a lane PR's first body line names, as report-outcome writes it.
const NAMES_ISSUE = /^(?:Closes|Refs:) #([1-9][0-9]*)$/;
// The search API returns at most 1000 results, 100 per page; the queued
// listing stops at the same 10 pages.
const PAGE = 100;
const MAX_PAGES = 10;
// The most blocker-list reads one check makes for queued issues.
export const BLOCKER_READS = 30;

// The Work status reader for a loop that can visit more issues than a
// per-issue read limit (read-status.mjs statusReader's `limit`) allows: one
// resolve-config.mjs issuesByStatus listing over every state (config.order),
// read on first use, gives each issue's state to statusLabels, so no issue
// past a limit is skipped. An unset models.issue-status leaves the names; a
// failed listing makes every call throw StatusReadError. `config` and
// `trustedActors` default to the base config's and the trusted-actor list;
// `sleep` is issuesByStatus's.
//
// Its `queued()` is the same listing's agent-ready issues, oldest first, each
// {number, names}: the names as statusLabels folds the field in, so a
// field-only agent-ready counts and a stale agent-ready label under another
// state does not, and an issue the listing holds (`held`) counts as queued.
// null with models.issue-status unset; a failed listing throws.
export function listedStatusOf({ env = {}, github, repository, config, trustedActors, sleep }) {
  let listing;
  const load = async () => {
    const { issueStatusFromBase, issuesByStatus } = await import(new URL("../resolve-config/resolve-config.mjs", import.meta.url).href);
    const leaf = config === undefined ? issueStatusFromBase(env) : config;
    if (!leaf) {
      return null;
    }
    const found = await issuesByStatus(github, repository, leaf.order, { config: leaf, trustedActors: trustedActors ?? loadTrustedActors(env), sleep });
    const held = new Map((found.held ?? []).map((issue) => [issue.number, issue]));
    return { config: leaf, found, held, states: new Map(found.map((issue) => [issue.number, issue.state])) };
  };
  const statusOf = async (number, names) => {
    listing ??= load();
    let read;
    try {
      read = await listing;
    } catch (error) {
      throw new StatusReadError(number, error);
    }
    // A held issue (Work status mid-write) reads as unreadable, never as its
    // labels: readLaneWip counts that as queued.
    const held = read?.held.get(Number(number));
    if (held) {
      throw new StatusReadError(number, held.reason);
    }
    return read ? statusLabels(read.states.get(Number(number)) ?? null, names, read.config) : names;
  };
  statusOf.queued = async () => {
    listing ??= load();
    const read = await listing;
    if (!read) {
      return null;
    }
    // A held issue (Work status mid-write, left out of the listing) counts as
    // agent-ready: leaving it out would undercount the cap by one, and
    // counting it only slows admissions.
    const held = [...read.held.values()].map((issue) => ({ number: issue.number, createdAt: String(issue.created_at ?? ""), names: ["agent-ready"] }));
    return read.found
      .map((issue) => ({ number: issue.number, createdAt: String(issue.created_at ?? ""), names: statusLabels(issue.state, issue.labels, read.config) }))
      .filter((issue) => lowered(issue.names).includes("agent-ready"))
      .concat(held)
      .sort((a, b) => (a.createdAt < b.createdAt ? -1 : a.createdAt > b.createdAt ? 1 : a.number - b.number))
      .map(({ number, names }) => ({ number, names }));
  };
  return statusOf;
}

// A hold label matches in any case, as pr-merge's holdReason matches it; the
// body line matches exactly.
export const isHeld = (pr) =>
  (pr?.labels ?? []).some((label) => typeof label?.name === "string" && HOLD_LABELS.has(label.name.toLowerCase())) ||
  String(pr?.body ?? "")
    .split(/\r?\n/)
    .includes(HOLD_LINE);

const namedIssue = (pr) => {
  const match = NAMES_ISSUE.exec(String(pr?.body ?? "").split(/\r?\n/, 1)[0].trim());
  return match ? Number(match[1]) : null;
};

const isoSecond = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
const isCount = (value) => Number.isSafeInteger(value) && value >= 0;

// The open lane PRs as { createdAt, held, issue }, the merged and opened
// counts in the window, and the queued issues' numbers; each null when its
// read fails. `searchIncomplete` is whether any answer said incomplete_results
// true, which a degraded search answers with a false empty. Reads run one at a time, and
// none starts once `remaining()` (the last x-ratelimit-remaining seen) is 0 or less.
// `pauseOnly` stops after the open listing and the merged count. `statusOf(number,
// names)` gives a listed issue's label names with its Work status field's say
// (listedStatusOf); by default the labels as listed.
export async function readLaneWip(github, { repo, bot = DEFAULT_BOT, now, windowHours, remaining = () => null, pauseOnly = false, statusOf = async (number, names) => names }) {
  const author = `author:app/${bot.replace(/\[bot\]$/, "")}`;
  const since = isoSecond(now - windowHours * HOUR_MS);
  let searchIncomplete = false;
  const checkBudget = () => {
    const left = remaining();
    if (left !== null && left <= 0) {
      throw new Error("the rate limit has no requests left");
    }
  };
  const search = async (q, page, perPage) => {
    checkBudget();
    const answer = await github("GET", `/search/issues?q=${encodeURIComponent(q)}&per_page=${perPage}&page=${page}`);
    if (answer?.incomplete_results !== false) {
      searchIncomplete ||= answer?.incomplete_results === true;
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
  // The listed items, and how many more the search counted than it listed
  // (past MAX_PAGES); null when a read fails.
  const list = async (q, map) => {
    const all = [];
    try {
      for (let page = 1; page <= MAX_PAGES; page += 1) {
        const answer = await search(q, page, PAGE);
        const items = answer?.items;
        if (!Array.isArray(items)) {
          throw new Error("the search answered no items");
        }
        all.push(...items.map(map));
        if (items.length < PAGE) {
          return { items: all, unlisted: 0 };
        }
        if (page === MAX_PAGES) {
          const total = answer?.total_count;
          return { items: all, unlisted: isCount(total) ? Math.max(1, total - all.length) : 1 };
        }
      }
    } catch {
      return null;
    }
  };
  const open = (await list(`repo:${repo} is:pr is:open ${author}`, (pr) => ({
    number: Number(pr?.number),
    createdAt: Date.parse(pr?.created_at),
    held: isHeld(pr),
    issue: namedIssue(pr),
  })))?.items ?? null;
  const merged = await count(`repo:${repo} is:pr is:merged ${author} merged:>=${since}`);
  if (pauseOnly) {
    return { open, merged, admitted: null, queued: null, queuedUnlisted: null, blocked: [], searchIncomplete, pauseOnly };
  }
  const admitted = await count(`repo:${repo} is:pr ${author} created:>=${since}`);
  // The queued issues come from the issues listing, not the search index,
  // whose results carry no recency guarantee: admit.mjs counts its racing
  // admissions against this count. The listing holds pull requests too and
  // takes no label exclusion, so both are left out here; a full last page
  // leaves at least one unlisted. A failed page or one that is not a list
  // leaves the count unread.
  // With a Work status listing (listedStatusOf's `queued`), the field decides
  // which issues are agent-ready and the label listing is not read; a failed
  // listing leaves the count unread.
  const listQueued = async () => {
    const numbers = [];
    try {
      checkBudget();
      const listed = await statusOf.queued?.();
      if (listed) {
        return { items: listed.filter((issue) => isQueued(issue.names)).map((issue) => issue.number), unlisted: 0 };
      }
      for (let page = 1; page <= MAX_PAGES; page += 1) {
        checkBudget();
        const items = await github("GET", `/repos/${repo}/issues?labels=agent-ready&state=open&sort=created&direction=asc&per_page=${PAGE}&page=${page}`);
        if (!Array.isArray(items)) {
          throw new Error("the issues listing answered no list");
        }
        for (const item of items.filter((entry) => !entry?.pull_request)) {
          // The listing names only agent-ready issues, so the label counts as
          // on each one unless the field says otherwise. An unreadable field
          // counts as queued, which only slows admissions.
          const names = [...(item?.labels ?? []).map((label) => label?.name), "agent-ready"];
          const queued = await statusOf(Number(item?.number), names).then(isQueued, (error) => {
            if (error instanceof StatusReadError) return true;
            throw error;
          });
          if (queued) {
            numbers.push(Number(item?.number));
          }
        }
        if (items.length < PAGE) {
          return { items: numbers, unlisted: 0 };
        }
      }
      return { items: numbers, unlisted: 1 };
    } catch {
      return null;
    }
  };
  const queued = await listQueued();
  // A search item carries no head ref, so a lane PR whose first body line
  // names no issue (a person edited it) costs one pull request read for its
  // lane branch. One that fails leaves the PR unmatched.
  for (const pr of queued?.items?.length ? (open ?? []) : []) {
    if (pr.issue === null && Number.isSafeInteger(pr.number) && pr.number > 0) {
      pr.issue = await github("GET", `/repos/${repo}/pulls/${pr.number}`).then(
        (pull) => laneBranchIssue(pull?.head?.ref),
        () => null,
      );
    }
  }
  // An agent-ready issue a blocker still blocks never runs (check-blockers.mjs),
  // so it is not queued work. One blocker-list read per queued issue no lane PR
  // names, at most BLOCKER_READS; past that, or on a failed read, the issue
  // counts as queued. A closed issue blocker, here or in another repository,
  // counts as done without reading who closed it: an untrusted close the lane
  // would still wait on is counted as queued, which only slows admissions.
  const named = new Set(open?.map((pr) => pr.issue) ?? []);
  const blocked = [];
  const unnamed = open === null ? [] : (queued?.items ?? []).filter((number) => !named.has(number) && Number.isSafeInteger(number) && number > 0);
  for (const number of unnamed.slice(0, BLOCKER_READS)) {
    try {
      if ((await stillBlocking(await blockersOf(github, `/repos/${repo}/issues/${number}`), repo, async () => true, async () => true)).length > 0) {
        blocked.push(number);
      }
    } catch {
      // Counted as queued.
    }
  }
  return { open, merged, admitted, queued: queued?.items ?? null, queuedUnlisted: queued?.unlisted ?? null, blocked, searchIncomplete };
}

const round = (value, places) => (value === null ? null : Number(value.toFixed(places)));

// The status as one flat object; the field names are a published contract
// (README.md, WIP cap).
export function wipStatus(
  { open, merged, admitted, queued = null, queuedUnlisted = 0, blocked = [], searchIncomplete = false, pauseOnly = false },
  { limits, wip, now, configError = false },
) {
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
  const admission = resolveAdmission(limits);
  const perHour = Math.max(computed ? (admission["admission-factor"] * merged) / window : 0, admission["admission-min-per-hour"]);
  const queuedCap = Number((perHour * window).toFixed(9));
  const named = new Set(open?.map((pr) => pr.issue) ?? []);
  // Issues past the listing's last page count as queued, and a count cut
  // short that way never admits.
  const truncated = (queuedUnlisted ?? 0) > 0;
  const waiting = new Set(blocked);
  const queuedIssues =
    queued === null || open === null ? null : queued.filter((number) => !named.has(number) && !waiting.has(number)).length + (queuedUnlisted ?? 0);
  const queuedTotal = queuedIssues === null ? null : queuedIssues + heldCount;
  const queuedOver = queuedTotal !== null && (truncated || queuedTotal >= queuedCap - 1e-9);
  // Admissions left before the cap; null when nothing gates them. An
  // unreadable base config or an incomplete search answer leaves none whatever
  // pause-from says: the caps or the counts are unknown.
  const unknown = configError ? "config-unreadable" : searchIncomplete ? "search-incomplete" : null;
  const room = unknown
    ? 0
    : !pausing || queuedTotal === null || pauseOnly
      ? null
      : truncated
        ? 0
        : Math.max(0, Math.ceil(queuedCap - queuedTotal - 1e-9));
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
    queued_issues: queuedIssues,
    queued_truncated: queuedIssues === null ? null : truncated,
    queued_total: queuedTotal,
    queued_cap: round(queuedCap, 3),
    admission_factor: admission["admission-factor"],
    admission_min_per_hour: admission["admission-min-per-hour"],
    wip_over: wipOver,
    held_over: heldOver,
    admission_over: admissionOver,
    queued_over: queuedOver,
    held_alarm: heldAlarm,
    alert: wipOver || heldOver || admissionOver || queuedOver || heldAlarm,
    pause_from: pauseFrom,
    paused: pausing && reasons.length > 0,
    pause_reason: pausing && reasons.length > 0 ? reasons.join(",") : null,
    admission_open: room === null || room > 0,
    admission_reason: room === 0 ? (unknown ?? "queued") : null,
    admission_room: room,
    admission_basis: unknown ?? (pauseOnly ? "not-read" : queuedTotal === null ? "fail-open" : "read"),
  };
}

// The status from the lanes App's PRs in `repo`, for the issue lane's check
// and work-unblock's sweep alike.
export async function checkWip(github, { repo, bot, now, limits, wip, remaining, pauseOnly = false, configError = false, statusOf }) {
  const reads = await readLaneWip(github, { repo, bot, now, windowHours: wip["merge-rate-window-hours"], remaining, pauseOnly, statusOf });
  return wipStatus(reads, { limits, wip, now, configError });
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

// The machine-readable line for paused admissions.
export const admissionLine = (s) =>
  `admission paused: reason=${s.admission_reason} queued=${s.queued_issues} held=${s.held_lane_prs} cap=${s.queued_cap}`;

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
    s.queued_over && `${s.queued_total} queued (${s.queued_issues} agent-ready issues with no open lane PR, ${s.held_lane_prs} held lane PRs) are at or over the queued cap of ${s.queued_cap}`,
    s.held_alarm && `${s.held_over_alarm_count} held lane PRs are older than ${s.held_alarm_hours} h`,
  ]
    .filter(Boolean)
    .join("; ");

export async function main({ env = process.env, github, now = Date.now(), log = console.log } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  const basePath = env.BASE_PATH || ".base";
  const { limits, wip, configError } = await baseConfig(basePath, log);
  const rate = searchRateLimit();
  github ??= createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse: rate.onResponse });
  const statusOf = listedStatusOf({ env: { ...env, BASE_PATH: basePath }, github, repository: repo });
  // A notice, and the same line in the step summary.
  const announce = (title, line) => {
    log(`::notice title=${title}::${escape(line)}`);
    if (env.GITHUB_STEP_SUMMARY) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `\n${line}\n`);
    }
  };
  const read = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)
    ? await checkWip(github, { repo, bot: env.LANES_BOT_LOGIN || DEFAULT_BOT, now, limits, wip, remaining: rate.remaining, pauseOnly: env.WIP_READS === "pause", configError, statusOf })
    : wipStatus({ open: null, merged: null, admitted: null, queued: null, queuedUnlisted: null }, { limits, wip, now, configError });
  // What the pause could not read, first one only; none when every read it
  // depends on succeeded. A merged count that cannot be read is no hold: the
  // cap is then the configured limits.wip-cap.
  const unread = configError
    ? "the base config could not be read"
    : read.countable_lane_prs === null
      ? "the open lane PRs could not be listed"
      : null;
  const held = unread !== null;
  const status = { ...read, pause_basis: held ? "unknown" : "read" };
  const json = JSON.stringify(status);
  writeOutputs({ capped: String(held || status.paused), held: String(held), "admission-open": String(status.admission_open), wip: json }, env.GITHUB_OUTPUT);
  if (env.GITHUB_STEP_SUMMARY) {
    appendFileSync(env.GITHUB_STEP_SUMMARY, `### Issue-lane WIP cap\n\n\`\`\`json\n${json}\n\`\`\`\n`);
  }
  if (held) {
    announce("WIP cap hold", `WIP cap hold: ${unread}, so the pause is unknown and this run starts no work; work-unblock's next sweep re-fires it and the check reads again`);
  }
  if (status.admission_basis === "search-incomplete") {
    log(
      `::warning title=check-wip-cap::GitHub search answered incomplete results (admission_basis search-incomplete), so its counts are unknown and no new admissions are made this run`,
    );
  }
  if (status.admission_basis === "config-unreadable") {
    log(
      `::warning title=check-wip-cap::the base config could not be read (admission_basis config-unreadable), so the caps are unknown and no new admissions are made this run`,
    );
  }
  if (status.alert) {
    log(
      `::warning title=check-wip-cap::${escape(alertText(status))}; ${held ? "this run holds on the unknown pause" : status.paused ? "this run starts no work and work-unblock re-fires it once under both caps" : `the lane keeps running (${!(status.wip_over || status.held_over) ? "only the WIP and held caps pause runs" : wip["pause-from"] === "" ? "pause-from is not set" : "pause-from not reached"})`}`,
    );
  }
  if (status.paused && !held) {
    announce(
      "admission paused",
      `admission paused: reason=${status.pause_reason} countable=${status.countable_lane_prs} wip_cap=${status.wip_cap} held=${status.held_lane_prs} held_cap=${status.held_cap}`,
    );
  }
  if (!status.admission_open) {
    announce("admission paused", admissionLine(status));
  }
  log(`check-wip-cap: ${json}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
