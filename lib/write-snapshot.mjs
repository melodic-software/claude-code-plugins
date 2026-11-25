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
    if (!has(body) || has(current)) {
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
