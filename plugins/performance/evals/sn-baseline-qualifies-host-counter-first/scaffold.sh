#!/usr/bin/env bash
# A guard hook with a locked /performance:goal in the topic's PLAN.md, ready for a baseline.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p hooks .work/guard-hook
cat >hooks/guard.sh <<'EOF'
#!/usr/bin/env bash
# Decides allow, ask or deny for one shell command. Usage: guard.sh <strict|lenient> <command>
set -euo pipefail
mode="$1"
cmd="$2"
word="$(echo "$cmd" | cut -d' ' -f1)"
flags="$(echo "$cmd" | tr -s ' ' | cut -d' ' -f2)"
if [[ "$word" == rm && "$flags" == -*r* ]]; then
  echo deny
  exit 0
fi
if [[ "$word" == git ]] && grep -q -- '--force' <<<"$cmd"; then
  if [[ "$mode" == strict ]]; then echo deny; else echo ask; fi
  exit 0
fi
echo allow
EOF
chmod +x hooks/guard.sh

cat >.work/guard-hook/PLAN.md <<'EOF'
# guard-hook

## Goal (locked by /performance:goal)

```text
Metric:     bash hooks/guard.sh strict 'rm -rf /tmp/x' -> wall time per call (ms)
Counter:    external commands per call (spawn census, PATH-shim accounting)   [ranked above the duration]
Correlation: unproven
Path:       deny path for rm -rf (observable: stdout "deny", exit 0)
Boundary:   start hook process exec -> end hook prints its decision; one process; warm path
Event:      n/a
Unit:       n/a
Floor:      0 external commands (measured by: census of a hook body that only prints "deny")
Realistic:  1 external command [stated]    Ideal: 0
Percentiles: p50, p95 over N>=20
Scaling:    n/a: subject reads no growing state
Done when:  counter <= 1 on the deny path; behavior unchanged in strict and lenient modes; merge in scope
Min attempts: n/a: no loop planned
Target (from /performance:target): hooks/guard.sh @ E1
```
EOF

printf '.work/\n' >.gitignore
git add .gitignore hooks
git commit -q -m "guard hook"
