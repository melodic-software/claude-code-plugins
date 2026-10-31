// Run: node --test plugins/knowledge/scripts/work-root.test.mjs
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, before, describe, it } from "node:test";

import { progressKey, workRoot } from "./work-root.mjs";

const CLI = path.join(import.meta.dirname, "work-root.mjs");
const base = realpathSync(mkdtempSync(path.join(os.tmpdir(), "work-root-test-")));
const gitConfig = path.join(base, "gitconfig");
const inherited = Object.fromEntries(
  Object.entries(process.env).filter(
    ([name]) => !["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"].includes(name) && !name.startsWith("GIT_CONFIG"),
  ),
);
const env = {
  ...inherited,
  GIT_CONFIG_GLOBAL: gitConfig,
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CEILING_DIRECTORIES: base,
};

const main = path.join(base, "claude-code-plugins");
const worktree = path.join(base, "api-worktree");
const outside = path.join(base, "loose");

function git(cwd, ...args) {
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", ...args], {
    cwd,
    env,
    stdio: "ignore",
  });
}

function cli(cwd, args, extraEnv = {}) {
  return spawnSync(process.execPath, [CLI, ...args], { cwd, env: { ...env, ...extraEnv }, encoding: "utf8" });
}

/** The base derivation, run as the distill skill text spelled it. */
function baseHash(projectPath) {
  return execFileSync(
    "bash",
    ["-c", 'printf \'%s\' "$1" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8', "_", projectPath],
    { encoding: "utf8" },
  ).trim();
}

before(() => {
  writeFileSync(gitConfig, "");
  mkdirSync(path.join(main, "docs", "deep"), { recursive: true });
  mkdirSync(outside);
  git(main, "init", "-q");
  git(main, "commit", "-q", "--allow-empty", "-m", "seed");
  git(main, "worktree", "add", "-q", worktree);
});

after(() => rmSync(base, { recursive: true, force: true }));

describe("work root", () => {
  it("is the main checkout's top-level from any directory inside it", () => {
    const r = cli(path.join(main, "docs", "deep"), []);
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, `${main}\n`);
  });

  it("is the linked worktree, not the main checkout, inside a worktree", () => {
    assert.equal(cli(worktree, []).stdout, `${worktree}\n`);
  });

  it("is the directory itself outside git", () => {
    const r = cli(outside, []);
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, `${outside}\n`);
  });

  it("treats empty, '.', and an unsubstituted user_config token as the default", () => {
    for (const value of ["", ".", "${user_config.library_dir}"]) {
      assert.equal(cli(worktree, ["--library-dir", value]).stdout, `${worktree}\n`, value);
    }
  });

  it("joins a relative library_dir to the top-level, not the working directory", () => {
    assert.equal(cli(path.join(main, "docs"), ["--library-dir", "corpus/k"]).stdout, `${path.join(main, "corpus", "k")}\n`);
  });

  it("uses an absolute library_dir as given", () => {
    assert.equal(cli(main, ["--library-dir", outside]).stdout, `${outside}\n`);
  });

  it("expands ${NAME} and %NAME% references", () => {
    assert.equal(cli(main, ["--library-dir", "${KC_DIR}/v"], { KC_DIR: outside }).stdout, `${path.join(outside, "v")}\n`);
    assert.equal(cli(main, ["--library-dir", "%KC_DIR%"], { KC_DIR: outside }).stdout, `${outside}\n`);
  });

  it("fails loud on an unset variable and prints no root", () => {
    const r = cli(main, ["--library-dir", "${KC_UNSET_DIR}"], { KC_UNSET_DIR: "" });
    assert.equal(r.status, 1);
    assert.equal(r.stdout, "");
    assert.match(r.stderr, /KC_UNSET_DIR.*unset or empty/);
  });

  it("expands a leading ~ to the home directory", { skip: process.platform === "win32" }, () => {
    assert.equal(workRoot({ libraryDir: "~/corpus", cwd: main, homedir: "/srv/home" }), "/srv/home/corpus");
  });

  it("rejects unknown flags and --progress-key with --library-dir", () => {
    assert.equal(cli(main, ["--nope"]).status, 2);
    assert.equal(cli(main, ["--library-dir"]).status, 2);
    assert.equal(cli(main, ["--progress-key", "--library-dir", "x"]).status, 2);
  });
});

describe("progress key", () => {
  it("matches the base derivation's hand-computed value for a fixed path", () => {
    // printf '%s' /srv/work/api | sha256sum | cut -c1-8 -> 0b860e31
    assert.equal(progressKey("/srv/work/api"), "api-0b860e31");
  });

  it("is byte-identical to the base derivation for the main checkout", () => {
    const r = cli(path.join(main, "docs"), ["--progress-key"]);
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, `claude-code-plugins-${baseHash(main)}\n`);
  });

  it("gives a linked worktree its own key", () => {
    const key = cli(worktree, ["--progress-key"]).stdout;
    assert.equal(key, `api-worktree-${baseHash(worktree)}\n`);
    assert.notEqual(key, cli(main, ["--progress-key"]).stdout);
  });

  it("reduces other characters in the basename to single hyphens", () => {
    assert.match(progressKey("/srv/My_Repo.v2"), /^my-repo-v2-[0-9a-f]{8}$/);
  });
});
