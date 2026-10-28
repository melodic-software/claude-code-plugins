#!/usr/bin/env node
// Drives Claude Code's TUI for the control-claude-code skill.
//
//   node driver.mjs launch --plugin-dir <dir> [--session <name>] [--ttl <seconds>] [--deps-dir <dir>]
//   node driver.mjs wait-for <text> [--timeout <ms>] [--session <name>]
//   node driver.mjs type [<text>] [--key <Name>]... [--session <name>]
//   node driver.mjs screenshot <path.png|path.svg> [--session <name>]
//   node driver.mjs record start <path.mp4|.gif|.png|.cast> [--session <name>]
//   node driver.mjs record stop [--session <name>]
//   node driver.mjs stop [--session <name>]
//   node driver.mjs doctor [--deps-dir <dir>]
//   node driver.mjs ready --plugin-dir <dir> --out <path.jsonl> [--timeout <ms>] [--session <name>] [--deps-dir <dir>]
//   node driver.mjs log <prompt> --plugin-dir <dir> --out <path.jsonl> [--timeout <ms>]
//
// The terminal engine lives in one process, so `launch` starts a detached
// holder that owns the session and listens on a local socket in a 0700
// directory (on Windows, a named pipe whose random name sits in a file there);
// every other session verb sends it one request. The holder exits when Claude
// Code does. The engine package is installed on first use from the committed
// lockfile, never vendored.
//
// `ready` and `log` run Claude Code in print mode with the launch's flags and
// environment and write its stream-json to --out. `ready` prints doctor's lines,
// whether the session answers, and the init event's fields, stops Claude Code
// once the init event arrives, and exits 1 unless `apiKeySource` is "none" and
// the init event lists the plugin under test. `log` runs the prompt to the end,
// stopping Claude Code early only when the init event names an API key. Both
// stop Claude Code at --timeout (ready 120000, log 600000 by default).
//
// Exit: 0 done, 1 the step failed, 2 usage, 3 no session, 4 broken install
// (the message carries the repair line), 5 a directory others can write.
import { spawn, spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import {
  closeSync,
  copyFileSync,
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
} from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { StringDecoder } from 'node:string_decoder';
import { parseArgs } from 'node:util';

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFESTS = ['package.json', 'package-lock.json'];
const ENGINE = '@microsoft/tui-test';
const COMPONENT = 'control-claude-code';
const PLUGIN = 'harness-ops';
const PLUGIN_DATA_ID = 'harness-ops-melodic-software';
const NPM_CI_ARGS = ['ci', '--ignore-scripts', '--no-audit', '--no-fund'];
const NPM_TIMEOUT_MS = 600_000;
const SIGNED = '.signatures-verified';
const FONT_ENTRY = 'noto-sans-symbols-2';
const MAX_TTL_S = 2147483; // setTimeout holds at most 2^31-1 ms
const SOCK_MAX = 100; // a Unix socket path is limited to roughly a hundred bytes
const EXIT_POLL_MS = 1000;
const NATIVE_LOAD = /failed to load the @microsoft\/tui-test native (?:addon|library)[^\n]*/;

// Launch flags and the variables cleared before Claude Code starts.
// Pointer: the Variables table lists ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN,
// ANTHROPIC_CUSTOM_HEADERS, the CLAUDE_CODE_USE_* provider switches and
// CLAUDE_CODE_FORCE_SESSION_PERSISTENCE: https://code.claude.com/docs/en/env-vars#variables
// As of: 2026-10-24. Recheck trigger: a Claude Code release adds or renames a
// provider switch or credential variable, or changes the persistence variable.
// Pointer: with only ANTHROPIC_BASE_URL set, requests route through the gateway
// carrying the saved claude.ai login:
// https://code.claude.com/docs/en/llm-gateway#subscriptions-and-gateways
// As of: 2026-10-24. Recheck trigger: that section changes which credential a
// base URL without a gateway credential sends.
export const LAUNCH_FLAGS = ['--restricted', '--strict-mcp-config'];
export const UNSET_VARS = [
  'ANTHROPIC_API_KEY',
  'ANTHROPIC_AUTH_TOKEN',
  'ANTHROPIC_BASE_URL',
  'ANTHROPIC_CUSTOM_HEADERS',
  'CLAUDE_CODE_USE_BEDROCK',
  'CLAUDE_CODE_USE_VERTEX',
  'CLAUDE_CODE_USE_FOUNDRY',
  'CLAUDE_CODE_USE_MANTLE',
  'CLAUDE_CODE_USE_ANTHROPIC_AWS',
];

/** The Claude Code command line and environment; pure, so it tests with no packages installed. */
export function buildLaunch(config, env) {
  if (!config?.pluginDir) throw new UsageError('launch needs --plugin-dir <dir>');
  const childEnv = { ...env, CLAUDE_CODE_FORCE_SESSION_PERSISTENCE: '1' };
  for (const name of UNSET_VARS) delete childEnv[name];
  return { argv: ['claude', ...LAUNCH_FLAGS, '--plugin-dir', config.pluginDir], env: childEnv };
}

// Print-mode flags, and the init event's key source that Ready requires to be "none".
// Pointer: the stream-json and --verbose rows of
// https://code.claude.com/docs/en/cli-reference#cli-flags, and the ApiKeySource
// table under https://code.claude.com/docs/en/agent-sdk/typescript#apikeysource
// As of: 2026-10-26. Recheck trigger: a Claude Code release changes the
// stream-json flags or the values the init event reports in apiKeySource.
export const PRINT_FLAGS = ['-p', '--output-format', 'stream-json', '--verbose'];
const NO_KEY = 'none';
const READY_PROMPT = 'Reply with the single word ok.';
const READY_TIMEOUT_MS = 120_000;
const LOG_TIMEOUT_MS = 600_000;
const STOP_GRACE_MS = 5000;

/** The print-mode command line: the launch's, then the stream-json flags and the prompt. */
export function buildPrint(config, env, prompt) {
  if (!prompt) throw new UsageError('print mode needs a prompt');
  if (prompt.startsWith('-')) throw new UsageError('a prompt may not start with -');
  const { argv, env: childEnv } = buildLaunch(config, env);
  return { argv: [...argv, ...PRINT_FLAGS, prompt], env: childEnv };
}

class UsageError extends Error {
  code = 2;
}
class NoSession extends Error {
  code = 3;
}
class Broken extends Error {
  code = 4;
  constructor(reason, repair) {
    super(repair ? `${reason}; repair: ${repair}` : reason);
  }
}
class Unsafe extends Error {
  code = 5;
}

/** Creates `dir` 0700 when absent and refuses one that is not a directory owned by you and closed to others. */
function privateDir(dir, { create = true } = {}) {
  if (create) mkdirSync(dir, { recursive: true, mode: 0o700 });
  else if (!existsSync(dir)) return dir;
  if (process.platform === 'win32') return dir; // the per-user profile's ACL guards it
  const st = lstatSync(dir);
  if (!st.isDirectory() || st.uid !== process.getuid() || (st.mode & 0o077) !== 0) {
    throw new Unsafe(`${dir} is not a private directory owned by you (mode 0700); fix or remove it and retry`);
  }
  return dir;
}

// ---- install (docs/conventions/on-demand-dependencies rules 2 and 3) ----

function checkoutRoot() {
  const root = resolve(HERE, '..', '..', '..', '..', '..');
  if (!existsSync(join(root, '.git')) || !existsSync(join(root, '.claude-plugin'))) return null;
  try {
    const ignored = readFileSync(join(root, '.gitignore'), 'utf8').split(/\r?\n/);
    return ignored.some((l) => ['.work/', '.work'].includes(l.trim())) ? root : null;
  } catch {
    return null;
  }
}

function depsBase(explicit, create = true) {
  if (explicit) return { base: privateDir(resolve(explicit), { create }), rule: '--deps-dir' };
  const env = process.env.CLAUDE_PLUGIN_DATA;
  if (env && (basename(env) === PLUGIN || basename(env).startsWith(`${PLUGIN}-`))) {
    return { base: env, rule: 'CLAUDE_PLUGIN_DATA' };
  }
  const root = checkoutRoot();
  if (root) return { base: join(root, '.work', PLUGIN), rule: 'checkout .work/' };
  const config = process.env.CLAUDE_CONFIG_DIR || join(os.homedir(), '.claude');
  return { base: join(config, 'plugins', 'data', PLUGIN_DATA_ID), rule: 'plugin data directory' };
}

const lockKey = () =>
  createHash('sha256').update(readFileSync(join(HERE, 'package-lock.json'))).digest('hex').slice(0, 12);
export const installDir = (base) => join(base, COMPONENT, lockKey());
const hasEngine = (dir) => existsSync(join(dir, 'node_modules', ENGINE, 'package.json'));

const shQ = (s) => `'${s.replaceAll("'", `'\\''`)}'`;
const psQ = (s) => `'${s.replace(/['‘’‚‛]/g, (m) => m + m)}'`;

/** One line that rebuilds the install: POSIX shell, or Windows PowerShell 5.1 on win32. */
export function repairLine(target, platform = process.platform) {
  const flags = NPM_CI_ARGS.slice(1).join(' ');
  const sources = MANIFESTS.map((m) => join(HERE, m));
  if (platform === 'win32') {
    return (
      "& { $ErrorActionPreference = 'Stop'; " +
      `Remove-Item -LiteralPath ${psQ(target)} -Recurse -Force -ErrorAction SilentlyContinue; ` +
      `New-Item -ItemType Directory -Force -Path ${psQ(target)} | Out-Null; ` +
      `Copy-Item -LiteralPath ${sources.map(psQ).join(', ')} -Destination ${psQ(target)}; ` +
      `Set-Location -LiteralPath ${psQ(target)}; npm.cmd ci ${flags} }`
    );
  }
  return (
    `rm -rf ${shQ(target)} && mkdir -p ${shQ(target)} && cp ${sources.map(shQ).join(' ')} ${shQ(target)}/ ` +
    `&& npm ci --prefix ${shQ(target)} ${flags}`
  );
}

function npm(args, cwd) {
  const run = spawnSync('npm', args, {
    cwd,
    encoding: 'utf8',
    timeout: NPM_TIMEOUT_MS,
    shell: process.platform === 'win32',
  });
  const tail = `${run.stderr || ''}${run.stdout || ''}`
    .split(/\r?\n/)
    .filter((l) => l.trim())
    .slice(-3)
    .join(' | ');
  return { ok: !run.error && run.status === 0, why: run.error ? String(run.error.message) : `exit ${run.status}: ${tail}` };
}

/**
 * Runs one short process in the engine and closes it, which loads the native
 * binding; readiness is a load probe, not a version check.
 */
function loadProbe(dir) {
  const url = pathToFileURL(join(dir, 'node_modules', ENGINE, 'dist', 'index.js')).href;
  const code = [
    'try {',
    `  const { TuiTest } = await import(${JSON.stringify(url)});`,
    "  const t = TuiTest.ephemeral('probe');",
    "  await t.run(process.execPath, ['-e', '0']);",
    '  await t.close();',
    '} catch (err) {',
    "  process.stderr.write(String(err?.message ?? err).split('\\n')[0]);",
    '  process.exit(1);',
    '}',
  ].join('\n');
  const run = spawnSync(process.execPath, ['--input-type=module', '-e', code], { encoding: 'utf8', timeout: 60_000 });
  return { ok: run.status === 0, why: (run.stderr || run.error?.message || `exit ${run.status}`).trim() };
}

const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
};

/** Removes the partial installs of processes that are gone. */
function reapPartials(target) {
  const dir = dirname(target);
  const names = existsSync(dir) ? readdirSync(dir) : [];
  for (const name of names) {
    const pid = /\.partial-(\d+)$/.exec(name)?.[1];
    if (pid && !alive(Number(pid))) rmSync(join(dir, name), { recursive: true, force: true });
  }
}

export function ensureInstalled(explicit) {
  const target = installDir(depsBase(explicit).base);
  const repair = repairLine(target);
  if (hasEngine(target) && existsSync(join(target, SIGNED))) return target;
  if (hasEngine(target)) {
    // Installed by the repair line: verify signatures and load once, then mark it.
    const audit = npm(['audit', 'signatures'], target);
    if (!audit.ok) throw new Broken(`npm audit signatures failed (${audit.why})`, repair);
    const probe = loadProbe(target);
    if (!probe.ok) throw new Broken(`the installed engine does not load (${probe.why})`, repair);
    writeFileSync(join(target, SIGNED), `${new Date().toISOString()}\n`);
    return target;
  }
  reapPartials(target);
  const partial = `${target}.partial-${process.pid}`;
  rmSync(partial, { recursive: true, force: true });
  try {
    mkdirSync(partial, { recursive: true });
    for (const m of MANIFESTS) copyFileSync(join(HERE, m), join(partial, m));
    const ci = npm(NPM_CI_ARGS, partial);
    if (!ci.ok || !hasEngine(partial)) throw new Broken(`npm ci failed (${ci.why})`, repair);
    const audit = npm(['audit', 'signatures'], partial);
    if (!audit.ok) throw new Broken(`npm audit signatures failed (${audit.why})`, repair);
    const probe = loadProbe(partial);
    if (!probe.ok) throw new Broken(`the installed engine does not load (${probe.why})`, repair);
    writeFileSync(join(partial, SIGNED), `${new Date().toISOString()}\n`);
    // A failed repair can leave the target without an engine; it holds nothing to keep.
    if (existsSync(target) && !hasEngine(target)) rmSync(target, { recursive: true, force: true });
    renameSync(partial, target);
  } catch (err) {
    rmSync(partial, { recursive: true, force: true });
    if (hasEngine(target) && existsSync(join(target, SIGNED))) return target; // a concurrent install won
    throw err instanceof Broken ? err : new Broken(`install failed (${err.message})`, repair);
  }
  return target;
}

// ---- session transport ----

/** The per-user directory for sockets, pipe names and holder logs; no other account can create it first. */
function runtimeDir(platform) {
  const env = process.env;
  if (platform === 'win32') return join(env.LOCALAPPDATA || join(os.homedir(), 'AppData', 'Local'), 'ccd');
  return env.XDG_RUNTIME_DIR ? join(env.XDG_RUNTIME_DIR, 'ccd') : join(os.homedir(), '.cache', 'ccd');
}

const checkSession = (session) => {
  if (!/^[\w-]{1,32}$/.test(session)) throw new UsageError('--session takes 1-32 letters, digits, _ or -');
};

/**
 * Where a session listens. POSIX: a socket in the private runtime directory.
 * Windows: a named pipe, which any local account could squat under a guessable
 * name, so `launch` records a random suffix in a file only this user reads.
 */
export function endpoint(session, platform = process.platform, { fresh = false } = {}) {
  checkSession(session);
  const dir = privateDir(runtimeDir(platform));
  if (platform !== 'win32') {
    const sock = join(dir, `${session}.sock`);
    if (Buffer.byteLength(sock) > SOCK_MAX) {
      throw new Error(`the socket path ${sock} is too long for a Unix socket; set XDG_RUNTIME_DIR to a short private directory`);
    }
    return { sock, dir };
  }
  const nameFile = join(dir, `${session}.pipe`);
  if (fresh) writeFileSync(nameFile, randomBytes(16).toString('hex'), { mode: 0o600 });
  if (!existsSync(nameFile)) throw new NoSession(`no session '${session}' is running; run launch first`);
  const user = createHash('sha256').update(os.userInfo().username).digest('hex').slice(0, 8);
  const suffix = readFileSync(nameFile, 'utf8').trim();
  return { sock: `\\\\.\\pipe\\ccd-${user}-${session}-${suffix}`, dir, nameFile };
}

const lockFile = (session) => {
  checkSession(session);
  return join(privateDir(runtimeDir(process.platform)), `${session}.lock`);
};
const lockOwner = (lock) => {
  try {
    return Number(readFileSync(lock, 'utf8'));
  } catch {
    return undefined;
  }
};
const release = (lock, pid) => {
  if (lockOwner(lock) === pid) rmSync(lock, { force: true });
};

/**
 * Reserves a session for this launch by creating its lock file exclusively, so
 * two launches cannot both start a holder. A lock whose process is gone is
 * reclaimed; one whose process runs means the session is taken.
 */
function reserve(session) {
  const lock = lockFile(session);
  const taken = new UsageError(`session '${session}' is already running; run stop first`);
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const fd = openSync(lock, 'wx', 0o600);
      writeFileSync(fd, String(process.pid));
      closeSync(fd);
      return lock;
    } catch (err) {
      if (err.code !== 'EEXIST') throw err;
    }
    const owner = lockOwner(lock);
    if (owner === undefined) continue; // released since the create failed
    if (!owner || alive(owner)) throw taken;
    // Re-read before removing, so a lock another launch just reclaimed is left alone.
    if (lockOwner(lock) === owner) rmSync(lock, { force: true });
  }
  throw taken;
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

function request(session, verb, args = {}) {
  const { sock } = endpoint(session);
  return new Promise((done, fail) => {
    const conn = net.createConnection(sock);
    let buf = '';
    conn.on('connect', () => conn.end(`${JSON.stringify({ verb, args })}\n`));
    conn.on('data', (d) => {
      buf += d;
    });
    conn.on('end', () => {
      try {
        const reply = JSON.parse(buf);
        if (reply.ok) done(reply.result);
        else fail(Object.assign(new Error(reply.error), { code: 1 }));
      } catch {
        fail(new Error(`the session holder sent no reply: ${buf.slice(0, 200)}`));
      }
    });
    conn.on('error', (err) => {
      if (['ENOENT', 'ECONNREFUSED'].includes(err.code)) {
        fail(new NoSession(`no session '${session}' is running; run launch first`));
      } else fail(err);
    });
  });
}

// ---- holder: owns the terminal session (internal verb `serve`) ----

const HANDLERS = {
  ping: async () => 'pong',
  'wait-for': async (t, { text, timeout }) => {
    await t.getByText(text).first().wait({ state: 'visible', timeout });
    return `seen: ${text}`;
  },
  type: async (t, { text, keys }) => {
    if (text) await t.type(text);
    if (keys?.length) await t.press(...keys);
    return 'typed';
  },
  screenshot: async (t, { path }) => {
    await t.screenshot(path);
    return path;
  },
  'record-start': async (t, { path }) => {
    await t.startRecording(path);
    return `recording: ${path}`;
  },
  'record-stop': async (t) => t.stopRecording(),
};

/** Whether Claude Code has exited; a state read that fails is not taken as an exit. */
async function childExited(terminal) {
  try {
    const state = await terminal.state();
    return state.exited != null || state.exit_signal != null;
  } catch {
    return false;
  }
}

async function serve(opts) {
  const { sock, nameFile } = endpoint(opts.session);
  const lock = lockFile(opts.session);
  const launch = buildLaunch({ pluginDir: opts['plugin-dir'] }, process.env);
  // The launch reserved the session, so a socket left here belongs to a holder that is gone;
  // one that still answers is refused, before claude starts, rather than unlinked.
  const stale = process.platform !== 'win32' && existsSync(sock);
  if (stale && (await listening(sock))) throw new Error(`another process is serving ${sock}`);
  for (const name of UNSET_VARS) delete process.env[name]; // the engine merges onto this env
  const { TuiTest } = await import(pathToFileURL(join(opts.install, 'node_modules', ENGINE, 'dist', 'index.js')).href);
  const terminal = TuiTest.ephemeral(COMPONENT);
  await terminal.run(launch.argv[0], launch.argv.slice(1), { env: launch.env, cols: 120, rows: 40 });
  if (await childExited(terminal)) throw new Error('claude exited as soon as it started');
  if (stale) rmSync(sock, { force: true });
  // Half-open: the client ends its side after the request, and the reply may take seconds.
  const server = net.createServer({ allowHalfOpen: true }, (conn) => {
    let buf = '';
    conn.on('data', async (d) => {
      buf += d;
      if (!buf.includes('\n')) return;
      let reply;
      try {
        const { verb, args } = JSON.parse(buf);
        if (verb === 'stop') {
          await terminal.closeQuiet();
          free(); // before the reply, so a launch right after stop finds the session free
          conn.end(`${JSON.stringify({ ok: true, result: 'stopped' })}\n`, () => process.exit(0));
          return;
        }
        const handler = HANDLERS[verb];
        if (!handler) throw new Error(`unknown verb ${verb}`);
        reply = { ok: true, result: await handler(terminal, args) };
      } catch (err) {
        reply = { ok: false, error: err.message };
      }
      conn.end(`${JSON.stringify(reply)}\n`);
    });
  });
  const free = () => {
    server.close();
    rmSync(nameFile ?? sock, { force: true });
    release(lock, process.pid); // last, so the next launch cannot reserve before the endpoint is gone
  };
  const exit = () => {
    free();
    process.exit(0);
  };
  const closeAndExit = async () => {
    await terminal.closeQuiet();
    exit();
  };
  setTimeout(closeAndExit, Number(opts.ttl) * 1000).unref();
  // Free the session as soon as Claude Code exits, so the next launch can start one.
  let polling = false;
  setInterval(async () => {
    if (polling) return;
    polling = true;
    if (await childExited(terminal)) {
      console.error('claude exited; the session holder stops');
      await closeAndExit();
    }
    polling = false;
  }, EXIT_POLL_MS);
  server.listen(sock);
}

async function launch(opts) {
  const pluginDir = opts['plugin-dir'] && resolve(opts['plugin-dir']);
  buildLaunch({ pluginDir }, process.env); // usage check before any install
  if (!/^[1-9]\d*$/.test(opts.ttl) || Number(opts.ttl) > MAX_TTL_S) {
    throw new UsageError(`--ttl takes a whole number of seconds up to ${MAX_TTL_S}`);
  }
  // Everything from here on, the pipe name and the log included, happens under the reservation.
  const lock = reserve(opts.session);
  let install;
  let log;
  let holder;
  try {
    try {
      await request(opts.session, 'ping');
      throw new UsageError(`session '${opts.session}' is already running; run stop first`);
    } catch (err) {
      if (!(err instanceof NoSession)) throw err;
    }
    install = ensureInstalled(opts['deps-dir']);
    const { dir } = endpoint(opts.session, process.platform, { fresh: true });
    log = join(dir, `${opts.session}.log`);
    const fd = openSync(log, 'w', 0o600);
    try {
      holder = spawn(
        process.execPath,
        [fileURLToPath(import.meta.url), 'serve', '--session', opts.session, '--plugin-dir', pluginDir, '--install', install, '--ttl', opts.ttl],
        { detached: true, stdio: ['ignore', fd, fd], env: buildLaunch({ pluginDir }, process.env).env },
      );
    } finally {
      closeSync(fd);
    }
    if (!holder.pid) throw new Error('the session holder did not start');
    writeFileSync(lock, String(holder.pid));
  } catch (err) {
    release(lock, process.pid);
    throw err;
  }
  let exited = false;
  holder.on('exit', () => {
    exited = true;
  });
  holder.unref();
  for (const deadline = Date.now() + 30_000; Date.now() < deadline && !exited; ) {
    try {
      await request(opts.session, 'ping');
      return `launched session '${opts.session}' (holder pid ${holder.pid}, log ${log})`;
    } catch {
      await new Promise((r) => setTimeout(r, 250));
    }
  }
  // A holder that never answered would keep the session reserved where stop cannot reach it.
  if (!exited) holder.kill();
  release(lock, holder.pid);
  const text = existsSync(log) ? readFileSync(log, 'utf8') : '';
  const native = NATIVE_LOAD.exec(text)?.[0];
  if (native) throw new Broken(`the installed engine does not load (${native})`, repairLine(install));
  const tail = text.trim().split('\n').slice(-5).join(' | ');
  const why = exited ? 'the session holder exited before the session started' : 'the session did not start within 30 s';
  throw new Error(`${why}${tail ? `: ${tail}` : ''}`);
}

/** The font probe harness-ops declares in prerequisites.json, or undefined when it cannot be read. */
function fontProbe() {
  try {
    const declared = JSON.parse(readFileSync(join(HERE, '..', '..', '..', 'prerequisites.json'), 'utf8'));
    return declared.requires.find((entry) => entry.id === FONT_ENTRY)?.detect?.probe;
  } catch {
    return undefined;
  }
}

function doctor(opts) {
  const { base, rule } = depsBase(opts['deps-dir'], false);
  const target = installDir(base);
  const lines = [`install base: ${base} (${rule})`, `install dir: ${target}`];
  let status = 0;
  if (!hasEngine(target)) {
    lines.push('engine: not installed; launch installs it on first use');
  } else {
    const probe = loadProbe(target);
    lines.push(`engine: ${probe.ok ? 'loads' : `BROKEN (${probe.why}); repair: ${repairLine(target)}`}`);
    lines.push(`signatures: ${existsSync(join(target, SIGNED)) ? 'verified at install' : 'not yet verified; launch verifies them'}`);
    if (!probe.ok) status = 4;
  }
  const unverified = 'capture proceeds, and a glyph missing from the installed fonts draws as a box';
  const probe = fontProbe();
  const fc = probe && spawnSync(probe.args[0], probe.args.slice(1), { encoding: 'utf8', timeout: 30_000 });
  if (!probe) {
    lines.push(`font: unverified (no ${FONT_ENTRY} probe in prerequisites.json); ${unverified}`);
  } else if (fc.error || fc.status !== 0) {
    lines.push(`font: unverified (no ${probe.args[0]}); ${unverified}`);
  } else {
    const font = probe.pattern;
    const found = new RegExp(font).test(fc.stdout);
    lines.push(`font: ${font} ${found ? 'found' : 'MISSING; some status glyphs draw as boxes in captures'}`);
  }
  return { text: lines.join('\n'), status };
}

// ---- print mode: the init event and the stream-json log ----

/**
 * Runs Claude Code in print mode, copies its stdout to `out`, and resolves with
 * the init event (undefined when none came), the exit, and whether the run hit
 * `timeoutMs`. Claude Code and every process it started are stopped as soon as
 * `stopAt(init)` holds or the time is up: SIGTERM, then SIGKILL after a grace.
 */
function runPrint({ pluginDir, out, prompt, stopAt, timeoutMs }) {
  const { argv, env } = buildPrint({ pluginDir }, process.env, prompt);
  const fd = openSync(out, 'w', 0o600);
  let open = true;
  const closeOut = () => {
    if (open) closeSync(fd);
    open = false;
  };
  return new Promise((done, fail) => {
    // Its own process group on POSIX, so a stop reaches a wrapper's children too.
    const group = process.platform !== 'win32';
    const child = spawn(argv[0], argv.slice(1), { env, detached: group, stdio: ['ignore', 'pipe', 'inherit'] });
    const decoder = new StringDecoder('utf8');
    let buf = '';
    let init;
    let timedOut = false;
    let killTimer;
    const send = (sig) => {
      try {
        if (group && child.pid) process.kill(-child.pid, sig);
        else child.kill(sig);
      } catch {
        // already gone
      }
    };
    const stop = () => {
      if (killTimer) return;
      send('SIGTERM');
      killTimer = setTimeout(() => send('SIGKILL'), STOP_GRACE_MS);
    };
    const deadline = setTimeout(() => {
      timedOut = true;
      stop();
    }, timeoutMs);
    child.stdout.on('data', (d) => {
      if (open) {
        try {
          writeSync(fd, d);
        } catch (err) {
          closeOut();
          stop();
          fail(new Error(`cannot write ${out}: ${err.message}`));
          return;
        }
      }
      if (init) return;
      buf += decoder.write(d);
      for (let nl = buf.indexOf('\n'); nl >= 0 && !init; nl = buf.indexOf('\n')) {
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        try {
          const event = JSON.parse(line);
          if (event?.type === 'system' && event.subtype === 'init') init = event;
        } catch {
          // a line that is not JSON is kept in the log and skipped here
        }
      }
      if (init && stopAt(init)) stop();
    });
    child.on('error', (err) => {
      clearTimeout(deadline);
      clearTimeout(killTimer);
      closeOut();
      fail(err.code === 'ENOENT' ? new Error('claude is not on PATH') : err);
    });
    child.on('close', (code, signal) => {
      clearTimeout(deadline);
      clearTimeout(killTimer);
      closeOut();
      done({ init, code, signal, timedOut });
    });
  });
}

function printTarget(opts, verb, defaultTimeout) {
  const pluginDir = opts['plugin-dir'] && resolve(opts['plugin-dir']);
  if (!pluginDir) throw new UsageError(`${verb} needs --plugin-dir <dir>`);
  if (!opts.out) throw new UsageError(`${verb} needs --out <path.jsonl>`);
  if (opts.timeout !== undefined && !/^[1-9]\d*$/.test(opts.timeout)) {
    throw new UsageError('--timeout takes a whole number of milliseconds');
  }
  if (!existsSync(pluginDir)) throw new UsageError(`--plugin-dir ${pluginDir} does not exist`);
  const timeoutMs = Math.min(opts.timeout === undefined ? defaultTimeout : Number(opts.timeout), MAX_TTL_S * 1000);
  return { pluginDir, out: resolve(opts.out), timeoutMs };
}

const keyLine = (init) =>
  init.apiKeySource === NO_KEY ? [] : [`refused: apiKeySource is ${JSON.stringify(init.apiKeySource)}, not "none"; drive nothing`];

/** The name in a plugin directory's manifest, or undefined when it has none. */
function manifestName(pluginDir) {
  try {
    return JSON.parse(readFileSync(join(pluginDir, '.claude-plugin', 'plugin.json'), 'utf8')).name;
  } catch {
    return undefined;
  }
}

const realOrSelf = (p) => {
  try {
    return realpathSync(p);
  } catch {
    return p;
  }
};

/** Whether the init event lists the plugin under test, by manifest name or by path. */
function loaded(init, pluginDir) {
  const name = manifestName(pluginDir);
  const dir = realOrSelf(pluginDir);
  return (init.plugins ?? []).some((p) => (name && p?.name === name) || (p?.path && realOrSelf(p.path) === dir));
}

async function sessionLine(session) {
  try {
    await request(session, 'ping');
    return `session '${session}': running`;
  } catch (err) {
    if (err instanceof NoSession) return `session '${session}': not running`;
    throw err;
  }
}

async function ready(opts) {
  const { pluginDir, out, timeoutMs } = printTarget(opts, 'ready', READY_TIMEOUT_MS);
  const health = doctor(opts);
  const lines = [health.text, await sessionLine(opts.session)];
  const { init, timedOut } = await runPrint({ pluginDir, out, prompt: READY_PROMPT, stopAt: () => true, timeoutMs });
  lines.push(`stream: ${out}`);
  if (!init) {
    lines.push(timedOut ? `init: no init event within ${timeoutMs} ms` : 'init: no init event');
    return { text: lines.join('\n'), status: health.status || 1 };
  }
  const plugins = (init.plugins ?? []).map((p) => p?.name).join(', ') || 'none';
  const hasPlugin = loaded(init, pluginDir);
  lines.push(`claude_code_version: ${init.claude_code_version}`, `apiKeySource: ${init.apiKeySource}`, `plugins: ${plugins}`, ...keyLine(init));
  if (!hasPlugin) lines.push(`refused: the init event does not list the plugin at ${pluginDir}; drive nothing`);
  return { text: lines.join('\n'), status: health.status || (init.apiKeySource === NO_KEY && hasPlugin ? 0 : 1) };
}

async function log(opts, prompt) {
  const { pluginDir, out, timeoutMs } = printTarget(opts, 'log', LOG_TIMEOUT_MS);
  const run = await runPrint({ pluginDir, out, prompt, stopAt: (i) => i.apiKeySource !== NO_KEY, timeoutMs });
  const ended = run.timedOut ? `stopped after ${timeoutMs} ms` : run.signal ? `stopped by ${run.signal}` : `exit ${run.code}`;
  if (!run.init) return { text: `log: ${out} (claude ${ended}); init: no init event`, status: 1 };
  const lines = [`log: ${out} (claude ${ended}, apiKeySource ${run.init.apiKeySource})`, ...keyLine(run.init)];
  const clean = run.init.apiKeySource === NO_KEY && run.code === 0 && !run.timedOut;
  return { text: lines.join('\n'), status: clean ? 0 : 1 };
}

// ---- CLI ----

const OPTIONS = {
  session: { type: 'string', default: 'default' },
  'plugin-dir': { type: 'string' },
  'deps-dir': { type: 'string' },
  install: { type: 'string' },
  ttl: { type: 'string', default: '3600' },
  timeout: { type: 'string' },
  key: { type: 'string', multiple: true },
  out: { type: 'string' },
};

const VERBS = {
  launch: (o) => launch(o),
  'wait-for': (o, [text]) => {
    if (!text) throw new UsageError('wait-for needs <text>');
    if (o.timeout !== undefined && !/^\d+$/.test(o.timeout)) throw new UsageError('--timeout takes a whole number of milliseconds');
    return request(o.session, 'wait-for', { text, timeout: o.timeout === undefined ? undefined : Number(o.timeout) });
  },
  type: (o, [text]) => {
    if (!text && !o.key) throw new UsageError('type needs <text> or --key <Name>');
    return request(o.session, 'type', { text, keys: o.key });
  },
  screenshot: (o, [path]) => {
    if (!path) throw new UsageError('screenshot needs <path>');
    return request(o.session, 'screenshot', { path: resolve(path) });
  },
  record: (o, [action, path]) => {
    if (action === 'start' && path) return request(o.session, 'record-start', { path: resolve(path) });
    if (action === 'stop') return request(o.session, 'record-stop');
    throw new UsageError('record takes start <path> or stop');
  },
  stop: (o) => request(o.session, 'stop'),
  doctor: (o) => doctor(o),
  ready: (o) => ready(o),
  log: (o, [prompt]) => log(o, prompt),
  serve: (o) => serve(o),
};

const ARITY = { 'wait-for': 1, type: 1, screenshot: 1, record: 2, log: 1 };

async function main(argv) {
  let parsed;
  try {
    parsed = parseArgs({ args: argv, options: OPTIONS, allowPositionals: true });
  } catch (err) {
    throw new UsageError(err.message);
  }
  const [verb, ...rest] = parsed.positionals;
  const run = VERBS[verb];
  if (!run) throw new UsageError(`verbs: ${Object.keys(VERBS).filter((v) => v !== 'serve').join(', ')}`);
  if (rest.length > (ARITY[verb] ?? 0)) throw new UsageError(`${verb} got extra arguments: ${rest.join(' ')}`);
  const out = await run(parsed.values, rest);
  if (out && typeof out === 'object') {
    console.log(out.text);
    return out.status;
  }
  if (out !== undefined) console.log(out);
  return 0;
}

const invoked = process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url);
if (invoked) {
  main(process.argv.slice(2)).then(
    (status) => {
      if (status) process.exitCode = status;
    },
    (err) => {
      console.error(`control-claude-code driver: ${err.message}`);
      process.exitCode = typeof err.code === 'number' ? err.code : 1;
    },
  );
}

export { main };
