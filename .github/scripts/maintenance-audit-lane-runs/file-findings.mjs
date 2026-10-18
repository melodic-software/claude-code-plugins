// The lane sweep's file job: checks every claim against main, fingerprints
// each finding, reads the issues earlier sweeps filed, and files, comments or
// skips per planFiling. No model. Writes with the job's own token, one call at
// a time, 1 s apart, within its call budget.
import { appendFileSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { createBudget } from "./collect.mjs";
import {
  checkClaim,
  fingerprint,
  inertTitle,
  planFiling,
  readFingerprint,
  renderBody,
  validateFinding,
} from "./findings.mjs";

export const FILER_LOGIN = "github-actions[bot]";
const LABELS = ["needs-triage", "source: lane-sweep"];

export function prepareItems({ findingsDir, baseDir }) {
  const items = [];
  const dropped = [];
  for (const entry of readdirSync(findingsDir).sort()) {
    let data;
    try {
      data = JSON.parse(readFileSync(join(findingsDir, entry, "findings.json"), "utf8"));
    } catch {
      dropped.push({ unit: entry, title: null, reason: "unreadable" });
      continue;
    }
    for (const finding of Array.isArray(data.findings) ? data.findings : []) {
      const bad = validateFinding(finding);
      if (bad.length > 0) {
        dropped.push({
          unit: data.unit,
          title: String(finding?.title ?? ""),
          reason: bad.join(","),
        });
        continue;
      }
      const failed = finding.evidence
        .map((claim) => [claim, checkClaim(baseDir, claim)])
        .find(([, result]) => !result.ok);
      if (failed) {
        dropped.push({
          unit: data.unit,
          title: finding.title,
          reason: `${failed[0].path}:${failed[0].line} ${failed[1].reason}`,
        });
        continue;
      }
      items.push({ fingerprint: fingerprint(finding), finding });
    }
  }
  return { items, dropped };
}

// Model text in the step summary: one line, no code spans, links, mentions
// or HTML.
const inertLine = (text) => inertTitle(String(text ?? "").replace(/[\r\n]+/g, " ").replace(/`/g, ""));

export const droppedLine = (d) => `- dropped (${d.unit}) ${inertLine(d.title)}: ${inertLine(d.reason)}`;

async function main() {
  const env = process.env;
  const repo = env.REPOSITORY;
  const budget = createBudget(Number(env.CALL_BUDGET ?? 50));
  const call = async (method, path, body) => {
    budget.spend();
    const response = await fetch(`${env.GITHUB_API_URL}${path}`, {
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
    if (!response.ok) throw new Error(`${method} ${path}: HTTP ${response.status}`);
    return response.json();
  };

  const { items, dropped } = prepareItems({
    findingsDir: env.FINDINGS_DIR,
    baseDir: env.BASE_DIR,
  });
  const existing = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = await call(
      "GET",
      `/repos/${repo}/issues?creator=${encodeURIComponent(FILER_LOGIN)}&state=all&per_page=100&page=${page}`,
    );
    existing.push(...batch.filter((i) => !i.pull_request && readFingerprint(i.body)));
    if (batch.length < 100) break;
  }
  const openItems = JSON.parse(readFileSync(env.OPEN_ITEMS_PATH, "utf8"));
  const plan = planFiling({
    items,
    existing,
    openNumbers: new Set(openItems.map((i) => i.number)),
    now: new Date(),
  });
  const labels = [];
  for (const name of LABELS) {
    if (await call("GET", `/repos/${repo}/labels/${encodeURIComponent(name)}`)) labels.push(name);
  }
  const runUrl = `${env.GITHUB_SERVER_URL}/${repo}/actions/runs/${env.GITHUB_RUN_ID}`;
  const filed = [];
  for (const { fingerprint: fp, finding, regressionOf } of plan.file) {
    await delay(1000);
    const issue = await call("POST", `/repos/${repo}/issues`, {
      title: inertTitle(finding.title),
      body: renderBody(finding, fp, runUrl, regressionOf),
      labels,
    });
    filed.push(issue.number);
  }
  for (const { number } of plan.comment) {
    await delay(1000);
    await call("POST", `/repos/${repo}/issues/${number}/comments`, {
      body: `Seen again by the lane sweep in [this run](${runUrl}).`,
    });
  }
  const lines = [
    "### Lane sweep filing",
    "",
    `Filed: ${filed.map((n) => `#${n}`).join(", ") || "none"}. Commented: ${plan.comment.map((c) => `#${c.number}`).join(", ") || "none"}. Labels applied: ${labels.join(", ") || "none"}. Calls: ${budget.used}.`,
    "",
    ...plan.skip.map((s) => `- skipped ${s.fingerprint}: ${s.reason}`),
    ...dropped.map(droppedLine),
  ];
  appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  console.log(
    `file-findings: filed ${filed.length}, commented ${plan.comment.length}, skipped ${plan.skip.length}, dropped ${dropped.length}`,
  );
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
