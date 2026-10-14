#!/usr/bin/env bash
# A locked goal whose metric command passes --json to a timing harness that has no such flag:
# the checked-out bench/time-guard.sh predates it.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p hooks bench .work/guard-hook
cat >hooks/guard.sh <<'EOF'
#!/usr/bin/env bash
# Decides allow or deny for one shell command. Usage: guard.sh <command>
set -euo pipefail
word="$(echo "$1" | cut -d' ' -f1)"
if [[ "$word" == rm ]]; then echo deny; else echo allow; fi
EOF

cat >bench/time-guard.sh <<'EOF'
#!/usr/bin/env bash
# Times hooks/guard.sh over N calls and prints one line per call: ms=<wall ms>.
set -euo pipefail
usage() {
  printf 'time-guard.sh [--iterations N]\n\n  --iterations N   calls to time (default 20)\n  --help           this text\n'
}
iterations=20
while (($#)); do
  case "$1" in
    --iterations) iterations="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) printf 'time-guard.sh: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for _ in $(seq "$iterations"); do
  start="$(date +%s%N)"
  bash "$root/hooks/guard.sh" 'rm -rf /tmp/x' >/dev/null
  end="$(date +%s%N)"
  printf 'ms=%s\n' "$(((end - start) / 1000000))"
done
EOF
chmod +x hooks/guard.sh bench/time-guard.sh

cat >.work/guard-hook/PLAN.md <<'EOF'
# guard-hook

## Goal (locked by /performance:goal)

```text
Metric:     bash bench/time-guard.sh --iterations 20 --json -> .p50_ms
Counter:    external commands per call (spawn census, PATH-shim accounting)   [ranked above the duration]
Correlation: unproven
Path:       deny path for rm -rf (observable: stdout "deny", exit 0)
Boundary:   start hook process exec -> end hook prints its decision; one process; warm path
Event:      n/a
Unit:       n/a
Floor:      0 external commands (measured by: census of a hook body that only prints "deny")
Realistic:  0 external commands [stated]    Ideal: 0
Percentiles: p50, p95 over N>=20
Scaling:    n/a: subject reads no growing state
Done when:  counter = 0 on the deny path; behavior unchanged; merge in scope
Min attempts: n/a: no loop planned
Target (from /performance:target): hooks/guard.sh @ E1
```
EOF

printf '.work/\n' >.gitignore
git add .gitignore hooks bench
git commit -q -m "guard hook and its timing harness"
