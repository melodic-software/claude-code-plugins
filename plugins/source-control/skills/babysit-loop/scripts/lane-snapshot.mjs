#!/usr/bin/env node

// Cycle-start snapshot for the babysit-loop merge lane: every open pull request and
// every open issue in one repository, read through fully paginated REST calls and
// checked for completeness before it is printed.
//
// Usage: node lane-snapshot.mjs --repo <owner/repo>
//
// Prints {repo, complete: true, openCount, prs, issues} and exits 0 only when the read
// is confirmed complete: the repository's open_issues_count (which counts open issues
// and open pull requests together) equals the pull requests plus issues listed, and the
// pull-request list holds exactly the pull requests the issue list names. Any other
// outcome prints nothing on stdout and one reason on stderr, so a caller can never act
// on a partial list:
//
//   2  usage error (missing or malformed --repo)
//   3  read failure: a gh call exited non-zero, or its output was not the expected JSON
//   4  incomplete read: the counts or the pull-request sets disagree (truncation, or the
//      queue moved between reads; the next cycle reads again)
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
const openCount = meta?.open_issues_count;
if (!Number.isInteger(openCount)) fail(3, "repository read carried no open_issues_count");

const pulls = listAll(`repos/${repo}/pulls?state=open&per_page=100`, "open pull requests");
// With issues disabled the issue list is not served; open_issues_count then counts pull
// requests alone.
const items = meta.has_issues === false ? [] : listAll(`repos/${repo}/issues?state=open&per_page=100`, "open issues");
const issueRows = items.filter((item) => !item.pull_request);

const pullNumbers = pulls.map((pr) => pr.number).sort((a, b) => a - b);
if (pulls.length + issueRows.length !== openCount) {
  fail(4, `listed ${pulls.length} pull requests and ${issueRows.length} issues, but the repository reports ${openCount} open`);
}
if (meta.has_issues !== false) {
  const fromIssues = items.filter((item) => item.pull_request).map((item) => item.number).sort((a, b) => a - b);
  if (fromIssues.join(",") !== pullNumbers.join(",")) {
    fail(4, "the pull-request list and the issue list name different open pull requests");
  }
}

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

process.stdout.write(`${JSON.stringify({ repo, complete: true, openCount, prs, issues }, null, 2)}\n`);
