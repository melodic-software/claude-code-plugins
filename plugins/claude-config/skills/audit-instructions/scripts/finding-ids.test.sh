#!/usr/bin/env bash
# Regression tests for finding-ids.sh (assertions from test-helpers.sh beside
# this file). The identity assertions it pins are audit-pass's §1 as this skill
# fills it: a re-run over an unchanged tree keeps every id, editing a flagged
# sentence changes that finding's id, an unrelated edit does not, and an I15
# conflict is one finding with two sites whatever order the lane met them in.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDS="$SCRIPT_DIR/finding-ids.sh"
FI="$SCRIPT_DIR/../../audit-pass/scripts/finding-identity.sh"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "SKIP: sha256sum or shasum required" >&2
  exit 0
fi

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO/skills/demo/reference"
git -C "$REPO" init -q
cat >"$REPO/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: Demo skill.
---

# Demo

## Rules

Always run the tests before committing.

## Other rules

Never run the tests.
EOF
cat >"$REPO/skills/demo/reference/spoke.md" <<'EOF'
# Spoke

This file is loaded by the hub when the release names a breaking change.

State each breaking change first.

```text
## not a heading
Always run the tests before committing.
```

Always run the tests before committing.
EOF
cat >"$REPO/skills/demo/reference/commented.md" <<'EOF'
# Spoke

<!--
## note
-->

Always run the tests before committing.
EOF
cat >"$REPO/skills/demo/reference/plain.md" <<'EOF'
# Spoke

Always run the tests before committing.
EOF

ids() { (cd "$REPO" && bash "$IDS" "$@"); }
field() { printf '%s\n' "$1" | cut -f"$2"; }

# --- Case 1: two runs over an unchanged tree yield identical ids -------------
ROWS=$'skills/demo/reference/spoke.md:3:I33\nskills/demo/SKILL.md:10:I6\nskills/demo/SKILL.md:10|skills/demo/SKILL.md:14|I15'
RUN1="$(printf '%s\n' "$ROWS" | ids)"
RUN2="$(printf '%s\n' "$ROWS" | ids)"
assert_eq "an unchanged tree yields identical output across two runs" "$RUN1" "$RUN2"
assert_not_contains "no row is refused" "$RUN1" "#REFUSED"
RUN3="$(cd "$REPO/skills/demo" && printf '%s\n' 'reference/spoke.md:3:I33' | bash "$IDS")"
assert_eq "the id does not depend on the working directory" \
  "$(field "$(printf '%s\n' "$RUN1" | sed -n 1p)" 2)" "$(field "$RUN3" 2)"
assert_contains "the surface is repo-relative" "$RUN3" \
  $'\tskills/demo/reference/spoke.md=e:'

I33_BEFORE="$(field "$(printf '%s\n' "$RUN1" | sed -n 1p)" 2)"

# --- Case 2: an unrelated paragraph above the finding keeps its id -----------
cp "$REPO/skills/demo/reference/spoke.md" "$TEST_TMPDIR/spoke.orig"
{
  printf '# Spoke\n\nAn unrelated paragraph.\n\n'
  tail -n +3 "$TEST_TMPDIR/spoke.orig"
} >"$REPO/skills/demo/reference/spoke.md"
I33_SHIFTED="$(printf '%s\n' 'skills/demo/reference/spoke.md:5:I33' | ids)"
assert_eq "inserting an unrelated paragraph above an I33 opener keeps its id" \
  "$I33_BEFORE" "$(field "$I33_SHIFTED" 2)"

# --- Case 3: editing the I33 opener changes that finding's id ----------------
cp "$TEST_TMPDIR/spoke.orig" "$REPO/skills/demo/reference/spoke.md"
sed -i.bak 's/names a breaking change/ships a breaking change/' \
  "$REPO/skills/demo/reference/spoke.md"
I33_EDITED="$(printf '%s\n' 'skills/demo/reference/spoke.md:3:I33' | ids)"
if [[ "$(field "$I33_EDITED" 2)" != "$I33_BEFORE" ]]; then
  pass "editing the I33 opener changes that finding's id"
else
  fail "editing the I33 opener changes that finding's id" "id unchanged: $I33_BEFORE"
fi
assert_eq "the group survives the edit" \
  "$(field "$(printf '%s\n' "$RUN1" | sed -n 1p)" 3)" "$(field "$I33_EDITED" 3)"
cp "$TEST_TMPDIR/spoke.orig" "$REPO/skills/demo/reference/spoke.md"

# --- Case 4: an I15 conflict is one finding with two sites -------------------
FWD="$(printf '%s\n' 'skills/demo/SKILL.md:10|skills/demo/SKILL.md:14|I15' | ids)"
REV="$(printf '%s\n' 'skills/demo/SKILL.md:14|skills/demo/SKILL.md:10|I15' | ids)"
assert_eq "an I15 conflict met as (A, B) and (B, A) has one id" "$(field "$FWD" 2)" "$(field "$REV" 2)"
assert_eq "an I15 conflict carries two sites" "5" "$(printf '%s\n' "$FWD" | awk -F'\t' '{print NF}')"
REC="$(printf '%s\n' 'skills/demo/SKILL.md:10|skills/demo/SKILL.md:14|I15' | ids --records)"
assert_contains "the I15 record declares its claim pairwise" "$REC" '"pairwise":true'
if command -v python3 >/dev/null 2>&1; then
  assert_eq "the I15 record passes audit-pass's emitter guard" "ok" \
    "$(bash "$FI" validate-record --record "$REC" 2>&1)"
  ONE="$(printf '%s\n' 'skills/demo/reference/spoke.md:3:I33' | ids --records)"
  assert_eq "a single-site record passes audit-pass's emitter guard" "ok" \
    "$(bash "$FI" validate-record --record "$ONE" 2>&1)"
  assert_not_contains "a single-site record is not pairwise" "$ONE" "pairwise"
else
  echo "SKIP: python3 absent; the emitter-guard checks did not run" >&2
fi

# --- Case 5: anchors follow the heading path, and fences are not headings ----
SAME_TEXT_A="$(printf '%s\n' 'skills/demo/SKILL.md:10:I6' | ids)"
SAME_TEXT_B="$(printf '%s\n' 'skills/demo/reference/spoke.md:9:I6' | ids)"
anchor_a="$(field "$SAME_TEXT_A" 4)"
anchor_b="$(field "$SAME_TEXT_B" 4)"
if [[ "${anchor_a#*=}" != "${anchor_b#*=}" ]]; then
  pass "the same sentence under a different heading path, inside a fence, anchors differently"
else
  fail "the same sentence under a different heading path, inside a fence, anchors differently" \
    "both anchors are ${anchor_a#*=}"
fi
AFTER_FENCE="$(field "$(printf '%s\n' 'skills/demo/reference/spoke.md:12:I6' | ids)" 4)"
PLAIN="$(field "$(printf '%s\n' 'skills/demo/reference/plain.md:3:I6' | ids)" 4)"
assert_eq "a body line after the fence is anchored under # Spoke alone, not the fenced ## line" \
  "${PLAIN#*=}" "${AFTER_FENCE#*=}"
AFTER_COMMENT="$(field "$(printf '%s\n' 'skills/demo/reference/commented.md:7:I6' | ids)" 4)"
assert_eq "a heading-shaped line inside a block HTML comment is not in the heading path" \
  "${PLAIN#*=}" "${AFTER_COMMENT#*=}"
FM_A="$(printf '%s\n' 'skills/demo/SKILL.md:10:I6' | ids)"
sed -i.bak 's/^description: Demo skill\.$/description: Demo skill, reworded./' \
  "$REPO/skills/demo/SKILL.md"
FM_B="$(printf '%s\n' 'skills/demo/SKILL.md:10:I6' | ids)"
assert_eq "editing frontmatter keeps a body finding's id" "$(field "$FM_A" 2)" "$(field "$FM_B" 2)"

# --- Case 6: rows that cannot be identified are refused, never given an id ---
REFUSED="$(printf '%s\n' \
  'skills/demo/SKILL.md:999:I6' \
  'skills/demo/SKILL.md:10:I99' \
  'skills/demo/SKILL.md:10|skills/demo/SKILL.md:14|I6' \
  'skills/demo/SKILL.md:10:I15' \
  'skills/demo/SKILL.md:9:I6' \
  'not a row' | ids)"
assert_contains "a line past EOF is refused" "$REFUSED" $'skills/demo/SKILL.md:999:I6\tline-past-eof'
assert_contains "an id with no claim template is refused" "$REFUSED" $'I99\tno-claim-template'
assert_contains "a pairwise row for a single-site claim is refused" "$REFUSED" \
  $'I6\tpairwise-row-for-a-single-site-claim'
assert_contains "a single-site I15 row is refused" "$REFUSED" $'I15\tI15-requires-two-sites'
assert_contains "a blank line is refused" "$REFUSED" $'skills/demo/SKILL.md:9:I6\tblank-line'
assert_contains "a non-row is refused as unparsable" "$REFUSED" $'not a row\tunparsable-row'
assert_eq "every refused row prints exactly one line" "6" "$(printf '%s\n' "$REFUSED" | grep -c '^#REFUSED')"

OUTSIDE="$TEST_TMPDIR/outside.md"
printf 'Never do this.\n' >"$OUTSIDE"
OUT_ROW="$(printf '%s\n' "$OUTSIDE:1:I6" | (cd "$REPO" && HOME="$TEST_TMPDIR/nohome" bash "$IDS"))"
assert_contains "a surface outside the repository and home is refused" "$OUT_ROW" \
  "surface-outside-repository-and-home"
mkdir -p "$TEST_TMPDIR/home/.claude"
printf 'Never do this.\n' >"$TEST_TMPDIR/home/.claude/CLAUDE.md"
USER_ROW="$(printf '%s\n' "$TEST_TMPDIR/home/.claude/CLAUDE.md:1:I6" |
  (cd "$REPO" && HOME="$TEST_TMPDIR/home" bash "$IDS"))"
assert_contains "a user-scope surface takes the user: prefix" "$USER_ROW" $'\tuser:.claude/CLAUDE.md=e:'

# --- Case 6b: under $HOME only instruction-file shapes are surfaces ----------
H="$TEST_TMPDIR/home"
mkdir -p "$H/.claude/plugins/cache/p/1.0/hooks" "$H/.claude/plugins/cache/p/1.0/skills/y" \
  "$H/.claude/skills/x/reference" "$H/.claude/projects/x" "$H/projects" \
  "$H/notes/skills" "$H/shared" "$H/.ssh" "$H/cc-alt" "$H/plant"
for f in CLAUDE.md projects/AGENTS.md notes/style.md shared/rules.md .claude/settings.json \
  .claude/plugins/cache/p/1.0/hooks/hooks.json .claude/skills/x/reference/table.yaml \
  .claude/plugins/cache/p/1.0/skills/y/data.yaml notes/skills/pw.txt \
  .ssh/config .claude/.credentials.json \
  .claude/projects/x/t.jsonl .bashrc notes/settings.json cc-alt/settings.json; do
  printf 'Never do this.\n' >"$H/$f"
done
home_ids() { (cd "$REPO" && env -u CLAUDE_CONFIG_DIR HOME="$H" bash "$IDS"); }
surface_row() { printf '%s\n' "$H/$1:1:I6" | home_ids; }

for shape in CLAUDE.md projects/AGENTS.md notes/style.md .claude/settings.json \
  .claude/plugins/cache/p/1.0/hooks/hooks.json .claude/skills/x/reference/table.yaml \
  .claude/plugins/cache/p/1.0/skills/y/data.yaml; do
  assert_contains "an instruction file under home yields user:$shape" "$(surface_row "$shape")" \
    $'\tuser:'"$shape=e:"
done
for other in .ssh/config .claude/.credentials.json .claude/projects/x/t.jsonl .bashrc \
  notes/settings.json notes/skills/pw.txt cc-alt/settings.json; do
  assert_contains "a non-instruction file under home is refused: $other" "$(surface_row "$other")" \
    $'#REFUSED\t'"$H/$other:1:I6"$'\tsurface-not-an-instruction-file'
done
RELOCATED="$(printf '%s\n' "$H/cc-alt/settings.json:1:I6" |
  (cd "$REPO" && HOME="$H" CLAUDE_CONFIG_DIR="$H/cc-alt" bash "$IDS"))"
assert_contains "settings.json in a relocated CLAUDE_CONFIG_DIR is a surface" "$RELOCATED" \
  $'\tuser:cc-alt/settings.json=e:'

# Symlinks resolve to the physical file before the shape test.
ln -s "$H/shared/rules.md" "$H/link-b.md"
ln -s link-b.md "$H/link-a.md"
assert_contains "a symlink chain inside home resolves to its target's user: surface" \
  "$(surface_row link-a.md)" $'\tuser:shared/rules.md=e:'
ln -s "$H/shared/rules.md" "$REPO/skills/demo/reference/ext.md"
assert_contains "a repository symlink into home takes the target's user: surface" \
  "$(printf '%s\n' 'skills/demo/reference/ext.md:1:I6' | home_ids)" $'\tuser:shared/rules.md=e:'
ln -s reference/plain.md "$REPO/skills/demo/alias.md"
assert_contains "a symlink chain inside the repository keeps the repo-relative target" \
  "$(printf '%s\n' 'skills/demo/alias.md:3:I6' | home_ids)" $'\tskills/demo/reference/plain.md=e:'
ln -s "$H/.ssh/config" "$H/plant/CLAUDE.md"
assert_contains "a CLAUDE.md symlinked to a non-instruction file is refused" \
  "$(surface_row plant/CLAUDE.md)" $'\tsurface-not-an-instruction-file'
ln -s "$OUTSIDE" "$H/notes/out.md"
assert_contains "a symlink from home to a file outside home and the repo is refused" \
  "$(surface_row notes/out.md)" $'\tsurface-outside-repository-and-home'

# --- Case 7: the claim table mirrors the reference and the catalog -----------
script_table="$(sed -n 's/^  \(I[0-9][0-9]*\(-[a-f]\)\{0,1\}\)) echo "\([^"]*\)" ;;$/\1 \3/p' "$IDS" | LC_ALL=C sort)"
# shellcheck disable=SC2016 # the backticks are literal markdown code spans
ref_table="$(sed -n 's/^| \(I[0-9][0-9]*\(-[a-f]\)\{0,1\}\) | `\([^`]*\)` | [12] |$/\1 \3/p' \
  "$SKILL_DIR/reference/finding-identity.md" | LC_ALL=C sort)"
assert_eq "the script's claim table equals the reference's" "$ref_table" "$script_table"
catalog_ids="$(sed -n 's/^### \(I[0-9][0-9]*\):.*/\1/p' "$SKILL_DIR/reference/criteria.md" |
  awk -F'I' '$2 >= 6' | LC_ALL=C sort)"
missing=""
while IFS= read -r cid; do
  [[ -n "$cid" ]] || continue
  printf '%s\n' "$script_table" | grep -q "^$cid " || missing="$missing $cid"
done <<<"$catalog_ids"
assert_eq "every catalog check from I6 on has a claim template" "" "$missing"
while IFS=' ' read -r cid claim; do
  [[ "$claim" == "$cid."* && "$claim" != *" "* ]] ||
    fail "claim template for $cid is <id>.<slug> with no spaces" "$claim"
done <<<"$script_table"
pass "every claim template is <id>.<slug> with no spaces"

printf '\n'
if [[ "$FAILED" -gt 0 ]]; then
  printf '%d of %d checks FAILED.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
printf 'All %d checks passed.\n' "$CASE_NUM"
