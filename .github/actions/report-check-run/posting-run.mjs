// Which workflow run posted a lane check run. report-check-run sets the check
// run's external_id to `<lane>:<activity>:<run id>:<run attempt>`; the API
// returns a check run a GITHUB_TOKEN created with details_url its own
// /runs/<check run id> page, whatever the POST set, so external_id is the one
// field that keeps the run.

const NAME = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/;
const RUN_NUMBER = /^[1-9][0-9]{0,19}$/;
const EXTERNAL_ID = /^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*:([1-9][0-9]{0,19}):([1-9][0-9]{0,19})$/;
// A check posted with a details_url GitHub kept: the run's own page.
const RUN_PAGE = /\/actions\/runs\/([1-9][0-9]{0,19})$/;

// The external_id for a check run the given run posts, or null when a field
// is malformed.
export function externalIdOf({ lane, activity, runId, runAttempt }) {
  return [lane, activity].every((name) => NAME.test(name ?? "")) && [runId, runAttempt].every((n) => RUN_NUMBER.test(n ?? ""))
    ? `${lane}:${activity}:${runId}:${runAttempt}`
    : null;
}

// The id of the workflow run that posted `check` (a REST check run), or null.
export function postingRunId(check) {
  return EXTERNAL_ID.exec(String(check?.external_id ?? ""))?.[1] ?? RUN_PAGE.exec(String(check?.details_url ?? ""))?.[1] ?? null;
}

// `<run id>:<run attempt>` of the workflow run attempt that posted `check`, read
// from external_id alone (a run page names no attempt), or null.
export function postingAttempt(check) {
  const match = EXTERNAL_ID.exec(String(check?.external_id ?? ""));
  return match ? `${match[1]}:${match[2]}` : null;
}
