import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
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
const runScript = (block) => {
  const lines = /\n {8}run: \|\n([\s\S]*)$/.exec(block)[1].split("\n");
  const end = lines.findIndex((line) => line !== "" && !line.startsWith(" ".repeat(10)));
  return (end < 0 ? lines : lines.slice(0, end)).map((line) => line.slice(10)).join("\n");
};

const HEAD = "1".repeat(40);
const TAG = "2".repeat(40);

function tipOutputs(job, listing) {
  const dir = tempDir("main-tip-");
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(dir, "listing"), listing);
  writeFileSync(join(bin, "git"), `#!/usr/bin/env bash\necho "$*" >>"${dir}/args"\ncat "${dir}/listing"\n`);
  chmodSync(join(bin, "git"), 0o755);
  const output = join(dir, "output");
  writeFileSync(output, "");
  const tip = stepsOf(jobBlock(job)).find((s) => s.name === "Resolve main's tip");
  assert.ok(tip, `${job}: tip step`);
  const run = spawnSync("bash", ["-e", "-o", "pipefail", "-c", runScript(tip.block)], {
    encoding: "utf8",
    env: { PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_REPOSITORY: REPO, TIP_BRANCH: "main", GITHUB_OUTPUT: output },
  });
  assert.equal(run.status, 0, run.stderr);
  return { output: readFileSync(output, "utf8"), args: readFileSync(join(dir, "args"), "utf8") };
}

test("each job's tip step lists the tag too and passes carry-tip only while no tag is named main", () => {
  for (const job of JOBS) {
    const plain = tipOutputs(job, `${HEAD}\trefs/heads/main\n`);
    assert.equal(plain.output, `sha=${HEAD}\ncarry-tip=${HEAD}\n`, `${job}: no tag`);
    assert.match(plain.args, /ls-remote https:\/\/github\.com\/melodic-software\/claude-code-plugins\.git refs\/heads\/main refs\/tags\/main\n$/, job);
    assert.equal(tipOutputs(job, `${HEAD}\trefs/heads/main\n${TAG}\trefs/tags/main\n`).output, `sha=${HEAD}\n`, `${job}: a tag named main`);
    assert.equal(tipOutputs(job, `${HEAD}\trefs/heads/main\n${TAG}\trefs/tags/main^{}\n`).output, `sha=${HEAD}\n`, `${job}: a peeled tag named main`);
    assert.equal(tipOutputs(job, `${HEAD}\trefs/heads/main\n${TAG}\trefs/tags/v1-main\n`).output, `sha=${HEAD}\ncarry-tip=${HEAD}\n`, `${job}: a tag only ending in main`);
  }
});

test("every onMain reader step of the three jobs gets the job's carry-tip", () => {
  for (const job of JOBS) {
    const readers = stepsOf(jobBlock(job)).filter((s) => READERS.test(s.block));
    assert.ok(readers.length >= 2, `${job}: readers found`);
    for (const reader of readers) {
      assert.ok(reader.block.includes("\n          PR_MERGE_MAIN_TIP: ${{ steps.tip.outputs.carry-tip }}\n"), `${job}: ${reader.name}`);
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

test("a sweep's four reader processes read the 404 tag once each and main once, and with carry-tip no ref, deciding the same", async () => {
  const before = await sweep({}, 4);
  assert.equal(before.refs, 5, "four unshared tag reads and one shared tip read");
  const after = await sweep({ PR_MERGE_MAIN_TIP: TIP }, 4);
  assert.equal(after.refs, 0, "no ref read with carry-tip");
  assert.deepEqual(after.answers, before.answers);
  assert.deepEqual(before.answers, [true, false, true, false, true, false, true, false]);
  assert.equal(before.compares, 2, "each head compared once for the job");
  assert.equal(after.compares, 2, "each head compared once for the job");
});
