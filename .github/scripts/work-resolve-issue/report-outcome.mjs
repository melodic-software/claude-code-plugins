#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { appendFileSync, lstatSync, readdirSync, readFileSync } from "node:fs";
import { join, posix, resolve } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { LIMIT_DEFAULTS, clampReset, readLimits } from "./limits.mjs";
import { networkError, retryApi } from "../lib/retry-fetch.mjs";
import { refusalText, sayWhy } from "../lib/admission-comment.mjs";
import { doneEvidence, parentDone, RUN_WORDS, stopLine } from "../lib/done-evidence.mjs";
import { laneBranchPattern, laneBranchPrefix, parseLaneBranch, WORK_RESOLVE_ISSUE } from "../lib/lane-branch.mjs";
import { markLaneHold } from "../lib/lane-hold-marker.mjs";
import { LANES_APP_LOGIN, REFINE_MARKER } from "../lib/lane-vocabulary.mjs";
import { personReasonLines } from "../lib/stop-reason.mjs";
import { readRawTrustedActors } from "../lib/trusted-actors.mjs";
import { DIFF, OUTSIDE_ACTOR_LABEL, trackerBindingText, UNTRUSTED_LABELS, visibleLines, wholeCompare } from "../pr-merge/merge-holds.mjs";
import { ATTENDED_LABEL, causeName, HOST_RUN_LABEL, leadingCode, runCode, securityWord, STOP_ROUTES, stopFault, stopReasonCode, stopRetries, stopRoute, stopWhy } from "./stop-routes.mjs";

export { doneEvidence, REFINE_MARKER };

export const HOLD_LINE = "Hold: a human merges this";
export const HOLD_LABEL = "do-not-merge";
export const EVAL_GATED_LABEL = "eval-gated";
export const evalHoldComment = (issueNumber) =>
  `Held for the before-and-after eval that cut item #${issueNumber} needs. The pr-merge release step lifts this hold when an eval-pair record exists for the current head.\n\n<!-- pr-hold reason=eval -->`;
const EXITS = new Set(["done", "pushback", "stopped"]);
const PUSHBACK_CAUSES = new Set(["intent", "intent-change"]);
const PUSHBACK_LANE_ROUTES = new Set(["host-run", "attended"]);
const pushbackStop = (outcome) => {
  const code = leadingCode(outcome.reason);
  if (code && stopRoute(code) === "hold") return code;
  const causeCode = leadingCode(outcome.cause);
  if (causeCode && stopRoute(causeCode) === "hold") return causeCode;
  const cause = causeName(outcome.cause);
  if (PUSHBACK_CAUSES.has(cause)) return "pushback";
  if (Object.hasOwn(STOP_ROUTES, cause) && STOP_ROUTES[cause].code === true && stopRoute(cause) === "hold") return cause;
  return PUSHBACK_LANE_ROUTES.has(stopRoute(code)) ? runCode(outcome.reason) : "pushback-means";
};
const stopWords = (outcome) =>
  [outcome?.reason, outcome?.summary, outcome?.cause, ...(outcome?.notDone ?? []).map((item) => item?.what)].filter(
    (words) => typeof words === "string" && words,
  );
const pushbackSecurity = (stop, outcome) =>
  stop === "pushback-means" && stopWords(outcome).some((words) => runCode(words, { anyCodeEnds: true }) === "security-risk");
const heldWord = (outcome) =>
  [leadingCode(outcome?.reason), leadingCode(outcome?.cause), causeName(outcome?.cause)].some((code) => stopRoute(code) === "hold")
    ? ""
    : (stopWords(outcome).map(securityWord).find(Boolean) ?? "");
const PREFIX = /^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9._-]+\))?!?: /;
const SUBJECT = /^(?!.*\bGH-\d)[A-Za-z0-9][A-Za-z0-9 ,.:;()'"`!?+=_-]{0,98}$/i;
const SUBJECT_MAX = 99;

function subjectFrom(text) {
  let subject = text
    .replaceAll(/[^A-Za-z0-9 ,.:;()'"`!?+=_-]+/g, " ")
    .replaceAll(/\b(GH)-(?=\d)/gi, "$1 ")
    .replaceAll(/\s+/g, " ")
    .replace(/^[^A-Za-z0-9]+/, "")
    .trimEnd();
  if (subject.length > SUBJECT_MAX) {
    const cut = subject.slice(0, SUBJECT_MAX + 1);
    subject = cut.slice(0, cut.lastIndexOf(" ") > 0 ? cut.lastIndexOf(" ") : SUBJECT_MAX);
  }
  return subject.replace(/[ ,:;-]+$/, "");
}

function conventionalFrom(text) {
  const prefix = PREFIX.exec(text)?.[0] ?? "";
  const subject = subjectFrom(text.slice(prefix.length));
  return subject ? `${prefix || "fix: "}${subject}` : "";
}

function prTitle(runTitle, issueTitle, issueNumber) {
  const match = PREFIX.exec(runTitle);
  if (match && SUBJECT.test(runTitle.slice(match[0].length))) {
    return runTitle;
  }
  return (match && conventionalFrom(runTitle)) || conventionalFrom(issueTitle) || `fix: resolve issue ${issueNumber}`;
}
export const HUMAN_MERGE_LABEL = "merge: human";
export function trustedLabeler(events, label, { bot, humans }) {
  const last = events.filter((event) => event?.event === "labeled" && event.label?.name === label).at(-1);
  return last !== undefined && (last.actor?.login === bot || humans.has(last.actor?.id));
}
const MAX_TEXT = 3000;
const MAX_ITEMS = 20;
const MAX_ITEM = 300;

export { clampReset };
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?Z$/;
export const ESCALATION_MARKER = "<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->";
const escalated = (lines) => [ESCALATION_MARKER, ...lines];
const LANE = "work-resolve-issue";
const MARKER = /^(?:<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\r?\n)?<!-- work-resolve-issue outcome=([a-z]+(?:-[a-z]+)*)(?: (security))?(?: resets=(\S+))?(?: cap=(\d+))?(?: pr=(\d+))?(?: run=(\d+))?(?: branch=(resumed))?(?: credential=(ISSUE_LANE_CLAUDE_API_KEY|ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN|FALLBACK_CLAUDE_CODE_OAUTH_TOKEN))?(?: fallback=(credit-stop|no-key))? -->/;

const resumedTag = (yes) => (yes ? " branch=resumed" : "");

const runLines = (runUrl) => (runUrl ? ["", `Run: ${runUrl}`] : []);

const CREDENTIALS = new Set(["ISSUE_LANE_CLAUDE_API_KEY", "ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN", "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN"]);
const FALLBACKS = new Set(["credit-stop", "no-key"]);
export function readLaneCredential(dir) {
  let lane;
  try {
    lane = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
  } catch {
    return {};
  }
  return {
    ...(CREDENTIALS.has(lane?.credential) && { credential: lane.credential }),
    ...(FALLBACKS.has(lane?.fallback) && { fallback: lane.fallback }),
  };
}

export function withCredential(plan, { credential, fallback } = {}) {
  const tag = `${CREDENTIALS.has(credential) ? ` credential=${credential}` : ""}${FALLBACKS.has(fallback) ? ` fallback=${fallback}` : ""}`;
  if (!tag || typeof plan?.comment !== "string") {
    return plan;
  }
  return { ...plan, comment: plan.comment.replace(/^(<!-- work-resolve-issue outcome=(?:(?! credential=| fallback=)[^\n])*?) -->/m, `$1${tag} -->`) };
}

export const limitedMarker = ({ resets, runId, onResumed = false }) =>
  `<!-- work-resolve-issue outcome=limited resets=${resets} run=${runId || 0}${resumedTag(onResumed)} -->`;

export const turnCapMarker = ({ cap, runId, onResumed = false }) =>
  `<!-- work-resolve-issue outcome=turn-cap${cap ? ` cap=${cap}` : ""}${runId ? ` run=${runId}` : ""}${resumedTag(onResumed)} -->`;

export const refsHoldMarker = (pr) => `<!-- work-resolve-issue refs-hold #${pr} -->`;

export function parseOutcomeMarker(body) {
  const match = MARKER.exec(String(body ?? ""));
  if (!match) {
    return null;
  }
  const resets = ISO.test(match[3] ?? "") ? Date.parse(match[3]) : Number.NaN;
  return {
    outcome: match[1],
    resets: Number.isFinite(resets) ? resets : null,
    run: match[6] ?? "",
    onResumed: match[7] === "resumed",
    ...(match[8] && { credential: match[8] }),
    ...(match[9] && { fallback: match[9] }),
    ...(match[5] && { pr: match[5] }),
    ...(match[2] && { security: true }),
  };
}

const CUT = "…";
const clip = (value, cap, tidy = (kept) => kept) => {
  if (value.length <= cap) {
    return tidy(value);
  }
  const head = value.slice(0, cap - CUT.length + 1);
  const words = head.slice(0, head.search(/\s\S*$/) + 1).trimEnd();
  const kept = tidy(words || head.slice(0, -1).replace(/[\uD800-\uDBFF]$/, "")).trimEnd();
  return kept && `${kept}${CUT}`;
};

const stopped = (reason) => ({ exit: "stopped", reason, title: "", summary: "", changes: [], verification: [], notDone: [], steps: [] });
const text = (value) => (typeof value === "string" ? clip(value, MAX_TEXT) : "");
const list = (value) =>
  Array.isArray(value) ? value.filter((item) => typeof item === "string").slice(0, MAX_ITEMS).map((item) => clip(item, MAX_ITEM)) : [];
const notDoneList = (value) =>
  (Array.isArray(value) ? value : [])
    .map((item) =>
      typeof item === "string"
        ? { what: item, required: false }
        : item?.required === true
          ? { what: typeof item.what === "string" ? item.what : "A required check the run did not name.", required: true }
          : typeof item?.what === "string"
            ? { what: item.what, required: false }
            : null,
    )
    .filter(Boolean)
    .slice(0, MAX_ITEMS)
    .map(({ what, required }) => ({ what: clip(what, MAX_ITEM), required }));

const stepList = (value) =>
  (Array.isArray(value) ? value : [])
    .filter((item) => typeof item?.activity === "string" && typeof item?.result === "string")
    .slice(0, MAX_ITEMS)
    .map(({ activity, result }) => ({ activity: activity.slice(0, 40), result: result.slice(0, 20) }));

function readDiffCheck(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"))?.merge?.["diff-check"];
  } catch {
    return undefined;
  }
}

function deniedPaths(diffCheck) {
  const paths = diffCheck?.["denied-paths"];
  return Array.isArray(paths) && paths.every((glob) => typeof glob === "string") ? paths : null;
}

export function readHoldPaths(path) {
  return deniedPaths(readDiffCheck(path));
}

export function heldPaths(path) {
  const diffCheck = readDiffCheck(path);
  const paths = deniedPaths(diffCheck);
  return paths !== null && [undefined, null, false, "false"].includes(diffCheck?.["path-holds"]) ? [] : paths;
}

const ATTEMPT = /^[1-9][0-9]{0,4}$/;
export function readScanRefusal(dir, attempt) {
  if (!ATTEMPT.test(attempt ?? "")) return "";
  const markerFile = new RegExp(`^scan-refused-${attempt}(-rung-up)?\\.txt$`);
  let kinds;
  try {
    kinds = readdirSync(dir)
      .filter((name) => markerFile.test(name) && lstatSync(join(dir, name)).isFile())
      .map((name) => readFileSync(join(dir, name), "utf8").trim());
  } catch {
    return "";
  }
  if (kinds.length === 0) return "";
  if (kinds.every((kind) => kind === "patch")) return "patch";
  return kinds.every((kind) => kind === "patch" || kind === "fault") ? "fault" : "output";
}

export const SCAN_REFUSALS = {
  patch: "The scan job refused the run's output, so nothing was published: too-large: the patch was over its 262144-byte cap. The run's log names its size.",
  output: "The scan job refused the run's output, so nothing was published. The run's log names why.",
  fault: "The patch did not apply to the head the scan job scans, so nothing was published. The run's log names it; that says nothing about a credential.",
};

export const COLLECT_REFUSED =
  "The run left content, a link or a directory at a name the patch collector only accepts as an empty stub (such as `.npmrc`, `.env` or a lockfile), so no patch was collected and nothing was published. The run's log names the file.";

export function readOutcome(path) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return { ...stopped("The run wrote no readable outcome file, so it stopped before it finished."), unread: true, stop: "outcome-unread" };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed) || !EXITS.has(parsed.exit)) {
    return { ...stopped("The run's outcome file names no known exit (done, pushback or stopped)."), unread: true, stop: "outcome-invalid" };
  }
  return {
    exit: parsed.exit,
    reason: text(parsed.reason),
    cause: text(parsed.cause),
    title: text(parsed.title),
    summary: text(parsed.summary),
    changes: list(parsed.changes),
    verification: list(parsed.verification),
    notDone: notDoneList(parsed.not_done),
    steps: stepList(parsed.steps),
    remaining: remainingList(parsed.remaining),
  };
}

function remainingList(value) {
  const items = Array.isArray(value) && value.length <= MAX_ITEMS && value.every((item) => typeof item === "string") ? value.map((item) => clip(item, MAX_ITEM)) : [];
  return items.every((item) => bullets([item]).slice(2).replace(CUT, "")) ? items : [];
}

const neutral = (value, cap, { path = false } = {}) =>
  clip(
    (path ? value : value.replaceAll(/<!--[\s\S]*?(-->|$)/g, ""))
      .replaceAll(/\p{Cf}/gu, "")
      .replaceAll("\r\n", "\n")
      .replaceAll(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/g, " ")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("[", "\\[")
      .replaceAll("]", "\\]")
      .replaceAll("@", "")
      .replaceAll("#", "＃")
      .replaceAll(/\bGH-/gi, "GH -")
      .replaceAll(/\/(issues|pull)\//gi, "/$1 /")
      .replaceAll("://", ": //")
      .replaceAll(/\bwww\./gi, "www ."),
    cap,
    (kept) => kept.replace(/&[a-z]*$|\\$/, ""),
  );

const quoted = (value) =>
  neutral(value || "(none)", MAX_TEXT)
    .trim()
    .split("\n")
    .map((line) => (line.trim() ? `> ${line.trimEnd()}` : ">"))
    .join("\n");

const TASK_ITEM = /^ {0,3}[-*+] \[[ xX]\] (.*)$/;
const PR_BODY = /\b(?:PR|pull request)(?:'s)? body\b/i;
const LINKAGE = /`(Refs:[ \t]*#[1-9][0-9]{0,8}|Siblings:[ \t]*#[1-9][0-9]{0,8}(?:[ \t]*,[ \t]*#[1-9][0-9]{0,8}){0,9})[ \t]*`/g;
const CODIFIES = /`(Codifies: (?:#[1-9][0-9]{0,8}|session) rung=[a-z][a-z0-9-]{0,39} (?:blocking|advisory))`/g;
const MAX_CODIFIES_LENGTH = 72;
export const MAX_LINKAGE = 10;
export function linkageLines(body, issueNumber) {
  const lines = new Set();
  for (const line of visibleLines(body)) {
    const item = TASK_ITEM.exec(line);
    if (!item || !PR_BODY.test(item[1])) {
      continue;
    }
    for (const [, quote] of item[1].matchAll(LINKAGE)) {
      const text = quote.replace(/:[ \t]*/, ": ").replaceAll(/[ \t]*,[ \t]*/g, ", ");
      if (text !== `Refs: #${issueNumber}`) {
        lines.add(text);
      }
    }
    for (const [, record] of item[1].matchAll(CODIFIES)) {
      if (record.length <= MAX_CODIFIES_LENGTH) {
        lines.add(record);
      }
    }
  }
  return [...lines].slice(0, MAX_LINKAGE);
}

const bullets = (items) =>
  items
    .slice(0, MAX_ITEMS)
    .map((item) => `- ${neutral(item.replaceAll(/\s+/g, " "), MAX_ITEM).trim()}`)
    .join("\n");

const notDoneLines = (notDone) => (notDone.length ? ["", "What the run says it did not do:", "", bullets(notDone.map(({ what }) => what))] : []);

export const DECISION_LINE = "**Decision recorded.**";
const DECISION = /^\*\*Decision recorded\.\*\*(\s|$)/;
const firstLine = (body) => String(body ?? "").trimStart().split("\n", 1)[0].trimEnd();
const COMMENT_URL = /^https:\/\/[A-Za-z0-9.-]+\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/[1-9][0-9]*#issuecomment-[1-9][0-9]*$/;

export function unmarkedAnswer(comments, humans, bot) {
  const since = comments.findLastIndex((comment) => comment?.user?.login === bot && parseOutcomeMarker(comment.body) !== null);
  const last = comments.slice(since + 1).filter((comment) => humans.has(comment?.user?.id)).at(-1);
  return last && last.performed_via_github_app == null && !DECISION.test(firstLine(last.body)) && COMMENT_URL.test(last.html_url ?? "") ? last.html_url : null;
}

function handBack({ outcome, issueNumber, branch, humanLabel, runUrl, runId, onResumed = false, unmarked = null, reason, spentSecurity = false, word = "" }) {
  const pushback = outcome.exit === "pushback";
  const [reasonMarker, reasonLine] = personReasonLines(LANE, reason);
  const lines = escalated([
    `<!-- work-resolve-issue outcome=${outcome.exit}${runId ? ` run=${runId}` : ""}${resumedTag(onResumed)} -->`,
    reasonMarker,
    spentSecurity
      ? "The work-resolve-issue lane hands this issue to a person: this run named a possible security risk again after its intake rounds were spent, so a person checks it first."
      : reason === "security" && pushback
        ? "The work-resolve-issue lane did not start this issue: the run named a possible security risk, so a person checks it first."
        : pushback
        ? "The work-resolve-issue lane did not start this issue: it needs a person to make it clearer first."
        : "The work-resolve-issue lane stopped partway through this issue and needs a person.",
    "",
    reasonLine,
    ...(word ? ["", `Matched security word: \`${word}\`. A match holds the stop whether or not the text names a risk, so read the word in context below.`] : []),
    "",
    "Why, in the run's own words:",
    "",
    quoted(outcome.reason || outcome.summary),
    ...notDoneLines(outcome.notDone),
  ]);
  if (pushback && unmarked) {
    lines.push(
      "",
      `The newest comment from a listed maintainer, ${unmarked}, does not start with \`${DECISION_LINE}\`, so the lane did not count it as an answer. If it answers the question, post the answer again in a new comment whose first line is:`,
      "",
      "```",
      `${DECISION_LINE} <answer>`,
      "```",
    );
  }
  if (branch) {
    lines.push(
      "",
      pushback
        ? `Partial work is on the branch \`${branch}\`.`
        : `Partial work is on the branch \`${branch}\`. A retry continues from it while it is not behind the default branch, and otherwise starts fresh from the default branch; delete the branch first to always start fresh.`,
    );
  }
  lines.push(
    ...runLines(runUrl),
    "",
    pushback
      ? `To retry, answer the question in a comment whose first line is \`${DECISION_LINE}\`, then set Work status to agent-ready again (clearing the \`${humanLabel}\` hold).`
      : `To retry, set Work status to agent-ready again (clearing the \`${humanLabel}\` hold).`,
  );
  return {
    action: "hand-back",
    exit: outcome.exit,
    issueNumber,
    comment: lines.join("\n"),
    addLabels: [],
    status: humanLabel,
  };
}

const ROUTE_OUTCOME = { retry: "retry", wait: "wait", intake: "intake", park: "parked", close: "closed", "host-run": "host-run", attended: "attended", fail: "failed" };
const ROUTE_LABEL = { "host-run": HOST_RUN_LABEL, attended: ATTENDED_LABEL };
const PARK_STATUS = "status: confirmed";
const KEPT = new Set(["retry", "wait"]);
const COUNTED = new Set([...KEPT, "intake"]);
export async function stripQueueLabels() {
  return [];
}
export const STATE_LABELS = [HOST_RUN_LABEL];

const labelNames = (labels) => labels.map((label) => String(typeof label === "string" ? label : label?.name).toLowerCase());

export async function stripStateLabels(github, base, had) {
  const present = new Set(labelNames(had));
  const removed = STATE_LABELS.filter((name) => present.has(name));
  for (const name of removed) {
    await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`).catch((error) => {
      if (error?.status !== 404) {
        throw error;
      }
    });
  }
  return removed;
}
const ROUTE_TEXT = {
  "host-run": `It added \`${HOST_RUN_LABEL}\` and set Work status to confirmed: an agent run on a host builds it, and it waits on no decision from a person.`,
  attended: `It added \`${ATTENDED_LABEL}\` and set Work status to confirmed: the step needs the owner present, and it waits on no decision from a person.`,
  intake: "It set Work status to needs-triage, so the hourly triage sweep sends it back through intake triage, and it waits on no decision from a person.",
  "intake-security": "It set Work status to needs-triage, so the hourly triage sweep sends it back through intake triage.",
  park: `It set Work status to confirmed, as admission parks a refusal no person answers, and it waits on no decision from a person. Once that step is done, a listed human's comment whose first line is \`${DECISION_LINE}\` sends it back through intake triage.`,
  close: "It closes the issue as completed.",
  fail: "It set Work status to needs-triage and added no label.",
};
export const waitedPull = (reason, issueNumber) =>
  [...String(reason ?? "").matchAll(/[#＃]([1-9][0-9]{0,9})\b/g)].map((match) => match[1]).find((number) => Number(number) !== issueNumber) ?? "";
const PUSHBACK_SECURITY_WHY =
  "the run pushed back without naming cause intent, and its words may name a security risk, so intake triage judges the issue again on evidence; if the run names it again once this intake round is spent, the issue reaches a person";
function stopPlan({ route, stop, shown, retries, cap, outcome, issueNumber, branch, runUrl, runId, onResumed = false, pr = "", after = "", why = "", neutral = false }) {
  const exit = ROUTE_OUTCOME[route];
  const lines = [
    `<!-- work-resolve-issue outcome=${exit}${neutral ? " security" : ""}${pr ? ` pr=${pr}` : ""}${runId ? ` run=${runId}` : ""}${resumedTag(onResumed)} -->`,
    `${stopLine(stop)} ${neutral ? PUSHBACK_SECURITY_WHY : stopWhy(shown)}.`,
    ...(why ? [why] : []),
    ...(after ? [`It must land after #${after}: intake triage records #${after} on its \`Blocked by:\` line, which writes the blocked-by edge.`] : []),
    route === "retry"
      ? `It keeps \`agent-ready\`, and work-unblock starts it again (retry ${retries + 1} of ${cap}).`
      : route === "wait"
        ? `It keeps \`agent-ready\`, and work-unblock starts it again once #${pr} merges or closes (wait ${retries + 1} of ${cap}).`
        : ROUTE_TEXT[neutral ? "intake-security" : route],
  ];
  const words = outcome.reason || outcome.summary;
  if (words) {
    lines.push("", RUN_WORDS, "", quoted(words));
  }
  if (outcome.exit === "pushback" && String(outcome.cause ?? "").trim()) {
    lines.push("", "The cause the run named:", "", quoted(String(outcome.cause)));
  }
  if (route === "close" && outcome.reason && outcome.summary) {
    lines.push("", "The run's report:", "", quoted(outcome.summary));
  }
  lines.push(...notDoneLines(outcome.notDone));
  if (branch) {
    lines.push("", `Partial work is on the branch \`${branch}\`. The next run continues from it while it is not behind the default branch, and otherwise starts fresh.`);
  }
  lines.push(...runLines(runUrl));
  if (route === "host-run") {
    lines.push("", `To hand it back to the lane, remove \`${HOST_RUN_LABEL}\` and set Work status to agent-ready again.`);
  } else if (route === "attended") {
    lines.push("", `Once the step is done, a listed human removes \`${ATTENDED_LABEL}\` and sets Work status to agent-ready again.`);
  } else if (route === "fail") {
    lines.push("", "To run it again, set Work status to agent-ready.");
  }
  return {
    action: route,
    exit,
    stop,
    issueNumber,
    runId,
    comment: lines.join("\n"),
    addLabels: Object.hasOwn(ROUTE_LABEL, route) ? [ROUTE_LABEL[route]] : [],
    ...((route === "park" || Object.hasOwn(ROUTE_LABEL, route)) && { status: PARK_STATUS }),
    ...(pr && { pr }),
    ...(after && { after }),
    ...(route === "park" && { admission: parkReason(stop, why || stopWhy(shown)) }),
  };
}

const parkReason = (stop, why) => {
  const said = why.replace(/\.$/, "");
  return `the work-resolve-issue lane stopped on it (\`${stop}\`); ${said.charAt(0).toLowerCase()}${said.slice(1)}`;
};

function routeStop(stop, args, { retries = 0, limits = LIMIT_DEFAULTS, route: given = stopRoute(stop), why = "", spentSecurity = false } = {}) {
  const cap = stopRetries(stop, limits["stop-retries"]);
  const spent = COUNTED.has(given) && retries >= cap;
  const security = given === "intake" && pushbackSecurity(stop, args.outcome);
  if (spent && security) {
    return routeStop("security-risk", args, { spentSecurity: true });
  }
  const shown = spent ? "retry-spent" : stop;
  const route = spent ? stopRoute(shown) : given;
  const pr = route === "wait" ? waitedPull(args.outcome?.reason, args.issueNumber) : "";
  const after = route === "intake" && shown === "blocked-by-issue" ? waitedPull(args.outcome?.reason, args.issueNumber) : "";
  const plan =
    route === "hold"
      ? handBack({ ...args, reason: stopReasonCode(shown), spentSecurity, word: shown === "security-risk" ? heldWord(args.outcome) : "" })
      : stopPlan({ ...args, outcome: { notDone: [], ...args.outcome }, route, stop, shown, retries, cap, pr, after, why, neutral: security });
  return { ...plan, stop, stopArgs: args, ...(why && { why }) };
}

export const capRetries = (plan, retries, limits = LIMIT_DEFAULTS) =>
  COUNTED.has(plan.action) ? routeStop(plan.stop, plan.stopArgs, { retries, limits, route: plan.action, why: plan.why }) : plan;

export const PATCH_REASONS = {
  "patch-empty": "the run wrote no change",
  "patch-protected-path": "the patch changes a path the issue lane may not push: a workflow, a CODEOWNERS file, submodule config or a settings file",
  "patch-invalid": "the run's output was not a valid patch to push: missing, too large or made on another commit",
  "patch-credential": "the patch, or a file it writes, carries a credential shape",
  "patch-not-applied": "the patch did not apply to the commit the run started from",
  "patch-apply-failed": "apply-issue-patch failed before it committed or refused the patch",
};

export const DIMENSION_STEPS = {
  "split-required": "Its Size is too large for one run: intake splits it into sub-issues (owner Q93).",
  "research-first": "Its Uncertainty says research comes first: plan or research the approach, then set Uncertainty to Known.",
  "probe-first": "Its Uncertainty says only an experiment answers it: run a probe or spike first, then set Uncertainty to Known.",
};

const RETIRED_SKIPS = new Set(["not-assessed"]);

export const OUTSIDE_AUTHOR = "outside-author";
const TRIAGE_AGAIN = new Set(["intake", "failed", OUTSIDE_AUTHOR]);

function outsideAuthorPlan({ issueNumber, runUrl, runId }) {
  const lines = [
    `<!-- work-resolve-issue outcome=${OUTSIDE_AUTHOR}${runId ? ` run=${runId}` : ""} -->`,
    "The work-resolve-issue lane did not start this issue (`outside-author`): its author is outside the trusted list, neither a listed human nor the lanes App, so the lane does not work from its text. A listed human re-files the work as a new issue in their own words.",
    ...runLines(runUrl),
  ];
  return { action: "hand-back", exit: OUTSIDE_AUTHOR, issueNumber, comment: lines.join("\n"), addLabels: [] };
}

export const WORKFLOW_STALE = "workflow-stale";

export const LANE_WORKFLOWS = [".github/workflows/pr-run-activity-write.yml", ".github/workflows/work-resolve-issue.yml"];
export const REFIRED = /^<!-- work-unblock refired ([0-9a-f]{40}-[0-9a-f]{40})( breaker)? -->/;
export const refireComment = (key, cause, actor = "work-unblock") =>
  `<!-- work-unblock refired ${key} -->\n${cause} ${actor} removed and added \`agent-ready\` back to start a fresh run on main's workflow files. If this run ends the same way, it re-fires the issue again, waiting longer each time.`;
const STALE_CAUSE =
  "The work-resolve-issue run that `agent-ready` started waited in its slot past a change to its lane workflow files on main, so it stopped before any model turn.";
export const LANE_HOLDS = new Set(["needs-owner-decision", "needs-reporter-info", "needs-human", ...UNTRUSTED_LABELS, ATTENDED_LABEL, HOST_RUN_LABEL, OUTSIDE_ACTOR_LABEL]);
const BLOB = /^[0-9a-f]{40}$/;

const admissionLib = () => import("../lib/admission-record.mjs");

const appSets = (fieldEvents, fieldId, appId) =>
  (fieldEvents ?? [])
    .filter((event) => event?.field === String(fieldId) && event.removed === false && event.to === "agent-ready" && event.actorId === appId)
    .map((event) => Date.parse(event.at));

const warnStatus = (issueNumber, error) =>
  console.log(`::warning title=work-status::issue #${issueNumber} is left as it is: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);

async function fieldState(field, issueNumber) {
  try {
    return await field.state(issueNumber);
  } catch (error) {
    warnStatus(issueNumber, error);
    return undefined;
  }
}

const NO_FIELD = { id: null, state: async () => null, events: async () => [], restart: async () => false };

export async function refireStale(github, repo, issueNumber, { workflowSha, bot, appId, humans, limits, statusOf = async (number, names) => names, field = NO_FIELD }) {
  if (!BLOB.test(workflowSha ?? "")) {
    return "skipped: the run names no workflow commit";
  }
  const shas = async (ref) => {
    const out = [];
    for (const path of LANE_WORKFLOWS) {
      const sha = (await github("GET", `${repo}/contents/${path}?ref=${ref}`))?.sha;
      if (!BLOB.test(String(sha))) {
        throw new Error(`${path} at ${ref} has no blob SHA`);
      }
      out.push(sha);
    }
    return out.join("-");
  };
  const key = await shas("main");
  if ((await shas(workflowSha)) === key) {
    return "skipped: the run's lane workflow files are main's";
  }
  const base = `${repo}/issues/${issueNumber}`;
  const issue = await github("GET", base);
  const labels = labelNames(issue?.labels ?? []);
  if (issue?.state !== "open") {
    return "skipped: the issue is closed";
  }
  const state = await fieldState(field, issueNumber);
  if (state === undefined) {
    return "skipped: the Work status could not be read";
  }
  if (state !== "agent-ready") {
    return "skipped: the Work status is not agent-ready";
  }
  const held = await laneHold(statusOf, issueNumber, labels);
  if (held) {
    return `skipped: ${held}`;
  }
  const all = await paginate(github, `${base}/comments`);
  const fieldEvents = await field.events(issueNumber);
  const { admittedAt } = await admissionLib();
  let admission;
  try {
    admission = admittedAt({ comments: all, appId, fieldEvents, fieldId: field.id, humans });
  } catch {
    return "skipped: no admission record or listed human's agent-ready set admitted the issue";
  }
  const comments = all.filter((comment) => comment?.user?.login === bot);
  const at = (comment) => Date.parse(comment.created_at);
  const from = Math.max(admission.at, ...comments.filter((comment) => parseOutcomeMarker(comment.body) !== null).map(at));
  const records = comments.filter((comment) => {
    const record = REFIRED.exec(String(comment.body ?? ""));
    return record !== null && record[2] === undefined && at(comment) > from;
  });
  const sets = appSets(fieldEvents, field.id, appId);
  const pending = records.some((comment) => !sets.some((time) => time >= at(comment)));
  if (!pending && records.length >= limits["limit-stops-per-issue"]) {
    return `skipped: ${records.length} re-fires since the issue's admission or a run last reported (limits.limit-stops-per-issue); work-unblock's sweep takes it`;
  }
  if (!pending) {
    await github("POST", `${base}/comments`, { body: refireComment(key, STALE_CAUSE, "The run's report-outcome") });
  }
  if (!(await field.restart(issueNumber, "agent-ready"))) {
    return "skipped: the Work status changed before the re-fire";
  }
  return `re-fired on workflow files ${key}`;
}

async function laneHold(statusOf, issueNumber, labels) {
  let names;
  try {
    names = (await statusOf(issueNumber, labels)).map((name) => String(name).toLowerCase());
  } catch (error) {
    warnStatus(issueNumber, error);
    return "the Work status could not be read";
  }
  const hold = names.find((label) => LANE_HOLDS.has(label));
  return hold ? `held by ${hold}` : "";
}

const ANSWERED_STOPS = new Set(["pushback", "intent-change", "design-change", "cost-risk"]);
const REDISPATCHED = /^(?:<!-- work-resolve-issue outcome=redispatch[^\n]* -->\r?\n)?<!-- work-resolve-issue redispatch comment=([1-9][0-9]{0,15}) -->/;
export const redispatchComment = (comment, runId = "") =>
  `<!-- work-resolve-issue outcome=redispatch${runId ? ` run=${runId}` : ""} -->\n<!-- work-resolve-issue redispatch comment=${comment.id} -->\nA record this run did not read was posted after its admission: ${comment.html_url}. The run's report-outcome posted a fresh admission record and set the Work status field to agent-ready again, so a fresh run admits the issue as it stands now and reads it.`;

export async function lateRecord({ comments, fieldEvents, fieldId, appId, bot, humans, runId }) {
  const { admissionRecords, admittedAt } = await admissionLib();
  const marker = runId
    ? comments.findLast((item) => item?.user?.login === bot && REDISPATCHED.test(String(item.body ?? "")) && parseOutcomeMarker(item.body)?.run === runId)
    : undefined;
  if (marker) {
    const named = REDISPATCHED.exec(String(marker.body))[1];
    const comment = comments.find((item) => String(item?.id) === named);
    const since = Date.parse(marker.created_at);
    return comment ? { comment, marker, recorded: admissionRecords(comments, appId).some(({ at }) => at >= since) } : null;
  }
  let from;
  try {
    from = admittedAt({ comments, appId, fieldEvents, fieldId, humans }).at;
  } catch {
    return null;
  }
  const comment = comments.find((item) => {
    const body = String(item?.body ?? "");
    if (!(Date.parse(item?.updated_at ?? item?.created_at ?? "") >= from)) {
      return false;
    }
    if (item.user?.login === bot) {
      return body.startsWith(REFINE_MARKER);
    }
    return item.user?.type === "User" && humans.has(item.user.id) && item.performed_via_github_app == null && DECISION.test(firstLine(body));
  });
  return comment ? { comment } : null;
}

async function redispatch(github, repo, plan, late, { runId, statusOf, field, appId }) {
  if (!Number.isSafeInteger(appId)) {
    return false;
  }
  const base = `${repo}/issues/${plan.issueNumber}`;
  const issue = await github("GET", base);
  const labels = labelNames(issue?.labels ?? []);
  const since = late.marker ? Date.parse(late.marker.created_at) : Number.POSITIVE_INFINITY;
  const events = late.marker ? await field.events(plan.issueNumber) : [];
  if (appSets(events, field.id, appId).some((time) => time >= since)) {
    return true;
  }
  if (issue?.state !== "open" || (await laneHold(statusOf, plan.issueNumber, labels))) {
    return false;
  }
  const state = await fieldState(field, plan.issueNumber);
  const newest = events.filter((event) => event?.field === String(field.id)).at(-1);
  const moving = state === null && newest?.removed === true && newest.actorId === appId && Date.parse(newest.at) >= since;
  if (state !== "agent-ready" && !moving) {
    return false;
  }
  if (!late.marker) {
    await github("POST", `${base}/comments`, { body: redispatchComment(late.comment, runId) });
  }
  if (!late.recorded) {
    const { writeAdmissionRecord } = await admissionLib();
    await writeAdmissionRecord(github, repo.slice("/repos/".length), plan.issueNumber, { actorId: appId, title: issue.title, body: issue.body ?? "" });
  }
  await field.restart(plan.issueNumber, moving ? null : "agent-ready");
  return true;
}

function limitedPlan({ issueNumber, branch, resets, runId, runUrl, onResumed }) {
  const lines = [
    limitedMarker({ resets, runId, onResumed }),
    `The work-resolve-issue lane stopped on its usage limit, not on this issue. It keeps \`agent-ready\`, and work-unblock starts it again after ${resets}.`,
  ];
  if (branch) {
    lines.push("", `Partial work is on the branch \`${branch}\`.`);
  }
  lines.push(...runLines(runUrl));
  return { action: "limited", exit: "limited", issueNumber, resets, runId, comment: lines.join("\n"), addLabels: [] };
}

function fundingPlan({ issueNumber, branch, regain, runId, runUrl, onResumed }) {
  const resets = regain === null ? "" : new Date(regain).toISOString().replace(/\.\d+Z$/, "Z");
  const lines = [
    `<!-- work-resolve-issue outcome=funding${resets ? ` resets=${resets}` : ""} run=${runId || 0}${resumedTag(onResumed)} -->`,
    resets
      ? `The work-resolve-issue lane stopped on its funding (\`funding\`: a spend limit or no credit), not on this issue. It keeps \`agent-ready\`, and work-unblock starts it again after ${resets}.`
      : "The work-resolve-issue lane stopped on its funding (`funding`: no credit or a disabled key), not on this issue. It keeps `agent-ready`, and work-unblock starts it again after limits.fallback-reset hours; after limits.limit-stops-per-issue limit and funding stops it removes `agent-ready` and marks the issue failed.",
  ];
  if (branch) {
    lines.push("", `Partial work is on the branch \`${branch}\`; the restart continues from it while it is not behind the default branch, and otherwise starts fresh.`);
  }
  lines.push(...runLines(runUrl));
  return { action: "funding", exit: "funding", issueNumber, runId, comment: lines.join("\n"), addLabels: [] };
}

function turnCapPlan({ issueNumber, branch, cap, timeout = false, restart, humanLabel, runId, runUrl, onResumed }) {
  const reached = timeout ? "its time ran out (the launcher's leg timeout)" : cap ? `turn cap ${cap} reached` : "turn cap reached";
  if (!restart) {
    return routeStop("turn-cap-spent", {
      outcome: stopped(`The run stopped: ${reached}, and it has used its turn-cap restarts.`),
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
      onResumed,
    });
  }
  const lines = [
    turnCapMarker({ cap, runId, onResumed }),
    `The work-resolve-issue lane stopped on this issue: ${reached}. It keeps \`agent-ready\`, and work-unblock starts it again from the branch, or fresh from the default branch once the branch is behind it.`,
    "",
    branch
      ? `Partial work is on the branch \`${branch}\`; a restart or retry continues from it while it is not behind the default branch, and otherwise starts fresh. Delete the branch first to always start fresh.`
      : "The run committed nothing.",
    ...runLines(runUrl),
  ];
  return { action: "turn-cap", exit: "turn-cap", issueNumber, runId, comment: lines.join("\n"), addLabels: [] };
}

export function readSummary(dir, { issueNumber, branch }) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(join(dir, "reuse-summary.json"), "utf8"));
  } catch {
    return null;
  }
  const output = parsed?.output;
  if (
    parsed?.version !== 1 ||
    parsed.issue !== issueNumber ||
    parsed.branch !== branch ||
    !BLOB.test(parsed.tip ?? "") ||
    output === null ||
    typeof output !== "object" ||
    Array.isArray(output)
  ) {
    return null;
  }
  const summary = text(output.summary);
  return summary.trim() ? { tip: parsed.tip, title: text(output.title), summary, changes: list(output.changes) } : null;
}

export function readChecks(text, { branch }) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  const results = parsed?.results;
  const valid =
    parsed?.version === 1 &&
    typeof branch === "string" &&
    branch !== "" &&
    parsed.branch === branch &&
    BLOB.test(parsed.tip ?? "") &&
    Array.isArray(results) &&
    results.length <= MAX_ITEMS &&
    results.every((result) => typeof result?.check === "string" && Number.isInteger(result.exit));
  if (!valid) {
    return null;
  }
  const record = { tip: parsed.tip, results: results.map(({ check, exit }) => ({ check: clip(check, MAX_ITEM), exit })) };
  return Object.hasOwn(parsed, "scan") ? { ...record, scan: SCAN_WORDS.has(parsed.scan) ? parsed.scan : "failed" } : record;
}
const SCAN_WORDS = new Set(["clean", "found", "failed"]);

const checkFailures = (checks) =>
  checks === null
    ? [{ what: "The runner's check results are missing, unreadable or for another tip of the branch.", required: true }]
    : checks.results.filter(({ exit }) => exit !== 0).map(({ check, exit }) => ({ what: `${check} failed (exit ${exit})`, required: true }));

export const checksPassed = (checks) => Boolean(checks?.results.length) && !checkFailures(checks).length;

export function mustHold({ issueLabels, humanMerge, holdPaths, changedFiles, checks, reused = false }) {
  return (
    humanMerge ||
    issueLabels.some((label) => UNTRUSTED_LABELS.includes(label)) ||
    holdPaths === null ||
    changedFiles === null ||
    changedFiles.some((path) => holdPaths.some((glob) => posix.matchesGlob(path, glob))) ||
    (reused && checks?.scan !== "clean")
  );
}

const scanLine = (checks) =>
  checks?.scan === "clean"
    ? "The runner's leak scan read everything the branch changes since its merge base with the default branch and found nothing credential-shaped."
    : checks?.scan === "found"
      ? "The runner's leak scan found a credential shape or a password or secret assignment in what the branch changes, so a person merges this."
      : "The runner's leak scan of the branch did not finish or could not be read, so a person merges this.";

const checkLines = (checks) =>
  checks === null
    ? "The runner's check results could not be read."
    : checks.results.length
      ? `The runner ran each check from the base copy against ${checks.tip}:\n\n${bullets(
          checks.results.map(({ check, exit }) => `${check}: ${exit === 0 ? "passed" : `failed (exit ${exit})`}`),
        )}`
      : "The runner ran no checks: the activity lists none.";

const MAX_FILES = 50;
function fileList(files, holdPaths) {
  if (!files) {
    return "The changed-file list is unavailable: the compare request failed.";
  }
  if (!files.length) {
    return "The compare listing names no changed files.";
  }
  const denied = (path) => holdPaths?.some((glob) => posix.matchesGlob(path, glob)) ?? false;
  const sorted = [...files.filter(denied), ...files.filter((path) => !denied(path))];
  return [
    holdPaths
      ? "Files the branch changes, from the compare listing; a denied path, which the merge lane refuses, is marked and listed first:"
      : "Files the branch changes, from the compare listing; the denied paths could not be read, so none is marked:",
    "",
    ...sorted
      .slice(0, MAX_FILES)
      .map((path) => `- ${neutral(path.replaceAll(/\s+/g, " "), MAX_ITEM, { path: true }).trim()}${denied(path) ? " (denied path)" : ""}`),
    ...(sorted.length > MAX_FILES ? [`- and ${sorted.length - MAX_FILES} more`] : []),
  ].join("\n");
}

const humanPullStop = (humanPull, args) =>
  routeStop("blocked-by-pr", {
    outcome: stopped(`A listed human's open pull request #${humanPull} names this issue, so the lane pushed no branch and opened no pull request.`),
    ...args,
  });

export function reusePlan({
  issueNumber,
  issueLabels = [],
  issueTitle = "",
  branch,
  runUrl = "",
  earlierRunUrl = "",
  summary = null,
  changedFiles = null,
  holdPaths = null,
  humanMerge = false,
  humanLabel = "needs-human",
  runId = "",
  humanPull = "",
  checks = null,
  linkage = [],
}) {
  if (humanPull) {
    return humanPullStop(humanPull, { issueNumber, branch, humanLabel, runUrl, runId, onResumed: false });
  }
  const hold = mustHold({ issueLabels, humanMerge, holdPaths, changedFiles, checks, reused: true });
  const opened = `Opened by the work-resolve-issue lane from \`${branch}\`, which an earlier run left with commits and no report.`;
  const [about, fix, earlierChecks, leftOut] = summary
    ? [
        [`${opened} A summary-only model pass read the branch's diff and the issue, changed nothing, and wrote:`, "", quoted(summary.summary)],
        summary.changes.length ? bullets(summary.changes) : "The summary pass listed no changes; the diff shows them.",
        "The earlier run reported no checks here, and the summary pass ran none.",
        "every check the earlier run would have reported",
      ]
    : [
        [`${opened} The model did not run again, and the earlier run's outcome could not be read, so this body carries none of its text.`],
        "The diff shows the changes.",
        "The earlier run reported no checks here.",
        "every check",
      ];
  const body = [
    `Closes #${issueNumber}`,
    ...linkage,
    "",
    ...(hold ? [HOLD_LINE, ""] : []),
    "## Summary",
    "",
    ...about,
    "",
    "## Fix",
    "",
    fix,
    "",
    fileList(changedFiles, holdPaths),
    "",
    "## Verification",
    "",
    `${earlierChecks}\n\n${checkLines(checks)}\n\n${scanLine(checks)}`,
    "",
    earlierRunUrl ? `- The earlier lane run: ${earlierRunUrl}` : "- The earlier lane run.",
    runUrl ? `- This lane run: ${runUrl}` : "- This lane run.",
    "",
    hold
      ? `Left out: ${leftOut}; a person reviews the diff before merging.`
      : `Left out: ${leftOut}; ci-status, pr-verify and the security review lane check the head before it merges.`,
    "",
    "## Related",
    "",
    `#${issueNumber}`,
  ].join("\n");
  return { action: "open-pr", issueNumber, title: prTitle(summary?.title ?? "", issueTitle, issueNumber), body, branch, hold };
}

export function decide({
  outcome,
  issueNumber,
  issueLabels,
  issueTitle = "",
  branch,
  changedFiles,
  holdPaths = null,
  humanMerge = false,
  humanLabel = "needs-human",
  runUrl = "",
  limit = null,
  turnCap = null,
  turnCapRestarts = 0,
  overCap = null,
  funding = null,
  issueStop = null,
  limits = LIMIT_DEFAULTS,
  now = Date.now(),
  runId = "",
  checks = null,
  resumed = "",
  escalation = "",
  humanPull = "",
  unmarked = null,
  collectRefused = false,
  linkage = [],
}) {
  outcome = { changes: [], verification: [], notDone: [], remaining: [], ...outcome };
  if (issueStop && outcome.unread) {
    outcome = { ...outcome, reason: issueStop, stop: Object.keys(ISSUE_STOPS).find((key) => ISSUE_STOPS[key] === issueStop) ?? outcome.stop };
  }
  const onResumed = !branch && resumed !== "";
  if (collectRefused) {
    return routeStop("collect-refused", { outcome: stopped(COLLECT_REFUSED), issueNumber, branch: "", humanLabel, runUrl, runId });
  }
  const patchRefused = (lead) =>
    routeStop(escalation, {
      outcome: stopped(`${lead}, but apply-issue-patch did not commit its patch (\`${escalation}\`): ${PATCH_REASONS[escalation]}. The run's log names the path or check.`),
      issueNumber,
      branch: branch || resumed,
      humanLabel,
      runUrl,
      runId,
      onResumed,
    });
  if (escalation && stopRoute(escalation) === "hold") {
    return patchRefused(outcome.exit === "done" ? "The run reported done" : "The run left a patch");
  }
  if (outcome.stop === "scan-refused-output") {
    return routeStop(outcome.stop, { outcome, issueNumber, branch: branch || resumed, humanLabel, runUrl, runId, onResumed });
  }
  if (humanPull && outcome.exit === "done") {
    return humanPullStop(humanPull, { issueNumber, branch: branch || resumed, humanLabel, runUrl, runId, onResumed });
  }
  if (funding && outcome.unread) {
    return fundingPlan({ issueNumber, branch, regain: funding.regain, runId, runUrl, onResumed });
  }
  if (limit && outcome.unread) {
    const resets = new Date(clampReset(limit.resets, now, limits)).toISOString().replace(/\.\d+Z$/, "Z");
    return limitedPlan({ issueNumber, branch, resets, runId, runUrl, onResumed });
  }
  if (turnCap && outcome.unread) {
    const restart = turnCapRestarts < limits["turn-cap-restarts"];
    return turnCapPlan({ issueNumber, branch, cap: turnCap.cap, timeout: turnCap.timeout === true, restart, humanLabel, runId, runUrl, onResumed });
  }
  if (outcome.exit === "done" && escalation && escalation !== "patch-empty" && !(escalation === "patch-apply-failed" && branch)) {
    return patchRefused("The run reported done");
  }
  const resumedChecked = checksPassed(checks);
  if (outcome.exit === "done" && !branch && resumed && resumedChecked) {
    const plan = decide({
      outcome: {
        ...outcome,
        verification: [
          `This run resumed \`${resumed}\` and made no commit of its own; the runner checked that whole branch at ${checks.tip}, and every commit on it ahead of the default branch is the lanes App's.`,
          ...outcome.verification,
        ],
      },
      issueNumber,
      issueLabels,
      issueTitle,
      branch: resumed,
      changedFiles,
      holdPaths,
      humanMerge,
      humanLabel,
      runUrl,
      overCap,
      limits,
      now,
      runId,
      checks,
      linkage,
    });
    return plan.action === "open-pr" ? { ...plan, tip: checks.tip } : plan;
  }
  if (outcome.exit === "done" && !branch && resumed) {
    return routeStop("resumed-unchecked", {
      outcome: stopped(
        `The run resumed \`${resumed}\` and reported done with no new commit. The earlier run's work is on that branch, and the runner's checks did not pass over that whole branch, so no PR was opened.`,
      ),
      issueNumber,
      branch: resumed,
      humanLabel,
      runUrl,
      runId,
      onResumed,
    });
  }
  if (outcome.exit === "done" && !branch) {
    return routeStop("done-no-commit", {
      outcome: stopped("The run reported done but committed nothing."),
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
    });
  }
  const stop = outcome.exit === "pushback" ? pushbackStop(outcome) : outcome.unread ? (outcome.stop ?? "outcome-unread") : runCode(outcome.reason);
  if (outcome.exit === "stopped" && stop === "patch-protected-path") {
    return routeStop(stop, {
      outcome: {
        ...outcome,
        reason: `The run stopped early (\`patch-protected-path\`): its change needs a path the issue lane may not push, which a person changes instead. In the run's words: ${outcome.reason}`,
      },
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
      onResumed,
    });
  }
  if (outcome.exit !== "done") {
    const retry = (stop === "report-delivered" || stop === "verified-done") && (branch || resumed);
    const why = "The run committed to a branch, or resumed one, so it retries instead of closing.";
    return routeStop(stop, { outcome, issueNumber, branch, humanLabel, runUrl, runId, onResumed, unmarked }, retry ? { route: "retry", why } : {});
  }
  const failed = checkFailures(checks);
  if (failed.length) {
    return routeStop("check-failed", {
      outcome: {
        ...outcome,
        exit: "stopped",
        reason: "The run reported done, but a check the runner ran on the branch failed or could not be read, so it is not finished.",
        notDone: [...failed, ...outcome.notDone],
      },
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
    });
  }
  if (outcome.notDone.some(({ required }) => required)) {
    return routeStop("required-undone", {
      outcome: {
        ...outcome,
        exit: "stopped",
        reason: "The run reported done but left a required check undone, so it is not finished.",
      },
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
    });
  }
  const refs = outcome.remaining.length > 0;
  const hold = mustHold({ issueLabels, humanMerge, holdPaths, changedFiles, checks });
  const gaps = outcome.notDone.map(({ what }) => what);
  const body = [
    refs ? `Refs: #${issueNumber}` : `Closes #${issueNumber}`,
    ...linkage.filter((line) => !(refs && line.startsWith("Refs:"))),
    ...(hold ? ["", HOLD_LINE] : []),
    "",
    "## Summary",
    "",
    "Opened by the work-resolve-issue lane. The run's own summary:",
    "",
    quoted(outcome.summary),
    ...(overCap ? ["", `The run went past its turn budget (turns=${overCap.turns} max-turns=${overCap.cap}): the work may be too big for one run.`] : []),
    ...(refs ? ["", "## Remaining work", "", bullets(outcome.remaining)] : []),
    ...(gaps.length ? ["", "## Not verified", "", bullets(gaps)] : []),
    "",
    "## Fix",
    "",
    outcome.changes.length ? bullets(outcome.changes) : "The run listed no changes; the diff shows them.",
    "",
    "## Verification",
    "",
    checkLines(checks),
    "",
    outcome.verification.length ? `The run reports:\n\n${bullets(outcome.verification)}` : "The run listed no checks.\n",
    runUrl ? `- The lane run: ${runUrl}` : "- The lane run.",
    "",
    gaps.length ? "Left out: the items under Not verified." : "Left out: nothing the run reported.",
    "",
    "## Related",
    "",
    `#${issueNumber}`,
  ].join("\n");
  return {
    action: "open-pr",
    issueNumber,
    title: prTitle(outcome.title, issueTitle, issueNumber),
    body,
    branch,
    hold,
  };
}

export function requiredSections(path, run = execFileSync) {
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    return [];
  }
  try {
    const list = JSON.parse(run("yq", ["-o=json", "-I=0", ".pr_body_required_sections // []", "-"], { input: text, encoding: "utf8", timeout: 30_000, maxBuffer: 1 << 20 }));
    return Array.isArray(list) ? list.filter((name) => typeof name === "string" && SECTION_NAME.test(name.trim())).map((name) => name.trim()) : [];
  } catch {
    return [];
  }
}

const SECTION_NAME = /^[A-Za-z0-9][A-Za-z0-9 ._/-]{0,59}$/;

export function withRequiredSections(body, names) {
  const have = new Set(body.split("\n").flatMap((line) => (line.startsWith("## ") ? [line.slice(3).trim().toLowerCase()] : [])));
  const missing = [...new Set(names)].filter((name) => !have.has(name.toLowerCase()));
  return missing.length === 0 ? body : [body, ...missing.flatMap((name) => ["", `## ${name}`, "", "The work-resolve-issue lane has nothing for this section; the sections above carry the run's report."])].join("\n");
}

function humanLabelFrom(path) {
  let config;
  try {
    config = JSON.parse(trackerBindingText(path));
  } catch (error) {
    if (error.code === "ENOENT") {
      return "needs-human";
    }
    throw new Error(`cannot read ${path}`);
  }
  const roles = config?.config?.role_labels ?? {};
  if (!Object.hasOwn(roles, "human-gated")) {
    return "needs-human";
  }
  const label = roles["human-gated"];
  if (typeof label !== "string" || label === "") {
    throw new Error("the human-gated role label is not a non-empty string");
  }
  if (label.trim().toLowerCase() === "agent-ready") {
    throw new Error("the human-gated role label is agent-ready");
  }
  return label;
}

export const RESUMABLE = new Set(["turn-cap", "stopped", "limited", "funding", "retry", "wait", "host-run", "attended", "failed"]);

const laneBranch = (issueNumber) => laneBranchPattern(WORK_RESOLVE_ISSUE, issueNumber);
export const isLaneBranch = (name, issueNumber) => laneBranch(issueNumber).test(name ?? "");
export const laneBranchIssue = (name) => {
  const parsed = parseLaneBranch(name);
  return parsed ? Number(parsed.issue) : null;
};

const laneCommit = (commit, bot) =>
  commit?.commit?.verification?.verified === true && commit.author?.login === bot && commit.committer?.login === "web-flow";
export const listedCommits = (comparison) =>
  Array.isArray(comparison?.commits) && comparison.commits.length === comparison.total_commits ? comparison.commits : null;
export const allLaneCommits = (commits, bot) => Array.isArray(commits) && commits.length > 0 && commits.every((commit) => laneCommit(commit, bot));

function fromLane(dir, read, fallback) {
  try {
    return read(JSON.parse(readFileSync(join(dir, "lane.json"), "utf8")));
  } catch {
    return fallback;
  }
}

export function readBranch(dir, issueNumber, key = "branch") {
  return fromLane(dir, (lane) => (isLaneBranch(lane?.[key], issueNumber) ? lane[key] : ""), "");
}

export const trustedCloser = (closing, { repo, bot, humans }) =>
  closing.find(({ author, repository }) => String(repository?.nameWithOwner ?? "").toLowerCase() === repo.toLowerCase() && trustedAuthor(author, { bot, humans }));
const trustedAuthor = (author, { bot, humans }) =>
  (author?.__typename === "Bot" && (author.login === bot || `${author.login}[bot]` === bot)) || (author?.__typename === "User" && humans.has(author.databaseId));

export function findPrior({ issueNumber, repo, bot, humans, branches, closing, markers, keepBehind = false }) {
  const lane = laneBranches(branches, issueNumber);
  const byBot = (pull) => pull?.user?.login === bot;
  const open = lane.find(({ pulls }) => pulls.some((pull) => pull.state === "open" && byBot(pull)));
  if (open) {
    return { action: "stop", reason: `the lanes App's PR from ${open.name} is open` };
  }
  const trusted = trustedCloser(closing, { repo, bot, humans });
  if (trusted) {
    return { action: "stop", reason: `open PR #${trusted.number} closes the issue` };
  }
  const reported = reportedIn(markers);
  const laneTip = ({ tip }) => laneCommit(tip, bot);
  const usable = (branch) => branch.aheadBy > 0 && laneTip(branch) && !branch.pulls.some(byBot);
  const reuse = lane.find((branch) => usable(branch) && !reported(branch));
  if (reuse) {
    return { action: "reuse", branch: reuse.name };
  }
  const allLane = ({ commits }) => allLaneCommits(commits, bot);
  const decisive = [...markers]
    .reverse()
    .find(
      (marker) =>
        !(marker.onResumed && RESUMABLE.has(marker.outcome)) &&
        !Object.hasOwn(DIMENSION_STEPS, marker.outcome) &&
        marker.outcome !== ROUTE_OUTCOME.park &&
        marker.outcome !== OUTSIDE_AUTHOR &&
        !RETIRED_SKIPS.has(marker.outcome),
    );
  const resume =
    RESUMABLE.has(decisive?.outcome) && decisive.run !== ""
      ? lane.find((branch) => branch.match[1] === decisive.run && usable(branch) && allLane(branch))
      : null;
  if (resume && resume.behindBy !== 0 && !keepBehind) {
    return { action: "run", stale: { branch: resume.name, tip: resume.sha, behindBy: resume.behindBy } };
  }
  return resume ? { action: "resume", branch: resume.name, tip: resume.sha, cause: decisive.outcome } : { action: "run" };
}

const laneBranches = (branches, issueNumber) => {
  const shape = laneBranch(issueNumber);
  return branches
    .map((branch) => ({ ...branch, match: shape.exec(branch.name) }))
    .filter(({ match }) => match)
    .sort((a, b) => Number(b.match[1]) - Number(a.match[1]) || Number(b.match[2]) - Number(a.match[2]));
};
const reportedIn = (markers) => ({ match, tipAt }) =>
  markers.some((marker) => marker.run === match[1] || (marker.run === "" && !(marker.at <= tipAt)));

export const PRUNE_CAP = 20;

export function pruneBranches({ issueNumber, bot, branches, markers, prior, runId = "" }) {
  const spared = new Set([prior?.branch, prior?.stale?.branch].filter(Boolean));
  const reported = reportedIn(markers);
  return laneBranches(branches, issueNumber)
    .filter((branch) => branch.pulls.length === 0 && laneCommit(branch.tip, bot) && allLaneCommits(branch.commits, bot) && reported(branch))
    .filter((branch) => branch.match[1] !== String(runId) && !spared.has(branch.name))
    .map(({ name }) => name)
    .slice(0, PRUNE_CAP);
}

export function readHumans(path) {
  const list = readRawTrustedActors(path);
  if (list?.version !== 1 || !Array.isArray(list.actors)) {
    throw new Error("the trusted-actor list does not match its schema");
  }
  return new Set(list.actors.filter((actor) => actor?.kind === "human" && Number.isInteger(actor.id)).map((actor) => actor.id));
}

function readHumansOrNone(path) {
  try {
    return readHumans(path ?? "");
  } catch {
    return new Set();
  }
}

export function readLimit(dir) {
  return fromLane(dir, (lane) => {
    if (lane?.class !== "rate-limit") {
      return null;
    }
    const resets = ISO.test(lane.resets ?? "") ? Date.parse(lane.resets) : Number.NaN;
    return { resets: Number.isFinite(resets) ? resets : null };
  }, null);
}

export const ISSUE_STOPS = {
  "issue-edited":
    "The run did not start: the issue's title or body changed after `agent-ready` was added, so the runner wrote no issue file for the skill and no model ran.",
  "issue-edited-trusted":
    "The run did not start: the issue's title or body changed after `agent-ready` was added, each change by a listed account, so the runner wrote no issue file for the skill and no model ran.",
  "issue-file":
    "The run did not start: the runner could not write the issue file for the skill, so no model ran. The run job's `Write the issue for the skill` step names the reason.",
};
export function readIssueStop(dir) {
  return fromLane(dir, (lane) => (Object.hasOwn(ISSUE_STOPS, lane?.class ?? "") ? ISSUE_STOPS[lane.class] : null), null);
}

const REGAIN = /regain access on ([^.\n"]{1,80})/i;
export function readFunding(dir) {
  return fromLane(dir, (lane) => {
    if (lane?.failed !== "true") {
      return null;
    }
    if (lane["api-error-status"] === "401") {
      return { regain: null };
    }
    const text = typeof lane["error-text"] === "string" ? lane["error-text"].slice(0, 2000) : "";
    const match = lane["api-error-status"] === "400" ? REGAIN.exec(text) : null;
    if (!match) {
      return null;
    }
    const regain = Date.parse(match[1].trim());
    return { regain: Number.isFinite(regain) ? regain : null };
  }, null);
}

const turnCount = (value) => (/^[1-9][0-9]{0,5}$/.test(value ?? "") ? Number(value) : null);

export function readTurnCap(dir) {
  return fromLane(dir, (lane) => {
    if (lane?.class === "timeout") {
      return { cap: null, timeout: true };
    }
    return lane?.class === "max-turns" ? { cap: turnCount(lane["max-turns"]) } : null;
  }, null);
}

export function readOverCap(dir) {
  return fromLane(dir, (lane) => {
    const [turns, cap] = [turnCount(lane?.turns), turnCount(lane?.["max-turns"])];
    return turns !== null && cap !== null && turns > cap ? { turns, cap } : null;
  }, null);
}

export async function humanSince(fieldEvents, fieldId, humans) {
  if (fieldId == null) {
    return Number.NEGATIVE_INFINITY;
  }
  const { personAdmissions } = await admissionLib();
  return personAdmissions(fieldEvents, { fieldId, humans }).at(-1)?.at ?? Number.NEGATIVE_INFINITY;
}

export const countTurnCapRestarts = (args) => countRestarts({ ...args, outcome: "turn-cap" });

function restartMarkers({ comments, since, bot, runId, outcome }) {
  return comments
    .map((comment) => (comment.user?.login === bot ? { ...parseOutcomeMarker(comment.body), at: Date.parse(comment.created_at), fault: faultComment(comment.body) } : null))
    .filter((marker) => marker?.outcome === outcome && marker.run !== runId && marker.at > since);
}
export const countRestarts = (args) => restartMarkers(args).length;

const FAULT_STOPS = Object.keys(STOP_ROUTES).filter(stopFault).map(stopLine);
const faultComment = (body) => {
  const line = String(body ?? "").split(/\r?\n/, 2)[1] ?? "";
  return FAULT_STOPS.some((stop) => line.startsWith(stop));
};

const spentOnFaults = (plan, markers, runId, limits) =>
  plan.action === "retry" &&
  stopFault(plan.stop) &&
  markers.length > 0 &&
  markers.length >= stopRetries(plan.stop, limits["stop-retries"]) &&
  markers.every((marker) => marker.fault) &&
  (!plan.stopArgs.branch || laneBranch(plan.issueNumber).exec(plan.stopArgs.branch)?.[1] !== runId);

async function paginate(github, path, maxPages = 50) {
  const items = [];
  const separator = path.includes("?") ? "&" : "?";
  for (let page = 1; page <= maxPages; page += 1) {
    const batch = await github("GET", `${path}${separator}per_page=100&page=${page}`);
    if (!Array.isArray(batch)) {
      throw new Error(`${path} answered something other than a list`);
    }
    items.push(...batch);
    if (batch.length < 100) {
      return items;
    }
  }
  throw new Error(`${path} has more than ${maxPages} pages`);
}

const CLOSING_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      closedByPullRequestsReferences(first: 100, after: $after, includeClosedPrs: false) {
        nodes { number state author { __typename login ... on User { databaseId } } repository { nameWithOwner } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

export async function closingPulls(github, { owner, name, number }, maxPages = 50) {
  const nodes = [];
  let after = null;
  for (let page = 1; page <= maxPages; page += 1) {
    const answer = await github("POST", "/graphql", { query: CLOSING_QUERY, variables: { owner, name, number, after } });
    const refs = answer?.data?.repository?.issue?.closedByPullRequestsReferences;
    if (answer?.errors?.length || !Array.isArray(refs?.nodes)) {
      throw new Error("the issue's closing pull requests could not be read");
    }
    if (!refs.nodes.every((node) => typeof node?.state === "string")) {
      throw new Error("the issue's closing pull requests answered one with no state");
    }
    nodes.push(...refs.nodes.filter((node) => node.state === "OPEN"));
    if (typeof refs.pageInfo?.hasNextPage !== "boolean") {
      throw new Error("the issue's closing pull requests answered no page information");
    }
    if (!refs.pageInfo.hasNextPage) {
      return nodes;
    }
    after = refs.pageInfo.endCursor;
    if (typeof after !== "string" || after === "") {
      throw new Error("the issue's closing pull requests answered a next page with no cursor");
    }
  }
  throw new Error(`the issue has more than ${maxPages} pages of closing pull requests`);
}

export const staleMarker = (branch) => `<!-- work-resolve-issue stale-branch=${branch} -->`;
const staleNoted = (body, branch) => String(body ?? "").split(/\r?\n/, 1)[0] === staleMarker(branch);
export const staleComment = (branch) =>
  `${staleMarker(branch)}\nThis run started fresh from the default branch instead of resuming \`${branch}\`, which is behind it. That branch keeps the earlier run's commits until the next run on this issue deletes it, when no pull request uses it.`;

function targetIssue(env) {
  if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) {
    throw new Error("ISSUE_NUMBER is not an issue number");
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
    throw new Error("GITHUB_REPOSITORY is not owner/repo");
  }
  return Number(env.ISSUE_NUMBER);
}

const botLogin = (env) => env.LANES_BOT_LOGIN || LANES_APP_LOGIN;
const resolvedConfigPath = (env) => env.RESOLVED_CONFIG || join(env.RUNNER_TEMP ?? "", "resolved-config.json");

const postedThisRun = (comments, { bot, outcome, runId }) =>
  comments.some((comment) => {
    const marker = comment.user?.login === bot ? parseOutcomeMarker(comment.body) : null;
    return marker?.outcome === outcome && runId !== "" && marker.run === runId;
  });

export async function findPriorMain({ env = process.env, fetchImpl, sleep, latchOptions } = {}) {
  const keepBehind = env.FIND_PRIOR_KEEP_BEHIND === "true";
  const holdsOnRefusal = !keepBehind;
  let reading = false;
  try {
    const issueNumber = targetIssue(env);
    const [owner, name] = env.GITHUB_REPOSITORY.split("/");
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const bot = botLogin(env);
    const humans = readHumans(env.TRUSTED_ACTORS_PATH ?? "");
    const { createGitHub } = await import(new URL("../lib/github-client.mjs", import.meta.url).href);
    const { createRateLimitLatch } = await import(new URL("../../actions/log-api-budget/rate-guard.mjs", import.meta.url).href);
    const github = createGitHub({
      token: env.GH_TOKEN,
      apiUrl: env.GITHUB_API_URL || undefined,
      fetchImpl,
      sleep,
      latch: createRateLimitLatch({ ...latchOptions, hold: holdsOnRefusal }),
    });
    reading = true;
    const appComments = (await paginate(github, `${repo}/issues/${issueNumber}/comments`)).filter((comment) => comment.user?.login === bot);
    const markers = appComments
      .map((comment) => ({ ...parseOutcomeMarker(comment.body), at: Date.parse(comment.created_at) }))
      .filter((marker) => marker.outcome !== undefined);
    if (markers.some((marker) => marker.run === "" && !Number.isFinite(marker.at))) {
      throw new Error("a lane outcome marker that names no run has no readable time");
    }
    const closing = await closingPulls(github, { owner, name, number: issueNumber });
    const shape = laneBranch(issueNumber);
    const matching = await github("GET", `${repo}/git/matching-refs/heads/${laneBranchPrefix(WORK_RESOLVE_ISSUE, issueNumber)}`);
    if (!Array.isArray(matching)) {
      throw new Error("the issue's lane branches could not be read");
    }
    const refs = matching
      .map((ref) => ({ name: String(ref.ref ?? "").replace(/^refs\/heads\//, ""), sha: ref.object?.sha }))
      .filter((ref) => shape.test(ref.name));
    const base = refs.length ? (await github("GET", repo))?.default_branch : "";
    if (refs.length && (typeof base !== "string" || base === "")) {
      throw new Error("the repository's default branch could not be read");
    }
    const legacy = markers.some((marker) => marker.run === "");
    const branches = [];
    for (const ref of refs) {
      const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(base)}...${encodeURIComponent(ref.name)}`);
      if (!Number.isSafeInteger(comparison?.ahead_by) || comparison.ahead_by < 0) {
        throw new Error(`the commits ${ref.name} holds ahead of ${base} could not be read`);
      }
      if (!Number.isSafeInteger(comparison.behind_by) || comparison.behind_by < 0) {
        throw new Error(`the commits ${ref.name} lacks from ${base} could not be read`);
      }
      const pulls = await paginate(github, `${repo}/pulls?state=all&head=${encodeURIComponent(`${owner}:${ref.name}`)}`);
      if (!/^[0-9a-f]{40}$/.test(ref.sha ?? "")) {
        throw new Error(`the tip of ${ref.name} could not be read`);
      }
      const tip = await github("GET", `${repo}/commits/${ref.sha}`);
      const tipAt = legacy ? Date.parse(tip?.commit?.committer?.date) : Number.NaN;
      if (legacy && !Number.isFinite(tipAt)) {
        throw new Error(`the tip commit time of ${ref.name} could not be read`);
      }
      const commits = listedCommits(comparison);
      branches.push({ name: ref.name, sha: ref.sha, aheadBy: comparison.ahead_by, behindBy: comparison.behind_by, tip, tipAt, pulls, commits });
    }
    reading = false;
    const prior = findPrior({ issueNumber, repo: env.GITHUB_REPOSITORY, bot, humans, branches, closing, markers, keepBehind });
    const runs = prior.action === "run" || prior.action === "resume";
    const prune =
      runs || prior.action === "reuse"
        ? pruneBranches({ issueNumber, bot, branches, markers, prior, runId: env.GITHUB_RUN_ID ?? "" })
        : [];
    const pruned = prune.length ? { "prune-branches": prune.join(" ") } : {};
    const outputs = runs
      ? {
          proceed: "true",
          "skip-reason": "",
          "reuse-branch": "",
          ...(prior.action === "resume"
            ? { "resume-branch": prior.branch, "resume-tip": prior.tip, "resume-cause": prior.cause }
            : {}),
          ...(prior.stale
            ? {
                "stale-branch": prior.stale.branch,
                "stale-tip": prior.stale.tip,
                "stale-noted": String(appComments.some((comment) => staleNoted(comment.body, prior.stale.branch))),
              }
            : {}),
          ...pruned,
        }
      : { proceed: "false", "skip-reason": "not-applicable", "reuse-branch": prior.action === "reuse" ? prior.branch : "", ...pruned };
    appendFileSync(env.GITHUB_OUTPUT, Object.entries(outputs).map(([key, value]) => `${key}=${value}\n`).join(""));
    console.log(
      prior.stale
        ? `report-outcome: ${prior.stale.branch} is ${prior.stale.behindBy} commits behind the default branch, so the model starts issue #${issueNumber} fresh from the default branch instead of resuming it; the branch is left as it is`
        : prior.action === "run"
        ? `report-outcome: no earlier run of issue #${issueNumber} left work to report; the model runs`
        : prior.action === "resume"
          ? `report-outcome: the model resumes issue #${issueNumber} from ${prior.branch} at ${prior.tip} (${prior.cause})`
          : prior.action === "reuse"
          ? `report-outcome: ${prior.branch} holds unreported work for issue #${issueNumber}; the work is skipped, a summary pass describes it and report-outcome opens its PR`
          : `report-outcome: ${prior.reason}; the model is skipped`,
    );
    return 0;
  } catch (error) {
    const message = String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ");
    if (reading && !keepBehind) {
      appendFileSync(env.GITHUB_OUTPUT, "proceed=false\n");
      console.log(`::notice title=report-outcome::could not read this issue's earlier work (${message}); the model is skipped, and a later run reads it again`);
      return 0;
    }
    console.log(`::error title=report-outcome::${message}`);
    return 1;
  }
}

async function applyHandBack(github, repo, plan, { setStatus = async () => {}, leaveAgentReady = async () => {}, stateOf } = {}) {
  const comment = async () => plan.comment && github("POST", `${repo}/issues/${plan.issueNumber}/comments`, { body: plan.comment });
  if (plan.addLabels.length) {
    await github("POST", `${repo}/issues/${plan.issueNumber}/labels`, { labels: plan.addLabels }, { safeToResend: true });
  }
  if (plan.status) {
    const moved = await setStatus(plan.issueNumber, await stateOf(plan.status), plan.status === PARK_STATUS ? { keepHold: true } : undefined);
    if (moved?.outcome === "held") {
      console.log(`report-outcome: issue #${plan.issueNumber} left as is: a person's Work status ${moved.state} holds it`);
      return;
    }
  } else if (!plan.addLabels.length) {
    await comment();
  }
  if (TRIAGE_AGAIN.has(plan.exit)) {
    await leaveAgentReady(plan.issueNumber, "needs-triage");
  }
  if (plan.status || plan.addLabels.length) {
    await comment();
  }
  console.log(`report-outcome: handed issue #${plan.issueNumber} back (${plan.exit})`);
}

const openPull = (github, repo, pr, { bot, humans }) =>
  pr
    ? github("GET", `${repo}/pulls/${pr}`).then(
        (pull) =>
          pull?.state === "open" && pull.merged_at == null
            ? trustedAuthor({ __typename: pull.user?.type, login: pull.user?.login, databaseId: pull.user?.id }, { bot, humans })
              ? "open"
              : "untrusted"
            : "",
        () => "",
      )
    : Promise.resolve("");

async function finishStop(github, repo, plan, { bot, appId, humans, runId, limits, lane = {}, verifyClose = "", setStatus, leaveAgentReady, statusOf, stateOf, field = NO_FIELD }) {
  const waited = plan.action === "wait" ? await openPull(github, repo, plan.pr, { bot, humans }) : "";
  if (plan.action === "wait" && waited !== "open") {
    const why = !plan.pr
      ? "Its reason names no pull request, so it retries instead."
      : waited === "untrusted"
        ? `#${plan.pr} was not opened by the lanes App or a listed human, so it retries instead.`
        : `#${plan.pr} is not an open pull request here, so it retries instead.`;
    plan = routeStop(plan.stop, plan.stopArgs, { limits, route: "retry", why });
  }
  if (plan.action === "close" && plan.stop === "already-done" && !(await doneEvidence(github, repo, plan.stopArgs.outcome?.reason, plan.issueNumber))) {
    const why =
      "Its reason cites no pull request merged into the default branch, or commit on it, made after the issue opened whose commit message closes this issue, so it retries instead of closing.";
    plan = routeStop(plan.stop, plan.stopArgs, { limits, route: "retry", why });
  }
  const trustedSubs = new Set(String(verifyClose).split(",").filter((number) => /^[1-9][0-9]{0,9}$/.test(number)).map(Number));
  if (plan.action === "close" && plan.stop === "verified-done" && !(await parentDone(github, repo, plan.issueNumber, async (number) => trustedSubs.has(Number(number))))) {
    const why =
      "Not every sub-issue of this issue is closed as completed by a listed human or a merge, as the run's admission read them, so it retries instead of closing.";
    plan = routeStop(plan.stop, plan.stopArgs, { limits, route: "retry", why });
  }
  let history = null;
  const read = async () => {
    if (history === null) {
      const comments = await paginate(github, `${repo}/issues/${plan.issueNumber}/comments`);
      const fieldEvents = await field.events(plan.issueNumber);
      history = { comments, fieldEvents, fieldId: field.id, since: await humanSince(fieldEvents, field.id, humans), appId, bot, humans, runId };
    }
    return history;
  };
  if (COUNTED.has(plan.action)) {
    const counted = { ...(await read()), outcome: plan.exit };
    if (spentOnFaults(plan, restartMarkers(counted), runId, limits)) {
      console.log(`::notice title=report-outcome::issue #${plan.issueNumber} stopped on a fault (${plan.stop}), and every retry since a person last added agent-ready was one too; it keeps agent-ready and a later run tries again`);
      markLaneHold();
      return;
    }
    plan = capRetries(plan, countRestarts(counted), limits);
  }
  plan = withCredential(plan, lane);
  if (plan.action === "hand-back" && ANSWERED_STOPS.has(plan.stop)) {
    const late = await read().then(lateRecord, () => null);
    if (late && (await redispatch(github, repo, plan, late, { runId, statusOf, field, appId }))) {
      console.log(`report-outcome: issue #${plan.issueNumber} got a record after its admission (${late.comment.html_url}); a fresh run reads it`);
      return;
    }
  }
  if (KEPT.has(plan.action)) {
    if (!postedThisRun(history.comments, { bot, outcome: plan.exit, runId })) {
      await github("POST", `${repo}/issues/${plan.issueNumber}/comments`, { body: plan.comment });
    }
    console.log(
      plan.action === "wait"
        ? `report-outcome: issue #${plan.issueNumber} waits on #${plan.pr} (${plan.stop}); it keeps agent-ready and work-unblock restarts it once #${plan.pr} merges or closes`
        : `report-outcome: issue #${plan.issueNumber} stopped (${plan.stop}); it keeps agent-ready and work-unblock retries it`,
    );
    return;
  }
  if (plan.action === "park") {
    const base = `${repo}/issues/${plan.issueNumber}`;
    await sayWhy(github, repo.slice("/repos/".length), base, (await read()).comments, refusalText(plan.admission), bot);
  }
  await applyHandBack(github, repo, plan, { setStatus, leaveAgentReady, stateOf });
  if (plan.action === "close") {
    const base = `${repo}/issues/${plan.issueNumber}`;
    const resend = (method, path) => github(method, path, undefined, { safeToResend: true });
    const had = (await github("GET", base))?.labels ?? [];
    await github("PATCH", base, { state: "closed", state_reason: "completed" }, { safeToResend: true });
    const states = await stripStateLabels(resend, base, had);
    console.log(`report-outcome: closed issue #${plan.issueNumber} (${plan.stop}); removed ${states.length} state label(s)`);
  }
}

export function workStatusField({ github, repository, config, reader, fieldEvents, restart }) {
  if (!config) {
    return NO_FIELD;
  }
  const state = async (number) => {
    await reader(number, []);
    return reader.state(number);
  };
  return {
    id: String(config["field-id"]),
    state,
    events: (number) => fieldEvents(github, repository, Number(number)),
    async restart(number, from) {
      if ((await state(number)) !== from) {
        return false;
      }
      const outcome = (await restart(Number(number), { from: from === null ? undefined : [from] }))?.outcome;
      return outcome !== "held" && outcome !== "moved";
    },
  };
}

async function baseStatus(env) {
  try {
    const actions = resolve(env.BASE_PATH || ".base", ".github", "actions");
    const { statusWriter } = await import(pathToFileURL(join(actions, "resolve-config", "write-status.mjs")).href);
    const { statusReader } = await import(pathToFileURL(join(actions, "resolve-config", "read-status.mjs")).href);
    const { fieldEvents, issueStatusFromBase } = await import(pathToFileURL(join(actions, "resolve-config", "resolve-config.mjs")).href);
    const { createGitHub } = await import(pathToFileURL(join(actions, "..", "scripts", "lib", "github-client.mjs")).href);
    const github = createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const repository = env.GITHUB_REPOSITORY;
    const { set, leaveAgentReady, restart } = await statusWriter({ env, github, repository });
    const statusOf = statusReader({ env, github, repository });
    const field = workStatusField({ github, repository, config: issueStatusFromBase(env), reader: statusOf, fieldEvents, restart });
    return { setStatus: set, leaveAgentReady, statusOf, field };
  } catch (error) {
    const fail = async () => {
      throw new Error(`the Work status writer and reader did not load: ${error?.message ?? error}`);
    };
    return { setStatus: fail, leaveAgentReady: fail, statusOf: fail, field: { id: null, state: fail, events: fail, restart: fail } };
  }
}

function appIdFrom(env, bot) {
  if (/^[1-9][0-9]*$/.test(env.APP_SENDER_ID ?? "")) {
    return Number(env.APP_SENDER_ID);
  }
  try {
    const actors = JSON.parse(readFileSync(env.TRUSTED_ACTORS ?? "", "utf8"))?.actors ?? [];
    const app = actors.find((actor) => actor?.kind === "bot" && actor.login === bot && Number.isSafeInteger(actor.id));
    return app ? app.id : Number.NaN;
  } catch {
    return Number.NaN;
  }
}

async function labelState(env, label) {
  const actions = resolve(env.BASE_PATH || ".base", ".github", "actions");
  const { issueStatusFromBase } = await import(pathToFileURL(join(actions, "resolve-config", "resolve-config.mjs")).href);
  const labels = issueStatusFromBase(env)?.labels ?? {};
  const state = Object.keys(labels).find((one) => labels[one].some((name) => name.toLowerCase() === label.toLowerCase()));
  if (state === undefined) {
    throw new Error(`models.issue-status gives no Work status state the label \`${label}\``);
  }
  return state;
}

export async function main({ env = process.env, fetch = globalThis.fetch, now = Date.now(), sleep, setStatus = async () => {}, leaveAgentReady = async () => {}, statusOf = async (number, names) => names, field = NO_FIELD } = {}) {
  const stateOf = (label) => labelState(env, label);
  const bot = botLogin(env);
  const appId = appIdFrom(env, bot);
  try {
    const issueNumber = targetIssue(env);
    const dimensionSkip = env.DIMENSION_SKIP ?? "";
    if (dimensionSkip && !Object.hasOwn(DIMENSION_STEPS, dimensionSkip) && dimensionSkip !== OUTSIDE_AUTHOR && dimensionSkip !== WORKFLOW_STALE) {
      throw new Error("DIMENSION_SKIP is not an issue-dimension skip reason");
    }
    const escalation = env.ESCALATION_REASON ?? "";
    if (escalation && !Object.hasOwn(PATCH_REASONS, escalation)) {
      throw new Error("ESCALATION_REASON is not an apply-issue-patch escalation reason");
    }
    const humanPull = env.HUMAN_PULL ?? "";
    if (humanPull && !/^[1-9][0-9]{0,9}$/.test(humanPull)) {
      throw new Error("HUMAN_PULL is not a pull request number");
    }
    const reuse = env.REUSE_BRANCH ?? "";
    const reused = laneBranch(issueNumber).exec(reuse);
    if (reuse && !reused) {
      throw new Error("REUSE_BRANCH is not this issue's lane branch");
    }
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const github = retryApi({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN, sleep });
    const runUrlOf = (id) => (env.GITHUB_SERVER_URL && id ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${id}` : "");
    const runUrl = runUrlOf(env.GITHUB_RUN_ID);
    const runId = /^[1-9][0-9]{0,14}$/.test(env.GITHUB_RUN_ID ?? "") ? env.GITHUB_RUN_ID : "";
    if (dimensionSkip === WORKFLOW_STALE) {
      const done = await refireStale(github, repo, issueNumber, {
        workflowSha: env.GITHUB_WORKFLOW_SHA,
        bot,
        appId,
        humans: readHumansOrNone(env.TRUSTED_ACTORS),
        limits: readLimits(resolvedConfigPath(env)),
        statusOf,
        field,
      });
      console.log(`report-outcome: issue #${issueNumber} stopped on stale workflow files; ${done}`);
      return 0;
    }
    if (dimensionSkip === OUTSIDE_AUTHOR) {
      const comments = await paginate(github, `${repo}/issues/${issueNumber}/comments`);
      const posted = comments.some((comment) => comment.user?.login === bot && parseOutcomeMarker(comment.body)?.outcome === OUTSIDE_AUTHOR);
      const plan = outsideAuthorPlan({ issueNumber, runUrl, runId });
      await applyHandBack(github, repo, posted ? { ...plan, comment: "" } : plan, { setStatus, leaveAgentReady, stateOf });
      return 0;
    }
    if (dimensionSkip) {
      const humanLabel = humanLabelFrom(env.TRACKER_CONFIG ?? ".base/docs/conventions/work-items.yaml");
      const plan = routeStop(dimensionSkip, { outcome: stopped(""), issueNumber, branch: "", humanLabel, runUrl, runId }, { why: DIMENSION_STEPS[dimensionSkip] });
      await finishStop(github, repo, plan, {
        bot,
        appId,
        humans: readHumansOrNone(env.TRUSTED_ACTORS),
        runId,
        limits: readLimits(resolvedConfigPath(env)),
        setStatus,
        leaveAgentReady,
        statusOf,
        stateOf,
        field,
      });
      return 0;
    }
    const dir = env.WORK_OUTCOME_DIR ?? "";
    const ran = readBranch(dir, issueNumber);
    const stale = readBranch(dir, issueNumber, "stale");
    if (stale) {
      await github("POST", `${repo}/issues/${issueNumber}/comments`, { body: staleComment(stale) }).then(
        () => console.log(`report-outcome: named the stale lane branch ${stale} on issue #${issueNumber}`),
        (error) => console.log(`report-outcome: could not name the stale lane branch ${stale}: ${error.message}`),
      );
    }
    let outcome = reuse && ran !== reuse ? null : readOutcome(join(dir, "work-outcome.json"));
    const refusal = !reuse && outcome?.unread && env.SCAN_REFUSED_DIR ? readScanRefusal(env.SCAN_REFUSED_DIR, env.GITHUB_RUN_ATTEMPT) : "";
    if (refusal) {
      outcome = { ...stopped(SCAN_REFUSALS[refusal]), unread: true, stop: `scan-refused-${refusal}` };
    }
    const branch = reuse || ran;
    const resumed = branch ? "" : readBranch(dir, issueNumber, "resume");
    const checkedBranch = branch || resumed;
    const checked = readChecks(env.RUNNER_CHECKS ?? "", { branch: checkedBranch });
    const limit = readLimit(dir);
    const turnCap = readTurnCap(dir);
    const overCap = readOverCap(dir);
    const funding = readFunding(dir);
    const issueStop = refusal ? null : readIssueStop(dir);
    const issue = await github("GET", `${repo}/issues/${issueNumber}`);
    const unreported = reuse && (outcome === null || outcome.unread);
    let summary = unreported && env.REUSE_SUMMARY_DIR ? readSummary(env.REUSE_SUMMARY_DIR, { issueNumber, branch: reuse }) : null;
    if (summary) {
      const ref = reuse.split("/").map(encodeURIComponent).join("/");
      const tip = await github("GET", `${repo}/git/ref/heads/${ref}`).then(
        (answer) => answer?.object?.sha,
        () => "",
      );
      if (tip !== summary.tip) {
        console.log(`report-outcome: ${reuse} is not at the tip the summary read, so the PR keeps the fixed text`);
        summary = null;
      }
    }
    const ownBranch = reuse !== "" || resumed !== "" || laneBranch(issueNumber).exec(branch)?.[1] === env.GITHUB_RUN_ID;
    let checks = checkedBranch && ownBranch && (unreported || outcome?.exit === "done") ? checked : null;
    if (checks) {
      const ref = checkedBranch.split("/").map(encodeURIComponent).join("/");
      const tip = await github("GET", `${repo}/git/ref/heads/${ref}`).then((answer) => answer?.object?.sha, () => "");
      if (tip !== checks.tip) {
        console.log(`report-outcome: ${checkedBranch} is not at the tip the runner checked, so its check results do not count`);
        checks = null;
      }
    }
    let base = "";
    let commits = null;
    const compare = async (head = branch) => {
      base = (await github("GET", repo)).default_branch;
      const comparison = await wholeCompare(
        (path) => github("GET", path),
        (path) => github("GET", path, undefined, { accept: DIFF }),
        `${repo}/compare/${encodeURIComponent(base)}...${encodeURIComponent(head)}`,
      );
      commits = listedCommits(comparison);
      return (comparison.files ?? []).flatMap((file) =>
        file.previous_filename ? [file.filename, file.previous_filename] : [file.filename],
      );
    };
    let changedFiles = outcome?.exit === "done" && branch ? await compare() : [];
    if (outcome?.exit === "done" && resumed && checks) {
      changedFiles = await compare(checks.tip);
      if (!allLaneCommits(commits, bot)) {
        console.log(`report-outcome: ${resumed} holds a commit that is not the lanes App's, so its check results do not count`);
        checks = null;
      }
    }
    const resolvedPath = resolvedConfigPath(env);
    const holdPaths = heldPaths(resolvedPath);
    const issueTitle = typeof issue.title === "string" ? issue.title : "";
    const issueLabels = (issue.labels ?? []).map((label) => label.name);
    const humanMerge =
      issueLabels.includes(HUMAN_MERGE_LABEL) &&
      (await paginate(github, `${repo}/issues/${issueNumber}/events`)
        .then((events) => trustedLabeler(events, HUMAN_MERGE_LABEL, { bot, humans: readHumans(env.TRUSTED_ACTORS ?? "") }), () => null)
        .catch(() => true));
    const listedHumans = () => readHumansOrNone(env.TRUSTED_ACTORS);
    const author = issue.user ?? {};
    const trustedIssue = (author.type === "User" && listedHumans().has(author.id)) || (author.type === "Bot" && author.login === bot);
    const linkage = trustedIssue ? linkageLines(issue.body, issueNumber) : [];
    const limits = readLimits(resolvedPath);
    const capped = !unreported && funding === null && turnCap !== null && outcome?.unread === true;
    const comments = capped ? await paginate(github, `${repo}/issues/${issueNumber}/comments`) : [];
    const turnCapRestarts = capped
      ? countTurnCapRestarts({
          comments,
          since: await humanSince(await field.events(issueNumber), field.id, listedHumans()),
          bot,
          runId,
        })
      : 0;
    const humanLabel = humanLabelFrom(env.TRACKER_CONFIG ?? ".base/docs/conventions/work-items.yaml");
    const unmarked =
      !unreported && outcome?.exit === "pushback"
        ? await paginate(github, `${repo}/issues/${issueNumber}/comments`)
            .then((list) => unmarkedAnswer(list, readHumans(env.TRUSTED_ACTORS ?? ""), bot))
            .catch(() => null)
        : null;
    let plan = unreported
      ? reusePlan({
          issueNumber,
          issueLabels,
          issueTitle,
          branch,
          runUrl,
          earlierRunUrl: runUrlOf(reused[1]),
          summary,
          changedFiles: await compare().catch(() => null),
          holdPaths,
          humanMerge,
          humanLabel,
          runId,
          humanPull,
          checks,
          linkage,
        })
      : decide({
          outcome,
          issueNumber,
          issueLabels,
          issueTitle,
          branch,
          resumed,
          changedFiles,
          holdPaths,
          humanMerge,
          humanLabel,
          runUrl,
          limit,
          turnCap,
          turnCapRestarts,
          overCap,
          funding,
          issueStop,
          limits,
          now,
          runId,
          checks,
          escalation,
          humanPull,
          unmarked,
          collectRefused: env.COLLECT_REFUSED === "true",
          linkage,
        });
    const lane = readLaneCredential(dir);
    plan = withCredential(plan, lane);
    if (plan.action === "open-pr") {
      plan = { ...plan, body: withRequiredSections(plan.body, requiredSections(env.SOURCE_CONTROL_CONFIG ?? ".base/docs/conventions/source-control.yaml")) };
    }
    if (plan.action === "turn-cap") {
      if (!postedThisRun(comments, { bot, outcome: "turn-cap", runId })) {
        await github("POST", `${repo}/issues/${issueNumber}/comments`, { body: plan.comment });
      }
      console.log(`report-outcome: issue #${issueNumber} reached its turn cap; work-unblock restarts it`);
      return 0;
    }
    if (plan.action === "limited" || plan.action === "funding") {
      const comments = await paginate(github, `${repo}/issues/${issueNumber}/comments`);
      if (!postedThisRun(comments, { bot, outcome: plan.action, runId: plan.runId })) {
        await github("POST", `${repo}/issues/${issueNumber}/comments`, { body: plan.comment });
      }
      console.log(
        plan.action === "funding"
          ? `report-outcome: issue #${issueNumber} stopped on the lane's funding; it waits`
          : `report-outcome: issue #${issueNumber} stopped on the usage limit; restart after ${plan.resets}`,
      );
      return 0;
    }
    if (plan.action === "open-pr" && humanMerge === null) {
      console.log(`::notice title=report-outcome::could not read who added ${HUMAN_MERGE_LABEL} to issue #${issueNumber}; no PR opens from ${plan.branch}, and a later run reads it again`);
      return 0;
    }
    if (plan.action === "open-pr") {
      const owner = env.GITHUB_REPOSITORY.split("/")[0];
      const findOpen = async () =>
        (await github("GET", `${repo}/pulls?state=open&head=${encodeURIComponent(`${owner}:${plan.branch}`)}`)).find(
          (candidate) => candidate.user?.login === bot,
        );
      let pull = await findOpen();
      const closer = pull
        ? undefined
        : trustedCloser(await closingPulls(github, { owner, name: env.GITHUB_REPOSITORY.split("/")[1], number: issueNumber }), {
            repo: env.GITHUB_REPOSITORY,
            bot,
            humans: listedHumans(),
          });
      if (closer) {
        console.log(`report-outcome: open PR #${closer.number} already closes issue #${issueNumber}, so no PR opens from ${plan.branch}`);
        plan = routeStop("closed-by-open-pr", {
          outcome: stopped(`Open PR #${closer.number} already closes this issue, so no second PR opened from \`${plan.branch}\`.`),
          issueNumber,
          branch: plan.branch,
          humanLabel,
          runUrl,
          runId,
        });
      } else {
        if (!pull) {
          const fields = { title: plan.title, body: plan.body, head: plan.branch, base: base || (await github("GET", repo)).default_branch, draft: false };
          try {
            pull = await github("POST", `${repo}/pulls`, fields);
          } catch (error) {
            if (!networkError(error)) {
              throw error;
            }
            pull = await findOpen();
            if (!pull) {
              throw new Error(`the PR create from ${plan.branch} failed on the network and no open PR from it reads back; the create is not sent again`, { cause: error });
            }
          }
        }
        const evalGated = issueLabels.includes(EVAL_GATED_LABEL);
        const alreadyHeld = (pull.labels ?? []).some((label) => label?.name === HOLD_LABEL);
        const labeled =
          !(plan.hold || evalGated) ||
          (await github("POST", `${repo}/issues/${pull.number}/labels`, { labels: [HOLD_LABEL] }, { safeToResend: true }).then(
            () => true,
            (error) => {
              console.log(`::warning title=report-outcome::could not label PR #${pull.number} ${HOLD_LABEL}: ${String(error?.message ?? error)}`);
              return false;
            },
          ));
        if (labeled && evalGated) {
          const body = evalHoldComment(issueNumber);
          const posted =
            alreadyHeld &&
            (await paginate(github, `${repo}/issues/${pull.number}/comments`).then(
              (all) => all.some((comment) => comment?.user?.login === bot && comment.body === body),
              () => false,
            ));
          if (!posted) {
            await github("POST", `${repo}/issues/${pull.number}/comments`, { body });
          }
        }
        const moved = Boolean(plan.tip) && pull.head?.sha !== plan.tip;
        if (labeled && !moved) {
          console.log(`report-outcome: opened PR #${pull.number} for issue #${issueNumber}`);
          return 0;
        }
        await github("PATCH", `${repo}/pulls/${pull.number}`, { state: "closed" }, { safeToResend: true });
        console.log(
          moved
            ? `report-outcome: closed PR #${pull.number}: its head is not ${plan.tip}, the tip the runner checked`
            : `report-outcome: closed PR #${pull.number}: it holds for a person and could not be labeled ${HOLD_LABEL}`,
        );
        plan = routeStop(moved ? "pr-head-moved" : "hold-label-failed", {
          outcome: stopped(
            moved
              ? `The PR from \`${plan.branch}\` opened at a head other than ${plan.tip}, the tip the runner checked, so it was closed.`
              : `The PR from \`${plan.branch}\` holds for a person, and the \`${HOLD_LABEL}\` label could not be added, so it was closed.`,
          ),
          issueNumber,
          branch: plan.branch,
          humanLabel,
          runUrl,
          runId,
        });
      }
    }
    await finishStop(github, repo, plan, { bot, appId, humans: listedHumans(), runId, limits, lane, verifyClose: env.VERIFY_CLOSE ?? "", setStatus, leaveAgentReady, statusOf, stateOf, field });
    return 0;
  } catch (error) {
    console.log(`::error title=report-outcome::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = process.argv[2] === "--find-prior" ? await findPriorMain() : await main(await baseStatus(process.env));
}
