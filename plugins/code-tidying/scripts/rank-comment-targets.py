#!/usr/bin/env python3
"""Rank files for a repo-wide comment pass: exposure times payload.

The output is a READING ORDER, not evidence. A high rank says a file is worth
looking at first; it never says a comment in it is wrong. The formula follows
what the defect-prediction literature actually supports and avoids what it
refutes:

  exposure = 0.45 r(churn/size) + 0.30 r(fan-in) + 0.15 r(churn) + 0.10 r(owner diffusion)
  payload  = r(residual comment volume)         comments beyond what size predicts
  score    = exposure^0.65 * payload^0.35        multiplicative: needs both

  r() is rank-normalization to [0,1]; every input here is power-law shaped,
  so a z-score would be owned by a handful of outliers.

Why these inputs: size-normalized churn is the one input with a hard result
behind it (Nagappan & Ball 2005, absolute churn R2 0.05 vs relative 0.81);
raw commit COUNT is deliberately not an input (Shrikanth & Menzies 2020 found
it replicates only sporadically); fan-in beat complexity at finding the code
developers call critical (Zimmermann & Nagappan 2008); owner diffusion is
one of the two practitioner beliefs that replicated.

Gates run before scoring, because a naive churn head is CHANGELOGs, manifests
and CI config (Spinellis et al. 2026 put 53.6% of hotspots in administrative
files; this repository reproduced that exactly): untracked, generated
(.gitattributes linguist-generated), vendored, lockfiles, CI workflow and
.claude trees, changelogs, files under the size floor, and bot-authored
commits are all dropped first. Byte-identical files collapse to one row
carrying an `instances` count, so a vendored copy kept in sync by a gate is
one target, not eighteen.

Optional drift column, bounded to the top N: how much older a file's comment
lines are than its code lines by git blame author-time. A comment whose code
has been rewritten under it is the highest-value candidate and no tool sells
this signal. git blame is O(file x history), so it never runs repo-wide.

Reading layers come from comment-census.py (scc, pygments). A shallow clone
cannot rank by history: the run says so and ranks by fan-in and payload only.

Usage: rank-comment-targets.py [--top N] [--window-months M] [--half-life-days D]
                               [--min-lines L] [--drift-top K] [--json]
Exit: 0 ranked; 1 not a git repository; 3 no reading layer; 2 usage.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path

EXIT_NOT_GIT = 1
EXIT_USAGE = 2
EXIT_NO_LAYER = 3
BOT = re.compile(r"\[bot\]|dependabot|renovate|github-actions", re.IGNORECASE)
ADMIN = re.compile(
    r"(^|/)(CHANGELOG[^/]*|\.github/workflows/.*|\.claude/.*|node_modules/.*|vendor/.*|dist/.*|build/.*|"
    r"[^/]*lock[^/]*\.(json|yaml|yml|toml))$",
    re.IGNORECASE,
)
CENSUS = Path(__file__).with_name("comment-census.py")


def git(*args: str, cwd: str = ".") -> str:
    return subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False, cwd=cwd
    ).stdout


def rank_norm(values: dict[str, float]) -> dict[str, float]:
    """Rank each value into [0, 1]; equal values share the mean of their ranks.

    Fractional ranking keeps a tie (common for fan-in and churn in a small or
    shallow repository) from being broken by path order, which would let the
    spelling of a filename move a score.
    """
    if not values:
        return {}
    order = sorted(values, key=lambda k: (values[k], k))
    n = len(order)
    if n == 1:
        return {order[0]: 1.0}
    out: dict[str, float] = {}
    i = 0
    while i < n:
        j = i
        while j + 1 < n and values[order[j + 1]] == values[order[i]]:
            j += 1
        mean_rank = (i + j) / 2
        for k in order[i : j + 1]:
            out[k] = mean_rank / (n - 1)
        i = j + 1
    return out


def generated_paths(paths: list[str]) -> set[str]:
    if not paths:
        return set()
    proc = subprocess.run(
        ["git", "check-attr", "--stdin", "-z", "linguist-generated"],
        input="\0".join(paths) + "\0",
        capture_output=True,
        text=True,
        check=False,
    )
    out: set[str] = set()
    fields = proc.stdout.split("\0")
    for i in range(0, len(fields) - 2, 3):
        if fields[i + 2] in ("set", "true"):
            out.add(fields[i])
    return out


def census_records() -> tuple[dict[str, dict], dict]:
    proc = subprocess.run(
        [sys.executable, str(CENSUS), ".", "--json", "--top", "0"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode == EXIT_NO_LAYER:
        raise SystemExit(EXIT_NO_LAYER)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(proc.returncode)
    rep = json.loads(proc.stdout)
    return {os.path.normpath(r["path"]): r for r in rep["files"]}, rep["sources"]


def churn_inputs(window_months: int, half_life_days: float, now: float):
    """Recency-weighted line churn, raw line churn, and per-file author commit counts."""
    log = git(
        "log",
        f"--since={window_months} months ago",
        "--numstat",
        "--no-renames",
        "--pretty=format:@%ct\t%aN",
    )
    weighted: dict[str, float] = defaultdict(float)
    raw: dict[str, float] = defaultdict(float)
    authors: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    w = 0.0
    author = ""
    skip = False
    ln2 = math.log(2)
    for line in log.splitlines():
        if line.startswith("@"):
            ct, _, author = line[1:].partition("\t")
            skip = bool(BOT.search(author))
            age_days = max(0.0, (now - float(ct)) / 86400)
            w = math.exp(-ln2 * age_days / half_life_days)
            continue
        if skip or not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 3 or parts[0] == "-":
            continue
        added, deleted, path = int(parts[0]), int(parts[1]), os.path.normpath(parts[2])
        weighted[path] += w * (added + deleted)
        raw[path] += added + deleted
        authors[path][author] += 1
    return weighted, raw, authors


def fan_in(paths: list[str]) -> dict[str, int]:
    """Occurrences of each candidate's basename across tracked text files, minus its own."""
    names = sorted({os.path.basename(p) for p in paths})
    if not names:
        return {}
    proc = subprocess.run(
        [
            "git",
            "grep",
            "-I",
            "-o",
            "-h",
            "-w",
            "-F",
            "-f",
            "-",
            "--",
            "*.sh",
            "*.py",
            "*.ts",
            "*.tsx",
            "*.js",
            "*.mjs",
            "*.cs",
            "*.yml",
            "*.yaml",
            "*.toml",
            "*.json",
            "*.md",
            "*.ps1",
        ],
        input="\n".join(names) + "\n",
        capture_output=True,
        text=True,
        check=False,
    )
    counts: dict[str, int] = defaultdict(int)
    for line in proc.stdout.splitlines():
        counts[line] += 1
    out = {}
    for p in paths:
        own = 0
        try:
            own = (
                Path(p)
                .read_text(encoding="utf-8", errors="replace")
                .count(os.path.basename(p))
            )
        except OSError:
            pass
        out[p] = max(0, counts.get(os.path.basename(p), 0) - own)
    return out


def comment_line_numbers(path: str) -> set[int]:
    try:
        from pygments import lex
        from pygments.lexers import get_lexer_for_filename
        from pygments.token import Comment
    except ImportError:
        return set()
    try:
        lexer = get_lexer_for_filename(path, stripnl=False)
    except Exception:  # noqa: BLE001 - unknown extension means no comment lines to report
        return set()
    src = Path(path).read_text(encoding="utf-8", errors="replace")
    line, out = 1, set()
    for tok, text in lex(src, lexer):
        if tok in Comment and tok is not Comment.Hashbang and text.strip():
            out.update(range(line, line + text.count("\n") + 1))
        line += text.count("\n")
    return out


def drift_days(path: str) -> float | None:
    """Median code-line author-time minus median comment-line author-time, in days."""
    blame = git("blame", "--line-porcelain", "-w", "--", path)
    times: dict[int, int] = {}
    lineno = 0
    for line in blame.splitlines():
        if line.startswith("author-time "):
            current = int(line.split()[1])
        elif line.startswith("\t"):
            lineno += 1
            times[lineno] = current
    comments = comment_line_numbers(path)
    ct = sorted(t for n, t in times.items() if n in comments)
    codet = sorted(t for n, t in times.items() if n not in comments)
    if not ct or not codet:
        return None
    return (codet[len(codet) // 2] - ct[len(ct) // 2]) / 86400


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--window-months", type=int, default=24)
    ap.add_argument("--half-life-days", type=float, default=90.0)
    ap.add_argument("--min-lines", type=int, default=30, help="size floor, in lines")
    ap.add_argument(
        "--drift-top",
        type=int,
        default=10,
        help="compute the blame drift column for this many top rows (0 disables)",
    )
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if (
        args.top < 0
        or args.min_lines < 0
        or args.drift_top < 0
        or args.half_life_days <= 0
    ):
        print(
            "rank-comment-targets: arguments must be non-negative (half-life positive)",
            file=sys.stderr,
        )
        return EXIT_USAGE
    if (
        subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            capture_output=True,
            check=False,
        ).returncode
        != 0
    ):
        return EXIT_NOT_GIT

    shallow = git("rev-parse", "--is-shallow-repository").strip() == "true"
    records, sources = census_records()
    tracked = [os.path.normpath(p) for p in git("ls-files", "-z").split("\0") if p]
    gated: dict[str, int] = defaultdict(int)
    generated = generated_paths(tracked)
    candidates = []
    for p in tracked:
        r = records.get(p)
        if r is None:
            gated["not a code file"] += 1
            continue
        if ADMIN.search(p):
            gated["administrative path"] += 1
            continue
        if p in generated:
            gated["generated"] += 1
            continue
        if r.get("lines", 0) < args.min_lines:
            gated["below size floor"] += 1
            continue
        candidates.append(p)

    # Collapse byte-identical files to one canonical row with an instance count.
    by_hash: dict[str, list[str]] = defaultdict(list)
    for p in candidates:
        by_hash[records[p]["sha256"]].append(p)
    canonical = {min(v): len(v) for v in by_hash.values()}
    rows = sorted(canonical)
    gated["byte-identical copies collapsed"] = len(candidates) - len(rows)

    now = time.time()
    weighted, raw, authors = (
        ({}, {}, {})
        if shallow
        else churn_inputs(args.window_months, args.half_life_days, now)
    )
    fin = fan_in(rows)

    # Residual comment volume: comment lines beyond the per-language median ratio.
    ratio_by_lang: dict[str, list[float]] = defaultdict(list)
    for p in rows:
        r = records[p]
        if r.get("lines"):
            ratio_by_lang[r.get("language", "?")].append(
                r.get("comment_lines", 0) / r["lines"]
            )
    median = {k: sorted(v)[len(v) // 2] for k, v in ratio_by_lang.items()}

    inputs: dict[str, dict[str, float]] = {}
    for p in rows:
        r = records[p]
        lines = max(1, r.get("lines", 0))
        a = sum(weighted.get(q, 0.0) for q in by_hash[r["sha256"]])
        raw_a = sum(raw.get(q, 0.0) for q in by_hash[r["sha256"]])
        auth = defaultdict(int)
        for q in by_hash[r["sha256"]]:
            for who, n in authors.get(q, {}).items():
                auth[who] += n
        total = sum(auth.values())
        diffusion = 1 - (max(auth.values()) / total) if total else 0.0
        expected = median.get(r.get("language", "?"), 0.0) * lines
        residual = max(0.0, r.get("comment_lines", 0) - expected)
        inputs[p] = {
            "churn_per_line": a / lines,
            "fan_in": float(fin.get(p, 0)),
            "churn": a,
            "raw_churn": raw_a,
            "owner_diffusion": diffusion,
            "residual_comment_lines": residual,
            "comment_lines": float(r.get("comment_lines", 0)),
            "lines": float(lines),
        }

    def norm(key):
        return rank_norm({p: v[key] for p, v in inputs.items()})

    r_cpl, r_fin, r_churn, r_own, r_res = (
        norm(k)
        for k in (
            "churn_per_line",
            "fan_in",
            "churn",
            "owner_diffusion",
            "residual_comment_lines",
        )
    )
    scored = []
    for p, v in inputs.items():
        if shallow:
            exposure = r_fin[p]
        else:
            exposure = (
                0.45 * r_cpl[p] + 0.30 * r_fin[p] + 0.15 * r_churn[p] + 0.10 * r_own[p]
            )
        payload = r_res[p] if v["comment_lines"] > 0 else 0.0
        score = (exposure**0.65) * (payload**0.35) if payload > 0 else 0.0
        scored.append(
            {
                "path": p,
                "score": round(score, 4),
                "instances": canonical[p],
                **{k: round(x, 3) for k, x in v.items()},
            }
        )
    scored.sort(key=lambda r: (-r["score"], r["path"]))
    top = scored[: args.top] if args.top else scored
    for row in top[: args.drift_top]:
        d = drift_days(row["path"])
        row["comment_age_vs_code_days"] = None if d is None else round(d, 1)

    report = {
        "reading_order_not_evidence": True,
        "shallow_clone": shallow,
        "sources": sources,
        "gated": dict(gated),
        "candidates": len(rows),
        "rows": top,
    }
    if args.json:
        print(json.dumps(report, indent=1, sort_keys=True))
        return 0
    print(
        "READING ORDER, NOT EVIDENCE: a rank says look here first; it never says a comment is wrong."
    )
    if shallow:
        print(
            "shallow clone: no usable history, ranking by fan-in and comment payload only"
        )
    print(
        f"layers: lines={sources.get('lines')} bytes={sources.get('bytes') or 'n/a'} complexity={sources.get('complexity') or 'n/a'}"
    )
    print(
        "gated out: "
        + ", ".join(f"{k}={v}" for k, v in sorted(gated.items()))
        + f"; candidates={len(rows)}"
    )
    print()
    print(
        "rank\tscore\tinst\tcomment_lines\tlines\tchurn\tfan_in\towners\tresidual\tdrift_days\tpath"
    )
    for i, r in enumerate(top, 1):
        drift = r.get("comment_age_vs_code_days")
        drift_s = "" if drift is None else f"{drift:+.0f}"
        print(
            f"{i}\t{r['score']:.3f}\t{r['instances']}\t{int(r['comment_lines'])}\t{int(r['lines'])}\t{r['churn']:.1f}\t{int(r['fan_in'])}\t{r['owner_diffusion']:.2f}\t{r['residual_comment_lines']:.0f}\t{drift_s}\t{r['path']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
