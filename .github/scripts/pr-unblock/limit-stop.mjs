// Whether an existing pr-unblock check run already handles a head, shared by
// dispatch.mjs and feedback-dispatch.mjs. A check run handles the head unless
// it is the gate's completed neutral skip for an untrusted trigger, or a run
// the usage limit stopped whose limit has reset: the lane's next trigger then
// dispatches it again, at most MAX_LIMIT_STOPS times on one head.
//
// A limit stop is read only from the lane record annotation that ci-workflows'
// report-lane-outcome writes with core.error: failure level, no title, and a
// message that opens "<AI review|lane> skipped: usage limit reached; re-run
// after it resets (<lane> exited with: <outcome> class=rate-limit <record
// tokens>). Last SDK result: ", matched from its start, so text a step or the
// model prints elsewhere in the job cannot pass for one.

// When a limit stop names no `resets=` time, it is taken to reset this long
// after the run ended: the shortest plan limit is a five-hour session window
// (https://support.claude.com/en/articles/11145838).
// TODO(C6): read limits.fallback-reset from pr-pipeline.yaml once that leaf exists.
export const FALLBACK_RESET_MS = 5 * 3_600_000;
const HOUR_MS = 3_600_000;
// Limit stops on one head after which the dispatchers stop re-dispatching it
// (judgment); the next push makes a new head.
export const MAX_LIMIT_STOPS = 3;
const RECORD =
  /^([^\n()]+) skipped: usage limit reached; re-run after it resets \(([^\n()]+) exited with: [a-z_]+ class=rate-limit((?: [a-z-]+=[^\s()]+)*)\)\. Last SDK result: /;
const RESETS = /^resets=(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z)$/;

// When the limit that stopped `run` resets (epoch ms), or null when no lane
// record marks it a limit stop. The stated reset is held between one hour and
// seven days after the run ended.
export function limitResetsAt(run, annotations) {
  const ended = Date.parse(run.completed_at ?? "");
  if (!Number.isFinite(ended)) {
    return null;
  }
  const record = annotations
    .filter((annotation) => annotation?.annotation_level === "failure" && !annotation.title)
    .map((annotation) => RECORD.exec(String(annotation.message ?? "")))
    .find((match) => match && match[1] === (/review/i.test(match[2]) ? "AI review" : match[2]));
  if (!record) {
    return null;
  }
  const stated = record[3]
    .split(" ")
    .map((token) => RESETS.exec(token)?.[1])
    .find(Boolean);
  const resets = stated ? Date.parse(stated) : ended + FALLBACK_RESET_MS;
  return Math.min(Math.max(resets, ended + HOUR_MS), ended + 7 * 24 * HOUR_MS);
}

const untrustedSkip = (run) =>
  run.status === "completed" &&
  run.conclusion === "neutral" &&
  String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger");

// Whether `runs` handle the head: any run that is not an untrusted skip or a
// reset limit stop does, and so do MAX_LIMIT_STOPS limit stops. Annotations
// are read only for a failed run.
export async function anyHandles(runs, { listAnnotations, now }) {
  let stops = 0;
  for (const run of runs) {
    if (untrustedSkip(run)) {
      continue;
    }
    if (run.status !== "completed" || run.conclusion !== "failure") {
      return true;
    }
    const resets = limitResetsAt(run, await listAnnotations(run.id));
    if (resets === null || now < resets) {
      return true;
    }
    stops += 1;
  }
  return stops >= MAX_LIMIT_STOPS;
}
