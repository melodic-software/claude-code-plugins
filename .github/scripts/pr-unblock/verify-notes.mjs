// Posts a pr-verify FAIL's summary and notes on its pull request as review
// comments, so pr-unblock's address-feedback round works them like the
// reviewer bot's threads (address-feedback.mjs VERIFY_NOTE_MARKER) instead of
// the pull request waiting for a person. Run by pr-feedback-dispatch.yml's
// post-verify-notes job, base code only, with the job's GITHUB_TOKEN
// (github-actions[bot]) after a pr-verify run completes. The verdict comes
// from that run's own artifact, which only steps of a pr-verify.yml run on
// main can upload; the workflow checks the run before this runs.
//
// It posts only for an open pull request whose current head is the one the
// FAIL judged, and only the comments not on it yet: a verifier note at that
// head on the same file is that comment, so a re-run after a partial post
// posts the rest and nothing twice. Each note that starts with a path the pull
// request changes (`path` or `path:line`, backticks allowed) goes on that
// file; the summary and every other note go on the first such file, or on the
// pull request's first changed file when no note names one. Model text is
// quoted as data in a text fence, wrapped to fit the page (quote), never
// interpolated into a command.
//
// On a pull request the lanes App did not open, a person's, the FAIL is no
// review thread: GitHub lets only its author or a writer resolve one, which
// the lanes App is not, and every conversation must be resolved to merge.
// Instead the summary and notes go in one PR comment, the marker its first
// line, updated in place on a later FAIL, and the PR gets the
// pr-verify-failed label, which ci-status holds in the merge queue. ci-status
// reads that label once per merge group, so a PR already queued past that read
// would still merge: one in the queue is dequeued too, under this job's
// pull-requests: write token. A refused dequeue fails the job red, naming the
// PR. No round starts. A PASS or PASS-NOTES at its head removes the label.
//
// A FAIL write-verdict.mjs recorded as withheld also holds the pull request
// for a person (holdForCredential), in any state and at any head, apart from
// the rest: a failure there still posts the notes, then fails the job.
//
// On a lanes App pull request a PASS or PASS-NOTES posts nothing and resolves
// nothing. For an open pull request still at the head it judged, it names
// that head in the pass-head-sha output when a fail-note thread from an
// earlier head is still open (address-feedback.mjs staleVerifyNotes); the
// dispatch job then sends pr-unblock.yml, whose publish-feedback job resolves
// those threads as the lanes App. Resolving a thread takes more than this
// job's token holds.
//
// Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT, APP_SENDER_ID
// (the lanes App's bot user id), ARTIFACT_NAME
// (pr-verify-<pr>-<sha>-<pass|pass-notes|fail>, then the head-ref digest
// write-verdict.mjs adds, absent on an older verdict, then on a FAIL
// optionally `-i` and the verdict's issue numbers: write-verdict.mjs NAME) and
// VERDICT_FILE (its verdict.json). For a FAIL, writes pr-number and head-sha
// outputs once the notes are on a lanes App pull request, posted now or by an
// earlier run; for a pass, pass-head-sha as above.

import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { personReasonLines } from "../lib/stop-reason.mjs";
import { headRefDigest, isVerdictName, NAME } from "../pr-verify/write-verdict.mjs";
import { createGitHubApi, humanGatedLabelFrom, MARKER_AUTHOR_ID, need, quote, staleVerifyNotes, VERIFY_NOTE_MARKER } from "./address-feedback.mjs";

// The label that holds a person's pull request after a FAIL (ci-status's
// merge-queue label step reads the same name).
export const FAILED_LABEL = "pr-verify-failed";

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

function laneAppId(appId) {
  if (!Number.isSafeInteger(appId) || appId < 1) {
    throw new Error("APP_SENDER_ID must name the lanes App's bot user id");
  }
  return appId;
}

// The changed path a note starts with, or null.
export function notePath(note, files) {
  const token = String(note).trimStart().split(/\s/, 1)[0] ?? "";
  const path = token
    .replace(/^[`'"([*]+/, "")
    .replace(/[`'")\]*.,;:]+$/, "")
    .replace(/:[0-9]+(-[0-9]+)?$/, "");
  return files.includes(path) ? path : null;
}

// The comments to post, each { path, body }, in the pull request's file order.
export function noteComments({ head, summary, notes, files }) {
  const byPath = new Map();
  const loose = [];
  for (const note of notes) {
    const path = notePath(note, files);
    if (path === null) {
      loose.push(note);
    } else {
      byPath.set(path, [...(byPath.get(path) ?? []), note]);
    }
  }
  const paths = files.filter((file) => byPath.has(file));
  const first = paths[0] ?? files[0];
  if (first === undefined) {
    return [];
  }
  return [first, ...paths.filter((path) => path !== first)].map((path) => {
    const lines = path === first ? [`Summary: ${summary}`, ...loose.map((note) => `- ${note}`), ...(byPath.get(path) ?? []).map((note) => `- ${note}`)] : byPath.get(path).map((note) => `- ${note}`);
    return {
      path,
      body: [VERIFY_NOTE_MARKER, `The pr-verify verifier failed head \`${head}\`. What it wrote${path === first ? "" : " about this file"}, as data:`, "", quote(lines)].join("\n"),
    };
  });
}

// The one PR comment a person's pull request gets for a FAIL.
export function failComment({ head, summary, notes }) {
  return [
    VERIFY_NOTE_MARKER,
    `The pr-verify verifier failed head \`${head}\`. What it wrote, as data:`,
    "",
    quote([`Summary: ${summary}`, ...notes.map((note) => `- ${note}`)]),
    "",
    `This pull request leaves the merge queue, and ci-status holds it out while it carries \`${FAILED_LABEL}\`. A pr-verify pass at a new commit removes the label.`,
  ].join("\n");
}

const hasLabel = async (api, pr, name = FAILED_LABEL) => (await api.listLabels(pr)).some((label) => label.name === name);

// Runs every step, so one failure leaves the others done, then throws the first.
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

// Called after the label, so a re-queue meets ci-status's label read.
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

// A withheld fail may mean a live credential in the pull request's commits,
// which a later clean commit does not rotate: it holds for a person, at
// whatever head the pull request has moved to. The label goes on in any state,
// so a closed pull request that reopens is still held; only an open one has a
// queue step. The label is the hold, so it goes first; the comment, whose first line gate-source.mjs CREDENTIAL_HOLD reads,
// keeps the clear paths off that label. It posts once per head whatever else
// the label stands for, and names no text.
async function holdForCredential({ api, pull, verdict: { pr, head }, humanGatedLabel, log }) {
  await everyStep(log, [
    async () => {
      const label = humanGatedLabel();
      if (!(await hasLabel(api, pr, label))) {
        await api.addLabels(pr, [label]);
      }
    },
    async () => {
      const reason = personReasonLines("pr-verify", "security");
      const said = `pr-verify withheld its fail at head \`${head}\``;
      const posted = (await api.listIssueComments(pr)).some((comment) => comment.user?.id === MARKER_AUTHOR_ID && firstLine(comment.body) === reason[0] && comment.body.includes(said));
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

// A person's pull request at the FAIL's head: its fail comment, then the label.
async function holdPersonPull({ api, verdict, log }) {
  const { pr, head } = verdict;
  const body = failComment(verdict);
  const mine = (await api.listIssueComments(pr)).filter((comment) => comment.user?.id === MARKER_AUTHOR_ID && firstLine(comment.body) === VERIFY_NOTE_MARKER);
  const last = mine.at(-1);
  if (last === undefined) {
    await api.createIssueComment(pr, body);
  } else if (last.body !== body) {
    await api.updateIssueComment(last.id, body);
  }
  if (!(await hasLabel(api, pr))) {
    await api.addLabels(pr, [FAILED_LABEL]);
  }
  await leaveQueue({ api, pr, log });
  log(`#${pr}: a person's pull request; the fail at ${head} is in its fail comment and the ${FAILED_LABEL} label holds it`);
}

// Whether the dot-joined numbers a name carries are the issues the verdict
// records, as sets.
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

// For a pass: whether a lanes App pull request is open at the head it judged
// and holds an open fail-note thread from another head, which only reads; a
// person's pull request there loses the label instead.
export async function findStaleNotes({ api, verdict, appId, log }) {
  const { pr, head } = verdict;
  laneAppId(appId);
  const pull = await api.getPull(pr);
  if (pull.state !== "open" || pull.head?.sha !== head) {
    log(`skip: #${pr} is not open at head ${head}`);
    return false;
  }
  if (pull.user?.id !== appId) {
    if (await hasLabel(api, pr)) {
      await api.removeLabel(pr, FAILED_LABEL);
      log(`#${pr}: the ${verdict.verdict} at ${head} removed ${FAILED_LABEL}`);
    }
    return false;
  }
  const stale = staleVerifyNotes(await api.listThreads(pr), head);
  log(`#${pr}: ${stale.length} open fail-note thread(s) from an earlier head than the ${verdict.verdict} at ${head}`);
  return stale.length > 0;
}

// For a fail: whether its notes are on a lanes App pull request, so a round
// starts. A person's pull request gets its fail comment and label instead.
// `humanGatedLabel` reads the label's name, and only the credential hold calls
// it, so a config it cannot read stops no other fail.
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
    await holdPersonPull({ api, verdict, log });
    return false;
  }
  const posted = new Set(
    (await api.listReviewComments(pr))
      .filter((comment) => comment.user?.id === MARKER_AUTHOR_ID && comment.commit_id === head && firstLine(comment.body) === VERIFY_NOTE_MARKER)
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
      // Each answer's rate-limit reading, for the job-end api-budget notice.
      fetch: rateLimitLatch.guard(globalThis.fetch),
    });
  if (verdict.verdict !== "fail") {
    if (await findStaleNotes({ api: client, verdict, appId, log })) {
      appendFileSync(env.GITHUB_OUTPUT, `pass-head-sha=${verdict.head}\n`);
    }
  } else if (await postNotes({ api: client, verdict, appId, humanGatedLabel: () => humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/.work-item-tracker.json"), log })) {
    appendFileSync(env.GITHUB_OUTPUT, `pr-number=${verdict.pr}\nhead-sha=${verdict.head}\n`);
  }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::verify-notes failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
