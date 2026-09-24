// roto.js: render traced drawings from <dir>/dNNN.json through the ink.js brush engine. Loaded by render.html?scene=roto.js.
//   window.renderDrawing(k) -> Promise; draws drawing k onto canvas#c at the source size.
//   window.renderFrame(t)   -> Promise; draws the drawing on screen at film time t: the last k with pts <= t.
//   Query: ?mode=a (plain even-odd fill, the baseline) | b (default: tone layers, bias ring, blur), ?dir=d (JSON folder),
//          ?brush={json} (overrides BRUSH), ?brushes=file.json ({"k": {brush}}, wins over everything; used by fit.py).
//   Deterministic: same k, same pixels. Paths only; no raster data.
import { capsule, paperGrain } from './ink.js';

const q = new URLSearchParams(location.search), MODE = q.get('mode') || 'b', DIR = q.get('dir') || 'd';
const cv = document.getElementById('c'), ctx = cv.getContext('2d');
const ix = await (await fetch(`${DIR}/index.json`)).json();   // {w, h, duration, drawings: [[k, pts, t1], ...]}
const PER = q.get('brushes') ? await (await fetch(q.get('brushes'))).json() : {};
cv.width = ix.w; cv.height = ix.h;
const cache = new Map();
const load = k => cache.get(k) || cache.set(k, fetch(`${DIR}/d${String(k).padStart(3, '0')}.json`).then(r => r.json())).get(k);

// Mode (b) defaults (reference/method.md). A drawing's `brush` (from the override file) overrides any key.
//   bias  px of ink added along every T edge (negative thins): a ring of ink.js capsules of width 2|bias| on the contour
//   blur  gaussian sigma in px over the finished drawing: the source's edge softness (codec + scaling)
//   grain 0 = off; else paperGrain opacity (uncorrelated grain lowers SSIM, so it stays off for a copy)
//   tones 0 = two-tone only (T layer in the ink colour)
export const BRUSH = { bias: 0.12, blur: 0.6, grain: 0, ...JSON.parse(q.get('brush') || '{}') };

function rings(d) {
  const out = [];
  for (const p of d.paths) { out.push(p.d); for (const h of p.holes) out.push(h); }
  return out;
}

function fillPaths(c, d, color) {
  const path = new Path2D();
  for (const r of rings(d)) {
    path.moveTo(r[0], r[1]);
    for (let i = 2; i < r.length; i += 2) path.lineTo(r[i], r[i + 1]);
    path.closePath();
  }
  c.fillStyle = color; c.fill(path, 'evenodd');
}

function edgeRing(c, L, bias, col) {
  const w = 2 * Math.abs(bias);
  for (const r of rings(L)) {
    const n = r.length / 2;
    for (let i = 0; i < n; i++) { const j = (i + 1) % n; capsule(c, r[2 * i], r[2 * i + 1], r[2 * j], r[2 * j + 1], w, col); }
  }
}

function draw(d) {
  const b = { ...BRUSH, ...(d.brush || {}), ...(PER[d.k] || {}) };
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.filter = 'none';
  ctx.fillStyle = d.paper; ctx.fillRect(0, 0, cv.width, cv.height);
  if (MODE === 'a') return fillPaths(ctx, d, d.ink);
  const off = new OffscreenCanvas(cv.width, cv.height), o = off.getContext('2d');
  o.fillStyle = d.paper; o.fillRect(0, 0, cv.width, cv.height);
  // tone layers light to dark; the T layer (d.paths) is the one XOR measures, and the only one `bias` moves
  const layers = [...(b.tones === 0 ? [] : d.tones || []), { lv: d.T, color: b.tones === 0 ? d.ink : d.t_color || d.ink, paths: d.paths }]
    .sort((p, q) => q.lv - p.lv);
  let above = d.paper;
  for (const L of layers) {
    const isT = L.paths === d.paths;
    if (isT && b.bias > 0) edgeRing(o, L, b.bias, L.color);
    fillPaths(o, L, L.color);
    if (isT && b.bias < 0) edgeRing(o, L, b.bias, above);
    above = L.color;
  }
  if (b.grain) { o.globalAlpha = b.grain; paperGrain(o, cv.width, cv.height, { seed: 999, step: d.k }); o.globalAlpha = 1; }
  ctx.drawImage(off, 0, 0);
  if (b.blur) gauss(ctx, b.blur);
}

// Separable gaussian on the canvas pixels. ctx.filter blur() silently drops sigmas below ~0.8 px in Chromium.
function gauss(c, sigma) {
  const w = cv.width, h = cv.height, im = c.getImageData(0, 0, w, h), p = im.data, R = Math.ceil(sigma * 3);
  const k = Array.from({ length: 2 * R + 1 }, (_, i) => Math.exp(-((i - R) ** 2) / (2 * sigma * sigma)));
  const sum = k.reduce((a, b) => a + b); for (let i = 0; i < k.length; i++) k[i] /= sum;
  const tmp = new Float32Array(w * h * 3);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) for (let ch = 0; ch < 3; ch++) {
    let s = 0; for (let i = -R; i <= R; i++) s += k[i + R] * p[(y * w + Math.min(w - 1, Math.max(0, x + i))) * 4 + ch];
    tmp[(y * w + x) * 3 + ch] = s;
  }
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) for (let ch = 0; ch < 3; ch++) {
    let s = 0; for (let i = -R; i <= R; i++) s += k[i + R] * tmp[(Math.min(h - 1, Math.max(0, y + i)) * w + x) * 3 + ch];
    p[(y * w + x) * 4 + ch] = s;   // Uint8ClampedArray rounds; adding 0.5 here double-rounds every channel upward
  }
  c.putImageData(im, 0, 0);
}

window.renderDrawing = async k => draw(await load(k));
window.renderFrame = async t => {
  let k = ix.drawings[0][0];
  for (const [kk, p] of ix.drawings) { if (p <= t + 1e-6) k = kk; else break; }
  return window.renderDrawing(k);
};
window.DURATION = ix.duration;
