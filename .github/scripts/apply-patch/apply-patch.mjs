#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, closeSync, existsSync, lstatSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, readSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

import { laneBranch, laneBranchPattern } from "../lib/lane-branch.mjs";
import { runAsScript } from "../lib/run-main.mjs";
import { BODY_HOLD, LANES_APP_LOGIN } from "../pr-merge/merge-holds.mjs";
import { CDN_MANIFEST, CDN_RECORD, CDN_SCRIPT, cdnPaths } from "./cdn-paths.mjs";
import { fixRefusal, installScriptPinRefusal, parseConfig } from "../pr-unblock/dependency-classify.mjs";
import { stopSkip } from "../pr-unblock/escalation-routes.mjs";
import { declarationRefusal } from "../pr-unblock/test-scope.mjs";
import { NOTE_ID, sharedCopyPairs, THREAD_ID, threadTrailerLines } from "../pr-unblock/thread-scope.mjs";
import { PREDICATES } from "./predicates.mjs";
import { PROTECTED_REFUSALS, segments } from "./protected-paths.mjs";
import { retryFetch } from "../lib/retry-fetch.mjs";

export { segments } from "./protected-paths.mjs";

export const MAX_PATCH_BYTES = 1024 * 1024;
export const MAX_BLOB_BYTES = 5 * 1024 * 1024;
export const MAX_TOTAL_BLOB_BYTES = 20 * 1024 * 1024;
export const MAX_TREE_ENTRIES_PER_REQUEST = 100;
export const RULES_PATH = ".github/actions/resolve-config/patch-rules.json";
export const DEPENDABOT_PATH = ".github/dependabot.yml";
const SHA = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const NAME = /^[a-z][a-z0-9-]*$/;
const SYMLINK = "120000";
const GITLINK = "160000";
const REGULAR = "100644";
const EXECUTABLE = "100755";
const ZERO = /^0+$/;

const lefthookConfigs = (...stems) => new Set(stems.flatMap((stem) => ["yml", "yaml", "toml", "json", "jsonc"].map((ext) => `${stem}.${ext}`)));
const LEFTHOOK_ROOT_CONFIGS = lefthookConfigs("lefthook", ".lefthook", "lefthook-local", ".lefthook-local");
const LEFTHOOK_DOT_CONFIGS = lefthookConfigs("lefthook", "lefthook-local");

const ROW_PATH_RULES = {
  skills: (s) => s.slice(0, -1).includes("skills"),
  "skill-md": (s) => s.at(-1) === "skill.md",
  gitattributes: (s) => s.at(-1) === ".gitattributes",
  husky: (s) => s[0] === ".husky",
  lefthook: (s) => s[0] === ".lefthook" || s[0] === ".lefthook-local" || (s.length === 1 && LEFTHOOK_ROOT_CONFIGS.has(s[0])) || (s.length === 2 && s[0] === ".config" && LEFTHOOK_DOT_CONFIGS.has(s[1])),
};
const rowPathRule = (name) => (entry) => ROW_PATH_RULES[name](segments(entry.path));

export const ALWAYS = ["backslash"];
export const REFUSALS = {
  backslash: PROTECTED_REFUSALS.backslash,
  "github-workflows": PROTECTED_REFUSALS["github-workflows"],
  codeowners: PROTECTED_REFUSALS.codeowners,
  gitmodules: PROTECTED_REFUSALS.gitmodules,
  settings: PROTECTED_REFUSALS.settings,
  "lane-grants": PROTECTED_REFUSALS["lane-grants"],
  symlink: { kind: "invalid", test: (entry) => entry.oldMode === SYMLINK || entry.newMode === SYMLINK },
  gitlink: { kind: "invalid", test: (entry) => entry.oldMode === GITLINK || entry.newMode === GITLINK },
  "rename-into-refused": PROTECTED_REFUSALS["rename-into-refused"],
  skills: { kind: "protected-path", optional: true, test: rowPathRule("skills") },
  "skill-md": { kind: "protected-path", optional: true, test: rowPathRule("skill-md") },
  gitattributes: { kind: "protected-path", optional: true, test: rowPathRule("gitattributes") },
  husky: { kind: "protected-path", optional: true, test: rowPathRule("husky") },
  lefthook: { kind: "protected-path", optional: true, test: rowPathRule("lefthook") },
  "claude-protected": PROTECTED_REFUSALS["claude-protected"],
  "new-exec-bit": { kind: "protected-path", optional: true, test: (entry) => entry.newMode === EXECUTABLE && entry.oldMode !== EXECUTABLE },
};

export const refusalsOf = (entry, names = Object.keys(REFUSALS).filter((name) => !REFUSALS[name].optional)) => names.filter((name) => REFUSALS[name].test(entry));

export const CREDENTIAL_SHAPES = Object.freeze([
  ["GitHub token", /\b(?:ghs_[A-Za-z0-9._-]{36,}|gh[pousr]_[0-9A-Za-z]{36,}|github_pat_[0-9A-Za-z_]{22,})/],
  ["Anthropic key", /sk-ant-[A-Za-z0-9_-]{20,}/],
]);
export const credentialIn = (text) => CREDENTIAL_SHAPES.find(([, pattern]) => pattern.test(text))?.[0] ?? "";

const SCAN_CHUNK_BYTES = MAX_PATCH_BYTES;
const SCAN_OVERLAP_BYTES = 4096;
function findInFile(file, find) {
  const fd = openSync(file, "r");
  try {
    const buffer = Buffer.alloc(SCAN_CHUNK_BYTES);
    for (let position = 0; ; position += SCAN_CHUNK_BYTES - SCAN_OVERLAP_BYTES) {
      const read = readSync(fd, buffer, 0, SCAN_CHUNK_BYTES, position);
      const found = find(buffer.subarray(0, read).toString("latin1"));
      if (found || read < SCAN_CHUNK_BYTES) return found;
    }
  } finally {
    closeSync(fd);
  }
}

const BINARY_HUNK = /^GIT binary patch$/m;
const unscannedKind = (file, kind) => (existsSync(file) && lstatSync(file).isFile() && findInFile(file, (text) => BINARY_HUNK.test(text)) ? "credential" : kind);

const REASONS = "not-reproducible|flaky|protected-path|weaken-required|unfixed";
const ESCALATED = new RegExp(`^(.+?): escalated (${REASONS})(?: |$)`);
const RUNG_UP_REASONS = new Set(["unfixed", "not-reproducible"]);

const escalations = (text) =>
  String(text).split("\n").flatMap((line) => {
    const match = ESCALATED.exec(line.replace(/\r$/, ""));
    return match ? [{ check: match[1], reason: match[2] }] : [];
  });
const escalatedReasons = (text) => escalations(text).map(({ reason }) => reason);

export function escalatedChecks(text) {
  return escalations(text).map(({ check }) => check);
}

export function rungUpEscalation(text) {
  const reasons = escalatedReasons(text);
  return reasons.length > 0 && reasons.every((reason) => RUNG_UP_REASONS.has(reason));
}

const HELD_ESCALATIONS = [
  ["protected-path", "ci-fix-protected-path"],
  ["weaken-required", "ci-fix-weaken-required"],
];

export function heldEscalation(text) {
  const reasons = escalatedReasons(text);
  return HELD_ESCALATIONS.find(([reason]) => reasons.includes(reason))?.[1] ?? "";
}

export const WEAKEN_RETRY = "ci-fix-weaken-retry";
const weakenStop = (held, weakenRetry) => (held === "ci-fix-weaken-required" && weakenRetry ? WEAKEN_RETRY : held);

const reportText = (reportDir) => {
  const file = reportDir ? join(reportDir, "reply.txt") : "";
  return Boolean(file) && existsSync(file) && lstatSync(file).isFile() ? readFileSync(file, "utf8") : "";
};

const REPORTS = {
  "ci-escalations": {
    escalated: (reportDir) => escalatedChecks(reportText(reportDir)).length > 0,
    rungUp: (reportDir) => rungUpEscalation(reportText(reportDir)),
    held: (reportDir) => heldEscalation(reportText(reportDir)),
  },
};

const REQUIREMENTS = {
  "dependency-verdict: fix": (context) => context.dependencyVerdict === "fix",
};

const STATUS = { M: "modified", A: "added", D: "removed", T: "changed" };

const blobText = (git, sha) => (ZERO.test(sha) ? null : git(["cat-file", "blob", sha]).toString("utf8"));

async function entryAt(api, treeSha, path) {
  const parts = path.split("/");
  let sha = treeSha;
  for (const [i, name] of parts.entries()) {
    const item = ((await api.getTree(sha))?.tree ?? []).find((row) => row?.path === name);
    if (i === parts.length - 1) {
      return item ?? null;
    }
    if (item?.type !== "tree") {
      return null;
    }
    sha = item.sha;
  }
  return null;
}

async function modeAt(api, treeSha, path) {
  const item = await entryAt(api, treeSha, path);
  return item?.type === "blob" ? item.mode : null;
}

export const CONTENT_RULES = {
  "pr-mode-revert": async ({ entries, api, pr, headSha }) => {
    const changed = entries.filter((entry) => [REGULAR, EXECUTABLE].includes(entry.oldMode) && [REGULAR, EXECUTABLE].includes(entry.newMode) && entry.oldMode !== entry.newMode);
    if (changed.length === 0) {
      return null;
    }
    const baseSha = (await api.getPull(pr))?.base?.sha;
    if (!SHA.test(String(baseSha ?? ""))) {
      return "the pull request's base commit is unknown";
    }
    const tree = (await api.compare(baseSha, headSha))?.merge_base_commit?.commit?.tree?.sha;
    if (!SHA.test(String(tree ?? ""))) {
      return "the merge base of the head and the base is unknown";
    }
    for (const entry of changed) {
      const mode = await modeAt(api, tree, entry.path);
      if (mode !== entry.newMode && !(mode === null && entry.newMode === REGULAR)) {
        return `${entry.path} changes mode ${entry.oldMode} to ${entry.newMode}, but the merge base holds it ${mode === null ? "not at all" : `at ${mode}`}`;
      }
    }
    return null;
  },
  "dependency-version-change": async ({ entries, git, context }) => {
    const byPath = new Map(entries.map((entry) => [entry.path, entry]));
    return fixRefusal(
      entries.map((entry) => ({ filename: entry.path, status: STATUS[entry.status?.[0]] ?? String(entry.status) })),
      context.dependabotConfig,
      {
        entry: async (path) => {
          const mode = byPath.get(path).newMode;
          return { type: mode === GITLINK ? "commit" : "blob", mode: Number.parseInt(mode, 8) };
        },
        text: async (side, path) => blobText(git, side === "before" ? byPath.get(path).oldSha : byPath.get(path).newSha),
      },
    );
  },
  "cdn-pins-sync": async ({ entries, git, context, headSha }) => {
    const wrong = entries.find(({ path, status, oldMode, newMode }) =>
      !context.cdnPins?.has(path) || status !== "M" || oldMode !== REGULAR || newMode !== REGULAR);
    if (wrong) return `${wrong.path} is not an in-place modification of a regular CDN pin file`;
    const root = mkdtempSync(join(tmpdir(), "cdn-pins-check-"));
    try {
      const base = JSON.parse(readFileSync(join(context.baseDir, CDN_RECORD), "utf8"));
      const patched = new Map(entries.map(({ path, newSha }) => [path, newSha]));
      for (const path of [CDN_MANIFEST, ...cdnPaths(base)]) {
        const dest = join(root, path);
        mkdirSync(dirname(dest), { recursive: true });
        writeFileSync(dest, git(["cat-file", "blob", patched.get(path) ?? `${headSha}:${path}`]));
      }
      const record = JSON.parse(readFileSync(join(root, CDN_RECORD), "utf8"));
      if (!isDeepStrictEqual(record.targets, base.targets)) return "the CDN pin targets changed";
      const { check } = await import(pathToFileURL(resolve(context.baseDir, CDN_SCRIPT)).href);
      const messages = check(root);
      return messages.length === 0 ? null : messages.join("\n");
    } catch {
      return "the CDN pins could not be checked with the base sync script";
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  },
  "install-script-pin": async ({ entries, git, context }) => {
    if (entries.length !== 1 || entries[0].path !== "package.json") {
      return `the patch changes ${entries.map((entry) => entry.path).join(", ") || "nothing"}, not package.json alone`;
    }
    const [entry] = entries;
    const scope = await CONTENT_RULES["dependency-version-change"]({ entries, git, context });
    return scope ?? installScriptPinRefusal(blobText(git, entry.oldSha), blobText(git, entry.newSha));
  },
  "test-scope-lines": async ({ entries, git }) => {
    for (const entry of entries) {
      if (entry.status?.[0] !== "M" || entry.oldMode !== entry.newMode || ![REGULAR, EXECUTABLE].includes(entry.newMode)) {
        return `${entry.path} is not a file modified in place`;
      }
      const why = declarationRefusal(entry.path, blobText(git, entry.oldSha), blobText(git, entry.newSha));
      if (why) {
        return `${entry.path}: ${why}`;
      }
    }
    return null;
  },
};

export const FROZEN_TIERS = Object.freeze({
  historical: Object.freeze(["docs/adr/**", "docs/upstream/**", ".claude/unhobble/**"]),
  released: Object.freeze(["**/CHANGELOG.md"]),
});
const FROZEN_WHY = {
  historical: "a historical record (docs/conventions/docs-naming.yaml tier historical) whose narrative stays as written",
  released: "a released changelog (docs/conventions/docs-naming.yaml tier released) the release tooling writes",
};
const tierGlob = (glob) => {
  const parts = segments(glob);
  if (parts.length === 2 && parts[0] === "**" && parts[1] !== "**") {
    return (path) => path.at(-1) === parts[1];
  }
  if (parts.at(-1) === "**" && !parts.slice(0, -1).includes("**")) {
    const prefix = parts.slice(0, -1);
    return (path) => path.length > prefix.length && prefix.every((part, i) => path[i] === part);
  }
  throw new Error(`FROZEN_TIERS holds a glob apply-patch cannot read: ${glob}`);
};
const FROZEN_MATCHERS = Object.entries(FROZEN_TIERS).map(([tier, globs]) => [tier, globs.map(tierGlob)]);
const frozenTier = (path) => FROZEN_MATCHERS.find(([, tests]) => tests.some((matches) => matches(segments(path))))?.[0];

const BEGIN_GENERATED = /^[ \t]*<!-- BEGIN GENERATED:(.*)-->[ \t]*$/;
const END_GENERATED = /^[ \t]*<!-- END GENERATED:.*-->[ \t]*$/;
const linesOf = (bytes) => (bytes.length === 0 ? [] : bytes.toString("latin1").split(/(?<=\n)/));
const markerText = (line) => line.replace(/\r?\n$/, "");

export function generatedRegions(bytes) {
  const regions = [];
  let open = null;
  for (const [index, line] of linesOf(bytes).entries()) {
    const begin = BEGIN_GENERATED.exec(markerText(line));
    if (begin) {
      if (open) {
        return { error: "its generated-region markers do not pair" };
      }
      open = { begin: index, generator: Buffer.from(begin[1], "latin1").toString("utf8").trim() };
    } else if (END_GENERATED.test(markerText(line))) {
      if (!open) {
        return { error: "its generated-region markers do not pair" };
      }
      regions.push({ ...open, end: index });
      open = null;
    }
  }
  return open ? { error: "its generated-region markers do not pair" } : { regions };
}

const commandText = (text, property = false) => {
  const escaped = String(text)
    .replace(/[\x00-\x09\x0b\x0c\x0e-\x1f\x7f]+/g, " ")
    .slice(0, 300)
    .replaceAll("%", "%25")
    .replaceAll("\r", "%0D")
    .replaceAll("\n", "%0A");
  return property ? escaped.replaceAll(":", "%3A").replaceAll(",", "%2C") : escaped;
};
const fileWarning = (path, why) => `::warning file=${commandText(path, true)}::${commandText(`apply-patch dropped the change to ${path}, ${why}`)}`;
const regionWarning = (path, line, generator) =>
  `::warning file=${commandText(path, true)},line=${line}::${commandText(`apply-patch dropped a change to the generated region of ${path} (${generator}); change the generator's inputs and regenerate`)}`;

function lineStarts(bytes) {
  const starts = [];
  for (let at = 0; at < bytes.length; at = bytes.indexOf(10, at) + 1 || bytes.length) {
    starts.push(at);
  }
  return starts;
}

function hunksOf(git, entry, oldCount, newCount) {
  if (ZERO.test(entry.oldSha) || ZERO.test(entry.newSha)) {
    return [{ oldStart: 0, oldCount, newStart: 0, newCount }];
  }
  const diff = git(["diff", "-U0", "--inter-hunk-context=0", "-a", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames", entry.oldSha, entry.newSha]).toString("latin1");
  const at = (start, count) => (count === 0 ? start : start - 1);
  return diff.split("\n").flatMap((line) => {
    const header = line.startsWith("@@ -") ? /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(line) : null;
    if (!header) {
      return [];
    }
    const [, a, b = "1", c, d = "1"] = header;
    return [{ oldStart: at(Number(a), Number(b)), oldCount: Number(b), newStart: at(Number(c), Number(d)), newCount: Number(d) }];
  });
}

const regionBytes = (lines, regions) => JSON.stringify(regions.map((region) => lines.slice(region.begin, region.end + 1).join("")));

export function protectedRegions(git, entry, hunks = hunksOf) {
  const restore = (why) => ({ sha: entry.oldSha, mode: entry.oldMode, warnings: [fileWarning(entry.path, why)] });
  const tier = frozenTier(entry.path);
  if (tier) {
    return restore(FROZEN_WHY[tier]);
  }
  const blob = (sha) => (ZERO.test(sha) ? Buffer.alloc(0) : git(["cat-file", "blob", sha]));
  const [before, after] = [blob(entry.oldSha), blob(entry.newSha)];
  const [head, patched] = [generatedRegions(before), generatedRegions(after)];
  if (head.error || patched.error) {
    return restore("whose generated-region markers do not pair");
  }
  if (head.regions.length === 0 && patched.regions.length === 0) {
    return { sha: entry.newSha, mode: entry.newMode, warnings: [] };
  }
  if (ZERO.test(entry.newSha)) {
    return restore(`which it deletes though it holds a generated region (${head.regions[0].generator})`);
  }
  const headRegions = regionBytes(linesOf(before), head.regions);
  const keepPatched = () =>
    regionBytes(linesOf(after), patched.regions) === headRegions ? { sha: entry.newSha, mode: entry.newMode, warnings: [] } : restore("whose generated regions the patch would change");
  const [oldStarts, newStarts] = [lineStarts(before), lineStarts(after)];
  const slice = (bytes, starts, from, count) => bytes.subarray(starts[from] ?? bytes.length, starts[from + count] ?? bytes.length);
  const isMarker = (line) => BEGIN_GENERATED.test(markerText(line)) || END_GENERATED.test(markerText(line));
  const warnings = [];
  const parts = [];
  let cursor = 0;
  for (const hunk of hunks(git, entry, oldStarts.length, newStarts.length)) {
    const last = hunk.oldStart + hunk.oldCount - 1;
    let region = hunk.oldCount > 0 ? head.regions.find((r) => r.begin <= last && hunk.oldStart <= r.end) : head.regions.find((r) => r.begin < hunk.oldStart && hunk.oldStart <= r.end);
    if (!region) {
      for (let j = hunk.newStart; j < hunk.newStart + hunk.newCount && !region; j += 1) {
        const line = slice(after, newStarts, j, 1).toString("latin1");
        if (isMarker(line)) {
          region = patched.regions.find((r) => r.begin === j || r.end === j) ?? { generator: "a generated-region marker" };
        }
      }
    }
    parts.push(slice(before, oldStarts, cursor, hunk.oldStart - cursor));
    if (region) {
      warnings.push(regionWarning(entry.path, Math.max(1, hunk.oldCount > 0 ? hunk.oldStart + 1 : hunk.oldStart), region.generator));
      parts.push(slice(before, oldStarts, hunk.oldStart, hunk.oldCount));
    } else {
      parts.push(slice(after, newStarts, hunk.newStart, hunk.newCount));
    }
    cursor = hunk.oldStart + hunk.oldCount;
  }
  if (warnings.length === 0) {
    return keepPatched();
  }
  parts.push(slice(before, oldStarts, cursor, oldStarts.length - cursor));
  const rebuilt = Buffer.concat(parts);
  const check = generatedRegions(rebuilt);
  if (check.error || regionBytes(linesOf(rebuilt), check.regions) !== headRegions) {
    return restore("whose generated regions its kept hunks would change");
  }
  if (rebuilt.equals(before)) {
    return { sha: entry.oldSha, mode: ZERO.test(entry.oldSha) ? entry.oldMode : entry.newMode, warnings };
  }
  return { sha: git(["hash-object", "-w", "--no-filters", "--stdin"], { input: rebuilt, stdio: ["pipe", "pipe", "pipe"] }).toString("utf8").trim(), mode: entry.newMode, warnings };
}

export const CONTENT_DROPS = {
  "protected-content": ({ entries, git }) => {
    const updates = [];
    const warnings = [];
    for (const entry of entries) {
      const outcome = protectedRegions(git, entry);
      for (const warning of outcome.warnings) {
        warnings.push(warning);
      }
      if (outcome.sha !== entry.newSha || outcome.mode !== entry.newMode) {
        if (!ZERO.test(outcome.sha) && ![REGULAR, EXECUTABLE].includes(outcome.mode)) {
          throw new Error(`protected-content would set ${entry.path} to blob ${outcome.sha} at mode ${outcome.mode}`);
        }
        updates.push(ZERO.test(outcome.sha) ? `0 ${"0".repeat(40)}\t${entry.path}` : `${outcome.mode} ${outcome.sha}\t${entry.path}`);
      }
    }
    return { updates, warnings };
  },
};

export function loadRules(baseDir) {
  if (!baseDir) {
    throw new Error("BASE_DIR, the trusted base checkout, is not set");
  }
  return JSON.parse(readFileSync(join(baseDir, RULES_PATH), "utf8"));
}

const movedFrom = (head, tip) => `the PR branch moved from ${head} to ${tip}; the patch is superseded`;

export const TARGETS = {
  pr: {
    row: (prepare) => prepare || "default",
    number: "pr",
    env: ["PR_NUMBER"],
    movedHead: true,
    checkRef: () => "",
    async held(api, number, { holds, repository }) {
      const [pull, labels] = [await api.getPull(number), await api.listLabels(number)];
      if (pull.head?.repo?.full_name !== repository) {
        throw new Error(`the PR head is ${pull.head?.repo?.full_name ?? "unreadable"}, not ${repository}; the patch is not pushed`);
      }
      const lanesApp = pull.user?.type === "Bot" && pull.user?.login === LANES_APP_LOGIN;
      return pull.draft !== false || labels.some((label) => holds.has(label.name)) || (!lanesApp && BODY_HOLD.test(String(pull.body ?? "")));
    },
    async ready(api, ref, head) {
      const tip = await api.readBranch(ref);
      if (!SHA.test(String(tip))) {
        throw new Error(`${ref} reads no commit`);
      }
      return tip === head ? "" : movedFrom(head, tip);
    },
    write: (api, ref, commit) => api.updateRef(`heads/${ref}`, commit, false),
  },
  issue: {
    row: () => "issue",
    number: "issue",
    env: ["ISSUE_NUMBER", "REQUIRED_LABELS", "PATCH_BASE_SHA"],
    movedHead: false,
    checkRef: (ref, { lane, issue }) => (laneBranchPattern(lane, issue).test(String(ref)) ? "" : `${ref} is not a ${laneBranch(lane, issue, "<run id>", "<attempt>")} branch`),
    async held(api, number, { holds, required }) {
      const names = new Set((await api.listLabels(number)).map((label) => label.name));
      return [...names].some((name) => holds.has(name)) || required.some((name) => !names.has(name));
    },
    ready: async () => {},
    write: (api, ref, commit) => api.createRef(`refs/heads/${ref}`, commit),
  },
};

async function landed(target, api, ref, commit, head, log) {
  try {
    await target.write(api, ref, commit);
  } catch (error) {
    if (!target.movedHead || error.status !== 422) {
      throw error;
    }
    const tip = await api.readBranch(ref).catch(() => head);
    if (!SHA.test(String(tip)) || tip === head || tip === commit) {
      throw error;
    }
    log(`${movedFrom(head, tip)} (${error.message})`);
    return false;
  }
  const after = await api.readBranch(ref);
  if (after !== commit) {
    throw new Error(`${ref} reads ${after} after the write of ${commit}`);
  }
  return true;
}

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

export function checkRow(row) {
  const unknown = (names, known) => names.filter((name) => !Object.hasOwn(known, name));
  const fail = (message) => {
    throw new Error(`patch-rules.json row \`${row.name}\` ${message}`);
  };
  const missing = Object.keys(REFUSALS).filter((name) => !ALWAYS.includes(name) && !REFUSALS[name].optional && !row.refuse?.includes(name));
  if (missing.length > 0) {
    fail(`does not refuse ${missing.join(", ")}`);
  }
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
  if (row["content-rule"] !== undefined && !Object.hasOwn(CONTENT_RULES, String(row["content-rule"])) && !Object.hasOwn(CONTENT_DROPS, String(row["content-rule"]))) {
    fail(`names an unknown content rule: ${row["content-rule"]}`);
  }
  if (isMerge(row) && Object.hasOwn(CONTENT_DROPS, String(row["content-rule"]))) {
    fail(`names the drop rule ${row["content-rule"]} on a merge row`);
  }
  if (row["reads-report"] !== null && !Object.hasOwn(REPORTS, row["reads-report"])) {
    fail(`reads an unknown report: ${row["reads-report"]}`);
  }
  if (row["max-files"] !== null && !(Number.isInteger(row["max-files"]) && row["max-files"] > 0)) {
    fail("has a max-files that is not a positive integer or null");
  }
  const parents = JSON.stringify(row.commit?.parents);
  if (parents === '["head","base"]') {
    const only = row["clean-patch"] === true ? '["shared-copies"]' : '["merge-result"]';
    if (JSON.stringify(row.allow) !== only || row.target !== "pr") {
      fail(`commits a merge but does not allow ${JSON.parse(only)[0]} alone on a pull request`);
    }
    if (!(Number.isInteger(row["max-blobs"]) && row["max-blobs"] > 0)) {
      fail("commits a merge with no max-blobs");
    }
  } else if (parents !== '["head"]') {
    fail("commits with parents this apply-patch does not support");
  } else if (row.allow?.includes("merge-result") || row["max-blobs"] !== undefined || row["clean-patch"] !== undefined) {
    fail("allows merge-result or sets max-blobs but does not commit a merge");
  }
  if (!row.escalations?.some((reason) => reason.endsWith("-invalid"))) {
    fail("has no -invalid escalation reason");
  }
  if (!Object.hasOwn(TARGETS, String(row.target))) {
    fail(`names an unknown target: ${row.target}`);
  }
  if (row["thread-trailer"] !== undefined && (row["thread-trailer"] !== true || !row.allow.includes("kept-threads"))) {
    fail("sets thread-trailer but does not allow kept-threads");
  }
  if (
    row["api-only"] !== undefined &&
    (row["api-only"] !== true ||
      row.target !== "pr" ||
      isMerge(row) ||
      row["skip-moved-head"] !== true ||
      row["script-exec-bit"] === true ||
      row["thread-trailer"] !== undefined ||
      row["reads-report"] !== null ||
      !Object.hasOwn(CONTENT_RULES, String(row["content-rule"])))
  ) {
    fail("sets api-only but is not a pull request row that skips a moved head and checks content with a refusing rule");
  }
  return row;
}

export const isMerge = (row) => row.commit?.parents?.length === 2;

export const reasonFor = (row, kind) =>
  row.escalations.find((reason) => reason.endsWith(`-${kind}`)) ?? row.escalations.find((reason) => reason.endsWith("-invalid"));

export const pushReason = (row, kind) => reasonFor(row, kind === "empty" ? (row["empty-at-push"] ?? "empty") : kind);

export function commitMessage(row, values, threads = []) {
  const fill = (text) =>
    text.replace(/\{(ref|base|lane|activity|issue)\}/g, (_, key) => {
      if (!values[key]) {
        throw new Error(`the commit message needs {${key}}, which this run does not give`);
      }
      return values[key];
    });
  return [fill(row.commit.message), "", fill(row.commit.trailer), ...threadTrailerLines(threads), ""].join("\n");
}

const sha256Of = (bytes) => createHash("sha256").update(bytes).digest("hex");

function readCapped(file, cap) {
  const fd = openSync(file, "r");
  try {
    const buffer = Buffer.alloc(cap);
    return buffer.subarray(0, readSync(fd, buffer, 0, cap, 0));
  } finally {
    closeSync(fd);
  }
}

export function leakedBlob(git, entries) {
  for (const entry of entries) {
    if (ZERO.test(entry.newSha) || entry.newMode === GITLINK) continue;
    try {
      if (credentialIn(git(["cat-file", "blob", entry.newSha]).toString("latin1"))) return entry;
    } catch (error) {
      if (error?.code === "ENOBUFS") return { ...entry, unread: true };
      throw error;
    }
  }
  return undefined;
}
const leakWhy = (leaked) => `the patched ${leaked.path} ${leaked.unread ? "is too large to scan, so it may carry" : "carries"} a credential shape`;

export function patchProblem(file, expected) {
  const invalid = (why) => ({ kind: "invalid", why });
  if (!existsSync(file)) {
    return invalid("the patch or its SHA-256 is missing");
  }
  if (!lstatSync(file).isFile()) {
    return invalid("the patch is not one regular file of at most 1 MiB");
  }
  const credential = findInFile(file, credentialIn);
  if (credential) {
    return { kind: "credential", why: `the patch carries a ${credential} shape` };
  }
  const refused = (why) => ({ kind: unscannedKind(file, "invalid"), why });
  const bytes = readCapped(file, MAX_PATCH_BYTES + 1);
  if (!SHA256.test(String(expected))) {
    return refused("the patch or its SHA-256 is missing");
  }
  if (bytes.length === 0 || bytes.length > MAX_PATCH_BYTES) {
    return refused("the patch is not one regular file of at most 1 MiB");
  }
  return sha256Of(bytes) === expected ? null : refused("the patch does not match its SHA-256");
}

export function select({ row, patchState, patchSha256, patchHeadSha, headSha, patchDir, reportDir, rung = 0, weakenRetry = false, mergeState = "" }) {
  checkRow(row);
  const decide = (proceed, skipReason, escalationReason) => ({
    proceed,
    skipReason: skipReason === "awaiting-human" && escalationReason ? stopSkip(escalationReason) : skipReason,
    escalationReason,
  });
  if (isMerge(row)) {
    if (mergeState !== "clean" && mergeState !== "conflicted") {
      return decide(false, "awaiting-human", reasonFor(row, "invalid"));
    }
    if (!SHA.test(String(patchHeadSha)) || !SHA.test(String(headSha)) || patchHeadSha !== headSha) {
      return decide(false, "superseded-sha", "");
    }
    if (row["clean-patch"] === true && (mergeState !== "clean" || (patchState !== "written" && patchState !== "empty"))) {
      return decide(false, "awaiting-human", reasonFor(row, "invalid"));
    }
    if (row["clean-patch"] === true && patchState === "empty") {
      return decide(true, "", "");
    }
    if (mergeState === "clean" && row["clean-patch"] !== true) {
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
    const held = escalated ? weakenStop(report.held(reportDir), weakenRetry) : "";
    return decide(false, "awaiting-human", held || reasonFor(row, escalated ? "escalated" : "empty"));
  }
  let names;
  try {
    names = readdirSync(patchDir);
  } catch {
    names = [];
  }
  const patch = join(patchDir, "patch.diff");
  const found = names.includes("patch.diff") ? patchProblem(patch, patchSha256) : null;
  const problem = found?.kind === "credential" ? found : names.length === 1 && names[0] === "patch.diff" ? found : { kind: unscannedKind(patch, "invalid") };
  if (problem) {
    return decide(false, "awaiting-human", reasonFor(row, problem.kind));
  }
  return decide(true, "", "");
}

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

const diffEntries = (git, from, to, flags = ["--no-renames"]) => changes(git(["diff-tree", "-r", "-z", ...flags, from, to]));

const fieldsAndPath = (record) => {
  const tab = record.indexOf("\t");
  return [record.slice(0, tab).split(" "), record.slice(tab + 1)];
};

function firstRefusal(checks) {
  for (const [entry, names] of checks) {
    const [refusal] = refusalsOf(entry, names);
    if (refusal) {
      return { kind: REFUSALS[refusal].kind, why: `refused (${refusal}): ${entry.path}` };
    }
  }
  return null;
}

function oversizeBlobs(git, written) {
  const sizes = written.map((entry) => Number(git(["cat-file", "-s", entry.newSha]).toString("utf8").trim()));
  const big = sizes.findIndex((size) => !(size <= MAX_BLOB_BYTES));
  if (big !== -1) {
    return `the patched ${written[big].path} is over ${MAX_BLOB_BYTES} bytes`;
  }
  return sizes.reduce((sum, size) => sum + size, 0) > MAX_TOTAL_BLOB_BYTES ? `the patched blobs total over ${MAX_TOTAL_BLOB_BYTES} bytes` : "";
}

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
const workflowEntries = (git, tree) =>
  git(["ls-tree", "-r", "-z", tree, "--", WORKFLOWS])
    .toString("utf8")
    .split("\0")
    .filter(Boolean)
    .map((record) => {
      const [[mode, , oid], path] = fieldsAndPath(record);
      return `${mode} ${oid} ${path}`;
    });

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
  return JSON.stringify(workflowEntries(git, baseSha)) === JSON.stringify(merged);
}

async function pushMerge({ api, cwd, gitBin, row, context, number, target, headSha, patchHeadSha, headRef, message, patchFile, patchSha256, holdLabels, repository, escalate, log }) {
  const merge = context.merge;
  if (
    !merge ||
    !SHA.test(String(merge.baseSha)) ||
    !SHA.test(String(merge.conflictTree)) ||
    !["clean", "conflicted"].includes(merge.state) ||
    !(merge.unmerged instanceof Set) ||
    !merge.treeEntries?.script ||
    !SHA256.test(String(merge.treeEntries?.sha256))
  ) {
    throw new Error("a merge row needs the pinned base, the conflict tree, the merge state, the conflicted paths and tree-entries.sh");
  }
  const reason = (name, why) => {
    const named = row.escalations.find((listed) => listed === name || listed.endsWith(`-${name}`));
    if (!named) {
      throw new Error(`the ${row.name} row cannot escalate ${name}`);
    }
    log(why);
    return { outcome: "escalate", escalationReason: named };
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
    let tree = merge.conflictTree;
    let entries = [];
    if (merge.state === "conflicted" || (row["clean-patch"] === true && (patchFile || patchSha256))) {
      const problem = patchProblem(patchFile, patchSha256);
      if (problem) {
        return escalate(problem.kind, problem.why);
      }
      tree = applyOnto(git, merge.conflictTree, patchFile, false);
      if (!tree) {
        return escalate("not-applied", "the patch does not apply to the conflict tree");
      }
      entries = diffEntries(git, merge.conflictTree, tree);
      if (entries.length === 0) {
        return escalate("empty", "the patch changes nothing in the conflict tree");
      }
      const leaked = leakedBlob(git, entries);
      if (leaked) {
        return escalate("credential", leakWhy(leaked));
      }
    } else if (patchFile) {
      return escalate("invalid", "a clean merge takes no patch");
    }
    const renames = diffEntries(git, merge.conflictTree, tree, ["-M", "--diff-filter=R"]);
    const refuse = [...row.refuse, ...ALWAYS];
    const refused = firstRefusal([...renames.map((item) => [item, ["rename-into-refused"]]), ...entries.map((item) => [item, refuse])]);
    if (refused) {
      return escalate(refused.kind, refused.why);
    }
    if (row["max-files"] !== null && entries.length > row["max-files"]) {
      return escalate("invalid", `the patch changes ${entries.length} paths; the row allows ${row["max-files"]}`);
    }
    const allow = row.allow.map((name) => PREDICATES[name](context));
    const outside = entries.find((entry) => !allow.every((admits) => admits(entry.path, entry)));
    if (outside) {
      return reason("unexpected-path-staged", `not a conflicted path: ${outside.path}`);
    }
    const oversize = oversizeBlobs(git, entries.filter((entry) => !ZERO.test(entry.newSha)));
    if (oversize) {
      return escalate("invalid", oversize);
    }
    const listed = merge.unmerged.size === 0 ? [] : git(["ls-tree", "-z", "--full-tree", "-r", tree, "--", ...merge.unmerged]).toString("utf8").split("\0").filter(Boolean);
    for (const record of listed) {
      const [[mode, , oid], path] = fieldsAndPath(record);
      if (mode !== GITLINK && hasConflictMarkers(git(["cat-file", "blob", oid]).toString("latin1"))) {
        return reason("unresolved-conflict", `a conflicted path still holds conflict markers: ${path}`);
      }
    }
    if (!workflowsAreBaseOwn(git, headSha, merge.baseSha, tree)) {
      return reason("workflow-staged", "the merge changes .github/workflows/ by more than the base's own workflows");
    }
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
      const [[mode, sha, flag], path] = fieldsAndPath(line);
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
    const movedEarly = await target.ready(api, headRef, headSha);
    if (movedEarly) {
      log(movedEarly);
      return { outcome: "superseded" };
    }
    for (const { path, sha } of uploads) {
      const stored = await api.createBlob(git(["cat-file", "blob", sha]).toString("base64"));
      if (stored !== sha) {
        throw new Error(`GitHub stored the blob for ${JSON.stringify(path)} as ${stored}, not ${sha}`);
      }
    }
    const headTree = git(["rev-parse", `${headSha}^{tree}`]).toString("utf8").trim();
    const built = await buildTree(api, headTree, treeEntries);
    if (built !== tree) {
      throw new Error(`GitHub built tree ${built}, not the merge tree ${tree}; nothing is committed`);
    }
    const commit = await api.createCommit(message, tree, [headSha, merge.baseSha]);
    if (!(await landed(target, api, headRef, commit, headSha, log))) {
      return { outcome: "superseded" };
    }
    log(`pushed merge ${commit} (${entries.length} patched path(s), ${uploads.length} new blob(s)) onto ${headRef}`);
    return { outcome: "pushed", commit, branch: headRef };
  } finally {
    rmSync(scratchDir, { recursive: true, force: true });
  }
}

const DEPENDABOT_LOGIN = "dependabot[bot]";

function numstatPaths(git, patchFile) {
  const fields = git(["apply", "--numstat", "-z", patchFile]).toString("utf8").split("\0");
  const paths = [];
  for (let i = 0; i < fields.length; i += 1) {
    const path = fields[i].split("\t")[2];
    if (path === "") {
      paths.push(fields[i + 1], fields[i + 2]);
      i += 2;
    } else if (path !== undefined) {
      paths.push(path);
    }
  }
  return [...new Set(paths)];
}

async function pushApiOnly({ api, gitBin, row, context, allow, number, target, headSha, patchHeadSha, headRef, message, patchFile, patchSha256, holdLabels, repository, escalate, log }) {
  const problem = patchProblem(patchFile, patchSha256);
  if (problem) {
    return escalate(problem.kind, problem.why);
  }
  if (patchHeadSha !== headSha) {
    log("the head moved since the producer's run; the row takes no moved head");
    return { outcome: "superseded" };
  }
  const head = await api.getCommit(headSha);
  const headTree = head?.tree?.sha;
  if (!SHA.test(String(headTree ?? ""))) {
    throw new Error(`the head commit ${headSha} names no tree`);
  }
  const trailer = message.split("\n")[2];
  if (String(head.message ?? "").split("\n").some((line) => line.trim() === trailer)) {
    log(`the head is this activity's own commit (${trailer}); nothing is pushed`);
    return { outcome: "not-applicable" };
  }
  const scratch = mkdtempSync(join(tmpdir(), "apply-patch-api-"));
  try {
    const git = gitRunner(scratch, gitBin, { GIT_DIR: join(scratch, "git"), GIT_INDEX_FILE: join(scratch, "index"), GIT_LITERAL_PATHSPECS: "1" });
    git(["init", "-q"]);
    git(["read-tree", "--empty"]);
    let paths;
    try {
      paths = numstatPaths(git, patchFile);
    } catch {
      return escalate("not-applied", "the patch does not parse");
    }
    const records = [];
    for (const path of paths) {
      const item = await entryAt(api, headTree, path);
      if (item === null) {
        continue;
      }
      if (item.type !== "blob") {
        return escalate("invalid", `${path} is not a file at the head`);
      }
      const bytes = Buffer.from(String((await api.getBlob(item.sha))?.content ?? ""), "base64");
      const sha = git(["hash-object", "-w", "--no-filters", "--stdin"], { input: bytes, stdio: ["pipe", "pipe", "pipe"] }).toString("utf8").trim();
      if (sha !== item.sha) {
        throw new Error(`the head blob of ${JSON.stringify(path)} reads as ${sha}, not ${item.sha}`);
      }
      records.push(`${item.mode} ${item.sha}\t${path}\0`);
    }
    if (records.length > 0) {
      git(["update-index", "--add", "-z", "--index-info"], { input: records.join(""), stdio: ["pipe", "pipe", "pipe"] });
    }
    const partial = git(["write-tree"]).toString("utf8").trim();
    let tree;
    try {
      git(["apply", "--cached", "--check", patchFile]);
      git(["apply", "--cached", patchFile]);
      tree = git(["write-tree"]).toString("utf8").trim();
    } catch {
      return escalate("not-applied", "the patch does not apply to the gated head");
    }
    const entries = diffEntries(git, partial, tree);
    if (entries.length === 0) {
      return escalate("empty", "the patch changes nothing");
    }
    const leaked = leakedBlob(git, entries);
    if (leaked) {
      return escalate("credential", leakWhy(leaked));
    }
    const refuse = [...row.refuse, ...ALWAYS];
    const renames = diffEntries(git, partial, tree, ["-M", "--diff-filter=R"]);
    const refused = firstRefusal([...renames.map((entry) => [entry, ["rename-into-refused"]]), ...entries.map((entry) => [entry, refuse])]);
    if (refused) {
      return escalate(refused.kind, refused.why);
    }
    if (row["max-files"] !== null && entries.length > row["max-files"]) {
      return escalate("invalid", `the patch changes ${entries.length} paths; the row allows ${row["max-files"]}`);
    }
    const outside = entries.find((entry) => !allow.every((admits) => admits(entry.path, entry)));
    if (outside) {
      return escalate("protected-path", `not allowed by ${row.allow.join(", ")}: ${outside.path}`);
    }
    const written = entries.filter((entry) => !ZERO.test(entry.newSha));
    const oversize = oversizeBlobs(git, written);
    if (oversize) {
      return escalate("invalid", oversize);
    }
    const contentRefusal = await CONTENT_RULES[row["content-rule"]]({ entries, git, context, api, pr: number, headSha });
    if (contentRefusal) {
      return escalate("protected-path", `refused by the ${row["content-rule"]} rule (${String(contentRefusal).slice(0, 200)})`);
    }
    if ((await api.getPull(number))?.user?.login === DEPENDABOT_LOGIN) {
      log("Dependabot opened the pull request; the patch is dropped");
      return { outcome: "held" };
    }
    if (await target.held(api, number, { holds: new Set(holdLabels), required: [], repository })) {
      log(`the ${row.target} is held; the patch is dropped`);
      return { outcome: "held" };
    }
    const movedEarly = await target.ready(api, headRef, headSha);
    if (movedEarly) {
      log(movedEarly);
      return { outcome: "superseded" };
    }
    const treeEntries = entries.filter((entry) => ZERO.test(entry.newSha)).map((entry) => ({ path: entry.path, mode: entry.oldMode, type: "blob", sha: null }));
    for (const entry of written) {
      const sha = await api.createBlob(git(["cat-file", "blob", entry.newSha]).toString("base64"));
      if (sha !== entry.newSha) {
        throw new Error(`GitHub stored a blob as ${sha}, not ${entry.newSha}`);
      }
      treeEntries.push({ path: entry.path, mode: entry.newMode, type: "blob", sha });
    }
    const built = await buildTree(api, headTree, treeEntries);
    for (const entry of entries) {
      const item = await entryAt(api, built, entry.path);
      const ok = ZERO.test(entry.newSha) ? item === null : item?.sha === entry.newSha && item?.mode === entry.newMode;
      if (!ok) {
        throw new Error(`GitHub built tree ${built} without the patched ${JSON.stringify(entry.path)}; nothing is committed`);
      }
    }
    const commit = await api.createCommit(message, built, [headSha]);
    if (!(await landed(target, api, headRef, commit, headSha, log))) {
      return { outcome: "superseded" };
    }
    log(`pushed ${commit} (${entries.length} path(s)) onto ${headRef} over the API`);
    return { outcome: "pushed", commit, branch: headRef };
  } finally {
    rmSync(scratch, { recursive: true, force: true });
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
  checkRow(row);
  const target = TARGETS[row.target];
  const allow = isMerge(row) ? [] : row.allow.map((name) => PREDICATES[name](context));
  if (row["thread-trailer"] === true && !Array.isArray(context.fixedThreads)) {
    throw new Error("the thread-trailer row needs the model job's scanned replies");
  }
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
  const message = commitMessage(row, { ref: headRef, base: baseRef, lane, activity, [target.number]: String(number) }, context.fixedThreads);
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
  if (row["api-only"] === true) {
    return pushApiOnly({ api, gitBin, row, context, allow, number, target, headSha, patchHeadSha, headRef, message, patchFile, patchSha256, holdLabels, repository, escalate, log });
  }
  const problem = patchProblem(patchFile, patchSha256);
  if (problem) {
    return escalate(problem.kind, problem.why);
  }
  const git = gitRunner(cwd, gitBin);
  const moved = patchHeadSha !== headSha;
  if (moved && row["skip-moved-head"] === true) {
    log("the head moved since the model's run; the row takes no moved head");
    return { outcome: "superseded" };
  }
  if (moved && !target.movedHead) {
    const elsewhere = `the patch was made on ${patchHeadSha}, not the start commit ${headSha}`;
    const atProducer = SHA.test(String(patchHeadSha)) && hasCommit(git, patchHeadSha) ? applyOnto(git, patchHeadSha, patchFile, false) : "";
    if (!atProducer) {
      const kind = unscannedKind(patchFile, "invalid");
      return escalate(kind, kind === "credential" ? `the patch's blobs cannot be read on ${patchHeadSha}, so they may carry a credential shape` : elsewhere);
    }
    const leaked = leakedBlob(git, diffEntries(git, patchHeadSha, atProducer));
    if (leaked) {
      return escalate("credential", leakWhy(leaked));
    }
    return escalate("invalid", elsewhere);
  }
  if (moved) {
    if (!SHA.test(String(patchHeadSha)) || !hasCommit(git, patchHeadSha)) {
      return { outcome: "superseded" };
    }
    const atProducer = applyOnto(git, patchHeadSha, patchFile, false);
    if (!atProducer) {
      return escalate("not-applied", "the patch does not apply to the head it was made on");
    }
    const patched = new Set(diffEntries(git, patchHeadSha, atProducer).map((entry) => entry.path));
    const touched = git(["diff-tree", "-r", "-z", "--no-renames", "--name-only", patchHeadSha, headSha]).toString("utf8").split("\0");
    if (touched.some((path) => patched.has(path))) {
      log("commits since the model's head touch a patched path; the patch is superseded");
      return { outcome: "superseded" };
    }
  }
  let tree = applyOnto(git, headSha, patchFile, moved);
  if (!tree) {
    const holds = row.escalations.some((reason) => reason.endsWith("-credential"));
    return escalate(holds ? unscannedKind(patchFile, "not-applied") : "not-applied", "the patch does not apply to the gated head");
  }
  let entries = diffEntries(git, headSha, tree);
  if (entries.length === 0) {
    return escalate("empty", "the patch changes nothing");
  }
  const leaked = leakedBlob(git, entries);
  if (leaked) {
    return escalate("credential", leakWhy(leaked));
  }
  let from = headSha;
  if (refusalBase && refusalBase !== headSha) {
    if (!SHA.test(String(refusalBase)) || !hasCommit(git, refusalBase)) {
      return escalate("invalid", `the default-branch commit ${refusalBase} is not in the checkout`);
    }
    from = git(["merge-base", refusalBase, headSha]).toString("utf8").trim();
  }
  const reaching = from === headSha ? entries : diffEntries(git, from, tree);
  const renames = diffEntries(git, from, tree, ["-M", "--diff-filter=R"]);
  const refuse = [...row.refuse, ...ALWAYS];
  const refused = firstRefusal([
    ...renames.map((entry) => [entry, ["rename-into-refused"]]),
    ...entries.map((entry) => [entry, refuse]),
    ...(reaching === entries ? [] : reaching.map((entry) => [entry, refuse])),
  ]);
  if (refused) {
    return escalate(refused.kind, refused.why);
  }
  if (row["max-files"] !== null && entries.length > row["max-files"]) {
    return escalate("invalid", `the patch changes ${entries.length} paths; the row allows ${row["max-files"]}`);
  }
  const outside = entries.find((entry) => !allow.every((admits) => admits(entry.path, entry)));
  if (outside) {
    return escalate("protected-path", `not allowed by ${row.allow.join(", ")}: ${outside.path}`);
  }
  let written = entries.filter((entry) => !ZERO.test(entry.newSha));
  const oversize = oversizeBlobs(git, written);
  if (oversize) {
    return escalate("invalid", oversize);
  }
  if (Object.hasOwn(CONTENT_DROPS, String(row["content-rule"]))) {
    const { updates, warnings } = CONTENT_DROPS[row["content-rule"]]({ entries, git });
    for (const warning of warnings) {
      log(warning);
    }
    if (updates.length > 0) {
      git(["update-index", "-z", "--index-info"], { input: updates.map((update) => `${update}\0`).join(""), stdio: ["pipe", "pipe", "pipe"] });
      tree = git(["write-tree"]).toString("utf8").trim();
      entries = diffEntries(git, headSha, tree);
      if (entries.length === 0) {
        log("the patch changes nothing outside protected content; nothing is pushed");
        return { outcome: "not-applicable" };
      }
      const rebuiltLeak = leakedBlob(git, entries);
      if (rebuiltLeak) {
        return escalate("credential", leakWhy(rebuiltLeak));
      }
      written = entries.filter((entry) => !ZERO.test(entry.newSha));
      const rebuiltOversize = oversizeBlobs(git, written);
      if (rebuiltOversize) {
        return escalate("invalid", rebuiltOversize);
      }
    }
  }
  const blobs = written.map((entry) => ({ entry, bytes: git(["cat-file", "blob", entry.newSha]) }));
  const contentRefusal = Object.hasOwn(CONTENT_RULES, String(row["content-rule"])) ? await CONTENT_RULES[row["content-rule"]]({ entries, git, context, api, pr, headSha }) : null;
  if (contentRefusal) {
    return escalate("protected-path", `refused by the ${row["content-rule"]} rule (${String(contentRefusal).slice(0, 200)})`);
  }
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
  if (await target.held(api, number, { holds: new Set(holdLabels), required: requiredLabels, repository })) {
    log(`the ${row.target} is held; the patch is dropped`);
    return { outcome: "held" };
  }
  const movedEarly = await target.ready(api, headRef, headSha);
  if (movedEarly) {
    log(movedEarly);
    return { outcome: "superseded" };
  }
  const treeEntries = entries.filter((entry) => ZERO.test(entry.newSha)).map((entry) => ({ path: entry.path, mode: entry.oldMode, type: "blob", sha: null }));
  for (const { entry, bytes } of blobs) {
    const sha = await api.createBlob(bytes.toString("base64"));
    if (sha !== entry.newSha) {
      throw new Error(`GitHub stored a blob as ${sha}, not ${entry.newSha}`);
    }
    treeEntries.push({ path: entry.path, mode: entry.newMode, type: "blob", sha });
  }
  const headTree = git(["rev-parse", `${headSha}^{tree}`]).toString("utf8").trim();
  const built = await buildTree(api, headTree, treeEntries);
  if (built !== tree) {
    throw new Error(`GitHub built tree ${built}, not the applied tree ${tree}; nothing is committed`);
  }
  const commit = await api.createCommit(message, tree, [headSha]);
  if (!(await landed(target, api, headRef, commit, headSha, log))) {
    return { outcome: "superseded" };
  }
  log(`pushed ${commit} (${entries.length} path(s)) onto ${headRef}`);
  return { outcome: "pushed", commit, branch: headRef };
}

export async function buildTree(api, baseTree, entries, max = MAX_TREE_ENTRIES_PER_REQUEST) {
  const deletionsFirst = entries.length > max ? [...entries.filter((item) => item.sha === null), ...entries.filter((item) => item.sha !== null)] : entries;
  let built = baseTree;
  for (let start = 0; start < deletionsFirst.length; start += max) {
    built = await api.createTree(built, deletionsFirst.slice(start, start + max));
  }
  return built;
}

const MAX_ANSWER = 500;
export async function failedAnswer(response, token) {
  let text = await response.text().catch(() => "");
  try {
    const body = JSON.parse(text);
    if (body !== null && typeof body === "object") {
      text = JSON.stringify({ message: body.message, errors: body.errors });
    }
  } catch {
  }
  if (token) {
    text = text.split(token).join("[redacted]");
  }
  for (const [, pattern] of CREDENTIAL_SHAPES) {
    text = text.replace(new RegExp(pattern.source, "g"), "[redacted]");
  }
  return text.replace(/[\x00-\x1f\x7f]+/g, " ").trim().slice(0, MAX_ANSWER);
}

export function createGitHubApi({ token, repository, apiUrl, fetch: rawFetch, sleep }) {
  if (typeof rawFetch !== "function") {
    throw new TypeError("createGitHubApi needs a fetch: an importer run from a checkout passes the rate guard's");
  }
  const fetch = retryFetch(rawFetch, { sleep });
  const repo = `${apiUrl}/repos/${repository}`;
  const headers = { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" };
  async function request(path, method = "GET", body, safeToResend = false) {
    const response = await fetch(`${repo}/${path}`, {
      method,
      safeToResend,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      const answer = await failedAnswer(response, token);
      throw Object.assign(new Error(`${method} ${path} returned ${response.status}${answer ? `: ${answer}` : ""}`), { status: response.status });
    }
    return { data: await response.json(), link: response.headers.get("link") ?? "" };
  }
  const refPath = (ref) => ref.split("/").map(encodeURIComponent).join("/");
  return {
    getPull: async (pr) => (await request(`pulls/${pr}`)).data,
    compare: async (base, head) => (await request(`compare/${base}...${head}`)).data,
    getTree: async (sha) => (await request(`git/trees/${sha}`)).data,
    getCommit: async (sha) => (await request(`git/commits/${sha}`)).data,
    getBlob: async (sha) => (await request(`git/blobs/${sha}`)).data,
    async listLabels(pr) {
      const { data, link } = await request(`issues/${pr}/labels?per_page=100`);
      if (/rel="next"/.test(link)) {
        throw new Error("the pull request has more labels than one page holds");
      }
      return data;
    },
    readBranch: async (ref) => (await request(`git/ref/heads/${refPath(ref)}`)).data.object.sha,
    createBlob: async (content) => (await request("git/blobs", "POST", { content, encoding: "base64" }, true)).data.sha,
    createTree: async (baseTree, tree) => (await request("git/trees", "POST", { base_tree: baseTree, tree }, true)).data.sha,
    createCommit: async (message, tree, parents) => (await request("git/commits", "POST", { message, tree, parents }, true)).data.sha,
    async updateRef(ref, sha, force) {
      await request(`git/refs/${refPath(ref)}`, "PATCH", { sha, force }, true);
    },
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

export function keptThreadsFrom(file) {
  if (!file) {
    return undefined;
  }
  const { threads: kept, verify_notes: notes = [], pr_paths: prPaths = [], copy_paths: copyPaths = [] } = JSON.parse(readFileSync(file, "utf8")) ?? {};
  const plain = (value) => typeof value === "string" && value !== "";
  if (!Array.isArray(notes) || !notes.every((note) => NOTE_ID.test(String(note?.id)) && plain(note.path))) {
    throw new Error("KEPT_THREADS_FILE holds a malformed verify_notes list");
  }
  const threads = Array.isArray(kept) ? [...kept, ...notes.map(({ id, path }) => ({ id, path }))] : kept;
  if (
    !Array.isArray(threads) ||
    !Array.isArray(prPaths) ||
    !prPaths.every(plain) ||
    !Array.isArray(copyPaths) ||
    !copyPaths.every(plain) ||
    !threads.every(
      (thread) =>
        plain(thread?.path) && (thread.named_paths === undefined || (Array.isArray(thread.named_paths) && thread.named_paths.every(plain))),
    )
  ) {
    throw new Error("KEPT_THREADS_FILE is not a thread file of paths, named_paths, pr_paths and copy_paths");
  }
  return {
    paths: new Set(threads.map((thread) => thread.path)),
    threads: threads.map(({ path, named_paths }) => ({ path, named_paths })),
    prPaths: new Set(prPaths),
    copyPaths: new Set(copyPaths),
    ids: threads.map((thread) => thread.id).filter((id) => typeof id === "string" && (THREAD_ID.test(id) || NOTE_ID.test(id))),
  };
}

const MAX_REPLIES_BYTES = 49152;

export function fixedThreadsFrom(file, kept) {
  if (!file) {
    return undefined;
  }
  const stat = lstatSync(file);
  if (!stat.isFile() || stat.size > MAX_REPLIES_BYTES) {
    throw new Error(`PATCH_REPLIES_FILE is not a regular file of at most ${MAX_REPLIES_BYTES} bytes`);
  }
  const valid = new Set();
  for (const line of readFileSync(file, "utf8").split("\n")) {
    try {
      const reply = JSON.parse(line);
      if (reply?.disposition === "VALID") {
        valid.add(reply.thread);
      }
    } catch {
    }
  }
  return (kept?.ids ?? []).filter((id) => valid.has(id));
}

export function sharedCopiesFrom(baseDir) {
  if (!baseDir) {
    throw new Error("BASE_DIR is not set; the shared-copies allow reads the base registry");
  }
  return new Set(sharedCopyPairs(readFileSync(join(baseDir, "scripts/shared-copies.txt"), "utf8")).map(([, copy]) => copy));
}

export function cdnPinsFrom(baseDir) {
  if (!baseDir) return null;
  try {
    return new Set(cdnPaths(JSON.parse(readFileSync(join(baseDir, CDN_RECORD), "utf8"))));
  } catch {
    return null;
  }
}

export function dependabotPairs(baseDir) {
  try {
    return parseConfig(readFileSync(join(baseDir, DEPENDABOT_PATH), "utf8"));
  } catch {
    return null;
  }
}

export function mergeFrom(env, { cwd = process.cwd(), gitBin = "/usr/bin/git" } = {}) {
  need(env, ["MERGE_BASE_SHA", "CONFLICT_TREE", "MERGE_STATE", "TREE_ENTRIES_SCRIPT", "TREE_ENTRIES_SHA256"]);
  const raw = gitRunner(cwd, gitBin)(["ls-files", "-u", "-z"]).toString("utf8");
  const unmerged = new Set(raw.split("\0").filter(Boolean).map((record) => fieldsAndPath(record)[1]));
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

function modelRung(value = "") {
  if (!["", "0", "1"].includes(value)) {
    throw new Error("MODEL_RUNG must be empty, 0 or 1");
  }
  return value === "1" ? 1 : 0;
}

function weakenRetryFrom(value = "") {
  if (!["", "true", "false"].includes(value)) {
    throw new Error("WEAKEN_RETRY must be empty, true or false");
  }
  return value === "true";
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
      weakenRetry: weakenRetryFrom(env.WEAKEN_RETRY),
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
  const keptThreads = keptThreadsFrom(env.KEPT_THREADS_FILE);
  const result = await push({
    api: api ?? createGitHubApi({ token: env.GH_TOKEN, repository: env.GITHUB_REPOSITORY, apiUrl: env.GITHUB_API_URL ?? "https://api.github.com", fetch: globalThis.fetch }),
    cwd,
    gitBin,
    row,
    context: {
      keptThreads,
      fixedThreads: row["thread-trailer"] === true ? fixedThreadsFrom(env.PATCH_REPLIES_FILE, keptThreads) : undefined,
      dependencyVerdict: env.DEPENDENCY_VERDICT ?? "",
      dependabotConfig: row.allow.includes("dependency-manifests") ? dependabotPairs(env.BASE_DIR) : undefined,
      baseDir: env.BASE_DIR,
      cdnPins: row.allow.includes("cdn-pins") ? cdnPinsFrom(env.BASE_DIR) : undefined,
      sharedCopies: row.allow.includes("shared-copies") ? sharedCopiesFrom(env.BASE_DIR) : undefined,
      merge,
    },
    [target.number]: Number(env[numberKey]),
    headSha: env.HEAD_SHA,
    patchHeadSha: env.PATCH_HEAD_SHA,
    headRef: env.HEAD_REF,
    baseRef: env.BASE_REF ?? "",
    lane: env.LANE,
    activity: env.PATCH_ACTIVITY,
    patchFile: merge?.state === "clean" && !(row["clean-patch"] === true && env.PATCH_SHA256) ? "" : env.PATCH_FILE,
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
    const skip = { superseded: "superseded-sha", "not-applicable": "not-applicable" }[result.outcome] ?? (result.outcome === "escalate" ? stopSkip(result.escalationReason) : "awaiting-human");
    writeFileSync(env.SKIP_REASON_FILE, `${skip}\n`);
  }
  log(`apply-patch (${row.name}): ${result.outcome}${result.escalationReason ? ` (${result.escalationReason})` : ""}`);
  return 0;
}

runAsScript(import.meta.url, "apply-patch", () => main(process.argv.slice(2), process.env));
