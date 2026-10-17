// The lane record for a posted check run: the run's failure class, limit reset
// and turn headroom, which ci-workflows' report-lane-outcome computed in the
// run job from the execution file. Every field is a run job output or the
// runner's own environment and is checked against a fixed shape here; nothing
// the model wrote reaches the record. It is posted twice: as the first line of
// output.summary (with the JSON form in output.text), which
// .github/scripts/pr-unblock/limit-stop.mjs reads first, and as one annotation
// in the shape limit-stop.mjs reads on check runs posted before the summary
// line existed.

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
const NAME = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/;
const RESETS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z$/;
const COUNT = /^(0|[1-9][0-9]{0,5})$/;
const RUN_NUMBER = /^[1-9][0-9]*$/;
const PATH = ".github/workflows/pr-run-activity-write.yml";

// The record's fields that passed their shape, or null when the run job left
// no record: the skill did not run, or the class is not one
// report-lane-outcome emits.
function laneRecord({ failureClass = "", resets = "", turns = "", maxTurns = "" }) {
  if (failureClass !== "" && !CLASSES.has(failureClass)) {
    return null;
  }
  const fields = {
    resets: failureClass === "rate-limit" && RESETS.test(resets) ? resets : null,
    turns: COUNT.test(turns) ? turns : null,
    "max-turns": COUNT.test(maxTurns) ? maxTurns : null,
  };
  if (failureClass === "" && fields.turns === null && fields["max-turns"] === null) {
    return null;
  }
  return { class: failureClass || null, ...fields };
}

const tokensOf = (fields) =>
  Object.entries(fields)
    .filter(([, value]) => value !== null)
    .map(([key, value]) => `${key}=${value}`);

// The record as the check run's output fields and external_id, or null when
// there is none. The summary line is `lane=<lane> activity=<activity>` then
// class, resets, turns and max-turns in that order, each omitted when absent.
export function laneRecordOutput({ lane, activity, runId = "", runAttempt = "", ...inputs }) {
  const record = laneRecord(inputs);
  if (!record || !NAME.test(lane ?? "") || !NAME.test(activity ?? "")) {
    return null;
  }
  const fields = { lane, activity, ...record };
  const json = Object.fromEntries(
    Object.entries(fields)
      .filter(([, value]) => value !== null)
      .map(([key, value]) => [key, key.endsWith("turns") ? Number(value) : value]),
  );
  return {
    line: tokensOf(fields).join(" "),
    text: `\`\`\`json\n${JSON.stringify(json)}\n\`\`\``,
    externalId:
      RUN_NUMBER.test(runId) && RUN_NUMBER.test(runAttempt) ? `${lane}:${runId}:${runAttempt}` : null,
  };
}

// One check-run annotation, or null when there is no record.
export function laneRecordAnnotation({ lane, ...inputs }) {
  const fields = laneRecord(inputs);
  if (!fields) {
    return null;
  }
  const { class: failureClass, ...rest } = fields;
  const record = tokensOf(rest)
    .map((token) => ` ${token}`)
    .join("");
  const at = { path: PATH, start_line: 1, end_line: 1 };
  if (failureClass === null) {
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
