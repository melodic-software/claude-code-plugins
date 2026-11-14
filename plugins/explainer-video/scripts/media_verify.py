# GENERATED from lib/media-render/media_verify.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""Checks on an encoded file: streams, duration, blank frames and luma SSIM against the source frame.
Standard library and media_encode only.

probe(path) -> ffprobe JSON (streams: codec, type, size, pix_fmt, duration; format duration).
stream_defects(probe, expected) -> missing or extra streams and a duration off the timeline by over a frame.
frame_at(video, t, out) writes the frame shown at t.
luma_ssim(source_png, frame_png) -> Y-plane SSIM in yuv444p (4:2:0 chroma on colored text is not legibility).
blank(png) -> True when the frame's gray levels span under BLANK_RANGE.
"""
import json
import re

import media_encode

BLANK_RANGE = 8


def probe(path):
    return json.loads(media_encode.probe(
        ['-show_entries', 'format=duration:stream=codec_type,codec_name,pix_fmt,width,height,duration', '-of', 'json',
         path]))


def stream_defects(info, expected_s, fps, audio, subtitle):
    """One video stream, an audio stream only when audio, a subtitle stream only when subtitle; the file within one
    frame of expected_s."""
    streams = info.get('streams', [])
    out = []
    for kind, want in (('video', 1), ('audio', int(audio)), ('subtitle', int(subtitle))):
        n = sum(s.get('codec_type') == kind for s in streams)
        if n != want:
            out.append(f'expected {want} {kind} stream(s), ffprobe found {n}')
    try:
        duration = float(info['format']['duration'])
    except (KeyError, TypeError, ValueError):
        return out + ['ffprobe reports no duration']
    if abs(duration - expected_s) > 1 / fps + 0.05:
        out.append(f'duration {duration:.3f} s differs from the timeline {expected_s:.3f} s')
    return out


def frame_at(video, t, out):
    media_encode.run(['-ss', f'{t:.3f}', '-i', video, '-frames:v', '1', out])


def luma_ssim(source_png, frame_png, top=1.0):
    """top: the share of the height compared, from the top (leaves out a burned-caption band)."""
    crop = f'crop=iw:trunc(ih*{top}/2)*2:0:0,' if top < 1.0 else ''
    r = media_encode.run(['-i', frame_png, '-i', source_png,
                          '-lavfi', f'[0:v]{crop}format=yuv444p[a];[1:v]{crop}format=yuv444p[b];[a][b]ssim',
                          '-f', 'null', '-'], report=True)
    m = re.search(r'SSIM Y:([\d.]+)', r.stderr)
    if not m:
        raise media_encode.EncodeError('ffmpeg ssim printed no Y value')
    return float(m.group(1))


def blank(png):
    gray = media_encode.run(['-i', png, '-vf', 'scale=64:36,format=gray', '-f', 'rawvideo', '-'], text=False).stdout
    return not gray or max(gray) - min(gray) < BLANK_RANGE
