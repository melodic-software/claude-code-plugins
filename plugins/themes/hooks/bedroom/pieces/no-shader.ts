import type { Piece } from '../core/piece.js'

/**
 * The hand-drawn room when the shader setting is off: the row of the day and the weather the other pieces give, for the
 * scene parts to draw the window's sky. The core reads it only while the shader is off, and sends the room again
 * whenever the drawing changes.
 */
export const piece: Piece = {
  name: 'no-shader',
  room: ctx => {
    const { sun, weather } = ctx.fields()
    return { sun, weather }
  },
}
