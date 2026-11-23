import { createHash } from "node:crypto";
import { isDeepStrictEqual } from "node:util";

import { paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { subIssueLeftOpen } from "../lib/done-evidence.mjs";
import { baseAdmissionRules, countedRefinement, here, humanActor, names, parentOf, personChecks, RECURRING, repoOf, specOf, taskItems, taskLinesOf, trustedTaskLines, withoutItems } from "./admit.mjs";

export const SIZE_SPLIT_MARKER = "<!-- intake-triage size-split -->";
export const SPLIT_CHILD_MARKER = "<!-- intake-triage size-split child -->";

export async function splitParentOf(github, repository, parent, appId) {
  if (parent === null || !here(parent.repository_url, repository) || !Number.isInteger(parent.number)) {
    return undefined;
  }
  return { number: parent.number, spec: await specOf(github, repository, parent.number), appId };
}

export async function trustedSplitChild(github, repository, number, humans, appId, taskList) {
  const spec = await specOf(github, repository, number);
  if (appId === undefined || spec.author?.__typename !== "Bot" || spec.author.databaseId !== appId || !spec.body.startsWith(SPLIT_CHILD_MARKER)) {
    return false;
  }
  const parent = await splitParentOf(github, repository, await parentOf(github, `/repos/${repository}/issues/${Number(number)}`), appId);
  return parent !== undefined && splitChildBody({ ...spec, splitParent: parent }, humans, taskList) !== null;
}

export function splitTaskLines(spec, humans, taskList, appId, webHosts) {
  const moved = personChecks(spec, humans, appId, taskList, webHosts);
  const own = trustedTaskLines(moved.length > 0 ? { ...spec, body: withoutItems(spec.body, taskList, moved) } : spec, humans, taskList);
  const refinement = countedRefinement(spec, humans, appId);
  const usable = Number.isSafeInteger(refinement?.databaseId) && typeof refinement.updatedAt === "string";
  const more = usable ? taskLinesOf(refinement.body, taskList) : [];
  return { lines: [...own, ...more], human: own.length, source: more.length > 0 ? { id: refinement.databaseId, updatedAt: refinement.updatedAt } : null };
}

export const splitSourceLine = ({ id, updatedAt }) => `<!-- size-split refinement=${id} updated_at=${updatedAt} -->`;
const SOURCE = /^<!-- size-split refinement=([1-9][0-9]{0,15}) updated_at=([0-9A-Za-z:.+-]{1,40}) -->$/;

export const splitChildHeader = (parent, part, parts, source = null, scoped = false) =>
  [
    SPLIT_CHILD_MARKER,
    `Part ${part} of ${parts} of #${parent}, split at intake (owner Q93). ${scoped ? "The done-when lines below are" : "The done-when below is"} copied from #${parent}${source ? " and intake's refinement comment on it" : ""} as written${scoped ? ", and the Scope line names the targets this part covers" : ""}.`,
    ...(source ? [splitSourceLine(source)] : []),
    "",
    "## Done when",
    "",
  ].join("\n");

export function splitChildBody(spec, humans, taskList) {
  const parent = spec?.splitParent;
  const author = spec?.author;
  if (typeof taskList !== "string" || taskList === "" || parent?.appId === undefined || !Number.isInteger(parent.number) || author?.__typename !== "Bot" || author.databaseId !== parent.appId) {
    return null;
  }
  const human = humanActor(humans);
  const edited = spec.lastEditedAt != null;
  if (!human(parent.spec?.author) || (edited && !human(spec.editor))) {
    return null;
  }
  const body = String(spec.body ?? "");
  const rows = body.split("\n");
  const part = /^Part ([1-9][0-9]?) of ([1-9][0-9]?) of #/.exec(rows[1] ?? "");
  const tag = SOURCE.exec(rows[2] ?? "");
  const source = tag ? { id: Number(tag[1]), updatedAt: tag[2] } : null;
  const scoped = rows.at(-1).startsWith(SCOPE_PREFIX);
  const header = part ? `${splitChildHeader(parent.number, Number(part[1]), Number(part[2]), source, scoped)}\n` : null;
  if (header === null || !body.startsWith(header)) {
    return null;
  }
  let refinement = [];
  if (source !== null) {
    const comments = parent.spec?.comments ?? [];
    const whole = (parent.spec?.commentCount ?? comments.length) === comments.length;
    const newest = whole ? countedRefinement(parent.spec, humans, parent.appId) : undefined;
    if (newest?.databaseId !== source.id || typeof newest.updatedAt !== "string" || !(newest.updatedAt === newest.createdAt || newest.updatedAt === source.updatedAt)) {
      return null;
    }
    refinement = taskLinesOf(newest.body, taskList);
  }
  const exact = [...trustedTaskLines(parent.spec, humans, taskList), ...refinement];
  const allowed = new Set(edited ? exact.flatMap((line) => [line, ...tickedForms(line, taskList)]) : exact);
  const lines = body.slice(header.length).split("\n");
  const scope = lines.at(-1)?.startsWith(SCOPE_PREFIX) ? scopeTargets(lines.pop(), exact.map((line) => taskText(line, taskList))) : [];
  return scope !== null && lines.length > 0 && lines.every((line) => allowed.has(line)) ? body : null;
}

export const SCOPE_PREFIX = "Scope: ";

export const taskText = (line, taskList) => line.trimStart().slice(taskList.length);

export const scopeTarget = (name, texts) =>
  typeof name === "string" && name.length >= 2 && name.length <= 100 && name.trim() === name && !/[,<>`@#\r\n]/.test(name) && texts.some((text) => text.includes(name));

export function splitScope(body) {
  const last = String(body ?? "").split("\n").at(-1);
  return last.startsWith(SCOPE_PREFIX) ? last.slice(SCOPE_PREFIX.length).split(", ") : null;
}

function scopeTargets(line, texts) {
  const names = splitScope(line);
  return new Set(names).size === names.length && names.every((name) => scopeTarget(name, texts)) ? names : null;
}

const tickedForms = (line, taskList) => {
  if (taskList.split("[ ]").length !== 2) {
    return [];
  }
  const indent = line.slice(0, line.length - line.trimStart().length);
  return ["[x]", "[X]"].map((box) => indent + taskList.replace("[ ]", box) + taskText(line, taskList));
};

export const linesDigest = (lines) => createHash("sha256").update(JSON.stringify(lines)).digest("hex");
const RECORD = /^<!-- size-split items=([0-9a-f]{64}) parts=([0-9,;]+) order=([0-9>,]*) filed=([0-9,]*)(?: groups=([A-Za-z0-9_-]{1,8000}))? -->$/;
const numbers = (text, separator) => (text === "" ? [] : text.split(separator).map(Number));

export const renderSplitRecord = ({ items, parts, order, filed = [], groups }) =>
  `<!-- size-split items=${items} parts=${parts.map((part) => part.join(",")).join(";")} order=${order.map(([a, b]) => `${a}>${b}`).join(",")} filed=${filed.join(",")}${groups ? ` groups=${Buffer.from(JSON.stringify(groups)).toString("base64url")}` : ""} -->`;

const decodeGroups = (text) => {
  try {
    const groups = JSON.parse(Buffer.from(text, "base64url").toString("utf8"));
    return Array.isArray(groups) && groups.every((group) => Array.isArray(group) && group.every((name) => typeof name === "string")) ? groups : null;
  } catch {
    return null;
  }
};

export function splitRecord(body) {
  const lines = String(body ?? "").split("\n");
  const match = lines[0] === SIZE_SPLIT_MARKER ? RECORD.exec(lines[1] ?? "") : null;
  if (!match) {
    return null;
  }
  return {
    items: match[1],
    parts: match[2].split(";").map((part) => numbers(part, ",")),
    order: match[3] === "" ? [] : match[3].split(",").map((pair) => pair.split(">").map(Number)),
    filed: numbers(match[4], ","),
    ...(match[5] !== undefined && { groups: decodeGroups(match[5]) }),
  };
}

const baseTaskList = () => baseAdmissionRules()["task-list"];

const filedRecord = (comments, isApp) =>
  comments
    .filter((comment) => isApp(comment.user))
    .map((comment) => ({ ...splitRecord(comment.body), at: comment.created_at }))
    .find((record) => (record.filed?.length ?? 0) > 0);

const citesChild = (children, repository) => {
  const bare = (text) => String(text ?? "").replaceAll(/[*()[\]`.,;:!]/g, " ").replaceAll(/\s+/g, " ").trim().toLowerCase();
  const titles = new Map(
    children.filter((child) => here(child?.repository_url, repository)).map((child) => [Number(child?.number), bare(String(child?.title ?? "").replace(/^\w+(?:\([^)]*\))?!?:\s*/, ""))]),
  );
  return (item) =>
    item.more.length === 0 &&
    [/^\s*(?:\*\*)?\(?#(\d+)\b/, /(?<![\w/#=?&])#(\d+)\)?[.;]?\s*$/].some((pattern) => {
      const match = pattern.exec(item.text);
      const title = titles.get(Number(match?.[1]));
      const rest = match ? bare(`${item.text.slice(0, match.index)} ${item.text.slice(match.index + match[0].length)}`) : null;
      return title !== undefined && (rest === "" || rest === title);
    });
};

export async function isSplitParent({ github, repository, issue, comments, children, isApp, humans }) {
  if (filedRecord(comments, isApp)) {
    return true;
  }
  if (children.length === 0 || names(issue.labels).includes(RECURRING)) {
    return false;
  }
  if (!taskItems(issue.body, baseTaskList()).every(citesChild(children, repository))) {
    return false;
  }
  const linker = new Map();
  const events = await paginate(github, `/repos/${repository}/issues/${issue.number}/events`);
  for (const event of events.filter((item) => item?.event === "sub_issue_added")) {
    const key = `${String(event.sub_issue?.repository?.full_name).toLowerCase()}#${event.sub_issue?.number}`;
    const newest = linker.get(key);
    if (newest === undefined || !(Date.parse(event.created_at) < Date.parse(newest.created_at))) {
      linker.set(key, event);
    }
  }
  return children.every((child) => {
    const actor = linker.get(`${repoOf(child?.repository_url)}#${child?.number}`)?.actor;
    return actor !== undefined && (isApp(actor) || humans.has(actor?.id));
  });
}

export async function splitLeftOpen({ github, repository, issue, comments, children, isApp, humans, trusted }) {
  if (children.length === 0 || !(await isSplitParent({ github, repository, issue, comments, children, isApp, humans }))) {
    return "it is not a split parent";
  }
  const childLeft = await subIssueLeftOpen(children, trusted, repository);
  if (childLeft) {
    return childLeft;
  }
  const taskList = baseTaskList();
  const record = filedRecord(comments, isApp);
  if (record) {
    const items = new Set(record.parts.flat());
    const listed = new Set(children.map((child) => Number(child?.number)));
    if (items.size !== Math.max(...items) || items.has(0) || record.parts.length !== record.filed.length || !record.filed.every((number) => listed.has(number)) || taskItems(issue.body, taskList).length > items.size) {
      return "its split record does not cover every item with its sub-issues";
    }
  } else if (!["[ ]", "[x]", "[X]"].some((box) => taskItems(issue.body, taskList.replace("[ ]", box)).length > 0)) {
    return "its body has no task list a sub-issue can cover";
  }
  const cites = citesChild(children, repository);
  const split = Date.parse(record?.at);
  const beforeSplit = (comment) => Date.parse(comment.updated_at ?? comment.created_at) <= split;
  if (comments.some((comment) => humans.has(comment.user?.id) && !beforeSplit(comment) && !taskItems(comment.body, taskList).every(cites))) {
    return "a listed human's comment leaves an open task item on it";
  }
  return null;
}

export async function splitParentClosed({ github, repository, issue, isApp, humans, trusted }) {
  if (issue?.state !== "closed" || issue.state_reason !== "completed" || !isApp(issue.closed_by) || !Number.isInteger(issue.number)) {
    return false;
  }
  const base = `/repos/${repository}/issues/${issue.number}`;
  const children = await paginate(github, `${base}/sub_issues`);
  return (await splitLeftOpen({ github, repository, issue, comments: await paginate(github, `${base}/comments`), children, isApp, humans, trusted })) === null;
}

export const splitDigest = ({ lines, source }) => linesDigest(source === null ? lines : [...lines, splitSourceLine(source)]);

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

function orderProblem(order, count) {
  const pairs = new Set();
  if (!Array.isArray(order)) {
    return "order must be a list of pairs";
  }
  for (const pair of order) {
    const valid = Array.isArray(pair) && pair.length === 2 && pair.every((p) => Number.isInteger(p) && p >= 1 && p <= count) && pair[0] !== pair[1];
    if (!valid || pairs.has(pair.join(">"))) {
      return "each order pair must name two different parts, once";
    }
    pairs.add(pair.join(">"));
  }
  const waits = Array.from({ length: count }, (_, index) => order.filter(([, b]) => b === index + 1).length);
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
  return done === count ? null : "the order has a cycle";
}
