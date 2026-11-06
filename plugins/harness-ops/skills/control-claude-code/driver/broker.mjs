#!/usr/bin/env node
// Launch broker for the control-claude-code driver: runs `launch`, `ready` and
// `log` where the broker runs, for a driver whose CCD_BROKER_SOCK names it.
//
//   <key> | node broker.mjs --socket <path> --driver <abs driver.mjs> --root <dir>... [--deps-dir <dir>] [--in-sandbox]
//
// Each connection sends one JSON line `{verb, args}`; the broker answers with
// JSON lines `{stdout}` and `{stderr}` as the driver writes them, then `{exit}`.
// It takes only the verbs in VERBS, each with the options its validator allows:
// a session name of 1-32 letters, digits, _ or -, not starting with -, and
// --plugin-dir and --out paths that resolve inside a --root, each passed on as
// one `--opt=value` argument. It runs the --driver it was started with, by
// absolute path, with --unattended, and hands that one child the key read from
// stdin as ANTHROPIC_API_KEY; the broker's own environment never holds it.
// Started with --in-sandbox, it also adds --in-sandbox to every request, so
// the driven session gets Bash and no scrub; a request cannot set it.
//
// It starts only on a dummy key (KEY_PREFIX), and only when it cannot write the
// driver's directory, the driver's config directory or --deps-dir: the workflow
// mounts all three read-only, so the PR code beside the broker cannot change
// what the broker runs. Our rule: the broker also starts only from the --driver's
// own directory, so the broker itself sits where it cannot write, and it imports
// no module from beside it, so nothing there runs before these checks.
//
// Exit: 0 stopped by a signal, 2 usage.
import { spawn } from 'node:child_process';
import { accessSync, constants, existsSync, lstatSync, readFileSync, realpathSync, rmSync, statSync } from 'node:fs';
import net from 'node:net';
import { basename, dirname, isAbsolute, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { StringDecoder } from 'node:string_decoder';
import { parseArgs } from 'node:util';

const SELF_DIR = dirname(realpathSync(fileURLToPath(import.meta.url)));
const REQUEST_MAX = 64 * 1024;
// The driver's session rule (driver.mjs SESSION), kept here so the broker imports nothing from beside it.
export const SESSION = /^[A-Za-z0-9_][\w-]{0,31}$/;
const CREDENTIALS = ['ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN'];
// Our rule: the broker hands the driven side a dummy key only. A key must carry this prefix, and one
// shaped like a real Anthropic key is refused outright, so a misconfigured job cannot pass the real one.
export const KEY_PREFIX = 'ccd-dummy-';
const REAL_KEY = 'sk-ant-';

export class Refused extends Error {}

const inside = (roots, path) => roots.some((root) => path === root || path.startsWith(root + sep));

const absolute = (name, value) => {
  if (!isAbsolute(value) || normalize(value) !== value || value.split(sep).includes('..')) {
    throw new Refused(`--${name} must be an absolute, normalized path`);
  }
  return value;
};

/** Validators by option kind; each returns the value to pass on or throws Refused. */
const KINDS = {
  session: (name, value) => {
    if (!SESSION.test(value)) throw new Refused(`--${name} takes 1-32 letters, digits, _ or -, not starting with -`);
    return value;
  },
  count: (name, value) => {
    if (!/^[1-9]\d{0,9}$/.test(value)) throw new Refused(`--${name} takes a whole number`);
    return value;
  },
  dir: (name, value, roots) => {
    absolute(name, value);
    let real;
    try {
      real = realpathSync(value);
    } catch {
      throw new Refused(`--${name} ${value} does not exist`);
    }
    if (!inside(roots, real) || !statSync(real).isDirectory()) throw new Refused(`--${name} must be a directory inside an allowed root`);
    return real;
  },
  file: (name, value, roots) => {
    absolute(name, value);
    let parent;
    try {
      parent = realpathSync(dirname(value));
    } catch {
      throw new Refused(`--${name}'s directory does not exist`);
    }
    if (!inside(roots, parent)) throw new Refused(`--${name} must be inside an allowed root`);
    const path = `${parent}${sep}${basename(value)}`;
    if (lstatSync(path, { throwIfNoEntry: false })?.isSymbolicLink()) throw new Refused(`--${name} may not be a symbolic link`);
    return path;
  },
  flag: () => undefined, // --unattended: the broker always adds it
};

const verb = (options, { prompt = false, required = [] } = {}) => ({ options, prompt, required });
const COMMON = { 'plugin-dir': 'dir', session: 'session', unattended: 'flag' };

/** Each verb the broker runs, with the kind of each option it accepts. */
export const VERBS = {
  launch: verb({ ...COMMON, ttl: 'count' }, { required: ['plugin-dir'] }),
  ready: verb({ ...COMMON, out: 'file', timeout: 'count' }, { required: ['plugin-dir', 'out'] }),
  log: verb({ ...COMMON, out: 'file', timeout: 'count' }, { prompt: true, required: ['plugin-dir', 'out'] }),
};

/**
 * The driver arguments a request maps to, after the verb's validator passes every option, or Refused.
 * `roots` are real paths. The result starts with the verb and always carries --unattended, and
 * --in-sandbox when the broker was started with it.
 */
export function driverArgs(request, roots, depsDir, inSandbox = false) {
  if (!request || typeof request !== 'object') throw new Refused('a request is one JSON object {verb, args}');
  const { verb: name, args } = request;
  if (typeof name !== 'string' || !Object.hasOwn(VERBS, name)) throw new Refused(`the broker runs only ${Object.keys(VERBS).join(', ')}`);
  if (!Array.isArray(args) || !args.every((a) => typeof a === 'string')) throw new Refused('args must be a list of strings');
  if (args.some((a) => a.includes('\0'))) throw new Refused('an argument may not hold a NUL character');
  const spec = VERBS[name];
  const options = Object.fromEntries(
    Object.entries(spec.options).map(([opt, kind]) => [opt, { type: kind === 'flag' ? 'boolean' : 'string' }]),
  );
  let parsed;
  try {
    parsed = parseArgs({ args, options, allowPositionals: spec.prompt, strict: true });
  } catch (err) {
    throw new Refused(err.message);
  }
  const out = [name];
  if (spec.prompt && parsed.positionals.length !== 1) throw new Refused(`${name} takes exactly one prompt`);
  for (const opt of spec.required) if (parsed.values[opt] === undefined) throw new Refused(`${name} needs --${opt}`);
  for (const [opt, value] of Object.entries(parsed.values)) {
    const passed = KINDS[spec.options[opt]](opt, value, roots);
    if (passed !== undefined) out.push(`--${opt}=${passed}`);
  }
  out.push('--unattended');
  if (inSandbox) out.push('--in-sandbox');
  if (depsDir && name !== 'log') out.push(`--deps-dir=${depsDir}`);
  if (spec.prompt) {
    const [prompt] = parsed.positionals;
    if (!prompt || prompt.startsWith('-')) throw new Refused('the prompt must be non-empty and may not start with -');
    out.push('--', prompt);
  }
  return out;
}

/** The driver child's environment: the broker's, less every credential and the broker socket, plus the key. */
export function childEnv(env, key) {
  const child = { ...env };
  for (const name of [...CREDENTIALS, 'CCD_BROKER_SOCK']) delete child[name];
  child.ANTHROPIC_API_KEY = key;
  return child;
}

/** Serves one connection: reads one request line, runs the driver, streams its output and exit back. */
function answer(conn, { driver, roots, depsDir, key, inSandbox }) {
  let buf = '';
  let started = false;
  let finished = false;
  const send = (reply) => {
    if (!finished && !conn.destroyed) conn.write(`${JSON.stringify(reply)}\n`);
  };
  const finish = (code) => {
    send({ exit: code });
    finished = true;
    conn.end();
  };
  conn.setEncoding('utf8');
  conn.on('error', () => {});
  conn.on('data', (d) => {
    if (started) return;
    buf += d;
    const nl = buf.indexOf('\n');
    if (nl < 0 && buf.length <= REQUEST_MAX) return;
    started = true;
    let args;
    try {
      if (nl < 0 || nl > REQUEST_MAX) throw new Refused(`a request is one line of at most ${REQUEST_MAX} bytes`);
      let request;
      try {
        request = JSON.parse(buf.slice(0, nl));
      } catch {
        throw new Refused('a request is one JSON object {verb, args}');
      }
      args = driverArgs(request, roots, depsDir, inSandbox);
    } catch (err) {
      send({ stderr: `launch broker: refused: ${err.message}\n` });
      return finish(2);
    }
    let child;
    try {
      child = spawn(process.execPath, [driver, ...args], { env: childEnv(process.env, key), stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (err) {
      send({ stderr: `launch broker: the driver did not start (${err.message})\n` });
      return finish(1);
    }
    for (const stream of ['stdout', 'stderr']) {
      const decoder = new StringDecoder('utf8');
      const relay = (text) => text && send({ [stream]: text });
      child[stream].on('data', (chunk) => relay(decoder.write(chunk)));
      child[stream].on('end', () => relay(decoder.end()));
    }
    child.on('error', (err) => {
      send({ stderr: `launch broker: the driver did not start (${err.message})\n` });
      finish(1);
    });
    child.on('close', (code) => finish(Number.isInteger(code) ? code : 1));
  });
}

/** Whether a process accepts connections on `sock`. */
const listening = (sock) =>
  new Promise((done) => {
    const conn = net.createConnection(sock);
    conn.on('connect', () => {
      conn.destroy();
      done(true);
    });
    conn.on('error', () => done(false));
  });

class Usage extends Error {}

const writable = (dir) => {
  try {
    accessSync(dir, constants.W_OK);
    return true;
  } catch {
    return false;
  }
};

/** Checks the start options and returns what the server needs; `selfDir` is the broker's own real directory. */
export function startConfig(values, key, selfDir = SELF_DIR) {
  const { socket, driver, root = [], 'deps-dir': depsDir, 'in-sandbox': inSandbox = false } = values;
  if (!socket || !isAbsolute(socket)) throw new Usage('--socket takes an absolute path');
  if (!driver || !isAbsolute(driver) || !existsSync(driver)) throw new Usage('--driver takes the absolute path of an existing driver.mjs');
  if (!root.length) throw new Usage('--root takes at least one directory');
  if (depsDir && !isAbsolute(depsDir)) throw new Usage('--deps-dir takes an absolute path');
  if (!key) throw new Usage('the key for the driver child is read from stdin, which was empty');
  if (key.startsWith(REAL_KEY)) throw new Usage(`the key on stdin looks like a real Anthropic key (${REAL_KEY}); the broker takes only a dummy`);
  if (!key.startsWith(KEY_PREFIX) || key.length === KEY_PREFIX.length) throw new Usage(`the key on stdin must be a dummy starting with ${KEY_PREFIX}`);
  const roots = root.map((r) => {
    if (!isAbsolute(r)) throw new Usage(`--root ${r} is not an absolute path`);
    try {
      return realpathSync(r);
    } catch {
      throw new Usage(`--root ${r} does not exist`);
    }
  });
  const realDriver = realpathSync(driver);
  if (inside(roots, realDriver)) throw new Usage('--driver may not sit inside a --root: the broker runs only a driver the roots cannot change');
  if (dirname(realDriver) !== selfDir) throw new Usage(`--driver must sit in the broker's own directory ${selfDir}`);
  if (depsDir && !existsSync(depsDir)) throw new Usage(`--deps-dir ${depsDir} does not exist; pre-fill it before the broker starts`);
  const realDeps = depsDir && realpathSync(depsDir);
  if (realDeps && inside(roots, realDeps)) throw new Usage('--deps-dir may not sit inside a --root');
  for (const dir of [dirname(realDriver), join(dirname(realDriver), '..', 'config'), realDeps].filter(Boolean)) {
    if (writable(dir)) throw new Usage(`${dir} is writable by the broker; mount it read-only so nothing beside the broker can change what it runs`);
  }
  const dir = lstatSync(dirname(socket));
  if (!dir.isDirectory() || dir.uid !== process.getuid() || (dir.mode & 0o077) !== 0) {
    throw new Usage(`${dirname(socket)} is not a private directory owned by you (mode 0700)`);
  }
  return { socket, driver: realDriver, roots, depsDir, key, inSandbox };
}

async function main(argv) {
  const { values } = parseArgs({
    args: argv,
    options: { socket: { type: 'string' }, driver: { type: 'string' }, root: { type: 'string', multiple: true }, 'deps-dir': { type: 'string' }, 'in-sandbox': { type: 'boolean' } },
  });
  const config = startConfig(values, readFileSync(0, 'utf8').trim());
  if (existsSync(config.socket)) {
    if (await listening(config.socket)) throw new Usage(`another process is serving ${config.socket}`);
    rmSync(config.socket, { force: true });
  }
  const server = net.createServer((conn) => answer(conn, config));
  const close = () => {
    server.close();
    rmSync(config.socket, { force: true });
    process.exit(0);
  };
  process.on('SIGTERM', close);
  process.on('SIGINT', close);
  server.listen(config.socket, () => console.error(`launch broker: listening on ${config.socket}`));
}

const invoked = process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url);
if (invoked) {
  main(process.argv.slice(2)).catch((err) => {
    console.error(`launch broker: ${err.message}`);
    process.exitCode = 2;
  });
}
