import { parseLaneBranch } from "../lib/lane-branch.mjs";
import { isMergeRiskTitle, mergeRiskTitle } from "../lib/run-title.mjs";
import { ofOrigin } from "../pr-verify/resolve-pr.mjs";

export const RATING_WORKFLOW_PATH = ".github/workflows/pr-rate-merge-risk.yml";
export const ARTIFACT_PREFIX = "pr-merge-risk";
export const RATING_FILE = "rating.json";
export const LEVELS = Object.freeze(["LOW", "MEDIUM", "HIGH", "CRITICAL"]);
export const CHECKS = Object.freeze(["agreed", "disputed", "added", "unchecked"]);
export const REASONS = Object.freeze(["pending", "no-run", "no-rating", "invalid", "unreadable", "over-budget"]);
export const runTitle = mergeRiskTitle;
export const artifactName = (pr, head) => `${ARTIFACT_PREFIX}-${pr}-${head}`;

const SHA = /^[0-9a-f]{40}$/;
const VERSION = /^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$/;
const MODEL = /^(claude-[a-z0-9]+(?:-[a-z0-9]+){0,6}(?:\[1m\])?|unknown|none)$/;
const MAX_ROWS = 20;
const AREA_MAX = 200;
const TEXT_MAX = 4000;

export class InvalidRating extends Error {}

const refuse = (why) => {
  throw new InvalidRating(why);
};
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const rank = (level) => LEVELS.indexOf(level);

function checkRow(row, index) {
  if (!isObject(row)) refuse(`row ${index} is not an object`);
  const { area, level, why, check, checker_level: checkerLevel = "", checker = "" } = row;
  if (typeof area !== "string" || area.trim() === "" || area.length > AREA_MAX) refuse(`row ${index} has no area`);
  if (!LEVELS.includes(level)) refuse(`row ${index} has no level`);
  if (typeof why !== "string" || why.length > TEXT_MAX) refuse(`row ${index} has no why`);
  if (!CHECKS.includes(check)) refuse(`row ${index} has no check`);
  if (checkerLevel !== "" && !LEVELS.includes(checkerLevel)) refuse(`row ${index} has a bad checker_level`);
  if (typeof checker !== "string" || checker.length > TEXT_MAX) refuse(`row ${index} has a bad checker`);
  return { area, level, why, check, checker_level: checkerLevel, checker };
}

export function checkResult(value, { pr, head }) {
  if (!isObject(value)) refuse("the result is not an object");
  if (!SHA.test(String(head)) || value.head !== head) refuse("the result names another head");
  if (value.pr !== pr) refuse("the result names another pull request");
  if (!Array.isArray(value.risks) || value.risks.length === 0 || value.risks.length > MAX_ROWS) refuse("the result has no rows");
  if (typeof value.demote !== "boolean") refuse("the result has no demote");
  const risks = value.risks.map(checkRow);
  const max = LEVELS[Math.max(...risks.flatMap((row) => [rank(row.level), rank(row.checker_level)]))];
  return { pr, head, risks, max, demote: rank(max) >= rank("HIGH") };
}

export function checkRating(value, { pr, head }) {
  const checked = checkResult(value, { pr, head });
  if (!VERSION.test(String(value.rubric ?? ""))) refuse("the rating has no rubric version");
  if (!MODEL.test(String(value.rater ?? "")) || !MODEL.test(String(value.checker ?? ""))) refuse("the rating has a bad model id");
  return { ...checked, rubric: value.rubric, rater: value.rater, checker: value.checker };
}

export function modelsOf(messages, checkerModel) {
  const list = Array.isArray(messages) ? messages : [];
  const checkers =
    typeof checkerModel === "string"
      ? new Set(
          list
            .filter((message) => message?.type === "assistant" && !message.parent_tool_use_id && Array.isArray(message.message?.content))
            .flatMap((message) => message.message.content.filter((block) => block?.type === "tool_use" && block.name === "Agent" && (block.input?.model ?? "") === checkerModel).map((block) => block.id)),
        )
      : undefined;
  const counts = (sub) => {
    const seen = new Map();
    for (const message of list) {
      if (message?.type !== "assistant" || Boolean(message.parent_tool_use_id) !== sub) continue;
      if (sub && checkers && !checkers.has(message.parent_tool_use_id)) continue;
      const model = message.message?.model;
      if (typeof model === "string") seen.set(model, (seen.get(model) ?? 0) + 1);
    }
    return [...seen].sort((a, b) => b[1] - a[1])[0]?.[0];
  };
  const id = (model, none) => (model === undefined ? none : MODEL.test(model) && model !== "none" && model !== "unknown" ? model : "unknown");
  return { rater: id(counts(false), "unknown"), checker: id(counts(true), "none") };
}

export const ratedLine = (rating) =>
  `Merge-Risk: max=${rating.max} demote=${rating.demote} head=${rating.head} rubric=${rating.rubric} rater=${rating.rater} checker=${rating.checker}`;

export function unratedLine(reason) {
  if (!REASONS.includes(reason)) refuse(`unrated reason ${reason} is not in the closed set`);
  return `Merge-Risk: unrated reason=${reason}`;
}

const unrated = (reason) => ({ line: unratedLine(reason), token: `unrated:${reason}` });

export const MERGE_RISK_MARKER = "merge-risk-line";
const LANE = "[a-z][a-z0-9-]{0,63}";
const RUN = "[1-9][0-9]{0,19}";
const MARKER_LINE = new RegExp(`^<!-- ${MERGE_RISK_MARKER} head=([0-9a-f]{40})(?: lane=${LANE} run=${RUN})? -->$`);

export function producerOf(branch) {
  const match = parseLaneBranch(branch, { lanePattern: LANE, runPattern: RUN });
  return match ? { lane: match.lane, run: match.run } : null;
}

export const markerBody = (head, line, producer = null) =>
  `<!-- ${MERGE_RISK_MARKER} head=${head}${producer ? ` lane=${producer.lane} run=${producer.run}` : ""} -->\n${line}`;

const isRated = (line) => String(line ?? "").startsWith("Merge-Risk: max=");

export function markerAction(comments, { bot, head, line, producer = null }) {
  const isApp = (actor) => actor?.__typename === "Bot" && actor.login === bot;
  const newest = (Array.isArray(comments) ? comments : [])
    .filter((c) => isApp(c?.author) && MARKER_LINE.test(String(c.body ?? "").split(/\r?\n/)[0]))
    .sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)))
    .at(-1);
  if (newest === undefined || (newest.lastEditedAt && !isApp(newest.editor)) || MARKER_LINE.exec(String(newest.body).split(/\r?\n/)[0])[1] !== head) return { action: "post" };
  const body = String(newest.body).replace(/\r\n/g, "\n");
  if (body === markerBody(head, line, producer) || (isRated(body.split("\n")[1]) && !isRated(line))) return { action: "none" };
  return Number.isSafeInteger(newest.databaseId) ? { action: "patch", id: newest.databaseId } : { action: "post" };
}

export async function readRating({ actions, download, repository, pr, head, base = "main" }) {
  const name = artifactName(pr, head);
  let text;
  try {
    let found;
    const listed = (await actions("GET", `/repos/${repository}/actions/artifacts?name=${encodeURIComponent(name)}&per_page=100`))?.artifacts ?? [];
    const candidates = listed.filter((item) => item?.name === name && item.expired === false && Number.isSafeInteger(item.workflow_run?.id) && Number.isSafeInteger(item.id)).sort((a, b) => b.id - a.id);
    for (const artifact of candidates) {
      const run = await actions("GET", `/repos/${repository}/actions/runs/${artifact.workflow_run.id}`);
      if (run?.id === artifact.workflow_run.id && ofOrigin(run, { path: RATING_WORKFLOW_PATH, repository, base })) {
        found = artifact;
        break;
      }
    }
    if (found === undefined) {
      const runs = (await actions("GET", `/repos/${repository}/actions/workflows/${RATING_WORKFLOW_PATH.split("/").at(-1)}/runs?event=workflow_run&branch=${base}&per_page=100`))?.workflow_runs ?? [];
      const mine = runs.filter((run) => isMergeRiskTitle(run?.display_title, pr, head) && ofOrigin(run, { path: RATING_WORKFLOW_PATH, repository, base }));
      return unrated(mine.length === 0 ? "no-run" : mine.some((run) => run.status !== "completed") ? "pending" : "no-rating");
    }
    text = await download(found.id);
  } catch {
    return unrated("unreadable");
  }
  try {
    return { line: ratedLine(checkRating(JSON.parse(text), { pr, head })), token: "rated" };
  } catch {
    return unrated("invalid");
  }
}

const within = (promise, ms, fallback) => {
  let timer;
  return Promise.race([Promise.resolve(promise).catch(() => fallback), new Promise((resolve) => (timer = setTimeout(resolve, ms, fallback)))]).finally(() => clearTimeout(timer));
};

export async function recordMergeRisk({ pull, comments, repository, actions, github, download, bot, readMs = 15_000, writeMs = 5_000, now = Date.now }) {
  const started = now();
  const result = { token: "unrated:unreadable", wrote: false, skipped: undefined, readMs: 0 };
  try {
    const pr = pull?.number;
    const head = pull?.headRefOid;
    if (!Number.isSafeInteger(pr) || pr < 1 || !SHA.test(String(head))) {
      result.skipped = "no-pull";
      return result;
    }
    const read = await within(
      readRating({ actions, download, repository, pr, head }).catch(() => unrated("unreadable")),
      readMs,
      unrated("over-budget"),
    );
    result.token = read.token;
    result.readMs = now() - started;
    const wrote = await within(
      (async () => {
        const producer = producerOf(pull.headRefName);
        const next = markerAction(comments, { bot, head, line: read.line, producer });
        if (next.action === "none") return "exact";
        const body = markerBody(head, read.line, producer);
        if (next.action === "patch") await github("PATCH", `/repos/${repository}/issues/comments/${next.id}`, { body });
        else await github("POST", `/repos/${repository}/issues/${pr}/comments`, { body });
        return "wrote";
      })(),
      writeMs,
      "write-failed",
    );
    result.wrote = wrote === "wrote";
    result.skipped = wrote === "wrote" ? undefined : wrote;
  } catch {
    result.skipped ??= "write-failed";
  }
  return result;
}
