#!/usr/bin/env node
// The publish part of collect, decide, publish and read: once an hour,
// work-unblock.yml's publish-lane-level job decides the issue lane's next
// level L (lane-level.mjs decide) and publishes it as `<level>@<valid-until>`
// in the one repository variable limits.lane-level.variable names, which
// lane-level-value.mjs reads for pick-slot and label-unblocked.
//
//   collect   the label-unblocked job's lanes App readings
//             (lane-level-readings.mjs), handed over as LANE_READINGS
//   previous  the decision state ({ level, streak, holdUntil }) the newest
//             scheduled run of main's work-unblock.yml kept as the
//             lane-level-state artifact; with none, the published level; with
//             neither, the default. Only that job's own steps upload it, and it
//             never goes through actions/cache, which any job in main's cache
//             scope can write.
//   demand    work-resolve-issue runs in progress, one listing: those past the
//             applied level wait for a slot
//   publish   a strategy picked from the config: shadow (limits.lane-level.
//             shadow, the default) logs what it would publish and writes
//             nothing; live writes the variable through levelVariableWriter;
//             live with no lane token writes nothing and says so.
//
// The lane token's Variables write covers every repository variable, the
// lanes kill switches among them, so every write goes through
// levelVariableWriter, which refuses any other name before a request.
//
// The guard covers this code only. snapshot and check read every repository
// variable with the lane token before and after the publish and fail the job
// on any change but the level variable (owner decisions Q113 (a) and Q115 (a)),
// which checks what the token did rather than what the code says it does.
//
// CLI:
//   mode       writes `shadow=true|false` to GITHUB_OUTPUT, so the job mints a
//              lane token only to write
//   run        decides, writes STATE_OUT, publishes, and ends green on any
//              failure with a notice: a missed hour holds the last value until
//              it expires, and an expired one reads as the default
//   snapshot   lists every repository variable into VARIABLES_STATE; exits 1
//              when the listing is incomplete, so the publish step is skipped
//   check      lists again and exits 1 on any change but the level variable,
//              or when either listing is missing or incomplete
//
// Environment: RESOLVED_CONFIG, LANE_READINGS, LANE_VARS (toJSON(vars)),
// ACTIONS_TOKEN (the job token, actions: read), GH_TOKEN (the lane token, live
// only), STATE_OUT, VARIABLES_STATE, GITHUB_REPOSITORY, GITHUB_RUN_ID,
// RUNNER_TEMP, GITHUB_API_URL, GITHUB_OUTPUT.
import { createHash } from "node:crypto";
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
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

// Guards the lane token's Variables write: the level variable, a well-formed
// value, and nothing else. A refused name or value makes no request.
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

// The lane token's client. The step's API_BUDGET_TOKEN is github-token, for
// the job token's reads and artifact download, so this client's readings are
// pinned to lanes-app.
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

// { waiting, running } from the issue lane's unfinished runs (every status
// label-unblocked counts as in flight, one count each), which past the
// applied level wait for a slot; null when a count fails.
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

// The last scheduled run's decision state, or null.
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

// The resolved limits decide() reads: lane-level, and api as set, which
// decide() fills from rate-limits.json. {} when the file cannot be read, so
// the defaults apply.
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
  // With no kept state, a published value still in force is the previous
  // level, as the readers see it once live; an expired or malformed one is
  // none, so decide() starts from the default.
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

// GET /repos/{repo}/actions/variables answers at most 30 a page, and 10 when
// per_page is not sent.
const VARIABLES_PER_PAGE = 30;
const digest = (value) => createHash("sha256").update(String(value ?? "")).digest("hex");
const shownName = (name) => String(name).replace(/[^A-Za-z0-9_]/g, "?");
// The failure annotations maintenance-monitor-signals keys signal 14 on.
export const VARIABLES_CHANGED = "lane-variables-changed:";
export const VARIABLES_UNREAD = "lane-variables-unread:";
const failure = (text) => console.log(`::error title=lane-variables::${text}`);

// Every repository variable as { name: { value: sha256, updated_at } }: the
// state file and the logs never hold a value, as this repository is public.
// Pages until the first page's total_count is reached, and throws on anything
// short of a whole, consistent listing.
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

// Each change between two listings but a create or change of `allowed`, as
// { kind, name }. The publisher only PATCHes or POSTs the level variable, so
// its removal is never the publisher's.
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

// The one name a change is allowed to: the configured level variable, and only
// when it is a *_LANE_LEVEL name, so a misconfigured kill switch name never
// passes.
const allowedVariable = (env) => {
  const name = configuredSettings(env).variable;
  return LEVEL_VARIABLE.test(name ?? "") ? name : null;
};

// True once the listing is in VARIABLES_STATE.
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

// True only when both listings read whole and nothing changed but the level
// variable.
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
    // These two end red, unlike run: a change the token made outside the level
    // variable, or a check that could not read, must reach a person.
    process.exitCode = (await (command === "snapshot" ? snapshot() : check())) ? 0 : 1;
  } else {
    console.error("usage: publish-lane-level.mjs mode|run|snapshot|check");
    process.exitCode = 2;
  }
}
