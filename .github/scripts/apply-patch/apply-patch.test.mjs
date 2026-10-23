import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { checkRow, credentialIn, hasConflictMarkers, keptThreadsFrom, loadRules, main, mergeFrom, push, pushReason, REFUSALS, refusalsOf, RULES_PATH, rowFor, select } from "./apply-patch.mjs";

// The registry as committed: the rows these tests hold apply-patch to.
const REPO_ROOT = join(import.meta.dirname, "../../..");
const RULES = loadRules(REPO_ROOT);
const row = (name, change = {}) => ({ ...rowFor(RULES, { prepare: name === "default" ? "" : name }), ...change });

const sha256 = (text) => createHash("sha256").update(text).digest("hex");
const entry = (path, oldMode = "100644", newMode = "100644") => ({ path, oldMode, newMode, newSha: "1".repeat(40) });

// Credential shapes built at run time, so no literal token sits in this file.
const ANTHROPIC_KEY = ["sk", "ant", "api03", "A1b2".repeat(20)].join("-");
const OAUTH_TOKEN = ["sk", "ant", "oat01", "Z9y8".repeat(20)].join("-");
// The stateless installation token is ghs_ then a JWT of about 520 characters: three
// base64url segments joined by '.', each segment obviously fake. The first carries an
// app-id-like prefix; the second has none, so no numeric app id is assumed.
const JWT = Array(3).fill("FAKE-not_a_token".repeat(10)).join(".");
const STATELESS_TOKEN = `${"ghs"}_123456_${JWT}`;
const GITHUB_TOKENS = [`${"ghp"}_${"a1".repeat(18)}`, `${"ghs"}_${"B2".repeat(18)}`, `${"github"}_pat_${"c3".repeat(41)}`, STATELESS_TOKEN, `${"ghs"}_${JWT}`];

function scratch(t) {
  const dir = mkdtempSync(join(tmpdir(), "apply-patch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

// --- the refusal table: each refused path or mode, one case each ---

test("refuses .github/workflows/x.yml", () => {
  assert.deepEqual(refusalsOf(entry(".github/workflows/x.yml")), ["github-workflows"]);
});

test("refuses .GitHub/Workflows/x in another case", () => {
  assert.deepEqual(refusalsOf(entry(".GitHub/Workflows/x")), ["github-workflows"]);
});

test("refuses .github/../.github/workflows/x through a .. segment", () => {
  assert.deepEqual(refusalsOf(entry(".github/../.github/workflows/x")), ["github-workflows"]);
});

test("refuses a/../.github/workflows/x through a .. segment", () => {
  assert.deepEqual(refusalsOf(entry("a/../.github/workflows/x")), ["github-workflows"]);
});

test("admits the rest of .github/: scripts, actions, standards and config", () => {
  for (const path of [".github/scripts/x.mjs", ".github/actions/a/action.yml", ".github/standards/s/policy.json", ".github/dependabot.yml", ".github/workflows.md"]) {
    assert.deepEqual(refusalsOf(entry(path)), [], path);
  }
});

test("refuses .claude/settings.json as a settings file only", () => {
  assert.deepEqual(refusalsOf(entry(".claude/settings.json")), ["settings"]);
});

test("refuses CODEOWNERS where GitHub reads it: the root, .github/ and docs/", () => {
  for (const path of ["CODEOWNERS", ".github/CODEOWNERS", "docs/codeowners", "Docs/CODEOWNERS"]) {
    assert.deepEqual(refusalsOf(entry(path)), ["codeowners"], path);
  }
  for (const path of ["plugins/p/CODEOWNERS", "docs/sub/CODEOWNERS", "CODEOWNERS.md"]) {
    assert.deepEqual(refusalsOf(entry(path)), [], path);
  }
});

test("admits the root .mcp.json", () => {
  assert.deepEqual(refusalsOf(entry(".mcp.json")), []);
});

test("admits a plugin's .mcp.json", () => {
  assert.deepEqual(refusalsOf(entry("plugins/p/.mcp.json")), []);
});

test("refuses .gitmodules", () => {
  assert.deepEqual(refusalsOf(entry(".gitmodules")), ["gitmodules"]);
});

test("refuses plugins/p/settings.local.json", () => {
  assert.deepEqual(refusalsOf(entry("plugins/p/settings.local.json")), ["settings"]);
});

test("refuses a symbolic link, mode 120000", () => {
  assert.deepEqual(refusalsOf(entry("docs/link", "000000", "120000")), ["symlink"]);
});

test("refuses a gitlink, mode 160000", () => {
  assert.deepEqual(refusalsOf(entry("vendor/sub", "160000", "160000")), ["gitlink"]);
});

test("admits plugin hooks, .claude-plugin, .claude, lib, scripts, CLAUDE.md and AGENTS.md", () => {
  for (const path of ["plugins/p/hooks/hooks.json", "plugins/p/.claude-plugin/plugin.json", ".claude/rules/r.md", "lib/x.mjs", "scripts/x.sh", "CLAUDE.md", "plugins/p/AGENTS.md"]) {
    assert.deepEqual(refusalsOf(entry(path)), [], path);
  }
});

// --- push, against a real repository and a fake of the GitHub API ---

const git = (cwd, args, input) => execFileSync("git", args, { cwd, input, encoding: "utf8" }).trim();

function commitAll(repo, message) {
  git(repo, ["add", "-A"]);
  git(repo, ["commit", "-q", "-m", message]);
  return git(repo, ["rev-parse", "HEAD"]);
}

// A repository at a head commit, and a patch the model's edits make against it.
function repoWithPatch(t, edit, { renames = false, head: seed = () => {} } = {}) {
  const repo = scratch(t);
  git(repo, ["init", "-q", "-b", "main"]);
  git(repo, ["config", "user.email", "t@example.com"]);
  git(repo, ["config", "user.name", "t"]);
  mkdirSync(join(repo, "scripts"));
  writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\nfoo=1\n");
  writeFileSync(join(repo, "README.md"), "# r\n");
  writeFileSync(join(repo, "notes.md"), "notes\n");
  seed(repo);
  const head = commitAll(repo, "head");
  edit(repo);
  git(repo, ["add", "-A"]);
  const text = execFileSync("git", ["diff", "--cached", "--binary", "--full-index", renames ? "-M" : "--no-renames", head], { cwd: repo, encoding: "utf8" });
  git(repo, ["reset", "-q", "--hard", head]);
  const patchFile = join(scratch(t), "patch.diff");
  writeFileSync(patchFile, text);
  return { repo, head, patchFile, sum: sha256(text) };
}

// Every call is recorded by name; trees are built with git, as GitHub would.
function fakeApi(repo, head, overrides = {}) {
  const calls = [];
  const record = (name, value) => {
    calls.push(typeof value === "undefined" ? name : { [name]: value });
  };
  let tip = head;
  return {
    calls,
    getPull: async () => (record("getPull"), overrides.pull ?? { draft: false, head: { repo: { full_name: "o/r" } } }),
    listLabels: async () => (record("listLabels"), overrides.labels ?? []),
    readBranch: async () => (record("readBranch"), overrides.branch ?? tip),
    createBlob: async (content) => (record("createBlob"), overrides.blobSha ?? git(repo, ["hash-object", "-w", "--stdin"], Buffer.from(content, "base64"))),
    createTree: async (baseTree, entries) => {
      record("createTree");
      if (overrides.tree) {
        return overrides.tree;
      }
      const index = join(mkdtempSync(join(tmpdir(), "apply-patch-index-")), "index");
      const env = { ...process.env, GIT_INDEX_FILE: index };
      execFileSync("git", ["read-tree", baseTree], { cwd: repo, env });
      for (const item of entries) {
        const line = item.sha === null ? `0 ${"0".repeat(40)}\t${item.path}\n` : `${item.mode} ${item.sha}\t${item.path}\n`;
        execFileSync("git", ["update-index", "--index-info"], { cwd: repo, env, input: line });
      }
      const tree = execFileSync("git", ["write-tree"], { cwd: repo, env, encoding: "utf8" }).trim();
      rmSync(dirname(index), { recursive: true, force: true });
      return tree;
    },
    createCommit: async (message, tree, parents) => (record("createCommit", { message, tree, parents }), "c".repeat(40)),
    updateRef: async (ref, sha, force) => {
      record("updateRef", { ref, sha, force });
      tip = overrides.afterWrite ?? sha;
    },
    createRef: async (ref, sha) => {
      record("createRef", { ref, sha });
      tip = sha;
    },
  };
}

const writes = (api) => api.calls.filter((call) => typeof call !== "string" || call.startsWith("create"));

const pushWith = (fix, api, extra = {}) =>
  push({
    api,
    cwd: fix.repo,
    gitBin: "git",
    row: row("default"),
    pr: 42,
    headSha: fix.head,
    patchHeadSha: fix.head,
    headRef: "feat/x",
    lane: "some-lane",
    activity: "some-activity",
    patchFile: fix.patchFile,
    patchSha256: fix.sum,
    holdLabels: ["do-not-merge", "needs-human"],
    repository: "o/r",
    ...extra,
  });

test("a new executable bit the patch sets pushes with the mode it set", async (t) => {
  const fix = repoWithPatch(t, (repo) => chmodSync(join(repo, "README.md"), 0o755));
  const api = fakeApi(fix.repo, fix.head);
  assert.equal((await pushWith(fix, api)).outcome, "pushed");
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.equal(git(fix.repo, ["ls-tree", createCommit.tree, "--", "README.md"]).split(" ")[0], "100755");
});

// A fix that makes two 100644 scripts executable and edits a test fixture,
// with no path under .github/.
test("under the ci-context row a fix that sets script exec bits and edits a fixture pushes, escalating nothing", async (t) => {
  const fix = repoWithPatch(
    t,
    (repo) => {
      chmodSync(join(repo, "scripts/x.sh"), 0o755);
      chmodSync(join(repo, "scripts/y.sh"), 0o755);
      writeFileSync(join(repo, "notes.md"), "notes\nget-field-options\n");
    },
    { head: (repo) => writeFileSync(join(repo, "scripts/y.sh"), "#!/bin/sh\n") },
  );
  const api = fakeApi(fix.repo, fix.head);
  const lines = [];
  assert.deepEqual(await pushWith(fix, api, { row: row("ci-context"), log: (line) => lines.push(line) }), { outcome: "pushed", commit: "c".repeat(40), branch: "feat/x" });
  assert.deepEqual(lines, ["pushed " + "c".repeat(40) + " (3 path(s)) onto feat/x"]);
  const { createCommit } = api.calls.find((call) => call.createCommit);
  for (const path of ["scripts/x.sh", "scripts/y.sh"]) {
    assert.equal(git(fix.repo, ["ls-tree", createCommit.tree, "--", path]).split(" ")[0], "100755", path);
  }
});

test("refuses a rename from an allowed path into .github/workflows/", async (t) => {
  const fix = repoWithPatch(
    t,
    (repo) => {
      mkdirSync(join(repo, ".github/workflows"), { recursive: true });
      renameSync(join(repo, "notes.md"), join(repo, ".github/workflows/notes.md"));
    },
    { renames: true },
  );
  assert.match(readFileSync(fix.patchFile, "utf8"), /^rename to \.github\/workflows\/notes\.md$/m);
  const api = fakeApi(fix.repo, fix.head);
  const lines = [];
  assert.deepEqual(await pushWith(fix, api, { log: (line) => lines.push(line) }), { outcome: "escalate", escalationReason: "patch-protected-path" });
  assert.deepEqual(lines, ["refused (rename-into-refused): .github/workflows/notes.md"]);
  assert.deepEqual(api.calls, []);
});

test("a patch that edits .github/scripts/ or .github/actions/ pushes", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    mkdirSync(join(repo, ".github/scripts"), { recursive: true });
    mkdirSync(join(repo, ".github/actions/a"), { recursive: true });
    writeFileSync(join(repo, ".github/scripts/x.mjs"), "export {};\n");
    writeFileSync(join(repo, ".github/actions/a/action.yml"), "runs: {}\n");
  });
  assert.deepEqual(await pushWith(fix, fakeApi(fix.repo, fix.head), { row: row("ci-context") }), { outcome: "pushed", commit: "c".repeat(40), branch: "feat/x" });
});

test("refuses a patched path holding a backslash, such as a .github\\x.yml add", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, ".github\\x.yml"), "on: push\n"));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api), { outcome: "escalate", escalationReason: "patch-protected-path" });
  assert.deepEqual(api.calls, []);
});

test("a patch that touches .github/ is refused end to end before any API call", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    mkdirSync(join(repo, ".github/workflows"), { recursive: true });
    writeFileSync(join(repo, ".github/workflows/ci.yml"), "on: push\n");
  });
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api, { row: row("ci-context") }), { outcome: "escalate", escalationReason: "ci-fix-protected-path" });
  assert.deepEqual(api.calls, []);
});

// --- row lookup and the row contract ---

test("row lookup picks the producer's prepare-mode row", () => {
  const picked = rowFor(RULES, { prepare: "review-threads" });
  assert.equal(picked.name, "review-threads");
  assert.deepEqual(picked.allow, ["kept-threads"]);
  assert.equal(picked["max-files"], 300);
});

test("row lookup falls back to default for a producer with no prepare mode, and throws for an unregistered one", () => {
  const picked = rowFor(RULES, { prepare: "" });
  assert.equal(picked.name, "default");
  assert.equal(picked.commit.message, "Apply {activity} on {ref}");
  assert.throws(() => rowFor(RULES, { prepare: "no-such-mode" }), /no `no-such-mode` row/);
  assert.throws(() => rowFor(RULES, { prepare: "issue" }), /belongs to the issue target/);
  assert.throws(() => rowFor(RULES, { target: "branch" }), /unknown patch target branch/);
});

test("a row without the universal refused set is rejected", () => {
  const refuse = RULES.default.refuse.filter((name) => name !== "settings");
  assert.throws(() => checkRow(row("default", { refuse })), /does not refuse settings/);
});

test("an unknown predicate throws before any git or API write", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  const api = fakeApi(fix.repo, fix.head);
  await assert.rejects(pushWith(fix, api, { row: row("default", { allow: ["no-such-predicate"] }) }), /unknown predicate: no-such-predicate/);
  assert.deepEqual(api.calls, []);
  assert.equal(git(fix.repo, ["status", "--porcelain"]), "");
});

test("a patch over max-files is refused", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    writeFileSync(join(repo, "README.md"), "# changed\n");
    writeFileSync(join(repo, "notes.md"), "changed\n");
  });
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api, { row: row("default", { "max-files": 1 }) }), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(api.calls, []);
});

// Agent instructions, plugin hooks and manifests, MCP config and .claude
// reach review on every row; settings files, submodules and code owners stay
// refused on every row.
const INSTRUCTION_PATHS = [
  ["CLAUDE.md", []],
  ["AGENTS.md", []],
  ["plugins/p/skills/s/CLAUDE.md", []],
  ["docs/Agents.MD", []],
  [".claude/settings.json", ["settings"]],
  ["plugins/p/.claude/rules/r.md", []],
  [".CLAUDE/x.md", []],
  ["plugins/p/hooks/hooks.json", []],
  ["plugins/p/Hooks/run.mjs", []],
  ["plugins/p/.claude-plugin/plugin.json", []],
  [".claude-plugin/marketplace.json", []],
  [".mcp.json", []],
  ["plugins/p/.MCP.json", []],
  [".gitmodules", ["gitmodules"]],
  ["CODEOWNERS", ["codeowners"]],
  ["docs/CODEOWNERS", ["codeowners"]],
  ["docs/codeowners", ["codeowners"]],
];

test("every row refuses the same instruction paths: settings, submodules and code owners only", () => {
  for (const [path, refusals] of INSTRUCTION_PATHS) {
    for (const name of Object.keys(RULES)) {
      assert.deepEqual(refusalsOf(entry(path), RULES[name].refuse), refusals, `${name} ${path}`);
    }
  }
});

// fix-docs hands on its patch with no prepare mode, so the default row holds
// it: an edit to an agent instruction or a plugin hook pushes, and one to a
// code owners file is refused whole before any API call.
for (const [path, edit] of [
  ["CLAUDE.md", (repo) => writeFileSync(join(repo, "CLAUDE.md"), "Follow the rules.\n")],
  ["docs/AGENTS.md", (repo) => (mkdirSync(join(repo, "docs")), writeFileSync(join(repo, "docs/AGENTS.md"), "x\n"))],
  ["plugins/x/hooks/h.sh", (repo) => (mkdirSync(join(repo, "plugins/x/hooks"), { recursive: true }), writeFileSync(join(repo, "plugins/x/hooks/h.sh"), "x\n"))],
]) {
  test(`a fix-docs patch that edits ${path} pushes`, async (t) => {
    const fix = repoWithPatch(t, (repo) => {
      writeFileSync(join(repo, "README.md"), "# fixed\n");
      edit(repo);
    });
    assert.equal((await pushWith(fix, fakeApi(fix.repo, fix.head), { lane: "pr-unblock", activity: "fix-docs" })).outcome, "pushed");
  });
}

test("a fix-docs patch that edits docs/CODEOWNERS is refused patch-protected-path before any API call", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    writeFileSync(join(repo, "README.md"), "# fixed\n");
    mkdirSync(join(repo, "docs"));
    writeFileSync(join(repo, "docs/CODEOWNERS"), "* @o\n");
  });
  const api = fakeApi(fix.repo, fix.head);
  const lines = [];
  assert.deepEqual(await pushWith(fix, api, { lane: "pr-unblock", activity: "fix-docs", log: (line) => lines.push(line) }), {
    outcome: "escalate",
    escalationReason: "patch-protected-path",
  });
  assert.deepEqual(lines, ["refused (codeowners): docs/CODEOWNERS"]);
  assert.deepEqual(api.calls, []);
});

test("a fix-docs patch of 300 files pushes, and one of 301 escalates patch-invalid with no API call", async (t) => {
  const files = (count) => (repo) => {
    mkdirSync(join(repo, "gen"));
    for (let i = 0; i < count; i += 1) {
      writeFileSync(join(repo, `gen/f${i}.md`), `${i}\n`);
    }
  };
  const atCap = repoWithPatch(t, files(300));
  assert.equal((await pushWith(atCap, fakeApi(atCap.repo, atCap.head))).outcome, "pushed");
  const over = repoWithPatch(t, files(301));
  const refused = fakeApi(over.repo, over.head);
  assert.deepEqual(await pushWith(over, refused), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(refused.calls, []);
});

test("a fix-docs patch commits Apply fix-docs on the head with the Lane-Activity: pr-unblock/fix-docs trailer", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# fixed\n"));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api, { lane: "pr-unblock", activity: "fix-docs" }), { outcome: "pushed", commit: "c".repeat(40), branch: "feat/x" });
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.equal(createCommit.message, "Apply fix-docs on feat/x\n\nLane-Activity: pr-unblock/fix-docs\n");
  assert.deepEqual(createCommit.parents, [fix.head]);
});

test("a fix-ci patch that edits CLAUDE.md pushes", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "CLAUDE.md"), "Run the checks.\n"));
  assert.equal((await pushWith(fix, fakeApi(fix.repo, fix.head), { row: row("ci-context") })).outcome, "pushed");
});

test("without PATCH_PREPARE a fix-ci patch falls to the default row, which refuses the same paths and gives other reasons", () => {
  const unset = rowFor(RULES, { prepare: "" });
  const fixCi = rowFor(RULES, { prepare: "ci-context" });
  assert.equal(unset.name, "default");
  assert.deepEqual(unset.refuse, fixCi.refuse);
  assert.equal(unset["reads-report"], null);
  assert.equal(fixCi["reads-report"], "ci-escalations");
  assert.ok(!unset.escalations.includes("ci-fix-protected-path"));
});

test("a row with no requires list throws before any git or API work", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  const api = fakeApi(fix.repo, fix.head);
  const { requires, ...rest } = row("default");
  assert.deepEqual(requires, []);
  assert.throws(() => checkRow(rest), /row `default` has no requires list/);
  await assert.rejects(pushWith(fix, api, { row: rest }), /has no requires list/);
  await assert.rejects(pushWith(fix, api, { row: { ...rest, requires: "dependency-verdict: fix" } }), /has no requires list/);
  assert.deepEqual(api.calls, []);
});

// One blob per file plus seven calls, so the 300 cap bounds the writes.
test("a fix-ci patch of 300 files pushes with 307 API calls, and one of 301 is refused with none", async (t) => {
  const files = (count) => (repo) => {
    mkdirSync(join(repo, "gen"));
    for (let i = 0; i < count; i += 1) {
      writeFileSync(join(repo, `gen/f${i}.txt`), `${i}\n`);
    }
  };
  const atCap = repoWithPatch(t, files(300));
  const api = fakeApi(atCap.repo, atCap.head);
  assert.equal((await pushWith(atCap, api, { row: row("ci-context") })).outcome, "pushed");
  assert.equal(api.calls.length, 307);
  const over = repoWithPatch(t, files(301));
  const refused = fakeApi(over.repo, over.head);
  assert.deepEqual(await pushWith(over, refused, { row: row("ci-context") }), { outcome: "escalate", escalationReason: "ci-fix-invalid" });
  assert.deepEqual(refused.calls, []);
});

// --- the dependency-review row: a fix to manifests a Dependabot PR already has ---

// A plain version bump of x from 1.0.0 to 2.0.0 and of numpy, as
// dependency-classify.mjs's fixRefusal admits one (its own tests hold the rule).
const PKG = (range, extra = {}) => `${JSON.stringify({ name: "p", scripts: { test: "node t.js" }, dependencies: { x: range }, ...extra }, null, 2)}\n`;
const LOCK = (version, resolved = `https://registry.npmjs.org/x/-/x-${version}.tgz`) =>
  `${JSON.stringify(
    { lockfileVersion: 3, packages: { "": { dependencies: { x: `^${version}` } }, "node_modules/x": { version, resolved, integrity: `sha512-${"A".repeat(86)}==` } } },
    null,
    2,
  )}\n`;
const REQS = (version, hash) => `numpy==${version} \\\n    --hash=sha256:${hash.repeat(64)}\n    # via onnxruntime\n`;
const PAIRS = [["npm", "/"], ["pip", "/"]];

// A head that holds the manifests at the old versions, and a patch of `edit`.
function dependencyPatch(t, edit) {
  return repoWithPatch(t, (repo) => edit(repo), {
    head: (repo) => {
      writeFileSync(join(repo, "package.json"), PKG("^1.0.0"));
      writeFileSync(join(repo, "package-lock.json"), LOCK("1.0.0"));
      writeFileSync(join(repo, "requirements.txt"), REQS("2.5.3", "a"));
    },
  });
}
const bump = (repo) => {
  writeFileSync(join(repo, "package.json"), PKG("^2.0.0"));
  writeFileSync(join(repo, "package-lock.json"), LOCK("2.0.0"));
  writeFileSync(join(repo, "requirements.txt"), REQS("2.5.4", "b"));
};
const dependencyPush = (fix, api, extra = {}) =>
  pushWith(fix, api, { row: row("dependency-review"), context: { dependencyVerdict: "fix", dependabotConfig: PAIRS }, ...extra });

test("requires dependency-verdict: fix refuses a patch without that verdict and applies one with it", async (t) => {
  const fix = dependencyPatch(t, bump);
  for (const verdict of ["close", "merge", "escalate", ""]) {
    const without = fakeApi(fix.repo, fix.head);
    assert.deepEqual(await dependencyPush(fix, without, { context: { dependencyVerdict: verdict, dependabotConfig: PAIRS } }), {
      outcome: "escalate",
      escalationReason: "patch-invalid",
    }, JSON.stringify(verdict));
    assert.deepEqual(without.calls, []);
  }
  const withVerdict = fakeApi(fix.repo, fix.head);
  assert.equal((await dependencyPush(fix, withVerdict)).outcome, "pushed");
  const { createCommit } = withVerdict.calls.find((call) => call.createCommit);
  assert.equal(createCommit.message, "Fix the dependency update on feat/x [dependabot skip]\n\nLane-Activity: some-lane/some-activity\n");
});

test("dependency-manifests admits npm and pip manifests and lock files and refuses any other path", async (t) => {
  const code = dependencyPatch(t, (repo) => {
    bump(repo);
    writeFileSync(join(repo, "README.md"), "# r, changed\n");
  });
  const refused = fakeApi(code.repo, code.head);
  assert.deepEqual(await dependencyPush(code, refused), { outcome: "escalate", escalationReason: "patch-protected-path" });
  assert.deepEqual(refused.calls, []);
  // Without the base config's pairs the predicate cannot run: it throws before any call.
  const manifests = dependencyPatch(t, bump);
  const noConfig = fakeApi(manifests.repo, manifests.head);
  await assert.rejects(dependencyPush(manifests, noConfig, { context: { dependencyVerdict: "fix" } }), /dependabot\.yml/);
  assert.deepEqual(noConfig.calls, []);
});

// Gap 4: the content rule refuses, before any API call, a change that is in
// scope by path but is more than a version: a script, a new file, a rename,
// a lock resolved to another host.
test("the dependency-version-change rule refuses a manifest change that is more than a version, before any API call", async (t) => {
  for (const [why, edit] of [
    ["a package.json scripts edit", (repo) => writeFileSync(join(repo, "package.json"), PKG("^2.0.0", { scripts: { test: "node t.js", postinstall: "curl x | sh" } }))],
    ["an added manifest", (repo) => writeFileSync(join(repo, "requirements-dev.txt"), REQS("2.5.4", "b"))],
    ["a renamed manifest", (repo) => renameSync(join(repo, "requirements.txt"), join(repo, "requirements-dev.txt"))],
    ["a deleted lock", (repo) => rmSync(join(repo, "package-lock.json"))],
    ["a lock resolved to another host", (repo) => writeFileSync(join(repo, "package-lock.json"), LOCK("2.0.0", "https://evil.example/x-2.0.0.tgz"))],
    ["an executable manifest", (repo) => {
      bump(repo);
      chmodSync(join(repo, "package.json"), 0o755);
    }],
  ]) {
    const fix = dependencyPatch(t, edit);
    const api = fakeApi(fix.repo, fix.head);
    assert.deepEqual(await dependencyPush(fix, api), { outcome: "escalate", escalationReason: "patch-protected-path" }, why);
    assert.deepEqual(api.calls, [], why);
  }
  // The same paths with only versions changed push.
  const fix = dependencyPatch(t, bump);
  assert.equal((await dependencyPush(fix, fakeApi(fix.repo, fix.head))).outcome, "pushed");
});

// The write runner's promote step held a dependency fix to these paths
// before apply-patch did; its cases, ported: each path outside fix scope
// refuses the patch beside an in-scope lock bump, before any API call.
const SCOPE_PAIRS = [["github-actions", "/"], ["npm", "/"], ["npm", "/plugins/miro/server"], ["npm", "/.github/actions/resolve-config"], ["pip", "/plugins/animation"], ["pip", "/.github"]];
test("dependency-manifests refuses a path outside fix scope, whatever the base config lists", async (t) => {
  for (const path of [
    "plugins/miro/server/src/index.js",
    ".github/workflows/x.yml",
    ".github/actions/resolve-config/package.json",
    ".github/requirements-ci.txt",
    "plugins/animation/setup.py",
    "plugins/animation/pyproject.toml",
    "plugins/unlisted/package.json",
    "plugins/miro/server/sub/package.json",
  ]) {
    const fix = dependencyPatch(t, (repo) => {
      writeFileSync(join(repo, "package-lock.json"), LOCK("2.0.0"));
      mkdirSync(join(repo, dirname(path)), { recursive: true });
      writeFileSync(join(repo, path), "x\n");
    });
    const api = fakeApi(fix.repo, fix.head);
    assert.deepEqual(await dependencyPush(fix, api, { context: { dependencyVerdict: "fix", dependabotConfig: SCOPE_PAIRS } }), { outcome: "escalate", escalationReason: "patch-protected-path" }, path);
    assert.deepEqual(api.calls, [], path);
  }
  // The npm manifests at the listed root push.
  const listed = dependencyPatch(t, (repo) => {
    writeFileSync(join(repo, "package.json"), PKG("^2.0.0"));
    writeFileSync(join(repo, "package-lock.json"), LOCK("2.0.0"));
  });
  assert.equal((await dependencyPush(listed, fakeApi(listed.repo, listed.head), { context: { dependencyVerdict: "fix", dependabotConfig: SCOPE_PAIRS } })).outcome, "pushed");
  // An empty config admits nothing.
  const fix = dependencyPatch(t, bump);
  await assert.rejects(dependencyPush(fix, fakeApi(fix.repo, fix.head), { context: { dependencyVerdict: "fix", dependabotConfig: [] } }), /dependabot\.yml/);
});

test("the dependency-version-change rule refuses a lock repointed at another package and an index URL", async (t) => {
  for (const [why, edit] of [
    ["a lock repointed at another package", (repo) => writeFileSync(join(repo, "package-lock.json"), LOCK("2.0.0", "https://registry.npmjs.org/evilpkg/-/evilpkg-6.6.6.tgz"))],
    ["an --extra-index-url line", (repo) => writeFileSync(join(repo, "requirements.txt"), `--extra-index-url https://evil.example/simple\n${REQS("2.5.4", "b")}`)],
  ]) {
    const fix = dependencyPatch(t, edit);
    const api = fakeApi(fix.repo, fix.head);
    assert.deepEqual(await dependencyPush(fix, api), { outcome: "escalate", escalationReason: "patch-protected-path" }, why);
    assert.deepEqual(api.calls, [], why);
  }
});

test("checkRow names an unknown content rule", () => {
  assert.throws(() => checkRow(row("dependency-review", { "content-rule": "anything" })), /unknown content rule: anything/);
  assert.equal(RULES["dependency-review"]["content-rule"], "dependency-version-change");
});

// Gap 3: the pairs come from BASE_DIR's dependabot.yml, never the checkout's.
test("main reads the dependency-manifests pairs from the base dependabot.yml", async (t) => {
  const fix = dependencyPatch(t, bump);
  const base = scratch(t);
  mkdirSync(join(base, dirname(RULES_PATH)), { recursive: true });
  cpSync(join(REPO_ROOT, RULES_PATH), join(base, RULES_PATH));
  // The checkout's copy would admit the root; the base's admits it too only once written.
  mkdirSync(join(fix.repo, ".github"), { recursive: true });
  writeFileSync(join(fix.repo, ".github/dependabot.yml"), "updates:\n  - package-ecosystem: npm\n    directory: /\n  - package-ecosystem: pip\n    directory: /\n");
  const out = scratch(t);
  const env = {
    BASE_DIR: base,
    PATCH_PREPARE: "dependency-review",
    GH_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    PR_NUMBER: "42",
    HEAD_SHA: fix.head,
    PATCH_HEAD_SHA: fix.head,
    HEAD_REF: "feat/x",
    LANE: "pr-unblock",
    PATCH_ACTIVITY: "review-dependency",
    PATCH_FILE: fix.patchFile,
    PATCH_SHA256: fix.sum,
    HOLD_LABELS: "[]",
    DEPENDENCY_VERDICT: "fix",
    SKIP_REASON_FILE: join(out, "skip"),
    ESCALATION_REASON_FILE: join(out, "escalation"),
    GITHUB_OUTPUT: join(out, "output"),
  };
  await assert.rejects(main([], env, { api: fakeApi(fix.repo, fix.head), cwd: fix.repo, gitBin: "git", log: () => {} }), /dependabot\.yml/);
  mkdirSync(join(base, ".github"), { recursive: true });
  writeFileSync(join(base, ".github/dependabot.yml"), "updates:\n  - package-ecosystem: npm\n    directory: /\n  - package-ecosystem: pip\n    directory: /\n");
  await main([], env, { api: fakeApi(fix.repo, fix.head), cwd: fix.repo, gitBin: "git", log: () => {} });
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^commit=c{40}$/m);
});

test("Git Data API calls per applied patch are one blob per changed file plus tree, commit and ref update plus the four re-reads", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    writeFileSync(join(repo, "README.md"), "# changed\n");
    writeFileSync(join(repo, "notes.md"), "changed\n");
    writeFileSync(join(repo, "NEW.md"), "new\n");
  });
  const api = fakeApi(fix.repo, fix.head);
  assert.equal((await pushWith(fix, api)).outcome, "pushed");
  const names = api.calls.map((call) => (typeof call === "string" ? call : Object.keys(call)[0]));
  assert.equal(names.filter((name) => name === "createBlob").length, 3);
  assert.equal(names.length, 3 + 3 + 4);
  assert.deepEqual(names.filter((name) => !name.startsWith("createBlob")), ["getPull", "listLabels", "readBranch", "createTree", "createCommit", "updateRef", "readBranch"]);
});

test("a pushed patch commits the row's message and trailer on the gated head and moves the branch without force", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n"));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api, { row: row("ci-context") }), { outcome: "pushed", commit: "c".repeat(40), branch: "feat/x" });
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.equal(createCommit.message, "Fix failing CI checks on feat/x\n\nLane-Activity: some-lane/some-activity\n");
  assert.deepEqual(createCommit.parents, [fix.head]);
  assert.deepEqual(api.calls.at(-2), { updateRef: { ref: "heads/feat/x", sha: "c".repeat(40), force: false } });
});

// The kept threads as keptThreadsFrom reads them from a threads.json.
const keptOf = (threads) => ({ paths: new Set(threads.map((thread) => thread.path)), threads });

test("kept-threads admits a kept thread's path and refuses one outside every thread's scope", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  const kept = fakeApi(fix.repo, fix.head);
  assert.equal((await pushWith(fix, kept, { row: row("review-threads"), context: { keptThreads: keptOf([{ path: "README.md" }]) } })).outcome, "pushed");
  const outside = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, outside, { row: row("review-threads"), context: { keptThreads: keptOf([{ path: "notes.md" }]) } }), {
    outcome: "escalate",
    escalationReason: "patch-protected-path",
  });
  assert.deepEqual(outside.calls, []);
  await assert.rejects(pushWith(fix, fakeApi(fix.repo, fix.head), { row: row("review-threads") }), /kept thread paths/);
  await assert.rejects(pushWith(fix, fakeApi(fix.repo, fix.head), { row: row("review-threads"), context: { keptThreads: new Set(["README.md"]) } }), /kept thread paths/);
});

// The review-threads row's scope, as the write runner's promote step held a
// lane branch to it: each case patches the files named, onto a head holding
// them, under kept threads on plugins/p/evals/c/case.yaml and src/round.py.
const SCOPE_THREADS = [{ path: "plugins/p/evals/c/case.yaml" }, { path: "src/round.py" }];
const threadPatch = (t, paths) =>
  repoWithPatch(t, (repo) => {
    for (const path of paths) {
      mkdirSync(join(repo, dirname(path)), { recursive: true });
      writeFileSync(join(repo, path), `${path}\n`);
    }
  });
const threadPush = (fix, threads = SCOPE_THREADS) => pushWith(fix, fakeApi(fix.repo, fix.head), { row: row("review-threads"), context: { keptThreads: keptOf(threads) } });

test("review-threads: the thread's path, its plugin's files and a sibling test push", async (t) => {
  const fix = threadPatch(t, [
    "plugins/p/evals/c/case.yaml",
    "plugins/p/evals/c/samples/deep/new.json",
    "plugins/p/evals/other/samples/new.json",
    "plugins/p/README.md",
    "src/test_round.py",
  ]);
  assert.equal((await threadPush(fix)).outcome, "pushed");
});

for (const path of ["plugins/q/evals/c/samples/new.json", "src/lib/test_round.py", "plugins/p/lib/run.js"]) {
  test(`review-threads: a change outside every kept thread's scope is refused whole: ${path}`, async (t) => {
    const fix = threadPatch(t, ["plugins/p/evals/c/case.yaml", path]);
    assert.deepEqual(await threadPush(fix), { outcome: "escalate", escalationReason: "patch-protected-path" });
  });
}

// #8116: a write-access fix request named a same-plugin code file, which the
// thread file carries as named_paths; without it the file is out of scope.
test("review-threads: a file a kept thread's named_paths holds pushes; the same file unnamed, or a named instruction path, is refused", async (t) => {
  const named = [{ path: "plugins/p/evals/c/case.yaml", named_paths: ["plugins/p/lib/run.js"] }];
  assert.equal((await threadPush(threadPatch(t, ["plugins/p/lib/run.js"]), named)).outcome, "pushed");
  assert.deepEqual(await threadPush(threadPatch(t, ["plugins/p/lib/run.js"]), [{ path: "plugins/p/evals/c/case.yaml" }]), {
    outcome: "escalate",
    escalationReason: "patch-protected-path",
  });
  const instruction = [{ path: "plugins/p/evals/c/case.yaml", named_paths: ["plugins/p/CODEOWNERS"] }];
  assert.deepEqual(await threadPush(threadPatch(t, ["plugins/p/CODEOWNERS"]), instruction), {
    outcome: "escalate",
    escalationReason: "patch-protected-path",
  });
});

test("review-threads: a symbolic link at an in-scope path is refused patch-invalid", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    mkdirSync(join(repo, "plugins/p"), { recursive: true });
    symlinkSync("../../README.md", join(repo, "plugins/p/notes.md"));
  });
  assert.deepEqual(await threadPush(fix), { outcome: "escalate", escalationReason: "patch-invalid" });
});

test("keptThreadsFrom reads a threads.json's paths and named_paths, and refuses any other shape", (t) => {
  const dir = scratch(t);
  const file = join(dir, "threads.json");
  writeFileSync(
    file,
    JSON.stringify({
      version: 1,
      head_sha: "a".repeat(40),
      threads: [
        { id: "PRRT_1", path: "plugins/p/a.md", comments: [{ id: 1, body: "x" }], named_paths: ["plugins/p/b.js"] },
        { id: "PRRT_2", path: "src/c.py", comments: [] },
      ],
    }),
  );
  assert.deepEqual(keptThreadsFrom(file), {
    paths: new Set(["plugins/p/a.md", "src/c.py"]),
    threads: [
      { path: "plugins/p/a.md", named_paths: ["plugins/p/b.js"] },
      { path: "src/c.py", named_paths: undefined },
    ],
  });
  assert.equal(keptThreadsFrom(""), undefined);
  for (const text of [JSON.stringify(["plugins/p/a.md"]), JSON.stringify({ threads: [{ path: 7 }] }), JSON.stringify({ threads: [{ path: "a", named_paths: "b" }] })]) {
    writeFileSync(file, text);
    assert.throws(() => keptThreadsFrom(file), /KEPT_THREADS_FILE/, text);
  }
});

test("checkRow holds merge-result and max-blobs to a merge row, and a merge row to merge-result on a pull request", () => {
  assert.throws(() => checkRow(row("default", { allow: ["merge-result"] })), /allows merge-result or sets max-blobs but does not commit a merge/);
  assert.throws(() => checkRow(row("default", { "max-blobs": 5 })), /allows merge-result or sets max-blobs but does not commit a merge/);
  assert.throws(() => checkRow(row("merge-base", { allow: ["any"] })), /does not allow merge-result alone on a pull request/);
  assert.throws(() => checkRow(row("merge-base", { target: "issue" })), /does not allow merge-result alone on a pull request/);
  assert.throws(() => checkRow(row("merge-base", { "max-blobs": undefined })), /commits a merge with no max-blobs/);
  assert.throws(() => checkRow(row("default", { commit: { ...RULES.default.commit, parents: ["base"] } })), /parents this apply-patch does not support/);
  assert.doesNotThrow(() => checkRow(row("merge-base")));
});

test("a PR whose head is a fork, or unreadable, throws before any write", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  for (const pull of [{ draft: false, head: { repo: { full_name: "fork/r" } } }, { draft: false, head: { repo: null } }]) {
    const api = fakeApi(fix.repo, fix.head, { pull });
    await assert.rejects(pushWith(fix, api), /the PR head is .*, not o\/r/);
    assert.deepEqual(writes(api), []);
  }
});

test("a hold label set while the model worked drops the patch uncommitted", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  const api = fakeApi(fix.repo, fix.head, { labels: [{ name: "needs-human" }] });
  assert.deepEqual(await pushWith(fix, api), { outcome: "held" });
  assert.deepEqual(writes(api), []);
});

// --- the credential scan: any shape refuses the whole patch ---

async function assertCredentialRefused(t, token) {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), `# changed\ntoken=${token}\n`));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(api.calls, []);
  const dir = dirname(fix.patchFile);
  assert.equal(select({ row: row("default"), patchState: "written", patchSha256: fix.sum, patchHeadSha: fix.head, headSha: fix.head, patchDir: dir }).escalationReason, "patch-invalid");
}

test("a patch carrying an Anthropic API key shape is refused whole", async (t) => {
  await assertCredentialRefused(t, ANTHROPIC_KEY);
});

test("a patch carrying an OAuth token shape is refused whole", async (t) => {
  await assertCredentialRefused(t, OAUTH_TOKEN);
});

test("a patch carrying a GitHub token shape (ghp_, ghs_, github_pat_) is refused whole", async (t) => {
  for (const token of GITHUB_TOKENS) {
    await assertCredentialRefused(t, token);
  }
});

test("credentialIn names every GitHub token shape and passes ordinary text", () => {
  for (const token of GITHUB_TOKENS) assert.equal(credentialIn(`x ${token} y`), "GitHub token", token.slice(0, 12));
  for (const text of ["ghs_job", "ghs_lane", "Bearer ghs_job", "a".repeat(40), "3e7fef0587433cfb07332dbeabf0d79fc0baadf3"]) {
    assert.equal(credentialIn(text), "", text);
  }
});

test("a credential inside a binary patch is caught in the patched blob", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "blob.bin"), Buffer.concat([Buffer.from([0, 1, 2, 0]), Buffer.from(GITHUB_TOKENS[0])])));
  assert.match(readFileSync(fix.patchFile, "utf8"), /GIT binary patch/);
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(api.calls, []);
});

// --- a head that moved since the model job ---

test("a moved tip takes the patch with --3way when the moved commits touch no patched path", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n"));
  writeFileSync(join(fix.repo, "README.md"), "# moved\n");
  const moved = commitAll(fix.repo, "moved");
  const api = fakeApi(fix.repo, moved);
  assert.equal((await pushWith(fix, api, { headSha: moved, patchHeadSha: fix.head })).outcome, "pushed");
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.deepEqual(createCommit.parents, [moved]);
  assert.equal(git(fix.repo, ["cat-file", "blob", `${createCommit.tree}:README.md`]), "# moved");
  assert.equal(git(fix.repo, ["cat-file", "blob", `${createCommit.tree}:scripts/x.sh`]), "#!/bin/sh\necho ok");
});

test("a moved tip whose commits touch a patched path skips superseded-sha", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n"));
  writeFileSync(join(fix.repo, "scripts/x.sh"), "#!/bin/sh\nfoo=2\n");
  const moved = commitAll(fix.repo, "moved");
  const api = fakeApi(fix.repo, moved);
  assert.deepEqual(await pushWith(fix, api, { headSha: moved, patchHeadSha: fix.head }), { outcome: "superseded" });
  assert.deepEqual(api.calls, []);
});

test("under the ci-context row a head that moved since the model job skips superseded-sha, escalating nothing", async (t) => {
  const dir = scratch(t);
  writeFileSync(join(dir, "patch.diff"), "diff --git a/x b/x\n");
  const sum = sha256("diff --git a/x b/x\n");
  const [head, other] = ["a".repeat(40), "b".repeat(40)];
  assert.deepEqual(select({ row: row("ci-context"), patchState: "written", patchSha256: sum, patchHeadSha: other, headSha: head, patchDir: dir }), {
    proceed: false,
    skipReason: "superseded-sha",
    escalationReason: "",
  });
  // The push refuses it too, though the moved commits touch no patched path.
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n"));
  writeFileSync(join(fix.repo, "README.md"), "# moved\n");
  const moved = commitAll(fix.repo, "moved");
  const api = fakeApi(fix.repo, moved);
  assert.deepEqual(await pushWith(fix, api, { row: row("ci-context"), headSha: moved, patchHeadSha: fix.head }), { outcome: "superseded" });
  assert.deepEqual(api.calls, []);
});

// The default row keeps the moved-head path on purpose: fix-docs runs once
// per pull request, so a skipped fix-docs patch would never run again. The
// review-threads row skips, as the write runner's promote step refused a
// branch that moved during the run: the replies judged the gated head.
test("the ci-context, review-threads and dependency-review rows skip a moved head; the other PR rows keep the moved-head path", (t) => {
  const dir = scratch(t);
  writeFileSync(join(dir, "patch.diff"), "diff --git a/x b/x\n");
  const sum = sha256("diff --git a/x b/x\n");
  const moved = { patchState: "written", patchSha256: sum, patchHeadSha: "b".repeat(40), headSha: "a".repeat(40), patchDir: dir };
  assert.equal(RULES.default["skip-moved-head"], false);
  assert.deepEqual(select({ row: row("default"), ...moved }), { proceed: true, skipReason: "", escalationReason: "" });
  for (const name of ["ci-context", "review-threads", "dependency-review"]) {
    assert.deepEqual(select({ row: row(name), ...moved }), { proceed: false, skipReason: "superseded-sha", escalationReason: "" }, name);
  }
});

// A Dependabot rebase between the select job and the push supersedes the fix.
test("under the dependency-review row a head that moved since the select job skips superseded-sha before any API call", async (t) => {
  const fix = dependencyPatch(t, bump);
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await dependencyPush(fix, api, { patchHeadSha: "b".repeat(40) }), { outcome: "superseded" });
  assert.deepEqual(api.calls, []);
});

test("under the review-threads row a head that moved since the model job skips superseded-sha before any API call", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  const api = fakeApi(fix.repo, fix.head);
  const result = await pushWith(fix, api, { row: row("review-threads"), patchHeadSha: "b".repeat(40), context: { keptThreads: keptOf([{ path: "README.md" }]) } });
  assert.deepEqual(result, { outcome: "superseded" });
  assert.deepEqual(api.calls, []);
});

// --- fix-ci's refusals, one test each ---

const ciPush = (fix, api, extra = {}) => pushWith(fix, api, { row: row("ci-context"), ...extra });
const patchDirOf = (t, text) => {
  const dir = scratch(t);
  writeFileSync(join(dir, "patch.diff"), text);
  return { dir, sum: sha256(text) };
};
const selectCi = (dir, sum, extra = {}) =>
  select({ row: row("ci-context"), patchState: "written", patchSha256: sum, patchHeadSha: "a".repeat(40), headSha: "a".repeat(40), patchDir: dir, ...extra });
const INVALID = { proceed: false, skipReason: "awaiting-human", escalationReason: "ci-fix-invalid" };

test("a draft set during the run drops the fix uncommitted", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head, { pull: { draft: true, head: { repo: { full_name: "o/r" } } } });
  assert.deepEqual(await ciPush(fix, api), { outcome: "held" });
  assert.deepEqual(writes(api), []);
});

test("a PR branch that moved before the write is not updated", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head, { branch: "e".repeat(40) });
  await assert.rejects(ciPush(fix, api), /moved/);
  assert.equal(api.calls.some((call) => call.updateRef), false);
});

test("a tree GitHub builds differently from the applied one is not committed", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head, { tree: "d".repeat(40) });
  await assert.rejects(ciPush(fix, api), /tree/);
  assert.equal(api.calls.some((call) => call.createCommit), false);
});

test("select: an extra file beside the patch, or a linked patch, is invalid", (t) => {
  const extra = patchDirOf(t, "diff --git a/x b/x\n");
  writeFileSync(join(extra.dir, "other"), "x");
  assert.deepEqual(selectCi(extra.dir, extra.sum), INVALID);
  const target = patchDirOf(t, "diff --git a/x b/x\n");
  const linked = scratch(t);
  symlinkSync(join(target.dir, "patch.diff"), join(linked, "patch.diff"));
  assert.deepEqual(selectCi(linked, target.sum), INVALID);
  assert.deepEqual(selectCi(target.dir, target.sum), { proceed: true, skipReason: "", escalationReason: "" });
});

test("a patch over 1 MiB is invalid in select and in the push", async (t) => {
  const text = `diff --git a/x b/x\n${"x".repeat(1024 * 1024)}`;
  const big = patchDirOf(t, text);
  assert.deepEqual(selectCi(big.dir, big.sum), INVALID);
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await ciPush(fix, api, { patchFile: join(big.dir, "patch.diff"), patchSha256: big.sum }), {
    outcome: "escalate",
    escalationReason: "ci-fix-invalid",
  });
  assert.deepEqual(api.calls, []);
});

test("a patch that does not apply to the gated head is not applied", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n"));
  writeFileSync(join(fix.repo, "scripts/x.sh"), "#!/bin/sh\nchanged=1\n");
  const moved = commitAll(fix.repo, "moved on");
  const api = fakeApi(fix.repo, moved);
  assert.deepEqual(await ciPush(fix, api, { headSha: moved, patchHeadSha: moved }), { outcome: "escalate", escalationReason: "ci-fix-not-applied" });
  assert.deepEqual(api.calls, []);
});

test("a patch file whose SHA-256 changed since the select step is invalid at push time", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await ciPush(fix, api, { patchSha256: "0".repeat(64) }), { outcome: "escalate", escalationReason: "ci-fix-invalid" });
  assert.deepEqual(api.calls, []);
});

test("an empty patch file is invalid in select and in the push", async (t) => {
  const none = patchDirOf(t, "");
  assert.deepEqual(selectCi(none.dir, none.sum), INVALID);
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await ciPush(fix, api, { patchFile: join(none.dir, "patch.diff"), patchSha256: none.sum }), {
    outcome: "escalate",
    escalationReason: "ci-fix-invalid",
  });
  assert.deepEqual(api.calls, []);
});

// A patch that changes README.md and changes it back applies and leaves the
// head's tree. The producer said it wrote a change, so fix-ci calls it
// invalid, as apply-ci-fix.mjs did (origin/main:.github/scripts/pr-unblock/apply-ci-fix.mjs:148-149).
test("a patch that applies but changes nothing escalates ci-fix-invalid", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const forward = readFileSync(fix.patchFile, "utf8");
  writeFileSync(join(fix.repo, "README.md"), "# s\n");
  const back = execFileSync("git", ["diff", "-R", "--full-index"], { cwd: fix.repo, encoding: "utf8" });
  git(fix.repo, ["checkout", "-q", "README.md"]);
  writeFileSync(fix.patchFile, forward + back);
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await ciPush(fix, api, { patchSha256: sha256(forward + back) }), { outcome: "escalate", escalationReason: "ci-fix-invalid" });
  assert.deepEqual(api.calls, []);
});

test("a blob GitHub stores under another SHA is not committed", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head, { blobSha: "f".repeat(40) });
  await assert.rejects(ciPush(fix, api), /stored a blob/);
  assert.equal(api.calls.some((call) => call === "createTree" || call.createCommit), false);
});

test("a branch that does not read back as the new commit after the write fails the push", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head, { afterWrite: "e".repeat(40) });
  await assert.rejects(ciPush(fix, api), /reads e{40} after the write/);
  assert.ok(api.calls.some((call) => call.updateRef));
});

// The script step in pr-run-activity-write.yml fails on a reason outside its
// case list, so every reason the push can write for fix-ci is in it.
test("every reason the push writes for the ci-context row is one the write runner's script step accepts", () => {
  const source = readFileSync(join(REPO_ROOT, ".github/scripts/apply-patch/apply-patch.mjs"), "utf8");
  const pushBody = source.slice(source.indexOf("export async function push("), source.indexOf("\nexport", source.indexOf("export async function push(") + 1));
  const kinds = new Set([...pushBody.matchAll(/escalate\("([a-z-]+)"/g)].map((match) => match[1]));
  for (const name of row("ci-context").refuse) kinds.add(REFUSALS[name].kind);
  assert.ok(kinds.has("empty") && kinds.has("not-applied") && kinds.has("protected-path") && kinds.has("invalid"), [...kinds].join(" "));
  const reasons = new Set([...kinds].map((kind) => pushReason(row("ci-context"), kind)));
  const write = readFileSync(join(REPO_ROOT, ".github/workflows/pr-run-activity-write.yml"), "utf8");
  const line = write.split("\n").find((text) => text.includes(":ci-fix-invalid |"));
  const accepted = new Set([...line.matchAll(/:(ci-fix-[a-z-]+)/g)].map((match) => match[1]));
  assert.deepEqual([...reasons].sort(), [...accepted].sort());
});

// The same for fix-docs, whose patch takes the default row: a patch that
// applies but changes nothing escalates patch-empty, and every reason the
// push writes is in the write runner's case list.
test("every reason the push writes for the default row is one the write runner's script step accepts, an empty diff patch-empty", () => {
  const source = readFileSync(join(REPO_ROOT, ".github/scripts/apply-patch/apply-patch.mjs"), "utf8");
  const pushBody = source.slice(source.indexOf("export async function push("), source.indexOf("\nexport", source.indexOf("export async function push(") + 1));
  const kinds = new Set([...pushBody.matchAll(/escalate\("([a-z-]+)"/g)].map((match) => match[1]));
  for (const name of row("default").refuse) kinds.add(REFUSALS[name].kind);
  assert.ok(kinds.has("empty"), [...kinds].join(" "));
  assert.equal(pushReason(row("default"), "empty"), "patch-empty");
  const write = readFileSync(join(REPO_ROOT, ".github/workflows/pr-run-activity-write.yml"), "utf8");
  const line = write.split("\n").find((text) => text.includes(":ci-fix-invalid |"));
  const accepted = new Set([...line.matchAll(/:(patch-[a-z-]+)/g)].map((match) => match[1]));
  for (const kind of kinds) assert.ok(accepted.has(pushReason(row("default"), kind)), `${kind}: ${pushReason(row("default"), kind)}`);
});

test("an empty patch-state whose report escalated a check names ci-fix-escalated", (t) => {
  const reportDir = scratch(t);
  writeFileSync(join(reportDir, "reply.txt"), "lint-shell: escalated not-reproducible needs a secret\n");
  const head = "a".repeat(40);
  const base = { row: row("ci-context"), patchState: "empty", patchSha256: "", patchHeadSha: head, headSha: head, patchDir: scratch(t) };
  assert.deepEqual(select({ ...base, reportDir, rung: 1 }), { proceed: false, skipReason: "awaiting-human", escalationReason: "ci-fix-escalated" });
  assert.equal(select({ ...base, reportDir: scratch(t) }).escalationReason, "ci-fix-empty");
});

// A fix-ci run that changed nothing and escalated only
// unfixed or not-reproducible checks retries once, one model rung up, instead
// of handing the PR to a person; protected-path, weaken-required and flaky
// stay with a person, and a rung-1 run never retries again.
for (const [why, reply, rung, want] of [
  ["unfixed at rung 0", "test-node: escalated unfixed three fixes failed\n", 0, { proceed: false, skipReason: "rung-up", escalationReason: "" }],
  ["unfixed and not-reproducible at rung 0", "a: escalated unfixed x\nb: escalated not-reproducible y\nc: fixed\n", 0, { proceed: false, skipReason: "rung-up", escalationReason: "" }],
  ["unfixed at rung 1", "test-node: escalated unfixed three fixes failed\n", 1, { proceed: false, skipReason: "awaiting-human", escalationReason: "ci-fix-escalated" }],
  ["protected-path at rung 0", "lint: escalated protected-path edits .github\n", 0, { proceed: false, skipReason: "awaiting-human", escalationReason: "ci-fix-escalated" }],
  ["weaken-required beside unfixed at rung 0", "a: escalated unfixed x\nb: escalated weaken-required y\n", 0, { proceed: false, skipReason: "awaiting-human", escalationReason: "ci-fix-escalated" }],
  ["flaky at rung 0", "a: escalated flaky x\n", 0, { proceed: false, skipReason: "awaiting-human", escalationReason: "ci-fix-escalated" }],
]) {
  test(`an empty fix-ci patch escalating ${why} selects ${want.skipReason}`, (t) => {
    const reportDir = scratch(t);
    writeFileSync(join(reportDir, "reply.txt"), reply);
    const head = "a".repeat(40);
    const base = { row: row("ci-context"), patchState: "empty", patchSha256: "", patchHeadSha: head, headSha: head, patchDir: scratch(t) };
    assert.deepEqual(select({ ...base, reportDir, rung }), want);
  });
}

test("a written fix-ci patch with an unfixed check still pushes and escalates, whatever the rung", (t) => {
  const dir = scratch(t);
  writeFileSync(join(dir, "patch.diff"), "diff --git a/x b/x\n");
  const reportDir = scratch(t);
  writeFileSync(join(reportDir, "reply.txt"), "test-node: escalated unfixed x\n");
  const head = "a".repeat(40);
  const base = { row: row("ci-context"), patchState: "written", patchSha256: sha256("diff --git a/x b/x\n"), patchHeadSha: head, headSha: head, patchDir: dir, reportDir };
  assert.deepEqual(select({ ...base, rung: 0 }), { proceed: true, skipReason: "", escalationReason: "ci-fix-escalated" });
});

test("select reads the rung from MODEL_RUNG and refuses any other value", async (t) => {
  const reportDir = scratch(t);
  writeFileSync(join(reportDir, "reply.txt"), "test-node: escalated unfixed x\n");
  const head = "a".repeat(40);
  const baseDir = scratch(t);
  mkdirSync(join(baseDir, dirname(RULES_PATH)), { recursive: true });
  writeFileSync(join(baseDir, RULES_PATH), JSON.stringify(RULES));
  const outputFor = async (rung) => {
    const out = join(scratch(t), "out");
    writeFileSync(out, "");
    const env = { BASE_DIR: baseDir, PATCH_PREPARE: "ci-context", PATCH_STATE: "empty", PATCH_HEAD_SHA: head, HEAD_SHA: head, PATCH_DIR: scratch(t), REPORT_DIR: reportDir, GITHUB_OUTPUT: out, MODEL_RUNG: rung };
    await main(["select"], env, { log: () => {} });
    return readFileSync(out, "utf8");
  };
  assert.match(await outputFor("1"), /^skip-reason=awaiting-human$/m);
  assert.match(await outputFor("0"), /^skip-reason=rung-up$/m);
  assert.match(await outputFor(""), /^skip-reason=rung-up$/m);
  await assert.rejects(() => outputFor("2"), /MODEL_RUNG/);
});

// --- select and main ---

test("select proceeds on a good artifact, reads the row's report, and names the row's empty reason", (t) => {
  const dir = scratch(t);
  writeFileSync(join(dir, "patch.diff"), "diff --git a/x b/x\n");
  const sum = sha256("diff --git a/x b/x\n");
  const head = "a".repeat(40);
  const base = { patchSha256: sum, patchHeadSha: head, headSha: head, patchDir: dir };
  assert.deepEqual(select({ row: row("default"), patchState: "written", ...base }), { proceed: true, skipReason: "", escalationReason: "" });
  const reportDir = scratch(t);
  writeFileSync(join(reportDir, "reply.txt"), "lint: fixed\ntest-node: escalated unfixed three fixes failed\n");
  assert.equal(select({ row: row("ci-context"), patchState: "written", ...base, reportDir }).escalationReason, "ci-fix-escalated");
  assert.equal(select({ row: row("default"), patchState: "empty", ...base }).escalationReason, "patch-empty");
  assert.equal(select({ row: row("default"), patchState: "written", ...base, patchSha256: "0".repeat(64) }).escalationReason, "patch-invalid");
});

test("patch-rules.json is read from the trusted base checkout, and a head copy is ignored", async (t) => {
  const base = scratch(t);
  const head = scratch(t);
  for (const dir of [base, head]) {
    mkdirSync(join(dir, dirname(RULES_PATH)), { recursive: true });
    cpSync(join(REPO_ROOT, RULES_PATH), join(dir, RULES_PATH));
  }
  const tampered = JSON.parse(readFileSync(join(head, RULES_PATH), "utf8"));
  tampered.default.escalations = ["head-invalid"];
  writeFileSync(join(head, RULES_PATH), JSON.stringify(tampered));
  const output = join(scratch(t), "output");
  const env = { BASE_DIR: base, PATCH_PREPARE: "", GITHUB_OUTPUT: output, HEAD_SHA: "a".repeat(40), PATCH_STATE: "" };
  await main(["select"], env, { cwd: head, log: () => {} });
  assert.match(readFileSync(output, "utf8"), /^escalation-reason=patch-invalid$/m);
  await assert.rejects(main(["select"], { ...env, BASE_DIR: "" }, { cwd: head, log: () => {} }), /BASE_DIR/);
});

// --- the issue target: a new lane branch with one commit ---

const LANE = "work-resolve-issue";
const ISSUE_BRANCH = `${LANE}/issue-7-123-1`;
const READY = [{ name: "agent-ready" }];
const issueRow = () => rowFor(RULES, { target: "issue" });

const pushIssue = (fix, api, extra = {}) =>
  push({
    api,
    cwd: fix.repo,
    gitBin: "git",
    row: issueRow(),
    issue: 7,
    headSha: fix.head,
    patchHeadSha: fix.head,
    headRef: ISSUE_BRANCH,
    lane: LANE,
    activity: "resolve-issue",
    patchFile: fix.patchFile,
    patchSha256: fix.sum,
    holdLabels: ["do-not-merge", "needs-human", "needs-owner-decision"],
    requiredLabels: ["agent-ready"],
    ...extra,
  });

const callNames = (api) => api.calls.map((call) => (typeof call === "string" ? call : Object.keys(call)[0]));

test("issue target: the lookup takes the issue row whatever the prepare mode", () => {
  const picked = rowFor(RULES, { prepare: "ci-context", target: "issue" });
  assert.equal(picked.name, "issue");
  assert.equal(picked.target, "issue");
  assert.equal(picked["max-files"], 300);
});

test("issue target: makes <lane>/issue-<n>-<run id>-<attempt> at the start commit with one commit", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# resolved\n"));
  const api = fakeApi(fix.repo, fix.head, { labels: READY });
  assert.deepEqual(await pushIssue(fix, api), { outcome: "pushed", commit: "c".repeat(40), branch: ISSUE_BRANCH });
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.equal(createCommit.message, "Resolve issue #7\n\nLane-Activity: work-resolve-issue/resolve-issue\n");
  assert.deepEqual(createCommit.parents, [fix.head]);
  assert.equal(git(fix.repo, ["cat-file", "blob", `${createCommit.tree}:README.md`]), "# resolved");
  assert.deepEqual(api.calls.filter((call) => call.createRef), [{ createRef: { ref: `refs/heads/${ISSUE_BRANCH}`, sha: "c".repeat(40) } }]);
  assert.ok(!callNames(api).includes("updateRef"), "an existing branch is never moved");
  assert.ok(!callNames(api).includes("getPull"), "no pull request is read");
});

test("issue target: a branch not of the lane's issue shape throws before any call", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# resolved\n"));
  for (const headRef of [`${LANE}/issue-8-123-1`, `${LANE}/issue-7-123`, `${LANE}/issue-7-0-1`, `pr-unblock/issue-7-123-1`, "main", `${LANE}/issue-7-123-1/x`]) {
    const api = fakeApi(fix.repo, fix.head, { labels: READY });
    await assert.rejects(pushIssue(fix, api, { headRef }), /is not a work-resolve-issue\/issue-7-<run id>-<attempt> branch/, headRef);
    assert.deepEqual(api.calls, [], headRef);
  }
});

test("issue target: a resumed run's patch lands on a new branch made at the resume tip", async (t) => {
  const fix = repoWithPatch(t, () => {});
  writeFileSync(join(fix.repo, "notes.md"), "earlier run's work\n");
  const resumeTip = commitAll(fix.repo, "earlier lane commit");
  writeFileSync(join(fix.repo, "README.md"), "# finished\n");
  git(fix.repo, ["add", "-A"]);
  const text = execFileSync("git", ["diff", "--cached", "--binary", "--full-index", "--no-renames", resumeTip], { cwd: fix.repo, encoding: "utf8" });
  git(fix.repo, ["reset", "-q", "--hard", resumeTip]);
  writeFileSync(fix.patchFile, text);
  const api = fakeApi(fix.repo, resumeTip, { labels: READY });
  const resumed = { ...fix, head: resumeTip, sum: sha256(text) };
  assert.equal((await pushIssue(resumed, api, { headRef: `${LANE}/issue-7-124-1`, refusalBase: fix.head })).outcome, "pushed", "a clean resume tip passes");
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.deepEqual(createCommit.parents, [resumeTip]);
  assert.equal(git(fix.repo, ["cat-file", "blob", `${createCommit.tree}:notes.md`]), "earlier run's work");
  assert.equal(git(fix.repo, ["cat-file", "blob", `${createCommit.tree}:README.md`]), "# finished");
});

test("issue target: a hold label added while the model worked drops the patch uncommitted", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# resolved\n"));
  for (const hold of ["needs-human", "needs-owner-decision", "do-not-merge"]) {
    const api = fakeApi(fix.repo, fix.head, { labels: [...READY, { name: hold }] });
    assert.deepEqual(await pushIssue(fix, api), { outcome: "held" }, hold);
    assert.deepEqual(writes(api), [], hold);
  }
});

test("issue target: agent-ready removed while the model worked drops the patch uncommitted", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# resolved\n"));
  const api = fakeApi(fix.repo, fix.head, { labels: [{ name: "bug" }] });
  assert.deepEqual(await pushIssue(fix, api), { outcome: "held" });
  assert.deepEqual(writes(api), []);
});

test("issue target: a patch made on another commit is refused, never applied with --3way", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n"));
  writeFileSync(join(fix.repo, "README.md"), "# moved\n");
  const moved = commitAll(fix.repo, "moved");
  const api = fakeApi(fix.repo, moved, { labels: READY });
  assert.deepEqual(await pushIssue(fix, api, { headSha: moved }), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(api.calls, []);
});

test("issue target: the issue row refuses the universal set, each refusal before any API call", async (t) => {
  const cases = [
    ["a .github/ workflow", (repo) => (mkdirSync(join(repo, ".github/workflows"), { recursive: true }), writeFileSync(join(repo, ".github/workflows/x.yml"), "on: push\n")), "patch-protected-path"],
    ["CODEOWNERS", (repo) => writeFileSync(join(repo, "CODEOWNERS"), "* @o\n"), "patch-protected-path"],
    [".gitmodules", (repo) => writeFileSync(join(repo, ".gitmodules"), "\n"), "patch-protected-path"],
    ["a settings.json", (repo) => writeFileSync(join(repo, "settings.json"), "{}\n"), "patch-protected-path"],
    ["a symbolic link", (repo) => symlinkSync("README.md", join(repo, "link")), "patch-invalid"],
  ];
  assert.deepEqual(issueRow().refuse, ["github-workflows", "codeowners", "gitmodules", "settings", "symlink", "gitlink", "rename-into-refused"]);
  for (const [what, edit, reason] of cases) {
    const fix = repoWithPatch(t, edit);
    const api = fakeApi(fix.repo, fix.head, { labels: READY });
    assert.deepEqual(await pushIssue(fix, api), { outcome: "escalate", escalationReason: reason }, what);
    assert.deepEqual(api.calls, [], what);
  }
});

const modeIn = (repo, tree, path) => git(repo, ["ls-tree", tree, "--", path]).split(" ")[0];

test("issue target: a new or changed file that ends in .sh or starts with #! lands 100755; any other file keeps 100644", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    writeFileSync(join(repo, "scripts/new.sh"), "set -eu\necho new\n");
    writeFileSync(join(repo, "scripts/tool"), "#!/usr/bin/env node\nconsole.log(1);\n");
    writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\nfoo=2\n");
    writeFileSync(join(repo, "notes.txt"), "plain\n");
  });
  const api = fakeApi(fix.repo, fix.head, { labels: READY });
  assert.equal((await pushIssue(fix, api)).outcome, "pushed");
  const { createCommit } = api.calls.find((call) => call.createCommit);
  for (const path of ["scripts/new.sh", "scripts/tool", "scripts/x.sh"]) {
    assert.equal(modeIn(fix.repo, createCommit.tree, path), "100755", path);
  }
  assert.equal(modeIn(fix.repo, createCommit.tree, "notes.txt"), "100644");
  assert.equal(modeIn(fix.repo, createCommit.tree, "README.md"), "100644", "an unchanged file keeps its mode");
});

test("issue target: a resumed run keeps the executable bits its earlier lane commit landed, on a script or not", async (t) => {
  for (const [path, body] of [
    ["scripts/new.sh", "echo earlier\n"],
    ["notes.md", "notes\n"],
  ]) {
    const fix = repoWithPatch(t, () => {});
    writeFileSync(join(fix.repo, path), body);
    chmodSync(join(fix.repo, path), 0o755);
    const resumeTip = commitAll(fix.repo, "earlier lane commit");
    writeFileSync(join(fix.repo, "README.md"), "# finished\n");
    git(fix.repo, ["add", "-A"]);
    const text = execFileSync("git", ["diff", "--cached", "--binary", "--full-index", "--no-renames", resumeTip], { cwd: fix.repo, encoding: "utf8" });
    git(fix.repo, ["reset", "-q", "--hard", resumeTip]);
    writeFileSync(fix.patchFile, text);
    const api = fakeApi(fix.repo, resumeTip, { labels: READY });
    const resumed = { ...fix, head: resumeTip, sum: sha256(text) };
    assert.equal((await pushIssue(resumed, api, { headRef: `${LANE}/issue-7-124-1`, refusalBase: fix.head })).outcome, "pushed", path);
  }
});

test("issue target: a resumed run whose patch adds a gitlink to a commit not in the repository escalates patch-invalid", async (t) => {
  const fix = repoWithPatch(t, () => {});
  writeFileSync(join(fix.repo, "notes.md"), "earlier run's work\n");
  const resumeTip = commitAll(fix.repo, "earlier lane commit");
  git(fix.repo, ["update-index", "--add", "--cacheinfo", `160000,${"ab".repeat(20)},vendor/sub`]);
  const text = execFileSync("git", ["diff", "--cached", "--binary", "--full-index", "--no-renames", resumeTip], { cwd: fix.repo, encoding: "utf8" });
  git(fix.repo, ["reset", "-q", "--hard", resumeTip]);
  writeFileSync(fix.patchFile, text);
  const api = fakeApi(fix.repo, resumeTip, { labels: READY });
  const resumed = { ...fix, head: resumeTip, sum: sha256(text) };
  assert.deepEqual(await pushIssue(resumed, api, { headRef: `${LANE}/issue-7-124-1`, refusalBase: fix.head }), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(api.calls, []);
});

test("issue target: a script in a plugin's hooks lands 100755", async (t) => {
  const fix = repoWithPatch(t, (repo) => (mkdirSync(join(repo, "plugins/p/hooks"), { recursive: true }), writeFileSync(join(repo, "plugins/p/hooks/x.sh"), "#!/bin/sh\n")));
  const api = fakeApi(fix.repo, fix.head, { labels: READY });
  assert.equal((await pushIssue(fix, api)).outcome, "pushed");
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.equal(modeIn(fix.repo, createCommit.tree, "plugins/p/hooks/x.sh"), "100755");
});

test("issue target: an executable bit the patch itself sets lands, on a script or not", async (t) => {
  for (const [what, path, edit] of [
    ["a non-script", "notes.md", (repo) => chmodSync(join(repo, "notes.md"), 0o755)],
    ["a new .sh", "scripts/new.sh", (repo) => (writeFileSync(join(repo, "scripts/new.sh"), "#!/bin/sh\n"), chmodSync(join(repo, "scripts/new.sh"), 0o755))],
  ]) {
    const fix = repoWithPatch(t, edit);
    const api = fakeApi(fix.repo, fix.head, { labels: READY });
    assert.equal((await pushIssue(fix, api)).outcome, "pushed", what);
    const { createCommit } = api.calls.find((call) => call.createCommit);
    assert.equal(modeIn(fix.repo, createCommit.tree, path), "100755", what);
  }
});

test("a row may set script exec bits whatever it refuses beyond the universal set", () => {
  assert.doesNotThrow(() => checkRow({ ...issueRow(), "script-exec-bit": true }));
  assert.doesNotThrow(() => checkRow({ ...row("default"), "script-exec-bit": true }));
});

test("issue target: API calls are one blob per changed file, then tree, commit, branch create and the label and branch reads; over max-files none", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    writeFileSync(join(repo, "README.md"), "# changed\n");
    writeFileSync(join(repo, "notes.md"), "changed\n");
    writeFileSync(join(repo, "NEW.md"), "new\n");
  });
  const api = fakeApi(fix.repo, fix.head, { labels: READY });
  assert.equal((await pushIssue(fix, api)).outcome, "pushed");
  const names = callNames(api);
  assert.equal(names.filter((name) => name === "createBlob").length, 3);
  assert.deepEqual(names.filter((name) => name !== "createBlob"), ["listLabels", "createTree", "createCommit", "createRef", "readBranch"]);
  assert.equal(names.length, 3 + 5);
  const capped = fakeApi(fix.repo, fix.head, { labels: READY });
  assert.deepEqual(await pushIssue(fix, capped, { row: { ...issueRow(), "max-files": 2 } }), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(capped.calls, []);
});

test("issue target: main reads ISSUE_NUMBER and REQUIRED_LABELS and writes the commit and branch", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# resolved\n"));
  const dir = scratch(t);
  const env = {
    BASE_DIR: REPO_ROOT,
    PATCH_TARGET: "issue",
    GH_TOKEN: "unused",
    GITHUB_REPOSITORY: "o/r",
    ISSUE_NUMBER: "7",
    REQUIRED_LABELS: '["agent-ready"]',
    HEAD_SHA: fix.head,
    PATCH_HEAD_SHA: fix.head,
    PATCH_BASE_SHA: fix.head,
    HEAD_REF: ISSUE_BRANCH,
    LANE,
    PATCH_ACTIVITY: "resolve-issue",
    PATCH_FILE: fix.patchFile,
    PATCH_SHA256: fix.sum,
    HOLD_LABELS: '["needs-human"]',
    SKIP_REASON_FILE: join(dir, "skip"),
    ESCALATION_REASON_FILE: join(dir, "escalation"),
    GITHUB_OUTPUT: join(dir, "output"),
  };
  const api = fakeApi(fix.repo, fix.head, { labels: READY });
  assert.equal(await main([], env, { api, cwd: fix.repo, gitBin: "git", log: () => {} }), 0);
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `commit=${"c".repeat(40)}\nbranch=${ISSUE_BRANCH}\n`);
  const { REQUIRED_LABELS, ...noRequired } = env;
  assert.equal(REQUIRED_LABELS, '["agent-ready"]');
  await assert.rejects(main([], noRequired, { api, cwd: fix.repo, gitBin: "git", log: () => {} }), /REQUIRED_LABELS not set/);
  await assert.rejects(main([], { ...env, ISSUE_NUMBER: "7a" }, { api, cwd: fix.repo, gitBin: "git", log: () => {} }), /ISSUE_NUMBER is not a positive integer/);
  const { PATCH_BASE_SHA, ...noBase } = env;
  assert.equal(PATCH_BASE_SHA, fix.head);
  const idle = fakeApi(fix.repo, fix.head, { labels: READY });
  await assert.rejects(main([], noBase, { api: idle, cwd: fix.repo, gitBin: "git", log: () => {} }), /PATCH_BASE_SHA not set/);
  await assert.rejects(main([], { ...env, PATCH_BASE_SHA: "" }, { api: idle, cwd: fix.repo, gitBin: "git", log: () => {} }), /PATCH_BASE_SHA not set/);
  assert.deepEqual(idle.calls, [], "a missing base fails closed before any API call");
});

// A resume tip of the patch's own, made after the default-branch commit.
function resumeWith(t, earlier) {
  const fix = repoWithPatch(t, () => {});
  earlier(fix.repo);
  const resumeTip = commitAll(fix.repo, "earlier lane commit");
  writeFileSync(join(fix.repo, "README.md"), "# finished\n");
  git(fix.repo, ["add", "-A"]);
  const text = execFileSync("git", ["diff", "--cached", "--binary", "--full-index", "--no-renames", resumeTip], { cwd: fix.repo, encoding: "utf8" });
  git(fix.repo, ["reset", "-q", "--hard", resumeTip]);
  writeFileSync(fix.patchFile, text);
  return { fix: { ...fix, head: resumeTip, sum: sha256(text) }, base: fix.head };
}

test("issue target: a resume tip carrying a refused path is refused, though the patch itself is clean", async (t) => {
  for (const [what, earlier, reason] of [
    ["a .claude/settings.json", (repo) => (mkdirSync(join(repo, ".claude")), writeFileSync(join(repo, ".claude/settings.json"), "{}\n")), "patch-protected-path"],
    ["a .github/ workflow", (repo) => (mkdirSync(join(repo, ".github/workflows"), { recursive: true }), writeFileSync(join(repo, ".github/workflows/x.yml"), "on: push\n")), "patch-protected-path"],
    ["CODEOWNERS", (repo) => writeFileSync(join(repo, "CODEOWNERS"), "* @o\n"), "patch-protected-path"],
  ]) {
    const { fix, base } = resumeWith(t, earlier);
    const api = fakeApi(fix.repo, fix.head, { labels: READY });
    assert.deepEqual(await pushIssue(fix, api, { headRef: `${LANE}/issue-7-124-1`, refusalBase: base }), { outcome: "escalate", escalationReason: reason }, what);
    assert.deepEqual(api.calls, [], what);
    const unchecked = fakeApi(fix.repo, fix.head, { labels: READY });
    assert.equal((await pushIssue(fix, unchecked, { headRef: `${LANE}/issue-7-124-1` })).outcome, "pushed", `${what}: only the base makes the difference`);
  }
});

test("issue target: a default-branch commit not in the checkout refuses the patch", async (t) => {
  const { fix } = resumeWith(t, (repo) => writeFileSync(join(repo, "notes.md"), "earlier\n"));
  const api = fakeApi(fix.repo, fix.head, { labels: READY });
  assert.deepEqual(await pushIssue(fix, api, { refusalBase: "e".repeat(40) }), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(api.calls, []);
});

// Zeros compress, so a patch well under 1 MiB carries blobs of many MiB.
test("a patched blob over 5 MiB is refused before any API call", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "big.bin"), Buffer.alloc(5 * 1024 * 1024 + 1)));
  assert.ok(readFileSync(fix.patchFile).length < 1024 * 1024);
  for (const push of [pushWith, pushIssue]) {
    const api = fakeApi(fix.repo, fix.head, { labels: READY });
    assert.deepEqual(await push(fix, api), { outcome: "escalate", escalationReason: "patch-invalid" });
    assert.deepEqual(api.calls, []);
  }
});

test("patched blobs over 20 MiB in total are refused, each one under the per-blob cap", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    for (let i = 0; i < 5; i += 1) {
      writeFileSync(join(repo, `part-${i}.bin`), Buffer.alloc(4 * 1024 * 1024 + i + 1));
    }
  });
  const api = fakeApi(fix.repo, fix.head, { labels: READY });
  assert.deepEqual(await pushIssue(fix, api), { outcome: "escalate", escalationReason: "patch-invalid" });
  assert.deepEqual(api.calls, []);
  const under = repoWithPatch(t, (repo) => writeFileSync(join(repo, "part.bin"), Buffer.alloc(5 * 1024 * 1024)));
  assert.equal((await pushIssue(under, fakeApi(under.repo, under.head, { labels: READY }))).outcome, "pushed", "exactly 5 MiB passes");
});

// --- the merge-base row: resolve-conflicts's patch on the conflict tree ---

const PREPARE = join(REPO_ROOT, ".github/scripts/merge-base/prepare.sh");
const COLLECT = join(REPO_ROOT, ".github/scripts/read-patch/collect-patch.sh");
const TREE_ENTRIES = join(REPO_ROOT, ".github/scripts/merge-base/tree-entries.sh");
const TREE_ENTRIES_SHA256 = sha256(readFileSync(TREE_ENTRIES));
const BOT = {
  GIT_AUTHOR_NAME: "melodic-automation-lanes[bot]",
  GIT_AUTHOR_EMAIL: "1+bot@users.noreply.github.com",
  GIT_COMMITTER_NAME: "melodic-automation-lanes[bot]",
  GIT_COMMITTER_EMAIL: "1+bot@users.noreply.github.com",
};

const write = (repo, files) => {
  for (const [path, text] of Object.entries(files)) {
    if (text === null) {
      rmSync(join(repo, path));
    } else {
      mkdirSync(join(repo, dirname(path)), { recursive: true });
      writeFileSync(join(repo, path), text);
    }
  }
};

// A base commit, a PR side and a main side, the base merged into the PR head
// by the real prepare.sh, and `resolve`'s edits collected from the conflict
// tree by the real collect-patch.sh, as the read runner does.
function mergeFixture(t, { base = {}, pr = {}, main: mainSide = {}, resolve = () => {} }) {
  const repo = scratch(t);
  git(repo, ["init", "-q", "-b", "main"]);
  git(repo, ["config", "user.email", "t@example.com"]);
  git(repo, ["config", "user.name", "t"]);
  git(repo, ["config", "core.autocrlf", "false"]);
  write(repo, { "keep.txt": "keep\n", ...base });
  commitAll(repo, "base");
  git(repo, ["checkout", "-q", "-b", "pr"]);
  write(repo, pr);
  const head = commitAll(repo, "pr side");
  git(repo, ["checkout", "-q", "main"]);
  write(repo, mainSide);
  const baseSha = commitAll(repo, "main side");
  git(repo, ["checkout", "-q", "--detach", head]);
  const out = scratch(t);
  const bump = join(out, "bump.sh");
  writeFileSync(bump, "#!/usr/bin/env bash\nexit 0\n");
  const printed = execFileSync("bash", [PREPARE, head, baseSha, bump, join(out, "merge")], {
    cwd: repo,
    env: { ...process.env, ...BOT },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  const value = (key) => new RegExp(`^${key}=(.*)$`, "m").exec(printed)?.[1] ?? "";
  const state = value("merge-state");
  const tree = value("conflict-tree");
  resolve(repo);
  const patchFile = join(scratch(t), "patch.diff");
  const collected = execFileSync("bash", [COLLECT, head, patchFile, tree], { cwd: repo, encoding: "utf8" });
  const patchState = /^state=(.*)$/m.exec(collected)[1];
  return { repo, head, base: baseSha, tree, state, patchState, patchFile: patchState === "written" ? patchFile : "", sum: /^sha256=(.*)$/m.exec(collected)[1] };
}

const mergeEnv = (fix, extra = {}) => ({
  MERGE_BASE_SHA: fix.base,
  CONFLICT_TREE: fix.tree,
  MERGE_STATE: fix.state,
  TREE_ENTRIES_SCRIPT: TREE_ENTRIES,
  TREE_ENTRIES_SHA256,
  ...extra,
});
const mergePush = (fix, api, { env = {}, ...extra } = {}) =>
  pushWith(fix, api, {
    row: row("merge-base"),
    context: { merge: mergeFrom(mergeEnv(fix, env), { cwd: fix.repo, gitBin: "git" }) },
    baseRef: "main",
    lane: "pr-unblock",
    activity: "resolve-conflicts",
    ...extra,
  });
const CONFLICT = { base: { "a.txt": "one\n" }, pr: { "a.txt": "pr\n" }, main: { "a.txt": "main\n" } };
const NO_PATCH = { patchFile: "", patchSha256: "" };

test("hasConflictMarkers reads markers of any length from seven, in order, and nothing else", () => {
  assert.equal(hasConflictMarkers("<<<<<<< HEAD\na\n=======\nb\n>>>>>>> main\n"), true);
  assert.equal(hasConflictMarkers("<<<<<<<<<< HEAD\r\na\r\n==========\r\nb\r\n>>>>>>>>>>\r\n"), true);
  assert.equal(hasConflictMarkers("a\n=======\nb\n"), false);
  assert.equal(hasConflictMarkers(">>>>>>> x\n=======\n<<<<<<< y\n"), false);
  assert.equal(hasConflictMarkers("<<<<<< short\n======\n>>>>>> short\n"), false);
});

test("a clean merge commits with no patch, the head and the pinned base as parents, uploading no blob either side holds", async (t) => {
  const fix = mergeFixture(t, { pr: { "p.txt": "pr\n" }, main: { "m.txt": "main\n", "docs/m2.md": "m2\n" } });
  assert.deepEqual([fix.state, fix.patchState], ["clean", "empty"]);
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await mergePush(fix, api, NO_PATCH), { outcome: "pushed", commit: "c".repeat(40), branch: "feat/x" });
  assert.deepEqual(callNames(api), ["getPull", "listLabels", "readBranch", "createTree", "createCommit", "updateRef", "readBranch"]);
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.deepEqual(createCommit, {
    message: "Merge main into feat/x\n\nLane-Activity: pr-unblock/resolve-conflicts\n",
    tree: fix.tree,
    parents: [fix.head, fix.base],
  });
  assert.equal(git(fix.repo, ["rev-parse", `${fix.tree}:m.txt`]), git(fix.repo, ["rev-parse", `${fix.base}:m.txt`]));
  assert.equal(git(fix.repo, ["rev-parse", `${fix.tree}:p.txt`]), git(fix.repo, ["rev-parse", `${fix.head}:p.txt`]));
  // A patch beside a clean merge is refused.
  const extra = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "x\n"));
  assert.deepEqual(await mergePush(fix, fakeApi(fix.repo, fix.head), { patchFile: extra.patchFile, patchSha256: extra.sum }), {
    outcome: "escalate",
    escalationReason: "conflict-patch-invalid",
  });
});

test("a resolved conflict pushes the resolution on the conflict tree as a merge commit", async (t) => {
  const fix = mergeFixture(t, { ...CONFLICT, resolve: (repo) => writeFileSync(join(repo, "a.txt"), "pr and main\n") });
  assert.deepEqual([fix.state, fix.patchState], ["conflicted", "written"]);
  // The patch holds the resolution alone.
  const text = readFileSync(fix.patchFile, "utf8");
  assert.deepEqual([...text.matchAll(/^diff --git a\/(\S+) /gm)].map((m) => m[1]), ["a.txt"]);
  const api = fakeApi(fix.repo, fix.head);
  assert.equal((await mergePush(fix, api)).outcome, "pushed");
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.deepEqual(createCommit.parents, [fix.head, fix.base]);
  assert.equal(git(fix.repo, ["cat-file", "-p", `${createCommit.tree}:a.txt`]), "pr and main");
  assert.equal(callNames(api).filter((name) => name === "createBlob").length, 1);
});

test("a conflicted path left with markers escalates unresolved-conflict before any API call", async (t) => {
  const fix = mergeFixture(t, {
    base: { "a.txt": "one\n", "b.txt": "one\n" },
    pr: { "a.txt": "pr\n", "b.txt": "pr\n" },
    main: { "a.txt": "main\n", "b.txt": "main\n" },
    resolve: (repo) => writeFileSync(join(repo, "a.txt"), "resolved\n"),
  });
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await mergePush(fix, api), { outcome: "escalate", escalationReason: "unresolved-conflict" });
  assert.deepEqual(api.calls, []);
  // A resolution that writes new marker lines is no resolution either.
  const marked = mergeFixture(t, { ...CONFLICT, resolve: (repo) => writeFileSync(join(repo, "a.txt"), "<<<<<<< x\npr\n=======\nmain\n>>>>>>> y\n") });
  assert.deepEqual(await mergePush(marked, fakeApi(marked.repo, marked.head)), { outcome: "escalate", escalationReason: "unresolved-conflict" });
});

test("a model may delete a conflicted path", async (t) => {
  const fix = mergeFixture(t, { ...CONFLICT, resolve: (repo) => rmSync(join(repo, "a.txt")) });
  const api = fakeApi(fix.repo, fix.head);
  assert.equal((await mergePush(fix, api)).outcome, "pushed");
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.throws(() => git(fix.repo, ["rev-parse", "--verify", "-q", `${createCommit.tree}:a.txt`]));
});

test("a patch that edits a path outside the conflicted set escalates unexpected-path-staged before any API call", async (t) => {
  const fix = mergeFixture(t, {
    ...CONFLICT,
    resolve: (repo) => write(repo, { "a.txt": "resolved\n", "keep.txt": "a semantic-sweep fix\n" }),
  });
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await mergePush(fix, api), { outcome: "escalate", escalationReason: "unexpected-path-staged" });
  assert.deepEqual(api.calls, []);
});

test("a model-authored workflow or code-owners edit is refused conflict-patch-protected-path before any API call", async (t) => {
  for (const path of [".github/workflows/ci.yml", "CODEOWNERS"]) {
    const fix = mergeFixture(t, { ...CONFLICT, resolve: (repo) => write(repo, { "a.txt": "resolved\n", [path]: "x\n" }) });
    const api = fakeApi(fix.repo, fix.head);
    assert.deepEqual(await mergePush(fix, api), { outcome: "escalate", escalationReason: "conflict-patch-protected-path" }, path);
    assert.deepEqual(api.calls, [], path);
  }
});

test("a base-side workflow change is admitted only when the merged workflows are exactly the base's", async (t) => {
  const own = mergeFixture(t, { base: { ".github/workflows/a.yml": "on: push\n" }, pr: { "p.txt": "pr\n" }, main: { ".github/workflows/a.yml": "on: pull_request\n" } });
  assert.equal((await mergePush(own, fakeApi(own.repo, own.head), NO_PATCH)).outcome, "pushed");
  // The PR's own diff touches a workflow too: the merged set is not the base's alone.
  const both = mergeFixture(t, {
    base: { ".github/workflows/a.yml": "on: push\n", ".github/workflows/b.yml": "on: push\n" },
    pr: { ".github/workflows/b.yml": "on: workflow_dispatch\n" },
    main: { ".github/workflows/a.yml": "on: pull_request\n" },
  });
  const api = fakeApi(both.repo, both.head);
  assert.deepEqual(await mergePush(both, api, NO_PATCH), { outcome: "escalate", escalationReason: "workflow-staged" });
  assert.deepEqual(api.calls, []);
  // A workflow the head adds would be pushed beside the base's change.
  const added = mergeFixture(t, {
    base: { ".github/workflows/a.yml": "on: push\n" },
    pr: { ".github/workflows/new.yml": "on: push\n" },
    main: { ".github/workflows/a.yml": "on: pull_request\n" },
  });
  assert.deepEqual(await mergePush(added, fakeApi(added.repo, added.head), NO_PATCH), { outcome: "escalate", escalationReason: "workflow-staged" });
});

test("a patch made on another conflict tree escalates conflict-patch-not-applied", async (t) => {
  const fix = mergeFixture(t, { ...CONFLICT, resolve: (repo) => writeFileSync(join(repo, "a.txt"), "resolved\n") });
  const api = fakeApi(fix.repo, fix.head);
  const headTree = git(fix.repo, ["rev-parse", `${fix.head}^{tree}`]);
  assert.deepEqual(await mergePush(fix, api, { env: { CONFLICT_TREE: headTree } }), { outcome: "escalate", escalationReason: "conflict-patch-not-applied" });
  assert.deepEqual(api.calls, []);
});

test("a merge row with no pinned base, conflict tree, state or base tree-entries.sh throws before any write", async (t) => {
  const fix = mergeFixture(t, { ...CONFLICT, resolve: (repo) => writeFileSync(join(repo, "a.txt"), "resolved\n") });
  for (const key of ["MERGE_BASE_SHA", "CONFLICT_TREE", "MERGE_STATE", "TREE_ENTRIES_SCRIPT", "TREE_ENTRIES_SHA256"]) {
    assert.throws(() => mergeFrom(mergeEnv(fix, { [key]: "" }), { cwd: fix.repo, gitBin: "git" }), new RegExp(key), key);
  }
  for (const env of [{ MERGE_BASE_SHA: "main" }, { CONFLICT_TREE: "x" }, { MERGE_STATE: "escalate" }, { MERGE_BASE_SHA: "0".repeat(40) }]) {
    const api = fakeApi(fix.repo, fix.head);
    await assert.rejects(mergePush(fix, api, { env }), /merge row needs|not in the checkout/, JSON.stringify(env));
    assert.deepEqual(api.calls, [], JSON.stringify(env));
  }
  // A tree-entries.sh copy that is not the base's never runs.
  const api = fakeApi(fix.repo, fix.head);
  await assert.rejects(mergePush(fix, api, { env: { TREE_ENTRIES_SHA256: "0".repeat(64) } }), /tree-entries\.sh does not match/);
  assert.deepEqual(api.calls, []);
  await assert.rejects(pushWith(fix, fakeApi(fix.repo, fix.head), { row: row("merge-base"), baseRef: "main", context: {} }), /merge row needs/);
});

test("under the merge-base row a head that moved since the select job skips superseded-sha before any API call", async (t) => {
  const fix = mergeFixture(t, { ...CONFLICT, resolve: (repo) => writeFileSync(join(repo, "a.txt"), "resolved\n") });
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await mergePush(fix, api, { patchHeadSha: "b".repeat(40) }), { outcome: "superseded" });
  assert.deepEqual(api.calls, []);
});

test("select under the merge-base row: a clean merge proceeds with no patch, an empty patch is unresolved-conflict, and a moved head skips", (t) => {
  const dir = scratch(t);
  writeFileSync(join(dir, "patch.diff"), "diff --git a/x b/x\n");
  const sum = sha256("diff --git a/x b/x\n");
  const head = "a".repeat(40);
  const at = (mergeState, patchState, extra = {}) =>
    select({ row: row("merge-base"), mergeState, patchState, patchSha256: sum, patchHeadSha: head, headSha: head, patchDir: dir, ...extra });
  assert.deepEqual(at("clean", ""), { proceed: true, skipReason: "", escalationReason: "" });
  assert.deepEqual(at("clean", "written"), { proceed: false, skipReason: "awaiting-human", escalationReason: "conflict-patch-invalid" });
  assert.deepEqual(at("conflicted", "written"), { proceed: true, skipReason: "", escalationReason: "" });
  assert.deepEqual(at("conflicted", "empty"), { proceed: false, skipReason: "awaiting-human", escalationReason: "unresolved-conflict" });
  assert.deepEqual(at("conflicted", ""), { proceed: false, skipReason: "awaiting-human", escalationReason: "conflict-patch-invalid" });
  for (const state of ["", "escalate", "Clean"]) {
    assert.deepEqual(at(state, ""), { proceed: false, skipReason: "awaiting-human", escalationReason: "conflict-patch-invalid" }, state);
  }
  assert.deepEqual(at("clean", "", { patchHeadSha: "b".repeat(40) }), { proceed: false, skipReason: "superseded-sha", escalationReason: "" });
  assert.deepEqual(at("conflicted", "written", { headSha: "b".repeat(40) }), { proceed: false, skipReason: "superseded-sha", escalationReason: "" });
});

// The Git Data API calls of one merge: 400 base-side files the base already
// holds upload nothing, two files both sides changed that merged cleanly and
// the one resolved conflict upload one blob each; the patch is the
// resolution alone, so max-files counts one path.
test("a merge with 400 base-side files, 2 clean two-sided merges and 1 resolution makes exactly 3 blobs, 1 tree, 1 commit and 1 ref update", async (t) => {
  const many = Object.fromEntries(Array.from({ length: 400 }, (_, i) => [`gen/f${i}.txt`, `${i} from main\n`]));
  const fix = mergeFixture(t, {
    base: { "a.txt": "one\n", "two/x.txt": "1\n2\n3\n4\n5\n", "two/y.txt": "1\n2\n3\n4\n5\n" },
    pr: { "a.txt": "pr\n", "two/x.txt": "1 pr\n2\n3\n4\n5\n", "two/y.txt": "1 pr\n2\n3\n4\n5\n" },
    main: { ...many, "a.txt": "main\n", "two/x.txt": "1\n2\n3\n4\n5 main\n", "two/y.txt": "1\n2\n3\n4\n5 main\n" },
    resolve: (repo) => writeFileSync(join(repo, "a.txt"), "pr and main\n"),
  });
  const api = fakeApi(fix.repo, fix.head);
  assert.equal((await mergePush(fix, api)).outcome, "pushed");
  assert.deepEqual(callNames(api), ["getPull", "listLabels", "readBranch", "createBlob", "createBlob", "createBlob", "createTree", "createCommit", "updateRef", "readBranch"]);
  const { createCommit } = api.calls.find((call) => call.createCommit);
  assert.deepEqual(createCommit.parents, [fix.head, fix.base]);
  assert.equal(git(fix.repo, ["rev-parse", `${createCommit.tree}:gen/f399.txt`]), git(fix.repo, ["rev-parse", `${fix.base}:gen/f399.txt`]));
  assert.equal(git(fix.repo, ["cat-file", "-p", `${createCommit.tree}:two/x.txt`]), "1 pr\n2\n3\n4\n5 main");
  // Patch paths over max-files, or new blobs over max-blobs: nothing is written.
  const twoConflicts = mergeFixture(t, {
    base: { "a.txt": "one\n", "b.txt": "one\n" },
    pr: { "a.txt": "pr\n", "b.txt": "pr\n" },
    main: { "a.txt": "main\n", "b.txt": "main\n" },
    resolve: (repo) => write(repo, { "a.txt": "a\n", "b.txt": "b\n" }),
  });
  const overFiles = fakeApi(twoConflicts.repo, twoConflicts.head);
  assert.deepEqual(await mergePush(twoConflicts, overFiles, { row: row("merge-base", { "max-files": 1 }) }), { outcome: "escalate", escalationReason: "conflict-patch-invalid" });
  assert.deepEqual(overFiles.calls, []);
  const overBlobs = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await mergePush(fix, overBlobs, { row: row("merge-base", { "max-blobs": 2 }) }), { outcome: "escalate", escalationReason: "conflict-patch-invalid" });
  assert.deepEqual(overBlobs.calls, []);
  assert.deepEqual([RULES["merge-base"]["max-files"], RULES["merge-base"]["max-blobs"]], [300, 300]);
});

test("a hold or a draft set while the model worked drops the merge uncommitted", async (t) => {
  const fix = mergeFixture(t, { ...CONFLICT, resolve: (repo) => writeFileSync(join(repo, "a.txt"), "resolved\n") });
  for (const overrides of [{ labels: [{ name: "needs-human" }] }, { pull: { draft: true, head: { repo: { full_name: "o/r" } } } }]) {
    const api = fakeApi(fix.repo, fix.head, overrides);
    assert.deepEqual(await mergePush(fix, api), { outcome: "held" });
    assert.deepEqual(writes(api), []);
  }
});

test("main reads the merge's conflicted paths from the checkout and takes no patch for a clean merge", async (t) => {
  const fix = mergeFixture(t, { ...CONFLICT, resolve: (repo) => writeFileSync(join(repo, "a.txt"), "resolved\n") });
  assert.deepEqual([...mergeFrom(mergeEnv(fix), { cwd: fix.repo, gitBin: "git" }).unmerged], ["a.txt"]);
  const base = scratch(t);
  mkdirSync(join(base, dirname(RULES_PATH)), { recursive: true });
  cpSync(join(REPO_ROOT, RULES_PATH), join(base, RULES_PATH));
  const out = scratch(t);
  const env = {
    BASE_DIR: base,
    PATCH_PREPARE: "merge-base",
    GH_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    PR_NUMBER: "42",
    HEAD_SHA: fix.head,
    PATCH_HEAD_SHA: fix.head,
    HEAD_REF: "feat/x",
    BASE_REF: "main",
    LANE: "pr-unblock",
    PATCH_ACTIVITY: "resolve-conflicts",
    PATCH_FILE: fix.patchFile,
    PATCH_SHA256: fix.sum,
    HOLD_LABELS: "[]",
    SKIP_REASON_FILE: join(out, "skip"),
    ESCALATION_REASON_FILE: join(out, "escalation"),
    GITHUB_OUTPUT: join(out, "output"),
    ...mergeEnv(fix),
  };
  await main([], env, { api: fakeApi(fix.repo, fix.head), cwd: fix.repo, gitBin: "git", log: () => {} });
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^commit=c{40}$/m);
  const clean = mergeFixture(t, { pr: { "p.txt": "pr\n" }, main: { "m.txt": "main\n" } });
  const cleanEnv = {
    ...env,
    HEAD_SHA: clean.head,
    PATCH_HEAD_SHA: clean.head,
    PATCH_FILE: join(out, "absent.diff"),
    PATCH_SHA256: "",
    GITHUB_OUTPUT: join(out, "clean-output"),
    ...mergeEnv(clean),
  };
  await main([], cleanEnv, { api: fakeApi(clean.repo, clean.head), cwd: clean.repo, gitBin: "git", log: () => {} });
  assert.match(readFileSync(cleanEnv.GITHUB_OUTPUT, "utf8"), /^commit=c{40}$/m);
});
