// I/O shell of resolve-config: reads the config, schema and vocabulary from
// under base-path only, the event file, and (only when a predicate needs it)
// the PR through the API; then writes ResolvedConfig to output-path and the
// step outputs. Every rejection or failure exits 1 and leaves no file.
import { readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { join, sep } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import {
  createGitHub,
  paginate,
} from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { pipelineEvent } from "./predicate.mjs";
import {
  checkConfigPath,
  laneHasActivity,
  modelArgs,
  modelSettings,
  neededFacts,
  resolve,
  resolveLimits,
  resolveRoute,
} from "./resolve.mjs";

const DEFAULT_BASE_PATH = ".base";
const DEFAULT_CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const SCHEMA_PATH = "docs/conventions/pr-pipeline/pr-pipeline.schema.json";
const VOCABULARY_PATH =
  ".github/standards/github-actions-conventions/vocabulary.json";
const CODEOWNERS_PATH = ".github/CODEOWNERS";
// pulls/{n}/files lists at most this many files; a list that long may be cut.
const FILES_CAP = 3000;
const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const SHA = /^[0-9a-f]{40}(?:[0-9a-f]{24})?$/;
// Reads of GET /pulls/{n} while mergeability is unknown, and the wait between
// them; then the activity skips with prerequisite-missing and the next trigger
// retries.
const MERGEABLE_READS = 3;
const MERGEABLE_WAIT_MS = 5000;

const readOwn = (name) =>
  JSON.parse(readFileSync(new URL(name, import.meta.url), "utf8"));

// The text of <basePath>/<relative>, or undefined when it does not exist. A
// path whose real location (after symlinks) leaves base-path is an error.
function readUnderBase(basePath, relative) {
  let real;
  try {
    real = realpathSync(join(basePath, relative));
  } catch (error) {
    if (error.code === "ENOENT") {
      return undefined;
    }
    throw error;
  }
  if (!real.startsWith(realpathSync(basePath) + sep)) {
    throw new Error(`${relative} resolves outside base-path`);
  }
  return readFileSync(real, "utf8");
}

function readJsonUnderBase(basePath, relative) {
  const text = readUnderBase(basePath, relative);
  return text === undefined ? undefined : JSON.parse(text);
}

async function gatherFacts(
  needed,
  { eventName, event, prNumber, headSha, repository, github, sleep },
) {
  const facts = { event: pipelineEvent(eventName, event) };
  let pull;
  const readPull = async () => {
    if (!PR_NUMBER.test(prNumber ?? "")) {
      throw new Error(
        "an applies-when predicate needs the PR, and no pr-number was given",
      );
    }
    pull = await github("GET", `/repos/${repository}/pulls/${prNumber}`);
    return pull;
  };
  const fetchPull = async () => pull ?? (await readPull());
  if (needed.includes("mergeable")) {
    // GitHub computes mergeability in the background and answers null until
    // it is done; a read at another head describes another commit. Only the
    // gated head's answer counts, and the payload's never does.
    if (!SHA.test(headSha ?? "")) {
      throw new Error(
        "a mergeable predicate needs the gated head-sha, and none was given",
      );
    }
    facts.mergeable = null;
    for (let read = 1; read <= MERGEABLE_READS; read += 1) {
      const { mergeable, head } = await readPull();
      if (head?.sha === headSha && typeof mergeable === "boolean") {
        facts.mergeable = mergeable ? "clean" : "conflicting";
        break;
      }
      if (read < MERGEABLE_READS) {
        await sleep(MERGEABLE_WAIT_MS);
      }
    }
  }
  if (needed.includes("draft")) {
    facts.draft = event.pull_request?.draft ?? (await fetchPull()).draft;
  }
  // An issues event has no PR: labels come from the issue (the payload's, or
  // read now for labels-absent and admission), and its update time is when it
  // was labeled.
  const issue = eventName === "issues" ? event.issue : undefined;
  if (issue !== undefined) {
    if (needed.includes("labeledAt") && typeof issue.updated_at === "string") {
      facts.labeledAt = issue.updated_at;
    }
    if (needed.includes("labels")) {
      const labels = needed.includes("freshLabels")
        ? (await github("GET", `/repos/${repository}/issues/${Number(issue.number)}`)).labels
        : issue.labels;
      facts.labels = labels.map((label) => label.name);
    }
  } else if (needed.includes("labels")) {
    const labels = needed.includes("freshLabels")
      ? (await fetchPull()).labels
      : (event.pull_request?.labels ?? (await fetchPull()).labels);
    facts.labels = labels.map((label) => label.name);
  }
  if (needed.includes("changedPaths")) {
    const changedFiles = (await fetchPull()).changed_files;
    const files = await paginate(
      github,
      `/repos/${repository}/pulls/${prNumber}/files`,
      FILES_CAP / 100 + 1,
    );
    if (files.length >= FILES_CAP || files.length < changedFiles) {
      throw new Error(
        `pulls/${prNumber}/files listed ${files.length} of ${changedFiles} changed files ` +
          `(the API stops at ${FILES_CAP}), so a paths predicate cannot be decided`,
      );
    }
    facts.changedPaths = files.flatMap((file) =>
      file.previous_filename
        ? [file.filename, file.previous_filename]
        : [file.filename],
    );
    // What the head still holds: an activity cannot edit a removed file.
    facts.changedTargets = files
      .filter((file) => file.status !== "removed")
      .map((file) => file.filename);
  }
  return facts;
}

// A model run's step outputs, or empty ones for a script. The args are
// checked against their only shape, so no output can carry a second line.
const MODEL_ARGS = /^(?:--model [a-z]+ )?--max-turns [1-9][0-9]*(?: --effort [a-z]+)?$/;
function modelOutputs(models) {
  if (models === null) {
    return { profile: "", "claude-args": "", "settings-json": "", "max-turns": "" };
  }
  const args = modelArgs(models);
  if (!MODEL_ARGS.test(args)) {
    throw new Error(`the resolved model arguments have an unexpected shape: ${args}`);
  }
  return {
    profile: models.profile,
    "claude-args": args,
    "settings-json": modelSettings(models),
    "max-turns": String(models["max-turns"]),
  };
}

function outputsFor({ lane, selected }) {
  const outputs = {
    enabled: String(lane.enabled),
    slots: JSON.stringify(lane.slots.map((slot) => slot.name)),
  };
  if (selected === null) {
    return outputs;
  }
  return {
    ...outputs,
    kind: selected.kind,
    effect: selected.effect,
    gating: selected.gating,
    skill: selected.skill ?? "",
    script: selected.script ?? "",
    ...modelOutputs(selected.models),
    "reads-untrusted": String(selected["reads-untrusted"]),
    applies: String(selected.applies),
    "skip-reason": selected["skip-reason"] ?? "",
    contents: selected.grant.contents,
    "pull-requests": selected.grant["pull-requests"],
    issues: selected.grant.issues,
    // Only a read grant cannot commit; any other value keeps the signed-commit check.
    "can-commit": String(selected.grant.contents !== "read"),
    ...(selected.prepare === undefined ? {} : { prepare: selected.prepare }),
  };
}

// Workflow-command escaping, so a message cannot start a second command.
const escapeCommand = (text) =>
  String(text)
    .replaceAll("%", "%25")
    .replaceAll("\r", "%0D")
    .replaceAll("\n", "%0A");

const wait = (ms) => new Promise((done) => setTimeout(done, ms));

function filesUnderBase(basePath, configPath) {
  checkConfigPath(configPath);
  const schema = readJsonUnderBase(basePath, SCHEMA_PATH);
  if (schema === undefined) {
    throw new Error(`no schema at ${SCHEMA_PATH} under base-path`);
  }
  return {
    config: readUnderBase(basePath, configPath),
    schema,
    vocabulary: readJsonUnderBase(basePath, VOCABULARY_PATH),
    codeowners: readUnderBase(basePath, CODEOWNERS_PATH),
    laneRules: readOwn("./lane-rules.json"),
    effectGrants: readOwn("./effect-grants.json"),
    activityRules: readOwn("./activity-rules.json"),
  };
}

// The ResolvedConfig for the request env names, or a throw: a Rejection
// (with its code) for a config or request the resolver refuses. `event` is the
// payload; by default it is read from EVENT_PATH. With `absentAsNull`, a valid
// config whose lane holds no slot for the activity resolves to null.
export async function resolveFromBase({ env, github, sleep = wait, event, absentAsNull = false }) {
  const basePath = env.BASE_PATH || DEFAULT_BASE_PATH;
  const configPath = env.CONFIG_PATH || DEFAULT_CONFIG_PATH;
  const files = filesUnderBase(basePath, configPath);
  const request = {
    lane: env.LANE,
    activity: env.ACTIVITY || undefined,
    configPath,
    basePath,
  };
  if (absentAsNull && !laneHasActivity(files, request)) {
    return null;
  }
  const facts = await gatherFacts(neededFacts(files, request), {
    eventName: env.EVENT_NAME,
    event: event ?? JSON.parse(readFileSync(env.EVENT_PATH, "utf8")),
    prNumber: env.PR_NUMBER,
    headSha: env.HEAD_SHA,
    repository: env.REPOSITORY,
    sleep,
    github:
      github ??
      createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
  });
  const resolved = resolve(files, { ...request, facts });
  // A runner that does not perform the prepare step would run the skill
  // without it, so an applying leaf that needs one fails instead.
  const { selected: chosen } = resolved;
  if (chosen?.applies && chosen.prepare && env.PREPARE_SUPPORTED !== "true") {
    throw new Error(
      `activity \`${chosen.name}\` sets prepare: ${chosen.prepare}, and this runner does not pass prepare-supported: true`,
    );
  }
  return resolved;
}

// The base config's resolved `limits`, for a script that resolves no lane
// slot; a config the resolver refuses throws.
export function limitsFromBase(env) {
  const basePath = env.BASE_PATH || DEFAULT_BASE_PATH;
  const configPath = env.CONFIG_PATH || DEFAULT_CONFIG_PATH;
  return resolveLimits(filesUnderBase(basePath, configPath), { configPath });
}

// A run that is no lane activity resolves only its model route.
function resolveRouteFromBase(env) {
  if (env.LANE) {
    throw new Error("set lane or model-route, not both");
  }
  const basePath = env.BASE_PATH || DEFAULT_BASE_PATH;
  const configPath = env.CONFIG_PATH || DEFAULT_CONFIG_PATH;
  const models = resolveRoute(filesUnderBase(basePath, configPath), {
    route: env.MODEL_ROUTE,
    configPath,
  });
  return {
    version: 1,
    source: { "base-path": basePath, "config-path": configPath },
    route: env.MODEL_ROUTE,
    models,
  };
}

export async function main({ env = process.env, github, sleep = wait } = {}) {
  const outputPath = env.OUTPUT_PATH;
  try {
    if (!outputPath) {
      throw new Error("output-path is not set");
    }
    rmSync(outputPath, { force: true });
    if (env.MODEL_ROUTE) {
      const routed = resolveRouteFromBase(env);
      writeFileSync(outputPath, `${JSON.stringify(routed, null, 2)}\n`);
      writeOutputs(modelOutputs(routed.models), env.GITHUB_OUTPUT);
      console.log(`resolve-config: route=${routed.route} profile=${routed.models.profile}`);
      return 0;
    }
    const resolved = await resolveFromBase({ env, github, sleep });
    writeFileSync(outputPath, `${JSON.stringify(resolved, null, 2)}\n`);
    writeOutputs(outputsFor(resolved), env.GITHUB_OUTPUT);
    const selected = resolved.selected;
    console.log(
      `resolve-config: lane=${resolved.lane.name}` +
        (selected
          ? ` activity=${selected.name} applies=${selected.applies}` +
            (selected.models ? ` profile=${selected.models.profile}` : "")
          : ""),
    );
    return 0;
  } catch (error) {
    if (outputPath) {
      rmSync(outputPath, { force: true });
    }
    console.log(
      `::error title=resolve-config::${escapeCommand(error?.message ?? error)}`,
    );
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
