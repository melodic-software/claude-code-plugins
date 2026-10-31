// reconciler-record.mjs: exits 0 when the lost-run reconciler's record vouches
// for its re-run of REVIEW_RUN_ID (attempt 2, started by github-actions[bot]),
// by the rules check-trusted-trigger applies to a reconciler re-run
// (reconcilerRecordVouches); 3 when it does not; 2 when an input or the list
// cannot be read, or a read fails unexpectedly. pr-feedback-dispatch.yml's
// rerun-ci-status records a ci-status re-run on exit 0 only.
//
// Environment: GH_TOKEN, GITHUB_API_URL, GITHUB_REPOSITORY, REVIEW_RUN_ID,
// DEFAULT_BRANCH, TRUSTED_ACTORS (the default branch's list), RECONCILER_WORKFLOW.
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, reconcilerRecordVouches, REPOSITORY } from "./check-trusted-trigger.mjs";

export async function main({ env = process.env, github, sleep } = {}) {
  const repository = env.GITHUB_REPOSITORY ?? "";
  const runId = env.REVIEW_RUN_ID ?? "";
  if (!REPOSITORY.test(repository) || !/^[1-9][0-9]{0,19}$/.test(runId) || !/^[A-Za-z0-9._/-]{1,255}$/.test(env.DEFAULT_BRANCH ?? "")) {
    console.log("reconciler-record: a malformed input; nothing vouches");
    return 2;
  }
  let list;
  try {
    list = loadTrustedList(env.TRUSTED_ACTORS);
  } catch {
    console.log("reconciler-record: the trusted-actor list is unreadable; nothing vouches");
    return 2;
  }
  try {
    const vouched = await reconcilerRecordVouches({
      github: github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined }),
      repository,
      defaultBranch: env.DEFAULT_BRANCH,
      list,
      deniedIds: new Set(),
      reconcilerWorkflow: env.RECONCILER_WORKFLOW ?? "",
      runId,
      ...(sleep ? { sleep } : {}),
    });
    console.log(`reconciler-record: run ${runId} attempt 2 ${vouched ? "has" : "has no"} reconciler record the trigger check accepts`);
    return vouched ? 0 : 3;
  } catch (error) {
    console.log(`reconciler-record: unexpected ${error?.name ?? "error"}; nothing vouches`);
    return 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
