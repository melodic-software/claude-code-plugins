import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const MODULE = fileURLToPath(new URL("./ci-workflows-at-pin.mjs", import.meta.url));
const WORKFLOW = fileURLToPath(new URL("../../workflows/pr-require-checks.yml", import.meta.url));
const PIN = /check-machine-paths@([0-9a-f]{40})/.exec(readFileSync(WORKFLOW, "utf8"))[1];

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
    assert.ok(existsSync(join(dir, "ci-workflows-at-pin", PIN, "ready")), "the pin's cache is written");
    assert.equal(existsSync(join(caller, "shallow")), false, "the caller's repository gains no shallow file");
    assert.equal(execFileSync("git", ["--git-dir", caller, "count-objects"], { encoding: "utf8" }).trim(), "0 objects, 0 kilobytes");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a pin that is not a full commit sha is refused before any fetch", async () => {
  const { fetchAtPin } = await import(MODULE);
  await assert.rejects(fetchAtPin("main", "README.md"), /not a full commit sha/);
});
