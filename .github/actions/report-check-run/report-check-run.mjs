// Writes one `<lane> / <activity>` check run for a pipeline activity from a
// scripted job. Every fact except the verdict file comes from env the report
// job sets; decide() validates the verdict and picks the conclusion.
import { readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { createGitHub } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { decide } from "./decide.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCHEMA = "docs/conventions/pr-pipeline/pr-pipeline.schema.json";
const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]*$/;

// null when there is no file; the raw text when it is not JSON, which decide
// rejects as a malformed verdict.
function readVerdict(verdictPath) {
  let text;
  try {
    text = readFileSync(verdictPath, "utf8");
  } catch {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

// An unreadable enum is an empty one, so every skip fails rather than passes.
function readSkipReasons(basePath) {
  try {
    const reasons = JSON.parse(
      readFileSync(path.join(basePath, SCHEMA), "utf8"),
    ).$defs["skip-reason"].enum;
    return Array.isArray(reasons) ? reasons : [];
  } catch {
    return [];
  }
}

// The signed-commit step runs unless can-commit is exactly 'false'; when it
// should have run, anything but 'true' counts as unverified.
const signedCommitsFrom = (env) =>
  env.CAN_COMMIT === "false"
    ? null
    : { all_verified: env.ALL_VERIFIED === "true" };

export async function main({
  env = process.env,
  fetchImpl = fetch,
  log = console.log,
} = {}) {
  if (
    !REPOSITORY.test(env.GITHUB_REPOSITORY ?? "") ||
    !SHA.test(env.HEAD_SHA_FALLBACK ?? "") ||
    !(!env.HEAD_SHA || SHA.test(env.HEAD_SHA))
  ) {
    log(
      "::error::report-check-run: repository, head-sha or head-sha-fallback is malformed",
    );
    return 1;
  }
  const decision = decide(
    env.VERDICT_PATH ? readVerdict(env.VERDICT_PATH) : null,
    {
      lane: env.LANE,
      activity: env.ACTIVITY,
      runResult: env.RUN_RESULT,
      actOutcome: env.ACT_OUTCOME,
      gateReason: env.GATE_REASON ?? "",
      headSha: env.HEAD_SHA ?? "",
      signedCommits: signedCommitsFrom(env),
      headShaFallback: env.HEAD_SHA_FALLBACK,
      gateSkipReasons: JSON.parse(
        readFileSync(path.join(HERE, "gate-skip-reasons.json"), "utf8"),
      ),
      skipReasons: readSkipReasons(env.BASE_PATH ?? ".base"),
    },
  );
  if (decision.kind === "refuse") {
    log(`::error::report-check-run: refused (${decision.why})`);
    return 1;
  }
  if (decision.kind === "none") {
    log(`report-check-run: no check posted (${decision.why})`);
    return 0;
  }
  const body = { ...decision.report };
  if (RUN_ID.test(env.GITHUB_RUN_ID ?? "")) {
    body.details_url = `${env.GITHUB_SERVER_URL ?? "https://github.com"}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`;
  }
  try {
    const github = createGitHub({
      token: env.GITHUB_TOKEN,
      apiUrl: env.GITHUB_API_URL,
      fetchImpl,
    });
    await github("POST", `/repos/${env.GITHUB_REPOSITORY}/check-runs`, body);
  } catch (error) {
    const detail =
      error?.name === "GitHubError" ? error.message : (error?.name ?? "error");
    log(`::error::report-check-run: could not post the check run (${detail})`);
    return 1;
  }
  log(
    `report-check-run: posted ${body.name} ${body.conclusion} on ${body.head_sha}`,
  );
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
