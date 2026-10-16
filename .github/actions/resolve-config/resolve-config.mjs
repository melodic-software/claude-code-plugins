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
  loadTrustedList,
  paginate,
} from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { pipelineEvent } from "./predicate.mjs";
import { checkConfigPath, laneHasActivity, neededFacts, resolve } from "./resolve.mjs";

const DEFAULT_BASE_PATH = ".base";
const DEFAULT_CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const SCHEMA_PATH = "docs/conventions/pr-pipeline/pr-pipeline.schema.json";
const VOCABULARY_PATH =
  ".github/standards/github-actions-conventions/vocabulary.json";
const CODEOWNERS_PATH = ".github/CODEOWNERS";
const TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json";
// The owner's batch ratification of an issue's admission, on a line of its own.
const RATIFICATION_MARKER =
  /^<!-- admission: admitted when unblocked, owner batch ratification \d{4}-\d{2}-\d{2} -->$/m;
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
  { eventName, event, prNumber, headSha, repository, github, sleep, loadRatifiers },
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
    if (needed.includes("ratified")) {
      const ratifiers = loadRatifiers();
      const comments = await paginate(
        github,
        `/repos/${repository}/issues/${Number(issue.number)}/comments`,
      );
      facts.ratified = comments.some(
        (comment) =>
          RATIFICATION_MARKER.test(comment.body ?? "") &&
          ratifiers.has(comment.user?.id) &&
          // Through a GitHub App, the text is that App's, not the owner's.
          comment.performed_via_github_app == null &&
          // An edit keeps the author, so edited text may be another account's.
          typeof comment.created_at === "string" &&
          comment.updated_at === comment.created_at,
      );
    }
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
    model: selected.model ?? "",
    "max-turns": selected["max-turns"] ?? "",
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

// The ResolvedConfig for the request env names, or a throw: a Rejection
// (with its code) for a config or request the resolver refuses. `event` is the
// payload; by default it is read from EVENT_PATH. With `absentAsNull`, a valid
// config whose lane holds no slot for the activity resolves to null.
export async function resolveFromBase({ env, github, sleep = wait, event, absentAsNull = false }) {
  const basePath = env.BASE_PATH || DEFAULT_BASE_PATH;
  const configPath = env.CONFIG_PATH || DEFAULT_CONFIG_PATH;
  checkConfigPath(configPath);
  const schema = readJsonUnderBase(basePath, SCHEMA_PATH);
  if (schema === undefined) {
    throw new Error(`no schema at ${SCHEMA_PATH} under base-path`);
  }
  const files = {
    config: readUnderBase(basePath, configPath),
    schema,
    vocabulary: readJsonUnderBase(basePath, VOCABULARY_PATH),
    codeowners: readUnderBase(basePath, CODEOWNERS_PATH),
    laneRules: readOwn("./lane-rules.json"),
    effectGrants: readOwn("./effect-grants.json"),
    activityRules: readOwn("./activity-rules.json"),
  };
  const request = {
    lane: env.LANE,
    activity: env.ACTIVITY || undefined,
    configPath,
    basePath,
  };
  if (absentAsNull && !laneHasActivity(files, request)) {
    return null;
  }
  // Who may ratify an issue's admission: the listed humans only. A lane never
  // admits work on its own.
  const loadRatifiers = () => {
    if (readUnderBase(basePath, TRUSTED_ACTORS_PATH) === undefined) {
      throw new Error(`no trusted-actor list at ${TRUSTED_ACTORS_PATH} under base-path`);
    }
    return loadTrustedList(join(basePath, TRUSTED_ACTORS_PATH)).humans;
  };
  const facts = await gatherFacts(neededFacts(files, request), {
    loadRatifiers,
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

export async function main({ env = process.env, github, sleep = wait } = {}) {
  const outputPath = env.OUTPUT_PATH;
  try {
    if (!outputPath) {
      throw new Error("output-path is not set");
    }
    rmSync(outputPath, { force: true });
    const resolved = await resolveFromBase({ env, github, sleep });
    writeFileSync(outputPath, `${JSON.stringify(resolved, null, 2)}\n`);
    writeOutputs(outputsFor(resolved), env.GITHUB_OUTPUT);
    const selected = resolved.selected;
    console.log(
      `resolve-config: lane=${resolved.lane.name}` +
        (selected
          ? ` activity=${selected.name} applies=${selected.applies}`
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
