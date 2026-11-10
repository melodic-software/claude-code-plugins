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
// CLI:
//   mode   writes `shadow=true|false` to GITHUB_OUTPUT, so the job mints a
//          lane token only to write
//   run    decides, writes STATE_OUT, publishes, and ends green on any
//          failure with a notice: a missed hour holds the last value until it
//          expires, and an expired one reads as the default
//
// Environment: RESOLVED_CONFIG, LANE_READINGS, LANE_VARS (toJSON(vars)),
// ACTIONS_TOKEN (the job token, actions: read), GH_TOKEN (the lane token, live
// only), STATE_OUT, GITHUB_REPOSITORY, GITHUB_RUN_ID, RUNNER_TEMP,
// GITHUB_API_URL, GITHUB_OUTPUT.
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
    notice(`the lane's runs were not listed (${String(error?.message ?? error).slice(0, 200)}); demand is unread`);
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
    notice(`the last decision state was not read (${String(error?.message ?? error).slice(0, 200)})`);
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
  const published = parseLevel(value);
  const previous = kept ?? (published ? { level: published.level } : null);
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
    outcome = `${settings.variable} was not set: ${String(error?.message ?? error).slice(0, 200)}`;
  }
  notice(`level ${decision.level} (${decision.reason}, from ${from}); applied now: ${describeLevel(applied)}; ${outcome}`);
  return decision;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const command = process.argv[2];
  if (command === "mode") {
    const settings = levelSettings(resolvedLimits(process.env.RESOLVED_CONFIG)["lane-level"]);
    appendFileSync(process.env.GITHUB_OUTPUT, `shadow=${settings.shadow ? "true" : "false"}\n`);
  } else if (command === "run") {
    try {
      await run();
    } catch (error) {
      notice(`no level was decided: ${String(error?.message ?? error).slice(0, 300)}`);
    }
  } else {
    console.error("usage: publish-lane-level.mjs mode|run");
    process.exitCode = 2;
  }
}
