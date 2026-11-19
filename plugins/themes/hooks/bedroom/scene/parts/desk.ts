import { U, f, pts, unit, type Part, type State, DEFAULT_STATE } from '../lib.ts'

type Pt = [number, number]
type Stop = [number, string, number?]

const D = 144
const sBack = (s: number, depth: number): number => 1 / (1 / s + depth / D)
const toward = (p: Pt, s: number, s2: number): Pt => [800 + (p[0] - 800) * (s2 / s), 500 + (p[1] - 500) * (s2 / s)]
const deskY = (s: number): number => 500 + 124 * s

const n = (v: number): string => String(+v.toFixed(3)).replace(/^(-?)0\./, '$1.')
const st = (s: Stop[]): string =>
  s.map(([o, c, a]) => `<stop${o ? ` offset="${n(o)}"` : ''} stop-color="${c}"${a === undefined ? '' : ` stop-opacity="${n(a)}"`}/>`).join('')
const grad = (tag: string, id: string, c: string, s: Stop[], user: boolean): string =>
  `<${tag} id="desk-${id}"${c ? ` ${c}` : ''}${user ? ' gradientUnits="userSpaceOnUse"' : ''}>${st(s)}</${tag}>`
const lin = (id: string, c: string, s: Stop[], user = false): string => grad('linearGradient', id, c, s, user)
const rad = (id: string, c: string, s: Stop[], user = false): string => grad('radialGradient', id, c, s, user)
const H = (x1: number, x2: number): string => (x1 === 0 && x2 === 1 ? '' : `x1="${f(x1)}" x2="${f(x2)}"`)
const V = (y1: number, y2: number): string => `x2="0"${y1 ? ` y1="${f(y1)}"` : ''} y2="${f(y2)}"`
const u = (id: string): string => `url(#desk-${id})`
const poly = (p: Pt[], fill: string, x = ''): string => `<polygon points="${pts(p)}" fill="${fill}"${x}/>`
const path = (d: string, fill: string, x = ''): string => `<path d="${d}" fill="${fill}"${x}/>`
const rect = (x: number, y: number, w: number, h: number, fill: string, x2 = ''): string =>
  `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h)}" fill="${fill}"${x2}/>`
const ell = (cx: number, cy: number, rx: number, ry: number, fill: string, x = ''): string =>
  `<ellipse cx="${f(cx)}" cy="${f(cy)}" rx="${f(rx)}" ry="${f(ry)}" fill="${fill}"${x}/>`
const op = (o: number): string => ` opacity="${n(+o.toFixed(2))}"`
const use = (id: string, fill: string, x = ''): string => `<use href="#desk-${id}" fill="${fill}"${x}/>`

function box(x0: number, x1: number, s: number, h: number, depth: number) {
  const yb = deskY(s)
  const yt = yb - h * U * s
  const s2 = sBack(s, depth)
  const tl = toward([x0, yt], s, s2)
  const tr = toward([x1, yt], s, s2)
  const br = toward([x1, yb], s, s2)
  return {
    yb,
    yt,
    front: [[x0, yt], [x1, yt], [x1, yb], [x0, yb]] as Pt[],
    top: [[x0, yt], [x1, yt], tr, tl] as Pt[],
    side: [[x1, yt], tr, br, [x1, yb]] as Pt[],
  }
}

const TH = 0.21
const CX = 800 - 371 / 1.36
function T(x: number, y: number, z = 0): Pt {
  const a = (x - 429) / 1.36
  const s = sBack(1.36, (a / U) * Math.sin(TH) + z * Math.cos(TH))
  return [800 + (CX + a * Math.cos(TH) - z * U * Math.sin(TH) - 800) * s, 500 + ((y - 500) / 1.36) * s]
}
const tp = (d: string, z = 0): string =>
  d.replace(/(-?[\d.]+) (-?[\d.]+)/g, (_m, x, y) => {
    const p = T(+x, +y, z)
    return `${f(p[0])} ${f(p[1])}`
  })
const Q = (p: [number, number, number][], fill: string, x = ''): string => poly(p.map(([a, b, c]) => T(a, b, c)), fill, x)
function A(x: number, y: number, z: number): string {
  const o = T(x, y, z)
  const p = T(x + 10, y, z)
  const q = T(x, y + 10, z)
  const m = [(p[0] - o[0]) / 10, (p[1] - o[1]) / 10, (q[0] - o[0]) / 10, (q[1] - o[1]) / 10]
  return ` transform="matrix(${m.map((v) => +v.toFixed(4)).join(' ')} ${f(o[0] - m[0] * x - m[2] * y)} ${f(o[1] - m[1] * x - m[3] * y)})"`
}

function noise(id: string, w: number, h: number, freq: string, oct: number, seed: number, rgb: string, a: number, b: number): string {
  const [r, g, bl] = rgb.split(' ')
  return (
    `<filter id="desk-f${id}" filterUnits="userSpaceOnUse" x="0" y="0" width="${w}" height="${h}" color-interpolation-filters="sRGB">` +
    `<feTurbulence type="fractalNoise" baseFrequency="${freq}" numOctaves="${oct}" seed="${seed}" stitchTiles="stitch"/>` +
    `<feColorMatrix values="0 0 0 0 ${r} 0 0 0 0 ${g} 0 0 0 0 ${bl} ${a} 0 0 0 ${b}"/></filter>` +
    `<pattern id="desk-${id}" width="${w}" height="${h}" patternUnits="userSpaceOnUse"><rect width="${w}" height="${h}" filter="url(#desk-f${id})"/></pattern>`
  )
}

export function part(state: State = DEFAULT_STATE): Part {
  const L6 = state.light
  const L1 = state.tv && !L6
  const PC = state.pc
  const L3 = PC && !L6
  const L7 = state.lamp
  const k7 = L6 ? 0.6 : 1
  const P = <X,>(d: X, l: X): X => (L6 ? l : d)
  const on = (b: boolean, s: string): string => (b ? s : '')

  const style = PC
    ? `.desk-s circle{animation:desk-st 10s cubic-bezier(.6,0,1,.7) infinite;transform-box:view-box;transform-origin:0 0}` +
      `@keyframes desk-st{0%{transform:scale(.1);opacity:0}30%{opacity:1}86%{opacity:1}100%{transform:scale(1);opacity:0}}` +
      `.desk-hd{animation:desk-hd 13s steps(1,end) infinite}` +
      `@keyframes desk-hd{0%{opacity:.2}61%{opacity:.9}62%{opacity:.35}63%{opacity:.85}65%{opacity:.2}87%{opacity:.75}88%{opacity:.2}}`
    : ''

  const sm = 1.12
  const ms2 = sBack(sm, 4)
  const mSide: Pt[] = [[340, 504], toward([340, 504], sm, ms2), toward([340, 628], sm, ms2), [340, 628]]
  const spk1 = box(342, 373, sm, 7, 4.5)
  const spk2 = box(474, 505, 1.05, 5.5, 4.5)
  const top: Pt[] = [[292, 624], [554, 624], [505, 649], [190, 649]]
  const side: Pt[] = [[505, 649], [554, 624], [554, 850], [505, 920]]

  let defs =
    noise('wd', 240, 120, '0.006 0.2', 3, 4, P('.8 .64 .48', '.95 .72 .5'), 2.2, -1.05) +
    noise('fb', 128, 128, '1.3', 1, 7, P('.62 .66 .78', '.7 .7 .76'), 2.4, -1.25) +
    noise('pl', 160, 160, '0.3', 2, 9, '.7 .68 .62', 1.6, -0.66) +
    `<pattern id="desk-wv" href="#desk-wd" patternTransform="rotate(90)"/>` +
    lin('tp', H(190, 554), P([[0, '#110f13'], [0.4, '#16131a'], [1, '#1a1614']], [[0, '#7c5230'], [0.45, '#8a5a2e'], [1, '#946236']]), true) +
    lin('fe', H(190, 505), P([[0, '#120f12'], [0.5, '#181412'], [1, '#1b1613']], [[0, '#6e4828'], [1, '#7e5430']]), true) +
    lin('ar', H(190, 505), P([[0, '#9aa4c8', 0.08], [0.2, '#9aa4c8', 0.2], [0.5, '#9aa4c8', 0.05], [1, '#9aa4c8', 0]], [[0, '#d8a878', 0.25], [1, '#e8b888', 0.4]]), true) +
    lin('sd', V(630, 910), P([[0, '#14131a'], [0.4, '#0e0e15'], [1, '#08080e']], [[0, '#7a5232'], [0.5, '#5a3a20'], [1, '#3a2614']]), true) +
    lin('sb', H(520, 554), [[0, '#05060c', 0], [1, '#05060c', P(0.8, 0.5)]], true) +
    lin('lp', H(197, 298), P([[0, '#0e0e14'], [1, '#07070c']], [[0, '#6a4626'], [1, '#3c2816']]), true) +
    lin('dk', V(0, 1), [[0, '#03040a', 0], [1, '#03040a', 0.75]]) +
    rad('cs', 'cx=".5" cy=".5" r=".5"', [[0, '#020308', 0.85], [0.55, '#020308', 0.4], [1, '#020308', 0]]) +
    lin('bg', H(0, 1), P([[0, '#191816'], [0.55, '#201f1d'], [1, '#22211f']], [[0, '#58534a'], [0.55, '#666054'], [1, '#6c665a']])) +
    lin('ms', H(0, 1), P([[0, '#1c1c20'], [0.3, '#141519'], [1, '#0e0f14']], [[0, '#7a7364'], [0.3, '#6a6456'], [1, '#504b40']])) +
    lin('bl', H(0, 1), P([[0, '#111219'], [1, '#0c0d14']], [[0, '#26262b'], [1, '#1a1a1e']])) +
    lin('rc', V(0, 1), P([[0, '#090908'], [0.8, '#131311'], [1, '#22211e']], [[0, '#26241f'], [0.8, '#48443b'], [1, '#6a6458']])) +
    rad('sc', 'cx=".5" cy=".48" r=".62"', PC ? P([[0, '#0c0f17'], [0.7, '#080a10'], [1, '#040508']], [[0, '#141820'], [0.7, '#0e1117'], [1, '#08090c']]) : P([[0, '#0b0d0d'], [0.7, '#080a0a'], [1, '#040505']], [[0, '#232827'], [0.7, '#1b1f1f'], [1, '#101313']])) +
    rad('sh', 'cx=".35" cy=".3" r=".75"', [[0, P('#9aa8d8', '#c8d0d8'), PC ? P(0.06, 0.08) : P(0.05, 0.12)], [1, '#9aa8d8', 0]]) +
    lin('kb', H(210, 370), P([[0, '#1f2025'], [0.4, '#282a31'], [1, '#212329']], [[0, '#6e685a'], [0.5, '#7a7464'], [1, '#726c5e']]), true) +
    lin('cf', H(328, 528), P([[0, '#1c2234'], [0.04, '#12151f'], [0.14, '#0d0e15'], [0.6, '#0b0c13'], [1, '#0d0f18']], [[0, '#363946'], [0.05, '#262833'], [0.5, '#22242e'], [0.92, '#262833'], [1, '#383b48']]), true) +
    lin('cx', H(328, 528), P([[0, '#0a0b11'], [1, '#13151e']], [[0, '#22242e'], [1, '#3a3d4a']]), true) +
    lin('ct', V(0, 1), P([[0, '#1c2038'], [0.08, '#12152a'], [1, '#0a0b12']], [[0, '#4e5262'], [0.1, '#363946'], [1, '#22242d']])) +
    lin('cv', V(0, 1), [[0, '#030408', 0], [0.5, '#030408', P(0.15, 0.1)], [1, '#030408', P(0.6, 0.45)]]) +
    lin('cy', H(0, 1), P([[0, '#1c2030'], [0.1, '#0f1119'], [1, '#0a0b10']], [[0, '#3a3b42'], [0.12, '#222328'], [0.85, '#1c1d21'], [1, '#34353c']])) +
    lin('lf', H(0, 1), P([[0, '#141720'], [0.25, '#1e2230'], [0.55, '#07080c'], [1, '#0e1018']], [[0, '#26272c'], [0.25, '#7a7c84'], [0.5, '#222328'], [0.85, '#4a4c54'], [1, '#26272c']])) +
    lin('cd', H(0, 1), P([[0, '#0d0e13'], [0.45, '#16181f'], [1, '#1b1e28']], [[0, '#4a4c54'], [0.45, '#7e8088'], [0.8, '#64666e'], [1, '#8c8e96']])) +
    lin('tf', V(0, 1), P([[0, '#181818'], [1, '#0e0e0e']], [[0, '#4e4a40'], [1, '#3a372f']])) +
    lin('sp', V(0, 1), P([[0, '#201f1c'], [1, '#181715']], [[0, '#2a2a2e'], [1, '#1e1e22']])) +
    lin('lm', V(0, 1), P([[0, '#1a1a20'], [1, '#08080a']], [[0, '#4a4a52'], [0.4, '#2a2a30'], [1, '#141416']])) +
    lin('lh', H(0, 1), P([[0, '#1c1d26'], [0.35, '#0e0e12'], [1, '#08080b']], [[0, '#4e4e56'], [0.35, '#2a2a30'], [1, '#18181c']]))
  if (PC) {
    defs +=
      rad('sg', 'cx=".8" cy=".28" r=".5"', [[0, '#3c52a8', P(0.18, 0.1)], [1, '#3c52a8', 0]]) +
      rad('gn', 'cx=".5" cy=".5" r=".5"', [[0, '#8dff9a'], [0.25, '#3ad25a', 0.6], [1, '#2ab048', 0]]) +
      rad('am', 'cx=".5" cy=".5" r=".5"', [[0, '#ffd27a'], [0.25, '#ff9a20', 0.6], [1, '#ff8a10', 0]]) +
      rad('or', 'cx=".5" cy=".5" r=".5"', [[0, '#ff9a50'], [0.3, '#ff6a20', 0.5], [1, '#ff5a10', 0]])
  } else {
    defs += lin('rf', 'y2="1"', [[0.2, '#c8d4d0', 0], [0.34, '#c8d4d0', P(0.035, 0.07)], [0.48, '#c8d4d0', 0]])
  }
  if (L3) {
    defs +=
      rad('tm', 'cx=".22" cy=".7" r=".4"', [[0, '#b8c4e8', 0.12], [1, '#b8c4e8', 0]]) +
      rad('gl', 'cx=".5" cy=".5" r=".5"', [[0, '#7b8cc4', 0.1], [0.45, '#5a6aa8', 0.04], [1, '#5a6aa8', 0]])
  }
  defs += L6 ? rad('c6', 'cx=".5" cy=".15" r=".7"', [[0, '#c8c4d0', 0.09], [1, '#c8c4d0', 0]]) : rad('tw', 'cx=".55" cy="0" r=".55"', [[0, '#34324e', 0.55], [1, '#34324e', 0]])
  if (L1 || L6) defs += lin('rv', V(0, 1), [[0, P('#4a5a90', '#a88660'), 0], [0.45, P('#4a5a90', '#a88660'), 0.6], [1, P('#4a5a90', '#a88660'), 0.1]])
  if (L1) {
    defs +=
      lin('b1', H(190, 554), [[0.55, '#3a4a90', 0], [1, '#3a4a90', 0.42]], true) +
      lin('b2', H(0, 1), [[0, '#4a5a98', 0.6], [0.4, '#3a4a88', 0.2], [1, '#3a4a88', 0.04]]) +
      lin('b3', V(630, 910), [[0, '#2c3664', 0.8], [0.4, '#1e2448', 0.45], [1, '#0a0b14', 0]], true) +
      lin('c1', H(328, 528), [[0.82, '#26316a', 0], [0.93, '#1e2756', 0.5], [0.98, '#24306a', 0.8], [1, '#2c3a78', 0.95]], true) +
      lin('b4', H(0, 1), [[0.75, '#26306a', 0], [0.92, '#26306a', 0.7], [1, '#26306a', 0.25]]) +
      rad('cl', 'cx=".62" cy=".4" r=".6"', [[0, '#1a2140', 0.22], [1, '#1a2140', 0]])
  }
  if (L7) {
    defs +=
      rad('p7', `cx="480" cy="636" r="230" gradientTransform="matrix(1 0 0 .2 0 508.8)"`, [[0, '#ffcc88', 0.85], [0.35, '#ffb868', 0.62], [0.65, '#ffa050', 0.25], [1, '#ff9a48', 0]], true) +
      rad('q7', 'cx="516" cy="568" r="140"', [[0, '#ffb868', 0.7], [0.4, '#ffa858', 0.28], [1, '#ff9848', 0]], true) +
      rad('w7', 'cx=".5" cy=".5" r=".5"', [[0, '#ffb060', 0.59], [0.4, '#ffa050', 0.21], [0.7, '#ff9040', 0.06], [1, '#ff9040', 0]]) +
      rad('bu', 'cx=".5" cy=".62" r=".6"', [[0, '#fffaf0'], [0.25, '#ffd590'], [0.8, '#e08a3c'], [1, '#9a5a28']]) +
      rad('bm', 'cx=".5" cy=".5" r=".5"', [[0, '#ffe2b0', 0.5], [0.3, '#ffc880', 0.18], [1, '#ffb060', 0]])
  }
  defs +=
    `<path id="desk-cb" d="${tp('M336 601C336 585 349 576.5 370 575C396 573 462 573 488 575C509 576.5 523 585 523 601L522 631C521 652 517 668 517 684C517 702 520 718 519 729C518 741 507 747.5 492 748L366 748C351 747.5 340 741 339 729C338 718 341 702 341 684C341 668 337 652 336 631Z')}"/>` +
    `<path id="desk-cu" d="M336 774C335 766 342 763 352 763L506 763C517 763 523 767 522 775L521 789C520 797 512 801 500 801L350 801C338 801 336 797 336 790Z"/>`
  let sg = ''
  for (const [z, o] of [[1.2, 1], [2.4, 0.5], [3.5, 0.2]]) {
    const a = T(523, 660, 0)
    const b = T(523, 660, z)
    sg += `<use href="#desk-cb" transform="translate(${f(b[0] - a[0])} ${f(b[1] - a[1])})"${o < 1 ? op(o) : ''}/>`
  }
  defs += `<g id="desk-sx">${sg}</g>`

  let under =
    rect(288, 624, 266, 226, u('dk'), op(P(0.9, 0.8))) +
    poly([[288, 624], [554, 624], [554, 850], [288, 850]], '#04050a', op(P(0.55, 0.62))) +
    poly([[190, 920], [505, 920], [554, 850], [292, 850]], '#03040a', op(P(0.8, 0.55))) +
    poly([[186, 919], [509, 919], [512, 934], [182, 934]], u('dk'), ` transform="rotate(180 347 926.5)"${op(P(0.7, 0.8))}`) +
    ell(436, 952, 108, 24, u('cs'), op(P(0.8, 0.9))) +
    P(ell(531.5, 616, 15, 11, u('cs'), op(0.45)), ell(522, 622, 14, 6, u('cs'), op(0.45)))
  if (L6) under += ell(178, 905, 26, 22, u('cs'), op(0.5)) + ell(190, 628, 14, 24, u('cs'), op(0.35))
  if (L7) under += ell(524, 593, 38, 46, u('w7'), op(k7))

  const lit7 = (id: string, d: string, fill: string, g: string, o: number): string =>
    L7 ? ((defs += `<path id="desk-${id}" d="${d}"/>`), use(id, fill) + use(id, u(g), op(o))) : path(d, fill)

  let body = ''
  body +=
    poly([[288, 634.5], [543, 634.5], [543, 746], [288, 746]], P('#0a0a0f', '#271a10')) +
    rect(288, 743, 255, 3, P('#11131c', '#3a2817'), op(0.5)) +
    poly([[197.5, 658.2], [297.5, 631.8], [297.5, 850], [197.5, 920]], u('lp')) +
    poly([[197.5, 658.2], [297.5, 631.8], [297.5, 850], [197.5, 920]], u('wv'), op(P(0.025, 0.05))) +
    `<path d="M306 636C303 690 312 760 300 849M318 636C326 700 330 735 314 790C306 815 318 838 322 849" fill="none" stroke="${P('#0d0e15', '#141416')}" stroke-width="1.2"/>` +
    poly([[289, 849], [343, 849], [346, 846.6], [293, 846.6]], P('#18181d', '#6a665c')) +
    rect(289, 849, 54, 9, P('#0e0e11', '#46433c')) +
    ell(316, 860, 34, 3, u('cs'), op(0.8)) +
    on(PC, ell(338, 852, 4, 3, u('or'), op(P(0.55, 0.35))) + rect(336.6, 850.8, 2.8, 2.2, '#ff8a3a', op(0.75)))

  const ts2 = sBack(1.2, 17)
  const tTop: Pt[] = [[405, 760], [480, 760], toward([480, 760], 1.2, ts2), toward([405, 760], 1.2, ts2)]
  const tSide: Pt[] = [[480, 760], toward([480, 760], 1.2, ts2), toward([480, 920], 1.2, ts2), [480, 920]]
  const bay = P('#151513', '#423e35')
  body +=
    poly(tSide, P('#111217', '#2e2b25')) +
    poly(tTop, P('#1a1a19', '#5a554a')) +
    rect(405, 760, 75, 158, u('tf'), ` rx="1.5"`) +
    rect(405, 760, 75, 158, u('pl'), op(P(0.03, 0.06))) +
    rect(411, 771, 63, 12, bay) +
    rect(411, 788, 63, 12, bay) +
    rect(411, 806, 63, 7, bay) +
    rect(405, 822, 75, 1.2, P('#0c0c0b', '#2a2822')) +
    ell(466, 834, 4.6, 4.6, P('#121211', '#2e2b25')) +
    ell(466, 833.3, 3.6, 3.4, P('#1e1e1c', '#4e4a40'))
  for (let i = 0; i < 6; i++) body += rect(412, 880 + i * 4.5, 61, 1.6, P('#0b0b0a', '#24221d'))
  if (PC)
    body +=
      ell(460, 848, 5, 5, u('gn'), op(0.6)) +
      rect(459, 847.2, 2.2, 1.6, '#9dffa8') +
      `<g class="desk-hd" opacity=".2">${ell(470, 848, 5, 5, u('am'))}${rect(469, 847.2, 2.2, 1.6, '#ffc060')}</g>`
  body += rect(405, 916, 75, 3, '#050508')

  body +=
    rect(190, 658, 7.5, 262, P('#120f10', '#76502c')) +
    rect(190, 658, 7.5, 60, u('dk'), ` transform="rotate(180 193.8 688)" opacity=".2"`) +
    rect(498, 658, 7, 262, u('fe')) +
    on(L1 || L6, rect(503, 658, 2, 262, u('rv'), op(0.6))) +
    rect(498, 700, 7, 220, u('dk'), op(0.6)) +
    poly(side, u('sd')) +
    on(L1, poly(side, u('b3'))) +
    poly(side, u('wv'), op(0.06)) +
    poly(side, u('sb')) +
    on(L1, poly([[505, 649], [548, 627.1], [548, 635], [505, 658.2]], '#323b60', op(0.5))) +
    poly([[505, 658.2], [554, 631.8], [554, 633.4], [505, 660.2]], '#07080e', op(0.7)) +
    poly(top, u('tp')) +
    on(!L6, poly(top, u('tw'))) +
    on(L3, poly(top, u('tm'))) +
    on(L1, poly(top, u('b1'), op(0.6))) +
    poly(top, u('wd'), op(P(0.1, 0.16))) +
    poly([[292, 624], [554, 624], [553, 626.5], [289, 626.5]], '#04050a', op(P(0.6, 0.4))) +
    on(L7, poly(top, u('p7'), op(k7))) +
    rect(190, 649, 315, 9.2, u('fe')) +
    rect(190, 649, 315, 9.2, u('wd'), op(P(0.08, 0.12))) +
    on(L1, rect(190, 649, 315, 9.2, u('b1'), op(0.5))) +
    rect(190, 648.4, 315, 1.1, u('ar')) +
    on(L1, rect(190, 648.4, 315, 1.1, u('b1'))) +
    on(L7, rect(190, 648.4, 315, 1.1, u('p7'), op(k7))) +
    rect(190, 657.2, 315, 2.5, '#050608', op(P(0.7, 0.45))) +
    rect(468, 648.6, 5, 1.4, P('#3a3440', '#7a5a40'), op(0.6))

  const metal = P('#0e0e12', '#2a2a2f')
  const sd = 'M-3.5 0A3.5 2 0 0 1 3.5 0L12 19A12 3 0 0 1-12 19Z'
  const shade = path(sd, u('lh'))
  body +=
    on(L6, path(sd, '#03040a', ` transform="translate(531 548.5) rotate(40) scale(1.35)" opacity=".18"`)) +
    ell(529.5, 629.5, 19, 3.2, u('cs')) +
    `<path d="M540 626.6C543 626 546 626.4 549 624.6" fill="none" stroke="${P('#0c0c10', '#18181b')}" stroke-width="1"/>` +
    lit7('lb', 'M514.5 628.5C514.5 625 521 623.2 529.5 623.2C538 623.2 544.5 625 544.5 628.5A15 2.3 0 0 1 514.5 628.5Z', u('lm'), 'q7', k7) +
    rect(535.5, 625.3, 3.4, 1.4, P('#050506', '#0c0c0e'), ` rx=".6"`) +
    `<path d="M531.5 625V578C531.5 557 533.5 542 538.5 536.5C541.5 533.5 545 535.5 541.5 539.5L536 544.5" fill="none" stroke="${metal}" stroke-width="2.8" stroke-linecap="round"/>` +
    `<path d="M530.6 622V578C530.6 558 532.6 543 537.6 537.4" fill="none" stroke="${P('#3a3e52', '#7a7a84')}" stroke-width=".7" stroke-dasharray=".45 .45" opacity="${P(0.3, 0.45)}"/>` +
    on(L1, `<path d="M532.6 622V578C532.6 558 534.6 543 539.6 537.6" fill="none" stroke="#3a4a90" stroke-width=".7" opacity=".6"/>`) +
    `<g transform="translate(536 544.5) rotate(40) scale(1.35)">` +
    shade +
    on(L1, `<path d="M3.5 0L12 19L9 19.6L2.5 1Z" fill="#3a4a90" opacity=".45"/>`) +
    on(L6, `<path d="M-2 1.4L-8.6 17.6L-6.8 17.9L-.8 1.6Z" fill="#9a9aa2" opacity=".2"/>`) +
    ell(0, 19, 11.6, 2, L7 ? u('bu') : P('#040405', '#0a0a0c')) +
    `</g>`

  body +=
    ell(spk2.front[0][0] + 16, spk2.yb, 22, 2.5, u('cs')) +
    poly(spk2.side, u('bl')) +
    poly(spk2.top, P('#1a1b22', '#2a2a2f')) +
    poly(spk2.front, u('sp')) +
    rect(477, spk2.yt + 4, 27, 34, P('#121214', '#18181b'))

  const sx = 222
  const sy = deskY(1.18)
  body += ell(sx, sy + 1, 27, 3.2, u('cs'))

  body +=
    ell(270, 640, 48, 4, u('cs')) +
    poly(mSide, u('ms')) +
    on(L1, poly(mSide, u('b2'))) +
    on(L7, poly(mSide, u('q7'), op(k7))) +
    poly(mSide, u('dk'), op(P(0.5, 0.35))) +
    lit7('mb', 'M353.5 505C357 509 360 517 361.6 527.7V590C359.6 598 357 604 353.5 611Z', P('#111218', '#4a463c'), 'q7', k7) +
    rect(200, 504, 140, 124, u('bg'), ` rx="5"`) +
    rect(200, 504, 140, 124, u('pl'), ` rx="5" opacity="${P(0.05, 0.1)}"`) +
    rect(200, 504, 140, 124, u('dk'), ` rx="5" opacity="${P(0.35, 0.3)}"`) +
    rect(204, 504, 132, 0.9, P('#5a5870', '#a8a090'), op(P(0.3, 0.5))) +
    on(L1 || L6, rect(338.6, 507, 1.6, 118, u('rv'), op(0.4))) +
    rect(244, 626, 52, 10, P('#141412', '#3e3a32')) +
    rect(211, 514, 118, 89, u('rc'), ` rx="5"`) +
    rect(214, 517, 112, 83, u('sc'), ` rx="4"`)
  if (PC) {
    let stars = ''
    for (let i = 0; i < 18; i++) {
      const a = unit(i, 1) * Math.PI * 2
      const rr = 0.3 + unit(i, 2) * 0.7
      stars += `<circle cx="${f(Math.cos(a) * 53 * rr)}" cy="${f(Math.sin(a) * 39 * rr)}" r="${f(0.4 + unit(i, 3) * 0.45)}" style="animation-delay:-${f(10 + unit(i, 4) * 10)}s"/>`
    }
    body += `<g class="desk-s" transform="translate(270 558.5)" fill="#d4dcff" opacity=".6">${stars}</g>` + rect(214, 517, 112, 83, u('sg'), ` rx="4"`)
  } else {
    body += rect(214, 517, 112, 83, u('rf'), ` rx="4"`)
  }
  body +=
    rect(214, 517, 112, 83, u('sh'), ` rx="4"`) +
    rect(214, 517, 112, 83, u('fb'), ` rx="4" opacity=".05"`) +
    rect(216, 601.6, 108, 1, P('#3a3a40', '#8a8474'), op(0.25)) +
    ell(319, 616, 2.4, 2.4, P('#121211', '#3a372f')) +
    on(PC, ell(319, 616, 3.5, 3.5, u('gn'), op(0.45)) + rect(318.4, 615.4, 1.2, 1.2, '#8dff9a', op(0.8))) +
    rect(298, 614.5, 5, 2.4, P('#1a1917', '#4e4a40'), ` rx="1"`) +
    rect(307, 614.5, 5, 2.4, P('#1a1917', '#4e4a40'), ` rx="1"`) +
    rect(264, 612, 12, 2.4, P('#33322e', '#7a7464'), op(0.6))

  body +=
    poly(spk1.side, u('bl')) +
    poly(spk1.top, P('#1a1b22', '#2a2a2f')) +
    poly(spk1.front, u('sp')) +
    rect(345, spk1.yt + 4, 25, 36, P('#0f0f11', '#161618'), ` rx="1.5"`) +
    rect(345, spk1.yt + 4, 25, 36, u('fb'), op(0.12)) +
    on(L1, rect(371.6, spk1.yt, 1.4, 60, u('rv'), op(0.5)))

  const kf = 1.165
  const kb = 1.125
  const kx0 = 205
  const kx1 = kx0 + 17 * U * kf
  const kyF = deskY(kf)
  const kyB = deskY(kb)
  const kTF = kyF - 0.9 * U * kf
  const kTB = kyB - 1.4 * U * kb
  const kBack = (x: number): number => 800 + (x - 800) * (kb / kf)
  const kTop: Pt[] = [[kx0, kTF], [kx1, kTF], [kBack(kx1), kTB], [kBack(kx0), kTB]]
  body +=
    poly([[kx0 - 2, kyF + 1], [kx1 + 2, kyF + 1], [kBack(kx1) + 2, kyB], [kBack(kx0) - 2, kyB]], u('cs')) +
    poly(kTop, P('#141418', '#5e5850')) +
    rect(kx0, kTF, kx1 - kx0, kyF - kTF, P('#1b1a1d', '#4e493f')) +
    rect(kx0, kTF, kx1 - kx0, 0.8, P('#3a3b44', '#9a9384'), op(0.6))
  let keys = ''
  for (let r = 0; r < 6; r++) {
    const t = (5.6 - r) / 6.4
    const y = kTF + (kTB - kTF) * t
    const xl = kx0 + (kBack(kx0) - kx0) * t + 2
    const xr = kx1 + (kBack(kx1) - kx1) * t - 2
    const w = xr - xl
    const seg = (a: number, b: number): string => `M${f(xl + w * a)} ${f(y)}H${f(xl + w * b)}`
    const d = r === 0 ? seg(0, 0.14) + seg(0.47, 0.63) + seg(0.66, 0.8) + seg(0.82, 0.92) : seg(0, 0.63) + seg(0.66, 0.79) + seg(0.82, 1)
    keys += `<path d="${d}" stroke-dashoffset="${[0, 2.1, 3.7, 1.2, 2.9, 0.6][r]}" stroke-opacity="${r < 2 ? 0.42 : 0.55}"/>`
  }
  body +=
    `<g fill="none" stroke="${u('kb')}" stroke-width="1.05" stroke-dasharray="5.4 1.3">${keys}</g>` +
    `<path d="M${f(kx0 + 2 + 0.094 * (kx1 - kx0) * 1.5)} ${f(kTF - 0.9)}H${f(kx0 + 0.47 * (kx1 - kx0))}" fill="none" stroke="${u('kb')}" stroke-width="1.05"/>` +
    on(L7, poly(kTop, u('p7'), op(0.6 * k7)))

  body +=
    poly([[300, 649.2], [366, 649.2], [370, 645.3], [307, 645.3]], P('#0e1120', '#1a2038')) +
    poly([[300, 649.2], [366, 649.2], [370, 645.3], [307, 645.3]], u('fb'), op(0.08)) +
    `<path d="M331 637C334 633 341 632 348 630.4C353 629.4 357 628 362 626.4M238 628C228 625.6 219 629 210 627.4C204 626.4 201 628 199 630" fill="none" stroke="${P('#1d1e26', '#4a463e')}" stroke-width="1"/>` +
    ell(330, 649, 13, 2, u('cs')) +
    lit7('mo', 'M319 647.6C318.4 641 322.4 636.2 329.4 635.8C336.4 635.8 341 640 340.4 647C340 649.4 335.4 650 329.4 650C323.4 650 319.4 649.4 319 647.6Z', P('#1e1d1b', '#6e685a'), 'p7', 0.6 * k7) +
    path('M321 641C323 637.4 326.4 636.4 329.4 636.3C333 636.3 336.6 637.6 338.4 640.6C333 639 326 639 321 641Z', P('#3a3c48', '#9a9384'), op(0.7)) +
    rect(329.2, 636.2, 0.6, 3.4, '#0c0c0e', op(0.7)) +
    on(L1, path('M338.6 641C340 643 340.2 646 339.6 648.4L340.4 647.6C341 645 340.6 642.6 338.6 641Z', '#4a5a90', op(0.25)))

  const sTop = sy - 4.6 * U * 1.18
  body +=
    rect(sx - 25, sy - 5, 50, 6, P('#0e0e12', '#1e1e22'), ` rx="2"`) +
    ell(sx, sy - 5, 25, 2.2, P('#17171c', '#2e2e34')) +
    path(`M${sx - 21} ${f(sy - 20)}V${f(sy - 6.5)}A21 1.8 0 0 0 ${sx + 21} ${f(sy - 6.5)}V${f(sy - 20)}Z`, u('cd')) +
    path(`M${sx - 21} ${f(sy - 12)}A21 1.8 0 0 0 ${sx + 21} ${f(sy - 12)}`, 'none', ` stroke="#07080c" stroke-width=".6" opacity=".5"`) +
    ell(sx, sy - 20, 21, 1.8, P('#22252f', '#9a9ca6')) +
    ell(sx, sy - 20, 3.4, 0.6, P('#0c0c10', '#3a3a40')) +
    rect(sx - 1.2, sTop + 4, 2.4, sy - 20 - sTop - 4, P('#1a1b22', '#4a4a52'), op(0.7)) +
    path(`M${sx - 22} ${f(sy - 5)}V${f(sTop + 9)}C${sx - 22} ${f(sTop + 2)} ${sx - 12} ${f(sTop)} ${sx} ${f(sTop)}C${sx + 12} ${f(sTop)} ${sx + 22} ${f(sTop + 2)} ${sx + 22} ${f(sTop + 9)}V${f(sy - 5)}Z`, P('#8090c0', '#d8dce8'), op(P(0.045, 0.1))) +
    rect(sx - 21.2, sTop + 8, 0.9, sy - sTop - 14, P('#7a8cd0', '#ffffff'), op(P(0.12, 0.3))) +
    on(L1, rect(sx + 19.8, sTop + 8, 1.2, sy - sTop - 14, '#7a8cd0', op(0.4))) +
    path(`M${sx - 14} ${f(sTop + 2.6)}C${sx - 6} ${f(sTop + 0.6)} ${sx + 6} ${f(sTop + 0.6)} ${sx + 14} ${f(sTop + 2.6)}`, 'none', ` stroke="${P('#9aa8e0', '#ffffff')}" stroke-width=".7" opacity="${P(0.12, 0.35)}"`)

  let chair = ''
  chair +=
    `<g transform="matrix(.953 0 0 .953 20.5 18.8)">` +
    poly([[427, 930], [438, 936], [371, 1035], [340, 1035]], u('cy')) +
    poly([[438, 936], [449, 930], [538, 1035], [508, 1035]], u('cy')) +
    path('M430 926L345 921.5C339 921.5 335.5 925 336.5 929L341 931.5L432 937Z', u('cy')) +
    path('M444 926L527 921C533 921 537 924 536 928.5L531.5 931L442 937Z', u('cy')) +
    path('M440 928L451 924L462 909L456 908Z', P('#0b0c12', '#1a1a1e')) +
    path('M328 932C328 926 335 924 342 925C349 926 351 931 350 936L349 945C348 950 343 952 337 952C331 952 327 949 327 944Z', u('cy')) +
    path('M523 931C523 925 530 923 537 924C543 925 545 930 544 935L543 944C542 949 537 951 532 951C526 951 522 948 522 943Z', u('cy')) +
    path('M452 911C452 907 457 906 461 906.5C465 907 466 910 466 913L465.5 938C465 941 462 942 459 942C455 942 452 940 452 937Z', u('cy')) +
    ell(436, 931, 17, 5.5, P('#0a0b10', '#121216')) +
    rect(423, 911, 26, 20, u('lf'), ` rx="1.5"`) +
    rect(424.5, 893, 23, 20, u('lf'), ` rx="1.5"`) +
    rect(426, 866, 20, 29, u('lf'), ` rx="1.5"`) +
    rect(430.5, 814, 11, 54, u('lf')) +
    on(L1, rect(423, 814, 26, 117, u('b4'))) +
    on(L6, ell(436, 818, 14, 6, u('cs'), op(0.7))) +
    '</g>'
  for (const [xo, pad] of [[314.4, P('#131624', '#2e2f36')], [519.2, u('cy')]] as [number, string][]) {
    const xu = xo + 12.2
    chair +=
      `<rect x="${f(xu - 4.8)}" y="712" width="9.5" height="80" fill="${u('cy')}"${A(xu, 750, 6)}/>` +
      Q([[xo, 700.2, 3], [xo + 24.4, 700.2, 3], [xo + 24.4, 700.2, 12], [xo, 700.2, 12]], pad) +
      `<rect x="${xo}" y="700.2" width="24.4" height="12.7" rx="5" fill="${u('cy')}"${A(xu, 706, 3)}/>`
  }
  chair +=
    Q([[336, 763.8, 0.5], [522, 763.8, 0.5], [522, 763.8, 13], [336, 763.8, 13]], P('#0d0f18', '#2a2c36')) +
    `<g${A(437, 808, 5)}>${rect(404, 801, 66, 16, P('#090a0e', '#131316'), ` rx="2"`)}</g>` +
    Q([[468, 808, 7], [500, 806, 7], [500.4, 810, 7], [468, 813, 7]], P('#0d0f16', '#1e1e22')) +
    Q([[468, 808, 7], [500, 806, 7], [500.2, 807, 7], [468, 809.2, 7]], P('#151a2c', '#5a5a62'), op(0.5)) +
    on(L1, Q([[468, 808, 7], [500, 806, 7], [500.2, 807, 7], [468, 809.2, 7]], '#2c3a70', op(0.5))) +
    `<g${A(429, 782, 0.5)}>${use('cu', u('cy'))}${use('cu', u('cv'))}${on(L1, use('cu', u('c1')))}${rect(346, 763.4, 166, 1.6, P('#1c2132', '#4a4c58'), op(0.5))}</g>` +
    path(tp('M420 740L440 740L442 800L418 800Z', -0.4), u('cy'))
  const t0 = T(429, 573, 0)
  const t1 = T(429, 573, 3.5)
  chair +=
    use('sx', u('cx')) +
    on(L1, use('sx', u('c1'))) +
    on(L7, use('sx', u('q7'), op(k7))) +
    use('cb', u('ct'), ` transform="translate(${f(t1[0] - t0[0])} ${f(t1[1] - t0[1])})" opacity=".6"`) +
    use('cb', u('ct'), ` transform="translate(${f((t1[0] - t0[0]) / 2)} ${f((t1[1] - t0[1]) / 2)})"`) +
    use('cb', u('cf')) +
    on(L1, use('cb', u('cl')) + use('cb', u('c1'))) +
    use('cb', u('cv')) +
    use('cb', u('pl'), op(P(0.03, 0.06))) +
    on(L6, use('cb', u('fb'), op(0.05)) + use('cb', u('c6')))
  body += chair

  let over = ''
  if (L3) over += ell(270, 560, 110, 92, u('gl')) + ell(270, 642, 95, 16, u('tm'), op(0.6))
  if (L7) over += ell(521, 567, 32, 26, u('w7'), op(0.36 * k7)) + ell(519.5, 564.5, 26, 15, u('bm'), op(k7))

  return { style, defs, under, body, over }
}
