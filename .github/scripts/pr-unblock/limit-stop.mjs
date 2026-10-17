// Whether an existing pr-unblock check run already handles a head, shared by
// dispatch.mjs and feedback-dispatch.mjs. A check run handles the head unless
// it is the gate's completed neutral skip for an untrusted trigger, or a run
// the usage limit stopped (a failure whose annotations carry the lane record's
// `class=rate-limit`) whose limit has reset: the lane's next trigger then
// dispatches it again.

// When a limit stop names no `resets=` time, it is taken to reset this long
// after the run ended: the shortest plan limit is a five-hour session window
// (https://support.claude.com/en/articles/11145838).
// TODO(C6): read limits.fallback-reset from pr-pipeline.yaml once that leaf exists.
export const FALLBACK_RESET_MS = 5 * 3_600_000;
const RATE_LIMIT = /\bclass=rate-limit\b/;
const RESETS = /\bresets=(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z)/;

// When the limit that stopped `run` resets (epoch ms), or null when the
// annotations do not mark it a limit stop.
export function limitResetsAt(run, annotations) {
  const text = annotations.map((annotation) => String(annotation?.message ?? "")).join("\n");
  if (!RATE_LIMIT.test(text)) {
    return null;
  }
  const stated = Date.parse(RESETS.exec(text)?.[1] ?? "");
  if (Number.isFinite(stated)) {
    return stated;
  }
  const ended = Date.parse(run.completed_at ?? "");
  return Number.isFinite(ended) ? ended + FALLBACK_RESET_MS : null;
}

const untrustedSkip = (run) =>
  run.status === "completed" &&
  run.conclusion === "neutral" &&
  String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger");

// Whether any of `runs` handles the head. Annotations are read only for a
// failed run.
export async function anyHandles(runs, { listAnnotations, now }) {
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
  }
  return false;
}
