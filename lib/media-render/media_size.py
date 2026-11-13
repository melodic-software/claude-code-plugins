"""The upload limit, checked and never met by recompressing or cutting (ADR 0106). Standard library and
media_encode only.

limit_bytes(mb) -> mb * 10**6, the smaller reading of a "MB" limit.
plan_split(starts, duration_s, size_bytes, limit) -> [(start_s, end_s)] at chapter starts, each part estimated
  under the limit at the file's own bitrate; SizeError when one chapter alone is estimated over it.
split(video, starts, duration_s, out_dir, limit) -> part files, stream-copied (chapter starts are keyframes); a part that is
  still over the limit is split again at its own chapter starts, and SizeError when it holds one chapter.
"""
from pathlib import Path

import media_encode

HEADROOM = 0.9


class SizeError(RuntimeError):
    pass


def limit_bytes(mb):
    return int(mb * 10 ** 6)


def plan_split(starts, duration_s, size_bytes, limit):
    """starts: chapter start times in seconds, the first 0."""
    rate = size_bytes / duration_s
    bounds = list(starts) + [duration_s]
    parts, a = [], bounds[0]
    for i in range(1, len(bounds)):
        if (bounds[i] - bounds[i - 1]) * rate > limit:
            raise SizeError(f'the chapter at {bounds[i - 1]:.1f} s alone is over the upload limit')
        if (bounds[i] - a) * rate > limit * HEADROOM and bounds[i - 1] > a:
            parts.append((a, bounds[i - 1]))
            a = bounds[i - 1]
    parts.append((a, duration_s))
    return parts


def _cut(video, a, b, out):
    media_encode.run(['-ss', f'{a:.3f}', '-i', video, '-t', f'{b - a:.3f}', '-map', '0', '-c', 'copy',
                      '-avoid_negative_ts', 'make_zero', out])


def split(video, starts, duration_s, out_dir, limit):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    pending = plan_split(starts, duration_s, Path(video).stat().st_size, limit)
    done = []
    while pending:
        a, b = pending.pop(0)
        path = out_dir / f'part-{len(done) + 1:02d}.mp4'
        _cut(video, a, b, path)
        if path.stat().st_size <= limit:
            done.append({'path': str(path), 'start_s': a, 'end_s': b, 'bytes': path.stat().st_size})
            continue
        inner = [s for s in starts if a < s < b]
        if not inner:
            path.unlink()
            raise SizeError(f'the chapter at {a:.1f} s alone is over the upload limit')
        mid = inner[len(inner) // 2]
        pending[:0] = [(a, mid), (mid, b)]
        path.unlink()
    return done
