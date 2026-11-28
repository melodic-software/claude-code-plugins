#!/usr/bin/env node
import { createHash } from "node:crypto";
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { decide } from "../lib/lane-level.mjs";
import { describeLevel, effectiveLevel, encodeLevel, LEVEL_VARIABLE, levelSettings, parseLevel, variableOf } from "../lib/lane-level-value.mjs";
import { ghDownloadArtifact, newestTrustedArtifact } from "../pr-merge/rotation.mjs";
import { budgetLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { IN_FLIGHT } from "./label-unblocked.mjs";

export const STATE_ARTIFACT = "lane-level-state";
export const STATE_FILE = "lane-level-state.json";
const WORKFLOW_PATH = ".github/workflows/work-unblock.yml";
const LANE_WORKFLOW = "work-resolve-issue.yml";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const notice = (text) => console.log(`::notice title=lane-level::${text}`);
const reason = (error, max = 200) => String(error?.message ?? error).slice(0, max);

export function levelVariableWriter({ github, repo, name }) {
  if (!LEVEL_VARIABLE.test(name ?? "") || !REPO.test(repo ?? "")) {
    throw new Error(`refusing to write variable ${JSON.stringify(name)}: only a *_LANE_LEVEL variable of this repository is the lane level`);
  }
  return {
    name,
    async write(value) {
      if (parseLevel(value) === null) {
        throw new Error(`refusing to write ${JSON.stringify(value)} to ${name}: not <level>@<valid-until>`);
      }
      try {
        await github("PATCH", `/repos/${repo}/actions/variables/${name}`, { name, value });
      } catch (error) {
        if (error?.status !== 404) {
          throw error;
        }
        await github("POST", `/repos/${repo}/actions/variables`, { name, value });
      }
    },
  };
}

export const laneClient = (env, fetchImpl) =>
  createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, latch: budgetLatch("lanes-app"), ...(fetchImpl ? { fetchImpl } : {}) });

export const shadowPublisher = () => ({
  async publish(value, name) {
    return `shadow: would set ${name} to ${value}; wrote nothing`;
  },
});

export const livePublisher = (writer) => ({
  async publish(value) {
    await writer.write(value);
    return `set ${writer.name} to ${value}`;
  },
});

export const noTokenPublisher = () => ({
  async publish(value, name) {
    return `no lane token, so ${name} was not set to ${value}; it holds until it expires`;
  },
});

export function publisherFor(settings, { github, repo }) {
  if (settings.shadow) {
    return shadowPublisher();
  }
  return github ? livePublisher(levelVariableWriter({ github, repo, name: settings.variable })) : noTokenPublisher();
}

export async function demandOf({ actions, repo, applied }) {
  try {
    let active = 0;
    for (const status of IN_FLIGHT) {
      const count = (await actions("GET", `/repos/${repo}/actions/workflows/${LANE_WORKFLOW}/runs?status=${status}&per_page=1`))?.total_count;
      if (!Number.isInteger(count) || count < 0) {
        return null;
      }
      active += count;
    }
    return { running: Math.min(active, applied), waiting: Math.max(0, active - applied) };
  } catch (error) {
    notice(`the lane's runs were not listed (${reason(error)}); demand is unread`);
    return null;
  }
}

const scheduledSweep = (repo) => (run) =>
  run?.path === WORKFLOW_PATH && run.event === "schedule" && run.head_branch === "main" && run.head_repository?.full_name === repo;

export async function previousState({ repo, runId, actions, download }) {
  try {
    const found = await newestTrustedArtifact({ repo, runId: String(runId), actions, name: STATE_ARTIFACT, workflow: WORKFLOW_PATH, trusted: scheduledSweep(repo), event: "schedule" });
    if (found?.artifactId === undefined) {
      return null;
    }
    const state = JSON.parse(download(found.artifactId));
    return state !== null && typeof state === "object" ? state : null;
  } catch (error) {
    notice(`the last decision state was not read (${reason(error)})`);
    return null;
  }
}

function resolvedLimits(path) {
  try {
    const limits = JSON.parse(readFileSync(path, "utf8"))?.limits;
    return { "lane-level": limits?.["lane-level"] ?? {}, api: limits?.api ?? {} };
  } catch {
    return { "lane-level": {}, api: {} };
  }
}

const configuredSettings = (env) => levelSettings(resolvedLimits(env.RESOLVED_CONFIG)["lane-level"]);

function parsedReadings(text) {
  try {
    return text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}

export async function run({ env = process.env, now = Date.now(), actions, github, download } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  const limits = resolvedLimits(env.RESOLVED_CONFIG);
  const settings = levelSettings(limits["lane-level"]);
  const value = variableOf(env.LANE_VARS, settings);
  const applied = effectiveLevel({ value, settings, now });
  actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
  download ??= ghDownloadArtifact({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: STATE_ARTIFACT, file: STATE_FILE });
  if (github === undefined && env.GH_TOKEN) {
    github = laneClient(env);
  }

  const kept = await previousState({ repo, runId: env.GITHUB_RUN_ID, actions, download });
  const live = effectiveLevel({ value, settings: { ...settings, shadow: false }, now });
  const previous = kept ?? (live.reason === "published" ? { level: live.published } : null);
  const demand = await demandOf({ actions, repo, applied: applied.level });
  const decision = decide(previous, parsedReadings(env.LANE_READINGS), demand, limits);
  const next = encodeLevel(decision.level, Math.floor(now / 1000) + settings["valid-minutes"] * 60);

  if (env.STATE_OUT) {
    writeFileSync(env.STATE_OUT, `${JSON.stringify({ level: decision.level, streak: decision.streak, holdUntil: decision.holdUntil, reason: decision.reason, at: Math.floor(now / 1000) })}\n`);
  }
  const from = previous?.level ?? "none";
  let outcome;
  try {
    outcome = await publisherFor(settings, { github, repo }).publish(next, settings.variable);
  } catch (error) {
    outcome = `${settings.variable} was not set: ${reason(error)}`;
  }
  notice(`level ${decision.level} (${decision.reason}, from ${from}); applied now: ${describeLevel(applied)}; ${outcome}`);
  return decision;
}

// List repository variables: per_page max 30, default 10: https://docs.github.com/en/rest/actions/variables#list-repository-variables
const VARIABLES_PER_PAGE = 30;
const digest = (value) => createHash("sha256").update(String(value ?? "")).digest("hex");
const shownName = (name) => String(name).replace(/[^A-Za-z0-9_]/g, "?");
export const VARIABLES_CHANGED = "lane-variables-changed:";
export const VARIABLES_UNREAD = "lane-variables-unread:";
const failure = (text) => console.log(`::error title=lane-variables::${text}`);

export async function listVariables({ github, repo }) {
  const variables = new Map();
  let total;
  for (let page = 1; total === undefined || page <= Math.ceil(total / VARIABLES_PER_PAGE); page += 1) {
    const answer = await github("GET", `/repos/${repo}/actions/variables?per_page=${VARIABLES_PER_PAGE}&page=${page}`);
    const count = answer?.total_count;
    if (!Number.isInteger(count) || count < 0 || !Array.isArray(answer.variables) || (total !== undefined && count !== total)) {
      throw new Error(`page ${page} of the variable listing is malformed or its total_count changed`);
    }
    total = count;
    for (const variable of answer.variables) {
      if (typeof variable?.name !== "string" || variables.has(variable.name)) {
        throw new Error(`page ${page} of the variable listing has an unnamed or repeated variable`);
      }
      variables.set(variable.name, { value: digest(variable.value), updated_at: String(variable.updated_at ?? "") });
    }
    if (answer.variables.length === 0) {
      break;
    }
  }
  if (variables.size !== total) {
    throw new Error(`the variable listing held ${variables.size} of its ${total} variables`);
  }
  return Object.fromEntries(variables);
}

export function variableChanges(before, after, allowed) {
  const changes = [];
  for (const name of new Set([...Object.keys(before), ...Object.keys(after)])) {
    const was = Object.hasOwn(before, name) ? before[name] : null;
    const is = Object.hasOwn(after, name) ? after[name] : null;
    const kind = !was ? "created" : !is ? "deleted" : was.value !== is.value || was.updated_at !== is.updated_at ? "changed" : null;
    if (kind && !(name === allowed && kind !== "deleted")) {
      changes.push({ kind, name });
    }
  }
  return changes.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

const allowedVariable = (env) => {
  const name = configuredSettings(env).variable;
  return LEVEL_VARIABLE.test(name ?? "") ? name : null;
};

export async function snapshot({ env = process.env, github } = {}) {
  try {
    github ??= laneClient(env);
    const variables = await listVariables({ github, repo: env.GITHUB_REPOSITORY ?? "" });
    writeFileSync(env.VARIABLES_STATE, `${JSON.stringify({ variables })}\n`);
    console.log(`listed ${Object.keys(variables).length} repository variables before the publish`);
    return true;
  } catch (error) {
    failure(`${VARIABLES_UNREAD} the repository variables were not listed before the publish, so nothing is published (${reason(error)})`);
    return false;
  }
}

export async function check({ env = process.env, github } = {}) {
  let before;
  let after;
  try {
    before = JSON.parse(readFileSync(env.VARIABLES_STATE, "utf8")).variables;
    if (before === null || typeof before !== "object") {
      throw new Error("the listing before the publish is not in the state file");
    }
  } catch (error) {
    failure(`${VARIABLES_UNREAD} the listing before the publish was not read (${reason(error)})`);
    return false;
  }
  try {
    github ??= laneClient(env);
    after = await listVariables({ github, repo: env.GITHUB_REPOSITORY ?? "" });
  } catch (error) {
    failure(`${VARIABLES_UNREAD} the repository variables were not listed after the publish (${reason(error)})`);
    return false;
  }
  const changes = variableChanges(before, after, allowedVariable(env));
  if (changes.length > 0) {
    failure(`${VARIABLES_CHANGED} ${changes.map(({ kind, name }) => `${kind} ${shownName(name)}`).join(", ")}`);
    return false;
  }
  console.log(`no repository variable changed but the level variable (${Object.keys(after).length} listed)`);
  return true;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const command = process.argv[2];
  if (command === "mode") {
    appendFileSync(process.env.GITHUB_OUTPUT, `shadow=${configuredSettings(process.env).shadow ? "true" : "false"}\n`);
  } else if (command === "run") {
    try {
      await run();
    } catch (error) {
      notice(`no level was decided: ${reason(error, 300)}`);
    }
  } else if (command === "snapshot" || command === "check") {
    process.exitCode = (await (command === "snapshot" ? snapshot() : check())) ? 0 : 1;
  } else {
    console.error("usage: publish-lane-level.mjs mode|run|snapshot|check");
    process.exitCode = 2;
  }
}
