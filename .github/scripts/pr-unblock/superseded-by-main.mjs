#!/usr/bin/env node
import { appendFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const OID = /^([0-9a-f]{40}|[0-9a-f]{64})$/;
const DIFF = ["--no-ext-diff", "--no-textconv", "--no-renames"];

/**
 * A git runner for the untrusted head checkout at `cwd`: no global or system
 * config, no replace refs, no hook, external diff or textconv, and
 * gitattributes read from the empty tree, so no head attribute changes what a
 * diff shows.
 */
export function gitIn(cwd) {
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1", GIT_NO_REPLACE_OBJECTS: "1" };
  delete env.GIT_ATTR_SOURCE;
  const run = (args, input) =>
    execFileSync("git", ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=", "-c", "diff.external=", ...args], {
      cwd,
      env,
      input,
      encoding: "utf8",
      maxBuffer: 1 << 30,
      stdio: ["pipe", "pipe", "pipe"],
    });
  env.GIT_ATTR_SOURCE = run(["hash-object", "-t", "tree", "/dev/null"]).trim();
  return run;
}

const commitPatchIds = (git, range) =>
  new Map(
    git(["patch-id", "--stable"], git(["log", "--no-merges", "-p", "--format=commit %H", ...DIFF, range]))
      .split("\n")
      .filter(Boolean)
      .map((line) => line.split(" ")),
  );

/**
 * Whether `base` already holds the change `head` makes, as `{ superseded, why }`.
 *
 * The rule compares patch-ids (git patch-id: a hash of a diff that ignores
 * line numbers and whitespace), as git cherry does, so it still holds after
 * the base edited the same lines again, which is the only way a change the
 * base already holds can conflict: the same edit on both sides merges
 * cleanly. The head is superseded when it adds at least one non-merge commit
 * with a diff since its merge base with the base, and either
 * - every such commit's patch-id is a non-merge base commit's since that
 *   merge base (a rebase merge or cherry-picks), or
 * - the head's net diff from the merge base has one such base commit's
 *   patch-id (a squash merge).
 * A head with any commit the base lacks (only partly superseded) is not, and
 * the model resolves its conflicts as before. A false negative costs only that
 * model run; a false positive costs only a person's look, since the lane never
 * closes the pull request.
 */
export function supersededBy(git, base, head) {
  const mergeBase = git(["merge-base", base, head]).trim();
  const own = [...commitPatchIds(git, `${mergeBase}..${head}`).keys()];
  if (own.length === 0) {
    return { superseded: false, why: "the head adds no commit with a diff of its own" };
  }
  const onBase = commitPatchIds(git, `${mergeBase}..${base}`);
  const missing = own.filter((id) => !onBase.has(id)).length;
  if (missing === 0) {
    return { superseded: true, why: `each of the head's ${own.length} change(s) has an equivalent commit on the base` };
  }
  const [net] = git(["patch-id", "--stable"], git(["diff", ...DIFF, mergeBase, head])).split(" ");
  if (net && onBase.has(net)) {
    return { superseded: true, why: `base commit ${onBase.get(net).trim()} holds the head's whole change since the merge base` };
  }
  return { superseded: false, why: `${missing} of the head's ${own.length} change(s) have no equivalent on the base` };
}

/**
 * resolve-conflicts-select's check after prepare.sh found a conflicted merge
 * and before any model turn, run from the root of the head checkout with no
 * model and no network. Reads GITHUB_OUTPUT, BASE_SHA (the pinned base) and
 * HEAD_SHA (the gated head); writes superseded=true|false. A failed git read
 * writes false with a warning, so the model resolves as before: the check is
 * local, so a retry on the same head and base would fail the same way.
 */
export function main(env, { cwd = process.cwd(), log = (line) => console.log(line) } = {}) {
  for (const key of ["GITHUB_OUTPUT", "BASE_SHA", "HEAD_SHA"]) {
    if (!env[key]) throw new Error(`${key} is not set`);
  }
  for (const key of ["BASE_SHA", "HEAD_SHA"]) {
    if (!OID.test(env[key])) throw new Error(`${key} is not a full commit id`);
  }
  let verdict;
  try {
    verdict = supersededBy(gitIn(cwd), env.BASE_SHA, env.HEAD_SHA);
  } catch (error) {
    appendFileSync(env.GITHUB_OUTPUT, "superseded=false\n");
    log(`::warning title=superseded-check::the check failed, so the model resolves as before: ${annotation(error.message)}`);
    return 0;
  }
  appendFileSync(env.GITHUB_OUTPUT, `superseded=${verdict.superseded}\n`);
  log(`::notice title=superseded-check::superseded=${verdict.superseded} head=${env.HEAD_SHA} base=${env.BASE_SHA}: ${verdict.why}`);
  return 0;
}

const annotation = (text) => String(text).replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.env);
  } catch (error) {
    console.log(`::error::superseded check failed: ${annotation(error.message)}`);
    process.exitCode = 1;
  }
}
