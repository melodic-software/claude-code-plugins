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
const VOCABULARY_PATH =
  ".github/standards/github-actions-conventions/vocabulary.json";
const CODEOWNERS_PATH = ".github/CODEOWNERS";
const TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json";
// The multi-agent role map a role profile resolves through.
const ROLE_MAP_PATH = "plugins/multi-agent/reference/defaults.yaml";
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

// The REST version that documents issue-field-values.
const FIELD_API_VERSION = "2026-03-10";
// The field event selection; the REST timeline names the actor but not the field.
const FIELD_EVENT_TYPES = "[ISSUE_FIELD_ADDED_EVENT, ISSUE_FIELD_CHANGED_EVENT, ISSUE_FIELD_REMOVED_EVENT]";
const FIELD_EVENT_NODES = `nodes {
        __typename
        ... on IssueFieldAddedEvent { createdAt value actor { ...who } issueField { ...field } }
        ... on IssueFieldChangedEvent { createdAt previousValue newValue actor { ...who } issueField { ...field } }
        ... on IssueFieldRemovedEvent { createdAt actor { ...who } issueField { ...field } }
      }`;
const FIELD_FRAGMENTS = `fragment who on Actor { __typename login ... on User { databaseId } ... on Bot { databaseId } }
fragment field on IssueFields { ... on IssueFieldSingleSelect { fullDatabaseId } }`;
// The newest field events one issue read takes.
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

// The issue's newest 100 single-select field events, oldest first, each
// {field, removed, actorId, actorLogin, actorType, at, from, to}: `field` the
// field id as a string, `actorId` null for an actor with no id, `actorLogin`
// as GraphQL names it (a bot's without `[bot]`), `actorType` `User` or `Bot`,
// `at` the event time, and `from` and `to` the option names before and after
// (null for none). An add or a removal names no earlier value, so its `from`
// is what the earlier events left.
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
  // `full`: the window held its limit, so older events went unread.
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

// Field id -> the account id that last set it (null after a removal or for an
// actor with no id), from fieldEvents.
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

// Open issues per issuesByStatus page. On pages of 100 GitHub answered stale
// nested field events: for 162 of 210 open issues the newest listed Work
// status event disagreed with the value or none was listed. On pages of 25
// every issue's value matched its newest event, at the same GraphQL points.
export const ISSUE_PAGE_SIZE = 25;
// Pages issuesByStatus reads before it throws: 2,000 open issues.
export const MAX_ISSUE_PAGES = 80;
// Field events per issue in the listing, as many as fieldEvents reads: the
// Work status setter is the newest Work status event among them, and a field
// value with none among a full window throws rather than read as unset.
const LISTED_FIELD_EVENTS = 100;
// Issues per listing whose Work status disagrees in the listing and is read
// again alone (read-status.mjs fieldStatusSetter): 10. Each re-read costs two
// calls, or four and a 3 s wait when it disagrees once more; an eleventh
// disagreeing issue is left out unread.
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

// The open issues whose Work status is one of `states`, oldest page first,
// each {number, created_at, labels, state}: `labels` the label names, `state`
// the trusted field state (issue-status.mjs issueStatus with `config` and
// `trustedActors`), or null for an issue whose field no counted account set
// and that carries one of those states' labels, which decide until the field
// is set. `since` (ISO time, optional) keeps only issues updated at or after
// it. A field value is read by its option name, a state name; a counted name
// `config` does not map throws `unmapped-status`. More than MAX_ISSUE_PAGES
// pages, a GraphQL error, a malformed answer or a Work status value whose
// setter falls outside LISTED_FIELD_EVENTS throws. An issue whose listed value
// and events disagree (StatusDisagreement), or whose value is one of `states`
// with no Work status event listed, since the listing's events can lag, is
// read again alone (fieldStatusSetter, which waits with `sleep`) and
// that read decides; a re-read that fails otherwise throws. One that still
// disagrees, a write still landing, or any past MAX_STATUS_REREADS (not read
// again) is left out of the result, logged as a ::notice::, and named in the
// result's non-enumerable `held`, each {number, created_at, reason}, so one
// issue mid-write fails only itself; a caller that must not undercount reads
// `held`.
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
      // The value and its events come from one read, so no fieldNames check.
      const events = eventsFrom(nodes);
      // An issue whose status cannot be read fails the listing only when it
      // could be one of `states`: a wanted label, or a Work status value or
      // event naming one of them. Any other is skipped, so one issue's
      // unreadable field cannot stop a listing it has no part in.
      const wantedValue = (node?.issueFieldValues?.nodes ?? []).find((value) => value?.field?.fullDatabaseId === statusField && states.includes(value?.name));
      const hasStatusEvent = events.some((event) => event.field === statusField);
      const couldMatch = () => labeled || wantedValue !== undefined || events.some((event) => event.field === statusField && states.includes(event.to));
      let state;
      try {
        if (nodes.length >= LISTED_FIELD_EVENTS && fieldValues.some((value) => String(value.field) === statusField) && !hasStatusEvent) {
          throw new Error(`#${node.number}'s Work status setter is older than its newest ${LISTED_FIELD_EVENTS} field events`);
        }
        // A listing can answer a value with none of the events that set it.
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
  // read now for labels-absent).
  const issue = eventName === "issues" ? event.issue : undefined;
  if (issue !== undefined) {
    // The issue's org field values: REST answers the integer field and
    // option ids the config maps (GraphQL answers only node ids). Each read
    // once, shared by the dimensions and the Work status; a Work status
    // disagreement reads both again for both.
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
      // Whether the issue is a trusted size-split sub-issue, which takes
      // split-child-size: the caller reads it (admit.mjs trustedSplitChild,
      // in work-resolve-issue's check-blockers.mjs) and passes it as
      // SPLIT_CHILD, so this floored module never loads intake's.
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
      // The trusted Work status decides the queue state, agent-ready included,
      // as read-status.mjs statusLabels folds it in: a field-only admission
      // matches `labels`, and a field hold matches `labels-absent`. A failed
      // read throws rather than fall back to the labels, which could miss a hold.
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
          // A read racing a write, as read-status.mjs fieldStatusSetter
          // treats it: both reads once more, and a second disagreement throws.
          await sleep(DISAGREEMENT_WAIT_MS);
          values = undefined;
          events = undefined;
          state = await readState();
          // The dimensions come from the read the status agreed on.
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
    // What the head still holds: an activity cannot edit a removed file.
    facts.changedTargets = files
      .filter((file) => file.status !== "removed")
      .map((file) => file.filename);
  }
  return facts;
}

// A model run's step outputs, or empty ones for a script. The args are
// checked against their only shape, so no output can carry a second line.
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
    // run-claude-cli inputs. Every profile resolves a routed alias.
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
    // Only a read grant cannot commit; any other value keeps the signed-commit check.
    "can-commit": String(selected.grant.contents !== "read"),
    ...(selected["applied-by"]?.patch === undefined ? {} : { "applied-by-patch": selected["applied-by"].patch }),
    ...(selected.prepare === undefined ? {} : { prepare: selected.prepare }),
    ...(selected.kind === "skill" ? { "permission-mode": selected["permission-mode"] ?? "dontAsk" } : {}),
    ...(selected.kind === "script" ? { checkout: selected.checkout ?? "head" } : {}),
    ...(selected["issue-dimensions"] === undefined
      ? {}
      : { "issue-dimensions": selected["issue-dimensions"], "timeout-minutes": String(selected["timeout-minutes"]) }),
  };
}

// Workflow-command escaping, so a message cannot start a second command.
const escapeCommand = (text) =>
  String(text)
    .replaceAll("%", "%25")
    .replaceAll("\r", "%0D")
    .replaceAll("\n", "%0A");

const wait = (ms) => new Promise((done) => setTimeout(done, ms));

// The base-path and config-path env names, with their defaults.
const pathsOf = (env) => ({
  basePath: env.BASE_PATH || DEFAULT_BASE_PATH,
  configPath: env.CONFIG_PATH || DEFAULT_CONFIG_PATH,
});

// `readRules` reads a rule file beside this module; tests replace it.
function filesUnderBase(basePath, configPath, readRules = readOwn) {
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
    trustedActors: readJsonUnderBase(basePath, TRUSTED_ACTORS_PATH),
    roleMap: readUnderBase(basePath, ROLE_MAP_PATH),
    laneRules: readRules("./lane-rules.json"),
    effectGrants: readRules("./effect-grants.json"),
    activityRules: readRules("./activity-rules.json"),
    patchRules: readRules("./patch-rules.json"),
    patchRulesSchema: readRules("./patch-rules.schema.json"),
  };
}

// MODEL_RUNG as resolve()'s rung: empty is none, 0 or 1 that rung; anything
// else is passed on for resolve() to refuse.
const modelRung = (value) => (value === undefined || value === "" ? undefined : /^[01]$/.test(value) ? Number(value) : value);

// The ResolvedConfig for the request env names, or a throw: a Rejection
// (with its code) for a config or request the resolver refuses. `event` is the
// payload; by default it is read from EVENT_PATH. With `absentAsNull`, a valid
// config whose lane holds no slot for the activity resolves to null.
export async function resolveFromBase({ env, github, sleep = wait, event, absentAsNull = false, readRules }) {
  const { basePath, configPath } = pathsOf(env);
  const files = filesUnderBase(basePath, configPath, readRules);
  const doc = loadConfig(files, { configPath });
  // A lane run checks the patch rules before anything else; the token
  // broker, which calls loadConfig and resolveGrant itself, never reads them.
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
  // A runner that does not perform the prepare step would run the skill
  // without it, so an applying leaf that needs one fails instead.
  const { selected: chosen } = resolved;
  if (chosen?.applies && chosen.prepare && env.PREPARE_SUPPORTED !== "true") {
    throw new Error(
      `activity \`${chosen.name}\` sets prepare: ${chosen.prepare}, and this runner does not pass prepare-supported: true`,
    );
  }
  checkAppliedBySupported(chosen, env.APPLIED_BY_SUPPORTED);
  return resolved;
}

// The base config's resolved `limits`, for a script that resolves no lane
// slot; a config the resolver refuses throws.
export function limitsFromBase(env) {
  const { basePath, configPath } = pathsOf(env);
  return resolveLimits(filesUnderBase(basePath, configPath), { configPath });
}

// The base config's resolved limits and its wip leaf as set, read once, for
// the WIP cap check.
export function wipFromBase(env) {
  const { basePath, configPath } = pathsOf(env);
  const files = filesUnderBase(basePath, configPath);
  return { limits: resolveLimits(files, { configPath }), wip: resolveWipLeaf(files, { configPath }) };
}

// The base config's resolved `loop` caps, likewise.
export function loopFromBase(env) {
  const { basePath, configPath } = pathsOf(env);
  return resolveLoop(filesUnderBase(basePath, configPath), { configPath });
}

// The base config's `adoption` section as set, after the same file checks as
// resolve(), for fix-ci-dispatch.mjs, which applies its defaults.
export function adoptionFromBase(env) {
  return configFromBase(env).adoption ?? {};
}

// The base config's `merge.refire-skip-branches`, the head branches a workflow
// owns and rebuilds, after the same file checks as resolve(), for the fix-ci
// dispatcher and context job, which never run fix-ci on one.
export function ownedBranchesFromBase(env) {
  return configFromBase(env).merge?.["refire-skip-branches"] ?? [];
}

// The base config as resolve() loads it, after the same file checks, for
// pr-refine's plan job and the readers below.
export function configFromBase(env) {
  const { basePath, configPath } = pathsOf(env);
  return loadConfig(filesUnderBase(basePath, configPath), { configPath });
}

// resolve-issue's `tidy.cutoffs` as set, or null when it does not tidy, for the
// fix-docs dispatcher, which skips a lane PR tidied in its own run.
export function tidyCutoffsFromBase(env) {
  return configFromBase(env).activities["resolve-issue"]?.tidy?.cutoffs ?? null;
}

// The base config's `models.issue-dimensions` leaf as set, or null, after the
// same file checks as resolve(), for intake triage's verdict writer.
export function issueDimensionsFromBase(env) {
  return configFromBase(env).models?.["issue-dimensions"] ?? null;
}

// The base config's `models.issue-status` leaf as set, or null, after the
// same file checks as resolve(), for the label writers' Work status mirror.
export function issueStatusFromBase(env) {
  return configFromBase(env).models?.["issue-status"] ?? null;
}

// The base config's `red-main` leaf as set and `merge.agent-identity`, after
// the same file checks as resolve(), for the post-merge red-main report. The
// leaf's defaults have one copy, in
// .github/scripts/post-merge-demotion-alert/red-main.mjs, which applies them.
export function redMainFromBase(env) {
  const doc = configFromBase(env);
  return { redMain: doc["red-main"] ?? {}, agentIdentity: doc.merge?.["agent-identity"] ?? "" };
}

// The base config's `post-merge.paths` as set and `merge.agent-identity`,
// likewise, for .github/scripts/post-merge-demotion-alert/merge-path.mjs,
// which applies them.
export function postMergeFromBase(env) {
  const doc = configFromBase(env);
  return { paths: doc["post-merge"]?.paths ?? {}, agentIdentity: doc.merge?.["agent-identity"] ?? "" };
}

// The hosts the issue lane (resolve-issue) may read, for intake admission:
// its web-access domains, "any", or [] when web access is off.
export function issueLaneWebHostsFromBase(env) {
  const web = configFromBase(env).activities?.["resolve-issue"]?.["web-access"];
  return web?.enabled ? web.domains : [];
}

// The base config's attended classes, {name: meaning}, or {} when unset.
export function attendedClassesFromBase(env) {
  return configFromBase(env).attended?.classes ?? {};
}

// The base config's `branch-cleanup` leaf as set, likewise; its defaults have
// one copy, in .github/scripts/branch-cleanup/rules.mjs.
export function branchCleanupFromBase(env) {
  return configFromBase(env)["branch-cleanup"] ?? {};
}

// A run that is no lane activity resolves only its model route.
function resolveRouteFromBase(env) {
  if (env.LANE) {
    throw new Error("set lane or model-route, not both");
  }
  const { basePath, configPath } = pathsOf(env);
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
