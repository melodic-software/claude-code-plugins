import { expect, test } from 'claude-code/testing'

// A second mod that toasts on every Bash call. Inline plugins close over nothing of this file.
const SENDER = {
  name: 'toast-sender',
  register(on: any) {
    on('tool.call', async ($: any, e: any, next: any) => {
      $.ui.toast('build finished')
      return next(e)
    })
  },
} as any

// A mod that toasts whatever is notified: forwarding must stop after one notification.
const ECHO = {
  name: 'toast-echo',
  register(on: any) {
    on('ui.notify', async ($: any, e: any, next: any) => {
      $.ui.toast(e.text)
      return next(e)
    })
  },
} as any

const world = (on: any) => {
  const toasts: string[] = []
  const notified: { text: string; title?: string }[] = []
  on('ui.toast', ($: unknown, e: { text: string }) => (toasts.push(e.text), { value: undefined }))
  on('ui.notify', ($: unknown, e: { text: string; title?: string }) => (notified.push({ text: e.text, title: e.title }), { value: { isSent: true, channel: 'kitty' } }))
  on('tool.call', () => ({ result: { stdout: 'ok' }, text: 'ok' }))
  return { toasts, notified }
}

const bash = ($: any) => $.tool.call({ tool: 'Bash', command: 'true' })
const settle = () => new Promise(r => setTimeout(r, 20))

test('forward: a toast from a second mod reaches the forwarder, which notifies and calls next', { plugins: [SENDER] }, async ($, on) => {
  const w = world(on)
  await bash($)
  await settle()
  expect(w.notified).toEqual([{ text: 'build finished', title: 'desktop-notification' }])
  expect(w.toasts).toEqual(['build finished'])
})

test('forward: a refused notification still lets the toast show', { plugins: [SENDER] }, async ($, on) => {
  const toasts: string[] = []
  on('ui.toast', ($: unknown, e: { text: string }) => (toasts.push(e.text), { value: undefined }))
  on('ui.notify', () => ({ deny: 'refused' }))
  on('tool.call', () => ({ result: { stdout: 'ok' }, text: 'ok' }))
  await bash($)
  await settle()
  expect(toasts).toEqual(['build finished'])
})

test('forward: a mod that toasts each notification does not echo without end', { plugins: [SENDER, ECHO] }, async ($, on) => {
  const w = world(on)
  await bash($)
  await settle()
  expect(w.notified).toEqual([{ text: 'build finished', title: 'desktop-notification' }])
  expect(w.toasts).toEqual(['build finished', 'build finished'])
})

for (const option of ['desktop_notification_forward_toasts_enabled', 'desktop_notification_enabled']) {
  test(`off: ${option} false suppresses forwarding and the toast still shows`, { plugins: [SENDER], options: { [option]: false } }, async ($, on) => {
    const w = world(on)
    await bash($)
    await settle()
    expect(w.notified).toEqual([])
    expect(w.toasts).toEqual(['build finished'])
  })
}
