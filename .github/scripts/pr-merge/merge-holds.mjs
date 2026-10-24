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
// - A manifest change the merge gate reviews (manifestChanges, the rule of
//   babysit_risk._manifest_changes): a plugin manifest or the marketplace
//   manifest, read at the base commit (BASE_SHA) and the head and compared
//   key by key. The same approval lifts it.
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
// exits 0. A changed manifest, and a cost path with a decision link in the
// body, are read with GH_TOKEN.
import { Buffer } from "node:buffer";
import { readFileSync } from "node:fs";
import { posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

// enable-auto-merge.test.mjs checks both agree with the gate's Python on every
// text it tries.
export const BODY_HOLD = /\bdo(?:n['’]?t| not)\s+merge\b|(?:^|\r)[^\S\r\n]*hold:/im;
export const HUMAN_VETO = /\bdo(?:n['’]?t| not|-not)[\s-]*merge\b/i;

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
// live link, or null when it does. The live link is the gate's
// (babysit_merge_policy._linked_issue): its one closing issue in `repo`, or,
// with no closing issue at all, the one issue its plain `Refs:` lines name
// (refsIssue). The pass binds when it judged that one issue, linked the same
// way (its `spec_kind`, `closes` when absent, as the reader reads an older
// record).
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
  let live = null;
  let linked = "refs";
  if (closing.totalCount > 0) {
    const [issue] = closing.nodes;
    if (closing.totalCount !== 1 || String(issue?.repository?.nameWithOwner).toLowerCase() !== String(repo).toLowerCase()) {
      return "it does not close exactly one issue in this repository, which pr-merge's lane takes";
    }
    live = issue.number;
    linked = "closes";
  } else {
    live = refsIssue(body);
  }
  if (!Number.isSafeInteger(live)) {
    return "it names no issue pr-merge's lane takes";
  }
  const judged = record.linked_issues.map((issue) => issue?.number);
  if (judged.length !== 1 || judged[0] !== live || kind !== linked) {
    return `its link changed since pr-verify passed it: it ${linked === "closes" ? "closes" : "refs"} #${live}, and the pass judged ${judged.map((n) => `#${n}`).join(", ") || "no issue"} (${kind})`;
  }
  return null;
}
// babysit_merge_policy.BLOCKER_ASSOCIATIONS.
const MEMBERS = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);
// The denied paths resolve-config adds to every config's (resolveMerge);
// merge-authority.test.mjs checks the two agree.
export const FORCED_DENIED_PATHS = Object.freeze([
  "docs/conventions/pr-pipeline.yaml",
  ".github/standards/trusted-actors/trusted-actors.json",
]);
// Every hold path check adds these: the forced paths and the merge gate's
// HIGH floor (babysit_risk.HIGH_FLOOR), which test_merge_holds_sync.py checks
// this covers. A manifest is compared base against head instead
// (manifestChanges).
export const HOLD_PATH_FLOOR = Object.freeze([
  ...FORCED_DENIED_PATHS,
  ".github/standards/trusted-actors/**",
  ".github/actions/check-trusted-trigger/**",
  "**/CODEOWNERS",
  "**/.gitmodules",
  ".github/actions/resolve-config/**",
  ".github/actions/check-kill-switch/**",
]);

// babysit_risk.is_manifest_path: a plugin manifest or the marketplace
// manifest, matched case-sensitively.
export function isManifestPath(path) {
  const parts = String(path).split("/");
  return (
    (parts.length === 2 && parts[0] === ".claude-plugin" && parts[1] === "marketplace.json") ||
    (parts.length === 4 && parts[0] === "plugins" && parts[2] === ".claude-plugin" && parts[3] === "plugin.json")
  );
}

// babysit_risk._manifest: the parsed object as a node tree, or null when the
// text is not a string, not JSON, not an object, or repeats a key. A node is
// { object: Map }, { array: [] } or { text }, a scalar's text telling values
// apart as Python's json.loads does: an integer and a float differ (1 and
// 1.0), so canonical (json.dumps with sort_keys) compares them as the gate.
function parseManifest(text) {
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
// babysit_risk._canonical: a key's canonical value, null when absent or
// `node` is no object.
const canonicalOf = (node, key) => (node?.object?.has(key) ? canonical(node.object.get(key)) : null);
// babysit_risk._EXECUTABLE_KEYS.
const EXECUTABLE_KEYS = Object.freeze(["hooks", "mcpServers", "lspServers", "monitors"]);

function pluginChanges(base, head) {
  const found = EXECUTABLE_KEYS.filter((key) => canonicalOf(base, key) !== canonicalOf(head, key));
  const monitors = (node) => canonicalOf(node.object.get("experimental"), "monitors");
  return monitors(base) === monitors(head) ? found : [...found, "experimental.monitors"];
}

// `plugins` by name, null unless a list of uniquely named objects.
function entries(node) {
  const plugins = node.object.get("plugins") ?? { array: [] };
  if (!plugins.array) {
    return null;
  }
  const named = new Map();
  for (const entry of plugins.array) {
    const name = entry.object?.get("name");
    if (name?.string) {
      named.set(JSON.parse(name.text), entry);
    }
  }
  return named.size === plugins.array.length ? named : null;
}

function marketplaceChanges(base, head) {
  const found = canonicalOf(base, "name") === canonicalOf(head, "name") ? [] : ["name"];
  const old = entries(base);
  const now = entries(head);
  if (old === null || now === null) {
    return [...found, "plugins is not a list of uniquely named entries"];
  }
  for (const name of [...new Set([...old.keys(), ...now.keys()])].sort()) {
    if (!now.has(name)) {
      found.push(`plugins[${name}] removed`);
    } else if (!old.has(name)) {
      found.push(`plugins[${name}] added`);
    } else if (canonicalOf(old.get(name), "source") !== canonicalOf(now.get(name), "source")) {
      found.push(`plugins[${name}].source`);
    }
  }
  return found;
}

// babysit_risk._manifest_changes: what in one changed manifest needs a
// person's review, empty when nothing does; test_merge_holds_sync.py checks
// the two agree. `change` is { path, previous, status, contents }, contents
// [base text, head text] with null for an absent side. In plugin.json an
// executable key or experimental.monitors that differs, in marketplace.json
// a plugin added, removed or renamed, a changed entry source or marketplace
// name; a manifest removed, renamed or copied, of any other status, or with a
// side that does not read, parse or repeats a key holds. An added plugin.json
// is compared with {}.
export function manifestChanges({ path, previous = null, status, contents } = {}) {
  if (!["modified", "added"].includes(status) || previous !== null) {
    return [`${status ?? "unknown"} manifest`];
  }
  if (!Array.isArray(contents) || contents.length !== 2) {
    return ["contents unreadable"];
  }
  const base = parseManifest(status === "added" ? "{}" : contents[0]);
  const head = parseManifest(contents[1]);
  if (base === null || head === null) {
    return ["unreadable, malformed or a repeated key"];
  }
  return path.endsWith("marketplace.json") ? marketplaceChanges(base, head) : pluginChanges(base, head);
}

// Why the changed manifests in `changes` (manifestChanges's entries) hold
// the head, or null. A manifest renamed away holds too.
export function manifestHold(changes) {
  if (!Array.isArray(changes)) {
    return "its changed manifests could not be read";
  }
  const held = changes
    .filter(({ path, previous }) => isManifestPath(path) || (previous != null && isManifestPath(previous)))
    .map((change) => [change.path, manifestChanges(change)])
    .filter(([, found]) => found.length);
  return held.length ? `it changes ${held.map(([path, found]) => `${path} (${found.join(", ")})`).join("; ")}, a manifest change that needs review` : null;
}

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
  const globs = [...holdPaths, ...HOLD_PATH_FLOOR];
  const held = files.find((path) => globs.some((glob) => matchesHoldPath(path, glob)));
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
// it; empty when nothing does. `manifest` is manifestHold's reason. `lifters`
// approved the head, which lifts a hold path or a manifest change but not an
// unreadable file list or hold-path list, nor a cost path, which only the
// owner's `decision` lifts.
export function holds(body, items, files, holdPaths, lifters = [], decision = null, manifest = null) {
  const reasons = [];
  const pathReason = [pathHold(files, holdPaths), manifest].filter(Boolean).join("; ") || null;
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

// The link file's verdict, a file that does not read included.
function linkOf(file, body, repo) {
  try {
    const { record, closing } = JSON.parse(readFileSync(file, "utf8"));
    return linkHold(record, body, closing, repo);
  } catch {
    return "its issue link could not be checked against its verifier pass";
  }
}

// One files-file line as a manifestChanges entry: [filename,
// previous_filename or null, status] from the pull request files API, or an
// object of those keys. An older line of one path and any renamed-from path
// has no status, so a manifest on it holds. A module older than this one
// reads every entry of a line as a path, null and the status matching no
// hold path.
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

// `changes` with each modified or added manifest's [base text at `base`,
// head text at `head`], base null for an added one; a read that fails, or a
// base that is not a commit SHA, leaves its contents out, so it holds.
export async function withContents(github, repo, changes, base, head) {
  const text = async (path, ref) => {
    const file = await github("GET", `/repos/${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${ref}`);
    if (file?.type !== "file" || file.encoding !== "base64" || typeof file.content !== "string") {
      throw new Error(`${path} at ${ref} did not read`);
    }
    // Strict, as the gate's decode("utf-8"): invalid UTF-8 throws, so it
    // holds, and a BOM stays, so JSON.parse refuses it as json.loads does.
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(Buffer.from(file.content, "base64"));
  };
  return Promise.all(
    changes.map(async (change) => {
      if (!isManifestPath(change.path) || !["modified", "added"].includes(change.status) || change.previous !== null || !/^[0-9a-f]{40}$/.test(String(base))) {
        return change;
      }
      try {
        return { ...change, contents: [change.status === "added" ? null : await text(change.path, base), await text(change.path, head)] };
      } catch {
        return change;
      }
    }),
  );
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
      costHold(files, null) && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) ? await costDecision(github, repo, Number(number), body, humans) : null;
    if (decision) {
      console.log(`#${number}: ${decision} records the owner's cost decision, which lifts its cost hold.`);
    }
    const manifest = manifestHold(await withContents(github, repo, changes, env.BASE_SHA, head));
    const reasons = holds(body, items, files, holdPaths, lifters, decision, manifest);
    const held = [pathHold(files, holdPaths), manifest].filter(Boolean).join("; ") || null;
    if (held && lifters.length && Array.isArray(holdPaths)) {
      console.log(`#${number}: ${lifters.join(", ")} approved this head, which lifts its hold path or manifest hold (${escape(held)}).`);
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
