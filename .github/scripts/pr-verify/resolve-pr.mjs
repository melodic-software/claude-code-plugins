// Resolves the pull request a pr-require-checks run passed, for pr-verify.yml.
// The only event field it takes is the upstream run id; every other fact is
// read back from the API. It proceeds only when all of these hold, and
// otherwise writes proceed=false with a reason:
// - the run is a completed pull_request run of pr-require-checks.yml, by
//   exact path, in this repository on a head of this repository, that
//   succeeded or failed only on holds an approving review of the head lifts
//   or the `do-not-merge` label (heldOnly), so a person approves, and a
//   session holding the pull request reads, a head pr-verify has judged;
// - exactly one open PR into main has that run's head SHA as its current head
//   and its head in this repository;
// - the PR is not a draft and not a dependency manager's (a Bot account with
//   one of DEPENDENCY_MANAGERS' logins), and the run did not start while it
//   was a draft (draftRun), whose suites all skipped;
// - under merge.verify-authors `lane` (the default) the lanes App opened it:
//   a Bot account whose login is merge.agent-identity, compared as the
//   pr-merge lane does (babysit_merge_policy._lane_authored); under
//   `lane-or-owner` that App or a User or Bot whose id is on the trusted
//   list (never matched by login), whose PRs the pr-merge lane adopts
//   (babysit_merge_policy.adoption_refusal); under `any` anyone may
//   have; any other value judges nothing;
// - the head has no counted verdict yet: a FAIL at it under this PR's number
//   or another the commit's pull requests carry, or a PASS or PASS-NOTES for
//   this PR, each looked up by exact artifact name, uploaded by a completed
//   run that the pr-merge lane's reader would count (countedBy, the same checks as
//   babysit_verify_evidence.py). A run still going or one that uploaded
//   nothing does not stop a new judgment, nor does a FAIL judged from a run
//   that started on the draft (draftJudgments), and neither do passes that all
//   started before the spec last changed (`specChanged`): the head is judged
//   again, with reason `spec-changed`.
// The babysit-prs test test_verify_rules_sync.py runs this file to keep
// DEPENDENCY_MANAGERS, isDependencyManager and countedBy in step with the gate.
// It also writes the PR's closing issues, or, when it closes none, the one
// issue its body's `Refs:` lines name (refsIssue), with their authors and last
// body editors to SPEC_FILE, and the spec text trusted humans wrote, with
// intake's refinement on their issues, to SPEC_TEXT_FILE (linkedIssues).
// The head SHA is the run's, never the PR's live head.
// This PR's own plain-named FAIL at the head (written when it linked no issue,
// or more than a name carries) stops a new judgment unless the PR now links
// issues a FAIL name can carry and, since that FAIL's run was created, only
// trusted people edited its body or connected or disconnected an issue, at
// least once (relinkedByPeople): reason `relinked`. This PR's own FAIL at the
// head, plain or named with its issues, also stops a new judgment unless,
// since its last such FAIL's run was created, a trusted person edited the
// body and only trusted people edited it or changed its links
// (editedByPeople): reason `body-edited`. A body edit re-runs
// pr-require-checks (`edited`), whose completion starts this run. The gate
// weighs the pass either judgment writes by the same rules
// (babysit_verify_evidence `_superseded`).
// A judgment also reports relink-since-head: whether the PR's body or links
// changed since the head commit (relinkedSince), which sets how long its pass
// lasts (write-verdict.mjs retentionDays).

import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  commitPulls,
  createGitHub,
  detailSuffix,
  graphQLReader,
  isFault,
  loadTrustedList,
  responseDetail,
} from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { titleRenamers } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { issuesSuffix, isVerdictName, NAME } from "./write-verdict.mjs";
import { refsIssue, visibleLines } from "../pr-merge/merge-holds.mjs";
import { carriesSplit, loadRules, personChecks, readSchedule, refinementSpec, SPLIT_CHILD_MARKER, splitChildBody, splitScope, taskItems, webHostsFrom } from "../intake-triage/admit.mjs";
import { issueBody, issueTitle, SCHEDULE_MARKER } from "../recurring-schedule/file-due.mjs";

export { refsIssue };

// The name grammar lives with its writer; the resolver checks names against it.
export { isVerdictName, NAME, NAME_MAX } from "./write-verdict.mjs";

export const UPSTREAM_PATH = ".github/workflows/pr-require-checks.yml";
export const VERIFY_PATH = ".github/workflows/pr-verify.yml";
// babysit_classify.DEPENDENCY_MANAGER_LOGINS: the pr-merge lane refuses these
// Bot accounts' pull requests before reading a verdict.
export const DEPENDENCY_MANAGERS = Object.freeze(["dependabot", "dependabot-preview", "renovate", "renovate-bot"]);
const VERIFY_AUTHORS = Object.freeze(["lane", "lane-or-owner", "any"]);

// The jobs as JOBS_FILE lists them, each with the job page the verifier cites.
export const shapeJobs = (runId, jobs) => ({
  run_id: Number(runId),
  jobs: jobs.map((job) => ({ name: String(job?.name ?? ""), conclusion: job?.conclusion ?? null, url: typeof job?.html_url === "string" ? job.html_url : null })),
});

// The file this script writes the jobs it read whole into, in RUNNER_TEMP
// (outside the workspace the model reads); null when RUNNER_TEMP is unset.
export const KEPT_JOBS = "pr-verify-upstream-jobs.json";
export const keptJobsPath = (env) => (env.RUNNER_TEMP ? path.join(env.RUNNER_TEMP, KEPT_JOBS) : null);

const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const MAX_PAGES = 100;

// A 200 whose completeness check failed: a list shorter than its count, or a
// field the answer lacks. The verdict is unknown, so closing holds on it.
const incomplete = (message) => Object.assign(new Error(message), { incomplete: true });
// A list read short of its count. Past `cap`, the most the query reads, every
// re-read meets the same limit, so it stays red; at or under it, a re-read can
// return it whole, so it holds (incomplete).
const shortList = (message, count, cap) => (Number.isSafeInteger(count) && count > cap ? new Error(message) : incomplete(message));

const COMMENT_FIELDS = "totalCount pageInfo { hasNextPage endCursor } nodes { databaseId createdAt updatedAt body lastEditedAt author { ...actor } editor { ...actor } }";
const ISSUE_FIELDS = `number repository { nameWithOwner } body lastEditedAt
          author { ...actor } editor { ...actor }
          comments(first: 100) { ${COMMENT_FIELDS} }`;
const ACTOR = "fragment actor on Actor { __typename login ... on User { databaseId } ... on Bot { databaseId } }";
// The pages after the first of an issue's comments.
const COMMENT_PAGE_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) { number comments(first: 100, after: $after) { ${COMMENT_FIELDS} } }
  }
}
${ACTOR}`;
// The most comment pages one issue's read takes. Every trusted comment is
// spec and the merge gate compares that set whole, so no page may be skipped;
// past the cap the read stays red and says so.
export const COMMENT_PAGES = 10;
// resolvePull's spec read also takes RELINK_QUERY's fields (`links` its
// timelineItems) and, when the body may be the spec, the first page of the
// title renames select-trusted-text's TITLE_RENAMES reads (`renames`), so one
// read serves linkedIssues, the relink rules and titleIsIntent.
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

// A pull request a closing pull request's `Siblings:` line names, with what
// creditedSiblings checks before crediting it.
const SIBLING_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issueOrPullRequest(number: $number) {
      __typename
      ... on PullRequest { number merged mergedAt baseRefName body lastEditedAt author { ...actor } editor { ...actor } repository { nameWithOwner } closingIssuesReferences(first: 1) { totalCount } }
    }
  }
}
${ACTOR}`;

// A size split's sub-issue's native parent, with the text admit.mjs specOf
// reads, for splitChildBody.
const PARENT_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      parent { number repository { nameWithOwner } body lastEditedAt author { ...actor } editor { ...actor }
        comments(first: 100) { ${COMMENT_FIELDS} } }
    }
  }
}
${ACTOR}`;

// The pull request's body edits and issue connect and disconnect events, the
// ways its linked issues change at one head, read whole in one query;
// babysit_verify_evidence.RELINK_QUERY is the same text.
export const RELINK_QUERY =
  "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){" +
  "pullRequest(number:$n){userContentEdits(first:100){totalCount " +
  "nodes{editedAt editor{...actor}}} " +
  "timelineItems(first:100,itemTypes:[CONNECTED_EVENT,DISCONNECTED_EVENT]){" +
  "filteredCount nodes{... on ConnectedEvent{createdAt actor{...actor}} " +
  "... on DisconnectedEvent{createdAt actor{...actor}}}}}}}" +
  "fragment actor on Actor{__typename login ... on User{databaseId} ... on Bot{databaseId}}";

// A User on the trusted list's humans: never the lanes App or another Bot.
const trustedHuman = (actor, humans) => actor?.__typename === "User" && humans.has(actor.databaseId);

// Whether at least one body edit or issue connect or disconnect on the pull
// request falls from `since` on (a body edit, under `bodyEdit`), and every
// one there was a trusted person's (babysit_verify_evidence
// `_relinked_by_people`, which ends the window at a pass run's completion).
// None there means the link changed some way this read cannot see. A failed
// read, a list cut short, or an act with no readable time is false. `read`
// lets one judgment share one RELINK_QUERY read.
async function actedByPeople(github, repository, number, humans, since, bodyEdit, read) {
  const start = Date.parse(since ?? "");
  const acts = Number.isNaN(start) ? null : await (read ?? (() => relinkActs(github, repository, number)))();
  const inside = (acts ?? []).filter(([at]) => Date.parse(at) >= start);
  return inside.some(([, , kind]) => !bodyEdit || kind === "edit") && inside.every(([, actor]) => trustedHuman(actor, humans));
}

export const relinkedByPeople = (github, repository, number, humans, since, read) => actedByPeople(github, repository, number, humans, since, false, read);

// The body-edit rule: a trusted person edited the body from `since`, this pull
// request's last FAIL at the head, on, and every act there was such a person's.
export const editedByPeople = (github, repository, number, humans, since, read) => actedByPeople(github, repository, number, humans, since, true, read);

// Every body edit and issue connect or disconnect on the pull request, each
// [time, actor, "edit" or "link"], read whole (RELINK_QUERY); null for a
// failed read, a list cut short, or an act with no readable time.
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

// relinkActs' acts from the two connections RELINK_QUERY reads.
function actsOf(edits, events) {
  // totalCount counts every timeline item; filteredCount the kinds asked.
  if (!Array.isArray(edits?.nodes) || edits.totalCount !== edits.nodes.length || !Array.isArray(events?.nodes) || events.filteredCount !== events.nodes.length) {
    return null;
  }
  const acts = [...edits.nodes.map((node) => [node?.editedAt, node?.editor, "edit"]), ...events.nodes.map((node) => [node?.createdAt, node?.actor, "link"])];
  return acts.some(([at]) => Number.isNaN(Date.parse(at ?? ""))) ? null : acts;
}

// Whether anyone edited the pull request's body or connected or disconnected
// an issue from `since`, the head commit's time, on. Only then can a pass
// judged at the head supersede a FAIL there (babysit_verify_evidence
// `_superseded` needs such an act after the FAIL, which comes after the
// commit), so write-verdict.mjs keeps such a pass as long as a FAIL. A time
// or read that fails answers true.
export async function relinkedSince(github, repository, number, since, read) {
  const start = Date.parse(since ?? "");
  const acts = Number.isNaN(start) ? null : await (read ?? (() => relinkActs(github, repository, number)))();
  return acts === null || acts.some(([at]) => Date.parse(at) >= start);
}

// babysit_merge_policy.names_nothing: whether a GraphQL answer says only that
// `repository.<field>` names nothing, null there with every error a NOT_FOUND
// at that path, as GitHub answers a `Refs: #<n>` whose number is no issue or
// pull request.
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

// A Bot account with a dependency manager's login; a User named like one is not.
export const isDependencyManager = (user) =>
  user?.type === "Bot" &&
  DEPENDENCY_MANAGERS.includes(String(user.login ?? "").toLowerCase().replace(/^app\//, "").replace(/\[bot\]$/, ""));

// babysit_merge_policy._login_key: REST spells an App `app[bot]`, GraphQL `app`.
const loginKey = (login) => String(login ?? "").trim().toLowerCase().replace(/\[bot\]$/, "");
const laneAuthored = (user, laneIdentity) =>
  loginKey(laneIdentity) !== "" && user?.type === "Bot" && loginKey(user.login) === loginKey(laneIdentity);
const ownerAuthored = (user, ids) => (user?.type === "User" || user?.type === "Bot") && ids.includes(user.id);

// pr-require-checks.yml's ci-status step that runs merge-holds.mjs on a lanes
// App pull request, and the step after it that aggregates the lanes. A run
// reports its own commit's step names, on a re-run too, so a held head whose
// newest run predates the current name still reports OLD_HOLD_STEP.
export const HOLD_STEP = "Fail a lanes App pull request on kill switch, hold path, verifier or veto";
const OLD_HOLD_STEP = "Fail a lanes App pull request its body or a member holds";
const HOLD_STEPS = [HOLD_STEP, OLD_HOLD_STEP];
export const AGGREGATE_STEP = "Aggregate lane results";
// The ci-status step that runs ci-workflows' check-contract (title,
// `do-not-merge` label, issue linkage), and the one error line its run.sh
// writes for the label, whose name pr-require-checks.yml leaves the default.
export const CONTRACT_STEP = "Check the pull-request contract";
export const DO_NOT_MERGE_LINE = "pr-contract: this PR carries the 'do-not-merge' label; remove it to merge.";
// What merge-holds.mjs `holds` writes after each hold an approving review of
// the head lifts, and the line the runner adds for the step's failing exit.
export const PERSON_LIFT = "; an approving review of this head by a person on the trusted-actor list lifts it";
const STEP_EXIT = "Process completed with exit code 1.";
const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
// One such hold's whole log line, `#<n>: <reason>.`: a hold path or a
// trusted-actor list widening, then PERSON_LIFT and its carry-over clause,
// in today's wording and the earlier one, to the end of the line. A changed
// path is author text, so only the full shape counts, never a substring.
export const personHoldLine = (line, number) =>
  !line.includes("a cost path") &&
  new RegExp(
    `^#${number}: (?:it changes .+, a hold path|it widens the trusted-actor list \\(.+\\))${escapeRegExp(PERSON_LIFT)}, and the approval carries over later merges (?:that bring only the base's changes|of the base that leave its net change the same); then re-run ci-status\\.$`,
  ).test(line);

// The `##[error]` lines of a job log, without the runner's timestamp.
export const errorLines = (log) =>
  String(log)
    .split(/\r?\n/)
    .flatMap((line) => /^﻿?(?:\S+ )?##\[error\](.*)$/.exec(line)?.slice(1) ?? []);

// Whether failed run `runId` failed only because a person has not yet approved
// pull request `number`'s head or holds it with `do-not-merge`: of its latest
// jobs only ci-status failed, its failed steps are HOLD_STEP, CONTRACT_STEP or
// both, the lanes aggregate succeeded, and every error that job logged is one
// of `number`'s holds an approval lifts (at least one when HOLD_STEP failed),
// DO_NOT_MERGE_LINE (exactly once when CONTRACT_STEP failed, never otherwise)
// or a failed step's exit. ci-status still fails, so such a head never merges
// unapproved or labeled; the verdict a judgment writes lifts no hold path and
// no label. A read that fails, a job or step list cut short, or any other
// error is false.
// The check is two halves: heldShape reads only the run's jobs, so it runs
// before the commit's pull requests are read, and heldOnly reads the
// ci-status log against the pull request's number.
// `read` is the resolution's one jobs read (latestJobs). Returns the ci-status
// job's id and its failed step names, or null.
async function heldShape(read) {
  try {
    const listed = await read();
    const jobs = listed?.jobs;
    if (!Array.isArray(jobs) || listed.total_count !== jobs.length) {
      return null;
    }
    const ci = jobs.filter((job) => job?.name === "ci-status");
    if (ci.length !== 1 || ci[0].conclusion !== "failure" || !Number.isSafeInteger(ci[0].id)) {
      return null;
    }
    if (jobs.some((job) => job !== ci[0] && !["success", "skipped", "neutral"].includes(job?.conclusion))) {
      return null;
    }
    const steps = Array.isArray(ci[0].steps) ? ci[0].steps : [];
    const failed = steps.filter((step) => step?.conclusion !== "success" && step?.conclusion !== "skipped");
    const names = failed.map((step) => step?.name);
    if (
      failed.length === 0 ||
      failed.some((step) => step.conclusion !== "failure" || ![...HOLD_STEPS, CONTRACT_STEP].includes(step.name)) ||
      new Set(names).size !== names.length ||
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
    return (
      errors.length - reasons.length === names.length &&
      person.length + label.length === reasons.length &&
      (person.length > 0) === names.some((name) => HOLD_STEPS.includes(name)) &&
      label.length === (names.includes(CONTRACT_STEP) ? 1 : 0)
    );
  } catch {
    return false;
  }
}

// The latest attempt's jobs of run `runId`, one page.
const latestJobs = (github, repository, runId) => github("GET", `/repos/${repository}/actions/runs/${runId}/jobs?filter=latest&per_page=100`);

// pr-require-checks.yml's ci-status step that runs only when the run's event
// is a draft's (`if: github.event.pull_request.draft == true`); every suite
// skips on such a run.
export const DRAFT_STEP = "Note a draft";

// Whether checks run `runId` started while its pull request was a draft: its
// latest ci-status job lists DRAFT_STEP as `success`; `skipped` is a ready
// pull request's run. The step reads the run's own event, which a re-run
// keeps, so marking the pull request ready since changes nothing. The jobs API
// can list a finished job's steps empty or cut short (pr-require-checks.yml's
// ci-status notes), so anything else (a read that fails, a job list cut short,
// no one ci-status job, the step not listed once, or no such conclusion)
// throws: no state is read from a missing step.
// `read` as heldShape's.
export async function draftRun(github, repository, runId, read) {
  const listed = await (read ?? (() => latestJobs(github, repository, runId)))();
  const jobs = listed?.jobs;
  if (!Array.isArray(jobs) || listed.total_count !== jobs.length) {
    throw shortList(`the jobs of run ${runId} could not be read whole`, listed?.total_count, 100);
  }
  const ci = jobs.filter((job) => job?.name === "ci-status");
  const steps = ci.length === 1 && Array.isArray(ci[0].steps) ? ci[0].steps.filter((step) => step?.name === DRAFT_STEP) : [];
  const conclusion = steps.length === 1 ? steps[0].conclusion : undefined;
  if (conclusion === "success" || conclusion === "skipped") {
    return conclusion === "success";
  }
  const message = `run ${runId}'s draft state could not be read: ci-status lists no conclusion for ${DRAFT_STEP}`;
  // Only steps listed empty or cut short (one ci-status job, the step absent)
  // can come back whole on a re-read, so only that holds. No single ci-status
  // job, or the step listed with another conclusion, reads the same every
  // time, so it stays red rather than holding the head unverified unseen.
  throw ci.length === 1 && steps.length === 0 ? incomplete(message) : new Error(message);
}

// For a counted FAIL's pr-verify run, whether it judged a checks run that
// started on the draft: every pr-require-checks pull_request run at the head
// created before it ran DRAFT_STEP. pr-verify starts when a checks run
// completes, so the run it judged is among them. Such a FAIL judged suites
// that never ran, which resolvePull no longer does. A read that fails, a list
// cut short, a time that cannot be read, or no run before it answers false, so
// the FAIL counts. babysit_verify_evidence `_draft_judged` is the same rule.
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

// Every artifact with exactly this name; a read that fails throws.
async function artifactsNamed(github, repository, name) {
  const artifacts = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const path = `/repos/${repository}/actions/artifacts?name=${encodeURIComponent(name)}&per_page=100&page=${page}`;
    const batch = (await github("GET", path))?.artifacts ?? [];
    artifacts.push(...batch);
    if (batch.length < 100) {
      return artifacts;
    }
  }
  throw new Error(`the ${name} artifacts have more than ${MAX_PAGES} pages`);
}

// Whether the pr-merge lane would count this artifact's run, and the run is
// complete: of verifier origin (path, event, branch, repository, head
// repository, a head SHA on the branch), completed, and for a pass concluded
// success. A read that fails counts nothing.
export async function countedBy(options) {
  return (await countedRun(options)) !== null;
}

// Whether a workflow run is of `path`'s origin: that file on `base`, started
// by workflow_run, in this repository, with a full head SHA. Only steps of
// such a run can upload its artifacts, so an artifact name alone proves
// nothing until its run passes this.
export const ofOrigin = (run, { path, repository, base = "main" }) =>
  run?.path === path &&
  run.event === "workflow_run" &&
  run.head_branch === base &&
  run.repository?.full_name === repository &&
  run.head_repository?.full_name === repository &&
  SHA.test(run.head_sha ?? "");

// countedBy's run record, or null when it would not count.
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

// Every pull request the commit belongs to, read through GraphQL when the
// REST pages fail (commitPulls); a read that fails both ways throws.
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

// The names that hold a counted verdict at the head: this PR's PASS,
// PASS-NOTES and FAIL, and a FAIL under each other number the commit's pull
// requests carry, each in the form write-verdict.mjs artifactName writes.
// It writes no head-ref digest, so no digest name is looked up; the change
// that moves the writer to digest names adds their lookups beside these
// until the last plain-named artifact expires. Given `issues`, this PR's linked issue
// numbers, it looks up only this PR's FAIL names with `-i` and those issues
// (write-verdict.mjs artifactName), so the caller reads the issues only for a
// head the names without them leave unjudged; issues no name carries (over
// the cap, or a number the pattern refuses) are never looked up, since the
// writer names that FAIL plainly. A FAIL another PR left at the
// head names issues this run never reads, so its suffixed name is missed and
// the head is judged again; so is a head whose linked issues changed since
// this PR's FAIL there. Each costs a run, and the earlier FAIL stays tied and
// refuses the head unless the gate finds it superseded (`_superseded`: only
// trusted people changed the link before the new pass started).
// A counted FAIL answers `fail`; this PR's counted passes answer only their
// runs' start times (`passes`), which `specChanged` weighs against the spec.
// The FAIL names come first: a counted FAIL alone decides, so the passes are
// looked up only when none is found. This PR's own FAIL (plain, or named
// with its issues) answers instead `ownFail` and `ownLast`, the earliest and
// latest creation times of its counted runs, so the caller can weigh a
// relink (`relinkedByPeople`) or a body edit (`editedByPeople`) and then look
// up the rest with `afterOwn`.
// A FAIL whose run judged a checks run that started on the draft counts as
// none (`draftJudged`, draftJudgments).
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
    for (const artifact of await artifactsNamed(github, repository, name)) {
      if (artifact?.name !== name || artifact.expired !== false) {
        continue;
      }
      const runId = artifact.workflow_run?.id;
      const run = Number.isSafeInteger(runId) ? await countedRun({ github, repository, runId, verdict, base }) : null;
      if (run !== null && verdict === "fail" && (await draftJudged(run))) {
        continue;
      }
      if (run !== null && verdict === "fail" && (name === own || name === own + suffix)) {
        created.push(Date.parse(run.created_at ?? ""));
      } else if (run !== null && verdict === "fail") {
        return { fail: true, passes };
      } else if (run !== null) {
        passes.push(run.run_started_at);
      }
    }
    if (created.length > 0) {
      // NaN for any missing time, which relinkedByPeople refuses.
      const at = (time) => (Number.isNaN(time) ? "" : new Date(time).toISOString());
      return { fail: false, passes, ownFail: at(Math.min(...created)), ownLast: at(Math.max(...created)) };
    }
  }
  return { fail: false, passes };
}

// Whether every counted pass at the head started before the live spec last
// changed (babysit_verify_evidence `_pass_refusal`, which refuses such a pass
// `verify:spec-changed`): a linked issue's body edit, a spec comment added or
// edited, or, for a pull request that is its own spec, a body edit. A pass
// with no readable start time is stale. The gate also refuses a changed
// closing set and a removed spec comment, which leave no time here; those
// heads stay judged, as before.
export function specChanged(passStarts, { linkedIssues: issues, specKind, bodyEditedAt }) {
  const times = [
    ...issues.flatMap((issue) => [issue.last_edited_at, ...issue.spec_comments.map((comment) => comment.updated_at)]),
    ...(specKind === "pull-request" ? [bodyEditedAt] : []),
  ].map((time) => Date.parse(time ?? ""));
  const changed = Math.max(-Infinity, ...times.filter((time) => !Number.isNaN(time)));
  return !passStarts.some((start) => Date.parse(start ?? "") > changed);
}

// The pull requests the visible `Siblings: #<a>, #<b>` lines of a pull request
// body name, read from its visible lines (merge-holds.mjs visibleLines, which
// refsIssue reads) from the first column. A `Siblings:` line in any other form,
// or more than SIBLINGS_MAX numbers, names none.
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

// The siblings a closing pull request's body names (siblingNumbers) that
// delivered part of one of its issues: each written by a trusted person or the
// lanes App (`laneAppId`), merged into `base` in this repository, closing no
// issue, with a `Refs:` line (refsIssue) naming that issue, and its body
// unedited unless a trusted person edited it last, or the lanes App did
// before the merge, with that body, which says the part. Read from GitHub,
// never from the body's prose. A number that names nothing credits nothing;
// any other failed read throws.
async function creditedSiblings(readRefs, repository, number, body, base, humans, laneAppId) {
  const [owner, name] = repository.split("/");
  const lanesApp = (actor) => laneAppId !== undefined && actor?.__typename === "Bot" && actor.databaseId === laneAppId;
  const credited = [];
  for (const sibling of siblingNumbers(body).filter((n) => n !== number)) {
    const answer = await readRefs("POST", "/graphql", { query: SIBLING_QUERY, variables: { owner, name, number: sibling } });
    const node = answer?.data?.repository?.issueOrPullRequest;
    // A GraphQL error other than NOT_FOUND stays red, as the client's own
    // GraphQL errors do; an answer with no node holds (incomplete).
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

// github-actions[bot], which maintenance-file-recurring-issues.yml files as.
const ACTIONS_BOT_ID = 41898282;

// The spec of an issue the recurring filer opened, or null: the title and body
// file-due.mjs builds from the one schedule row its one marker line names, in
// the schedule this script's checkout holds (main's, in pr-verify.yml). The
// issue's own text is never read as spec, so an edit by anyone cannot change
// this text; it can only point the marker at another reviewed row of that
// schedule (hardening candidate: also require an unedited issue).
export function recurringSpec(issue, schedule) {
  const marks = [...String(issue?.body ?? "").matchAll(SCHEDULE_MARKER)];
  if (issue?.author?.__typename !== "Bot" || issue.author.databaseId !== ACTIONS_BOT_ID || marks.length !== 1) {
    return null;
  }
  const rows = Array.isArray(schedule?.items) ? schedule.items.filter((row) => row?.id === marks[0][1]) : [];
  return rows.length === 1 && typeof rows[0].title === "string" && rows[0].title !== "" ? `# ${issueTitle(rows[0])}\n\n${issueBody(rows[0])}` : null;
}

// The closing issues in this repository, or, when the pull request closes
// none, the one issue its `Refs:` lines name (refsIssue), with their authors
// and last body editors (`linkedIssues`), and the spec text: each body and comment written,
// and last edited if ever, by a User on the trusted list's humans, the PR
// author included, and, on an issue whose body is such text, intake's
// refinement comment by the lanes App (`laneAppId`), the newest and only
// while unedited (admit.mjs refinementSpec) and created before the pull
// request, so nothing the App posts once a lane run has the issue becomes
// spec (`specText`), with the body's done-when items that refinement lists
// as checks a person runs (`person_checks`, admit.mjs personChecks under the
// issue lane's `webHosts`); a split refinement whose record does not stand is
// left out. Other Bot and App text is left out even where
// select-trusted-text keeps it, except the body of a sub-issue the lanes App
// filed in a size split, under the split-child trust rule, `taskList` being
// admission's `task-list` (admit.mjs splitChildBody, its one home). Given the
// `base` branch, a closing issue also carries the siblings that delivered part
// of it (`credited_siblings`, creditedSiblings), so its diff is judged for the
// rest. An issue the recurring filer opened takes its body from its row of
// `schedule` (recurringSpec), marked `source` `recurring-schedule`; it
// defaults to this checkout's schedule, so every caller (the pr-unblock lanes
// too) gets the same spec.
// The merge gate cannot see the refinement: an edit, a hide (isMinimized)
// or a newer one after a pass leaves that pass standing. An edit only takes
// the refinement out of spec, so no one gains a spec by it; a person's
// correction made after a pass waits for the next head. `read` posts the
// spec query for the variables it is given (resolvePull's folded one).
// Issue `number`'s comments whole, from `first`, the first page an issue
// read returned, and up to COMMENT_PAGES - 1 more. `subject` names the issue
// in the error: "#<label>: <subject>'s comments could not be read" holds
// (incomplete), as a re-read can return them whole; over the cap stays red.
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

export async function linkedIssues(github, readRefs, repository, number, humans, laneAppId, taskList, webHosts, read, base, schedule = readSchedule()) {
  const [owner, name] = repository.split("/");
  const variables = { owner, name, number };
  const data = await (read ? read(variables) : github("POST", "/graphql", { query: SPEC_QUERY, variables }));
  const refs = data?.data?.repository?.pullRequest?.closingIssuesReferences;
  if (!refs || !Array.isArray(refs.nodes) || refs.totalCount !== refs.nodes.length) {
    throw shortList(`#${number}: the closing issues could not be read`, refs?.totalCount, 10);
  }
  const trusted = (actor) => trustedHuman(actor, humans);
  const written = (item) => trusted(item?.author) && (item.lastEditedAt == null || trusted(item.editor));
  let nodes = refs.nodes;
  const named = refs.totalCount === 0 ? refsIssue(data.data.repository.pullRequest.body) : null;
  if (named !== null) {
    // `readRefs` keeps GraphQL errors, so a NOT_FOUND reaches namesNothing.
    const answer = await readRefs("POST", "/graphql", { query: REFS_QUERY, variables: { owner, name, number: named } });
    // Only an exact NOT_FOUND names nothing; a null without it is no answer.
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
  // The split sub-issues' bodies that count, by issue number.
  const childBodies = new Map();
  for (const issue of issues) {
    if (laneAppId === undefined || issue.author?.__typename !== "Bot" || issue.author.databaseId !== laneAppId || !String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER)) {
      continue;
    }
    // A parent read short of its comments stops the run, as the issue's own
    // comments do above: a judgment without the child's criteria would leave
    // a pass the gate counts once the parent reads whole again (an outsider
    // padding the parent past the page, then deleting the padding).
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
  const pullRequest = data.data.repository.pullRequest;
  const siblings = base !== undefined && named === null && issues.length > 0 ? await creditedSiblings(readRefs, repository, number, pullRequest.body, base, humans, laneAppId) : [];
  return {
    // Who last edited the pull request's own body: null when never edited.
    bodyEditor: pullRequest.lastEditedAt == null ? null : (pullRequest.editor?.databaseId ?? 0),
    bodyEditedAt: pullRequest.lastEditedAt ?? null,
    linkedIssues: issues.map((issue) => ({
      number: issue.number,
      ...actorFields(issue.author, "author"),
      last_edited_at: typeof issue.lastEditedAt === "string" ? issue.lastEditedAt : null,
      ...actorFields(issue.editor, "editor"),
      // The humans' spec comments the model gets, which the gate recomputes
      // with the same filter (babysit_verify_evidence._spec_comments); the
      // refinement stays out, since that filter is human-only.
      spec_comments: issue.comments.nodes
        .filter(written)
        .map((comment) => ({ id: comment.databaseId, updated_at: comment.updatedAt })),
    })),
    // How the spec was linked: `closes` for closing issues, `refs` for the one
    // issue a `Refs:` line names, which the verifier judges as a partial slice.
    specKind: issues.length === 0 ? "none" : named !== null ? "refs" : "closes",
    specText: issues.map((issue) => {
      const newest = written(issue) ? refinementSpec(issue.comments.nodes, laneAppId) : undefined;
      const refinement = Date.parse(newest?.createdAt ?? "") < Date.parse(pullRequest.createdAt ?? "") ? newest : undefined;
      // Under admission's guards and web hosts (admit.mjs personChecks).
      const checks = refinement === undefined ? [] : personChecks({ ...issue, comments: issue.comments.nodes }, humans, laneAppId, taskList, webHosts);
      // A split refinement whose record does not stand reaches the verifier
      // in no form, so its prose names no item a person runs; a split drafts
      // no criteria (refine.mjs validateOutput), so nothing else goes with it.
      const counted = refinement !== undefined && (checks.length > 0 || !carriesSplit(refinement.body)) ? refinement : undefined;
      const recurring = written(issue) || childBodies.has(issue.number) ? null : recurringSpec(issue, schedule);
      return {
        number: issue.number,
        spec_kind: named !== null ? "refs" : "closes",
        ...(recurring !== null && { source: "recurring-schedule" }),
        body: written(issue) && typeof issue.body === "string" ? issue.body : (childBodies.get(issue.number) ?? recurring),
        // A trusted target-subset part's Scope line (admit.mjs splitScope):
        // its done-when lines apply only to these targets.
        ...(!written(issue) && childBodies.has(issue.number) && splitScope(childBodies.get(issue.number)) !== null && { scope: splitScope(childBodies.get(issue.number)) }),
        comments: issue.comments.nodes.filter((comment) => written(comment) || comment === counted).map((comment) => String(comment.body ?? "")),
        // The body's done-when items that refinement lists as checks a
        // person runs (admit.mjs personChecks), each as written.
        ...(checks.length > 0 && { person_checks: checks.map((n) => taskItems(issue.body, taskList)[n - 1].text) }),
        ...(siblings.some((sibling) => sibling.issue === issue.number) && {
          credited_siblings: siblings.filter((sibling) => sibling.issue === issue.number).map(({ number: sibling, body }) => ({ number: sibling, body })),
        }),
      };
    }),
  };
}

export async function resolvePull({ github, readRefs = github, readLog, repository, upstreamRunId, humans, base = "main", verifyAuthors = "lane", laneIdentity, laneAppId, taskList, webHosts, ownerIds: owners = [], specFromBodyApps = [], keepJobs, rated, schedule = readSchedule() }) {
  const skip =(reason) => ({ proceed: false, reason });
  if (!RUN_ID.test(String(upstreamRunId))) {
    throw new Error("the upstream run id is not a run id");
  }
  const run = await github("GET", `/repos/${repository}/actions/runs/${upstreamRunId}`);
  if (
    String(run?.id) !== String(upstreamRunId) ||
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
  // One read of the run's jobs serves heldShape, draftRun and, through
  // keepJobs, upstream-jobs.mjs. A failed run whose jobs are not a hold's
  // shape skips before the commit's pull requests are read.
  let jobs;
  const readJobs = () => (jobs ??= latestJobs(github, repository, upstreamRunId));
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
  if (isDependencyManager(pull.user)) {
    return skip("dependency-manager");
  }
  if (!VERIFY_AUTHORS.includes(verifyAuthors)) {
    return skip("verify-authors-invalid");
  }
  if (verifyAuthors === "lane" && !laneAuthored(pull.user, laneIdentity)) {
    return skip("author-not-lane");
  }
  if (verifyAuthors === "lane-or-owner" && !laneAuthored(pull.user, laneIdentity) && !ownerAuthored(pull.user, owners)) {
    return skip("author-not-lane-or-owner");
  }
  if (run.conclusion === "failure" && !(await heldOnly(readLog, shape, pull.number))) {
    return skip("not-a-passing-run");
  }
  // An unreadable draft state throws, as any other failed read here does: the
  // step holds before its judgment (closing), so it writes no verdict, and the
  // lost-run reconciler re-runs it once (reconcile.mjs faultHeld).
  if (await draftRun(github, repository, upstreamRunId, readJobs)) {
    return skip("draft-run");
  }
  // draftRun read the list whole, or it would have thrown.
  keepJobs?.((await readJobs()).jobs);
  // Another workflow's reads of the same pull request (pr-rate-merge-risk.yml):
  // `rated` answers whether its own artifact for this head already stands, and
  // the verifier's judged-head rules do not apply. The closing issues are read
  // as for a judgment; the body is never the spec here, since that workflow
  // reads only a lanes App pull request.
  if (rated !== undefined) {
    if (await rated({ github, repository, number: pull.number, head, base })) {
      return skip("already-rated");
    }
    const { bodyEditor, bodyEditedAt, ...spec } = await linkedIssues(github, readRefs, repository, pull.number, humans, laneAppId, taskList, webHosts, undefined, base, schedule);
    return { proceed: true, reason: "ok", relinkSinceHead: false, prNumber: pull.number, headSha: head, baseSha: pull.base.sha, headRef: String(pull.head.ref ?? ""), ...spec };
  }
  const prs =new Set(associated.map((item) => item?.number).filter((n) => Number.isSafeInteger(n) && n > 0));
  const draftJudged = draftJudgments(github, repository, head);
  let { fail, passes, ownFail, ownLast } = await judged({ github, repository, number: pull.number, head, base, prs, draftJudged });
  if (fail) {
    return skip("already-judged");
  }
  // The spec read carries the relink fields and, when the body may be the
  // spec (bodyIsIntent's author half), the title renames' first page.
  // `specPull` is the pull request of the latest answer, the one specRead
  // comes from: undefined before any answer, null for an answer without one.
  const bodyMayBeSpec = humans.has(pull.user?.id) || specFromBodyApps.includes(pull.user?.id);
  let specPull;
  const readSpec = async (variables) => {
    const answer = await github("POST", "/graphql", { query: specQuery(`\n      ${RELINK_FIELDS}${bodyMayBeSpec ? `\n      ${RENAME_FIELDS}` : ""}`), variables });
    specPull = answer?.data?.repository?.pullRequest ?? null;
    return answer;
  };
  const readSpecIssues = () => linkedIssues(github, readRefs, repository, pull.number, humans, laneAppId, taskList, webHosts, readSpec, base, schedule);
  // One relink read per judgment, shared by every rule that weighs it: the
  // spec answer's, where a missing or malformed field reads as a failed
  // read, or RELINK_QUERY's when no spec read answered.
  let acts;
  const readActs = () => (acts ??= specPull === undefined ? relinkActs(github, repository, pull.number) : Promise.resolve(actsOf(specPull?.userContentEdits, specPull?.links)));
  // Why a judged head is judged again: `relinked` or `body-edited`.
  let reopened;
  let specRead;
  if (ownFail !== undefined) {
    // This PR's plain FAIL stands unless it now links issues a FAIL name
    // carries, which differ from the none or too many the FAIL recorded, and
    // only trusted people changed the link since, or a trusted person edited
    // the body since and every act was such a person's. A failed read keeps it.
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
  // No closing issue here: the title and body of a trusted person's PR, or
  // of an App whose bodies a script writes (adoption.spec-from-body-apps),
  // are the spec. A model-written body, the lanes App's included, never is:
  // the run that wrote the diff would have written its spec too.
  // A person is a kind human id on the trusted list, not a GitHub User: a
  // model's account may be a User (babysit_merge_policy.lane_eligibility's twin).
  // A body someone else edited is not the author's intent, unless a trusted
  // person did it; an editor GitHub cannot name is someone else. The title
  // follows the same rule through its latest rename (titleRenamers, shared
  // with select-trusted-text, which keeps a title only when every renamer is
  // listed). The spec answer holds the renames' first page; a longer list is
  // read whole through titleRenamers, and a page with no node list stops the
  // run as titleRenamers does.
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
  // A pass judged before the spec last changed is one the gate refuses, so
  // the head is judged again against the spec as it is now. A pass that still
  // stands decides as a FAIL would, so the FAIL named with this PR's issues
  // (read only now: the name records them) is looked up only past it.
  if (passes.length > 0 && !specChanged(passes, { ...spec, bodyEditedAt })) {
    return skip("already-judged");
  }
  const issues = spec.linkedIssues.map((issue) => issue.number);
  const named = await judged({ github, repository, number: pull.number, head, base, prs, issues, draftJudged });
  if (named.fail) {
    return skip("already-judged");
  }
  if (named.ownFail !== undefined) {
    // This PR's FAIL named with its issues stands unless a trusted person
    // edited the body after its last FAIL here, plain or named, and every
    // act since was such a person's. A time that cannot be read keeps it.
    const times = [ownLast, named.ownLast].filter((time) => time !== undefined).map((time) => Date.parse(time));
    const last = times.some(Number.isNaN) ? "" : new Date(Math.max(...times)).toISOString();
    if (!(await editedByPeople(github, repository, pull.number, humans, last, readActs))) {
      return skip("already-judged");
    }
    reopened = "body-edited";
  }
  return {
    proceed: true,
    reason: reopened ?? (passes.length > 0 ? "spec-changed" : "ok"),
    // A re-opened head's pass may supersede the FAIL there, so it is kept as long.
    relinkSinceHead: reopened !== undefined || (await relinkedSince(github, repository, pull.number, run.head_commit?.timestamp, readActs)),
    prNumber: pull.number,
    headSha: head,
    baseSha: pull.base.sha,
    headRef: String(pull.head.ref ?? ""),
    ...spec,
  };
}

// adoption.spec-from-body-apps as yq prints it, one id per line; anything but
// an id leaves every App needing an issue.
export function specFromBodyApps(text) {
  const ids = String(text ?? "").split(/\s+/).filter(Boolean);
  return ids.every((id) => /^[1-9][0-9]*$/.test(id)) ? ids.map(Number) : [];
}

// check-intent's reads, handed to check-intent-subscription in one job output
// so a handoff does not repeat them: written by `carry` from the files and
// outputs of the base-side steps, before the model runs, as base64 JSON. A
// bundle over CARRY_MAX characters is not handed on, so the job output and the
// env var that takes it stay small; the subscription job then reads again.
export const CARRY_MAX = 96_000;
const HEAD_REF = /^[A-Za-z0-9._/-]+$/;
const ATTEMPT = /^[1-9][0-9]{0,4}$/;

export function packReads({ attempt, prNumber, headSha, baseSha, headRef, relinkSinceHead, linkedIssues, specText, context }) {
  const packed = Buffer.from(
    JSON.stringify({ v: 1, attempt, pr: prNumber, head_sha: headSha, base_sha: baseSha, head_ref: headRef, relink_since_head: relinkSinceHead, linked_issues: linkedIssues, spec_text: specText, context }),
  ).toString("base64");
  return packed.length <= CARRY_MAX ? packed : "";
}

// The carried reads when they hold for this run attempt: a re-run of the
// subscription job alone is a new attempt that keeps check-intent's outputs,
// and what was judged may have changed since, so it reads again. Anything
// malformed is null, never a partial bundle.
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

// `carry`: the reads output, from the resolver's outputs and the data files
// it and select-trusted-text wrote; empty when anything is missing.
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
  // Checked as the taker will, so a bad bundle is never handed on.
  if (packed !== "" && takeReads(packed, env.GITHUB_RUN_ATTEMPT) === null) {
    packed = "";
  }
  appendFileSync(env.GITHUB_OUTPUT, `reads=${packed}\n`);
  console.log(packed === "" ? "resolve-pr: no reads handed on; a handoff reads again" : `resolve-pr: handed on ${packed.length} characters of reads`);
}

// For a workflow other than pr-verify.yml that reads the same pull request
// (RATED_WORKFLOW_PATH, RATED_ARTIFACT_PREFIX): whether an unexpired
// `<prefix>-<pr>-<head>` artifact of a run of that file's origin (ofOrigin)
// already stands, so the head is not paid for twice. Undefined when neither is
// set, which leaves the verifier's rules; a malformed value throws.
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
    for (const artifact of await artifactsNamed(github, repository, name)) {
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

// The lane a failure or hold names: pr-verify unless RESOLVE_LANE names
// another reader of the same pull request.
const laneOf = (env) => (/^[a-z][a-z0-9-]{0,40}$/.test(env?.RESOLVE_LANE ?? "") ? env.RESOLVE_LANE : "pr-verify");

export async function main(env = process.env, { github, fetchImpl, latch } = {}) {
  if (env.CARRIED) {
    const taken = takeReads(env.CARRIED, env.GITHUB_RUN_ATTEMPT);
    if (taken !== null && env.CONTEXT_FILE && env.SPEC_FILE && env.SPEC_TEXT_FILE && env.GITHUB_OUTPUT) {
      writeFileSync(env.SPEC_FILE, `${JSON.stringify(taken.linkedIssues, null, 2)}\n`);
      writeFileSync(env.SPEC_TEXT_FILE, `${JSON.stringify(taken.specText, null, 2)}\n`);
      writeFileSync(env.CONTEXT_FILE, `${JSON.stringify(taken.context, null, 2)}\n`);
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
    "GITHUB_OUTPUT",
    "UPSTREAM_RUN_ID",
    "SPEC_FILE",
    "SPEC_TEXT_FILE",
    "TRUSTED_ACTORS_PATH",
  ]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const trusted = loadTrustedList(env.TRUSTED_ACTORS_PATH);
  const api = (keepGraphQLErrors) => createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, fetchImpl, keepGraphQLErrors, latch });
  // A job's log: GitHub answers with a redirect to storage, which is read
  // without the token.
  const send = fetchImpl ?? fetch;
  // The API request is counted for the job-end api-calls notice; the storage
  // read it redirects to is not a GitHub API request.
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
  const result = await resolvePull({
    github: github ?? api(false),
    // The Refs read needs GraphQL errors back to tell a typo from a failure.
    readRefs: github ?? api(true),
    readLog,
    repository: env.GITHUB_REPOSITORY,
    upstreamRunId: env.UPSTREAM_RUN_ID,
    humans: trusted.humans,
    // pr-verify.yml reads both from main's pr-pipeline.yaml; unset is `lane`.
    verifyAuthors: env.VERIFY_AUTHORS ?? "lane",
    laneIdentity: env.LANE_IDENTITY,
    // The lanes App's id: merge.agent-identity's entry on the trusted list,
    // with or without its [bot] suffix.
    laneAppId: trusted.logins.get(`${loginKey(env.LANE_IDENTITY)}[bot]`),
    // Admission's task-list marker, from the checkout this script runs from
    // (main's, in pr-verify.yml): a split sub-issue counts only by it.
    taskList: loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)))["task-list"],
    // The issue lane's web hosts, which pr-verify.yml reads from main's
    // pr-pipeline.yaml as admission does (resolve-config issueLaneWebHostsFromBase).
    webHosts: webHostsFrom(env.ISSUE_LANE_WEB_HOSTS),
    ownerIds: [...trusted.ids],
    specFromBodyApps: specFromBodyApps(env.SPEC_FROM_BODY_APPS),
    keepJobs: (list) => {
      jobs = list;
    },
    rated: ratedBy(env),
  });
  if (result.proceed && !/^[A-Za-z0-9._/-]+$/.test(result.headRef)) {
    throw new Error("the head branch has a name the outputs cannot carry");
  }
  if (result.proceed) {
    writeFileSync(env.SPEC_FILE, `${JSON.stringify(result.linkedIssues, null, 2)}\n`);
    writeFileSync(env.SPEC_TEXT_FILE, `${JSON.stringify(result.specText, null, 2)}\n`);
    // The run's jobs, read whole, for upstream-jobs.mjs (keptJobs).
    if (jobs !== undefined && keptJobsPath(env)) {
      writeFileSync(keptJobsPath(env), `${JSON.stringify(shapeJobs(env.UPSTREAM_RUN_ID, jobs))}\n`);
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

// The step's error annotation for a failed run, with the refused answer's
// detail when a GitHub call failed.
export const failureAnnotation = (error, env = process.env) => `::error::${laneOf(env)} could not resolve the pull request: ${error.message}${detailSuffix(error)}`;

// The reason a GitHub fault writes, which pr-verify.yml's HELD_STEP runs on.
export const HELD_REASON = "held";
// pr-verify.yml's step that runs only on a held run, so the lost-run reconciler
// reads its annotations only for such a run (reconcile.mjs faultHeld).
export const HELD_STEP = "Note the hold";

// The step's closing for the error main threw: a GitHub fault (isFault: a 5xx,
// a 429, a rate-guard stop under API_BUDGET_HOLD, or no answer) or a 200 whose
// completeness check failed (`incomplete`) holds green with a `held: ` notice
// and proceed=false, so nothing is judged and the lost-run reconciler re-runs
// the run once on its next pass (outage posture element 2); any other error
// fails the step with failureAnnotation.
export function closing(error, env = process.env) {
  if (!isFault(error) && error?.incomplete !== true) {
    return { lines: [failureAnnotation(error, env)], outputs: null, code: 1 };
  }
  const why = `${error?.message ?? error}${detailSuffix(error)}`.replaceAll(/[\r\n%]/g, " ");
  const lane = laneOf(env);
  return { lines: [`::notice title=${lane}::held: ${lane} could not resolve the pull request: ${why}`], outputs: `proceed=false\nreason=${HELD_REASON}\n`, code: 0 };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href && process.argv[2] === "carry") {
  carryMain();
} else if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    const closed = closing(error);
    closed.lines.forEach((line) => console.log(line));
    if (closed.outputs && process.env.GITHUB_OUTPUT) {
      appendFileSync(process.env.GITHUB_OUTPUT, closed.outputs);
    }
    process.exitCode = closed.code;
  });
}
