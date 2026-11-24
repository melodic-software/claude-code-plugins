"""Cut a review's patch into chunks one run reads, and each chunk into parts
one Read returns whole. pr-review-main and pr-verify both cut with it.

usage: diff_chunking.py split <patch> <out-dir> <max-bytes> <max-chunks> <manifest> <manifest-bytes> [<max-files>] [--cut-lines]
       diff_chunking.py parts <diff-dir> <part-bytes> <part-lines> [--file-parts <list>] [--wrap <bytes>]

split writes <out-dir>/chunk-<k>.patch, k from 1, each at most max-bytes and,
with max-files, at most that many files, the patch's bytes in order and
nothing else. A chunk ends at a file boundary (a `diff --git` line). A file
over max-bytes is cut at its hunks (`@@` lines) into pieces of at most
max-bytes, each repeating the file's header (its lines before the first
hunk), in order; a piece counts as one file, and two pieces of a file never
share a chunk. A file with a hunk that, with that header, is over max-bytes,
or a patch that needs more than max-chunks chunks, is too large: nothing is
written, the error names each such file, and the exit status is 3. With
--cut-lines such a hunk is cut between its lines instead, each cut under an
`@@` header recounted for its lines, so the chunks hold every line but no
longer the patch's bytes alone; only a line over max-bytes with the headers
is then too large. An empty patch writes no chunk.

With more than one chunk split also writes <manifest>, each file of the patch
in order as `chunk <k> <status> <path>`, status added, deleted, renamed (the
path `old -> new`) or modified, and each piece of a cut file as
`chunk <k> piece <i> of <n> <status> <path>`, so each chunk's reviewer sees
what the other chunks hold. Each path is git's own, quoted as git quotes it,
so a path never breaks a line. Files past manifest-bytes are counted, not
listed; the whole manifest, that count's line included, stays within
manifest-bytes.

parts cuts each <diff-dir>/chunk-<k>.patch into <diff-dir>/chunk-<k>/part-<n>.patch
files, n from 001, of at most part-bytes and part-lines, removes the chunk
file, and prints each chunk's bytes, comma-separated. Read may cut a long
line short, so a line over LONG_LINE_BYTES (or --wrap) continues on lines
that start `\\ continued: `, which no line of a diff does, never cut inside a
UTF-8 character, and every byte reaches a whole Read. An empty chunk is one
empty part. With --file-parts, each `diff --git` line of the diff appends the
part it starts in, relative to <diff-dir>'s parent, to that list.
"""

import argparse
import re
import sys
from pathlib import Path

TOO_LARGE = 3
LONG_LINE_BYTES = 1800
MARK = b"\\ continued: "
MIN_WRAP = 40
HUNK = re.compile(rb"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)", re.S)


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


def cut_hunk(hunk: bytes, room: int) -> list[bytes] | None:
    """A hunk as hunks of at most room bytes, cut between its lines, each
    under an `@@` header recounted for its own lines, so every line keeps
    its place in the file. A `\\ No newline` line stays with the line before
    it. None when the header is not git's, or one line is over room with a
    header. starts holds the first line number of each side; a side git
    counts 0 names the line before, so it starts one later. No cut's numbers
    pass the whole hunk's end, so reserve, a header with those, is the
    longest any cut needs."""
    lines = lines_of(hunk)
    match = HUNK.match(lines[0])
    if not match or len(lines) < 2:
        return None
    starts = [
        int(start) + (count == b"0")
        for start, count in ((match[1], match[2]), (match[3], match[4]))
    ]
    tail = match[5]
    units: list[bytes] = []
    for line in lines[1:]:
        if line.startswith(b"\\") and units:
            units[-1] += line
        else:
            units.append(line)
    n = len(units)
    reserve = len(header(starts[0] + n, n, starts[1] + n, n, tail))
    out: list[bytes] = []
    body: list[bytes] = []
    size = 0
    for unit in units + [b""]:
        if body and (not unit or reserve + size + len(unit) > room):
            olds = sum(u[:1] in b" -" for u in body)
            news = sum(u[:1] in b" +" for u in body)
            out.append(header(starts[0], olds, starts[1], news, tail) + b"".join(body))
            starts = [starts[0] + olds, starts[1] + news]
            body, size = [], 0
        if not unit:
            break
        if reserve + len(unit) > room:
            return None
        body.append(unit)
        size += len(unit)
    return out


def header(old: int, olds: int, new: int, news: int, tail: bytes) -> bytes:
    return (
        b"@@ -%d,%d +%d,%d @@" % (old - (olds == 0), olds, new - (news == 0), news)
        + tail
    )


def pieces_of(
    lines: list[bytes], max_bytes: int, cut_lines: bool = False
) -> list[bytes] | None:
    """A file's diff whole, or cut at its hunks into pieces of at most
    max_bytes under its header; None when a hunk with the header is over,
    unless cut_lines cuts such a hunk at its lines (None then only when one
    line is over). A content line starts with a prefix byte, so only a hunk
    header starts `@@`."""
    whole = b"".join(lines)
    if len(whole) <= max_bytes:
        return [whole]
    at = next((i for i, line in enumerate(lines) if line.startswith(b"@@")), len(lines))
    head = b"".join(lines[:at])
    hunks: list[bytes] = []
    for line in lines[at:]:
        if line.startswith(b"@@"):
            hunks.append(b"")
        hunks[-1] += line
    if cut_lines:
        cut: list[bytes] = []
        for hunk in hunks:
            if len(head) + len(hunk) <= max_bytes:
                cut.append(hunk)
            elif (parts := cut_hunk(hunk, max_bytes - len(head))) is None:
                return None
            else:
                cut += parts
        hunks = cut
    if not hunks or len(head) + max(map(len, hunks)) > max_bytes:
        return None
    pieces = [head + hunks[0]]
    for hunk in hunks[1:]:
        if len(pieces[-1]) + len(hunk) > max_bytes:
            pieces.append(head)
        pieces[-1] += hunk
    return pieces


PieceNumber = int
PiecesOfFileOrZeroWhenWhole = int
Unit = tuple[bytes, PieceNumber, PiecesOfFileOrZeroWhenWhole]


def split(
    data: bytes,
    max_bytes: int,
    max_chunks: int,
    max_files: int = 0,
    cut_lines: bool = False,
) -> list[list[Unit]]:
    units: list[Unit] = []
    over = []
    for lines in files_of(data):
        pieces = pieces_of(lines, max_bytes, cut_lines)
        if pieces is None:
            over.append(entry(lines).decode(errors="replace"))
            continue
        count = len(pieces) if len(pieces) > 1 else 0
        units += [(piece, i, count) for i, piece in enumerate(pieces, 1)]
    if over:
        what = "line" if cut_lines else "hunk"
        raise TooLarge(
            f"a file has a {what} larger than one chunk of {max_bytes} bytes: {', '.join(over)}"
        )
    chunks: list[list[Unit]] = []
    size = 0
    for unit in units:
        if (
            not chunks
            or size + len(unit[0]) > max_bytes
            or (max_files and len(chunks[-1]) >= max_files)
        ):
            chunks.append([])
            size = 0
        chunks[-1].append(unit)
        size += len(unit[0])
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


def manifest(chunks: list[list[Unit]], max_bytes: int) -> bytes:
    lines = [
        b"chunk %d " % k
        + (b"piece %d of %d " % (i, count) if count else b"")
        + entry(lines_of(unit))
        for k, chunk in enumerate(chunks, 1)
        for unit, i, count in chunk
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


def fold(line: bytes, wrap: int) -> list[bytes]:
    """A line as lines of at most wrap bytes, each after the first marked.
    A cut backs off at most three UTF-8 continuation bytes, so a run of stray
    ones still folds at the cap."""
    if wrap < MIN_WRAP:
        raise ValueError(f"a fold needs at least {MIN_WRAP} bytes a line")
    out = []
    rest, mark = line, b""
    while len(mark) + len(rest) > wrap:
        at = wrap - len(mark)
        for _ in range(3):
            if at <= 1 or not 0x80 <= rest[at] < 0xC0:
                break
            at -= 1
        out.append(mark + rest[:at])
        rest, mark = rest[at:], MARK
    return out + [mark + rest]


def parts(
    data: bytes, part_bytes: int, part_lines: int, wrap: int = LONG_LINE_BYTES
) -> tuple[list[bytes], list[int]]:
    """The chunk's parts, and the part index each `diff --git` line starts
    in. The header test reads the line as the diff has it, so a continuation
    cannot pose as a file."""
    out: list[bytes] = []
    headers: list[int] = []
    size = count = 0
    lines = data.split(b"\n")
    if lines[-1] == b"":
        lines.pop()
    for line in lines:
        for i, text in enumerate(fold(line, wrap)):
            if not out or size + len(text) + 1 > part_bytes or count >= part_lines:
                out.append(b"")
                size = count = 0
            out[-1] += text + b"\n"
            size += len(text) + 1
            count += 1
            if i == 0 and line.startswith(b"diff --git "):
                headers.append(len(out))
    return out or [b""], headers


def write_parts(
    diff_dir: Path, part_bytes: int, part_lines: int, file_parts: Path | None, wrap: int
) -> list[int]:
    sizes = []
    k = 1
    while (chunk := diff_dir / f"chunk-{k}.patch").exists():
        data = chunk.read_bytes()
        out, headers = parts(data, part_bytes, part_lines, wrap)
        (diff_dir / f"chunk-{k}").mkdir()
        for n, part in enumerate(out, 1):
            (diff_dir / f"chunk-{k}" / f"part-{n:03d}.patch").write_bytes(part)
        if file_parts:
            with file_parts.open("a") as listed:
                listed.writelines(
                    f"{diff_dir.name}/chunk-{k}/part-{n:03d}.patch\n" for n in headers
                )
        sizes.append(len(data))
        chunk.unlink()
        k += 1
    return sizes


def main(argv: list[str]) -> int:
    cli = argparse.ArgumentParser(prog="diff_chunking.py")
    sub = cli.add_subparsers(dest="command", required=True)
    s = sub.add_parser("split")
    for name, kind in zip(
        ("patch", "out", "max_bytes", "max_chunks", "manifest", "manifest_bytes"),
        (Path, Path, int, int, Path, int),
    ):
        s.add_argument(name, type=kind)
    s.add_argument("max_files", nargs="?", type=int, default=0)
    s.add_argument("--cut-lines", action="store_true")
    p = sub.add_parser("parts")
    p.add_argument("diff_dir", type=Path)
    p.add_argument("part_bytes", type=int)
    p.add_argument("part_lines", type=int)
    p.add_argument("--file-parts", type=Path)
    p.add_argument("--wrap", type=int, default=LONG_LINE_BYTES)
    a = cli.parse_args(argv)
    if a.command == "parts":
        sizes = write_parts(
            a.diff_dir, a.part_bytes, a.part_lines, a.file_parts, a.wrap
        )
        print(",".join(map(str, sizes)))
        return 0
    try:
        chunks = split(
            a.patch.read_bytes(), a.max_bytes, a.max_chunks, a.max_files, a.cut_lines
        )
    except TooLarge as error:
        print(f"split-diff: {error}", file=sys.stderr)
        return TOO_LARGE
    for k, chunk in enumerate(chunks, 1):
        (a.out / f"chunk-{k}.patch").write_bytes(b"".join(u for u, _, _ in chunk))
    if len(chunks) > 1:
        a.manifest.write_bytes(manifest(chunks, a.manifest_bytes))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
