import assert from "node:assert/strict";
import { test } from "node:test";

import { earlierFailNotes, MAX_NOTE_ITEMS } from "./earlier-fail-notes.mjs";
import { NOTE_ID } from "./thread-scope.mjs";
import { VERIFY_NOTE_MARKER } from "./address-feedback.mjs";

const REPO = "o/r";
const FAILED = "b".repeat(40);
const MAIN_SHA = "c".repeat(40);
const RUN = 900;
const NAME = `pr-verify-42-${FAILED}-fail`;

const verdict = (extra = {}) => ({ verdict: "fail", pr: 42, head_sha: FAILED, summary: "the loop skips the last item", notes: ["src/a.js:3 off by one", "loose note"], ...extra });

// The REST answers the reads walk: the FAIL index for the head, the run's
// artifacts, the run record and its compare against main (resolve-pr.mjs
// countedBy), then the verdict zip, which `unzip` here reads as its text.
function fakeActions({ index, artifacts, run = {}, compare = { status: "ahead" }, file = verdict() } = {}) {
  const reads = [];
  const downloads = [];
  const answers = {
    [`/repos/${REPO}/actions/artifacts?name=pr-verify-index-sha-${FAILED}&per_page=100`]: index ?? { total_count: 1, artifacts: [{ id: 1, name: `pr-verify-index-sha-${FAILED}`, workflow_run: { id: RUN } }] },
    [`/repos/${REPO}/actions/runs/${RUN}/artifacts?per_page=100`]: artifacts ?? { total_count: 2, artifacts: [{ id: 7, name: NAME }, { id: 8, name: `pr-verify-index-sha-${FAILED}` }] },
    [`/repos/${REPO}/actions/runs/${RUN}`]: {
      id: RUN,
      path: ".github/workflows/pr-verify.yml",
      event: "workflow_run",
      head_branch: "main",
      repository: { full_name: REPO },
      head_repository: { full_name: REPO },
      status: "completed",
      conclusion: "success",
      head_sha: MAIN_SHA,
      ...run,
    },
    [`/repos/${REPO}/compare/${MAIN_SHA}...main`]: compare,
  };
  return {
    reads,
    downloads,
    actions: {
      async read(path) {
        reads.push(path);
        if (!Object.hasOwn(answers, path)) {
          throw new Error(`GET ${path} returned 404`);
        }
        return answers[path];
      },
      async download(id) {
        downloads.push(id);
        return Buffer.from(JSON.stringify(file));
      },
    },
  };
}

const read = (fake, extra = {}) => earlierFailNotes({ actions: fake.actions, repository: REPO, pr: 42, heads: [FAILED], files: ["src/a.js", "src/b.js"], unzip: (zip) => zip.toString("utf8"), ...extra });

test("the FAILed head's notes come from its verdict artifact, as pr-verify's note comments would carry them", async () => {
  const fake = fakeActions();
  const items = await read(fake);
  assert.deepEqual(
    items.map(({ id, head, path }) => [id, head, path]),
    [["VNOTE_1", FAILED, "src/a.js"]],
  );
  assert.ok(items.every((item) => NOTE_ID.test(item.id)));
  assert.ok(items[0].body.startsWith(`${VERIFY_NOTE_MARKER}\nThe pr-verify verifier failed head \`${FAILED}\``), items[0].body);
  assert.match(items[0].body, /Summary: the loop skips the last item/);
  assert.match(items[0].body, /src\/a\.js:3 off by one/);
  assert.match(items[0].body, /loose note/);
  // Only the FAIL verdict is downloaded, never the index.
  assert.deepEqual(fake.downloads, [7]);
});

test("a FAIL on several files gives one item per file, numbered across the heads", async () => {
  const fake = fakeActions({ file: verdict({ notes: ["src/a.js one", "src/b.js two"] }) });
  const items = await read(fake);
  assert.deepEqual(items.map(({ id, path }) => [id, path]), [["VNOTE_1", "src/a.js"], ["VNOTE_2", "src/b.js"]]);
});

test("a run the merge gate would not count hands the model nothing: it is passed over, and with no counted FAIL left the read fails closed", async () => {
  for (const run of [{ path: ".github/workflows/evil.yml" }, { head_branch: "feature" }, { event: "push" }, { head_repository: { full_name: "fork/r" } }, { status: "in_progress" }]) {
    const fake = fakeActions({ run });
    await assert.rejects(read(fake), /no FAIL verdict artifact/, JSON.stringify(run));
    assert.deepEqual(fake.downloads, [], JSON.stringify(run));
  }
  await assert.rejects(read(fakeActions({ compare: { status: "diverged" } })), /no FAIL verdict artifact/);
});

test("every other read that fails, or finds no FAIL, throws", async () => {
  const cases = [
    ["no index", fakeActions({ index: { total_count: 0, artifacts: [] } }), /no FAIL verdict artifact/],
    ["only expired", fakeActions({ artifacts: { total_count: 1, artifacts: [{ id: 7, name: NAME, expired: true }] } }), /no FAIL verdict artifact/],
    ["another PR's FAIL", fakeActions({ artifacts: { total_count: 1, artifacts: [{ id: 7, name: `pr-verify-43-${FAILED}-fail` }] } }), /no FAIL verdict artifact/],
    ["a short listing", fakeActions({ index: { total_count: 101, artifacts: [] } }), /does not list/],
    ["an index with no run", fakeActions({ index: { total_count: 1, artifacts: [{ id: 1, workflow_run: {} }] } }), /names no run/],
    ["a verdict for another head", fakeActions({ file: verdict({ head_sha: "d".repeat(40) }) }), /does not record the verdict/],
    ["a verdict with no notes", fakeActions({ file: verdict({ notes: "x" }) }), /does not record the fail/],
    ["a withheld verdict", fakeActions({ file: verdict({ withheld: true }) }), /not a readable FAIL/],
  ];
  for (const [label, fake, error] of cases) {
    await assert.rejects(read(fake), error, label);
  }
  const broken = fakeActions();
  broken.actions.download = async () => {
    throw new Error("GET artifact 7 zip returned 410");
  };
  await assert.rejects(read(broken), /410/);
  await assert.rejects(read(fakeActions(), { unzip: () => "not json" }), SyntaxError);
});

test("more items than one round takes fail closed", async () => {
  const files = Array.from({ length: MAX_NOTE_ITEMS + 1 }, (_, i) => `src/f${i}.js`);
  const fake = fakeActions({ file: verdict({ notes: files.map((file) => `${file} note`) }) });
  await assert.rejects(read(fake, { files }), /note item/);
});
