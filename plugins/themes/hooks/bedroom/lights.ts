// @generated from lights.glsl by glsl2dsl.mjs. Edit the .glsl, not this file.
import { abs, buffer, clamp, cos, dot, dt, exp, first, floor, fract, length, max, min, mix, mod, picture, pointer, pointerCount, pointers, pow, range, shader, sin, size, smoothstep, sqrt, step, table, time, values, vec2, vec3, vec4, type Buffer, type Pixel } from 'claude-code/shader'

const v = values({ tv: [0, 1], lava: [0, 1], clock: [0, 719], pc: [0, 1], lamp: [0, 1], tape: [0, 1], console: [0, 1], light: [0, 1] })
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
// The television's light on the room, k strong, its color following the screen: blue idle, green-grey tape,
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
function pic(uv: vec2): vec4 {
  let now_tv = state.at(vec2(0, 0)).x
  let now_lava = state.at(vec2(1, 0)).x
  let now_pc = state.at(vec2(2, 0)).x
  let now_lamp = state.at(vec2(3, 0)).x
  let now_tape = state.at(vec2(4, 0)).x
  let now_console = state.at(vec2(5, 0)).x
  let now_light = state.at(vec2(6, 0)).x
  let since_console = state.at(vec2(5, 1)).x
  let now_clock = state.at(vec2(8, 0)).x
  let s = max(size.x / 1600, size.y / 1000)
  let at = vec2(vec2(800 + (uv.x - 0.5) * size.x / s, 500 + (0.5 - uv.y) * size.y / s))
  // Computed dusk, laid first so every light below goes over it. Each point keeps m of its lit color and takes dc,
  // the dusk's own blue ambient; m rises down the wall, falls toward the camera on the floor, and is set by region for
  // the furniture. The bulb's output falls as v_light squared and glows warm part way. The television's halo is added
  // back, and the window's sky, the two screens and the power lights stay out of the darkening.
  let acc = vec4(vec4(0))
  let night = 1 - now_light * now_light
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
  m = m + (mix(0.7 + 0.2 * up, 1, open) - m) * gl
  dc = vec3(mix(dc, cc * fade, gl))
  }
  }
  }
  } else {
  if (at.x > 186.0 && at.y < 900.0) {
  m = mix(m, 0.12, smoothstep(186, 194, at.x) * (1 - smoothstep(850, 895, at.y)))
  }
  }
  if (abs(at.x - 280.0) < 84.0 && abs(at.y - 573.0) < 75.0) {
  let mon = sbox(at, vec2(280, 573), vec2(81, 71), 1)
  m = mix(m, 0.24, mon)
  dc = vec3(mix(dc, vec3(0.02, 0.022, 0.043) * night, mon))
  let shown = max(sbox(at, vec2(270, 557), vec2(54.25, 39.25), 2.25), 1 - smoothstep(1, 2.6, length(at - vec2(318.4, 616))))
  m = m + (1 - m) * shown
  dc = vec3(dc * (1 - shown))
  }
  if (abs(at.x - 430.0) < 102.0 && abs(at.y - 686.0) < 116.0) {
  let cd = vec2(abs(at - vec2(430, 686)) - vec2(74, 88))
  let ch = 1 - smoothstep(21, 26, length(max(cd, vec2(0))) + min(max(cd.x, cd.y), 0))
  m = mix(m, 0.24, ch)
  dc = vec3(mix(dc, vec3(0.012, 0.016, 0.042) * night, ch))
  }
  if (abs(at.x - 403.0) < 70.0 && abs(at.y - 850.0) < 5.0) {
  let led = max(1 - smoothstep(1, 2.2, length(at - vec2(460, 848))), 1 - smoothstep(1, 2.2, length(at - vec2(469.6, 848))))
  led = max(led, 1 - smoothstep(1, 2.2, length(at - vec2(337.3, 852)))) * now_pc
  m = m + (1 - m) * led
  dc = vec3(dc * (1 - led))
  }
  // The desk lamp, when on, shows the shade, the arm and the window trim beside it in their own warm light.
  if (at.x > 470.0 && abs(at.y - 580.0) < 76.0) {
  let lp = 0.5 * now_lamp * pow(clamp(1 - ell(at, vec2(516, 578), vec2(40, 75)), 0, 1), 1.3)
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
  m = mix(m, 0.1 + 0.02 * now_tv, pt)
  dc = vec3(mix(dc, vec3(0, 0.01, 0.035) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(now_tape, now_console, night * 0.075 * now_tv), pt))
  }
  } else {
  // The dresser's left side from its top down, and the front lip of its top, lit from the television.
  if (at.y > 590.0 && at.x > 1066.0 && at.x < 1402.0) {
  let sd = 1 - smoothstep(1108, 1112, at.x)
  let top = sbox(at, vec2(1256, 608), vec2(146, 8.5), 1)
  m = mix(mix(m, 0.08 + 0.05 * now_tv, sd), 0.1 + 0.12 * now_tv, top)
  dc = vec3(mix(dc, vec3(0, 0.01, 0.035) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(now_tape, now_console, night * 0.05 * now_tv), sd))
  dc = vec3(mix(dc, vec3(0, 0.01, 0.035) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(now_tape, now_console, night * 0.1 * now_tv), top))
  }
  if (at.x > 1111.5 - 0.075 * (at.y - 430.0) && at.x < 1296.0 && at.y > 421.0 && at.y < 597.0) {
  m = 0.16
  }
  if (abs(at.x - 1321.0) < 23.0 && at.y > 497.0 && at.y < 597.0) {
  m = 0.14
  }
  if (abs(at.x - 1232.0) < 60.0 && at.y < 432.0) {
  let cat = 1 - smoothstep(0.95, 1.05, min(ell(at, vec2(1231, 425), vec2(49, 44)), ell(at, vec2(1254, 388), vec2(20, 21))))
  m = mix(m, 0.07 + 0.05 * now_tv, cat)
  }
  if (abs(at.x - 1411.75) < 12.0 && abs(at.y - 493.0) < 19.0) {
  let sw = sbox(at, vec2(1411.75, 493), vec2(10.75, 17.5), 0.7)
  m = mix(m, 0.12, sw)
  dc = vec3(dc + vec3(0, 0.005, 0.06) * (sw * night * now_tv))
  }
  }
  if (at.y > 268.0) {
  let ea = vec2((at - vec2(1290, 477)) * vec2(0.00726, 0.00607))
  let eb = vec2((at - vec2(1215, 502)) * vec2(0.00347, 0.00427))
  let qa = clamp(1 - dot(ea, ea), 0, 1)
  let qb = clamp(1 - dot(eb, eb), 0, 1)
  let glow = (0.199 * qa * qa + 0.102 * qb * qb) * (1 - smoothstep(560, 616, at.y))
  glow = glow + 0.25 * clamp(1 - abs(at.x - 1208) / 110, 0, 1) * clamp(1 - abs(at.y - 604) / 8, 0, 1)
  glow = glow * (1 - 0.6 * step(1111.5 - 0.075 * (at.y - 430), at.x) * step(at.x, 1296) * step(421, at.y) * step(at.y, 597)) * now_tv
  m = m * (1 - glow)
  dc = vec3(dc * (1 - glow) + tvl(now_tape, now_console, night * glow))
  }
  if (abs(at.x - 1207.5) < 76.0 && abs(at.y - 485.0) < 58.0) {
  let gd = vec2(abs(at - vec2(1207.5, 485)) - vec2(73, 55.5))
  let shown = 1 - smoothstep(-2, 1.5, max(gd.x, gd.y))
  m = m + (1 - m) * shown
  dc = vec3(dc * (1 - shown))
  }
  } else {
  // The dresser's drawer faces, lit from the television above and less further down, and its left side.
  if (at.x > 1066.0 && at.x < 1402.0 && at.y < 905.0) {
  let dt = clamp((at.y - 612) / 256, 0, 1)
  let sd = 1 - smoothstep(1108, 1112, at.x)
  // The faces keep little of their lit orange and take a grey bounce off the screen, strongest on the top row, so
  // they read as the neutral dark grey of the hand-drawn dusk room (fitted to it on the three rows of drawers).
  let du = clamp(1 - dt * 2, 0, 1) * (1 - 0.3 * smoothstep(1200, 1340, at.x))
  let dw = 1 - dt
  let dg = (0.007 + 0.05 * dw * dw * (1 - 0.3 * smoothstep(1200, 1340, at.x))) * (1 - sd) * now_tv * (1 - 0.6 * max(now_tape, now_console))
  m = 0.08 + now_tv * mix(-0.008, 0.05, sd)
  dc = vec3((vec3(0, 0.004, 0.012) + vec3(0, 0.006, 0.023) * sd + vec3(dg)) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(now_tape, now_console, night * now_tv * mix(0.01 + 0.085 * du * du, 0.05, sd)))
  }
  if (at.y > 900.0) {
  let ep = vec2((at - vec2(1230, 965)) * vec2(0.0042, 0.0143))
  let pool = clamp(1 - dot(ep, ep), 0, 1)
  pool = 0.12 * pool * pool * now_tv
  m = m * (1 - pool)
  dc = vec3(dc * (1 - pool) + tvl(now_tape, now_console, night * pool))
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
  m = mix(m, 0.1 + 0.16 * now_tv, gm)
  dc = vec3(mix(dc, vec3(0, 0.004, 0.012) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(now_tape, now_console, night * 0.05 * now_tv), gm))
  }
  } else {
  // The door: its panels kept, a little of the television's light, and a warm strip of hallway light in the gap.
  if (at.y > 198.0 && at.y < 850.0) {
  m = 0.26
  let el = vec2((at - vec2(1208, 485)) * 0.00179)
  let lq = clamp(1 - dot(el, el), 0, 1)
  dc = vec3(vec3(0, 0.012, 0.045) * night + vec3(0.36, 0.2, 0.06) * wf + tvl(now_tape, now_console, night * 0.13 * lq * lq * now_tv))
  if (abs(at.x - 1460.5) < 12.0 && at.y > 234.0) {
  let hs = sbox(at, vec2(1460.5, 545), vec2(10.5, 311), 1)
  let wl = smoothstep(560, 760, at.y)
  m = mix(m, 0.12 + 0.12 * wl, hs)
  dc = vec3(mix(dc, vec3(0.004, 0.006, 0.014) * night + vec3(0.06, 0.035, 0.012) * (wl * night) + vec3(0.36, 0.2, 0.06) * wf, hs))
  }
  }
  }
  // The hallway light through the gap, a faint warm wedge on the floor below it.
  if (at.y > 850.0 && abs(at.x - 1450.0) < 60.0) {
  let fy = at.y - 850
  let wedge = clamp(1 - abs(at.x - 1460 + 0.5 * fy) / (6 + 0.4 * fy), 0, 1) * (1 - smoothstep(850, 915, at.y))
  dc = vec3(dc + vec3(0.045, 0.026, 0.008) * (wedge * night))
  }
  let vr = vec2((at - vec2(800, 500)) * vec2(0.00104, 0.00163))
  m = m * (1 - 0.6 * clamp(dot(vr, vr) - 0.3, 0, 0.75))
  }
  acc = vec4(vec4(dc, fade * (1 - m)))
  }
  let c = vec2(at - vec2(1207.5, 485))
  // The television: its cover, and under it the tape and the console, gathered in tv and laid over the dusk.
  let tv = vec4(vec4(0))
  if (abs(c.x) < 82.0 && abs(c.y) < 60.0) {
  let d = vec2(abs(c) - vec2(73, 55.5))
  let glass = 1 - smoothstep(-2, 1.5, max(d.x, d.y))
  let p = 1 - now_tv
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
  let tk = now_tape * (1 - smoothstep(-0.8, 0.4, tlip))
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
  let thw = 0.135 + 0.06 * tlow + 0.008 * tlow * tsway // spellchecker:disable-line
  let tdc = max(abs(tgx) - thw, max(tp.y - 0.05, -0.6 - tp.y)) // spellchecker:disable-line
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
  let k_on = clamp(now_console * (1 - now_tape), 0, 1)
  let k_w = k_on * k_gm
  let k_t = since_console
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
  let k_hole = k_mh * k_on * now_tv * smoothstep(2.6, 3.6, k_t)
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
  let k_ba = k_w * (0.21 * (1 - abs(at.y - k_ty) / 11) + 0.12 * exp(-k_s1 * k_s1) * smoothstep(0.2, 0.8, sin(at.x * 0.11 + 1.7) * sin(at.x * 0.037 + 0.4))) // spellchecker:disable-line
  con = vec4(vec4(vec3(0.847, 0.878, 1) * k_ba + con.rgb * (1 - k_ba), k_ba + con.a * (1 - k_ba))) // spellchecker:disable-line
  }
  let k_lo = k_on * now_tv * (1 - k_gm)
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
  }
  if (abs(at.x - 1376.0) < 85.0 && abs(at.y - 530.0) < 112.0) {
  let on = now_lava * (1 - 0.55 * now_light)
  let wall = 1 - smoothstep(604, 608, at.y)
  let shelf = 1 - 0.75 * (1 - smoothstep(1343, 1349, at.x)) * smoothstep(486, 492, at.y)
  let stand = mix(8.8, 14.5, clamp((at.y - 557) / 43, 0, 1))
  let body = (1 - smoothstep(stand - 1, stand, abs(at.x - 1376))) * smoothstep(556, 557.5, at.y)
  wall = wall * (1 - 0.85 * body)
  let far = clamp(1 - ell(at, vec2(1376, 530), vec2(78, 108)), 0, 1)
  let g1 = 0.26 * pow(far, 1.7) * wall * shelf * on
  acc = vec4(vec4(acc.rgb * (1 - g1) + vec3(0.58, 0.25, 0.94) * g1, acc.a * (1 - g1) + g1))
  let near = clamp(1 - ell(at, vec2(1376, 536), vec2(30, 56)), 0, 1)
  let g2 = 0.2 * pow(near, 1.4) * wall * shelf * on
  acc = vec4(vec4(acc.rgb * (1 - g2) + vec3(0.706, 0.408, 1) * g2, acc.a * (1 - g2) + g2))
  let top = clamp(1 - ell(at, vec2(1376, 604), vec2(50, 50)), 0, 1)
  let g3 = 0.12 * pow(top, 1.5) * smoothstep(592, 596, at.y) * (1 - smoothstep(604, 607, at.y)) * (1 - smoothstep(1392, 1402, at.x)) * (1 - body) * on
  acc = vec4(vec4(acc.rgb * (1 - g3) + vec3(0.627, 0.314, 0.941) * g3, acc.a * (1 - g3) + g3))
  let g4 = 0.26 * body * (1 - smoothstep(557, 571, at.y)) * on
  acc = vec4(vec4(acc.rgb * (1 - g4) + vec3(0.627, 0.314, 0.941) * g4, acc.a * (1 - g4) + g4))
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
  let bloom = 0.24 * exp(-2.2 * ell(at, vec2(1376, 528), vec2(15, 32)) * ell(at, vec2(1376, 528), vec2(15, 32))) * wall * on
  acc = vec4(vec4(acc.rgb * (1 - bloom) + vec3(0.66, 0.36, 1) * bloom, acc.a * (1 - bloom) + bloom))
  }
  if (at.x < 345.0) {
  let dark = 1 - now_pc
  let m = vec2(abs(at - vec2(270, 557)) - vec2(56, 41))
  let screen = (1 - smoothstep(-4, 0.5, max(m.x, m.y))) * 0.78 * dark
  acc = vec4(vec4(acc.rgb * (1 - screen) + vec3(0.03, 0.035, 0.035) * screen, acc.a * (1 - screen) + screen))
  let led = (1 - smoothstep(0.6, 1, ell(at, vec2(319, 616), vec2(4.5, 4.5)))) * 0.85 * dark
  acc = vec4(vec4(acc.rgb * (1 - led) + vec3(0.05, 0.06, 0.05) * led, acc.a * (1 - led) + led))
  }
  if (abs(at.x - 524.0) < 45.0) {
  let lit = now_lamp * (1 - 0.65 * step(0.4, now_lamp) * step(now_lamp, 0.6))
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
  if (max(abs(at.x - 1227.0) / 16.0, abs(at.y - 591.5) / 7.0) < 1.0) {
  let r = vec2(abs(at - vec2(1227, 591.5)) - vec2(13.8, 5.4))
  let face = 1 - smoothstep(-0.4, 0.4, max(r.x, r.y))
  acc = vec4(vec4(acc.rgb * (1 - face) + vec3(0.016, 0.024, 0.039) * face, acc.a * (1 - face) + face))
  let mins = floor(now_clock + 0.5)
  let hour = floor(mins / 60)
  let minute = mins - hour * 60
  hour = hour + 12 * (1 - step(0.5, hour))
  let px = vec2(floor((at - vec2(1215, 587.1)) * s) + vec2(0.5))
  let thick = max(1, floor(s * 1.3 + 0.5))
  let tens = floor(hour / 10)
  let ink = digit(px, tens, s, thick) * step(0.5, tens)
  ink = max(ink, digit(px - vec2(floor(6 * s + 0.5), 0), hour - tens * 10, s, thick))
  let mt = floor(minute / 10)
  ink = max(ink, digit(px - vec2(floor(13.2 * s + 0.5), 0), mt, s, thick))
  ink = max(ink, digit(px - vec2(floor(19.2 * s + 0.5), 0), minute - mt * 10, s, thick))
  let beat = step(fract(time), 0.5)
  let dots = max(bar(px, vec2(11.8, 2.9), vec2(11.8, 2.9), s, thick), bar(px, vec2(11.8, 6.1), vec2(11.8, 6.1), s, thick)) * beat
  ink = max(ink, dots) * face
  acc = vec4(vec4(acc.rgb * (1 - ink) + vec3(0.25, 0.9, 0.55) * ink, acc.a * (1 - ink) + ink))
  }
  // The console's power light: a small green lamp on its front, lit while the console is on.
  if (max(abs(at.x - 1332.6), abs(at.y - 507.6)) < 5.0) {
  let cpd = length(at - vec2(1332.6, 507.6))
  let cpg = clamp((0.5 * exp(-cpd * cpd / 5) + 1 - smoothstep(0.5, 0.9, cpd)) * now_console, 0, 1)
  acc = vec4(vec4(acc.rgb * (1 - cpg) + vec3(0.55, 1, 0.72) * cpg, acc.a * (1 - cpg) + cpg))
  }
  return vec4(acc)
}


const HIT = table([[1125,425,166,122],[1358,470,42,136],[195,500,150,145],[498,530,58,70],[1125,562,166,46],[1298,490,46,118],[1398,468,34,50]])
const HIT2 = table([[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0],[1337,533,21,69],[0,0,0,0],[0,0,0,0]])
const PACE = table([[4.5,3],[2.5,2.5],[5,3.3],[6,3.5],[6,6],[6,6],[3.3,7]])

// A row of texels the shader keeps from frame to frame.
// One a switch: how far on it is drawn (0 to 1), what it is heading for, the mod's number as last seen, and a
// set-up flag. A click
// here flips what the switch is heading for at once, unless it is still changing. The mod's number is eased by the
// app over seconds, so only its direction is read: the moment it starts to rise the switch heads on, and to fall, off.
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
  if (cell.y > 0.5) {
    let heading = state.at(vec2(cell.x, 0)).y
    let age = was.x + dt
    let alive = was.z + dt
    if (first || was.w < 0.5) {
      age = 99
      alive = 0
    }
    // The app eases the mod's numbers in over seconds when the shader starts, so for its first four seconds a change
    // of heading is the shader catching up, not a click, and must not replay a switch-on.
    if (alive > 4 && abs(heading - was.y) > 0.5) {
      age = 0
    }
    return vec4(age, heading, min(alive, 10), 1)
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
    if (cell.x > 3.5) {
      asked = v.tape
    }
    if (cell.x > 4.5) {
      asked = v.console
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
    // The fourth number is 0 until this texel has been set up: the app clears the buffers when it restarts the shader.
    if (first || was.w < 0.5) {
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
  if (cell.x > 7.5) {
    let shown = was.x
    let seen = was.y
    let still = was.z
    if (first || was.w < 0.5) {
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
  return next
}

const state: Buffer = buffer({ size: [9, 2], float: 32, filter: 'nearest' }, (p: Pixel) => advance(p.cell))

export default shader({
  fps: 30,
  passes: [state, picture((p: Pixel) => pic(p.uv))],
})
