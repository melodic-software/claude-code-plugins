#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 0
gate="$SCRIPT_DIR/check-changelog-fragments.sh"
self="$(basename "$0")"
remote="${1:-origin}"
zero=0000000000000000000000000000000000000000

top="$(git rev-parse --show-toplevel 2>/dev/null)" && cd "$top" || exit 0
head_sha="$(git rev-parse HEAD 2>/dev/null)" || exit 0
default="$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null)" || default="$remote/main"
default_branch="refs/heads/${default#"$remote"/}"

check=0
while IFS=' ' read -r local_ref local_sha remote_ref _; do
  [[ -n "${local_ref:-}" ]] || continue
  [[ "$local_sha" != "$zero" ]] || continue
  [[ "$remote_ref" == refs/heads/* ]] || continue
  [[ "$remote_ref" != "$default_branch" ]] || continue
  [[ "$local_sha" == "$head_sha" ]] || {
    echo "$self: $local_ref is not HEAD; its checks are left to CI." >&2
    continue
  }
  check=1
done

((check)) || exit 0
if ! changed_files::verify_base "$default"; then
  echo "$self: $default is not fetched; the pre-push checks are left to CI." >&2
  exit 0
fi

status=0
if [[ -n "$(git status --porcelain --untracked-files=all -- .changes 2>/dev/null)" ]]; then
  echo "$self: .changes/ has uncommitted edits, so the pushed fragments' format is left to CI." >&2
else
  "$gate" --check || status=$?
fi
if ((status != 1)); then
  "$gate" --check-required "$default" || status=$?
fi
blocked=0
case "$status" in
0) ;;
1)
  echo "$self: fix the fragment finding above, commit, and push again (ADR 0048; scripts/new-changelog-fragment.sh writes one)." >&2
  blocked=1
  ;;
*) echo "$self: the fragment gate could not run (exit $status); left to CI." >&2 ;;
esac

case "$(uname -s 2>/dev/null)" in
MINGW* | MSYS* | CYGWIN*)
  echo "$self: on Windows only the fragment checks run; the whole-branch checks are left to CI until they are timed there." >&2
  exit "$blocked"
  ;;
*) ;;
esac
if [[ -n "$(git status --porcelain --untracked-files=all 2>/dev/null)" ]]; then
  echo "$self: the working tree has uncommitted changes, so the whole-branch checks are left to CI." >&2
  exit "$blocked"
fi

parity() {
  local p="$SCRIPT_DIR/check-changelog-parity.sh"
  "$p" --check &&
    CHANGELOG_PARITY_COLLISIONS=advisory "$p" --check-bump "$default" &&
    "$p" --check-preserved "$default" &&
    "$p" --check-order
}

contracts() {
  local out rc=0
  out="$(VALIDATE_CONTRACTS_BASE_REF="$default" node "$SCRIPT_DIR/validate-plugin-contracts.mjs" 2>&1)" || rc=$?
  printf '%s\n' "$out"
  if ((rc == 0)) && grep -q '^warning: ' <<<"$out"; then
    echo "a contract warning fails like an error (scripts/validate-plugins.sh)."
    rc=1
  fi
  return "$rc"
}

work="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-checks.XXXXXX")" || {
  echo "$self: mktemp failed; the whole-branch checks are left to CI." >&2
  exit "$blocked"
}
trap 'rm -rf "$work"' EXIT

names=(changelog-parity plugin-options-docs plugin-contracts marketplace catalog cheatsheet)
tools=(bash python3 node node node node)
fixes=(
  "fix the CHANGELOG or version finding, then re-run scripts/check-changelog-parity.sh --check; CHANGELOG_PARITY_COLLISIONS=advisory scripts/check-changelog-parity.sh --check-bump $default; scripts/check-changelog-parity.sh --check-preserved $default; scripts/check-changelog-parity.sh --check-order"
  "python3 scripts/sync-plugin-options-docs.py"
  "fix the manifest or skill finding, then re-run node scripts/validate-plugin-contracts.mjs"
  "node scripts/generate-marketplace.mjs"
  "node scripts/generate-catalog.mjs"
  "node scripts/generate-cheatsheet.mjs --root ."
)
pids=()
for i in "${!names[@]}"; do
  pids[i]=""
  if ! command -v "${tools[i]}" >/dev/null 2>&1; then
    echo "$self: ${tools[i]} is not on PATH, so ${names[i]} is left to CI." >&2
    continue
  fi
  case "${names[i]}" in
  changelog-parity) parity ;;
  plugin-options-docs) python3 "$SCRIPT_DIR/sync-plugin-options-docs.py" --check ;;
  plugin-contracts) contracts ;;
  marketplace) node "$SCRIPT_DIR/generate-marketplace.mjs" --check ;;
  catalog) node "$SCRIPT_DIR/generate-catalog.mjs" --check ;;
  cheatsheet) node "$SCRIPT_DIR/generate-cheatsheet.mjs" --check --root . ;;
  *) ;;
  esac >"$work/${names[i]}" 2>&1 &
  pids[i]=$!
done

for i in "${!names[@]}"; do
  [[ -n "${pids[i]}" ]] || continue
  rc=0
  wait "${pids[i]}" || rc=$?
  case "$rc" in
  0) ;;
  1)
    {
      cat "$work/${names[i]}"
      echo "$self: ${names[i]} failed; fix: ${fixes[i]}"
    } >&2
    blocked=1
    ;;
  *) echo "$self: ${names[i]} could not run (exit $rc); left to CI." >&2 ;;
  esac
done
((blocked == 0)) || echo "$self: commit the fixes above and push again." >&2
exit "$blocked"
