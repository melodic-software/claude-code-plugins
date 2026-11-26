#!/usr/bin/env bash
set -uo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-silent-revert.sh"
FENCE3=$'\x60\x60\x60'
FENCE4=$'\x60\x60\x60\x60'
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

repo=""

MK_REPO_FAILED="$SELF_DIR/.mk-repo-failed-this-path-does-not-exist"
mk_repo() {
  local -n _mk_repo_out="$1"
  local dir
  if ! fixture_tree::build dir --sut "$SCRIPT" --git >/dev/null; then
    _mk_repo_out="$MK_REPO_FAILED"
    return 0
  fi
  printf 'base line %s\n' $(seq 1 5) >"$dir/feature.txt"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm "base"
  _mk_repo_out="$dir"
}

add_block() {
  local repo="$1" file="$2" count="$3" tag="$4" i
  for i in $(seq 1 "$count"); do
    printf 'the %s guard rejects a relocation outside the session root, case %s\n' \
      "$tag" "$i" >>"$repo/$file"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the $tag guard"
}

drop_block() {
  local repo="$1" file="$2" tag="$3" msg="$4"
  grep -v "the $tag guard rejects" "$repo/$file" >"$repo/$file.tmp" || true
  mv "$repo/$file.tmp" "$repo/$file"
  printf 'unrelated work from the stale branch\n' >>"$repo/$file"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "$msg"
}

PIN_OLD=07df326dec55d0740f9b0dd885a2d09c09620deb
PIN_NEW=3f2a9c1e5d7b4a6f8e0c2d1b9a7f5e3c1d0b8a6e

add_pins() {
  local repo="$1" file="$2" count="$3" sha="$4" i
  for i in $(seq 1 "$count"); do
    printf '      uses: melodic-software/ci-workflows/.github/workflows/job-%s.yml@%s # v0.82.0\n' \
      "$i" "$sha" >>"$repo/$file"
  done
}

repin() {
  local repo="$1" file="$2"
  sed "s/$3 # v0\.82\.0/$4 # v0.82.1/" "$repo/$file" >"$repo/$file.tmp"
  mv "$repo/$file.tmp" "$repo/$file"
}

filler() {
  local repo="$1" n="$2" i
  for i in $(seq 1 "$n"); do
    printf 'filler %s\n' "$i" >>"$repo/other.txt"
    git_test_config "$repo" add -A >/dev/null
    git_test_config "$repo" commit -qm "chore: unrelated change $i"
  done
}

RC=0
OUT=""
run_canary() {
  local repo="$1"
  shift
  local script="${CANARY_SCRIPT:-scripts/check-silent-revert.sh}"
  if [[ -z "$repo" || ! -d "$repo" || ! -f "$repo/$script" ]]; then
    fail "fixture setup failed: no usable repository at '${repo:-<empty>}' (wanted $script) -- the harness could not build its fixture, so nothing was tested"
    RC=99
    OUT="fixture setup failed"
    return 0
  fi
  local tmp
  tmp="$(mktemp "$TMP/x.XXXX")"
  (cd "$repo" && bash "$script" "$@") >"$tmp" 2>&1
  RC=$?
  OUT="$(cat "$tmp")"
  rm -f "$tmp"
}

t_fires_on_silent_revert() {
  local repo out
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  filler "$repo" 2
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$out"; then
    ok "fires when a merge drops a block a recent commit had added"
  else
    fail "expected a finding (rc=1), got rc=$RC: $out"
  fi
}

t_finding_is_actionable() {
  local repo out culprit remover
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse --short=9 HEAD)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  remover="$(git -C "$repo" rev-parse --short=9 HEAD)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"

  local missing=""
  grep -q "$culprit" <<<"$out" || missing="$missing adding-commit"
  grep -q "$remover" <<<"$out" || missing="$missing removing-commit"
  grep -q 'feature.txt' <<<"$out" || missing="$missing file-name"
  grep -q 'the alpha guard rejects' <<<"$out" || missing="$missing removed-content"
  if [[ -z "$missing" ]]; then
    ok "finding names the content, the remover, the adder, and the file"
  else
    fail "finding omitted:$missing -- $out"
  fi
}

t_quiet_below_threshold() {
  local repo out
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "chore: trim (#99)"
  SILENT_REVERT_THRESHOLD=500 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "stays quiet when the removal is below the volume threshold"
  else
    fail "expected clean below threshold, got rc=$RC: $out"
  fi
}

t_quiet_outside_recency_window() {
  local repo out
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  filler "$repo" 6
  drop_block "$repo" feature.txt alpha "chore: remove old guard (#99)"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_WINDOW=3 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "stays quiet when the removed content is older than the recency window"
  else
    fail "expected clean outside window, got rc=$RC: $out"
  fi
}

t_does_not_sum_across_culprits() {
  local repo out
  mk_repo repo
  add_block "$repo" feature.txt 18 alpha
  add_block "$repo" feature.txt 18 beta
  grep -v 'guard rejects' "$repo/feature.txt" >"$repo/f.tmp" || true
  mv "$repo/f.tmp" "$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: tidy (#99)"
  SILENT_REVERT_THRESHOLD=25 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "does not sum unrelated culprits into one finding (36 lines, 18 each, threshold 25)"
  else
    fail "expected clean; culprits must be counted separately: $out"
  fi
}

t_pure_pin_bump_is_not_a_removal() {
  local repo
  mk_repo repo
  add_pins "$repo" feature.txt 40 "$PIN_OLD"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "ci: re-pin ci-workflows to v0.82.0"
  repin "$repo" feature.txt "$PIN_OLD" "$PIN_NEW"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "ci: re-pin ci-workflows to v0.82.1"
  SILENT_REVERT_THRESHOLD=1 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]] && grep -q '^ok ' <<<"$OUT"; then
    ok "a pin bump that changes only the SHA and version comment of 40 recent lines scores 0 (threshold 1)"
  else
    fail "expected a pure pin bump to attribute nothing, got rc=$RC: $OUT"
  fi
}

t_real_removal_beside_a_pin_bump_still_fires() {
  local repo
  mk_repo repo
  add_pins "$repo" feature.txt 40 "$PIN_OLD"
  add_block "$repo" feature.txt 30 alpha
  repin "$repo" feature.txt "$PIN_OLD" "$PIN_NEW"
  grep -vE '/job-([1-9]|10)\.yml@' "$repo/feature.txt" >"$repo/f.tmp" || true
  mv "$repo/f.tmp" "$repo/feature.txt"
  drop_block "$repo" feature.txt alpha "ci: re-pin ci-workflows to v0.82.1"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'lines lost   40  ' <<<"$OUT"; then
    ok "a pin bump beside a real removal counts the 30 dropped lines and 10 dropped pins, not the 30 re-pinned ones"
  else
    fail "expected one 40-line finding (30 block lines + 10 removed pins), got rc=$RC: $OUT"
  fi
}

t_sha_line_with_changed_free_comment_still_fires() {
  local repo i
  mk_repo repo
  for i in $(seq 1 30); do
    printf 'git checkout %s  # keep: needed for the relocation regression\n' \
      "$PIN_OLD" >>"$repo/feature.txt"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: pin the relocation fixtures"
  sed "s/$PIN_OLD  # keep: needed for the relocation regression/$PIN_NEW  # anything/" \
    "$repo/feature.txt" >"$repo/f.tmp"
  mv "$repo/f.tmp" "$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: bump fixture pins"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'lines lost   30  ' <<<"$OUT"; then
    ok "a SHA line whose free-text comment changed counts as removed (30 lines, threshold 20)"
  else
    fail "expected one 30-line finding; only a version-tag comment may fold, got rc=$RC: $OUT"
  fi
}

t_rename_is_not_a_removal() {
  local repo out
  mk_repo repo
  add_block "$repo" moved.txt 60 alpha
  git_test_config "$repo" mv moved.txt relocated.txt >/dev/null
  git_test_config "$repo" commit -qm "refactor: relocate the guard (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "renaming a file a recent commit added is not reported as a removal"
  else
    fail "a pure rename must not fire, rc=$RC: $out"
  fi
}

py_function() {
  local name="$1" i
  printf 'def %s():\n' "$name"
  for i in $(seq 1 "$2"); do
    printf '    the %s guard rejects a relocation outside the session root, case %s\n' "${3:-$name}" "$i"
  done
}

move_py_function() {
  local repo="$1" name="$2" dest="$3"
  awk -v d="def $name():" '$0 == d { on = 1; print; next } on && /^    / { print; next } { on = 0 }' \
    "$repo/feature.py" >>"$repo/$dest"
}

drop_py_functions() {
  awk '/^def / { on = 1; next } on && /^    / { next } { on = 0; print }' "$1/feature.py" >"$1/feature.py.tmp"
  mv "$1/feature.py.tmp" "$1/feature.py"
}

t_cross_file_move_is_not_a_removal() {
  local repo sink
  mk_repo repo
  { printf 'import os\n\n'; py_function alpha_guard 40; } >"$repo/feature.py"
  commit_all "$repo" "feat: add the alpha guard"
  move_py_function "$repo" alpha_guard helpers.py
  drop_py_functions "$repo"
  commit_all "$repo" "refactor: extract the alpha guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]] && [[ ! -s "$sink" ]] && grep -q '^ok ' <<<"$OUT"; then
    ok "moving a 41-line function into a new file in the same commit is not a removal (threshold 20)"
  else
    fail "a cross-file move must report ok, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_top_level_lines_pasted_without_their_run_still_fire() {
  local repo sink culprit
  mk_repo repo
  printf 'an existing helper line that stays where it is\n' >"$repo/helpers.txt"
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  grep 'the alpha guard rejects' "$repo/feature.txt" >>"$repo/helpers.txt"
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "refactor: tidy the alpha guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$OUT" &&
    [[ "$(cat "$sink")" == "$culprit 40" ]]; then
    ok "40 top-level lines pasted into another existing file without the rest of their run still fire"
  else
    fail "want one 40-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

MD_HEADING='## The alpha guard and its relocation rules'

add_md_section() {
  local repo="$1" i
  {
    printf '## Overview\n\nan overview line that stays where it is\n\n%s\n\n' "$MD_HEADING"
    for i in $(seq 1 40); do
      printf 'the alpha guard rejects a relocation outside the session root, case %s\n' "$i"
    done
  } >"$repo/doc.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "docs: add the alpha guard section"
}

t_markdown_body_pasted_without_its_heading_still_fires() {
  local repo sink culprit
  mk_repo repo
  add_md_section "$repo"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  grep 'the alpha guard rejects' "$repo/doc.md" >"$repo/alpha.md"
  grep -v 'the alpha guard rejects' "$repo/doc.md" >"$repo/doc.md.tmp" || true
  mv "$repo/doc.md.tmp" "$repo/doc.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "docs: tidy the alpha guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$OUT" &&
    [[ "$(cat "$sink")" == "$culprit 40" ]]; then
    ok "a Markdown section body pasted into a new file without its heading still fires on all 40 lines"
  else
    fail "want one 40-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_markdown_section_moved_with_its_heading_is_not_a_removal() {
  local repo sink
  mk_repo repo
  add_md_section "$repo"
  sed -n "/^$MD_HEADING\$/,\$p" "$repo/doc.md" >"$repo/alpha.md"
  sed "/^$MD_HEADING\$/,\$d" "$repo/doc.md" >"$repo/doc.md.tmp"
  mv "$repo/doc.md.tmp" "$repo/doc.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "docs: move the alpha guard section (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]] && [[ ! -s "$sink" ]] && grep -q '^ok ' <<<"$OUT"; then
    ok "a Markdown section moved to a new file with its heading is not a removal (threshold 20)"
  else
    fail "a Markdown section move must report ok, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_markdown_body_pasted_under_a_copied_heading_still_fires() {
  local repo sink culprit
  mk_repo repo
  add_md_section "$repo"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  sed -n "/^$MD_HEADING\$/,\$p" "$repo/doc.md" >"$repo/alpha.md"
  grep -v 'the alpha guard rejects' "$repo/doc.md" >"$repo/doc.md.tmp" || true
  mv "$repo/doc.md.tmp" "$repo/doc.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "docs: tidy the alpha guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$OUT" &&
    [[ "$(cat "$sink")" == "$culprit 40" ]]; then
    ok "a Markdown section body pasted under a copy of its heading, the original heading kept, still fires on all 40 lines"
  else
    fail "want one 40-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_top_level_run_split_across_two_paths_still_fires() {
  local repo sink culprit
  mk_repo repo
  printf '\n' >>"$repo/feature.txt"
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  grep -E 'case ([1-9]|1[0-9]|20)$' "$repo/feature.txt" >"$repo/helpers-a.txt"
  grep -E 'case (2[1-9]|3[0-9]|40)$' "$repo/feature.txt" >"$repo/helpers-b.txt"
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "refactor: split the alpha guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$OUT" &&
    [[ "$(cat "$sink")" == "$culprit 40" ]]; then
    ok "a 40-line top-level run split across two new files still fires on all 40 lines"
  else
    fail "want one 40-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

FIRST_HALF='case ([1-9]|1[0-9]|20)$'
SECOND_HALF='case (2[1-9]|3[0-9]|40)$'

guard_lines() {
  local prefix="$1" i
  for i in $(seq 1 40); do
    printf '%sthe alpha guard rejects a relocation outside the session root, case %s\n' "$prefix" "$i"
  done
}

expect_finding() {
  local repo="$1" culprit="$2" count="$3" what="$4" sink
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$OUT" &&
    [[ "$(cat "$sink")" == "$culprit $count" ]]; then
    ok "$what"
  else
    fail "$what: want one $count-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

commit_all() {
  git_test_config "$1" add -A >/dev/null
  git_test_config "$1" commit -qm "$2"
}

split_md_section() {
  local repo heading_in_b="$1" culprit
  mk_repo repo
  add_md_section "$repo"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  {
    printf '%s\n\n' "$MD_HEADING"
    grep -E "$FIRST_HALF" "$repo/doc.md"
  } >"$repo/alpha-a.md"
  {
    [[ "$heading_in_b" = yes ]] && printf '%s\n\n' "$MD_HEADING"
    grep -E "$SECOND_HALF" "$repo/doc.md"
  } >"$repo/alpha-b.md"
  sed "/^$MD_HEADING\$/,\$d" "$repo/doc.md" >"$repo/doc.md.tmp"
  mv "$repo/doc.md.tmp" "$repo/doc.md"
  commit_all "$repo" "docs: split the alpha guard section (#99)"
  expect_finding "$repo" "$culprit" 42 "$2"
}

t_markdown_section_split_across_two_paths_still_fires() {
  split_md_section no "a Markdown section split across two new files fires on the whole 42-line section"
}

t_markdown_section_split_with_a_copied_heading_still_fires() {
  split_md_section yes "a Markdown section split across two new files, each with a copy of its heading, fires on the whole 42-line section"
}

t_indented_chain_split_with_a_copied_chain_still_fires() {
  local repo culprit
  mk_repo repo
  {
    printf '\nparent:\n  child:\n'
    guard_lines '    '
  } >>"$repo/feature.txt"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  { printf 'parent:\n  child:\n'; grep -E "$FIRST_HALF" "$repo/feature.txt"; } >"$repo/a.txt"
  { printf 'parent:\n  child:\n'; grep -E "$SECOND_HALF" "$repo/feature.txt"; } >"$repo/b.txt"
  grep -vE '^(parent:|  child:|    the alpha guard)' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "refactor: split the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 42 \
    "an indented block split across two new files, each with a copy of its header chain, fires on all 42 lines"
}

t_markdown_body_under_an_unrecognized_heading_still_fires() {
  local repo culprit heading
  for heading in $'Actual heading\n==============' '  ## retained heading'; do
    mk_repo repo
    { printf '%s\n\n' "$heading"; guard_lines ''; printf '\n# tail\n'; } >"$repo/doc.md"
    commit_all "$repo" "docs: add the alpha guard"
    culprit="$(git -C "$repo" rev-parse HEAD)"
    grep 'the alpha guard rejects' "$repo/doc.md" >"$repo/a.txt"
    grep -v 'the alpha guard rejects' "$repo/doc.md" >"$repo/doc.md.tmp" || true
    mv "$repo/doc.md.tmp" "$repo/doc.md"
    commit_all "$repo" "docs: tidy the alpha guard (#99)"
    expect_finding "$repo" "$culprit" 40 \
      "a Markdown body moved out from under a retained '${heading%%$'\n'*}' heading still fires on all 40 lines"
  done
}

t_top_level_run_reordered_in_its_destination_still_fires() {
  local repo culprit
  mk_repo repo
  { printf '\n'; guard_lines ''; printf '\ntail\n'; } >>"$repo/feature.txt"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  {
    grep -E "$SECOND_HALF" "$repo/feature.txt"
    printf '\n'
    grep -E "$FIRST_HALF" "$repo/feature.txt"
  } >"$repo/a.txt"
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "refactor: move the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 40 "a top-level run re-added out of order in one new file still fires on all 40 lines"
}

t_fenced_body_pasted_without_its_fences_still_fires() {
  local repo culprit
  mk_repo repo
  {
    printf 'old\n## h\n```text\n'
    guard_lines ''
    printf '```\n# tail\n'
  } >"$repo/doc.md"
  commit_all "$repo" "docs: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  { printf '## h\n'; grep 'the alpha guard rejects' "$repo/doc.md"; } >"$repo/a.txt"
  printf 'old\n# tail\n' >"$repo/doc.md"
  commit_all "$repo" "docs: move the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 43 "a fenced Markdown body pasted with its heading but without its fences still fires on all 43 lines"
}

t_duplicate_lines_need_their_own_copies_to_move() {
  local repo culprit
  mk_repo repo
  { printf '\nparent:\nparent:\n'; guard_lines ''; printf '\ntail\n'; } >>"$repo/feature.txt"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  { printf 'parent:\n'; grep 'the alpha guard rejects' "$repo/feature.txt"; } >"$repo/a.txt"
  grep -vE '^(parent:|the alpha guard)' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "refactor: move the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 42 "a run with two identical lines re-added with one copy of them still fires on all 42 lines"
}

tag_lines() {
  local tag="$1" i
  for i in $(seq 1 "$2"); do
    printf 'the %s guard rejects a relocation outside the session root, case %s\n' "$tag" "$i"
  done
}

t_whole_block_moved_into_an_existing_file_still_fires() {
  local repo culprit
  mk_repo repo
  printf 'existing_helper() { :; }\n' >"$repo/lib.sh"
  add_function "$repo"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  sed -n '/^alpha_guard() {$/,/^}$/p' "$repo/feature.txt" >>"$repo/lib.sh"
  sed '/^alpha_guard() {$/,/^}$/d' "$repo/feature.txt" >"$repo/feature.txt.tmp"
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "refactor: move the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 42 "a whole function moved into a file that already existed still fires on all 42 lines"
}

t_recent_move_reverted_to_its_old_home_still_fires() {
  local repo culprit
  mk_repo repo
  guard_lines '' >"$repo/old-home.txt"
  printf '\n' >>"$repo/feature.txt"
  commit_all "$repo" "feat: add the alpha guard"
  cat "$repo/old-home.txt" >>"$repo/feature.txt"
  rm "$repo/old-home.txt"
  commit_all "$repo" "refactor: move the alpha guard into feature.txt (#98)"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  grep 'the alpha guard rejects' "$repo/feature.txt" >"$repo/old-home.txt"
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "feat: unrelated work from a stale branch (#99)"
  expect_finding "$repo" "$culprit" 40 \
    "a stale squash restoring a block to the path a recent commit moved it from still fires on all 40 lines"
}

t_block_moved_into_a_changes_fragment_still_fires() {
  local repo culprit
  mk_repo repo
  mkdir -p "$repo/plugins/foo" "$repo/.changes/foo"
  printf '# Changelog\n' >"$repo/plugins/foo/CHANGELOG.md"
  { printf '\n'; guard_lines ''; } >>"$repo/feature.txt"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  { printf -- '---\nbump: none\n---\n\n'; grep 'the alpha guard rejects' "$repo/feature.txt"; } \
    >"$repo/.changes/foo/notes.md"
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "chore: stage the notes (#99)"
  expect_finding "$repo" "$culprit" 40 "a block moved into a new .changes fragment a release would delete still fires on all 40 lines"
}

t_markdown_body_under_no_atx_heading_still_fires() {
  local repo culprit heading
  for heading in '**The alpha guard**' '<h2>The alpha guard</h2>' $'Actual heading\r\n==============\r'; do
    mk_repo repo
    if [[ "$heading" == *$'\r' ]]; then
      { printf '%s\n\r\n' "$heading"; guard_lines '' | sed 's/$/\r/'; printf '\r\n# tail\r\n'; } >"$repo/doc.md"
    else
      { printf '%s\n\n' "$heading"; guard_lines ''; printf '\n**Other**\n\nother text that stays where it is\n'; } >"$repo/doc.md"
    fi
    commit_all "$repo" "docs: add the alpha guard"
    culprit="$(git -C "$repo" rev-parse HEAD)"
    grep 'the alpha guard rejects' "$repo/doc.md" >"$repo/alpha.md"
    grep -v 'the alpha guard rejects' "$repo/doc.md" >"$repo/doc.md.tmp" || true
    mv "$repo/doc.md.tmp" "$repo/doc.md"
    commit_all "$repo" "docs: tidy the alpha guard (#99)"
    expect_finding "$repo" "$culprit" 40 \
      "a Markdown body under '${heading%%[$'\r\n']*}', with no ATX heading, moved to a new file still fires on all 40 lines"
  done
}

t_markdown_after_a_nested_fence_still_fires() {
  local repo culprit
  mk_repo repo
  {
    printf '# Guide\n\n## Usage\n\nan intro line under usage that stays where it is\n\n'
    printf '%smarkdown\n%sbash\n\n# configure the alpha guard before the first run\n%s\n%s\n\n' "$FENCE4" "$FENCE3" "$FENCE3" "$FENCE4"
    guard_lines ''
    printf '\n## Next section\n\nnext section text that also moves along\n'
  } >"$repo/doc.md"
  commit_all "$repo" "docs: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  sed -n '/^# configure the alpha guard/,$p' "$repo/doc.md" >"$repo/moved.md"
  sed '/^# configure the alpha guard/,$d' "$repo/doc.md" >"$repo/doc.md.tmp"
  mv "$repo/doc.md.tmp" "$repo/doc.md"
  commit_all "$repo" "docs: split the guide (#99)"
  expect_finding "$repo" "$culprit" 48 \
    "Markdown after a four-backtick fence, moved from a fake heading inside it to a new file, still fires on all 48 lines"
}

t_single_lines_scattered_to_new_files_still_fire() {
  local repo culprit i=0 line
  mk_repo repo
  { printf '\n'; guard_lines '' | awk '{ print; print "" }'; } >>"$repo/feature.txt"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  while IFS= read -r line; do
    i=$((i + 1))
    printf '%s\n' "$line" >"$repo/fragment-$i.txt"
  done < <(grep 'the alpha guard rejects' "$repo/feature.txt")
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "refactor: scatter the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 40 "40 blank-separated lines moved one per new file still fire on all 40 lines"
}

t_string_body_moved_out_of_a_deleted_function_still_fires() {
  local repo culprit
  mk_repo repo
  {
    printf '\nemit_alpha_template() {\n  cat <<'"'"'EOF'"'"'\nfirst template paragraph line long enough to count\n\n'
    guard_lines ''
    printf '\nEOF\n}\n'
  } >>"$repo/feature.sh"
  commit_all "$repo" "feat: add the alpha template"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  guard_lines '' >"$repo/template.txt"
  printf 'base line\n' >"$repo/feature.sh"
  commit_all "$repo" "refactor: tidy the alpha template (#99)"
  expect_finding "$repo" "$culprit" 48 \
    "a column-0 heredoc body moved to a new file while its function is deleted still fires on all 48 lines"
}

t_function_pasted_inside_another_function_still_fires() {
  local repo culprit
  mk_repo repo
  py_function alpha_guard 40 >"$repo/feature.py"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  {
    printf 'def beta():\n    beta_setup_step_one_that_stays = 1\n'
    py_function alpha_guard 40
    printf '    beta_setup_step_two_that_stays = 2\n'
  } >"$repo/helpers.py"
  printf 'import os\n' >"$repo/feature.py"
  commit_all "$repo" "refactor: move the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 41 "a function pasted into another function's body in a new file still fires on all 41 lines"
}

t_function_moved_into_a_disabled_heredoc_still_fires() {
  local repo culprit
  mk_repo repo
  add_function "$repo"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  {
    printf "existing() { :; }\n: <<'DISABLED'\n"
    sed -n '/^alpha_guard() {$/,/^}$/p' "$repo/feature.txt"
    printf 'DISABLED\n'
  } >"$repo/lib.sh"
  sed '/^alpha_guard() {$/,/^}$/d' "$repo/feature.txt" >"$repo/feature.txt.tmp"
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "refactor: move the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 42 "a function moved into a disabled heredoc in a new file still fires on all 42 lines"
}

t_markdown_section_moved_into_a_wrapper_still_fires() {
  local repo culprit wrapper
  for wrapper in '<!--|-->' "${FENCE3}markdown|${FENCE3}"; do
    mk_repo repo
    add_md_section "$repo"
    culprit="$(git -C "$repo" rev-parse HEAD)"
    {
      printf '# Archive\n\n%s\n' "${wrapper%|*}"
      sed -n "/^$MD_HEADING\$/,\$p" "$repo/doc.md"
      printf '%s\n' "${wrapper#*|}"
    } >"$repo/archive.md"
    sed "/^$MD_HEADING\$/,\$d" "$repo/doc.md" >"$repo/doc.md.tmp"
    mv "$repo/doc.md.tmp" "$repo/doc.md"
    commit_all "$repo" "docs: archive the alpha guard (#99)"
    expect_finding "$repo" "$culprit" 42 \
      "a Markdown section moved inside a '${wrapper%|*}' wrapper in a new file still fires on all 42 lines"
  done
}

t_function_moved_into_a_changelog_shaped_path_still_fires() {
  local repo culprit name
  for name in docs/changelog.md HISTORY.md CHANGELOG.MD docs/.changes/foo/notes.md plugins/foo/CHANGES.md; do
    mk_repo repo
    py_function alpha_guard 40 >"$repo/feature.py"
    commit_all "$repo" "feat: add the alpha guard"
    culprit="$(git -C "$repo" rev-parse HEAD)"
    mkdir -p "$repo/$(dirname "$name")"
    move_py_function "$repo" alpha_guard "$name"
    printf 'import os\n' >"$repo/feature.py"
    commit_all "$repo" "chore: record the alpha guard (#99)"
    expect_finding "$repo" "$culprit" 41 "a function moved into a new $name still fires on all 41 lines"
  done
}

t_flat_paragraphs_moved_to_new_files_still_fire() {
  local repo culprit
  mk_repo repo
  { printf '\n'; guard_lines '' | head -n 39 | awk '{ print } NR % 3 == 0 { print "" }'; } >>"$repo/feature.txt"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  grep 'the alpha guard rejects' "$repo/feature.txt" | awk -v r="$repo" '{ print > (r "/part" int((NR - 1) / 3) ".txt") }'
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  commit_all "$repo" "refactor: scatter the alpha guard (#99)"
  expect_finding "$repo" "$culprit" 39 "39 lines of three-line paragraphs moved whole into new files still fire, since flat blocks never move"
}

t_go_raw_string_body_moved_out_still_fires() {
  local repo culprit
  mk_repo repo
  {
    printf 'package main\n\nfunc render() string {\n\treturn `\nfirst template paragraph line long enough\n\n'
    guard_lines ''
    printf '\n`\n}\n'
  } >"$repo/main.go"
  commit_all "$repo" "feat: add the template"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  guard_lines '' >"$repo/template.txt"
  printf 'package main\n' >"$repo/main.go"
  commit_all "$repo" "refactor: tidy the template (#99)"
  expect_finding "$repo" "$culprit" 48 "a Go raw-string body moved to a new file while its function is deleted still fires on all 48 lines"
}

t_markdown_tail_after_an_html_block_still_fires() {
  local repo culprit
  mk_repo repo
  {
    printf '## Usage\n\nan intro line under usage that stays where it is\n\n<!--\n\n# reviewer note: keep this example current\n-->\n\n'
    guard_lines ''
  } >"$repo/doc.md"
  commit_all "$repo" "docs: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  sed -n '/^# reviewer note/,$p' "$repo/doc.md" >"$repo/moved.md"
  sed '/^# reviewer note/,$d' "$repo/doc.md" >"$repo/doc.md.tmp"
  mv "$repo/doc.md.tmp" "$repo/doc.md"
  commit_all "$repo" "docs: split the usage (#99)"
  expect_finding "$repo" "$culprit" 43 \
    "Markdown moved from a heading inside an HTML comment to a new file still fires on all 43 lines"
}

t_heredoc_body_moved_out_of_a_kept_function_still_fires() {
  local repo culprit
  mk_repo repo
  { printf '\nemit_alpha_template() {\n  cat <<'"'"'EOF'"'"'\n\n'; guard_lines ''; printf '\nEOF\n}\n'; } >>"$repo/feature.sh"
  commit_all "$repo" "feat: add the alpha template"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  guard_lines '' >"$repo/template.txt"
  grep -v 'the alpha guard rejects' "$repo/feature.sh" >"$repo/feature.sh.tmp" || true
  mv "$repo/feature.sh.tmp" "$repo/feature.sh"
  commit_all "$repo" "refactor: tidy the alpha template (#99)"
  expect_finding "$repo" "$culprit" 40 "a column-0 heredoc body moved to a new file out of a function that stays still fires on all 40 lines"
}

t_unmoved_duplicate_cannot_borrow_a_moved_block() {
  local repo culprit sink
  mk_repo repo
  py_function dup_guard 20 >"$repo/feature.py"
  commit_all "$repo" "feat: add the old copy"
  filler "$repo" 5
  {
    py_function dup_guard 20
    py_function uniq_guard 20 | tail -n +2
    printf '\n'
    cat "$repo/feature.py"
  } >"$repo/feature.py.tmp"
  mv "$repo/feature.py.tmp" "$repo/feature.py"
  commit_all "$repo" "feat: add the recent copy"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  py_function dup_guard 20 >"$repo/helpers.py"
  drop_py_functions "$repo"
  commit_all "$repo" "refactor: tidy the guards (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=25 SILENT_REVERT_WINDOW=3 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && [[ "$(cat "$sink")" == "$culprit 41" ]]; then
    ok "the old copy's move does not discount the recent copy's identical lines (41 lines, threshold 25, window 3)"
  else
    fail "want one 41-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_partial_move_counts_only_the_lines_not_re_added() {
  local repo sink culprit
  mk_repo repo
  { py_function alpha_one 9 alpha; printf '\n'; py_function alpha_two 31 alpha; } >"$repo/feature.py"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  move_py_function "$repo" alpha_one helpers.py
  drop_py_functions "$repo"
  commit_all "$repo" "refactor: extract the alpha guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$OUT" &&
    [[ "$(cat "$sink")" == "$culprit 33" ]]; then
    ok "re-adding one of two deleted functions elsewhere still fires on the other 32 lines and the short header"
  else
    fail "want one 33-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_one_copy_discounts_one_deletion() {
  local repo sink culprit
  mk_repo repo
  local i
  mk_repo repo
  for i in $(seq 1 10); do
    py_function alpha_guard 2
    printf '\n'
  done >"$repo/feature.py"
  commit_all "$repo" "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  py_function alpha_guard 2 >"$repo/helpers.py"
  drop_py_functions "$repo"
  commit_all "$repo" "refactor: keep one copy of the guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && [[ "$(cat "$sink")" == "$culprit 28" ]]; then
    ok "one re-added copy of a function deleted 10 times discounts one function's body, not all 10"
  else
    fail "want one 28-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_moved_short_lines_still_count() {
  local repo sink culprit i
  mk_repo repo
  for i in $(seq 1 30); do
    printf 'x%s = %s\n' "$i" "$i" >>"$repo/feature.txt"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the short assignments"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  grep '^x' "$repo/feature.txt" >"$repo/helpers.txt" || true
  grep -v '^x' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "refactor: move the assignments (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && [[ "$(cat "$sink")" == "$culprit 30" ]]; then
    ok "lines shorter than the move minimum are not discounted when re-added elsewhere"
  else
    fail "want one 30-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

add_function() {
  local repo="$1" i
  {
    printf '\nalpha_guard() {\n'
    for i in $(seq 1 40); do
      printf '  the alpha guard rejects a relocation outside the session root, case %s\n' "$i"
    done
    printf '}\n'
  } >>"$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the alpha guard"
}

t_function_moved_with_its_definition_is_not_a_removal() {
  local repo sink
  mk_repo repo
  add_function "$repo"
  sed -n '/^alpha_guard() {$/,/^}$/p' "$repo/feature.txt" >"$repo/helpers.txt"
  sed '/^alpha_guard() {$/,/^}$/d' "$repo/feature.txt" >"$repo/feature.txt.tmp"
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "refactor: extract the alpha guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]] && [[ ! -s "$sink" ]] && grep -q '^ok ' <<<"$OUT"; then
    ok "a function moved to a new file with its definition line is not a removal (threshold 20)"
  else
    fail "a function extraction must report ok, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_body_pasted_elsewhere_without_its_definition_still_fires() {
  local repo sink culprit
  mk_repo repo
  add_function "$repo"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  grep 'the alpha guard rejects' "$repo/feature.txt" >"$repo/helpers.txt"
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/feature.txt.tmp" || true
  mv "$repo/feature.txt.tmp" "$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "refactor: tidy the alpha guard (#99)"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$OUT" &&
    [[ "$(cat "$sink")" == "$culprit 40" ]]; then
    ok "a function body pasted into another file without its definition line still fires on all 40 lines"
  else
    fail "want one 40-line finding for $culprit, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

drop_fragments() {
  local repo="$1" consume="$2" i j
  for i in $(seq 0 30); do
    mkdir -p "$repo/plugins/plugin$i" "$repo/.changes/plugin$i"
    printf '# Changelog for plugin%s\n\n## 1.0.0\n\n- First release.\n' "$i" \
      >"$repo/plugins/plugin$i/CHANGELOG.md"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: seed the changelogs"
  for i in $(seq 1 30); do
    for j in $(seq 1 10); do
      printf 'the plugin%s fragment line %s describes a fix to the guard\n' "$i" "$j"
    done >"$repo/.changes/plugin$i/fix-guard-0123abcd.md"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "fix: add the guard fragments (#98)"
  [[ "$(cat "$repo"/.changes/plugin*/*.md | wc -l)" -eq 300 ]] ||
    fail "fixture built the wrong number of fragment lines (want 300)"
  if [[ "$consume" = yes ]]; then
    for i in $(seq 1 30); do
      cat "$repo/.changes/plugin$i/fix-guard-0123abcd.md" >>"$repo/plugins/plugin$i/CHANGELOG.md"
    done
  elif [[ "$consume" = other ]]; then
    printf -- '- An unrelated plugin0 note.\n' >>"$repo/plugins/plugin0/CHANGELOG.md"
  fi
  git_test_config "$repo" rm -rq .changes >/dev/null
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: drop the fragments (#99)"
}

t_release_consuming_fragments_is_not_a_removal() {
  local repo
  mk_repo repo
  drop_fragments "$repo" yes
  run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]]; then
    ok "a commit consuming 300 lines of recent .changes/ fragments into CHANGELOG.md is not a removal (threshold 200)"
  else
    fail "consumed .changes/ fragments must not fire, rc=$RC: $OUT"
  fi
}

assert_fragment_drop_fires() {
  local repo sink
  mk_repo repo
  drop_fragments "$repo" "$1"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -qxE '[0-9a-f]{40} 300' "$sink" && [[ "$(wc -l <"$sink")" -eq 1 ]]; then
    ok "$2 (300 lines, threshold 200)"
  else
    fail "$2: want one 300-line finding, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_fragments_dropped_without_changelog_still_fire() {
  assert_fragment_drop_fires no "dropping recent .changes/ fragments with no CHANGELOG change fires"
}

t_fragments_dropped_beside_another_changelog_still_fire() {
  assert_fragment_drop_fires other "dropping recent .changes/ fragments while editing a different plugin's CHANGELOG fires"
}

drop_bumped_fragments() {
  local repo="$1" bump="$2" changelog="$3" layout="$4" i j path
  for i in $(seq 0 30); do
    mkdir -p "$repo/plugins/plugin$i"
    printf '# Changelog for plugin%s\n\n## 1.0.0\n\n- First release.\n' "$i" \
      >"$repo/plugins/plugin$i/CHANGELOG.md"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: seed the changelogs"
  for i in $(seq 1 30); do
    path=".changes/plugin$i/readme-install-0123abcd.md"
    if [[ "$layout" = elsewhere ]]; then
      path=".changes/plugin$i/nested/readme-install-0123abcd.md"
      ((i % 2)) || path="notes/plugin$i/readme-install-0123abcd.md"
    fi
    mkdir -p "$repo/${path%/*}"
    {
      printf -- '---\nbump: %s\n---\n' "$bump"
      for j in $(seq 1 7); do
        printf 'the plugin%s README install line %s needs no release\n' "$i" "$j"
      done
    } >"$repo/$path"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "docs: one install form in every README (#98)"
  [[ "$(find "$repo/.changes" "$repo/notes" -type f -exec cat {} + 2>/dev/null | wc -l)" -eq 300 ]] ||
    fail "fixture built the wrong number of fragment lines (want 300)"
  if [[ "$changelog" = other ]]; then
    printf -- '- An unrelated plugin0 note.\n' >>"$repo/plugins/plugin0/CHANGELOG.md"
  fi
  git_test_config "$repo" rm -rq --ignore-unmatch -- .changes notes >/dev/null
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore(release): release 1 plugins (#99)"
}

t_release_none_fragment_cleanup_is_not_a_removal() {
  local repo
  mk_repo repo
  drop_bumped_fragments "$repo" none other fragment
  run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]]; then
    ok "a release deleting 300 lines of bump: none fragments whose plugins' CHANGELOGs stay unchanged is not a removal (threshold 200)"
  else
    fail "a release's bump: none fragment cleanup must not fire, rc=$RC: $OUT"
  fi
}

assert_bumped_drop_fires() {
  local repo sink
  mk_repo repo
  drop_bumped_fragments "$repo" "$1" "$2" "$3"
  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -qxE '[0-9a-f]{40} 300' "$sink" && [[ "$(wc -l <"$sink")" -eq 1 ]]; then
    ok "$4 (300 lines, threshold 200)"
  else
    fail "$4: want one 300-line finding, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_release_patch_fragment_drop_still_fires() {
  assert_bumped_drop_fires patch other fragment \
    "a release deleting bump: patch fragments whose plugins' CHANGELOGs stay unchanged fires"
}

t_none_front_matter_outside_fragment_layout_still_fires() {
  assert_bumped_drop_fires none other elsewhere \
    "deleting bump: none files nested under .changes/<p>/ or outside .changes/ fires beside a CHANGELOG change"
}

t_none_fragment_drop_without_any_changelog_change_still_fires() {
  assert_bumped_drop_fires none no fragment \
    "deleting bump: none fragments in a commit that changes no CHANGELOG fires"
}

t_counts_are_immune_to_ambient_git_config() {
  local repo clean_sink hostile_sink cfg revs
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  local culprit
  culprit="$(git -C "$repo" rev-parse HEAD)"
  add_block "$repo" feature.txt 30 beta
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"

  clean_sink="$(mktemp "$TMP/x.XXXX")"
  hostile_sink="$(mktemp "$TMP/x.XXXX")"
  cfg="$repo/hostile-gitconfig"
  revs="$repo/ignore-revs.txt"
  printf '%s\n' "$culprit" >"$revs"
  {
    printf '[blame]\n\tignoreRevsFile = %s\n' "$revs"
    printf '[diff]\n\talgorithm = histogram\n\trenames = false\n\tsuppressBlankEmpty = true\n'
    printf '\texternal = %s\n' "$repo/never-run-this-diff.sh"
  } >"$cfg"

  FINDINGS_SINK="$clean_sink" SILENT_REVERT_THRESHOLD=20 \
    run_canary "$repo" --commit HEAD
  local clean_rc="$RC"
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$hostile_sink" SILENT_REVERT_THRESHOLD=20 \
    run_canary "$repo" --commit HEAD
  local hostile_rc="$RC"

  sort -o "$clean_sink" "$clean_sink"
  sort -o "$hostile_sink" "$hostile_sink"

  if [[ -s "$clean_sink" ]] && [[ "$clean_rc" -eq "$hostile_rc" ]] &&
    cmp -s "$clean_sink" "$hostile_sink"; then
    ok "attribution counts are identical under hostile ambient git config"
  else
    fail "ambient git config changed the attribution (rc $clean_rc vs $hostile_rc): $(
      printf 'clean=[%s] hostile=[%s]' "$(tr '\n' ';' <"$clean_sink")" \
        "$(tr '\n' ';' <"$hostile_sink")"
    )"
  fi

  local move
  mk_repo move
  { printf 'import os\n\n'; py_function alpha_guard 40; } >"$move/feature.py"
  commit_all "$move" "feat: add the alpha guard"
  move_py_function "$move" alpha_guard helpers.py
  drop_py_functions "$move"
  commit_all "$move" "refactor: extract the alpha guard (#99)"
  : >"$clean_sink"
  : >"$hostile_sink"
  FINDINGS_SINK="$clean_sink" SILENT_REVERT_THRESHOLD=20 run_canary "$move" --commit HEAD
  clean_rc="$RC"
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$hostile_sink" SILENT_REVERT_THRESHOLD=20 \
    run_canary "$move" --commit HEAD
  if [[ "$clean_rc" -eq 0 && "$RC" -eq 0 ]] && [[ ! -s "$clean_sink" && ! -s "$hostile_sink" ]]; then
    ok "a whole-run move is discounted identically under hostile ambient git config"
  else
    fail "ambient git config changed the move discount (rc $clean_rc vs $RC): clean=[$(tr '\n' ';' <"$clean_sink")] hostile=[$(tr '\n' ';' <"$hostile_sink")]"
  fi
  rm -f "$clean_sink" "$hostile_sink"
}

strip_pin() {
  local repo="$1" name="$2" expr="$3"
  local src="$repo/scripts/check-silent-revert.sh" dst="$repo/scripts/$name.sh"
  local src_code dst_code
  [[ -f "$src" ]] || {
    fail "strip_pin($name): no detector at $src -- the fixture was never built"
    return 1
  }
  sed "$expr" "$src" >"$dst" 2>/dev/null
  src_code="$(mktemp "$TMP/x.XXXX")"
  dst_code="$(mktemp "$TMP/x.XXXX")"
  grep -v '^[[:space:]]*#' "$src" >"$src_code"
  grep -v '^[[:space:]]*#' "$dst" >"$dst_code"
  if cmp -s "$src_code" "$dst_code"; then
    rm -f "$src_code" "$dst_code"
    fail "strip_pin($name): the edit changed no CODE line, so the 'stripped' copy runs identically to the shipped detector and this case would pass either way (a comment-only match counts as no match)"
    return 1
  fi
  rm -f "$src_code" "$dst_code"
  return 0
}

t_rename_pin_is_load_bearing() {
  local repo culprit cfg intact_rc stripped_rc
  mk_repo repo
  printf 'the alpha guard rejects a relocation outside the session root, case %s\n' \
    $(seq 1 500) >"$repo/moved.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  git_test_config "$repo" mv moved.txt relocated.txt >/dev/null
  git_test_config "$repo" commit -qm "refactor: relocate the guard (#99)"

  cfg="$repo/no-renames-gitconfig"
  printf '[diff]\n\trenames = false\n' >"$cfg"

  strip_pin "$repo" no-rename-pin '/--name-only/ s/ -M / /g' || return 0

  GIT_CONFIG_GLOBAL="$cfg" run_canary "$repo" --commit HEAD
  intact_rc="$RC"
  GIT_CONFIG_GLOBAL="$cfg" CANARY_SCRIPT=scripts/no-rename-pin.sh \
    run_canary "$repo" --commit HEAD
  stripped_rc="$RC"

  if [[ "$intact_rc" -eq 0 ]] && [[ "$stripped_rc" -eq 1 ]]; then
    ok "the -M pin is load-bearing: stripped it reports a pure rename as a 500-line removal, pinned it stays clean"
  else
    fail "the -M pin did not discriminate (pinned rc=$intact_rc want 0, stripped rc=$stripped_rc want 1): $OUT"
  fi
}

build_basename_changing_relocation() {
  local repo="$1" n="$2" lines="$3" i j
  mkdir -p "$repo/src"
  for i in $(seq 1 "$n"); do
    : >"$repo/src/old${i}.txt"
    for j in $(seq 1 "$lines"); do
      printf 'the alpha guard file %s line %s\n' "$i" "$j" >>"$repo/src/old${i}.txt"
    done
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: land the corpus"
  mkdir -p "$repo/dst"
  for i in $(seq 1 "$n"); do
    {
      head -n $((lines - 1)) "$repo/src/old${i}.txt"
      printf 'the alpha guard file %s line %s touched\n' "$i" "$lines"
    } >"$repo/dst/new${i}.txt"
    rm -f "$repo/src/old${i}.txt"
  done
  rmdir "$repo/src" 2>/dev/null || true
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: relocate the corpus"
}

t_minus_diff_lock_file_is_attributed() {
  local repo sink lock_culprit txt_culprit
  mk_repo repo
  {
    printf '*.lock -diff\n'
    printf '*.png binary\n'
  } >"$repo/.gitattributes"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: hide lock diffs and mark pngs binary"

  add_block "$repo" foo.lock 320 alpha
  lock_culprit="$(git -C "$repo" rev-parse HEAD)"
  dd if=/dev/urandom of="$repo/img.png" bs=1024 count=200 status=none 2>/dev/null ||
    dd if=/dev/urandom of="$repo/img.png" bs=1024 count=200 2>/dev/null
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: land the image"
  add_block "$repo" plain.txt 25 beta
  txt_culprit="$(git -C "$repo" rev-parse HEAD)"

  grep -v "the alpha guard rejects" "$repo/foo.lock" >"$repo/foo.lock.tmp" || true
  mv "$repo/foo.lock.tmp" "$repo/foo.lock"
  dd if=/dev/urandom of="$repo/img.png" bs=1024 count=200 status=none 2>/dev/null ||
    dd if=/dev/urandom of="$repo/img.png" bs=1024 count=200 2>/dev/null
  grep -v "the beta guard rejects" "$repo/plain.txt" >"$repo/plain.txt.tmp" || true
  mv "$repo/plain.txt.tmp" "$repo/plain.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: unrelated feature (#99)"

  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  sort -o "$sink" "$sink"

  if [[ "$RC" -eq 1 ]] &&
    grep -qx "${lock_culprit} 320" "$sink" &&
    grep -qx "${txt_culprit} 25" "$sink" &&
    grep -q 'foo.lock' <<<"$OUT" &&
    grep -q 'plain.txt' <<<"$OUT" &&
    ! grep -q 'img.png' <<<"$OUT"; then
    ok "a -diff lock file is attributed and a binary png churn is not (#2883)"
  else
    fail "lock/png/txt mix: want rc=1 with ${lock_culprit}=320 and ${txt_culprit}=25, no png; rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_minus_diff_recovery_is_load_bearing() {
  local repo intact_sink stripped_sink intact_rc stripped_rc
  mk_repo repo
  printf '*.lock -diff\n' >"$repo/.gitattributes"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: hide lock diffs"
  add_block "$repo" foo.lock 320 alpha
  drop_block "$repo" foo.lock alpha "feat: unrelated feature (#99)"

  strip_pin "$repo" no-attr-recover '/grep -q/ s/\^Binary files /^Binary files NEVER /' || return 0

  intact_sink="$(mktemp "$TMP/x.XXXX")"
  stripped_sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$intact_sink" SILENT_REVERT_THRESHOLD=200 \
    run_canary "$repo" --commit HEAD
  intact_rc="$RC"
  FINDINGS_SINK="$stripped_sink" SILENT_REVERT_THRESHOLD=200 \
    CANARY_SCRIPT=scripts/no-attr-recover.sh run_canary "$repo" --commit HEAD
  stripped_rc="$RC"

  if [[ "$intact_rc" -eq 1 ]] && [[ -s "$intact_sink" ]] &&
    [[ "$stripped_rc" -eq 0 ]] && [[ ! -s "$stripped_sink" ]]; then
    ok "blob-to-blob recovery is load-bearing: stripped it a -diff lock deletion is a FALSE GREEN"
  else
    fail "attr recovery did not discriminate (pinned rc=$intact_rc want 1, stripped rc=$stripped_rc want 0): pinned=[$(tr '\n' ';' <"$intact_sink")] stripped=[$(tr '\n' ';' <"$stripped_sink")]"
  fi
  rm -f "$intact_sink" "$stripped_sink"
}

t_detector_does_not_pass_text() {
  local code
  code="$(mktemp "$TMP/x.XXXX")"
  grep -v '^[[:space:]]*#' "$SCRIPT" >"$code"
  if grep -Eq -- '(^|[[:space:]])--text([[:space:]]|$)' "$code"; then
    fail "the detector's code passes --text, which #2883 forbids: $(grep -E -- '--text' "$code")"
  else
    ok "the detector does not pass --text (blob-to-blob recovery, not -a)"
  fi
  rm -f "$code"
}

t_minus_diff_whole_file_deletion_is_attributed() {
  local repo sink culprit
  mk_repo repo
  printf '*.lock -diff\n' >"$repo/.gitattributes"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: hide lock diffs"
  add_block "$repo" foo.lock 320 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  git_test_config "$repo" rm -q foo.lock >/dev/null
  git_test_config "$repo" commit -qm "feat: unrelated feature (#99)"

  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=200 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 1 ]] && grep -qx "${culprit} 320" "$sink"; then
    ok "a wholly deleted -diff lock file is attributed (320 lines)"
  else
    fail "whole-file -diff deletion must fire 320, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_explicit_binary_ascii_is_not_attributed() {
  local repo sink
  mk_repo repo
  printf '*.pdf binary\n' >"$repo/.gitattributes"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: mark pdfs binary"
  {
    printf '%%PDF-1.4\n'
    for i in $(seq 1 320); do
      printf 'the alpha guard rejects a relocation outside the session root, case %s\n' "$i"
    done
  } >"$repo/doc.pdf"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: land the ascii pdf"
  : >"$repo/doc.pdf"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: unrelated feature (#99)"

  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=200 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]] && [[ ! -s "$sink" ]]; then
    ok "an ASCII file marked binary is not attributed"
  else
    fail "explicit binary must stay clean even without NULs, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_binary_asset_churn_is_not_a_finding() {
  local repo sink
  mk_repo repo
  printf '*.png binary\n' >"$repo/.gitattributes"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: mark pngs binary"
  dd if=/dev/urandom of="$repo/img.png" bs=1024 count=200 status=none 2>/dev/null ||
    dd if=/dev/urandom of="$repo/img.png" bs=1024 count=200 2>/dev/null
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: land the image"
  dd if=/dev/urandom of="$repo/img.png" bs=1024 count=200 status=none 2>/dev/null ||
    dd if=/dev/urandom of="$repo/img.png" bs=1024 count=200 2>/dev/null
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: re-export the image"

  sink="$(mktemp "$TMP/x.XXXX")"
  FINDINGS_SINK="$sink" SILENT_REVERT_THRESHOLD=200 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]] && [[ ! -s "$sink" ]]; then
    ok "a binary png re-export is not a finding (no --text)"
  else
    fail "binary churn must stay clean, rc=$RC sink=[$(tr '\n' ';' <"$sink")] out=$OUT"
  fi
  rm -f "$sink"
}

t_rename_limit_does_not_decompose_basename_changing_relocation() {
  local repo
  mk_repo repo
  build_basename_changing_relocation "$repo" 1001 10
  SILENT_REVERT_THRESHOLD=200 run_canary "$repo" --commit HEAD
  if [[ "$RC" -eq 0 ]]; then
    ok "a 1001-file basename-changing relocation is not a finding (-l0)"
  else
    fail "default renameLimit must not decompose 1001 basename-changing moves, rc=$RC: $OUT"
  fi
}

t_rename_limit_flag_is_load_bearing() {
  local repo cfg intact_rc stripped_rc intact_sink stripped_sink
  mk_repo repo
  build_basename_changing_relocation "$repo" 12 20

  cfg="$repo/low-rename-limit-gitconfig"
  printf '[diff]\n\trenameLimit = 1\n' >"$cfg"

  strip_pin "$repo" no-l0-pin '/--name-only/ s/ -l0 / /' || return 0

  intact_sink="$(mktemp "$TMP/x.XXXX")"
  stripped_sink="$(mktemp "$TMP/x.XXXX")"
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$intact_sink" SILENT_REVERT_THRESHOLD=200 \
    run_canary "$repo" --commit HEAD
  intact_rc="$RC"
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$stripped_sink" SILENT_REVERT_THRESHOLD=200 \
    CANARY_SCRIPT=scripts/no-l0-pin.sh run_canary "$repo" --commit HEAD
  stripped_rc="$RC"

  if [[ "$intact_rc" -eq 0 ]] && [[ ! -s "$intact_sink" ]] &&
    [[ "$stripped_rc" -eq 1 ]] && [[ -s "$stripped_sink" ]]; then
    ok "the -l0 flag is load-bearing: stripped it a renameLimit=1 relocation fires, pinned it stays clean"
  else
    fail "the -l0 flag did not discriminate (pinned rc=$intact_rc want 0, stripped rc=$stripped_rc want 1): pinned=[$(tr '\n' ';' <"$intact_sink")] stripped=[$(tr '\n' ';' <"$stripped_sink")] out=$OUT"
  fi
  rm -f "$intact_sink" "$stripped_sink"
}

t_ext_diff_pin_is_load_bearing() {
  local repo cfg intact_rc stripped_rc intact_sink stripped_sink
  mk_repo repo
  add_block "$repo" feature.txt 300 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"

  cfg="$repo/ext-diff-gitconfig"
  printf '[diff]\n\texternal = /usr/bin/true\n' >"$cfg"

  strip_pin "$repo" no-ext-pin 's/ --no-ext-diff//' || return 0

  intact_sink="$(mktemp "$TMP/x.XXXX")"
  stripped_sink="$(mktemp "$TMP/x.XXXX")"
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$intact_sink" SILENT_REVERT_THRESHOLD=200 \
    run_canary "$repo" --commit HEAD
  intact_rc="$RC"
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$stripped_sink" SILENT_REVERT_THRESHOLD=200 \
    CANARY_SCRIPT=scripts/no-ext-pin.sh run_canary "$repo" --commit HEAD
  stripped_rc="$RC"

  if [[ "$intact_rc" -eq 1 ]] && [[ -s "$intact_sink" ]] &&
    [[ "$stripped_rc" -eq 0 ]] && [[ ! -s "$stripped_sink" ]]; then
    ok "the --no-ext-diff pin is load-bearing: stripped it is a FALSE GREEN under diff.external, pinned it still fires"
  else
    fail "the --no-ext-diff pin did not discriminate (pinned rc=$intact_rc want 1 with findings, stripped rc=$stripped_rc want 0 with none): pinned=[$(tr '\n' ';' <"$intact_sink")] stripped=[$(tr '\n' ';' <"$stripped_sink")]"
  fi
  rm -f "$intact_sink" "$stripped_sink"
}

t_textconv_pin_is_load_bearing() {
  local repo cfg clean_sink intact_sink both_sink blame_sink diff_sink
  local clean_rc intact_rc live_before live_after clean_n both_n
  mk_repo repo
  printf '*.md diff=markdown\n' >"$repo/.gitattributes"
  printf 'base line %s\n' $(seq 1 150) >"$repo/feature.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: name a diff driver for markdown"

  add_block "$repo" feature.md 300 alpha
  drop_block "$repo" feature.md alpha "feat: unrelated feature (#99)"

  cfg="$repo/textconv-gitconfig"
  printf '[diff "markdown"]\n\ttextconv = sed p\n' >"$cfg"

  live_before="$(git_test_config "$repo" blame --line-porcelain HEAD~1 -- feature.md 2>/dev/null | grep -c '^	')"
  live_after="$(GIT_CONFIG_GLOBAL="$cfg" git_test_config "$repo" blame --line-porcelain HEAD~1 -- feature.md 2>/dev/null | grep -c '^	')"
  if [[ "$live_before" -lt 1 ]] || [[ "$live_after" -ne $((live_before * 2)) ]]; then
    fail "the textconv driver is not active in this fixture (blame returned $live_before lines unfiltered and $live_after filtered, want the filtered count to be double), so this case cannot say anything about the pin -- fix the fixture, do not read this as the pin being inert"
    return 0
  fi

  strip_pin "$repo" no-textconv-pin 's/ --no-textconv//g' || return 0
  strip_pin "$repo" blame-textconv-unpinned '/blame --no-ignore-revs-file/ s/ --no-textconv//' || return 0
  strip_pin "$repo" diff-textconv-unpinned '/diff --no-ext-diff/ s/ --no-textconv//' || return 0

  clean_sink="$(mktemp "$TMP/x.XXXX")"
  intact_sink="$(mktemp "$TMP/x.XXXX")"
  both_sink="$(mktemp "$TMP/x.XXXX")"
  blame_sink="$(mktemp "$TMP/x.XXXX")"
  diff_sink="$(mktemp "$TMP/x.XXXX")"

  FINDINGS_SINK="$clean_sink" SILENT_REVERT_THRESHOLD=200 run_canary "$repo" --commit HEAD
  clean_rc="$RC"
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$intact_sink" SILENT_REVERT_THRESHOLD=200 \
    run_canary "$repo" --commit HEAD
  intact_rc="$RC"
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$both_sink" SILENT_REVERT_THRESHOLD=200 \
    CANARY_SCRIPT=scripts/no-textconv-pin.sh run_canary "$repo" --commit HEAD
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$blame_sink" SILENT_REVERT_THRESHOLD=200 \
    CANARY_SCRIPT=scripts/blame-textconv-unpinned.sh run_canary "$repo" --commit HEAD
  GIT_CONFIG_GLOBAL="$cfg" FINDINGS_SINK="$diff_sink" SILENT_REVERT_THRESHOLD=200 \
    CANARY_SCRIPT=scripts/diff-textconv-unpinned.sh run_canary "$repo" --commit HEAD

  local sk
  for sk in "$clean_sink" "$intact_sink" "$both_sink" "$blame_sink" "$diff_sink"; do
    sort -o "$sk" "$sk"
  done

  clean_n="$(awk 'NR == 1 { print $2 }' "$clean_sink")"
  both_n="$(awk 'NR == 1 { print $2 }' "$both_sink")"
  if [[ "$clean_rc" -eq 1 ]] && [[ -s "$clean_sink" ]] &&
    [[ "$intact_rc" -eq "$clean_rc" ]] && cmp -s "$clean_sink" "$intact_sink" &&
    [[ "$clean_n" =~ ^[0-9]+$ ]] && [[ "$both_n" =~ ^[0-9]+$ ]] &&
    [[ "$both_n" -eq $((clean_n * 2)) ]] &&
    [[ ! -s "$blame_sink" ]] && [[ ! -s "$diff_sink" ]]; then
    ok "the --no-textconv pin is load-bearing on the diff AND the blame: stripping both inflates the count, stripping either one alone SILENCES a real finding; pinned both it is unchanged"
  else
    fail "the --no-textconv pin did not discriminate (clean rc=$clean_rc, pinned rc=$intact_rc): clean=[$(tr '\n' ';' <"$clean_sink")] pinned=[$(tr '\n' ';' <"$intact_sink")] both-stripped=[$(tr '\n' ';' <"$both_sink")] blame-only-stripped=[$(tr '\n' ';' <"$blame_sink")] diff-only-stripped=[$(tr '\n' ';' <"$diff_sink")]"
  fi
  rm -f "$clean_sink" "$intact_sink" "$both_sink" "$blame_sink" "$diff_sink"
}

t_show_signature_pin_is_load_bearing() {
  local repo cfg intact_rc stripped_rc intact_out grafted
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/f.tmp" || true
  mv "$repo/f.tmp" "$repo/feature.txt"
  printf 'unrelated work from the stale branch\n' >>"$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm 'revert: remove the alpha guard (#99)'

  git_test_config "$repo" cat-file commit HEAD >"$repo/raw-commit"
  awk '
    !grafted && /^$/ {
      print "gpgsig -----BEGIN SSH SIGNATURE-----"
      print " U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgZ3JhZnRlZGZpeHR1cmVzaWduYXR1"
      print " cmVub3RhcmVhbGtleQAAAANnaXQAAAAAAAAABnNoYTUxMgAAAFMAAAALc3NoLWVkMjU1MTkA"
      print " AABAZ3JhZnRlZGZpeHR1cmVzaWduYXR1cmVieXRlc25vdGFyZWFsc2lnbmF0dXJlYXRhbGxo"
      print " ZXJlAA=="
      print " -----END SSH SIGNATURE-----"
      grafted = 1
    }
    { print }
  ' "$repo/raw-commit" >"$repo/raw-commit-signed"
  grafted="$(git_test_config "$repo" hash-object -t commit -w --stdin <"$repo/raw-commit-signed")"
  git_test_config "$repo" update-ref HEAD "$grafted"
  if ! grep -q '^gpgsig' < <(git_test_config "$repo" cat-file commit HEAD 2>/dev/null); then
    fail "the fixture commit carries no signature header, so log.showSignature would print nothing and this case would pass with or without the pin (not a pass)"
    return 0
  fi

  cfg="$repo/show-signature-gitconfig"
  printf '[log]\n\tshowSignature = true\n[gpg]\n\tformat = ssh\n' >"$cfg"

  strip_pin "$repo" no-signature-pin 's/ --no-show-signature//g' || return 0

  GIT_CONFIG_GLOBAL="$cfg" SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  intact_rc="$RC"
  intact_out="$OUT"
  GIT_CONFIG_GLOBAL="$cfg" SILENT_REVERT_THRESHOLD=20 \
    CANARY_SCRIPT=scripts/no-signature-pin.sh run_canary "$repo" --commit HEAD
  stripped_rc="$RC"

  if [[ "$intact_rc" -eq 0 ]] && grep -q '^declared ' <<<"$intact_out" &&
    [[ "$stripped_rc" -eq 1 ]]; then
    ok "the --no-show-signature pin is load-bearing: stripped it reads a signed revert's subject as gpg output and fires, pinned it reads the declaration"
  else
    fail "the --no-show-signature pin did not discriminate (pinned rc=$intact_rc want 0 and declared, stripped rc=$stripped_rc want 1): $intact_out"
  fi
}

assert_declared() {
  local label="$1" msg="$2" expect_rc="$3"
  local repo out
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "$msg"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq "$expect_rc" ]]; then
    ok "$label"
  else
    fail "$label: expected rc=$expect_rc, got rc=$RC: $out"
  fi
}

t_declared_forms() {
  assert_declared 'a Revert-quote subject silences the canary' \
    'Revert "feat: add the alpha guard"' 0
  assert_declared 'a "This reverts commit <sha>" line silences the canary' \
    "$(printf 'chore: back out the guard\n\nThis reverts commit 0123456789abcdef0123456789abcdef01234567.\n')" 0
  assert_declared 'an Intentional-removal trailer silences the canary' \
    "$(printf 'refactor: drop the alpha guard (#99)\n\nIntentional-removal: superseded by the shared guard in #100\n')" 0
}

t_conventional_revert_subject_is_declared() {
  assert_declared 'a bare "revert:" subject silences the canary' \
    'revert: remove the alpha guard (#99)' 0
  assert_declared 'a scoped "revert(scope):" subject silences the canary' \
    'revert(disk-hygiene): remove the alpha guard (#99)' 0
  assert_declared 'a breaking "revert!:" subject silences the canary' \
    'revert!: remove the alpha guard (#99)' 0
  assert_declared 'a scoped breaking "revert(scope)!:" subject silences the canary' \
    'revert(disk-hygiene)!: remove the alpha guard (#99)' 0
}

t_prose_mentioning_revert_still_fires() {
  assert_declared 'prose mentioning "revert" does not silence the canary' \
    "$(printf 'feat: unrelated feature (#99)\n\nThis does not revert anything; the guard work is untouched.\n')" 1
  assert_declared 'a subject merely containing "revert" does not silence the canary' \
    'feat: do not revert the alpha guard (#99)' 1
  assert_declared 'a subject whose type merely starts with "revert" does not silence the canary' \
    'reverted: drop the alpha guard (#99)' 1
  assert_declared 'an uppercase "Revert:" subject the title gate would reject does not silence the canary' \
    'Revert: drop the alpha guard (#99)' 1
  assert_declared 'a "revert:" with no description does not silence the canary' \
    'revert:' 1
}

t_empty_trailer_still_fires() {
  assert_declared 'an empty Intentional-removal trailer does not silence the canary' \
    "$(printf 'refactor: drop the guard (#99)\n\nIntentional-removal:\n')" 1
}

t_acknowledged_commit_is_cleared() {
  local repo out sha
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"
  printf '# ack\n%s  reviewed: intentional\n' "$sha" >"$repo/scripts/ack.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_ACK=scripts/ack.txt \
    run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'reviewed and cleared' <<<"$out"; then
    ok "a reviewed commit recorded in the acknowledgment file is cleared"
  else
    fail "expected the acknowledged commit to clear, rc=$RC: $out"
  fi
}

t_abbreviated_ack_does_not_clear() {
  local repo out sha
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse --short=9 HEAD)"
  printf '%s  reviewed: intentional\n' "$sha" >"$repo/scripts/ack.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_ACK=scripts/ack.txt \
    run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "an abbreviated sha in the acknowledgment file does not clear a finding"
  else
    fail "expected an abbreviated ack to be refused, rc=$RC: $out"
  fi
}

t_ack_last_row_without_newline_is_honored() {
  local repo out sha
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"

  printf '# ack\n%s  reviewed: last row, no trailing newline' "$sha" \
    >"$repo/scripts/ack.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_ACK=scripts/ack.txt \
    run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'reviewed and cleared' <<<"$out"; then
    ok "an acknowledgment file whose last row has no trailing newline still clears"
  else
    fail "expected the unterminated last ack row to clear, rc=$RC: $out"
  fi
}

t_default_threshold_is_wired() {
  local repo out
  mk_repo repo
  add_block "$repo" feature.txt 260 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "the shipped default threshold fires on a 260-line drop"
  else
    fail "shipped default did not fire on 260 lines, rc=$RC: $out"
  fi
  mk_repo repo
  add_block "$repo" feature.txt 60 beta
  drop_block "$repo" feature.txt beta "feat: unrelated feature (#98)"
  run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "the shipped default threshold stays quiet on a 60-line drop"
  else
    fail "shipped default fired on 60 lines, rc=$RC: $out"
  fi
}

t_range_mode_scans_every_commit() {
  local repo out base
  mk_repo repo
  base="$(git -C "$repo" rev-parse HEAD)"
  add_block "$repo" feature.txt 40 alpha
  filler "$repo" 1
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" "$base..HEAD"
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'SILENT REVERT SUSPECTED' <<<"$out"; then
    ok "range mode scans every commit in the push"
  else
    fail "expected range mode to find the revert, rc=$RC: $out"
  fi
}

t_declared_note_ends_its_line() {
  local repo out base
  mk_repo repo
  base="$(git -C "$repo" rev-parse HEAD)"
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha 'revert: remove the alpha guard (#99)'
  filler "$repo" 1
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" "$base..HEAD"
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q '^declared ' <<<"$out" &&
    grep -q '^ok ' <<<"$out"; then
    ok "the declared note ends its line, so the next commit's verdict is not glued to it"
  else
    fail "expected a standalone 'ok' line after the declared note, rc=$RC: $out"
  fi
}

t_whole_file_deletion_is_attributed() {
  local repo out
  mk_repo repo
  printf 'the alpha guard rejects relocation, case %s\n' $(seq 1 40) >"$repo/guard.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the guard file"
  rm "$repo/guard.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'guard.txt' <<<"$out"; then
    ok "a wholly deleted file is attributed like any other removal"
  else
    fail "expected the deleted file to be attributed, rc=$RC: $out"
  fi
}

t_unresolvable_range_fails_closed() {
  local repo out
  mk_repo repo
  run_canary "$repo" "deadbeef..HEAD"
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "an unresolvable range exits 2 (cannot run), never a quiet pass"
  else
    fail "expected rc=2 on an unresolvable range, got rc=$RC: $out"
  fi
  run_canary "$repo" "not-a-range"
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "a malformed range argument exits 2"
  else
    fail "expected rc=2 on a malformed range, got rc=$RC: $out"
  fi
  run_canary "$repo"
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "no arguments exits 2 with usage"
  else
    fail "expected rc=2 with no arguments, got rc=$RC: $out"
  fi
}

t_root_commit_is_handled() {
  local repo out
  mk_repo repo
  run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'root commit' <<<"$out"; then
    ok "a root commit is reported as having no parent, not crashed on"
  else
    fail "expected the root commit to be handled, rc=$RC: $out"
  fi
}

t_empty_range_is_clean() {
  local repo out head
  mk_repo repo
  add_block "$repo" feature.txt 5 alpha
  head="$(git -C "$repo" rev-parse HEAD)"
  run_canary "$repo" "$head..$head"
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'no commits in range' <<<"$out"; then
    ok "an empty range is clean and says so"
  else
    fail "expected an empty range to be clean, rc=$RC: $out"
  fi
}

t_replay_fails_on_broken_expectation() {
  local repo out sha
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"

  printf '# fixture\nfires %s a real drop\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "replay passes when a recorded incident still fires"
  else
    fail "replay should have passed, rc=$RC: $out"
  fi

  printf 'clean %s deliberately wrong\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "replay fails when a recorded expectation no longer holds"
  else
    fail "replay should have failed on a wrong expectation, rc=$RC: $out"
  fi

  printf 'fires 0123456789abcdef0123456789abcdef01234567 unreachable\n' \
    >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "replay exits 2 when a recorded commit is unreachable (shallow history)"
  else
    fail "expected rc=2 on an unreachable incident commit, rc=$RC: $out"
  fi
}

t_replay_asserts_the_recorded_attribution() {
  local repo out culprit other
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  other="$(git -C "$repo" rev-parse HEAD~1)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  local sha
  sha="$(git -C "$repo" rev-parse HEAD)"

  printf 'fires %s [%s=40] a real drop\n' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'attribution(s) reproduced exactly' <<<"$out"; then
    ok "replay passes when the recorded culprit and line count both reproduce"
  else
    fail "replay should have passed on a correct attribution, rc=$RC: $out"
  fi

  printf 'fires %s [%s=40] wrong culprit\n' "$sha" "$other" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'fires, but NOT as recorded' <<<"$out"; then
    ok "replay fails when the finding is attributed to a different culprit"
  else
    fail "a wrong recorded culprit must fail the replay, rc=$RC: $out"
  fi

  printf 'fires %s [%s=39] wrong count\n' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'fires, but NOT as recorded' <<<"$out"; then
    ok "replay fails when the recorded line count no longer reproduces"
  else
    fail "a wrong recorded line count must fail the replay, rc=$RC: $out"
  fi

  printf 'fires %s [%s=40,%s=301] one attribution never reproduces\n' \
    "$sha" "$culprit" "$other" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'fires, but NOT as recorded' <<<"$out"; then
    ok "replay fails when one of two recorded attributions stops reproducing"
  else
    fail "a missing recorded attribution must fail the replay, rc=$RC: $out"
  fi

  local bad
  for bad in "[${culprit:0:9}=40]" "[$culprit=many]" "[$culprit]" "[]" \
    "[$culprit=40" "["; do
    printf 'fires %s %s malformed\n' "$sha" "$bad" >"$repo/scripts/inc.txt"
    SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
      run_canary "$repo" --verify-known-incidents
    out="$OUT"
    if [[ "$RC" -eq 2 ]]; then
      ok "a malformed attribution field '$bad' exits 2 rather than passing or failing"
    else
      fail "expected rc=2 on malformed attribution '$bad', got rc=$RC: $out"
    fi
  done

  for bad in "[$culprit=40,]" "[,$culprit=40]" "[$culprit=40,,$other=1]" "[,]"; do
    printf 'fires %s %s comma\n' "$sha" "$bad" >"$repo/scripts/inc.txt"
    SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
      run_canary "$repo" --verify-known-incidents
    out="$OUT"
    if [[ "$RC" -eq 2 ]]; then
      ok "a comma-malformed attribution field '$bad' exits 2"
    else
      fail "expected rc=2 on comma-malformed attribution '$bad', got rc=$RC: $out"
    fi
  done

  printf 'clean %s [%s=40] attribution on a firing commit\n' "$sha" "$culprit" \
    >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'should stay clean and fired' <<<"$out"; then
    ok "a firing commit labeled clean still fails on status, attribution or not"
  else
    fail "expected rc=1 for a firing commit on a clean row, got rc=$RC: $out"
  fi

  printf 'fires %s no attribution recorded\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'fires as recorded' <<<"$out"; then
    ok "a fires row with no attribution field still replays on exit status alone"
  else
    fail "an attribution-less row must still work, rc=$RC: $out"
  fi
}

t_replay_asserts_clean_row_attribution() {
  local repo out culprit other sha
  mk_repo repo
  add_block "$repo" feature.txt 15 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  other="$(git -C "$repo" rev-parse HEAD~1)"
  drop_block "$repo" feature.txt alpha "docs: ordinary iteration (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"

  printf 'clean %s [%s=15] closest miss\n' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'largest sub-threshold attribution reproduced exactly' <<<"$out"; then
    ok "replay passes when a clean row's largest sub-threshold attribution reproduces"
  else
    fail "clean-row attribution should have passed, rc=$RC: $out"
  fi

  printf 'clean %s [%s=14] stale count\n' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'stays clean, but NOT as recorded' <<<"$out"; then
    ok "replay fails when a clean row's recorded line count no longer reproduces"
  else
    fail "a wrong clean-row count must fail the replay, rc=$RC: $out"
  fi

  printf 'clean %s [%s=15] wrong culprit\n' "$sha" "$other" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'stays clean, but NOT as recorded' <<<"$out"; then
    ok "replay fails when a clean row's figure is attributed to a different culprit"
  else
    fail "a wrong clean-row culprit must fail the replay, rc=$RC: $out"
  fi

  printf 'clean %s no attribution recorded\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'stays clean as recorded' <<<"$out"; then
    ok "a clean row with no attribution field still replays on exit status alone"
  else
    fail "an attribution-less clean row must still work, rc=$RC: $out"
  fi
}

t_attribute_file_git_failure_is_exit_2() {
  local repo real_git shimdir sha out
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: drop (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"

  real_git="$(command -v git)"
  fixture_tree::build shimdir --label silent-revert-shim
  cat >"$shimdir/git" <<EOF
#!/usr/bin/env bash
real_git=$(printf '%q' "$real_git")
if [[ "\${CANARY_INJECT_BLAME_FAIL:-}" == 1 && "\$1" == blame ]]; then
  echo "fatal: injected blame failure" >&2
  exit 128
fi
if [[ "\${CANARY_INJECT_DIFF_FAIL:-}" == 1 && "\$1" == diff ]]; then
  for a in "\$@"; do
    if [[ "\$a" == --unified=0 ]]; then
      echo "fatal: injected diff failure" >&2
      exit 128
    fi
  done
fi
if [[ "\${CANARY_INJECT_ENUM_FAIL:-}" == 1 && "\$1" == diff ]]; then
  for a in "\$@"; do
    if [[ "\$a" == --name-only ]]; then
      echo "fatal: injected enumeration failure" >&2
      exit 128
    fi
  done
fi
if [[ "\${CANARY_INJECT_GIT_WARN:-}" == 1 ]]; then
  if [[ "\$1" == blame ]]; then
    echo "warning: injected git noise that must not leak" >&2
  elif [[ "\$1" == diff ]]; then
    for a in "\$@"; do
      if [[ "\$a" == --unified=0 ]]; then
        echo "warning: injected git noise that must not leak" >&2
        break
      fi
    done
  fi
fi
exec "\$real_git" "\$@"
EOF
  chmod +x "$shimdir/git"

  CANARY_INJECT_BLAME_FAIL=1 PATH="$shimdir:$PATH" \
    SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'git blame failed attributing' <<<"$out"; then
    ok "a failed blame is exit 2, not a quiet zero-attribution pass"
  else
    fail "expected rc=2 on injected blame failure, rc=$RC: $out"
  fi

  CANARY_INJECT_DIFF_FAIL=1 PATH="$shimdir:$PATH" \
    SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'git diff failed attributing' <<<"$out"; then
    ok "a failed content diff is exit 2, not a quiet zero-attribution pass"
  else
    fail "expected rc=2 on injected diff failure, rc=$RC: $out"
  fi

  CANARY_INJECT_ENUM_FAIL=1 PATH="$shimdir:$PATH" \
    SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'git diff --name-only failed enumerating' <<<"$out"; then
    ok "a failed file-enumeration diff is exit 2, not a quiet ok"
  else
    fail "expected rc=2 on injected enumeration failure, rc=$RC: $out"
  fi

  printf 'fires %s [%s=40] a real drop\n' "$sha" "$(git -C "$repo" rev-parse HEAD~1)" \
    >"$repo/scripts/inc.txt"
  CANARY_INJECT_BLAME_FAIL=1 PATH="$shimdir:$PATH" \
    SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'could not run' <<<"$out"; then
    ok "a failed blame during replay is exit 2, not a row FAIL or a pass"
  else
    fail "expected rc=2 on injected blame failure in replay, rc=$RC: $out"
  fi

  CANARY_INJECT_GIT_WARN=1 PATH="$shimdir:$PATH" \
    SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && ! grep -q 'injected git noise' <<<"$out"; then
    ok "successful attribution still discards git stderr"
  else
    fail "git stderr leaked on success, or the finding disappeared, rc=$RC: $out"
  fi
}

t_replay_refuses_a_zero_row_or_truncated_file() {
  local repo out sha culprit
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"

  : >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && ! grep -q 'reproduces every recorded incident' <<<"$out"; then
    ok "an empty incident file is exit 2, not a green replay"
  else
    fail "expected rc=2 on an empty incident file, rc=$RC: $out"
  fi

  printf '# only a comment\n# still nothing pinned\n' >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && ! grep -q 'reproduces every recorded incident' <<<"$out"; then
    ok "a comments-only incident file is exit 2, not a green replay"
  else
    fail "expected rc=2 on a comments-only incident file, rc=$RC: $out"
  fi

  local line1 line2
  line1="fires $sha [$culprit=40] row 1 correct"
  line2="fires $sha [$culprit=1] row 2 wrong count"
  printf '%s\n%s\n' "$line1" "$line2" >"$repo/scripts/inc-nl.txt"
  printf '%s\n%s' "$line1" "$line2" >"$repo/scripts/inc-nonl.txt"
  local nl_bytes nonl_bytes
  nl_bytes="$(wc -c <"$repo/scripts/inc-nl.txt")"
  nonl_bytes="$(wc -c <"$repo/scripts/inc-nonl.txt")"
  if [[ "$((nl_bytes - nonl_bytes))" -eq 1 ]]; then
    ok "the newline and no-newline fixtures differ by exactly one trailing byte"
  else
    fail "newline fixture ($nl_bytes bytes) must be one byte longer than no-newline ($nonl_bytes bytes)"
  fi

  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc-nl.txt \
    run_canary "$repo" --verify-known-incidents
  local rc_nl="$RC" out_nl="$OUT"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc-nonl.txt \
    run_canary "$repo" --verify-known-incidents
  local rc_nonl="$RC" out_nonl="$OUT"

  if [[ "$rc_nl" -eq 1 && "$rc_nonl" -eq 1 ]] &&
    grep -q 'fires, but NOT as recorded' <<<"$out_nl" &&
    grep -q 'fires, but NOT as recorded' <<<"$out_nonl"; then
    ok "a two-row file without a trailing newline reaches the same FAIL as with one"
  else
    fail "newline and no-newline two-row files must both FAIL on the wrong last row; nl rc=$rc_nl nonl rc=$rc_nonl nl=$out_nl nonl=$out_nonl"
  fi

  printf 'fires %s [%s=40] the only row' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'attribution(s) reproduced exactly' <<<"$out"; then
    ok "a one-row file with no trailing newline still verifies that row"
  else
    fail "the last unterminated row must be processed, rc=$RC: $out"
  fi
}

mk_restoration_repo() {
  local repo="$1"
  printf 'the restored guard rejects a relocation\nRESTORED_MARKER_SENTINEL\n' \
    >"$repo/guarded.txt"
  printf 'SCOPED_ONLY_ELSEWHERE lives here and nowhere else\n' >"$repo/elsewhere.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: the content an incident removed"
  git -C "$repo" rev-parse HEAD
}

t_restoration_reports_present_and_absent_markers() {
  local repo out sha
  mk_repo repo
  sha="$(mk_restoration_repo "$repo")"

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'present: RESTORED_MARKER_SENTINEL' <<<"$out"; then
    ok "a restored marker resolves and the assertion exits 0"
  else
    fail "a restored marker should have passed, rc=$RC: $out"
  fi

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt NEVER_PRESENT_ANYWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'NOT RESTORED: NEVER_PRESENT_ANYWHERE' <<<"$out"; then
    ok "an absent marker fails the restoration assertion and names the content"
  else
    fail "an absent marker must fail the assertion, rc=$RC: $out"
  fi

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
    printf 'marker %s guarded.txt NEVER_PRESENT_ANYWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 1 ]] &&
    grep -q 'present: RESTORED_MARKER_SENTINEL' <<<"$out" &&
    grep -q 'NOT RESTORED: NEVER_PRESENT_ANYWHERE' <<<"$out"; then
    ok "a partial re-land (one marker back, one still absent) fails the assertion"
  else
    fail "a partially re-landed incident must still fail, rc=$RC: $out"
  fi

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt [not-restored: superseded by the shared guard] NEVER_PRESENT_ANYWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]] &&
    grep -q 'deliberately not restored: superseded by the shared guard' <<<"$out"; then
    ok "a dispositioned absent marker passes and prints its recorded reason"
  else
    fail "a dispositioned absent marker should have passed, rc=$RC: $out"
  fi

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt SCOPED_ONLY_ELSEWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && grep -q 'NOT RESTORED: SCOPED_ONLY_ELSEWHERE' <<<"$out"; then
    ok "a marker present only OUTSIDE its bound path still fails (path-scoped)"
  else
    fail "a marker matched outside its bound path is a false green, rc=$RC: $out"
  fi

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration "$sha"
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -qF "resolved at $sha" <<<"$out"; then
    ok "the assertion resolves markers at an explicitly supplied rev"
  else
    fail "an explicit rev should have resolved, rc=$RC: $out"
  fi

  SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-restoration 0123456789abcdef0123456789abcdef01234567
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "an unresolvable rev exits 2 rather than reporting content it never read"
  else
    fail "expected rc=2 on an unresolvable rev, got rc=$RC: $out"
  fi
}

t_restoration_refuses_a_malformed_corpus() {
  local repo out sha
  mk_repo repo
  sha="$(mk_restoration_repo "$repo")"

  printf 'fires %s a real drop with nothing recorded\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'carries no marker' <<<"$out"; then
    ok "a fires row carrying no marker exits 2 rather than passing vacuously"
  else
    fail "a marker-less fires row must exit 2, rc=$RC: $out"
  fi

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
    printf 'marker 0123456789abcdef0123456789abcdef01234567 guarded.txt RESTORED_MARKER_SENTINEL\n'
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q "names no recorded 'fires' incident" <<<"$out"; then
    ok "a marker naming no fires row exits 2"
  else
    fail "an orphan marker row must exit 2, rc=$RC: $out"
  fi

  local bad desc
  while read -r desc bad; do
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s %s\n' "$sha" "$bad"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    if [[ "$RC" -eq 2 ]]; then
      ok "a marker row with $desc exits 2"
    else
      fail "expected rc=2 for a marker row with $desc, got rc=$RC: $out"
    fi
  done <<'BAD_ROWS'
no-marker-text guarded.txt
a-disposition-where-the-path-should-be [not-restored: why] RESTORED_MARKER_SENTINEL
an-empty-disposition-reason guarded.txt [not-restored:] RESTORED_MARKER_SENTINEL
a-whitespace-only-disposition-reason guarded.txt [not-restored:   ] RESTORED_MARKER_SENTINEL
an-unknown-disposition-keyword guarded.txt [ignored: why] RESTORED_MARKER_SENTINEL
an-unterminated-disposition guarded.txt [not-restored: why RESTORED_MARKER_SENTINEL
BAD_ROWS

  printf '# only comments here\n' >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q "no 'fires' row" <<<"$out"; then
    ok "a corpus with no fires row exits 2 rather than passing while covering nothing"
  else
    fail "an empty corpus must exit 2, rc=$RC: $out"
  fi
  printf 'clean %s only a clean row\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "a corpus of only 'clean' rows exits 2"
  else
    fail "a clean-only corpus must exit 2, rc=$RC: $out"
  fi

  {
    printf 'fires 0123456789abcdef0123456789abcdef01234567 not a real commit\n'
    printf 'marker 0123456789abcdef0123456789abcdef01234567 guarded.txt RESTORED_MARKER_SENTINEL\n'
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'unreachable' <<<"$out"; then
    ok "a fires row naming an unreachable commit exits 2 even with a resolving marker"
  else
    fail "an unreachable incident commit must exit 2, rc=$RC: $out"
  fi

  printf 'expectations: ["x"] and ] alone\n' >>"$repo/guarded.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: bracketed content"
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt [not-restored: reason with no bracket] expectations: ["x"] and ] alone\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]] &&
    grep -q 'present: expectations: \["x"\] and \] alone' <<<"$out"; then
    ok "a dispositioned row whose MARKER text contains ']' is well-formed"
  else
    fail "a bracketed marker on a dispositioned row must resolve, rc=$RC: $out"
  fi

  printf 'expectations: ["a", "b"]\n' >>"$repo/guarded.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: content with a bracket"
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt expectations: ["a", "b"]\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "an undispositioned marker's text may contain ']'"
  else
    fail "a bracket in ordinary marker text must be fine, rc=$RC: $out"
  fi

  {
    printf '# leading comment\n'
    printf '   # an INDENTED comment\n'
    printf '   \n'
    printf '\n'
    printf 'fires %s a real drop\n' "$sha"
    printf '  # indented comment between rows\n'
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "indented comments and whitespace-only lines are skipped, not called unknown rows"
  else
    fail "a formatting-only corpus edit must not fail the assertion, rc=$RC: $out"
  fi
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -ne 2 ]]; then
    ok "the replay parses the same indented comments the restoration assertion does"
  else
    fail "the two readers disagree about comments, rc=$RC: $out"
  fi

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "${sha:0:9}"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "an abbreviated sha on a marker row exits 2"
  else
    fail "expected rc=2 on an abbreviated marker sha, got rc=$RC: $out"
  fi

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
    printf 'markers %s guarded.txt typo in the row kind\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'unknown row kind' <<<"$out"; then
    ok "an unknown row kind exits 2"
  else
    fail "expected rc=2 on an unknown row kind, got rc=$RC: $out"
  fi
}

t_restoration_binds_a_marker_to_exactly_one_file() {
  local repo out sha widened
  mk_repo repo
  sha="$(mk_restoration_repo "$repo")"

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s . NEVER_PRESENT_ANYWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -ne 0 ]]; then
    ok "a marker bound to '.' cannot be satisfied by the corpus file itself"
  else
    fail "a '.' path let the corpus satisfy its own marker, rc=$RC: $out"
  fi

  for widened in "." ".." "*" "plugins" "" "scripts" ":/" ":(glob)**/*"; do
    [[ -n "$widened" ]] || continue
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s %s RESTORED_MARKER_SENTINEL\n' "$sha" "$widened"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    local wt_rc="$RC"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration "$sha"
    if [[ "$wt_rc" -ne 0 ]] && [[ "$RC" -ne 0 ]]; then
      ok "a widened marker path '$widened' never reports the marker present"
    else
      fail "widened path '$widened' gave a false green (worktree rc=$wt_rc, rev rc=$RC): $out"
    fi
  done

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s scripts RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'bind a marker to exactly one file' <<<"$out"; then
    ok "a marker path naming a directory exits 2 and names the fix"
  else
    fail "a directory marker path must exit 2, rc=$RC: $out"
  fi

  printf 'RESTORED_MARKER_SENTINEL\n' >"$repo/untracked.txt"
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s untracked.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "an untracked file cannot satisfy a marker in working-tree mode"
  else
    fail "an untracked path must not satisfy a marker, rc=$RC: $out"
  fi
  rm -f "$repo/untracked.txt"

  if ln -s "$PWD/../outside-target.txt" "$repo/linked.txt" 2>/dev/null &&
    [[ -L "$repo/linked.txt" ]]; then
    git_test_config "$repo" add -A >/dev/null 2>&1
    git_test_config "$repo" commit -qm "chore: a symlink" >/dev/null 2>&1
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s linked.txt RESTORED_MARKER_SENTINEL\n' "$sha"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    if [[ "$RC" -eq 2 ]] && grep -q 'is a symlink' <<<"$out"; then
      ok "a tracked symlink cannot satisfy a marker in working-tree mode"
    else
      fail "a symlinked marker path must be refused as a symlink, rc=$RC: $out"
    fi
    rm -f "$repo/linked.txt"
    git_test_config "$repo" add -A >/dev/null 2>&1
    git_test_config "$repo" commit -qm "chore: drop the symlink" >/dev/null 2>&1
  fi

  local link_blob link_rev
  link_blob="$(printf '../../guarded.txt' | git_test_config "$repo" hash-object -w --stdin)"
  git_test_config "$repo" update-index --add \
    --cacheinfo "120000,$link_blob,nested/dir/linked.txt"
  git_test_config "$repo" commit -qm "chore: a nested symlink" >/dev/null
  link_rev="$(git_test_config "$repo" rev-parse HEAD)"
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s nested/dir/linked.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-restoration "$link_rev"
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && grep -q 'is a symlink at' <<<"$out"; then
    ok "a tracked symlink cannot satisfy a marker in explicit-rev mode"
  else
    fail "a symlinked marker path at a rev must exit 2, rc=$RC: $out"
  fi
  git_test_config "$repo" rm -q --cached nested/dir/linked.txt >/dev/null
  git_test_config "$repo" commit -qm "chore: drop the nested symlink" >/dev/null

  local escaping
  for escaping in "/etc/hostname" "../guarded.txt" "a/../../guarded.txt" ".."; do
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s %s RESTORED_MARKER_SENTINEL\n' "$sha" "$escaping"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    if [[ "$RC" -eq 2 ]]; then
      ok "a marker path escaping the repository ('$escaping') exits 2"
    else
      fail "escaping path '$escaping' must exit 2, rc=$RC: $out"
    fi
  done

  local globbed
  for globbed in "guarded*.txt" "guarded?.txt" "guarded[0-9].txt" ":(glob)guarded.txt"; do
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s %s RESTORED_MARKER_SENTINEL\n' "$sha" "$globbed"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    local wt_rc="$RC"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration "$sha"
    if [[ "$wt_rc" -eq 2 ]] && [[ "$RC" -eq 2 ]]; then
      ok "a glob marker path '$globbed' is refused identically in both modes"
    else
      fail "glob path '$globbed' must exit 2 in both modes (worktree=$wt_rc, rev=$RC): $out"
    fi
  done
}

t_restoration_and_replay_share_the_corpus() {
  local repo out sha culprit
  mk_repo repo
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"
  printf 'RESTORED_MARKER_SENTINEL\n' >"$repo/guarded.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "fix: re-land the content"

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'fires as recorded' <<<"$out"; then
    ok "the replay steps over marker rows instead of reading a path as a sha"
  else
    fail "marker rows must not disturb --verify-known-incidents, rc=$RC: $out"
  fi

  {
    printf 'fires %s [%s=40] a real drop\n' "$sha" "$culprit"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && grep -q 'present: RESTORED_MARKER_SENTINEL' <<<"$out"; then
    ok "a fires row carrying a bracketed attribution field still resolves its markers"
  else
    fail "the restoration parser must ignore a fires row's extra fields, rc=$RC: $out"
  fi
}

t_shipped_data_files_are_wellformed() {
  local inc="$SELF_DIR/silent-revert-incidents.txt"
  local ack="$SELF_DIR/silent-revert-acknowledged.txt"
  local bad=0 n

  if [[ ! -f "$inc" ]]; then
    fail "missing $inc"
    return
  fi
  n="$(grep -cE '^(fires|clean)[[:space:]]+[0-9a-f]{40}[[:space:]]' "$inc")"
  [[ "$n" -ge 2 ]] || bad=1
  grep -qvE '^(fires|clean|marker)[[:space:]]+[0-9a-f]{40}[[:space:]]' \
    < <(grep -vE '^[[:space:]]*(#|$)' "$inc") && bad=1
  if [[ "$bad" -eq 0 ]]; then
    ok "silent-revert-incidents.txt is well-formed with $n pinned rows"
  else
    fail "silent-revert-incidents.txt is malformed or has too few rows (n=$n)"
  fi

  local fires_rows
  fires_rows="$(grep -cE '^fires[[:space:]]' "$inc")"
  bad=0
  [[ "$fires_rows" -ge 1 ]] || bad=1
  grep -qvE '^fires[[:space:]]+[0-9a-f]{40}[[:space:]]+\[[0-9a-f]{40}=[0-9]+(,[0-9a-f]{40}=[0-9]+)*\][[:space:]]' \
    < <(grep -E '^fires[[:space:]]' "$inc") &&
    bad=1
  if [[ "$bad" -eq 0 ]]; then
    ok "every shipped fires row carries a well-formed attribution field ($fires_rows rows)"
  else
    fail "a shipped fires row is missing or has a malformed [<sha>=<lines>] attribution field"
  fi

  local clean_rows
  clean_rows="$(grep -cE '^clean[[:space:]]' "$inc")"
  bad=0
  [[ "$clean_rows" -ge 1 ]] || bad=1
  grep -qvE '^clean[[:space:]]+[0-9a-f]{40}[[:space:]]+\[[0-9a-f]{40}=[0-9]+(,[0-9a-f]{40}=[0-9]+)*\][[:space:]]' \
    < <(grep -E '^clean[[:space:]]' "$inc") &&
    bad=1
  if [[ "$bad" -eq 0 ]]; then
    ok "every shipped clean row carries a well-formed attribution field ($clean_rows rows)"
  else
    fail "a shipped clean row is missing or has a malformed [<sha>=<lines>] attribution field"
  fi

  bad=0
  local row_sha marker_shas
  marker_shas="$(awk '$1 == "marker" { print $2 }' "$inc" | sort -u)"
  while read -r row_sha; do
    [[ -n "$row_sha" ]] || continue
    grep -qxF "$row_sha" <<<"$marker_shas" || bad=1
  done < <(awk '$1 == "fires" { print $2 }' "$inc")
  if [[ "$bad" -eq 0 ]]; then
    ok "every shipped fires row carries at least one restoration marker"
  else
    fail "a shipped fires row in silent-revert-incidents.txt carries no marker row"
  fi

  bad=0
  while read -r row_sha; do
    [[ -n "$row_sha" ]] || continue
    grep -qxF "$row_sha" < <(awk '$1 == "fires" { print $2 }' "$inc") || bad=1
  done < <(printf '%s\n' "$marker_shas")
  if [[ "$bad" -eq 0 ]]; then
    ok "every shipped marker row names a recorded fires incident"
  else
    fail "a marker row in silent-revert-incidents.txt names no fires row"
  fi

  bad=0
  if [[ -f "$ack" ]]; then
    grep -qvE '^[0-9a-f]{40}[[:space:]]+[^[:space:]]' \
      < <(grep -vE '^[[:space:]]*(#|$)' "$ack") && bad=1
    if [[ "$bad" -eq 0 ]]; then
      ok "silent-revert-acknowledged.txt rows are full shas with a recorded reason"
    else
      fail "silent-revert-acknowledged.txt has a row that is not <full-sha> <reason>"
    fi
  fi
}

t_fires_on_silent_revert
t_finding_is_actionable
t_quiet_below_threshold
t_quiet_outside_recency_window
t_does_not_sum_across_culprits
t_pure_pin_bump_is_not_a_removal
t_real_removal_beside_a_pin_bump_still_fires
t_sha_line_with_changed_free_comment_still_fires
t_rename_is_not_a_removal
t_cross_file_move_is_not_a_removal
t_top_level_lines_pasted_without_their_run_still_fire
t_markdown_body_pasted_without_its_heading_still_fires
t_markdown_section_moved_with_its_heading_is_not_a_removal
t_markdown_body_pasted_under_a_copied_heading_still_fires
t_top_level_run_split_across_two_paths_still_fires
t_markdown_section_split_across_two_paths_still_fires
t_markdown_section_split_with_a_copied_heading_still_fires
t_indented_chain_split_with_a_copied_chain_still_fires
t_markdown_body_under_an_unrecognized_heading_still_fires
t_top_level_run_reordered_in_its_destination_still_fires
t_fenced_body_pasted_without_its_fences_still_fires
t_duplicate_lines_need_their_own_copies_to_move
t_whole_block_moved_into_an_existing_file_still_fires
t_recent_move_reverted_to_its_old_home_still_fires
t_block_moved_into_a_changes_fragment_still_fires
t_markdown_body_under_no_atx_heading_still_fires
t_markdown_after_a_nested_fence_still_fires
t_single_lines_scattered_to_new_files_still_fire
t_string_body_moved_out_of_a_deleted_function_still_fires
t_unmoved_duplicate_cannot_borrow_a_moved_block
t_function_pasted_inside_another_function_still_fires
t_function_moved_into_a_disabled_heredoc_still_fires
t_markdown_section_moved_into_a_wrapper_still_fires
t_function_moved_into_a_changelog_shaped_path_still_fires
t_flat_paragraphs_moved_to_new_files_still_fire
t_go_raw_string_body_moved_out_still_fires
t_markdown_tail_after_an_html_block_still_fires
t_heredoc_body_moved_out_of_a_kept_function_still_fires
t_partial_move_counts_only_the_lines_not_re_added
t_one_copy_discounts_one_deletion
t_moved_short_lines_still_count
t_function_moved_with_its_definition_is_not_a_removal
t_body_pasted_elsewhere_without_its_definition_still_fires
t_release_consuming_fragments_is_not_a_removal
t_fragments_dropped_without_changelog_still_fire
t_fragments_dropped_beside_another_changelog_still_fire
t_release_none_fragment_cleanup_is_not_a_removal
t_release_patch_fragment_drop_still_fires
t_none_front_matter_outside_fragment_layout_still_fires
t_none_fragment_drop_without_any_changelog_change_still_fires
t_counts_are_immune_to_ambient_git_config
t_rename_pin_is_load_bearing
t_minus_diff_lock_file_is_attributed
t_minus_diff_whole_file_deletion_is_attributed
t_minus_diff_recovery_is_load_bearing
t_detector_does_not_pass_text
t_explicit_binary_ascii_is_not_attributed
t_binary_asset_churn_is_not_a_finding
t_rename_limit_does_not_decompose_basename_changing_relocation
t_rename_limit_flag_is_load_bearing
t_ext_diff_pin_is_load_bearing
t_textconv_pin_is_load_bearing
t_show_signature_pin_is_load_bearing
t_declared_forms
t_conventional_revert_subject_is_declared
t_prose_mentioning_revert_still_fires
t_empty_trailer_still_fires
t_acknowledged_commit_is_cleared
t_abbreviated_ack_does_not_clear
t_ack_last_row_without_newline_is_honored
t_default_threshold_is_wired
t_range_mode_scans_every_commit
t_declared_note_ends_its_line
t_whole_file_deletion_is_attributed
t_unresolvable_range_fails_closed
t_root_commit_is_handled
t_empty_range_is_clean
t_replay_fails_on_broken_expectation
t_replay_asserts_the_recorded_attribution
t_replay_asserts_clean_row_attribution
t_attribute_file_git_failure_is_exit_2
t_replay_refuses_a_zero_row_or_truncated_file
t_restoration_reports_present_and_absent_markers
t_restoration_refuses_a_malformed_corpus
t_restoration_binds_a_marker_to_exactly_one_file
t_restoration_and_replay_share_the_corpus
t_shipped_data_files_are_wellformed

test_harness::report
