import { expect, test } from 'claude-code/testing'

import { BUILT } from './index.js'
import { VOICES_WAIT_MS, engineCommand } from './sound.js'
import { sky, stand, onWindows, quiet, ranBy } from './sound-testing.js'

test('/bedroom sound ends with the voices the mixer reports, how long since it last wrote, and the last file it could not open; no answer within the wait says so', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 2, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(2000)
  const m = s.mixers.at(-1)!
  m.voices = 'crickets/crickets.wav,0.1960,15234,1,0 rain/roof-rain.wav,0.0000,0,0,1'
  m.outbox.push('failed rain/roof-rain.wav Exception from HRESULT: 0xC00D11B1\n')
  m.wake?.()
  await s.advance(3000)
  const answer = (await engineCommand(s.$, await s.ctx(), 'sound', [])) ?? ''
  expect(ranBy(s).filter(line => line === 'voices').length).toBe(1)
  expect(answer.slice(answer.indexOf('objects on|off.'))).toMatch(
    /^objects on\|off\. mixer last heard \d+ ms ago; its voices: crickets\/crickets\.wav volume 0\.1960 at 15234 ms, length known; rain\/roof-rain\.wav volume 0\.0000 at 0 ms, length unknown, ending\. last open failure: rain\/roof-rain\.wav 3 s ago: Exception from HRESULT: 0xC00D11B1\.$/,
  )
  expect(s.notes().some(line => line.includes('sound: the mixer could not open rain/roof-rain.wav: Exception from HRESULT: 0xC00D11B1'))).toBe(true)

  m.mute = true
  m.wake?.()
  await s.settle()
  const late = engineCommand(s.$, await s.ctx(), 'sound', [])
  await s.advance(VOICES_WAIT_MS)
  expect(await late).toMatch(/its voices: no answer\. last open failure: rain\/roof-rain\.wav \d+ s ago/)
  await quiet(s)
})
