// The monitoring lane's job: collect, detect, write every signal's state and
// evidence to the job summary, then keep at most one open incident issue per
// signal (issues.mjs planIssues). Writes with the job's own token, 1 s apart,
// within the call budget, and only to the issues it files. No model.
//
// Environment: GITHUB_TOKEN, REPOSITORY, AGENT_IDENTITY, CALL_BUDGET,
// WINDOW_MINUTES, GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID, RUNNER_TEMP,
// JOBS_CARRY_PATH (read the last run's job reads and episodes and write this
// run's there), GITHUB_STEP_SUMMARY. For a replay: NOW (an ISO time) and
// DRY_RUN=1, which reads and plans but writes nothing.
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { FIELD_API, statusWriter } from "../../actions/resolve-config/write-status.mjs";
import { collect, JOBS_ARTIFACT, JOBS_FILE, jobsCarryFile, listFiled, parseEpisodeCarry, parseHeldCarry, parseJobsCarry } from "./collect.mjs";
import { FILING, fenced, incidentRules, planIssues, readMarker, renderBody, renderRetire, unreadSignals } from "./issues.mjs";
import { detect, holdRule } from "./signals.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { ghDownload, newestTrustedRun } from "../pr-merge/rotation.mjs";

const WORKFLOW_PATH = ".github/workflows/maintenance-monitor-signals.yml";
// The checkout's pipeline config, three levels above this file.
const CONFIG = fileURLToPath(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url));

// The last run's carry, from the newest scheduled or hand-started run of
// main's copy of this workflow that holds the JOBS_ARTIFACT, this run aside:
// only a run's own steps upload its artifacts. `jobs` is its completed job
// reads (collect.mjs parseJobsCarry), empty with a warning when there is none
// or it cannot be read, so every run's jobs are read as before. `held` is its
// held runs (parseHeldCarry), null when there is none or, with a warning, when
// it cannot be read. `episodes` is the signals' timers (parseEpisodeCarry),
// empty when there is none or, with a warning, when it cannot be read, so a
// timer restarts and an incident opens later, never earlier. Off unless
// JOBS_CARRY_PATH is set.
export async function readJobsCarry({ env, repo, actions, download, now = new Date() }) {
  const none = { jobs: new Map(), held: null, episodes: {} };
  if (!env.JOBS_CARRY_PATH) return none;
  const warn = (what, error) => console.log(`::warning::monitoring lane: ${what}: ${error?.message ?? error}`);
  let text;
  try {
    const id = await newestTrustedRun({ repo, runId: String(env.GITHUB_RUN_ID), actions, name: JOBS_ARTIFACT, workflow: WORKFLOW_PATH });
    if (id === undefined) return none;
    download ??= ghDownload({ repo, token: env.GITHUB_TOKEN, dir: env.RUNNER_TEMP ?? tmpdir(), name: JOBS_ARTIFACT, file: JOBS_FILE });
    text = download(id);
  } catch (error) {
    warn("nothing carried, so every run's jobs are read", error);
    return none;
  }
  const carry = { jobs: new Map(), held: null, episodes: {} };
  try {
    carry.jobs = parseJobsCarry(text, repo);
  } catch (error) {
    warn("no job reads carried, so every run's jobs are read", error);
  }
  try {
    carry.held = parseHeldCarry(text, repo);
  } catch (error) {
    warn("no held runs carried", error);
  }
  try {
    carry.episodes = parseEpisodeCarry(text, repo, now);
  } catch (error) {
    warn("no signal timers carried, so each restarts", error);
  }
  return carry;
}

// pr-pipeline.yaml's monitor.lane-holds rule (signals.mjs holdRule), read with
// yq as the workflow reads merge.agent-identity, or the error that stopped it.
export function readHoldRule({ path = CONFIG, run = execFileSync } = {}) {
  try {
    return holdRule(JSON.parse(run("yq", ["-o=json", '.monitor."lane-holds" // {}', path], { encoding: "utf8" })));
  } catch (error) {
    return new Error(`the monitor.lane-holds rule was not read: ${error?.message ?? error}`);
  }
}

// pr-pipeline.yaml's monitor.incidents thresholds (issues.mjs incidentRules),
// or the error that stopped the read.
export function readIncidentRules({ path = CONFIG, run = execFileSync } = {}) {
  try {
    return incidentRules(JSON.parse(run("yq", ["-o=json", ".monitor.incidents // {}", path], { encoding: "utf8" })));
  } catch (error) {
    return new Error(`the monitor.incidents thresholds were not read: ${error?.message ?? error}`);
  }
}

// Every GitHub call goes through the rate guard (rate-guard.mjs); the fetch
// is read at call time, so a test's stub is guarded too.
const guardedFetch = (url, init) => rateLimitLatch.guard(globalThis.fetch)(url, init);

const WORK_STATUS_FIELD = 48484079;
const PRIORITY_FIELD = 49622037;
const INCIDENT_TYPE = "Bug";

// What a signal knows at filing (docs/standards/issue-tracker.md, "Filing an
// issue"). Size, Complexity and Uncertainty need someone who has read the
// fault, and triage sets them.
export const incidentFields = (signal) => [
  { field_id: WORK_STATUS_FIELD, value: "needs-triage" },
  { field_id: PRIORITY_FIELD, value: FILING[signal].priority },
];

// A filed incident's body changes only when its findings change, and no write
// adds a comment except the retirement note. The rewrite takes agent-ready off
// first (statusWriter's leaveAgentReady, with orUnset), since a person vetted
// the earlier text; the PATCH runs last and carries the marker, so a failed
// call before it leaves the old state recorded and the write is retried on the
// next run. A failed filing is planned again next run; a failed field write
// only warns, and triage sets what is missing.
export async function writePlan({ plan, call, repo, runUrl, leaveAgentReady = async () => {}, setFields = async () => {}, wait = () => delay(1000) }) {
  const done = { filed: [], updated: [], closed: [], retired: [], failed: [] };
  for (const { family } of plan.file) {
    try {
      await wait();
      const issue = await call("POST", `/repos/${repo}/issues`, { title: FILING[family.signal].title, type: INCIDENT_TYPE, body: renderBody(family, runUrl) });
      done.filed.push(issue.number);
      // GitHub drops a type the token may not set without an error.
      if (issue.type?.name !== INCIDENT_TYPE) console.log(`::warning::#${issue.number} came back without Issue Type ${INCIDENT_TYPE}`);
      await wait();
      await setFields(issue.number, incidentFields(family.signal)).catch((error) => console.log(`::warning::#${issue.number}'s field values were not set: ${error.message}`));
    } catch (error) {
      done.failed.push({ target: family.signal, error: error.message });
    }
  }
  const attempt = async (number, into, write) => {
    try {
      await write();
      into.push(number);
    } catch (error) {
      done.failed.push({ target: `#${number}`, error: error.message });
    }
  };
  for (const { number, family } of plan.update) {
    await attempt(number, done.updated, async () => {
      await wait();
      await leaveAgentReady(number, "needs-triage", { orUnset: true });
      await wait();
      await call("PATCH", `/repos/${repo}/issues/${number}`, { body: renderBody(family, runUrl) });
    });
  }
  for (const { number, family } of plan.close) {
    await attempt(number, done.closed, async () => {
      await wait();
      await call("PATCH", `/repos/${repo}/issues/${number}`, { state: "closed", state_reason: "completed", body: renderBody(family, runUrl) });
    });
  }
  for (const { number } of plan.retire) {
    await attempt(number, done.retired, async () => {
      await wait();
      await call("POST", `/repos/${repo}/issues/${number}/comments`, { body: renderRetire(runUrl) });
      await wait();
      await call("PATCH", `/repos/${repo}/issues/${number}`, { state: "closed", state_reason: "not_planned" });
    });
  }
  return done;
}

// Every signal's state, then each current finding's evidence inside a fence.
export const statusLines = (plan) =>
  plan.status.flatMap(({ signal, state, findings }) => [
    `- **${signal}**: ${state}`,
    ...findings.flatMap((f) => ["", `\`${f.key}\` (${f.area}):`, "", fenced([f.summary, ...f.facts])]),
    ...(findings.length > 0 ? [""] : []),
  ]);

// Signals the owner asked to surface as an ::error on the monitoring run too,
// each run while they fire (#9170). The text is already inert.
const ERROR_SIGNALS = new Set(["11 post-merge unreadable"]);
export const errorLines = (findings) => findings.filter((f) => ERROR_SIGNALS.has(f.signal)).map((f) => `::error::${f.title}: ${f.summary}`);

function client(env) {
  let used = 0;
  const budget = Number(env.CALL_BUDGET ?? 250);
  const call = async (method, path, body) => {
    if (used >= budget) throw new Error(`call budget of ${budget} spent`);
    used += 1;
    const response = await guardedFetch(`${env.GITHUB_API_URL ?? "https://api.github.com"}${path}`, {
      method,
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "x-github-api-version": "2022-11-28",
        ...(body ? { "content-type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.status === 404 && method === "GET") return null;
    if (!response.ok) {
      throw Object.assign(new Error(`${method} ${path.split("?")[0]}: HTTP ${response.status}`), { status: response.status });
    }
    return path.endsWith("/zip") ? Buffer.from(await response.arrayBuffer()) : response.json();
  };
  return { call, used: () => used };
}

async function main(env = process.env) {
  const repo = env.REPOSITORY;
  const replay = Boolean(env.NOW);
  const now = replay ? new Date(env.NOW) : new Date();
  const windowStart = new Date(now.getTime() - Number(env.WINDOW_MINUTES ?? 65) * 60_000);
  const { call, used } = client(env);
  const get = (path) => call("GET", path);
  const graphql = (query, variables) => call("POST", "/graphql", { query, variables });
  const getStatus = async (url) => {
    const response = await fetch(url, { signal: AbortSignal.timeout(20_000) });
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
    return response.json();
  };
  // The artifact's one JSON file, or, given names, each named file's text.
  const readArtifact = async (id, files = null) => {
    const dir = mkdtempSync(join(env.RUNNER_TEMP ?? tmpdir(), "monitor-"));
    const unzip = (...name) => execFileSync("unzip", ["-p", join(dir, "a.zip"), ...name], { encoding: "utf8", maxBuffer: 16 << 20 });
    try {
      writeFileSync(join(dir, "a.zip"), await get(`/repos/${repo}/actions/artifacts/${id}/zip`));
      return files ? Object.fromEntries(files.map((name) => [name, unzip(name)])) : JSON.parse(unzip());
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
  // GET /rate_limit does not count against the limit.
  const ownRate = replay ? null : ((await get("/rate_limit").catch(() => null))?.resources?.core ?? null);
  const carry = await readJobsCarry({ env, repo, actions: call, now });

  const data = await collect({
    carriedJobs: carry.jobs,
    holds: { rule: readHoldRule(), carried: carry.held },
    get,
    graphql,
    getStatus,
    readArtifact,
    repo,
    now,
    windowStart,
    agentIdentity: env.AGENT_IDENTITY,
    ownRate: ownRate && { used: ownRate.used, limit: ownRate.limit, remaining: ownRate.remaining },
  });
  const findings = detect(data);
  // Thresholds this run could not read are a gap no source names, which leaves
  // every signal and its issue as they are.
  const rules = readIncidentRules();
  const gaps = [...data.gaps];
  if (rules instanceof Error) gaps.push(`incident thresholds: ${rules.message}`);
  const existing = (await listFiled({ get, repo })).filter((i) => readMarker(i.body));
  const plan = planIssues({ findings, existing, unread: unreadSignals(gaps), rules: rules instanceof Error ? {} : rules, episodes: carry.episodes, now });
  if (env.JOBS_CARRY_PATH) {
    try {
      writeFileSync(env.JOBS_CARRY_PATH, jobsCarryFile(repo, data.jobsCarry, data.heldCarry, { at: now.toISOString(), signals: plan.episodes }));
    } catch (error) {
      console.log(`::warning::monitoring lane: the job reads and signal timers were not carried: ${error.message}`);
    }
  }
  const runUrl = `${env.GITHUB_SERVER_URL ?? "https://github.com"}/${repo}/actions/runs/${env.GITHUB_RUN_ID ?? 0}`;

  let done = { filed: [], updated: [], closed: [], retired: [], failed: [] };
  if (!env.DRY_RUN) {
    // The field write sends its own API version, which `call` cannot, so it
    // goes through its own client, outside the call budget.
    const github = createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const { leaveAgentReady } = await statusWriter({ env, github, repository: repo });
    const setFields = (number, values) => github("POST", `/repos/${repo}/issues/${number}/issue-field-values`, { issue_field_values: values }, FIELD_API);
    done = await writePlan({ plan, call, repo, runUrl, leaveAgentReady, setFields });
  }

  const list = (numbers) => numbers.map((n) => `#${n}`).join(", ") || "none";
  const lines = [
    `### Monitoring lane${env.DRY_RUN ? " (dry run)" : ""}`,
    "",
    `Window ${windowStart.toISOString()} to ${now.toISOString()}. Findings: ${findings.length}. Filed: ${list(done.filed)}. Updated: ${list(done.updated)}. Closed: ${list(done.closed)}. Rolling issues retired: ${list(done.retired)}. Calls: ${used()}.`,
    "",
    ...statusLines(plan),
    ...plan.logged.map((f) => `- logged, not filed: ${f.title} (${f.summary})`),
    ...plan.file.map((p) => `- plan: file ${p.family.signal}`),
    ...plan.update.map((p) => `- plan: update #${p.number} ${p.family.signal}`),
    ...plan.close.map((p) => `- plan: clear and close #${p.number} ${p.family.signal}`),
    ...plan.retire.map((p) => `- plan: retire #${p.number} \`${p.key}\``),
    ...plan.skip.map((s) => `- plan: skip ${s.family} (${s.reason}${s.number ? `, #${s.number}` : ""})`),
    ...gaps.map((g) => `- not read: ${g}`),
    ...done.failed.map((f) => `- failed ${f.target}: ${f.error}`),
  ];
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  else console.log(lines.join("\n"));
  for (const gap of gaps) console.log(`::warning::monitoring lane: not read: ${gap}`);
  for (const line of errorLines(findings)) console.log(line);
  if (done.failed.length > 0) {
    console.log(`::error::${done.failed.length} monitoring lane write(s) failed; see the step summary`);
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
