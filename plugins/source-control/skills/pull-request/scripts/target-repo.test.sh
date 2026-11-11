#!/usr/bin/env bash
# Tests for target-repo.sh. Each case builds a throwaway git repo with a given
# set of remotes and runs the resolver against a stub gh whose
# `repo set-default --view` and `api` output come from the STUB_* variables.
# Non-zero exit on any FAIL.

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

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

# check <desc> <repo> <expected stdout> <expected exit> <stderr substring> [VAR=value...]
check() {
  local desc="$1" repo="$2" want_out="$3" want_rc="$4" want_err="$5"
  shift 5
  local out rc err
  err=$(env PATH="$WORKDIR/bin:$PATH" "$@" bash "$RESOLVER" --dir "$repo" 2>&1 >"$WORKDIR/out")
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

check "a recorded default wins even with two GitHub repositories" "$FORK" \
  "me/tool" 0 "target repository: me/tool" STUB_VIEW_OUT=me/tool
check "no default and one GitHub repository resolves to it" "$SINGLE" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT"
check "two remotes naming the same repository count as one" "$SAME" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT"
check "no default with a fork and its upstream is refused with the set-default fix" "$FORK" \
  "" 1 "gh repo set-default <owner>/<repo>" "STUB_VIEW_ERR=$NO_DEFAULT"
check "no github.com remote falls back to gh's own resolution" "$GHE" \
  "acme/tool" 0 "target repository: acme/tool" "STUB_VIEW_ERR=$NO_DEFAULT" STUB_API_OUT=acme/tool
check "an unrecognized --view message is not read as no default" "$SINGLE" \
  "" 1 "unknown flag: --view" "STUB_VIEW_ERR=unknown flag: --view"
check "a failing gh is reported, not resolved" "$SINGLE" \
  "" 1 "HTTP 401" "STUB_VIEW_ERR=HTTP 401" STUB_VIEW_RC=1
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
