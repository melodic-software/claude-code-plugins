// The record a dispatcher run leaves for the next one, kept in the Actions
// cache: per check name, the heads whose check runs handle them for good
// (permanentlyHandles in limit-stop.mjs), and per head the PR and run a
// dispatch started. A reader only skips work on it, never dispatches on it,
// so a lost or tampered record costs reads or a skip, not an extra run. Each
// entry is validated; anything else in the file is dropped.

import { readFileSync, writeFileSync } from "node:fs";

const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,14}$/;
// Raised whenever a dispatcher changes which check runs handle a head for
// good, so a record written under the old rule is read as empty: version 2
// leaves unrecorded a head a later no-model-turn reply or verdict can release,
// version 3 a review-dependency head a limit stop holds until its reset, and
// version 4 a resolve-conflicts head a failed run or a held skip left. A fix-ci
// head recorded at its per-head cap needs no new version: a record with no
// fix-ci entry reads the same either way.
export const RECORD_VERSION = 4;

export function emptyRecord() {
  return { handled: new Map(), dispatched: new Map() };
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
  for (const [head, entry] of Object.entries(doc.dispatched ?? {})) {
    if (SHA.test(head) && Number.isSafeInteger(entry?.number) && entry.number > 0 && RUN_ID.test(String(entry?.runId))) {
      record.dispatched.set(head, { number: entry.number, runId: String(entry.runId) });
    }
  }
  return record;
}

export function serializeRecord(record) {
  const handled = Object.fromEntries(
    [...record.handled].filter(([, heads]) => heads.size > 0).sort(([a], [b]) => a.localeCompare(b)).map(([check, heads]) => [check, [...heads].sort()]),
  );
  const dispatched = Object.fromEntries([...record.dispatched].sort(([a], [b]) => a.localeCompare(b)));
  return `${JSON.stringify({ version: RECORD_VERSION, handled, dispatched })}\n`;
}

export const isHandled = (record, check, head) => record.handled.get(check)?.has(head) === true;

export function markHandled(record, check, head) {
  if (!record.handled.has(check)) {
    record.handled.set(check, new Set());
  }
  record.handled.get(check).add(head);
}

// Keeps only the entries for `heads`, the open PRs' current heads.
export function pruneRecord(record, heads) {
  for (const set of record.handled.values()) {
    for (const head of set) {
      if (!heads.has(head)) {
        set.delete(head);
      }
    }
  }
  for (const head of record.dispatched.keys()) {
    if (!heads.has(head)) {
      record.dispatched.delete(head);
    }
  }
}

// The record at `path`, empty when the file is absent or unreadable.
export function readRecord(path) {
  if (!path) {
    return { record: emptyRecord(), text: "" };
  }
  let text = "";
  try {
    text = readFileSync(path, "utf8");
  } catch {
    return { record: emptyRecord(), text: "" };
  }
  return { record: parseRecord(text), text };
}

// Writes the record when it differs from what was read; returns whether it did.
export function writeRecord(path, record, before) {
  const text = serializeRecord(record);
  if (!path || text === serializeRecord(parseRecord(before))) {
    return false;
  }
  writeFileSync(path, text);
  return true;
}
