#!/usr/bin/env node
// apply-patch.mjs: the one script that applies a read model job's patch and
// commits it, with no model and no producer code run. Its target picks the row
// of patch-rules.json, read from the trusted base checkout (BASE_DIR), never
// from the head: a pull request target takes the producer's prepare-mode row
// (`default` for none) and moves the PR branch on from the gated head; the
// issue target takes the `issue` row and makes a new lane branch at the commit
// the producer started from. A lane changes what is admitted by registering a
// row or a predicate, never by a branch here.
//
//   select  before the mint and the head checkout, with no token: checks the
//           downloaded artifact (exactly one regular patch.diff, at most 1 MiB,
//           with the model job's SHA-256 and no credential shape) and reads the
//           row's producer report. An empty or invalid patch hands the work to
//           a person.
//   (none)  after the checkout of the start commit, with the lane token:
//           checks the row and builds its allow predicates (an unknown name
//           throws before any write), checks the row's requirements and the
//           patch again, applies it to the index with git's hooks and config
//           off, and refuses the whole patch when any change matches a
//           refusal, exceeds max-files, fails an allow predicate or the row's
//           content rule, or a new blob carries a credential shape. On a PR, a
//           head that moved since
//           the model job skips superseded-sha under a skip-moved-head row,
//           and otherwise takes the patch with --3way only when the moved
//           commits touch no patched path, else it skips superseded-sha; an
//           issue patch applies only to the commit it was made on. It then
//           re-reads the holds (a PR's labels and draft state, or an issue's
//           hold and required labels), commits the tree through the Git Data
//           API, checks the tree hash, and moves the PR branch with
//           force: false or creates the new branch, which fails if it exists.
//           Under a merge row (parents [head, base]) the checkout holds the
//           merge of the pinned base the write runner just ran (prepare.sh):
//           the patch applies to the conflict tree T0, never the head; only
//           its own changes face the refusals, max-files, merge-result and
//           the credential and size checks, while the merge's base-side
//           changes pass through. Every originally conflicted path must be
//           left marker-free, a workflow change must be exactly the base's,
//           and the commit has the head and the base as parents. A clean
//           merge needs no patch.
//
// Environment, both: BASE_DIR, PATCH_PREPARE (empty for none), PATCH_TARGET
// (pr, the default, or issue). Select: GITHUB_OUTPUT, PATCH_STATE,
// PATCH_SHA256, PATCH_HEAD_SHA, HEAD_SHA, PATCH_DIR, REPORT_DIR. Script step:
// GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER (pr) or ISSUE_NUMBER,
// REQUIRED_LABELS (a JSON list) and PATCH_BASE_SHA (the default-branch commit
// the refusals measure from) (issue), HEAD_SHA, PATCH_HEAD_SHA, HEAD_REF (the
// PR branch, or the new `<lane>/issue-<n>-<run id>-<attempt>` branch), LANE,
// PATCH_ACTIVITY, PATCH_FILE, PATCH_SHA256, HOLD_LABELS, SKIP_REASON_FILE,
// ESCALATION_REASON_FILE; optional BASE_REF, KEPT_THREADS_FILE (the select
// job's threads.json, whose threads' path and named_paths the kept-threads
// predicate reads), DEPENDENCY_VERDICT (the scanned verdict the
// dependency-verdict requirement reads) and GITHUB_OUTPUT (gets commit=<sha>
// and branch=<ref>). A row that allows dependency-manifests reads the
// [ecosystem, directory] pairs from BASE_DIR's .github/dependabot.yml. A merge
// row: select reads MERGE_STATE (clean or conflicted); the script step also
// MERGE_BASE_SHA (the pinned base, the second parent), CONFLICT_TREE (T0,
// which the runner checked against the select job's), BASE_REF, and
// TREE_ENTRIES_SCRIPT with TREE_ENTRIES_SHA256 (the base copy of
// tree-entries.sh); it reads the conflicted paths from the checkout's index.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, lstatSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { fixRefusal, parseConfig } from "../pr-unblock/dependency-classify.mjs";
import { PREDICATES } from "./predicates.mjs";

export const MAX_PATCH_BYTES = 1024 * 1024;
// A compressed binary patch inflates: any one patched blob, and all of them
// together, are capped before any is read.
export const MAX_BLOB_BYTES = 5 * 1024 * 1024;
export const MAX_TOTAL_BLOB_BYTES = 20 * 1024 * 1024;
export const RULES_PATH = ".github/actions/resolve-config/patch-rules.json";
export const DEPENDABOT_PATH = ".github/dependabot.yml";
const SHA = /^[0-9a-f]{40}$/;
const NAME = /^[a-z][a-z0-9-]*$/;
const SYMLINK = "120000";
const GITLINK = "160000";
const REGULAR = "100644";
const EXECUTABLE = "100755";
const ZERO = /^0+$/;

// A path's segments in lower case with `.`, `..` and empty segments resolved,
// so `.GitHub/x` and `a/../.github/x` read as `.github/x`.
export function segments(path) {
  const out = [];
  for (const part of String(path).toLowerCase().split("/")) {
    if (part === "..") {
      out.pop();
    } else if (part !== "" && part !== ".") {
      out.push(part);
    }
  }
  return out;
}

const PATH_RULES = {
  // The lane token has no workflows permission, so GitHub refuses the push.
  "github-workflows": (s) => s[0] === ".github" && s[1] === "workflows",
  // The three places GitHub reads a CODEOWNERS file from
  // (docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners,
  // as of 2026-10-22; recheck when that page names another location).
  codeowners: (s) => s.at(-1) === "codeowners" && (s.length === 1 || (s.length === 2 && [".github", "docs"].includes(s[0]))),
  gitmodules: (s) => s.at(-1) === ".gitmodules",
  settings: (s) => /^settings[^/]*\.json$/.test(s.at(-1) ?? ""),
};
const pathRule = (name) => (entry) => PATH_RULES[name](segments(entry.path));
const pathRefused = (path) => Object.values(PATH_RULES).some((rule) => rule(segments(path))) || path.includes("\\");

// The refusal table. Every row must name every refusal but those in ALWAYS,
// which apply to every row unnamed; any match refuses the whole patch, and
// `kind` picks the row's escalation reason.
export const ALWAYS = ["backslash"];
export const REFUSALS = {
  // A backslash reads as a directory separator on Windows checkouts.
  backslash: { kind: "protected-path", test: (entry) => entry.path.includes("\\") },
  "github-workflows": { kind: "protected-path", test: pathRule("github-workflows") },
  codeowners: { kind: "protected-path", test: pathRule("codeowners") },
  gitmodules: { kind: "protected-path", test: pathRule("gitmodules") },
  settings: { kind: "protected-path", test: pathRule("settings") },
  symlink: { kind: "invalid", test: (entry) => entry.oldMode === SYMLINK || entry.newMode === SYMLINK },
  gitlink: { kind: "invalid", test: (entry) => entry.oldMode === GITLINK || entry.newMode === GITLINK },
  "rename-into-refused": { kind: "protected-path", test: (entry) => entry.renamedFrom !== undefined && pathRefused(entry.path) },
};

// The names of the refusals that match one changed entry; by default all.
export const refusalsOf = (entry, names = Object.keys(REFUSALS)) => names.filter((name) => REFUSALS[name].test(entry));

// Credential shapes: any match in the patch or a patched blob refuses it all.
// GitHub prefixes from
// https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#githubs-token-formats
// and the ghs_ regex GitHub recommends for current and stateless installation tokens from
// https://github.blog/changelog/2026-05-15-github-app-installation-tokens-per-request-override-header/
// (as of 2026-10-21; recheck when GitHub changes a token format or its recommended regex).
export const CREDENTIALS = [
  { name: "Anthropic API key", pattern: /sk-ant-(?:api|admin)\d{2}-[A-Za-z0-9_-]{20,}/ },
  { name: "Anthropic OAuth token", pattern: /sk-ant-oat\d{2}-[A-Za-z0-9_-]{20,}/ },
  { name: "GitHub token", pattern: /\b(?:gh[pousr]_[A-Za-z0-9]{36,}|ghs_[A-Za-z0-9._-]{36,}|github_pat_[A-Za-z0-9_]{22,})/ },
];
export const credentialIn = (text) => CREDENTIALS.find((credential) => credential.pattern.test(text))?.name ?? "";

const REASONS = "not-reproducible|flaky|protected-path|weaken-required|unfixed";
const ESCALATED_LINE = new RegExp(`^(.+?): escalated (?:${REASONS})(?: |$)`);

const ESCALATED_REASON = new RegExp(`^.+?: escalated (${REASONS})(?: |$)`);
// The reasons a fix-ci retry one model rung up may answer; protected-path,
// weaken-required and flaky stay with a person.
const RUNG_UP_REASONS = new Set(["unfixed", "not-reproducible"]);

const reportLines = (text) => String(text).split("\n").map((line) => line.replace(/\r$/, ""));

// The checks a report escalated, one per `<check>: escalated <reason>
// <sentence>` line. The report is model output: only this shape is read.
export function escalatedChecks(text) {
  return reportLines(text)
    .map((line) => ESCALATED_LINE.exec(line)?.[1])
    .filter(Boolean);
}

// Whether a report escalated at least one check and every escalation is one
// a stronger model may answer.
export function rungUpEscalation(text) {
  const reasons = reportLines(text).flatMap((line) => ESCALATED_REASON.exec(line)?.[1] ?? []);
  return reasons.length > 0 && reasons.length === escalatedChecks(text).length && reasons.every((reason) => RUNG_UP_REASONS.has(reason));
}

const reportText = (reportDir) => {
  const file = reportDir ? join(reportDir, "reply.txt") : "";
  return Boolean(file) && existsSync(file) && lstatSync(file).isFile() ? readFileSync(file, "utf8") : "";
};

// The producer reports a row may read: each says whether the model escalated,
// and whether a retry one model rung up may answer every escalation.
const REPORTS = {
  "ci-escalations": {
    escalated: (reportDir) => escalatedChecks(reportText(reportDir)).length > 0,
    rungUp: (reportDir) => rungUpEscalation(reportText(reportDir)),
  },
};

// What the producer's output must say before anything applies.
const REQUIREMENTS = {
  "dependency-verdict: fix": (context) => context.dependencyVerdict === "fix",
};

// git's raw status letter as the REST file listing names it.
const STATUS = { M: "modified", A: "added", D: "removed", T: "changed" };

// A row's content rule: what each changed file's bytes must also meet, read
// from the local objects. It returns the first refusal, or null.
export const CONTENT_RULES = {
  // A version change of a regular npm or pip manifest or lock file modified in
  // place, as dependency-classify.mjs's fixRefusal decides; the verdict job
  // runs the same rule again on what landed.
  "dependency-version-change": async ({ entries, git, context }) => {
    const byPath = new Map(entries.map((entry) => [entry.path, entry]));
    const blob = (sha) => (ZERO.test(sha) ? null : git(["cat-file", "blob", sha]).toString("utf8"));
    return fixRefusal(
      entries.map((entry) => ({ filename: entry.path, status: STATUS[entry.status?.[0]] ?? String(entry.status) })),
      context.dependabotConfig,
      {
        entry: async (path) => {
          const mode = byPath.get(path).newMode;
          return { type: mode === GITLINK ? "commit" : "blob", mode: Number.parseInt(mode, 8) };
        },
        text: async (side, path) => blob(side === "before" ? byPath.get(path).oldSha : byPath.get(path).newSha),
      },
    );
  },
};

export function loadRules(baseDir) {
  if (!baseDir) {
    throw new Error("BASE_DIR, the trusted base checkout, is not set");
  }
  return JSON.parse(readFileSync(join(baseDir, RULES_PATH), "utf8"));
}

const laneBranch = (lane, issue) => new RegExp(`^${lane}/issue-${issue}-[1-9][0-9]*-[1-9][0-9]*$`);

// Where a target's commit goes. `row` names the row it reads; `number` the
// push argument that names its PR or issue, and `env` the script step
// variables it needs past the shared ones (its number first); `held` re-reads
// what stops the commit; `ready` checks the ref before any write; `write`
// moves or makes it.
export const TARGETS = {
  pr: {
    row: (prepare) => prepare || "default",
    number: "pr",
    env: ["PR_NUMBER"],
    movedHead: true,
    checkRef: () => "",
    // The push goes to this repository's branch only: a fork head throws.
    async held(api, number, { holds, repository }) {
      const [pull, labels] = [await api.getPull(number), await api.listLabels(number)];
      if (pull.head?.repo?.full_name !== repository) {
        throw new Error(`the PR head is ${pull.head?.repo?.full_name ?? "unreadable"}, not ${repository}; the patch is not pushed`);
      }
      return pull.draft !== false || labels.some((label) => holds.has(label.name));
    },
    async ready(api, ref, head) {
      const tip = await api.readBranch(ref);
      if (tip !== head) {
        throw new Error(`the PR branch moved from ${head} to ${tip}; the patch is not pushed`);
      }
    },
    // force: false refuses anything but a fast-forward from the gated head.
    write: (api, ref, commit) => api.updateRef(`heads/${ref}`, commit, false),
  },
  issue: {
    row: () => "issue",
    number: "issue",
    env: ["ISSUE_NUMBER", "REQUIRED_LABELS", "PATCH_BASE_SHA"],
    movedHead: false,
    checkRef: (ref, { lane, issue }) => (laneBranch(lane, issue).test(String(ref)) ? "" : `${ref} is not a ${lane}/issue-${issue}-<run id>-<attempt> branch`),
    // A hold label added, or a required label (agent-ready) removed, while
    // the model worked stops the commit.
    async held(api, number, { holds, required }) {
      const names = new Set((await api.listLabels(number)).map((label) => label.name));
      return [...names].some((name) => holds.has(name)) || required.some((name) => !names.has(name));
    },
    // The branch is new: creating it fails when it exists, so nothing is read first.
    ready: async () => {},
    write: (api, ref, commit) => api.createRef(`refs/heads/${ref}`, commit),
  },
};

// The producer's row: the target's, which for a PR is its prepare mode's, or
// `default` when it has none.
export function rowFor(rules, { prepare = "", target = "pr" } = {}) {
  if (!Object.hasOwn(TARGETS, target)) {
    throw new Error(`unknown patch target ${target}`);
  }
  const name = TARGETS[target].row(prepare);
  const owner = Object.keys(TARGETS).find((other) => other !== target && TARGETS[other].row("") === name);
  if (owner) {
    throw new Error(`the \`${name}\` row belongs to the ${owner} target`);
  }
  if (!Object.hasOwn(rules, name)) {
    throw new Error(`patch-rules.json has no \`${name}\` row`);
  }
  return { name, target, ...rules[name] };
}

// Every name the row uses is known and the universal refusals are all there;
// otherwise it throws, before anything is applied or written.
export function checkRow(row) {
  const unknown = (names, known) => names.filter((name) => !Object.hasOwn(known, name));
  const fail = (message) => {
    throw new Error(`patch-rules.json row \`${row.name}\` ${message}`);
  };
  const missing = Object.keys(REFUSALS).filter((name) => !ALWAYS.includes(name) && !row.refuse?.includes(name));
  if (missing.length > 0) {
    fail(`does not refuse ${missing.join(", ")}`);
  }
  // push reads every requirement before anything applies.
  if (!Array.isArray(row.requires)) {
    fail("has no requires list");
  }
  for (const [what, names, known] of [
    ["refusal", row.refuse, REFUSALS],
    ["predicate", row.allow ?? [], PREDICATES],
    ["requirement", row.requires, REQUIREMENTS],
  ]) {
    const bad = unknown(names, known);
    if (bad.length > 0) {
      fail(`names an unknown ${what}: ${bad.join(", ")}`);
    }
  }
  if (!Array.isArray(row.allow) || row.allow.length === 0) {
    fail("allows nothing");
  }
  if (row["content-rule"] !== undefined && !Object.hasOwn(CONTENT_RULES, String(row["content-rule"]))) {
    fail(`names an unknown content rule: ${row["content-rule"]}`);
  }
  if (row["reads-report"] !== null && !Object.hasOwn(REPORTS, row["reads-report"])) {
    fail(`reads an unknown report: ${row["reads-report"]}`);
  }
  if (row["max-files"] !== null && !(Number.isInteger(row["max-files"]) && row["max-files"] > 0)) {
    fail("has a max-files that is not a positive integer or null");
  }
  const parents = JSON.stringify(row.commit?.parents);
  if (parents === '["head","base"]') {
    // A merge commit only for a PR, and only of the conflicted paths' resolutions.
    if (JSON.stringify(row.allow) !== '["merge-result"]' || row.target !== "pr") {
      fail("commits a merge but does not allow merge-result alone on a pull request");
    }
    if (!(Number.isInteger(row["max-blobs"]) && row["max-blobs"] > 0)) {
      fail("commits a merge with no max-blobs");
    }
  } else if (parents !== '["head"]') {
    fail("commits with parents this apply-patch does not support");
  } else if (row.allow?.includes("merge-result") || row["max-blobs"] !== undefined) {
    fail("allows merge-result or sets max-blobs but does not commit a merge");
  }
  if (!row.escalations?.some((reason) => reason.endsWith("-invalid"))) {
    fail("has no -invalid escalation reason");
  }
  if (!Object.hasOwn(TARGETS, String(row.target))) {
    fail(`names an unknown target: ${row.target}`);
  }
  return row;
}

// A merge row commits with the head and the base as parents.
export const isMerge = (row) => row.commit?.parents?.length === 2;

// The row's reason for a kind of outcome, else its -invalid reason.
export const reasonFor = (row, kind) =>
  row.escalations.find((reason) => reason.endsWith(`-${kind}`)) ?? row.escalations.find((reason) => reason.endsWith("-invalid"));

// The reason the push writes to the escalation file for a kind: a patch that
// applies but changes nothing is the row's empty-at-push kind (ci-context:
// invalid, since the producer said it wrote a change), else its empty reason.
export const pushReason = (row, kind) => reasonFor(row, kind === "empty" ? (row["empty-at-push"] ?? "empty") : kind);

// The commit message with the row's placeholders filled; a placeholder with no
// value throws.
export function commitMessage(row, values) {
  const fill = (text) =>
    text.replace(/\{(ref|base|lane|activity|issue)\}/g, (_, key) => {
      if (!values[key]) {
        throw new Error(`the commit message needs {${key}}, which this run does not give`);
      }
      return values[key];
    });
  return `${fill(row.commit.message)}\n\n${fill(row.commit.trailer)}\n`;
}

const sha256Of = (bytes) => createHash("sha256").update(bytes).digest("hex");

// Why the patch file is not to be applied, or "" when it is: a regular file of
// at most MAX_PATCH_BYTES with the SHA-256 given and no credential shape.
export function patchProblem(file, expected) {
  if (!/^[0-9a-f]{64}$/.test(String(expected)) || !existsSync(file)) {
    return "the patch or its SHA-256 is missing";
  }
  const stat = lstatSync(file);
  if (!stat.isFile() || stat.size === 0 || stat.size > MAX_PATCH_BYTES) {
    return "the patch is not one regular file of at most 1 MiB";
  }
  const bytes = readFileSync(file);
  if (sha256Of(bytes) !== expected) {
    return "the patch does not match its SHA-256";
  }
  const credential = credentialIn(bytes.toString("latin1"));
  return credential ? `the patch carries a ${credential} shape` : "";
}

// `rung` is the producer's model rung (0 or 1): at 0, an empty patch whose
// report escalated only checks a stronger model may answer skips rung-up, and
// the caller runs the producer once more at rung 1, instead of escalating.
export function select({ row, patchState, patchSha256, patchHeadSha, headSha, patchDir, reportDir, rung = 0, mergeState = "" }) {
  checkRow(row);
  const decide = (proceed, skipReason, escalationReason) => ({ proceed, skipReason, escalationReason });
  // A merge row: a clean merge commits with no patch; a conflicted one needs
  // the model's patch, and an empty one leaves the conflicts as git left them.
  if (isMerge(row)) {
    if (mergeState !== "clean" && mergeState !== "conflicted") {
      return decide(false, "awaiting-human", reasonFor(row, "invalid"));
    }
    if (!SHA.test(String(patchHeadSha)) || !SHA.test(String(headSha)) || patchHeadSha !== headSha) {
      return decide(false, "superseded-sha", "");
    }
    if (mergeState === "clean") {
      return patchState === "" ? decide(true, "", "") : decide(false, "awaiting-human", reasonFor(row, "invalid"));
    }
    if (patchState === "empty") {
      return decide(false, "awaiting-human", pushReason(row, "empty"));
    }
  }
  const report = row["reads-report"] === null ? null : REPORTS[row["reads-report"]];
  const escalated = report !== null && report.escalated(reportDir);
  if (patchState !== "written" && patchState !== "empty") {
    return decide(false, "awaiting-human", reasonFor(row, "invalid"));
  }
  if (!SHA.test(String(patchHeadSha)) || !SHA.test(String(headSha)) || (row["skip-moved-head"] === true && patchHeadSha !== headSha)) {
    return decide(false, "superseded-sha", "");
  }
  if (patchState === "empty") {
    if (escalated && rung === 0 && report.rungUp(reportDir)) {
      return decide(false, "rung-up", "");
    }
    return decide(false, "awaiting-human", reasonFor(row, escalated ? "escalated" : "empty"));
  }
  let names = [];
  try {
    names = readdirSync(patchDir);
  } catch {
    names = [];
  }
  if (names.length !== 1 || names[0] !== "patch.diff" || patchProblem(join(patchDir, "patch.diff"), patchSha256)) {
    return decide(false, "awaiting-human", reasonFor(row, "invalid"));
  }
  return decide(true, "", escalated ? reasonFor(row, "escalated") : "");
}

// git with an allowlisted environment, so nothing the job's env or the
// checkout's config names runs. `extra` adds variables: a merge row reads
// attributes from the base tree and works in a scratch index, never the
// merge's own.
function gitRunner(cwd, gitBin, extra = {}) {
  const env = {
    PATH: "/usr/bin:/bin",
    HOME: process.env.HOME ?? "/tmp",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_NO_REPLACE_OBJECTS: "1",
    GIT_TERMINAL_PROMPT: "0",
    ...extra,
  };
  const flags = ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=", "-c", "diff.external="];
  return (args, options = {}) => execFileSync(gitBin, [...flags, ...args], { cwd, env, maxBuffer: 1 << 28, stdio: ["ignore", "pipe", "pipe"], ...options });
}

// `git diff-tree -r -z` raw output: one entry per changed path, with the old
// path of a rename when rename detection ran.
function changes(raw) {
  const fields = raw.toString("utf8").split("\0");
  const entries = [];
  for (let i = 0; i + 1 < fields.length; ) {
    const [oldMode, newMode, oldSha, newSha, status] = fields[i].replace(/^:/, "").split(" ");
    if (/^[RC]/.test(status)) {
      entries.push({ oldMode, newMode, oldSha, newSha, status, renamedFrom: fields[i + 1], path: fields[i + 2] });
      i += 3;
    } else {
      entries.push({ oldMode, newMode, oldSha, newSha, status, path: fields[i + 1] });
      i += 2;
    }
  }
  return entries;
}

// The tree the patch makes on a commit's tree, or "" when it does not apply.
function applyOnto(git, sha, patchFile, threeWay) {
  try {
    git(["read-tree", sha]);
    const flags = threeWay ? ["--3way"] : [];
    git(["apply", "--cached", "--check", ...flags, patchFile]);
    git(["apply", "--cached", ...flags, patchFile]);
    return git(["write-tree"]).toString("utf8").trim();
  } catch {
    return "";
  }
}

// A script by the exec-bit rule: a regular file that ends in .sh or whose
// blob starts with #!. The mode is checked first, so no gitlink's commit or
// symlink is read as a blob.
const isScript = (git, entry) =>
  [REGULAR, EXECUTABLE].includes(entry.newMode) &&
  (entry.path.endsWith(".sh") || git(["cat-file", "blob", entry.newSha]).subarray(0, 2).toString("latin1") === "#!");

const hasCommit = (git, sha) => {
  try {
    git(["cat-file", "-e", `${sha}^{commit}`]);
    return true;
  } catch {
    return false;
  }
};

// Marker lines in order, any length from seven (conflict-marker-size): a run of
// <, then a run of =, then a run of >, the outer two followed by a space or the
// line end. prepare.sh holds the same rule as an awk program.
export function hasConflictMarkers(text) {
  let state = 0;
  for (const line of String(text).replaceAll("\r", "").split("\n")) {
    if (state === 0 && /^<{7,}( |$)/.test(line)) {
      state = 1;
    } else if (state === 1 && /^={7,}$/.test(line)) {
      state = 2;
    } else if (state === 2 && /^>{7,}( |$)/.test(line)) {
      return true;
    }
  }
  return false;
}

const WORKFLOWS = ".github/workflows/";
// git ls-tree -r -z records under .github/workflows/ as "<mode> <oid> <path>".
const workflowEntries = (git, tree) =>
  git(["ls-tree", "-r", "-z", tree, "--", WORKFLOWS])
    .toString("utf8")
    .split("\0")
    .filter(Boolean)
    .map((record) => {
      const tab = record.indexOf("\t");
      const [mode, , oid] = record.slice(0, tab).split(" ");
      return `${mode} ${oid} ${record.slice(tab + 1)}`;
    });

// post.sh's workflows_are_base_own: a merge tree whose workflows differ from
// the head's is admitted only when the PR's own diff against every merge base
// touches no workflow, the workflows are exactly the base's, and no head
// workflow is dropped.
function workflowsAreBaseOwn(git, headSha, baseSha, tree) {
  const head = workflowEntries(git, headSha);
  const merged = workflowEntries(git, tree);
  if (JSON.stringify(head) === JSON.stringify(merged)) {
    return true;
  }
  let bases = [];
  try {
    bases = git(["merge-base", "--all", headSha, baseSha]).toString("utf8").split("\n").filter(Boolean);
  } catch {
    return false;
  }
  if (bases.length === 0) {
    return false;
  }
  for (const mergeBase of bases) {
    try {
      git(["diff", "--quiet", "--no-ext-diff", mergeBase, headSha, "--", WORKFLOWS]);
    } catch {
      return false;
    }
  }
  const base = workflowEntries(git, baseSha);
  const basePaths = new Set(base.map((record) => record.split(" ").slice(2).join(" ")));
  return JSON.stringify(base) === JSON.stringify(merged) && head.every((record) => basePaths.has(record.split(" ").slice(2).join(" ")));
}

// A merge row's push. `merge` is { baseSha, conflictTree, state, unmerged
// (a Set of the paths the merge left conflicted), treeEntries: { script,
// sha256 } }.
async function pushMerge({ api, cwd, gitBin, row, context, number, target, headSha, patchHeadSha, headRef, message, patchFile, patchSha256, holdLabels, repository, escalate, log }) {
  const merge = context.merge;
  if (
    !merge ||
    !SHA.test(String(merge.baseSha)) ||
    !SHA.test(String(merge.conflictTree)) ||
    !["clean", "conflicted"].includes(merge.state) ||
    !(merge.unmerged instanceof Set) ||
    !merge.treeEntries?.script ||
    !/^[0-9a-f]{64}$/.test(String(merge.treeEntries?.sha256))
  ) {
    throw new Error("a merge row needs the pinned base, the conflict tree, the merge state, the conflicted paths and tree-entries.sh");
  }
  const reason = (name, why) => {
    if (!row.escalations.includes(name)) {
      throw new Error(`the ${row.name} row cannot escalate ${name}`);
    }
    log(why);
    return { outcome: "escalate", escalationReason: name };
  };
  if (patchHeadSha !== headSha) {
    log("the head moved since the select job; the merge is superseded");
    return { outcome: "superseded" };
  }
  if ((merge.state === "clean") !== (merge.unmerged.size === 0)) {
    throw new Error(`a ${merge.state} merge with ${merge.unmerged.size} conflicted path(s)`);
  }
  const scratchDir = mkdtempSync(join(tmpdir(), "apply-patch-merge-"));
  try {
    const git = gitRunner(cwd, gitBin, { GIT_ATTR_SOURCE: merge.baseSha, GIT_INDEX_FILE: join(scratchDir, "index"), GIT_LITERAL_PATHSPECS: "1" });
    const version = /git version (\d+)\.(\d+)/.exec(git(["version"]).toString("utf8"));
    if (!version || Number(version[1]) < 2 || (Number(version[1]) === 2 && Number(version[2]) < 41)) {
      throw new Error("a merge row needs git 2.41 or later, which reads attributes from a tree");
    }
    if (!hasCommit(git, headSha) || !hasCommit(git, merge.baseSha) || git(["cat-file", "-t", merge.conflictTree]).toString("utf8").trim() !== "tree") {
      throw new Error("the head, the base or the conflict tree is not in the checkout");
    }
    // P: the patch on T0, or T0 itself for a clean merge.
    let tree = merge.conflictTree;
    let entries = [];
    if (merge.state === "conflicted") {
      const problem = patchProblem(patchFile, patchSha256);
      if (problem) {
        return escalate("invalid", problem);
      }
      tree = applyOnto(git, merge.conflictTree, patchFile, false);
      if (!tree) {
        return escalate("not-applied", "the patch does not apply to the conflict tree");
      }
      entries = changes(git(["diff-tree", "-r", "-z", "--no-renames", merge.conflictTree, tree]));
      if (entries.length === 0) {
        return escalate("empty", "the patch changes nothing in the conflict tree");
      }
    } else if (patchFile) {
      return escalate("invalid", "a clean merge takes no patch");
    }
    // Only the patch's own changes face the rules; one refused entry refuses it whole.
    const renames = changes(git(["diff-tree", "-r", "-z", "-M", "--diff-filter=R", merge.conflictTree, tree]));
    const refuse = [...row.refuse, ...ALWAYS];
    for (const [entry, names] of [...renames.map((item) => [item, ["rename-into-refused"]]), ...entries.map((item) => [item, refuse])]) {
      const [refusal] = refusalsOf(entry, names);
      if (refusal) {
        return escalate(REFUSALS[refusal].kind, `refused (${refusal}): ${entry.path}`);
      }
    }
    if (row["max-files"] !== null && entries.length > row["max-files"]) {
      return escalate("invalid", `the patch changes ${entries.length} paths; the row allows ${row["max-files"]}`);
    }
    const allow = row.allow.map((name) => PREDICATES[name](context));
    const outside = entries.find((entry) => !allow.every((admits) => admits(entry.path)));
    if (outside) {
      return reason("unexpected-path-staged", `not a conflicted path: ${outside.path}`);
    }
    const written = entries.filter((entry) => !ZERO.test(entry.newSha));
    const sizes = written.map((entry) => Number(git(["cat-file", "-s", entry.newSha]).toString("utf8").trim()));
    const big = sizes.findIndex((size) => !(size <= MAX_BLOB_BYTES));
    if (big !== -1) {
      return escalate("invalid", `the patched ${written[big].path} is over ${MAX_BLOB_BYTES} bytes`);
    }
    if (sizes.reduce((sum, size) => sum + size, 0) > MAX_TOTAL_BLOB_BYTES) {
      return escalate("invalid", `the patched blobs total over ${MAX_TOTAL_BLOB_BYTES} bytes`);
    }
    const leaked = written.find((entry) => credentialIn(git(["cat-file", "blob", entry.newSha]).toString("latin1")));
    if (leaked) {
      return escalate("invalid", `the patched ${leaked.path} carries a credential shape`);
    }
    // Every conflicted path still in the tree is resolved.
    const listed = merge.unmerged.size === 0 ? [] : git(["ls-tree", "-z", "--full-tree", "-r", tree, "--", ...merge.unmerged]).toString("utf8").split("\0").filter(Boolean);
    for (const record of listed) {
      const tab = record.indexOf("\t");
      const [mode, , oid] = record.slice(0, tab).split(" ");
      if (mode !== GITLINK && hasConflictMarkers(git(["cat-file", "blob", oid]).toString("latin1"))) {
        return reason("unresolved-conflict", `a conflicted path still holds conflict markers: ${record.slice(tab + 1)}`);
      }
    }
    if (!workflowsAreBaseOwn(git, headSha, merge.baseSha, tree)) {
      return reason("workflow-staged", "the merge changes .github/workflows/ by more than the base's own workflows");
    }
    // The tree as entries against the head, from the base's tree-entries.sh:
    // only a blob neither parent holds is uploaded, at most max-blobs.
    const script = readFileSync(merge.treeEntries.script);
    if (sha256Of(script) !== merge.treeEntries.sha256) {
      throw new Error("tree-entries.sh does not match the SHA-256 recorded when it was copied from the base");
    }
    const listing = execFileSync("/usr/bin/bash", [merge.treeEntries.script, headSha, merge.baseSha, tree], {
      cwd,
      env: { PATH: "/usr/bin:/bin", HOME: process.env.HOME ?? "/tmp", GIT_NO_REPLACE_OBJECTS: "1" },
      encoding: "utf8",
      maxBuffer: 1 << 28,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const treeEntries = [];
    const uploads = [];
    for (const line of listing.split("\n").filter(Boolean)) {
      const tab = line.indexOf("\t");
      const [mode, sha, flag] = line.slice(0, tab).split(" ");
      const path = line.slice(tab + 1);
      const type = mode === GITLINK ? "commit" : "blob";
      treeEntries.push({ path, mode, type, sha: sha === "null" ? null : sha });
      if (flag === "create-blob") {
        uploads.push({ path, sha });
      }
    }
    if (uploads.length > row["max-blobs"]) {
      return escalate("invalid", `the merge needs ${uploads.length} new blobs; the row allows ${row["max-blobs"]}`);
    }
    if (await target.held(api, number, { holds: new Set(holdLabels), required: [], repository })) {
      log(`the ${row.target} is held; the merge is dropped`);
      return { outcome: "held" };
    }
    await target.ready(api, headRef, headSha);
    for (const { path, sha } of uploads) {
      const stored = await api.createBlob(git(["cat-file", "blob", sha]).toString("base64"));
      if (stored !== sha) {
        throw new Error(`GitHub stored the blob for ${JSON.stringify(path)} as ${stored}, not ${sha}`);
      }
    }
    const headTree = git(["rev-parse", `${headSha}^{tree}`]).toString("utf8").trim();
    const built = treeEntries.length > 0 ? await api.createTree(headTree, treeEntries) : headTree;
    if (built !== tree) {
      throw new Error(`GitHub built tree ${built}, not the merge tree ${tree}; nothing is committed`);
    }
    const commit = await api.createCommit(message, tree, [headSha, merge.baseSha]);
    await target.write(api, headRef, commit);
    const after = await api.readBranch(headRef);
    if (after !== commit) {
      throw new Error(`${headRef} reads ${after} after the write of ${commit}`);
    }
    log(`pushed merge ${commit} (${entries.length} patched path(s), ${uploads.length} new blob(s)) onto ${headRef}`);
    return { outcome: "pushed", commit, branch: headRef };
  } finally {
    rmSync(scratchDir, { recursive: true, force: true });
  }
}

export async function push({
  api,
  cwd,
  gitBin = "/usr/bin/git",
  row,
  context = {},
  pr,
  issue,
  headSha,
  patchHeadSha,
  headRef,
  baseRef = "",
  lane,
  activity,
  patchFile,
  patchSha256,
  holdLabels,
  requiredLabels = [],
  repository = "",
  refusalBase = "",
  log = () => {},
}) {
  // Everything the row names resolves before any git or API work.
  checkRow(row);
  const target = TARGETS[row.target];
  // A merge row builds its predicates once the conflict tree is checked.
  const allow = isMerge(row) ? [] : row.allow.map((name) => PREDICATES[name](context));
  if (!NAME.test(String(lane)) || !NAME.test(String(activity))) {
    throw new Error("LANE and PATCH_ACTIVITY must be lane and activity names");
  }
  const number = { pr, issue }[target.number];
  if (!Number.isSafeInteger(number) || number < 1) {
    throw new Error(`the ${row.target} target needs its ${target.number} number`);
  }
  const badRef = target.checkRef(headRef, { lane, issue: number });
  if (badRef) {
    throw new Error(badRef);
  }
  const message = commitMessage(row, { ref: headRef, base: baseRef, lane, activity, [target.number]: String(number) });
  const escalate = (kind, why) => {
    log(why);
    return { outcome: "escalate", escalationReason: pushReason(row, kind) };
  };
  const unmet = row.requires.find((requirement) => !REQUIREMENTS[requirement](context));
  if (unmet) {
    return escalate("invalid", `the producer's output does not say ${unmet}`);
  }
  if (isMerge(row)) {
    return pushMerge({ api, cwd, gitBin, row, context, number, target, headSha, patchHeadSha, headRef, message, patchFile, patchSha256, holdLabels, repository, escalate, log });
  }
  const problem = patchProblem(patchFile, patchSha256);
  if (problem) {
    return escalate("invalid", problem);
  }
  const git = gitRunner(cwd, gitBin);
  const moved = patchHeadSha !== headSha;
  if (moved && row["skip-moved-head"] === true) {
    log("the head moved since the model's run; the row takes no moved head");
    return { outcome: "superseded" };
  }
  if (moved && !target.movedHead) {
    return escalate("invalid", `the patch was made on ${patchHeadSha}, not the start commit ${headSha}`);
  }
  if (moved) {
    // The moved commits may touch no path the patch changes.
    if (!SHA.test(String(patchHeadSha)) || !hasCommit(git, patchHeadSha)) {
      return { outcome: "superseded" };
    }
    const atProducer = applyOnto(git, patchHeadSha, patchFile, false);
    if (!atProducer) {
      return escalate("not-applied", "the patch does not apply to the head it was made on");
    }
    const patched = new Set(changes(git(["diff-tree", "-r", "-z", "--no-renames", patchHeadSha, atProducer])).map((entry) => entry.path));
    const touched = git(["diff-tree", "-r", "-z", "--no-renames", "--name-only", patchHeadSha, headSha]).toString("utf8").split("\0");
    if (touched.some((path) => patched.has(path))) {
      log("commits since the model's head touch a patched path; the patch is superseded");
      return { outcome: "superseded" };
    }
  }
  let tree = applyOnto(git, headSha, patchFile, moved);
  if (!tree) {
    return escalate("not-applied", "the patch does not apply to the gated head");
  }
  const entries = changes(git(["diff-tree", "-r", "-z", "--no-renames", headSha, tree]));
  if (entries.length === 0) {
    return escalate("empty", "the patch changes nothing");
  }
  // A start commit that is not on the default branch (a resumed lane
  // branch's tip) brings its own commits to the new branch, so the refusals
  // also cover what the final tree changes since the default-branch commit it
  // forked from, the diff the pull request shows.
  let from = headSha;
  if (refusalBase && refusalBase !== headSha) {
    if (!SHA.test(String(refusalBase)) || !hasCommit(git, refusalBase)) {
      return escalate("invalid", `the default-branch commit ${refusalBase} is not in the checkout`);
    }
    from = git(["merge-base", refusalBase, headSha]).toString("utf8").trim();
  }
  const reaching = from === headSha ? entries : changes(git(["diff-tree", "-r", "-z", "--no-renames", from, tree]));
  const renames = changes(git(["diff-tree", "-r", "-z", "-M", "--diff-filter=R", from, tree]));
  // One refused entry refuses the whole patch, before anything is written.
  // A rename is checked as one first; every entry then meets the rest.
  const refuse = [...row.refuse, ...ALWAYS];
  const checks = [
    ...renames.map((entry) => [entry, ["rename-into-refused"]]),
    ...entries.map((entry) => [entry, refuse]),
    ...(reaching === entries ? [] : reaching.map((entry) => [entry, refuse])),
  ];
  for (const [entry, names] of checks) {
    const [refusal] = refusalsOf(entry, names);
    if (refusal) {
      return escalate(REFUSALS[refusal].kind, `refused (${refusal}): ${entry.path}`);
    }
  }
  if (row["max-files"] !== null && entries.length > row["max-files"]) {
    return escalate("invalid", `the patch changes ${entries.length} paths; the row allows ${row["max-files"]}`);
  }
  const outside = entries.find((entry) => !allow.every((admits) => admits(entry.path)));
  if (outside) {
    return escalate("protected-path", `not allowed by ${row.allow.join(", ")}: ${outside.path}`);
  }
  const written = entries.filter((entry) => !ZERO.test(entry.newSha));
  const sizes = written.map((entry) => Number(git(["cat-file", "-s", entry.newSha]).toString("utf8").trim()));
  const big = sizes.findIndex((size) => !(size <= MAX_BLOB_BYTES));
  if (big !== -1) {
    return escalate("invalid", `the patched ${written[big].path} is over ${MAX_BLOB_BYTES} bytes`);
  }
  if (sizes.reduce((sum, size) => sum + size, 0) > MAX_TOTAL_BLOB_BYTES) {
    return escalate("invalid", `the patched blobs total over ${MAX_TOTAL_BLOB_BYTES} bytes`);
  }
  const blobs = written.map((entry) => ({ entry, bytes: git(["cat-file", "blob", entry.newSha]) }));
  const leaked = blobs.find(({ bytes }) => credentialIn(bytes.toString("latin1")));
  if (leaked) {
    return escalate("invalid", `the patched ${leaked.entry.path} carries a credential shape`);
  }
  // Before any tree or commit is built: each file's change must also meet the
  // row's content rule.
  const contentRefusal = row["content-rule"] === undefined ? null : await CONTENT_RULES[row["content-rule"]]({ entries, git, context });
  if (contentRefusal) {
    return escalate("protected-path", `refused by the ${row["content-rule"]} rule (${String(contentRefusal).slice(0, 200)})`);
  }
  // The model's tools set no file mode, so under script-exec-bit each new or
  // changed script, a .sh file or one starting with #!, is made executable
  // here, in the index the patch was applied to.
  if (row["script-exec-bit"] === true) {
    const scripts = blobs.filter(({ entry }) => entry.newMode !== EXECUTABLE && isScript(git, entry));
    if (scripts.length > 0) {
      git(["update-index", ...scripts.flatMap(({ entry }) => ["--cacheinfo", EXECUTABLE, entry.newSha, entry.path])]);
      tree = git(["write-tree"]).toString("utf8").trim();
      for (const { entry } of scripts) {
        entry.newMode = EXECUTABLE;
      }
    }
  }
  // A hold set while the model worked stops the commit.
  if (await target.held(api, number, { holds: new Set(holdLabels), required: requiredLabels, repository })) {
    log(`the ${row.target} is held; the patch is dropped`);
    return { outcome: "held" };
  }
  await target.ready(api, headRef, headSha);
  const treeEntries = entries.filter((entry) => ZERO.test(entry.newSha)).map((entry) => ({ path: entry.path, mode: entry.oldMode, type: "blob", sha: null }));
  for (const { entry, bytes } of blobs) {
    const sha = await api.createBlob(bytes.toString("base64"));
    if (sha !== entry.newSha) {
      throw new Error(`GitHub stored a blob as ${sha}, not ${entry.newSha}`);
    }
    treeEntries.push({ path: entry.path, mode: entry.newMode, type: "blob", sha });
  }
  const headTree = git(["rev-parse", `${headSha}^{tree}`]).toString("utf8").trim();
  const built = await api.createTree(headTree, treeEntries);
  if (built !== tree) {
    throw new Error(`GitHub built tree ${built}, not the applied tree ${tree}; nothing is committed`);
  }
  const commit = await api.createCommit(message, tree, [headSha]);
  await target.write(api, headRef, commit);
  const after = await api.readBranch(headRef);
  if (after !== commit) {
    throw new Error(`${headRef} reads ${after} after the write of ${commit}`);
  }
  log(`pushed ${commit} (${entries.length} path(s)) onto ${headRef}`);
  return { outcome: "pushed", commit, branch: headRef };
}

// The REST calls apply-patch makes. GitHub signs a commit made with no author
// or committer as the App.
export function createGitHubApi({ token, repository, apiUrl, fetch = globalThis.fetch }) {
  const repo = `${apiUrl}/repos/${repository}`;
  const headers = { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" };
  async function request(path, method = "GET", body) {
    const response = await fetch(`${repo}/${path}`, {
      method,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw new Error(`${method} ${path} returned ${response.status}`);
    }
    return { data: await response.json(), link: response.headers.get("link") ?? "" };
  }
  const refPath = (ref) => ref.split("/").map(encodeURIComponent).join("/");
  return {
    getPull: async (pr) => (await request(`pulls/${pr}`)).data,
    async listLabels(pr) {
      const { data, link } = await request(`issues/${pr}/labels?per_page=100`);
      if (/rel="next"/.test(link)) {
        throw new Error("the pull request has more labels than one page holds");
      }
      return data;
    },
    // From git/ref, which GET /pulls can lag behind after a push.
    readBranch: async (ref) => (await request(`git/ref/heads/${refPath(ref)}`)).data.object.sha,
    createBlob: async (content) => (await request("git/blobs", "POST", { content, encoding: "base64" })).data.sha,
    createTree: async (baseTree, tree) => (await request("git/trees", "POST", { base_tree: baseTree, tree })).data.sha,
    createCommit: async (message, tree, parents) => (await request("git/commits", "POST", { message, tree, parents })).data.sha,
    async updateRef(ref, sha, force) {
      await request(`git/refs/${refPath(ref)}`, "PATCH", { sha, force });
    },
    // GitHub answers 422 when the ref already exists.
    async createRef(ref, sha) {
      await request("git/refs", "POST", { ref, sha });
    },
  };
}

function need(env, keys) {
  const missing = keys.filter((key) => !env[key]);
  if (missing.length > 0) {
    throw new Error(`${missing.join(", ")} not set`);
  }
}

// The kept threads of a threads.json: each a path and, when a fix request
// named files, its named_paths.
export function keptThreadsFrom(file) {
  if (!file) {
    return undefined;
  }
  const threads = JSON.parse(readFileSync(file, "utf8"))?.threads;
  const plain = (value) => typeof value === "string" && value !== "";
  if (
    !Array.isArray(threads) ||
    !threads.every(
      (thread) =>
        plain(thread?.path) && (thread.named_paths === undefined || (Array.isArray(thread.named_paths) && thread.named_paths.every(plain))),
    )
  ) {
    throw new Error("KEPT_THREADS_FILE is not a thread file of paths and named_paths");
  }
  return { paths: new Set(threads.map((thread) => thread.path)), threads: threads.map(({ path, named_paths }) => ({ path, named_paths })) };
}

// The base dependabot.yml's [ecosystem, directory] pairs, or null when the
// file does not read; the dependency-manifests predicate then throws.
export function dependabotPairs(baseDir) {
  try {
    return parseConfig(readFileSync(join(baseDir, DEPENDABOT_PATH), "utf8"));
  } catch {
    return null;
  }
}

// A merge row's inputs: the step's own, and the paths the checkout's merge left
// conflicted, read from its index (`git ls-files -u`), which no model touched.
export function mergeFrom(env, { cwd = process.cwd(), gitBin = "/usr/bin/git" } = {}) {
  need(env, ["MERGE_BASE_SHA", "CONFLICT_TREE", "MERGE_STATE", "TREE_ENTRIES_SCRIPT", "TREE_ENTRIES_SHA256"]);
  const raw = gitRunner(cwd, gitBin)(["ls-files", "-u", "-z"]).toString("utf8");
  const unmerged = new Set(
    raw
      .split("\0")
      .filter(Boolean)
      .map((record) => record.slice(record.indexOf("\t") + 1)),
  );
  return {
    baseSha: env.MERGE_BASE_SHA,
    conflictTree: env.CONFLICT_TREE,
    state: env.MERGE_STATE,
    unmerged,
    treeEntries: { script: env.TREE_ENTRIES_SCRIPT, sha256: env.TREE_ENTRIES_SHA256 },
  };
}

function labelList(env, key) {
  const labels = JSON.parse(env[key]);
  if (!Array.isArray(labels) || !labels.every((label) => typeof label === "string")) {
    throw new Error(`${key} is not a list of labels`);
  }
  return labels;
}

// The producer's model rung from MODEL_RUNG: empty or 0 is the route's own
// profile, 1 the rung above it; anything else is refused.
function modelRung(value = "") {
  if (!["", "0", "1"].includes(value)) {
    throw new Error("MODEL_RUNG must be empty, 0 or 1");
  }
  return value === "1" ? 1 : 0;
}

export async function main(argv, env, { api, cwd = process.cwd(), gitBin, log = (line) => console.log(line) } = {}) {
  const row = rowFor(loadRules(env.BASE_DIR), { prepare: env.PATCH_PREPARE ?? "", target: env.PATCH_TARGET || "pr" });
  const target = TARGETS[row.target];
  if (argv[0] === "select") {
    need(env, ["GITHUB_OUTPUT", "HEAD_SHA"]);
    const result = select({
      row,
      patchState: env.PATCH_STATE ?? "",
      patchSha256: env.PATCH_SHA256 ?? "",
      patchHeadSha: env.PATCH_HEAD_SHA ?? "",
      headSha: env.HEAD_SHA,
      patchDir: env.PATCH_DIR ?? "",
      reportDir: env.REPORT_DIR ?? "",
      rung: modelRung(env.MODEL_RUNG),
      mergeState: env.MERGE_STATE ?? "",
    });
    appendFileSync(env.GITHUB_OUTPUT, `proceed=${result.proceed}\nskip-reason=${result.skipReason}\nescalation-reason=${result.escalationReason}\n`);
    log(`select (${row.name}): proceed=${result.proceed} skip=${result.skipReason || "none"} escalation=${result.escalationReason || "none"}`);
    return 0;
  }
  if (argv.length > 0) {
    throw new Error("usage: apply-patch.mjs [select]");
  }
  need(env, [
    "GH_TOKEN",
    "GITHUB_REPOSITORY",
    ...target.env,
    "HEAD_SHA",
    "PATCH_HEAD_SHA",
    "HEAD_REF",
    "LANE",
    "PATCH_ACTIVITY",
    "PATCH_FILE",
    "HOLD_LABELS",
    "SKIP_REASON_FILE",
    "ESCALATION_REASON_FILE",
  ]);
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const [numberKey] = target.env;
  if (!/^[1-9][0-9]{0,14}$/.test(env[numberKey])) {
    throw new Error(`${numberKey} is not a positive integer`);
  }
  const merge = isMerge(row) ? mergeFrom(env, { cwd, gitBin }) : undefined;
  const result = await push({
    api: api ?? createGitHubApi({ token: env.GH_TOKEN, repository: env.GITHUB_REPOSITORY, apiUrl: env.GITHUB_API_URL ?? "https://api.github.com" }),
    cwd,
    gitBin,
    row,
    context: {
      keptThreads: keptThreadsFrom(env.KEPT_THREADS_FILE),
      dependencyVerdict: env.DEPENDENCY_VERDICT ?? "",
      // Read from the trusted base copy, and only for a row that needs it.
      dependabotConfig: row.allow.includes("dependency-manifests") ? dependabotPairs(env.BASE_DIR) : undefined,
      merge,
    },
    [target.number]: Number(env[numberKey]),
    headSha: env.HEAD_SHA,
    patchHeadSha: env.PATCH_HEAD_SHA,
    headRef: env.HEAD_REF,
    baseRef: env.BASE_REF ?? "",
    lane: env.LANE,
    activity: env.PATCH_ACTIVITY,
    // A clean merge has no patch.
    patchFile: merge?.state === "clean" ? "" : env.PATCH_FILE,
    patchSha256: env.PATCH_SHA256 ?? "",
    holdLabels: ["do-not-merge", ...labelList(env, "HOLD_LABELS")],
    requiredLabels: env.REQUIRED_LABELS ? labelList(env, "REQUIRED_LABELS") : [],
    repository: env.GITHUB_REPOSITORY,
    refusalBase: env.PATCH_BASE_SHA ?? "",
    log,
  });
  if (result.outcome === "escalate") {
    writeFileSync(env.ESCALATION_REASON_FILE, `${result.escalationReason}\n`);
  }
  if (result.outcome === "pushed" && env.GITHUB_OUTPUT) {
    appendFileSync(env.GITHUB_OUTPUT, `commit=${result.commit}\nbranch=${result.branch}\n`);
  }
  if (result.outcome !== "pushed") {
    writeFileSync(env.SKIP_REASON_FILE, result.outcome === "superseded" ? "superseded-sha\n" : "awaiting-human\n");
  }
  log(`apply-patch (${row.name}): ${result.outcome}${result.escalationReason ? ` (${result.escalationReason})` : ""}`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::apply-patch failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
