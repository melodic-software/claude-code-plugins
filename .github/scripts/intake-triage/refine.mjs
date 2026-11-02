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
// REFINE_MARKER; it never edits the issue body. Exact: the comment lists the drafted
// criteria as a task list. On an issue a listed human filed, admit.mjs and
// pr-verify count the newest refinement as spec while it is unedited (owner
// decision Q78); on any other issue its criteria count only once a listed
// human posts them as their own. Only when that text, with this refinement
// counted as posted, holds a task list (admit.mjs hasTrustedCriteria) does it
// ask for one more triage, which runs
// admission again: it takes the lanes App's `status: needs-decision` off, or,
// for a `status: ready` issue admission has not taken, keeps the labels, adds
// `needs-triage`, and sets the job's `redispatch` output. Otherwise the labels
// stay and the comment asks a listed human to post the confirmed criteria as
// their own `**Decision recorded.**` comment, which re-enters intake; a
// re-triage then would only refuse again. Not exact: the comment
// asks numbered questions, each with a `RECOMMENDED:` answer and its basis,
// shows the reply to copy (DECISION_REPLY) above its footer, and the issue
// keeps or gets `status: needs-decision`, in place of any `status: confirmed`
// so one status stands, which a person's
// `**Decision recorded.**` sends back through intake-reenter.yml. An exact
// output that names a duplicate or fixing change becomes not exact, with one
// question whether to close the issue. It never adds `agent-ready` or
// `needs-human`, and files no issue. It lifts no App needs-decision while the
// App's verdict comment lists a flag other than intent, or records that an
// earlier flag is unknown (admit.mjs earlierFlags); that hold stays for a
// person.
//
// An exact refinement ends its criteria with one plain External state line
// (externalLine): `none`, `iac (<owner/repo>)` or `manual (<class>: <what>)`,
// the class one of pr-pipeline.yaml's attended.classes, which --select puts
// in the context and --apply checks. Admission refuses a `manual` one with the
// `attended` label (admit.mjs externalState).
//
// A split the model judges sound names exactly the held item numbers; the
// model writes no text the lanes read. The refinement comment lists those
// items as written, quoted, as checks a person runs that the lane does not
// do, and records their numbers and the body they number (admit.mjs
// splitItemsLine, bodyVersion); then the script lifts the App's `status:
// needs-decision` and asks for triage again. The body stays as its author
// wrote it, so pr-verify still trusts it: admission and pr-verify leave those
// items out while that comment counts as spec and names the body as it is
// (admit.mjs personChecks). It splits only when admission's comment refused
// the issue for those items alone; an item's deeper-indented lines go with
// it, so every task-list line nested under a moved item must be one the lane
// cannot perform too.
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
import { isDeepStrictEqual } from "node:util";
import { appendFileSync } from "node:fs";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, GitHubError, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { ADMIT_MARKER, admissionParked, authorAdmitted, bodyVersion, CONFIRMED, decisionStays, EXTERNAL_STATE, hasTrustedCriteria, loadRules, ownedLines, REFINE_FOOTERS, REFINE_MARKER, refusalText, SPEC_COMMENTS, specOf, splitItemsLine, taskItems, unrunnableCriteria, unrunnableReason } from "./admit.mjs";
import { LANES_APP_LOGIN, MARKER } from "./apply-verdict.mjs";
import { linesDigest, renderSplitRecord, SCOPE_PREFIX, scopeTarget, SIZE_SPLIT_MARKER, SIZE_SPLIT_PENDING, SPLIT_CHILD_MARKER, splitChildHeader, splitRecord, splitSourceLine, splitTaskLines, taskText } from "./admit.mjs";
import { statusMirror } from "../../actions/resolve-config/write-status.mjs";

export { bodyVersion, REFINE_MARKER };
const TASK = "- [ ] ";
const LANE_BOT = "github-actions[bot]";
const NEEDS_DECISION = "status: needs-decision";
const READY = "status: ready";
const NEEDS_HUMAN = "needs-human";
const NEEDS_TRIAGE = "needs-triage";
const AGENT_READY = "agent-ready";
const NUMBER = /^[1-9][0-9]{0,9}$/;
const RELATIONS = new Set(["duplicate", "fixed-by", "related"]);
const EXTERNAL_KINDS = new Set(["none", "iac", "manual"]);
const EXTERNAL_NONE = Object.freeze({ state: "none", repo: "", class: "", what: "" });
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const LIMITS = { criteria: 12, dependencies: 10, related: 10, questions: 5, sources: 15, split: 12 };
const TEXT_MAX = 500;
const CANDIDATES = 10;

const labelNames = (issue) => (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// The lanes App's own refinement comment: posted by its account id, marker first.
export const isRefinement = (comment, appId) =>
  appId !== undefined && comment?.user?.id === appId && String(comment.body ?? "").startsWith(REFINE_MARKER);

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
// trusted task-list lines (admit.mjs splitTaskLines: the listed human's, then
// those of intake's refinement where admission counts it), covering each
// once, and `order`, pairs [a, b] that make part b wait on part a; parts no
// pair links run in parallel. The script files each part as a sub-issue of
// the issue, authored by the lanes App, whose body is admit.mjs
// splitChildHeader, naming the refinement when the part holds a line of it,
// and that part's lines copied as written (admission and pr-verify trust it
// under admit.mjs splitChildBody, the rule's one home), writes the order as native
// blocked-by edges, puts the issue's open blockers on the parts nothing
// precedes, moves the edges of issues the issue blocks onto the parts nothing
// follows, and lists the sub-issues in the App's SIZE_SPLIT_MARKER comment.
// No hold label and no born-triaged marker: intake triages each sub-issue.
// A sub-issue never splits again, and the issue's body is never edited.
// When the lines cannot be grouped into whole changes because each repeats
// over named targets, the model may instead return `groups`, lists of target
// names it copies from the lines (a target-subset split, admission rules'
// `size-split.on-decline: subset`): each sub-issue then holds every line and
// one admit.mjs SCOPE_PREFIX line naming its targets.

// admission-rules.json's `size-split`: {onDecline, maxParts}. `on-decline`
// is `subset` (a declined line split may split by target) or `park`;
// `max-parts` caps the sub-issues. Throws on any other shape.
export function sizeSplitSettings(rules) {
  const section = rules?.["size-split"] ?? {};
  const known = ["on-decline", "max-parts"];
  const onDecline = section["on-decline"] ?? "subset";
  const maxParts = section["max-parts"] ?? 10;
  if (typeof section !== "object" || Array.isArray(section) || !Object.keys(section).every((key) => known.includes(key)) || !["subset", "park"].includes(onDecline) || !Number.isInteger(maxParts) || maxParts < 2 || maxParts > 99) {
    throw new Error("admission-rules.json `size-split` holds only `on-decline` (subset or park) and `max-parts` (2 to 99)");
  }
  return { onDecline, maxParts };
}

// A size split's visible declines (decision on the silent park): one lanes
// App comment per reason and body version, fixed text only, no hold label.
export const SIZE_DECLINE_MARKER = "<!-- intake-triage size-split-decline -->";
const DECLINES = {
  "not-human": "a listed human did not file it, and a split copies only a listed human's text",
  "few-lines": "its trusted text holds fewer than 2 task-list lines, even with intake's refinement",
  "no-split": "no split into whole changes was found, either by task-list line or by the targets the lines name",
  "bad-split": "the proposed split of its task-list lines did not cover each line exactly once in 2 or more parts",
  "bad-subset": "the proposed target groups were not text copied from its task-list lines, each target named once and inside no other target",
  "no-type": "its Issue Type is not one admission takes, so its sub-issues would take none",
};
const declineMarker = (code) => SIZE_DECLINE_MARKER.replace(" -->", ` reason=${code} -->`);

// Posts decline `code` on the issue unless the lanes App already posted it
// for this body. The text is fixed; no model or issue text is rendered.
async function postDecline({ github, base, appId, body, code, log }) {
  const head = `${declineMarker(code)}\n${bodyVersion(body)}\n`;
  if ((await paginate(github, `${base}/comments`)).some((item) => appId !== undefined && item?.user?.id === appId && String(item.body ?? "").startsWith(head))) {
    log(`refine: ${base} already says why it is not split (${code})`);
    return;
  }
  await github("POST", `${base}/comments`, {
    body: `${head}**Not split at intake (owner Q93).** This Size Large issue stays parked at \`status: ready\`: ${DECLINES[code]}. No person is asked to act and no hold label is added. The split settings are \`size-split\` in \`.github/actions/resolve-config/admission-rules.json\`.\n\n<sub>Automated by the lanes App, once per reason and body version.</sub>`,
  });
  log(`refine: ${base} says why it is not split (${code})`);
}

// Posts the decline refine-select chose (context.size_decline) for the
// body it read; a body changed since gets nothing, as its triage reruns.
export async function applySizeDecline({ github, repository, number, appId, context, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  if (!Object.hasOwn(DECLINES, context?.size_decline) || issue.pull_request || issue.state !== "open" || String(issue.body ?? "") !== context?.issue?.body) {
    log(`refine: #${number} changed or closed since the decline was chosen; nothing written`);
    return { outcome: "skipped" };
  }
  await postDecline({ github, base, appId, body: issue.body, code: context.size_decline, log });
  return { outcome: "declined" };
}

// The split record's `items`: the digest of the lines split, and of the
// refinement they copy when they copy one, so a newer refinement with the
// same lines files no second set of sub-issues. Pure.
export const splitDigest = ({ lines, source }) => linesDigest(source === null ? lines : [...lines, splitSourceLine(source)]);

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
// listed human filed splits, since only its text, and the refinement on it,
// the sub-issues can carry (admit.mjs splitChildBody). Reads only.
async function selectSizeSplit({ github, repository, number, issue, comments, humans, appId, startedAt, splitConfig, note }) {
  if (!sizeSplitPending(comments, appId)) {
    return null;
  }
  const decline = (why) => {
    note(`#${number} stays parked for its size split: ${why}`);
    return { refine: false, reason: `parked for its size split, not split: ${why}` };
  };
  // A decline that leaves the issue parked for good: apply-refinement posts it.
  const visible = (code, why) => ({ ...decline(why), refine: true, context: { version: 1, size_decline: code, issue: { number, title: String(issue.title ?? ""), body: String(issue.body ?? ""), labels: labelNames(issue) } } });
  const lane = comments.filter((c) => c.user?.login === LANE_BOT && c.user?.type === "Bot" && String(c.body ?? "").startsWith(MARKER));
  if (lane.length !== 1 || !(Date.parse(lane[0].updated_at) >= startedAt)) {
    return decline("no single intake lane comment from this run");
  }
  if (String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER)) {
    return decline("it is a sub-issue a split filed, which never splits again");
  }
  if (!humans.has(issue.user?.id)) {
    return visible("not-human", "a listed human did not file it");
  }
  const own = ownSplit(comments, appId);
  if ((own?.record.filed.length ?? 0) > 0) {
    return decline("the lanes App already split it");
  }
  if (own === null && (issue.sub_issues_summary?.total ?? 0) > 0) {
    return decline("it already has sub-issues");
  }
  const split = splitTaskLines(await specOf(github, repository, number), humans, splitConfig().rules["task-list"], appId, () => splitConfig().webHosts);
  const { lines } = split;
  if (lines.length < 2) {
    const why = `its trusted text holds ${lines.length} task-list line(s), and a split needs at least 2`;
    // The thin refinement drafts criteria first (owner Q78); the split then
    // runs on its lines at the next triage.
    return refinedBody(comments, appId, issue.body) ? visible("few-lines", why) : { thin: `fewer than 2 trusted task-list lines for its size split: ${why}` };
  }
  return {
    refine: true,
    reason: `Size large, waiting on its split into sub-issues; ${lines.length} trusted task-list lines`,
    context: {
      version: 1,
      size_split: { items: lines.map((text, index) => ({ n: index + 1, text })), digest: splitDigest(split), max_parts: sizeSplitSettings(splitConfig().rules).maxParts },
      issue: { number, title: String(issue.title ?? ""), body: String(issue.body ?? ""), labels: labelNames(issue) },
      triage: String(lane[0].body),
    },
  };
}

// Why `output` is no partition of `count` items, or null: exactly `parts`
// and `order`; 2 to `maxParts` parts, none empty, covering items 1..count
// once each; order pairs of distinct part numbers, none repeated, with no
// cycle. Pure.
export function partitionProblem(output, count, maxParts = 10) {
  if (output === null || typeof output !== "object" || Array.isArray(output) || Object.keys(output).sort().join() !== "order,parts") {
    return "the output must hold exactly parts and order";
  }
  const { parts, order } = output;
  if (!Array.isArray(parts) || parts.length < 2 || parts.length > maxParts || parts.length > count) {
    return `parts must be a list of 2 to ${Math.min(maxParts, count)} parts`;
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
  return orderProblem(order, parts.length);
}

// Why `groups` and `order` are no target-subset split over task lines
// `lines`, or null: 2 to `maxParts` non-empty groups, each target an
// admit.mjs scopeTarget over the lines' texts after their `taskList`
// marker, named once and inside no other target (two parts would own the
// same work), every line's text holding one of the targets (none left out
// of every part), an order as partitionProblem takes it, and groups the
// split record holds: they must
// come back from renderSplitRecord through splitRecord, so the record's
// cap and its parser stay one source. Pure.
export function subsetProblem({ groups, order }, lines, maxParts, taskList) {
  const texts = lines.map((line) => taskText(line, taskList));
  if (!Array.isArray(groups) || groups.length < 2 || groups.length > maxParts) {
    return `groups must be a list of 2 to ${maxParts} groups`;
  }
  const seen = new Set();
  for (const group of groups) {
    if (!Array.isArray(group) || group.length === 0) {
      return "each group must be a non-empty list";
    }
    for (const name of group) {
      if (!scopeTarget(name, texts) || seen.has(name)) {
        return "each target must be text copied from one task-list line, named once";
      }
      seen.add(name);
    }
  }
  const names = [...seen];
  if (names.some((name) => names.some((other) => other !== name && other.includes(name)))) {
    return "no target may be text inside another target";
  }
  if (!texts.every((text) => names.some((name) => text.includes(name)))) {
    return "the targets must cover every task-list line";
  }
  const problem = orderProblem(order, groups.length);
  if (problem !== null) {
    return problem;
  }
  const every = lines.map((_, index) => index + 1);
  const record = renderSplitRecord({ items: "0".repeat(64), parts: groups.map(() => every), order, groups });
  return isDeepStrictEqual(splitRecord(`${SIZE_SPLIT_MARKER}\n${record}`)?.groups, groups) ? null : "the groups are too long for the split record";
}

// Why `order` is no acyclic list of distinct pairs over parts 1..count. Pure.
function orderProblem(order, count) {
  const parts = Array.from({ length: count });
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
  if (!authorAdmitted(issue, humans, appId)) {
    return no("the author is neither a listed human nor the lanes App");
  }
  if (labelNames(issue).includes(NEEDS_HUMAN)) {
    return no(`a person holds it (${NEEDS_HUMAN})`);
  }
  const comments = await paginate(github, `${base}/comments`);
  const sized = await selectSizeSplit({ github, repository, number, issue, comments, humans, appId, startedAt, splitConfig, note });
  if (sized !== null && sized.thin === undefined) {
    return sized;
  }
  const lane = comments.filter((c) => c.user?.login === LANE_BOT && c.user?.type === "Bot" && String(c.body ?? "").startsWith(MARKER));
  if (lane.length !== 1 || !(Date.parse(lane[0].updated_at) >= startedAt)) {
    return no("no single intake lane comment from this run");
  }
  if (refinedBody(comments, appId, issue.body)) {
    return no("the lanes App already refined this body");
  }
  const { thin, reasons } = sized?.thin ? { thin: true, reasons: [sized.thin] } : isThin({ body: issue.body, laneBody: lane[0].body });
  const admission = comments.find((comment) => appId !== undefined && comment?.user?.id === appId && String(comment.body ?? "").startsWith(ADMIT_MARKER))?.body;
  const split = thin ? null : splitOf({ body: issue.body, laneBody: lane[0].body, labels: labelNames(issue), admission, ...splitConfig() });
  if (!thin && split === null) {
    return no("not thin, and no done-when items to split off");
  }
  const stays = split === null ? null : await decisionStays(github, base, comments, appId);
  if (stays !== null) {
    return no(stays);
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
      // pr-pipeline.yaml attended.classes: the only classes a manual
      // External state may name.
      attended: { ...(splitConfig().attended ?? {}) },
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

// The model's `external`, checked: `none`; `iac` with an owner/name `repo`;
// or `manual` with a `class` of `classes` (pr-pipeline.yaml attended.classes,
// from the context) and a `what`. Throws on any other shape.
function externalOf(value, classes) {
  const keys = ["state", "repo", "class", "what"];
  if (value === null || typeof value !== "object" || Array.isArray(value) || Object.keys(value).sort().join() !== [...keys].sort().join() || !keys.every((key) => isText(value[key]))) {
    throw new Error(`\`external\` must hold exactly ${keys.join(", ")}, each a string`);
  }
  if (!EXTERNAL_KINDS.has(value.state)) {
    throw new Error(`\`external.state\` must be one of ${[...EXTERNAL_KINDS].join(", ")}`);
  }
  if (value.state === "iac" && !REPO.test(value.repo)) {
    throw new Error("an `iac` external state names its repository as owner/name");
  }
  if (value.state === "manual" && (!Object.hasOwn(classes, value.class) || value.what.trim() === "")) {
    throw new Error(`a \`manual\` external state names one of the attended classes (${Object.keys(classes).join(", ") || "none configured"}) and what the step is`);
  }
  return value;
}

// The model's output, checked; related work outside `known` (the candidate
// numbers) is dropped. `split` is the context's split, or null; `classes`,
// the context's attended classes. Throws on any other shape.
export function validateOutput(output, known, split = null, classes = {}) {
  const keys = ["exact", "outcome", "criteria", "dependencies", "related", "questions", "sources", "split", "external"];
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
  // Checked only once `exact` is final: a not-exact refinement records none,
  // so a stray value there must not stop its questions posting.
  const external = exact ? externalOf(output.external, classes) : EXTERNAL_NONE;
  return { exact, outcome: output.outcome, criteria, dependencies, related, questions, sources, split: moved, external };
}

// The External state line an exact refinement ends its criteria with: plain
// text, never a task-list line, in the fixed form admit.mjs externalState
// reads. Only `what` and `repo` are model text; the class is a configured name.
export function externalLine({ state, repo, class: kind, what }) {
  if (state === "iac") {
    return `${EXTERNAL_STATE}iac (${line(repo)})`;
  }
  return state === "manual" ? `${EXTERNAL_STATE}manual (${kind}: ${line(what)})` : `${EXTERNAL_STATE}none`;
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

// The reply a refinement that asks questions shows the owner to copy: only a
// comment whose first line is `**Decision recorded.**` counts as an answer
// (select-trusted-text's isDecisionComment), and nothing tells them so but this.
export const DECISION_REPLY = "**Decision recorded.** <answer>";

// `body` is the issue body the refinement is for (bodyVersion); a split
// adds the items it lists (splitItemsLine); `checks`, a split's items as
// written; `retriage`, whether intake triages the issue again.
export function render(output, { body, checks = [], retriage = false } = {}) {
  const parts = [REFINE_MARKER, ...(body === undefined ? [] : [bodyVersion(body)]), ...(output.split.length > 0 ? [splitItemsLine(output.split)] : []), "**Refinement.** A read-only run explored this repository, searched its issues and pull requests, and read the allowed docs to draft what follows. On an issue a listed human filed, it counts as the issue's spec once posted, while unedited; it is still model text, so check it.", ""];
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
    if (output.external) {
      parts.push(externalLine(output.external), "");
    }
  }
  section("Dependencies", output.dependencies.map((item) => `- ${line(item)}`));
  section("Related work", output.related.map((item) => `- #${item.number} (${item.relation}): ${line(item.note)}`));
  section(
    "Open questions",
    output.questions.map((item, index) => `${index + 1}. ${line(item.question)}\n   RECOMMENDED: ${line(item.recommended)} Basis: ${line(item.basis)}`),
  );
  section("Sources read", output.sources.map((item) => `- ${line(item)}`));
  if (!output.exact) {
    parts.push("To answer, post a comment that starts with this line:", "", "```", DECISION_REPLY, "```", "");
  }
  parts.push(
    !output.exact ? REFINE_FOOTERS.questions : retriage ? REFINE_FOOTERS.retriage : REFINE_FOOTERS.confirm,
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
    ? `Done-when item ${moved[0]} of the issue body needs a person: it is a check a person runs, listed below, and the lane does not do it.`
    : `Done-when items ${[...moved].sort((a, b) => a - b).join(", ")} of the issue body need a person: they are checks a person runs, listed below, and the lane does not do them.`;

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

// Sets the labels, then posts the refinement. {outcome, redispatch}.
// `context` is what the model read: an issue whose title or body changed
// since gets nothing, and is triaged again. The comment goes last because
// its marker stops a later refinement of the same body: a failure before it
// leaves no marker, so the next triage refines the issue again and finishes
// the labels. A split does the same and never edits the body: its comment
// names the body and the items a person runs (splitItemsLine), which
// admission and pr-verify read from it (admit.mjs personChecks).
// `humans` and `rules` decide whether an exact refinement asks for a
// re-triage (admit.mjs hasTrustedCriteria, over the spec with this refinement
// posted); a failed read of the spec throws before any label write.
export async function applyRefinement({ github, repository, number, appId, humans, rules, output, context, mirrorStatus = async () => {}, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const labels = labelNames(issue);
  // The Work status field mirrors the labels a branch leaves (write-status.mjs).
  const mirror = (add, remove = []) => mirrorStatus(number, { had: labels, add, remove });
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
    if (!labels.includes(NEEDS_DECISION) || (await decisionStays(github, base, comments, appId)) !== null) {
      return skip(`is no longer held by the lanes App's ${NEEDS_DECISION} alone`);
    }
    await github("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
    await removeLabel(github, base, NEEDS_DECISION);
    await mirror([NEEDS_TRIAGE], [NEEDS_DECISION]);
    await github("POST", `${base}/comments`, { body: render(output, { body: issue.body, checks: movedTexts(issue.body, rules["task-list"], output.split), retriage: true }) });
    log(`refine: #${number} split; items ${output.split.join(", ")} listed as checks a person runs, ${NEEDS_DECISION} lifted and triage asked again`);
    return { outcome: "split", redispatch: true };
  }
  const post = (retriage = false) => github("POST", `${base}/comments`, { body: render(output, { body: issue.body, retriage }) });
  // Admission reads criteria only from a listed human's text and, on an issue
  // a listed human filed, the newest unedited refinement, so a re-triage
  // without them would refuse again. It judges the spec as it will read once
  // this refinement is posted, as the newest comment: one read, before any
  // label write. Past admission's comment window the refinement is unread
  // and admission refuses, so it asks for no triage.
  const untrusted = async () => {
    const spec = await specOf(github, repository, number);
    const refinement = { body: render(output, { body: issue.body, retriage: true }), lastEditedAt: null, author: { __typename: "Bot", databaseId: appId } };
    if (spec.commentCount < SPEC_COMMENTS && hasTrustedCriteria({ ...spec, comments: [...spec.comments, refinement] }, humans, rules["task-list"], appId)) {
      return false;
    }
    await post();
    log(`refine: #${number} is exact; no text admission counts holds a task list yet, so the labels stay and no triage is asked`);
    return true;
  };
  if (!output.exact) {
    if (labels.includes(READY)) {
      await removeLabel(github, base, READY);
    }
    if (!labels.includes(NEEDS_DECISION)) {
      await github("POST", `${base}/labels`, { labels: [NEEDS_DECISION] });
    }
    // After the add, so no read sees the issue with no status: one stands.
    if (labels.includes(CONFIRMED)) {
      await removeLabel(github, base, CONFIRMED);
    }
    await mirror([NEEDS_DECISION], [READY, CONFIRMED]);
    await post();
    log(`refine: #${number} is not exact; it waits at ${NEEDS_DECISION} with recommended answers`);
    return { outcome: "needs-decision", redispatch: false };
  }
  // Admission parks a refusal no person must answer at status: confirmed
  // (admit.mjs): it resumes like the App's own needs-decision below. Only a
  // parked issue resumes here: an App refinement never lifts a person's own
  // confirmation, which intake-reenter lifts on that person's decision.
  if (admissionParked(labels, comments, appId)) {
    if (await untrusted()) {
      return { outcome: "exact", redispatch: false };
    }
    await github("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
    await removeLabel(github, base, CONFIRMED);
    await mirror([NEEDS_TRIAGE], [CONFIRMED]);
    await post(true);
    log(`refine: #${number} is exact; ${CONFIRMED} lifted and triage asked again`);
    return { outcome: "exact", redispatch: true };
  }
  // A `status: ready` issue admission has not taken (no needs-decision, no
  // agent-ready) is triaged again when the text admission counts, with this
  // refinement posted, holds criteria.
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
    await mirror([NEEDS_TRIAGE]);
    await post(true);
    log(`refine: #${number} is exact; triage asked again so admission reads the criteria`);
    return { outcome: "exact", redispatch: true };
  }
  // Only the lanes App's own needs-decision gives way, and not for a flag past
  // intent: a person's stays.
  const stays = await decisionStays(github, base, comments, appId);
  if (stays !== null) {
    await post();
    log(`refine: #${number} is exact; ${stays}, so it stays`);
    return { outcome: "exact", redispatch: false };
  }
  if (await untrusted()) {
    return { outcome: "exact", redispatch: false };
  }
  // needs-triage first: a failure between the two leaves a label a sweep picks up.
  await github("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
  await removeLabel(github, base, NEEDS_DECISION);
  await mirror([NEEDS_TRIAGE], [NEEDS_DECISION]);
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
    const what = record.groups ? `every task-list line, scoped to ${record.groups[index].map((name) => `\`${name}\``).join(", ")}` : `task-list ${items.length === 1 ? "line" : "lines"} ${items.join(", ")}`;
    return `- Part ${index + 1}: ${what}${after.length > 0 ? `, after part ${after.join(", ")}` : ""}${child === undefined ? "" : `: #${child}`}`;
  });
  return [
    SIZE_SPLIT_MARKER,
    renderSplitRecord(record),
    `**Split at intake (owner Q93).** This issue is Size Large, so its done-when is split into ${record.parts.length} sub-issues, each holding its task-list lines as written.${record.filed.length === 0 ? " Filing them now." : ""}`,
    "",
    ...rows,
    "",
    "<sub>Automated split by the lanes App. Admission waits on this issue while a sub-issue is open; work-unblock closes it as completed once every sub-issue is closed as completed by a merge or a listed human and its done-when is covered.</sub>",
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
// with REST `number` and `id`, unless the edge is there. Whether the edge
// stands: a refused edge (422) is logged and returns false, not thrown.
async function blockOn({ github, repository, issue, blocker, log }) {
  const path = `/repos/${repository}/issues/${issue.number}/dependencies/blocked_by`;
  if ((await paginate(github, path)).some((item) => item?.id === blocker.id)) {
    return true;
  }
  try {
    await github("POST", path, { issue_id: blocker.id });
    return true;
  } catch (error) {
    if (!(error instanceof GitHubError && error.status === 422)) {
      throw error;
    }
    log(`::warning title=refine::GitHub refused the edge #${issue.number} blocked by #${blocker.number}`);
    return false;
  }
}

// Files the split as the lanes App. {outcome: split | skipped, children}.
// The split record goes on the issue first, from the model's partition; a
// retry finishes that record and ignores a new partition. Each step checks
// before it writes, so a retry files, links and edges nothing twice: a part
// whose body the App already filed under the issue is reused. Each part takes
// the issue's Issue Type, which admission requires. An edge GitHub refuses
// leaves the split unfinished: what the issue blocks keeps its edge to the
// issue, and the record stays unfiled so the next triage retries. The
// record's `filed` list goes last, and is the guard that stops a later split.
export async function applySizeSplit({ github, repository, number, appId, humans, rules, webHosts, output, context, log = console.log, note = () => {} }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const settings = sizeSplitSettings(rules);
  // A skip with a decline `code` leaves the issue parked for good, so the
  // lanes App says why on it (postDecline).
  const skip = async (why, code = null) => {
    log(`refine: #${number} ${why}; nothing filed`);
    note(`#${number} stays parked for its size split: ${why}`);
    if (code !== null) {
      await postDecline({ github, base, appId, body: issue.body, code, log });
    }
    return { outcome: "skipped", children: [] };
  };
  if (issue.pull_request || issue.state !== "open" || !Number.isInteger(issue.id)) {
    return skip("is not an open issue");
  }
  if (labelNames(issue).includes(NEEDS_HUMAN)) {
    return skip(`is held by ${NEEDS_HUMAN}`);
  }
  const type = issue.type?.name;
  if (![...rules.types, ...rules["types-under-parent"], ...rules["types-parent-if-present"]].includes(type)) {
    return skip(`its Issue Type ${type ?? "none"} is not one admission takes, so its parts would take none`, "no-type");
  }
  if (String(issue.title ?? "") !== context?.issue?.title || String(issue.body ?? "") !== context?.issue?.body || String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER)) {
    return skip("changed while the model ran");
  }
  const split = splitTaskLines(await specOf(github, repository, number), humans, rules["task-list"], appId, webHosts);
  const { lines } = split;
  const digest = splitDigest(split);
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
    // A target-subset record's parts are every line once per group, so an
    // edited record can neither orphan a line nor read past its groups.
    const every = lines.map((_, index) => index + 1);
    const problem =
      record.groups === undefined
        ? partitionProblem({ parts: record.parts, order: record.order }, lines.length, settings.maxParts)
        : (subsetProblem({ groups: record.groups, order: record.order }, lines, settings.maxParts, rules["task-list"]) ?? (isDeepStrictEqual(record.parts, record.groups.map(() => every)) ? null : "parts"));
    if (record.items !== digest || problem !== null) {
      return skip("its split record no longer matches its trusted task-list lines");
    }
    log(`refine: #${number} resumes the split its record holds`);
  } else {
    const shaped = output !== null && typeof output === "object" && !Array.isArray(output);
    const { groups = [], ...byLine } = shaped ? output : {};
    const noParts = shaped && Array.isArray(output.parts) && output.parts.length === 0;
    if (noParts && Array.isArray(groups) && groups.length > 0) {
      if (settings.onDecline !== "subset") {
        return skip("the lines split only by target, and size-split on-decline is park", "no-split");
      }
      const problem = subsetProblem({ groups, order: output.order }, lines, settings.maxParts, rules["task-list"]);
      if (problem !== null) {
        return skip(`the model's target split is not one: ${problem}`, "bad-subset");
      }
      const every = lines.map((_, index) => index + 1);
      record = { items: digest, parts: groups.map(() => every), order: output.order, filed: [], groups };
    } else {
      const problem = partitionProblem(shaped ? byLine : output, lines.length, settings.maxParts);
      if (problem !== null) {
        return skip(`the model's split is not one: ${problem}`, noParts ? "no-split" : "bad-split");
      }
      record = { items: digest, parts: output.parts, order: output.order, filed: [] };
    }
    commentId = (await github("POST", `${base}/comments`, { body: renderSplit(record) }))?.id;
    if (!Number.isInteger(commentId)) {
      throw new Error("the split comment came back with no id");
    }
  }
  const filed = await filedChildren(github, repository, base, appId);
  const linked = new Set((await paginate(github, `${base}/sub_issues`)).map((item) => item?.id));
  const children = [];
  for (const [index, items] of record.parts.entries()) {
    // A part that holds a refinement line names that refinement (splitChildBody);
    // a target-subset part holds every line and its Scope line.
    const source = items.some((n) => n > split.human) ? split.source : null;
    const scope = record.groups ? `\n${SCOPE_PREFIX}${record.groups[index].join(", ")}` : "";
    const body = `${splitChildHeader(number, index + 1, record.parts.length, source, scope !== "")}\n${items.map((n) => lines[n - 1]).join("\n")}${scope}`;
    let child = filed.find((item) => item.body === body);
    if (child === undefined) {
      child = await github("POST", `/repos/${repository}/issues`, { title: `${line(issue.title).slice(0, 230)} - part ${index + 1} of ${record.parts.length}`, body, type });
      if (!Number.isInteger(child?.number) || !Number.isInteger(child?.id)) {
        throw new Error("a sub-issue came back with no number or id");
      }
      // GitHub drops a type the token may not set without an error.
      if (child.type?.name !== type) {
        log(`::warning title=refine::#${child.number} came back without Issue Type ${type}; admission refuses it until one is set`);
      }
      log(`refine: #${number} filed #${child.number} for part ${index + 1}`);
    }
    if (!linked.has(child.id)) {
      await github("POST", `${base}/sub_issues`, { sub_issue_id: child.id });
    }
    children.push(child);
  }
  let lost = 0;
  const edge = async (args) => {
    const stands = await blockOn({ github, repository, log, ...args });
    lost += stands ? 0 : 1;
    return stands;
  };
  for (const [a, b] of record.order) {
    await edge({ issue: children[b - 1], blocker: children[a - 1] });
  }
  // The issue's open blockers hold the parts nothing precedes; what waits on
  // the issue waits on the parts nothing follows instead.
  const first = children.filter((_, index) => !record.order.some(([, b]) => b === index + 1));
  const last = children.filter((_, index) => !record.order.some(([a]) => a === index + 1));
  for (const blocker of (await paginate(github, `${base}/dependencies/blocked_by`)).filter((item) => item?.state === "open" && Number.isInteger(item.id))) {
    for (const child of first) {
      await edge({ issue: child, blocker });
    }
  }
  for (const dependent of await paginate(github, `${base}/dependencies/blocking`)) {
    if (!here(dependent?.repository_url, repository) || dependent.pull_request || !Number.isInteger(dependent.number)) {
      log(`refine: #${number} leaves a blocked item outside this repository's issues as is`);
      continue;
    }
    let moved = true;
    for (const child of last) {
      moved = (await edge({ issue: dependent, blocker: child })) && moved;
    }
    // The issue's own edge goes only once every replacement stands.
    if (!moved) {
      continue;
    }
    try {
      await github("DELETE", `/repos/${repository}/issues/${dependent.number}/dependencies/blocked_by/${issue.id}`);
    } catch (error) {
      if (!(error instanceof GitHubError && error.status === 404)) {
        throw error;
      }
    }
  }
  if (lost > 0) {
    const why = `GitHub refused ${lost} blocked-by edge(s), so the split is left unfinished for the next triage to retry`;
    log(`refine: #${number} ${why}`);
    note(`#${number} stays parked for its size split: ${why}`);
    return { outcome: "incomplete", children: [] };
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
        const { attendedClassesFromBase, issueLaneWebHostsFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
        const github = createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL });
        const splitConfig = () => ({ rules: rules(), webHosts: issueLaneWebHostsFromBase(env), attended: attendedClassesFromBase(env) });
        const result = await selectRefinement({ github, repository, number, humans, appId, startedAt, splitConfig, note: summary });
        if (result.refine) {
          writeFileSync(env.CONTEXT_PATH, `${JSON.stringify(result.context, null, 2)}\n`);
        }
        console.log(`refine: #${number} ${result.refine ? "is refined" : "is not refined"} (${result.reason})`);
        writeOutputs({ refine: String(result.refine), mode: result.context?.size_split ? "size-split" : result.context?.size_decline ? "size-decline" : "refine" });
      } else if (process.argv[2] === "--apply") {
        const context = JSON.parse(readFileSync(env.CONTEXT_PATH, "utf8"));
        if (context?.issue?.number !== number) {
          throw new Error("the context is for another issue");
        }
        const github = createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL });
        // A decline refine-select chose: no model ran and no refinement exists.
        const raw = () => JSON.parse(readFileSync(env.REFINEMENT_PATH, "utf8")).output;
        if (context.size_decline) {
          await applySizeDecline({ github, repository, number, appId, context });
          writeOutputs({ redispatch: "false", children: "" });
        } else if (context.size_split) {
          // applySizeSplit checks the partition itself: a bad one leaves the issue parked, green.
          const { issueLaneWebHostsFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
          const webHosts = () => issueLaneWebHostsFromBase(env);
          const result = await applySizeSplit({ github, repository, number, appId, humans, rules: rules(), webHosts, output: raw(), context, note: summary });
          writeOutputs({ redispatch: "false", children: result.children.join(" ") });
        } else {
          const known = new Set((context.candidates ?? []).map((item) => item.number));
          const output = validateOutput(raw(), known, context.split ?? null, context.attended ?? {});
          const mirrorStatus = await statusMirror({ env, github, repository });
          const result = await applyRefinement({ github, repository, number, appId, humans, rules: rules(), output, context, mirrorStatus });
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
