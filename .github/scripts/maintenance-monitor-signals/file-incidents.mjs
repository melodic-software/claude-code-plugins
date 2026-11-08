// The monitoring lane's one lanes App write: files the incidents the monitor
// job planned (monitor.mjs filingPlan), so intake triage runs on them, and sets
// their Work status and Priority at filing. An issue GITHUB_TOKEN opens starts
// no workflow, which is why this is not the job token. No model; the plan is
// checked against the hash the monitor job recorded before this runs.
//
// Environment: GH_TOKEN (the lane token), REPOSITORY, AGENT_IDENTITY, PLAN_FILE,
// GITHUB_API_URL, GITHUB_STEP_SUMMARY.
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { FIELD_API } from "../../actions/resolve-config/write-status.mjs";
import { readMarker } from "./issues.mjs";

const guardedFetch = (url, init) => rateLimitLatch.guard(globalThis.fetch)(url, init);

// Why the plan is unusable, or null.
export function planProblem(plan, repo) {
  if (plan?.version !== 1 || plan.repository !== repo || !Array.isArray(plan.incidents)) return "the plan has an unexpected shape or names another repository";
  for (const i of plan.incidents) {
    if (typeof i?.title !== "string" || typeof i.body !== "string" || !readMarker(i.body)?.key.startsWith("incident:") || typeof i.type !== "string" || !Array.isArray(i.labels) || !Array.isArray(i.fields)) {
      return "an incident in the plan has an unexpected shape";
    }
  }
  return null;
}

// Files each planned incident that has no open issue. A re-run of this job
// after a partial failure finds the ones already filed by their marker and
// leaves them, so a signal never holds two open incidents. A failed field write
// only warns: triage still runs and sets what it decides.
export async function fileIncidents({ plan, call, setFields, repo, agentIdentity, log = console.log, wait = () => delay(1000) }) {
  const done = { filed: [], skipped: [], failed: [] };
  const open = await call("GET", `/repos/${repo}/issues?creator=${encodeURIComponent(agentIdentity)}&state=open&per_page=100`);
  const openKeys = new Set(open.map((i) => readMarker(i.body)?.key).filter(Boolean));
  for (const incident of plan.incidents) {
    const key = readMarker(incident.body).key;
    if (openKeys.has(key)) {
      done.skipped.push(key);
      continue;
    }
    try {
      await wait();
      const issue = await call("POST", `/repos/${repo}/issues`, { title: incident.title, body: incident.body, type: incident.type, labels: incident.labels });
      done.filed.push(issue.number);
      // GitHub drops a type the token may not set without an error.
      if (issue.type?.name !== incident.type) log(`::warning::#${issue.number} came back without Issue Type ${incident.type}`);
      await wait();
      await setFields(issue.number, incident.fields).catch((error) => log(`::warning::#${issue.number}'s field values were not set: ${error.message}`));
    } catch (error) {
      done.failed.push({ target: key, error: error.message });
    }
  }
  return done;
}

async function main(env = process.env) {
  const repo = env.REPOSITORY;
  const request = async (method, path, body, headers = {}) => {
    const response = await guardedFetch(`${env.GITHUB_API_URL ?? "https://api.github.com"}${path}`, {
      method,
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${env.GH_TOKEN}`,
        "x-github-api-version": "2022-11-28",
        ...(body ? { "content-type": "application/json" } : {}),
        ...headers,
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!response.ok) throw Object.assign(new Error(`${method} ${path.split("?")[0]}: HTTP ${response.status}`), { status: response.status });
    return response.json();
  };
  const plan = JSON.parse(readFileSync(env.PLAN_FILE, "utf8"));
  const problem = planProblem(plan, repo);
  if (problem) {
    console.log(`::error::monitoring lane: ${problem}; nothing filed`);
    process.exitCode = 1;
    return;
  }
  const setFields = (number, fields) => request("POST", `/repos/${repo}/issues/${number}/issue-field-values`, { issue_field_values: fields }, FIELD_API);
  const done = await fileIncidents({ plan, call: request, setFields, repo, agentIdentity: env.AGENT_IDENTITY });
  const list = (items) => items.join(", ") || "none";
  const lines = [
    "### Monitoring lane: incidents filed as the lanes App",
    "",
    `Filed: ${list(done.filed.map((n) => `#${n}`))}. Already open: ${list(done.skipped)}.`,
    ...done.failed.map((f) => `- failed ${f.target}: ${f.error}`),
  ];
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  else console.log(lines.join("\n"));
  if (done.failed.length > 0) {
    console.log(`::error::${done.failed.length} incident filing(s) failed; the next run plans them again`);
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
