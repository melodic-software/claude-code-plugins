// The report-only Merge-Risk line (#13657, owner decision Q57): the rating
// pr-rate-merge-risk.yml uploaded for the head an arm is about to arm, written
// as the pull request body's last line so the squash commit carries it.
//
//   Merge-Risk: max=<level> demote=<bool> head=<sha> rubric=<version> rater=<model> checker=<model>
//   Merge-Risk: unrated reason=<pending|no-run|no-rating|invalid|unreadable|over-budget>
//
// No gate, hold or rung reads it. Every field is a closed value, a validated
// SHA, version or model id, never text the pull request's author wrote, so
// it can never read as a hold (merge-holds.mjs BODY_HOLD, LANE_HOLD) or wrap
// into a squash line that starts `committer ` (pr-require-checks.yml).
// recordMergeRisk never throws and is bounded in time, so a missing or failed
// rating never blocks or delays the arm.
//
// The rating artifact is untrusted on read: its shape is checked again, and
// max and demote are recomputed from its rows, never taken from it.
// write-rating.mjs runs the same checks on the skill's result before upload.

import { ofOrigin } from "../pr-verify/resolve-pr.mjs";

export const RATING_WORKFLOW_PATH = ".github/workflows/pr-rate-merge-risk.yml";
export const ARTIFACT_PREFIX = "pr-merge-risk";
export const RATING_FILE = "rating.json";
export const LEVELS = Object.freeze(["LOW", "MEDIUM", "HIGH", "CRITICAL"]);
export const CHECKS = Object.freeze(["agreed", "disputed", "added", "unchecked"]);
export const REASONS = Object.freeze(["pending", "no-run", "no-rating", "invalid", "unreadable", "over-budget"]);
// The run-name pr-rate-merge-risk.yml gives each run, so a run still going
// can be told apart for its pull request and head.
export const runTitle = (pr, head) => `merge-risk #${pr} ${head}`;
export const artifactName = (pr, head) => `${ARTIFACT_PREFIX}-${pr}-${head}`;

const SHA = /^[0-9a-f]{40}$/;
const VERSION = /^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$/;
// A model id as the CLI reports it, or one of the closed stand-ins.
const MODEL = /^(claude-[a-z0-9]+(?:-[a-z0-9]+){0,6}(?:\[1m\])?|unknown|none)$/;
const MAX_ROWS = 20;
const AREA_MAX = 200;
const TEXT_MAX = 4000;
const LINE = /^Merge-Risk:.*$/;

export class InvalidRating extends Error {}

const refuse = (why) => {
  throw new InvalidRating(why);
};
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const rank = (level) => LEVELS.indexOf(level);

// One row of the skill's result, or a refusal.
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

// The skill's result block (merge-risk SKILL.md step 5) for `pr` at `head`,
// with max and demote recomputed from the rows: the highest of every row's
// level and checker_level, and demote when that is HIGH or CRITICAL.
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

// rating.json as write-rating.mjs wrote it, checked as checkResult checks the
// result, plus the fields the line takes.
export function checkRating(value, { pr, head }) {
  const checked = checkResult(value, { pr, head });
  if (!VERSION.test(String(value.rubric ?? ""))) refuse("the rating has no rubric version");
  if (!MODEL.test(String(value.rater ?? "")) || !MODEL.test(String(value.checker ?? ""))) refuse("the rating has a bad model id");
  return { ...checked, rubric: value.rubric, rater: value.rater, checker: value.checker };
}

// The rater's and checker's model ids from run-claude-cli's execution file:
// the main thread's most frequent assistant model, and a subagent's (a
// message with a parent_tool_use_id). `none` when no subagent ran, `unknown`
// for an id the pattern refuses.
export function modelsOf(messages) {
  const counts = (sub) => {
    const seen = new Map();
    for (const message of Array.isArray(messages) ? messages : []) {
      if (message?.type !== "assistant" || Boolean(message.parent_tool_use_id) !== sub) continue;
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

const FENCE = /^ {0,3}(`{3,}|~{3,})/;

// `body` with `line` as its last line. Only what this writes is replaced: the
// trailing run of Merge-Risk lines at the body's end, outside any fence, with
// the blank lines before it. A Merge-Risk line anywhere else, a fenced
// example of the format included, is the author's text and stays as written.
export function withMergeRiskLine(body, line) {
  const lines = String(body ?? "")
    .replace(/\s+$/, "")
    .split("\n");
  let end = lines.length;
  while (end > 0 && LINE.test(lines[end - 1].replace(/\r$/, ""))) end -= 1;
  // An odd number of fence lines before the run puts it inside an open fence.
  const fences = lines.slice(0, end).filter((text) => FENCE.test(text)).length;
  const kept = (fences % 2 === 0 ? lines.slice(0, end) : lines).join("\n").replace(/\s+$/, "");
  return kept === "" ? line : `${kept}\n\n${line}`;
}

// Whether only the lanes App (`bot`, its login without `[bot]`) wrote the
// body, read whole: its author and every editor. A body anyone else touched
// is left alone, so the App's edit never makes an untrusted editor's text
// read as trusted (select-trusted-text keeps a body by its last editor).
export function appOnlyBody(pull, bot) {
  const edits = pull?.userContentEdits;
  if (typeof bot !== "string" || bot === "" || pull?.author?.__typename !== "Bot" || pull.author.login !== bot) return false;
  if (!Array.isArray(edits?.nodes) || !(edits.totalCount <= edits.nodes.length)) return false;
  return edits.nodes.every((edit) => edit?.editor?.__typename === "Bot" && edit.editor.login === bot);
}

// The line for `pr` at `head`, and its outcome token (`rated` or
// `unrated:<reason>`). Reads on `actions` (the job token, actions: read):
// the artifacts of that exact name, each counted only from a run of the
// rating workflow's origin; with none, the workflow's recent runs say whether
// one for this head is still going. `download(artifactId)` returns the text of
// rating.json. A throwing read is `unreadable`; a bad rating `invalid`.
export async function readRating({ actions, download, repository, pr, head, base = "main" }) {
  const unrated = (reason) => ({ line: unratedLine(reason), token: `unrated:${reason}` });
  const name = artifactName(pr, head);
  let found;
  try {
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
      const mine = runs.filter((run) => run?.display_title === runTitle(pr, head) && ofOrigin(run, { path: RATING_WORKFLOW_PATH, repository, base }));
      return unrated(mine.length === 0 ? "no-run" : mine.some((run) => run.status !== "completed") ? "pending" : "no-rating");
    }
  } catch {
    return unrated("unreadable");
  }
  let text;
  try {
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

// Resolves to `fallback` once `ms` pass, whatever `promise` does.
const within = (promise, ms, fallback) => {
  let timer;
  return Promise.race([Promise.resolve(promise).catch(() => fallback), new Promise((resolve) => (timer = setTimeout(resolve, ms, fallback)))]).finally(() => clearTimeout(timer));
};

// The arm-side step: read the rating within `readMs` (a synchronous
// `download` runs to its own timeout first), then set the line on a
// fresh read of the body within `writeMs`. `github` is the client that may
// edit the body. A body anyone but the lanes App (`bot`) wrote or edited
// (appOnlyBody) is neither read for nor written, and a body that changed
// since the listing (`pull.body`) is left alone, so a person's edit is never
// overwritten. Never throws.
export async function recordMergeRisk({ pull, repository, actions, github, download, bot, readMs = 15_000, writeMs = 5_000, now = Date.now }) {
  const started = now();
  const result = { token: "unrated:unreadable", wrote: false, skipped: undefined, readMs: 0 };
  try {
    const pr = pull?.number;
    const head = pull?.headRefOid;
    if (!Number.isSafeInteger(pr) || pr < 1 || !SHA.test(String(head))) {
      result.skipped = "no-pull";
      return result;
    }
    if (!appOnlyBody(pull, bot)) {
      result.token = "skipped";
      result.skipped = "untrusted-body";
      return result;
    }
    const over = { line: unratedLine("over-budget"), token: "unrated:over-budget" };
    const unreadable = { line: unratedLine("unreadable"), token: "unrated:unreadable" };
    const read = await within(
      (async () => readRating({ actions, download, repository, pr, head }))().catch(() => unreadable),
      readMs,
      over,
    );
    result.token = read.token;
    result.readMs = now() - started;
    const wrote = await within(
      (async () => {
        const live = (await github("GET", `/repos/${repository}/pulls/${pr}`))?.body ?? null;
        if (String(live ?? "") !== String(pull.body ?? "")) return "body-changed";
        const next = withMergeRiskLine(live, read.line);
        if (next === String(live ?? "")) return "exact";
        await github("PATCH", `/repos/${repository}/pulls/${pr}`, { body: next });
        return "wrote";
      })().catch(() => "write-failed"),
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
