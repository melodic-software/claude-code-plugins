#!/usr/bin/env node
// merge-holds.mjs: the merge holds a pull request's own text carries, by the
// rules pr-merge's gate reads them. enable-auto-merge.mjs arms nothing they
// hold, and ci-status runs this file alone, fetched from the base commit, on
// every lanes App pull request, so it imports no other file of the repository.
//
// - A body hold (babysit_merge_policy.BODY_MERGE_HOLD_RE): a line opening with
//   `Hold:`, or "do not merge" anywhere. Removing that text lifts it.
// - A member veto (babysit_merge.human_veto_logins): each OWNER, MEMBER or
//   COLLABORATOR person's newest comment, review or inline comment with text
//   decides, and holds when it says "do not merge"
//   (babysit_merge.HUMAN_MERGE_VETO_RE). A later one by the same person
//   lifts it; an item with no text lifts nothing.
// - A hold path: a changed file, or a renamed file's old path, matching the
//   merge lane's denied paths, which resolve-config resolves as the config's
//   merge.diff-check.denied-paths plus HOLD_PATH_FLOOR. A person on the
//   trusted-actor list lifts it by approving the head: their newest review of
//   the head that approves, requests changes or was dismissed must approve.
// - A cost path (COST_PATHS): a changed file the gate holds for the owner's
//   cost decision. An approval does not lift it; only the decision the gate
//   reads does (costDecision), linked from the body.
// - No verifier pass, when a verdicts file is given (ci-status gives one in
//   the merge queue only): the head merges on a PASS or PASS-NOTES that
//   pr-verify.yml uploaded from a completed, successful run on main
//   (verdictHold). The same approval of the head lifts it, the human merge
//   path for a pull request pr-merge's gate sends to a person. FAILs and the
//   repeated-FAIL cap are enable-auto-merge.mjs's, through pr-merge's own
//   reader, which disarms such a pull request.
//
// Command line: merge-holds.mjs <number> <body-file> <discussion-file>
// <files-file> <denied-paths-file> <trusted-actors-file> <head-sha>
// [<verdicts-file>]. The verdicts file holds one {name, verdict, runId, run}
// per line, run as GET actions/runs/{runId} gives it, for each unexpired artifact
// named a pass at the head; GITHUB_REPOSITORY names the repository. The
// discussion file holds one REST issue comment, review or review comment per
// line; the files file one JSON array per changed file, its path then any
// renamed-from path; the denied-paths file the config's
// merge.diff-check.denied-paths as JSON; the trusted-actors file
// trusted-actors.json. Each hold prints as an ::error:: and exits 1; no hold
// exits 0. A cost path with a decision link in the body reads the decision
// with GH_TOKEN.
import { readFileSync } from "node:fs";
import { posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

// enable-auto-merge.test.mjs checks both agree with the gate's Python on every
// text it tries.
export const BODY_HOLD = /\bdo(?:n['’]?t| not)\s+merge\b|(?:^|\r)[^\S\r\n]*hold:/im;
export const HUMAN_VETO = /\bdo(?:n['’]?t| not|-not)[\s-]*merge\b/i;
// babysit_merge_policy.BLOCKER_ASSOCIATIONS.
const MEMBERS = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);
// The denied paths resolve-config adds to every config's (resolveMerge);
// merge-authority.test.mjs checks the two agree.
export const FORCED_DENIED_PATHS = Object.freeze([
  "docs/conventions/pr-pipeline.yaml",
  ".github/**",
  ".github/standards/trusted-actors/trusted-actors.json",
]);
// Every hold path check adds these: the forced paths, the rest of the merge
// gate's HIGH floor (babysit_risk.HIGH_FLOOR), and every plugin manifest and
// the marketplace manifest (babysit_risk.is_manifest_path), a path-wide
// stand-in for the gate's manifest checks.
export const HOLD_PATH_FLOOR = Object.freeze([
  ...FORCED_DENIED_PATHS,
  "**/CODEOWNERS",
  "**/.gitmodules",
  "**/.claude-plugin/plugin.json",
  ".claude-plugin/marketplace.json",
]);
// babysit_risk.COST_PATHS, matched case-folded as its glob_match does;
// test_merge_holds_sync.py checks the two agree.
export const COST_PATHS = Object.freeze([
  "plugins/multi-agent/reference/defaults.yaml",
  "**/Pulumi.yaml",
  "**/Pulumi.*.yaml",
  "**/*.tf",
  "**/*.tfvars",
  "**/*.bicep",
  "**/*.bicepparam",
]);

// The members whose newest item with text vetoes the merge, sorted. Each item
// is { login, isUser, association, at, body }, `at` an ISO 8601 UTC time.
export function vetoers(items) {
  const newest = new Map();
  for (const { login, isUser, association, at, body } of items) {
    if (!isUser || !MEMBERS.has(String(association).toUpperCase()) || !String(body ?? "").trim()) {
      continue;
    }
    if (!newest.has(login) || at >= newest.get(login).at) {
      newest.set(login, { at, body: String(body) });
    }
  }
  return [...newest]
    .filter(([, { body }]) => HUMAN_VETO.test(body))
    .map(([login]) => login)
    .sort();
}

// One REST issue comment, review or review comment as a vetoers item.
export const fromRest = (row) => ({
  login: String(row?.user?.login ?? ""),
  userId: row?.user?.id,
  state: row?.state,
  commitId: row?.commit_id,
  isUser: row?.user?.type === "User",
  association: row?.author_association,
  at: String(row?.submitted_at ?? row?.created_at ?? ""),
  body: String(row?.body ?? ""),
});

// Whether `path` matches the hold-path `glob`. path.matchesGlob has no `dot`
// option, so `*` and `**` skip a segment opening with "."; both sides mark
// such a segment alike first, so `.github/**` holds `.github/a/.x` too.
const undot = (text) => String(text).replaceAll(/(^|\/)\./g, "$1\u0001");
export const matchesHoldPath = (path, glob) => posix.matchesGlob(undot(path), undot(glob));

// Why the head's changed `files` hold it, or null. Null `holdPaths` or
// `files` (unreadable) holds it.
export function pathHold(files, holdPaths) {
  if (!Array.isArray(holdPaths)) {
    return "the hold paths could not be read";
  }
  if (!Array.isArray(files)) {
    return "its changed files could not all be read";
  }
  if (typeof posix.matchesGlob !== "function") {
    return "this Node has no path.matchesGlob, so its hold paths cannot be checked";
  }
  const globs = [...holdPaths, ...HOLD_PATH_FLOOR];
  const held = files.find((path) => globs.some((glob) => matchesHoldPath(path, glob)));
  return held === undefined ? null : `it changes ${held}, a hold path`;
}

// Why the changed `files` hold it for the owner's cost decision, or null when
// none is a cost path or `decision` (costDecision's link) clears it. As
// glob_match does, a glob also covers everything under it.
export function costHold(files, decision) {
  const held = (Array.isArray(files) ? files : []).find((path) =>
    COST_PATHS.some((glob) => [glob, `${glob}/**`].some((each) => matchesHoldPath(String(path).toLowerCase(), each.toLowerCase()))),
  );
  return held === undefined || decision ? null : `it changes ${held}, a cost path`;
}

// babysit_merge_policy COST_DECISION_LINK, DECISION_LINE and HTML_COMMENT.
const DECISION_LINK = /https:\/\/github\.com\/([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)\/(?:issues|pull)\/([0-9]+)#issuecomment-([0-9]+)/g;
const DECISION_LINE = /^\*\*Decision recorded\.\*\*[ \t]+Cost:/;
const HTML_COMMENT = /<!--[\s\S]*?(?:-->|$)/g;
export const PULL_OPENED_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { createdAt closingIssuesReferences(first: 2) { totalCount nodes { number repository { nameWithOwner } } } }
  }
}`;
export const COMMENT_EDITED_QUERY = "query($id: ID!) { node(id: $id) { ... on IssueComment { lastEditedAt } } }";

// The first comment link in `body`, outside HTML comments, that records the
// owner's cost decision for pull request `number` of `repo`, else null: the
// rule of babysit_merge_policy.cost_decision, with the owner a person whose
// id is in `humans` (trusted-actors.json), as ci-status's cost-only review
// hold step names one. The comment is on the pull request, or on its one
// closing issue in `repo` and newer than the pull request; by a User, not
// through an App; never edited; its first line `**Decision recorded.** Cost:`.
// `github(method, path, body)` reads; a read that fails clears nothing.
export async function costDecision(github, repo, number, body, humans) {
  const links = [...String(body ?? "").replaceAll(HTML_COMMENT, "").matchAll(DECISION_LINK)].filter(
    (link) => `${link[1]}/${link[2]}`.toLowerCase() === String(repo).toLowerCase(),
  );
  if (!links.length) {
    return null;
  }
  const [owner, name] = repo.split("/");
  let pull;
  try {
    pull = (await github("POST", "/graphql", { query: PULL_OPENED_QUERY, variables: { owner, name, number } }))?.data?.repository?.pullRequest;
  } catch {
    return null;
  }
  const opened = Date.parse(pull?.createdAt);
  const closing = pull?.closingIssuesReferences;
  const issue =
    closing?.totalCount === 1 && closing.nodes?.length === 1 && String(closing.nodes[0]?.repository?.nameWithOwner).toLowerCase() === repo.toLowerCase()
      ? closing.nodes[0].number
      : null;
  for (const link of links) {
    const target = Number(link[3]);
    if (target !== number && target !== issue) {
      continue;
    }
    try {
      const comment = await github("GET", `/repos/${repo}/issues/comments/${link[4]}`);
      if (
        !String(comment?.issue_url ?? "").endsWith(`/issues/${target}`) ||
        comment.user?.type !== "User" ||
        comment.performed_via_github_app != null ||
        !humans.has(comment.user.id) ||
        !DECISION_LINE.test(String(comment.body ?? "").trimStart()) ||
        (target !== number && !(Date.parse(comment.created_at) > opened))
      ) {
        continue;
      }
      const node = (await github("POST", "/graphql", { query: COMMENT_EDITED_QUERY, variables: { id: String(comment.node_id) } }))?.data?.node;
      if (node && "lastEditedAt" in node && node.lastEditedAt === null) {
        return link[0];
      }
    } catch {
      // An unreadable comment clears nothing.
    }
  }
  return null;
}

// A GitHub REST and GraphQL reader on fetch, for costDecision.
const fetchGitHub = (env) => async (method, path, body) => {
  const response = await fetch(`${env.GITHUB_API_URL || "https://api.github.com"}${path}`, {
    method,
    headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GH_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = response.ok ? await response.json() : null;
  if (json === null || json.errors?.length) {
    throw new Error(`${method} ${path} failed with status ${response.status}`);
  }
  return json;
};

// The config's denied paths, or null unless a list of strings; pathHold adds
// the floor.
export function holdPathsOf(denied) {
  return Array.isArray(denied) && denied.every((glob) => typeof glob === "string") ? denied : null;
}

// The trusted people (numeric `humans` ids) whose newest deciding review of
// `head` among `items` approves it, sorted by login.
export function pathLifters(items, humans, head) {
  const newest = new Map();
  for (const item of items) {
    if (!item.isUser || !humans.has(item.userId) || item.commitId !== head) {
      continue;
    }
    if (!["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].includes(item.state)) {
      continue;
    }
    if (!newest.has(item.userId) || item.at >= newest.get(item.userId).at) {
      newest.set(item.userId, item);
    }
  }
  return [...newest.values()]
    .filter(({ state }) => state === "APPROVED")
    .map(({ login }) => login)
    .sort();
}

// Why the pull request's `body`, discussion `items` and changed `files` hold
// it; empty when nothing does. `lifters` approved the head, which lifts a hold
// path but not an unreadable file list or hold-path list, nor a cost path,
// which only the owner's `decision` lifts.
export function holds(body, items, files, holdPaths, lifters = [], decision = null) {
  const reasons = [];
  const pathReason = pathHold(files, holdPaths);
  const readable = Array.isArray(files) && Array.isArray(holdPaths);
  if (pathReason && !(readable && lifters.length)) {
    reasons.push(
      readable
        ? `${pathReason}; an approving review of this head by a person on the trusted-actor list lifts it, then re-run ci-status`
        : pathReason,
    );
  }
  const cost = costHold(files, decision);
  if (cost) {
    reasons.push(
      `${cost}; the owner's unedited comment opening '**Decision recorded.** Cost:' on this pull request or its closing issue, linked from the body, lifts it`,
    );
  }
  if (BODY_HOLD.test(String(body ?? ""))) {
    reasons.push("its body holds it (a line opening with 'Hold:', or 'do not merge'); removing that text lifts it");
  }
  const vetoes = vetoers(items);
  if (vetoes.length) {
    reasons.push(`${vetoes.join(", ")} asked not to merge it; a later comment by the same person lifts it, then re-run ci-status`);
  }
  return reasons;
}

// The verifier workflow (resolve-pr.mjs VERIFY_PATH).
export const VERIFY_PATH = ".github/workflows/pr-verify.yml";
const PASSES = Object.freeze(["pass", "pass-notes"]);

// Why the head has no verifier pass, or null when a record shows one: a pass
// or pass-notes artifact whose run is pr-verify.yml's, event workflow_run, on
// `branch` of `repo` with its head in `repo`, completed with success: the
// fields of babysit_verify_evidence `_origin` and a counted run, without its
// compare read that main holds the run's commit, since main's ruleset
// forbids the force push that could drop it. The records are
// read for the head alone, by exact name, so a record of another head never
// reaches here.
export function verdictHold(records, repo, branch = "main") {
  if (!Array.isArray(records) || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(String(repo))) {
    return "its pr-verify verdicts could not be read";
  }
  const pass = records.find(
    ({ verdict, runId, run } = {}) =>
      PASSES.includes(verdict) &&
      Number.isSafeInteger(runId) &&
      run?.id === runId &&
      run.path === VERIFY_PATH &&
      run.event === "workflow_run" &&
      run.head_branch === branch &&
      run.repository?.full_name === repo &&
      run.head_repository?.full_name === repo &&
      run.status === "completed" &&
      run.conclusion === "success",
  );
  return pass ? null : "pr-verify has not passed this head";
}

// A log line can carry a changed file's name: escape what would start a
// workflow command on a new line.
const escape = (text) => String(text).replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");

// The numeric ids of trusted-actors.json's people.
export const humansOf = (actors) =>
  new Set(actors.filter((actor) => actor?.kind === "human" && Number.isInteger(actor?.id)).map(({ id }) => id));

export async function main(argv = process.argv.slice(2), { env = process.env, github = fetchGitHub(env) } = {}) {
  const [number, bodyFile, discussionFile, filesFile, deniedFile, actorsFile, head, verdictsFile] = argv;
  try {
    if (
      !/^[1-9][0-9]*$/.test(String(number)) ||
      !bodyFile ||
      !discussionFile ||
      !filesFile ||
      !deniedFile ||
      !actorsFile ||
      !/^[0-9a-f]{40}$/.test(String(head))
    ) {
      throw new Error(
        "usage: merge-holds.mjs <number> <body-file> <discussion-file> <files-file> <denied-paths-file> <trusted-actors-file> <head-sha> [<verdicts-file>]",
      );
    }
    const lines = (file) => readFileSync(file, "utf8").split("\n").filter((line) => line.trim());
    const items = lines(discussionFile).map((line) => fromRest(JSON.parse(line)));
    const files = lines(filesFile).flatMap((line) => JSON.parse(line).map(String));
    const holdPaths = holdPathsOf(JSON.parse(readFileSync(deniedFile, "utf8")));
    const actors = JSON.parse(readFileSync(actorsFile, "utf8"))?.actors;
    if (!Array.isArray(actors)) {
      throw new Error("the trusted-actor list has no actors");
    }
    const humans = humansOf(actors);
    const lifters = pathLifters(items, humans, head);
    const body = readFileSync(bodyFile, "utf8");
    const repo = String(env.GITHUB_REPOSITORY);
    const decision =
      costHold(files, null) && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) ? await costDecision(github, repo, Number(number), body, humans) : null;
    if (decision) {
      console.log(`#${number}: ${decision} records the owner's cost decision, which lifts its cost hold.`);
    }
    const reasons = holds(body, items, files, holdPaths, lifters, decision);
    const held = pathHold(files, holdPaths);
    if (held && lifters.length && Array.isArray(holdPaths)) {
      console.log(`#${number}: ${lifters.join(", ")} approved this head, which lifts its hold path (${escape(held)}).`);
    }
    if (verdictsFile) {
      const unverified = verdictHold(lines(verdictsFile).map((line) => JSON.parse(line)), env.GITHUB_REPOSITORY);
      if (!unverified) {
        console.log(`#${number}: no verifier hold: pr-verify passed this head.`);
      } else if (lifters.length) {
        console.log(`#${number}: no verifier hold: ${lifters.join(", ")} approved this head, which lifts '${unverified}'.`);
      } else {
        reasons.push(
          `${unverified}; wait for pr-verify to pass it, after which enable-auto-merge arms it again, or an approving review of this head by a person on the trusted-actor list lifts it, then re-queue`,
        );
      }
    }
    for (const reason of reasons) {
      console.log(`::error::#${number}: ${escape(reason)}.`);
    }
    if (!reasons.length) {
      console.log(`#${number}: no body hold, no member veto and no hold path.`);
    }
    return reasons.length ? 1 : 0;
  } catch (error) {
    console.log(`::error::merge-holds: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
