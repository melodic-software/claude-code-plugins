#!/usr/bin/env bash
# Tests for the core dispatcher: usage, binding resolution, capability gating, and
# list-frontier derivation — all against a fake adapter (no network, no gh).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCHER="$SCRIPT_DIR/work-item-tracker.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/lib.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Fake adapter: provider "fake" so the gh prerequisite gate stays out of the way.
FAKE_DIR="$TEST_TMPDIR/adapters/fake"
mkdir -p "$FAKE_DIR"
cat >"$FAKE_DIR/capabilities.json" <<'EOF'
{
  "schema_version": "1.0",
  "provider": "fake",
  "verbs": {
    "create-item": false,
    "get-item": true,
    "claim": true,
    "renew-lease": true,
    "reclaim": true,
    "link-blocks": true,
    "add-sub-item": true,
    "list-items": true,
    "list-sub-items": true,
    "capabilities": true
  }
}
EOF
cat >"$FAKE_DIR/capabilities.sh" <<EOF
#!/usr/bin/env bash
jq -c . "$FAKE_DIR/capabilities.json"
EOF
cat >"$FAKE_DIR/list-items.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\r\n' '{"schema_version":"1.0","items":[{"id":"fake:o/r#1","state":"open","assignees":[],"labels":[],"blocked_by_count":0},{"id":"fake:o/r#2","state":"open","assignees":[],"labels":["needs-human"],"blocked_by_count":0},{"id":"fake:o/r#3","state":"open","assignees":[],"labels":[],"blocked_by_count":1}]}'
EOF
cat >"$FAKE_DIR/list-sub-items.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"schema_version":"1.0","items":[]}'
EOF
cat >"$FAKE_DIR/get-item.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"schema_version":"1.0","id":"fake:o/r#1"}\n'
EOF

BINDING="$TEST_TMPDIR/binding.json"
printf '%s\n' '{"schema_version":"1.0","provider":"fake","config":{"lease_ttl_hours":24}}' >"$BINDING"

run_dispatcher() {
  WORK_ITEM_TRACKER_BINDING="$BINDING" WIT_ADAPTERS_DIR="$TEST_TMPDIR/adapters" \
    bash "$DISPATCHER" "$@"
}

# --- usage errors → exit 2 ---

run_dispatcher >/dev/null 2>&1
assert_eq "no verb → exit 2" "2" "$?"

run_dispatcher bogus-verb >/dev/null 2>&1
assert_eq "unknown verb → exit 2" "2" "$?"

# --- binding errors → exit 3 ---

(cd "$TEST_TMPDIR" && WORK_ITEM_TRACKER_BINDING="$TEST_TMPDIR/nope.json" bash "$DISPATCHER" capabilities >/dev/null 2>&1)
assert_eq "missing binding → exit 3" "3" "$?"

BAD="$TEST_TMPDIR/bad.json"
printf 'nope\n' >"$BAD"
(WORK_ITEM_TRACKER_BINDING="$BAD" bash "$DISPATCHER" capabilities >/dev/null 2>&1)
assert_eq "invalid binding → exit 3" "3" "$?"

# --- unknown provider → exit 3 ---

NOPROV="$TEST_TMPDIR/noprov.json"
printf '%s\n' '{"schema_version":"1.0","provider":"ghost","config":{"lease_ttl_hours":24}}' >"$NOPROV"
(WORK_ITEM_TRACKER_BINDING="$NOPROV" WIT_ADAPTERS_DIR="$TEST_TMPDIR/adapters" bash "$DISPATCHER" capabilities >/dev/null 2>&1)
assert_eq "missing adapter dir → exit 3" "3" "$?"

# --- contract-version handshake (CONTRACT.md "Contract-version handshake") ---
# Adapters resolve consumer-local first, so a shadowing/generated adapter can skew
# from the engine: major skew refuses (exit 3, direction-appropriate fix named);
# newer-minor proceeds with a stderr notice (tolerant reader).

# make_skew_adapter <provider> <schema_version-json> — fake adapter + binding for
# handshake cases; capabilities.sh present so a passing handshake can dispatch.
make_skew_adapter() {
  local provider="$1" version_json="$2"
  local dir="$TEST_TMPDIR/adapters/$provider"
  mkdir -p "$dir"
  printf '%s\n' "{$version_json\"provider\":\"$provider\",\"verbs\":{\"capabilities\":true}}" \
    >"$dir/capabilities.json"
  cat >"$dir/capabilities.sh" <<EOF
#!/usr/bin/env bash
jq -c . "$dir/capabilities.json"
EOF
  printf '%s\n' "{\"schema_version\":\"1.0\",\"provider\":\"$provider\",\"config\":{\"lease_ttl_hours\":24}}" \
    >"$TEST_TMPDIR/$provider-binding.json"
}

# run_skew <provider> <args…> — dispatcher against the skew provider's binding.
run_skew() {
  local provider="$1"
  shift
  WORK_ITEM_TRACKER_BINDING="$TEST_TMPDIR/$provider-binding.json" WIT_ADAPTERS_DIR="$TEST_TMPDIR/adapters" \
    bash "$DISPATCHER" "$@"
}

make_skew_adapter "noversion" ""
ERR="$(run_skew noversion capabilities 2>&1 >/dev/null)"
assert_eq "manifest without schema_version → exit 3" "3" "$?"
assert_contains "unversioned-manifest error names schema_version" "$ERR" "schema_version"

make_skew_adapter "newermajor" "\"schema_version\":\"2.0\","
ERR="$(run_skew newermajor capabilities 2>&1 >/dev/null)"
assert_eq "newer-major manifest → exit 3" "3" "$?"
assert_contains "newer-major error says update the plugin" "$ERR" "update the work-items plugin"

make_skew_adapter "oldermajor" "\"schema_version\":\"0.9\","
ERR="$(run_skew oldermajor capabilities 2>&1 >/dev/null)"
assert_eq "older-major manifest → exit 3" "3" "$?"
assert_contains "older-major error says regenerate the adapter" "$ERR" "update or regenerate the adapter"

# Leading-zero components must be read base-10, not octal: "08.0" is major 8,
# which must refuse — a bare (( )) would error on octal 08 and, with the errored
# condition read as false, wave the incompatible adapter through.
make_skew_adapter "leadingzero" "\"schema_version\":\"08.0\","
ERR="$(run_skew leadingzero capabilities 2>&1 >/dev/null)"
assert_eq "leading-zero major manifest → exit 3" "3" "$?"
assert_contains "leading-zero error says update the plugin" "$ERR" "update the work-items plugin"

make_skew_adapter "newerminor" "\"schema_version\":\"1.99\","
OUT="$(run_skew newerminor capabilities 2>/dev/null)"
assert_eq "newer-minor manifest proceeds → exit 0" "0" "$?"
assert_eq "newer-minor capabilities passthrough intact" "newerminor" "$(jq -r '.provider' <<<"$OUT")"
ERR="$(run_skew newerminor capabilities 2>&1 >/dev/null)"
assert_contains "newer-minor proceeds with a stderr notice" "$ERR" "newer than core"

# --- capability gate: declared-false verb → exit 6, clear stderr ---

ERR="$(run_dispatcher create-item --title x 2>&1 >/dev/null)"
RC_CAPTURE=$?
assert_eq "declared-false verb → exit 6" "6" "$RC_CAPTURE"
assert_contains "exit-6 stderr names verb + provider" "$ERR" "create-item"

# --- capabilities passthrough ---

OUT="$(run_dispatcher capabilities)"
assert_eq "capabilities → exit 0" "0" "$?"
assert_eq "capabilities schema_version" "1.0" "$(jq -r '.schema_version' <<<"$OUT")"

# --- list-frontier derivation over the fake adapter (CR-laden output) ---

OUT="$(run_dispatcher list-frontier)"
assert_eq "list-frontier → exit 0" "0" "$?"
assert_not_contains "frontier stdout CR-free" "$OUT" "$(printf '\r')"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "frontier keeps unblocked+unassigned" "fake:o/r#1,fake:o/r#2" "$IDS"

OUT="$(run_dispatcher list-frontier --autonomous)"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "autonomous frontier drops needs-human" "fake:o/r#1" "$IDS"

run_dispatcher list-frontier --bogus >/dev/null 2>&1
assert_eq "list-frontier bad flag → exit 2" "2" "$?"

# --parent + --repo is an invalid combination: --repo cannot re-target a
# container-scoped frontier, so it must be rejected loudly, not silently dropped.
ERR="$(run_dispatcher list-frontier --parent 'fake:o/r#9' --repo o/r 2>&1 >/dev/null)"
RC_CAPTURE=$?
assert_eq "list-frontier --parent + --repo → exit 2" "2" "$RC_CAPTURE"
assert_contains "--parent + --repo error names --repo/--parent" "$ERR" "--repo is not valid with --parent"

# --- two-root adapter resolution (CONTRACT.md "Adapter resolution") ---
# WIT_ADAPTERS_DIR is left UNSET here so the consumer-local-first / plugin-bundled
# fallback search runs. Consumer-local root is ${CLAUDE_PROJECT_DIR}/tools/
# work-item-tracker/adapters; the bundled root is the dispatcher's own adapters/.

# make_fake_adapter <dir> <provider-sentinel> — a capabilities-only adapter whose
# manifest echoes <provider-sentinel>, so the resolved dir can be attributed.
make_fake_adapter() {
  local dir="$1" sentinel="$2"
  mkdir -p "$dir"
  printf '%s\n' "{\"schema_version\":\"1.0\",\"provider\":\"$sentinel\",\"verbs\":{\"capabilities\":true}}" \
    >"$dir/capabilities.json"
  cat >"$dir/capabilities.sh" <<EOF
#!/usr/bin/env bash
jq -c . "$dir/capabilities.json"
EOF
}

PROJECT="$TEST_TMPDIR/project"
LOCAL_ADAPTERS="$PROJECT/tools/work-item-tracker/adapters"

# Unshipped provider "acme" works purely from a consumer-local adapter.
make_fake_adapter "$LOCAL_ADAPTERS/acme" "acme-local"
ACME_BINDING="$TEST_TMPDIR/acme.json"
printf '%s\n' '{"schema_version":"1.0","provider":"acme","config":{"lease_ttl_hours":24}}' >"$ACME_BINDING"
OUT="$(WORK_ITEM_TRACKER_BINDING="$ACME_BINDING" CLAUDE_PROJECT_DIR="$PROJECT" bash "$DISPATCHER" capabilities 2>/dev/null)"
assert_eq "consumer-local resolves an unshipped provider" "acme-local" "$(jq -r '.provider' <<<"$OUT")"

# A consumer-local dir of a BUNDLED provider name shadows the shipped adapter.
make_fake_adapter "$LOCAL_ADAPTERS/local-markdown" "local-markdown-shadow"
LM_BINDING="$TEST_TMPDIR/lm.json"
printf '%s\n' '{"schema_version":"1.0","provider":"local-markdown","config":{"lease_ttl_hours":24,"storage_dir":"/tmp/wit-x"}}' >"$LM_BINDING"
OUT="$(WORK_ITEM_TRACKER_BINDING="$LM_BINDING" CLAUDE_PROJECT_DIR="$PROJECT" bash "$DISPATCHER" capabilities 2>/dev/null)"
assert_eq "consumer-local shadows a bundled adapter" "local-markdown-shadow" "$(jq -r '.provider' <<<"$OUT")"

# With no consumer-local adapters dir, the plugin-bundled adapter is the fallback.
EMPTY_PROJECT="$TEST_TMPDIR/empty-project"
mkdir -p "$EMPTY_PROJECT"
OUT="$(WORK_ITEM_TRACKER_BINDING="$LM_BINDING" CLAUDE_PROJECT_DIR="$EMPTY_PROJECT" bash "$DISPATCHER" capabilities 2>/dev/null)"
assert_eq "plugin-bundled adapter is the fallback" "local-markdown" "$(jq -r '.provider' <<<"$OUT")"

# WIT_ADAPTERS_DIR still short-circuits both roots (single explicit override).
OUT="$(WORK_ITEM_TRACKER_BINDING="$BINDING" WIT_ADAPTERS_DIR="$TEST_TMPDIR/adapters" CLAUDE_PROJECT_DIR="$PROJECT" bash "$DISPATCHER" capabilities 2>/dev/null)"
assert_eq "WIT_ADAPTERS_DIR override wins over consumer-local" "fake" "$(jq -r '.provider' <<<"$OUT")"

# --- F3.8: consumer-local resolution in a bare shell (no CLAUDE_PROJECT_DIR) ---
# The consumer-local root anchors at the git toplevel when CLAUDE_PROJECT_DIR is
# unset — the same anchor the binding read uses — so a bare shell that finds the
# binding also finds consumer-local adapters instead of silently skipping them (#2941).
git init -q "$PROJECT"
mkdir -p "$PROJECT/deep"
OUT="$(cd "$PROJECT/deep" && env -u CLAUDE_PROJECT_DIR WORK_ITEM_TRACKER_BINDING="$ACME_BINDING" bash "$DISPATCHER" capabilities 2>/dev/null)"
assert_eq "bare shell resolves consumer-local via git toplevel" "acme-local" "$(jq -r '.provider' <<<"$OUT")"

[[ $FAILED -eq 0 ]] || exit 1
