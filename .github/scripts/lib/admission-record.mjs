// The issue lane's admission record: one new lanes-App comment per admission
// (admit.mjs, report-outcome.mjs redispatch), carrying the sha256 of the
// title and body the admission read, and the resolver that finds the
// admission a run freezes its text at (write-issue.mjs) and counts its
// restarts from (report-outcome.mjs). Self-contained: report-outcome runs
// from a copy of its own directory beside this lib.
import { createHash } from "node:crypto";

export const ADMISSION_RECORD_MARKER = "<!-- issue-admission-record -->";
const HEX = /^[0-9a-f]{64}$/;

export const contentHash = (text) => createHash("sha256").update(String(text ?? ""), "utf8").digest("hex");

const canonical = ({ actorId, titleSha256, bodySha256 }) =>
  `${ADMISSION_RECORD_MARKER}\n${JSON.stringify({ v: 1, actor_id: actorId, title_sha256: titleSha256, body_sha256: bodySha256 })}`;

export const recordBody = ({ actorId, title, body }) => canonical({ actorId, titleSha256: contentHash(title), bodySha256: contentHash(body) });

// Always a new comment, never an edit: an edited record does not count.
export async function writeAdmissionRecord(github, repository, number, { actorId, title, body }) {
  await github("POST", `/repos/${repository}/issues/${number}/comments`, { body: recordBody({ actorId, title, body }) });
}

export const timeOf = (value) => (typeof value === "string" ? Date.parse(value) : Number.NaN);

// The lanes App's admission records, oldest first, each {at, record}. A
// comment counts only when the App's user id wrote it (never its login), its
// body is exactly the canonical record and it was never edited; an App
// comment that opens with the marker and is anything else throws.
export function admissionRecords(comments, appId) {
  const out = [];
  for (const comment of comments ?? []) {
    const text = String(comment?.body ?? "");
    if (comment?.user?.id !== appId || !text.startsWith(ADMISSION_RECORD_MARKER)) {
      continue;
    }
    let parsed;
    try {
      parsed = JSON.parse(text.slice(ADMISSION_RECORD_MARKER.length + 1));
    } catch {
      throw new Error(`admission record comment ${comment.id} is not parsable`);
    }
    const record = { actorId: parsed?.actor_id, titleSha256: parsed?.title_sha256, bodySha256: parsed?.body_sha256 };
    const at = timeOf(comment.created_at);
    if (
      parsed?.v !== 1 ||
      !Number.isSafeInteger(record.actorId) ||
      !HEX.test(record.titleSha256 ?? "") ||
      !HEX.test(record.bodySha256 ?? "") ||
      canonical(record) !== text ||
      !Number.isFinite(at) ||
      (comment.updated_at != null && comment.updated_at !== comment.created_at)
    ) {
      throw new Error(`admission record comment ${comment.id} is not a record as written`);
    }
    out.push({ at, record });
  }
  return out.sort((a, b) => a.at - b.at);
}

// The newest admission record, or null.
export const readAdmissionRecord = (comments, appId) => admissionRecords(comments, appId).at(-1) ?? null;

// A listed human's Work status sets of `state` (resolve-config.mjs
// fieldEvents' shape), oldest first, each {at, actorId}.
export function personAdmissions(fieldEvents, { fieldId, state = "agent-ready", humans }) {
  return (fieldEvents ?? [])
    .filter(
      (event) =>
        event?.field === String(fieldId) && event.removed === false && event.to === state && event.actorType === "User" && humans.has(event.actorId),
    )
    .map((event) => ({ at: timeOf(event.at), actorId: event.actorId }))
    .filter((one) => Number.isFinite(one.at))
    .sort((a, b) => a.at - b.at);
}

// The admission a run anchors on: {at, kind: "record"|"person", record}.
// Candidates are the App's records and a listed human's agent-ready sets;
// with `sender`, which must be the App or a listed human, a human sender's
// own sets are the only ones that count, records left out, since that
// set is itself the admission (an older record must never win when the
// trigger's update time predates the set); the App's restart counts every
// record and every listed human's set. With `triggerAt`, the newest candidate at
// or before it, else the first after it (the trigger's update time can
// predate its own event); a later admission never moves the anchor. Neither
// found throws.
export function admittedAt({ comments, appId, fieldEvents, fieldId, state = "agent-ready", humans, sender, triggerAt }) {
  if (sender != null && sender !== appId && !humans.has(sender)) {
    throw new Error("the run's sender is neither the lanes App nor a listed human");
  }
  const personSender = sender != null && sender !== appId;
  const records = personSender ? [] : admissionRecords(comments, appId).map(({ at, record }) => ({ at, kind: "record", record }));
  const people =
    fieldId == null
      ? []
      : personAdmissions(fieldEvents, { fieldId, state, humans })
          .filter((one) => !personSender || one.actorId === sender)
          .map(({ at }) => ({ at, kind: "person", record: null }));
  // A record and a person's set in one second: the person's is later.
  const all = [...records, ...people].sort((a, b) => a.at - b.at || (a.kind === "person") - (b.kind === "person"));
  const bounded = Number.isFinite(triggerAt) ? (all.filter((one) => one.at <= triggerAt).at(-1) ?? all.find((one) => one.at > triggerAt)) : all.at(-1);
  if (!bounded) {
    throw new Error("no admission record or listed human's agent-ready set admitted the issue");
  }
  return bounded;
}

// Whether `title` and `body` are the text `record` admitted.
export const matchesRecord = (record, { title, body }) => contentHash(title) === record.titleSha256 && contentHash(body) === record.bodySha256;
