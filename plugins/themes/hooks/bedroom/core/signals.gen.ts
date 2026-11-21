// @generated from the shader's signals and the build's set by its build script, with lights.ts. Do not edit by hand.
/** The values the shader reads, each with its range. */
export const VALUES = {"tv":[0,1],"lava":[0,1],"pc":[0,1],"lamp":[0,1],"light":[0,1],"clock":[0,719],"screen":[0,63],"world":[0,255]} as const
/** screen's fields: hurry, hall, then the tape's and the console's (bit + 2 * sequence bit), each at its unit. */
export const SCREEN = {"hurry":1,"hall":2,"tape":4,"console":16} as const
/** world = sun + sun * (weather + weather * (work + work * zone)); codes above top are never sent. */
export const WORLD = {"sun":8,"weather":5,"work":2,"zone":3,"top":239} as const
export const ACCEPT = {"move":0.05,"near":0.3,"start":6,"screen":0.5,"screenMany":3,"world":2.5} as const
export const HURRY = {"pace":0.1666,"seconds":30} as const
export const STRIKE = {"every":73,"shift":17,"modulo":101,"below":35,"beatEvery":29,"beatShift":5,"beatModulo":41,"beatBase":8} as const
/** The cues, each sent as world = top + id: one event the shader runs once, a hallway pass, the hall light, a strike. */
export const CUES = {"pass":1,"light":2,"strike":3} as const
/** The seconds after the shader starts in which it starts no event and takes no cue. */
export const EVENTS = {"after":30} as const
/** The pieces built in, from shader/pieces.json or --pieces. A piece reads these here, never from pieces/index.js. */
export const BUILT: readonly string[] = ["time","weather","claude-tv","hallway","sound","no-shader"]
/** The picture parts left out (piece.part). */
export const WITHOUT: readonly string[] = []
