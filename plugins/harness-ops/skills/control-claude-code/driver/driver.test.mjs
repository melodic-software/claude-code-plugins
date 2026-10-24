// Runs with no node_modules: driver.mjs loads the terminal engine only inside
// the session holder, and every engine below is a stub. Expected values come
// from the plan's launch contract (three flags, the auth variables unset, no
// --bare, persistence forced), the Claude Code Environment variables and LLM
// gateway pages, Node's setTimeout ceiling (2^31-1 ms), and the shared
// prerequisites checker's probe rule (the pattern is a regular expression run
// over the probe's output).
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
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
    message: 'verbs: launch, wait-for, type, screenshot, record, stop, doctor',
  });
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
