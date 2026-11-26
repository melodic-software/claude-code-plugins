import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { REPOSITORY } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { fieldStatus, HOLD_STATES, loadTrustedActors } from "../../actions/resolve-config/read-status.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";
import { AGENT_READY } from "../lib/lane-vocabulary.mjs";

const fold = (name) => String(typeof name === "string" ? name : name?.name).toLowerCase();
const annotate = (line) => String(line).replaceAll(/[\r\n%]/g, " ");

const stateOf = (name, config) =>
  typeof name === "string" ? Object.keys(config.labels).find((state) => config.labels[state].some((label) => fold(label) === fold(name))) : undefined;

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

export const STOPPED_STATE = "confirmed";

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
