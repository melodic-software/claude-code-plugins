import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../scripts/lib/github-client.mjs";
import { loadTrustedList, reconcilerRecordVouches, REPOSITORY } from "./check-trusted-trigger.mjs";

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
