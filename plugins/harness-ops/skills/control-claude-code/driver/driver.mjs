#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import {
  closeSync,
  constants,
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
  statSync,
  writeFileSync,
  writeSync,
} from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import { basename, dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { StringDecoder } from 'node:string_decoder';
import { parseArgs } from 'node:util';

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFESTS = ['package.json', 'package-lock.json'];
const ENGINE = '@microsoft/tui-test';
const COMPONENT = 'control-claude-code';
const PLUGIN = 'harness-ops';
const NPM_CI_ARGS = ['ci', '--ignore-scripts', '--no-audit', '--no-fund'];
const NPM_TIMEOUT_MS = 600_000;
const SIGNED = '.signatures-verified';
const FONT_ENTRY = 'noto-sans-symbols-2';
const MAX_TTL_S = 2147483; // setTimeout holds at most 2^31-1 ms
const TIMER_MAX_MS = 2 ** 31 - 1; // a longer setTimeout delay fires after 1 ms
const timerMs = (ms) => Math.min(ms, TIMER_MAX_MS);
const SOCK_MAX = 100; // a Unix socket path is limited to roughly a hundred bytes
const EXIT_POLL_MS = 1000;
const WHOLE = /^[1-9]\d*$/;
const NATIVE_LOAD = /failed to load the @microsoft\/tui-test native (?:addon|library)[^\n]*/;

export const LAUNCH_FLAGS = ['--restricted', '--strict-mcp-config'];
export const IN_SANDBOX_FLAGS = ['--strict-mcp-config'];
export const SANDBOX_KEY_PREFIX = 'ccd-dummy-';
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

const NO_KEY = 'none';
const CI_KEY_SOURCES = { ANTHROPIC_API_KEY: 'ANTHROPIC_API_KEY', CLAUDE_CODE_OAUTH_TOKEN: NO_KEY };
const CI_NAMES = Object.keys(CI_KEY_SOURCES);
const CONFIG = join(HERE, '..', 'config', 'defaults.json');

/** The variable names committed config lists under `credentials.ci`; each must be one CI_KEY_SOURCES knows. */
export function ciCredentials(file = CONFIG) {
  const names = Object.values(JSON.parse(readFileSync(file, 'utf8')).credentials?.ci ?? {});
  const unknown = names.filter((n) => !Object.hasOwn(CI_KEY_SOURCES, n));
  if (unknown.length) throw new UsageError(`credentials.ci names ${unknown.join(', ')}, which the driver cannot vouch for`);
  return names;
}

/**
 * The Claude Code command line, environment and the apiKeySource Ready accepts; pure, so it tests
 * with no packages installed. Attended, the API-key, gateway and provider variables are cleared and
 * the source must be "none"; CLAUDE_CODE_OAUTH_TOKEN, the person's own login, passes through as it
 * always has. Unattended, the one `config.credentials` variable that is set is kept, the scrub keeps it
 * from the processes Claude Code starts, and two set at once is refused before anything runs.
 * `realSetup` starts Claude Code with none of the isolating flags, so the person's own settings,
 * plugins, hooks and MCP servers load; it runs only attended, and only it takes a `launcher`, the
 * argument vector run in place of the bare `claude`.
 */
export function buildLaunch(config, env) {
  if (!config?.pluginDir) throw new UsageError('launch needs --plugin-dir <dir>');
  const launcher = config.launcher ?? [];
  if (launcher.length && !config.realSetup) throw new UsageError('--launcher runs only with --real-setup');
  if (config.realSetup && (config.unattended || config.inSandbox)) {
    throw new Refused('refused: --real-setup loads the person\'s own settings, MCP servers and Bash, so it runs only attended: never with --unattended, --in-sandbox or a kept credential');
  }
  const childEnv = { ...env, CLAUDE_CODE_FORCE_SESSION_PERSISTENCE: '1', CLAUDE_CODE_HIDE_CWD: '1' };
  const set = config.unattended ? (config.credentials ?? []).filter((n) => env[n]) : [];
  if (set.length > 1) throw new Refused(`refused: ${set.join(' and ')} are both set; an unattended run takes one credential`);
  const [kept] = set;
  const key = kept === 'ANTHROPIC_API_KEY' ? env[kept] : '';
  if (config.inSandbox && !(key.startsWith(SANDBOX_KEY_PREFIX) && key.length > SANDBOX_KEY_PREFIX.length)) {
    throw new Refused(`refused: --in-sandbox runs only under the launch broker, on an unattended ANTHROPIC_API_KEY starting with ${SANDBOX_KEY_PREFIX}`);
  }
  for (const name of [...UNSET_VARS, ...(config.credentials ?? [])]) if (name !== kept) delete childEnv[name];
  if (kept && !config.inSandbox) childEnv.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = '1';
  const flags = config.realSetup ? [] : config.inSandbox ? IN_SANDBOX_FLAGS : LAUNCH_FLAGS;
  return {
    argv: [...(launcher.length ? launcher : ['claude']), ...flags, '--plugin-dir', config.pluginDir],
    env: childEnv,
    keySource: kept ? CI_KEY_SOURCES[kept] : NO_KEY,
  };
}

export const PRINT_FLAGS = ['-p', '--output-format', 'stream-json', '--verbose'];
const READY_PROMPT = 'Reply with the single word ok.';
const READY_TIMEOUT_MS = 120_000;
const LOG_TIMEOUT_MS = 600_000;
const STOP_GRACE_MS = 5000;

// A --real-setup print-mode turn keeps --strict-mcp-config. Why:
// https://code.claude.com/docs/en/permissions#what-runs-before-you-trust-a-folder
const REAL_SETUP_PRINT_FLAGS = ['--strict-mcp-config'];

/** The print-mode command line: the launch's, then the stream-json flags and the prompt. */
export function buildPrint(config, env, prompt) {
  if (!prompt) throw new UsageError('print mode needs a prompt');
  if (prompt.startsWith('-')) throw new UsageError('a prompt may not start with -');
  const launch = buildLaunch(config, env);
  const strict = config.realSetup ? REAL_SETUP_PRINT_FLAGS : [];
  return { ...launch, argv: [...launch.argv, ...strict, ...PRINT_FLAGS, prompt] };
}

const launchConfig = (opts, pluginDir) => ({
  pluginDir,
  unattended: Boolean(opts.unattended),
  credentials: opts.unattended ? ciCredentials() : [],
  inSandbox: Boolean(opts['in-sandbox']),
  realSetup: Boolean(opts['real-setup']),
  launcher: opts.launcher ?? [],
});

class UsageError extends Error {
  code = 2;
}
class Refused extends Error {
  code = 1;
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

/**
 * This plugin's data directory name, as Claude Code names it: the plugin id `<name>@<marketplace>`
 * with every character outside A-Za-z0-9_- replaced by `-`. The marketplace comes from an install at
 * <config>/plugins/cache/<marketplace>/<name>/<version>, the layout lib/plugin-options.mjs
 * resolveInstall reads; this skill is copied alone into CI, so it keeps its own copy of the rule.
 * Anywhere else is a --plugin-dir session, whose plugin id ends in @inline.
 */
export function pluginDataId(pluginRoot) {
  const parts = pluginRoot.replaceAll('\\', '/').split('/');
  const at = parts.lastIndexOf('cache');
  const cached = at > 0 && parts[at - 1] === 'plugins' && parts.length - at === 4 && parts.slice(at + 1).every(Boolean);
  return `${PLUGIN}@${cached ? parts[at + 1] : 'inline'}`.replace(/[^A-Za-z0-9_-]/g, '-');
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
  return { base: join(config, 'plugins', 'data', pluginDataId(resolve(HERE, '..', '..', '..'))), rule:'plugin data directory' };
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

function reapPartials(target) {
  const dir = dirname(target);
  const names = existsSync(dir) ? readdirSync(dir) : [];
  for (const name of names) {
    const pid = /\.partial-(\d+)$/.exec(name)?.[1];
    if (pid && !alive(Number(pid))) rmSync(join(dir, name), { recursive: true, force: true });
  }
}

function verifyInstall(dir, repair) {
  const audit = npm(['audit', 'signatures'], dir);
  if (!audit.ok) throw new Broken(`npm audit signatures failed (${audit.why})`, repair);
  const probe = loadProbe(dir);
  if (!probe.ok) throw new Broken(`the installed engine does not load (${probe.why})`, repair);
  writeFileSync(join(dir, SIGNED), `${new Date().toISOString()}\n`);
}

export function ensureInstalled(explicit) {
  const target = installDir(depsBase(explicit).base);
  const repair = repairLine(target);
  const verified = () => hasEngine(target) && existsSync(join(target, SIGNED));
  if (verified()) return target;
  if (hasEngine(target)) {
    verifyInstall(target, repair);
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
    verifyInstall(partial, repair);
    if (existsSync(target) && !hasEngine(target)) rmSync(target, { recursive: true, force: true });
    renameSync(partial, target);
  } catch (err) {
    rmSync(partial, { recursive: true, force: true });
    if (verified()) return target;
    throw err instanceof Broken ? err : new Broken(`install failed (${err.message})`, repair);
  }
  return target;
}


function runtimeDir(platform) {
  const env = process.env;
  if (platform === 'win32') return join(env.LOCALAPPDATA || join(os.homedir(), 'AppData', 'Local'), 'ccd');
  if (env.CCD_RUNTIME_DIR && !isAbsolute(env.CCD_RUNTIME_DIR)) throw new UsageError('CCD_RUNTIME_DIR must be an absolute path');
  const base = env.CCD_RUNTIME_DIR || env.XDG_RUNTIME_DIR;
  return base ? join(base, 'ccd') : join(os.homedir(), '.cache', 'ccd');
}

/** A session name: 1-32 letters, digits, _ or -, not starting with -, so it never reads as a flag. */
export const SESSION = /^[A-Za-z0-9_][\w-]{0,31}$/;
const checkSession = (session) => {
  if (!SESSION.test(session)) throw new UsageError('--session takes 1-32 letters, digits, _ or -, not starting with -');
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
      throw new Error(`the socket path ${sock} is too long for a Unix socket; set ${process.env.CCD_RUNTIME_DIR ? 'CCD_RUNTIME_DIR' : 'CCD_RUNTIME_DIR or XDG_RUNTIME_DIR'} to a short private directory`);
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
    if (owner === undefined) continue;
    if (!owner || alive(owner)) throw taken;
    if (lockOwner(lock) === owner) rmSync(lock, { force: true });
  }
  throw taken;
}

const listening = (sock) =>
  new Promise((done) => {
    const conn = net.createConnection(sock);
    conn.on('connect', () => {
      conn.destroy();
      done(true);
    });
    conn.on('error', () => done(false));
  });

const REPLY_LINE_MAX = 1 << 20;
const REPLY_GRACE_MS = 120_000;

/** Sends one verb to the session holder; fails past `deadlineMs` (at most TIMER_MAX_MS) or a reply over REPLY_LINE_MAX. */
export function request(session, verb, args = {}, deadlineMs = (args.timeout ?? 0) + REPLY_GRACE_MS) {
  const { sock } = endpoint(session);
  const ms = timerMs(deadlineMs);
  return new Promise((resolveReply, rejectReply) => {
    const conn = net.createConnection(sock);
    let buf = '';
    const timer = setTimeout(() => fail(new Error(`the session holder did not reply within ${ms} ms`)), ms);
    const done = (v) => (clearTimeout(timer), resolveReply(v));
    const fail = (err) => {
      clearTimeout(timer);
      conn.destroy();
      rejectReply(err);
    };
    conn.on('connect', () => conn.write(`${JSON.stringify({ verb, args })}\n`));
    conn.on('data', (d) => {
      buf += d;
      if (buf.length > REPLY_LINE_MAX) fail(new Error('the session holder sent a reply over 1 MiB'));
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

const PING_MS = 5000;

async function liveSessions(platform = process.platform) {
  const dir = privateDir(runtimeDir(platform), { create: false });
  const suffix = platform === 'win32' ? '.pipe' : '.sock';
  const names = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(suffix)).map((f) => f.slice(0, -suffix.length)) : [];
  const live = [];
  for (const name of names.filter((n) => SESSION.test(n))) {
    if (await request(name, 'ping', {}, PING_MS).then(() => true, () => false)) live.push(name);
  }
  return live;
}

/**
 * The account lines of `session`, else of the one session running, from its holder, which reads
 * `claude auth status` in that session's own launch environment. Fails with no session or several,
 * and on any reply but the KEY_AUTH_NONE line alone or one-line values.
 */
export async function drivenAccount(session) {
  if (session === undefined) {
    const live = await liveSessions();
    if (live.length !== 1) throw new Error(live.length ? `${live.length} sessions are running (${live.join(', ')}); pass --session <name>` : 'no session is running; launch one first');
    [session] = live;
  }
  const lines = await request(session, 'account');
  const value = (l) => typeof l === 'string' && l.trim() !== '' && !/[\r\n]/.test(l) && !l.startsWith('none:');
  const none = Array.isArray(lines) && lines.length === 1 && lines[0] === KEY_AUTH_NONE;
  if (!none && !(Array.isArray(lines) && lines.length && lines.every(value))) {
    throw new Error('the session holder answered with something other than account lines; use nothing it wrote');
  }
  return lines;
}


const CONFIG_DIR = join(HERE, '..', 'config');

/** config/defaults.json, then config/local.json over it. */
export function readConfig(dir = CONFIG_DIR) {
  const layer = (name) => {
    try {
      return JSON.parse(readFileSync(join(dir, name), 'utf8'));
    } catch (err) {
      if (err.code === 'ENOENT') return {};
      throw new UsageError(`config/${name} is not valid JSON`);
    }
  };
  const config = { ...layer('defaults.json'), ...layer('local.json') };
  if (!Number.isInteger(config.maxEntryPoints) || config.maxEntryPoints < 1) {
    throw new UsageError('config maxEntryPoints must be a whole number above 0');
  }
  return config;
}

/** The plugin directory (the nearest one holding .claude-plugin/plugin.json) of each changed file, once each, in order. */
export function changedPlugins(files, root = process.cwd()) {
  const dirs = [];
  for (const file of files) {
    if (isAbsolute(file) || file.split(/[\\/]/).includes('..')) throw new UsageError(`a changed file must be a path inside the repository: ${file}`);
    for (let dir = dirname(file); dir !== '.' && dir !== dirname(dir); dir = dirname(dir)) {
      if (existsSync(join(root, dir, '.claude-plugin', 'plugin.json'))) {
        if (!dirs.includes(dir)) dirs.push(dir);
        break;
      }
    }
  }
  return dirs;
}

function plugins(files, config = readConfig()) {
  const dirs = files.length ? changedPlugins(files) : [config.pluginDir].filter(Boolean);
  if (!files.length && !dirs.length) throw new UsageError('plugins got no changed file and config sets no pluginDir');
  if (files.length && !dirs.length) console.error('no changed file is inside a plugin; launch nothing');
  for (const dir of dirs.slice(config.maxEntryPoints)) console.error(`blocked: maxEntryPoints reached: ${dir}`);
  return { text: dirs.slice(0, config.maxEntryPoints).join('\n'), status: 0 };
}


const SKILL_FILE = join(HERE, '..', 'SKILL.md');
const MASK_CHAR = '*';
const BOX = /[─-╿]/;
const MIRROR_READY = 'ccd-mirror-ready';
const MIRROR_MS = 5000;
const FRAME_MS = 250;

/**
 * The `- <label> | <regex>` lines under SKILL.md's `## Mask`, as case-insensitive regular expressions;
 * the lines under its `### Real setup` only for a session launched with --real-setup.
 */
export function readMasks(text, { realSetup = false } = {}) {
  const masks = [];
  let inside = false;
  let skip = false;
  let fence = false;
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*(```|~~~)/.test(line)) fence = !fence;
    else if (fence) continue;
    else if (line.startsWith('## ')) [inside, skip] = [line.trim() === '## Mask', false];
    else if (inside && line.startsWith('### ')) skip = line.trim() === '### Real setup' && !realSetup;
    else if (inside && !skip) {
      const m = /^- ([^|]*[^|\s])\s*\|\s*(\S.*)$/.exec(line);
      if (m) masks.push({ label: m[1].trim(), pattern: new RegExp(m[2].trimEnd(), 'gi') });
    }
  }
  if (!masks.length) throw new Error('SKILL.md ## Mask holds no mask line; capture nothing');
  return masks;
}

/**
 * The parsed `claude auth status --json`, run in `env`, the session's launch environment.
 * The output is never echoed, so no value reaches a log or an error message.
 */
export function authStatus(env) {
  const run = spawnSync('claude', ['auth', 'status', '--json'], {
    env,
    encoding: 'utf8',
    timeout: 30_000,
    shell: process.platform === 'win32',
  });
  if (run.error) throw new Error('claude auth status did not run; cannot read the signed-in account to mask it');
  try {
    return JSON.parse(run.stdout);
  } catch {
    throw new Error('claude auth status printed no JSON; cannot read the signed-in account to mask it');
  }
}

/** The email and organization name an auth status names, without duplicates or blanks. */
export function statusValues(status) {
  const values = [status?.email, status?.orgName].filter((v) => typeof v === 'string' && v.trim());
  return [...new Set(values)];
}

export const KEY_AUTH_NONE = 'none: API-key auth has no signed-in account';

/**
 * The lines `cli/account.mjs` prints for a session: its email and organization name, else the
 * KEY_AUTH_NONE line when the session runs on the ANTHROPIC_API_KEY its launch kept and the status
 * names no account. Any other status is an error, so the post-check never reads "nothing to hide"
 * from a session whose sign-in it cannot see.
 */
export function accountLines(status, keySource) {
  const values = statusValues(status);
  if (values.length) return values;
  if (status?.authMethod === 'api_key' && keySource === 'ANTHROPIC_API_KEY') return [KEY_AUTH_NONE];
  throw new Error('claude auth status names no email or organization');
}

const sessionStatus = (ctx) => (ctx.status ??= authStatus(ctx.env));

const unitsOf = (cell) => cell.char.length;

/**
 * Hides each mask match within a screen row, and each value anywhere on the screen
 * ignoring case, whitespace, `|` and box drawing, so a value wrapped across rows or
 * split by a border is still hidden. Each hidden cell is masked through the end of its row
 * segment, up to the next box-drawing cell or the row's last column, so the stars never show how
 * long the value was; rows are padded with blanks to `cols` first. Box-drawing cells stay.
 * Returns the masked rows of cells and their text.
 */
export function maskCells(cells, masks, values = [], cols = 0) {
  const byRow = new Map();
  for (const cell of cells) {
    const copy = { ...cell, link: '', link_id: '' };
    if (!byRow.has(copy.y)) byRow.set(copy.y, []);
    byRow.get(copy.y).push(copy);
  }
  const rows = [...byRow.keys()].sort((a, b) => a - b).map((y) => byRow.get(y).sort((a, b) => a.x - b.x));
  for (const row of rows) {
    const y = row[0].y;
    for (let x = row.at(-1).x + 1; x < cols; x++) row.push({ x, y, char: ' ', fg: 'default', bg: 'default', link: '', link_id: '' });
  }
  const hide = new Set();
  for (const row of rows) {
    const text = row.map((c) => c.char).join('');
    const at = row.flatMap((c) => Array(unitsOf(c)).fill(c));
    for (const { pattern } of masks) {
      for (const m of text.matchAll(pattern)) for (let i = m.index; i < m.index + m[0].length; i++) hide.add(at[i]);
    }
  }
  let flat = '';
  const stream = [];
  for (const cell of rows.flat()) {
    if (!cell.char || /\s/.test(cell.char) || cell.char === '|' || BOX.test(cell.char)) continue;
    const low = cell.char.toLowerCase();
    flat += low;
    for (let i = 0; i < low.length; i++) stream.push(cell);
  }
  for (const value of values) {
    const needle = value.toLowerCase().replace(/[\s|]/g, '');
    if (!needle) continue;
    for (let i = flat.indexOf(needle); i >= 0; i = flat.indexOf(needle, i + 1)) {
      for (let k = i; k < i + needle.length; k++) hide.add(stream[k]);
    }
  }
  const blank = (cell) => {
    Object.assign(cell, { char: MASK_CHAR, fg: 'default', bg: 'default' });
    for (const [name] of ATTRS) cell[name] = false;
  };
  for (const row of rows) {
    let masking = false;
    for (const cell of row) {
      if (BOX.test(cell.char)) masking = false;
      else if (masking || hide.has(cell)) {
        masking = true;
        blank(cell);
      }
    }
  }
  return { rows, text: rows.map((row) => row.map((c) => c.char).join('')).join('\n') };
}

const color = (value, base) => {
  if (typeof value === 'number') return [`${base};5;${value}`];
  const hex = /^#([0-9a-f]{6})$/i.exec(value ?? '')?.[1];
  if (!hex) return [];
  const n = Number.parseInt(hex, 16);
  return [`${base};2;${n >> 16};${(n >> 8) & 255};${n & 255}`];
};
const ATTRS = [
  ['bold', 1],
  ['dim', 2],
  ['italic', 3],
  ['underline', 4],
  ['blink', 5],
  ['inverse', 7],
  ['invisible', 8],
  ['strike', 9],
];
const sgr = (cell) => {
  const parts = ['0', ...ATTRS.filter(([name]) => cell[name]).map(([, code]) => String(code))];
  return `\x1b[${[...parts, ...color(cell.fg, 38), ...color(cell.bg, 48)].join(';')}m`;
};

/** The escape sequence that draws masked rows of cells, colors and attributes kept, links dropped. */
export function renderFrame(rows) {
  let out = '\x1b[0m\x1b[2J';
  for (const row of rows) {
    if (!row.length) continue;
    out += `\x1b[${row[0].y + 1};1H`;
    let last = '';
    for (const cell of row) {
      if (cell.char === '') continue;
      const style = sgr(cell);
      if (style !== last) out += style;
      last = style;
      out += cell.char;
    }
  }
  return `${out}\x1b[0m`;
}

const settled = (text) =>
  text
    .split('\n')
    .map((l) => l.trimEnd())
    .join('\n')
    .trimEnd();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const MIRROR_JS = `process.stdin.setRawMode(true);process.stdin.on('data',(d)=>process.stdout.write(d));process.stdout.write('\\x1b[?25l${MIRROR_READY}');`;

async function openMirror(ctx, size) {
  const mirror = ctx.TuiTest.ephemeral(`${COMPONENT}-mirror`);
  try {
    await mirror.run(process.execPath, ['-e', MIRROR_JS], { cols: size.cols, rows: size.rows });
    await mirror.getByText(MIRROR_READY).first().wait({ state: 'visible', timeout: MIRROR_MS });
  } catch (err) {
    await mirror.closeQuiet().catch(() => {});
    throw err;
  }
  return mirror;
}

async function maskedFrame(t, ctx) {
  ctx.mask ??= { masks: readMasks(readFileSync(SKILL_FILE, 'utf8'), ctx), values: statusValues(sessionStatus(ctx)) };
  const size = await t.getSize();
  const { rows, text } = maskCells(await t.cells(0, 0, size.cols, size.rows), ctx.mask.masks, ctx.mask.values, size.cols);
  return { size, text, draw: renderFrame(rows) };
}

async function show(mirror, frame) {
  await mirror.write(frame.draw);
  const want = settled(frame.text);
  for (const deadline = Date.now() + MIRROR_MS; settled(await mirror.text()) !== want; await sleep(50)) {
    if (Date.now() > deadline) throw new Error('the masked frame did not redraw; nothing captured');
  }
}

const removeCapture = (path) => {
  rmSync(path, { force: true });
  rmSync(`${path}.txt`, { force: true });
};

async function syncFrame(t, ctx, rec) {
  if (rec.busy || rec.error) return;
  rec.busy = true;
  try {
    const frame = await maskedFrame(t, ctx);
    if (frame.draw !== rec.last) {
      await show(rec.mirror, frame);
      rec.last = frame.draw;
      if (rec.frames.at(-1) !== frame.text) rec.frames.push(frame.text);
    }
  } catch (err) {
    rec.error = err;
  } finally {
    rec.busy = false;
  }
}


const RECORD_STOPPED = 'recording stopped';

const HANDLERS = {
  ping: async () => 'pong',
  account: async (_t, _args, ctx) => accountLines(sessionStatus(ctx), ctx.keySource),
  'wait-for': async (t, { text, timeout }) => {
    await t.getByText(text).first().wait({ state: 'visible', timeout });
    return `seen: ${text}`;
  },
  type: async (t, { text, keys }) => {
    if (text) await t.type(text);
    if (keys?.length) await t.press(...keys);
    return 'typed';
  },
  screenshot: async (t, { path }, ctx) => {
    const frame = await maskedFrame(t, ctx);
    const mirror = await openMirror(ctx, frame.size);
    try {
      await show(mirror, frame);
      await mirror.screenshot(path);
      writeFileSync(`${path}.txt`, `${settled(await mirror.text())}\n`);
    } catch (err) {
      removeCapture(path);
      throw err;
    } finally {
      await mirror.closeQuiet().catch(() => {});
    }
    return path;
  },
  'record-start': async (t, { path }, ctx) => {
    if (ctx.recording) throw new Error('a recording is running; run record stop first');
    const frame = await maskedFrame(t, ctx);
    const mirror = await openMirror(ctx, frame.size);
    const rec = { mirror, path, frames: [frame.text], last: frame.draw };
    try {
      await show(mirror, frame);
      await mirror.startRecording(path);
    } catch (err) {
      await mirror.closeQuiet().catch(() => {});
      removeCapture(path);
      throw err;
    }
    rec.timer = setInterval(() => syncFrame(t, ctx, rec), FRAME_MS);
    ctx.recording = rec;
    return `recording: ${path}`;
  },
  'record-stop': async (t, _args, ctx) => {
    const rec = ctx.recording;
    if (!rec) throw new Error('no recording is running');
    ctx.recording = undefined;
    clearInterval(rec.timer);
    while (rec.busy) await sleep(20);
    try {
      await syncFrame(t, ctx, rec);
      await rec.mirror.stopRecording();
      if (rec.error) throw rec.error;
      writeFileSync(`${rec.path}.txt`, `${rec.frames.map(settled).join('\n\n')}\n`);
      return RECORD_STOPPED;
    } catch (err) {
      removeCapture(rec.path);
      throw err;
    } finally {
      await rec.mirror.closeQuiet().catch(() => {});
    }
  },
};

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
  const launch = buildLaunch(launchConfig(opts, opts['plugin-dir']), process.env);
  const stale = process.platform !== 'win32' && existsSync(sock);
  if (stale && (await listening(sock))) throw new Error(`another process is serving ${sock}`);
  for (const name of Object.keys(process.env)) if (!(name in launch.env)) delete process.env[name]; // the engine merges onto this env
  const { TuiTest } = await import(pathToFileURL(join(opts.install, 'node_modules', ENGINE, 'dist', 'index.js')).href);
  const terminal = TuiTest.ephemeral(COMPONENT);
  const ctx = { TuiTest, env: launch.env, keySource: launch.keySource, realSetup: Boolean(opts['real-setup']) };
  await terminal.run(launch.argv[0], launch.argv.slice(1), { env: launch.env, cols: 120, rows: 40 });
  for (const name of CI_NAMES) delete process.env[name];
  if (await childExited(terminal)) throw new Error(`${launch.argv[0]} exited as soon as it started`);
  if (stale) rmSync(sock, { force: true });
  const closeTerminal = async () => {
    await ctx.recording?.mirror.closeQuiet().catch(() => {});
    await terminal.closeQuiet();
  };
  const server = net.createServer((conn) => {
    let buf = '';
    conn.on('error', () => {});
    conn.on('data', async (d) => {
      buf += d;
      if (!buf.includes('\n')) return;
      let reply;
      try {
        const { verb, args } = JSON.parse(buf);
        if (verb === 'stop') {
          await closeTerminal();
          free();
          conn.end(`${JSON.stringify({ ok: true, result: 'stopped' })}\n`, () => process.exit(0));
          return;
        }
        const handler = HANDLERS[verb];
        if (!handler) throw new Error(`unknown verb ${verb}`);
        reply = { ok: true, result: await handler(terminal, args, ctx) };
      } catch (err) {
        reply = { ok: false, error: err.message };
      }
      conn.end(`${JSON.stringify(reply)}\n`);
    });
  });
  const free = () => {
    server.close();
    rmSync(nameFile ?? sock, { force: true });
    release(lock, process.pid);
  };
  const closeAndExit = async () => {
    await closeTerminal();
    free();
    process.exit(0);
  };
  setTimeout(closeAndExit, Number(opts.ttl) * 1000).unref();
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

/**
 * The directory claude starts in: the one --cwd names; under --in-sandbox the caller's own, since
 * the caller's sandbox is the boundary; else `<session>.cwd` in the runtime directory, which
 * `launch` empties and makes private each time (`fresh`), so a driven session never starts in the
 * caller's checkout.
 */
export function launchCwd(opts) {
  if (opts.cwd !== undefined) {
    if (!opts.cwd) throw new UsageError('--cwd takes a directory');
    const dir = resolve(opts.cwd);
    if (!statSync(dir, { throwIfNoEntry: false })?.isDirectory()) throw new UsageError(`--cwd ${dir} is not a directory`);
    return { dir, fresh: false };
  }
  if (opts['in-sandbox']) return { dir: process.cwd(), fresh: false };
  checkSession(opts.session);
  return { dir: join(runtimeDir(process.platform), `${opts.session}.cwd`), fresh: true };
}

async function launch(opts) {
  const pluginDir = opts['plugin-dir'] && resolve(opts['plugin-dir']);
  const config = launchConfig(opts, pluginDir);
  const { env, argv } = buildLaunch(config, process.env);
  if (!WHOLE.test(opts.ttl) || Number(opts.ttl) > MAX_TTL_S) {
    throw new UsageError(`--ttl takes a whole number of seconds up to ${MAX_TTL_S}`);
  }
  const cwd = launchCwd(opts);
  if (opts['dry-run']) {
    checkSession(opts.session);
    depsBase(opts['deps-dir'], false);
    return `dry run: would launch session '${opts.session}' in ${cwd.dir} running ${argv.join(' ')}; started nothing`;
  }
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
    if (cwd.fresh) {
      rmSync(cwd.dir, { recursive: true, force: true });
      privateDir(cwd.dir);
    }
    log = join(dir, `${opts.session}.log`);
    const fd = openSync(log, 'w', 0o600);
    try {
      holder = spawn(
        process.execPath,
        [
          fileURLToPath(import.meta.url),
          'serve',
          '--session',
          opts.session,
          '--plugin-dir',
          pluginDir,
          '--install',
          resolve(install),
          '--ttl',
          opts.ttl,
          ...(config.unattended ? ['--unattended'] : []),
          ...(config.inSandbox ? ['--in-sandbox'] : []),
          ...(config.realSetup ? ['--real-setup'] : []),
          ...config.launcher.map((word) => `--launcher=${word}`),
        ],
        { cwd: cwd.dir, detached: true, stdio: ['ignore', fd, fd], env },
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
      return `launched session '${opts.session}' in ${cwd.dir} (holder pid ${holder.pid}, log ${log})`;
    } catch {
      await sleep(250);
    }
  }
  if (!exited) holder.kill();
  release(lock, holder.pid);
  const text = existsSync(log) ? readFileSync(log, 'utf8') : '';
  const native = NATIVE_LOAD.exec(text)?.[0];
  if (native) throw new Broken(`the installed engine does not load (${native})`, repairLine(install));
  const tail = text.trim().split('\n').slice(-5).join(' | ');
  const why = exited ? 'the session holder exited before the session started' : 'the session did not start within 30 s';
  throw new Error(`${why}${tail ? `: ${tail}` : ''}`);
}

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
    const found = new RegExp(probe.pattern).test(fc.stdout);
    lines.push(`font: ${probe.pattern} ${found ? 'found' : 'MISSING; some status glyphs draw as boxes in captures'}`);
  }
  return { text: lines.join('\n'), status };
}


function runPrint({ config, out, prompt, stopAt, timeoutMs }) {
  const { argv, env } = buildPrint(config, process.env, prompt);
  const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_TRUNC | (constants.O_NOFOLLOW ?? 0);
  let fd;
  try {
    fd = openSync(out, flags, 0o600);
  } catch (err) {
    throw new Error(`cannot open ${out} (${err.code ?? err.message})`);
  }
  let open = true;
  const closeOut = () => {
    if (open) closeSync(fd);
    open = false;
  };
  return new Promise((done, fail) => {
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
        }
      }
      if (init && stopAt(init)) stop();
    });
    const settle = () => {
      clearTimeout(deadline);
      clearTimeout(killTimer);
      closeOut();
    };
    child.on('error', (err) => {
      settle();
      fail(err.code === 'ENOENT' ? new Error(`${argv[0]} is not on PATH`) : err);
    });
    child.on('close', (code, signal) => {
      settle();
      done({ init, code, signal, timedOut });
    });
  });
}

function printTarget(opts, verb, defaultTimeout) {
  const pluginDir = opts['plugin-dir'] && resolve(opts['plugin-dir']);
  if (!pluginDir) throw new UsageError(`${verb} needs --plugin-dir <dir>`);
  if (!opts.out) throw new UsageError(`${verb} needs --out <path.jsonl>`);
  if (opts.timeout !== undefined && !WHOLE.test(opts.timeout)) {
    throw new UsageError('--timeout takes a whole number of milliseconds');
  }
  if (!existsSync(pluginDir)) throw new UsageError(`--plugin-dir ${pluginDir} does not exist`);
  const timeoutMs = Math.min(opts.timeout === undefined ? defaultTimeout : Number(opts.timeout), MAX_TTL_S * 1000);
  const config = launchConfig(opts, pluginDir);
  return { config, keySource: buildLaunch(config, process.env).keySource, out: resolve(opts.out), timeoutMs };
}

const keyLine = (init, want) =>
  init.apiKeySource === want ? [] : [`refused: apiKeySource is ${JSON.stringify(init.apiKeySource)}, not ${JSON.stringify(want)}; drive nothing`];

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

const wouldRunPrint = (config, prompt, out) =>
  `dry run: would run ${buildPrint(config, process.env, prompt).argv.join(' ')} and write its stream-json to ${out}; ran nothing`;

async function ready(opts) {
  const { config, keySource, out, timeoutMs } = printTarget(opts, 'ready', READY_TIMEOUT_MS);
  if (opts['dry-run']) {
    checkSession(opts.session);
    depsBase(opts['deps-dir'], false);
    return wouldRunPrint(config, READY_PROMPT, out);
  }
  const { pluginDir } = config;
  const health = doctor(opts);
  const lines = [health.text, await sessionLine(opts.session)];
  const { init, timedOut } = await runPrint({ config, out, prompt: READY_PROMPT, stopAt: () => true, timeoutMs });
  lines.push(`stream: ${out}`);
  if (!init) {
    lines.push(timedOut ? `init: no init event within ${timeoutMs} ms` : 'init: no init event');
    return { text: lines.join('\n'), status: health.status || 1 };
  }
  const plugins = (init.plugins ?? []).map((p) => p?.name).join(', ') || 'none';
  const hasPlugin = loaded(init, pluginDir);
  const keys = keyLine(init, keySource);
  lines.push(`claude_code_version: ${init.claude_code_version}`, `apiKeySource: ${init.apiKeySource}`, `plugins: ${plugins}`, ...keys);
  if (!hasPlugin) lines.push(`refused: the init event does not list the plugin at ${pluginDir}; drive nothing`);
  return { text: lines.join('\n'), status: health.status || (!keys.length && hasPlugin ? 0 : 1) };
}

async function log(opts, prompt) {
  const { config, keySource, out, timeoutMs } = printTarget(opts, 'log', LOG_TIMEOUT_MS);
  if (opts['dry-run']) return wouldRunPrint(config, prompt, out);
  const run = await runPrint({ config, out, prompt, stopAt: (i) => i.apiKeySource !== keySource, timeoutMs });
  const ended = run.timedOut ? `stopped after ${timeoutMs} ms` : run.signal ? `stopped by ${run.signal}` : `exit ${run.code}`;
  if (!run.init) return { text: `log: ${out} (claude ${ended}); init: no init event`, status: 1 };
  const keys = keyLine(run.init, keySource);
  const lines = [`log: ${out} (claude ${ended}, apiKeySource ${run.init.apiKeySource})`, ...keys];
  const clean = !keys.length && run.code === 0 && !run.timedOut;
  return { text: lines.join('\n'), status: clean ? 0 : 1 };
}


export const BROKERED = ['launch', 'ready', 'log'];
const PATH_OPTIONS = ['plugin-dir', 'out', 'deps-dir'];
export const RELAY_PREFIX = 'broker| ';
const LAUNCH_MS = 30_000 + NPM_TIMEOUT_MS;

/** How long a brokered verb waits for the broker's exit: the verb's own timeout plus the reply grace, at most TIMER_MAX_MS. */
export function brokerDeadline(verb, values) {
  const own = WHOLE.test(values.timeout ?? '') ? Number(values.timeout) : undefined;
  const base = { launch: LAUNCH_MS, ready: own ?? READY_TIMEOUT_MS, log: own ?? LOG_TIMEOUT_MS }[verb];
  return timerMs(base + REPLY_GRACE_MS);
}

const ESCAPES = /\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)?|[@-_])/g;
const CONTROLS = /[\x00-\x08\x0b-\x1f\x7f-\x9f\u2028\u2029]/g;

/** A writer that strips control characters from relayed text and starts each line with RELAY_PREFIX. */
export function relayLines(stream) {
  let atStart = true;
  return (text) => {
    let out = '';
    for (const ch of text.replace(ESCAPES, '').replace(CONTROLS, '')) {
      if (atStart) out += RELAY_PREFIX;
      out += ch;
      atStart = ch === '\n';
    }
    if (out) stream.write(out);
  };
}

function checkBrokerSocket(sock) {
  if (!isAbsolute(sock)) throw new UsageError('CCD_BROKER_SOCK must be an absolute path');
  privateDir(dirname(sock), { create: false });
  const st = lstatSync(sock, { throwIfNoEntry: false });
  if (!st) throw new Error(`the launch broker at ${sock} did not answer (ENOENT)`);
  if (!st.isSocket() || st.uid !== process.getuid()) throw new Unsafe(`${sock} is not a socket owned by you; drive nothing`);
}

/** The one-line request a brokered verb sends: the options as typed, paths made absolute here, then `--` and the positionals. */
export function brokerRequest(verb, tokens, positionals, cwd = process.cwd()) {
  const args = [];
  for (const token of tokens) {
    if (token.kind !== 'option') continue;
    args.push(`--${token.name}`);
    if (token.value !== undefined) args.push(PATH_OPTIONS.includes(token.name) ? resolve(cwd, token.value) : token.value);
  }
  return { verb, args: positionals.length ? [...args, '--', ...positionals] : args };
}

/**
 * Sends one request to the broker at `sock` and relays its streamed stdout and stderr until the
 * final exit status, which it resolves with. The replies are untrusted data: anything that is not a
 * string chunk or a whole exit status from 0 to 255 fails the verb, so does no exit by `timeoutMs`,
 * and relayed text loses its control characters and carries RELAY_PREFIX on every line.
 */
export function viaBroker(sock, req, { stdout = process.stdout, stderr = process.stderr, timeoutMs = REPLY_GRACE_MS } = {}) {
  const toOut = relayLines(stdout);
  const toErr = relayLines(stderr);
  return new Promise((resolveExit, rejectExit) => {
    const conn = net.createConnection(sock);
    conn.setEncoding('utf8');
    let buf = '';
    let exit;
    const timer = setTimeout(() => stopWith(new Error(`the launch broker sent no exit status within ${timeoutMs} ms`)), timeoutMs);
    const done = (code) => (clearTimeout(timer), resolveExit(code));
    const fail = (err) => (clearTimeout(timer), rejectExit(err));
    const stopWith = (err) => {
      conn.destroy();
      fail(err);
    };
    const take = (line) => {
      let reply;
      try {
        reply = JSON.parse(line);
      } catch {
        reply = undefined;
      }
      if (typeof reply?.stdout === 'string') toOut(reply.stdout);
      else if (typeof reply?.stderr === 'string') toErr(reply.stderr);
      else if (Number.isInteger(reply?.exit) && reply.exit >= 0 && reply.exit <= 255) exit = reply.exit;
      else return false;
      return true;
    };
    conn.on('connect', () => conn.write(`${JSON.stringify(req)}\n`));
    conn.on('data', (d) => {
      buf += d;
      for (let nl = buf.indexOf('\n'); nl >= 0 && exit === undefined; nl = buf.indexOf('\n')) {
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        if (!take(line)) return stopWith(new Error(`the launch broker sent a reply that is not a stream chunk or an exit: ${line.slice(0, 200)}`));
      }
      if (exit !== undefined) {
        conn.destroy();
        done(exit);
      } else if (buf.length > REPLY_LINE_MAX) stopWith(new Error('the launch broker sent a reply line over 1 MiB'));
    });
    conn.on('end', () => {
      if (exit === undefined) fail(new Error('the launch broker closed the connection without an exit status'));
    });
    conn.on('error', (err) => {
      if (exit === undefined) fail(new Error(`the launch broker at ${sock} did not answer (${err.code ?? err.message})`));
    });
  });
}


const OPTIONS = {
  session: { type: 'string', default: 'default' },
  'plugin-dir': { type: 'string' },
  'deps-dir': { type: 'string' },
  cwd: { type: 'string' },
  install: { type: 'string' },
  ttl: { type: 'string', default: '3600' },
  timeout: { type: 'string' },
  key: { type: 'string', multiple: true },
  out: { type: 'string' },
  unattended: { type: 'boolean' },
  'in-sandbox': { type: 'boolean' },
  'real-setup': { type: 'boolean' },
  launcher: { type: 'string', multiple: true },
  'dry-run': { type: 'boolean' },
  help: { type: 'boolean' },
};

const SESSION_OPT = '[--session <name>]';
const LAUNCH_ENV_OPTS = '[--unattended] [--in-sandbox] [--real-setup [--launcher <word>]...]';
/**
 * Per verb: `usage`, its flags after `node driver.mjs <verb>`; `brief`, the line `--help` lists it
 * with; `more`, what only `<verb> --help` adds; `writes`, whether it writes or sends, which is what
 * makes it take `--dry-run`.
 */
export const HELP = {
  launch: {
    usage: `--plugin-dir <dir> ${SESSION_OPT} [--cwd <dir>] [--ttl <seconds>] [--deps-dir <dir>] ${LAUNCH_ENV_OPTS}`,
    brief: 'Starts Claude Code with the plugin loaded, held by a detached session holder.',
    more: 'Claude Code starts in --cwd, under --in-sandbox in the caller\'s directory, else in <session>.cwd under the runtime directory, emptied on each launch. Installs the terminal engine from the committed lockfile on first use. The session stops after --ttl seconds (default 3600) or at stop. --real-setup starts it without --restricted and --strict-mcp-config, attended only; each --launcher adds one word of the command run in place of claude.',
    writes: true,
  },
  'wait-for': { usage: `<text> [--timeout <ms>] ${SESSION_OPT}`, brief: 'Waits until the session screen shows <text>; reads only.' },
  type: {
    usage: `[<text>] [--key <Name>]... ${SESSION_OPT}`,
    brief: 'Sends <text>, then each --key (such as Enter), to the session as keystrokes.',
    writes: true,
  },
  screenshot: {
    usage: `<path.png|path.svg> ${SESSION_OPT}`,
    brief: 'Writes a masked capture of the session screen to <path>.',
    more: 'Writes the text the capture shows beside it as <path>.txt. A frame that does not redraw exactly writes nothing.',
    writes: true,
  },
  record: {
    usage: `(start <path.mp4|.gif|.png|.cast> | stop) ${SESSION_OPT}`,
    brief: 'Starts or stops a masked recording of the session.',
    more: 'stop writes the recording, and every frame\'s text beside it as <path>.txt.',
    writes: true,
  },
  stop: { usage: SESSION_OPT, brief: 'Stops the session; the evidence files stay.', writes: true },
  doctor: { usage: '[--deps-dir <dir>]', brief: 'Prints whether the terminal engine is installed and loads, and whether the status font is present; reads only.' },
  ready: {
    usage: `--plugin-dir <dir> --out <path.jsonl> [--timeout <ms>] ${SESSION_OPT} [--deps-dir <dir>] ${LAUNCH_ENV_OPTS}`,
    brief: 'Checks a session is fit to drive and writes the init event to --out.',
    more: 'Prints doctor\'s lines and whether the session answers, then runs one print-mode turn and stops it at the init event. Exits 4 when doctor finds a broken install, else 1 unless the key source is the one the launch expects and the init event lists the plugin under test.',
    writes: true,
  },
  log: {
    usage: `<prompt> --plugin-dir <dir> --out <path.jsonl> [--timeout <ms>] ${LAUNCH_ENV_OPTS}`,
    brief: 'Runs <prompt> in print mode and keeps its stream-json in --out.',
    writes: true,
  },
  plugins: { usage: '[<changed file>...]', brief: 'Prints the plugin directory of each changed file, once each; reads only.' },
};
const EXITS = 'Exit: 0 done, 1 the step failed, 2 usage, 3 no session, 4 broken install, 5 a directory others can write.';
const usageLine = (verb) => `node driver.mjs ${verb} ${HELP[verb].usage}${HELP[verb].writes ? ' [--dry-run]' : ''}`;

/** `--help` text: one line per verb, or, for a verb, its flags and all it does. */
export function helpText(verb) {
  const entry = Object.hasOwn(HELP, verb) ? HELP[verb] : undefined;
  if (entry) return [usageLine(verb), '', [entry.brief, entry.more].filter(Boolean).join(' '), '', EXITS].join('\n');
  return [
    'node driver.mjs <verb> [flags]',
    '',
    ...Object.entries(HELP).map(([name, { brief }]) => `  ${name.padEnd(11)}${brief}`),
    '',
    'node driver.mjs <verb> --help prints that verb\'s flags. --dry-run, on a verb that writes or sends, prints what it would do and does nothing.',
    EXITS,
  ].join('\n');
}

const wouldRequest = (session, kind, payload = {}) => {
  checkSession(session);
  const json = JSON.stringify(payload);
  return `dry run: would send '${kind}' to session '${session}'${json === '{}' ? '' : ` with ${json}`}; sent nothing`;
};
const sendOrShow = (o, kind, payload) => (o['dry-run'] ? wouldRequest(o.session, kind, payload) : request(o.session, kind, payload));

const expectReply = (got, want, what = 'the requested capture path') => {
  if (got !== want) throw new Error(`the session holder answered with something other than ${what}; use nothing it wrote`);
  return got;
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
    return sendOrShow(o, 'type', { text, keys: o.key });
  },
  screenshot: async (o, [path]) => {
    if (!path) throw new UsageError('screenshot needs <path>');
    const want = resolve(path);
    if (o['dry-run']) return wouldRequest(o.session, 'screenshot', { path: want });
    return expectReply(await request(o.session, 'screenshot', { path: want }), want);
  },
  record: async (o, [action, path]) => {
    if (action === 'start' && path) {
      const want = resolve(path);
      if (o['dry-run']) return wouldRequest(o.session, 'record-start', { path: want });
      return expectReply(await request(o.session, 'record-start', { path: want }), `recording: ${want}`);
    }
    if (action === 'stop') {
      if (o['dry-run']) return wouldRequest(o.session, 'record-stop');
      return expectReply(await request(o.session, 'record-stop'), RECORD_STOPPED, `"${RECORD_STOPPED}"`);
    }
    throw new UsageError('record takes start <path> or stop');
  },
  stop: (o) => sendOrShow(o, 'stop'),
  doctor: (o) => doctor(o),
  ready: (o) => ready(o),
  log: (o, [prompt]) => log(o, prompt),
  plugins: (_o, files) => plugins(files),
  serve: (o) => serve(o),
};

const ARITY = { 'wait-for': 1, type: 1, screenshot: 1, record: 2, log: 1, plugins: Number.POSITIVE_INFINITY };

async function main(argv) {
  let parsed;
  try {
    parsed = parseArgs({ args: argv, options: OPTIONS, allowPositionals: true, tokens: true });
  } catch (err) {
    throw new UsageError(`${err.message}; node driver.mjs --help lists the verbs and their flags`);
  }
  const [verb, ...rest] = parsed.positionals;
  const unknown = new UsageError(`verbs: ${Object.keys(HELP).join(', ')}; node driver.mjs --help says what each does`);
  if (parsed.values.help) {
    if (verb !== undefined && !Object.hasOwn(HELP, verb)) throw unknown;
    console.log(helpText(verb));
    return 0;
  }
  const run = Object.hasOwn(VERBS, verb) ? VERBS[verb] : undefined;
  if (!run) throw unknown;
  if (rest.length > (ARITY[verb] ?? 0)) throw new UsageError(`${verb} got extra arguments: ${rest.join(' ')}`);
  const dryRun = parsed.values['dry-run'];
  if (dryRun && !HELP[verb]?.writes) {
    throw new UsageError(`${verb} writes and sends nothing, so it takes no --dry-run; run it without that flag`);
  }
  const broker = process.env.CCD_BROKER_SOCK;
  if (broker && BROKERED.includes(verb)) {
    if (parsed.values['real-setup']) throw new Refused('refused: --real-setup runs only attended, and the launch broker runs unattended');
    checkBrokerSocket(broker);
    const req = brokerRequest(verb, parsed.tokens.filter((t) => t.name !== 'dry-run'), rest);
    if (!dryRun) return viaBroker(broker, req, { timeoutMs: brokerDeadline(verb, parsed.values) });
    await run(parsed.values, rest);
    console.log(`dry run: would send ${JSON.stringify(req)} to the launch broker at ${broker}; sent nothing`);
    return 0;
  }
  const out = await run(parsed.values, rest);
  if (out && typeof out === 'object') {
    if (out.text) console.log(out.text);
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
