import { DEFAULT_STATE, f, pts, proj, toWall, unit, type Part, type State } from '../lib.ts'

type Pt = [number, number]
type Stop = [number, string, number?]

const S = 1.16
const S_OPEN = 1.18
const TV: Pt = [1208, 485]
const FX = 1110
const FY = 606
const FW = 290
const FH = 300
const OAK = '#c8975c'
const M = ' class="dresser-m"'

const box = (x: number, y: number, w: number, h: number): string => `M${f(x)},${f(y)}h${f(w)}v${f(h)}h-${f(w)}z`
const rect = (x: number, y: number, w: number, h: number, fill: string, extra = ''): string => path(box(x, y, w, h), fill, extra)
const poly = (p: Pt[], fill: string, extra = ''): string => `<polygon points="${pts(p)}" fill="${fill}"${extra}/>`
const ell = (cx: number, cy: number, rx: number, ry: number, fill: string, extra = ''): string =>
  `<ellipse cx="${f(cx)}" cy="${f(cy)}" rx="${f(rx)}" ry="${f(ry)}"${fill && ` fill="${fill}"`}${extra}/>`
const path = (d: string, fill: string, extra = ''): string => `<path d="${d}" fill="${fill}"${extra}/>`
const num = (v: number): string => String(Math.round(v * 100) / 100).replace(/^0\./, '.')
const op = (a: number): string => ` opacity="${num(a)}"`
const stops = (list: Stop[]): string =>
  list.map(([o, c, a]) => `<stop offset="${num(o)}" stop-color="${c}"${a === undefined ? '' : ` stop-opacity="${num(a)}"`}/>`).join('')
const lin = (id: string, coords: string, list: Stop[]): string =>
  `<linearGradient id="dresser-${id}"${coords && ' ' + coords}>${stops(list)}</linearGradient>`
const rad = (id: string, attrs: string, list: Stop[]): string =>
  `<radialGradient id="dresser-${id}"${attrs && ' ' + attrs}>${stops(list)}</radialGradient>`
const US = 'gradientUnits="userSpaceOnUse"'
const V = 'x2="0" y2="1"'
const u = (id: string): string => `url(#dresser-${id})`
const open = (x: number, y: number): Pt => {
  const [wx, wy] = toWall(x, y, S)
  return proj(wx, wy, S_OPEN)
}
const blur = (id: string, sd: number, m: number): string =>
  `<filter id="dresser-${id}" x="-${num(m)}" y="-${num(m)}" width="${1 + 2 * m}" height="${1 + 2 * m}"><feGaussianBlur stdDeviation="${sd}"/></filter>`

const grain = (id: string, w: number, h: number, freq: string, seed: number, k: number): string =>
  `<filter id="dresser-${id}f" filterUnits="userSpaceOnUse" x="0" y="0" width="${w}" height="${h}"><feTurbulence type="fractalNoise" baseFrequency="${freq}" numOctaves="3" seed="${seed}" stitchTiles="stitch"/><feColorMatrix values="0 0 0 0 .3 0 0 0 0 .15 0 0 0 0 .05 ${k} 0 0 0 -${f(k * 0.42)}"/></filter>` +
  `<pattern id="dresser-${id}" width="${w}" height="${h}" patternUnits="userSpaceOnUse"><rect width="${w}" height="${h}" filter="url(#dresser-${id}f)"/></pattern>`

let L1 = ''
let L6 = ''
let lips = ''
let hi = ''
let lo = ''
let KS = ''
let KC = ''

function knob(cx: number, cy: number, row: number, light: boolean): void {
  const r = 6
  const dx = TV[0] - cx
  const dy = TV[1] - cy
  const d = Math.hypot(dx, dy)
  L1 += ell(cx + (dx / d) * 2, cy - 4.3, 3, 1, '', op([0.95, 0.6, 0.32][row]))
  L6 += ell(cx - 2, cy - 2.4, 2.4, 1.7, '')
  KS += light ? ell(cx + 2, cy + 4.5, r * 1.6, r * 1.2, '') : ell(cx - (dx / d) * 1.2, cy + 3, r * 1.45, r * 1.05, '')
  KC += `<circle cx="${f(cx)}" cy="${f(cy)}" r="${r}"/>`
}

function drawer(x0: number, y0: number, x1: number, y1: number, row: number, col: number, light: boolean): string {
  const w = x1 - x0
  const kx = (x0 + x1) / 2
  const ky = (y0 + y1) / 2 - 2
  lips += `M${f(x0)},${f(y0)}h${f(w)}v1.2h-${f(w)}z`
  const h = y1 - y0
  const L = (x: number, y: number, W: number, H: number, t: number, s: number): string =>
    `M${f(x)},${f(y)}h${f(W)}v${f(t)}h-${f(W - s)}v${f(H - t)}h-${f(s)}z`
  const R = (x: number, y: number, W: number, H: number, t: number, s: number): string =>
    `M${f(x + W)},${f(y)}v${f(H)}h-${f(W)}v-${f(t)}h${f(W - s)}v-${f(H - t)}z`
  hi += L(x0, y0, w, h, 1.4, 1.2) + L(x0 + 7, y0 + 7, w - 14, h - 14, 1.2, 1.2)
  lo += R(x0, y0, w, h, 1.6, 1.4) + R(x0 + 7, y0 + 7, w - 14, h - 14, 1.2, 1.2)
  const k = unit(row * 2 + col, 5)
  knob(kx, ky, row, light)
  return (
    rect(x0, y0, w, y1 - y0, u(`g${(row + col) % 2 ? 'b' : 'a'}`)) +
    rect(x0, y0, w, y1 - y0, k > 0.5 ? '#fff4e0' : '#2a1406', op(0.03 + Math.abs(k - 0.5) * 0.12)) +
    rect(x0, y1, w, 3, u('os'))
  )
}

const ROWS: Pt[] = [[618, 694.5], [697.5, 778], [781, 864]]
const COLS: Pt[] = [[1114, 1253.5], [1256.5, 1396]]

const BODY = 'M-3,-13C-4,-19 -9,-26 -12,-23C-14,-21 -13,-14 -13,-9C-13,-4 -16,0 -16,7C-16,17 -8,22 0,22C9,22 16,17 16,8C16,1 13,-3 13,-8C13,-12 13,-18 10,-19C7,-20 5,-17 3,-13Z'
const GUARD = 'M-2.5,-13C-5,-16 -8,-19 -9.5,-16C-10.5,-12 -9,-7 -9.5,-3C-10,3 -9,8 -5,10C-1.5,11.5 2.5,9.5 5,7.5C7,6 6.5,2 5,-1C7,-4 7.5,-8 6,-10C4.5,-12 3.5,-13 2.5,-13Z'
const HEAD = 'M-2,-53C-2,-60 -2.5,-66 -1,-71.5C.5,-73 2.5,-72 3,-70L5,-66C5.5,-62 3,-59 2,-53Z'
const PICKUPS = 'M-3.5,-8h7v1.2h-7zM-3.5,-3h7v1.2h-7zM-3.5,2.5l7,-1.3v1.2l-7,1.3z'

const guitar = (t: string, c: string[], extra = ''): string =>
  `<g${t && ` transform="${t}"`}><use href="#dresser-gB" fill="${c[0]}"/>${extra}<use href="#dresser-gP" fill="${c[1]}"/><use href="#dresser-gK" fill="#121012"/>` +
  `${rect(-2, -54, 4, 42, c[2])}${rect(-1.6, -53, 3.2, 40, c[3])}<use href="#dresser-gH" fill="${c[2]}"/></g>`

const GG = 'M0,0C-36,0 -64,-16 -64,-50C-64,-74 -51,-84 -51,-104C-51,-122 -58,-140 -54,-160C-52,-172 -48,-183 -40,-183C-33,-183 -31,-175 -29,-168C-25,-158 -19,-154 -12,-154L12,-152C19,-152 26,-156 30,-162C33,-168 41,-170 42,-162C43,-150 46,-118 51,-100C56,-86 63,-74 63,-48C63,-16 36,0 0,0Z'
const GR = 'M-12,-150C-20,-152 -28,-150 -34,-140C-40,-128 -44,-116 -43,-100C-42,-88 -46,-76 -45,-62C-44,-52 -35,-50 -27,-56L-21,-58L22,-60C23,-44 26,-30 36,-22C46,-16 56,-22 57,-36C58,-52 52,-66 48,-80C45,-94 46,-110 40,-124C34,-138 22,-148 12,-150Z'
const GD = 'M-8,-305L-11,-353C-12,-367 -12,-374 -6,-377C4,-381 19,-377 22,-366C24,-357 19,-351 13,-346C9,-342 8,-329 9,-317L8,-305Z'
const GF = 'M-8,-305L8,-305L11,-122C11,-117 -11,-117 -11,-122Z'
const GA = 0.17
const GL = 0.09
function g3(x: number, y: number, h = 0): Pt {
  const [ca, sa, cb, sb] = [Math.cos(GA), Math.sin(GA), Math.cos(GL), Math.sin(GL)]
  const X = 30.4 + (x * sa - y * ca * sb) / 10 - h * ca * cb
  const Y = 44.6 + (y * cb) / 10 - h * sb
  const Z = 16 + (x * ca + y * sa * sb) / 10 + h * sa * cb
  const s = 130.5 / (130.5 - Z)
  return [800 + X * 7.8 * s, 500 + Y * 7.8 * s]
}
const r1 = (v: number): number => Math.round(v * 10) / 10
const fz = (v: number): string => String(r1(v)).replace(/^(-?)0\./, '$1.')
function pl(lines: Pt[][], tail = ''): string {
  let c: Pt = [0, 0]
  let out = ''
  for (const line of lines) {
    line.forEach(([x, y], i) => {
      const d: Pt = [r1(x - c[0]), r1(y - c[1])]
      out += (i ? 'l' : out ? 'm' : 'M') + `${fz(d[0])},${fz(d[1])}`
      c = [c[0] + d[0], c[1] + d[1]]
    })
    out += tail
  }
  return out
}
function pj(d: string, h = 0): string {
  let c: Pt = [0, 0]
  let out = ''
  for (const [, cmd, args] of d.matchAll(/([MLCZ])([^MLCZ]*)/g)) {
    if (cmd === 'Z') {
      out += 'z'
      continue
    }
    const n = (args.match(/-?[\d.]+/g) ?? []).map(Number)
    const q: string[] = []
    let e: Pt = c
    for (let i = 0; i < n.length; i += 2) {
      const [x, y] = g3(n[i], n[i + 1], h)
      const d: Pt = [r1(x - c[0]), r1(y - c[1])]
      q.push(`${fz(d[0])},${fz(d[1])}`)
      e = [c[0] + d[0], c[1] + d[1]]
    }
    out += (out ? cmd.toLowerCase() : 'M') + q.join(' ').replace(/ -/g, '-')
    c = e
  }
  return out
}

const FONT = 'font-family="Impact, Arial Black, Arial, sans-serif" font-weight="900" text-anchor="middle"'
const stroke = (d: string, c: string, w: number, extra = ''): string => `<path d="${d}" class="dresser-s" stroke="${c}" stroke-width="${w}"${extra}/>`

function concertArt(): string {
  const K = '#1a1016'
  let rays = ''
  for (let k = 0; k < 7; k++) {
    const a0 = (k * 2 * Math.PI) / 7 + 0.1
    const a1 = a0 + Math.PI / 7
    rays += `M49,96L${f(49 + Math.cos(a0) * 140)},${f(96 + Math.sin(a0) * 140)}L${f(49 + Math.cos(a1) * 140)},${f(96 + Math.sin(a1) * 140)}Z`
  }
  let crowd = 'M0,150V145'
  for (let k = 0; k < 9; k++) crowd += `a5.45,${f(4 + unit(k, 3) * 3)} 0 0 1 10.9,0`
  return (
    rect(0, 0, 98, 150, u('p1')) +
    path(rays, '#f8e2a4', op(0.2)) +
    rect(0, 124, 98, 26, '#6a3c2c') +
    path(crowd + 'V150Z', '#2a1824') +
    path('M44,104L41,129L45.5,129L49,108L51,108L54.5,129L59,129L56,104Z', K) +
    path('M42.5,79Q50,76 57.5,79L58.5,105L41.5,105Z', K) +
    guitar('translate(55 99) rotate(-62.5) scale(-.4 .4)', [K, K, K, K], '') +
    stroke('M44,81L37,88L31,86M56,81L60,90L56,97', K, 4.4) +
    `<circle cx="50" cy="71" r="7" fill="${K}"/>` +
    ell(50, 73.5, 3.4, 4.4, K) +
    stroke('M30.5,85.5h0M56,98h0', K, 3)
  )
}

function pulloutArt(): string {
  const SUN = [u('sb'), '#161214', '#b07a40', '#3a2216']
  const paper =
    path('M65.5,0h.6v184h-.6zM0,91.5h132v.6h-132z', '#fff8e8', op(0.2)) +
    path('M66.1,0h.6v184h-.6zM0,92.1h132v.6h-132z', '#000', op(0.15)) +
    path('M65.6,38h.9v5h-.9zM65.6,141h.9v5h-.9z', '#a8a8a4')
  return (
    rect(0, 0, 132, 184, u('p2')) + ell(68, 72, 62, 84, u('sp')) + rect(0, 148, 132, 36, '#3e2c26') +
    ell(66, 152, 30, 4, '#0e0a0c', op(0.6)) +
    stroke('M55,153L66,139L77,153M66,139V70', '#141216', 1.8) +
    guitar('translate(66 118) rotate(-3) scale(1.05)', SUN) +
    stroke('M62,67h8', '#141216', 2) +
    paper
  )
}

type Poster = { x: number; y: number; w: number; h: number; rot: number; curl: number; c: number; art: string; mounts: string }

function poster(p: Poster, i: number, st: State, lm: string[]): string {
  const { x, y, w, h, rot, curl, c } = p
  const corners: Pt[] = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
  const C = corners[curl]
  const prev = corners[(curl + 3) % 4]
  const next = corners[(curl + 1) % 4]
  const along = (q: Pt): Pt => {
    const l = Math.hypot(q[0] - C[0], q[1] - C[1])
    return [C[0] + ((q[0] - C[0]) * c) / l, C[1] + ((q[1] - C[1]) * c) / l]
  }
  const A = along(prev)
  const B = along(next)
  const Mid: Pt = [(A[0] + B[0]) / 2, (A[1] + B[1]) / 2]
  const ctl = (k: number): string => `${f(C[0] + (Mid[0] - C[0]) * k)},${f(C[1] + (Mid[1] - C[1]) * k)}`
  let outline = ''
  for (let k = 0; k < 4; k++) {
    const q = corners[k]
    outline += k === curl ? `L${f(A[0])},${f(A[1])}Q${ctl(1.3)} ${f(B[0])},${f(B[1])}` : `L${f(q[0])},${f(q[1])}`
  }
  outline = 'M' + outline.slice(1) + 'Z'
  const all = box(x, y, w, h)
  const [sx, sy] = st.light ? [1.4, 2.2] : st.tv ? [0.6, -1.8] : [0.9, 0.5]
  return (
    `<g transform="rotate(${rot} ${f(x + w / 2)} ${f(y + h / 2)})">` +
    path(outline, '#01020a', `${op(st.light ? 0.5 : 0.55)} transform="translate(${sx} ${sy})" filter="${u('pb')}"`) +
    `<clipPath id="dresser-c${i}"><path d="${outline}"/></clipPath>` +
    `<g clip-path="url(#dresser-c${i})"><g filter="${u('pa')}"><g transform="translate(${x} ${y})">${p.art}</g></g>` +
    path(all, '#efe2c4', op(i ? 0.1 : 0.2)) +
    `<g${M}>${lm.map((l) => `<path d="${all}" ${l}/>`).join('')}</g>` +
    `</g>` +
    path(`M${f(A[0])},${f(A[1])}Q${ctl(1.3)} ${f(B[0])},${f(B[1])}Q${ctl(2.1)} ${f(A[0])},${f(A[1])}Z`, u('pc')) +
    p.mounts +
    `</g>`
  )
}

export function part(st: State = DEFAULT_STATE): Part {
  L1 = ''
  L6 = ''
  KS = ''
  KC = ''
  lips = 'M1110,606h290v2.5h-290zM1110,867h290v1.4h-290z'
  hi = 'M1110,606h290v2h-290zM1110,867h290v1.4h-290z'
  lo = ''
  const { light, lava } = st
  const tv = st.tv && !light
  const side: Pt[] = [[1067.2, 591.4], [FX, FY], [FX, 906], [1067.2, 850]]
  const top: Pt[] = [[1067.2, 591.4], [1317.2, 591.4], [1400, FY], [FX, FY]]
  const [ox0, oy0] = open(COLS[1][0], ROWS[0][0])
  const [ox1, oy1] = open(COLS[1][1], ROWS[0][1])

  let defs =
    grain('ga', 256, 128, '.008 .24', 7, 1.9) +
    `<pattern id="dresser-gb" href="#dresser-ga" patternTransform="translate(97 41)"/>` +
    grain('gv', 64, 256, '.12 .008', 3, 1.6) +
    `<path id="dresser-gB" d="${BODY}"/><path id="dresser-gP" d="${GUARD}"/><path id="dresser-gH" d="${HEAD}"/><path id="dresser-gK" d="${PICKUPS}"/>` +
    `<path id="dresser-gG" d="${pj(GG)}"/><path id="dresser-gR" d="${pj(GR, 0.1)}"/><path id="dresser-gD" d="${pj(GD, 0.2)}"/><path id="dresser-gF" d="${pj(GF, 0.45)}"/>` +
    `<path id="dresser-gp" d="M-12,-3.5h24c4.5,0 4.5,7 0,7h-24c-4.5,0 -4.5,-7 0,-7z"/><clipPath id="dresser-gx"><polygon points="${pts(side)}"/></clipPath><clipPath id="dresser-gf"><use href="#dresser-gF"/></clipPath>` +
    (light ? lin('gz', 'x2="1"', [[0, '#fff4e0', 0], [0.2, '#fff4e0', 0.2], [0.38, '#fff4e0', 0]]) : '') +
    lin('gw', 'x2="1"', [[0.5, '#fff0d8', 0], [1, light ? '#fff0d8' : tv ? '#3c4a8c' : '#384060', light ? 0.65 : 0.28]]) +
    rad('ks', '', [[0, '#000000', 0.6], [1, '#000000', 0]]) +
    rad('kn', 'fx=".4" fy=".3"', [[0, '#e0b070'], [0.55, '#b0773e'], [1, '#4a2c14']]) +
    lin('os', V, [[0, '#020203', 0.75], [1, '#020203', 0]]) +
    rad('oh', 'cy="0" r=".5" gradientTransform="scale(1 2)"', [[0, '#020203', 0.7], [0.75, '#020203', 0.55], [1, '#020203', 0]]) +
    lin('ar', V, light ? [[0, '#0a0706', 0.8], [1, '#2a2420']] : [[0, '#0a0706'], [1, '#4a4440']]) +
    lin('cl', V, [[0, '#1a1c22'], [0.22, '#62646e'], [1, '#3c3e48']]) +
    lin('fs', V, [[0, '#010205', 0.85], [0.35, '#010205', 0.42], [1, '#010205', 0]]) +
    lin('ao', 'x1="1" x2="0"', [[0, '#010205', 0.6], [1, '#010205', 0]]) +
    lin('rw', 'x2=".42"', [[0, '#010205', light ? 0.45 : 0.55], [1, '#010205', 0]]) +
    lin('pc', V, light ? [[0, '#b4a690'], [1, '#7a6e5e']] : [[0, '#0e1222'], [1, tv ? '#20264a' : '#141830']]) +
    rad('p1', `${US} cx="49" cy="96" r="96"`, [[0, '#f0c470'], [0.3, '#de8a48'], [0.62, '#b4566c'], [1, '#5e4282']]) +
    lin('p2', V, [[0, '#2e3c5a'], [0.6, '#4c3648'], [1, '#2a2028']]) +
    rad('sp', '', [[0, '#f2c47c', 0.7], [1, '#f2c47c', 0]]) +
    rad('sb', 'cx=".45" cy=".62" r=".6"', [[0, '#e4aa4c'], [0.5, '#b0501e'], [0.85, '#4a1a0c'], [1, '#1a0a06']]) +
    blur('pb', 1.6, 0.06) +
    blur('pa', 0.8, 0.03) +
    blur('bl', 6, 0.25) +
    blur('gs', 3, 0.15) +
    (light ? '' : blur('ab', 4, 0.4))

  if (light) {
    defs +=
      lin('lf', 'x2=".45" y2="1"', [[0, '#c8ac90'], [1, '#86725f']]) +
      lin('ls', 'x1="1" x2=".1" y2="1"', [[0, '#9c8874'], [1, '#6a5c50']]) +
      lin('lt', '', [[0, '#d8c0a2'], [1, '#e4ccac']]) +
      lin('lp', V, [[0, '#c4b49a'], [1, '#ac9c84']]) +
      rad('kw', '', [[0, '#fff2d6', 0.75], [1, '#fff2d6', 0]]) +
      blur('ap', 1.5, 0.3)
  } else {
    defs +=
      lin('lf', V, [[0, '#1c2034'], [1, '#0d0e18']]) +
      lin('ls', 'x1="1" x2=".1" y2="1"', [[0, '#16206a'], [1, '#080c2a']]) +
      lin('sc', V, [[0, '#13162b'], [1, '#13162b', 0]]) +
      lin('qz', '', [[0, '#030308', 0.7], [0.4, '#030308', 0.6], [1, '#030308', 0]])
  }
  if (tv) {
    defs +=
      lin('l1t', '', [[0, '#3c54d8', 0.15], [0.43, '#3c54d8', 0.9], [1, '#3c54d8', 0.2]]) +
      rad('l1f', `${US} cx="1208" cy="606" r="260" gradientTransform="matrix(1 0 0 .35 0 393.9)"`, [[0, '#3048c8', 0.5], [1, '#3048c8', 0]]) +
      rad('l1p', `${US} cx="1208" cy="470" r="320"`, [[0, '#3a4cb8', 0.65], [0.45, '#2c3a94', 0.36], [1, '#2c3a94', 0]]) +
      rad('l1l', `${US} cx="1208" cy="485" r="330"`, [[0.35, '#4a5ab0', 0.6], [0.62, '#3a4676', 0.36], [0.92, '#3a4676', 0.12], [1, '#3a4676', 0]]) +
      rad('kh', '', [[0, '#5064c4', 0.6], [1, '#5064c4', 0]])
  }

  const under = light
    ? poly([[1067, 594], [1067, 850], [1062, 851], [1064, 596]], u('ao'), op(0.4))
    : poly([[1067, 594], [1067, 850], [1040, 852], [1052, 596]], u('ao'), ` filter="${u('ab')}"`)

  let body =
    poly([[1040, 848], [1322, 848], [1410, 909], [1060, 909]], '#010205', ` opacity=".9" filter="${u('bl')}"`) +
    poly([[1100, 902], [1410, 902], [1436, 985], [1074, 985]], u('fs'), ` filter="${u('bl')}"`) +
    poly([[1317, 591], [1600, 780], [1600, 850], [1317, 850]], u('rw'), ` filter="${u('bl')}"`)

  const lm = [`fill="${light ? u('lp') : '#141a30'}"`]
  if (tv) lm.push(`fill="${u('l1p')}"`)
  const pin = (x: number, yy: number): string =>
    (light ? `<circle cx="${f(x + 0.8)}" cy="${f(yy + 1.2)}" r="1.8" fill="#01020a"${op(0.45)}/>` : '') +
    `<circle cx="${f(x)}" cy="${f(yy)}" r="1.5" fill="${light ? '#a8362e' : tv ? '#2a3058' : '#151830'}"/>`
  const tape = (x: number, yy: number, a: number): string =>
    `<path d="M-6,-2.2h12v4.4h-12z" fill="${light ? '#ece0b0' : tv ? '#5a64a0' : '#2a2e48'}"${op(light ? 0.4 : 0.2)} transform="translate(${f(x)} ${f(yy)}) rotate(${a})"/>`
  body += poster({ x: 1136, y: 200, w: 98, h: 150, rot: -1.2, curl: 2, c: 7, art: concertArt(), mounts: pin(1140, 204) + pin(1230, 203.5) + pin(1140, 346) }, 0, st, lm)
  body += poster({ x: 1250, y: 168, w: 132, h: 184, rot: 0.9, curl: 0, c: 8, art: pulloutArt(), mounts: tape(1381, 169, 40) + tape(1381, 351, -40) + tape(1251, 351, 40) }, 1, st, lm)

  let alb = poly(side, OAK) + poly(side, u('gv'), op(0.6))
  alb += poly([[1104.1, 889], [1073.1, 849.5], [1073.1, 857.7], [1104.1, 898.3]], '#060406')
  alb += rect(FX, FY, FW, FH, OAK) + rect(FX, FY, FW, FH, u('ga'))
  alb += path('M1112,615h286v3h-286zM1112,694.5h286v3h-286zM1112,778h286v3h-286zM1112,864h286v3h-286zM1253.5,618h3v246h-3z', '#3a2414')
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 2; c++) {
      if (r === 0 && c === 1) continue
      alb += drawer(COLS[c][0], ROWS[r][0], COLS[c][1], ROWS[r][1], r, c, light)
    }
  }
  alb += rect(COLS[1][0], ROWS[0][0], COLS[1][1] - COLS[1][0], ROWS[0][1] - ROWS[0][0], '#020203')
  alb += rect(ox0, oy1, ox1 - ox0, 7, u('oh'))
  alb += poly([[COLS[1][0], ROWS[0][0]], [ox0, oy0], [ox0, oy1], [COLS[1][0], ROWS[0][1]]], '#6a4426')
  alb += rect(ox0, oy0, ox1 - ox0, oy1 - oy0, OAK) + drawer(ox0, oy0, ox1, oy1, 0, 1, light)
  const cloth = `M${f(ox0 + 18)},${f(oy0 - 1.6)}c8,-.6 19,-.4 27,.3c1.5,3 1,8 -.5,12.5c-6,1.5 -13,.6 -17,-2.5c-2.5,-.2 -4.5,-1.2 -5.5,-2.6c-1.5,-2 -3,-5 -4,-7.8z`
  defs += `<path id="dresser-cs" d="${cloth}"/>`
  alb += `<use href="#dresser-cs" fill="#010203" opacity=".45" transform="translate(.8 1.6)"/><use href="#dresser-cs" fill="${u('cl')}"/>`
  if (light) alb += stroke(`M${f(ox0 + 23)},${f(oy0 + 1)}c4,3 9,4 14,2M${f(ox0 + 27)},${f(oy0 + 5.5)}c3,2 7,2.5 11,1`, '#3c3e48', 0.8)
  alb += `<g fill="${u('ks')}">${KS}</g><g fill="${u('kn')}">${KC}</g>`
  alb += rect(FX, FY, FW, 9, u('gb'))
  alb += rect(1112, 615, 286, 4, '#020203', op(light ? 0.55 : 0.7))
  alb += rect(FX, 875, FW, 2, '#030304', op(0.7))
  alb += rect(FX, 877, FW, 29, u('ga'))
  alb += path('M1131,906C1131,900 1134,896 1141,896Q1255,890 1369,896C1376,896 1379,900 1379,906Z', u('ar'), light ? ` filter="${u('ap')}"` : '')
  if (!light) alb += rect(FX, 904, FW, 2, '#010103', op(0.8))
  alb += poly(top, OAK) + poly(top, u('ga'), op(0.7))
  alb += rect(1067, 591, 250, 1.2, '#020206', op(0.8))

  let map = poly(side, u('ls')) + poly(top, light ? u('lt') : '#1c2036') + rect(FX, FY, FW, FH, u('lf')) + rect(1399.5, oy0, ox1 - 1399.5, oy1 - oy0, light ? '#a68e77' : '#1a1e30')
  if (tv) map += `${poly(top, u('l1t'))}${rect(FX, FY, FW, FH, u('l1f'))}`
  body += alb + `<g${M}>${map}</g>`

  if (tv) body += `${path(lips, u('l1l'))}<g fill="${u('kh')}">${L1}</g>`
  if (light) {
    body += path(hi, '#ffe2ac', op(0.2)) + path(lo, '#1a0c04', op(0.3)) + `<g fill="${u('kw')}">${L6}</g>`
    body += rect(1112, 619, 286, 5, u('os'), op(0.5))
  } else {
    body += rect(1109, FY + 2, 1, 92, u('sc'))
    body += poly([[1067.2, 591.4], [1160, 591.4], [1160, 906], [FX, 906], [FX, 620], [1107, FY]], u('qz'))
  }

  const k = (d: string, l: string): string => (light ? l : d)
  const CH = k('#454c6e', '#d6d4ce')
  const use = (id: string, fill: string, extra = ''): string => `<use href="#dresser-${id}" fill="${fill}"${extra}/>`
  const fit = (y: number, h: number): string => {
    const [a, b] = g3(0, y, h)
    const c = [g3(1, y, h), g3(0, y + 1, h)].flatMap(([x, z]) => [Math.round((x - a) * 1e3) / 1e3, Math.round((z - b) * 1e3) / 1e3])
    return `matrix(${c.map((v) => String(v).replace(/^(-?)0\./, '$1.')).join(' ')} ${fz(a - y * c[2])} ${fz(b - y * c[3])})`
  }
  const [o0, o1] = g3(0, -80)
  const [jx, jy, hv] = [g3(1, -80), g3(0, -79), g3(0, -80, 1)].map(([a, b]) => [a - o0, b - o1])
  const det = jx[0] * jy[1] - jy[0] * jx[1]
  const hl = [(hv[0] * jy[1] - jy[0] * hv[1]) / det, (jx[0] * hv[1] - hv[0] * jx[1]) / det]
  const up = (h: number): string => ` transform="translate(${num(hl[0] * h)} ${num(hl[1] * h)})"`
  const mv = (h: number, dx = 0): string => ` transform="translate(${num(hv[0] * h + dx)} ${num(hv[1] * h)})"`
  defs +=
    `<g id="dresser-gq">${use('gp', k('#040406', '#0a090b'))}${use('gp', k('#0c0c12', '#1a181b'), up(0.25))}` +
    stroke('M-10.5,0h0m4.2,0h0m4.2,0h0m4.2,0h0m4.2,0h0m4.2,0h0', CH, 1.9, up(0.3)) +
    `</g><g id="dresser-gk">${stroke(`M0,0l${num(hl[0] * 0.6)},${num(hl[1] * 0.6)}`, k('#16182a', '#7e7462'), 8)}<circle r="3.9"${up(0.6)} fill="${k('#2a2e44', '#c8bea6')}"/></g>`
  const dash = [0]
  let dots = ''
  for (let n = 1, y0 = 0; n < 22; n++) {
    const y = 255 * (1 - 2 ** (-n / 12))
    dash.push(r1(y - y0 - 0.25), 0.5)
    const m = r1((y + y0) / 2 - 305)
    if (n === 12) dots += `M-4,${m}h0m8,0h0`
    else if (n % 2 && n !== 1 && n !== 11 && n !== 13) dots += `M0,${m}h0`
    y0 = y + 0.25
  }
  dash.push(99)
  let strs = ''
  for (let i = 0; i < 6; i++) strs += `M${fz(i * 4.2 - 10.5)},${[-45, -47, -49, -47, -49, -51][i]}L${fz(i * 2.8 - 7)},-305L-6,${-315 - 9 * i}`
  const POSTS = 'M-6,-315h0m0,-9h0m0,-9h0m0,-9h0m0,-9h0m0,-9h0'
  const [gx, gy] = g3(0, 0)
  body += ell(gx + (light ? 6 : 0), gy - 1, 28, 6, u('ks'))
  body += `<g clip-path="${u('gx')}" fill="#010205"><g filter="${u('gs')}"${op(light ? 0.55 : 0.4)} transform="translate(${light ? '10 2' : '7 0'})"><use href="#dresser-gG"/><use href="#dresser-gF"/><use href="#dresser-gD"/></g></g>`
  body +=
    `<g fill="${k(tv ? '#0a0c1a' : '#08080c', '#100e12')}">` +
    [1, 2, 3, 4, 5, 6, 7, 8].map((i) => `<use href="#dresser-gG" x="${num(hv[0] * i * -0.22)}"/>`).join('') +
    (light ? `<use href="#dresser-gG" x="${num(hv[0] * -1.7)}" fill="none" stroke="${u('gw')}" stroke-width=".9"/>` : '') +
    `</g>` +
    `<path d="${pl([[g3(8, -305, 0.45), g3(11, -152, 0.45), g3(5, -152, -0.35), g3(3, -305, -0.35)]])}z" fill="${k('#1a1824', '#9c6a36')}"/>` +
    use('gG', k('#1c2034', '#6a6058'), ' transform="translate(-.7 -.5)"') +
    use('gG', k('#0a0a10', '#131115')) +
    (light ? use('gG', u('gz')) : '') +
    `<use href="#dresser-gG" fill="none" stroke="${u('gw')}" stroke-width="${light ? 1.3 : 0.8}"/>` +
    use('gR', k('#2a2e42', '#b4a486'), ` stroke="${k('#08080c', '#3a3028')}" stroke-width=".5"`) +
    `<g transform="${fit(-80, 0)}">` +
    `<use href="#dresser-gq" y="-112"/><use href="#dresser-gq" y="-89"/><use href="#dresser-gq" transform="translate(0 -65) rotate(8)"/>` +
    `<path d="M-17,-57h34v19h-34z" fill="${k('#262a40', '#8e8c88')}"${up(0.1)}/>` +
    `<path d="M-12.3,-47h24.6" stroke="${CH}" stroke-width="6" stroke-dasharray="3.6 .6"${up(0.3)}/>` +
    stroke('M31,-88L38,-75', '#020203', 2.4, up(0.1)) +
    `<circle cx="34" cy="-82" r="2" fill="${k('#2a2e44', '#d8d0bc')}"${up(0.45)}/>` +
    `<use href="#dresser-gk" x="28" y="-60"/><use href="#dresser-gk" x="35" y="-45"/><use href="#dresser-gk" x="41" y="-31"/></g>` +
    stroke('M-12,-315h-8m8,-9h-8m8,-9h-8m8,-9h-8m8,-9h-8m8,-9h-8', CH, 4, ` transform="${fit(-340, -0.2)}"`) +
    use('gD', k('#16141e', '#8a5e30'), mv(-0.55)) +
    use('gD', k('#24222f', '#c4945a')) +
    use('gF', k('#0c0a0e', '#3a2216'), ` stroke="${k('#05050a', '#22140c')}" stroke-width=".4"`) +
    `<g clip-path="${u('gf')}"><path d="M0,-305V-120" transform="${fit(-210, 0.47)}" fill="none" stroke="${k('#2e3450', '#bdb8ae')}" stroke-width="26" stroke-dasharray="${dash.map(fz).join(' ')}"/></g>` +
    `<g transform="${fit(-210, 0.47)}">` +
    stroke(dots, k('#3a3e52', '#e8e0cc'), 2.2) +
    stroke('M-8,-305h16', k('#3a3e52', '#e8e2cc'), 1.6) +
    stroke(strs, k('#5a6288', '#e2ded6'), 0.7, op(light ? 0.8 : 0.6)) +
    stroke(POSTS, CH, 3.4) +
    `</g>` +
    stroke(pl([[g3(0, 4, -0.9)], [g3(-40, -186, -0.9)]], 'h0'), CH, 2.2)

  return { style: '.dresser-m{mix-blend-mode:multiply}.dresser-s{fill:none;stroke-linecap:round;stroke-linejoin:round}', defs, under, body }
}
