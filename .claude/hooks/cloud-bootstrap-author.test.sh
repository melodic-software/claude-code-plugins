#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
# shellcheck source=../../scripts/test-git-helpers.sh
source "$repo_root/scripts/test-git-helpers.sh"

BOOTSTRAP="${CLOUD_BOOTSTRAP_SCRIPT:-$repo_root/.claude/cloud-bootstrap.sh}"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq unavailable; the gh stub answers through the block's --jq filter"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BLOCK="$TMP/author-block.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  awk '/^gh_user=/ {p = 1} /^hook_safe_path=/ {p = 0} p' "$BOOTSTRAP"
} >"$BLOCK"
if ! grep -q 'author.email' "$BLOCK" || grep -q 'Report' "$BLOCK"; then
  echo "FAIL: could not extract the git-author block between its anchors in $BOOTSTRAP"
  exit 1
fi

mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ -n "${GH_STUB_USER:-}" ]] || exit 1
[[ "$1 $2 $3" == 'api user --jq' ]] || exit 1
printf '%s' "$GH_STUB_USER" | jq -r "$4"
STUB
chmod +x "$TMP/bin/gh"

pass=0
fail=0
check() {
  if [[ "$2" == "$3" ]]; then
    echo "ok   - $1"
    pass=$((pass + 1))
  else
    printf 'not ok - %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3"
    fail=$((fail + 1))
  fi
}

global_config() {
  local cfg="$TMP/$1.gitconfig"
  if [[ -n "${5:-}" ]]; then
    GIT_CONFIG_GLOBAL="$cfg" git config --global author.name 'Stale Author'
    GIT_CONFIG_GLOBAL="$cfg" git config --global author.email 'stale@example.test'
  fi
  PATH="$TMP/bin:$PATH" GIT_CONFIG_GLOBAL="$cfg" GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CODE_REMOTE="$3" CLAUDE_PROJECT_DIR="$repo_root" GH_STUB_USER="$4" \
    bash "$2" >/dev/null 2>&1 || echo "exit $?"
  GIT_CONFIG_GLOBAL="$cfg" git config --global --list 2>/dev/null | sort
}

octo='{"login":"octo","id":42,"name":"Octo Cat"}'
check 'the connected account sets author.* only' \
  "$(printf '%s\n' 'author.email=42+octo@users.noreply.github.com' 'author.name=Octo Cat')" \
  "$(global_config success "$BLOCK" true "$octo")"
check 'an account with no display name falls back to the login' \
  "$(printf '%s\n' 'author.email=42+octo@users.noreply.github.com' 'author.name=octo')" \
  "$(global_config no-name "$BLOCK" true '{"login":"octo","id":42,"name":null}')"
check 'a failed gh call sets nothing and does not abort' '' \
  "$(global_config failure "$BLOCK" true '')"
check 'a failed gh call clears a stale author' '' \
  "$(global_config stale "$BLOCK" true '' stale)"
check 'an empty login sets nothing' '' \
  "$(global_config no-login "$BLOCK" true '{"login":null,"id":42,"name":"Octo Cat"}')"
check 'an empty id sets nothing' '' \
  "$(global_config no-id "$BLOCK" true '{"login":"octo","id":null,"name":"Octo Cat"}')"
check 'a non-remote session sets nothing' '' \
  "$(global_config local "$BOOTSTRAP" false "$octo")"

echo
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
