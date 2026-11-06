// Runs with no node_modules: claude and the terminal engine are stubs. Expected
// values come from the broker contract: the verbs launch, ready and log only; a
// session name matching ^[\w-]{1,32}$; --plugin-dir and --out under the roots the
// broker starts with; the driver it starts with run by absolute path with
// --unattended; a key read at start handed only to the driver child; replies
// streamed as {stdout}, {stderr} and a final {exit}.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import net from 'node:net';
import { tmpdir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { childEnv, driverArgs, Refused, startConfig, VERBS } from './broker.mjs';
import { installDir as installDirOf } from './driver.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const DRIVER = join(HERE, 'driver.mjs');
const BROKER = join(HERE, 'broker.mjs');
const posixOnly = { skip: process.platform === 'win32' && 'the broker serves a Unix socket; the stubs are POSIX scripts' };

const boxes = [];
const children = [];
after(() => {
  for (const child of children) child.kill('SIGKILL');
  for (const dir of boxes) rmSync(dir, { recursive: true, force: true });
});

/** A private tree: a root holding a plugin, an outside dir, a bin for stubs, a deps dir and a runtime dir. */
function box() {
  const top = realpathSync(mkdtempSync(join(tmpdir(), 'ccd-broker-')));
  boxes.push(top);
  const dirs = { top, root: join(top, 'root'), outside: join(top, 'outside'), bin: join(top, 'bin'), deps: join(top, 'deps'), rt: join(top, 'rt') };
  for (const name of ['root', 'outside', 'bin', 'deps', 'rt']) mkdirSync(dirs[name], { mode: 0o700 });
  dirs.plugin = join(dirs.root, 'plugin');
  mkdirSync(join(dirs.plugin, '.claude-plugin'), { recursive: true });
  writeFileSync(join(dirs.plugin, '.claude-plugin', 'plugin.json'), JSON.stringify({ name: 'demo' }));
  return dirs;
}

const refuses = (request, pattern, b = box()) =>
  assert.throws(
    () => driverArgs(request, [b.root]),
    (err) => err instanceof Refused && pattern.test(err.message),
  );

// ---- the verb table ----

test('the broker runs exactly launch, ready and log', () => {
  assert.deepEqual(Object.keys(VERBS).sort(), ['launch', 'log', 'ready']);
});

test('a verb outside the table is refused, inherited names and socket verbs included', () => {
  for (const verb of ['stop', 'serve', 'type', 'screenshot', 'doctor', '__proto__', 'constructor', 'toString', 42]) {
    refuses({ verb, args: [] }, /the broker runs only launch, ready, log/);
  }
});

test('a request that is not an object of a verb and a list of strings is refused', () => {
  refuses(null, /one JSON object/);
  refuses('launch', /one JSON object/);
  refuses({ verb: 'launch', args: '--plugin-dir /x' }, /list of strings/);
  refuses({ verb: 'launch', args: [1] }, /list of strings/);
});

test('session names outside 1-32 letters, digits, _ or - are refused; the edges pass', () => {
  const b = box();
  const launch = (session) => driverArgs({ verb: 'launch', args: ['--plugin-dir', b.plugin, '--session', session] }, [b.root]);
  for (const bad of ['', 'a b', 'a/b', '../x', 'x'.repeat(33), 'naïve', 'a;b']) {
    assert.throws(() => launch(bad), /--session takes 1-32 letters, digits, _ or -/, JSON.stringify(bad));
  }
  assert.equal(launch('x'.repeat(32)).includes('x'.repeat(32)), true);
  assert.equal(launch('a_b-9').includes('a_b-9'), true);
});

test('a plugin dir that is relative, holds .., lies outside the roots or escapes them by symlink is refused', () => {
  const b = box();
  const escape = join(b.root, 'escape');
  symlinkSync(b.outside, escape);
  const launch = (dir) => ({ verb: 'launch', args: ['--plugin-dir', dir] });
  refuses(launch('root/plugin'), /absolute, normalized path/, b);
  refuses(launch(`${b.root}/plugin/../../outside`), /absolute, normalized path/, b);
  refuses(launch(b.outside), /inside an allowed root/, b);
  refuses(launch(escape), /inside an allowed root/, b);
  refuses(launch(join(b.root, 'missing')), /does not exist/, b);
});

test('an --out outside the roots, in a missing directory, or an existing symlink is refused', () => {
  const b = box();
  const link = join(b.root, 'link.jsonl');
  symlinkSync(join(b.outside, 'target.jsonl'), link);
  const ready = (out) => ({ verb: 'ready', args: ['--plugin-dir', b.plugin, '--out', out] });
  refuses(ready(join(b.outside, 'init.jsonl')), /--out must be inside an allowed root/, b);
  refuses(ready(join(b.root, 'nope', 'init.jsonl')), /--out's directory does not exist/, b);
  refuses(ready(link), /--out may not be a symbolic link/, b);
  refuses(ready('init.jsonl'), /absolute, normalized path/, b);
});

test('options the verb does not take are refused: a client --deps-dir, --key, --ttl on ready', () => {
  const b = box();
  refuses({ verb: 'launch', args: ['--plugin-dir', b.plugin, '--deps-dir', b.deps] }, /deps-dir/, b);
  refuses({ verb: 'launch', args: ['--plugin-dir', b.plugin, '--key', 'Enter'] }, /key/, b);
  refuses({ verb: 'ready', args: ['--plugin-dir', b.plugin, '--out', join(b.root, 'o'), '--ttl', '5'] }, /ttl/, b);
  refuses({ verb: 'launch', args: ['--plugin-dir', b.plugin, '--ttl', 'soon'] }, /--ttl takes a whole number/, b);
});

test('a verb without its required paths is refused', () => {
  const b = box();
  refuses({ verb: 'launch', args: [] }, /launch needs --plugin-dir/, b);
  refuses({ verb: 'ready', args: ['--plugin-dir', b.plugin] }, /ready needs --out/, b);
});

test('log takes exactly one prompt, and one that reads as a flag is refused', () => {
  const b = box();
  const log = (...prompts) => ({ verb: 'log', args: ['--plugin-dir', b.plugin, '--out', join(b.root, 'run.jsonl'), '--', ...prompts] });
  refuses(log(), /exactly one prompt/, b);
  refuses(log('a', 'b'), /exactly one prompt/, b);
  refuses(log('--unattended'), /may not start with -/, b);
  refuses(log(''), /non-empty/, b);
  refuses({ verb: 'ready', args: ['--plugin-dir', b.plugin, '--out', join(b.root, 'o'), 'extra'] }, /Unexpected argument|positional/i, b);
});

test('an accepted request becomes the driver arguments with --unattended, the broker deps dir and the prompt last', () => {
  const b = box();
  const out = join(b.root, 'run.jsonl');
  assert.deepEqual(driverArgs({ verb: 'launch', args: ['--plugin-dir', b.plugin, '--session', 's1', '--ttl', '60', '--unattended'] }, [b.root], b.deps), [
    'launch', '--plugin-dir', b.plugin, '--session', 's1', '--ttl', '60', '--unattended', '--deps-dir', b.deps,
  ]);
  assert.deepEqual(driverArgs({ verb: 'ready', args: ['--plugin-dir', b.plugin, '--out', out] }, [b.root], b.deps), [
    'ready', '--plugin-dir', b.plugin, '--out', out, '--unattended', '--deps-dir', b.deps,
  ]);
  assert.deepEqual(driverArgs({ verb: 'log', args: ['--plugin-dir', b.plugin, '--out', out, '--timeout', '9', '--', 'run /demo'] }, [b.root], b.deps), [
    'log', '--plugin-dir', b.plugin, '--out', out, '--timeout', '9', '--unattended', '--', 'run /demo',
  ]);
});

test('the driver child gets the start key and no other credential or broker socket', () => {
  const env = { PATH: '/bin', ANTHROPIC_API_KEY: 'from-env', CLAUDE_CODE_OAUTH_TOKEN: 'sub', CCD_BROKER_SOCK: '/s', CCD_RUNTIME_DIR: '/rt' };
  assert.deepEqual(childEnv(env, 'dummy'), { PATH: '/bin', CCD_RUNTIME_DIR: '/rt', ANTHROPIC_API_KEY: 'dummy' });
  assert.equal(env.ANTHROPIC_API_KEY, 'from-env', 'the broker environment is not changed');
});

test('the broker refuses to start on a driver inside a root, an empty key, or a socket directory others can open', posixOnly, () => {
  const b = box();
  const base = { socket: join(b.rt, 'broker.sock'), driver: DRIVER, root: [b.root] };
  assert.equal(startConfig(base, 'k').driver, realpathSync(DRIVER));
  const inRoot = join(b.root, 'driver.mjs');
  writeFileSync(inRoot, '');
  assert.throws(() => startConfig({ ...base, driver: inRoot }, 'k'), /--driver may not sit inside a --root/);
  assert.throws(() => startConfig(base, ''), /read from stdin, which was empty/);
  const open = join(b.top, 'open');
  mkdirSync(open);
  chmodSync(open, 0o777); // mkdir's mode is masked by the umask
  assert.throws(() => startConfig({ ...base, socket: join(open, 'broker.sock') }, 'k'), /not a private directory/);
});

// ---- over the socket, against a stub claude ----

const initLine = (source) =>
  JSON.stringify({ type: 'system', subtype: 'init', apiKeySource: source, claude_code_version: '9.9.9', plugins: [{ name: 'demo', path: '/p' }] });

/** A claude that records its argv, key and broker socket variable, prints the init event, then runs `rest`. */
function stubClaude(b, source, rest = 'exec sleep 30') {
  const script = [
    '#!/bin/sh',
    `printf '%s\\n' "$@" > "${b.top}/argv"`,
    `printf '%s' "\${ANTHROPIC_API_KEY-unset}" > "${b.top}/key"`,
    `printf '%s' "\${CCD_BROKER_SOCK-unset}" > "${b.top}/sock"`,
    `printf '%s\\n' '${initLine(source)}'`,
    rest,
  ].join('\n');
  writeFileSync(join(b.bin, 'claude'), `${script}\n`, { mode: 0o755 });
}

const brokerEnv = (b) => ({
  ...process.env,
  PATH: `${b.bin}${delimiter}${process.env.PATH}`,
  CCD_RUNTIME_DIR: b.rt,
  ANTHROPIC_API_KEY: 'from-broker-env',
});

/** Starts the broker with `key` on stdin and resolves once it listens. */
function startBroker(b, key = 'dummy-from-stdin') {
  const sock = join(b.rt, 'broker.sock');
  const child = spawn(process.execPath, [BROKER, '--socket', sock, '--driver', DRIVER, '--root', b.root, '--deps-dir', b.deps], {
    env: brokerEnv(b),
    stdio: ['pipe', 'ignore', 'pipe'],
  });
  children.push(child);
  child.stdin.end(key);
  return new Promise((done, fail) => {
    let err = '';
    child.stderr.on('data', (d) => {
      err += d;
      if (err.includes('listening on')) done(sock);
    });
    child.on('exit', (code) => fail(new Error(`broker exited ${code}: ${err}`)));
  });
}

/** Runs the driver CLI as the outer session would, in `cwd`, with CCD_BROKER_SOCK set. */
function client(b, sock, args, cwd = b.root) {
  const env = { ...process.env, CCD_BROKER_SOCK: sock, CCD_RUNTIME_DIR: b.rt };
  delete env.ANTHROPIC_API_KEY;
  const child = spawn(process.execPath, [DRIVER, ...args], { cwd, env, stdio: ['ignore', 'pipe', 'pipe'] });
  children.push(child);
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (d) => (stdout += d));
  child.stderr.on('data', (d) => (stderr += d));
  return new Promise((done) => child.on('close', (code) => done({ code, stdout, stderr })));
}

/** Sends raw bytes to the broker and resolves with the reply lines. */
function raw(sock, bytes) {
  return new Promise((done, fail) => {
    const conn = net.createConnection(sock);
    let buf = '';
    conn.on('connect', () => conn.write(bytes));
    conn.on('data', (d) => (buf += d));
    conn.on('end', () => done(buf.trim().split('\n').map((l) => JSON.parse(l))));
    conn.on('error', fail);
  });
}

test('a brokered ready runs the driver there unattended with the start key, paths resolved against the client cwd', posixOnly, async () => {
  const b = box();
  stubClaude(b, 'ANTHROPIC_API_KEY');
  const sock = await startBroker(b);
  const got = await client(b, sock, ['ready', '--plugin-dir', 'plugin', '--out', 'init.jsonl', '--timeout', '20000']);
  assert.equal(got.code, 0, got.stdout + got.stderr);
  assert.match(got.stdout, /^apiKeySource: ANTHROPIC_API_KEY$/m);
  assert.match(got.stdout, /^plugins: demo$/m);
  assert.match(got.stdout, new RegExp(`^install base: ${b.deps} \\(--deps-dir\\)$`, 'm'));
  assert.equal(readFileSync(join(b.top, 'key'), 'utf8'), 'dummy-from-stdin', 'the key comes from stdin, not the broker env');
  assert.equal(readFileSync(join(b.top, 'sock'), 'utf8'), 'unset', 'the driver child is not in broker mode');
  assert.deepEqual(readFileSync(join(b.top, 'argv'), 'utf8').trim().split('\n').slice(2, 4), ['--plugin-dir', b.plugin]);
  assert.equal(readFileSync(join(b.root, 'init.jsonl'), 'utf8').trim(), initLine('ANTHROPIC_API_KEY'));
});

test('a brokered verb relays the driver exit: a key source other than the kept key exits 1', posixOnly, async () => {
  const b = box();
  stubClaude(b, 'none');
  const sock = await startBroker(b);
  const got = await client(b, sock, ['ready', '--plugin-dir', b.plugin, '--out', join(b.root, 'init.jsonl'), '--timeout', '20000']);
  assert.equal(got.code, 1);
  assert.match(got.stdout, /refused: apiKeySource is "none", not "ANTHROPIC_API_KEY"; drive nothing/);
});

test('a brokered log streams the driver output and exit', posixOnly, async () => {
  const b = box();
  stubClaude(b, 'ANTHROPIC_API_KEY', `printf '%s\\n' '{"type":"result"}'\nexit 0`);
  const sock = await startBroker(b);
  const out = join(b.root, 'run.jsonl');
  const got = await client(b, sock, ['log', 'run /demo', '--plugin-dir', b.plugin, '--out', out]);
  assert.equal(got.code, 0, got.stderr);
  assert.equal(got.stdout, `log: ${out} (claude exit 0, apiKeySource ANTHROPIC_API_KEY)\n`);
  assert.equal(readFileSync(join(b.top, 'argv'), 'utf8').trim().split('\n').at(-1), 'run /demo');
});

test('the broker refuses over the socket: a bad session, an unknown verb, malformed JSON, an oversize request', posixOnly, async () => {
  const b = box();
  stubClaude(b, 'ANTHROPIC_API_KEY');
  const sock = await startBroker(b);
  const bad = await client(b, sock, ['launch', '--plugin-dir', b.plugin, '--session', 'bad.name']);
  assert.equal(bad.code, 2);
  assert.match(bad.stderr, /launch broker: refused: --session takes 1-32 letters, digits, _ or -/);
  assert.deepEqual(await raw(sock, `${JSON.stringify({ verb: 'stop', args: [] })}\n`), [
    { stderr: 'launch broker: refused: the broker runs only launch, ready, log\n' },
    { exit: 2 },
  ]);
  assert.deepEqual(await raw(sock, 'not json\n'), [{ stderr: 'launch broker: refused: a request is one JSON object {verb, args}\n' }, { exit: 2 }]);
  const big = await raw(sock, 'x'.repeat(64 * 1024 + 1));
  assert.deepEqual(big.at(-1), { exit: 2 });
  assert.match(big[0].stderr, /a request is one line of at most 65536 bytes/);
  assert.throws(() => readFileSync(join(b.top, 'argv')), { code: 'ENOENT' }, 'no refused request ran claude');
});

test('a brokered launch starts the session there, and socket verbs reach its holder directly', posixOnly, async () => {
  const b = box();
  const seen = join(b.top, 'seen.json');
  const engine = join(installDirOf(b.deps), 'node_modules', '@microsoft', 'tui-test');
  mkdirSync(join(engine, 'dist'), { recursive: true, mode: 0o700 });
  writeFileSync(join(engine, 'package.json'), '{"type":"module"}');
  writeFileSync(
    join(engine, 'dist', 'index.js'),
    `import { writeFileSync } from 'node:fs';
export const TuiTest = { ephemeral: () => ({
  run: async (cmd, args, opts) => writeFileSync(${JSON.stringify(seen)}, JSON.stringify({ key: opts.env.ANTHROPIC_API_KEY ?? null, sock: opts.env.CCD_BROKER_SOCK ?? null })),
  state: async () => ({ exited: null, exit_signal: null }),
  type: async (text) => writeFileSync(${JSON.stringify(seen)} + '.typed', text),
  close: async () => {},
  closeQuiet: async () => {},
}) };
`,
  );
  writeFileSync(join(installDirOf(b.deps), '.signatures-verified'), 'stub\n');
  const sock = await startBroker(b);
  const name = `b${process.pid}`;
  try {
    const launched = await client(b, sock, ['launch', '--plugin-dir', b.plugin, '--session', name, '--ttl', '60']);
    assert.equal(launched.code, 0, launched.stderr);
    assert.match(launched.stdout, new RegExp(`^launched session '${name}'`));
    assert.deepEqual(JSON.parse(readFileSync(seen, 'utf8')), { key: 'dummy-from-stdin', sock: null });
    const typed = await client(b, sock, ['type', 'hello', '--session', name]);
    assert.equal(typed.code, 0, typed.stderr);
    assert.equal(readFileSync(`${seen}.typed`, 'utf8'), 'hello');
  } finally {
    const stopped = await client(b, sock, ['stop', '--session', name]);
    assert.equal(stopped.code, 0, stopped.stderr);
  }
});
