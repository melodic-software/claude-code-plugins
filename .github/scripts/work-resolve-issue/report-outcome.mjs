#!/usr/bin/env node
// report-outcome.mjs: the work-resolve-issue lane's report-outcome leaf. Reads
// what the resolve-issue run left and acts on the issue, with no model:
//
//   done      opens a draft PR from the run's branch: the body starts
//             `Closes #<issue>`, the title is the run's when it is Conventional
//             Commits (else `chore: work on #<issue>`), the PR gets the issue's
//             `work-class:` labels, and the body carries the hold line when a
//             human must merge it.
//   pushback  comments why, adds the human-gated label, removes agent-ready.
//   stopped   comments why, adds the human-gated label, and names the branch
//             that holds any partial work. A missing or invalid outcome file
//             is stopped.
//
// Run from the base copy. It reads only the outcome directory and the GitHub
// API, and never writes to a branch.
//
// Environment:
//   GH_TOKEN            token with pull-requests: write and issues: write
//   GITHUB_REPOSITORY   owner/repo
//   ISSUE_NUMBER        the issue the lane worked
//   WORK_OUTCOME_DIR    holds work-outcome.json (written by the skill, so
//                       untrusted) and lane.json (written by the runner)
//   TRACKER_CONFIG      base .work-item-tracker.json, for the human-gated label
//   GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID
import { readFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

export const HOLD_LINE = "Hold: a human merges this";
const EXITS = new Set(["done", "pushback", "stopped"]);
// The subject allows no `#` or `/`, so the squash commit title cannot name an
// issue to close.
const CONVENTIONAL =
  /^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9._-]+\))?!?: [A-Za-z0-9][A-Za-z0-9 ,.:()'_-]{0,98}$/;
const WORK_CLASS = /^work-class: /;
// Work a human merges: the classes past mechanical, and any diff that touches
// what the lanes or their trust rest on.
const HOLD_CLASSES = new Set(["work-class: scoped", "work-class: structural", "work-class: untrusted-provenance"]);
const HOLD_PATHS = [
  /^\.github\//,
  /^\.claude\//,
  /^\.claude-plugin\//,
  /(^|\/)(AGENTS|CLAUDE|REVIEW)\.md$/,
  /^docs\/conventions\//,
  /^plugins\/[^/]+\/hooks\//,
  /^plugins\/[^/]+\/\.claude-plugin\//,
  /^scripts\//,
];
const MAX_TEXT = 3000;
// GET /compare lists at most this many files, so a listing this long may
// hide a hold path.
const COMPARE_FILES_CAP = 300;

const stopped = (reason) => ({ exit: "stopped", reason, title: "", summary: "" });
const text = (value) => (typeof value === "string" ? value.slice(0, MAX_TEXT) : "");

// The skill's outcome file, checked as data. Anything unreadable is stopped.
export function readOutcome(path) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return stopped("The run wrote no readable outcome file, so it stopped before it finished.");
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed) || !EXITS.has(parsed.exit)) {
    return stopped("The run's outcome file names no known exit (done, pushback or stopped).");
  }
  return { exit: parsed.exit, reason: text(parsed.reason), title: text(parsed.title), summary: text(parsed.summary) };
}

// Model text goes inside a fenced block, so it adds no mention or markup when
// rendered. Squash merge copies the body as plain text, so issue references
// are broken too: `#` becomes a full-width ＃ and `/issues/` or `/pull/` gains
// a space, so no closing keyword in it can close an issue.
const quoted = (value) =>
  [
    "```text",
    (value || "(none)")
      .replaceAll("`", "'")
      .replaceAll("#", "＃")
      .replaceAll(/\/(issues|pull)\//gi, "/$1 /"),
    "```",
  ].join("\n");

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

// What to do on the issue, from the outcome and what the run left.
export function decide({ outcome, issueNumber, issueLabels, branch, changedFiles, humanLabel = "needs-human", runUrl = "" }) {
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
  const labels = issueLabels.filter((name) => WORK_CLASS.test(name));
  const hold =
    labels.some((name) => HOLD_CLASSES.has(name)) ||
    changedFiles.length >= COMPARE_FILES_CAP ||
    changedFiles.some((path) => HOLD_PATHS.some((pattern) => pattern.test(path)));
  const body = [
    `Closes #${issueNumber}`,
    ...(hold ? ["", HOLD_LINE] : []),
    "",
    "## Summary",
    "",
    "Opened by the work-resolve-issue lane. The run's own summary:",
    "",
    quoted(outcome.summary),
    "",
    "## Fix",
    "",
    `The commits on \`${branch}\`.`,
    "",
    "## Verification",
    "",
    runUrl ? `The lane run: ${runUrl}` : "The lane run.",
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
    labels,
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
  return label;
}

function readBranch(dir, issueNumber) {
  try {
    const { branch } = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
    return new RegExp(`^work-resolve-issue/issue-${issueNumber}-[1-9][0-9]*-[1-9][0-9]*$`).test(branch ?? "") ? branch : "";
  } catch {
    return "";
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

export async function main({ env = process.env, fetch = globalThis.fetch } = {}) {
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
      humanLabel: humanLabelFrom(env.TRACKER_CONFIG ?? ".base/.work-item-tracker.json"),
      runUrl:
        env.GITHUB_SERVER_URL && env.GITHUB_RUN_ID
          ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
          : "",
    });
    if (plan.action === "open-pr") {
      const pull = await github("POST", `${repo}/pulls`, {
        title: plan.title,
        body: plan.body,
        head: plan.branch,
        base,
        draft: true,
      });
      if (plan.labels.length) {
        await github("POST", `${repo}/issues/${pull.number}/labels`, { labels: plan.labels });
      }
      console.log(`report-outcome: opened draft PR #${pull.number} for issue #${issueNumber}`);
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
