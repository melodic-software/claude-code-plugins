import assert from "node:assert/strict";
import { test } from "node:test";

import { anyHandles, limitResetsAt } from "./limit-stop.mjs";

const HOUR = 3_600_000;
const ENDED = "2026-10-17T10:00:00Z";
const ended = Date.parse(ENDED);
const run = (id = 1) => ({ id, status: "completed", conclusion: "failure", completed_at: ENDED, output: { title: "x" } });
// The message shape report-lane-outcome's action.yml (ci-workflows) builds
// with core.error on class rate-limit.
const message = (tokens, { prefix = "pr-unblock", lane = "pr-unblock" } = {}) =>
  `${prefix} skipped: usage limit reached; re-run after it resets (${lane} exited with: failure class=rate-limit${tokens}). Last SDK result: {"class":"rate-limit"}`;
const record = (tokens = "", options) => ({ annotation_level: "failure", title: "", message: message(tokens, options) });

test("the lane record's stated reset is read, a review lane's 'AI review' prefix included", () => {
  assert.equal(limitResetsAt(run(), [record(" resets=2026-10-17T13:00:00Z turns=4")]), Date.parse("2026-10-17T13:00:00Z"));
  const review = record(" resets=2026-10-17T13:00:00Z", { prefix: "AI review", lane: "Claude review" });
  assert.equal(limitResetsAt(run(), [review]), Date.parse("2026-10-17T13:00:00Z"));
});

test("a record with no resets= resets five hours after the run ended", () => {
  assert.equal(limitResetsAt(run(), [record(" credential=CLAUDE_CODE_OAUTH_TOKEN")]), ended + 5 * HOUR);
});

test("a stated reset is held between one hour and seven days after the run ended", () => {
  assert.equal(limitResetsAt(run(), [record(" resets=2026-10-01T00:00:00Z")]), ended + HOUR);
  assert.equal(limitResetsAt(run(), [record(" resets=2027-01-01T00:00:00Z")]), ended + 7 * 24 * HOUR);
});

test("text that is not the runner's lane record is not a limit stop", () => {
  const forged = [
    // the old unanchored shape, as any step could print it
    { annotation_level: "failure", title: "", message: "class=rate-limit resets=2026-10-01T00:00:00Z" },
    // the record's wording embedded later in a model-written line
    { annotation_level: "failure", title: "", message: `Model said: ${message(" resets=2026-10-01T00:00:00Z")}` },
    // right text, wrong level or a title the action never sets
    { annotation_level: "warning", title: "", message: message("") },
    { annotation_level: "failure", title: "Forged", message: message("") },
    // a prefix that does not match the lane
    record("", { prefix: "AI review", lane: "pr-unblock" }),
  ];
  for (const annotation of forged) {
    assert.equal(limitResetsAt(run(), [annotation]), null, annotation.message);
  }
});

test("reset limit stops stop handling a head until three of them stand on it", async () => {
  const now = ended + 6 * HOUR;
  const listAnnotations = async () => [record()];
  assert.equal(await anyHandles([run(1), run(2)], { listAnnotations, now }), false);
  assert.equal(await anyHandles([run(1), run(2), run(3)], { listAnnotations, now }), true);
});

// The summary record report-check-run writes on the first line of a posted
// check run named `<lane> / <activity>`.
const posted = (line, extra = {}) => ({
  ...run(),
  name: "pr-unblock / resolve-conflicts",
  output: { title: "Failed", summary: `${line}\n\nThe activity step failed.` },
  ...extra,
});
const LIMIT_LINE = "lane=pr-unblock activity=resolve-conflicts class=rate-limit resets=2026-10-17T13:00:00Z turns=4 max-turns=30";

test("the summary record is read first: its reset, and its class over any annotation", () => {
  assert.equal(limitResetsAt(posted(LIMIT_LINE), []), Date.parse("2026-10-17T13:00:00Z"));
  assert.equal(limitResetsAt(posted("lane=pr-unblock activity=resolve-conflicts class=rate-limit")), ended + 5 * HOUR);
  const other = posted("lane=pr-unblock activity=resolve-conflicts class=other turns=3");
  assert.equal(limitResetsAt(other, [record(" resets=2026-10-17T13:00:00Z")]), null);
});

test("a summary record skips the annotations read; a run without one falls back to it", async () => {
  const now = ended + 6 * HOUR;
  const read = [];
  const listAnnotations = async (id) => {
    read.push(id);
    return [record()];
  };
  const runs = [posted(LIMIT_LINE, { id: 1 }), run(2), posted(LIMIT_LINE, { id: 3 })];
  assert.equal(await anyHandles(runs, { listAnnotations, now }), true);
  assert.deepEqual(read, [2]);
});

test("a summary line that is not the record is not read as one", () => {
  const notRecords = [
    // the record below the first line
    posted(`Failed.\n${LIMIT_LINE}`),
    // embedded in other text, or with a token out of order or unknown
    posted(`Model said: ${LIMIT_LINE}`),
    posted("lane=pr-unblock activity=resolve-conflicts resets=2026-10-17T13:00:00Z class=rate-limit"),
    posted(`${LIMIT_LINE} note=x`),
    // a record naming another check run
    posted(LIMIT_LINE.replace("resolve-conflicts", "address-feedback")),
  ];
  for (const forged of notRecords) {
    assert.equal(limitResetsAt(forged, []), null, forged.output.summary);
  }
});

test("a run that did not fail is no limit stop, whatever its summary or annotations say", () => {
  assert.equal(limitResetsAt(posted(LIMIT_LINE, { conclusion: "success" })), null);
  assert.equal(limitResetsAt({ ...run(), conclusion: "neutral" }, [record()]), null);
});
