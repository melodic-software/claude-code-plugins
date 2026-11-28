#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-version.sh
source "$SCRIPT_DIR/gh-version.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

STUB_BIN="$(mktemp -d)"
NOGH="$(mktemp -d)"
trap 'rm -rf "$STUB_BIN" "$NOGH"' EXIT

cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh version %s (test)\n' "${GH_STUB_VERSION:?}"
EOF
chmod +x "$STUB_BIN/gh"

run_at() {
  local ver="$1"
  GH_STUB_VERSION="$ver" PATH="$STUB_BIN:$PATH" wit_gh_has_native_surface
  printf '%s\n' "$?"
}

assert_eq "2.45 (observed cloud gh) is below the floor" "1" "$(run_at 2.45.0)"
assert_eq "2.93 is below the floor" "1" "$(run_at 2.93.0)"
assert_eq "2.94 meets the floor" "0" "$(run_at 2.94.0)"
assert_eq "2.95 is above the floor" "0" "$(run_at 2.95.1)"
assert_eq "3.0 (next major) meets the floor" "0" "$(run_at 3.0.0)"

assert_eq "raw version from 2.45 stub" "2.45" \
  "$(GH_STUB_VERSION=2.45.0 PATH="$STUB_BIN:$PATH" wit_gh_version_raw)"
assert_eq "raw version from 2.94 stub" "2.94" \
  "$(GH_STUB_VERSION=2.94.0 PATH="$STUB_BIN:$PATH" wit_gh_version_raw)"

UNPARSABLE="$STUB_BIN/unparsable"
mkdir -p "$UNPARSABLE"
cat >"$UNPARSABLE/gh" <<'EOF'
#!/usr/bin/env bash
printf 'not a version string\n'
EOF
chmod +x "$UNPARSABLE/gh"
PATH="$UNPARSABLE:$PATH" wit_gh_has_native_surface
assert_eq "unparsable gh --version fails closed" "1" "$?"

CLAUDE_CODE_REMOTE=true GH_STUB_VERSION=2.94.0 PATH="$STUB_BIN:$PATH" wit_gh_has_native_surface
assert_eq "CLAUDE_CODE_REMOTE=true refuses the native surface on gh 2.94" "1" "$?"
CLAUDE_CODE_REMOTE=false GH_STUB_VERSION=2.94.0 PATH="$STUB_BIN:$PATH" wit_gh_has_native_surface
assert_eq "CLAUDE_CODE_REMOTE=false keeps the native surface on gh 2.94" "0" "$?"
CLAUDE_CODE_REMOTE=true wit_gh_session_refuses_graphql
assert_eq "CLAUDE_CODE_REMOTE=true is a GraphQL-refusing session" "0" "$?"
CLAUDE_CODE_REMOTE='' wit_gh_session_refuses_graphql
assert_eq "an unset CLAUDE_CODE_REMOTE is not" "1" "$?"

PATH="$NOGH" wit_gh_has_native_surface
assert_eq "missing gh fails closed" "1" "$?"

ART_OK="$STUB_BIN/art-ok"
mkdir -p "$ART_OK"
cat >"$ART_OK/gh" <<'EOF'
#!/usr/bin/env bash
printf 'USAGE\n  gh issue artifact <command> [flags]\n'
EOF
chmod +x "$ART_OK/gh"
PATH="$ART_OK:$PATH" wit_gh_has_issue_artifact
assert_eq "gh with issue artifact subcommand → 0" "0" "$?"

ART_COBRA="$STUB_BIN/art-cobra"
mkdir -p "$ART_COBRA"
cat >"$ART_COBRA/gh" <<'EOF'
#!/usr/bin/env bash
printf 'Work with GitHub issues.\nUSAGE\n  gh issue <command> [flags]\n'
EOF
chmod +x "$ART_COBRA/gh"
PATH="$ART_COBRA:$PATH" wit_gh_has_issue_artifact
assert_eq "old gh cobra fallback help for unknown subcommand → 1" "1" "$?"

ART_FAIL="$STUB_BIN/art-fail"
mkdir -p "$ART_FAIL"
cat >"$ART_FAIL/gh" <<'EOF'
#!/usr/bin/env bash
echo 'unknown command "artifact" for "gh issue"' >&2
exit 1
EOF
chmod +x "$ART_FAIL/gh"
PATH="$ART_FAIL:$PATH" wit_gh_has_issue_artifact
assert_eq "gh exiting non-zero on artifact --help → 1" "1" "$?"

PATH="$NOGH" wit_gh_has_issue_artifact
assert_eq "missing gh → wit_gh_has_issue_artifact returns 1" "1" "$?"

[[ $FAILED -eq 0 ]] || exit 1
