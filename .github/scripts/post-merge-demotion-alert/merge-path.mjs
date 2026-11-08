// Merge paths for the post-merge accounting (README.md, "Merge paths"): which
// path a merged pull request took, the labels that record it, and the per-path
// rollup read back from those labels.
//
// A merge is on the `lanes` path when the agent identity is the actor or
// enqueuer of its pull request's latest AddedToMergeQueueEvent, the test the
// alert's `classify` applies. It is on a configured path (`post-merge.paths`
// in pr-pipeline.yaml) when one of that path's enqueuers is, and an agent
// session wrote the pull request (isAgentAuthored). A record-mode path's
// merges get `merge-path: <path>`, and its reverted pull requests
// `post-merge: reverted` too; nothing here demotes, trips the revert breaker or
// holds a pull request, and the lanes path gets no label.
//
//   merge-path.mjs label --merged "<n>..." --reverted "<n>..."
//     The alert job's canary pass: labels the push's merges and the pull
//     requests it reverts. Needs BASE_PATH (main's checkout, for the config),
//     GITHUB_REPOSITORY and gh's token. Exits 1 when a label write failed.
//   merge-path.mjs rollup --since <YYYY-MM-DD> --until <YYYY-MM-DD> [--repo <owner/repo>] [--json]
//     Merges, reverts and escaped defects per path for merges in the window.
//     Reads the config under BASE_PATH, default this checkout.
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

export const PATH_LABEL_PREFIX = "merge-path: ";
export const REVERTED_LABEL = "post-merge: reverted";
// Older pull requests carry the names from before the org label grammar
// (`axis: value`): `merge-path:<path>` and `post-merge:reverted`.
const PATH_LABEL_STEM = "merge-path:"; // both forms start with it
const LEGACY_REVERTED_LABEL = "post-merge:reverted";
const isReverted = (labels) => labels.includes(REVERTED_LABEL) || labels.includes(LEGACY_REVERTED_LABEL);
// The path a label names, for either the current or the legacy prefix; null for any other label.
export const labelPath = (label) =>
  label.startsWith(PATH_LABEL_STEM) ? label.slice(PATH_LABEL_STEM.length).trim() || null : null;
export const LANES = "lanes";
const OTHER = "other";
const LABEL_COLOR = "c5def5";
const PATH_NAME = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const LOGIN = /^[A-Za-z0-9]+(-[A-Za-z0-9]+)*(\[bot\])?$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

const SESSION_MARKER = /<!--\s*session:\s*\S[^\n]*?-->/;
const GENERATED = "Generated with [Claude Code]";
const CLAUDE_TRAILER = /^co-authored-by:[ \t]*claude\b/im;

// The agent-authored rule: the body carries a session marker or the Claude
// Code footer, and a commit carries a Co-Authored-By: Claude trailer.
export const isAgentAuthored = ({ body, commitMessages }) =>
  (SESSION_MARKER.test(body ?? "") || (body ?? "").includes(GENERATED)) &&
  (commitMessages ?? []).some((message) => CLAUDE_TRAILER.test(message ?? ""));

// The configured paths that are well formed, as { name: { mode, enqueuers } }
// with enqueuers lowercased; anything else is dropped.
export function resolvePaths(paths) {
  const out = {};
  for (const [name, path] of Object.entries(paths ?? {})) {
    const enqueuers = Array.isArray(path?.enqueuers) ? path.enqueuers.filter((l) => typeof l === "string" && LOGIN.test(l)) : [];
    if (PATH_NAME.test(name) && name !== LANES && path?.mode === "record" && enqueuers.length) {
      out[name] = { mode: "record", enqueuers: enqueuers.map((l) => l.toLowerCase()) };
    }
  }
  return out;
}

// A queue actor's login as the alert keys it: lowercased, a Bot's with [bot].
const actorKey = (actor) =>
  !actor?.login
    ? ""
    : actor.login.toLowerCase() + (actor.__typename === "Bot" && !actor.login.endsWith("[bot]") ? "[bot]" : "");

// The path a merged pull request took: `lanes`, a configured path's name, or null.
export function pathOf(pr, { identity, paths }) {
  const keys = [actorKey(pr.queue?.actor), actorKey(pr.queue?.enqueuer)].filter(Boolean);
  if (identity && keys.includes(identity.toLowerCase())) return LANES;
  for (const [name, path] of Object.entries(paths)) {
    if (keys.some((k) => path.enqueuers.includes(k)) && isAgentAuthored(pr)) return name;
  }
  return null;
}

// The labels each pull request still needs: its record path's label, and
// post-merge: reverted when the push reverted it. A legacy name already on the
// pull request counts as present. [{ number, labels }].
export function labelPlan(prs, { identity, paths, reverted }) {
  const plan = [];
  for (const pr of prs) {
    const path = pathOf(pr, { identity, paths });
    if (!path || path === LANES) continue;
    const labels = [];
    if (!pr.labels.some((l) => labelPath(l) === path)) labels.push(`${PATH_LABEL_PREFIX}${path}`);
    if (reverted.has(pr.number) && !isReverted(pr.labels)) labels.push(REVERTED_LABEL);
    if (labels.length) plan.push({ number: pr.number, labels });
  }
  return plan;
}

const QUEUE_FIELDS = `timelineItems(itemTypes: [ADDED_TO_MERGE_QUEUE_EVENT], last: 1) {
  nodes { ... on AddedToMergeQueueEvent { actor { __typename login } enqueuer { __typename login } } } }`;

export const pullRequestsQuery = (numbers) =>
  `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { ${numbers
    .map(
      (n) => `p${n}: pullRequest(number: ${n}) { number body labels(first: 100) { nodes { name } }
  commits(last: 100) { nodes { commit { message } } } ${QUEUE_FIELDS} }`,
    )
    .join(" ")} } }`;

// The labels a pull request's label events leave on it, in timeline order: added by a
// LabeledEvent, taken off by a later UnlabeledEvent. A label deleted repo-wide leaves its
// LabeledEvent and no UnlabeledEvent, so it stays in this set.
const labelsFromEvents = (nodes) => {
  const held = new Set();
  for (const e of nodes ?? []) {
    const name = e?.label?.name;
    if (!name) continue;
    if (e.__typename === "UnlabeledEvent") held.delete(name);
    else held.add(name);
  }
  return [...held];
};

// One pullRequest node as { number, body, labels, commitMessages, queue }. With the
// rollup's label events read, `labels` also holds a label the pull request still had
// when the label itself was deleted.
export const toPr = (node) => ({
  number: node.number,
  title: node.title ?? "",
  body: node.body ?? "",
  mergedAt: node.mergedAt ?? null,
  labels: [
    ...new Set([
      ...(node.labels?.nodes ?? []).map((l) => l.name),
      ...labelsFromEvents(node.labelEvents?.nodes),
    ]),
  ],
  commitMessages: (node.commits?.nodes ?? []).map((c) => c.commit?.message ?? ""),
  queue: node.timelineItems?.nodes?.at(-1) ?? null,
});

const numbersOf = (text) => [...new Set((text ?? "").split(/\s+/).filter((t) => /^[1-9][0-9]*$/.test(t)).map(Number))];

const API_BUDGET_LIB = fileURLToPath(new URL("../../actions/log-api-budget/api-budget.bash", import.meta.url));

// `gh <args>`, through api-budget.bash's gh wrapper when API_BUDGET_TOKEN
// names the token (the job-end api-calls notice counts each request); plain
// gh otherwise, as for a rollup run by hand.
const defaultGh = (args) =>
  execFileSync(
    "bash",
    ["-c", '[ -z "${API_BUDGET_TOKEN:-}" ] || { . "$0" 2>/dev/null && api_budget_wrap_gh "$API_BUDGET_TOKEN"; }; gh "$@"', API_BUDGET_LIB, ...args],
    { encoding: "utf8", maxBuffer: 256 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] },
  );

const graphql = (gh, query, vars) =>
  JSON.parse(gh(["api", "graphql", "-f", `query=${query}`, ...Object.entries(vars).flatMap(([k, v]) => ["-f", `${k}=${v}`])]));

// The canary pass: label the push's record-path merges and the pull requests
// it reverts. Returns { plan, failed }.
export function label({ repo, merged, reverted, config, gh = defaultGh, log = console.log }) {
  const paths = resolvePaths(config.paths);
  const numbers = [...new Set([...merged, ...reverted])].sort((a, b) => a - b);
  if (!Object.keys(paths).length || !numbers.length) {
    log("no record path or no pull request to label");
    return { plan: [], failed: 0 };
  }
  const [owner, name] = repo.split("/");
  const data = graphql(gh, pullRequestsQuery(numbers), { owner, name }).data?.repository ?? {};
  const prs = Object.values(data).filter(Boolean).map(toPr);
  const plan = labelPlan(prs, { identity: config.agentIdentity, paths, reverted: new Set(reverted) });
  let failed = 0;
  const ensured = new Set();
  for (const { number, labels } of plan) {
    for (const l of labels) {
      if (ensured.has(l)) continue;
      ensured.add(l);
      try {
        gh(["api", `repos/${repo}/labels/${encodeURIComponent(l)}`]);
      } catch {
        try {
          gh(["api", "-X", "POST", `repos/${repo}/labels`, "-f", `name=${l}`, "-f", `color=${LABEL_COLOR}`, "-f", "description=Post-merge accounting record (README.md, Merge paths)"]);
        } catch {
          log(`::warning::could not create the label ${l}; adding it anyway`);
        }
      }
    }
    try {
      gh(["api", "-X", "POST", `repos/${repo}/issues/${number}/labels`, ...labels.flatMap((l) => ["-f", `labels[]=${l}`])]);
      log(`labeled #${number}: ${labels.join(", ")}`);
    } catch (e) {
      failed += 1;
      const reason = String(e.stderr || e.message || "").trim().split("\n")[0].slice(0, 300);
      log(`::error::could not label #${number} ${labels.join(", ")}: ${reason}`);
    }
  }
  if (!plan.length) log(`no record-path merge among #${numbers.join(", #")} needs a label`);
  return { plan, failed };
}

// --- Rollup ------------------------------------------------------------------

const FIX_TITLE = /^fix(\([^)]*\))?!?:/;
const REVERT_MARKER = /^<!-- babysit-merge-demotion sha=[0-9a-f]{40} signal=revert -->/;

const days = (since, until) => {
  const out = [];
  for (let d = new Date(`${since}T00:00:00Z`); d <= new Date(`${until}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + 1)) {
    out.push(d.toISOString().slice(0, 10));
  }
  return out;
};

const MERGED_QUERY = `query($q: String!, $after: String) { search(query: $q, type: ISSUE, first: 50, after: $after) {
  pageInfo { hasNextPage endCursor }
  nodes { ... on PullRequest { number title body mergedAt labels(first: 100) { nodes { name } }
  labelEvents: timelineItems(itemTypes: [LABELED_EVENT, UNLABELED_EVENT], last: 100) {
    nodes { __typename ... on LabeledEvent { label { name } } ... on UnlabeledEvent { label { name } } } }
  ${QUEUE_FIELDS} } } } }`;

function search(gh, query, q) {
  const nodes = [];
  let after = "";
  for (;;) {
    const page = graphql(gh, query, after ? { q, after } : { q }).data.search;
    nodes.push(...page.nodes.filter((n) => n?.number));
    if (!page.pageInfo.hasNextPage) return nodes;
    after = page.pageInfo.endCursor;
  }
}

// The rollup over already-read pull requests: `merged` is every pull request
// merged from the window's start to now, `revertRecords` the lane revert
// records' bodies. A merge's path is its merge-path label, current or held when the
// label was deleted (its LabeledEvent survives with no UnlabeledEvent), else `lanes` by
// enqueuer, else `other`. Reverted: labeled post-merge:reverted or named on a
// lane revert record. Escaped: a later merged pull request with a fix: title
// cites it as #N or by URL.
export function rollup({ repo, since, until, merged, revertRecords, identity }) {
  const end = new Date(`${until}T00:00:00Z`).getTime() + 86_400_000;
  const start = new Date(`${since}T00:00:00Z`).getTime();
  const inWindow = merged.filter((pr) => {
    const at = Date.parse(pr.mergedAt);
    return at >= start && at < end;
  });
  const revertedByRecord = new Set();
  const url = new RegExp(`/${repo.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}/pull/([1-9][0-9]*)`, "g");
  for (const body of revertRecords) {
    for (const line of body.split("\n")) {
      if (line.startsWith("- Reverted pull request: ")) for (const m of line.matchAll(url)) revertedByRecord.add(Number(m[1]));
    }
  }
  const cited = new Map();
  for (const fix of merged.filter((pr) => FIX_TITLE.test(pr.title))) {
    const refs = new Set([...fix.body.matchAll(/(?<![\w/])#([1-9][0-9]*)\b/g)].map((m) => Number(m[1])));
    for (const m of fix.body.matchAll(url)) refs.add(Number(m[1]));
    for (const n of refs) if (n !== fix.number) cited.set(n, [...(cited.get(n) ?? []), fix]);
  }
  const rows = {};
  for (const pr of inWindow) {
    const path = pr.labels.map(labelPath).find(Boolean) ?? pathOf(pr, { identity, paths: {} }) ?? OTHER;
    const row = (rows[path] ??= { merges: 0, reverts: 0, escapes: 0 });
    row.merges += 1;
    if (isReverted(pr.labels) || revertedByRecord.has(pr.number)) row.reverts += 1;
    if ((cited.get(pr.number) ?? []).some((fix) => Date.parse(fix.mergedAt) > Date.parse(pr.mergedAt))) row.escapes += 1;
  }
  return { repo, since, until, paths: rows };
}

export function readRollup({ repo, since, until, identity, gh = defaultGh, today = new Date().toISOString().slice(0, 10) }) {
  const merged = days(since, today < until ? until : today).flatMap((d) =>
    search(gh, MERGED_QUERY, `repo:${repo} is:pr is:merged merged:${d}..${d}`).map(toPr),
  );
  const RECORDS_QUERY = `query($q: String!, $after: String) { search(query: $q, type: ISSUE, first: 50, after: $after) {
    pageInfo { hasNextPage endCursor } nodes { ... on Issue { number body author { login } } } } }`;
  const filers = new Set(["github-actions", identity.replace(/\[bot\]$/, "").toLowerCase()]);
  const revertRecords = search(gh, RECORDS_QUERY, `repo:${repo} is:issue in:title "Post-merge revert"`)
    .filter((i) => filers.has((i.author?.login ?? "").replace(/\[bot\]$/, "").toLowerCase()))
    .map((i) => (i.body ?? "").replace(/^\s+/, ""))
    .filter((b) => REVERT_MARKER.test(b));
  return rollup({ repo, since, until, merged, revertRecords, identity });
}

export const formatRollup = ({ repo, since, until, paths }) =>
  [
    `${repo} merges ${since}..${until} (UTC, both days included)`,
    "| Path | Merges | Reverts | Escaped defects (cited by a later fix, upper bound) |",
    "|---|---:|---:|---:|",
    ...Object.entries(paths)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([p, r]) => `| ${p} | ${r.merges} | ${r.reverts} | ${r.escapes} |`),
  ].join("\n");

function option(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
}

async function loadConfig(basePath) {
  const { postMergeFromBase } = await import(
    pathToFileURL(`${basePath}/.github/actions/resolve-config/resolve-config.mjs`).href
  );
  return postMergeFromBase({ BASE_PATH: basePath });
}

async function main(argv = process.argv.slice(2), env = process.env) {
  const [command] = argv;
  if (command === "label") {
    const config = await loadConfig(env.BASE_PATH || ".base");
    const { failed } = label({
      repo: env.GITHUB_REPOSITORY,
      merged: numbersOf(option(argv, "--merged")),
      reverted: numbersOf(option(argv, "--reverted")),
      config,
    });
    if (failed) process.exitCode = 1;
    return;
  }
  if (command === "rollup") {
    const since = option(argv, "--since");
    const until = option(argv, "--until");
    if (!DATE.test(since ?? "") || !DATE.test(until ?? "") || since > until) {
      throw new Error("rollup needs --since and --until as YYYY-MM-DD, since no later than until");
    }
    const root = env.BASE_PATH || resolve(fileURLToPath(import.meta.url), "../../../..");
    const config = await loadConfig(root);
    const repo = option(argv, "--repo") || defaultGh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).trim();
    const result = readRollup({ repo, since, until, identity: config.agentIdentity });
    console.log(argv.includes("--json") ? JSON.stringify(result, null, 2) : formatRollup(result));
    return;
  }
  throw new Error("usage: merge-path.mjs label --merged \"<n>...\" --reverted \"<n>...\" | rollup --since <date> --until <date> [--repo <owner/repo>] [--json]");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.log(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
