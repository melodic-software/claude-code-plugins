// The monitoring lane's job: collect, detect, then file, update, reopen or
// skip one issue per finding. Writes with the job's own token, 1 s apart, within the
// call budget, and only to the issues it files. No model.
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
import { planIssues, readMarker, renderBody, renderComment } from "./issues.mjs";
import { detect } from "./signals.mjs";

const LABELS = ["needs-triage", "source: factory-monitor"];

// A reopened issue goes back to triage: the filing labels that exist return,
// and agent-ready comes off; a 404 means it was not on the issue.
async function retriage({ call, repo, number, labels, wait }) {
  if (labels.length > 0) {
    await wait();
    await call("POST", `/repos/${repo}/issues/${number}/labels`, { labels });
  }
  await wait();
  await call("DELETE", `/repos/${repo}/issues/${number}/labels/agent-ready`).catch((error) => {
    if (error.status !== 404) throw error;
  });
}

export async function writePlan({ plan, existing, call, repo, labels, runUrl, wait = () => delay(1000) }) {
  const done = { filed: [], updated: [], reopened: [], failed: [] };
  for (const { finding } of plan.file) {
    await wait();
    try {
      const issue = await call("POST", `/repos/${repo}/issues`, {
        title: finding.title,
        body: renderBody(finding, runUrl),
        labels,
      });
      done.filed.push(issue.number);
    } catch (error) {
      done.failed.push({ target: finding.key, error: error.message });
    }
  }
  // The comment carries the new evidence; the marker then records its
  // fingerprint, so a failed comment is retried on the next run. A reopen
  // sends the issue back to triage first and sets the state in that same
  // last PATCH, so a failed label call leaves it closed and retried too.
  const writes = [
    ...plan.update.map((u) => ({ ...u, reopen: false, into: done.updated })),
    ...plan.reopen.map((r) => ({ ...r, reopen: true, into: done.reopened })),
  ];
  for (const { number, finding, reopen, into } of writes) {
    const body = existing.find((i) => i.number === number).body;
    const [, ...rest] = body.split("\n");
    const marker = renderBody(finding, runUrl).split("\n", 1)[0];
    const state = reopen ? { state: "open", state_reason: "reopened" } : {};
    try {
      await wait();
      await call("POST", `/repos/${repo}/issues/${number}/comments`, { body: renderComment(finding, runUrl) });
      if (reopen) await retriage({ call, repo, number, labels, wait });
      await wait();
      await call("PATCH", `/repos/${repo}/issues/${number}`, { ...state, body: [marker, ...rest].join("\n") });
      into.push(number);
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
    const response = await fetch(`${env.GITHUB_API_URL ?? "https://api.github.com"}${path}`, {
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
  const plan = planIssues({ findings, existing });
  const runUrl = `${env.GITHUB_SERVER_URL ?? "https://github.com"}/${repo}/actions/runs/${env.GITHUB_RUN_ID ?? 0}`;

  let done = { filed: [], updated: [], reopened: [], failed: [] };
  const labels = [];
  if (!env.DRY_RUN) {
    for (const name of LABELS) {
      if (await get(`/repos/${repo}/labels/${encodeURIComponent(name)}`)) labels.push(name);
    }
    done = await writePlan({ plan, existing, call, repo, labels, runUrl });
  }

  const lines = [
    `### Monitoring lane${env.DRY_RUN ? " (dry run)" : ""}`,
    "",
    `Window ${windowStart.toISOString()} to ${now.toISOString()}. Findings: ${findings.length}. Filed: ${done.filed.map((n) => `#${n}`).join(", ") || "none"}. Updated: ${done.updated.map((n) => `#${n}`).join(", ") || "none"}. Reopened: ${done.reopened.map((n) => `#${n}`).join(", ") || "none"}. Labels: ${labels.join(", ") || "none"}. Calls: ${used()}.`,
    "",
    ...findings.map((f) => `- ${f.signal} \`${f.key}\`: ${f.summary}`),
    ...plan.file.map((p) => `- plan: file \`${p.finding.key}\``),
    ...plan.update.map((p) => `- plan: update #${p.number} \`${p.finding.key}\``),
    ...plan.reopen.map((p) => `- plan: reopen #${p.number} \`${p.finding.key}\``),
    ...plan.skip.map((s) => `- plan: skip \`${s.key}\` (${s.reason}${s.number ? `, #${s.number}` : ""})`),
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
