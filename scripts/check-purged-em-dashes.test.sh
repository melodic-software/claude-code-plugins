#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-purged-em-dashes.sh"
DETECT="$SCRIPT_DIR/../plugins/ai-slop/skills/audit/scripts/detect.sh"
DETECT="$(cd "$(dirname "$DETECT")" && pwd)/$(basename "$DETECT")"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=test-git-helpers.sh
. "$SCRIPT_DIR/test-git-helpers.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

EM="$(printf '\xe2\x80\x94')"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
TMP=""
fixture_tree::build TMP --label purged-em-dashes

# run_cfg <detector-config> <fixture-root> <allowlist-relative-path> [args...]:
# sets OUT and RC. The config is a parameter because three of the cases below
# turn on what the SUT derives from a DIFFERENT tracked config than the default
# one; every other case goes through run(), which pins the default.
# Deliberately not wrapped in a command substitution of its own: that forks a
# subshell and the exit status never reaches the caller.
run_cfg() {
  local cfg="$1" root="$2" list="$3"
  shift 3
  OUT="$(
    EM_DASH_PURGED_ROOT="$root" \
      EM_DASH_PURGED_PATHS="$list" \
      EM_DASH_SLOP_CONFIG="$cfg" \
      EM_DASH_DETECT="$DETECT" \
      bash "$SUT" "$@" 2>&1
  )"
  RC=$?
}

run() { run_cfg "docs/conventions/ai-slop.yaml" "$@"; }

REPO="$TMP/repo"
mkdir -p "$REPO/docs/conventions" "$REPO/surface" "$REPO/other"
git_init_test_repo "$REPO"

write() { printf '%s\n' "$2" >"$REPO/$1"; }

write "docs/conventions/ai-slop.yaml" 'excluded_paths: []
disabled_rules: ["rule-em-dash", "rule-emoji-formatting"]'

write "surface/clean.md" 'A purged surface. It uses periods, and commas, instead.'

write "surface/dirty.md" "A surface with a regression ${EM} right here in prose."

printf '%s\n' \
  'Prose with no em dash.' \
  '' \
  '```text' \
  "code ${EM} fence" \
  '```' \
  '' \
  "ignored ${EM} line <!-- ai-slop-ignore:quoted source -->" \
  >"$REPO/surface/data.md"

write "other/unlisted.md" "Not on the allowlist ${EM} so not this gate's business."

# Nested under surface/ so `surface/*.md` must NOT match it: git `:(glob)`
# (and this gate's in-process replica) does not let `*` cross `/`. An em dash
# here would fail the globbed allowlist if the matcher ever went wildmatch.
mkdir -p "$REPO/surface/deep"
write "surface/deep/nested.md" "A nested regression ${EM} that surface/*.md must not see."

write "surface/other-tells.md" 'I hope this helps. It is important to note this, in order to keep the check cheap.'

printf '%s\n' \
  '<!-- ai-slop-ignore-file -->' \
  '' \
  "Wholly declined text ${EM} not this gate's business either." \
  >"$REPO/surface/marked.md"

write "docs/conventions/cfg-em-dash-allowed.yaml" 'excluded_paths: []
em_dash_allowed_paths: ["surface/dirty.md"]
disabled_rules: ["rule-em-dash"]'
write "docs/conventions/cfg-rule-allowed.yaml" 'excluded_paths: []
rule_allowed_paths:
  rule-em-dash: ["surface/dirty.md"]
disabled_rules: ["rule-em-dash"]'
write "docs/conventions/cfg-excluded.yaml" 'excluded_paths: ["surface/dirty.md"]
disabled_rules: ["rule-em-dash"]'
write "docs/conventions/cfg-refused.yaml" '{"excluded_paths":[],"disabled_rules":["rule-em-dash"]}'

mkdir -p "$REPO/edge/b.c" "$REPO/edge/x/deep" "$REPO/edge/y"
for f in edge/.dotted.md edge/b.c/inner.md 'edge/[lit].md' edge/x/a.md edge/y/a.md edge/x/deep/a.md; do
  write "$f" 'Clean edge-case surface.'
done

list() {
  local name="$1"
  shift
  printf '%s\n' "$@" >"$REPO/$name.txt"
}

list "only-clean" 'surface/clean.md'
list "other-tells" 'surface/clean.md' 'surface/other-tells.md'
list "marked" 'surface/clean.md' 'surface/marked.md'
list "clean-and-data" 'surface/clean.md' 'surface/data.md'
list "with-dirty" 'surface/clean.md' 'surface/dirty.md'
list "globbed" 'surface/*.md'
list "stale" 'surface/clean.md' 'surface/gone.md'
list "empty" '# only a comment' ''
list "commented" 'surface/clean.md   # the surface purged in this fixture'
list "edge" 'edge/.dotted.md' 'edge/*.md' 'edge/b.?/*.md' 'edge/[xy]/a.md' \
  'edge/\[lit\].md' 'edge/*/a.md' 'edge/*/*/a.md' 'edge/gone/*.md'

git_test_config "$REPO" add -A
git_test_config "$REPO" commit -qm fixture

run "$REPO" "only-clean.txt"
clean_rc=$RC clean_out="$OUT"
if ((clean_rc == 0)); then
  ok "clean surface passes"
else
  fail "clean surface passes (rc=$clean_rc): $clean_out"
fi
if [[ "$clean_out" != *"unlisted.md"* ]] &&
  [[ "$clean_out" == *"1 declared paths, 1 files scanned"* ]]; then
  ok "a file outside the allowlist is not scanned"
else
  fail "a file outside the allowlist is not scanned: $clean_out"
fi

run "$REPO" "with-dirty.txt"
if ((RC == 1)); then
  ok "seeded em dash fails the gate"
else
  fail "seeded em dash fails the gate (rc=$RC, want 1): $OUT"
fi
if [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "the failure names the offending file"
else
  fail "the failure names the offending file: $OUT"
fi
if [[ "$OUT" != *"surface/clean.md:"* ]]; then
  ok "the failure does not implicate the clean file"
else
  fail "the failure does not implicate the clean file: $OUT"
fi
if [[ "$OUT" != *"config layer did not take effect"* ]]; then
  ok "the derived config layer takes effect"
else
  fail "the derived config layer takes effect: $OUT"
fi
if [[ "$OUT" != *"expected only rule-em-dash enabled"* ]]; then
  ok "the one-rule liveness guard is not what failed the seeded violation"
else
  fail "the one-rule liveness guard is not what failed the seeded violation: $OUT"
fi

run "$REPO" "clean-and-data.txt"
if ((RC == 0)); then
  ok "em dashes in a code fence and an ignore-marked line do not fire"
else
  fail "em dashes in a code fence and an ignore-marked line do not fire (rc=$RC): $OUT"
fi

run "$REPO" "other-tells.txt"
if ((RC == 0)) && [[ "$OUT" == *"2 declared paths, 2 files scanned"* ]]; then
  ok "other-rule tells on a declared path do not fail a one-rule run"
else
  fail "other-rule tells on a declared path do not fail a one-rule run (rc=$RC): $OUT"
fi

run "$REPO" "marked.txt"
if ((RC == 0)); then
  ok "a whole-file ignore marker does not break the coverage assertion"
else
  fail "a whole-file ignore marker does not break the coverage assertion (rc=$RC): $OUT"
fi

run "$REPO" "globbed.txt"
if ((RC == 1)) && [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "a glob entry expands to every matching tracked file"
else
  fail "a glob entry expands to every matching tracked file (rc=$RC): $OUT"
fi
if [[ "$OUT" != *"surface/deep/nested.md"* ]]; then
  ok "a * glob does not match across a directory separator"
else
  fail "a * glob does not match across a directory separator: $OUT"
fi

run "$REPO" "stale.txt"
if ((RC == 1)) && [[ "$OUT" == *"stale allowlist entry"* ]] && [[ "$OUT" == *"surface/gone.md"* ]]; then
  ok "an entry matching no tracked file fails as stale"
else
  fail "an entry matching no tracked file fails as stale (rc=$RC): $OUT"
fi

run "$REPO" "edge.txt" --list
want=(
  'ok     edge/.dotted.md (1 files)'
  'ok     edge/*.md (2 files)'
  'ok     edge/b.?/*.md (1 files)'
  'ok     edge/[xy]/a.md (2 files)'
  'ok     edge/\[lit\].md (1 files)'
  'ok     edge/*/a.md (2 files)'
  'ok     edge/*/*/a.md (1 files)'
  'STALE  edge/gone/*.md'
)
edge_ok=1
for line in "${want[@]}"; do
  [[ "$OUT" == *"$line"* ]] || edge_ok=0
done
if ((RC == 1 && edge_ok)); then
  ok "glob entries attribute dots, brackets and single-star segments correctly"
else
  fail "glob entries attribute dots, brackets and single-star segments correctly (rc=$RC): $OUT"
fi

run "$REPO" "empty.txt"
if ((RC == 2)); then
  ok "an allowlist with no active entry is exit 2, not a clean run"
else
  fail "an allowlist with no active entry is exit 2 (rc=$RC): $OUT"
fi

run "$REPO" "missing.txt"
if ((RC == 2)); then
  ok "a missing allowlist is exit 2"
else
  fail "a missing allowlist is exit 2 (rc=$RC): $OUT"
fi

run "$REPO" "commented.txt"
if ((RC == 0)); then
  ok "an inline comment is stripped from an entry"
else
  fail "an inline comment is stripped from an entry (rc=$RC): $OUT"
fi

run "$REPO" "only-clean.txt" --list
if ((RC == 0)) && [[ "$OUT" == *"surface/clean.md"* ]]; then
  ok "--list reports each declared entry"
else
  fail "--list reports each declared entry (rc=$RC): $OUT"
fi
run "$REPO" "with-dirty.txt" --list
if ((RC == 0)) && [[ "$OUT" != *"no em dashes"* ]] && [[ "$OUT" != *"em-dash line(s)"* ]]; then
  ok "--list expands the allowlist without running the detector"
else
  fail "--list expands the allowlist without running the detector (rc=$RC): $OUT"
fi

run "$REPO" "only-clean.txt" --bogus
if ((RC == 2)); then
  ok "an unknown argument is exit 2"
else
  fail "an unknown argument is exit 2 (rc=$RC): $OUT"
fi

OUT="$(EM_DASH_PURGED_ROOT="$REPO" EM_DASH_PURGED_PATHS="only-clean.txt" \
  EM_DASH_SLOP_CONFIG="does-not-exist.yaml" EM_DASH_DETECT="$DETECT" \
  bash "$SUT" 2>&1)"
RC=$?
if ((RC == 2)); then
  ok "an unreadable detector config is exit 2"
else
  fail "an unreadable detector config is exit 2 (rc=$RC): $OUT"
fi

run_cfg "docs/conventions/cfg-refused.yaml" "$REPO" "only-clean.txt"
if ((RC == 2)) && [[ "$OUT" == *"could not derive the detector config"* ]]; then
  ok "a detector config the YAML parser refuses is exit 2"
else
  fail "a detector config the YAML parser refuses is exit 2 (rc=$RC): $OUT"
fi

run_cfg "docs/conventions/cfg-em-dash-allowed.yaml" "$REPO" "with-dirty.txt"
if ((RC == 1)) && [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "em_dash_allowed_paths does not exempt a declared path"
else
  fail "em_dash_allowed_paths does not exempt a declared path (rc=$RC, want 1): $OUT"
fi

run_cfg "docs/conventions/cfg-rule-allowed.yaml" "$REPO" "with-dirty.txt"
if ((RC == 1)) && [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "rule_allowed_paths[rule-em-dash] does not exempt a declared path"
else
  fail "rule_allowed_paths[rule-em-dash] does not exempt a declared path (rc=$RC, want 1): $OUT"
fi

run_cfg "docs/conventions/cfg-excluded.yaml" "$REPO" "with-dirty.txt"
if ((RC == 1)) && [[ "$OUT" == *"were NOT checked"* ]] && [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "a declared path the config excludes fails the gate and is named"
else
  fail "a declared path the config excludes fails the gate and is named (rc=$RC, want 1): $OUT"
fi
if [[ "$OUT" != *"em-dash line(s)"* ]]; then
  ok "the excluded path fails as unchecked rather than as a finding"
else
  fail "the excluded path fails as unchecked rather than as a finding: $OUT"
fi

test_harness::report
