#!/usr/bin/env bash
# Tests for read-prep-audits.sh. Expected outputs follow the prep_audits
# contract in reference/config-resolution.md: an absent key runs every default
# audit, `enabled: false` turns one class's audit off, a `skill` replaces it,
# and anything the reader cannot trust runs every default audit.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-prep-audits.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

ALL_DEFAULT=$'markdown\tdefault\nrenames\tdefault\nskills\tdefault\nrules\tdefault\ntests\tdefault'

ON_DEFAULT=(--base main --default-branch main)
read_doc() { printf '%s' "$1" | bash "$SCRIPT" "${ON_DEFAULT[@]}" - 2>/dev/null; }

out=$(read_doc '')
assert_eq "no file (git show printed nothing) runs every default audit" $'source\tdefault\n'"$ALL_DEFAULT" "$out"

out=$(read_doc $'pr_open_state: ready\npre_ready:\n  - step: verify\n    enabled: false\n')
assert_eq "a file without prep_audits runs every default audit" $'source\tdefault\n'"$ALL_DEFAULT" "$out"

out=$(read_doc $'prep_audits: []\n')
assert_eq "an empty list runs every default audit" $'source\tdefault\n'"$ALL_DEFAULT" "$out"

out=$(read_doc $'prep_audits:\n  - class: markdown\n    enabled: true\n    skill: /team-docs:prose-lint\n  - class: rules\n    enabled: false\n  - class: tests\n    enabled: false\n')
assert_eq "a skill replaces one class, enabled false turns others off, the rest stay default" \
  $'source\tconfig\nmarkdown\treplace\t/team-docs:prose-lint\nrenames\tdefault\nskills\tdefault\nrules\toff\ntests\toff' "$out"

out=$(read_doc $'prep_audits:\n  - class: skills\n    enabled: true\n    skill: "/lint-skills"\n  - class: renames\n    enabled: true\n')
assert_eq "a project skill with no plugin replaces, and enabled true alone keeps the default" \
  $'source\tconfig\nmarkdown\tdefault\nrenames\tdefault\nskills\treplace\t/lint-skills\nrules\tdefault\ntests\tdefault' "$out"

out=$(read_doc $'pre_ready:\n  - step: verify\n    enabled: "false"\nprep_audits:\n  - class: rules\n    enabled: false\n')
assert_eq "a quoted enabled under another key does not fail this list" \
  $'source\tconfig\nmarkdown\tdefault\nrenames\tdefault\nskills\tdefault\nrules\toff\ntests\tdefault' "$out"

# The parser accepts a uniform base indent and a byte-order mark, so the text scan must too.
RULES_ONLY_OFF=$'source\tconfig\nmarkdown\tdefault\nrenames\tdefault\nskills\tdefault\nrules\toff\ntests\tdefault'
out=$(read_doc $'  pr_open_state: ready\n  prep_audits:\n    - class: rules\n      enabled: false\n  other: 1\n')
assert_eq "a document indented two spaces is read" "$RULES_ONLY_OFF" "$out"
out=$(read_doc $'\xef\xbb\xbfprep_audits:\n  - class: rules\n    enabled: false\n')
assert_eq "a byte-order mark before the key is read" "$RULES_ONLY_OFF" "$out"

# Names the reader uses inside must not be read from the environment it inherits.
out=$(printf '' | env audit_rules=off bash "$SCRIPT" "${ON_DEFAULT[@]}" - 2>/dev/null)
assert_eq "an inherited audit_rules does not turn the rules audit off" $'source\tdefault\n'"$ALL_DEFAULT" "$out"
out=$(printf 'prep_audits:\n  - class: markdown\n    enabled: true\n' | env item_0_skill=/evil:skip bash "$SCRIPT" "${ON_DEFAULT[@]}" - 2>/dev/null)
assert_eq "an inherited item_0_skill does not replace an enabled item" $'source\tconfig\n'"$ALL_DEFAULT" "$out"

# Each untrusted shape: the source line fails closed with a reason, and every class runs its default.
check_fail_closed() {
  local label="$1" doc="$2" reason="$3" got
  got=$(read_doc "$doc")
  assert_eq "$label runs every default audit" $'source\tfail-closed\t'"$reason"$'\n'"$ALL_DEFAULT" "$got"
}

check_fail_closed "an unknown class" \
  $'prep_audits:\n  - class: rules\n    enabled: false\n  - class: security\n    enabled: false\n' "unknown class 'security' in prep_audits"
check_fail_closed "the code class, which is not configurable here," \
  $'prep_audits:\n  - class: code\n    enabled: false\n' "unknown class 'code' in prep_audits"
check_fail_closed "a class listed twice" \
  $'prep_audits:\n  - class: rules\n    enabled: true\n  - class: rules\n    enabled: false\n' "class 'rules' is listed twice in prep_audits"
check_fail_closed "a skill on the off-only tests class" \
  $'prep_audits:\n  - class: tests\n    enabled: true\n    skill: /team:judge\n' "class 'tests' cannot be replaced, only turned off"
check_fail_closed "an off class that also names a skill" \
  $'prep_audits:\n  - class: markdown\n    enabled: false\n    skill: /team:prose-lint\n' "class 'markdown' is off and also names a skill"
check_fail_closed "a skill carrying arguments" \
  $'prep_audits:\n  - class: markdown\n    enabled: true\n    skill: /team:prose-lint --fix\n' "class 'markdown' has skill '/team:prose-lint --fix', not /<plugin>:<skill> or /<skill>"
check_fail_closed "a shell command in place of a skill" \
  $'prep_audits:\n  - class: markdown\n    enabled: true\n    skill: npx markdownlint .\n' "class 'markdown' has skill 'npx markdownlint .', not /<plugin>:<skill> or /<skill>"
check_fail_closed "an empty skill" \
  $'prep_audits:\n  - class: rules\n    enabled: true\n    skill: ""\n' "class 'rules' has skill '', not /<plugin>:<skill> or /<skill>"
check_fail_closed "an enabled value other than true or false" \
  $'prep_audits:\n  - class: rules\n    enabled: off\n' "class 'rules' has enabled 'off', not true or false"
check_fail_closed "an item with no enabled value" \
  $'prep_audits:\n  - class: rules\n    skill: /team:rules\n' "class 'rules' has no enabled value in prep_audits"
check_fail_closed "an item with no class" \
  $'prep_audits:\n  - enabled: false\n' "prep_audits item 0 has no class"
check_fail_closed "an extra key inside an item" \
  $'prep_audits:\n  - class: rules\n    enabled: false\n    why: x\n' "prep_audits item 0 has an unknown key 'why'"
check_fail_closed "a quoted enabled value" \
  $'prep_audits:\n  - class: rules\n    enabled: "false"\n' "an enabled value in prep_audits is quoted, not a boolean"
check_fail_closed "a list of bare class names" \
  $'prep_audits: [rules]\n' "prep_audits item 0 is not a {class, enabled} mapping"
check_fail_closed "a scalar prep_audits" \
  $'prep_audits: off\n' "prep_audits is not a list"
check_fail_closed "a mapping keyed by class" \
  $'prep_audits:\n  rules:\n    enabled: false\n' "prep_audits is a mapping, not a list"
check_fail_closed "a repeated prep_audits key" \
  $'prep_audits: []\nprep_audits:\n  - class: rules\n    enabled: false\n' "prep_audits appears more than once"
# The parser emits no record for an empty value, so these are found in the text.
check_fail_closed "an empty flow list as a skill" \
  $'prep_audits:\n  - class: rules\n    enabled: false\n    skill: []\n' "prep_audits item has a key with no value"
check_fail_closed "an unknown key with an empty value" \
  $'prep_audits:\n  - class: rules\n    enabled: false\n    note:\n' "prep_audits item has a key with no value"
check_fail_closed "a trailing empty list item" \
  $'prep_audits:\n  - class: rules\n    enabled: false\n  -\n' "prep_audits holds an empty item"
check_fail_closed "a trailing empty item under a two-space base indent" \
  $'  prep_audits:\n    - class: rules\n      enabled: false\n    -\n' "prep_audits holds an empty item"
check_fail_closed "an empty value under a two-space base indent" \
  $'  prep_audits:\n    - class: rules\n      enabled: false\n      skill: []\n' "prep_audits item has a key with no value"
check_fail_closed "an only, empty list item" \
  $'prep_audits:\n  -\n' "prep_audits holds an empty item"
check_fail_closed "a file the parser rejects" \
  $'prep_audits:\n\t- class: rules\n' "docs/conventions/source-control.yaml does not parse: line 2: tab indentation"

# The list is honored only on the default branch: any other base is one the author may have pushed unreviewed.
RULES_OFF=$'prep_audits:\n  - class: rules\n    enabled: false\n'
out=$(printf '%s' "$RULES_OFF" | bash "$SCRIPT" --base stack/layer-2 --default-branch main - 2>/dev/null)
assert_eq "a base other than the default branch fails closed and runs every default audit" \
  $'source\tfail-closed\tbase stack/layer-2 is not the default branch main\n'"$ALL_DEFAULT" "$out"
out=$(printf '%s' "$RULES_OFF" | bash "$SCRIPT" --base main --default-branch '' - 2>/dev/null)
assert_eq "an unread default branch fails closed and runs every default audit" \
  $'source\tfail-closed\tthe repository\'s default branch could not be read\n'"$ALL_DEFAULT" "$out"

# A NUL byte would vanish in a shell variable, turning `fal\0se` into `false`.
out=$(printf 'prep_audits:\n  - class: rules\n    enabled: fal\000se\n' | bash "$SCRIPT" "${ON_DEFAULT[@]}" - 2>/dev/null)
assert_eq "a NUL byte in the document fails closed and runs every default audit" \
  $'source\tfail-closed\tthe input holds a NUL byte\n'"$ALL_DEFAULT" "$out"

printf '' | bash "$SCRIPT" - >/dev/null 2>&1
assert_exit "a read without --base and --default-branch is a usage error" 2 "$?"
bash "$SCRIPT" --base main --default-branch main docs/conventions/source-control.yaml >/dev/null 2>&1
assert_exit "a working-tree path is refused" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
