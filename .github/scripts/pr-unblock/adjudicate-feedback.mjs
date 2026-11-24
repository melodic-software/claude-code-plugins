#!/usr/bin/env node
// adjudicate-feedback.mjs: the pr-unblock lane's adjudication of a disputed
// review finding, one an address-feedback round answered INCORRECT, UNCERTAIN
// or VALID-defer (DISPUTED): any reply that leaves the thread open. A
// fresh-context model sees the whole review comment, the locations both the
// reviewer and the lane cited and those files at the head, never the lane's
// reasoning, and returns a verdict as structured output; this file stages its
// input, collects its verdict, and applies it with no model.
//
//   prepare  run by pr-unblock.yml's adjudicate-feedback job, base code only,
//            with the job's read-only token, before any model turn: reads the
//            select job's threads.json and the scan job's replies.jsonl, each
//            checked against the SHA-256 its writer recorded, and for each
//            DISPUTED reply on an adjudicable thread no adjudication has
//            stood before and no trusted person directed (up to MAX_THREADS)
//            writes
//            <OUT_DIR>/<slot>/: finding.json (path, line, head, and the
//            review comment), evidence.json (the lane's cited path:line
//            list, never its note), review-evidence.json (the locations the
//            review comment cites) and files/<path>.txt, the cited files and
//            the finding's own at the head, and contract.json: the linked
//            issues' spec text trusted people wrote (pr-verify's
//            resolve-pr.mjs linkedIssues), empty when none is linked or it
//            cannot be read. <OUT_DIR>/index.json names each slot's thread.
//            Outputs `count`.
//   collect  run after the model steps: reads each slot's verdict.json (the
//            launcher's structured output) and writes VERDICTS_FILE, one
//            entry per indexed thread; an absent or malformed verdict is
//            null, and an intent or design question settled by a quote that
//            is not in the slot's contract.json, or settled toward the lane,
//            stays that question for a person. Outputs `sha256`.
//
// settleDisputes is publish-feedback.mjs's DISPUTED branch: after the lane's
// replies are posted it applies each verdict (adjudicationReplies, fixed text
// only) and returns the round's escalation reason.

import { createHash } from "node:crypto";
import { appendFileSync, existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import { runAsScript } from "../lib/run-main.mjs";
import { claimsSecurity, contractIssues, createGitHubApi, FINDING_STANDS, linkedSpec, need, SECURITY_PERSON_SEVERITY, securityNeedsPerson, severityOf, SEVERITY_SHAPED, SHA } from "./address-feedback.mjs";

export { contractIssues };

export const MAX_THREADS = 3;
export const DISPUTED = Object.freeze(["INCORRECT", "UNCERTAIN", "VALID-defer"]);
export const LEFT_OPEN = "left-open";
export const VERDICTS = ["lane", "reviewer", "human", "tests-only"];
export const QUESTIONS = ["intent", "design", "security"];
export const CONTRACT_QUESTIONS = ["intent", "design"];
export const QUOTE_MIN = 20;
const QUOTE_MAX = 2000;
const ISSUE_URL = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/[1-9][0-9]{0,9}$/;
// The first line of each adjudication reply the lanes App posts: this, or
// FINDING_STANDS, which the next address-feedback round reads.
export const FINDING_ANSWERED = "<!-- pr-unblock adjudicate-feedback: finding-answered -->";
const FILE_BYTES = 204800;
const EVIDENCE_CAP = 10;
// Each staged file's suffix, so a cited CLAUDE.md, AGENTS.md or .claude/**
// file is never at a path Claude Code reads as instructions.
export const STAGED_SUFFIX = ".txt";
const PATH = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*$/;
const PATH_LINE = /^([A-Za-z0-9_@+.-]+(?:\/[A-Za-z0-9_@+.-]+)*):([1-9][0-9]{0,6})$/;
const DOT_SEGMENT = /(^|\/)\.\.?(\/|$)/;
const THREAD_ID = /^PRRT_[A-Za-z0-9_-]{1,100}$/;
const PROSE_LOCATION = /(?<![\w@+./:-])((?:[\w@+.-]+\/)*[\w@+.-]+):([1-9][0-9]{0,6})(?![\w])/g;
const CRITICAL = new RegExp(`${SEVERITY_SHAPED.source}[^A-Za-z\\n]*critical\\b`, "im");
export const isCritical = (body) => CRITICAL.test(String(body ?? ""));
const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");
const safePath = (path) => typeof path === "string" && PATH.test(path) && !DOT_SEGMENT.test(path);

export const stood = (comments) => (comments ?? []).some((comment) => comment.author === "lane" && firstLine(comment.body) === FINDING_STANDS);

export const directed = (comments) => (comments ?? []).some((comment) => comment.direction === true);

const listedState = (comments) => (comments?.[0]?.listed === true ? comments[0].security ?? "pending" : null);
const minorSecurity = (comments) => comments?.[0]?.lane === "claude-security-review" && !securityNeedsPerson(comments[0].body);
export const adjudicable = (comments) => {
  const root = comments?.[0];
  if (root?.author !== "reviewer" || isCritical(root.body)) {
    return false;
  }
  if (root.listed === true) {
    return listedState(comments) === "clear";
  }
  if (root.lane === undefined) {
    return !claimsSecurity(root.body);
  }
  return root.lane === "claude-review" || minorSecurity(comments);
};

export const securityRoot = (comments) => {
  const root = comments?.[0];
  if (root?.author === undefined) {
    return true;
  }
  if (root.author !== "reviewer") {
    return false;
  }
  if (root.listed === true) {
    return listedState(comments) !== "clear";
  }
  if (root.lane === undefined) {
    return claimsSecurity(root.body);
  }
  return root.lane === "claude-security-review" ? securityNeedsPerson(root.body) : root.lane !== "claude-review";
};

const DEPENDENCIES_FLAG = /^manifest dependencies: flag(,|$)/;
const PLUGIN_MANIFEST = /^plugins\/([A-Za-z0-9._-]+)\/\.claude-plugin\/plugin\.json$/;
export const MARKETPLACE = ".claude-plugin/marketplace.json";
// A dependency entry that resolves in the plugin's own marketplace: a string
// with no `@marketplace` and no version, which only the object form carries
// (code.claude.com/docs/en/plugins-reference#dependencies, as of 2026-10-29;
// recheck when that section adds an entry form).
const BARE_NAME = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const IN_REPOSITORY = /^\.\/[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)*$/;
// What a dependency may declare and hold and still add nothing Claude Code
// runs once it is enabled for every user of the flagged plugin: a manifest of
// metadata and userConfig only, a marketplace entry of listing fields only,
// and none of the default locations of hooks (a mod's module included), MCP
// or LSP servers, monitors, executables, workflows or settings
// (code.claude.com/docs/en/plugins-reference, "Fields" and "Standard
// layout", as of 2026-10-29; recheck when either adds a component). Any other
// key, its own `dependencies` included, fails closed.
const INERT_MANIFEST = new Set(["$schema", "name", "displayName", "version", "description", "author", "homepage", "repository", "license", "keywords", "metadata", "userConfig"]);
const INERT_ENTRY = new Set(["name", "source", "displayName", "version", "description", "author", "homepage", "repository", "license", "keywords", "category", "tags", "relevance", "defaultEnabled"]);
const RUNS = new Set(["hooks", ".mcp.json", ".lsp.json", "monitors", "bin", "workflows", "settings.json"]);
const GUARDED =
  /\b(install(ed)?|uninstalled|enabled?|disabled|resolves?|available|unavailable|absent|present|missing|exists?|loaded|fallback|falls? back|otherwise|optional(ly)?|never|not|cannot|without|if|when(ever)?|unless|where|whether|once|in case)\b|n['\u2019]t\b/i;
const GUARD_LINES = 2;
// The files whose text Claude Code loads as a plugin's skills, agents or
// commands; an eval case, a changelog or a script is no call site.
const callSite = (dir, path) => new RegExp(`^plugins/${dir.replace(/\./g, "\\.")}/(skills|agents|commands)/([A-Za-z0-9_@+.-]+/)*[A-Za-z0-9_@+.-]+\\.md$`).test(path) && !/\/evals\//.test(path);
const firstContentLine = (body) => String(body ?? "").split("\n").map((line) => line.replace(/\r$/, "")).find((line) => line.trim() !== "") ?? "";
const nextSection = (lines) => {
  let next = false;
  let fence = false;
  return lines.map((line) => {
    if (/^\s*(```|~~~)/.test(line)) {
      fence = !fence;
    } else if (!fence && /^#{1,2}\s/.test(line)) {
      next = /^##\s+Next\b/.test(line);
    }
    return next;
  });
};
const unguardedCall = (lines, at, dependency, next = nextSection(lines)) =>
  new RegExp(`(^|[\\s\`(])/${dependency}:`).test(lines[at] ?? "") &&
  !next[at] &&
  !GUARDED.test(lines.slice(Math.max(0, at - GUARD_LINES), at + GUARD_LINES + 1).join("\n"));
const linesOf = (file) => (typeof file === "string" ? file.split("\n") : []);

export const dependencyFlag = (comments, path) => {
  const root = comments?.[0];
  const body = String(root?.body ?? "");
  return (
    root?.author === "reviewer" &&
    root.listed !== true &&
    root.lane === "claude-security-review" &&
    PLUGIN_MANIFEST.test(path ?? "") &&
    DEPENDENCIES_FLAG.test(firstContentLine(body)) &&
    !isCritical(body) &&
    ["SUGGESTION", "IMPORTANT"].includes(severityOf(body))
  );
};

const parseObject = (text) => {
  try {
    const value = JSON.parse(String(text));
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
};

const pluginEntries = (text) => {
  const plugins = parseObject(text)?.plugins;
  return Array.isArray(plugins) ? plugins.filter((entry) => entry !== null && typeof entry === "object") : [];
};

async function executable({ ref, read, listTree, entry, dir }) {
  const entryKey = Object.keys(entry ?? {}).find((key) => !INERT_ENTRY.has(key));
  if (entryKey !== undefined) {
    return `has a ${MARKETPLACE} entry that sets ${entryKey}`;
  }
  const manifestPath = `${dir}/.claude-plugin/plugin.json`;
  const manifest = parseObject(await read(manifestPath));
  if (!manifest) {
    return `has no readable ${manifestPath}`;
  }
  const manifestKey = Object.keys(manifest).find((key) => !INERT_MANIFEST.has(key));
  if (manifestKey !== undefined) {
    return `declares ${manifestKey} in ${manifestPath}`;
  }
  const tree = await listTree(ref, dir);
  if (!Array.isArray(tree) || tree.length === 0) {
    return `has no files under ${dir}`;
  }
  const ships = tree.find((item) => RUNS.has(item?.name));
  return ships ? `ships ${dir}/${ships.name}` : null;
}

export async function hardRequire({ getText, listTree, sha, baseSha, path, evidence }) {
  if (!SHA.test(String(baseSha ?? ""))) {
    return { why: "the PR's base commit is unknown" };
  }
  if (typeof listTree !== "function") {
    return { why: "the dependency's files cannot be listed" };
  }
  const read = new Map();
  const at = (ref) => (file) => {
    const key = `${ref}:${file}`;
    if (!read.has(key)) {
      read.set(key, getText(file, ref));
    }
    return read.get(key);
  };
  const text = at(sha);
  const baseText = at(baseSha);
  const dir = PLUGIN_MANIFEST.exec(path ?? "")?.[1];
  const manifest = dir ? parseObject(await text(path)) : null;
  const entries = pluginEntries(await text(MARKETPLACE));
  if (!manifest || !entries.some((entry) => entry.source === `./plugins/${dir}`)) {
    return { why: `the flagged plugin is not an entry of ${MARKETPLACE}` };
  }
  const dependencies = manifest.dependencies;
  if (!Array.isArray(dependencies) || dependencies.length === 0) {
    return { why: "the manifest lists no dependencies" };
  }
  const baseEntries = pluginEntries(await baseText(MARKETPLACE));
  const sites = [];
  for (const dependency of dependencies) {
    if (typeof dependency !== "string" || !BARE_NAME.test(dependency)) {
      return { why: `${JSON.stringify(dependency).slice(0, 100)} is not a bare plugin name` };
    }
    const source = entries.find((entry) => entry.name === dependency)?.source;
    if (dependency === manifest.name || typeof source !== "string" || !IN_REPOSITORY.test(source) || DOT_SEGMENT.test(source.slice(2))) {
      return { why: `${dependency} is not another plugin of ${MARKETPLACE} with a source in this repository` };
    }
    if (!baseEntries.some((entry) => entry.name === dependency && entry.source === source)) {
      return { why: `${dependency} is not an entry of ${MARKETPLACE} at the PR base with the source ${source}` };
    }
    for (const [ref, readAt, refEntries, side] of [
      [baseSha, baseText, baseEntries, "base"],
      [sha, text, entries, "head"],
    ]) {
      const runs = await executable({ ref, read: readAt, listTree, entry: refEntries.find((entry) => entry.name === dependency), dir: source.slice(2) });
      if (runs) {
        return { why: `${dependency} at the PR ${side} ${runs}` };
      }
    }
    let site = null;
    let baseMiss = null;
    for (const cited of evidence) {
      const match = PATH_LINE.exec(cited);
      if (!match || DOT_SEGMENT.test(match[1]) || !callSite(dir, match[1])) {
        continue;
      }
      if (!unguardedCall(linesOf(await text(match[1])), Number(match[2]) - 1, dependency)) {
        continue;
      }
      const baseLines = linesOf(await baseText(match[1]));
      const baseNext = nextSection(baseLines);
      if (baseLines.some((_, line) => unguardedCall(baseLines, line, dependency, baseNext))) {
        site = cited;
        break;
      }
      baseMiss ??= match[1];
    }
    if (site === null && baseMiss !== null) {
      return { why: `${dependency}: no line of ${baseMiss} at the PR base invokes /${dependency}: with no gate, fallback or negation within ${GUARD_LINES} lines` };
    }
    if (site === null) {
      return { why: `no skill, agent or command line the lane cited in plugins/${dir}/ invokes /${dependency}: with no gate, fallback or negation within ${GUARD_LINES} lines` };
    }
    sites.push(site);
  }
  return { sites };
}

export function reviewerEvidence(body, repository) {
  const text = String(body ?? "");
  const found = [...text.matchAll(PROSE_LOCATION)].filter((match) => /[/.]/.test(match[1])).map((match) => [match.index, match[1], match[2]]);
  if (/^[\w.-]+\/[\w.-]+$/.test(repository ?? "")) {
    const permalink = new RegExp(`https://github\\.com/${repository.replace(/\./g, "\\.")}/blob/[0-9a-f]{40}/([^\\s#?)\\]]+)#L([1-9][0-9]{0,6})`, "g");
    found.push(...[...text.matchAll(permalink)].map((match) => [match.index, match[1], match[2]]));
  }
  const seen = new Set();
  const out = [];
  for (const [, path, line] of found.sort((a, b) => a[0] - b[0])) {
    const key = `${path}:${line}`;
    if (safePath(path) && !seen.has(key) && out.length < EVIDENCE_CAP) {
      seen.add(key);
      out.push({ path, line: Number(line) });
    }
  }
  return out;
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

function readChecked(path, expected, what) {
  const stat = lstatSync(path);
  if (!stat.isFile()) {
    throw new Error(`${what} is not a regular file`);
  }
  const text = readFileSync(path, "utf8");
  if (!/^[0-9a-f]{64}$/.test(expected ?? "") || sha256(text) !== expected) {
    throw new Error(`${what} does not match the SHA-256 its writer recorded`);
  }
  return text;
}

export function disputes(threadFile, repliesText, repository = "") {
  const kept = new Map((threadFile.threads ?? []).map((thread) => [thread.id, thread]));
  const slots = [];
  const over = [];
  const seen = new Set();
  for (const line of repliesText.split("\n").filter((row) => row.trim() !== "")) {
    const reply = JSON.parse(line);
    const thread = kept.get(reply?.thread);
    const settledByScript = reply?.disposition === "INCORRECT" && dependencyFlag(thread?.comments, thread?.path);
    if (!DISPUTED.includes(reply?.disposition) || !thread || !THREAD_ID.test(thread.id) || seen.has(thread.id) || settledByScript || !adjudicable(thread.comments) || stood(thread.comments) || directed(thread.comments)) {
      continue;
    }
    seen.add(thread.id);
    if (slots.length >= MAX_THREADS) {
      over.push(thread.id);
      continue;
    }
    const evidence = (Array.isArray(reply.evidence) ? reply.evidence : [])
      .slice(0, EVIDENCE_CAP)
      .filter((ev) => typeof ev === "string")
      .map((ev) => PATH_LINE.exec(ev))
      .filter((match) => match && !DOT_SEGMENT.test(match[1]))
      .map((match) => ({ path: match[1], line: Number(match[2]) }));
    const comment = String(thread.comments?.[0]?.body ?? "");
    const cited = reviewerEvidence(comment, repository);
    const paths = [...new Set([thread.path, ...evidence.map((ev) => ev.path), ...cited.map((ev) => ev.path)])].filter(safePath);
    slots.push({
      thread: thread.id,
      finding: { path: thread.path, line: thread.line ?? null, comment },
      evidence,
      cited,
      paths,
    });
  }
  return { slots, over };
}

export async function prepare({ threadsText, repliesText, headSha, outDir, getText, repository = "", contract = [] }) {
  const threadFile = JSON.parse(threadsText);
  if (threadFile?.version !== 1 || threadFile.head_sha !== headSha) {
    throw new Error("threads.json is not the select job's thread file for this head");
  }
  const { slots, over } = disputes(threadFile, repliesText, repository);
  mkdirSync(outDir, { recursive: true });
  const index = [];
  for (const [slot, entry] of slots.entries()) {
    const dir = join(outDir, String(slot));
    mkdirSync(join(dir, "files"), { recursive: true });
    const found = new Map();
    for (const path of entry.paths) {
      const text = await getText(path, headSha);
      const fits = typeof text === "string" && Buffer.byteLength(text) <= FILE_BYTES;
      let state = typeof text !== "string" ? "absent" : fits ? "present" : "too-large";
      if (fits) {
        try {
          const staged = join(dir, "files", `${path}${STAGED_SUFFIX}`);
          mkdirSync(dirname(staged), { recursive: true });
          writeFileSync(staged, text);
        } catch {
          state = "absent";
        }
      }
      found.set(path, state);
    }
    writeFileSync(join(dir, "finding.json"), `${JSON.stringify({ head_sha: headSha, ...entry.finding, file: found.get(entry.finding.path) ?? "absent" }, null, 2)}\n`);
    const locations = (list) => `${JSON.stringify(list.map((ev) => ({ location: `${ev.path}:${ev.line}`, file: found.get(ev.path) ?? "absent" })), null, 2)}\n`;
    writeFileSync(join(dir, "evidence.json"), locations(entry.evidence));
    writeFileSync(join(dir, "review-evidence.json"), locations(entry.cited));
    writeFileSync(join(dir, "contract.json"), `${JSON.stringify({ issues: contractIssues(contract, repository) }, null, 2)}\n`);
    index.push({ slot, thread: entry.thread });
  }
  writeFileSync(join(outDir, "index.json"), `${JSON.stringify({ version: 1, head_sha: headSha, slots: index, over }, null, 2)}\n`);
  return { count: index.length, over };
}

export function quoteSource(quote, issues) {
  if (typeof quote !== "string" || quote.trim().length < QUOTE_MIN) {
    return null;
  }
  const issue = (Array.isArray(issues) ? issues : []).find((entry) =>
    [entry?.body, ...(Array.isArray(entry?.comments) ? entry.comments : [])].some((text) => typeof text === "string" && text.includes(quote)),
  );
  return typeof issue?.url === "string" && ISSUE_URL.test(issue.url) ? issue.url : null;
}

export function verdictOf(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const keys = Object.keys(value).sort().join(",");
  if (keys !== "question,verdict" && keys !== "question,quote,verdict") {
    return null;
  }
  const { verdict, question, quote = "" } = value;
  if (!VERDICTS.includes(verdict) || typeof quote !== "string" || quote.length > QUOTE_MAX) {
    return null;
  }
  if (verdict === "human") {
    return QUESTIONS.includes(question) ? { verdict, question } : null;
  }
  if (question === "none") {
    return { verdict, question };
  }
  if (!CONTRACT_QUESTIONS.includes(question) || quote.trim() === "") {
    return null;
  }
  return verdict === "reviewer" ? { verdict, question, quote } : verdict === "lane" ? { verdict: "human", question } : null;
}

export function checkQuote(verdict, issues) {
  if (verdict?.quote === undefined) {
    return verdict;
  }
  const url = quoteSource(verdict.quote, issues);
  return url === null ? { verdict: "human", question: verdict.question } : { ...verdict, url };
}

export function collect({ outDir }) {
  const index = JSON.parse(readFileSync(join(outDir, "index.json"), "utf8"));
  const threads = index.slots.map(({ slot, thread }) => {
    const path = join(outDir, String(slot), "verdict.json");
    let verdict = null;
    if (existsSync(path) && lstatSync(path).isFile()) {
      try {
        verdict = verdictOf(JSON.parse(readFileSync(path, "utf8")));
      } catch {
        verdict = null;
      }
    }
    if (verdict?.quote !== undefined) {
      let issues = [];
      try {
        const contract = join(outDir, String(slot), "contract.json");
        issues = lstatSync(contract).isFile() ? JSON.parse(readFileSync(contract, "utf8")).issues : [];
      } catch {
        issues = [];
      }
      verdict = checkQuote(verdict, issues);
    }
    return { thread, ...(verdict ?? { verdict: null, question: null }) };
  });
  return { version: 1, head_sha: index.head_sha, threads };
}

export function parseVerdicts(text, headSha) {
  if (text === null) {
    return new Map();
  }
  try {
    const file = JSON.parse(text);
    if (file?.version !== 1 || file.head_sha !== headSha || !Array.isArray(file.threads)) {
      return new Map();
    }
    return new Map(
      file.threads
        .map((entry) => {
          const verdict = verdictOf({ verdict: entry?.verdict, question: entry?.question, ...(entry?.quote === undefined ? {} : { quote: entry.quote }) });
          if (verdict?.quote !== undefined) {
            return [entry.thread, typeof entry.url === "string" && ISSUE_URL.test(entry.url) ? { ...verdict, url: entry.url } : { verdict: "human", question: verdict.question }];
          }
          return [entry?.thread, verdict];
        })
        .filter(([thread, verdict]) => THREAD_ID.test(thread ?? "") && verdict !== null),
    );
  } catch {
    return new Map();
  }
}

const evidenceLine = (evidence) => (evidence.length > 0 ? `Evidence: ${evidence.map((ev) => `\`${ev}\``).join(", ")}` : "Evidence: none in the checkout");

const contractLines = (settled) =>
  settled?.quote === undefined
    ? []
    : [
        "",
        `The linked issue settles this ${settled.question} question (${settled.url}):`,
        "",
        ...settled.quote.split("\n").map((line) => `> ${line.replace(/\r$/, "").replaceAll("<!--", "&lt;!--")}`),
      ];

export function adjudicationReply(verdict, evidence, headSha, settled) {
  const seen = `A fresh-context adjudicator read the review comment, the locations both sides cited and the code at \`${headSha}\`, without the fixing lane's reasoning,`;
  return verdict === "lane"
    ? [FINDING_ANSWERED, "**pr-unblock / adjudicate-feedback: the finding does not hold, resolved**", "", `${seen} and found that the code answers the finding.`, "", evidenceLine(evidence)].join("\n")
    : [
        FINDING_STANDS,
        "**pr-unblock / adjudicate-feedback: the finding stands**",
        "",
        `${seen} and found that the finding holds. The next address-feedback round fixes it; a round that leaves this thread open again ends the lane in a failing status.`,
        ...contractLines(settled),
        "",
        evidenceLine(evidence),
      ].join("\n");
}

export function testsReply(runs, headSha) {
  return [
    FINDING_ANSWERED,
    "**pr-unblock / adjudicate-feedback: every check the plan selected passed, resolved**",
    "",
    `A fresh-context adjudicator found that this finding asks only for tests or checks CI runs. Every check the plan selected (\`scripts/plan-test-lanes.sh\`) passed at \`${headSha}\`, and no test check on that commit failed:`,
    "",
    ...runs.map((run) => `- [${run.name}](${run.url})`),
  ].join("\n");
}

export function hardRequireReply(path, sites, headSha) {
  return [
    FINDING_ANSWERED,
    "**pr-unblock / adjudicate-feedback: hard requires on this marketplace's plugins, resolved**",
    "",
    `At \`${headSha}\`, each \`dependencies\` entry in \`${path}\` is a bare name of another plugin \`${MARKETPLACE}\` lists, here and at the PR's base, with the same source in this repository, whose manifest, marketplace entry and files there and at the PR's base declare no hooks, servers, monitors, executables, workflows, settings or dependencies of their own, and the lane cited a line in the plugin that invokes each one with no presence gate, condition or fallback on it, outside a \`## Next\` section, in a file whose text at the PR's base already holds such a call. The security-review lane rated this flag below CRITICAL, so it is settled without a person.`,
    "",
    evidenceLine(sites),
  ].join("\n");
}

const ORDER = [
  "feedback-question-security",
  "feedback-question-intent",
  "feedback-question-design",
  "feedback-disputed-security",
  "feedback-uncertain-security",
  "feedback-disputed",
  "feedback-uncertain",
  "feedback-partial",
  "feedback-unadjudicated",
  "feedback-stood-open",
  "feedback-verifier-open",
  "",
];

const verifierNote = (comments) => comments?.[0]?.author === "verifier";

export const FINDING_STANDS_SKIP = "finding-stands";

export async function settleDisputes({ api, pr, adjudicatedSha, headSha = adjudicatedSha, posted, replies, shown, now, verdicts, ci, pushed, headMoved, resolveAfterReply, escalationReason, log }) {
  let stands = false;
  let deferred = false;
  let reason = escalationReason;
  const raise = (next) => {
    if (ORDER.indexOf(next) < ORDER.indexOf(reason)) {
      reason = next;
    }
  };
  const byThread = new Map(replies.map((reply) => [reply.thread, reply]));
  const answer = async (thread, body, resolve) => {
    try {
      const ids = shown.get(thread).comment_ids;
      const before = await api.readThread(thread);
      if (
        before.isResolved !== false ||
        before.pr !== pr ||
        before.commentIds.length !== ids.length + 1 ||
        !ids.every((id, i) => before.commentIds[i] === id) ||
        (await headMoved())
      ) {
        log(`${thread}: left as it is; it or the PR head changed after the lane's reply`);
        raise("feedback-partial");
        return "changed";
      }
      const reply = await api.replyToComment(pr, ids[0], body);
      if (reply?.in_reply_to_id !== ids[0]) {
        throw new Error(`the adjudication reply on ${thread} did not land on its thread`);
      }
      if (!resolve) {
        return "posted";
      }
      const resolved = await resolveAfterReply(api, thread, [...before.commentIds, reply.id], headMoved);
      if (!resolved) {
        log(`${thread}: answered, but the thread was left open: it or the PR head changed`);
        raise("feedback-partial");
        return "open";
      }
      return resolved === LEFT_OPEN ? LEFT_OPEN : "resolved";
    } catch (error) {
      log(`stopped adjudicating at ${thread}: ${String(error?.message ?? error).slice(0, 300)}`);
      return "failed";
    }
  };
  const closed = (outcome) => (outcome === LEFT_OPEN ? "left open for the person" : "resolved");
  for (const { thread, disposition } of posted) {
    const comments = now.get(thread)?.comments;
    if (stood(comments)) {
      if (disposition !== "VALID") {
        log(`${thread}: the finding stood at adjudication and this round left it open (${disposition})`);
        raise("feedback-stood-open");
      }
      continue;
    }
    if (!DISPUTED.includes(disposition)) {
      continue;
    }
    if (directed(comments)) {
      log(`${thread}: a trusted person directed this thread; it goes back to them, not to an adjudicator`);
      raise("feedback-disputed");
      continue;
    }
    if (verifierNote(comments)) {
      log(`${thread}: a pr-verify note left open (${disposition}); pr-verify judges the next head`);
      raise("feedback-verifier-open");
      continue;
    }
    if (listedState(comments) === "held") {
      log(`${thread}: the security-review lane held this head as CRITICAL; a listed review bot's finding on it goes to a person`);
      raise("feedback-question-security");
      continue;
    }
    if (listedState(comments) === "pending" && !isCritical(comments[0].body)) {
      log(`${thread}: the security-review lane has not reviewed this head yet; the dispute waits for the next round`);
      deferred = true;
      continue;
    }
    const path = shown.get(thread)?.path;
    if (disposition === "INCORRECT" && dependencyFlag(comments, path)) {
      let found;
      try {
        const baseSha = (await api.getPull(pr))?.base?.sha;
        found = await hardRequire({ getText: (file, ref) => api.getText(file, ref), listTree: (ref, dir) => api.listTree(ref, dir), sha: headSha, baseSha, path, evidence: byThread.get(thread)?.evidence ?? [] });
      } catch (error) {
        found = { why: `a read failed: ${String(error?.message ?? error).slice(0, 300)}` };
      }
      if (found.sites) {
        const outcome = await answer(thread, hardRequireReply(path, found.sites, headSha), true);
        if (outcome === "failed") {
          raise("feedback-partial");
          break;
        }
        if (outcome === "resolved" || outcome === LEFT_OPEN) {
          log(`${thread}: a dependencies flag on hard requires in this marketplace; ${closed(outcome)}`);
        }
        continue;
      }
      log(`${thread}: a dependencies flag hardRequire does not settle (${found.why})`);
    }
    if (!adjudicable(comments)) {
      log(`${thread}: a CRITICAL finding, a security-review finding rated ${SECURITY_PERSON_SEVERITY} or above or unrated, or a person's own thread; it goes to a person, not to an adjudicator`);
      raise(`${disposition === "INCORRECT" ? "feedback-disputed" : "feedback-uncertain"}${securityRoot(comments) ? "-security" : ""}`);
      continue;
    }
    const verdict = verdicts.get(thread);
    if (!verdict) {
      log(`${thread}: no adjudicator verdict`);
      raise("feedback-unadjudicated");
      continue;
    }
    if (verdict.verdict === "human") {
      if (verdict.question === "security" && minorSecurity(comments)) {
        log(`${thread}: the adjudicator found a security question on a finding the security-review lane rated below ${SECURITY_PERSON_SEVERITY}; left open`);
        raise("feedback-unadjudicated");
        continue;
      }
      log(`${thread}: the adjudicator found a ${verdict.question} question`);
      raise(`feedback-question-${verdict.question}`);
      continue;
    }
    if (verdict.verdict === "tests-only") {
      const runs = Array.isArray(ci?.runs) ? ci.runs : [];
      if (disposition !== "UNCERTAIN") {
        log(`${thread}: a tests-only verdict settles only an UNCERTAIN reply, not ${disposition}; left open`);
        raise("feedback-unadjudicated");
      } else if (minorSecurity(comments)) {
        log(`${thread}: a tests-only verdict does not settle a security-review finding; left open`);
        raise("feedback-unadjudicated");
      } else if (pushed) {
        log(`${thread}: tests-only, but this round pushed past ${adjudicatedSha}, whose checks were read; left open`);
        raise("feedback-unadjudicated");
      } else if (ci?.state === "red") {
        log(`${thread}: tests-only, and a covering check failed at ${adjudicatedSha}; left open for fix-ci`);
      } else if (ci?.state !== "green" || runs.length === 0) {
        log(`${thread}: tests-only, but the covering checks at ${adjudicatedSha} have not all passed; left open`);
        raise("feedback-unadjudicated");
      } else {
        const outcome = await answer(thread, testsReply(runs, adjudicatedSha), true);
        if (outcome === "failed") {
          raise("feedback-partial");
          break;
        }
        if (outcome === "resolved" || outcome === LEFT_OPEN) {
          log(`${thread}: tests-only, and every covering check passed; ${closed(outcome)}`);
        }
      }
      continue;
    }
    if (verdict.verdict === "lane" && disposition !== "INCORRECT") {
      log(`${thread}: a lane verdict settles only an INCORRECT reply, not ${disposition}; left open`);
      raise("feedback-unadjudicated");
      continue;
    }
    const outcome = await answer(thread, adjudicationReply(verdict.verdict, byThread.get(thread)?.evidence ?? [], adjudicatedSha, verdict), verdict.verdict === "lane");
    if (outcome === "failed") {
      raise("feedback-partial");
      break;
    }
    if (outcome === "resolved" || outcome === LEFT_OPEN) {
      log(`${thread}: the finding does not hold; ${closed(outcome)}`);
    } else if (outcome === "posted") {
      log(`${thread}: the finding stands`);
      stands = true;
    }
  }
  return { escalationReason: reason, skipReason: (stands || deferred) && !pushed && reason === "" ? FINDING_STANDS_SKIP : "" };
}

export async function main(argv, env, { api, readContract, log = (line) => console.log(line) } = {}) {
  const command = argv[0];
  need(env, ["GITHUB_OUTPUT", "OUT_DIR"]);
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  if (command === "prepare") {
    need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "HEAD_SHA", "THREADS_FILE", "THREADS_SHA256", "REPLIES_FILE", "REPLIES_SHA256"]);
    if (!SHA.test(env.HEAD_SHA)) {
      throw new Error("HEAD_SHA is not a commit id");
    }
    const { budgetedFetch } = await import("./request-budget.mjs");
    const client =
      api ??
      createGitHubApi({
        token: env.GITHUB_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
        fetch: budgetedFetch({ log }).fetch,
      });
    const { count, over } = await prepare({
      contract: await (readContract ?? linkedSpec)(env, log),
      threadsText: readChecked(env.THREADS_FILE, env.THREADS_SHA256, "threads.json"),
      repliesText: readChecked(env.REPLIES_FILE, env.REPLIES_SHA256, "replies.jsonl"),
      headSha: env.HEAD_SHA,
      outDir: env.OUT_DIR,
      repository: env.GITHUB_REPOSITORY,
      getText: (path, ref) => client.getText(path, ref),
    });
    output("count", String(count));
    log(`${count} disputed thread(s) to adjudicate${over.length > 0 ? `; ${over.length} past the cap of ${MAX_THREADS}` : ""}`);
    return 0;
  }
  if (command === "collect") {
    need(env, ["VERDICTS_FILE"]);
    const text = `${JSON.stringify(collect({ outDir: env.OUT_DIR }))}\n`;
    writeFileSync(env.VERDICTS_FILE, text);
    output("sha256", sha256(text));
    return 0;
  }
  throw new Error("usage: adjudicate-feedback.mjs prepare|collect");
}

runAsScript(import.meta.url, "adjudicate-feedback", () => main(process.argv.slice(2), process.env));
