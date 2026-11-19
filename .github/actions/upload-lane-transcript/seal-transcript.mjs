// Seal one lane leg's transcript, gzipped, to the transcript public key as one
// seal-lane-output record, written under RUNNER_TEMP for the upload step. The
// plaintext stays in memory: only the sealed record reaches disk, and nothing
// here prints it. README.md states the format.
import { appendFileSync, lstatSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

import { JOB_ID, SealError, parsePublicKey, sealRecord } from "../seal-lane-output/seal.mjs";

export const PAYLOAD = "transcript.json.gz";
export const TELEMETRY_PAYLOAD = "otel.jsonl.gz";
export const MAX_ARTIFACT_BYTES = 63 * 1024 * 1024;

/** True for a regular, non-empty file; a link or a missing path is not one. */
function hasContent(file) {
  try {
    const stat = file === "" ? undefined : lstatSync(file);
    return stat?.isFile() === true && stat.size > 0;
  } catch {
    return false;
  }
}

function jobIdOf(env) {
  const jobId = env.JOB_ID ?? "";
  if (!JOB_ID.test(jobId)) throw new SealError("the job-id input is not a job key");
  return jobId;
}

export function main(env = process.env) {
  if (String(env.PUBLIC_KEY ?? "").trim() === "") {
    process.stdout.write("::notice::upload-lane-transcript: the LANE_TRANSCRIPT_PUBLIC_KEY variable is not set, so this leg's transcript is not uploaded\n");
    return;
  }
  // The key first: a malformed key fails whether or not a leg ran.
  const recipient = parsePublicKey(env.PUBLIC_KEY);
  const jobId = jobIdOf(env);
  const file = env.EXECUTION_FILE ?? "";
  // No regular, non-empty file: no leg ran, so there is nothing to keep.
  if (!hasContent(file)) return;
  const record = sealRecord(recipient, PAYLOAD, gzipSync(readFileSync(file)), env.GITHUB_RUN_ID, jobId);
  const dir = path.join(env.RUNNER_TEMP, "lane-transcript", jobId);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const sealed = path.join(dir, `${PAYLOAD}.sealed`);
  writeFileSync(sealed, record, { flag: "wx" });
  appendFileSync(env.GITHUB_OUTPUT, `file=${sealed}\n`);
}

/**
 * Seal the leg's telemetry beside its sealed transcript, under its own payload
 * name and the same run and job binding. Runs after the transcript is on disk
 * and never touches it; an artifact that would pass the puller's limit leaves
 * the telemetry out.
 */
export function sealTelemetry(env = process.env, maxArtifactBytes = MAX_ARTIFACT_BYTES) {
  const file = env.OTEL_FILE ?? "";
  if (!hasContent(file)) return;
  const recipient = parsePublicKey(env.PUBLIC_KEY);
  const jobId = jobIdOf(env);
  const dir = path.join(env.RUNNER_TEMP, "lane-transcript", jobId);
  const transcriptBytes = statSync(path.join(dir, `${PAYLOAD}.sealed`)).size;
  const record = sealRecord(recipient, TELEMETRY_PAYLOAD, gzipSync(readFileSync(file)), env.GITHUB_RUN_ID, jobId);
  if (transcriptBytes + record.length > maxArtifactBytes) {
    process.stdout.write("::warning::upload-lane-transcript: the telemetry is left out: with it the artifact would pass the transcript puller's size limit\n");
    return;
  }
  const sealed = path.join(dir, `${TELEMETRY_PAYLOAD}.sealed`);
  writeFileSync(sealed, record, { flag: "wx" });
  appendFileSync(env.GITHUB_OUTPUT, `file=${sealed}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv[2] === "telemetry") {
    try {
      sealTelemetry();
    } catch (error) {
      process.stdout.write(`::warning::upload-lane-transcript: the telemetry is left out: ${error instanceof SealError ? error.message : `it could not be sealed (${error.name})`}\n`);
    }
  } else {
    try {
      main();
    } catch (error) {
      process.stdout.write(`::error::upload-lane-transcript: ${error instanceof SealError ? error.message : `the transcript could not be sealed (${error.name})`}\n`);
      process.exit(1);
    }
  }
}
