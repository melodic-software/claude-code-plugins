// Runs the dependency-review path check of pr-run-activity-write.yml's promote
// step (the `script:` of the step with `id: promote`) against fake GitHub
// clients. A fix in scope reaches the next gate, the hold-label read, which
// fails here because the case passes no hold labels. review-threads has no
// promote step: its fix lands through apply-patch.mjs (apply-patch.test.mjs).
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

const WORKFLOW = new URL("../../workflows/pr-run-activity-write.yml", import.meta.url);
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

const HOLD = /^No hold labels were read/;

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
