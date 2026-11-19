/**
 * Reuses a finished capture of the same pull request and head instead of
 * driving the app again (pr-verify-capture.yml): every PR Require Checks run
 * on a head starts its own capture run, and the judges read only their sibling
 * run's artifact (find-capture.mjs), so the sibling re-uploads the earlier
 * capture under its own run.
 *
 *   node reuse-capture.mjs find   reads the earlier capture's run and artifact
 *   node reuse-capture.mjs take   copies the downloaded capture to OUT
 *
 * The key is everything that changes the capture: the pull request, its head
 * and base, the app, and the main-side inputs the workflow lists in INPUTS
 * (git object ids of the files and folders the job runs, and its config). A
 * capture is stamped with the key and its maker's run at collect time, and a
 * reuse keeps that stamp, so `provenance.run_id` always names the run that
 * drove the app. The stamp is written after the head checkout, so it is as
 * untrusted as the rest of the capture; it is read only to decide whether to
 * capture again, for the same pull request and head.
 */
import { createHash } from "node:crypto";
import { appendFileSync, copyFileSync, lstatSync, mkdirSync, readdirSync, readFileSync, rmSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, detailSuffix } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { artifactName, CAPTURE_PATH } from "./find-capture.mjs";

const ID = /^[1-9][0-9]{0,19}$/;
const PR = /^[1-9][0-9]{0,15}$/;
const SHA = /^[0-9a-f]{40}$/;
const KEY = /^[0-9a-f]{64}$/;
export const MAX_CANDIDATES = 5;

export function reuseKey({ pr, headSha, baseSha, app, inputs }) {
  return createHash("sha256").update(JSON.stringify({ v: 1, pr: String(pr), headSha, baseSha, app, inputs: String(inputs) })).digest("hex");
}

/**
 * The run record an earlier capture must come from: this workflow file on
 * main, started by workflow_run in this repository, finished green, its
 * run-name naming this head. Any same-repository pull_request workflow can
 * upload an artifact of the capture's name; this is what rules those out.
 */
const isFinishedCapture = (run, { repository, headSha }) =>
  run?.path === CAPTURE_PATH &&
  run.event === "workflow_run" &&
  run.head_branch === "main" &&
  run.repository?.full_name === repository &&
  run.status === "completed" &&
  run.conclusion === "success" &&
  new RegExp(`^pr-verify-capture [1-9][0-9]{0,19} ${headSha}$`).test(String(run.display_title)) &&
  ID.test(String(run.id));

/**
 * { runId, artifactId } of the newest earlier capture of this pull request
 * and head, or undefined.
 */
export async function findEarlier(github, { repository, pr, headSha, runId }) {
  if (!PR.test(String(pr)) || !SHA.test(String(headSha))) return undefined;
  const name = artifactName(pr, headSha);
  const listed = await github("GET", `/repos/${repository}/actions/artifacts?name=${name}&per_page=20`);
  const candidates = (Array.isArray(listed?.artifacts) ? listed.artifacts : [])
    .filter((a) => a?.name === name && a.expired === false && ID.test(String(a.id)) && ID.test(String(a.workflow_run?.id)) && String(a.workflow_run.id) !== String(runId))
    .sort((a, b) => b.id - a.id)
    .slice(0, MAX_CANDIDATES);
  for (const candidate of candidates) {
    const run = await github("GET", `/repos/${repository}/actions/runs/${candidate.workflow_run.id}`);
    if (isFinishedCapture(run, { repository, headSha }) && String(run.id) === String(candidate.workflow_run.id)) {
      return { runId: String(run.id), artifactId: String(candidate.id) };
    }
  }
  return undefined;
}

function regularFiles(dir, rel = "") {
  const files = [];
  for (const entry of readdirSync(path.join(dir, rel))) {
    const child = path.join(rel, entry);
    const stat = lstatSync(path.join(dir, child));
    if (stat.isDirectory()) files.push(...regularFiles(dir, child));
    else if (stat.isFile()) files.push(child);
  }
  return files;
}

/**
 * Why the downloaded capture cannot stand in for this run's, or undefined
 * when it can. Only a capture that finished counts: a blocked one is captured
 * again, and so is one made under another key.
 */
export function refusal(summary, key) {
  if (summary === null || typeof summary !== "object" || Array.isArray(summary)) return "the earlier summary is not a JSON object";
  const status = summary.capture?.status;
  if (typeof status !== "string" || status === "blocked") return "the earlier capture did not finish";
  if (summary.provenance?.key !== key) return "the earlier capture was made under another key";
  if (!ID.test(String(summary.provenance?.run_id))) return "the earlier capture names no run that made it";
  return undefined;
}

/**
 * Copies the downloaded capture in dir to out when it can stand in, and
 * returns the run that made it, or { refused }.
 */
export function takeEarlier({ dir, out, key }) {
  let summary;
  try {
    summary = JSON.parse(readFileSync(path.join(dir, "e2e-summary.json"), "utf8"));
  } catch {
    return { refused: "the earlier capture has no readable e2e-summary.json" };
  }
  const refused = refusal(summary, key);
  if (refused) return { refused };
  rmSync(out, { recursive: true, force: true });
  for (const rel of regularFiles(dir)) {
    mkdirSync(path.dirname(path.join(out, rel)), { recursive: true });
    copyFileSync(path.join(dir, rel), path.join(out, rel));
  }
  return { madeBy: String(summary.provenance.run_id) };
}

export async function main(env = process.env, mode = process.argv[2], { github, fetchImpl } = {}) {
  const write = (line) => env.GITHUB_OUTPUT && appendFileSync(env.GITHUB_OUTPUT, `${line}\n`);
  if (mode === "find") {
    const key = reuseKey({ pr: env.PR_NUMBER, headSha: env.HEAD_SHA, baseSha: env.BASE_SHA, app: env.APP, inputs: env.INPUTS ?? "" });
    write(`key=${key}`);
    try {
      const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, fetchImpl });
      const found = await findEarlier(client, { repository: env.GITHUB_REPOSITORY, pr: env.PR_NUMBER, headSha: env.HEAD_SHA, runId: env.GITHUB_RUN_ID });
      if (!found) {
        console.log("reuse-capture: no earlier capture of this head; the capture runs");
        return;
      }
      write(`run-id=${found.runId}`);
      write(`artifact-id=${found.artifactId}`);
      console.log(`reuse-capture: run ${found.runId}'s capture of this head, artifact ${found.artifactId}`);
    } catch (error) {
      console.log(`::notice::earlier captures could not be read (${error.message}${detailSuffix(error)}); the capture runs`);
    }
    return;
  }
  if (mode === "take") {
    if (!KEY.test(String(env.KEY))) {
      console.log("::notice::no reuse key; the capture runs");
      return;
    }
    const taken = takeEarlier({ dir: env.EARLIER, out: env.OUT, key: env.KEY });
    if (taken.refused) {
      console.log(`::notice::${taken.refused}; the capture runs`);
      return;
    }
    write("reused=true");
    write(`made-by=${taken.madeBy}`);
    console.log(`::notice::capture reused from ${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${taken.madeBy}; no model session runs`);
    return;
  }
  throw new Error(`unknown mode ${mode}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::notice::the capture is not reused: ${error.message}`);
  });
}
