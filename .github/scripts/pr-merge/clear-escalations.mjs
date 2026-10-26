#!/usr/bin/env node
// clear-escalations.mjs: takes the human-gated label off an open pull request
// into main once the reason the pr-unblock lane recorded for it no longer holds
// at the current head. No model.
//
// Only a label the lanes App set is ever removed, and only when all of these hold:
// - The newest `labeled` event for the label on the PR's timeline has the lanes
//   App bot as its actor, and the App's first escalation comment after it
//   came within PAIRED_MS (report-escalation.sh writes the label, then the
//   comment).
// - No review lane holds it: no comment carrying a REVIEW_HOLD marker line, by
//   claude[bot] or by github-actions[bot] ending in the lane's `claude-lane:`
//   footer, was written or edited since the label was last removed (ever,
//   when it never was). A lane adding a label the PR already carries writes
//   no `labeled` event, so its hold can sit under the App's label, and a
//   person removing the label is what lifts it.
// - Every escalation comment since that label event is the App's: its author
//   is the bot login and a Bot account, its first line is the pr-unblock
//   escalation marker, its second the resume-key line, and its `- Reason:`
//   line names one of CHECKS. A later escalation adds no label event, so each
//   one counts. Text anyone else writes, a marker included, is never read.
// - No lanes App comment written or edited since then carries any other
//   marker (pr-merge's, another lane's): unknown keeps it.
// - No person commented, reviewed, or left a review or commit comment since
//   the label went on: they may want the lane to wait. Bot accounts (AI
//   review, other lanes) are not someone speaking; an App marker is judged
//   by the rule above instead.
// - Every recorded reason no longer holds at the current head:
//     workflow-staged          main changed nothing under .github/workflows/
//                              since its merge base with the head, so merging
//                              main into the head stages no workflow change
//     unresolved-conflict,     GitHub reports the PR mergeable: no conflict
//     protected-path-conflict  is left to resolve
//     feedback-protected-path  the PR changes nothing under .github/workflows/
//   A listing that may be cut short, or a mergeable state not yet computed,
//   counts as the reason still holding.
// Any other reason is decided by a person and is never cleared here.
//
// With no pr-unblock escalation since the label, a pr-merge escalation clears
// as `head-moved` instead, but only when the marked lanes App comment written
// last before the label is pr-merge's and came within PAIRED_MS of it, or
// carries pr-merge's escalation line (enable-auto-merge puts the label back
// under a standing one), so a label added for another reason is never read
// as pr-merge's. Then the newest lanes App comment carrying each of
// pr-merge's own markers (PR_MERGE_MARKERS) names, in its `at head `<sha>``,
// a head that is not the PR's current one. pr-merge then judges the new head
// and escalates again if its refusal still holds: under `merge.lane-prs:
// native` enable-auto-merge does, labeling it again only for a cause a person
// must clear. A marker whose head does not parse as 40-hex keeps the label,
// and so does any other marker, as above.
//
// Before the label comes off, the App posts one comment naming the cleared
// reason and the head; a sweep that finds that comment for this escalation
// and head only retries the removal. At most CLEARS_PER_RUN a run.
//
// Under `merge.lane-prs: native`, enable-auto-merge's own person refusal
// comment (one of personBodies, unedited) on a lanes App pull request, the
// only pr-merge escalation there, naming the current head, whose reason is
// the gate's issue-link, verifier or risk answer (READER_HOLDS), is judged
// again at that head: the gate's reader (`evidence`, as enable-auto-merge
// reads it, the room's rung cap passed as C3 so the scorer answers at the
// config's rung) runs, and the label comes off as `refusal-cleared` when
// nothing refuses, or when the answer was read whole and what refuses now
// is a lane's (verifyClears `lane`) for the same cause: for a verifier
// reason a verdict, read once the link passes, that is neither unreadable
// nor missing; for a risk reason a risk score, which the reader computes
// only once the link and verdict pass. An issue-link reason comes off only
// when nothing refuses. A person's
// refusal, an unread answer and a failed read keep it; so does a hold or
// cost path, which no reader answer clears. At most NATIVE_READS_PER_RUN
// reads a run, starting at an offset that moves with the run number
// (rotated), so labels past the cap are read on a later run.
//
// Environment:
//   GH_TOKEN             the lane App token (pull-requests and issues write)
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   TRACKER_CONFIG       the base .work-item-tracker.json, for the human-gated
//                        label (default .base/.work-item-tracker.json)
//   LANE_PRS             merge.lane-prs as resolve-config resolved it; only
//                        `native` re-judges enable-auto-merge's refusal
//   LANES_BOT_LOGIN      the lanes App bot login (default
//                        melodic-automation-lanes[bot])
//   GITHUB_API_URL
//   GITHUB_RUN_NUMBER    where the sweep starts (rotated)
//   BABYSIT_VERIFY_GH_TOKEN, BABYSIT_VERIFY_LISTING, BABYSIT_VERIFY_HEAD_REFS,
//   BABYSIT_RUN_CACHE    the gate reader's Actions token and the run's shared
//                        reads, as enable-auto-merge passes them
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { humanGatedLabelFrom } from "../pr-unblock/address-feedback.mjs";
import {
  CLEARED,
  ESCALATION,
  escalationsSince,
  foreignMarker,
  isApp,
  labelHistory,
  laneHold,
  lines,
  openReviewHold,
  PAIRED_MS,
  RESUME_KEY,
  same,
  spoken,
} from "../pr-unblock/gate-source.mjs";
import { isProtectedPath } from "../pr-unblock/thread-scope.mjs";
import { personBodies, pythonVerify, READER_HOLDS, REFUSAL_MARKER, rotated, verifyClears, verifyHold } from "./enable-auto-merge.mjs";

const DEFAULT_BOT = "melodic-automation-lanes[bot]";
const REASON = /^- Reason: `([a-z-]+)`$/m;
const clearedMarker = (reason, head) => `<!-- pr-pipeline needs-human-cleared reason=${reason} head=${head} -->`;
// babysit_merge.py's verifier-refusal escalation, reasons comment, shared-copy
// escalation and Dependabot-major escalation: the marker on the first or
// second line, the next line naming `at head `<sha>``.
const PR_MERGE_MARKERS = Object.freeze([
  "<!-- babysit-merge-verify-escalation -->",
  "<!-- babysit-merge-risk -->",
  "<!-- babysit-merge-shared-copy-escalation -->",
  "<!-- babysit-merge-dependabot-major -->",
]);
// The work-items escalation line pr-merge writes above a marker: pr-merge's
// own, so it neither unpairs the comment nor counts as another lane's marker.
const PR_MERGE_ESCALATION = "<!-- work-items:escalation lane=pr-merge kind=escalated -->";
const prMergeLine = (line) => PR_MERGE_MARKERS.includes(line) || line === PR_MERGE_ESCALATION;
const AT_HEAD = / at head `([^`]*)`/g;
const HEAD_MOVED = "head-moved";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
// The compare API lists at most 300 files, the PR files API at most 3000.
const COMPARE_CAP = 300;
const FILES_CAP = 3000;
// Each clear lets the lanes run on the PR again (judgment).
export const CLEARS_PER_RUN = 5;
// Each reader run takes up to enable-auto-merge's VERIFY_TIMEOUT_MS; the
// step's timeout-minutes (pr-merge.yml) allows this many (judgment).
export const NATIVE_READS_PER_RUN = 3;
const REFUSAL_CLEARED = "refusal-cleared";
// babysit_verify_evidence.py's verdicts and risk answer for a read that did
// not finish (UNREADABLE, MISSING, `reviews: "unreadable: …"`).
const UNREAD = Object.freeze(["verify:unreadable", "verify:missing"]);
const UNREAD_REVIEWS = /^unreadable:/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (number, error) =>
  console.log(`::error title=clear-escalations::#${number}: ${escapeCommand(error?.message ?? error)}`);

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
      : "the pull request changes nothing under .github/workflows/";
  },
});

function mergeable(pull) {
  return pull.mergeable === true && pull.mergeable_state !== "dirty" ? "GitHub reports no conflict with main" : null;
}

const keepNote = (label) => `To keep a person on it, add \`${label}\` back: a label a person adds is never removed.`;

export const clearedComment = (reason, head, why, label) =>
  reason === REFUSAL_CLEARED
    ? `${clearedMarker(reason, head)}\nThe pr-merge lane left this pull request for a person, and at \`${head}\` that no longer holds (\`${REFUSAL_CLEARED}\`): ${why}. pr-merge removed \`${label}\`, so the next scheduled run judges it again. ${keepNote(label)}`
    : reason === HEAD_MOVED
    ? `${clearedMarker(reason, head)}\nThe pr-merge lane escalated this pull request, and its head has moved (\`${HEAD_MOVED}\`): ${why}. pr-merge removed \`${label}\` so it judges \`${head}\` afresh, and escalates again if its refusal still holds. ${keepNote(label)}`
    : `${clearedMarker(reason, head)}\nThe pr-unblock lane escalated this pull request as \`${reason.replaceAll(",", "`, `")}\`, and that no longer holds at \`${head}\`: ${why}. pr-merge removed \`${label}\`, so the lanes run on it again. ${keepNote(label)}`;

// The newest lanes App comment carrying each pr-merge marker, with the head it
// names: null when that line names none, or more than one, as 40-hex.
function prMergeEscalations(appComments) {
  return PR_MERGE_MARKERS.flatMap((marker) => {
    const newest = appComments.filter((item) => lines(item.body).slice(0, 2).includes(marker)).at(-1);
    if (newest === undefined) {
      return [];
    }
    const body = lines(newest.body);
    const named = [...String(body[body.indexOf(marker) + 1] ?? "").matchAll(AT_HEAD)].map((match) => match[1]);
    return [{ marker, head: named.length === 1 && SHA.test(named[0]) ? named[0] : null }];
  });
}

// enable-auto-merge's person refusal comment, when it is the only pr-merge
// escalation in `merged`, names `head`, verifyHold wrote its reason, and
// nothing edited it since (enable-auto-merge posts a person's anew):
// { kind, reason }, kind a READER_HOLDS key.
function nativeRefusal(appComments, merged, label, head) {
  if (merged.length !== 1 || merged[0].marker !== REFUSAL_MARKER || merged[0].head !== head) {
    return null;
  }
  const newest = appComments.filter((item) => lines(item.body).slice(0, 2).includes(REFUSAL_MARKER)).at(-1);
  if (!(Date.parse(newest.updated_at) <= Date.parse(newest.created_at))) {
    return null;
  }
  const reason = lines(newest.body).slice(5, -1).join("\n");
  const kind = Object.keys(READER_HOLDS).find((key) => reason.startsWith(READER_HOLDS[key]));
  return kind !== undefined && personBodies(reason, head, label).includes(newest.body) ? { kind, reason } : null;
}

// Whether the reader's `evidence` at `head` lifts a `kind` refusal: nothing
// refuses, or the answer was read whole and what refuses is a lane's for the
// same cause. The reader reads the verdict only once the link passes, and
// the risk score only once the verdict passes too, so a refusal of either
// hides what comes after it.
function liftsRefusal(kind, evidence, head) {
  if (verifyHold(evidence, head) === null) {
    return true;
  }
  if (kind === "link" || evidence.ineligible !== null || verifyClears(evidence, head) !== "lane" || UNREAD.includes(evidence.refusal) || UNREAD_REVIEWS.test(evidence.reviews ?? "")) {
    return false;
  }
  return kind === "verdict" || evidence.refusal === null;
}

// Whether the lanes App comment written last at or before `since` that carries
// any marker other than this script's own is pr-merge's alone, and was written
// within PAIRED_MS of it (pr-merge writes its comment, then the label) or
// carries pr-merge's escalation line, under which enable-auto-merge puts a
// missing label back with no new comment. A comment's writes are its
// creation and its last edit; a tie fails closed.
function pairedWithPrMerge(appComments, since) {
  let newest = -Infinity;
  let ours = false;
  let escalated = false;
  for (const item of appComments) {
    const markers = lines(item.body).filter((line) => line.includes("<!--") && !CLEARED.test(line));
    const at = Math.max(...[item.created_at, item.updated_at].map(Date.parse).filter((time) => time <= since));
    if (markers.length === 0 || at < newest) {
      continue;
    }
    const mine = markers.some((line) => PR_MERGE_MARKERS.includes(line)) && markers.every(prMergeLine);
    ours = at > newest ? mine : ours && mine;
    escalated = at > newest ? markers.includes(PR_MERGE_ESCALATION) : escalated && markers.includes(PR_MERGE_ESCALATION);
    newest = at;
  }
  return ours && (since - newest <= PAIRED_MS || escalated);
}

// What to clear on `number`, or { reason } saying why nothing is.
async function verdict({ github, repo, number, label, bot, mainSha, lanePrs, verify, reads }) {
  const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
  const { labeled, since, lifted } = labelHistory(timeline, label);
  if (!isApp(labeled?.actor, bot)) {
    return { reason: `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App` };
  }
  // A comment's writes are its creation and its last edit; a tie, or a time
  // that does not parse, keeps the label.
  const held = openReviewHold(timeline, lifted);
  if (held !== undefined) {
    return { reason: `a review lane holds it: ${laneHold(held).slice(0, 120)}` };
  }
  // Every escalation since the label went on: a later one posts no new label
  // event, so each reason it recorded must have cleared.
  const appComments = timeline.filter((item) => item.event === "commented" && isApp(item.user, bot));
  const escalations = escalationsSince(appComments, since);
  const merged = escalations.length === 0 && pairedWithPrMerge(appComments, since) ? prMergeEscalations(appComments) : [];
  let reasons = [];
  if (merged.length === 0) {
    if (escalations.length === 0 || !(escalations[0].at - since <= PAIRED_MS)) {
      return { reason: `no pr-unblock escalation by the lanes App right after it added ${label}` };
    }
    reasons = [...new Set(escalations.map(({ body }) => REASON.exec(body.join("\n"))?.[1]))];
    const decided = reasons.find((reason) => !Object.hasOwn(CHECKS, reason ?? ""));
    if (reasons.length === 0 || decided !== undefined || reasons.includes(undefined)) {
      return { reason: `an escalation reason since the label (${decided ?? "none"}) is one a person decides` };
    }
  }
  // The App also escalates for other lanes (a work-items:escalation from
  // another lane, a pr-merge marker this script does not judge) without adding
  // the label again. Any marker on an App comment written or edited since the
  // label that is not the escalation being judged or this script's own keeps
  // it, so a marker this script does not know fails closed.
  const known = merged.length > 0 ? prMergeLine : (line) => line === ESCALATION || RESUME_KEY.test(line);
  const foreign = foreignMarker(appComments, since, known);
  if (foreign !== undefined) {
    return { reason: `a lanes App comment since ${label} went on carries another marker: ${foreign.slice(0, 120)}` };
  }
  // Only a person speaking keeps the label; an account GitHub marks Bot does
  // not. An unknown author counts as a person.
  const speaker = timeline.flatMap(spoken).find(({ user, at }) => !(at <= since) && user?.type !== "Bot");
  if (speaker !== undefined) {
    return { reason: `${speaker.user?.login ?? "an account"} commented or reviewed after ${label} went on` };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  if (pull?.state !== "open" || pull.base?.ref !== "main" || !SHA.test(String(pull.head?.sha))) {
    return { reason: "not an open pull request into main" };
  }
  if (!(pull.labels ?? []).some((item) => same(item.name, label))) {
    return { reason: `${label} is no longer on it` };
  }
  const why = [];
  if (merged.length > 0) {
    const unread = merged.find(({ head }) => head === null);
    if (unread !== undefined) {
      return { reason: `the pr-merge comment carrying ${unread.marker} names no head this script can read` };
    }
    // A refusal at an old head takes the head-moved path below.
    const native = lanePrs === "native" && isApp(pull.user, bot) ? nativeRefusal(appComments, merged, label, pull.head.sha) : null;
    if (native !== null) {
      if (reads.left <= 0) {
        return { reason: `enable-auto-merge's refusal waits: ${NATIVE_READS_PER_RUN} reader runs this run` };
      }
      reads.left -= 1;
      let evidence;
      try {
        evidence = await verify({ number, headRefOid: pull.head.sha, baseRefOid: pull.base?.sha }, "C3");
      } catch (error) {
        return { reason: `the gate's reader did not answer: ${escapeCommand(error?.message ?? error)}` };
      }
      const held = verifyHold(evidence, pull.head.sha);
      if (!liftsRefusal(native.kind, evidence, pull.head.sha)) {
        return { reason: `enable-auto-merge's refusal still needs a person at ${pull.head.sha}: ${held}` };
      }
      return cleared(timeline, bot, since, [REFUSAL_CLEARED], pull.head.sha, [
        `it refused this head (${native.reason})`,
        held === null ? "the gate now takes its issue link, verifier verdict and risk score" : `what refuses now is one the lanes clear: ${held}`,
      ]);
    }
    if (merged.some(({ head }) => head === pull.head.sha)) {
      return { reason: `a pr-merge escalation names the current head ${pull.head.sha}` };
    }
    reasons = [HEAD_MOVED];
    why.push(`its escalation names head \`${[...new Set(merged.map(({ head }) => head))].join("`, `")}\`, and the head is now \`${pull.head.sha}\``);
  } else {
    for (const reason of reasons) {
      const cleared = await CHECKS[reason]({ github, repo, pull, mainSha });
      if (cleared === null) {
        return { reason: `${reason} still holds at ${pull.head.sha}` };
      }
      why.push(cleared);
    }
  }
  return cleared(timeline, bot, since, reasons, pull.head.sha, why);
}

// The clear of `reasons` at `head`, and whether its comment is already posted.
function cleared(timeline, bot, since, reasons, head, why) {
  const recorded = reasons.join(",");
  const marker = clearedMarker(recorded, head);
  const explained = timeline.some(
    (item) => item.event === "commented" && isApp(item.user, bot) && Date.parse(item.created_at) >= since && lines(item.body)[0] === marker,
  );
  return { reason: null, recorded, head, why: why.join("; "), explained };
}

export async function main({ env = process.env, github, verify } = {}) {
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
    verify ??= pythonVerify(env);
    const reads = { left: NATIVE_READS_PER_RUN };
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
    for (const { number } of rotated(held, Number(env.GITHUB_RUN_NUMBER))) {
      if (cleared >= CLEARS_PER_RUN) {
        console.log(`clear-escalations: #${number} not checked: ${CLEARS_PER_RUN} cleared this run`);
        continue;
      }
      try {
        const result = await verdict({ github, repo, number, label, bot, mainSha, lanePrs: env.LANE_PRS, verify, reads });
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
