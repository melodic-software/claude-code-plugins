import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { checkRow, loadRules, main, push, refusalsOf, RULES_PATH, rowFor, select } from "./apply-patch.mjs";

// The registry as committed: the rows these tests hold apply-patch to.
const REPO_ROOT = join(import.meta.dirname, "../../..");
const RULES = loadRules(REPO_ROOT);
const row = (name, change = {}) => ({ ...rowFor(RULES, { prepare: name === "default" ? "" : name }), ...change });

const sha256 = (text) => createHash("sha256").update(text).digest("hex");
const entry = (path, oldMode = "100644", newMode = "100644") => ({ path, oldMode, newMode, newSha: "1".repeat(40) });

// Credential shapes built at run time, so no literal token sits in this file.
const ANTHROPIC_KEY = ["sk", "ant", "api03", "A1b2".repeat(20)].join("-");
const OAUTH_TOKEN = ["sk", "ant", "oat01", "Z9y8".repeat(20)].join("-");
const GITHUB_TOKENS = [`${"ghp"}_${"a1".repeat(18)}`, `${"ghs"}_${"B2".repeat(18)}`, `${"github"}_pat_${"c3".repeat(41)}`];

function scratch(t) {
  const dir = mkdtempSync(join(tmpdir(), "apply-patch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

// --- the refusal table: each refused path or mode, one case each ---

test("refuses .github/x", () => {
  assert.ok(refusalsOf(entry(".github/x")).includes("github"));
});

test("refuses .GitHub/x in another case", () => {
  assert.ok(refusalsOf(entry(".GitHub/x")).includes("github"));
});

test("refuses .github/../.github/x through a .. segment", () => {
  assert.ok(refusalsOf(entry(".github/../.github/x")).includes("github"));
});

test("refuses a/../.github/x through a .. segment", () => {
  assert.ok(refusalsOf(entry("a/../.github/x")).includes("github"));
});

test("refuses .claude/settings.json", () => {
  assert.ok(refusalsOf(entry(".claude/settings.json")).includes("claude"));
});

test("refuses the root .mcp.json", () => {
  assert.deepEqual(refusalsOf(entry(".mcp.json")), ["mcp-config"]);
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

test("admits plugin hooks, .claude-plugin, lib, scripts, CLAUDE.md and AGENTS.md", () => {
  for (const path of ["plugins/p/hooks/hooks.json", "plugins/p/.claude-plugin/plugin.json", "lib/x.mjs", "scripts/x.sh", "CLAUDE.md", "plugins/p/AGENTS.md"]) {
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
function repoWithPatch(t, edit, { renames = false } = {}) {
  const repo = scratch(t);
  git(repo, ["init", "-q", "-b", "main"]);
  git(repo, ["config", "user.email", "t@example.com"]);
  git(repo, ["config", "user.name", "t"]);
  mkdirSync(join(repo, "scripts"));
  writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\nfoo=1\n");
  writeFileSync(join(repo, "README.md"), "# r\n");
  writeFileSync(join(repo, "notes.md"), "notes\n");
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
    readBranch: async () => (record("readBranch"), tip),
    createBlob: async (content) => (record("createBlob"), git(repo, ["hash-object", "-w", "--stdin"], Buffer.from(content, "base64"))),
    createTree: async (baseTree, entries) => {
      record("createTree");
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
      tip = sha;
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

test("refuses a new executable bit on a file not executable at head", async (t) => {
  const fix = repoWithPatch(t, (repo) => chmodSync(join(repo, "README.md"), 0o755));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api), { outcome: "escalate", escalationReason: "patch-protected-path" });
  assert.deepEqual(api.calls, []);
});

test("refuses a rename from an allowed path into .github/", async (t) => {
  const fix = repoWithPatch(
    t,
    (repo) => {
      mkdirSync(join(repo, ".github"));
      renameSync(join(repo, "notes.md"), join(repo, ".github/notes.md"));
    },
    { renames: true },
  );
  assert.match(readFileSync(fix.patchFile, "utf8"), /^rename to \.github\/notes\.md$/m);
  const api = fakeApi(fix.repo, fix.head);
  const lines = [];
  assert.deepEqual(await pushWith(fix, api, { log: (line) => lines.push(line) }), { outcome: "escalate", escalationReason: "patch-protected-path" });
  assert.deepEqual(lines, ["refused (rename-into-refused): .github/notes.md"]);
  assert.deepEqual(api.calls, []);
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

test("requires dependency-verdict: fix refuses a patch without that verdict and applies one with it", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  const without = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, without, { row: row("dependency-review"), context: { dependencyVerdict: "close" } }), {
    outcome: "escalate",
    escalationReason: "patch-invalid",
  });
  assert.deepEqual(without.calls, []);
  const withVerdict = fakeApi(fix.repo, fix.head);
  assert.equal((await pushWith(fix, withVerdict, { row: row("dependency-review"), context: { dependencyVerdict: "fix" } })).outcome, "pushed");
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

test("kept-threads admits a kept thread's path and refuses one outside every thread's scope", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  const kept = fakeApi(fix.repo, fix.head);
  assert.equal((await pushWith(fix, kept, { row: row("review-threads"), context: { keptThreads: new Set(["README.md"]) } })).outcome, "pushed");
  const outside = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, outside, { row: row("review-threads"), context: { keptThreads: new Set(["notes.md"]) } }), {
    outcome: "escalate",
    escalationReason: "patch-protected-path",
  });
  assert.deepEqual(outside.calls, []);
  await assert.rejects(pushWith(fix, fakeApi(fix.repo, fix.head), { row: row("review-threads") }), /kept thread paths/);
});

test("merge-result throws before any write until merge commits are supported", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# changed\n"));
  const api = fakeApi(fix.repo, fix.head);
  await assert.rejects(pushWith(fix, api, { row: row("default", { allow: ["merge-result"] }) }), /merge-result is not supported/);
  assert.deepEqual(api.calls, []);
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
  assert.equal((await pushIssue(resumed, api, { headRef: `${LANE}/issue-7-124-1` })).outcome, "pushed");
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
    ["a .claude/ file", (repo) => (mkdirSync(join(repo, "plugins/p/.claude"), { recursive: true }), writeFileSync(join(repo, "plugins/p/.claude/x.md"), "x\n")), "patch-protected-path"],
    ["the root .mcp.json", (repo) => writeFileSync(join(repo, ".mcp.json"), "{}\n"), "patch-protected-path"],
    [".gitmodules", (repo) => writeFileSync(join(repo, ".gitmodules"), "\n"), "patch-protected-path"],
    ["a settings.json", (repo) => writeFileSync(join(repo, "settings.json"), "{}\n"), "patch-protected-path"],
    ["a symbolic link", (repo) => symlinkSync("README.md", join(repo, "link")), "patch-invalid"],
    ["a new executable bit", (repo) => chmodSync(join(repo, "notes.md"), 0o755), "patch-protected-path"],
  ];
  assert.deepEqual(issueRow().refuse, RULES.default.refuse);
  for (const [what, edit, reason] of cases) {
    const fix = repoWithPatch(t, edit);
    const api = fakeApi(fix.repo, fix.head, { labels: READY });
    assert.deepEqual(await pushIssue(fix, api), { outcome: "escalate", escalationReason: reason }, what);
    assert.deepEqual(api.calls, [], what);
  }
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
});
