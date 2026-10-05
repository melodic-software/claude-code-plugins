"""Frame-level QC for a rendered demo: decodes the MP4 and measures every acceptance rule from the
rendered frames. The camera rect of each frame is estimated by registering the frame against the
capture it samples (normalized cross-correlation over scale and position), never read from the EDL,
so a producer's own numbers cannot pass a video the frames contradict.

Checks (thresholds: defaults.json "qc" and "motion", overridable with --config):
  capture-match   every page frame matches its capture at some zoom (registration is trustworthy)
  zoom-share      share of runtime (title excluded) at >= zoom_threshold, at least zoom_share_min
  edge-clip       a settled zoomed frame cuts no text: every frame edge that is not the page
                  boundary lies in a gutter of the capture under it
  target-headroom each click target is in shot with safe-margin headroom at its click
  caption-anchor  captions sit only at the primary anchor or the one fixed fallback
  stillness       no still stretch (caption band masked) longer than still_max
  motion          every camera move within the zoom/pan speed and acceleration caps
  nav-cuts        each page cut is taken with the camera still; one that changes the URL (the EDL's
                  nav_cuts say where) at 1.0x, an in-page state cut at 1.0x or with clean edges
  crossfade       no frame is a blend of the frames around a page change
  blank           no white, black or flat frame after the title
Camera-dependent checks report SKIP when the EDL's camera layer is off (plain style).

usage: qc.py EDL.json VIDEO.mp4 OUT_DIR [--config FILE]
exit: 0 every check passed, 1 a check failed, 2 the inputs could not be read
Writes OUT_DIR/qc.json and contact sheets (cuts, zoom peaks, longest still, each failure) for the
independent reviewer.
"""
import argparse
import json
import math
import subprocess
import sys
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from demo_common import SMOOTH_10_90, SMOOTH_PEAK_A, SMOOTH_PEAK_V, Ink, anchor_box, edge_ink, font, load_config

AW, AH = 240, 135   # registration resolution
SW, SH = 480, 270   # stillness / blend resolution


def decode(video, w, h):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(video), '-vf', f'scale={w}:{h}:flags=area', '-f', 'rawvideo',
                          '-pix_fmt', 'gray', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(np.float32)


def ncc_valid(img, T):
    """Normalized cross-correlation of template T over every position where it fits inside img."""
    th, tw = T.shape
    ih, iw = img.shape
    T0 = T - T.mean()
    tn = math.sqrt(float((T0 ** 2).sum())) or 1.0
    shape = (ih, iw)
    corr = np.fft.irfft2(np.fft.rfft2(img) * np.fft.rfft2(T0[::-1, ::-1], s=shape), s=shape)[th - 1:ih, tw - 1:iw]
    S1 = np.pad(img.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    S2 = np.pad((img * img).cumsum(0).cumsum(1), ((1, 0), (1, 0)))

    def box(S):
        return S[th:, tw:] - S[:-th, tw:] - S[th:, :-tw] + S[:-th, :-tw]
    n = th * tw
    # a near-flat window (blank page area) would divide by ~0: floor its variance at a share of the template's
    var = np.maximum(box(S2) - box(S1) ** 2 / n, 0.05 * tn * tn + 1e-6)
    return corr / (tn * np.sqrt(var))


class Registrar:
    """Finds where a rendered frame sits in its capture. The caption band at the bottom is left out
    of the template (rows >= `rows`): a caption pill is drawn there, not part of the page."""

    def __init__(self, W, H, zmax, rows):
        self.W, self.H, self.zmax, self.rows = W, H, zmax, rows
        self.full = lru_cache(maxsize=8)(lambda p: Image.open(p).convert('L'))
        self.scaled = lru_cache(maxsize=256)(self._scaled)

    def _scaled(self, path, zq):
        z = zq / 1000
        return np.asarray(self.full(path).resize((round(AW * z), round(AH * z)), Image.BOX), np.float32)

    def score(self, frame, path, z):
        img = self.scaled(path, int(round(z * 1000)))
        if img.shape[0] < AH or img.shape[1] < AW:
            return -1.0, (0, 0)
        r = ncc_valid(img[:img.shape[0] - (AH - self.rows)], frame[:self.rows])
        k = np.unravel_index(int(r.argmax()), r.shape)
        return float(r[k]), (int(k[1]), int(k[0]))

    def estimate(self, frame, path, hint=None):
        """(zoom, rect in CSS px, score) for a frame showing part of the capture at `path`."""
        def scan(zs):
            return [(float(z),) + self.score(frame, path, z) for z in zs]
        res = []
        if hint:
            res = scan(np.arange(max(1.0, hint - 0.03), hint + 0.0301, 0.01))
        if not res or max(r[1] for r in res) < 0.7:
            res = scan(np.arange(1.0, self.zmax + 0.15, 0.04))
            zb = max(res, key=lambda r: r[1])[0]
            res = scan(np.arange(max(1.0, zb - 0.04), zb + 0.0401, 0.01))
        res.sort()
        j = max(range(len(res)), key=lambda i: res[i][1])
        z, s, (px, py) = res[j]
        if 0 < j < len(res) - 1:   # parabolic refinement over scale
            a, b, c = res[j - 1][1], s, res[j + 1][1]
            den = a - 2 * b + c
            if den < 0:
                z += 0.5 * (a - c) / den * (res[j + 1][0] - res[j][0])
        k = self.W / AW
        w = self.W / z
        return z, [px / res[j][0] * k, py / res[j][0] * k, w, self.H / z], s


def sheet(frames_rgb, items, path):
    cols, tw, th = 3, 640, 360
    rows = max(1, (len(items) + cols - 1) // cols)
    img = Image.new('RGB', (cols * tw, rows * (th + 30)), (255, 255, 255))
    d = ImageDraw.Draw(img)
    f = font(18)
    for n, (fi, label) in enumerate(items):
        x, y = (n % cols) * tw, (n // cols) * (th + 30)
        img.paste(frames_rgb(fi).resize((tw, th), Image.LANCZOS), (x, y + 30))
        d.text((x + 6, y + 5), label, font=f, fill=(0, 0, 0))
    img.save(path)


def spans(idx, fps):
    """Frame indices -> 't0-t1s' spans for messages."""
    out, start, prev = [], None, None
    for i in idx:
        if start is None:
            start = prev = i
        elif i == prev + 1:
            prev = i
        else:
            out.append(f'{start / fps:.2f}-{(prev + 1) / fps:.2f}s')
            start = prev = i
    if start is not None:
        out.append(f'{start / fps:.2f}-{(prev + 1) / fps:.2f}s')
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('edl')
    ap.add_argument('video')
    ap.add_argument('out')
    ap.add_argument('--config')
    a = ap.parse_args(argv)
    try:
        edl = json.loads(Path(a.edl).read_text())
        log = json.loads(Path(a.video).with_suffix('.render.json').read_text())['frames']
        tl = json.loads((Path(edl['capture']) / 'timeline.json').read_text())
    except (OSError, ValueError, KeyError) as e:
        print(f'qc: cannot read inputs: {e}', file=sys.stderr)
        return 2
    cfg = load_config(a.config) if a.config else edl.get('config') or load_config()
    Q, MOT, CAM, CAP = cfg['qc'], cfg['motion'], cfg['camera'], cfg['captions']
    W, H, fps = edl['width'], edl['height'], edl['fps']
    cap_dir = Path(edl['capture'])
    by_t = {round(f['t'], 4): str(cap_dir / f['file']) for f in tl['frames']}
    camera_on = edl['layers'].get('camera', True)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    results = []

    def check(name, status, detail):
        results.append({'check': name, 'status': status, 'detail': detail})

    reg_frames = decode(a.video, AW, AH)
    small = decode(a.video, SW, SH)
    n = min(len(reg_frames), len(small), len(log))
    runtime = [i for i in range(n) if log[i]['captures'] and not any(isinstance(s, str) for s in log[i]['src'])]
    if not runtime:
        print('qc: no page frames found', file=sys.stderr)
        return 2

    # ---- registration: zoom and rect per runtime frame, measured from the frame ------------------
    rows = int((H - CAP['margin'] - CAP['pill_h'] - CAP['clear']) * AH / H)
    reg = Registrar(W, H, CAM['zmax'], rows)
    est = {}
    prev = None
    for i in runtime:
        path = by_t.get(round(log[i]['captures'][-1], 4))
        if path is None:
            print(f'qc: frame {i} names a capture not in the timeline', file=sys.stderr)
            return 2
        if prev is not None and est[prev][3] == path and np.abs(reg_frames[i] - reg_frames[prev]).max() < 2:
            est[i] = est[prev]   # an unchanged frame keeps its measurement
        else:
            z, rect, s = reg.estimate(reg_frames[i], path, est[prev][0] if prev is not None else None)
            est[i] = (z, rect, s, path)
        prev = i
    poor = [i for i in runtime if est[i][2] < Q['match_min']]
    check('capture-match', 'FAIL' if poor else 'PASS',
          f"min NCC {min(est[i][2] for i in runtime):.3f} (floor {Q['match_min']})" + (f"; poor at {spans(poor, fps)[:6]}" if poor else ''))

    lnz = np.log(np.array([est[i][0] for i in runtime]))
    cx = np.array([est[i][1][0] + est[i][1][2] / 2 for i in runtime])
    cy = np.array([est[i][1][1] + est[i][1][3] / 2 for i in runtime])
    good = np.array([est[i][2] >= Q['match_min'] for i in runtime])
    if good.any() and not good.all():   # a frame that does not match its capture gives no rect: interpolate
        at = np.arange(len(runtime))
        lnz, cx, cy = (np.interp(at, at[good], v[good]) for v in (lnz, cx, cy))
    def med5(v):   # registration noise is one or two frames wide
        p = np.pad(v, 2, mode='edge')
        return np.median(np.stack([p[k:k + len(v)] for k in range(5)]), axis=0)
    lnz, cx, cy = med5(lnz), med5(cx), med5(cy)
    zf = np.exp(lnz)

    # camera still at a frame: no zoom or pan change across a settled_frames window
    dz = np.abs(np.diff(lnz, prepend=lnz[0]))
    dp = np.hypot(np.diff(cx, prepend=cx[0]), np.diff(cy, prepend=cy[0])) * zf / W
    moving = (dz > 0.002) | (dp > 0.002)
    k = Q['settled_frames']
    settled = np.array([not moving[max(0, j - k // 2):j + k // 2 + 1].any() for j in range(len(runtime))])

    # ---- zoom share ---------------------------------------------------------------------------
    if camera_on:
        zoomed = zf >= Q['zoom_threshold'] - 0.005
        share = float(zoomed.mean())
        check('zoom-share', 'PASS' if share >= Q['zoom_share_min'] else 'FAIL',
              f"{share:.0%} of {len(runtime) / fps:.2f}s runtime at >= {Q['zoom_threshold']}x (min {Q['zoom_share_min']:.0%}); "
              f"{zoomed.sum() / fps:.2f}s zoomed")
    else:
        check('zoom-share', 'SKIP', 'camera layer off (plain style)')

    # ---- edge clipping on settled zoomed frames, against the capture under each edge ---------------
    masks = edl.get('content_masks', [])

    @lru_cache(maxsize=32)
    def ink_for(path, src_key):
        mb = next((tuple(m['box']) for m in masks if m['src0'] <= src_key <= m['src1']), None)
        return Ink(path, W, H, CAM['word_gap'], mb)
    clipped = {}
    for j, i in enumerate(runtime):
        if not settled[j] or zf[j] < 1.02:
            continue
        rect = [cx[j] - W / zf[j] / 2, cy[j] - H / zf[j] / 2, W / zf[j], H / zf[j]]
        rect[0] = min(max(rect[0], 0.0), W - rect[2])
        rect[1] = min(max(rect[1], 0.0), H - rect[3])
        # registration is good to about one analysis pixel: an edge passes if a gutter lies within that
        # distance of where it was measured, and an edge that close to the page edge is the page edge
        prec = W / AW / zf[j]
        ink = ink_for(est[i][3], log[i]['captures'][-1])
        worst = None
        for d in np.arange(-prec, prec + 1e-6, 1.0):
            e = edge_ink(ink, [rect[0] + d, rect[1] + d, rect[2], rect[3]], Q['edge_band'], W, H, 2 * prec)
            worst = e if worst is None else {k2: min(worst.get(k2, v), v) for k2, v in e.items()}
        bad = {k2: round(v, 1) for k2, v in (worst or {}).items() if v > Q['edge_ink_max']}
        if bad:
            clipped[i] = bad
    if camera_on:
        detail = 'no settled zoomed frame cuts text'
        if clipped:
            first = next(iter(clipped))
            detail = f'text cut at {spans(sorted(clipped), fps)[:6]}; first {first / fps:.2f}s edges {clipped[first]}'
        check('edge-clip', 'FAIL' if clipped else 'PASS', detail)
    else:
        check('edge-clip', 'SKIP', 'camera layer off (plain style)')

    # ---- click targets keep headroom ------------------------------------------------------------
    if camera_on:
        bad = []
        for s in edl.get('steps', []):
            fi = int(round(s['click_out'] * fps))
            j = next((j for j, i in enumerate(runtime) if i >= fi), None)
            if j is None:
                continue
            z = zf[j]
            r = [cx[j] - W / z / 2, cy[j] - H / z / 2, W / z, H / z]
            tb, m = s['target_box'], CAM['safe_margin'] / z / 2
            inside = (tb[0] >= r[0] + m or r[0] < 1) and (tb[1] >= r[1] + m or r[1] < 1) and \
                (tb[0] + tb[2] <= r[0] + r[2] - m or r[0] + r[2] > W - 1) and (tb[1] + tb[3] <= r[1] + r[3] - m or r[1] + r[3] > H - 1)
            if not inside:
                bad.append(f"{s['id']}@{s['click_out']:.2f}s")
        check('target-headroom', 'FAIL' if bad else 'PASS', f'targets out of shot or at the frame edge: {bad}' if bad else 'every click target in shot with headroom')
    else:
        check('target-headroom', 'SKIP', 'camera layer off (plain style)')

    # ---- caption anchors ------------------------------------------------------------------------
    if edl['layers'].get('captions'):
        allowed = CAP['anchors'][:2]
        bad = [c['text'] for c in edl.get('captions', [])
               if c.get('slot') not in allowed or list(c['box']) != list(anchor_box(c['slot'], c['box'][2], W, H, cfg))]
        check('caption-anchor', 'FAIL' if bad else 'PASS', f'off-anchor captions: {bad}' if bad else f'primary or fallback only ({allowed})')
    else:
        check('caption-anchor', 'SKIP', 'captions layer off')

    # ---- stillness (caption band masked) --------------------------------------------------------
    band0 = int((H - CAP['margin'] - CAP['pill_h'] - CAP['clear']) * SH / H)
    band1 = int(math.ceil((H - CAP['margin'] + CAP['clear']) * SH / H))
    sm = small.copy()
    sm[:, band0:band1, :] = 0
    diff = np.abs(sm[1:] - sm[:-1]).reshape(len(sm) - 1, SH // 15, 15, SW // 16, 16).mean(axis=(2, 4)).max(axis=(1, 2))
    rset = set(runtime)
    longest, run, run_start, worst = 0, 0, None, None
    for i in range(1, n):
        if i in rset and (i - 1) in rset and diff[i - 1] < Q['still_block_delta']:
            if run == 0:
                run_start = i - 1
            run += 1
            if (run + 1) / fps > longest:
                longest, worst = (run + 1) / fps, (run_start, i)
        else:
            run = 0
    check('stillness', 'PASS' if longest <= Q['still_max'] + 1 / fps else 'FAIL',
          f"longest still {longest:.2f}s (max {Q['still_max']}s)" + (f' at {worst[0] / fps:.2f}-{(worst[1] + 1) / fps:.2f}s' if worst else ''))

    # ---- motion: each move's peaks from its measured 10-90% duration and total change --------------
    tol = 1 + Q['motion_tolerance']
    moves, j = [], 0
    while j < len(runtime):
        if moving[j]:
            s0 = j
            while j < len(runtime) and (moving[j] or (j + 1 < len(runtime) and moving[j + 1])):
                j += 1
            moves.append((max(s0 - 1, 0), min(j, len(runtime) - 1)))
        j += 1
    over = []
    for s0, s1 in moves:
        if runtime[s1] - runtime[s0] != s1 - s0:
            continue   # spans a gap in runtime frames (title): not a camera move
        dl = lnz[s1] - lnz[s0]
        pv = np.hypot(cx - cx[s0], cy - cy[s0])
        dpan = float(pv[s1]) * max(zf[s0], zf[s1]) / W
        for name, delta, prog, lim_v, lim_a in (
                ('zoom', abs(dl), (lnz[s0:s1 + 1] - lnz[s0]) / dl if abs(dl) > 0.02 else None, MOT['max_zoom_rate'], MOT['max_zoom_accel']),
                ('pan', dpan, pv[s0:s1 + 1] / pv[s1] if dpan > 0.02 else None, MOT['max_pan_speed'], MOT['max_pan_accel'])):
            if prog is None:
                continue
            t = np.arange(len(prog)) / fps
            t10 = float(np.interp(0.1, np.maximum.accumulate(prog), t))
            t90 = float(np.interp(0.9, np.maximum.accumulate(prog), t))
            T = max((t90 - t10) / SMOOTH_10_90, 1 / fps)
            v, acc = SMOOTH_PEAK_V * delta / T, SMOOTH_PEAK_A * delta / T ** 2
            if v > lim_v * tol or acc > lim_a * tol:
                over.append(f'{name} {runtime[s0] / fps:.2f}-{runtime[s1] / fps:.2f}s: {v:.2f}/s (cap {lim_v}), {acc:.2f}/s^2 (cap {lim_a}), T {T:.2f}s')
    check('motion', 'FAIL' if over else 'PASS', over[:6] if over else f'{len(moves)} camera moves within the caps')

    # ---- page cuts: camera still; a URL change at 1.0x, an in-page state cut at 1.0x or clean edges --
    # The EDL says only where the URL changes; the zoom at each cut is the one measured from the frames.
    pos = {i: j for j, i in enumerate(runtime)}
    url_frames = {int(round(c * fps)) for c in edl.get('nav_cuts', [])}
    caps_small = {}

    def cap_small(path):
        if path not in caps_small:
            caps_small[path] = np.asarray(Image.open(path).convert('L').resize((SW, SH), Image.BOX), np.float32)
        return caps_small[path]
    cuts, bad_cuts = [], []
    for i in runtime[1:]:
        if (i - 1) not in rset or est[i][3] == est[i - 1][3]:
            continue
        url = bool({i - 1, i, i + 1} & url_frames)
        changed = float((np.abs(cap_small(est[i][3]) - cap_small(est[i - 1][3])) > 24).mean())
        if not url and changed < Q['nav_change_min']:
            continue
        j = pos[i]
        cuts.append(i)
        url_frames -= {i - 1, i, i + 1}
        still = not moving[max(0, j - 2):j + 3].any()
        at_one = zf[j - 1] <= Q['nav_zoom_max'] and zf[j] <= Q['nav_zoom_max']
        clean = (i not in clipped) and ((i - 1) not in clipped)
        if not (still and (at_one or (clean and not url))):
            bad_cuts.append(f"{'URL' if url else 'state'} cut {i / fps:.2f}s zoom {zf[j - 1]:.2f}->{zf[j]:.2f} still={still}")
    bad_cuts += [f'URL cut at {f / fps:.2f}s shows no page change in the frames' for f in sorted(url_frames)]
    check('nav-cuts', 'FAIL' if bad_cuts else 'PASS',
          bad_cuts or f'{len(cuts)} page cuts, camera still; URL changes at 1.0x, state cuts at 1.0x or with clean edges')

    # ---- crossfades: a frame that is a blend of its neighbors across a page change ------------------
    # Checked around each page change only: slow camera motion also makes a frame resemble the average
    # of its neighbors, and is not a crossfade.
    blends = []
    near_cut = sorted({c + d for c in cuts for d in range(-4, 5)} & rset)
    for i in near_cut:
        if (i - 1) not in rset or (i + 1) not in rset:
            continue
        A, B, F = sm[i - 1], sm[i + 1], sm[i]   # caption band masked: a caption fade is a designed blend
        d = A - B
        if float(np.abs(d).mean()) < 0.5:   # neighbors alike: nothing to blend (typing, cursor travel)
            continue
        alpha = float(((F - B) * d).sum() / max((d * d).sum(), 1e-6))
        resid = float(np.abs(F - (alpha * A + (1 - alpha) * B)).mean())
        nearest = min(float(np.abs(F - A).mean()), float(np.abs(F - B).mean()))
        if 0.15 < alpha < 0.85 and nearest > 0.3 and resid < Q['crossfade_gain'] * nearest:
            blends.append(i)
    check('crossfade', 'FAIL' if blends else 'PASS', f'blended frames at {spans(blends, fps)[:6]}' if blends else 'every page change is a hard cut')

    # ---- blank, white or flat frames ------------------------------------------------------------
    flat = [i for i in runtime if small[i].std() < Q['blank_std'] or (small[i].mean() > Q['white_luma'] and small[i].std() < 3 * Q['blank_std'])]
    check('blank', 'FAIL' if flat else 'PASS', f'flat or white frames at {spans(flat, fps)[:6]}' if flat else 'no flat or white frame')

    # ---- report and contact sheets ----------------------------------------------------------------
    @lru_cache(maxsize=64)
    def rgb(fi):
        raw = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{fi / fps:.4f}', '-i', str(a.video), '-frames:v', '1',
                              '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], capture_output=True, check=True).stdout
        return Image.frombytes('RGB', (W, H), raw)
    peaks = sorted(runtime, key=lambda i: -zf[pos[i]])[:3]
    items = [(i, f'cut {i / fps:.2f}s') for i in cuts[:6]] + [(i, f'zoom {zf[pos[i]]:.2f}x {i / fps:.2f}s') for i in peaks]
    if worst:
        items.append((worst[0], f'still from {worst[0] / fps:.2f}s'))
    sheet(rgb, items, out / 'sheet-key-moments.png')
    fails = [(sorted(clipped)[:1], 'edge-clip'), (blends[:1], 'crossfade'), (flat[:1], 'blank'), (poor[:1], 'capture-match')]
    fail_items = [(i, f'{name} {i / fps:.2f}s') for idx, name in fails for i in idx]
    if fail_items:
        sheet(rgb, fail_items, out / 'sheet-failures.png')
    report = {'video': str(a.video), 'runtime_s': round(len(runtime) / fps, 3), 'checks': results,
              'zoom_series': [[round(runtime[j] / fps, 3), round(float(zf[j]), 3)] for j in range(len(runtime))]}
    (out / 'qc.json').write_text(json.dumps(report, indent=1))
    for r in results:
        print(f"{r['status']:4} {r['check']}: {r['detail']}")
    failed = [r['check'] for r in results if r['status'] == 'FAIL']
    print(f"qc: {'FAIL ' + ', '.join(failed) if failed else 'all checks passed'} -> {out / 'qc.json'}")
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
