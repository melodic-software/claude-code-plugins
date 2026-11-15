// sibling-workdir.sh: the driven session's working directory in the capture's
// sibling sandbox becomes a writable clone of the head checkout, with its
// history and the default branch, once the workflow marks the head ready.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";

const SCRIPT = fileURLToPath(new URL("./sibling-workdir.sh", import.meta.url));
const skip = process.platform === "win32" && "bash and git";

const git = (args, cwd) => {
  const result = spawnSync("git", ["-c", "user.name=t", "-c", "user.email=t@invalid", "-c", "commit.gpgsign=false", ...args], { cwd, encoding: "utf8" });
  assert.equal(result.status, 0, `git ${args.join(" ")}: ${result.stderr}`);
  return result.stdout.trim();
};

// A checkout shaped like actions/checkout's with fetch-depth 0: the branches as
// origin's remote-tracking refs and the pull request's head checked out detached.
// Main has two commits and the pull request one more.
const headCheckout = (root) => {
  const upstream = path.join(root, "upstream");
  git(["init", "-q", "-b", "main", upstream]);
  git(["commit", "-q", "--allow-empty", "-m", "one"], upstream);
  git(["commit", "-q", "--allow-empty", "-m", "two"], upstream);
  const main = git(["rev-parse", "HEAD"], upstream);
  git(["checkout", "-q", "-b", "feature"], upstream);
  writeFileSync(path.join(upstream, "changed.txt"), "the pull request's file\n");
  git(["add", "changed.txt"], upstream);
  git(["commit", "-q", "-m", "three"], upstream);
  const head = git(["rev-parse", "HEAD"], upstream);
  const checkout = path.join(root, "head");
  git(["init", "-q", checkout]);
  git(["fetch", "-q", upstream, "+refs/heads/*:refs/remotes/origin/*"], checkout);
  git(["checkout", "-q", "--detach", head], checkout);
  return { checkout, head, main };
};

// Read-only as the sandbox mounts it.
const lock = (dir) => spawnSync("chmod", ["-R", "a-w", dir]);
const unlock = (dir) => spawnSync("chmod", ["-R", "u+w", dir]);

const run = (args) => spawnSync("bash", [SCRIPT, ...args], { encoding: "utf8", env: { PATH: process.env.PATH } });
const result = (file) => JSON.parse(readFileSync(file, "utf8"));

test("once the head is ready, the working directory is a writable clone of it with its history and the default branch", { skip }, () => {
  const root = tempDir("sibling-workdir-");
  const { checkout, head, main } = headCheckout(root);
  const work = path.join(root, "w");
  mkdirSync(work);
  mkdirSync(path.join(root, "head-ready"));
  const out = path.join(root, "workdir.json");
  lock(checkout);
  try {
    const ran = run([path.join(root, "head-ready"), checkout, work, out, "1"]);
    assert.equal(ran.status, 0, ran.stderr);
    assert.deepEqual(result(out), { status: "ready", head });
    assert.equal(git(["rev-parse", "HEAD"], work), head);
    assert.equal(git(["rev-list", "--count", "HEAD"], work), "3");
    assert.equal(git(["rev-parse", "refs/remotes/origin/main"], work), main);
    assert.equal(git(["merge-base", "HEAD", "origin/main"], work), main);
    assert.equal(readFileSync(path.join(work, "changed.txt"), "utf8"), "the pull request's file\n");
    // A skill can write its memory file and commit beside the head's files; the head stays as it was.
    writeFileSync(path.join(work, "memory.md"), "x");
    git(["add", "memory.md"], work);
    git(["commit", "-q", "-m", "four"], work);
    assert.equal(git(["rev-parse", "HEAD"], checkout), head);
    assert.equal(git(["status", "--porcelain"], checkout), "");
  } finally {
    unlock(checkout);
  }
});

test("with no head-ready directory by its wait, the working directory stays empty and the result says timeout", { skip }, () => {
  const root = tempDir("sibling-workdir-");
  const { checkout } = headCheckout(root);
  const work = path.join(root, "w");
  mkdirSync(work);
  const out = path.join(root, "workdir.json");
  const ran = run([path.join(root, "head-ready"), checkout, work, out, "1"]);
  assert.equal(ran.status, 0, ran.stderr);
  assert.deepEqual(result(out), { status: "timeout", head: "" });
  assert.deepEqual(readdirSync(work), []);
});

test("a head that is no repository leaves the working directory empty and the result failed", { skip }, () => {
  const root = tempDir("sibling-workdir-");
  const checkout = path.join(root, "head");
  mkdirSync(checkout);
  writeFileSync(path.join(checkout, "file"), "x");
  const work = path.join(root, "w");
  mkdirSync(work);
  mkdirSync(path.join(root, "head-ready"));
  const out = path.join(root, "workdir.json");
  const ran = run([path.join(root, "head-ready"), checkout, work, out, "1"]);
  assert.equal(ran.status, 0, ran.stderr);
  assert.deepEqual(result(out), { status: "failed", head: "" });
  assert.deepEqual(readdirSync(work), []);
  assert.ok(!existsSync(`${out}.tmp`));
});

test("a working directory that is not empty is never cloned into, and is reported failed", { skip }, () => {
  const root = tempDir("sibling-workdir-");
  const { checkout } = headCheckout(root);
  const work = path.join(root, "w");
  mkdirSync(work);
  writeFileSync(path.join(work, "planted"), "x");
  mkdirSync(path.join(root, "head-ready"));
  const out = path.join(root, "workdir.json");
  const ran = run([path.join(root, "head-ready"), checkout, work, out, "1"]);
  assert.equal(ran.status, 0, ran.stderr);
  assert.equal(result(out).status, "failed");
  assert.ok(!existsSync(path.join(work, ".git")));
});
