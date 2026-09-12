#!/usr/bin/env bash
# Self-contained tests for resolve-config.sh. No repository test library: this
# script ships inside the plugin, so its suite has to run wherever the plugin is
# installed.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/resolve-config.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0

pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

# A fresh consumer root with an empty HOME beside it, so no layer is present
# until a case writes one.
new_root() {
  root="$TEST_TMPDIR/root-$CASES-$RANDOM"
  mkdir -p "$root/.claude" "$root/home"
  printf '%s' "$root"
}

write_layer() {
  # write_layer <path> <file_names-json> [schema]
  schema="${3:-1}"
  mkdir -p "$(dirname "$1")"
  printf '{"schema": %s, "file_names": %s}\n' "$schema" "$2" >"$1"
}

resolve() {
  # resolve <root> [extra args...]
  r="$1"
  shift
  bash "$SUT" resolve --root "$r" --home "$r/home" "$@"
}

layers() {
  r="$1"
  shift
  bash "$SUT" layers --root "$r" --home "$r/home" "$@"
}

# 1. Every layer absent resolves to the bundled defaults.
root="$(new_root)"
out="$(resolve "$root")"
assert_eq "no layers: rule is the bundled lower-kebab" "lower-kebab" "$(printf '%s' "$out" | jq -r '.file_names.rule')"
assert_eq "no layers: roots is the bundled docs" "docs" "$(printf '%s' "$out" | jq -r '.file_names.roots[0]')"
assert_eq "no layers: schema is stamped" "1" "$(printf '%s' "$out" | jq -r '.schema')"
assert_eq "no layers: every key is provenance bundled" "" "$(layers "$root" | grep -v 'bundled$' || true)"

# 2. The team layer supplies a nearest-wins key whole.
root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.json" '{"regex": "^team$"}'
assert_eq "team layer: regex overrides the default" "^team$" "$(resolve "$root" | jq -r '.file_names.regex')"
assert_contains "team layer: provenance names it" "$(layers "$root")" "regex	bundled,team"

# 3. The overlay beats the team layer on a nearest-wins key.
write_layer "$root/.claude/docs-hygiene.local.json" '{"regex": "^overlay$"}'
assert_eq "overlay: nearest wins on regex" "^overlay$" "$(resolve "$root" | jq -r '.file_names.regex')"

# 4. Additive keys append, and the team entries survive.
root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.json" '{"exempt_paths": ["docs/frozen/**"]}'
write_layer "$root/.claude/docs-hygiene.local.json" '{"exempt_paths": ["docs/mine/**"]}'
out="$(resolve "$root" | jq -c '.file_names.exempt_paths')"
assert_contains "additive: the team entry survives the overlay" "$out" '"docs/frozen/**"'
assert_contains "additive: the overlay entry is added" "$out" '"docs/mine/**"'
assert_contains "additive: the bundled entry survives too" "$out" '"docs/topics/**"'

# 5. A personal layer cannot shrink a policy-floor list: an overlay `tiers` that
#    omits the frozen released tier still resolves with it present.
root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.local.json" '{"tiers": [{"name": "mine", "paths": ["docs/x/**"], "forms": "all"}]}'
names="$(resolve "$root" | jq -r '.file_names.tiers[].name' | sort | tr '\n' ' ')"
assert_eq "policy floor: the overlay adds a tier and removes none" "historical mine released " "$names"

# 6. `generated` is team-layer only: an overlay declaration is inert.
root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.local.json" '{"generated": [{"path": "x", "regenerate": "rm -rf /"}]}'
out="$(resolve "$root" | jq -r '.file_names.generated[0].path')"
assert_eq "team-only: the overlay regenerator is ignored" "docs/architecture/landscape.json" "$out"
assert_contains "team-only: the overlay declaration is reported inert" "$(layers "$root")" "!inert:generated	overlay"

# 7. The same holds for the user-global layer.
root="$(new_root)"
write_layer "$root/home/.claude/docs-hygiene.json" '{"generated": [{"path": "y", "regenerate": "true"}]}'
assert_eq "team-only: the user-global regenerator is ignored" "docs/architecture/landscape.json" "$(resolve "$root" | jq -r '.file_names.generated[0].path')"
assert_contains "team-only: the user-global declaration is reported inert" "$(layers "$root")" "!inert:generated	user-global"

# 8. A team layer DOES supply `generated`.
root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.json" '{"generated": [{"path": "build/out.json", "regenerate": "make out"}]}'
assert_eq "team layer supplies the regenerator" "build/out.json" "$(resolve "$root" | jq -r '.file_names.generated[0].path')"

# 9. Malformed JSON is fatal and names the file.
root="$(new_root)"
printf '{not json' >"$root/.claude/docs-hygiene.json"
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_eq "malformed team layer exits 2" "2" "$(
  resolve "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_contains "malformed team layer is named" "$err" "docs-hygiene.json"

# 10. A missing schema is fatal.
root="$(new_root)"
printf '{"file_names": {"rule": "lower-kebab"}}\n' >"$root/.claude/docs-hygiene.json"
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_contains "missing schema is refused" "$err" "schema 'missing'"

# 11. An unknown schema is fatal.
root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.json" '{"rule": "lower-kebab"}' 99
err="$(resolve "$root" 2>&1 >/dev/null)"
assert_contains "unknown schema is refused" "$err" "schema '99'"

# 12. A jq that emits CRLF (native Windows behavior) still resolves clean values.
root="$(new_root)"
mkdir -p "$root/bin"
{
  printf '#!/usr/bin/env bash\n'
  printf 'REAL=%q\n' "$(command -v jq)"
  printf '"$REAL" "$@" | sed "s/$/\\r/"\n'
} >"$root/bin/jq"
chmod +x "$root/bin/jq"
write_layer "$root/.claude/docs-hygiene.json" '{"regex": "^crlf$"}'
out="$(PATH="$root/bin:$PATH" resolve "$root" | jq -r '.file_names.regex')"
assert_eq "CRLF jq: the resolved regex carries no carriage return" "^crlf$" "$out"

# 13. Usage errors exit 2.
assert_eq "unknown action exits 2" "2" "$(
  bash "$SUT" frobnicate >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "no action exits 2" "2" "$(
  bash "$SUT" --root "$TEST_TMPDIR" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "a missing --root directory exits 2" "2" "$(
  bash "$SUT" resolve --root "$TEST_TMPDIR/nope" >/dev/null 2>&1
  printf '%s' "$?"
)"

# 14. `paths` reports each layer's location and presence.
root="$(new_root)"
write_layer "$root/.claude/docs-hygiene.json" '{}'
out="$(bash "$SUT" paths --root "$root" --home "$root/home")"
assert_contains "paths: the team layer is present" "$out" "team	$root/.claude/docs-hygiene.json	present"
assert_contains "paths: the overlay is absent" "$out" "overlay	$root/.claude/docs-hygiene.local.json	absent"

# 15. With no --root the resolver takes the git toplevel of the working
#     directory, never the directory the script lives in.
root="$(new_root)"
git init -q "$root" >/dev/null 2>&1
git -C "$root" config user.email fixture@example.invalid
git -C "$root" config user.name "Fixture"
git -C "$root" config commit.gpgsign false
write_layer "$root/.claude/docs-hygiene.json" '{"regex": "^from-cwd$"}'
out="$(cd "$root" && HOME="$root/home" bash "$SUT" resolve | jq -r '.file_names.regex')"
assert_eq "no --root: the git toplevel of the cwd supplies the team layer" "^from-cwd$" "$out"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
