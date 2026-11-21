import { expect, test } from 'claude-code/testing'

import { BUILT } from '../pieces/index.js'
import { NOT_BUILT } from './piece.js'
import { QUIET, startRoom } from './testing.js'

test('every /bedroom word answers', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  const run = room.run

  expect(await run('status')).toBe('on: tv, pc. off: tape, console, light, lamp, lava. posters: plain. dim: 0')
  expect(await run('stats')).toMatch(/^renders: \d+\. room sent: \d+\. changed by numbers only: \d+ \(most in one minute this hour: \d+\)\. last render asked [\d.-]+ ms after the change, built in [\d.]+ ms \(slowest [\d.]+ ms\)\. room size: \d+ of 131072 characters\. shader: on\. build: /)
  expect(await run('glass 30')).toBe('glass 30, blur 0')
  expect(await run('glass 300')).toMatch(/^give a number from 0 to 95/)
  expect(await run('blur 4')).toBe('glass 30, blur 4')
  expect(await run('blur')).toMatch(/^give a number from 0 to 40/)
  expect(await run('title console Starfall Run')).toBe('the console title is "Starfall Run"; this sends the room once')
  expect(await run('title console')).toBe('the console title is the default; this sends the room once')
  expect(await run('title')).toMatch(/^say which/)
  expect(await run('dim 30')).toMatch(/dim: 30/)
  expect(await run('dim 90')).toBe('give a number from 0 to 80, as in /bedroom dim 30')
  expect(await run('dim')).toMatch(/dim: 0$/)
  expect(await run('posters plain')).toMatch(/posters: plain/)
  expect(await run('posters loud')).toBe('posters is plain')
  expect(await run('calibrate')).toBe('click the bottom-left corner of the front of the dresser')

  await room.clock.advance(7300)
  expect(await run('tv off')).toMatch(/off: tv,/)
  expect(await run('tv off')).toMatch(/^the tv is already off/)
  expect(await run('tv')).toMatch(/^on: tv,/)
  for (const name of ['tape', 'console', 'pc', 'light', 'lamp', 'lava']) {
    const now = await run(name)
    expect(now, name).toMatch(/^on: /)
    expect(await run(`${name} maybe`)).toBe(`say on or off, as in /bedroom ${name} off; with neither, it flips`)
  }
  await room.clock.advance(8000)
  const screen = (await room.values())?.screen
  expect(await run('tape on')).toMatch(/^the tape is already on\. If the room shows it otherwise, \/bedroom sync/)
  expect(await run('console on')).toMatch(/^the console is already on\. If the room shows it otherwise, \/bedroom sync/)
  await room.clock.advance(4000)
  expect((await room.values())?.screen).toBe(screen)

  await room.clock.advance(7300)
  expect(await room.values()).toBeDefined()
  expect(await run('shader off')).toMatch(/^the shader is off/)
  expect(await room.values()).toBeUndefined()
  expect(await run('instant on')).toMatch(/^instant switching is on/)
  expect(await run('shader default')).toMatch(/^shader follows its setting again \(now true\)/)
  expect(await run('sync')).toMatch(/^the room shows alone for 7 seconds/)
  expect(await room.values()).toBeUndefined()
  expect(await run('reset')).toMatch(/^on: tv, pc\. off: tape, console, light, lamp, lava/)
  expect(await run('off')).toBe('cleared')
  expect(await run('on')).toBe('the room is on')

  for (const [word, piece] of [['time noon', 'time'], ['weather rain', 'weather'], ['signal off', 'claude-tv'], ['hall off', 'hallway'], ['sound', 'sound']] as const) {
    const reply = await run(word)
    if (!BUILT.includes(piece)) expect(reply, word).toBe(NOT_BUILT)
    else expect(reply.length, word).toBeGreaterThan(0)
  }
  for (const key of ['time', 'weather', 'sound', 'signal', 'hall']) {
    expect(await run(`${key} default`)).toMatch(new RegExp(`^${key} follows its setting again`))
  }
  expect(await run('juggle')).toMatch(/^no such setting\. The switches are tv, tape, console, pc, light, lamp, lava; also status/)
  await room.unmount()
})
