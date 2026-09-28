#!/usr/bin/env bash
# Offline fleet sync: park a dirty side branch, fast-forward main, skip a divergence.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SYNC="$ROOT/skills/sync/scripts/sync-fleet.sh"
FAIL=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git init -q -b main "$TMP/origin"
git -C "$TMP/origin" config user.email t@example.com
git -C "$TMP/origin" config user.name t
echo base >"$TMP/origin/README"
git -C "$TMP/origin" add README
git -C "$TMP/origin" commit -q -m base
git clone -q "$TMP/origin" "$TMP/repo"
git -C "$TMP/repo" config user.email t@example.com
git -C "$TMP/repo" config user.name t
git -C "$TMP/repo" checkout -q -b feature
echo side >"$TMP/repo/side.txt"

plan="$(bash "$SYNC" --repo "$TMP/repo")"
printf '%s\n' "$plan" | grep -q 'park-then-ff-pull' && ok "dry-run plans a park" || bad "dry-run plans a park" "$plan"
[[ "$(git -C "$TMP/repo" branch --show-current)" == "feature" ]] && ok "dry-run does not switch" || bad "dry-run does not switch" "$(git -C "$TMP/repo" branch --show-current)"

out="$(bash "$SYNC" --apply --yes --repo "$TMP/repo" --park-root "$TMP/parks")"
printf '%s\n' "$out" | grep -q $'result\t'"$TMP/repo"$'\tok\t' && ok "apply fast-forwards" || bad "apply fast-forwards" "$out"
[[ "$(git -C "$TMP/repo" branch --show-current)" == "main" ]] && ok "canonical is on the default branch" || bad "canonical is on the default branch" "$(git -C "$TMP/repo" branch --show-current)"
[[ -z "$(git -C "$TMP/repo" status --porcelain)" ]] && ok "canonical is clean" || bad "canonical is clean" "$(git -C "$TMP/repo" status --porcelain)"
if find "$TMP/parks" -name side.txt -type f | grep -q side.txt; then
  ok "side file lives in the park worktree"
else
  bad "side file lives in the park worktree" "$(find "$TMP/parks" -type f 2>/dev/null | head)"
fi

# Diverged main is not a fast-forward.
echo other >"$TMP/origin/README"
git -C "$TMP/origin" add README
git -C "$TMP/origin" commit -q -m other
echo local >"$TMP/repo/README"
git -C "$TMP/repo" add README
git -C "$TMP/repo" commit -q -m local
out="$(bash "$SYNC" --apply --yes --repo "$TMP/repo" --park-root "$TMP/parks")"
printf '%s\n' "$out" | grep -q 'not a fast-forward' && ok "divergence is skipped" || bad "divergence is skipped" "$out"

none="$(cd "$TMP" && bash "$ROOT/scripts/resolve-fleet-scope.sh"; echo exit:$?)"
printf '%s\n' "$none" | grep -q 'exit:3' && ok "no scope exits 3" || bad "no scope exits 3" "$none"

printf '%s failed\n' "$FAIL"
[[ "$FAIL" -eq 0 ]]
