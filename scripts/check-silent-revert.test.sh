#!/usr/bin/env bash
# Unit tests for check-silent-revert.sh.
#
# Every case builds a throwaway git repository and drives the real script, so
# the suite is hermetic: it needs no network, no GitHub API, and nothing about
# this repository's own history. That split is deliberate. These tests pin the
# MECHANICS -- attribution, per-culprit aggregation, the recency window, every
# disposition path, and the fail-closed exits. The claim that the shipped
# thresholds still catch the real #2691 merges is a different claim about
# different data, and it is pinned separately by
# `check-silent-revert.sh --verify-known-incidents` against
# scripts/silent-revert-incidents.txt, which the canary workflow runs with full
# history. Neither is allowed to substitute for the other, and neither is
# allowed to skip.
#
# Most cases override SILENT_REVERT_THRESHOLD so fixtures stay small and
# readable. `default_threshold_is_wired` deliberately does not, so a typo in the
# shipped default cannot hide behind an override in every single test.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-silent-revert.sh"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

TMPDIRS=()
cleanup() {
  local d
  for d in ${TMPDIRS+"${TMPDIRS[@]}"}; do
    [[ -n "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

# A repo laid out the way the incident was: a base file, then a "culprit" commit
# that adds a block of content, then optional filler commits, then whatever the
# test wants to do to that block.
#
# It must NEVER return an empty path. Callers invoke it as `repo="$(mk_repo)"`,
# so a `return 1` from inside the command substitution cannot abort the suite --
# the caller just gets "" and carries on. And "" is not inert: `git -C ""`
# operates on the CALLER's repository, so the very next `add -A` + `commit`
# stages and commits whatever the developer happened to be working on, authored
# as `test <t@t.test>`. That is not hypothetical -- it happened during #2837's
# development when mktemp transiently failed under load, and the resulting
# commit cannot be pushed here because it fails required_signatures.
#
# So a failure yields a path that does not exist. Every git call against it then
# fails loudly and the assertions go red, which is the correct fail-closed
# outcome for a harness that cannot build its fixture. The path is derived from
# SELF_DIR rather than written as a drive-root absolute like /nonexistent/...,
# which MSYS rewrites into the Git installation prefix on Windows.
MK_REPO_FAILED="$SELF_DIR/.mk-repo-failed-this-path-does-not-exist"
mk_repo() {
  local dir
  dir="$(mktemp -d)" || {
    printf '%s' "$MK_REPO_FAILED"
    return 0
  }
  TMPDIRS+=("$dir")
  git_init_test_repo "$dir" >/dev/null || {
    printf '%s' "$MK_REPO_FAILED"
    return 0
  }
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-silent-revert.sh"
  printf 'base line %s\n' $(seq 1 5) >"$dir/feature.txt"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm "base"
  printf '%s' "$dir"
}

# add_block <repo> <file> <count> <tag> -- the content a later commit will drop.
add_block() {
  local repo="$1" file="$2" count="$3" tag="$4" i
  for i in $(seq 1 "$count"); do
    printf 'the %s guard rejects a relocation outside the session root, case %s\n' \
      "$tag" "$i" >>"$repo/$file"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the $tag guard"
}

# drop_block <repo> <file> <tag> <commit-message> -- a squash carrying a tree
# from before the block existed, exactly as the incident's merges did.
drop_block() {
  local repo="$1" file="$2" tag="$3" msg="$4"
  grep -v "the $tag guard rejects" "$repo/$file" >"$repo/$file.tmp" || true
  mv "$repo/$file.tmp" "$repo/$file"
  printf 'unrelated work from the stale branch\n' >>"$repo/$file"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "$msg"
}

filler() {
  local repo="$1" n="$2" i
  for i in $(seq 1 "$n"); do
    printf 'filler %s\n' "$i" >>"$repo/other.txt"
    git_test_config "$repo" add -A >/dev/null
    git_test_config "$repo" commit -qm "chore: unrelated change $i"
  done
}

# run_canary <repo> <args...>
#
# Sets RC and OUT. Deliberately NOT a function whose output the caller captures
# with $(...): a command substitution runs in a subshell, so an exit status
# assigned to a global inside one is silently discarded and every assertion
# degrades to "rc=0". Callers therefore invoke it as a statement and read the
# globals afterwards. Env overrides go on the call as a prefix
# (`SILENT_REVERT_THRESHOLD=20 run_canary ...`), which bash applies to the
# child process the function launches.
#
# CANARY_SCRIPT names the detector to run, relative to the fixture root. It
# defaults to the shipped path; the pin-discrimination cases below point it at a
# deliberately de-pinned copy so a run with the flag and a run without it can be
# compared. Set it as an env prefix on the call, never as a global assignment,
# so it cannot leak into the next case.
#
# A FIXTURE THAT FAILED TO BUILD MUST NOT LOOK LIKE A RESULT. mk_repo yields
# MK_REPO_FAILED when mktemp or git init fails, and `cd` into a path that does
# not exist makes the subshell exit 1 -- which is BYTE-IDENTICAL to the detector
# firing. Every `expect_rc=1` case (the false-positive-resistance ones, the
# cases that must FIRE) would then report `ok` while testing nothing, which is
# the fail-open the whole suite exists to prevent. mktemp really did fail
# transiently during #2837's development, so this is a measured mode, not a
# hypothetical one. RC=99 is outside the detector's contract (0/1/2), so no
# assertion can mistake it for an expected status, and the case is also counted
# as a failure here so the reason is named rather than inferred.
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
  tmp="$(mktemp)"
  (cd "$repo" && bash "$script" "$@") >"$tmp" 2>&1
  RC=$?
  OUT="$(cat "$tmp")"
  rm -f "$tmp"
}

# --------------------------------------------------------------------------
# 1. The incident shape itself.
# --------------------------------------------------------------------------
t_fires_on_silent_revert() {
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  filler "$repo" 2
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'SILENT REVERT SUSPECTED'; then
    ok "fires when a merge drops a block a recent commit had added"
  else
    fail "expected a finding (rc=1), got rc=$RC: $out"
  fi
}

# Requirement 4: a finding that only says "something changed" is useless. It has
# to name what vanished, which commit removed it, and which commit added it.
t_finding_is_actionable() {
  local repo out culprit remover
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse --short=9 HEAD)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  remover="$(git -C "$repo" rev-parse --short=9 HEAD)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"

  local missing=""
  printf '%s' "$out" | grep -q "$culprit" || missing="$missing adding-commit"
  printf '%s' "$out" | grep -q "$remover" || missing="$missing removing-commit"
  printf '%s' "$out" | grep -q 'feature.txt' || missing="$missing file-name"
  printf '%s' "$out" | grep -q 'the alpha guard rejects' || missing="$missing removed-content"
  if [[ -z "$missing" ]]; then
    ok "finding names the content, the remover, the adder, and the file"
  else
    fail "finding omitted:$missing -- $out"
  fi
}

# --------------------------------------------------------------------------
# 2. False-positive controls.
# --------------------------------------------------------------------------
t_quiet_below_threshold() {
  local repo out
  repo="$(mk_repo)"
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
  repo="$(mk_repo)"
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

# Per-culprit aggregation, not a repo-wide sum. Ordinary work deletes a few
# recent lines from several commits at once; summing them would re-admit exactly
# the routine case the volume threshold exists to exclude.
t_does_not_sum_across_culprits() {
  local repo out
  repo="$(mk_repo)"
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

# Renaming a file is not deleting its content. Without git's rename detection a
# `git mv` decomposes into delete + add, and every line of a moved file would be
# attributed as removed -- so relocating a large file a recent commit had added
# would fire. This repo restructures skills and docs constantly, which makes
# that a live false-positive class rather than a hypothetical one.
t_rename_is_not_a_removal() {
  local repo out
  repo="$(mk_repo)"
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

# The attribution counts must not depend on the CALLER'S GIT CONFIG. They are
# what the replay's recorded expectations assert on, so a developer's ambient
# settings deciding them means a red build on a clean tree -- which is exactly
# what #2843's first CI run hit, from `diff.algorithm = histogram`.
#
# This case is the anchor for the claim attribute_file's pin table makes, and
# it is deliberately the SAME claim: identical counts regardless of the
# CALLER's configuration. The cases after it prove each individual pin is what
# holds that true; this one proves the property itself, against several hostile
# keys at once.
#
# Four keys, all live exposures: `diff.algorithm` changes which lines a hunk
# calls deleted, `diff.renames` decomposes a rename into delete + add,
# `diff.external` replaces git's diff output wholesale, and
# `blame.ignoreRevsFile` REASSIGNS authorship away from the listed commits.
# The last is the nastiest -- on the real corpus it swung one attribution
# 853 -> 259 -- and it also does not respond to `-c key=`, only to the
# `--no-ignore-revs-file` option, so this case is what keeps that non-obvious
# distinction from being "simplified" back into a broken pin. `diff.external`
# names a path that does not exist on purpose: a pin that failed would make git
# try to run it, and the canary must not depend on how that failure presents.
t_counts_are_immune_to_ambient_git_config() {
  local repo clean_sink hostile_sink cfg revs
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  local culprit
  culprit="$(git -C "$repo" rev-parse HEAD)"
  add_block "$repo" feature.txt 30 beta
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"

  clean_sink="$(mktemp)"
  hostile_sink="$(mktemp)"
  cfg="$repo/hostile-gitconfig"
  revs="$repo/ignore-revs.txt"
  printf '%s\n' "$culprit" >"$revs"
  # Deliberately hostile but entirely legitimate developer settings.
  {
    printf '[blame]\n\tignoreRevsFile = %s\n' "$revs"
    printf '[diff]\n\talgorithm = histogram\n\trenames = false\n'
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
  rm -f "$clean_sink" "$hostile_sink"
}

# --------------------------------------------------------------------------
# 2b. Every pinned flag must be LOAD-BEARING, proven by taking it away.
# --------------------------------------------------------------------------
# The immunity case above proves the SHIPPED detector does not move under
# hostile config. It cannot prove that any individual pin is what holds it
# still: a flag whose knob turned out not to matter would pass that case
# identically. A pin nobody can show is load-bearing is a pin the next tidy
# deletes as noise, so each case below runs one fixture and one hostile config
# TWICE -- against the shipped detector and against a copy with exactly one
# flag removed -- and asserts the two DISAGREE. A case that passes both ways
# is worthless, which is the whole reason these exist.
#
# strip_pin <repo> <name> <sed-expr> writes scripts/<name>.sh and fails LOUDLY
# when the edit matched nothing. A sed that silently matches nothing -- after
# someone reflows the call it targets, say -- yields a "stripped" copy byte
# identical to the shipped one, and every assertion below would then pass
# while comparing a script against itself. That is the same fail-open shape as
# a fixture that never got built, so it is caught the same way.
#
# The comparison ignores comment lines, and that is load-bearing rather than
# tidy: the flag names these expressions match also appear in the prose ABOVE
# the calls they target. A whole-file `cmp` is therefore satisfied by comment
# collateral alone -- reflow the call at line 467 and the sed still rewrites
# the comment at line 456, the copy still "differs", and the arm silently
# compares the shipped detector against a comment-only edit. That is precisely
# the fail-open this guard exists to close, so it must compare CODE.
strip_pin() {
  local repo="$1" name="$2" expr="$3"
  local src="$repo/scripts/check-silent-revert.sh" dst="$repo/scripts/$name.sh"
  local src_code dst_code
  [[ -f "$src" ]] || {
    fail "strip_pin($name): no detector at $src -- the fixture was never built"
    return 1
  }
  sed "$expr" "$src" >"$dst" 2>/dev/null
  src_code="$(mktemp)"
  dst_code="$(mktemp)"
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

# -M. Without it, `diff.renames = false` in the caller's config decomposes a
# `git mv` into a whole-file delete plus an add, every line of the moved file
# is attributed to whoever last touched it, and relocating a large file a
# recent commit added FIRES. This repo restructures skills and docs constantly,
# so that is a live false-positive class. t_rename_is_not_a_removal covers the
# behaviour; this covers the pin that survives a hostile caller.
t_rename_pin_is_load_bearing() {
  local repo culprit cfg intact_rc stripped_rc
  repo="$(mk_repo)"
  printf 'the alpha guard rejects a relocation outside the session root, case %s\n' \
    $(seq 1 500) >"$repo/moved.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the alpha guard"
  culprit="$(git -C "$repo" rev-parse HEAD)"
  git_test_config "$repo" mv moved.txt relocated.txt >/dev/null
  git_test_config "$repo" commit -qm "refactor: relocate the guard (#99)"

  cfg="$repo/no-renames-gitconfig"
  printf '[diff]\n\trenames = false\n' >"$cfg"

  strip_pin "$repo" no-rename-pin '/git diff/ s/ -M / /g' || return 0

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

# --no-ext-diff. `diff.external` is what difftastic's and delta's own install
# instructions tell people to put in their global config, so this is ordinary
# developer configuration rather than an exotic one -- and it is a FALSE GREEN:
# the external command replaces git's diff output entirely, no @@ hunk headers
# reach attribute_file, every commit attributes nothing, and the canary reports
# `ok` on a real incident. Measured on the shipped corpus before the pin:
# cc58cbc53 under `[diff] external = /usr/bin/true` exited 0 with an empty
# findings sink, against 853 + 298 on a clean config.
#
# Only the hunk-producing diff carries the flag, and that is measured rather
# than assumed: adding it to the `--name-only` enumeration alone leaves the
# false green fully intact (rc 0, empty sink), because --name-only never runs a
# diff driver. Pinning it there too would be decoration this case could not
# defend.
t_ext_diff_pin_is_load_bearing() {
  local repo cfg intact_rc stripped_rc intact_sink stripped_sink
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 300 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"

  cfg="$repo/ext-diff-gitconfig"
  printf '[diff]\n\texternal = /usr/bin/true\n' >"$cfg"

  strip_pin "$repo" no-ext-pin 's/ --no-ext-diff//' || return 0

  intact_sink="$(mktemp)"
  stripped_sink="$(mktemp)"
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

# --no-textconv, on BOTH the diff and the blame. A `.gitattributes` entry like
# this repository's own `*.md diff=markdown` names a driver; a developer who
# then defines `diff.markdown.textconv` in their global config turns that name
# into a CONTENT TRANSFORMER, and git feeds the transformed text to diff and to
# blame alike. `--no-ext-diff` does NOT cover this -- it disallows
# `diff.<name>.command`, not textconv -- so measuring the two separately is the
# only way to know the pin set is complete.
#
# The nastiest arm is the MIXED one, which is why both halves are asserted here
# rather than left to inference. attribute_file computes -L ranges from the
# DIFF's view of the file and hands them to BLAME, so pinning only one of the
# two makes the views disagree and the ranges land on the wrong lines. Neither
# half errors; both just return a wrong number.
#
# THE TRANSFORMER HAS TO CHANGE THE LINE COUNT, and that is the whole reason
# this fixture duplicates lines rather than prepending them. A transformer that
# only PREPENDS shifts the hunk's starting offset while leaving its length
# alone, so all four arms report the identical count and the case passes
# vacuously -- it did exactly that, agreeing at 300 on every arm, until the
# transformer was changed to one that doubles. Measured here with `sed p`:
#
#        shipped (both pinned)                300   <- the truth
#        neither pinned                       600   <- diff and blame agree, wrongly
#        diff pinned, blame not          SILENT     <- the views disagree
#        blame pinned, diff not          SILENT     <- and so do these
#
# The mixed arms are the dangerous ones. The ranges and the file no longer line
# up, so part of the block falls outside them; with this fixture's 150 lines of
# earlier content the surviving count drops under the 200 threshold and the
# commit reports `ok` with an empty findings sink. Not an error, not a wrong
# number a reader might notice -- a true finding suppressed outright.
#
# `git blame` applying textconv by default is UNDOCUMENTED: `git blame -h`
# lists no --textconv/--no-textconv and git-blame's manual page contains no
# occurrence of the word, though both spellings are accepted and the flag is
# demonstrably load-bearing. So this case is also the record of why a flag with
# no entry in its own command's help is not decoration. `--no-ext-diff` is the
# mirror image and deliberately NOT on the blame call: it is accepted there,
# but blame never runs an external diff driver, so it would be decoration.
t_textconv_pin_is_load_bearing() {
  local repo cfg clean_sink intact_sink both_sink blame_sink diff_sink
  local clean_rc intact_rc live_before live_after clean_n both_n
  repo="$(mk_repo)"
  printf '*.md diff=markdown\n' >"$repo/.gitattributes"
  # feature.md needs content from an EARLIER commit ahead of the block the
  # culprit adds. Misaligned -L ranges only become visible as a changed
  # attribution when they slide off one commit's lines and onto another's; with
  # the culprit's block alone in the file, a shifted range still lands entirely
  # inside that same culprit and all four arms report 300 -- which is how this
  # case passed vacuously once already.
  #
  # 150 lines rather than a token few. The margin the mixed arms produce is
  # bounded by how far the ranges can slide, so it scales with this number:
  # measured 300 vs 295 at 5 base lines, 300 vs 240 at 60, and at 150 the
  # misattributed count falls below the 200 threshold entirely and the arm goes
  # SILENT (rc 0, empty sink). That last one is the real-world harm this pin
  # prevents -- a true finding suppressed, not merely miscounted -- so the
  # fixture is sized to reproduce it rather than the marginal case.
  printf 'base line %s\n' $(seq 1 150) >"$repo/feature.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: name a diff driver for markdown"

  add_block "$repo" feature.md 300 alpha
  drop_block "$repo" feature.md alpha "feat: unrelated feature (#99)"

  # `sed p` doubles every line, so a deleted block reports twice the deletions.
  # It is written as a bare PATH-resolved command with no script file and no
  # absolute path anywhere, which is not a stylistic choice: git spawns a
  # textconv through the platform's native process API, and on Windows that
  # cannot resolve the MSYS-style /tmp/... path mktemp -d hands back. A helper
  # script in the fixture directory therefore fails with `cannot spawn ... No
  # such file or directory`, every arm reports zero, and the case reads as "the
  # pin is inert" when nothing ever ran.
  cfg="$repo/textconv-gitconfig"
  printf '[diff "markdown"]\n\ttextconv = sed p\n' >"$cfg"

  # Prove the DRIVER ITSELF is live before asking what the detector does with
  # it. A textconv that never activates -- absent interpreter, unreadable
  # attributes, a config scope git does not consult on this platform -- would
  # make every arm below agree, and agreement would then read as "the pin does
  # nothing" when the truth is "the experiment never ran". Assert on raw git,
  # independently of the canary, so the two failures cannot be confused.
  #
  # The blame is deliberately UNBOUNDED: a -L range bounds the output, so
  # `-L1,1` returns exactly one line whether or not the file was doubled and
  # could never observe the transformation.
  live_before="$(git_test_config "$repo" blame --line-porcelain HEAD~1 -- feature.md 2>/dev/null | grep -c '^	')"
  live_after="$(GIT_CONFIG_GLOBAL="$cfg" git_test_config "$repo" blame --line-porcelain HEAD~1 -- feature.md 2>/dev/null | grep -c '^	')"
  if [[ "$live_before" -lt 1 ]] || [[ "$live_after" -ne $((live_before * 2)) ]]; then
    fail "the textconv driver is not active in this fixture (blame returned $live_before lines unfiltered and $live_after filtered, want the filtered count to be double), so this case cannot say anything about the pin -- fix the fixture, do not read this as the pin being inert"
    return 0
  fi

  strip_pin "$repo" no-textconv-pin 's/ --no-textconv//g' || return 0
  strip_pin "$repo" blame-textconv-unpinned '/git blame/ s/ --no-textconv//' || return 0
  strip_pin "$repo" diff-textconv-unpinned '/git diff --no-ext-diff/,+1 s/ --no-textconv//' || return 0

  clean_sink="$(mktemp)"
  intact_sink="$(mktemp)"
  both_sink="$(mktemp)"
  blame_sink="$(mktemp)"
  diff_sink="$(mktemp)"

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

  # The two mixed arms must go SILENT, not merely differ -- that is the harm.
  # Asserting emptiness rather than inequality also keeps this case honest if
  # the fixture is ever resized: shrink the base block and the arms start
  # reporting a wrong-but-present count, and this assertion fails rather than
  # quietly weakening to the marginal signal it started as.
  #
  # The both-stripped arm is asserted as an exact DOUBLING rather than as mere
  # inequality, for the same reason. `sed p` duplicates every line, so an
  # unpinned diff and an unpinned blame agree on a count exactly twice the
  # truth -- a specific number this case can name, and the one the table above
  # states. Inequality would also be satisfied by a count that is merely
  # different, which is how a case that measured something drifts into a case
  # that only observed a change.
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

# --no-show-signature. This repository REQUIRES signed commits, so every commit
# the canary scans on main carries one. `log.showSignature = true` in the
# CALLER's config -- an ordinary thing for a reviewer to set -- makes git
# prepend the verification result to `git log --format=` output ON STDOUT,
# which is exactly what `$(...)` captures. declares_removal reads the subject
# as `%B | head -1`, so the subject it matches becomes
# `Good "git" signature for ...`, the intent match goes blind, and the one
# deliberate revert in main's history fires as a false positive with the
# signature line printed where the report's subject belongs.
#
# This pin protects INTENT DETECTION, not the counts. No `git diff` and no
# `git blame` output passes through it, so no calibration figure moves in
# either direction -- unlike the two pins above, whose whole exposure is the
# numbers.
#
# Two things make or break this case, both measured rather than assumed:
#
#   The fixture commit must actually CARRY A SIGNATURE. With
#   commit.gpgsign=false -- what git_init_test_repo sets, and what every other
#   case here uses -- git has nothing to verify, prints nothing extra, and the
#   case would pass with and without the pin while proving nothing. The
#   signature is therefore grafted on directly: the commit object is re-emitted
#   with a `gpgsig` header and HEAD repointed at it. That needs no signing
#   program, no key, no keyring, no agent and no network, which keeps the case
#   hermetic on every platform -- an ephemeral ssh key does not, because
#   ssh-keygen refuses a private key whose permissions it considers too open
#   and Windows temp directories hand out exactly such ACLs.
#
#   It does not matter that the grafted signature is not valid. git runs the
#   verification either way and prints its verdict ahead of the message, which
#   is the whole failure: an unverifiable signature prints MORE noise, not
#   less. The case asserts on the detector's BEHAVIOUR rather than on the
#   wording of that verdict, which varies by git version and signature format.
#
#   The declared form must be SUBJECT-derived (`revert:` here). The body forms
#   -- `This reverts commit`, `Intentional-removal:` -- grep the whole message
#   with `^` anchors and survive the prepended lines untouched, so a body
#   fixture would also pass both ways.
t_show_signature_pin_is_load_bearing() {
  local repo cfg intact_rc stripped_rc intact_out grafted
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  grep -v 'the alpha guard rejects' "$repo/feature.txt" >"$repo/f.tmp" || true
  mv "$repo/f.tmp" "$repo/feature.txt"
  printf 'unrelated work from the stale branch\n' >>"$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm 'revert: remove the alpha guard (#99)'

  # Graft a signature header on. The blank line that ends the header block is
  # where it goes; everything else about the commit is reproduced verbatim.
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
  if ! git_test_config "$repo" cat-file commit HEAD 2>/dev/null | grep -q '^gpgsig'; then
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

  if [[ "$intact_rc" -eq 0 ]] && printf '%s' "$intact_out" | grep -q '^declared ' &&
    [[ "$stripped_rc" -eq 1 ]]; then
    ok "the --no-show-signature pin is load-bearing: stripped it reads a signed revert's subject as gpg output and fires, pinned it reads the declaration"
  else
    fail "the --no-show-signature pin did not discriminate (pinned rc=$intact_rc want 0 and declared, stripped rc=$stripped_rc want 1): $intact_out"
  fi
}

# --------------------------------------------------------------------------
# 3. Declared-intent forms. Constrained matching only.
# --------------------------------------------------------------------------
assert_declared() {
  local label="$1" msg="$2" expect_rc="$3"
  local repo out
  repo="$(mk_repo)"
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

# The Conventional-Commits revert type (#2837). This is the ONLY revert subject
# this repo's required PR-title gate admits, and squash_merge_commit_title:
# PR_TITLE puts the PR title on main verbatim -- so without these three forms a
# deliberate revert reaches main wearing a subject the detector cannot read.
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

# The reason why matching is constrained rather than a substring search: a
# message that merely mentions reverting must NOT silence a real finding, or the
# false-positive fix becomes a false-negative hole. Both halves are covered --
# the body (the original case) and the SUBJECT, which is what the new
# Conventional-Commits form reads and therefore what a substring bug would
# widen. `revert` must be the type token at position zero, nothing else.
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

# An empty trailer would be a blanket mute with no accountability.
t_empty_trailer_still_fires() {
  assert_declared 'an empty Intentional-removal trailer does not silence the canary' \
    "$(printf 'refactor: drop the guard (#99)\n\nIntentional-removal:\n')" 1
}

# --------------------------------------------------------------------------
# 4. Retrospective acknowledgment.
# --------------------------------------------------------------------------
t_acknowledged_commit_is_cleared() {
  local repo out sha
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"
  printf '# ack\n%s  reviewed: intentional\n' "$sha" >"$repo/scripts/ack.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_ACK=scripts/ack.txt \
    run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'reviewed and cleared'; then
    ok "a reviewed commit recorded in the acknowledgment file is cleared"
  else
    fail "expected the acknowledged commit to clear, rc=$RC: $out"
  fi
}

# Abbreviations are refused so one row can never widen to cover a commit nobody
# reviewed -- the difference between an audit trail and a mute button.
t_abbreviated_ack_does_not_clear() {
  local repo out sha
  repo="$(mk_repo)"
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

# --------------------------------------------------------------------------
# 5. Shipped defaults, range mode, whole-file removal, fail-closed exits.
# --------------------------------------------------------------------------
# No env override here on purpose: this is the only case that would catch a
# broken shipped default.
t_default_threshold_is_wired() {
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 260 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "the shipped default threshold fires on a 260-line drop"
  else
    fail "shipped default did not fire on 260 lines, rc=$RC: $out"
  fi
  # And the shipped default must not fire on a drop well under it.
  repo="$(mk_repo)"
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
  repo="$(mk_repo)"
  base="$(git -C "$repo" rev-parse HEAD)"
  add_block "$repo" feature.txt 40 alpha
  filler "$repo" 1
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" "$base..HEAD"
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'SILENT REVERT SUSPECTED'; then
    ok "range mode scans every commit in the push"
  else
    fail "expected range mode to find the revert, rc=$RC: $out"
  fi
}

# The `declared` disposition prints a two-line note, and the second line has to
# END the line. Without its trailing newline the next commit's verdict is glued
# onto it in range mode -- `...revert typeok 04a2ec188 fix(...)` -- which is
# unreadable and, worse, makes the `ok` line invisible to any `^ok ` grep. Only
# range mode shows it, because --commit mode stops after the one commit.
t_declared_note_ends_its_line() {
  local repo out base
  repo="$(mk_repo)"
  base="$(git -C "$repo" rev-parse HEAD)"
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha 'revert: remove the alpha guard (#99)'
  filler "$repo" 1
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" "$base..HEAD"
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s\n' "$out" | grep -q '^declared ' &&
    printf '%s\n' "$out" | grep -q '^ok '; then
    ok "the declared note ends its line, so the next commit's verdict is not glued to it"
  else
    fail "expected a standalone 'ok' line after the declared note, rc=$RC: $out"
  fi
}

t_whole_file_deletion_is_attributed() {
  local repo out
  repo="$(mk_repo)"
  printf 'the alpha guard rejects relocation, case %s\n' $(seq 1 40) >"$repo/guard.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the guard file"
  rm "$repo/guard.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'guard.txt'; then
    ok "a wholly deleted file is attributed like any other removal"
  else
    fail "expected the deleted file to be attributed, rc=$RC: $out"
  fi
}

# Fail-closed: an unresolvable range must exit 2 (cannot run), never 0 (clean).
# A canary that reports success when it could not see the history is the exact
# false-green this whole check exists to eliminate.
t_unresolvable_range_fails_closed() {
  local repo out
  repo="$(mk_repo)"
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
  repo="$(mk_repo)"
  run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'root commit'; then
    ok "a root commit is reported as having no parent, not crashed on"
  else
    fail "expected the root commit to be handled, rc=$RC: $out"
  fi
}

# An empty range is a real state (a push that fast-forwards nothing) and must be
# distinguishable from a failure.
t_empty_range_is_clean() {
  local repo out head
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 5 alpha
  head="$(git -C "$repo" rev-parse HEAD)"
  run_canary "$repo" "$head..$head"
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'no commits in range'; then
    ok "an empty range is clean and says so"
  else
    fail "expected an empty range to be clean, rc=$RC: $out"
  fi
}

# --------------------------------------------------------------------------
# 6. The incident-replay harness must itself fail when an expectation breaks.
# --------------------------------------------------------------------------
t_replay_fails_on_broken_expectation() {
  local repo out sha
  repo="$(mk_repo)"
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

  # Same commit, wrong expectation: the harness must go red rather than
  # rubber-stamp whatever the detector currently happens to do.
  printf 'clean %s deliberately wrong\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "replay fails when a recorded expectation no longer holds"
  else
    fail "replay should have failed on a wrong expectation, rc=$RC: $out"
  fi

  # An unreachable commit is a shallow clone, not a pass.
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

# The attribution field is the difference between "this commit still fires" and
# "this commit still fires FOR THE RECORDED REASON" (#2833). Exit status alone
# passes a row whose culprit or line count has silently moved, so each of those
# regressions is pinned here directly.
t_replay_asserts_the_recorded_attribution() {
  local repo out culprit other
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  other="$(git -C "$repo" rev-parse HEAD~1)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  local sha
  sha="$(git -C "$repo" rev-parse HEAD)"

  # Baseline: the true culprit and the true count pass.
  printf 'fires %s [%s=40] a real drop\n' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'attribution(s) reproduced exactly'; then
    ok "replay passes when the recorded culprit and line count both reproduce"
  else
    fail "replay should have passed on a correct attribution, rc=$RC: $out"
  fi

  # Right commit, right count, WRONG culprit. Exit status alone would pass this.
  printf 'fires %s [%s=40] wrong culprit\n' "$sha" "$other" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'fires, but NOT as recorded'; then
    ok "replay fails when the finding is attributed to a different culprit"
  else
    fail "a wrong recorded culprit must fail the replay, rc=$RC: $out"
  fi

  # Right commit, right culprit, WRONG count.
  printf 'fires %s [%s=39] wrong count\n' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'fires, but NOT as recorded'; then
    ok "replay fails when the recorded line count no longer reproduces"
  else
    fail "a wrong recorded line count must fail the replay, rc=$RC: $out"
  fi

  # A recorded attribution the run does not produce at all -- the two-culprit
  # shape from cc58cbc53, where the surviving finding used to carry the row.
  printf 'fires %s [%s=40,%s=301] one attribution never reproduces\n' \
    "$sha" "$culprit" "$other" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'fires, but NOT as recorded'; then
    ok "replay fails when one of two recorded attributions stops reproducing"
  else
    fail "a missing recorded attribution must fail the replay, rc=$RC: $out"
  fi

  # A malformed field must be exit 2 (cannot run), never a FAIL and never a
  # pass: an expectation silently misread is the same false green the canary
  # exists to remove.
  local bad
  # The last two shapes have no closing bracket. They matter most: a leading `[`
  # that is never closed used to fail the field-detection glob outright, so the
  # remainder became free-text note and the row fell back to passing on exit
  # status alone -- reintroducing the pre-#2833 gap by the one route nobody
  # would think to look at. Raised on #2843 by two independent review lanes.
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

  # An attribution on a `clean` row is nonsense -- clean rows have no findings.
  printf 'clean %s [%s=40] attribution on a clean row\n' "$sha" "$culprit" \
    >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "an attribution recorded on a 'clean' row exits 2"
  else
    fail "expected rc=2 for an attribution on a clean row, got rc=$RC: $out"
  fi

  # And a `fires` row with no attribution keeps working -- the field is optional
  # so a row can be pinned before its attribution has been measured.
  printf 'fires %s no attribution recorded\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'fires as recorded'; then
    ok "a fires row with no attribution field still replays on exit status alone"
  else
    fail "an attribution-less row must still work, rc=$RC: $out"
  fi
}

# The shipped data files must parse and be non-empty, so a truncated or
# malformed file cannot quietly turn the replay into a no-op.
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
  # Anything non-blank, non-comment must match the row grammar.
  grep -vE '^[[:space:]]*(#|$)' "$inc" |
    grep -qvE '^(fires|clean)[[:space:]]+[0-9a-f]{40}[[:space:]]' && bad=1
  if [[ "$bad" -eq 0 ]]; then
    ok "silent-revert-incidents.txt is well-formed with $n pinned rows"
  else
    fail "silent-revert-incidents.txt is malformed or has too few rows (n=$n)"
  fi

  # The attribution field is optional in the grammar, so nothing above would
  # notice a shipped `fires` row that quietly lost one and fell back to
  # asserting exit status alone -- which is exactly the weakness #2833 closed.
  # Every shipped `fires` row must carry a well-formed one.
  local fires_rows
  fires_rows="$(grep -cE '^fires[[:space:]]' "$inc")"
  bad=0
  [[ "$fires_rows" -ge 1 ]] || bad=1
  grep -E '^fires[[:space:]]' "$inc" |
    grep -qvE '^fires[[:space:]]+[0-9a-f]{40}[[:space:]]+\[[0-9a-f]{40}=[0-9]+(,[0-9a-f]{40}=[0-9]+)*\][[:space:]]' &&
    bad=1
  if [[ "$bad" -eq 0 ]]; then
    ok "every shipped fires row carries a well-formed attribution field ($fires_rows rows)"
  else
    fail "a shipped fires row is missing or has a malformed [<sha>=<lines>] attribution field"
  fi

  bad=0
  if [[ -f "$ack" ]]; then
    grep -vE '^[[:space:]]*(#|$)' "$ack" |
      grep -qvE '^[0-9a-f]{40}[[:space:]]+[^[:space:]]' && bad=1
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
t_rename_is_not_a_removal
t_counts_are_immune_to_ambient_git_config
t_rename_pin_is_load_bearing
t_ext_diff_pin_is_load_bearing
t_textconv_pin_is_load_bearing
t_show_signature_pin_is_load_bearing
t_declared_forms
t_conventional_revert_subject_is_declared
t_prose_mentioning_revert_still_fires
t_empty_trailer_still_fires
t_acknowledged_commit_is_cleared
t_abbreviated_ack_does_not_clear
t_default_threshold_is_wired
t_range_mode_scans_every_commit
t_declared_note_ends_its_line
t_whole_file_deletion_is_attributed
t_unresolvable_range_fails_closed
t_root_commit_is_handled
t_empty_range_is_clean
t_replay_fails_on_broken_expectation
t_replay_asserts_the_recorded_attribution
t_shipped_data_files_are_wellformed

echo
echo "check-silent-revert.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
