#!/usr/bin/env node
// upstream-apply-changelog: the scripted halves of .github/workflows/upstream-apply-changelog.yml.
// No model runs here. Subcommands:
//   gate     picks the release, skips one already processed, applies the
//            per-day cap (read-only GITHUB_TOKEN with actions: read)
//   push     checks each planned branch and recreates it through the Git Data
//            API as lanes App commits (mutate-branch token)
//   publish  opens one PR per pushed branch and files the release's handoffs
//            as one issue (publish-artifact token)
// The plan and the bundle come from the model job, so every field is data:
// names are held to fixed shapes and every commit to its plugin's paths.
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { createGitHubApi } from "../apply-patch/apply-patch.mjs";

export const RELEASE = /^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,5})$/;
const PLUGIN = /^[a-z0-9][a-z0-9-]{0,63}$/;
const SHA = /^[0-9a-f]{40}$/;
const KEY = /^changelog:[0-9.]+\.\.[0-9.]+:[a-z-]+:[A-Za-z0-9_./-]{1,200}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

export const branchFor = (plugin, release) => `changelog/${plugin}/v${release}`;
export const startedArtifact = (release, runId) => `upstream-apply-changelog-started-${release}-${runId}`;
export const doneArtifact = (release) => `upstream-apply-changelog-done-${release}`;
export const alreadyProcessed = (artifacts) => (artifacts?.total_count ?? 0) > 0;
export const handoffMarker = (key) => `<!-- upstream-apply-changelog key=${key} -->`;
export const releaseMarker = (release) => `<!-- upstream-apply-changelog release=${release} -->`;
const ISSUE_BODY_MAX = 65536; // GitHub's issue body limit
const TRUNCATED = "Handoff bodies are truncated proportionally to fit GitHub's 65536-character issue body limit.";
const KIND = /^[a-z][a-z-]{0,39}$/;

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

// Files a release's handoffs as one issue, found again by its release marker
// in any state. An open issue missing some keys, in its body and comments,
// gets them appended in one update, or in one comment when the body would
// pass the limit; a closed one is left alone.
export async function fileReleaseHandoffs({ repo, release, handoffs, api }) {
  if (!handoffs.length) return "no handoffs; nothing filed";
  const marker = releaseMarker(release);
  const q = encodeURIComponent(`repo:${repo} is:issue in:body "upstream-apply-changelog release=${release}"`);
  const found = await api(`/search/issues?q=${q}&per_page=20`);
  const issue = (found?.items ?? []).find((i) => typeof i.body === "string" && i.body.includes(marker));
  if (!issue) {
    const head = `${marker}\n\n`;
    const body = head + renderItems(handoffs, ISSUE_BODY_MAX - head.length);
    await api(`/repos/${repo}/issues`, { method: "POST", body: { title: releaseTitle(release, handoffs.length), body } });
    return `filed ${handoffs.length} handoffs as one issue`;
  }
  if (issue.state !== "open") return `the release issue #${issue.number} is closed; nothing filed`;
  const comments = await listComments(api, repo, issue.number);
  const have = new Set([issue.body, ...comments.map((c) => c?.body ?? "")].flatMap(keysIn));
  const missing = handoffs.filter((h) => !have.has(h.key));
  if (!missing.length) return `the release issue #${issue.number} already holds every handoff`;
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

async function api(path, { method = "GET", body, allow404 = false } = {}) {
  const res = await fetch(`${process.env.GITHUB_API_URL || "https://api.github.com"}${path}`, {
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
  // changelog-status.sh:59 prints `cap: within budget (<r> releases / <i> items)`;
  // :57 prints `releases:` space-separated, oldest first.
  if (!value("cap").startsWith("within budget")) throw new Error(`changelog-status.sh reports cap: ${value("cap") || "missing"}`);
  const versions = value("releases").split(/ +/).filter(Boolean);
  if (!versions.length || !versions.every((v) => RELEASE.test(v))) throw new Error("the status file's releases line is malformed");
  return versions;
}

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
    (a) => a?.name?.startsWith("upstream-apply-changelog-started-") && now - Date.parse(a.created_at) < DAY_MS,
  ).length;
}

export function validatePlan(plan, { release, baseSha }) {
  const fail = (why) => {
    throw new Error(`ci-plan.json: ${why}`);
  };
  if (plan?.schema !== "changelog-ci-plan/1") fail("not a changelog-ci-plan/1 plan");
  if (plan.status === "stopped") return { branches: [], handoffs: [] };
  if (plan.status !== "planned") fail("status is neither planned nor stopped");
  if (plan.range !== `${release}..${release}`) fail("its range is not this run's release");
  if (plan.base_sha !== baseSha) fail("its base_sha is not the commit the run checked out");
  const branches = Array.isArray(plan.branches) ? plan.branches : fail("branches is not a list");
  const handoffs = Array.isArray(plan.handoffs) ? plan.handoffs : fail("handoffs is not a list");
  const seen = new Set();
  for (const b of branches) {
    if (!PLUGIN.test(b?.plugin ?? "")) fail("a branch names a malformed plugin");
    if (seen.has(b.plugin)) fail(`plugin ${b.plugin} has two branches`);
    seen.add(b.plugin);
    if (b.branch !== branchFor(b.plugin, release)) fail(`${b.plugin}'s branch is not ${branchFor(b.plugin, release)}`);
    if (b.base_sha !== baseSha || !SHA.test(b.head_sha ?? "")) fail(`${b.branch} has a wrong base or head`);
    const title = b.pr?.title;
    if (typeof title !== "string" || !title.startsWith(`chore(${b.plugin}): `) || title.length > 200 || /[\r\n]/.test(title)) {
      fail(`${b.branch}'s pull request title is not chore(${b.plugin}): ...`);
    }
    if (typeof b.pr?.body !== "string" || b.pr.body.length > 60000) fail(`${b.branch}'s pull request body is missing or too long`);
  }
  const keys = new Set();
  for (const h of handoffs) {
    if (!KEY.test(h?.key ?? "") || !h.key.startsWith(`changelog:${release}..${release}:`)) fail("a handoff key is malformed");
    if (keys.has(h.key)) fail(`handoff ${h.key} appears twice`);
    keys.add(h.key);
    if (typeof h.title !== "string" || !h.title || h.title.length > 256 || /[\r\n]/.test(h.title)) fail(`${h.key} has a bad title`);
    if (typeof h.body !== "string" || h.body.length > 60000) fail(`${h.key} has a bad body`);
  }
  return { branches, handoffs };
}

// Every path a commit in base..head changes, either side of a rename, must
// sit under plugins/<plugin>/ or .changes/<plugin>/, as a regular file.
export function checkRawLog(raw, plugin) {
  const allowed = [`plugins/${plugin}/`, `.changes/${plugin}/`];
  for (const line of raw.split("\n").filter((l) => l.startsWith(":"))) {
    const [meta, ...paths] = line.split("\t");
    const [srcMode, dstMode] = meta.slice(1).split(" ");
    for (const mode of [srcMode, dstMode]) {
      if (mode !== "000000" && mode !== "100644" && mode !== "100755") {
        throw new Error(`a commit writes mode ${mode}; only regular files may change`);
      }
    }
    for (const p of paths) {
      if (!allowed.some((prefix) => p.startsWith(prefix)) || p.split("/").includes("..")) {
        throw new Error(`a commit changes ${p}, outside plugins/${plugin}/ and .changes/${plugin}/`);
      }
    }
  }
}

const git = (repo, args, extra = {}) => execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", ...extra }).trim();
const MAX_BLOB = 64 * 1024 * 1024;

// The commits in base..head, oldest first, each as its message and the files
// it changes: a deleted file has content null. A merge commit is refused.
export function readCommits(repoDir, baseSha, headSha) {
  if (git(repoDir, ["rev-list", "--min-parents=2", `${baseSha}..${headSha}`])) throw new Error("a planned branch holds a merge commit");
  return git(repoDir, ["rev-list", "--reverse", `${baseSha}..${headSha}`])
    .split("\n")
    .filter(Boolean)
    .map((sha) => ({
      message: execFileSync("git", ["-C", repoDir, "show", "-s", "--format=%B", sha], { encoding: "utf8" }),
      entries: git(repoDir, ["diff-tree", "-r", "--no-renames", "--raw", "--no-abbrev", "--no-commit-id", sha])
        .split("\n")
        .filter((line) => line.startsWith(":"))
        .map((line) => {
          const [meta, path] = line.split("\t");
          const [srcMode, dstMode, , dstSha] = meta.slice(1).split(" ");
          if (dstMode === "000000") return { path, mode: srcMode, content: null };
          return { path, mode: dstMode, content: execFileSync("git", ["-C", repoDir, "cat-file", "blob", dstSha], { maxBuffer: MAX_BLOB }) };
        }),
    }));
}

// Replays the commits through the Git Data API with no author or committer,
// so GitHub authors and signs each as the lanes App, as apply-patch does
// (apply-patch.mjs createGitHubApi). Returns the new head, whose tree must be
// the planned head's: what is pushed is exactly what the scan job scanned.
export async function replayCommits(commits, { baseSha, baseTree, headTree, api }) {
  let parent = baseSha;
  let tree = baseTree;
  for (const { message, entries } of commits) {
    const blobs = [];
    for (const { path, mode, content } of entries) {
      blobs.push({ path, mode, type: "blob", sha: content === null ? null : await api.createBlob(Buffer.from(content).toString("base64")) });
    }
    if (blobs.length) tree = await api.createTree(tree, blobs);
    parent = await api.createCommit(message, tree, [parent]);
  }
  if (tree !== headTree) throw new Error(`the replayed tree ${tree} is not the planned head's ${headTree}`);
  return parent;
}

async function gate(env) {
  const repo = env.GITHUB_REPOSITORY;
  let candidates;
  if (env.EVENT_NAME === "workflow_dispatch") {
    if (!RELEASE.test(env.RELEASE_INPUT ?? "")) throw new Error("the release input is not one MAJOR.MINOR.PATCH");
    candidates = [env.RELEASE_INPUT];
  } else {
    candidates = releasesFromStatus(readFileSync(env.STATUS_FILE, "utf8")).reverse();
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
  const recent = await api(`/repos/${repo}/actions/artifacts?per_page=100`);
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
  const plan = validatePlan(JSON.parse(readFileSync(PLAN_FILE, "utf8")), { release, baseSha });
  const writer = createGitHubApi({ token: env.GH_TOKEN, repository: repo, apiUrl: env.GITHUB_API_URL || "https://api.github.com" });
  const heads = {};
  if (plan.branches.length && !existsSync(BUNDLE_FILE)) throw new Error("the plan names branches and the run left no bundle");
  for (const b of plan.branches) {
    const local = `refs/upstream-apply-changelog/${b.plugin}`;
    git(repoDir, ["fetch", "--no-tags", BUNDLE_FILE, `${b.head_sha}:${local}`]);
    if (git(repoDir, ["rev-parse", local]) !== b.head_sha) throw new Error(`${b.branch} is not at its planned head`);
    if (git(repoDir, ["merge-base", baseSha, b.head_sha]) !== baseSha) throw new Error(`${b.branch} does not start at the base`);
    checkRawLog(git(repoDir, ["log", "--format=", "--raw", "--no-renames", "--no-abbrev", `${baseSha}..${b.head_sha}`]), b.plugin);
    const headTree = git(repoDir, ["rev-parse", `${b.head_sha}^{tree}`]);
    const existing = await api(`/repos/${repo}/git/ref/heads/${b.branch}`, { allow404: true });
    if (existing) {
      // A re-run's branch counts only when its tip holds the planned tree.
      const tip = existing.object?.sha;
      const commit = SHA.test(tip ?? "") ? await api(`/repos/${repo}/git/commits/${tip}`) : null;
      if (commit?.tree?.sha === headTree) heads[b.branch] = tip;
      console.log(`${b.branch} already exists${heads[b.branch] ? "" : " with another tree"}; not pushed`);
      continue;
    }
    const head = await replayCommits(readCommits(repoDir, baseSha, b.head_sha), {
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

async function publish(env) {
  const { RELEASE: release, BASE_SHA: baseSha, PLAN_FILE, GITHUB_REPOSITORY: repo } = env;
  const plan = validatePlan(JSON.parse(readFileSync(PLAN_FILE, "utf8")), { release, baseSha });
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
  console.log(await fileReleaseHandoffs({ repo, release, handoffs: plan.handoffs, api }));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const commands = { gate, push, publish };
  const run = commands[process.argv[2]];
  if (!run) {
    console.error("usage: upstream-apply-changelog.mjs gate|push|publish");
    process.exit(2);
  }
  run(process.env).catch((error) => {
    console.log(`::error::${String(error.message).replace(/[\r\n]+/g, " ")}`);
    process.exit(1);
  });
}
