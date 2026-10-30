// Expected values come from the trust rule last-report.mjs shares with the
// lane records (lane-records.mjs): the report is read only from the newest
// scheduled or hand-started pr-merge.yml run on main other than this one,
// holding the artifact unexpired, whose head commit is on main; any failure
// leaves no report.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { forgetMainTip } from "./head-ref-map.mjs";
import { main } from "./last-report.mjs";
import { mainCall } from "./on-main.fixture.mjs";

const REPO = "melodic-software/claude-code-plugins";
const dir = mkdtempSync(join(tmpdir(), "last-report-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const sha = (id) => String(id).padStart(40, "a");
const wf = (id, event, head_sha = sha(id)) => ({ id, event, head_branch: "main", path: ".github/workflows/pr-merge.yml", head_sha });

let n = 0;
// `runs` is the pr-merge.yml run listing, newest first; `held` lists the runs
// holding the report artifact; `offMain` the head commits not on main.
async function readLast({ runs = [], held = [], offMain = [], downloadFails = false, planted = false } = {}) {
  forgetMainTip();
  n += 1;
  const out = join(dir, `last-${n}`);
  if (planted) {
    mkdirSync(out);
    writeFileSync(join(out, "post-merge.json"), "planted");
  }
  const downloads = [];
  const actions = async (method, url) => {
    if (/\/actions\/workflows\/pr-merge\.yml\/runs\?branch=main&.*&page=1$/.test(url)) return { workflow_runs: runs };
    const onMain = mainCall(url, { offMain });
    if (onMain !== undefined) return onMain;
    const id = Number(/\/actions\/runs\/(\d+)\/artifacts\?per_page=100$/.exec(url)?.[1]);
    assert.ok(id, `unexpected call ${url}`);
    const artifacts = held.includes(id) ? [{ name: "pr-merge-post-merge-report", expired: false }] : [];
    return { total_count: artifacts.length, artifacts };
  };
  const download = (id, target) => {
    downloads.push(id);
    if (downloadFails) throw new Error("download 502");
    mkdirSync(target);
    writeFileSync(join(target, "post-merge.json"), `report of ${id}`);
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    await main({ env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "999", LAST_REPORT_DIR: out }, actions, download });
  } finally {
    console.log = log;
  }
  const file = join(out, "post-merge.json");
  return { downloads, lines, report: existsSync(file) ? readFileSync(file, "utf8") : undefined };
}

test("the newest trusted run's report on main is read, this run and other events aside", async () => {
  const result = await readLast({
    runs: [wf(999, "schedule"), wf(8, "pull_request_target"), wf(7, "schedule"), wf(6, "workflow_dispatch")],
    held: [999, 8, 7, 6],
    offMain: [sha(7)],
  });
  // Run 7's head commit is off main, so run 6 (hand-started) is read.
  assert.deepEqual(result.downloads, [6]);
  assert.equal(result.report, "report of 6");
});

test("no earlier report, or one that fails to download, leaves none, even one planted", async () => {
  const none = await readLast({ runs: [wf(7, "schedule")], held: [], planted: true });
  assert.deepEqual(none.downloads, []);
  assert.equal(none.report, undefined);
  const failed = await readLast({ runs: [wf(7, "schedule")], held: [7], planted: true });
  assert.equal(failed.report, "report of 7");
  const broken = await readLast({ runs: [wf(7, "schedule")], held: [7], downloadFails: true, planted: true });
  assert.equal(broken.report, undefined);
  assert.match(broken.lines.join("\n"), /^::warning title=last post-merge report::download 502; the post-merge check runs$/m);
});
