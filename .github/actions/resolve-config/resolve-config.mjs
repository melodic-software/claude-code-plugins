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
import { checkConfigPath, neededFacts, resolve } from "./resolve.mjs";

const DEFAULT_BASE_PATH = ".base";
const DEFAULT_CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const SCHEMA_PATH = "docs/conventions/pr-pipeline/pr-pipeline.schema.json";
const VOCABULARY_PATH =
  ".github/standards/github-actions-conventions/vocabulary.json";
// pulls/{n}/files lists at most this many files; a list that long may be cut.
const FILES_CAP = 3000;
const PR_NUMBER = /^[1-9][0-9]{0,9}$/;

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
  { eventName, event, prNumber, repository, github },
) {
  const facts = { event: pipelineEvent(eventName, event) };
  let pull;
  const fetchPull = async () => {
    if (!PR_NUMBER.test(prNumber ?? "")) {
      throw new Error(
        "an applies-when predicate needs the PR, and no pr-number was given",
      );
    }
    pull ??= await github("GET", `/repos/${repository}/pulls/${prNumber}`);
    return pull;
  };
  if (needed.includes("labels")) {
    const labels = event.pull_request?.labels ?? (await fetchPull()).labels;
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
  };
}

// Workflow-command escaping, so a message cannot start a second command.
const escapeCommand = (text) =>
  String(text)
    .replaceAll("%", "%25")
    .replaceAll("\r", "%0D")
    .replaceAll("\n", "%0A");

export async function main({ env = process.env, github } = {}) {
  const outputPath = env.OUTPUT_PATH;
  try {
    if (!outputPath) {
      throw new Error("output-path is not set");
    }
    rmSync(outputPath, { force: true });
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
      laneRules: readOwn("./lane-rules.json"),
      effectGrants: readOwn("./effect-grants.json"),
    };
    const request = {
      lane: env.LANE,
      activity: env.ACTIVITY || undefined,
      configPath,
      basePath,
    };
    const facts = await gatherFacts(neededFacts(files, request), {
      eventName: env.EVENT_NAME,
      event: JSON.parse(readFileSync(env.EVENT_PATH, "utf8")),
      prNumber: env.PR_NUMBER,
      repository: env.REPOSITORY,
      github:
        github ??
        createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
    });
    const resolved = resolve(files, { ...request, facts });
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
