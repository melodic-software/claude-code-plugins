#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const MIN_FAILURES = 5;
const CALL_BUDGET = 200;
const SLICE_DAYS = 7;
const SIGNALS = ["demotion", "canary", "revert", "any"];
const DEMOTION_SIGNALS = new Set(["schedule", "dispatch", "read-back"]);

const SHA = /^[0-9a-f]{40}$/;
const MARKER = /^<!-- merge-risk-line head=([0-9a-f]{40})(?: lane=([a-z][a-z0-9-]{0,63}) run=([1-9][0-9]{0,19}))? -->$/;
const RATED = /^Merge-Risk: max=(?:LOW|MEDIUM|HIGH|CRITICAL) demote=(true|false)(?:\s|$)/;
const RECORD = /^<!-- (babysit-merge-demotion|post-merge-failure) sha=([0-9a-f]{40}) signal=(schedule|dispatch|canary|revert|read-back) -->$/;
const firstLine = (text) => String(text ?? "").split(/\r?\n/)[0];

export function readMarker(comments, bot, head) {
  const isApp = (actor) => actor?.__typename === "Bot" && actor.login === bot;
  const newest = (comments ?? [])
    .filter((c) => isApp(c?.author) && !(c.lastEditedAt && !isApp(c.editor)) && MARKER.exec(firstLine(c.body))?.[1] === head)
    .sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)))
    .at(-1);
  if (!newest) return null;
  const [, , lane = null, run = null] = MARKER.exec(firstLine(newest.body));
  const rated = RATED.exec(String(newest.body).split(/\r?\n/)[1] ?? "");
  return { demote: rated ? rated[1] === "true" : null, lane, run };
}

export function squashRating(body) {
  const lines = String(body ?? "").split(/\r?\n/);
  const at = lines.findLastIndex((line) => line.startsWith("Merge-Risk: "));
  if (at < 0) return null;
  const end = lines.findIndex((line, i) => i > at && line.trim() === "");
  const rated = RATED.exec(lines.slice(at, end < 0 ? undefined : end).join(" "));
  return rated ? rated[1] === "true" : null;
}

const REVERT_SUBJECT = /^Revert "|^revert(\([^)]*\))?!?: /;
const stripOwnRef = (subject) => subject.replace(/ *\(#[0-9]+\)$/, "");

export function revertsOf({ subject, body }) {
  const shas = [...new Set([...String(body).matchAll(/This reverts (?:commit )?([0-9a-f]{40})/g)].map((m) => m[1]))];
  if (shas.length) return { shas, prs: [], subjects: [] };
  if (!REVERT_SUBJECT.test(subject)) return null;
  const prs = [
    ...[...String(body).matchAll(/(?:^|[^A-Za-z0-9_])reverts[ \t]+(?:[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)?#([0-9]+)/gi)].map((m) => Number(m[1])),
    ...[...stripOwnRef(subject).matchAll(/\(#([0-9]+)/g)].map((m) => Number(m[1])),
  ];
  if (prs.length) return { shas: [], prs: [...new Set(prs)], subjects: [] };
  const quoted = /^Revert "(.*)"/.exec(subject)?.[1];
  if (quoted !== undefined) return { shas: [], prs: [], subjects: [quoted] };
  const rest = subject.replace(REVERT_SUBJECT, "").trimStart();
  const inner = /"(.*)"/.exec(rest)?.[1];
  return { shas: [], prs: [], subjects: [...new Set([inner, rest, stripOwnRef(rest)].filter((s) => s !== undefined))] };
}

export function parseRecordMarker(line) {
  const match = RECORD.exec(String(line ?? ""));
  return match && { kind: match[1], sha: match[2], signal: match[3] };
}

export function readRecord(body) {
  const lines = String(body ?? "").split(/\r?\n/);
  const marker = parseRecordMarker(lines[0]);
  if (!marker) return null;
  const prs = lines.flatMap((line) => /^- Pull request: \S*\/pull\/([0-9]+)/.exec(line)?.[1] ?? []).map(Number);
  const range = lines.flatMap((line) => /^ +- .*`([0-9a-f]{40})`/.exec(line)?.[1] ?? []);
  const also = lines.flatMap((line) => (line.startsWith("- Also charged by this run: ") ? [...line.matchAll(/`([0-9a-f]{40})`/g)].map((m) => m[1]) : []));
  if (also.length) range.push(marker.sha, ...also);
  return { signal: marker.signal, sha: marker.sha, prs, range };
}

const ratio = (part, whole) => (whole === 0 ? null : Math.round((part / whole) * 10000) / 10000);
const empty = () => ({ rated: 0, demotion: 0, demotion_in_range: 0, canary: 0, canary_in_range: 0, revert: 0, any: 0 });

export function compute({ since, until, commits, markers, records }) {
  const markerOf = new Map(markers.map((m) => [m.merge, m]));
  let unrated = 0;
  const rated = [];
  for (const c of commits) {
    if (c.ct < since || c.ct >= until) continue;
    const marker = markerOf.get(c.sha);
    const demote = marker?.demote ?? c.demote;
    if (demote === null || demote === undefined) {
      if (marker) unrated += 1;
      continue;
    }
    rated.push({ ...c, demote, lane: marker?.lane ?? null });
  }
  const hit = (merge, signals) => {
    const named = records.filter((r) => signals(r.signal));
    return {
      alone: named.some((r) => r.range.length === 0 && (r.sha === merge.sha || r.prs.includes(merge.pr))),
      inRange: named.some((r) => r.range.includes(merge.sha)),
    };
  };
  const reverted = (merge) =>
    commits.some(
      (k) =>
        k.reverts &&
        k.sha !== merge.sha &&
        k.ct >= merge.ct &&
        (k.reverts.shas.includes(merge.sha) || k.reverts.prs.includes(merge.pr) || k.reverts.subjects.some((s) => s === merge.subject || s === stripOwnRef(merge.subject))),
    );
  const groups = { true: empty(), false: empty() };
  const byLane = {};
  for (const merge of rated) {
    const demotion = hit(merge, (s) => DEMOTION_SIGNALS.has(s));
    const canary = hit(merge, (s) => s === "canary");
    const revert = reverted(merge);
    const targets = [groups[merge.demote]];
    if (merge.lane) targets.push(((byLane[merge.lane] ??= { true: empty(), false: empty() }))[merge.demote]);
    for (const g of targets) {
      g.rated += 1;
      g.demotion += demotion.alone;
      g.demotion_in_range += !demotion.alone && demotion.inRange;
      g.canary += canary.alone;
      g.canary_in_range += !canary.alone && canary.inRange;
      g.revert += revert;
      g.any += demotion.alone || canary.alone || revert;
    }
  }
  const compare = Object.fromEntries(
    SIGNALS.map((s) => [
      s,
      groups.true[s] >= MIN_FAILURES && groups.false[s] >= MIN_FAILURES
        ? { true: ratio(groups.true[s], groups.true.rated), false: ratio(groups.false[s], groups.false.rated) }
        : "not enough failures to compare",
    ]),
  );
  return { min_failures: MIN_FAILURES, rated: rated.length, unrated, groups, compare, by_lane: byLane, without_lane: rated.filter((m) => !m.lane).length };
}

const COLUMNS = ["rated", "demotion", "demotion_in_range", "canary", "canary_in_range", "revert", "any"];
const table = (rows) => [`| group | ${COLUMNS.join(" | ")} |`, `|${" --- |".repeat(COLUMNS.length + 1)}`, ...rows.map(([name, g]) => `| ${name} | ${COLUMNS.map((k) => g[k]).join(" | ")} |`)];

export function renderMarkdown(result) {
  const out = [`Rated merges: ${result.rated} (${result.unrated} more armed unrated). Rates need ${result.min_failures} failures in each group.`, ""];
  out.push(...table([["demote=true", result.groups.true], ["demote=false", result.groups.false]]), "");
  for (const s of SIGNALS) {
    const c = result.compare[s];
    out.push(`- ${s}: ${typeof c === "string" ? c : `demote=true ${c.true}, demote=false ${c.false}`}`);
  }
  const lanes = Object.entries(result.by_lane);
  if (lanes.length) {
    out.push("", `Per lane (${result.without_lane} rated merges name no lane):`, "");
    out.push(...table(lanes.flatMap(([lane, g]) => [[`${lane} demote=true`, g.true], [`${lane} demote=false`, g.false]])));
  }
  return `${out.join("\n")}\n`;
}

export class RateLimited extends Error {}
let calls = 0;

function gh(args, { raw = false, cwd } = {}) {
  if (calls >= CALL_BUDGET) throw new Error(`the call budget of ${CALL_BUDGET} is spent`);
  calls += 1;
  try {
    const text = execFileSync("gh", args, { cwd, encoding: "utf8", maxBuffer: 1 << 28, stdio: ["ignore", "pipe", "pipe"] });
    return raw ? text : JSON.parse(text);
  } catch (error) {
    const output = `${error.stderr ?? ""}${error.stdout ?? ""}`;
    const why = output.trim().split("\n")[0] || error.message;
    if (/rate limit|HTTP 429|secondary rate/i.test(output)) throw new RateLimited(`gh ${args[1] ?? ""}: ${why}`);
    throw new Error(`gh ${args.slice(0, 2).join(" ")}: ${why}`);
  }
}

const SEARCH = `query($q: String!, $after: String) {
  search(type: ISSUE, query: $q, first: 20, after: $after) {
    issueCount pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest { number mergedAt headRefOid mergeCommit { oid }
      comments(last: 100) { totalCount nodes { author { __typename login } editor { __typename login } lastEditedAt createdAt body } } } }
  }
}`;

const day = (epoch) => new Date(epoch * 1000).toISOString().slice(0, 10);

export function fetchSnapshot({ dir, branch, repo, since, until }) {
  const truncated = [];
  const log = execFileSync("git", ["-C", dir, "log", "--first-parent", `--since=@${since}`, "--format=%H%x1f%ct%x1f%s%x1f%b%x1e", branch], { encoding: "utf8", maxBuffer: 1 << 28 });
  const commits = log
    .split("\x1e")
    .map((r) => r.replace(/^\n/, ""))
    .filter(Boolean)
    .map((r) => {
      const [sha, ct, subject, body = ""] = r.split("\x1f");
      return { sha, ct: Number(ct), pr: Number(/\(#([0-9]+)\)$/.exec(subject)?.[1]) || null, subject, demote: squashRating(body), reverts: revertsOf({ subject, body }) };
    });
  const yaml = gh(["api", "-H", "Accept: application/vnd.github.raw", `repos/${repo}/contents/docs/conventions/pr-pipeline.yaml`], { raw: true });
  const identity = /^merge:\n(?:[ \t]+.*\n|\s*\n)*?[ \t]+agent-identity: ([A-Za-z0-9-]+)\[bot\]\s*$/m.exec(yaml)?.[1];
  if (!identity) throw new Error("docs/conventions/pr-pipeline.yaml names no merge.agent-identity");
  const markers = [];
  for (let from = since; from < until; from += SLICE_DAYS * 86400) {
    const q = `repo:${repo} is:pr is:merged author:app/${identity} merged:${day(from)}..${day(Math.min(from + SLICE_DAYS * 86400, until) - 1)}`;
    for (let after = null; ; ) {
      const page = gh(["api", "graphql", "-f", `query=${SEARCH}`, "-f", `q=${q}`, ...(after ? ["-f", `after=${after}`] : [])]).data.search;
      if (!after && page.issueCount > 1000) truncated.push(`${q}: ${page.issueCount} pull requests, of which a search reads 1000`);
      for (const pr of page.nodes) {
        const merge = pr.mergeCommit?.oid;
        if (!SHA.test(String(merge))) continue;
        if (pr.comments.totalCount > 100) truncated.push(`#${pr.number}: only its newest 100 comments were read`);
        const marker = readMarker(pr.comments.nodes, identity, pr.headRefOid);
        if (marker) markers.push({ pr: pr.number, merge, ...marker });
      }
      if (!page.pageInfo.hasNextPage) break;
      after = page.pageInfo.endCursor;
    }
  }
  const records = [];
  for (const creator of ["github-actions[bot]", `${identity}[bot]`]) {
    for (let page = 1; ; page += 1) {
      const batch = gh(["api", `repos/${repo}/issues?state=all&creator=${encodeURIComponent(creator)}&since=${new Date(since * 1000).toISOString()}&per_page=100&page=${page}`]);
      for (const issue of batch) {
        const record = issue.pull_request ? null : readRecord(issue.body);
        if (record) records.push(record);
      }
      if (batch.length < 100) break;
    }
  }
  return { schema: 1, repo, branch, since, until, truncated, commits, markers, records };
}

class UsageError extends Error {}

function parseArgs(argv, now) {
  const opts = { action: "run", dir: ".", format: "json" };
  const rest = [...argv];
  if (rest[0] === "fetch") opts.action = rest.shift();
  const keys = { "--repo": "dir", "--branch": "branch", "--since": "since", "--until": "until", "--format": "format", "--snapshot": "snapshot", "--out": "out" };
  while (rest.length) {
    const flag = rest.shift();
    const value = rest.shift();
    if (!keys[flag] || value === undefined) throw new UsageError(`unknown argument or missing value: ${flag}`);
    opts[keys[flag]] = value;
  }
  if (!["json", "md"].includes(opts.format)) throw new UsageError("--format is json or md");
  if (opts.action === "fetch" && !opts.out) throw new UsageError("fetch needs --out FILE");
  const epoch = (d, flag) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) throw new UsageError(`${flag} must be a YYYY-MM-DD date`);
    return Date.parse(`${d}T00:00:00Z`) / 1000;
  };
  opts.until = opts.until ? epoch(opts.until, "--until") + 86400 : Math.floor(now / 1000);
  opts.since = opts.since ? epoch(opts.since, "--since") : Math.floor((opts.until - 84 * 86400) / 86400) * 86400;
  if (!(opts.since < opts.until)) throw new UsageError("--since must come before --until");
  return opts;
}

export function main(argv, now = Date.now()) {
  let opts;
  try {
    opts = parseArgs(argv, now);
  } catch (error) {
    console.error(`merge-risk-failures: ${error.message}`);
    return 2;
  }
  try {
    let snapshot;
    if (opts.snapshot) snapshot = JSON.parse(readFileSync(opts.snapshot, "utf8"));
    else {
      const branch = opts.branch ?? execFileSync("git", ["-C", opts.dir, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], { encoding: "utf8" }).trim();
      const repo = gh(["repo", "view", "--json", "nameWithOwner"], { cwd: opts.dir }).nameWithOwner;
      snapshot = fetchSnapshot({ dir: opts.dir, branch, repo, since: opts.since, until: opts.until });
      console.error(`merge-risk-failures: ${calls} gh calls`);
    }
    if (opts.action === "fetch") {
      writeFileSync(opts.out, JSON.stringify(snapshot));
      return 0;
    }
    const result = { since: day(snapshot.since), until: day(snapshot.until - 1), truncated: snapshot.truncated ?? [], ...compute(snapshot) };
    process.stdout.write(opts.format === "md" ? `Window ${result.since} to ${result.until}.\n${result.truncated.map((t) => `PARTIAL: ${t}\n`).join("")}${renderMarkdown(result)}` : `${JSON.stringify(result, null, 2)}\n`);
    return 0;
  } catch (error) {
    console.error(`merge-risk-failures: ${error instanceof RateLimited ? "rate limited, stopped: " : ""}${error.message} (after ${calls} gh calls)`);
    return error instanceof RateLimited ? 3 : 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) process.exitCode = main(process.argv.slice(2));
