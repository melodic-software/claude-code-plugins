// write-snapshot: atomically replace one guard contract file with the JSON body on
// stdin. A guard's mod runs it through $.process.run, because a mod's $.fs has no
// rename, delete or chmod. Node built-ins only; Linux, macOS and native Windows.
//
// Usage:
//   node write-snapshot.mjs <target> [--preserve-key <key>] [--floor <seconds>] [--prune] < body
//
//   rate-limit-guard: node write-snapshot.mjs ~/.claude/rate-limit-guard/rate-limits.json \
//                       --preserve-key rate_limits [--floor 300]
//   context-guard:    node write-snapshot.mjs ~/.claude/context-guard/context/<session_id>.json \
//                       --prune [--floor <seconds>]
//
//   <target>              absolute path to <name>.json, <name> of [A-Za-z0-9_.-] not starting
//                         with a dot. The caller accepts a session id only as [A-Za-z0-9_-]+.
//                         A missing directory is created owner-only (chmod 0700, best-effort,
//                         skipped on Windows; a failed chmod never stops the write).
//   stdin                 one JSON object of at most 1 MiB (bytes) whose captured_at is
//                         YYYY-MM-DDTHH:MM:SSZ, written as given except that trailing
//                         whitespace is trimmed and one newline added, owner-only (0600).
//                         The helper never adds, drops or reorders a field.
//   --preserve-key <key>  a body without top-level <key> never replaces a file that has it,
//                         and is written when the file has none (rate-limit-guard passes
//                         rate_limits: a windowless session never overwrites windows).
//   --floor <seconds>     skip when the body's captured_at is less than <seconds> after the
//                         file's (FLOOR below). Without it the write is not floor-bound.
//   --prune               at most hourly, delete <name>.json, .<name>.json.last and
//                         .<name>.json.lock files in the target directory older than 14 days,
//                         delete every session's .*.json.tmp.* temp older than 60 s (the
//                         context-guard tee's sweep pattern and age), and re-assert the
//                         directory's 0700 mode. The directory's
//                         .prune-stamp holds the epoch seconds of the last pass; absent,
//                         unreadable, future-dated or a symlink counts as due. The whole pass
//                         is best-effort: a stamp, chmod or delete that fails never stops the
//                         write.
//
// Exit codes; stdout and stderr carry at most one line each:
//   0  written.
//   1  failed (directory, temp file, or rename after 3 tries); stderr "write-snapshot: <reason>".
//      The target is unchanged and no temp file is left; readers fail open.
//   2  usage: bad arguments, or a body that is not a JSON object with a valid captured_at;
//      stderr "write-snapshot: <reason>". Nothing is touched.
//   3  skipped by rule; stdout "skip <rule>", where <rule> is lock, preserve, regress or floor.
//
// Rules, decided while holding the lock .<name>.json.lock, which is created exclusively and
// stolen when older than 60 s:
//   lock      after 3 tries 100 ms apart, a body lacking the --preserve-key key skips; any
//             other body writes unlocked (last writer wins between two window-bearing writes).
//   preserve  see --preserve-key.
//   regress   a file whose captured_at is later than the body's is kept, unless it is more
//             than 300 s later (an implausible clock), which is replaced.
//   floor     see --floor.
//   A body that adds the --preserve-key key to a file without it is exempt from regress and floor.
// The rename is retried 3 times 100 ms apart (Windows refuses to replace a file a reader holds
// open: EPERM, EBUSY, EACCES), then skipped with exit 1 and the temp removed.
//
// Every run sweeps, best-effort, the target's own temp files older than 60 s, named
// .<name>.json.tmp.<anything>: the helper's, .<name>.json.tmp.w<pid>-<hex> (never ending in
// .tmp.<digits>, the shape harness-ops audit-install-state reads as a shell's $$ temp), and the
// statusline tee's, .<name>.json.tmp.<pid>.<random>. Other files' temps are left to --prune. A lock
// that cannot be released after a write is left for the 60 s steal; the write still exits 0.
//
// FLOOR. The machine-wide write floor (at most one write per 300 s unless a window moved a
// whole point or reset) is the mod's decision, made in memory: it compares its reading with the
// last one it wrote and with the captured_at it reads from the file through $.fs, in process,
// so an event that writes nothing spawns nothing. A floor-bound write passes --floor 300; a
// write for a moved or reset window omits it. The helper repeats the check under the lock
// against the file as it is then, so two sessions that both decided to write inside the floor
// produce one write.

import { randomBytes } from "node:crypto";
import {
  chmodSync,
  closeSync,
  existsSync,
  lstatSync,
  mkdirSync,
  openSync,
  readdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
  writeSync,
} from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const TRIES = 3;
const PAUSE_MS = 100;
const STALE_MS = 60_000;
const PRUNE_EVERY_S = 3600;
const PRUNE_AGE_MS = 14 * 86_400_000;
const CEILING_S = 300;
const MAX_BODY = 1 << 20;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const NAME = /^[\w-][\w.-]*\.json$/;

class Usage extends Error {}

const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const capturedAt = (o) =>
  isObject(o) && typeof o.captured_at === "string" && ISO.test(o.captured_at) ? Date.parse(o.captured_at) / 1000 : Number.NaN;

function parseArgs(argv) {
  const opts = { target: null, floor: null, preserveKey: null, prune: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--prune") opts.prune = true;
    else if (a === "--floor" || a === "--preserve-key") {
      const v = argv[++i];
      if (v === undefined) throw new Usage(`${a} needs a value`);
      if (a === "--preserve-key") opts.preserveKey = v;
      else if (/^\d+$/.test(v)) opts.floor = Number(v);
      else throw new Usage(`--floor takes whole seconds, got ${v}`);
    } else if (a.startsWith("--") || opts.target !== null) throw new Usage(`unexpected argument ${a}`);
    else opts.target = a;
  }
  if (opts.target === null) throw new Usage("missing target path");
  if (!path.isAbsolute(opts.target) || !NAME.test(path.basename(opts.target))) {
    throw new Usage(`target must be an absolute path to <name>.json: ${opts.target}`);
  }
  return opts;
}

function parseBody(text) {
  if (Buffer.byteLength(text) > MAX_BODY) throw new Usage("body is over 1 MiB");
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw new Usage("body is not JSON");
  }
  if (Number.isNaN(capturedAt(body))) {
    throw new Usage("body must be a JSON object whose captured_at is YYYY-MM-DDTHH:MM:SSZ");
  }
  return body;
}

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function quietly(fn) {
  try {
    fn();
  } catch {}
}

function removeOlder(dir, nowMs, ageMs, match) {
  for (const name of readdirSync(dir)) {
    if (!match(name)) continue;
    const file = path.join(dir, name);
    try {
      const s = lstatSync(file);
      if (s.isFile() && nowMs - s.mtimeMs > ageMs) rmSync(file, { force: true });
    } catch {}
  }
}

function prune(dir, nowMs, ownerOnly) {
  const stamp = path.join(dir, ".prune-stamp");
  const nowS = Math.floor(nowMs / 1000);
  let last = 0;
  let link = false;
  try {
    link = lstatSync(stamp).isSymbolicLink();
    const text = link ? "" : readFileSync(stamp, "utf8").trim();
    if (/^\d+$/.test(text)) last = Number(text);
  } catch {}
  if (!link && last <= nowS && nowS - last < PRUNE_EVERY_S) return;
  if (!link) quietly(() => writeFileSync(stamp, `${nowS}\n`));
  ownerOnly(dir);
  removeOlder(dir, nowMs, STALE_MS, (n) => /^\..*\.json\.tmp\./.test(n));
  removeOlder(
    dir,
    nowMs,
    PRUNE_AGE_MS,
    (n) => (/^[^.].*\.json$/.test(n) && !n.includes(".tmp.")) || /^\..+\.json\.(last|lock)$/.test(n),
  );
}

function acquire(lock) {
  for (let i = 0; i < TRIES; i++) {
    if (i) sleep(PAUSE_MS);
    try {
      if (Date.now() - lstatSync(lock).mtimeMs > STALE_MS) rmSync(lock, { recursive: true, force: true });
    } catch {}
    try {
      closeSync(openSync(lock, "wx", 0o600));
      return true;
    } catch {}
  }
  return false;
}

// Returns { code, out?, err? } and never throws; the exit codes are the usage comment's.
export function writeSnapshot(argv, text, options) {
  const { rename = renameSync, chmod = chmodSync, write = writeSync } = options ?? {};
  let lock = null;
  const skip = (rule) => ({ code: 3, out: `skip ${rule}` });
  const ownerOnly = (dir) => process.platform !== "win32" && quietly(() => chmod(dir, 0o700));
  try {
    const { target, floor, preserveKey, prune: pruning } = parseArgs(argv);
    const body = parseBody(text);
    const dir = path.dirname(target);
    const name = path.basename(target);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true, mode: 0o700 });
      ownerOnly(dir);
    }
    const now = Date.now();
    quietly(() => removeOlder(dir, now, STALE_MS, (n) => n.startsWith(`.${name}.tmp.`)));
    if (pruning) quietly(() => prune(dir, now, ownerOnly));

    const has = (o) => preserveKey !== null && isObject(o) && Object.hasOwn(o, preserveKey);
    const lockPath = path.join(dir, `.${name}.lock`);
    if (acquire(lockPath)) lock = lockPath;
    else if (preserveKey !== null && !has(body)) return skip("lock");

    const current = readJson(target);
    if (has(current) && !has(body)) return skip("preserve");
    if (!(has(body) && !has(current))) {
      const was = capturedAt(current);
      const at = capturedAt(body);
      if (was > at && was <= at + CEILING_S) return skip("regress");
      if (floor !== null && at >= was && at - was < floor) return skip("floor");
    }

    const tmp = path.join(dir, `.${name}.tmp.w${process.pid}-${randomBytes(4).toString("hex")}`);
    const fd = openSync(tmp, "wx", 0o600);
    try {
      write(fd, `${text.trimEnd()}\n`);
      closeSync(fd);
    } catch (e) {
      quietly(() => closeSync(fd));
      quietly(() => rmSync(tmp, { force: true }));
      throw e;
    }
    let error;
    for (let i = 0; i < TRIES; i++) {
      if (i) sleep(PAUSE_MS);
      try {
        rename(tmp, target);
        return { code: 0 };
      } catch (e) {
        error = e;
      }
    }
    quietly(() => rmSync(tmp, { force: true }));
    return { code: 1, err: `rename failed after ${TRIES} tries: ${error.code ?? error.message}` };
  } catch (e) {
    return { code: e instanceof Usage ? 2 : 1, err: e.message };
  } finally {
    if (lock) quietly(() => rmSync(lock, { force: true }));
  }
}

function invokedDirectly() {
  try {
    const [a, b] = [process.argv[1], fileURLToPath(import.meta.url)].map((p) => realpathSync(p));
    return process.platform === "win32" ? a.toLowerCase() === b.toLowerCase() : a === b;
  } catch {
    return false;
  }
}

if (invokedDirectly()) {
  let result;
  try {
    let text = "";
    process.stdin.setEncoding("utf8");
    for await (const chunk of process.stdin) text += chunk;
    result = writeSnapshot(process.argv.slice(2), text);
  } catch (e) {
    result = { code: 1, err: e.message };
  }
  if (result.out) process.stdout.write(`${result.out}\n`);
  if (result.err) process.stderr.write(`write-snapshot: ${result.err.replace(/\s+/g, " ")}\n`);
  process.exitCode = result.code;
}
