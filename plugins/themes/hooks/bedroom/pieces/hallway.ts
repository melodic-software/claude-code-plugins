import type { Ctx, Piece } from '../core/piece.js'
import { CUES } from '../core/signals.gen.js'

/** How soon a cue shows once it is sent: the app's delay and ease, then the shader's 2.5 s hold. */
const SHOWS_S = 4.5

/** /bedroom hall pass and /bedroom hall light: the hallway's events at once, while the hallway is on. */
async function now(ctx: Ctx, word: 'pass' | 'light'): Promise<string> {
  if (!ctx.setting('hall')) return 'the hallway is off: say /bedroom hall on first'
  const delay = await ctx.cue(word === 'pass' ? CUES.pass : CUES.light, `/bedroom hall ${word}`)
  const when = `in about ${Math.round(delay / 1000 + SHOWS_S)} s`
  return word === 'pass'
    ? `someone passes the door ${when}`
    : `the hall light turns on ${when} and stays on for three minutes; if it is already on, it turns off`
}

/**
 * The hallway: the hall field is 1 while the hall setting is on, which lets the shader run the hallway's own timed
 * events; /bedroom hall on|off holds a choice in the store; /bedroom hall pass and hall light run one event at once.
 */
export const piece: Piece = {
  name: 'hallway',
  fields: ctx => ({ hall: ctx.setting('hall') ? 1 : 0 }),
  commands: {
    hall: async (ctx, args) => {
      const word = (args[0] ?? '').toLowerCase()
      if (word === 'pass' || word === 'light') return now(ctx, word)
      if (word !== 'on' && word !== 'off') {
        return `the hallway's events are ${ctx.setting('hall') ? 'on' : 'off'}. Say /bedroom hall on or off, hall pass or hall light to see one now, or hall default to follow the setting`
      }
      await ctx.save({ hall: word === 'on' })
      await ctx.send(`/bedroom hall ${word}`)
      return word === 'on'
        ? 'the hallway is on: about once an hour someone passes the door, and now and then the hall light comes on for three minutes'
        : 'the hallway is off: the light in the gap stays as it is'
    },
  },
}
