#!/usr/bin/env bash
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
standards="$scratch/standards"
mkdir -p "$standards/.github"
printf 'rules: checkout\n' >"$standards/.github/zizmor.yml"

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
  OUT=$(PATH="$scratch/bin:$PATH" STANDARDS_DIR="$standards" bash "$SCRIPT" 2>&1) && RC=0 || RC=$?
}

check() {
  if [[ "$2" == yes ]]; then ok "$1"; else bad "$1" "rc=$RC out=$OUT"; fi
}

finding='::error file=.github/workflows/a.yml,line=7,title=unpinned-uses::a.yml:7: unpinned action reference'

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

stub 0 '' 1 "$(online_error '    2: HTTP status client error (401 Unauthorized) for url (https://api.github.com/advisories)')"
run
check 'a 401 still fails' "$([[ $RC -ne 0 && "$OUT" != *'::warning title=zizmor online'* ]] && echo yes)"

stub 0 '' 1 "$(online_error '    2: HTTP status client error (404 Not Found) for url (https://api.github.com/repos/x/y)')"
run
check 'a 404 still fails' "$([[ $RC -ne 0 && "$OUT" != *'::warning title=zizmor online'* ]] && echo yes)"

stub 0 '' 1 $'fatal: no audit was performed\nfailed to load input .github/workflows/a.yml'
run
check 'an online-run error that is not a network error still fails' "$([[ $RC -eq 1 ]] && echo yes)"

stub 0 '' 14 "$finding"
run
check 'an online finding fails' "$([[ $RC -eq 14 && "$OUT" == *"$finding"* ]] && echo yes)"

stub 13 "$finding" 1 "$(online_error '    2: HTTP status client error (403 Forbidden) for url (https://api.github.com/advisories)')"
run
check 'an offline finding fails, whatever the online run would do' \
  "$([[ $RC -eq 13 && "$(wc -l <"$scratch/calls")" -eq 1 ]] && echo yes)"

stub 1 "$(online_error '    2: HTTP status client error (403 Forbidden) for url (https://api.github.com/advisories)')" 0 ''
run
check 'an error in the offline run fails, even one that reads like a network error' "$([[ $RC -eq 1 ]] && echo yes)"

stub 0 '' 0 ''
run
check 'a clean run passes with no warning' "$([[ $RC -eq 0 && "$OUT" != *'::warning'* ]] && echo yes)"

repo=""
fixture_tree::build repo --git --label run-zizmor-repo
mkdir -p "$repo/.github"
printf 'rules: base\n' >"$repo/.github/zizmor.yml"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m base
base_sha=$(git_test_config "$repo" rev-parse HEAD)
printf 'rules: head\n' >"$repo/.github/zizmor.yml"
printf 'rules: root\n' >"$repo/zizmor.yaml"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m head

bare=""
fixture_tree::build bare --git --label run-zizmor-bare
mkdir -p "$bare/docs/conventions"
printf 'standards_repository: example-org/standards\n' >"$bare/docs/conventions/source-control.yaml"
git_test_config "$bare" add -A
git_test_config "$bare" commit -q -m base
bare_sha=$(git_test_config "$bare" rev-parse HEAD)
mkdir -p "$bare/.github"
printf 'rules: head\n' >"$bare/.github/zizmor.yml"
git_test_config "$bare" add -A
git_test_config "$bare" commit -q -m head

cat >"$scratch/bin/zizmor" <<EOS
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$scratch/calls"
for arg in "\$@"; do
  [[ "\$arg" == --config=* ]] && cat "\${arg#--config=}" >>"$scratch/configs"
done
exit 0
EOS
cat >"$scratch/bin/gh" <<EOS
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$scratch/gh.calls"
cat "$scratch/gh.out" || exit 1
EOS
chmod +x "$scratch/bin/zizmor" "$scratch/bin/gh"

run_in() {
  : >"$scratch/calls"
  : >"$scratch/configs"
  : >"$scratch/gh.calls"
  OUT=$(cd "$1" && PATH="$scratch/bin:$PATH" BASE_SHA="$2" STANDARDS_DIR="${3:-}" bash "$SCRIPT" 2>&1) && RC=0 || RC=$?
}

run_in "$repo" "$base_sha"
check "a pull request is audited under the base commit's config, not the head's" \
  "$([[ $RC -eq 0 && "$(cat "$scratch/configs")" == $'rules: base\nrules: base' && ! -s "$scratch/gh.calls" ]] && echo yes)"
check 'the offline run and the online run both pass that config' \
  "$([[ "$(grep -c -- '--config=' "$scratch/calls")" -eq 2 ]] && echo yes)"

printf 'rules: standards\n' >"$scratch/gh.out"
run_in "$bare" "$bare_sha"
check "a base with no config falls back to the config of its standards_repository, whatever the head adds" \
  "$([[ $RC -eq 0 && "$(cat "$scratch/configs")" == $'rules: standards\nrules: standards' && "$(head -n 1 "$scratch/gh.calls")" == *repos/example-org/standards/contents/.github/zizmor.yml ]] && echo yes)"

nokey=""
fixture_tree::build nokey --git --label run-zizmor-nokey
printf 'readme\n' >"$nokey/README.md"
git_test_config "$nokey" add -A
git_test_config "$nokey" commit -q -m base
nokey_sha=$(git_test_config "$nokey" rev-parse HEAD)
mkdir -p "$nokey/docs/conventions"
printf 'standards_repository: head-org/standards\n' >"$nokey/docs/conventions/source-control.yaml"
git_test_config "$nokey" add -A
git_test_config "$nokey" commit -q -m head
run_in "$nokey" "$nokey_sha"
check "a base with no config and no standards_repository fails closed, whatever the head adds" \
  "$([[ $RC -eq 2 && ! -s "$scratch/calls" && ! -s "$scratch/gh.calls" ]] && echo yes)"

rm "$scratch/gh.out"
run_in "$bare" "$bare_sha"
check "an unreadable standards config fails closed before zizmor runs" \
  "$([[ $RC -eq 2 && ! -s "$scratch/calls" ]] && echo yes)"

run_in "$bare" "$bare_sha" "$standards"
check "a base with no config reads the run's standards checkout, with no API read" \
  "$([[ $RC -eq 0 && "$(cat "$scratch/configs")" == $'rules: checkout\nrules: checkout' && ! -s "$scratch/gh.calls" ]] && echo yes)"
run_in "$repo" "$base_sha" "$standards"
check "the base commit's own config still wins over the standards checkout" \
  "$([[ $RC -eq 0 && "$(cat "$scratch/configs")" == $'rules: base\nrules: base' ]] && echo yes)"
run_in "$bare" "$bare_sha" "$scratch/no-standards"
check "a standards checkout without the config fails closed before zizmor runs" \
  "$([[ $RC -eq 2 && ! -s "$scratch/calls" ]] && echo yes)"

run_in "$repo" "$(printf '0%.0s' {1..40})"
check 'a base commit missing from the checkout fails closed' \
  "$([[ $RC -eq 2 && ! -s "$scratch/calls" ]] && echo yes)"

run_in "$repo" ""
check 'outside a pull request zizmor gets no --config and discovers its own' \
  "$([[ $RC -eq 0 && "$(grep -c -- '--config' "$scratch/calls")" -eq 0 && ! -s "$scratch/gh.calls" ]] && echo yes)"

none=""
fixture_tree::build none --label run-zizmor-none
run_in "$none" "" "$standards"
check "outside a pull request a checkout with no config falls back to standards' config" \
  "$([[ $RC -eq 0 && "$(cat "$scratch/configs")" == $'rules: checkout\nrules: checkout' && ! -s "$scratch/gh.calls" ]] && echo yes)"

step=$(grep -n -A9 -- '- name: Run zizmor$' "$ROOT/.github/workflows/pr-require-checks.yml")
check 'the lint-repo zizmor step runs scripts/run-zizmor.sh' \
  "$([[ "$step" == *'run: scripts/run-zizmor.sh'* ]] && echo yes)"
check "the lint-repo zizmor step hands it the pull request's base commit" \
  "$([[ "$step" == *'BASE_SHA: '*'{{ github.event.pull_request.base.sha }}'* ]] && echo yes)"
check "the lint-repo zizmor step hands it the run's standards checkout" \
  "$([[ "$step" == *'STANDARDS_DIR: '*'{{ steps.standards.outputs.path }}'* ]] && echo yes)"

test_harness::report
