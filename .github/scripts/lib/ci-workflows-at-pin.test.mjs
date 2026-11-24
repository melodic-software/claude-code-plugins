import assert from "node:assert/strict";
import { execFile, execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { describe, test } from "node:test";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const MODULE = fileURLToPath(new URL("./ci-workflows-at-pin.mjs", import.meta.url));
const WORKFLOW = fileURLToPath(new URL("../../workflows/pr-require-checks.yml", import.meta.url));
const PIN = /check-machine-paths@(main)/.exec(readFileSync(WORKFLOW, "utf8"))[1];

test("a pinned file is read by git fetch into its own cache, whatever GIT_DIR the caller exports", () => {
  const dir = mkdtempSync(join(tmpdir(), "ci-workflows-at-pin-test-"));
  try {
    const caller = join(dir, "caller.git");
    execFileSync("git", ["init", "-q", "--bare", caller]);
    const out = spawnSync(
      process.execPath,
      ["--input-type=module", "-e", "const m = await import(process.argv[1]); process.stdout.write(await m.fetchAtPin(process.argv[2], '.github/actions/check-machine-paths/action.yml'));", MODULE, PIN],
      { encoding: "utf8", env: { ...process.env, GIT_DIR: caller, TMPDIR: dir } },
    );
    assert.equal(out.status, 0, out.stderr);
    assert.match(out.stdout, /^name: /m);
    assert.ok(readdirSync(join(dir, "ci-workflows-at-pin")).some((sha) => /^[0-9a-f]{40}$/.test(sha) && existsSync(join(dir, "ci-workflows-at-pin", sha, "ready"))), "the commit's cache is written");
    assert.equal(existsSync(join(caller, "shallow")), false, "the caller's repository gains no shallow file");
    assert.equal(execFileSync("git", ["--git-dir", caller, "count-objects"], { encoding: "utf8" }).trim(), "0 objects, 0 kilobytes");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("main is resolved to its tip's full sha before anything is cached, for the contract read too", () => {
  const dir = mkdtempSync(join(tmpdir(), "ci-workflows-at-pin-test-"));
  try {
    const out = spawnSync(
      process.execPath,
      ["--input-type=module", "-e", "const m = await import(process.argv[1]); process.stdout.write(JSON.stringify(await m.contractFilesAtPin('main')));", MODULE],
      { encoding: "utf8", env: { ...process.env, TMPDIR: dir } },
    );
    assert.equal(out.status, 0, out.stderr);
    assert.ok(JSON.parse(out.stdout).length > 0, out.stdout);
    const tip = execFileSync("git", ["ls-remote", "https://github.com/melodic-software/ci-workflows.git", "refs/heads/main"], { encoding: "utf8" }).split("\t")[0];
    const cached = readdirSync(join(dir, "ci-workflows-at-pin"));
    assert.ok(cached.includes(tip), `${tip} in ${cached.join(", ")}`);
    assert.ok(cached.every((name) => /^[0-9a-f]{40}$/.test(name)), cached.join(", "));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a ref that is neither main nor a full commit sha is refused before any fetch", async () => {
  const { fetchAtPin } = await import(MODULE);
  await assert.rejects(fetchAtPin("v1", "README.md"), /neither main nor a full commit sha/);
});

const STUB_BIN = fileURLToPath(new URL("./fixtures/stub-git", import.meta.url));
const REAL_GIT = execFileSync("sh", ["-c", "command -v git"], { encoding: "utf8" }).trim();
const GITHUB_403 = "fatal: unable to access 'https://github.com/melodic-software/ci-workflows.git/': The requested URL returned error: 403";

async function fetchThroughStub(fails, error) {
  const dir = mkdtempSync(join(tmpdir(), "ci-workflows-at-pin-test-"));
  try {
    const count = join(dir, "count");
    const env = { ...process.env, PATH: `${STUB_BIN}:${process.env.PATH}`, TMPDIR: dir, STUB_GIT_REAL: REAL_GIT, STUB_GIT_FAILS: String(fails), STUB_GIT_ERROR: error, STUB_GIT_COUNT: count };
    const script = "const m = await import(process.argv[1]); process.stdout.write(await m.fetchAtPin(process.argv[2], 'README.md'));";
    const started = Date.now();
    const outcome = await promisify(execFile)(process.execPath, ["--input-type=module", "-e", script, MODULE, "a".repeat(40)], { encoding: "utf8", env }).then(
      ({ stdout }) => ({ stdout }),
      (failure) => ({ stderr: failure.stderr }),
    );
    return { ...outcome, fetches: Number(readFileSync(count, "utf8")), seconds: (Date.now() - started) / 1000 };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe("a fetch that fails", { concurrency: true }, () => {
  test("twice on an HTTP 403 is run again after 2 s and 5 s and its file is read", async () => {
    const { stdout, fetches, seconds } = await fetchThroughStub(2, "error: RPC failed; HTTP 403 curl 22 The requested URL returned error: 403");
    assert.equal(stdout, "stub file\n");
    assert.equal(fetches, 3);
    assert.ok(seconds >= 7, `${seconds} s`);
  });

  test("on an error no outage explains throws at once", async () => {
    const { stdout, stderr, fetches } = await fetchThroughStub(9, "fatal: remote error: upload-pack: not our ref aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    assert.equal(stdout, undefined);
    assert.match(stderr, /git fetch of ci-workflows a{40} failed: fatal: remote error: upload-pack: not our ref/);
    assert.equal(fetches, 1);
  });

  test("three times on GitHub's 403 throws that 403", async () => {
    const { stdout, stderr, fetches } = await fetchThroughStub(9, GITHUB_403);
    assert.equal(stdout, undefined);
    assert.match(stderr, /git fetch of ci-workflows a{40} failed: .*The requested URL returned error: 403/);
    assert.equal(fetches, 3);
  });
});
