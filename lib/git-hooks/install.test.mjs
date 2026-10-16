// Contract tests for lib/git-hooks/install.mjs: every adapter against a real
// git repository, with commits that run the installed hooks. A fixture plugin
// carries one pre-commit entry that blocks a changed line holding BADWORD, so
// these cases need no external checker. Expected outcomes come from the
// check-placement contract (drift states, decision kinds, the stamp line), not
// from running the code under test.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { main, readStamp, stampHash, validateEntries } from "./install.mjs";
import { main as prerequisites } from "../prerequisites.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const work = mkdtempSync(path.join(tmpdir(), "git-hooks-test-"));
after(() => rmSync(work, { recursive: true, force: true }));
const has = (tool) => spawnSync("sh", ["-c", `command -v ${tool}`]).status === 0;
const posixHost = process.platform !== "win32";

// Git sees no global or system config, so a host core.hooksPath cannot leak in.
const baseEnv = { ...process.env, GIT_CONFIG_GLOBAL: path.join(work, "no-global"), GIT_CONFIG_NOSYSTEM: "1" };
for (const k of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "CLAUDECODE", "AI_AGENT", "HUSKY", "CLAUDE_PLUGIN_DATA"]) {
  delete baseEnv[k];
}
process.env.GIT_CONFIG_GLOBAL = baseEnv.GIT_CONFIG_GLOBAL;
process.env.GIT_CONFIG_NOSYSTEM = "1";

let counter = 0;
function git(repo, args, env = {}) {
  const r = spawnSync("git", args, { cwd: repo, encoding: "utf8", env: { ...baseEnv, ...env } });
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

function repo() {
  const dir = path.join(work, `repo${++counter}`);
  mkdirSync(dir);
  git(dir, ["init", "-q", "-b", "main"]);
  git(dir, ["config", "user.name", "t"]);
  git(dir, ["config", "user.email", "t@example.invalid"]);
  writeFileSync(path.join(dir, "notes.txt"), "an old BADWORD line\n");
  git(dir, ["add", "notes.txt"]);
  git(dir, ["commit", "-q", "-m", "seed", "--no-verify"]);
  return dir;
}

const WORD_CHECK = `#!/usr/bin/env bash
# demo-checks word-check: block a changed line holding BADWORD.
set -uo pipefail
here="\${BASH_SOURCE[0]%/*}"
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
. "$lib" || exit 1
checks_init pre-commit "$@" || exit 0
checks_require_tool "\${WORD_CHECK_TOOL:-grep}" "install-it-here"
checks_changed_lines
: >"$CHECKS_TMP/found"
while IFS= read -r -d '' f; do
  grep -n BADWORD -- "$f" | sed "s#^\\([0-9]*\\):.*#$f:\\1: BADWORD#" >>"$CHECKS_TMP/found"
done < <(checks_files)
checks_filter_findings <"$CHECKS_TMP/found" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
exit 1
`;

function plugin(entries) {
  const root = path.join(work, `plugin${++counter}`);
  mkdirSync(path.join(root, ".claude-plugin"), { recursive: true });
  mkdirSync(path.join(root, "git-hooks"));
  mkdirSync(path.join(root, "lib", "git-hooks"), { recursive: true });
  writeFileSync(path.join(root, ".claude-plugin", "plugin.json"), JSON.stringify({ name: "demo-checks" }));
  const list = entries ?? [{ name: "word-check", event: "pre-commit", script: "word-check.sh", tools: ["grep"], rewrites: false }];
  writeFileSync(path.join(root, "git-hooks", "entries.json"), JSON.stringify({ entries: list }));
  writeFileSync(path.join(root, "git-hooks", "word-check.sh"), WORD_CHECK);
  copyFileSync(path.join(here, "check-lib.sh"), path.join(root, "lib", "git-hooks", "check-lib.sh"));
  const prereq = {
    id: "grep",
    kind: "cli",
    need: "required",
    for: ["hook:word-check.sh"],
    detect: { any: ["grep"] },
    degrade: "Without grep nothing is checked.",
    install: { docs: "https://example.invalid/grep" },
    check: "/demo-checks:check",
  };
  writeFileSync(path.join(root, "prerequisites.json"), JSON.stringify({ requires: [prereq] }));
  return root;
}

function run(root, dir, ...args) {
  const out = [];
  const err = [];
  const code = main([...args, "--repo", dir, "--plugin-root", root], {}, { stdout: (s) => out.push(s), stderr: (s) => err.push(s) });
  return { code, out, err, json: () => JSON.parse(out.join("\n")) };
}

function stageBad(dir, file = "change.txt") {
  writeFileSync(path.join(dir, file), "fine\nnew BADWORD here\n");
  git(dir, ["add", file]);
}

function commit(dir, env = {}, extra = []) {
  return git(dir, [...extra, "commit", "-q", "-m", "change"], env);
}

const kinds = (planned) => planned.decisions.map((d) => d.kind);

describe("plain", () => {
  test("plain local: a changed line blocks the commit, an unchanged one does not", () => {
    const root = plugin();
    const dir = repo();
    assert.equal(run(root, dir, "detect").json().manager, "plain");
    assert.deepEqual(run(root, dir, "copy", "--scope", "local").json(), [{ entry: "word-check", status: "installed" }]);
    stageBad(dir);
    const blocked = commit(dir);
    assert.equal(blocked.status, 1);
    assert.match(blocked.stderr, /^change\.txt:2: BADWORD$/m);
    writeFileSync(path.join(dir, "notes.txt"), "an old BADWORD line\nclean addition\n");
    git(dir, ["rm", "-q", "--cached", "change.txt"]);
    git(dir, ["add", "notes.txt"]);
    assert.equal(commit(dir).status, 0, "BADWORD on an unchanged line must not block");
    assert.equal(run(root, dir, "verify").code, 0);
  });

  test("plain shared: copies are staged executable, .gitattributes is created, core.hooksPath is a decision", () => {
    const root = plugin();
    const dir = repo();
    const planned = run(root, dir, "plan", "--scope", "shared").json();
    assert.ok(kinds(planned).includes("hooks-path"));
    assert.ok(planned.actions.some((a) => a.op === "gitattributes"));
    run(root, dir, "copy", "--scope", "shared");
    const staged = git(dir, ["ls-files", "-s", ".githooks"]).stdout;
    assert.match(staged, /^100755 \S+ 0\t\.githooks\/demo-checks\/word-check\.sh$/m);
    assert.match(staged, /^100755 \S+ 0\t\.githooks\/pre-commit$/m);
    assert.match(staged, /^100644 \S+ 0\t\.githooks\/pre-commit\.d\/demo-checks\.word-check$/m);
    assert.equal(readFileSync(path.join(dir, ".gitattributes"), "utf8"), ".githooks/** text eol=lf\n");
    assert.match(run(root, dir, "verify").out.join("\n"), /^missing\tword-check\t/m, "not active until core.hooksPath is set");
    git(dir, ["config", "core.hooksPath", ".githooks"]);
    assert.equal(run(root, dir, "verify").code, 0);
    stageBad(dir);
    assert.equal(commit(dir).status, 1);
  });

  test("plain: an existing hook is a foreign-hook decision and runs first once chained", () => {
    const root = plugin();
    const dir = repo();
    const hook = path.join(dir, ".git", "hooks", "pre-commit");
    writeFileSync(hook, "#!/bin/sh\necho chained-ran >&2\n");
    chmodSync(hook, 0o755);
    const planned = run(root, dir, "plan", "--scope", "local").json();
    assert.deepEqual(
      planned.decisions.find((d) => d.kind === "foreign-hook"),
      { kind: "foreign-hook", file: hook, chainAs: `${hook}.pre-checks` },
    );
    run(root, dir, "copy", "--scope", "local");
    assert.equal(readFileSync(hook, "utf8"), "#!/bin/sh\necho chained-ran >&2\n", "copy never overwrites a foreign hook");
    writeFileSync(`${hook}.pre-checks`, readFileSync(hook));
    chmodSync(`${hook}.pre-checks`, 0o755);
    rmSync(hook);
    run(root, dir, "copy", "--scope", "local");
    stageBad(dir);
    const r = commit(dir);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /chained-ran/);
  });

  test("dash: the plain dispatcher runs under dash", { skip: !has("dash") }, () => {
    const root = plugin();
    const dir = repo();
    run(root, dir, "copy", "--scope", "local");
    stageBad(dir);
    const r = spawnSync("dash", [path.join(dir, ".git", "hooks", "pre-commit")], { cwd: dir, encoding: "utf8", env: baseEnv });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /change\.txt:2: BADWORD/);
  });
});

describe("lefthook", { skip: !has("lefthook") }, () => {
  test("lefthook shared: plan renders the job, and the commit blocks once it is applied", () => {
    const root = plugin();
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), "# project hooks\n");
    assert.equal(run(root, dir, "detect").json().manager, "lefthook");
    const planned = run(root, dir, "plan", "--scope", "shared").json();
    assert.ok(kinds(planned).includes("lefthook-install"));
    const config = planned.decisions.find((d) => d.kind === "lefthook-config");
    assert.equal(config.file, "lefthook.yml");
    assert.equal(
      config.snippet,
      "pre-commit:\n  jobs:\n    - name: demo-checks-word-check\n      run: bash .githooks/demo-checks/word-check.sh",
    );
    run(root, dir, "copy", "--scope", "shared");
    writeFileSync(path.join(dir, "lefthook.yml"), `# project hooks\n${config.snippet}\n`);
    assert.equal(spawnSync("lefthook", ["install"], { cwd: dir, env: baseEnv }).status, 0);
    assert.equal(run(root, dir, "verify").code, 0);
    stageBad(dir);
    const r = commit(dir);
    assert.notEqual(r.status, 0);
    assert.match(`${r.stdout}${r.stderr}`, /change\.txt:2: BADWORD/);
  });

  test("lefthook local: the job goes to lefthook-local.yml, which must be ignored", () => {
    const root = plugin();
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), "# project hooks\n");
    const planned = run(root, dir, "plan", "--scope", "local").json();
    const config = planned.decisions.find((d) => d.kind === "lefthook-config");
    assert.equal(config.file, "lefthook-local.yml");
    assert.match(config.snippet, /run: bash \.git\/hooks\/demo-checks\/word-check\.sh$/);
    assert.deepEqual(planned.decisions.find((d) => d.kind === "exclude"), {
      kind: "exclude",
      file: path.join(dir, ".git", "info", "exclude"),
      line: "/lefthook-local.yml",
    });
  });
});

describe("husky", () => {
  // A stand-in for husky 9's layout (.husky/_/h runs .husky/<event> with sh -e),
  // since the npm package is not installed in the test lane.
  function huskyRepo() {
    const dir = repo();
    mkdirSync(path.join(dir, ".husky", "_"), { recursive: true });
    const shell = has("dash") ? "dash" : "sh";
    writeFileSync(
      path.join(dir, ".husky", "_", "h"),
      `#!/bin/sh\nn=$(basename "$0")\ns=$(dirname "$(dirname "$0")")/$n\n[ ! -f "$s" ] && exit 0\n${shell} -e "$s" "$@"\n`,
    );
    writeFileSync(path.join(dir, ".husky", "_", "pre-commit"), '#!/bin/sh\n. "$(dirname "$0")/h"\n');
    chmodSync(path.join(dir, ".husky", "_", "pre-commit"), 0o755);
    git(dir, ["config", "core.hooksPath", ".husky/_"]);
    return dir;
  }

  test("husky: local scope is refused as husky-shared-only", () => {
    const root = plugin();
    const dir = huskyRepo();
    assert.equal(run(root, dir, "detect").json().manager, "husky");
    const planned = run(root, dir, "plan", "--scope", "local").json();
    assert.deepEqual(kinds(planned), ["husky-shared-only"]);
    assert.equal(run(root, dir, "copy", "--scope", "local").code, 2);
  });

  test("husky shared under dash -e: the rendered line blocks the commit", () => {
    const root = plugin();
    const dir = huskyRepo();
    const planned = run(root, dir, "plan", "--scope", "shared").json();
    const config = planned.decisions.find((d) => d.kind === "husky-config");
    assert.deepEqual(config, {
      kind: "husky-config",
      entry: "word-check",
      file: ".husky/pre-commit",
      snippet: "bash .githooks/demo-checks/word-check.sh",
    });
    run(root, dir, "copy", "--scope", "shared");
    writeFileSync(path.join(dir, ".husky", "pre-commit"), `${config.snippet}\n`);
    assert.equal(run(root, dir, "verify").code, 0);
    stageBad(dir);
    const r = commit(dir);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /change\.txt:2: BADWORD/);
  });
});

describe("drift", () => {
  function installed() {
    const root = plugin();
    const dir = repo();
    run(root, dir, "copy", "--scope", "local");
    return { root, dir, copy: path.join(dir, ".git", "hooks", "demo-checks", "word-check.sh") };
  }

  test("idempotent: a second copy reports unchanged and leaves every byte alone", () => {
    const { root, dir, copy } = installed();
    const before = readFileSync(copy, "utf8");
    assert.deepEqual(run(root, dir, "copy", "--scope", "local").json(), [{ entry: "word-check", status: "unchanged" }]);
    assert.equal(readFileSync(copy, "utf8"), before);
    assert.equal(run(root, dir, "plan", "--scope", "local").json().actions[0].state, "ok");
  });

  test("the stamp is line 2 and hashes the source script plus the check lib", () => {
    const { root, copy } = installed();
    const lines = readFileSync(copy, "utf8").split("\n");
    const source = readFileSync(path.join(root, "git-hooks", "word-check.sh"), "utf8");
    const lib = readFileSync(path.join(root, "lib", "git-hooks", "check-lib.sh"), "utf8");
    assert.equal(lines[0], "#!/usr/bin/env bash");
    assert.equal(lines[1], `# demo-checks word-check sha256:${stampHash(source, lib)}`);
    assert.equal(readStamp(lines.join("\n")).body, source);
  });

  test("stale: a changed source reports stale, and copy refreshes it", () => {
    const { root, dir } = installed();
    writeFileSync(path.join(root, "git-hooks", "word-check.sh"), `${WORD_CHECK}# changed\n`);
    const r = run(root, dir, "verify", "--quiet");
    assert.deepEqual(r.out, ["demo-checks: git hook word-check stale; run /demo-checks:setup apply install-git-hooks"]);
    assert.equal(run(root, dir, "copy", "--scope", "local").json()[0].status, "refreshed");
    assert.deepEqual(run(root, dir, "verify", "--quiet").out, []);
  });

  test("modified: an edited copy reports modified, copy refuses it, --force replaces it", () => {
    const { root, dir, copy } = installed();
    writeFileSync(copy, `${readFileSync(copy, "utf8")}echo local edit\n`);
    assert.match(run(root, dir, "verify").out.join("\n"), /^modified\tword-check\t/m);
    const refused = run(root, dir, "copy", "--scope", "local");
    assert.equal(refused.code, 1);
    assert.equal(refused.json()[0].status, "refused");
    assert.ok(kinds(run(root, dir, "plan", "--scope", "local").json()).includes("modified"));
    assert.equal(run(root, dir, "copy", "--scope", "local", "--force").json()[0].status, "refreshed");
    assert.equal(run(root, dir, "verify").code, 0);
  });

  test("crlf: a copy checked out with CRLF line endings still verifies ok", () => {
    const { root, dir, copy } = installed();
    writeFileSync(copy, readFileSync(copy, "utf8").replace(/\n/g, "\r\n"));
    const lib = path.join(path.dirname(copy), "check-lib.sh");
    writeFileSync(lib, readFileSync(lib, "utf8").replace(/\n/g, "\r\n"));
    assert.equal(run(root, dir, "verify").out[0], "ok\tword-check");
  });

  test("missing: a never-installed entry is drift, with the exact user line", () => {
    const root = plugin();
    const dir = repo();
    const r = run(root, dir, "verify", "--quiet");
    assert.equal(r.code, 0);
    assert.deepEqual(r.out, ["demo-checks: git hook word-check missing; run /demo-checks:setup apply install-git-hooks"]);
    assert.equal(run(root, dir, "verify").code, 1);
  });

  test("declined: silent in quiet mode, reported by hand, cleared by an install", () => {
    const root = plugin();
    const dir = repo();
    assert.equal(run(root, dir, "decline", "--entry", "word-check").code, 0);
    assert.equal(git(dir, ["config", "--local", "--get", "checks.demo-checks.word-check.declined"]).stdout.trim(), "true");
    assert.deepEqual(run(root, dir, "verify", "--quiet").out, []);
    assert.equal(run(root, dir, "verify").out[0], "declined\tword-check");
    run(root, dir, "copy", "--scope", "local");
    assert.equal(git(dir, ["config", "--local", "--get", "checks.demo-checks.word-check.declined"]).status, 1);
  });

  test("verify outside a git repository is silent under --quiet", () => {
    const root = plugin();
    const dir = mkdtempSync(path.join(work, "nogit-"));
    const r = run(root, dir, "verify", "--quiet");
    assert.equal(r.code, 0);
    assert.deepEqual(r.out, []);
  });

  test("migrate: a shared plan names the local copies left behind", () => {
    const { root, dir, copy } = installed();
    const migrate = run(root, dir, "plan", "--scope", "shared").json().decisions.find((d) => d.kind === "migrate");
    assert.deepEqual(migrate, { kind: "migrate", from: "local", files: [copy] });
  });

  test("missing tool and CI coverage are decisions with the plugin's install hint", () => {
    const root = plugin([{ name: "word-check", event: "pre-commit", script: "word-check.sh", tools: ["nosuchtool-xyz"], rewrites: false }]);
    const prereq = JSON.parse(readFileSync(path.join(root, "prerequisites.json"), "utf8"));
    prereq.requires[0].id = "nosuchtool-xyz";
    prereq.requires[0].install = { cargo: "cargo install nosuchtool-xyz", docs: "https://example.invalid/x" };
    writeFileSync(path.join(root, "prerequisites.json"), JSON.stringify(prereq));
    const dir = repo();
    const planned = run(root, dir, "plan", "--scope", "local").json();
    assert.deepEqual(planned.decisions.find((d) => d.kind === "missing-tool"), {
      kind: "missing-tool",
      entry: "word-check",
      tool: "nosuchtool-xyz",
      install: "cargo install nosuchtool-xyz; https://example.invalid/x",
    });
    assert.ok(kinds(planned).includes("no-ci-rerun"));
    assert.match(run(root, dir, "verify").out.join("\n"), /^tool\tnosuchtool-xyz\tmissing$/m);
  });
});

describe("repository shapes", () => {
  test("linked-worktree: local copies land in the common hooks dir, and the exclude file is the common one", () => {
    const root = plugin();
    const dir = repo();
    const linked = path.join(work, `linked${++counter}`);
    git(dir, ["worktree", "add", "-q", "-b", "side", linked]);
    writeFileSync(path.join(linked, "lefthook.yml"), "# hooks\n");
    const planned = run(root, linked, "plan", "--scope", "local").json();
    assert.equal(planned.decisions.find((d) => d.kind === "exclude").file, path.join(dir, ".git", "info", "exclude"));
    rmSync(path.join(linked, "lefthook.yml"));
    run(root, linked, "copy", "--scope", "local");
    assert.ok(existsSync(path.join(dir, ".git", "hooks", "demo-checks", "word-check.sh")));
    stageBad(linked);
    assert.equal(commit(linked).status, 1);
  });

  test("foreign-manager: the pre-commit framework or two managers make a manager-conflict", () => {
    const root = plugin();
    const dir = repo();
    writeFileSync(path.join(dir, ".pre-commit-config.yaml"), "repos: []\n");
    const planned = run(root, dir, "plan", "--scope", "local").json();
    assert.equal(planned.manager, "conflict");
    assert.deepEqual(planned.decisions, [
      { kind: "manager-conflict", evidence: [{ manager: "pre-commit", evidence: ".pre-commit-config.yaml" }] },
    ]);
    assert.deepEqual(planned.actions, []);
    assert.equal(run(root, dir, "copy", "--scope", "local").code, 2);
    rmSync(path.join(dir, ".pre-commit-config.yaml"));
    writeFileSync(path.join(dir, "lefthook.yml"), "\n");
    mkdirSync(path.join(dir, ".husky"));
    assert.equal(run(root, dir, "detect").json().manager, "conflict");
    assert.equal(run(root, dir, "plan", "--scope", "local", "--manager", "plain").json().manager, "plain");
  });

  test("simple-git-hooks, overcommit and husky v4 are each detected as foreign", () => {
    const root = plugin();
    for (const [file, text, manager] of [
      [".simple-git-hooks.json", "{}", "simple-git-hooks"],
      [".overcommit.yml", "{}", "overcommit"],
      [".huskyrc", "{}", "husky-v4"],
    ]) {
      const dir = repo();
      writeFileSync(path.join(dir, file), text);
      assert.deepEqual(run(root, dir, "detect").json(), { manager: "conflict", evidence: [{ manager, evidence: file }] });
    }
  });
});

describe("manifest", () => {
  test("a rewriting pre-push entry and a bad event are rejected", () => {
    const errors = validateEntries({
      entries: [
        { name: "a", event: "pre-push", script: "a.sh", tools: [], rewrites: true },
        { name: "b", event: "post-merge", script: "b.sh", tools: [], rewrites: false },
      ],
    });
    assert.deepEqual(errors, [
      "entries[0]: a pre-push entry cannot rewrite",
      "entries[1].event must be one of pre-commit, pre-push, commit-msg",
    ]);
  });

  test("a plugin without entries.json is a usage error", () => {
    const root = plugin();
    rmSync(path.join(root, "git-hooks", "entries.json"));
    assert.equal(run(root, repo(), "verify").code, 2);
  });
});

describe("prerequisites probe", () => {
  test("the SessionStart probe prints the drift line once per session", () => {
    const root = plugin();
    const dir = repo();
    const data = mkdtempSync(path.join(work, "data-"));
    const probe = () => {
      const out = [];
      const env = { ...baseEnv, CLAUDE_PLUGIN_DATA: data, CLAUDE_PROJECT_DIR: dir };
      prerequisites(["probe", root], { env, cwd: dir, stdin: () => '{"session_id":"s1"}' }, { stdout: (s) => out.push(s), stderr: () => {} });
      return out;
    };
    assert.deepEqual(probe().map((s) => JSON.parse(s)), [
      { systemMessage: "demo-checks: git hook word-check missing; run /demo-checks:setup apply install-git-hooks" },
    ]);
    assert.deepEqual(probe(), []);
  });

  test("an installed, current entry keeps the probe silent", () => {
    const root = plugin();
    const dir = repo();
    run(root, dir, "copy", "--scope", "local");
    const out = [];
    const env = { ...baseEnv, CLAUDE_PROJECT_DIR: dir };
    prerequisites(["probe", root], { env, cwd: dir, stdin: () => "{}" }, { stdout: (s) => out.push(s), stderr: () => {} });
    assert.deepEqual(out, []);
  });
});

test("installed scripts are executable", { skip: !posixHost }, () => {
  const root = plugin();
  const dir = repo();
  run(root, dir, "copy", "--scope", "local");
  assert.ok(statSync(path.join(dir, ".git", "hooks", "pre-commit")).mode & 0o100);
  assert.ok(statSync(path.join(dir, ".git", "hooks", "demo-checks", "word-check.sh")).mode & 0o100);
});
