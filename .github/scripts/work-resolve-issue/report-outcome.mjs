#!/usr/bin/env node
// report-outcome.mjs: the work-resolve-issue lane's report-outcome leaf. Reads
// what the resolve-issue run left and acts on the issue, with no model:
//
//   done      opens a ready PR from the run's branch: the body starts
//             `Closes #<issue>`, or `Refs: #<issue>` when the run reports
//             `"link": "refs"` (a recorded decision keeps the issue open),
//             which also holds the PR for a human, since the merge gate
//             reads the work class from a closing issue. The title is the
//             run's when it is Conventional Commits (else
//             `chore: work on #<issue>`), and the body carries
//             the hold line when a human must merge it. The PR gets no label:
//             the work class lives on the issue only, and the merge gate reads
//             it from the PR's closing issue. The body fills the PR body contract's
//             sections from the outcome's summary, changes, verification and
//             not_done. A done outcome whose not_done holds a required check
//             is stopped.
//   pushback  comments why, adds the human-gated label, removes agent-ready.
//   stopped   comments why, adds the human-gated label, and names the branch
//             that holds any partial work. A missing or invalid outcome file
//             is stopped.
//   limited   a run that wrote no readable outcome file and whose lane.json
//             carries class rate-limit (the run hit its credential's usage
//             limit before it could report): comments once with the
//             limited marker naming when the limit resets, keeps agent-ready
//             and adds no label, so work-unblock restarts it after the reset.
//   reused    the resolve-issue run skipped the model for a lane branch an
//             earlier run left with commits and no report (REUSE_BRANCH):
//             the earlier outcome counts only when this run's artifact names
//             that branch (a re-run attempt); with none readable, a held PR
//             with fixed text only opens from it, whatever the limit record.
//
// Run from the base copy. It reads only the outcome directory and the GitHub
// API, and never writes to a branch.
//
// `--find-prior` runs before the resolve-issue mint instead, with the job's
// read-only token, and writes the step outputs `proceed`, `skip-reason` and
// `reuse-branch` (see findPrior).
//
// Environment:
//   GH_TOKEN            token with pull-requests: write and issues: write
//                       (--find-prior: the job's read-only GITHUB_TOKEN)
//   GITHUB_REPOSITORY   owner/repo
//   ISSUE_NUMBER        the issue the lane worked
//   WORK_OUTCOME_DIR    holds work-outcome.json (written by the skill, so
//                       untrusted) and lane.json (written by the runner: the
//                       lane branch, and the run's limit `class` and `resets`)
//   REUSE_BRANCH        the lane branch --find-prior chose, or empty
//   TRACKER_CONFIG      base .work-item-tracker.json, for the human-gated label
//   RESOLVED_CONFIG     resolve-config's output for this run (default
//                       $RUNNER_TEMP/resolved-config.json), for the denied paths
//   LANES_BOT_LOGIN     the lanes App bot login, the only author of an open PR
//                       a rerun reuses (default melodic-automation-lanes[bot])
//   TRUSTED_ACTORS_PATH --find-prior: trusted-actors.json from the default
//                       branch tip, whose humans' closing PRs stop the lane
//   GITHUB_OUTPUT       --find-prior: the step output file
//   GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID
import { appendFileSync, readFileSync } from "node:fs";
import { join, posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

export const HOLD_LINE = "Hold: a human merges this";
const EXITS = new Set(["done", "pushback", "stopped"]);
// The subject allows no `#` or `/`, so the squash commit title cannot name an
// issue to close.
const CONVENTIONAL =
  /^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9._-]+\))?!?: [A-Za-z0-9][A-Za-z0-9 ,.:()'_-]{0,98}$/;
// Work a human merges: the classes past mechanical, and any diff that touches
// a path the merge lane refuses (merge.diff-check.denied-paths in the base
// pr-pipeline.yaml), so the two lists cannot drift apart.
const HOLD_CLASSES = new Set(["work-class: scoped", "work-class: structural", "work-class: untrusted-provenance"]);
const MAX_TEXT = 3000;
const MAX_ITEMS = 20;
const MAX_ITEM = 300;
// GET /compare lists at most this many files, so a listing this long may
// hide a hold path.
const COMPARE_FILES_CAP = 300;

// When a limit stop names no reset time, it is taken to reset this long after
// the run: the shortest plan limit is a five-hour session window
// (https://support.claude.com/en/articles/11145838).
// Hard-coded until pr-pipeline.yaml has a limits.fallback-reset leaf:
// https://github.com/melodic-software/claude-code-plugins/issues/7764
export const FALLBACK_RESET_MS = 5 * 3_600_000;
const HOUR_MS = 3_600_000;

// When a limit stop at `from` may restart: its stated reset (else the
// fallback), held between one hour and seven days after the stop, so a reset
// in the past cannot start a tight restart loop and one far off cannot park
// the issue.
export const clampReset = (resets, from) =>
  Math.min(Math.max(resets ?? from + FALLBACK_RESET_MS, from + HOUR_MS), from + 7 * 24 * HOUR_MS);
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?Z$/;
const MARKER = /^<!-- work-resolve-issue outcome=([a-z]+)(?: resets=(\S+))?(?: run=(\d+))? -->/;

// The marker a limited run leaves on its issue; work-unblock reads it back.
export const limitedMarker = ({ resets, runId }) =>
  `<!-- work-resolve-issue outcome=limited resets=${resets} run=${runId || 0} -->`;

// {outcome, resets, run} from a comment body that opens with the lane's
// marker, or null. resets is epoch milliseconds, or null when absent or
// unreadable.
export function parseOutcomeMarker(body) {
  const match = MARKER.exec(String(body ?? ""));
  if (!match) {
    return null;
  }
  const resets = ISO.test(match[2] ?? "") ? Date.parse(match[2]) : Number.NaN;
  return { outcome: match[1], resets: Number.isFinite(resets) ? resets : null, run: match[3] ?? "" };
}

const stopped = (reason) => ({ exit: "stopped", reason, title: "", summary: "", changes: [], verification: [], notDone: [], steps: [] });
const text = (value) => (typeof value === "string" ? value.slice(0, MAX_TEXT) : "");
const list = (value) =>
  Array.isArray(value) ? value.filter((item) => typeof item === "string").slice(0, MAX_ITEMS).map((item) => item.slice(0, MAX_ITEM)) : [];
// A not_done entry is a string or {what, required}; required marks a check the
// run had to pass and did not, and counts whatever `what` holds.
const notDoneList = (value) =>
  (Array.isArray(value) ? value : [])
    .map((item) =>
      typeof item === "string"
        ? { what: item, required: false }
        : item?.required === true
          ? { what: typeof item.what === "string" ? item.what : "A required check the run did not name.", required: true }
          : typeof item?.what === "string"
            ? { what: item.what, required: false }
            : null,
    )
    .filter(Boolean)
    .slice(0, MAX_ITEMS)
    .map(({ what, required }) => ({ what: what.slice(0, MAX_ITEM), required }));

// The prep steps the run reports, each {activity, result}, both strings;
// post-statuses.mjs decides which of them it posts.
const stepList = (value) =>
  (Array.isArray(value) ? value : [])
    .filter((item) => typeof item?.activity === "string" && typeof item?.result === "string")
    .slice(0, MAX_ITEMS)
    .map(({ activity, result }) => ({ activity: activity.slice(0, 40), result: result.slice(0, 20) }));

// The merge lane's denied-path globs from the resolved config, or null when
// they cannot be read, which holds every PR.
export function readHoldPaths(path) {
  try {
    const paths = JSON.parse(readFileSync(path, "utf8"))?.merge?.["diff-check"]?.["denied-paths"];
    return Array.isArray(paths) && paths.length && paths.every((glob) => typeof glob === "string") ? paths : null;
  } catch {
    return null;
  }
}

// The skill's outcome file, checked as data. Anything unreadable is stopped.
export function readOutcome(path) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return { ...stopped("The run wrote no readable outcome file, so it stopped before it finished."), unread: true };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed) || !EXITS.has(parsed.exit)) {
    return { ...stopped("The run's outcome file names no known exit (done, pushback or stopped)."), unread: true };
  }
  return {
    exit: parsed.exit,
    reason: text(parsed.reason),
    title: text(parsed.title),
    summary: text(parsed.summary),
    changes: list(parsed.changes),
    verification: list(parsed.verification),
    notDone: notDoneList(parsed.not_done),
    steps: stepList(parsed.steps),
    link: parsed.link === "refs" ? "refs" : "closes",
  };
}

// Model text is data. HTML comments go; `&` is escaped first, so no entity
// can spell `@` or `#`, then raw HTML (`<`, `>`) and link syntax (`[`, `]`,
// which could hide a reference definition). `@` is dropped so nothing
// mentions anyone, and issue references are broken: squash merge copies the
// body as plain text, so `#` becomes a full-width ＃, `GH-` and `/issues/` or
// `/pull/` gain a space, and no closing keyword in it can close an issue.
// `://` and `www.` gain a space too, so no bare URL autolinks.
// Control characters other than newline go. The cap applies after escaping.
const neutral = (value, cap) =>
  value
    .replaceAll(/<!--[\s\S]*?(-->|$)/g, "")
    .replaceAll("\r\n", "\n")
    .replaceAll(/[\u0000-\u0009\u000b-\u001f\u007f]/g, " ")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("[", "\\[")
    .replaceAll("]", "\\]")
    .replaceAll("@", "")
    .replaceAll("#", "＃")
    .replaceAll(/\bGH-/gi, "GH -")
    .replaceAll(/\/(issues|pull)\//gi, "/$1 /")
    .replaceAll("://", ": //")
    .replaceAll(/\bwww\./gi, "www .")
    .slice(0, cap)
    .replace(/&[a-z]*$|\\$/, "");

// Every line prefixed `> `, so no line of it can start a heading or leave the
// quote, and the text wraps when rendered.
const quoted = (value) =>
  neutral(value || "(none)", MAX_TEXT)
    .trim()
    .split("\n")
    .map((line) => (line.trim() ? `> ${line.trimEnd()}` : ">"))
    .join("\n");

// One line per item, so an item cannot open a section of its own.
const bullets = (items) =>
  items
    .slice(0, MAX_ITEMS)
    .map((item) => `- ${neutral(item.replaceAll(/\s+/g, " "), MAX_ITEM).trim()}`)
    .join("\n");

// The marker names the run, so --find-prior never reuses a branch whose work
// this report already handed on.
function handBack({ outcome, issueNumber, branch, humanLabel, runUrl, runId }) {
  const pushback = outcome.exit === "pushback";
  const lines = [
    `<!-- work-resolve-issue outcome=${outcome.exit}${runId ? ` run=${runId}` : ""} -->`,
    pushback
      ? "The work-resolve-issue lane did not start this issue: it needs a person to make it clearer first."
      : "The work-resolve-issue lane stopped partway through this issue and needs a person.",
    "",
    "Why, in the run's own words:",
    "",
    quoted(outcome.reason || outcome.summary),
  ];
  if (outcome.notDone.length) {
    lines.push("", "What the run says it did not do:", "", bullets(outcome.notDone.map(({ what }) => what)));
  }
  if (branch) {
    lines.push("", `Partial work is on the branch \`${branch}\`.`);
  }
  if (runUrl) {
    lines.push("", `Run: ${runUrl}`);
  }
  lines.push(
    "",
    pushback
      ? `To retry, answer the question here, remove \`${humanLabel}\` and add \`agent-ready\` again.`
      : `To retry, remove \`${humanLabel}\`, then remove and add \`agent-ready\`.`,
  );
  return {
    action: "hand-back",
    exit: outcome.exit,
    issueNumber,
    comment: lines.join("\n"),
    addLabels: [humanLabel],
    removeLabels: pushback ? ["agent-ready"] : [],
  };
}

// A run the usage limit stopped: one marker comment, agent-ready kept, no
// label, so work-unblock restarts the issue once the limit resets.
function limitedPlan({ issueNumber, branch, resets, runId, runUrl }) {
  const lines = [
    limitedMarker({ resets, runId }),
    `The work-resolve-issue lane stopped on its usage limit, not on this issue. It keeps \`agent-ready\`, and work-unblock starts it again after ${resets}.`,
  ];
  if (branch) {
    lines.push("", `Partial work is on the branch \`${branch}\`.`);
  }
  if (runUrl) {
    lines.push("", `Run: ${runUrl}`);
  }
  return { action: "limited", exit: "limited", issueNumber, resets, runId, comment: lines.join("\n"), addLabels: [], removeLabels: [] };
}

// A lane branch an earlier run left with commits and no report, whose outcome
// this run cannot read: a PR a human merges, with fixed text only.
export function reusePlan({ issueNumber, branch, runUrl = "", earlierRunUrl = "" }) {
  const body = [
    `Closes #${issueNumber}`,
    "",
    HOLD_LINE,
    "",
    "## Summary",
    "",
    `Opened by the work-resolve-issue lane from \`${branch}\`, which an earlier run left with commits and no report. The model did not run again, and the earlier run's outcome could not be read, so this body carries none of its text.`,
    "",
    "## Fix",
    "",
    "The diff shows the changes.",
    "",
    "## Verification",
    "",
    "The earlier run reported no checks here.",
    "",
    earlierRunUrl ? `- The earlier lane run: ${earlierRunUrl}` : "- The earlier lane run.",
    runUrl ? `- This lane run: ${runUrl}` : "- This lane run.",
    "",
    "Left out: every check; a person reviews the diff before merging.",
    "",
    "## Related",
    "",
    `#${issueNumber}`,
  ].join("\n");
  return { action: "open-pr", issueNumber, title: `chore: work on #${issueNumber}`, body, branch };
}

// What to do on the issue, from the outcome and what the run left. `limit` is
// the runner's limit record ({resets}, epoch ms or null) when the run hit its
// usage limit; a missing reset counts from `now`, the run's end.
export function decide({
  outcome,
  issueNumber,
  issueLabels,
  branch,
  changedFiles,
  holdPaths = null,
  humanLabel = "needs-human",
  runUrl = "",
  limit = null,
  now = Date.now(),
  runId = "",
}) {
  outcome = { changes: [], verification: [], notDone: [], ...outcome };
  // A limit record counts only for a run that left no outcome of its own: any
  // code the run executed can forge the record, so it must not hide a stop
  // or pushback the skill reported from the person it goes to.
  if (limit && outcome.unread) {
    const resets = new Date(clampReset(limit.resets, now)).toISOString().replace(/\.\d+Z$/, "Z");
    return limitedPlan({ issueNumber, branch, resets, runId, runUrl });
  }
  if (outcome.exit === "done" && !branch) {
    return handBack({
      outcome: stopped("The run reported done but committed nothing."),
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
    });
  }
  if (outcome.exit !== "done") {
    return handBack({ outcome, issueNumber, branch, humanLabel, runUrl, runId });
  }
  if (outcome.notDone.some(({ required }) => required)) {
    return handBack({
      outcome: {
        ...outcome,
        exit: "stopped",
        reason: "The run reported done but left a required check undone, so it is not finished.",
      },
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
    });
  }
  const refs = outcome.link === "refs";
  const hold =
    refs ||
    issueLabels.some((name) => HOLD_CLASSES.has(name)) ||
    changedFiles.length >= COMPARE_FILES_CAP ||
    holdPaths === null ||
    changedFiles.some((path) => holdPaths.some((glob) => posix.matchesGlob(path, glob)));
  // The sections of the PR body contract (.claude/rules/pr-body-contract.md),
  // in the org PR template's order, with the run's gaps above the work.
  const gaps = outcome.notDone.map(({ what }) => what);
  const body = [
    refs ? `Refs: #${issueNumber}` : `Closes #${issueNumber}`,
    ...(hold ? ["", HOLD_LINE] : []),
    "",
    "## Summary",
    "",
    "Opened by the work-resolve-issue lane. The run's own summary:",
    "",
    quoted(outcome.summary),
    ...(gaps.length ? ["", "## Not verified", "", bullets(gaps)] : []),
    "",
    "## Fix",
    "",
    outcome.changes.length ? bullets(outcome.changes) : "The run listed no changes; the diff shows them.",
    "",
    "## Verification",
    "",
    outcome.verification.length ? `The run reports:\n\n${bullets(outcome.verification)}` : "The run listed no checks.\n",
    runUrl ? `- The lane run: ${runUrl}` : "- The lane run.",
    "",
    gaps.length ? "Left out: the items under Not verified." : "Left out: nothing the run reported.",
    "",
    "## Related",
    "",
    `#${issueNumber}`,
  ].join("\n");
  return {
    action: "open-pr",
    issueNumber,
    title: CONVENTIONAL.test(outcome.title) ? outcome.title : `chore: work on #${issueNumber}`,
    body,
    branch,
  };
}

function humanLabelFrom(path) {
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
  // agent-ready starts this lane, so a pushback adding it would start the
  // next run itself.
  if (label.trim().toLowerCase() === "agent-ready") {
    throw new Error("the human-gated role label is agent-ready");
  }
  return label;
}

// The issue's lane branch name, capturing its run id and attempt.
const laneBranch = (issueNumber) => new RegExp(`^work-resolve-issue/issue-${issueNumber}-([1-9][0-9]*)-([1-9][0-9]*)$`);
export const isLaneBranch = (name, issueNumber) => laneBranch(issueNumber).test(name ?? "");

export function readBranch(dir, issueNumber) {
  try {
    const { branch } = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
    return isLaneBranch(branch, issueNumber) ? branch : "";
  } catch {
    return "";
  }
}

// Whether an earlier run already did the issue's work, from facts read before
// the resolve-issue mint:
//   stop   a lanes-App PR from a lane branch is open, or an open PR in this
//          repository closes the issue and the lanes App or a listed human
//          opened it (anyone can write `Closes #N`, so an outsider's PR
//          would let anyone stop the lane);
//   reuse  the first lane branch, newest first, with commits ahead of the default branch,
//          a tip commit GitHub verified and the lanes App authored or
//          committed (a branch name proves nothing about who pushed to it),
//          no lanes-App PR in any state (a closed one was rejected or
//          merged) and no lanes-App outcome marker for its run (that report
//          already handed the work on, so the model runs again);
//   run    otherwise.
// `branches` are {name, aheadBy, tip, tipAt, pulls} (tip from GET
// /commits/{sha}, tipAt epoch ms, pulls from
// GET /pulls?state=all&head=); `closing` the issue's open closing PRs as
// GraphQL nodes; `markers` the lanes App's parsed outcome markers, each with
// `at`. A marker naming no run, posted before markers named one, covers every
// branch whose tip is not newer than it.
export function findPrior({ issueNumber, repo, bot, humans, branches, closing, markers }) {
  const shape = laneBranch(issueNumber);
  const lane = branches
    .map((branch) => ({ ...branch, match: shape.exec(branch.name) }))
    .filter(({ match }) => match)
    .sort((a, b) => Number(b.match[1]) - Number(a.match[1]) || Number(b.match[2]) - Number(a.match[2]));
  const byBot = (pull) => pull?.user?.login === bot;
  const open = lane.find(({ pulls }) => pulls.some((pull) => pull.state === "open" && byBot(pull)));
  if (open) {
    return { action: "stop", reason: `the lanes App's PR from ${open.name} is open` };
  }
  const trusted = closing.find(
    ({ author, repository }) =>
      String(repository?.nameWithOwner ?? "").toLowerCase() === repo.toLowerCase() &&
      ((author?.__typename === "Bot" && (author.login === bot || `${author.login}[bot]` === bot)) ||
        (author?.__typename === "User" && humans.has(author.databaseId))),
  );
  if (trusted) {
    return { action: "stop", reason: `open PR #${trusted.number} closes the issue` };
  }
  const reported = ({ match, tipAt }) =>
    markers.some((marker) => marker.run === match[1] || (marker.run === "" && !(marker.at <= tipAt)));
  const laneTip = ({ tip }) =>
    tip?.commit?.verification?.verified === true && (tip.author?.login === bot || tip.committer?.login === bot);
  const reuse = lane.find(
    (branch) => branch.aheadBy > 0 && laneTip(branch) && !branch.pulls.some(byBot) && !reported(branch),
  );
  return reuse ? { action: "reuse", branch: reuse.name } : { action: "run" };
}

// The listed humans' ids in trusted-actors.json; throws when it cannot be read.
export function readHumans(path) {
  const list = JSON.parse(readFileSync(path, "utf8"));
  if (list?.version !== 1 || !Array.isArray(list.actors)) {
    throw new Error("the trusted-actor list does not match its schema");
  }
  return new Set(list.actors.filter((actor) => actor?.kind === "human" && Number.isInteger(actor.id)).map((actor) => actor.id));
}

// The runner's limit record in lane.json: {resets} (epoch ms, or null when
// the run named none) when the run's class is rate-limit, else null.
export function readLimit(dir) {
  try {
    const lane = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
    if (lane?.class !== "rate-limit") {
      return null;
    }
    const resets = ISO.test(lane.resets ?? "") ? Date.parse(lane.resets) : Number.NaN;
    return { resets: Number.isFinite(resets) ? resets : null };
  } catch {
    return null;
  }
}

function api({ fetch, apiUrl, token }) {
  return async (method, path, body) => {
    const response = await fetch(`${apiUrl}${path}`, {
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) {
      throw new Error(`${method} ${path} answered ${response.status}`);
    }
    return response.status === 204 ? null : response.json();
  };
}

// Every page of a list endpoint, 100 per page. A script activity runs from a
// copy of its own directory (collect-base-activity), so this is not imported.
async function paginate(github, path, maxPages = 50) {
  const items = [];
  const separator = path.includes("?") ? "&" : "?";
  for (let page = 1; page <= maxPages; page += 1) {
    const batch = await github("GET", `${path}${separator}per_page=100&page=${page}`);
    if (!Array.isArray(batch)) {
      throw new Error(`${path} answered something other than a list`);
    }
    items.push(...batch);
    if (batch.length < 100) {
      return items;
    }
  }
  throw new Error(`${path} has more than ${maxPages} pages`);
}

const CLOSING_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      closedByPullRequestsReferences(first: 100, after: $after, includeClosedPrs: false) {
        nodes { number author { __typename login ... on User { databaseId } } repository { nameWithOwner } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

// Every open PR that closes the issue, across pages, so no number of other
// PRs can push a trusted one out of reach.
async function closingPulls(github, { owner, name, number }, maxPages = 50) {
  const nodes = [];
  let after = null;
  for (let page = 1; page <= maxPages; page += 1) {
    const answer = await github("POST", "/graphql", { query: CLOSING_QUERY, variables: { owner, name, number, after } });
    const refs = answer?.data?.repository?.issue?.closedByPullRequestsReferences;
    if (answer?.errors?.length || !Array.isArray(refs?.nodes)) {
      throw new Error("the issue's closing pull requests could not be read");
    }
    nodes.push(...refs.nodes);
    if (typeof refs.pageInfo?.hasNextPage !== "boolean") {
      throw new Error("the issue's closing pull requests answered no page information");
    }
    if (!refs.pageInfo.hasNextPage) {
      return nodes;
    }
    after = refs.pageInfo.endCursor;
    if (typeof after !== "string" || after === "") {
      throw new Error("the issue's closing pull requests answered a next page with no cursor");
    }
  }
  throw new Error(`the issue has more than ${maxPages} pages of closing pull requests`);
}

// --find-prior: reads the facts findPrior decides on and writes its step
// outputs. Any failed read, or an answer of the wrong shape, fails the step,
// so the mint never follows it.
export async function findPriorMain({ env = process.env, fetch = globalThis.fetch } = {}) {
  try {
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) {
      throw new Error("ISSUE_NUMBER is not an issue number");
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const issueNumber = Number(env.ISSUE_NUMBER);
    const [owner, name] = env.GITHUB_REPOSITORY.split("/");
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const bot = env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]";
    const humans = readHumans(env.TRUSTED_ACTORS_PATH ?? "");
    const github = api({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN });
    const markers = (await paginate(github, `${repo}/issues/${issueNumber}/comments`))
      .filter((comment) => comment.user?.login === bot)
      .map((comment) => ({ ...parseOutcomeMarker(comment.body), at: Date.parse(comment.created_at) }))
      .filter((marker) => marker.outcome !== undefined);
    // A marker naming no run is matched by its time, so that time must read.
    if (markers.some((marker) => marker.run === "" && !Number.isFinite(marker.at))) {
      throw new Error("a lane outcome marker that names no run has no readable time");
    }
    const closing = await closingPulls(github, { owner, name, number: issueNumber });
    const shape = laneBranch(issueNumber);
    // The trailing `-` keeps issue 1 from matching issue 12's branches.
    const matching = await github("GET", `${repo}/git/matching-refs/heads/work-resolve-issue/issue-${issueNumber}-`);
    if (!Array.isArray(matching)) {
      throw new Error("the issue's lane branches could not be read");
    }
    const refs = matching
      .map((ref) => ({ name: String(ref.ref ?? "").replace(/^refs\/heads\//, ""), sha: ref.object?.sha }))
      .filter((ref) => shape.test(ref.name));
    const base = refs.length ? (await github("GET", repo))?.default_branch : "";
    if (refs.length && (typeof base !== "string" || base === "")) {
      throw new Error("the repository's default branch could not be read");
    }
    const legacy = markers.some((marker) => marker.run === "");
    const branches = [];
    for (const ref of refs) {
      const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(base)}...${encodeURIComponent(ref.name)}`);
      if (!Number.isSafeInteger(comparison?.ahead_by) || comparison.ahead_by < 0) {
        throw new Error(`the commits ${ref.name} holds ahead of ${base} could not be read`);
      }
      const pulls = await paginate(github, `${repo}/pulls?state=all&head=${encodeURIComponent(`${owner}:${ref.name}`)}`);
      if (!/^[0-9a-f]{40}$/.test(ref.sha ?? "")) {
        throw new Error(`the tip of ${ref.name} could not be read`);
      }
      const tip = await github("GET", `${repo}/commits/${ref.sha}`);
      // Only a marker naming no run needs the tip's time.
      const tipAt = legacy ? Date.parse(tip?.commit?.committer?.date) : Number.NaN;
      if (legacy && !Number.isFinite(tipAt)) {
        throw new Error(`the tip commit time of ${ref.name} could not be read`);
      }
      branches.push({ name: ref.name, aheadBy: comparison.ahead_by, tip, tipAt, pulls });
    }
    const prior = findPrior({ issueNumber, repo: env.GITHUB_REPOSITORY, bot, humans, branches, closing, markers });
    const outputs =
      prior.action === "run"
        ? { proceed: "true", "skip-reason": "", "reuse-branch": "" }
        : { proceed: "false", "skip-reason": "not-applicable", "reuse-branch": prior.action === "reuse" ? prior.branch : "" };
    appendFileSync(env.GITHUB_OUTPUT, Object.entries(outputs).map(([key, value]) => `${key}=${value}\n`).join(""));
    console.log(
      prior.action === "run"
        ? `report-outcome: no earlier run of issue #${issueNumber} left work to report; the model runs`
        : prior.action === "reuse"
          ? `report-outcome: ${prior.branch} holds unreported work for issue #${issueNumber}; the model is skipped and report-outcome opens its PR`
          : `report-outcome: ${prior.reason}; the model is skipped`,
    );
    return 0;
  } catch (error) {
    console.log(`::error title=report-outcome::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

export async function main({ env = process.env, fetch = globalThis.fetch, now = Date.now() } = {}) {
  try {
    const issueNumber = Number(env.ISSUE_NUMBER);
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) {
      throw new Error("ISSUE_NUMBER is not an issue number");
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const reuse = env.REUSE_BRANCH ?? "";
    const reused = laneBranch(issueNumber).exec(reuse);
    if (reuse && !reused) {
      throw new Error("REUSE_BRANCH is not this issue's lane branch");
    }
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const github = api({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN });
    const dir = env.WORK_OUTCOME_DIR ?? "";
    const ran = readBranch(dir, issueNumber);
    // On a reuse the downloaded outcome is the branch's own only when it names
    // that branch (a re-run attempt of the run that made it).
    const outcome = reuse && ran !== reuse ? null : readOutcome(join(dir, "work-outcome.json"));
    const branch = reuse || ran;
    const limit = readLimit(dir);
    const runUrlOf = (id) => (env.GITHUB_SERVER_URL && id ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${id}` : "");
    const runUrl = runUrlOf(env.GITHUB_RUN_ID);
    const issue = await github("GET", `${repo}/issues/${issueNumber}`);
    let changedFiles = [];
    let base = "";
    if (outcome?.exit === "done" && branch) {
      base = (await github("GET", repo)).default_branch;
      const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(base)}...${encodeURIComponent(branch)}`);
      changedFiles = (comparison.files ?? []).flatMap((file) =>
        file.previous_filename ? [file.filename, file.previous_filename] : [file.filename],
      );
    }
    // A reuse whose outcome cannot be read never takes the limit record: the
    // skipped run hit no limit, and a limited marker would loop restarts.
    const plan =
      reuse && (outcome === null || outcome.unread)
        ? reusePlan({ issueNumber, branch, runUrl, earlierRunUrl: runUrlOf(reused[1]) })
        : decide({
            outcome,
            issueNumber,
            issueLabels: (issue.labels ?? []).map((label) => label.name),
            branch,
            changedFiles,
            holdPaths: readHoldPaths(env.RESOLVED_CONFIG || join(env.RUNNER_TEMP ?? "", "resolved-config.json")),
            humanLabel: humanLabelFrom(env.TRACKER_CONFIG ?? ".base/.work-item-tracker.json"),
            runUrl,
            limit,
            now,
            runId: /^[1-9][0-9]{0,14}$/.test(env.GITHUB_RUN_ID ?? "") ? env.GITHUB_RUN_ID : "",
          });
    if (plan.action === "limited") {
      // Once per run: a rerun of this report, however late, finds its own
      // marker in the issue's whole comment history and posts nothing.
      const bot = env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]";
      const comments = await paginate(github, `${repo}/issues/${issueNumber}/comments`);
      const posted = comments.some((comment) => {
        const marker = comment.user?.login === bot ? parseOutcomeMarker(comment.body) : null;
        return marker?.outcome === "limited" && plan.runId !== "" && marker.run === plan.runId;
      });
      if (!posted) {
        await github("POST", `${repo}/issues/${issueNumber}/comments`, { body: plan.comment });
      }
      console.log(`report-outcome: issue #${issueNumber} stopped on the usage limit; restart after ${plan.resets}`);
      return 0;
    }
    if (plan.action === "open-pr") {
      // A rerun finds the PR it already opened. Anyone can open a PR between two branches of a public repository, so
      // only one the lanes App opened is reused; otherwise the create fails.
      const owner = env.GITHUB_REPOSITORY.split("/")[0];
      const bot = env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]";
      const open = (
        await github("GET", `${repo}/pulls?state=open&head=${encodeURIComponent(`${owner}:${plan.branch}`)}`)
      ).find((candidate) => candidate.user?.login === bot);
      const pull =
        open ??
        (await github("POST", `${repo}/pulls`, {
          title: plan.title,
          body: plan.body,
          head: plan.branch,
          base: base || (await github("GET", repo)).default_branch,
          draft: false,
        }));
      console.log(`report-outcome: opened PR #${pull.number} for issue #${issueNumber}`);
      return 0;
    }
    // The label first, so a failed comment still leaves the issue with a person.
    await github("POST", `${repo}/issues/${issueNumber}/labels`, { labels: plan.addLabels });
    for (const name of plan.removeLabels) {
      await github("DELETE", `${repo}/issues/${issueNumber}/labels/${encodeURIComponent(name)}`).catch((error) =>
        console.log(`report-outcome: could not remove ${name}: ${error.message}`),
      );
    }
    await github("POST", `${repo}/issues/${issueNumber}/comments`, { body: plan.comment });
    console.log(`report-outcome: handed issue #${issueNumber} back (${plan.exit})`);
    return 0;
  } catch (error) {
    console.log(`::error title=report-outcome::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = process.argv[2] === "--find-prior" ? await findPriorMain() : await main();
}
