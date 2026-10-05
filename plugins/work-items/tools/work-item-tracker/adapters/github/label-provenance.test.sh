#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline: label-provenance against a gh stub that applies the script's own --jq program to a
# raw timeline payload and answers the permission endpoint from per-login fixture files shaped
# like GitHub's response ({permission, role_name}). Expected verdicts come from the admission
# rule: a labeler is trusted only with `admin` or `write` permission (maintain reads as write,
# triage as read), the most recent application of a label decides, and any failed or empty read
# refuses.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/label-provenance.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"                                            # no id
assert_usage_error "$S" "github:o/r#1"                             # no --label
assert_usage_error "$S" "github:o/r#1" --label ""                  # empty label
assert_usage_error "$S" "github:o/r#1" --label a --nope            # unknown argument
assert_usage_error "$S" "local-markdown:o/r#1" --label agent-ready # foreign provider
assert_usage_error "$S" "not-an-id" --label agent-ready            # malformed id

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
PERMS="$TMP_ROOT/perms"
LOG="$TMP_ROOT/gh.log"
mkdir -p "$STUB" "$PERMS"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
if [[ "$1" == "--version" ]]; then
  printf 'gh version 2.97.0 (test)\n'
  exit 0
fi
path="" prog=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --jq) prog="$2"; shift 2 ;;
  api | --paginate) shift ;;
  *) path="$1"; shift ;;
  esac
done
case "$path" in
*/timeline*)
  if [[ -n "${GH_STUB_TIMELINE_ERR:-}" ]]; then
    printf '%s\n' "$GH_STUB_TIMELINE_ERR" >&2
    exit 1
  fi
  jq -c "$prog" <<<"$GH_STUB_TIMELINE"
  ;;
*/collaborators/*/permission)
  login="${path#*/collaborators/}"
  login="${login%/permission}"
  if [[ -f "$GH_STUB_PERM_DIR/$login.json" ]]; then
    cat "$GH_STUB_PERM_DIR/$login.json"
  else
    printf 'gh: Not Found (HTTP 404)\n' >&2
    exit 1
  fi
  ;;
*)
  printf 'gh-stub: unhandled %s\n' "$path" >&2
  exit 90
  ;;
esac
EOF
chmod +x "$STUB/gh"

printf '%s\n' '{"permission":"admin","role_name":"admin"}' >"$PERMS/owner-a.json"
printf '%s\n' '{"permission":"write","role_name":"maintain"}' >"$PERMS/maint-b.json"
printf '%s\n' '{"permission":"write","role_name":"write"}' >"$PERMS/dev-c.json"
printf '%s\n' '{"permission":"read","role_name":"triage"}' >"$PERMS/triager-d.json"
printf '%s\n' '{"permission":"read","role_name":"read"}' >"$PERMS/reader-e.json"
printf '%s\n' '{"role_name":"custom"}' >"$PERMS/blank-f.json"

# ev <label> <actor> <created_at>: one timeline `labeled` event in GitHub's field shape.
ev() {
  jq -nc --arg l "$1" --arg a "$2" --arg t "$3" \
    '{event: "labeled", label: {name: $l, color: "ededed"}, actor: {login: $a}, created_at: $t}'
}

OUT="" RC=0
# run <timeline-json> <args...>
run() {
  local timeline="$1"
  shift
  : >"$LOG"
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" GH_STUB_PERM_DIR="$PERMS" \
    GH_STUB_TIMELINE="$timeline" bash "$S" "$@" 2>/dev/null)"
  RC=$?
}

ID="github:o/r#7"
AR="agent-ready"
C1="work-class: read-only"

# --- triage-role labeler on the work-class label: refused ---
TL="[$(ev "$AR" maint-b 2026-10-01T10:00:00Z),$(ev "$C1" triager-d 2026-10-01T10:05:00Z)]"
run "$TL" "$ID" --label "$AR" --label "$C1"
assert_eq "triage-labelled C1: exit 0 (the read succeeded)" "0" "$RC"
assert_eq "triage-labelled C1: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"
assert_eq "triage-labelled C1: work-class row names the actor" "triager-d" \
  "$(jq -r --arg l "$C1" '.labels[] | select(.label == $l) | .actor' <<<"$OUT")"
assert_eq "triage-labelled C1: role reported as triage" "triage" \
  "$(jq -r --arg l "$C1" '.labels[] | select(.label == $l) | .role' <<<"$OUT")"
assert_eq "triage-labelled C1: work-class row untrusted" "false" \
  "$(jq -r --arg l "$C1" '.labels[] | select(.label == $l) | .trusted' <<<"$OUT")"
assert_eq "triage-labelled C1: maintain labeler of agent-ready still trusted" "true" \
  "$(jq -r --arg l "$AR" '.labels[] | select(.label == $l) | .trusted' <<<"$OUT")"
assert_eq "result carries schema_version and the id" "1.0 $ID" "$(jq -r '"\(.schema_version) \(.id)"' <<<"$OUT")"

# --- triage-role labeler on agent-ready: refused ---
TL="[$(ev "$AR" triager-d 2026-10-01T10:00:00Z),$(ev "$C1" dev-c 2026-10-01T10:05:00Z)]"
run "$TL" "$ID" --label "$AR" --label "$C1"
assert_eq "triage-applied agent-ready: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"

# --- read-role labeler: refused ---
TL="[$(ev "$AR" reader-e 2026-10-01T10:00:00Z),$(ev "$C1" dev-c 2026-10-01T10:05:00Z)]"
run "$TL" "$ID" --label "$AR" --label "$C1"
assert_eq "read-role labeler: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"

# --- write, maintain and admin labelers: admitted ---
TL="[$(ev "$AR" dev-c 2026-10-01T10:00:00Z),$(ev "$C1" dev-c 2026-10-01T10:05:00Z)]"
run "$TL" "$ID" --label "$AR" --label "$C1"
assert_eq "write-labelled item: exit 0" "0" "$RC"
assert_eq "write-labelled item: admitted" "true" "$(jq -r '.admitted' <<<"$OUT")"
assert_eq "write-labelled item: no reasons" "null null" "$(jq -r '[.labels[].reason] | map(tostring) | join(" ")' <<<"$OUT")"
TL="[$(ev "$AR" owner-a 2026-10-01T10:00:00Z),$(ev "$C1" maint-b 2026-10-01T10:05:00Z)]"
run "$TL" "$ID" --label "$AR" --label "$C1"
assert_eq "admin + maintain labelers: admitted" "true" "$(jq -r '.admitted' <<<"$OUT")"

# --- the most recent application decides, by created_at, not array position ---
TL="[$(ev "$C1" triager-d 2026-10-02T09:00:00Z),$(ev "$C1" dev-c 2026-10-01T09:00:00Z),$(ev "$AR" dev-c 2026-10-01T08:00:00Z)]"
run "$TL" "$ID" --label "$AR" --label "$C1"
assert_eq "later triage re-application overrides an earlier write one" "false" "$(jq -r '.admitted' <<<"$OUT")"
TL="[$(ev "$C1" dev-c 2026-10-02T09:00:00Z),$(ev "$C1" triager-d 2026-10-01T09:00:00Z),$(ev "$AR" dev-c 2026-10-01T08:00:00Z)]"
run "$TL" "$ID" --label "$AR" --label "$C1"
assert_eq "later write re-application overrides an earlier triage one" "true" "$(jq -r '.admitted' <<<"$OUT")"

# --- failed timeline read: no verdict, non-zero exit ---
ERRFILE="$(mktemp "$TMP_ROOT/e.XXXXXX")"
OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" GH_STUB_PERM_DIR="$PERMS" GH_STUB_TIMELINE="[]" \
  GH_STUB_TIMELINE_ERR="dial tcp: connection refused" bash "$S" "$ID" --label "$AR" 2>"$ERRFILE")"
RC=$?
assert_eq "failed timeline read: exit 8 (provider unavailable)" "8" "$RC"
assert_eq "failed timeline read: no JSON on stdout" "" "$OUT"
assert_contains "failed timeline read: stderr carries the cause" "$(<"$ERRFILE")" "connection refused"
rm -f "$ERRFILE"

# --- empty timeline and a label with no labeled event: refused with a reason ---
run "[]" "$ID" --label "$AR"
assert_eq "empty timeline: exit 0" "0" "$RC"
assert_eq "empty timeline: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"
assert_eq "empty timeline: reason names the missing event" "no labeled event for this label" \
  "$(jq -r '.labels[0].reason' <<<"$OUT")"
TL="[$(ev "$AR" dev-c 2026-10-01T10:00:00Z)]"
run "$TL" "$ID" --label "$AR" --label "$C1"
assert_eq "label with no labeled event: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"

# --- failed or empty permission read: refused with a reason ---
TL="[$(ev "$AR" "lane-app[bot]" 2026-10-01T10:00:00Z)]"
run "$TL" "$ID" --label "$AR"
assert_eq "permission 404: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"
assert_contains "permission 404: reason carries the error" "$(jq -r '.labels[0].reason' <<<"$OUT")" "permission read failed"
TL="[$(ev "$AR" blank-f 2026-10-01T10:00:00Z)]"
run "$TL" "$ID" --label "$AR"
assert_eq "permission field absent: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"

# --- untrusted strings stay data ---
# An actor login that is not a GitHub login never reaches the API path or a shell.
MARK="$TMP_ROOT/pwned"
TL="[$(ev "$AR" "x\$(touch $MARK)" 2026-10-01T10:00:00Z)]"
run "$TL" "$ID" --label "$AR"
assert_eq "unsafe actor login: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"
assert_eq "unsafe actor login: no permission call made" "0" "$(grep -c 'collaborators' "$LOG")"
assert_eq "unsafe actor login: nothing executed" "absent" "$([[ -e "$MARK" ]] && echo present || echo absent)"
# A label name carrying jq and shell syntax matches only itself.
# shellcheck disable=SC2016  # the $( ) is the payload under test and must stay literal
ODD='x" or true | "$(touch '"$MARK"')'
TL="[$(ev "$AR" triager-d 2026-10-01T10:00:00Z),$(ev "$ODD" dev-c 2026-10-01T10:05:00Z)]"
run "$TL" "$ID" --label "$ODD"
assert_eq "odd label name matched exactly: trusted" "true" "$(jq -r '.admitted' <<<"$OUT")"
assert_eq "odd label name echoed verbatim" "$ODD" "$(jq -r '.labels[0].label' <<<"$OUT")"
run "$TL" "$ID" --label "$AR" --label "$ODD"
assert_eq "odd label beside a triage agent-ready: not admitted" "false" "$(jq -r '.admitted' <<<"$OUT")"
assert_eq "odd label name: nothing executed" "absent" "$([[ -e "$MARK" ]] && echo present || echo absent)"
# Same refusal under bash 5.1 compatibility.
TL="[$(ev "$AR" maint-b 2026-10-01T10:00:00Z),$(ev "$C1" triager-d 2026-10-01T10:05:00Z)]"
OUT="$(BASH_COMPAT=51 PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" GH_STUB_PERM_DIR="$PERMS" \
  GH_STUB_TIMELINE="$TL" bash "$S" "$ID" --label "$AR" --label "$C1" 2>/dev/null)"
assert_eq "BASH_COMPAT=51: triage-labelled C1 still refused" "false" "$(jq -r '.admitted' <<<"$OUT")"

[[ $FAILED -eq 0 ]] || exit 1
