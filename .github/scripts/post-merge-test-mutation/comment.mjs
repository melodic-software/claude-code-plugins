// post-merge-test-mutation.yml's comment step: puts the body report.mjs built
// from the validated result on the pull request that merged the pushed head,
// as one comment. A re-run edits this lane's comment there instead of adding
// another. No model runs here.
//
// Env: PULL (report.mjs's `pull` output), COMMENT_PATH, REPOSITORY,
// GITHUB_TOKEN (pull-requests: write).
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { ownComment as ownMarked, upsert as upsertMarked } from "../lib/upsert-comment.mjs";
import { MARKER } from "./report.mjs";

export const ownComment = ({ github, repository, pull }) => ownMarked({ github, repository, pull, marker: MARKER });
export const upsert = ({ github, repository, pull, body }) => upsertMarked({ github, repository, pull, marker: MARKER, body });

export async function main(env = process.env, { github } = {}) {
  if (!/^[1-9][0-9]*$/.test(env.PULL ?? "")) {
    console.log("::notice::no merged pull request to comment on");
    return 0;
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.REPOSITORY ?? "")) {
    console.log("::error::REPOSITORY is not owner/name");
    return 1;
  }
  let body;
  try {
    body = readFileSync(env.COMMENT_PATH, "utf8");
  } catch {
    console.log("::error::report.mjs left no comment body");
    return 1;
  }
  if (!body.startsWith(`${MARKER}\n`)) {
    console.log("::error::the comment body does not start with the lane's marker");
    return 1;
  }
  const client = github ?? createGitHub({ token: env.GITHUB_TOKEN });
  try {
    const done = await upsert({ github: client, repository: env.REPOSITORY, pull: env.PULL, body });
    console.log(`::notice::${done} the mutation report on #${env.PULL}`);
    return 0;
  } catch (error) {
    console.log(`::error::could not post the mutation report on #${env.PULL}: ${error?.message ?? error}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
