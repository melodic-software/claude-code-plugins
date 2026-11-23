import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import intakeTriage from "./credential-legs/intake-triage.mjs";
import auditLaneRuns from "./credential-legs/maintenance-audit-lane-runs.mjs";
import tidyCodeUpkeep from "./credential-legs/maintenance-tidy-code-upkeep.mjs";
import prRateMergeRisk from "./credential-legs/pr-rate-merge-risk.mjs";
import prVerify from "./credential-legs/pr-verify.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const DECLARATIONS = [prVerify, prRateMergeRisk, intakeTriage, tidyCodeUpkeep, auditLaneRuns];

const STEP = /^ {6}- name: (.*)$/;
const STEP_ID = /^ {8}id: (.*)$/;
const STEP_COMMENT = /^ {6}#/;

export function jobSpan(lines, id) {
  const start = lines.indexOf(`  ${id}:`);
  if (start === -1) throw new Error(`sync-credential-legs: no job ${id}`);
  let end = start + 1;
  while (end < lines.length && !/^ {0,2}\S/.test(lines[end])) end++;
  while (lines[end - 1] === "") end--;
  return [start, end];
}

function parse(job) {
  const at = job.indexOf("    steps:");
  if (at === -1) throw new Error("sync-credential-legs: the key job has no steps");
  const steps = [];
  const first = { body: [null] };
  for (const line of job.slice(at + 1)) {
    const name = STEP.exec(line)?.[1];
    const last = steps.at(-1) ?? first;
    if (name !== undefined) {
      const lead = [];
      while (last.body.length > 1 && (last.body.at(-1) === "" || STEP_COMMENT.test(last.body.at(-1)))) lead.unshift(last.body.pop());
      if (last === first && last.body.length > 1) throw new Error(`sync-credential-legs: a line before the first step: ${last.body[1]}`);
      steps.push({ name, lead, body: [line] });
    } else {
      last.body.push(line);
      last.id ??= STEP_ID.exec(line)?.[1];
    }
  }
  return { header: job.slice(0, at + 1), steps };
}

const count = (text, from) => (typeof from === "string" ? text.split(from).length - 1 : [...text.matchAll(from)].length);

export function render(keyJob, leg) {
  const { header, steps } = parse(keyJob);
  const is = (s, name) => s.name === name || (s.id !== undefined && name === `#${s.id}`);
  const named = (name) => {
    const found = steps.filter((s) => is(s, name));
    if (!found.length) throw new Error(`sync-credential-legs: ${leg.job} names a step the key job lacks: ${name}`);
    if (found.length > 1) throw new Error(`sync-credential-legs: ${leg.job} names ${found.length} steps ${name}; name one by its #id`);
    return found[0];
  };
  for (const name of [...(leg.drop ?? []), ...Object.keys(leg.move ?? {}), ...Object.values(leg.move ?? {}), ...Object.keys(leg.comments ?? {})]) named(name);
  let kept = steps.filter((s) => !(leg.drop ?? []).some((name) => is(s, name)));
  for (const [name, after] of Object.entries(leg.move ?? {})) {
    const step = named(name);
    kept = kept.filter((s) => s !== step);
    const at = kept.indexOf(named(after));
    if (at === -1) throw new Error(`sync-credential-legs: ${leg.job} moves ${name} after a dropped step`);
    kept.splice(at + 1, 0, step);
  }
  const lines = [...header];
  for (const step of kept) {
    const comment = leg.comments?.[step.name] ?? leg.comments?.[`#${step.id}`];
    const own = step.lead.filter((line) => STEP_COMMENT.test(line));
    const written = comment === true ? own : comment === undefined ? [] : comment.split("\n").map((line) => `      # ${line}`.trimEnd());
    lines.push(...step.lead.filter((line) => line === ""), ...written, ...step.body);
  }
  let text = lines.join("\n");
  for (const [from, to, times] of leg.replace ?? []) {
    const found = count(text, from);
    if (found !== times) throw new Error(`sync-credential-legs: ${leg.job} expects ${times} of ${from}, found ${found}`);
    text = typeof from === "string" ? text.replaceAll(from, to) : text.replace(from, to);
  }
  return text;
}

export function checkFunding(funding, workflow, job, text) {
  const file = path.basename(workflow);
  const lane = funding.roles.flatMap((role) => role.lanes.map((l) => ({ ...l, keySecret: role.keySecret }))).find((l) => l.workflow === file && l.id === job);
  if (!lane) throw new Error(`sync-credential-legs: lane-funding.json funds no ${job} lane in ${file}, so it gets no derived job`);
  if (lane.currentSecrets.includes(lane.keySecret)) throw new Error(`sync-credential-legs: ${job} in ${file} is funded by the API key, not a subscription or fallback token`);
  const used = [...new Set([...text.matchAll(/secrets\.([A-Z0-9_]*CLAUDE[A-Z0-9_]*)/g)].map((m) => m[1]))];
  const unfunded = used.filter((secret) => !lane.currentSecrets.includes(secret));
  if (unfunded.length) throw new Error(`sync-credential-legs: ${job} in ${file} reads ${unfunded.join(", ")}, which lane-funding.json does not fund it with`);
}

export function generate(text, declaration, funding) {
  const lines = text.split("\n");
  const [ks, ke] = jobSpan(lines, declaration.key);
  const keyJob = lines.slice(ks, ke);
  for (const leg of declaration.legs) {
    const rendered = render(keyJob, leg);
    checkFunding(funding, declaration.workflow, leg.job, rendered);
    const [start, end] = jobSpan(lines, leg.job);
    lines.splice(start, end - start, ...rendered.split("\n"));
  }
  return lines.join("\n");
}

function diff(file, before, after) {
  const dir = mkdtempSync(path.join(tmpdir(), "credential-legs-"));
  try {
    writeFileSync(path.join(dir, "committed"), before);
    writeFileSync(path.join(dir, "rendered"), after);
    const out = spawnSync("git", ["diff", "--no-index", "--no-color", "--", "committed", "rendered"], { cwd: dir, encoding: "utf8" }).stdout;
    return `${file}\n${out}`;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

export function main(argv, root = ROOT, declarations = DECLARATIONS) {
  const check = argv.length === 1 && argv[0] === "--check";
  if (argv.length && !check) {
    process.stderr.write("usage: node scripts/sync-credential-legs.mjs [--check]\n");
    return 2;
  }
  const funding = JSON.parse(readFileSync(path.join(root, ".github/lane-funding.json"), "utf8"));
  let stale = 0;
  for (const declaration of declarations) {
    const file = path.join(root, declaration.workflow);
    const text = readFileSync(file, "utf8");
    const want = generate(text, declaration, funding);
    if (want === text) continue;
    stale++;
    if (check) process.stdout.write(diff(declaration.workflow, text, want));
    else {
      writeFileSync(file, want);
      process.stdout.write(`sync-credential-legs: rewrote ${declaration.workflow}\n`);
    }
  }
  if (check && stale) {
    process.stdout.write(`sync-credential-legs: ${stale} workflow(s) stale; run node scripts/sync-credential-legs.mjs\n`);
    return 1;
  }
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2));
