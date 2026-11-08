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
// refine.mjs), tagged `refinement`: admission may have counted its criteria,
// and the pr-merge lane's capped-close record (CAPPED_CLOSE_MARKER,
// babysit_verify_evidence.py capped_close), tagged `verify-findings`: the
// verifier's findings on the pull request it closed for this fresh attempt,
// quoted as data. That record is posted just before the restart's re-add,
// which anchors at the admission it restarted, so it is kept whenever it was
// posted, only while no one but the lanes App edited it.
// `person_checks` lists, as written, the body's done-when items intake's split
// refinement names as checks a person runs, only under admission's guards
// (admit.mjs personChecks, over the comments posted before the admission, with the
// issue lane's web hosts); a split refinement whose record does not stand is
// left out, so its prose excuses no item. `split_parent` holds the body of the
// native parent a size split filed the issue from, only while the issue
// counts as that parent's text (admit.mjs splitChildBody) and a listed human
// wrote, and last edited before the admission if ever, that body: the split
// copies only its task-list lines. `scope` lists, for such a part split by
// target, the targets its Scope line names (admit.mjs splitScope).
// `verify_close` lists, for a finished parent (admit.mjs finishedParent), its
// sub-issues, each closed as completed by a trusted close: the run checks the
// issue's own done-when and stops verified-done or verify-unmet. On any failure no file is left, so
// the skill never reads a partial issue.
//
// The admission readAdmission anchors on admitted the issue as it stood
// then, so a comment created or edited after that is left out, and a title or
// body changed since fails the run; an admission record's hashes must also
// match the title and body written here.
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
//   TRIGGER_SENDER_ID     the account whose event started the run (else
//                         LABEL_SENDER_ID)
//   TRIGGER_AT            the issue's updated_at in that event's payload (else
//                         LABEL_EVENT_AT)
//   BASE_PATH, CONFIG_PATH
//                         the base checkout and its pr-pipeline.yaml, whose
//                         models.issue-status names the Work status field
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
//                         changed after the admission, or refused=edited-trusted
//                         when only listed accounts changed them, which
//                         report-outcome names
import { rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { fieldEvents, issueStatusFromBase } from "../../actions/resolve-config/resolve-config.mjs";
import { authorAdmitted, carriesSplit, closedByTrusted, finishedParent, humanWritten, loadRules, parentOf, personChecks, REFINE_MARKER, refinementSpec, SPLIT_CHILD_MARKER, splitChildBody, splitParentOf, splitScope, specOf, taskItems, webHostsFrom } from "../intake-triage/admit.mjs";
import { admittedAt, matchesRecord } from "../lib/admission-record.mjs";
import { RESUMABLE } from "./report-outcome.mjs";

// Comments other than decisions, newest kept, so a pile of them cannot crowd
// out the body.
export const MAX_OTHER_COMMENTS = 20;

// The first line of the pr-merge lane's capped-close record.
export const CAPPED_CLOSE_MARKER = "<!-- verify-capped-close pr=";

const timeOf = (value) => (typeof value === "string" ? Date.parse(value) : Number.NaN);
const firstLine = (body) => (body ?? "").trimStart().split("\n", 1)[0].trimEnd();

// When an issue's body was last edited, and its newest body edits and title
// changes with the account behind each. GitHub lists body edits newest first
// and timeline items oldest first, so each reads its newest page.
const ACCOUNT = "{ ... on User { databaseId } ... on Bot { databaseId } }";
const ISSUE_EDITS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      lastEditedAt
      userContentEdits(first: 100) { pageInfo { hasNextPage } nodes { editedAt editor ${ACCOUNT} } }
      timelineItems(itemTypes: [RENAMED_TITLE_EVENT], last: 100) { pageInfo { hasPreviousPage } nodes { ... on RenamedTitleEvent { createdAt actor ${ACCOUNT} } } }
    }
  }
}`;

// "" when the title and body are as they stood at `frozenAt`; "edited-trusted"
// when every change since was made by an account in `trusted`; else "edited".
// Timestamps are whole seconds, so a change in the label's own second counts
// as after it, and an unparsable time is a change. Fail closed: a change whose
// account is unread, or a page that may hide an older change after
// `frozenAt`, is "edited". A failed read or an unexpected shape throws.
async function readEditsSince(github, repository, number, frozenAt, trusted) {
  const [owner, name] = repository.split("/");
  const issue = (await github("POST", "/graphql", { query: ISSUE_EDITS_QUERY, variables: { owner, name, number: Number(number) } }))
    ?.data?.repository?.issue;
  if (issue === null || typeof issue !== "object" || Array.isArray(issue)) {
    throw new Error("issue edits have an unexpected shape");
  }
  const after = (time) => time != null && !(timeOf(time) < frozenAt);
  // An older page can hide a change only when every node on this one is after `frozenAt`.
  const since = (page, olderKey, timeKey, accountKey) => {
    const nodes = Array.isArray(page?.nodes) ? page.nodes : [];
    const hidden = page?.pageInfo?.[olderKey] === true && nodes.every((node) => after(node?.[timeKey]));
    const changes = nodes.filter((node) => node === null || typeof node !== "object" || after(node[timeKey]));
    return { hidden, changes, byTrusted: changes.every((node) => trusted.has(node?.[accountKey]?.databaseId)) };
  };
  const body = since(issue.userContentEdits, "hasNextPage", "editedAt", "editor");
  const title = since(issue.timelineItems, "hasPreviousPage", "createdAt", "actor");
  const bodyChanged = after(issue.lastEditedAt);
  if (!bodyChanged && title.changes.length === 0) {
    return "";
  }
  const bodyTrusted = !bodyChanged || (body.changes.length > 0 && !body.hidden && body.byTrusted);
  return bodyTrusted && !title.hidden && title.byTrusted ? "edited-trusted" : "edited";
}

// The admission the run freezes at (admission-record.mjs admittedAt): the
// lanes App's newest admission record or a listed human's newest Work status
// set of agent-ready, whichever is newer, at or before the event that started
// the run (`triggerAt`, its payload's issue update time; else the first after
// it), so a later admission never moves it. The App's restarts write no
// record, so they anchor at the admission they restarted. A human sender's own
// sets count, and none when the App sent it. Neither found throws.
async function readAdmission(github, repository, number, { lanesAppId, humans, sender, triggerAt, env }) {
  const config = issueStatusFromBase(env);
  const state = Object.values(config?.options ?? {}).includes("agent-ready") ? "agent-ready" : null;
  const comments = await paginate(github, `/repos/${repository}/issues/${number}/comments`);
  const events = config && state ? await fieldEvents(github, repository, Number(number)) : [];
  return admittedAt({ comments, appId: lanesAppId, fieldEvents: events, fieldId: state ? config["field-id"] : null, humans, sender, triggerAt });
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
    const senderText = env.TRIGGER_SENDER_ID || env.LABEL_SENDER_ID || "";
    if (!/^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "") || !/^[1-9][0-9]*$/.test(senderText)) {
      throw new Error("LANES_APP_ID or TRIGGER_SENDER_ID is not a user id");
    }
    const triggerAt = timeOf(env.TRIGGER_AT || env.LABEL_EVENT_AT);
    if (!Number.isFinite(triggerAt)) {
      throw new Error("TRIGGER_AT is not a time");
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
    Object.assign(dropped, { "lanes-app": 0, "after-admission": 0, "over-cap": 0, "stale-split": 0 });

    const admission = await readAdmission(client, repository, env.ISSUE_NUMBER, { lanesAppId, humans, sender: Number(senderText), triggerAt, env });
    const frozenAt = admission.at;
    // Edits since the admission decide first; a record also holds the hashes
    // of the text it admitted, which this run's one read must match.
    let refused = await readEditsSince(client, repository, env.ISSUE_NUMBER, frozenAt, new Set([...ids, lanesAppId]));
    if (!refused && admission.kind === "record" && !matchesRecord(admission.record, { title: data.title, body: data.body ?? "" })) {
      refused = "edited";
    }
    if (refused) {
      const by = refused === "edited" ? "" : ", each change by a listed account";
      throw Object.assign(new Error(`the issue title or body changed after its admission${by}`), { refused });
    }

    // The body's checks a person runs, as admission read them: the comments
    // posted before the admission, every one read, on the body as written now.
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
    // A finished parent's run verifies its own done-when and builds nothing.
    const finished = await finishedParent({ github: client, repository, issue: data, trusted: closedByTrusted({ github: client, repository, humans, appId: lanesAppId }) });

    const comments = [];
    const entry = (comment, kind, decision) => ({
      author_login: comment.user.login,
      author_kind: kind,
      created_at: comment.created_at,
      url: comment.html_url,
      body: comment.body ?? "",
      decision,
    });
    for (const { comment, lastEditedAt, lastEditorId } of kept) {
      const fromApp = comment.user.id === lanesAppId;
      const text = String(comment.body ?? "");
      const refinement = fromApp && text.startsWith(REFINE_MARKER);
      if (fromApp && text.startsWith(CAPPED_CLOSE_MARKER) && (lastEditorId == null || lastEditorId === lanesAppId)) {
        comments.push(entry(comment, "verify-findings", false));
        continue;
      }
      if (fromApp && !refinement) {
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
      const decision = !refinement && isDecisionComment({ comment, lastEditedAt, lastEditorId }, humans);
      comments.push({
        ...entry(comment, refinement ? "refinement" : humans.has(comment.user.id) ? "human" : "bot", decision),
        ...(decision && { decided_at: new Date(Math.max(createdAt, editedAt)).toISOString() }),
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
      ...(finished !== null && { verify_close: { sub_issues: finished } }),
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
