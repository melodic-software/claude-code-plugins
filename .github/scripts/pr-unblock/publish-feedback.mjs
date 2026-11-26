#!/usr/bin/env node
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, lstatSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { runAsScript } from "../lib/run-main.mjs";
import {
  answeredIds,
  answeredLine,
  BAD_CHARS,
  COMMENT_ITEM_ID,
  BODY_LIMITS,
  bodySections,
  countRounds,
  createGitHubApi,
  FORBIDDEN,
  gateLines,
  sectionRefusal,
  currentThreads,
  isRoundMarker,
  DEFAULT_MAX_ROUNDS,
  laneReader,
  FRESH_FIXER_ROUNDS,
  roundLine,
  maxRoundsFrom,
  need,
  positive,
  reviewerIdFrom,
  reviewerIdsFrom,
  ROUND_MARKER,
  scanRefusal,
  SHA,
  staleVerifyNotes,
  trustedHumansFrom,
  withLaneBinding,
} from "./address-feedback.mjs";
import { DISPUTED, FINDING_ANSWERED, LEFT_OPEN, parseVerdicts, settleDisputes } from "./adjudicate-feedback.mjs";
import { inThreadScope, NOTE_ID, THREAD_ID, threadsNamed } from "./thread-scope.mjs";
import { stopSkip } from "./escalation-routes.mjs";

export const LIMITS = { bytes: 49152, runBytes: 1048576, note: 2000, evidence: 10 };
const WEB_FLOW_ID = 19864447;
export const FIX_TRAILER = "Lane-Activity: pr-unblock/address-feedback";
const PATH_LINE = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*:[1-9][0-9]{0,6}$/;
const DOT_SEGMENT = /(^|\/)\.\.?(\/|:)/;
export const FOLLOW_UP = "follow-up";
const DISPOSITIONS = ["VALID", "INCORRECT", "UNCERTAIN", "VALID-defer", FOLLOW_UP];
const RESOLVING = new Set(["VALID", FOLLOW_UP]);
export const ALREADY_ADDRESSED = "already-addressed";
const NOTE_DISPOSITIONS = ["VALID", ALREADY_ADDRESSED];
export const ANSWERED = "answered";
const KEYS = ["disposition", "evidence", "fix_sha", "note", "thread"];
const LABELS = {
  VALID: "VALID, fixed",
  INCORRECT: "INCORRECT, left open",
  UNCERTAIN: "UNCERTAIN, left open",
  "VALID-defer": "VALID (defer), left open",
  [FOLLOW_UP]: "outside the closing issue's scope, a follow-up",
};
const FOLLOW_UP_LINE = "This advisory asks for a change outside the closing issue's scope, so this pull request leaves it out and records it under `## Follow-ups` in the pull request body.";
const FOLLOW_UPS_HEADING = /^## Follow-ups[ \t]*$/;
const FOLLOW_UP_TEXT_CAP = 200;
const FOLLOW_UP_MARKER = "Pre-existing (advisory):";

export function followUpBullet(advisory, link) {
  const first = String(advisory ?? "")
    .split(/\r?\n/)
    .map((row) => row.trim())
    .find((row) => row !== "");
  let stripped = (first ?? "").replace(/`/g, "'");
  for (let prev; prev !== stripped; ) {
    prev = stripped;
    stripped = stripped.replace(/<!--|-->/g, "");
  }
  const text = [...stripped].slice(0, FOLLOW_UP_TEXT_CAP).join("") || "advisory";
  return `- ${FOLLOW_UP_MARKER} \`${text}\` ([thread](${link}))`;
}

export function withFollowUp(body, bullet, link) {
  const text = String(body ?? "");
  if (text.includes(link)) {
    return text;
  }
  const eol = text.includes("\r\n") ? "\r\n" : "\n";
  const rows = text.split(/\r?\n/);
  const start = rows.findIndex((row) => FOLLOW_UPS_HEADING.test(row));
  if (start === -1) {
    const kept = text.replace(/\s+$/, "");
    return [...(kept ? [kept, ""] : []), "## Follow-ups", "", bullet].join(eol) + eol;
  }
  const next = rows.findIndex((row, i) => i > start && /^#{1,2} /.test(row));
  let at = next === -1 ? rows.length : next;
  while (at > start + 1 && rows[at - 1].trim() === "") {
    at -= 1;
  }
  rows.splice(at, 0, ...(at === start + 1 ? ["", bullet] : [bullet]));
  return rows.join(eol);
}

async function recordFollowUp(api, pr, comment) {
  const link = comment?.html_url;
  if (typeof link !== "string" || !link.startsWith("https://github.com/")) {
    throw new Error(`root comment ${comment?.id} has no link to record under ## Follow-ups`);
  }
  const body = (await api.getPull(pr))?.body ?? "";
  const next = withFollowUp(body, followUpBullet(comment.body, link), link);
  if (next !== body) {
    await api.updatePullBody(pr, next);
  }
}

export function takeBodyRecord(text) {
  const kept = [];
  const records = [];
  for (const line of text.split("\n")) {
    let value;
    try {
      value = JSON.parse(line);
    } catch {
      value = null;
    }
    if (value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).join() === "body_sections") {
      records.push({ line, sections: value.body_sections });
    } else {
      kept.push(line);
    }
  }
  const replyText = kept.join("\n");
  if (records.length === 0) {
    return { replyText, record: null };
  }
  const [{ line, sections }] = records;
  const wellFormed =
    records.length === 1 &&
    Buffer.byteLength(line) <= BODY_LIMITS.record &&
    Array.isArray(sections) &&
    sections.length > 0 &&
    sections.length <= BODY_LIMITS.sections &&
    sections.every((section) => section !== null && typeof section === "object" && Object.keys(section).sort().join() === "heading,text" && typeof section.heading === "string" && typeof section.text === "string") &&
    new Set(sections.map((section) => section.heading)).size === sections.length;
  return { replyText, record: wellFormed ? { sections } : { refusal: "the body record is malformed" } };
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

export function refreshedBody(body, sections, offered = []) {
  const text = String(body ?? "");
  const { rows, sections: found } = bodySections(text);
  const hashes = new Map(offered.map(({ heading, sha256: hash }) => [heading, hash]));
  const edits = [];
  for (const { heading, text: next } of sections) {
    const matches = found.filter((section) => section.heading === heading);
    if (!hashes.has(heading) || matches.length !== 1 || matches[0].end >= rows.length) {
      return { refusal: "it names a section the select job did not offer" };
    }
    if (sha256(matches[0].text) !== hashes.get(heading)) {
      return { refusal: "a section changed since the select job read it" };
    }
    const why = sectionRefusal(next);
    if (why !== null) {
      return { refusal: `the text holds ${why}` };
    }
    edits.push({ ...matches[0], next });
  }
  for (const { start, end, next } of edits.sort((a, b) => b.start - a.start)) {
    const eol = rows[start].endsWith("\r") ? "\r" : "";
    rows.splice(start + 1, end - start - 1, ...["", ...next.trim().split("\n"), ""].map((row) => row + eol));
  }
  const result = rows.join("\n");
  if (gateLines(text).join("\n") !== gateLines(result).join("\n")) {
    return { refusal: "it would change a line a gate reads" };
  }
  return { body: result };
}

async function refreshBody({ api, pr, headMoved, body, log }) {
  if (body?.record == null) {
    return null;
  }
  const dropped = (why) => {
    log(`the body refresh is dropped: ${why}`);
    return `The body refresh was dropped: ${why}.`;
  };
  if (body.record.refusal) {
    return dropped(body.record.refusal);
  }
  if (!body.offered) {
    return dropped("the select job offered no body section");
  }
  if (!body.fixed) {
    log("no fix landed this round, so the body is left as it is");
    return null;
  }
  try {
    if (await headMoved()) {
      return dropped("the PR head moved");
    }
    const current = (await api.getPull(pr))?.body ?? "";
    const next = refreshedBody(current, body.record.sections, body.offered);
    if (next.refusal) {
      return dropped(next.refusal);
    }
    if (next.body !== current) {
      await api.updatePullBody(pr, next.body);
    }
    log(`refreshed ${body.record.sections.length} body section(s)`);
    return null;
  } catch (error) {
    log(`could not refresh the body: ${String(error?.message ?? error).slice(0, 300)}`);
    return "The body refresh was dropped: the body could not be read or written.";
  }
}

const RESOLVING_FIRST_LINES = new Set([...[...RESOLVING].map((disposition) => `**pr-unblock / address-feedback: ${LABELS[disposition]}**`), FINDING_ANSWERED]);
export const isResolvingAnswer = (body) => RESOLVING_FIRST_LINES.has(String(body ?? "").split("\n")[0].replace(/\r$/, ""));

class Invalid extends Error {}

function check(condition, why) {
  if (!condition) {
    throw new Invalid(why);
  }
}

const sameIds = (a, b) => a.length === b.length && a.every((id, i) => id === b[i]);

const citation = (ev) => [ev.slice(0, ev.lastIndexOf(":")), Number(ev.slice(ev.lastIndexOf(":") + 1))];

const CI_RUN_URL = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/actions\/runs\/[1-9][0-9]{0,19}\/job\/[1-9][0-9]{0,19}$/;
const CI_RUN_NAME = /^[A-Za-z0-9_.-]+(?: [A-Za-z0-9_.-]+)*( \([0-9]{1,3}\))?$/;
const ciValid = (ci) =>
  ci !== null &&
  typeof ci === "object" &&
  Object.keys(ci).sort().join(",") === "runs,state" &&
  ["green", "red", "unsettled"].includes(ci.state) &&
  Array.isArray(ci.runs) &&
  ci.runs.length <= 100 &&
  ci.runs.every((run) => run !== null && typeof run === "object" && Object.keys(run).sort().join(",") === "name,url" && CI_RUN_NAME.test(String(run.name)) && CI_RUN_URL.test(String(run.url)));

export function parseRun(text) {
  let run;
  try {
    run = JSON.parse(text);
  } catch {
    throw new Invalid("run.json does not parse");
  }
  check(
    run?.version === 1 &&
      SHA.test(run.head_sha ?? "") &&
      Array.isArray(run.threads) &&
      [run.pr_paths, run.copy_paths].every((paths) => paths === undefined || (Array.isArray(paths) && paths.every((path) => typeof path === "string"))),
    "run.json is malformed",
  );
  check(
    run.stale_notes === undefined ||
      (Array.isArray(run.stale_notes) && run.stale_notes.length > 0 && run.threads.length === 0 && run.stale_notes.every((id) => THREAD_ID.test(String(id)))),
    "run.json holds a malformed stale_notes list",
  );
  check(run.superseded_head === undefined || (run.stale_notes !== undefined && SHA.test(String(run.superseded_head))), "run.json holds a malformed superseded_head");
  check(
    run.verify_notes === undefined ||
      (Array.isArray(run.verify_notes) &&
        run.verify_notes.length > 0 &&
        run.threads.length === 0 &&
        run.stale_notes === undefined &&
        new Set(run.verify_notes.map((note) => note?.id)).size === run.verify_notes.length &&
        run.verify_notes.every((note) => NOTE_ID.test(String(note?.id)) && SHA.test(String(note.head)) && typeof note.path === "string" && note.path !== "")),
    "run.json holds a malformed verify_notes list",
  );
  check(
    run.reviewed_heads === undefined || (Array.isArray(run.reviewed_heads) && run.reviewed_heads.every((sha) => SHA.test(String(sha)))),
    "run.json holds a malformed reviewed_heads list",
  );
  check(run.ci === undefined || ciValid(run.ci), "run.json holds a malformed ci snapshot");
  check(
    run.body_sections === undefined ||
      (Array.isArray(run.body_sections) &&
        run.body_sections.length <= BODY_LIMITS.sections &&
        run.body_sections.every((section) => typeof section?.heading === "string" && /^[0-9a-f]{64}$/.test(String(section.sha256)))),
    "run.json holds a malformed body_sections list",
  );
  check(
    run.pr_comments === undefined ||
      (Array.isArray(run.pr_comments) &&
        run.pr_comments.length > 0 &&
        run.verify_notes === undefined &&
        run.stale_notes === undefined &&
        new Set(run.pr_comments.map((item) => item?.id)).size === run.pr_comments.length &&
        run.pr_comments.every((item) => COMMENT_ITEM_ID.test(String(item?.id)) && item.id === `PRC_${item.comment_id}` && Number.isSafeInteger(item.comment_id) && typeof item.updated_at === "string")),
    "run.json holds a malformed pr_comments list",
  );
  for (const thread of run.threads) {
    check(
      THREAD_ID.test(thread?.id ?? "") &&
        typeof thread.path === "string" &&
        Array.isArray(thread.comment_ids) &&
        thread.comment_ids.length > 0 &&
        thread.comment_ids.every((id) => Number.isSafeInteger(id) && id > 0) &&
        (thread.named_paths === undefined ||
          (Array.isArray(thread.named_paths) && thread.named_paths.every((path) => typeof path === "string"))) &&
        (thread.may_follow_up === undefined || thread.may_follow_up === true),
      "run.json holds a malformed thread",
    );
  }
  return run;
}

export function parseReplies(text, run, fileExists) {
  check(Buffer.byteLength(text) <= LIMITS.bytes, "the replies are over the size limit");
  const kept = new Map(run.threads.map((thread) => [thread.id, thread]));
  const notes = new Set((run.verify_notes ?? []).map((note) => note.id));
  const asks = new Set((run.pr_comments ?? []).map((item) => item.id));
  const seen = new Set();
  const replies = [];
  for (const line of text.split("\n").filter((row) => row !== "")) {
    let reply;
    try {
      reply = JSON.parse(line);
    } catch {
      throw new Invalid("a reply line does not parse");
    }
    check(reply !== null && typeof reply === "object" && !Array.isArray(reply), "a reply is not an object");
    check(Object.keys(reply).sort().join() === KEYS.join(), "a reply's fields are not the template's");
    const { thread, disposition, evidence, fix_sha: fixSha, note } = reply;
    check(typeof thread === "string" && (kept.has(thread) || notes.has(thread) || asks.has(thread)), "a reply names a thread the runner did not keep");
    check(!seen.has(thread), "two replies name one thread");
    seen.add(thread);
    if (asks.has(thread)) {
      check(disposition === ANSWERED, "a comment's reply is not answered");
    } else if (notes.has(thread)) {
      check(NOTE_DISPOSITIONS.includes(disposition), "a pr-verify note's reply is not VALID or already-addressed");
    } else {
      check(DISPOSITIONS.includes(disposition), "a reply's disposition is not one the template allows");
      check(disposition !== FOLLOW_UP || kept.get(thread).may_follow_up === true, "a follow-up reply names a thread that is no advisory finding with a closing issue's scope");
    }
    check(
      Array.isArray(evidence) &&
        evidence.length <= LIMITS.evidence &&
        evidence.every((ev) => typeof ev === "string" && PATH_LINE.test(ev) && !DOT_SEGMENT.test(ev)),
      "a reply's evidence is not a list of path:line",
    );
    check(!["VALID", "INCORRECT", ALREADY_ADDRESSED].includes(disposition) || evidence.length > 0, "a VALID, INCORRECT or already-addressed reply cites no evidence");
    check(
      evidence.every((ev) => fileExists(citation(ev)[0])),
      "a reply's evidence names a file not in the checkout",
    );
    check(fixSha === "", "a reply's fix_sha is not empty");
    check(
      typeof note === "string" && note.length > 0 && [...note].length <= LIMITS.note && !BAD_CHARS.test(note) && !FORBIDDEN.test(note),
      "a reply's note is empty, too long, or holds a control character, an HTML comment or a token",
    );
    replies.push({ thread, disposition, evidence, fixSha, note });
  }
  return replies;
}

export function renderReply({ disposition, evidence, fixSha, note }) {
  const fence = "`".repeat(Math.max(3, ...[...note.matchAll(/`+/g)].map((run) => run[0].length + 1)));
  return [
    `**pr-unblock / address-feedback: ${LABELS[disposition]}**`,
    "",
    evidence.length > 0 ? `Evidence: ${evidence.map((ev) => `\`${ev}\``).join(", ")}` : "Evidence: none in the checkout",
    ...(fixSha ? [`Fix: ${fixSha}`] : []),
    ...(disposition === FOLLOW_UP ? ["", FOLLOW_UP_LINE] : []),
    "",
    `${fence}text`,
    note,
    fence,
  ].join("\n");
}

export function renderAnswer({ evidence, note }, commentId, link) {
  const fence = "`".repeat(Math.max(3, ...[...note.matchAll(/`+/g)].map((run) => run[0].length + 1)));
  const asked = /^https:\/\/github\.com\/[^\s()]+$/.test(String(link ?? "")) ? `[this comment](${link})` : `comment ${commentId}`;
  return [
    answeredLine(commentId),
    `**pr-unblock / address-feedback: an answer to ${asked}**`,
    "",
    evidence.length > 0 ? `Evidence: ${evidence.map((ev) => `\`${ev}\``).join(", ")}` : "Evidence: none in the checkout",
    "",
    `${fence}text`,
    note,
    fence,
  ].join("\n");
}

async function answerComments({ api, pr, appId, asks, answers, headMoved, log }) {
  const posted = [];
  if (answers.length === 0) {
    return { posted, stopped: "" };
  }
  const comments = await api.listIssueComments(pr);
  const byId = new Map(comments.map((comment) => [comment.id, comment]));
  const answered = answeredIds(comments, appId);
  for (const answer of answers) {
    const { comment_id: commentId, updated_at: seenAt } = asks.get(answer.thread);
    const asked = byId.get(commentId);
    try {
      if (answered.has(String(commentId))) {
        log(`skipped ${answer.thread}: the lanes App already answered it`);
        continue;
      }
      if (!asked || asked.updated_at !== seenAt) {
        log(`skipped ${answer.thread}: it changed since the model job read it`);
        continue;
      }
      if (await headMoved()) {
        log(`stopped at ${answer.thread}: the PR head moved`);
        return { posted, stopped: "feedback-partial" };
      }
      await api.createIssueComment(pr, renderAnswer(answer, commentId, asked.html_url));
    } catch (error) {
      log(`stopped at ${answer.thread}: ${String(error?.message ?? error).slice(0, 300)}`);
      return { posted, stopped: "feedback-partial" };
    }
    posted.push({ thread: answer.thread, disposition: ANSWERED });
    log(`answered ${answer.thread}`);
  }
  return { posted, stopped: "" };
}

const SKILL_FILE = /^((?:.*\/)?skills\/[^/]+\/)SKILL\.md$/;

export function lineChanged(patch, line) {
  for (const [, start, count] of String(patch ?? "").matchAll(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/gm)) {
    const first = Number(start);
    const size = count === undefined ? 1 : Number(count);
    if (line >= first && line < first + size) {
      return true;
    }
  }
  return false;
}

function citedFiles(evidence, patches, thread, prPaths = new Set(), copyPaths = new Set()) {
  return new Set(
    evidence
      .map(citation)
      .filter(([path, line]) => (prPaths.has(path) || inThreadScope(path, new Set([thread.path]), [thread], { prPaths, copyPaths })) && lineChanged(patches.get(path), line))
      .map(([path]) => path),
  );
}

function touchesThread(changed, thread, cited) {
  if (changed.some((file) => file === thread.path || cited.has(file))) {
    return true;
  }
  const skillDir = SKILL_FILE.exec(thread.path)?.[1];
  return skillDir !== undefined && changed.some((file) => file.startsWith(skillDir));
}

const isLaneFix = (commit, appId) =>
  commit.author?.id === appId &&
  commit.committer?.id === WEB_FLOW_ID &&
  commit.commit?.verification?.verified === true &&
  commit.commit.verification.reason === "valid" &&
  String(commit.commit?.message ?? "")
    .split("\n")
    .some((line) => line.replace(/\r$/, "") === FIX_TRAILER);

export async function earlierFixOf({ commits, appId, after, thread, evidence, claimed, filesOf }) {
  const cites = evidence.map(citation);
  for (let i = commits.length - 1; i >= 0; i -= 1) {
    const commit = commits[i];
    if (
      !isLaneFix(commit, appId) ||
      !threadsNamed(commit.commit.message).has(thread.id) ||
      claimed.has(commit.sha) ||
      !(Date.parse(commit.commit?.committer?.date ?? "") > after)
    ) {
      continue;
    }
    const later = new Set();
    for (const next of commits.slice(i + 1)) {
      for (const file of await filesOf(next.sha)) {
        later.add(file.filename);
      }
    }
    const current = (await filesOf(commit.sha)).filter((file) => !later.has(file.filename));
    const patches = new Map(current.map((file) => [file.filename, file.patch]));
    if (!touchesThread([...patches.keys()], thread, citedFiles(evidence, patches, thread))) {
      continue;
    }
    if (cites.some(([path, line]) => patches.has(path) && lineChanged(patches.get(path), line))) {
      return commit.sha;
    }
  }
  return null;
}

const claimedFixes = (reviewComments, appId) =>
  new Set(
    reviewComments
      .filter((comment) => comment.user?.id === appId)
      .flatMap((comment) => [...String(comment.body ?? "").matchAll(/^Fix: ([0-9a-f]{40})$/gm)].map((match) => match[1])),
  );

async function fixesLanded({ api, pr, run, headSha, replies, appId, judgedAt, patchWritten, claimed = new Set() }) {
  const valid = replies.filter((reply) => reply.disposition === "VALID");
  const landed = new Map();
  if (valid.length === 0 && run.head_sha === headSha) {
    return landed;
  }
  const comparison = await api.compareWhole(run.head_sha, headSha);
  const fixes = valid.length === 0 ? [] : (comparison.commits ?? []).filter((commit) => isLaneFix(commit, appId));
  const fixSha = fixes.length === 1 ? fixes[0].sha : "";
  const threadOf = new Map(run.threads.map((thread) => [thread.id, thread]));
  const paths = new Set(run.threads.map((thread) => thread.path));
  const prPaths = new Set(run.pr_paths ?? []);
  const copyPaths = new Set(run.copy_paths ?? []);
  const files = comparison.files ?? [];
  const inRange =
    ["ahead", "identical"].includes(comparison.status) &&
    fixes.length <= 1 &&
    files.every((file) =>
      [file.filename, file.previous_filename].every(
        (path) =>
          path === undefined ||
          inThreadScope(path, paths, run.threads, {
            prPaths,
            copyPaths,
            added: path === file.filename && ["added", "renamed", "copied"].includes(file.status),
          }),
      ),
    );
  if (!inRange) {
    return null;
  }
  if (fixSha) {
    const commitFiles = (await api.getCommit(fixSha)).files ?? [];
    const changed = commitFiles.map((file) => file.filename);
    const patches = new Map(commitFiles.map((file) => [file.filename, file.patch]));
    const named = threadsNamed(fixes[0].commit.message);
    const touches = (thread, reply) => touchesThread(changed, thread, citedFiles(reply.evidence, patches, thread, prPaths, copyPaths));
    if (!valid.every((reply) => named.has(reply.thread) && touches(threadOf.get(reply.thread), reply))) {
      return null;
    }
    for (const reply of valid) {
      landed.set(reply.thread, fixSha);
    }
    return landed;
  }
  if (valid.length > 0) {
    if (patchWritten) {
      return null;
    }
    const commits = await api.listPullCommits(pr);
    const read = new Map();
    const filesOf = async (sha) => {
      if (!read.has(sha)) {
        read.set(sha, (await api.getCommit(sha)).files ?? []);
      }
      return read.get(sha);
    };
    for (const reply of valid) {
      const sha = await earlierFixOf({
        commits,
        appId,
        after: judgedAt(reply.thread),
        thread: threadOf.get(reply.thread),
        evidence: reply.evidence,
        claimed,
        filesOf,
      });
      if (sha === null) {
        return null;
      }
      landed.set(reply.thread, sha);
    }
  }
  return landed;
}

async function resolveAfterReply(api, id, expected, headMoved) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      const after = await api.readThread(id);
      if (!sameIds(after.commentIds, expected) || (await headMoved())) {
        return false;
      }
      if (after.isResolved === true && attempt > 1) {
        return true;
      }
      if (after.isResolved !== false) {
        return false;
      }
      if ((await api.resolveThread(id)) !== true) {
        throw new Error(`replied on ${id} but it does not read resolved`);
      }
      return true;
    } catch (error) {
      if (attempt >= 2) {
        throw error;
      }
    }
  }
}

export const modelRunLine = (modelRun) => `<!-- pr-unblock:address-feedback-model-run ${modelRun} -->`;

export const PASS_ONLY_SKIP = "pass-only";

async function resolveStaleNotes({ api, pr, headSha, headRef, run, log, summary }) {
  const headMoved = async () => run.head_sha !== headSha || (await api.readBranch(headRef)) !== headSha;
  const open = new Set(staleVerifyNotes(await api.listThreads(pr), headSha, { supersededHead: run.superseded_head }));
  const failed = [];
  let resolved = 0;
  for (const id of run.stale_notes) {
    if (!open.has(id)) {
      log(`${id} is no open fail-note thread from an earlier head; left alone`);
      continue;
    }
    try {
      if (await headMoved()) {
        log(`the PR head is no longer ${run.head_sha}, which pr-verify passed; nothing more is resolved`);
        break;
      }
      if ((await api.resolveThread(id)) !== true) {
        throw new Error("it does not read resolved");
      }
      resolved += 1;
    } catch (error) {
      failed.push(id);
      log(`could not resolve ${id}: ${String(error?.message ?? error).slice(0, 300)}`);
    }
  }
  const counted = `resolved ${resolved} fail-note thread(s) a pr-verify pass at ${run.head_sha} superseded`;
  log(counted);
  summary(counted);
  if (failed.length > 0) {
    throw new Error(`could not resolve ${failed.join(", ")}`);
  }
  return { escalationReason: "", skipReason: PASS_ONLY_SKIP, posted: [] };
}

function staleRunOf(readArtifact) {
  try {
    const run = parseRun(readArtifact().runText);
    return run.stale_notes ? run : null;
  } catch {
    return null;
  }
}

const UNDISPOSED_SHOWN = 20;
export const undisposedLines = (undisposed = []) =>
  undisposed.length === 0
    ? []
    : [
        "",
        "Kept review threads with no disposition:",
        ...undisposed.slice(0, UNDISPOSED_SHOWN).map(({ id, comment }) => `- \`${id}\` (root comment ${comment})`),
        ...(undisposed.length > UNDISPOSED_SHOWN ? [`- and ${undisposed.length - UNDISPOSED_SHOWN} more`] : []),
      ];

export async function publish(args) {
  const { api, pr, headSha, appId, modelRun, maxRounds = DEFAULT_MAX_ROUNDS, log = () => {}, summary = () => {} } = args;
  const staleRun = staleRunOf(args.readArtifact);
  if (staleRun !== null) {
    return resolveStaleNotes({ api, pr, headSha, headRef: args.headRef, run: staleRun, log, summary });
  }
  let result = null;
  let failure = null;
  try {
    result = await postReplies({ ...args, log });
  } catch (error) {
    failure = error;
  }
  const bodyNote =
    result === null ? null : await refreshBody({ api, pr, headMoved: async () => (await api.readBranch(args.headRef)) !== headSha, body: result.body, log });
  try {
    const comments = await api.listIssueComments(pr);
    const runLine = modelRun ? modelRunLine(modelRun) : null;
    if (runLine && comments.some((comment) => isRoundMarker(comment, appId) && String(comment.body).split("\n").includes(runLine))) {
      log(`the round of model run ${modelRun} is already recorded`);
    } else {
      const rounds = countRounds(comments, appId) + 1;
      const round = roundLine(rounds, maxRounds + FRESH_FIXER_ROUNDS);
      await api.createIssueComment(
        pr,
        [
          ROUND_MARKER,
          ...(runLine ? [runLine] : []),
          `pr-unblock / address-feedback finished ${round} on ${headSha}.`,
          ...undisposedLines(result?.undisposed),
          ...(bodyNote ? ["", bodyNote] : []),
        ].join("\n"),
      );
      log(`recorded round ${rounds}${result?.escalationReason ? `; escalating ${result.escalationReason}` : ""}`);
    }
  } catch (error) {
    log(`could not record the round: ${String(error?.message ?? error).slice(0, 300)}`);
    if (result !== null && result.escalationReason === "") {
      result = { ...result, escalationReason: "feedback-partial" };
    }
  }
  if (failure !== null) {
    throw failure;
  }
  return result;
}

async function settleNotes({ api, pr, run, headSha, replies, appId, log }) {
  if (replies.length !== run.verify_notes.length) {
    const disposed = new Set(replies.map((reply) => reply.thread));
    const undisposed = run.verify_notes.filter((note) => !disposed.has(note.id)).map((note) => note.id);
    log(`no reply is recorded: ${replies.length} of ${run.verify_notes.length} pr-verify notes have a disposition; none for ${undisposed.join(", ")}`);
    return { escalationReason: "feedback-incomplete", posted: [] };
  }
  if (!replies.some((reply) => reply.disposition === "VALID")) {
    if (run.head_sha !== headSha) {
      log("every pr-verify note is reported already addressed, yet the PR head moved since the select job read it");
      return { escalationReason: "feedback-not-landed", posted: [] };
    }
    log(`every one of the ${replies.length} pr-verify notes is reported already addressed by the diff, and nothing was pushed`);
    return { escalationReason: "feedback-already-addressed", posted: [] };
  }
  const threads = run.verify_notes.map(({ id, path }) => ({ id, path, comment_ids: [] }));
  const landed = await fixesLanded({ api, pr, run: { ...run, threads }, headSha, replies, appId, judgedAt: () => Number.NaN, patchWritten: true });
  if (landed === null || landed.size === 0) {
    log("no fix of a pr-verify note reached the PR branch as this round's one fix commit naming it, or the branch changed another path");
    return { escalationReason: "feedback-not-landed", posted: [] };
  }
  log(`pushed ${[...new Set(landed.values())].join(", ")}, fixing ${[...landed.keys()].join(", ")}`);
  return { escalationReason: "", posted: [] };
}

async function postReplies({ api, pr, headSha, headRef, appId, patchState = "", scanRefused = "", repliesExpected = false, reviewerId, reviewerIds = [], trustedHumans, readArtifact, readAdjudication = () => null, fileExists, log }) {
  let escalationReason = "";
  const headMoved = async () => (await api.readBranch(headRef)) !== headSha;
  {
    let run;
    let replies;
    let bodyRecord = null;
    try {
      const { runText, repliesText } = readArtifact();
      run = parseRun(runText);
      if (repliesText === null) {
        if (scanRefused !== "" || repliesExpected) {
          log(`no reply is posted: ${scanRefused ? `the scan refused the model call's ${scanRefused}` : "the replies the scan uploaded did not arrive"}`);
          return { escalationReason: "feedback-invalid", posted: [] };
        }
        if (headSha !== run.head_sha) {
          log("no reply is posted: no replies, and the PR head moved since the select job read it");
          return { escalationReason: "feedback-not-landed", posted: [] };
        }
        if (patchState !== "") {
          log(`no reply is posted: no replies beside a ${patchState} patch`);
          return { escalationReason: "feedback-invalid", posted: [] };
        }
        log("no reply is posted: no model turn uploaded replies");
        return { escalationReason: "", skipReason: "no-model-turn", posted: [] };
      }
      check(Buffer.byteLength(repliesText) <= LIMITS.bytes, "the replies are over the size limit");
      const taken = takeBodyRecord(repliesText);
      bodyRecord = taken.record;
      replies = parseReplies(taken.replyText, run, fileExists);
    } catch (error) {
      if (!(error instanceof Invalid) && error.code !== "ENOENT") {
        throw error;
      }
      log(`no reply is posted: ${error instanceof Invalid ? error.message : "the artifact is missing"}`);
      return { escalationReason: "feedback-invalid", posted: [] };
    }
    const body = (fixed) => ({ record: bodyRecord, offered: run.body_sections, fixed });
    const asks = new Map((run.pr_comments ?? []).map((item) => [item.id, item]));
    const answers = replies.filter((reply) => asks.has(reply.thread));
    replies = replies.filter((reply) => !asks.has(reply.thread));
    if (run.threads.length === 0 && asks.size > 0 && patchState === "written") {
      log("no reply is posted: a round with only comments to answer wrote a patch");
      return { escalationReason: "feedback-invalid", posted: [] };
    }
    if (run.verify_notes) {
      const settledNotes = await settleNotes({ api, pr, run, headSha, replies, appId, log });
      return { ...settledNotes, body: body(settledNotes.escalationReason === "") };
    }
    if (replies.length !== run.threads.length || answers.length !== asks.size) {
      const disposed = new Set([...replies, ...answers].map((reply) => reply.thread));
      const undisposed = [
        ...run.threads.filter((thread) => !disposed.has(thread.id)).map((thread) => ({ id: thread.id, comment: thread.comment_ids[0] })),
        ...[...asks.values()].filter((item) => !disposed.has(item.id)).map((item) => ({ id: item.id, comment: item.comment_id })),
      ];
      log(`no reply is posted: ${replies.length + answers.length} of ${run.threads.length + asks.size} kept threads and comments have a disposition; none for ${undisposed.map((thread) => thread.id).join(", ")}`);
      return { escalationReason: "feedback-incomplete", posted: [], undisposed };
    }
    const heads = run.reviewed_heads && new Set(run.reviewed_heads);
    const { kept, reviewComments } = await currentThreads({ api, pr, reviewerId, reviewerIds, appId, trustedHumans, heads, log });
    const now = new Map(kept.map((thread) => [thread.id, thread]));
    const shown = new Map(run.threads.map((thread) => [thread.id, thread]));
    const createdAt = new Map(reviewComments.map((comment) => [comment.id, comment.created_at]));
    const rootComments = new Map(reviewComments.map((comment) => [comment.id, comment]));
    const judgedAt = (thread) => {
      const times = (now.get(thread)?.comments ?? [])
        .filter((comment) => ["reviewer", "verifier", "lane"].includes(comment.author))
        .map((comment) => Date.parse(createdAt.get(comment.id) ?? ""));
      return times.length === 0 ? Number.NaN : Math.max(...times);
    };
    const landed = await fixesLanded({
      api,
      pr,
      run,
      headSha,
      replies,
      appId,
      judgedAt,
      patchWritten: patchState === "written",
      claimed: claimedFixes(reviewComments, appId),
    });
    if (landed === null) {
      log("no reply is posted: no one fix commit naming each VALID thread reached the PR branch, or the branch changed another path");
      return { escalationReason: "feedback-not-landed", posted: [] };
    }
    replies = replies.map((reply) => (reply.disposition === "VALID" ? { ...reply, fixSha: landed.get(reply.thread) } : reply));
    const appPr = (await api.getPull(pr))?.user?.id === appId;
    const resolve = appPr
      ? resolveAfterReply
      : async (_api, id) => {
          log(`${id}: left open; the lanes App cannot resolve a thread on a PR it did not open`);
          return LEFT_OPEN;
        };
    const posted = [];
    for (const reply of replies) {
      const ids = shown.get(reply.thread).comment_ids;
      const fresh = now.get(reply.thread);
      try {
        const reread = fresh && (await api.readThread(reply.thread));
        if (
          !fresh ||
          !sameIds(fresh.comments.map((comment) => comment.id), ids) ||
          reread.isResolved !== false ||
          reread.pr !== pr ||
          reread.commentCount !== ids.length ||
          !sameIds(reread.commentIds, ids)
        ) {
          log(`skipped ${reply.thread}: it changed since the model job read it`);
          continue;
        }
        if (await headMoved()) {
          log(`stopped at ${reply.thread}: the PR head is no longer ${headSha}`);
          escalationReason = posted.length === 0 ? "feedback-not-landed" : "feedback-partial";
          break;
        }
        if (reply.disposition === FOLLOW_UP) {
          await recordFollowUp(api, pr, rootComments.get(ids[0]));
        }
        const answer = await api.replyToComment(pr, ids[0], renderReply(reply));
        if (answer?.in_reply_to_id !== ids[0]) {
          throw new Error(`the reply on ${reply.thread} did not land on its thread`);
        }
        posted.push({ thread: reply.thread, disposition: reply.disposition });
        if (RESOLVING.has(reply.disposition) && !(await resolve(api, reply.thread, [...ids, answer.id], headMoved))) {
          log(`replied on ${reply.thread} but left it open: it or the PR head changed while the reply was posted`);
          escalationReason = "feedback-partial";
          continue;
        }
      } catch (error) {
        log(`stopped at ${reply.thread}: ${String(error?.message ?? error).slice(0, 300)}`);
        escalationReason = "feedback-partial";
        break;
      }
      log(`replied on ${reply.thread} (${reply.disposition})${RESOLVING.has(reply.disposition) && appPr ? "; resolved" : ""}`);
    }
    const settled = await settleDisputes({
      api,
      pr,
      adjudicatedSha: run.head_sha,
      headSha,
      posted,
      replies,
      shown,
      now,
      verdicts: posted.some((entry) => DISPUTED.includes(entry.disposition)) ? parseVerdicts(readAdjudication(), run.head_sha) : new Map(),
      ci: run.ci,
      pushed: run.head_sha !== headSha,
      headMoved,
      resolveAfterReply: resolve,
      escalationReason,
      log,
    });
    const asked = settled.escalationReason === "" ? await answerComments({ api, pr, appId, asks, answers, headMoved, log }) : { posted: [], stopped: "" };
    return {
      ...settled,
      escalationReason: settled.escalationReason || asked.stopped,
      posted: [...posted, ...asked.posted],
      body: body(landed.size > 0),
    };
  }
}

const matchesSha256 = (text, recorded) => /^[0-9a-f]{64}$/.test(recorded ?? "") && createHash("sha256").update(text).digest("hex") === recorded;

export async function main(env, { api, actions, log = (line) => console.log(line) } = {}) {
  need(env, [
    "GH_TOKEN",
    "GITHUB_REPOSITORY",
    "PR_NUMBER",
    "HEAD_SHA",
    "HEAD_REF",
    "GITHUB_RUN_ID",
    "APP_SENDER_ID",
    "TRUSTED_ACTORS",
    "FEEDBACK_REPLIES_DIR",
    "GITHUB_WORKSPACE",
    "SKIP_REASON_FILE",
    "ESCALATION_REASON_FILE",
  ]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const attempt = env.MODEL_RUN_ATTEMPT ?? "";
  if (attempt !== "" && !/^[1-9][0-9]{0,4}$/.test(attempt)) {
    throw new Error("MODEL_RUN_ATTEMPT is not a run attempt");
  }
  const patchState = env.REVIEW_PATCH_STATE ?? "";
  if (!["", "written", "empty"].includes(patchState)) {
    throw new Error("REVIEW_PATCH_STATE is not a patch state");
  }
  const scanRefused = scanRefusal({ dir: env.SCAN_REFUSED_DIR ?? "", read: env.SCAN_REFUSED_READ ?? "" });
  const runId = positive(env.GITHUB_RUN_ID, "GITHUB_RUN_ID");
  const modelRun = attempt ? `${runId}-${attempt}` : null;
  const dir = env.FEEDBACK_REPLIES_DIR;
  const read = (name, limit = LIMITS.bytes + 1) => {
    const path = join(dir, name);
    const stat = lstatSync(path);
    if (!stat.isFile()) {
      throw new Invalid(`${name} is not a regular file`);
    }
    if (stat.size > limit) {
      throw new Invalid(`${name} is over the size limit`);
    }
    return readFileSync(path, "utf8");
  };
  const readRun = () => {
    const text = read("run.json", LIMITS.runBytes);
    if (!matchesSha256(text, env.RUN_SHA256)) {
      throw new Invalid("run.json does not match the SHA-256 the select job recorded");
    }
    return text;
  };
  const readReplies = () => {
    let text;
    try {
      text = read("replies.jsonl");
    } catch (error) {
      if (error.code === "ENOENT") {
        return null;
      }
      throw error;
    }
    if (!matchesSha256(text, env.REPLIES_SHA256)) {
      throw new Invalid("replies.jsonl does not match the SHA-256 the scan job recorded");
    }
    return text;
  };
  const readAdjudication = () => {
    const path = join(env.ADJUDICATION_DIR ?? "", "verdicts.json");
    if (!env.ADJUDICATION_DIR || !existsSync(path) || !lstatSync(path).isFile() || lstatSync(path).size > LIMITS.bytes) {
      return null;
    }
    const text = readFileSync(path, "utf8");
    return matchesSha256(text, env.ADJUDICATION_SHA256) ? text : null;
  };
  const { escalationReason, skipReason } = await publish({
    api: withLaneBinding(
      api ??
        createGitHubApi({
          token: env.GH_TOKEN,
          repository: env.GITHUB_REPOSITORY,
          apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
          graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
        }),
      actions ?? laneReader(env),
    ),
    pr,
    headSha: env.HEAD_SHA,
    headRef: env.HEAD_REF,
    appId,
    modelRun,
    patchState,
    scanRefused,
    repliesExpected: attempt !== "" || (env.REPLIES_SHA256 ?? "") !== "",
    maxRounds: maxRoundsFrom(env.REVIEW_ROUNDS),
    reviewerId: reviewerIdFrom(env.TRUSTED_ACTORS),
    reviewerIds: reviewerIdsFrom(env.REVIEWER_IDS),
    trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS),
    readArtifact: () => ({ runText: readRun(), repliesText: readReplies() }),
    readAdjudication,
    fileExists: (path) => existsSync(join(env.GITHUB_WORKSPACE, path)),
    log,
    summary: (line) => env.GITHUB_STEP_SUMMARY && appendFileSync(env.GITHUB_STEP_SUMMARY, `${line}\n`),
  });
  if (escalationReason) {
    writeFileSync(env.ESCALATION_REASON_FILE, `${escalationReason}\n`);
    writeFileSync(env.SKIP_REASON_FILE, `${stopSkip(escalationReason)}\n`);
  } else if (skipReason) {
    writeFileSync(env.SKIP_REASON_FILE, `${skipReason}\n`);
  }
  return 0;
}

runAsScript(import.meta.url, "publish-feedback", () => main(process.env));
