// Runs with no node_modules: driver.mjs loads the terminal engine only inside
// the session holder, and every engine below is a stub. Expected values come
// from the plan's launch contract (three flags, the auth variables unset, no
// --bare, persistence forced), the Claude Code Environment variables and LLM
// gateway pages, Node's setTimeout ceiling (2^31-1 ms), and the shared
// prerequisites checker's probe rule (the pattern is a regular expression run
// over the probe's output).
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import * as driver from './driver.mjs';
import { buildLaunch, ensureInstalled, installDir, main } from './driver.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLEARED = [
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
const posixOnly = { skip: process.platform === 'win32' && 'the stubs are POSIX scripts and modes' };
const NATIVE_FAILURE = 'failed to load the @microsoft/tui-test native addon: Cannot find native binding';

// Every session socket in this file lives under a private runtime directory of its own.
const RUNTIME = mkdtempSync(join(tmpdir(), 'ccd-rt-'));
process.env.XDG_RUNTIME_DIR = RUNTIME;
// A runner that exports either would move the sockets or send launch, ready and log to a broker.
delete process.env.CCD_RUNTIME_DIR;
delete process.env.CCD_BROKER_SOCK;
after(() => rmSync(RUNTIME, { recursive: true, force: true }));
let sessions = 0;
const session = () => `t${process.pid}-${++sessions}`;

test('launch runs claude restricted, MCP-strict, on the plugin dir, never bare', () => {
  const { argv } = buildLaunch({ pluginDir: '/repo/plugins/context-usage' }, {});
  assert.deepEqual(argv, ['claude', '--restricted', '--strict-mcp-config', '--plugin-dir', '/repo/plugins/context-usage']);
  assert.ok(!argv.includes('--bare'));
});

test('launch clears every auth, gateway and provider variable and keeps the rest', () => {
  const input = { PATH: '/usr/bin', HOME: '/u', CLAUDE_CODE_OAUTH_TOKEN: 'sub' };
  for (const name of CLEARED) input[name] = 'set-by-parent';
  const before = { ...input };
  const { env } = buildLaunch({ pluginDir: '/p' }, input);
  for (const name of CLEARED) assert.equal(name in env, false, `${name} must be unset`);
  assert.equal(env.PATH, '/usr/bin');
  assert.equal(env.HOME, '/u');
  assert.equal(env.CLAUDE_CODE_OAUTH_TOKEN, 'sub');
  assert.equal(env.CLAUDE_CODE_FORCE_SESSION_PERSISTENCE, '1');
  assert.deepEqual(input, before, 'the caller env is not mutated');
});

test('persistence and the hidden cwd are forced to 1 even when the parent set them to 0', () => {
  const { env } = buildLaunch({ pluginDir: '/p' }, { CLAUDE_CODE_FORCE_SESSION_PERSISTENCE: '0', CLAUDE_CODE_HIDE_CWD: '0' });
  assert.equal(env.CLAUDE_CODE_FORCE_SESSION_PERSISTENCE, '1');
  assert.equal(env.CLAUDE_CODE_HIDE_CWD, '1');
});

test('launch without a plugin dir is a usage error raised before any install', async () => {
  await assert.rejects(main(['launch']), { code: 2, message: 'launch needs --plugin-dir <dir>' });
});

test('a key typed as a second positional is refused, not dropped', async () => {
  await assert.rejects(main(['type', 'hello', 'Enter']), { code: 2, message: 'type got extra arguments: hello Enter' });
});

test('a ttl that is not a whole number of seconds is refused before any install', async () => {
  await assert.rejects(main(['launch', '--plugin-dir', '/p', '--ttl', 'soon']), {
    code: 2,
    message: '--ttl takes a whole number of seconds up to 2147483',
  });
});

test('an unknown verb is a usage error naming the verbs and where to read what each does', async () => {
  await assert.rejects(main(['dance']), {
    code: 2,
    message: 'verbs: launch, wait-for, type, screenshot, record, stop, doctor, ready, log, plugins; node driver.mjs --help says what each does',
  });
});

test('an unknown flag is a usage error that points to --help', async () => {
  await assert.rejects(main(['stop', '--force']), { code: 2, message: /; node driver\.mjs --help lists the verbs and their flags$/ });
});

/** Runs main with console.log captured, resolving with its status and the lines it printed. */
async function printed(args) {
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    return { status: await main(args), text: lines.join('\n') };
  } finally {
    console.log = log;
  }
}

test('--help lists every verb in one line each and exits 0', async () => {
  const { status, text } = await printed(['--help']);
  assert.equal(status, 0);
  for (const verb of Object.keys(driver.HELP)) assert.match(text, new RegExp(`^  ${verb} +\\S`, 'm'), `${verb} is listed`);
  assert.ok(!text.includes('--plugin-dir'), 'the verb list leaves each verb\'s flags to <verb> --help');
  assert.match(text, /<verb> --help/);
});

test('--help on a verb the driver does not have is the unknown-verb usage error', async () => {
  for (const verb of ['dance', 'constructor']) await assert.rejects(main([verb, '--help']), { code: 2, message: /^verbs: launch, / });
});

test('<verb> --help prints that verb\'s flags, with --dry-run only on a verb that writes or sends', async () => {
  const launch = await printed(['launch', '--help']);
  assert.equal(launch.status, 0);
  assert.match(launch.text, /^node driver\.mjs launch --plugin-dir <dir> .*\[--dry-run\]$/m);
  const doctor = await printed(['doctor', '--help']);
  assert.match(doctor.text, /^node driver\.mjs doctor \[--deps-dir <dir>\]$/m);
  for (const [verb, { writes }] of Object.entries(driver.HELP)) {
    assert.equal((await printed([verb, '--help'])).text.includes('[--dry-run]'), Boolean(writes), verb);
  }
});

test('--dry-run on a session verb prints the request and sends nothing, with no session running', async () => {
  const s = session();
  const type = await printed(['type', 'hi', '--key', 'Enter', '--session', s, '--dry-run']);
  assert.equal(type.status, 0);
  assert.equal(type.text, `dry run: would send 'type' to session '${s}' with {"text":"hi","keys":["Enter"]}; sent nothing`);
  const shot = await printed(['screenshot', 'shot.png', '--session', s, '--dry-run']);
  assert.match(shot.text, new RegExp(`would send 'screenshot' to session '${s}' with \\{"path":".*shot\\.png"\\}; sent nothing$`));
  assert.equal((await printed(['record', 'stop', '--session', s, '--dry-run'])).text, `dry run: would send 'record-stop' to session '${s}'; sent nothing`);
  assert.equal((await printed(['stop', '--session', s, '--dry-run'])).text, `dry run: would send 'stop' to session '${s}'; sent nothing`);
  await assert.rejects(main(['type', '--session', s, '--dry-run']), { code: 2, message: 'type needs <text> or --key <Name>' });
});

test('launch --dry-run prints the claude command line and reserves no session', async () => {
  const s = session();
  const plugin = mkdtempSync(join(tmpdir(), 'ccd-dry-'));
  try {
    const { status, text } = await printed(['launch', '--plugin-dir', plugin, '--session', s, '--dry-run']);
    assert.equal(status, 0);
    assert.equal(text, `dry run: would launch session '${s}' running claude --restricted --strict-mcp-config --plugin-dir ${plugin}; started nothing`);
    assert.ok(!existsSync(join(RUNTIME, 'ccd', `${s}.lock`)), 'no lock file');
    await assert.rejects(main(['launch', '--plugin-dir', plugin, '--ttl', 'soon', '--dry-run']), { code: 2 });
  } finally {
    rmSync(plugin, { recursive: true, force: true });
  }
});

test('log --dry-run prints the print-mode command line and writes no --out file', async () => {
  const plugin = mkdtempSync(join(tmpdir(), 'ccd-dry-'));
  const out = join(plugin, 'run.jsonl');
  try {
    const { status, text } = await printed(['log', 'say ok', '--plugin-dir', plugin, '--out', out, '--dry-run']);
    assert.equal(status, 0);
    assert.match(text, /^dry run: would run claude --restricted --strict-mcp-config --plugin-dir \S+ -p .* say ok and write its stream-json to \S+run\.jsonl; ran nothing$/);
    assert.ok(!existsSync(out));
  } finally {
    rmSync(plugin, { recursive: true, force: true });
  }
});

test('--dry-run on a verb that only reads is refused with what to do instead', async () => {
  await assert.rejects(main(['doctor', '--dry-run']), {
    code: 2,
    message: 'doctor writes and sends nothing, so it takes no --dry-run; run it without that flag',
  });
});

test('print mode runs the launch command line in stream-json with the prompt last', () => {
  const { argv, env } = driver.buildPrint({ pluginDir: '/p' }, { ANTHROPIC_API_KEY: 'k' }, 'say ok');
  assert.deepEqual(argv, [
    'claude',
    '--restricted',
    '--strict-mcp-config',
    '--plugin-dir',
    '/p',
    '-p',
    '--output-format',
    'stream-json',
    '--verbose',
    'say ok',
  ]);
  assert.equal('ANTHROPIC_API_KEY' in env, false);
});

test('a print-mode prompt that reads as a flag is refused', () => {
  assert.throws(() => driver.buildPrint({ pluginDir: '/p' }, {}, '--dangerously-skip-permissions'), { code: 2 });
});

test('ready and log name what they lack before claude starts', async () => {
  await assert.rejects(main(['ready', '--out', '/tmp/x.jsonl']), { code: 2, message: 'ready needs --plugin-dir <dir>' });
  await assert.rejects(main(['ready', '--plugin-dir', '/p']), { code: 2, message: 'ready needs --out <path.jsonl>' });
  await assert.rejects(main(['log', '--plugin-dir', HERE, '--out', join(RUNTIME, 'x.jsonl')]), { code: 2, message: 'print mode needs a prompt' });
  await assert.rejects(main(['log', 'hi', '--plugin-dir', join(RUNTIME, 'absent'), '--out', join(RUNTIME, 'x.jsonl')]), {
    code: 2,
    message: `--plugin-dir ${join(RUNTIME, 'absent')} does not exist`,
  });
  await assert.rejects(main(['log', 'hi', '--plugin-dir', HERE, '--out', join(RUNTIME, 'x.jsonl'), '--timeout', 'soon']), {
    code: 2,
    message: '--timeout takes a whole number of milliseconds',
  });
});

test('the control skill config keeps local.json out of git and ships every floor at its safe value', () => {
  const config = join(HERE, '..', 'config');
  assert.deepEqual(readFileSync(join(config, '.gitignore'), 'utf8').split(/\r?\n/).filter(Boolean), ['local.json']);
  const defaults = JSON.parse(readFileSync(join(config, 'defaults.json'), 'utf8'));
  assert.equal(typeof defaults.pluginDir, 'string');
  assert.ok(defaults.pluginDir.length > 0);
  assert.equal(defaults.maxCaptures, 20);
  assert.equal(defaults.maxEntryPoints, 6);
  assert.deepEqual(defaults.credentials, { ci: { apiKey: 'ANTHROPIC_API_KEY', oauthToken: 'CLAUDE_CODE_OAUTH_TOKEN' } });
  assert.deepEqual(driver.ciCredentials(), ['ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN']);
  assert.deepEqual(defaults.safety, { recipients: {}, signInAttempts: {}, production: {}, unattendedWrites: false });
});

test('credentials.ci naming a variable the driver has no key source for is refused', () => {
  const file = join(RUNTIME, 'defaults.json');
  writeFileSync(file, JSON.stringify({ credentials: { ci: { other: 'ANTHROPIC_AUTH_TOKEN' } } }));
  assert.throws(() => driver.ciCredentials(file), { code: 2, message: /credentials\.ci names ANTHROPIC_AUTH_TOKEN/ });
});

const CI = ['ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN'];

test('attended clears the API key, passes the person\'s own OAuth token through, and requires "none"', () => {
  // The config an attended verb builds: no --unattended, no CI names.
  const { env, keySource } = buildLaunch({ pluginDir: '/p' }, { ANTHROPIC_API_KEY: 'fake', CLAUDE_CODE_OAUTH_TOKEN: 'fake' });
  assert.equal('ANTHROPIC_API_KEY' in env, false);
  assert.equal(env.CLAUDE_CODE_OAUTH_TOKEN, 'fake');
  assert.equal('CLAUDE_CODE_SUBPROCESS_ENV_SCRUB' in env, false);
  assert.equal(keySource, 'none');
});

test('unattended keeps the one CI credential set, scrubs it from subprocesses, and accepts its key source', () => {
  for (const [name, source] of [
    ['ANTHROPIC_API_KEY', 'ANTHROPIC_API_KEY'],
    ['CLAUDE_CODE_OAUTH_TOKEN', 'none'],
  ]) {
    const { env, keySource } = buildLaunch({ pluginDir: '/p', unattended: true, credentials: CI }, { [name]: 'fake', ANTHROPIC_AUTH_TOKEN: 'x' });
    assert.equal(env[name], 'fake', name);
    assert.equal(env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB, '1', name);
    assert.equal('ANTHROPIC_AUTH_TOKEN' in env, false, 'every other auth variable is still cleared');
    assert.equal(keySource, source, name);
  }
});

test('unattended with no CI credential set runs as attended does', () => {
  const { env, keySource } = buildLaunch({ pluginDir: '/p', unattended: true, credentials: CI }, { PATH: '/usr/bin' });
  assert.equal('CLAUDE_CODE_SUBPROCESS_ENV_SCRUB' in env, false);
  assert.equal(keySource, 'none');
});

// The launch the #13711 probe ran in the sibling sandbox (probe-13711-bash.yml at 6764ca031f8):
// LAUNCH_FLAGS ['--strict-mcp-config'] and no scrub line, so Bash is in the default tools.
test('in-sandbox drops --restricted and the scrub, and still keeps the one CI credential', () => {
  const { argv, env, keySource } = buildLaunch(
    { pluginDir: '/p', unattended: true, credentials: CI, inSandbox: true },
    { ANTHROPIC_API_KEY: 'ccd-dummy-x', ANTHROPIC_AUTH_TOKEN: 'x' },
  );
  assert.deepEqual(argv, ['claude', '--strict-mcp-config', '--plugin-dir', '/p']);
  assert.equal('CLAUDE_CODE_SUBPROCESS_ENV_SCRUB' in env, false);
  assert.equal(env.ANTHROPIC_API_KEY, 'ccd-dummy-x');
  assert.equal('ANTHROPIC_AUTH_TOKEN' in env, false);
  assert.equal(keySource, 'ANTHROPIC_API_KEY');
});

test('in-sandbox refuses unless the launch keeps a broker dummy key: --restricted and the scrub never drop around a real one', () => {
  for (const [config, env] of [
    [{ pluginDir: '/p', inSandbox: true }, {}],
    [{ pluginDir: '/p', unattended: true, credentials: CI, inSandbox: true }, {}],
    [{ pluginDir: '/p', unattended: true, credentials: CI, inSandbox: true }, { ANTHROPIC_API_KEY: 'sk-ant-x' }],
    [{ pluginDir: '/p', unattended: true, credentials: CI, inSandbox: true }, { ANTHROPIC_API_KEY: 'ccd-dummy-' }],
    [{ pluginDir: '/p', unattended: true, credentials: CI, inSandbox: true }, { CLAUDE_CODE_OAUTH_TOKEN: 'ccd-dummy-x' }],
  ]) {
    assert.throws(() => buildLaunch(config, env), /--in-sandbox/, JSON.stringify(env));
  }
});

test('unattended refuses two CI credentials set at once, before anything runs', async () => {
  const saved = { ...process.env };
  process.env.ANTHROPIC_API_KEY = 'fake';
  process.env.CLAUDE_CODE_OAUTH_TOKEN = 'fake';
  try {
    for (const args of [
      ['launch', '--plugin-dir', '/p', '--unattended'],
      ['ready', '--plugin-dir', HERE, '--out', join(RUNTIME, 'x.jsonl'), '--unattended'],
    ]) {
      await assert.rejects(main(args), { code: 1, message: /ANTHROPIC_API_KEY and CLAUDE_CODE_OAUTH_TOKEN are both set/ });
    }
    assert.equal(existsSync(join(RUNTIME, 'x.jsonl')), false, 'ready started no claude');
  } finally {
    for (const name of CI) {
      if (saved[name] === undefined) delete process.env[name];
      else process.env[name] = saved[name];
    }
  }
});

test('the Windows repair line enters the install dir instead of passing it to npm.cmd', () => {
  const line = driver.repairLine('D:\\work dir\\deps', 'win32');
  assert.ok(line.includes("Set-Location -LiteralPath 'D:\\work dir\\deps'; npm.cmd ci --ignore-scripts --no-audit --no-fund"), line);
  assert.ok(!line.includes('--prefix'), line);
});

// ---- stubs: npm, fc-list and the engine on a private PATH ----

function sandbox({ npm = 'exit 1', engine } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'ccd-test-'));
  const bin = join(root, 'bin');
  const deps = join(root, 'deps');
  mkdirSync(bin, { mode: 0o700 });
  mkdirSync(deps, { mode: 0o700 });
  writeFileSync(join(bin, 'npm'), `#!/bin/sh\n${npm}\n`, { mode: 0o755 });
  if (engine) writeFileSync(join(bin, 'engine.js'), engine);
  return { root, bin, deps, target: installDir(deps) };
}

function placeEngine(dir, source, { marked = false } = {}) {
  const engine = join(dir, 'node_modules', '@microsoft', 'tui-test');
  mkdirSync(join(engine, 'dist'), { recursive: true, mode: 0o700 });
  writeFileSync(join(engine, 'package.json'), '{"type":"module"}');
  writeFileSync(join(engine, 'dist', 'index.js'), source);
  if (marked) writeFileSync(join(dir, '.signatures-verified'), 'stub\n');
}

async function withPath(bin, fn) {
  const saved = process.env.PATH;
  process.env.PATH = `${bin}${delimiter}${saved}`;
  try {
    return await fn();
  } finally {
    process.env.PATH = saved;
  }
}

// An engine whose binding loads only when a process is run, as the real one does.
const RUNS = `let ran = false;
export const TuiTest = { ephemeral: () => ({
  run: async () => { ran = true; },
  close: async () => { if (!ran) throw new Error('close before run: the binding never loaded'); },
  closeQuiet: async () => { throw new Error('closeQuiet hides a binding that never loaded'); },
}) };
`;
// An engine that answers every call; for cases about the install, not the probe.
const ANSWERS = `export const TuiTest = { ephemeral: () => ({
  run: async () => {},
  close: async () => {},
  closeQuiet: async () => {},
}) };
`;
const NATIVE_BROKEN = `export const TuiTest = { ephemeral: () => ({
  run: async () => { throw new Error(${JSON.stringify(NATIVE_FAILURE)}); },
  close: async () => {},
  closeQuiet: async () => {},
}) };
`;

test('a repaired install whose engine does not load fails closed with the repair line, unmarked', posixOnly, async () => {
  const box = sandbox({ npm: 'exit 0' });
  placeEngine(box.target, "throw new Error('engine refuses to load');\n");
  try {
    await assert.rejects(
      withPath(box.bin, () => ensureInstalled(box.deps)),
      (err) => {
        assert.equal(err.code, 4);
        assert.match(err.message, /^the installed engine does not load \(.*engine refuses to load.*\); repair: rm -rf /);
        return true;
      },
    );
    assert.equal(existsSync(join(box.target, '.signatures-verified')), false);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a repaired install whose native binding is missing fails the load probe', posixOnly, async () => {
  const box = sandbox({ npm: 'exit 0' });
  placeEngine(box.target, NATIVE_BROKEN);
  try {
    await assert.rejects(
      withPath(box.bin, () => ensureInstalled(box.deps)),
      (err) => {
        assert.equal(err.code, 4);
        assert.ok(err.message.includes(`does not load (${NATIVE_FAILURE})`), err.message);
        return true;
      },
    );
    assert.equal(existsSync(join(box.target, '.signatures-verified')), false);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a repaired install whose engine runs a process is marked verified, then reused without npm', posixOnly, async () => {
  const box = sandbox({ npm: 'exit 0' });
  placeEngine(box.target, RUNS);
  try {
    assert.equal(await withPath(box.bin, () => ensureInstalled(box.deps)), box.target);
    assert.equal(existsSync(join(box.target, '.signatures-verified')), true);
    writeFileSync(join(box.bin, 'npm'), '#!/bin/sh\nexit 1\n', { mode: 0o755 });
    assert.equal(await withPath(box.bin, () => ensureInstalled(box.deps)), box.target);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('an install dir a failed repair left without an engine is replaced, and dead partials are reaped', posixOnly, async () => {
  const ci = [
    'if [ "$1" = ci ]; then',
    '  mkdir -p node_modules/@microsoft/tui-test/dist',
    '  cp "$(dirname "$0")/engine.js" node_modules/@microsoft/tui-test/dist/index.js',
    `  echo '{"type":"module"}' > node_modules/@microsoft/tui-test/package.json`,
    'fi',
    'exit 0',
  ].join('\n');
  const box = sandbox({ npm: ci, engine: ANSWERS });
  mkdirSync(box.target, { recursive: true, mode: 0o700 });
  writeFileSync(join(box.target, 'package.json'), '{}');
  const stale = `${box.target}.partial-99999999`;
  mkdirSync(stale);
  writeFileSync(join(stale, 'package.json'), '{}');
  try {
    assert.equal(await withPath(box.bin, () => ensureInstalled(box.deps)), box.target);
    assert.equal(existsSync(join(box.target, 'node_modules', '@microsoft', 'tui-test', 'dist', 'index.js')), true);
    assert.equal(existsSync(stale), false);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a ttl above the setTimeout ceiling is refused before any install; the ceiling itself is not', posixOnly, async () => {
  const box = sandbox();
  try {
    await withPath(box.bin, async () => {
      const args = ['launch', '--plugin-dir', '/p', '--deps-dir', box.deps];
      await assert.rejects(main([...args, '--session', session(), '--ttl', '2147484']), {
        code: 2,
        message: '--ttl takes a whole number of seconds up to 2147483',
      });
      // The failing npm stub stops the install: past the usage check, the install is the step that fails.
      await assert.rejects(main([...args, '--session', session(), '--ttl', '2147483']), { code: 4 });
    });
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a wait-for timeout that is not a whole number of milliseconds is a usage error', async () => {
  await assert.rejects(main(['wait-for', 'ready', '--timeout', 'soon', '--session', session()]), {
    code: 2,
    message: '--timeout takes a whole number of milliseconds',
  });
  await assert.rejects(main(['wait-for', 'ready', '--timeout', '5', '--session', session()]), { code: 3 });
});

test('session sockets live in $XDG_RUNTIME_DIR/ccd, created private', posixOnly, async () => {
  await assert.rejects(main(['stop', '--session', session()]), { code: 3 });
  const st = statSync(join(RUNTIME, 'ccd'));
  assert.equal(st.mode & 0o777, 0o700);
});

test('without $XDG_RUNTIME_DIR, session sockets live under the home cache directory', posixOnly, async () => {
  const home = mkdtempSync(join(tmpdir(), 'ccd-home-'));
  const saved = { HOME: process.env.HOME, XDG: process.env.XDG_RUNTIME_DIR };
  process.env.HOME = home;
  delete process.env.XDG_RUNTIME_DIR;
  try {
    await assert.rejects(main(['stop', '--session', session()]), { code: 3 });
    assert.equal(statSync(join(home, '.cache', 'ccd')).mode & 0o777, 0o700);
  } finally {
    process.env.HOME = saved.HOME;
    process.env.XDG_RUNTIME_DIR = saved.XDG;
    rmSync(home, { recursive: true, force: true });
  }
});

test('a socket directory others can write is refused as unsafe, not as a broken install', posixOnly, async () => {
  const runtime = mkdtempSync(join(tmpdir(), 'ccd-rt-open-'));
  mkdirSync(join(runtime, 'ccd'));
  chmodSync(join(runtime, 'ccd'), 0o777);
  process.env.XDG_RUNTIME_DIR = runtime;
  try {
    await assert.rejects(main(['stop', '--session', session()]), (err) => {
      assert.equal(err.code, 5);
      assert.match(err.message, /is not a private directory owned by you/);
      assert.doesNotMatch(err.message, /repair/);
      return true;
    });
  } finally {
    process.env.XDG_RUNTIME_DIR = RUNTIME;
    rmSync(runtime, { recursive: true, force: true });
  }
});

test('an explicit --deps-dir others can write is refused; a private one is used', posixOnly, async () => {
  const box = sandbox();
  const open = join(box.root, 'open');
  mkdirSync(open);
  chmodSync(open, 0o777);
  try {
    await withPath(box.bin, async () => {
      await assert.rejects(main(['doctor', '--deps-dir', open]), { code: 5 });
      assert.equal(await main(['doctor', '--deps-dir', box.deps]), 0);
    });
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('doctor runs the font probe declared in prerequisites.json', posixOnly, async () => {
  const declared = JSON.parse(readFileSync(join(HERE, '..', '..', '..', 'prerequisites.json'), 'utf8'));
  const { probe } = declared.requires.find((e) => e.id === 'noto-sans-symbols-2').detect;
  const box = sandbox();
  writeFileSync(join(box.bin, probe.args[0]), `#!/bin/sh\necho "$@" > "$(dirname "$0")/args"\necho 'DejaVu Sans'\n`, {
    mode: 0o755,
  });
  const lines = [];
  const log = console.log;
  console.log = (s) => lines.push(s);
  try {
    await withPath(box.bin, () => main(['doctor', '--deps-dir', box.deps]));
  } finally {
    console.log = log;
  }
  try {
    assert.equal(readFileSync(join(box.bin, 'args'), 'utf8').trim(), probe.args.slice(1).join(' '));
    assert.match(lines.join('\n'), /font: .*MISSING/);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('the Windows pipe name carries the random suffix the launch recorded', async () => {
  const data = mkdtempSync(join(tmpdir(), 'ccd-appdata-'));
  const saved = process.env.LOCALAPPDATA;
  process.env.LOCALAPPDATA = data;
  try {
    assert.throws(() => driver.endpoint('w1', 'win32'), { code: 3 });
    mkdirSync(join(data, 'ccd'), { recursive: true });
    writeFileSync(join(data, 'ccd', 'w1.pipe'), '0123abcd');
    assert.match(driver.endpoint('w1', 'win32').sock, /^\\\\\.\\pipe\\ccd-[0-9a-f]{8}-w1-0123abcd$/);
  } finally {
    if (saved === undefined) delete process.env.LOCALAPPDATA;
    else process.env.LOCALAPPDATA = saved;
    rmSync(data, { recursive: true, force: true });
  }
});

// ---- the holder, run against stub engines ----

test('a verified install whose native binding has since gone fails launch with the repair line', posixOnly, async () => {
  const box = sandbox();
  placeEngine(box.target, NATIVE_BROKEN, { marked: true });
  try {
    await withPath(box.bin, () =>
      assert.rejects(main(['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', session(), '--ttl', '60']), (err) => {
        assert.equal(err.code, 4);
        assert.ok(err.message.includes(NATIVE_FAILURE), err.message);
        assert.match(err.message, /; repair: rm -rf /);
        return true;
      }),
    );
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('the holder exits and frees the session when claude exits', posixOnly, async () => {
  // claude "exits" once the test writes the sentinel; until then the session answers.
  const box = sandbox();
  const sentinel = join(box.root, 'claude-exited');
  const exits = `import { existsSync } from 'node:fs';
export const TuiTest = { ephemeral: () => ({
  run: async () => {},
  state: async () => ({ exited: existsSync(${JSON.stringify(sentinel)}) ? 0 : null, exit_signal: null }),
  type: async () => {},
  close: async () => {},
  closeQuiet: async () => {},
}) };
`;
  placeEngine(box.target, exits, { marked: true });
  const name = session();
  try {
    await withPath(box.bin, () => main(['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '60']));
    assert.equal(await main(['type', 'x', '--session', name]), 0, 'the session answers while claude runs');
    writeFileSync(sentinel, '');
    let code;
    for (const deadline = Date.now() + 10_000; Date.now() < deadline; ) {
      code = await main(['type', 'x', '--session', name]).then(
        () => 0,
        (err) => err.code,
      );
      if (code === 3) break;
      await new Promise((r) => setTimeout(r, 250));
    }
    assert.equal(code, 3, 'the session is gone once claude has exited');
  } finally {
    await main(['stop', '--session', name]).catch(() => {});
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('an unattended run drives the session it launched: no terminal, no key, cwd hidden, then stopped', posixOnly, async () => {
  // The engine records what the holder hands claude; the launch runs with no terminal on stdin.
  const box = sandbox();
  const seen = join(box.root, 'seen.json');
  const records = `import { writeFileSync } from 'node:fs';
export const TuiTest = { ephemeral: () => ({
  run: async (cmd, args, opts) => writeFileSync(${JSON.stringify(seen)}, JSON.stringify({
    cmd, args, tty: Boolean(process.stdin.isTTY),
    key: opts.env.ANTHROPIC_API_KEY ?? null, hide: opts.env.CLAUDE_CODE_HIDE_CWD ?? null,
  })),
  state: async () => ({ exited: null, exit_signal: null }),
  type: async () => {},
  close: async () => {},
  closeQuiet: async () => {},
}) };
`;
  placeEngine(box.target, records, { marked: true });
  const name = session();
  const saved = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'from-parent';
  try {
    await withPath(box.bin, () => main(['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '60']));
    assert.equal(await main(['type', 'x', '--session', name]), 0, 'the launched session takes input');
    const got = JSON.parse(readFileSync(seen, 'utf8'));
    assert.equal(got.cmd, 'claude');
    assert.deepEqual(got.args, ['--restricted', '--strict-mcp-config', '--plugin-dir', '/p']);
    assert.equal(got.tty, false, 'the holder runs with no terminal for a person');
    assert.equal(got.key, null, 'the parent key never reaches claude');
    assert.equal(got.hide, '1');
    assert.equal(await main(['stop', '--session', name]), 0);
    await assert.rejects(main(['type', 'x', '--session', name]), { code: 3 });
  } finally {
    if (saved === undefined) delete process.env.ANTHROPIC_API_KEY;
    else process.env.ANTHROPIC_API_KEY = saved;
    await main(['stop', '--session', name]).catch(() => {});
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('an unattended launch hands claude the one CI credential with the subprocess scrub on', posixOnly, async () => {
  const box = sandbox();
  const seen = join(box.root, 'seen.json');
  const records = `import { writeFileSync } from 'node:fs';
export const TuiTest = { ephemeral: () => ({
  run: async (cmd, args, opts) => writeFileSync(${JSON.stringify(seen)}, JSON.stringify({
    key: opts.env.ANTHROPIC_API_KEY ?? null, scrub: opts.env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB ?? null,
  })),
  state: async () => ({ exited: null, exit_signal: null }),
  type: async () => writeFileSync(${JSON.stringify(seen)} + '.holder', process.env.ANTHROPIC_API_KEY ?? 'unset'),
  close: async () => {},
  closeQuiet: async () => {},
}) };
`;
  placeEngine(box.target, records, { marked: true });
  const name = session();
  const saved = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'fake-ci';
  try {
    await withPath(box.bin, () => main(['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '60', '--unattended']));
    const got = JSON.parse(readFileSync(seen, 'utf8'));
    assert.equal(got.key, 'fake-ci');
    assert.equal(got.scrub, '1');
    assert.equal(await main(['type', 'x', '--session', name]), 0);
    assert.equal(readFileSync(`${seen}.holder`, 'utf8'), 'unset', 'the holder drops the key once claude has it');
    assert.equal(await main(['stop', '--session', name]), 0);
  } finally {
    if (saved === undefined) delete process.env.ANTHROPIC_API_KEY;
    else process.env.ANTHROPIC_API_KEY = saved;
    await main(['stop', '--session', name]).catch(() => {});
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('an in-sandbox launch reaches the holder: claude starts without --restricted and with no scrub', posixOnly, async () => {
  const box = sandbox();
  const seen = join(box.root, 'seen.json');
  const records = `import { writeFileSync } from 'node:fs';
export const TuiTest = { ephemeral: () => ({
  run: async (cmd, args, opts) => writeFileSync(${JSON.stringify(seen)}, JSON.stringify({
    args, key: opts.env.ANTHROPIC_API_KEY ?? null, scrub: opts.env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB ?? null,
  })),
  state: async () => ({ exited: null, exit_signal: null }),
  type: async () => {},
  close: async () => {},
  closeQuiet: async () => {},
}) };
`;
  placeEngine(box.target, records, { marked: true });
  const name = session();
  const saved = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'ccd-dummy-x';
  try {
    await withPath(box.bin, () =>
      main(['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '60', '--unattended', '--in-sandbox']),
    );
    const got = JSON.parse(readFileSync(seen, 'utf8'));
    assert.deepEqual(got.args, ['--strict-mcp-config', '--plugin-dir', '/p']);
    assert.equal(got.key, 'ccd-dummy-x');
    assert.equal(got.scrub, null);
    assert.equal(await main(['stop', '--session', name]), 0);
  } finally {
    if (saved === undefined) delete process.env.ANTHROPIC_API_KEY;
    else process.env.ANTHROPIC_API_KEY = saved;
    await main(['stop', '--session', name]).catch(() => {});
    rmSync(box.root, { recursive: true, force: true });
  }
});

const isAlive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

test('two concurrent launches of one session start one holder; the other is refused', posixOnly, async () => {
  // Each holder records its pid when it starts claude, so the test can see every holder that ran.
  const box = sandbox();
  const pids = join(box.root, 'holders');
  mkdirSync(pids);
  const records = `import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
export const TuiTest = { ephemeral: () => ({
  run: async () => { writeFileSync(join(${JSON.stringify(pids)}, String(process.pid)), ''); },
  state: async () => ({ exited: null, exit_signal: null }),
  close: async () => {},
  closeQuiet: async () => {},
}) };
`;
  placeEngine(box.target, records, { marked: true });
  const name = session();
  const args = ['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '30'];
  const holders = () => readdirSync(pids).map(Number);
  try {
    const results = await withPath(box.bin, () => Promise.allSettled([main(args), main(args)]));
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1, 'exactly one launch succeeds');
    const refused = results.find((r) => r.status === 'rejected')?.reason;
    assert.equal(refused?.code, 2);
    assert.equal(refused?.message, `session '${name}' is already running; run stop first`);
    assert.equal(await main(['stop', '--session', name]), 0);
    let running = holders();
    for (const deadline = Date.now() + 10_000; Date.now() < deadline && running.some(isAlive); ) {
      await new Promise((r) => setTimeout(r, 100));
      running = holders();
    }
    assert.deepEqual(running.filter(isAlive), [], 'stop leaves no holder running');
  } finally {
    for (const pid of holders().filter(isAlive)) process.kill(pid);
    rmSync(box.root, { recursive: true, force: true });
  }
});

// ---- print mode, run against a stub claude ----

const initLine = (source) =>
  JSON.stringify({ type: 'system', subtype: 'init', apiKeySource: source, claude_code_version: '9.9.9', plugins: [{ name: 'demo', path: '/p' }] });

// A claude that records its argv and the key it was given, prints the init event, then runs `rest`.
function stubClaude(box, source, rest) {
  const script = [
    '#!/bin/sh',
    `printf '%s\\n' "$@" > "${box.root}/argv"`,
    `printf '%s' "\${ANTHROPIC_API_KEY-unset}" > "${box.root}/key"`,
    `printf '%s\\n' '${initLine(source)}'`,
    rest,
  ].join('\n');
  writeFileSync(join(box.bin, 'claude'), `${script}\n`, { mode: 0o755 });
}

// The plugin under test: a directory whose manifest carries `name`.
function pluginDir(box, name = 'demo') {
  const dir = join(box.root, 'plugin');
  mkdirSync(join(dir, '.claude-plugin'), { recursive: true });
  writeFileSync(join(dir, '.claude-plugin', 'plugin.json'), JSON.stringify({ name }));
  return dir;
}

async function quietly(fn) {
  const lines = [];
  const log = console.log;
  console.log = (s) => lines.push(s);
  try {
    return { result: await fn(), text: lines.join('\n') };
  } finally {
    console.log = log;
  }
}

test('ready stops claude at the init event and passes on apiKeySource "none"', posixOnly, async () => {
  const box = sandbox();
  // exec, so stopping the stub stops the process holding its stdout
  stubClaude(box, 'none', 'exec sleep 30');
  const out = join(box.root, 'init.jsonl');
  const saved = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'from-parent';
  try {
    const started = Date.now();
    const { result, text } = await withPath(box.bin, () =>
      quietly(() => main(['ready', '--plugin-dir', pluginDir(box), '--out', out, '--deps-dir', box.deps])),
    );
    assert.equal(result, 0);
    assert.ok(Date.now() - started < 20_000, 'claude was stopped, not waited out');
    assert.match(text, /apiKeySource: none/);
    assert.match(text, /plugins: demo/);
    assert.match(text, /session 'default': not running/);
    assert.doesNotMatch(text, /refused/);
    assert.equal(readFileSync(out, 'utf8').trim(), initLine('none'));
    assert.equal(readFileSync(join(box.root, 'key'), 'utf8'), 'unset');
    assert.deepEqual(readFileSync(join(box.root, 'argv'), 'utf8').trim().split('\n').slice(-5), [
      '-p',
      '--output-format',
      'stream-json',
      '--verbose',
      'Reply with the single word ok.',
    ]);
  } finally {
    if (saved === undefined) delete process.env.ANTHROPIC_API_KEY;
    else process.env.ANTHROPIC_API_KEY = saved;
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('ready exits 1 when the init event names an API key', posixOnly, async () => {
  const box = sandbox();
  stubClaude(box, 'apiKeyHelper', 'exec sleep 30');
  try {
    const { result, text } = await withPath(box.bin, () =>
      quietly(() => main(['ready', '--plugin-dir', pluginDir(box), '--out', join(box.root, 'init.jsonl'), '--deps-dir', box.deps])),
    );
    assert.equal(result, 1);
    assert.match(text, /refused: apiKeySource is "apiKeyHelper"/);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('ready still requires apiKeySource "none": every key source is refused', posixOnly, async () => {
  // The non-none values of the ApiKeySource table the driver's pointer names.
  for (const source of ['user', 'project', 'org', 'temporary', 'apiKeyHelper', 'ANTHROPIC_API_KEY', '/login managed key']) {
    const box = sandbox();
    stubClaude(box, source, 'exec sleep 30');
    try {
      const { result, text } = await withPath(box.bin, () =>
        quietly(() => main(['ready', '--plugin-dir', pluginDir(box), '--out', join(box.root, 'init.jsonl'), '--deps-dir', box.deps])),
      );
      assert.equal(result, 1, source);
      assert.match(text, new RegExp(`refused: apiKeySource is "${source}", not "none"; drive nothing`));
    } finally {
      rmSync(box.root, { recursive: true, force: true });
    }
  }
});

test('ready exits 1 when the init event does not list the plugin under test', posixOnly, async () => {
  const box = sandbox();
  stubClaude(box, 'none', 'exec sleep 30');
  try {
    const dir = pluginDir(box, 'other');
    const { result, text } = await withPath(box.bin, () =>
      quietly(() => main(['ready', '--plugin-dir', dir, '--out', join(box.root, 'init.jsonl'), '--deps-dir', box.deps])),
    );
    assert.equal(result, 1);
    assert.match(text, /refused: the init event does not list the plugin at /);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('ready exits 1 when claude prints no init event', posixOnly, async () => {
  const box = sandbox();
  writeFileSync(join(box.bin, 'claude'), '#!/bin/sh\necho not json\nexit 0\n', { mode: 0o755 });
  try {
    const { result, text } = await withPath(box.bin, () =>
      quietly(() => main(['ready', '--plugin-dir', pluginDir(box), '--out', join(box.root, 'init.jsonl'), '--deps-dir', box.deps])),
    );
    assert.equal(result, 1);
    assert.match(text, /init: no init event$/m);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('ready gives up on a claude that prints nothing once --timeout passes', posixOnly, async () => {
  const box = sandbox();
  writeFileSync(join(box.bin, 'claude'), '#!/bin/sh\nexec sleep 30\n', { mode: 0o755 });
  try {
    const started = Date.now();
    const args = ['ready', '--plugin-dir', pluginDir(box), '--out', join(box.root, 'init.jsonl'), '--deps-dir', box.deps, '--timeout', '500'];
    const { result, text } = await withPath(box.bin, () => quietly(() => main(args)));
    assert.equal(result, 1);
    assert.match(text, /init: no init event within 500 ms/);
    assert.ok(Date.now() - started < 20_000, 'claude was stopped at the timeout');
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('log keeps the whole stream-json run and exits with claude', posixOnly, async () => {
  const box = sandbox();
  const result = JSON.stringify({ type: 'result', subtype: 'success' });
  stubClaude(box, 'none', `printf '%s\\n' '${result}'\nexit 0`);
  const out = join(box.root, 'run.jsonl');
  try {
    const { result: status } = await withPath(box.bin, () =>
      quietly(() => main(['log', 'run /demo', '--plugin-dir', pluginDir(box), '--out', out])),
    );
    assert.equal(status, 0);
    assert.deepEqual(readFileSync(out, 'utf8').trim().split('\n'), [initLine('none'), result]);
    assert.equal(readFileSync(join(box.root, 'argv'), 'utf8').trim().split('\n').at(-1), 'run /demo');
    assert.equal(statSync(out).mode & 0o777, 0o600);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('log exits 1 and names the exit when claude fails', posixOnly, async () => {
  const box = sandbox();
  stubClaude(box, 'none', 'exit 3');
  try {
    const { result, text } = await withPath(box.bin, () =>
      quietly(() => main(['log', 'run /demo', '--plugin-dir', pluginDir(box), '--out', join(box.root, 'run.jsonl')])),
    );
    assert.equal(result, 1);
    assert.match(text, /claude exit 3, apiKeySource none/);
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('log stops claude and every process it started when the init event names an API key', posixOnly, async () => {
  const box = sandbox();
  // No exec: the sleep is a child of the stub and holds its stdout, as a wrapper's child would.
  stubClaude(box, 'ANTHROPIC_API_KEY', 'sleep 30');
  const out = join(box.root, 'run.jsonl');
  try {
    const started = Date.now();
    const { result, text } = await withPath(box.bin, () =>
      quietly(() => main(['log', 'run /demo', '--plugin-dir', pluginDir(box), '--out', out])),
    );
    assert.equal(result, 1);
    assert.ok(Date.now() - started < 20_000, 'claude was stopped, not waited out');
    assert.match(text, /refused: apiKeySource is "ANTHROPIC_API_KEY"/);
    assert.equal(readFileSync(out, 'utf8').trim(), initLine('ANTHROPIC_API_KEY'));
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('unattended with the CI API key: ready and log accept that source and hand claude the key', posixOnly, async () => {
  const saved = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'fake-ci';
  try {
    const box = sandbox();
    try {
      stubClaude(box, 'ANTHROPIC_API_KEY', 'exec sleep 30');
      const args = ['ready', '--plugin-dir', pluginDir(box), '--out', join(box.root, 'init.jsonl'), '--deps-dir', box.deps];
      const unattended = await withPath(box.bin, () => quietly(() => main([...args, '--unattended'])));
      assert.equal(unattended.result, 0);
      assert.doesNotMatch(unattended.text, /refused/);
      assert.equal(readFileSync(join(box.root, 'key'), 'utf8'), 'fake-ci');
      const attended = await withPath(box.bin, () => quietly(() => main(args)));
      assert.equal(attended.result, 1, 'attended still requires "none"');
      assert.equal(readFileSync(join(box.root, 'key'), 'utf8'), 'unset');
      stubClaude(box, 'ANTHROPIC_API_KEY', `printf '%s\\n' '{"type":"result"}'\nexit 0`);
      const logged = await withPath(box.bin, () =>
        quietly(() => main(['log', 'run /demo', '--plugin-dir', pluginDir(box), '--out', join(box.root, 'run.jsonl'), '--unattended'])),
      );
      assert.equal(logged.result, 0);
      assert.match(logged.text, /exit 0, apiKeySource ANTHROPIC_API_KEY\)$/);
    } finally {
      rmSync(box.root, { recursive: true, force: true });
    }
    const box2 = sandbox();
    try {
      stubClaude(box2, 'none', 'exec sleep 30');
      const { result, text } = await withPath(box2.bin, () =>
        quietly(() => main(['ready', '--plugin-dir', pluginDir(box2), '--out', join(box2.root, 'init.jsonl'), '--deps-dir', box2.deps, '--unattended'])),
      );
      assert.equal(result, 1, 'a kept API key that reports "none" is not the source the driver expects');
      assert.match(text, /refused: apiKeySource is "none", not "ANTHROPIC_API_KEY"; drive nothing/);
    } finally {
      rmSync(box2.root, { recursive: true, force: true });
    }
  } finally {
    if (saved === undefined) delete process.env.ANTHROPIC_API_KEY;
    else process.env.ANTHROPIC_API_KEY = saved;
  }
});

test('log reports a claude missing from PATH', posixOnly, async () => {
  const box = sandbox();
  const saved = process.env.PATH;
  process.env.PATH = box.bin;
  try {
    await assert.rejects(main(['log', 'run /demo', '--plugin-dir', pluginDir(box), '--out', join(box.root, 'run.jsonl')]), {
      message: 'claude is not on PATH',
    });
  } finally {
    process.env.PATH = saved;
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a reservation left by a process that is gone is reclaimed, and a launch right after stop is not refused', posixOnly, async () => {
  const box = sandbox();
  const runs = `export const TuiTest = { ephemeral: () => ({
  run: async () => {},
  state: async () => ({ exited: null, exit_signal: null }),
  close: async () => {},
  closeQuiet: async () => {},
}) };
`;
  placeEngine(box.target, runs, { marked: true });
  const name = session();
  // 99999999 is above the largest pid Linux (2^22) or macOS (99998) assigns, so no process holds it.
  mkdirSync(join(RUNTIME, 'ccd'), { recursive: true, mode: 0o700 });
  writeFileSync(join(RUNTIME, 'ccd', `${name}.lock`), '99999999');
  const args = ['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '30'];
  try {
    await withPath(box.bin, async () => {
      assert.equal(await main(args), 0, 'a dead reservation does not block the launch');
      assert.equal(await main(['stop', '--session', name]), 0);
      assert.equal(await main(args), 0, 'a launch right after stop is not refused');
    });
  } finally {
    await main(['stop', '--session', name]).catch(() => {});
    rmSync(box.root, { recursive: true, force: true });
  }
});

// ---- masks ----
// The fixtures are rewrites of real /status and /usage screens with every value invented; the
// values each test expects hidden are the invented ones, read off the fixture by hand.

const fixture = (name) => readFileSync(join(HERE, 'fixtures', name), 'utf8').replace(/\n$/, '');
const MASKS = driver.readMasks(readFileSync(join(HERE, '..', 'SKILL.md'), 'utf8'));
const VALUES = ['user@example.com', 'Example Org'];

/** Terminal cells for screen text, one per code point, default colors; `cols` pads each row with blanks. */
function toCells(text, cols = 0) {
  return text.split('\n').flatMap((line, y) =>
    Array.from(line.padEnd(cols)).map((char, x) => ({ x, y, char, fg: 'default', bg: 'default', bold: false, link: '', link_id: '' })),
  );
}

const COLS = 40;
const maskRow = (row, values = [], cols = COLS) => driver.maskCells(toCells(row, cols), MASKS, values).text;

test('two plan names mask to the same row: the stars run to the row end, so their count shows no length', () => {
  const ultra = maskRow('Opus 5.5 · Claude Ultra');
  assert.equal(ultra, maskRow('Opus 5.5 · Claude Max'));
  assert.equal(ultra, `Opus 5.5 · ${'*'.repeat(COLS - 11)}`);
});

test('a bordered pane row masks the plan only up to its border, and keeps the border', () => {
  assert.equal(maskRow('│ Opus 5.5 · Claude Max  │ Tips', [], 0), '│ Opus 5.5 · ************│ Tips');
  assert.equal(maskRow('│ Opus 5.5 · Claude Ultra│ Tips', [], 0), '│ Opus 5.5 · ************│ Tips');
});

test('the usage notice masks from its first match to the row end, so nothing after it marks where the values end', () => {
  const row = "You've used 85% of your weekly limit · resets Nov 9 at 3am · /usage-credits to keep using Claude";
  assert.equal(maskRow(row, [], 0), `You've used ${'*'.repeat(row.length - 12)}`);
});

test('an email value in a bordered row masks to the border and keeps it', () => {
  assert.equal(maskRow('│ Email: kim@example.org    │ ok │', ['kim@example.org'], 0), '│ Email: *******************│ ok │');
});

test('a row shorter than the screen is masked to the screen width maskCells is given', () => {
  const { text } = driver.maskCells(toCells('Opus 5.5 · Claude Max'), MASKS, [], COLS);
  assert.equal(text, `Opus 5.5 · ${'*'.repeat(COLS - 11)}`);
});

test('the status screen keeps its labels and loses the account, session, cwd and usage values', () => {
  const { text } = driver.maskCells(toCells(fixture('status-screen.txt')), MASKS, VALUES);
  for (const hidden of ['user@example.com', 'Example Org', '00000000-0000', '/home/<user>/project', '42%', 'Jan 7', 'Claude Max account']) {
    assert.ok(!text.includes(hidden), `${hidden} is masked`);
  }
  for (const kept of ['Version:           2.1.316', 'Email:             ****************', 'Organization:      *******', 'Esc to cancel']) {
    assert.ok(text.includes(kept), `${kept} stays`);
  }
});

test('the usage screen loses its cost, token counts, meter and reset time', () => {
  const { text } = driver.maskCells(toCells(fixture('usage-screen.txt')), MASKS, []);
  for (const hidden of ['$1.2345', '120 input', '42% used', '███', 'Jan 7']) assert.ok(!text.includes(hidden), `${hidden} is masked`);
  for (const kept of ['Total cost:', 'Current week (all models)', 'Total duration (wall): 14s']) assert.ok(text.includes(kept), `${kept} stays`);
});

test('the startup banner keeps the model and loses the plan tier', () => {
  for (const name of ['status-screen.txt', 'usage-screen.txt']) {
    const [banner] = driver.maskCells(toCells(fixture(name)), MASKS, []).text.split('\n');
    assert.ok(banner.includes('Opus 5.5 · '), `${name} keeps the model`);
    assert.ok(!banner.includes('Max'), `${name} loses the tier`);
  }
});

test('the banner loses any plan name after "· Claude", through its segment end, and keeps every other row', () => {
  const mask = (row) => driver.maskCells(toCells(row), MASKS, []).text;
  assert.equal(mask('Sonnet 5.5 · Claude Max'), 'Sonnet 5.5 · **********');
  assert.equal(mask('Haiku 5.5 ·  Claude Pro   '), 'Haiku 5.5 ·  *************');
  assert.equal(mask('│ Opus 5.5 · Claude Ultra │ Tips │'), '│ Opus 5.5 · *************│ Tips │');
  for (const kept of ['Opus 5.5 · API Usage Billing', 'Default (Opus 5.5 · Best for everyday, complex tasks)', 'keep using Claude Code']) {
    assert.equal(mask(kept), kept);
  }
});

test('the key-auth status screen has no account to hide and still loses its session id and cwd', () => {
  const { text } = driver.maskCells(toCells(fixture('status-key-auth-screen.txt')), MASKS, []);
  for (const absent of ['@', 'Email:', 'Organization:', 'Login method:', '00000000-0000', '/home/<user>/project']) {
    assert.ok(!text.includes(absent), `${absent} is not on the masked screen`);
  }
  for (const kept of [
    `Session ID:                 ${'*'.repeat(36)}`,
    `cwd:                        ${'*'.repeat(20)}`,
    'Auth token:                 none',
    'API key:                    ANTHROPIC_API_KEY',
    'Opus 5.5 · API Usage Billing',
  ]) {
    assert.ok(text.includes(kept), `${kept} stays`);
  }
});

test('a value wrapped across rows and split by a border is masked to each segment end; the next segment is not', () => {
  const { text } = driver.maskCells(toCells('│ team: Example\n│ Org │ ok'), MASKS, ['Example Org']);
  assert.equal(text, '│ team: *******\n│ ****│ ok');
});

test('a home path outside the cwd line is masked through the row end', () => {
  const { text } = driver.maskCells(toCells('see /home/<user>/x here'), MASKS, []);
  assert.equal(text, `see ${'*'.repeat(19)}`);
});

test('a masked cell loses its colors and attributes, so a colored meter shows no level', () => {
  const cells = toCells('42% used').map((c) => ({ ...c, bg: '#ff0000', inverse: true }));
  const { rows } = driver.maskCells(cells, MASKS, []);
  assert.deepEqual(
    rows[0].map((c) => [c.char, c.bg, c.inverse]),
    Array(8).fill(['*', 'default', false]),
  );
});

test('a masked frame redraws with its colors and attributes and without its links', () => {
  const [cell] = toCells('a');
  const draw = driver.renderFrame([[{ ...cell, fg: '#d77757', bg: 1, bold: true, link: 'mailto:user@example.com' }]]);
  assert.ok(draw.includes('\x1b[1;1H\x1b[0;1;38;2;215;119;87;48;5;1ma'), JSON.stringify(draw));
  assert.ok(!draw.includes('example.com'));
});

// An engine whose live terminal shows `screen`, and whose second terminal (the mirror) keeps what it
// is sent in `<box>/drawn`, shows the rows of the last frame as its text, and "renders" that text.
const MIRROR_ENGINE = (screen, box, { stuck = false } = {}) => `import { appendFileSync, writeFileSync } from 'node:fs';
const cells = ${JSON.stringify(toCells(screen))};
const rows = (frame) => frame.replace(/\\x1b\\[[0-9;?]*[mJl]/g, '').split(/\\x1b\\[\\d+;1H/).slice(1).join('\\n');
export const TuiTest = { ephemeral: (prefix) => {
  if (!prefix.endsWith('mirror')) return {
    run: async () => {}, state: async () => ({ exited: null, exit_signal: null }),
    getSize: async () => ({ cols: 120, rows: ${screen.split('\n').length} }), cells: async () => cells,
    close: async () => {}, closeQuiet: async () => {},
  };
  let shown = 'ccd-mirror-ready';
  return {
    run: async () => {}, getByText: () => ({ first: () => ({ wait: async () => {} }) }),
    write: async (d) => { appendFileSync(${JSON.stringify(join(box.root, 'drawn'))}, d); if (!${stuck}) shown = rows(d); },
    text: async () => shown,
    screenshot: async (p) => writeFileSync(p, shown),
    startRecording: async (p) => writeFileSync(p, shown), stopRecording: async () => 'stopped',
    closeQuiet: async () => {},
  };
} };
`;

/** A sandbox with a stub claude whose `auth status --json` names the invented account. */
function maskBox(screen, opts) {
  const box = sandbox();
  placeEngine(box.target, MIRROR_ENGINE(screen, box, opts), { marked: true });
  const status = JSON.stringify({ loggedIn: true, email: 'user@example.com', orgName: 'Example Org' });
  writeFileSync(join(box.bin, 'claude'), `#!/bin/sh\nprintf '%s\\n' '${status}'\n`, { mode: 0o755 });
  return box;
}

test('screenshot hands the renderer the masked screen and writes a sidecar without the account', posixOnly, async () => {
  const box = maskBox(fixture('status-screen.txt'));
  const name = session();
  const png = join(box.root, 'status-01.png');
  try {
    await withPath(box.bin, async () => {
      await main(['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '60']);
      assert.equal(await quietly(() => main(['screenshot', png, '--session', name])).then((r) => r.result), 0);
    });
    const drawn = readFileSync(join(box.root, 'drawn'), 'utf8');
    const sidecar = readFileSync(`${png}.txt`, 'utf8');
    for (const [what, text] of [['renderer input', drawn], ['sidecar', sidecar], ['capture', readFileSync(png, 'utf8')]]) {
      assert.ok(!text.includes('user@example.com'), `${what} lacks the email`);
      assert.ok(!text.includes('Example Org'), `${what} lacks the organization`);
      assert.ok(text.includes('Version:'), `${what} still shows the screen`);
    }
  } finally {
    await main(['stop', '--session', name]).catch(() => {});
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a recording draws only masked frames and its sidecar holds their text', posixOnly, async () => {
  const box = maskBox(fixture('status-screen.txt'));
  const name = session();
  const mp4 = join(box.root, 'status-01.mp4');
  try {
    await withPath(box.bin, async () => {
      await main(['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '60']);
      await quietly(() => main(['record', 'start', mp4, '--session', name]));
      assert.equal((await quietly(() => main(['record', 'stop', '--session', name]))).text, 'recording stopped');
    });
    const sidecar = readFileSync(`${mp4}.txt`, 'utf8');
    assert.ok(sidecar.includes('Email:             ****************'), sidecar);
    assert.ok(!readFileSync(join(box.root, 'drawn'), 'utf8').includes('user@example.com'));
  } finally {
    await main(['stop', '--session', name]).catch(() => {});
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a masked frame that never redraws fails the screenshot with no capture and no sidecar', posixOnly, async () => {
  const box = maskBox(fixture('status-screen.txt'), { stuck: true });
  const name = session();
  const png = join(box.root, 'status-01.png');
  try {
    await withPath(box.bin, async () => {
      await main(['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '60']);
      await assert.rejects(main(['screenshot', png, '--session', name]), { code: 1, message: 'the masked frame did not redraw; nothing captured' });
    });
    assert.equal(existsSync(png), false);
    assert.equal(existsSync(`${png}.txt`), false);
  } finally {
    await main(['stop', '--session', name]).catch(() => {});
    rmSync(box.root, { recursive: true, force: true });
  }
});

// ---- changed plugins ----

test('plugins names each changed plugin once, in order, and nothing for a file outside a plugin', () => {
  const root = mkdtempSync(join(tmpdir(), 'ccd-repo-'));
  try {
    for (const name of ['alpha', 'beta']) {
      mkdirSync(join(root, 'plugins', name, '.claude-plugin'), { recursive: true });
      writeFileSync(join(root, 'plugins', name, '.claude-plugin', 'plugin.json'), '{}');
    }
    const files = ['plugins/beta/hooks/x.sh', 'docs/readme.md', 'plugins/alpha/skills/a/SKILL.md', 'plugins/beta/README.md'];
    assert.deepEqual(driver.changedPlugins(files, root), ['plugins/beta', 'plugins/alpha']);
    assert.deepEqual(driver.changedPlugins(['docs/readme.md'], root), []);
    assert.throws(() => driver.changedPlugins(['../outside/x'], root), { code: 2 });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('plugins lists at most maxEntryPoints plugins and names the rest blocked', async () => {
  const root = mkdtempSync(join(tmpdir(), 'ccd-repo-'));
  const cwd = process.cwd();
  const errors = [];
  const error = console.error;
  try {
    const names = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'];
    for (const name of names) {
      mkdirSync(join(root, 'plugins', name, '.claude-plugin'), { recursive: true });
      writeFileSync(join(root, 'plugins', name, '.claude-plugin', 'plugin.json'), '{}');
    }
    process.chdir(root);
    console.error = (s) => errors.push(s);
    const { result, text } = await quietly(() => main(['plugins', ...names.map((n) => `plugins/${n}/x.md`)]));
    assert.equal(result, 0);
    assert.deepEqual(text.split('\n'), ['plugins/p1', 'plugins/p2', 'plugins/p3', 'plugins/p4', 'plugins/p5', 'plugins/p6']);
    assert.deepEqual(errors, ['blocked: maxEntryPoints reached: plugins/p7']);
  } finally {
    console.error = error;
    process.chdir(cwd);
    rmSync(root, { recursive: true, force: true });
  }
});

test('plugins with no changed file names the configured plugin dir', async () => {
  const defaults = JSON.parse(readFileSync(join(HERE, '..', 'config', 'defaults.json'), 'utf8'));
  const { result, text } = await quietly(() => main(['plugins']));
  assert.equal(result, 0);
  assert.equal(text, defaults.pluginDir);
});

// ---- the runtime directory variable and broker mode ----

/** Sets each variable (undefined unsets it) for the run of `fn`, then puts back what was there. */
async function withEnv(vars, fn) {
  const saved = Object.fromEntries(Object.keys(vars).map((name) => [name, process.env[name]]));
  const put = (values) => {
    for (const [name, value] of Object.entries(values)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  };
  put(vars);
  try {
    return await fn();
  } finally {
    put(saved);
  }
}

test('CCD_RUNTIME_DIR comes ahead of XDG_RUNTIME_DIR for session sockets, created private', posixOnly, async () => {
  const ccd = mkdtempSync(join(tmpdir(), 'ccd-own-'));
  try {
    await withEnv({ CCD_RUNTIME_DIR: ccd, CCD_BROKER_SOCK: undefined }, () =>
      assert.rejects(main(['stop', '--session', session()]), { code: 3 }),
    );
    assert.equal(statSync(join(ccd, 'ccd')).mode & 0o777, 0o700);
  } finally {
    rmSync(ccd, { recursive: true, force: true });
  }
});

test('a socket path too long under CCD_RUNTIME_DIR names CCD_RUNTIME_DIR as the variable to shorten', posixOnly, async () => {
  const root = mkdtempSync(join(tmpdir(), 'ccd-long-'));
  try {
    const ccd = join(root, 'x'.repeat(120));
    await withEnv({ CCD_RUNTIME_DIR: ccd, CCD_BROKER_SOCK: undefined }, () =>
      assert.throws(() => driver.endpoint('s', 'linux'), /; set CCD_RUNTIME_DIR to a short private directory$/),
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a brokered request carries the options as typed, paths made absolute against the cwd, and the prompt after --', posixOnly, async () => {
  const { tokens, positionals } = (await import('node:util')).parseArgs({
    args: ['log', 'run /demo', '--plugin-dir', 'plugins/demo', '--out=run.jsonl', '--timeout', '9', '--unattended'],
    options: { 'plugin-dir': { type: 'string' }, out: { type: 'string' }, timeout: { type: 'string' }, unattended: { type: 'boolean' } },
    allowPositionals: true,
    tokens: true,
  });
  assert.deepEqual(driver.brokerRequest('log', tokens, positionals.slice(1), '/work'), {
    verb: 'log',
    args: ['--plugin-dir', '/work/plugins/demo', '--out', '/work/run.jsonl', '--timeout', '9', '--unattended', '--', 'run /demo'],
  });
});

/** A one-connection server at a fresh socket that records the request line and answers with `lines`. */
async function fakeBroker(lines, { end = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'ccd-fb-'));
  const sock = join(dir, 'b.sock');
  const seen = [];
  const server = (await import('node:net')).default.createServer((conn) => {
    conn.once('data', (d) => {
      seen.push(String(d));
      for (const line of lines) conn.write(`${line}\n`);
      if (end) conn.end();
    });
  });
  await new Promise((r) => server.listen(sock, r));
  return { sock, seen, close: () => (server.close(), rmSync(dir, { recursive: true, force: true })) };
}

const sink = () => {
  const chunks = [];
  return { chunks, write: (s) => chunks.push(s) };
};

test('broker mode relays stdout and stderr chunks, each line prefixed, and resolves with the exit status', posixOnly, async () => {
  const fb = await fakeBroker([JSON.stringify({ stdout: 'a\n' }), JSON.stringify({ stderr: 'b\n' }), JSON.stringify({ stdout: 'c\n' }), JSON.stringify({ exit: 4 })]);
  try {
    const out = sink();
    const err = sink();
    assert.equal(await driver.viaBroker(fb.sock, { verb: 'ready', args: [] }, { stdout: out, stderr: err }), 4);
    assert.deepEqual(out.chunks, ['broker| a\n', 'broker| c\n']);
    assert.deepEqual(err.chunks, ['broker| b\n']);
    assert.deepEqual(fb.seen, [`${JSON.stringify({ verb: 'ready', args: [] })}\n`]);
  } finally {
    fb.close();
  }
});

test('broker replies are untrusted: a malformed line, an out-of-range exit or no exit at all fails the verb', posixOnly, async () => {
  const cases = [
    [['not json'], /not a stream chunk or an exit/],
    [[JSON.stringify({ stdout: 42 })], /not a stream chunk or an exit/],
    [[JSON.stringify({ exit: 256 })], /not a stream chunk or an exit/],
    [[JSON.stringify({ exit: -1 })], /not a stream chunk or an exit/],
    [[JSON.stringify({ exit: 1.5 })], /not a stream chunk or an exit/],
    [[JSON.stringify({ stdout: 'partial' })], /closed the connection without an exit status/],
  ];
  for (const [lines, pattern] of cases) {
    const fb = await fakeBroker(lines);
    try {
      await assert.rejects(driver.viaBroker(fb.sock, { verb: 'ready', args: [] }, { stdout: sink(), stderr: sink() }), pattern, lines[0]);
    } finally {
      fb.close();
    }
  }
});

test('with CCD_BROKER_SOCK set, launch, ready and log go to the broker; socket verbs, doctor and plugins do not', posixOnly, async () => {
  const fb = await fakeBroker([JSON.stringify({ exit: 0 })]);
  const missing = join(fb.sock, '..', 'none.sock');
  try {
    await withEnv({ CCD_BROKER_SOCK: missing }, async () => {
      await assert.rejects(main(['ready', '--plugin-dir', 'p', '--out', 'o']), /the launch broker at .*none\.sock did not answer \(ENOENT\)/);
      await assert.rejects(main(['stop', '--session', session()]), { code: 3, message: /no session/ });
      assert.equal((await quietly(() => main(['plugins']))).result, 0);
    });
    await withEnv({ CCD_BROKER_SOCK: fb.sock }, () => main(['launch', '--plugin-dir', '/p', '--session', 'brk']));
    assert.deepEqual(JSON.parse(fb.seen[0]), { verb: 'launch', args: ['--plugin-dir', '/p', '--session', 'brk'] });
  } finally {
    fb.close();
  }
});

test('without CCD_BROKER_SOCK, log runs claude here and prints exactly its one line', posixOnly, async () => {
  // A broker listening at a known path is never contacted when the variable is unset.
  const fb = await fakeBroker([JSON.stringify({ exit: 9 })]);
  const box = sandbox();
  stubClaude(box, 'none', `printf '%s\\n' '{"type":"result"}'\nexit 0`);
  const out = join(box.root, 'run.jsonl');
  try {
    const { result, text } = await withEnv({ CCD_BROKER_SOCK: undefined }, () =>
      withPath(box.bin, () => quietly(() => main(['log', 'run /demo', '--plugin-dir', pluginDir(box), '--out', out]))),
    );
    assert.equal(result, 0);
    assert.equal(text, `log: ${out} (claude exit 0, apiKeySource none)`);
    assert.equal(readFileSync(join(box.root, 'key'), 'utf8'), 'unset');
    assert.deepEqual(fb.seen, []);
  } finally {
    fb.close();
    rmSync(box.root, { recursive: true, force: true });
  }
});

// ---- hardening: relayed text, the broker socket, deadlines, capture paths, --out ----

import netForHolders from 'node:net';
import { symlinkSync } from 'node:fs';

test('relayed text loses ESC sequences and control characters, keeps \\n and \\t, and every line starts with broker| ', () => {
  const out = sink();
  const write = driver.relayLines(out);
  write('x\x1b[31mred\x1b[0m\x1b]0;title\x07\x9b\ty');
  write('\x07z\r\nw');
  write('');
  assert.deepEqual(out.chunks, ['broker| xred\ty', 'z\nbroker| w']);
});

test('relayed text loses U+2028 and U+2029, so no unprefixed line can start inside a chunk', () => {
  const out = sink();
  driver.relayLines(out)('ok verdict: PASS done');
  assert.deepEqual(out.chunks, ['broker| okverdict: PASSdone']);
});

test('a broker socket that is relative, not a socket, or in a directory others can open is refused before connecting', posixOnly, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'ccd-bs-'));
  const file = join(dir, 'plain');
  writeFileSync(file, '');
  const open = join(dir, 'open');
  mkdirSync(open);
  chmodSync(open, 0o777);
  try {
    const ready = () => main(['ready', '--plugin-dir', 'p', '--out', 'o']);
    await withEnv({ CCD_BROKER_SOCK: 'rel.sock' }, () => assert.rejects(ready(), { code: 2, message: 'CCD_BROKER_SOCK must be an absolute path' }));
    await withEnv({ CCD_BROKER_SOCK: file }, () => assert.rejects(ready(), { code: 5, message: `${file} is not a socket owned by you; drive nothing` }));
    await withEnv({ CCD_BROKER_SOCK: join(open, 'b.sock') }, () => assert.rejects(ready(), { code: 5, message: /is not a private directory owned by you/ }));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a broker that sends no exit status fails the verb at its deadline', posixOnly, async () => {
  const fb = await fakeBroker([JSON.stringify({ stdout: 'working\n' })], { end: false });
  try {
    const started = Date.now();
    await assert.rejects(driver.viaBroker(fb.sock, { verb: 'log', args: [] }, { stdout: sink(), stderr: sink(), timeoutMs: 200 }), /sent no exit status within 200 ms/);
    assert.ok(Date.now() - started < 10_000);
  } finally {
    fb.close();
  }
});

test('a brokered verb waits its own timeout plus a 120 s grace: ready 120 s, log 600 s, launch 630 s by default', () => {
  assert.equal(driver.brokerDeadline('ready', { timeout: '1000' }), 121_000);
  assert.equal(driver.brokerDeadline('ready', {}), 240_000);
  assert.equal(driver.brokerDeadline('log', {}), 720_000);
  assert.equal(driver.brokerDeadline('log', { timeout: 'soon' }), 720_000);
  assert.equal(driver.brokerDeadline('launch', {}), 750_000);
});

/** A holder stand-in at session `name`'s socket: `reply(line, conn)` answers each request. */
async function fakeHolder(name, reply) {
  mkdirSync(join(RUNTIME, 'ccd'), { recursive: true, mode: 0o700 });
  const sock = join(RUNTIME, 'ccd', `${name}.sock`);
  const server = netForHolders.createServer((conn) => conn.once('data', (d) => reply(String(d), conn)));
  await new Promise((r) => server.listen(sock, r));
  return () => (server.close(), rmSync(sock, { force: true }));
}

test('a session holder that does not reply in time, or replies past 1 MiB, fails the verb', posixOnly, async () => {
  const silent = session();
  const closeSilent = await fakeHolder(silent, () => {});
  const flood = session();
  const closeFlood = await fakeHolder(flood, (_line, conn) => conn.write('x'.repeat((1 << 20) + 1)));
  try {
    await assert.rejects(driver.request(silent, 'ping', {}, 200), /the session holder did not reply within 200 ms/);
    await assert.rejects(driver.request(flood, 'ping', {}, 10_000), /the session holder sent a reply over 1 MiB/);
  } finally {
    closeSilent();
    closeFlood();
  }
});

test('screenshot and record start use only the path they asked for: any other answer fails the verb', posixOnly, async () => {
  const name = session();
  let answer;
  const close = await fakeHolder(name, (_line, conn) => conn.end(`${JSON.stringify({ ok: true, result: answer })}\n`));
  const want = join(process.cwd(), 'shot.png');
  try {
    answer = '/elsewhere/shot.png';
    await assert.rejects(main(['screenshot', 'shot.png', '--session', name]), /other than the requested capture path/);
    answer = `recording: /elsewhere/shot.mp4`;
    await assert.rejects(main(['record', 'start', 'shot.mp4', '--session', name]), /other than the requested capture path/);
    answer = want;
    assert.equal((await quietly(() => main(['screenshot', 'shot.png', '--session', name]))).text, want);
    answer = `recording: ${join(process.cwd(), 'shot.mp4')}`;
    assert.equal((await quietly(() => main(['record', 'start', 'shot.mp4', '--session', name]))).text, answer);
  } finally {
    close();
  }
});

test('record stop prints only the fixed stop reply: a holder naming a path fails the verb', posixOnly, async () => {
  const name = session();
  let answer;
  const close = await fakeHolder(name, (_line, conn) => conn.end(`${JSON.stringify({ ok: true, result: answer })}\n`));
  try {
    answer = '/elsewhere/x.mp4';
    await assert.rejects(main(['record', 'stop', '--session', name]), /other than "recording stopped"; use nothing it wrote/);
    answer = 'recording stopped';
    assert.equal((await quietly(() => main(['record', 'stop', '--session', name]))).text, 'recording stopped');
  } finally {
    close();
  }
});

// Node's setTimeout takes at most 2^31-1 ms and fires a longer delay after 1 ms.
test('a deadline past the setTimeout maximum waits instead of firing at once', posixOnly, async () => {
  assert.equal(driver.brokerDeadline('ready', { timeout: '9999999999' }), 2 ** 31 - 1);
  assert.equal(driver.brokerDeadline('ready', { timeout: String(2 ** 31 - 1) }), 2 ** 31 - 1);
  const name = session();
  const close = await fakeHolder(name, (_line, conn) => setTimeout(() => conn.end(`${JSON.stringify({ ok: true, result: 'late' })}\n`), 300));
  try {
    assert.equal(await driver.request(name, 'wait-for', { timeout: 2 ** 32 }), 'late');
  } finally {
    close();
  }
});

test('log will not write its --out through a symlink', posixOnly, async () => {
  const box = sandbox();
  stubClaude(box, 'none', `printf '%s\\n' '{"type":"result"}'\nexit 0`);
  const target = join(box.root, 'target.jsonl');
  writeFileSync(target, 'kept\n');
  const link = join(box.root, 'run.jsonl');
  symlinkSync(target, link);
  try {
    await assert.rejects(
      withPath(box.bin, () => main(['log', 'run /demo', '--plugin-dir', pluginDir(box), '--out', link])),
      { message: `cannot open ${link} (ELOOP)` },
    );
    assert.equal(readFileSync(target, 'utf8'), 'kept\n');
  } finally {
    rmSync(box.root, { recursive: true, force: true });
  }
});

test('a relative CCD_RUNTIME_DIR and a session name starting with - are usage errors', posixOnly, async () => {
  await withEnv({ CCD_RUNTIME_DIR: 'relative/rt' }, () =>
    assert.rejects(main(['stop', '--session', session()]), { code: 2, message: 'CCD_RUNTIME_DIR must be an absolute path' }),
  );
  await assert.rejects(main(['stop', '--session=-x']), { code: 2, message: '--session takes 1-32 letters, digits, _ or -, not starting with -' });
});

// ---- cli/account.mjs: the driven session's account, read by its holder ----
// The stub outputs follow `claude auth status --json` from Claude Code 2.1.319: `authMethod` is
// `api_key` under ANTHROPIC_API_KEY (no email or orgName) and `claude.ai` for a subscription login.
// The caller's own `claude` always disagrees with the holder's, as the CI outer leg's does with the
// sibling sandbox's, so a value read in the caller's environment fails each case.

const ACCOUNT = join(HERE, '..', 'cli', 'account.mjs');
const KEY_AUTH = JSON.stringify({ loggedIn: true, authMethod: 'api_key', apiProvider: 'firstParty', apiKeySource: 'ANTHROPIC_API_KEY' });
const SIGNED_IN = JSON.stringify({ loggedIn: true, authMethod: 'claude.ai', email: 'user@example.com', orgName: 'Example Org' });
const STAYS_UP = `export const TuiTest = { ephemeral: () => ({
  run: async () => {}, state: async () => ({ exited: null, exit_signal: null }),
  close: async () => {}, closeQuiet: async () => {},
}) };
`;

/** A sandbox whose `claude auth status --json` prints `status`. */
function authBox(status) {
  const box = sandbox();
  writeFileSync(join(box.bin, 'claude'), `#!/bin/sh\nprintf '%s\\n' '${status}'\n`, { mode: 0o755 });
  return box;
}

/** Runs account.mjs under `runtime` with `bin` first on PATH; async, so an in-process holder can answer. */
const runAccount = (runtime, bin, args = []) =>
  new Promise((done) => {
    const env = { ...process.env, XDG_RUNTIME_DIR: runtime, PATH: `${bin}${delimiter}${process.env.PATH}` };
    const child = spawn(process.execPath, [ACCOUNT, ...args], { env });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (status) => done({ status, stdout, stderr }));
  });

/** Launches a session in a runtime directory of its own whose holder's claude prints `status`, then runs `fn`. */
async function withAccountSession(status, { key } = {}, fn) {
  const runtime = mkdtempSync(join(tmpdir(), 'ccd-acct-'));
  const box = authBox(status);
  placeEngine(box.target, STAYS_UP, { marked: true });
  const caller = authBox(status === KEY_AUTH ? SIGNED_IN : KEY_AUTH);
  const name = session();
  const inRuntime = (f) => withEnv({ XDG_RUNTIME_DIR: runtime, ANTHROPIC_API_KEY: key }, f);
  try {
    const launch = ['launch', '--plugin-dir', '/p', '--deps-dir', box.deps, '--session', name, '--ttl', '60'];
    await inRuntime(() => withPath(box.bin, () => quietly(() => main(key ? [...launch, '--unattended'] : launch))));
    return await fn({ runtime, name, callerBin: caller.bin });
  } finally {
    await inRuntime(() => main(['stop', '--session', name]).catch(() => {}));
    for (const dir of [box.root, caller.root, runtime]) rmSync(dir, { recursive: true, force: true });
  }
}

test('account prints the none: line for a session on its kept ANTHROPIC_API_KEY, whatever the caller is signed in as', posixOnly, () =>
  withAccountSession(KEY_AUTH, { key: 'fake-ci' }, async ({ runtime, callerBin }) => {
    const run = await runAccount(runtime, callerBin);
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, 'none: API-key auth has no signed-in account\n');
  }));

test('account prints the email and organization of a signed-in session, not the caller key auth', posixOnly, () =>
  withAccountSession(SIGNED_IN, {}, async ({ runtime, name, callerBin }) => {
    for (const args of [[], ['--session', name]]) {
      const run = await runAccount(runtime, callerBin, args);
      assert.equal(run.status, 0, run.stderr);
      assert.equal(run.stdout, 'user@example.com\nExample Org\n', `account ${args.join(' ')}`);
    }
  }));

test('account prints the organization of a session on key auth that names one', posixOnly, () =>
  withAccountSession(JSON.stringify({ ...JSON.parse(KEY_AUTH), orgName: 'Example Org' }), { key: 'fake-ci' }, async ({ runtime, callerBin }) => {
    const run = await runAccount(runtime, callerBin);
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, 'Example Org\n');
  }));

test('account exits 1 with nothing on stdout for key auth the launch did not keep', posixOnly, () =>
  // An attended launch clears ANTHROPIC_API_KEY, so a key reported anyway came from somewhere the driver cannot see.
  withAccountSession(KEY_AUTH, {}, async ({ runtime, callerBin }) => {
    const run = await runAccount(runtime, callerBin);
    assert.equal(run.status, 1);
    assert.equal(run.stdout, '');
    assert.equal(run.stderr, 'account: claude auth status names no email or organization\n');
  }));

test('account exits 1 with nothing on stdout for a session with no login, or a subscription login naming no account', posixOnly, async () => {
  for (const status of [{ loggedIn: false, authMethod: 'none', apiProvider: 'firstParty' }, { loggedIn: true, authMethod: 'claude.ai' }]) {
    await withAccountSession(JSON.stringify(status), { key: 'fake-ci' }, async ({ runtime, callerBin }) => {
      const run = await runAccount(runtime, callerBin);
      assert.equal(run.status, 1);
      assert.equal(run.stdout, '');
    });
  }
});

test('account exits 1 with nothing on stdout when the session holder cannot read its auth status', posixOnly, () =>
  withAccountSession('not json', { key: 'fake-ci' }, async ({ runtime, callerBin }) => {
    const run = await runAccount(runtime, callerBin);
    assert.equal(run.status, 1);
    assert.equal(run.stdout, '');
    assert.equal(run.stderr, 'account: claude auth status printed no JSON; cannot read the signed-in account to mask it\n');
  }));

test('account exits 1 with nothing on stdout when no session runs or the named one is missing', posixOnly, async () => {
  const runtime = mkdtempSync(join(tmpdir(), 'ccd-acct-'));
  const caller = authBox(SIGNED_IN);
  try {
    let run = await runAccount(runtime, caller.bin);
    assert.deepEqual(run, { status: 1, stdout: '', stderr: 'account: no session is running; launch one first\n' });
    run = await runAccount(runtime, caller.bin, ['--session', 'gone']);
    assert.deepEqual(run, { status: 1, stdout: '', stderr: "account: no session 'gone' is running; run launch first\n" });
  } finally {
    rmSync(caller.root, { recursive: true, force: true });
    rmSync(runtime, { recursive: true, force: true });
  }
});

/** A holder stand-in under `runtime` that answers ping with pong and account with `lines`. */
async function accountHolder(runtime, name, lines) {
  mkdirSync(join(runtime, 'ccd'), { recursive: true, mode: 0o700 });
  const sock = join(runtime, 'ccd', `${name}.sock`);
  const server = netForHolders.createServer((conn) =>
    conn.once('data', (d) => conn.end(`${JSON.stringify({ ok: true, result: JSON.parse(d).verb === 'ping' ? 'pong' : lines })}\n`)),
  );
  await new Promise((r) => server.listen(sock, r));
  return () => server.close();
}

test('account exits 1 with nothing on stdout when two sessions run, or a holder answers anything but account lines', posixOnly, async () => {
  const runtime = mkdtempSync(join(tmpdir(), 'ccd-acct-'));
  const caller = authBox(SIGNED_IN);
  const closers = [];
  try {
    closers.push(await accountHolder(runtime, 'one', ['user@example.com']), await accountHolder(runtime, 'two', ['user@example.com']));
    let run = await runAccount(runtime, caller.bin);
    assert.deepEqual(run, { status: 1, stdout: '', stderr: 'account: 2 sessions are running (one, two); pass --session <name>\n' });
    run = await runAccount(runtime, caller.bin, ['--session', 'one']);
    assert.deepEqual(run, { status: 0, stdout: 'user@example.com\n', stderr: '' });
    const forged = [
      ['none: API-key auth has no signed-in account', 'user@example.com'],
      ['none: nothing to see'],
      [],
      ['user@example.com\nnone: API-key auth has no signed-in account'],
      'none: API-key auth has no signed-in account',
    ];
    for (const [i, lines] of forged.entries()) {
      closers.push(await accountHolder(runtime, `forged${i}`, lines));
      run = await runAccount(runtime, caller.bin, ['--session', `forged${i}`]);
      assert.equal(run.status, 1, JSON.stringify(lines));
      assert.equal(run.stdout, '', JSON.stringify(lines));
    }
  } finally {
    for (const close of closers) close();
    rmSync(caller.root, { recursive: true, force: true });
    rmSync(runtime, { recursive: true, force: true });
  }
});
