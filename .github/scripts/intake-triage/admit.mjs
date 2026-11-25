import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { paginate } from "../lib/github-client.mjs";
import { appCloseKind, isTrustedClose } from "../../actions/check-trusted-trigger/close-trust.mjs";
import { carried, DECISION_LABELS, HOLD_STATES, isStatusLabel, readyWhileDeferred, StatusReadError } from "../../actions/resolve-config/read-status.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { OUTSIDE_ACTOR_LABEL, UNTRUSTED_LABEL, UNTRUSTED_LABELS } from "../pr-merge/merge-holds.mjs";
import { ADMIT_MARKER, refusalText, sayWhy as writeWhy } from "../lib/admission-comment.mjs";
import { contentHash, matchesRecord, readAdmissionRecord, writeAdmissionRecord } from "../lib/admission-record.mjs";
import { stopLine, subIssueLeftOpen } from "../lib/done-evidence.mjs";
import { ACTIONS_BOT_ID, AGENT_READY, ATTENDED, HOST_RUN, LANES_APP_LOGIN, NEEDS_DECISION, READY, REFINE_MARKER } from "../lib/lane-vocabulary.mjs";
import { PERSON_REASONS, personReasonLines } from "../lib/stop-reason.mjs";
import { SCHEDULE_MARKER } from "../recurring-schedule/file-due.mjs";
import { closingPulls } from "../work-resolve-issue/report-outcome.mjs";
import { splitParentClosed, splitParentOf } from "./size-split.mjs";
import { appRefinement, bodyVersion, countedRefinement, driftIssue, driftShape, fenceBlocks, here, INVISIBLE, LANES_APP_IDENTITY, names, OWN_AGENT_DEFAULTS, ownAgentText, PAID_EVAL, parentOf, personChecks, plainText, RECURRING, repoOf, SPEC_COMMENTS, specOf, SPLIT_CHILD_MARKER, SPLIT_ITEMS, splitChildBody, taskItems, trustedSpecTexts, unrunnableCriteria, withoutItems, writtenBy } from "./issue-spec.mjs";

export { actionsBotOnly, baseAdmissionRules, bodyVersion, countedRefinement, DRIFT_TITLE, driftIssue, driftLead, driftSpecText, EVAL_RUN, here, humanActor, issueUnrunnableRules, LANES_APP_IDENTITY, loadRules, names, OWN_AGENT_DEFAULTS, ownAgentText, ownedLines, PAID_EVAL, parentOf, personChecks, RECURRING, refinementSpec, repoOf, SPEC_COMMENTS, specOf, taskItems, taskLinesOf, trustedDriftSpec, trustedSpecTexts, trustedTaskLines, unrunnableCriteria, unrunnableRulesOf, vendoredDriftLead, vendoredDriftSpecText, vendoredRows, withoutItems } from "./issue-spec.mjs";
export { ACTIONS_BOT_ID, ADMIT_MARKER, AGENT_READY, ATTENDED, HOST_RUN, NEEDS_DECISION, READY, REFINE_MARKER, refusalText };

export const INTAKE_LANE = "intake-triage";
export const HOLD_ORDER = Object.freeze(["security", "cost", "intent", "design"]);
if (HOLD_ORDER.toSorted().join() !== PERSON_REASONS.toSorted().join()) {
  throw new Error("HOLD_ORDER must order exactly the stop-reason person reasons");
}
export const strongestReason = (codes) => HOLD_ORDER.find((code) => codes.has(code)) ?? null;
export function heldRefusalText(reasons, code) {
  const [marker, line] = personReasonLines(INTAKE_LANE, code);
  return `${refusalText(reasons)}\n\n${line}\n${marker}`;
}

export const DEFERRED = "admission-deferred";
export const REFINE_FOOTERS = {
  questions: "<sub>Automated refinement by the lanes App. Answer with a comment whose first line is `**Decision recorded.**`.</sub>",
  retriage: "<sub>Automated refinement by the lanes App. Intake triages the issue again with it.</sub>",
  confirm:
    "<sub>Automated refinement by the lanes App. Admission counts only criteria a listed human wrote: to confirm these, post them as your own comment whose first line is `**Decision recorded.**`, which sends the issue back through intake.</sub>",
};
export const VERDICT_MARKER = "<!-- intake-triage verdict -->";
export const VERDICT_CLEAR = "The latest triage verdict holds nothing: ";
export const CLEAR_READY = "the issue is at `";
export const CLEAR_ADMITTED = "admission moved the issue to `";
const JUDGED = /^<!-- intake-triage judged title_sha256:([0-9a-f]{64}) body_sha256:([0-9a-f]{64}) -->$/;
export const judgedLine = ({ title, body }) => `<!-- intake-triage judged title_sha256:${contentHash(title)} body_sha256:${contentHash(body)} -->`;
export const VERDICT_FLAGS = new Set(["intent", "security", "cost"]);
export const EARLIER = "(an earlier verdict)";
export const UNRECORDED = "no lanes App verdict comment shows whether an earlier verdict was flagged";
export const SIZE_SPLIT_PENDING = "Size large: the split into sub-issues at intake is pending (owner Q93)";
export const PATCH_SPLIT_PENDING = "its last run's patch was over the scan job's size cap (scan-refused-patch): the split into sub-issues at intake is pending (owner Q93)";
export const PATCH_SPLIT_CHILD = "its last run's patch was over the scan job's size cap (scan-refused-patch), and a size-split sub-issue never splits again (owner Q93), so a builder session takes it";
export const PATCH_DRIFT = "its last run's patch was over the scan job's size cap (scan-refused-patch), and a trusted upstream-drift issue is never split, so a builder session takes it";
export const SPLIT_PENDING = new Set([SIZE_SPLIT_PENDING, PATCH_SPLIT_PENDING]);
export const SIZE_SPLIT_DONE =
  "Size large: every sub-issue is closed, but it is still open, so an item no sub-issue covers or a sub-issue's close keeps it from closing as a finished split (owner Q93)";
export const subIssueWait = (number) => `sub-issue #${number} is open`;
export const CONFIRMED = "status: confirmed";
export const EXTERNAL_STATE = "External state: ";
const PERSON_LABELS = new Set(["needs-owner-decision", "do-not-merge"]);
export const UNTRUSTED = UNTRUSTED_LABEL;
const PARENT_HOLDS = new Set(["needs-human"]);
export const BODY_HOLD = /^[^\S\r\n]*hold:/im;

export const OWN_AGENT_SIZES = Object.freeze(["small", "medium"]);
export const SOURCE_LABEL = /^source: [^\s,][^,]*$/i;
export const NO_SOURCE = "an own-agent filing needs exactly one `source: <producer>` label to be admitted unattended, so a listed human decides it";
export const OWN_AGENT_EDITED = "its body was last edited by an account other than the own-agent identity that filed it, so it is no own-agent text and a listed human decides it";
export const OWN_AGENT_PATCH_CAP = "its last run's patch was over the scan job's size cap (scan-refused-patch), and an own-agent filing is never split automatically, so a listed human decides it";
export const SOURCE_UNREAD = "the open issues of its `source:` label were not read, so its producer's cap is unknown";
export const ownAgentSize = (size) => `an own-agent filing is admitted only at Size small or medium, and it is Size ${size}, which is never split automatically, so a listed human decides it`;
export const sourceCapWait = (label, older, cap) => `${older} older open issue(s) carry \`${label}\`, at or over that producer's cap of ${cap} (own-agents.source-cap)`;

export function ownAgentIds(rules, appId) {
  const { identities } = rules?.["own-agents"] ?? OWN_AGENT_DEFAULTS;
  return new Set(identities.map((id) => (id === LANES_APP_IDENTITY ? appId : id)).filter((id) => Number.isSafeInteger(id) && id !== ACTIONS_BOT_ID));
}

export const sourceLabels = (labels) => names(labels).filter((name) => /^source:/i.test(String(name ?? "")));

export function readSchedule(path = fileURLToPath(new URL("../../recurring-schedule.json", import.meta.url))) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

const scheduleIds = (body) => [...String(body ?? "").matchAll(SCHEDULE_MARKER)].map((match) => match[1]);

export function operatorConfirmation({ schedule, labels, body }) {
  if (!labels.includes(RECURRING)) {
    return null;
  }
  if (!Array.isArray(schedule?.items)) {
    return "it carries recurring and .github/recurring-schedule.json could not be read, so admission cannot tell whether its schedule row needs an operator's confirmation";
  }
  const ids = scheduleIds(body);
  const rows = schedule.items.filter((item) => ids.includes(item?.id));
  if (rows.length === 0) {
    return "it carries recurring and no `<!-- recurring-schedule id=<id> -->` line names a row of .github/recurring-schedule.json, so admission cannot tell whether its schedule row needs an operator's confirmation";
  }
  const row = rows.find((item) => item?.precondition?.requires_operator_confirmation === true);
  return row ? `its recurring schedule row ${row.id} needs an operator's confirmation (requires_operator_confirmation)` : null;
}

export const blockersOf = (github, base) => paginate(github, `${base}/dependencies/blocked_by`);

export async function openSubIssues(github, base, issue) {
  const { total, completed } = issue?.sub_issues_summary ?? {};
  const none = Number.isSafeInteger(total) && Number.isSafeInteger(completed) && total <= completed;
  return none ? [] : (await paginate(github, `${base}/sub_issues`)).filter((item) => item?.state !== "closed");
}

const sameRepository = (nameWithOwner, repository) => String(nameWithOwner ?? "").toLowerCase() === repository.toLowerCase();

const BLOCKER_NUMBER = /^[1-9][0-9]{0,9}$/;

export const blockerDone = (blocker, repository, trusted) =>
  blocker?.state === "closed" &&
  (blocker.pull_request
    ? here(blocker.repository_url, repository) && Boolean(blocker.pull_request.merged_at)
    : BLOCKER_NUMBER.test(String(blocker.number)) && Boolean(trusted(blocker)));

export async function stillBlocking(blockers, repository, isTrusted, elsewhere = async () => false) {
  const pending = blockers.filter((blocker) => !blockerDone(blocker, repository, () => true));
  if (pending.length > 0) {
    return pending;
  }
  const untrusted = [];
  for (const blocker of blockers) {
    if (blocker.pull_request) {
      continue;
    }
    if (!(await (here(blocker.repository_url, repository) ? isTrusted(Number(blocker.number)) : elsewhere(blocker)))) {
      untrusted.push(blocker);
    }
  }
  return untrusted;
}

export function refsNames(body, number) {
  if (!Number.isSafeInteger(number) || number < 1) {
    return false;
  }
  const line = new RegExp(String.raw`^Refs: (?:#\d+, )*#${number}(?:, #\d+)*(?: \(.*\))?$`);
  return String(body ?? "")
    .split("\n")
    .some((text) => line.test(text.trim()));
}

export function openPullsNaming(timeline, repository, number, closing = []) {
  const linked = timeline
    .map((event) => (event?.event === "cross-referenced" ? event.source?.issue : null))
    .filter((source) => source?.pull_request && source.state === "open" && here(source.repository_url, repository) && refsNames(source.body, number))
    .map((source) => source.number);
  const closes = closing.filter((node) => sameRepository(node?.repository?.nameWithOwner, repository)).map((node) => node.number);
  return [...new Set([...closes, ...linked])];
}

export function mergedRefsAfter(node, number, repository, humans, appId) {
  const at = (text) => {
    const time = Date.parse(text);
    return Number.isFinite(time) ? time : Number.NEGATIVE_INFINITY;
  };
  const decision = (comment) =>
    comment?.author?.__typename === "User" &&
    isDecisionComment(
      { comment: { user: { id: comment.author.databaseId }, body: comment.body }, lastEditedAt: comment.lastEditedAt ?? null, lastEditorId: comment.editor?.databaseId },
      humans,
    );
  const refinement = (comment) =>
    appId !== undefined && comment?.author?.__typename === "Bot" && comment.author.databaseId === appId && String(comment.body ?? "").startsWith(REFINE_MARKER);
  const since = Math.max(at(node?.createdAt), ...(node?.comments?.nodes ?? []).filter((comment) => decision(comment) || refinement(comment)).map((comment) => at(comment.createdAt)));
  const pulls = (node?.timelineItems?.nodes ?? [])
    .map((event) => event?.source)
    .filter(
      (source) =>
        Number.isSafeInteger(source?.number) &&
        source.merged === true &&
        sameRepository(source.repository?.nameWithOwner, repository) &&
        at(source.mergedAt) > since &&
        refsNames(source.body, number),
    )
    .map((source) => source.number);
  return [...new Set(pulls)].sort((a, b) => a - b);
}

const DONE_FIELDS = `fragment done on Issue {
  createdAt
  comments(last: 100) { nodes { createdAt body lastEditedAt author { ...actor } editor { ...actor } } }
  timelineItems(itemTypes: [CROSS_REFERENCED_EVENT], last: 100) { nodes { ... on CrossReferencedEvent { source { ... on PullRequest { number merged mergedAt body repository { nameWithOwner } } } } } }
}
fragment actor on Actor { __typename ... on User { databaseId } ... on Bot { databaseId } }`;
// GraphQL caps a call at 500,000 nodes: https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api#node-limit
export const DONE_BATCH = 50;

export async function mergedRefsPulls({ github, repository, numbers, humans, appId, log = console.log }) {
  const [owner, name] = repository.split("/");
  const wanted = [...new Set(numbers.map(Number).filter((n) => Number.isSafeInteger(n) && n > 0))];
  const found = new Map();
  if (wanted.length === 0) {
    return found;
  }
  const query = `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { ${wanted.map((n) => `i${n}: issue(number: ${n}) { ...done }`).join(" ")} } }\n${DONE_FIELDS}`;
  try {
    const answer = await github("POST", "/graphql", { query, variables: { owner, name } });
    const repo = answer?.data?.repository;
    if (repo === null || typeof repo !== "object") {
      throw new Error("the answer has no repository");
    }
    for (const n of wanted) {
      const pulls = mergedRefsAfter(repo[`i${n}`], n, repository, humans, appId);
      if (pulls.length > 0) {
        found.set(n, pulls);
      }
    }
  } catch (error) {
    log(`::warning title=admit::merged Refs pull requests not read (${String(error?.message ?? error).replaceAll("\n", " ")}); admitting as if none`);
    return new Map();
  }
  return found;
}

export function mergedRefsReader({ github, repository, numbers = [], humans, appId, log }) {
  const order = numbers.map(Number);
  const reads = new Map();
  return async (number) => {
    const index = order.indexOf(Number(number));
    const key = index === -1 ? `#${number}` : Math.floor(index / DONE_BATCH);
    if (!reads.has(key)) {
      const batch = index === -1 ? [Number(number)] : order.slice(key * DONE_BATCH, (key + 1) * DONE_BATCH);
      reads.set(key, mergedRefsPulls({ github, repository, numbers: batch, humans, appId, log }));
    }
    return (await reads.get(key)).get(Number(number)) ?? [];
  };
}

export const doneReason = (pulls) =>
  `merged pull request ${pulls.map((n) => `#${n}`).join(", ")} names it with \`Refs:\` after its newest decision or refinement comment, so its work may already be done: close the issue if it is, or post a comment whose first line is \`**Decision recorded.**\` saying what is left, which sends it back through intake`;

export async function openPullsFor(github, repository, number) {
  const [owner, name] = repository.split("/");
  return openPullsNaming(
    await paginate(github, `/repos/${repository}/issues/${number}/timeline`),
    repository,
    Number(number),
    await closingPulls(github, { owner, name, number: Number(number) }),
  );
}

export async function humanPullsFor(github, repository, number, humans) {
  const pulls = [];
  for (const pr of await openPullsFor(github, repository, number)) {
    const pull = await github("GET", `/repos/${repository}/pulls/${pr}`);
    if (pull?.state === "open" && humans.has(pull.user?.id)) {
      pulls.push(pull);
    }
  }
  return pulls;
}

let chargeWords;
export function chargePattern() {
  if (chargeWords === undefined) {
    const words = JSON.parse(readFileSync(new URL("../../../plugins/work-items/scripts/charge-words.json", import.meta.url), "utf8"));
    const pattern = (key, flags = "gi") => {
      if (typeof words[key] !== "string" || words[key] === "") {
        throw new Error(`plugins/work-items/scripts/charge-words.json: \`${key}\` must be a pattern`);
      }
      return new RegExp(words[key], flags);
    };
    chargeWords = { code: pattern("code"), cost: pattern("cost"), costPrivate: pattern("cost_private"), workHeadings: pattern("work_headings", "i") };
  }
  return chargeWords;
}

const withoutCode = (text, code) => String(text ?? "").replace(code, (match) => match.replace(/[^\n]/g, " "));

const chargeWordsIn = (prose, { cost, costPrivate }, isPublic) =>
  [...prose.matchAll(cost), ...(isPublic ? [] : prose.matchAll(costPrivate))].map((m) => m[0].toLowerCase());

export const chargeHits = (text, charges, isPublic = false) => [...new Set(chargeWordsIn(withoutCode(text, charges.code), charges, isPublic))];

const ATX_HEADING = /^ {0,3}(#{1,6})(?:[ \t]|$)/;

const workSections = (prose, text, workHeadings) => {
  const names = String(text ?? "").split("\n");
  const lines = [];
  let known = false;
  let level = 0;
  prose.split("\n").forEach((line, index) => {
    const depth = ATX_HEADING.exec(line.replace(INVISIBLE, "").trimEnd())?.[1].length;
    if (depth !== undefined && (level === 0 || depth <= level)) {
      const work = workHeadings.test(plainText(names[index]).replace(/^[^\p{L}\p{N}]+/u, ""));
      known ||= work;
      level = work ? depth : 0;
    }
    if (level > 0) {
      lines.push(line);
    }
  });
  return { known, lines };
};

const LOWERING =
  /\b(?:shorten\w*|reduc\w*|lower\w*|drop\w*|remov\w*|delete[sd]?|deleting|disable[sd]?|disabling|(?:cut|cuts|cutting)(?! over)|bound|bounds|bounded|bounding|trim\w*|turn(?:s|ed|ing)? off|cancel\w*|retir\w*|set(?:s|ting)? (?:an? |the )(?:[\w-]+ ){0,2}polic(?:y|ies))\b/i;
const CHARGING =
  /\b(?:buy|buys|buying|bought|purchas\w*|pay|pays|paying|add|adds|adding|added|creat\w*|provision\w*|deploy\w*|enabl\w*|turn(?:s|ed|ing)? on|rais\w*|increase[sd]?|increasing|extend\w*|lengthen\w*|upgrad\w*|take|takes|taking|mov(?:e|es|ed|ing)|switch\w*|migrat\w*|adopt\w*|subscrib\w*|needs?|requires?|uses?|using|runs?|running|bump\w*|doubl\w*|expand\w*|spin(?:s|ning)? up|spun up|allocate[sd]?|allocating|allocations?|configure[sd]?|configuring|keep|keeps|keeping|kept|sign(?:s|ed|ing)? up|opt(?:s|ed|ing)? in|set(?:s|ting)?(?! (?:an? |the )(?:[\w-]+ ){0,2}polic))\b/i;
const ADMIT_CHARGES = /\bazure\b/gi;
const ACCOUNT_CHARGES = /\b(?:aws|gcp|google cloud|openai|openrouter|bedrock)\b(?![-/](?:sdk|cli|compatible|codex)\b)/gi;
const accountsTakenOn = (clause) => (CHARGING.test(clause.replace(/[-/]/g, " ").replace(/\bdeployments?\b/gi, "")) ? [...clause.matchAll(ACCOUNT_CHARGES)].map((m) => m[0].toLowerCase()) : []);
const SAFEGUARD = /\b(?:spend(?:ing)?[- ](?:limits?|caps?)|caps?|budgets?|quotas?)\b/i;
const SPEND_GUARD = "a spend guard";
const SPEND_LIMIT = /\b(?:spend(?:ing)?|billing|costs?|budget|dollar)[- ](?:limits?|caps?|budgets?|quotas?)\b|\b(?:limits?|caps?|budgets?|quotas?) (?:on|for) (?:spend\w*|billing|costs?)\b|\$\s?\d/i;
const TOWARD = /\b(?:for|with|in favou?r of|instead of|in place of|over to)\b/i;
const clauseCharges = (clause, charges, isPublic) => [...chargeWordsIn(clause, charges, isPublic), ...[...clause.matchAll(ADMIT_CHARGES)].map((m) => m[0].toLowerCase())];
const lowersOnly = (clause, charges, isPublic) => {
  if (!LOWERING.test(clause) || CHARGING.test(clause) || SAFEGUARD.test(clause)) {
    return false;
  }
  const at = clause.search(TOWARD);
  return at < 0 || clauseCharges(clause.slice(at), charges, isPublic).length === 0;
};
const clausesOf = (text) => String(text).split(/[.;!?](?=\s|$)|\n(?=\s*(?:$|[-*+]\s|\d+[.)]\s))/);
const LIST_WORD = String.raw`(?!(?:or|and|nor)(?![\p{L}\p{N}]))[\p{L}\p{N}][\p{L}\p{N}'’-]*`;
const LIST_ITEM = String.raw`${LIST_WORD}(?:[ \t]+${LIST_WORD})?`;
const NEGATED_LIST = new RegExp(
  String.raw`^(?:[^\p{L}]|\[x\])*(?:no|without)[ \t]+(${LIST_ITEM}(?:(?:[ \t]*,[ \t]*${LIST_ITEM})*,?[ \t]+(?:or|and|nor)[ \t]+${LIST_ITEM})*)[^\p{L}\p{N}]*$`,
  "iu",
);
const negatedOnly = (clause, charges, isPublic) => {
  const list = NEGATED_LIST.exec(clause)?.[1];
  return (
    list !== undefined &&
    ![CHARGING, SAFEGUARD, SPEND_LIMIT].some((keeps) => keeps.test(clause)) &&
    list
      .split(/[ \t]*,[ \t]*(?:(?:or|and|nor)[ \t]+)?|[ \t]+(?:or|and|nor)[ \t]+/i)
      .map((item) => item.replace(/^(?:new|additional|extra)[ \t]+/i, ""))
      .every((item) => !/[ \t]/.test(item) || clauseCharges(item, charges, isPublic).join(" ") === item.toLowerCase())
  );
};

export function workCharges({ title, body }, charges, isPublic, taskList) {
  const read = (text) => withoutCode(text, charges.code);
  const prose = read(body);
  const lines = prose.split("\n");
  const items = taskItems(body, taskList).map(({ line, more }) => [line, ...more].map((index) => lines[index]).join(" "));
  const sections = workSections(prose, body, charges.workHeadings);
  const whole = !sections.known && !hasTaskLine(prose, taskList);
  const parts = [read(title), ...items, ...(whole ? [prose] : [sections.lines.join("\n")])];
  return [
    ...new Set(
      parts
        .flatMap(clausesOf)
        .filter((clause) => !lowersOnly(clause, charges, isPublic))
        .filter((clause) => !negatedOnly(clause, charges, isPublic))
        .flatMap((clause) => {
          const named = clauseCharges(clause, charges, isPublic);
          const words = named.length > 0 ? named : accountsTakenOn(clause);
          return words.length === 0 && SPEND_LIMIT.test(clause) && (LOWERING.test(clause) || CHARGING.test(clause)) ? [SPEND_GUARD] : words;
        }),
    ),
  ];
}

const tally = (words) => words.reduce((counts, word) => counts.set(word, (counts.get(word) ?? 0) + 1), new Map());
const chargeCounts = (text, charges, isPublic) => [String(text ?? ""), withoutCode(text, charges.code)].map((part) => tally(chargeWordsIn(part, charges, isPublic)));

export const chargeWordsInCode = (text, charges, isPublic) => {
  const [all, prose] = chargeCounts(text, charges, isPublic);
  return [...all].filter(([word, count]) => count > (prose.get(word) ?? 0)).map(([word]) => word);
};

export const wrappedWords = (before, after, charges, isPublic) => {
  const [allBefore, proseBefore] = chargeCounts(before, charges, isPublic);
  const [allAfter, proseAfter] = chargeCounts(after, charges, isPublic);
  return [...proseBefore].filter(([word, count]) => (proseAfter.get(word) ?? 0) < count && (allAfter.get(word) ?? 0) >= allBefore.get(word)).map(([word]) => word);
};

export const titleWraps = (title, events, charges, isPublic) => {
  const now = chargeWordsInCode(title, charges, isPublic);
  return (events ?? [])
    .filter((event) => event?.event === "renamed")
    .flatMap(({ rename, created_at: at }) => wrappedWords(rename?.from, rename?.to, charges, isPublic).filter((word) => now.includes(word)).map((word) => ({ where: "the title", word, at })));
};

export function revisionWraps(text, node, charges, isPublic) {
  const edits = node?.userContentEdits;
  if (node?.includesCreatedEdit !== true || !Array.isArray(edits?.nodes) || edits.nodes.length === 0 || typeof edits.pageInfo?.hasNextPage !== "boolean") {
    throw new Error("the body has no complete revision list");
  }
  if (edits.pageInfo.hasNextPage) {
    return [{ unreadable: "the body has more than one page of revisions" }];
  }
  if (edits.nodes.some((edit) => edit?.deletedAt != null)) {
    return [{ unreadable: "a revision of the body is deleted" }];
  }
  if (!edits.nodes.every((edit) => typeof edit?.diff === "string" && Number.isFinite(Date.parse(edit.editedAt)))) {
    throw new Error("a revision of the body has no text or edit time");
  }
  const revisions = edits.nodes.toReversed().sort((a, b) => Date.parse(a.editedAt) - Date.parse(b.editedAt));
  if (revisions.at(-1).diff !== text) {
    throw new Error("the newest revision of the body is not its current text");
  }
  const now = chargeWordsInCode(text, charges, isPublic);
  return revisions.slice(1).flatMap((revision, index) =>
    wrappedWords(revisions[index].diff, revision.diff, charges, isPublic)
      .filter((word) => now.includes(word))
      .map((word) => ({ where: "the body", word, at: revision.editedAt })),
  );
}

const EDITS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) { includesCreatedEdit userContentEdits(first: 100) { pageInfo { hasNextPage } nodes { editedAt deletedAt diff } } } }
}`;

export async function chargeEditsOf({ github, repository, number, spec, charges, public: isPublic }) {
  if (spec.lastEditedAt == null || chargeWordsInCode(spec.body, charges, isPublic).length === 0) {
    return [];
  }
  const [owner, name] = repository.split("/");
  try {
    const answer = await github("POST", "/graphql", { query: EDITS_QUERY, variables: { owner, name, number: Number(number) } });
    return revisionWraps(spec.body, answer?.data?.repository?.issue, charges, isPublic);
  } catch (error) {
    return [{ failed: String(error?.message ?? error).replaceAll("\n", " ") }];
  }
}

const chargeEditReason = ({ where, word, at, unreadable, failed }) => {
  if (word !== undefined) {
    return `an edit of ${where} at ${at} moved a charge word (${word}) from prose into code, which needs an owner decision`;
  }
  const after = failed === undefined ? "which needs an owner decision" : "which no person must answer: dispatching intake again judges it anew";
  return `a charge word in code could not be compared with its edit history (${failed ?? unreadable}), ${after}`;
};

export function unrunnableReason({ items, found }) {
  if (found.length === 0) {
    return null;
  }
  const list = found.map(({ n, kind, text }) => `item ${n} (${kind}: "${text}")`).join(", ");
  const to = found.some(({ kind }) => kind === PAID_EVAL) ? "the owner, since a paid eval can bill the owner" : `the host queue (\`${HOST_RUN}\`)`;
  const split =
    found.length === items
      ? `no done-when item is left for the lane, so it goes to ${to}`
      : `recommended split: keep the other items here as the admissible issue and move these to a child issue for ${to}`;
  return `its done-when asks for what an unattended lane run cannot perform: ${list}; ${split}`;
}

const removedByUntrusted = (events, label, trusted) => {
  const newest = (events ?? []).filter((event) => ["labeled", "unlabeled"].includes(event?.event) && event.label?.name === label).at(-1);
  return newest?.event === "unlabeled" && !trusted(newest.actor);
};

export function untrustedHold({ labels, events, humans, isApp }) {
  const removedByOther = UNTRUSTED_LABELS.some((label) => removedByUntrusted(events, label, (actor) => humans.has(actor?.id) || isApp(actor)));
  return names(labels).some((name) => UNTRUSTED_LABELS.includes(name)) || removedByOther;
}

export function authorAdmitted(issue, humans, appId) {
  const author = issue?.user?.id;
  return author !== undefined && (humans.has(author) || (Number.isInteger(appId) && author === appId));
}

export const driftIssueId = (item) => driftIssue(item)?.id ?? null;

export const driftShaped = (issue, rows) => issue?.user?.id === ACTIONS_BOT_ID && driftShape(issue.title, issue.body, rows) !== null;

export async function authorTrust(github, repository, issue, humans, appId) {
  if (authorAdmitted(issue, humans, appId)) {
    return "listed";
  }
  return driftShaped(issue) && driftIssueId(await specOf(github, repository, issue.number)) !== null ? "drift" : null;
}

export const confirmedOnly = (labels) =>
  labels.includes(CONFIRMED) && !labels.some((label) => label === AGENT_READY || (isStatusLabel(label) && label !== CONFIRMED));

export const admissionParked = (labels, comments, appId) =>
  confirmedOnly(labels) &&
  Number.isInteger(appId) &&
  comments.some((comment) => comment?.user?.id === appId && String(comment.body ?? "").startsWith(ADMIT_MARKER));

export function addedByTrusted(events, label, humans, appId) {
  const actor = (events ?? []).filter((event) => event?.event === "labeled" && event.label?.name === label).at(-1)?.actor;
  return humans.has(actor?.id) || (appId !== undefined && actor?.id === appId);
}

export const PATCH_CAP_STOP = "scan-refused-patch";
const INTAKE_OUTCOME = /^<!-- work-resolve-issue outcome=intake(?: [a-z]+=\S+)* -->$/;

export function patchCapStopped(comments, events, humans, appId) {
  const reset = Math.max(
    Number.NEGATIVE_INFINITY,
    ...(events ?? []).filter((event) => event?.event === "labeled" && event.label?.name === AGENT_READY && humans.has(event.actor?.id)).map((event) => Date.parse(event.created_at)).filter(Number.isFinite),
  );
  return (comments ?? []).some((comment) => {
    const [marker, stop] = String(comment?.body ?? "").split(/\r?\n/);
    return isAppId(comment?.user?.id, appId) && INTAKE_OUTCOME.test(marker) && String(stop ?? "").startsWith(stopLine(PATCH_CAP_STOP)) && Date.parse(comment.created_at) > reset;
  });
}

const DEFERRAL_HOLDS = ["do-not-merge", "needs-human"];
export const SECURITY_AREA = "area: security";
export const BODY_EDITED = "its body was edited after it was deferred, so the admission it was deferred from judged an older body";

export function deferralLapsed({ labels, events, editedAt, humans, appId }) {
  const lower = names(labels).map((name) => String(name).toLowerCase());
  const newestAdd = (label) => (events ?? []).filter((event) => event?.event === "labeled" && String(event.label?.name).toLowerCase() === label).at(-1);
  const deferredAt = Date.parse(newestAdd(DEFERRED)?.created_at);
  const since = (at) => !Number.isFinite(deferredAt) || !(Date.parse(at) <= deferredAt);
  const found = [];
  if (!lower.includes(READY)) {
    found.push({ reason: `it lost ${READY} while deferred`, kind: "not-ready", hold: false });
  }
  for (const label of DEFERRAL_HOLDS.filter((name) => lower.includes(name))) {
    found.push({ reason: `it carries ${label}`, kind: "held", hold: true });
  }
  if (untrustedHold({ labels, events, humans, isApp: (actor) => appId !== undefined && actor?.id === appId })) {
    found.push({ reason: `${UNTRUSTED} work needs a person`, kind: "held", hold: true });
  }
  if (lower.includes(SECURITY_AREA) && since(newestAdd(SECURITY_AREA)?.created_at)) {
    found.push({ reason: `${SECURITY_AREA} was added after it was deferred, so the admission it was deferred from did not judge it`, kind: "stale", hold: true });
  }
  if (editedAt != null && since(editedAt)) {
    found.push({ reason: BODY_EDITED, kind: "stale", hold: false });
  }
  return found;
}

export function attendedHold(events, humans) {
  return removedByUntrusted(events, ATTENDED, (actor) => humans.has(actor?.id));
}

export function externalState(spec, humans, appId) {
  const refinement = countedRefinement(spec, humans, appId);
  const text = String(refinement?.body ?? "")
    .split("\n")
    .find((row) => row.startsWith(EXTERNAL_STATE));
  const match = /^(none)$|^(iac|manual) \((.+)\)$/.exec(text?.slice(EXTERNAL_STATE.length) ?? "");
  return match ? { state: match[1] ?? match[2], detail: match[3] ?? "", at: refinement.createdAt } : null;
}

const liftedSince = (events, humans, at) =>
  (events ?? []).some(
    (event) => event?.event === "unlabeled" && event.label?.name === ATTENDED && humans.has(event.actor?.id) && Date.parse(event.created_at) > Date.parse(at),
  );

const before = (events, a, b) => {
  const [at, bt] = [Date.parse(events[a]?.created_at), Date.parse(events[b]?.created_at)];
  return Number.isFinite(at) && Number.isFinite(bt) && at !== bt ? at < bt : a < b;
};

const isLabeling = (event, kind, names) => event?.event === kind && names.includes(String(event.label?.name).toLowerCase());
const isReadyAdd = (event) => isLabeling(event, "labeled", [READY]);

export function removalStands(events, isRemoval, isMark = () => true, isReMark = isReadyAdd) {
  const removals = events.flatMap((event, index) => (isRemoval(event, index) ? [index] : []));
  if (removals.length === 0) {
    return false;
  }
  const newest = removals.reduce((a, b) => (before(events, a, b) ? b : a));
  return !events.some((event, index) => isReMark(event) && isMark(event) && before(events, newest, index));
}

const STOP_HOLDS = ["needs-human", ...DECISION_LABELS];

export function admissionSettled(labels, events, isMark, state) {
  if (state === AGENT_READY || (state == null && labels.includes(AGENT_READY))) {
    return `already ${AGENT_READY}`;
  }
  const reMark = (event) => isReadyAdd(event) || isLabeling(event, "unlabeled", STOP_HOLDS);
  if (removalStands(events, (event) => event?.event === "unlabeled" && event.label?.name === AGENT_READY, isMark, reMark)) {
    return `${AGENT_READY} was removed and ${READY} not added since`;
  }
  return null;
}

/**
 * `reported` (admissionFacts) maps a blocker the lanes App closed
 * report-delivered to {at, url, reason} only when isTrustedClose does not count
 * that close (its outcome comment predates the last reopen), so the blocker
 * still waits, but its report may answer what the issue waited for. Until a
 * verdict written after that close judges the issue against it, the wait
 * carries `retriage` and admit() sends the issue back to intake; once one has,
 * the issue's own criteria decide. `comments` (admissionFacts) carry
 * report-outcome's patch-cap stop (patchCapStopped).
 */
export function decide({ issue, verdict, rules, parent, blockers, trustedCloses, reported = new Map(), pulls = [], subIssues = [], finished = false, doneBy = [], events, comments = [], spec, schedule, humans, appId, repository, webHosts, public: isPublic = false, charges = chargePattern(), chargeEdits = [], holdLabels, fieldState, sourceOpen }) {
  const labels = names(holdLabels ?? issue.labels);
  if (!labels.includes(READY)) {
    return { verdict: "skip", reasons: [`no ${READY}`] };
  }
  const isApp = appActor(appId);
  const trustedActor = (actor) => humans.has(actor?.id) || isApp(actor);
  const settled = admissionSettled(labels, events, (event) => trustedActor(event.actor), fieldState);
  if (settled) {
    return { verdict: "skip", reasons: [settled] };
  }
  const taskList = rules["task-list"];

  const refuse = [];
  const hostWork = new Set();
  const holdCodes = new Set();
  const holdFor = (code) => holdCodes.add(code);
  const splitChild = splitChildBody(spec, humans, taskList) !== null;
  const drift = issue.user?.id === ACTIONS_BOT_ID && driftIssueId(spec) !== null;
  const unsplit = splitChild || drift;
  if (unsplit && !rules.sizes.includes("large")) {
    rules = { ...rules, sizes: [...rules.sizes, "large"] };
  }
  const ownIds = ownAgentIds(rules, appId);
  const ownAgent = !splitChild && ownIds.has(issue.user?.id) && !String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER);
  let source;
  if (!authorAdmitted(issue, humans, appId) && !drift && !ownAgent) {
    refuse.push("the author is neither a listed human nor the lanes App");
    holdFor("security");
  } else if (isAppId(issue.user?.id, appId) && !splitChild && !ownAgent) {
    refuse.push("the lanes App filed it and it is not a trusted size-split sub-issue (splitChildBody), so a listed human files it as their own");
    holdFor("security");
  } else if (ownAgent) {
    if (!ownAgentText(spec, ownIds) || spec.author.databaseId !== issue.user.id) {
      refuse.push(OWN_AGENT_EDITED);
      holdFor("security");
    }
    const sources = sourceLabels(issue.labels);
    if (sources.length === 1 && SOURCE_LABEL.test(sources[0])) {
      source = sources[0];
    } else {
      refuse.push(NO_SOURCE);
      holdFor("security");
    }
  }
  const type = issue.type?.name ?? "none";
  const underParent = rules["types-under-parent"].includes(type);
  if (!underParent && !rules.types.includes(type) && !rules["types-parent-if-present"].includes(type)) {
    refuse.push(`type ${type} is not one of ${[...rules.types, ...rules["types-under-parent"], ...rules["types-parent-if-present"]].join(", ")}`);
  } else if (underParent || (rules["types-parent-if-present"].includes(type) && parent !== null)) {
    const containerLabels = rules["parent-container-labels"] ?? [];
    const container = parent !== null && names(parent.labels).some((label) => containerLabels.includes(label));
    const held = (label) => (PARENT_HOLDS.has(label) && !container) || (DECISION_LABELS.includes(label) && parent.decisionOpen !== false);
    const parentOk = parent !== null && parent.state === "open" && humans.has(parent.user?.id) && !names(parent.holdLabels ?? parent.labels).some(held);
    if (!parentOk) {
      refuse.push(`a ${type} needs an open parent issue a listed human filed that awaits no decision`);
    }
  }
  if (verdict.untrusted || untrustedHold({ labels, events, humans, isApp })) {
    refuse.push(`${UNTRUSTED} work needs a person`);
    holdFor("security");
  }
  if (labels.includes(OUTSIDE_ACTOR_LABEL)) {
    refuse.push(`it carries ${OUTSIDE_ACTOR_LABEL}, which a person lifts`);
    holdFor("security");
  }
  const parked = [];
  const openSubs = subIssues.filter((item) => item?.state !== "closed");
  const size = verdict.dimensions?.size;
  const overCap = rules.sizes.includes(size) && patchCapStopped(comments, events, humans, appId);
  if (ownAgent && (size === "large" || (rules.sizes.includes(size) && !OWN_AGENT_SIZES.includes(size)))) {
    refuse.push(ownAgentSize(size));
    holdFor("intent");
  } else if (ownAgent && overCap) {
    refuse.push(OWN_AGENT_PATCH_CAP);
    holdFor("intent");
  } else if ((size === "large" || overCap) && !rules.sizes.includes("large")) {
    if (!((issue.sub_issues_summary?.total ?? 0) > 0)) {
      parked.push(size === "large" ? SIZE_SPLIT_PENDING : PATCH_SPLIT_PENDING);
    } else if (openSubs.length === 0 && !finished) {
      refuse.push(SIZE_SPLIT_DONE);
    }
  } else if (overCap && unsplit) {
    const reason = splitChild ? PATCH_SPLIT_CHILD : PATCH_DRIFT;
    refuse.push(reason);
    hostWork.add(reason);
  } else if (!rules.sizes.includes(size)) {
    refuse.push(`Size ${size} is not one of ${rules.sizes.join(", ")}`);
  }
  if (!rules.uncertainty.includes(verdict.dimensions?.uncertainty)) {
    refuse.push(`Uncertainty ${verdict.dimensions?.uncertainty} is not one of ${rules.uncertainty.join(", ")}`);
  }
  const unset = ["size", "uncertainty"].filter((name) => verdict.dimensions?.[name] === "unset");
  if ((spec?.commentCount ?? 0) > (spec?.comments?.length ?? 0)) {
    refuse.push(`it has ${spec.commentCount} comments, more than the ${SPEC_COMMENTS} pr-verify reads, so pr-verify cannot verify a pull request for it`);
  }
  const ownSpec = ownAgent ? ownIds : undefined;
  const texts = trustedSpecTexts(spec, humans, appId, taskList, ownSpec);
  const moved = personChecks(spec, humans, appId, taskList, webHosts);
  if (moved.length > 0) {
    texts[0] = withoutItems(texts[0], taskList, moved);
  }
  if (!hasTrustedCriteria(spec, humans, taskList, appId, ownSpec)) {
    refuse.push(noTrustedSpec(taskList));
  }
  const criteria = unrunnableCriteria(texts.join("\n"), taskList, webHosts);
  const unrunnable = unrunnableReason(criteria);
  const paid = criteria.found.some(({ kind }) => kind === PAID_EVAL);
  const queued = labels.includes(HOST_RUN) && addedByTrusted(events, HOST_RUN, humans, appId);
  const queue = unrunnable !== null && !queued && !paid;
  const hostRun = queue && criteria.found.length === criteria.items;
  const split = queue && !hostRun;
  if (unrunnable) {
    refuse.push(unrunnable);
    if (paid) holdFor("cost");
    if (hostRun) hostWork.add(unrunnable);
  }
  const charged = workCharges(issue, charges, isPublic, taskList);
  if (charged.length > 0) {
    refuse.push(`its title or stated work names a charge (${charged.join(", ")}), which needs an owner decision`);
    holdFor("cost");
  }
  for (const edit of [...titleWraps(issue.title, events, charges, isPublic), ...chargeEdits]) {
    refuse.push(chargeEditReason(edit));
    if (edit.failed === undefined) holdFor("cost");
  }
  if (BODY_HOLD.test(String(issue.body ?? ""))) {
    refuse.push("a line of its body opens with `Hold:`, a person's hold; removing that line lifts it");
    holdFor("intent");
  }
  if (verdict.writtenAt !== undefined) {
    const judged = Date.parse(verdict.writtenAt);
    const edited = spec?.lastEditedAt == null ? null : Date.parse(spec.lastEditedAt);
    if (!Number.isFinite(judged) || (edited !== null && !(edited <= judged))) {
      refuse.push("its body was edited after the triage verdict, which judged the body as it stood before");
    }
  }
  let attended = false;
  if (!labels.includes(ATTENDED) && attendedHold(events, humans)) {
    refuse.push(`the newest removal of ${ATTENDED} was not a listed human's, so its hold stands`);
  }
  const external = externalState(spec, humans, appId);
  if (external?.state === "manual" && !labels.includes(ATTENDED) && !liftedSince(events, humans, external.at)) {
    refuse.push(`its refinement records External state: manual (${external.detail}), a step that needs the owner present (${ATTENDED})`);
    attended = true;
  }
  for (const label of rules["refuse-labels"]) {
    if (labels.includes(label)) {
      refuse.push(`it carries ${label}`);
      if (PERSON_LABELS.has(label)) holdFor("intent");
    }
  }
  if (verdict.writtenAt === undefined && labels.includes(DEFERRED)) {
    for (const lapsed of deferralLapsed({ labels, events, editedAt: spec?.lastEditedAt, humans, appId })) {
      if (!refuse.includes(lapsed.reason)) {
        refuse.push(lapsed.reason);
      }
      if (lapsed.hold) holdFor(lapsed.reason.startsWith(UNTRUSTED) || lapsed.reason.startsWith(SECURITY_AREA) ? "security" : "intent");
    }
  }
  const confirm = operatorConfirmation({ schedule, labels, body: issue.body });
  if (confirm) {
    refuse.push(confirm);
  }
  if (doneBy.length > 0 && !finished) {
    refuse.push(doneReason(doneBy));
  }
  const hold = holdCodes.size > 0;
  const wait = [];
  const retriage = [];
  const after = Math.max(judgedSince(events, trustedActor), Date.parse(verdict.writtenAt) || Number.NEGATIVE_INFINITY);
  for (const blocker of blockers) {
    if (!blockerDone(blocker, repository, (b) => trustedCloses.has(blockerKey(b, repository)))) {
      const name = here(blocker.repository_url, repository) ? `#${blocker.number}` : blockerKey(blocker, repository);
      const report = reported.get(blockerKey(blocker, repository));
      const closed = Date.parse(report?.at);
      if (reportCleared(report, after)) {
        continue;
      }
      if (report && Number.isFinite(closed)) {
        retriage.push({ number: blocker.number, url: report.url, reason: report.reason });
        wait.push(`blocker ${name} was closed by the lanes App as report-delivered, which is no completed work, so intake triages this issue again against that report`);
      } else {
        wait.push(`blocker ${name} is not closed by a listed human or a merge`);
      }
    }
  }
  for (const pull of pulls) {
    wait.push(`open pull request #${pull} is for it`);
  }
  if (source !== undefined) {
    const cap = (rules["own-agents"] ?? OWN_AGENT_DEFAULTS)["source-cap"];
    const older = Array.isArray(sourceOpen) ? sourceOpen.filter((n) => n < Number(issue.number)).length : null;
    if (older === null) {
      wait.push(SOURCE_UNREAD);
    } else if (older >= cap) {
      wait.push(sourceCapWait(source, older, cap));
    }
  }
  for (const child of openSubs) {
    wait.push(subIssueWait(child.number));
  }
  if (!hold && openSubs.length > 0) {
    return { verdict: "wait", reasons: wait, pulls };
  }
  const criteriaOnly = refuse.length === 1 && refuse[0] === noTrustedSpec(taskList);
  if (criteriaOnly && !hold && parked.length === 0 && wait.length === 0 && verdict.writtenAt !== undefined && !labels.includes("needs-human") && refineDue(spec, humans, appId, taskList)) {
    return { verdict: "wait", reasons: [`${refuse[0]}; intake's refinement of this body is due and may supply them`], pulls: [] };
  }
  if (refuse.length === 1 && refuse[0] === BODY_EDITED && !hold && !attended && wait.length === 0 && parked.length === 0 && verdict.writtenAt === undefined) {
    return { verdict: "wait", reasons: refuse, pulls: [], retriage: [] };
  }
  if (refuse.length > 0) {
    return {
      verdict: "refuse",
      reasons: refuse,
      ...(hold && { hold, reason: strongestReason(holdCodes) }),
      ...(attended && { attended }),
      ...(!hold && refuse.every((reason) => hostWork.has(reason)) && wait.length === 0 && parked.length === 0 && { hostRun: true }),
      ...(doneBy.length > 0 && { done: doneBy }),
      ...(unset.length > 0 && refuse.length === unset.length && { unsetOnly: unset }),
      ...(split && verdict.writtenAt === undefined && refuse.length === 1 && !hold && !attended && wait.length === 0 && parked.length === 0 && { triage: true }),
    };
  }
  if (parked.length > 0) {
    return { verdict: "wait", reasons: parked, pulls: [] };
  }
  if (wait.length > 0) {
    return { verdict: "wait", reasons: wait, pulls, ...(retriage.length > 0 && pulls.length === 0 && { retriage }) };
  }
  return { verdict: "admit", reasons: [] };
}

export function judgedSince(events, trusted) {
  const times = (events ?? [])
    .filter((event) => event?.event === "labeled" && [READY, AGENT_READY].includes(String(event.label?.name).toLowerCase()) && trusted(event.actor))
    .map((event) => Date.parse(event.created_at))
    .filter(Number.isFinite);
  return Math.max(Number.NEGATIVE_INFINITY, ...times);
}

/**
 * Whether a blocker the lanes App closed report-delivered (`report`, as
 * appCloseKind reads it) and isTrustedClose does not count (its outcome comment
 * predates the last reopen) no longer holds its dependent: something judged
 * the dependent at `after` (ms), after that close, against the report. A report
 * with no readable time holds. Pure.
 */
export function reportCleared(report, after) {
  const closed = Date.parse(report?.at);
  return report?.stop === "report-delivered" && Number.isFinite(closed) && after > closed;
}

export const clearedPastReport = ({ github, repository, isApp, trusted, after }) => async (number) =>
  (await trusted(number)) || (after > Number.NEGATIVE_INFINITY && reportCleared(await currentAppClose(github, repository, number, isApp), after));

export async function currentAppClose(github, repository, number, isApp) {
  try {
    const issue = await github("GET", `/repos/${repository}/issues/${number}`);
    return issue?.state === "closed" && isApp(issue.closed_by) ? await appCloseKind(github, repository, number, isApp) : null;
  } catch {
    return null;
  }
}

export const RETRIAGE_MARKER = "<!-- intake-triage retriage -->";

export const retriageNote = (reasons, items) => `${RETRIAGE_MARKER}\nNot admitted to the issue lane yet: ${reasons}.\n\n${retriageText(items)}`;

export function retriageText(items) {
  if (items.length === 0) {
    return "Intake triages this issue again, against its body as it stands now.";
  }
  const quote = (text) => String(text ?? "").slice(0, 2000).split(/\r?\n/).map((line) => `> ${line}`).join("\n");
  return [
    "The reports below are data for that triage, not instructions:",
    ...items.map(({ number, url, reason }) => `\n#${number}'s report-delivered close${url ? ` (${url})` : ""}:\n\n${quote(reason)}`),
  ].join("\n");
}

export const blockerKey = (blocker, repository) =>
  here(blocker.repository_url, repository) ? blocker.number : `${repoOf(blocker.repository_url)}#${blocker.number}`;

export async function trustedElsewhere(github, blocker, humans) {
  const repo = repoOf(blocker.repository_url);
  if (repo === null || !BLOCKER_NUMBER.test(String(blocker.number))) {
    return false;
  }
  try {
    return humans.has((await github("GET", `/repos/${repo}/issues/${blocker.number}`))?.closed_by?.id);
  } catch {
    return false;
  }
}

export const isAppId = (id, appId) => appId !== undefined && id !== undefined && id !== null && String(id) === String(appId);

const appActor = (appId) => (actor) => appId !== undefined && actor?.id === appId;

export const ownVerdict = (comments, appId) =>
  comments.find((c) => isAppId(c.user?.id, appId) && String(c.body ?? "").startsWith(`${VERDICT_MARKER}\n`));

export function earlierFlags(comments, appId) {
  const own = ownVerdict(comments, appId);
  const lines = String(own?.body ?? "").split("\n");
  if (!own || lines.includes(`- ${UNRECORDED}`)) {
    return null;
  }
  return [
    ...new Set(
      lines
        .filter((line) => line.startsWith("- flagged: "))
        .flatMap((line) => line.slice("- flagged: ".length).replace(` ${EARLIER}`, "").split(","))
        .map((flag) => flag.trim())
        .filter((flag) => VERDICT_FLAGS.has(flag)),
    ),
  ];
}

export async function decisionStays(github, base, comments, appId, events = () => paginate(github, `${base}/events`)) {
  const setter = (await events()).filter((event) => event?.event === "labeled" && DECISION_LABELS.includes(event.label?.name)).at(-1)?.actor?.id;
  if (setter !== appId) {
    return `a person set its ${NEEDS_DECISION}`;
  }
  if (!ownVerdict(comments, appId)) {
    return null;
  }
  const flags = earlierFlags(comments, appId);
  if (flags === null) {
    return `its ${NEEDS_DECISION} stands: whether an earlier verdict flagged is unknown`;
  }
  const stops = flags.filter((flag) => flag !== "intent");
  return stops.length > 0 ? `its ${NEEDS_DECISION} stands for flagged: ${stops.join(", ")}` : null;
}

export const refinementExact = (body) => {
  const last = String(body ?? "").trimEnd().split("\n").at(-1);
  return last === REFINE_FOOTERS.retriage || last === REFINE_FOOTERS.confirm;
};

export async function parentDecisionOpen({ github, repository, parent, humans, appId, events }) {
  if (appId === undefined || !here(parent?.repository_url, repository) || !Number.isInteger(parent?.number)) {
    return true;
  }
  const base = `/repos/${repository}/issues/${parent.number}`;
  try {
    const comments = await paginate(github, `${base}/comments`);
    if ((await decisionStays(github, base, comments, appId, events)) !== null) {
      return true;
    }
    const refinement = comments.findLast(
      (comment) => comment?.user?.id === appId && String(comment.body ?? "").startsWith(REFINE_MARKER),
    );
    const asking = refinement ?? (earlierFlags(comments, appId)?.includes("intent") ? ownVerdict(comments, appId) : undefined);
    if (asking === undefined || (refinement !== undefined && refinementExact(refinement.body))) {
      return false;
    }
    const since = Date.parse(asking.created_at);
    const { kept } = await selectTrustedIssueComments({ github, repository, issueNumber: parent.number, ids: humans });
    return !kept.some((item) => Date.parse(item.comment.created_at) > since && isDecisionComment(item, humans));
  } catch {
    return true;
  }
}

export const sayWhy = (github, repository, base, comments, text) => writeWhy(github, repository, base, comments, text, LANES_APP_LOGIN);

const REFINE_TASK = "- [ ] ";

export function refineDue(spec, humans, appId, taskList) {
  if (!spec || taskList !== REFINE_TASK || appId === undefined || !writtenBy(humans)(spec) || !(spec.commentCount + 2 <= SPEC_COMMENTS)) {
    return false;
  }
  const body = String(spec.body ?? "");
  if (body.split("\n").some((line) => line.trimStart().startsWith(REFINE_TASK))) {
    return false;
  }
  const version = bodyVersion(body);
  return !(spec.comments ?? []).some((comment) => appRefinement(comment, appId) && String(comment.body).split("\n")[1] === version);
}

export const noTrustedSpec = (taskList) =>
  `no trusted-human acceptance criteria: a listed human must put the confirmed \`${taskList.trim()}\` criteria in the body or post them as their own comment, or, on an issue a listed human filed, intake's newest refinement comment must hold them unedited`;

export function briefedIssue(issue, appId) {
  const labels = issue?.labels;
  if (appId === undefined || issue?.author?.__typename !== "Bot" || issue.author.databaseId !== appId || !Array.isArray(labels?.nodes) || labels.totalCount !== labels.nodes.length) {
    return false;
  }
  const held = new Set([...HOLD_STATES, ...UNTRUSTED_LABELS].map((name) => name.toLowerCase()));
  if (names(labels.nodes).some((name) => held.has(String(name ?? "").toLowerCase())) || BODY_HOLD.test(String(issue.body ?? ""))) {
    return false;
  }
  const rest = (issue.comments ?? []).map((comment) => ({
    id: comment?.databaseId,
    user: { id: comment?.author?.__typename === "Bot" ? comment.author.databaseId : undefined },
    body: comment?.body,
    created_at: comment?.createdAt,
    updated_at: comment?.lastEditedAt ?? comment?.createdAt,
  }));
  try {
    const newest = readAdmissionRecord(rest, appId);
    return (newest !== null && matchesRecord(newest.record, { title: issue.title, body: issue.body })) || triageBriefed(issue.comments, appId, issue);
  } catch {
    return false;
  }
}

// The owner's triage-verdict reading, https://github.com/melodic-software/architecture/pull/167.
export function triageBriefed(comments, appId, { title, body }) {
  const app = (actor) => appId !== undefined && actor?.__typename === "Bot" && actor.databaseId === appId;
  const own = (comments ?? []).find((comment) => app(comment?.author) && String(comment.body ?? "").startsWith(`${VERDICT_MARKER}\n`));
  if (!own || (own.lastEditedAt != null && !app(own.editor))) {
    return false;
  }
  const lines = String(own.body).split("\n");
  const stamp = JUDGED.exec(lines.at(-1));
  return (
    [CLEAR_READY, CLEAR_ADMITTED].some((outcome) => lines[1].startsWith(`${VERDICT_CLEAR}${outcome}`)) &&
    stamp !== null &&
    stamp[1] === contentHash(title) &&
    stamp[2] === contentHash(body)
  );
}

export const humanWritten = (item, humans) => writtenBy(humans)(item);

export const splitItemsLine = (moved) => `<!-- split items=${[...moved].sort((a, b) => a - b).join(",")} -->`;

export const carriesSplit = (body) => SPLIT_ITEMS.test(String(body ?? "").split("\n")[2] ?? "");

export function webHostsFrom(text) {
  if (text === undefined || text === "") {
    return undefined;
  }
  const value = JSON.parse(text);
  if (value === "any" || (Array.isArray(value) && value.every((host) => typeof host === "string"))) {
    return value;
  }
  throw new Error("ISSUE_LANE_WEB_HOSTS is neither \"any\" nor a list of host names");
}

const hasTaskLine = (text, taskList) => {
  const lines = String(text ?? "").split("\n");
  const blocks = fenceBlocks(lines);
  return lines.some((line, index) => blocks[index] === 0 && line.replace(INVISIBLE, "").trimStart().startsWith(taskList));
};

export const hasTrustedCriteria = (spec, humans, taskList, appId, ownIds) =>
  trustedSpecTexts(spec, humans, appId, taskList, ownIds).some((text) => hasTaskLine(text, taskList));

export async function finishedParent({ github, repository, issue, trusted }) {
  if (!((issue?.sub_issues_summary?.total ?? 0) > 0)) {
    return null;
  }
  const children = await paginate(github, `/repos/${repository}/issues/${issue.number}/sub_issues`);
  return children.length > 0 && (await subIssueLeftOpen(children, trusted, repository)) === null ? children.map((child) => Number(child.number)) : null;
}

/**
 * admissionFacts' `isTrusted` for admit(): issue `number` here was closed by a
 * listed human or a merge, by the lanes App as already-done or verified-done
 * with evidence that still holds (owner Q9), by the lanes App on its own
 * outcome close comment when `blocker` is set (owner Q300: blockers only), or
 * is a split parent the lanes App closed (splitParentClosed), read fresh.
 */
export const closedByTrusted = ({ github, repository, humans, appId }) => {
  const isApp = appActor(appId);
  const trusted = async (number, { blocker = false } = {}) => {
    const issue = await github("GET", `/repos/${repository}/issues/${number}`);
    return (await isTrustedClose(github, repository, issue, humans, isApp, { blocker })) || splitParentClosed({ github, repository, issue, isApp, humans, trusted });
  };
  return trusted;
};

export async function noteUnrunnable({ github, repository, issue, rules, webHosts, statusOf, log = console.log }) {
  const base = `/repos/${repository}/issues/${issue.number}`;
  const reason = unrunnableReason(unrunnableCriteria(issue.body, rules["task-list"], webHosts));
  if (!reason) {
    return { outcome: "none", reasons: [] };
  }
  const labels = statusOf ? await statusOf(Number(issue.number), names(issue.labels)) : names(issue.labels);
  const settled = admissionSettled(
    labels,
    statusOf?.events ? await statusOf.events(Number(issue.number)) : await paginate(github, `${base}/events`),
    undefined,
    statusOf?.state ? await statusOf.state(Number(issue.number)) : undefined,
  );
  if (settled) {
    log(`admit: #${issue.number} left as is (${settled})`);
    return { outcome: "skipped", reasons: [settled] };
  }
  await sayWhy(github, repository, base, await paginate(github, `${base}/comments`), `Not admitted to the issue lane: ${reason}.`);
  log(`admit: #${issue.number} held; split noted (${reason})`);
  return { outcome: "noted", reasons: [reason] };
}

export const WRITTEN_STATUS_REREADS = 3;
export const WRITTEN_STATUS_WAIT_MS = 5000;

export const ADMISSION_STATUS_READS = 2 + WRITTEN_STATUS_REREADS;

export async function writtenLabels({ statusOf, number, names, wrote, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) }) {
  if (wrote === undefined || wrote === null || !statusOf.state) {
    return statusOf(number, names);
  }
  let waited = 0;
  for (let reread = 0; ; reread += 1) {
    let seen;
    try {
      const labels = await statusOf(number, names);
      seen = (await statusOf.state(number)) ?? "unset";
      if (seen === wrote) {
        return labels;
      }
    } catch (error) {
      if (error?.cause?.name !== "StatusDisagreement") {
        throw error;
      }
      seen = "two disagreeing values";
    }
    if (reread === WRITTEN_STATUS_REREADS) {
      throw new StatusReadError(number, `it read ${seen}, not the \`${wrote}\` this run wrote, on ${reread + 1} reads over ${waited / 1000} s`);
    }
    const ms = WRITTEN_STATUS_WAIT_MS * 2 ** reread;
    await sleep(ms);
    waited += ms;
  }
}

export async function admissionFacts({ github, repository, number, issue, rules, humans, isTrusted, appId, doneBy, statusOf, wrote, sleep }) {
  const base = `/repos/${repository}/issues/${number}`;
  const blockers = await blockersOf(github, base);
  const isApp = appActor(appId);
  const trusted = isTrusted ?? (async (blocker, options) => isTrustedClose(github, repository, await github("GET", `/repos/${repository}/issues/${blocker}`), humans, isApp, options));
  const trustedCloses = new Set();
  const reported = new Map();
  for (const blocker of blockers) {
    if (!blocker.pull_request && blockerDone(blocker, repository, () => true)) {
      const local = here(blocker.repository_url, repository);
      const ok = local ? await trusted(blocker.number, { blocker: true }) : await trustedElsewhere(github, blocker, humans);
      if (ok) {
        trustedCloses.add(blockerKey(blocker, repository));
      } else if (local && appId !== undefined) {
        const close = await currentAppClose(github, repository, blocker.number, isApp);
        if (close?.stop === "report-delivered" && close.at) {
          reported.set(blockerKey(blocker, repository), { stop: close.stop, at: close.at, url: close.url, reason: close.reason });
        }
      }
    }
  }
  const spec = await specOf(github, repository, number);
  const child = isApp(issue.user) && String(issue.body ?? "").startsWith(SPLIT_CHILD_MARKER);
  const typed = [...rules["types-under-parent"], ...rules["types-parent-if-present"]].includes(issue.type?.name);
  const parent = child || typed ? await parentOf(github, base) : null;
  if (child) {
    spec.splitParent = await splitParentOf(github, repository, parent, appId);
  }
  const parentHolds = statusOf && typed && parent !== null && here(parent.repository_url, repository) ? await statusOf(parent.number, names(parent.labels)) : undefined;
  const parentEvents = parentHolds && (() => statusOf.events(parent.number));
  const decisionOpen =
    typed && parent !== null && carried(names(parent.labels), DECISION_LABELS) ? await parentDecisionOpen({ github, repository, parent, humans, appId, events: parentEvents }) : undefined;
  const isPublic = (await github("GET", `/repos/${repository}`))?.visibility === "public";
  const subIssues = await openSubIssues(github, base, issue);
  const sources = sourceLabels(issue.labels);
  const counted = ownAgentIds(rules, appId).has(issue.user?.id) && sources.length === 1 && SOURCE_LABEL.test(sources[0]);
  const sourceOpen = counted
    ? (await paginate(github, `/repos/${repository}/issues?state=open&labels=${encodeURIComponent(sources[0])}`)).filter((item) => !item?.pull_request).map((item) => Number(item.number))
    : undefined;
  return {
    sourceOpen,
    issue,
    ...(statusOf && { holdLabels: await readyWhileDeferred(await writtenLabels({ statusOf, number: Number(number), names: names(issue.labels), wrote, sleep }), names(issue.labels)) }),
    ...(statusOf?.state && { fieldState: await statusOf.state(Number(number)) }),
    comments: await paginate(github, `${base}/comments`),
    spec,
    schedule: readSchedule(),
    parent: typed && parent !== null ? { ...parent, decisionOpen, ...(parentHolds && { holdLabels: parentHolds }) } : null,
    blockers,
    trustedCloses,
    reported,
    pulls: await openPullsFor(github, repository, number),
    subIssues,
    finished: subIssues.length === 0 && (await finishedParent({ github, repository, issue, trusted })) !== null,
    doneBy: await (doneBy ?? mergedRefsReader({ github, repository, humans, appId }))(Number(number)),
    events: statusOf?.events ? await statusOf.events(Number(number)) : await paginate(github, `${base}/events`),
    public: isPublic,
    chargeEdits: await chargeEditsOf({ github, repository, number, spec, charges: chargePattern(), public: isPublic }),
  };
}

export const DEFERRED_AHEAD_READS = 10;

export const roomDeferred = (labels) => {
  const lower = names(labels).map((name) => String(name).toLowerCase());
  return lower.includes(READY) && !UNTRUSTED_LABELS.some((name) => lower.includes(name)) && !DEFERRAL_HOLDS.some((name) => lower.includes(name));
};

export async function deferredAhead(github, repository, issue, listing, pullsFor = (number) => openPullsFor(github, repository, number)) {
  const created = Date.parse(issue.created_at);
  if (!Number.isFinite(created)) {
    return true;
  }
  try {
    const deferred = await listing.issues(["deferred"]);
    if ((deferred.held ?? []).some((item) => Number(item.number) !== Number(issue.number) && !(Date.parse(item.created_at) >= created))) {
      return true;
    }
    const older = deferred
      .filter((item) => Number(item.number) !== Number(issue.number) && Date.parse(item.created_at) < created)
      .sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at) || a.number - b.number);
    for (const item of older.slice(0, DEFERRED_AHEAD_READS)) {
      if (roomDeferred(item.state === null ? item.labels : [...item.labels, READY]) && (await pullsFor(item.number)).length === 0) {
        return true;
      }
    }
    return older.length > DEFERRED_AHEAD_READS;
  } catch (error) {
    console.log(`::warning title=admit::the deferred listing could not be read, so #${issue.number} counts an older deferred issue ahead of it: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return true;
  }
}

export const RACE_WINDOW_MS = 10 * 60_000;

export async function admissionsSince(github, repository, since, listing) {
  const stamp = new Date(since).toISOString().replace(/\.\d{3}Z$/, "Z");
  const listed = new Set();
  const found = await listing.issues(["deferred", AGENT_READY], { since: stamp });
  for (const item of found) {
    if (!item?.pull_request && Number.isSafeInteger(item?.number)) {
      listed.add(item.number);
    }
  }
  const entered = (found.held ?? []).filter((item) => Number.isSafeInteger(item?.number) && !listed.has(item.number)).map((item) => ({ number: item.number, at: null }));
  for (const number of listed) {
    const adds = (await listing.events(number)).filter((event) => event?.event === "labeled" && [AGENT_READY, DEFERRED].includes(event.label?.name));
    const times = (name) => adds.filter((event) => event.label.name === name).map((event) => Date.parse(event.created_at)).filter((time) => Number.isFinite(time) && time >= since);
    const [claims, admits] = [times(DEFERRED), times(AGENT_READY)];
    if (adds.length === 0) {
      entered.push({ number, at: null });
    } else if (claims.length > 0 || admits.length > 0) {
      entered.push({ number, at: claims.length > 0 ? Math.max(...claims) : Math.min(...admits) });
    }
  }
  return entered.sort((a, b) => (a.at ?? Number.NEGATIVE_INFINITY) - (b.at ?? Number.NEGATIVE_INFINITY) || a.number - b.number);
}

export function admissionsAhead(entered, number) {
  const own = entered.find((item) => item.number === Number(number));
  const others = entered.filter((item) => item.number !== Number(number));
  return own?.at == null ? others.length : others.filter((item) => item.at === null || item.at <= own.at).length;
}

export async function admit({ github, repository, number, verdict, rules, humans, appId, status, webHosts, setStatus, statusOf, wrote, sleep, listing, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const isTrusted = closedByTrusted({ github, repository, humans, appId });
  const doneBy = mergedRefsReader({ github, repository, humans, appId, log });
  const facts = await admissionFacts({ github, repository, number, issue, rules, humans, appId, isTrusted, doneBy, statusOf, wrote, sleep });
  const { comments } = facts;
  const decision = decide({ ...facts, verdict, rules, humans, appId, repository, webHosts });
  const reasons = decision.reasons.join("; ");
  const lower = names(facts.holdLabels ?? issue.labels);
  const move = (state) => setStatus(number, state, { keepHold: true });
  const write = (state, label) => (lower.includes(label) ? undefined : state === "needs-owner-decision" ? setStatus(number, state) : move(state));
  const held = (result) => {
    if (result?.outcome !== "held") {
      return null;
    }
    const why = `a person's Work status ${result.state} holds it`;
    log(`admit: #${number} left as is (${why})`);
    return { outcome: "held", reasons: [why], status: result.state };
  };
  if (decision.verdict === "skip") {
    log(`admit: #${number} left as is (${reasons})`);
    return { outcome: "skipped", reasons: decision.reasons };
  }
  if (decision.verdict === "refuse") {
    const parked = decision.hold ? NEEDS_DECISION : CONFIRMED;
    const stop = held(await write(decision.hold ? "needs-owner-decision" : "confirmed", parked));
    if (stop) {
      return stop;
    }
    const marks = [...(decision.attended ? [ATTENDED] : []), ...(decision.hostRun ? [HOST_RUN] : [])];
    if (marks.length > 0) {
      await github("POST", `${base}/labels`, { labels: marks });
    }
    await sayWhy(github, repository, base, comments, decision.hold ? heldRefusalText(reasons, decision.reason) : refusalText(reasons));
    log(`admit: #${number} refused (${reasons})`);
    return { outcome: "refused", reasons: decision.reasons, status: parked };
  }
  if (decision.verdict === "wait" && decision.retriage) {
    const stop = held(await write("needs-triage", "needs-triage"));
    if (stop) {
      return stop;
    }
    await sayWhy(github, repository, base, comments, retriageNote(reasons, decision.retriage));
    log(`admit: #${number} sent back to intake (${reasons})`);
    return { outcome: "retriage", reasons: decision.reasons };
  }
  if (decision.verdict === "wait") {
    const stop = held(decision.pulls.length > 0 ? await write("deferred", DEFERRED) : lower.includes(DEFERRED) ? await move("ready") : undefined);
    if (stop) {
      return stop;
    }
    await sayWhy(github, repository, base, comments, `Not admitted to the issue lane yet: ${reasons}.`);
    log(`admit: #${number} waits (${reasons})`);
    return { outcome: "waiting", reasons: decision.reasons };
  }
  const record = () => writeAdmissionRecord(github, repository, number, { actorId: appId, title: issue.title, body: issue.body ?? "" });
  const checkedAt = Date.now();
  const s = await status();
  const unread = s.admission_basis === "fail-open";
  const full = s.paused || unread || !s.admission_open || (s.admission_room ?? 1) <= 0;
  if (full || (await deferredAhead(github, repository, issue, listing))) {
    const why = !full
      ? `an older issue deferred for room (${DEFERRED}) is ahead of it`
      : s.paused
        ? `the lane is paused (${s.pause_reason})`
        : unread
          ? "the issue lane's queued count could not be read (admission_basis fail-open)"
          : `admissions are closed (${s.admission_reason})`;
    await record();
    const stop = held(await write("deferred", DEFERRED));
    if (stop) {
      return stop;
    }
    log(`admit: #${number} deferred: ${why}`);
    return { outcome: "deferred", reasons: [why] };
  }
  await record();
  const capped = Number.isFinite(s.admission_room);
  if (capped) {
    const stop = held(lower.includes(DEFERRED) ? await move("ready") : undefined) ?? held(await move("deferred"));
    if (stop) {
      return stop;
    }
    let ahead;
    try {
      ahead = admissionsAhead(await admissionsSince(github, repository, checkedAt - RACE_WINDOW_MS, listing), number);
    } catch (error) {
      const why = `the admissions racing it could not be read (${String(error?.message ?? error).replaceAll("\n", " ")})`;
      log(`admit: #${number} deferred: ${why}`);
      return { outcome: "deferred", reasons: [why] };
    }
    if (ahead >= s.admission_room) {
      const why = `${ahead} issue(s) entered admission ahead of it since check-wip-cap's count, which takes the room of ${s.admission_room} it read`;
      log(`admit: #${number} deferred: ${why}`);
      return { outcome: "deferred", reasons: [why] };
    }
  }
  const stop = held(await move(AGENT_READY));
  if (stop) {
    return stop;
  }
  log(`admit: #${number} set to ${AGENT_READY}`);
  return { outcome: "admitted", reasons: [] };
}
