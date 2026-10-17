#!/usr/bin/env node
// write-issue.mjs: writes issue.json for the resolve-issue skill. The title,
// body and labels go in as written (anyone can write them; the skill reads
// them as data). Comments go in only when select-trusted-text's author and
// edit rules keep them, oldest first, each tagged with its author's kind from
// the trusted-actor list. A human's comment whose first line is
// `**Decision recorded.**`, not posted through an App and never edited or last
// edited by a human, is marked `decision: true` with `decided_at`, its latest
// create or edit time. The lanes App's own comments never go in: its
// pushback quotes the issue body. On any failure no file is left, so the
// skill never reads a partial issue.
//
// When the lanes App applied the label (LABEL_SENDER_ID is LANES_APP_ID),
// the trigger gate admitted the issue as it stood at the newest ratification
// marker, so a comment created or edited after that marker is left out too,
// and a title or body changed since that marker fails the run.
//
// Environment:
//   GITHUB_TOKEN          the lane token, which can read the issue
//   GITHUB_REPOSITORY     owner/repo
//   ISSUE_NUMBER          the issue the lane works
//   TRUSTED_ACTORS_PATH   the base's trusted-actor list
//   ISSUE_FILE            where to write issue.json
//   LANES_APP_ID          the lanes App bot's user id
//   LABEL_SENDER_ID       the account that applied the label
//   GITHUB_API_URL
import { rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  createGitHub,
  loadTrustedList,
  readIssueEdits,
  unchangedSince,
} from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { findRatification } from "../../actions/resolve-config/ratification.mjs";
import { selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";

const DECISION = /^\*\*Decision recorded\.\*\*(\s|$)/;
// Comments other than decisions, newest kept, so a pile of them cannot crowd
// out the body.
export const MAX_OTHER_COMMENTS = 20;

const timeOf = (value) => (typeof value === "string" ? Date.parse(value) : Number.NaN);
const firstLine = (body) => (body ?? "").trimStart().split("\n", 1)[0].trimEnd();

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
    if (!/^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "")) {
      throw new Error("LANES_APP_ID is not a user id");
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
    dropped["after-ratification"] = 0;
    dropped["over-cap"] = 0;

    let frozenAt = Number.POSITIVE_INFINITY;
    if (env.LABEL_SENDER_ID === env.LANES_APP_ID) {
      const ratifiers = new Set([...humans].filter((id) => id !== lanesAppId));
      const markers = kept.map(({ comment }) => comment).filter((comment) => findRatification([comment], ratifiers));
      if (markers.length === 0) {
        throw new Error("the lanes App applied the label but no ratification marker is kept");
      }
      frozenAt = Math.max(...markers.map((comment) => timeOf(comment.created_at)));
      // The gate checked this before the run; the author can edit since.
      if (!unchangedSince(await readIssueEdits(client, repository, env.ISSUE_NUMBER), frozenAt)) {
        throw new Error("the issue title or body changed after the newest ratification marker");
      }
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
      if (!(createdAt <= frozenAt && editedAt <= frozenAt)) {
        dropped["after-ratification"] += 1;
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
