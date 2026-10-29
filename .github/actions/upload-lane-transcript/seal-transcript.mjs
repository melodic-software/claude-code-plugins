// Seal one lane leg's transcript, gzipped, to the transcript public key as one
// seal-lane-output record, written under RUNNER_TEMP for the upload step. The
// plaintext stays in memory: only the sealed record reaches disk, and nothing
// here prints it. README.md states the format.
import { appendFileSync, lstatSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

import { JOB_ID, SealError, parsePublicKey, sealRecord } from "../seal-lane-output/seal.mjs";

export const PAYLOAD = "transcript.json.gz";

export function main(env = process.env) {
  if (String(env.PUBLIC_KEY ?? "").trim() === "") {
    process.stdout.write("::notice::upload-lane-transcript: the LANE_TRANSCRIPT_PUBLIC_KEY variable is not set, so this leg's transcript is not uploaded\n");
    return;
  }
  // The key first: a malformed key fails whether or not a leg ran.
  const recipient = parsePublicKey(env.PUBLIC_KEY);
  const jobId = env.JOB_ID ?? "";
  if (!JOB_ID.test(jobId)) throw new SealError("the job-id input is not a job key");
  const file = env.EXECUTION_FILE ?? "";
  let stat;
  try {
    stat = file === "" ? undefined : lstatSync(file);
  } catch {
    stat = undefined;
  }
  // No regular, non-empty file: no leg ran, so there is nothing to keep.
  if (!stat?.isFile() || stat.size === 0) return;
  const record = sealRecord(recipient, PAYLOAD, gzipSync(readFileSync(file)), env.GITHUB_RUN_ID, jobId);
  const dir = path.join(env.RUNNER_TEMP, "lane-transcript", jobId);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const sealed = path.join(dir, `${PAYLOAD}.sealed`);
  writeFileSync(sealed, record, { flag: "wx" });
  appendFileSync(env.GITHUB_OUTPUT, `file=${sealed}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stdout.write(`::error::upload-lane-transcript: ${error instanceof SealError ? error.message : `the transcript could not be sealed (${error.name})`}\n`);
    process.exit(1);
  }
}
