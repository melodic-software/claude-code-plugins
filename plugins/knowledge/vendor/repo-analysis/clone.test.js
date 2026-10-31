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

/** An empty global config, so fixture git never reads the host's identity, signing or rewrites. */
const fixtureConfig = path.join(sandbox(), "gitconfig");
fs.writeFileSync(fixtureConfig, "");
const tmpRoot = os.tmpdir();
/** The host environment without any GIT_* variable, with git config and discovery held to the sandboxes. */
const fixtureEnv = {
  ...Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.toUpperCase().startsWith("GIT_"))),
  GIT_CONFIG_GLOBAL: fixtureConfig,
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CEILING_DIRECTORIES: [tmpRoot, fs.realpathSync(tmpRoot)].join(path.delimiter),
};

const git = (cwd, ...args) =>
  execFileSync(
    "git",
    ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false", ...args],
    { cwd, encoding: "utf8", env: fixtureEnv },
  ).trim();

/** Real git, with file:// let back in so a hardened clone can reach a local fixture. */
const allowFile = (command, args, options) =>
  spawn(command, args, { ...options, env: { ...options.env, GIT_ALLOW_PROTOCOL: "https:file" } });

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
    assert.equal(await shallowCloneGitHubRepo(url, dest, allowFile), true);
    assert.equal(git(dest, "rev-parse", "HEAD"), head);
    assert.equal(git(dest, "rev-list", "--count", "HEAD"), "1");
    assert.equal(fs.readFileSync(path.join(dest, "b.txt"), "utf8"), "second\n");
  });

  it("resolves false for a repository that does not exist", async () => {
    const missing = pathToFileURL(path.join(sandbox(), "missing")).href;
    assert.equal(await shallowCloneGitHubRepo(missing, path.join(sandbox(), "clone"), allowFile), false);
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
      "-c",
      "protocol.allow=never",
      "-c",
      "protocol.https.allow=always",
      "-c",
      "core.symlinks=false",
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
        await shallowCloneGitHubRepo(alias, hardened, allowFile),
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

  describe("with git config passed through the environment", () => {
    /** Run `body` with `vars` set in the parent environment, restoring it after. */
    async function withEnv(vars, body) {
      const saved = Object.fromEntries(Object.keys(vars).map((key) => [key, process.env[key]]));
      Object.assign(process.env, vars);
      try {
        return await body();
      } finally {
        for (const [key, value] of Object.entries(saved)) {
          if (value === undefined) delete process.env[key];
          else process.env[key] = value;
        }
      }
    }

    for (const [label, varsFor] of [
      [
        "GIT_CONFIG_COUNT",
        (alias, url) => ({ GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: `url.${url}.insteadOf`, GIT_CONFIG_VALUE_0: alias }),
      ],
      ["GIT_CONFIG_PARAMETERS", (alias, url) => ({ GIT_CONFIG_PARAMETERS: `'url.${url}.insteadof'='${alias}'` })],
    ]) {
      it(`ignores an insteadOf set through ${label}, which the inherited mode applies`, async () => {
        const { url, head } = fixtureRepo();
        const alias = pathToFileURL(path.join(sandbox(), "alias")).href;
        const inherited = path.join(sandbox(), "clone");
        const hardened = path.join(sandbox(), "clone");
        const results = await withEnv(varsFor(alias, url), async () => [
          await shallowCloneGitHubRepo(alias, inherited, undefined, { inheritGitEnvironment: true }),
          await shallowCloneGitHubRepo(alias, hardened, allowFile),
        ]);
        assert.deepEqual(results, [true, false]);
        assert.equal(git(inherited, "rev-parse", "HEAD"), head);
        assert.equal(fs.existsSync(hardened), false);
      });
    }

    it("drops every environment config variable and points global and system config at an empty file", async () => {
      let env;
      let configText;
      const spawnFn = (_command, _args, options) => {
        env = options.env;
        configText = fs.readFileSync(options.env.GIT_CONFIG_GLOBAL, "utf8");
        return { pid: undefined, on: (event, callback) => event === "close" && callback(0) };
      };
      await withEnv(
        { GIT_CONFIG_PARAMETERS: "'a.b'='c'", GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "a.b", GIT_CONFIG_VALUE_0: "c" },
        () => shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", spawnFn),
      );
      for (const key of ["GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0"]) {
        assert.equal(key in env, false, key);
      }
      assert.equal(configText, "");
      assert.equal(path.dirname(env.GIT_CONFIG_GLOBAL), env.HOME);
      assert.equal(env.GIT_CONFIG_SYSTEM, env.GIT_CONFIG_GLOBAL);
      assert.equal(env.GIT_CONFIG_NOSYSTEM, "1");
    });
  });

  describe("hardened transport and checkout", () => {
    /** Run `body` with `name` set to `value` in the parent environment, restoring it after. */
    async function withVar(name, value, body) {
      const saved = process.env[name];
      process.env[name] = value;
      try {
        return await body();
      } finally {
        if (saved === undefined) delete process.env[name];
        else process.env[name] = saved;
      }
    }

    it("refuses a file:// URL, which the inherited mode clones", async () => {
      const { url, head } = fixtureRepo();
      const hardened = path.join(sandbox(), "clone");
      const inherited = path.join(sandbox(), "clone");
      assert.equal(await shallowCloneGitHubRepo(url, hardened), false);
      assert.equal(fs.existsSync(hardened), false);
      assert.equal(await shallowCloneGitHubRepo(url, inherited, undefined, { inheritGitEnvironment: true }), true);
      assert.equal(git(inherited, "rev-parse", "HEAD"), head);
    });

    it("ignores an inherited GIT_WORK_TREE, which the inherited mode checks out into", async () => {
      const { url } = fixtureRepo();
      const workTree = path.join(sandbox(), "work-tree");
      const hardened = path.join(sandbox(), "clone");
      const inherited = path.join(sandbox(), "clone");
      const results = await withVar("GIT_WORK_TREE", workTree, async () => [
        await shallowCloneGitHubRepo(url, hardened, allowFile),
        await shallowCloneGitHubRepo(url, inherited, undefined, { inheritGitEnvironment: true }),
      ]);
      assert.deepEqual(results, [true, true]);
      assert.equal(fs.readFileSync(path.join(hardened, "b.txt"), "utf8"), "second\n");
      assert.equal(fs.existsSync(path.join(inherited, "b.txt")), false);
      assert.equal(fs.readFileSync(path.join(workTree, "b.txt"), "utf8"), "second\n");
    });

    it("checks a symbolic link out as a regular file holding its target path", async () => {
      const dir = sandbox();
      git(dir, "init", "-q");
      fs.writeFileSync(path.join(dir, "a.txt"), "first\n");
      fs.writeFileSync(path.join(dir, "target"), "a.txt");
      const blob = git(dir, "hash-object", "-w", "target");
      git(dir, "add", "a.txt");
      git(dir, "update-index", "--add", "--cacheinfo", `120000,${blob},link`);
      git(dir, "commit", "-q", "-m", "link");
      const dest = path.join(sandbox(), "clone");
      assert.equal(await shallowCloneGitHubRepo(pathToFileURL(dir).href, dest, allowFile), true);
      const link = fs.lstatSync(path.join(dest, "link"));
      assert.equal(link.isSymbolicLink(), false);
      assert.equal(link.isFile(), true);
      assert.equal(fs.readFileSync(path.join(dest, "link"), "utf8"), "a.txt");
    });

    it("drops inherited GIT_* variables in any case and sets the transport limits", async () => {
      let call;
      const spawnFn = (_command, args, options) => {
        call = { args, env: options.env };
        return { pid: undefined, on: (event, callback) => event === "close" && callback(0) };
      };
      await withVar("Git_Ssl_No_Verify", "1", () =>
        withVar("GIT_DIR", "/elsewhere/.git", () =>
          shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", spawnFn, { env: { GIT_DIR: "/again" } }),
        ),
      );
      assert.equal("Git_Ssl_No_Verify" in call.env, false);
      assert.equal("GIT_DIR" in call.env, false);
      assert.equal(call.env.GIT_ALLOW_PROTOCOL, "https");
      assert.equal(call.env.GIT_PROTOCOL_FROM_USER, "0");
      assert.deepEqual(call.args.slice(0, 8), [
        "-c",
        "credential.helper=",
        "-c",
        "protocol.allow=never",
        "-c",
        "protocol.https.allow=always",
        "-c",
        "core.symlinks=false",
      ]);
    });

    it("adds the env option over the parent's environment in the inherited mode", async () => {
      let env;
      const spawnFn = (_command, _args, options) => {
        env = options.env;
        return { pid: undefined, on: (event, callback) => event === "close" && callback(0) };
      };
      await withVar("CLONE_TEST_KEEP", "kept", () =>
        shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", spawnFn, {
          inheritGitEnvironment: true,
          env: { GIT_LFS_SKIP_SMUDGE: "1" },
        }),
      );
      assert.equal(env.GIT_LFS_SKIP_SMUDGE, "1");
      assert.equal(env.CLONE_TEST_KEEP, "kept");
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

  for (const url of [
    "https:github.com/o/r",
    "https://github.com/o/r/",
    "https://user@github.com/o/r",
    "https://github.com:443/o/r",
    "https://github.com/o/r?x=1",
    "https://gitlab.com/o/r",
    "https://github.com/o/r/tree/main",
  ]) {
    it(`refuses a URL that is not https://github.com/<owner>/<repo>: ${url}`, async () => {
      const io = capture();
      assert.equal(await runCloneCli([url, path.join(sandbox(), "d")], { clone: neverCalled, stderr: io.stderr }), 2);
      assert.match(io.err, /only an https URL is cloned/);
    });
  }

  it("clones the rebuilt URL, never the argument as given", async () => {
    const calls = [];
    const ok = async (url) => (calls.push(url), true);
    const dest = path.join(sandbox(), "d");
    assert.equal(await runCloneCli(["HTTPS://GitHub.com/o/r.git", dest], { clone: ok, stderr: capture().stderr }), 0);
    assert.deepEqual(calls, ["https://github.com/o/r"]);
  });

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
