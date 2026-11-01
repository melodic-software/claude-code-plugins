#!/usr/bin/env bash
# Tests for migrate-binding.sh: a fixture JSON binding and overlay are copied into
# the convention home's YAML files, read back through the seam's own reader, and the
# JSON files are left byte-for-byte unchanged.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR
# The developer's global and system git config (a core.excludesFile among them)
# must not decide whether a fixture's overlay path is ignored.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/migrate-binding.sh"
BINDING_LIB="$SCRIPT_DIR/../../../tools/work-item-tracker/lib/binding.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3, actual: $2" ;;
  esac
}
assert_same_file() {
  if cmp -s "$2" "$3"; then pass "$1"; else fail "$1" "$3 differs from $2"; fi
}
assert_absent() {
  if [[ ! -e "$2" ]]; then pass "$1"; else fail "$1" "$2 exists"; fi
}

# fixture <name>: a fresh git repository with a gitignored YAML overlay path.
fixture() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '%s\n' '*.local.yaml' '.work-item-tracker.local.json' >"$dir/.gitignore"
  printf '%s\n' "$dir"
}

# effective <root>: the binding path and effective binding the seam resolves there.
effective() {
  CLAUDE_PROJECT_DIR="$1" bash -c '
    source "$1"
    path="$(wit_find_binding)" || exit 1
    printf "%s\n" "$path"
    wit_effective_binding_json "$path" | jq -S -c .' _ "$BINDING_LIB"
}

# Case 1: binding plus overlay, default home, values the YAML subset must escape.
ROOT="$(fixture default-home)"
cat >"$ROOT/.work-item-tracker.json" <<'EOF'
{
  "schema_version": "1.0",
  "provider": "github",
  "docs": "Binding: see \"CONTRACT.md\" at a\\path\tend",
  "config": {
    "lease_ttl_hours": 24,
    "role_labels": { "human-gated": "needs: human" },
    "github": { "wont_do_labels": ["wontfix", "invalid"], "empty": [] }
  }
}
EOF
printf '%s\n' '{"config": {"lease_ttl_hours": 6}}' >"$ROOT/.work-item-tracker.local.json"
cp "$ROOT/.work-item-tracker.json" "$TEST_TMPDIR/binding.orig"
cp "$ROOT/.work-item-tracker.local.json" "$TEST_TMPDIR/overlay.orig"
out="$(bash "$SCRIPT" --root "$ROOT" 2>&1)"
assert_eq "binding plus overlay: exit 0" 0 "$?"
assert_contains "binding plus overlay: binding copied" "$out" "binding: copied"
assert_contains "binding plus overlay: overlay copied" "$out" "overlay: copied"
assert_same_file "binding plus overlay: JSON binding unchanged" "$TEST_TMPDIR/binding.orig" "$ROOT/.work-item-tracker.json"
assert_same_file "binding plus overlay: JSON overlay unchanged" "$TEST_TMPDIR/overlay.orig" "$ROOT/.work-item-tracker.local.json"
read_back="$(effective "$ROOT")"
assert_eq "binding plus overlay: seam resolves the YAML binding" "$ROOT/docs/conventions/work-items.yaml" "${read_back%%$'\n'*}"
expected='{"config":{"github":{"empty":[],"wont_do_labels":["wontfix","invalid"]},"lease_ttl_hours":"6","role_labels":{"human-gated":"needs: human"}},"docs":"Binding: see \"CONTRACT.md\" at a\\path\tend","provider":"github","schema_version":"1.0"}'
assert_eq "binding plus overlay: seam reads the same values, overlay merged" "$expected" "${read_back#*$'\n'}"

# Case 2: a re-run finds both layers already in YAML and writes nothing.
cp "$ROOT/docs/conventions/work-items.yaml" "$TEST_TMPDIR/yaml.first"
out="$(bash "$SCRIPT" --root "$ROOT" 2>&1)"
assert_eq "re-run: exit 0" 0 "$?"
assert_contains "re-run: binding already in YAML" "$out" "binding: already-yaml"
assert_contains "re-run: overlay already in YAML" "$out" "overlay: already-yaml"
assert_same_file "re-run: YAML binding unchanged" "$TEST_TMPDIR/yaml.first" "$ROOT/docs/conventions/work-items.yaml"

# Case 3: an existing work-items.yaml with other settings and no final newline.
ROOT="$(fixture existing-yaml)"
mkdir -p "$ROOT/docs/conventions"
printf '# team layer\nai_disclaimer: false' >"$ROOT/docs/conventions/work-items.yaml"
printf '%s\n' '{"schema_version": "1.0", "provider": "github", "config": {"lease_ttl_hours": 24}}' >"$ROOT/.work-item-tracker.json"
out="$(bash "$SCRIPT" --root "$ROOT" 2>&1)"
assert_eq "existing YAML: exit 0" 0 "$?"
assert_contains "existing YAML: no overlay to copy" "$out" "overlay: no-json"
records="$(awk -f "$SCRIPT_DIR/../../triage/scripts/yaml-subset.awk" "$ROOT/docs/conventions/work-items.yaml")"
assert_contains "existing YAML: other settings kept" "$records" $'ai_disclaimer\tfalse'
assert_contains "existing YAML: binding appended" "$records" $'tracker.provider\tgithub'

# Case 4: a bound convention home receives the files.
ROOT="$(fixture bound-home)"
mkdir -p "$ROOT/config/team"
# shellcheck disable=SC2016 # the backticks are the pointer line's markdown, not a command
printf '%s\n' '<!-- BEGIN GENERATED: convention-home -->' 'Team conventions live in `config/team`.' \
  '<!-- END GENERATED: convention-home -->' >"$ROOT/AGENTS.md"
printf '%s\n' '{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items"}}' >"$ROOT/.work-item-tracker.json"
bash "$SCRIPT" --root "$ROOT" >/dev/null 2>&1
assert_eq "bound home: exit 0" 0 "$?"
read_back="$(effective "$ROOT")"
assert_eq "bound home: binding lands in the home" "$ROOT/config/team/work-items.yaml" "${read_back%%$'\n'*}"

# Case 5: an overlay path no .gitignore rule covers stops both layers: a YAML
# binding alone would leave the JSON overlay unread.
ROOT="$(fixture not-ignored)"
: >"$ROOT/.gitignore"
printf '%s\n' '{"schema_version": "1.0", "provider": "github", "config": {"lease_ttl_hours": 24}}' >"$ROOT/.work-item-tracker.json"
printf '%s\n' '{"config": {"lease_ttl_hours": 6}}' >"$ROOT/.work-item-tracker.local.json"
out="$(bash "$SCRIPT" --root "$ROOT" 2>/dev/null)"
assert_eq "not ignored: exit 3" 3 "$?"
assert_contains "not ignored: reported" "$out" "overlay: not-ignored"
assert_absent "not ignored: no YAML binding" "$ROOT/docs/conventions/work-items.yaml"
assert_absent "not ignored: no YAML overlay" "$ROOT/docs/conventions/work-items.local.yaml"

# Case 5b: a global excludes file named .gitignore protects no teammate, so it does
# not count as a repository rule.
ROOT="$(fixture global-excludes)"
: >"$ROOT/.gitignore"
mkdir -p "$TEST_TMPDIR/home"
printf '%s\n' '*.local.yaml' >"$TEST_TMPDIR/home/.gitignore"
printf '[core]\n\texcludesFile = %s\n' "$TEST_TMPDIR/home/.gitignore" >"$TEST_TMPDIR/global.gitconfig"
printf '%s\n' '{"schema_version": "1.0", "provider": "github", "config": {"lease_ttl_hours": 24}}' >"$ROOT/.work-item-tracker.json"
printf '%s\n' '{"config": {"lease_ttl_hours": 6}}' >"$ROOT/.work-item-tracker.local.json"
out="$(GIT_CONFIG_GLOBAL="$TEST_TMPDIR/global.gitconfig" bash "$SCRIPT" --root "$ROOT" 2>/dev/null)"
assert_eq "global excludes file: exit 3" 3 "$?"
assert_contains "global excludes file: reported" "$out" "overlay: not-ignored"
assert_absent "global excludes file: no YAML overlay" "$ROOT/docs/conventions/work-items.local.yaml"

# Case 6: values the YAML subset cannot carry, or the seam would read as absent,
# stop before any write.
ROOT="$(fixture null-value)"
printf '%s\n' '{"schema_version": "1.0", "provider": "github", "config": {"lease_ttl_hours": 24, "container_label": null, "jira": {"resolutions": {}}}}' >"$ROOT/.work-item-tracker.json"
err="$(bash "$SCRIPT" --root "$ROOT" 2>&1 >/dev/null)"
assert_eq "unsupported value: exit 1" 1 "$?"
assert_contains "unsupported value: names the null" "$err" "null at config.container_label"
assert_contains "unsupported value: names the empty object" "$err" "an empty object at config.jira.resolutions"
assert_absent "unsupported value: no YAML written" "$ROOT/docs/conventions/work-items.yaml"

# Case 7: no JSON binding writes nothing.
ROOT="$(fixture no-json)"
out="$(bash "$SCRIPT" --root "$ROOT" 2>&1)"
assert_eq "no JSON: exit 0" 0 "$?"
assert_contains "no JSON: reported" "$out" "binding: no-json"
assert_absent "no JSON: no YAML written" "$ROOT/docs/conventions/work-items.yaml"

# Case 8: a repository that declined a home keeps the JSON binding.
ROOT="$(fixture declined)"
printf '%s\n' '<!-- BEGIN GENERATED: convention-home -->' 'declined' '<!-- END GENERATED: convention-home -->' >"$ROOT/AGENTS.md"
printf '%s\n' '{"schema_version": "1.0", "provider": "github", "config": {"lease_ttl_hours": 24}}' >"$ROOT/.work-item-tracker.json"
bash "$SCRIPT" --root "$ROOT" >/dev/null 2>&1
assert_eq "declined home: exit 4" 4 "$?"
assert_absent "declined home: no YAML written" "$ROOT/docs/conventions/work-items.yaml"

if [[ "$FAILED" -gt 0 ]]; then
  printf '%s case(s) failed\n' "$FAILED" >&2
  exit 1
fi
echo "all migrate-binding tests passed"
