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
// posts the rest and nothing twice. On a pull request the lanes App did not open (an
// adopted one, `merge.verify-authors: lane-or-owner`) no round starts, and the
// notes tell its author why the pr-merge lane refuses it. Each note that starts with a path the pull
// request changes (`path` or `path:line`, backticks allowed) goes on that
// file; the summary and every other note go on the first such file, or on the
// pull request's first changed file when no note names one. Model text is
// quoted as data in a text fence, never interpolated into a command.
//
// Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT, ARTIFACT_NAME
// (pr-verify-<pr>-<sha>-fail, then the head-ref digest write-verdict.mjs
// adds, absent on an older verdict) and
// VERDICT_FILE (its verdict.json). Writes pr-number and head-sha outputs once
// the notes are on the pull request, posted now or by an earlier run.

import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { headRefDigest } from "../pr-verify/write-verdict.mjs";
import { createGitHubApi, MARKER_AUTHOR_ID, need, VERIFY_NOTE_MARKER } from "./address-feedback.mjs";

export const FAIL_NAME = /^pr-verify-([1-9][0-9]{0,9})-([0-9a-f]{40})-fail(?:-([0-9a-f]{16}))?$/;
// GitHub refuses a comment body over 65536 characters; leave room for the
// framing (judgment).
const BODY_MAX = 60000;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

// The changed path a note starts with, or null.
export function notePath(note, files) {
  const token = String(note).trimStart().split(/\s/, 1)[0] ?? "";
  const path = token
    .replace(/^[`'"([*]+/, "")
    .replace(/[`'")\]*.,;:]+$/, "")
    .replace(/:[0-9]+(-[0-9]+)?$/, "");
  return files.includes(path) ? path : null;
}

// One fenced quote, with no fence inside it and no control character.
function quote(lines) {
  // biome-ignore lint/suspicious/noControlCharactersInRegex: control characters are what it removes
  const text = lines.join("\n").replace(/\r\n/g, "\n").replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "?").replaceAll("```", "'''");
  return ["```text", text.length > BODY_MAX ? `${text.slice(0, BODY_MAX)} [cut]` : text, "```"].join("\n");
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

export function readVerdict(name, text) {
  const match = FAIL_NAME.exec(name ?? "");
  if (!match) {
    throw new Error("the artifact name is not a pr-verify fail verdict");
  }
  const verdict = JSON.parse(text);
  if (
    verdict?.verdict !== "fail" ||
    verdict.pr !== Number(match[1]) ||
    verdict.head_sha !== match[2] ||
    (match[3] !== undefined && headRefDigest(verdict.head_ref) !== match[3]) ||
    typeof verdict.summary !== "string" ||
    !Array.isArray(verdict.notes) ||
    !verdict.notes.every((note) => typeof note === "string")
  ) {
    throw new Error("the verdict file does not record the fail its name names");
  }
  return { pr: verdict.pr, head: verdict.head_sha, summary: verdict.summary, notes: verdict.notes };
}

export async function postNotes({ api, verdict, log }) {
  const { pr, head } = verdict;
  const pull = await api.getPull(pr);
  if (pull.state !== "open" || pull.head?.sha !== head) {
    log(`skip: #${pr} is not open at head ${head}`);
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
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "ARTIFACT_NAME", "VERDICT_FILE"]);
  const verdict = readVerdict(env.ARTIFACT_NAME, readFileSync(env.VERDICT_FILE, "utf8"));
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
    });
  if (await postNotes({ api: client, verdict, log })) {
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
