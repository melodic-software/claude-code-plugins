import type { EngineInterface } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { startRoom } from '../core/testing.js'
import { BUILT } from './index.js'
import { BANK, OBJECTS, PURR } from './sound-bank.js'
import { BEAT_MS, PARENT_MS, PING_MS, QUIET_MS, STEADY_MS, STOP_FADE_MS, encodedOf, fileOf, linesOf, mixerScript, powershellArgv, wordsOf } from './sound-mixer.js'
import {
  COMMAND_LAG_MS,
  HURRIED_MS,
  OFF_FADE_MS,
  PICTURE_LAG_MS,
  START_FADE_MS,
  NIGHT_LEVEL,
  WATCH_MS,
  COPY,
  HANDOVER_MS,
  RETRY_MS,
  SILENT_MS,
  hooks,
  engineCommand,
  engineSwitched,
  engineTick,
  follow,
  gainOf,
  purr,
  thunderFor,
} from './sound.js'
import { wait, NIGHT, type FakeMixer, COMMANDS, runFile, mixerChild, sky, stand, ranBy, onWindows, quiet } from './sound-testing.js'

declare function setTimeout(fn: () => void, ms: number): unknown

test('in the plugin, one mixer plays the bed, the television and a change of weather, and sound off ends it', { timeoutMs: 30000, options: NIGHT }, async ($, on) => {
  if (!BUILT.includes('sound')) return
  const mixers: FakeMixer[] = []
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000, tokens: 20_000, percent: 10 }, rateLimits: [] } }))
  on('session.info', () => ({ value: { platform: 'wsl', isHosted: false } as never }))
  on('env.get', (_, e) => ({ value: e.name === 'PATH' ? '/win:/usr/bin' : undefined }))
  on('fs.exists', (_, e) => ({ value: ['/win/powershell.exe', '/usr/bin/wslpath'].includes(String(e.path).replace(/^[A-Za-z]:/, '').replace(/\\/g, '/')) }))
  on('process.run', (_, e) => ({ value: { exitCode: 0, stdout: e.argv[1] === '-u' ? `${COMMANDS}\n` : 'W:\\room\\sounds\\bedroom\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('audio.play', () => ({ value: undefined }))
  let clockNow = (): number => 0
  on('process.spawn', async function* (_, e) {
    const m: FakeMixer = { ran: [], outbox: [], ended: false, last: 0 }
    if (e.argv[0] === 'powershell.exe') {
      mixers.push(m)
      expect(e.argv.slice(0, 4)).toEqual(['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand'])
      expect(e.argv.some(word => word.includes('$') || word.includes('MediaPlayer'))).toBe(false)
    }
    yield* mixerChild(m, () => clockNow(), wake => void setTimeout(wake, 20))
  })
  const room = await startRoom($, on, { fakes: false, onWrite: (path, text) => (path === COMMANDS ? runFile(mixers.at(-1)!, text, clockNow()) : undefined) })
  clockNow = () => room.clock.now()
  const verbs = (): string[] => (mixers[0]?.ran ?? []).map(r => r.words.join(' '))

  expect(await room.run('sound on')).toMatch(/^sound is on, played by the Windows mixer \(powershell\.exe\) at volume 70/)
  await wait(50)
  expect(mixers.length).toBe(1)
  expect(verbs()).toContain(`bed ${BANK.night.entries.auto.late} ${(gainOf(70) * NIGHT_LEVEL).toFixed(4)} ${START_FADE_MS}`)
  expect(verbs()).toContain(`load ${BANK.tv.entries.tube.on}`)

  await room.run('tv')
  await wait(50)
  expect(verbs().some(line => line.startsWith(`shot ${BANK.tv.entries.tube.on} `) || line.startsWith(`shot ${BANK.tv.entries.tube.off} `))).toBe(false)
  await room.clock.advance(COMMAND_LAG_MS.direction)
  await wait(50)
  expect(verbs().filter(line => line.startsWith('shot tv/')).length).toBe(1)

  await room.run('weather rain')
  await room.clock.advance(PICTURE_LAG_MS - WATCH_MS)
  await wait(50)
  expect(verbs().some(line => line.startsWith('bed rain/'))).toBe(false)
  for (let step = 0; step < 10 && !verbs().some(line => line.startsWith('bed rain/')); step++) {
    await room.clock.advance(1000)
    await wait(30)
  }
  const rain = verbs().find(line => line.startsWith('bed rain/'))
  expect(rain?.split(' ').slice(0, 2)).toEqual(['bed', BANK.rain.entries.roof.rain])
  expect(Number(rain?.split(' ')[3])).toBeGreaterThan(HURRIED_MS - 1000)

  await room.run('sound volume 40')
  await wait(50)
  expect(verbs().at(-1)).toBe(`level ${gainOf(40).toFixed(4)} 400`)

  expect(await room.run('sound off')).toMatch(/^sound is off: what was playing has faded out/)
  await wait(50)
  expect(verbs().at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  expect(mixers[0]?.ended).toBe(false)
  await room.clock.advance(OFF_FADE_MS + 250)
  await wait(50)
  expect(mixers[0]?.ended).toBe(true)
  await room.clock.advance(3 * 60_000)
  await wait(50)
  expect(mixers.length).toBe(1)
  await room.unmount()
})

test("the mixer's command file, its answers and its script", () => {
  expect(wordsOf({ verb: 'bed', name: undefined, gain: 0.5, fadeMs: 6000.4 })).toBe('bed - 0.5000 6000')
  expect(wordsOf({ verb: 'bed', name: 'night/x.wav', gain: 0.5, fadeMs: 60, from: 0.125 })).toBe('bed night/x.wav 0.5000 60 0.1250')
  expect(mixerScript('W:\\s')).toContain('a=$(if($w.Count -gt 5){[double]$w[5]}else{0})')
  expect(wordsOf({ verb: 'shot', name: 'tv/tube-on.wav', gain: 1.2 })).toBe('shot tv/tube-on.wav 1.0000')
  expect(fileOf([{ seq: 3, command: { verb: 'ping' } }, { seq: 4, command: { verb: 'quit', fadeMs: 150 } }])).toBe('3 ping\n4 quit 150\nend\n')
  expect(linesOf('..ready D:\\tmp\\a.b\\commands.txt\n.ok 3\nsounding 3\n..ok')).toEqual({
    lines: [
      { kind: 'ready', path: 'D:\\tmp\\a.b\\commands.txt' },
      { kind: 'ok', seq: 3 },
      { kind: 'sounding', seq: 3 },
    ],
    rest: 'ok',
  })
  const script = mixerScript("W:\\it's\\sounds")
  expect(script).toContain("$root='W:\\it''s\\sounds'")
  expect(script).toContain('System.Windows.Media.MediaPlayer')
  expect(script).toContain(`if($now-$seen -gt ${QUIET_MS}){Stop $now}`)
  expect(script).toContain(`function Stop($now){if($script:quit -lt 0){foreach($v in $voices){Fade $v 0 ${STOP_FADE_MS} $now;$v.drop=$true};$script:quit=$now+${STOP_FADE_MS}}}`)
  expect(script).toContain(`if($parent -gt 0 -and $now-$looked -ge ${PARENT_MS}){$looked=$now;try{[void][Diagnostics.Process]::GetProcessById($parent)}catch{Stop $now}}`)
  expect(script).toContain("Say ('pid '+$PID)")
  expect(linesOf('pid 4242\n').lines).toEqual([{ kind: 'pid', pid: 4242 }])
  expect(wordsOf({ verb: 'voices' })).toBe('voices')
  expect(linesOf('.voices 9 cicadas/chorus.wav,0.4900,1234,1,0 rain/roof-rain.wav,0.0000,0,0,1\nvoices 10\nfailed rain/roof-rain.wav Cannot open the file.\n').lines).toEqual([
    {
      kind: 'voices',
      seq: 9,
      voices: [
        { name: 'cicadas/chorus.wav', volume: 0.49, atMs: 1234, lengthKnown: true, drop: false },
        { name: 'rain/roof-rain.wav', volume: 0, atMs: 0, lengthKnown: false, drop: true },
      ],
    },
    { kind: 'voices', seq: 10, voices: [] },
    { kind: 'failed', name: 'rain/roof-rain.wav', text: 'Cannot open the file.' },
  ])
  expect(script).toContain("$p.add_MediaFailed({param($s,$e)[Console]::Out.Write('failed '+$n+' '+")
  expect(script).toContain("'voices'{[Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(")
  expect(script).toContain("+[int]$v.p.NaturalDuration.HasTimeSpan+','+[int]$v.drop};Say $t}")
  expect(script).toContain(`if($now-$beat -ge ${BEAT_MS})`)
  expect(script).toContain('Remove-Item -LiteralPath $dir')
  expect(script).toContain(`if($key -ne $stamp -or $now -ge $reread){$reread=$now+${STEADY_MS};`)
  expect(script).not.toContain('else{break}')
  expect(script.endsWith(';exit $code')).toBe(true)
  expect(PING_MS * 3).toBeLessThanOrEqual(QUIET_MS)
  expect(STOP_FADE_MS).toBeLessThanOrEqual(1000)

  expect([encodedOf('a'), encodedOf('ab'), encodedOf('abc'), encodedOf('é')]).toEqual(['YQA=', 'YQBiAA==', 'YQBiAGMA', '6QA='])
  const argv = powershellArgv(script)
  expect(argv.slice(0, 4)).toEqual(['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand'])
  expect(argv[4]).toMatch(/^[A-Za-z0-9+/]+=*$/)
  expect(argv.length).toBe(5)
  expect(argv.join(' ').length).toBeLessThan(32_767)
})

test('S2: a one-shot is a line in the running mixer\'s file, written in the same turn as the click, with no process started', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 4, weather: 0 })
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on, played by the Windows mixer/)
  await s.settle()
  expect(s.mixers.length).toBe(1)
  expect(ranBy(s)).toContain('bed - 0.4900 1500')
  for (const file of [BANK.tv.entries.tube.on, ...OBJECTS.lamp, PURR, ...BANK.thunder.entries.storm.far]) expect(ranBy(s)).toContain(`load ${file}`)

  const spawns = s.calls.filter(call => call === 'process.spawn').length
  const at = s.now()
  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.settle()
  const shot = s.mixers[0]!.ran.find(r => r.words[0] === 'shot')
  expect(shot?.words).toEqual(['shot', BANK.tv.entries.tube.on, '0.4900'])
  expect(shot?.at).toBe(at)
  engineSwitched(s.$, await s.ctx(), 'lamp', true, 'click')
  engineSwitched(s.$, await s.ctx(), 'tape', true, 'click')
  purr(s.$)
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('shot ')).map(line => line.split(' ')[1])).toEqual([BANK.tv.entries.tube.on, OBJECTS.lamp[0], OBJECTS.tape[0], PURR])
  expect(s.calls.filter(call => call === 'process.spawn').length).toBe(spawns)
  expect(s.notes().filter(line => / sounding \d+ ms after it was sent$/.test(line)).length).toBe(3)

  engineSwitched(s.$, await s.ctx(), 'tv', false, 'command')
  engineSwitched(s.$, await s.ctx(), 'console', true, 'command')
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('shot tv/tube-off'))).toEqual([])
  await s.advance(COMMAND_LAG_MS.direction)
  expect(ranBy(s).filter(line => line.startsWith('shot tv/tube-off')).length).toBe(1)
  expect(ranBy(s).filter(line => line.startsWith(`shot ${OBJECTS.console[0]}`))).toEqual([])
  await s.advance(COMMAND_LAG_MS.screen - COMMAND_LAG_MS.direction)
  expect(ranBy(s).filter(line => line.startsWith(`shot ${OBJECTS.console[0]}`)).length).toBe(1)

  sky.weather = 4
  await engineTick(s.$, await s.ctx())
  await thunderFor(s.$, { at: s.now() - 1000, delayS: 1 })
  engineSwitched(s.$, await s.ctx(), 'light', true, 'click')
  await s.advance(WATCH_MS)
  expect(ranBy(s).filter(line => !line.startsWith('level ')).slice(-3).map(line => line.split(' ').slice(0, 2).join(' ')).sort()).toEqual([`bed ${BANK.rain.entries.roof.storm}`, `shot ${BANK.thunder.entries.storm.near[0]}`, `shot ${OBJECTS.light[0]}`].sort())

  await engineCommand(s.$, await s.ctx(), 'sound', ['objects', 'off'])
  const shots = ranBy(s).filter(line => line.startsWith('shot ')).length
  for (const name of ['lava', 'lamp', 'pc'] as const) engineSwitched(s.$, await s.ctx(), name, true, 'click')
  purr(s.$)
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('shot ')).length).toBe(shots)
  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('shot ')).length).toBe(shots + 1)

  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  expect(ranBy(s).at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  const offAt = s.now()
  await s.advance(OFF_FADE_MS)
  expect(s.mixers[0]!.ended).toBe(false)
  await s.advance(250 + BEAT_MS)
  expect(s.mixers.every(m => m.ended)).toBe(true)
  expect(s.mixers[0]!.endedAt! - offAt).toBeLessThanOrEqual(OFF_FADE_MS + 250 + BEAT_MS)
  await quiet(s)
})

test('S2: the mixer pings while it runs, and a mixer that exits by itself is one line in the debug log', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 4, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(3 * PING_MS + 10)
  expect(ranBy(s).filter(line => line === 'ping').length).toBe(3)
  const m = s.mixers[0]!
  m.outbox.push('error the file did not open\n')
  m.exitCode = 3
  m.wake?.()
  await s.settle()
  expect(m.ended).toBe(true)
  expect(s.notes().filter(line => !line.includes('powershell.exe process'))).toEqual([expect.stringMatching(new RegExp(`sound: the mixer exited 3: the file did not open; the mixer starts again in ${RETRY_MS / 1000} s$`))])
  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.advance(1000)
  expect(s.mixers.length).toBe(1)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/sound is on but nothing plays: the mixer exited 3/)
  await s.advance(RETRY_MS + WATCH_MS)
  expect(s.mixers.length).toBe(2)
  await quiet(s)
})

test('a mixer that stops by itself after its idle limit is started again with sound still on; an early clean exit is a failure', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 4, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(QUIET_MS + 10)
  s.mixers[0]!.exitCode = 0
  s.mixers[0]!.wake?.()
  await s.advance(WATCH_MS + 10)
  expect(s.mixers[0]!.ended).toBe(true)
  expect(s.notes()).toEqual([expect.stringMatching(new RegExp(`sound: the mixer stopped after ${QUIET_MS / 1000} s with no command; the next sound starts it again$`))])
  expect(s.mixers.length).toBe(2)
  expect(ranBy(s).some(line => line.startsWith('bed '))).toBe(true)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).not.toMatch(/stopped:/)

  await s.advance(1000)
  s.mixers[1]!.exitCode = 0
  s.mixers[1]!.wake?.()
  await s.advance(WATCH_MS + 10)
  expect(s.notes().at(-1)).toMatch(new RegExp(`sound: the mixer exited 0; the mixer starts again in ${RETRY_MS / 1000} s$`))
  expect(s.mixers.length).toBe(2)
  await s.advance(RETRY_MS + WATCH_MS)
  expect(s.mixers.length).toBe(3)
  await quiet(s)
})

/** The sound piece's own hooks, by event, as register adds them. */
function soundHooks(): Map<string, ($: EngineInterface, e: unknown, next: (e: unknown) => unknown) => unknown> {
  const handlers = new Map<string, ($: EngineInterface, e: unknown, next: (e: unknown) => unknown) => unknown>()
  hooks(((name: string, fn: never) => void handlers.set(name, fn)) as never)
  return handlers
}

test('the session ending, or its desktop window going, fades the mixer out and keeps it out until a window attaches', async () => {
  if (!BUILT.includes('sound')) return
  const on = soundHooks()
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  on.get('session.detach')!(s.$, { surface: 'desktop', clientId: 'c1', reason: 'closed' }, e => e)
  await s.settle()
  expect(ranBy(s).at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  await s.advance(10 * WATCH_MS)
  expect(s.mixers.length).toBe(1)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is on but nothing plays: no desktop window shows this session/)
  on.get('session.attach')!(s.$, { surface: 'desktop', clientId: 'c2' }, e => e)
  await s.advance(WATCH_MS)
  expect(s.mixers.length).toBe(2)
  expect(ranBy(s).some(line => line.startsWith(`bed ${BANK.cicadas.entries.chorus.bed} `))).toBe(true)
  on.get('session.end')!(s.$, { reason: 'other', sessionId: 's1' }, e => e)
  await s.settle()
  expect(ranBy(s).at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  await s.advance(10 * WATCH_MS)
  expect(s.mixers.length).toBe(2)
  on.get('session.attach')!(s.$, { surface: 'desktop', clientId: 'c3' }, e => e)
  await quiet(s)
})

test('pings keep a quiet morning\'s mixer alive, and a mixer silent past its limit with no exit seen is replaced and sent the bed', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 5, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(4 * PING_MS + 10)
  expect(ranBy(s).filter(line => line === 'ping').length).toBe(4)
  expect(ranBy(s).filter(line => line.startsWith('bed '))).toEqual([`bed - 0.4900 ${START_FADE_MS}`])
  expect(s.mixers.length).toBe(1)

  s.mixers[0]!.mute = true
  Object.assign(sky, { sun: 0, weather: 0 })
  await s.advance(SILENT_MS + 2 * WATCH_MS)
  expect(s.mixers.length).toBe(2)
  expect(s.notes()).toContainEqual(expect.stringMatching(new RegExp(`sound: the mixer has said nothing for ${SILENT_MS / 1000} s; starting another$`)))
  expect(ranBy(s).filter(line => line.startsWith('bed '))).toEqual([`bed ${BANK.cicadas.entries.chorus.bed} 0.4900 ${START_FADE_MS}`])
  await quiet(s)
})

test('one player per session: a newer copy of the mod holding it ends this one\'s, and this one waits for an older copy to fade out', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(s.mixers.length).toBe(1)
  s.state.set('bedroom-mixer', COPY + 1)
  await s.advance(WATCH_MS + 10)
  expect(ranBy(s).at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  await s.advance(10 * WATCH_MS)
  expect(s.mixers.length).toBe(1)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/nothing plays: a newer copy of the mod plays it/)

  s.state.set('bedroom-mixer', COPY - 1)
  await s.advance(WATCH_MS + 10)
  expect([s.mixers.length, s.state.get('bedroom-mixer')]).toEqual([1, COPY])
  await s.advance(HANDOVER_MS + WATCH_MS)
  expect(s.mixers.length).toBe(2)
  expect(s.state.get('bedroom-mixer')).toBe(COPY)
  await quiet(s)
})

test('with sound saved on and nothing started yet, as after a reload, a change of hour starts the mixer and sends the bed', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await (await s.ctx()).save({ sound: true })
  expect(s.mixers.length).toBe(0)
  await engineCommand(s.$, await s.ctx(), 'time', ['dusk'])
  await s.advance(10)
  expect(s.mixers.length).toBe(1)
  expect(ranBy(s).filter(line => line.startsWith('bed '))).toEqual([`bed ${BANK.cicadas.entries.chorus.bed} 0.4900 ${START_FADE_MS}`])
  await s.advance(5 * PING_MS)
  expect(ranBy(s).filter(line => line === 'ping').length).toBe(5)
  await quiet(s)
})

test('a one-shot and the bed both waiting to hold the player open one mixer between them, and sound off ends it', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  const state = s.$.state as unknown as { set: (key: unknown, value: unknown) => Promise<void> }
  const set = state.set
  const held: (() => void)[] = []
  state.set = (key, value) => new Promise(resolve => void held.push(() => void set(key, value).then(resolve)))
  await (await s.ctx()).save({ sound: true })
  purr(s.$)
  void follow(s.$)
  await s.settle()
  expect(held.length).toBe(2)
  state.set = set
  for (const release of held.splice(0)) release()
  await s.advance(10)
  expect(s.mixers.length).toBe(1)
  await quiet(s)
  expect(s.mixers.every(m => m.ended)).toBe(true)
})
