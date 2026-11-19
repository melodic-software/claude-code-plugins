import { VP, U, FLOOR_Y, CEILING_Y, DEFAULT_STATE, f, pts, type Part, type State } from '../lib.ts'

type Stop = readonly [number, string, number?]
type P = readonly [number, number]

const z = (v: number): string => String(Math.round(v * 100) / 100).replace(/^0\./, '.')
const stops = (list: readonly Stop[]): string =>
  list.map(([o, c, a]) => `<stop offset="${z(o)}" stop-color="${c}"${a === undefined ? '' : ` stop-opacity="${z(a)}"`}/>`).join('')
const lin = (id: string, x1: number, y1: number, x2: number, y2: number, list: readonly Stop[]): string =>
  `<linearGradient id="room-${id}" gradientUnits="userSpaceOnUse" x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}">${stops(list)}</linearGradient>`
const rad = (id: string, cx: number, cy: number, r: number, list: readonly Stop[], t = ''): string =>
  `<radialGradient id="room-${id}" gradientUnits="userSpaceOnUse" cx="${f(cx)}" cy="${f(cy)}" r="${f(r)}"${t ? ` gradientTransform="${t}"` : ''}>${stops(list)}</radialGradient>`
const box = (id: string, list: readonly Stop[], at = ''): string => `<radialGradient id="room-${id}"${at}>${stops(list)}</radialGradient>`
const poly = (p: readonly P[], fill: string, a = 1): string =>
  `<polygon points="${pts(p)}" fill="${fill}"${a < 1 ? ` fill-opacity="${z(a)}"` : ''}/>`
const rect = (x: number, y: number, w: number, h: number, fill: string, extra = ''): string =>
  `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h)}" fill="${fill}"${extra}/>`
const f2 = (v: number): string => String(Math.round(v * 100) / 100)
const blur = (id: string, x: number, y: number, w: number, h: number, sd: number): string =>
  `<filter id="room-${id}" x="${x}" y="${y}" width="${w}" height="${h}" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="${sd}"/></filter>`
const qmask = (id: string, q: number): string =>
  lin(id + 'g', 0, 0, 1600, 0, [
    [0.3, '#fff'],
    [0.35, '#fff', q],
    [0.7, '#fff', q],
    [0.76, '#fff'],
  ]) + `<mask id="room-${id}"><rect width="1600" height="1000" fill="url(#room-${id}g)"/></mask>`

function tile(id: string, size: number, freq: string, oct: number, seed: number, rgb: string, k: number, pt = ''): string {
  const h = f2(k / 2)
  const [r, g, b] = rgb.split(' ')
  return (
    `<filter id="room-f${id}" x="0" y="0" width="${size}" height="${size}" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">` +
    `<feTurbulence type="fractalNoise" baseFrequency="${freq}" numOctaves="${oct}" seed="${seed}" stitchTiles="stitch" result="n"/>` +
    `<feColorMatrix in="n" values="0 0 0 0 ${r} 0 0 0 0 ${g} 0 0 0 0 ${b} ${k} 0 0 0 -${h}" result="a"/>` +
    `<feColorMatrix in="n" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -${k} 0 0 0 ${h}" result="b"/>` +
    `<feMerge><feMergeNode in="a"/><feMergeNode in="b"/></feMerge></filter>` +
    `<pattern id="room-${id}" width="${size}" height="${size}" patternUnits="userSpaceOnUse"${pt ? ` patternTransform="${pt}"` : ''}>` +
    `<rect width="${size}" height="${size}" filter="url(#room-f${id})"/></pattern>`
  )
}

const D = 144 * U
const scale = (z: number): number => D / (D - z)
const screen = (x: number, yw: number, z: number): P => {
  const s = scale(z)
  return [VP.x + (x - VP.x) * s, VP.y + (yw - VP.y) * s]
}

const CAS = 27
const OPEN_X = 1425 + CAS
const HEAD_Y = FLOOR_Y - 80 * U
const HALL_Y = VP.y + (FLOOR_Y - VP.y) * 0.75
const W = 32
const TH = Math.asin(5 / W)
const XH = OPEN_X + W * U
const plan = (u: number, n: number): P => {
  const d = (W - u) * U
  return [XH - d * Math.cos(TH) + n * U * Math.sin(TH), d * Math.sin(TH) + n * U * Math.cos(TH)]
}
const door = (u: number, v: number, n = 0): P => {
  const [x, z] = plan(u, n)
  return screen(x, FLOOR_Y - v * U, z)
}
const quad = (u0: number, v0: number, u1: number, v1: number): P[] => [door(u0, v0), door(u1, v0), door(u1, v1), door(u0, v1)]

type Tone = readonly [string, number]
function panel(u0: number, v0: number, u1: number, v1: number, tones: (above: boolean) => readonly Tone[]): string {
  const g = 0.3
  const b = 1.5
  const o = quad(u0, v0, u1, v1)
  const m = quad(u0 + g, v0 + g, u1 - g, v1 - g)
  const i = quad(u0 + b, v0 + b, u1 - b, v1 - b)
  const tone = tones((door(u0, (v0 + v1) / 2)[1] ?? 0) < 470)
  const ring = (a: P[], c: P[], k: number): P[] => [a[k], a[(k + 1) % 4], c[(k + 1) % 4], c[k]]
  let s = `<path d="M${pts(o)}ZM${pts(m)}Z" fill="#03040a" fill-opacity=".5" fill-rule="evenodd"/>`
  for (let k = 0; k < 4; k++) s += poly(ring(m, i, k), tone[k][0], tone[k][1])
  return s
}

export function part(state: State = DEFAULT_STATE): Part {
  const L6 = state.light
  const L1 = state.tv && !L6

  let defs =
    lin('wall', 0, CEILING_Y, 0, FLOOR_Y, L6
      ? [
          [0, '#25366c'],
          [0.25, '#243468'],
          [0.6, '#223162'],
          [1, '#1f2d59'],
        ]
      : [
          [0, '#06070f'],
          [0.12, '#090b15'],
          [0.45, '#0c0e1a'],
          [0.85, '#0d0f1b'],
          [1, '#0b0d17'],
        ]) +
    lin('ceil', 0, 0, 0, CEILING_Y, L6
      ? [
          [0, '#3e3c3d'],
          [0.75, '#353438'],
          [1, '#2e2e34'],
        ]
      : [
          [0, '#040509'],
          [1, '#080a12'],
        ]) +
    lin('cao', 0, CEILING_Y - 4, 0, CEILING_Y + 70, [
      [0, '#020308', 0],
      [0.06, '#020308', L6 ? 0.3 : 0.5],
      [0.3, '#020308', L6 ? 0.1 : 0.18],
      [1, '#020308', 0],
    ]) +
    lin('floor', 0, FLOOR_Y, 0, 1000, L6
      ? [
          [0, '#3d3734'],
          [0.5, '#3c3532'],
          [1, '#423931'],
        ]
      : [
          [0, '#0b0c17'],
          [0.35, '#080912'],
          [1, '#05060b'],
        ]) +
    lin('fao', 0, FLOOR_Y, 0, FLOOR_Y + 22, [
      [0, '#010104', L6 ? 0.55 : 0.85],
      [0.3, '#010104', 0.35],
      [1, '#010104', 0],
    ]) +
    lin('base', 0, 823, 0, FLOOR_Y, L6
      ? [
          [0, '#4f3423'],
          [0.12, '#3a2619'],
          [0.25, '#2f1f15'],
          [0.85, '#291a11'],
          [1, '#160e09'],
        ]
      : [
          [0, '#141217'],
          [0.12, '#0f0d11'],
          [0.25, '#0d0c0f'],
          [0.85, '#0b0a0d'],
          [1, '#060609'],
        ]) +
    lin('bq', 0, 0, 1600, 0, L6
      ? [
          [0, '#46342c', 0],
          [0.3, '#46342c', 0.1],
          [0.37, '#46342c', 0.66],
          [0.68, '#46342c', 0.66],
          [0.76, '#46342c', 0.08],
          [1, '#46342c', 0],
        ]
      : [
          [0, '#0b0d17', 0],
          [0.3, '#0b0d17', 0.15],
          [0.37, '#0c0e19', 0.8],
          [0.68, '#0c0e19', 0.8],
          [0.76, '#0b0d17', 0.1],
          [1, '#0b0d17', 0],
        ]) +
    qmask('gq', 0.5) +
    qmask('bm', 0) +
    box('sink', [
      [0, '#020309', 1],
      [0.5, '#020309', 0.45],
      [1, '#020309', 0],
    ]) +
    lin('dr', 0, HEAD_Y, 0, FLOOR_Y, L6
      ? [
          [0, '#4a3120'],
          [0.5, '#3f2a1b'],
          [1, '#2c1d13'],
        ]
      : [
          [0, '#0a0b12'],
          [1, '#07080d'],
        ]) +
    lin('cs', 1425, 0, 1452, 0, L6
      ? [
          [0, '#4a3120'],
          [0.3, '#3d2819'],
          [1, '#2f1f14'],
        ]
      : [
          [0, '#0c0b0f'],
          [1, '#09080c'],
        ]) +
    lin('hall', 0, HEAD_Y + 8, 0, HALL_Y, [
      [0, L6 ? '#241c16' : '#09080b'],
      [0.62, L6 ? '#2a1f17' : '#0f0c0d'],
      [1, L6 ? '#2e2218' : '#1e140c'],
    ]) +
    lin('hfl', 0, HALL_Y, 0, FLOOR_Y, [
      [0, '#2a1a0e'],
      [1, '#1c120a'],
    ]) +
    blur('gb', 1446, 220, 52, 636, 0.6) +
    blur('sb', 1394, 468, 36, 50, 0.4) +
    blur('pb', 1490, 200, 120, 660, 0.5) +
    lin('edge', 0, HEAD_Y, 0, FLOOR_Y, L6
      ? [
          [0, '#5c3e27'],
          [0.6, '#4d3320'],
          [0.9, '#42291a'],
          [1, '#2e1d11'],
        ]
      : [
          [0, '#0f0f17'],
          [0.45, '#13131d'],
          [0.7, '#151419'],
          [0.84, '#251a12'],
          [0.94, '#2e1f10'],
          [1, '#22170d'],
        ]) +
    lin('sw', 1401, 0, 1423, 0, L6
      ? [
          [0, '#8f897c'],
          [0.15, '#827c70'],
          [0.7, '#726d62'],
          [1, '#5e594f'],
        ]
      : [
          [0, '#15161c'],
          [0.15, '#121319'],
          [1, '#0d0e13'],
        ]) +
    lin('tg', 1410.5, 0, 1413.1, 0, L6
      ? [
          [0, '#a49e90'],
          [0.45, '#7c776c'],
          [1, '#4c483f'],
        ]
      : [
          [0, '#1d1e25'],
          [0.45, '#15161c'],
          [1, '#0c0d12'],
        ]) +
    box('knob', L6
      ? [
          [0, '#d6b47a'],
          [0.25, '#8a6a3a'],
          [0.7, '#3e2c14'],
          [1, '#1a1209'],
        ]
      : [
          [0, '#24221f'],
          [0.25, '#1a1714'],
          [0.7, '#110f0c'],
          [1, '#09080a'],
        ], ' cx=".4" cy=".38"') +
    (L6
      ? ''
      : lin('wedge', 1460, 852, 1390, 985, [
          [0, '#7a4a20', 0.2],
          [0.4, '#6a3f1c', 0.08],
          [1, '#5a351a', 0],
        ])) +
    blur('soft', 1280, 830, 340, 180, 2.5) +
    rad('vig', 800, 500, 960, L6
      ? [
          [0.72, '#020309', 0],
          [0.9, '#020309', 0.12],
          [1, '#020309', 0.32],
        ]
      : [
          [0, '#020309', 0],
          [0.5, '#020309', 0],
          [0.78, '#020309', 0.28],
          [1, '#020309', 0.62],
        ], 'translate(800 500) scale(1 .64) translate(-800 -500)') +
    tile('stip', 200, '.6', 2, 4, L6 ? '.28 .35 .6' : '.12 .14 .23', 1.8) +
    tile('pop', 128, '.75', 2, 9, L6 ? '.32 .31 .32' : '.12 .13 .2', 3) +
    tile('pile', 200, '.6 1.2', 2, 2, L6 ? '.3 .27 .25' : '.12 .13 .2', 3, 'scale(1 .9)') +
    tile('mot', 256, '.03125 .0625', 3, 7, L6 ? '.28 .25 .23' : '.1 .11 .17', 3) +
    tile('grain', 128, '.75', 2, 5, '.75 .77 .85', 3.2) +
    lin('pn', 262, 130, 499, 175, L6
      ? [
          [0, '#1f5a34'],
          [0.6, '#1b5030'],
          [1, '#164227'],
        ]
      : [
          [0, '#080d0b'],
          [1, '#070b0a'],
        ]) +
    blur('ps', 245, 115, 270, 85, L6 ? 2.2 : 1)

  if (L1) {
    defs +=
      rad('l1', 1208, 485, 560, [
        [0, '#252e55', 0.62],
        [0.45, '#232b50', 0.4],
        [0.72, '#1c2242', 0.12],
        [1, '#1c2242', 0],
      ]) +
      lin('ar', 1425, 0, 1428.5, 0, [
        [0, '#2a3256', 0.3],
        [0.3, '#2a3256', 0.45],
        [1, '#2a3256', 0],
      ])
  }
  if (L6) defs += tile('wg', 256, '.35 .006', 2, 3, '.4 .28 .18', 2) + '<pattern id="room-wg2" href="#room-wg" patternTransform="translate(5 0)"/>'

  let body = rect(0, 0, 1600, 1000, 'url(#room-wall)')
  body += rect(0, CEILING_Y - 4, 1600, 74, 'url(#room-cao)')
  body += rect(0, 0, 1600, CEILING_Y, 'url(#room-ceil)') + rect(0, 0, 1600, CEILING_Y, 'url(#room-pop)', L6 ? ' opacity=".3"' : ' opacity=".6"')
  body += rect(0, CEILING_Y - 1.5, 1600, 2.5, '#020308', ` opacity="${L6 ? '.35' : '.5'}"`)

  const pen = 'M271 129.5Q385 146.5 498 160.5Q501 162 498 163.5Q385 175 271 183Z'
  const sleeve = 'M262 129.8L272 129.4L272 183.2L262 182.6Z'
  let pn = `<path d="${pen}" fill="url(#room-pn)"/>`
  pn += `<path d="M272 130Q385 146.5 497 161L497 162.6Q385 149.8 272 134Z" fill="#000" opacity=".18"/>`
  pn += `<path d="${pen}" fill="url(#room-pw)"/>`
  defs += lin('pw', 272, 0, 499, 0, [
    [0, '#000', 0.12],
    [0.22, '#fff', L6 ? 0.07 : 0.02],
    [0.48, '#000', 0.16],
    [0.72, '#fff', L6 ? 0.05 : 0.015],
    [1, '#000', 0.1],
  ])
  pn += `<path d="${sleeve}" fill="${L6 ? '#17181c' : '#060608'}"/>`
  const ink = L6 ? '#cfcdc2' : '#0c110f'
  pn +=
    `<g clip-path="url(#room-pc)"><g fill="${ink}" font-family="Rockwell, Georgia, Times New Roman, serif" font-weight="bold" transform="rotate(1.5 280 160)">` +
    `<text x="283" y="148.5" font-size="8.5" letter-spacing="1.6" textLength="72" lengthAdjust="spacingAndGlyphs">LANTERN HILL</text>` +
    `<text x="281" y="168.5" font-size="17" letter-spacing=".6" textLength="128" lengthAdjust="spacingAndGlyphs">NIGHTJARS</text></g></g>`
  defs += `<clipPath id="room-pc"><path d="${pen}"/></clipPath>`
  const tack = L6 ? '#b8ab8c' : '#121116'
  pn += `<path d="${pen}" fill="url(#room-stip)" opacity="${L6 ? '.3' : '.15'}"/>`
  for (const y of [133, 179]) pn += `<circle cx="267" cy="${y}" r="1.9" fill="${tack}"/>`
  const pennant =
    `<g filter="url(#room-ps)" opacity="${L6 ? '.5' : '.3'}">` +
    `<path d="${pen}" fill="#02030a" transform="translate(${L6 ? '-3 4.5' : '0 1.5'})"/>` +
    `<path d="${sleeve}" fill="#02030a" transform="translate(${L6 ? '-3 4.5' : '0 1.5'})"/></g>` +
    `<g filter="url(#room-pf)">${pn}</g>`
  defs += blur('pf', 255, 120, 255, 70, 0.3)

  body += rect(0, 823, 1425, 27, 'url(#room-base)')
  body +=
    '<g mask="url(#room-bm)">' +
    rect(0, 821, 1425, 2, '#020308', ' opacity=".3"') +
    rect(0, 822.6, 1425, 1.6, L6 ? '#6e4a30' : '#211d22', ' opacity=".55"') +
    rect(0, 826.2, 1425, 1, '#05060c', ' opacity=".35"') +
    '</g>'
  body += rect(0, 822.5, 1425, 28.5, 'url(#room-bq)')
  body += rect(0, CEILING_Y, 1600, FLOOR_Y - CEILING_Y, 'url(#room-stip)', ` opacity="${L6 ? '.18' : '.22'}"`)
  body += pennant

  body += rect(0, FLOOR_Y, 1600, 150, 'url(#room-floor)')
  body += rect(0, FLOOR_Y, 1600, 150, 'url(#room-pile)', L6 ? ' opacity=".4"' : ' opacity=".6"')
  body += rect(0, FLOOR_Y, 1600, 150, 'url(#room-mot)', L6 ? ' opacity=".14"' : ' opacity=".3"')
  body += rect(0, FLOOR_Y, 1600, 22, 'url(#room-fao)')

  const casing = poly(
    [
      [1425, HEAD_Y - CAS],
      [1600, HEAD_Y - CAS],
      [1600, HEAD_Y],
      [OPEN_X, HEAD_Y],
      [OPEN_X, FLOOR_Y],
      [1425, FLOOR_Y],
    ],
    'X',
  )
  body += rect(1421, HEAD_Y - CAS - 8, 4, FLOOR_Y - HEAD_Y + CAS + 8, 'url(#room-sink)', ' opacity=".3"')
  body += rect(1418, HEAD_Y - CAS - 10, 220, 14, 'url(#room-sink)', ' opacity=".5"')
  body += casing.replaceAll('"X"', '"url(#room-cs)"')
  if (L6) body += casing.replaceAll('"X"', '"url(#room-wg)"').replaceAll('/>', ' opacity=".22"/>')
  if (L1) body += casing.replaceAll('"X"', '"url(#room-l1)"')
  body += rect(1425, HEAD_Y - 2, 200, 2, '#05060c', ' opacity=".6"')
  if (L1) body += rect(1425, HEAD_Y - CAS, 3.5, FLOOR_Y - HEAD_Y + CAS, 'url(#room-ar)')
  if (L6) {
    body += rect(1425, HEAD_Y - CAS, 2.5, FLOOR_Y - HEAD_Y + CAS, '#6d4b31', ' opacity=".45"')
    body += rect(1425, HEAD_Y - CAS, 200, 2, '#6d4b31', ' opacity=".4"')
  }
  body += rect(1450, HEAD_Y, 2, FLOOR_Y - HEAD_Y, '#05060b', ' opacity=".7"')

  let gap = rect(OPEN_X, HEAD_Y, 40, HALL_Y - HEAD_Y, 'url(#room-hall)')
  gap += rect(OPEN_X, HALL_Y, 40, FLOOR_Y - HALL_Y, 'url(#room-hfl)')
  if (L6) gap += rect(OPEN_X, HALL_Y, 40, FLOOR_Y - HALL_Y, '#4a3a2c', ' opacity=".35"')
  gap += rect(OPEN_X, HALL_Y - 21, 40, 1.5, '#4a2f15', ' opacity=".22"')
  gap += rect(OPEN_X, HALL_Y - 1, 40, 3, '#0c0806', ' opacity=".3"')
  gap += rect(OPEN_X - 1, HEAD_Y, 41, 8, L6 ? '#2a1c12' : '#0b0c15')
  gap += rect(OPEN_X, HEAD_Y, 1.4, FLOOR_Y - HEAD_Y, 'url(#room-edge)', ' opacity=".8"')
  body += `<g filter="url(#room-gb)">${gap}</g>`

  const slab = [door(0, 0.6), door(0, 80), door(W, 80), door(W, 0.6)]
  body += poly([door(0, 0.6, -1.375), door(0, 80, -1.375), door(0, 80), door(0, 0.6)], 'url(#room-edge)')
  body += poly(slab, 'url(#room-dr)')
  if (L6) body += poly(slab, 'url(#room-wg)', 0.25)
  if (L1) body += poly(slab, 'url(#room-l1)')
  body += poly([door(0, 0.6), door(0, 80), door(0.25, 80), door(0.25, 0.6)], '#3a2a1a', 0.35)
  const rows: readonly [number, number][] = [
    [9, 28],
    [35, 59],
    [63.5, 75.5],
  ]
  const t0 = door(0, 80)
  const t1 = door(W, 80)
  body += poly([t0, t1, [t1[0], t1[1] + 1.5], [t0[0], t0[1] + 1.5]], '#05060c', 0.45)
  const tones = (above: boolean): readonly Tone[] =>
    L6
      ? [
          ['#000', 0.3],
          ['#000', 0.22],
          ['#7a5638', 0.38],
          ['#6a4a30', 0.28],
        ]
      : L1
        ? [
            above ? ['#27304f', 0.3] : ['#000', 0.42],
            ['#000', 0.3],
            above ? ['#000', 0.35] : ['#2a3354', 0.3],
            ['#2e3860', 0.32],
          ]
        : [
            ['#000', 0.4],
            ['#000', 0.3],
            ['#16151a', 0.3],
            ['#141419', 0.3],
          ]
  const fields = rows.map(([v0, v1]) => `M${pts(quad(6, v0 + 1.5, 12.25, v1 - 1.5))}Z`).join('')
  const grain = L6 ? `<path d="${fields}" fill="url(#room-dr)"/><path d="${fields}" fill="url(#room-wg2)" opacity=".25"/>` : ''
  body += `<g filter="url(#room-pb)">${grain}${rows.map(([v0, v1]) => panel(4.5, v0, 13.75, v1, tones)).join('')}</g>`
  if (L6) body += poly(slab, 'url(#room-mot)', 0.12)
  const kn = door(2.4, 36, 2.2)
  const ro = door(2.4, 36, 0.1)
  const ks = scale(plan(2.4, 2.2)[1])
  body += `<ellipse cx="${f(kn[0] + 3)}" cy="${f(kn[1] + 4)}" rx="12" ry="11" fill="url(#room-sink)" opacity=".6"/>`
  body += `<ellipse cx="${f(ro[0])}" cy="${f(ro[1])}" rx="${f(U * (L6 ? 0.7 : 0.9))}" ry="${f(U)}" fill="${L6 ? '#3a2a14' : '#0e0d0c'}"/>`
  if (L1) body += `<ellipse cx="${f(ro[0] - 2)}" cy="${f(ro[1] - 1)}" rx="3" ry="5" fill="#2c3350" opacity=".25"/>`
  if (L6) body += `<path d="M${f(ro[0] - U * 0.7)} ${f(ro[1])}A${f(U * 0.7)} ${f(U)} 0 0 1 ${f(ro[0])} ${f(ro[1] - U)}" fill="none" stroke="#8a6a3a" stroke-width=".6" opacity=".35"/>`
  body += poly([door(2.4, 36.5, 0.2), door(2.4, 36.9, 1.9), door(2.4, 35.1, 1.9), door(2.4, 35.5, 0.2)], L6 ? '#3c2a14' : '#14120e')
  body += `<ellipse cx="${f(kn[0])}" cy="${f(kn[1])}" rx="${f(1.12 * U * ks)}" ry="${f(1.12 * U * ks)}" fill="url(#room-knob)"/>`
  if (L1) body += `<circle cx="${f(kn[0] - 3)}" cy="${f(kn[1] - 3.5)}" r="1" fill="#7c88ad" opacity=".45"/>`
  body += `<circle cx="${f(kn[0] + 4.5)}" cy="${f(kn[1] + 4)}" r="1.4" fill="#5a3a1c" opacity=".35"/>`

  const sy = 493
  let sw = rect(1403, sy - 17.2, 21.5, 35, '#020309', ` rx="1.5" opacity="${L6 ? '.25' : '.45'}"`)
  if (L6) sw += rect(1403.2, sy - 15, 21.5, 35, '#03040b', ' rx="1.5" opacity=".3"')
  sw += rect(1401, sy - 17.5, 21.5, 35, 'url(#room-sw)', ' rx="1.2"')
  if (L1) sw += rect(1401, sy - 17.5, 21.5, 35, 'url(#room-l1)', ' rx="1.2"')
  for (const dy of [-13, 13]) sw += `<circle cx="1411.8" cy="${f(sy + dy)}" r="1" fill="${L6 ? '#4a463e' : '#0b0d17'}"/>`
  sw += rect(1410, sy - 4.5, 3.6, 9, L6 ? '#2b2924' : '#06070d', ' rx=".8"')
  const ty = L6 ? sy - 7.5 : sy + 0.5
  sw += rect(1412.5, L6 ? sy - 6.5 : sy + 0.8, 2, 7, '#04050a', ' rx=".8" opacity=".5"')
  sw += rect(1410.5, ty, 2.6, 7, 'url(#room-tg)', ' rx=".8"')
  body += `<g filter="url(#room-sb)">${sw}</g>`

  const lamp: P = [VP.x + 700 / 0.75, -370]
  const ray = (p: P, z: number): P => {
    const t = (z - p[1]) / (p[1] - lamp[1])
    return screen(p[0] + t * (p[0] - lamp[0]), FLOOR_Y, z)
  }
  const p1: P = [OPEN_X, 0]
  const p2 = plan(0, -1.375)
  let warm = poly([ray(p1, 20), ray(p1, 330), ray(p2, 330), ray(p2, 30)], 'url(#room-wedge)')
  const b0 = door(0, 0.3)
  const b1 = door(18, 0.3)
  warm += poly([b0, b1, [b1[0], b1[1] + 5], [b0[0], b0[1] + 6]], '#5a3818', 0.14)
  warm += poly([door(0, 0.7), door(18, 0.7), door(18, 0), door(0, 0)], '#7a4c22', 0.45)
  if (L6) warm = poly([door(0, 0), door(W, 0), [door(W, 0)[0] + 30, door(W, 0)[1] + 14], [b0[0] + 8, b0[1] + 10]], '#04050b', 0.45)
  body += `<g filter="url(#room-soft)">${warm}</g>`

  let over = rect(0, 0, 1600, 1000, 'url(#room-vig)')
  over += rect(0, 0, 1600, 1000, 'url(#room-grain)', ' opacity=".04" mask="url(#room-gq)"')

  return { defs, body, over }
}
