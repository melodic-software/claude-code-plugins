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
//
// Run from the base copy. It reads only the outcome directory and the GitHub
// API, and never writes to a branch.
//
// Environment:
//   GH_TOKEN            token with pull-requests: write and issues: write
//   GITHUB_REPOSITORY   owner/repo
//   ISSUE_NUMBER        the issue the lane worked
//   WORK_OUTCOME_DIR    holds work-outcome.json (written by the skill, so
//                       untrusted) and lane.json (written by the runner: the
//                       lane branch, and the run's limit `class` and `resets`)
//   TRACKER_CONFIG      base .work-item-tracker.json, for the human-gated label
//   RESOLVED_CONFIG     resolve-config's output for this run (default
//                       $RUNNER_TEMP/resolved-config.json), for the denied paths
//   LANES_BOT_LOGIN     the lanes App bot login, the only author of an open PR
//                       a rerun reuses (default melodic-automation-lanes[bot])
//   GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID
import { readFileSync } from "node:fs";
import { join, posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

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

function handBack({ outcome, issueNumber, branch, humanLabel, runUrl }) {
  const pushback = outcome.exit === "pushback";
  const lines = [
    `<!-- work-resolve-issue outcome=${outcome.exit} -->`,
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
    });
  }
  if (outcome.exit !== "done") {
    return handBack({ outcome, issueNumber, branch, humanLabel, runUrl });
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

export function readBranch(dir, issueNumber) {
  try {
    const { branch } = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
    return new RegExp(`^work-resolve-issue/issue-${issueNumber}-[1-9][0-9]*-[1-9][0-9]*$`).test(branch ?? "") ? branch : "";
  } catch {
    return "";
  }
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

export async function main({ env = process.env, fetch = globalThis.fetch, now = Date.now() } = {}) {
  try {
    const issueNumber = Number(env.ISSUE_NUMBER);
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) {
      throw new Error("ISSUE_NUMBER is not an issue number");
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const github = api({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN });
    const dir = env.WORK_OUTCOME_DIR ?? "";
    const outcome = readOutcome(join(dir, "work-outcome.json"));
    const branch = readBranch(dir, issueNumber);
    const limit = readLimit(dir);
    const issue = await github("GET", `${repo}/issues/${issueNumber}`);
    let changedFiles = [];
    let base = "";
    if (outcome.exit === "done" && branch) {
      base = (await github("GET", repo)).default_branch;
      const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(base)}...${encodeURIComponent(branch)}`);
      changedFiles = (comparison.files ?? []).flatMap((file) =>
        file.previous_filename ? [file.filename, file.previous_filename] : [file.filename],
      );
    }
    const plan = decide({
      outcome,
      issueNumber,
      issueLabels: (issue.labels ?? []).map((label) => label.name),
      branch,
      changedFiles,
      holdPaths: readHoldPaths(env.RESOLVED_CONFIG || join(env.RUNNER_TEMP ?? "", "resolved-config.json")),
      humanLabel: humanLabelFrom(env.TRACKER_CONFIG ?? ".base/.work-item-tracker.json"),
      runUrl:
        env.GITHUB_SERVER_URL && env.GITHUB_RUN_ID
          ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
          : "",
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
          base,
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
  process.exitCode = await main();
}
