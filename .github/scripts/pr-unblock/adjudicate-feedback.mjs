#!/usr/bin/env node
// adjudicate-feedback.mjs: the pr-unblock lane's adjudication of a disputed
// review finding, one an address-feedback round answered INCORRECT. A
// fresh-context model sees the finding's claim, the lane's cited evidence and
// the files at the head, never either side's reasoning, and returns a verdict
// as structured output; this file stages its input, collects its verdict, and
// applies it with no model.
//
//   prepare  run by pr-unblock.yml's adjudicate-feedback job, base code only,
//            with the job's read-only token, before any model turn: reads the
//            select job's threads.json and the scan job's replies.jsonl, each
//            checked against the SHA-256 its writer recorded, and for each
//            INCORRECT reply on an adjudicable thread no adjudication has
//            stood before and no trusted person directed (up to MAX_THREADS)
//            writes
//            <OUT_DIR>/<slot>/: finding.json (path, line, head, and the
//            claim: the review comment's first paragraph, with its severity
//            line), evidence.json (the cited path:line list, never the
//            lane's note) and files/<path>.txt, the cited files and the
//            finding's own at the head. <OUT_DIR>/index.json names each slot's
//            thread. Outputs `count`.
//   collect  run after the model steps: reads each slot's verdict.json (the
//            launcher's structured output) and writes VERDICTS_FILE, one
//            entry per indexed thread; an absent or malformed verdict is
//            null. Outputs `sha256`.
//
// settleDisputes is publish-feedback.mjs's INCORRECT branch: after the lane's
// replies are posted it applies each verdict (adjudicationReplies, fixed text
// only) and returns the round's escalation reason.

import { createHash } from "node:crypto";
import { appendFileSync, existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

import { createGitHubApi, FINDING_STANDS, need, SHA, VERIFY_NOTE_MARKER } from "./address-feedback.mjs";

// The most disputed threads one round adjudicates: pr-unblock.yml runs one
// model step per slot. A thread past it is not adjudicated, and the round
// escalates feedback-unadjudicated.
export const MAX_THREADS = 3;
export const VERDICTS = ["lane", "reviewer", "human"];
export const QUESTIONS = ["intent", "design", "security"];
// The first line of each adjudication reply the lanes App posts: this, or
// FINDING_STANDS, which the next address-feedback round reads.
export const FINDING_ANSWERED = "<!-- pr-unblock adjudicate-feedback: finding-answered -->";
const FILE_BYTES = 204800;
const CLAIM_CHARS = 2000;
// The most cited locations one slot stages: publish-feedback.mjs's
// LIMITS.evidence, which rejects a reply citing more.
const EVIDENCE_CAP = 10;
// Each staged file's suffix, so a cited CLAUDE.md, AGENTS.md or .claude/**
// file is never at a path Claude Code reads as instructions.
export const STAGED_SUFFIX = ".txt";
const PATH = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*$/;
const PATH_LINE = /^([A-Za-z0-9_@+.-]+(?:\/[A-Za-z0-9_@+.-]+)*):([1-9][0-9]{0,6})$/;
const DOT_SEGMENT = /(^|\/)\.\.?(\/|$)/;
const THREAD_ID = /^PRRT_[A-Za-z0-9_-]{1,100}$/;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");
const safePath = (path) => typeof path === "string" && PATH.test(path) && !DOT_SEGMENT.test(path);

// Whether a thread's comments, tagged as threads.json and keepThreads tag
// them, hold an adjudication that let the finding stand: the lanes App's
// comment whose first line is FINDING_STANDS.
export const stood = (comments) => (comments ?? []).some((comment) => comment.author === "lane" && firstLine(comment.body) === FINDING_STANDS);

// Whether a trusted person's direction is on the thread (threadAuthors tags
// it): their call outranks an adjudicator's, so such a thread is never
// adjudicated.
export const directed = (comments) => (comments ?? []).some((comment) => comment.direction === true);

// Whether an adjudicator may judge a dispute on the thread: only one a
// pr-verify verifier note opened, or a review comment keepThreads tagged with
// the code-review lane (a github-actions[bot] footer; claude[bot] writes its
// own body, so it names no lane). A security-review finding, and one of no
// tagged lane, always goes to a person.
export const adjudicable = (comments) => {
  const root = comments?.[0];
  return root?.author === "verifier" || (root?.author === "reviewer" && root.lane === "claude-review");
};

// The review comment's claim, without its rationale: a leading `severity:`
// line, then the first paragraph after it, cut at CLAIM_CHARS. The repro,
// the reasoning and the suggested fix in later paragraphs, and the review
// lane's footer, are left out. Leading `<!-- -->` marker lines are dropped;
// a verifier note (verify-notes.mjs) is its introduction line and the quoted
// block that holds the finding, so the claim is the whole note.
export function claimOf(body) {
  const text = String(body ?? "").replace(/\r\n/g, "\n");
  const note = firstLine(text) === VERIFY_NOTE_MARKER;
  const lines = text.split("\n");
  while (lines.length > 0 && /^<!--.*-->\s*$/.test(lines[0])) {
    lines.shift();
  }
  const paragraphs = lines
    .join("\n")
    .split(/\n[ \t]*\n/)
    .map((paragraph) => paragraph.trim())
    .filter((paragraph) => paragraph !== "" && !/^`?claude-lane: /.test(paragraph));
  let severity = null;
  if (paragraphs.length > 0 && /^severity: \S+$/i.test(paragraphs[0].split("\n")[0])) {
    const [line, ...rest] = paragraphs[0].split("\n");
    severity = line;
    if (rest.join("\n").trim() === "") {
      paragraphs.shift();
    } else {
      paragraphs[0] = rest.join("\n").trim();
    }
  }
  const claim = note ? lines.join("\n").trim() : (paragraphs[0] ?? "");
  return { severity, claim: claim.slice(0, CLAIM_CHARS) };
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

// The slots to adjudicate: each INCORRECT reply whose thread the select job
// kept, is adjudicable, no adjudication has stood and no trusted person
// directed, in reply order, one slot per thread. Returns [{thread, finding, evidence, paths}] and
// the threads past MAX_THREADS.
export function disputes(threadFile, repliesText) {
  const kept = new Map((threadFile.threads ?? []).map((thread) => [thread.id, thread]));
  const slots = [];
  const over = [];
  const seen = new Set();
  for (const line of repliesText.split("\n").filter((row) => row.trim() !== "")) {
    const reply = JSON.parse(line);
    const thread = kept.get(reply?.thread);
    if (reply?.disposition !== "INCORRECT" || !thread || !THREAD_ID.test(thread.id) || seen.has(thread.id) || !adjudicable(thread.comments) || stood(thread.comments) || directed(thread.comments)) {
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
    const root = thread.comments?.[0] ?? {};
    const paths = [...new Set([thread.path, ...evidence.map((ev) => ev.path)])].filter(safePath);
    slots.push({
      thread: thread.id,
      finding: { path: thread.path, line: thread.line ?? null, ...claimOf(root.body) },
      evidence,
      paths,
    });
  }
  return { slots, over };
}

export async function prepare({ threadsText, repliesText, headSha, outDir, getText }) {
  const threadFile = JSON.parse(threadsText);
  if (threadFile?.version !== 1 || threadFile.head_sha !== headSha) {
    throw new Error("threads.json is not the select job's thread file for this head");
  }
  const { slots, over } = disputes(threadFile, repliesText);
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
        // A path that collides with another staged one (`a` beside `a/b`)
        // is absent for this slot rather than failing the round.
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
    writeFileSync(
      join(dir, "evidence.json"),
      `${JSON.stringify(entry.evidence.map((ev) => ({ location: `${ev.path}:${ev.line}`, file: found.get(ev.path) ?? "absent" })), null, 2)}\n`,
    );
    index.push({ slot, thread: entry.thread });
  }
  writeFileSync(join(outDir, "index.json"), `${JSON.stringify({ version: 1, head_sha: headSha, slots: index, over }, null, 2)}\n`);
  return { count: index.length, over };
}

// One structured output, held to the schema's closed sets; null otherwise.
export function verdictOf(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).sort().join(",") !== "question,verdict") {
    return null;
  }
  const { verdict, question } = value;
  if (!VERDICTS.includes(verdict)) {
    return null;
  }
  if (verdict === "human" ? !QUESTIONS.includes(question) : question !== "none") {
    return null;
  }
  return { verdict, question };
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
    return { thread, ...(verdict ?? { verdict: null, question: null }) };
  });
  return { version: 1, head_sha: index.head_sha, threads };
}

// verdicts.json as the reply job reads it: thread -> {verdict, question}, for
// the head the select job read (run.json's head_sha), the code the adjudicator
// saw. Anything malformed reads as no verdicts.
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
        .map((entry) => [entry?.thread, verdictOf({ verdict: entry?.verdict, question: entry?.question })])
        .filter(([thread, verdict]) => THREAD_ID.test(thread ?? "") && verdict !== null),
    );
  } catch {
    return new Map();
  }
}

const evidenceLine = (evidence) => (evidence.length > 0 ? `Evidence: ${evidence.map((ev) => `\`${ev}\``).join(", ")}` : "Evidence: none in the checkout");

// The fixed reply for a lane or reviewer verdict; no model text.
export function adjudicationReply(verdict, evidence, headSha) {
  const seen = `A fresh-context adjudicator read the finding, the evidence below and the code at \`${headSha}\`, without either side's reasoning,`;
  return verdict === "lane"
    ? [FINDING_ANSWERED, "**pr-unblock / adjudicate-feedback: the finding does not hold, resolved**", "", `${seen} and found that the code answers the finding.`, "", evidenceLine(evidence)].join("\n")
    : [
        FINDING_STANDS,
        "**pr-unblock / adjudicate-feedback: the finding stands**",
        "",
        `${seen} and found that the finding holds. The next address-feedback round fixes it; another INCORRECT reply on this thread is not accepted and hands the pull request to a person.`,
        "",
        evidenceLine(evidence),
      ].join("\n");
}

// The round's escalation reasons, most urgent first; one round records one.
const ORDER = [
  "feedback-partial",
  "feedback-unadjudicated",
  "feedback-question-security",
  "feedback-question-intent",
  "feedback-question-design",
  "feedback-disputed",
  "feedback-uncertain",
  "",
];

// The reply job's skip reason for a round that left a finding standing with
// the PR head where the select job read it: no review run follows to start
// the round that fixes it, so feedback-dispatch.mjs's sweep dispatches that
// head again.
export const FINDING_STANDS_SKIP = "finding-stands";

// publish-feedback.mjs's INCORRECT branch, after the lane's replies posted:
// - a thread an adjudication stood before (stood) that this round left open
//   is the cap: feedback-disputed, and no second adjudication;
// - an INCORRECT thread a trusted person directed (directed) is theirs:
//   feedback-disputed, and no adjudication;
// - an INCORRECT thread that is not adjudicable (a security-review finding,
//   or one of unknown lane) goes to a person: feedback-disputed, and any
//   verdict for it is ignored;
// - an INCORRECT thread with no verdict escalates feedback-unadjudicated;
// - human: no reply, feedback-question-<intent|design|security>; a question
//   only the owner answers stays the owner's;
// - lane: the fixed reply, then the thread is resolved;
// - reviewer: the fixed FINDING_STANDS reply; when the head did not move
//   this round (`pushed` false) and nothing escalates, the round skips
//   FINDING_STANDS_SKIP.
// A thread that changed, a moved head or a failed write stops here as
// feedback-partial. Returns {escalationReason, skipReason}.
export async function settleDisputes({ api, pr, adjudicatedSha, posted, replies, shown, now, verdicts, pushed, headMoved, resolveAfterReply, escalationReason, log }) {
  let stands = false;
  let reason = escalationReason;
  const raise = (next) => {
    if (ORDER.indexOf(next) < ORDER.indexOf(reason)) {
      reason = next;
    }
  };
  const byThread = new Map(replies.map((reply) => [reply.thread, reply]));
  for (const { thread, disposition } of posted) {
    if (stood(now.get(thread)?.comments)) {
      if (disposition !== "VALID") {
        log(`${thread}: the finding stood at adjudication and this round left it open (${disposition})`);
        raise("feedback-disputed");
      }
      continue;
    }
    if (disposition !== "INCORRECT") {
      continue;
    }
    if (directed(now.get(thread)?.comments)) {
      log(`${thread}: a trusted person directed this thread; it goes back to them, not to an adjudicator`);
      raise("feedback-disputed");
      continue;
    }
    if (!adjudicable(now.get(thread)?.comments)) {
      log(`${thread}: not a code-review or verifier finding; it goes to a person, not to an adjudicator`);
      raise("feedback-disputed");
      continue;
    }
    const verdict = verdicts.get(thread);
    if (!verdict) {
      log(`${thread}: no adjudicator verdict`);
      raise("feedback-unadjudicated");
      continue;
    }
    if (verdict.verdict === "human") {
      log(`${thread}: the adjudicator found a ${verdict.question} question`);
      raise(`feedback-question-${verdict.question}`);
      continue;
    }
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
        continue;
      }
      const answer = await api.replyToComment(pr, ids[0], adjudicationReply(verdict.verdict, byThread.get(thread)?.evidence ?? [], adjudicatedSha));
      if (answer?.in_reply_to_id !== ids[0]) {
        throw new Error(`the adjudication reply on ${thread} did not land on its thread`);
      }
      if (verdict.verdict === "lane") {
        if (!(await resolveAfterReply(api, thread, [...before.commentIds, answer.id], headMoved))) {
          log(`${thread}: the finding does not hold, but the thread was left open: it or the PR head changed`);
          raise("feedback-partial");
          continue;
        }
        log(`${thread}: the finding does not hold; resolved`);
      } else {
        log(`${thread}: the finding stands`);
        stands = true;
      }
    } catch (error) {
      log(`stopped adjudicating at ${thread}: ${String(error?.message ?? error).slice(0, 300)}`);
      raise("feedback-partial");
      break;
    }
  }
  return { escalationReason: reason, skipReason: stands && !pushed && reason === "" ? FINDING_STANDS_SKIP : "" };
}

export async function main(argv, env, { api, log = (line) => console.log(line) } = {}) {
  const command = argv[0];
  need(env, ["GITHUB_OUTPUT", "OUT_DIR"]);
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  if (command === "prepare") {
    need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "HEAD_SHA", "THREADS_FILE", "THREADS_SHA256", "REPLIES_FILE", "REPLIES_SHA256"]);
    if (!SHA.test(env.HEAD_SHA)) {
      throw new Error("HEAD_SHA is not a commit id");
    }
    const client =
      api ??
      createGitHubApi({
        token: env.GITHUB_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      });
    const { count, over } = await prepare({
      threadsText: readChecked(env.THREADS_FILE, env.THREADS_SHA256, "threads.json"),
      repliesText: readChecked(env.REPLIES_FILE, env.REPLIES_SHA256, "replies.jsonl"),
      headSha: env.HEAD_SHA,
      outDir: env.OUT_DIR,
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

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::adjudicate-feedback failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
