#!/usr/bin/env bash
# Builds a Python repository that already ratchets one counter in .performance/ratchets.json:
# CI runs the vendored .performance/ratchet.py check with no --file. Nine `type: ignore`
# comments exist under app/, and a script counts them.
set -euo pipefail

skill_script="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/ratchet/scripts" && pwd)/ratchet.py"

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p app .performance .github/workflows
for module in api cache jobs mailer models queue reports search webhooks; do
  printf 'import vendored_%s  # type: ignore[import-not-found]\n\n\ndef ready() -> bool:\n    return True\n' \
    "$module" >"app/$module.py"
done

cat >count-ignores.sh <<'EOF'
#!/usr/bin/env bash
# Counts `type: ignore` comments under app/ and prints ignores=<n>.
# Exits 2 when app/ is missing, so a broken checkout never reads as zero.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -d app ]] || { echo "count-ignores: app/ not found" >&2; exit 2; }
count="$(grep -rhoE '#[[:space:]]*type:[[:space:]]*ignore' app | wc -l | tr -d ' ')"
printf 'ignores=%s\n' "$count"
EOF
chmod +x count-ignores.sh

# The vendored script is the skill's copy without its two generated header lines.
tail -n +3 "$skill_script" >.performance/ratchet.py

cat >.performance/ratchets.json <<'EOF'
{
  "counters": [
    {
      "name": "import-spawns",
      "command": "printf 'spawns=3\\n'",
      "field": "spawns",
      "ceiling": 3,
      "goal": "startup spawns 5 -> 3. Correlation: unproven: no field data yet"
    }
  ]
}
EOF

cat >.github/workflows/ci.yml <<'EOF'
name: ci
on:
  pull_request:
permissions:
  contents: read
jobs:
  tests:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Unit tests
        run: python3 -m unittest
      - name: Check counter ceilings
        run: python3 .performance/ratchet.py check
EOF

cat >CONTRIBUTING.md <<'EOF'
# Contributing

The `tests` job in `.github/workflows/ci.yml` is the required status check for merge.
EOF

git add .
git commit -q -m "reports service with one ratcheted counter"
