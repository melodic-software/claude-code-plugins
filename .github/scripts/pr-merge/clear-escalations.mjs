#!/usr/bin/env node
// clear-escalations.mjs: takes the human-gated label off an open pull request
// into main once the reason the pr-unblock lane recorded for it no longer holds
// at the current head. No model.
//
// Only a label the lanes App set is ever removed, and only when all of these hold:
// - The newest `labeled` event for the label on the PR's timeline has the lanes
//   App bot as its actor, and it is no later than the App's newest escalation
//   comment (report-escalation.sh writes the label, then the comment).
// - That comment is the App's: its author is the bot login and a Bot account,
//   its first line is the pr-unblock escalation marker, its second the
//   resume-key line, and its `- Reason:` line names one of CHECKS. Text anyone
//   else writes, a marker included, is never read for a reason.
// - No account other than a bot commented or reviewed after that comment: a
//   person who spoke since may be asking the lane to wait.
// - The recorded reason no longer holds at the current head:
//     workflow-staged          main changed nothing under .github/workflows/
//                              since its merge base with the head, so merging
//                              main into the head stages no workflow change
//     unresolved-conflict,     GitHub reports the PR mergeable: no conflict
//     protected-path-conflict  is left to resolve
//     feedback-protected-path  the PR changes nothing under .github/
//   A listing that may be cut short, or a mergeable state not yet computed,
//   counts as the reason still holding.
// Any other reason is decided by a person and is never cleared here.
//
// Before the label comes off, the App posts one comment naming the cleared
// reason and the head; a sweep that finds that comment for this escalation
// and head only retries the removal. At most CLEARS_PER_RUN a run.
//
// Environment:
//   GH_TOKEN             the lane App token (pull-requests and issues write)
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   TRACKER_CONFIG       the base .work-item-tracker.json, for the human-gated
//                        label (default .base/.work-item-tracker.json)
//   LANES_BOT_LOGIN      the lanes App bot login (default
//                        melodic-automation-lanes[bot])
//   GITHUB_API_URL
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { humanGatedLabelFrom } from "../pr-unblock/address-feedback.mjs";
import { isProtectedPath } from "../pr-unblock/thread-scope.mjs";

const DEFAULT_BOT = "melodic-automation-lanes[bot]";
const ESCALATION = "<!-- work-items:escalation lane=pr-unblock kind=escalated -->";
const RESUME_KEY = /^<!-- pr-unblock resume-key=([0-9a-f]{40}|[0-9a-f]{64}) -->$/;
const REASON = /^- Reason: `([a-z-]+)`$/m;
const clearedMarker = (reason, head) => `<!-- pr-pipeline needs-human-cleared reason=${reason} head=${head} -->`;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
// The compare API lists at most 300 files, the PR files API at most 3000.
const COMPARE_CAP = 300;
const FILES_CAP = 3000;
// Each clear lets the lanes run on the PR again (judgment).
export const CLEARS_PER_RUN = 5;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (number, error) =>
  console.log(`::error title=clear-escalations::#${number}: ${escapeCommand(error?.message ?? error)}`);
const lines = (body) => String(body ?? "").split("\n").map((line) => line.replace(/\r$/, ""));
const same = (a, b) => String(a ?? "").toLowerCase() === String(b).toLowerCase();
const isApp = (user, bot) => user?.login === bot && user?.type === "Bot";

// Why each reason no longer holds at `pull`'s head, or null while it holds.
const CHECKS = Object.freeze({
  "workflow-staged": async ({ github, repo, pull, mainSha }) => {
    const files = (await github("GET", `/repos/${repo}/compare/${pull.head.sha}...${mainSha}`))?.files;
    if (!Array.isArray(files) || files.length >= COMPARE_CAP) {
      return null;
    }
    const workflow = (path) => /^\.github\/workflows\//.test(String(path ?? ""));
    return files.some((file) => workflow(file.filename) || workflow(file.previous_filename))
      ? null
      : `main changes nothing under .github/workflows/ since its merge base with ${pull.head.sha}`;
  },
  "unresolved-conflict": async ({ pull }) => mergeable(pull),
  "protected-path-conflict": async ({ pull }) => mergeable(pull),
  "feedback-protected-path": async ({ github, repo, pull }) => {
    const files = await paginate(github, `/repos/${repo}/pulls/${pull.number}/files`);
    return files.length >= FILES_CAP || files.some((file) => isProtectedPath(file.filename) || isProtectedPath(file.previous_filename ?? ""))
      ? null
      : "the pull request changes nothing under .github/";
  },
});

function mergeable(pull) {
  return pull.mergeable === true && pull.mergeable_state !== "dirty" ? "GitHub reports no conflict with main" : null;
}

export const clearedComment = (reason, head, why, label) =>
  `${clearedMarker(reason, head)}\nThe pr-unblock lane escalated this pull request as \`${reason}\`, and that no longer holds at \`${head}\`: ${why}. pr-merge removed \`${label}\`, so the lanes run on it again. To keep a person on it, add \`${label}\` back: a label a person adds is never removed.`;

// When a timeline item was written, and by whom, for a comment or review.
function spoken(item) {
  if (item.event === "commented") {
    return [{ user: item.user ?? item.actor, at: Date.parse(item.created_at) }];
  }
  if (item.event === "reviewed") {
    return [{ user: item.user, at: Date.parse(item.submitted_at) }];
  }
  if (item.event === "line-commented" || item.event === "commit-commented") {
    return (item.comments ?? []).map((comment) => ({ user: comment.user, at: Date.parse(comment.created_at) }));
  }
  return [];
}

// What to clear on `number`, or { reason } saying why nothing is.
async function verdict({ github, repo, number, label, bot, mainSha }) {
  const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
  const escalation = timeline
    .filter((item) => item.event === "commented" && isApp(item.user, bot))
    .map((item) => ({ item, body: lines(item.body), at: Date.parse(item.created_at) }))
    .filter(({ body, at }) => body[0] === ESCALATION && RESUME_KEY.test(body[1] ?? "") && Number.isFinite(at))
    .at(-1);
  if (escalation === undefined) {
    return { reason: "no pr-unblock escalation by the lanes App" };
  }
  const recorded = REASON.exec(escalation.body.join("\n"))?.[1];
  if (!Object.hasOwn(CHECKS, recorded ?? "")) {
    return { reason: `its escalation reason ${recorded ?? "(none)"} is one a person decides` };
  }
  const labeled = timeline.filter((item) => item.event === "labeled" && same(item.label?.name, label)).at(-1);
  if (!isApp(labeled?.actor, bot)) {
    return { reason: `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App` };
  }
  if (!(Date.parse(labeled.created_at) <= escalation.at)) {
    return { reason: `${label} was added after the escalation comment` };
  }
  const speaker = timeline
    .flatMap(spoken)
    .find(({ user, at }) => !(at <= escalation.at) && user?.type !== "Bot");
  if (speaker !== undefined) {
    return { reason: `${speaker.user?.login ?? "an account"} commented or reviewed after the escalation` };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  if (pull?.state !== "open" || pull.base?.ref !== "main" || !SHA.test(String(pull.head?.sha))) {
    return { reason: "not an open pull request into main" };
  }
  if (!(pull.labels ?? []).some((item) => same(item.name, label))) {
    return { reason: `${label} is no longer on it` };
  }
  const why = await CHECKS[recorded]({ github, repo, pull, mainSha });
  if (why === null) {
    return { reason: `${recorded} still holds at ${pull.head.sha}` };
  }
  const marker = clearedMarker(recorded, pull.head.sha);
  const explained = timeline.some(
    (item) => item.event === "commented" && isApp(item.user, bot) && Date.parse(item.created_at) >= escalation.at && lines(item.body)[0] === marker,
  );
  return { reason: null, recorded, head: pull.head.sha, why, explained };
}

export async function main({ env = process.env, github } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("clear-escalations: the lanes kill switch stops this run; nothing read or removed");
      return 0;
    }
    const repo = env.GITHUB_REPOSITORY;
    const bot = env.LANES_BOT_LOGIN || DEFAULT_BOT;
    const label = humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/.work-item-tracker.json");
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const tip = await github("GET", `/repos/${repo}/git/ref/heads/main`);
    const mainSha = tip?.ref === "refs/heads/main" ? tip.object?.sha : undefined;
    if (!SHA.test(String(mainSha))) {
      throw new Error("main's tip has no commit SHA");
    }
    const held = (await paginate(github, `/repos/${repo}/issues?state=open&labels=${encodeURIComponent(label)}`)).filter(
      (item) => item.pull_request && Number.isSafeInteger(item.number) && item.number > 0,
    );
    let failed = 0;
    let cleared = 0;
    for (const { number } of held) {
      if (cleared >= CLEARS_PER_RUN) {
        console.log(`clear-escalations: #${number} not checked: ${CLEARS_PER_RUN} cleared this run`);
        continue;
      }
      try {
        const result = await verdict({ github, repo, number, label, bot, mainSha });
        if (result.reason !== null) {
          console.log(`clear-escalations: #${number} kept: ${result.reason}`);
          continue;
        }
        // The comment first: a failed removal is retried by the next sweep,
        // which finds the comment and posts no second one.
        const base = `/repos/${repo}/issues/${number}`;
        if (!result.explained) {
          await github("POST", `${base}/comments`, { body: clearedComment(result.recorded, result.head, result.why, label) });
        }
        await github("DELETE", `${base}/labels/${encodeURIComponent(label)}`);
        cleared += 1;
        console.log(`clear-escalations: #${number} cleared: ${result.recorded} no longer holds at ${result.head}`);
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=clear-escalations::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
