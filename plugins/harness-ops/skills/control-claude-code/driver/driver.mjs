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
//
// The terminal engine lives in one process, so `launch` starts a detached
// holder that owns the session and listens on a local socket in a 0700
// directory; every other verb sends it one request. The engine package is
// installed on first use from the committed lockfile, never vendored.
//
// Exit: 0 done, 1 the step failed, 2 usage, 3 no session, 4 broken install
// (the message carries the repair line).
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  closeSync,
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
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
const FONT = 'Noto Sans Symbols 2';

// Launch flags and the variables cleared before Claude Code starts.
// Pointer: the Environment variables page lists ANTHROPIC_API_KEY,
// ANTHROPIC_AUTH_TOKEN, the CLAUDE_CODE_USE_* provider switches and
// CLAUDE_CODE_FORCE_SESSION_PERSISTENCE: https://code.claude.com/docs/en/env-vars
// As of: 2026-10-24. Recheck trigger: a Claude Code release adds or renames a
// provider switch or credential variable, or changes the persistence variable.
export const LAUNCH_FLAGS = ['--restricted', '--strict-mcp-config'];
export const UNSET_VARS = [
  'ANTHROPIC_API_KEY',
  'ANTHROPIC_AUTH_TOKEN',
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

function depsBase(explicit) {
  if (explicit) return { base: resolve(explicit), rule: '--deps-dir' };
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
const installDir = (base) => join(base, COMPONENT, lockKey());
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
      `npm.cmd ci --prefix ${psQ(target)} ${flags} }`
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

/** Starts the engine and closes it; readiness is a load probe, not a version check. */
function loadProbe(dir) {
  const url = pathToFileURL(join(dir, 'node_modules', ENGINE, 'dist', 'index.js')).href;
  const code = `const { TuiTest } = await import(${JSON.stringify(url)}); await TuiTest.ephemeral('probe').closeQuiet();`;
  const run = spawnSync(process.execPath, ['--input-type=module', '-e', code], { encoding: 'utf8', timeout: 60_000 });
  return { ok: run.status === 0, why: (run.stderr || run.error?.message || '').trim().split('\n').slice(-1)[0] };
}

function ensureInstalled(explicit) {
  const target = installDir(depsBase(explicit).base);
  const repair = repairLine(target);
  if (hasEngine(target) && existsSync(join(target, SIGNED))) return target;
  if (hasEngine(target)) {
    // Installed by the repair line: verify signatures once, then mark it.
    const audit = npm(['audit', 'signatures'], target);
    if (!audit.ok) throw new Broken(`npm audit signatures failed (${audit.why})`, repair);
    writeFileSync(join(target, SIGNED), `${new Date().toISOString()}\n`);
    return target;
  }
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
    renameSync(partial, target);
  } catch (err) {
    rmSync(partial, { recursive: true, force: true });
    if (hasEngine(target) && existsSync(join(target, SIGNED))) return target; // a concurrent install won
    throw err instanceof Broken ? err : new Broken(`install failed (${err.message})`, repair);
  }
  return target;
}

// ---- session transport ----

function socketPath(session) {
  if (!/^[\w-]{1,32}$/.test(session)) throw new UsageError('--session takes 1-32 letters, digits, _ or -');
  const user = createHash('sha256').update(os.userInfo().username).digest('hex').slice(0, 8);
  if (process.platform === 'win32') return { sock: `\\\\.\\pipe\\ccd-${user}-${session}`, dir: os.tmpdir() };
  // Short and private: a Unix socket path is limited to roughly a hundred bytes.
  const dir = join(os.tmpdir(), `ccd-${user}`);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const st = lstatSync(dir);
  if (!st.isDirectory() || st.uid !== process.getuid() || (st.mode & 0o077) !== 0) {
    throw new Broken(`${dir} is not a private directory owned by you; remove it and retry`);
  }
  return { sock: join(dir, `${session}.sock`), dir };
}

function request(session, verb, args = {}) {
  const { sock } = socketPath(session);
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

async function serve(opts) {
  const { sock } = socketPath(opts.session);
  const launch = buildLaunch({ pluginDir: opts['plugin-dir'] }, process.env);
  for (const name of UNSET_VARS) delete process.env[name]; // the engine merges onto this env
  const { TuiTest } = await import(pathToFileURL(join(opts.install, 'node_modules', ENGINE, 'dist', 'index.js')).href);
  const terminal = TuiTest.ephemeral(COMPONENT);
  await terminal.run(launch.argv[0], launch.argv.slice(1), { env: launch.env, cols: 120, rows: 40 });
  if (process.platform !== 'win32' && existsSync(sock)) unlinkSync(sock);
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
          conn.end(`${JSON.stringify({ ok: true, result: 'stopped' })}\n`, () => shutdown());
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
  const shutdown = () => {
    server.close();
    if (process.platform !== 'win32') rmSync(sock, { force: true });
    process.exit(0);
  };
  setTimeout(async () => {
    await terminal.closeQuiet();
    shutdown();
  }, Number(opts.ttl) * 1000).unref();
  server.listen(sock);
}

async function launch(opts) {
  const pluginDir = opts['plugin-dir'] && resolve(opts['plugin-dir']);
  buildLaunch({ pluginDir }, process.env); // usage check before any install
  const { dir } = socketPath(opts.session);
  try {
    await request(opts.session, 'ping');
    throw new UsageError(`session '${opts.session}' is already running; run stop first`);
  } catch (err) {
    if (!(err instanceof NoSession)) throw err;
  }
  const install = ensureInstalled(opts['deps-dir']);
  const log = join(dir, `${opts.session}.log`);
  const fd = openSync(log, 'w', 0o600);
  const holder = spawn(
    process.execPath,
    [fileURLToPath(import.meta.url), 'serve', '--session', opts.session, '--plugin-dir', pluginDir, '--install', install, '--ttl', opts.ttl],
    { detached: true, stdio: ['ignore', fd, fd], env: buildLaunch({ pluginDir }, process.env).env },
  );
  closeSync(fd);
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
  const tail = existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').slice(-5).join(' | ') : '';
  throw new Error(`the session did not start within 30 s${tail ? `: ${tail}` : ''}`);
}

function doctor(opts) {
  const { base, rule } = depsBase(opts['deps-dir']);
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
  const fc = spawnSync('fc-list', [':', 'family'], { encoding: 'utf8', timeout: 30_000 });
  if (fc.error || fc.status !== 0) {
    lines.push(`font: unverified (no fc-list); capture proceeds, and a glyph missing from the installed fonts draws as a box`);
  } else {
    lines.push(`font: ${fc.stdout.includes(FONT) ? `${FONT} found` : `${FONT} MISSING; some status glyphs draw as boxes in captures`}`);
  }
  return { text: lines.join('\n'), status };
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
};

const VERBS = {
  launch: (o) => launch(o),
  'wait-for': (o, [text]) => {
    if (!text) throw new UsageError('wait-for needs <text>');
    return request(o.session, 'wait-for', { text, timeout: o.timeout ? Number(o.timeout) : undefined });
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
  serve: (o) => serve(o),
};

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
