#!/usr/bin/env node
// lane-armed.mjs: posts pr-merge's `pr-merge/lane-armed` attestation (owner
// decision Q5) on the first candidate whose gate passed its lane-armed paths,
// from the sweep's pr-merge-summary.json, and names the artifact the next
// step uploads; `rerun` then re-runs that head's red ci-status job so
// ci-status reads both (merge-holds.mjs laneArmedHold). No model.
//
// The check run alone proves nothing: any workflow with checks: write posts
// as the same app and can copy this run's id. The artifact
// laneArmedArtifact(pr, head), which only this run's own steps can upload, is
// the proof, so one head is attested a run (an upload step names one
// artifact); a later passing head waits for the next run.
//
// A row attests only when the gate recorded `laneArmed` with no refusal (both
// review lanes bound to a clean main-run review of the head, no open review
// thread, a risk score and verdict that pass: babysit_risk.lane_arm_record),
// the row's head is its pull request's head, and the head does not shrink the
// hold floor against the base: every FLOOR_CLASSES and HOLD_PATH_CLASSES row
// of the base stays at the head with its class or a stricter one, and the
// head lane-arms nothing the base does not. Any read that fails refuses.
//
// Each attestation is one countable record: the line `lane-armed {...}` in
// the check run's summary, printed again as a `::notice::`. Each refusal
// prints a `::notice::lane-armed refused` line naming the failed condition.
//
// Environment:
//   GH_TOKEN            the job's own token: checks: write, actions: write,
//                       pull-requests: read, contents: read
//   GITHUB_REPOSITORY   owner/repo
//   SUMMARY_PATH        pr-merge-summary.json (attest)
//   LANE_ARMED_OUT      the directory the record file is written to (attest)
//   GITHUB_OUTPUT       gets `artifact` and `head` for the upload (attest)
//   LANE_ARMED_HEAD     the attested head (rerun)
//   GITHUB_RUN_ID, GITHUB_SERVER_URL, GITHUB_API_URL
import { Buffer } from "node:buffer";
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { LANE_ARMED_CHECK, laneArmedArtifact } from "./merge-holds.mjs";

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]*$/;
const RISK = "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py";
const HOLDS = ".github/scripts/pr-merge/merge-holds.mjs";
const RANK = { enforcement: 1, gate: 2, trust: 3 };
const LANES = ["claude-review", "claude-security-review"];
const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// The floor rows and lane-armed globs a file's text declares: babysit_risk.py
// `("glob", "class"),` and merge-holds.mjs `["glob", "class"],` rows, and the
// entries of its generated LANE_ARMED list. Null when either is missing.
export function floorOf(text) {
  const rows = new Map();
  for (const [, glob, kind] of String(text).matchAll(/^\s*[[(]"([^"]+)", "(trust|gate|enforcement)"[\])],/gm)) {
    rows.set(glob, kind);
  }
  const block = /LANE_ARMED(?::[^=]*)? = (?:Object\.freeze\()?[[(]\n([\s\S]*?)\n\s*[\])]/.exec(String(text));
  if (rows.size === 0 || !block) {
    return null;
  }
  return { rows, armed: [...block[1].matchAll(/"([^"]+)"/g)].map(([, glob]) => glob) };
}

// Why `head` (floorOf) shrinks `base`'s floor, or null.
export function shrinks(base, head) {
  if (!base || !head) {
    return "the floor rows could not be read";
  }
  for (const [glob, kind] of base.rows) {
    if (!head.rows.has(glob)) return `it removes the floor row ${glob}`;
    if (RANK[head.rows.get(glob)] < RANK[kind]) return `it moves ${glob} from ${kind} to ${head.rows.get(glob)}`;
  }
  const added = head.armed.find((glob) => !base.armed.includes(glob));
  return added === undefined ? null : `it lane-arms ${added}, which the base does not`;
}

// The record an attestation carries, from a summary row and this run.
export const recordOf = (row, run) => ({
  v: 1,
  pr: row.pr,
  head: row.head,
  paths: row.laneArmed.paths,
  lanes: Object.fromEntries(LANES.map((lane) => [lane, row.laneArmed.lanes?.[lane] ?? null])),
  threads: row.laneArmed.threads,
  run: Number(run),
});

// Why `row` does not attest before any read, or null.
export function rowRefusal(row) {
  const armed = row?.laneArmed;
  if (!armed || typeof armed !== "object") return "the gate recorded no lane-armed paths";
  if (armed.refused) return String(armed.refused);
  if (!Array.isArray(armed.paths) || armed.paths.length === 0 || !armed.paths.every((path) => typeof path === "string")) return "the gate recorded no lane-armed paths";
  if (armed.threads !== 0) return "the open review threads are not zero";
  if (!LANES.every((lane) => armed.lanes?.[lane] === 0)) return "a review lane has an open finding";
  return null;
}

async function text(github, repo, path, ref) {
  const file = await github("GET", `/repos/${repo}/contents/${path}?ref=${ref}`);
  if (file?.encoding !== "base64" || typeof file.content !== "string") throw new Error(`${path} at ${ref} is not a file`);
  return Buffer.from(file.content, "base64").toString("utf8");
}

// Re-run the ci-status job of the head's newest pull_request run of
// pr-require-checks.yml when it finished red; a running one reads the
// attestation itself.
async function rerunCiStatus(github, repo, head) {
  const runs = (await github("GET", `/repos/${repo}/actions/workflows/pr-require-checks.yml/runs?head_sha=${head}&event=pull_request&per_page=20`))?.workflow_runs;
  const run = (Array.isArray(runs) ? runs : []).reduce((a, b) => (a === null || b.id > a.id ? b : a), null);
  if (!run || run.status !== "completed") return "no finished ci-status run to re-run";
  const jobs = (await github("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?per_page=100`))?.jobs;
  const job = (Array.isArray(jobs) ? jobs : []).find((each) => each?.name === "ci-status");
  if (!job || job.conclusion === "success") return "ci-status is not red";
  await github("POST", `/repos/${repo}/actions/jobs/${job.id}/rerun`);
  return `re-ran ci-status job ${job.id}`;
}

export async function main({ env = process.env, github, fetchImpl, mode = process.argv[2] ?? "attest" } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    if (!RUN_ID.test(env.GITHUB_RUN_ID ?? "")) throw new Error("GITHUB_RUN_ID is not a run id");
    const repo = env.GITHUB_REPOSITORY;
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, fetchImpl });
    if (mode === "rerun") {
      if (!SHA.test(env.LANE_ARMED_HEAD ?? "")) throw new Error("LANE_ARMED_HEAD is not a commit SHA");
      console.log(`lane-armed: ${await rerunCiStatus(github, repo, env.LANE_ARMED_HEAD)}`);
      return 0;
    }
    let rows;
    try {
      rows = JSON.parse(readFileSync(env.SUMMARY_PATH, "utf8"));
    } catch {
      rows = [];
    }
    const details = `${env.GITHUB_SERVER_URL || "https://github.com"}/${repo}/actions/runs/${env.GITHUB_RUN_ID}`;
    let failed = 0;
    let attested = null;
    for (const row of Array.isArray(rows) ? rows : []) {
      if (!row?.laneArmed || !Number.isSafeInteger(row.pr) || !SHA.test(String(row.head)) || Object.hasOwn(row, "carried")) continue;
      const refuse = (why) => console.log(`::notice::lane-armed refused ${JSON.stringify({ v: 1, pr: row.pr, head: row.head, reason: why })}`);
      const early = rowRefusal(row) ?? (attested ? `this run attested #${attested.pr}; the next run attests this head` : null);
      if (early) {
        refuse(early);
        continue;
      }
      try {
        const pull = await github("GET", `/repos/${repo}/pulls/${row.pr}`);
        if (pull?.head?.sha !== row.head || !SHA.test(String(pull?.base?.sha))) {
          refuse("the head the gate judged is not the pull request's head");
          continue;
        }
        // Each file against its own base copy: either one is what runs.
        let shrunk = null;
        for (const path of [RISK, HOLDS]) {
          shrunk ??= shrinks(floorOf(await text(github, repo, path, pull.base.sha)), floorOf(await text(github, repo, path, row.head)));
        }
        if (shrunk) {
          refuse(`the head shrinks the hold floor: ${shrunk}`);
          continue;
        }
        const record = recordOf(row, env.GITHUB_RUN_ID);
        const line = `lane-armed ${JSON.stringify(record)}`;
        await github("POST", `/repos/${repo}/check-runs`, {
          name: LANE_ARMED_CHECK,
          head_sha: row.head,
          external_id: env.GITHUB_RUN_ID,
          details_url: details,
          status: "completed",
          conclusion: "success",
          output: {
            title: `pr-merge's gate passed ${record.paths.length} lane-armed path(s) on clean main-run reviews`,
            summary: [
              `Both review lanes are bound to a main-run review of \`${row.head}\` with no open finding, no review thread is open, the risk score and verdict pass, and the hold floor is not shrunk against the base. ci-status trusts this only with this run's artifact \`${laneArmedArtifact(row.pr, row.head)}\`.`,
              "",
              "```text",
              line,
              "```",
            ].join("\n"),
          },
        });
        console.log(`::notice::${line}`);
        attested = record;
      } catch (error) {
        failed += 1;
        refuse(`a read or write failed: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    if (attested) {
      mkdirSync(env.LANE_ARMED_OUT, { recursive: true });
      writeFileSync(join(env.LANE_ARMED_OUT, "lane-armed.json"), `${JSON.stringify(attested)}\n`);
      appendFileSync(env.GITHUB_OUTPUT, `artifact=${laneArmedArtifact(attested.pr, attested.head)}\nhead=${attested.head}\n`);
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=lane-armed::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
