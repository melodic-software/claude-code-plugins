#!/usr/bin/env node
// refine.mjs: refines a thin issue after intake triage, and splits a held
// one. No model runs here; intake-triage.yml's refine-issue job runs one
// between the two modes.
//
// `--select` (the job's read-only GITHUB_TOKEN) decides whether the issue is
// thin or splits and writes the context the model reads. Thin: the triage
// verdict's `Flags:` line names `intent` (no exact outcome), or the body has
// no unquoted task list line (no checkable criteria). Splits: not thin, the
// verdict raised no flag, the lanes App's own `status: needs-decision` holds
// it, and some of its done-when items are ones a lane run cannot perform
// (admit.mjs unrunnableCriteria, the check that held it) while at least one
// item stays once they move; the context then carries those items as `split`. It refines only an open
// issue whose author is a listed human or the lanes App, that no person holds
// (`needs-human`), whose one intake lane comment this run wrote, and that the
// lanes App has not refined before (the loop guard). The context holds the
// issue's title, body and labels, the listed humans' comments
// (select-trusted-text's author and edit rules), the triage comment, and the
// open and closed issues and merged pull requests a title search finds, as
// duplicate and already-fixed candidates; the model gets no GitHub access.
//
// `--apply` (the lanes App token, issues write) validates the model's
// structured output and posts it as a separate comment opening with
// REFINE_MARKER; only a split (below) edits the body. Exact: the comment lists the drafted
// criteria as a task list, which admit.mjs does not count for criterion 7
// until a listed human posts them as their own (owner decision Q9: pr-verify
// reads only their text). Only when that text already holds a task list
// (admit.mjs hasTrustedCriteria) does it ask for one more triage, which runs
// admission again: it takes the lanes App's `status: needs-decision` off, or,
// for a `status: ready` issue admission has not taken, keeps the labels, adds
// `needs-triage`, and sets the job's `redispatch` output. Otherwise the labels
// stay and the comment asks a listed human to post the confirmed criteria as
// their own `**Decision recorded.**` comment, which re-enters intake; a
// re-triage then would only refuse again. Not exact: the comment
// asks numbered questions, each with a `RECOMMENDED:` answer and its basis,
// and the issue keeps or gets `status: needs-decision`, which a person's
// `**Decision recorded.**` sends back through intake-reenter.yml. It never
// adds `agent-ready`, or `needs-human` to the issue it refines.
//
// A split the model judges sound names exactly the held item numbers; the
// model writes no text the lanes read. The script files one child issue,
// authored by the lanes App, labeled `needs-human` and typed CHILD_TYPE with
// the born-triaged marker last (so intake skips it), that holds those items
// as written and links back; lifts the App's
// `status: needs-decision` and asks for triage again; and rewrites the
// issue's body, replacing those items with one plain line linking the child,
// so admission reads the rest. It splits only when admission's comment
// refused the issue for those items alone; an item's deeper-indented lines
// move with it, so every task-list line nested under a moved item must be one
// the lane cannot perform too. A retry reuses a child the App already filed for the issue
// with the same items (on the issue's timeline), so it files one.
//
// Model text is data: each field is rendered on one line, with `<`, `[`, `]`,
// `(` and `)` escaped, and mentions, `#N` and `GH-N` references, `://` and
// `www.` broken (the broken `@` also stops an email autolink), so it cannot
// forge a marker, ping anyone, cross-reference an issue, add a link or
// autolink, or add a task list line outside the criteria.
//
// Environment:
//   GITHUB_TOKEN / GH_TOKEN   the job's read token (--select) or the lanes App token (--apply)
//   GITHUB_REPOSITORY, GITHUB_API_URL
//   ISSUE_NUMBER
//   STARTED_AT            when this run's first job started (--select)
//   TRUSTED_ACTORS_PATH   the default branch's trusted-actor list
//   BASE_PATH             the default branch checkout, for admission-rules.json
//                         and resolve-issue's web hosts
//   KILL_SWITCH           `proceed`, or the run stops before any API call
//   CONTEXT_PATH          where --select writes, and --apply reads, the context
//   REFINEMENT_PATH       the model's structured output (--apply)
import { readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { appendFileSync } from "node:fs";

import { BORN_TRIAGED_MARKER } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, GitHubError, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { ADMIT_MARKER, hasTrustedCriteria, loadRules, REFINE_MARKER, refusalText, specOf, taskItems, unrunnableCriteria, unrunnableReason } from "./admit.mjs";
import { LANES_APP_LOGIN, MARKER } from "./apply-verdict.mjs";
import { linesDigest, renderSplitRecord, SIZE_SPLIT_MARKER, SIZE_SPLIT_PENDING, SPLIT_CHILD_MARKER, splitChildHeader, splitRecord, trustedTaskLines } from "./admit.mjs";

export { REFINE_MARKER };
// Opens the body of the child issue a split files.
export const SPLIT_MARKER = "<!-- intake-triage split -->";
const CHILD_TYPE = "Task";
const TASK = "- [ ] ";
const LANE_BOT = "github-actions[bot]";
const NEEDS_DECISION = "status: needs-decision";
const READY = "status: ready";
const NEEDS_HUMAN = "needs-human";
const NEEDS_TRIAGE = "needs-triage";
const AGENT_READY = "agent-ready";
const NUMBER = /^[1-9][0-9]{0,9}$/;
const RELATIONS = new Set(["duplicate", "fixed-by", "related"]);
const LIMITS = { criteria: 12, dependencies: 10, related: 10, questions: 5, sources: 15, split: 12 };
const TEXT_MAX = 500;
const CANDIDATES = 10;

const labelNames = (issue) => (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// The lanes App's own refinement comment: posted by its account id, marker first.
export const isRefinement = (comment, appId) =>
  appId !== undefined && comment?.user?.id === appId && String(comment.body ?? "").startsWith(REFINE_MARKER);

// The verdict's flags, or null without exactly one unquoted Flags line.
const flagsOf = (laneBody) => {
  const flags = String(laneBody ?? "")
    .split("\n")
    .filter((line) => line.startsWith("Flags: "));
  return flags.length === 1 ? flags[0].slice(7).split(",").map((flag) => flag.trim()) : null;
};

// {thin, reasons} from the body and the triage comment's verdict lines.
export function isThin({ body, laneBody }) {
  const reasons = [];
  if (flagsOf(laneBody)?.includes("intent")) {
    reasons.push("the triage flagged intent: no exact outcome");
  }
  if (!String(body ?? "").split("\n").some((line) => line.trimStart().startsWith(TASK))) {
    reasons.push("the body has no task list: no checkable criteria");
  }
  return { thin: reasons.length > 0, reasons };
}

// The lines the moved items (1-based numbers) own: each one's own line and
// its deeper-indented lines, nested task-list lines included.
const ownedLines = (items, moved) => new Set(items.flatMap(({ line, more }, index) => (moved.includes(index + 1) ? [line, ...more] : [])));

// The split a held issue gets, or null: it is at `status: needs-decision`,
// the verdict raised no flag, some done-when items are ones a lane run cannot
// perform, every task-list line they own is one too, at least one item lies
// outside them, and `admission`, the lanes App's admission comment, refused
// it for those items and nothing else. {count, items:
// [{n, kind, text}]}, each text the item's first line, whole. Who set the
// label and wrote the comment is checked apart. Pure.
export function splitOf({ body, laneBody, labels, admission, rules, webHosts }) {
  if (!labels.includes(NEEDS_DECISION) || flagsOf(laneBody)?.join() !== "none") {
    return null;
  }
  const items = taskItems(body, rules["task-list"]);
  const unrunnable = unrunnableCriteria(body, rules["task-list"], webHosts);
  const { found } = unrunnable;
  const moved = found.map(({ n }) => n);
  const owned = ownedLines(items, moved);
  // A nested task-list line the lane can perform would move unasked; with
  // none, an item stays exactly when one is not moved.
  const carried = items.some(({ line }, index) => owned.has(line) && !moved.includes(index + 1));
  if (found.length === 0 || carried || found.length === items.length || admission !== `${ADMIT_MARKER}\n${refusalText(unrunnableReason(unrunnable))}`) {
    return null;
  }
  return { count: items.length, items: found.map(({ n, kind }) => ({ n, kind, text: items[n - 1].text })) };
}

// Who last set `status: needs-decision`, by account id.
const decisionSetter = async (github, base) =>
  (await paginate(github, `${base}/events`)).filter((event) => event?.event === "labeled" && event.label?.name === NEEDS_DECISION).at(-1)?.actor?.id;

// Up to four plain lowercase words from the title, each 4 or more letters or
// digits, so no search qualifier or operator survives.
export function searchTerms(title) {
  const words = String(title ?? "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((word) => word.length >= 4 && !["repo", "user", "author", "label", "private", "public", "type", "state", "with", "from", "that", "this"].includes(word));
  return [...new Set(words)].slice(0, 4);
}

// Only items a listed human or the lanes App opened: anyone can open an issue
// here, and its title reaches the model.
async function candidates(github, repository, issue, trusted) {
  const terms = searchTerms(issue.title);
  if (terms.length === 0) {
    return [];
  }
  const found = [];
  for (const kind of ["is:issue", "is:pr is:merged"]) {
    const q = encodeURIComponent(`repo:${repository} ${kind} ${terms.join(" OR ")}`);
    const answer = await github("GET", `/search/issues?q=${q}&per_page=${CANDIDATES}`);
    for (const item of answer?.items ?? []) {
      if (item?.number !== issue.number && Number.isInteger(item?.number) && trusted(item.user?.id) && !found.some((seen) => seen.number === item.number)) {
        found.push({
          number: item.number,
          kind: item.pull_request ? "pull request" : "issue",
          title: String(item.title ?? ""),
          state: item.state ?? null,
          state_reason: item.state_reason ?? null,
          closed_at: item.closed_at ?? null,
        });
      }
    }
  }
  return found;
}

// A size split (owner Q93): an issue admission parked at SIZE_SPLIT_PENDING
// is split into sub-issues before any run takes it. The model returns only
// item numbers: `parts`, each a list of the 1-based numbers of the issue's
// trusted task-list lines (admit.mjs trustedTaskLines), covering each once,
// and `order`, pairs [a, b] that make part b wait on part a; parts no pair
// links run in parallel. The script files each part as a sub-issue of the
// issue, authored by the lanes App, whose body is admit.mjs splitChildHeader
// and that part's lines copied as written (admission and pr-verify count it
// as the listed human's text, splitChildBody), writes the order as native
// blocked-by edges, puts the issue's open blockers on the parts nothing
// precedes, moves the edges of issues the issue blocks onto the parts nothing
// follows, and lists the sub-issues in the App's SIZE_SPLIT_MARKER comment.
// No hold label and no born-triaged marker: intake triages each sub-issue.
// A sub-issue never splits again, and the issue's body is never edited.
export const MAX_PARTS = 10;

// Whether the lanes App's admission comment waits on SIZE_SPLIT_PENDING.
export function sizeSplitPending(comments, appId) {
  const prefix = `${ADMIT_MARKER}\nNot admitted to the issue lane yet: `;
  const own = comments.find((comment) => appId !== undefined && comment?.user?.id === appId && String(comment.body ?? "").startsWith(ADMIT_MARKER));
  const body = String(own?.body ?? "");
  return body.startsWith(prefix) && body.slice(prefix.length).replace(/\.$/, "").split("; ").includes(SIZE_SPLIT_PENDING);
}

// The lanes App's split record on the issue: {comment, record}, or null.
const ownSplit = (comments, appId) => {
  const comment = comments.find((item) => appId !== undefined && item?.user?.id === appId && splitRecord(item.body) !== null);
  return comment ? { comment, record: splitRecord(comment.body) } : null;
};

// {refine, reason, context} for an issue admission parked at
// SIZE_SPLIT_PENDING, or null for any other: a parked issue is never refined
// another way, and `note(why)` records why one is not split. Only an issue a
// listed human filed splits, since only its text the sub-issues can carry
// (admit.mjs splitChildBody). Reads only.
async function selectSizeSplit({ github, repository, number, issue, comments, humans, appId, startedAt, splitConfig, note }) {
  if (!sizeSplitPending(comments, appId)) {
    return null;
  }
  const decline = (why) => {
    note(`#${number} stays parked for its size split: ${why}`);
    return { refine: false, reason: `parked for its size split, not split: ${why}` };
  };
  const lane = comments.filter((c) => c.user?.login === LANE_BOT && c.user?.type === "Bot" && String(c.body ?? "").startsWith(MARKER));
  if (lane.length !== 1 || !(Date.parse(lane[0].updated_at) >= startedAt)) {
    return decline("no single intake lane comment from this run");
  }
  if (String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER)) {
    return decline("it is a sub-issue a split filed, which never splits again");
  }
  if (!humans.has(issue.user?.id)) {
    return decline("a listed human did not file it");
  }
  const own = ownSplit(comments, appId);
  if ((own?.record.filed.length ?? 0) > 0) {
    return decline("the lanes App already split it");
  }
  if (own === null && (issue.sub_issues_summary?.total ?? 0) > 0) {
    return decline("it already has sub-issues");
  }
  const lines = trustedTaskLines(await specOf(github, repository, number), humans, splitConfig().rules["task-list"]);
  if (lines.length < 2) {
    return decline(`its trusted text holds ${lines.length} task-list line(s), and a split needs at least 2`);
  }
  return {
    refine: true,
    reason: `Size large, waiting on its split into sub-issues; ${lines.length} trusted task-list lines`,
    context: {
      version: 1,
      size_split: { items: lines.map((text, index) => ({ n: index + 1, text })), digest: linesDigest(lines), max_parts: MAX_PARTS },
      issue: { number, title: String(issue.title ?? ""), body: String(issue.body ?? ""), labels: labelNames(issue) },
      triage: String(lane[0].body),
    },
  };
}

// Why `output` is no partition of `count` items, or null: exactly `parts`
// and `order`; 2 to MAX_PARTS parts, none empty, covering items 1..count
// once each; order pairs of distinct part numbers, none repeated, with no
// cycle. Pure.
export function partitionProblem(output, count) {
  if (output === null || typeof output !== "object" || Array.isArray(output) || Object.keys(output).sort().join() !== "order,parts") {
    return "the output must hold exactly parts and order";
  }
  const { parts, order } = output;
  if (!Array.isArray(parts) || parts.length < 2 || parts.length > MAX_PARTS || parts.length > count) {
    return `parts must be a list of 2 to ${Math.min(MAX_PARTS, count)} parts`;
  }
  const seen = new Set();
  for (const part of parts) {
    if (!Array.isArray(part) || part.length === 0) {
      return "each part must be a non-empty list";
    }
    for (const n of part) {
      if (!Number.isInteger(n) || n < 1 || n > count || seen.has(n)) {
        return `each item 1 to ${count} must be in exactly one part`;
      }
      seen.add(n);
    }
  }
  if (seen.size !== count) {
    return `each item 1 to ${count} must be in exactly one part`;
  }
  const pairs = new Set();
  if (!Array.isArray(order)) {
    return "order must be a list of pairs";
  }
  for (const pair of order) {
    const valid = Array.isArray(pair) && pair.length === 2 && pair.every((p) => Number.isInteger(p) && p >= 1 && p <= parts.length) && pair[0] !== pair[1];
    if (!valid || pairs.has(pair.join(">"))) {
      return "each order pair must name two different parts, once";
    }
    pairs.add(pair.join(">"));
  }
  // Kahn's algorithm: every part leaves the queue only when the order has no cycle.
  const waits = parts.map((_, index) => order.filter(([, b]) => b === index + 1).length);
  const ready = waits.flatMap((w, index) => (w === 0 ? [index + 1] : []));
  let done = 0;
  while (ready.length > 0) {
    const a = ready.pop();
    done += 1;
    for (const [, b] of order.filter(([from]) => from === a)) {
      waits[b - 1] -= 1;
      if (waits[b - 1] === 0) {
        ready.push(b);
      }
    }
  }
  return done === parts.length ? null : "the order has a cycle";
}

// {refine, reason, context}. Reads only.
// `splitConfig` returns {rules, webHosts}, read only for an issue that is
// not thin.
// A size split comes first (selectSizeSplit), with its own guard; `note`
// records why a parked issue is not split.
export async function selectRefinement({ github, repository, number, humans, appId, startedAt, splitConfig, note = () => {} }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const no = (reason) => ({ refine: false, reason });
  if (issue.pull_request || issue.state !== "open") {
    return no("not an open issue");
  }
  if (!(humans.has(issue.user?.id) || (appId !== undefined && issue.user?.id === appId))) {
    return no("the author is neither a listed human nor the lanes App");
  }
  if (labelNames(issue).includes(NEEDS_HUMAN)) {
    return no(`a person holds it (${NEEDS_HUMAN})`);
  }
  const comments = await paginate(github, `${base}/comments`);
  const sized = await selectSizeSplit({ github, repository, number, issue, comments, humans, appId, startedAt, splitConfig, note });
  if (sized !== null) {
    return sized;
  }
  const lane = comments.filter((c) => c.user?.login === LANE_BOT && c.user?.type === "Bot" && String(c.body ?? "").startsWith(MARKER));
  if (lane.length !== 1 || !(Date.parse(lane[0].updated_at) >= startedAt)) {
    return no("no single intake lane comment from this run");
  }
  if (comments.some((comment) => isRefinement(comment, appId))) {
    return no("the lanes App already refined it");
  }
  const { thin, reasons } = isThin({ body: issue.body, laneBody: lane[0].body });
  const admission = comments.find((comment) => appId !== undefined && comment?.user?.id === appId && String(comment.body ?? "").startsWith(ADMIT_MARKER))?.body;
  const split = thin ? null : splitOf({ body: issue.body, laneBody: lane[0].body, labels: labelNames(issue), admission, ...splitConfig() });
  if (!thin && split === null) {
    return no("not thin, and no done-when items to split off");
  }
  if (split !== null && (await decisionSetter(github, base)) !== appId) {
    return no(`a person set its ${NEEDS_DECISION}`);
  }
  const { kept } = await selectTrustedIssueComments({ github, repository, issueNumber: number, ids: humans });
  return {
    refine: true,
    reason: split === null ? reasons.join("; ") : `held for done-when items ${split.items.map(({ n }) => n).join(", ")}, which a lane run cannot perform`,
    context: {
      version: 1,
      issue: { number, title: String(issue.title ?? ""), body: String(issue.body ?? ""), labels: labelNames(issue) },
      thin: reasons,
      split,
      triage: String(lane[0].body),
      comments: kept.map(({ comment }) => ({ author: comment.user?.login ?? "", created_at: comment.created_at ?? null, body: String(comment.body ?? "") })),
      candidates: await candidates(github, repository, issue, (id) => humans.has(id) || (appId !== undefined && id === appId)),
    },
  };
}

const isText = (value) => typeof value === "string";
const list = (value, key, check) => {
  if (!Array.isArray(value) || value.length > LIMITS[key] || !value.every(check)) {
    throw new Error(`\`${key}\` must be a list of at most ${LIMITS[key]}`);
  }
  return value;
};

// The model's output, checked; related work outside `known` (the candidate
// numbers) is dropped. `split` is the context's split, or null. Throws on
// any other shape.
export function validateOutput(output, known, split = null) {
  const keys = ["exact", "outcome", "criteria", "dependencies", "related", "questions", "sources", "split"];
  if (output === null || typeof output !== "object" || Array.isArray(output) || Object.keys(output).sort().join() !== [...keys].sort().join()) {
    throw new Error(`the refinement must hold exactly ${keys.join(", ")}`);
  }
  if (typeof output.exact !== "boolean" || !isText(output.outcome)) {
    throw new Error("`exact` must be a boolean and `outcome` a string");
  }
  const criteria = list(output.criteria, "criteria", (item) => isText(item) && item.trim() !== "");
  const dependencies = list(output.dependencies, "dependencies", isText);
  const sources = list(output.sources, "sources", isText);
  const related = list(
    output.related,
    "related",
    (item) => item && Number.isInteger(item.number) && RELATIONS.has(item.relation) && isText(item.note) && Object.keys(item).length === 3,
  ).filter((item) => known.has(item.number));
  const questions = list(
    output.questions,
    "questions",
    (item) => item && [item.question, item.recommended, item.basis].every((text) => isText(text) && text.trim() !== "") && Object.keys(item).length === 3,
  );
  const moved = list(output.split, "split", Number.isInteger);
  if (output.exact) {
    if ((split === null && criteria.length === 0) || questions.length > 0 || output.outcome.trim() === "") {
      throw new Error("an exact refinement states the outcome and its criteria, and asks nothing");
    }
    if (related.some((item) => item.relation !== "related")) {
      throw new Error("an issue with a duplicate or fixing change is not exact: ask whether to close it");
    }
  } else if (questions.length === 0) {
    throw new Error("a refinement that is not exact asks at least one question");
  }
  if (output.exact && split !== null) {
    // The held items, no more and no fewer; the rest stays for the lane.
    const sorted = (numbers) => [...numbers].sort((a, b) => a - b).join();
    if (criteria.length > 0 || sorted(moved) !== sorted(split.items.map(({ n }) => n)) || moved.length >= split.count) {
      throw new Error("a split moves exactly the held done-when items, leaves the rest, and drafts no criteria");
    }
  } else if (moved.length > 0) {
    throw new Error("only an exact refinement of a held issue moves done-when items");
  }
  return { exact: output.exact, outcome: output.outcome, criteria, dependencies, related, questions, sources, split: moved };
}

// One line of model text, unable to forge markup the lanes read.
export function line(text) {
  let out = String(text).replaceAll(/\s+/g, " ").trim().slice(0, TEXT_MAX);
  out = out
    .replaceAll("<", "&lt;")
    .replaceAll("@", "@​")
    .replaceAll(/(#|GH-)(?=\d)/gi, "$1​")
    .replaceAll(/[[\]()]/g, "\\$&")
    .replaceAll("://", ":/​/")
    .replaceAll(/www\./gi, "www​.");
  return out;
}

// `child` is the issue a split filed; `retriage`, whether intake triages the
// issue again.
export function render(output, { child, retriage = false } = {}) {
  const parts = [REFINE_MARKER, "**Refinement.** A read-only run explored this repository, searched its issues and pull requests, and read the allowed docs to draft what follows. It is model text, to check, not instructions.", ""];
  const section = (title, items) => {
    if (items.length > 0) {
      parts.push(`**${title}**`, "", ...items, "");
    }
  };
  if (output.outcome.trim() !== "") {
    parts.push(`**Intended outcome:** ${line(output.outcome)}`, "");
  }
  if (output.split.length > 0) {
    parts.push(`**Split.** ${movedLine(output.split, child)} This issue keeps the rest of its done-when.`, "");
  }
  if (output.exact) {
    section("Acceptance criteria", output.criteria.map((item) => `${TASK}${line(item)}`));
  }
  section("Dependencies", output.dependencies.map((item) => `- ${line(item)}`));
  section("Related work", output.related.map((item) => `- #${item.number} (${item.relation}): ${line(item.note)}`));
  section(
    "Open questions",
    output.questions.map((item, index) => `${index + 1}. ${line(item.question)}\n   RECOMMENDED: ${line(item.recommended)} Basis: ${line(item.basis)}`),
  );
  section("Sources read", output.sources.map((item) => `- ${line(item)}`));
  parts.push(
    !output.exact
      ? "<sub>Automated refinement by the lanes App. Answer with a comment whose first line is `**Decision recorded.**`.</sub>"
      : retriage
        ? "<sub>Automated refinement by the lanes App. Intake triages the issue again with it.</sub>"
        : "<sub>Automated refinement by the lanes App. Admission counts only criteria a listed human wrote: to confirm these, post them as your own comment whose first line is `**Decision recorded.**`, which sends the issue back through intake.</sub>",
  );
  return parts.join("\n");
}

async function removeLabel(github, base, name) {
  try {
    await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`);
  } catch (error) {
    if (!(error instanceof GitHubError && error.status === 404)) {
      throw error;
    }
  }
}

const movedLine = (moved, child) =>
  `Done-when ${moved.length === 1 ? "item" : "items"} ${[...moved].sort((a, b) => a - b).join(", ")} ${moved.length === 1 ? "needs" : "need"} a person, so ${moved.length === 1 ? "it moved" : "they moved"} to #${child}.`;

// The child issue's body: the moved items as written (`texts`, each an
// item's lines with its task-list prefix), mentions broken so they do not
// ping again, then the born-triaged marker, so intake skips it.
export function childBody(number, texts) {
  return [
    SPLIT_MARKER,
    `Split from #${number}: an unattended lane run cannot perform these done-when items, so a person does. #${number} keeps the rest.`,
    "",
    "## Done when",
    "",
    ...texts.map((text) => text.trimEnd().replaceAll("@", "@​")),
    "",
    BORN_TRIAGED_MARKER,
  ].join("\n");
}

// The moved items, each its first line from the task-list prefix on and its
// deeper-indented lines after it, as one text per item; an item nested under
// another moved item is already in that one's text. Pure.
export function movedTexts(body, taskList, moved) {
  const lines = String(body).split("\n");
  const items = taskItems(body, taskList);
  return moved
    .filter((n) => !moved.some((m) => m !== n && items[m - 1].more.includes(items[n - 1].line)))
    .map((n) => [lines[items[n - 1].line].trimStart(), ...items[n - 1].more.map((index) => lines[index])].join("\n"));
}

// The issue's body with the moved task-list items taken out, their
// deeper-indented lines with them: the first one's line becomes a plain list
// line linking the child, the others go. Pure.
export function splitBody(body, taskList, moved, child) {
  const gone = ownedLines(taskItems(body, taskList), moved);
  let linked = false;
  return String(body)
    .split("\n")
    .flatMap((text, index) => {
      if (!gone.has(index)) {
        return [text];
      }
      if (linked) {
        return [];
      }
      linked = true;
      return [`${text.slice(0, text.length - text.trimStart().length)}- ${movedLine(moved, child)}`];
    })
    .join("\n");
}

// Gives the child CHILD_TYPE as intake's reusable does, through GraphQL. The
// type only lets intake skip the child, so a failure is logged, not thrown.
async function setType(github, repository, nodeId, log) {
  try {
    const [owner, name] = repository.split("/");
    const types = (
      await github("POST", "/graphql", {
        query: "query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { issueTypes(first: 25) { nodes { id name isEnabled } } } }",
        variables: { owner, name },
      })
    )?.data?.repository?.issueTypes?.nodes;
    const type = (types ?? []).find((node) => node?.name === CHILD_TYPE && node.isEnabled)?.id;
    if (typeof nodeId !== "string" || typeof type !== "string") {
      throw new Error(`no ${CHILD_TYPE} type or no issue id`);
    }
    await github("POST", "/graphql", {
      query: "mutation($id: ID!, $type: ID!) { updateIssue(input: { id: $id, issueTypeId: $type }) { issue { issueType { name } } } }",
      variables: { id: nodeId, type },
    });
  } catch (error) {
    log(`::warning title=refine::the child got no ${CHILD_TYPE} type, so intake triages it (${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")})`);
  }
}

// The child the lanes App already filed for this issue with `body`, the
// items it would move now, from the issue's timeline, or undefined.
async function childOf(github, repository, base, appId, body) {
  return (await paginate(github, `${base}/timeline`))
    .map((event) => (event?.event === "cross-referenced" ? event.source?.issue : null))
    .find(
      (source) =>
        source &&
        !source.pull_request &&
        source.user?.id === appId &&
        String(source.repository_url ?? "").toLowerCase().endsWith(`/repos/${repository}`.toLowerCase()) &&
        source.body === body,
    )?.number;
}

// Sets the labels, then posts the refinement. {outcome, redispatch}.
// `context` is what the model read: an issue whose title or body changed
// since gets nothing. The comment goes last because its marker stops every
// later refinement: a failure before it leaves no marker, so the next triage
// refines the issue again and finishes the labels. A split files or finds
// the child first, then sets the labels, then rewrites the body: a failure
// before the body edit leaves the held items in place for the next triage to
// hold and split again, onto the same child.
// `humans` and `rules` decide whether an exact refinement asks for a
// re-triage (admit.mjs hasTrustedCriteria); a failed read of the spec throws
// before any label write.
export async function applyRefinement({ github, repository, number, appId, humans, rules, output, context, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const labels = labelNames(issue);
  const skip = (why) => {
    log(`refine: #${number} ${why}; nothing written`);
    return { outcome: "skipped", redispatch: false };
  };
  if (issue.pull_request || issue.state !== "open") {
    return skip("is not an open issue");
  }
  if (labels.includes(NEEDS_HUMAN)) {
    return skip(`is held by ${NEEDS_HUMAN}`);
  }
  if (String(issue.title ?? "") !== context?.issue?.title || String(issue.body ?? "") !== context?.issue?.body) {
    return skip("changed while the model ran");
  }
  if ((await paginate(github, `${base}/comments`)).some((comment) => isRefinement(comment, appId))) {
    return skip("is already refined");
  }
  if (output.split.length > 0) {
    if (!labels.includes(NEEDS_DECISION) || (await decisionSetter(github, base)) !== appId) {
      return skip(`is no longer held by the lanes App's ${NEEDS_DECISION}`);
    }
    const body = childBody(number, movedTexts(issue.body, rules["task-list"], output.split));
    let child = await childOf(github, repository, base, appId, body);
    if (child === undefined) {
      const filed = (
        await github("POST", `/repos/${repository}/issues`, {
          title: `${String(issue.title)} (checks a person runs)`.slice(0, 256),
          body,
          labels: [NEEDS_HUMAN],
        })
      );
      if (!Number.isInteger(filed?.number)) {
        throw new Error("the child issue came back with no number");
      }
      child = filed.number;
      log(`refine: #${number} filed #${child} for done-when items ${output.split.join(", ")}`);
      await setType(github, repository, filed.node_id, log);
    }
    // Read again before the labels and the body edit, so a person's edit
    // since is kept: the issue stays held, and a later split reuses the child.
    if (String((await github("GET", base))?.body ?? "") !== String(issue.body ?? "")) {
      log(`refine: #${number} changed before its body edit; #${child} filed, body left as is`);
      return { outcome: "skipped", redispatch: false, child };
    }
    await github("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
    await removeLabel(github, base, NEEDS_DECISION);
    await github("PATCH", base, { body: splitBody(issue.body, rules["task-list"], output.split, child) });
    await github("POST", `${base}/comments`, { body: render(output, { child, retriage: true }) });
    log(`refine: #${number} split; items ${output.split.join(", ")} moved to #${child}, ${NEEDS_DECISION} lifted and triage asked again`);
    return { outcome: "split", redispatch: true, child };
  }
  const post = (retriage = false) => github("POST", `${base}/comments`, { body: render(output, { retriage }) });
  // Admission reads criteria only from a listed human's text, so a re-triage
  // without them would refuse again: one read, before any label write.
  const untrusted = async () => {
    if (hasTrustedCriteria(await specOf(github, repository, number), humans, rules["task-list"])) {
      return false;
    }
    await post();
    log(`refine: #${number} is exact; no listed human's text holds a task list yet, so the labels stay and no triage is asked`);
    return true;
  };
  if (!output.exact) {
    if (labels.includes(READY)) {
      await removeLabel(github, base, READY);
    }
    if (!labels.includes(NEEDS_DECISION)) {
      await github("POST", `${base}/labels`, { labels: [NEEDS_DECISION] });
    }
    await post();
    log(`refine: #${number} is not exact; it waits at ${NEEDS_DECISION} with recommended answers`);
    return { outcome: "needs-decision", redispatch: false };
  }
  // A `status: ready` issue admission has not taken (no needs-decision, no
  // agent-ready) is triaged again when a listed human's text holds criteria.
  if (!labels.includes(NEEDS_DECISION)) {
    if (!labels.includes(READY) || labels.includes(AGENT_READY)) {
      await post();
      log(`refine: #${number} is exact; no needs-decision to lift and nothing awaits admission`);
      return { outcome: "exact", redispatch: false };
    }
    if (await untrusted()) {
      return { outcome: "exact", redispatch: false };
    }
    await github("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
    await post(true);
    log(`refine: #${number} is exact; triage asked again so admission reads the criteria`);
    return { outcome: "exact", redispatch: true };
  }
  // Only the lanes App's own needs-decision gives way: a person's stays.
  const setter = (await paginate(github, `${base}/events`)).filter((event) => event?.event === "labeled" && event.label?.name === NEEDS_DECISION).at(-1)?.actor?.id;
  if (setter !== appId) {
    await post();
    log(`refine: #${number} is exact; a person set its needs-decision, so it stays`);
    return { outcome: "exact", redispatch: false };
  }
  if (await untrusted()) {
    return { outcome: "exact", redispatch: false };
  }
  // needs-triage first: a failure between the two leaves a label a sweep picks up.
  await github("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
  await removeLabel(github, base, NEEDS_DECISION);
  await post(true);
  log(`refine: #${number} is exact; ${NEEDS_DECISION} lifted and triage asked again`);
  return { outcome: "exact", redispatch: true };
}

// The lanes App's comment on a split issue: SIZE_SPLIT_MARKER, the split
// record, and one line per part, from numbers only. Pure.
export function renderSplit(record) {
  const rows = record.parts.map((items, index) => {
    const after = record.order.filter(([, b]) => b === index + 1).map(([a]) => a);
    const child = record.filed[index];
    return `- Part ${index + 1}: task-list ${items.length === 1 ? "line" : "lines"} ${items.join(", ")}${after.length > 0 ? `, after part ${after.join(", ")}` : ""}${child === undefined ? "" : `: #${child}`}`;
  });
  return [
    SIZE_SPLIT_MARKER,
    renderSplitRecord(record),
    `**Split at intake (owner Q93).** This issue is Size Large, so its done-when is split into ${record.parts.length} sub-issues, each holding its task-list lines as written.${record.filed.length === 0 ? " Filing them now." : ""}`,
    "",
    ...rows,
    "",
    "<sub>Automated split by the lanes App. Admission waits on this issue while a sub-issue is open; work-unblock closes it as completed once every sub-issue is closed by a merge or a listed human.</sub>",
  ].join("\n");
}

const here = (url, repository) => String(url ?? "").toLowerCase().endsWith(`/repos/${repository}`.toLowerCase());

// The sub-issue bodies the lanes App already filed for issue `base`: its
// sub-issues, and issues its timeline says reference it (one filed but not
// yet linked). [{number, id, body}].
async function filedChildren(github, repository, base, appId) {
  const timeline = (await paginate(github, `${base}/timeline`)).map((event) => (event?.event === "cross-referenced" ? event.source?.issue : null));
  return [...(await paginate(github, `${base}/sub_issues`)), ...timeline].filter(
    (item) =>
      item &&
      !item.pull_request &&
      item.user?.id === appId &&
      here(item.repository_url, repository) &&
      Number.isInteger(item.number) &&
      Number.isInteger(item.id) &&
      String(item.body ?? "").startsWith(SPLIT_CHILD_MARKER),
  );
}

// Adds a native edge: `issue` is blocked by `blocker`, both issue objects
// with REST `number` and `id`, unless the edge is there. A refused edge (422)
// is logged, not thrown.
async function blockOn({ github, repository, issue, blocker, log }) {
  const path = `/repos/${repository}/issues/${issue.number}/dependencies/blocked_by`;
  if ((await paginate(github, path)).some((item) => item?.id === blocker.id)) {
    return;
  }
  try {
    await github("POST", path, { issue_id: blocker.id });
  } catch (error) {
    if (!(error instanceof GitHubError && error.status === 422)) {
      throw error;
    }
    log(`::warning title=refine::GitHub refused the edge #${issue.number} blocked by #${blocker.number}`);
  }
}

// Files the split as the lanes App. {outcome: split | skipped, children}.
// The split record goes on the issue first, from the model's partition; a
// retry finishes that record and ignores a new partition. Each step checks
// before it writes, so a retry files, links and edges nothing twice: a part
// whose body the App already filed under the issue is reused. The record's
// `filed` list goes last, and is the guard that stops a later split.
export async function applySizeSplit({ github, repository, number, appId, humans, rules, output, context, log = console.log, note = () => {} }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const skip = (why) => {
    log(`refine: #${number} ${why}; nothing written`);
    note(`#${number} stays parked for its size split: ${why}`);
    return { outcome: "skipped", children: [] };
  };
  if (issue.pull_request || issue.state !== "open" || !Number.isInteger(issue.id)) {
    return skip("is not an open issue");
  }
  if (labelNames(issue).includes(NEEDS_HUMAN)) {
    return skip(`is held by ${NEEDS_HUMAN}`);
  }
  if (String(issue.title ?? "") !== context?.issue?.title || String(issue.body ?? "") !== context?.issue?.body || String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER)) {
    return skip("changed while the model ran");
  }
  const lines = trustedTaskLines(await specOf(github, repository, number), humans, rules["task-list"]);
  const digest = linesDigest(lines);
  if (digest !== context.size_split?.digest) {
    return skip("its trusted task-list lines changed while the model ran");
  }
  const own = ownSplit(await paginate(github, `${base}/comments`), appId);
  let record;
  let commentId;
  if (own !== null) {
    record = own.record;
    commentId = own.comment.id;
    if (record.filed.length > 0) {
      return skip("is already split");
    }
    if (record.items !== digest || partitionProblem({ parts: record.parts, order: record.order }, lines.length) !== null) {
      return skip("its split record no longer matches its trusted task-list lines");
    }
    log(`refine: #${number} resumes the split its record holds`);
  } else {
    const problem = partitionProblem(output, lines.length);
    if (problem !== null) {
      return skip(`the model's split is not one: ${problem}`);
    }
    record = { items: digest, parts: output.parts, order: output.order, filed: [] };
    commentId = (await github("POST", `${base}/comments`, { body: renderSplit(record) }))?.id;
    if (!Number.isInteger(commentId)) {
      throw new Error("the split comment came back with no id");
    }
  }
  const filed = await filedChildren(github, repository, base, appId);
  const linked = new Set((await paginate(github, `${base}/sub_issues`)).map((item) => item?.id));
  const children = [];
  for (const [index, items] of record.parts.entries()) {
    const body = `${splitChildHeader(number, index + 1, record.parts.length)}\n${items.map((n) => lines[n - 1]).join("\n")}`;
    let child = filed.find((item) => item.body === body);
    if (child === undefined) {
      child = await github("POST", `/repos/${repository}/issues`, { title: `${line(issue.title).slice(0, 230)} - part ${index + 1} of ${record.parts.length}`, body });
      if (!Number.isInteger(child?.number) || !Number.isInteger(child?.id)) {
        throw new Error("a sub-issue came back with no number or id");
      }
      log(`refine: #${number} filed #${child.number} for part ${index + 1}`);
    }
    if (!linked.has(child.id)) {
      await github("POST", `${base}/sub_issues`, { sub_issue_id: child.id });
    }
    children.push(child);
  }
  for (const [a, b] of record.order) {
    await blockOn({ github, repository, issue: children[b - 1], blocker: children[a - 1], log });
  }
  // The issue's open blockers hold the parts nothing precedes; what waits on
  // the issue waits on the parts nothing follows instead.
  const first = children.filter((_, index) => !record.order.some(([, b]) => b === index + 1));
  const last = children.filter((_, index) => !record.order.some(([a]) => a === index + 1));
  for (const blocker of (await paginate(github, `${base}/dependencies/blocked_by`)).filter((item) => item?.state === "open" && Number.isInteger(item.id))) {
    for (const child of first) {
      await blockOn({ github, repository, issue: child, blocker, log });
    }
  }
  for (const dependent of await paginate(github, `${base}/dependencies/blocking`)) {
    if (!here(dependent?.repository_url, repository) || dependent.pull_request || !Number.isInteger(dependent.number)) {
      log(`refine: #${number} leaves a blocked item outside this repository's issues as is`);
      continue;
    }
    for (const child of last) {
      await blockOn({ github, repository, issue: dependent, blocker: child, log });
    }
    try {
      await github("DELETE", `/repos/${repository}/issues/${dependent.number}/dependencies/blocked_by/${issue.id}`);
    } catch (error) {
      if (!(error instanceof GitHubError && error.status === 404)) {
        throw error;
      }
    }
  }
  record.filed = children.map((child) => child.number);
  await github("PATCH", `/repos/${repository}/issues/comments/${commentId}`, { body: renderSplit(record) });
  log(`refine: #${number} split into ${record.filed.map((child) => `#${child}`).join(", ")}`);
  return { outcome: "split", children: record.filed };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const env = process.env;
  // A size split left parked says why in the step summary.
  const summary = (text) => (env.GITHUB_STEP_SUMMARY ? appendFileSync(env.GITHUB_STEP_SUMMARY, `${text}\n`) : console.log(text));
  try {
    if (env.KILL_SWITCH !== "proceed") {
      console.log("refine: the kill switch did not answer proceed; nothing read or written");
      writeOutputs({ refine: "false", redispatch: "false" });
    } else {
      if (!NUMBER.test(env.ISSUE_NUMBER ?? "")) {
        throw new Error(`ISSUE_NUMBER must be a positive number, not '${env.ISSUE_NUMBER}'`);
      }
      const number = Number(env.ISSUE_NUMBER);
      const repository = env.GITHUB_REPOSITORY;
      const { humans, logins } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
      const appId = logins.get(LANES_APP_LOGIN);
      const rules = () => loadRules(`${env.BASE_PATH}/.github/actions/resolve-config/admission-rules.json`);
      if (process.argv[2] === "--select") {
        const startedAt = Date.parse(env.STARTED_AT ?? "");
        if (!Number.isFinite(startedAt)) {
          throw new Error("STARTED_AT is not a time");
        }
        const { issueLaneWebHostsFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
        const github = createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL });
        const splitConfig = () => ({ rules: rules(), webHosts: issueLaneWebHostsFromBase(env) });
        const result = await selectRefinement({ github, repository, number, humans, appId, startedAt, splitConfig, note: summary });
        if (result.refine) {
          writeFileSync(env.CONTEXT_PATH, `${JSON.stringify(result.context, null, 2)}\n`);
        }
        console.log(`refine: #${number} ${result.refine ? "is refined" : "is not refined"} (${result.reason})`);
        writeOutputs({ refine: String(result.refine), mode: result.context?.size_split ? "size-split" : "refine" });
      } else if (process.argv[2] === "--apply") {
        const context = JSON.parse(readFileSync(env.CONTEXT_PATH, "utf8"));
        if (context?.issue?.number !== number) {
          throw new Error("the context is for another issue");
        }
        const raw = JSON.parse(readFileSync(env.REFINEMENT_PATH, "utf8")).output;
        const github = createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL });
        if (context.size_split) {
          // applySizeSplit checks the partition itself: a bad one leaves the issue parked, green.
          const result = await applySizeSplit({ github, repository, number, appId, humans, rules: rules(), output: raw, context, note: summary });
          writeOutputs({ redispatch: "false", children: result.children.join(" ") });
        } else {
          const known = new Set((context.candidates ?? []).map((item) => item.number));
          const output = validateOutput(raw, known, context.split ?? null);
          const result = await applyRefinement({ github, repository, number, appId, humans, rules: rules(), output, context });
          writeOutputs({ redispatch: String(result.redispatch), children: "" });
        }
      } else {
        throw new Error("pass --select or --apply");
      }
    }
  } catch (error) {
    console.log(`::error title=refine::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    process.exitCode = 1;
  }
}
