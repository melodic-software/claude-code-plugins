import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, lstatSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { budgetedClient, pages } from "../lib/github-rest.mjs";
import { runAsScript } from "../lib/run-main.mjs";
import { AGGREGATE_JOBS, FAILED } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { stopSkip } from "./escalation-routes.mjs";
import { declaredPaths, exactPath, insertDeclarations, suiteComment } from "./test-scope.mjs";

export const TRAILER = "Lane-Activity: pr-unblock/fix-test-scope";
export const MAX_BOT_COMMITS = 2;
export const MAX_GAPS = 50;
export const MAX_SUITES = 20;
export const MAX_TRACE_BYTES = 1024 * 1024;
export const REQUIRED_WORKFLOW = ".github/workflows/pr-require-checks.yml";
export const TRACE_JOB = "Test Selection";
export const TRACE_STEP = "Trace the changed suites";
export const ACCEPTED_VERDICT = /^(selects |unmapped: )/;
export const REASONS = Object.freeze({ invalid: "test-scope-invalid", notAllGaps: "test-scope-not-all-gaps", gapsRemain: "test-scope-gaps-remain" });
export const DEPENDABOT_LOGIN = "dependabot[bot]";

const SHA = /^[0-9a-f]{40}$/;
const PASSED_STEP = new Set(["success", "skipped"]);

const logText = (text) => String(text).replace(/[\x00-\x1f\x7f]+/g, " ").slice(0, 200);
const refuse = (reason, why) => ({ reason, why: logText(why) });

export function traceOnlyFailure(required) {
  const jobs = Array.isArray(required?.jobs) ? required.jobs : [];
  if (required?.run?.conclusion !== "failure") {
    return false;
  }
  const failed = jobs.filter((job) => FAILED.has(job?.conclusion) && !AGGREGATE_JOBS.has(job.name));
  if (failed.length !== 1 || failed[0].name !== TRACE_JOB || failed[0].conclusion !== "failure" || !Array.isArray(failed[0].steps)) {
    return false;
  }
  const steps = failed[0].steps;
  const at = steps.findIndex((step) => step?.conclusion === "failure");
  return at !== -1 && steps[at].name === TRACE_STEP && steps.slice(0, at).every((step) => PASSED_STEP.has(step?.conclusion));
}

class TraceError extends Error {}

function table(dir, name, width) {
  const file = join(dir, name);
  const stat = lstatSync(file, { throwIfNoEntry: false });
  if (!stat?.isFile() || stat.size > MAX_TRACE_BYTES) {
    throw new TraceError(`${name} is not a regular file of at most ${MAX_TRACE_BYTES} bytes`);
  }
  const text = readFileSync(file, "utf8");
  if (/[\r\0]/.test(text)) {
    throw new TraceError(`${name} holds a carriage return or NUL`);
  }
  const lines = text.endsWith("\n") ? text.slice(0, -1).split("\n") : text === "" ? [] : text.split("\n");
  return lines.map((line, index) => {
    const fields = line.split("\t");
    if (fields.length !== width || fields.some((field) => field === "")) {
      throw new TraceError(`${name} line ${index + 1} is not ${width} tab-separated fields`);
    }
    return fields;
  });
}

export const SUITE_COLUMNS = 4;
const SUITE_ROW = /^([0-9]+|not-traced)\t[0-9]+\t[0-9]+$/;

export function readTrace(dir) {
  try {
    const suites = table(dir, "suites.tsv", SUITE_COLUMNS);
    const bad = suites.findIndex((fields) => !SUITE_ROW.test(fields.slice(1).join("\t")));
    if (bad !== -1) {
      throw new TraceError(`suites.tsv line ${bad + 1} is not suite, exit code or not-traced, seconds, read count`);
    }
    return { gaps: table(dir, "gaps.tsv", 3), suites, verdicts: table(dir, "verdicts.tsv", 2) };
  } catch (error) {
    if (error instanceof TraceError) {
      return refuse(REASONS.invalid, error.message);
    }
    throw error;
  }
}

export function traceGaps({ gaps, suites, verdicts }) {
  if (suites.some(([, status]) => status === "not-traced")) {
    return refuse(REASONS.notAllGaps, "a suite was not traced inside the budget");
  }
  if (verdicts.some(([, verdict]) => verdict.startsWith("not checked"))) {
    return refuse(REASONS.notAllGaps, "a file the suites read was not checked against the selector");
  }
  if (gaps.length === 0 || gaps.length > MAX_GAPS) {
    return refuse(REASONS.notAllGaps, `the trace lists ${gaps.length} gaps; the lane declares 1 to ${MAX_GAPS}`);
  }
  const traced = new Set(suites.map(([suite]) => suite));
  for (const [suite, file, verdict] of gaps) {
    if (!ACCEPTED_VERDICT.test(verdict)) {
      return refuse(REASONS.notAllGaps, `a gap's verdict is not one a test-scope line answers: ${verdict}`);
    }
    if (!traced.has(suite)) {
      return refuse(REASONS.invalid, `a gap names a suite the trace did not trace: ${suite}`);
    }
  }
  return { gaps: gaps.map(([suite, file]) => ({ suite, file })) };
}

const REGULAR_MODES = new Set(["100644", "100755"]);

function laneMayWrite(path) {
  const parts = path.toLowerCase().split("/");
  return parts[0] !== ".github" && parts.at(-1) !== "codeowners" && !parts.at(-1).startsWith("lane-grants");
}

export function planDeclarations({ gaps, changed, headEntry, baseHas, headText }) {
  const bySuite = new Map();
  for (const { suite, file } of gaps) {
    if (!exactPath(suite) || !exactPath(file)) {
      return refuse(REASONS.invalid, `a gap names a path that is not one exact path: ${suite} ${file}`);
    }
    bySuite.set(suite, new Set([...(bySuite.get(suite) ?? []), file]));
  }
  if (bySuite.size > MAX_SUITES) {
    return refuse(REASONS.notAllGaps, `${bySuite.size} suites have gaps; the lane declares in at most ${MAX_SUITES}`);
  }
  const files = [];
  for (const [suite, reads] of [...bySuite].sort(([a], [b]) => a.localeCompare(b))) {
    const comment = suiteComment(suite);
    if (comment === null || !laneMayWrite(suite)) {
      return refuse(REASONS.notAllGaps, `${suite} is not a suite the lane may declare in`);
    }
    if (!["added", "modified", "renamed", "copied", "changed"].includes(changed.get(suite))) {
      return refuse(REASONS.notAllGaps, `${suite} is not a suite the pull request changes`);
    }
    const entry = headEntry(suite);
    if (entry?.type !== "blob" || !REGULAR_MODES.has(entry.mode)) {
      return refuse(REASONS.invalid, `${suite} is not a regular file at the head`);
    }
    const before = headText(suite);
    const declared = new Set(declaredPaths(before, comment));
    const paths = [...reads].sort();
    for (const path of paths) {
      if (path === suite || declared.has(path)) {
        return refuse(REASONS.notAllGaps, `${suite} already declares or is ${path}`);
      }
      if (!baseHas(path) || headEntry(path)?.type !== "blob") {
        return refuse(REASONS.notAllGaps, `${path} is not a file at both the base and the head`);
      }
    }
    const after = insertDeclarations(before, comment, paths);
    if (after === null) {
      return refuse(REASONS.invalid, `${suite} has no line end to insert after`);
    }
    files.push({ path: suite, mode: entry.mode, after, paths });
  }
  return { files };
}

function gitIn(dir, extra = {}) {
  const env = { PATH: "/usr/bin:/bin", HOME: process.env.HOME ?? "/tmp", GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1", GIT_NO_REPLACE_OBJECTS: "1", GIT_TERMINAL_PROMPT: "0", ...extra };
  const flags = ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=", "-c", "core.autocrlf=false", "-c", "core.attributesFile=/dev/null", "-c", "diff.external="];
  return (args, options = {}) => execFileSync("git", [...flags, ...args], { cwd: dir, env, maxBuffer: 1 << 28, stdio: ["ignore", "pipe", "pipe"], ...options });
}

export function treeReader(dir) {
  const git = gitIn(dir);
  return {
    entry(path) {
      const line = git(["ls-tree", "-z", "HEAD", "--", path]).toString("utf8").split("\0")[0];
      if (!line) {
        return null;
      }
      const [mode, type] = line.slice(0, line.indexOf("\t")).split(" ");
      return line.slice(line.indexOf("\t") + 1) === path ? { mode, type } : null;
    },
    text: (path) => git(["cat-file", "blob", `HEAD:${path}`]).toString("utf8"),
  };
}

export function buildPatch(headDir, files) {
  const scratch = mkdtempSync(join(tmpdir(), "declare-test-scope-"));
  try {
    const git = gitIn(headDir, { GIT_INDEX_FILE: join(scratch, "index"), GIT_LITERAL_PATHSPECS: "1" });
    git(["read-tree", "HEAD"]);
    for (const file of files) {
      const sha = git(["hash-object", "-w", "--no-filters", "--stdin"], { input: Buffer.from(file.after, "utf8"), stdio: ["pipe", "pipe", "pipe"] }).toString("utf8").trim();
      git(["update-index", "--cacheinfo", `${file.mode},${sha},${file.path}`]);
    }
    const tree = git(["write-tree"]).toString("utf8").trim();
    return git(["diff", "--binary", "--full-index", "--no-renames", "--no-ext-diff", "--no-textconv", "--no-color", "HEAD", tree]).toString("utf8");
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

export async function locate({ call, repository, pr, headSha }) {
  const pull = await call("GET", `/repos/${repository}/pulls/${pr}`);
  if (pull?.head?.sha !== headSha) {
    return { skip: "superseded-sha", why: "the head moved since the select job read it" };
  }
  if (pull.head?.repo?.full_name !== repository || pull.user?.login === DEPENDABOT_LOGIN || pull.draft !== false) {
    return { skip: "not-applicable", why: "the pull request is a draft, from a fork, or Dependabot's" };
  }
  const commits = await pages(call, `/repos/${repository}/pulls/${pr}/commits`, { max: 3 });
  const ours = (commit) => String(commit?.commit?.message ?? "").split("\n").some((line) => line.trim() === TRAILER);
  if (ours(commits.at(-1)) || commits.filter(ours).length >= MAX_BOT_COMMITS) {
    return refuse(REASONS.gapsRemain, `the head is the lane's own commit, or the pull request carries ${MAX_BOT_COMMITS} of them`);
  }
  const listing = await call("GET", `/repos/${repository}/actions/runs?head_sha=${headSha}&event=pull_request&per_page=100`);
  const [run] = (listing?.workflow_runs ?? [])
    .filter((item) => item.path === REQUIRED_WORKFLOW && item.head_repository?.full_name === repository && item.status === "completed")
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.id - a.id);
  if (!run) {
    return { skip: "not-applicable", why: "no completed pull_request run of pr-require-checks at the head" };
  }
  const jobs = await pages(call, `/repos/${repository}/actions/runs/${run.id}/jobs?filter=latest`, { key: "jobs", max: 3 });
  if (!traceOnlyFailure({ run, jobs })) {
    return { skip: "not-applicable", why: `run ${run.id} did not fail at ${TRACE_STEP} alone` };
  }
  return { runId: run.id, attempt: run.run_attempt };
}

const output = (env, values) => appendFileSync(env.GITHUB_OUTPUT, Object.entries(values).map(([key, value]) => `${key}=${value}\n`).join(""));

export async function testScopeFromBase(baseDir, standardsDir) {
  const resolver = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
  return resolver.testScopeFromBase({ BASE_PATH: baseDir, STANDARDS_DIR: standardsDir });
}

export async function main(argv, env, { call, log = (line) => console.log(line), loadTestScope = testScopeFromBase } = {}) {
  const need = (keys) => {
    const missing = keys.filter((key) => !env[key]);
    if (missing.length > 0) {
      throw new Error(`${missing.join(", ")} not set`);
    }
  };
  need(["GITHUB_OUTPUT", "GITHUB_REPOSITORY", "PR_NUMBER", "HEAD_SHA"]);
  if (!/^[1-9][0-9]{0,9}$/.test(env.PR_NUMBER) || !SHA.test(env.HEAD_SHA)) {
    throw new Error("PR_NUMBER and HEAD_SHA must be a PR number and a commit id");
  }
  need(["BASE_DIR"]);
  const client = call ?? budgetedClient(env, { budget: 20 });
  let applyOn;
  const live = async () => (applyOn ??= (await loadTestScope(env.BASE_DIR, env.STANDARDS_DIR)).apply === true);
  const stop = async (reason, why) => {
    output(env, (await live()) ? { "escalation-reason": reason } : { "skip-reason": stopSkip(reason) });
    log(`declare-test-scope: ${reason}: ${why}`);
  };
  if (argv[0] === "locate") {
    const found = await locate({ call: client, repository: env.GITHUB_REPOSITORY, pr: env.PR_NUMBER, headSha: env.HEAD_SHA });
    if (found.runId) {
      output(env, { "run-id": found.runId, "run-attempt": found.attempt });
      log(`declare-test-scope: run ${found.runId} attempt ${found.attempt} failed at ${TRACE_STEP} alone`);
    } else if (found.reason) {
      await stop(found.reason, found.why);
    } else {
      output(env, { "skip-reason": found.skip });
      log(`declare-test-scope: ${found.skip}: ${found.why}`);
    }
    return 0;
  }
  if (argv[0] !== "build") {
    throw new Error("usage: declare-test-scope.mjs locate|build");
  }
  need(["TRACE_DIR", "HEAD_DIR", "PATCH_OUT"]);
  const head = treeReader(env.HEAD_DIR);
  const base = treeReader(env.BASE_DIR);
  if (gitIn(env.HEAD_DIR)(["rev-parse", "HEAD"]).toString("utf8").trim() !== env.HEAD_SHA) {
    throw new Error("the head checkout is not HEAD_SHA");
  }
  const trace = readTrace(env.TRACE_DIR);
  const gaps = trace.reason ? trace : traceGaps(trace);
  let plan = gaps;
  if (!gaps.reason) {
    const listed = await pages(client, `/repos/${env.GITHUB_REPOSITORY}/pulls/${env.PR_NUMBER}/files`, { max: 30 });
    const changed = new Map(listed.map((file) => [file.filename, file.status]));
    plan = planDeclarations({ gaps: gaps.gaps, changed, headEntry: head.entry, baseHas: (path) => base.entry(path)?.type === "blob", headText: head.text });
  }
  if (plan.reason) {
    await stop(plan.reason, plan.why);
    return 0;
  }
  const patch = buildPatch(env.HEAD_DIR, plan.files);
  writeFileSync(env.PATCH_OUT, patch);
  const declarations = plan.files.reduce((sum, file) => sum + file.paths.length, 0);
  output(env, { state: "written", sha256: createHash("sha256").update(patch).digest("hex"), suites: plan.files.length, declarations, apply: await live() });
  log(`declare-test-scope: ${declarations} declaration(s) in ${plan.files.length} suite(s): ${plan.files.map((file) => file.path).join(", ")}`);
  return 0;
}

runAsScript(import.meta.url, "declare-test-scope", () => main(process.argv.slice(2), process.env));
