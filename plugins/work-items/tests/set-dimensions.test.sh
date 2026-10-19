#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Triage's dimension writer: the model names one key per dimension, and the script turns each
# into the option id the repository's models.issue-dimensions map gives it, then sets them
# through the tracker seam. The fixture config uses names and ids no skill text holds, so a
# pass shows they come from the config. The seam runs for real against a gh stub whose org
# listing holds the fixture's ids.
#
#   bash plugins/work-items/tests/set-dimensions.test.sh
# test-scope: plugins/work-items/tools/work-item-tracker/adapters/github/capabilities.json plugins/work-items/tools/work-item-tracker/adapters/github/common.sh plugins/work-items/tools/work-item-tracker/adapters/github/set-fields.sh plugins/work-items/tools/work-item-tracker/lib/id.sh plugins/work-items/tools/work-item-tracker/lib/lease.sh
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
S="$PLUGIN_DIR/skills/triage/scripts/set-dimensions.sh"
# shellcheck source=../tools/work-item-tracker/tests/lib.sh
source "$PLUGIN_DIR/tools/work-item-tracker/tests/lib.sh"
command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
REPO="$TMP_ROOT/repo"
mkdir -p "$REPO/docs/conventions" "$TMP_ROOT/bin"
git -C "$REPO" init -q
cat >"$REPO/docs/conventions/pr-pipeline.yaml" <<'EOF'
models:
  issue-dimensions:
    fields:
      size:
        field-id: 11
        options: { "101": tiny, "102": huge }
      complexity:
        field-id: 12
        options: { "201": easy, "202": hard }
      uncertainty:
        field-id: 13
        options: { "301": clear, "302": foggy }
    sizes:
      tiny: { base-turns: 10, timeout-minutes: 5 }
      huge: split
    complexity: { easy: 1, hard: 2 }
    uncertainty: { clear: run, foggy: probe-first }
EOF
git -C "$REPO" -c user.email=t@t -c user.name=t add -A
git -C "$REPO" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm fixture
COMMIT="$(git -C "$REPO" rev-parse HEAD)"
printf '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}\n' >"$REPO/.work-item-tracker.json"

LOG="$TMP_ROOT/gh.log"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
[[ "$1" == "--version" ]] && { printf 'gh version 2.97.0 (test)\n'; exit 0; }
for a in "$@"; do
  case "$a" in
  orgs/*/issue-fields)
    printf '%s\n' '[{"id":11,"data_type":"single_select","options":[{"id":101,"name":"Tiny"},{"id":102,"name":"Huge"}]},
      {"id":12,"data_type":"single_select","options":[{"id":201,"name":"Easy"},{"id":202,"name":"Hard"}]},
      {"id":13,"data_type":"single_select","options":[{"id":301,"name":"Clear"},{"id":302,"name":"Foggy"}]}]'
    exit 0 ;;
  repos/*/issue-field-values) printf '[]\n'; exit 0 ;;
  esac
done
exit 90
EOF
chmod +x "$TMP_ROOT/bin/gh"

run() {
  : >"$LOG"
  OUT="$(cd "$REPO" && PATH="$TMP_ROOT/bin:$PATH" GH_STUB_LOG="$LOG" WIT_WRITE_SPACING_S=0 \
    CLAUDE_PROJECT_DIR="$REPO" bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
  ERR="$(<"$TMP_ROOT/err")"
}
writes() { grep -c 'issue-field-values' "$LOG"; }

ID="github:o/r#5"

run "$ID" size=tiny complexity=hard uncertainty=clear
assert_eq "all three keys → exit 0" "0" "$RC"
assert_eq "sets each dimension by the option id its key maps to" '[[11,101,"Tiny"],[12,202,"Hard"],[13,301,"Clear"]]' \
  "$(jq -c '[.fields[] | [.field_id, .option_id, .value]]' <<<"$OUT")"
assert_eq "one write" "1" "$(writes)"

run --dry-run "$ID" size=huge complexity=easy uncertainty=foggy
assert_eq "dry run → exit 0" "0" "$RC"
assert_eq "dry run resolves the ids" '[["size","huge",11,102],["complexity","easy",12,201],["uncertainty","foggy",13,302]]' \
  "$(jq -c '[.fields[] | [.dimension, .key, .field_id, .option_id]]' <<<"$OUT")"
assert_eq "dry run writes nothing" "0" "$(writes)"

run --ref "$COMMIT" "$ID" size=tiny complexity=easy uncertainty=clear
assert_eq "--ref reads the committed config" "0" "$RC"

run "$ID" size=small complexity=easy uncertainty=clear
assert_eq "a key the map lacks → exit 2" "2" "$RC"
assert_contains "error names the key and dimension" "$ERR" "small"
assert_eq "no write for an unmapped key" "0" "$(writes)"

run "$ID" size=tiny complexity=easy
assert_eq "a dimension left out → exit 2" "2" "$RC"
assert_contains "error names the missing dimension" "$ERR" "uncertainty"
assert_eq "no write for a partial assessment" "0" "$(writes)"

run "$ID" size=tiny complexity=easy uncertainty=clear effort=low
assert_eq "a dimension the config lacks → exit 2" "2" "$RC"

run --ref "not-a-ref" "$ID" size=tiny complexity=easy uncertainty=clear
assert_eq "malformed --ref → exit 2" "2" "$RC"

mv "$REPO/docs/conventions/pr-pipeline.yaml" "$TMP_ROOT/away.yaml"
run "$ID" size=tiny complexity=easy uncertainty=clear
assert_eq "no dimension map → exit 3" "3" "$RC"
mv "$TMP_ROOT/away.yaml" "$REPO/docs/conventions/pr-pipeline.yaml"

# Two option ids for one key would make the write a guess.
CFG="$REPO/docs/conventions/pr-pipeline.yaml"
text="$(<"$CFG")"
printf '%s\n' "${text/\"102\": huge/\"102\": tiny}" >"$CFG"
run "$ID" size=tiny complexity=easy uncertainty=clear
assert_eq "a key two options map to → exit 2" "2" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
