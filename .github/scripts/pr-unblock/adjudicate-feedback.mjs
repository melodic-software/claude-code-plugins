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
//            is not in the slot's contract.json stays that question for a
//            person. Outputs `sha256`.
//
// settleDisputes is publish-feedback.mjs's DISPUTED branch: after the lane's
// replies are posted it applies each verdict (adjudicationReplies, fixed text
// only) and returns the round's escalation reason.

import { createHash } from "node:crypto";
import { appendFileSync, existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

import { createGitHubApi, FINDING_STANDS, need, SECURITY_PERSON_SEVERITY, securityNeedsPerson, SHA } from "./address-feedback.mjs";

// The most disputed threads one round adjudicates: pr-unblock.yml runs one
// model step per slot. A thread past it is not adjudicated, and the round
// escalates feedback-unadjudicated.
export const MAX_THREADS = 3;
// The dispositions that leave a thread open, each one an adjudicator judges
// on an adjudicable thread instead of a person. Only an INCORRECT reply (the
// lane asserted, with evidence, that the finding does not hold) can be
// resolved by a lane verdict; on UNCERTAIN or VALID-defer only a reviewer or
// human verdict settles it, so a model never closes a thread the lane did not
// dispute (settleDisputes).
export const DISPUTED = Object.freeze(["INCORRECT", "UNCERTAIN", "VALID-defer"]);
// What a resolveAfterReply stand-in returns when the lanes App answered a
// thread it cannot resolve (a PR it did not open): handled, and still open.
export const LEFT_OPEN = "left-open";
export const VERDICTS = ["lane", "reviewer", "human"];
export const QUESTIONS = ["intent", "design", "security"];
// The questions a quoted contract line may settle: never security, so a
// security judgment always reaches a person.
export const CONTRACT_QUESTIONS = ["intent", "design"];
// The shortest quote that settles a question, so a word or two that happens
// to appear in the issue settles nothing (judgment), and the longest kept.
export const QUOTE_MIN = 20;
const QUOTE_MAX = 2000;
const ISSUE_URL = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/[1-9][0-9]{0,9}$/;
// The first line of each adjudication reply the lanes App posts: this, or
// FINDING_STANDS, which the next address-feedback round reads.
export const FINDING_ANSWERED = "<!-- pr-unblock adjudicate-feedback: finding-answered -->";
const FILE_BYTES = 204800;
// The most cited locations one slot stages from each side: publish-feedback.mjs's
// LIMITS.evidence, which rejects a reply citing more.
const EVIDENCE_CAP = 10;
// Each staged file's suffix, so a cited CLAUDE.md, AGENTS.md or .claude/**
// file is never at a path Claude Code reads as instructions.
export const STAGED_SUFFIX = ".txt";
const PATH = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*$/;
const PATH_LINE = /^([A-Za-z0-9_@+.-]+(?:\/[A-Za-z0-9_@+.-]+)*):([1-9][0-9]{0,6})$/;
const DOT_SEGMENT = /(^|\/)\.\.?(\/|$)/;
const THREAD_ID = /^PRRT_[A-Za-z0-9_-]{1,100}$/;
// A path:line token in review prose; the path must hold a `/` or a `.`.
const PROSE_LOCATION = /(?<![\w@+./:-])((?:[\w@+.-]+\/)*[\w@+.-]+):([1-9][0-9]{0,6})(?![\w])/g;
// The security-review lane's severity line (security-review SKILL.md,
// "Reporting"), anywhere in the comment.
const CRITICAL = /^[ \t]*severity:[ \t]*critical[ \t]*$/im;
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

// Whether an adjudicator may judge a dispute on the thread: a review comment
// that carries no `severity: CRITICAL` line and that keepThreads tagged with
// the code-review lane (a github-actions[bot] footer; claude[bot] writes its
// own body, so it names no lane), with the security-review lane and a rating
// below the one a person decides (securityNeedsPerson), or as a listed review
// bot's (from its account id) whose `security` state is clear: the
// security-review lane reviewed the head the bot reviewed and holds nothing
// there or since. The bot's own severity badge decides nothing. A listed
// bot's finding the lane held goes to a person (feedback-question-security);
// one the lane has not reviewed yet waits for the next round
// (settleDisputes). A CRITICAL finding, a security-review finding a person
// decides, one of no tagged lane, and a pr-verify verifier note (resolving it
// leaves the verifier's FAIL holding the merge, and pr-verify judges each
// head once) always go to a person.
const listedState = (comments) => (comments?.[0]?.listed === true ? comments[0].security ?? "pending" : null);
// Whether the thread's root is a security-review lane finding rated below the
// one a person decides.
const minorSecurity = (comments) => comments?.[0]?.lane === "claude-security-review" && !securityNeedsPerson(comments[0].body);
export const adjudicable = (comments) => {
  const root = comments?.[0];
  if (root?.author !== "reviewer" || CRITICAL.test(String(root.body ?? ""))) {
    return false;
  }
  return root.listed === true ? listedState(comments) === "clear" : root.lane === "claude-review" || minorSecurity(comments);
};

// The locations a review comment cites: path:line tokens in its prose and
// line-numbered permalinks into `repository`, each safe path:line once, at
// most EVIDENCE_CAP.
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

// The slots to adjudicate: each DISPUTED reply whose thread the select job
// kept, is adjudicable, no adjudication has stood and no trusted person
// directed, in reply order, one slot per thread. Returns [{thread, finding,
// evidence, cited, paths}] and the threads past MAX_THREADS.
export function disputes(threadFile, repliesText, repository = "") {
  const kept = new Map((threadFile.threads ?? []).map((thread) => [thread.id, thread]));
  const slots = [];
  const over = [];
  const seen = new Set();
  for (const line of repliesText.split("\n").filter((row) => row.trim() !== "")) {
    const reply = JSON.parse(line);
    const thread = kept.get(reply?.thread);
    if (!DISPUTED.includes(reply?.disposition) || !thread || !THREAD_ID.test(thread.id) || seen.has(thread.id) || !adjudicable(thread.comments) || stood(thread.comments) || directed(thread.comments)) {
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
    const locations = (list) => `${JSON.stringify(list.map((ev) => ({ location: `${ev.path}:${ev.line}`, file: found.get(ev.path) ?? "absent" })), null, 2)}\n`;
    writeFileSync(join(dir, "evidence.json"), locations(entry.evidence));
    writeFileSync(join(dir, "review-evidence.json"), locations(entry.cited));
    writeFileSync(join(dir, "contract.json"), `${JSON.stringify({ issues: contractIssues(contract, repository) }, null, 2)}\n`);
    index.push({ slot, thread: entry.thread });
  }
  writeFileSync(join(outDir, "index.json"), `${JSON.stringify({ version: 1, head_sha: headSha, slots: index, over }, null, 2)}\n`);
  return { count: index.length, over };
}

// The linked issues' spec text as contract.json stages it: each issue's URL,
// its body when trusted people wrote it, and its trusted comments, all as
// resolve-pr.mjs linkedIssues returns them (`specText`).
export function contractIssues(specText, repository) {
  return (Array.isArray(specText) ? specText : [])
    .filter((issue) => Number.isSafeInteger(issue?.number) && issue.number > 0)
    .map((issue) => ({
      number: issue.number,
      url: `https://github.com/${repository}/issues/${issue.number}`,
      body: typeof issue.body === "string" ? issue.body : null,
      comments: (Array.isArray(issue.comments) ? issue.comments : []).filter((comment) => typeof comment === "string"),
    }));
}

// The URL of the staged issue whose text holds `quote` exactly, or null.
export function quoteSource(quote, issues) {
  if (typeof quote !== "string" || quote.trim().length < QUOTE_MIN) {
    return null;
  }
  const issue = (Array.isArray(issues) ? issues : []).find((entry) =>
    [entry?.body, ...(Array.isArray(entry?.comments) ? entry.comments : [])].some((text) => typeof text === "string" && text.includes(quote)),
  );
  return typeof issue?.url === "string" && ISSUE_URL.test(issue.url) ? issue.url : null;
}

// One structured output, held to the schema's closed sets; null otherwise.
// A lane or reviewer verdict on an intent or design question must carry a
// quote, the contract line that settles it; any other verdict's quote is
// dropped.
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
  return CONTRACT_QUESTIONS.includes(question) && quote.trim() !== "" ? { verdict, question, quote } : null;
}

// A verdict that settles a question by quote, checked against the staged
// issues: kept with the quote's issue URL when the quote is in them, else
// the question goes to a person, as with no quote.
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
        .map((entry) => {
          const verdict = verdictOf({ verdict: entry?.verdict, question: entry?.question, ...(entry?.quote === undefined ? {} : { quote: entry.quote }) });
          // A settling quote counts only with the issue URL collect found it in.
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

// The contract lines that settled a question: the quote, checked to be the
// linked issue's own text, each line quoted, and the issue it is in. An HTML
// comment opener is escaped so no quoted line reads as a marker.
const contractLines = (settled) =>
  settled?.quote === undefined
    ? []
    : [
        "",
        `The linked issue settles this ${settled.question} question (${settled.url}):`,
        "",
        ...settled.quote.split("\n").map((line) => `> ${line.replace(/\r$/, "").replaceAll("<!--", "&lt;!--")}`),
      ];

// The fixed reply for a lane or reviewer verdict; no model text but a quote
// of the linked issue's own text (`settled`, a verdict checkQuote kept).
export function adjudicationReply(verdict, evidence, headSha, settled) {
  const seen = `A fresh-context adjudicator read the review comment, the locations both sides cited and the code at \`${headSha}\`, without the fixing lane's reasoning,`;
  return verdict === "lane"
    ? [FINDING_ANSWERED, "**pr-unblock / adjudicate-feedback: the finding does not hold, resolved**", "", `${seen} and found that the code answers the finding.`, ...contractLines(settled), "", evidenceLine(evidence)].join("\n")
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

// The round's escalation reasons, most urgent first; one round records one.
// A reason escalation-routes.json holds for a person outranks every reason it
// routes to a failing status, so a question for a person is never lost.
const ORDER = [
  "feedback-question-security",
  "feedback-question-intent",
  "feedback-question-design",
  "feedback-disputed",
  "feedback-uncertain",
  "feedback-partial",
  "feedback-unadjudicated",
  "feedback-stood-open",
  "feedback-verifier-open",
  "",
];

// Whether a thread is a pr-verify verifier note (threadAuthors tags it).
const verifierNote = (comments) => comments?.[0]?.author === "verifier";

// The reply job's skip reason for a round that left a finding standing, or a
// listed bot's dispute waiting on the security-review lane, with the PR head
// where the select job read it: no review run may follow to start
// the round that fixes it, so feedback-dispatch.mjs's sweep dispatches that
// head again.
export const FINDING_STANDS_SKIP = "finding-stands";

// publish-feedback.mjs's DISPUTED branch, after the lane's replies posted:
// - a thread an adjudication stood before (stood) that this round left open
//   is the cap: feedback-stood-open, and no second adjudication;
// - a DISPUTED thread a trusted person directed (directed) is theirs:
//   feedback-disputed, and no adjudication;
// - a DISPUTED pr-verify verifier note: feedback-verifier-open (pr-verify's
//   own FAIL holds the merge, and it judges the next head afresh);
// - a DISPUTED listed review bot's finding the security-review lane held as
//   CRITICAL: feedback-question-security; one whose head the lane has not
//   reviewed yet is deferred: no verdict, no escalation, and the round skips
//   FINDING_STANDS_SKIP as below so the sweep dispatches the head again;
// - any other DISPUTED thread that is not adjudicable (a CRITICAL finding, a
//   security-review finding rated at or above SECURITY_PERSON_SEVERITY or
//   with no readable rating, or one of unknown lane) goes to a person:
//   feedback-disputed when the reply is INCORRECT, else feedback-uncertain,
//   and any verdict for it is ignored;
// - a DISPUTED thread with no verdict escalates feedback-unadjudicated;
// - human: no reply, feedback-question-<intent|design|security>; a question
//   only the owner answers stays the owner's, except a security question on
//   a security-review finding rated below SECURITY_PERSON_SEVERITY, which is
//   feedback-unadjudicated;
// - lane: on an INCORRECT reply, the fixed reply, then the thread is
//   resolved (left open, as LEFT_OPEN, where the lanes App cannot resolve
//   it); on an UNCERTAIN or VALID-defer reply (the lane could not tell,
//   or agreed the finding holds) no reply, the thread stays open (the
//   ruleset's thread resolution still holds the merge), and
//   feedback-unadjudicated;
// - reviewer: the fixed FINDING_STANDS reply, which the next round reads as
//   a finding to fix; when the head did not move this round (`pushed`
//   false) and nothing escalates, the round skips FINDING_STANDS_SKIP.
// A thread that changed, a moved head or a failed write stops here as
// feedback-partial. Returns {escalationReason, skipReason}.
export async function settleDisputes({ api, pr, adjudicatedSha, posted, replies, shown, now, verdicts, pushed, headMoved, resolveAfterReply, escalationReason, log }) {
  let stands = false;
  // A listed bot's dispute the security-review lane has not rated yet: like a
  // finding that stood, it is left for the next round at this head.
  let deferred = false;
  let reason = escalationReason;
  const raise = (next) => {
    if (ORDER.indexOf(next) < ORDER.indexOf(reason)) {
      reason = next;
    }
  };
  const byThread = new Map(replies.map((reply) => [reply.thread, reply]));
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
    if (listedState(comments) === "pending" && !CRITICAL.test(String(comments[0].body ?? ""))) {
      log(`${thread}: the security-review lane has not reviewed this head yet; the dispute waits for the next round`);
      deferred = true;
      continue;
    }
    if (!adjudicable(comments)) {
      log(`${thread}: not a non-CRITICAL code-review finding or a security-review finding rated below ${SECURITY_PERSON_SEVERITY}; it goes to a person, not to an adjudicator`);
      raise(disposition === "INCORRECT" ? "feedback-disputed" : "feedback-uncertain");
      continue;
    }
    const verdict = verdicts.get(thread);
    if (!verdict) {
      log(`${thread}: no adjudicator verdict`);
      raise("feedback-unadjudicated");
      continue;
    }
    if (verdict.verdict === "human") {
      // The security-review lane rated this finding below the one a person
      // decides, so a security question on it ends the lane in a failing
      // status, not with a person.
      if (verdict.question === "security" && minorSecurity(comments)) {
        log(`${thread}: the adjudicator found a security question on a finding the security-review lane rated below ${SECURITY_PERSON_SEVERITY}; left open`);
        raise("feedback-unadjudicated");
        continue;
      }
      log(`${thread}: the adjudicator found a ${verdict.question} question`);
      raise(`feedback-question-${verdict.question}`);
      continue;
    }
    // Only an INCORRECT reply is the lane disputing the finding with
    // evidence. On UNCERTAIN or VALID-defer a lane verdict alone would let one
    // model turn close a finding no one disputed, so the thread stays open.
    if (verdict.verdict === "lane" && disposition !== "INCORRECT") {
      log(`${thread}: a lane verdict settles only an INCORRECT reply, not ${disposition}; left open`);
      raise("feedback-unadjudicated");
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
      const answer = await api.replyToComment(pr, ids[0], adjudicationReply(verdict.verdict, byThread.get(thread)?.evidence ?? [], adjudicatedSha, verdict));
      if (answer?.in_reply_to_id !== ids[0]) {
        throw new Error(`the adjudication reply on ${thread} did not land on its thread`);
      }
      if (verdict.verdict === "lane") {
        const resolved = await resolveAfterReply(api, thread, [...before.commentIds, answer.id], headMoved);
        if (!resolved) {
          log(`${thread}: the finding does not hold, but the thread was left open: it or the PR head changed`);
          raise("feedback-partial");
          continue;
        }
        log(`${thread}: the finding does not hold; ${resolved === LEFT_OPEN ? "left open for the person" : "resolved"}`);
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
  return { escalationReason: reason, skipReason: (stands || deferred) && !pushed && reason === "" ? FINDING_STANDS_SKIP : "" };
}

// The linked issues' spec text trusted people wrote, as pr-verify reads it
// (resolve-pr.mjs linkedIssues): [] when PR_NUMBER is unset or the read
// fails, so no quote can settle a question and it stays a person's. Loaded
// here, from the full base checkout, for the reason request-budget.mjs is.
async function linkedSpec(env, log) {
  if (!/^[1-9][0-9]*$/.test(env.PR_NUMBER ?? "")) {
    return [];
  }
  try {
    const { linkedIssues } = await import("../pr-verify/resolve-pr.mjs");
    const { createGitHub, loadTrustedList } = await import("../../actions/check-trusted-trigger/check-trusted-trigger.mjs");
    const { loadRules } = await import("../intake-triage/admit.mjs");
    const trusted = loadTrustedList(env.TRUSTED_ACTORS_PATH || ".base/.github/standards/trusted-actors/trusted-actors.json");
    const api = (keepGraphQLErrors) => createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, keepGraphQLErrors });
    const identity = String(env.LANE_IDENTITY ?? "").trim().toLowerCase().replace(/\[bot\]$/, "");
    const taskList = loadRules(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url).pathname)["task-list"];
    const { specText } = await linkedIssues(api(false), api(true), env.GITHUB_REPOSITORY, Number(env.PR_NUMBER), trusted.humans, identity ? trusted.logins.get(`${identity}[bot]`) : undefined, taskList);
    return specText;
  } catch (error) {
    log(`::warning::cannot read the linked issues' spec text (${String(error?.message ?? error).slice(0, 300)}); no question settles by quote this round`);
    return [];
  }
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
    // Each read's rate-limit headers go to the job-end api-budget notice.
    // request-budget.mjs reaches into .github/actions, so it loads here, from
    // the full base checkout prepare runs in: publish-feedback.mjs imports this
    // module from a copy of this directory alone.
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
