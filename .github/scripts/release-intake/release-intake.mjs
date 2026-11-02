#!/usr/bin/env node
// release-intake: the scripted halves of .github/workflows/release-intake.yml.
// No model runs here. Subcommands:
//   gate     picks the release, skips one already processed, applies the
//            per-day cap (read-only GITHUB_TOKEN with actions: read)
//   push     checks each planned branch and pushes it (mutate-branch token)
//   publish  opens one PR per pushed branch and files each handoff once
//            (publish-artifact token)
// The plan and the bundle come from the model job, so every field is data:
// names are held to fixed shapes and every commit to its plugin's paths.
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const RELEASE = /^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,5})$/;
const PLUGIN = /^[a-z0-9][a-z0-9-]{0,63}$/;
const SHA = /^[0-9a-f]{40}$/;
const KEY = /^changelog:[0-9.]+\.\.[0-9.]+:[a-z-]+:[A-Za-z0-9_./-]{1,200}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

export const branchFor = (plugin, release) => `changelog/${plugin}/v${release}`;
export const startedArtifact = (release, runId) => `release-intake-started-${release}-${runId}`;
export const doneArtifact = (release) => `release-intake-done-${release}`;
export const handoffMarker = (key) => `<!-- release-intake key=${key} -->`;

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
    (a) => a?.name?.startsWith("release-intake-started-") && now - Date.parse(a.created_at) < DAY_MS,
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

async function gate(env) {
  const repo = env.GITHUB_REPOSITORY;
  let release = env.RELEASE_INPUT ?? "";
  if (env.EVENT_NAME === "workflow_dispatch") {
    if (!RELEASE.test(release)) throw new Error("the release input is not one MAJOR.MINOR.PATCH");
  } else {
    release = newestRelease(await api("/repos/anthropics/claude-code/releases?per_page=20"));
    if (!release) throw new Error("no Claude Code release could be read");
  }
  output("release", release);
  const done = await api(`/repos/${repo}/actions/artifacts?per_page=1&name=${doneArtifact(release)}`);
  const refs = await api(`/repos/${repo}/git/matching-refs/heads/changelog/`);
  const branches = (refs ?? []).filter((r) => r.ref.endsWith(`/v${release}`));
  if ((done?.total_count ?? 0) > 0 || branches.length > 0) {
    console.log(`Claude Code ${release} was already processed; nothing to do`);
    output("proceed", "false");
    return;
  }
  const cap = Number(env.DAILY_CAP);
  if (!Number.isInteger(cap) || cap < 1) throw new Error("the per-day cap is not a positive whole number");
  const recent = await api(`/repos/${repo}/actions/artifacts?per_page=100`);
  const started = startedInWindow(recent?.artifacts ?? [], Date.now());
  if (started >= cap) {
    console.log(`::notice::release-intake started ${started} runs in the last 24 hours, at its cap of ${cap}; Claude Code ${release} waits`);
    output("proceed", "false");
    return;
  }
  output("proceed", "true");
}

async function push(env) {
  const { RELEASE: release, BASE_SHA: baseSha, PLAN_FILE, BUNDLE_FILE, REPO_DIR: repoDir, GITHUB_REPOSITORY: repo } = env;
  const plan = validatePlan(JSON.parse(readFileSync(PLAN_FILE, "utf8")), { release, baseSha });
  const pushed = [];
  if (plan.branches.length && !existsSync(BUNDLE_FILE)) throw new Error("the plan names branches and the run left no bundle");
  for (const b of plan.branches) {
    const local = `refs/release-intake/${b.plugin}`;
    git(repoDir, ["fetch", "--no-tags", BUNDLE_FILE, `${b.head_sha}:${local}`]);
    if (git(repoDir, ["rev-parse", local]) !== b.head_sha) throw new Error(`${b.branch} is not at its planned head`);
    if (git(repoDir, ["merge-base", baseSha, b.head_sha]) !== baseSha) throw new Error(`${b.branch} does not start at the base`);
    checkRawLog(git(repoDir, ["log", "--format=", "--raw", "--no-renames", "--no-abbrev", `${baseSha}..${b.head_sha}`]), b.plugin);
    if (await api(`/repos/${repo}/git/ref/heads/${b.branch}`, { allow404: true })) {
      console.log(`${b.branch} already exists; skipped`);
      continue;
    }
    // The token rides in an extraheader from the environment, never the URL or argv.
    git(repoDir, ["push", `https://github.com/${repo}.git`, `${b.head_sha}:refs/heads/${b.branch}`], {
      env: {
        ...process.env,
        GIT_CONFIG_COUNT: "1",
        GIT_CONFIG_KEY_0: "http.https://github.com/.extraheader",
        GIT_CONFIG_VALUE_0: `AUTHORIZATION: basic ${Buffer.from(`x-access-token:${env.GH_TOKEN}`).toString("base64")}`,
      },
    });
    pushed.push(b.branch);
  }
  console.log(`pushed ${pushed.length} of ${plan.branches.length} branches`);
}

async function publish(env) {
  const { RELEASE: release, BASE_SHA: baseSha, PLAN_FILE, GITHUB_REPOSITORY: repo } = env;
  const plan = validatePlan(JSON.parse(readFileSync(PLAN_FILE, "utf8")), { release, baseSha });
  const owner = repo.split("/")[0];
  let opened = 0;
  let filed = 0;
  for (const b of plan.branches) {
    const ref = await api(`/repos/${repo}/git/ref/heads/${b.branch}`, { allow404: true });
    if (ref?.object?.sha !== b.head_sha) {
      console.log(`${b.branch} is missing or not at the planned head; no pull request`);
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
  for (const h of plan.handoffs) {
    const marker = handoffMarker(h.key);
    const q = encodeURIComponent(`repo:${repo} is:issue in:body "${h.key}"`);
    const found = await api(`/search/issues?q=${q}&per_page=20`);
    if ((found?.items ?? []).some((i) => typeof i.body === "string" && i.body.includes(marker))) {
      console.log(`handoff ${h.key} is already filed`);
      continue;
    }
    await api(`/repos/${repo}/issues`, { method: "POST", body: { title: h.title, body: `${h.body}\n\n${marker}\n` } });
    filed++;
  }
  console.log(`opened ${opened} pull requests and filed ${filed} handoffs`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const commands = { gate, push, publish };
  const run = commands[process.argv[2]];
  if (!run) {
    console.error("usage: release-intake.mjs gate|push|publish");
    process.exit(2);
  }
  run(process.env).catch((error) => {
    console.log(`::error::${String(error.message).replace(/[\r\n]+/g, " ")}`);
    process.exit(1);
  });
}
