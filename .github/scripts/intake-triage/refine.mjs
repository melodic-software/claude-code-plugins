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
// (`needs-human`), whose one intake lane comment this run wrote, and whose
// body as it is now the lanes App has not refined (the loop guard: each
// refinement names the body it is for, by hash, so a person's edit gets one
// more). The context holds the
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
// `**Decision recorded.**` sends back through intake-reenter.yml. An exact
// output that names a duplicate or fixing change becomes not exact, with one
// question whether to close the issue. It never adds `agent-ready` or
// `needs-human`, and files no issue.
//
// A split the model judges sound names exactly the held item numbers; the
// model writes no text the lanes read. The refinement comment lists those
// items as written, quoted, as checks a person runs that the lane does not
// do; then the script lifts the App's `status: needs-decision`, asks for
// triage again, and rewrites the issue's body, replacing those items with one
// plain line pointing at that comment, so admission reads the rest. It splits
// only when admission's comment refused the issue for those items alone; an
// item's deeper-indented lines move with it, so every task-list line nested
// under a moved item must be one the lane cannot perform too. The comment
// names the body the split leaves, so a retry after a failed body edit reuses
// it.
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
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, GitHubError, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { ADMIT_MARKER, hasTrustedCriteria, loadRules, REFINE_MARKER, refusalText, specOf, taskItems, unrunnableCriteria, unrunnableReason } from "./admit.mjs";
import { LANES_APP_LOGIN, MARKER } from "./apply-verdict.mjs";

export { REFINE_MARKER };
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

// The refinement comment's second line: the issue body it is for.
export const bodyVersion = (body) => `<!-- refined body sha256:${createHash("sha256").update(String(body ?? "")).digest("hex")} -->`;

// Whether the lanes App already refined `body`.
const refinedBody = (comments, appId, body) => comments.some((comment) => isRefinement(comment, appId) && String(comment.body).split("\n")[1] === bodyVersion(body));

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

// {refine, reason, context}. Reads only.
// `splitConfig` returns {rules, webHosts}, read only for an issue that is
// not thin.
export async function selectRefinement({ github, repository, number, humans, appId, startedAt, splitConfig }) {
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
  const lane = comments.filter((c) => c.user?.login === LANE_BOT && c.user?.type === "Bot" && String(c.body ?? "").startsWith(MARKER));
  if (lane.length !== 1 || !(Date.parse(lane[0].updated_at) >= startedAt)) {
    return no("no single intake lane comment from this run");
  }
  if (refinedBody(comments, appId, issue.body)) {
    return no("the lanes App already refined this body");
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
  let criteria = list(output.criteria, "criteria", (item) => isText(item) && item.trim() !== "");
  const dependencies = list(output.dependencies, "dependencies", isText);
  const sources = list(output.sources, "sources", isText);
  const related = list(
    output.related,
    "related",
    (item) => item && Number.isInteger(item.number) && RELATIONS.has(item.relation) && isText(item.note) && Object.keys(item).length === 3,
  ).filter((item) => known.has(item.number));
  let questions = list(
    output.questions,
    "questions",
    (item) => item && [item.question, item.recommended, item.basis].every((text) => isText(text) && text.trim() !== "") && Object.keys(item).length === 3,
  );
  let moved = list(output.split, "split", Number.isInteger);
  let exact = output.exact;
  // A duplicate or fixing change makes it not exact, whatever else it holds:
  // ask whether to close the issue.
  const closing = exact ? related.filter((item) => item.relation !== "related") : [];
  if (exact && closing.length === 0) {
    if ((split === null && criteria.length === 0) || questions.length > 0 || output.outcome.trim() === "") {
      throw new Error("an exact refinement states the outcome and its criteria, and asks nothing");
    }
  } else if (exact) {
    exact = false;
    criteria = [];
    moved = [];
    const close = {
      question: `Should this issue close? The refinement found ${closing.map((item) => `#${item.number} (${item.relation})`).join(", ")}.`,
      recommended: "Close it if that change covers this issue; otherwise record what is still left to do.",
      basis: closing.map((item) => (item.note.trim() === "" ? `#${item.number}` : `#${item.number}: ${item.note}`)).join("; "),
    };
    questions = [close, ...questions].slice(0, LIMITS.questions);
  } else if (questions.length === 0) {
    throw new Error("a refinement that is not exact asks at least one question");
  }
  if (exact && split !== null) {
    // The held items, no more and no fewer; the rest stays for the lane.
    const sorted = (numbers) => [...numbers].sort((a, b) => a - b).join();
    if (criteria.length > 0 || sorted(moved) !== sorted(split.items.map(({ n }) => n)) || moved.length >= split.count) {
      throw new Error("a split moves exactly the held done-when items, leaves the rest, and drafts no criteria");
    }
  } else if (moved.length > 0) {
    throw new Error("only an exact refinement of a held issue moves done-when items");
  }
  return { exact, outcome: output.outcome, criteria, dependencies, related, questions, sources, split: moved };
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

// `body` is the issue body the refinement is for (bodyVersion); `checks`, a
// split's moved items as written; `retriage`, whether intake triages the
// issue again.
export function render(output, { body, checks = [], retriage = false } = {}) {
  const parts = [REFINE_MARKER, ...(body === undefined ? [] : [bodyVersion(body)]), "**Refinement.** A read-only run explored this repository, searched its issues and pull requests, and read the allowed docs to draft what follows. It is model text, to check, not instructions.", ""];
  const section = (title, items) => {
    if (items.length > 0) {
      parts.push(`**${title}**`, "", ...items, "");
    }
  };
  if (output.outcome.trim() !== "") {
    parts.push(`**Intended outcome:** ${line(output.outcome)}`, "");
  }
  if (output.split.length > 0) {
    parts.push(`**Split.** ${movedLine(output.split)} This issue keeps the rest of its done-when.`, "");
    section("Not done by the lane: checks a person runs", checks.map(quoted));
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

// A moved item as written, quoted so no line is a task-list line, with `<`
// escaped and mentions broken so it forges no marker and pings no one again.
const quoted = (text) =>
  text
    .trimEnd()
    .split("\n")
    .map((row) => `> ${row.replaceAll("<", "&lt;").replaceAll("@", "@​")}`)
    .join("\n");

async function removeLabel(github, base, name) {
  try {
    await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`);
  } catch (error) {
    if (!(error instanceof GitHubError && error.status === 404)) {
      throw error;
    }
  }
}

const movedLine = (moved) =>
  moved.length === 1
    ? `Done-when item ${moved[0]} needs a person, so it moved to the lanes App's refinement comment, as a check a person runs.`
    : `Done-when items ${[...moved].sort((a, b) => a - b).join(", ")} need a person, so they moved to the lanes App's refinement comment, as checks a person runs.`;

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
// line pointing at the refinement comment, the others go. Pure.
export function splitBody(body, taskList, moved) {
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
      return [`${text.slice(0, text.length - text.trimStart().length)}- ${movedLine(moved)}`];
    })
    .join("\n");
}

// Sets the labels, then posts the refinement. {outcome, redispatch}.
// `context` is what the model read: an issue whose title or body changed
// since gets nothing, and is triaged again. The comment goes last because
// its marker stops a later refinement of the same body: a failure before it
// leaves no marker, so the next triage refines the issue again and finishes
// the labels. A split posts its comment first, naming the body the split
// leaves, so the moved items are on the issue before the body loses them;
// then it sets the labels and rewrites the body. A failure before the body
// edit leaves the held items in place for the next triage to hold and split
// again, reusing that comment.
// `humans` and `rules` decide whether an exact refinement asks for a
// re-triage (admit.mjs hasTrustedCriteria); a failed read of the spec throws
// before any label write.
export async function applyRefinement({ github, repository, number, appId, humans, rules, output, context, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const labels = labelNames(issue);
  const skip = (why, redispatch = false) => {
    log(`refine: #${number} ${why}; nothing written${redispatch ? ", triage asked again" : ""}`);
    return { outcome: "skipped", redispatch };
  };
  if (issue.pull_request || issue.state !== "open") {
    return skip("is not an open issue");
  }
  if (labels.includes(NEEDS_HUMAN)) {
    return skip(`is held by ${NEEDS_HUMAN}`);
  }
  if (String(issue.title ?? "") !== context?.issue?.title || String(issue.body ?? "") !== context?.issue?.body) {
    return skip("changed while the model ran", true);
  }
  const comments = await paginate(github, `${base}/comments`);
  if (refinedBody(comments, appId, issue.body)) {
    return skip("is already refined");
  }
  if (output.split.length > 0) {
    if (!labels.includes(NEEDS_DECISION) || (await decisionSetter(github, base)) !== appId) {
      return skip(`is no longer held by the lanes App's ${NEEDS_DECISION}`);
    }
    const after = splitBody(issue.body, rules["task-list"], output.split);
    if (!refinedBody(comments, appId, after)) {
      await github("POST", `${base}/comments`, { body: render(output, { body: after, checks: movedTexts(issue.body, rules["task-list"], output.split), retriage: true }) });
    }
    // Read again before the labels and the body edit, so a person's edit
    // since is kept: the issue stays held, and its next triage reads the edit.
    if (String((await github("GET", base))?.body ?? "") !== String(issue.body ?? "")) {
      log(`refine: #${number} changed before its body edit; body and labels left as is, triage asked again`);
      return { outcome: "skipped", redispatch: true };
    }
    await github("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
    await removeLabel(github, base, NEEDS_DECISION);
    await github("PATCH", base, { body: after });
    log(`refine: #${number} split; items ${output.split.join(", ")} listed as checks a person runs, ${NEEDS_DECISION} lifted and triage asked again`);
    return { outcome: "split", redispatch: true };
  }
  const post = (retriage = false) => github("POST", `${base}/comments`, { body: render(output, { body: issue.body, retriage }) });
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

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const env = process.env;
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
        const result = await selectRefinement({ github, repository, number, humans, appId, startedAt, splitConfig });
        if (result.refine) {
          writeFileSync(env.CONTEXT_PATH, `${JSON.stringify(result.context, null, 2)}\n`);
        }
        console.log(`refine: #${number} ${result.refine ? "is refined" : "is not refined"} (${result.reason})`);
        writeOutputs({ refine: String(result.refine) });
      } else if (process.argv[2] === "--apply") {
        const context = JSON.parse(readFileSync(env.CONTEXT_PATH, "utf8"));
        if (context?.issue?.number !== number) {
          throw new Error("the context is for another issue");
        }
        const known = new Set((context.candidates ?? []).map((item) => item.number));
        const output = validateOutput(JSON.parse(readFileSync(env.REFINEMENT_PATH, "utf8")).output, known, context.split ?? null);
        const github = createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL });
        const result = await applyRefinement({ github, repository, number, appId, humans, rules: rules(), output, context });
        writeOutputs({ redispatch: String(result.redispatch) });
      } else {
        throw new Error("pass --select or --apply");
      }
    }
  } catch (error) {
    console.log(`::error title=refine::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    process.exitCode = 1;
  }
}
