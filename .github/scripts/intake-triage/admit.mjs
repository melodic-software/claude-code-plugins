// admit.mjs: after apply-verdict set `status: ready`, adds `agent-ready` as
// the lanes App when the issue meets #9212's admission criteria (owner
// decision Q51), and the issue lane's caps have room. No model. The rules come
// from the default branch's .github/actions/resolve-config/admission-rules.json.
//
// Criteria 1, 5 and 6 (exact intent, no very-high security risk, no charge)
// are already in `status: ready`: apply-verdict withholds it on any flag
// (triage flags security only for a very-high risk) or a hold label, and the
// cost rule adds needs-human. Criterion 4 (no protected path named) is not
// applied. This checks the rest:
//
// - 2: the Issue Type is in `types`, or in `types-under-parent` under an open
//   parent issue a listed human filed that awaits no decision; a type in
//   `types-parent-if-present` needs that parent only when it has one (Q83);
// - 3: the Size and Uncertainty apply-verdict wrote are in `sizes` and
//   `uncertainty`, and the issue is not `work-class: untrusted-provenance`
//   work; no other work class gates admission (owner Q85, #9668);
// - 7: a `task-list` line, the criteria the lane checks, in text pr-verify
//   will read (resolve-pr.mjs linkedIssues): the body or a comment written,
//   and last edited if ever, by a listed human, and, on an issue whose body a
//   listed human wrote, refine.mjs's newest refinement comment while unedited
//   (refinementSpec). Nothing else the lanes App wrote counts, an App-filed
//   issue included, and an issue with more comments than the 100 pr-verify
//   reads is refused, since pr-verify stops on it;
// - 8: no `refuse-labels` label, every blocker a merged pull request in this
//   repository or an issue closed, for any reason, by a listed human or (in
//   this repository only) a merge or commit, read there when it is another
//   repository's, and no open pull request in this repository is for
//   the issue: one GitHub says closes it, or whose body has the issue lane's
//   `Refs: #<issue>` line (report-outcome.mjs). A passing mention is not one;
// - 9: the author is a listed human or the lanes App;
// - lane-runnable done-when: no task-list item asks for what an unattended
//   lane run cannot do (unrunnableCriteria below): a run on a named host or
//   OS, a paid eval, a run repeated N times, a measurement over time, or a
//   page on a host outside resolve-issue's web-access domains. The refusal
//   recommends splitting those items into a needs-human child issue, which
//   refine.mjs files when some items are left for the lane;
// - 10: check-wip-cap's status: over the queued cap, or with the lane paused
//   over the WIP or held cap (from wip.pause-from), the issue gets
//   `admission-deferred`, which work-unblock's hourly sweep admits once there
//   is room. With room, an issue still waits behind an older open issue in
//   `admission-deferred`, so admission takes the oldest first (owner Q95),
//   unless a blocker it rests on is one the sweep does not count yet
//   (sweepCounts): such an issue is admitted with room and, with none,
//   waits with a comment instead of `admission-deferred`.
//
// A refusal a person must settle swaps `status: ready` for
// `status: needs-decision`; a blocker or an open pull request keeps
// `status: ready`. Either way one App comment carrying ADMIT_MARKER says why.
// An open pull request also adds `admission-deferred`: work-unblock's sweep
// skips the issue while such a pull request is open and admits it once none
// is. An issue that waits only on a blocker loses `admission-deferred`, and
// work-unblock admits it when its blocker closes. A refused issue loses it
// too. The sweep runs these rules itself only on an issue a listed human
// marked (added admission-deferred to an issue with `status: ready`). An
// issue already agent-ready is left alone, and so is one whose agent-ready
// was removed until the lanes App or a listed human adds `status: ready`
// after the newest removal. Issue text can only
// refuse: it never satisfies a criterion the fields, labels or API decide.
import { readFileSync } from "node:fs";

import { isTrustedClose, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { closingPulls } from "../work-resolve-issue/report-outcome.mjs";

export const AGENT_READY = "agent-ready";
export const DEFERRED = "admission-deferred";
export const ADMIT_MARKER = "<!-- intake-triage admission -->";
// Opens the lanes App's refinement comment (refine.mjs).
export const REFINE_MARKER = "<!-- intake-triage refinement -->";
export const READY = "status: ready";
export const NEEDS_DECISION = "status: needs-decision";
const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";
// The one work class that holds an issue for a person (owner Q85, #9668).
export const UNTRUSTED = "work-class: untrusted-provenance";
const PARENT_HOLDS = new Set(["needs-human", "needs-owner-decision", NEEDS_DECISION]);
const LISTS = ["types", "types-under-parent", "types-parent-if-present", "sizes", "uncertainty", "refuse-labels"];

// The rules file, each list checked to hold strings.
export function loadRules(path) {
  const rules = JSON.parse(readFileSync(path, "utf8"));
  for (const key of LISTS) {
    if (!Array.isArray(rules?.[key]) || !rules[key].every((item) => typeof item === "string" && item !== "")) {
      throw new Error(`${path}: \`${key}\` must be a list of strings`);
    }
  }
  if (typeof rules["task-list"] !== "string" || rules["task-list"] === "") {
    throw new Error(`${path}: \`task-list\` must be a string`);
  }
  return rules;
}

const here = (url, repository) =>
  String(url ?? "")
    .toLowerCase()
    .endsWith(`/repos/${repository}`.toLowerCase());

// The open pull requests in `repository` for issue `number`: those `closing`
// (closedByPullRequestsReferences nodes) lists in this repository, and those
// the timeline says reference it whose body has a `Refs: #<number>` line.
export function openPullsNaming(timeline, repository, number, closing = []) {
  const refs = `Refs: #${number}`;
  const linked = timeline
    .map((event) => (event?.event === "cross-referenced" ? event.source?.issue : null))
    .filter(
      (source) =>
        source?.pull_request &&
        source.state === "open" &&
        here(source.repository_url, repository) &&
        String(source.body ?? "")
          .split("\n")
          .some((line) => line.trim() === refs),
    )
    .map((source) => source.number);
  const closes = closing
    .filter((node) => String(node?.repository?.nameWithOwner ?? "").toLowerCase() === repository.toLowerCase())
    .map((node) => node.number);
  return [...new Set([...closes, ...linked])];
}

// The open pull requests for an issue, read fresh (openPullsNaming).
export async function openPullsFor(github, repository, number) {
  const [owner, name] = repository.split("/");
  return openPullsNaming(
    await paginate(github, `/repos/${repository}/issues/${number}/timeline`),
    repository,
    Number(number),
    await closingPulls(github, { owner, name, number: Number(number) }),
  );
}

// Done-when items an unattended lane run cannot perform. Each pattern needs
// an action or a place within one clause of its subject, so an item that only
// names a host, a threshold or a retention period passes.
const N = String.raw`(?:\d+|two|three|four|five|seven|ten|fourteen|twenty|thirty|fifty|hundred)`;
const UNIT = String.raw`(?:hours?|days?|weeks?|months?|nights?)`;
const UNRUNNABLE = [
  [
    "a run on a host the lane is not",
    /\b(?:on|from|in) (?:a |an |the |another |each )?(?:windows(?: 1[01])?|macos|mac|wsl2?|fleet|physical|desktop|remote|attended) (?:host|machine|workstation|laptop|desktop|box|vm)s?\b/i,
  ],
  [
    "a paid eval",
    /\b(?:run|execute|launch|start)\b[^,;:]{0,40}\b(?:paid evals?|claude plugin eval\b(?![^,;:]*\b(?:validate|dry[- ]run|no-spend)\b))/i,
  ],
  [
    "a repeated run",
    new RegExp(
      String.raw`\b(?:run|execute|repeat|pass(?:es)?|succeed|complete)\b[^,;:]{0,40}\b${N} (?:consecutive|successive|back-to-back|repeated|loaded|parallel) (?:runs?|passes|iterations|sessions|times)\b|\b${N} (?:consecutive|successive|back-to-back|repeated|loaded|parallel) (?:runs?|passes|iterations|sessions) (?:pass|succeed|complete|show|report)`,
      "i",
    ),
  ],
  [
    "a measurement over time",
    {
      // An observation window, not a duration the lane can read from config:
      // an expiry or retention period passes.
      window: new RegExp(
        [
          String.raw`\b(?:for|over|across|during) the (?:next|following|coming) (?:${N} )?${UNIT}\b`,
          String.raw`\b(?:measure|observe|monitor|watch|track)\b[^,;:]{0,60}\b(?:for|over|across|during) (?:a |an |one |${N} )?${UNIT}\b`,
          String.raw`\b(?:measure|observe|monitor|watch|track|confirm|verify|check)\b[^,;:]{0,60}\bafter (?:a |an |one |${N} )?${UNIT} (?:of (?:use|running|runs|operation|traffic)|that)\b`,
        ].join("|"),
        "i",
      ),
      retention: /\b(?:expir\w*|keeps?|kept|retain\w*|retention|older than|ttl)\b/i,
      test(text) {
        return this.window.test(text) && !this.retention.test(text);
      },
    },
  ],
];
// The lane can always reach these; a page elsewhere needs resolve-issue's
// web access.
const GITHUB_HOSTS = ["github.com", "api.github.com", "localhost", "127.0.0.1"];
// An item reads a page only when its clause asks to open or compare against it,
// not when it names a URL as text to edit.
const READS_PAGE = /\b(?:read|fetch|open|visit|load|browse|check|confirm|verify|match(?:es)?|compare|against|according|shows?|says|lists?)\b/i;
const allowedBy = (hosts) => (host) =>
  hosts.some((entry) => (entry.startsWith("*.") ? host.endsWith(entry.slice(1)) : host === entry));
// Backtick-free, mention-free, at most 80 characters: issue text
// quoted back into an App comment.
const excerpt = (text) => {
  const plain = text.replaceAll("`", "").replaceAll("@", "@\u200b").trim();
  return plain.length > 80 ? `${plain.slice(0, 77)}...` : plain;
};

// [{line, text, more}] for each task-list item, in order: its index among
// the body's `\n`-split lines, its text after the task-list prefix, and the
// indexes of the lines after it indented deeper than its marker (a sub-list
// or wrapped text, part of the item). Item n (1-based) is entry n - 1. Pure.
export const taskItems = (body, taskList) => {
  const lines = String(body ?? "").split("\n");
  const indent = (line) => line.length - line.trimStart().length;
  const items = [];
  lines.forEach((line, index) => {
    const trimmed = line.trimStart();
    if (!trimmed.startsWith(taskList)) {
      return;
    }
    const more = [];
    for (let next = index + 1; next < lines.length && lines[next].trim() !== "" && indent(lines[next]) > indent(line); next += 1) {
      more.push(next);
    }
    items.push({ line: index, text: trimmed.slice(taskList.length), more });
  });
  return items;
};

// The admission comment's text for a refusal, after ADMIT_MARKER: each reason
// names what admission needs; only a security or intent reason asks a person.
export const refusalText = (reasons) =>
  `Not admitted to the issue lane: ${reasons}. Admission takes the issue once each of those is met, when intake triages it again (\`.github/actions/resolve-config/admission-rules.json\`).`;

// [{n, kind, text}] for each task-list item (1-based n) the lane cannot
// perform. `webHosts` is resolve-issue's web-access domains: "any" skips the
// URL check, an absent list allows only GitHub and local hosts, and a `*.`
// entry allows that domain's subdomains. Pure.
export function unrunnableCriteria(body, taskList, webHosts) {
  const allowed = webHosts === "any" ? null : allowedBy([...GITHUB_HOSTS, ...(Array.isArray(webHosts) ? webHosts : [])].map((h) => h.toLowerCase()));
  const items = taskItems(body, taskList).map(({ text }) => text);
  const found = [];
  items.forEach((text, index) => {
    let kind = UNRUNNABLE.find(([, pattern]) => pattern.test(text))?.[0];
    if (!kind && allowed) {
      // Clauses split on , ; and a colon that does not start ://.
      const outside = text
        .split(/[,;]|:(?!\/\/)/)
        .filter((clause) => READS_PAGE.test(clause))
        .flatMap((clause) => [...clause.matchAll(/\bhttps?:\/\/([a-z0-9.-]+)/gi)].map((m) => m[1].toLowerCase().replace(/\.+$/, "")))
        .find((host) => !allowed(host));
      if (outside) {
        kind = `a page on ${outside}, outside the lane's web hosts`;
      }
    }
    if (kind) {
      found.push({ n: index + 1, kind, text: excerpt(text) });
    }
  });
  return { items: items.length, found };
}

// The refusal reason for unrunnableCriteria's result, with the split it
// recommends, or null when every item is runnable.
export function unrunnableReason({ items, found }) {
  if (found.length === 0) {
    return null;
  }
  const list = found.map(({ n, kind, text }) => `item ${n} (${kind}: "${text}")`).join(", ");
  const split =
    found.length === items
      ? "no done-when item is left for the lane, so a person takes the issue"
      : "recommended split: keep the other items here as the admissible issue and move these to a needs-human child issue";
  return `its done-when asks for what an unattended lane run cannot perform: ${list}; ${split}`;
}

const names = (labels) => (labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// Whether events[a] happened before events[b]: by created_at when both have
// one and they differ, else by their order as listed.
const before = (events, a, b) => {
  const [at, bt] = [Date.parse(events[a]?.created_at), Date.parse(events[b]?.created_at)];
  return Number.isFinite(at) && Number.isFinite(bt) && at !== bt ? at < bt : a < b;
};

// Whether an agent-ready removal still stands: the newest event `isRemoval`
// accepts has no `status: ready` add after it that `isMark` accepts (by
// default, any). A lane's escalation or a person's removal keeps the issue out
// until triage or a person marks it ready again. Pure.
export function removalStands(events, isRemoval, isMark = () => true) {
  const removals = events.flatMap((event, index) => (isRemoval(event, index) ? [index] : []));
  if (removals.length === 0) {
    return false;
  }
  const newest = removals.reduce((a, b) => (before(events, a, b) ? b : a));
  return !events.some(
    (event, index) => event?.event === "labeled" && String(event.label?.name).toLowerCase() === READY && isMark(event) && before(events, newest, index),
  );
}

// Why admission leaves an issue alone whatever its verdict, or null: it is
// already agent-ready, or its agent-ready was removed and no `status: ready`
// `isMark` accepts was added since (removalStands). Pure.
export function admissionSettled(labels, events, isMark) {
  if (labels.includes(AGENT_READY)) {
    return `already ${AGENT_READY}`;
  }
  if (removalStands(events, (event) => event?.event === "unlabeled" && event.label?.name === AGENT_READY, isMark)) {
    return `${AGENT_READY} was removed and ${READY} not added since`;
  }
  return null;
}

// {verdict: admit | refuse | wait | skip, reasons}. Pure.
export function decide({ issue, verdict, rules, parent, blockers, trustedCloses, pulls = [], events, spec, humans, appId, repository, webHosts }) {
  const labels = names(issue.labels);
  if (!labels.includes(READY)) {
    return { verdict: "skip", reasons: [`no ${READY}`] };
  }
  // Only the App's or a listed human's status: ready lifts a removal: the
  // App's agent-ready starts a credentialed run.
  const settled = admissionSettled(labels, events, (event) => humans.has(event.actor?.id) || (appId !== undefined && event.actor?.id === appId));
  if (settled) {
    return { verdict: "skip", reasons: [settled] };
  }

  const refuse = [];
  const author = issue.user?.id;
  if (!(humans.has(author) || (appId !== undefined && author === appId))) {
    refuse.push("the author is neither a listed human nor the lanes App");
  }
  const type = issue.type?.name ?? "none";
  const underParent = rules["types-under-parent"].includes(type);
  if (!underParent && !rules.types.includes(type) && !rules["types-parent-if-present"].includes(type)) {
    refuse.push(`type ${type} is not one of ${[...rules.types, ...rules["types-under-parent"], ...rules["types-parent-if-present"]].join(", ")}`);
  } else if (underParent || (rules["types-parent-if-present"].includes(type) && parent !== null)) {
    const parentOk =
      parent !== null && parent.state === "open" && humans.has(parent.user?.id) && !names(parent.labels).some((label) => PARENT_HOLDS.has(label));
    if (!parentOk) {
      refuse.push(`a ${type} needs an open parent issue a listed human filed that awaits no decision`);
    }
  }
  // The hold also stands when its newest event is a removal by neither a
  // listed human nor the lanes App.
  const untrustedEvent = (events ?? []).filter((event) => ["labeled", "unlabeled"].includes(event?.event) && event.label?.name === UNTRUSTED).at(-1);
  const removedByOther = untrustedEvent?.event === "unlabeled" && !humans.has(untrustedEvent.actor?.id) && !(appId !== undefined && untrustedEvent.actor?.id === appId);
  if (verdict.workClass === UNTRUSTED || names(issue.labels).includes(UNTRUSTED) || removedByOther) {
    refuse.push(`${UNTRUSTED} work needs a person`);
  }
  // Reasons the owner already settled without a person: they park the issue
  // at status: ready (a wait with no pull request), never needs-decision.
  const parked = [];
  if (verdict.dimensions?.size === "large" && !rules.sizes.includes("large")) {
    parked.push(`Size large: the split into sub-issues at intake is pending (owner Q93)`);
  } else if (!rules.sizes.includes(verdict.dimensions?.size)) {
    refuse.push(`Size ${verdict.dimensions?.size} is not one of ${rules.sizes.join(", ")}`);
  }
  if (!rules.uncertainty.includes(verdict.dimensions?.uncertainty)) {
    refuse.push(`Uncertainty ${verdict.dimensions?.uncertainty} is not one of ${rules.uncertainty.join(", ")}`);
  }
  // pr-verify judges a lane PR only against text a listed human wrote and
  // the refinement on their issue, so the criteria count only there, and it
  // stops on an issue with more comments than it reads (resolve-pr.mjs
  // linkedIssues).
  if ((spec?.commentCount ?? 0) > (spec?.comments?.length ?? 0)) {
    refuse.push(`it has ${spec.commentCount} comments, more than the ${SPEC_COMMENTS} pr-verify reads, so pr-verify cannot verify a pull request for it`);
  }
  const lines = trustedSpecTexts(spec, humans, appId).flatMap((text) => text.split("\n"));
  if (!hasTrustedCriteria(spec, humans, rules["task-list"], appId)) {
    refuse.push(noTrustedSpec(rules["task-list"]));
  }
  // A copied refinement breaks `://` and `www.` with a zero-width space so no
  // link renders; the check reads the URL as written.
  const unrunnable = unrunnableReason(unrunnableCriteria(lines.join("\n").replaceAll("\u200b", ""), rules["task-list"], webHosts));
  if (unrunnable) {
    refuse.push(unrunnable);
  }
  for (const label of rules["refuse-labels"]) {
    if (labels.includes(label)) {
      refuse.push(`it carries ${label}`);
    }
  }
  if (refuse.length > 0) {
    return { verdict: "refuse", reasons: [...refuse, ...parked] };
  }
  if (parked.length > 0) {
    return { verdict: "wait", reasons: parked, pulls: [] };
  }

  const wait = [];
  for (const blocker of blockers) {
    const done =
      blocker.state === "closed" &&
      // A merge counts only here: another repository's merge carries no trust check.
      (blocker.pull_request
        ? here(blocker.repository_url, repository) && Boolean(blocker.pull_request.merged_at)
        : trustedCloses.has(blockerKey(blocker, repository)));
    if (!done) {
      const name = here(blocker.repository_url, repository) ? `#${blocker.number}` : blockerKey(blocker, repository);
      wait.push(`blocker ${name} is not closed by a listed human or a merge`);
    }
  }
  for (const pull of pulls) {
    wait.push(`open pull request #${pull} is for it`);
  }
  if (wait.length > 0) {
    return { verdict: "wait", reasons: wait, pulls };
  }
  return { verdict: "admit", reasons: [] };
}

// A blocker's repository, `owner/name`, from its API URL, or null.
const repoOf = (url) => /\/repos\/([\w.-]+\/[\w.-]+)$/.exec(String(url ?? ""))?.[1]?.toLowerCase() ?? null;

// trustedCloses' key for a blocker: its number here, `owner/name#number` in
// another repository.
export const blockerKey = (blocker, repository) =>
  here(blocker.repository_url, repository) ? blocker.number : `${repoOf(blocker.repository_url)}#${blocker.number}`;

// Whether another repository's closed blocker issue was closed by a listed
// human, read fresh from that repository. A commit or merge there carries no
// trust check, as for a pull-request blocker. A read that fails leaves it
// blocking.
async function trustedElsewhere(github, blocker, humans) {
  const repo = repoOf(blocker.repository_url);
  if (repo === null || !/^[1-9][0-9]{0,9}$/.test(String(blocker.number))) {
    return false;
  }
  try {
    return humans.has((await github("GET", `/repos/${repo}/issues/${blocker.number}`))?.closed_by?.id);
  } catch {
    return false;
  }
}

async function parentOf(github, base) {
  try {
    return await github("GET", `${base}/parent`);
  } catch (error) {
    if (error?.status === 404) {
      return null;
    }
    throw error;
  }
}

// One App comment carrying ADMIT_MARKER, edited in place on a later run.
export async function sayWhy(github, repository, base, comments, text) {
  const body = `${ADMIT_MARKER}\n${text}`;
  const own = comments.find(
    (comment) => comment.user?.login === LANES_APP_LOGIN && String(comment.body ?? "").startsWith(ADMIT_MARKER),
  );
  if (own?.body === body) {
    return;
  }
  if (own) {
    await github("PATCH", `/repos/${repository}/issues/comments/${own.id}`, {
      body,
    });
  } else {
    await github("POST", `${base}/comments`, { body });
  }
}

// The body, the comment count and the first 100 comments, each with its
// author, last editor and edit time: the first 100 comments are what pr-verify
// reads, and it stops on an issue with more.
const SPEC_COMMENTS = 100;
const SPEC_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) {
    body lastEditedAt author { ...actor } editor { ...actor }
    comments(first: ${SPEC_COMMENTS}) { totalCount nodes { body lastEditedAt author { ...actor } editor { ...actor } } }
  } }
}
fragment actor on Actor { __typename ... on User { databaseId } ... on Bot { databaseId } }`;

// {body, lastEditedAt, author, editor, commentCount, comments: [{body,
// lastEditedAt, author, editor}]} for the issue, as GraphQL answers them. An
// unexpected shape throws.
export async function specOf(github, repository, number) {
  const [owner, name] = repository.split("/");
  const issue = (await github("POST", "/graphql", { query: SPEC_QUERY, variables: { owner, name, number: Number(number) } }))?.data?.repository?.issue;
  const text = (item) =>
    item !== null && typeof item === "object" && typeof item.body === "string" && (item.lastEditedAt === null || typeof item.lastEditedAt === "string");
  if (!text(issue) || !Array.isArray(issue.comments?.nodes) || !issue.comments.nodes.every(text) || !Number.isSafeInteger(issue.comments.totalCount)) {
    throw new Error("the issue's text, authors and edit times have an unexpected shape");
  }
  const { body, lastEditedAt, author, editor } = issue;
  return { body, lastEditedAt, author, editor, commentCount: issue.comments.totalCount, comments: issue.comments.nodes };
}

export const noTrustedSpec = (taskList) =>
  `no trusted-human acceptance criteria: a listed human must put the confirmed \`${taskList.trim()}\` criteria in the body or post them as their own comment, or, on an issue a listed human filed, intake's newest refinement comment must hold them unedited`;

// The one comment of the lanes App's (a Bot whose id is `appId`) that counts
// as spec, or undefined: the newest that opens with REFINE_MARKER, and only
// while never edited; an older one never stands in for it. `comments` are in
// GraphQL order, oldest first. The caller checks the body a listed human
// wrote; resolve-pr.mjs linkedIssues shares this rule and also requires the
// comment to predate the pull request. Pure.
export function refinementSpec(comments, appId) {
  const newest = (comments ?? []).findLast(
    (comment) =>
      appId !== undefined &&
      comment?.author?.__typename === "Bot" &&
      comment.author.databaseId === appId &&
      String(comment.body ?? "").startsWith(REFINE_MARKER),
  );
  return newest?.lastEditedAt == null ? newest : undefined;
}

// The texts pr-verify will read as spec: the body and each comment written,
// and last edited if ever, by a User among `humans`, and, when the body is
// such text, the lanes App's refinement (refinementSpec)
// (.github/scripts/pr-verify/resolve-pr.mjs linkedIssues). No other Bot or
// App text counts. Pure.
export function trustedSpecTexts(spec, humans, appId) {
  const trusted = (actor) => actor?.__typename === "User" && humans.has(actor.databaseId);
  const written = (item) => trusted(item?.author) && (item.lastEditedAt == null || trusted(item.editor));
  if (!spec) {
    return [];
  }
  const refinement = written(spec) ? refinementSpec(spec.comments, appId) : undefined;
  return [spec, ...(spec.comments ?? [])].filter((item) => written(item) || item === refinement).map((item) => String(item.body ?? ""));
}

const hasTaskLine = (text, taskList) =>
  String(text ?? "")
    .split("\n")
    .some((line) => line.trimStart().startsWith(taskList));

// Whether that text holds a `taskList` line: criterion 7. Pure.
export const hasTrustedCriteria = (spec, humans, taskList, appId) =>
  trustedSpecTexts(spec, humans, appId).some((text) => hasTaskLine(text, taskList));

// For an issue apply-verdict held without admission (a flag, an escalation or
// a hold), the same split note a refusal posts, when a done-when item is one
// the lane cannot perform, so the split survives a verdict that never reaches
// decide(). It skips where decide() does (admissionSettled), and leaves an
// unchanged note alone. Returns {outcome: noted | none | skipped, reasons}.
export async function noteUnrunnable({ github, repository, issue, rules, webHosts, log = console.log }) {
  const base = `/repos/${repository}/issues/${issue.number}`;
  const reason = unrunnableReason(unrunnableCriteria(issue.body, rules["task-list"], webHosts));
  if (!reason) {
    return { outcome: "none", reasons: [] };
  }
  const settled = admissionSettled(names(issue.labels), await paginate(github, `${base}/events`));
  if (settled) {
    log(`admit: #${issue.number} left as is (${settled})`);
    return { outcome: "skipped", reasons: [settled] };
  }
  await sayWhy(github, repository, base, await paginate(github, `${base}/comments`), `Not admitted to the issue lane: ${reason}.`);
  log(`admit: #${issue.number} held; split noted (${reason})`);
  return { outcome: "noted", reasons: [reason] };
}

// Every fact decide() reads but the verdict, the rules and the caller's own
// (humans, appId, repository, webHosts), for `issue` as just read.
// `isTrusted(number)` answers whether a closed blocker's close counts; by
// default it reads the blocker fresh.
export async function admissionFacts({ github, repository, number, issue, rules, humans, isTrusted }) {
  const base = `/repos/${repository}/issues/${number}`;
  const blockers = await paginate(github, `${base}/dependencies/blocked_by`);
  // Anyone may close their own issue, so a blocking issue counts only with a
  // trusted close, read fresh from the issue; one closed as not planned or a
  // duplicate counts too, since nothing is left to wait for. `isTrusted`
  // answers for this repository's blockers only.
  const trusted =
    isTrusted ?? (async (blocker) => isTrustedClose(github, repository, await github("GET", `/repos/${repository}/issues/${blocker}`), humans));
  const trustedCloses = new Set();
  for (const blocker of blockers) {
    if (!blocker.pull_request && blocker.state === "closed") {
      const ok = here(blocker.repository_url, repository) ? await trusted(blocker.number) : await trustedElsewhere(github, blocker, humans);
      if (ok) {
        trustedCloses.add(blockerKey(blocker, repository));
      }
    }
  }
  // A throw here stops the caller before decide(), so nothing is written.
  const spec = await specOf(github, repository, number);
  return {
    issue,
    // Read for the admission comment's own earlier copy (sayWhy).
    comments: await paginate(github, `${base}/comments`),
    spec,
    parent: [...rules["types-under-parent"], ...rules["types-parent-if-present"]].includes(issue.type?.name) ? await parentOf(github, base) : null,
    blockers,
    trustedCloses,
    pulls: await openPullsFor(github, repository, number),
    events: await paginate(github, `${base}/events`),
  };
}

// Whether an open issue created before `issue` carries admission-deferred:
// one search. An unreadable or incomplete answer counts as one, since the
// sweep admits deferred issues oldest first anyway. It counts every older
// deferred issue, including one the sweep keeps deferred for an open pull
// request or an untrusted label; that costs a newer issue at most one hourly
// sweep's wait, never a stall, and reading each one's events to tell them
// apart would cost a call per deferred issue.
async function deferredAhead(github, repository, issue) {
  const created = Date.parse(issue.created_at);
  if (!Number.isFinite(created)) {
    return true;
  }
  const before = new Date(created).toISOString().replace(/\.\d{3}Z$/, "+00:00");
  const q = `repo:${repository} is:issue is:open label:${DEFERRED} created:<${before}`;
  try {
    const answer = await github("GET", `/search/issues?q=${encodeURIComponent(q)}&per_page=1`);
    return answer?.incomplete_results !== false || answer.total_count !== 0;
  } catch {
    return true;
  }
}

// Whether work-unblock's sweep (label-unblocked.mjs readiness) counts every
// blocker as decide() does: a merged pull request or an issue closed as
// completed, in this repository. It drops the deferral of an issue with any
// other blocker without admitting it, so such an issue is never deferred:
// with room it is admitted, and with none it waits with a comment. Pure.
const sweepCounts = (blockers, repository) =>
  blockers.every(
    (blocker) =>
      blocker.state === "closed" &&
      here(blocker.repository_url, repository) &&
      (blocker.pull_request ? Boolean(blocker.pull_request.merged_at) : blocker.state_reason === "completed"),
  );

// Reads the issue fresh, decides, and writes. `status` answers check-wip-cap's
// status for the issue lane. Returns {outcome, reasons}.
export async function admit({ github, repository, number, verdict, rules, humans, appId, status, webHosts, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const facts = await admissionFacts({ github, repository, number, issue, rules, humans });
  const { comments } = facts;
  const decision = decide({
    ...facts,
    verdict,
    rules,
    humans,
    appId,
    repository,
    webHosts,
  });
  const reasons = decision.reasons.join("; ");
  const undefer = async () => {
    if (names(issue.labels).includes(DEFERRED)) {
      await github("DELETE", `${base}/labels/${DEFERRED}`);
    }
  };
  if (decision.verdict === "skip") {
    log(`admit: #${number} left as is (${reasons})`);
    return { outcome: "skipped", reasons: decision.reasons };
  }
  if (decision.verdict === "refuse") {
    // The hold before status: ready comes off: a failed write never leaves
    // admission-deferred on an issue with neither, which the sweep admits.
    await github("POST", `${base}/labels`, { labels: [NEEDS_DECISION] });
    await github("DELETE", `${base}/labels/${encodeURIComponent(READY)}`);
    await undefer();
    await sayWhy(github, repository, base, comments, refusalText(reasons));
    log(`admit: #${number} refused (${reasons})`);
    return { outcome: "refused", reasons: decision.reasons };
  }
  if (decision.verdict === "wait") {
    if (decision.pulls.length === 0) {
      await undefer();
    } else if (!names(issue.labels).includes(DEFERRED)) {
      await github("POST", `${base}/labels`, { labels: [DEFERRED] });
    }
    await sayWhy(github, repository, base, comments, `Not admitted to the issue lane yet: ${reasons}.`);
    log(`admit: #${number} waits (${reasons})`);
    return { outcome: "waiting", reasons: decision.reasons };
  }
  const s = await status();
  const full = s.paused || !s.admission_open || (s.admission_room ?? 1) <= 0;
  const counted = sweepCounts(facts.blockers, repository);
  if (full || (counted && (await deferredAhead(github, repository, issue)))) {
    const why = !full
      ? `an older ${DEFERRED} issue is ahead of it`
      : s.paused
        ? `the lane is paused (${s.pause_reason})`
        : `admissions are closed (${s.admission_reason})`;
    if (!counted) {
      // The sweep would drop the deferral without admitting it: say so
      // instead of deferring.
      await undefer();
      const reason = `${why}, and the hourly sweep cannot admit it, since it counts only blockers closed as completed or merged in this repository`;
      await sayWhy(github, repository, base, comments, `Not admitted to the issue lane yet: ${reason}.`);
      log(`admit: #${number} waits (${reason})`);
      return { outcome: "waiting", reasons: [reason] };
    }
    await github("POST", `${base}/labels`, { labels: [DEFERRED] });
    log(`admit: #${number} deferred: ${why}`);
    return { outcome: "deferred", reasons: [why] };
  }
  await github("POST", `${base}/labels`, { labels: [AGENT_READY] });
  log(`admit: #${number} labeled ${AGENT_READY}`);
  return { outcome: "admitted", reasons: [] };
}
