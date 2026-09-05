#!/usr/bin/env python3
"""Count the comment burden of a code tree, with an honest token estimate.

Answers the question a comment-removal pass has to be able to answer before
and after it runs: how many comment lines and bytes are here, what is that in
tokens, and did the last pass move the number.

Two reading layers, each named in the output so a reader knows how the count
was made:

  scc       per-file comment and code LINES plus a complexity estimate, in one
            pass over 300+ languages. No byte counts.
  pygments  per-file comment BYTES and lines from the token stream, so the
            token estimate is real text, not a line-count multiplied by a
            guess. Correct on heredocs, trailing comments and block comments.

Both present: lines and complexity from scc, bytes from pygments. Neither
present: exit 3 naming what to install. A line-prefix grep is never used,
because it counts heredoc bodies and string data as comments.

Byte-identical files count once in the deduplicated totals: a vendored copy
kept in sync by a gate is one authored file, however many times it is
instantiated. Both totals are printed because they answer different
questions (authoring effort versus what an agent pays to read).

Tokens are estimated as bytes / 4 and labelled as an estimate throughout.

Usage: comment-census.py [PATH ...] [--top N] [--json] [--baseline FILE]
                         [--layer auto|scc|pygments]
Exit: 0 counted; 3 no reading layer available; 2 usage.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

CODE_EXT = {
    ".cs", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".pyi", ".sh", ".bash",
    ".ps1", ".psm1", ".go", ".rs", ".java", ".rb", ".lua", ".sql", ".c", ".h", ".cpp",
    ".hpp", ".yaml", ".yml", ".toml",
}
EXIT_NO_LAYER = 3
EXIT_USAGE = 2


def tracked_files(roots: list[Path]) -> list[Path]:
    """Code files under each root: git-tracked when inside a repo, else walked."""
    out: list[Path] = []
    for root in roots:
        if root.is_file():
            if root.suffix.lower() in CODE_EXT:
                out.append(root)
            continue
        try:
            listing = subprocess.run(
                ["git", "ls-files", "-z", "--", str(root)],
                capture_output=True, check=True, cwd=str(root if root.is_dir() else root.parent),
            ).stdout
            names = [n for n in listing.decode(errors="replace").split("\0") if n]
            base = root if root.is_dir() else root.parent
            found = [base / n for n in names]
        except (subprocess.CalledProcessError, FileNotFoundError):
            found = [p for p in root.rglob("*") if p.is_file()]
        out.extend(p for p in found if p.suffix.lower() in CODE_EXT and p.is_file())
    seen: set[Path] = set()
    uniq = []
    for p in out:
        rp = p.resolve()
        if rp not in seen:
            seen.add(rp)
            uniq.append(p)
    return sorted(uniq, key=lambda p: str(p))


def scc_counts(files: list[Path]) -> dict[str, dict] | None:
    exe = shutil.which("scc")
    if not exe or not files:
        return None
    proc = subprocess.run(
        [exe, "--by-file", "--format", "json", "--no-cocomo", *map(str, files)],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode != 0:
        return None
    by_path: dict[str, dict] = {}
    for lang in json.loads(proc.stdout or "[]"):
        for f in lang.get("Files", []):
            by_path[os.path.normpath(f["Location"])] = {
                "language": lang.get("Name", f.get("Language", "?")),
                "comment_lines": f.get("Comment", 0),
                "code_lines": f.get("Code", 0),
                "lines": f.get("Lines", 0),
                "complexity": f.get("Complexity", 0),
            }
    return by_path


def pygments_counts(path: Path) -> dict | None:
    try:
        from pygments import lex
        from pygments.lexers import get_lexer_for_filename
        from pygments.token import Comment
        from pygments.util import ClassNotFound
    except ImportError:
        return None
    try:
        lexer = get_lexer_for_filename(str(path), stripnl=False)
    except ClassNotFound:
        return {"language": "?", "comment_lines": 0, "comment_bytes": 0, "lines": 0, "lexed": False}
    src = path.read_text(encoding="utf-8", errors="replace")
    line = 1
    comment_lines: set[int] = set()
    comment_bytes = 0
    for tok, text in lex(src, lexer):
        if tok in Comment and tok not in (Comment.Hashbang, Comment.Preproc):
            body = text.strip("\n")
            if body.strip():
                comment_bytes += len(body.encode("utf-8"))
                for i in range(text.count("\n") + 1):
                    if i < len(text.split("\n")) and text.split("\n")[i].strip():
                        comment_lines.add(line + i)
        line += text.count("\n")
    return {
        "language": lexer.name,
        "comment_lines": len(comment_lines),
        "comment_bytes": comment_bytes,
        "lines": src.count("\n") + (0 if src.endswith("\n") or not src else 1),
        "lexed": True,
    }


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def census(files: list[Path], layer: str) -> tuple[list[dict], dict]:
    scc = scc_counts(files) if layer in ("auto", "scc") else None
    use_pygments = layer in ("auto", "pygments")
    records = []
    sources = {"lines": None, "bytes": None, "complexity": None}
    for p in files:
        rec = {"path": str(p), "sha256": sha256_of(p), "size": p.stat().st_size}
        s = scc.get(os.path.normpath(str(p))) if scc else None
        g = pygments_counts(p) if use_pygments else None
        if g is None and use_pygments and layer == "pygments":
            return [], {"error": "pygments is not installed (pip install pygments)"}
        if s:
            rec.update(language=s["language"], comment_lines=s["comment_lines"],
                       code_lines=s["code_lines"], lines=s["lines"], complexity=s["complexity"])
            sources["lines"] = sources["lines"] or "scc"
            sources["complexity"] = "scc"
        if g and g.get("lexed"):
            rec.setdefault("language", g["language"])
            rec.setdefault("comment_lines", g["comment_lines"])
            rec.setdefault("lines", g["lines"])
            rec["comment_bytes"] = g["comment_bytes"]
            sources["bytes"] = "pygments"
            sources["lines"] = sources["lines"] or "pygments"
        if "comment_lines" not in rec:
            rec.update(language=(g or {}).get("language", "?"), comment_lines=0, lines=0, unread=True)
        records.append(rec)
    if not records:
        return [], sources
    if sources["lines"] is None:
        return [], {"error": "neither scc nor pygments is available (install scc, or pip install pygments)"}
    return records, sources


def totals(records: list[dict], dedupe: bool) -> dict:
    chosen = records
    duplicates = 0
    if dedupe:
        by_hash: dict[str, dict] = {}
        for r in records:
            if r["sha256"] not in by_hash:
                by_hash[r["sha256"]] = r
            else:
                duplicates += 1
        chosen = list(by_hash.values())
    cl = sum(r.get("comment_lines", 0) for r in chosen)
    lines = sum(r.get("lines", 0) for r in chosen)
    cb = sum(r.get("comment_bytes", 0) for r in chosen if "comment_bytes" in r)
    return {
        "files": len(chosen),
        "duplicate_copies_collapsed": duplicates,
        "comment_lines": cl,
        "lines": lines,
        "comment_ratio": round(cl / lines, 4) if lines else 0.0,
        "comment_bytes": cb,
        "approx_tokens": cb // 4,
    }


def by_language(records: list[dict]) -> list[dict]:
    agg: dict[str, dict] = defaultdict(lambda: {"files": 0, "comment_lines": 0, "lines": 0, "comment_bytes": 0})
    for r in records:
        a = agg[r.get("language", "?")]
        a["files"] += 1
        a["comment_lines"] += r.get("comment_lines", 0)
        a["lines"] += r.get("lines", 0)
        a["comment_bytes"] += r.get("comment_bytes", 0)
    rows = []
    for lang, a in agg.items():
        rows.append({"language": lang, **a, "comment_ratio": round(a["comment_lines"] / a["lines"], 4) if a["lines"] else 0.0})
    return sorted(rows, key=lambda r: (-r["comment_lines"], r["language"]))


def render(report: dict, top: int) -> str:
    out = []
    src = report["sources"]
    out.append(
        f"layers: lines={src.get('lines') or 'n/a'} bytes={src.get('bytes') or 'n/a (pip install pygments)'} "
        f"complexity={src.get('complexity') or 'n/a (install scc)'}"
    )
    for key, label in (("raw", "raw   "), ("deduped", "deduped")):
        t = report[key]
        out.append(
            f"{label}: files={t['files']} comment_lines={t['comment_lines']} lines={t['lines']} "
            f"ratio={t['comment_ratio']:.1%} comment_bytes={t['comment_bytes']} approx_tokens={t['approx_tokens']}"
            + (f" (collapsed {t['duplicate_copies_collapsed']} byte-identical copies)" if key == "deduped" else "")
        )
    out.append("tokens are an estimate: comment_bytes / 4")
    out.append("")
    out.append("language\tfiles\tcomment_lines\tlines\tratio\tcomment_bytes")
    for r in report["by_language"]:
        out.append(f"{r['language']}\t{r['files']}\t{r['comment_lines']}\t{r['lines']}\t{r['comment_ratio']:.1%}\t{r['comment_bytes']}")
    if top:
        out.append("")
        out.append(f"top {top} files by comment_lines (deduplicated)")
        seen: set[str] = set()
        shown = 0
        for r in sorted(report["files"], key=lambda r: (-r.get("comment_lines", 0), r["path"])):
            if r["sha256"] in seen:
                continue
            seen.add(r["sha256"])
            out.append(f"{r.get('comment_lines', 0)}\t{r.get('lines', 0)}\t{r['path']}")
            shown += 1
            if shown >= top:
                break
    if "delta" in report:
        d = report["delta"]
        out.append("")
        out.append(
            f"delta vs baseline (deduped): comment_lines {d['comment_lines']:+d}, "
            f"comment_bytes {d['comment_bytes']:+d}, approx_tokens {d['approx_tokens']:+d}"
        )
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("paths", nargs="*", type=Path, help="files or directories; default: the current directory")
    ap.add_argument("--top", type=int, default=10, help="top-N files by comment lines (0 to omit)")
    ap.add_argument("--json", action="store_true", help="emit the full report as JSON (usable as a later --baseline)")
    ap.add_argument("--baseline", type=Path, help="a prior --json report to diff the deduplicated totals against")
    ap.add_argument("--layer", choices=("auto", "scc", "pygments"), default="auto")
    args = ap.parse_args(argv)

    roots = args.paths or [Path(".")]
    for r in roots:
        if not r.exists():
            print(f"comment-census: no such path {r}", file=sys.stderr)
            return EXIT_USAGE
    files = tracked_files(roots)
    records, sources = census(files, args.layer)
    if "error" in sources:
        print(f"comment-census: UNAVAILABLE: {sources['error']}", file=sys.stderr)
        return EXIT_NO_LAYER
    report = {
        "sources": sources,
        "raw": totals(records, dedupe=False),
        "deduped": totals(records, dedupe=True),
        "by_language": by_language(records),
        "files": records,
        "token_estimate": "comment_bytes / 4",
    }
    if args.baseline:
        try:
            base = json.loads(args.baseline.read_text(encoding="utf-8"))["deduped"]
        except (OSError, ValueError, KeyError) as exc:
            print(f"comment-census: baseline unreadable: {exc}", file=sys.stderr)
            return EXIT_USAGE
        cur = report["deduped"]
        report["delta"] = {k: cur[k] - base.get(k, 0) for k in ("comment_lines", "comment_bytes", "approx_tokens")}
    if args.json:
        print(json.dumps(report, indent=1, sort_keys=True))
    else:
        print(render(report, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
