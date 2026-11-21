// @generated from lights.glsl by glsl2dsl.mjs. Edit the .glsl, not this file.
// build: pieces=time,weather,claude-tv,hallway,sound,no-shader without=none
import { abs, buffer, clamp, cos, dot, dt, exp, first, floor, fract, length, max, min, mix, mod, picture, pointer, pointerCount, pointers, pow, shader, sin, size, smoothstep, sqrt, step, table, time, values, vec2, vec3, vec4, type Buffer, type Pixel } from 'claude-code/shader'

const v = values({ tv: [0, 1], lava: [0, 1], pc: [0, 1], lamp: [0, 1], light: [0, 1], clock: [0, 719], screen: [0, 63], world: [0, 255] })
const TAB_skyline = table([448.8,447,447.5,448.3,450.1,450.5,450.8,450.3,446.8,446.7,444,442.5,442.2,442,442.9,443,445.1,448.6,449.3,449.5,449.7,450.9,453.2,454.2,455,457.3,463.4,466,466.3,469.2,480.5,483,486.2,487.4,509.3,511.6,551,551.5,551.8,552,551.8,552.3,552.5,551.9,551.5,551.5,551.1,550.5,550.5,551.1,551.6,551.8,552.1,552.5,551.8,551.4,550.6,550.3,550.4,550.5,550.5,550.6,550.8,550.9,551.2,552,551.8,551.7,551.5,551.8,551.5,548.6,541.3,538.6,533.1,528.8,527.3,526,526.4,524.7,523.9,521,522.5,522.9,523.2,521.4,519.2,519.8,519.1,517.1,516.9,515,514.1,511.7,511.1,509.8,509.4,507.8,508.5,506.7,506.4,505.5,505.8,505.2,506.2,507,507,507])
const TAB_sides = table([[0,255],[107,255],[114,255],[117,255],[118,255],[135,255],[139,255],[143,255],[150,255],[152,255],[150,255],[154,255],[160,255],[160,255],[167,255],[170,255],[170,255],[169,255],[170,255],[170,255],[171,255],[174,255],[178,255],[179,255],[185,255],[184,255],[182,255],[182,255],[178,255],[177,255],[176,255],[178,255],[181,255],[181,122],[186,112],[189,103],[193,96],[193,92],[192,86],[191,78],[190,67],[189,46],[189,44],[183,30],[183,26],[183,23],[188,20],[187,21],[182,20],[178,17],[175,16],[171,10],[168,9],[167,11],[163,10],[161,5],[161,6],[155,5],[140,5],[136,6],[112,6],[86,2],[86,2],[86,3],[85,6],[85,8],[85,4]])
// The switches that change without sending the room again. The room under this is drawn with the television and
// the computer on, and the lava lamp and the desk lamp off. All positions are the room's own viewBox units.
// Television: tv runs from 1 (on) to 0 (off) on the mod shader's own clock (build-lights.mjs), quick going off.
// The picture collapses to a line and then a dot, the way a tube set does.
// Computer: off, its screen and power light go dark.
// Desk lamp: the lit mouth of its shade and the warm light it lays on the wall and the things beside it. It dips
// once part way through coming on, the way a bulb catches.
// With the ceiling light on, the room under this is the lit one: the television's light no longer darkens the room
// when it goes off, and the lava lamp's glow is weaker.
// VCR clock: the display drawn in the room is painted dark and the time drawn on it in seven-segment digits. clock is the minute of
// the half day, 0 to 719, as the mod reads it from the computer's local time; the colon blinks once a second.
// Lava lamp: the lit glass with its wax, and the purple light it lays on the wall, the dresser top and its own base.
function ell(p: vec2, c: vec2, r: vec2): number {
  return length((p - c) / r)
}
// 1 inside the box of center c and half size h, 0 outside, with a soft edge e wide either side.
function sbox(p: vec2, c: vec2, h: vec2, e: number): number {
  let d = vec2(abs(p - c) - h)
  return 1 - smoothstep(-e, e, max(d.x, d.y))
}
// The television's light on the room, k strong, its color following the screen: blue idle, green-gray tape,
// dim violet console (the tape wins over the console).
function tvl(tape: number, con: number, k: number): vec3 {
  let kc = con * (1 - tape)
  return vec3((vec3(0.165, 0.282, 0.91) + vec3(-0.065, -0.112, -0.79) * tape + vec3(-0.055, -0.202, -0.61) * kc) * k)
}
function eq(n: number, k: number): number {
  return 1 - step(0.5, abs(n - k))
}
// One bar of a digit, drawn on whole pixels so its edges are hard and every bar is the same thickness: px is the
// pixel, a and b the ends of its center line in the room's units, k the pixels a unit, t its thickness in pixels.
function bar(px: vec2, a: vec2, b: vec2, k: number, t: number): number {
  let lo = vec2(floor(a * k + 0.5) - vec2(floor(t * 0.5)))
  let hi = vec2(floor(b * k + 0.5) - vec2(floor(t * 0.5)) + vec2(t))
  return step(lo.x, px.x) * step(px.x, hi.x) * step(lo.y, px.y) * step(px.y, hi.y)
}
// One seven-segment digit 4.8 units wide and 8.8 tall.
function digit(px: vec2, n: number, k: number, t: number): number {
  let a = bar(px, vec2(1.8, 0.7), vec2(3, 0.7), k, t) * (1 - eq(n, 1)) * (1 - eq(n, 4))
  let b = bar(px, vec2(4.1, 1.8), vec2(4.1, 3.3), k, t) * (1 - eq(n, 5)) * (1 - eq(n, 6))
  let c = bar(px, vec2(4.1, 5.5), vec2(4.1, 7), k, t) * (1 - eq(n, 2))
  let d = bar(px, vec2(1.8, 8.1), vec2(3, 8.1), k, t) * (1 - eq(n, 1)) * (1 - eq(n, 4)) * (1 - eq(n, 7))
  let e = bar(px, vec2(0.7, 5.5), vec2(0.7, 7), k, t) * max(max(eq(n, 0), eq(n, 2)), max(eq(n, 6), eq(n, 8)))
  let f = bar(px, vec2(0.7, 1.8), vec2(0.7, 3.3), k, t) * (1 - eq(n, 1)) * (1 - eq(n, 2)) * (1 - eq(n, 3)) * (1 - eq(n, 7))
  let g = bar(px, vec2(1.8, 4.4), vec2(3, 4.4), k, t) * step(1.5, n) * (1 - eq(n, 7))
  return max(max(max(a, b), max(c, d)), max(max(e, f), g))
}
// Two hashes for the tape's city: one number, or one cell, to a fixed number from 0 to 1.
function thash(n: number): number {
  return fract(sin(n * 12.9898 + 4.1) * 43758.5453)
}
function thash2(q: vec2): number {
  return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453)
}
// A number from 0 to 1 for a cell, and smooth noise made of them.
function hsh(p: vec2): number {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453)
}
function vn(p: vec2): number {
  let i = vec2(floor(p))
  let f = vec2(fract(p))
  let u = vec2(f * f * (3 - 2 * f))
  let i10 = vec2(i + vec2(1, 0))
  let i01 = vec2(i + vec2(0, 1))
  let i11 = vec2(i + vec2(1, 1))
  return mix(mix(hsh(i), hsh(i10), u.x), mix(hsh(i01), hsh(i11), u.x), u.y)
}
// One layer of stars, at most one a cell of `cell` units, about `dens` of the cells lit. A star smaller than a
// pixel (px, in units) is drawn a pixel wide and dimmer, so it neither vanishes nor shimmers as it drifts.
function stars(p: vec2, cell: number, dens: number, rad: number, px: number): number {
  let id = vec2(floor(p / cell))
  let f = vec2(fract(p / cell))
  let h1 = hsh(id)
  let id2 = vec2(id + vec2(17.3, 5.1))
  let id3 = vec2(id + vec2(3.7, 9.2))
  let h2 = hsh(id2)
  let lit = step(1 - dens, hsh(id3))
  let o = vec2((f - vec2(0.25 + 0.5 * h1, 0.25 + 0.5 * h2)) * cell)
  let r = max(rad, px)
  let glint = 0.82 + 0.18 * sin(time * (0.4 + h2) + h1 * 40)
  return lit * (0.35 + 0.65 * h2 * h2) * exp(-dot(o, o) / (r * r)) * rad * rad / (r * r) * glint
}
// The window's glass, for the pieces that paint in it. win_clear is 0 on what stands in front of the
// window: the blind's cord and the monitor. The desk lamp's shade starts right of the glass, at x 507. win_pane is the
// upper sash's two panes, win_open the opening behind the insect screen, and win_sky 1 above the trees, the treeline and
// the field (a table taken from the room's own outlines), soft over 2
// units, and 0 on the utility pole.
function win_clear(p: vec2): number {
  let cord = sbox(p, vec2(466.7, 460), vec2(1.2, 130), 0.4)
  let monitor = sbox(p, vec2(280, 573), vec2(81, 71), 0.5)
  return (1 - cord) * (1 - monitor)
}
// The panes as window.ts draws them: above the upper sash's bottom rail (y 406.3 to 418.0) the glass shows through
// both sashes, between both muntins (x 389.8 to 399.8); below it, through the lower sash alone, from x 294.2 and
// beside its muntin only (x 389.8 to 395.7). One box and one bar, each moved at y 412, inside the rail.
function win_pane(p: vec2): number {
  let low = step(412, p.y)
  let c = vec2(mix(vec2(395.45, 369.9), vec2(392.75, 435.15), low))
  let h = vec2(mix(vec2(95.45, 35.9), vec2(98.15, 16.65), low))
  let bar = sbox(p, vec2(394.8 - 2.05 * low, 400), vec2(5.5 - 2.05 * low, 80), 0.5)
  return sbox(p, c, h, 0.5) * (1 - bar) * win_clear(p)
}
function win_open(p: vec2): number {
  return sbox(p, vec2(397.5, 523.6), vec2(106.1, 48.4), 0.5) * win_clear(p)
}
// The skyline's y at p.x: the top of whatever stands outside the window there.
function win_top(p: vec2): number {
  let q = clamp((p.x - 292) / 2, 0, 106)
  let i0 = floor(q)
  let ya = TAB_skyline.at(i0)
  let yb = TAB_skyline.at(i0 + 1)
  return mix(ya, yb, q - i0)
}
function win_sky(p: vec2, ys: number): number {
  let pole = sbox(p, vec2(424.4, 510), vec2(1.6, 74), 0.4)
  return smoothstep(-1, 1, ys - p.y) * (1 - pole)
}
// The land as the room draws it, for the day view: x the near trees, y the far treeline, z 1 on the sky, 0 on the land,
// the pole and its crossarm, w the pole and its crossarm. The near trees' tops are the skyline (top); their sides come
// from tables/sides.json (tools/window-geom.mjs), half units right of x 266 and of x 430. rn, a noise of 0 to 1,
// roughens each edge into leaves by about a unit either way; each edge is soft over about a unit, as the room's blur
// makes it.
function win_land(p: vec2, top: number, rn: number): vec4 {
  let e = 2.8 * (rn - 0.5)
  let near = 0
  if (abs(p.x - 397.0) > 32.0) {
    let qs = clamp((p.y - 440) * 0.5, 0, 65)
    let ks = floor(qs)
    let side = vec2(mix(TAB_sides.at(ks), TAB_sides.at(ks + 1), qs - ks) * 0.5 + vec2(266, 430))
    near = clamp(0.7 * (p.y - top + e) + 0.5, 0, 1) * clamp(0.7 * (max(side.x - p.x, p.x - side.y) + e) + 0.5, 0, 1)
  }
  let far = clamp(0.8 * (p.y - 551.6 + 0.7 * e) + 0.5, 0, 1)
  let pole = 0
  if (abs(p.x - 424.3) < 6.5) {
    pole = max(sbox(p, vec2(424.4, 510), vec2(1.25 + 0.0018 * (p.y - 436), 74), 0.35), sbox(p, vec2(424.25, 442.2), vec2(5.75, 0.6), 0.35))
  }
  return vec4(vec4(near, far, (1 - max(near, far)) * (1 - pole), pole))
}
// How much of the light a passer-by holds back at x, room units along the hall from where they are: none beyond 75
// units, all from -25 to 25, a smooth ramp between, so there is no edge to see.
function hw_hold(x: number): number {
  return smoothstep(-75, -25, x) * (1 - smoothstep(25, 75, x))
}
function pic(uv: vec2): vec4 {
  let now_light = state.at(vec2(6, 0)).x
  let s = max(size.x / 1600, size.y / 1000)
  let at = vec2(vec2(800 + (uv.x - 0.5) * size.x / s, 500 + (0.5 - uv.y) * size.y / s))
  // Computed dusk, laid first so every light below goes over it. Each point keeps m of its lit color and takes dc,
  // the dusk's own blue ambient; m rises down the wall, falls toward the camera on the floor, and is set by region for
  // the furniture. The bulb's output falls as v_light squared and glows warm part way. The television's halo is added
  // back, and the window's sky, the two screens and the power lights stay out of the darkening.
  let acc = vec4(vec4(0))
  // l_dusky scales the whole computed dusk; l_keep lowers what it keeps of the lit room (the time piece's lanes).
  let night = (1 - now_light * now_light) * state.at(vec2(12, 0)).x
  if (night > 0.001) {
  let glowing = now_light * (1 - now_light)
  let fade = night + 0.32 * glowing
  let fl = clamp((at.y - 815) * 0.03, 0, 1)
  let wf = glowing * fade
  let dc = vec3((vec3(0.02, 0.022, 0.043) + vec3(-0.008, -0.002, 0.016) * fl) * night + vec3(0.36, 0.2, 0.06) * wf)
  let m = 0.006 + 0.00039 * clamp(at.y, 101, 430) + 0.035 * step(at.y, 101) - 0.05 * fl - 0.0006 * clamp(at.y - 850, 0, 120)
  if (at.x < 560.0) {
  if (at.y < 625.0) {
  if (at.y < 184.0) {
  if (abs(at.x - 380.0) < 120.0 && at.y > 128.0) {
  m = 0.06
  }
  } else {
  if (at.x > 243.0 && at.x < 531.0 && at.y > 203.0) {
  m = 0.2
  if (at.y < 336.0 && abs(at.x - 388.0) < 116.0 && at.y > 237.0) {
  m = 0.17
  dc = vec3(dc + vec3(0.014, 0.02, 0.1) * night)
  }
  // The glass: the lit room already dims the sky behind it, so the dusk keeps most of the lit glass and adds a
  // little blue, more in the upper sash. Trees and ground keep their own dark, so no mask follows their outline.
  if (at.y > 335.0 && at.y < 590.0) {
  let pane = sbox(at, vec2(394, 393), vec2(94, 58), 0.5) * (1 - sbox(at, vec2(394, 393), vec2(6, 60), 0.5)) * (1 - sbox(at, vec2(394, 410.5), vec2(96, 5.5), 0.5))
  let open = sbox(at, vec2(398.5, 524), vec2(105.5, 48), 0.5)
  let gl = max(pane, open) * (1 - sbox(at, vec2(466.7, 460), vec2(1.2, 130), 0.4))
  let up = smoothstep(405, 452, at.y)
  let cc = vec3(mix(vec3(0, 0.01, 0.1) + vec3(0.05, 0.02, 0) * up, vec3(0, 0, 0.035) + vec3(0.03, 0.012, 0) * clamp((at.y - 505) / 40, 0, 1), open))
  // The glass keeps its dusk level at every l_keep, as the screens do: the night outside is the time piece's to paint.
  m = m + (mix(0.7 + 0.2 * up, 1, open) / max(state.at(vec2(12, 0)).y, 0.5) - m) * gl
  dc = vec3(mix(dc, cc * fade, gl))
  }
  }
  }
  } else {
  if (at.x > 186.0 && at.y < 900.0) {
  m = mix(m, 0.22, smoothstep(186, 194, at.x) * (1 - smoothstep(850, 895, at.y)))
  }
  }
  if (abs(at.x - 280.0) < 84.0 && abs(at.y - 573.0) < 75.0) {
  let mon = sbox(at, vec2(280, 573), vec2(81, 71), 1)
  m = mix(m, 0.24, mon)
  dc = vec3(mix(dc, vec3(0.02, 0.022, 0.043) * night, mon))
  let shown = max(sbox(at, vec2(270, 557), vec2(54.25, 39.25), 2.25), 1 - smoothstep(1, 2.6, length(at - vec2(318.4, 616))))
  // The screens and the power lights keep all of their lit color at every l_keep: m rises toward 1 / l_keep, so the
  // last line's m * l_keep reaches 1 there. At l_keep 1 this is the old m + (1 - m) * shown.
  let kq = 1 / max(state.at(vec2(12, 0)).y, 0.5)
  m = m + (kq - m) * shown
  dc = vec3(dc * (1 - shown))
  }
  if (abs(at.x - 430.0) < 102.0 && abs(at.y - 686.0) < 116.0) {
  let cd = vec2(abs(at - vec2(430, 686)) - vec2(74, 88))
  let ch = 1 - smoothstep(21, 26, length(max(cd, vec2(0))) + min(max(cd.x, cd.y), 0))
  m = mix(m, 0.36, ch)
  dc = vec3(mix(dc, vec3(0.012, 0.016, 0.042) * night, ch))
  }
  if (abs(at.x - 403.0) < 70.0 && abs(at.y - 850.0) < 5.0) {
  let led = max(1 - smoothstep(1, 2.2, length(at - vec2(460, 848))), 1 - smoothstep(1, 2.2, length(at - vec2(469.6, 848))))
  led = max(led, 1 - smoothstep(1, 2.2, length(at - vec2(337.3, 852)))) * state.at(vec2(2, 0)).x
  let kl = 1 / max(state.at(vec2(12, 0)).y, 0.5)
  m = m + (kl - m) * led
  dc = vec3(dc * (1 - led))
  }
  // The desk lamp, when on, shows the shade, the arm and the window trim beside it in their own warm light.
  if (at.x > 430.0 && abs(at.y - 600.0) < 96.0) {
  let lp = 0.5 * state.at(vec2(3, 0)).x * pow(clamp(1 - ell(at, vec2(506, 600), vec2(80, 96)), 0, 1), 1.1)
  m = m + (1 - m) * lp
  dc = vec3(dc * (1 - lp) + vec3(0.05, 0.025, 0) * (lp * night))
  }
  let vl = vec2((at - vec2(800, 500)) * vec2(0.00104, 0.00163))
  m = m * (1 - 0.6 * clamp(dot(vl, vl) - 0.3, 0, 0.75))
  }
  if (at.x > 955.0) {
  // The things the television lights keep more of their lit color (their own edges and grain) and take its light
  // (tvl), by v_tv, over a darker ambient than the wall's, vec3(0.0, 0.01, 0.035).
  if (at.x < 1425.0) {
  if (at.y < 616.0) {
  if (at.y < 356.0) {
  if (abs(at.x - 1260.0) < 128.0 && at.y > 170.0) {
  let pt = sbox(at, vec2(1183, 275), vec2(45, 67), 2) + sbox(at, vec2(1317, 259), vec2(65, 83), 2)
  m = mix(m, 0.1 + 0.02 * state.at(vec2(0, 0)).x, pt)
  dc = vec3(mix(dc, vec3(0, 0.01, 0.035) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x, night * 0.075 * state.at(vec2(0, 0)).x), pt))
  }
  } else {
  // The dresser's left side from its top down, and the front lip of its top, lit from the television.
  if (at.y > 590.0 && at.x > 1066.0 && at.x < 1402.0) {
  let sd = 1 - smoothstep(1108, 1112, at.x)
  let top = sbox(at, vec2(1256, 608), vec2(146, 8.5), 1)
  m = mix(mix(m, 0.14 + 0.05 * state.at(vec2(0, 0)).x, sd), 0.17 + 0.12 * state.at(vec2(0, 0)).x, top)
  dc = vec3(mix(dc, vec3(0, 0.01, 0.035) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x, night * 0.05 * state.at(vec2(0, 0)).x), sd))
  dc = vec3(mix(dc, vec3(0, 0.01, 0.035) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x, night * 0.1 * state.at(vec2(0, 0)).x), top))
  }
  if (at.x > 1111.5 - 0.075 * (at.y - 430.0) && at.x < 1296.0 && at.y > 421.0 && at.y < 597.0) {
  m = 0.23
  }
  if (abs(at.x - 1321.0) < 23.0 && at.y > 497.0 && at.y < 597.0) {
  m = 0.22
  }
  if (abs(at.x - 1232.0) < 60.0 && at.y < 432.0) {
  let cat = 1 - smoothstep(0.95, 1.05, min(ell(at, vec2(1231, 425), vec2(49, 44)), ell(at, vec2(1254, 388), vec2(20, 21))))
  m = mix(m, 0.07 + 0.05 * state.at(vec2(0, 0)).x, cat)
  }
  if (abs(at.x - 1411.75) < 12.0 && abs(at.y - 493.0) < 19.0) {
  let sw = sbox(at, vec2(1411.75, 493), vec2(10.75, 17.5), 0.7)
  m = mix(m, 0.12, sw)
  dc = vec3(dc + vec3(0, 0.005, 0.06) * (sw * night * state.at(vec2(0, 0)).x))
  }
  }
  if (at.y > 268.0) {
  let ea = vec2((at - vec2(1290, 477)) * vec2(0.00726, 0.00607))
  let eb = vec2((at - vec2(1215, 502)) * vec2(0.00347, 0.00427))
  let qa = clamp(1 - dot(ea, ea), 0, 1)
  let qb = clamp(1 - dot(eb, eb), 0, 1)
  let glow = (0.199 * qa * qa + 0.102 * qb * qb) * (1 - smoothstep(560, 616, at.y))
  glow = glow + 0.25 * clamp(1 - abs(at.x - 1208) / 110, 0, 1) * clamp(1 - abs(at.y - 604) / 8, 0, 1)
  glow = glow * (1 - 0.6 * step(1111.5 - 0.075 * (at.y - 430), at.x) * step(at.x, 1296) * step(421, at.y) * step(at.y, 597)) * state.at(vec2(0, 0)).x
  m = m * (1 - glow)
  dc = vec3(dc * (1 - glow) + tvl(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x, night * glow))
  }
  if (abs(at.x - 1207.5) < 76.0 && abs(at.y - 485.0) < 58.0) {
  let gd = vec2(abs(at - vec2(1207.5, 485)) - vec2(73, 55.5))
  let shown = 1 - smoothstep(-2, 1.5, max(gd.x, gd.y))
  let kt = 1 / max(state.at(vec2(12, 0)).y, 0.5)
  m = m + (kt - m) * shown
  dc = vec3(dc * (1 - shown))
  }
  } else {
  // The dresser's drawer faces, lit from the television above and less further down, and its left side.
  if (at.x > 1066.0 && at.x < 1402.0 && at.y < 905.0) {
  let dt = clamp((at.y - 612) / 256, 0, 1)
  let sd = 1 - smoothstep(1108, 1112, at.x)
  // The faces keep little of their lit orange and take a gray bounce off the screen, strongest on the top row, so
  // they read as the neutral dark gray of the hand-drawn dusk room (fitted to it on the three rows of drawers).
  let du = clamp(1 - dt * 2, 0, 1) * (1 - 0.3 * smoothstep(1200, 1340, at.x))
  let dw = 1 - dt
  let dg = (0.007 + 0.05 * dw * dw * (1 - 0.3 * smoothstep(1200, 1340, at.x))) * (1 - sd) * state.at(vec2(0, 0)).x * (1 - 0.6 * max(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x))
  m = 0.15 + state.at(vec2(0, 0)).x * mix(-0.008, 0.05, sd)
  dc = vec3((vec3(0, 0.004, 0.012) + vec3(0, 0.006, 0.023) * sd + vec3(dg)) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x, night * state.at(vec2(0, 0)).x * mix(0.01 + 0.085 * du * du, 0.05, sd)))
  }
  if (at.y > 900.0) {
  let ep = vec2((at - vec2(1230, 965)) * vec2(0.0042, 0.0143))
  let pool = clamp(1 - dot(ep, ep), 0, 1)
  pool = 0.12 * pool * pool * state.at(vec2(0, 0)).x
  m = m * (1 - pool)
  dc = vec3(dc * (1 - pool) + tvl(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x, night * pool))
  }
  }
  // The guitar leaning on the dresser: its headstock and neck along one slanted line, and its body.
  if (abs(at.x - 1082.0) < 40.0 && abs(at.y - 732.0) < 176.0) {
  let gx = abs(at.x - 1097 + 0.0914 * (at.y - 563))
  let gw = mix(8.5, 5, smoothstep(615, 630, at.y))
  let neck = (1 - smoothstep(gw - 1, gw + 1, gx)) * smoothstep(557, 561, at.y) * (1 - smoothstep(790, 800, at.y))
  let gq = vec2(abs(at - vec2(1083.5, 832)) - vec2(11.5, 52))
  let gh = vec2(abs(at - vec2(1071, 753)) - vec2(1, 16))
  let gb = min(length(max(gq, vec2(0))) + min(max(gq.x, gq.y), 0) - 18, length(max(gh, vec2(0))) + min(max(gh.x, gh.y), 0) - 8)
  let gm = max(neck, 1 - smoothstep(-1, 1, gb))
  m = mix(m, 0.15 + 0.16 * state.at(vec2(0, 0)).x, gm)
  dc = vec3(mix(dc, vec3(0, 0.004, 0.012) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x, night * 0.05 * state.at(vec2(0, 0)).x), gm))
  }
  } else {
  // The door: its panels kept, a little of the television's light, and a warm strip of hallway light in the gap.
  if (at.y > 198.0 && at.y < 850.0) {
  m = 0.33
  let el = vec2((at - vec2(1208, 485)) * 0.00179)
  let lq = clamp(1 - dot(el, el), 0, 1)
  dc = vec3(vec3(0, 0.012, 0.045) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(state.at(vec2(4, 0)).x, state.at(vec2(5, 0)).x, night * 0.13 * lq * lq * state.at(vec2(0, 0)).x))
  if (abs(at.x - 1460.5) < 12.0 && at.y > 234.0) {
  let hs = sbox(at, vec2(1460.5, 545), vec2(10.5, 311), 1)
  let wl = smoothstep(560, 760, at.y)
  m = mix(m, 0.12 + 0.12 * wl, hs)
  dc = vec3(mix(dc, vec3(0.004, 0.006, 0.014) * night + vec3(0.06, 0.035, 0.012) * (wl * night * (state.at(vec2(15, 0)).x * (1 - 0.6 * state.at(vec2(15, 0)).y) * (1 - 0.6 * state.at(vec2(11, 0)).y))) + vec3(0.36, 0.2, 0.06) * wf, hs))
let hw_src = 0
let hw_don = (state.at(vec2(15, 0)).x - 1) * 0.667 * night
let hw_go = step(0.0001, state.at(vec2(15, 0)).y)
let hw_b = (state.at(vec2(15, 0)).z - 0.5) * 625
let hw_h = 856 - at.y
let hw_low = 1 - smoothstep(0, 140, hw_h)
let hw_dim = hw_go * hw_hold((at.x - 1460.5) * 1.3 - hw_b) * (0.52 * mix(0.85, 1, smoothstep(0, 150, hw_h)) * (1 - smoothstep(380, 640, hw_h)) + 0.08 * hw_low * cos(hw_b * 0.06))
let hw_lead = 0.15 * hw_go * exp(-hw_b * hw_b / 30000)
let hw_cast = (1 - hs * hw_dim) * (1 - hs * hw_lead)
dc = vec3((dc + vec3(0.34, 0.22, 0.10) * (hw_don * hs * (1 - 0.6 * smoothstep(0, 1, abs((at.y - 234) / 622 - hw_src))))) * hw_cast)
let hw_edge = smoothstep(1469.6, 1470.6, at.x) * (1 - smoothstep(1470.8, 1472.4, at.x)) * smoothstep(250, 450, at.y)
dc = vec3(dc + vec3(0.07, 0.042, 0.015) * (hw_don * 1.5 * (1 - hw_dim) * (1 - hw_lead) * hw_edge))
  }
  }
  }
  // The hallway light through the gap, a faint warm wedge on the floor below it, fainter late at night.
  if (at.y > 850.0 && abs(at.x - 1450.0) < 60.0) {
  let fy = at.y - 850
  let wedge = clamp(1 - abs(at.x - 1460 + 0.5 * fy) / (6 + 0.4 * fy), 0, 1) * (1 - smoothstep(850, 915, at.y))
  dc = vec3(dc + vec3(0.045, 0.026, 0.008) * (wedge * night * (state.at(vec2(15, 0)).x * (1 - 0.6 * state.at(vec2(15, 0)).y) * (1 - 0.6 * state.at(vec2(11, 0)).y))))
let hw_fon = (state.at(vec2(15, 0)).x - 1) * 0.667 * night
let hw_fx = at.x - 1460 + 0.5 * fy
let hw_fw = 4 + 0.45 * fy
let hw_fgo = step(0.0001, state.at(vec2(15, 0)).y)
let hw_fb = (state.at(vec2(15, 0)).z - 0.5) * 625
let hw_flead = 1 - 0.15 * hw_fgo * exp(-hw_fb * hw_fb / 30000)
let hw_fdim = (1 - 0.47 * hw_fgo * hw_hold(hw_fx / hw_fw * 13.6 - hw_fb)) * hw_flead
dc = vec3(dc + vec3(0.17, 0.11, 0.045) * (hw_fon * clamp(1 - abs(hw_fx) / hw_fw, 0, 1) * (1 - smoothstep(860, 935, at.y)) * hw_fdim))
let hw_ux = at.x - 1478.6
let hw_uy = at.y - 860.2 + max(-0.42 * hw_ux, 0.057 * hw_ux)
let hw_under = smoothstep(-8.6, -6.6, hw_ux) * (1 - smoothstep(4, 30, hw_ux)) * (clamp(1 - abs(hw_uy) / 2.2, 0, 1) + 0.35 * smoothstep(-1, 1.5, hw_uy) * (1 - smoothstep(1.5, 10, hw_uy)))
let hw_udim = (1 - 0.47 * hw_fgo * hw_hold((at.x - 1460.5) * 1.3 - hw_fb)) * hw_flead
dc = vec3(dc + vec3(0.13, 0.078, 0.028) * (hw_fon * 1.5 * hw_udim * hw_under))
  }
  let vr = vec2((at - vec2(800, 500)) * vec2(0.00104, 0.00163))
  m = m * (1 - 0.6 * clamp(dot(vr, vr) - 0.3, 0, 0.75))
  }
  acc = vec4(vec4(dc, fade * (1 - m * state.at(vec2(12, 0)).y)))
  }
  // The things left of the room's middle, in one box (x up to 569, y 333.5 to 641) so the boxes inside it are tested
  // only there: each box test is work at every point it is asked.
  if (at.x < 569.0 && at.y > 333.5 && at.y < 641.0) {
  // The window: the glass and no more, for the pieces' snippets.
  if (abs(at.x - 397.5) < 106.6 && at.y > 333.5 && at.y < 573.0) {
  let w_pane = win_pane(at)
  let w_open = win_open(at)
  let w_top = win_top(at)
  let w_sky = win_sky(at, w_top)
  // By day the pieces paint from the room's own outlines: w_land (win_land), w_rn its leaf noise, and w_s, the sky by
  // those outlines, easing in with the daylight; at evening, night and predawn w_s is w_sky and the rest is unread.
  let w_land = vec4(vec4(0, 0, 1, 0))
  let w_rn = 0.5
  let w_d = clamp(4 * state.at(vec2(11, 0)).x, 0, 1)
  let w_s = w_sky
  if (w_d > 0.0) {
  if (at.y > 435.0) {
  w_rn = vn(vec2(at.x * 0.45 + at.y * 0.17, at.y * 0.47 - at.x * 0.15))
  w_land = vec4(win_land(at, w_top, w_rn))
  w_s = mix(w_sky, w_land.z, w_d)
  }
  }
let td_day = state.at(vec2(11, 0)).x
let td_late = state.at(vec2(11, 0)).y
let td_dawn = state.at(vec2(11, 0)).w
let td_warm = state.at(vec2(11, 0)).z
let td_clear = 1 - state.at(vec2(13, 0)).x
let td_open = max(w_open, sbox(at, vec2(358, 512), vec2(3.5, 10.5), 0.5) * clamp(at.x - 354.1 - 0.45 * (at.y - 505), 0, 1))
let td_v = clamp((at.y - 335) * 0.0045, 0, 1)
// The day sky, pale toward the horizon; lavender over peach at dawn; warm low down at golden hour.
let td_sky = vec3(mix(mix(vec3(0.33, 0.52, 0.81), vec3(0.72, 0.80, 0.87), td_v), mix(vec3(0.27, 0.33, 0.56), vec3(0.96, 0.72, 0.56), td_v), 0.85 * td_dawn))
td_sky = vec3(mix(td_sky, mix(vec3(0.42, 0.54, 0.76), vec3(1, 0.68, 0.40), td_v * td_v), 0.85 * td_warm))
// The night sky: deep blue, lighter toward the horizon and lavender there as dawn nears. It is laid thin high up, where
// the room's own stars twinkle through, and thick low down, where it covers the dusk's afterglow. The moon, high in the
// upper left pane with its halo, is hidden by cloud.
let td_m = vec2(at - vec2(322, 361))
let td_md = length(td_m)
let td_disk = (1 - smoothstep(4.2, 5, td_md)) * td_clear
let td_ns = vec3(mix(vec3(0.012, 0.022, 0.07), vec3(0.05, 0.065, 0.15) + vec3(0.16, 0.08, 0.12) * td_dawn, td_v * td_v) + vec3(0.19, 0.2, 0.26) * (exp(-td_md * td_md / 150) * td_clear))
td_ns = vec3(mix(td_ns, vec3(0.95, 0.94, 0.86) * (0.35 + 0.65 * smoothstep(3.6, 5.4, length(td_m + vec2(1.9, 0.8)))), td_disk))
let td_d = clamp(4 * td_day, 0, 1)
// The pole's two wires against the day sky: the curves the room draws from the crossarm's ends.
let td_wx = at.x - 424.25
let td_wy = 441.4 + mix(0.163 * td_wx - 0.00126 * td_wx * td_wx, -0.262 * td_wx - 0.0004 * td_wx * td_wx, step(td_wx, 0))
let td_wire = clamp(1 - (abs(at.y - td_wy) - 0.25) * 1.4 * s, 0, 1) * 0.8 * step(338, at.x) * td_d
let td_sc = vec3(mix(mix(td_ns, td_sky, td_d), vec3(0.16, 0.16, 0.17), td_wire))
// The land by day, in the room's outlines and layers (w_land): the far treeline darkening to its foot, the field below
// it, the near trees in front with clumps of leaves lit from above, and the pole in its own weathered wood; the leaf
// noise (w_rn) shades leaves, grass and treeline. At night it is the night's dark, the room's own yard light and
// fireflies showing faintly through.
let td_land = vec3(vec3(0.010, 0.013, 0.026))
if (td_d > 0.0 && at.y > 435.0) {
let td_nz = w_rn
let td_ld = vec3(mix(vec3(0.46, 0.55, 0.53) - vec3(0.008) * clamp(at.y - 548, 0, 14), vec3(0.40, 0.52, 0.23), smoothstep(560.5, 562.5, at.y)) * (0.86 + 0.28 * td_nz))
td_ld = vec3(mix(td_ld, vec3(0.06, 0.14, 0.04) + vec3(0.26, 0.32, 0.1) * td_nz * td_nz * (0.6 + 0.4 * clamp(1 - (at.y - w_top) * 0.015, 0, 1)), w_land.x))
td_ld = vec3(mix(td_ld, vec3(0.30, 0.26, 0.22) + vec3(0.09, 0.08, 0.06) * smoothstep(424.8, 423.4, at.x), w_land.w))
// The hour's light on the land: warm at golden hour, cool and dim at dawn. The open sash is seen through the insect screen.
td_ld = vec3(td_ld * mix(vec3(1), vec3(1.2, 0.93, 0.66), td_warm) * mix(vec3(1), vec3(0.74, 0.68, 0.80), td_dawn) * (1 - 0.28 * td_open))
td_land = vec3(mix(td_land, td_ld, td_d))
}
// One layer: by day the whole view, the land opaque from day 0.63; at night the sky, and the land in part.
let td_a = mix(max(min(1, 1.6 * td_day), 0.62 * td_late), max(min(1, 1.3 * td_day), td_late * max(0.35 + 0.57 * td_v, td_disk)), w_s) * (w_pane + td_open)
let td_col = vec3(mix(td_land, td_sc, w_s))
acc = vec4(vec4(acc.rgb * (1 - td_a) + td_col * td_a, acc.a * (1 - td_a) + td_a))
// More stars at night, in the upper panes clear of the moon: at most one a 9-unit cell, a tenth of the cells lit.
if (at.y < 453.0) {
let td_g = vec2(at / 9)
let td_h = hsh(floor(td_g)) - 0.9
let td_st = step(0, td_h) * clamp(1.4 - length(fract(td_g) - vec2(0.3 + 4 * td_h, 0.7 - 4 * td_h)) * 9 * s, 0, 1) * (0.3 + 6 * td_h) * (1 - 0.7 * td_v) * clamp((td_late - 0.6) * 2.5, 0, 1) * td_clear * w_s * w_pane * step(22, td_md)
acc = vec4(vec4(acc.rgb * (1 - td_st) + vec3(0.86, 0.88, 0.98) * td_st, acc.a * (1 - td_st) + td_st))
}
let wx_wet = state.at(vec2(13, 0)).y
let wx_storm = state.at(vec2(13, 0)).z
let wx_glass = w_pane + w_open
// The cloud: soft rolls drifting slowly, a dull gray by day, darker with rain and a storm. Late in the day it turns a dark
// blue-gray lit by the town below, never black: a little lighter than the wall round the window, so the glass still
// reads as sky and the land still stands dark against it; rain and a storm darken it less at night than by day. Behind
// it the moon is a soft glow with no disc (wx_mg), where the clear sky shows it.
let wx_n = 0.5 + 0.25 * sin(at.x * 0.045 + time * 0.03 + 2 * sin(at.y * 0.07)) + 0.25 * sin(at.y * 0.11 + at.x * 0.013 - time * 0.021)
let wx_cc = vec3(mix(mix(vec3(0.19, 0.17, 0.22), vec3(0.68, 0.70, 0.74), state.at(vec2(11, 0)).x), vec3(0.075, 0.085, 0.115), state.at(vec2(11, 0)).y) * (1 - (0.3 * wx_wet + 0.25 * wx_storm) * (1 - 0.5 * state.at(vec2(11, 0)).y)))
let wx_m = vec2(at - vec2(322, 361))
let wx_mg = exp(-dot(wx_m, wx_m) / 2500) * state.at(vec2(11, 0)).y * (1 - 0.6 * wx_wet)
let wx_cv = min(1, 1.3 * state.at(vec2(13, 0)).x) * mix(0.3 + 0.4 * wx_wet, 1, w_sky) * wx_glass
acc = vec4(vec4(acc.rgb * (1 - wx_cv) + (wx_cc * (0.85 + 0.26 * wx_n) + vec3(0.09, 0.09, 0.1) * wx_mg * w_sky) * wx_cv, acc.a * (1 - wx_cv) + wx_cv))
// Beads on the panes (the open sash has no glass): a grid of 7-unit cells whose columns slide down each at its own
// speed and wander a little side to side, a bead in some cells, each shown for its own share of its own cycle so they
// come and go at different times; more and larger as the rain grows. A bead shows the lighter sky below it upside down.
// The slide wraps every 256 cells and a cell's row is hashed modulo 256, so the pattern runs on unbroken.
let wx_c = floor(at.x / 7)
let wx_q = vec2(vec2(at.x + 1.4 * sin(at.y * 0.09 + wx_c * 2.1), at.y - mod((1.5 + 5 * fract(wx_c * 0.618)) * time, 1792)) / 7)
let wx_id = vec2(floor(wx_q))
let wx_h = hsh(vec2(wx_id.x, mod(wx_id.y, 256)))
let wx_o = vec2((fract(wx_q) - vec2(0.3 + 0.4 * fract(wx_h * 7.31), 0.3 + 0.4 * fract(wx_h * 3.17))) * 7)
let wx_r = (0.9 + 1.4 * fract(wx_h * 13.7)) * (0.7 + 0.5 * wx_wet)
let wx_bead = clamp((1 - dot(wx_o, wx_o) / (wx_r * wx_r)) * 2, 0, 1) * step(1 - 0.6 * wx_wet, wx_h) * step(fract(time * (0.04 + 0.07 * fract(wx_h * 5.1)) + wx_h * 9), 0.7) * 0.4 * wx_wet * w_pane
acc = vec4(vec4(acc.rgb * (1 - wx_bead) + (wx_cc * (1.9 - wx_o.y / wx_r) + vec3(0.07, 0.07, 0.09)) * wx_bead, acc.a * (1 - wx_bead) + wx_bead))
// Rain beyond the glass, drawn a pixel wide at any size, in 2.5-unit columns slanted by the storm's wind. Half the
// columns are slow and short (160 units a second, a sixth of each 60-unit run) and half fast and long (300 a second,
// nearly half the run). Rain shows a few of the slow ones; a downpour and a storm add the fast ones and more of both.
// Each column keeps its own speed whatever the weather, and the fall wraps every 3 s (8 and 15 runs), so a change of
// weather fades columns in and out and nothing jumps.
let wx_heavy = clamp((wx_wet - 0.6) * 2.5 + wx_storm, 0, 1)
let wx_u = (at.x - (0.1 + 0.36 * wx_storm) * at.y) / 2.5
let wx_hs = thash(floor(wx_u))
let wx_fast = step(0.5, wx_hs)
let wx_run = fract((at.y - mix(160, 300, wx_fast) * mod(time, 3)) / 60 + wx_hs * 5.3)
let wx_streak = clamp(1 + (0.3 - abs(fract(wx_u) - 0.2 - 0.6 * fract(wx_hs * 3.1)) * 2.5) * s, 0, 1) * clamp(min(wx_run, mix(0.17, 0.45, wx_fast) - wx_run) * 10, 0, 1) * step(fract(wx_hs * 9.7), mix(0.75 * wx_wet, 0.9 * wx_heavy, wx_fast)) * (0.22 * wx_wet + 0.08 * wx_heavy) * wx_glass
acc = vec4(vec4(acc.rgb * (1 - wx_streak) + (wx_cc * 1.5 + vec3(0.12, 0.13, 0.16)) * wx_streak, acc.a * (1 - wx_streak) + wx_streak))
// A strike whitens the sky in the panes; the trees, the field and the pole stand dark against it.
let wx_f = 0.4 * state.at(vec2(13, 0)).w * w_sky * wx_glass
acc = vec4(vec4(acc.rgb * (1 - wx_f) + vec3(0.75, 0.80, 0.95) * wx_f, acc.a * (1 - wx_f) + wx_f))
  }
  if (at.x < 345.0 && abs(at.y - 568.0) < 54.0) {
  let dark = 1 - state.at(vec2(2, 0)).x
  let m = vec2(abs(at - vec2(270, 557)) - vec2(56, 41))
  let screen = (1 - smoothstep(-4, 0.5, max(m.x, m.y))) * 0.78 * dark
  acc = vec4(vec4(acc.rgb * (1 - screen) + vec3(0.03, 0.035, 0.035) * screen, acc.a * (1 - screen) + screen))
  let led = (1 - smoothstep(0.6, 1, ell(at, vec2(319, 616), vec2(4.5, 4.5)))) * 0.85 * dark
  acc = vec4(vec4(acc.rgb * (1 - led) + vec3(0.05, 0.06, 0.05) * led, acc.a * (1 - led) + led))
  }
  if (abs(at.x - 524.0) < 45.0 && abs(at.y - 589.0) < 52.0) {
  let lit = state.at(vec2(3, 0)).x * (1 - 0.65 * step(0.4, state.at(vec2(3, 0)).x) * step(state.at(vec2(3, 0)).x, 0.6)) * state.at(vec2(12, 0)).z
  let w1 = 0.2 * pow(clamp(1 - ell(at, vec2(524, 593), vec2(38, 46)), 0, 1), 1.5) * lit
  acc = vec4(vec4(acc.rgb * (1 - w1) + vec3(1, 0.66, 0.4) * w1, acc.a * (1 - w1) + w1))
  let w2 = 0.26 * pow(clamp(1 - ell(at, vec2(521, 567), vec2(32, 26)), 0, 1), 1.5) * lit
  acc = vec4(vec4(acc.rgb * (1 - w2) + vec3(1, 0.69, 0.44) * w2, acc.a * (1 - w2) + w2))
  let q = vec2(at - vec2(519.6, 564))
  let turned = vec2(vec2(q.x * 0.755 + q.y * 0.656, q.y * 0.755 - q.x * 0.656))
  let ring = length(turned / vec2(15, 5.5))
  let mouth = (1 - smoothstep(0.7, 1, ring)) * 0.95 * lit
  acc = vec4(vec4(acc.rgb * (1 - mouth) + mix(vec3(1, 0.86, 0.62), vec3(0.98, 0.6, 0.28), clamp(ring * ring, 0, 1)) * mouth, acc.a * (1 - mouth) + mouth))
  let ledge = (1 - smoothstep(538, 552, at.x)) * smoothstep(526, 529, at.x) * smoothstep(626.5, 628, at.y) * (1 - smoothstep(633, 635, at.y)) * 0.45 * lit
  acc = vec4(vec4(acc.rgb * (1 - ledge) + vec3(1, 0.85, 0.65) * ledge, acc.a * (1 - ledge) + ledge))
  }
  }
  // The television, the lava lamp and the wall switch, the VCR clock and the console's light, in one box (x 1121 to
  // 1461, y 417 to 642) for the same reason.
  if (at.x > 1121.0 && at.x < 1461.0 && at.y > 417.0 && at.y < 642.0) {
  let c = vec2(at - vec2(1207.5, 485))
  // The television: its cover, and under it the tape and the console, gathered in tv and laid over the dusk.
  let tv = vec4(vec4(0))
  if (abs(c.x) < 82.0 && abs(c.y) < 60.0) {
  let d = vec2(abs(c) - vec2(73, 55.5))
  let glass = 1 - smoothstep(-2, 1.5, max(d.x, d.y))
  let p = 1 - state.at(vec2(0, 0)).x
  let squash = clamp(p * 2, 0, 1)
  let shrink = clamp(p * 2 - 1, 0, 1)
  let h = 57 * (1 - squash) * (1 - squash)
  let w = 75 * (1 - shrink)
  let band = (1 - smoothstep(h - 1, h + 1, abs(c.y))) * (1 - smoothstep(w - 1, w + 1, abs(c.x)))
  let a = glass * (1 - band) * 0.97
  let line = glass * exp(-c.y * c.y / 5) * (1 - smoothstep(w, w + 6, abs(c.x))) * 4 * p * (1 - p)
  tv = vec4(vec4(vec3(0.03, 0.035, 0.05) * a + vec3(0.75, 0.85, 1) * line, a))
  }
  // The console's picture, under the television-off cover: a green orb boots for two seconds, then deep space with
  // the game's title. The title is text in the room on a dark card (scene/parts/tv.ts); this paints the blue screen
  // over the card at every other time. Over what this paints, the room's own scan lines (each pixel darkened by the
  // share of it the 1.6-unit pattern covers, so they match the room's at any size) and breathing; over the console's
  // picture, a slow tracking band.
  // Tape: a night rooftop on a played tape, laid under the television's own cover so the tube collapse and the dark
  // glass still hide it. Opaque inside the rounded glass while the tape plays. Positions here are the picture's own,
  // tu: the glass center is 0, its top edge 1, x to the right and y up. The room's glass is 141 by 106 with corners of
  // 9 and a lip 3 wider round it with corners of 11 (scene/parts/tv.ts); the lip is lit blue there, so this covers it
  // too and paints it the dark green the tape's light would leave on it. It goes under acc, so the first picture laid
  // under wins: keep this before the console's picture, and lay that under acc too, so the tape wins over the console.
  if (max(abs(c.x) / 75.0, abs(c.y) / 57.5) < 1.0) {
  let tqx = max(abs(c.x) - 62.5, 0)
  let tqy = max(abs(c.y) - 45, 0)
  let tlip = sqrt(tqx * tqx + tqy * tqy) - 11
  let tk = state.at(vec2(4, 0)).x * (1 - smoothstep(-0.8, 0.4, tlip))
  let tb = 1.5 / (55.5 * s)
  let tu = vec2(vec2(c.x, -c.y) / 55.5)
  // The tracking band rolls down the picture once every 21 seconds and bends the lines it crosses.
  let troll = 1.35 - 2.7 * fract(time / 21)
  let ttr = exp(-(tu.y - troll) * (tu.y - troll) / 0.005)
  let tp = vec2(vec2(tu.x + 0.018 * ttr * sin(tu.y * 70), tu.y))
  // The camera drifts: the city slides against the figure, the far towers less, over minutes.
  let tdrift = 0.32 * sin(time * 0.011)
  let th = -0.3
  let tsk = clamp((tp.y - th) / 1.1, 0, 1)
  let tcol = vec3(mix(vec3(0.1, 0.22, 0.14), vec3(0.008, 0.024, 0.016), sqrt(tsk)))
  tcol = vec3(tcol + vec3(0.03, 0.06, 0.04) * (0.5 + 0.5 * sin(tp.x * 2.3 + tdrift * 0.4 + sin(tp.y * 6 + 1.3))) * tsk * (1 - tsk))
  // A hazy moon high on the left, behind cloud.
  let tmoon = ell(tp, vec2(-0.62 + tdrift * 0.15, 0.6), vec2(0.075, 0.075))
  tcol = vec3(tcol + vec3(0.42, 0.55, 0.45) * (1 - smoothstep(0.75, 1.1, tmoon)) * 0.4 + vec3(0.06, 0.1, 0.07) * exp(-tmoon * tmoon * 0.35))
  let tfx = tp.x + tdrift * 0.55 + 1
  let tfc = floor(tfx / 0.085)
  let tfr = thash(tfc)
  let tfh = th + 0.06 + 0.42 * tfr * tfr + 0.08 * thash(tfc + 17)
  let tfm = 1 - smoothstep(tfh - tb, tfh + tb, tp.y)
  let tfcol = vec3(mix(vec3(0.028, 0.065, 0.042), vec3(0.05, 0.11, 0.07), clamp((th + 0.12 - tp.y) / 0.3, 0, 1)))
  let tfwc = vec2(vec2(tfx / 0.017, tp.y / 0.024))
  let tfw = step(0.83, thash2(floor(tfwc))) * step(fract(tfwc.x), 0.6) * step(fract(tfwc.y), 0.55) * step(tp.y, tfh - 0.03)
  tcol = vec3(mix(tcol, tfcol + vec3(0.16, 0.27, 0.15) * tfw * (0.4 + 0.6 * thash(tfc + 5)), tfm))
  let tnx = tp.x + tdrift + 2
  let tnc = floor(tnx / 0.23)
  let tnr = thash(tnc + 41)
  let tnh = th + 0.02 + 0.7 * tnr * tnr
  let tns = abs(fract(tnx / 0.23) - 0.5) * 0.23
  let tnw = 0.075 + 0.035 * thash(tnc + 9)
  let tnin = 1 - smoothstep(tnw - tb, tnw + tb, tns)
  let tntop = tnh - 0.05 * smoothstep(tnw * 0.6 - tb, tnw * 0.6 + tb, tns) * step(0.4, tnr)
  let tnant = (1 - smoothstep(0.004, 0.004 + tb, tns)) * step(tp.y, tnh + 0.16) * step(0.72, tnr)
  let tnm = max(tnin * (1 - smoothstep(tntop - tb, tntop + tb, tp.y)), tnant)
  let tnwc = vec2(vec2(tnx / 0.028, tp.y / 0.036))
  let tnl = step(0.74, thash2(floor(tnwc))) * step(fract(tnwc.x), 0.55) * step(fract(tnwc.y), 0.5) * step(tp.y, tntop - 0.03) * step(tns, tnw - 0.012)
  let tnwk = vec2(floor(tnwc) + vec2(3, 7))
  let tnwin = vec3(mix(vec3(0.3, 0.55, 0.32), vec3(0.62, 0.78, 0.45), thash2(tnwk)))
  let tncol = vec3(vec3(0.01, 0.022, 0.016) + vec3(0.025, 0.06, 0.04) * exp(min(tp.y - tntop, 0) * 14) * tnin * (1 - tnant) + tnwin * tnl)
  tcol = vec3(mix(tcol, tncol, tnm))
  // A warning light on the tall towers' masts, pulsing slowly.
  let tnlt = vec2(vec2(tns, tp.y - tnh - 0.16))
  tcol = vec3(tcol + vec3(0.75, 0.22, 0.14) * exp(-dot(tnlt, tnlt) / 0.00012) * step(0.72, tnr) * (0.45 + 0.55 * sin(time * 1.6 + tnc * 2)))
  // The parapet, its wet coping catching the city's light, and the wet roof in front of it.
  tcol = vec3(mix(tcol, vec3(0.012, 0.022, 0.017), 1 - smoothstep(th - tb, th + tb, tp.y)))
  let tcop = (tp.y - th + 0.007) / 0.009
  tcol = vec3(tcol + vec3(0.11, 0.24, 0.15) * exp(-tcop * tcop) * (0.7 + 0.3 * sin(tp.x * 5 + 1)))
  let troof = 1 - smoothstep(th - 0.08 - tb, th - 0.08 + tb, tp.y)
  let tdep = clamp((th - 0.08 - tp.y) / 0.62, 0, 1)
  let trf = vec3(vec3(0.014, 0.03, 0.021) + vec3(0.07, 0.16, 0.1) * exp(-tdep * 2.6))
  // Each near tower and its lit windows smear down the wet roof as a soft rippled streak.
  let tst = (1 - smoothstep(tnw * 0.3, tnw * 1.1, tns)) * (0.2 + 0.8 * thash(tnc + 5)) * (0.35 + 0.65 * exp(-tdep * 2.2))
  let trip = 0.7 + 0.3 * sin(tp.y * 95 + 3 * sin(tp.x * 11) + time * 0.6)
  let tpud = 1 - smoothstep(0.4, 1, ell(tp, vec2(-0.25, -0.72), vec2(0.6, 0.16)))
  trf = vec3(trf + vec3(0.1, 0.2, 0.12) * tst * trip * (0.35 + 0.65 * tpud) + vec3(0.025, 0.06, 0.04) * tpud)
  let trefl = (1 - smoothstep(0.09, 0.17, abs(tp.x - 0.4))) * smoothstep(-1.1, -0.8, tp.y) * (1 - smoothstep(-0.81, -0.79, tp.y))
  trf = vec3(trf * (1 - 0.7 * trefl))
  tcol = vec3(mix(tcol, trf, troof))
  // The figure in the long coat, seen from behind, its hem moving a little in the wind.
  let tsway = 0.5 + 0.5 * sin(time * 0.33)
  let tlow = clamp((0.05 - tp.y) / 0.65, 0, 1)
  let tgx = tp.x - 0.4 + 0.02 * tlow * tlow * tsway
  let thalf = 0.135 + 0.06 * tlow + 0.008 * tlow * tsway
  let tdc = max(abs(tgx) - thalf, max(tp.y - 0.05, -0.6 - tp.y))
  let tdsh = (ell(tp, vec2(0.4, 0.05), vec2(0.15, 0.065)) - 1) * 0.06
  let tdcl = max(abs(tp.x - 0.4) - 0.05, abs(tp.y - 0.13) - 0.04)
  let tdhd = (ell(tp, vec2(0.4, 0.215), vec2(0.052, 0.066)) - 1) * 0.05
  let tdlg = max(abs(abs(tp.x - 0.396) - 0.05) - 0.026, max(tp.y + 0.57, -0.8 - tp.y))
  let tdf = min(min(min(tdc, tdsh), min(tdcl, tdhd)), tdlg)
  let tfg = 1 - smoothstep(-tb, tb, tdf)
  let tside = clamp(0.5 - (tp.x - 0.4) * 6, 0, 1)
  let tedge = smoothstep(-0.016, -0.002, tdf) * (0.15 + 0.85 * tside) * smoothstep(-0.7, 0.1, tp.y)
  tcol = vec3(mix(tcol, vec3(0.005, 0.011, 0.008) + vec3(0.16, 0.36, 0.22) * tedge, tfg))
  // Tape: the band's haze and grain, the green cast, a raised black, then the play triangle, the scan lines and the
  // dark corners of the tube.
  tcol = vec3(tcol + vec3(0.05, 0.07, 0.06) * ttr + vec3(0.06, 0.08, 0.07) * ttr * thash2(floor(vec2(tp.x * 70, tu.y * 40))))
  tcol = vec3(tcol * vec3(1.15, 1.4, 1.2) + vec3(0.01, 0.018, 0.014))
  let tpl = vec2(tu - vec2(-1.07, 0.71))
  let tpm = 1 - smoothstep(-tb, tb, max(-tpl.x, abs(tpl.y) + tpl.x * 0.6 - 0.045))
  tcol = vec3(mix(tcol, vec3(0.82, 0.92, 0.86), tpm * 0.9))
  let tscan = 0.8 + 0.2 * cos(uv.y * size.y * 2.0944)
  let tvig = 1 - 0.35 * pow(clamp(length(tu * vec2(0.72, 0.95)), 0, 1.4), 2.6)
  tcol = vec3(tcol * tscan * tvig)
  tcol = vec3(mix(tcol, vec3(0.035, 0.055, 0.05), smoothstep(-0.5, 0.5, tlip + 3)))
  tv = vec4(vec4(tv.rgb + tcol * tk * (1 - tv.a), tv.a + tk * (1 - tv.a)))
  }
  if (abs(at.x - 1207.5) < 86.0) {
  if (abs(at.y - 485.0) < 68.0) {
  let con = vec4(vec4(0))
  let k_e = vec2(abs(c) - vec2(61.5, 44))
  let k_sd = length(max(k_e, vec2(0))) + min(max(k_e.x, k_e.y), 0) - 9
  let k_gm = 1 - smoothstep(-0.7, 0.5, k_sd)
  let k_ce = vec2(abs(at - vec2(1208, 480)) - vec2(44, 8))
  let k_on = clamp(state.at(vec2(5, 0)).x * (1 - state.at(vec2(4, 0)).x), 0, 1)
  let k_w = k_on * k_gm
  let k_t = state.at(vec2(5, 1)).x
  let k_pic = vec3(vec3(0))
  if (k_w > 0.001) {
  let k_fade = smoothstep(1.7, 2.6, k_t)
  let k_vig = 1 - 0.6 * smoothstep(0.78, 1.05, length(c / vec2(72, 55)))
  if (k_fade < 1.0) {
  let k_o = vec2(at - vec2(1207.5, 482))
  let k_after = max(k_t - 0.8, 0)
  let k_beat = 0.1 * sin(k_after * 5) * exp(-k_after * 1.8) * step(0.8, k_t)
  let k_r = (3 + 17 * smoothstep(0, 0.9, k_t)) * (1 + k_beat)
  let k_u = vec2(k_o / k_r)
  let k_d = length(k_u)
  let k_f1 = sin(k_u.x * 6 + 1.8 * sin(k_u.y * 4.5 + k_t * 2) + k_t * 1.2)
  let k_f2 = sin(k_u.y * 5.5 - 1.6 * sin(k_u.x * 4 - k_t * 1.6) - k_t * 0.8)
  let k_pl = 0.5 + 0.5 * k_f1 * k_f2
  let k_core = exp(-k_d * k_d * 2.2)
  let k_body = exp(-k_d * k_d * 0.9) * (0.45 + 0.55 * k_pl)
  let k_edge = exp(-(k_d - 0.92) * (k_d - 0.92) * 28) * 0.45
  let k_halo = exp(-k_d * 1.3) * 0.5
  let k_lum = smoothstep(0, 0.45, k_t) * (1 + 2.5 * k_beat)
  let k_boot = vec3(vec3(0.006, 0.018, 0.01) * k_vig + (vec3(0.08, 0.42, 0.1) * k_halo + vec3(0.2, 0.9, 0.25) * k_body + vec3(0.55, 1, 0.5) * k_edge + vec3(0.85, 1, 0.72) * k_core * 0.7) * k_lum)
  k_pic = vec3(min(k_boot, vec3(1)) * (1 - k_fade))
  }
  if (k_fade > 0.0) {
  let k_out = length(max(k_ce, vec2(0)))
  let k_mid = exp(-k_out * k_out / 160)
  let k_clr = smoothstep(1.5, 5, k_out)
  let k_sp = vec3(mix(vec3(0.006, 0.008, 0.024), vec3(0.043, 0.075, 0.212), k_mid))
  let k_nl = at.y - 512 + 0.18 * (at.x - 1207.5)
  let k_nb = exp(-k_nl * k_nl / 220)
  let k_nq = vec2(at + vec2(time * 0.22, 0))
  let k_n1 = vec2(k_nq * 0.055)
  let k_n2 = vec2(k_nq * 0.12 + vec2(5.2, 1.3))
  let k_n = vn(k_n1) * 0.65 + vn(k_n2) * 0.35
  let k_nc = vec3(mix(vec3(0.42, 0.14, 0.52), vec3(0.1, 0.32, 0.48), 0.5 + 0.5 * sin(k_nq.x * 0.045 + k_nq.y * 0.07)))
  k_sp = vec3(k_sp + k_nc * k_nb * (smoothstep(0.3, 0.85, k_n) * 0.7 + 0.1) * (1 - k_mid))
  let k_go = vec2(at - vec2(1246, 451))
  let k_gr = vec2(vec2(k_go.x * 0.906 + k_go.y * 0.423, k_go.y * 0.906 - k_go.x * 0.423))
  let k_ge = length(k_gr / vec2(15, 4.6))
  let k_lane = 1 - 0.45 * exp(-(k_gr.y + 0.9) * (k_gr.y + 0.9) * 1.5) * (1 - smoothstep(4, 13, abs(k_gr.x)))
  let k_gx = (exp(-k_ge * k_ge * 10) * 0.75 + exp(-k_ge * 2.6) * 0.32 * (0.8 + 0.2 * sin(k_gr.x * 0.9 - k_gr.y * 2))) * k_lane
  k_sp = vec3(k_sp + mix(vec3(0.5, 0.6, 1), vec3(1, 0.92, 0.8), exp(-k_ge * k_ge * 4)) * k_gx)
  let k_px = 0.75 / s
  let k_p1 = vec2(at + vec2(time * 0.35, 0))
  let k_p2 = vec2(at + vec2(time * 0.8 + 31, 7))
  let k_p3 = vec2(at + vec2(time * 1.6 + 57, 3))
  let k_st = stars(k_p1, 4.5, 0.32, 0.28, k_px) * 0.55
  k_st = k_st + stars(k_p2, 9, 0.3, 0.4, k_px) * 0.8
  k_st = k_st + stars(k_p3, 17, 0.35, 0.55, k_px)
  k_sp = vec3(k_sp + vec3(0.85, 0.9, 1) * k_st * 1.4 * k_clr * (1 - 0.75 * k_mid))
  k_pic = vec3(k_pic + k_sp * k_vig * k_fade)
  }
  let k_h = vec2(at - vec2(1176, 452))
  let k_ht = length(vec2(k_h.x * 0.97 - k_h.y * 0.242, k_h.x * 0.242 + k_h.y * 0.97) / vec2(46, 22))
  k_pic = vec3(mix(k_pic, vec3(0.91, 0.93, 1), 0.12 * clamp(1 - k_ht, 0, 1)))
  }
  con = vec4(vec4(k_pic * k_w, k_w))
  // The blue over the title's card fades out over 12 units round it and carries the glass's soft highlight, so the
  // patch shows no edge on the idle screen.
  if (abs(at.y - 480.0) < 21.0) {
  let k_cd = max(k_ce.x, k_ce.y)
  let k_m = 1 - smoothstep(0.8, 12, length(max(k_ce, vec2(0))))
  let k_mh = 1 - smoothstep(-2.2, -0.8, k_cd)
  let k_gt = length((at - vec2(1207.5, 480.76)) / vec2(101.52, 76.32))
  let k_cb = vec3(mix(mix(vec3(0.259, 0.392, 0.957), vec3(0.196, 0.325, 0.918), clamp(k_gt / 0.35, 0, 1)), vec3(0.133, 0.22, 0.761), clamp((k_gt - 0.35) / 0.33, 0, 1)))
  let k_bh = vec2(at - vec2(1176, 452))
  let k_bt = length(vec2(k_bh.x * 0.97 - k_bh.y * 0.242, k_bh.x * 0.242 + k_bh.y * 0.97) / vec2(46, 22))
  k_cb = vec3(mix(k_cb, vec3(0.91, 0.93, 1), 0.12 * clamp(1 - k_bt, 0, 1)))
  k_cb = vec3(k_cb * 0.81 + vec3(0.2, 0.329, 0.949) * 0.19 + vec3(0.0064, 0.0078, 0.013))
  con = vec4(vec4(con.rgb + k_cb * k_m * (1 - k_w), con.a + k_m * (1 - k_w)))
  let k_hole = k_mh * k_on * state.at(vec2(0, 0)).x * smoothstep(2.6, 3.6, k_t)
  con = vec4(con * (1 - k_hole) + vec4(0, 0, 0, 0.15 * k_hole))
  }
  if (abs(c.y) < 56.0) {
  if (con.a > 0.001) {
  let k_y0 = (at.y - 0.5 / s) / 1.6
  let k_y1 = (at.y + 0.5 / s) / 1.6
  let k_cv = (floor(k_y1) * 0.7 + min(fract(k_y1) * 1.6, 0.7) - floor(k_y0) * 0.7 - min(fract(k_y0) * 1.6, 0.7)) * s
  let k_sa = 0.025 + 0.312 * k_cv
  con = vec4(vec4(con.rgb * (1 - k_sa) + vec3(0, 0.023, 0.07) * k_sa * con.a, con.a))
  }
  }
  let k_ty = 417 + 138 * clamp((mod(time, 24) / 24 - 0.4) / 0.22, 0, 1)
  if (abs(at.y - k_ty) < 11.0) {
  let k_s1 = (at.y - k_ty + 4) / 0.5
  let k_band = k_w * (0.21 * (1 - abs(at.y - k_ty) / 11) + 0.12 * exp(-k_s1 * k_s1) * smoothstep(0.2, 0.8, sin(at.x * 0.11 + 1.7) * sin(at.x * 0.037 + 0.4)))
  con = vec4(vec4(vec3(0.847, 0.878, 1) * k_band + con.rgb * (1 - k_band), k_band + con.a * (1 - k_band)))
  }
  let k_lo = k_on * state.at(vec2(0, 0)).x * (1 - k_gm)
  if (k_lo > 0.001) {
  let k_le = vec2(abs(c) - vec2(63, 45.5))
  let k_ls = length(max(k_le, vec2(0))) + min(max(k_le.x, k_le.y), 0) - 12
  let k_in = 1 - smoothstep(-0.5, 0.5, k_ls)
  let k_lf = clamp(1 - k_ls / 9, 0, 1)
  let k_lip = k_lo * (0.9 * k_in + 0.3 * k_lf * k_lf * (1 - k_in))
  let k_lc = vec3(mix(vec3(0.17, 0.17, 0.19), vec3(0.05, 0.055, 0.095), k_in))
  con = vec4(vec4(k_lc * k_lip + con.rgb * (1 - k_lip), k_lip + con.a * (1 - k_lip)))
  }
  // Under everything already laid: the television's cover, and the tape's picture, which wins over the console.
  tv = vec4(vec4(tv.rgb + con.rgb * (1 - tv.a), tv.a + con.a * (1 - tv.a)))
  }
  }
  if (abs(c.x) < 86.0 && abs(c.y) < 68.0) {
  acc = vec4(vec4(acc.rgb * (1 - tv.a) + tv.rgb, acc.a * (1 - tv.a) + tv.a))
// While Claude works, a black layer of 2.5 to 5% that drifts with two slow waves: the screen only darkens, softly.
let ct_d = vec2(abs(c) - vec2(73, 55.5))
let ct_glass = (1 - smoothstep(-2, 1.5, max(ct_d.x, ct_d.y))) * state.at(vec2(0, 0)).x
let ct_a = ct_glass * state.at(vec2(14, 0)).x * (0.025 + 0.0125 * (1 + sin(time * 2.9) * sin(time * 1.7 + 1.3)))
acc = vec4(vec4(acc.rgb * (1 - ct_a), acc.a * (1 - ct_a) + ct_a))
// As the context fills, a second soft band rolls down the glass once every 13 s, streaked along its length, at up to 8%.
// It is off the glass at the turn of its 13 s (y 70 units from the center), so it never jumps in view.
let ct_dy = c.y + 70 - 140 * fract(time / 13)
let ct_streak = 0.55 + 0.45 * sin(at.x * 0.13 + time * 0.7) * sin(at.x * 0.047 + 1.3)
let ct_b = ct_glass * state.at(vec2(14, 0)).y * 0.08 * exp(-ct_dy * ct_dy / 40) * ct_streak
acc = vec4(vec4(acc.rgb * (1 - ct_b) + vec3(0.82, 0.86, 0.96) * ct_b, acc.a * (1 - ct_b) + ct_b))
  }
  if (abs(at.x - 1376.0) < 85.0 && abs(at.y - 530.0) < 112.0) {
  // l_glowDim lowers the lava lamp's and the desk lamp's light by day.
  let on = state.at(vec2(1, 0)).x * (1 - 0.55 * now_light) * state.at(vec2(12, 0)).z
  let wall = 1 - smoothstep(604, 608, at.y)
  let shelf = 1 - 0.75 * (1 - smoothstep(1343, 1349, at.x)) * smoothstep(486, 492, at.y)
  let stand = mix(8.8, 14.5, clamp((at.y - 557) / 43, 0, 1))
  let body = (1 - smoothstep(stand - 1, stand, abs(at.x - 1376))) * smoothstep(556, 557.5, at.y)
  wall = wall * (1 - 0.85 * body)
  let far = clamp(1 - ell(at, vec2(1376, 530), vec2(82, 110)), 0, 1)
  let g1 = 0.34 * pow(far, 1.25) * wall * shelf * on
  acc = vec4(vec4(acc.rgb * (1 - g1) + vec3(0.58, 0.25, 0.94) * g1, acc.a * (1 - g1) + g1))
  let near = clamp(1 - ell(at, vec2(1376, 536), vec2(30, 56)), 0, 1)
  let g2 = 0.2 * pow(near, 1.4) * wall * shelf * on
  acc = vec4(vec4(acc.rgb * (1 - g2) + vec3(0.706, 0.408, 1) * g2, acc.a * (1 - g2) + g2))
  let top = clamp(1 - ell(at, vec2(1376, 604), vec2(50, 50)), 0, 1)
  let g3 = 0.12 * pow(top, 1.5) * smoothstep(592, 596, at.y) * (1 - smoothstep(604, 607, at.y)) * (1 - smoothstep(1392, 1402, at.x)) * (1 - body) * on
  acc = vec4(vec4(acc.rgb * (1 - g3) + vec3(0.627, 0.314, 0.941) * g3, acc.a * (1 - g3) + g3))
  let g4 = 0.26 * body * (1 - smoothstep(557, 571, at.y)) * on
  acc = vec4(vec4(acc.rgb * (1 - g4) + vec3(0.627, 0.314, 0.941) * g4, acc.a * (1 - g4) + g4))
  // The glass and its wax paint only inside x 1376 +- 12.2 and y 493.6 to 555.4.
  if (abs(at.x - 1376.0) < 13.0 && at.y > 493.0 && at.y < 556.0) {
  let low = clamp((at.y - 537) / 18, 0, 1)
  let girth = mix(5.4, 11.8, smoothstep(-0.25, 1, (at.y - 494) / 43)) - 4.4 * low * low
  let inside = (1 - smoothstep(girth - 0.8, girth + 0.4, abs(at.x - 1376))) * smoothstep(493.6, 494.6, at.y) * (1 - smoothstep(554.4, 555.4, at.y))
  let depth = clamp((at.y - 494) / 61, 0, 1)
  let liquid = vec3(mix(mix(vec3(0.227, 0.078, 0.408), vec3(0.416, 0.157, 0.722), clamp(depth / 0.6, 0, 1)), vec3(0.635, 0.306, 0.941), clamp((depth - 0.6) / 0.4, 0, 1)))
  let y1 = 539.5 - 20 * (1 - cos(time * 0.083))
  let y2 = 512 + 17 * (1 - cos(time * 0.067))
  let y3 = 521 - 11 * (1 - cos(time * 0.1))
  let wax = 1 - smoothstep(0.75, 1.1, ell(at, vec2(1374, y1), vec2(5, 8.5)))
  wax = max(wax, 1 - smoothstep(0.75, 1.1, ell(at, vec2(1379, y2), vec2(4, 5.2))))
  wax = max(wax, 1 - smoothstep(0.7, 1.1, ell(at, vec2(1372, y3), vec2(2.3, 3.2))))
  wax = max(wax, 1 - smoothstep(0.8, 1.05, ell(at, vec2(1376, 556), vec2(10, 7))))
  wax = max(wax, 1 - smoothstep(0.8, 1.05, ell(at, vec2(1376, 496.5), vec2(5.5, 2.8))))
  let lamp = vec3(mix(liquid, vec3(0.9, 0.62, 1), wax * 0.92))
  lamp = vec3(lamp * (0.9 + 0.25 * (1 - smoothstep(0, girth, abs(at.x - 1373.5)))))
  lamp = vec3(lamp + vec3(0.88, 0.63, 1) * 0.16 * clamp(1 - ell(at, vec2(1376, 540), vec2(9, 40)), 0, 1))
  let rim = smoothstep(553.2, 553.8, at.y) * (1 - smoothstep(554.6, 555.2, at.y))
  lamp = vec3(mix(lamp, vec3(0.75, 0.44, 1), rim * 0.55))
  let g5 = inside * on
  acc = vec4(vec4(acc.rgb * (1 - g5) + lamp * g5, acc.a * (1 - g5) + g5))
  }
  let bloom = 0.24 * exp(-2.2 * ell(at, vec2(1376, 528), vec2(15, 32)) * ell(at, vec2(1376, 528), vec2(15, 32))) * wall * on
  acc = vec4(vec4(acc.rgb * (1 - bloom) + vec3(0.66, 0.36, 1) * bloom, acc.a * (1 - bloom) + bloom))
  // The wall switch's toggle, inside this block's box: the room under the shader draws it up (the ceiling light on).
  // Once the light is under half on it snaps down: the plate and the slot cover where it stood, and it stands below.
  let swl = sbox(at, vec2(1411.8, 497), vec2(1.3, 3.5), 0.3)
  let swp = max(sbox(at, vec2(1411.8, 489), vec2(1.6, 3.8), 0.3), swl) * (1 - step(0.5, now_light))
  let swc = vec3(mix(mix(vec3(0.082, 0.09, 0.188), vec3(0.047, 0.059, 0.153), step(488.4, at.y)), vec3(0.15, 0.16, 0.27) - vec3(0.08) * smoothstep(494, 500.5, at.y), swl))
  acc = vec4(vec4(acc.rgb * (1 - swp) + swc * swp, acc.a * (1 - swp) + swp))
  }
  if (max(abs(at.x - 1227.0) / 16.0, abs(at.y - 591.5) / 7.0) < 1.0) {
  let r = vec2(abs(at - vec2(1227, 591.5)) - vec2(13.8, 5.4))
  let face = 1 - smoothstep(-0.4, 0.4, max(r.x, r.y))
  acc = vec4(vec4(acc.rgb * (1 - face) + vec3(0.016, 0.024, 0.039) * face, acc.a * (1 - face) + face))
  let mins = floor(state.at(vec2(8, 0)).x + 0.5)
  let hour = floor(mins / 60)
  let minute = mins - hour * 60
  hour = hour + 12 * (1 - step(0.5, hour))
  let px = vec2(floor((at - vec2(1215, 587.1)) * s) + vec2(0.5))
  let thick = max(1, floor(s * 1.3 + 0.5))
  let tens = floor(hour / 10)
  let ink = digit(px, tens, s, thick) * step(0.5, tens)
  let pu = vec2(px - vec2(floor(6 * s + 0.5), 0))
  ink = max(ink, digit(pu, hour - tens * 10, s, thick))
  let mt = floor(minute / 10)
  let pv = vec2(px - vec2(floor(13.2 * s + 0.5), 0))
  ink = max(ink, digit(pv, mt, s, thick))
  let pw = vec2(px - vec2(floor(19.2 * s + 0.5), 0))
  ink = max(ink, digit(pw, minute - mt * 10, s, thick))
  let beat = step(fract(time), 0.5)
  let dots = max(bar(px, vec2(11.8, 2.9), vec2(11.8, 2.9), s, thick), bar(px, vec2(11.8, 6.1), vec2(11.8, 6.1), s, thick)) * beat
  ink = max(ink, dots) * face
  acc = vec4(vec4(acc.rgb * (1 - ink) + vec3(0.25, 0.9, 0.55) * ink, acc.a * (1 - ink) + ink))
  }
  // The console's power light: a small green lamp on its front, lit while the console is on.
  if (max(abs(at.x - 1332.6), abs(at.y - 507.6)) < 5.0) {
  let cpd = length(at - vec2(1332.6, 507.6))
  let cpg = clamp((0.5 * exp(-cpd * cpd / 5) + 1 - smoothstep(0.5, 0.9, cpd)) * state.at(vec2(5, 0)).x, 0, 1)
  acc = vec4(vec4(acc.rgb * (1 - cpg) + vec3(0.55, 1, 0.72) * cpg, acc.a * (1 - cpg) + cpg))
  }
  }
  return vec4(acc)
}


const HIT = table([[1125,425,166,122],[1358,470,39,136],[195,500,150,145],[498,530,58,70],[1125,562,166,46],[1298,490,38,118],[1398,468,34,50]])
const HIT2 = table([[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0],[1337,533,20,69],[0,0,0,0],[0,0,0,0]])
const PACE = table([[4.5,3],[2.5,2.5],[5,3.3],[6,3.5],[6,6],[6,6],[3.3,7]])
const SUN = table([[0,0,0,0],[0,0.5,0,0],[0,1,0,0],[0,0.6,0,0.4],[0.35,0,0,1],[0.85,0,0,0.25],[1,0,0,0],[0.65,0,1,0]])
const WEATHER = table([[0,0,0],[0.75,0,0],[0.9,0.6,0],[1,1,0],[1,0.9,1]])

// A lane's step toward its target, at most rate a second, and never more than one frame's at 30 a second: a long
// frame would otherwise move the whole room at once.
function toward(now: number, target: number, rate: number): number {
  let most = rate * min(dt, 0.03333333333333333)
  return now + clamp(target - now, -most, most)
}
// While the hurry timer runs, every lane moves at least a whole change in 6 seconds.
function paceOf(hurry: number, own: number): number {
  return max(own, step(0.0001, hurry) * 0.1666)
}
// One field of a coded value: the whole number of units, count wide. No code yet (-1) reads as 0.
function field(code: number, unit: number, count: number): number {
  return mod(floor(max(code, 0) / unit), count)
}
function differs(a: number, b: number, unit: number, count: number): number {
  return step(0.5, abs(field(a, unit, count) - field(b, unit, count)))
}
// The app eases a value through every code between, so a code counts only once the number has held still.
// screen: (accepted or -1, seen, still, 1) after this frame, given the frame before's and the seconds since set-up.
// In the first 6 seconds any code that holds 0.5 s is taken. After them, a code that changes one field
// is taken after 0.5 s, and one that changes more, which is a code on the way, only after 3 s.
// A long frame counts as a tenth of a second still: the app may not move the number while the window stalls, and a
// code on the way must not be taken for having stood through one frame.
function screenStep(was: vec4, now: number, start: number): vec4 {
  let seen = was.y
  let still = was.z + min(dt, 0.1)
  if (abs(now - seen) > 0.05) {
    seen = now
    still = 0
  }
  let k = floor(seen + 0.5)
  let near = 1 - step(0.3, abs(seen - k))
  let fields = differs(k, was.x, 1, 2) + differs(k, was.x, 2, 2) + differs(k, was.x, 4, 4) + differs(k, was.x, 16, 4)
  let hold = 0.5 + 2.5 * step(6, start) * step(1.5, fields)
  let accepted = was.x
  if (near * step(0.5, abs(k - was.x)) * (1 - step(still, hold)) > 0.5) {
    accepted = k
  }
  return vec4(accepted, seen, still, 1)
}
// world: the same, taken only after 2.5 s still, at a start, after a clear and while running alike.
function worldStep(was: vec4, now: number): vec4 {
  let seen = was.y
  let still = was.z + min(dt, 0.1)
  if (abs(now - seen) > 0.05) {
    seen = now
    still = 0
  }
  let k = floor(seen + 0.5)
  let near = (1 - step(0.3, abs(seen - k))) * step(k, 239.5)
  let accepted = was.x
  if (near * step(0.5, abs(k - was.x)) * (1 - step(still, 2.5)) > 0.5) {
    accepted = k
  }
  return vec4(accepted, seen, still, 1)
}

// A row of texels the shader keeps from frame to frame.
// One a switch: how far on it is drawn (0 to 1), what it is heading for, the mod's number as last seen (for the tape
// and the console, their screen field as last taken, plus 4 once clicked since set-up), and a set-up flag. A click here
// flips what the switch is heading for at once, even while it is still changing. The mod's numbers for the other five
// are eased by the app over seconds, so only their direction is read: the moment one starts to rise the switch heads
// on, and to fall, off. The tape and the console take their orders from screen.
// Texel 7: whether the pointer was down, so a press counts once.
// The second row, one texel a switch: the seconds since what it is heading for last changed, and that heading as
// last seen. It starts at 99, so nothing replays a switch-on when the shader starts.
// Texel 8: the minute the VCR clock shows. The app eases the mod's number over seconds, so the clock takes a new
// minute only once the number has stood still for a moment, and never counts through the minutes between.
function advance(cell: vec2): vec4 {
  let was = vec4(state.at(cell))
  let held = vec4(state.at(vec2(7, 0)))
  let press = pointer(0).down * step(0.5, pointerCount)
  let next = vec4(press, 0, 0, 0)
  let scr = vec4(state.at(vec2(9, 0)))
  let scr1 = vec4(state.at(vec2(9, 1)))
  let world = state.at(vec2(10, 0)).x
  let setup = 0
  if (was.w < 0.5) {
    setup = 1
  }
  if (cell.x > 10.5) {
    // The pieces' columns. In scope: the accepted fields, the hurry timer, the VCR minute and the seconds since it
    // was taken, and this column's lanes and private numbers as they stood.
    let hurry = scr1.x
    let wc = max(world, 0)
    let sun = mod(wc, 8)
    let wr = floor(wc / 8)
    let weather = mod(wr, 5)
    let wq = floor(wr / 5)
    let work = mod(wq, 2)
    let zone = floor(wq / 2)
    let hall = field(scr.x, 2, 2)
    let minute = state.at(vec2(8, 0)).x
    let beat = state.at(vec2(8, 1)).x
    // A cue taken the frame before is 0 seconds old for exactly one frame: a piece runs its event when it reads that.
    let cueNow = vec4(state.at(vec2(10, 1)))
    let cue = cueNow.x * (1 - step(0.0001, cueNow.y)) * step(30, time)
    if (cell.x < 11.5) {
      // Column 11: the time piece.
      let p = vec4(state.at(vec2(11, 0)))
      let q = vec4(state.at(vec2(11, 1)))
      let p0 = p.x
      let p1 = p.y
      let p2 = p.z
      let p3 = p.w
      let q0 = q.x
      let q1 = q.y
      let q2 = q.z
      let fresh = 0
      if (q.w < 0.5) {
        fresh = 1
      }
      let a0 = p0
      let a1 = p1
      let a2 = p2
      let a3 = p3
      let m0 = q0
      let m1 = q1
      let m2 = q2
      let td_row = vec4(SUN.at(sun))
      let td_pace = paceOf(hurry, 0.000667)
      a0 = toward(p0, td_row.x, td_pace)
      a1 = toward(p1, td_row.y, td_pace)
      a2 = toward(p2, td_row.z, td_pace)
      a3 = toward(p3, td_row.w, td_pace)
      // Every lane holds its default from a set-up until world is first accepted.
      if (fresh > 0.5 || world < -0.5) {
        a0 = 0
        a1 = 0
        a2 = 0
        a3 = 0
      }
      if (fresh > 0.5) {
        m0 = 0
        m1 = 0
        m2 = 0
      }
      if (cell.y > 0.5) {
        return vec4(m0, m1, m2, 1)
      }
      return vec4(a0, a1, a2, a3)
    }
    if (cell.x < 12.5) {
      // Column 12: the time piece.
      let p = vec4(state.at(vec2(12, 0)))
      let q = vec4(state.at(vec2(12, 1)))
      let p0 = p.x
      let p1 = p.y
      let p2 = p.z
      let p3 = p.w
      let q0 = q.x
      let q1 = q.y
      let q2 = q.z
      let fresh = 0
      if (q.w < 0.5) {
        fresh = 1
      }
      let a0 = p0
      let a1 = p1
      let a2 = p2
      let a3 = p3
      let m0 = q0
      let m1 = q1
      let m2 = q2
      let td_row = vec4(SUN.at(sun))
      let td_pace = paceOf(hurry, 0.000667)
      a0 = toward(p0, 1 - 0.85 * td_row.x * (1 - 0.5 * state.at(vec2(13, 0)).x - 0.15 * state.at(vec2(13, 0)).z), td_pace)
      a1 = toward(p1, 1 - 0.45 * td_row.y, td_pace)
      a2 = toward(p2, 1 - 0.6 * td_row.x * (1 - 0.3 * state.at(vec2(13, 0)).x), td_pace)
      a3 = 0
      // Every lane holds its default from a set-up until world is first accepted.
      if (fresh > 0.5 || world < -0.5) {
        a0 = 1
        a1 = 1
        a2 = 1
        a3 = 0
      }
      if (fresh > 0.5) {
        m0 = 0
        m1 = 0
        m2 = 0
      }
      if (cell.y > 0.5) {
        return vec4(m0, m1, m2, 1)
      }
      return vec4(a0, a1, a2, a3)
    }
    if (cell.x < 13.5) {
      // Column 13: the weather piece.
      let p = vec4(state.at(vec2(13, 0)))
      let q = vec4(state.at(vec2(13, 1)))
      let p0 = p.x
      let p1 = p.y
      let p2 = p.z
      let p3 = p.w
      let q0 = q.x
      let q1 = q.y
      let q2 = q.z
      let fresh = 0
      if (q.w < 0.5) {
        fresh = 1
      }
      let a0 = p0
      let a1 = p1
      let a2 = p2
      let a3 = p3
      let m0 = q0
      let m1 = q1
      let m2 = q2
      let wx_row = vec3(WEATHER.at(weather))
      let wx_rate = paceOf(hurry, 0.0111)
      a0 = toward(p0, wx_row.x, wx_rate)
      a1 = toward(p1, wx_row.y, wx_rate)
      a2 = toward(p2, wx_row.z, wx_rate)
      let wx_minute = floor(minute + 0.5)
      let wx_second = 8 + mod(wx_minute * 29 + 5, 41)
      let wx_due = step(mod(wx_minute * 73 + 17, 101), 34.5) * step(wx_second, beat) * (1 - step(wx_second, q2))
      let wx_rule = (1 - step(time, 30)) * (1 - step(0.0001, hurry))
      let wx_cue = step(2.5, cue) * (1 - step(3.5, cue))
      let wx_go = max(wx_due * wx_rule * step(0.5, abs(q1 - wx_minute - 1)), wx_cue) * step(3.5, weather) * step(0.3, p2) * (1 - step(0.5, q0))
      if (q0 > 0.5) {
      m0 = q0 + min(dt, 0.03333333333333333)
      }
      if (wx_go > 0.5) {
      m0 = 1
      m1 = wx_minute + 1
      }
      let wx_age = max(m0 - 1, 0)
      let wx_flash = a2 * step(0.5, m0) * smoothstep(0, 0.35, wx_age) * exp(-max(wx_age - 0.35, 0) / 0.6)
      a3 = wx_flash * step(0.001, wx_flash)
      if (wx_age > 5.35) {
      m0 = 0
      }
      m2 = beat
      // Every lane holds its default from a set-up until world is first accepted.
      if (fresh > 0.5 || world < -0.5) {
        a0 = 0
        a1 = 0
        a2 = 0
        a3 = 0
      }
      if (fresh > 0.5) {
        m0 = 0
        m1 = 0
        m2 = 0
      }
      if (cell.y > 0.5) {
        return vec4(m0, m1, m2, 1)
      }
      return vec4(a0, a1, a2, a3)
    }
    if (cell.x < 14.5) {
      // Column 14: the claude-tv piece.
      let p = vec4(state.at(vec2(14, 0)))
      let q = vec4(state.at(vec2(14, 1)))
      let p0 = p.x
      let p1 = p.y
      let p2 = p.z
      let p3 = p.w
      let q0 = q.x
      let q1 = q.y
      let q2 = q.z
      let fresh = 0
      if (q.w < 0.5) {
        fresh = 1
      }
      let a0 = p0
      let a1 = p1
      let a2 = p2
      let a3 = p3
      let m0 = q0
      let m1 = q1
      let m2 = q2
      let roughTarget = 0.4 * step(0.5, zone) + 0.6 * step(1.5, zone)
      a0 = toward(p0, work, paceOf(hurry, mix(0.3333, 0.6667, step(p0, work))))
      a1 = toward(p1, roughTarget, paceOf(hurry, mix(0.01667, 0.00833, step(p1, roughTarget))))
      a2 = 0
      a3 = 0
      m0 = 0
      m1 = 0
      m2 = 0
      // Every lane holds its default from a set-up until world is first accepted.
      if (fresh > 0.5 || world < -0.5) {
        a0 = 0
        a1 = 0
        a2 = 0
        a3 = 0
      }
      if (fresh > 0.5) {
        m0 = 0
        m1 = 0
        m2 = 0
      }
      if (cell.y > 0.5) {
        return vec4(m0, m1, m2, 1)
      }
      return vec4(a0, a1, a2, a3)
    }
    if (cell.x < 15.5) {
      // Column 15: the hallway piece.
      let p = vec4(state.at(vec2(15, 0)))
      let q = vec4(state.at(vec2(15, 1)))
      let p0 = p.x
      let p1 = p.y
      let p2 = p.z
      let p3 = p.w
      let q0 = q.x
      let q1 = q.y
      let q2 = q.z
      let fresh = 0
      if (q.w < 0.5) {
        fresh = 1
      }
      let a0 = p0
      let a1 = p1
      let a2 = p2
      let a3 = p3
      let m0 = q0
      let m1 = q1
      let m2 = q2
      let hw_go = (1 - step(20, q2)) * step(20, beat) * hall * step(30, time) * (1 - step(0.0001, hurry))
      let hw_code = floor(minute * 1023 / 719 + 0.5005)
      let hw_late = step(1.5, sun) * (1 - step(3.5, sun))
      let hw_pass = (1 - hw_late) * (1 - step(2, mod(hw_code * 61 + 8.5, 127)))
      let hw_hash = mod(hw_code * 89 + 69.5, 211)
      let hw_light = (1 - step(1.5, sun)) * (1 - step(3, hw_hash)) + hw_late * (1 - step(1, hw_hash))
      let hw_cueLight = step(1.5, cue) * (1 - step(2.5, cue)) * hall
      let hw_cuePass = step(0.5, cue) * (1 - step(1.5, cue)) * hall * (1 - step(0.0001, q1))
      m0 = max(max(q0 - dt, 0) * hall, 180 * hw_go * hw_light * (1 - step(0.0001, q0)))
      m0 = mix(m0, 180 * (1 - step(0.0001, q0)), hw_cueLight)
      m1 = mix(max(q1 - dt, -100), 2.5, max(hw_go * hw_pass * step(q1, -99.99), hw_cuePass))
      m2 = beat
      let hw_into = 2.5 - m1
      a0 = toward(p0, 1 + 1.5 * step(0.0001, m0), paceOf(hurry, 2.5))
      a1 = smoothstep(0, 0.8, hw_into) * (1 - smoothstep(1.2, 2.5, hw_into)) * step(0.0001, m1)
      a2 = clamp(hw_into / 2.5, 0, 1) * step(0.0001, m1)
      a3 = 0
      // Every lane holds its default from a set-up until world is first accepted.
      if (fresh > 0.5 || world < -0.5) {
        a0 = 1
        a1 = 0
        a2 = 0
        a3 = 0
      }
      if (fresh > 0.5) {
        m0 = 0
        m1 = 0
        m2 = 0
      }
      if (cell.y > 0.5) {
        return vec4(m0, m1, m2, 1)
      }
      return vec4(a0, a1, a2, a3)
    }
    return vec4(0, 0, 0, 1)
  }
  if (cell.y > 0.5) {
    if (cell.x < 6.5) {
      let heading = state.at(vec2(cell.x, 0)).y
      let age = was.x + dt
      let alive = was.z + dt
      if (was.w < 0.5) {
        age = 99
        alive = 0
      }
      // A start-window order from screen sets the tape or the console where it already stands drawn, at once: that
      // is the shader catching up, not a change, so it does not replay a switch-on.
      let caught = 0
      if (cell.x > 3.5 && cell.x < 5.5) {
        caught = step(abs(state.at(vec2(cell.x, 0)).x - heading), 0.0001) * (1 - step(6, scr1.y))
      }
      // The app eases the mod's numbers in over seconds when the shader starts, so for its first four seconds a change
      // of heading is the shader catching up, not a click, and must not replay a switch-on.
      if (alive > 4 && abs(heading - was.y) > 0.5 && caught < 0.5) {
        age = 0
      }
      return vec4(age, heading, min(alive, 10), 1)
    }
    if (cell.x > 7.5 && cell.x < 8.5) {
      // The seconds since the VCR's minute was taken, for the pieces' timed events.
      let minuteNow = state.at(vec2(8, 0)).x
      let beat = was.x + dt
      let taken = was.y
      if (setup > 0.5 || abs(minuteNow - taken) > 0.5) {
        beat = 0
        taken = minuteNow
      }
      return vec4(beat, taken, 0, 1)
    }
    if (cell.x > 9.5 && cell.x < 10.5) {
      // A cue: world codes above 239 carry one event to run once (239 + id), never a state. The mod holds one
      // for 2.5 s and more, then sends the atmosphere's code back. A cue held still as long as world needs is
      // taken once: (cue id, seconds since it was taken, the code taken, 1). It is taken again only after world has
      // left the cue's codes. Nothing else changes: world's own fields stay as they were.
      let wt = vec4(state.at(vec2(10, 0)))
      let k = floor(wt.y + 0.5)
      let cue = was.x
      let age = min(was.y + min(dt, 0.03333333333333333), 99)
      let taken = was.z
      if (k < 239.5) {
        taken = 0
      }
      if (step(239.5, k) * (1 - step(0.3, abs(wt.y - k))) * step(2.5, wt.z) * step(0.5, abs(k - taken)) > 0.5) {
        cue = k - 239
        age = 0
        taken = k
      }
      if (setup > 0.5) {
        cue = 0
        age = 99
        taken = 0
      }
      return vec4(cue, age, taken, 1)
    }
    if (cell.x > 8.5 && cell.x < 9.5) {
      // The hurry timer is set to 30 s at a set-up and at each flip of screen's hurry bit, and counts
      // down only while world rests on the code it took: while world has no code yet, or one on the way, it stands
      // still, so the lanes get their whole change once world takes the code, however slowly the app eases there.
      // It counts a long frame as one frame at 30 a second, as toward() moves the lanes, so the lanes still get their
      // whole change. The start window is the first 6 s after a set-up.
      let since = min(was.y + dt, 99)
      let wt = vec4(state.at(vec2(10, 0)))
      let hurried = max(was.x - min(dt, 0.03333333333333333) * step(abs(wt.y - wt.x), 0.3), 0)
      let before = vec4(state.at(vec2(9, 0)))
      let after = screenStep(before, v.screen, was.y)
      if (step(0.5, abs(after.x - before.x)) * differs(after.x, before.x, 1, 2) > 0.5) {
        hurried = 30
      }
      if (setup > 0.5) {
        hurried = 30
        since = 0
      }
      return vec4(hurried, since, 0, 1)
    }
    return vec4(0, 0, 0, 1)
  }
  if (cell.x < 6.5) {
    let asked = v.tv
    if (cell.x > 0.5) {
      asked = v.lava
    }
    if (cell.x > 1.5) {
      asked = v.pc
    }
    if (cell.x > 2.5) {
      asked = v.lamp
    }
    if (cell.x > 5.5) {
      asked = v.light
    }
    let box = vec4(HIT.at(cell.x))
    let other = vec4(HIT2.at(cell.x))
    let s = max(size.x / 1600, size.y / 1000)
    // The app reports up to four pointers, and one that has lifted stays in the list for a while, so the mouse is
    // not always the first. Every one is read: a press inside this switch's rectangle, on the bare backdrop.
    let pressed = 0
    for (const p of pointers) {
      let at = vec2(800 + (p.where.x - 0.5) * size.x / s, 500 + (0.5 - p.where.y) * size.y / s)
      let inside = step(box.x, at.x) * step(at.x, box.x + box.z) * step(box.y, at.y) * step(at.y, box.y + box.w)
      inside = max(inside, step(other.x, at.x) * step(at.x, other.x + other.z) * step(other.y, at.y) * step(at.y, other.y + other.w) * step(0.5, other.z))
      // gone is 0 while the pointer is there: one that has lifted is not a press, whatever it last reported.
      pressed = max(pressed, p.down * (1 - p.over) * inside * (1 - step(0.0001, p.gone)))
    }
    // A click is the frame a press appears here: pressed now, and not pressed here the frame before (the fourth
    // number of this texel, which is 1 when set up and 2 while a press is held on this switch).
    let click = step(0.5, pressed) * (1 - step(1.5, was.w))
    let level = was.x
    let want = was.y
    let last = was.z
    if (cell.x < 3.5 || cell.x > 5.5) {
      // The fourth number is 0 until this texel has been set up: the app clears the buffers when it restarts the shader.
      if (was.w < 0.5) {
        level = step(0.5, asked)
        want = level
        last = asked
      }
      // The mod's number moves only when the shader starts (the app eases it in from 0) and on a /bedroom command; a
      // click never moves it. So a move of a fiftieth is an order, and the switch heads the way the number moved.
      if (asked > last + 0.02) {
        want = 1
        last = asked
      }
      if (asked < last - 0.02) {
        want = 0
        last = asked
      }
    } else {
      // The tape and the console: their field of screen (the commanded state, and a bit that flips with each
      // command). In the start window a changed field sets the switch at once, unless a click has turned it since
      // set-up; after it, the switch heads for the field's state at its own pace, as after a click.
      let unit = 4
      if (cell.x > 4.5) {
        unit = 16
      }
      let taken = field(scr.x, unit, 4)
      let bit = mod(taken, 2)
      let clicked = step(3.5, last)
      if (was.w < 0.5) {
        level = 0
        want = 0
        last = 0
        clicked = 0
      } else {
        if (abs(taken - mod(last, 4)) > 0.5) {
          if (scr1.y < 6) {
            if (clicked < 0.5) {
              level = bit
              want = bit
            }
          } else {
            want = bit
          }
          last = taken + 4 * clicked
        }
      }
      if (click > 0.5) {
        last = mod(last, 4) + 4
      }
    }
    // A click flips the switch, here and nowhere else. One made while the switch is still changing turns it
    // round from where it has got to, so every click counts, however fast.
    if (click > 0.5) {
      want = 1 - want
    }
    let pace = vec2(PACE.at(cell.x))
    level = clamp(level + (want * 2 - 1) * dt * mix(pace.x, pace.y, want), 0, 1)
    // In those first four seconds a switch is drawn where it is heading at once, with no animation.
    if (state.at(vec2(cell.x, 1)).z < 4) {
      level = want
    }
    next = vec4(level, want, last, 1 + step(0.5, pressed))
  }
  if (cell.x > 7.5 && cell.x < 8.5) {
    let shown = was.x
    let seen = was.y
    let still = was.z
    if (was.w < 0.5) {
      shown = v.clock
      seen = v.clock
      still = 0
    }
    if (abs(v.clock - seen) > 0.3) {
      seen = v.clock
      still = 0
    } else {
      still = still + dt
    }
    if (still > 0.4) {
      shown = seen
    }
    next = vec4(shown, seen, still, 1)
  }
  if (cell.x > 8.5 && cell.x < 9.5) {
    if (setup > 0.5) {
      return vec4(-1, v.screen, 0, 1)
    }
    return screenStep(was, v.screen, scr1.y)
  }
  if (cell.x > 9.5 && cell.x < 10.5) {
    if (setup > 0.5) {
      return vec4(-1, v.world, 0, 1)
    }
    return worldStep(was, v.world)
  }
  return next
}

const state: Buffer = buffer({ size: [16, 2], float: 32, filter: 'nearest' }, (p: Pixel) => advance(p.cell))

export default shader({
  fps: 30,
  passes: [state, picture((p: Pixel) => pic(p.uv))],
})
