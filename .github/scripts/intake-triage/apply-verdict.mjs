#!/usr/bin/env node
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, GitHubError, isFault, paginate } from "../lib/github-client.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { checkWip, listedStatusOf, searchRateLimit } from "../../actions/check-wip-cap/check-wip-cap.mjs";
import { readLimits, readWip } from "../work-resolve-issue/limits.mjs";
import { ADMISSION_STATUS_READS, admit, authorTrust, CLEAR_ADMITTED, CLEAR_READY, CONFIRMED, earlierFlags, EARLIER, INTAKE_LANE, isAppId as isApp, judgedLine, loadRules, noteUnrunnable, ownVerdict, specOf, strongestReason, UNRECORDED, UNTRUSTED, VERDICT_CLEAR, VERDICT_FLAGS as FLAGS, VERDICT_MARKER } from "./admit.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { ACTIONS_BOT_ID, LANES_APP_LOGIN, NEEDS_DECISION, NEEDS_HUMAN, READY } from "../lib/lane-vocabulary.mjs";
import { personReasonLines } from "../lib/stop-reason.mjs";
import { MAX_TEXT_BLOCKERS, parseBlockedBy, textBlockers, writeEdges } from "./edges.mjs";
import { OUTSIDE_ACTOR_LABEL, UNTRUSTED_LABELS } from "../pr-merge/merge-holds.mjs";
import { FIELD_API, postOptionNames, statusWriter } from "../../actions/resolve-config/write-status.mjs";
import { carried, DECISION_LABELS, HOLD_STATES, INFO_LABELS, loadTrustedActors, statusEvents, statusReader } from "../../actions/resolve-config/read-status.mjs";

export { LANES_APP_LOGIN, NEEDS_DECISION, READY };
export const MARKER = "<!-- claude-lane intake-triage -->";
const LANE_BOT = "github-actions[bot]";
const NEEDS_TRIAGE = "needs-triage";
const HOLDS = new Set([NEEDS_HUMAN, ...INFO_LABELS, ...DECISION_LABELS, OUTSIDE_ACTOR_LABEL]);
const PERSON_HOLDS = new Set([NEEDS_HUMAN, OUTSIDE_ACTOR_LABEL]);
const TRIAGE_REFUSABLE = [NEEDS_HUMAN, ...DECISION_LABELS];
const LATE_HOLDS = [OUTSIDE_ACTOR_LABEL, ...UNTRUSTED_LABELS];
const ESCALATED = "Automated triage handed this issue to a maintainer.";
export const DIMENSIONS = Object.freeze({
  size: "Size",
  complexity: "Complexity",
  uncertainty: "Uncertainty",
});
const OPTION_ORDER = Object.freeze({
  size: ["small", "medium", "large"],
  complexity: ["low", "medium", "high"],
  uncertainty: ["known", "knowable", "unknown"],
});
const inReadingOrder = (key, names) => {
  const rank = (name) => {
    const index = OPTION_ORDER[key].indexOf(name.toLowerCase());
    return index === -1 ? OPTION_ORDER[key].length : index;
  };
  return names.toSorted((a, b) => rank(a) - rank(b));
};
const UNTRUSTED_FLAG = "untrusted";
const LIST_MARKER = /^\s*(?:[-*+]|\d+[.)])\s+/;
const QUOTED = /^\s*(?:(?:[-*+]|\d+[.)])\s*)?>/;
const COST_CANONICAL = /^(\*\*)?cost( decided)?:\1 (.+)$/i;
const NO_CHARGE = /^(?:none|n\/a|no charge|no cost)\.?$/i;
const COST_LABEL = /^\W*costs?(?!-(?:benefit|effective)\b)\s*[:\u2014\u2013(-]/i;
const COST_LABEL_TEXT = /^\W*costs?\s*(?:\([^)]*\))?\s*[:\u2014\u2013-]?\s*/i;
const COST_PROBLEM = "a Cost line is not in the `Cost: ` / `Cost decided: ` form";
const NUMBER = /^[1-9][0-9]{0,9}$/;

const labelNames = (issue) => (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));
const admissionError = (error) => ({ outcome: "error", reasons: [String(error?.message ?? error)], ...(isFault(error) ? { fault: true } : {}) });

export function checkActors(env, humans, logins) {
  if (!NUMBER.test(env.ACTOR_ID ?? "")) {
    return false;
  }
  const actor = Number(env.ACTOR_ID);
  const actorOk = humans.has(actor) || (env.EVENT_NAME === "workflow_dispatch" && actor === ACTIONS_BOT_ID);
  if (!actorOk) {
    return false;
  }
  if (env.RUN_ATTEMPT === "1") {
    return true;
  }
  const rerunner = logins.get(String(env.TRIGGERING_ACTOR ?? "").toLowerCase());
  return rerunner !== undefined && humans.has(rerunner);
}

export async function checkRun({ env, humans, logins, github, log = console.log }) {
  if (!checkActors(env, humans, logins)) {
    log("apply-verdict: the broker would not mint for this run's actors");
    return false;
  }
  if (!NUMBER.test(env.ISSUE_NUMBER ?? "")) {
    throw new Error(`ISSUE_NUMBER must be a positive number, not '${env.ISSUE_NUMBER}'`);
  }
  let issue;
  try {
    issue = await github("GET", `/repos/${env.GITHUB_REPOSITORY}/issues/${env.ISSUE_NUMBER}`);
  } catch (error) {
    log(`::warning::apply-verdict: #${env.ISSUE_NUMBER} could not be read (${error.name} ${error.status ?? ""}); the write step reads it again`);
    return true;
  }
  if (issue?.pull_request || issue?.state !== "open") {
    log(`::notice::apply-verdict: #${env.ISSUE_NUMBER} is not an open issue; no token requested, nothing written`);
    return false;
  }
  let trust;
  try {
    trust = await authorTrust(github, env.GITHUB_REPOSITORY, issue, humans, logins.get(LANES_APP_LOGIN));
  } catch (error) {
    log(`::warning::apply-verdict: #${env.ISSUE_NUMBER}'s drift-issue edit history could not be read (${error.name} ${error.status ?? ""}); the write step reads it again`);
    return true;
  }
  if (trust === null) {
    log(`::notice::apply-verdict: #${env.ISSUE_NUMBER}'s author is neither a listed human nor the lanes App, and it is no trusted upstream-drift issue; no token requested, nothing written`);
    return false;
  }
  log("apply-verdict: the broker would mint for this run's actors");
  return true;
}

export const knownFlags = (flags) => flags.every((flag) => FLAGS.has(flag) || flag === UNTRUSTED_FLAG) && new Set(flags).size === flags.length;

export function typedFlags(text) {
  let flags;
  try {
    flags = JSON.parse(String(text ?? ""))?.flags;
  } catch {
    return null;
  }
  return Array.isArray(flags) && knownFlags(flags) ? flags : null;
}

function typedVerdict(text, dimensionsConfig) {
  const flags = typedFlags(text);
  if (flags === null) {
    return null;
  }
  const value = JSON.parse(text);
  const dimensions = {};
  for (const key of Object.keys(DIMENSIONS)) {
    const options = Object.values(dimensionsConfig?.fields?.[key]?.options ?? {});
    const option = options.find((name) => typeof value[key] === "string" && name.toLowerCase() === value[key].toLowerCase());
    if (option === undefined) {
      return null;
    }
    dimensions[key] = option;
  }
  const blockedBy = value.blocked_by;
  if (!Array.isArray(blockedBy) || !blockedBy.every((number) => Number.isSafeInteger(number) && number > 0)) {
    return null;
  }
  return { dimensions, flags, blockedBy: [...new Set(blockedBy)] };
}

export function parseVerdict(body, dimensionsConfig, typedText = "") {
  const lines = String(body ?? "").split("\n");
  const problems = [];
  const shown = {};
  const escalated = String(body ?? "").includes(ESCALATED);

  const lineValue = (prefix) => {
    const found = lines.filter((line) => line.startsWith(`${prefix}: `)).map((line) => line.slice(prefix.length + 2).trim());
    if (found.length !== 1) {
      problems.push(`${found.length === 0 ? "no" : "more than one"} \`${prefix}:\` line`);
      return null;
    }
    shown[prefix] = found[0].slice(0, 40).replaceAll(/[^A-Za-z0-9 ,.:-]/g, "?");
    return found[0];
  };

  let dimensions = {};
  for (const [key, prefix] of Object.entries(DIMENSIONS)) {
    const value = lineValue(prefix);
    const options = Object.values(dimensionsConfig?.fields?.[key]?.options ?? {});
    const option = options.find((name) => name.toLowerCase() === value?.toLowerCase());
    if (value !== null && option === undefined) {
      problems.push(`\`${prefix}: ${shown[prefix]}\` is not one of ${inReadingOrder(key, options).join(", ")}`);
    }
    dimensions[key] = option ?? null;
  }
  if (Object.values(dimensions).some((value) => value === null)) {
    dimensions = null;
  }

  let flags = null;
  const untrusted = lines.some(
    (line) => line.startsWith("Flags: ") && line.slice("Flags: ".length).split(",").some((flag) => flag.trim() === UNTRUSTED_FLAG),
  );
  const beforeFlags = problems.length;
  const flagText = lineValue("Flags");
  if (flagText === "none") {
    flags = [];
  } else if (flagText !== null) {
    const list = flagText.split(",").map((flag) => flag.trim());
    if (knownFlags(list)) {
      flags = list.filter((flag) => flag !== UNTRUSTED_FLAG);
    } else {
      problems.push(`\`Flags: ${shown.Flags}\` is not none or a list of ${[...FLAGS, UNTRUSTED_FLAG].join(", ")}`);
    }
  }
  const flagsUnreadable = flags === null && lines.some((line) => line.startsWith("Flags: "));
  const flagProblems = flagsUnreadable ? problems.slice(beforeFlags) : [];
  const { numbers, problem } = escalated || untrusted ? { numbers: [], problem: null } : parseBlockedBy(lines);
  let cost = false;
  let costProblem = false;
  for (const line of lines) {
    if (QUOTED.test(line)) {
      continue;
    }
    const unlisted = line.replace(LIST_MARKER, "").trim();
    const canonical = COST_CANONICAL.exec(unlisted);
    const text = canonical?.[3].replaceAll(/[*_`]/g, "").trim();
    if (canonical && text) {
      cost ||= canonical[2] === undefined && !NO_CHARGE.test(text);
    } else {
      const bare = unlisted.replaceAll(/[*_`]/g, "");
      costProblem ||= COST_LABEL.test(bare) && !NO_CHARGE.test(bare.replace(COST_LABEL_TEXT, "").trim());
    }
  }
  if (costProblem) {
    problems.push(COST_PROBLEM);
  }
  const typed = typedVerdict(typedText, dimensionsConfig);
  if (typed === null) {
    return { escalated, untrusted, cost, dimensions, flags, blockedBy: numbers, blockedByProblem: problem, problems };
  }
  const anyUntrusted = untrusted || typed.flags.includes(UNTRUSTED_FLAG);
  return {
    escalated,
    untrusted: anyUntrusted,
    cost,
    dimensions: escalated ? dimensions : typed.dimensions,
    flags: flagsUnreadable ? null : [...new Set([...typed.flags.filter((flag) => flag !== UNTRUSTED_FLAG), ...(flags ?? [])])],
    blockedBy: escalated || anyUntrusted ? [] : typed.blockedBy,
    blockedByProblem: null,
    problems: [...flagProblems, ...(costProblem ? [COST_PROBLEM] : [])],
  };
}

export function planWrites(
  verdict,
  { labels, rawLabels = labels, fields, dimensionsConfig, appId, humans = new Set(), holdSetters = {}, earlierFlags = [], triageLabels = [] },
) {
  const had = (name) => labels.includes(name) || rawLabels.includes(name);
  const reasons = [...verdict.problems];
  const codes = new Set(verdict.problems.map((problem) => (problem === COST_PROBLEM ? "cost" : "intent")));
  const add = [];
  const remove = [];
  if (verdict.escalated) {
    reasons.push("the triage run escalated");
    codes.add("security");
  }
  if (verdict.untrusted || labels.some((label) => UNTRUSTED_LABELS.includes(label))) {
    reasons.push(`${UNTRUSTED} work needs a person`);
    codes.add("security");
  }
  if (verdict.untrusted && !labels.includes(UNTRUSTED)) {
    add.push(UNTRUSTED);
  }

  const fieldWrites = [];
  const dimensions = verdict.dimensions === null ? null : { ...verdict.dimensions };
  if (verdict.dimensions !== null) {
    for (const key of Object.keys(DIMENSIONS)) {
      const { "field-id": fieldId, options } = dimensionsConfig.fields[key];
      const optionId = Object.keys(options).find((id) => options[id] === verdict.dimensions[key]);
      const current = fields[String(fieldId)];
      if (current && String(current.option) !== optionId && humans.has(Number(current.setter))) {
        dimensions[key] = options[String(current.option)] ?? null;
        if (dimensions[key] === null) {
          reasons.push(`${DIMENSIONS[key]} holds an option models.issue-dimensions does not map`);
          codes.add("intent");
        }
      } else if (current && String(current.option) !== optionId && !isApp(current.setter, appId)) {
        reasons.push(`${DIMENSIONS[key]} was set to another value by someone other than a listed human or the lanes App`);
        codes.add("intent");
      } else if (current && !isApp(current.setter, appId) && !humans.has(Number(current.setter))) {
        reasons.push(`${DIMENSIONS[key]} holds the verdict's value, but from a setter the work lanes do not count`);
        codes.add("intent");
      } else if (!current || String(current.option) !== optionId) {
        fieldWrites.push({
          key,
          fieldId,
          optionId: Number(optionId),
          name: verdict.dimensions[key],
        });
      }
    }
  }
  if (verdict.flags?.length) {
    reasons.push(`flagged: ${verdict.flags.join(", ")}`);
    verdict.flags.forEach((flag) => codes.add(flag));
  }
  if (verdict.cost) {
    codes.add("cost");
  }
  const holdReasons = (holds) => {
    const appHolds =
      earlierFlags === null || earlierFlags.length > 0
        ? []
        : holds.filter((label) => !PERSON_HOLDS.has(label) && isApp(holdSetters[label], appId));
    const kept = holds.filter((label) => !appHolds.includes(label));
    const found = kept.map((label) => `held by ${label}`);
    const holdCodes = kept.map((label) => (label === OUTSIDE_ACTOR_LABEL ? "security" : "intent"));
    const carried = holds.length > 0 ? (earlierFlags ?? []).filter((flag) => !verdict.flags?.includes(flag)) : [];
    if (carried.length > 0) {
      found.push(`flagged: ${carried.join(", ")} ${EARLIER}`);
      holdCodes.push(...carried);
    }
    if (holds.length > 0 && earlierFlags === null) {
      found.push(UNRECORDED);
      holdCodes.push("intent");
    }
    return { appHolds, found, holdCodes };
  };
  const isReady = (found) => reasons.length + found.length === 0 && verdict.dimensions !== null && verdict.flags !== null;
  const holds = labels.filter((label) => HOLDS.has(label));
  const candidates =
    !verdict.escalated &&
    !verdict.untrusted &&
    !verdict.cost &&
    Array.isArray(verdict.flags) &&
    verdict.flags.length === 0 &&
    !(Array.isArray(earlierFlags) && earlierFlags.length > 0) &&
    !LATE_HOLDS.some((label) => labels.includes(label))
      ? TRIAGE_REFUSABLE.filter((label) => labels.includes(label) && triageLabels.includes(label))
      : [];
  let held = holdReasons(holds);
  let refused = [];
  if (candidates.length > 0) {
    const without = holdReasons(holds.filter((label) => !candidates.includes(label)));
    if (isReady(without.found)) {
      held = without;
      refused = candidates;
      remove.push(...candidates);
    }
  }
  const { appHolds } = held;
  reasons.push(...held.found);
  held.holdCodes.forEach((code) => codes.add(code));

  const ready = isReady([]);
  if (ready) {
    remove.push(...appHolds);
    if (!labels.includes(READY)) {
      add.push(READY);
    }
  } else {
    if (had(READY)) {
      remove.push(READY);
    }
    if (!carried(labels, DECISION_LABELS) && !carried(labels, INFO_LABELS)) {
      add.push(NEEDS_DECISION);
    }
  }
  const after = [NEEDS_TRIAGE, ...(ready ? [] : [CONFIRMED])].filter(had);
  const reason = ready ? null : (strongestReason(codes) ?? "intent");
  return { add, remove: [...remove, ...after], fieldWrites, ready, reasons, reason, dimensions, refused };
}

export { earlierFlags, ownVerdict, UNRECORDED, VERDICT_MARKER };

export function flagsAfterDecision(flags, own, kept, humans) {
  const since = Date.parse(raisedAt(own?.body) ?? own?.updated_at);
  const decided = Number.isFinite(since) && kept.some((item) => Date.parse(item.comment?.created_at) > since && isDecisionComment(item, humans));
  return decided && flags !== null ? flags.filter((flag) => flag !== "intent") : flags;
}

const RAISED = "<!-- intake-triage intent-raised-at ";
export function raisedAt(body) {
  const line = String(body ?? "").split("\n").find((l) => l.startsWith(RAISED) && l.endsWith(" -->"));
  return line ? line.slice(RAISED.length, -" -->".length) : null;
}

export function raisedLine(verdictFlags, writtenAt, earlierBody) {
  const at = verdictFlags?.includes("intent") ? writtenAt : raisedAt(earlierBody);
  return Number.isFinite(Date.parse(at)) ? [`${RAISED}${at} -->`] : [];
}

async function labelSetters(labels, since, events, appId) {
  const held = new Set(labels.filter((label) => HOLDS.has(label)));
  const setters = {};
  if (held.size === 0) {
    return { setters, triage: [] };
  }
  const before = new Set();
  const bot = new Set();
  const other = new Set();
  const time = (event) => {
    const at = Date.parse(event?.created_at);
    return Number.isFinite(at) ? at : Number.POSITIVE_INFINITY;
  };
  const history = (await events()).toSorted(
    (a, b) => (time(a) === time(b) ? 0 : time(a) < time(b) ? -1 : 1) || (Number(a?.id) || 0) - (Number(b?.id) || 0),
  );
  for (const event of history) {
    const name = event?.label?.name;
    if (!held.has(name) || (event.event !== "labeled" && event.event !== "unlabeled")) {
      continue;
    }
    const readable = Number.isFinite(Date.parse(event.created_at));
    const after = readable && Date.parse(event.created_at) >= since;
    if (event.event === "unlabeled") {
      if (readable && !after) {
        before.delete(name);
      }
      continue;
    }
    setters[name] = event.actor?.id ?? null;
    if (!after) {
      before.add(name);
    } else if (setters[name] === ACTIONS_BOT_ID || isApp(setters[name], appId)) {
      bot.add(name);
    } else {
      other.add(name);
    }
  }
  return { setters, triage: [...bot].filter((name) => !before.has(name) && !other.has(name)) };
}

async function readFields(github, repository, number, fieldSetters) {
  const rows = await github("GET", `/repos/${repository}/issues/${number}/issue-field-values`, undefined, FIELD_API);
  if (!Array.isArray(rows)) {
    throw new Error(`#${number}'s field values answered ${rows === null ? "null" : typeof rows}, not a list`);
  }
  const setters = await fieldSetters(github, repository, number);
  const fields = {};
  for (const row of rows) {
    if (row?.single_select_option?.id !== undefined) {
      fields[String(row.issue_field_id)] = {
        option: row.single_select_option.id,
        setter: setters[String(row.issue_field_id)] ?? null,
      };
    }
  }
  return fields;
}

export async function verdictStatus(labels, config) {
  const { collapseStatus } = await import("../../actions/resolve-config/issue-status.mjs");
  const state = collapseStatus(labels, config);
  return state === "agent-ready" ? null : state;
}

const STATUS_ADDS = new Set([READY, NEEDS_DECISION]);
const QUEUE_LABELS = new Set([READY, NEEDS_TRIAGE, CONFIRMED]);

export async function run({ env, github, dimensionsConfig, fieldSetters, admitIssue, noteSplit, setStatus = async () => {}, statusConfig = null, statusOf, log = console.log }) {
  if (env.KILL_SWITCH !== "proceed") {
    log("apply-verdict: the kill switch did not answer proceed; nothing read or written");
    return { outcome: "stopped" };
  }
  const repository = env.GITHUB_REPOSITORY;
  const number = Number(env.ISSUE_NUMBER);
  if (!NUMBER.test(env.ISSUE_NUMBER ?? "")) {
    throw new Error(`ISSUE_NUMBER must be a positive number, not '${env.ISSUE_NUMBER}'`);
  }
  const startedAt = Date.parse(env.STARTED_AT ?? "");
  if (!Number.isFinite(startedAt)) {
    throw new Error("STARTED_AT is not a time");
  }
  if (!dimensionsConfig?.fields) {
    throw new Error("the config sets no models.issue-dimensions");
  }
  const { humans, logins } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
  const appId = logins.get(LANES_APP_LOGIN);

  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  if (issue.pull_request || issue.state !== "open") {
    log(`apply-verdict: #${number} is not an open issue; nothing written`);
    return { outcome: "skipped" };
  }
  if ((await authorTrust(github, repository, issue, humans, appId)) === null) {
    log(`apply-verdict: #${number}'s author is neither a listed human nor the lanes App, and it is no trusted upstream-drift issue; nothing written`);
    return { outcome: "skipped" };
  }
  const comments = await paginate(github, `${base}/comments`);
  const lane = comments.filter(
    (comment) => comment.user?.login === LANE_BOT && comment.user?.type === "Bot" && String(comment.body ?? "").startsWith(MARKER),
  );
  if (lane.length !== 1) {
    throw new Error(`#${number} has ${lane.length} intake-triage lane comments, not one`);
  }
  const comment = lane[0];
  if (!(Date.parse(comment.updated_at) >= startedAt)) {
    throw new Error(`#${number}'s lane comment was last written before this run started; this run's triage wrote none`);
  }

  const verdict = parseVerdict(comment.body, dimensionsConfig, env.VERDICT);
  const issueLabels = labelNames(issue);
  const labels = statusOf ? await statusOf(number, issueLabels) : issueLabels;
  const fields = await readFields(github, repository, number, fieldSetters);
  const events = statusOf ? () => statusOf.events(number) : () => paginate(github, `${base}/events`);
  const { setters, triage } = await labelSetters(labels, startedAt, events, appId);
  let flagsBefore = earlierFlags(comments, appId);
  const own = ownVerdict(comments, appId);
  if (own && labels.some((label) => HOLDS.has(label)) && flagsBefore?.includes("intent")) {
    try {
      const { kept } = await selectTrustedIssueComments({ github, repository, issueNumber: number, ids: humans });
      flagsBefore = flagsAfterDecision(flagsBefore, own, kept, humans);
    } catch (error) {
      log(`apply-verdict: the recorded decisions on #${number} were not read (${String(error?.message ?? error)}); the earlier verdict's flags hold`);
    }
  }
  const planFor = (current) =>
    planWrites(verdict, {
      labels: current,
      rawLabels: issueLabels,
      fields,
      dimensionsConfig,
      appId,
      humans,
      holdSetters: setters,
      earlierFlags: flagsBefore,
      triageLabels: triage,
    });
  let plan = planFor(labels);

  if (plan.fieldWrites.length > 0) {
    const post = (issue_field_values) => github("POST", `${base}/issue-field-values`, { issue_field_values }, FIELD_API, { resendOnce: true });
    const written = await postOptionNames(
      post,
      plan.fieldWrites.map(({ fieldId, name }) => ({ field_id: fieldId, value: name })),
      new Set(plan.fieldWrites.map(({ fieldId }) => fieldId)),
      (line) => log(`apply-verdict: ${line}`),
    );
    const answered = new Map((Array.isArray(written) ? written : []).map((row) => [row?.issue_field_id, row?.single_select_option?.id]));
    const wrong = plan.fieldWrites.filter(({ fieldId, optionId }) => answered.get(fieldId) !== optionId);
    if (wrong.length > 0) {
      throw new Error(
        `GitHub kept other options than models.issue-dimensions maps for ${wrong.map(({ key }) => DIMENSIONS[key]).join(", ")}; fix models.issue-dimensions and triage again`,
      );
    }
  }
  const named = verdict.untrusted || labels.some((label) => UNTRUSTED_LABELS.includes(label)) ? { numbers: [], dropped: 0 } : textBlockers(issue.body, repository);
  const blockers = [...new Set([...verdict.blockedBy, ...named.numbers])];
  const edges = blockers.length > 0 ? await writeEdges({ github, repository, number, blockers }) : null;
  if (named.dropped > 0) {
    log(`::warning title=apply-verdict::#${number}'s body names ${named.dropped} blocker(s) past the first ${MAX_TEXT_BLOCKERS}; no edge is written for them`);
  }
  let lateHolds = [];
  if (plan.refused.length > 0) {
    const now = labelNames(await github("GET", base));
    lateHolds = LATE_HOLDS.filter((label) => now.includes(label) && !labels.includes(label));
    if (lateHolds.length > 0) {
      log(`apply-verdict: ${lateHolds.join(", ")} landed after the first read; nothing triage applied is refused`);
      plan = planFor([...new Set([...labels, ...lateHolds])]);
    }
  }
  const waits = plan.ready && (edges?.missed.length ?? 0) > 0;
  const add = waits ? plan.add.filter((name) => name !== READY) : plan.add;
  const remove = waits ? [...plan.remove, READY] : plan.remove;
  let reasonsError = null;
  const edgeForbidden = forbidden(edges?.missed, edges?.undeleted);
  const say = async (admission) => {
    try {
      await sayReasons(github, repository, base, comments, appId, plan, admission, edgeForbidden, raisedLine(verdict.flags, comment.updated_at, own?.body), () =>
        judgedText(github, repository, number, comment.updated_at),
      );
    } catch (error) {
      reasonsError = String(error?.message ?? error);
    }
  };
  if (!plan.ready) {
    await say(null);
  }
  const labeled = reasonsError === null;
  const unready = remove.filter((name) => name === READY);
  const off = new Set(labeled ? remove : unready);
  if (statusConfig && labels.includes("agent-ready") && (await statusOf?.unset?.(number))) {
    off.add("agent-ready");
  }
  const state = statusConfig && (await verdictStatus([...new Set([...labels, ...lateHolds, ...(labeled ? add : [])])].filter((name) => !off.has(name)), statusConfig));
  const field = String(statusConfig?.["field-id"]);
  const bots = statusConfig ? (await import("../../actions/resolve-config/issue-status.mjs")).statusBotSetters(loadTrustedActors(env), statusConfig) : [];
  const counted = (setter) => humans.has(setter) || isApp(setter, appId) || bots.some((entry) => entry.id === setter);
  const writeState = async () =>
    state ? setStatus(number, state, { fields: counted(fields[field]?.setter) ? { [field]: fields[field] } : {}, ...(HOLD_STATES.includes(state) ? {} : { keepHold: true }) }) : null;
  const labelAdds = add.filter((name) => !STATUS_ADDS.has(name));
  const labelRemoves = remove.filter((name) => !QUEUE_LABELS.has(name));
  if (labeled) {
    await removeLabels(github, base, labelRemoves);
    await addLabels(github, base, labelAdds);
  }
  const stateWrite = await writeState();
  const report = (admission, summary) => {
    log(summary);
    return { outcome: plan.ready ? "ready" : "needs-decision", plan, admission, reasonsError, missed: edges?.missed ?? [], undeleted: edges?.undeleted ?? [], summary };
  };
  if (stateWrite?.outcome === "held") {
    const why = `a person's Work status ${stateWrite.state} holds it`;
    return report({ outcome: "held", reasons: [why], status: stateWrite.state }, `apply-verdict: #${number} left as is (${why}); no admission`);
  }
  let admission = waits ? { outcome: EDGE_MISSING, reasons: [`blocked-by edge ${missedEdges(edges.missed).join("; ")}`] } : null;
  if (plan.ready && admitIssue && !waits) {
    try {
      const wrote = ["written", "unchanged"].includes(stateWrite?.outcome) ? stateWrite.state : undefined;
      admission = await admitIssue({ ...verdict, dimensions: plan.dimensions, writtenAt: comment.updated_at }, { wrote });
    } catch (error) {
      admission = admissionError(error);
    }
  }
  if (!plan.ready && labeled && noteSplit) {
    try {
      admission = await noteSplit(issue);
    } catch (error) {
      admission = admissionError(error);
    }
  }
  if (plan.ready) {
    await say(admission);
  }
  const summary = [
    "### intake-triage apply-verdict",
    "",
    `- Issue: #${number}`,
    `- Fields written: ${plan.fieldWrites.map(({ key, name }) => `${DIMENSIONS[key]} ${name}`).join(", ") || "none"}`,
    labeled
      ? `- Labels added: ${labelAdds.join(", ") || "none"}; removed: ${labelRemoves.join(", ") || "none"}`
      : "- Labels: none written, since the reasons comment was not written",
    ...(state ? [`- Work status: ${state}`] : []),
    ...(plan.refused.length ? [`- Refused: ${refusedNote(plan.refused)}`] : []),
    `- Status: ${plan.ready ? (settled(admission) ?? READY) : NEEDS_DECISION}${plan.reasons.length ? ` (${plan.reasons.join("; ")})` : ""}`,
    ...(edges || verdict.blockedByProblem ? [`- Blocked by: ${edgeSummary(edges, verdict.blockedByProblem)}`] : []),
    ...(admission ? [`- Admission: ${admission.outcome}${admission.reasons.length ? ` (${admission.reasons.join("; ")})` : ""}`] : []),
    ...(reasonsError ? [`- Reasons comment: not written (${reasonsError})`] : []),
  ].join("\n");
  return report(admission, summary);
}

async function removeLabels(github, base, names) {
  for (const name of names) {
    try {
      await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`);
    } catch (error) {
      if (!(error instanceof GitHubError && error.status === 404)) {
        throw error;
      }
    }
  }
}

const edgeSummary = (edges, problem) =>
  [
    ...(edges?.written.length ? [`${edges.written.map((n) => `#${n}`).join(", ")} written`] : []),
    ...(edges?.unwritten.length ? [`${edges.unwritten.map((n) => `#${n}`).join(", ")} written, then deleted, since an edge missed`] : []),
    ...undeletedEdges(edges?.undeleted ?? []),
    ...(edges?.skipped ?? []).map(({ number, why }) => `#${number} skipped (${why})`),
    ...missedEdges(edges?.missed ?? []),
    ...(problem ? [problem] : []),
  ].join("; ");

const missedEdges = (missed) => missed.map(({ number, status }) => `#${number} not written (GitHub answered ${status})`);
const undeletedEdges = (undeleted) => undeleted.map(({ number, status }) => `#${number} written and not deleted (GitHub answered ${status})`);
const forbidden = (missed = [], undeleted = []) => [...missed, ...undeleted].some(({ status }) => status === 403);

export const FORBIDDEN_EDGE =
  "a 403 is a rate limit when this run's label writes landed, since this token makes them through the same grant, and intake's next run writes the edge; otherwise the lanes App lacks the Issues repository permission at write, which no re-run fixes. To grant it, the App's owner sets Issues to Read and write under Repository permissions on the App's Permissions & events settings page, then the owner of the account it is installed on approves the updated permissions";

export function missedAnnotation(missed = [], undeleted = [], ready = true) {
  if (missed.length === 0) {
    return null;
  }
  const edges = [
    ...missedEdges(missed),
    ...(undeleted.length
      ? [`${undeletedEdges(undeleted).join("; ")}, so work-unblock can admit the issue when that blocker closes before intake runs again`]
      : []),
  ].join("; ");
  if (!ready) {
    return {
      fail: false,
      line: `::warning title=apply-verdict::blocked-by edges not written on a verdict that is not ready: ${edges}; the verdict's labels are written, and work-unblock, which reads only native edges, does not see ${undeleted.length ? "the blockers not written" : "these blockers"}`,
    };
  }
  return forbidden(missed, undeleted)
    ? {
        fail: true,
        line: `::error title=apply-verdict::blocked-by edges not written: ${edges}; ${FORBIDDEN_EDGE}. The verdict's labels are written without ${READY}, and admission waits for intake to run again`,
      }
    : {
        fail: false,
        line: `::warning title=apply-verdict::blocked-by edges not written: ${edges}; the verdict's labels are written without ${READY}, and admission waits until the hourly triage sweep runs intake again, which writes them`,
      };
}

export { isFault };

export function closing({ result, error } = {}) {
  const clean = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
  const held = (why) => `::notice title=apply-verdict::held: ${why}`;
  if (error !== undefined) {
    const why = clean(error?.message ?? error);
    return isFault(error) ? { lines: [held(why)], code: 0, held: true } : { lines: [`::error title=apply-verdict::${why}`], code: 1, held: false };
  }
  const lines = [];
  let code = 0;
  const missed = missedAnnotation(result.missed, result.undeleted, result.plan?.ready);
  if (missed) {
    lines.push(missed.line);
    code = missed.fail ? 1 : code;
  }
  if (result.admission?.outcome === "error") {
    const why = `admission failed: ${clean(result.admission.reasons[0])}`;
    lines.push(result.admission.fault ? held(why) : `::error title=apply-verdict::${why}`);
    code = result.admission.fault ? code : 1;
  }
  if (result.reasonsError) {
    lines.push(`::error title=apply-verdict::the reasons comment was not written: ${clean(result.reasonsError)}`);
    code = 1;
  }
  return { lines, code, held: Boolean(result.admission?.fault) };
}

export function finish({ lines, code, held }, { outputPath, log = console.log } = {}) {
  lines.forEach((line) => log(line));
  if (held && outputPath) {
    writeOutputs({ held: "true" }, outputPath);
  }
  return code;
}

const refusedNote = (refused) =>
  `${refused.map((label) => `\`${label}\``).join(", ")} came off: this run's triage applied ${refused.length > 1 ? "them" : "it"} with no intent, security or cost flag, and only a flag stops for a person: admission routes a capability limit (a host run, a paid eval), and the issue lane decides a choice of means.`;

const EDGE_MISSING = "waits for a blocked-by edge";
const WAITS = "none: admission waits for intake to run again, since a blocked-by edge is missing";

const settled = (admission) =>
  admission?.outcome === "refused" || admission?.outcome === "held"
    ? (admission.status ?? NEEDS_DECISION)
    : admission?.outcome === "error"
      ? "not settled: admission did not finish"
      : admission?.outcome === EDGE_MISSING
        ? WAITS
        : null;

// The triage-verdict brief, https://github.com/melodic-software/architecture/pull/167.
export async function judgedText(github, repository, number, judgedAt) {
  try {
    const spec = await specOf(github, repository, number);
    const judged = Date.parse(judgedAt);
    const edited = spec.lastEditedAt == null ? null : Date.parse(spec.lastEditedAt);
    return typeof spec.title === "string" && Number.isFinite(judged) && (edited === null || edited <= judged) ? { title: spec.title, body: spec.body } : null;
  } catch {
    return null;
  }
}

async function sayReasons(github, repository, base, comments, appId, plan, admission, refused, raised = [], judge = async () => null) {
  const own = ownVerdict(comments, appId);
  const after = settled(admission);
  const admissionSaid = admission?.outcome === "refused" && !HOLDS.has(after);
  if (plan.ready && !own && (after === null || admissionSaid) && plan.refused.length === 0) {
    return;
  }
  const judged = plan.ready && (after === null || admission?.outcome === "refused") ? await judge() : null;
  const stamp = judged ? `\n${judgedLine(judged)}` : "";
  const body = plan.ready
    ? `${VERDICT_MARKER}\n${VERDICT_CLEAR}${
        admission?.outcome === "refused"
          ? `${CLEAR_ADMITTED}${after}\`; its comment says why.`
          : admission?.outcome === "held"
            ? `a person set the Work status to \`${after}\`, which holds the issue.`
            : after === WAITS
            ? `a blocked-by edge is missing, so the issue carries no \`status:\` label and admission waits for intake to run again, which the hourly triage sweep starts.${
                refused ? ` GitHub answered 403 for an edge, and ${FORBIDDEN_EDGE}.` : ""
              }`
            : after
              ? "admission did not finish, so the issue's status is not settled."
            : `${CLEAR_READY}${READY}\`.`
      }${plan.refused.length ? `\n\n${refusedNote(plan.refused)}` : ""}${stamp}`
    : [
        VERDICT_MARKER,
        `The triage verdict left this issue at \`${NEEDS_DECISION}\`:`,
        "",
        ...plan.reasons.map((reason) => `- ${reason}`),
        "",
        ...raised,
        ...personReasonLines(INTAKE_LANE, plan.reason).toReversed(),
      ].join("\n");
  if (own?.body === body) {
    return;
  }
  if (own) {
    await github("PATCH", `/repos/${repository}/issues/comments/${own.id}`, { body });
  } else {
    await github("POST", `${base}/comments`, { body });
  }
}

async function addLabels(github, base, names) {
  if (names.length > 0) {
    await github("POST", `${base}/labels`, { labels: names });
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const env = process.env;
  if (process.argv[2] === "--check") {
    const { humans, logins } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const github = createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL });
    const proceed = await checkRun({ env, humans, logins, github });
    writeOutputs({ proceed: String(proceed) });
  } else {
    let closed;
    try {
      const { issueDimensionsFromBase, issueLaneWebHostsFromBase, issueStatusFromBase, issuesByStatus, fieldSetters } = await import(
        new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href
      );
      const rate = searchRateLimit();
      const github = createGitHub({
        token: env.GH_TOKEN,
        apiUrl: env.GITHUB_API_URL,
        onResponse: rate.onResponse,
      });
      const repository = env.GITHUB_REPOSITORY;
      const { humans, logins } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
      const { set: setStatus } = await statusWriter({ env, github, repository });
      const statusConfig = issueStatusFromBase(env);
      const trustedActors = loadTrustedActors(env);
      const listing = {
        issues: (states, options) => issuesByStatus(github, repository, states, { ...options, config: statusConfig, trustedActors }),
        events: (number) => statusEvents({ github, repository, number, config: statusConfig }),
      };
      const rules = () => loadRules(`${env.BASE_PATH}/.github/actions/resolve-config/admission-rules.json`);
      const admitIssue = (verdict, { wrote } = {}) =>
        admit({
          setStatus,
          listing,
          github,
          repository,
          number: Number(env.ISSUE_NUMBER),
          verdict,
          wrote,
          rules: rules(),
          humans,
          appId: logins.get(LANES_APP_LOGIN),
          webHosts: issueLaneWebHostsFromBase(env),
          statusOf: statusReader({ env, github, repository, limit: ADMISSION_STATUS_READS }),
          status: () =>
            checkWip(github, {
              repo: repository,
              bot: LANES_APP_LOGIN,
              now: Date.now(),
              limits: readLimits(env.RESOLVED_CONFIG),
              wip: readWip(env.RESOLVED_CONFIG),
              remaining: rate.remaining,
              statusOf: listedStatusOf({ env, github, repository }),
            }),
        });
      const noteSplit = (issue) =>
        noteUnrunnable({
          github,
          repository,
          issue,
          rules: rules(),
          webHosts: issueLaneWebHostsFromBase(env),
          statusOf: statusReader({ env, github, repository }),
        });
      const result = await run({
        env,
        github,
        dimensionsConfig: issueDimensionsFromBase(env),
        fieldSetters,
        admitIssue,
        noteSplit,
        setStatus,
        statusConfig,
        statusOf: statusReader({ env, github, repository }),
      });
      if (result.summary && env.GITHUB_STEP_SUMMARY) {
        appendFileSync(env.GITHUB_STEP_SUMMARY, `${result.summary}\n`);
      }
      closed = closing({ result });
    } catch (error) {
      closed = closing({ error });
    }
    process.exitCode = finish(closed, { outputPath: env.GITHUB_OUTPUT });
  }
}
