import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

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
