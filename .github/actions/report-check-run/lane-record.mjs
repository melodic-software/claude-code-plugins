// The lane record for a posted check run: the run's failure class, limit reset
// and turn headroom, which ci-workflows' report-lane-outcome computed in the
// run job from the execution file. Every field is a run job output or the
// runner's own environment and is checked against a fixed shape here; nothing
// the model wrote reaches the record. It is posted as the first line of
// output.summary, which .github/scripts/pr-unblock/limit-stop.mjs reads, with
// the JSON form in output.text.

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
      RUN_NUMBER.test(runId) && RUN_NUMBER.test(runAttempt) ? `${lane}:${activity}:${runId}:${runAttempt}` : null,
  };
}
