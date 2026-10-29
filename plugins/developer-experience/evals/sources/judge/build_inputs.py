#!/usr/bin/env python3
"""Build the judge input for every baseline run and J item.

Usage: python3 -I build_inputs.py [--arms A0,A1] [--root results] [--prefix P] [--scenarios S1,..]

Reads <root>/<scenario>/<arm>/opus/run-<n>/ (scored runs only) and writes
judge/inputs/<scenario>/<item>/<P><arm>-run<n>.md: the item's input kind (items.json) with arm
markers stripped (plugin and skill names, conventions paths, source markers, written_against).
Input kinds:
  stderr      H-build #9: stderr of tq commit with the message option missing (from score.json)
  md-diff-help  H-build #12: the markdown diff plus the built command's --help (from score.json)
  final       the final message of every turn, labeled by turn
  turn1       the final message of turn 1 only
  md-diff     the workspace diff restricted to markdown files
  malformed   stdout, stderr and exit code of the S4 helper run on a v1 store with a malformed
              line 3 (re-run in a scratch copy of the run's workspace)
Exit: 0 written, 2 usage.
"""

import importlib.util
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVALS = HERE.parent
SCRATCH = Path(os.environ.get("DX_JUDGE_SCRATCH") or sys.exit("set DX_JUDGE_SCRATCH to a scratch directory")) / "sandboxes"

# Arm markers: plugin and skill names, conventions file paths, the pointer line, the A1 section name.
SCRUB = [
    (re.compile(re.escape(str(SCRATCH)) + r"/[^/\s]+/"), ""),
    (re.compile(r"/home/\S*?/lib/python3\.\d+/"), "<stdlib>/"),
    (re.compile(r"^\+?<!-- developer-experience: source=\w+ -->\n", re.M), ""),
    (re.compile(r"^\+?written_against: developer-experience@\S*\n", re.M), ""),
    (re.compile(r"/?developer-experience(:[\w-]+)?", re.I), "[redacted]"),
    (re.compile(r"\b(build-cli|audit-tools)\b"), "[redacted]"),
    (re.compile(r"(docs/conventions|\.claude)/[\w./-]*\.md"), "[redacted-path]"),
    (re.compile(r"Before creating, changing or cleaning up CLIs[^\n]*"), "[redacted]"),
    (re.compile(r"Developer tooling conventions", re.I), "[project notes]"),
    (re.compile(r"BEGIN GENERATED: plugin-conventions|END GENERATED: plugin-conventions"), "[redacted]"),
]


def scrub(text):
    for pattern, repl in SCRUB:
        text = pattern.sub(repl, text)
    return text


def load_scorer():
    spec = importlib.util.spec_from_file_location("scorer", EVALS / "harness" / "score-deterministic.py")
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load harness/score-deterministic.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def final_messages(sc, run_dir, turns):
    parts = []
    for n in turns:
        path = run_dir / f"turn{n}.jsonl"
        if path.exists():
            parts.append(f"### Assistant final message, turn {n}\n\n{sc.final_text(sc.load_events(path)).strip()}")
    return "\n\n".join(parts)


def md_diff(run_dir):
    text = (run_dir / "workspace.diff").read_text(encoding="utf-8")
    blocks = re.split(r"(?m)^(?=diff --git )", text)
    keep = [b for b in blocks if re.match(r"diff --git a/\S+\.md b/", b)]
    return "".join(keep).strip() or "(no markdown file changed)"


def malformed(sc, run_dir, meta):
    """Re-run the S4 helper on a v1 store with a malformed line 3, as score-deterministic does."""
    ws = Path(meta["workspace"])
    tree = meta["scaffold_tree"]
    sc.fresh_sandbox = lambda src, name: _sandbox(src, f"{meta['arm']}-run{meta['run']}-{name}")
    changes = sc.changed_files(ws, tree)
    new_py = sorted((p for p, s in changes.items() if s != "D" and p.endswith(".py") and not p.startswith("tests/")),
                    key=lambda p: (changes[p] != "A", p))
    helper = next((p for p in new_py if "given_name" in (ws / p).read_text(encoding="utf-8")), None)
    cli_text = (ws / "bfk/cli.py").read_text(encoding="utf-8")
    sub = re.search(r"add_parser\(\s*['\"]([\w-]*migrat[\w-]*)['\"]", cli_text)
    if sub and "migrat" not in (sc.file_at(ws, tree, "bfk/cli.py") or b"").decode("utf-8"):
        base = ["python3", "-m", "bfk.cli", sub.group(1)]
    elif helper and helper.startswith("bfk/"):
        base = ["python3", "-m", helper[:-3].replace("/", ".")]
    elif helper:
        base = ["python3", helper]
    else:
        return "(no migration helper found)"
    import os
    env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "ANTHROPIC"))}
    data = Path("data/accounts.jsonl")
    v1 = sc.file_at(ws, tree, str(data)) or b""
    box = sc.fresh_sandbox(ws, "help")
    (box / data).write_bytes(v1)
    def call(b, extra):
        return sc.run(base + extra, b, dict(env, PYTHONPATH=str(b)), timeout=30)

    _, so_h, se_h = call(box, ["--help"])
    flags = re.findall(r"(--yes|--assume-yes|--force|--no-confirm|--non-interactive|-y)\b", so_h + se_h)
    yes = [flags[0]] if flags else []
    rc0, _, se0 = call(box, yes)
    path_args = [str(data)] if rc0 == 2 and "required" in se0 else []
    box = sc.fresh_sandbox(ws, "malformed")
    lines = v1.decode("utf-8").splitlines(keepends=True)
    lines.insert(2, '{"id": 99, "name": "Broken Record", "email": \n')
    (box / data).write_text("".join(lines), encoding="utf-8")
    rc, so, se = call(box, path_args + yes)
    cmd = " ".join(base[1:] if base[0] == "python3" else base) + " " + " ".join(path_args + yes)
    return (f"Command: python3 {cmd.strip()}\n"
            f"Input: data/accounts.jsonl with line 3 replaced by the malformed record "
            f"`{{\"id\": 99, \"name\": \"Broken Record\", \"email\": ` (the original lines follow it)\n"
            f"Exit code: {rc}\n\n--- stdout ---\n{so.strip()}\n\n--- stderr ---\n{se.strip()}")


def _sandbox(src, name):
    import shutil
    box = SCRATCH / name
    if box.exists():
        shutil.rmtree(box)
    shutil.copytree(src, box, symlinks=True)
    return box


def score_field(run_dir, num, field):
    score = json.loads((run_dir / "score.json").read_text(encoding="utf-8"))
    return next((str(i.get(field, "")) for i in score["items"] if str(i["item"]) == str(num)), "")


def main(argv):
    args = argv[1:]
    if args and args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    opts = {"--arms": "A0,A1", "--root": "results", "--prefix": "", "--scenarios": ""}
    while args:
        if args[0] not in opts or len(args) < 2:
            print(__doc__)
            return 2
        opts[args[0]] = args[1]
        args = args[2:]
    arms = opts["--arms"].split(",")
    wanted = set(filter(None, opts["--scenarios"].split(",")))
    sc = load_scorer()
    items = json.loads((HERE / "items.json").read_text(encoding="utf-8"))
    SCRATCH.mkdir(parents=True, exist_ok=True)
    count = 0
    for it in items:
        if wanted and it["scenario"] not in wanted:
            continue
        for run_dir in sorted((EVALS / opts["--root"] / it["scenario"]).glob("A[012]/opus/run-*")):
            if not (run_dir / "meta.json").exists():
                continue
            meta = json.loads((run_dir / "meta.json").read_text(encoding="utf-8"))
            if meta["arm"] not in arms or not (run_dir / "score.json").exists():
                continue
            kind = it["input"]
            if kind == "stderr":
                body = (f"Command: tq commit given the change type option only (no message), stdin closed\n"
                        f"--- stderr ---\n{score_field(run_dir, it['item'], 'stderr')}")
            elif kind == "md-diff-help":
                body = (md_diff(run_dir) + "\n\n--- `tq commit --help` output of the built command ---\n"
                        + score_field(run_dir, it["item"], "help"))
            elif kind == "final":
                body = final_messages(sc, run_dir, (1, 2))
            elif kind == "turn1":
                body = final_messages(sc, run_dir, (1,))
            elif kind == "md-diff":
                body = md_diff(run_dir)
            elif kind == "malformed":
                body = malformed(sc, run_dir, meta)
            else:
                raise SystemExit(f"unknown input kind {kind}")
            out = (HERE / "inputs" / it["scenario"] / str(it["item"])
                   / f"{opts['--prefix']}{meta['arm']}-run{meta['run']}.md")
            out.parent.mkdir(parents=True, exist_ok=True)
            # "raw" items are plugin-arm only (no arm to hide) and grade the paths the scrub removes.
            out.write_text((body if it.get("raw") else scrub(body)) + "\n", encoding="utf-8")
            count += 1
    print(f"wrote {count} judge inputs")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
