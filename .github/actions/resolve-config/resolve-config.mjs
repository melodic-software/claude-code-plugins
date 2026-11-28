import { readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { join, sep } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import {
  createGitHub,
  paginate,
} from "../../scripts/lib/github-client.mjs";
import { issueStatus, issueStatusSetter, StatusDisagreement } from "./issue-status.mjs";
import { checkPatchRules } from "./patch-rules.mjs";
import { pipelineEvent } from "./predicate.mjs";
import { DISAGREEMENT_WAIT_MS, fieldStatusSetter, statusLabels } from "./read-status.mjs";
import {
  checkAppliedBySupported,
  checkConfigPath,
  laneHasActivity,
  loadConfig,
  modelArgs,
  modelSettings,
  neededFacts,
  resolve,
  resolveLimits,
  resolveLoop,
  resolveRoute,
  resolveWipLeaf,
} from "./resolve.mjs";

const DEFAULT_BASE_PATH = ".base";
const DEFAULT_CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const SCHEMA_PATH = "docs/conventions/pr-pipeline/pr-pipeline.schema.json";
const CODEOWNERS_PATH = ".github/CODEOWNERS";
const STANDARDS_VOCABULARY_PATH = "components/github-actions-conventions/vocabulary.json";
const STANDARDS_TRUSTED_ACTORS_PATH = "components/trusted-actors/trusted-actors.json";
const ROLE_MAP_PATH = "plugins/multi-agent/reference/defaults.yaml";
const FILES_CAP = 3000;
const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const SHA = /^[0-9a-f]{40}(?:[0-9a-f]{24})?$/;
const MERGEABLE_READS = 3;
const MERGEABLE_WAIT_MS = 5000;

const OWN_FILES = {
  "./lane-rules.json": new URL("./lane-rules.json", import.meta.url),
  "./effect-grants.json": new URL("./effect-grants.json", import.meta.url),
  "./activity-rules.json": new URL("./activity-rules.json", import.meta.url),
  "./patch-rules.json": new URL("./patch-rules.json", import.meta.url),
  "./patch-rules.schema.json": new URL("./patch-rules.schema.json", import.meta.url),
};
const readOwn = (name) => {
  if (!Object.hasOwn(OWN_FILES, name)) {
    throw new Error(`${name} is not in OWN_FILES, the literal URLs collect-base-activity's stager follows`);
  }
  return JSON.parse(readFileSync(OWN_FILES[name], "utf8"));
};

function readUnder(root, relative, name = "base-path") {
  let real;
  try {
    real = realpathSync(join(root, relative));
  } catch (error) {
    if (error.code === "ENOENT") {
      return undefined;
    }
    throw error;
  }
  if (!real.startsWith(realpathSync(root) + sep)) {
    throw new Error(`${relative} resolves outside ${name}`);
  }
  return readFileSync(real, "utf8");
}

const readUnderBase = (basePath, relative) => readUnder(basePath, relative);

function readJsonUnder(root, relative, name) {
  const text = readUnder(root, relative, name);
  return text === undefined ? undefined : JSON.parse(text);
}

const readJsonUnderBase = (basePath, relative) => readJsonUnder(basePath, relative);

const standardsFiles = (standardsPath) =>
  standardsPath
    ? {
        vocabulary: readJsonUnder(standardsPath, STANDARDS_VOCABULARY_PATH, "standards-path"),
        trustedActors: readJsonUnder(standardsPath, STANDARDS_TRUSTED_ACTORS_PATH, "standards-path"),
      }
    : {};

const FIELD_API_VERSION = "2026-03-10";
const FIELD_EVENT_TYPES = "[ISSUE_FIELD_ADDED_EVENT, ISSUE_FIELD_CHANGED_EVENT, ISSUE_FIELD_REMOVED_EVENT]";
const FIELD_EVENT_NODES = `nodes {
        __typename
        ... on IssueFieldAddedEvent { createdAt value actor { ...who } issueField { ...field } }
        ... on IssueFieldChangedEvent { createdAt previousValue newValue actor { ...who } issueField { ...field } }
        ... on IssueFieldRemovedEvent { createdAt actor { ...who } issueField { ...field } }
      }`;
const FIELD_FRAGMENTS = `fragment who on Actor { __typename login ... on User { databaseId } ... on Bot { databaseId } }
fragment field on IssueFields { ... on IssueFieldSingleSelect { fullDatabaseId } }`;
const FIELD_EVENT_LIMIT = 100;
const FIELD_EVENTS = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) {
    timelineItems(last: ${FIELD_EVENT_LIMIT}, itemTypes: ${FIELD_EVENT_TYPES}) {
      ${FIELD_EVENT_NODES}
    }
  } }
}
${FIELD_FRAGMENTS}`;

const graphqlFailure = (answer, what) =>
  Array.isArray(answer?.errors) && answer.errors.length > 0
    ? new Error(`${what} could not be read: ${answer.errors.map((e) => e?.message).join("; ")}`)
    : null;

export async function fieldEvents(github, repository, number) {
  const [owner, name] = repository.split("/");
  const answer = await github("POST", "/graphql", { query: FIELD_EVENTS, variables: { owner, name, number } });
  const failure = graphqlFailure(answer, "the issue's field events");
  if (failure) {
    throw failure;
  }
  const issue = answer?.data?.repository?.issue;
  if (issue === null || typeof issue !== "object") {
    throw new Error("the issue's field events answer named no issue");
  }
  const nodes = issue.timelineItems?.nodes;
  if (!Array.isArray(nodes)) {
    throw new Error("the issue's field events answer holds no event list");
  }
  return Object.defineProperty(eventsFrom(nodes), "full", { value: nodes.length >= FIELD_EVENT_LIMIT });
}

function eventsFrom(nodes) {
  const text = (value) => (typeof value === "string" ? value : null);
  const held = Object.create(null);
  const events = [];
  for (const node of nodes) {
    const field = node?.issueField?.fullDatabaseId;
    if (typeof field !== "string" || !/^[1-9][0-9]*$/.test(field)) {
      continue;
    }
    const id = node.actor?.databaseId;
    const removed = node.__typename === "IssueFieldRemovedEvent";
    const changed = node.__typename === "IssueFieldChangedEvent";
    const to = removed ? null : text(changed ? node.newValue : node.value);
    events.push({
      field,
      removed,
      actorId: Number.isInteger(id) ? id : null,
      actorLogin: text(node.actor?.login),
      actorType: text(node.actor?.__typename),
      at: text(node.createdAt),
      from: changed ? text(node.previousValue) : (held[field] ?? null),
      to,
    });
    held[field] = to;
  }
  return events;
}

export async function fieldSetters(github, repository, number) {
  return settersOf(await fieldEvents(github, repository, number));
}

function settersOf(events) {
  const setters = Object.create(null);
  for (const event of events) {
    setters[event.field] = event.removed ? null : event.actorId;
  }
  return setters;
}

export const ISSUE_PAGE_SIZE = 25;
export const MAX_ISSUE_PAGES = 80;
const LISTED_FIELD_EVENTS = 100;
export const MAX_STATUS_REREADS = 10;
const OPEN_ISSUES = `query($owner: String!, $name: String!, $cursor: String, $since: DateTime) {
  repository(owner: $owner, name: $name) {
    issues(states: OPEN, first: ${ISSUE_PAGE_SIZE}, after: $cursor, filterBy: { since: $since }) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        createdAt
        labels(first: 30) { nodes { name } }
        issueFieldValues(first: 10) { nodes { ... on IssueFieldSingleSelectValue { name field { ...field } } } }
        timelineItems(last: ${LISTED_FIELD_EVENTS}, itemTypes: ${FIELD_EVENT_TYPES}) {
          ${FIELD_EVENT_NODES}
        }
      }
    }
  }
}
${FIELD_FRAGMENTS}`;

export async function issuesByStatus(github, repository, states, { since, config, trustedActors, sleep = wait } = {}) {
  const [owner, name] = repository.split("/");
  const option = Object.fromEntries(Object.entries(config.options).map(([id, state]) => [state, Number(id)]));
  const wanted = new Set(states.flatMap((state) => config.labels[state] ?? []).map((label) => label.toLowerCase()));
  const statusField = String(config["field-id"]);
  const found = [];
  const held = [];
  Object.defineProperty(found, "held", { value: held });
  let rereads = 0;
  let cursor = null;
  for (let page = 1; page <= MAX_ISSUE_PAGES; page += 1) {
    const answer = await github("POST", "/graphql", { query: OPEN_ISSUES, variables: { owner, name, cursor, since: since ?? null } });
    const failure = graphqlFailure(answer, "the open issues");
    if (failure) {
      throw failure;
    }
    const issues = answer?.data?.repository?.issues;
    if (!Array.isArray(issues?.nodes) || typeof issues.pageInfo?.hasNextPage !== "boolean") {
      throw new Error("the open issues answer holds no issue list");
    }
    for (const node of issues.nodes) {
      const labels = (node?.labels?.nodes ?? []).map((label) => label?.name).filter((label) => typeof label === "string");
      const labeled = labels.some((label) => wanted.has(label.toLowerCase()));
      const fieldValues = (node?.issueFieldValues?.nodes ?? [])
        .filter((value) => typeof value?.name === "string" && typeof value.field?.fullDatabaseId === "string")
        .map((value) => ({ field: Number(value.field.fullDatabaseId), option: option[value.name] ?? value.name }));
      const nodes = node?.timelineItems?.nodes;
      if (!Number.isInteger(node?.number) || !Array.isArray(nodes)) {
        throw new Error("the open issues answer holds an issue with no number or event list");
      }
      const events = eventsFrom(nodes);
      const wantedValue = (node?.issueFieldValues?.nodes ?? []).find((value) => value?.field?.fullDatabaseId === statusField && states.includes(value?.name));
      const hasStatusEvent = events.some((event) => event.field === statusField);
      const couldMatch = () => labeled || wantedValue !== undefined || events.some((event) => event.field === statusField && states.includes(event.to));
      let state;
      try {
        if (nodes.length >= LISTED_FIELD_EVENTS && fieldValues.some((value) => String(value.field) === statusField) && !hasStatusEvent) {
          throw new Error(`#${node.number}'s Work status setter is older than its newest ${LISTED_FIELD_EVENTS} field events`);
        }
        if (wantedValue !== undefined && !hasStatusEvent) {
          throw new StatusDisagreement(`issue field ${statusField} (Work status) holds \`${wantedValue.name}\`, but the listing shows no Work status event`);
        }
        state = issueStatus({ fieldValues, fieldEvents: events, fieldEventsFull: nodes.length >= LISTED_FIELD_EVENTS }, config, trustedActors);
      } catch (error) {
        if (!couldMatch()) {
          continue;
        }
        if (error?.name !== "StatusDisagreement") {
          throw error;
        }
        let disagreement = error;
        if (rereads < MAX_STATUS_REREADS) {
          rereads += 1;
          try {
            ({ state } = await fieldStatusSetter({ github, repository, number: node.number, config, trustedActors, issueStatusSetter, fieldEvents, sleep }));
            disagreement = null;
          } catch (again) {
            if (again?.name !== "StatusDisagreement") {
              throw again;
            }
            disagreement = again;
          }
        }
        if (disagreement) {
          held.push({ number: node.number, created_at: node.createdAt, reason: disagreement.message });
          console.log(`::notice title=issuesByStatus::#${node.number} is left out of this listing: ${String(disagreement.message).replaceAll(/[\r\n%]/g, " ")}`);
          continue;
        }
      }
      if (state === null ? labeled : states.includes(state)) {
        found.push({ number: node.number, created_at: node.createdAt, labels, state });
      }
    }
    if (!issues.pageInfo.hasNextPage) {
      return found;
    }
    cursor = issues.pageInfo.endCursor;
  }
  throw new Error(`the open issues run past ${MAX_ISSUE_PAGES} pages`);
}

async function gatherFacts(
  needed,
  { eventName, event, prNumber, headSha, repository, github, sleep, splitChild, status },
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
  const issue = eventName === "issues" ? event.issue : undefined;
  if (issue !== undefined) {
    let values;
    let events;
    const readValues = async () => {
      if (values === undefined) {
        const rows = await github("GET", `/repos/${repository}/issues/${Number(issue.number)}/issue-field-values`, undefined, {
          "X-GitHub-Api-Version": FIELD_API_VERSION,
        });
        if (!Array.isArray(rows)) {
          throw new Error("the issue's field values answer is not a list");
        }
        values = rows.map((row) => ({
          field: row?.issue_field_id,
          option: row?.single_select_option?.id ?? null,
        }));
      }
      return values;
    };
    const readEvents = async () => (events ??= await fieldEvents(github, repository, Number(issue.number)));
    if (needed.includes("fieldValues")) {
      facts.fieldValues = await readValues();
    }
    if (needed.includes("fieldSetters")) {
      facts.fieldSetters = settersOf(await readEvents());
    }
    if (needed.includes("splitChild")) {
      if (splitChild !== "true" && splitChild !== "false") {
        throw new Error("split-child must be `true` or `false` when the issue's dimensions are read");
      }
      facts.splitChild = splitChild === "true";
    }
    if (needed.includes("labels")) {
      const labels = needed.includes("freshLabels")
        ? (await github("GET", `/repos/${repository}/issues/${Number(issue.number)}`)).labels
        : issue.labels;
      facts.labels = labels.map((label) => label.name);
      if (status?.config) {
        const readState = async () => {
          const fieldEventsRead = await readEvents();
          return issueStatus(
            { fieldValues: await readValues(), fieldEvents: fieldEventsRead, fieldEventsFull: fieldEventsRead.full === true },
            status.config,
            status.trustedActors,
          );
        };
        let state;
        try {
          state = await readState();
        } catch (error) {
          if (error?.name !== "StatusDisagreement") {
            throw error;
          }
          await sleep(DISAGREEMENT_WAIT_MS);
          values = undefined;
          events = undefined;
          state = await readState();
          if (needed.includes("fieldValues")) {
            facts.fieldValues = await readValues();
          }
          if (needed.includes("fieldSetters")) {
            facts.fieldSetters = settersOf(await readEvents());
          }
        }
        facts.labels = statusLabels(state, facts.labels, status.config);
      }
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
    facts.changedTargets = files
      .filter((file) => file.status !== "removed")
      .map((file) => file.filename);
  }
  return facts;
}

const MODEL_ARGS = /^--model [a-z]+ --max-turns [1-9][0-9]*(?: --effort [a-z]+)?$/;
function modelOutputs(models) {
  if (models === null) {
    return { profile: "", "claude-args": "", "settings-json": "", "max-turns": "", model: "", effort: "" };
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
    model: models.model,
    effort: models.effort ?? "",
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
    actions: selected.grant.actions ?? "",
    "actions-variables": selected.grant["actions-variables"] ?? "",
    "can-commit": String(selected.grant.contents !== "read"),
    ...(selected["applied-by"]?.patch === undefined ? {} : { "applied-by-patch": selected["applied-by"].patch }),
    ...(selected["applied-by"]?.["triage-verdict"] === undefined ? {} : { "applied-by-triage-verdict": selected["applied-by"]["triage-verdict"] }),
    ...(selected.prepare === undefined ? {} : { prepare: selected.prepare }),
    ...(selected.kind === "skill" ? { "permission-mode": selected["permission-mode"] ?? "dontAsk" } : {}),
    ...(selected.kind === "script" ? { checkout: selected.checkout ?? "head" } : {}),
    ...(selected["issue-dimensions"] === undefined
      ? {}
      : { "issue-dimensions": selected["issue-dimensions"], "timeout-minutes": String(selected["timeout-minutes"]) }),
  };
}

const escapeCommand = (text) =>
  String(text)
    .replaceAll("%", "%25")
    .replaceAll("\r", "%0D")
    .replaceAll("\n", "%0A");

const wait = (ms) => new Promise((done) => setTimeout(done, ms));

const pathsOf = (env) => ({
  basePath: env.BASE_PATH || DEFAULT_BASE_PATH,
  configPath: env.CONFIG_PATH || DEFAULT_CONFIG_PATH,
  standardsPath: env.STANDARDS_DIR || undefined,
});

function filesUnderBase({ basePath, configPath, standardsPath }, readRules = readOwn) {
  checkConfigPath(configPath);
  const schema = readJsonUnderBase(basePath, SCHEMA_PATH);
  if (schema === undefined) {
    throw new Error(`no schema at ${SCHEMA_PATH} under base-path`);
  }
  return {
    config: readUnderBase(basePath, configPath),
    schema,
    ...standardsFiles(standardsPath),
    codeowners: readUnderBase(basePath, CODEOWNERS_PATH),
    roleMap: readUnderBase(basePath, ROLE_MAP_PATH),
    laneRules: readRules("./lane-rules.json"),
    effectGrants: readRules("./effect-grants.json"),
    activityRules: readRules("./activity-rules.json"),
    patchRules: readRules("./patch-rules.json"),
    patchRulesSchema: readRules("./patch-rules.schema.json"),
  };
}

const modelRung = (value) => (value === undefined || value === "" ? undefined : /^[01]$/.test(value) ? Number(value) : value);

export async function resolveFromBase({ env, github, sleep = wait, event, absentAsNull = false, readRules }) {
  const paths = pathsOf(env);
  const { basePath, configPath } = paths;
  const files = filesUnderBase(paths, readRules);
  const doc = loadConfig(files, { configPath });
  checkPatchRules(files.patchRules, files.patchRulesSchema, doc.activities);
  const request = {
    lane: env.LANE,
    activity: env.ACTIVITY || undefined,
    configPath,
    basePath,
    pinnedDimensions: env.ISSUE_DIMENSIONS || undefined,
    rung: modelRung(env.MODEL_RUNG),
  };
  if (absentAsNull && !laneHasActivity(files, request)) {
    return null;
  }
  const facts = await gatherFacts(neededFacts(files, request), {
    status: { config: doc.models?.["issue-status"] ?? null, trustedActors: files.trustedActors },
    splitChild: env.SPLIT_CHILD,
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
  const { selected: chosen } = resolved;
  if (chosen?.applies && chosen.prepare && env.PREPARE_SUPPORTED !== "true") {
    throw new Error(
      `activity \`${chosen.name}\` sets prepare: ${chosen.prepare}, and this runner does not pass prepare-supported: true`,
    );
  }
  checkAppliedBySupported(chosen, env.APPLIED_BY_SUPPORTED);
  return resolved;
}

export function limitsFromBase(env) {
  const paths = pathsOf(env);
  return resolveLimits(filesUnderBase(paths), paths);
}

export function wipFromBase(env) {
  const paths = pathsOf(env);
  const { configPath } = paths;
  const files = filesUnderBase(paths);
  return { limits: resolveLimits(files, { configPath }), wip: resolveWipLeaf(files, { configPath }) };
}

export function loopFromBase(env) {
  const paths = pathsOf(env);
  return resolveLoop(filesUnderBase(paths), paths);
}

export function adoptionFromBase(env) {
  return configFromBase(env).adoption ?? {};
}

export function testScopeFromBase(env) {
  return { apply: configFromBase(env)["test-scope"]?.apply === true };
}

export function ownedBranchesFromBase(env) {
  return configFromBase(env).merge?.["refire-skip-branches"] ?? [];
}

export function configFromBase(env) {
  const paths = pathsOf(env);
  return loadConfig(filesUnderBase(paths), paths);
}

export function tidyCutoffsFromBase(env) {
  return configFromBase(env).activities["resolve-issue"]?.tidy?.cutoffs ?? null;
}

export function refineDispatchActivitiesFromBase(env) {
  return configFromBase(env)["refine-dispatch"]?.activities ?? [];
}

export function issueDimensionsFromBase(env) {
  return configFromBase(env).models?.["issue-dimensions"] ?? null;
}

export function issueStatusFromBase(env) {
  return configFromBase(env).models?.["issue-status"] ?? null;
}

export function redMainFromBase(env) {
  const doc = configFromBase(env);
  return { redMain: doc["red-main"] ?? {}, agentIdentity: doc.merge?.["agent-identity"] ?? "" };
}

export function postMergeFromBase(env) {
  const doc = configFromBase(env);
  return { paths: doc["post-merge"]?.paths ?? {}, agentIdentity: doc.merge?.["agent-identity"] ?? "" };
}

export function issueLaneWebHostsFromBase(env) {
  const web = configFromBase(env).activities?.["resolve-issue"]?.["web-access"];
  return web?.enabled ? web.domains : [];
}

export function attendedClassesFromBase(env) {
  return configFromBase(env).attended?.classes ?? {};
}

export function branchCleanupFromBase(env) {
  return configFromBase(env)["branch-cleanup"] ?? {};
}

function resolveRouteFromBase(env) {
  if (env.LANE) {
    throw new Error("set lane or model-route, not both");
  }
  const paths = pathsOf(env);
  const { basePath, configPath } = paths;
  const models = resolveRoute(filesUnderBase(paths), {
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
