import { appendFileSync, readFileSync } from "node:fs";

import { runAsScript } from "../lib/run-main.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { personReasonLines } from "../lib/stop-reason.mjs";
import { headRefDigest, isVerdictName, NAME } from "../pr-verify/write-verdict.mjs";
import { createGitHubApi, humanGatedLabelFrom, leaveQueueOnHold, MARKER_AUTHOR_ID, need, quote, staleVerifyNotes, VERIFY_NOTE_MARKER } from "./address-feedback.mjs";

export const FAILED_LABEL = "pr-verify-failed";

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

const markedBy = (comment, line) => comment.user?.id === MARKER_AUTHOR_ID && firstLine(comment.body) === line;

const bullets = (notes) => notes.map((note) => `- ${note}`);

function laneAppId(appId) {
  if (!Number.isSafeInteger(appId) || appId < 1) {
    throw new Error("APP_SENDER_ID must name the lanes App's bot user id");
  }
  return appId;
}

export function notePath(note, files) {
  const token = String(note).trimStart().split(/\s/, 1)[0] ?? "";
  const path = token
    .replace(/^[`'"([*]+/, "")
    .replace(/[`'")\]*.,;:]+$/, "")
    .replace(/:[0-9]+(-[0-9]+)?$/, "");
  return files.includes(path) ? path : null;
}

export function noteComments({ head, summary, notes, files }) {
  const byPath = new Map();
  const loose = [];
  for (const note of notes) {
    const path = notePath(note, files);
    if (path === null) {
      loose.push(note);
    } else if (byPath.has(path)) {
      byPath.get(path).push(note);
    } else {
      byPath.set(path, [note]);
    }
  }
  const paths = files.filter((file) => byPath.has(file));
  const first = paths[0] ?? files[0];
  if (first === undefined) {
    return [];
  }
  return [first, ...paths.filter((path) => path !== first)].map((path) => {
    const own = bullets(byPath.get(path) ?? []);
    const lines = path === first ? [`Summary: ${summary}`, ...bullets(loose), ...own] : own;
    return {
      path,
      body: [VERIFY_NOTE_MARKER, `The pr-verify verifier failed head \`${head}\`. What it wrote${path === first ? "" : " about this file"}, as data:`, "", quote(lines)].join("\n"),
    };
  });
}

export function failComment({ head, summary, notes }) {
  return [
    VERIFY_NOTE_MARKER,
    `The pr-verify verifier failed head \`${head}\`. What it wrote, as data:`,
    "",
    quote([`Summary: ${summary}`, ...bullets(notes)]),
    "",
    `This pull request leaves the merge queue, and ci-status holds it out while it carries \`${FAILED_LABEL}\`. A pr-verify pass removes the label, at a new commit or at this same head: once a trusted person edits the body, and only trusted people have edited it since the fail, this head is judged again, so a fail on the body or the issues it links needs only the body fixed, no new commit.`,
  ].join("\n");
}

const hasLabel = async (api, pull, pr, name = FAILED_LABEL) => (Array.isArray(pull?.labels) ? pull.labels : await api.listLabels(pr)).some((label) => label.name === name);

async function everyStep(log, steps) {
  const failures = [];
  for (const step of steps) {
    try {
      await step();
    } catch (error) {
      failures.push(error);
    }
  }
  for (const error of failures.slice(1)) {
    log(`::error::${error.message}`);
  }
  if (failures.length > 0) {
    throw failures[0];
  }
}

async function leaveQueue({ api, pr, log }) {
  const entry = await api.readQueueEntry(pr);
  if (!entry.queued) {
    return;
  }
  try {
    await api.dequeuePull(entry.id);
  } catch (error) {
    log(`::error::#${pr}: could not dequeue it (${error.message}); its queued merge was not stopped`);
    throw error;
  }
  log(`#${pr}: dequeued from the merge queue`);
}

async function holdForCredential({ api, pull, verdict: { pr, head }, humanGatedLabel, log }) {
  await everyStep(log, [
    async () => {
      const label = humanGatedLabel();
      if (!(await hasLabel(api, pull, pr, label))) {
        await api.addLabels(pr, [label]);
      }
    },
    async () => {
      const reason = personReasonLines("pr-verify", "security");
      const said = `pr-verify withheld its fail at head \`${head}\``;
      const posted = (await api.listIssueComments(pr)).some((comment) => markedBy(comment, reason[0]) && comment.body.includes(said));
      if (!posted) {
        await api.createIssueComment(
          pr,
          [...reason, "", `${said}: its text was shaped like a credential, or its step stopped on the credential scan. Check this pull request's commits for a credential and rotate any that is real; removing it from the head does not. A person removing the human-gated label lifts this hold.`].join("\n"),
        );
      }
    },
    async () => {
      if (pull.state === "open") {
        await leaveQueue({ api, pr, log });
      }
    },
  ]);
  log(`#${pr}: withheld fail at ${head}; held for a person`);
}

async function holdPersonPull({ api, pull, verdict, log }) {
  const { pr, head } = verdict;
  const body = failComment(verdict);
  const last = (await api.listIssueComments(pr)).findLast((comment) => markedBy(comment, VERIFY_NOTE_MARKER));
  if (last === undefined) {
    await api.createIssueComment(pr, body);
  } else if (last.body !== body) {
    await api.updateIssueComment(last.id, body);
  }
  if (!(await hasLabel(api, pull, pr))) {
    await api.addLabels(pr, [FAILED_LABEL]);
  }
  await leaveQueueOnHold({ readQueueEntry: (n) => api.readQueueEntry(n), dequeuePull: (id) => api.dequeuePull(id), pr, label: FAILED_LABEL, log });
  log(`#${pr}: a person's pull request; the fail at ${head} is in its fail comment and the ${FAILED_LABEL} label holds it`);
}

const sameIssues = (named, recorded) => {
  if (!Array.isArray(recorded)) return false;
  const a = new Set(named.split(".").map(Number));
  const b = new Set(recorded.map((issue) => issue?.number));
  return a.size === b.size && [...a].every((n) => b.has(n));
};

export function readVerdict(name, text) {
  const match = NAME.exec(name ?? "");
  if (!match || !isVerdictName(name)) {
    throw new Error("the artifact name is not a pr-verify verdict");
  }
  const [, pr, head, kind, issues] = match;
  const digest = /^-([0-9a-f]{16})/.exec(name.slice(`pr-verify-${pr}-${head}-${kind}`.length))?.[1];
  const verdict = JSON.parse(text);
  if (
    verdict?.verdict !== kind ||
    verdict.pr !== Number(pr) ||
    verdict.head_sha !== head ||
    (digest !== undefined && headRefDigest(verdict.head_ref) !== digest) ||
    (issues !== undefined && !sameIssues(issues, verdict.linked_issues)) ||
    ![undefined, true].includes(verdict.withheld)
  ) {
    throw new Error("the verdict file does not record the verdict its name names");
  }
  if (kind !== "fail") {
    return { pr: verdict.pr, head: verdict.head_sha, verdict: kind };
  }
  if (typeof verdict.summary !== "string" || !Array.isArray(verdict.notes) || !verdict.notes.every((note) => typeof note === "string")) {
    throw new Error("the verdict file does not record the fail its name names");
  }
  return { pr: verdict.pr, head: verdict.head_sha, verdict: kind, summary: verdict.summary, notes: verdict.notes, withheld: verdict.withheld === true };
}

export async function findStaleNotes({ api, verdict, appId, log }) {
  const { pr, head } = verdict;
  laneAppId(appId);
  const pull = await api.getPull(pr);
  if (pull.state !== "open" || pull.head?.sha !== head) {
    log(`skip: #${pr} is not open at head ${head}`);
    return false;
  }
  if (pull.user?.id !== appId) {
    if (await hasLabel(api, pull, pr)) {
      await api.removeLabel(pr, FAILED_LABEL);
      log(`#${pr}: the ${verdict.verdict} at ${head} removed ${FAILED_LABEL}`);
    }
    return false;
  }
  if (pull.review_comments === 0) {
    log(`#${pr}: no review comment, so no open fail-note thread the ${verdict.verdict} at ${head} may supersede`);
    return false;
  }
  const open = staleVerifyNotes(await api.listThreads(pr), head, { supersededHead: head });
  log(`#${pr}: ${open.length} open fail-note thread(s) the ${verdict.verdict} at ${head} may supersede`);
  return open.length > 0;
}

export async function postNotes({ api, verdict, appId, humanGatedLabel = () => "needs-human", log }) {
  laneAppId(appId);
  const pull = await api.getPull(verdict.pr);
  let posted = false;
  await everyStep(log, [
    ...(verdict.withheld ? [() => holdForCredential({ api, pull, verdict, humanGatedLabel, log })] : []),
    async () => {
      posted = await postAtHead({ api, pull, verdict, appId, log });
    },
  ]);
  return posted;
}

async function postAtHead({ api, pull, verdict, appId, log }) {
  const { pr, head } = verdict;
  if (pull.state !== "open" || pull.head?.sha !== head) {
    log(`skip: #${pr} is not open at head ${head}`);
    return false;
  }
  if (pull.user?.id !== appId) {
    await holdPersonPull({ api, pull, verdict, log });
    return false;
  }
  const resolved = new Set((await api.listThreads(pr)).filter((thread) => thread.isResolved === true).flatMap((thread) => (thread.comments?.nodes ?? []).map((comment) => comment.databaseId)));
  const posted = new Set(
    (await api.listReviewComments(pr))
      .filter((comment) => markedBy(comment, VERIFY_NOTE_MARKER) && comment.original_commit_id === head && !resolved.has(comment.id))
      .map((comment) => comment.path),
  );
  const files = (await api.listPullFiles(pr)).map((file) => file.filename);
  const comments = noteComments({ ...verdict, files });
  if (comments.length === 0) {
    log(`skip: #${pr} changes no file to comment on`);
    return false;
  }
  const missing = comments.filter(({ path }) => !posted.has(path));
  for (const { path, body } of missing) {
    await api.createReviewComment(pr, { body, commit_id: head, path, subject_type: "file" });
  }
  log(`#${pr}: posted ${missing.length} of ${comments.length} verifier note comment(s) on head ${head}`);
  return true;
}

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "APP_SENDER_ID", "ARTIFACT_NAME", "VERDICT_FILE"]);
  const appId = laneAppId(Number(env.APP_SENDER_ID));
  const verdict = readVerdict(env.ARTIFACT_NAME, readFileSync(env.VERDICT_FILE, "utf8"));
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      fetch: rateLimitLatch.guard(globalThis.fetch),
    });
  if (verdict.verdict !== "fail") {
    if (await findStaleNotes({ api: client, verdict, appId, log })) {
      appendFileSync(env.GITHUB_OUTPUT, `pass-head-sha=${verdict.head}\n`);
    }
  } else if (await postNotes({ api: client, verdict, appId, humanGatedLabel: () => humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/docs/conventions/work-items.yaml"), log })) {
    appendFileSync(env.GITHUB_OUTPUT, `pr-number=${verdict.pr}\nhead-sha=${verdict.head}\n`);
  }
  return 0;
}

runAsScript(import.meta.url, "verify-notes", () => main(process.env));
