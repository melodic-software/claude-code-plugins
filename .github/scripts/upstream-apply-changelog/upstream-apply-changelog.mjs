#!/usr/bin/env node
// upstream-apply-changelog: the scripted halves of .github/workflows/upstream-apply-changelog.yml.
// No model runs here. Subcommands:
//   gate     picks the release, skips one already processed, applies the
//            per-day cap (read-only GITHUB_TOKEN with actions: read)
//   scan     checks each planned head's net diff in the scan job and stops
//            the release on a hold path (no write token)
//   push     checks each planned branch and recreates it through the Git Data
//            API as one lanes App commit on the base (mutate-branch token)
//   publish  opens one PR per pushed branch and files one issue per handoff
//            row, plus a stopped plan's stop notice (publish-artifact token)
// The plan and each branch's tree come from the apply-changelog job, so every field is
// data: names are held to fixed shapes and each branch's net diff to its
// plugin's paths, none of them a hold path. The bundle holds the scan job's
// synthetic commits only. The plan and how publish files it:
// https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/changelog/context/ci-mode.md#the-plan
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
const DAY_MS = 24 * 60 * 60 * 1000;

export const branchFor = (plugin, release) => `changelog/${plugin}/v${release}`;
// One name for every start record (an artifact is scoped to its run), so the
// cap lists them by name instead of paging the repository's artifacts.
export const STARTED_ARTIFACT = "upstream-apply-changelog-started";
export const doneArtifact = (release) => `upstream-apply-changelog-done-${release}`;
export const alreadyProcessed = (artifacts) => (artifacts?.total_count ?? 0) > 0;
export const handoffMarker = (key) => `<!-- upstream-apply-changelog key=${key} -->`;
export const releaseMarker = (release) => `<!-- upstream-apply-changelog release=${release} -->`;
export const SOURCE_LABEL = "source: upstream-apply-changelog";
const KIND = /^[a-z][a-z-]{0,39}$/;
const REASON_MAX = 500;
// ci-mode.md: the two reasons a plan stops before deriving any row, and
// hold-path, which the scan job sets when a planned branch changes one.
const STOP_REASONS = new Set(["cap-exceeded", "range-not-computed", "hold-path"]);
// range-not-computed can pass on a later run (the changelog fetch failed, or
// the page lags the tag), so it files nothing and leaves the release undone;
// cap-exceeded and hold-path come from the release's fixed changelog text, so
// its stop notice and rows are filed and the release marked done
// (https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/changelog/context/ci-mode.md#the-plan).
export const marksDone = (stop) => stop !== "range-not-computed";

const STOP_WHY = {
  "hold-path": "a planned branch changed a hold path, so no branch was opened",
};
const stopLine = (release, stop) =>
  `The plan for Claude Code v${release} stopped (stop_reason \`${stop}\`): ${STOP_WHY[stop] ?? "no changelog row was derived and no branch was opened"}. ` +
  "Any handoff rows it has are filed one issue per row. This notice holds no row and no `source:` label, so intake leaves it for a person. " +
  "The release is marked done once this notice and every row issue are filed, so later runs do not take it again.";
const ISSUE_TYPE = "Task";
const keysIn = (body) => [...body.matchAll(/<!-- upstream-apply-changelog key=(\S+) -->/g)].map((m) => m[1]);
const DRIFT_LINE = "Drift key: ";
const DRIFT_KEY = /^[A-Za-z0-9_.:@/-]{1,200}$/;
const driftLines = (body) => body.split("\n").map((l) => l.trim()).filter((l) => l.startsWith(DRIFT_LINE)).map((l) => l.slice(DRIFT_LINE.length));
export const driftKeyOf = (body) => driftLines(body).find((k) => DRIFT_KEY.test(k)) ?? null;

async function openDriftIssue(api, repo, driftKey) {
  const app = LANES_APP_LOGIN.replace(/\[bot\]$/, "");
  const q = encodeURIComponent(`repo:${repo} is:issue is:open author:app/${app} in:body "${DRIFT_LINE}${driftKey}"`);
  const found = await api(`/search/issues?q=${q}&per_page=100`);
  return (found?.items ?? []).find(
    (i) => i?.user?.login === LANES_APP_LOGIN && i.state === "open" && typeof i.body === "string" && driftLines(i.body).includes(driftKey),
  );
}

async function withoutOpenDrift(api, repo, handoffs) {
  const open = new Map();
  const kept = [];
  let skipped = 0;
  for (const h of handoffs) {
    const driftKey = driftKeyOf(h.body);
    if (driftKey && !open.has(driftKey)) open.set(driftKey, await openDriftIssue(api, repo, driftKey));
    const issue = driftKey && open.get(driftKey);
    if (issue) {
      skipped++;
      console.log(`${h.key}: drift key ${driftKey} is already open in #${issue.number}; not filed again`);
    } else kept.push(h);
  }
  return { kept, skipped };
}

// A native-overlap verdict is never the lane's
// (https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/audit-native-overlap/SKILL.md,
// "Never auto-verdict"). Admission refuses a body line opening with `Hold:`
// (admit.mjs BODY_HOLD), so a nomination has no agent-ready path.
export const NOMINATION_HOLD =
  "Hold: a replace nomination from the upstream-apply-changelog lane. A native-overlap verdict is written by a person, " +
  "or a session acting on the owner's recorded direction (/harness-ops:audit-native-overlap, \"Never auto-verdict\"), " +
  "so this issue has no agent-ready path. Run /harness-ops:audit-native-overlap on the owner surface to record a keep or replace verdict; removing this line lifts the hold.";
const ROUTE = {
  issue: "Route: an ordinary issue; intake and review decide any hold.",
  nomination: "Route: a nomination for /harness-ops:audit-native-overlap, never lane work.",
};
const lensOf = (key) => key.split(":")[2];
const kindOf = (h) => (KIND.test(h.kind ?? "") ? h.kind : "handoff");
const oneLine = (text) => text.replace(/\s+/g, " ").trim();
const reasonOf = (h) => (typeof h.reason === "string" && oneLine(h.reason) ? oneLine(h.reason).slice(0, REASON_MAX) : "none given");

// The route per lens or kind:
// https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/changelog/context/ci-mode.md#the-plan
export function routeOf(h) {
  const lens = lensOf(h.key);
  if (lens === "docs-lag" || h.kind === "docs-lag") return "log";
  if (lens === "replace" || h.kind === "nomination") return "nomination";
  return "issue";
}

export function rowIssue(h) {
  const route = routeOf(h);
  const head = [
    handoffMarker(h.key),
    "",
    ...(route === "nomination" ? [NOMINATION_HOLD, ""] : []),
    `Lens: \`${lensOf(h.key)}\``,
    `Handoff reason (\`${kindOf(h)}\`): ${reasonOf(h)}`,
    ROUTE[route],
    "",
  ];
  return { title: h.title, type: ISSUE_TYPE, labels: [SOURCE_LABEL], body: `${head.join("\n")}\n${h.body}` };
}

const docsLagLine = (h) => `docs-lag, not filed (an upstream docs gap): \`${h.key}\` ${h.title}`;

export const stopIssue = (release, stop) => ({
  title: `Claude Code v${release} changelog: plan stopped (${stop})`,
  type: ISSUE_TYPE,
  body: `${releaseMarker(release)}\n\n${stopLine(release, stop)}\n`,
});

// Every string publish can post from the plan, as plain text for the scan
// job: each pull request title and body, and the issue strings and summary
// lines fileHandoffs can post
// (https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/changelog/context/ci-mode.md#the-plan).
export function publishText(plan, release) {
  const parts = plan.branches.flatMap((b) => [b.pr.title, b.pr.body]);
  if (marksDone(plan.stop_reason)) {
    if (plan.stop_reason) {
      const notice = stopIssue(release, plan.stop_reason);
      parts.push(notice.title, notice.body);
    }
    for (const h of plan.handoffs) {
      if (routeOf(h) === "log") parts.push(docsLagLine(h));
      else {
        const issue = rowIssue(h);
        parts.push(issue.title, issue.body);
      }
    }
  }
  return `${parts.join("\n\n")}\n`;
}

const APP_AUTHOR = `author:app/${LANES_APP_LOGIN.replace(/\[bot\]$/, "")}`;
const SEARCH_PAGES = 10;
const ownOpen = (i) => i?.user?.login === LANES_APP_LOGIN && i.state === "open" && typeof i.body === "string";

const COMMENT_PAGES = 10;

// An older per-release checklist issue moved the rows its full body could not
// hold into lanes App comments, which no body search reads
// (https://docs.github.com/en/rest/search/search#search-issues-and-pull-requests).
// More comments than COMMENT_PAGES pages hold, or an answer that is not a
// list, throws so no key is filed twice.
async function commentKeys(api, repo, number, open) {
  for (let page = 1; page <= COMMENT_PAGES; page++) {
    const batch = await api(`/repos/${repo}/issues/${number}/comments?per_page=100&page=${page}`);
    if (!Array.isArray(batch)) throw new Error(`the comments on #${number} did not come back as a list`);
    for (const c of batch) {
      if (c?.user?.login === LANES_APP_LOGIN && typeof c.body === "string") for (const k of keysIn(c.body)) if (!open.has(k)) open.set(k, number);
    }
    if (batch.length < 100) return;
  }
  throw new Error(`#${number} has more comments than ${COMMENT_PAGES} pages hold`);
}

async function legacyCommentKeys(api, repo, release, open) {
  const q = encodeURIComponent(`repo:${repo} is:issue is:open ${APP_AUTHOR} in:body "upstream-apply-changelog release=${release}"`);
  const items = (await api(`/search/issues?q=${q}&per_page=100`))?.items;
  if (!Array.isArray(items)) throw new Error("the legacy release-issue search did not come back as a list");
  for (const i of items.filter(ownOpen)) if (i.body.includes(releaseMarker(release))) await commentKeys(api, repo, i.number, open);
}

// Keys carry the release, so one search finds them all, an older per-release
// checklist's included, and that checklist's comments are read too. The search
// API returns at most 1000 results
// (https://docs.github.com/en/rest/search/search#about-search), so past that
// it throws rather than file a key twice.
async function openKeys(api, repo, release) {
  const q = encodeURIComponent(`repo:${repo} is:issue is:open ${APP_AUTHOR} in:body "upstream-apply-changelog key=changelog:${release}..${release}"`);
  const open = new Map();
  for (let page = 1; page <= SEARCH_PAGES; page++) {
    const items = (await api(`/search/issues?q=${q}&per_page=100&page=${page}`))?.items;
    if (!Array.isArray(items)) throw new Error("the open-key search did not come back as a list");
    for (const i of items.filter(ownOpen)) for (const k of keysIn(i.body)) if (!open.has(k)) open.set(k, i.number);
    if (items.length < 100) {
      await legacyCommentKeys(api, repo, release, open);
      return open;
    }
  }
  throw new Error(`more open issues hold this release's keys than ${SEARCH_PAGES} search pages return`);
}

// GitHub drops a type or label the token may not set without an error
// (https://docs.github.com/en/rest/issues/issues#create-an-issue).
function checkFiled(filed, labeled) {
  if (filed?.type?.name !== ISSUE_TYPE) console.log(`::warning::#${filed?.number} came back without Issue Type ${ISSUE_TYPE}`);
  if (labeled && !(filed?.labels ?? []).some((l) => l?.name === SOURCE_LABEL)) console.log(`::warning::#${filed?.number} came back without the label ${SOURCE_LABEL}`);
}

async function fileStopNotice(api, repo, release, stop) {
  const marker = releaseMarker(release);
  const q = encodeURIComponent(`repo:${repo} is:issue ${APP_AUTHOR} in:body "upstream-apply-changelog release=${release}"`);
  const found = await api(`/search/issues?q=${q}&per_page=20`);
  const issue = (found?.items ?? []).find((i) => i?.user?.login === LANES_APP_LOGIN && typeof i.body === "string" && i.body.includes(marker));
  if (issue) return `the stop notice #${issue.number} is already filed`;
  checkFiled(await api(`/repos/${repo}/issues`, { method: "POST", body: stopIssue(release, stop) }), false);
  return `filed the stop notice (${stop})`;
}

const count = (n, one, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

// Any failed read or write throws, so the release is not marked done and the
// next run, which skips what is open, finishes it
// (https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/changelog/context/ci-mode.md#the-plan).
export async function fileHandoffs({ repo, release, handoffs: planned, stop = null, api, summary = () => {} }) {
  if (!planned.length && !stop) return "no handoffs; nothing filed";
  const said = stop ? [await fileStopNotice(api, repo, release, stop)] : [];
  const logged = planned.filter((h) => routeOf(h) === "log");
  for (const h of logged) {
    console.log(docsLagLine(h));
    summary(docsLagLine(h));
  }
  const { kept, skipped } = await withoutOpenDrift(api, repo, planned.filter((h) => routeOf(h) !== "log"));
  const open = kept.length ? await openKeys(api, repo, release) : new Map();
  let filed = 0;
  for (const h of kept) {
    if (open.has(h.key)) {
      console.log(`${h.key}: already open in #${open.get(h.key)}; not filed again`);
      continue;
    }
    checkFiled(await api(`/repos/${repo}/issues`, { method: "POST", body: rowIssue(h) }), true);
    filed++;
  }
  said.push(`filed ${count(filed, "handoff issue")}`);
  if (kept.length > filed) said.push(`${kept.length - filed} already open`);
  if (skipped) said.push(`${count(skipped, "drift key")} already open`);
  if (logged.length) said.push(`${count(logged.length, "docs-lag row")} logged`);
  return said.join("; ");
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

// Every pull request, in any state, whose head is this branch.
const pullsFor = (repo, branch) => api(`/repos/${repo}/pulls?state=all&head=${repo.split("/")[0]}:${encodeURIComponent(branch)}`);

// The unread releases, oldest first, from changelog-status.sh's status file:
// `range: up to date` is none; `cap: within budget` lists them on `releases:`; any other shape
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

// Which part of a handoff key breaks KEY or the release prefix, with its
// length; never any of its text.
export function keyProblem(key, release) {
  if (typeof key !== "string") return "is not a string";
  const prefix = `changelog:${release}..${release}:`;
  const size = `(${key.length} characters)`;
  if (!key.startsWith(prefix)) return `does not start with ${prefix} ${size}`;
  const rest = key.slice(prefix.length);
  const colon = rest.indexOf(":");
  const lens = colon < 0 ? rest : rest.slice(0, colon);
  if (!/^[a-z-]+$/.test(lens)) return `has a lens that is empty or has characters outside [a-z-] ${size}`;
  const surface = colon < 0 ? "" : rest.slice(colon + 1);
  if (!surface) return `has an empty surface ${size}`;
  if (surface.length > 200) return `has a surface over 200 characters ${size}`;
  if (!/^[A-Za-z0-9_./-]+$/.test(surface)) return `has a surface with characters outside [A-Za-z0-9_./-] ${size}`;
  return KEY.test(key) ? null : `does not match the key grammar ${size}`;
}

// Which PLUGIN rule a plugin name breaks, with its length; never its text.
export function pluginProblem(plugin) {
  if (typeof plugin !== "string") return "is not a string";
  const size = `(${plugin.length} characters)`;
  if (!plugin) return "is empty";
  if (plugin.length > 64) return `is over 64 characters ${size}`;
  if (!/^[a-z0-9]/.test(plugin)) return `does not start with [a-z0-9] ${size}`;
  if (!PLUGIN.test(plugin)) return `has characters outside [a-z0-9-] ${size}`;
  return null;
}

const ITEM_IDS = /^(?:Items: )?\d+\.\d+\.\d+-\d{3}(?:, \d+\.\d+\.\d+-\d{3})*$/;
const FILED_BY = /^Filed by \/harness-ops:changelog apply \(native drift, [0-9.]+\.\.[0-9.]+\)$/;
const SENTENCE_MAX = 500;

// A handoff body is item ids and the required sentence, never changelog text
// (https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/changelog/context/ci-mode.md#the-plan).
// A native-drift body also holds its script-built lines: quoted `>` data, the
// `Drift key:` line and the `Filed by` line. Any other line is dropped, so
// model text outside that shape is never posted.
export function boundBody(h) {
  const sentence = typeof h.required_sentence === "string" ? h.required_sentence.trim() : "";
  const drift = lensOf(h.key) === "native-drift";
  const keep = (line) => {
    const t = line.trim();
    if (!t || ITEM_IDS.test(t) || (sentence && t === sentence)) return true;
    if (!drift) return false;
    return t.startsWith("> ") || FILED_BY.test(t) || (t.startsWith(DRIFT_LINE) && DRIFT_KEY.test(t.slice(DRIFT_LINE.length)));
  };
  return h.body.split(/\r?\n/).filter(keep).join("\n").trim();
}

// Every message names a field and its index, never a value: the plan is
// model output and the scan job reports these before it scans anything.
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
    const badPlugin = pluginProblem(b?.plugin);
    if (badPlugin) fail(`${at}.plugin ${badPlugin}`);
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
    const badKey = keyProblem(h?.key, release);
    if (badKey) fail(`${at}.key ${badKey}`);
    if (keys.has(h.key)) fail(`${at}.key repeats an earlier handoff's key`);
    keys.add(h.key);
    if (typeof h.title !== "string" || !h.title || h.title.length > 256 || /[\r\n]/.test(h.title)) fail(`${at}.title is bad`);
    if (typeof h.body !== "string" || h.body.length > 60000) fail(`${at}.body is bad`);
    const sentence = h.required_sentence;
    if (sentence != null && (typeof sentence !== "string" || sentence.length > SENTENCE_MAX || /[\r\n]/.test(sentence))) {
      fail(`${at}.required_sentence is not one line of at most ${SENTENCE_MAX} characters`);
    }
  });
  return { status, stop_reason, branches, handoffs: handoffs.map((h) => ({ ...h, body: boundBody(h) })) };
}

// The change lines of a raw diff (`:<modes> <shas> <status>\t<path>...`).
const rawLines = (raw) => raw.split("\n").filter((l) => l.startsWith(":"));

// Every path the raw diff changes, either side of a rename, must sit under
// plugins/<plugin>/ or .changes/<plugin>/, as a regular file. Messages name
// the branch index and the raw line number, never a path.
export function checkRawLog(raw, plugin, index = 0) {
  const allowed = [`plugins/${plugin}/`, `.changes/${plugin}/`];
  rawLines(raw).forEach((line, n) => {
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
  rawLines(raw).some((line) => line.split("\t").slice(1).some((p) => globs.some((g) => matchesHoldPath(p, g))));

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
  return rawLines(netRawDiff(repoDir, baseSha, headSha)).map((line) => {
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
    if (!alreadyProcessed(done)) {
      release = candidate;
      break;
    }
    console.log(`Claude Code ${candidate} was already processed`);
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
  const writer = createGitHubApi({ token: env.GH_TOKEN, repository: repo, apiUrl: env.GITHUB_API_URL || "https://api.github.com", fetch: guardedFetch });
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
      const tipCommit = SHA.test(tip ?? "") ? await api(`/repos/${repo}/git/commits/${tip}`) : null;
      if (tipCommit?.tree?.sha === headTree) {
        heads[b.branch] = tip;
        console.log(`${b.branch} already exists at the planned tree; not pushed`);
        continue;
      }
      // Another tree is an earlier run's work: done once it has a pull
      // request, else stranded, so the run fails before the done marker.
      const prs = await pullsFor(repo, b.branch);
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

async function planFiles(env) {
  const { IN, RELEASE: release, BASE_SHA: baseSha } = env;
  const plan = readPlan(readFileSync(`${IN}/plan.json`, "utf8"), { release, baseSha });
  writeFileSync(`${IN}/heads.txt`, plan.branches.map((b) => `${b.head_sha}\n`).join(""));
  writeFileSync(`${IN}/publish.txt`, publishText(plan, release));
  console.log(`${plan.branches.length} branches, ${plan.handoffs.length} handoffs`);
}

async function synthetic(env) {
  const heads = readFileSync(`${env.IN}/heads.txt`, "utf8").split("\n").filter(Boolean);
  console.log(JSON.stringify(syntheticBundle(env.REPO_DIR, env.BASE_SHA, heads, `${env.OUT}/branches.bundle`)));
}

async function publish(env) {
  const { RELEASE: release, BASE_SHA: baseSha, PLAN_FILE, GITHUB_REPOSITORY: repo } = env;
  const plan = readPlan(readFileSync(PLAN_FILE, "utf8"), { release, baseSha });
  // push's heads output: each branch it pushed or found at the planned tree.
  const heads = JSON.parse(env.HEADS || "{}");
  let opened = 0;
  for (const b of plan.branches) {
    const ref = await api(`/repos/${repo}/git/ref/heads/${b.branch}`, { allow404: true });
    if (!SHA.test(heads[b.branch] ?? "") || ref?.object?.sha !== heads[b.branch]) {
      console.log(`${b.branch} is missing or not at the head push left; no pull request`);
      continue;
    }
    const prs = await pullsFor(repo, b.branch);
    if (prs.length) {
      console.log(`${b.branch} already has pull request #${prs[0].number}`);
      continue;
    }
    await api(`/repos/${repo}/pulls`, { method: "POST", body: { title: b.pr.title, body: b.pr.body, head: b.branch, base: "main" } });
    opened++;
  }
  console.log(`opened ${opened} pull requests`);
  if (!marksDone(plan.stop_reason)) {
    console.log(`::notice::the plan for Claude Code v${release} stopped (${plan.stop_reason}); nothing filed, and the next run takes it again`);
    output("done", "false");
    return;
  }
  const summary = (line) => env.GITHUB_STEP_SUMMARY && appendFileSync(env.GITHUB_STEP_SUMMARY, `- ${line}\n`);
  console.log(await fileHandoffs({ repo, release, handoffs: plan.handoffs, stop: plan.stop_reason, api, summary }));
  output("done", "true");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const commands = { gate, "plan-files": planFiles, scan, synthetic, push, publish };
  const run = commands[process.argv[2]];
  if (!run) {
    console.error("usage: upstream-apply-changelog.mjs gate|plan-files|scan|synthetic|push|publish");
    process.exit(2);
  }
  run(process.env).catch((error) => {
    console.log(`::error::${String(error.message).replace(/[\r\n]+/g, " ")}`);
    process.exit(1);
  });
}
