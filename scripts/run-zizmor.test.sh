#!/usr/bin/env bash
# Self-test for scripts/run-zizmor.sh with a stubbed zizmor on PATH. The stub
# answers the offline run (--no-online-audits) and the online run separately,
# so each case pins one pair of outcomes. The error text is zizmor 1.30's, from
# merge-group run 39187151244 (403 on api.github.com/advisories) and a local
# reproduction of a refused connection.
# test-scope: scripts/run-zizmor.sh .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/run-zizmor.sh"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$ROOT/scripts/lib/fixture-tree.sh"

scratch=""
fixture_tree::build scratch --label run-zizmor
mkdir -p "$scratch/bin"

# A fatal online-audit error, as zizmor 1.30 prints it, with <cause> as the
# innermost lines.
online_error() {
  cat <<EOF
fatal: no audit was performed
'known-vulnerable-actions' audit failed on file://./.github/actions/check-wip-cap/action.yml

Caused by:
    0: error in 'known-vulnerable-actions' audit
    1: request error while accessing GitHub API
$1
EOF
}

# stub <offline-rc> <offline-out> <online-rc> <online-out>: a zizmor whose
# offline run (--no-online-audits) and online run print and exit as given.
stub() {
  printf '%s' "$2" >"$scratch/offline.out"
  printf '%s' "$4" >"$scratch/online.out"
  cat >"$scratch/bin/zizmor" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$scratch/calls"
case " \$* " in
*' --no-online-audits '*) cat "$scratch/offline.out"; exit $1 ;;
*) cat "$scratch/online.out"; exit $3 ;;
esac
EOF
  chmod +x "$scratch/bin/zizmor"
  : >"$scratch/calls"
}

run() {
  OUT=$(PATH="$scratch/bin:$PATH" bash "$SCRIPT" 2>&1) && RC=0 || RC=$?
}

check() { # check <name> <condition-result>
  if [[ "$2" == yes ]]; then ok "$1"; else bad "$1" "rc=$RC out=$OUT"; fi
}

finding='::error file=.github/workflows/a.yml,line=7,title=unpinned-uses::a.yml:7: unpinned action reference'

# A 403 from the online audit warns, names the status, and passes.
stub 0 '' 1 "$(online_error '    2: HTTP status client error (403 Forbidden) for url (https://api.github.com/advisories?ecosystem=actions)')"
run
check 'a 403 from the online audit is a warning naming the status, and passes' \
  "$([[ $RC -eq 0 && "$OUT" == *'::warning title=zizmor online audits not run::'*'HTTP 403'* ]] && echo yes)"
check 'the offline audits run first, then the online run' \
  "$([[ "$(sed -n 1p "$scratch/calls")" == *--no-online-audits* && "$(sed -n 2p "$scratch/calls")" != *--no-online-audits* ]] && echo yes)"

stub 0 '' 1 "$(online_error '    2: HTTP status client error (429 Too Many Requests) for url (https://api.github.com/advisories)')"
run
check 'a 429 is a warning naming the status' "$([[ $RC -eq 0 && "$OUT" == *'::warning '*'HTTP 429'* ]] && echo yes)"

stub 0 '' 1 "$(online_error '    2: HTTP status server error (502 Bad Gateway) for url (https://api.github.com/advisories)')"
run
check 'a 5xx is a warning naming the status' "$([[ $RC -eq 0 && "$OUT" == *'::warning '*'HTTP 502'* ]] && echo yes)"

stub 0 '' 1 "$(online_error $'    2: error sending request for url (https://api.github.com/advisories)\n    3: operation timed out')"
run
check 'a timeout is a warning naming the network error' \
  "$([[ $RC -eq 0 && "$OUT" == *'::warning '*'operation timed out'* ]] && echo yes)"

# Not a downgrade: a 401 or 404 is a configuration or reference problem.
stub 0 '' 1 "$(online_error '    2: HTTP status client error (401 Unauthorized) for url (https://api.github.com/advisories)')"
run
check 'a 401 still fails' "$([[ $RC -ne 0 && "$OUT" != *'::warning title=zizmor online'* ]] && echo yes)"

stub 0 '' 1 "$(online_error '    2: HTTP status client error (404 Not Found) for url (https://api.github.com/repos/x/y)')"
run
check 'a 404 still fails' "$([[ $RC -ne 0 && "$OUT" != *'::warning title=zizmor online'* ]] && echo yes)"

# An exit 1 that is not a GitHub API request error still fails.
stub 0 '' 1 $'fatal: no audit was performed\nfailed to load input .github/workflows/a.yml'
run
check 'an online-run error that is not a network error still fails' "$([[ $RC -eq 1 ]] && echo yes)"

# Findings from the online run fail with zizmor's own exit code.
stub 0 '' 14 "$finding"
run
check 'an online finding fails' "$([[ $RC -eq 14 && "$OUT" == *"$finding"* ]] && echo yes)"

# Findings from an offline audit fail, and the online run is not reached.
stub 13 "$finding" 1 "$(online_error '    2: HTTP status client error (403 Forbidden) for url (https://api.github.com/advisories)')"
run
check 'an offline finding fails, whatever the online run would do' \
  "$([[ $RC -eq 13 && "$(wc -l <"$scratch/calls")" -eq 1 ]] && echo yes)"

# An offline-run error fails too: only the online run can be downgraded.
stub 1 "$(online_error '    2: HTTP status client error (403 Forbidden) for url (https://api.github.com/advisories)')" 0 ''
run
check 'an error in the offline run fails, even one that reads like a network error' "$([[ $RC -eq 1 ]] && echo yes)"

stub 0 '' 0 ''
run
check 'a clean run passes with no warning' "$([[ $RC -eq 0 && "$OUT" != *'::warning'* ]] && echo yes)"

# The lint-repo step runs this script, not a bare zizmor.
step=$(grep -n -A8 -- '- name: Run zizmor$' "$ROOT/.github/workflows/pr-require-checks.yml")
check 'the lint-repo zizmor step runs scripts/run-zizmor.sh' \
  "$([[ "$step" == *'run: scripts/run-zizmor.sh'* ]] && echo yes)"

test_harness::report
