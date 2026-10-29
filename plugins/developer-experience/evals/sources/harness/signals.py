#!/usr/bin/env python3
"""List which plugin files each A2 run read, in order, for the transcript signals.

Usage: python3 -I signals.py [--root results] [--model opus] [--help]

For every A2 run under ROOT/<scenario>/A2/<model>/run-<n>/, reads turn1/turn2 stream-json and
records each Read call on a file inside the run's plugin copy, plus each Bash call whose command
names a plugin-copy file (`cat`, `sed`, `bash`, ...). Paths print relative to the plugin root.
Prints one line per run (order of first touches, repeated files with counts), then a summary:
per skill invoked, how many runs touched each bundled file. Exit 0.
"""

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

EVALS = Path(__file__).resolve().parent.parent
BUNDLED = ["skills/setup/SKILL.md", "skills/setup/reference/conventions-file.md", "skills/setup/scripts/pointer-line.sh",
           "skills/build-cli/SKILL.md", "skills/build-cli/reference/cli-contract.md", "skills/audit-tools/SKILL.md",
           "context/recommendation-basis.md", "lib/resolve-convention-home.sh", "README.md", "CHANGELOG.md",
           ".claude-plugin/plugin.json"]
PAT = re.compile(r"(?:developer-experience/)((?:skills|context|lib)/[\w./-]+|README\.md|CHANGELOG\.md|\.claude-plugin/plugin\.json)")


def touches(run_dir):
    seq = []
    for n in (1, 2):
        p = run_dir / f"turn{n}.jsonl"
        if not p.exists():
            continue
        events = []
        for line in p.read_text(encoding="utf-8").splitlines():
            try:
                events.append(json.loads(line))
            except ValueError:
                continue
        # A call the permission check denied read nothing; it is not a touch.
        denied = {d.get("tool_use_id") for e in events if e.get("type") == "result"
                  for d in e.get("permission_denials") or []}
        for e in events:
            if e.get("type") != "assistant":
                continue
            for b in e.get("message", {}).get("content", []) or []:
                if not isinstance(b, dict) or b.get("type") != "tool_use" or b.get("id") in denied:
                    continue
                inp = b.get("input", {}) or {}
                if b.get("name") == "Read":
                    m = PAT.search(str(inp.get("file_path", "")))
                    if m:
                        seq.append((n, "Read", m.group(1)))
                elif b.get("name") == "Bash":
                    for m in PAT.finditer(str(inp.get("command", ""))):
                        seq.append((n, "Bash", m.group(1)))
                elif b.get("name") == "Skill":
                    seq.append((n, "Skill", str(inp.get("skill", ""))))
    return seq


def main(argv):
    args = argv[1:]
    if args[:1] in (["-h"], ["--help"]):
        print(__doc__)
        return 0
    root = args[args.index("--root") + 1] if "--root" in args else "results"
    model = args[args.index("--model") + 1] if "--model" in args else "opus"
    per_skill = defaultdict(Counter)
    runs_per_skill = Counter()
    for run_dir in sorted((EVALS / root).glob(f"*/A2/{model}/run-*")):
        seq = touches(run_dir)
        sc = run_dir.parent.parent.parent.name
        slash = "setup (slash)" if sc.startswith("T") else ("build-cli (slash)" if sc == "N1" else "(none)")
        skills = sorted({s.split(":")[-1] for _, k, s in seq if k == "Skill"}) or [slash]
        files = [f for _, k, f in seq if k != "Skill"]
        order = list(dict.fromkeys(files))
        reps = {f: c for f, c in Counter(files).items() if c > 1}
        print(f"{run_dir.parent.parent.parent.name} {run_dir.name} skills={','.join(skills)} "
              f"order={order} repeated={reps}")
        for s in skills:
            runs_per_skill[s] += 1
            per_skill[s].update(set(files))
    print("\nRuns touching each bundled file, per skill invoked:")
    for s, n in sorted(runs_per_skill.items()):
        print(f"- {s} ({n} runs): " + ", ".join(f"{f} {per_skill[s][f]}" for f in BUNDLED if per_skill[s][f]))
        never = [f for f in BUNDLED if not per_skill[s][f]]
        print(f"  never: {', '.join(never)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
