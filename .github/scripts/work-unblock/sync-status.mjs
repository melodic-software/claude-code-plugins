// Writes a listed human's status-label edit into the issue's Work status
// field (models.issue-status), the field being the state. It only adds: a
// label's absence never resets the field.
//
// - `labeled` with a queue-state label (ready, confirmed, deferred,
//   needs-triage): writes that label's state, unless the field's trusted
//   state is a hold (read-status.mjs HOLD_STATES), since a label never
//   releases a hold, or is that state already.
// - `labeled agent-ready`: writes nothing. The App's agent-ready write would
//   start a run with no admission record; a person sets the field directly.
// - `labeled` with a hold label: writes nothing. The reader adds hold labels
//   on top of the field, and a hold the App wrote would read as the App's.
// - `unlabeled agent-ready`: a person stopping the lane. Writes confirmed,
//   only while the field reads agent-ready (write-status.mjs
//   leaveAgentReady): not ready or deferred, whose App write would read as a
//   trusted status: ready after the removal and admit the issue again.
// - any other `unlabeled`: writes nothing; the release paths own those.
//
// The workflow runs it only for a listed human's label event, one run per
// issue at a time in event order, with the lanes
// App token: the field's reader counts agent-ready only from a listed human or
// the App.
// A failed field write fails the run.
//
// Environment: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_EVENT_NAME,
// GITHUB_EVENT_PATH, GITHUB_API_URL, TRUSTED_ACTORS_PATH, KILL_SWITCH
// (`proceed`, or the run stops before any API call), BASE_PATH (the base
// checkout, default `.base`).
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, REPOSITORY } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { fieldStatus, HOLD_STATES, loadTrustedActors } from "../../actions/resolve-config/read-status.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";

const AGENT_READY = "agent-ready";
const fold = (name) => String(typeof name === "string" ? name : name?.name).toLowerCase();
const annotate = (line) => String(line).replaceAll(/[\r\n%]/g, " ");

// The models.issue-status state whose labels include `name`, without case.
const stateOf = (name, config) =>
  typeof name === "string" ? Object.keys(config.labels).find((state) => config.labels[state].some((label) => fold(label) === fold(name))) : undefined;

// What a label event asks of the field: `{set: state}`, `{leave: true}` for
// agent-ready taken off, or `{why}` when it asks nothing. Pure.
export function translateLabel(event, config) {
  const state = stateOf(event?.label?.name, config);
  if (state === undefined) {
    return { why: "not a status label" };
  }
  if (event.action === "labeled") {
    if (state === AGENT_READY) {
      return { why: "agent-ready, which a person sets on the Work status field itself" };
    }
    return HOLD_STATES.includes(state) ? { why: "a hold label, which the reader adds on top of the field" } : { set: state };
  }
  if (event.action === "unlabeled" && state === AGENT_READY) {
    return { leave: true };
  }
  return { why: "a status label taken off, which only a release path writes" };
}

// The state agent-ready taken off by a person leaves the field at.
export const STOPPED_STATE = "confirmed";

// One label event. `status` holds `fieldState(number)` (the field's trusted
// state, null when none) and the writer (write-status.mjs statusWriter's set
// and leaveAgentReady). Returns the write's outcome, `unchanged`, or
// `skipped` with why.
export async function onLabelEvent({ event, config, status }) {
  if (event?.issue?.pull_request) {
    return { outcome: "skipped", reason: "a pull request" };
  }
  const asked = translateLabel(event, config);
  const number = Number(event?.issue?.number);
  if (asked.leave) {
    return status.leaveAgentReady(number, STOPPED_STATE);
  }
  if (asked.set === undefined) {
    return { outcome: "skipped", reason: asked.why };
  }
  const held = await status.fieldState(number);
  if (HOLD_STATES.includes(held)) {
    return { outcome: "skipped", reason: `the field holds ${held}` };
  }
  if (held === asked.set) {
    return { outcome: "unchanged", state: held };
  }
  return status.set(number, asked.set);
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
    if (env.GITHUB_EVENT_NAME !== "issues") {
      throw new Error("this runs only on an issue label event");
    }
    const repository = env.GITHUB_REPOSITORY;
    // resolve-config.mjs loads the packages the job installs, so it loads
    // here, after the kill switch.
    const { issueStatusFromBase } = await import("../../actions/resolve-config/resolve-config.mjs");
    const config = issueStatusFromBase(env);
    if (!config) {
      log("sync-status: models.issue-status is unset, so no Work status field is written");
      return 0;
    }
    const trustedActors = loadTrustedActors(env);
    const github = createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const writer = await statusWriter({ env, github, repository });
    const fieldState = (number) => fieldStatus({ github, repository, number, config, trustedActors });
    const event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8"));
    const result = await onLabelEvent({ event, config, status: { ...writer, fieldState } });
    const detail = result.reason || result.state;
    log(`sync-status: #${Number(event.issue?.number)} ${result.outcome}${detail ? ` (${detail})` : ""}`);
    return 0;
  } catch (error) {
    log(`::error title=sync-status::${annotate(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
