import { VP, f, pts, unit, type Part, type State } from '../lib.ts'

type Stop = readonly [number, string, number?]
type Pt = readonly [number, number]

const st = (s: readonly Stop[]): string =>
  s.map(([o, c, a]) => `<stop offset="${o}" stop-color="${c}"${a === undefined ? '' : ` stop-opacity="${a}"`}/>`).join('')
const lg = (id: string, x1: number, y1: number, x2: number, y2: number, s: readonly Stop[], extra = ''): string =>
  `<linearGradient id="tv-${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"${extra}>${st(s)}</linearGradient>`
const US = ' gradientUnits="userSpaceOnUse"'
const rg = (id: string, s: readonly Stop[], extra = ''): string => `<radialGradient id="tv-${id}"${extra}>${st(s)}</radialGradient>`
const R = (x: number, y: number, w: number, h: number, fill: string, extra = ''): string =>
  `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h)}" fill="${fill}"${extra}/>`
const P = (p: readonly Pt[], fill: string, extra = ''): string => `<polygon points="${pts(p)}" fill="${fill}"${extra}/>`
const E = (cx: number, cy: number, rx: number, ry: number, fill: string, extra = ''): string =>
  `<ellipse cx="${f(cx)}" cy="${f(cy)}" rx="${f(rx)}" ry="${f(ry)}" fill="${fill}"${extra}/>`
const D = (d: string, fill: string, extra = ''): string => `<path d="${d}" fill="${fill}"${extra}/>`
const u = (id: string): string => `url(#tv-${id})`
const o = (v: number): string => ` opacity="${Math.round(v * 1000) / 1000}"`
const fall = (c: string, a0: number, p: number): Stop[] =>
  [0, 0.25, 0.5, 0.75, 1].map((t) => [t, c, Math.round(a0 * (1 - t) ** p * 1000) / 1000] as const)
const HAND = 'font-family="Ink Free, Segoe Print, Bradley Hand, cursive"'
const MONO = 'font-family="monospace" font-weight="bold" font-size="10"'
const CS = ' color-interpolation-filters="sRGB"'

const GX = 1137
const GY = 432
const GW = 141
const GH = 106

const back = (x: number, y: number): Pt => [x + (VP.x - x) * 0.027, y + (VP.y - y) * 0.027]

function digits(x0: number, y: number, text: string, lit: boolean): string {
  const w = 3.1
  const h = 6
  const t = 0.75
  const on: Record<string, string> = { '0': 'abcdef', '1': 'bc', '2': 'abdeg' }
  let d = ''
  let x = x0
  for (const ch of text) {
    if (ch === ':') {
      if (lit) d += `M${f(x + 0.6)} ${f(y + 1.5)}v.8M${f(x + 0.6)} ${f(y + 4.1)}v.8`
      x += 2
      continue
    }
    const m = t / 2
    const seg: Record<string, readonly [number, number, number, number]> = {
      a: [x + t / 2, y + m, 1, w - t],
      b: [x + w - m, y + t / 2, 0, h / 2 - t / 2],
      c: [x + w - m, y + h / 2, 0, h / 2 - t / 2],
      d: [x + t / 2, y + h - m, 1, w - t],
      e: [x + m, y + h / 2, 0, h / 2 - t / 2],
      f: [x + m, y + t / 2, 0, h / 2 - t / 2],
      g: [x + t / 2, y + h / 2, 1, w - t],
    }
    for (const k of lit ? on[ch] : 'abcdefg') {
      const [sx, sy, hz, len] = seg[k]
      d += `M${f(sx)} ${f(sy)}${hz ? 'h' : 'v'}${f(len)}`
    }
    x += w + 1.2
  }
  return `<path d="${d}" stroke="${lit ? '#39c47a' : '#0c2218'}" stroke-width="${t}" fill="none"/>`
}

const hex = (c: string): number[] => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16))
const toHex = (v: readonly number[]): string =>
  '#' + v.map((x) => Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, '0')).join('')
const add = (base: string, light: string, t: number): string => {
  const b = hex(light)
  return toHex(hex(base).map((x, i) => x + b[i] * t))
}

const HM = 'matrix(1.12 0 0 1.12 -158 -44)'
const C_BODY = 'M1184 425C1180 410 1184 392 1198 386C1212 381 1228 380 1240 382L1270 396C1279 402 1282 413 1281 425Z'
const C_HEAD = 'M1240.6 390C1240.4 381.5 1248.6 376.6 1259 376.6C1269.4 376.6 1277.6 381.5 1277.4 390C1278.6 394.5 1277.4 399.5 1273.4 403.2C1268.6 407.6 1249.4 407.6 1244.6 403.2C1240.6 399.5 1239.4 394.5 1240.6 390Z'
const C_CAP = 'M1240.6 392.5C1240 382 1248.6 376.6 1259 376.6C1269.4 376.6 1278 382 1277.4 392.5C1275 396.2 1270.4 395.6 1266.6 393.2C1263.8 390.4 1261.2 385.4 1259.7 380.6L1258.3 380.6C1256.8 385.4 1254.2 390.4 1251.4 393.2C1248 396.8 1243.4 398.6 1240.8 396Z'
const C_SADDLE = 'M1189 386C1198 378 1214 376 1226 377C1228 386 1223 394 1214 397C1205 400 1196 400.5 1190 398Z'
const C_RUMP = 'M1182 411C1181 403 1184 395 1190 391C1194 397 1193 406 1189 412C1186.5 415 1183 414.5 1182 411Z'
const C_TAILTOP = 'M1184 419C1166 420.5 1144 420.5 1129 421'
const C_TAIL = 'M1129 420.6C1124.6 422.6 1123.4 434 1123.6 447'
const C_TIP = 'M1123.6 444C1123.7 449 1125.6 456.6 1129.4 457.2'

const LV_BASE = 'M1359 605C1359 602.5 1360 601 1361.5 600L1367.2 557L1384.8 557L1390.5 600C1392 601 1393 602.5 1393 605Z'
const LV_GLASS = 'M1368.6 555C1366 549 1364 543 1364.2 537C1365 523 1368.5 507 1370.6 494L1381.4 494C1383.5 507 1387 523 1387.8 537C1388 543 1386 549 1383.4 555Z'
const LV_CAP = 'M1370 495L1372.8 480.5Q1376 478.6 1379.2 480.5L1382 495Z'

export function part(state: State): Part {
  const L = state.light
  const k = (d: string, l: string): string => (L ? l : d)
  const scr = !state.tv ? 'off' : state.console ? 'game' : state.tape ? 'tape' : 'blue'
  const on = scr !== 'off'
  const lc = scr === 'blue' ? '#2a48e8' : scr === 'tape' ? '#6a5c8e' : '#3c4ca8'
  const ga = scr === 'off' ? 0 : scr === 'blue' ? 1 : scr === 'tape' ? 0.6 : 0.35
  const la = L ? 0 : ga
  const PC = '#a050f0'
  const pa = state.lava ? (L ? 0.45 : 1) : 0
  const fur = (c: readonly string[], r: number): Stop[] =>
    [0, 0.5, 1].map((t, i) => [t, add(c[i], lc, r * la * [0.03, 0.08, 0.26][i])] as const)

  let style =
    '@keyframes tv-ef{0%,92%,100%{transform:none}93.5%{transform:rotate(-14deg)}95%{transform:rotate(4deg)}96.5%{transform:none}}.tv-ef{transform-origin:1269px 381px;animation:tv-ef 47s ease-in-out infinite}' +
    '@keyframes tv-tt{0%,88%,100%{transform:none}92%{transform:rotate(16deg)}96%{transform:rotate(-4deg)}}.tv-tt{transform-origin:1123.6px 447px;animation:tv-tt 60s ease-in-out infinite}'
  if (on) {
    style +=
      '@keyframes tv-br{50%{opacity:.94}}.tv-br{animation:tv-br 8s ease-in-out infinite}' +
      '@keyframes tv-sd{50%{opacity:.05}}.tv-sd{animation:tv-sd 8s ease-in-out infinite}'
  }
  if (scr === 'tape') {
    style += '@keyframes tv-tr{0%,40%{transform:translateY(0)}62%,100%{transform:translateY(138px)}}.tv-tr{animation:tv-tr 24s linear infinite}'
  }
  if (scr === 'tape') {
    style +=
      '@keyframes tv-dg{0%{opacity:1}10%,100%{opacity:0}}.tv-dg{animation:tv-dg 10s steps(1,end) infinite}' +
      '@keyframes tv-pan{50%{transform:translate(-5px,1.2px)}100%{transform:translate(-1.5px,-.8px)}}.tv-pan{animation:tv-pan 26s ease-in-out infinite alternate}' +
      '@keyframes tv-sw{50%{transform:rotate(5deg)}}.tv-sw{transform-origin:1184px 471px;animation:tv-sw 9s ease-in-out infinite}' +
      '@keyframes tv-ff{50%{opacity:.15}}.tv-ff{animation:tv-ff 7s ease-in-out infinite}'
  }
  if (state.tape) {
    style +=
      '@keyframes tv-in{from{transform:translate(3.6px,1.2px)}}.tv-in{animation:tv-in 2.4s ease-out .6s 1 backwards}' +
      '@keyframes tv-fl{from{transform:scaleY(0)}}.tv-fl{transform-origin:0 580px;animation:tv-fl .5s ease-in 3s 1 backwards}'
  }
  if (scr === 'game') {
    style +=
      '@keyframes tv-ga{100%{transform:translate(14px,6px)}}.tv-ga{animation:tv-ga 34s ease-in-out infinite alternate}' +
      '@keyframes tv-gb{100%{transform:translate(-12px,-5px)}}.tv-gb{animation:tv-gb 41s ease-in-out infinite alternate}' +
      '@keyframes tv-ps{50%{opacity:.15}}.tv-ps{animation:tv-ps 6s ease-in-out infinite}'
  }
  if (state.tv || state.tape) style += '@keyframes tv-ck{0%,45%{opacity:1}52%,93%{opacity:.35}}.tv-ck{animation:tv-ck 3s ease-in-out infinite}'
  if (state.lava) {
    style +=
      '@keyframes tv-b1{50%{transform:translate(1px,-26px) scale(.8,1.25)}100%{transform:translate(-1px,-40px) scale(.9,1.05)}}.tv-b1{transform-origin:1374px 540px;animation:tv-b1 38s ease-in-out infinite alternate}' +
      '@keyframes tv-b2{100%{transform:translate(-1px,34px) scale(1.1,.9)}}.tv-b2{transform-origin:1379px 512px;animation:tv-b2 47s ease-in-out infinite alternate}' +
      '@keyframes tv-b3{0%{transform:translateY(-4px)}100%{transform:translate(2px,-26px)}}.tv-b3{animation:tv-b3 31s ease-in-out infinite alternate}'
  }

  let defs =
    `<filter id="tv-nf" x="0" y="0" width="1" height="1"><feTurbulence type="fractalNoise" baseFrequency="1.1" numOctaves="2" stitchTiles="stitch"/><feColorMatrix values="2 0 0 0 -.8 2 0 0 0 -.8 2.2 0 0 0 -.8 0 0 0 0 1"/></filter>` +
    `<pattern id="tv-g" width="128" height="128" patternUnits="userSpaceOnUse"><rect width="128" height="128" filter="url(#tv-nf)"/></pattern>` +
    `<filter id="tv-df" x="0" y="0" width="1" height="1"><feTurbulence type="fractalNoise" baseFrequency=".9" seed="7" stitchTiles="stitch"/><feColorMatrix values="0 0 0 0 .85 0 0 0 0 .9 0 0 0 0 1 6 0 0 0 -4.1"/></filter>` +
    `<pattern id="tv-du" width="128" height="128" patternUnits="userSpaceOnUse"><rect width="128" height="128" filter="url(#tv-df)"/></pattern>` +
    `<pattern id="tv-gr" width="2.2" height="2.2" patternUnits="userSpaceOnUse"><circle cx="1.1" cy="1.1" r=".62" fill="#04050a"/></pattern>` +
    `<filter id="tv-sf" x="-20%" y="-60%" width="140%" height="220%"${CS}><feGaussianBlur stdDeviation="1.5"/></filter>` +
    `<filter id="tv-fz" x="-5%" y="-10%" width="110%" height="120%"${CS}><feGaussianBlur stdDeviation=".4"/></filter>` +
    `<filter id="tv-fm" x="-10%" y="-20%" width="120%" height="140%"${CS}><feGaussianBlur stdDeviation=".8"/></filter>` +
    `<filter id="tv-ft" filterUnits="userSpaceOnUse" x="1110" y="412" width="32" height="54"${CS}><feGaussianBlur stdDeviation=".4"/></filter>` +
    `<clipPath id="tv-cg"><rect x="${GX}" y="${GY}" width="${GW}" height="${GH}" rx="9"/></clipPath>` +
    `<clipPath id="tv-cc"><path d="${C_BODY}"/><path d="${C_HEAD}" transform="${HM}"/><ellipse cx="1253" cy="414" rx="18" ry="9"/></clipPath>` +
    rg('hl', [[0, '#e8eeff', 0.12], [1, '#e8eeff', 0]]) +
    lg('ds', 0, 0, 0, 1, [[0, '#000', 0.75], [1, '#000', 0]]) +
    lg('dk', 0, 0, 1, 0, [[0, '#000', 0], [0.5, '#000', 0], [1, '#000', 0.3]]) +
    lg('vh', 0, 0, 1, 0, [[0, '#000', 0.45], [0.25, '#000', 0], [0.8, '#000', 0], [1, '#000', 0.3]]) +
    rg('led', [[0, '#c8ffd8'], [0.25, '#5dff9a', 0.8], [0.6, '#2fbf6a', 0.18], [1, '#2fbf6a', 0]]) +
    rg('ck', fall('#3dff8a', 0.09, 1.6)) +
    (L
      ? lg('cf', 0, 421, 0, 571, [[0, '#3c3c42'], [0.12, '#323238'], [1, '#26262b']], US) +
        lg('sd', 0, 0, 1, 0, [[0, '#34343a'], [1, '#3e3e44']]) +
        lg('tp', 0, 0, 1, 0, [[0, '#2e2e33'], [1, '#232327']]) +
        lg('vf', 0, 0, 0, 1, [[0, '#4a4b51'], [0.14, '#333439'], [0.6, '#2e2f34'], [1, '#232428']]) +
        lg('cs', 0, 0, 1, 0, [[0, '#303036'], [1, '#26262b']]) +
        lg('cn', 0, 0, 1, 0, [[0, '#3a3a40'], [0.12, '#2a2a2f'], [1, '#1d1d21']]) +
        lg('lm', 0, 0, 1, 0, [[0, '#2a2230'], [0.22, '#5e5068'], [0.4, '#2c2434'], [1, '#120e16']])
      : rg('cf', [[0, '#16171d'], [0.45, '#111218'], [1, '#0a0b10']], ' gradientUnits="userSpaceOnUse" cx="1208" cy="484" r="122"') +
        lg('sd', 0, 0, 1, 0, [[0, '#0a0b10'], [1, '#0f1015']]) +
        lg('tp', 0, 0, 1, 0, [[0, '#0c0d12'], [1, '#08090d']]) +
        lg('vf', 0, 0, 0, 1, [[0, '#0a0b11'], [0.2, '#101118'], [0.6, '#121319'], [1, '#0c0d12']]) +
        lg('cs', 0, 0, 1, 0, [[0, '#0f1016'], [1, '#0a0b10']]) +
        lg('cn', 0, 0, 1, 0, [[0, '#111217'], [0.12, '#0d0e13'], [1, '#08090d']]) +
        lg('lm', 0, 0, 1, 0, [[0, '#0e0d14'], [0.25, '#17151f'], [0.45, '#0b0a10'], [1, '#060609']])) +
    lg('cw', 0, 365, 0, 424, fur(L ? ['#dcd5c8', '#c4bdb0', '#968f84'] : ['#17181f', '#131419', '#0e0f13'], 1), US) +
    lg('tab', 0, 365, 0, 424, fur(L ? ['#5e4a3a', '#433427', '#2a2018'] : ['#0e0e12', '#0b0b0e', '#09090c'], 0.35), US)
  if (on) {
    defs +=
      `<pattern id="tv-sl" width="8" height="1.6" patternUnits="userSpaceOnUse"><rect width="8" height=".7" fill="#000510" opacity=".32"/></pattern>` +
      `<filter id="tv-tf" x="-10%" y="-60%" width="120%" height="220%"><feGaussianBlur stdDeviation="1.3"/></filter>` +
      `<filter id="tv-bf" x="-30%" y="-35%" width="160%" height="170%"><feGaussianBlur stdDeviation="6"/></filter>` +
      `<filter id="tv-bw" x="-40%" y="-50%" width="180%" height="200%"><feGaussianBlur stdDeviation="12"/></filter>` +
      rg('cl', [[0.45, lc, 0.2 * ga * (L ? 0.5 : 1)], [1, lc, 0]], ' gradientUnits="userSpaceOnUse" cx="1208" cy="484" r="122"') +
      lg('tb', 0, 0, 0, 1, [[0, '#c8d4ff', 0], [0.45, '#d8e0ff', 0.2], [0.55, '#d8e0ff', 0.22], [1, '#c8d4ff', 0]])
  }
  if (la) {
    defs +=
      rg('h', fall(lc, 0.27 * la, 2.2)) +
      rg('hw', fall(lc, 0.08 * la, 1.6)) +
      rg('hn', fall(lc, 0.3 * la, 1.6)) +
      rg('p', fall(lc, 0.2 * la, 2)) +
      lg('el', 0, 0, 0, 1, [[0, lc, 0.3 * la], [1, lc, 0]]) +
      lg('tl', 0, 0, 0, 1, [[0, lc, 0.25 * la], [1, lc, 0]])
  }
  if (scr === 'blue') {
    defs +=
      rg('gl', [[0, '#4264f4'], [0.35, '#3253ea'], [0.68, '#2238c2'], [0.88, '#16268c'], [1, '#0c1552']], ' cx=".5" cy=".46" r=".72"') +
      rg('lip', [[0.62, '#2a3a9a'], [0.8, '#1a2566'], [1, '#0b0e22']], ' cx=".5" cy=".5" r=".72"')
  } else if (scr === 'tape') {
    defs +=
      rg('lip', [[0.62, '#4c4250'], [0.8, '#2a2430'], [1, '#0d0c12']], ' cx=".5" cy=".5" r=".72"') +
      lg('vs', 0, 425, 0, 505, [[0, '#24346a'], [0.42, '#5e5486'], [0.78, '#bb7f6c'], [1, '#dc9e62']], US) +
      lg('vl', 0, 0, 0, 1, [[0, '#26331f'], [1, '#121a10']]) +
      rg('sun', fall('#ffc27a', 0.5, 1.5)) +
      `<filter id="tv-vb" x="-10%" y="-20%" width="120%" height="140%"><feGaussianBlur stdDeviation=".9"/></filter>`
  } else if (scr === 'game') {
    defs +=
      rg('lip', [[0.62, '#1e2450'], [0.8, '#141834'], [1, '#0a0b16']], ' cx=".5" cy=".5" r=".72"') +
      rg('gb', [[0, '#141a3a'], [0.6, '#0a0d1e'], [1, '#05060c']], ' cx=".5" cy=".45" r=".75"') +
      rg('g1', fall('#2ab8c4', 0.4, 1.6)) +
      rg('g2', fall('#8a5cff', 0.36, 1.6))
  } else {
    defs +=
      rg('lip', L ? [[0.62, '#3a3d3a'], [0.8, '#2a2c2a'], [1, '#18191a']] : [[0.62, '#1a1d1b'], [0.8, '#121413'], [1, '#09090a']], ' cx=".5" cy=".5" r=".72"') +
      rg('gl', L ? [[0, '#3c423e'], [0.55, '#2c312d'], [1, '#161917']] : [[0, '#141715'], [0.6, '#0f1110'], [1, '#090a0a']], ' cx=".42" cy=".38" r=".8"') +
      rg('sb', [[0, '#ff8a70'], [0.3, '#ff3a28', 0.6], [1, '#ff3a28', 0]])
  }
  if (state.lava) {
    defs +=
      `<clipPath id="tv-lv"><path d="${LV_GLASS}"/></clipPath>` +
      lg('lq', 0, 0, 0, 1, [[0, '#3a1468'], [0.6, '#6a28b8'], [1, '#a24ef0']]) +
      rg('wx', [[0, '#f2c4ff'], [0.6, '#d070ff'], [1, '#a048e8', 0.85]], ' cx=".4" cy=".35" r=".8"') +
      rg('pt', fall(PC, 0.3 * pa, 1.5), ' gradientUnits="userSpaceOnUse" cx="1376" cy="604" r="50"') +
      lg('pb', 0, 0, 0, 1, [[0, PC, 0.26 * pa], [0.14, PC, 0.05 * pa], [0.32, PC, 0]]) +
      rg('pw', fall('#9440f0', 0.26 * pa, 1.7)) +
      rg('lavaglow', fall('#b468ff', 0.2 * pa, 1.4))
    if (!on) defs += `<filter id="tv-bf" x="-30%" y="-35%" width="160%" height="170%"><feGaussianBlur stdDeviation="6"/></filter>`
  } else {
    defs += lg('lq', 0, 0, 0, 1, L ? [[0, '#2e1a44'], [1, '#3e2258']] : [[0, '#0c0a12'], [1, '#100c17']])
  }
  if (L) defs += `<filter id="tv-wf" x="-30%" y="-20%" width="160%" height="140%"><feGaussianBlur stdDeviation="6"/></filter>`

  let under = ''
  if (la) {
    under +=
      `<g class="tv-br" opacity="1">` +
      E(1150, 520, 330, 250, u('hw')) +
      E(1262, 468, 250, 230, u('h')) +
      E(1300, 485, 120, 150, u('hn')) +
      E(1230, 965, 300, 85, u('p')) +
      `</g>`
  }
  if (state.lava) under += E(1376, 530, 78, 108, u('pw')) + E(1376, 536, 30, 56, u('lavaglow'))
  if (L) {
    under +=
      `<g filter="url(#tv-wf)" fill="#0a0608" opacity=".36">` +
      D('M1290 418L1296 428C1300 424 1310 424 1314 428L1320 418L1323 433C1328 440 1327 452 1322 458L1339 474L1345 598L1296 598L1296 452C1288 446 1286 436 1290 418Z', 'inherit') +
      P([[1337, 518], [1357, 528], [1361, 598], [1337, 598]], 'inherit') +
      D('M1403 532Q1410 524 1417 532L1421 560L1425 591L1397 591L1400 560Z', 'inherit') +
      `</g>`
  }

  let body = ''

  if (state.lava) body += P([[1290, 591], [1317, 591], [1400, 606], [1290, 606]], u('pt'))
  if (la) body += E(1208, 604.6, 58, 1.3, lc,`${o(0.22 * la)} filter="url(#tv-sf)"`)

  const sh = `${o(L ? 0.55 : 0.35)} filter="url(#tv-sf)"`
  body += P([[1104, 593], [1290, 593], [1286, 603], [1128, 603]], '#000', sh) + E(1324, 601, 16, 2.5, '#000', sh) + E(1376, 604.5, 18, 1.8, "#000", sh)
  body += R(1130, 598, 160, 6, u('ds'), ' opacity=".9"')

  const upright = (x: number, w: number, top: number, kind: string, label: string, salt: number, rot = 0): string => {
    const bottom = 601
    const h = bottom - top
    let s = rot ? `<g transform="rotate(${f(rot)} ${f(x + w)} ${bottom})">` : '<g>'
    if (!rot) s += P([[x, top], [x + w, top], back(x + w, top), back(x, top)], k('#0d0e13', '#3a3a3f'))
    if (kind === 'vhs') {
      s += R(x, top, w, h, k('#0b0c11', '#1e1e21'))
      const ly = top + 6 + unit(salt, 4) * 3
      const lh = h - 14 - unit(salt, 5) * 4
      const lr = (unit(salt, 6) - 0.5) * 1.6
      s += `<g transform="rotate(${f(lr)} ${f(x + w / 2)} ${f(ly + lh / 2)})">${R(x + 1.6, ly, w - 3.2, lh, k('#13141b', '#a39a84'))}`
      s += `<text transform="translate(${f(x + w - 2.6)} ${f(ly + lh - 3)}) rotate(-90)" ${HAND} font-size="${f(w * 0.6)}" fill="${k('#05060a', '#1f2238')}" opacity=".8">${label}</text></g>`
    } else if (kind === 'sleeve') {
      s += R(x, top, w, h, k('#110f15', '#6a2b28'))
      s += R(x, top + h * 0.12, w, h * 0.34, k('#0d0d13', '#b9ae96'), ' opacity=".75"')
      s += R(x + w * 0.2, top + h * 0.6, w * 0.6, h * 0.16, k('#17121c', '#2a2a46'), ' opacity=".8"')
      s += P([[x, top], [x + w, top], [x + w, top + 3], [x + w * 0.6, top + 1.2], [x, top + 2.2]], k('#1e1f2c', '#c0a890'), ' opacity=".45"')
    } else {
      s += R(x, top, w, h, kind)
      s += R(x, top + h * (0.18 + unit(salt, 7) * 0.2), w, h * 0.12, k('#1a1b22', '#8a8696'), ' opacity=".3"')
    }
    s += R(x, top, w, h, u('dk'))
    if (L) s += R(x, top, w, 2.5, '#fff1d8', ' opacity=".1"')
    if (la) s += R(x, top, 0.6, h, lc, o(0.18 * la))
    if (pa) s += R(x + w - 0.7, top, 0.7, h, PC, o(0.25 * pa))
    return s + '</g>'
  }
  body += P([[1338, 537], [1338, 601], back(1338, 601), back(1338, 537)], u('tp'))
  body += upright(1338, 8.6, 537, 'vhs', '@TAPE@', 1)
  body += upright(1347, 9.6, 535, 'sleeve', '', 2)
  body += R(1337, 597, 24, 5, u('ds'), ' opacity=".7"')

  body += upright(1357, 4.7, 536, k('#100d16', '#3a3550'), '', 3, 7)

  body += D(LV_BASE, u('lm'))
  if (state.lava) body += D('M1361.5 600L1367.2 557L1384.8 557L1390.5 600Z', u('pb'))
  body += R(1366.5, 553.6, 19, 4, k('#0c0b11', '#3a3040'), ' rx="1"')
  if (L) body += R(1367, 553.6, 18, 1, '#fff0dc', ' opacity=".18"')
  body += D(LV_GLASS, u('lq'))
  const pool = 'M1366 556C1367 551 1370 548 1373 549.5C1375 546.5 1379.5 547 1381 550C1384 549.5 1386.5 552 1386 556Z'
  if (state.lava) {
    body += E(1376, 540, 9, 40, '#e0a0ff', ' opacity=".14" filter="url(#tv-sf)"')
    body += `<g clip-path="url(#tv-lv)">`
    body += D(pool, u('wx')) + E(1376, 496.5, 5.5, 2.8, u('wx'))
    body += `<g class="tv-b1">${D('M1374 531C1378 531 1379.5 537 1379 541C1378.6 545.5 1376.6 548 1374 548C1371 548 1369 545 1369.2 541C1369.4 536 1370.5 531 1374 531Z', u('wx'))}</g>`
    body += `<g class="tv-b2">${D('M1379 507C1382.5 507.2 1383.4 511 1383 513.5C1382.4 516.5 1380.5 517.6 1378.6 517.4C1376 517 1374.8 514.6 1375 512C1375.3 509 1376.6 506.8 1379 507Z', u('wx'))}</g>`
    body += `<g class="tv-b3">${E(1372, 525, 2.3, 3.2, u('wx'))}</g>`
    body += `</g>`
    body += R(1366.5, 553.6, 19, 1.2, '#c070ff', ' opacity=".55" rx=".6"')
  } else {
    body += D(pool, k('#120f18', '#4c2b62'))
  }
  body += `<path d="M1367.4 538C1368 523 1370.2 509 1372.2 498" stroke="#fff" stroke-width="2" fill="none"${o(L ? 0.2 : state.lava ? 0.08 : 0.03)} filter="url(#tv-sf)"/>`
  if (la) body += `<path d="M1366 548C1364 538 1366 522 1370.6 496M1361 601L1367 559" stroke="${lc}" stroke-width="2" fill="none"${o(0.16 * la)} filter="url(#tv-sf)"/>`
  body += D(LV_CAP, u('lm'))
  if (state.lava) body += R(1370, 493.4, 12, 1.4, '#c070ff', ' opacity=".4"')

  body += P([[1279, 498.2], [1310, 498], [1310, 603], [1279, 596.8]], u('cs'))
  for (let i = 0; i < 6; i++) {
    const y = 512 + i * 15
    body += `<path d="M1310 ${y}L1290 ${f(y + (y - 500) * -0.02)}" stroke="${k('#05060a', '#18181c')}" stroke-width=".7" opacity=".6"/>`
  }
  if (la) body += R(1288, 498, 22, 105, lc, o(0.08 * la))
  body += R(1310, 498, 27, 105, u('cn'))
  body += R(1310, 498, 27, 105, u('g'), ' opacity=".04"')
  body += R(1310, 498, 27, 1, k('#1c1e26', '#5c5c64'), ' opacity=".6"')
  body += R(1318.5, 506, 0.6, 84, '#000', ' opacity=".7"')
  body += R(1319.1, 506, 0.4, 84, k('#181a22', '#4a4a50'), ' opacity=".5"')
  body += R(1323, 582, 10, 2.2, '#030305') + R(1323, 587, 10, 2.2, '#030305')
  body += R(1325, 503, 6, 2, k('#0e1016', '#1a1a1e'))
  if (pa) body += R(1335.8, 498, 1.2, 105, PC, o(0.18 * pa))
  body += state.console
    ? E(1332.6, 507.6, 4, 4, u('led'), ' opacity=".55"') + E(1332.6, 507.6, 0.7, 0.7, '#9dffc0')
    : E(1332.6, 507.6, 0.8, 0.8, k('#0c0d12', '#26262a'))

  body += P([[1105.9, 564.8], [1135, 571], [1135, 603], [1105.9, 594]], u('tp'))
  body += R(1135, 571, 146, 32, u('vf'))
  body += R(1135, 571, 146, 32, u('vh'))
  body += R(1135, 571, 146, 32, u('g'), ' opacity=".05"')
  body += R(1135, 571, 146, 5, u('ds'))
  body += R(1135, 601.5, 146, 1.5, '#000', ' opacity=".5"')
  let door = R(1142, 580, 64, 11.5, k('#0a0b10', '#1c1d21'), ' rx=".8"') + R(1143.5, 590.2, 61, 0.6, '#000', ' opacity=".6"')
  if (L) door += R(1142.5, 580.4, 63, 0.7, '#fff', ' opacity=".08"')
  if (state.tape) {
    body += R(1142, 580, 64, 11.5, '#020205', ' rx=".8"')
    body += `<g class="tv-in">${R(1144, 581.6, 60, 8.6, k('#0a0a0e', '#161618'))}${R(1144, 581.6, 60, 1, k('#14151b', '#3a3a3e'))}</g>`
    body += R(1142, 580, 64, 1.6, '#000', ' opacity=".6"')
    body += `<g class="tv-fl">${door}</g>`
  } else {
    body += door
  }
  body += R(1212, 579, 64, 3.2, k('#0c0d13', '#1d1e22'), ' rx=".5"')
  body += R(1213, 586, 28, 11, '#04060a', ' rx=".6"')
  const skew = `<g transform="skewX(-6) translate(${f(Math.tan((6 * Math.PI) / 180) * 591)} 0)">`
  body += skew + digits(1216, 588.5, '88:88', false) + `</g>`
  if (state.tv || state.tape) {
    body += `<g class="tv-ck" opacity="1">${skew}${digits(1216, 588.5, '12:00', true)}</g>`
    body += E(1226, 591.5, 14, 6, u('ck')) + `</g>`
  } else {
    body += `<g opacity=".8">${skew}${digits(1216, 588.5, '12:00', true)}</g>` + E(1226, 591.5, 14, 6, u('ck')) + `</g>`
  }
  if (state.tape) body += P([[1244.5, 582], [1248.3, 584], [1244.5, 586]], '#4fe08e', ' opacity=".85"') + E(1246, 584, 4, 3, u('ck'))
  for (let i = 0; i < 4; i++) body += R(1250 + i * 6.5, 588, 4.6, 2.4, k('#0b0c12', '#1b1c20'), ' rx=".5"')
  body += `<circle cx="1275" cy="595" r="2" fill="${k('#0b0c12', '#18181c')}"/><circle cx="1275" cy="594.4" r="1.4" fill="${k('#1e212c', '#56575e')}"/>`
  if (la) body += R(1135, 571, 1.2, 32, lc, o(0.14 * la))

  const tabD = k('#08080b', '#2a2119')
  const pink = add(k('#100e12', '#a2706c'), lc, 0.1 * la)
  body += `<g transform="${HM}"><g class="tv-ef"><g filter="url(#tv-fz)">${D('M1275.8 386C1277.4 378 1277.2 371.5 1275.4 365.8C1270.6 368.2 1266.6 372.2 1263.6 378.4Z', u('tab'))}${D('M1273.6 381.5C1274.4 376.5 1274.2 372.5 1273.4 369.4C1270.6 371.4 1268.4 374 1266.8 377.4Z', pink, ' opacity=".9"')}</g></g></g>`
  const tail = (d: string, w: number, e = d): string =>
    `<path d="${d}" stroke="${add(k('#0d0d11', '#5a4a3b'), lc, 0.1 * la)}" stroke-width="${w}" stroke-linecap="round" fill="none"/>` +
    (L ? `<path d="${e}" stroke="${tabD}" stroke-width="${w + 0.1}" stroke-dasharray="2.6 3.4" fill="none" opacity=".22"/>` +
      `<path d="${e}" stroke="#a89c88" stroke-width="${f(w * 0.3)}" fill="none" opacity=".22" transform="translate(-1 -.6)"/>` : '') +
    (la ? `<path d="${e}" stroke="${lc}" stroke-width="${f(w * 0.3)}" fill="none"${o(0.22 * la)} transform="translate(1.8 .4)"/>` : '')
  let cat = tail(C_TAILTOP, 7)
  cat += D(C_BODY, u('cw'))
  const fm = ' filter="url(#tv-fm)"'
  cat += `<g clip-path="url(#tv-cc)"><g${fm}>${D(C_SADDLE, u('tab'))}${D(C_RUMP, u('tab'))}<path d="M1197 381l-.4 9M1207 379l0 9M1217 378l.6 9M1184 399l4.5 2.2M1183 404l4.5 1.6" stroke="${tabD}" stroke-width="1.1" opacity=".45"/>`
  if (L) cat += `<path d="M1186 395C1190 390 1196 387.5 1204 386C1216 383.5 1230 383 1242 385" stroke="#f2e6cc" stroke-width="3" fill="none" opacity=".2"/>`
  cat += `</g></g>`
  cat += E(1253, 414, 18, 9, u('cw'))
  let head = L ? E(1259, 409.5, 13, 2.2, '#4a4036', ' opacity=".16" filter="url(#tv-fm)"') : ''
  head += D('M1242.2 386C1240.6 378 1240.8 371.5 1242.6 365.8C1247.4 368.2 1251.4 372.2 1254.4 378.4Z', u('tab'))
  head += D('M1244.4 381.5C1243.6 376.5 1243.8 372.5 1244.6 369.4C1247.4 371.4 1249.6 374 1251.2 377.4Z', pink, ' opacity=".9"')
  head += D(C_HEAD, u('cw'))
  head += D('M1241 393.5L1238.4 397.2L1242 398.4ZM1277 393.5L1279.6 397.2L1276 398.4Z', u('cw'))
  head += `<g${fm}>${D(C_CAP, u('tab'))}<path d="M1252 380.5l1.6 4.4M1255 378.6l.8 4.6M1263 378.6l-.8 4.6M1266 380.5l-1.6 4.4M1244 386l4.2 1.6M1274 386l-4.2 1.6M1242.4 392.6l4.4.6M1275.6 392.6l-4.4.6" stroke="${tabD}" stroke-width=".8" opacity=".5"/></g>`
  head += `<path d="M1248.4 391.4Q1250.8 392.9 1253.2 391.6M1269.6 391.4Q1267.2 392.9 1264.8 391.6" stroke="${add(k('#0c0f0c', '#6f7a48'), lc, 0.06 * la)}" stroke-width=".4" fill="none"/>`
  head += `<path d="M1247.6 390.6Q1250.8 392.6 1254 390.8M1270.4 390.6Q1267.2 392.6 1264 390.8" stroke="${tabD}" stroke-width=".7" fill="none" opacity=".6"/>`
  const muz = add(k('#16171e', '#dcd5c8'), lc, 0.13 * la)
  head += `<g${fm}>${E(1256.2, 400.8, 3.4, 2.6, muz)}${E(1261.8, 400.8, 3.4, 2.6, muz)}</g>`
  head += D('M1256.9 396.6Q1259 395.8 1261.1 396.6Q1260.6 398.4 1259 399.2Q1257.4 398.4 1256.9 396.6Z', add(k('#131116', '#bf8582'), lc, 0.2 * la))
  head += `<path d="M1259 399.2v1.3M1256.8 401.6Q1259 402 1259 400.5Q1259 402 1261.2 401.6" stroke="${k('#050506', '#3e3228')}" stroke-width=".5" fill="none" opacity=".6"/>`
  head += `<path d="M1255 401l-11-1.6M1255 402l-11.5 1.2M1263 401l11-1.6M1263 402l11.5 1.2" stroke="${add(k('#262a3a', '#ddd4c2'), lc, 0.3 * la)}" stroke-width=".3"${o(L ? 0.45 : 0.2)}/>`
  cat += `<g transform="${HM}">${head}</g>`
  if (L) cat += R(1150, 362, 135, 64, u('g'), ` clip-path="url(#tv-cc)" opacity=".06"`)
  body += `<g filter="url(#tv-fz)">${cat}</g>`

  body += P([[1106.5, 453], [1113.3, 422.6], [1113.3, 569.5], [1106.5, 557.4]], u('tp'))
  body += P([[1113.3, 423.5], [1120, 421], [1120, 571], [1113.3, 569.5]], u('sd'))
  body += `<rect x="1120" y="421" width="176" height="150" rx="4" fill="${u('cf')}"/>`
  if (on) body += `<rect x="1120" y="421" width="176" height="150" rx="4" fill="${u('cl')}"/>`
  body += `<rect x="1120" y="421" width="176" height="150" rx="4" fill="${u('g')}" opacity=".04"/>`
  if (L) body += R(1121, 421, 174, 2.4, '#fff3e0', ' opacity=".12"') + R(1113.3, 422.6, 6.7, 2, '#fff3e0', ' opacity=".08"')
  if (la) body += R(1121, 421, 174, 3, u('tl')) + R(1120, 423, 1.4, 70, u('el'))
  body += R(1123, 566, 170, 5, u('ds'), ' transform="rotate(180 1208 568.5)"')
  if (on) body += `<rect x="${GX - 9}" y="${GY - 7.5}" width="${GW + 18}" height="${GH + 16}" rx="15" fill="${lc}"${o(0.1 * ga)}/>`
  if (L) body += `<rect x="${GX - 9}" y="${GY - 7.5}" width="${GW + 18}" height="3" rx="1.5" fill="#fff3e0" opacity=".06"/>`
  body += `<rect x="${GX - 4.5}" y="${GY - 4.5}" width="${GW + 9}" height="${GH + 9}" rx="12" fill="${k('#09090c', '#141417')}"/>`
  body += `<rect x="${GX - 3}" y="${GY - 3}" width="${GW + 6}" height="${GH + 6}" rx="11" fill="${u('lip')}"/>`
  const glass = scr === 'blue' || scr === 'off' ? u('gl') : scr === 'tape' ? '#1c2030' : u('gb')
  body += `<rect x="${GX}" y="${GY}" width="${GW}" height="${GH}" rx="9" fill="${glass}"/>`

  body += `<g clip-path="url(#tv-cg)">`
  const osd = (x: number, y: number, t: string, anchor = ''): string => `<text x="${f(x)}" y="${f(y)}"${anchor}>${t}</text>`
  if (scr === 'tape') {
    body += `<g class="tv-pan">`
    body += R(1126, 424, 164, 84, u('vs'))
    body += E(1236, 501, 52, 15, u('sun'))
    body += D('M1126 498C1140 494 1150 497 1160 493C1172 495 1180 490 1192 494C1204 491 1214 496 1226 493C1240 497 1252 492 1266 495C1276 492 1284 496 1290 494L1290 512L1126 512Z', '#1a1720', ' filter="url(#tv-vb)"')
    body += D('M1259 510L1260 489L1257 482L1261 484L1263 478L1264 489L1266 510ZM1236 486C1231 477 1238 468 1246 467C1248 457 1260 451 1268 456C1278 451 1290 459 1288 470C1295 477 1292 490 1282 492C1277 499 1266 497 1262 492C1254 497 1240 495 1236 486Z', '#131119', ' filter="url(#tv-vb)"')
    body += R(1126, 505, 164, 40, u('vl'))
    body += `<path d="M1163 470L1155 516M1165 470L1173 516M1203 471L1197 516M1205 471L1213 516M1162 470L1207 472" stroke="#0e0d12" stroke-width="1.6" fill="none" filter="url(#tv-vb)"/>`
    body += `<g class="tv-sw"><path d="M1180 471V500M1188 471V500M1178 500.5H1190" stroke="#100f14" stroke-width="1" fill="none"/></g>`
    for (let i = 0; i < 5; i++) {
      body += `<circle class="tv-ff" cx="${f(1150 + unit(i, 31) * 110)}" cy="${f(512 + unit(i, 32) * 20)}" r=".9" fill="#e6ff8c" style="animation-delay:-${2 + i * 1.4}s"/>`
    }
    body += R(1126, 424, 164, 120, '#ffd6a8', ' opacity=".05"')
    body += `</g>`
  } else if (scr === 'game') {
    body += `<g class="tv-ga">${E(1186, 470, 44, 32, u('g1'))}</g>`
    body += `<g class="tv-gb">${E(1236, 500, 48, 34, u('g2'))}</g>`
    body += `<circle cx="1208" cy="481" r="21" fill="none" stroke="#a8dcff" stroke-width=".8" opacity=".22"/>`
    body += `<circle cx="1208" cy="481" r="13" fill="none" stroke="#c9b4ff" stroke-width=".5" opacity=".14"/>`
    body += `<text class="tv-ps" x="1208" y="523" font-family="monospace" font-size="5.6" letter-spacing="1" text-anchor="middle" fill="#cfe0ff" opacity=".5">PRESS START</text>`
  }
  if (scr === 'blue' || scr === 'tape') {
    const play = scr === 'tape'
    const tri = play ? P([[1178, 444.6], [1185.5, 448.6], [1178, 452.6]], 'inherit') : ''
    const all = osd(1149, 452, play ? 'PLAY' : 'STOP') + tri + osd(1149, 527, 'SP') + (play ? osd(1224, 527, '0:47:1') : osd(1266, 527, '0:47:12', ' text-anchor="end"'))
    body += `<g opacity=".9" ${MONO}>`
    body += `<g filter="url(#tv-tf)" fill="#cfd8ff" opacity=".7">${all}</g>`
    body += `<g fill="#ff4d6a" opacity=".3" transform="translate(-.6 0)">${all}</g>`
    body += `<g fill="#4de8ff" opacity=".3" transform="translate(.6 0)">${all}</g>`
    body += `<g fill="#dfe5ff" opacity=".78">${all}`
    if (play) {
      body += `<g transform="translate(1260 527)">`
      for (let i = 0; i < 10; i++) body += `<text class="tv-dg" style="animation-delay:${i - 20}s" opacity="${i === 2 ? 1 : 0}">${i}</text>`
      body += `</g>`
    }
    body += `</g></g>`
  }
  if (state.titles?.console !== '') body += `<rect x="1164" y="472" width="88" height="16" fill="#04050b"/>@TITLE@`
  if (on) {
    body += `<path d="M1141 447Q1150 442.5 1161 441.5Q1163 463 1162 485Q1151 487.5 1142 492Q1139.5 470 1141 447Z" fill="#c2b0f0" opacity=".07" filter="url(#tv-sf)"/>`
    body += E(1176, 452, 46, 22, u('hl'), ' transform="rotate(-14 1176 452)"')
    body += R(GX, GY, GW, GH, u('sl'))
    body += R(GX, GY, GW, GH, u('du'), ' opacity=".07"')
    if (scr === 'tape') {
      body += `<g class="tv-tr"><rect x="${GX}" y="406" width="${GW}" height="22" fill="${u('tb')}"/>`
      for (let i = 0; i < 6; i++) {
        const y = 410 + unit(i, 21) * 14
        const x = GX + unit(i, 22) * 120
        body += E(x + 12, y, 6 + unit(i, 23) * 18, 0.7, u('hl'), ` opacity="${f(0.5 + unit(i, 24) * 0.5)}"`)
      }
      body += `</g>`
    }
    body += `<rect class="tv-sd" x="${GX}" y="${GY}" width="${GW}" height="${GH}" fill="#000818" opacity="0"/>`
  } else {
    body += `<path d="M1141 447Q1150 442.5 1161 441.5Q1163 463 1162 485Q1151 487.5 1142 492Q1139.5 470 1141 447Z" fill="${k('#5c5c96', '#3a3f52')}"${o(L ? 0.35 : 0.12)} filter="url(#tv-sf)"/>`
    body += `<path d="M1151 442.5Q1152.5 465 1151.5 488M1141 466Q1151 463.5 1162 462" stroke="#050607" stroke-width="1.6" fill="none"${o(L ? 0.4 : 0.25)} filter="url(#tv-sf)"/>`
    if (L) {
      body += R(GX, 470, GW, 30, '#8a7a62', ' opacity=".05" filter="url(#tv-sf)"')
      body += E(1196, 441, 7, 2.2, '#fff4dc', ' opacity=".22" filter="url(#tv-sf)"')
    }
    body += E(1176, 452, 46, 22, u('hl'), ` transform="rotate(-14 1176 452)"${o(L ? 1.6 : 0.6)}`)
    body += R(GX, GY, GW, GH, u('du'), o(L ? 0.12 : 0.06))
  }
  body += `</g>`

  body += `<g filter="url(#tv-ft)">${tail(C_TAIL, 7.5)}</g>`
  body += `<g class="tv-tt"><g filter="url(#tv-ft)">${tail(C_TIP, 6.5, 'M1123.6 447C1124 452 1125.6 456.6 1129.4 457.2')}</g></g>`

  const grille = k('#121318', '#2c2c31')
  body += `<rect x="1128" y="550" width="46" height="13" rx="1.5" fill="${grille}"/><rect x="1128" y="550" width="46" height="13" rx="1.5" fill="${u('gr')}"/>`
  body += `<rect x="1242" y="550" width="46" height="13" rx="1.5" fill="${grille}"/><rect x="1242" y="550" width="46" height="13" rx="1.5" fill="${u('gr')}"/>`
  body += `<rect x="1199" y="545" width="18" height="3.6" rx="1" fill="${k('#121319', '#55565c')}"/>`
  for (let i = 0; i < 5; i++) body += `<rect x="${1186 + i * 9}" y="556" width="6.4" height="3" rx=".8" fill="${k('#0c0d13', '#1c1c20')}"/>`
  body += on
    ? E(1180.5, 557.5, 3.5, 3.5, u('led'), ' opacity=".5"') + E(1180.5, 557.5, 0.65, 0.65, '#9dffc0')
    : E(1180.5, 557.5, 3, 3, u('sb'), ' opacity=".4"') + E(1180.5, 557.5, 0.55, 0.55, '#ff7a64')

  const cord = 'M1326 590C1329 597 1336 600 1344 600'
  if (!L) body += `<path d="${cord}" stroke="#000" stroke-width="2.6" fill="none" opacity=".4" transform="translate(2 2)" filter="url(#tv-sf)"/>`
  body += `<path d="${cord}" stroke="${k('#07080c', '#1b1b1f')}" stroke-width="1.4" fill="none"/>`

  let over = ''
  if (on) {
    const bc = scr === 'blue' ? '#3354f2' : scr === 'tape' ? '#a88aa0' : '#5a68d0'
    const bloom = ga * (L ? 0.5 : 1)
    over +=
      `<g class="tv-br" opacity="1">` +
      `<rect x="${GX + 2}" y="${GY + 2}" width="${GW - 4}" height="${GH - 4}" rx="9" fill="${bc}"${o(0.26 * bloom)} filter="url(#tv-bf)"/>` +
      `<rect x="${GX + 6}" y="${GY + 4}" width="${GW - 8}" height="${GH - 10}" rx="9" fill="${bc}"${o(0.12 * bloom)} filter="url(#tv-bw)"/>` +
      `</g>`
  }
  if (state.lava) over += E(1376, 528, 15, 32, '#a85cff', `${o(0.24 * (L ? 0.6 : 1))} filter="url(#tv-bf)"`)

  const z = (s: string): string => s.replace(/(^|[^\d.])0\.(?=\d)/g, '$1.')
  const esc = (t: string): string => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  const name = esc(state.titles?.console ?? 'FAR MERIDIAN')
  const fit = name.length > 13 ? ' textLength="82" lengthAdjust="spacingAndGlyphs"' : ''
  const title = `<g font-family="Bahnschrift, Eurostile, 'Segoe UI', sans-serif" font-weight="300" font-stretch="expanded" font-size="7" letter-spacing="2.2" text-anchor="middle"><text x="1209.1" y="482.5"${fit} fill="#7f9dff" opacity=".55" filter="url(#tv-tg)">${name}</text><text x="1209.1" y="482.5"${fit} fill="#e4ebff">${name}</text></g>`
  return {
    style: z(style),
    defs: z(defs) + `<filter id="tv-tg" x="-10%" y="-60%" width="120%" height="220%"><feGaussianBlur stdDeviation="1.2"/></filter>`,
    under: z(under),
    body: z(body).replace('@TITLE@', title).replace('@TAPE@', esc(state.titles?.tape ?? 'ROOFTOP')),
    over: z(over),
  }
}
