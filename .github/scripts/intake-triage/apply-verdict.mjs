#!/usr/bin/env node
// apply-verdict.mjs: writes intake triage's verdict on the issue it triaged, as
// the lanes App, so the work lanes count it. No model. It reads the lane
// comment the ci-workflows reusable posted (github-actions[bot], first line the
// marker) and takes:
//
// - the work class from the comment's second line, `Proposed work class:
//   <label>`, which the reusable enum-checks and writes `none` on an escalated run;
// - Size, Complexity and Uncertainty from lines that start the line with exactly
//   `Size: `, `Complexity: ` or `Uncertainty: `, each once, the value an option
//   name of models.issue-dimensions (its key, capitalized: Small, Knowable);
// - the flags from one `Flags: ` line, `none` or a comma list of intent,
//   security and cost;
// - the issues it depends on from one `Blocked by: ` line, `none` or a comma
//   list of `#<number>` (edges.mjs); a missing or unreadable line names none.
//
// It then adds the class label, sets the three issue fields (their ids from
// models.issue-dimensions, checked against the ids GitHub answers) and adds
// `status: ready` when all three fields and no flag parsed, no hold label
// (needs-human, status: needs-info, status: needs-decision) holds the issue,
// and nothing it found conflicts; otherwise `status: needs-decision` (unless a
// needs-info or needs-decision status is already there), removing a parked
// `status: confirmed` after the add so one status stands, never
// `status: ready`, and one lanes App comment, edited in place, that lists why.
// A status hold the lanes App set on an earlier run gives way to a ready
// verdict and is taken off only when the App's earlier verdict comment lists
// no flag. One that listed a flag, or no App verdict comment at all (an issue
// held before these comments), holds, and the new comment carries the flag or
// the missing record forward. A held verdict writes that comment before its
// labels and, when the comment write fails, adds no label and takes off only
// `status: ready`, so no hold lands without its record; needs-human, and
// a hold the triage run (github-actions[bot], the reusable's escalation), a
// person, or an unread setter set, holds. One exception: a needs-human or
// status: needs-decision this run's triage applied (github-actions[bot], at or after STARTED_AT) on a
// verdict that did not escalate, absent when the run started, with a readable
// `Flags: none`, no `Cost: ` line (a `Cost decided: ` one is fine) and no outside-actor or untrusted-provenance
// hold (read again right before the label writes), is refused and taken off when
// the rest of the plan is ready, so a capability limit (a host run, a paid
// eval) reaches admission, which routes it to `host-run` or holds it with a
// split, and a choice of means stays the issue lane's. The
// `needs-triage` floor label is taken off after the verdict is written.
// The work class gates nothing (owner Q85, #9668) except
// `work-class: untrusted-provenance`, which holds the issue and is never taken
// off. The lanes App's own earlier class and field values give way to the new
// verdict; a field value a listed human set is kept and is the value admission
// reads; one anyone else set, or one whose setter cannot be read, is kept and
// sends the issue to needs-decision; a class anyone else set is kept. A class
// that is not one of the repository's work-class labels is not applied. When
// it applied a class it rewrites the comment's "a maintainer confirms" lines.
// It writes a native blocked-by edge for each open issue of this repository
// the verdict or the issue body (edges.mjs textBlockers) names; an edge GitHub answers 403, 429 or 5xx for is missed,
// named in the summary and an annotation, the edges the run wrote are
// deleted again, and a ready verdict then lands
// without `status: ready` and is not admitted, so the hourly triage sweep runs
// intake again (a 403 also fails the job after every write). Then on
// `status: ready` it hands the verdict to admit.mjs,
// which adds `agent-ready` when the admission rules, the blockers and the caps
// allow. Otherwise, when a done-when item is one the lane cannot perform,
// admit.mjs's noteUnrunnable posts the split it recommends. An option GitHub
// keeps under another id than models.issue-dimensions maps fails the run and
// leaves the issue's labels as they are.
//
// Issue text can only refuse or hold back: a line the model quotes is prefixed
// `> ` and matches nothing, a duplicated, missing or unknown value writes no
// fields, the body's blockers add only edges to open issues, and an escalated
// run writes only needs-decision, its reasons and those edges; model text
// reaches a reason only as letters, digits and plain punctuation. It writes only on an open issue
// whose author is a listed human or the lanes App, and only from a lane
// comment updated at or after STARTED_AT (this run's), so a run whose triage
// wrote nothing never applies an older verdict.
//
// `--check` decides, before any token is requested, whether the broker would
// mint: the actor is a listed human, or github-actions[bot] on a dispatch; a
// re-run's triggering actor is a listed human.
//
// Environment:
//   GH_TOKEN              the lanes App token: issues write
//   GITHUB_REPOSITORY     owner/repo
//   GITHUB_API_URL
//   ISSUE_NUMBER          the triaged issue
//   STARTED_AT            when this run's first job started (ISO 8601)
//   TRUSTED_ACTORS_PATH   the default branch's trusted-actor list
//   BASE_PATH             the default branch checkout, for models.issue-dimensions
//   KILL_SWITCH           `proceed`, or the run stops before any API call
//   RESOLVED_CONFIG       resolve-config's output: the limits and wip leaves
//                         admission's cap check reads
//   EVENT_NAME, ACTOR_ID, TRIGGERING_ACTOR, RUN_ATTEMPT   for --check
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, GitHubError, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { checkWip, searchRateLimit } from "../../actions/check-wip-cap/check-wip-cap.mjs";
import { readLimits, readWip } from "../work-resolve-issue/limits.mjs";
import { admit, authorAdmitted, CONFIRMED, earlierFlags, EARLIER, isAppId as isApp, loadRules, noteUnrunnable, ownVerdict, UNRECORDED, UNTRUSTED, VERDICT_FLAGS as FLAGS, VERDICT_MARKER } from "./admit.mjs";
import { MAX_TEXT_BLOCKERS, parseBlockedBy, textBlockers, writeEdges } from "./edges.mjs";
import { OUTSIDE_ACTOR_LABEL } from "../pr-merge/merge-holds.mjs";

export const MARKER = "<!-- claude-lane intake-triage -->";
const LANE_BOT = "github-actions[bot]";
const ACTIONS_BOT_ID = 41898282;
export const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";
export const READY = "status: ready";
export const NEEDS_DECISION = "status: needs-decision";
const NEEDS_INFO = "status: needs-info";
const NEEDS_HUMAN = "needs-human";
// The reusable removes this floor label only from a triage it routed.
const NEEDS_TRIAGE = "needs-triage";
const HOLDS = new Set([NEEDS_HUMAN, NEEDS_INFO, NEEDS_DECISION, OUTSIDE_ACTOR_LABEL]);
// Holds a lanes App hold-lift never takes off; needs-human comes off only as
// a refused triage label (planWrites).
const PERSON_HOLDS = new Set([NEEDS_HUMAN, OUTSIDE_ACTOR_LABEL]);
// Holds this run's triage may apply only beside a flag (planWrites refuses one without).
const TRIAGE_REFUSABLE = [NEEDS_HUMAN, NEEDS_DECISION];
// Labels that stop admission for a person; a refusal is dropped when one
// lands after the first read.
const LATE_HOLDS = [OUTSIDE_ACTOR_LABEL, UNTRUSTED];
const ESCALATED = "Automated triage handed this issue to a maintainer.";
export const DIMENSIONS = Object.freeze({
  size: "Size",
  complexity: "Complexity",
  uncertainty: "Uncertainty",
});
const CLASS_LINE = /^Proposed work class: (work-class: [a-z0-9-]+|none)$/;
const LIST_MARKER = /^\s*(?:[-*+]|\d+[.)])\s+/;
const QUOTED = /^\s*(?:(?:[-*+]|\d+[.)])\s*)?>/;
// The two canonical shapes, bare or in `**Label:**` bold.
const COST_CANONICAL = /^(\*\*)?cost( decided)?:\1 (.+)$/i;
const NO_CHARGE = /^(?:none|n\/a|no charge|no cost)\.?$/i;
const COST_LABEL = /^\W*costs?(?!-(?:benefit|effective)\b)\s*[:\u2014\u2013(-]/i;
const COST_LABEL_TEXT = /^\W*costs?\s*(?:\([^)]*\))?\s*[:\u2014\u2013-]?\s*/i;
// The reusable's wording the verdict makes untrue once the class is applied.
export const OLD_BASIS = "Basis: automated intake triage; a maintainer confirms or changes it.";
export const NEW_BASIS = "Basis: automated intake triage; the lanes App applied this class.";
export const OLD_FOOTER = "<sub>Automated triage. A maintainer reviews it.</sub>";
export const NEW_FOOTER = "<sub>Automated triage, applied by the lanes App.</sub>";
const FIELD_API = { "X-GitHub-Api-Version": "2026-03-10" };
const NUMBER = /^[1-9][0-9]{0,9}$/;

const capitalize = (key) => key.charAt(0).toUpperCase() + key.slice(1);

// The --check answer: whether the broker would mint for this run's actors.
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

// The verdict the lane comment carries: {escalated, workClass, dimensions,
// flags, problems}. workClass is null for `none`; dimensions maps each key to
// its config key or is null; flags is a list or null. problems says why a part
// did not parse.
export function parseVerdict(body, dimensionsConfig, classes) {
  const lines = String(body ?? "").split("\n");
  const problems = [];
  const shown = {};
  const escalated = String(body ?? "").includes(ESCALATED);
  const classMatch = CLASS_LINE.exec(lines[1] ?? "");
  const proposed = classMatch && classMatch[1] !== "none" && !escalated ? classMatch[1] : null;
  const workClass = proposed !== null && classes.has(proposed) ? proposed : null;
  // The hold reads the proposal itself, so a missing label cannot drop it.
  const untrusted = proposed === UNTRUSTED;

  const lineValue = (prefix) => {
    const found = lines.filter((line) => line.startsWith(`${prefix}: `)).map((line) => line.slice(prefix.length + 2).trim());
    if (found.length === 1) {
      // Model text: only letters, digits and plain punctuation reach a reason.
      shown[prefix] = found[0].slice(0, 40).replaceAll(/[^A-Za-z0-9 ,.:-]/g, "?");
    }
    if (found.length !== 1) {
      problems.push(`${found.length === 0 ? "no" : "more than one"} \`${prefix}:\` line`);
      return null;
    }
    return found[0];
  };

  let dimensions = {};
  for (const [key, prefix] of Object.entries(DIMENSIONS)) {
    const value = lineValue(prefix);
    const options = Object.values(dimensionsConfig?.fields?.[key]?.options ?? {});
    const option = options.find((name) => capitalize(name) === value);
    if (value !== null && option === undefined) {
      problems.push(`\`${prefix}: ${shown[prefix]}\` is not one of ${options.map(capitalize).join(", ")}`);
    }
    dimensions[key] = option ?? null;
  }
  if (Object.values(dimensions).some((value) => value === null)) {
    dimensions = null;
  }

  let flags = null;
  const flagText = lineValue("Flags");
  if (flagText === "none") {
    flags = [];
  } else if (flagText !== null) {
    const list = flagText.split(",").map((flag) => flag.trim());
    if (list.every((flag) => FLAGS.has(flag)) && new Set(list).size === list.length) {
      flags = list;
    } else {
      problems.push(`\`Flags: ${shown.Flags}\` is not none or a list of ${[...FLAGS].join(", ")}`);
    }
  }
  // An unreadable line names no blocker and holds nothing: an unnamed edge is
  // a finding for review, not a stop.
  const { numbers, problem } = escalated || untrusted ? { numbers: [], problem: null } : parseBlockedBy(lines);
  // A verdict line, any case, past one list marker and with `*`, `_` and
  // backticks dropped: `Cost: <text>` names a charge an owner decides, whatever
  // Flags reads, unless <text> is only none, n/a, no charge or no cost
  // (any other text after it holds); `Cost decided: <text>` names one a recorded
  // decision covers and holds nothing. Only bare or `**Cost:**` dress counts as
  // that form: any other cost label (`**Cost**:`, `_Cost:_`, `Costs:`, `Cost —`,
  // `Cost (estimate):`) is a problem, which holds, unless its text is only a
  // no-charge phrase. A `>` quote, alone or after a list marker, is issue text;
  // `Costing:`, `Cost-benefit:`, `Cost-effective:` or `Estimated cost:` is not a
  // label; any other `Cost-<word>:` is.
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
    problems.push("a Cost line is not in the `Cost: ` / `Cost decided: ` form");
  }
  return { escalated, workClass, untrusted, cost, dimensions, flags, blockedBy: numbers, blockedByProblem: problem, problems };
}

// The writes the verdict calls for, given the issue's labels and its current
// field values ({fieldId: {option, setter}}). Pure.
export function planWrites(
  verdict,
  { labels, fields, dimensionsConfig, appId, humans = new Set(), classSetters = {}, holdSetters = {}, earlierFlags = [], triageLabels = [] },
) {
  const reasons = [...verdict.problems];
  const add = [];
  const remove = [];
  if (verdict.escalated) {
    reasons.push("the triage run escalated");
  }
  if (verdict.untrusted || labels.includes(UNTRUSTED)) {
    reasons.push(`${UNTRUSTED} work needs a person`);
  }

  let classApplied = false;
  if (verdict.workClass !== null) {
    const held = labels.filter((label) => label.startsWith("work-class:"));
    if (held.length === 0) {
      add.push(verdict.workClass);
      classApplied = true;
    } else if (held.length === 1 && held[0] === verdict.workClass) {
      classApplied = true;
    } else if (held.length === 1 && held[0] !== UNTRUSTED && isApp(classSetters[held[0]], appId)) {
      // Only the lanes App's own earlier class gives way; anyone else's,
      // or one no event names, is kept.
      remove.push(held[0]);
      add.push(verdict.workClass);
      classApplied = true;
    } else if (verdict.workClass === UNTRUSTED) {
      // A hold label is added beside any class already held.
      add.push(UNTRUSTED);
      classApplied = true;
    }
  }

  const fieldWrites = [];
  // The values admission reads: the verdict's, or a listed human's kept one.
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
        }
      } else if (current && String(current.option) !== optionId && !isApp(current.setter, appId)) {
        reasons.push(`${DIMENSIONS[key]} was set to another value by someone other than a listed human or the lanes App`);
      } else if (current && !isApp(current.setter, appId) && !humans.has(Number(current.setter))) {
        // The value matches, but the work lanes count it only when a listed
        // human or the lanes App set it (resolve-config dimensions.mjs).
        reasons.push(`${DIMENSIONS[key]} holds the verdict's value, but from a setter the work lanes do not count`);
      } else if (!current || String(current.option) !== optionId) {
        fieldWrites.push({
          key,
          fieldId,
          optionId: Number(optionId),
          name: capitalize(verdict.dimensions[key]),
        });
      }
    }
  }
  if (verdict.flags?.length) {
    reasons.push(`flagged: ${verdict.flags.join(", ")}`);
  }
  // A status hold the lanes App set on an earlier run gives way to this
  // verdict only when the App's earlier verdict comment lists no flag
  // (earlierFlags []); a listed flag or no readable comment (null) holds, as
  // does one the triage run (github-actions[bot]), a person, or an unread
  // setter set. needs-human and the outside-actor flag never give way here;
  // needs-human comes off only as a refused triage label, below.
  const holdReasons = (holds) => {
    const appHolds =
      earlierFlags === null || earlierFlags.length > 0
        ? []
        : holds.filter((label) => !PERSON_HOLDS.has(label) && isApp(holdSetters[label], appId));
    const found = holds.filter((label) => !appHolds.includes(label)).map((label) => `held by ${label}`);
    // Carried into the comment, so a later clean verdict still reads the flag,
    // or still reads that no record says.
    const carried = holds.length > 0 ? (earlierFlags ?? []).filter((flag) => !verdict.flags?.includes(flag)) : [];
    if (carried.length > 0) {
      found.push(`flagged: ${carried.join(", ")} ${EARLIER}`);
    }
    if (holds.length > 0 && earlierFlags === null) {
      found.push(UNRECORDED);
    }
    return { appHolds, found };
  };
  const isReady = (found) => reasons.length + found.length === 0 && verdict.dimensions !== null && verdict.flags !== null;
  // needs-human or status: needs-decision this run's triage applied on a
  // verdict whose Flags line reads none is refused when the rest of the plan
  // is ready: only a flag names a person reason, so admission routes the
  // capability limit or the agent decides the means. An unreadable Flags line,
  // a `Cost: ` line (not `Cost decided: `), an earlier verdict's flag, an outside-actor or
  // untrusted-provenance hold (flag.mjs adds needs-human as the same
  // github-actions[bot]), or any other reason keeps both.
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

  const ready = isReady([]);
  if (ready) {
    remove.push(...appHolds);
    if (!labels.includes(READY)) {
      add.push(READY);
    }
  } else {
    if (labels.includes(READY)) {
      remove.push(READY);
    }
    if (!labels.includes(NEEDS_DECISION) && !labels.includes(NEEDS_INFO)) {
      add.push(NEEDS_DECISION);
    }
  }
  // The verdict is the triage, so the floor label goes after it, and a held
  // verdict's hold replaces a parked status: confirmed: one status stands.
  const after = [NEEDS_TRIAGE, ...(ready ? [] : [CONFIRMED])].filter((name) => labels.includes(name));
  return { add, remove: [...remove, ...after], fieldWrites, classApplied, ready, reasons, dimensions, refused };
}

export { earlierFlags, ownVerdict, UNRECORDED, VERDICT_MARKER };

// The lane comment with the maintainer-confirms wording replaced, or null when
// it has none.
export function rewordComment(body) {
  const next = body.replace(OLD_BASIS, NEW_BASIS).replace(OLD_FOOTER, NEW_FOOTER);
  return next === body ? null : next;
}

// {setters, triage}: setters maps each work-class and hold label on the issue
// to who added it last, from the issue's events (none when no event names it);
// triage lists the ones this run's triage applied: absent at `since`, replaying
// labeled and unlabeled events by time and id (an add with an unreadable time
// counts as before it, a removal with one removes nothing), and added at or
// after it only by github-actions[bot].
async function labelSetters(github, base, labels, since) {
  const held = new Set(labels.filter((label) => label.startsWith("work-class:") || HOLDS.has(label)));
  const setters = {};
  if (held.size === 0) {
    return { setters, triage: [] };
  }
  const before = new Set();
  const bot = new Set();
  const other = new Set();
  // Replayed by (time, id); an unreadable time sorts last.
  const time = (event) => {
    const at = Date.parse(event?.created_at);
    return Number.isFinite(at) ? at : Number.POSITIVE_INFINITY;
  };
  const events = (await paginate(github, `${base}/events`)).toSorted(
    (a, b) => (time(a) === time(b) ? 0 : time(a) < time(b) ? -1 : 1) || (Number(a?.id) || 0) - (Number(b?.id) || 0),
  );
  for (const event of events) {
    const name = event?.label?.name;
    if (!held.has(name) || (event.event !== "labeled" && event.event !== "unlabeled")) {
      continue;
    }
    const readable = Number.isFinite(Date.parse(event.created_at));
    const after = readable && Date.parse(event.created_at) >= since;
    if (event.event === "unlabeled") {
      // An unreadable removal takes nothing off: the hold it may have
      // lifted still counts as there before this run.
      if (readable && !after) {
        before.delete(name);
      }
      continue;
    }
    setters[name] = event.actor?.id ?? null;
    if (!after) {
      before.add(name);
    } else if (setters[name] === ACTIONS_BOT_ID) {
      bot.add(name);
    } else {
      other.add(name);
    }
  }
  return { setters, triage: [...bot].filter((name) => !before.has(name) && !other.has(name)) };
}

// {fieldId: {option, setter}} from the REST values and the GraphQL setters.
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

export async function run({ env, github, dimensionsConfig, fieldSetters, admitIssue, noteSplit, log = console.log }) {
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
  if (!authorAdmitted(issue, humans, appId)) {
    log(`apply-verdict: #${number}'s author is neither a listed human nor the lanes App; nothing written`);
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

  const classes = new Set(
    (await paginate(github, `/repos/${repository}/labels`))
      .map((label) => label?.name)
      .filter((name) => typeof name === "string" && name.startsWith("work-class:")),
  );
  const verdict = parseVerdict(comment.body, dimensionsConfig, classes);
  const labels = (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));
  const fields = await readFields(github, repository, number, fieldSetters);
  const { setters, triage } = await labelSetters(github, base, labels, startedAt);
  const planFor = (current) =>
    planWrites(verdict, {
      labels: current,
      fields,
      dimensionsConfig,
      appId,
      humans,
      classSetters: setters,
      holdSetters: setters,
      earlierFlags: earlierFlags(comments, appId),
      triageLabels: triage,
    });
  let plan = planFor(labels);

  if (plan.fieldWrites.length > 0) {
    const written = await github(
      "POST",
      `${base}/issue-field-values`,
      {
        issue_field_values: plan.fieldWrites.map(({ fieldId, name }) => ({
          field_id: fieldId,
          value: name,
        })),
      },
      FIELD_API,
    );
    const answered = new Map((Array.isArray(written) ? written : []).map((row) => [row?.issue_field_id, row?.single_select_option?.id]));
    const wrong = plan.fieldWrites.filter(({ fieldId, optionId }) => answered.get(fieldId) !== optionId);
    if (wrong.length > 0) {
      // Config drift, not the issue's: the run fails and the issue keeps
      // its labels.
      throw new Error(
        `GitHub kept other options than models.issue-dimensions maps for ${wrong.map(({ key }) => DIMENSIONS[key]).join(", ")}; fix models.issue-dimensions and triage again`,
      );
    }
  }
  // Before any label, so admission reads them. Admission reads blockers only
  // from the native edges, so a missed one would be invisible to it: a ready
  // verdict then lands without `status: ready` and is not admitted, and the
  // hourly triage sweep (maintenance-audit-lane-runs/triage-sweep.mjs), which
  // dispatches intake on an issue with no `status:` label, runs it again.
  // writeEdges deletes the edges this run wrote when any misses, so
  // work-unblock never reads a partial set; the re-run writes them all.
  // The body's own `Blocked by` and `Depends on` lines count too, since
  // the model's line can leave them out (#8994); an escalated verdict
  // writes them, so a label added by hand later still finds the edge.
  const named = verdict.untrusted || labels.includes(UNTRUSTED) ? { numbers: [], dropped: 0 } : textBlockers(issue.body, repository);
  const blockers = [...new Set([...verdict.blockedBy, ...named.numbers])];
  const edges = blockers.length > 0 ? await writeEdges({ github, repository, number, blockers }) : null;
  if (named.dropped > 0) {
    log(`::warning title=apply-verdict::#${number}'s body names ${named.dropped} blocker(s) past the first ${MAX_TEXT_BLOCKERS}; no edge is written for them`);
  }
  // The outside-actor check (flag.mjs) can add its label and needs-human after
  // the first read, and admission never reads outside-actor, so a refusal
  // reads the labels once more, right before the label writes, and is
  // dropped when a late hold landed.
  if (plan.refused.length > 0) {
    const now = ((await github("GET", base)).labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));
    const late = LATE_HOLDS.filter((label) => now.includes(label) && !labels.includes(label));
    if (late.length > 0) {
      log(`apply-verdict: ${late.join(", ")} landed after the first read; nothing triage applied is refused`);
      plan = planFor([...new Set([...labels, ...late])]);
    }
  }
  const waits = plan.ready && (edges?.missed.length ?? 0) > 0;
  const add = waits ? plan.add.filter((name) => name !== READY) : plan.add;
  const remove = waits ? [...plan.remove, READY] : plan.remove;
  // A held verdict's reasons comment goes before its labels, so a hold never
  // lands without the record of whether it was flagged (earlierFlags): when
  // the comment write fails, no hold, class or floor label changes and the
  // caller fails the job; `status: ready` still comes off, since taking it off
  // adds no hold.
  // A ready verdict's comment names admission's outcome, so it goes after; a
  // failed one stops neither the reword nor the summary.
  let reasonsError = null;
  const edgeForbidden = forbidden(edges?.missed, edges?.undeleted);
  const say = async (admission) => {
    try {
      await sayReasons(github, repository, base, comments, appId, plan, admission, edgeForbidden);
    } catch (error) {
      reasonsError = String(error?.message ?? error);
    }
  };
  if (!plan.ready) {
    await say(null);
  }
  const labeled = reasonsError === null;
  const unready = remove.filter((name) => name === READY);
  if (labeled) {
    const late = remove.filter((name) => name === NEEDS_TRIAGE || name === CONFIRMED);
    await removeLabels(github, base, remove.filter((name) => !late.includes(name)));
    await addLabels(github, base, add);
    await removeLabels(github, base, late);
  } else {
    await removeLabels(github, base, unready);
  }
  // Before the reword: whether the App may edit github-actions[bot]'s
  // comment is unproven, and a refused edit must not stop admission. An
  // admission error stops neither the reword nor the summary; the caller
  // fails the job on it.
  let admission = waits ? { outcome: EDGE_MISSING, reasons: [`blocked-by edge ${missedEdges(edges.missed).join("; ")}`] } : null;
  if (plan.ready && admitIssue && !waits) {
    try {
      admission = await admitIssue({ ...verdict, dimensions: plan.dimensions, writtenAt: comment.updated_at });
    } catch (error) {
      admission = { outcome: "error", reasons: [String(error?.message ?? error)] };
    }
  }
  // A held issue never reaches admission, so its split note, when a done-when
  // item is one the lane cannot perform, is written here.
  if (!plan.ready && labeled && noteSplit) {
    try {
      admission = await noteSplit(issue);
    } catch (error) {
      admission = { outcome: "error", reasons: [String(error?.message ?? error)] };
    }
  }
  if (plan.ready) {
    await say(admission);
  }
  if (plan.classApplied && labeled) {
    const reworded = rewordComment(comment.body);
    if (reworded !== null) {
      await github("PATCH", `/repos/${repository}/issues/comments/${comment.id}`, { body: reworded });
    }
  }
  const summary = [
    "### intake-triage apply-verdict",
    "",
    `- Issue: #${number}`,
    `- Work class: ${verdict.workClass ?? "none"}${plan.classApplied ? "" : " (not applied)"}`,
    `- Fields written: ${plan.fieldWrites.map(({ key, name }) => `${DIMENSIONS[key]} ${name}`).join(", ") || "none"}`,
    labeled
      ? `- Labels added: ${add.join(", ") || "none"}; removed: ${remove.join(", ") || "none"}`
      : `- Labels added: none, since the reasons comment was not written; removed: ${unready.join(", ") || "none"}`,
    ...(plan.refused.length ? [`- Refused: ${refusedNote(plan.refused)}`] : []),
    `- Status: ${plan.ready ? (settled(admission) ?? READY) : NEEDS_DECISION}${plan.reasons.length ? ` (${plan.reasons.join("; ")})` : ""}`,
    ...(edges || verdict.blockedByProblem ? [`- Blocked by: ${edgeSummary(edges, verdict.blockedByProblem)}`] : []),
    ...(admission ? [`- Admission: ${admission.outcome}${admission.reasons.length ? ` (${admission.reasons.join("; ")})` : ""}`] : []),
    ...(reasonsError ? [`- Reasons comment: not written (${reasonsError})`] : []),
  ].join("\n");
  log(summary);
  return { outcome: plan.ready ? "ready" : "needs-decision", plan, admission, reasonsError, missed: edges?.missed ?? [], undeleted: edges?.undeleted ?? [], summary };
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

// What a 403 on a blocked-by edge means and how to grant the permission, for
// the annotation and the issue comment. GitHub has no separate dependencies
// permission: the blocked-by endpoints take the Issues repository permission,
// at write to add or delete an edge
// (https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps,
// read 2026-10-26). Label writes take Issues or Pull requests write; while
// intake-triage.yml grants this job pull-requests: read, labels that landed
// rule the permission in, so the 403 was a rate limit. An added permission
// takes effect once each account the App is installed on approves it
// (https://docs.github.com/en/apps/maintaining-github-apps/modifying-a-github-app-registration,
// read 2026-10-26).
export const FORBIDDEN_EDGE =
  "a 403 is a rate limit when this run's label writes landed, since this token makes them through the same grant, and intake's next run writes the edge; otherwise the lanes App lacks the Issues repository permission at write, which no re-run fixes. To grant it, the App's owner sets Issues to Read and write under Repository permissions on the App's Permissions & events settings page, then the owner of the account it is installed on approves the updated permissions";

// The annotation for missed edges, or null. A 403 is a missing permission,
// which no re-run fixes, or a rate limit: it fails the job, after every write.
// Either way a ready verdict waits without `status: ready` for the sweep. An
// edge the run wrote and could not delete after a miss is a partial set
// work-unblock reads: when that blocker closes first, it can admit the issue.
// A verdict that is not ready admits nothing and holds no `status: ready`
// back, so its missed edges only warn.
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

// Why a ready verdict took a triage hold off, for the comment and the summary.
const refusedNote = (refused) =>
  `${refused.map((label) => `\`${label}\``).join(", ")} came off: this run's triage applied ${refused.length > 1 ? "them" : "it"} with no intent, security or cost flag, and only a flag stops for a person: admission routes a capability limit (a host run, a paid eval), and the issue lane decides a choice of means.`;

// Admission's stand-in outcome when a blocked-by edge was missed.
const EDGE_MISSING = "waits for a blocked-by edge";
const WAITS = "none: admission waits for intake to run again, since a blocked-by edge is missing";

// Where a ready verdict leaves the issue after admission, when admission
// moved it off `status: ready` or did not finish; null when it stays ready.
const settled = (admission) =>
  admission?.outcome === "refused"
    ? (admission.status ?? NEEDS_DECISION)
    : admission?.outcome === "error"
      ? "not settled: admission did not finish"
      : admission?.outcome === EDGE_MISSING
        ? WAITS
        : null;

// One lanes App comment, edited in place, says why the verdict holds the
// issue; a later ready verdict marks it settled, naming the status admission
// left. None is posted for a ready verdict that stays ready and never held;
// one admission moved or did not finish gets the record a later run reads.
// A missing edge GitHub answered 403 for names the permission (refused); a
// 429 or 5xx does not, since the sweep's re-run writes it.
async function sayReasons(github, repository, base, comments, appId, plan, admission, refused) {
  const own = ownVerdict(comments, appId);
  const after = settled(admission);
  if (plan.ready && !own && after === null && plan.refused.length === 0) {
    return;
  }
  const body = plan.ready
    ? `${VERDICT_MARKER}\nThe latest triage verdict holds nothing: ${
        admission?.outcome === "refused"
          ? `admission moved the issue to \`${after}\`; its comment says why.`
          : after === WAITS
            ? `a blocked-by edge is missing, so the issue carries no \`status:\` label and admission waits for intake to run again, which the hourly triage sweep starts.${
                refused ? ` GitHub answered 403 for an edge, and ${FORBIDDEN_EDGE}.` : ""
              }`
            : after
              ? "admission did not finish, so the issue's status is not settled."
            : `the issue is at \`${READY}\`.`
      }${plan.refused.length ? `\n\n${refusedNote(plan.refused)}` : ""}`
    : [
        VERDICT_MARKER,
        `The triage verdict left this issue at \`${NEEDS_DECISION}\`:`,
        "",
        ...plan.reasons.map((reason) => `- ${reason}`),
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
    const proceed = checkActors(env, humans, logins);
    writeOutputs({ proceed: String(proceed) });
    console.log(`apply-verdict: the broker ${proceed ? "would" : "would not"} mint for this run's actors`);
  } else {
    try {
      const { issueDimensionsFromBase, issueLaneWebHostsFromBase, fieldSetters } = await import(
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
      // Read only when admitting, so a malformed rules file stops
      // admission and not the verdict.
      const admitIssue = (verdict) =>
        admit({
          github,
          repository,
          number: Number(env.ISSUE_NUMBER),
          verdict,
          rules: loadRules(`${env.BASE_PATH}/.github/actions/resolve-config/admission-rules.json`),
          humans,
          appId: logins.get(LANES_APP_LOGIN),
          webHosts: issueLaneWebHostsFromBase(env),
          status: () =>
            checkWip(github, {
              repo: repository,
              bot: LANES_APP_LOGIN,
              now: Date.now(),
              limits: readLimits(env.RESOLVED_CONFIG),
              wip: readWip(env.RESOLVED_CONFIG),
              remaining: rate.remaining,
            }),
        });
      const noteSplit = (issue) =>
        noteUnrunnable({
          github,
          repository,
          issue,
          rules: loadRules(`${env.BASE_PATH}/.github/actions/resolve-config/admission-rules.json`),
          webHosts: issueLaneWebHostsFromBase(env),
        });
      const result = await run({
        env,
        github,
        dimensionsConfig: issueDimensionsFromBase(env),
        fieldSetters,
        admitIssue,
        noteSplit,
      });
      if (result.summary && env.GITHUB_STEP_SUMMARY) {
        appendFileSync(env.GITHUB_STEP_SUMMARY, `${result.summary}\n`);
      }
      const missed = missedAnnotation(result.missed, result.undeleted, result.plan?.ready);
      if (missed) {
        console.log(missed.line);
        if (missed.fail) {
          process.exitCode = 1;
        }
      }
      if (result.admission?.outcome === "error") {
        console.log(`::error title=apply-verdict::admission failed: ${result.admission.reasons[0].replaceAll(/[\r\n%]/g, " ")}`);
        process.exitCode = 1;
      }
      if (result.reasonsError) {
        console.log(`::error title=apply-verdict::the reasons comment was not written: ${result.reasonsError.replaceAll(/[\r\n%]/g, " ")}`);
        process.exitCode = 1;
      }
    } catch (error) {
      console.log(`::error title=apply-verdict::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
      process.exitCode = 1;
    }
  }
}
