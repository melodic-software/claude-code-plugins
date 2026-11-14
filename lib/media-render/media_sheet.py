"""Contact sheets: the source frames tiled at native resolution, never downscaled. Standard library and
media_encode only.

sheets(pngs, out_dir, columns=2, max_bytes=10 * 10**6) -> [{'path', 'bytes', 'frames'}]: as few sheets as keep
each under max_bytes (GitHub's image limit); a single frame over it raises SheetError.
"""
import math
from pathlib import Path

import media_encode


class SheetError(RuntimeError):
    pass


def _tile(pngs, out, columns):
    rows = math.ceil(len(pngs) / columns)
    work = Path(out).parent
    listing = work / f'{Path(out).stem}.ffconcat'
    listing.write_text('ffconcat version 1.0\n' + ''.join(media_encode.concat_file(Path(p).resolve()) + '\n' for p in pngs),
                       encoding='utf-8')
    try:
        media_encode.run(['-f', 'concat', '-safe', '0', '-i', listing, '-vf', f'tile={columns}x{rows}:padding=16',
                          '-frames:v', '1', '-update', '1', out])
    finally:
        listing.unlink(missing_ok=True)
    return Path(out).stat().st_size


def sheets(pngs, out_dir, columns=2, max_bytes=10 * 10 ** 6):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    per = len(pngs)
    while True:
        groups = [pngs[i:i + per] for i in range(0, len(pngs), per)]
        made = []
        for k, group in enumerate(groups, 1):
            path = out_dir / f'contact-sheet-{k:02d}.png'
            made.append({'path': str(path), 'bytes': _tile(group, path, columns), 'frames': len(group)})
        if all(m['bytes'] <= max_bytes for m in made):
            return made
        for m in made:
            Path(m['path']).unlink(missing_ok=True)
        if per == 1:
            raise SheetError('one frame alone is over the image size limit')
        per = math.ceil(per / 2)
