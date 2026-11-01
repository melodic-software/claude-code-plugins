#!/usr/bin/env node
// reenter.mjs: sends an answered issue back to intake triage. On a new
// comment on an open issue (never a pull request):
//
// - `status: needs-decision` and a decision comment (select-trusted-text's
//   isDecisionComment, the rule write-issue.mjs marks `decision: true` by):
//   remove `status: needs-decision`;
// - `status: confirmed`, where admission parks a refusal no person must
//   answer, and a decision comment: remove `status: confirmed`;
// - `status: needs-info` and a comment by the issue's author or a listed
//   human, not posted through an App: remove `status: needs-info`;
// - EVENT_NAME `issues` (no comment): a listed human removed `needs-human` and
//   the issue carries no `status:` label but `status: needs-decision`, and no
//   `agent-ready`, `needs-human` or `needs-triage`. The newest `needs-human`
//   removal in the issue's events must be that person's; remove
//   `status: needs-decision` when the issue carries it;
// - EVENT_NAME `issues` with REMOVED_LABEL `status: confirmed`: work-unblock
//   took it off because a blocker closed (label-unblocked.mjs). The newest
//   removal of that label must be the lanes App's, the issue must carry no
//   `status:` label, `agent-ready`, `needs-human`, `needs-triage` or
//   `admission-deferred`, and intake must admit its author. The App's other
//   removals land after a status, `agent-ready` or `needs-triage`, so they
//   stop here. `needs-triage` is the claim, since work-unblock already took
//   the label: a second run finds it and dispatches nothing;
//
// A decision on an issue that carries `needs-human` changes nothing: only a
// listed human removes that label (docs/contracts/loop-lane/README.md, the
// label table), and their removal re-enters an issue at
// `status: needs-decision` (owner decision on #10735). At `status: confirmed`
// it re-enters nothing, so the decision is posted again after it;
//
// then add `needs-triage` and dispatch intake-triage.yml once, only for an
// issue whose author intake admits (a listed human or the lanes App). Anything else
// changes nothing. It never adds `agent-ready`. Removing the status label is
// the claim: when GitHub answers 404 another run already took it, so a second
// answer, or a racing run, dispatches nothing. When a later call fails, the
// run puts the labels back and fails, so a re-run can take the claim again. Every fact is read from the API;
// the event supplies only the issue and comment numbers and, on `issues`, the
// removed label. A failed call on a removal puts no status back: with no
// `status:` label a re-run sends it on, and the triage sweep dispatches it.
//
// Environment:
//   GITHUB_TOKEN          the job's token: issues write, actions write
//   GITHUB_REPOSITORY     owner/repo
//   ISSUE_NUMBER, COMMENT_ID (not read when EVENT_NAME is `issues`)
//   EVENT_NAME            `issues` for a label removal, else a comment
//   REMOVED_LABEL         on `issues`, the label removed; `status: confirmed`
//                         or, by default, `needs-human`
//   TRUSTED_ACTORS_PATH   the default branch's trusted-actor list
//   LANES_APP_ID          the lanes App bot's user id, or empty
//   KILL_SWITCH           `proceed`, or the run stops before any API call
//   GITHUB_API_URL
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, GitHubError, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { admissionParked, authorAdmitted } from "../intake-triage/admit.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";

export const NEEDS_DECISION = "status: needs-decision";
export const NEEDS_INFO = "status: needs-info";
// Where admission parks a refusal no person must answer (admit.mjs CONFIRMED).
export const CONFIRMED = "status: confirmed";
export const NEEDS_HUMAN = "needs-human";
export const NEEDS_TRIAGE = "needs-triage";
const AGENT_READY = "agent-ready";
const DEFERRED = "admission-deferred";
const WORKFLOW = "intake-triage.yml";
const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;

const labelNames = (issue) => (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// Which answer the comment is, or null: `decision`, `parked` (a decision on an
// issue admission parked at status: confirmed) or `info`.
export async function classify({ github, repository, issue, comment, humans, ids, lanesAppId }) {
  if (issue.pull_request || issue.state !== "open") {
    return null;
  }
  const user = comment.user ?? {};
  if (user.type !== "User" || user.id === lanesAppId || comment.performed_via_github_app != null) {
    return null;
  }
  const labels = labelNames(issue);
  const kept = async () => {
    const { kept: list } = await selectTrustedIssueComments({ github, repository, issueNumber: issue.number, ids });
    return list.find((item) => item.comment.id === comment.id) ?? null;
  };
  if (labels.includes(NEEDS_DECISION) && humans.has(user.id)) {
    const item = await kept();
    if (item && isDecisionComment(item, humans)) {
      return "decision";
    }
  }
  // status: confirmed is also triage's verified status, so only an issue
  // admission parked there counts (refine.mjs applies the same guard).
  const parked = async () => admissionParked(labels, await paginate(github, `/repos/${repository}/issues/${issue.number}/comments`), lanesAppId);
  if (humans.has(user.id) && labels.includes(CONFIRMED) && (await parked())) {
    const item = await kept();
    if (item && isDecisionComment(item, humans)) {
      return "parked";
    }
  }
  if (labels.includes(NEEDS_INFO)) {
    if (user.id === issue.user?.id) {
      return "info";
    }
    if (humans.has(user.id) && (await kept())) {
      return "info";
    }
  }
  return null;
}

async function removeLabel(github, base, name) {
  try {
    await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`);
    return true;
  } catch (error) {
    if (error instanceof GitHubError && error.status === 404) {
      return false;
    }
    throw error;
  }
}

const EVENT_PAGE = 100;
const MAX_EVENT_PAGES = 10;

// The actor behind the newest `unlabeled` event of `name`, or null.
async function lastRemover(github, base, name) {
  let actor = null;
  for (let page = 1; page <= MAX_EVENT_PAGES; page += 1) {
    const events = await github("GET", `${base}/events?per_page=${EVENT_PAGE}&page=${page}`);
    for (const event of events) {
      if (event.event === "unlabeled" && event.label?.name === name) {
        actor = event.actor ?? null;
      }
    }
    if (events.length < EVENT_PAGE) {
      return actor;
    }
  }
  throw new Error(`the issue's events exceed ${MAX_EVENT_PAGES} pages`);
}

// A listed human lifted `needs-human` and left the issue parked nowhere or at
// `status: needs-decision`: true when intake should take it again.
async function liftReenters({ github, base, issue, humans, lanesAppId }) {
  if (issue.pull_request || issue.state !== "open") {
    return false;
  }
  const labels = labelNames(issue);
  const parked = labels.some((name) => name?.startsWith("status:") && name !== NEEDS_DECISION);
  if (parked || [NEEDS_HUMAN, NEEDS_TRIAGE, AGENT_READY].some((name) => labels.includes(name))) {
    return false;
  }
  if (!authorAdmitted(issue, humans, lanesAppId)) {
    return false;
  }
  const actor = await lastRemover(github, base, NEEDS_HUMAN);
  return actor?.type === "User" && humans.has(actor.id);
}

// The lanes App took `status: confirmed` off and left the issue with nothing
// else to move it: true when intake should take it again.
async function unparkReenters({ github, base, issue, humans, lanesAppId }) {
  if (issue.pull_request || issue.state !== "open" || lanesAppId === null) {
    return false;
  }
  const labels = labelNames(issue);
  if (labels.some((name) => name?.startsWith("status:")) || [NEEDS_HUMAN, NEEDS_TRIAGE, AGENT_READY, DEFERRED].some((name) => labels.includes(name))) {
    return false;
  }
  return authorAdmitted(issue, humans, lanesAppId) && (await lastRemover(github, base, CONFIRMED))?.id === lanesAppId;
}

async function restore({ client, base, labels, addedTriage, log }) {
  try {
    if (addedTriage) {
      await removeLabel(client, base, NEEDS_TRIAGE);
    }
    await client("POST", `${base}/labels`, { labels });
    log(`intake-reenter: restored ${labels.join(", ")}; re-run the job to send the issue back to triage`);
  } catch {
    log(`::error title=intake-reenter::could not restore ${labels.join(", ")}; restore them by hand`);
  }
}

export async function main({ env = process.env, github, log = console.log } = {}) {
  try {
    if (env.KILL_SWITCH !== "proceed") {
      log("intake-reenter: the kill switch stops this run; nothing read or labeled");
      return 0;
    }
    const lift = env.EVENT_NAME === "issues";
    if (!NUMBER.test(env.ISSUE_NUMBER ?? "") || !(lift || /^[1-9][0-9]{0,15}$/.test(env.COMMENT_ID ?? "")) || !REPOSITORY.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("ISSUE_NUMBER, COMMENT_ID or GITHUB_REPOSITORY is malformed");
    }
    const lanesAppId = /^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "") ? Number(env.LANES_APP_ID) : null;
    const { ids, humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const repository = env.GITHUB_REPOSITORY;
    const base = `/repos/${repository}/issues/${env.ISSUE_NUMBER}`;
    const issue = await client("GET", base);
    if (lift) {
      const removed = env.REMOVED_LABEL === CONFIRMED ? CONFIRMED : NEEDS_HUMAN;
      if (!(await (removed === CONFIRMED ? unparkReenters : liftReenters)({ github: client, base, issue, humans, lanesAppId }))) {
        log(`intake-reenter: not a removal of ${removed} that sends an issue to intake; nothing changed`);
        return 0;
      }
      // At status: needs-decision, removing it is the claim, as for a comment.
      const decided = labelNames(issue).includes(NEEDS_DECISION);
      if (decided && !(await removeLabel(client, base, NEEDS_DECISION))) {
        log(`intake-reenter: ${NEEDS_DECISION} is already gone; nothing dispatched`);
        return 0;
      }
      try {
        await client("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
        await client("POST", `/repos/${repository}/actions/workflows/${WORKFLOW}/dispatches`, {
          ref: "main",
          inputs: { "issue-number": String(issue.number) },
        });
      } catch (error) {
        if (decided) {
          await restore({ client, base, labels: [NEEDS_DECISION], addedTriage: true, log });
        } else {
          await removeLabel(client, base, NEEDS_TRIAGE).catch(() => false);
        }
        throw error;
      }
      log(`intake-reenter: ${removed} lifted, ${decided ? `removed ${NEEDS_DECISION}, ` : ""}added ${NEEDS_TRIAGE}, dispatched ${WORKFLOW}`);
      return 0;
    }
    const comment = await client("GET", `/repos/${repository}/issues/comments/${env.COMMENT_ID}`);
    if (comment.issue_url !== undefined && !String(comment.issue_url).endsWith(base)) {
      throw new Error("the comment is not on the issue");
    }
    const kind = await classify({ github: client, repository, issue, comment, humans, ids, lanesAppId });
    if (!kind) {
      log("intake-reenter: not an answer to a parked issue; nothing changed");
      return 0;
    }
    const had = labelNames(issue);
    if (kind !== "info" && had.includes(NEEDS_HUMAN)) {
      const next =
        kind === "decision"
          ? `a listed human's removal of ${NEEDS_HUMAN} sends it back to triage`
          : `a listed human removes ${NEEDS_HUMAN} and posts the decision again, since a removal re-enters no issue at ${CONFIRMED}`;
      log(`intake-reenter: ${NEEDS_HUMAN} holds the issue, so a decision changes nothing; ${next}`);
      return 0;
    }
    const status = { decision: NEEDS_DECISION, parked: CONFIRMED, info: NEEDS_INFO }[kind];
    if (!(await removeLabel(client, base, status))) {
      log(`intake-reenter: ${status} is already gone; nothing dispatched`);
      return 0;
    }
    // Past the claim, a failed call puts the labels back as they were, so a
    // re-run of the job finds the issue parked and the answer is not lost.
    try {
      await client("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
      // Intake admits an issue only from a listed human or the lanes App; any
      // other issue waits in needs-triage for a person, so its author cannot
      // start a model run with each reply.
      if (!authorAdmitted(issue, humans, lanesAppId)) {
        log(`intake-reenter: removed ${status}, added ${NEEDS_TRIAGE}; the author is not one intake admits, so nothing dispatched`);
        return 0;
      }
      await client("POST", `/repos/${repository}/actions/workflows/${WORKFLOW}/dispatches`, {
        ref: "main",
        inputs: { "issue-number": String(issue.number) },
      });
    } catch (error) {
      await restore({ client, base, labels: [status], addedTriage: !had.includes(NEEDS_TRIAGE), log });
      throw error;
    }
    log(`intake-reenter: removed ${status}, added ${NEEDS_TRIAGE}, dispatched ${WORKFLOW}`);
    return 0;
  } catch (error) {
    const detail = error?.name === "GitHubError" ? error.message : (error?.message ?? "error");
    log(`::error title=intake-reenter::${String(detail).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
