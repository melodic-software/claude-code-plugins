import { readFileSync, writeFileSync } from "node:fs";

const SHA = /^[0-9a-f]{40}$/;
export const RUN_ID = /^[1-9][0-9]{0,14}$/;
// NaN for a run with no readable start: it compares false either way.
export const startOf = (run) => Date.parse(run.started_at ?? "");

export async function sendDispatch(api, log, { workflow, base, node, inputs, label = "", errorLabel = "", note = () => "" }) {
  try {
    const { workflowRunId } = await api.dispatchWorkflow({ workflow, ref: `refs/heads/${base}`, inputs });
    const id = String(workflowRunId);
    if (!RUN_ID.test(id)) {
      log(`::error::#${node.number}: ${errorLabel}dispatch returned no valid workflow_run_id`);
      return null;
    }
    log(`dispatched ${label}#${node.number} head ${node.headRefOid} workflow_run_id=${id}${note()}`);
    return id;
  } catch (error) {
    log(`::error::#${node.number}: ${errorLabel}dispatch failed: ${error.message}`);
    return null;
  }
}
// Raised whenever a dispatcher changes which check runs handle a head for
// good, so a record written under the old rule is read as empty: version 2
// leaves unrecorded a head a later no-model-turn reply or verdict can release,
// version 3 a review-dependency head a limit stop holds until its reset, and
// version 4 a resolve-conflicts head a failed run or a held skip left, and
// version 5 a resolve-conflicts head a select job's stop left under an older
// base, and version 6 a resolve-conflicts, sync-shared-copies or
// review-dependency head a head-lag stop left (limit-stop.mjs
// lagStopsRelease), and version 7 an address-feedback or fix-ci head
// pr-verify's FAIL cap held, which a superseded FAIL now clears
// (https://github.com/melodic-software/claude-code-plugins/issues/17646). A fix-ci
// head recorded at its per-head cap needs no new version: a record with no
// fix-ci entry reads the same either way; nor do fix-docs runs, read as none.
export const RECORD_VERSION = 7;
const MAX_DOCS_RUNS = 20;

export function emptyRecord() {
  return { handled: new Map(), bases: new Map(), dispatched: new Map(), docsRuns: new Map() };
}

export function parseRecord(text) {
  const record = emptyRecord();
  let doc;
  try {
    doc = JSON.parse(text);
  } catch {
    return record;
  }
  if (doc?.version !== RECORD_VERSION) {
    return record;
  }
  for (const [check, heads] of Object.entries(doc.handled ?? {})) {
    if (Array.isArray(heads)) {
      record.handled.set(check, new Set(heads.filter((head) => SHA.test(String(head)))));
    }
  }
  for (const [head, base] of Object.entries(doc.bases ?? {})) {
    if (SHA.test(head) && SHA.test(String(base))) {
      record.bases.set(head, base);
    }
  }
  for (const [head, entry] of Object.entries(doc.dispatched ?? {})) {
    if (SHA.test(head) && Number.isSafeInteger(entry?.number) && entry.number > 0 && RUN_ID.test(String(entry?.runId))) {
      record.dispatched.set(head, { number: entry.number, runId: String(entry.runId) });
    }
  }
  for (const [head, runs] of Object.entries(doc.docsRuns ?? {})) {
    if (SHA.test(head) && Array.isArray(runs)) {
      const ids = [...new Set(runs.map(String).filter((id) => RUN_ID.test(id)))].slice(-MAX_DOCS_RUNS);
      if (ids.length > 0) {
        record.docsRuns.set(head, ids);
      }
    }
  }
  return record;
}

const byKey = (entries) => entries.sort(([a], [b]) => a.localeCompare(b));

export function serializeRecord(record) {
  const handled = Object.fromEntries(
    byKey([...record.handled].filter(([, heads]) => heads.size > 0)).map(([check, heads]) => [check, [...heads].sort()]),
  );
  const bases = Object.fromEntries(byKey([...record.bases]));
  const dispatched = Object.fromEntries(byKey([...record.dispatched]));
  const docsRuns = Object.fromEntries(
    byKey([...record.docsRuns].filter(([, ids]) => ids.length > 0)).map(([head, ids]) => [head, ids.slice(-MAX_DOCS_RUNS)]),
  );
  return `${JSON.stringify({ version: RECORD_VERSION, handled, bases, dispatched, docsRuns })}\n`;
}

export const isHandled = (record, check, head) => record.handled.get(check)?.has(head) === true;

export function markHandled(record, check, head) {
  if (!record.handled.has(check)) {
    record.handled.set(check, new Set());
  }
  record.handled.get(check).add(head);
}

export function pruneRecord(record, heads) {
  for (const set of record.handled.values()) {
    for (const head of set) {
      if (!heads.has(head)) {
        set.delete(head);
      }
    }
  }
  for (const map of [record.bases, record.dispatched, record.docsRuns]) {
    for (const head of map.keys()) {
      if (!heads.has(head)) {
        map.delete(head);
      }
    }
  }
}

export function readRecord(path) {
  let text;
  try {
    text = path ? readFileSync(path, "utf8") : "";
  } catch {
    text = "";
  }
  return { record: parseRecord(text), text };
}

export function writeRecord(path, record, before) {
  const text = serializeRecord(record);
  if (!path || text === serializeRecord(parseRecord(before))) {
    return false;
  }
  writeFileSync(path, text);
  return true;
}
