#!/usr/bin/env node
// Launch broker for the control-claude-code driver: runs `launch`, `ready` and
// `log` where the broker runs, for a driver whose CCD_BROKER_SOCK names it.
//
//   <key> | node broker.mjs --socket <path> --driver <abs driver.mjs> --root <dir>... [--deps-dir <dir>]
//
// Each connection sends one JSON line `{verb, args}`; the broker answers with
// JSON lines `{stdout}` and `{stderr}` as the driver writes them, then `{exit}`.
// It takes only the verbs in VERBS, each with the options its validator allows:
// a session name of 1-32 letters, digits, _ or -, and --plugin-dir and --out
// paths that resolve inside a --root. It runs the --driver it was started with,
// by absolute path, with --unattended, and hands that one child the key read
// from stdin as ANTHROPIC_API_KEY; the broker's own environment never holds it.
//
// Exit: 0 stopped by a signal, 2 usage.
import { spawn } from 'node:child_process';
import { existsSync, lstatSync, readFileSync, realpathSync, rmSync, statSync } from 'node:fs';
import net from 'node:net';
import { basename, dirname, isAbsolute, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { StringDecoder } from 'node:string_decoder';
import { parseArgs } from 'node:util';

const REQUEST_MAX = 64 * 1024;
const CREDENTIALS = ['ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN'];

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
    if (!/^[\w-]{1,32}$/.test(value)) throw new Refused(`--${name} takes 1-32 letters, digits, _ or -`);
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
 * `roots` are real paths. The result starts with the verb and always carries --unattended.
 */
export function driverArgs(request, roots, depsDir) {
  if (!request || typeof request !== 'object') throw new Refused('a request is one JSON object {verb, args}');
  const { verb: name, args } = request;
  if (typeof name !== 'string' || !Object.hasOwn(VERBS, name)) throw new Refused(`the broker runs only ${Object.keys(VERBS).join(', ')}`);
  if (!Array.isArray(args) || !args.every((a) => typeof a === 'string')) throw new Refused('args must be a list of strings');
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
    if (passed !== undefined) out.push(`--${opt}`, passed);
  }
  out.push('--unattended');
  if (depsDir && name !== 'log') out.push('--deps-dir', depsDir);
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
function answer(conn, { driver, roots, depsDir, key }) {
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
      args = driverArgs(request, roots, depsDir);
    } catch (err) {
      send({ stderr: `launch broker: refused: ${err.message}\n` });
      return finish(2);
    }
    const child = spawn(process.execPath, [driver, ...args], { env: childEnv(process.env, key), stdio: ['ignore', 'pipe', 'pipe'] });
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

/** Checks the start options and returns what the server needs. */
export function startConfig(values, key) {
  const { socket, driver, root = [], 'deps-dir': depsDir } = values;
  if (!socket || !isAbsolute(socket)) throw new Usage('--socket takes an absolute path');
  if (!driver || !isAbsolute(driver) || !existsSync(driver)) throw new Usage('--driver takes the absolute path of an existing driver.mjs');
  if (!root.length) throw new Usage('--root takes at least one directory');
  if (depsDir && !isAbsolute(depsDir)) throw new Usage('--deps-dir takes an absolute path');
  if (!key) throw new Usage('the key for the driver child is read from stdin, which was empty');
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
  const dir = lstatSync(dirname(socket));
  if (!dir.isDirectory() || dir.uid !== process.getuid() || (dir.mode & 0o077) !== 0) {
    throw new Usage(`${dirname(socket)} is not a private directory owned by you (mode 0700)`);
  }
  return { socket, driver: realDriver, roots, depsDir, key };
}

async function main(argv) {
  const { values } = parseArgs({
    args: argv,
    options: { socket: { type: 'string' }, driver: { type: 'string' }, root: { type: 'string', multiple: true }, 'deps-dir': { type: 'string' } },
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
