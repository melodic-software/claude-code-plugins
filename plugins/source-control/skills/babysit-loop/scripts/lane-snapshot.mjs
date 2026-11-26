#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import process from "node:process";
import { parseArgs } from "node:util";

const REPO = /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/;
const TIMEOUT_MS = 120_000;
const RULES_PATH = ".github/actions/resolve-config/admission-rules.json";

function fail(code, reason) {
  process.stderr.write(`lane-snapshot: ${reason}\n`);
  process.exit(code);
}

function ghJson(args, label, ifNotFound) {
  const run = spawnSync("gh", ["api", ...args], {
    encoding: "utf8",
    timeout: TIMEOUT_MS,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (ifNotFound !== undefined && run.status !== 0 && run.stderr?.includes("HTTP 404")) return ifNotFound;
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
  issues: `number title ${LABELS} milestone { title } updatedAt authorAssociation ${AUTHOR}`,
};

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

const rules = ghJson(["-H", "Accept: application/vnd.github.raw", `repos/${repo}/contents/${RULES_PATH}`], "admission rules", {});
const cordoned = rules?.["cordoned-milestones"] ?? [];
if (!Array.isArray(cordoned)) fail(3, "admission rules carried a cordoned-milestones that is not a list");

function readLists() {
  const pulls = listAll("pullRequests", "open pull requests");
  const issues = meta.has_issues ? listAll("issues", "open issues") : [];
  return pulls && issues ? { pulls, issues } : null;
}

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
  milestone: issue.milestone?.title ?? null,
  cordoned: cordoned.includes(issue.milestone?.title),
  updatedAt: issue.updatedAt ?? null,
  authorAssociation: issue.authorAssociation ?? null,
  author: author(issue.author),
}));

process.stdout.write(`${JSON.stringify({ repo, complete: true, prs, issues }, null, 2)}\n`);
