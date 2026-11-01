// The pr-unblock lane's address-feedback thread selection, shared by the model
// job's runner step and the reply job's script (publish-feedback.mjs). It runs
// no PR head code and hands the model no decision.
//
//   select  run by .github/workflows/pr-unblock.yml's address-feedback-select
//           job, which runs only base code, before the model job and any
//           model turn, with the job's read-only token: keeps the unresolved
//           review threads the reviewer bot or a listed review bot opened
//           in a review on a head a review lane's marker confirms, when
//           every comment is the bot's (a listed bot's only behind a trusted
//           person's `@codex` request, requestSkip),
//           a trusted person with write access asked the lane to fix it, or
//           a trusted person answered the lane's escalation, then decides
//           skip (no such thread), escalate (the PR changes
//           .github/workflows/**; or the configured number of rounds already
//           ran, no write-access fix request came after the newest one, and
//           a person gated the PR or a kept thread is one only a person
//           decides, needsPerson, or
//           the fresh fixer's round past the cap already ran) or proceed,
//           writing the thread file
//           the skill's review-thread tool reads, with the same-plugin files
//           a write-access fix request names (namedPaths) and the files the
//           PR already changes (pr_paths, prPathsOf), and run.json, the
//           record the reply job checks the replies against, with the
//           reviewed heads the threads were kept on (runRecord). On a PR carrying the
//           human-gated label it keeps only threads a trusted person with
//           write access asked it to fix (isFixRequest), and skips
//           awaiting-human when there are none, unless a lane escalation put
//           the label on and no review lane holds the PR (gate-source.mjs),
//           and on an adopted owner PR only as prHold lets fix-ci work it.
//           On an adopted owner PR a body line starting `Hold:` skips
//           awaiting-human. An untaken thread whose stop on this head is
//           already in the session-builder queue (sessionQueued) skips
//           awaiting-session instead of escalating again.
//
// Every comment body is copied into the thread file and never logged or
// interpolated into a command. Only a trusted person's reply to the lane's
// escalation, or with no escalation a trusted person's comment from the first
// write-access fix request on, is marked as direction; every other body is
// data.

import { execFileSync } from "node:child_process";
import { appendFileSync, lstatSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { commentItems, FAILING, gateSource, laneHold, latestRuns, listLabelEvents, prHold, ROUND_MARKER } from "./gate-source.mjs";
import { retryFetch } from "./retry-fetch.mjs";
import { isProtectedPath, namedInScope, prPathsOf } from "./thread-scope.mjs";
import { retryRung, ROUTES, stopSkip } from "./escalation-routes.mjs";

// The round cap is the config's `loop.review-rounds`, passed in as
// REVIEW_ROUNDS; the resolver's default is the fallback.
export const DEFAULT_MAX_ROUNDS = 2;
// Rounds past the cap that go to a fresh fixer instead of a person
// (judgment: one more new session on the findings the capped rounds left; a
// PR still drawing findings after it is not converging, and more rounds only
// spend usage).
export const FRESH_FIXER_ROUNDS = 1;
// The fresh fixer round's brief, the thread file's `retry.brief`: fixed text,
// never anything a head, a finding or a model wrote. The read runner adds it
// to the skill's preamble (collect-base-activity).
export const FRESH_ROUND_BRIEF =
  "The lane's capped review rounds left these findings open, and this run is their one fresh fixer round before the lane stops. " +
  "Fix each finding in the code it names. Never weaken, skip or delete a test, assertion or check to close a finding. " +
  "A security finding rated CRITICAL that this round leaves open goes to a person.";
// How the round marker and the neutral checks show the count.
export const roundLine = (round, max) => `round ${round} of max ${max}`;
export { ROUND_MARKER };
// The activity select decides, as escalation-routes.json names it.
const ACTIVITY = "address-feedback";
// github-actions[bot], the author of the review lanes' reviewed-head markers.
export const MARKER_AUTHOR_ID = 41898282;
const REVIEWED_HEAD =
  /^<!-- claude-lane-reviewed-head lane=(claude-review|claude-security-review) sha=([0-9a-f]{40}) -->$/;
export const SHA = /^[0-9a-f]{40}$/;
// The first line of each review comment verify-notes.mjs posts, as
// github-actions[bot] (MARKER_AUTHOR_ID), with a pr-verify FAIL's notes. Such
// a comment opens a thread this lane works like the reviewer bot's.
export const VERIFY_NOTE_MARKER = "<!-- pr-verify:fail-note -->";
const THREAD_COMMENT_CAP = 100;
// The most files the pulls files listing returns
// (docs.github.com/en/rest/pulls/pulls#list-pull-requests-files, as of
// 2026-10-15; recheck when that section changes its limit).
const FILES_CAP = 3000;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

// The checkout this script runs from: the select job's base copy.
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");

// scripts/plan-test-lanes.sh over `paths`, the selection pr-require-checks.yml's
// select-tests job makes, as its key=value lines.
export function planLanes(paths, root = ROOT) {
  const out = execFileSync("bash", [join(root, "scripts/plan-test-lanes.sh"), "--", ...paths], {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
    maxBuffer: 16 * 1024 * 1024,
  });
  return Object.fromEntries(
    out
      .split("\n")
      .filter((line) => line.includes("="))
      .map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)]),
  );
}

// The check-run names a plan's lanes post: test-bash, test-python and
// test-node in pr-require-checks.yml (a matrix lane once per leg its
// bash_legs or python_legs lists, as `<lane> (<leg>)`), and each
// pr-test-platforms.yml job it names. An unreadable leg list throws.
const legs = (value) => {
  const list = JSON.parse(value || "[0]");
  if (!Array.isArray(list) || list.length === 0 || !list.every((leg) => Number.isSafeInteger(leg) && leg >= 0)) {
    throw new Error("a lane's legs are not a list of leg numbers");
  }
  return list;
};
export function coveringLanes(plan) {
  const matrix = ["bash", "python"].filter((lane) => plan[lane] === "true").flatMap((lane) => legs(plan[`${lane}_legs`]).map((leg) => `test-${lane} (${leg})`));
  const node = plan.node === "true" ? ["test-node"] : [];
  const windows = JSON.parse(plan.windows_jobs || "[]");
  return [...matrix, ...node, ...(Array.isArray(windows) ? windows.filter((job) => typeof job === "string") : [])];
}

// A test lane's check-run name: every test job in pr-require-checks.yml and
// pr-test-platforms.yml is named test-<lane>, a matrix leg `test-<lane> (<leg>)`.
const TEST_LANE = /^test-[a-z0-9]+(?:-[a-z0-9]+)*(?: \(\d+\))?$/;
// A cancelled run is not red: fix-ci does not take a head whose only failing
// checks were cancelled (fix-ci-dispatch.mjs), so it settles nothing instead.
const failed = (run) => run.status === "completed" && FAILING.has(run.conclusion);
const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);

// The head's CI for the tests the PR selects, which the reply job settles a
// tests-only finding from (adjudicate-feedback.mjs settleDisputes): the
// latest real run (gate-source.mjs latestRuns) of each github-actions check.
// The plan is read from the base tree, so it can list fewer lanes than the
// head's select-tests job ran. red: any test lane run on the head failed,
// planned or not; green: every covering lane the plan names
// has a run, each one passed, and no test lane the plan does not name ran;
// unsettled otherwise (pending, cancelled, missing or skipped, an unplanned lane that
// ran, a listing past its pages, no covering lane, or a failed read), which
// settles nothing.
export async function ciSnapshot({ api, headSha, files, plan = planLanes }) {
  try {
    const lanes = coveringLanes(plan([...new Set(files.flatMap((file) => [file?.filename, file?.previous_filename]).filter((path) => typeof path === "string" && path !== ""))].sort()));
    const listed = await api.listCommitCheckRuns(headSha);
    const tests = [...latestRuns(listed.filter((run) => run?.app?.slug === "github-actions")).values()].filter((run) => TEST_LANE.test(String(run.name)));
    const red = tests.filter(failed).sort(byName);
    if (red.length > 0) {
      return { state: "red", runs: red.map((run) => ({ name: run.name, url: run.html_url })) };
    }
    const runs = tests.filter((run) => lanes.includes(String(run.name))).sort(byName);
    const unplanned = tests.some((run) => !lanes.includes(String(run.name)) && run.conclusion !== "skipped");
    const passed =
      lanes.length > 0 &&
      listed.complete !== false &&
      !unplanned &&
      lanes.every((lane) => runs.some((run) => run.name === lane)) &&
      runs.every((run) => run.status === "completed" && run.conclusion === "success");
    return { state: passed ? "green" : "unsettled", runs: runs.map((run) => ({ name: run.name, url: run.html_url })) };
  } catch {
    return { state: "unsettled", runs: [] };
  }
}

// GitHub refuses a comment body over 65536 characters; leave room for the
// framing (judgment).
const BODY_MAX = 60000;

// GitHub scrolls a long line in a code block instead of wrapping it, so each
// quoted line is broken at a space to fit WRAP columns, its continuations
// indented two spaces; a word longer than that (a URL, a path) stays whole. A
// quote over FOLD_LINES lines folds into a <details> block (judgment).
export const WRAP = 100;
const FOLD_LINES = 20;

export function wrapLine(line, width = WRAP) {
  const out = [];
  let lead = "";
  let rest = line;
  while (lead.length + rest.length > width) {
    const room = width - lead.length;
    let cut = rest.lastIndexOf(" ", room);
    if (cut <= 0) cut = rest.indexOf(" ", room);
    if (cut <= 0) break;
    out.push(lead + rest.slice(0, cut).trimEnd());
    rest = rest.slice(cut + 1).trimStart();
    lead = "  ";
  }
  out.push(lead + rest);
  return out;
}

// One fenced quote, with no fence inside it and no control character. The
// fence keeps the quoted text inert: no mention, reference, link or HTML
// renders, and no line of it reads as a lane footer, rating or fix request.
// `summary` labels the <details> block a long quote folds into.
export function quote(lines, summary = (count) => `What it wrote (${count} lines)`) {
  // biome-ignore lint/suspicious/noControlCharactersInRegex: control characters are what it removes
  const text = lines.join("\n").replace(/\r\n/g, "\n").replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "?").replaceAll("```", "'''");
  const wrapped = (text.length > BODY_MAX ? `${text.slice(0, BODY_MAX)} [cut]` : text).split("\n").flatMap((line) => wrapLine(line));
  const fence = ["```text", ...wrapped, "```"].join("\n");
  return wrapped.length > FOLD_LINES ? [`<details><summary>${summary(wrapped.length)}</summary>`, "", fence, "", "</details>"].join("\n") : fence;
}

// The ids of the unresolved threads (listThreads) a pr-verify FAIL's notes
// opened on a head other than `head`: the first comment is
// github-actions[bot]'s, opens with VERIFY_NOTE_MARKER, and was posted on
// another commit (its original commit, which a later push does not move). A
// pass at `head` supersedes them: post-verify-notes finds them, and
// publish-feedback.mjs resolves them as the lanes App.
export function staleVerifyNotes(threads, head) {
  return threads
    .filter((thread) => {
      const root = thread.root?.nodes?.[0];
      const commit = root?.originalCommit?.oid ?? "";
      return thread.isResolved === false && root?.author?.databaseId === MARKER_AUTHOR_ID && firstLine(root.body) === VERIFY_NOTE_MARKER && SHA.test(commit) && commit !== head;
    })
    .map((thread) => thread.id);
}

// A review lane's own comment as the pr-review-cli reusable posts it: by
// github-actions[bot] (MARKER_AUTHOR_ID), its last non-blank line the lane's
// `claude-lane: <lane>` footer. Any other github-actions[bot] comment is not a
// finding.
const LANE_FOOTER = /^`?claude-lane: (claude-review|claude-security-review)`?$/;
const lastLine = (body) =>
  String(body ?? "")
    .split("\n")
    .map((line) => line.trim())
    .findLast((line) => line !== "") ?? "";
// The lane a comment body's footer names, or null.
export const laneOf = (body) => LANE_FOOTER.exec(lastLine(body))?.[1] ?? null;
export const isLaneComment = (comment) => comment.authorId === MARKER_AUTHOR_ID && laneOf(comment.body) !== null;

// The security-review lane's ratings, lowest first (security-review SKILL.md,
// "Reporting": one `severity: <rating>` line per inline comment), and the
// one a person decides: only CRITICAL holds (owner decision on #11020).
export const SECURITY_SEVERITIES = Object.freeze(["SUGGESTION", "IMPORTANT", "CRITICAL"]);
export const SECURITY_PERSON_SEVERITY = "CRITICAL";
// Any line shaped like a rating, wherever it sits: the word behind any run of
// leading markup (indent, `>`, bold or italic, a code span, a heading, a list
// bullet or number), closing markup after it, then a colon or a spaced dash,
// so `**Severity**: X`, `- severity: X`, `### Severity: X` and `Severity - X`
// all count; the lane's own line is unindented, outside a fence, and the
// comment's first line or the last one above its `claude-lane:` footer (blank
// lines skipped).
export const SEVERITY_SHAPED = /^[ \t>*_`#+\-\d.]*severity[*_`]*[ \t]*(?::|[-–—][ \t])/i;
// A body that names the security-review lane behind a `lane:` or `claude-lane:`
// label: anywhere on the label's line (behind another name, in brackets, with
// markup or a trail), or on the next non-blank line when the label ends its
// own. Prose that only mentions the lane's name is no claim.
const SECURITY_LANE_NAMED = /\blane:\s*[^\n]*claude-security-review/i;
const SEVERITY_LINE = /^severity:[ \t]*([A-Za-z]+)[ \t]*$/i;
const FENCE = /^[ \t]*(```|~~~)/;
// A lane comment's one rating, upper-cased, or null (unrated, so a person
// decides) unless the body holds exactly one rating-shaped line and it is the
// lane's own: unindented, outside any fenced block, and the first non-blank
// line or the last non-blank line above the lane footer. A rating quoted from
// the pull request (fenced, indented, `>`-quoted or mid-body) never supplies
// it, and any second rating-shaped line voids it.
export function severityOf(body) {
  const lines = String(body ?? "")
    .split("\n")
    .map((line) => line.replace(/\r$/, ""));
  const content = [];
  let fence = null;
  for (const line of lines) {
    const open = FENCE.exec(line)?.[1];
    if (fence === null && open) {
      fence = open;
      content.push({ line, fenced: true });
      continue;
    }
    if (fence !== null) {
      if (open === fence) {
        fence = null;
      }
      content.push({ line, fenced: true });
      continue;
    }
    content.push({ line, fenced: false });
  }
  const shaped = content.filter(({ line }) => SEVERITY_SHAPED.test(line));
  if (shaped.length !== 1 || shaped[0].fenced) {
    return null;
  }
  const nonBlank = content.filter(({ line }) => line.trim() !== "");
  const footer = nonBlank.length > 0 && laneOf(nonBlank.at(-1).line) !== null;
  const positions = [nonBlank[0], footer ? nonBlank.at(-2) : undefined];
  const match = positions.includes(shaped[0]) ? SEVERITY_LINE.exec(shaped[0].line) : null;
  const rating = match?.[1].toUpperCase();
  return SECURITY_SEVERITIES.includes(rating) ? rating : null;
}
// Whether a security-review lane comment is one a person decides: rated at or
// above `floor` (SECURITY_PERSON_SEVERITY unless given), or with no rating it
// can read (fail closed).
export const securityNeedsPerson = (body, floor = SECURITY_PERSON_SEVERITY) => {
  const severity = severityOf(body);
  return severity === null || SECURITY_SEVERITIES.indexOf(severity) >= SECURITY_SEVERITIES.indexOf(floor);
};
// Whether the reviewer bot's own finding claims a security rating a person
// decides at `floor`. Its footer is model text, so the claim is read from the
// content, never from an exact footer: a body that names the security-review
// lane behind a label (SECURITY_LANE_NAMED, a malformed or trailed footer
// included) or holds any rating-shaped line (SEVERITY_SHAPED) is a security
// claim, and securityNeedsPerson rules it: a rating it can read at or above
// `floor`, or none it can read, keeps the hold such a lane finding has. Only a
// body with neither is the code lane's: a claim worded outside those two
// shapes reads as prose.
export const claimsSecurity = (body, floor = SECURITY_PERSON_SEVERITY) => {
  const text = String(body ?? "");
  const claims = SECURITY_LANE_NAMED.test(text) || text.split("\n").some((line) => SEVERITY_SHAPED.test(line));
  return claims && securityNeedsPerson(text, floor);
};

// A thread whose first comment is a pr-verify verifier note (threadAuthors).
const isVerifierNote = (thread) => thread.comments[0]?.author === "verifier";
const isDirected = (thread) => thread.comments.some((comment) => comment.direction === true);

// Past the round cap, the threads only a person may still decide: a security
// lane finding rated at or above `floor` or unrated (securityNeedsPerson), a
// verifier note or listed review bot's finding a trusted person directed, and
// a listed bot's finding on a head the security-review lane held as CRITICAL
// (keepThreads' `security` state; the bot's own badge decides nothing). Only
// on a github-actions[bot] root (`rootAuthorId`) is a lane footer the
// pr-review-cli reusable's, never model text, so a reviewer root by anyone
// else is the reviewer bot's own finding (claude[bot]), which is ruled as the
// code lane's unless its text names the security-review lane or carries a
// rating, rated at or above `floor` or with no rating it can read
// (claimsSecurity). A listed bot is matched on its account id (keepThreads'
// `listed`, from pr-pipeline.yaml review-threads.reviewer-ids).
// The code lane's finding, the reviewer bot's own, a listed bot's other
// findings, a security lane finding rated below `floor` and an undirected
// verifier note go to a fresh fixer: a round cap is a lane bound, and
// pr-verify's FAIL already holds the merge and judges the next head afresh.
export const needsPerson = (thread, rootAuthorId, floor = SECURITY_PERSON_SEVERITY) => {
  if (isVerifierNote(thread)) {
    return isDirected(thread);
  }
  const root = thread.comments[0];
  if (root?.author !== "reviewer") {
    return true;
  }
  if (root.listed === true) {
    return root.security === "held" || isDirected(thread);
  }
  if (rootAuthorId !== MARKER_AUTHOR_ID) {
    return claimsSecurity(root.body, floor);
  }
  const lane = laneOf(root.body);
  return lane === "claude-security-review" ? securityNeedsPerson(root.body, floor) : lane !== "claude-review";
};

// Round markers the lanes App posted; any other author's copy is ignored.
export const isRoundMarker = (comment, appId) => comment.user?.id === appId && firstLine(comment.body) === ROUND_MARKER;

export function countRounds(issueComments, appId) {
  return issueComments.filter((comment) => isRoundMarker(comment, appId)).length;
}

// The model job's check run, posted by its report job with the job token on
// the head it gated. A round that took a model turn ends success or failure;
// skips end neutral. It counts rounds the reply job could not record (a gate
// or broker refusal after the push moved the head); a forged one only stops
// the lane sooner.
export const MODEL_CHECK = "pr-unblock / address-feedback";
// The reply job's check: a lane stop there runs the head's retry a rung up.
export const REPLY_CHECK = "pr-unblock / publish-feedback";
const isModelRun = (run, conclusions) =>
  run.name === MODEL_CHECK && run.app?.slug === "github-actions" && conclusions.includes(run.conclusion);
export function countCheckRounds(checkRunsByCommit) {
  return checkRunsByCommit.filter((runs) => runs.some((run) => isModelRun(run, ["success", "failure"]))).length;
}

// When the newest round ended: the latest of the round markers' creation and
// the model check runs' completion, a cancelled or timed-out one included so
// one fix request cannot start a round again after such a run. NaN when any of
// them has no readable time, so no fix request counts as newer.
export function lastRoundAt(issueComments, appId, checkRunsByCommit) {
  const ended = ["success", "failure", "cancelled", "timed_out"];
  const times = [
    ...issueComments.filter((comment) => isRoundMarker(comment, appId)).map((comment) => comment.created_at),
    ...checkRunsByCommit.flat().filter((run) => isModelRun(run, ended)).map((run) => run.completed_at),
  ].map((time) => Date.parse(time ?? ""));
  return times.some(Number.isNaN) ? Number.NaN : Math.max(...times);
}

// The security-review lane's own signals on the PR: the heads it reviewed
// (its reviewed-head marker, posted by github-actions[bot]) and the holds it
// posted for a person on a CRITICAL rating (its hold comment naming
// lane=claude-security-review and the critical-security criterion; laneHold
// checks the author and footer), each with when it was posted.
const SECURITY_HOLD = /^<!-- claude-lane-hold lane=claude-security-review sha=([0-9a-f]{40}) criteria=([a-z,-]+) -->$/;
export function securitySignals(issueComments) {
  const reviewed = new Set();
  const holds = [];
  for (const comment of issueComments) {
    const marker = comment.user?.id === MARKER_AUTHOR_ID ? REVIEWED_HEAD.exec(firstLine(comment.body)) : null;
    if (marker?.[1] === "claude-security-review") {
      reviewed.add(marker[2]);
    }
    const hold = SECURITY_HOLD.exec(laneHold({ event: "commented", ...comment }) ?? "");
    if (hold?.[2].split(",").includes("critical-security")) {
      holds.push({ sha: hold[1], at: Date.parse(comment.created_at ?? "") });
    }
  }
  return { reviewed, holds };
}

// A listed bot's finding as the security-review lane left the PR: held (a
// critical-security hold on the head the bot reviewed, or one posted at or
// after its review, so on a later head), clear (the lane reviewed that head
// and holds nothing), or pending (the lane has not reviewed it yet).
export function securityState({ reviewed, holds }, review) {
  const since = Date.parse(review.submitted_at ?? "");
  if (holds.some((hold) => hold.sha === review.commit_id || hold.at >= since)) {
    return "held";
  }
  return reviewed.has(review.commit_id) ? "clear" : "pending";
}

export function reviewedHeads(issueComments) {
  const heads = new Set();
  for (const comment of issueComments) {
    if (comment.user?.id !== MARKER_AUTHOR_ID) {
      continue;
    }
    const match = REVIEWED_HEAD.exec(firstLine(comment.body));
    if (match) {
      heads.add(match[2]);
    }
  }
  return heads;
}

// The first line of the reply publish-feedback.mjs posts on a thread it
// leaves open: every disposition but VALID; older threads still carry the
// `for a person` forms.
const ESCALATION_REPLY =
  /^\*\*pr-unblock \/ address-feedback: (INCORRECT, left open|UNCERTAIN, left open(?: for a person)?|VALID \(defer\), left open(?: for a person)?)\*\*$/;
// The first line of the reply publish-feedback.mjs posts when an adjudicator
// finds a disputed finding stands (adjudicate-feedback.mjs): the next round
// works that thread again and accepts no second INCORRECT on it.
export const FINDING_STANDS = "<!-- pr-unblock adjudicate-feedback: finding-stands -->";
export const isEscalationReply = (comment, appId) => comment?.user?.id === appId && ESCALATION_REPLY.test(firstLine(comment.body));

// On a PR carrying the human-gated label, a thread is worked only when a
// trusted person with write access asks for it: a line of their reply that
// starts with this phrase, in any case, outside a fenced code block. A quoted
// line starts with `>`, so it never matches.
export const FIX_REQUEST = /^pr-fix lane: please fix this finding(?=[\s.:;,!]|$)/i;
export function isFixRequest(body) {
  let fenced = false;
  for (const line of String(body ?? "").split("\n")) {
    if (/^ {0,3}(```|~~~)/.test(line)) {
      fenced = !fenced;
    } else if (!fenced && FIX_REQUEST.test(line.replace(/\r$/, ""))) {
      return true;
    }
  }
  return false;
}

// The file-shaped words of a fix request's body outside fenced code blocks and
// quoted lines: each word with wrapping backticks, quotes, brackets or
// emphasis, trailing punctuation and a trailing :line or :line-line removed,
// kept when its last segment has an extension. A _ is a legal first or last
// character of a name, so it is emphasis only as a matched pair.
const WRAP_START = /^[`'"([{<*]+/;
const WRAP_END = /[`'")\]}>*.,;:!?]+$/;
const UNDERSCORE_PAIR = /^(_+)(.+)\1$/;
export function pathTokens(body) {
  const tokens = new Set();
  let fenced = false;
  for (const raw of String(body ?? "").split("\n")) {
    const line = raw.replace(/\r$/, "");
    if (/^ {0,3}(```|~~~)/.test(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced || /^ {0,3}>/.test(line)) {
      continue;
    }
    for (const word of line.split(/\s+/)) {
      const token = word
        .replace(WRAP_START, "")
        .replace(WRAP_END, "")
        .replace(UNDERSCORE_PAIR, "$2")
        .replace(/:[1-9][0-9]*(-[1-9][0-9]*)?$/, "");
      if (/\.[A-Za-z0-9]+$/.test(token.slice(token.lastIndexOf("/") + 1))) {
        tokens.add(token);
      }
    }
  }
  return [...tokens];
}

// The most named paths one thread adds, counted after the existence check.
export const NAMED_CAP = 10;
// The most distinct directories one thread's existence check reads.
export const TREE_READ_CAP = 2 * NAMED_CAP;
// A regular or executable file's git mode, as GraphQL's TreeEntry.mode gives
// it (100644 and 100755 in decimal): a symbolic link (120000) and a gitlink
// (160000) are never named in.
const FILE_MODES = new Set([0o100644, 0o100755]);

// The paths a kept thread's fix requests name that may join its scope: each
// path token of a comment by one of `fixers` that is a fix request
// (isFixRequest), read as repository-relative when it holds a / and as a
// file in the thread path's directory when it does not, allowed by
// namedInScope for the thread, and a regular file at `headSha`
// (`listTree(sha, dir)` answers the directory's GraphQL tree entries).
export async function namedPaths({ thread, reviewComments, fixers, headSha, listTree }) {
  const rows = new Map(reviewComments.map((row) => [row.id, row]));
  const dir = thread.path.slice(0, thread.path.lastIndexOf("/") + 1);
  const candidates = new Set();
  for (const comment of thread.comments) {
    const row = rows.get(comment.id);
    if (comment.author !== "trusted-human" || !fixers.has(row?.user?.id) || !isFixRequest(row.body)) {
      continue;
    }
    for (const token of pathTokens(row.body)) {
      const path = token.includes("/") ? token : `${dir}${token}`;
      if (path !== thread.path && namedInScope(path, thread.path)) {
        candidates.add(path);
      }
    }
  }
  const trees = new Map();
  const named = [];
  for (const path of candidates) {
    if (named.length === NAMED_CAP) {
      break;
    }
    const parent = path.slice(0, path.lastIndexOf("/"));
    if (!trees.has(parent)) {
      if (trees.size === TREE_READ_CAP) {
        continue;
      }
      trees.set(parent, await listTree(headSha, parent));
    }
    const entry = trees.get(parent).find((e) => e.name === path.slice(parent.length + 1));
    if (entry?.type === "blob" && FILE_MODES.has(entry.mode)) {
      named.push(path);
    }
  }
  return named;
}

// The ids of the trusted people who wrote a fix request in `comments` (each
// { authorId, login, body }) and hold write or admin permission on the
// repository now (`permission(login)` answers GitHub's permission field).
export async function fixRequesters({ comments, trustedHumans, permission }) {
  const logins = new Map();
  for (const comment of comments) {
    if (trustedHumans.has(comment.authorId) && comment.login && isFixRequest(comment.body)) {
      logins.set(comment.authorId, comment.login);
    }
  }
  const writers = new Set();
  for (const [id, login] of logins) {
    if (["admin", "write"].includes(await permission(login))) {
      writers.add(id);
    }
  }
  return writers;
}

// fixRequesters over a PR's review comments (the REST rows).
export const reviewFixers = ({ reviewComments, trustedHumans = new Set(), permission }) =>
  fixRequesters({
    comments: reviewComments.map((row) => ({ authorId: row.user?.id, login: row.user?.login, body: row.body })),
    trustedHumans,
    permission,
  });

// The base's human-gated role label: config.role_labels["human-gated"] of
// .work-item-tracker.json, needs-human when the file or entry is absent.
export function humanGatedLabelFrom(path) {
  let config;
  try {
    config = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") {
      return "needs-human";
    }
    throw new Error(`cannot read ${path}`);
  }
  const roles = config?.config?.role_labels ?? {};
  if (!Object.hasOwn(roles, "human-gated")) {
    return "needs-human";
  }
  const label = roles["human-gated"];
  if (typeof label !== "string" || label === "") {
    throw new Error("the human-gated role label is not a non-empty string");
  }
  return label;
}

// Who wrote each comment of a thread, or null when it is not one to work.
// `comments` are oldest first, each { authorId, createdAt, body, lastEditedAt,
// editorId }. The first is the reviewer bot's, a listed review bot's (one of
// `reviewerIds`, pr-pipeline.yaml review-threads.reviewer-ids, matched on the
// account id GitHub records; its comments count as the reviewer bot's
// throughout), a lane comment (isLaneComment, which counts as the reviewer
// bot's throughout), a verifier note
// (github-actions[bot]'s, its first line VERIFY_NOTE_MARKER), or a trusted
// person's (a thread they opened, worked only under the fix-request or
// escalation rule below), and one of these holds:
// - every comment is the reviewer bot's, but a verifier note's own;
// - the lanes App never commented, every later comment is the reviewer bot's
//   or a trusted person's, and one is a fix request (isFixRequest) by one of
//   `fixers` (the trusted people with write access who wrote a fix request,
//   fixRequesters); the trusted people's comments from the first such
//   request on are direction;
// - the lanes App's last comment escalated the thread and every comment after
//   it is a trusted person's reply, which is direction;
// - the lanes App's last comment is an adjudication that let the finding
//   stand (FINDING_STANDS), and every comment after it, if any, is a trusted
//   person's reply, which is direction.
// A comment by anyone else, a trusted person's comment last edited by anyone
// but a trusted person, or a reply not after the escalation leaves the thread
// alone. The select step and the reply job (keepThreads) and the dispatcher
// (feedback-dispatch.mjs) all judge a thread with this. With `requesters` (a
// set of ids, given on a PR carrying the human-gated label), a thread is
// worked only when a reply is a fix request by one of them, after the
// escalation when there is one.
export function threadAuthors(comments, { reviewerId, reviewerIds = [], appId, trustedHumans = new Set(), requesters = null, fixers = requesters ?? new Set() }) {
  const verifier = comments.length > 0 && comments[0].authorId === MARKER_AUTHOR_ID && firstLine(comments[0].body) === VERIFY_NOTE_MARKER;
  const reviewer = (comment) => comment.authorId === reviewerId || reviewerIds.includes(comment.authorId) || isLaneComment(comment);
  const isHuman = (comment) =>
    trustedHumans.has(comment.authorId) && (comment.lastEditedAt == null || trustedHumans.has(comment.editorId));
  if (comments.length === 0 || (!reviewer(comments[0]) && !verifier && !isHuman(comments[0]))) {
    return null;
  }
  const finder = (comment, i) => (i === 0 && verifier ? { author: "verifier" } : reviewer(comment) ? { author: "reviewer" } : null);
  if (comments.every((comment, i) => finder(comment, i) !== null)) {
    return requesters ? null : comments.map(finder);
  }
  const asks = (ids, comment) => ids.has(comment.authorId) && isFixRequest(comment.body);
  const last = comments.findLastIndex((comment) => comment.authorId === appId);
  if (last === -1) {
    const humanAsks = (ids) => comments.some((comment) => isHuman(comment) && asks(ids, comment));
    if (!humanAsks(fixers) || (requesters && !humanAsks(requesters))) {
      return null;
    }
    const asked = comments.findIndex((comment) => isHuman(comment) && asks(fixers, comment));
    const authors = [];
    for (const [i, comment] of comments.entries()) {
      if (finder(comment, i)) {
        authors.push(finder(comment, i));
      } else if (isHuman(comment)) {
        authors.push(i >= asked ? { author: "trusted-human", direction: true } : { author: "trusted-human" });
      } else {
        return null;
      }
    }
    return authors;
  }
  // An adjudication that let the finding stand (adjudicate-feedback.mjs)
  // hands the thread back to the lane with no reply needed.
  const stands = last >= 1 && firstLine(comments[last].body) === FINDING_STANDS;
  if (last < 1 || !(stands || ESCALATION_REPLY.test(firstLine(comments[last].body))) || (last === comments.length - 1 && !stands)) {
    return null;
  }
  if (requesters && !comments.slice(last + 1).some((comment) => asks(requesters, comment))) {
    return null;
  }
  const escalatedAt = Date.parse(comments[last].createdAt ?? "");
  const authors = [];
  for (const [i, comment] of comments.entries()) {
    const id = comment.authorId;
    const human = isHuman(comment);
    if (i > last) {
      // NaN compares false, so an unparsable time leaves the thread alone.
      if (!human || !(Date.parse(comment.createdAt ?? "") > escalatedAt)) {
        return null;
      }
      authors.push({ author: "trusted-human", direction: true });
    } else if (finder(comment, i) || id === appId || human) {
      authors.push(finder(comment, i) ?? { author: id === appId ? "lane" : "trusted-human" });
    } else {
      return null;
    }
  }
  return authors;
}

// A `@codex` mention in any case, as a whole handle: the request that asks
// chatgpt-codex-connector[bot] for a review. Code spans and fences count, as
// the bot answers a mention there.
export const CODEX_MENTION = /(?:^|[^\w@/.-])@codex(?![\w-])/i;
// What counts as an untrusted request: `@codex` after any character, so a
// form the bot may also answer (`x.@codex`) never slips past (fail closed).
const ANY_CODEX_MENTION = /@codex(?![\w-])/i;

// Why the `@codex` request behind a listed bot's review is not a trusted
// person's, or null when it is. Anyone can comment `@codex` on a public repository, so a
// request is looked for in the window from the same bot's previous review to
// this one (`authorId`'s review submitted at `submittedAt`): `mentions` are
// the PR's issue comments, review comments and review bodies, each
// { authorId, createdAt, editedAt, body }, and `reviews` its reviews, each
// { authorId, submittedAt }. The listed bots' own text never counts (Codex's
// review names `@codex review` in its help text). Any untrusted request in the
// window, by creation or last edit, fails it; so does none from a trusted
// person (an automatic review, or a request answered earlier), or an
// unreadable review time.
//
// With no `@codex` comment the review is automatic, asked for by whoever
// triggered it: the PR's author on opening, or the actor of a ready-for-review
// event (`triggers`, readTriggers). Which one cannot be told apart, so every
// such event in the window must be a trusted person's or the lanes App's
// (`appId`, APP_SENDER_ID); one by anyone else, github-actions[bot] included,
// fails it. An event with no readable time is not counted, and unreadable
// triggers (null) fail the check. Our own bots (the lanes App and
// github-actions[bot], whose review lanes edit their marker in place) are
// exempt from the edited and deleted comment rules, never trusted by them.
export function codexRequest({ authorId, submittedAt, reviews, mentions, triggers = null, reviewerIds = [], trustedHumans = new Set(), appId }) {
  const ourBot = (id) => id === appId || id === MARKER_AUTHOR_ID;
  const at = Date.parse(submittedAt ?? "");
  // Unreadable triggers (readTriggers' null) leave edits and deletions unseen.
  if (Number.isNaN(at) || triggers === null) {
    return { reason: "codex-request-not-found" };
  }
  const since = Math.max(...reviews.filter((review) => review.authorId === authorId).map((review) => Date.parse(review.submittedAt ?? "")).filter((time) => time < at));
  const within = (time) => time > since && time <= at;
  const untrusted = (requester, via) => ({ reason: "codex-request-untrusted", requester, via });
  let trusted = false;
  for (const mention of mentions) {
    if (reviewerIds.includes(mention.authorId)) {
      continue;
    }
    const body = String(mention.body ?? "");
    const created = Date.parse(mention.createdAt ?? "");
    // A review body's edit time comes from GraphQL (readTriggers' reviewEdits).
    const edited = Date.parse((mention.reviewId === undefined ? mention.editedAt : triggers.reviewEdits?.[mention.reviewId]) ?? "");
    if (trustedHumans.has(mention.authorId)) {
      trusted ||= CODEX_MENTION.test(body) && within(created);
    } else if (ANY_CODEX_MENTION.test(body) && (Number.isNaN(created) || within(created) || within(edited))) {
      return untrusted(mention.authorId, "@codex request");
    } else if (!ourBot(mention.authorId) && created <= at && edited > created && edited > since) {
      // Edited since the window opened: it may have held a request then.
      return untrusted(mention.authorId, "edited comment");
    }
  }
  for (const deletion of triggers.deletions ?? []) {
    const id = deletion.authorId;
    if (!(Date.parse(deletion.at ?? "") <= since) && !trustedHumans.has(id) && !ourBot(id) && !reviewerIds.includes(id)) {
      return untrusted(id, "deleted comment");
    }
  }
  const events = [{ via: "opening of the pull request", ...triggers.opened }, ...triggers.ready.map((event) => ({ via: "ready-for-review event", ...event }))];
  for (const event of events) {
    if (!within(Date.parse(event.at ?? ""))) {
      continue;
    }
    if (!trustedHumans.has(event.actorId) && event.actorId !== appId) {
      return { reason: "codex-request-untrusted", requester: event.actorId, via: event.via };
    }
    trusted = true;
  }
  return trusted ? null : { reason: "codex-request-not-found" };
}

// The PR history codexRequest reads besides its comments: the events that
// start an automatic review (the PR's opening, by its author, and each
// ready-for-review event of its REST issue timeline), and from
// REQUEST_HISTORY_QUERY each deleted comment's author and time and each
// review's last edit time. `pull` is the REST pull request when the caller
// already read it. A failed read is null, which codexRequest fails closed on.
export async function readTriggers({ api, pr, pull }) {
  try {
    const [read, timeline, history] = await Promise.all([pull ?? api.getPull(pr), api.listTimeline(pr), api.listRequestHistory(pr)]);
    return {
      opened: { actorId: read?.user?.id, at: read?.created_at },
      ready: timeline.filter((event) => event?.event === "ready_for_review").map((event) => ({ actorId: event.actor?.id, at: event.created_at })),
      deletions: history.deletions,
      reviewEdits: history.reviewEdits,
    };
  } catch {
    return null;
  }
}

// The deleted comments (CommentDeletedEvent: who wrote each, when it went)
// and each review's last edit time, which REST does not give. More than one
// page of either throws, so codexRequest fails closed.
export const REQUEST_HISTORY_QUERY = `query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      timelineItems(itemTypes: [COMMENT_DELETED_EVENT], first: 100) {
        pageInfo { hasNextPage }
        nodes { ... on CommentDeletedEvent { createdAt deletedCommentAuthor { ... on User { databaseId } ... on Bot { databaseId } } } }
      }
      reviews(first: 100) { pageInfo { hasNextPage } nodes { databaseId lastEditedAt } }
    }
  }
}`;
export function requestHistoryOf(data) {
  const pull = data?.repository?.pullRequest;
  if (!pull || pull.timelineItems.pageInfo.hasNextPage || pull.reviews.pageInfo.hasNextPage) {
    throw new Error("the pull request's comment deletions or reviews run past one page");
  }
  return {
    deletions: pull.timelineItems.nodes.map((node) => ({ authorId: node.deletedCommentAuthor?.databaseId, at: node.createdAt })),
    reviewEdits: Object.fromEntries(pull.reviews.nodes.filter((node) => node.lastEditedAt).map((node) => [node.databaseId, node.lastEditedAt])),
  };
}

// Whether any of `authorIds` is a listed bot's, so readTriggers is worth a read.
export const anyListed = (authorIds, reviewerIds = []) => reviewerIds.length > 0 && authorIds.some((id) => reviewerIds.includes(id));

// Why a thread threadAuthors accepted (`authors`) is not worked for want of a
// trusted `@codex` request (codexRequest), or null. Only a thread no trusted
// person directed is checked, at each listed bot's comment (`comments`, each
// { authorId, review: { authorId, submittedAt } }). The select step and the
// reply job (keepThreads) and the dispatcher (feedback-dispatch.mjs) all ask.
export function requestSkip({ authors, comments, reviews, mentions, triggers = null, reviewerIds = [], trustedHumans, appId }) {
  if (authors.some((author) => author.direction === true)) {
    return null;
  }
  for (const comment of comments) {
    if (reviewerIds.includes(comment.authorId)) {
      const submittedAt = comment.review?.authorId === comment.authorId ? comment.review.submittedAt : undefined;
      const skip = codexRequest({ authorId: comment.authorId, submittedAt, reviews, mentions, triggers, reviewerIds, trustedHumans, appId });
      if (skip) {
        return skip;
      }
    }
  }
  return null;
}

// The log line for a requestSkip answer: ids and a fixed reason, never a body.
export const requestSkipLine = (id, skip) =>
  `skip thread ${id}: ${skip.reason} (${
    skip.reason === "codex-request-untrusted"
      ? `the ${skip.via} behind the bot's review came from account ${skip.requester}, not on the trusted-actor list`
      : "no trusted @codex request, and no readable opening or ready-for-review event, since the bot's previous review"
  })`;

// The `@codex` request candidates of a PR's REST rows, for codexRequest.
export const restMentions = ({ issueComments = [], reviewComments = [], reviews = [] }) => [
  ...[...issueComments, ...reviewComments].map((row) => ({ authorId: row.user?.id, createdAt: row.created_at, editedAt: row.updated_at, body: row.body })),
  ...reviews.map((review) => ({ authorId: review.user?.id, createdAt: review.submitted_at, reviewId: review.id, body: review.body })),
];

// Whether a thread threadAuthors accepted (`authors`) sits on a review its
// finder submitted on a marker-confirmed head: the reviewer bot's, a listed review bot's,
// github-actions[bot]'s for a verifier note or a lane comment, or the trusted
// person's who opened it (always directed, so any head). A trusted
// person's direction (a fix request, or a reply to the lane's escalation)
// asks for the thread, so its review may be on an earlier head. `review` is
// { user: { id }, commit_id }. keepThreads and the dispatcher
// (feedback-dispatch.mjs hasWorkableThread) both judge a thread with this.
export function onReviewedHead({ authors, firstAuthorId, review, heads }) {
  const directed = authors.some((a) => a.direction === true);
  // threadAuthors accepted the root's author (the reviewer bot, a listed
  // review bot, or github-actions[bot] for a verifier note or a lane comment),
  // so its own review vouches for it.
  return firstAuthorId !== undefined && review?.user?.id === firstAuthorId && (directed || heads.has(review.commit_id));
}

// A thread is kept when it is unresolved, its first comment belongs to a
// review its own author (the reviewer bot, a listed review bot,
// github-actions[bot] for a lane comment or a verifier note, or the trusted
// person who opened it) submitted on a
// marker-confirmed head (any head for a thread carrying
// a trusted person's direction), and threadAuthors accepts its comments.
// A thread with more comments than one page reads is left alone. A listed
// review bot's comment is tagged `listed`, from its account id alone. A
// thread requestSkip refuses (no trusted `@codex` request behind a listed
// bot's review, read from `issueComments`, the review comments and the
// reviews) is left alone, its reason logged.
export function keepThreads({ threads, reviewComments, reviews, heads, security = { reviewed: new Set(), holds: [] }, reviewerId, reviewerIds = [], appId, trustedHumans = new Set(), requesters = null, fixers = requesters ?? new Set(), issueComments = [], triggers = null, log = () => {} }) {
  const comments = new Map(reviewComments.map((comment) => [comment.id, comment]));
  const reviewsById = new Map(reviews.map((review) => [review.id, review]));
  const mentions = restMentions({ issueComments, reviewComments, reviews });
  const reviewTimes = reviews.map((review) => ({ authorId: review.user?.id, submittedAt: review.submitted_at }));
  const kept = [];
  for (const thread of threads) {
    if (thread.isResolved || thread.comments.totalCount > THREAD_COMMENT_CAP) {
      continue;
    }
    const nodes = thread.comments.nodes;
    const rows = nodes.map((node) => comments.get(node.databaseId));
    if (rows.length === 0 || rows.some((row) => row === undefined)) {
      continue;
    }
    const authors = threadAuthors(
      rows.map((row, i) => ({
        authorId: row.user?.id,
        createdAt: row.created_at,
        body: row.body,
        lastEditedAt: nodes[i].lastEditedAt,
        editorId: nodes[i].editor?.databaseId,
      })),
      { reviewerId, reviewerIds, appId, trustedHumans, requesters, fixers },
    );
    if (authors === null) {
      continue;
    }
    const review = reviewsById.get(rows[0].pull_request_review_id);
    if (!onReviewedHead({ authors, firstAuthorId: rows[0].user?.id, review, heads })) {
      continue;
    }
    const skip = requestSkip({
      authors,
      comments: rows.map((row) => {
        const own = reviewsById.get(row.pull_request_review_id);
        return { authorId: row.user?.id, review: own && { authorId: own.user?.id, submittedAt: own.submitted_at } };
      }),
      reviews: reviewTimes,
      mentions,
      triggers,
      reviewerIds,
      trustedHumans,
      appId,
    });
    if (skip) {
      log(requestSkipLine(thread.id, skip));
      continue;
    }
    kept.push({
      id: thread.id,
      path: rows[0].path,
      line: rows[0].line ?? rows[0].original_line ?? null,
      review_commit: review.commit_id,
      // Newer changes moved the thread's code, so its line may be stale.
      is_outdated: thread.isOutdated === true,
      root_comment_id: rows[0].id,
      // A lane only from the github-actions[bot] author whose footer the
      // review lanes write; claude[bot] writes its own body.
      comments: rows.map((row, i) => {
        const lane = isLaneComment({ authorId: row.user?.id, body: row.body }) ? laneOf(row.body) : null;
        const listed = authors[i].author === "reviewer" && reviewerIds.includes(row.user?.id);
        // A listed bot's root carries the security-review lane's state for
        // it (securityState): the lane's rating, not the bot's badge, decides.
        const state = listed && i === 0 ? { security: securityState(security, review) } : {};
        return { id: row.id, ...authors[i], ...(lane ? { lane } : {}), ...(listed ? { listed } : {}), ...state, body: row.body ?? "" };
      }),
    });
  }
  return kept;
}

// Whether this head's address-feedback stop sits in the session-builder
// queue: the lanes App's lane-stopped comment for the activity (one, edited in
// place, report-escalation.sh) names `headSha` and a reason whose
// escalation-routes.json entry names a `label` the PR carries (needs-session).
const LANE_STOPPED = `<!-- pr-unblock:lane-stopped activity=${ACTIVITY} -->`;
export function sessionQueued({ labels = [], issueComments, headSha, isLanesApp }) {
  const names = new Set(labels.map((label) => label.name));
  return issueComments.some((comment) => {
    const body = String(comment.body ?? "").replaceAll("\r\n", "\n");
    if (!isLanesApp(comment.user) || firstLine(body) !== LANE_STOPPED) {
      return false;
    }
    const reason = /^- Reason: `([^`]*)`$/m.exec(body)?.[1] ?? "";
    const label = Object.hasOwn(ROUTES, reason) ? ROUTES[reason].label : undefined;
    return /^- Head: `([0-9a-f]{40})`$/m.exec(body)?.[1] === headSha && typeof label === "string" && names.has(label);
  });
}

export async function select({
  api,
  pr,
  headSha,
  repository,
  appId,
  reviewerId,
  reviewerIds = [],
  trustedHumans,
  humanGatedLabel = "needs-human",
  maxRounds = DEFAULT_MAX_ROUNDS,
  adoption = NO_ADOPTION,
  ci = async () => undefined,
  log = () => {},
}) {
  const [pull, files, issueComments, reviews, reviewComments, threads] = await Promise.all([
    api.getPull(pr),
    api.listPullFiles(pr),
    api.listIssueComments(pr),
    api.listReviews(pr),
    api.listReviewComments(pr),
    api.listThreads(pr),
  ]);
  // An owner PR whose body gained a `Hold:` line after dispatch is held, as
  // feedback-dispatch.mjs ownerSkip holds it at dispatch.
  const owner = ownerAuthored(pull, adoption);
  if (owner && HOLD_LINE.test(String(pull.body ?? ""))) {
    return { decision: "skip", skipReason: "awaiting-human", threads: [] };
  }
  // The human-gated label holds the PR except for threads a trusted person
  // with write access asked the lane to fix, unless a lane escalation put it
  // on and no review lane holds the PR (gate-source.mjs). On an owner PR the
  // lane escalation lets the round work only as it lets fix-ci work there
  // (prHold): not after address-feedback's own escalation, nor once a person
  // spoke after the label went on. The label stays on.
  const labeled = (pull.labels ?? []).some((label) => label.name === humanGatedLabel);
  const timeline = async () => [...commentItems(issueComments), ...(await api.listLabelEvents(pr))];
  const isLanesApp = (user) => user?.id === appId && user?.type === "Bot";
  const gated =
    labeled &&
    (owner
      ? (
          await prHold({
            labels: pull.labels.map((label) => label.name),
            holdLabels: [],
            gateLabel: humanGatedLabel,
            head: headSha,
            activity: ACTIVITY,
            appId,
            readTimeline: timeline,
            readReviews: async () => ({ comments: reviewComments, reviews }),
          })
        ).held
      : gateSource({ timeline: await timeline(), label: humanGatedLabel, head: headSha, isLanesApp }).source !== "lane-escalation");
  const fixers = await reviewFixers({ reviewComments, trustedHumans, permission: api.getPermission });
  const heads = reviewedHeads(issueComments);
  const kept = keepThreads({
    threads,
    reviewComments,
    reviews,
    heads,
    security: securitySignals(issueComments),
    reviewerId,
    reviewerIds,
    appId,
    trustedHumans,
    requesters: gated ? fixers : null,
    fixers,
    issueComments,
    triggers: anyListed(reviewComments.map((row) => row.user?.id), reviewerIds) ? await readTriggers({ api, pr, pull }) : null,
    log,
  });
  // An unresolved thread the lane does not take (a reviewer it does not
  // trust, a review on an older head, a reply it already gave) would block
  // the merge with no stop on record, so it ends in a failing status. A
  // pr-verify FAIL's note from an older head is not one: a pass at this head
  // resolves it (the pass-only round in main), and a failing status here
  // would fail ci-status, which pr-verify waits on, so no pass could come.
  // The note still holds the merge, which needs every thread resolved.
  // With no hold and no other unresolved thread left, every thread stop is
  // gone on this head: `resolved` lets report-stop-status clear its status.
  if (kept.length === 0) {
    if (gated) {
      return { decision: "skip", skipReason: "awaiting-human", threads: kept };
    }
    const stale = new Set(staleVerifyNotes(threads, headSha));
    const untaken = threads.some((thread) => thread.isResolved === false && !stale.has(thread.id));
    // On an adopted owner PR (ownerAuthored), a thread the lane does not take
    // is the owner's (one they wrote, answered, or a lane answer the lanes App
    // cannot resolve there), and so no stop: it still holds the merge until it
    // is resolved. Any other person's PR still escalates.
    if (untaken && owner) {
      return { decision: "skip", skipReason: "not-applicable", threads: kept };
    }
    // A stop already queued for a session builder on this head stands down:
    // escalating again would only re-post it. A new head escalates afresh.
    if (untaken && sessionQueued({ labels: pull.labels, issueComments, headSha, isLanesApp })) {
      return { decision: "skip", skipReason: "awaiting-session", threads: kept };
    }
    return untaken
      ? { decision: "escalate", escalationReason: "feedback-untaken-threads", threads: kept }
      : { decision: "skip", skipReason: "stop-resolved", resolved: true, threads: kept };
  }
  // The files listing stops at FILES_CAP, so a longer diff could hide a
  // .github/workflows/ path and is treated as touching one.
  if (
    files.length >= FILES_CAP ||
    files.some((file) => isProtectedPath(file.filename) || isProtectedPath(file.previous_filename ?? ""))
  ) {
    return { decision: "escalate", escalationReason: "feedback-protected-path", threads: kept };
  }
  const commits = await api.listPullCommits(pr);
  const checkRuns = await Promise.all(commits.map((commit) => api.listCheckRuns(commit.sha, MODEL_CHECK)));
  const rounds = Math.max(countRounds(issueComments, appId), countCheckRounds(checkRuns));
  // The most automatic rounds a PR gets: the cap and the fresh fixer's round.
  const bound = maxRounds + FRESH_FIXER_ROUNDS;
  let worked = kept;
  let retry;
  if (rounds >= maxRounds) {
    // Past the cap, a trusted person with write access who asked for a fix
    // after the newest round grants one more round, for the threads they
    // asked about only.
    const since = lastRoundAt(issueComments, appId, checkRuns);
    const rows = new Map(reviewComments.map((row) => [row.id, row]));
    worked = kept.filter((thread) =>
      thread.comments.some((comment) => {
        const row = rows.get(comment.id);
        return (
          comment.author === "trusted-human" &&
          fixers.has(row.user?.id) &&
          isFixRequest(comment.body) &&
          Date.parse(row.created_at ?? "") > since
        );
      }),
    );
    if (worked.length === 0) {
      // Otherwise a PR a person gated goes to a person: only a fresh fix
      // request lifts their hold. So does a thread only a person decides
      // (needsPerson). Every other finding, a security finding rated below
      // CRITICAL included, goes to a fresh fixer: one more round with
      // FRESH_ROUND_BRIEF, a new session like every round, reading only the
      // thread file and the PR head. Once that round has run, no automatic
      // round ever runs again: the head fails, feedback-verifier-open when
      // only verifier notes are left, feedback-not-converging otherwise.
      const rootOf = (thread) => rows.get(thread.root_comment_id);
      const spent = rounds >= bound;
      const holds = (thread) => needsPerson(thread, rootOf(thread)?.user?.id);
      if (gated || kept.some(holds)) {
        return { decision: "escalate", escalationReason: "feedback-round-cap", rounds, maxRounds: bound, threads: kept };
      }
      if (spent) {
        const escalationReason = kept.every(isVerifierNote) ? "feedback-verifier-open" : "feedback-not-converging";
        return { decision: "escalate", escalationReason, rounds, maxRounds: bound, threads: kept };
      }
      worked = kept;
      retry = { brief: FRESH_ROUND_BRIEF };
    }
  }
  for (const thread of worked) {
    const named = await namedPaths({ thread, reviewComments, fixers, headSha, listTree: api.listTree });
    if (named.length > 0) {
      thread.named_paths = named;
    }
  }
  return {
    decision: "proceed",
    // A retry after the reply job stopped on this head runs one rung up.
    modelRung: retryRung(await api.listCheckRuns(headSha, REPLY_CHECK)),
    rounds,
    maxRounds: bound,
    // The gate the round works past on a PR carrying the human-gated label,
    // which the write runner's holds read: fix-request when every kept thread
    // carries a write-access fix request, lane-escalation when a lane
    // escalation that lets this activity work put the label on.
    humanGate: labeled ? (gated ? "fix-request" : "lane-escalation") : "",
    threads: worked,
    file: { version: 1, repository, pr, head_sha: headSha, pr_paths: prPathsOf(files), threads: worked, ...(retry ? { retry } : {}) },
    reviewedHeads: [...heads].sort(),
    ci: await ci({ headSha, files }),
  };
}

// run.json, as its bytes: the gated head, the kept threads with the comment
// ids the model is shown, and the reviewed heads they were kept on, a pure
// function of the thread file and those heads. publish-feedback.mjs checks the
// model's replies against it and re-reads the threads against those heads: a
// review lane edits its one marker in place, so after the fix push it may name
// only the fix head. `ci` is ciSnapshot's, when the select job took one.
export function runRecord(file, reviewedHeads, ci) {
  const run = {
    version: 1,
    head_sha: file.head_sha,
    pr_paths: file.pr_paths,
    threads: file.threads.map((t) => ({
      id: t.id,
      path: t.path,
      comment_ids: t.comments.map((c) => c.id),
      ...(t.named_paths ? { named_paths: t.named_paths } : {}),
    })),
    ...(file.stale_notes ? { stale_notes: file.stale_notes } : {}),
    ...(reviewedHeads ? { reviewed_heads: reviewedHeads } : {}),
    ...(ci ? { ci } : {}),
  };
  return `${JSON.stringify(run)}\n`;
}

// The kept threads of a PR as they are now: the reply job's re-read, judged
// against `heads` (the select job's reviewed heads) when given, else the
// markers as they are now.
export async function currentThreads({ api, pr, reviewerId, reviewerIds = [], appId, trustedHumans, heads, log = () => {} }) {
  const [issueComments, reviews, reviewComments, threads] = await Promise.all([
    api.listIssueComments(pr),
    api.listReviews(pr),
    api.listReviewComments(pr),
    api.listThreads(pr),
  ]);
  const fixers = await reviewFixers({ reviewComments, trustedHumans, permission: api.getPermission });
  const triggers = anyListed(reviewComments.map((row) => row.user?.id), reviewerIds) ? await readTriggers({ api, pr }) : null;
  return {
    issueComments,
    reviewComments,
    kept: keepThreads({ threads, reviewComments, reviews, heads: heads ?? reviewedHeads(issueComments), security: securitySignals(issueComments), reviewerId, reviewerIds, appId, trustedHumans, fixers, issueComments, triggers, log }),
  };
}

const THREAD_QUERY = `query($id: ID!) {
  node(id: $id) {
    ... on PullRequestReviewThread {
      isResolved pullRequest { number } comments(first: 100) { totalCount nodes { databaseId } }
    }
  }
}`;

const TREE_QUERY = `query($owner: String!, $name: String!, $expression: String!) {
  repository(owner: $owner, name: $name) {
    object(expression: $expression) { ... on Tree { entries { name type mode } } }
  }
}`;

const QUEUE_ENTRY_QUERY = `query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) { pullRequest(number: $pr) { id mergeQueueEntry { id } } }
}`;
const RESOLVE_MUTATION = `mutation($id: ID!) {
  resolveReviewThread(input: { threadId: $id }) { thread { isResolved } }
}`;

const THREADS_QUERY = `query($owner: String!, $name: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          id isResolved isOutdated
          comments(first: 100) {
            totalCount
            nodes { databaseId lastEditedAt editor { ... on User { databaseId } ... on Bot { databaseId } } }
          }
          root: comments(first: 1) {
            nodes { author { ... on User { databaseId } ... on Bot { databaseId } } body originalCommit { oid } }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

// The fetch a main run from the full base checkout hands createGitHubApi: each
// attempt's rate-limit reading goes to the job-end api-calls notice
// (rate-guard.mjs countRequests), and nothing else changes. It loads here, at
// run time: publish-feedback.mjs and apply-dependency-verdict.mjs import this
// module from a copy of this directory alone, which cannot reach .github/actions.
export const countedFetch = async (fetchImpl = globalThis.fetch) =>
  (await import("../../actions/log-api-budget/rate-guard.mjs")).countRequests(fetchImpl);

// A read, GraphQL queries included, and a write marked safeToResend, is sent
// again after a network error or a 5xx (retry-fetch.mjs). Closing a closed
// pull request changes nothing; a blob, a tree and a commit are used only by
// the sha their answer names, and a ref update carries the sha it sets. A
// comment, an issue and a mutation are sent once.
export function createGitHubApi({ token, repository, apiUrl, graphqlUrl, fetch: rawFetch = globalThis.fetch, sleep }) {
  const fetch = retryFetch(rawFetch, { sleep });
  const [owner, name] = repository.split("/");
  const headers = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
  };
  async function request(url, method = "GET", body, safeToResend = false) {
    const response = await fetch(url, {
      method,
      safeToResend,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw Object.assign(new Error(`${method} ${url} returned ${response.status}`), { status: response.status });
    }
    return { data: await response.json(), link: response.headers.get("link") ?? "" };
  }
  async function paginate(path) {
    const rows = [];
    let url = `${apiUrl}/repos/${owner}/${name}/${path}${path.includes("?") ? "&" : "?"}per_page=100`;
    while (url) {
      const { data, link } = await request(url);
      rows.push(...data);
      url = /<([^>]+)>;\s*rel="next"/.exec(link)?.[1] ?? "";
    }
    return rows;
  }
  async function graphql(query, variables) {
    const { data } = await request(graphqlUrl, "POST", { query, variables });
    if (data.errors?.length) {
      throw new Error(`GraphQL: ${data.errors.map((error) => error.message).join("; ")}`);
    }
    return data.data;
  }
  const repo = `${apiUrl}/repos/${owner}/${name}`;
  return {
    getPull: async (pr) => (await request(`${repo}/pulls/${pr}`)).data,
    // A GraphQL answer whole, errors kept for the caller to judge
    // (fix-ci-context.mjs, for pr-verify's linkedIssues).
    graphqlAnswer: async (body) => (await request(graphqlUrl, "POST", body)).data,
    listLabelEvents: (pr) => listLabelEvents({ graphql, repository, number: pr }),
    // Metadata read, which every token holds. A 404 (not a collaborator) is none.
    async getPermission(login) {
      const url = `${repo}/collaborators/${encodeURIComponent(login)}/permission`;
      const response = await fetch(url, { headers });
      if (response.status === 404) {
        return "none";
      }
      if (!response.ok) {
        throw new Error(`GET ${url} returned ${response.status}`);
      }
      return (await response.json()).permission;
    },
    closePull: async (pr) => (await request(`${repo}/pulls/${pr}`, "PATCH", { state: "closed" }, true)).data,
    createIssue: async (fields) => (await request(`${repo}/issues`, "POST", fields)).data,
    listIssues: (query) => paginate(`issues?${query}`),
    listPullFiles: (pr) => paginate(`pulls/${pr}/files`),
    listIssueComments: (pr) => paginate(`issues/${pr}/comments`),
    // The REST issue timeline, as gate-source.mjs prHold reads it.
    listTimeline: (pr) => paginate(`issues/${pr}/timeline`),
    listReviews: (pr) => paginate(`pulls/${pr}/reviews`),
    // Written or edited since `since` (GitHub's since query value) when given.
    listReviewComments: (pr, since) => paginate(`pulls/${pr}/comments${since === undefined ? "" : `?since=${encodeURIComponent(since)}`}`),
    listPullCommits: (pr) => paginate(`pulls/${pr}/commits`),
    // A commit's statuses, newest first (fix-ci-context.mjs weakenStopped).
    listCommitStatuses: (sha) => paginate(`commits/${sha}/statuses`),
    // A branch's repository activity, newest first, read by cursor to its end
    // (contents read): merge-holds.mjs branchActivity, loaded at run time from
    // ../pr-merge, where collect-base-activity stages it beside a script copy.
    async listActivity(branch) {
      const { branchActivity, LINK } = await import("../pr-merge/merge-holds.mjs");
      const read = async (method, path) => {
        const { data, link } = await request(`${apiUrl}${path}`, method);
        return Array.isArray(data) ? Object.defineProperty(data, LINK, { value: link }) : data;
      };
      return branchActivity(read, `${owner}/${name}`, branch);
    },
    async listCheckRuns(sha, name) {
      const url = `${repo}/commits/${sha}/check-runs?check_name=${encodeURIComponent(name)}&filter=all&per_page=100`;
      return (await request(url)).data.check_runs ?? [];
    },
    // Every check run on a commit, re-runs and a contract-only run's skips
    // included (failingChecks prefers a real result over a skip), up to 300
    // (fix-ci-context.mjs).
    async listCommitCheckRuns(sha) {
      const runs = [];
      let total = Infinity;
      for (let page = 1; page <= 3; page += 1) {
        const { data } = await request(`${repo}/commits/${sha}/check-runs?filter=all&per_page=100&page=${page}`);
        runs.push(...(data.check_runs ?? []));
        total = data.total_count ?? Infinity;
        if ((data.check_runs ?? []).length < 100) {
          break;
        }
      }
      // complete: the listing holds every check run, not the first 300.
      return Object.assign(runs, { complete: runs.length >= total });
    },
    listAnnotations: async (id) => (await request(`${repo}/check-runs/${id}/annotations?per_page=50`)).data,
    getJob: async (id) => (await request(`${repo}/actions/jobs/${id}`)).data,
    // The job log redirects to a short-lived download URL; fetch follows it.
    async getJobLog(id) {
      const response = await fetch(`${repo}/actions/jobs/${id}/logs`, { headers });
      if (!response.ok) {
        throw Object.assign(new Error(`GET job ${id} logs returned ${response.status}`), { status: response.status });
      }
      return response.text();
    },
    async getCommit(sha) {
      return (await request(`${repo}/commits/${sha}`)).data;
    },
    // A file's text at `ref` through the raw media type, which serves files
    // over 1 MB (docs.github.com/en/rest/repos/contents#get-repository-content,
    // as of 2026-10-21; recheck when that section changes its size limits);
    // null when the path is absent.
    async getText(path, ref) {
      const url = `${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${encodeURIComponent(ref)}`;
      const response = await fetch(url, { headers: { ...headers, Accept: "application/vnd.github.raw+json" } });
      if (response.status === 404) {
        return null;
      }
      if (!response.ok) {
        throw new Error(`GET ${url} returned ${response.status}`);
      }
      return response.text();
    },
    async listThreads(pr) {
      const nodes = [];
      let after = null;
      for (;;) {
        const page = (await graphql(THREADS_QUERY, { owner, name, pr, after })).repository.pullRequest.reviewThreads;
        nodes.push(...page.nodes);
        if (!page.pageInfo.hasNextPage) {
          return nodes;
        }
        after = page.pageInfo.endCursor;
      }
    },
    listRequestHistory: async (pr) => requestHistoryOf(await graphql(REQUEST_HISTORY_QUERY, { owner, name, pr })),
    // The entries of the tree at `${sha}:${dir}`, none when it is no tree.
    async listTree(sha, dir) {
      const object = (await graphql(TREE_QUERY, { owner, name, expression: `${sha}:${dir}` })).repository.object;
      return object?.entries ?? [];
    },
    async readThread(id) {
      const node = (await graphql(THREAD_QUERY, { id })).node;
      return {
        isResolved: node?.isResolved,
        pr: node?.pullRequest?.number,
        commentCount: node?.comments?.totalCount,
        commentIds: (node?.comments?.nodes ?? []).map((comment) => comment.databaseId),
      };
    },
    // From git/ref, which GET /pulls can lag behind after a push.
    async readBranch(ref) {
      return (await request(`${repo}/git/ref/heads/${ref.split("/").map(encodeURIComponent).join("/")}`)).data.object.sha;
    },
    async compare(base, head) {
      return (await request(`${repo}/compare/${base}...${head}`)).data;
    },
    async getRun(id) {
      return (await request(`${repo}/actions/runs/${id}`)).data;
    },
    async createReviewComment(pr, fields) {
      return (await request(`${repo}/pulls/${pr}/comments`, "POST", fields)).data;
    },
    async replyToComment(pr, commentId, body) {
      return (await request(`${repo}/pulls/${pr}/comments/${commentId}/replies`, "POST", { body })).data;
    },
    async resolveThread(id) {
      return (await graphql(RESOLVE_MUTATION, { id })).resolveReviewThread.thread.isResolved;
    },
    // The pull request's node id, and whether it sits in the merge queue.
    async readQueueEntry(pr) {
      const pull = (await graphql(QUEUE_ENTRY_QUERY, { owner, name, pr })).repository.pullRequest;
      return { id: pull.id, queued: pull.mergeQueueEntry !== null };
    },
    async dequeuePull(id) {
      await graphql("mutation($id: ID!) { dequeuePullRequest(input: { id: $id }) { clientMutationId } }", { id });
    },
    async createIssueComment(pr, body) {
      await request(`${repo}/issues/${pr}/comments`, "POST", { body });
    },
    async updateIssueComment(id, body) {
      await request(`${repo}/issues/comments/${id}`, "PATCH", { body }, true);
    },
    async addLabels(pr, labels) {
      await request(`${repo}/issues/${pr}/labels`, "POST", { labels }, true);
    },
    async removeLabel(pr, label) {
      await request(`${repo}/issues/${pr}/labels/${encodeURIComponent(label)}`, "DELETE");
    },
    // One page: a pull request with more labels than one page holds is refused.
    async listLabels(pr) {
      const { data, link } = await request(`${repo}/issues/${pr}/labels?per_page=100`);
      if (/rel="next"/.test(link)) {
        throw new Error("the pull request has more labels than one page holds");
      }
      return data;
    },
    // The Git Data API: GitHub signs a commit made with no author or
    // committer as the App.
    createBlob: async (content) => (await request(`${repo}/git/blobs`, "POST", { content, encoding: "base64" }, true)).data.sha,
    createTree: async (baseTree, tree) => (await request(`${repo}/git/trees`, "POST", { base_tree: baseTree, tree }, true)).data.sha,
    createCommit: async (message, tree, parents) => (await request(`${repo}/git/commits`, "POST", { message, tree, parents }, true)).data.sha,
    async updateRef(ref, sha, force) {
      await request(`${repo}/git/refs/${ref.split("/").map(encodeURIComponent).join("/")}`, "PATCH", { sha, force }, true);
    },
  };
}

const MARKER_FILE = /^scan-refused-[1-9][0-9]{0,4}(-rung-up)?\.txt$/;

// The model call's scan refusal for a reply or verdict script: '' none,
// `patch` an oversize patch, `output` any other. It comes from the markers the
// read runner's scan-refusal job uploads, never from a job output: a failed
// job's outputs are not documented to reach a workflow_call caller. `dir` is
// where the write runner downloaded every attempt's marker for the model
// call's activity (SCAN_REFUSED_DIR), `read` that download's outcome
// (SCAN_REFUSED_READ). A download that failed cannot rule a refusal out, so
// it reads `output`; the markers read `patch` only when every one names it,
// so a mixed set fails closed to `output`. A forged marker only hands the
// round to a person.
export function scanRefusal({ dir = "", read = "" } = {}) {
  if (read === "failure") {
    return "output";
  }
  if (dir === "") {
    return "";
  }
  let names;
  try {
    names = readdirSync(dir);
  } catch (error) {
    if (error.code === "ENOENT") {
      return "";
    }
    throw error;
  }
  const kinds = names
    .filter((name) => MARKER_FILE.test(name) && lstatSync(join(dir, name)).isFile())
    .map((name) => readFileSync(join(dir, name), "utf8").trim());
  if (kinds.length === 0) {
    return "";
  }
  return kinds.every((kind) => kind === "patch") ? "patch" : "output";
}

export function need(env, keys) {
  for (const key of keys) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
}

export function positive(value, name) {
  if (!/^[1-9][0-9]{0,14}$/.test(String(value))) {
    throw new Error(`${name} is not a positive integer`);
  }
  return Number(value);
}

export function maxRoundsFrom(value) {
  return value === undefined || value === "" ? DEFAULT_MAX_ROUNDS : positive(value, "REVIEW_ROUNDS");
}

const readActors = (path) => JSON.parse(readFileSync(path, "utf8")).actors ?? [];

// The ids of the people on the base's trusted-actors list.
export function trustedHumansFrom(trustedActorsPath) {
  return new Set(
    readActors(trustedActorsPath)
      .filter((row) => row.kind === "human")
      .map((row) => positive(row.id, `a human id in ${trustedActorsPath}`)),
  );
}

// No owner is adopted unless the base config's `adoption` section sets
// idle-hours (pr-pipeline.yaml).
export const NO_ADOPTION = Object.freeze({ ownerIds: Object.freeze(new Set()), idleHours: undefined });

// An owner PR: one a person on the base's trusted-actors list opened (by id,
// kind human), under an `adoption` section. Its rounds post as the lanes App
// like a lanes App PR's, so a lane answer is told apart from the person's.
export const ownerAuthored = (pull, adoption = NO_ADOPTION) =>
  adoption.idleHours !== undefined && pull.user?.type === "User" && adoption.ownerIds.has(pull.user?.id);

// A body line starting "Hold:", as babysit's BODY_MERGE_HOLD_RE reads it
// (babysit_merge.py): any case, after any non-newline whitespace, NBSP
// included, with a bare CR as a line break too. On an owner PR it holds the
// lane off: feedback-dispatch.mjs ownerSkip, select, fix-ci-dispatch.mjs.
export const HOLD_LINE = /(?:^|(?<=[\r\n]))[^\S\r\n]*hold:/i;

// The owners whose PRs a round serves: the base trusted-actors list's people,
// under the base config's `adoption` section. An unreadable section adopts no
// owner, and lanes App PRs proceed.
export async function ownerAdoption(env, log = () => {}) {
  try {
    const { adoptionFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
    const idleHours = adoptionFromBase({ BASE_PATH: env.BASE_PATH || ".base" })["idle-hours"];
    if (idleHours === undefined) {
      return NO_ADOPTION;
    }
    return { ownerIds: trustedHumansFrom(env.TRUSTED_ACTORS || `${env.BASE_PATH || ".base"}/.github/standards/trusted-actors/trusted-actors.json`), idleHours };
  } catch (error) {
    log(`::warning::cannot read the base adoption section or trusted-actors list (${error.message}); no owner PR is served this run`);
    return NO_ADOPTION;
  }
}

// The reviewer bot's id comes from the base's trusted-actors list, by login.
export function reviewerIdFrom(trustedActorsPath, login = "claude[bot]") {
  const actor = readActors(trustedActorsPath).find((row) => row.login === login && row.kind === "bot");
  return positive(actor?.id, `the ${login} id in ${trustedActorsPath}`);
}

// The listed review bots' ids, pr-pipeline.yaml review-threads.reviewer-ids
// as the workflow prints it, one per line; unset is none.
export function reviewerIdsFrom(text) {
  return String(text ?? "")
    .split(/\s+/)
    .filter(Boolean)
    .map((id) => positive(id, "an id in REVIEWER_IDS"));
}

export async function main(argv, env, { api, log = (line) => console.log(line) } = {}) {
  const command = argv[0];
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      fetch: await countedFetch(),
    });
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  const selectThreads = async () => {
    need(env, ["TRUSTED_ACTORS"]);
    return select({
      api: client,
      pr,
      headSha: env.HEAD_SHA,
      repository: env.GITHUB_REPOSITORY,
      appId,
      reviewerId: reviewerIdFrom(env.TRUSTED_ACTORS),
      reviewerIds: reviewerIdsFrom(env.REVIEWER_IDS),
      trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS),
      humanGatedLabel: humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/.work-item-tracker.json"),
      maxRounds: maxRoundsFrom(env.REVIEW_ROUNDS),
      adoption: await ownerAdoption(env, log),
      ci: ({ headSha, files }) => ciSnapshot({ api: client, headSha, files }),
      log,
    });
  };
  if (command === "select" && env.VERIFY_PASS_HEAD) {
    // A pass-only round (pr-feedback-dispatch.yml after a pr-verify pass):
    // only the stale fail-note threads, for the reply job to resolve; no
    // thread for a model, so the round's model jobs and its neutral checks
    // stay off. With nothing to resolve (as on a rerun after the notes were
    // resolved by hand), the full select runs for `stop-resolved` alone, so
    // report-stop-status can clear a stop an earlier attempt left; no
    // `proceed` or `resolve-only`, so no model or reply job starts.
    need(env, ["THREAD_FILE", "RUN_FILE"]);
    if (!SHA.test(env.VERIFY_PASS_HEAD)) {
      throw new Error("VERIFY_PASS_HEAD is not a commit id");
    }
    if (!env.DISPATCHER_RUN_ID) {
      throw new Error("only a dispatcher run sends a pr-verify pass head");
    }
    if (env.VERIFY_PASS_HEAD !== env.HEAD_SHA) {
      log(`skip: the PR head ${env.HEAD_SHA} is not ${env.VERIFY_PASS_HEAD}, which pr-verify passed`);
      return 0;
    }
    const stale = staleVerifyNotes(await client.listThreads(pr), env.HEAD_SHA);
    log(`pass-only: ${stale.length} open fail-note thread(s) from an earlier head`);
    if (stale.length > 0) {
      const file = { version: 1, repository: env.GITHUB_REPOSITORY, pr, head_sha: env.HEAD_SHA, pr_paths: [], threads: [], stale_notes: stale };
      writeFileSync(env.THREAD_FILE, `${JSON.stringify(file, null, 2)}\n`);
      writeFileSync(env.RUN_FILE, runRecord(file));
      output("resolve-only", "true");
    } else {
      output("stop-resolved", String((await selectThreads()).resolved === true));
    }
    return 0;
  }
  if (command === "select") {
    need(env, ["THREAD_FILE", "RUN_FILE"]);
    const result = await selectThreads();
    if (result.file) {
      writeFileSync(env.THREAD_FILE, `${JSON.stringify(result.file, null, 2)}\n`);
      writeFileSync(env.RUN_FILE, runRecord(result.file, result.reviewedHeads, result.ci));
    }
    output("proceed", String(result.decision === "proceed"));
    // The write runner drops the human-gated label from the hold list only
    // on fix-request (every kept thread carries a write-access fix request),
    // or on lane-escalation (a lane escalation put the label on) while it
    // reads that again right before its push.
    output("human-gate", result.humanGate ?? "");
    output("model-rung", result.modelRung ?? "");
    output("skip-reason", result.decision === "skip" ? result.skipReason : result.decision === "escalate" ? stopSkip(result.escalationReason) : "");
    output("escalation-reason", result.escalationReason ?? "");
    // The neutral checks' summary line when the PR stopped at the round cap.
    output("not-run-detail", result.decision === "escalate" && result.maxRounds ? roundLine(result.rounds, result.maxRounds) : "");
    output("stop-resolved", String(result.resolved === true));
    log(`${result.decision}: ${result.threads.length} kept thread(s), ${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`);
    return 0;
  }
  throw new Error("usage: address-feedback.mjs select");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::address-feedback failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
