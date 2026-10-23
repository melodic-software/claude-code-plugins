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
// - 7: the body, or a comment the lanes App's account posted opening with
//   REFINE_MARKER (refine.mjs, which writes a task list only for an issue
//   it made exact) after the body's last edit, has a `task-list` line, the
//   criteria the lane checks;
// - 8: no `refuse-labels` label, every blocker a merged pull request or an
//   issue closed as completed by a listed human or a merge here (the close
//   work-unblock counts), and no open pull request in this repository names
//   the issue;
// - 9: the author is a listed human or the lanes App;
// - 10: check-wip-cap's status: over the queued cap, or with the lane paused
//   over the WIP or held cap (from wip.pause-from), the issue gets
//   `admission-deferred`, which work-unblock's hourly sweep admits once there
//   is room.
//
// A refusal a person must settle swaps `status: ready` for
// `status: needs-decision`; a blocker or an open pull request keeps
// `status: ready`. Either way one App comment carrying ADMIT_MARKER says why.
// An open pull request also adds `admission-deferred`: work-unblock's sweep
// skips the issue while such a pull request is open and admits it once none
// is. An issue that waits only on a blocker loses `admission-deferred`, and
// work-unblock admits it when its blocker closes. A refused issue loses it
// too, so the sweep, which does not read these rules, cannot admit it. An
// issue already agent-ready, or whose agent-ready was ever removed, is left
// alone. Issue text can only
// refuse: it never satisfies a criterion the fields, labels or API decide.
import { readFileSync } from "node:fs";

import { isTrustedClose, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const AGENT_READY = "agent-ready";
export const DEFERRED = "admission-deferred";
export const ADMIT_MARKER = "<!-- intake-triage admission -->";
// Opens the lanes App's refinement comment (refine.mjs).
export const REFINE_MARKER = "<!-- intake-triage refinement -->";
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

const here = (url, repository) =>
  String(url ?? "")
    .toLowerCase()
    .endsWith(`/repos/${repository}`.toLowerCase());

// The open pull requests in `repository` an issue's timeline says reference it.
export const openPullsNaming = (timeline, repository) =>
  timeline
    .map((event) => (event?.event === "cross-referenced" ? event.source?.issue : null))
    .filter((source) => source?.pull_request && source.state === "open" && here(source.repository_url, repository))
    .map((source) => source.number);

const names = (labels) => (labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// {verdict: admit | refuse | wait | skip, reasons}. Pure.
export function decide({ issue, verdict, rules, parent, blockers, trustedCloses, timeline, events, comments = [], bodyEditedAt = null, humans, appId, repository }) {
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
  // A refinement drafted before the body's last edit may not fit the body now.
  const refinements = refinementsOf(comments, appId)
    .filter((comment) => bodyEditedAt === null || Date.parse(comment.created_at) >= Date.parse(bodyEditedAt))
    .map((comment) => String(comment.body));
  const lines = [String(issue.body ?? ""), ...refinements].flatMap((text) => text.split("\n"));
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
  for (const blocker of blockers) {
    const done =
      blocker.state === "closed" &&
      here(blocker.repository_url, repository) &&
      (blocker.pull_request
        ? Boolean(blocker.pull_request.merged_at)
        : blocker.state_reason === "completed" && trustedCloses.has(blocker.number));
    if (!done) {
      wait.push(`blocker #${blocker.number} is not closed as completed by a listed human or a merge`);
    }
  }
  const pulls = openPullsNaming(timeline, repository);
  for (const pull of pulls) {
    wait.push(`open pull request #${pull} names it`);
  }
  if (wait.length > 0) {
    return { verdict: "wait", reasons: wait, pulls };
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
async function sayWhy(github, repository, base, comments, text) {
  const body = `${ADMIT_MARKER}\n${text}`;
  const own = comments.find(
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

const refinementsOf = (comments, appId) =>
  comments.filter((comment) => appId !== undefined && comment?.user?.id === appId && String(comment.body ?? "").startsWith(REFINE_MARKER));

const BODY_EDIT_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) { lastEditedAt } }
}`;

// When the issue's body was last edited, or null when never. An unexpected shape throws.
async function bodyEditedAtOf(github, repository, number) {
  const [owner, name] = repository.split("/");
  const issue = (await github("POST", "/graphql", { query: BODY_EDIT_QUERY, variables: { owner, name, number: Number(number) } }))?.data?.repository?.issue;
  if (issue === null || typeof issue !== "object" || (issue.lastEditedAt !== null && typeof issue.lastEditedAt !== "string")) {
    throw new Error("the issue's body edit time has an unexpected shape");
  }
  return issue.lastEditedAt;
}

// Reads the issue fresh, decides, and writes. `status` answers check-wip-cap's
// status for the issue lane. Returns {outcome, reasons}.
export async function admit({ github, repository, number, verdict, rules, humans, appId, status, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const blockers = await paginate(github, `${base}/dependencies/blocked_by`);
  // Anyone may close their own issue as completed, so a blocking issue counts
  // only with a trusted close, read fresh from the issue.
  const trustedCloses = new Set();
  for (const blocker of blockers) {
    if (!blocker.pull_request && blocker.state === "closed" && blocker.state_reason === "completed" && here(blocker.repository_url, repository)) {
      if (await isTrustedClose(github, repository, await github("GET", `/repos/${repository}/issues/${blocker.number}`), humans)) {
        trustedCloses.add(blocker.number);
      }
    }
  }
  const comments = await paginate(github, `${base}/comments`);
  const decision = decide({
    issue,
    comments,
    bodyEditedAt: refinementsOf(comments, appId).length > 0 ? await bodyEditedAtOf(github, repository, number) : null,
    verdict,
    rules,
    parent: rules["types-under-parent"].includes(issue.type?.name) ? await parentOf(github, base) : null,
    blockers,
    trustedCloses,
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
      comments,
      `Not admitted to the issue lane: ${reasons}. A recorded decision does not change these rules (\`.github/actions/resolve-config/admission-rules.json\`); a person who wants it worked adds \`agent-ready\`.`,
    );
    log(`admit: #${number} refused (${reasons})`);
    return { outcome: "refused", reasons: decision.reasons };
  }
  if (decision.verdict === "wait") {
    if (decision.pulls.length === 0) {
      await undefer();
    } else if (!names(issue.labels).includes(DEFERRED)) {
      await github("POST", `${base}/labels`, { labels: [DEFERRED] });
    }
    await sayWhy(github, repository, base, comments, `Not admitted to the issue lane yet: ${reasons}.`);
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
