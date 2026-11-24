#!/usr/bin/env bash
# Tests for target-repo.sh. Each case builds a throwaway git repo with a given
# set of remotes and runs the resolver against a stub gh whose
# `repo set-default --view` and `api` output come from the STUB_* variables.
# The stub's `api repos/<repo>` builds the repository's JSON and runs the
# caller's --jq filter over it with jq. STUB_PARENTS lists `<repo>=<parent>`
# pairs, space-separated; any other repository has no parent. STUB_NOPUSH lists
# repositories the caller cannot push to. STUB_API_FAIL makes the call fail with
# that message.
# Non-zero exit on any FAIL.

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GH_REPO GITHUB_ACTIONS
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="${SCRIPT_DIR}/target-repo.sh"

PASS=0
FAIL=0
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/bin"
cat >"$WORKDIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
"repo set-default")
  [[ -n "${STUB_VIEW_ERR:-}" ]] && printf '%s\n' "$STUB_VIEW_ERR" >&2
  [[ -n "${STUB_VIEW_OUT:-}" ]] && printf '%s\n' "$STUB_VIEW_OUT"
  exit "${STUB_VIEW_RC:-0}"
  ;;
"api repos/{owner}/{repo}") printf '%s\n' "${STUB_API_OUT:-}" ;;
"api repos/"*)
  if [[ -n "${STUB_API_FAIL:-}" ]]; then
    printf '%s\n' "$STUB_API_FAIL" >&2
    exit 1
  fi
  repo=${2#repos/} parent=null push=true
  for pair in ${STUB_PARENTS:-}; do
    [[ "${pair%%=*}" == "$repo" ]] && parent="{\"full_name\":\"${pair#*=}\"}"
  done
  [[ " ${STUB_NOPUSH:-} " == *" $repo "* ]] && push=false
  [[ "$3" == --jq ]] || { echo "stub gh: expected --jq" >&2; exit 99; }
  perms=",\"permissions\":{\"push\":$push}"
  [[ " ${STUB_NOPERMS:-} " == *" $repo "* ]] && perms=
  printf '{"full_name":"%s","parent":%s%s}\n' "$repo" "$parent" "$perms" | jq -r "$4"
  ;;
*) echo "stub gh: unexpected call: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$WORKDIR/bin/gh"

NO_DEFAULT='No default remote repository has been set. To learn more about the default repository, run: gh repo set-default --help'

make_repo() {
  local repo="$WORKDIR/$1"
  shift
  git init -q "$repo"
  for pair in "$@"; do
    git -C "$repo" remote add "${pair%%=*}" "${pair#*=}"
  done
  echo "$repo"
}

check() {
  local desc="$1" repo="$2" want_out="$3" want_rc="$4" want_err="$5"
  shift 5
  local out rc err extra=()
  [[ -n "${WRITE_MODE:-}" ]] && extra=(--write)
  err=$(env PATH="$WORKDIR/bin:$PATH" "$@" bash "$RESOLVER" --dir "$repo" "${extra[@]}" 2>&1 >"$WORKDIR/out")
  rc=$?
  out=$(<"$WORKDIR/out")
  if [[ "$out" == "$want_out" && $rc -eq $want_rc && "$err" == *"$want_err"* ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "       got     out='$out' exit=$rc err='$err'"
    echo "       wanted  out='$want_out' exit=$want_rc err contains '$want_err'"
    FAIL=$((FAIL + 1))
  fi
}

FORK=$(make_repo fork origin=https://github.com/me/tool.git upstream=git@github.com:acme/tool.git)
SINGLE=$(make_repo single origin=https://github.com/acme/tool)
SAME=$(make_repo same origin=git@github.com:acme/tool.git github=https://github.com/acme/tool/)
GHE=$(make_repo ghe origin=https://ghe.example.com/acme/tool.git)
UNRELATED=$(make_repo unrelated origin=https://github.com/acme/tool.git other=https://github.com/beta/lib.git)
NO_ORIGIN=$(make_repo no-origin mine=https://github.com/me/tool.git upstream=https://github.com/acme/tool.git)

check "a stock fork clone with upstream as the gh default pins the fork origin names" "$FORK" \
  "me/tool" 0 "target repository: me/tool" STUB_VIEW_OUT=acme/tool STUB_PARENTS=me/tool=acme/tool
check "no default with a fork and its upstream pins the fork" "$FORK" \
  "me/tool" 0 "target repository: me/tool" "STUB_VIEW_ERR=$NO_DEFAULT" STUB_PARENTS=me/tool=acme/tool
check "a fork under a remote other than origin is still found" "$NO_ORIGIN" \
  "me/tool" 0 "target repository: me/tool" "STUB_VIEW_ERR=$NO_DEFAULT" STUB_PARENTS=me/tool=acme/tool
check "a fork the caller cannot push to loses to the recorded default" "$FORK" \
  "acme/tool" 0 "target repository: acme/tool" STUB_VIEW_OUT=acme/tool STUB_PARENTS=me/tool=acme/tool STUB_NOPUSH=me/tool
check "a failed repository read stops and names the repository" "$FORK" \
  "" 1 "could not read repository me/tool" STUB_VIEW_OUT=acme/tool "STUB_API_FAIL=HTTP 503: Service Unavailable"
check "two unrelated repositories with no default are refused with the set-default fix" "$UNRELATED" \
  "" 1 "gh repo set-default <owner>/<repo>" "STUB_VIEW_ERR=$NO_DEFAULT"
check "two unrelated repositories follow a recorded default" "$UNRELATED" \
  "beta/lib" 0 "target repository: beta/lib" STUB_VIEW_OUT=beta/lib
check "an explicit GH_REPO wins over the recorded default" "$FORK" \
  "elsewhere/other" 0 "target repository: elsewhere/other" GH_REPO=elsewhere/other STUB_VIEW_OUT=me/tool
check "a GH_REPO with a host prefix drops the host" "$SINGLE" \
  "elsewhere/other" 0 "target repository: elsewhere/other" GH_REPO=github.com/elsewhere/other
check "no default and one GitHub repository resolves to it" "$SINGLE" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT"
check "two remotes naming the same repository count as one" "$SAME" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT"
check "no github.com remote falls back to gh's own resolution" "$GHE" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT" STUB_API_OUT=acme/tool
check "an unrecognized --view message is not read as no default" "$SINGLE" \
  "" 1 "unknown flag: --view" "STUB_VIEW_ERR=unknown flag: --view"
check "a failing gh is reported, not resolved" "$SINGLE" \
  "" 1 "HTTP 401" "STUB_VIEW_ERR=HTTP 401" STUB_VIEW_RC=1
checkw() { WRITE_MODE=1 check "$@"; }
checkw "a write to the one remote the caller cannot push to is refused" "$SINGLE" \
  "" 1 "you cannot push to acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT" STUB_NOPUSH=acme/tool
checkw "a write to a GH_REPO the caller cannot push to is refused" "$SINGLE" \
  "" 1 "you cannot push to elsewhere/other" GH_REPO=elsewhere/other STUB_NOPUSH=elsewhere/other
checkw "a write to a recorded default the caller cannot push to is refused" "$UNRELATED" \
  "" 1 "you cannot push to beta/lib" STUB_VIEW_OUT=beta/lib STUB_NOPUSH=beta/lib
checkw "a write to a pushable repository resolves" "$SINGLE" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT"
checkw "a write passes when GitHub returns no permissions field" "$SINGLE" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT" STUB_NOPERMS=acme/tool
checkw "a write stops when the permission read fails" "$SINGLE" \
  "" 1 "could not read repository acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT" "STUB_API_FAIL=HTTP 503"
checkw "a write inside GitHub Actions skips the push check" "$SINGLE" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT" STUB_NOPUSH=acme/tool GITHUB_ACTIONS=true
check "a read of a repository the caller cannot push to still resolves" "$SINGLE" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT" STUB_NOPUSH=acme/tool
usage_err=$(bash "$RESOLVER" --bogus 2>&1)
if [[ $? -eq 2 && "$usage_err" == *"usage: target-repo.sh"* ]]; then
  echo "PASS: an unknown argument is a usage error"
  PASS=$((PASS + 1))
else
  echo "FAIL: an unknown argument is a usage error (got '$usage_err')"
  FAIL=$((FAIL + 1))
fi

echo "target-repo.sh: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
