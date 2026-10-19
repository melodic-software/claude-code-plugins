// Runs the review-threads path check of pr-run-activity-write.yml's promote
// step (the `script:` of the step with `id: promote`) against fake GitHub
// clients. A changed path in scope reaches the next gate, the hold-label read,
// which fails here because the case passes no hold labels.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

const WORKFLOW = new URL("../../workflows/pr-run-activity-write.yml", import.meta.url);
const SCOPE = new URL("./thread-scope.mjs", import.meta.url);
const HEAD = "a".repeat(40);
const LANE = "b".repeat(40);

function promoteScript() {
  const lines = readFileSync(WORKFLOW, "utf8").split("\n");
  const id = lines.findIndex((line) => /^\s+id: promote$/.test(line));
  assert.notEqual(id, -1, "the workflow has the promote step");
  const start = lines.findIndex((line, i) => i > id && /^\s+script: \|$/.test(line));
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

const dir = mkdtempSync(join(tmpdir(), "promote-scope-"));
after(() => rmSync(dir, { recursive: true, force: true }));

// Every lane-tip tree entry is a regular file unless `modes` names it.
async function promote(files, { scope = readFileSync(SCOPE), sha256, threads = [{ path: "plugins/p/evals/c/case.yaml" }, { path: "src/round.py" }], modes = {} } = {}) {
  const threadFile = join(dir, "threads.json");
  writeFileSync(threadFile, JSON.stringify({ threads }));
  const scopeScript = join(dir, "thread-scope.mjs");
  writeFileSync(scopeScript, scope);
  const env = {
    HEAD_SHA: HEAD,
    HEAD_REF: "feature",
    LANE_BRANCH: "lane-commits/x",
    MERGE_BASE: "false",
    THREAD_FILE: threadFile,
    SCOPE_SCRIPT: scopeScript,
    SCOPE_SHA256: sha256 ?? createHash("sha256").update(readFileSync(SCOPE)).digest("hex"),
    DEPENDENCY_REVIEW: "false",
    HOLD_LABELS: "",
  };
  const saved = { ...process.env };
  Object.assign(process.env, env);
  const failed = [];
  const core = { setOutput() {}, info() {}, warning() {}, setFailed: (message) => failed.push(message) };
  const github = {
    request: async () => ({ data: { object: { sha: LANE } } }),
    async graphql(query, { expression }) {
      const dir = expression.slice(`${LANE}:`.length);
      const entries = files
        .map((f) => f.filename)
        .filter((name) => name.slice(0, Math.max(name.lastIndexOf("/"), 0)) === dir)
        .map((name) => ({ name: name.slice(dir ? dir.length + 1 : 0), ...(modes[name] ?? { type: "blob", mode: 0o100644 }) }));
      return { repository: { object: { entries } } };
    },
    rest: {
      repos: { compareCommitsWithBasehead: async () => ({ data: { files } }) },
      git: { deleteRef: async () => {} },
    },
  };
  const context = { repo: { owner: "o", repo: "r" } };
  try {
    const AsyncFunction = (async () => {}).constructor;
    await new AsyncFunction("github", "context", "core", "require", promoteScript())(
      github,
      context,
      core,
      createRequire(import.meta.url),
    );
  } finally {
    process.env = saved;
  }
  return failed;
}

const HOLD = /^No hold labels were read/;
const OUT = /^The lane branch changes a path outside the kept threads' scope or under \.github\//;

test("in-scope changes pass the path check: the thread's path, its plugin's files, a sibling test", async () => {
  const failed = await promote([
    { filename: "plugins/p/evals/c/case.yaml" },
    { filename: "plugins/p/evals/c/samples/deep/new.json" },
    { filename: "plugins/p/evals/other/samples/new.json" },
    { filename: "plugins/p/README.md" },
    { filename: "src/test_round.py" },
  ]);
  assert.equal(failed.length, 1);
  assert.match(failed[0], HOLD);
});

for (const file of [
  { filename: "plugins/q/evals/c/samples/new.json" },
  { filename: "src/lib/test_round.py" },
  { filename: ".github/workflows/x.yml" },
  { filename: "plugins/p/evals/c/x.json", previous_filename: ".github/x.yml" },
]) {
  test(`an out-of-scope change stops the move: ${file.previous_filename ?? file.filename}`, async () => {
    const failed = await promote([{ filename: "plugins/p/evals/c/case.yaml" }, file]);
    assert.equal(failed.length, 1);
    assert.match(failed[0], OUT);
  });
}

test("a rewritten scope copy, or no recorded hash, stops the move", async () => {
  const permissive = "export const inThreadScope = () => true;\n";
  for (const options of [{ scope: permissive }, { sha256: "" }]) {
    const failed = await promote([{ filename: ".github/workflows/x.yml" }], options);
    assert.deepEqual(failed, ["thread-scope.mjs does not match the base's copy; the PR branch is not moved"]);
  }
});

test("a file a kept thread's named_paths holds passes the path check; the same file unnamed stops the move", async () => {
  const named = [{ path: "plugins/p/evals/c/case.yaml", named_paths: ["plugins/p/lib/run.js"] }];
  const passed = await promote([{ filename: "plugins/p/lib/run.js" }], { threads: named });
  assert.equal(passed.length, 1);
  assert.match(passed[0], HOLD);
  const stopped = await promote([{ filename: "plugins/p/lib/run.js" }]);
  assert.match(stopped[0], OUT);
  const instruction = await promote([{ filename: "plugins/p/AGENTS.md" }], { threads: [{ ...named[0], named_paths: ["plugins/p/AGENTS.md"] }] });
  assert.match(instruction[0], OUT);
});

test("a symbolic link or gitlink the lane adds at an in-scope path stops the move; a removed file needs no entry", async () => {
  for (const mode of [{ type: "blob", mode: 0o120000 }, { type: "commit", mode: 0o160000 }]) {
    const failed = await promote([{ filename: "plugins/p/hooksx" }], { modes: { "plugins/p/hooksx": mode } });
    assert.deepEqual(failed, ["The lane branch adds or changes a path that is not a regular file (plugins/p/hooksx); the PR branch is not moved"]);
  }
  const removed = await promote([{ filename: "plugins/p/README.md", status: "removed" }], { modes: { "plugins/p/README.md": { type: "missing" } } });
  assert.match(removed[0], HOLD);
});
