// Runs with no node_modules: driver.mjs loads the terminal engine only inside
// the session holder, and every engine below is a stub. Expected values come
// from the plan's launch contract (three flags, the auth variables unset, no
// --bare, persistence forced), the Claude Code Environment variables and LLM
// gateway pages, Node's setTimeout ceiling (2^31-1 ms), and the shared
// prerequisites checker's probe rule (the pattern is a regular expression run
// over the probe's output).
import assert from 'node:assert/strict';
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
after(() => rmSync(RUNTIME, { recursive: true, force: true }));
let sessions = 0;
const session = () => `t${process.pid}-${++sessions}`;

test('launch runs claude restricted, MCP-strict, on the plugin dir, never bare', () => {
  const { argv } = buildLaunch({ pluginDir: '/repo/plugins/context-guard' }, {});
  assert.deepEqual(argv, ['claude', '--restricted', '--strict-mcp-config', '--plugin-dir', '/repo/plugins/context-guard']);
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

test('persistence is forced to 1 even when the parent set it to 0', () => {
  const { env } = buildLaunch({ pluginDir: '/p' }, { CLAUDE_CODE_FORCE_SESSION_PERSISTENCE: '0' });
  assert.equal(env.CLAUDE_CODE_FORCE_SESSION_PERSISTENCE, '1');
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

test('an unknown verb is a usage error naming the verbs', async () => {
  await assert.rejects(main(['dance']), {
    code: 2,
    message: 'verbs: launch, wait-for, type, screenshot, record, stop, doctor, ready, log',
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
  assert.deepEqual(defaults.credentials, {});
  assert.deepEqual(defaults.safety, { recipients: {}, signInAttempts: {}, production: {}, unattendedWrites: false });
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
