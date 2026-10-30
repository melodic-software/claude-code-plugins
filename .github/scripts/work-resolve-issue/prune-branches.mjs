// work-resolve-issue.yml's prune-lane-branches job: deletes the lane branches
// of stopped runs that report-outcome.mjs --find-prior named (pruneBranches),
// which the read runner's issue-fields job held to the lane-branch shape.
// The run job that named them ran the model, so the list is only a claim:
// this script drops any name that is not this issue's lane branch, is this
// run's own (any attempt), or is the reuse or resume branch, then reads every
// remaining branch in one GraphQL request and keeps any that backs a pull
// request in any state, is gone, or reads oddly. Each delete is one GraphQL
// updateRefs whose beforeOid is the tip read, so a push after the read makes
// GitHub refuse it. A failed read deletes nothing; a refused delete is logged
// and the next branch still goes. Nothing here fails the run.
//
// Environment: GITHUB_TOKEN, GITHUB_API_URL, REPOSITORY, ISSUE_NUMBER,
// RUN_ID, PRUNE_BRANCHES (space-separated), REUSE_BRANCH, RESUME_BRANCH.
import process from "node:process";
import { pathToFileURL } from "node:url";

import { client, DELETE_REF, ZERO_OID } from "../branch-cleanup/cleanup.mjs";
import { isLaneBranch, PRUNE_CAP } from "./report-outcome.mjs";

const SHA = /^[0-9a-f]{40}$/;

// The names this run may delete, before any read.
export function claimed(env) {
  if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) throw new Error("ISSUE_NUMBER is not an issue number");
  if (!/^[1-9][0-9]*$/.test(env.RUN_ID ?? "")) throw new Error("RUN_ID is not a run id");
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.REPOSITORY ?? "")) throw new Error("REPOSITORY is not owner/repo");
  const own = `work-resolve-issue/issue-${env.ISSUE_NUMBER}-${env.RUN_ID}-`;
  const spared = new Set([env.REUSE_BRANCH, env.RESUME_BRANCH].filter(Boolean));
  const names = [...new Set(String(env.PRUNE_BRANCHES ?? "").split(/\s+/).filter(Boolean))];
  return names.filter((name) => isLaneBranch(name, env.ISSUE_NUMBER) && !name.startsWith(own) && !spared.has(name)).slice(0, PRUNE_CAP);
}

const readQuery = (count) => {
  const vars = Array.from({ length: count }, (_, i) => `, $b${i}: String!`).join("");
  const refs = Array.from(
    { length: count },
    (_, i) => `b${i}: ref(qualifiedName: $b${i}) { target { oid } associatedPullRequests(states: [OPEN, CLOSED, MERGED]) { totalCount } }`,
  ).join("\n    ");
  return `query($owner: String!, $name: String!${vars}) {\n  repository(owner: $owner, name: $name) {\n    id\n    ${refs}\n  }\n}`;
};

export async function prune(env, { call, log = console.log }) {
  const names = claimed(env);
  const deleted = [];
  if (names.length === 0) {
    log("prune-branches: no branch to delete");
    return { deleted };
  }
  const [owner, name] = env.REPOSITORY.split("/");
  let repository;
  try {
    const variables = { owner, name, ...Object.fromEntries(names.map((branch, i) => [`b${i}`, `refs/heads/${branch}`])) };
    repository = (await call("POST", "/graphql", { query: readQuery(names.length), variables }))?.data?.repository;
    if (typeof repository?.id !== "string" || repository.id === "") throw new Error("no repository id");
  } catch (error) {
    log(`::warning::prune-branches: could not read the branches, so none is deleted: ${error.message}`);
    return { deleted };
  }
  for (const [i, branch] of names.entries()) {
    const ref = repository[`b${i}`];
    const oid = ref?.target?.oid;
    if (ref?.associatedPullRequests?.totalCount !== 0 || !SHA.test(oid ?? "")) {
      log(`prune-branches: kept ${branch}: ${ref ? "it backs a pull request or reads oddly" : "it is gone"}`);
      continue;
    }
    try {
      await call("POST", "/graphql", {
        query: DELETE_REF,
        variables: { repositoryId: repository.id, name: `refs/heads/${branch}`, beforeOid: oid, afterOid: ZERO_OID },
      });
      deleted.push(branch);
      log(`prune-branches: deleted ${branch} at ${oid}; restore with git push origin ${oid}:refs/heads/${branch}`);
    } catch (error) {
      log(`::warning::prune-branches: could not delete ${branch}: ${error.message}`);
    }
  }
  return { deleted };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const env = process.env;
  try {
    const names = claimed(env);
    await prune(env, { call: client(env, { dryRun: false, budget: 1 + names.length }) });
  } catch (error) {
    console.log(`::warning::prune-branches: ${error.message}`);
  }
}
