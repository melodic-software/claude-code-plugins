import { expect, test } from 'claude-code/testing'

import { AUTO_NOTE, buildPrompt, ledgerLine, noteFor, summarize, type Finding } from './observer-live.ts'
import { readOptions } from './observer-machine.ts'

const F: Finding = { finding: 'Merged without the verdict.', category: 'verification', rule: 'R6', evidence: 'gh pr merge ran first' }

test('readOptions gives every default when nothing is set', () => {
  const { options, invalid } = readOptions({})
  expect(invalid).toEqual([])
  expect(options).toMatchObject({
    stepCheck: true,
    turnEndCheck: false,
    stepEvery: 6,
    autoSend: false,
    autoNote: AUTO_NOTE,
    guidance: '',
    checkPrompt: '',
    changeCheck: false,
    changeTools: ['Edit', 'Write', 'NotebookEdit'],
    gateCheck: false,
    gateTimeoutMs: 30_000,
    gateRefusals: 1,
    clearAfterPrompts: 2,
    ignoredFree: 2,
    skipMax: 16,
    guidanceMax: 2000,
  })
  expect(options.gatePattern.test('git push origin feat/x')).toBe(true)
  expect(options.gatePattern.test('gh pr merge 12 --squash')).toBe(true)
  expect(options.gatePattern.test('gh api repos/o/r/issues -X POST -f body=x')).toBe(true)
  expect(options.gatePattern.test('git status')).toBe(false)
  expect(options.gatePattern.test('gh pr view 12')).toBe(false)
})

test('readOptions takes valid values and falls back, naming each invalid key', () => {
  const { options, invalid } = readOptions({
    observer_auto_send: true,
    observer_step_every: 3,
    observer_change_tools: 'Edit, Write',
    observer_gate_pattern: '(',
    observer_gate_timeout_seconds: -5,
    observer_gate_refusals: 2,
    observer_guidance: 'Watch for skipped skill steps.',
  })
  expect(options.autoSend).toBe(true)
  expect(options.stepEvery).toBe(3)
  expect(options.changeTools).toEqual(['Edit', 'Write'])
  expect(options.gateRefusals).toBe(2)
  expect(options.guidance).toBe('Watch for skipped skill steps.')
  expect(options.gateTimeoutMs).toBe(30_000)
  expect(options.gatePattern.test('git push')).toBe(true)
  expect(invalid.sort()).toEqual(['observer_gate_pattern', 'observer_gate_timeout_seconds'])
})

test('noteFor speaks as the person for Send and as the plugin for auto-send', () => {
  expect(noteFor(F)).toContain('not my instruction')
  const auto = noteFor(F, 'plugin')
  expect(auto.startsWith(AUTO_NOTE)).toBe(true)
  expect(auto).not.toContain('my instruction')
  expect(auto).toContain('> verification: Merged without the verdict.')
  expect(noteFor(F, 'plugin', 'Custom lead:')).toContain('Custom lead:\n> verification')
})

test('ledgerLine writes each kind, with the delivery for auto-sent', () => {
  expect(ledgerLine('confirmed', 'T', F)).toBe('\n- Confirmed T: Merged without the verdict.\n')
  expect(ledgerLine('auto-sent', 'T', F, 'append')).toBe('\n- Auto-sent T (append): Merged without the verdict.\n')
})

test('buildPrompt names the widened kinds, adds guidance cut to its limit, and says when findings are sent', () => {
  const plain = buildPrompt([], [])
  expect(plain).toContain("never sees your reply unless the person sends it")
  for (const term of ['skill', 'standard', 'review criteri', 'plugin philosophy', 'code-quality', 'intent and vision']) expect(plain).toContain(term)
  const auto = buildPrompt([], [], undefined, [], false, { autoSend: true, guidance: 'x'.repeat(50), guidanceMax: 10 })
  expect(auto).toContain('sent to the assistant as a note')
  expect(auto).toContain(`The person's guidance for these checks:\n${'x'.repeat(10)}\n`)
  expect(auto).not.toContain('x'.repeat(11))
})

test('buildPrompt replaces only the instructions with an override, keeping the lists and the answer shape', () => {
  const p = buildPrompt(['seen one'], [], undefined, [], false, { override: 'Only flag skipped tests.' })
  expect(p).toContain('Only flag skipped tests.')
  expect(p).not.toContain('Four kinds count')
  expect(p).toContain('- seen one')
  expect(p).toContain('finding: none')
})

test('buildPrompt asks about a held command', () => {
  expect(buildPrompt([], [], undefined, [], false, { heldCommand: 'git push' })).toContain('about to run this command')
})

test('summarize counts auto-sends and observer turns', () => {
  const rows = [
    { trigger: 'step', outcome: 'shown', latencyMs: 1000, usage: { output_tokens: 1, cache_read_input_tokens: 10, cache_creation_input_tokens: 0 } },
    { answer: 'auto_sent', delivery: 'append' },
    { answer: 'auto_sent', delivery: 'submit' },
    { answer: 'auto_send_failed', delivery: 'append' },
    { observerTurn: 't1', usage: { output_tokens: 2000, cache_read_input_tokens: 5000, cache_creation_input_tokens: 0 } },
  ]
  expect(summarize(rows)).toContain('auto-sent 2 (append 1, submit 1), failed 1; observer turns 1: 5K cache read, 2K output')
})
