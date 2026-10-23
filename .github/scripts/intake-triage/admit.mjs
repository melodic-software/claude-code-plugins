// admit.mjs: after apply-verdict set `status: ready`, adds `agent-ready` as
// the lanes App when the issue meets #9212's admission criteria (owner
// decision Q51), and the issue lane's caps have room. No model. The rules come
// from the default branch's .github/actions/resolve-config/admission-rules.json.
//
// Criteria 1, 5 and 6 (exact intent, no very-high security risk, no charge)
// are already in `status: ready`: apply-verdict withholds it on any flag
// (triage flags security only for a very-high risk) or a hold label, and the
// cost rule adds needs-human. Criterion 4 (no protected path named) is not
// applied. This checks the rest:
//
// - 2: the Issue Type is in `types`, or in `types-under-parent` under an open
//   parent issue a listed human filed that awaits no decision;
// - 3: the class, Size and Uncertainty apply-verdict wrote are in `classes`,
//   `sizes` and `uncertainty`;
// - 7: the body has a `task-list` line, the criteria the lane checks;
// - 8: no `refuse-labels` label, every blocker closed as completed (or merged),
//   and no open pull request in this repository names the issue;
// - 9: the author is a listed human or the lanes App;
// - 10: check-wip-cap's status: over the queued cap, or with the lane paused
//   over the WIP or held cap (from wip.pause-from), the issue gets
//   `admission-deferred`, which work-unblock's hourly sweep admits once there
//   is room.
//
// A refusal a person must settle swaps `status: ready` for
// `status: needs-decision`; a blocker or an open pull request keeps the issue
// as it is (work-unblock admits it when its blocker closes). Either way one
// App comment carrying ADMIT_MARKER says why. An issue already agent-ready, or
// whose agent-ready was ever removed, is left alone. A refused or waiting issue
// loses `admission-deferred`, so work-unblock's sweep, which does not read these
// rules, cannot admit it later. Issue text can only
// refuse: it never satisfies a criterion the fields, labels or API decide.
import { readFileSync } from "node:fs";

import { paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const AGENT_READY = "agent-ready";
export const DEFERRED = "admission-deferred";
export const ADMIT_MARKER = "<!-- intake-triage admission -->";
const READY = "status: ready";
const NEEDS_DECISION = "status: needs-decision";
const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";
const PARENT_HOLDS = new Set(["needs-human", "needs-owner-decision", NEEDS_DECISION]);
const LISTS = ["types", "types-under-parent", "classes", "sizes", "uncertainty", "refuse-labels"];

// The rules file, each list checked to hold strings.
export function loadRules(path) {
  const rules = JSON.parse(readFileSync(path, "utf8"));
  for (const key of LISTS) {
    if (!Array.isArray(rules?.[key]) || !rules[key].every((item) => typeof item === "string" && item !== "")) {
      throw new Error(`${path}: \`${key}\` must be a list of strings`);
    }
  }
  if (typeof rules["task-list"] !== "string" || rules["task-list"] === "") {
    throw new Error(`${path}: \`task-list\` must be a string`);
  }
  return rules;
}

const names = (labels) => (labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// {verdict: admit | refuse | wait | skip, reasons}. Pure.
export function decide({ issue, verdict, rules, parent, blockers, timeline, events, humans, appId, repository }) {
  const labels = names(issue.labels);
  if (!labels.includes(READY)) {
    return { verdict: "skip", reasons: [`no ${READY}`] };
  }
  if (labels.includes(AGENT_READY)) {
    return { verdict: "skip", reasons: [`already ${AGENT_READY}`] };
  }
  if (events.some((event) => event?.event === "unlabeled" && event.label?.name === AGENT_READY)) {
    return { verdict: "skip", reasons: [`${AGENT_READY} was removed before`] };
  }

  const refuse = [];
  const author = issue.user?.id;
  if (!(humans.has(author) || (appId !== undefined && author === appId))) {
    refuse.push("the author is neither a listed human nor the lanes App");
  }
  const type = issue.type?.name ?? "none";
  if (rules["types-under-parent"].includes(type)) {
    const parentOk =
      parent !== null && parent.state === "open" && humans.has(parent.user?.id) && !names(parent.labels).some((label) => PARENT_HOLDS.has(label));
    if (!parentOk) {
      refuse.push(`a ${type} needs an open parent issue a listed human filed that awaits no decision`);
    }
  } else if (!rules.types.includes(type)) {
    refuse.push(`type ${type} is not one of ${[...rules.types, ...rules["types-under-parent"]].join(", ")}`);
  }
  if (!rules.classes.includes(verdict.workClass)) {
    refuse.push(`${verdict.workClass} is not one of ${rules.classes.join(", ")}`);
  }
  if (!rules.sizes.includes(verdict.dimensions?.size)) {
    refuse.push(`Size ${verdict.dimensions?.size} is not one of ${rules.sizes.join(", ")}`);
  }
  if (!rules.uncertainty.includes(verdict.dimensions?.uncertainty)) {
    refuse.push(`Uncertainty ${verdict.dimensions?.uncertainty} is not one of ${rules.uncertainty.join(", ")}`);
  }
  const lines = String(issue.body ?? "").split("\n");
  if (!lines.some((line) => line.trimStart().startsWith(rules["task-list"]))) {
    refuse.push(`it has no \`${rules["task-list"]}\` task list to check`);
  }
  for (const label of rules["refuse-labels"]) {
    if (labels.includes(label)) {
      refuse.push(`it carries ${label}`);
    }
  }
  if (refuse.length > 0) {
    return { verdict: "refuse", reasons: refuse };
  }

  const wait = [];
  const here = (url) =>
    String(url ?? "")
      .toLowerCase()
      .endsWith(`/repos/${repository}`.toLowerCase());
  for (const blocker of blockers) {
    const done =
      blocker.state === "closed" &&
      here(blocker.repository_url) &&
      (blocker.pull_request ? Boolean(blocker.pull_request.merged_at) : blocker.state_reason === "completed");
    if (!done) {
      wait.push(`blocker #${blocker.number} is not closed as completed`);
    }
  }
  for (const event of timeline) {
    const source = event?.source?.issue;
    if (
      event?.event === "cross-referenced" &&
      source?.pull_request &&
      source.state === "open" &&
      here(source.repository_url)
    ) {
      wait.push(`open pull request #${source.number} names it`);
    }
  }
  if (wait.length > 0) {
    return { verdict: "wait", reasons: wait };
  }
  return { verdict: "admit", reasons: [] };
}

async function parentOf(github, base) {
  try {
    return await github("GET", `${base}/parent`);
  } catch (error) {
    if (error?.status === 404) {
      return null;
    }
    throw error;
  }
}

// One App comment carrying ADMIT_MARKER, edited in place on a later run.
async function sayWhy(github, repository, base, text) {
  const body = `${ADMIT_MARKER}\n${text}`;
  const own = (await paginate(github, `${base}/comments`)).find(
    (comment) => comment.user?.login === LANES_APP_LOGIN && String(comment.body ?? "").startsWith(ADMIT_MARKER),
  );
  if (own) {
    await github("PATCH", `/repos/${repository}/issues/comments/${own.id}`, {
      body,
    });
  } else {
    await github("POST", `${base}/comments`, { body });
  }
}

// Reads the issue fresh, decides, and writes. `status` answers check-wip-cap's
// status for the issue lane. Returns {outcome, reasons}.
export async function admit({ github, repository, number, verdict, rules, humans, appId, status, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const decision = decide({
    issue,
    verdict,
    rules,
    parent: rules["types-under-parent"].includes(issue.type?.name) ? await parentOf(github, base) : null,
    blockers: await paginate(github, `${base}/dependencies/blocked_by`),
    timeline: await paginate(github, `${base}/timeline`),
    events: await paginate(github, `${base}/events`),
    humans,
    appId,
    repository,
  });
  const reasons = decision.reasons.join("; ");
  const undefer = async () => {
    if (names(issue.labels).includes(DEFERRED)) {
      await github("DELETE", `${base}/labels/${DEFERRED}`);
    }
  };
  if (decision.verdict === "skip") {
    log(`admit: #${number} left as is (${reasons})`);
    return { outcome: "skipped", reasons: decision.reasons };
  }
  if (decision.verdict === "refuse") {
    await github("DELETE", `${base}/labels/${encodeURIComponent(READY)}`);
    await github("POST", `${base}/labels`, { labels: [NEEDS_DECISION] });
    await undefer();
    await sayWhy(
      github,
      repository,
      base,
      `Not admitted to the issue lane: ${reasons}. A recorded decision does not change these rules (\`.github/actions/resolve-config/admission-rules.json\`); a person who wants it worked adds \`agent-ready\`.`,
    );
    log(`admit: #${number} refused (${reasons})`);
    return { outcome: "refused", reasons: decision.reasons };
  }
  if (decision.verdict === "wait") {
    await undefer();
    await sayWhy(github, repository, base, `Not admitted to the issue lane yet: ${reasons}.`);
    log(`admit: #${number} waits (${reasons})`);
    return { outcome: "waiting", reasons: decision.reasons };
  }
  const s = await status();
  if (s.paused || !s.admission_open || (s.admission_room ?? 1) <= 0) {
    await github("POST", `${base}/labels`, { labels: [DEFERRED] });
    const why = s.paused ? `the lane is paused (${s.pause_reason})` : `admissions are closed (${s.admission_reason})`;
    log(`admit: #${number} deferred: ${why}`);
    return { outcome: "deferred", reasons: [why] };
  }
  await github("POST", `${base}/labels`, { labels: [AGENT_READY] });
  log(`admit: #${number} labeled ${AGENT_READY}`);
  return { outcome: "admitted", reasons: [] };
}
