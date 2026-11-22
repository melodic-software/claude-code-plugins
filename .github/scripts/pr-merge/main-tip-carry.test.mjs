import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { forgetMainTip, onMain } from "./head-ref-map.mjs";
import { mainCall, TIP } from "./on-main.fixture.mjs";
import { sharedReads } from "./rotation.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const text = readFileSync(join(root, ".github/workflows/pr-merge.yml"), "utf8");
const JOBS = ["dispatch-post-merge-runs", "merge", "enable-auto-merge"];
const READERS = /node \.base\/\.github\/scripts\/pr-merge\/(carry-run-cache\.mjs read|head-ref-map\.mjs read|lane-records\.mjs read|last-report\.mjs|verify-answers\.mjs)$/m;
const REPO = "melodic-software/claude-code-plugins";

const jobBlock = (id) => {
  const match = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(text);
  assert.ok(match, `job ${id}`);
  return match[1];
};
const stepsOf = (block) =>
  block
    .split(/\n(?=      - name: )/)
    .slice(1)
    .map((b) => ({ name: /^      - name: (.*)$/m.exec(b)[1], block: b }));
test("each job's tip step is the resolve-branch-tip action on main", () => {
  for (const job of JOBS) {
    const tip = stepsOf(jobBlock(job)).find((s) => s.name === "Resolve main's tip");
    assert.ok(tip, `${job}: tip step`);
    assert.match(tip.block, /\n {8}uses: melodic-software\/ci-workflows\/\.github\/actions\/resolve-branch-tip@[0-9a-f]{40} # v\d+\.\d+\.\d+\n {8}with:\n {10}branch: main$/m, job);
  }
});

test("every onMain reader step of the three jobs gets the job's unambiguous tip", () => {
  for (const job of JOBS) {
    const readers = stepsOf(jobBlock(job)).filter((s) => READERS.test(s.block));
    assert.ok(readers.length >= 2, `${job}: readers found`);
    for (const reader of readers) {
      assert.ok(reader.block.includes("\n          PR_MERGE_MAIN_TIP: ${{ steps.tip.outputs.unambiguous-sha }}\n"), `${job}: ${reader.name}`);
    }
  }
});

async function sweep(env, processes) {
  const shared = join(tempDir("main-tip-reads-"), "reads.json");
  const calls = [];
  const client = async (method, url) => {
    calls.push(url);
    return mainCall(url, { offMain: ["9".repeat(40)] });
  };
  const answers = [];
  for (let n = 0; n < processes; n += 1) {
    forgetMainTip();
    const actions = sharedReads(client, shared);
    answers.push(await onMain({ repo: REPO, actions, sha: "7".repeat(40), env }), await onMain({ repo: REPO, actions, sha: "9".repeat(40), env }));
  }
  return { answers, refs: calls.filter((url) => url.includes("/git/ref/")).length, compares: calls.filter((url) => url.includes("/compare/")).length };
}

test("a sweep's four reader processes read the 404 tag once each and main once, and with PR_MERGE_MAIN_TIP no ref, deciding the same", async () => {
  const before = await sweep({}, 4);
  assert.equal(before.refs, 5, "four unshared tag reads and one shared tip read");
  const after = await sweep({ PR_MERGE_MAIN_TIP: TIP }, 4);
  assert.equal(after.refs, 0, "no ref read with PR_MERGE_MAIN_TIP");
  assert.deepEqual(after.answers, before.answers);
  assert.deepEqual(before.answers, [true, false, true, false, true, false, true, false]);
  assert.equal(before.compares, 2, "each head compared once for the job");
  assert.equal(after.compares, 2, "each head compared once for the job");
});
