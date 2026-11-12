import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { fileDue, HELD, main, scheduleIds } from "./file-due.mjs";

const REPO = "o/r";
const TODAY = "2026-11-06";
const noWait = async () => {};

const row = (over = {}) => ({
  id: "ci-pins",
  title: "Review CI pins",
  cadence: "monthly",
  area: [],
  next_due: "2026-11-01",
  notes: "Check each pinned action.",
  ...over,
});

// A GitHub stand-in: open issues the list endpoint pages through 100 at a
// time, the labels that exist, and a POST that adds the filed issue to the list.
function fakeApi({ issues = [], labels = ["recurring"], failPost = false, dropType = false } = {}) {
  const state = { issues: [...issues], posts: [], next: 900 };
  const call = async (method, path, body) => {
    const list = /^\/repos\/o\/r\/issues\?labels=recurring&state=open&per_page=100&page=(\d+)$/.exec(path);
    if (method === "GET" && list) {
      const open = state.issues.filter((i) => i.labels.includes("recurring"));
      return open.slice((Number(list[1]) - 1) * 100, Number(list[1]) * 100);
    }
    const label = /^\/repos\/o\/r\/labels\/(.+)$/.exec(path);
    if (method === "GET" && label) return labels.includes(decodeURIComponent(label[1])) ? { name: decodeURIComponent(label[1]) } : null;
    if (method === "POST" && path === "/repos/o/r/issues") {
      if (failPost) throw Object.assign(new Error("POST /repos/o/r/issues: HTTP 502"), { status: 502 });
      state.next += 1;
      state.posts.push(body);
      state.issues.push({ number: state.next, body: body.body, labels: body.labels });
      return { number: state.next, ...(dropType ? {} : { type: { name: body.type } }) };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { call, state };
}

test("a due row with no open issue is filed with the row's title, a type, the row's context and the marker", async () => {
  const api = fakeApi();
  const results = await fileDue({ schedule: { items: [row()] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.deepEqual(results, [{ id: "ci-pins", next_due: "2026-11-01", due: true, outcome: "filed", issue: 901 }]);
  assert.deepEqual(api.state.posts, [
    {
      title: "Review CI pins",
      type: "Task",
      body: [
        "## Context",
        "",
        "Schedule row `ci-pins` (cadence monthly) in `.github/recurring-schedule.json` came due on 2026-11-01. `/work-items:track recheck ci-pins` closes this issue and advances `next_due`.",
        "",
        "Check each pinned action.",
        "",
        "<!-- recurring-schedule id=ci-pins -->",
      ].join("\n"),
      labels: ["recurring"],
    },
  ]);
});

test("a row's area adds no title prefix, and next_due equal to today is due", async () => {
  const api = fakeApi();
  await fileDue({ schedule: { items: [row({ area: ["work-items", "ci"], next_due: TODAY })] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.equal(api.state.posts[0].title, "Review CI pins");
});

test("a precondition prompt that needs no confirmation is in the body", async () => {
  const prompt = "A model release must have occurred since last_checked.";
  for (const precondition of [{ id: "p", prompt }, { id: "p", prompt, requires_operator_confirmation: false }]) {
    const api = fakeApi();
    await fileDue({ schedule: { items: [row({ precondition })] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
    assert.ok(api.state.posts[0].body.endsWith(`Check each pinned action.\n\n## Precondition\n\n${prompt}\n\n<!-- recurring-schedule id=ci-pins -->`), api.state.posts[0].body);
  }
});

test("a due row that needs an operator's confirmation is held with no API call", async () => {
  const api = fakeApi();
  const calls = [];
  const call = async (...args) => (calls.push(args), api.call(...args));
  const held = row({ precondition: { id: "p", prompt: "x", requires_operator_confirmation: true } });
  const results = await fileDue({ schedule: { items: [held] }, today: TODAY, call, repo: REPO, wait: noWait });
  assert.deepEqual(results, [{ id: "ci-pins", next_due: "2026-11-01", due: true, outcome: "held", reason: HELD }]);
  assert.deepEqual(calls, []);
});

test("a held row beside a fileable row files only the fileable one", async () => {
  const api = fakeApi();
  const held = row({ id: "ablation", precondition: { id: "p", prompt: "x", requires_operator_confirmation: true } });
  const results = await fileDue({ schedule: { items: [held, row()] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.deepEqual(results.map((r) => [r.id, r.outcome]), [["ablation", "held"], ["ci-pins", "filed"]]);
  assert.deepEqual(api.state.posts.map((p) => p.title), ["Review CI pins"]);
});

test("an open recurring issue whose body marker names the row covers it, and nothing is filed", async () => {
  const api = fakeApi({ issues: [{ number: 42, labels: ["recurring"], body: "text\n<!-- recurring-schedule id=ci-pins -->" }] });
  const results = await fileDue({ schedule: { items: [row()] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.deepEqual(results, [{ id: "ci-pins", next_due: "2026-11-01", due: true, outcome: "covered", issue: 42 }]);
  assert.deepEqual(api.state.posts, []);
});

test("a marker on its own line covers the row, a CRLF line ending included", async () => {
  for (const body of ["intro\n<!-- recurring-schedule id=ci-pins -->\nmore", "intro\r\n<!-- recurring-schedule id=ci-pins -->\r\nmore"]) {
    const api = fakeApi({ issues: [{ number: 7, labels: ["recurring"], body }] });
    const [result] = await fileDue({ schedule: { items: [row()] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
    assert.deepEqual([result.outcome, result.issue], ["covered", 7], JSON.stringify(body));
  }
});

test("an inline or re-spaced marker does not cover the row, so the row is filed", async () => {
  for (const body of ["see <!-- recurring-schedule id=ci-pins --> here", "<!--recurring-schedule id=ci-pins-->", "<!--   recurring-schedule   id=ci-pins   -->", " <!-- recurring-schedule id=ci-pins -->"]) {
    const api = fakeApi({ issues: [{ number: 7, labels: ["recurring"], body }] });
    const [result] = await fileDue({ schedule: { items: [row()] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
    assert.deepEqual([result.outcome, result.issue], ["filed", 901], JSON.stringify(body));
  }
});

test("a recurring issue with no marker, or another row's marker, does not cover the row", async () => {
  const api = fakeApi({
    issues: [
      { number: 5, labels: ["recurring"], body: "[Maintenance] Review CI pins" },
      { number: 6, labels: ["recurring"], body: "<!-- recurring-schedule id=ci-pins-extra -->" },
      { number: 8, labels: ["recurring"], body: null },
    ],
  });
  const [result] = await fileDue({ schedule: { items: [row()] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.equal(result.outcome, "filed");
  assert.equal(api.state.posts.length, 1);
});

test("a marked issue on the second page of the open list still covers the row", async () => {
  const filler = Array.from({ length: 100 }, (_, i) => ({ number: i + 1, labels: ["recurring"], body: `<!-- recurring-schedule id=other-${i} -->` }));
  const api = fakeApi({ issues: [...filler, { number: 777, labels: ["recurring"], body: "<!-- recurring-schedule id=ci-pins -->" }] });
  const [result] = await fileDue({ schedule: { items: [row()] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.deepEqual([result.outcome, result.issue], ["covered", 777]);
});

test("a row not yet due is skipped without reading the issues", async () => {
  const api = fakeApi();
  const calls = [];
  const call = async (...args) => (calls.push(args), api.call(...args));
  const results = await fileDue({ schedule: { items: [row({ next_due: "2026-11-07" })] }, today: TODAY, call, repo: REPO, wait: noWait });
  assert.deepEqual(results, [{ id: "ci-pins", next_due: "2026-11-07", due: false, outcome: "not-due" }]);
  assert.deepEqual(calls, []);
});

test("a second run on the same day files nothing", async () => {
  const api = fakeApi();
  const schedule = { items: [row(), row({ id: "docs-drift", title: "Docs drift", cadence: "quarterly" })] };
  const first = await fileDue({ schedule, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.deepEqual(first.map((r) => r.outcome), ["filed", "filed"]);
  const second = await fileDue({ schedule, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.deepEqual(second.map((r) => [r.outcome, r.issue]), [["covered", 901], ["covered", 902]]);
  assert.equal(api.state.posts.length, 2);
});

test("a filing applies only the recurring label, and a missing one fails the row", async () => {
  const noCadence = fakeApi({ labels: ["recurring"] });
  await fileDue({ schedule: { items: [row()] }, today: TODAY, call: noCadence.call, repo: REPO, wait: noWait });
  assert.deepEqual(noCadence.state.posts[0].labels, ["recurring"]);
  const noRecurring = fakeApi({ labels: [] });
  const [result] = await fileDue({ schedule: { items: [row()] }, today: TODAY, call: noRecurring.call, repo: REPO, wait: noWait });
  assert.deepEqual([result.outcome, result.reason], ["failed", "label recurring does not exist"]);
  assert.deepEqual(noRecurring.state.posts, []);
});

test("an unreadable open-issue list fails every due row and files nothing", async () => {
  const call = async () => {
    throw new Error("GET /repos/o/r/issues: HTTP 500");
  };
  const results = await fileDue({ schedule: { items: [row(), row({ id: "later", next_due: "2027-01-01" })] }, today: TODAY, call, repo: REPO, wait: noWait });
  assert.deepEqual(results.map((r) => [r.id, r.outcome]), [["later", "not-due"], ["ci-pins", "failed"]]);
});

test("a row whose id cannot be a marker id fails without a write", async () => {
  const api = fakeApi();
  const [result] = await fileDue({ schedule: { items: [row({ id: "has space" })] }, today: TODAY, call: api.call, repo: REPO, wait: noWait });
  assert.deepEqual([result.outcome, result.reason], ["failed", "id is not a marker id"]);
  assert.deepEqual(api.state.posts, []);
});

test("scheduleIds reads every distinct marker id in a body", () => {
  assert.deepEqual(scheduleIds("<!-- recurring-schedule id=a -->\n<!-- recurring-schedule id=b.c_d-1 -->\n<!-- recurring-schedule id=a -->"), ["a", "b.c_d-1"]);
  assert.deepEqual(scheduleIds("<!-- recurring-schedule -->"), []);
});

async function withSchedule(items, fn) {
  const dir = mkdtempSync(join(tmpdir(), "file-due-"));
  try {
    writeFileSync(join(dir, "schedule.json"), JSON.stringify({ items }));
    return await fn(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("main writes the step summary counts, one line per row, and exits 1 on a failed write", async () => {
  await withSchedule(
    [
      row(),
      row({ id: "covered-row", title: "Covered" }),
      row({ id: "later", next_due: "2026-12-01" }),
      row({ id: "held-row", precondition: { id: "p", prompt: "x", requires_operator_confirmation: true } }),
    ],
    async (dir) => {
      const api = fakeApi({ failPost: true, issues: [{ number: 3, labels: ["recurring"], body: "<!-- recurring-schedule id=covered-row -->" }] });
      const lines = [];
      const code = await main({
        argv: [join(dir, "schedule.json")],
        env: { TODAY, REPOSITORY: REPO, GITHUB_STEP_SUMMARY: join(dir, "summary.md") },
        call: api.call,
        log: (line) => lines.push(line),
        wait: noWait,
      });
      assert.equal(code, 1);
      const summary = readFileSync(join(dir, "summary.md"), "utf8");
      assert.match(summary, /\| 4 \| 3 \| 0 \| 1 \| 1 \| 1 \| 1 \|/);
      assert.match(summary, /- covered `covered-row` by #3/);
      assert.match(summary, /- held `held-row`: needs an operator's confirmation/);
      assert.match(summary, /- failed `ci-pins`: POST \/repos\/o\/r\/issues: HTTP 502/);
      const rows = lines.filter((l) => l.startsWith("file-due {")).map((l) => JSON.parse(l.slice("file-due ".length)));
      assert.deepEqual(rows.map((r) => [r.today, r.id, r.outcome]), [
        [TODAY, "later", "not-due"],
        [TODAY, "held-row", "held"],
        [TODAY, "ci-pins", "failed"],
        [TODAY, "covered-row", "covered"],
      ]);
      assert.ok(lines.includes("::error::1 recurring schedule row(s) failed; see the step summary"), lines.join("\n"));
    },
  );
});

test("main exits 0 and counts a filed row when every write succeeds", async () => {
  await withSchedule([row()], async (dir) => {
    const api = fakeApi();
    const code = await main({ argv: [join(dir, "schedule.json")], env: { TODAY, REPOSITORY: REPO, GITHUB_STEP_SUMMARY: join(dir, "summary.md") }, call: api.call, log: () => {}, wait: noWait });
    assert.equal(code, 0);
    const summary = readFileSync(join(dir, "summary.md"), "utf8");
    assert.match(summary, /\| 1 \| 1 \| 1 \| 0 \| 0 \| 0 \| 0 \|/);
    assert.match(summary, /- filed #901 for `ci-pins`/);
  });
});

test("main without an injected call spends CALL_BUDGET through the shared client and reports the calls used", async (t) => {
  const requests = [];
  t.mock.method(globalThis, "fetch", async (url, init) => {
    requests.push(`${init.method} ${url}`);
    return new Response("[]", { status: 200, headers: { "content-type": "application/json" } });
  });
  await withSchedule([row()], async (dir) => {
    const lines = [];
    const code = await main({
      argv: [join(dir, "schedule.json")],
      env: { TODAY, REPOSITORY: REPO, GITHUB_TOKEN: "t", GITHUB_API_URL: "https://api.test", CALL_BUDGET: "1" },
      log: (line) => lines.push(line),
      wait: noWait,
    });
    assert.equal(code, 1);
    assert.deepEqual(requests, ["GET https://api.test/repos/o/r/issues?labels=recurring&state=open&per_page=100&page=1"]);
    const failed = JSON.parse(lines[0].slice("file-due ".length));
    assert.deepEqual([failed.id, failed.outcome, failed.reason], ["ci-pins", "failed", "call budget of 1 spent"]);
    assert.match(lines.at(-2), /, failed 1, calls 1$/);
  });
});
