// Runs with no node_modules: driver.mjs loads the terminal engine only inside
// the session holder. Expected values come from the plan's launch contract
// (three flags, the auth variables unset, no --bare, persistence forced) and
// the Claude Code Environment variables page for the provider switches.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildLaunch, main } from './driver.mjs';

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
