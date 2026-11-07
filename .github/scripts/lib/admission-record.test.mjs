// Expected hashes are the published SHA-256 test vectors (FIPS 180-2: "abc",
// and the empty string); ids are the shared trusted-actors fixture's.
import assert from "node:assert/strict";
import { test } from "node:test";

import { ADMISSION_RECORD_MARKER, admittedAt, contentHash, matchesRecord, readAdmissionRecord, recordBody, writeAdmissionRecord } from "./admission-record.mjs";

const APP = 337595936;
const OWNER = 153232337;
const HUMANS = new Set([OWNER]);
const EMPTY = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
const ABC = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
const at = (hour) => `2026-11-07T${String(hour).padStart(2, "0")}:00:00Z`;
const record = (id, hour, body, user = { id: APP, login: "melodic-automation-lanes[bot]" }) => ({ id, user, body, created_at: at(hour), updated_at: at(hour) });
const field = (hour, actorId = OWNER, extra = {}) => ({ field: "48484079", removed: false, actorId, actorType: "User", at: at(hour), from: null, to: "agent-ready", ...extra });

test("contentHash is the sha256 hex of the utf-8 text, null read as empty", () => {
  assert.equal(contentHash("abc"), ABC);
  assert.equal(contentHash(""), EMPTY);
  assert.equal(contentHash(null), EMPTY);
});

test("the record is the marker line and the JSON of version, actor and both hashes", () => {
  assert.equal(
    recordBody({ actorId: APP, title: "abc", body: "" }),
    `${ADMISSION_RECORD_MARKER}\n{"v":1,"actor_id":${APP},"title_sha256":"${ABC}","body_sha256":"${EMPTY}"}`,
  );
});

test("writing a record posts one new comment", async () => {
  const calls = [];
  await writeAdmissionRecord(async (...args) => calls.push(args), "o/r", 7, { actorId: APP, title: "abc", body: "" });
  assert.deepEqual(calls, [["POST", "/repos/o/r/issues/7/comments", { body: recordBody({ actorId: APP, title: "abc", body: "" }) }]]);
});

test("no record and no person's set throws", () => {
  assert.throws(() => admittedAt({ comments: [], appId: APP, fieldEvents: [], fieldId: 48484079, humans: HUMANS }), /no admission record/);
});

test("the newest App record anchors and carries its hashes; matchesRecord compares the text", () => {
  const found = admittedAt({
    comments: [record(1, 1, recordBody({ actorId: APP, title: "old", body: "old" })), record(2, 3, recordBody({ actorId: APP, title: "abc", body: "" }))],
    appId: APP,
    fieldEvents: [],
    fieldId: 48484079,
    humans: HUMANS,
  });
  assert.equal(found.kind, "record");
  assert.equal(found.at, Date.parse(at(3)));
  assert.equal(found.record.titleSha256, ABC);
  assert.equal(matchesRecord(found.record, { title: "abc", body: "" }), true);
  assert.equal(matchesRecord(found.record, { title: "abc", body: "edited" }), false);
});

test("a listed human's agent-ready set newer than the record is the anchor", () => {
  const found = admittedAt({ comments: [record(1, 1, recordBody({ actorId: APP, title: "t", body: "b" }))], appId: APP, fieldEvents: [field(2)], fieldId: 48484079, humans: HUMANS });
  assert.deepEqual([found.kind, found.at], ["person", Date.parse(at(2))]);
});

test("an App field set, another field, another state, a removal or an unlisted account is no person's admission", () => {
  const events = [
    field(5, APP, { actorType: "Bot" }),
    field(5, OWNER, { field: "1" }),
    field(5, OWNER, { to: "ready" }),
    field(5, OWNER, { removed: true, to: null }),
    field(5, 999),
  ];
  const found = admittedAt({ comments: [record(1, 1, recordBody({ actorId: APP, title: "t", body: "b" }))], appId: APP, fieldEvents: events, fieldId: 48484079, humans: HUMANS });
  assert.deepEqual([found.kind, found.at], ["record", Date.parse(at(1))]);
});

test("a marked comment by another user id, the App's login included, is ignored", () => {
  const forged = record(2, 4, recordBody({ actorId: APP, title: "t", body: "b" }), { id: 999, login: "melodic-automation-lanes[bot]" });
  assert.equal(readAdmissionRecord([forged], APP), null);
  assert.throws(() => admittedAt({ comments: [forged], appId: APP, fieldEvents: [], fieldId: 48484079, humans: HUMANS }), /no admission record/);
});

test("an App comment carrying the marker inside other text, extra text after it, or an edit is no record and throws", () => {
  const valid = recordBody({ actorId: APP, title: "t", body: "b" });
  assert.equal(readAdmissionRecord([record(1, 1, `The run said: ${valid}`)], APP), null);
  assert.throws(() => readAdmissionRecord([record(1, 1, `${valid}\nmore`)], APP), /not parsable|as written/);
  assert.throws(() => readAdmissionRecord([record(1, 1, `${valid} `)], APP), /as written/);
  assert.throws(() => readAdmissionRecord([{ ...record(1, 1, valid), updated_at: at(2) }], APP), /as written/);
  assert.throws(() => readAdmissionRecord([record(1, 1, `${ADMISSION_RECORD_MARKER}\nnot json`)], APP), /not parsable/);
});

test("an admission after the trigger never moves the anchor; with none at or before it, the first after", () => {
  const comments = [record(1, 1, recordBody({ actorId: APP, title: "t", body: "b" })), record(2, 5, recordBody({ actorId: APP, title: "t", body: "b" }))];
  const args = { comments, appId: APP, fieldEvents: [field(3)], fieldId: 48484079, humans: HUMANS };
  assert.equal(admittedAt({ ...args, triggerAt: Date.parse(at(2)) }).at, Date.parse(at(1)));
  assert.equal(admittedAt({ ...args, triggerAt: Date.parse(at(4)) }).kind, "person");
  assert.equal(admittedAt({ ...args, triggerAt: Date.parse("2026-11-07T00:30:00Z") }).at, Date.parse(at(1)));
});

test("a human sender counts only their own sets, the App's restart every listed human's, and anyone else throws", () => {
  const args = { comments: [record(1, 1, recordBody({ actorId: APP, title: "t", body: "b" }))], appId: APP, fieldEvents: [field(3)], fieldId: 48484079, humans: new Set([OWNER, 42]) };
  assert.equal(admittedAt({ ...args, sender: OWNER }).kind, "person");
  // A human sender's own set is the admission: with none, no record stands in.
  assert.throws(() => admittedAt({ ...args, sender: 42 }), /no admission record/);
  assert.equal(admittedAt({ ...args, sender: APP }).kind, "person");
  assert.throws(() => admittedAt({ ...args, sender: 999 }), /neither the lanes App nor a listed human/);
});

test("a human-started run anchors on that human's set even when the trigger's update time predates it and an older record exists", () => {
  // Intake's record at 01, a decision comment bumps updated_at to 04, the
  // human's agent-ready set lands at 05 with the payload still saying 04.
  const found = admittedAt({
    comments: [record(1, 1, recordBody({ actorId: APP, title: "t", body: "b" }))],
    appId: APP,
    fieldEvents: [field(5)],
    fieldId: 48484079,
    humans: HUMANS,
    sender: OWNER,
    triggerAt: Date.parse(at(4)),
  });
  assert.deepEqual([found.kind, found.at], ["person", Date.parse(at(5))]);
});
