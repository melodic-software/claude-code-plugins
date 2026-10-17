// Whether an existing pr-unblock check run already handles a head, shared by
// dispatch.mjs and feedback-dispatch.mjs. A check run handles the head unless
// it is the gate's completed neutral skip for an untrusted trigger, or a run
// the usage limit stopped whose limit has reset: the lane's next trigger then
// dispatches it again, at most MAX_LIMIT_STOPS times on one head.
//
// A limit stop is read only from a failed run's lane record, which
// report-check-run writes from runner-computed outputs. The record is the first
// line of the run's output.summary, matched whole: `lane=<lane>
// activity=<activity>` naming the run itself, then class, resets, turns and
// max-turns in that order, each optional. A run with no such line was posted
// before report-check-run wrote it; its record is the annotation in the shape
// ci-workflows' report-lane-outcome writes with core.error: failure level, no
// title, and a message that opens "<AI review|lane> skipped: usage limit
// reached; re-run after it resets (<lane> exited with: <outcome>
// class=rate-limit <record tokens>). Last SDK result: ", matched from its
// start, so text a step or the model prints elsewhere cannot pass for one.

// When a limit stop names no `resets=` time, it is taken to reset this long
// after the run ended: the shortest plan limit is a five-hour session window
// (https://support.claude.com/en/articles/11145838).
// Hard-coded until pr-pipeline.yaml has a limits.fallback-reset leaf:
// https://github.com/melodic-software/claude-code-plugins/issues/7764
export const FALLBACK_RESET_MS = 5 * 3_600_000;
const HOUR_MS = 3_600_000;
// Limit stops on one head after which the dispatchers stop re-dispatching it
// (judgment); the next push makes a new head.
export const MAX_LIMIT_STOPS = 3;
const RECORD =
  /^([^\n()]+) skipped: usage limit reached; re-run after it resets \(([^\n()]+) exited with: [a-z_]+ class=rate-limit((?: [a-z-]+=[^\s()]+)*)\)\. Last SDK result: /;
const ISO = String.raw`\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z`;
const RESETS = new RegExp(`^resets=(${ISO})$`);
const NAME = "[a-z][a-z0-9]*(?:-[a-z0-9]+)*";
const SUMMARY_RECORD = new RegExp(
  `^lane=(${NAME}) activity=(${NAME})(?: class=([a-z-]+))?(?: resets=(${ISO}))?` +
    "(?: turns=(?:0|[1-9][0-9]{0,5}))?(?: max-turns=(?:0|[1-9][0-9]{0,5}))?$",
);

// The lane record on the first line of `run`'s output.summary, or null when
// that line is not one or names another check run.
export function summaryRecord(run) {
  const match = SUMMARY_RECORD.exec(String(run.output?.summary ?? "").split("\n")[0]);
  if (!match || run.name !== `${match[1]} / ${match[2]}`) {
    return null;
  }
  return { failureClass: match[3] ?? "", resets: match[4] ?? "" };
}

function annotationResets(annotations) {
  const record = annotations
    .filter((annotation) => annotation?.annotation_level === "failure" && !annotation.title)
    .map((annotation) => RECORD.exec(String(annotation.message ?? "")))
    .find((match) => match && match[1] === (/review/i.test(match[2]) ? "AI review" : match[2]));
  if (!record) {
    return null;
  }
  return record[3]
    .split(" ")
    .map((token) => RESETS.exec(token)?.[1])
    .find(Boolean) ?? "";
}

// When the limit that stopped the failed `run` resets (epoch ms), or null when
// its lane record does not mark it a limit stop. `annotations` are read only
// when the summary carries no record. The stated reset is held between one
// hour and seven days after the run ended.
export function limitResetsAt(run, annotations = []) {
  const ended = Date.parse(run.completed_at ?? "");
  if (!Number.isFinite(ended) || run.conclusion !== "failure") {
    return null;
  }
  const summary = summaryRecord(run);
  if (summary && summary.failureClass !== "rate-limit") {
    return null;
  }
  const stated = summary ? summary.resets : annotationResets(annotations);
  if (stated === null) {
    return null;
  }
  const resets = stated ? Date.parse(stated) : ended + FALLBACK_RESET_MS;
  return Math.min(Math.max(resets, ended + HOUR_MS), ended + 7 * 24 * HOUR_MS);
}

const untrustedSkip = (run) =>
  run.status === "completed" &&
  run.conclusion === "neutral" &&
  String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger");

// Whether `runs` handle the head: any run that is not an untrusted skip or a
// reset limit stop does, and so do MAX_LIMIT_STOPS limit stops. Annotations
// are read only for a failed run whose summary carries no lane record.
export async function anyHandles(runs, { listAnnotations, now }) {
  let stops = 0;
  for (const run of runs) {
    if (untrustedSkip(run)) {
      continue;
    }
    if (run.status !== "completed" || run.conclusion !== "failure") {
      return true;
    }
    const resets = limitResetsAt(run, summaryRecord(run) ? [] : await listAnnotations(run.id));
    if (resets === null || now < resets) {
      return true;
    }
    stops += 1;
  }
  return stops >= MAX_LIMIT_STOPS;
}
