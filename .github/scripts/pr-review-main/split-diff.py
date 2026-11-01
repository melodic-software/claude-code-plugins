"""Split the main-run review's patch into chunks one review reads whole.

usage: split-diff.py <patch> <out-dir> <max-bytes> <max-chunks> <manifest> <manifest-bytes> [<max-files>]

Writes <out-dir>/chunk-<k>.patch, k from 1, each at most max-bytes and, with
max-files, at most that many files, the
patch's bytes in order and nothing else. A chunk ends at a file boundary (a
`diff --git` line), and a file is never split: a file over max-bytes, or a
patch that needs more than max-chunks chunks, is too large: nothing is
written, the error names each such file, and the exit status is 3. An empty
patch writes no chunk.

With more than one chunk it also writes <manifest>, each file of the patch
in order as `chunk <k> <status> <path>`, status added, deleted, renamed (the
path `old -> new`) or modified, so each chunk's reviewer sees what the other
chunks hold. Each path is git's own, quoted as git quotes it, so a path never
breaks a line. Files past manifest-bytes are counted, not listed; the whole manifest, that
count's line included, stays within manifest-bytes.
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


def files_of(data: bytes) -> list[list[bytes]]:
    files: list[list[bytes]] = []
    for line in lines_of(data):
        if not files or line.startswith(b"diff --git "):
            files.append([])
        files[-1].append(line)
    return files


def split(
    data: bytes, max_bytes: int, max_chunks: int, max_files: int = 0
) -> list[bytes]:
    files = files_of(data)
    over = [
        entry(lines).decode(errors="replace")
        for lines in files
        if sum(map(len, lines)) > max_bytes
    ]
    if over:
        raise TooLarge(
            f"a file is larger than one chunk of {max_bytes} bytes: {', '.join(over)}"
        )
    chunks: list[bytes] = []
    count = 0
    for unit in (b"".join(lines) for lines in files):
        if (
            not chunks
            or len(chunks[-1]) + len(unit) > max_bytes
            or (max_files and count >= max_files)
        ):
            chunks.append(b"")
            count = 0
        chunks[-1] += unit
        count += 1
    if len(chunks) > max_chunks:
        raise TooLarge(f"the diff needs {len(chunks)} chunks, more than {max_chunks}")
    return chunks


def entry(lines: list[bytes]) -> bytes:
    """A file's `<status> <path>` from its header lines. Content lines start
    with a prefix byte, so none matches; without a rename the header's a and
    b paths are the same, each half of it."""
    rest = lines[0][len(b"diff --git ") :].rstrip(b"\n")
    path = rest[: (len(rest) - 1) // 2]
    path = b'"' + path[3:] if path.startswith(b'"') else path[2:]
    status = b"modified"
    renamed = {}
    for line in lines[1:]:
        if line.startswith((b"--- ", b"@@ ")):
            break
        for key in (b"rename from ", b"rename to "):
            if line.startswith(key):
                renamed[key] = line[len(key) :].rstrip(b"\n")
        if line.startswith(b"new file mode "):
            status = b"added"
        elif line.startswith(b"deleted file mode "):
            status = b"deleted"
    if len(renamed) == 2:
        return b"renamed " + renamed[b"rename from "] + b" -> " + renamed[b"rename to "]
    return status + b" " + path


def manifest(chunks: list[bytes], max_bytes: int) -> bytes:
    lines = [
        b"chunk %d " % k + entry(lines)
        for k, chunk in enumerate(chunks, 1)
        for lines in files_of(chunk)
    ]

    def more(count: int) -> bytes:
        return b"and %d more files, not listed\n" % count if count else b""

    out = b""
    for n, line in enumerate(lines):
        left = len(lines) - n - 1
        if len(out) + len(line) + 1 + len(more(left)) > max_bytes:
            return out + more(len(lines) - n)
        out += line + b"\n"
    return out


if __name__ == "__main__":
    patch, out, max_bytes, max_chunks, manifest_file, manifest_bytes = sys.argv[1:7]
    max_files = int(sys.argv[7]) if len(sys.argv) > 7 else 0
    try:
        chunks = split(
            Path(patch).read_bytes(), int(max_bytes), int(max_chunks), max_files
        )
    except TooLarge as error:
        print(f"split-diff: {error}", file=sys.stderr)
        sys.exit(TOO_LARGE)
    for k, chunk in enumerate(chunks, 1):
        (Path(out) / f"chunk-{k}.patch").write_bytes(chunk)
    if len(chunks) > 1:
        Path(manifest_file).write_bytes(manifest(chunks, int(manifest_bytes)))
