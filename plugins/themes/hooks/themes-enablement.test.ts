import type { On, ProcessSpawnChunk, ProcessSpawnResult } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { EVENING, QUIET } from './bedroom/core/testing'

const REPO_FILE = '/work/docs/conventions/themes.yaml'

const setupThemesWorld = (
  on: On,
  {
    repoYaml,
    userConfig,
  }: { repoYaml?: string; userConfig?: Record<string, unknown> } = {},
) => {
  mock.clock(on, { now: EVENING })
  mock.store(on, {})
  const registered: string[] = []
  const themes: string[] = []
  on('command.register', (_, e) => {
    registered.push(e.name)
    return { value: { command: e.name } }
  })
  on('theme.set', (_, e) => {
    themes.push(`set ${e.backdrop !== undefined && 'scene' in e.backdrop ? e.backdrop.scene : 'none'}`)
    return { value: { isDrawn: true, requestId: 'backdrop' } }
  })
  on('theme.clear', () => {
    themes.push('clear')
    return { value: { isDrawn: false, reason: 'cleared' } }
  })
  on('ui.log', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.usage', () => ({
    value: { startedAt: EVENING, context: { window: 200_000, tokens: 20_000, percent: 10 }, rateLimits: [] },
  }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('settings.read', (_, e) => ({
    value: e.source === 'user' && userConfig ? { pluginConfigs: { 'themes@melodic-software': { options: userConfig } } } : {},
  }))
  on('fs.stat', (_, e) => {
    if (e.path === REPO_FILE && repoYaml !== undefined) {
      return { value: { kind: 'file', size: repoYaml.length, mtimeMs: 0, isLink: false } }
    }
    return { deny: `ENOENT: ${e.path}` }
  })
  on('fs.read', (_, e) => {
    if (e.path === REPO_FILE && repoYaml !== undefined) return { value: repoYaml }
    return { deny: `ENOENT: ${e.path}` }
  })
  return { registered, themes }
}

test('enablement: user false registers and draws nothing whatever docs/conventions/themes.yaml says', {
  options: { ...QUIET, themes_enabled: false },
}, async ($, on) => {
  const w = setupThemesWorld(on, { repoYaml: 'themes_enabled: true\n' })
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  expect(w.registered).toEqual([])
  expect(w.themes).toEqual([])
})

test('enablement: user unset and repository false registers and draws nothing', {
  options: QUIET,
}, async ($, on) => {
  const w = setupThemesWorld(on, { repoYaml: 'themes_enabled: false\n' })
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  expect(w.registered).toEqual([])
  expect(w.themes).toEqual([])
})

test('enablement: user unset and repository true registers /bedroom and sets the theme', {
  options: QUIET,
}, async ($, on) => {
  const w = setupThemesWorld(on, { repoYaml: 'themes_enabled: true\n' })
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  expect(w.registered).toEqual(['bedroom'])
  expect(w.themes).toEqual(['set bedroom'])
})

test('enablement: explicit user true overrides repository false', {
  options: { ...QUIET, themes_enabled: true },
}, async ($, on) => {
  const w = setupThemesWorld(on, {
    repoYaml: 'themes_enabled: false\n',
    userConfig: { themes_enabled: true },
  })
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  expect(w.registered).toEqual(['bedroom'])
  expect(w.themes).toEqual(['set bedroom'])
})

test('enablement: repo false with sound true keeps piece hooks silent on detach/attach and turn lifecycle', {
  options: { ...QUIET, sound: true, signal: true },
}, async ($, on) => {
  mock.store(on, {})
  const registered: string[] = []
  const themes: string[] = []
  const processes: string[] = []
  const existsProbes: string[] = []
  const timers: number[] = []
  on('command.register', (_, e) => {
    registered.push(e.name)
    return { value: { command: e.name } }
  })
  on('theme.set', (_, e) => {
    themes.push(`set ${e.backdrop !== undefined && 'scene' in e.backdrop ? e.backdrop.scene : 'none'}`)
    return { value: { isDrawn: true, requestId: 'backdrop' } }
  })
  on('ui.log', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('clock.now', () => ({ value: EVENING }))
  on('clock.after', (_, e) => {
    timers.push(e.ms)
    return { value: { cancel: () => undefined } }
  })
  on('fs.exists', (_, e) => {
    existsProbes.push(e.path)
    return { value: true }
  })
  on('process.run', (_, e) => {
    processes.push(e.argv.join(' '))
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('audio.play', () => {
    processes.push('audio.play')
    return { value: undefined }
  })
  on('process.spawn', async function* (_, e): AsyncGenerator<ProcessSpawnChunk, ProcessSpawnResult> {
    processes.push(e.argv.join(' '))
    return { code: 0, signal: null }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.detach', (_, e) => ({ clientId: e.clientId }))
  on('session.attach', (_, e) => ({ clientId: e.clientId }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('session.stop', (_, e) => ({ isTurnRunning: e.isTurnRunning }))
  on('session.measure', (_, e) => ({ changed: e.changed }))
  on('settings.read', () => ({ value: {} }))
  on('fs.stat', (_, e) => {
    if (e.path === REPO_FILE) {
      return { value: { kind: 'file', size: 22, mtimeMs: 0, isLink: false } }
    }
    return { deny: `ENOENT: ${e.path}` }
  })
  on('fs.read', (_, e) => {
    if (e.path === REPO_FILE) return { value: 'themes_enabled: false\n' }
    return { deny: `ENOENT: ${e.path}` }
  })

  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  await $.session.detach({ surface: 'desktop', clientId: 'desktop:default', reason: 'detach' })
  await $.session.attach({ surface: 'desktop', clientId: 'desktop:default' })
  await $.turn.start({ text: '', turnId: 't1' })
  await $.turn.complete({ answer: '', durationMs: 1000, isAborted: false, turnId: 't1', reason: 'answer' })
  await $.session.measure({ context: { window: 200_000, tokens: 160_000, percent: 80 }, rateLimits: [], changed: ['context'] })
  await $.session.stop({ isTurnRunning: true })
  await $.session.end({ reason: 'other', sessionId: 's1' })

  expect(registered).toEqual([])
  expect(themes).toEqual([])
  expect(processes).toEqual([])
  expect(existsProbes).toEqual([])
  expect(timers).toEqual([])
})
