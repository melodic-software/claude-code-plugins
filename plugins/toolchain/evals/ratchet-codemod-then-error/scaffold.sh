#!/usr/bin/env bash
# A Python repository whose in-house linter has a rule, no-legacy-typing, with 54 violations across
# six files and a safe autofix. The rule is off in tools/lint.toml.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .github tools src
mkdir -p .github/workflows tools src
cat >tools/lint.toml <<'EOF'
[rules]
no-legacy-typing = "off"
EOF
cat >tools/lint.py <<'EOF'
"""The repository's in-house linter. Rule severities (off, warn, error) live in tools/lint.toml.

    python3 tools/lint.py                        run every rule at its severity; exit 1 on an error
    python3 tools/lint.py --rule R --statistics  print `R violations=<n>` and exit 0
    python3 tools/lint.py --rule R --fix         apply R's safe autofix to every violation

no-legacy-typing: a typing.List/Dict/Set/Tuple generic where the builtin generic works.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PATTERN = re.compile(r"\b(List|Dict|Set|Tuple)\[")
SEVERITY = re.compile(r'^(?P<rule>[\w-]+)\s*=\s*"(?P<level>off|warn|error)"\s*$', re.M)


def sources():
    files = sorted((ROOT / "src").rglob("*.py"))
    if not files:
        sys.exit("lint: no sources under src/")
    return files


def main(argv):
    if "--rule" in argv:
        rule = argv[argv.index("--rule") + 1]
        if rule != "no-legacy-typing":
            sys.exit(f"lint: unknown rule {rule}")
        if "--fix" in argv:
            for path in sources():
                path.write_text(PATTERN.sub(lambda m: m.group(1).lower() + "[", path.read_text()))
            return 0
        count = sum(len(PATTERN.findall(path.read_text())) for path in sources())
        print(f"{rule} violations={count}")
        return 0
    levels = {m["rule"]: m["level"] for m in SEVERITY.finditer((ROOT / "tools/lint.toml").read_text())}
    failed = 0
    for path in sources():
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if PATTERN.search(line) and levels.get("no-legacy-typing", "off") != "off":
                print(f"{path.relative_to(ROOT)}:{number}: no-legacy-typing")
                failed += levels["no-legacy-typing"] == "error"
    return 1 if failed else 0


sys.exit(main(sys.argv[1:]))
EOF
for module in orders invoices refunds payouts carts stock; do
  {
    printf 'from typing import Dict, List\n\n'
    for n in 1 2 3; do
      printf 'def %s_%s(rows: List[int], index: Dict[str, int]) -> List[int]:\n    return rows\n\n' "${module}" "${n}"
    done
  } >"src/${module}.py"
done
cat >.github/workflows/ci.yml <<'EOF'
name: ci
on:
  pull_request:
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: python3 tools/lint.py
EOF
g add -A
g commit -q -m "ledger service"
