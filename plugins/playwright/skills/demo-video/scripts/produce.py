"""Stage 3 of the demo-video pipeline: render edl.json (plus the capture frames it points at) to an
H.264 MP4. Every editing decision lives in the EDL; this file draws it.

Layers (edl["layers"], each switchable with --off NAME[,NAME]):
  title     title card, dipping through ink to the first page frame (the only blend)
  camera    zoom/pan keyframes (off: full frame throughout)
  cursor    drawn pointer          ripple   click ring
  captions  step and outcome pills  narration  the EDL's scheduled clips

usage: produce.py EDL.json OUT.mp4 [--off LAYERS] [--jobs N]
Writes OUT.render.json beside the video: per frame, the capture shown and the overlays drawn. qc.py
uses it only to know which capture a frame samples; it measures everything else from the frames.
"""
import argparse
import bisect
import json
import os
import subprocess
from functools import lru_cache
from multiprocessing import Pool
from pathlib import Path

from PIL import Image, ImageDraw

from demo_common import font, smooth

ACCENT = (45, 140, 255)
OK_GREEN = (36, 163, 92)
INK = (17, 20, 28)
RIPPLE = 0.3   # seconds


def ease_cubic(u):   # the curve record.mjs moves the real mouse with
    u = min(max(u, 0.0), 1.0)
    return 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2


class Renderer:
    def __init__(self, edl, off):
        self.e = edl
        self.W, self.H, self.fps = edl['width'], edl['height'], edl['fps']
        self.dsf = edl.get('dsf', 1)
        self.layers = {k: v and k not in off for k, v in edl['layers'].items()}
        cap = Path(edl['capture'])
        tl = json.loads((cap / 'timeline.json').read_text())
        self.frames = [(f['t'], str(cap / f['file'])) for f in tl['frames']]
        self.digests = [f.get('digest', f['file']) for f in tl['frames']]
        self.ftimes = [t for t, _ in self.frames]
        self.segs = edl['segments']
        self.forbidden = edl.get('forbidden_source', [])
        self.cam = edl['camera']
        self.cur = edl['cursor']
        self.click_out = [self.out_of(c['t']) for c in self.cur['clicks']]
        cs = edl['caption_style']
        self.f_cap = font(cs['font_size'], cs.get('font'))
        self.f_badge = font(23, cs.get('font'))
        self.f_title = font(80, cs.get('font'))
        self.f_sub = font(38, cs.get('font'))
        self.load = lru_cache(maxsize=6)(self._load)
        self.view = lru_cache(maxsize=12)(self._view)
        self.cap_layers = {}

    def out_of(self, st):
        for s in self.segs:
            if s['src0'] <= st <= s['src1'] and s['src1'] > s['src0']:
                return s['out0'] + (s['out1'] - s['out0']) * (st - s['src0']) / (s['src1'] - s['src0'])
        return None

    def seg_index(self, ot):
        for k, s in enumerate(self.segs):
            if ot < s['out1']:
                return k
        return len(self.segs) - 1

    def src_in(self, k, ot):
        s = self.segs[k]
        u = min(max((ot - s['out0']) / max(s['out1'] - s['out0'], 1e-9), 0.0), 1.0)
        return s['src0'] + (s['src1'] - s['src0']) * u

    def sources(self, ot):
        """[(source, weight)]: 'title', 'ink' (flat colour) or a source time. Cuts between page
        states are hard; the only blends are the title dipping to ink and ink fading up."""
        B = self.segs[0]['out0']
        tr = self.segs[0]['transition_in'] or {}
        d = tr.get('duration', 0.0) if tr.get('from') == 'title' else 0.0
        if d and ot < B - d:
            return [('title', 1.0)]
        if d and ot < B - d / 2:
            w = smooth((ot - (B - d)) / (d / 2))
            return [('title', 1 - w), ('ink', w)]
        if d and ot < B:
            w = smooth((ot - (B - d / 2)) / (d / 2))
            return [('ink', 1 - w), (self.src_in(0, B), w)]
        if ot < B:
            return [('title', 1.0)]
        return [(self.src_in(self.seg_index(ot), ot), 1.0)]

    def rect_at(self, ot):
        if not self.layers.get('camera'):
            return (0.0, 0.0, float(self.W), float(self.H))
        cam = self.cam
        for p, q in zip(cam, cam[1:]):
            if p['t'] <= ot <= q['t']:
                u = 0.0 if q['t'] == p['t'] else smooth((ot - p['t']) / (q['t'] - p['t']))
                return tuple(p['rect'][j] + (q['rect'][j] - p['rect'][j]) * u for j in range(4))
        return tuple(cam[-1]['rect'])

    def capture_index(self, st):
        i = max(0, bisect.bisect_right(self.ftimes, st) - 1)
        for a0, a1 in self.forbidden:   # a capture from a navigation or loading window: the first after it
            if a0 < self.ftimes[i] < a1:
                i = min(bisect.bisect_left(self.ftimes, a1), len(self.frames) - 1)
        return i

    def cursor_at(self, st):
        pos = (self.cur['start']['x'], self.cur['start']['y'])
        for m in self.cur['moves']:
            if st < m['t']:
                break
            if st <= m['t1']:
                u = ease_cubic((st - m['t']) / max(m['t1'] - m['t'], 1e-9))
                return (m['from']['x'] + (m['to']['x'] - m['from']['x']) * u, m['from']['y'] + (m['to']['y'] - m['from']['y']) * u)
            pos = (m['to']['x'], m['to']['y'])
        return pos

    def _load(self, path):
        return Image.open(path).convert('RGB')

    def _view(self, path, rect):
        d = self.dsf
        im = self.load(path)
        box = (max(rect[0] * d, 0), max(rect[1] * d, 0), min((rect[0] + rect[2]) * d, im.width), min((rect[1] + rect[3]) * d, im.height))
        return im.resize((self.W, self.H), Image.LANCZOS, box=box)

    def title(self):
        img = Image.new('RGB', (self.W, self.H), INK)
        d = ImageDraw.Draw(img)
        t = self.e['title']
        d.text((self.W / 2, self.H / 2 - 36), t['text'], font=self.f_title, fill=(255, 255, 255), anchor='mm')
        d.text((self.W / 2, self.H / 2 + 52), t['subtitle'], font=self.f_sub, fill=(150, 200, 255), anchor='mm')
        return img

    @staticmethod
    @lru_cache(maxsize=64)
    def cursor_sprite(q):
        scale, S = q / 20.0, 4
        pts = [(0, 0), (0, 22), (5.5, 17), (9.5, 26), (13, 24.5), (9, 16), (16, 16)]
        k = scale * S
        img = Image.new('RGBA', (int(22 * k), int(32 * k)), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        off = 2 * k
        d.polygon([(off + x * k + 1.2 * k, off + y * k + 1.6 * k) for x, y in pts], fill=(0, 0, 0, 70))
        d.polygon([(off + x * k, off + y * k) for x, y in pts], fill=(255, 255, 255, 255), outline=(0, 0, 0, 255), width=max(1, int(1.5 * k)))
        return img.resize((img.width // S, img.height // S), Image.LANCZOS), off / S

    def ripple(self, img, box, age, z):
        """A rounded ring growing outward from the clicked element's box, never over its label,
        kept inside the frame. Returns its outer box in output px, or None."""
        if not (0 <= age <= RIPPLE):
            return None
        u = age / RIPPLE
        stroke = 3.0 * z
        gap = (3 + 9 * smooth(u)) * z
        room = min(box[0], box[1], self.W - box[0] - box[2], self.H - box[1] - box[3]) - stroke - 1
        gap = max(min(gap, room), 1.0)
        alpha = int(230 * (1 - u) ** 0.8)
        x0, y0, x1, y1 = box[0] - gap, box[1] - gap, box[0] + box[2] + gap, box[1] + box[3] + gap
        ox0, oy0 = max(x0 - stroke, 1), max(y0 - stroke, 1)
        ox1, oy1 = min(x1 + stroke, self.W - 1), min(y1 + stroke, self.H - 1)
        S = 3
        w, h = int(ox1 - ox0) + 2, int(oy1 - oy0) + 2
        if w <= 2 or h <= 2:
            return None
        layer = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        rad = (min(box[3], box[2]) / 2 + gap) * S
        rect = [(x0 - ox0 - stroke / 2) * S, (y0 - oy0 - stroke / 2) * S, (x1 - ox0 + stroke / 2) * S, (y1 - oy0 + stroke / 2) * S]
        d.rounded_rectangle(rect, radius=rad, outline=(255, 255, 255, alpha), width=int(stroke * 1.8 * S))
        d.rounded_rectangle(rect, radius=rad, outline=ACCENT + (alpha,), width=int(stroke * S))
        layer = layer.resize((w, h), Image.LANCZOS)
        img.paste(layer, (int(ox0), int(oy0)), layer)
        return [round(x0 - stroke, 1), round(y0 - stroke, 1), round(x1 + stroke, 1), round(y1 + stroke, 1)]

    def caption_layer(self, ci):
        """Solid ink pill with a step badge (number) or outcome badge (check) and white text (~18:1)."""
        if ci in self.cap_layers:
            return self.cap_layers[ci]
        c = self.e['captions'][ci]
        _, _, w, h = c['box']
        S = 4
        layer = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle([0, 0, w * S - 1, h * S - 1], radius=h * S // 2,
                                               fill=tuple(self.e['caption_style']['background']) + (255,))
        layer = layer.resize((w, h), Image.LANCZOS)
        cy, r = h // 2, 19
        badge = Image.new('RGBA', (2 * r * S, 2 * r * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(badge)
        if c['kind'] == 'outcome':
            d.ellipse([0, 0, 2 * r * S - 1, 2 * r * S - 1], fill=OK_GREEN + (255,))
            k = r * S / 21
            d.line([(11 * k, 21.5 * k), (18 * k, 28.5 * k), (31 * k, 14 * k)], fill=(255, 255, 255, 255), width=int(4 * k), joint='curve')
        else:
            d.ellipse([0, 0, 2 * r * S - 1, 2 * r * S - 1], fill=ACCENT + (255,))
        badge = badge.resize((2 * r, 2 * r), Image.LANCZOS)
        x0 = (h - 2 * r) // 2 + 2
        layer.alpha_composite(badge, (x0, cy - r))
        d = ImageDraw.Draw(layer)
        fg = tuple(self.e['caption_style']['text']) + (255,)
        if c['kind'] != 'outcome':
            d.text((x0 + r, cy + 1), c['badge'], font=self.f_badge, fill=fg, anchor='mm')
        d.text((x0 + 2 * r + 14, cy + 1), c['text'], font=self.f_cap, fill=fg, anchor='lm')
        self.cap_layers[ci] = layer
        return layer

    def caption_alpha(self, ot, c):
        """Fade in, and fade out to exactly 0 one frame before the span end, so nothing lingers."""
        a, b = c['span']
        f = self.e['caption_style']['fade']
        k = smooth((ot - a) / f) if ot >= a else 0.0
        if not c.get('hold_through_end'):
            k = min(k, smooth((b - 1 / self.fps - ot) / f))
        return 0.0 if k < 0.02 else k

    def frame(self, fi):
        ot = fi / self.fps
        rect = self.rect_at(ot)
        rect_key = tuple(round(v, 2) for v in rect)
        srcs = self.sources(ot) if self.layers.get('title') else [(self.src_in(0, ot) if s in ('title', 'ink') else s, w) for s, w in self.sources(ot)]
        img, used = None, []
        for s, w in srcs:
            if s == 'title':
                part = self.title()
            elif s == 'ink':
                part = Image.new('RGB', (self.W, self.H), INK)
            else:
                i = self.capture_index(s)
                part = self.view(self.frames[i][1], rect_key).copy()
                used.append(round(self.frames[i][0], 4))
            img = part if img is None else Image.blend(img, part, w)
        log = {'ot': round(ot, 4), 'src': [s if isinstance(s, str) else round(s, 4) for s, _ in srcs],
               'w': [round(w, 3) for _, w in srcs], 'rect': [round(v, 2) for v in rect], 'captures': used}
        page_srcs = [s for s, _ in srcs if not isinstance(s, str)]
        title_w = sum(w for s, w in srcs if isinstance(s, str))
        z = self.W / rect[2]
        if page_srcs and title_w < 0.5:
            st = page_srcs[-1]
            if self.layers.get('ripple'):
                for c, oc in zip(self.cur['clicks'], self.click_out):
                    if oc is None or not (0 <= ot - oc <= RIPPLE):
                        continue
                    if used and self.digests[self.capture_index(c['t'])] != self.digests[self.capture_index(st)]:
                        continue   # the ripple belongs to the clicked page state
                    b = c['box']
                    drawn = self.ripple(img, ((b[0] - rect[0]) * z, (b[1] - rect[1]) * z, b[2] * z, b[3] * z), ot - oc, z)
                    if drawn:
                        log['ripple'] = drawn
            hidden = self.cur.get('hidden_from') is not None and ot >= self.cur['hidden_from']
            if self.layers.get('cursor') and not hidden:
                cx, cy = self.cursor_at(st)
                px, py = (cx - rect[0]) * z, (cy - rect[1]) * z
                press = any(oc is not None and 0 <= ot - oc <= 0.1 for oc in self.click_out)
                spr, off = self.cursor_sprite(int(round(20 * 1.3 * z * (0.85 if press else 1.0))))
                img.paste(spr, (int(round(px - off)), int(round(py - off))), spr)
                log['cursor'] = [round(px, 1), round(py, 1)]
        if self.layers.get('captions'):
            for ci, c in enumerate(self.e['captions']):
                if c['span'][0] <= ot <= c['span'][1]:
                    k = self.caption_alpha(ot, c)
                    if k <= 0:
                        continue
                    layer = self.caption_layer(ci)
                    if k < 1:
                        layer = layer.copy()
                        layer.putalpha(layer.getchannel('A').point(lambda v, k=k: int(v * k)))
                    img.paste(layer, (c['box'][0], c['box'][1]), layer)
                    log['caption'] = list(c['box'])
        return img, log


R = None


def _init(edl, off):
    global R
    R = Renderer(edl, off)


def _render(fi):
    img, log = R.frame(fi)
    return img.tobytes(), log


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('edl')
    ap.add_argument('out')
    ap.add_argument('--off', default='', help='comma-separated layers to switch off')
    ap.add_argument('--jobs', type=int, default=min(16, os.cpu_count() or 4))
    ap.add_argument('--preset', help='x264 preset in place of the EDL\'s (a faster draft encode)')
    a = ap.parse_args(argv)
    edl = json.loads(Path(a.edl).read_text())
    off = set(filter(None, a.off.split(',')))
    W, H, fps = edl['width'], edl['height'], edl['fps']
    nframes = int(round(edl['total'] * fps))
    enc = {**edl['encode'], **({'preset': a.preset} if a.preset else {})}
    out = Path(a.out)
    video_only = out.with_suffix('.video.mp4')
    vf = 'scale=out_color_matrix=bt709:out_range=tv:flags=lanczos+accurate_rnd+full_chroma_int+full_chroma_inp,format=' + enc['pix_fmt']
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}',
           '-r', str(fps), '-i', '-', '-vf', vf, '-c:v', enc['codec'], '-profile:v', enc['profile'], '-preset', enc['preset'],
           '-crf', str(enc['crf']), '-x264-params', 'colorprim=bt709:transfer=bt709:colormatrix=bt709:range=tv',
           '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
           '-movflags', '+faststart', str(video_only)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    logs = []
    with Pool(a.jobs, initializer=_init, initargs=(edl, off)) as pool:
        for buf, log in pool.imap(_render, range(nframes), chunksize=6):
            proc.stdin.write(buf)
            logs.append(log)
    proc.stdin.close()
    if proc.wait():
        raise SystemExit('ffmpeg video encode failed')
    clips = edl.get('audio', []) if edl['layers'].get('narration') and 'narration' not in off else []
    if clips:
        cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(video_only)]
        parts = []
        for i, x in enumerate(clips):
            cmd += ['-i', x['file']]
            ms = int(round(x['start'] * 1000))
            parts.append(f"[{i + 1}:a]atrim=start={x.get('trim', 0)}:duration={x['duration']},asetpts=PTS-STARTPTS,"
                         f'aresample=48000,adelay={ms}:all=1[a{i}]')
        fc = ';'.join(parts) + ';' + ''.join(f'[a{i}]' for i in range(len(clips))) + \
            f'amix=inputs={len(clips)}:normalize=0:dropout_transition=0,apad[aout]'
        cmd += ['-filter_complex', fc, '-map', '0:v', '-map', '[aout]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k',
                '-t', f'{nframes / fps:.3f}', '-movflags', '+faststart', str(out)]
        subprocess.run(cmd, check=True)
        video_only.unlink()
    else:
        video_only.replace(out)
    out.with_suffix('.render.json').write_text(json.dumps({'fps': fps, 'frames': logs}))
    print(f'{out}: {nframes} frames, {nframes / fps:.2f}s, narration clips={len(clips)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
