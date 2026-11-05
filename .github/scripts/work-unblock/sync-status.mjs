// Mirrors an issue's status labels into its Work status field
// (models.issue-status), whoever changed them. A status label added or
// removed by a person, a gh session, an outside reusable or a skill reaches
// the field only here; the lane and maintenance scripts mirror their own
// writes (write-status.mjs statusMirror), since a GITHUB_TOKEN label change
// starts no workflow run.
//
// - `issues` labeled or unlabeled: when the changed label is one of
//   models.issue-status's labels and the issue is no pull request, read the
//   issue's labels fresh (several label events can land together) and its
//   field, and write the state the labels collapse to unless the field
//   already holds it.
// - `schedule` (work-unblock's hourly run): the same for every open issue, one
//   at a time, a short pause apart, within CALL_BUDGET calls, ending on
//   `swept N: wrote W, unchanged U, failed F`.
//
// The field counts as holding a state only when the reader would trust it
// (issue-status.mjs issueStatus: a listed human or the lanes App set it), so
// a value an untrusted account set is written again; this script writes with
// the lanes App token for that reason. Labels stay the source of truth: a
// failed field write warns (writeStatus) and changes no label.
//
// Environment: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_EVENT_NAME,
// GITHUB_EVENT_PATH, GITHUB_API_URL, TRUSTED_ACTORS_PATH, KILL_SWITCH
// (`proceed`, or the run stops before any API call), CALL_BUDGET (the sweep's
// limit, default 800), BASE_PATH (the base checkout, default `.base`).
import { readFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { FIELD_API, writeStatus } from "../../actions/resolve-config/write-status.mjs";

const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;
const MAX_ISSUE_PAGES = 20;
const fold = (name) => String(typeof name === "string" ? name : name?.name).toLowerCase();
const annotate = (line) => String(line).replaceAll(/[\r\n%]/g, " ");

// Whether `name` is one of models.issue-status's labels.
export const isStatusLabel = (name, config) =>
  typeof name === "string" && Object.values(config.labels).some((labels) => labels.some((label) => fold(label) === fold(name)));

// Mirrors one issue. `issue` is the issue as just listed, else it is read.
// `status` holds issue-status.mjs's collapseStatus and issueStatus,
// resolve-config.mjs's fieldSetters and write-status.mjs's writeStatus.
// Returns writeStatus's outcome, `unchanged` when the field already holds the
// state, or `skipped` for a pull request.
export async function mirrorIssue({ github, repository, number, issue, config, trustedActors, status, log = console.log }) {
  const read = issue ?? (await github("GET", `/repos/${repository}/issues/${number}`));
  if (read?.pull_request) {
    return { outcome: "skipped", reason: "a pull request" };
  }
  const rows = await github("GET", `/repos/${repository}/issues/${number}/issue-field-values`, undefined, FIELD_API);
  if (!Array.isArray(rows)) {
    throw new Error(`#${number}'s field values answered something other than a list`);
  }
  const facts = {
    fieldValues: rows.map((row) => ({ field: row?.issue_field_id, option: row?.single_select_option?.id ?? null })),
    fieldSetters: await status.fieldSetters(github, repository, number),
  };
  const have = status.issueStatus(facts, config, trustedActors);
  let labels = read?.labels ?? [];
  let want = status.collapseStatus(labels, config);
  // A listed issue's labels can be minutes old by its turn in the sweep, and a
  // label-event run may have written the newer state since: read the issue
  // again before writing, so a stale listing never reverts the field.
  if (have !== want && issue) {
    const fresh = await github("GET", `/repos/${repository}/issues/${number}`);
    labels = fresh?.labels ?? [];
    want = status.collapseStatus(labels, config);
  }
  if (have === want) {
    return { outcome: "unchanged", state: want };
  }
  return status.writeStatus({ github, repository, number, labels, config, log });
}

// One label event. Returns mirrorIssue's answer, or `skipped` with why.
export async function onLabelEvent({ event, github, repository, config, trustedActors, status, log = console.log }) {
  if (event?.issue?.pull_request) {
    return { outcome: "skipped", reason: "a pull request" };
  }
  if (!isStatusLabel(event?.label?.name, config)) {
    return { outcome: "skipped", reason: "not a status label" };
  }
  return mirrorIssue({ github, repository, number: Number(event.issue.number), config, trustedActors, status, log });
}

// Every open issue, oldest first. `budget` is the most calls the sweep makes;
// past it the sweep stops and says so.
export async function sweep({ github, repository, config, trustedActors, status, budget = 800, pause = () => delay(250), log = console.log }) {
  let used = 0;
  const call = (...args) => {
    if (used >= budget) {
      throw new Error(`call budget of ${budget} spent`);
    }
    used += 1;
    return github(...args);
  };
  const counts = { swept: 0, wrote: 0, unchanged: 0, failed: 0 };
  let stopped = "";
  const issues = [];
  for (let page = 1; page <= MAX_ISSUE_PAGES; page += 1) {
    const batch = await call("GET", `/repos/${repository}/issues?state=open&direction=asc&per_page=100&page=${page}`);
    issues.push(...batch.filter((item) => !item.pull_request));
    if (batch.length < 100) {
      break;
    }
  }
  for (const issue of issues) {
    try {
      const { outcome } = await mirrorIssue({ github: call, repository, number: issue.number, issue, config, trustedActors, status, log });
      counts.swept += 1;
      if (outcome === "written") {
        counts.wrote += 1;
      } else if (outcome === "unchanged") {
        counts.unchanged += 1;
      } else {
        counts.failed += 1;
      }
    } catch (error) {
      if (/call budget/.test(error?.message ?? "")) {
        stopped = `; stopped at #${issue.number}: ${error.message}`;
        break;
      }
      counts.swept += 1;
      counts.failed += 1;
      log(`::warning title=work-status::#${issue.number} not swept: ${annotate(error?.message ?? error)}`);
    }
    await pause();
  }
  log(`swept ${counts.swept}: wrote ${counts.wrote}, unchanged ${counts.unchanged}, failed ${counts.failed}${stopped} (${used} calls)`);
  return { ...counts, stopped, used };
}

export async function main({ env = process.env, log = console.log } = {}) {
  try {
    if (env.KILL_SWITCH !== "proceed") {
      log("sync-status: the kill switch stops this run; nothing read or written");
      return 0;
    }
    if (!REPOSITORY.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const repository = env.GITHUB_REPOSITORY;
    // resolve-config.mjs and issue-status.mjs load the packages the job
    // installs, so they load here, after the kill switch.
    const { fieldSetters, issueStatusFromBase } = await import("../../actions/resolve-config/resolve-config.mjs");
    const { collapseStatus, issueStatus } = await import("../../actions/resolve-config/issue-status.mjs");
    const config = issueStatusFromBase(env);
    if (!config) {
      log("sync-status: models.issue-status is unset, so no Work status field is written");
      return 0;
    }
    const trustedActors = JSON.parse(readFileSync(env.TRUSTED_ACTORS_PATH, "utf8"));
    const github = createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const status = { collapseStatus, issueStatus, fieldSetters, writeStatus };
    const args = { github, repository, config, trustedActors, status, log };
    if (env.GITHUB_EVENT_NAME === "schedule") {
      const budget = /^[1-9][0-9]{0,4}$/.test(env.CALL_BUDGET ?? "") ? Number(env.CALL_BUDGET) : undefined;
      const result = await sweep({ ...args, budget });
      return result.failed > 0 || result.stopped ? 1 : 0;
    }
    if (env.GITHUB_EVENT_NAME !== "issues") {
      throw new Error("this runs only on an issue label event or the hourly schedule");
    }
    const event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8"));
    const result = await onLabelEvent({ ...args, event });
    log(`sync-status: #${Number(event.issue?.number)} ${result.outcome}${result.reason ? ` (${result.reason})` : result.state ? ` (${result.state})` : ""}`);
    return 0;
  } catch (error) {
    log(`::error title=sync-status::${annotate(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
