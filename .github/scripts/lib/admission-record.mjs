import { createHash } from "node:crypto";

export const ADMISSION_RECORD_MARKER = "<!-- issue-admission-record -->";
const HEX = /^[0-9a-f]{64}$/;

export const contentHash = (text) => createHash("sha256").update(String(text ?? ""), "utf8").digest("hex");

const canonical = ({ actorId, titleSha256, bodySha256 }) =>
  `${ADMISSION_RECORD_MARKER}\n${JSON.stringify({ v: 1, actor_id: actorId, title_sha256: titleSha256, body_sha256: bodySha256 })}`;

export const recordBody = ({ actorId, title, body }) => canonical({ actorId, titleSha256: contentHash(title), bodySha256: contentHash(body) });

export async function writeAdmissionRecord(github, repository, number, { actorId, title, body }) {
  await github("POST", `/repos/${repository}/issues/${number}/comments`, { body: recordBody({ actorId, title, body }) });
}

export const timeOf = (value) => (typeof value === "string" ? Date.parse(value) : Number.NaN);

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

export const readAdmissionRecord = (comments, appId) => admissionRecords(comments, appId).at(-1) ?? null;

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
  const all = [...records, ...people].sort((a, b) => a.at - b.at || (a.kind === "person") - (b.kind === "person"));
  const bounded = Number.isFinite(triggerAt) ? (all.filter((one) => one.at <= triggerAt).at(-1) ?? all.find((one) => one.at > triggerAt)) : all.at(-1);
  if (!bounded) {
    throw new Error("no admission record or listed human's agent-ready set admitted the issue");
  }
  return bounded;
}

export const matchesRecord = (record, { title, body }) => contentHash(title) === record.titleSha256 && contentHash(body) === record.bodySha256;
