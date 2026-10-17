// The lane record annotation for a posted check run: the run's failure class,
// limit reset and turn headroom, which ci-workflows' report-lane-outcome
// computed in the run job from the execution file. Every field is a run job
// output and is checked against a fixed shape here; nothing the model wrote
// reaches the message. A rate-limit message keeps the exact shape
// .github/scripts/pr-unblock/limit-stop.mjs parses.

const CLASSES = new Set([
  "auth",
  "rate-limit",
  "overloaded",
  "max-turns",
  "timeout",
  "other",
  "skipped-validation",
  "incomplete",
]);
const RESETS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z$/;
const COUNT = /^(0|[1-9][0-9]{0,5})$/;
const PATH = ".github/workflows/pr-run-activity-write.yml";

// One check-run annotation, or null when the run job left no record: the
// skill did not run, or the class is not one report-lane-outcome emits.
export function laneRecordAnnotation({
  lane,
  failureClass = "",
  resets = "",
  turns = "",
  maxTurns = "",
}) {
  if (failureClass !== "" && !CLASSES.has(failureClass)) {
    return null;
  }
  const tokens = [
    failureClass === "rate-limit" && RESETS.test(resets) && `resets=${resets}`,
    COUNT.test(turns) && `turns=${turns}`,
    COUNT.test(maxTurns) && `max-turns=${maxTurns}`,
  ].filter(Boolean);
  if (failureClass === "" && tokens.length === 0) {
    return null;
  }
  const record = tokens.map((token) => ` ${token}`).join("");
  const at = { path: PATH, start_line: 1, end_line: 1 };
  if (failureClass === "") {
    return { ...at, annotation_level: "notice", message: `${lane} completed:${record}.` };
  }
  if (failureClass === "skipped-validation") {
    return {
      ...at,
      annotation_level: "warning",
      message: `${lane} concluded: success class=skipped-validation${record} with no execution evidence.`,
    };
  }
  const skipped = /review/iu.test(lane) ? "AI review" : lane;
  return {
    ...at,
    annotation_level: "failure",
    message:
      failureClass === "rate-limit"
        ? `${skipped} skipped: usage limit reached; re-run after it resets ` +
          `(${lane} exited with: failure class=rate-limit${record}). Last SDK result: in the run log.`
        : `${lane} exited with: failure class=${failureClass}${record}.`,
  };
}
