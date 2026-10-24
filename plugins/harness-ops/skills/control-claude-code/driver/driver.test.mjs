// Runs with no node_modules: driver.mjs loads the terminal engine only inside
// the session holder. Expected values come from the plan's launch contract
// (three flags, the auth variables unset, no --bare, persistence forced) and
// the Claude Code Environment variables page for the provider switches.
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { test } from 'node:test';
import { buildLaunch, ensureInstalled, installDir, main } from './driver.mjs';

const CLEARED = [
  'ANTHROPIC_API_KEY',
  'ANTHROPIC_AUTH_TOKEN',
  'CLAUDE_CODE_USE_BEDROCK',
  'CLAUDE_CODE_USE_VERTEX',
  'CLAUDE_CODE_USE_FOUNDRY',
  'CLAUDE_CODE_USE_MANTLE',
  'CLAUDE_CODE_USE_ANTHROPIC_AWS',
];

test('launch runs claude restricted, MCP-strict, on the plugin dir, never bare', () => {
  const { argv } = buildLaunch({ pluginDir: '/repo/plugins/context-guard' }, {});
  assert.deepEqual(argv, ['claude', '--restricted', '--strict-mcp-config', '--plugin-dir', '/repo/plugins/context-guard']);
  assert.ok(!argv.includes('--bare'));
});

test('launch clears every auth and provider variable and keeps the rest', () => {
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
    message: '--ttl takes a whole number of seconds',
  });
});

test('an unknown verb is a usage error naming the verbs', async () => {
  await assert.rejects(main(['dance']), {
    code: 2,
    message: 'verbs: launch, wait-for, type, screenshot, record, stop, doctor',
  });
});

// A repaired install (engine present, no marker) passes the same readiness gate
// as a first install: the convention's load probe, failing closed with the repair
// line. npm is a stub on PATH so the case needs no network; POSIX only.
const posixOnly = { skip: process.platform === 'win32' && 'the npm stub is a POSIX script' };

function repairedInstall(engineSource) {
  const root = mkdtempSync(join(tmpdir(), 'ccd-test-'));
  const bin = join(root, 'bin');
  mkdirSync(bin);
  writeFileSync(join(bin, 'npm'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  const target = installDir(join(root, 'deps'));
  const engine = join(target, 'node_modules', '@microsoft', 'tui-test');
  mkdirSync(join(engine, 'dist'), { recursive: true });
  writeFileSync(join(engine, 'package.json'), '{}');
  writeFileSync(join(engine, 'dist', 'index.js'), engineSource);
  return { root, bin, target };
}

function withPath(bin, fn) {
  const saved = process.env.PATH;
  process.env.PATH = `${bin}${delimiter}${saved}`;
  try {
    return fn();
  } finally {
    process.env.PATH = saved;
  }
}

test('a repaired install whose engine does not load fails closed with the repair line, unmarked', posixOnly, () => {
  const { root, bin, target } = repairedInstall("throw new Error('engine refuses to load');\n");
  try {
    assert.throws(() => withPath(bin, () => ensureInstalled(join(root, 'deps'))), (err) => {
      assert.equal(err.code, 4);
      assert.match(err.message, /^the installed engine does not load \(.*\); repair: rm -rf /);
      return true;
    });
    assert.equal(existsSync(join(target, '.signatures-verified')), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a repaired install whose engine loads is marked verified and reused', posixOnly, () => {
  const loads = "export const TuiTest = { ephemeral: () => ({ closeQuiet: async () => {} }) };\n";
  const { root, bin, target } = repairedInstall(loads);
  try {
    assert.equal(withPath(bin, () => ensureInstalled(join(root, 'deps'))), target);
    assert.equal(existsSync(join(target, '.signatures-verified')), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
