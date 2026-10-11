#!/usr/bin/env node

// Cycle-start snapshot for the babysit-loop merge lane: every open pull request and
// every open issue in one repository, read through GraphQL cursor pagination and checked
// for completeness before it is printed.
//
// Usage: node lane-snapshot.mjs --repo <owner/repo>
//
// Prints {repo, complete: true, prs, issues} and exits 0 only when every page of both
// lists was read (gh exits non-zero on a failed page, and --paginate has no cap) and each
// list is whole: no number repeats, and the count read equals the totalCount every page
// reported. Cursors do not shift the way REST page offsets do when an item opens or
// closes mid-read, and the totalCount check catches a list that changed between pages.
// A list that fails the check is re-read once before it counts. Any other outcome prints
// nothing on stdout and one reason on stderr, so a caller can never act on a partial list:
//
//   2  usage error (missing or malformed --repo)
//   3  read failure: a gh call exited non-zero, or its output was not the expected JSON
//   4  incomplete read: a list failed the completeness check on both reads (the queue
//      kept moving; the next cycle reads again)
//
// Provenance fields are null when GitHub does not return them (a deleted fork's head
// repository, a deleted author), so a caller's fail-closed test sees the gap rather than
// a default. Author login and type keep the REST shape the trust test matches: a GraphQL
// Bot login gains the `[bot]` suffix REST reports, and type is the GraphQL typename.

import { spawnSync } from "node:child_process";
import process from "node:process";
import { parseArgs } from "node:util";

const REPO = /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/;
const TIMEOUT_MS = 120_000;

function fail(code, reason) {
  process.stderr.write(`lane-snapshot: ${reason}\n`);
  process.exit(code);
}

function ghJson(args, label) {
  const run = spawnSync("gh", ["api", ...args], {
    encoding: "utf8",
    timeout: TIMEOUT_MS,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (run.error || run.status !== 0) {
    const detail = (run.error?.message ?? run.stderr ?? "").trim().slice(0, 300);
    fail(3, `${label} read failed (exit ${run.status ?? "none"}): ${detail}`);
  }
  try {
    return JSON.parse(run.stdout);
  } catch {
    fail(3, `${label} returned output that is not JSON`);
  }
}

const LABELS = "labels(first: 100) { totalCount nodes { name } }";
const AUTHOR = "author { __typename login }";
const FIELDS = {
  pullRequests: `number title isDraft ${LABELS} headRefOid updatedAt isCrossRepository headRepositoryOwner { login } authorAssociation ${AUTHOR}`,
  issues: `number title ${LABELS} updatedAt authorAssociation ${AUTHOR}`,
};

// Every open node of one connection, oldest first, through `--paginate --slurp` (one
// response object per page). Returns null when the pages do not add up to one whole list.
function listAll(connection, label) {
  const query = `query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    ${connection}(states: OPEN, first: 100, after: $endCursor, orderBy: {field: CREATED_AT, direction: ASC}) {
      totalCount pageInfo { hasNextPage endCursor } nodes { ${FIELDS[connection]} }
    }
  }
}`;
  const [owner, name] = repo.split("/");
  const pages = ghJson(
    ["graphql", "--paginate", "--slurp", "-F", `owner=${owner}`, "-F", `name=${name}`, "-f", `query=${query}`],
    label,
  );
  const conns = Array.isArray(pages) ? pages.map((page) => page?.data?.repository?.[connection]) : [];
  if (
    !conns.length ||
    !conns.every((c) => Array.isArray(c?.nodes) && Number.isInteger(c.totalCount)) ||
    conns.at(-1).pageInfo?.hasNextPage !== false
  ) {
    fail(3, `${label} returned an unexpected page shape`);
  }
  const nodes = conns.flatMap((c) => c.nodes);
  if (nodes.some((node) => (node.labels?.totalCount ?? 0) > (node.labels?.nodes?.length ?? 0)))
    fail(3, `${label} carried an item with more labels than one read returns`);
  const total = conns[0].totalCount;
  const whole =
    conns.every((c) => c.totalCount === total) &&
    nodes.length === total &&
    new Set(nodes.map((node) => node.number)).size === total;
  return whole ? nodes : null;
}

const author = (user) => ({
  login: user?.login == null ? null : user.__typename === "Bot" ? `${user.login}[bot]` : user.login,
  type: user?.__typename ?? null,
});
const labels = (item) => (item.labels?.nodes ?? []).map((label) => label.name);

let values;
try {
  ({ values } = parseArgs({
    options: { repo: { type: "string" } },
    strict: true,
  }));
} catch (error) {
  fail(2, error.message);
}
const repo = values.repo ?? "";
if (!REPO.test(repo) || repo.split("/").some((part) => /^\.+$/.test(part)))
  fail(2, `--repo must be owner/repo (got '${repo}')`);

const meta = ghJson([`repos/${repo}`], "repository");
if (typeof meta?.has_issues !== "boolean") fail(3, "repository read carried no has_issues");

// One read of both lists. With issues disabled there is no issue list to read.
function readLists() {
  const pulls = listAll("pullRequests", "open pull requests");
  const issues = meta.has_issues ? listAll("issues", "open issues") : [];
  return pulls && issues ? { pulls, issues } : null;
}

// An item opened or closed mid-read leaves a list short, long, or with a repeat; read
// both again once before giving up on the cycle.
const read = readLists() ?? readLists();
if (!read) fail(4, "an open pull-request or issue list was incomplete on two reads");

const prs = read.pulls.map((pr) => ({
  number: pr.number,
  title: pr.title,
  isDraft: pr.isDraft === true,
  labels: labels(pr),
  headRefOid: pr.headRefOid ?? null,
  updatedAt: pr.updatedAt ?? null,
  isCrossRepository: typeof pr.isCrossRepository === "boolean" ? pr.isCrossRepository : null,
  headRepositoryOwner: pr.headRepositoryOwner?.login ?? null,
  authorAssociation: pr.authorAssociation ?? null,
  author: author(pr.author),
}));
const issues = read.issues.map((issue) => ({
  number: issue.number,
  title: issue.title,
  labels: labels(issue),
  updatedAt: issue.updatedAt ?? null,
  authorAssociation: issue.authorAssociation ?? null,
  author: author(issue.author),
}));

process.stdout.write(`${JSON.stringify({ repo, complete: true, prs, issues }, null, 2)}\n`);
