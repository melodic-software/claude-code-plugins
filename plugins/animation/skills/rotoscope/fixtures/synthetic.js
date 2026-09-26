// synthetic.js: the committed test scene regress.py --synthetic renders, encodes, re-traces and measures.
//   24 distinct drawings held alternately 2 and 3 frames at 24 fps (60 frames, 2.5 s); each drawing
//   moves a brushed ink mass and re-lays its strokes, so no two drawings repeat. Deterministic (ink.js rng).
import { INK, inkFill, inkStroke } from './ink.js';

export const DRAWINGS = 24;
const HOLDS = Array.from({ length: DRAWINGS }, (_, k) => (k % 2 ? 3 : 2));
const START = HOLDS.reduce((a, h) => [...a, a[a.length - 1] + h], [0]);   // first frame of each drawing
const W = 480, H = 270, PAPER = '#efe9e0';
const cv = document.getElementById('c'), ctx = cv.getContext('2d');
cv.width = W; cv.height = H;
window.DURATION = START[DRAWINGS] / 24;

function draw(k) {
  ctx.fillStyle = PAPER; ctx.fillRect(0, 0, W, H);
  inkStroke(ctx, [[12, 12], [W - 12, 12], [W - 12, H - 12], [12, H - 12], [12, 12]], { width: 8, taper: [1, 1], seed: 3, step: k });
  const x = 90 + k * 12, y = 135 + 30 * Math.sin(k / 3);
  inkFill(ctx, [[x - 60, y - 40], [x + 50, y - 55], [x + 70, y + 35], [x - 40, y + 50]], { width: 10, seed: 5, step: k, color: INK });
  inkStroke(ctx, [[40, H - 50], [W / 2, H - 70 - 4 * (k % 5)], [W - 40, H - 45]], { width: 9, seed: 7, step: k, color: INK });
}

window.renderDrawing = async k => draw(k);
window.renderFrame = async t => {
  const f = Math.round(t * 24);
  let k = 0;
  while (k + 1 < DRAWINGS && START[k + 1] <= f) k++;
  draw(k);
};
