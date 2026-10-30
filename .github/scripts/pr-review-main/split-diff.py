"""Split the main-run review's patch into chunks one review reads whole.

usage: split-diff.py <patch> <out-dir> <max-bytes> <max-chunks>

Writes <out-dir>/chunk-<k>.patch, k from 1, each at most max-bytes, the
patch's bytes in order and nothing else. A chunk ends at a file boundary (a
`diff --git` line), and a file is never split: a file over max-bytes, or a
patch that needs more than max-chunks chunks, is too large: nothing is
written and the exit status is 3. An empty patch writes no chunk.
"""

import sys
from pathlib import Path

TOO_LARGE = 3


class TooLarge(Exception):
    pass


def lines_of(data: bytes) -> list[bytes]:
    """Each line with its newline; a content line always starts with a
    prefix byte, so a line that starts `diff --git ` is git's."""
    lines = [line + b"\n" for line in data.split(b"\n")]
    lines[-1] = lines[-1][:-1]
    return [line for line in lines if line]


def split(data: bytes, max_bytes: int, max_chunks: int) -> list[bytes]:
    files: list[list[bytes]] = []
    for line in lines_of(data):
        if not files or line.startswith(b"diff --git "):
            files.append([])
        files[-1].append(line)
    chunks: list[bytes] = []
    for unit in (b"".join(lines) for lines in files):
        if len(unit) > max_bytes:
            raise TooLarge("a file is larger than one chunk")
        if not chunks or len(chunks[-1]) + len(unit) > max_bytes:
            chunks.append(b"")
        chunks[-1] += unit
    if len(chunks) > max_chunks:
        raise TooLarge(f"the diff needs {len(chunks)} chunks, more than {max_chunks}")
    return chunks


if __name__ == "__main__":
    patch, out, max_bytes, max_chunks = sys.argv[1:5]
    try:
        chunks = split(Path(patch).read_bytes(), int(max_bytes), int(max_chunks))
    except TooLarge as error:
        print(f"split-diff: {error}", file=sys.stderr)
        sys.exit(TOO_LARGE)
    for k, chunk in enumerate(chunks, 1):
        (Path(out) / f"chunk-{k}.patch").write_bytes(chunk)
