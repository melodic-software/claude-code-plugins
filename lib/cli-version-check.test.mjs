import { strict as assert } from "node:assert";
import { spawn, spawnSync } from "node:child_process";
import fs, { existsSync, mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { checkVersion, claimDaily, compareVersions, DAY_MS, parseVersion, STALE_LOCK_MS } from "./cli-version-check.mjs";
import { tempDir } from "./test-tmp.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "cli-version-check.mjs");
const NOW = Date.parse("2026-11-21T12:00:00Z");

/** A fetch stand-in answering every call with `body` (or throwing `body` when it is an Error), recording each URL. */
function fakeFetch(body, status = 200) {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init });
    if (body instanceof Error) throw body;
    return { ok: status >= 200 && status < 300, status, json: async () => body };
  };
  return { fetch, calls };
}

function check(stateDir, overrides) {
  return checkVersion({ stateDir, cli: "agy", installed: "agy 1.5.13 (abc123)", source: "github:google-antigravity/antigravity-cli", now: NOW, ...overrides });
}

test("a CLI behind the latest release is reported once, with the configured hint", async () => {
  const dir = tempDir("cvc-");
  const { fetch, calls } = fakeFetch({ tag_name: "v1.6.0" });
  const result = await check(dir, { fetch, hint: "Run chezmoi apply." });
  assert.deepEqual(result, { status: "behind", installed: "1.5.13", latest: "1.6.0", message: "agy 1.5.13 is behind 1.6.0. Run chezmoi apply." });
  assert.equal(calls[0].url, "https://api.github.com/repos/google-antigravity/antigravity-cli/releases/latest");
  assert.ok(calls[0].init.signal, "the lookup carries a timeout signal");
});

test("a second check the same day is skipped without a lookup", async () => {
  const dir = tempDir("cvc-");
  await check(dir, { fetch: fakeFetch({ tag_name: "1.5.13" }).fetch });
  const second = fakeFetch({ tag_name: "1.5.13" });
  assert.deepEqual(await check(dir, { fetch: second.fetch, now: NOW + DAY_MS - 1 }), { status: "skipped" });
  assert.equal(second.calls.length, 0);
});

test("the check is due again a day later", async () => {
  const dir = tempDir("cvc-");
  await check(dir, { fetch: fakeFetch({ tag_name: "1.5.13" }).fetch });
  const result = await check(dir, { fetch: fakeFetch({ tag_name: "1.5.13" }).fetch, now: NOW + DAY_MS });
  assert.equal(result.status, "current");
});

test("a failed lookup is reported as unverified and still waits a day", async () => {
  const dir = tempDir("cvc-");
  const result = await check(dir, { fetch: fakeFetch(new Error("getaddrinfo ENOTFOUND")).fetch });
  assert.equal(result.status, "unverified");
  assert.match(result.message, /ENOTFOUND\); next check in 24 hours\.$/);
  const retry = fakeFetch({ tag_name: "1.5.13" });
  assert.equal((await check(dir, { fetch: retry.fetch, now: NOW + 60_000 })).status, "skipped");
  assert.equal(retry.calls.length, 0);
});

test("an HTTP error status is unverified, naming the status", async () => {
  const result = await check(tempDir("cvc-"), { fetch: fakeFetch({ message: "rate limited" }, 403).fetch });
  assert.equal(result.status, "unverified");
  assert.match(result.message, /\(HTTP 403\)/);
});

test("a timeout is reported as no answer within the limit", async () => {
  const timeout = Object.assign(new Error("aborted"), { name: "TimeoutError" });
  const result = await check(tempDir("cvc-"), { fetch: fakeFetch(timeout).fetch, timeoutMs: 1500 });
  assert.match(result.message, /\(no answer in 1500 ms\)/);
});

test("a CLI that prints no version is reported missing, with the hint, and makes no lookup", async () => {
  const { fetch, calls } = fakeFetch({ tag_name: "1.5.13" });
  const result = await check(tempDir("cvc-"), { fetch, installed: "", hint: "Install it with your dotfiles." });
  assert.deepEqual(result, { status: "not-installed", message: "agy is not installed or printed no version. Install it with your dotfiles." });
  assert.equal(calls.length, 0);
});

test("an installed version at or above the latest is current and prints nothing", async () => {
  for (const tag of ["1.5.13", "1.5.12"]) {
    const result = await check(tempDir("cvc-"), { fetch: fakeFetch({ tag_name: tag }).fetch });
    assert.equal(result.status, "current");
    assert.equal(result.message, undefined);
  }
});

test("an npm source reads the registry's latest version, scoped packages included", async () => {
  const { fetch, calls } = fakeFetch({ version: "0.2.0" });
  const result = await check(tempDir("cvc-"), { fetch, cli: "playwright-cli", installed: "0.1.9", source: "npm:@playwright/cli" });
  assert.equal(calls[0].url, "https://registry.npmjs.org/@playwright/cli/latest");
  assert.equal(result.status, "behind");
});

test("a multi-line hint is folded onto the one report line", async () => {
  const result = await check(tempDir("cvc-"), { fetch: fakeFetch({ tag_name: "2.0.0" }).fetch, hint: "Update:\n  run apply" });
  assert.equal(result.message, "agy 1.5.13 is behind 2.0.0. Update: run apply");
});

test("an invalid source or name is a usage error and writes no state", async () => {
  const dir = tempDir("cvc-");
  await assert.rejects(check(dir, { source: "https://example.test/latest" }), /invalid source/);
  await assert.rejects(check(dir, { cli: "../escape" }), /invalid name/);
  assert.equal(existsSync(join(dir, "cli-version-check")), false);
});

test("claimDaily keeps separate days per name", () => {
  const dir = tempDir("cvc-");
  assert.equal(claimDaily({ stateDir: dir, name: "routing-agy", now: NOW }), true);
  assert.equal(claimDaily({ stateDir: dir, name: "routing-agy", now: NOW + 1 }), false);
  assert.equal(claimDaily({ stateDir: dir, name: "models-agy", now: NOW + 1 }), true);
});

test("a stamp in the future or an unreadable stamp makes the job due", () => {
  const dir = tempDir("cvc-");
  const file = join(dir, "cli-version-check", "agy.json");
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify({ checked_at: new Date(NOW + DAY_MS).toISOString() }));
  assert.equal(claimDaily({ stateDir: dir, name: "agy", now: NOW }), true);
  writeFileSync(file, "{not json");
  assert.equal(claimDaily({ stateDir: dir, name: "agy", now: NOW }), true);
});

test("only one of many processes claiming the same name at once wins", async () => {
  const dir = tempDir("cvc-");
  const runs = Array.from({ length: 24 }, () =>
    new Promise((resolve) => {
      const child = spawn(process.execPath, [SCRIPT, "claim", "--state-dir", dir, "--name", "race"]);
      child.on("exit", resolve);
    }),
  );
  const codes = await Promise.all(runs);
  assert.equal(codes.filter((code) => code === 0).length, 1);
  assert.equal(codes.filter((code) => code === 1).length, 23);
});

test("a claim that lands while another claimant is on its way to the lock makes that claimant lose", () => {
  const dir = tempDir("cvc-");
  const original = fs.mkdirSync;
  const restore = () => {
    fs.mkdirSync = original;
    syncBuiltinESMExports();
  };
  let inner;
  fs.mkdirSync = (...args) => {
    restore();
    const until = Date.now() + 2;
    while (Date.now() < until);
    inner = claimDaily({ stateDir: dir, name: "race" });
    return original(...args);
  };
  syncBuiltinESMExports();
  try {
    const outer = claimDaily({ stateDir: dir, name: "race" });
    assert.deepEqual({ inner, outer }, { inner: true, outer: false });
  } finally {
    restore();
  }
});

test("a fresh lock held by another claimant refuses; a stale one is broken", () => {
  const dir = tempDir("cvc-");
  const lock = join(dir, "cli-version-check", "agy.json.lock");
  mkdirSync(dirname(lock), { recursive: true });
  writeFileSync(lock, "");
  assert.equal(claimDaily({ stateDir: dir, name: "agy", now: NOW }), false);
  const old = (Date.now() - STALE_LOCK_MS - 1000) / 1000;
  utimesSync(lock, old, old);
  assert.equal(claimDaily({ stateDir: dir, name: "agy", now: NOW }), true);
  assert.equal(existsSync(lock), false);
});

test("a lock that vanished before its age was read is never removed, even when a fresh one has replaced it", () => {
  const dir = tempDir("cvc-");
  const lock = join(dir, "cli-version-check", "agy.json.lock");
  mkdirSync(dirname(lock), { recursive: true });
  writeFileSync(lock, "");
  const original = fs.statSync;
  const restore = () => {
    fs.statSync = original;
    syncBuiltinESMExports();
  };
  fs.statSync = (path, ...rest) => {
    restore();
    rmSync(lock);
    const result = original(path, ...rest);
    writeFileSync(lock, "");
    return result;
  };
  syncBuiltinESMExports();
  try {
    assert.equal(claimDaily({ stateDir: dir, name: "agy", now: NOW }), false);
    assert.equal(existsSync(lock), true);
  } finally {
    restore();
  }
});

test("parseVersion and compareVersions", () => {
  assert.equal(parseVersion("codex-cli 0.80.1"), "0.80.1");
  assert.equal(parseVersion("v2.1"), "2.1");
  assert.equal(parseVersion("/usr/bin/bash: line 4: agy: command not found"), null);
  assert.equal(parseVersion("no digits"), null);
  assert.equal(compareVersions("1.10.0", "1.9.9"), 1);
  assert.equal(compareVersions("1.5", "1.5.0"), 0);
  assert.equal(compareVersions("1.5.0", "1.5.1"), -1);
});

test("command line: claim exits 0 when due and 1 when not; a usage error exits 2", () => {
  const dir = tempDir("cvc-");
  const run = (...args) => spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8" });
  assert.equal(run("claim", "--state-dir", dir, "--name", "routing-agy").status, 0);
  assert.equal(run("claim", "--state-dir", dir, "--name", "routing-agy").status, 1);
  const bad = run("check", "--state-dir", dir, "--cli", "agy", "--source", "ftp:nope");
  assert.equal(bad.status, 2);
  assert.match(bad.stderr, /invalid source/);
  assert.equal(run("nonsense").status, 2);
  assert.equal(run("claim", "--state-dir", dir).status, 2);
  assert.equal(run("claim", "--state-dir", dir, "--cli", "agy").status, 2);
  assert.equal(run("check", "--state-dir", dir, "--source", "npm:ctx7").status, 2);
  assert.equal(existsSync(join(dir, "cli-version-check", "undefined.json")), false);
});
