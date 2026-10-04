import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import {
  chmodSync,
  closeSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { writeSnapshot } from "./write-snapshot.mjs";

const helper = fileURLToPath(new URL("./write-snapshot.mjs", import.meta.url));
const posix = process.platform !== "win32";
const root = mkdtempSync(path.join(tmpdir(), "write-snapshot-"));
after(() => rmSync(root, { recursive: true, force: true }));

let n = 0;
function freshDir() {
  const dir = path.join(root, `case-${++n}`);
  mkdirSync(dir);
  return dir;
}

function run(args, body) {
  const r = spawnSync(process.execPath, [helper, ...args], { input: body, encoding: "utf8" });
  return { code: r.status, out: r.stdout.trim(), err: r.stderr.trim() };
}

function runAsync(args, body) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [helper, ...args]);
    child.on("close", (code) => resolve(code));
    child.stdin.end(body);
  });
}

function ageFile(file, seconds) {
  const t = (Date.now() - seconds * 1000) / 1000;
  utimesSync(file, t, t);
}

// Matches the harness-ops audit-install-state classifier for a shell `$$` temp
// (`re.fullmatch(r"rate-limit-guard/.*\.tmp\.\d+")`). A helper temp must never
// match it, or a leftover is misread as a crashed shell's file.
const shellPidTemp = /^rate-limit-guard\/.*\.tmp\.\d+$/;

const windows = '{"captured_at":"2026-10-03T10:00:00Z","rate_limits":{"five_hour":{"used_percentage":41,"resets_at":1790000000}},"session_id":"s1"}\n';
const windowless = '{"captured_at":"2026-10-03T10:00:30Z","session_id":"s2"}\n';

test("renames the body into place and leaves no temp behind", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const r = run([target], windows);
  assert.equal(r.code, 0, r.err);
  assert.equal(readFileSync(target, "utf8"), windows);
  assert.deepEqual(readdirSync(dir), ["rate-limits.json"]);
});

test("a body without a trailing newline lands with one", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  assert.equal(run([target], windows.trimEnd()).code, 0);
  assert.equal(readFileSync(target, "utf8"), windows);
});

test("creates a missing directory owner-only and the file owner-only", { skip: !posix }, () => {
  const dir = path.join(freshDir(), "nested", "rate-limit-guard");
  const target = path.join(dir, "rate-limits.json");
  assert.equal(run([target], windows).code, 0);
  assert.equal(statSync(dir).mode & 0o777, 0o700);
  assert.equal(statSync(target).mode & 0o777, 0o600);
});

test("a windowless body never replaces a window-bearing file", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  writeFileSync(target, windows);
  const r = run([target, "--preserve-key", "rate_limits"], windowless);
  assert.equal(r.code, 3);
  assert.equal(r.out, "skip preserve");
  assert.equal(readFileSync(target, "utf8"), windows);
});

test("window-bearing is structural: a value naming the key does not count", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  writeFileSync(target, windows);
  const body = '{"captured_at":"2026-10-03T10:00:30Z","session_name":"rate_limits"}\n';
  assert.equal(run([target, "--preserve-key", "rate_limits"], body).out, "skip preserve");
  assert.equal(readFileSync(target, "utf8"), windows);
});

test("a windowless body is written when there are no windows to preserve", () => {
  for (const before of [null, '{"captured_at":"2026-10-03T09:00:00Z","session_id":"s0"}\n', "{torn"]) {
    const dir = freshDir();
    const target = path.join(dir, "rate-limits.json");
    if (before !== null) writeFileSync(target, before);
    const r = run([target, "--preserve-key", "rate_limits"], windowless);
    assert.equal(r.code, 0, `before=${before}: ${r.err}`);
    assert.equal(readFileSync(target, "utf8"), windowless);
  }
});

test("the floor skips a write within that many seconds of the file's captured_at", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  writeFileSync(target, windows);
  const at = (t) => windows.replace("10:00:00", t);
  const r = run([target, "--floor", "300"], at("10:04:59"));
  assert.equal(r.out, "skip floor");
  assert.equal(readFileSync(target, "utf8"), windows);
  assert.equal(run([target, "--floor", "300"], at("10:05:00")).code, 0);
  assert.equal(readFileSync(target, "utf8"), at("10:05:00"));
  assert.equal(run([target], at("10:05:01")).code, 0, "no --floor: the caller decided to write");
});

test("the floor never holds back windows over a windowless file", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  writeFileSync(target, '{"captured_at":"2026-10-03T09:59:50Z","session_id":"s2"}\n');
  const r = run([target, "--floor", "300", "--preserve-key", "rate_limits"], windows);
  assert.equal(r.code, 0, r.err);
  assert.equal(readFileSync(target, "utf8"), windows);
});

test("an older observation never replaces a newer one, unless the newer is implausible", () => {
  const dir = freshDir();
  const target = path.join(dir, "s.json");
  const at = (t) => `{"captured_at":"2026-10-03T${t}Z","session_id":"s"}\n`;
  writeFileSync(target, at("10:00:10"));
  assert.equal(run([target], at("10:00:00")).out, "skip regress");
  assert.equal(readFileSync(target, "utf8"), at("10:00:10"));
  assert.equal(run([target], at("10:00:10")).code, 0, "an equal second is not older");
  writeFileSync(target, at("10:05:01"));
  assert.equal(run([target], at("10:00:00")).code, 0, "301 s ahead is past the 300 s ceiling");
  assert.equal(readFileSync(target, "utf8"), at("10:00:00"));
});

test("a stale lock is stolen; a live one makes a windowless writer skip", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const lock = path.join(dir, ".rate-limits.json.lock");
  writeFileSync(lock, "");
  ageFile(lock, 61);
  assert.equal(run([target, "--preserve-key", "rate_limits"], windowless).code, 0);
  assert.equal(existsSync(lock), false, "the stolen lock is released after the write");

  writeFileSync(lock, "");
  const r = run([target, "--preserve-key", "rate_limits"], windowless.replace("10:00:30", "10:00:40"));
  assert.equal(r.out, "skip lock");
  assert.equal(readFileSync(target, "utf8"), windowless);
});

test("a live lock does not stop a window-bearing writer, and is left for its holder", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const lock = path.join(dir, ".rate-limits.json.lock");
  writeFileSync(lock, "");
  assert.equal(run([target, "--preserve-key", "rate_limits"], windows).code, 0);
  assert.equal(readFileSync(target, "utf8"), windows);
  assert.equal(existsSync(lock), true);
});

test("concurrent writers leave one whole body and keep the windows", async () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const bodies = [];
  for (let i = 0; i < 12; i++) {
    const plain = windowless.replace("10:00:30", "10:00:00").replace("s2", `w${i}`);
    bodies.push(i % 2 ? plain : windows.replace("s1", `r${i}`));
  }
  const codes = await Promise.all(bodies.map((b) => runAsync([target, "--preserve-key", "rate_limits"], b)));
  for (const code of codes) assert.ok(code === 0 || code === 3, `exit ${code}`);
  const final = readFileSync(target, "utf8");
  assert.ok(bodies.includes(final), "the file is exactly one writer's body");
  assert.ok("rate_limits" in JSON.parse(final));
  assert.deepEqual(readdirSync(dir), ["rate-limits.json"]);
});

test("rename is retried after a sharing failure, and temps never look like a shell pid temp", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const tries = [];
  const rename = (from, to) => {
    tries.push(from);
    if (tries.length < 3) throw Object.assign(new Error("busy"), { code: "EBUSY" });
    renameSync(from, to);
  };
  assert.equal(writeSnapshot([target], windows, { rename }).code, 0);
  assert.equal(tries.length, 3);
  assert.equal(readFileSync(target, "utf8"), windows);
  for (let i = 0; i < 40; i++) {
    writeSnapshot([target], windows, {
      rename: (from, to) => {
        tries.push(from);
        renameSync(from, to);
      },
    });
  }
  for (const from of tries) {
    assert.equal(path.dirname(from), dir);
    assert.ok(path.basename(from).startsWith("."), from);
    assert.doesNotMatch(`rate-limit-guard/${path.basename(from)}`, shellPidTemp);
  }
});

test("a rename that keeps failing is skipped after three tries with its temp removed", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const before = '{"captured_at":"2026-10-03T09:00:00Z","session_id":"s0"}\n';
  writeFileSync(target, before);
  let calls = 0;
  const rename = () => {
    calls++;
    throw Object.assign(new Error("denied"), { code: "EPERM" });
  };
  const r = writeSnapshot([target], windows, { rename });
  assert.equal(r.code, 1);
  assert.match(r.err, /EPERM/);
  assert.equal(calls, 3);
  assert.equal(readFileSync(target, "utf8"), before);
  assert.deepEqual(readdirSync(dir), ["rate-limits.json"]);
});

test("a real rename failure exits 1 with one stderr line and no temp left", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  mkdirSync(path.join(target, "occupied"), { recursive: true });
  const r = run([target], windows);
  assert.equal(r.code, 1);
  assert.equal(r.err.split("\n").length, 1);
  assert.match(r.err, /^write-snapshot: /);
  assert.deepEqual(readdirSync(dir), ["rate-limits.json"]);
});

test("temps older than a minute are swept; live ones and other files stay", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const legacy = path.join(dir, ".rate-limits.json.tmp.4242.1717");
  const live = path.join(dir, ".rate-limits.json.tmp.w77-0a1b2c3d");
  const recorder = path.join(dir, "stop-events.jsonl.tmp.99");
  for (const f of [legacy, live, recorder]) writeFileSync(f, "x");
  ageFile(legacy, 61);
  ageFile(recorder, 3600);
  assert.equal(run([target], windows).code, 0);
  assert.deepEqual(readdirSync(dir).sort(), [path.basename(live), "rate-limits.json", "stop-events.jsonl.tmp.99"].sort());
});

test("the sweep runs even when the write is skipped", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  writeFileSync(target, windows);
  const legacy = path.join(dir, ".rate-limits.json.tmp.4242.1717");
  writeFileSync(legacy, "x");
  ageFile(legacy, 120);
  assert.equal(run([target, "--preserve-key", "rate_limits"], windowless).out, "skip preserve");
  assert.equal(existsSync(legacy), false);
});

function pruneFixture() {
  const dir = path.join(freshDir(), "context");
  mkdirSync(dir);
  const files = {
    old: path.join(dir, "old-session.json"),
    fresh: path.join(dir, "fresh-session.json"),
    oldLast: path.join(dir, ".old-session.json.last"),
    oldLock: path.join(dir, ".old-session.json.lock"),
    marker: path.join(dir, "old-session.compacted"),
  };
  for (const f of Object.values(files)) writeFileSync(f, "{}");
  const fifteenDays = 15 * 24 * 3600;
  for (const k of ["old", "oldLast", "oldLock", "marker"]) ageFile(files[k], fifteenDays);
  ageFile(files.fresh, 13 * 24 * 3600);
  return { dir, files, target: path.join(dir, "abc-123_x.json") };
}

const sessionBody = '{"captured_at":"2026-10-03T10:00:00Z","session_id":"abc-123_x","context_window":{"used_percentage":21}}\n';

test("--prune deletes session files older than 14 days and stamps the pass", () => {
  const { dir, files, target } = pruneFixture();
  const before = Math.floor(Date.now() / 1000);
  assert.equal(run([target, "--prune"], sessionBody).code, 0);
  assert.equal(existsSync(files.old), false);
  assert.equal(existsSync(files.oldLast), false);
  assert.equal(existsSync(files.oldLock), false);
  assert.equal(existsSync(files.fresh), true, "13 days is inside the retention");
  assert.equal(existsSync(files.marker), true, "only snapshot files are pruned");
  const stamp = Number(readFileSync(path.join(dir, ".prune-stamp"), "utf8").trim());
  assert.ok(stamp >= before && stamp <= before + 5, `stamp ${stamp}`);
  if (posix) assert.equal(statSync(dir).mode & 0o777, 0o700, "the pass re-asserts the mode");
});

test("--prune runs at most hourly by its stamp", () => {
  for (const [stampAge, pruned] of [
    [10, false],
    [3500, false],
    [3600, true],
    [-600, true],
  ]) {
    const { dir, files, target } = pruneFixture();
    writeFileSync(path.join(dir, ".prune-stamp"), `${Math.floor(Date.now() / 1000) - stampAge}\n`);
    assert.equal(run([target, "--prune"], sessionBody).code, 0);
    assert.equal(existsSync(files.old), !pruned, `stamp ${stampAge} s old`);
  }
});

test("without --prune nothing old is deleted", () => {
  const { files, target } = pruneFixture();
  assert.equal(run([target], sessionBody).code, 0);
  assert.equal(existsSync(files.old), true);
});

test("bad input exits 2 with one stderr line and writes nothing", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const cases = [
    [[], windows],
    [["relative/rate-limits.json"], windows],
    [[path.join(dir, ".hidden.json")], windows],
    [[path.join(dir, "rate-limits.txt")], windows],
    [[target, "--floor", "5m"], windows],
    [[target, "--unknown"], windows],
    [[target], "{torn"],
    [[target], "[1,2]"],
    [[target], '{"session_id":"s"}'],
    [[target], '{"captured_at":"yesterday"}'],
  ];
  for (const [args, body] of cases) {
    const r = run(args, body);
    assert.equal(r.code, 2, `${JSON.stringify(args)} ${body}`);
    assert.match(r.err, /^write-snapshot: [^\n]+$/);
  }
  assert.deepEqual(readdirSync(dir), []);
});

const eperm = () => {
  throw Object.assign(new Error("operation not permitted"), { code: "EPERM" });
};

test("a chmod that fails never stops the write", () => {
  const { target } = pruneFixture();
  assert.equal(writeSnapshot([target, "--prune"], sessionBody, { chmod: eperm }).code, 0);
  assert.equal(readFileSync(target, "utf8"), sessionBody);
  const fresh = path.join(freshDir(), "made", "rate-limits.json");
  assert.equal(writeSnapshot([fresh], windows, { chmod: eperm }).code, 0);
  assert.equal(readFileSync(fresh, "utf8"), windows);
});

test("a prune that cannot write its stamp still writes the snapshot", () => {
  const { dir, target } = pruneFixture();
  mkdirSync(path.join(dir, ".prune-stamp"));
  const r = run([target, "--prune"], sessionBody);
  assert.equal(r.code, 0, r.err);
  assert.equal(readFileSync(target, "utf8"), sessionBody);
});

test("the 1 MiB body limit counts bytes, not characters", () => {
  const dir = freshDir();
  const target = path.join(dir, "s.json");
  const sized = (pad) => `{"captured_at":"2026-10-03T10:00:00Z","pad":"${pad}"}\n`;
  // 400,000 three-byte characters: 1,200,000 bytes, but only 400,000 UTF-16 units.
  for (const body of [sized("x".repeat(1 << 20)), sized("€".repeat(400_000))]) {
    const r = run([target], body);
    assert.equal(r.code, 2);
    assert.match(r.err, /1 MiB/);
  }
  assert.deepEqual(readdirSync(dir), []);
  const accented = sized("café €");
  assert.equal(run([target], accented).code, 0);
  assert.equal(readFileSync(target, "utf8"), accented);
});

test("a lock that cannot be removed never stops the write or throws", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const lock = path.join(dir, ".rate-limits.json.lock");
  const rename = (from, to) => {
    renameSync(from, to);
    rmSync(lock, { force: true });
    mkdirSync(path.join(lock, "held"), { recursive: true });
  };
  let r;
  assert.doesNotThrow(() => {
    r = writeSnapshot([target], windows, { rename });
  });
  assert.equal(readFileSync(target, "utf8"), windows);
  assert.equal(r.code, 0, "the snapshot itself was written");
});

test("a temp whose write and close both fail is removed", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  const write = (fd) => {
    closeSync(fd);
    throw Object.assign(new Error("no space left on device"), { code: "ENOSPC" });
  };
  const r = writeSnapshot([target], windows, { write });
  assert.equal(r.code, 1);
  assert.match(r.err, /ENOSPC|no space/);
  assert.deepEqual(readdirSync(dir), []);
});

test("a directory that cannot be listed still gets the snapshot", { skip: !posix || process.getuid?.() === 0 }, () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  chmodSync(dir, 0o300);
  try {
    const r = run([target], windows);
    assert.equal(r.code, 0, r.err);
    assert.equal(readFileSync(target, "utf8"), windows);
  } finally {
    chmodSync(dir, 0o700);
  }
});

test("null or absent options are accepted", () => {
  const dir = freshDir();
  const target = path.join(dir, "rate-limits.json");
  assert.equal(writeSnapshot([target], windows, null).code, 0);
  assert.equal(writeSnapshot([target], windows).code, 0);
  assert.equal(readFileSync(target, "utf8"), windows);
});

test("--prune also sweeps every session's aged .*.json.tmp.* temps, and only those", () => {
  for (const pruning of [false, true]) {
    const dir = freshDir();
    const target = path.join(dir, "abc.json");
    const otherSession = [".other.json.tmp.4242.1717", ".other.json.tmp.w9-00ff00ff"];
    const survivors = [".zones.tmp.1", "stop-events.jsonl.tmp.77", "abc.compacted.tmp.5", ".fresh.json.tmp.1.2"];
    for (const f of [...otherSession, ...survivors]) writeFileSync(path.join(dir, f), "x");
    for (const f of [...otherSession, ...survivors.slice(0, 3)]) ageFile(path.join(dir, f), 61);
    const args = pruning ? [target, "--prune"] : [target];
    assert.equal(run(args, sessionBody.replace("abc-123_x", "abc")).code, 0);
    const kept = pruning ? survivors : [...otherSession, ...survivors];
    const expected = ["abc.json", ...kept, ...(pruning ? [".prune-stamp"] : [])].sort();
    assert.deepEqual(readdirSync(dir).sort(), expected, `pruning=${pruning}`);
  }
});

test("the sweep removes only the target's own temps", () => {
  const dir = freshDir();
  const target = path.join(dir, "abc.json");
  const own = [".abc.json.tmp.4242.1717", ".abc.json.tmp.w9-00ff00ff"];
  const others = [".zones.tmp.1", ".other-session.json.tmp.4242.1717", ".other-session.json.tmp.w9-00ff00ff"];
  for (const f of [...own, ...others]) {
    writeFileSync(path.join(dir, f), "x");
    ageFile(path.join(dir, f), 120);
  }
  assert.equal(run([target], sessionBody.replace("abc-123_x", "abc")).code, 0);
  assert.deepEqual(readdirSync(dir).sort(), ["abc.json", ...others].sort());
});
