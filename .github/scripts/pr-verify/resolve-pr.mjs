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
//   one of DEPENDENCY_MANAGERS' logins);
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
//   nothing does not stop a new judgment, and neither do passes that all
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
// least once (relinkedByPeople): reason `relinked`. The gate weighs the pass that
// judgment writes by the same rule (babysit_verify_evidence `_superseded`).
// A judgment also reports relink-since-head: whether the PR's body or links
// changed since the head commit (relinkedSince), which sets how long its pass
// lasts (write-verdict.mjs retentionDays).

import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  commitPulls,
  createGitHub,
  detailSuffix,
  graphQLReader,
  loadTrustedList,
  responseDetail,
} from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { titleRenamers } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { issuesSuffix, isVerdictName, NAME } from "./write-verdict.mjs";
import { refsIssue } from "../pr-merge/merge-holds.mjs";
import { carriesSplit, loadRules, personChecks, refinementSpec, SPLIT_CHILD_MARKER, splitChildBody, splitScope, taskItems, webHostsFrom } from "../intake-triage/admit.mjs";

export { refsIssue };

// The name grammar lives with its writer; the resolver checks names against it.
export { isVerdictName, NAME, NAME_MAX } from "./write-verdict.mjs";

export const UPSTREAM_PATH = ".github/workflows/pr-require-checks.yml";
export const VERIFY_PATH = ".github/workflows/pr-verify.yml";
// babysit_classify.DEPENDENCY_MANAGER_LOGINS: the pr-merge lane refuses these
// Bot accounts' pull requests before reading a verdict.
export const DEPENDENCY_MANAGERS = Object.freeze(["dependabot", "dependabot-preview", "renovate", "renovate-bot"]);
const VERIFY_AUTHORS = Object.freeze(["lane", "lane-or-owner", "any"]);

const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const MAX_PAGES = 100;

const ISSUE_FIELDS = `number repository { nameWithOwner } body lastEditedAt
          author { ...actor } editor { ...actor }
          comments(first: 100) { totalCount nodes { databaseId createdAt updatedAt body lastEditedAt author { ...actor } editor { ...actor } } }`;
const ACTOR = "fragment actor on Actor { __typename login ... on User { databaseId } ... on Bot { databaseId } }";
const SPEC_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      createdAt body lastEditedAt editor { ...actor }
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
const REFS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issueOrPullRequest(number: $number) { __typename ... on Issue { ${ISSUE_FIELDS} } }
  }
}
${ACTOR}`;

// A size split's sub-issue's native parent, with the text admit.mjs specOf
// reads, for splitChildBody.
const PARENT_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      parent { number repository { nameWithOwner } body lastEditedAt author { ...actor } editor { ...actor }
        comments(first: 100) { totalCount nodes { databaseId createdAt updatedAt body lastEditedAt author { ...actor } editor { ...actor } } } }
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
// request falls from `since` on, and every one there was a trusted person's
// (babysit_verify_evidence `_relinked_by_people`, which ends the window at a
// pass run's completion). None there means the link changed some way this read cannot
// see. A failed read, a list cut short, or an act with no readable time is false.
export async function relinkedByPeople(github, repository, number, humans, since) {
  const start = Date.parse(since ?? "");
  const acts = Number.isNaN(start) ? null : await relinkActs(github, repository, number);
  const inside = (acts ?? []).filter(([at]) => Date.parse(at) >= start);
  return inside.length > 0 && inside.every(([, actor]) => trustedHuman(actor, humans));
}

// Every body edit and issue connect or disconnect on the pull request, each
// [time, actor], read whole (RELINK_QUERY); null for a failed read, a list
// cut short, or an act with no readable time.
async function relinkActs(github, repository, number) {
  const [o, r] = repository.split("/");
  let pull;
  try {
    pull = (await github("POST", "/graphql", { query: RELINK_QUERY, variables: { o, r, n: number } }))?.data?.repository?.pullRequest;
  } catch {
    return null;
  }
  const edits = pull?.userContentEdits;
  // totalCount counts every timeline item; filteredCount the kinds asked.
  const events = pull?.timelineItems;
  if (!Array.isArray(edits?.nodes) || edits.totalCount !== edits.nodes.length || !Array.isArray(events?.nodes) || events.filteredCount !== events.nodes.length) {
    return null;
  }
  const acts = [...edits.nodes.map((node) => [node?.editedAt, node?.editor]), ...events.nodes.map((node) => [node?.createdAt, node?.actor])];
  return acts.some(([at]) => Number.isNaN(Date.parse(at ?? ""))) ? null : acts;
}

// Whether anyone edited the pull request's body or connected or disconnected
// an issue from `since`, the head commit's time, on. Only then can a pass
// judged at the head supersede a FAIL there (babysit_verify_evidence
// `_superseded` needs such an act after the FAIL, which comes after the
// commit), so write-verdict.mjs keeps such a pass as long as a FAIL. A time
// or read that fails answers true.
export async function relinkedSince(github, repository, number, since) {
  const start = Date.parse(since ?? "");
  const acts = Number.isNaN(start) ? null : await relinkActs(github, repository, number);
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
// App pull request, and the step after it that aggregates the lanes.
export const HOLD_STEP = "Fail a lanes App pull request its body or a member holds";
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
export async function heldOnly(github, readLog, repository, runId, number) {
  try {
    const listed = await github("GET", `/repos/${repository}/actions/runs/${runId}/jobs?filter=latest&per_page=100`);
    const jobs = listed?.jobs;
    if (!Array.isArray(jobs) || listed.total_count !== jobs.length) {
      return false;
    }
    const ci = jobs.filter((job) => job?.name === "ci-status");
    if (ci.length !== 1 || ci[0].conclusion !== "failure" || !Number.isSafeInteger(ci[0].id)) {
      return false;
    }
    if (jobs.some((job) => job !== ci[0] && !["success", "skipped", "neutral"].includes(job?.conclusion))) {
      return false;
    }
    const steps = Array.isArray(ci[0].steps) ? ci[0].steps : [];
    const failed = steps.filter((step) => step?.conclusion !== "success" && step?.conclusion !== "skipped");
    const names = failed.map((step) => step?.name);
    if (
      failed.length === 0 ||
      failed.some((step) => step.conclusion !== "failure" || ![HOLD_STEP, CONTRACT_STEP].includes(step.name)) ||
      new Set(names).size !== names.length ||
      !steps.some((step) => step?.name === AGGREGATE_STEP && step.conclusion === "success")
    ) {
      return false;
    }
    const errors = errorLines(await readLog(ci[0].id));
    const reasons = errors.filter((line) => line !== STEP_EXIT);
    const person = reasons.filter((line) => personHoldLine(line, number));
    const label = reasons.filter((line) => line === DO_NOT_MERGE_LINE);
    return (
      errors.length - reasons.length === failed.length &&
      person.length + label.length === reasons.length &&
      (person.length > 0) === names.includes(HOLD_STEP) &&
      label.length === (names.includes(CONTRACT_STEP) ? 1 : 0)
    );
  } catch {
    return false;
  }
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
    run.path !== VERIFY_PATH ||
    run.event !== "workflow_run" ||
    run.head_branch !== base ||
    run.repository?.full_name !== repository ||
    run.head_repository?.full_name !== repository ||
    run.status !== "completed" ||
    (verdict !== "fail" && run.conclusion !== "success") ||
    !SHA.test(run.head_sha ?? "")
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
        throw new Error(`page ${page} is not a list`);
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
// looked up only when none is found. This PR's plain FAIL answers instead
// `ownFail`, the earliest creation time of its counted runs, so the caller
// can weigh a relink (`relinkedByPeople`) and then look up the rest with
// `afterOwn`.
async function judged({ github, repository, number, head, base, prs, issues, afterOwn = false }) {
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
      if (run !== null && verdict === "fail" && name === own && issues === undefined) {
        created.push(Date.parse(run.created_at ?? ""));
      } else if (run !== null && verdict === "fail") {
        return { fail: true, passes };
      } else if (run !== null) {
        passes.push(run.run_started_at);
      }
    }
    if (created.length > 0) {
      // NaN for any missing time, which relinkedByPeople refuses.
      const earliest = Math.min(...created);
      return { fail: false, passes, ownFail: Number.isNaN(earliest) ? "" : new Date(earliest).toISOString() };
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
// admission's `task-list` (admit.mjs splitChildBody, its one home).
// The merge gate cannot see the refinement: an edit, a hide (isMinimized)
// or a newer one after a pass leaves that pass standing. An edit only takes
// the refinement out of spec, so no one gains a spec by it; a person's
// correction made after a pass waits for the next head.
export async function linkedIssues(github, readRefs, repository, number, humans, laneAppId, taskList, webHosts) {
  const [owner, name] = repository.split("/");
  const data = await github("POST", "/graphql", { query: SPEC_QUERY, variables: { owner, name, number } });
  const refs = data?.data?.repository?.pullRequest?.closingIssuesReferences;
  if (!refs || !Array.isArray(refs.nodes) || refs.totalCount !== refs.nodes.length) {
    throw new Error(`#${number}: the closing issues could not be read`);
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
      throw new Error(`#${number}: the Refs issue could not be read`);
    }
    nodes = node?.__typename === "Issue" ? [node] : [];
  }
  const issues = nodes.filter(
    (issue) => issue?.repository?.nameWithOwner === repository && Number.isSafeInteger(issue.number),
  );
  for (const issue of issues) {
    const comments = issue.comments;
    if (!Array.isArray(comments?.nodes) || comments.totalCount !== comments.nodes.length) {
      throw new Error(`#${issue.number}: the issue's comments could not be read`);
    }
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
      throw new Error(`#${issue.number}: the split parent could not be read`);
    }
    const parent = read.parent;
    const here = parent?.repository?.nameWithOwner === repository;
    if (here && (!Array.isArray(parent.comments?.nodes) || parent.comments.totalCount !== parent.comments.nodes.length)) {
      throw new Error(`#${issue.number}: the split parent's comments could not be read`);
    }
    const body = here ? splitChildBody({ ...issue, splitParent: { number: parent.number, spec: { ...parent, comments: parent.comments.nodes }, appId: laneAppId } }, humans, taskList) : null;
    if (body !== null) {
      childBodies.set(issue.number, body);
    }
  }
  const pullRequest = data.data.repository.pullRequest;
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
      return {
        number: issue.number,
        spec_kind: named !== null ? "refs" : "closes",
        body: written(issue) && typeof issue.body === "string" ? issue.body : (childBodies.get(issue.number) ?? null),
        // A trusted target-subset part's Scope line (admit.mjs splitScope):
        // its done-when lines apply only to these targets.
        ...(!written(issue) && childBodies.has(issue.number) && splitScope(childBodies.get(issue.number)) !== null && { scope: splitScope(childBodies.get(issue.number)) }),
        comments: issue.comments.nodes.filter((comment) => written(comment) || comment === counted).map((comment) => String(comment.body ?? "")),
        // The body's done-when items that refinement lists as checks a
        // person runs (admit.mjs personChecks), each as written.
        ...(checks.length > 0 && { person_checks: checks.map((n) => taskItems(issue.body, taskList)[n - 1].text) }),
      };
    }),
  };
}

export async function resolvePull({ github, readRefs = github, readLog, repository, upstreamRunId, humans, base = "main", verifyAuthors = "lane", laneIdentity, laneAppId, taskList, webHosts, ownerIds: owners = [], specFromBodyApps = [] }) {
  const skip = (reason) => ({ proceed: false, reason });
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
  if (run.conclusion === "failure" && !(typeof readLog === "function" && (await heldOnly(github, readLog, repository, upstreamRunId, pull.number)))) {
    return skip("not-a-passing-run");
  }
  const prs = new Set(associated.map((item) => item?.number).filter((n) => Number.isSafeInteger(n) && n > 0));
  let { fail, passes, ownFail } = await judged({ github, repository, number: pull.number, head, base, prs });
  if (fail) {
    return skip("already-judged");
  }
  let specRead;
  if (ownFail !== undefined) {
    // This PR's plain FAIL stands unless it now links issues a FAIL name
    // carries, which differ from the none or too many the FAIL recorded, and
    // only trusted people changed the link since. A failed read keeps it.
    specRead = await linkedIssues(github, readRefs, repository, pull.number, humans, laneAppId, taskList, webHosts).catch(() => null);
    const suffix = specRead && issuesSuffix(specRead.linkedIssues.map((issue) => issue.number));
    if (!suffix || !isVerdictName(`pr-verify-${pull.number}-${head}-fail${suffix}`) || !(await relinkedByPeople(github, repository, pull.number, humans, ownFail))) {
      return skip("already-judged");
    }
    ({ fail, passes } = await judged({ github, repository, number: pull.number, head, base, prs, afterOwn: true }));
    if (fail) {
      return skip("already-judged");
    }
  }
  specRead ??= await linkedIssues(github, readRefs, repository, pull.number, humans, laneAppId, taskList, webHosts);
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
  // listed).
  const { bodyEditor, bodyEditedAt, ...spec } = specRead;
  const byAuthorOrPerson = (id) => Number.isSafeInteger(id) && (id === pull.user?.id || humans.has(id));
  const bodyIsIntent =
    (humans.has(pull.user?.id) || specFromBodyApps.includes(pull.user?.id)) &&
    (bodyEditor === null || byAuthorOrPerson(bodyEditor));
  const titleIsIntent = async () => {
    const renamers = await titleRenamers(github, repository, pull.number);
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
  if ((await judged({ github, repository, number: pull.number, head, base, prs, issues })).fail) {
    return skip("already-judged");
  }
  return {
    proceed: true,
    reason: ownFail !== undefined ? "relinked" : passes.length > 0 ? "spec-changed" : "ok",
    relinkSinceHead: ownFail !== undefined || (await relinkedSince(github, repository, pull.number, run.head_commit?.timestamp)),
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
  });
  if (result.proceed && !/^[A-Za-z0-9._/-]+$/.test(result.headRef)) {
    throw new Error("the head branch has a name the outputs cannot carry");
  }
  if (result.proceed) {
    writeFileSync(env.SPEC_FILE, `${JSON.stringify(result.linkedIssues, null, 2)}\n`);
    writeFileSync(env.SPEC_TEXT_FILE, `${JSON.stringify(result.specText, null, 2)}\n`);
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
export const failureAnnotation = (error) => `::error::pr-verify could not resolve the pull request: ${error.message}${detailSuffix(error)}`;

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href && process.argv[2] === "carry") {
  carryMain();
} else if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(failureAnnotation(error));
    process.exitCode = 1;
  });
}
