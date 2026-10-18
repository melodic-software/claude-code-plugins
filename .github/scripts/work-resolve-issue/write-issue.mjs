#!/usr/bin/env node
// write-issue.mjs: writes issue.json for the resolve-issue skill. The title,
// body and labels go in as written (anyone can write them; the skill reads
// them as data). Comments go in only when select-trusted-text's author and
// edit rules keep them, oldest first, each tagged with its author's kind from
// the trusted-actor list. A human's comment whose first line is
// `**Decision recorded.**`, not posted through an App, and unedited or last
// edited by a human, is marked `decision: true` with `decided_at`, its latest
// create or edit time. The lanes App's own comments never go in: its
// pushback quotes the issue body. On any failure no file is left, so the
// skill never reads a partial issue.
//
// The label admitted the issue as it stood when LABEL_SENDER_ID last added
// LABEL_NAME (the issue's labeled events), so a comment created or edited
// after that is left out, and a title or body changed since fails the run.
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
//   GITHUB_API_URL
import { rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";

const DECISION = /^\*\*Decision recorded\.\*\*(\s|$)/;
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
// restart) admits nothing new, so it anchors at the label it restarted.
async function readAdmittedAt(github, repository, number, label, senderId, lanesAppId, eventAt) {
  const events = (await paginate(github, `/repos/${repository}/issues/${number}/events`))
    .filter((event) => (event?.event === "labeled" || event?.event === "unlabeled") && event.label?.name === label)
    // Times are whole seconds; the event id breaks a tie in the order GitHub recorded them.
    .sort((a, b) => timeOf(a.created_at) - timeOf(b.created_at) || Number(a.id) - Number(b.id));
  const bySender = (event) => event.event === "labeled" && event.actor?.id === senderId;
  let index = events.findLastIndex((event) => bySender(event) && timeOf(event.created_at) <= eventAt);
  if (index < 0) {
    index = events.findIndex((event) => bySender(event) && timeOf(event.created_at) > eventAt);
  }
  while (index > 0 && events[index].actor?.id === lanesAppId && events[index - 1].event === "unlabeled" && events[index - 1].actor?.id === lanesAppId) {
    index = events.slice(0, index - 1).findLastIndex((event) => event.event === "labeled");
  }
  const at = index < 0 ? Number.NaN : timeOf(events[index].created_at);
  if (!Number.isFinite(at)) {
    throw new Error(`no ${label} label event that admitted the issue`);
  }
  return at;
}

export async function main({ env = process.env, github, log = console.log } = {}) {
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
    const { kept, dropped } = await selectTrustedIssueComments({
      github: client,
      repository,
      issueNumber: env.ISSUE_NUMBER,
      ids,
    });
    dropped["lanes-app"] = 0;
    dropped["after-admission"] = 0;
    dropped["over-cap"] = 0;

    const frozenAt = await readAdmittedAt(client, repository, env.ISSUE_NUMBER, env.LABEL_NAME, Number(env.LABEL_SENDER_ID), lanesAppId, eventAt);
    // Timestamps are whole seconds, so a change in the label's own second counts as after it.
    // NaN compares false, so an unparseable time is a change.
    const edits = await readIssueEdits(client, repository, env.ISSUE_NUMBER);
    if (!edits.every((time) => time == null || timeOf(time) < frozenAt)) {
      throw new Error(`the issue title or body changed after ${env.LABEL_NAME} was added`);
    }

    const comments = [];
    for (const { comment, lastEditedAt, lastEditorId } of kept) {
      if (comment.user.id === lanesAppId) {
        dropped["lanes-app"] += 1;
        continue;
      }
      const createdAt = timeOf(comment.created_at);
      const editedAt = lastEditedAt === null ? createdAt : timeOf(lastEditedAt);
      // NaN compares false, so an unparseable time is left out.
      if (!(createdAt < frozenAt && editedAt < frozenAt)) {
        dropped["after-admission"] += 1;
        continue;
      }
      const human = humans.has(comment.user.id);
      // A decision is a human's own text: not posted through an App, and
      // never edited or last edited by a human.
      const decision =
        human &&
        comment.performed_via_github_app == null &&
        (lastEditedAt === null || humans.has(lastEditorId)) &&
        DECISION.test(firstLine(comment.body));
      comments.push({
        author_login: comment.user.login,
        author_kind: human ? "human" : "bot",
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
    };
    writeFileSync(file, `${JSON.stringify(issue, null, 2)}\n`);
    log(`write-issue: kept ${issue.comments.length} comment(s), dropped ${JSON.stringify(dropped)}`);
    return 0;
  } catch (error) {
    if (file) {
      rmSync(file, { force: true });
    }
    const detail = error?.name === "GitHubError" ? error.message : (error?.message ?? "error");
    log(`::error title=write-issue::${String(detail).replaceAll(/[\r\n%]/g, " ")}; no issue file written`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
