
import { appendFileSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  commitPulls,
  createGitHub,
  detailSuffix,
  ETAG,
  GitHubError,
  graphQLReader,
  isFault,
  responseDetail,
} from "../lib/github-client.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { listChangedAt } from "../lib/trusted-actors.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { PR_READS, prReads, titleRenamers } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { issuesSuffix, isVerdictName, NAME } from "./write-verdict.mjs";
import { specSource } from "./spec-source.mjs";
import { authorSkip, baselineOnly, DEPENDENCY_MANAGERS, isDependencyManager, loginKey, refsIssue, visibleLines } from "../pr-merge/merge-holds.mjs";
import { GATE_ALIAS, gateEntries } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { ACTIONS_BOT_ID, briefedIssue, carriesSplit, ownAgentIds, readSchedule, SOURCE_LABEL, sourceLabels, webHostsFrom } from "../intake-triage/admit.mjs";
import { actionsBotOnly, baseAdmissionRules, DRIFT_TITLE, driftIssue, loadRules, ownAgentText, personChecks, refinementSpec, SPLIT_CHILD_MARKER, splitChildBody, splitScope, taskItems, trustedDriftSpec, vendoredDriftLead, vendoredRows } from "../intake-triage/issue-spec.mjs";
import { issueBody, issueTitle, SCHEDULE_MARKER } from "../recurring-schedule/file-due.mjs";
import { FILING, incidentKey, readMarker } from "../maintenance-monitor-signals/issues.mjs";

export { DEPENDENCY_MANAGERS, isDependencyManager, refsIssue, vendoredRows };

export { isVerdictName, NAME, NAME_MAX } from "./write-verdict.mjs";

export const UPSTREAM_PATH = ".github/workflows/pr-require-checks.yml";
export const VERIFY_PATH = ".github/workflows/pr-verify.yml";

export const shapeJobs = (runId, jobs) => ({
  run_id: Number(runId),
  jobs: jobs.map((job) => ({ name: String(job?.name ?? ""), conclusion: job?.conclusion ?? null, url: typeof job?.html_url === "string" ? job.html_url : null })),
});

export const KEPT_JOBS = "pr-verify-upstream-jobs.json";
export const keptJobsPath = (env) => (env.RUNNER_TEMP ? path.join(env.RUNNER_TEMP, KEPT_JOBS) : null);

const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;

export function readUpstreamRun(eventText) {
  const run = JSON.parse(eventText)?.workflow_run;
  if (run === null || typeof run !== "object" || Array.isArray(run)) {
    throw new Error("the event payload holds no workflow_run");
  }
  return run;
}

// The jobs of `run`'s own attempt, which a later attempt does not change
// (https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run-attempt).
export const attemptJobsPath = (repository, run, page) =>
  `/repos/${repository}/actions/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=100${page === undefined ? "" : `&page=${page}`}`;
const isAttempt = (value) => Number.isSafeInteger(value) && value >= 1;
const MAX_PAGES = 100;

const incomplete = (message) => Object.assign(new Error(message), { incomplete: true });
const shortList = (message, count, cap) => (Number.isSafeInteger(count) && count > cap ? new Error(message) : incomplete(message));

const COMMENT_FIELDS = "totalCount pageInfo { hasNextPage endCursor } nodes { databaseId createdAt updatedAt body lastEditedAt author { ...actor } editor { ...actor } }";
const ISSUE_FIELDS = `number repository { nameWithOwner } title body lastEditedAt
          author { ...actor } editor { ...actor } labels(first: 50) { totalCount nodes { name } }
          comments(first: 100) { ${COMMENT_FIELDS} }`;
const ACTOR = "fragment actor on Actor { __typename login ... on User { databaseId } ... on Bot { databaseId } }";
const COMMENT_PAGE_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) { number comments(first: 100, after: $after) { ${COMMENT_FIELDS} } }
  }
}
${ACTOR}`;
export const COMMENT_PAGES = 10;
const RELINK_FIELDS = `userContentEdits(first: 100) { totalCount nodes { editedAt editor { ...actor } } }
      links: timelineItems(first: 100, itemTypes: [CONNECTED_EVENT, DISCONNECTED_EVENT]) {
        filteredCount nodes { ... on ConnectedEvent { createdAt actor { ...actor } } ... on DisconnectedEvent { createdAt actor { ...actor } } }
      }`;
const RENAME_FIELDS = `renames: timelineItems(itemTypes: [RENAMED_TITLE_EVENT], first: 100) {
        nodes { ... on RenamedTitleEvent { actor { ...actor } } }
        pageInfo { hasNextPage endCursor }
      }`;
const specQuery = (extra = "") => `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      createdAt body lastEditedAt editor { ...actor }${extra}
      closingIssuesReferences(first: 10) {
        totalCount
        nodes {
          ${ISSUE_FIELDS}
        }
      }
    }
  }
}
${ACTOR}`;
const SPEC_QUERY = specQuery();
const REFS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issueOrPullRequest(number: $number) { __typename ... on Issue { ${ISSUE_FIELDS} } }
  }
}
${ACTOR}`;

const SIBLING_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issueOrPullRequest(number: $number) {
      __typename
      ... on PullRequest { number merged mergedAt baseRefName body lastEditedAt author { ...actor } editor { ...actor } repository { nameWithOwner } closingIssuesReferences(first: 1) { totalCount } }
    }
  }
}
${ACTOR}`;

const PARENT_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      parent { number repository { nameWithOwner } body lastEditedAt author { ...actor } editor { ...actor }
        comments(first: 100) { ${COMMENT_FIELDS} } }
    }
  }
}
${ACTOR}`;

export const RELINK_QUERY =
  "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){" +
  "pullRequest(number:$n){userContentEdits(first:100){totalCount " +
  "nodes{editedAt editor{...actor}}} " +
  "timelineItems(first:100,itemTypes:[CONNECTED_EVENT,DISCONNECTED_EVENT]){" +
  "filteredCount nodes{... on ConnectedEvent{createdAt actor{...actor}} " +
  "... on DisconnectedEvent{createdAt actor{...actor}}}}}}}" +
  "fragment actor on Actor{__typename login ... on User{databaseId} ... on Bot{databaseId}}";

const trustedHuman = (actor, humans) => actor?.__typename === "User" && humans.has(actor.databaseId);

async function actedByPeople(github, repository, number, humans, since, bodyEdit, read) {
  const start = Date.parse(since ?? "");
  const acts = await actsFrom(github, repository, number, start, read);
  const inside = (acts ?? []).filter(([at]) => Date.parse(at) >= start);
  return inside.some(([, , kind]) => !bodyEdit || kind === "edit") && inside.every(([, actor]) => trustedHuman(actor, humans));
}

export const relinkedByPeople = (github, repository, number, humans, since, read) => actedByPeople(github, repository, number, humans, since, false, read);

export const editedByPeople = (github, repository, number, humans, since, read) => actedByPeople(github, repository, number, humans, since, true, read);

async function relinkActs(github, repository, number) {
  const [o, r] = repository.split("/");
  let pull;
  try {
    pull = (await github("POST", "/graphql", { query: RELINK_QUERY, variables: { o, r, n: number } }))?.data?.repository?.pullRequest;
  } catch {
    return null;
  }
  return actsOf(pull?.userContentEdits, pull?.timelineItems);
}

function actsOf(edits, events) {
  if (!Array.isArray(edits?.nodes) || edits.totalCount !== edits.nodes.length || !Array.isArray(events?.nodes) || events.filteredCount !== events.nodes.length) {
    return null;
  }
  const acts = [...edits.nodes.map((node) => [node?.editedAt, node?.editor, "edit"]), ...events.nodes.map((node) => [node?.createdAt, node?.actor, "link"])];
  return acts.some(([at]) => Number.isNaN(Date.parse(at ?? ""))) ? null : acts;
}

const actsFrom = async (github, repository, number, start, read) =>
  Number.isNaN(start) ? null : (read ?? (() => relinkActs(github, repository, number)))();

export async function relinkedSince(github, repository, number, since, read) {
  const start = Date.parse(since ?? "");
  const acts = await actsFrom(github, repository, number, start, read);
  return acts === null || acts.some(([at]) => Date.parse(at) >= start);
}

export function namesNothing(answer, field) {
  const repository = answer?.data?.repository;
  const errors = answer?.errors;
  return (
    repository !== null &&
    typeof repository === "object" &&
    Object.hasOwn(repository, field) &&
    repository[field] === null &&
    Array.isArray(errors) &&
    errors.length > 0 &&
    errors.every((e) => e?.type === "NOT_FOUND" && Array.isArray(e.path) && e.path.length === 2 && e.path[0] === "repository" && e.path[1] === field)
  );
}

const actorFields = (actor, role) => ({
  [`${role}_login`]: typeof actor?.login === "string" ? actor.login : null,
  [`${role}_id`]: Number.isSafeInteger(actor?.databaseId) ? actor.databaseId : null,
  [`${role}_type`]: typeof actor?.__typename === "string" ? actor.__typename : null,
});

export const HOLD_STEP = "Fail a lanes App pull request on kill switch, hold path, verifier or veto";
const OLD_HOLD_STEP = "Fail a lanes App pull request its body or a member holds";
const HOLD_STEPS = [HOLD_STEP, OLD_HOLD_STEP];
export const AGGREGATE_STEP = "Aggregate lane results";
/**
 * The ci-status step that fails on ci-workflows' check-contract (title,
 * `do-not-merge` label, issue linkage), its own error line, and the one error
 * line check-contract's run.sh writes for the label, whose name
 * pr-require-checks.yml leaves the default. check-contract runs inside the
 * report-ci-status composite, which AGGREGATE_STEP names: that step still
 * succeeds, but its log keeps check-contract's lines and exit. A run from
 * before the composite reports OLD_CONTRACT_STEP, which ran check-contract
 * itself.
 */
export const CONTRACT_STEP = "Fail on the contract or draft policy";
export const CONTRACT_LINE = "ci-status: the pull-request contract or the draft policy failed; see the step above.";
const OLD_CONTRACT_STEP = "Check the pull-request contract";
const CONTRACT_STEPS = [CONTRACT_STEP, OLD_CONTRACT_STEP];
export const DO_NOT_MERGE_LINE = "check-contract: this PR carries the 'do-not-merge' label; remove it to merge.";
export const PERSON_LIFT = "; an approving review of this head by a person on the trusted-actor list lifts it";
const STEP_EXIT = "Process completed with exit code 1.";
const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
export const personHoldLine = (line, number) =>
  !line.includes("a cost path") &&
  new RegExp(
    `^#${number}: it changes .+, a hold path${escapeRegExp(PERSON_LIFT)}, and the approval carries over later merges (?:that bring only the base's changes|of the base that leave its net change the same); then re-run ci-status\\.$`,
  ).test(line);

export const errorLines = (log) =>
  String(log)
    .split(/\r?\n/)
    .flatMap((line) => /^﻿?(?:\S+ )?##\[error\](.*)$/.exec(line)?.slice(1) ?? []);

async function heldShape(read) {
  try {
    const listed = await read();
    const jobs = listed?.jobs;
    if (!Array.isArray(jobs) || listed.total_count !== jobs.length) {
      return null;
    }
    const ci = gateEntries(jobs);
    if (ci.length !== 1 || ci[0].conclusion !== "failure" || !Number.isSafeInteger(ci[0].id)) {
      return null;
    }
    const alias = (job) => job?.name === GATE_ALIAS && job !== ci[0];
    if (jobs.some((job) => job !== ci[0] && !alias(job) && !["success", "skipped", "neutral"].includes(job?.conclusion))) {
      return null;
    }
    const steps = Array.isArray(ci[0].steps) ? ci[0].steps : [];
    const failed = steps.filter((step) => step?.conclusion !== "success" && step?.conclusion !== "skipped");
    const names = failed.map((step) => step?.name);
    if (
      failed.length === 0 ||
      failed.some((step) => step.conclusion !== "failure" || ![...HOLD_STEPS, ...CONTRACT_STEPS].includes(step.name)) ||
      new Set(names).size !== names.length ||
      names.filter((name) => CONTRACT_STEPS.includes(name)).length > 1 ||
      !steps.some((step) => step?.name === AGGREGATE_STEP && step.conclusion === "success")
    ) {
      return null;
    }
    return { ciId: ci[0].id, names };
  } catch {
    return null;
  }
}

async function heldOnly(readLog, { ciId, names }, number) {
  try {
    const errors = errorLines(await readLog(ciId));
    const reasons = errors.filter((line) => line !== STEP_EXIT);
    const person = reasons.filter((line) => personHoldLine(line, number));
    const label = reasons.filter((line) => line === DO_NOT_MERGE_LINE);
    const own = reasons.filter((line) => line === CONTRACT_LINE);
    const composite = names.includes(CONTRACT_STEP) ? 1 : 0;
    return (
      errors.length - reasons.length === names.length + composite &&
      person.length + label.length + own.length === reasons.length &&
      (person.length > 0) === names.some((name) => HOLD_STEPS.includes(name)) &&
      label.length === (names.some((name) => CONTRACT_STEPS.includes(name)) ? 1 : 0) &&
      own.length === composite
    );
  } catch {
    return false;
  }
}

const latestJobs = (github, repository, runId) => github("GET", `/repos/${repository}/actions/runs/${runId}/jobs?filter=latest&per_page=100`);

export const DRAFT_STEP = "Note a draft";

export async function draftRun(github, repository, runId, read) {
  const listed = await (read ?? (() => latestJobs(github, repository, runId)))();
  const jobs = listed?.jobs;
  if (!Array.isArray(jobs) || listed.total_count !== jobs.length) {
    throw shortList(`the jobs of run ${runId} could not be read whole`, listed?.total_count, 100);
  }
  const ci = gateEntries(jobs);
  const steps = ci.length === 1 && Array.isArray(ci[0].steps) ? ci[0].steps.filter((step) => step?.name === DRAFT_STEP) : [];
  const conclusion = steps.length === 1 ? steps[0].conclusion : undefined;
  if (conclusion === "success" || conclusion === "skipped") {
    return conclusion === "success";
  }
  const message = `run ${runId}'s draft state could not be read: ci-status lists no conclusion for ${DRAFT_STEP}`;
  throw ci.length === 1 && steps.length === 0 ? incomplete(message) : new Error(message);
}

export function draftJudgments(github, repository, head) {
  let listing;
  const drafts = new Map();
  return async (verify) => {
    try {
      listing ??= github("GET", `/repos/${repository}/actions/workflows/${UPSTREAM_PATH.split("/").at(-1)}/runs?head_sha=${head}&event=pull_request&per_page=100`);
      const listed = await listing;
      const runs = listed?.workflow_runs;
      if (!Array.isArray(runs) || listed.total_count !== runs.length) {
        return false;
      }
      const judgedAt = Date.parse(verify.created_at ?? "");
      if (Number.isNaN(judgedAt) || runs.some((run) => Number.isNaN(Date.parse(run?.created_at ?? "")))) {
        return false;
      }
      const before = runs.filter((run) => Date.parse(run.created_at) < judgedAt);
      for (const { id } of before) {
        if (!drafts.has(id)) {
          drafts.set(id, Number.isSafeInteger(id) ? draftRun(github, repository, id) : Promise.resolve(false));
        }
        if (!(await drafts.get(id))) {
          return false;
        }
      }
      return before.length > 0;
    } catch {
      return false;
    }
  };
}

// A 304 to an authorized If-None-Match is not counted against the primary rate limit
// (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests).
const emptyListingTags = new WeakMap();
const ETAG_FORM = /^(W\/)?"[!#-~]{1,200}"$/;

async function artifactsNamed(github, repository, name, { emptyIsSafe = false } = {}) {
  const artifacts = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const path = `/repos/${repository}/actions/artifacts?name=${encodeURIComponent(name)}&per_page=100&page=${page}`;
    const tag = page === 1 && emptyIsSafe ? emptyListingTags.get(github) : undefined;
    let listing;
    try {
      listing = await (tag === undefined ? github("GET", path) : github("GET", path, undefined, { "If-None-Match": tag }));
    } catch (error) {
      if (tag !== undefined && error instanceof GitHubError && error.status === 304) {
        return [];
      }
      throw error;
    }
    if (
      page === 1 &&
      !emptyListingTags.has(github) &&
      listing?.total_count === 0 &&
      Array.isArray(listing.artifacts) &&
      listing.artifacts.length === 0 &&
      ETAG_FORM.test(listing[ETAG] ?? "")
    ) {
      emptyListingTags.set(github, listing[ETAG]);
    }
    const batch = listing?.artifacts ?? [];
    artifacts.push(...batch);
    if (batch.length < 100) {
      return artifacts;
    }
  }
  throw new Error(`the ${name} artifacts have more than ${MAX_PAGES} pages`);
}

export async function countedBy(options) {
  return (await countedRun(options)) !== null;
}

export const ofOrigin = (run, { path, repository, base = "main" }) =>
  run?.path === path &&
  run.event === "workflow_run" &&
  run.head_branch === base &&
  run.repository?.full_name === repository &&
  run.head_repository?.full_name === repository &&
  SHA.test(run.head_sha ?? "");

async function countedRun({ github, repository, runId, verdict, base }) {
  let run;
  try {
    run = await github("GET", `/repos/${repository}/actions/runs/${runId}`);
  } catch {
    return null;
  }
  if (
    run?.id !== runId ||
    !ofOrigin(run, { path: VERIFY_PATH, repository, base }) ||
    run.status !== "completed" ||
    (verdict !== "fail" && run.conclusion !== "success")
  ) {
    return null;
  }
  try {
    const compare = await github("GET", `/repos/${repository}/compare/${run.head_sha}...${base}`);
    return compare?.status === "ahead" || compare?.status === "identical" ? run : null;
  } catch {
    return null;
  }
}

async function pullsOfCommit(github, repository, head) {
  const readRest = async () => {
    const pulls = [];
    for (let page = 1; page <= MAX_PAGES; page += 1) {
      const batch = await github("GET", `/repos/${repository}/commits/${head}/pulls?per_page=100&page=${page}`);
      if (!Array.isArray(batch)) {
        throw incomplete(`page ${page} is not a list`);
      }
      pulls.push(...batch);
      if (batch.length < 100) {
        return pulls;
      }
    }
    throw Object.assign(new Error(`the pull requests of ${head} have more than ${MAX_PAGES} pages`), { fallback: false });
  };
  return commitPulls({ repository, sha: head, readRest, readGraphQL: graphQLReader(github) });
}

async function judged({ github, repository, number, head, base, prs, issues, afterOwn = false, draftJudged }) {
  const named = (pr, verdict) => `pr-verify-${pr}-${head}-${verdict}`;
  const own = named(number, "fail");
  const suffix = issues === undefined ? "" : issuesSuffix(issues);
  const names =
    issues === undefined
      ? [
          ...(afterOwn ? [] : [own]),
          ...[...prs].filter((other) => other !== number).map((other) => named(other, "fail")),
          ...["pass", "pass-notes"].map((verdict) => named(number, verdict)),
        ]
      : suffix
        ? [own + suffix].filter(isVerdictName)
        : [];
  const passes = [];
  for (const name of names) {
    const [, , , verdict] = NAME.exec(name);
    const created = [];
    for (const artifact of await artifactsNamed(github, repository, name, { emptyIsSafe: verdict !== "fail" })) {
      if (artifact?.name !== name || artifact.expired !== false) {
        continue;
      }
      const runId = artifact.workflow_run?.id;
      const run = Number.isSafeInteger(runId) ? await countedRun({ github, repository, runId, verdict, base }) : null;
      if (run === null) {
        continue;
      }
      if (verdict !== "fail") {
        passes.push(run.run_started_at);
      } else if (await draftJudged(run)) {
        continue;
      } else if (name === own || name === own + suffix) {
        created.push(Date.parse(run.created_at ?? ""));
      } else {
        return { fail: true, passes };
      }
    }
    if (created.length > 0) {
      const at = (time) => (Number.isNaN(time) ? "" : new Date(time).toISOString());
      return { fail: false, passes, ownFail: at(Math.min(...created)), ownLast: at(Math.max(...created)) };
    }
  }
  return { fail: false, passes };
}

export function specChanged(passStarts, { linkedIssues: issues, specKind, bodyEditedAt, listChangedAt }) {
  const times = [
    ...issues.flatMap((issue) => [issue.last_edited_at, ...issue.spec_comments.map((comment) => comment.updated_at)]),
    ...(specKind === "pull-request" ? [bodyEditedAt] : []),
    listChangedAt,
  ].map((time) => Date.parse(time ?? ""));
  const changed = Math.max(-Infinity, ...times.filter((time) => !Number.isNaN(time)));
  return !passStarts.some((start) => Date.parse(start ?? "") > changed);
}

export const SIBLINGS_MAX = 10;
const SIBLINGS_LINE = /^siblings:/i;
const SIBLINGS_PLAIN = /^Siblings:[ \t]*(#[1-9][0-9]{0,8}(?:[ \t]*,[ \t]*#[1-9][0-9]{0,8})*)[ \t]*$/;
export function siblingNumbers(body) {
  const numbers = new Set();
  for (const line of visibleLines(body)) {
    if (!SIBLINGS_LINE.test(line)) {
      continue;
    }
    const plain = SIBLINGS_PLAIN.exec(line);
    if (!plain) {
      return [];
    }
    for (const digits of plain[1].match(/[0-9]+/g)) {
      numbers.add(Number(digits));
    }
  }
  return numbers.size <= SIBLINGS_MAX ? [...numbers] : [];
}

async function creditedSiblings(readRefs, repository, number, body, base, humans, laneAppId) {
  const [owner, name] = repository.split("/");
  const lanesApp = (actor) => laneAppId !== undefined && actor?.__typename === "Bot" && actor.databaseId === laneAppId;
  const credited = [];
  for (const sibling of siblingNumbers(body).filter((n) => n !== number)) {
    const answer = await readRefs("POST", "/graphql", { query: SIBLING_QUERY, variables: { owner, name, number: sibling } });
    const node = answer?.data?.repository?.issueOrPullRequest;
    if (answer?.errors ? !namesNothing(answer, "issueOrPullRequest") : node === null || typeof node !== "object") {
      const message = `#${number}: sibling #${sibling} could not be read`;
      throw answer?.errors ? new Error(message) : incomplete(message);
    }
    const merged = node?.__typename === "PullRequest" && node.number === sibling && node.merged === true && node.repository?.nameWithOwner === repository && node.baseRefName === base;
    const slice = merged && node.closingIssuesReferences?.totalCount === 0 && (trustedHuman(node.author, humans) || lanesApp(node.author));
    const kept = node?.lastEditedAt == null || trustedHuman(node.editor, humans) || (lanesApp(node.editor) && Date.parse(node.lastEditedAt) <= Date.parse(node.mergedAt ?? ""));
    const issue = slice && kept ? refsIssue(node.body) : null;
    if (issue !== null) {
      credited.push({ issue, number: sibling, body: String(node.body) });
    }
  }
  return credited;
}

export function recurringSpec(issue, schedule) {
  const marks = [...String(issue?.body ?? "").matchAll(SCHEDULE_MARKER)];
  if (issue?.author?.__typename !== "Bot" || issue.author.databaseId !== ACTIONS_BOT_ID || marks.length !== 1) {
    return null;
  }
  const rows = Array.isArray(schedule?.items) ? schedule.items.filter((row) => row?.id === marks[0][1]) : [];
  return rows.length === 1 && typeof rows[0].title === "string" && rows[0].title !== "" ? `# ${issueTitle(rows[0])}\n\n${issueBody(rows[0])}` : null;
}

const PIN_PREFIX = "**Last audited upstream state:**";
const PIN_MARKER = /^\*\*Last audited upstream state:\*\* `([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)@[0-9a-f]{40}`/;
const COMPARE_FILES_CAP = 300;

export function upstreamPages(dir = fileURLToPath(new URL("../../../docs/upstream/", import.meta.url)), prefix = "docs/upstream") {
  const pages = new Map();
  let names;
  try {
    names = readdirSync(dir, { recursive: true }).map(String).filter((name) => name.endsWith(".md")).sort();
  } catch {
    return pages;
  }
  for (const name of names) {
    let line;
    try {
      line = readFileSync(path.join(dir, name), "utf8").split("\n").find((text) => text.includes(PIN_PREFIX));
    } catch {
      continue;
    }
    const mark = PIN_MARKER.exec(line ?? "");
    if (mark) {
      pages.set(`${prefix}/${name.split(path.sep).join("/")}`, mark[1]);
    }
  }
  return pages;
}

const VENDORED_UNSAFE = new Set(["scripts", "hooks", "lib", ".claude-plugin", ".mcp.json", "evals", "..", "."]);
const VENDOR_INERT = /(?:\.md|\.jsonc|^LICENSE)$/;
export function vendoredPath(plugin, name) {
  if (typeof plugin !== "string" || typeof name !== "string") {
    return false;
  }
  const fragment = `.changes/${plugin}/`;
  if (name.startsWith(fragment)) {
    return /^[^/]+\.md$/.test(name.slice(fragment.length));
  }
  const parts = name.split("/");
  const vendored = parts.slice(4, -1).includes("vendor");
  const procedure = (parts[3] === "update" && !vendored) || (parts.at(-2) === "actions" && parts.at(-1) === "update.md");
  return (
    name.startsWith(`plugins/${plugin}/skills/`) &&
    parts.length > 4 &&
    parts.every((part) => part !== "" && !VENDORED_UNSAFE.has(part)) &&
    !procedure &&
    (vendored ? VENDOR_INERT.test(parts.at(-1)) : name.endsWith(".md"))
  );
}

export const skillFile = (name) => typeof name === "string" && /^plugins\/[^/]+\/skills\/(?:[^/]+\/)+SKILL\.md$/i.test(name) &&!name.split("/").slice(4, -1).includes("vendor");

const SYNC_STAMP = /^ {2}(upstream-version|upstream-sha|synced): ("?)[\w.\/@:+-]+\2$/;
const PRECOMPUTE_FENCE = /(?:`{3,}|~{3,})\s*!/;

function skillSurface(text) {
  const lines = typeof text === "string" ? text.split("\n") : [];
  const end = lines[0] === "---" ? lines.indexOf("---", 1) : -1;
  if (end === -1 || lines.some((line) => PRECOMPUTE_FENCE.test(line))) {
    return null;
  }
  return {
    front: lines.slice(1, end).map((line) => (SYNC_STAMP.test(line) ? line.slice(0, line.indexOf(":") + 1) : line)),
    precompute: lines.slice(end + 1).filter((line) => line.includes("!`")),
  };
}

export function skillTextSafe(base, head) {
  const before = skillSurface(base);
  const after = skillSurface(head);
  return before !== null && after !== null && JSON.stringify(before) === JSON.stringify(after);
}

function vendoredSkillSafe(file) {
  if (skillFile(file?.previous_filename)) {
    return false;
  }
  return !skillFile(file?.filename) || (file.status === "modified" && skillTextSafe(file.texts?.base, file.texts?.head));
}

const VENDORED_REPORT_SCRIPT = fileURLToPath(new URL("../../../scripts/upstream-drift-vendored-report.sh", import.meta.url));
const ALL_VENDORED_ROW = /^\s*"([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\|plugins\/([A-Za-z0-9][A-Za-z0-9_.-]*)\/[^|"]*\|[^|"]*(\|files-only)?"\s*$/;
const ALL_VENDORED_ROW_ID = /^\s*"([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\|/;

export function allVendoredRows(file = VENDORED_REPORT_SCRIPT) {
  const rows = new Map();
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch {
    return rows;
  }
  for (const line of text.split("\n")) {
    const row = ALL_VENDORED_ROW.exec(line);
    if (row) {
      const prev = rows.get(row[1]);
      const plugin = !rows.has(row[1]) || prev?.plugin === row[2] ? row[2] : null;
      const filesOnly = Boolean(row[3]) && (!rows.has(row[1]) || prev?.filesOnly === true);
      rows.set(row[1], plugin === null ? null : { plugin, filesOnly });
    } else {
      const id = ALL_VENDORED_ROW_ID.exec(line)?.[1];
      if (id !== undefined) {
        rows.set(id, null);
      }
    }
  }
  return rows;
}

export function vendoredPluginPath(plugin, name) {
  if (typeof plugin !== "string" || typeof name !== "string") {
    return false;
  }
  const fragment = `.changes/${plugin}/`;
  if (name.startsWith(fragment)) {
    return /^[^/]+\.md$/.test(name.slice(fragment.length));
  }
  const parts = name.split("/");
  return name.startsWith(`plugins/${plugin}/`) && parts.length > 2 && parts.every((part) => part !== "" && part !== "." && part !== "..");
}

export function vendoredNonFilesOnlySpecText(id, plugin) {
  return [
    `# Upstream drift: ${id}`,
    "",
    `Bring this repository's vendored copy of upstream \`${id}\` in \`plugins/${plugin}/\` up to date per its row in \`scripts/upstream-drift-vendored-report.sh\`. Fold what changed upstream into the plugin's distilled files and add a changelog fragment under \`.changes/${plugin}/\`; leave the plugin's \`version\` and \`CHANGELOG.md\` unchanged. An upstream change that would change the design of one of this repository's skills is not applied without owner approval. The pull request changes only files under \`plugins/${plugin}/\` and \`.changes/${plugin}/\` and closes this issue with \`Closes #<this issue>\`.`,
    "",
    "## Done when",
    "",
    `- [ ] The vendored copy of \`${id}\` in \`plugins/${plugin}/\` is brought up to date as its row's drift-check script reports it.`,
    "- [ ] Relevant upstream changes are folded into the plugin's distilled files, or the pull request body says why any are left out.",
    `- [ ] The plugin carries a changelog fragment under \`.changes/${plugin}/\` and its \`version\` and \`CHANGELOG.md\` are unchanged.`,
    `- [ ] The pull request changes only files under \`plugins/${plugin}/\` and \`.changes/${plugin}/\`, and its body closes this issue with \`Closes\`.`,
  ].join("\n");
}

export function driftSpec(issue, pages, files, rows = vendoredRows(), allRows = allVendoredRows()) {
  if (!Array.isArray(files) || files.length === 0 || files.length >= COMPARE_FILES_CAP) {
    return null;
  }
  const drift = driftIssue(issue, rows);
  if (drift === null) {
    const id = actionsBotOnly(issue) ? DRIFT_TITLE.exec(String(issue?.title ?? ""))?.[1] : undefined;
    const lead = String(issue?.body ?? "").split("\n", 1)[0].replace(/\r$/, "");
    const entry = id !== undefined && lead === vendoredDriftLead(id) ? allRows.get(id) : null;
    if (!entry || entry.filesOnly || typeof entry.plugin !== "string") {
      return null;
    }
    const inside = (name) => vendoredPluginPath(entry.plugin, name);
    return files.every((file) => inside(file?.filename) && (file.previous_filename === undefined || inside(file.previous_filename)))
      ? vendoredNonFilesOnlySpecText(id, entry.plugin)
      : null;
  }
  if (drift.kind === "vendored") {
    const plugin = rows.get(drift.id);
    const inside = (name) => vendoredPath(plugin, name);
    return typeof plugin === "string" && files.every((file) => inside(file?.filename) && (file.previous_filename === undefined || inside(file.previous_filename)) && vendoredSkillSafe(file)) ? trustedDriftSpec(drift) : null;
  }
  const own = [...pages].filter(([, upstream]) => upstream === drift.id).map(([page]) => page);
  if (own.length === 0 || !files.every((file) => file?.status === "modified" && own.includes(file.filename))) {
    return null;
  }
  return trustedDriftSpec(drift, own);
}

const MAIN_RED = "1 main red";
export const MAIN_RED_TITLE = FILING[MAIN_RED].title;
const MAIN_RED_KEY = incidentKey(MAIN_RED);

export const MAIN_RED_SPEC = [
  `# ${MAIN_RED_TITLE}`,
  "",
  "A required check on main fails or flakes. Make main's required checks pass again by fixing the cause of that failure. Fixing the cause is the whole delivery: the monitoring lane closes this issue on its own once the signal stays clear, so a pull request that links it with `Refs:` names no remaining work.",
  "",
  "## Done when",
  "",
  "- [ ] The cause of the failing or flaky required check on main is fixed, without weakening, skipping or deleting that check or any other.",
  "- [ ] The change does not widen beyond that fix.",
].join("\n");

export const mainRedIncident = (issue) => actionsBotOnly(issue) && issue.title === MAIN_RED_TITLE && readMarker(issue.body)?.key === MAIN_RED_KEY;

const MONITOR_BY_KEY = new Map(
  Object.entries(FILING)
    .filter(([signal]) => signal !== MAIN_RED)
    .map(([signal, { title }]) => [incidentKey(signal), { signal, title }]),
);

export function monitorIncidentSpec(signal, title) {
  return [
    `# ${title}`,
    "",
    `The monitoring lane filed this incident for signal \`${signal}\`. Fix the cause of that signal without weakening, skipping or deleting any check, security control or billing/rate hold. Fixing the cause is the whole delivery: the monitoring lane closes this issue on its own once the signal stays clear, so a pull request that links it with \`Refs:\` names no remaining work.`,
    "",
    "## Done when",
    "",
    `- [ ] The cause of the \`${signal}\` monitoring signal is fixed, without weakening, skipping or deleting any check, security control or hold.`,
    "- [ ] The change does not widen beyond that fix.",
  ].join("\n");
}

export function monitorIncident(issue) {
  if (!actionsBotOnly(issue)) {
    return null;
  }
  const marker = readMarker(issue.body);
  const entry = marker ? MONITOR_BY_KEY.get(marker.key) : undefined;
  return entry && issue.title === entry.title ? monitorIncidentSpec(entry.signal, entry.title) : null;
}

export const DEAD_LINKS_MARKER = "<!-- link-check-dead-pointer rollup -->";
export const DEAD_LINKS_TITLE = "Dead links found by the online link check";
export const DEAD_LINKS_SPEC = [
  `# ${DEAD_LINKS_TITLE}`,
  "",
  "Repair or demote dead external links reported by the weekly online link check, following `plugins/attribution/skills/audit/reference/dispositions.md`: point at a live source holding the same fact, demote to a stamped record or archived-snapshot citation without re-expanding into a copy, or add an exact-URL `.lycheeignore` entry for a live page that refuses the checker (with the dated reason in the commit message). The online link-check workflow closes this rollup on its own once no dead links remain, so a pull request that links it with `Refs:` names no remaining work.",
  "",
  "## Done when",
  "",
  "- [ ] Each dead link the pull request addresses is removed, replaced with a live pointer or demoted record, or given an exact-URL `.lycheeignore` entry.",
  "- [ ] The change does not weaken or disable the link check or widen beyond repairing those links.",
].join("\n");

export const deadLinksRollup = (issue) =>
  actionsBotOnly(issue) &&
  issue.title === DEAD_LINKS_TITLE &&
  String(issue.body ?? "").split("\n", 1)[0].replace(/\r$/, "") === DEAD_LINKS_MARKER;

const DEMOTION = "babysit-merge-demotion";
const DEMOTION_MARKER = /^<!-- babysit-merge-demotion sha=[0-9a-f]{40} signal=(schedule|dispatch|canary|revert|read-back) -->$/;

export function demotionAlertSpec(signal) {
  return [
    `# Resolve post-merge demotion (${signal})`,
    "",
    `A post-merge demotion alert (\`${DEMOTION}\`, signal \`${signal}\`) demoted unattended merging. Fix the underlying post-merge failure, restore or confirm the reverted change, or acknowledge an intentional deletion (such as in \`scripts/silent-revert-acknowledged.txt\` for a canary false positive) without weakening, skipping or deleting any check. The demotion lifts and closes automatically once resolved on main, so a pull request that links it with \`Refs:\` names no remaining work.`,
    "",
    "## Done when",
    "",
    `- [ ] The underlying cause of the post-merge \`${signal}\` demotion is fixed (or the intentional change is acknowledged) without weakening, skipping or deleting any check.`,
    "- [ ] The change does not widen beyond resolving that demotion.",
  ].join("\n");
}

export function demotionAlert(issue, laneAppId) {
  const botFiled = actionsBotOnly(issue) || (laneAppId !== undefined && ownAgentText(issue, new Set([laneAppId])));
  if (!botFiled || typeof issue?.title !== "string" || !issue.title.endsWith(": unattended merging demoted")) {
    return null;
  }
  const first = String(issue.body ?? "").split("\n", 1)[0].replace(/\r$/, "");
  const match = DEMOTION_MARKER.exec(first);
  return match ? demotionAlertSpec(match[1]) : null;
}

const SKILL_READS_MAX = 10;

async function fileText(github, repository, name, ref) {
  const file = await github("GET", `/repos/${repository}/contents/${name.split("/").map(encodeURIComponent).join("/")}?ref=${ref}`);
  if (file?.encoding !== "base64" || typeof file.content !== "string") {
    throw incomplete(`${name} at ${ref} could not be read`);
  }
  return Buffer.from(file.content, "base64").toString("utf8");
}

async function compareFiles(github, repository, base, head) {
  const answer = await github("GET", `/repos/${repository}/compare/${base}...${head}`);
  if (!Array.isArray(answer?.files)) {
    throw incomplete(`the changed files from ${base} to ${head} could not be read`);
  }
  const mergeBase = answer.merge_base_commit?.sha;
  const skills = answer.files.filter((file) => file?.status === "modified" && skillFile(file.filename));
  if (skills.length === 0 || skills.length > SKILL_READS_MAX || typeof mergeBase !== "string") {
    return answer.files;
  }
  const texts = new Map();
  for (const { filename } of skills) {
    texts.set(filename, { base: await fileText(github, repository, filename, mergeBase), head: await fileText(github, repository, filename, head) });
  }
  return answer.files.map((file) => (texts.has(file?.filename) ? { ...file, texts: texts.get(file.filename) } : file));
}

export const PERSON_CHECK = "Person check:";

async function wholeComments(github, repository, number, first, label, subject) {
  const unread = () => incomplete(`#${label}: ${subject}'s comments could not be read`);
  if (!Array.isArray(first?.nodes) || !Number.isSafeInteger(first.totalCount)) {
    throw unread();
  }
  const cap = COMMENT_PAGES * 100;
  if (first.totalCount > cap) {
    throw new Error(`#${label}: ${subject} has ${first.totalCount} comments, more than the ${cap} (${COMMENT_PAGES} pages) this read takes`);
  }
  const [owner, name] = repository.split("/");
  const nodes = [...first.nodes];
  let page = first;
  for (let pages = 1; nodes.length < first.totalCount && pages < COMMENT_PAGES; pages += 1) {
    const after = page.pageInfo?.endCursor;
    if (page.pageInfo?.hasNextPage !== true || typeof after !== "string") {
      throw unread();
    }
    const issue = (await github("POST", "/graphql", { query: COMMENT_PAGE_QUERY, variables: { owner, name, number, after } }))?.data?.repository?.issue;
    page = issue?.number === number ? issue.comments : null;
    if (!Array.isArray(page?.nodes) || page.nodes.length === 0) {
      throw unread();
    }
    nodes.push(...page.nodes);
  }
  if (nodes.length !== first.totalCount) {
    throw unread();
  }
  return { totalCount: first.totalCount, nodes };
}

export async function linkedIssues(github, readRefs, repository, number, humans, laneAppId, taskList, webHosts, read, base, schedule = readSchedule(), drift = {}) {
  const [owner, name] = repository.split("/");
  const variables = { owner, name, number };
  const data = await (read ? read(variables) : github("POST", "/graphql", { query: SPEC_QUERY, variables }));
  const refs = data?.data?.repository?.pullRequest?.closingIssuesReferences;
  if (!refs || !Array.isArray(refs.nodes) || refs.totalCount !== refs.nodes.length) {
    throw shortList(`#${number}: the closing issues could not be read`, refs?.totalCount, 10);
  }
  const trusted = (actor) => trustedHuman(actor, humans);
  const written = (item) => trusted(item?.author) && (item.lastEditedAt == null || trusted(item.editor));
  const ownIds = ownAgentIds(baseAdmissionRules(), laneAppId);
  let nodes = refs.nodes;
  const named = refs.totalCount === 0 ? refsIssue(data.data.repository.pullRequest.body) : null;
  if (named !== null) {
    const answer = await readRefs("POST", "/graphql", { query: REFS_QUERY, variables: { owner, name, number: named } });
    const node = answer?.data?.repository?.issueOrPullRequest;
    if (answer?.errors ? !namesNothing(answer, "issueOrPullRequest") : node === null || typeof node !== "object") {
      const message = `#${number}: the Refs issue could not be read`;
      throw answer?.errors ? new Error(message) : incomplete(message);
    }
    nodes = node?.__typename === "Issue" ? [node] : [];
  }
  const issues = [];
  for (const issue of nodes.filter((item) => item?.repository?.nameWithOwner === repository && Number.isSafeInteger(item.number))) {
    issues.push({ ...issue, comments: await wholeComments(github, repository, issue.number, issue.comments, issue.number, "the issue") });
  }
  const childBodies = new Map();
  for (const issue of issues) {
    if (laneAppId === undefined || issue.author?.__typename !== "Bot" || issue.author.databaseId !== laneAppId || !String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER)) {
      continue;
    }
    const read = (await github("POST", "/graphql", { query: PARENT_QUERY, variables: { owner, name, number: issue.number } }))?.data?.repository?.issue;
    if (read === null || typeof read !== "object" || !Object.hasOwn(read, "parent")) {
      throw incomplete(`#${issue.number}: the split parent could not be read`);
    }
    const parent = read.parent;
    const here = parent?.repository?.nameWithOwner === repository;
    const comments = here ? await wholeComments(github, repository, parent.number, parent.comments, issue.number, "the split parent") : null;
    const body = here ? splitChildBody({ ...issue, splitParent: { number: parent.number, spec: { ...parent, comments: comments.nodes }, appId: laneAppId } }, humans, taskList) : null;
    if (body !== null) {
      childBodies.set(issue.number, body);
    }
  }
  const driftBodies = new Map();
  const driftShaped = (issue) => issue.author?.__typename === "Bot" && issue.author.databaseId === ACTIONS_BOT_ID && DRIFT_TITLE.test(String(issue.title ?? ""));
  if (named === null && typeof drift.changedFiles === "function" && issues.some(driftShaped)) {
    const files = await drift.changedFiles();
    const pages = drift.pages ?? upstreamPages();
    for (const issue of issues) {
      const body = driftSpec(issue, pages, files, drift.rows ?? vendoredRows(), drift.allRows ?? allVendoredRows());
      if (body !== null) {
        driftBodies.set(issue.number, body);
      }
    }
  }
  const pullRequest = data.data.repository.pullRequest;
  const siblings = base !== undefined && named === null && issues.length > 0 ? await creditedSiblings(readRefs, repository, number, pullRequest.body, base, humans, laneAppId) : [];
  return {
    bodyEditor: pullRequest.lastEditedAt == null ? null : (pullRequest.editor?.databaseId ?? 0),
    bodyEditedAt: pullRequest.lastEditedAt ?? null,
    linkedIssues: issues.map((issue) => ({
      number: issue.number,
      ...actorFields(issue.author, "author"),
      last_edited_at: typeof issue.lastEditedAt === "string" ? issue.lastEditedAt : null,
      ...actorFields(issue.editor, "editor"),
      spec_comments: issue.comments.nodes
        .filter(written)
        .map((comment) => ({ id: comment.databaseId, updated_at: comment.updatedAt })),
    })),
    specKind: issues.length === 0 ? "none" : named !== null ? "refs" : "closes",
    specText: issues.map((issue) => {
      const newest = written(issue) ? refinementSpec(issue.comments.nodes, laneAppId) : undefined;
      const refinement = Date.parse(newest?.createdAt ?? "") < Date.parse(pullRequest.createdAt ?? "") ? newest : undefined;
      const checks = refinement === undefined ? [] : personChecks({ ...issue, comments: issue.comments.nodes }, humans, laneAppId, taskList, webHosts);
      const counted = refinement !== undefined && (checks.length > 0 || !carriesSplit(refinement.body)) ? refinement : undefined;
      const items = taskItems(issue.body, taskList);
      const marked = written(issue) ? items.flatMap(({ text }, i) => (text.startsWith(PERSON_CHECK) ? [i + 1] : [])) : [];
      const person = [...new Set([...checks, ...marked])].sort((a, b) => a - b);
      const childBody = childBodies.get(issue.number);
      const sources = sourceLabels(issue.labels?.nodes);
      const spec = specSource({
        written: written(issue),
        body: issue.body,
        splitChild: childBody,
        splitMarked: String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER),
        ownFiling: sources.length === 1 && SOURCE_LABEL.test(sources[0]) && ownAgentText(issue, ownIds),
        briefed: briefedIssue({ ...issue, comments: issue.comments.nodes }, laneAppId),
        recurring: recurringSpec(issue, schedule),
        drift: driftBodies.get(issue.number) ?? null,
        incident: mainRedIncident(issue) ? MAIN_RED_SPEC : null,
        monitor: monitorIncident(issue),
        deadLinks: deadLinksRollup(issue) ? DEAD_LINKS_SPEC : null,
        demotion: demotionAlert(issue, laneAppId),
      });
      const scope = !written(issue) && childBody !== undefined ? splitScope(childBody) : null;
      return {
        number: issue.number,
        spec_kind: named !== null ? "refs" : "closes",
        ...spec,
        ...(scope !== null && { scope }),
        comments: issue.comments.nodes.filter((comment) => written(comment) || comment === counted).map((comment) => String(comment.body ?? "")),
        ...(person.length > 0 && { person_checks: person.map((n) => items[n - 1].text) }),
        ...(siblings.some((sibling) => sibling.issue === issue.number) && {
          credited_siblings: siblings.filter((sibling) => sibling.issue === issue.number).map(({ number: sibling, body }) => ({ number: sibling, body })),
        }),
      };
    }),
  };
}

export async function resolvePull({ github, readRefs = github, readLog, repository, upstreamRun: run, humans, base = "main", verifyAuthors = "lane", laneIdentity, laneAppId, baselineFile, taskList, webHosts, ownerIds: owners = [], specFromBodyApps = [], keepJobs, keepReads, rated, schedule = readSchedule(), upstreamPages: pages, trustedListChangedAt }) {
  const skip = (reason) => ({ proceed: false, reason });
  if (!RUN_ID.test(String(run?.id))) {
    throw new Error("the upstream run id is not a run id");
  }
  const upstreamRunId = run.id;
  if (
    !isAttempt(run.run_attempt) ||
    run.path !== UPSTREAM_PATH ||
    run.event !== "pull_request" ||
    run.status !== "completed" ||
    (run.conclusion !== "success" && run.conclusion !== "failure") ||
    run.repository?.full_name !== repository ||
    run.head_repository?.full_name !== repository ||
    !SHA.test(run.head_sha ?? "")
  ) {
    return skip("not-a-passing-run");
  }
  let jobs;
  const readJobs = () => (jobs ??= github("GET", attemptJobsPath(repository, run)));
  const shape = run.conclusion === "failure" && typeof readLog === "function" ? await heldShape(readJobs) : null;
  if (run.conclusion === "failure" && shape === null) {
    return skip("not-a-passing-run");
  }
  const head = run.head_sha;
  const associated = await pullsOfCommit(github, repository, head);
  const pulls = associated.filter(
    (pull) =>
      pull?.state === "open" &&
      pull.head?.sha === head &&
      pull.head?.repo?.full_name === repository &&
      pull.base?.ref === base,
  );
  if (pulls.length !== 1) {
    return skip("no-single-pr");
  }
  const [pull] = pulls;
  if (!Number.isSafeInteger(pull.number) || pull.number < 1 || !SHA.test(pull.base?.sha ?? "")) {
    return skip("no-single-pr");
  }
  if (pull.draft !== false) {
    return skip("draft");
  }
  const unjudged = authorSkip(pull.user, verifyAuthors, laneIdentity, owners);
  if (unjudged !== null) {
    return skip(unjudged);
  }
  if (run.conclusion === "failure" && !(await heldOnly(readLog, shape, pull.number))) {
    return skip("not-a-passing-run");
  }
  if (baselineOnly(pull.user, [baselineFile], laneAppId, baselineFile)) {
    const files = await github("GET", `/repos/${repository}/pulls/${pull.number}/files?per_page=100`);
    const paths = Array.isArray(files) ? files.flatMap((file) => [file?.filename, ...(file?.previous_filename ? [file.previous_filename] : [])]) : null;
    if (baselineOnly(pull.user, paths, laneAppId, baselineFile)) {
      return skip("native-baseline");
    }
  }
  const notDraftRun = async () => {
    if (await draftRun(github, repository, upstreamRunId, readJobs)) {
      return false;
    }
    keepJobs?.((await readJobs()).jobs);
    return true;
  };
  const drift = { pages, changedFiles: () => compareFiles(github, repository, pull.base.sha, head) };
  if (rated !== undefined) {
    if (await rated({ github, repository, number: pull.number, head, base })) {
      return skip("already-rated");
    }
    if (!(await notDraftRun())) {
      return skip("draft-run");
    }
    const { bodyEditor, bodyEditedAt, ...spec } = await linkedIssues(github, readRefs, repository, pull.number, humans, laneAppId, taskList, webHosts, undefined, base, schedule, drift);
    return { proceed: true, reason: "ok", relinkSinceHead: false, prNumber: pull.number, headSha: head, baseSha: pull.base.sha, headRef: String(pull.head.ref ?? ""), ...spec };
  }
  const prs = new Set(associated.map((item) => item?.number).filter((n) => Number.isSafeInteger(n) && n > 0));
  const draftJudged = draftJudgments(github, repository, head);
  let { fail, passes, ownFail, ownLast } = await judged({ github, repository, number: pull.number, head, base, prs, draftJudged });
  if (fail) {
    return skip("already-judged");
  }
  const bodyMayBeSpec = humans.has(pull.user?.id) || specFromBodyApps.includes(pull.user?.id);
  let specPull;
  const readSpec = async (variables) => {
    const answer = await github("POST", "/graphql", { query: specQuery(`\n      ${RELINK_FIELDS}${bodyMayBeSpec ? `\n      ${RENAME_FIELDS}` : ""}`), variables });
    specPull = answer?.data?.repository?.pullRequest ?? null;
    return answer;
  };
  const readSpecIssues = () => linkedIssues(github, readRefs, repository, pull.number, humans, laneAppId, taskList, webHosts, readSpec, base, schedule, drift);
  let acts;
  const readActs = () => (acts ??= specPull === undefined ? relinkActs(github, repository, pull.number) : Promise.resolve(actsOf(specPull?.userContentEdits, specPull?.links)));
  let reopened;
  let specRead;
  if (ownFail !== undefined) {
    specRead = await readSpecIssues().catch(() => null);
    const suffix = specRead && issuesSuffix(specRead.linkedIssues.map((issue) => issue.number));
    const relinked = Boolean(suffix) && isVerdictName(`pr-verify-${pull.number}-${head}-fail${suffix}`) && (await relinkedByPeople(github, repository, pull.number, humans, ownFail, readActs));
    if (!relinked && !(await editedByPeople(github, repository, pull.number, humans, ownLast, readActs))) {
      return skip("already-judged");
    }
    reopened = relinked ? "relinked" : "body-edited";
    ({ fail, passes } = await judged({ github, repository, number: pull.number, head, base, prs, afterOwn: true, draftJudged }));
    if (fail) {
      return skip("already-judged");
    }
  }
  specRead ??= await readSpecIssues();
  const { bodyEditor, bodyEditedAt, ...spec } = specRead;
  const byAuthorOrPerson = (id) => Number.isSafeInteger(id) && (id === pull.user?.id || humans.has(id));
  const bodyIsIntent = bodyMayBeSpec && (bodyEditor === null || byAuthorOrPerson(bodyEditor));
  const titleIsIntent = async () => {
    const renames = specPull?.renames;
    if (!Array.isArray(renames?.nodes)) {
      throw incomplete("timelineItems could not be read");
    }
    const renamers = renames.pageInfo?.hasNextPage === true ? await titleRenamers(github, repository, pull.number) : renames.nodes.map((event) => event?.actor ?? null);
    return renamers.length === 0 || byAuthorOrPerson(renamers.at(-1)?.databaseId);
  };
  if (spec.linkedIssues.length === 0 && bodyIsIntent && (await titleIsIntent())) {
    const body = `${String(pull.title ?? "")}\n\n${String(pull.body ?? "")}`;
    spec.specKind = "pull-request";
    spec.specText = [{ number: pull.number, source: "pull-request", spec_kind: "pull-request", body, comments: [] }];
  }
  if (passes.length > 0 && !specChanged(passes, { ...spec, bodyEditedAt, listChangedAt: await trustedListChangedAt?.() })) {
    return skip("already-judged");
  }
  const issues = spec.linkedIssues.map((issue) => issue.number);
  const named = await judged({ github, repository, number: pull.number, head, base, prs, issues, draftJudged });
  if (named.fail) {
    return skip("already-judged");
  }
  if (named.ownFail !== undefined) {
    const times = [ownLast, named.ownLast].filter((time) => time !== undefined).map((time) => Date.parse(time));
    const last = times.some(Number.isNaN) ? "" : new Date(Math.max(...times)).toISOString();
    if (!(await editedByPeople(github, repository, pull.number, humans, last, readActs))) {
      return skip("already-judged");
    }
    reopened = "body-edited";
  }
  if (!(await notDraftRun())) {
    return skip("draft-run");
  }
  keepReads?.(prReads(pull.number, pull, specPull));
  return {
    proceed: true,
    reason: reopened ?? (passes.length > 0 ? "spec-changed" : "ok"),
    relinkSinceHead: reopened !== undefined || (await relinkedSince(github, repository, pull.number, run.head_commit?.timestamp, readActs)),
    prNumber: pull.number,
    headSha: head,
    baseSha: pull.base.sha,
    headRef: String(pull.head.ref ?? ""),
    ...spec,
  };
}

export function specFromBodyApps(text) {
  const ids = String(text ?? "").split(/\s+/).filter(Boolean);
  return ids.every((id) => /^[1-9][0-9]*$/.test(id)) ? ids.map(Number) : [];
}

export const CARRY_MAX = 96_000;
const HEAD_REF = /^[A-Za-z0-9._/-]+$/;
const ATTEMPT = /^[1-9][0-9]{0,4}$/;

export function packReads({ attempt, prNumber, headSha, baseSha, headRef, relinkSinceHead, linkedIssues, specText, context }) {
  const packed = Buffer.from(
    JSON.stringify({ v: 1, attempt, pr: prNumber, head_sha: headSha, base_sha: baseSha, head_ref: headRef, relink_since_head: relinkSinceHead, linked_issues: linkedIssues, spec_text: specText, context }),
  ).toString("base64");
  return packed.length <= CARRY_MAX ? packed : "";
}

export function takeReads(carried, attempt) {
  if (String(carried ?? "").length > CARRY_MAX) {
    return null;
  }
  let reads;
  try {
    reads = JSON.parse(Buffer.from(String(carried ?? ""), "base64").toString("utf8"));
  } catch {
    return null;
  }
  const valid =
    reads?.v === 1 &&
    ATTEMPT.test(String(attempt ?? "")) &&
    reads.attempt === String(attempt) &&
    Number.isSafeInteger(reads.pr) &&
    reads.pr > 0 &&
    SHA.test(reads.head_sha ?? "") &&
    SHA.test(reads.base_sha ?? "") &&
    HEAD_REF.test(reads.head_ref ?? "") &&
    (reads.relink_since_head === "true" || reads.relink_since_head === "false") &&
    Array.isArray(reads.linked_issues) &&
    Array.isArray(reads.spec_text) &&
    reads.context !== null &&
    typeof reads.context === "object" &&
    !Array.isArray(reads.context);
  return valid
    ? { prNumber: reads.pr, headSha: reads.head_sha, baseSha: reads.base_sha, headRef: reads.head_ref, relinkSinceHead: reads.relink_since_head, linkedIssues: reads.linked_issues, specText: reads.spec_text, context: reads.context }
    : null;
}

export function carryMain(env = process.env) {
  let packed = "";
  try {
    packed = packReads({
      attempt: String(env.GITHUB_RUN_ATTEMPT ?? ""),
      prNumber: Number(env.PR_NUMBER),
      headSha: env.HEAD_SHA,
      baseSha: env.BASE_SHA,
      headRef: env.HEAD_REF,
      relinkSinceHead: env.RELINK_SINCE_HEAD,
      linkedIssues: JSON.parse(readFileSync(env.SPEC_FILE, "utf8")),
      specText: JSON.parse(readFileSync(env.SPEC_TEXT_FILE, "utf8")),
      context: JSON.parse(readFileSync(env.CONTEXT_FILE, "utf8")),
    });
  } catch {
    packed = "";
  }
  if (packed !== "" && takeReads(packed, env.GITHUB_RUN_ATTEMPT) === null) {
    packed = "";
  }
  appendFileSync(env.GITHUB_OUTPUT, `reads=${packed}\n`);
  console.log(packed === "" ? "resolve-pr: no reads handed on; a handoff reads again" : `resolve-pr: handed on ${packed.length} characters of reads`);
}

export function ratedBy(env) {
  if (!env.RATED_WORKFLOW_PATH && !env.RATED_ARTIFACT_PREFIX) {
    return undefined;
  }
  const path = String(env.RATED_WORKFLOW_PATH ?? "");
  const prefix = String(env.RATED_ARTIFACT_PREFIX ?? "");
  if (!/^\.github\/workflows\/[a-z0-9-]+\.yml$/.test(path) || !/^[a-z][a-z0-9-]{0,40}$/.test(prefix)) {
    throw new Error("RATED_WORKFLOW_PATH or RATED_ARTIFACT_PREFIX is malformed");
  }
  return async ({ github, repository, number, head, base }) => {
    const name = `${prefix}-${number}-${head}`;
    for (const artifact of await artifactsNamed(github, repository, name, { emptyIsSafe: true })) {
      const runId = artifact?.workflow_run?.id;
      if (artifact?.name !== name || artifact.expired !== false || !Number.isSafeInteger(runId)) {
        continue;
      }
      const run = await github("GET", `/repos/${repository}/actions/runs/${runId}`);
      if (run?.id === runId && ofOrigin(run, { path, repository, base })) {
        return true;
      }
    }
    return false;
  };
}

const laneOf = (env) => (/^[a-z][a-z0-9-]{0,40}$/.test(env?.RESOLVE_LANE ?? "") ? env.RESOLVE_LANE : "pr-verify");

const writeJson = (file, value) => writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);

export async function main(env = process.env, { github, fetchImpl, latch } = {}) {
  if (env.CARRIED) {
    const taken = takeReads(env.CARRIED, env.GITHUB_RUN_ATTEMPT);
    if (taken !== null && env.CONTEXT_FILE && env.SPEC_FILE && env.SPEC_TEXT_FILE && env.GITHUB_OUTPUT) {
      writeJson(env.SPEC_FILE, taken.linkedIssues);
      writeJson(env.SPEC_TEXT_FILE, taken.specText);
      writeJson(env.CONTEXT_FILE, taken.context);
      const lines = [
        "proceed=true",
        "reason=carried",
        `pr-number=${taken.prNumber}`,
        `head-sha=${taken.headSha}`,
        `base-sha=${taken.baseSha}`,
        `head-ref=${taken.headRef}`,
        `relink-since-head=${taken.relinkSinceHead}`,
        "carried=true",
      ];
      appendFileSync(env.GITHUB_OUTPUT, `${lines.join("\n")}\n`);
      console.log(`resolve-pr: proceed=true reason=carried pr=${taken.prNumber} head=${taken.headSha}`);
      return;
    }
    console.log("resolve-pr: the key job's reads do not hold for this attempt; reading again");
  }
  for (const key of [
    "GITHUB_TOKEN",
    "GITHUB_REPOSITORY",
    "GITHUB_EVENT_PATH",
    "GITHUB_OUTPUT",
    "SPEC_FILE",
    "SPEC_TEXT_FILE",
    "TRUSTED_ACTORS_PATH",
  ]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const upstreamRun = readUpstreamRun(readFileSync(env.GITHUB_EVENT_PATH, "utf8"));
  const trusted = loadTrustedList(env.TRUSTED_ACTORS_PATH);
  const api = (keepGraphQLErrors) => createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, fetchImpl, keepGraphQLErrors, latch });
  const send = fetchImpl ?? fetch;
  const counted = countRequests(send);
  const readLog = async (jobId) => {
    let response = await counted(`${env.GITHUB_API_URL ?? "https://api.github.com"}/repos/${env.GITHUB_REPOSITORY}/actions/jobs/${jobId}/logs`, {
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GITHUB_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28" },
      redirect: "manual",
    });
    const location = response.headers.get("location");
    if (response.status >= 300 && response.status < 400 && location) {
      response = await send(location);
    }
    if (!response.ok) {
      throw Object.assign(new Error(`the log of job ${jobId} answered ${response.status}`), { detail: await responseDetail(response) });
    }
    return response.text();
  };
  let jobs;
  let reads;
  const client = github ?? api(false);
  const result = await resolvePull({
    github: client,
    readRefs: github ?? api(true),
    readLog,
    repository: env.GITHUB_REPOSITORY,
    upstreamRun,
    humans: trusted.humans,
    verifyAuthors: env.VERIFY_AUTHORS ?? "lane",
    laneIdentity: env.LANE_IDENTITY,
    laneAppId: trusted.logins.get(`${loginKey(env.LANE_IDENTITY)}[bot]`),
    baselineFile: env.BASELINE_FILE,
    taskList: loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)))["task-list"],
    webHosts: webHostsFrom(env.ISSUE_LANE_WEB_HOSTS),
    ownerIds: [...trusted.ids],
    specFromBodyApps: specFromBodyApps(env.SPEC_FROM_BODY_APPS),
    keepJobs: (list) => {
      jobs = list;
    },
    keepReads: (kept) => {
      reads = kept;
    },
    rated: ratedBy(env),
    trustedListChangedAt: env.STANDARDS_SHA ? () => listChangedAt(client, env.STANDARDS_SHA) : undefined,
  });
  if (result.proceed && !/^[A-Za-z0-9._/-]+$/.test(result.headRef)) {
    throw new Error("the head branch has a name the outputs cannot carry");
  }
  if (result.proceed) {
    writeJson(env.SPEC_FILE, result.linkedIssues);
    writeJson(env.SPEC_TEXT_FILE, result.specText);
    const keptFile = jobs !== undefined && keptJobsPath(env);
    if (keptFile) {
      writeFileSync(keptFile, `${JSON.stringify(shapeJobs(upstreamRun.id, jobs))}\n`);
    }
    if (reads && env.RUNNER_TEMP) {
      writeFileSync(path.join(env.RUNNER_TEMP, PR_READS), `${JSON.stringify(reads)}\n`);
    }
  }
  const lines = [
    `proceed=${result.proceed}`,
    `reason=${result.reason}`,
    `pr-number=${result.prNumber ?? ""}`,
    `head-sha=${result.headSha ?? ""}`,
    `base-sha=${result.baseSha ?? ""}`,
    `head-ref=${result.headRef ?? ""}`,
    `relink-since-head=${result.relinkSinceHead ?? ""}`,
  ];
  appendFileSync(env.GITHUB_OUTPUT, `${lines.join("\n")}\n`);
  const summary = {
    "author-not-lane": "skipped: author not the lanes App",
    "author-not-lane-or-owner": "skipped: author neither the lanes App nor a trusted actor",
    "verify-authors-invalid": "skipped: verify-authors value is invalid",
  }[result.reason];
  if (summary && env.GITHUB_STEP_SUMMARY) {
    appendFileSync(env.GITHUB_STEP_SUMMARY, `${summary}\n`);
  }
  console.log(`resolve-pr: proceed=${result.proceed} reason=${result.reason}${result.proceed ? ` pr=${result.prNumber} head=${result.headSha}` : ""}`);
}

export const failureAnnotation = (error, env = process.env) => `::error::${laneOf(env)} could not resolve the pull request: ${error.message}${detailSuffix(error)}`;

export const HELD_REASON = "held";
export const HELD_STEP = "Note the hold";

export function closing(error, env = process.env) {
  if (!isFault(error) && error?.incomplete !== true) {
    return { lines: [failureAnnotation(error, env)], outputs: null, code: 1 };
  }
  const why = `${error?.message ?? error}${detailSuffix(error)}`.replaceAll(/[\r\n%]/g, " ");
  const lane = laneOf(env);
  return { lines: [`::notice title=${lane}::held: ${lane} could not resolve the pull request: ${why}`], outputs: `proceed=false\nreason=${HELD_REASON}\n`, code: 0 };
}

const isEntry = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isEntry && process.argv[2] === "carry") {
  carryMain();
} else if (isEntry) {
  main().catch((error) => {
    const closed = closing(error);
    closed.lines.forEach((line) => console.log(line));
    if (closed.outputs && process.env.GITHUB_OUTPUT) {
      appendFileSync(process.env.GITHUB_OUTPUT, closed.outputs);
    }
    process.exitCode = closed.code;
  });
}
