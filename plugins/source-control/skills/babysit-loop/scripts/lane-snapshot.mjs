#!/usr/bin/env node

// Cycle-start snapshot for the babysit-loop merge lane: every open pull request and
// every open issue in one repository, read through fully paginated REST calls and
// checked for completeness before it is printed.
//
// Usage: node lane-snapshot.mjs --repo <owner/repo>
//
// Prints {repo, complete: true, prs, issues} and exits 0 only when every page of both
// lists was read (gh exits non-zero on a failed page, and --paginate has no cap) and the
// pull-request list holds exactly the pull requests the issue list names. A disagreement
// is re-read once before it counts. Any other outcome prints nothing on stdout and one
// reason on stderr, so a caller can never act on a partial list:
//
//   2  usage error (missing or malformed --repo)
//   3  read failure: a gh call exited non-zero, or its output was not the expected JSON
//   4  inconsistent read: the two lists disagreed on both reads (the queue kept moving;
//      the next cycle reads again)
//
// Provenance fields are null when GitHub does not return them (a deleted fork's head
// repository), so a caller's fail-closed test sees the gap rather than a default.

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
  const run = spawnSync("gh", ["api", ...args], { encoding: "utf8", timeout: TIMEOUT_MS, maxBuffer: 256 * 1024 * 1024 });
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

// `--paginate --slurp` wraps every page in an outer array; anything else is a read we
// cannot trust.
function listAll(endpoint, label) {
  const pages = ghJson(["--paginate", "--slurp", endpoint], label);
  if (!Array.isArray(pages) || !pages.every(Array.isArray)) fail(3, `${label} returned an unexpected page shape`);
  return pages.flat();
}

const author = (user) => ({ login: user?.login ?? null, type: user?.type ?? null });
const labels = (item) => (item.labels ?? []).map((label) => label.name);

let values;
try {
  ({ values } = parseArgs({ options: { repo: { type: "string" } }, strict: true }));
} catch (error) {
  fail(2, error.message);
}
const repo = values.repo ?? "";
if (!REPO.test(repo) || repo.split("/").some((part) => /^\.+$/.test(part))) fail(2, `--repo must be owner/repo (got '${repo}')`);

const meta = ghJson([`repos/${repo}`], "repository");
if (typeof meta?.has_issues !== "boolean") fail(3, "repository read carried no has_issues");

const numbers = (rows) => rows.map((row) => row.number).sort((a, b) => a - b).join(",");
// One read of both lists. With issues disabled the issue list is not served, so there
// is nothing to cross-check the pull-request list against.
function readLists() {
  const pulls = listAll(`repos/${repo}/pulls?state=open&per_page=100`, "open pull requests");
  if (!meta.has_issues) return { pulls, items: [], consistent: true };
  const items = listAll(`repos/${repo}/issues?state=open&per_page=100`, "open issues");
  return { pulls, items, consistent: numbers(pulls) === numbers(items.filter((item) => item.pull_request)) };
}

// A PR opened or closed between the two reads makes them disagree; read both again once
// before giving up on the cycle.
let read = readLists();
if (!read.consistent) read = readLists();
if (!read.consistent) fail(4, "the pull-request list and the issue list name different open pull requests on two reads");
const { pulls, items } = read;
const issueRows = items.filter((item) => !item.pull_request);

const prs = pulls.map((pr) => {
  const head = pr.head?.repo;
  const base = pr.base?.repo;
  return {
    number: pr.number,
    title: pr.title,
    isDraft: pr.draft === true,
    labels: labels(pr),
    headRefOid: pr.head?.sha ?? null,
    updatedAt: pr.updated_at ?? null,
    isCrossRepository: head && base ? head.full_name !== base.full_name : null,
    headRepositoryOwner: head?.owner?.login ?? null,
    authorAssociation: pr.author_association ?? null,
    author: author(pr.user),
  };
});
const issues = issueRows.map((issue) => ({
  number: issue.number,
  title: issue.title,
  labels: labels(issue),
  updatedAt: issue.updated_at ?? null,
  authorAssociation: issue.author_association ?? null,
  author: author(issue.user),
}));

process.stdout.write(`${JSON.stringify({ repo, complete: true, prs, issues }, null, 2)}\n`);
