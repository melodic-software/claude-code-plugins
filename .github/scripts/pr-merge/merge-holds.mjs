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
//   config's merge.diff-check.denied-paths or HOLD_PATH_FLOOR. A person on
//   the trusted-actor list lifts it by approving the head: their newest
//   review of the head that approves, requests changes or was dismissed must
//   approve. No other path is held for being trusted alone: the review lanes
//   judge it.
// - A trusted-actor list widening (actorsHold, the rule of
//   babysit_risk._actors_widened): TRUSTED_ACTORS_PATH read at the base commit
//   (BASE_SHA) and the head and compared; only removing entries passes. The
//   approval of the head that lifts a hold path lifts it.
// - A cost path (COST_PATHS): a changed file the gate holds for the owner's
//   cost decision. An approval does not lift it; only the decision the gate
//   reads does (costDecision), linked from the body: on the pull request, or
//   on its linked issue naming it, for the head it decided or a later one
//   whose every change since is a base merge.
// - No verifier pass, when a verdicts file is given (ci-status gives one in
//   the merge queue only): the head merges on a PASS or PASS-NOTES that
//   pr-verify.yml uploaded from a completed, successful run on main
//   (verdictHold). The same approval of the head lifts it, the human merge
//   path for a pull request pr-merge's gate sends to a person.
// - A FAIL the gate's reader counts, when an evidence file is given with the
//   verdicts: babysit_verify_evidence.py `evidence`'s report for the head,
//   which ci-status runs from main's checkout in the merge queue
//   (evidenceHold). It holds on every refusal but the three a pass decides
//   (verify:missing, verify:spec-changed, verify:untrusted-spec, which
//   verdictHold and linkHold judge here): the FAIL classes, verify:unreadable,
//   verify:too-old and any refusal this module does not know. A report that
//   does not read, or is for another head, holds. The same approval lifts it.
// - A changed issue link, when a link file is given with the verdicts: the
//   pass binds only while the live link is the one its verdict judged
//   (linkHold), as pr-merge's reader binds it (babysit_verify_evidence.py
//   `_pass_refusal`), so a body edited after arming to close or name another
//   issue does not merge on a pass for the old one. The same approval lifts it.
//
// Command line: merge-holds.mjs <number> <body-file> <discussion-file>
// <files-file> <denied-paths-file> <trusted-actors-file> <head-sha>
// [<verdicts-file> <link-file> [<evidence-file>]]. The link file holds {record, closing}: the
// verdict.json of the pass verdictHold counts (null when none was read) and
// the pull request's closingIssuesReferences (totalCount, nodes with number
// and repository.nameWithOwner). The verdicts file holds one {name, verdict, runId, run}
// per line, run as GET actions/runs/{runId} gives it, for each unexpired artifact
// named a pass at the head; GITHUB_REPOSITORY names the repository. The
// evidence file holds the reader's one JSON line (Evidence.report); with
// verdicts and no evidence file, the FAIL check holds as unreadable. The
// discussion file holds one REST issue comment, review or review comment per
// line; the files file one changed file per line, its path, renamed-from
// path and status (changeOf); the denied-paths file the config's
// merge.diff-check.denied-paths as JSON; the trusted-actors file
// trusted-actors.json. Each hold prints as an ::error:: and exits 1; no hold
// exits 0. Who wrote a body that holds, a changed trusted-actor list, and a
// cost path with a decision link in the body, are read with GH_TOKEN.
import { Buffer } from "node:buffer";
import { readFileSync } from "node:fs";
import { posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

// enable-auto-merge.test.mjs checks both agree with the gate's Python on every
// text it tries.
export const BODY_HOLD = /\bdo(?:n['’]?t| not)\s+merge\b|(?:^|\r)[^\S\r\n]*hold:/im;
export const HUMAN_VETO = /\bdo(?:n['’]?t| not|-not)[\s-]*merge\b/i;
// The lanes App's bot login. A `Hold:` line on its own pull request holds the
// merge, not a fix pushed to it (apply-patch.mjs's held()).
export const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";
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
  const numbers = refsNumbers(body);
  return numbers?.size === 1 ? [...numbers][0] : null;
}

// The issues the visible plain `Refs: #<n>` lines of `body` name, as
// refsIssue reads them, or null when such a line is in any other form.
function refsNumbers(body) {
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
  return numbers;
}

// Why the pass `record` (its verdict.json) does not bind the pull request's
// live link, or null when it does. The live link is its closing issues in
// `repo`, or, with no closing issue at all, the one issue its plain `Refs:`
// lines name (refsNumbers). The pass binds unless the live link drops the
// issue it judged (a link removed, or closing issues all in another
// repository, drop it), or names that issue linked another way (its
// `spec_kind`, `closes` when absent, as the reader reads an older record). A
// link of several issues that still names the judged one binds: the fix loop
// rewrites it.
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
  const live = linked === "closes" ? closing.nodes.filter(own).map((issue) => issue.number) : [...(refsNumbers(body) ?? [])];
  const judged = record.linked_issues.map((issue) => issue?.number);
  const [only] = judged;
  if (judged.length !== 1 || !live.includes(only) || kind !== linked) {
    const named = linked === "closes" ? closing.nodes.map((issue) => `${own(issue) ? "" : issue?.repository?.nameWithOwner}#${issue?.number}`) : live.map((n) => `#${n}`);
    return `its link changed since pr-verify passed it: it ${linked} ${named.join(", ") || "no issue"}, and the pass judged ${judged.map((n) => `#${n}`).join(", ") || "no issue"} (${kind})`;
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

// The narrow floor every hold path check adds to the configured globs (owner
// decision Q-FLOOR (B)): the code main runs to mint and scope lane tokens
// and judge triggers (resolve-config, request-lane-token,
// check-trusted-trigger, check-kill-switch, the rate guard), code owners and
// submodules; and the files that enforce the floor (owner decision
// Q-ENFORCE (A)): this module, enable-auto-merge, superseded,
// clear-escalations, babysit_risk.py, the ci-status workflow, the pr-merge
// workflow that wires them, the pipeline config, every module those scripts
// import, and the babysit-prs modules
// babysit_risk.py and the Python those scripts run (babysit_verify_evidence.py)
// import (test_merge_holds_sync.py derives both closures and requires them
// here). babysit_risk.HIGH_FLOOR, which
// test_merge_holds_sync.py checks this equals. A constant of the module
// ci-status and enable-auto-merge run from the base commit, so a pull
// request cannot rewrite it.
export const HOLD_PATH_FLOOR = Object.freeze([
  ".github/actions/check-trusted-trigger/**",
  "**/CODEOWNERS",
  "**/.gitmodules",
  ".github/actions/resolve-config/**",
  ".github/actions/check-kill-switch/**",
  ".github/actions/request-lane-token/**",
  ".github/actions/log-api-budget/rate-guard.mjs",
  ".github/actions/log-api-budget/rate-limits.json",
  ".github/scripts/pr-merge/merge-holds.mjs",
  ".github/scripts/pr-merge/enable-auto-merge.mjs",
  ".github/scripts/pr-merge/superseded.mjs",
  ".github/scripts/pr-merge/clear-escalations.mjs",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_check_inputs.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_checks.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_classify.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_dependabot.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_feedback.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_repo_config.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_review_trigger.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_run_cache.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_state.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_util.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_whole_review.py",
  ".github/workflows/pr-require-checks.yml",
  ".github/workflows/pr-merge.yml",
  "docs/conventions/pr-pipeline.yaml",
  ".github/scripts/pr-unblock/address-feedback.mjs",
  ".github/scripts/pr-unblock/gate-source.mjs",
  ".github/scripts/pr-unblock/thread-scope.mjs",
  ".github/scripts/work-resolve-issue/report-outcome.mjs",
  ".github/scripts/work-resolve-issue/limits.mjs",
]);

// Why the head's changed `files` hold it, or null: one matching `holdPaths`
// or HOLD_PATH_FLOOR. Null `holdPaths` or `files` (unreadable) holds it.
export const pathHold = (files, holdPaths) => pathHoldKind(files, holdPaths)?.reason ?? null;

// pathHold's answer with its kind: `hold-path` for a changed file a hold
// path matches, `unread` for a list that could not be read or checked.
export function pathHoldKind(files, holdPaths) {
  if (!Array.isArray(holdPaths)) {
    return { kind: "unread", reason: "the hold paths could not be read" };
  }
  if (!Array.isArray(files)) {
    return { kind: "unread", reason: "its changed files could not all be read" };
  }
  if (typeof posix.matchesGlob !== "function") {
    return { kind: "unread", reason: "this Node has no path.matchesGlob, so its hold paths cannot be checked" };
  }
  const globs = [...holdPaths, ...HOLD_PATH_FLOOR];
  const held = files.find((path) => globs.some((glob) => matchesHoldPath(path, glob)));
  return held === undefined ? null : { kind: "hold-path", reason: `it changes ${held}, a hold path` };
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

// babysit_risk._manifest: the parsed object as a node tree, or null when the
// text is not a string, not JSON, not an object, or repeats a key. A node is
// { object: Map }, { array: [] } or { text }, a scalar's text telling values
// apart as Python's json.loads does: an integer and a float differ (1 and
// 1.0), so canonical (json.dumps with sort_keys) compares them as the gate.
function parseStrict(text) {
  if (typeof text !== "string") {
    return null;
  }
  try {
    JSON.parse(text);
  } catch {
    return null;
  }
  // The text is valid JSON, so the walk below needs no error handling.
  let at = 0;
  const space = () => {
    while (" \t\n\r".includes(text[at] ?? "x")) at += 1;
  };
  const string = () => {
    const start = at;
    for (at += 1; text[at] !== '"'; at += 1) {
      if (text[at] === "\\") at += 1;
    }
    at += 1;
    return JSON.parse(text.slice(start, at));
  };
  const items = (close, read) => {
    at += 1;
    for (space(); text[at] !== close; space()) {
      read();
      space();
      if (text[at] === ",") at += 1;
    }
    at += 1;
  };
  const value = () => {
    space();
    if (text[at] === "{") {
      const object = new Map();
      items("}", () => {
        const key = string();
        if (object.has(key)) throw new Error("duplicate key");
        space();
        at += 1;
        object.set(key, value());
      });
      return { object };
    }
    if (text[at] === "[") {
      const array = [];
      items("]", () => array.push(value()));
      return { array };
    }
    if (text[at] === '"') return { text: JSON.stringify(string()), string: true };
    const token = /^(?:true|false|null|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(text.slice(at))[0];
    at += token.length;
    if (!/^-?\d/.test(token)) return { text: token };
    if (!/[.eE]/.test(token)) {
      // json.loads refuses an integer past int_max_str_digits (4300), so the
      // gate reads that side as malformed.
      if (token.replace("-", "").length > 4300) throw new Error("integer too long");
      return { text: `${BigInt(token)}` };
    }
    const number = Number(token);
    return { text: `${Object.is(number, -0) ? "-0" : String(number)}.f` };
  };
  try {
    const root = value();
    return root.object ? root : null;
  } catch {
    return null;
  }
}

const canonical = (node) =>
  node.object
    ? `{${[...node.object]
        .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
        .map(([key, child]) => `${JSON.stringify(key)}:${canonical(child)}`)
        .join(",")}}`
    : node.array
      ? `[${node.array.map(canonical).join(",")}]`
      : node.text;
// babysit_risk.TRUSTED_ACTORS_PATH, matched case-folded as glob_match does.
export const TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json";

// babysit_risk._actors_widened: why one change of the trusted-actor list
// widens trust, or null when it only removes entries; test_merge_holds_sync.py
// checks the two agree. `change` is { status, previous, contents }, contents
// [base text, head text]. Anything but a file modified in place, a side that
// does not read or parse or repeats a key, an `actors` that is no list, or a
// change to any other key holds, and so does an entry added or changed.
export function actorsWidened({ status, previous = null, contents } = {}) {
  if (status !== "modified" || previous !== null) {
    return `${status ?? "unknown"} trusted-actor list`;
  }
  if (!Array.isArray(contents) || contents.length !== 2) {
    return "contents unreadable";
  }
  const [base, head] = contents.map(parseStrict);
  if (base === null || head === null) {
    return "unreadable, malformed or a repeated key";
  }
  const [old, now] = [base, head].map((node) => node.object.get("actors"));
  if (!old?.array || !now?.array) {
    return "actors is not a list";
  }
  const rest = (node) => canonical({ object: new Map([...node.object].filter(([key]) => key !== "actors")) });
  if (rest(base) !== rest(head)) {
    return "a key other than actors changed";
  }
  const gained = new Map();
  for (const [entries, step] of [[now.array, 1], [old.array, -1]]) {
    for (const entry of entries) {
      const key = canonical(entry);
      gained.set(key, (gained.get(key) ?? 0) + step);
    }
  }
  const added = [...gained].filter(([, n]) => n > 0).map(([key]) => key).sort();
  return added.length ? `entries added or changed: ${added.join(", ")}` : null;
}

// Why the changes (changeOf's, with withActorContents's contents) widen the
// trusted-actor list, or null. A change whose path or renamed-from path is the
// list counts.
export function actorsHold(changes) {
  if (!Array.isArray(changes)) {
    return "its changed files could not all be read";
  }
  const found = changes
    .filter(({ path, previous }) => [path, previous].some((each) => each != null && matchesHoldPath(each, TRUSTED_ACTORS_PATH)))
    .map((change) => [change.path, actorsWidened(change)])
    .filter(([, why]) => why);
  return found.length ? `it widens the trusted-actor list (${found.map(([path, why]) => `${path}: ${why}`).join("; ")})` : null;
}

// `changes` with the trusted-actor list's [base text at `base`, head text at
// `head`] on a change that modifies it in place; a read that fails, or a base
// that is not a commit SHA, leaves its contents out, so it holds.
export async function withActorContents(github, repo, changes, base, head) {
  const text = async (path, ref) => {
    const file = await github("GET", `/repos/${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${ref}`);
    if (file?.type !== "file" || file.encoding !== "base64" || typeof file.content !== "string") {
      throw new Error(`${path} at ${ref} did not read`);
    }
    // Strict, as the gate's decode("utf-8"): invalid UTF-8 throws, so it
    // holds, and a BOM stays, so the parse refuses it as json.loads does.
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(Buffer.from(file.content, "base64"));
  };
  return Promise.all(
    changes.map(async (change) => {
      if (!matchesHoldPath(change.path, TRUSTED_ACTORS_PATH) || change.status !== "modified" || change.previous !== null || !/^[0-9a-f]{40}$/.test(String(base))) {
        return change;
      }
      try {
        return { ...change, contents: [await text(change.path, base), await text(change.path, head)] };
      } catch {
        return change;
      }
    }),
  );
}

// babysit_merge_policy COST_DECISION_LINK, DECISION_LINE and HTML_COMMENT.
const DECISION_LINK = /https:\/\/github\.com\/([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)\/(?:issues|pull)\/([0-9]+)#issuecomment-([0-9]+)/g;
const DECISION_LINE = /^\*\*Decision recorded\.\*\*[ \t]+Cost:/;
export const PULL_OPENED_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { createdAt baseRefName headRefName closingIssuesReferences(first: 2) { totalCount nodes { number repository { nameWithOwner } } } }
  }
}`;
export const COMMENT_EDITED_QUERY = "query($id: ID!) { node(id: $id) { ... on IssueComment { lastEditedAt } } }";

// Whether `text` names pull request `number` as `#<number>`: not part of a
// longer number, and not after a letter, digit, `_`, `#`, `&`, `/`, `.` or
// `-`, so neither `owner/repo#<number>` nor `&#<number>` counts
// (babysit_merge_policy.names_pull; the review lanes' hold step excludes the
// same characters but `.` and `-`).
export function namesPull(text, number) {
  return Number.isSafeInteger(number) && new RegExp(`(?:^|[^A-Za-z0-9_#&/.-])#${number}(?:[^0-9]|$)`).test(String(text ?? ""));
}

// The review lanes whose status job records a `claude-lane-hold` notice, as
// [workflow file, status job name] (ci-status's cost-hold step reads the same
// two). The notice's head and criteria, and the base branch name a compare
// takes, as the hold step reads it.
export const REVIEW_LANES = [
  ["pr-review-hosted.yml", "pr-review / claude-review-status"],
  ["pr-review-security-hosted.yml", "pr-review-security / security-review"],
];
const HOLD_NOTICE = /^claude-lane-hold lane=[a-z-]+ sha=([0-9a-f]{40}) criteria=([a-z,-]+) label=/;
const BRANCH = /^(?!-)(?!.*\.\.)[A-Za-z0-9._/-]{1,255}$/;

// Why a compare answer (base...head) shows a head whose lane runs cannot be
// trusted, else null: it changes a review-lane workflow, which a
// pull_request run takes from the head and so could write the notice, or it
// lists 300 files or more (the compare API's cap), or no file list.
export function laneChange(compare) {
  const files = compare?.files;
  if (!Array.isArray(files)) return "no file list";
  if (files.length >= 300) return "too many files";
  const lanes = REVIEW_LANES.map(([file]) => `.github/workflows/${file}`);
  return files.some((f) => lanes.includes(f?.filename)) ? "a review-lane workflow" : null;
}

// The cost hold notices among one status job's `annotations`, as { sha, at }
// with `at` the job's completion: only those naming `head`, the head its run
// ran on, so a notice can speak for no other commit.
export function costNotices(annotations, head, at) {
  return (Array.isArray(annotations) ? annotations : []).flatMap((a) => {
    const notice = a?.annotation_level === "notice" ? HOLD_NOTICE.exec(String(a.message ?? "")) : null;
    return notice && notice[1] === head && notice[2].split(",").includes("cost") ? [{ sha: notice[1], at }] : [];
  });
}

// The decided head: the sha of the newest of `notices` before `at`, else
// null; null too when two heads share that time
// (babysit_merge_policy.decided_head, and ci-status's cost-hold step).
export function decidedHead(notices, at) {
  const cutoff = Date.parse(at);
  const before = notices.filter((n) => Date.parse(n.at) < cutoff);
  const newest = Math.max(...before.map((n) => Date.parse(n.at)));
  const heads = new Set(before.filter((n) => Date.parse(n.at) === newest).map((n) => n.sha));
  return heads.size === 1 ? [...heads][0] : null;
}

// Every item of the REST list at `path` whose answer holds it under `key`.
async function listed(read, path, key) {
  const rows = [];
  for (let page = 1; ; page += 1) {
    const answer = await read("GET", `${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${page}`);
    const items = answer?.[key];
    if (!Array.isArray(items)) {
      throw new Error(`${path} has no ${key} list`);
    }
    rows.push(...items);
    if (items.length < 100) {
      return rows;
    }
  }
}

// The head a decision made at `at` decided, from the review lanes' check-run
// annotations, never a comment (any GITHUB_TOKEN workflow posts as
// github-actions[bot]): every pull_request run of a REVIEW_LANES workflow on
// the head `branch` started before `at`, each run's head vetted against
// `base` (laneChange), its status job's cost notices (costNotices) from jobs
// done before `at`, then decidedHead. A run on a head that fails the vet, or
// a read that fails, decides nothing. `read` holds actions: read and
// checks: read.
async function noticedHead(read, repo, branch, base, at) {
  const cutoff = Date.parse(at);
  if (!Number.isFinite(cutoff) || typeof branch !== "string" || !BRANCH.test(branch)) {
    return null;
  }
  const notices = [];
  const vetted = new Set();
  for (const [file, check] of REVIEW_LANES) {
    const runs = await listed(read, `/repos/${repo}/actions/workflows/${file}/runs?event=pull_request&branch=${encodeURIComponent(branch)}`, "workflow_runs");
    for (const run of runs) {
      if (!(Date.parse(run?.created_at) < cutoff)) {
        continue;
      }
      const head = String(run.head_sha ?? "");
      if (!/^[0-9a-f]{40}$/.test(head)) {
        return null;
      }
      if (!vetted.has(head)) {
        if (laneChange(await read("GET", `/repos/${repo}/compare/${base}...${head}`)) !== null) {
          return null;
        }
        vetted.add(head);
      }
      for (const job of await listed(read, `/repos/${repo}/actions/runs/${run.id}/jobs?filter=all`, "jobs")) {
        if (job?.name === check && Date.parse(job.completed_at) < cutoff) {
          notices.push(...costNotices(await pages(read, `/repos/${repo}/check-runs/${job.id}/annotations`), head, job.completed_at));
        }
      }
    }
  }
  return decidedHead(notices, at);
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

// Whether the decision `comment` covers the pull request at `head` (owner
// decisions Q17 c and Q18 d on #9436): its decided head (noticedHead, read
// with `actions` from the head branch `branch`'s lane runs) is `head`, with
// no compare read, or every change since is a merge of the base branch
// `base`, so the net change against it is the same at both (sameNetChange).
// No decided head, an unusable base name or a read that fails carries
// nothing.
async function carries(github, actions, repo, comment, head, base, branch) {
  try {
    if (typeof base !== "string" || !BRANCH.test(base)) {
      return false;
    }
    const decided = await noticedHead(actions, repo, branch, base, comment.created_at);
    if (decided === null) {
      return false;
    }
    if (decided === head) {
      return true;
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
// body)` reads; `actions`, the same shape, reads the lane runs, their jobs,
// annotations and compares (it needs actions: read and checks: read). A
// failed read of the pull request or the Refs target decides nothing, and one
// of a comment or its edit state skips that comment.
export async function costDecision(github, repo, number, body, humans, head, actions = github) {
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
  return decision && (await carries(github, actions, repo, decision.comment, head, pull?.baseRefName, pull?.headRefName)) ? decision.link : null;
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
// it; empty when nothing does. `lifters` approved the head, which lifts a
// hold path but not an unreadable file list or hold-path list, nor a cost
// path, which only the owner's `decision` lifts. It lifts `widened`
// (actorsHold's reason) too. `byPerson` (personWrote) says whether the body
// can hold.
export function holds(body, items, files, holdPaths, lifters = [], decision = null, byPerson = true, widened = null) {
  const reasons = [];
  if (widened && !lifters.length) {
    reasons.push(`${widened}; an approving review of this head by a person on the trusted-actor list lifts it, then re-run ci-status`);
  }
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

// The refusals of babysit_verify_evidence.py a pass decides: verdictHold and
// linkHold judge the pass here, and an approval lifts them as it lifts this.
const PASS_REFUSALS = Object.freeze(["verify:missing", "verify:spec-changed", "verify:untrusted-spec"]);

// Why the reader's report for `head` holds it, or null: a refusal outside
// PASS_REFUSALS (a FAIL class, verify:unreadable, verify:too-old or one this
// module does not know) holds, and so does a report that does not read or
// names another head.
export function evidenceHold(report, head) {
  if (
    report === null ||
    typeof report !== "object" ||
    Array.isArray(report) ||
    report.head !== head ||
    !("refusal" in report) ||
    (report.refusal !== null && typeof report.refusal !== "string")
  ) {
    return "its pr-verify FAILs could not be read";
  }
  const { refusal, detail } = report;
  if (refusal === null || PASS_REFUSALS.includes(refusal)) {
    return null;
  }
  return `pr-verify's reader refuses this head (${refusal}${typeof detail === "string" && detail ? `: ${detail}` : ""})`;
}

// The evidence file's verdict, a file that does not read included.
function evidenceOf(file, head) {
  try {
    return evidenceHold(JSON.parse(readFileSync(file, "utf8")), head);
  } catch {
    return "its pr-verify FAILs could not be read";
  }
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
  const [number, bodyFile, discussionFile, filesFile, deniedFile, actorsFile, head, verdictsFile, linkFile, evidenceFile] = argv;
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
        "usage: merge-holds.mjs <number> <body-file> <discussion-file> <files-file> <denied-paths-file> <trusted-actors-file> <head-sha> [<verdicts-file> <link-file> [<evidence-file>]]",
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
    const widened = actorsHold(await withActorContents(github, repo, changes, env.BASE_SHA, head));
    const reasons = holds(body, items, files, holdPaths, lifters, decision, byPerson, widened);
    const held = pathHold(files, holdPaths);
    if (held && lifters.length && Array.isArray(holdPaths)) {
      console.log(`#${number}: ${lifters.join(", ")} approved this head, which lifts its hold path (${escape(held)}).`);
    }
    if (widened && lifters.length) {
      console.log(`#${number}: ${lifters.join(", ")} approved this head, which lifts its trusted-actor list hold (${escape(widened)}).`);
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
      const failed = evidenceFile ? evidenceOf(evidenceFile, head) : "its pr-verify FAILs could not be read";
      if (!failed) {
        const refusal = JSON.parse(readFileSync(evidenceFile, "utf8")).refusal;
        console.log(`#${number}: no pr-verify FAIL hold: ${refusal ? `the reader refuses this head only on its pass (${refusal})` : "the reader allows this head"}.`);
      } else if (lifters.length) {
        console.log(`#${number}: no pr-verify FAIL hold: ${lifters.join(", ")} approved this head, which lifts '${escape(failed)}'.`);
      } else {
        reasons.push(`${failed}; push a new head for pr-verify to judge, after which enable-auto-merge arms it again, or an approving review of this head by a person on the trusted-actor list lifts it, then re-queue`);
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
