#!/usr/bin/env bash
# A guard hook whose spawn cut /performance:verify reported MET on a counter, with a
# deterministic count command and a required CI workflow to host the ratchet.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p hooks bench .github/workflows .work/guard-hook
cat >hooks/guard.sh <<'EOF'
#!/usr/bin/env bash
# Decides allow or deny for one shell command. Usage: guard.sh <command>
set -euo pipefail
cmd="$(printf '%s' "$1" | tr -s ' ')"
read -r word flags _ <<<"$cmd"
if [[ "$word" == rm && "${flags:-}" == -*r* ]]; then echo deny; else echo allow; fi
EOF

cat >bench/count-spawns.sh <<'EOF'
#!/usr/bin/env bash
# Counts the external commands hooks/guard.sh starts for one deny-path call and prints
# spawns=<n>. Exits non-zero when the hook fails. No cache is involved.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shims="$root/bench/.shims"
log="$root/bench/.spawn-log"
mkdir -p "$shims"
: >"$log"
for tool in cat cut tr grep sed awk; do
  real="$(command -v "$tool")"
  printf '#!/bin/sh\necho %s >>"%s"\nexec "%s" "$@"\n' "$tool" "$log" "$real" >"$shims/$tool"
  chmod +x "$shims/$tool"
done
PATH="$shims:$PATH" bash "$root/hooks/guard.sh" 'rm -rf /tmp/x' >/dev/null
printf 'spawns=%s\n' "$(wc -l <"$log" | tr -d ' ')"
EOF
chmod +x hooks/guard.sh bench/count-spawns.sh

cat >.github/workflows/ci.yml <<'EOF'
name: ci
on:
  pull_request:
permissions:
  contents: read
jobs:
  ci-status:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Shell tests
        run: bash hooks/guard.sh 'rm -rf /tmp/x' | grep -qx deny
EOF

cat >.work/guard-hook/verify.md <<'EOF'
# /performance:verify report: guard-hook

Target:      1 / 0        Floor: 0
Counter:     4 -> 1          [headline] [unproven]
Correlation: unproven: no duration rig run yet
Scaling:     n/a
Event:       n/a
Unit:        n/a
Measured:    hooks/guard.sh at HEAD
Deployed:    n/a (no install record for this subject)
Duration:    REFUSED, counter-only goal
Limiter:     the one tr call that normalizes spaces; measured by bench/count-spawns.sh
Ruled out:   a failing hook spending fewer spawns: the hook printed deny with exit 0 in every run
Verdict:     MET
Behavior:    UNCHANGED (differential: 40 inputs, modes covered: default)
Not covered: durations
Overrides:   none
Reproduced by an independent verifier: yes, nothing diverged

Counter command: bash bench/count-spawns.sh  (prints spawns=<n>; CI runners start cold and the hook keeps no cache)
Ships behind a flag: no
EOF

printf '.work/\nbench/.shims/\nbench/.spawn-log\n' >.gitignore
git add .gitignore hooks bench .github
git commit -q -m "guard hook, spawn counter and CI"
