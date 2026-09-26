// ink.js: stroke-built ink for two-tone, hand-drawn-looking Canvas 2D animation.
// Contract for every function here:
//   - deterministic: output depends only on the arguments; randomness comes from rng(seed, step).
//   - `step` is the boil counter (e.g. floor(t * 8) for animation on 3s at 24 fps). Same step, same drawing;
//     a new step re-lays every stroke, which is what makes the ink crawl. `boil: 0` freezes a shape.
//   - no alpha blending on ink (two-tone rule); only paperGrain uses alpha, by design.
//   - no dependencies, no DOM access beyond the ctx passed in (paperGrain creates one offscreen canvas).
//   - the default ink is INK; a scene in a style passes the pack's palette.ink as `color`.

export const INK = '#141211';

export function rng(seed, step = 0) {
  let a = (Math.imul(seed | 0, 0x9E3779B1) ^ Math.imul(step | 0, 0x85EBCA77)) >>> 0;
  return () => { a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
}

// One round-ended brush dab. The building block of everything else.
export function capsule(ctx, x1, y1, x2, y2, w, color) {
  ctx.strokeStyle = color; ctx.lineWidth = w; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2 + 0.01, y2); ctx.stroke();
}

// Longest-edge direction of a polygon: the natural hatch direction for rays, bars, buildings.
export function principalAngle(pts) {
  let best = 0, ang = 0;
  for (let i = 0; i < pts.length; i++) {
    const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length], d = (x2 - x1) ** 2 + (y2 - y1) ** 2;
    if (d > best) { best = d; ang = Math.atan2(y2 - y1, x2 - x1); }
  }
  return ang;
}

// inkFill(ctx, pts, opts): fill a closed polygon with rows of overlapping round-ended strokes.
//   pts       [[x,y],...] closed polygon (any winding; even-odd spans)
//   color     fill colour
//   seed,step identity and boil counter; boil (0..1) scales how much of the layout re-rolls per step
//   angle     hatch direction in radians (default: longest edge)
//   width     stroke thickness in px (default 12); row pitch is width * pitch (default 0.78)
//   len       [min,max] stroke length in px (default [30, 120])
//   dryBrush  0..1 chance of a paper gap between consecutive strokes in a row (default 0.12)
//   overshoot how far stroke ends wander past the polygon edge, in widths (default 0.6): the comb edge
export function inkFill(ctx, pts, o = {}) {
  const color = o.color || INK, w = o.width || 12, pitch = o.pitch || 0.78, [l0, l1] = o.len || [30, 120];
  const dry = o.dryBrush ?? 0.12, over = o.overshoot ?? 0.6, boil = o.boil ?? 1;
  const r = rng(o.seed || 1, boil ? o.step || 0 : 0), a = o.angle ?? principalAngle(pts), c = Math.cos(a), s = Math.sin(a);
  const loc = pts.map(([x, y]) => [x * c + y * s, -x * s + y * c]); // rotate so strokes run along +x
  let y0 = Infinity, y1 = -Infinity; for (const p of loc) { y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); }
  ctx.strokeStyle = color; ctx.lineCap = 'round';
  for (let y = y0 + w * (0.2 + 0.3 * r()); y < y1 - w * 0.1; y += w * pitch * (0.85 + 0.3 * r())) {
    const xs = [];
    for (let i = 0; i < loc.length; i++) {
      const [ax, ay] = loc[i], [bx, by] = loc[(i + 1) % loc.length];
      if ((ay <= y) !== (by <= y)) xs.push(ax + (y - ay) / (by - ay) * (bx - ax));
    }
    xs.sort((p, q) => p - q);
    for (let k = 0; k + 1 < xs.length; k += 2) {
      const a0 = xs[k], b0 = xs[k + 1];
      let x = a0 + (r() - 0.65) * w * over * 2;
      const end = b0 + (r() - 0.35) * w * over * 2;
      while (x < end) {
        const x2 = Math.min(end, x + l0 + (l1 - l0) * r()), yy = y + (r() - 0.5) * w * 0.25, lw = w * (0.75 + 0.4 * r());
        const tilt = (r() - 0.5) * w * 0.3;
        ctx.lineWidth = lw; ctx.beginPath();
        ctx.moveTo(x * c - yy * s, x * s + yy * c); ctx.lineTo(x2 * c - (yy + tilt) * s, x2 * s + (yy + tilt) * c); ctx.stroke();
        if (x2 >= end) break;
        x = x2 + (r() < dry ? w * (0.4 + 1.2 * r()) : -w * (0.3 + 0.4 * r()));
      }
    }
  }
}

// inkStroke(ctx, pts, opts): a brushed line along a polyline, built from dabs.
//   width     base thickness; taper [start, end] multipliers (default [1, 0.25])
//   strands   parallel sub-strokes across the width (default 1); >1 leaves cream grooves between them
//   dab       dab length in px (default 3 * width, min 14); dryBrush chance of a skipped dab (default 0.08)
//   wobble    per-step perpendicular jitter in widths (default 0.15)
export function inkStroke(ctx, pts, o = {}) {
  const color = o.color || INK, W = o.width || 10, [t0, t1] = o.taper || [1, 0.25], n = o.strands || 1;
  const dry = o.dryBrush ?? 0.08, wob = o.wobble ?? 0.15, r = rng(o.seed || 1, o.boil === 0 ? 0 : o.step || 0);
  const cum = [0]; for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
  const total = cum[cum.length - 1]; if (total < 0.5) return;
  const at = d => { let i = 1; while (i < cum.length - 1 && cum[i] < d) i++; const u = (d - cum[i - 1]) / ((cum[i] - cum[i - 1]) || 1), p = pts[i - 1], q = pts[i], L = Math.hypot(q[0] - p[0], q[1] - p[1]) || 1;
    return [p[0] + (q[0] - p[0]) * u, p[1] + (q[1] - p[1]) * u, -(q[1] - p[1]) / L, (q[0] - p[0]) / L]; };
  const dab = o.dab || Math.min(45, Math.max(14, W * 1.5));
  for (let sI = 0; sI < n; sI++) {
    const off = n > 1 ? (sI / (n - 1) - 0.5) : 0;
    let d = r() * dab * 0.3;
    while (d < total) {
      const d2 = Math.min(total, d + dab * (0.6 + 0.8 * r())), u = d / total, wd = W * (t0 + (t1 - t0) * u);
      if (r() >= dry || d === 0) {
        const [x1, y1, nx, ny] = at(d), [x2, y2] = at(d2), sw = n > 1 ? wd / n * 0.85 : wd, j1 = (r() - 0.5) * wd * wob * 2, j2 = (r() - 0.5) * wd * wob * 2;
        const o1 = off * wd * 0.9 + j1, o2 = off * wd * 0.9 + j2;
        capsule(ctx, x1 + nx * o1, y1 + ny * o1, x2 + nx * o2, y2 + ny * o2, sw * (0.8 + 0.35 * r()), color);
      }
      if (d2 >= total) break;
      d = d2 - dab * 0.15 * r();
    }
  }
}

// splatter(ctx, cx, cy, r, opts): specks and flicked dashes around a point.
//   dots      count of round specks; positions fixed by seed, each blinks off with probability `flicker` per step
//   dashes    count of short radial flicks, fully re-laid every step
//   size      speck radius scale in px (default 3)
export function splatter(ctx, cx, cy, R, o = {}) {
  const color = o.color || INK, fixed = rng(o.seed || 1, 0), live = rng(o.seed || 1, (o.step || 0) + 1), sz = o.size || 3;
  for (let i = 0; i < (o.dots ?? 10); i++) {
    const a = fixed() * 6.283, d = Math.sqrt(fixed()) * R, rad = sz * (0.4 + fixed()), show = live() >= (o.flicker ?? 0.3);
    if (show) { const jx = (live() - 0.5) * sz, jy = (live() - 0.5) * sz; capsule(ctx, cx + Math.cos(a) * d + jx, cy + Math.sin(a) * d + jy, cx + Math.cos(a) * d + jx + 0.5, cy + Math.sin(a) * d + jy, rad * 2, color); }
  }
  for (let i = 0; i < (o.dashes ?? 6); i++) {
    const a = live() * 6.283, d = R * (0.3 + live()), l = sz * (2 + 6 * live());
    capsule(ctx, cx + Math.cos(a) * d, cy + Math.sin(a) * d, cx + Math.cos(a) * (d + l), cy + Math.sin(a) * (d + l), sz * (0.6 + live()), color);
  }
}

// dashedLine(ctx, x1, y1, x2, y2, opts): hand-inked dashed line whose dashes crawl each step.
//   dash, gap   px lengths (default 9, 6); width px (default 2.5); double: 0 or px offset for a second parallel line
export function dashedLine(ctx, x1, y1, x2, y2, o = {}) {
  const color = o.color || INK, dash = o.dash || 9, gap = o.gap || 6, w = o.width || 2.5, r = rng(o.seed || 1, o.step || 0);
  const L = Math.hypot(x2 - x1, y2 - y1); if (L < 1) return;
  const ux = (x2 - x1) / L, uy = (y2 - y1) / L;
  for (const off of o.double ? [-o.double / 2, o.double / 2] : [0]) {
    for (let d = r() * (dash + gap); d < L; d += dash + gap + (r() - 0.5) * gap) {
      const l = dash * (0.6 + 0.8 * r()), j = (r() - 0.5) * w * 0.6 + off, e = Math.min(L, d + l);
      capsule(ctx, x1 + ux * d - uy * j, y1 + uy * d + ux * j, x1 + ux * e - uy * j, y1 + uy * e + ux * j, w * (0.8 + 0.4 * r()), color);
    }
  }
}

// paperGrain(ctx, w, h, opts): faint paper tooth over the whole frame, shifted per step so it boils.
//   The one deliberate alpha use (7-10%). Cached per seed/size.
const grains = new Map();
export function paperGrain(ctx, w, h, o = {}) {
  const seed = o.seed || 999, key = `${seed}:${w}x${h}`, step = o.step || 0;
  if (!grains.has(key)) {
    const g = document.createElement('canvas'); g.width = w + 64; g.height = h + 64;
    const gc = g.getContext('2d'), r = rng(seed);
    for (let i = 0; i < (w * h) / 66; i++) { gc.fillStyle = r() < .5 ? 'rgba(20,18,17,0.10)' : 'rgba(240,235,225,0.07)'; gc.fillRect(r() * g.width, r() * g.height, 1 + r() * 2, 1 + r() * 2); }
    grains.set(key, g);
  }
  ctx.drawImage(grains.get(key), -((step * 37) % 64), -((step * 23) % 64));
}
