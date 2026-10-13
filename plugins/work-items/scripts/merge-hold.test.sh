#!/usr/bin/env bash
# Offline tests for merge-hold.sh against a gh stub that applies the script's own --jq program
# to a fixture comments payload and answers the permission endpoint from per-login fixture
# files. Expected verdicts come from the rule: a comment holds the merge only when it contains
# `Hold: a human merges this` and its author has `admin` or `write`; any failed read refuses.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/merge-hold.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

check() { # <name> <expected-rc> <expected-stdout> <actual-rc> <actual-stdout>
  if [[ "$2" == "$4" && "$3" == "$5" ]]; then
    printf 'PASS: %s\n' "$1"
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL: %s\n  expected rc=%s out=[%s], got rc=%s out=[%s]\n' "$1" "$2" "$3" "$4" "$5" >&2
  fi
}

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not installed" >&2
  exit 0
}

mkdir -p "$TMP/bin" "$TMP/perms"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
path="" prog=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --jq) prog="$2"; shift 2 ;;
  api | --paginate) shift ;;
  *) path="$1"; shift ;;
  esac
done
case "$path" in
*/comments*)
  [[ -z "${GH_STUB_COMMENTS_ERR:-}" ]] || { echo "gh: HTTP 502" >&2; exit 1; }
  jq -r "$prog" <<<"$GH_STUB_COMMENTS"
  ;;
*/collaborators/*/permission)
  login="${path#*/collaborators/}"
  login="${login%/permission}"
  f="$GH_STUB_PERM_DIR/$login.json"
  [[ -f "$f" ]] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
  jq -r "$prog" "$f"
  ;;
*) exit 90 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
printf '{"permission":"admin","role_name":"admin"}' >"$TMP/perms/owner.json"
printf '{"permission":"write","role_name":"maintain"}' >"$TMP/perms/maint.json"
printf '{"permission":"read","role_name":"triage"}' >"$TMP/perms/triager.json"
printf '{"permission":"read","role_name":"read"}' >"$TMP/perms/stranger.json"

OWNER_SAYS="Owner ratified this: put 'Hold: a human merges this' in the PR body."
comment() { jq -nc --arg u "$1" --arg b "$2" '{user: {login: $u}, body: $b}'; }

run() { # <comments-json-array> [env...]
  local out rc
  out="$(env PATH="$TMP/bin:$PATH" GH_STUB_PERM_DIR="$TMP/perms" GH_STUB_COMMENTS="$1" "${@:2}" \
    bash "$S" --repo o/r --issue 7 2>/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$out"
}
verdict() { # <name> <expected-rc> <expected-out> <comments> [env...]
  local r
  r="$(run "${@:4}")"
  check "$1" "$2" "$3" "${r%%|*}" "${r#*|}"
}

HOLD="Hold: a human merges this"
verdict "admin comment quoting the line holds" 0 "$HOLD" "[$(comment owner "$OWNER_SAYS")]"
verdict "maintain (write) comment holds" 0 "$HOLD" "[$(comment maint "$HOLD")]"
verdict "triage commenter does not hold" 1 "" "[$(comment triager "$HOLD")]"
verdict "read-only commenter does not hold" 1 "" "[$(comment stranger "$OWNER_SAYS")]"
verdict "untrusted line plus trusted line holds" 0 "$HOLD" \
  "[$(comment stranger "$HOLD"),$(comment owner "$OWNER_SAYS")]"
verdict "owner comment without the line does not hold" 1 "" "[$(comment owner "looks good")]"
verdict "no comments does not hold" 1 "" "[]"
verdict "different case is not the line" 1 "" "[$(comment owner "hold: a human merges this")]"
verdict "comment read failure refuses" 11 "" "[]" GH_STUB_COMMENTS_ERR=1
verdict "permission read failure refuses" 11 "" "[$(comment ghost "$HOLD")]"
verdict "malformed login is ignored" 1 "" "[$(comment 'a;b' "$HOLD")]"

for args in "" "--repo o/r" "--issue 7" "--repo bad --issue 7" "--repo o/r --issue 0" "--repo o/r --issue 7 --x 1"; do
  # shellcheck disable=SC2086 # word splitting is the point: each string is an argument list
  bash "$S" $args >/dev/null 2>&1
  check "usage error: [$args]" 2 "" "$?" ""
done

((FAILED == 0)) || {
  echo "$FAILED failed" >&2
  exit 1
}
echo "all passed"
