import type { Piece } from '../core/piece.js'

/** The hallway: the hall field is 1 while the hall setting is on, which lets the shader run the hallway's own timed events; /bedroom hall on|off holds a choice in the store. */
export const piece: Piece = {
  name: 'hallway',
  fields: ctx => ({ hall: ctx.setting('hall') ? 1 : 0 }),
  commands: {
    hall: async (ctx, args) => {
      const word = (args[0] ?? '').toLowerCase()
      if (word !== 'on' && word !== 'off') {
        return `the hallway's events are ${ctx.setting('hall') ? 'on' : 'off'}. Say /bedroom hall on or off, or hall default to follow the setting`
      }
      await ctx.save({ hall: word === 'on' })
      await ctx.send(`/bedroom hall ${word}`)
      return word === 'on'
        ? 'the hallway is on: about once an hour someone passes the door, and now and then the hall light comes on for three minutes'
        : 'the hallway is off: the light in the gap stays as it is'
    },
  },
}
