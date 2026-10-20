#!/usr/bin/env node
// apply-ci-fix.mjs: the pr-unblock lane's apply-ci-fix activity, a script with no
// model that applies the patch the fix-ci model job left and pushes it. It
// runs no PR head code: git reads the patch and the checkout's objects, with
// hooks, fsmonitor and every global and system config off.
//
//   select  run by .github/workflows/pr-run-activity-write.yml for
//           `prepare: apply-patch`, before the mint and the head checkout,
//           with no token: checks the downloaded patch artifact (exactly one
//           regular patch.diff, at most 1 MiB, with the model job's SHA-256)
//           and that the PR head is still the one the model job worked on, and
//           reads the model's report. A moved head skips superseded-sha; an
//           empty or invalid patch hands the PR to a person.
//   (none)  the activity's script step, after the head checkout, with the
//           lane token: applies the patch to the index with no --unsafe-paths,
//           refuses the whole patch when any change is under .github/
//           (thread-scope.mjs's isProtectedPath) or an instruction path, or is
//           a symbolic link or gitlink, re-reads the hold labels and draft
//           state, then commits
//           the tree on the gated head through the Git Data API and moves the
//           PR branch without force.
//
// Environment, select: GITHUB_OUTPUT, PATCH_STATE, PATCH_SHA256,
// PATCH_HEAD_SHA, HEAD_SHA, PATCH_DIR, REPORT_DIR (the model job's reply,
// may be empty). Script step: GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER, HEAD_SHA,
// HEAD_REF, PATCH_FILE, PATCH_SHA256, HOLD_LABELS, SKIP_REASON_FILE,
// ESCALATION_REASON_FILE.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, lstatSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { createGitHubApi, need, positive, SHA } from "./address-feedback.mjs";
import { isInstructionPath, isProtectedPath } from "./thread-scope.mjs";
import { FIX_TRAILER } from "./fix-ci-context.mjs";

export const MAX_PATCH_BYTES = 1024 * 1024;
const REASONS = "not-reproducible|flaky|protected-path|weaken-required|unfixed";
const ESCALATED_LINE = new RegExp(`^(.+?): escalated (?:${REASONS})(?: |$)`);
const SYMLINK = "120000";
const GITLINK = "160000";
const ZERO = /^0+$/;
// .github/ and the paths the harness or the forge reads as instructions or
// ownership (thread-scope.mjs's isInstructionPath), at any depth and in any
// case. Code and test files stay editable, so fix-ci can fix a check's own
// script.
export const refusedPath = (path) => isProtectedPath(path) || isInstructionPath(path);

// The checks the ci --ci report escalated, one per `<check>: escalated
// <reason> <sentence>` line. The report is model output: only this shape is
// read, and only to decide whether a person is needed.
export function escalatedChecks(text) {
  return String(text)
    .split("\n")
    .map((line) => ESCALATED_LINE.exec(line.replace(/\r$/, ""))?.[1])
    .filter(Boolean);
}

function reportEscalates(reportDir) {
  const file = reportDir ? join(reportDir, "reply.txt") : "";
  if (!file || !existsSync(file) || !lstatSync(file).isFile()) {
    return false;
  }
  return escalatedChecks(readFileSync(file, "utf8")).length > 0;
}

const sha256Of = (bytes) => createHash("sha256").update(bytes).digest("hex");

// A regular file of at most MAX_PATCH_BYTES whose SHA-256 is the one given.
function patchMatches(file, expected) {
  if (!/^[0-9a-f]{64}$/.test(String(expected)) || !existsSync(file)) {
    return false;
  }
  const stat = lstatSync(file);
  if (!stat.isFile() || stat.size === 0 || stat.size > MAX_PATCH_BYTES) {
    return false;
  }
  return sha256Of(readFileSync(file)) === expected;
}

export function select({ patchState, patchSha256, patchHeadSha, headSha, patchDir, reportDir }) {
  const decide = (proceed, skipReason, escalationReason) => ({ proceed, skipReason, escalationReason });
  const escalated = reportEscalates(reportDir);
  if (patchState !== "written" && patchState !== "empty") {
    return decide(false, "awaiting-human", "ci-fix-invalid");
  }
  if (!SHA.test(String(patchHeadSha)) || patchHeadSha !== headSha) {
    return decide(false, "superseded-sha", "");
  }
  if (patchState === "empty") {
    return decide(false, "awaiting-human", escalated ? "ci-fix-escalated" : "ci-fix-empty");
  }
  let names = [];
  try {
    names = readdirSync(patchDir);
  } catch {
    names = [];
  }
  if (names.length !== 1 || names[0] !== "patch.diff" || !patchMatches(join(patchDir, "patch.diff"), patchSha256)) {
    return decide(false, "awaiting-human", "ci-fix-invalid");
  }
  return decide(true, "", escalated ? "ci-fix-escalated" : "");
}

// git with an allowlisted environment, so nothing the job's env or the
// checkout's config names runs.
function gitRunner(cwd, gitBin) {
  const env = {
    PATH: "/usr/bin:/bin",
    HOME: process.env.HOME ?? "/tmp",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_NO_REPLACE_OBJECTS: "1",
    GIT_TERMINAL_PROMPT: "0",
  };
  const flags = ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=", "-c", "diff.external="];
  return (args, options = {}) => execFileSync(gitBin, [...flags, ...args], { cwd, env, maxBuffer: 1 << 28, stdio: ["ignore", "pipe", "pipe"], ...options });
}

// `git diff-tree -r -z --no-renames` raw output: one entry per changed path.
function changes(raw) {
  const fields = raw.toString("utf8").split("\0");
  const entries = [];
  for (let i = 0; i + 1 < fields.length; i += 2) {
    const [oldMode, newMode, , newSha] = fields[i].replace(/^:/, "").split(" ");
    entries.push({ oldMode, newMode, newSha, path: fields[i + 1] });
  }
  return entries;
}

export async function push({ api, cwd, gitBin = "/usr/bin/git", pr, headSha, headRef, patchFile, patchSha256, holdLabels, log }) {
  if (!patchMatches(patchFile, patchSha256)) {
    return { outcome: "escalate", escalationReason: "ci-fix-invalid" };
  }
  const git = gitRunner(cwd, gitBin);
  // The patch applies to the gated head's tree, whatever the index holds.
  git(["read-tree", headSha]);
  try {
    git(["apply", "--cached", "--check", patchFile]);
  } catch {
    return { outcome: "escalate", escalationReason: "ci-fix-not-applied" };
  }
  git(["apply", "--cached", patchFile]);
  const tree = git(["write-tree"]).toString("utf8").trim();
  const entries = changes(git(["diff-tree", "-r", "-z", "--no-renames", headSha, tree]));
  if (entries.length === 0) {
    return { outcome: "escalate", escalationReason: "ci-fix-invalid" };
  }
  // One refused entry refuses the whole patch, before anything is written.
  if (entries.some((entry) => refusedPath(entry.path))) {
    return { outcome: "escalate", escalationReason: "ci-fix-protected-path" };
  }
  if (entries.some((entry) => [entry.oldMode, entry.newMode].some((mode) => mode === SYMLINK || mode === GITLINK))) {
    return { outcome: "escalate", escalationReason: "ci-fix-invalid" };
  }
  // A hold or a draft set while the model worked stops the push, as the
  // write runner's promote step does.
  const holds = new Set(holdLabels);
  const [pull, labels] = [await api.getPull(pr), await api.listLabels(pr)];
  if (pull.draft !== false || labels.some((label) => holds.has(label.name))) {
    log("the pull request is held or a draft; the fix is dropped");
    return { outcome: "held" };
  }
  const tip = await api.readBranch(headRef);
  if (tip !== headSha) {
    throw new Error(`the PR branch moved from ${headSha} to ${tip}; the fix is not pushed`);
  }
  const treeEntries = [];
  for (const entry of entries) {
    if (ZERO.test(entry.newSha)) {
      treeEntries.push({ path: entry.path, mode: entry.oldMode, type: "blob", sha: null });
      continue;
    }
    const content = git(["cat-file", "blob", entry.newSha]).toString("base64");
    const sha = await api.createBlob(content);
    if (sha !== entry.newSha) {
      throw new Error(`GitHub stored a blob as ${sha}, not ${entry.newSha}`);
    }
    treeEntries.push({ path: entry.path, mode: entry.newMode, type: "blob", sha });
  }
  const headTree = (await api.getCommit(headSha)).commit.tree.sha;
  const built = await api.createTree(headTree, treeEntries);
  if (built !== tree) {
    throw new Error(`GitHub built tree ${built}, not the applied tree ${tree}; nothing is committed`);
  }
  const message = `Fix failing CI checks on ${headRef}\n\n${FIX_TRAILER}\n`;
  const commit = await api.createCommit(message, tree, [headSha]);
  // force: false refuses anything but a fast-forward from the gated head.
  await api.updateRef(`heads/${headRef}`, commit, false);
  const moved = await api.readBranch(headRef);
  if (moved !== commit) {
    throw new Error(`the PR branch reads ${moved} after the update to ${commit}`);
  }
  log(`pushed ${commit} (${entries.length} path(s)) onto ${headRef}`);
  return { outcome: "pushed", commit };
}

export async function main(argv, env, { api, cwd = process.cwd(), gitBin, log = (line) => console.log(line) } = {}) {
  if (argv[0] === "select") {
    need(env, ["GITHUB_OUTPUT", "HEAD_SHA"]);
    const result = select({
      patchState: env.PATCH_STATE ?? "",
      patchSha256: env.PATCH_SHA256 ?? "",
      patchHeadSha: env.PATCH_HEAD_SHA ?? "",
      headSha: env.HEAD_SHA,
      patchDir: env.PATCH_DIR ?? "",
      reportDir: env.REPORT_DIR ?? "",
    });
    appendFileSync(
      env.GITHUB_OUTPUT,
      `proceed=${result.proceed}\nskip-reason=${result.skipReason}\nescalation-reason=${result.escalationReason}\n`,
    );
    log(`select: proceed=${result.proceed} skip=${result.skipReason || "none"} escalation=${result.escalationReason || "none"}`);
    return 0;
  }
  if (argv.length > 0) {
    throw new Error("usage: apply-ci-fix.mjs [select]");
  }
  need(env, ["GH_TOKEN", "GITHUB_REPOSITORY", "PR_NUMBER", "HEAD_SHA", "HEAD_REF", "PATCH_FILE", "HOLD_LABELS", "SKIP_REASON_FILE", "ESCALATION_REASON_FILE"]);
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const holdLabels = JSON.parse(env.HOLD_LABELS);
  if (!Array.isArray(holdLabels) || !holdLabels.every((label) => typeof label === "string")) {
    throw new Error("HOLD_LABELS is not a list of labels");
  }
  const client =
    api ??
    createGitHubApi({
      token: env.GH_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
    });
  const result = await push({
    api: client,
    cwd,
    gitBin,
    pr: positive(env.PR_NUMBER, "PR_NUMBER"),
    headSha: env.HEAD_SHA,
    headRef: env.HEAD_REF,
    patchFile: env.PATCH_FILE,
    patchSha256: env.PATCH_SHA256 ?? "",
    holdLabels: ["do-not-merge", ...holdLabels],
    log,
  });
  if (result.outcome === "escalate") {
    writeFileSync(env.ESCALATION_REASON_FILE, `${result.escalationReason}\n`);
  }
  if (result.outcome !== "pushed") {
    writeFileSync(env.SKIP_REASON_FILE, "awaiting-human\n");
  }
  log(`apply-ci-fix: ${result.outcome}${result.escalationReason ? ` (${result.escalationReason})` : ""}`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::apply-ci-fix failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
