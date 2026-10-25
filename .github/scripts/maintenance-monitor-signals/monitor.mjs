// The monitoring lane's job: collect, detect, then keep one rolling issue per
// signal family: file it, rewrite it when its state changes, close it when the
// signal clears and reopen it when the signal fires again. Platform incidents
// go to the run summary only. Open issues from the earlier one-issue-per-key
// scheme are closed, pointing at the family's issue. Writes with the job's own
// token, 1 s apart, within the call budget, and only to the issues it files.
// No model.
//
// Environment: GITHUB_TOKEN, REPOSITORY, AGENT_IDENTITY, CALL_BUDGET,
// WINDOW_MINUTES, GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID,
// GITHUB_STEP_SUMMARY. For a replay: NOW (an ISO time) and DRY_RUN=1, which
// reads and plans but writes nothing.
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { collect, listFiled } from "./collect.mjs";
import { planIssues, readMarker, renderBody, renderComment, renderSupersede, titleOf, unreadSignals } from "./issues.mjs";
import { detect } from "./signals.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";

// Every GitHub call goes through the rate guard (rate-guard.mjs); the fetch
// is read at call time, so a test's stub is guarded too.
const guardedFetch = (url, init) => rateLimitLatch.guard(globalThis.fetch)(url, init);

// No needs-triage: a rolling issue is a status record the lane rewrites, not
// an intake item.
const LABELS = ["source: factory-monitor"];

export async function writePlan({ plan, call, repo, labels, runUrl, wait = () => delay(1000) }) {
  const done = { filed: [], updated: [], reopened: [], closed: [], failed: [] };
  const rollingOf = new Map();
  for (const { family } of plan.file) {
    await wait();
    try {
      const issue = await call("POST", `/repos/${repo}/issues`, {
        title: titleOf(family.signal),
        body: renderBody(family, runUrl),
        labels,
      });
      done.filed.push(issue.number);
      rollingOf.set(family.signal, issue.number);
    } catch (error) {
      done.failed.push({ target: family.signal, error: error.message });
    }
  }
  // A body a person vetted for agent-ready is replaced, so agent-ready comes
  // off before the PATCH (a 404 means it was not on the issue). The PATCH
  // runs last and carries the marker, so a failed call before it leaves the
  // old state recorded and the write is retried on the next run.
  const writes = [
    ...plan.update.map((u) => ({ ...u, reopen: false, into: done.updated })),
    ...plan.reopen.map((r) => ({ ...r, reopen: true, into: done.reopened })),
  ];
  for (const { number, family, reopen, into } of writes) {
    const clear = family.findings.length === 0;
    const state = reopen
      ? { state: "open", state_reason: "reopened" }
      : clear
        ? { state: "closed", state_reason: "completed" }
        : {};
    try {
      await wait();
      await call("POST", `/repos/${repo}/issues/${number}/comments`, { body: renderComment(family, runUrl) });
      await wait();
      await call("DELETE", `/repos/${repo}/issues/${number}/labels/agent-ready`).catch((error) => {
        if (error.status !== 404) throw error;
      });
      await wait();
      await call("PATCH", `/repos/${repo}/issues/${number}`, { ...state, body: renderBody(family, runUrl) });
      into.push(number);
    } catch (error) {
      done.failed.push({ target: `#${number}`, error: error.message });
    }
  }
  for (const { number, signal, rolling } of plan.close) {
    try {
      await wait();
      await call("POST", `/repos/${repo}/issues/${number}/comments`, {
        body: renderSupersede(signal, rolling ?? rollingOf.get(signal) ?? null),
      });
      await wait();
      await call("PATCH", `/repos/${repo}/issues/${number}`, { state: "closed", state_reason: "not_planned" });
      done.closed.push(number);
    } catch (error) {
      done.failed.push({ target: `#${number}`, error: error.message });
    }
  }
  return done;
}

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
  const getStatus = async (url) => {
    const response = await fetch(url, { signal: AbortSignal.timeout(20_000) });
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
    return response.json();
  };
  const readArtifact = async (id) => {
    const dir = mkdtempSync(join(env.RUNNER_TEMP ?? tmpdir(), "monitor-"));
    try {
      writeFileSync(join(dir, "a.zip"), await get(`/repos/${repo}/actions/artifacts/${id}/zip`));
      return JSON.parse(execFileSync("unzip", ["-p", join(dir, "a.zip")], { encoding: "utf8", maxBuffer: 16 << 20 }));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
  // GET /rate_limit does not count against the limit.
  const ownRate = replay ? null : ((await get("/rate_limit").catch(() => null))?.resources?.core ?? null);

  const data = await collect({
    get,
    getStatus,
    readArtifact,
    repo,
    now,
    windowStart,
    agentIdentity: env.AGENT_IDENTITY,
    ownRate: ownRate && { used: ownRate.used, limit: ownRate.limit, remaining: ownRate.remaining },
  });
  const findings = detect(data);
  const existing = (await listFiled({ get, repo })).filter((i) => readMarker(i.body));
  const plan = planIssues({ findings, existing, unread: unreadSignals(data.gaps) });
  const runUrl = `${env.GITHUB_SERVER_URL ?? "https://github.com"}/${repo}/actions/runs/${env.GITHUB_RUN_ID ?? 0}`;

  let done = { filed: [], updated: [], reopened: [], closed: [], failed: [] };
  const labels = [];
  if (!env.DRY_RUN) {
    for (const name of LABELS) {
      if (await get(`/repos/${repo}/labels/${encodeURIComponent(name)}`)) labels.push(name);
    }
    done = await writePlan({ plan, call, repo, labels, runUrl });
  }

  const list = (numbers) => numbers.map((n) => `#${n}`).join(", ") || "none";
  const lines = [
    `### Monitoring lane${env.DRY_RUN ? " (dry run)" : ""}`,
    "",
    `Window ${windowStart.toISOString()} to ${now.toISOString()}. Findings: ${findings.length}. Filed: ${list(done.filed)}. Updated: ${list(done.updated)}. Reopened: ${list(done.reopened)}. Closed as superseded: ${list(done.closed)}. Labels: ${labels.join(", ") || "none"}. Calls: ${used()}.`,
    "",
    ...findings.map((f) => `- ${f.signal} \`${f.key}\`: ${f.summary}`),
    ...plan.logged.map((f) => `- logged, not filed: ${f.title} (${f.summary})`),
    ...plan.file.map((p) => `- plan: file ${p.family.signal}`),
    ...plan.update.map((p) => `- plan: ${p.family.findings.length === 0 ? "clear and close" : "update"} #${p.number} ${p.family.signal}`),
    ...plan.reopen.map((p) => `- plan: reopen #${p.number} ${p.family.signal}`),
    ...plan.close.map((p) => `- plan: close #${p.number} \`${p.key}\` as superseded`),
    ...plan.skip.map((s) => `- plan: skip ${s.family} (${s.reason}${s.number ? `, #${s.number}` : ""})`),
    ...data.gaps.map((g) => `- not read: ${g}`),
    ...done.failed.map((f) => `- failed ${f.target}: ${f.error}`),
  ];
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  else console.log(lines.join("\n"));
  for (const gap of data.gaps) console.log(`::warning::monitoring lane: not read: ${gap}`);
  if (done.failed.length > 0) {
    console.log(`::error::${done.failed.length} monitoring lane write(s) failed; see the step summary`);
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
