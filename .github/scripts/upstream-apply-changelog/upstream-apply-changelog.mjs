#!/usr/bin/env node
// upstream-apply-changelog: the scripted halves of .github/workflows/upstream-apply-changelog.yml.
// No model runs here. Subcommands:
//   gate     picks the release, skips one already processed, applies the
//            per-day cap (read-only GITHUB_TOKEN with actions: read)
//   scan     checks each planned head's net diff in the scan job and stops
//            the release on a hold path (no write token)
//   push     checks each planned branch and recreates it through the Git Data
//            API as one lanes App commit on the base (mutate-branch token)
//   publish  opens one PR per pushed branch and files the release's handoffs
//            as one issue (publish-artifact token)
// The plan and each branch's tree come from the model job, so every field is
// data: names are held to fixed shapes and each branch's net diff to its
// plugin's paths, none of them a hold path. The bundle holds the scan job's
// synthetic commits only.
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createGitHubApi } from "../apply-patch/apply-patch.mjs";
import { LANES_APP_LOGIN, matchesHoldPath } from "../pr-merge/merge-holds.mjs";

export const RELEASE = /^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,5})$/;
const PLUGIN = /^[a-z0-9][a-z0-9-]{0,63}$/;
const SHA = /^[0-9a-f]{40}$/;
// The handoff key grammar ci-mode.md states verbatim; a test holds the two equal.
export const KEY = /^changelog:[0-9.]+\.\.[0-9.]+:[a-z-]+:[A-Za-z0-9_./-]{1,200}$/;
const QUOTE_MAX = 120;
const DAY_MS = 24 * 60 * 60 * 1000;

export const branchFor = (plugin, release) => `changelog/${plugin}/v${release}`;
// One name for every start record (an artifact is scoped to its run), so the
// cap lists them by name instead of paging the repository's artifacts.
export const STARTED_ARTIFACT = "upstream-apply-changelog-started";
export const doneArtifact = (release) => `upstream-apply-changelog-done-${release}`;
export const alreadyProcessed = (artifacts) => (artifacts?.total_count ?? 0) > 0;
export const handoffMarker = (key) => `<!-- upstream-apply-changelog key=${key} -->`;
export const releaseMarker = (release) => `<!-- upstream-apply-changelog release=${release} -->`;
const ISSUE_BODY_MAX = 65536; // GitHub's issue body limit
const TRUNCATED = "Handoff bodies are truncated proportionally to fit GitHub's 65536-character issue body limit.";
const KIND = /^[a-z][a-z-]{0,39}$/;
// ci-mode.md: the two reasons a plan stops before deriving any row, and
// hold-path, which the scan job sets when a planned branch changes one.
const STOP_REASONS = new Set(["cap-exceeded", "range-not-computed", "hold-path"]);
// range-not-computed can pass on a later run (the changelog fetch failed, or
// the page lags the tag), so it files nothing and leaves the release undone;
// cap-exceeded and hold-path come from the release's fixed changelog text, so
// its issue is filed and the release marked done.
export const marksDone = (stop) => stop !== "range-not-computed";

const STOP_WHY = {
  "hold-path": "a planned branch changed a hold path, so no branch was opened",
};
const stopLine = (release, stop) =>
  `The plan for Claude Code v${release} stopped (stop_reason \`${stop}\`): ${STOP_WHY[stop] ?? "no changelog row was derived and no branch was opened"}. ` +
  "The release is marked done once this issue holds its handoffs, so later runs do not take it again.";
const releaseTitle = (release, n) => `Claude Code v${release} changelog: ${n} handoff${n === 1 ? "" : "s"}`;
const keysIn = (body) => [...body.matchAll(/<!-- upstream-apply-changelog key=(\S+) -->/g)].map((m) => m[1]);

// One checklist item per handoff, its body indented under it, within `budget`
// characters: when the bodies do not fit, each is cut in proportion to its
// length and a line says so.
export function renderItems(handoffs, budget) {
  const indent = (text) => text.replace(/^(?=.)/gm, "  ");
  const item = (h, body) => {
    const kind = KIND.test(h.kind ?? "") ? h.kind : "handoff";
    return `- [ ] ${kind}: ${h.title}\n\n${body ? `${body}\n\n` : ""}  ${handoffMarker(h.key)}\n`;
  };
  const bodies = handoffs.map((h) => indent(h.body));
  const full = handoffs.map((h, i) => item(h, bodies[i])).join("\n");
  if (full.length <= budget) return full;
  const fixed = handoffs.map((h) => item(h, "")).join("\n").length + TRUNCATED.length + 2;
  const room = budget - fixed - handoffs.length * 2;
  if (room < 0) throw new Error("the handoff checklist does not fit in one issue body");
  const total = bodies.reduce((sum, b) => sum + b.length, 0);
  const cut = bodies.map((b) => b.slice(0, Math.floor((b.length * room) / total)).trimEnd());
  return `${TRUNCATED}\n\n${handoffs.map((h, i) => item(h, cut[i])).join("\n")}`;
}

// The new release issue's title and body, as publish posts them; a stopped
// plan's issue opens with its stop_reason.
export function releaseIssue(release, handoffs, stop = null) {
  const head = `${releaseMarker(release)}\n\n${stop ? `${stopLine(release, stop)}\n\n` : ""}`;
  return { title: releaseTitle(release, handoffs.length), body: head + renderItems(handoffs, ISSUE_BODY_MAX - head.length) };
}

// Every string publish can post from the plan, as plain text for the scan
// job: each pull request title and body, the new release issue, and the
// handoff items untruncated, as an append or a comment posts them.
export function publishText(plan, release) {
  const parts = plan.branches.flatMap((b) => [b.pr.title, b.pr.body]);
  if (marksDone(plan.stop_reason) && (plan.handoffs.length || plan.stop_reason)) {
    const issue = releaseIssue(release, plan.handoffs, plan.stop_reason);
    parts.push(issue.title, issue.body, renderItems(plan.handoffs, Number.POSITIVE_INFINITY));
  }
  return `${parts.join("\n\n")}\n`;
}

// Files a release's handoffs as one issue, found again by its release marker
// in any state. Only an issue the lanes App opened counts, and only key
// markers in its body and the App's comments: anyone can type a marker. An
// open issue missing some keys gets them appended in one update, or in one
// comment when the body would pass the limit; a closed one is left alone.
// A stopped plan publish files (`stop` is a stop_reason marksDone accepts)
// is marked done once this returns, so it files the issue even with no
// handoffs, and a closed issue missing a key throws instead.
export async function fileReleaseHandoffs({ repo, release, handoffs, stop = null, api }) {
  if (!handoffs.length && !stop) return "no handoffs; nothing filed";
  const marker = releaseMarker(release);
  const app = LANES_APP_LOGIN.replace(/\[bot\]$/, "");
  const q = encodeURIComponent(`repo:${repo} is:issue author:app/${app} in:body "upstream-apply-changelog release=${release}"`);
  const found = await api(`/search/issues?q=${q}&per_page=20`);
  const issue = (found?.items ?? []).find(
    (i) => i?.user?.login === LANES_APP_LOGIN && typeof i.body === "string" && i.body.includes(marker),
  );
  if (!issue) {
    await api(`/repos/${repo}/issues`, { method: "POST", body: releaseIssue(release, handoffs, stop) });
    return `filed ${handoffs.length} handoffs as one issue`;
  }
  if (issue.state !== "open" && !stop) return `the release issue #${issue.number} is closed; nothing filed`;
  const comments = await listComments(api, repo, issue.number);
  const own = comments.filter((c) => c?.user?.login === LANES_APP_LOGIN && typeof c.body === "string");
  const have = new Set([issue.body, ...own.map((c) => c.body)].flatMap(keysIn));
  const missing = handoffs.filter((h) => !have.has(h.key));
  if (!missing.length) return `the release issue #${issue.number} already holds every handoff`;
  if (issue.state !== "open") {
    throw new Error(`the release issue #${issue.number} is closed and lacks ${missing.length} handoffs; the stopped release is not marked done`);
  }
  const base = `${issue.body.trimEnd()}\n\n`;
  const items = renderItems(missing, Number.POSITIVE_INFINITY);
  if (base.length + items.length > ISSUE_BODY_MAX) {
    // The body is full: the missing items go in one comment instead.
    const head = `${marker}\n\n`;
    const body = head + renderItems(missing, ISSUE_BODY_MAX - head.length);
    await api(`/repos/${repo}/issues/${issue.number}/comments`, { method: "POST", body: { body } });
    return `commented ${missing.length} handoffs on the full release issue #${issue.number}`;
  }
  await api(`/repos/${repo}/issues/${issue.number}`, {
    method: "PATCH",
    body: { title: releaseTitle(release, have.size + missing.length), body: base + items },
  });
  return `appended ${missing.length} handoffs to the release issue #${issue.number}`;
}

const COMMENT_PAGES = 10;

// Every comment the release issue holds, read a full page at a time up to
// COMMENT_PAGES pages; more than that, or an answer that is not a list,
// throws so no key is filed twice.
async function listComments(api, repo, number) {
  const all = [];
  for (let page = 1; page <= COMMENT_PAGES; page++) {
    const batch = await api(`/repos/${repo}/issues/${number}/comments?per_page=100&page=${page}`);
    if (!Array.isArray(batch)) throw new Error(`the comments on #${number} did not come back as a list`);
    all.push(...batch);
    if (batch.length < 100) return all;
  }
  throw new Error(`#${number} has more comments than ${COMMENT_PAGES} pages hold`);
}

function output(name, value) {
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`);
}

const guardedFetch = rateLimitLatch.guard(globalThis.fetch);

export async function api(path, { method = "GET", body, allow404 = false } = {}) {
  const res = await guardedFetch(`${process.env.GITHUB_API_URL || "https://api.github.com"}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${process.env.GH_TOKEN}`,
      accept: "application/vnd.github+json",
      "x-github-api-version": "2022-11-28",
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (allow404 && res.status === 404) return null;
  if (!res.ok) throw new Error(`${method} ${path.split("?")[0]} answered ${res.status}`);
  return res.status === 204 ? null : res.json();
}

// The unread releases, oldest first, from changelog-status.sh's status file
// (the file scripts/claude-code-release-issues.sh reads): `range: up to date`
// is none; `cap: within budget` lists them on `releases:`; any other shape
// (cap exceeded, range not computed) throws, so a person handles it.
export function releasesFromStatus(text) {
  const value = (key) => text.match(new RegExp(`^${key}: (.*)$`, "m"))?.[1]?.trim() ?? "";
  if (value("range") === "up to date") return [];
  // changelog-status.sh:57 prints `cap: within budget (<r> releases / <i> items)`;
  // :55 prints `releases:` space-separated, oldest first.
  if (!value("cap").startsWith("within budget")) throw new Error(`changelog-status.sh reports cap: ${value("cap") || "missing"}`);
  const versions = value("releases").split(/ +/).filter(Boolean);
  if (!versions.length || !versions.every((v) => RELEASE.test(v))) throw new Error("the status file's releases line is malformed");
  return versions;
}

// A scheduled gate checks the done marker of at most this many unread
// releases, newest first: --ci never moves the read marker, so the unread list
// only grows, and each check is one REST call per tick. Older releases wait
// for a person to move the marker. Ten is the changelog skill's default
// replay cap (changelog-status.sh, --cap-releases).
export const SCHEDULE_WINDOW = 10;

// The releases a scheduled gate checks, newest first.
export const scheduledCandidates = (text) => releasesFromStatus(text).reverse().slice(0, SCHEDULE_WINDOW);

// The newest release by version, from the release list (newest first is not
// guaranteed, so it sorts). Tags are `v<MAJOR.MINOR.PATCH>`; any other tag is skipped.
export function newestRelease(releases) {
  const versions = releases
    .filter((r) => r && !r.draft && !r.prerelease && typeof r.tag_name === "string")
    .map((r) => r.tag_name.replace(/^v/, ""))
    .filter((v) => RELEASE.test(v));
  versions.sort((a, b) => {
    const [x, y] = [a, b].map((v) => v.split(".").map(Number));
    return x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
  });
  return versions.at(-1) ?? "";
}

// Runs started in the last 24 hours, counted from the gate's started
// artifacts, as red-main counts reverts "in any 24 hours".
export function startedInWindow(artifacts, now) {
  return artifacts.filter(
    (a) => a?.name === STARTED_ARTIFACT && now - Date.parse(a.created_at) < DAY_MS,
  ).length;
}

// The plan file parsed and checked. A parse error names no input: Node
// quotes the text it could not parse, and the plan is model output.
export function readPlan(text, ctx) {
  let plan;
  try {
    plan = JSON.parse(text);
  } catch {
    throw new Error("ci-plan.json: not valid JSON");
  }
  return validatePlan(plan, ctx);
}

// A rejected value as inert log text: cut to QUOTE_MAX characters, then
// JSON-quoted (CR, LF and every control character become escapes), with `%`
// and anything outside printable ASCII escaped, so the `::error::` line it
// lands in can neither decode a newline nor start a workflow command.
export function quote(value) {
  if (typeof value !== "string") return `(${value === null ? "null" : typeof value})`;
  const text = JSON.stringify(value.slice(0, QUOTE_MAX)).replace(/[^\x20-\x24\x26-\x7e]/g, (c) =>
    c === "%" ? "%25" : `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`,
  );
  return value.length > QUOTE_MAX ? `${text}...` : text;
}

// Messages name a field and its index; a rejected key or plugin is shown only
// through quote(), since the plan is model output and the scan job reports
// these before it scans anything.
export function validatePlan(plan, { release, baseSha }) {
  const fail = (why) => {
    throw new Error(`ci-plan.json: ${why}`);
  };
  if (plan?.schema !== "changelog-ci-plan/1") fail("schema is not changelog-ci-plan/1");
  const { status } = plan;
  if (status !== "planned" && status !== "stopped") fail("status is neither planned nor stopped");
  if (plan.range !== `${release}..${release}`) fail("range is not this run's release");
  if (plan.base_sha !== baseSha) fail("base_sha is not the commit the run checked out");
  // A stopped plan derived no rows, so it publishes no branch; its handoffs
  // (ci-mode.md: cap exceeded carries a docs-conformance one) are still
  // filed, under an issue line naming its stop_reason.
  const stopped = status === "stopped";
  const stop_reason = !stopped ? null : STOP_REASONS.has(plan.stop_reason) ? plan.stop_reason : fail("stop_reason is not cap-exceeded, range-not-computed or hold-path");
  const branches = stopped ? [] : Array.isArray(plan.branches) ? plan.branches : fail("branches is not a list");
  const handoffs = Array.isArray(plan.handoffs) ? plan.handoffs : fail("handoffs is not a list");
  const seen = new Set();
  branches.forEach((b, i) => {
    const at = `branches[${i}]`;
    if (!PLUGIN.test(b?.plugin ?? "")) fail(`${at}.plugin is malformed: ${quote(b?.plugin)}`);
    if (seen.has(b.plugin)) fail(`${at}.plugin repeats an earlier branch's plugin`);
    seen.add(b.plugin);
    if (b.branch !== branchFor(b.plugin, release)) fail(`${at}.branch is not changelog/<plugin>/v<release>`);
    if (b.base_sha !== baseSha) fail(`${at}.base_sha is not the run's base`);
    if (!SHA.test(b.head_sha ?? "") || b.head_sha === baseSha) fail(`${at}.head_sha is not a commit after the base`);
    const title = b.pr?.title;
    if (typeof title !== "string" || !title.startsWith(`chore(${b.plugin}): `) || title.length > 200 || /[\r\n]/.test(title)) {
      fail(`${at}.pr.title is not chore(<plugin>): ... on one line of at most 200 characters`);
    }
    if (typeof b.pr?.body !== "string" || b.pr.body.length > 60000) fail(`${at}.pr.body is missing or too long`);
  });
  const keys = new Set();
  handoffs.forEach((h, i) => {
    const at = `handoffs[${i}]`;
    if (!KEY.test(h?.key ?? "") || !h.key.startsWith(`changelog:${release}..${release}:`)) fail(`${at}.key is malformed: ${quote(h?.key)}`);
    if (keys.has(h.key)) fail(`${at}.key repeats an earlier handoff's key`);
    keys.add(h.key);
    if (typeof h.title !== "string" || !h.title || h.title.length > 256 || /[\r\n]/.test(h.title)) fail(`${at}.title is bad`);
    if (typeof h.body !== "string" || h.body.length > 60000) fail(`${at}.body is bad`);
  });
  return { status, stop_reason, branches, handoffs };
}

// Every path the raw diff changes, either side of a rename, must sit under
// plugins/<plugin>/ or .changes/<plugin>/, as a regular file. Messages name
// the branch index and the raw line number, never a path.
export function checkRawLog(raw, plugin, index = 0) {
  const allowed = [`plugins/${plugin}/`, `.changes/${plugin}/`];
  raw
    .split("\n")
    .filter((l) => l.startsWith(":"))
    .forEach((line, n) => {
      const at = `branches[${index}] raw line ${n + 1}`;
      const [meta, ...paths] = line.split("\t");
      const [srcMode, dstMode] = meta.slice(1).split(" ");
      for (const mode of [srcMode, dstMode]) {
        if (mode !== "000000" && mode !== "100644" && mode !== "100755") {
          throw new Error(`${at} writes a mode other than a regular file; only regular files may change`);
        }
      }
      for (const p of paths) {
        if (!allowed.some((prefix) => p.startsWith(prefix)) || p.split("/").includes("..")) {
          throw new Error(`${at} changes a path outside plugins/${plugin}/ and .changes/${plugin}/`);
        }
      }
    });
}

// The security review lane's hold-paths, which scripts/sync-hold-floor.py
// writes from the hold floor (HOLD_PATH_CLASSES in merge-holds.mjs), the
// trusted-actor list and the security review's own files. Read from the
// checkout this module runs from, never the model's tree; unreadable or empty
// throws, so nothing is published unchecked.
export const HOLD_PATHS_FILE = new URL("../../workflows/pr-review-security-hosted.yml", import.meta.url);
export function readHoldPaths(text) {
  const lines = text.split("\n");
  const at = (word) => lines.findIndex((l) => l.trimStart().startsWith(`# ${word} hold-floor hold-paths`));
  const [begin, end] = [at("BEGIN"), at("END")];
  if (begin < 0 || end < begin || lines[begin + 1]?.trim() !== "hold-paths: |") throw new Error("the hold-paths block was not found");
  const globs = lines.slice(begin + 2, end).map((l) => l.trim()).filter(Boolean);
  if (!globs.length) throw new Error("the hold-paths block lists no path");
  return globs;
}
let holdPaths;
export const loadHoldPaths = () => (holdPaths ??= readHoldPaths(readFileSync(HOLD_PATHS_FILE, "utf8")));

// Whether a raw diff changes a hold path, either side of a rename.
export const changesHoldPath = (raw, globs = loadHoldPaths()) =>
  raw
    .split("\n")
    .filter((l) => l.startsWith(":"))
    .some((line) => line.split("\t").slice(1).some((p) => globs.some((g) => matchesHoldPath(p, g))));

// The first planned branch whose net diff changes a hold path, or -1, after
// checking each one stays in its plugin. Each head must be in repoDir.
export function holdPathBranch(repoDir, baseSha, branches, globs = loadHoldPaths()) {
  return branches.findIndex((b, i) => {
    const raw = netRawDiff(repoDir, baseSha, b.head_sha);
    checkRawLog(raw, b.plugin, i);
    return changesHoldPath(raw, globs);
  });
}

// The plan text stopped on hold-path: no branch, the handoffs kept.
export const stoppedPlanText = (text) => JSON.stringify({ ...JSON.parse(text), status: "stopped", stop_reason: "hold-path", branches: [] });

const git = (repo, args, extra = {}) => execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", ...extra }).trim();
const MAX_BLOB = 64 * 1024 * 1024;

// The net raw diff base..head: what the one published commit changes, and
// what the scan job scanned. Intermediate commits are never published.
export const netRawDiff = (repoDir, baseSha, headSha) =>
  git(repoDir, ["diff-tree", "-r", "--no-renames", "--raw", "--no-abbrev", baseSha, headSha]);

// The files the net diff changes: a deleted file has content null.
export function readNetChanges(repoDir, baseSha, headSha) {
  return netRawDiff(repoDir, baseSha, headSha)
    .split("\n")
    .filter((line) => line.startsWith(":"))
    .map((line) => {
      const [meta, path] = line.split("\t");
      const [srcMode, dstMode, , dstSha] = meta.slice(1).split(" ");
      if (dstMode === "000000") return { path, mode: srcMode, content: null };
      return { path, mode: dstMode, content: execFileSync("git", ["-C", repoDir, "cat-file", "blob", dstSha], { maxBuffer: MAX_BLOB }) };
    });
}

// `git diff --numstat` marks a binary file `-\t-\t`; the scan reads text,
// so a branch with one is refused. The message names no path.
export function refuseBinary(numstat, index = 0) {
  if (numstat.split("\n").some((line) => line.startsWith("-\t-\t"))) {
    throw new Error(`branches[${index}] changes a binary file; only text is published`);
  }
}

// One commit on the base, with no author or committer, so GitHub authors and
// signs it as the lanes App, as apply-patch does (apply-patch.mjs
// createGitHubApi). Its message is the scanned pull request title and its
// tree must be the planned head's: what is pushed is exactly what the scan
// job scanned. Returns the new commit.
export async function commitNetTree(changes, { message, baseSha, baseTree, headTree, api }) {
  if (!changes.length) throw new Error("a planned branch changes nothing against the base");
  const entries = [];
  for (const { path, mode, content } of changes) {
    entries.push({ path, mode, type: "blob", sha: content === null ? null : await api.createBlob(Buffer.from(content).toString("base64")) });
  }
  const tree = await api.createTree(baseTree, entries);
  if (tree !== headTree) throw new Error(`the built tree ${tree} is not the planned head's ${headTree}`);
  return api.createCommit(message, tree, [baseSha]);
}

const SYNTHETIC_ENV = {
  GIT_AUTHOR_NAME: "upstream-apply-changelog",
  GIT_AUTHOR_EMAIL: "upstream-apply-changelog@users.noreply.github.com",
  GIT_AUTHOR_DATE: "1970-01-01T00:00:00Z",
  GIT_COMMITTER_NAME: "upstream-apply-changelog",
  GIT_COMMITTER_EMAIL: "upstream-apply-changelog@users.noreply.github.com",
  GIT_COMMITTER_DATE: "1970-01-01T00:00:00Z",
};
export const SYNTHETIC_MESSAGE = "upstream-apply-changelog scanned tree";

// The scan job's stand-in for each planned head: one commit on the base
// holding the head's tree, with a fixed identity, date and message, bundled
// alone. The bundle push gets then carries no model commit, header, merge or
// intermediate blob, only what the scan read as the net diff. Returns each
// branch's { commit, tree } in plan order.
export function syntheticBundle(repoDir, baseSha, heads, bundlePath) {
  const env = { ...process.env, ...SYNTHETIC_ENV };
  const quiet = { stdio: ["ignore", "pipe", "pipe"] };
  const made = heads.map((head, i) => {
    const tree = git(repoDir, ["rev-parse", "--verify", `${head}^{tree}`], quiet);
    const commit = git(repoDir, ["commit-tree", "--no-gpg-sign", tree, "-p", baseSha, "-m", SYNTHETIC_MESSAGE], { env, ...quiet });
    if (git(repoDir, ["rev-parse", `${commit}^{tree}`], quiet) !== tree) throw new Error(`branches[${i}]'s synthetic commit does not hold its head's tree`);
    git(repoDir, ["update-ref", `refs/synthetic/${i}`, commit], quiet);
    return { commit, tree };
  });
  git(repoDir, ["bundle", "create", "--quiet", bundlePath, `^${baseSha}`, ...heads.map((_, i) => `refs/synthetic/${i}`)], quiet);
  return made;
}

// The scan job's synthetic output: one { commit, tree } per planned branch.
export function readSynthetic(text, count) {
  let list;
  try {
    list = JSON.parse(text || "[]");
  } catch {
    throw new Error("the scan job's synthetic commits are not JSON");
  }
  if (!Array.isArray(list) || list.length !== count || !list.every((s) => SHA.test(s?.commit ?? "") && SHA.test(s?.tree ?? ""))) {
    throw new Error("the scan job's synthetic commits do not match the plan's branches");
  }
  return list;
}

// Fetches a branch's synthetic commit from the scanned bundle and checks it
// is one commit on the base holding the tree the scan recorded.
export function fetchSynthetic(repoDir, bundleFile, baseSha, { commit, tree }, local, i) {
  git(repoDir, ["fetch", "--quiet", "--no-tags", bundleFile, `${commit}:${local}`]);
  if (git(repoDir, ["rev-parse", local]) !== commit) throw new Error(`branches[${i}] is not at its synthetic commit`);
  if (git(repoDir, ["rev-list", "--parents", "-n", "1", commit]) !== `${commit} ${baseSha}`) throw new Error(`branches[${i}] is not one commit on the base`);
  if (git(repoDir, ["rev-parse", `${commit}^{tree}`]) !== tree) throw new Error(`branches[${i}] does not hold the scanned tree`);
  return commit;
}

async function gate(env) {
  const repo = env.GITHUB_REPOSITORY;
  let candidates;
  if (env.EVENT_NAME === "workflow_dispatch") {
    if (!RELEASE.test(env.RELEASE_INPUT ?? "")) throw new Error("the release input is not one MAJOR.MINOR.PATCH");
    candidates = [env.RELEASE_INPUT];
  } else {
    candidates = scheduledCandidates(readFileSync(env.STATUS_FILE, "utf8"));
  }
  let release = "";
  for (const candidate of candidates) {
    const done = await api(`/repos/${repo}/actions/artifacts?per_page=1&name=${doneArtifact(candidate)}`);
    // Only the done marker skips a release: push skips a branch that exists
    // and publish opens a pull request a pushed branch lacks, so a run after a
    // failed publish finishes the work instead of stranding the branch.
    if (alreadyProcessed(done)) {
      console.log(`Claude Code ${candidate} was already processed`);
      continue;
    }
    release = candidate;
    break;
  }
  if (!release) {
    console.log("no unprocessed Claude Code release; nothing to do");
    output("proceed", "false");
    return;
  }
  output("release", release);
  const cap = Number(env.DAILY_CAP);
  if (!Number.isInteger(cap) || cap < 1) throw new Error("the per-day cap is not a positive whole number");
  const recent = await api(`/repos/${repo}/actions/artifacts?per_page=100&name=${STARTED_ARTIFACT}`);
  const started = startedInWindow(recent?.artifacts ?? [], Date.now());
  if (started >= cap) {
    console.log(`::notice::upstream-apply-changelog started ${started} runs in the last 24 hours, at its cap of ${cap}; Claude Code ${release} waits`);
    output("proceed", "false");
    return;
  }
  output("proceed", "true");
}

async function push(env) {
  const { RELEASE: release, BASE_SHA: baseSha, PLAN_FILE, BUNDLE_FILE, REPO_DIR: repoDir, GITHUB_REPOSITORY: repo } = env;
  const plan = readPlan(readFileSync(PLAN_FILE, "utf8"), { release, baseSha });
  const writer = createGitHubApi({ token: env.GH_TOKEN, repository: repo, apiUrl: env.GITHUB_API_URL || "https://api.github.com" });
  const heads = {};
  if (plan.branches.length && !existsSync(BUNDLE_FILE)) throw new Error("the plan names branches and the run left no bundle");
  // The bundle holds the scan job's synthetic commits only, never the
  // model's heads, which push never reads.
  const synthetic = readSynthetic(env.SYNTHETIC, plan.branches.length);
  for (const [i, b] of plan.branches.entries()) {
    const local = `refs/upstream-apply-changelog/${b.plugin}`;
    const commit = fetchSynthetic(repoDir, BUNDLE_FILE, baseSha, synthetic[i], local, i);
    const raw = netRawDiff(repoDir, baseSha, commit);
    checkRawLog(raw, b.plugin, i);
    if (changesHoldPath(raw)) throw new Error(`branches[${i}] changes a hold path; the scan job should have stopped the release`);
    refuseBinary(git(repoDir, ["diff", "--numstat", "--no-renames", baseSha, commit]), i);
    const headTree = synthetic[i].tree;
    const existing = await api(`/repos/${repo}/git/ref/heads/${b.branch}`, { allow404: true });
    if (existing) {
      // A re-run's branch counts only when its tip holds the planned tree.
      const tip = existing.object?.sha;
      const commit = SHA.test(tip ?? "") ? await api(`/repos/${repo}/git/commits/${tip}`) : null;
      if (commit?.tree?.sha === headTree) {
        heads[b.branch] = tip;
        console.log(`${b.branch} already exists at the planned tree; not pushed`);
        continue;
      }
      // Another tree is an earlier run's work: done once it has a pull
      // request, else stranded, so the run fails before the done marker.
      const prs = await api(`/repos/${repo}/pulls?state=all&head=${repo.split("/")[0]}:${encodeURIComponent(b.branch)}`);
      if (!prs?.length) throw new Error(`branches[${i}] already exists with another tree and no pull request; open one for it or delete it, then dispatch again`);
      console.log(`${b.branch} already has pull request #${prs[0].number} with another tree; not pushed`);
      continue;
    }
    const head = await commitNetTree(readNetChanges(repoDir, baseSha, commit), {
      message: b.pr.title,
      baseSha,
      baseTree: git(repoDir, ["rev-parse", `${baseSha}^{tree}`]),
      headTree,
      api: writer,
    });
    await writer.createRef(`refs/heads/${b.branch}`, head);
    heads[b.branch] = head;
  }
  output("heads", JSON.stringify(heads));
  console.log(`${Object.keys(heads).length} of ${plan.branches.length} branches are at their planned tree`);
}

// The scan job's path check, after it fetched each planned head into REPO_DIR.
// A branch outside its plugin throws; one changing a hold path rewrites the
// plan in IN to stopped (hold-path) with no branch, and empties heads.txt and
// rewrites publish.txt to match, so the scans read what push and publish get.
async function scan(env) {
  const { IN, RELEASE: release, BASE_SHA: baseSha, REPO_DIR: repoDir } = env;
  const text = readFileSync(`${IN}/plan.json`, "utf8");
  const plan = readPlan(text, { release, baseSha });
  // Only this check sets hold-path; the model's plan may not claim it.
  if (plan.stop_reason === "hold-path") throw new Error("ci-plan.json: stop_reason hold-path is set by the scan job, not the plan");
  const held = holdPathBranch(repoDir, baseSha, plan.branches);
  if (held < 0) {
    console.log(`${plan.branches.length} branches stay in their plugins and change no hold path`);
    return;
  }
  const stopped = stoppedPlanText(text);
  writeFileSync(`${IN}/plan.json`, stopped);
  writeFileSync(`${IN}/heads.txt`, "");
  writeFileSync(`${IN}/publish.txt`, publishText(readPlan(stopped, { release, baseSha }), release));
  console.log(`::warning::branches[${held}] changes a hold path; Claude Code v${release} stops with stop_reason hold-path and no branch is opened`);
}

async function publish(env) {
  const { RELEASE: release, BASE_SHA: baseSha, PLAN_FILE, GITHUB_REPOSITORY: repo } = env;
  const plan = readPlan(readFileSync(PLAN_FILE, "utf8"), { release, baseSha });
  const owner = repo.split("/")[0];
  // push's heads output: each branch it pushed or found at the planned tree.
  const heads = JSON.parse(env.HEADS || "{}");
  let opened = 0;
  for (const b of plan.branches) {
    const ref = await api(`/repos/${repo}/git/ref/heads/${b.branch}`, { allow404: true });
    if (!SHA.test(heads[b.branch] ?? "") || ref?.object?.sha !== heads[b.branch]) {
      console.log(`${b.branch} is missing or not at the head push left; no pull request`);
      continue;
    }
    const prs = await api(`/repos/${repo}/pulls?state=all&head=${owner}:${encodeURIComponent(b.branch)}`);
    if (prs.length) {
      console.log(`${b.branch} already has pull request #${prs[0].number}`);
      continue;
    }
    await api(`/repos/${repo}/pulls`, { method: "POST", body: { title: b.pr.title, body: b.pr.body, head: b.branch, base: "main" } });
    opened++;
  }
  console.log(`opened ${opened} pull requests`);
  // A deterministic stop's release is marked done once its issue holds every
  // handoff; a filing that fails throws, and the next run takes it again.
  if (!marksDone(plan.stop_reason)) {
    console.log(`::notice::the plan for Claude Code v${release} stopped (${plan.stop_reason}); nothing filed, and the next run takes it again`);
    output("done", "false");
    return;
  }
  console.log(await fileReleaseHandoffs({ repo, release, handoffs: plan.handoffs, stop: plan.stop_reason, api }));
  output("done", "true");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const commands = { gate, scan, push, publish };
  const run = commands[process.argv[2]];
  if (!run) {
    console.error("usage: upstream-apply-changelog.mjs gate|scan|push|publish");
    process.exit(2);
  }
  run(process.env).catch((error) => {
    console.log(`::error::${String(error.message).replace(/[\r\n]+/g, " ")}`);
    process.exit(1);
  });
}
