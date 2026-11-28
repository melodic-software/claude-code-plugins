import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { chmodSync, mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { isHookEnabled, isNoRepositoryLayer, resolveHookEnabled } from './hook-enabled.mjs'

function makeFixture() {
  const work = mkdtempSync(join(tmpdir(), 'hook-enabled-mjs-'))
  const project = join(work, 'project')
  const home = join(work, 'home')
  const conf = join(project, 'docs', 'conventions', 'demo.yaml')
  const installed = join(work, 'config', 'plugins', 'cache', 'market', 'demo', '1.0.0', 'lib', 'hook-enabled.mjs')
  const settings = join(work, 'config', 'settings.json')
  mkdirSync(join(project, 'docs', 'conventions'), { recursive: true })
  mkdirSync(join(project, 'settings'), { recursive: true })
  mkdirSync(join(home, 'docs', 'conventions'), { recursive: true })
  mkdirSync(join(work, 'config', 'plugins', 'cache', 'market', 'demo', '1.0.0', 'lib'), { recursive: true })
  return {
    work,
    project,
    home,
    conf,
    installed,
    settings,
    setRepo(content) {
      if (content === null) rmSync(conf, { force: true })
      else writeFileSync(conf, content, 'utf8')
    },
    setSettings(obj) {
      if (obj === null) rmSync(settings, { force: true })
      else writeFileSync(settings, typeof obj === 'string' ? obj : JSON.stringify(obj), 'utf8')
    },
    cleanup() {
      rmSync(work, { recursive: true, force: true })
    },
  }
}

function runResolve(fx, plugin, key, def, opts = {}) {
  const errs = []
  const env = { HOME: fx.home, CLAUDE_PROJECT_DIR: fx.project, ...(opts.env ?? {}) }
  const code = resolveHookEnabled(plugin, key, def, {
    ...opts,
    env,
    stderr: (m) => errs.push(m),
  })
  return { code, err: errs.join('\n') }
}

const dropped = (val, from) =>
  `hook-enabled: demo_enabled: dropped "${val}" from ${from}; only an unquoted true or false is read`

test('precedence: user layer beats repository layer beats plugin default', () => {
  const fx = makeFixture()
  try {
    fx.setRepo('demo_enabled: true\n')
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, { env: { CLAUDE_PLUGIN_OPTION_DEMO_ENABLED: 'false' } }),
      { code: 1, err: '' },
    )
    assert.equal(
      isHookEnabled('demo', 'demo_enabled', true, {
        env: { HOME: fx.home, CLAUDE_PROJECT_DIR: fx.project, CLAUDE_PLUGIN_OPTION_DEMO_ENABLED: 'false' },
      }),
      false,
    )

    fx.setRepo('demo_enabled: false\n')
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', false, { env: { CLAUDE_PLUGIN_OPTION_DEMO_ENABLED: 'true' } }),
      { code: 0, err: '' },
    )
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 1, err: '' })
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, { env: { CLAUDE_PLUGIN_OPTION_DEMO_ENABLED: '' } }),
      { code: 1, err: '' },
    )

    fx.setRepo('demo_enabled: true\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', false), { code: 0, err: '' })

    fx.setRepo(null)
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 0, err: '' })
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', false), { code: 1, err: '' })
  } finally {
    fx.cleanup()
  }
})

test('invalid values are named and dropped; comments, BOM, CRLF, nested and longer keys handled', () => {
  const fx = makeFixture()
  try {
    fx.setRepo('demo_enabled: false\n')
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, { env: { CLAUDE_PLUGIN_OPTION_DEMO_ENABLED: 'yes' } }),
      { code: 1, err: dropped('yes', 'CLAUDE_PLUGIN_OPTION_DEMO_ENABLED') },
    )

    fx.setRepo('demo_enabled: "false"\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), {
      code: 0,
      err: dropped('"false"', fx.conf),
    })

    fx.setRepo('demo_enabled:\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', false), {
      code: 1,
      err: dropped('', fx.conf),
    })

    fx.setRepo('demo_enabled: TRUE\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', false), {
      code: 1,
      err: dropped('TRUE', fx.conf),
    })

    fx.setRepo('\uFEFFdemo_enabled: false   # off for this repository\r\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 1, err: '' })

    fx.setRepo('other:\n  demo_enabled: false\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 0, err: '' })

    fx.setRepo('demo_enabled_extra: false\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 0, err: '' })

    fx.setRepo('demo_enabled: false\ndemo_enabled: true\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 1, err: '' })
  } finally {
    fx.cleanup()
  }
})

test('symlinks, home-root guard, custom --root and --home', () => {
  const fx = makeFixture()
  try {
    const target = join(fx.work, 'target.yaml')
    writeFileSync(target, 'demo_enabled: false\n', 'utf8')
    symlinkSync(target, fx.conf)
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), {
      code: 0,
      err: `hook-enabled: demo_enabled: skipped ${fx.conf}; a symlink, and the repository layer reads only regular files`,
    })

    assert.equal(isNoRepositoryLayer(fx.home, fx.home), true)
    assert.equal(isNoRepositoryLayer(fx.work, fx.home), true)
    assert.equal(isNoRepositoryLayer('', fx.home), true)
    assert.equal(isNoRepositoryLayer(fx.project, fx.home), false)
    assert.equal(isNoRepositoryLayer('C:\\Example\\Home', 'c:/Example/Home'), true)

    writeFileSync(join(fx.project, 'settings', 'demo.yaml'), 'demo_enabled: false\n', 'utf8')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true, { home: 'settings' }), { code: 1, err: '' })

    const boundDir = join(fx.project, 'team')
    mkdirSync(boundDir, { recursive: true })
    writeFileSync(join(boundDir, 'demo.yaml'), 'demo_enabled: false\n', 'utf8')
    writeFileSync(
      join(fx.project, 'AGENTS.md'),
      '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `team`.\n<!-- END GENERATED: convention-home -->\n',
      'utf8',
    )
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 1, err: '' })

    writeFileSync(
      join(fx.project, 'AGENTS.md'),
      '<!-- BEGIN GENERATED: convention-home -->\ndeclined\n<!-- END GENERATED: convention-home -->\n',
      'utf8',
    )
    fx.setRepo('demo_enabled: false\n')
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 0, err: '' })

    rmSync(join(fx.project, 'AGENTS.md'))
    writeFileSync(
      join(fx.project, 'CLAUDE.md'),
      '<!-- BEGIN GENERATED: convention-home -->\nConventions live in `team`.\n<!-- END GENERATED: convention-home -->\n',
      'utf8',
    )
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 1, err: '' })

    const linkHome = join(fx.project, 'linked-home')
    symlinkSync(boundDir, linkHome)
    writeFileSync(
      join(fx.project, 'AGENTS.md'),
      '<!-- BEGIN GENERATED: convention-home -->\nConventions live in `linked-home`.\n<!-- END GENERATED: convention-home -->\n',
      'utf8',
    )
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 0, err: '' })

    writeFileSync(
      join(fx.project, 'AGENTS.md'),
      '<!-- BEGIN GENERATED: convention-home -->\nConventions live in `../escape`.\n<!-- END GENERATED: convention-home -->\n',
      'utf8',
    )
    assert.deepEqual(runResolve(fx, 'demo', 'demo_enabled', true), { code: 0, err: '' })
  } finally {
    fx.cleanup()
  }
})

test('security mode: repository and env false ignored; install-cache settings and managed files respected', () => {
  const fx = makeFixture()
  const managedDir = join(fx.work, 'managed')
  const managed = join(managedDir, 'managed-settings.json')
  const dropin = join(managedDir, 'managed-settings.d', '50-team.json')
  mkdirSync(join(managedDir, 'managed-settings.d'), { recursive: true })
  try {
    fx.setRepo('demo_enabled: false\n')
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, { security: true, managedFiles: [] }),
      { code: 0, err: '' },
    )
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        security: true,
        managedFiles: [],
        env: { CLAUDE_PLUGIN_OPTION_DEMO_ENABLED: 'false' },
      }),
      { code: 0, err: '' },
    )
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', false, {
        security: true,
        managedFiles: [],
        env: { CLAUDE_PLUGIN_OPTION_DEMO_ENABLED: 'true' },
      }),
      { code: 0, err: '' },
    )

    fx.setRepo('demo_enabled: true\n')
    fx.setSettings({ pluginConfigs: { 'demo@market': { options: { demo_enabled: false } } } })
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        security: true,
        sourceFile: fx.installed,
        managedFiles: [],
        env: { CLAUDE_PLUGIN_OPTION_DEMO_ENABLED: 'true' },
      }),
      { code: 1, err: '' },
    )
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        security: false,
        sourceFile: fx.installed,
        managedFiles: [],
      }),
      { code: 0, err: '' },
    )
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        security: true,
        sourceFile: '/tmp/not-cache/hook-enabled.mjs',
        managedFiles: [],
      }),
      { code: 0, err: '' },
    )

    writeFileSync(managed, JSON.stringify({ pluginConfigs: { 'demo@market': { options: { demo_enabled: true } } } }))
    chmodSync(managed, 0o666)
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        security: true,
        sourceFile: fx.installed,
        managedFiles: [managed],
        ownerCheck: true,
      }),
      { code: 0, err: '' },
    )

    fx.setSettings({ pluginConfigs: { 'demo@market': { options: { demo_enabled: true } } } })
    writeFileSync(managed, JSON.stringify({ pluginConfigs: { 'demo@market': { options: { demo_enabled: false } } } }))
    chmodSync(managed, 0o666)
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', false, {
        security: true,
        sourceFile: fx.installed,
        managedFiles: [managed],
        ownerCheck: true,
      }),
      {
        code: 0,
        err: `hook-enabled: demo_enabled: skipped false from ${managed}; a managed file that turns a guard off must be root-owned and writable by no one else`,
      },
    )
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        security: true,
        sourceFile: fx.installed,
        managedFiles: [managed],
        ownerCheck: false,
      }),
      { code: 1, err: '' },
    )

    writeFileSync(managed, JSON.stringify({ pluginConfigs: { 'demo@market': { options: { demo_enabled: true } } } }))
    writeFileSync(dropin, JSON.stringify({ pluginConfigs: { 'demo@market': { options: { demo_enabled: false } } } }))
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        security: true,
        sourceFile: fx.installed,
        managedFiles: [managed, dropin],
        ownerCheck: false,
      }),
      { code: 1, err: '' },
    )
  } finally {
    fx.cleanup()
  }
})

test('gitHook mode: reads CLAUDE_CONFIG_DIR/settings.json and git toplevel repository layer', () => {
  const fx = makeFixture()
  const clone = join(fx.work, 'clone')
  const configDir = join(fx.work, 'claude')
  const userSettings = join(configDir, 'settings.json')
  mkdirSync(join(clone, 'docs', 'conventions'), { recursive: true })
  mkdirSync(join(clone, 'sub', 'dir'), { recursive: true })
  mkdirSync(configDir, { recursive: true })
  try {
    execFileSync('git', ['-c', 'init.defaultBranch=main', 'init', '-q', clone], {
      env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' },
    })
    writeFileSync(join(clone, 'docs', 'conventions', 'demo.yaml'), 'demo_enabled: true\n', 'utf8')
    writeFileSync(userSettings, JSON.stringify({ pluginConfigs: { 'demo@market': { options: { demo_enabled: false } } } }))
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        gitHook: true,
        cwd: join(clone, 'sub', 'dir'),
        env: { CLAUDE_CONFIG_DIR: configDir, GIT_CEILING_DIRECTORIES: fx.work },
      }),
      { code: 1, err: '' },
    )

    writeFileSync(
      userSettings,
      JSON.stringify({
        pluginConfigs: {
          'demo@market': { options: { demo_enabled: false } },
          'demo@other': { options: { demo_enabled: true } },
        },
      }),
    )
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        gitHook: true,
        cwd: join(clone, 'sub', 'dir'),
        env: { CLAUDE_CONFIG_DIR: configDir, GIT_CEILING_DIRECTORIES: fx.work },
      }),
      {
        code: 0,
        err: `hook-enabled: demo_enabled: skipped pluginConfigs["demo@*"] in ${userSettings}; entries for more than one marketplace set different values`,
      },
    )

    rmSync(userSettings)
    writeFileSync(join(clone, 'docs', 'conventions', 'demo.yaml'), 'demo_enabled: false\n', 'utf8')
    assert.deepEqual(
      runResolve(fx, 'demo', 'demo_enabled', true, {
        gitHook: true,
        cwd: join(clone, 'sub', 'dir'),
        env: {
          CLAUDE_CONFIG_DIR: configDir,
          CLAUDE_PROJECT_DIR: fx.project,
          GIT_CEILING_DIRECTORIES: fx.work,
        },
      }),
      { code: 1, err: '' },
    )
  } finally {
    fx.cleanup()
  }
})

test('usage errors return exit code 2 and isHookEnabled stays on (fail open)', () => {
  const fx = makeFixture()
  try {
    const badPlugin = runResolve(fx, '../bad', 'demo_enabled', true)
    assert.equal(badPlugin.code, 2)
    assert.match(badPlugin.err, /not a plain name/)

    const badKey = runResolve(fx, 'demo', 'not_a_valid_key', true)
    assert.equal(badKey.code, 2)
    assert.match(badKey.err, /not a snake_case/)

    const badDef = runResolve(fx, 'demo', 'demo_enabled', 'true')
    assert.equal(badDef.code, 2)
    assert.match(badDef.err, /not true or false/)
    assert.equal(isHookEnabled('demo', 'bad', true, { stderr: () => {} }), true)
  } finally {
    fx.cleanup()
  }
})
