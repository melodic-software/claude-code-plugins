import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  createModEnablement,
  extractPluginOption,
  isNoRepositoryLayer,
  parseRepoBoolean,
  refreshModEnablement,
  resolveConventionHome,
  resolveInstallId,
  resolveModHookEnabled,
} from './mod-hook-enabled.ts'

function fakeEngine({
  pluginRoot = '/var/tmp/home/.claude/plugins/cache/melodic-software/demo/1.0.0',
  settings = {},
  files = {},
  stats = {},
  env = { HOME: '/var/tmp/home' },
  sessionRoot,
  unstubbed = [],
} = {}) {
  const logs = []
  const isUnstubbed = name => unstubbed.includes(name)
  const $ = {
    plugin: { name: 'demo', root: pluginRoot },
    settings: {
      read: async ({ source } = {}) => {
        if (isUnstubbed('settings.read')) throw new Error('no implementation for settings.read')
        return settings[source] ?? {}
      },
    },
    session: {
      root: async () => {
        if (isUnstubbed('session.root') || sessionRoot === undefined) {
          throw new Error('no implementation for session.root')
        }
        return sessionRoot
      },
    },
    env: {
      get: async name => {
        if (isUnstubbed('env.get')) throw new Error('no implementation for env.get')
        return env[name]
      },
    },
    fs: {
      stat: async path => {
        if (isUnstubbed('fs.stat')) throw new Error('no implementation for fs.stat')
        if (Object.hasOwn(stats, path)) return stats[path]
        if (Object.hasOwn(files, path)) return { kind: 'file', size: files[path].length, mtimeMs: 0, isLink: false }
        throw new Error(`ENOENT: ${path}`)
      },
      read: async path => {
        if (isUnstubbed('fs.read')) throw new Error('no implementation for fs.read')
        if (Object.hasOwn(files, path)) return files[path]
        throw new Error(`ENOENT: ${path}`)
      },
    },
    ui: {
      log: (text, opts) => {
        logs.push({ text, opts })
      },
    },
  }
  return { $, logs }
}

test('isNoRepositoryLayer skips empty, home, and ancestors of home', () => {
  assert.equal(isNoRepositoryLayer('', '/var/tmp/home'), true)
  assert.equal(isNoRepositoryLayer('/var/tmp/home', '/var/tmp/home'), true)
  assert.equal(isNoRepositoryLayer('/var/tmp/home/', '/var/tmp/home'), true)
  assert.equal(isNoRepositoryLayer('/var/tmp', '/var/tmp/home'), true)
  assert.equal(isNoRepositoryLayer('/', '/var/tmp/home'), true)
  assert.equal(isNoRepositoryLayer('/var/tmp/home/repo', '/var/tmp/home'), false)
  assert.equal(isNoRepositoryLayer('/var/tmp/home-two/repo', '/var/tmp/home'), false)
  assert.equal(isNoRepositoryLayer('D:\\work\\home', 'D:/work/home'), true)
  assert.equal(isNoRepositoryLayer('D:\\work\\home\\repo', 'D:\\work\\home'), false)
})

test('parseRepoBoolean handles BOM, CRLF, comments, and rejects quoted/invalid values', () => {
  assert.deepEqual(parseRepoBoolean('\uFEFFdemo_enabled: false # off\r\n', 'demo_enabled'), {
    status: 'value',
    value: false,
  })
  assert.deepEqual(parseRepoBoolean('other: 1\ndemo_enabled:   true  \n', 'demo_enabled'), {
    status: 'value',
    value: true,
  })
  assert.deepEqual(parseRepoBoolean('demo_enabled: "false"\n', 'demo_enabled'), {
    status: 'invalid',
    raw: '"false"',
  })
  assert.deepEqual(parseRepoBoolean('  demo_enabled: false\n', 'demo_enabled'), {
    status: 'absent',
  })
  assert.deepEqual(parseRepoBoolean('other_enabled: false\n', 'demo_enabled'), {
    status: 'absent',
  })
})

test('resolveInstallId extracts name@marketplace from plugins/cache paths only', () => {
  assert.equal(
    resolveInstallId('/var/tmp/home/.claude/plugins/cache/melodic-software/demo/1.2.3'),
    'demo@melodic-software',
  )
  assert.equal(
    resolveInstallId('D:\\work\\home\\.claude\\plugins\\cache\\mkt\\demo\\0.1.0'),
    'demo@mkt',
  )
  assert.equal(resolveInstallId('/var/tmp/repos/claude-code-plugins/plugins/demo'), null)
})

test('extractPluginOption matches installId or skips conflicting marketplaces', () => {
  const logs = []
  const settings = {
    pluginConfigs: {
      'demo@mkt-a': { options: { demo_enabled: true } },
      'demo@mkt-b': { options: { demo_enabled: false } },
    },
  }
  assert.deepEqual(
    extractPluginOption(settings, 'demo', 'demo_enabled', 'demo@mkt-a', 'user settings', m => logs.push(m)),
    { status: 'value', value: true },
  )
  assert.equal(logs.length, 0)

  assert.deepEqual(
    extractPluginOption(settings, 'demo', 'demo_enabled', null, 'user settings', m => logs.push(m)),
    { status: 'absent' },
  )
  assert.match(logs[0], /more than one marketplace set different values/)
})

test('resolveModHookEnabled: unset user option defers to repository false and repository true', async () => {
  const spec = { plugin: 'demo', key: 'demo_enabled', defaultValue: true }
  const repoFile = '/work/repo/docs/conventions/demo.yaml'

  const off = fakeEngine({ files: { [repoFile]: 'demo_enabled: false\n' } })
  assert.equal(await resolveModHookEnabled(off.$, { demo_enabled: true }, spec, '/work/repo'), false)

  const onSpec = { plugin: 'demo', key: 'demo_enabled', defaultValue: false }
  const on = fakeEngine({ files: { [repoFile]: 'demo_enabled: true\n' } })
  assert.equal(await resolveModHookEnabled(on.$, { demo_enabled: false }, onSpec, '/work/repo'), true)
})

test('resolveModHookEnabled: explicit user setting beats repository in both directions', async () => {
  const spec = { plugin: 'demo', key: 'demo_enabled', defaultValue: true }
  const repoFile = '/work/repo/docs/conventions/demo.yaml'

  const userTrue = fakeEngine({
    settings: { user: { pluginConfigs: { 'demo@melodic-software': { options: { demo_enabled: true } } } } },
    files: { [repoFile]: 'demo_enabled: false\n' },
  })
  assert.equal(await resolveModHookEnabled(userTrue.$, { demo_enabled: true }, spec, '/work/repo'), true)

  const userFalse = fakeEngine({
    files: { [repoFile]: 'demo_enabled: true\n' },
  })
  assert.equal(await resolveModHookEnabled(userFalse.$, { demo_enabled: false }, spec, '/work/repo'), false)
})

test('resolveModHookEnabled: security mode ignores repository false but honors user false and managed policy', async () => {
  const spec = { plugin: 'demo', key: 'demo_enabled', defaultValue: true, security: true }
  const repoFile = '/work/repo/docs/conventions/demo.yaml'

  const repoFalse = fakeEngine({ files: { [repoFile]: 'demo_enabled: false\n' } })
  assert.equal(await resolveModHookEnabled(repoFalse.$, { demo_enabled: true }, spec, '/work/repo'), true)

  const userFalse = fakeEngine({
    settings: { user: { pluginConfigs: { 'demo@melodic-software': { options: { demo_enabled: false } } } } },
    files: { [repoFile]: 'demo_enabled: true\n' },
  })
  assert.equal(await resolveModHookEnabled(userFalse.$, { demo_enabled: false }, spec, '/work/repo'), false)

  const policyTrue = fakeEngine({
    settings: {
      policy: { pluginConfigs: { 'demo@melodic-software': { options: { demo_enabled: true } } } },
      user: { pluginConfigs: { 'demo@melodic-software': { options: { demo_enabled: false } } } },
    },
  })
  assert.equal(await resolveModHookEnabled(policyTrue.$, { demo_enabled: false }, spec, '/work/repo'), true)
})

test('resolveModHookEnabled: symlinked repo file and invalid values are logged and skipped', async () => {
  const spec = { plugin: 'demo', key: 'demo_enabled', defaultValue: true }
  const repoFile = '/work/repo/docs/conventions/demo.yaml'

  const link = fakeEngine({
    stats: { [repoFile]: { kind: 'file', size: 20, mtimeMs: 0, isLink: true } },
    files: { [repoFile]: 'demo_enabled: false\n' },
  })
  assert.equal(await resolveModHookEnabled(link.$, { demo_enabled: true }, spec, '/work/repo'), true)
  assert.match(link.logs[0].text, /symlink/)

  const badVal = fakeEngine({ files: { [repoFile]: 'demo_enabled: "false"\n' } })
  assert.equal(await resolveModHookEnabled(badVal.$, { demo_enabled: true }, spec, '/work/repo'), true)
  assert.match(badVal.logs[0].text, /dropped ""false""/)
})

test('resolveModHookEnabled: invalid spec fails open and logs diagnostic', async () => {
  const env = fakeEngine()
  assert.equal(await resolveModHookEnabled(env.$, {}, { plugin: '../bad', key: 'demo_enabled', defaultValue: true }), true)
  assert.match(env.logs[0].text, /not a plain name/)

  const env2 = fakeEngine()
  assert.equal(await resolveModHookEnabled(env2.$, {}, { plugin: 'demo', key: 'bad_key', defaultValue: true }), true)
  assert.match(env2.logs[0].text, /not a snake_case <name>_enabled key/)
})

test('resolveModHookEnabled: works when fs.stat and settings.read are unstubbed in unit tests', async () => {
  const spec = { plugin: 'demo', key: 'demo_enabled', defaultValue: true }
  const repoFile = '/work/repo/docs/conventions/demo.yaml'
  const minimal = fakeEngine({
    files: { [repoFile]: 'demo_enabled: false\n' },
    unstubbed: ['settings.read', 'fs.stat', 'env.get', 'session.root'],
  })
  assert.equal(await resolveModHookEnabled(minimal.$, {}, spec, '/work/repo'), false)
})

test('createModEnablement: tracks load-time disablement and updates state on resolve', async () => {
  const spec = { plugin: 'demo', key: 'demo_enabled', defaultValue: true }
  const off = createModEnablement({ demo_enabled: false }, spec)
  assert.equal(off.isDisabledAtLoad(), true)
  assert.equal(off.isEnabled(), false)

  const secOff = createModEnablement({ demo_enabled: false }, { ...spec, security: true })
  assert.equal(secOff.isDisabledAtLoad(), false)
  assert.equal(secOff.isEnabled(), false)

  const gate = createModEnablement({ demo_enabled: true }, spec)
  assert.equal(gate.isDisabledAtLoad(), false)
  assert.equal(gate.isEnabled(), true)

  const eng = fakeEngine({ files: { '/work/repo/docs/conventions/demo.yaml': 'demo_enabled: false\n' } })
  assert.equal(await refreshModEnablement(eng.$, gate, '/work/repo'), false)
  assert.equal(gate.isEnabled(), false)
})

test('resolveConventionHome reads AGENTS.md and CLAUDE.md bindings, ignores pure shims, and honors declined', async () => {
  const bound = fakeEngine({
    files: {
      '/work/repo/AGENTS.md':
        '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `ops/conventions`.\n<!-- END GENERATED: convention-home -->\n',
      '/work/repo/ops/conventions/demo.yaml': 'demo_enabled: false\n',
    },
    stats: {
      '/work/repo': { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, resolved: '/work/repo' },
      '/work/repo/ops/conventions': {
        kind: 'dir',
        size: 0,
        mtimeMs: 0,
        isLink: false,
        resolved: '/work/repo/ops/conventions',
      },
    },
  })
  assert.equal(await resolveConventionHome(bound.$, '/work/repo'), 'ops/conventions')
  const spec = { plugin: 'demo', key: 'demo_enabled', defaultValue: true }
  assert.equal(await resolveModHookEnabled(bound.$, { demo_enabled: true }, spec, '/work/repo'), false)

  const claudeFallback = fakeEngine({
    files: {
      '/work/repo/CLAUDE.md':
        '<!-- BEGIN GENERATED: convention-home -->\nLive in `team/rules`.\n<!-- END GENERATED: convention-home -->\n',
    },
    stats: {
      '/work/repo': { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, resolved: '/work/repo' },
      '/work/repo/team/rules': { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, resolved: '/work/repo/team/rules' },
    },
  })
  assert.equal(await resolveConventionHome(claudeFallback.$, '/work/repo'), 'team/rules')

  const pureShim = fakeEngine({
    files: { '/work/repo/CLAUDE.md': '@AGENTS.md\n' },
  })
  assert.equal(await resolveConventionHome(pureShim.$, '/work/repo'), 'docs/conventions')

  const declined = fakeEngine({
    files: {
      '/work/repo/AGENTS.md':
        '<!-- BEGIN GENERATED: convention-home -->\ndeclined\n<!-- END GENERATED: convention-home -->\n',
      '/work/repo/docs/conventions/demo.yaml': 'demo_enabled: false\n',
    },
  })
  assert.equal(await resolveConventionHome(declined.$, '/work/repo'), null)
  assert.equal(await resolveModHookEnabled(declined.$, { demo_enabled: true }, spec, '/work/repo'), true)
})

test('resolveConventionHome refuses traversal, .git, symlinked dirs, and out-of-tree targets', async () => {
  const traversal = fakeEngine({
    files: {
      '/work/repo/AGENTS.md':
        '<!-- BEGIN GENERATED: convention-home -->\n`../outside`\n<!-- END GENERATED: convention-home -->\n',
    },
  })
  assert.equal(await resolveConventionHome(traversal.$, '/work/repo'), null)

  const dotGit = fakeEngine({
    files: {
      '/work/repo/AGENTS.md':
        '<!-- BEGIN GENERATED: convention-home -->\n`.git/hooks`\n<!-- END GENERATED: convention-home -->\n',
    },
  })
  assert.equal(await resolveConventionHome(dotGit.$, '/work/repo'), null)

  const symlinkDir = fakeEngine({
    files: {
      '/work/repo/AGENTS.md':
        '<!-- BEGIN GENERATED: convention-home -->\n`ops/conventions`\n<!-- END GENERATED: convention-home -->\n',
    },
    stats: {
      '/work/repo': { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, resolved: '/work/repo' },
      '/work/repo/ops/conventions': {
        kind: 'dir',
        size: 0,
        mtimeMs: 0,
        isLink: true,
        resolved: '/work/other',
      },
    },
  })
  assert.equal(await resolveConventionHome(symlinkDir.$, '/work/repo'), null)

  const intermediateLink = fakeEngine({
    files: {
      '/work/repo/AGENTS.md':
        '<!-- BEGIN GENERATED: convention-home -->\n`ops/conventions`\n<!-- END GENERATED: convention-home -->\n',
    },
    stats: {
      '/work/repo': { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, resolved: '/work/repo' },
      '/work/repo/ops/conventions': {
        kind: 'dir',
        size: 0,
        mtimeMs: 0,
        isLink: false,
        resolved: '/work/other/conventions',
      },
    },
  })
  assert.equal(await resolveConventionHome(intermediateLink.$, '/work/repo'), null)
})
