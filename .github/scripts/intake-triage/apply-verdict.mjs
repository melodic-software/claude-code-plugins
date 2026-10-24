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
//   security and cost.
//
// It then adds the class label, sets the three issue fields (their ids from
// models.issue-dimensions, checked against the ids GitHub answers) and adds
// `status: ready` when all three fields and no flag parsed, no hold label
// (needs-human, status: needs-info, status: needs-decision) is on the issue,
// and nothing it found conflicts; otherwise `status: needs-decision` (unless a
// needs-info or needs-decision status is already there) and never
// `status: ready`; a `needs-triage` the triage left also keeps it from ready.
// The work class gates nothing (owner Q85, #9668) except
// `work-class: untrusted-provenance`, which holds the issue and is never taken
// off. Only the lanes App's own earlier class and field values give way to the
// new verdict; a field value anyone else set, or one whose setter cannot be
// read, is kept and sends the issue to needs-decision, and a class anyone else
// set is kept. A class that is not one of the repository's work-class labels
// is not applied. When it applied a class it rewrites the comment's
// "a maintainer confirms" lines. On `status: ready` it hands the verdict to
// admit.mjs, which adds `agent-ready` when the admission rules and the caps
// allow. Otherwise, when a done-when item is one the lane cannot perform,
// admit.mjs's noteUnrunnable posts the split it recommends.
//
// Issue text can only refuse: a line the model quotes is prefixed `> ` and
// matches nothing, a duplicated, missing or unknown value writes no fields, and
// an escalated run writes only needs-decision. It writes only on an open issue
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
import { admit, loadRules, noteUnrunnable } from "./admit.mjs";

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
const ESCALATED = "Automated triage handed this issue to a maintainer.";
export const DIMENSIONS = Object.freeze({
  size: "Size",
  complexity: "Complexity",
  uncertainty: "Uncertainty",
});
const FLAGS = new Set(["intent", "security", "cost"]);
// The one class that holds an issue for a person; the writer never takes it off.
const UNTRUSTED = "work-class: untrusted-provenance";
const CLASS_LINE = /^Proposed work class: (work-class: [a-z0-9-]+|none)$/;
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
  const escalated = String(body ?? "").includes(ESCALATED);
  const classMatch = CLASS_LINE.exec(lines[1] ?? "");
  const proposed = classMatch && classMatch[1] !== "none" && !escalated ? classMatch[1] : null;
  const workClass = proposed !== null && classes.has(proposed) ? proposed : null;

  const lineValue = (prefix) => {
    const found = lines.filter((line) => line.startsWith(`${prefix}: `)).map((line) => line.slice(prefix.length + 2).trim());
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
      problems.push(`\`${prefix}: ${value.slice(0, 40)}\` is not one of ${options.map(capitalize).join(", ")}`);
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
      problems.push(`\`Flags: ${flagText.slice(0, 40)}\` is not none or a list of ${[...FLAGS].join(", ")}`);
    }
  }
  return { escalated, workClass, dimensions, flags, problems };
}

// The writes the verdict calls for, given the issue's labels and its current
// field values ({fieldId: {option, setter}}). Pure.
// Whether an account id (a REST number, a GraphQL databaseId, or a string
// either way) is the lanes App's; never for an unknown id or App.
const isApp = (id, appId) => appId !== undefined && id !== undefined && id !== null && String(id) === String(appId);

export function planWrites(verdict, { labels, fields, dimensionsConfig, appId, humans = new Set(), classSetters = {} }) {
  const reasons = [...verdict.problems];
  const add = [];
  const remove = [];
  if (verdict.escalated) {
    reasons.push("the triage run escalated");
  }
  if (verdict.workClass === UNTRUSTED || labels.includes(UNTRUSTED)) {
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
    }
  }

  const fieldWrites = [];
  if (verdict.dimensions !== null) {
    for (const key of Object.keys(DIMENSIONS)) {
      const { "field-id": fieldId, options } = dimensionsConfig.fields[key];
      const optionId = Object.keys(options).find((id) => options[id] === verdict.dimensions[key]);
      const current = fields[String(fieldId)];
      if (current && String(current.option) !== optionId && !isApp(current.setter, appId)) {
        reasons.push(`${DIMENSIONS[key]} was set to another value by someone other than the lanes App`);
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
  const holds = labels.filter((label) => label === NEEDS_HUMAN || label === NEEDS_INFO || label === NEEDS_DECISION);
  if (holds.length > 0) {
    reasons.push(`held by ${holds.join(", ")}`);
  }
  if (labels.includes(NEEDS_TRIAGE)) {
    reasons.push(`the issue carries ${NEEDS_TRIAGE}`);
  }

  const ready = reasons.length === 0 && verdict.dimensions !== null && verdict.flags !== null;
  if (ready) {
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
  return { add, remove, fieldWrites, classApplied, ready, reasons };
}

// The lane comment with the maintainer-confirms wording replaced, or null when
// it has none.
export function rewordComment(body) {
  const next = body.replace(OLD_BASIS, NEW_BASIS).replace(OLD_FOOTER, NEW_FOOTER);
  return next === body ? null : next;
}

// {label: account id} for each work-class label on the issue: who added it
// last, from the issue's events; none when no event names it.
async function classSetters(github, base, labels) {
  const held = new Set(labels.filter((label) => label.startsWith("work-class:")));
  const setters = {};
  if (held.size === 0) {
    return setters;
  }
  for (const event of await paginate(github, `${base}/events`)) {
    if (event?.event === "labeled" && held.has(event.label?.name)) {
      setters[event.label.name] = event.actor?.id ?? null;
    }
  }
  return setters;
}

// {fieldId: {option, setter}} from the REST values and the GraphQL setters.
async function readFields(github, repository, number, fieldSetters) {
  const rows = await github("GET", `/repos/${repository}/issues/${number}/issue-field-values`, undefined, FIELD_API);
  const setters = await fieldSetters(github, repository, number);
  const fields = {};
  for (const row of Array.isArray(rows) ? rows : []) {
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
  if (!(humans.has(issue.user?.id) || (appId !== undefined && issue.user?.id === appId))) {
    log(`apply-verdict: #${number}'s author is neither a listed human nor the lanes App; nothing written`);
    return { outcome: "skipped" };
  }
  const lane = (await paginate(github, `${base}/comments`)).filter(
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
  const plan = planWrites(verdict, {
    labels,
    fields,
    dimensionsConfig,
    appId,
    humans,
    classSetters: await classSetters(github, base, labels),
  });

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
      await addLabels(github, base, labels.includes(NEEDS_DECISION) ? [] : [NEEDS_DECISION]);
      throw new Error(
        `GitHub kept other options than models.issue-dimensions maps for ${wrong.map(({ key }) => DIMENSIONS[key]).join(", ")}; the issue is set to ${NEEDS_DECISION}`,
      );
    }
  }
  for (const name of plan.remove) {
    try {
      await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`);
    } catch (error) {
      if (!(error instanceof GitHubError && error.status === 404)) {
        throw error;
      }
    }
  }
  await addLabels(github, base, plan.add);
  // Before the reword: whether the App may edit github-actions[bot]'s
  // comment is unproven, and a refused edit must not stop admission. An
  // admission error stops neither the reword nor the summary; the caller
  // fails the job on it.
  let admission = null;
  if (plan.ready && admitIssue) {
    try {
      admission = await admitIssue(verdict);
    } catch (error) {
      admission = { outcome: "error", reasons: [String(error?.message ?? error)] };
    }
  }
  // A held issue never reaches admission, so its split note, when a done-when
  // item is one the lane cannot perform, is written here.
  if (!plan.ready && noteSplit) {
    try {
      admission = await noteSplit(issue);
    } catch (error) {
      admission = { outcome: "error", reasons: [String(error?.message ?? error)] };
    }
  }
  if (plan.classApplied) {
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
    `- Labels added: ${plan.add.join(", ") || "none"}; removed: ${plan.remove.join(", ") || "none"}`,
    `- Status: ${plan.ready ? READY : NEEDS_DECISION}${plan.reasons.length ? ` (${plan.reasons.join("; ")})` : ""}`,
    ...(admission ? [`- Admission: ${admission.outcome}${admission.reasons.length ? ` (${admission.reasons.join("; ")})` : ""}`] : []),
  ].join("\n");
  log(summary);
  return { outcome: plan.ready ? "ready" : "needs-decision", plan, admission, summary };
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
      if (result.admission?.outcome === "error") {
        console.log(`::error title=apply-verdict::admission failed: ${result.admission.reasons[0].replaceAll(/[\r\n%]/g, " ")}`);
        process.exitCode = 1;
      }
    } catch (error) {
      console.log(`::error title=apply-verdict::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
      process.exitCode = 1;
    }
  }
}
