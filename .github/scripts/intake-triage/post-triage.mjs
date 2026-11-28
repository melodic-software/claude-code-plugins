#!/usr/bin/env node
import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { checkVerdict } from "../../../plugins/work-items/skills/triage/scripts/check-ci-verdict.mjs";
import { createGitHub, paginate } from "../lib/github-client.mjs";

export const MARKER = "<!-- claude-lane intake-triage -->";
export const FOOTER = "<sub>Automated triage. A maintainer reviews it.</sub>";
export const ESCALATED_NOTE = "Thanks for the report. Automated triage handed this issue to a maintainer.";
export const DEFERRED = "permission denial(s) on an otherwise clean triage";
export const CREDENTIAL = /(sk-ant-[A-Za-z0-9_-]{8,}|gh[opsur]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)/u;
const LANE_BOT = "github-actions[bot]";
const COMMENT_CAP = 3000;
const PERSON_NEEDED = ["needs-owner-decision", "needs-reporter-info", "area: security"];
const FIELD_API = { "X-GitHub-Api-Version": "2026-03-10" };
const TYPES_QUERY = "query($owner: String!, $repo: String!) { repository(owner: $owner, name: $repo) { issueTypes(first: 25) { nodes { id name isEnabled } } } }";
const SET_TYPE = "mutation($id: ID!, $type: ID!) { updateIssue(input: { id: $id, issueTypeId: $type }) { issue { issueType { name } } } }";
const FIELD_HISTORY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) {
    timelineItems(last: 100, itemTypes: [ISSUE_FIELD_ADDED_EVENT, ISSUE_FIELD_CHANGED_EVENT]) { nodes {
      ... on IssueFieldAddedEvent { actor { ...who } issueField { ...field } }
      ... on IssueFieldChangedEvent { actor { ...who } issueField { ...field } }
    } }
  } }
}
fragment who on Actor { __typename ... on User { databaseId } }
fragment field on IssueFields { ... on IssueFieldSingleSelect { fullDatabaseId } }`;

export const isAdmission = (label) => label === "agent-ready" || label === "provenance: untrusted" || label.startsWith("work-class:");
export const breakMentions = (text) => text.replace(/@(?=[A-Za-z0-9])/gu, "@​");
const labelName = (label) => (typeof label === "string" ? label : label?.name);

export function readDenials(path) {
  try {
    const value = JSON.parse(readFileSync(path, "utf8"))?.denied_total;
    return Number.isSafeInteger(value) && value >= 0 ? value : Number.NaN;
  } catch {
    return Number.NaN;
  }
}

export function plan({ verdict, allowed, escalationLabel }) {
  const escalate = [];
  if (verdict.needs_human) escalate.push("the model asked for a person");
  const labels = new Set();
  const rejected = [];
  for (const label of verdict.labels) {
    if (allowed.has(label)) labels.add(label);
    else rejected.push(String(label).slice(0, 100));
  }
  let comment = verdict.comment.trim().slice(0, COMMENT_CAP);
  if (CREDENTIAL.test(comment)) escalate.push("the comment looked like it carried a credential");
  comment = breakMentions(comment);
  if (escalate.length > 0) {
    labels.clear();
    labels.add(escalationLabel);
    comment = ESCALATED_NOTE;
  }
  return { labels, rejected, comment, escalate, escalated: escalate.length > 0 };
}

export const laneBody = (comment) => [MARKER, comment, FOOTER].join("\n\n");

export const SUMMARY_HEADING = "### intake-triage / post-triage";
export const MAX_BULLETS = 5;

export function renderSummary(verdictLine, bullets = [], details = []) {
  const lines = [SUMMARY_HEADING, "", verdictLine];
  if (bullets.length > 0) lines.push("", ...bullets.slice(0, MAX_BULLETS).map((line) => `- ${line}`));
  const rest = [...bullets.slice(MAX_BULLETS), ...details];
  if (rest.length > 0) lines.push("", "<details><summary>Diagnostics</summary>", "", ...rest.map((line) => `- ${line}`), "", "</details>");
  return lines;
}

export async function main({ env = process.env, github, log = console.log } = {}) {
  const output = (name, value) => env.GITHUB_OUTPUT && appendFileSync(env.GITHUB_OUTPUT, `${name}=${value}\n`);
  const summary = (lines) => env.GITHUB_STEP_SUMMARY && appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  if (!/^[1-9][0-9]{0,9}$/u.test(env.ISSUE_NUMBER ?? "") || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(env.GITHUB_REPOSITORY ?? "")) {
    log("::error::ISSUE_NUMBER or GITHUB_REPOSITORY is malformed");
    return 1;
  }
  let verdict;
  try {
    verdict = JSON.parse(readFileSync(env.VERDICT_FILE, "utf8"));
  } catch (error) {
    log(`::error::the verdict file is unreadable: ${error.message}; nothing applied`);
    summary(renderSummary("Not applied: the verdict file is unreadable."));
    return 1;
  }
  const problems = checkVerdict(verdict);
  if (problems.length > 0) {
    log(`::error::the verdict fails check-ci-verdict: ${problems.join("; ")}; nothing applied`);
    summary(renderSummary("Not applied: the verdict fails check-ci-verdict.", [], problems));
    return 1;
  }
  const denials = readDenials(env.ACT_TURNS_FILE ?? "");
  if (denials > 0) {
    log(`::warning::${denials} ${DEFERRED}: nothing applied, so a later triage run retries the issue.`);
    output("deferred", "true");
    summary(renderSummary(`Deferred: ${denials} permission denial(s) on an otherwise clean triage; nothing applied, and a later run retries the issue.`));
    return 0;
  }

  const [owner, repo] = env.GITHUB_REPOSITORY.split("/");
  const repoPath = `/repos/${owner}/${repo}`;
  const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
  const graphql = async (query, variables) => (await client("POST", "/graphql", { query, variables }))?.data;
  const issue_number = Number(env.ISSUE_NUMBER);
  const issue = await client("GET", `${repoPath}/issues/${issue_number}`);
  if (issue?.pull_request) {
    log(`::error::#${issue_number} is a pull request, not an issue`);
    return 1;
  }

  const live = new Set((await paginate(client, `${repoPath}/labels`)).map((label) => label.name));
  const escalationLabel = env.ESCALATION_LABEL || "needs-human";
  if (!live.has(escalationLabel) || isAdmission(escalationLabel)) {
    log(`::error::escalation label '${escalationLabel}' does not exist in this repository or is an admission label`);
    return 1;
  }
  const PRIORITY_FIELD = /^[1-9][0-9]{0,9}$/u.test(env.PRIORITY_FIELD_ID ?? "") ? Number(env.PRIORITY_FIELD_ID) : 0;
  const offered = (label) => live.has(label) || (PRIORITY_FIELD > 0 && label.startsWith("priority: "));
  const allowed = new Set(
    String(env.ALLOWED_LABELS ?? "")
      .split("\n")
      .map((label) => label.trim())
      .filter((label) => label && offered(label) && !label.includes("'") && !isAdmission(label)),
  );
  let floor = env.FLOOR_LABEL ?? "";
  if (floor && isAdmission(floor)) {
    log(`::error::floor label '${floor}' is an admission label`);
    return 1;
  }
  if (floor && !live.has(floor)) floor = "";
  let types = {};
  try {
    const data = await graphql(TYPES_QUERY, { owner, repo });
    types = Object.fromEntries(
      (data?.repository?.issueTypes?.nodes ?? [])
        .filter((t) => t?.isEnabled && typeof t.name === "string" && !t.name.includes("'") && t.name.trim().toLowerCase() !== "none")
        .map((t) => [t.name, t.id]),
    );
  } catch (error) {
    log(`::warning::Issue Types unreadable, so the lane sets none: ${error.message}`);
  }

  const { labels, rejected, escalate, escalated, comment: planned } = plan({ verdict, allowed, escalationLabel });
  if (Number.isNaN(denials)) {
    escalate.push("an unreadable number of permission denials");
    labels.clear();
    labels.add(escalationLabel);
  }
  const isEscalated = escalated || Number.isNaN(denials);
  const comment = isEscalated ? ESCALATED_NOTE : planned;
  const wanted = typeof verdict.type === "string" ? verdict.type : "";
  const usable = Object.hasOwn(types, wanted);

  const priorities = [...labels].filter((label) => label.startsWith("priority:"));
  const people = /^[^,]+(,[^,]+)*$/u.test(env.AUTHOR_IDS ?? "") ? new Set(env.AUTHOR_IDS.split(",")) : new Set();
  const held = (issue.labels ?? []).map(labelName).filter((name) => typeof name === "string");
  const replaced = [];
  const exclusive = [];
  let failure;
  const FIELD_VALUES = `${repoPath}/issues/${issue_number}/issue-field-values`;
  const priorityOf = (rows) => (Array.isArray(rows) ? rows : []).find((row) => row?.issue_field_id === PRIORITY_FIELD)?.single_select_option?.name ?? "";
  let fieldReadable = false;
  let priorityOption = "";
  if (PRIORITY_FIELD && priorities.length === 1) {
    try {
      priorityOption = priorityOf(await client("GET", `${FIELD_VALUES}?per_page=100`, undefined, FIELD_API));
      fieldReadable = true;
    } catch (error) {
      log(`::warning::The Priority field could not be read, so priority stays on labels: ${error.message}`);
    }
  }
  const fieldSetByPerson = async () => {
    try {
      const data = await graphql(FIELD_HISTORY, { owner, name: repo, number: issue_number });
      const last = (data?.repository?.issue?.timelineItems?.nodes ?? []).filter((node) => String(node?.issueField?.fullDatabaseId) === String(PRIORITY_FIELD)).at(-1);
      return last?.actor?.__typename === "User" && people.has(String(last.actor.databaseId));
    } catch (error) {
      log(`::warning::The Priority field's history could not be read, so its value stands: ${error.message}`);
      return true;
    }
  };
  let priorityPick = "";
  let priorityLost = false;
  let commentPosted = false;
  try {
    const body = laneBody(comment);
    const earlier = (await paginate(client, `${repoPath}/issues/${issue_number}/comments`)).find(
      (c) => c.user?.login === LANE_BOT && String(c.body ?? "").startsWith(MARKER),
    );
    if (earlier) await client("PATCH", `${repoPath}/issues/comments/${earlier.id}`, { body });
    else await client("POST", `${repoPath}/issues/${issue_number}/comments`, { body });
    commentPosted = true;
    const picks = [...labels].filter((label) => label.startsWith("priority:"));
    for (const label of picks) labels.delete(label);
    if (picks.length > 1) exclusive.push(`${picks.join(" and ")} picked, neither applied`);
    else if (picks.length === 1 && priorityOption) {
      const current = `priority: ${priorityOption}`;
      if (current === picks[0]) exclusive.push(`kept ${current}`);
      else if (await fieldSetByPerson()) exclusive.push(`kept ${current}, set by a listed person, over ${picks[0]}`);
      else {
        priorityPick = picks[0];
        replaced.push(...held.filter((label) => label.startsWith("priority:")));
      }
    } else if (picks.length === 1) {
      const on = held.filter((label) => label.startsWith("priority:"));
      if (on.length === 0) priorityPick = picks[0];
      else {
        const setters = new Map();
        (await paginate(client, `${repoPath}/issues/${issue_number}/events`)).forEach((event, at) => {
          if (event.event === "labeled" && typeof event.label?.name === "string") setters.set(event.label.name, { actor: event.actor, at });
        });
        const byPerson = (label) => {
          const actor = setters.get(label)?.actor;
          return actor?.type === "User" && Number.isInteger(actor.id) && people.has(String(actor.id));
        };
        const keep = on.filter(byPerson).sort((a, b) => setters.get(b).at - setters.get(a).at)[0] ?? picks[0];
        if (on.includes(keep)) exclusive.push(`kept ${keep}${keep === picks[0] ? "" : `, set by a listed person, over ${picks[0]}`}`);
        else priorityPick = keep;
        replaced.push(...on.filter((label) => label !== keep));
      }
    }
    if (priorityPick) {
      const value = priorityPick.slice("priority: ".length);
      let written = "";
      if (fieldReadable) {
        try {
          written = priorityOf(await client("POST", FIELD_VALUES, { issue_field_values: [{ field_id: PRIORITY_FIELD, value }] }, FIELD_API));
          if (written !== value) log(`::warning::GitHub kept Priority '${written}', not '${value}'.`);
        } catch (error) {
          log(`::warning::The Priority field was not set: ${error.message}`);
        }
      }
      if (written === value) exclusive.push(`field set to ${value}`);
      else if (live.has(priorityPick)) labels.add(priorityPick);
      else {
        priorityLost = true;
        replaced.length = 0;
        log(`::warning::Neither the Priority field nor label '${priorityPick}' could carry the pick.`);
      }
    }
    if (labels.size > 0) await client("POST", `${repoPath}/issues/${issue_number}/labels`, { labels: [...labels] });
    for (const name of replaced) {
      try {
        await client("DELETE", `${repoPath}/issues/${issue_number}/labels/${encodeURIComponent(name)}`);
      } catch (error) {
        if (error.status !== 404) throw error;
      }
    }
  } catch (error) {
    failure = error;
  }

  const personNeeded = [...labels].some((label) => label.startsWith("status:") || PERSON_NEEDED.includes(label));
  const routed = isEscalated || (priorities.length === 1 && !priorityLost && !personNeeded);
  const existingType = typeof issue.type?.name === "string" ? issue.type.name : "";
  let typeSet = !failure && usable && existingType ? existingType : "";
  let typeFailure;
  let typeDropped = false;
  if (!failure && usable && !existingType) {
    try {
      const data = await graphql(SET_TYPE, { id: issue.node_id, type: types[wanted] });
      if (data?.updateIssue?.issue?.issueType?.name === wanted) typeSet = wanted;
      else {
        typeDropped = true;
        log(`::warning::GitHub did not keep Issue Type '${wanted}'; the token may not be allowed to set types.`);
      }
    } catch (error) {
      typeFailure = error;
    }
  }
  let floorCleared = false;
  let floorAdded = false;
  if (!failure && floor) {
    try {
      if (typeSet && routed && !labels.has(floor)) {
        try {
          await client("DELETE", `${repoPath}/issues/${issue_number}/labels/${encodeURIComponent(floor)}`);
          floorCleared = true;
        } catch (error) {
          if (error.status !== 404) throw error;
        }
      } else if (!labels.has(floor)) {
        let exists = true;
        try {
          await client("GET", `${repoPath}/labels/${encodeURIComponent(floor)}`);
        } catch (error) {
          if (error.status !== 404) throw error;
          exists = false;
          log(`::warning::Floor label '${floor}' no longer exists; not adding it.`);
        }
        if (exists) {
          await client("POST", `${repoPath}/issues/${issue_number}/labels`, { labels: [floor] });
          floorAdded = true;
        }
      }
    } catch (error) {
      failure = error;
    }
  }
  failure ??= typeFailure;

  const landed = !failure && !priorityLost && !typeDropped;
  const verdictLine = failure
    ? commentPosted
      ? `Failed: the lane comment posted, but a write did not land (${failure.message}).`
      : `Failed: the lane comment did not post (${failure.message}); nothing else was written.`
    : isEscalated
      ? `Escalated: handed to a maintainer with ${escalationLabel} and the fixed note (${escalate.join("; ")}).`
      : !landed
        ? `Applied, verdict withheld: ${priorityLost ? "no field or label could carry the priority pick" : "GitHub did not keep the Issue Type"}, so apply-verdict writes nothing.`
        : `Applied: comment posted, ${labels.size} label(s) added, Issue Type ${typeSet || "not set"}.`;
  summary(
    renderSummary(
      verdictLine,
      [
        `Labels applied: ${[...labels].join(", ") || "none"}`,
        `Priority: ${exclusive.join("; ") || "as applied"}`,
        `Issue Type: ${typeSet || "not set"} (requested: ${usable ? wanted : "none"})`,
        `Floor label: ${floorCleared ? "removed" : floorAdded ? "added" : "unchanged"}`,
      ],
      [`Labels rejected: ${rejected.join(", ") || "none"}`, `Labels replaced: ${replaced.join(", ") || "none"}`],
    ),
  );
  if (!isEscalated && landed) {
    const { size, complexity, uncertainty, flags, blocked_by } = verdict;
    output("verdict", JSON.stringify({ size, complexity, uncertainty, flags, blocked_by }));
  }
  if (failure) {
    log(`::error::Applying the triage failed: ${failure.message}`);
    return 1;
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
