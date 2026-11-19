import { proj, unit, f, DEFAULT_STATE, type Part, type State } from '../lib.ts'

type V = [number, number]

const SL = 0.986
const SU = 0.976
const SS = 0.964
const MX = 387

/** f() without the leading zero. */
const g = (v: number): string => f(v).replace(/^(-?)0\./, '$1.')
const pt = (p: readonly number[]): string => `${g(p[0])},${g(p[1])}`
const pts = (list: readonly (readonly number[])[]): string => list.map(pt).join(' ')

type Stop = [number, string, number?]
/** Two decimals, no leading zero (f() keeps only one, which merges close gradient stops). */
const d2 = (v: number): string => String(Math.round(v * 100) / 100).replace(/^(-?)0\./, '$1.')
const stops = (list: Stop[]): string =>
  list.map(([o, c, op]) => `<stop offset="${d2(o)}" stop-color="${c}"${op === undefined ? '' : ` stop-opacity="${d2(op)}"`}/>`).join('')
const lin = (id: string, x1: number, y1: number, x2: number, y2: number, list: Stop[], user = true): string =>
  `<linearGradient id="window-${id}"${user ? ' gradientUnits="userSpaceOnUse"' : ''} x1="${g(x1)}" y1="${g(y1)}" x2="${g(x2)}" y2="${g(y2)}">${stops(list)}</linearGradient>`
const rad = (id: string, cx: number, cy: number, r: number, list: Stop[], extra = ''): string =>
  `<radialGradient id="window-${id}" gradientUnits="userSpaceOnUse" cx="${g(cx)}" cy="${g(cy)}" r="${g(r)}"${extra}>${stops(list)}</radialGradient>`
/** Paint a shape kept in defs. */
const use = (id: string, a: string): string => `<use href="#window-${id}" ${a}/>`

function sub(x0: number, y0: number, x1: number, y1: number, s: number): string {
  const [ax, ay] = proj(x0, y0, s)
  const [bx, by] = proj(x1, y1, s)
  return `M${g(ax)} ${g(ay)}H${g(bx)}V${g(by)}H${g(ax)}Z`
}
const box = (x0: number, y0: number, x1: number, y1: number, s: number, a: string): string => `<path d="${sub(x0, y0, x1, y1, s)}" ${a}/>`

/** A clockwise outline roughened by midpoint displacement into a leaf edge; segments listed in `plain` stay straight. */
function rough(keys: V[], seed: number, amp: number, min: number, plain: number[] = []): string {
  const out: V[] = [keys[0]]
  let n = 0
  for (let k = 0; k + 1 < keys.length; k++) {
    let seg: V[] = [keys[k], keys[k + 1]]
    if (!plain.includes(k)) {
      for (let pass = 0; pass < 8; pass++) {
        const next: V[] = [seg[0]]
        for (let i = 0; i + 1 < seg.length; i++) {
          const [ax, ay] = seg[i]
          const [bx, by] = seg[i + 1]
          const L = Math.hypot(bx - ax, by - ay)
          if (L > min) {
            n++
            const o = (unit(n, seed) - 0.42) * L * amp
            const t = 0.3 + 0.4 * unit(n, seed + 5)
            next.push([ax + (bx - ax) * t + ((by - ay) / L) * o, ay + (by - ay) * t - ((bx - ax) / L) * o])
          }
          next.push(seg[i + 1])
        }
        seg = next
      }
    }
    out.push(...seg.slice(1))
  }
  let d = `M${g(out[0][0])} ${g(out[0][1])}l`
  let [px, py] = [Math.round(out[0][0] * 10), Math.round(out[0][1] * 10)]
  for (const [x, y] of out.slice(1)) {
    const [qx, qy] = [Math.round(x * 10), Math.round(y * 10)]
    const dx = g((qx - px) / 10)
    const dy = g((qy - py) / 10)
    d += (d.endsWith('l') || dx.startsWith('-') ? '' : ' ') + dx + (dy.startsWith('-') ? '' : ' ') + dy
    px = qx
    py = qy
  }
  return d + 'Z'
}

/** A sash frame: outline with two pane holes split by one muntin, at plane scale s. Returns the frame path and its small details. */
function sash(y0: number, y1: number, s: number, tr: number, br: number, gop: string): [string, string] {
  const st = 17
  const m = 3
  const panes: V[] = [[270 + st, MX - m], [MX + m, 504 - st]]
  let d = sub(270, y0, 504, y1, s)
  let lips = ''
  for (const [a, b] of panes) {
    d += sub(a, y0 + tr, b, y1 - br, s)
    const [lx, ly] = proj(a, y0 + tr, s)
    const [rx, ly2] = proj(b, y1 - br, s)
    lips += `<rect x="${g(lx)}" y="${g(ly)}" width="1.6" height="${g(ly2 - ly)}" fill="#2c2948" opacity=".5"/><rect x="${g(lx)}" y="${g(ly)}" width="${g(rx - lx)}" height="1.3" fill="#05060c" opacity=".5"/>`
  }
  const rails = sub(270 + st, y0, 504 - st, y0 + tr, s) + sub(270 + st, y1 - br, 504 - st, y1, s)
  const stiles = sub(270, y0, 270 + st, y1, s) + sub(504 - st, y0, 504, y1, s) + sub(MX - m, y0 + tr, MX + m, y1 - br, s)
  return [`<path d="${d}" fill-rule="evenodd"/>`, `<path d="${rails}" fill="url(#window-gr)" opacity="${gop}"/><path d="${stiles}" fill="url(#window-gv)" opacity="${gop}"/>${lips}`]
}

export function part(state: State = DEFAULT_STATE): Part {
  const L6 = state.light
  const L1 = state.tv && !L6
  const L7 = state.lamp
  const gop = L6 ? '.09' : '.04'

  const cloud = (cx: number, cy: number, w: number, h: number, seed: number, n: number): string => {
    let s = ''
    for (let j = 0; j < n; j++) {
      const u = (k: number): number => unit(j, seed * 7 + k)
      s += `<ellipse cx="${g(cx + (u(1) - 0.5) * w * 0.8)}" cy="${g(cy + (u(2) - 0.5) * h * 1.8)}" rx="${g(w * (0.1 + 0.28 * u(3)))}" ry="${g(h * (0.16 + 0.28 * u(4)))}" opacity="${g(0.4 + 0.6 * u(5))}"/>`
    }
    return s
  }
  const far = rough(
    [[266, 600], [266, 554], [320, 552], [332, 553], [342, 551.5], [352, 553], [364, 551], [376, 552.5], [388, 550.5], [398, 552.5], [410, 550.5], [422, 552], [436, 551], [510, 553], [510, 600]],
    7, 0.14, 1.3, [0, 1, 12, 13],
  )
  const crown = rough(
    [[266, 600], [266, 478], [271, 466], [278, 458], [286, 449], [297, 448], [305, 451], [312, 446], [322, 443], [331, 450], [340, 455], [346, 466], [351, 476], [355, 484], [357, 494], [354, 499], [359, 509], [361, 520], [357, 527], [359, 535], [350, 544], [347, 549], [310, 551], [306, 600]],
    11, 0.55, 1.4, [0, 1, 2, 3, 22],
  )
  const right = rough(
    [[432, 600], [431, 574], [433, 560], [435, 548], [440, 536], [446, 526], [454, 521], [461, 524], [467, 520], [474, 515], [483, 510], [491, 506], [499, 505], [506, 507], [512, 510], [512, 600]],
    23, 0.55, 1.4, [0, 14],
  )

  const BX = 272.6
  let slats = ''
  for (let i = 0; i < 13; i++) {
    const u = (k: number): number => unit(i, 40 + k)
    const y = 246.2 + i * 6.25 + (u(1) - 0.5) * 0.6
    const k = 1.5 * (i / 12) ** 2 + (u(2) - 0.5) * 0.5
    const h = 3.7 + u(3) * 0.8
    const b = 0.7 + u(4) * 0.8
    slats += `<path d="M${BX} ${g(y)}Q388 ${g(y + b)} 504 ${g(y + k)}v${g(h)}Q388 ${g(y + h + b)} ${BX} ${g(y + h)}z"/>`
  }
  const rail = `M${BX} 327.4L504 329V334.2L${BX} 332.6Z`
  const head = `M${BX} 237.4H504V244.6H${BX}Z`

  const [sU, sUd] = sash(234, 416, SU, 17, 12, gop)
  const [sL, sLd] = sash(292, 474, SL, 12, 22, gop)

  const so = 1.016
  const casing = 'M243 207H531V593H504V234H270V593H243Z'

  let defs =
    lin('sky', 0, 234, 0, 563, [
      [0, '#08112c'], [0.18, '#0c1638'], [0.38, '#161d48'], [0.55, '#241f50'], [0.68, '#3a2853'],
      [0.78, '#563354'], [0.86, '#7a4650'], [0.93, '#8b5541'], [0.97, '#955e43'], [1, '#8a5844'],
    ]) +
    rad('ag', 452, 556, 150, [[0, '#b8744e', 0.24], [1, '#b8744e', 0]], ' gradientTransform="matrix(1 0 0 .4 0 333.6)"') +
    lin('cl', 0, 0, 0, 1, [[0, '#2a2650', 0.35], [0.55, '#6a4462', 0.55], [1, '#d08a6c', 0.9]], false) +
    lin('hz', 0, 547, 0, 565, [[0, '#3a2c4c'], [1, '#1e1a32']]) +
    lin('fd', 0, 560, 0, 594, [[0, '#171426'], [1, '#08090f']]) +
    lin('sk', 0, 474, 0, 590, [[0, '#2a2638', 0], [0.75, '#4a3a4a', 0.13], [1, '#2a2638', 0.06]]) +
    lin('sn', 0, 594, 0, 602.7, [[0, '#28243a', 0.7], [0.3, '#18161f', 0.3], [1, '#07080f', 0.6]]) +
    lin('mg', 0, 0, -26, -4.3, [[0, '#f2f4ff', 0.95], [1, '#f2f4ff', 0]]) +
    rad('ff', 0, 0, 4, [[0, '#f6ffc0'], [0.16, '#d6f07a', 0.9], [0.45, '#9ccf45', 0.16], [1, '#9ccf45', 0]]) +
    rad('yl', 0, 0, 9, [[0, '#dfe9ff', 0.5], [0.3, '#9fb6ff', 0.14], [1, '#9fb6ff', 0]]) +
    lin('gl', 0, 0, 1, 1, [[0, '#8a96c8', 0], [0.42, '#8a96c8', 0], [0.5, '#8a96c8', 0.05], [0.62, '#8a96c8', 0]], false) +
    rad('hb', 438, 546, 128, [[0, '#b06e4c', 0.16], [0.5, '#8a5244', 0.06], [1, '#8a5244', 0]], ' gradientTransform="matrix(1 0 0 .27 0 398.6)"') +
    `<filter id="window-nf" x="0" y="0" width="1" height="1"><feTurbulence type="fractalNoise" baseFrequency=".04 .7" numOctaves="2" stitchTiles="stitch"/><feColorMatrix values="0 0 0 0 .8 0 0 0 0 .8 0 0 0 0 .9 0 0 0 1.8 -.75"/></filter>` +
    `<pattern id="window-gr" width="128" height="128" patternUnits="userSpaceOnUse"><rect width="128" height="128" filter="url(#window-nf)"/></pattern>` +
    `<pattern id="window-gv" href="#window-gr" patternTransform="rotate(90)"/>` +
    `<filter id="window-tb" filterUnits="userSpaceOnUse" x="262" y="436" width="254" height="168"><feGaussianBlur stdDeviation=".5"/></filter>` +
    `<filter id="window-cb" filterUnits="userSpaceOnUse" x="266" y="384" width="244" height="94"><feGaussianBlur stdDeviation="1.2"/></filter>` +
    lin('ao', 0, 0, 1, 0, [[0, '#04050a', 0], [1, '#04050a', 0.5]], false) +
    `<linearGradient id="window-aoR" href="#window-ao" x1="1" x2="0"/><linearGradient id="window-aoT" href="#window-ao" x2="0" y2="1"/>` +
    lin('us', 0, 601, 0, 608, [[0, '#07060a', 0.6], [1, '#07060a', 0]]) +
    `<g id="window-w"><path id="window-c" d="${casing}"/><path id="window-a" d="M248 601H526V625H248Z"/>` +
    `<polygon id="window-t" points="236,593 538,593 ${pts([proj(538, 593, so), proj(236, 593, so)])}"/>` +
    `<path id="window-n" d="${sub(236, 593, 538, 601, so)}"/>` +
    `<polygon id="window-e" points="538,593 538,601 ${pts([proj(538, 601, so), proj(538, 593, so)])}"/>` +
    `<polygon id="window-i" points="270,593 504,593 ${pts([proj(504, 593, SS), proj(270, 593, SS)])}"/>` +
    `<path id="window-k" d="M239 203.5h296v5H239Z"/></g>` +
    `<g id="window-bl">${slats}<path d="${rail}"/></g>` +
    `<g id="window-cd"><ellipse cx="466.9" cy="592.9" rx="2.2" ry=".6" fill="#05060b" stroke="none" opacity=".4"/><path d="M466.2 244.6V586.6M467.2 244.6V586.6" fill="none"/><path d="M466.7 586c-1.3 0-1.6 2.6-1.4 4.6.2 1.6.7 2.4 1.4 2.4s1.2-.8 1.4-2.4c.2-2-.1-4.6-1.4-4.6z"/></g>` +
    `<path id="window-wd" d="M276.6 245.6V401" stroke-linecap="round" fill="none"/>` +
    `<path id="window-ld" d="M300 244.6V328.6M388 244.6V329.5M474 244.6V330.4" fill="none"/>` +
    `<path id="window-s1" ${sU.slice(6)}` +
    `<path id="window-s2" ${sL.slice(6)}`

  if (!L6) {
    defs +=
      lin('ap', 0, 606, 0, 625, [[0, '#05060b', 0], [1, '#05060b', 0.4]]) +
      lin('jb', 270, 0, 289, 0, [[0, '#141220'], [1, '#262236']]) +
      lin('st', 0, 589, 0, 593, [[0, '#2a2638'], [1, '#1c1a28']]) +
      lin('cs', 243, 207, 531, 600, [[0, '#120e10'], [1, '#0e0b0d']]) +
      lin('sf', 270, 0, 510, 0, [[0, '#0f0c10'], [1, '#130f13']]) +
      lin('bb', 0, 0, 0, 1, [[0, '#2b2944'], [0.35, '#1c1b2e'], [1, '#0c0c15']], false) +
      lin('hr', 0, 237, 0, 245, [[0, '#17161f'], [0.8, '#1d1c28'], [1, '#09090f']])
  }
  if (L6) {
    defs +=
      lin('cL', 470, 207, 290, 620, [[0, '#4c3320'], [0.5, '#3c281a'], [1, '#2c1d12']]) +
      lin('tL', 0, 593, 0, 603, [[0, '#3f2a19'], [1, '#5e4027']]) +
      lin('nL', 0, 593, 0, 602, [[0, '#6a4a2e'], [0.2, '#4a3220'], [1, '#2e1f13']]) +
      lin('aL', 0, 601, 0, 625, [[0, '#2a1c12'], [0.4, '#3a2818'], [1, '#44301e']]) +
      lin('jL', 270, 0, 289, 0, [[0, '#2e1f13'], [1, '#3e2a1a']]) +
      lin('sL', 270, 0, 504, 0, [[0, '#2e1f14'], [1, '#3a2819']]) +
      lin('bL', 0, 0, 0, 1, [[0, '#9a907e'], [0.22, '#887f6e'], [0.7, '#706a5d'], [1, '#45403a']], false) +
      lin('bs', 272, 0, 504, 0, [[0, '#1a1410', 0.3], [0.14, '#1a1410', 0.08], [0.8, '#1a1410', 0], [1, '#1a1410', 0.14]]) +
      lin('hL', 0, 237, 0, 245, [[0, '#6e675a'], [0.75, '#857c6b'], [1, '#3e3a32']]) +
      lin('rf', 300, 330, 262, 468, [[0, '#c9b49a', 0.16], [0.38, '#c9b49a', 0.1], [0.44, '#3a4d78', 0.14], [0.8, '#3a4d78', 0.05], [1, '#3a4d78', 0]]) +
      lin('rg', 0, 0, 1, 1, [[0.25, '#9a8a78', 0], [0.42, '#9a8a78', 0.08], [0.58, '#9a8a78', 0.02], [0.7, '#9a8a78', 0]], false) +
      rad('sh', 0, 0, 1, [[0, '#0c1226', 0.55], [0.6, '#0c1226', 0.3], [1, '#0c1226', 0]], ' gradientTransform="matrix(20 0 0 225 243 418)"') +
      rad('sv', 0, 0, 1, [[0, '#0c1226', 0.5], [1, '#0c1226', 0]], ' gradientTransform="matrix(170 0 0 15 387 601)"')
  }
  if (L1) {
    defs +=
      rad('tl', 600, 470, 300, [[0, '#2b3a80', 0.16], [1, '#2b3a80', 0]]) +
      lin('tv', 0, 0, 1, 0, [[0, '#3456e6', 0], [1, '#3456e6', 0.06]], false) +
      lin('rr', 531, 0, 532.6, 0, [[0, '#1f2540', 0.85], [1, '#1f2540', 0]]) +
      lin('rl', 272.6, 0, 270, 0, [[0, '#2a2843'], [1, '#2a2843', 0]])
  }
  if (L7) defs += rad('lp', 516, 572, 55, [[0, '#ffb070', 0.6], [0.3, '#e08848', 0.3], [1, '#e08848', 0]]) + rad('lq', 506, 586, 58, [[0, '#e09050', 0.16], [1, '#e09050', 0]])
  if (!L6) defs += rad('sp', 387, 430, 330, [[0, '#2a3364', 0.42], [0.45, '#1e2550', 0.2], [1, '#141a3a', 0]]) + rad('fl', 330, 905, 190, [[0, '#1d2448', 0.16], [1, '#1d2448', 0]], ' gradientTransform="matrix(1 0 0 .3 0 633.5)"')

  const stars: [number, number, number][] = [[306, 344, 0.8], [343, 372, 0.6], [372, 351, 0.7], [421, 340, 0.9], [466, 366, 0.6], [447, 391, 0.55], [313, 388, 0.6]]
  const flies: [number, number, number, string][] = [[306, 488, 7.3, 'a'], [329, 497, 8.9, 'b'], [349, 523, 6.6, 'a'], [447, 541, 9.6, 'b'], [474, 538, 7.9, 'a'], [490, 534, 8.4, 'b'], [455, 546, 9.1, 'a']]

  let body = ''
  body += `<rect x="266" y="232" width="246" height="366" fill="url(#window-sky)"/><rect x="266" y="470" width="246" height="102" fill="url(#window-ag)"/>`
  body += stars.map(([x, y, r], i) => `<circle class="window-tw" cx="${x}" cy="${y}" r="${r}" fill="#dfe4ff" opacity=".5" style="animation-delay:-${i * 2 + 2}s;animation-duration:${7 + (i % 3) * 2}s"/>`).join('')
  body += `<g transform="translate(300 343)"><g class="window-met" opacity="0"><path d="M0 0L-26-4.3" stroke="url(#window-mg)" stroke-width=".9" stroke-linecap="round"/><circle r=".9" fill="#f6f7ff"/></g></g>`
  body += `<g filter="url(#window-cb)" fill="url(#window-cl)">${cloud(350, 437, 110, 5, 1, 4)}${cloud(446, 454, 100, 4, 2, 3)}${cloud(380, 404, 96, 3, 3, 3)}${cloud(318, 471, 70, 3, 4, 2)}</g>`
  const tb = '<g filter="url(#window-tb)">'
  const holes = [[300, 452, 0.9, 0.6], [318, 449.5, 0.6, 0.5], [335, 455, 1.1, 0.7], [344, 466, 0.7, 0.5], [350, 489, 1, 0.6], [357, 500, 0.6, 0.5], [353, 515, 0.9, 0.6], [359, 526, 0.6, 0.4], [347, 538, 1.2, 0.7], [452, 528, 0.8, 0.5], [471, 522, 1.1, 0.6], [487, 513, 0.6, 0.5], [440, 541, 0.7, 0.5]]
  body += `${tb}<path d="${far}" fill="url(#window-hz)"/>`
  body += `<path d="M266 562L300 561L340 562.5L380 560.5L420 562L460 561L510 562V600H266Z" fill="url(#window-fd)"/></g>`
  body += `<g transform="translate(384 557)"><circle r="9" fill="url(#window-yl)"/><circle r=".8" fill="#e8f0ff"/></g>`
  body += `<path d="M422.9 584L423.4 436H425.3L425.9 584ZM418.5 441.6H430V442.8H418.5Z" fill="#07080e"/>`
  body += `<path d="M419 441.4Q380 452 338 460M429.5 441.4Q470 448 512 446" stroke="#07080e" stroke-width=".5" fill="none"/>`
  body += `${tb}<path d="${crown}" fill="#06070c"/><path d="${right}" fill="#06070c"/>`
  body += `<g fill="url(#window-sky)">${holes.map(([x, y, a, b]) => `<ellipse cx="${x}" cy="${y}" rx="${a}" ry="${b}"/>`).join('')}</g></g>`
  body += flies.map(([x, y, d, k], i) => `<g transform="translate(${x} ${y})"><circle class="window-f${k}" r="4" fill="url(#window-ff)" opacity="${i % 3 === 0 ? 0.45 : 0}" style="animation-duration:${d}s;animation-delay:-${i * 2 + 2}s"/></g>`).join('')
  body += `<rect x="289" y="474" width="216" height="116" fill="#0b0d18" opacity=".36"/><rect x="289" y="474" width="216" height="116" fill="#2a2238" opacity=".07"/><rect x="289" y="474" width="216" height="116" fill="url(#window-sk)"/>`
  const scr = 'M289.1 474H292V589.6H289.1ZM289.1 585.8H505V589.6H289.1Z'
  body += `<path d="${scr}" fill="#191a2a"/><rect x="292" y="585.8" width="213" height=".8" fill="#3c3148" opacity=".7"/>`
  if (L6) body += `<rect x="270" y="234" width="234" height="240" fill="#06070c" opacity=".5"/><rect x="266" y="474" width="246" height="124" fill="#06070c" opacity=".32"/><rect x="270" y="234" width="234" height="240" fill="url(#window-rf)"/><rect x="270" y="234" width="234" height="240" fill="url(#window-rg)"/><rect x="289" y="474" width="216" height="116" fill="#6a6258" opacity=".13"/><path d="${scr}" fill="#5a524a" opacity=".7"/>`
  if (L7) body += `<rect x="440" y="520" width="66" height="72" fill="url(#window-lq)"/>`
  const jamb = `270,234 270,593 ${pts([proj(270, 593, SS), proj(270, 234, SS)])}`
  /** Dusk fill, or the lit fill when L6 is on. */
  const lit = (dusk: string, l6: string): string => `fill="${(L6 ? l6 : dusk).replace(/^(\w+)$/, 'url(#window-$1)')}"`
  body += `<polygon points="${jamb}" ${lit('jb', 'jL')}/>`
  body += [0.995, 0.981].map(s => box(270, 234, 270.8, 593, s, 'fill="#07080f" opacity=".45"')).join('')
  body += `<polygon points="270,234 504,234 ${pts([proj(504, 234, SS), proj(270, 234, SS)])}" ${lit('#0b0c16', '#1e150f')}/>`
  body += use('i', lit('st', 'tL'))
  const sashFill = (id: string): string => use(id, lit('sf', 'sL')) + (L1 ? use(id, 'fill="url(#window-tl)"') : '')
  body += box(270, 234, 504, 416, SU, 'fill="#0a0d22" opacity=".14"') + box(270, 234, 504, 416, SU, 'fill="url(#window-gl)"')
  body += sashFill('s1') + sUd
  body += `<g transform="rotate(.22 390 384)">`
  body += box(270, 292, 504, 474, SL, 'fill="#0a0d22" opacity=".12"')
  if (L1) body += `<rect x="392" y="304" width="100" height="148" fill="url(#window-tv)"/>`
  body += sashFill('s2') + sLd
  if (L1) body += `<rect x="392" y="452" width="112" height="22" fill="url(#window-tv)" opacity=".5"/>`
  body += `<rect x="277" y="472.6" width="230" height="1.4" fill="#4a3440" opacity=".45"/>`
  body += `<path d="M388 295.2q5-5.4 10 0z" fill="#2b2519"/><path d="M389.5 293q3.5-2.8 7 0" stroke="#6a5a3a" stroke-width=".4" fill="none" opacity=".6"/>`
  body += [325, 455].map(x => `<rect x="${x}" y="460.6" width="7" height="2.6" rx="1.1" fill="#221d14"/><rect x="${x + 1}" y="460.7" width="5" height=".5" fill="#6a5a3a" opacity=".45"/>`).join('')
  body += `</g>`
  body += `<path d="${head}" ${lit('hr', 'hL')}/>` + use('bl', lit('bb', 'bL'))
  if (L1) body += `<rect x="272" y="237" width="232" height="98" fill="url(#window-tv)"/>`
  if (L6) body += `<rect x="272" y="237" width="232" height="98" fill="url(#window-bs)"/>`
  body += `<path d="M${BX} 244.6H504v.9H${BX}Z" fill="#05060b" opacity=".6"/>`
  body += use('ld', L6 ? 'stroke="#a89e8a" stroke-width=".4" opacity=".28"' : 'stroke="#2a2a40" stroke-width=".45" opacity=".6"')
  body += use('wd', L6 ? 'stroke="#8e8573" stroke-width="1.1" opacity=".4"' : 'stroke="#2c2c48" stroke-width="1.1" opacity=".45"')
  body += use('cd', (L6 ? 'stroke="#8e8573" fill="#8e8573" stroke-width=".5" opacity=".85"' : 'stroke="#0d0d15" fill="#14141c" stroke-width=".5"') + ' class="window-cy"')
  body += use('t', lit('st', 'tL')) + use('n', lit('cs', 'nL')) + use('e', lit('#120e11', '#2a1c14')) + use('a', lit('cs', 'aL')) + use('c', lit('cs', 'cL')) + use('k', lit('#110e12', '#4a3220'))
  body += box(236, 593, 538, 593.9, so, `fill="${L6 ? '#7a5a3a' : '#2a2638'}" opacity=".7"`)
  body += `<path d="M243 207H531V234H243Z" fill="url(#window-gr)" opacity="${gop}"/><path d="M243 234H270V593H243ZM504 234H531V593H504Z" fill="url(#window-gv)" opacity="${gop}"/>`
  body += `${L6 ? '' : '<rect x="248" y="606" width="278" height="19" fill="url(#window-ap)"/>'}<rect x="248" y="618.5" width="278" height="1.2" fill="#06070d" opacity=".5"/><rect x="248" y="619.7" width="278" height=".8" fill="${L6 ? '#5a3e26' : '#1c1a24'}" opacity=".5"/>`
  body += box(236, 593.9, 538, 601, so, 'fill="url(#window-sn)"')
  body += `<rect x="239" y="203.5" width="296" height=".8" fill="${L6 ? '#7a5838' : '#221f2a'}" opacity=".6"/><rect x="239" y="208.5" width="296" height="1.6" fill="#06070d" opacity=".55"/>`
  body += `<path d="M243 207H531V211H243ZM243 211H247V593H243ZM527 211H531V593H527Z" fill="#07080f" opacity=".3"/>`
  body += `<path d="M266.6 230.6H507.4V232H266.6ZM266.6 232H268V593H266.6Z" fill="#07080f" opacity=".3"/>`
  body += `<rect x="270" y="234" width="2.6" height="359" fill="${L6 ? '#4e3522' : L1 ? 'url(#window-rl)' : '#1c1a29'}" opacity=".8"/><rect x="531" y="207" width="${L1 ? 1.6 : 1.3}" height="386" fill="${L6 ? '#3e2a1a' : L1 ? 'url(#window-rr)' : '#0f0d11'}"/>`
  if (L1) body += use('w', 'fill="url(#window-tl)"')
  if (L7) body += 'ctne'.split('').map(k => use(k, 'fill="url(#window-lp)"')).join('')
  body += `<rect x="248" y="601" width="278" height="7" fill="url(#window-us)"${L6 ? ' opacity=".3"' : ''}/>`

  let under = `<g${L6 ? ' opacity=".45"' : ''}><rect x="235" y="207" width="8" height="396" fill="url(#window-ao)"/><rect x="531" y="207" width="8" height="396" fill="url(#window-aoR)"/><rect x="239" y="198" width="296" height="9" fill="url(#window-aoT)"/></g>`
  under = L6
    ? `<rect x="222" y="192" width="21" height="452" fill="url(#window-sh)"/><rect x="216" y="601" width="342" height="16" fill="url(#window-sv)"/>` + under
    : `<rect x="40" y="100" width="720" height="750" fill="url(#window-sp)"/><rect x="100" y="850" width="460" height="110" fill="url(#window-fl)"/>` + under

  const over = `<rect x="262" y="510" width="262" height="72" fill="url(#window-hb)"${L6 ? ' opacity=".4"' : ''}/>`

  const style =
    `.window-tw{animation:window-tw 9s ease-in-out infinite alternate}` +
    `@keyframes window-tw{from{opacity:.25}to{opacity:.7}}` +
    `.window-fa{animation:window-fa 8s ease-in-out infinite}.window-fb{animation:window-fb 8s ease-in-out infinite}` +
    `@keyframes window-fa{0%{opacity:0;transform:translate(0,0)}22%{opacity:.9}48%{opacity:.12}62%,100%{opacity:0;transform:translate(3px,-2.5px)}}` +
    `@keyframes window-fb{0%{opacity:0;transform:translate(0,0)}25%{opacity:.85}50%{opacity:.1}64%,100%{opacity:0;transform:translate(-2.5px,-1.5px)}}` +
    `.window-cy{transform-origin:466.7px 244.6px;animation:window-cy 11s ease-in-out infinite alternate}` +
    `@keyframes window-cy{from{transform:rotate(-.04deg)}to{transform:rotate(.06deg)}}` +
    `.window-met{animation:window-met 3600s linear infinite}` +
    `@keyframes window-met{0%,6.66%{opacity:0;transform:translate(0,0)}6.668%{opacity:.85}6.712%{opacity:.5}6.722%,100%{opacity:0;transform:translate(128px,21px)}}`

  return { style, defs, under, body, over }
}
