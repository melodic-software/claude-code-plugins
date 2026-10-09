"""Stage 2 of the demo-video pipeline: turn a capture (record.mjs's timeline.json) and a script
(captions, outcomes, narration text) into edl.json, the edit-decision list produce.py renders.
Every editing choice (retiming, holds, cuts, camera keyframes, caption text and placement, audio
placement) lands in the EDL as data, and the plan refuses to write an EDL that breaks a rule.

Camera rules (produced style):
  - each action is framed on its semantic block with safe-margin headroom; every frame edge that
    is not the page boundary lies in a gutter (no text line or block crosses it), and one caption
    anchor (primary, else the one fixed fallback) is empty page;
  - every zoom change is an eased move inside the motion limits (defaults.json "motion");
  - a navigating click eases back to 1.0x and the camera is still across the hard cut; on the
    landed page it pushes in on the next action or the content;
  - a still stretch longer than the QC limit gets a slow gutter-snapped push-in.
Other rules: nothing between a navigating click and the settled page reaches the output, nor any
logged loading state; no transition other than the title dip (no crossfades).

Narration (--audio-dir DIR): per caption one clip, DIR/<step>[.outcome|.results]/narration.wav with
its words.json (the /speech:narrate output layout) or DIR/<step>[...].wav|.m4a. Leading silence is
trimmed to the first word. A step's cursor travel or hold stretches until its clips fit.

usage: build_edl.py CAPTURE_DIR SCRIPT.json OUT_EDL.json [--audio-dir DIR] [--style produced|plain]
                    [--layers title=on,camera=off,...] [--config FILE] [--font FILE]
exit: 0 written, 1 the plan breaks a rule (each broken rule printed)
"""
import argparse
import bisect
import json
import math
from pathlib import Path

import numpy as np

from demo_common import (SMOOTH_PEAK_A, SMOOTH_PEAK_V, Ink, anchor_box, clip_duration, edge_ink, load_config, move_duration,
                         pill_width, smooth)

LAYERS = ('title', 'camera', 'cursor', 'ripple', 'captions', 'narration')
STYLE_OFF = {'produced': set(), 'plain': {'title', 'camera', 'captions'}}


def parse_layers(style, spec, audio_dir=None):
    """The style decides which layers exist (plain has no title, camera or captions); a toggle set to
    off or false removes its layer in either style, and on or true keeps the style's choice.
    Narration exists when there is an audio directory to play."""
    layers = {k: k not in STYLE_OFF[style] for k in LAYERS}
    layers['narration'] = bool(audio_dir)
    for item in filter(None, (spec or '').split(',')):
        name, _, value = item.partition('=')
        if name not in LAYERS or value not in ('on', 'off', 'true', 'false'):
            raise SystemExit(f'--layers: expected NAME=on|off with NAME in {LAYERS}, got {item!r}')
        if value in ('off', 'false'):
            layers[name] = False
    return layers


def counts(integ, x0, y0, x1, y1, W, H):
    """Vectorized area counts on an integral image; x*/y* broadcast to one shape."""
    x0 = np.clip(np.floor(x0), 0, W).astype(int)
    x1 = np.clip(np.ceil(x1), 0, W).astype(int)
    y0 = np.clip(np.floor(y0), 0, H).astype(int)
    y1 = np.clip(np.ceil(y1), 0, H).astype(int)
    return integ[y1, x1] - integ[y0, x1] - integ[y1, x0] + integ[y0, x0]


def move_seconds(origin, z, X, Y, W, H, motion):
    """move_duration from `origin` to every candidate rect (zoom z, top-left X, Y), vectorized."""
    z0 = W / origin[2]
    dz = abs(math.log(z / z0))
    c0x, c0y = origin[0] + origin[2] / 2, origin[1] + origin[3] / 2
    dp = np.hypot(X + W / z / 2 - c0x, Y + H / z / 2 - c0y) * max(z0, z) / W
    zr, pr, za, pa = motion['max_zoom_rate'], motion['max_pan_speed'], motion['max_zoom_accel'], motion['max_pan_accel']
    V, A = SMOOTH_PEAK_V, SMOOTH_PEAK_A
    t = np.maximum.reduce([np.full_like(dp, motion['min_move_duration']), np.full_like(dp, V * dz / zr), V * dp / pr,
                           np.full_like(dp, math.sqrt(A * dz / za)), np.sqrt(A * dp / pa)])
    f = motion['combined_fraction']
    both = (V * dz / t > f * zr) & (V * dp / t > f * pr)
    t = np.where(both, np.maximum(t, V * np.minimum(dz / (f * zr), dp / (f * pr))), t)
    return t * 1.02


def focus_rect(ink, block, target, W, H, cfg, pill_w, zrange, prefer=None, origin=None, budget=None, exit_budget=None):
    """The shot for a block: highest zoom in zrange (aspect W:H) that holds the block with safe-margin
    headroom on every edge that is not the page boundary, puts every other edge in a gutter, leaves a
    caption anchor (primary first, else the fallback) on empty page, and, with `budget`, is reachable
    from `origin` in that many seconds inside the motion limits. Among those, the one nearest the
    preferred center (block center pulled halfway toward the target, or `prefer`).
    Returns (rect, zoom, anchor) or (None, 1.0, None)."""
    cam, cap = cfg['camera'], cfg['captions']
    zmin, zmax = zrange
    if block is not None:
        bx, by, bw, bh = block
        cx, cy = bx + bw / 2, by + bh / 2
        if target is not None:
            cx += (target[0] + target[2] / 2 - cx) * 0.5
            cy += (target[1] + target[3] / 2 - cy) * 0.5
    else:
        cx, cy = prefer if prefer else (W / 2, H / 2)
    band, limit, step = cam['gutter_band'], cam['edge_ink'], cam['search_step']
    clear = cap['clear'] + 8
    integ = ink.integ
    best_by_zoom = []
    for z in np.arange(zmax, zmin - 1e-6, -0.05):
        z = float(z)
        w, h = W / z, H / z
        m = cam['safe_margin'] / z
        xs = np.unique(np.append(np.arange(0.0, W - w, step), W - w))
        ys = np.unique(np.append(np.arange(0.0, H - h, step), H - h))
        X, Y = np.meshgrid(xs, ys)
        ok = np.ones_like(X, bool)
        if block is not None:
            lo_x = (X < 0.5) & (bx >= 0) | (bx - X >= m)
            hi_x = (X + w > W - 0.5) & (bx + bw <= W) | (X + w - (bx + bw) >= m)
            lo_y = (Y < 0.5) & (by >= 0) | (by - Y >= m)
            hi_y = (Y + h > H - 0.5) & (by + bh <= H) | (Y + h - (by + bh) >= m)
            ok &= lo_x & hi_x & lo_y & hi_y
        left = np.where(X > 0.5, counts(integ, X - band, Y, X + band, Y + h, W, H), 0)
        right = np.where(X + w < W - 0.5, counts(integ, X + w - band, Y, X + w + band, Y + h, W, H), 0)
        top = np.where(Y > 0.5, counts(integ, X, Y - band, X + w, Y + band, W, H), 0)
        bottom = np.where(Y + h < H - 0.5, counts(integ, X, Y + h - band, X + w, Y + h + band, W, H), 0)
        ok &= (left <= limit) & (right <= limit) & (top <= limit) & (bottom <= limit)
        if budget is not None and origin is not None:
            ok &= move_seconds(origin, z, X, Y, W, H, cfg['motion']) <= budget
        if exit_budget is not None:   # a navigating click's shot eases back to 1.0x before the cut
            ok &= move_seconds([0.0, 0.0, W, H], z, X, Y, W, H, cfg['motion']) <= exit_budget
        if not ok.any():
            continue
        dist = np.abs(X + w / 2 - cx) + np.abs(Y + h / 2 - cy)
        for anchor in cap['anchors']:
            ax, ay, aw, ah = anchor_box(anchor, pill_w, W, H, cfg)
            area = counts(integ, X + (ax - clear) / z, Y + (ay - clear) / z, X + (ax + aw + clear) / z, Y + (ay + ah + clear) / z, W, H)
            good = ok & (area <= limit)
            if good.any():
                k = np.unravel_index(np.where(good, dist, np.inf).argmin(), dist.shape)
                x0, y0 = float(X[k]), float(Y[k])
                off = max(abs(x0 + w / 2 - cx) / w, abs(y0 + h / 2 - cy) / h)
                best_by_zoom.append((round(float(z), 3), off, [round(x0, 2), round(y0, 2), round(w, 2), round(h, 2)], anchor))
                break
    if not best_by_zoom:
        return None, 1.0, None
    top = best_by_zoom[0][0]
    centered = [b for b in best_by_zoom if b[1] <= 0.08 and b[0] >= top - 0.15 - 1e-6]
    z, _, rect, anchor = centered[0] if centered else best_by_zoom[0]
    return rect, z, anchor


def contains(outer, inner, margin=0.0):
    return (inner[0] >= outer[0] + margin and inner[1] >= outer[1] + margin and
            inner[0] + inner[2] <= outer[0] + outer[2] - margin and inner[1] + inner[3] <= outer[1] + outer[3] - margin)


def load_clip(audio_dir, name):
    """(file, trim, duration) for a narration clip, or None. With words.json the leading silence
    before the first word is trimmed (Kokoro pads each clip) and the clip ends after the last word."""
    d = Path(audio_dir)
    folder = d / name
    if (folder / 'narration.wav').exists():
        f = folder / 'narration.wav'
        total = clip_duration(f)
        words_file = folder / 'words.json'
        if words_file.exists():
            words = json.loads(words_file.read_text()).get('words') or []
            if words:
                trim = max(0.0, words[0]['start'] - 0.05)
                end = min(total, words[-1]['end'] + 0.15)
                return str(f.resolve()), round(trim, 3), round(end - trim, 3)
        return str(f.resolve()), 0.0, round(total, 3)
    for ext in ('.wav', '.m4a', '.mp3'):
        f = d / f'{name}{ext}'
        if f.exists():
            return str(f.resolve()), 0.0, round(clip_duration(f), 3)
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('capture')
    ap.add_argument('script')
    ap.add_argument('out')
    ap.add_argument('--audio-dir')
    ap.add_argument('--style', choices=sorted(STYLE_OFF), default='produced')
    ap.add_argument('--layers', default='')
    ap.add_argument('--config')
    ap.add_argument('--font')
    a = ap.parse_args(argv)
    cfg = load_config(a.config)
    P, CAM, MOT, CAP, NAR = cfg['pacing'], cfg['camera'], cfg['motion'], cfg['captions'], cfg['narration']
    layers = parse_layers(a.style, a.layers, a.audio_dir)
    cap = Path(a.capture).resolve()
    tl = json.loads((cap / 'timeline.json').read_text())
    script = json.loads(Path(a.script).read_text())
    W, H, dsf = tl['width'], tl['height'], tl.get('dsf', 1)
    ev, frames = tl['events'], tl['frames']
    ftimes = [f['t'] for f in frames]
    full = [0.0, 0.0, float(W), float(H)]

    def capture_at(t):
        return cap / frames[max(0, bisect.bisect_right(ftimes, t) - 1)]['file']

    # a step id logged only by demo.moveTo is cursor travel, not a step: the cursor layer draws it
    # inside whichever segment its source time falls in
    order = []
    for e in ev:
        if e.get('step') and e['name'] != 'move' and e['step'] not in order:
            order.append(e['step'])
    by = {s: [e for e in ev if e.get('step') == s] for s in order}

    def first(s, name):
        return next((e for e in by[s] if e['name'] == name), None)

    def last(s, name):
        return next((e for e in reversed(by[s]) if e['name'] == name), None)

    start_t = next(e['t'] for e in ev if e['name'] == 'start')
    end_t = next(e['t'] for e in ev if e['name'] == 'end')
    moves = [e for e in ev if e['name'] == 'move']
    errs = []
    for s in order:
        for need in ('move', 'click', 'settled'):
            if first(s, need) is None:
                errs.append(f'step {s}: no {need} event (each step is a demo.click ... demo.settle)')
    if errs:
        raise SystemExit('capture is not a demo replay:\n  ' + '\n  '.join(errs))

    infos = {s: script.get('steps', {}).get(s, {}) for s in order}
    steps = []
    for i, s in enumerate(order):
        ck, st, typ = first(s, 'click'), last(s, 'settled'), first(s, 'type')
        # the travel that ends at the click; an earlier demo.moveTo under the same id plays before it
        mv = next((e for e in reversed(by[s]) if e['name'] == 'move' and e['t'] <= ck['t']), first(s, 'move'))
        nav = (ck.get('url') or '') != (st.get('url') or ck.get('url') or '')
        steps.append({'id': s, 'mv': mv, 'ck': ck, 'st': st, 'typ': typ, 'navigates': nav and not typ,
                      'caption': infos[s].get('caption', s), 'outcome': infos[s].get('outcome'),
                      'target_box': ck['box'], 'block': ck.get('block')})

    # ---- shots (source-time decisions: what each action's shot frames) ------------------------
    # Each shot must be reachable from where the camera is in the time the edit gives it: a click shot by
    # the click (cursor travel), a typing shot within open_modal plus a beat, a landing shot within one
    # second; so no move runs long and the motion limits pick a smaller zoom instead of a slow drag.
    zr_shot = (CAM['zmin_shot'], CAM['zmax'])
    zr_land = (CAM['zmin_shot'], CAM['landing_zoom'] + 0.1)

    def pad_block(box):
        return [box[0] - 120, box[1] - 80, box[2] + 240, box[3] + 160]
    cur = full
    for k, stp in enumerate(steps):
        ck, st, typ = stp['ck'], stp['st'], stp['typ']
        pw = max(pill_width(stp['caption'], cfg, a.font), pill_width(stp['outcome'] or '', cfg, a.font))
        tb = ck['box']
        edge = CAM['edge_min']
        at_edge = tb[0] < edge or tb[1] < edge or tb[0] + tb[2] > W - edge or tb[1] + tb[3] > H - edge
        held = layers['camera'] and cur != full and contains(cur, tb, CAM['safe_margin'] * cur[2] / W)
        budget = P['move'] + P['pre_click'] + (P['lead_in'] if k == 0 else 0.0)
        if held:   # the target is already in shot with headroom: keep the shot
            shot = cur
        elif at_edge or not layers['camera']:
            shot = None
        else:
            ink = Ink(capture_at(ck['t']), W, H, CAM['word_gap'])
            shot = focus_rect(ink, stp['block'] or pad_block(tb), tb, W, H, cfg, pw, zr_shot, origin=cur, budget=budget,
                              exit_budget=1.0 if stp['navigates'] else None)[0]
        stp['click_held'], stp['click_shot'] = held, shot
        cur = shot or full
        stp['type_rect'] = stp['land_rect'] = None
        if typ and layers['camera']:
            res_box = st.get('modal') or st.get('box') or typ.get('modal') or typ['box']
            ink_r = Ink(capture_at(st['t']), W, H, CAM['word_gap'], st.get('modal'))
            r = focus_rect(ink_r, res_box, typ['box'], W, H, cfg, pw, zr_shot, origin=cur, budget=P['open_modal'] + 0.35)[0]
            stp['type_rect'] = r
            cur = r or cur
        if stp['navigates']:
            cur = full   # eases out to 1.0x before the cut
            nxt = steps[k + 1] if k + 1 < len(steps) else None
            if layers['camera']:
                ink_l = Ink(capture_at(st['t']), W, H, CAM['word_gap'])
                lpw = max(pw, pill_width(nxt['caption'], cfg, a.font)) if nxt else pw
                if nxt:
                    nb = nxt['ck'].get('block') or pad_block(nxt['ck']['box'])
                    r = focus_rect(ink_l, nb, nxt['ck']['box'], W, H, cfg, lpw, zr_land, origin=full, budget=1.0)[0]
                else:
                    r = focus_rect(ink_l, None, None, W, H, cfg, lpw, zr_land, prefer=ink_l.centroid(), origin=full, budget=1.0)[0]
                stp['land_rect'] = r
                cur = r or full

    # ---- segments (source spans with output durations) -----------------------------------------
    segments, forbidden = [], []

    def seg(src0, src1, dur, step, kind):
        segments.append({'src0': src0, 'src1': src1, 'dur': dur, 'step': step, 'kind': kind})

    seg(start_t, steps[0]['mv']['t'], P['lead_in'], steps[0]['id'], 'lead')
    for k, stp in enumerate(steps):
        s, mv, ck, st, typ = stp['id'], stp['mv'], stp['ck'], stp['st'], stp['typ']
        seg(mv['t'], mv['t1'], P['move'], s, 'move')
        seg(mv['t1'], ck['t'], P['pre_click'], s, 'pre-click')
        if typ:
            typed = first(s, 'typed')
            seg(ck['t'], typ['t'], P['open_modal'], s, 'open')
            keys = [e['t'] for e in by[s] if e['name'] == 'key'] or [typ['t']]
            bounds = [typ['t']] + keys[1:] + [typed['t']]
            for k0, k1 in zip(bounds, bounds[1:]):
                seg(k0, k1, 1 / P['type_cps'], s, 'type')
            seg(typed['t'], st['t'], P['typed_to_settle'], s, 'results')
        elif stp['navigates']:
            press = ck['t'] + 0.05
            seg(ck['t'], press, P['nav_press'], s, 'press')
            r = stp['click_shot']
            out_d = move_duration(r, full, 0.0, W, MOT) if r else 0.0
            seg(press, press, out_d + P['cam_clear'], s, 'exit')   # frozen page while the camera eases out
            stp['exit_ease'] = out_d
            forbidden.append((press + 1e-3, st['t']))
        else:
            seg(ck['t'], st['t'], P['typed_to_settle'], s, 'settle')
        nxt_mv = steps[k + 1]['mv']['t'] if k + 1 < len(steps) else None
        lr = stp.get('land_rect')
        in_d = move_duration(full, lr, 0.0, W, MOT) if lr else 0.0
        stp['land_ease'] = in_d
        base = P['end_hold'] if nxt_mv is None else P['hold']
        # a landed page holds long enough to read its outcome caption once the push-in ends
        dur = max(base, P['after_cut'] + in_d + 1.0) if stp['navigates'] else base
        if nxt_mv is None:
            dur = (P['after_cut'] + in_d if stp['navigates'] else 0.0) + P['end_hold']
        seg(st['t'], nxt_mv if nxt_mv else min(st['t'] + 1.5, end_t), dur, s, 'hold')
    for e in ev:
        if e['name'] == 'loading':
            forbidden.append((e['t'] - 0.2, e['t1'] + 0.2))
    for a0, a1 in forbidden:
        kept = []
        for sg in segments:
            if sg['src1'] <= a0 or sg['src0'] >= a1 or sg['src0'] == sg['src1']:
                kept.append(sg)
                continue
            parts = [(p, q) for p, q in [(sg['src0'], min(a0, sg['src1'])), (max(a1, sg['src0']), sg['src1'])] if q - p > 1e-3]
            span = sum(q - p for p, q in parts)
            kept += [{**sg, 'src0': p, 'src1': q, 'dur': sg['dur'] * (q - p) / span} for p, q in parts]
        segments[:] = kept

    def seg_idx(s, kind):
        return [j for j, sg in enumerate(segments) if sg['step'] == s and sg['kind'] == kind]

    def retime():
        o = P['title'] if layers['title'] else 0.0
        for j, sg in enumerate(segments):
            sg['out0'] = round(o, 4)
            o += sg['dur']
            sg['out1'] = round(o, 4)
            jump = j > 0 and abs(sg['src0'] - segments[j - 1]['src1']) > 1e-3
            sg['transition_in'] = {'type': 'cut'} if jump else None
        if layers['title']:
            segments[0]['transition_in'] = {'type': 'dip', 'duration': P['title_dip'], 'from': 'title'}
        return o

    def step_start(k):
        return segments[0]['out0'] if k == 0 else segments[seg_idx(steps[k]['id'], 'move')[0]]['out0']

    def hold_seg(k):
        return segments[seg_idx(steps[k]['id'], 'hold')[0]]

    def caption_spans(total):
        caps = []
        for k, stp in enumerate(steps):
            nxt = step_start(k + 1) if k + 1 < len(steps) else total
            hs = hold_seg(k)
            end = hs['out0'] if stp['navigates'] else nxt
            caps.append({'step': stp['id'], 'kind': 'step', 'badge': str(k + 1), 'text': stp['caption'],
                         'span': [round(step_start(k), 4), round(end, 4)]})
            if stp['navigates'] and stp['outcome']:
                after = P['after_cut'] + stp['land_ease']
                caps.append({'step': stp['id'], 'kind': 'outcome', 'badge': 'check', 'text': stp['outcome'],
                             'span': [round(hs['out0'] + after, 4), round(nxt, 4)], 'hold_through_end': k + 1 == len(steps)})
        return caps

    # ---- narration: schedule clips, stretch cursor travel or holds until they fit -----------------
    clips = {}
    if a.audio_dir and layers['narration']:
        for stp in steps:
            for kind, name in (('step', stp['id']), ('outcome', f"{stp['id']}.outcome"), ('results', f"{stp['id']}.results")):
                c = load_clip(a.audio_dir, name)
                if c:
                    clips[(stp['id'], kind)] = c
    audio = []
    total = retime()
    captions = caption_spans(total)
    for _ in range(40):
        total = retime()
        captions = caption_spans(total)
        audio, prev_end = [], None
        for ci, c in enumerate(captions):
            lines = [(c['kind'], c['span'][0] + NAR['caption_lead'])]
            if c['kind'] == 'step':
                rs = seg_idx(c['step'], 'results')
                if rs:
                    lines.append(('results', segments[rs[0]]['out0']))
            for kind, earliest in lines:
                clip = clips.get((c['step'], kind))
                if not clip:
                    continue
                f, trim, d = clip
                t0 = earliest if prev_end is None else max(earliest, prev_end + NAR['gap'])
                audio.append({'caption': ci, 'step': c['step'], 'kind': kind, 'file': f, 'trim': trim,
                              'start': round(t0, 4), 'duration': d, 'end': round(t0 + d, 4)})
                prev_end = t0 + d
        stretched = False
        for k, stp in enumerate(steps):
            mine = [x for x in audio if x['step'] == stp['id']]
            if not mine:
                continue
            own = [x for x in mine if x['kind'] != 'outcome']
            if stp['navigates'] and own:
                need = max(x['end'] for x in own) - (hold_seg(k)['out0'] - NAR['pad'])
                if need > 1e-3:
                    segments[seg_idx(stp['id'], 'move')[0]]['dur'] += need   # slower cursor travel, never a still dwell
                    stretched = True
                    break
            limit = total - NAR['end_pad'] if k + 1 == len(steps) else step_start(k + 1) - NAR['pad']
            need = max(x['end'] for x in mine) - limit
            if need > 1e-3:
                hold_seg(k)['dur'] += need
                stretched = True
                break
        if not stretched:
            break
    for x in audio:
        if x is next(y for y in audio if y['caption'] == x['caption']):
            c = captions[x['caption']]
            c['span'][0] = round(min(max(c['span'][0], x['start'] - NAR['caption_lead']), c['span'][1]), 4)
    segments[:] = [sg for sg in segments if sg['dur'] > 1e-6]
    total = retime()

    def out_of(t, kind=None, step=None):
        for sg in segments:
            if (kind is None or (sg['kind'] == kind and sg['step'] == step)) and sg['src0'] <= t <= sg['src1']:
                return sg['out0'] + (sg['out1'] - sg['out0']) * (t - sg['src0']) / max(sg['src1'] - sg['src0'], 1e-9)
        raise ValueError(t)

    def src_of(t_out):
        sg = next((s for s in segments if t_out < s['out1']), segments[-1])
        u = min(max((t_out - sg['out0']) / max(sg['out1'] - sg['out0'], 1e-9), 0.0), 1.0)
        return sg['src0'] + (sg['src1'] - sg['src0']) * u

    cuts = [sg['out0'] for sg in segments[1:] if sg['transition_in'] and sg['transition_in']['type'] == 'cut']
    nav_cuts = [hold_seg(k)['out0'] for k, stp in enumerate(steps) if stp['navigates']]

    # ---- camera keyframes -------------------------------------------------------------------------
    still = MOT['min_still_between_moves']
    plan = []   # (t_start, rect): move to rect starting at t_start; full rect is the default
    for k, stp in enumerate(steps):
        t_move = step_start(k) if k else segments[0]['out0']
        if stp['click_shot'] and not stp['click_held']:
            plan.append((t_move, stp['click_shot'], 'click'))
        if stp.get('type_rect'):
            plan.append((segments[seg_idx(stp['id'], 'open')[0]]['out0'], stp['type_rect'], 'type'))
        if stp['navigates']:
            ex = seg_idx(stp['id'], 'exit')
            if ex and stp['click_shot']:
                plan.append((segments[ex[0]]['out0'], full, 'exit'))
            if stp.get('land_rect'):
                plan.append((hold_seg(k)['out0'] + P['after_cut'], stp['land_rect'], 'land'))
    cam = [{'t': 0.0, 'rect': full}]
    cur, t_free = full, 0.0
    for t0, rect, kind in plan:
        if rect == cur:
            continue
        d = move_duration(cur, rect, 0.0, W, MOT)
        t0 = max(t0, t_free + (still if t_free > 0 else 0.0))
        cam += [{'t': round(t0, 4), 'rect': cur}, {'t': round(t0 + d, 4), 'rect': rect}]
        cur, t_free = rect, t0 + d
    # a still stretch longer than the QC limit gets a slow push-in toward a tighter gutter-snapped shot
    still_max = cfg['qc']['still_max']
    keys = sorted(cam, key=lambda c: c['t'])
    moves_t = [(p['t'], q['t'], q['rect']) for p, q in zip(keys, keys[1:]) if p['rect'] != q['rect']]
    gaps, prev_end, prev_rect = [], 0.0, full
    for m0, m1, r in moves_t + [(total, total, None)]:
        gaps.append((prev_end, m0, prev_rect))
        prev_end, prev_rect = m1, r if r else prev_rect
    for g0, g1, r in gaps:
        if g0 < segments[0]['out0'] - 1e-6:
            g0 = segments[0]['out0']
        bounds = [g0] + [c for c in cuts if g0 < c < g1] + [g1]
        for a0, a1 in zip(bounds, bounds[1:]):
            if a1 - a0 <= still_max - 0.1 or not layers['camera'] or any(abs(a1 - c) < 1e-3 for c in nav_cuts):
                continue   # short enough, no camera, or it ends at a navigation cut, which is taken at 1.0x
            ink = Ink(capture_at(src_of((a0 + a1) / 2)), W, H, CAM['word_gap'])
            z = W / r[2]
            center = (r[0] + r[2] / 2, r[1] + r[3] / 2)
            pw = max([pill_width(c['text'], cfg, a.font) for c in captions if c['span'][0] < a1 and c['span'][1] > a0] or [0])
            tgt = None
            for zz in (z * CAM['drift'], z / CAM['drift']):
                zz = min(max(zz, 1.0), CAM['zmax'])
                if abs(zz - z) < 0.02:
                    continue
                cand, _, _ = focus_rect(ink, None, None, W, H, cfg, pw, (zz - 0.02, zz + 0.02), prefer=center)
                if cand and abs(W / cand[2] - z) >= 0.02:
                    tgt = cand
                    break
            if not tgt:
                continue
            t_s, t_e = a0 + still, a1 - still
            if t_e - t_s < MOT['min_move_duration'] or t_e - t_s < move_duration(r, tgt, 0.0, W, MOT):
                continue
            # the next move now starts from the drifted rect: it must still fit its time inside the limits
            nxt = next(((m0, m1, r1) for m0, m1, r1 in moves_t if m0 >= a1 - 1e-6), None)
            if nxt and move_duration(tgt, nxt[2], 0.0, W, MOT) > nxt[1] - nxt[0] + 1e-3:
                continue
            cam += [{'t': round(t_s, 4), 'rect': r}, {'t': round(t_e, 4), 'rect': tgt}]
            for c in cam:   # the hold until the next move starts is at the drifted rect
                if t_e + 1e-6 < c['t'] <= (nxt[0] if nxt else total) + 1e-6 and c['rect'] == r:
                    c['rect'] = tgt
    cam.sort(key=lambda c: c['t'])

    def rect_at(t):
        for p, q in zip(cam, cam[1:]):
            if p['t'] <= t <= q['t']:
                u = 0 if q['t'] == p['t'] else smooth((t - p['t']) / (q['t'] - p['t']))
                return [p['rect'][j] + (q['rect'][j] - p['rect'][j]) * u for j in range(4)]
        return cam[-1]['rect']

    # ---- cursor ---------------------------------------------------------------------------------
    last_nav = steps[-1]['navigates']
    hidden_from = hold_seg(len(steps) - 1)['out0'] if last_nav else None

    def cursor_at(st):
        pos = (moves[0]['from']['x'], moves[0]['from']['y'])
        for m in moves:
            if st < m['t']:
                break
            if st <= m['t1']:
                u = (st - m['t']) / max(m['t1'] - m['t'], 1e-9)
                u = 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2
                return (m['from']['x'] + (m['to']['x'] - m['from']['x']) * u, m['from']['y'] + (m['to']['y'] - m['from']['y']) * u)
            pos = (m['to']['x'], m['to']['y'])
        return pos

    # ---- caption placement: the primary anchor, else the one fixed fallback, on empty page --------
    for c in captions:
        w = pill_width(c['text'], cfg, a.font)
        stp = next(s for s in steps if s['id'] == c['step'])
        occ = {name: 0.0 for name in CAP['anchors']}
        t = c['span'][0]
        while t <= c['span'][1]:
            r = rect_at(t)
            z = W / r[2]
            s_t = src_of(t)
            modal = stp['st'].get('modal') if stp['typ'] and s_t >= stp['typ']['t'] else None
            ink = Ink(capture_at(s_t), W, H, CAM['word_gap'], modal)
            for name in CAP['anchors']:
                ax, ay, aw, ah = anchor_box(name, w, W, H, cfg)
                k_ = CAP['clear']
                x0, y0 = r[0] + (ax - k_) / z, r[1] + (ay - k_) / z
                x1, y1 = r[0] + (ax + aw + k_) / z, r[1] + (ay + ah + k_) / z
                hit = ink.count(x0, y0, x1, y1)
                if c['kind'] == 'step':
                    tb = stp['target_box']
                    if not (tb[0] + tb[2] < x0 or tb[0] > x1 or tb[1] + tb[3] < y0 or tb[1] > y1):
                        hit += 1e3
                if hidden_from is None or t < hidden_from:
                    cx, cy = cursor_at(s_t)
                    if x0 - 20 <= cx <= x1 + 4 and y0 - 30 <= cy <= y1 + 4:
                        hit += 1e3
                occ[name] = max(occ[name], hit)
            t += 0.1
        name = next((n for n in CAP['anchors'] if occ[n] <= CAM['edge_ink']), min(occ, key=occ.get))
        c['slot'], c['box'], c['anchor_occupancy'] = name, list(anchor_box(name, w, W, H, cfg)), {k: round(v, 1) for k, v in occ.items()}
        if layers['captions'] and occ[name] > CAM['edge_ink']:
            errs.append(f"caption {c['text']!r} has no empty anchor ({c['anchor_occupancy']})")

    # ---- rules ----------------------------------------------------------------------------------
    for sg in segments:
        for a0, a1 in forbidden:
            if sg['src1'] > sg['src0'] and sg['src0'] < a1 - 1e-6 and sg['src1'] > a0 + 1e-6:
                errs.append(f"{sg['kind']}/{sg['step']} shows source inside a navigation or loading window")
    cmoves = [(p['t'], q['t'], p['rect'], q['rect']) for p, q in zip(cam, cam[1:]) if p['rect'] != q['rect']]
    for m0, m1, r0, r1 in cmoves:
        if m1 - m0 < move_duration(r0, r1, 0.0, W, MOT) / 1.02 - 1e-3:
            errs.append(f'camera move {m0:.2f}-{m1:.2f}s is faster than the motion limits allow')
    for (_, a1, _, _), (b0, _, _, _) in zip(cmoves, cmoves[1:]):
        if b0 - a1 < still - 1e-3:
            errs.append(f'camera rests only {b0 - a1:.2f}s between moves at {a1:.2f}s (min {still})')
    for c in cuts:
        for m0, m1, _, _ in cmoves:
            if m0 < c - 1e-6 and m1 > c - P['cam_clear'] + 1e-3:
                errs.append(f'cut at {c:.2f}s while the camera moves')
    for c in nav_cuts:
        r = rect_at(c - 1e-3)
        if layers['camera'] and abs(W / r[2] - 1.0) > 1e-3:
            errs.append(f'navigation cut at {c:.2f}s taken at {W / r[2]:.2f}x, not 1.0x')
    for stp in steps:
        for key in ('click_shot', 'type_rect', 'land_rect'):
            r = stp.get(key)
            if r:
                ink = Ink(capture_at(stp['st']['t'] if key == 'land_rect' else stp['ck']['t']), W, H, CAM['word_gap'],
                          stp['st'].get('modal') if key == 'type_rect' else None)
                bad = {e: v for e, v in edge_ink(ink, r, CAM['gutter_band'], W, H).items() if v > CAM['edge_ink']}
                if bad:
                    errs.append(f"{stp['id']} {key} cuts content at {bad}")
    for stp in steps:
        print(f"  step {stp['id']}: click {stp['click_shot']}{' (held)' if stp['click_held'] else ''} type {stp.get('type_rect')} land {stp.get('land_rect')} "
              f"navigates={stp['navigates']}")
    for c in captions:
        print(f"  caption {c['kind']} {c['step']} {c['span']}: {c['slot']} {c['anchor_occupancy']}")

    edl = {
        'version': 1,
        'capture': str(cap),
        'width': W, 'height': H, 'fps': 30, 'dsf': dsf,
        'total': round(total, 4),
        'style': a.style,
        'layers': layers,
        'config': cfg,
        'forbidden_source': [[round(x, 4), round(y, 4)] for x, y in forbidden],
        # while a modal is open only the modal is content; its dimmed backdrop is not
        'content_masks': [{'src0': s['typ']['t'], 'src1': steps[k + 1]['ck']['t'] + 0.05 if k + 1 < len(steps) else end_t,
                           'box': s['st']['modal']} for k, s in enumerate(steps) if s['typ'] and s['st'].get('modal')],
        'title': {'text': script.get('title', ''), 'subtitle': script.get('subtitle', ''), 'duration': P['title'] if layers['title'] else 0.0},
        'caption_style': {'height': CAP['pill_h'], 'fade': CAP['fade'], 'font_size': CAP['font_size'], 'font': a.font,
                          'background': [17, 20, 28], 'text': [255, 255, 255], 'margin': CAP['margin']},
        'encode': {'codec': 'libx264', 'profile': 'high', 'preset': 'slower', 'crf': 16, 'pix_fmt': 'yuv420p'},
        'segments': [{k: v for k, v in sg.items() if k != 'dur'} for sg in segments],
        'cuts': [round(c, 4) for c in cuts],
        'nav_cuts': [round(c, 4) for c in nav_cuts],
        'camera': cam,
        'cursor': {
            'start': moves[0]['from'],
            'moves': [{k: e[k] for k in ('t', 't1', 'from', 'to')} for e in moves],
            'clicks': [{'t': e['t'], 'x': e['x'], 'y': e['y'], 'box': e['box']} for e in ev if e['name'] == 'click'],
            'hidden_from': hidden_from,
        },
        'captions': captions,
        'audio': audio,
        'steps': [{'id': s['id'], 'caption': s['caption'], 'outcome': s['outcome'], 'navigates': s['navigates'],
                   'target_box': s['target_box'], 'click_t': s['ck']['t'], 'click_out': round(out_of(s['ck']['t']), 4)}
                  for s in steps],
    }
    if errs:   # kept beside the output for diagnosis, under a name produce.py is never pointed at
        rejected = Path(a.out).with_suffix('.rejected.json')
        rejected.write_text(json.dumps(edl, indent=1))
        print('EDL breaks rules (plan kept at ' + str(rejected) + '):\n  ' + '\n  '.join(errs))
        return 1
    Path(a.out).write_text(json.dumps(edl, indent=1))
    print(f'edl: {len(steps)} steps, {len(segments)} segments, {len(cam)} camera keys, {total:.2f}s -> {a.out}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
