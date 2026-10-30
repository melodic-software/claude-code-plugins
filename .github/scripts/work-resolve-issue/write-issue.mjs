#!/usr/bin/env node
// write-issue.mjs: writes issue.json for the resolve-issue skill. The title,
// body and labels go in as written: an issue neither a listed human nor the
// lanes App wrote fails the run here, behind the admit job's own stop
// (check-blockers.mjs), and the skill still reads them as data. Comments go in only when select-trusted-text's author and
// edit rules keep them, oldest first, each tagged with its author's kind from
// the trusted-actor list. A human's comment whose first line is
// `**Decision recorded.**`, not posted through an App, and unedited or last
// edited by a human, is marked `decision: true` with `decided_at`, its latest
// create or edit time. The lanes App's own comments never go in, since its
// pushback quotes the issue body, except its intake refinement (REFINE_MARKER,
// refine.mjs), tagged `refinement`: admission may have counted its criteria.
// `person_checks` lists, as written, the body's done-when items intake's split
// refinement names as checks a person runs, only under admission's guards
// (admit.mjs personChecks, over the comments posted before the label, with the
// issue lane's web hosts); a split refinement whose record does not stand is
// left out, so its prose excuses no item. `split_parent` holds the body of the
// native parent a size split filed the issue from, only while the issue
// counts as that parent's text (admit.mjs splitChildBody) and a listed human
// wrote, and last edited before the label if ever, that body: the split
// copies only its task-list lines. `scope` lists, for such a part split by
// target, the targets its Scope line names (admit.mjs splitScope). On any failure no file is left, so
// the skill never reads a partial issue.
//
// The label admitted the issue as it stood at the label event readAdmittedAt
// anchors on, so a comment created or edited after that is left out, and a
// title or body changed since fails the run.
//
// When the run resumes an earlier run's lane branch (report-outcome
// --find-prior), `resume` says so: the branch, why that run ended, the tip the
// new branch starts at, each commit's subject (the earlier run's words, data)
// and the files it changed with their line counts, from GET /compare between
// the trusted base and the tip. When the run starts fresh past an earlier
// run's lane branch that is behind the default branch, `stale_branch` lists
// that branch's work the same way, for the model to reuse its approach.
//
// Environment:
//   GITHUB_TOKEN          the lane token, which can read the issue
//   GITHUB_REPOSITORY     owner/repo
//   ISSUE_NUMBER          the issue the lane works
//   TRUSTED_ACTORS_PATH   the base's trusted-actor list
//   ISSUE_FILE            where to write issue.json
//   LANES_APP_ID          the lanes App bot's user id
//   LABEL_SENDER_ID       the account that applied the label
//   LABEL_NAME            the label whose event started the run
//   LABEL_EVENT_AT        the issue's updated_at in that event's payload
//   RESUME_BRANCH, RESUME_TIP, RESUME_CAUSE
//                         the resumed lane branch, its tip and the earlier
//                         run's outcome, or empty when the run resumes nothing
//   STALE_BRANCH, STALE_TIP
//                         the stale lane branch the run starts fresh past and
//                         its checked tip, or empty
//   BASE_SHA              the trusted base the comparison starts from
//   ISSUE_LANE_WEB_HOSTS  the issue lane's web hosts as JSON (admit.mjs
//                         webHostsFrom); unset allows only GitHub hosts
//   GITHUB_API_URL
//   GITHUB_OUTPUT         receives refused=edited when the title or body
//                         changed after the label, which report-outcome names
import { rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { authorAdmitted, carriesSplit, humanWritten, loadRules, parentOf, personChecks, REFINE_MARKER, refinementSpec, removalStands, SPLIT_CHILD_MARKER, splitChildBody, splitParentOf, splitScope, specOf, taskItems, webHostsFrom } from "../intake-triage/admit.mjs";
import { RESUMABLE } from "./report-outcome.mjs";

// Comments other than decisions, newest kept, so a pile of them cannot crowd
// out the body.
export const MAX_OTHER_COMMENTS = 20;

const timeOf = (value) => (typeof value === "string" ? Date.parse(value) : Number.NaN);
const firstLine = (body) => (body ?? "").trimStart().split("\n", 1)[0].trimEnd();

// When an issue's body was last edited and its title last changed.
const ISSUE_EDITS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      lastEditedAt
      timelineItems(itemTypes: [RENAMED_TITLE_EVENT], last: 1) { nodes { ... on RenamedTitleEvent { createdAt } } }
    }
  }
}`;

// The issue's body edit and title change times (null when never). A failed
// read or an unexpected shape throws.
async function readIssueEdits(github, repository, number) {
  const [owner, name] = repository.split("/");
  const issue = (await github("POST", "/graphql", { query: ISSUE_EDITS_QUERY, variables: { owner, name, number: Number(number) } }))
    ?.data?.repository?.issue;
  if (issue === null || typeof issue !== "object" || Array.isArray(issue)) {
    throw new Error("issue edits have an unexpected shape");
  }
  return [issue.lastEditedAt, ...(issue.timelineItems?.nodes ?? []).map((node) => node?.createdAt)];
}

// When `senderId` added `label` in the event that started this run (its newest
// such event no later than `eventAt`, the issue's update time in the payload):
// that account admitted the text as it stood then. A later label event, by
// any account, never moves it, so a run never adopts a newer admission.
// Adding a label need not bump the update time, so the payload's can predate
// its own label event (the App's re-add lands a second after its removal);
// with no such event at or before it, the run's is the first one after it.
// The lanes App's remove-and-re-add after a limit stop (work-unblock's
// restart) admits nothing new, so it anchors at the label it restarted,
// which must be the App's or a listed human's. An App removal that a
// `status: ready` from the App or a listed human followed before the re-add
// no longer stands (admit.mjs removalStands): that re-add is a fresh
// admission and anchors itself.
async function readAdmittedAt(github, repository, number, label, senderId, lanesAppId, humans, eventAt) {
  const all = (await paginate(github, `/repos/${repository}/issues/${number}/events`))
    // Times are whole seconds; the event id breaks a tie in the order GitHub recorded them.
    .sort((a, b) => timeOf(a?.created_at) - timeOf(b?.created_at) || Number(a?.id) - Number(b?.id));
  const events = all.filter((event) => (event?.event === "labeled" || event?.event === "unlabeled") && event.label?.name === label);
  const trusted = (event) => event.actor?.id === lanesAppId || humans.has(event.actor?.id);
  const restart = (removal, readd) => removalStands(all.slice(0, all.indexOf(readd)), (event) => event === removal, trusted);
  const bySender = (event) => event.event === "labeled" && event.actor?.id === senderId;
  let index = events.findLastIndex((event) => bySender(event) && timeOf(event.created_at) <= eventAt);
  if (index < 0) {
    index = events.findIndex((event) => bySender(event) && timeOf(event.created_at) > eventAt);
  }
  while (
    index > 0 &&
    events[index].actor?.id === lanesAppId &&
    events[index - 1].event === "unlabeled" &&
    events[index - 1].actor?.id === lanesAppId &&
    restart(events[index - 1], events[index])
  ) {
    index = events.slice(0, index - 1).findLastIndex((event) => event.event === "labeled");
    if (index >= 0 && events[index].actor?.id !== lanesAppId && !humans.has(events[index].actor?.id)) {
      index = -1;
    }
  }
  const at = index < 0 ? Number.NaN : timeOf(events[index].created_at);
  if (!Number.isFinite(at)) {
    throw new Error(`no ${label} label event that admitted the issue`);
  }
  return at;
}

// The resume record, or undefined when the run resumes nothing. Any value
// that is not its expected shape, or a failed comparison, throws.
const SHA = /^[0-9a-f]{40}$/;
export const MAX_RESUME_COMMITS = 50;
export const MAX_RESUME_FILES = 100;
const laneShape = (issueNumber) => new RegExp(`^work-resolve-issue/issue-${issueNumber}-[1-9][0-9]*-[1-9][0-9]*$`);
async function readResume(github, env) {
  const { RESUME_BRANCH: branch = "", RESUME_TIP: tip = "", RESUME_CAUSE: cause = "", BASE_SHA: base = "" } = env;
  if (!branch && !tip && !cause) {
    return undefined;
  }
  if (!laneShape(env.ISSUE_NUMBER).test(branch) || !SHA.test(tip) || !SHA.test(base) || !RESUMABLE.has(cause)) {
    throw new Error("the resume branch, tip, cause or base is malformed");
  }
  return { branch, cause, tip, ...(await branchWork(github, env, base, tip)) };
}

// The stale-branch record, or undefined when the run started past none: the
// lane branch issue-prior would have resumed but for being behind the default
// branch, at the tip it checked every commit of, which this run does not start
// from. Any value that is not its expected shape, or a failed comparison,
// throws.
async function readStale(github, env) {
  const { STALE_BRANCH: branch = "", STALE_TIP: tip = "", BASE_SHA: base = "" } = env;
  if (!branch && !tip) {
    return undefined;
  }
  if (!laneShape(env.ISSUE_NUMBER).test(branch) || !SHA.test(tip) || !SHA.test(base)) {
    throw new Error("the stale branch, tip or base is malformed");
  }
  return { branch, tip, ...(await branchWork(github, env, base, tip)) };
}

// Each commit's subject (the earlier run's words, data) and the files it
// changed with their line counts, from GET /compare between the trusted base
// and `tip`, capped.
async function branchWork(github, env, base, tip) {
  const comparison = await github("GET", `/repos/${env.GITHUB_REPOSITORY}/compare/${base}...${tip}`);
  if (!Array.isArray(comparison?.commits) || !Array.isArray(comparison?.files)) {
    throw new Error("the earlier branch's comparison has an unexpected shape");
  }
  return {
    commits: comparison.commits
      .slice(-MAX_RESUME_COMMITS)
      .map((item) => firstLine(String(item?.commit?.message ?? "")).slice(0, 200)),
    files: comparison.files.slice(0, MAX_RESUME_FILES).map((file) => ({
      path: String(file?.filename ?? "").slice(0, 300),
      additions: Number.isSafeInteger(file?.additions) ? file.additions : 0,
      deletions: Number.isSafeInteger(file?.deletions) ? file.deletions : 0,
    })),
  };
}

export async function main({ env = process.env, github, log = console.log, write = (outputs) => env.GITHUB_OUTPUT && writeOutputs(outputs, env.GITHUB_OUTPUT) } = {}) {
  const file = env.ISSUE_FILE;
  try {
    if (!file) {
      throw new Error("ISSUE_FILE is empty");
    }
    rmSync(file, { force: true });
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "") || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("ISSUE_NUMBER or GITHUB_REPOSITORY is malformed");
    }
    if (!/^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "") || !/^[1-9][0-9]*$/.test(env.LABEL_SENDER_ID ?? "")) {
      throw new Error("LANES_APP_ID or LABEL_SENDER_ID is not a user id");
    }
    if (!env.LABEL_NAME) {
      throw new Error("LABEL_NAME is empty");
    }
    const eventAt = timeOf(env.LABEL_EVENT_AT);
    if (!Number.isFinite(eventAt)) {
      throw new Error("LABEL_EVENT_AT is not a time");
    }
    const lanesAppId = Number(env.LANES_APP_ID);
    const { ids, humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const repository = env.GITHUB_REPOSITORY;
    const data = await client("GET", `/repos/${repository}/issues/${env.ISSUE_NUMBER}`);
    // The admit job stops this run first (check-blockers.mjs); this holds the
    // line if a run gets past it.
    if (!authorAdmitted(data, humans, lanesAppId)) {
      throw new Error("the issue's author is neither a listed human nor the lanes App");
    }
    const { kept, dropped } = await selectTrustedIssueComments({
      github: client,
      repository,
      issueNumber: env.ISSUE_NUMBER,
      ids,
    });
    dropped["lanes-app"] = 0;
    dropped["after-admission"] = 0;
    dropped["over-cap"] = 0;

    const frozenAt = await readAdmittedAt(client, repository, env.ISSUE_NUMBER, env.LABEL_NAME, Number(env.LABEL_SENDER_ID), lanesAppId, humans, eventAt);
    // Timestamps are whole seconds, so a change in the label's own second counts as after it.
    // NaN compares false, so an unparsable time is a change.
    const edits = await readIssueEdits(client, repository, env.ISSUE_NUMBER);
    if (!edits.every((time) => time == null || timeOf(time) < frozenAt)) {
      throw Object.assign(new Error(`the issue title or body changed after ${env.LABEL_NAME} was added`), { refused: "edited" });
    }

    // The body's checks a person runs, as admission read them: the comments
    // posted before the label, every one read, on the body as written now.
    const taskList = loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)))["task-list"];
    const spec = await specOf(client, repository, env.ISSUE_NUMBER);
    const before = spec.comments.filter((node) => timeOf(node.createdAt) < frozenAt);
    const moved =
      spec.commentCount === spec.comments.length && spec.body === (data.body ?? "")
        ? personChecks({ ...spec, comments: before }, humans, lanesAppId, taskList, () => webHostsFrom(env.ISSUE_LANE_WEB_HOSTS))
        : [];
    const standing = moved.length > 0 ? refinementSpec(before, lanesAppId)?.databaseId : undefined;
    // A size split's part: its parent's body, under the part's own trust rule.
    let splitParent;
    let scope = null;
    if (spec.author?.__typename === "Bot" && spec.author.databaseId === lanesAppId && spec.body.startsWith(SPLIT_CHILD_MARKER)) {
      const parent = await splitParentOf(client, repository, await parentOf(client, `/repos/${repository}/issues/${env.ISSUE_NUMBER}`), lanesAppId);
      const settled = parent?.spec.lastEditedAt == null || timeOf(parent.spec.lastEditedAt) < frozenAt;
      if (parent && settled && humanWritten(parent.spec, humans) && splitChildBody({ ...spec, splitParent: parent }, humans, taskList) !== null) {
        splitParent = { number: parent.number, body: parent.spec.body };
        scope = splitScope(spec.body);
      }
    }
    dropped["stale-split"] = 0;

    const comments = [];
    for (const { comment, lastEditedAt, lastEditorId } of kept) {
      const refinement = comment.user.id === lanesAppId && String(comment.body ?? "").startsWith(REFINE_MARKER);
      if (comment.user.id === lanesAppId && !refinement) {
        dropped["lanes-app"] += 1;
        continue;
      }
      if (refinement && carriesSplit(comment.body) && comment.id !== standing) {
        dropped["stale-split"] += 1;
        continue;
      }
      const createdAt = timeOf(comment.created_at);
      const editedAt = lastEditedAt === null ? createdAt : timeOf(lastEditedAt);
      // NaN compares false, so an unparsable time is left out.
      if (!(createdAt < frozenAt && editedAt < frozenAt)) {
        dropped["after-admission"] += 1;
        continue;
      }
      const human = humans.has(comment.user.id);
      const decision = !refinement && isDecisionComment({ comment, lastEditedAt, lastEditorId }, humans);
      comments.push({
        author_login: comment.user.login,
        author_kind: refinement ? "refinement" : human ? "human" : "bot",
        created_at: comment.created_at,
        url: comment.html_url,
        body: comment.body ?? "",
        decision,
        ...(decision ? { decided_at: new Date(Math.max(createdAt, editedAt)).toISOString() } : {}),
      });
    }
    const others = comments.filter((comment) => !comment.decision);
    const cut = new Set(others.slice(0, Math.max(0, others.length - MAX_OTHER_COMMENTS)));
    dropped["over-cap"] = cut.size;

    const issue = {
      number: data.number,
      title: data.title,
      body: data.body ?? "",
      labels: (data.labels ?? []).map((label) => (typeof label === "string" ? label : label.name)),
      comments: comments.filter((comment) => !cut.has(comment)),
      ...(moved.length > 0 && { person_checks: moved.map((n) => taskItems(spec.body, taskList)[n - 1].text) }),
      ...(splitParent && { split_parent: splitParent }),
      ...(scope !== null && { scope }),
    };
    const resume = await readResume(client, env);
    if (resume) {
      issue.resume = resume;
    }
    const stale = await readStale(client, env);
    if (stale) {
      issue.stale_branch = stale;
    }
    writeFileSync(file, `${JSON.stringify(issue, null, 2)}\n`);
    log(`write-issue: kept ${issue.comments.length} comment(s), dropped ${JSON.stringify(dropped)}`);
    return 0;
  } catch (error) {
    if (file) {
      rmSync(file, { force: true });
    }
    const detail = error?.name === "GitHubError" ? error.message : (error?.message ?? "error");
    log(`::error title=write-issue::${String(detail).replaceAll(/[\r\n%]/g, " ")}; no issue file written`);
    if (error?.refused) {
      write({ refused: error.refused });
    }
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
