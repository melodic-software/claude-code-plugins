const NAME = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/;
const RUN_NUMBER = /^[1-9][0-9]{0,19}$/;
const EXTERNAL_ID = /^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*:([1-9][0-9]{0,19}):([1-9][0-9]{0,19})$/;
const RUN_PAGE = /\/actions\/runs\/([1-9][0-9]{0,19})$/;

export function externalIdOf({ lane, activity, runId, runAttempt }) {
  return [lane, activity].every((name) => NAME.test(name ?? "")) && [runId, runAttempt].every((n) => RUN_NUMBER.test(n ?? ""))
    ? `${lane}:${activity}:${runId}:${runAttempt}`
    : null;
}

const externalIdMatch = (check) => EXTERNAL_ID.exec(String(check?.external_id ?? ""));

export function postingRunId(check) {
  return externalIdMatch(check)?.[1] ?? RUN_PAGE.exec(String(check?.details_url ?? ""))?.[1] ?? null;
}

export function postingAttempt(check) {
  const match = externalIdMatch(check);
  return match ? `${match[1]}:${match[2]}` : null;
}
