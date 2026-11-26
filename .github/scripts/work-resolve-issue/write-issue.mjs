#!/usr/bin/env node
import { rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, paginate } from "../lib/github-client.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { fieldEvents, issueStatusFromBase } from "../../actions/resolve-config/resolve-config.mjs";
import { ACTIONS_BOT_ID, authorAdmitted, carriesSplit, closedByTrusted, driftShaped, finishedParent, humanWritten, REFINE_MARKER, webHostsFrom } from "../intake-triage/admit.mjs";
import { driftIssue, loadRules, parentOf, personChecks, refinementSpec, specOf, SPLIT_CHILD_MARKER, splitChildBody, splitScope, taskItems, trustedDriftSpec } from "../intake-triage/issue-spec.mjs";
import { splitParentOf } from "../intake-triage/size-split.mjs";
import { admittedAt, contentHash, matchesRecord, timeOf } from "../lib/admission-record.mjs";
import { laneBranchPattern, WORK_RESOLVE_ISSUE } from "../lib/lane-branch.mjs";
import { RESUMABLE } from "./report-outcome.mjs";

export const MAX_OTHER_COMMENTS = 20;

export const CAPPED_CLOSE_MARKER = "<!-- verify-capped-close pr=";

const firstLine = (body) => (body ?? "").trimStart().split("\n", 1)[0].trimEnd();

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

async function readEditsSince(github, repository, number, frozenAt, trusted, bodyFree = null) {
  const [owner, name] = repository.split("/");
  const issue = (await github("POST", "/graphql", { query: ISSUE_EDITS_QUERY, variables: { owner, name, number: Number(number) } }))
    ?.data?.repository?.issue;
  if (issue === null || typeof issue !== "object" || Array.isArray(issue)) {
    throw new Error("issue edits have an unexpected shape");
  }
  const after = (time) => time != null && !(timeOf(time) < frozenAt);
  const since = (page, olderKey, timeKey, accountKey) => {
    const nodes = Array.isArray(page?.nodes) ? page.nodes : [];
    const hidden = page?.pageInfo?.[olderKey] === true && nodes.every((node) => after(node?.[timeKey]));
    const changes = nodes.filter((node) => node === null || typeof node !== "object" || after(node[timeKey]));
    return { hidden, changes, byTrusted: changes.every((node) => trusted.has(node?.[accountKey]?.databaseId)) };
  };
  const body = since(issue.userContentEdits, "hasNextPage", "editedAt", "editor");
  const title = since(issue.timelineItems, "hasPreviousPage", "createdAt", "actor");
  const freeOnly = bodyFree !== null && !body.hidden && body.changes.length > 0 && body.changes.every((node) => node?.editor?.databaseId === bodyFree);
  const bodyChanged = after(issue.lastEditedAt) && !freeOnly;
  if (!bodyChanged && title.changes.length === 0) {
    return "";
  }
  const bodyTrusted = !bodyChanged || (body.changes.length > 0 && !body.hidden && body.byTrusted);
  return bodyTrusted && !title.hidden && title.byTrusted ? "edited-trusted" : "edited";
}

async function readAdmission(github, repository, number, { lanesAppId, humans, sender, triggerAt, env }) {
  const config = issueStatusFromBase(env);
  const state = Object.values(config?.options ?? {}).includes("agent-ready") ? "agent-ready" : null;
  const comments = await paginate(github, `/repos/${repository}/issues/${number}/comments`);
  const events = config && state ? await fieldEvents(github, repository, Number(number)) : [];
  return admittedAt({ comments, appId: lanesAppId, fieldEvents: events, fieldId: state ? config["field-id"] : null, humans, sender, triggerAt });
}

const SHA = /^[0-9a-f]{40}$/;
export const MAX_RESUME_COMMITS = 50;
export const MAX_RESUME_FILES = 100;
const laneShape = (issueNumber) => laneBranchPattern(WORK_RESOLVE_ISSUE, issueNumber);
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
    let spec;
    let drifted = null;
    if (!authorAdmitted(data, humans, lanesAppId)) {
      spec = driftShaped(data) ? await specOf(client, repository, env.ISSUE_NUMBER) : undefined;
      drifted = spec === undefined ? null : driftIssue(spec);
      if (drifted === null) {
        throw new Error("the issue's author is neither a listed human nor the lanes App, and it is no trusted upstream-drift issue");
      }
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
    const drift = drifted !== null;
    let refused = await readEditsSince(client, repository, env.ISSUE_NUMBER, frozenAt, new Set([...ids, lanesAppId]), drift ? ACTIONS_BOT_ID : null);
    const recordMatches = (record) => (drift ? contentHash(data.title) === record.titleSha256 : matchesRecord(record, { title: data.title, body: data.body ?? "" }));
    if (!refused && admission.kind === "record" && !recordMatches(admission.record)) {
      refused = "edited";
    }
    if (refused) {
      const by = refused === "edited" ? "" : ", each change by a listed account";
      throw Object.assign(new Error(`the issue title or body changed after its admission${by}`), { refused });
    }

    const taskList = loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)))["task-list"];
    spec ??= await specOf(client, repository, env.ISSUE_NUMBER);
    const before = spec.comments.filter((node) => timeOf(node.createdAt) < frozenAt);
    const moved =
      spec.commentCount === spec.comments.length && spec.body === (data.body ?? "")
        ? personChecks({ ...spec, comments: before }, humans, lanesAppId, taskList, () => webHostsFrom(env.ISSUE_LANE_WEB_HOSTS))
        : [];
    const standing = moved.length > 0 ? refinementSpec(before, lanesAppId)?.databaseId : undefined;
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
      body: drifted === null ? (data.body ?? "") : trustedDriftSpec(drifted),
      ...(drifted !== null && { source: "upstream-drift" }),
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
