// Resolves the pull request a pr-require-checks run passed, for pr-verify.yml.
// The only event field it takes is the upstream run id; every other fact is
// read back from the API. It proceeds only when all of these hold, and
// otherwise writes proceed=false with a reason:
// - the run is a completed, successful pull_request run of
//   pr-require-checks.yml, by exact path, in this repository on a head of
//   this repository;
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

import { appendFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  commitPulls,
  createGitHub,
  graphQLReader,
  loadTrustedList,
} from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { headRefDigest, issuesSuffix, isVerdictName, NAME } from "./write-verdict.mjs";
import { refsIssue } from "../pr-merge/merge-holds.mjs";
import { refinementSpec, SPLIT_CHILD_MARKER, splitChildBody } from "../intake-triage/admit.mjs";

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
        comments(first: 100) { totalCount nodes { body lastEditedAt author { ...actor } editor { ...actor } } } }
    }
  }
}
${ACTOR}`;

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
// requests carry, each without a head-ref digest and with the digest of that
// pull request's head branch (write-verdict.mjs headRefDigest), which doubles
// the lookups. Once write-verdict writes only digest names, the digest-free
// lookups are needed only until the last artifact named that way expires
// (90-day retention), and then go. Given `issues`, this PR's linked issue
// numbers, it looks up only this PR's FAIL names with `-i` and those issues
// (write-verdict.mjs artifactName), so the caller reads the issues only for a
// head the names without them leave unjudged; issues no name carries (over
// the cap, or a number the pattern refuses) are never looked up, since the
// writer names that FAIL plainly. A FAIL another PR left at the
// head names issues this run never reads, so its suffixed name is missed and
// the head is judged again; so is a head whose linked issues a body edit
// changed since this PR's FAIL there. Each costs a run and changes nothing
// the gate decides: the earlier FAIL stays tied and refuses the head.
// A counted FAIL answers `fail`; this PR's counted passes answer only their
// runs' start times (`passes`), which `specChanged` weighs against the spec.
async function judged({ github, repository, number, head, base, refs, issues }) {
  // The digest is hex whatever the branch holds, so any non-empty one is looked up.
  const named = (pr, verdict) => {
    const ref = refs.get(pr);
    return [`pr-verify-${pr}-${head}-${verdict}`, ...(ref ? [`pr-verify-${pr}-${head}-${verdict}-${headRefDigest(ref)}`] : [])];
  };
  const suffix = issues === undefined ? "" : issuesSuffix(issues);
  const names =
    issues === undefined
      ? [
          ...["pass", "pass-notes", "fail"].flatMap((verdict) => named(number, verdict)),
          ...[...refs.keys()].filter((other) => other !== number).flatMap((other) => named(other, "fail")),
        ]
      : suffix
        ? named(number, "fail")
            .map((name) => name + suffix)
            .filter(isVerdictName)
        : [];
  const passes = [];
  for (const name of names) {
    const [, , , verdict] = NAME.exec(name);
    for (const artifact of await artifactsNamed(github, repository, name)) {
      if (artifact?.name !== name || artifact.expired !== false) {
        continue;
      }
      const runId = artifact.workflow_run?.id;
      const run = Number.isSafeInteger(runId) ? await countedRun({ github, repository, runId, verdict, base }) : null;
      if (run !== null && verdict === "fail") {
        return { fail: true, passes };
      }
      if (run !== null) {
        passes.push(run.run_started_at);
      }
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
// spec (`specText`). Other Bot and App text is left out even where
// select-trusted-text keeps it, except the body of a sub-issue the lanes App
// filed in a size split, whose lines are its listed-human parent's
// (admit.mjs splitChildBody).
// The merge gate cannot see the refinement: an edit, a hide (isMinimized)
// or a newer one after a pass leaves that pass standing. An edit only takes
// the refinement out of spec, so no one gains a spec by it; a person's
// correction made after a pass waits for the next head.
async function linkedIssues(github, readRefs, repository, number, humans, laneAppId) {
  const [owner, name] = repository.split("/");
  const data = await github("POST", "/graphql", { query: SPEC_QUERY, variables: { owner, name, number } });
  const refs = data?.data?.repository?.pullRequest?.closingIssuesReferences;
  if (!refs || !Array.isArray(refs.nodes) || refs.totalCount !== refs.nodes.length) {
    throw new Error(`#${number}: the closing issues could not be read`);
  }
  const trusted = (actor) => actor?.__typename === "User" && humans.has(actor.databaseId);
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
    const parent = (await github("POST", "/graphql", { query: PARENT_QUERY, variables: { owner, name, number: issue.number } }))?.data?.repository?.issue?.parent;
    const complete = parent?.repository?.nameWithOwner === repository && Array.isArray(parent.comments?.nodes) && parent.comments.totalCount === parent.comments.nodes.length;
    const body = complete ? splitChildBody({ ...issue, splitParent: { number: parent.number, spec: { ...parent, comments: parent.comments.nodes }, appId: laneAppId } }, humans) : null;
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
      return {
        number: issue.number,
        spec_kind: named !== null ? "refs" : "closes",
        body: written(issue) && typeof issue.body === "string" ? issue.body : (childBodies.get(issue.number) ?? null),
        comments: issue.comments.nodes.filter((comment) => written(comment) || comment === refinement).map((comment) => String(comment.body ?? "")),
      };
    }),
  };
}

export async function resolvePull({ github, readRefs = github, repository, upstreamRunId, humans, base = "main", verifyAuthors = "lane", laneIdentity, laneAppId, ownerIds: owners = [], specFromBodyApps = [] }) {
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
    run.conclusion !== "success" ||
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
  const refs = new Map(
    associated
      .filter((item) => Number.isSafeInteger(item?.number) && item.number > 0)
      .map((item) => [item.number, String(item.head?.ref ?? "")]),
  );
  const { fail, passes } = await judged({ github, repository, number: pull.number, head, base, refs });
  if (fail) {
    return skip("already-judged");
  }
  // This PR's FAIL is named with the issues it records, read only now.
  const specRead = await linkedIssues(github, readRefs, repository, pull.number, humans, laneAppId);
  const issues = specRead.linkedIssues.map((issue) => issue.number);
  if ((await judged({ github, repository, number: pull.number, head, base, refs, issues })).fail) {
    return skip("already-judged");
  }
  // No closing issue here: the title and body of a trusted person's PR, or
  // of an App whose bodies a script writes (adoption.spec-from-body-apps),
  // are the spec. A model-written body, the lanes App's included, never is:
  // the run that wrote the diff would have written its spec too.
  // A person is a kind human id on the trusted list, not a GitHub User: a
  // model's account may be a User (babysit_merge_policy.lane_eligibility's twin).
  // A body someone else edited is not the author's intent, unless a trusted
  // person did it; an editor GitHub cannot name is someone else.
  const { bodyEditor, bodyEditedAt, ...spec } = specRead;
  const bodyIsIntent =
    (humans.has(pull.user?.id) || specFromBodyApps.includes(pull.user?.id)) &&
    (bodyEditor === null || bodyEditor === pull.user?.id || humans.has(bodyEditor));
  if (spec.linkedIssues.length === 0 && bodyIsIntent) {
    const body = `${String(pull.title ?? "")}\n\n${String(pull.body ?? "")}`;
    spec.specKind = "pull-request";
    spec.specText = [{ number: pull.number, source: "pull-request", spec_kind: "pull-request", body, comments: [] }];
  }
  // A pass judged before the spec last changed is one the gate refuses, so
  // the head is judged again against the spec as it is now.
  if (passes.length > 0 && !specChanged(passes, { ...spec, bodyEditedAt })) {
    return skip("already-judged");
  }
  return {
    proceed: true,
    reason: passes.length > 0 ? "spec-changed" : "ok",
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

export async function main(env = process.env, { github, fetchImpl } = {}) {
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
  const api = (keepGraphQLErrors) => createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, fetchImpl, keepGraphQLErrors });
  const result = await resolvePull({
    github: github ?? api(false),
    // The Refs read needs GraphQL errors back to tell a typo from a failure.
    readRefs: github ?? api(true),
    repository: env.GITHUB_REPOSITORY,
    upstreamRunId: env.UPSTREAM_RUN_ID,
    humans: trusted.humans,
    // pr-verify.yml reads both from main's pr-pipeline.yaml; unset is `lane`.
    verifyAuthors: env.VERIFY_AUTHORS ?? "lane",
    laneIdentity: env.LANE_IDENTITY,
    // The lanes App's id: merge.agent-identity's entry on the trusted list,
    // with or without its [bot] suffix.
    laneAppId: trusted.logins.get(`${loginKey(env.LANE_IDENTITY)}[bot]`),
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

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::error::pr-verify could not resolve the pull request: ${error.message}`);
    process.exitCode = 1;
  });
}
