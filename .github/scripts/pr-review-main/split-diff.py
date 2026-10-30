"""Split the main-run review's patch into chunks one review reads whole.

usage: split-diff.py <patch> <out-dir> <max-bytes> <max-chunks>

Writes <out-dir>/chunk-<k>.patch, k from 1, each at most max-bytes, the
patch's bytes in order and nothing else. A chunk ends at a file boundary
(a `diff --git` line). A file over max-bytes splits at its hunks (`@@` lines),
each piece led by the file's own header lines, so every chunk reads as a
patch. A hunk that does not fit one chunk beside its header, or a patch that
needs more than max-chunks chunks, is too large: nothing is written and the
exit status is 3. An empty patch writes no chunk.
"""

import sys
from pathlib import Path

TOO_LARGE = 3


class TooLarge(Exception):
    pass


def lines_of(data: bytes) -> list[bytes]:
    """Each line with its newline; a content line always starts with a
    prefix byte, so a line that starts `diff --git ` or `@@ ` is git's."""
    lines = [line + b"\n" for line in data.split(b"\n")]
    lines[-1] = lines[-1][:-1]
    return [line for line in lines if line]


def pieces(lines: list[bytes], max_bytes: int) -> list[bytes]:
    """The file patch whole, or split at its hunks under its header."""
    whole = b"".join(lines)
    if len(whole) <= max_bytes:
        return [whole]
    start = next((i for i, line in enumerate(lines) if line.startswith(b"@@ ")), None)
    if start is None:
        raise TooLarge("a file with no hunk is larger than one chunk")
    header = b"".join(lines[:start])
    hunks: list[bytes] = []
    for line in lines[start:]:
        if line.startswith(b"@@ "):
            hunks.append(b"")
        hunks[-1] += line
    found = [header]
    for hunk in hunks:
        if len(header) + len(hunk) > max_bytes:
            raise TooLarge("a hunk with its file's header is larger than one chunk")
        if found[-1] != header and len(found[-1]) + len(hunk) > max_bytes:
            found.append(header)
        found[-1] += hunk
    return found


def split(data: bytes, max_bytes: int, max_chunks: int) -> list[bytes]:
    files: list[list[bytes]] = []
    for line in lines_of(data):
        if not files or line.startswith(b"diff --git "):
            files.append([])
        files[-1].append(line)
    chunks: list[bytes] = []
    for unit in (piece for lines in files for piece in pieces(lines, max_bytes)):
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
