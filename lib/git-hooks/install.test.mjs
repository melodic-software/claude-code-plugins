// Contract tests for lib/git-hooks/install.mjs: every adapter against a real
// git repository, with commits that run the installed hooks. A fixture plugin
// carries one pre-commit entry that blocks a changed line holding BADWORD, so
// these cases need no external checker. Expected outcomes come from the
// check-placement contract (drift states, decision kinds, the stamp line), not
// from running the code under test.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { DISPATCHER, main, PRIOR_DISPATCHERS, readStamp, validateEntries } from "./install.mjs";
import { main as prerequisites } from "../prerequisites.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const work = mkdtempSync(path.join(tmpdir(), "git-hooks-test-"));
after(() => rmSync(work, { recursive: true, force: true }));
const has = (tool) => spawnSync("sh", ["-c", `command -v ${tool}`]).status === 0;
const posixHost = process.platform !== "win32";

// Git sees no global or system config, so a host core.hooksPath cannot leak in,
// and runs no detached auto maintenance, whose lock file would change a tree() snapshot.
const gitEnv = {
  GIT_CONFIG_GLOBAL: path.join(work, "no-global"),
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_COUNT: "2",
  GIT_CONFIG_KEY_0: "maintenance.auto",
  GIT_CONFIG_VALUE_0: "false",
  GIT_CONFIG_KEY_1: "gc.auto",
  GIT_CONFIG_VALUE_1: "0",
};
const baseEnv = { ...process.env, ...gitEnv };
for (const k of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "CLAUDECODE", "AI_AGENT", "HUSKY", "CLAUDE_PLUGIN_DATA"]) {
  delete baseEnv[k];
}
Object.assign(process.env, gitEnv);

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

// The entry shape the check-placement contract gives: POSIX sh until the check
// lib, sourced first, has it running under bash.
const WORD_CHECK = `#!/bin/sh
# demo-checks word-check: block a changed line holding BADWORD.
case "$0" in
*/*) here="\${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
. "$lib" || exit 1
set -uo pipefail
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

function plugin(entries, manifest = {}) {
  const root = path.join(work, `plugin${++counter}`);
  mkdirSync(path.join(root, ".claude-plugin"), { recursive: true });
  mkdirSync(path.join(root, "git-hooks"));
  mkdirSync(path.join(root, "lib", "git-hooks"), { recursive: true });
  writeFileSync(path.join(root, ".claude-plugin", "plugin.json"), JSON.stringify({ name: "demo-checks" }));
  const list = entries ?? [{ name: "word-check", event: "pre-commit", script: "word-check.sh", tools: ["grep"], rewrites: false }];
  writeFileSync(path.join(root, "git-hooks", "entries.json"), JSON.stringify({ ...manifest, entries: list }));
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

// tree(dir) -> sorted "<relative path> <mode> <sha256 of bytes>" for every file
// and directory under dir, so a before/after comparison sees any write.
function tree(dir, base = dir) {
  return readdirSync(dir, { withFileTypes: true })
    .flatMap((d) => {
      const full = path.join(dir, d.name);
      const rel = path.relative(base, full);
      const mode = (statSync(full).mode & 0o777).toString(8);
      if (d.isDirectory()) return [`${rel}/ ${mode}`, ...tree(full, base)];
      return [`${rel} ${mode} ${createHash("sha256").update(readFileSync(full)).digest("hex")}`];
    })
    .sort();
}

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

  test("plain local: a marker naming another script reads as drift, and copy repairs it", () => {
    const root = plugin();
    const dir = repo();
    run(root, dir, "copy", "--scope", "local");
    const marker = path.join(dir, ".git", "hooks", "pre-commit.d", "demo-checks.word-check");
    writeFileSync(marker, "demo-checks/gone.sh\n");
    const drifted = run(root, dir, "verify");
    assert.equal(drifted.code, 1);
    assert.match(drifted.out.join("\n"), /^missing\tword-check\tinstalled but not wired/m);
    assert.deepEqual(run(root, dir, "copy", "--scope", "local").json(), [{ entry: "word-check", status: "refreshed" }]);
    assert.equal(run(root, dir, "verify").code, 0);
  });

  test("plain shared: a git add that fails reports stage-failed and exits 1", () => {
    const root = plugin();
    const dir = repo();
    writeFileSync(path.join(dir, ".git", "index.lock"), "");
    const copied = run(root, dir, "copy", "--scope", "shared");
    assert.equal(copied.code, 1);
    assert.deepEqual(copied.json(), [{ entry: "word-check", status: "stage-failed" }]);
  });

  test("plain shared plus a local entry: it lands in .githooks/local/, excluded, and the shared dispatcher runs it", () => {
    const root = plugin();
    const dir = repo();
    git(dir, ["config", "core.hooksPath", ".githooks"]);
    const planned = run(root, dir, "plan", "--scope", "local").json();
    assert.deepEqual(planned.decisions.find((d) => d.kind === "exclude"), {
      kind: "exclude",
      file: path.join(dir, ".git", "info", "exclude"),
      line: "/.githooks/local/",
    });
    run(root, dir, "copy", "--scope", "local");
    assert.ok(existsSync(path.join(dir, ".githooks", "local", "demo-checks", "word-check.sh")));
    assert.ok(existsSync(path.join(dir, ".githooks", "local", "pre-commit.d", "demo-checks.word-check")));
    writeFileSync(path.join(dir, ".git", "info", "exclude"), "/.githooks/local/\n");
    assert.ok(!kinds(run(root, dir, "plan", "--scope", "local").json()).includes("exclude"));
    assert.equal(git(dir, ["status", "--porcelain", "--untracked-files=all", ".githooks/local"]).stdout, "");
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

  test("plain: a dispatcher an earlier release wrote is replaced rather than refused", () => {
    assert.ok(PRIOR_DISPATCHERS.some((prior) => prior.includes('feed bash "$base/$rel"')), "the release that ran entries under bash");
    for (const prior of PRIOR_DISPATCHERS) {
      const root = plugin();
      const dir = repo();
      const hook = path.join(dir, ".git", "hooks", "pre-commit");
      writeFileSync(hook, prior);
      chmodSync(hook, 0o755);
      const planned = kinds(run(root, dir, "plan", "--scope", "local").json());
      assert.ok(!planned.includes("modified") && !planned.includes("foreign-hook"), planned.join(", "));
      assert.deepEqual(run(root, dir, "copy", "--scope", "local").json(), [{ entry: "word-check", status: "installed" }]);
      assert.equal(readFileSync(hook, "utf8"), DISPATCHER);
    }
  });

  test("plain: an entry an earlier release installed, with a bash first line, still runs by it", () => {
    const root = plugin();
    const dir = repo();
    run(root, dir, "copy", "--scope", "local");
    const copy = path.join(dir, ".git", "hooks", "demo-checks", "word-check.sh");
    writeFileSync(copy, "#!/usr/bin/env bash\n[[ -n x ]] && echo old-entry-ran >&2\nexit 1\n");
    chmodSync(copy, 0o755);
    stageBad(dir);
    const r = commit(dir);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /old-entry-ran/);
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
      "pre-commit:\n  jobs:\n    - name: demo-checks-word-check\n      run: sh .githooks/demo-checks/word-check.sh",
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
    assert.match(config.snippet, /run: sh \.git\/hooks\/demo-checks\/word-check\.sh$/);
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

  test("husky: --manager plain at local scope finds .husky/_ owned and writes nothing", () => {
    const root = plugin();
    const dir = huskyRepo();
    const before = tree(path.join(dir, ".husky", "_"));
    const owned = { kind: "hooks-path-owned", hooksPath: ".husky/_", dir: path.join(dir, ".husky", "_") };
    const planned = run(root, dir, "plan", "--scope", "local", "--manager", "plain").json();
    assert.deepEqual(planned.actions, []);
    assert.deepEqual(planned.decisions, [owned]);
    const copied = run(root, dir, "copy", "--scope", "local", "--manager", "plain");
    assert.equal(copied.code, 1);
    assert.deepEqual(copied.json(), { installed: [], decisions: [owned] });
    assert.deepEqual(tree(path.join(dir, ".husky", "_")), before, "nothing under .husky/_ is added, removed or changed");
    assert.ok(before.length >= 2, "the snapshot saw the husky files");
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
      snippet: "sh .githooks/demo-checks/word-check.sh",
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

  // Fixed fixture bytes; each expected hash is a literal from
  // `printf '<script>\0<lib>[\0<asset>]' | sha256sum`, the composition the
  // contract documents (LF-normalized script, NUL, lib, then NUL and each asset).
  function stampFixture(assets) {
    const root = plugin([{ name: "word-check", event: "pre-commit", script: "word-check.sh", tools: [], rewrites: false, assets }]);
    writeFileSync(path.join(root, "git-hooks", "word-check.sh"), "#!/usr/bin/env bash\r\necho hi\r\n");
    writeFileSync(path.join(root, "lib", "git-hooks", "check-lib.sh"), "# lib\n");
    mkdirSync(path.join(root, "config"));
    writeFileSync(path.join(root, "config", "x.toml"), "x = 1\n");
    const dir = repo();
    run(root, dir, "copy", "--scope", "local");
    return readFileSync(path.join(dir, ".git", "hooks", "demo-checks", "word-check.sh"), "utf8");
  }

  test("the stamp is line 2 and hashes the LF-normalized script, a NUL, then the check lib", () => {
    const copy = stampFixture(undefined);
    assert.equal(
      copy,
      "#!/usr/bin/env bash\n# demo-checks word-check sha256:0ba1c5cebb1daa1c8161b9bac5810654b5267aa582f9ebbf7c4c1451d8526ef8\necho hi\n",
    );
    assert.equal(readStamp(copy).body, "#!/usr/bin/env bash\necho hi\n");
  });

  test("an asset joins the stamp after a NUL", () => {
    const copy = stampFixture(["config/x.toml"]);
    assert.equal(
      copy.split("\n")[1],
      "# demo-checks word-check sha256:bd5fab36861d04b4bf00f755b20818edcd02c43c85c585dc1acdb5ee2ca1ec2b",
    );
  });

  test("assets: copied beside the script, and a changed asset reports stale", () => {
    const root = plugin([
      { name: "word-check", event: "pre-commit", script: "word-check.sh", tools: ["grep"], rewrites: false, assets: ["config/words.toml"] },
    ]);
    mkdirSync(path.join(root, "config"));
    writeFileSync(path.join(root, "config", "words.toml"), "first\n");
    const dir = repo();
    run(root, dir, "copy", "--scope", "local");
    const installedAsset = path.join(dir, ".git", "hooks", "demo-checks", "words.toml");
    assert.equal(readFileSync(installedAsset, "utf8"), "first\n");
    assert.equal(run(root, dir, "verify").out[0], "ok\tword-check");
    writeFileSync(path.join(root, "config", "words.toml"), "second\n");
    assert.match(run(root, dir, "verify").out[0], /^stale\tword-check\t/);
    assert.equal(run(root, dir, "copy", "--scope", "local").json()[0].status, "refreshed");
    assert.equal(readFileSync(installedAsset, "utf8"), "second\n");
    writeFileSync(installedAsset, "edited here\n");
    assert.match(run(root, dir, "verify").out[0], /^modified\tword-check\t/, "an edited installed asset is a local modification");
  });

  test("assets must be plugin-relative with distinct base names", () => {
    const base = { name: "a", event: "pre-commit", script: "a.sh", tools: [], rewrites: false };
    assert.deepEqual(validateEntries({ entries: [{ ...base, assets: ["../x"] }] }), ["entries[0].assets must be relative paths inside the plugin"]);
    assert.deepEqual(validateEntries({ entries: [{ ...base, assets: ["a/x", "b/x"] }] }), [
      "entries[0].assets need distinct base names other than check-lib.sh",
    ]);
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

  // withGlobal(fn) runs fn against a fresh, empty global git config file.
  function withGlobal(fn) {
    const saved = process.env.GIT_CONFIG_GLOBAL;
    const file = path.join(work, `global${++counter}`);
    process.env.GIT_CONFIG_GLOBAL = file;
    try {
      return fn((args) => git(work, ["config", "--file", file, ...args]));
    } finally {
      process.env.GIT_CONFIG_GLOBAL = saved;
    }
  }
  const missingLine = (entry) => `demo-checks: git hook ${entry} missing; run /demo-checks:setup apply install-git-hooks`;
  const twoEntries = () =>
    plugin([
      { name: "word-check", event: "pre-commit", script: "word-check.sh", tools: [], rewrites: false },
      { name: "word-push", event: "pre-push", script: "word-check.sh", tools: [], rewrites: false },
    ]);

  test("decline --global: written to global config, silences every clone, --undo clears it", () =>
    withGlobal((globalConfig) => {
      const root = plugin();
      const first = repo();
      const second = repo();
      assert.equal(run(root, first, "decline", "--entry", "word-check", "--global").code, 0);
      assert.equal(globalConfig(["--get", "checks.demo-checks.word-check.declined"]).stdout.trim(), "true");
      assert.equal(git(first, ["config", "--local", "--get", "checks.demo-checks.word-check.declined"]).status, 1);
      assert.deepEqual(run(root, second, "verify", "--quiet").out, []);
      assert.equal(run(root, second, "verify").out[0], "declined\tword-check");
      assert.equal(run(root, first, "decline", "--entry", "word-check", "--global", "--undo").code, 0);
      assert.deepEqual(run(root, second, "verify", "--quiet").out, [missingLine("word-check")]);
    }));

  test("a local false overrides a global true for the same entry", () =>
    withGlobal((globalConfig) => {
      const root = plugin();
      const dir = repo();
      globalConfig(["checks.demo-checks.word-check.declined", "true"]);
      git(dir, ["config", "--local", "checks.demo-checks.word-check.declined", "false"]);
      assert.deepEqual(run(root, dir, "verify", "--quiet").out, [missingLine("word-check")]);
    }));

  test("master key: declines every entry; a per-entry false opts one back in", () =>
    withGlobal((globalConfig) => {
      const root = twoEntries();
      const dir = repo();
      globalConfig(["checks.git-hooks.declined", "true"]);
      assert.deepEqual(run(root, dir, "verify", "--quiet").out, []);
      assert.deepEqual(run(root, dir, "verify").out, ["declined\tword-check", "declined\tword-push"]);
      git(dir, ["config", "--local", "checks.demo-checks.word-push.declined", "false"]);
      assert.deepEqual(run(root, dir, "verify", "--quiet").out, [missingLine("word-push")]);
    }));

  test("a non-boolean entry value reads as not declined, even under the master key", () =>
    withGlobal((globalConfig) => {
      const root = plugin();
      const dir = repo();
      globalConfig(["checks.git-hooks.declined", "true"]);
      git(dir, ["config", "--local", "checks.demo-checks.word-check.declined", "maybe"]);
      assert.deepEqual(run(root, dir, "verify", "--quiet").out, [missingLine("word-check")]);
    }));

  test("decline --global --undo fails when the global config cannot be written", { skip: !posixHost || process.getuid?.() === 0 }, () => {
    const saved = process.env.GIT_CONFIG_GLOBAL;
    const locked = path.join(work, `locked${++counter}`);
    mkdirSync(locked);
    const file = path.join(locked, "gitconfig");
    process.env.GIT_CONFIG_GLOBAL = file;
    try {
      git(work, ["config", "--file", file, "checks.demo-checks.word-check.declined", "true"]);
      chmodSync(locked, 0o555);
      const root = plugin();
      const dir = repo();
      assert.equal(run(root, dir, "decline", "--entry", "word-check", "--global", "--undo").code, 2);
      chmodSync(locked, 0o755);
      assert.equal(run(root, dir, "decline", "--entry", "word-check", "--global", "--undo").code, 0);
      assert.equal(run(root, dir, "decline", "--entry", "word-check", "--global", "--undo").code, 0);
    } finally {
      chmodSync(locked, 0o755);
      process.env.GIT_CONFIG_GLOBAL = saved;
    }
  });

  test("copy over a master decline opts the installed entry back in", () =>
    withGlobal((globalConfig) => {
      const root = plugin();
      const dir = repo();
      globalConfig(["checks.git-hooks.declined", "true"]);
      run(root, dir, "copy", "--scope", "local");
      assert.equal(git(dir, ["config", "--local", "--get", "checks.demo-checks.word-check.declined"]).stdout.trim(), "false");
      assert.equal(run(root, dir, "verify").out[0], "ok\tword-check");
    }));

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

// A plugin whose entries.json names a lefthook remote: the consumer's lefthook
// config carries one `remotes:` entry and the installer writes nothing.
const REMOTE = {
  git_url: "https://example.invalid/demo/checks-repo",
  ref: "main",
  config: "plugins/demo-checks/git-hooks/lefthook-remote.yml",
};
const REMOTE_SNIPPET = [
  "remotes:",
  "  - git_url: https://example.invalid/demo/checks-repo",
  "    ref: main",
  "    refetch_frequency: 24h",
  "    configs:",
  "      - plugins/demo-checks/git-hooks/lefthook-remote.yml",
].join("\n");

describe("remote", () => {
  const remotePlugin = () => plugin(undefined, { remote: REMOTE });
  // What `lefthook install` leaves behind: the event hook it writes and the
  // fetched copy under <git-path info>/lefthook-remotes/<repository name>-<ref>/.
  function fetched(dir) {
    writeFileSync(path.join(dir, ".git", "hooks", "pre-commit"), "#!/bin/sh\ncall_lefthook run pre-commit\n");
    const config = path.join(dir, ".git", "info", "lefthook-remotes", "checks-repo-main", REMOTE.config);
    mkdirSync(path.dirname(config), { recursive: true });
    writeFileSync(config, "pre-commit:\n");
  }

  test("a malformed remote block is rejected, a well-formed one passes", () => {
    const entries = [{ name: "word-check", event: "pre-commit", script: "word-check.sh", tools: [], rewrites: false }];
    assert.deepEqual(validateEntries({ entries, remote: REMOTE }), []);
    assert.deepEqual(validateEntries({ entries, remote: { git_url: "ftp://x", ref: "-x", config: "../up.yml" } }), [
      "remote.git_url must be an https or ssh git URL",
      "remote.ref must be a branch or tag name",
      "remote.config must be a relative .yml path inside the remote repository",
    ]);
  });

  test("plan returns the remotes: entry and lefthook install, and writes nothing", () => {
    const root = remotePlugin();
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), "# project hooks\n");
    const before = tree(dir);
    const planned = run(root, dir, "plan", "--scope", "remote").json();
    assert.equal(planned.manager, "lefthook");
    assert.deepEqual(planned.actions, []);
    assert.deepEqual(planned.decisions.find((d) => d.kind === "lefthook-config"), {
      kind: "lefthook-config",
      file: "lefthook.yml",
      snippet: REMOTE_SNIPPET,
    });
    assert.ok(kinds(planned).includes("lefthook-install"));
    assert.deepEqual(tree(dir), before);
  });

  test("a repository with no hook manager is planned for lefthook, creating lefthook.yml", () => {
    const planned = run(remotePlugin(), repo(), "plan", "--scope", "remote").json();
    assert.equal(planned.manager, "lefthook");
    assert.equal(planned.decisions.find((d) => d.kind === "lefthook-config").file, "lefthook.yml");
  });

  test("husky is a remote-needs-lefthook decision", () => {
    const dir = repo();
    mkdirSync(path.join(dir, ".husky"));
    const planned = run(remotePlugin(), dir, "plan", "--scope", "remote").json();
    assert.deepEqual(kinds(planned), ["remote-needs-lefthook"]);
  });

  test("a lefthook config with its own source_dir is a remote-source-dir decision; the default passes", () => {
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), "source_dir: .hooks/\n");
    const planned = run(remotePlugin(), dir, "plan", "--scope", "remote").json();
    assert.deepEqual(planned.decisions, [{ kind: "remote-source-dir", file: "lefthook.yml", sourceDir: ".hooks/" }]);
    writeFileSync(path.join(dir, "lefthook.yml"), "source_dir: ./.lefthook/\n");
    assert.ok(kinds(run(remotePlugin(), dir, "plan", "--scope", "remote").json()).includes("lefthook-config"));
  });

  test("a source_dir in a TOML or JSON lefthook config is a remote-source-dir decision", () => {
    for (const [file, text] of [["lefthook.toml", 'source_dir = ".hooks/"\n'], ["lefthook.json", '{"source_dir": ".hooks/"}']]) {
      const dir = repo();
      writeFileSync(path.join(dir, file), text);
      assert.deepEqual(run(remotePlugin(), dir, "plan", "--scope", "remote").json().decisions, [
        { kind: "remote-source-dir", file, sourceDir: ".hooks/" },
      ]);
    }
  });

  test("verify is missing until lefthook installed the hook and fetched the remote, then ok, and the probe is silent", () => {
    const root = remotePlugin();
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), `${REMOTE_SNIPPET}\n`);
    const unfetched = run(root, dir, "verify");
    assert.equal(unfetched.code, 1);
    assert.deepEqual(unfetched.out, [
      "missing\tword-check\tlefthook remote not fetched or hook not installed; run lefthook install",
    ]);
    fetched(dir);
    const ok = run(root, dir, "verify");
    assert.equal(ok.code, 0);
    assert.deepEqual(ok.out, ["ok\tword-check"]);
    assert.deepEqual(run(root, dir, "plan", "--scope", "remote").json().decisions.filter((d) => d.kind.startsWith("lefthook")), []);
    const out = [];
    const env = { ...baseEnv, CLAUDE_PROJECT_DIR: dir };
    prerequisites(["probe", root], { env, cwd: dir, stdin: () => "{}" }, { stdout: (s) => out.push(s), stderr: () => {} });
    assert.deepEqual(out, []);
  });

  test("an entry on another ref is a lefthook-config decision naming it, and verify says to set the ref", () => {
    const root = remotePlugin();
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), `${REMOTE_SNIPPET.replace("ref: main", "ref: develop")}\n`);
    fetched(dir);
    const config = run(root, dir, "plan", "--scope", "remote").json().decisions.find((d) => d.kind === "lefthook-config");
    assert.equal(config.foundRef, "develop");
    const verify = run(root, dir, "verify");
    assert.equal(verify.code, 1);
    assert.deepEqual(verify.out, [
      'missing\tword-check\tlefthook remote ref is "develop", not main; set ref: main',
    ]);
  });

  test("another host, or a comment naming the URL, is not the remote", () => {
    const root = remotePlugin();
    const dir = repo();
    fetched(dir);
    const other = REMOTE_SNIPPET.replace("https://example.invalid/", "https://evil.invalid/");
    for (const text of [other, `# ${REMOTE.git_url} ${REMOTE.config}`]) {
      writeFileSync(path.join(dir, "lefthook.yml"), `${text}\n`);
      assert.ok(kinds(run(root, dir, "plan", "--scope", "remote").json()).includes("lefthook-config"));
      assert.notDeepEqual(run(root, dir, "verify").out, ["ok\tword-check"]);
    }
  });

  test("the remote verifies ok in any key order, and in TOML and JSON configs", () => {
    const root = remotePlugin();
    const { git_url: url, ref, config } = REMOTE;
    const shapes = {
      "lefthook.yml": `remotes: # shared\n- ref: "${ref}"\n  configs: [x]\n  configs:\n    - ${config}\n  git_url: ${url}\n`,
      ".lefthook.yml": `remotes:\n  - git_url: ${url}\n    # ref: develop\n    ref: ${ref}\n    configs: [other.yml, "${config}"]\n`,
      ".config/lefthook.yml": `remotes:\n  - {git_url: ${url}, ref: ${ref}, configs: [${config}]}\n`,
      "lefthook.toml": `[[remotes]]\ngit_url = "${url}"\nref = "${ref}"\nconfigs = ["${config}"]\n\n[pre-commit]\n`,
      "lefthook.json": JSON.stringify({ remotes: [{ git_url: url, ref, configs: [config] }] }),
    };
    for (const [file, text] of Object.entries(shapes)) {
      const dir = repo();
      mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
      writeFileSync(path.join(dir, file), text);
      fetched(dir);
      assert.deepEqual(run(root, dir, "verify").out, ["ok\tword-check"], file);
      assert.ok(!kinds(run(root, dir, "plan", "--scope", "remote").json()).includes("lefthook-config"), file);
    }
  });

  test("a column-0 comment between remotes entries hides no entry", () => {
    const root = remotePlugin();
    const dir = repo();
    const ours = REMOTE_SNIPPET.replace(/^remotes:\n/, "");
    writeFileSync(path.join(dir, "lefthook.yml"), `remotes:\n  - git_url: https://example.invalid/other\n    configs: [x.yml]\n# guardrails hooks\n${ours}\n`);
    fetched(dir);
    assert.deepEqual(run(root, dir, "verify").out, ["ok\tword-check"]);
    assert.ok(!kinds(run(root, dir, "plan", "--scope", "remote").json()).includes("lefthook-config"));
  });

  test("a key named in a trailing comment does not shadow the real key", () => {
    const root = remotePlugin();
    const dir = repo();
    const text = REMOTE_SNIPPET.replace(`git_url: ${REMOTE.git_url}`, `git_url: ${REMOTE.git_url}  # pinned, ref: develop`);
    writeFileSync(path.join(dir, "lefthook.yml"), `${text}\n`);
    fetched(dir);
    assert.deepEqual(run(root, dir, "verify").out, ["ok\tword-check"]);
  });

  test("a fetched copy under another directory name still verifies", () => {
    const root = remotePlugin();
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), `${REMOTE_SNIPPET}\n`);
    writeFileSync(path.join(dir, ".git", "hooks", "pre-commit"), "#!/bin/sh\ncall_lefthook run pre-commit\n");
    const config = path.join(dir, ".git", "info", "lefthook-remotes", "checks-repo-main-0123abc", REMOTE.config);
    mkdirSync(path.dirname(config), { recursive: true });
    writeFileSync(config, "pre-commit:\n");
    assert.deepEqual(run(root, dir, "verify").out, ["ok\tword-check"]);
  });

  test("a fetched copy of another ref, or of a repository whose name extends this one, stays missing", () => {
    const root = remotePlugin();
    for (const name of ["checks-repo-develop", "checks-repo-extra-main"]) {
      const dir = repo();
      writeFileSync(path.join(dir, "lefthook.yml"), `${REMOTE_SNIPPET}\n`);
      writeFileSync(path.join(dir, ".git", "hooks", "pre-commit"), "#!/bin/sh\ncall_lefthook run pre-commit\n");
      const config = path.join(dir, ".git", "info", "lefthook-remotes", name, REMOTE.config);
      mkdirSync(path.dirname(config), { recursive: true });
      writeFileSync(config, "pre-commit:\n");
      assert.equal(run(root, dir, "verify").code, 1, name);
    }
  });

  test("a quoted job name and a commands: key are both leftover shared jobs", () => {
    const root = remotePlugin();
    const dir = repo();
    for (const config of ['pre-commit:\n  jobs:\n    - name: "demo-checks-word-check"\n', "pre-commit:\n  commands:\n    demo-checks-word-check:\n      run: x\n"]) {
      writeFileSync(path.join(dir, "lefthook.yml"), config);
      const migrate = run(root, dir, "plan", "--scope", "remote").json().decisions.find((d) => d.kind === "migrate");
      assert.deepEqual(migrate?.jobs, ["demo-checks-word-check"]);
    }
  });

  test("local copies are a migrate decision in a remote plan", () => {
    const root = remotePlugin();
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), "# project hooks\n");
    run(root, dir, "copy", "--scope", "local");
    const migrate = run(root, dir, "plan", "--scope", "remote").json().decisions.find((d) => d.kind === "migrate" && d.from === "local");
    assert.equal(migrate?.files.length, 1);
  });

  test("shared copies and their lefthook job are a migrate decision", () => {
    const root = remotePlugin();
    const dir = repo();
    writeFileSync(path.join(dir, "lefthook.yml"), "# project hooks\n");
    const shared = run(root, dir, "plan", "--scope", "shared").json().decisions.find((d) => d.kind === "lefthook-config");
    writeFileSync(path.join(dir, "lefthook.yml"), `${shared.snippet}\n`);
    run(root, dir, "copy", "--scope", "shared");
    const migrate = run(root, dir, "plan", "--scope", "remote").json().decisions.find((d) => d.kind === "migrate");
    assert.deepEqual(migrate, {
      kind: "migrate",
      from: "shared",
      dir: ".githooks/demo-checks",
      files: [path.join(dir, ".githooks", "demo-checks", "word-check.sh")],
      jobs: ["demo-checks-word-check"],
    });
  });

  test("copy --scope remote, and plan --scope remote for a plugin naming no remote, are usage errors", () => {
    const dir = repo();
    assert.equal(run(remotePlugin(), dir, "copy", "--scope", "remote").code, 2);
    const plain = run(plugin(), dir, "plan", "--scope", "remote");
    assert.equal(plain.code, 2);
    assert.match(plain.err.join("\n"), /names no lefthook remote/);
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

// A cloned repository's contents are untrusted: a committed symlink must not
// steer a write outside the work tree, a device or huge file must not be read
// whole, and a hook that merely mentions the dispatcher's sentinel is not ours.
describe("untrusted repository contents", { skip: !posixHost }, () => {
  test("copy refuses every symlinked target, writes nothing through it, and plan names it", () => {
    const root = plugin();
    const dir = repo();
    const outside = mkdtempSync(path.join(work, "outside-"));
    const victim = path.join(outside, "victim.txt");
    const victimLib = path.join(outside, "victim-lib.txt");
    writeFileSync(victim, "keep me\n");
    writeFileSync(victimLib, "keep me too\n");
    const hooks = path.join(dir, ".githooks");
    mkdirSync(path.join(hooks, "pre-commit.d"), { recursive: true });
    mkdirSync(path.join(hooks, "demo-checks"));
    symlinkSync(victim, path.join(hooks, "pre-commit.d", "demo-checks.word-check"));
    symlinkSync(victimLib, path.join(hooks, "demo-checks", "check-lib.sh"));
    symlinkSync(path.join(outside, "created"), path.join(hooks, "pre-commit"));
    const planned = run(root, dir, "plan", "--scope", "shared").json();
    assert.deepEqual(planned.decisions.find((d) => d.kind === "unsafe-path"), {
      kind: "unsafe-path",
      entry: "word-check",
      file: path.join(hooks, "demo-checks", "check-lib.sh"),
    });
    const copied = run(root, dir, "copy", "--scope", "shared");
    assert.equal(copied.code, 1);
    assert.deepEqual(copied.json(), [{ entry: "word-check", status: "unsafe-path" }]);
    assert.equal(readFileSync(victim, "utf8"), "keep me\n");
    assert.equal(readFileSync(victimLib, "utf8"), "keep me too\n");
    assert.ok(!existsSync(path.join(outside, "created")), "a dangling link's target is never created");
    assert.ok(!existsSync(path.join(hooks, "demo-checks", "word-check.sh")), "nothing is written once any target is unsafe");
    assert.ok(!existsSync(path.join(dir, ".gitattributes")));
  });

  test("copy refuses a symlinked directory on the way to the copies", () => {
    const root = plugin();
    const dir = repo();
    const outside = mkdtempSync(path.join(work, "outside-"));
    symlinkSync(outside, path.join(dir, ".githooks"));
    const copied = run(root, dir, "copy", "--scope", "shared");
    assert.deepEqual(copied.json(), [{ entry: "word-check", status: "unsafe-path" }]);
    assert.deepEqual(readdirSync(outside), []);
  });

  // Run in a child process: a reader with no bound would fill memory here.
  function boundedRun(dir, root, ...args) {
    return spawnSync(process.execPath, [path.join(here, "install.mjs"), ...args, "--repo", dir, "--plugin-root", root], {
      encoding: "utf8",
      env: baseEnv,
      timeout: 15000,
    });
  }

  test("a copy or package.json linked to /dev/zero is read as absent, within bounded time", { skip: !existsSync("/dev/zero") }, () => {
    const root = plugin();
    const dir = repo();
    symlinkSync("/dev/zero", path.join(dir, "package.json"));
    mkdirSync(path.join(dir, ".git", "hooks", "demo-checks"), { recursive: true });
    symlinkSync("/dev/zero", path.join(dir, ".git", "hooks", "demo-checks", "word-check.sh"));
    const detected = boundedRun(dir, root, "detect");
    assert.equal(detected.status, 0);
    assert.deepEqual(JSON.parse(detected.stdout), { manager: "plain", evidence: [] });
    const verified = boundedRun(dir, root, "verify", "--quiet");
    assert.equal(verified.status, 0);
    assert.equal(verified.stdout, "demo-checks: git hook word-check missing; run /demo-checks:setup apply install-git-hooks\n");
  });

  test("an oversize installed copy is not read and reports missing", () => {
    const root = plugin();
    const dir = repo();
    run(root, dir, "copy", "--scope", "local");
    const copy = path.join(dir, ".git", "hooks", "demo-checks", "word-check.sh");
    writeFileSync(copy, `${readFileSync(copy, "utf8")}#${"x".repeat(1024 * 1024)}\n`);
    assert.match(run(root, dir, "verify").out[0], /^missing\tword-check\t/);
  });

  test("a hook holding the sentinel but not the dispatcher is modified: copy refuses it, --force replaces it", () => {
    const root = plugin();
    const dir = repo();
    const hook = path.join(dir, ".git", "hooks", "pre-commit");
    const planted = `#!/bin/sh\n# checks-dispatcher v1\necho planted >&2\n`;
    writeFileSync(hook, planted);
    assert.deepEqual(
      run(root, dir, "plan", "--scope", "local").json().decisions.find((d) => d.kind === "modified"),
      { kind: "modified", entry: "word-check", file: hook },
    );
    const refused = run(root, dir, "copy", "--scope", "local");
    assert.equal(refused.code, 1);
    assert.deepEqual(refused.json(), [{ entry: "word-check", status: "refused" }]);
    assert.equal(readFileSync(hook, "utf8"), planted);
    assert.equal(run(root, dir, "copy", "--scope", "local", "--force").json()[0].status, "installed");
    assert.equal(readFileSync(hook, "utf8"), DISPATCHER);
    assert.equal(run(root, dir, "verify").code, 0);
  });
});

test("installed scripts are executable", { skip: !posixHost }, () => {
  const root = plugin();
  const dir = repo();
  run(root, dir, "copy", "--scope", "local");
  assert.ok(statSync(path.join(dir, ".git", "hooks", "pre-commit")).mode & 0o100);
  assert.ok(statSync(path.join(dir, ".git", "hooks", "demo-checks", "word-check.sh")).mode & 0o100);
});
