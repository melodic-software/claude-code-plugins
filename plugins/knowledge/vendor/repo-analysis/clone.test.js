import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, describe, it } from "node:test";
import { pathToFileURL } from "node:url";

import { runCloneCli } from "./clone-cli.js";
import { liveCloneGroupCount, shallowCloneGitHubRepo } from "./clone.js";

const sandboxes = [];
after(() => {
  for (const dir of sandboxes) fs.rmSync(dir, { recursive: true, force: true });
});

function sandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "repo-analysis-clone-"));
  sandboxes.push(dir);
  return dir;
}

const git = (cwd, ...args) =>
  execFileSync(
    "git",
    ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false", ...args],
    { cwd, encoding: "utf8" },
  ).trim();

/** A local repository with two commits; returns its file URL and head commit. */
function fixtureRepo() {
  const dir = sandbox();
  git(dir, "init", "-q");
  fs.writeFileSync(path.join(dir, "a.txt"), "first\n");
  git(dir, "add", "a.txt");
  git(dir, "commit", "-q", "-m", "first");
  fs.writeFileSync(path.join(dir, "b.txt"), "second\n");
  git(dir, "add", "b.txt");
  git(dir, "commit", "-q", "-m", "second");
  return { url: pathToFileURL(dir).href, head: git(dir, "rev-parse", "HEAD") };
}

describe("shallowCloneGitHubRepo", () => {
  it("clones only the head commit of the default branch", async () => {
    const { url, head } = fixtureRepo();
    const dest = path.join(sandbox(), "clone");
    assert.equal(await shallowCloneGitHubRepo(url, dest), true);
    assert.equal(git(dest, "rev-parse", "HEAD"), head);
    assert.equal(git(dest, "rev-list", "--count", "HEAD"), "1");
    assert.equal(fs.readFileSync(path.join(dest, "b.txt"), "utf8"), "second\n");
  });

  it("resolves false for a repository that does not exist", async () => {
    const missing = pathToFileURL(path.join(sandbox(), "missing")).href;
    assert.equal(await shallowCloneGitHubRepo(missing, path.join(sandbox(), "clone")), false);
  });

  it("runs git with no credential helper, no prompt, no LFS download and a throwaway home", async () => {
    let call;
    const spawnFn = (command, args, options) => {
      call = { command, args, home: options.env.HOME, env: options.env, homeExisted: fs.existsSync(options.env.HOME) };
      return { pid: undefined, on: (event, callback) => event === "close" && callback(0) };
    };
    await shallowCloneGitHubRepo("https://github.com/owner/repo", "-dest", spawnFn);
    assert.equal(call.command, "git");
    assert.deepEqual(call.args, [
      "-c",
      "credential.helper=",
      "clone",
      "--depth",
      "1",
      "--single-branch",
      "--",
      "https://github.com/owner/repo",
      "-dest",
    ]);
    assert.notEqual(call.home, os.homedir());
    assert.equal(call.homeExisted, true);
    assert.equal(fs.existsSync(call.home), false);
    assert.equal(call.env.USERPROFILE, call.home);
    assert.equal(call.env.XDG_CONFIG_HOME, call.home);
    assert.equal(call.env.GIT_ASKPASS, "");
    assert.equal(call.env.SSH_ASKPASS, "");
    assert.equal(call.env.GIT_TERMINAL_PROMPT, "0");
    assert.equal(call.env.GIT_LFS_SKIP_SMUDGE, "1");
  });

  describe("with inheritGitEnvironment", () => {
    /** Run `body` with HOME pointing at a home whose git config rewrites `alias` to `target`. */
    async function withAliasHome(alias, target, body) {
      const home = sandbox();
      fs.writeFileSync(path.join(home, ".gitconfig"), `[url "${target}"]\n\tinsteadOf = ${alias}\n`);
      const saved = { HOME: process.env.HOME, XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME, GIT_CONFIG_GLOBAL: process.env.GIT_CONFIG_GLOBAL };
      process.env.HOME = home;
      delete process.env.XDG_CONFIG_HOME;
      delete process.env.GIT_CONFIG_GLOBAL;
      try {
        return await body();
      } finally {
        for (const [key, value] of Object.entries(saved)) {
          if (value === undefined) delete process.env[key];
          else process.env[key] = value;
        }
      }
    }

    it("reads the user's git config, which the default hides", async () => {
      const { url, head } = fixtureRepo();
      const alias = pathToFileURL(path.join(sandbox(), "alias")).href;
      const inherited = path.join(sandbox(), "clone");
      const hardened = path.join(sandbox(), "clone");
      const results = await withAliasHome(alias, url, async () => [
        await shallowCloneGitHubRepo(alias, inherited, undefined, { inheritGitEnvironment: true }),
        await shallowCloneGitHubRepo(alias, hardened),
      ]);
      assert.deepEqual(results, [true, false]);
      assert.equal(git(inherited, "rev-parse", "HEAD"), head);
      assert.equal(git(inherited, "rev-list", "--count", "HEAD"), "1");
    });

    it("passes git's stderr to onStderr when the clone fails", async () => {
      const missing = path.join(sandbox(), "missing");
      let stderr;
      const ok = await shallowCloneGitHubRepo(pathToFileURL(missing).href, path.join(sandbox(), "clone"), undefined, {
        inheritGitEnvironment: true,
        onStderr: (text) => (stderr = text),
      });
      assert.equal(ok, false);
      assert.match(stderr, /^fatal: /m);
      assert.ok(stderr.includes(missing), stderr);
    });

    it("keeps the credential helper, prompts and process environment, where the default blanks the helper", async () => {
      const calls = [];
      const spawnFn = (command, args, options) => {
        calls.push({ args, options });
        return { pid: undefined, on: (event, callback) => event === "close" && callback(0) };
      };
      await shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", spawnFn, { inheritGitEnvironment: true });
      await shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", spawnFn);
      const [inherited, hardened] = calls;
      assert.deepEqual(inherited.args, ["clone", "--depth", "1", "--single-branch", "--", "https://github.com/owner/repo", "dest"]);
      assert.equal(inherited.options.env, process.env);
      assert.equal(inherited.options.detached, false);
      assert.deepEqual(hardened.args.slice(0, 2), ["-c", "credential.helper="]);
      assert.equal(hardened.options.env.GIT_TERMINAL_PROMPT, "0");
    });
  });

  it("kills a clone that outlives the timeout and counts it failed", async () => {
    const hanging = (_command, _args, options) =>
      spawn(process.execPath, ["-e", "setTimeout(() => {}, 60000)"], options);
    const started = Date.now();
    assert.equal(await shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", hanging, { timeoutMs: 200 }), false);
    assert.ok(Date.now() - started < 30_000);
    assert.equal(liveCloneGroupCount(), 0);
  });
});

describe("clone-cli", () => {
  const capture = () => {
    const io = { err: "" };
    io.stderr = { write: (text) => (io.err += text) };
    return io;
  };
  const neverCalled = async () => assert.fail("clone must not run");

  it("rejects missing arguments", async () => {
    const io = capture();
    assert.equal(await runCloneCli(["https://github.com/o/r"], { clone: neverCalled, stderr: io.stderr }), 2);
    assert.match(io.err, /^Usage: node clone-cli\.js/);
  });

  for (const url of ["file:///tmp/repo", "ext::sh -c touch% /tmp/x", "http://github.com/o/r", "not a url"]) {
    it(`refuses a URL that is not https: ${url}`, async () => {
      const io = capture();
      assert.equal(await runCloneCli([url, path.join(sandbox(), "d")], { clone: neverCalled, stderr: io.stderr }), 2);
      assert.match(io.err, /only an https URL is cloned/);
    });
  }

  it("refuses a destination that already holds files", async () => {
    const dest = sandbox();
    fs.writeFileSync(path.join(dest, "x"), "");
    const io = capture();
    assert.equal(await runCloneCli(["https://github.com/o/r", dest], { clone: neverCalled, stderr: io.stderr }), 2);
    assert.match(io.err, /destination is not empty/);
  });

  it("exits 0 on a clone and 1 on a failed one", async () => {
    const dest = path.join(sandbox(), "d");
    /** @type {string[][]} */
    const calls = [];
    const ok = async (url, to) => (calls.push([url, to]), true);
    assert.equal(await runCloneCli(["https://github.com/o/r", dest], { clone: ok, stderr: capture().stderr }), 0);
    assert.deepEqual(calls, [["https://github.com/o/r", dest]]);
    const io = capture();
    assert.equal(await runCloneCli(["https://github.com/o/r", dest], { clone: async () => false, stderr: io.stderr }), 1);
    assert.match(io.err, /the clone of https:\/\/github\.com\/o\/r failed/);
  });
});
