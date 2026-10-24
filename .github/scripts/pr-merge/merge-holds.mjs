#!/usr/bin/env node
// merge-holds.mjs: the merge holds a pull request's own text carries, by the
// rules pr-merge's gate reads them. enable-auto-merge.mjs arms nothing they
// hold, and ci-status runs this file alone, fetched from the base commit, on
// every lanes App pull request, so it imports no other file of the repository.
//
// - A body hold (babysit_merge_policy.BODY_MERGE_HOLD_RE): a line opening with
//   `Hold:`, or "do not merge" anywhere, in a body a person wrote
//   (personWrote), or the lane's own hold line (LANE_HOLD, report-outcome's
//   HOLD_LINE for untrusted-provenance work, a person's `merge: human` and a
//   denied path) in any body. Other lanes App text holds nothing. Removing
//   that text lifts it.
// - A member veto (babysit_merge.human_veto_logins): each OWNER, MEMBER or
//   COLLABORATOR person's newest comment, review or inline comment with text
//   decides, and holds when it says "do not merge"
//   (babysit_merge.HUMAN_MERGE_VETO_RE). A later one by the same person
//   lifts it; an item with no text lifts nothing.
// - A hold path: a changed file, or a renamed file's old path, matching the
//   config's merge.diff-check.denied-paths. A person on the trusted-actor
//   list lifts it by approving the head: their newest review of the head that
//   approves, requests changes or was dismissed must approve. No path is held
//   for being trusted alone: the review lanes judge it.
// - A cost path (COST_PATHS): a changed file the gate holds for the owner's
//   cost decision. An approval does not lift it; only the decision the gate
//   reads does (costDecision), linked from the body: on the pull request, or
//   on its linked issue naming it, for the head it decided or a later one
//   whose every change since is a base merge.
// - No verifier pass, when a verdicts file is given (ci-status gives one in
//   the merge queue only): the head merges on a PASS or PASS-NOTES that
//   pr-verify.yml uploaded from a completed, successful run on main
//   (verdictHold). The same approval of the head lifts it, the human merge
//   path for a pull request pr-merge's gate sends to a person. FAILs and the
//   repeated-FAIL cap are enable-auto-merge.mjs's, through pr-merge's own
//   reader, which disarms such a pull request.
// - A changed issue link, when a link file is given with the verdicts: the
//   pass binds only while the live link is the one its verdict judged
//   (linkHold), as pr-merge's reader binds it (babysit_verify_evidence.py
//   `_pass_refusal`), so a body edited after arming to close or name another
//   issue does not merge on a pass for the old one. The same approval lifts it.
//
// Command line: merge-holds.mjs <number> <body-file> <discussion-file>
// <files-file> <denied-paths-file> <trusted-actors-file> <head-sha>
// [<verdicts-file> <link-file>]. The link file holds {record, closing}: the
// verdict.json of the pass verdictHold counts (null when none was read) and
// the pull request's closingIssuesReferences (totalCount, nodes with number
// and repository.nameWithOwner). The verdicts file holds one {name, verdict, runId, run}
// per line, run as GET actions/runs/{runId} gives it, for each unexpired artifact
// named a pass at the head; GITHUB_REPOSITORY names the repository. The
// discussion file holds one REST issue comment, review or review comment per
// line; the files file one changed file per line, its path, renamed-from
// path and status (changeOf); the denied-paths file the config's
// merge.diff-check.denied-paths as JSON; the trusted-actors file
// trusted-actors.json. Each hold prints as an ::error:: and exits 1; no hold
// exits 0. Who wrote a body that holds, and a cost path with a decision link
// in the body, are read with GH_TOKEN.
import { readFileSync } from "node:fs";
import { posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

// enable-auto-merge.test.mjs checks both agree with the gate's Python on every
// text it tries.
export const BODY_HOLD = /\bdo(?:n['’]?t| not)\s+merge\b|(?:^|\r)[^\S\r\n]*hold:/im;
export const HUMAN_VETO = /\bdo(?:n['’]?t| not|-not)[\s-]*merge\b/i;
// report-outcome.mjs HOLD_LINE on a line of its own, which
// enable-auto-merge.test.mjs checks; it holds whoever wrote the body.
export const LANE_HOLD = /(?:^|[\r\n])Hold: a human merges this[^\S\r\n]*(?:[\r\n]|$)/;
// Whether `body` holds: the lane's hold line, or hold text a person wrote.
export const bodyHolds = (body, byPerson) => LANE_HOLD.test(String(body ?? "")) || (byPerson && BODY_HOLD.test(String(body ?? "")));

// babysit_merge_policy.refs_issue, which test_verify_rules_sync.py keeps equal:
// the one issue the visible `Refs: #<n>` lines of a pull request body name,
// else null. A line counts only from its first column, outside an HTML comment
// and a fenced code block; a `Refs:` line in any other form, or two numbers,
// name none.
const HTML_COMMENT = /<!--[\s\S]*?(?:-->|$)/g;
const FENCE = /^ {0,3}(`{3,}|~{3,})/;
const REFS_LINE = /^[Rr][Ee][Ff][Ss]:/;
const REFS_PLAIN = /^Refs:[ \t]*#([1-9][0-9]{0,8})[ \t]*$/;
export function refsIssue(body) {
  const numbers = new Set();
  let fence = "";
  for (const line of String(body ?? "").replace(HTML_COMMENT, "").split(/\r\n|\r|\n/)) {
    const marker = FENCE.exec(line);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && line.slice(marker[0].length).replace(/[ \t]/g, "") === "") {
        fence = "";
      }
      continue;
    }
    if (marker) {
      fence = marker[1];
      continue;
    }
    if (!REFS_LINE.test(line)) {
      continue;
    }
    const plain = REFS_PLAIN.exec(line);
    if (!plain) {
      return null;
    }
    numbers.add(Number(plain[1]));
  }
  return numbers.size === 1 ? [...numbers][0] : null;
}

// Why the pass `record` (its verdict.json) does not bind the pull request's
// live link, or null when it does. The live link is its closing issues in
// `repo`, or, with no closing issue at all, the one issue its plain `Refs:`
// lines name (refsIssue). The pass binds unless the live link names an issue
// and drops the one it judged, or names only that issue linked another way
// (its `spec_kind`, `closes` when absent, as the reader reads an older
// record). A link of no issue, or of more than one, holds nothing here: the
// fix loop rewrites it.
export function linkHold(record, body, closing, repo) {
  if (record === null || typeof record !== "object" || !Array.isArray(record.linked_issues)) {
    return "its verifier pass's record could not be read";
  }
  const kind = record.spec_kind ?? "closes";
  if (!["closes", "refs"].includes(kind)) {
    return `its verifier pass judged a spec of kind '${String(kind)}', not a linked issue`;
  }
  if (!Array.isArray(closing?.nodes) || !Number.isSafeInteger(closing.totalCount) || closing.totalCount !== closing.nodes.length) {
    return "its closing issues could not be read";
  }
  const own = (issue) => String(issue?.repository?.nameWithOwner).toLowerCase() === String(repo).toLowerCase();
  const linked = closing.totalCount > 0 ? "closes" : "refs";
  const refs = linked === "refs" ? refsIssue(body) : null;
  const live = linked === "closes" ? closing.nodes.filter(own).map((issue) => issue.number) : refs === null ? [] : [refs];
  const judged = record.linked_issues.map((issue) => issue?.number);
  const [only] = judged;
  if (judged.length !== 1 || (live.length > 0 && !live.includes(only)) || (live.length === 1 && kind !== linked)) {
    return `its link changed since pr-verify passed it: it ${linked} ${live.map((n) => `#${n}`).join(", ") || "no issue"}, and the pass judged ${judged.map((n) => `#${n}`).join(", ") || "no issue"} (${kind})`;
  }
  return null;
}
// babysit_merge_policy.BLOCKER_ASSOCIATIONS.
const MEMBERS = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);

// The pull request's author and the editors of its body, for personWrote.
export const BODY_WRITERS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { author { __typename } userContentEdits(first: 100) { totalCount nodes { editor { __typename } } } }
  }
}`;

// Whether a person wrote any of the body of `pull` (BODY_WRITERS_QUERY's
// pullRequest, or a listing's with the same fields): its author or an editor
// of its body is not a Bot account. A deleted account, an edit list not read
// whole or a pull request that did not read counts as a person, so a hold an
// unknown hand wrote still holds.
export function personWrote(pull) {
  const edits = pull?.userContentEdits;
  if (!pull?.author || !Array.isArray(edits?.nodes) || !(edits.totalCount <= edits.nodes.length)) {
    return true;
  }
  return [pull.author, ...edits.nodes.map((edit) => edit?.editor)].some((who) => who?.__typename !== "Bot");
}

// babysit_risk.COST_PATHS, matched case-folded as its glob_match does;
// test_merge_holds_sync.py checks the two agree. Each one is a real charge.
export const COST_PATHS = Object.freeze([
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

// Whether `path` matches the hold-path `glob`, case-folded as glob_match
// folds it: a lane host on a case-insensitive filesystem reads `.github/codeowners`
// as CODEOWNERS. path.matchesGlob has no `dot` option, so `*` and `**` skip a
// segment opening with "."; both sides mark such a segment alike first, so
// `.github/**` holds `.github/a/.x` too.
const undot = (text) => String(text).toLowerCase().replaceAll(/(^|\/)\./g, "$1\u0001");
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
  const held = files.find((path) => holdPaths.some((glob) => matchesHoldPath(path, glob)));
  return held === undefined ? null : `it changes ${held}, a hold path`;
}

// Why the changed `files` hold it for the owner's cost decision, or null when
// none is a cost path or `decision` (costDecision's link) clears it. As
// glob_match does, a glob also covers everything under it, and `*` matches a
// segment's leading "." (so `*.tf` holds `.tf`).
export function costHold(files, decision) {
  const held = (Array.isArray(files) ? files : []).find((path) => {
    const folded = String(path).toLowerCase().replaceAll(/(^|\/)\./g, "$1\u0001.");
    return COST_PATHS.some((glob) => [glob, `${glob}/**`].some((each) => posix.matchesGlob(folded, each.toLowerCase())));
  });
  return held === undefined || decision ? null : `it changes ${held}, a cost path`;
}

// babysit_merge_policy COST_DECISION_LINK, DECISION_LINE and HTML_COMMENT.
const DECISION_LINK = /https:\/\/github\.com\/([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)\/(?:issues|pull)\/([0-9]+)#issuecomment-([0-9]+)/g;
const DECISION_LINE = /^\*\*Decision recorded\.\*\*[ \t]+Cost:/;
export const PULL_OPENED_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { createdAt baseRefName closingIssuesReferences(first: 2) { totalCount nodes { number repository { nameWithOwner } } } }
  }
}`;
export const COMMENT_EDITED_QUERY = "query($id: ID!) { node(id: $id) { ... on IssueComment { lastEditedAt } } }";
export const COMMENT_DELETED_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { timelineItems(itemTypes: [COMMENT_DELETED_EVENT], last: 100) { filteredCount nodes { ... on CommentDeletedEvent { createdAt } } } }
  }
}`;

// Whether `text` names pull request `number` as `#<number>`: not part of a
// longer number, and not after a letter, digit, `_`, `#`, `&`, `/`, `.` or
// `-`, so neither `owner/repo#<number>` nor `&#<number>` counts
// (babysit_merge_policy.names_pull; the review lanes' hold step excludes the
// same characters but `.` and `-`).
export function namesPull(text, number) {
  return Number.isSafeInteger(number) && new RegExp(`(?:^|[^A-Za-z0-9_#&/.-])#${number}(?:[^0-9]|$)`).test(String(text ?? ""));
}

// A review lane's cost hold marker, as ci-workflows apply-review-hold writes
// it on the first line of its hold comment: the head it held and its
// criteria. The base branch name a compare takes, as the hold step reads it.
const COST_MARKER = /^<!-- claude-lane-hold lane=[a-z-]+ sha=([0-9a-f]{40}) criteria=([a-z,-]+) -->(?:\n|$)/;
const BRANCH = /^(?!-)(?!.*\.\.)[A-Za-z0-9._/-]{1,255}$/;

// The newest cost hold marker github-actions[bot] posted among the pull
// request's `comments` before a decision made at `at`, as { sha, node, at }
// (the head it held, its comment's node id and created_at), else null
// (babysit_merge_policy.cost_marker; the first of two at one time wins, as
// in the review lanes' hold step). It decides a head only while never
// edited and while no comment was deleted since it was posted, which the
// caller reads.
export function costMarker(comments, at) {
  const cutoff = Date.parse(at);
  let found = null;
  let latest = -Infinity;
  for (const row of Array.isArray(comments) ? comments : []) {
    const marker = row?.user?.login === "github-actions[bot]" ? COST_MARKER.exec(String(row.body ?? "")) : null;
    const made = Date.parse(row?.created_at);
    if (marker && marker[2].split(",").includes("cost") && made < cutoff && made > latest) {
      found = { sha: marker[1], node: String(row.node_id ?? ""), at: row.created_at };
      latest = made;
    }
  }
  return found;
}

// Whether a COMMENT_DELETED_QUERY answer (its `data`) shows a comment on the
// pull request deleted at or after `at`, or cannot show that none was: no
// readable list, more deletions than it lists, or a time that does not parse
// (babysit_merge_policy.deleted_since). A deleted newer marker would
// otherwise make an older one the decided head.
export function deletedSince(answer, at) {
  const when = Date.parse(at);
  const items = answer?.repository?.pullRequest?.timelineItems;
  const nodes = items?.nodes;
  if (!Number.isFinite(when) || !Array.isArray(nodes) || !Number.isInteger(items.filteredCount) || items.filteredCount > nodes.length) {
    return true;
  }
  return nodes.some((node) => {
    const made = Date.parse(node?.createdAt);
    return !Number.isFinite(made) || made >= when;
  });
}

// Whether a COMMENT_EDITED_QUERY answer's node was never edited.
const unedited = (node) => Boolean(node) && "lastEditedAt" in node && node.lastEditedAt === null;

// Whether two compare answers (base...head) show the same net change of the
// pull request: the same filenames, each with the same status,
// previous_filename and patch. A list of 300 files or more (the compare
// API's cap), a file with no patch, a filename listed twice, or an answer
// with no file list is not the same (babysit_merge_policy.same_net_change).
export function sameNetChange(decided, current) {
  const net = (compare) => {
    const files = compare?.files;
    if (!Array.isArray(files) || files.length >= 300) return null;
    const byName = new Map();
    for (const f of files) {
      if (typeof f?.filename !== "string" || typeof f.patch !== "string" || byName.has(f.filename)) return null;
      byName.set(f.filename, JSON.stringify([f.status ?? null, f.previous_filename ?? null, f.patch]));
    }
    return byName;
  };
  const [then, now] = [net(decided), net(current)];
  return then !== null && now !== null && then.size === now.size && [...then].every(([name, value]) => now.get(name) === value);
}

// Every page of the REST list at `path`.
async function pages(github, path) {
  const rows = [];
  for (let page = 1; ; page += 1) {
    const read = await github("GET", `${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${page}`);
    if (!Array.isArray(read)) {
      throw new Error(`${path} is not a list`);
    }
    rows.push(...read);
    if (read.length < 100) {
      return rows;
    }
  }
}

// Whether the decision `comment` covers pull request `number` at `head`
// (owner decisions Q17 c and Q18 d on #9436): its decided head (costMarker,
// never edited, so no one with write access moved its sha) is `head`, with
// no compare read, or every change since is a merge of the base branch
// `base`, so the net change against it is the same at both (sameNetChange).
// No marker, an edited or unreadable newest marker (no older one stands in),
// a comment deleted since that marker was posted (deletedSince, read before
// the head check, so deleting a newer marker cannot promote an older head),
// an unusable base name or a read that fails carries nothing.
async function carries(github, repo, number, comment, head, base) {
  try {
    const marker = costMarker(await pages(github, `/repos/${repo}/issues/${number}/comments`), comment.created_at);
    if (marker === null) {
      return false;
    }
    const node = (await github("POST", "/graphql", { query: COMMENT_EDITED_QUERY, variables: { id: marker.node } }))?.data?.node;
    if (!unedited(node)) {
      return false;
    }
    const [owner, name] = repo.split("/");
    const deleted = await github("POST", "/graphql", { query: COMMENT_DELETED_QUERY, variables: { owner, name, number } });
    if (deletedSince(deleted?.data, marker.at)) {
      return false;
    }
    const decided = marker.sha;
    if (decided === head) {
      return true;
    }
    if (typeof base !== "string" || !BRANCH.test(base)) {
      return false;
    }
    const then = await github("GET", `/repos/${repo}/compare/${base}...${decided}`);
    const now = await github("GET", `/repos/${repo}/compare/${base}...${head}`);
    return sameNetChange(then, now);
  } catch {
    return false;
  }
}

// The comment link in `body`, outside HTML comments, that records the
// owner's cost decision for pull request `number` of `repo` at `head`, else
// null: the rule of babysit_merge_policy.cost_decision, with the owner a
// person whose id is in `humans` (trusted-actors.json), as ci-status's
// cost-only review hold step names one. The comment is on the pull request,
// or on its linked issue in `repo` (the one closing issue, else with none the
// one refsIssue names, read to be an issue and not a pull request), newer
// than the pull request and naming it (namesPull); by a User, not through an
// App; never edited; its first line `**Decision recorded.** Cost:`. Of
// those, the decision is the newest on the pull request, else the newest on
// the issue, as the review lanes' hold step picks it; it covers the head it
// decided and a later one only when every change since is a base merge
// (carries, against the pull request's base branch). `github(method, path,
// body)` reads; a failed read of the pull request or the Refs target decides
// nothing, and one of a comment or its edit state skips that comment.
export async function costDecision(github, repo, number, body, humans, head) {
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
  const refs = closing?.totalCount === 0 ? refsIssue(body) : null;
  let issue =
    refs ??
    (closing?.totalCount === 1 && closing.nodes?.length === 1 && String(closing.nodes[0]?.repository?.nameWithOwner).toLowerCase() === repo.toLowerCase()
      ? closing.nodes[0].number
      : null);
  let checked = refs === null;
  const decisions = [];
  for (const link of links) {
    const target = Number(link[3]);
    if (target !== number && target !== issue) {
      continue;
    }
    if (target !== number && !checked) {
      // A Refs number may name a pull request; only an issue is consulted.
      try {
        const read = await github("GET", `/repos/${repo}/issues/${refs}`);
        issue = read?.number === refs && read.pull_request == null ? refs : null;
      } catch {
        return null;
      }
      checked = true;
      if (issue === null) {
        continue;
      }
    }
    try {
      const comment = await github("GET", `/repos/${repo}/issues/comments/${link[4]}`);
      if (
        !String(comment?.issue_url ?? "").endsWith(`/issues/${target}`) ||
        comment.user?.type !== "User" ||
        comment.performed_via_github_app != null ||
        !humans.has(comment.user.id) ||
        !DECISION_LINE.test(String(comment.body ?? "").trimStart()) ||
        (target !== number && !(Date.parse(comment.created_at) > opened && namesPull(comment.body, number)))
      ) {
        continue;
      }
      const node = (await github("POST", "/graphql", { query: COMMENT_EDITED_QUERY, variables: { id: String(comment.node_id) } }))?.data?.node;
      if (unedited(node)) {
        decisions.push({ link: link[0], comment, own: target === number });
      }
    } catch {
      // An unreadable comment clears nothing.
    }
  }
  const at = (d) => {
    const made = Date.parse(d.comment.created_at);
    return Number.isNaN(made) ? -Infinity : made;
  };
  // The newest; of two at one time, the first linked.
  const newest = (own) => decisions.filter((d) => d.own === own).reduce((best, d) => (best === undefined || at(d) > at(best) ? d : best), undefined);
  const decision = newest(true) ?? newest(false);
  return decision && (await carries(github, repo, number, decision.comment, head, pull?.baseRefName)) ? decision.link : null;
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

// The config's denied paths, or null unless a list of strings.
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
// it; empty when nothing does. `lifters` approved the head, which lifts a
// hold path but not an unreadable file list or hold-path list, nor a cost
// path, which only the owner's `decision` lifts. `byPerson` (personWrote)
// says whether the body can hold.
export function holds(body, items, files, holdPaths, lifters = [], decision = null, byPerson = true) {
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
      `${cost}; the owner's unedited comment opening '**Decision recorded.** Cost:' on this pull request, or on its linked issue naming this pull request, linked from the body, lifts it for the head it decided and a later head that only merges the base`,
    );
  }
  if (bodyHolds(body, byPerson)) {
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

// The link file's verdict, a file that does not read included.
function linkOf(file, body, repo) {
  try {
    const { record, closing } = JSON.parse(readFileSync(file, "utf8"));
    return linkHold(record, body, closing, repo);
  } catch {
    return "its issue link could not be checked against its verifier pass";
  }
}

// One files-file line as { path, previous, status }: [filename,
// previous_filename or null, status] from the pull request files API, or an
// object of those keys. An older line of one path and any renamed-from path
// has no status. A module older than this one reads every entry of a line as
// a path, null and the status matching no hold path.
export function changeOf(line) {
  if (Array.isArray(line)) {
    const [path, previous = null, status = null] = line;
    return {
      path: String(path),
      previous: previous === null ? null : String(previous),
      status: line.length === 3 && typeof status === "string" ? status : null,
    };
  }
  if (line === null || typeof line !== "object" || typeof line.filename !== "string") {
    throw new Error("a changed file does not read");
  }
  const previous = line.previous_filename;
  return { path: line.filename, previous: typeof previous === "string" && previous ? previous : null, status: typeof line.status === "string" ? line.status : null };
}

// Whether a person wrote the body of pull request `number` (personWrote); a
// read that fails counts as a person.
async function bodyByPerson(github, repo, number) {
  const [owner, name] = repo.split("/");
  try {
    return personWrote((await github("POST", "/graphql", { query: BODY_WRITERS_QUERY, variables: { owner, name, number } }))?.data?.repository?.pullRequest);
  } catch {
    return true;
  }
}

export async function main(argv = process.argv.slice(2), { env = process.env, github = fetchGitHub(env) } = {}) {
  const [number, bodyFile, discussionFile, filesFile, deniedFile, actorsFile, head, verdictsFile, linkFile] = argv;
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
        "usage: merge-holds.mjs <number> <body-file> <discussion-file> <files-file> <denied-paths-file> <trusted-actors-file> <head-sha> [<verdicts-file> <link-file>]",
      );
    }
    const lines = (file) => readFileSync(file, "utf8").split("\n").filter((line) => line.trim());
    const items = lines(discussionFile).map((line) => fromRest(JSON.parse(line)));
    const changes = lines(filesFile).map((line) => changeOf(JSON.parse(line)));
    const files = changes.flatMap(({ path, previous }) => [path, ...(previous === null ? [] : [previous])]);
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
      costHold(files, null) && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) ? await costDecision(github, repo, Number(number), body, humans, head) : null;
    if (decision) {
      console.log(`#${number}: ${decision} records the owner's cost decision, which lifts its cost hold.`);
    }
    const byPerson = BODY_HOLD.test(body) && !LANE_HOLD.test(body) && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) ? await bodyByPerson(github, repo, Number(number)) : true;
    if (!byPerson) {
      console.log(`#${number}: its body's hold text is the lanes App's own, which holds nothing.`);
    }
    const reasons = holds(body, items, files, holdPaths, lifters, decision, byPerson);
    const held = pathHold(files, holdPaths);
    if (held && lifters.length && Array.isArray(holdPaths)) {
      console.log(`#${number}: ${lifters.join(", ")} approved this head, which lifts its hold path (${escape(held)}).`);
    }
    if (verdictsFile) {
      const unverified = verdictHold(lines(verdictsFile).map((line) => JSON.parse(line)), env.GITHUB_REPOSITORY);
      // An approval lifts the verifier hold whole, the link with it.
      const relinked = unverified || lifters.length ? null : linkFile ? linkOf(linkFile, body, repo) : "its issue link could not be checked against its verifier pass";
      if (!unverified && !relinked) {
        console.log(`#${number}: no verifier hold: pr-verify passed this head.`);
      } else if (!unverified && lifters.length === 0) {
        // pr-verify skips a head it already passed (resolve-pr.mjs `judged`),
        // so only a new head or an approval recovers it.
        reasons.push(`${relinked}; pr-verify does not judge this head again, so push a new head for it to judge, after which enable-auto-merge arms it again, or an approving review of this head by a person on the trusted-actor list lifts it, then re-queue`);
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
