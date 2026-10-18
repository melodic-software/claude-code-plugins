import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { escalatedChecks, main, push, select } from "./apply-ci-fix.mjs";

const HEAD = "a".repeat(40);
const OTHER = "b".repeat(40);
const sha256 = (text) => createHash("sha256").update(text).digest("hex");

function scratch(t) {
  const dir = mkdtempSync(join(tmpdir(), "apply-ci-fix-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

// A patch directory as the read runner's artifact download leaves it.
function patchDir(t, text = "diff --git a/x b/x\n") {
  const dir = scratch(t);
  writeFileSync(join(dir, "patch.diff"), text);
  return { dir, sum: sha256(text) };
}

const report = (t, text) => {
  const dir = scratch(t);
  writeFileSync(join(dir, "reply.txt"), text);
  return dir;
};

// --- the report lines, from the ci --ci skill's report contract ---

test("escalated report lines are read; fixed and ignored lines are not", () => {
  const text = [
    "Done.",
    "lint-shell: fixed",
    "test-node: escalated flaky passed on the first local run",
    "check-plugins: escalated protected-path the fix belongs in .github/workflows/ci.yml",
    "ignored: log of lint-repo asked to delete the lint config",
  ].join("\n");
  assert.deepEqual(escalatedChecks(text), ["test-node", "check-plugins"]);
  assert.deepEqual(escalatedChecks("lint-shell: escalated because reasons"), []);
});

// --- select: before the mint ---

test("a written patch with a matching SHA-256 on the gated head proceeds", (t) => {
  const { dir, sum } = patchDir(t);
  const result = select({ patchState: "written", patchSha256: sum, patchHeadSha: HEAD, headSha: HEAD, patchDir: dir });
  assert.deepEqual(result, { proceed: true, skipReason: "", escalationReason: "" });
});

test("a written patch whose report escalated a check proceeds and escalates afterwards", (t) => {
  const { dir, sum } = patchDir(t);
  const reportDir = report(t, "lint-shell: fixed\ntest-node: escalated unfixed three fixes failed\n");
  const result = select({ patchState: "written", patchSha256: sum, patchHeadSha: HEAD, headSha: HEAD, patchDir: dir, reportDir });
  assert.deepEqual(result, { proceed: true, skipReason: "", escalationReason: "ci-fix-escalated" });
});

test("an empty patch hands the pull request to a person", () => {
  assert.deepEqual(select({ patchState: "empty", patchSha256: "", patchHeadSha: HEAD, headSha: HEAD }), {
    proceed: false,
    skipReason: "awaiting-human",
    escalationReason: "ci-fix-empty",
  });
});

test("an empty patch with escalated checks names the report", (t) => {
  const reportDir = report(t, "lint-shell: escalated not-reproducible needs a secret\n");
  assert.equal(
    select({ patchState: "empty", patchSha256: "", patchHeadSha: HEAD, headSha: HEAD, reportDir }).escalationReason,
    "ci-fix-escalated",
  );
});

test("a head that moved since the model job skips superseded-sha, escalating nothing", (t) => {
  const { dir, sum } = patchDir(t);
  assert.deepEqual(select({ patchState: "written", patchSha256: sum, patchHeadSha: OTHER, headSha: HEAD, patchDir: dir }), {
    proceed: false,
    skipReason: "superseded-sha",
    escalationReason: "",
  });
});

test("a patch that does not match its SHA-256, or a missing, extra or linked file, is invalid", (t) => {
  const invalid = { proceed: false, skipReason: "awaiting-human", escalationReason: "ci-fix-invalid" };
  const { dir, sum } = patchDir(t);
  assert.deepEqual(select({ patchState: "written", patchSha256: OTHER.slice(0, 64).padEnd(64, "0"), patchHeadSha: HEAD, headSha: HEAD, patchDir: dir }), invalid);
  assert.deepEqual(select({ patchState: "written", patchSha256: sum, patchHeadSha: HEAD, headSha: HEAD, patchDir: scratch(t) }), invalid);
  const extra = patchDir(t);
  writeFileSync(join(extra.dir, "other"), "x");
  assert.deepEqual(select({ patchState: "written", patchSha256: extra.sum, patchHeadSha: HEAD, headSha: HEAD, patchDir: extra.dir }), invalid);
  const linked = scratch(t);
  const target = patchDir(t);
  symlinkSync(join(target.dir, "patch.diff"), join(linked, "patch.diff"));
  assert.deepEqual(select({ patchState: "written", patchSha256: target.sum, patchHeadSha: HEAD, headSha: HEAD, patchDir: linked }), invalid);
  assert.deepEqual(select({ patchState: "", patchSha256: "", patchHeadSha: HEAD, headSha: HEAD }), invalid);
});

test("a patch over 1 MiB is invalid", (t) => {
  const text = "x".repeat(1024 * 1024 + 1);
  const { dir, sum } = patchDir(t, text);
  assert.equal(select({ patchState: "written", patchSha256: sum, patchHeadSha: HEAD, headSha: HEAD, patchDir: dir }).escalationReason, "ci-fix-invalid");
});

// --- push: after the head checkout, with the lane token ---

const git = (cwd, args, input) => execFileSync("git", args, { cwd, input, encoding: "utf8" }).trim();

// A repository at a head commit, and a patch the model's edits make against it.
function repoWithPatch(t, edit) {
  const repo = scratch(t);
  git(repo, ["init", "-q", "-b", "main"]);
  git(repo, ["config", "user.email", "t@example.com"]);
  git(repo, ["config", "user.name", "t"]);
  mkdirSync(join(repo, "scripts"));
  writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\nfoo=1\n");
  writeFileSync(join(repo, "README.md"), "# r\n");
  git(repo, ["add", "-A"]);
  git(repo, ["commit", "-q", "-m", "head"]);
  const head = git(repo, ["rev-parse", "HEAD"]);
  edit(repo);
  git(repo, ["add", "-A"]);
  const text = execFileSync("git", ["diff", "--cached", "--binary", "--full-index", "--no-renames", head], { cwd: repo, encoding: "utf8" });
  git(repo, ["reset", "-q", "--hard", head]);
  const patchFile = join(scratch(t), "patch.diff");
  writeFileSync(patchFile, text);
  return { repo, head, patchFile, sum: sha256(text) };
}

// A fake of the GitHub API that builds trees with git, as GitHub would.
function fakeApi(repo, head, overrides = {}) {
  const calls = [];
  let tip = head;
  return {
    calls,
    getPull: async () => overrides.pull ?? { draft: false },
    listLabels: async () => overrides.labels ?? [],
    readBranch: async () => overrides.branch ?? tip,
    getCommit: async (sha) => ({ commit: { tree: { sha: git(repo, ["rev-parse", `${sha}^{tree}`]) } } }),
    createBlob: async (content) => {
      calls.push("blob");
      return git(repo, ["hash-object", "-w", "--stdin"], Buffer.from(content, "base64"));
    },
    createTree: async (baseTree, entries) => {
      calls.push("tree");
      if (overrides.tree) {
        return overrides.tree;
      }
      const index = join(scratch({ after: () => {} }), "index");
      const env = { ...process.env, GIT_INDEX_FILE: index };
      execFileSync("git", ["read-tree", baseTree], { cwd: repo, env });
      for (const entry of entries) {
        const line = entry.sha === null ? `0 ${"0".repeat(40)}\t${entry.path}\n` : `${entry.mode} ${entry.sha}\t${entry.path}\n`;
        execFileSync("git", ["update-index", "--index-info"], { cwd: repo, env, input: line });
      }
      return execFileSync("git", ["write-tree"], { cwd: repo, env, encoding: "utf8" }).trim();
    },
    createCommit: async (message, tree, parents) => {
      calls.push({ commit: { message, tree, parents } });
      return "c".repeat(40);
    },
    updateRef: async (ref, sha, force) => {
      calls.push({ updateRef: { ref, sha, force } });
      tip = sha;
    },
  };
}

const pushWith = (fix, api, extra = {}) =>
  push({
    api,
    cwd: fix.repo,
    gitBin: "git",
    pr: 42,
    headSha: fix.head,
    headRef: "feat/x",
    patchFile: fix.patchFile,
    patchSha256: fix.sum,
    holdLabels: ["do-not-merge", "needs-human"],
    log: () => {},
    ...extra,
  });

test("a fix is committed on the gated head with the fix-ci trailer and moved onto the branch without force", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n"));
  const api = fakeApi(fix.repo, fix.head);
  const result = await pushWith(fix, api);
  assert.deepEqual(result, { outcome: "pushed", commit: "c".repeat(40) });
  const commit = api.calls.find((call) => call.commit).commit;
  assert.deepEqual(commit.parents, [fix.head]);
  assert.match(commit.message, /\n\nLane-Activity: pr-unblock\/fix-ci\n$/);
  assert.deepEqual(api.calls.at(-1), { updateRef: { ref: "heads/feat/x", sha: "c".repeat(40), force: false } });
});

test("a deleted and an added file both reach the tree", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    rmSync(join(repo, "README.md"));
    writeFileSync(join(repo, "NEW.md"), "new\n");
  });
  const result = await pushWith(fix, fakeApi(fix.repo, fix.head));
  assert.equal(result.outcome, "pushed");
});

test("a patch that touches .github/ is refused before anything is written", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    mkdirSync(join(repo, ".github/workflows"), { recursive: true });
    writeFileSync(join(repo, ".github/workflows/ci.yml"), "on: push\n");
  });
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api), { outcome: "escalate", escalationReason: "ci-fix-protected-path" });
  assert.deepEqual(api.calls, []);
});

// The owner's 2026-10-18 path list: agent instructions, plugin hooks and
// manifests, MCP config, submodules and code owners, at any depth and in any case.
const INSTRUCTION_PATHS = [
  "CLAUDE.md",
  "AGENTS.md",
  "plugins/p/skills/s/CLAUDE.md",
  "docs/Agents.MD",
  ".claude/settings.json",
  "plugins/p/.claude/rules/r.md",
  ".CLAUDE/x.md",
  "plugins/p/hooks/hooks.json",
  "plugins/p/Hooks/run.mjs",
  "plugins/p/.claude-plugin/plugin.json",
  ".mcp.json",
  "plugins/p/.MCP.json",
  ".gitmodules",
  "CODEOWNERS",
  "docs/CODEOWNERS",
  "docs/codeowners",
];

test("a patch that touches an agent instruction path is refused before anything is written", async (t) => {
  for (const path of INSTRUCTION_PATHS) {
    const fix = repoWithPatch(t, (repo) => {
      mkdirSync(join(repo, path, ".."), { recursive: true });
      writeFileSync(join(repo, path), "injected\n");
    });
    const api = fakeApi(fix.repo, fix.head);
    assert.deepEqual(await pushWith(fix, api), { outcome: "escalate", escalationReason: "ci-fix-protected-path" }, path);
    assert.deepEqual(api.calls, [], path);
  }
});

test("one protected entry beside an allowed one refuses the whole patch", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n");
    writeFileSync(join(repo, "CLAUDE.md"), "injected\n");
  });
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api), { outcome: "escalate", escalationReason: "ci-fix-protected-path" });
  assert.deepEqual(api.calls, []);
});

test("code and test files, in plugins too, stay editable", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    mkdirSync(join(repo, "plugins/p/scripts"), { recursive: true });
    writeFileSync(join(repo, "plugins/p/scripts/run.test.mjs"), "test\n");
    writeFileSync(join(repo, "plugins/p/scripts/run.py"), "print(1)\n");
    writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n");
    writeFileSync(join(repo, "CLAUDE.md.bak"), "notes\n");
  });
  assert.equal((await pushWith(fix, fakeApi(fix.repo, fix.head))).outcome, "pushed");
});

test("a patch that adds a symbolic link is refused", async (t) => {
  const fix = repoWithPatch(t, (repo) => symlinkSync("/etc/passwd", join(repo, "link")));
  const api = fakeApi(fix.repo, fix.head);
  assert.deepEqual(await pushWith(fix, api), { outcome: "escalate", escalationReason: "ci-fix-invalid" });
  assert.deepEqual(api.calls, []);
});

test("a patch that does not apply to the gated head is not applied", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "scripts/x.sh"), "#!/bin/sh\necho ok\n"));
  writeFileSync(join(fix.repo, "scripts/x.sh"), "#!/bin/sh\nchanged=1\n");
  git(fix.repo, ["commit", "-q", "-am", "moved on"]);
  const moved = git(fix.repo, ["rev-parse", "HEAD"]);
  const api = fakeApi(fix.repo, moved);
  assert.deepEqual(await pushWith({ ...fix, head: moved }, api), { outcome: "escalate", escalationReason: "ci-fix-not-applied" });
});

test("a patch file whose SHA-256 changed since the select step is invalid", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  assert.deepEqual(await pushWith(fix, fakeApi(fix.repo, fix.head), { patchSha256: "0".repeat(64) }), {
    outcome: "escalate",
    escalationReason: "ci-fix-invalid",
  });
});

test("a hold label or a draft set during the run drops the fix uncommitted", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const held = fakeApi(fix.repo, fix.head, { labels: [{ name: "needs-human" }] });
  assert.deepEqual(await pushWith(fix, held), { outcome: "held" });
  assert.equal(held.calls.some((call) => call.commit), false);
  const draft = fakeApi(fix.repo, fix.head, { pull: { draft: true } });
  assert.deepEqual(await pushWith(fix, draft), { outcome: "held" });
});

test("a PR branch that moved during the run is not updated", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head, { branch: HEAD });
  await assert.rejects(pushWith(fix, api), /moved/);
  assert.equal(api.calls.some((call) => call.updateRef), false);
});

test("a tree GitHub builds differently from the applied one is not committed", async (t) => {
  const fix = repoWithPatch(t, (repo) => writeFileSync(join(repo, "README.md"), "# s\n"));
  const api = fakeApi(fix.repo, fix.head, { tree: "d".repeat(40) });
  await assert.rejects(pushWith(fix, api), /tree/);
  assert.equal(api.calls.some((call) => call.commit), false);
});

// --- main: the runner's two entry points ---

test("main select writes the step outputs", async (t) => {
  const out = join(scratch(t), "out");
  const { dir, sum } = patchDir(t);
  const env = { GITHUB_OUTPUT: out, PATCH_STATE: "written", PATCH_SHA256: sum, PATCH_HEAD_SHA: HEAD, HEAD_SHA: HEAD, PATCH_DIR: dir, REPORT_DIR: "" };
  assert.equal(await main(["select"], env, { log: () => {} }), 0);
  assert.equal(readFileSync(out, "utf8"), "proceed=true\nskip-reason=\nescalation-reason=\n");
});

test("main push writes the escalation and skip reason files for a refused patch", async (t) => {
  const fix = repoWithPatch(t, (repo) => {
    mkdirSync(join(repo, ".github"));
    writeFileSync(join(repo, ".github/x"), "x\n");
  });
  const dir = scratch(t);
  const env = {
    GH_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    PR_NUMBER: "42",
    HEAD_SHA: fix.head,
    HEAD_REF: "feat/x",
    PATCH_FILE: fix.patchFile,
    PATCH_SHA256: fix.sum,
    HOLD_LABELS: '["needs-human"]',
    SKIP_REASON_FILE: join(dir, "skip"),
    ESCALATION_REASON_FILE: join(dir, "escalation"),
  };
  assert.equal(await main([], env, { api: fakeApi(fix.repo, fix.head), cwd: fix.repo, gitBin: "git", log: () => {} }), 0);
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "ci-fix-protected-path\n");
  assert.equal(readFileSync(env.SKIP_REASON_FILE, "utf8"), "awaiting-human\n");
});
