#!/usr/bin/env bash
# A finished snapshot pair for a guard hook: the after arm cuts external commands, and in
# lenient mode it also turns an rm -rf deny into an ask. Only a differential over both modes
# shows the change; the strict mode is byte-identical.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p arms/before arms/after .work/guard-hook/baselines
cat >arms/before/guard.sh <<'EOF'
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

cat >arms/after/guard.sh <<'EOF'
#!/usr/bin/env bash
# Decides allow, ask or deny for one shell command. Usage: guard.sh <strict|lenient> <command>
set -euo pipefail
mode="$1"
cmd="$2"
read -r word flags _ <<<"$cmd"
if [[ "$word" == rm && "${flags:-}" == -*r* ]]; then
  if [[ "$mode" == strict ]]; then echo deny; else echo ask; fi
  exit 0
fi
if [[ "$word" == git && "$cmd" == *--force* ]]; then
  if [[ "$mode" == strict ]]; then echo deny; else echo ask; fi
  exit 0
fi
echo allow
EOF
chmod +x arms/before/guard.sh arms/after/guard.sh

cat >arms/corpus.txt <<'EOF'
ls -la
git status --porcelain
git push --force origin main
rm -rf /tmp/build
rm notes.txt
echo hello
EOF

cat >.work/guard-hook/PLAN.md <<'EOF'
# guard-hook

## Goal (locked by /performance:goal)

```text
Metric:     bash guard.sh strict 'rm -rf /tmp/build' -> wall time per call (ms)
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
Done when:  counter <= 0 on the deny path; behavior unchanged in both modes (strict, lenient); merge in scope
Min attempts: n/a: no loop planned
Target (from /performance:target): guard.sh @ E1
```
EOF

cat >.work/guard-hook/baselines/baseline.md <<'EOF'
Capture: unassisted, verification absent
Tool: arms/before/guard.sh @ worktree file (no --version) flags-ok: yes behind-upstream: not determinable column-ok: yes
Counter: before spawns=3 (PATH-shim accounting), 2 runs agreed
Path (before): deny path for rm -rf -> deny path (evidence: stdout "deny", exit 0; state: recorded none)
Duration: REFUSED for this report; counter only
EOF

cat >.work/guard-hook/baselines/post.md <<'EOF'
Capture: unassisted, verification absent
Tool: arms/after/guard.sh @ worktree file (no --version) flags-ok: yes behind-upstream: not determinable column-ok: yes
Counter: after spawns=0 (PATH-shim accounting), 2 runs agreed
Path (after): deny path for rm -rf -> deny path (evidence: stdout "deny", exit 0; state: recorded none)
Duration: REFUSED for this report; counter only
EOF

printf '.work/\n' >.gitignore
git add .gitignore arms
git commit -q -m "guard hook before and after arms"
