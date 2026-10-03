#!/usr/bin/env bash
# Unit tests for affected-tests.sh. Selection only — nothing here runs a real
# suite, because the point of the tool is that the real suites are expensive.
#
# Most scenarios build a throwaway git repo carrying a MINIATURE version of this
# repo's own shape: a shared lib with a sync manifest, two carrying plugins, and
# co-located suites. The exceptions are the two cases that must be proved
# against the LIVE repo — the derived shared-lib copy set and the real no-suite
# list — because a synthetic fixture cannot show that the derivation still
# tracks reality, which is the whole failure mode this tool exists to avoid.
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/affected-tests.sh"

# A fixture runs a COPY of the gate, so the builder stages scripts/lib/ with it:
# without those, the copy dies on a missing source at line 1 and every assertion
# below turns into the same opaque failure.
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-vars here is what tells it (SC2154) the names are written.
repo="" repo_renamed="" repo_multi="" repo2="" repo3="" repo_merge="" shimdir=""

# write_print_manifest <dest> <src> <copies-glob>
# A fixture sync script that publishes via --print-manifest. The glob is
# expanded at invocation time so a newly carrying plugin is picked up with
# no edit to this file — the same derivation the live scripts use.
write_print_manifest() {
  local dest="$1" src_path="$2" copies_glob="$3"
  cat >"$dest" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--print-manifest" ]]; then
  printf 'src\t%s\n' '${src_path}'
  shopt -s nullglob
  for c in ${copies_glob}; do
    printf 'copy\t%s\n' "\$c"
  done
  exit 0
fi
EOF
}
NO_SUITE="$SELF_DIR/affected-tests-no-suite.txt"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

# A stand-in suite that is cheap to run and records that it ran.
# shellcheck disable=SC2016 # deliberate: the emitted file must expand these, not this shell
suite_body() {
  printf '#!/usr/bin/env bash\nprintf %%s "%s" >>"${MARKER_FILE:-/dev/null}"\nexit %s\n' "$1" "${2:-0}"
}

# Write a fixture script whose only job is to source its sibling widget.sh —
# the shape that makes it a DEPENDENT of the shared lib.
# shellcheck disable=SC2016 # deliberate: the emitted file must expand these, not this shell
mk_widget_consumer() {
  printf 'source "$(dirname "${BASH_SOURCE[0]}")/widget.sh"\n' >"$1"
}

mk_repo() { # <out-var>
  local dir
  fixture_tree::build "$1" --sut "$SCRIPT" --git --label affected-tests-fixture || return 1
  dir="${!1}"

  mkdir -p "$dir/lib" "$dir/plugins/alpha/hooks" "$dir/plugins/beta/hooks"
  cp "$NO_SUITE" "$dir/scripts/affected-tests-no-suite.txt"
  # The live scopes list names suites this fixture does not have.
  printf '# fixture scopes\n' >"$dir/scripts/affected-tests-scopes.txt"

  # --jobs N delegates to the SIBLING run-plugin-tests.sh rather than spawning
  # anything itself, so the fixture carries that sibling too. Its serial
  # allowlist is empty here: the shipped one names suites this fixture does not
  # have, and the runner rejects a stale entry rather than ignoring it.
  cp "$REPO_ROOT/scripts/run-plugin-tests.sh" "$dir/scripts/run-plugin-tests.sh"
  : >"$dir/scripts/run-plugin-tests-serial.txt"

  # A sync manifest that publishes via --print-manifest, with a GLOB copy
  # pattern expanded at invocation time. The selector must read the copy set
  # from that surface rather than knowing the plugin names.
  write_print_manifest "$dir/scripts/sync-widget.sh" "lib/widget.sh" \
    "plugins/*/hooks/widget.sh"

  printf 'widget_helper() { echo widget; }\n' >"$dir/lib/widget.sh"
  suite_body lib-widget >"$dir/lib/widget.test.sh"

  local p
  for p in alpha beta; do
    printf 'widget_helper() { echo widget; }\n' >"$dir/plugins/$p/hooks/widget.sh"
    mk_widget_consumer "$dir/plugins/$p/hooks/$p-hook.sh"
    suite_body "$p-hook" >"$dir/plugins/$p/hooks/$p-hook.test.sh"
    printf '# %s plugin\n' "$p" >"$dir/plugins/$p/README.md"
  done

  # A file no suite names and no no-suite pattern covers.
  printf 'echo orphan\n' >"$dir/scripts/zzorphan-tool.sh"

  git_test_config "$dir" add scripts lib plugins >/dev/null
  git_test_config "$dir" commit -qm base >/dev/null
}

# run_sel <repo> <args...> -> selection in OUT, exit status in RC.
# Both come back through globals rather than stdout: wrapping this in a command
# substitution would run it in a subshell, and RC would silently keep whatever
# the PREVIOUS case left behind — an assertion that reads as passing while
# checking nothing.
RC=0
OUT=""
run_sel() {
  local repo="$1"
  shift
  OUT="$(cd "$repo" && bash scripts/affected-tests.sh "$@" 2>/dev/null)"
  RC=$?
}

# Captured output is matched in-shell, never piped into a reader: under pipefail
# an early-exit reader can kill the writer with SIGPIPE (see the pin below).
# has_line <text> <line>: <line> is one whole line of <text>, matched literally.
has_line() { [[ $'\n'$1$'\n' == *$'\n'"$2"$'\n'* ]]; }

# contains <text> <needle>: <needle> occurs anywhere in <text>, matched literally.
contains() { [[ $1 == *"$2"* ]]; }

# --- the match helpers hold on an input far larger than a pipe buffer -------
# A reader that exits on its first match can leave the writer to die of SIGPIPE,
# and pipefail then reports that 141 as the match failing: a present needle reads
# as absent, and a negated assertion passes. The needle sits on line 1 of 1 MB.
filler=x
for _ in {1..20}; do filler+=$filler; done
big=$'NEEDLE-LINE\n'"$filler"
unset filler
if has_line "$big" NEEDLE-LINE; then
  ok "has_line finds line 1 of a 1 MB input"
else
  fail "has_line missed line 1 of a 1 MB input"
fi
if contains "$big" NEEDLE-LINE; then
  ok "contains finds a needle on line 1 of a 1 MB input"
else
  fail "contains missed a needle on line 1 of a 1 MB input"
fi
if has_line "$big" ABSENT-LINE || contains "$big" ABSENT-NEEDLE; then
  fail "a needle absent from a 1 MB input was reported present"
else
  ok "a needle absent from a 1 MB input is reported absent by both helpers"
fi
unset big

# --- no assertion in this file pipes output into an early-exit grep --------
# The pin above covers the helpers; this keeps the piped shape from coming back
# at any other site. Comment lines are skipped, so prose may still name it.
piped_q="$(grep -nE '^[^#]*\|[[:space:]]*grep[^|]*-[a-zA-Z]*q' "$SELF_DIR/affected-tests.test.sh")"
case $? in
0) fail "non-comment lines pipe into grep -q, a SIGPIPE race under pipefail: $piped_q" ;;
1) ok "no non-comment line in this suite pipes into grep -q" ;;
*) fail "the piped grep -q guard could not read $SELF_DIR/affected-tests.test.sh" ;;
esac

# --- co-located mapping ----------------------------------------------------
mk_repo repo
run_sel "$repo" plugins/alpha/hooks/alpha-hook.sh
out="$OUT"
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/alpha/hooks/alpha-hook.test.sh &&
  ! has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
  ok "co-located: a hook selects its own suite and not a sibling plugin's"
else
  fail "co-located mapping (rc=$RC): $out"
fi

# --- a changed suite selects itself ----------------------------------------
run_sel "$repo" plugins/beta/hooks/beta-hook.test.sh
out="$OUT"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
  ok "a changed *.test.sh selects itself"
else
  fail "self-selection (rc=$RC): $out"
fi

# --- shared-lib fan-out, derived from the sync manifest --------------------
run_sel "$repo" lib/widget.sh
out="$OUT"
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" lib/widget.test.sh &&
  has_line "$out" plugins/alpha/hooks/alpha-hook.test.sh &&
  has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
  ok "shared lib fans out to every carrying plugin's suite"
else
  fail "shared-lib fan-out (rc=$RC): $out"
fi

# --- the fan-out is DERIVED, not transcribed -------------------------------
# A third carrying plugin appears with NO edit to the manifest and NO edit to
# the selector. A hardcoded copy list would miss it silently; that silent miss
# is the exact rot this test exists to catch.
mkdir -p "$repo/plugins/gamma/hooks"
printf 'widget_helper() { echo widget; }\n' >"$repo/plugins/gamma/hooks/widget.sh"
mk_widget_consumer "$repo/plugins/gamma/hooks/gamma-hook.sh"
suite_body gamma-hook >"$repo/plugins/gamma/hooks/gamma-hook.test.sh"
git_test_config "$repo" add plugins/gamma >/dev/null
git_test_config "$repo" commit -qm gamma >/dev/null
run_sel "$repo" lib/widget.sh
out="$OUT"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/gamma/hooks/gamma-hook.test.sh; then
  ok "a newly carrying plugin is picked up with no selector or manifest edit"
else
  fail "derived fan-out missed a new carrying plugin (rc=$RC): $out"
fi

# --- an empty derivation is a loud error, not an empty selection -----------
# The publisher declares a copy KEY whose entries match nothing on disk — the
# rot shape: listed copies that no longer exist. This is distinct from a
# manifest that declares no copy key at all (a canonical-only cluster with no
# carrier yet, accepted further down); the two differ at the published surface
# by the copy key's presence, so the copy line here must be explicit — the
# write_print_manifest fixture's nullglob expansion would drop it entirely.
sedless="$repo/scripts/sync-widget.sh"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [[ "${1:-}" == "--print-manifest" ]]; then\n'
  printf '  printf "src\\tlib/widget.sh\\n"\n'
  printf '  printf "copy\\tplugins/alpha/hooks/nothing-matches-this.sh\\n"\n'
  printf '  exit 0\n'
  printf 'fi\n'
} >"$sedless"
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" 'ZERO copy paths'; then
  ok "a sync manifest that yields no copies fails loudly"
else
  fail "empty derivation should exit 2 (rc=$RC): $out"
fi
rm -rf "$repo"

# --- unmapped file: fail loud, and the documented escape hatch -------------
mk_repo repo
out="$(cd "$repo" && bash scripts/affected-tests.sh scripts/zzorphan-tool.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 1 ]] && contains "$out" 'UNMAPPED'; then
  ok "a file covered by nothing exits non-zero and says so"
else
  fail "unmapped file should exit 1 with an UNMAPPED report (rc=$RC): $out"
fi

out="$(cd "$repo" && bash scripts/affected-tests.sh --allow-unmapped scripts/zzorphan-tool.sh 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  ok "--allow-unmapped downgrades the failure"
else
  fail "--allow-unmapped should exit 0 (rc=$RC): $out"
fi

# --- a FAILING git grep is fatal, never a narrower selection ---------------
# A reverse lookup reading from `< <(git grep ... 2>/dev/null || true)` would
# discard git's diagnostic and erase its exit code, making a git ERROR (>=2)
# identical to NO MATCH (1). Both would come back as "no dependents": a change
# that normally fans out to many suites would select one or none, at exit 0.
# That is under-selection reported as success — the exact fail-open this tool
# exists to refuse — so the shim below makes `git grep` fail and demands a loud
# exit.
#
# The shim delegates every other subcommand to the REAL git, captured as an
# absolute path so the shim cannot recurse into itself via PATH.
fixture_tree::build shimdir --label affected-tests-shim
REAL_GIT="$(command -v git)"
# shellcheck disable=SC2016 # deliberate: the emitted shim must expand these, not this shell
printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "grep" ]]; then\n  echo "fatal: simulated git grep failure" >&2\n  exit 128\nfi\nexec "%s" "$@"\n' "$REAL_GIT" >"$shimdir/git"
chmod +x "$shimdir/git"

# Vacuity check: the SAME invocation must succeed without the shim, or the
# assertion below would pass for a reason that has nothing to do with git grep.
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  ok "vacuity: the shared-lib selection succeeds when git grep works"
else
  fail "vacuity check failed — the shim case below would prove nothing (rc=$RC): $out"
fi

out="$(cd "$repo" && PATH="$shimdir:$PATH" bash scripts/affected-tests.sh lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" "git grep' failed"; then
  ok "a failing git grep exits 2 with a diagnostic instead of under-selecting"
else
  fail "git grep failure should be fatal, not a silent narrow selection (rc=$RC): $out"
fi
rm -rf "$shimdir"

# --- a usage error exits 2, not 1 ------------------------------------------
# `${2:?...}` exits 1, which this script already spends on an unmapped file and
# on a failing suite under --run, while the header documents usage errors as 2.
for flag in --base --print-fanout; do
  out="$(cd "$repo" && bash scripts/affected-tests.sh "$flag" 2>&1)"
  RC=$?
  if [[ "$RC" -eq 2 ]] && contains "$out" "needs a"; then
    ok "$flag with no value exits 2 (usage), not 1"
  else
    fail "$flag with no value should exit 2 (rc=$RC): $out"
  fi
done

# --- a sync-*.sh that is not a manifest is skipped, not fatal --------------
# If build_sync_map exited 2 on ANY scripts/sync-*.sh without a published src,
# the first helper that merely shares the prefix would turn this suite's
# REQUIRED CI lane red repo-wide. Half a manifest (one published key, not the
# other) must still be fatal.
printf '#!/usr/bin/env bash\necho "a helper, not a copy manifest"\n' >"$repo/scripts/sync-helper.sh"
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/alpha/hooks/alpha-hook.test.sh; then
  ok "a sync-*.sh publishing neither src nor copy is skipped, not fatal"
else
  fail "non-manifest sync-*.sh should be skipped (rc=$RC): $out"
fi

# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [[ "${1:-}" == "--print-manifest" ]]; then\n'
  printf '  printf "copy\\tplugins/alpha/hooks/widget.sh\\n"\n'
  printf '  exit 0\n'
  printf 'fi\n'
} >"$repo/scripts/sync-helper.sh"
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" 'no src='; then
  ok "a sync-*.sh that publishes copies but no src is still fatal"
else
  fail "half a manifest should exit 2 (rc=$RC): $out"
fi

# The skip must key on whether a src key is DECLARED, not on whether copies
# yielded entries. An empty src line is a half-manifest even with no copy
# lines, and the zero-manifests guard cannot catch that while the fixture's
# real sync-widget.sh still parses.
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [[ "${1:-}" == "--print-manifest" ]]; then\n'
  printf '  printf "src\\t\\n"\n'
  printf '  exit 0\n'
  printf 'fi\n'
} >"$repo/scripts/sync-helper.sh"
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" 'no src='; then
  ok "an empty published src with no copies is a half-manifest, not a helper"
else
  fail "empty src with no copies should exit 2 (rc=$RC): $out"
fi
rm -f "$repo/scripts/sync-helper.sh"

# --- a src with no copy key is a canonical-only cluster, not fatal ---------
# A shared lib that has landed with no carrier yet publishes its src and zero
# copy lines. That is not the rot the zero-yield guard exists for (declared
# copy patterns matching nothing): it must register with an empty copy set so
# the selector keeps running and --print-fanout can still name the src.
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [[ "${1:-}" == "--print-manifest" ]]; then\n'
  printf '  printf "src\\tlib/solo.sh\\n"\n'
  printf '  exit 0\n'
  printf 'fi\n'
} >"$repo/scripts/sync-solo.sh"
printf 'solo_helper() { echo solo; }\n' >"$repo/lib/solo.sh"
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/alpha/hooks/alpha-hook.test.sh; then
  ok "a src-only manifest registers as a canonical-only cluster, not fatal"
else
  fail "src-only manifest should not be fatal (rc=$RC): $out"
fi
out="$(cd "$repo" && bash scripts/affected-tests.sh --print-fanout lib/solo.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 && -z "$out" ]]; then
  ok "--print-fanout on a canonical-only src prints an empty copy set and exits 0"
else
  fail "--print-fanout on a canonical-only src should be empty and exit 0 (rc=$RC): $out"
fi
rm -f "$repo/scripts/sync-solo.sh" "$repo/lib/solo.sh"

# --- a file an earlier seed already walked past is still MAPPED ------------
# Regression: the shared lib's walk reaches alpha-hook.sh as a dependent. With
# one visited set across seeds, alpha-hook.sh's own walk was short-circuited,
# it contributed nothing, and it was reported unmapped — a false alarm that
# trains people to reach for --allow-unmapped.
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh plugins/alpha/hooks/alpha-hook.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && ! contains "$out" 'UNMAPPED'; then
  ok "a changed file reached by an earlier file's walk is not reported unmapped"
else
  fail "shared-walk file falsely unmapped (rc=$RC): $out"
fi

# --- a no-suite class is NOT an unmapped failure ---------------------------
out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/alpha/README.md 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && ! contains "$out" 'UNMAPPED'; then
  ok "a recorded no-suite path class exits 0 without an unmapped report"
else
  fail "no-suite class should exit 0 quietly (rc=$RC): $out"
fi

# --- a deleted file that maps to nothing is a visible note, not an error ---
# A deletion has no content left to cover; the loud UNMAPPED failure exists for
# paths that still EXIST with unknown coverage.
out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/alpha/hooks/removed-helper.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] &&
  contains "$out" 'deleted: plugins/alpha/hooks/removed-helper.sh' &&
  ! contains "$out" 'UNMAPPED'; then
  ok "a deleted unmapped path exits 0 with a visible deleted note"
else
  fail "deleted unmapped path should be a note, not an error (rc=$RC): $out"
fi

# --- a deletion whose co-located suite survives still selects that suite ----
# The surviving suite is exactly what fails loudly if the deletion broke
# something, so a deletion must keep selecting through every rule and only
# fall to the deleted note when NOTHING claims it.
mk_widget_consumer "$repo/plugins/alpha/hooks/gone.sh"
suite_body gone >"$repo/plugins/alpha/hooks/gone.test.sh"
rm "$repo/plugins/alpha/hooks/gone.sh"
run_sel "$repo" plugins/alpha/hooks/gone.sh
out="$OUT"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/alpha/hooks/gone.test.sh; then
  ok "a deletion with a surviving co-located suite still selects it"
else
  fail "deletion should select its surviving suite (rc=$RC): $out"
fi
rm -f "$repo/plugins/alpha/hooks/gone.test.sh"

# --- explicit paths vs the default diff ------------------------------------
base="$(git -C "$repo" rev-parse HEAD)"
printf '# edited\n' >>"$repo/plugins/beta/hooks/beta-hook.sh"
run_sel "$repo" --base "$base"
out="$OUT"
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/beta/hooks/beta-hook.test.sh &&
  ! has_line "$out" plugins/alpha/hooks/alpha-hook.test.sh; then
  ok "default mode selects from the working-tree diff against the base ref"
else
  fail "diff mode (rc=$RC): $out"
fi

# An UNCOMMITTED, UNTRACKED new file is part of the work in front of the
# developer, so the diff mode must see it too.
mk_widget_consumer "$repo/plugins/alpha/hooks/alpha-extra.sh"
suite_body alpha-extra >"$repo/plugins/alpha/hooks/alpha-extra.test.sh"
run_sel "$repo" --base "$base"
out="$OUT"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/alpha/hooks/alpha-extra.test.sh; then
  ok "diff mode includes untracked files"
else
  fail "untracked file missed by diff mode (rc=$RC): $out"
fi

# --- a merge in progress diffs against the incoming side, not the fork -----
# Merging the base branch in leaves HEAD at the pre-merge commit while the
# working tree already carries the incoming side. A file changed only there is
# not this change's work and must not be selected; the branch's own edit, left
# conflicted, still is.
mk_repo repo_merge
fork="$(git -C "$repo_merge" rev-parse HEAD)"
git_test_config "$repo_merge" checkout -q -b incoming
printf '# incoming\n' >>"$repo_merge/plugins/alpha/hooks/alpha-hook.sh"
printf '# incoming only\n' >>"$repo_merge/plugins/beta/hooks/beta-hook.sh"
git_test_config "$repo_merge" commit -qam incoming >/dev/null
git_test_config "$repo_merge" checkout -q -b feature "$fork"
printf '# feature\n' >>"$repo_merge/plugins/alpha/hooks/alpha-hook.sh"
git_test_config "$repo_merge" commit -qam feature >/dev/null
git_test_config "$repo_merge" merge -q incoming >/dev/null 2>&1
if [[ ! -f "$repo_merge/.git/MERGE_HEAD" ]]; then
  fail "fixture: the conflicting merge did not leave MERGE_HEAD behind"
else
  run_sel "$repo_merge" --base incoming
  out="$OUT"
  if [[ "$RC" -eq 0 ]] &&
    has_line "$out" plugins/alpha/hooks/alpha-hook.test.sh &&
    ! has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
    ok "mid-merge, a file changed only on the incoming side is not selected"
  else
    fail "mid-merge selection charged the incoming side's files (rc=$RC): $out"
  fi
fi

# --- a broken diff is fatal, never an empty selection ----------------------
# A producer running inside a process substitution would confine its fatal exit
# to the subshell: mapfile would succeed with nothing and the run would report
# "nothing to select" and exit 0. A validation caller would read that as clean.
out="$(cd "$repo" && bash scripts/affected-tests.sh --base definitely-not-a-ref 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && ! contains "$out" 'nothing to select'; then
  ok "an unresolvable base ref exits 2 instead of reporting an empty selection"
else
  fail "broken diff should be fatal (rc=$RC): $out"
fi

# --- an absolute path inside the repo is normalized, not silently missed ---
abs="$repo/plugins/beta/hooks/beta-hook.sh"
run_sel "$repo" "$abs"
out="$OUT"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
  ok "an absolute path under the repo root resolves to the same selection"
else
  fail "absolute path not normalized (rc=$RC): $out"
fi

# --- an absolute path from outside the repo is refused, not swallowed ------
out="$(cd "$repo" && bash scripts/affected-tests.sh /elsewhere/lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" 'absolute'; then
  ok "an absolute path outside the repo is refused out loud"
else
  fail "foreign absolute path should exit 2 (rc=$RC): $out"
fi

# --- --run executes the selected suites, sequentially ----------------------
marker="$(mktemp "$TMP_ROOT/affected-tests-marker.XXXXXX")"
: >"$marker"
(cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh --run lib/widget.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 0 ]] && grep -q 'lib-widget' "$marker" && grep -q 'beta-hook' "$marker"; then
  ok "--run executes every selected suite"
else
  fail "--run did not execute the selection (rc=$RC): $(cat "$marker")"
fi

# --- --run --jobs N hands the same selection to run-plugin-tests.sh ---------
#
# The property is that the SET of suites executed does not change with the job
# count; only how many run at once does. A second parallel runner living here
# is what this option exists to avoid, so the delegation is what is checked:
# run-plugin-tests.sh owns the worker, the print lock and the serial allowlist.
: >"$marker"
(cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh --run --jobs 3 lib/widget.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 0 ]] && grep -q 'lib-widget' "$marker" && grep -q 'beta-hook' "$marker"; then
  ok "--run --jobs 3 executes the same selection as --run"
else
  fail "--run --jobs 3 did not execute the selection (rc=$RC): $(cat "$marker")"
fi

out="$(cd "$repo" && bash scripts/affected-tests.sh --run --jobs 3 lib/widget.sh 2>&1)"
if contains "$out" 'across up to 3 job(s)'; then
  ok "--jobs 3 announces the concurrency rather than claiming sequential"
else
  fail "--jobs 3 did not report running across jobs: $out"
fi

for bad in 0 x '' -1; do
  (cd "$repo" && bash scripts/affected-tests.sh --run --jobs "$bad" lib/widget.sh >/dev/null 2>&1)
  RC=$?
  if [[ "$RC" -eq 2 ]]; then
    ok "--jobs '$bad' is a usage error, not leg 1 of 1 (rc=2)"
  else
    fail "--jobs '$bad' should exit 2, got rc=$RC"
  fi
done

# --- --shard is a partition, not a filter -----------------------------------
# The claim CI makes when it fans one selection across four runners is that the
# legs together ARE the selection and no suite ran twice. Proved on the fixture
# repo rather than the live tree on purpose: each live derivation walks the
# whole corpus, and this suite is itself one of the suites a leg runs, so a
# handful of live derivations here would cost back part of what the shard
# saves and would unbalance whichever leg drew this file.
shard_paths=(lib/widget.sh plugins/alpha/hooks/alpha-hook.sh plugins/beta/hooks/beta-hook.sh)
select_shard() {
  local spec="$1"
  local -a argv=(bash scripts/affected-tests.sh)
  [[ -n "$spec" ]] && argv+=(--shard "$spec")
  (cd "$repo" && "${argv[@]}" -- "${shard_paths[@]}" 2>/dev/null)
}
# The equals form, spelled out separately because select_shard cannot express an
# EMPTY spec: `--shard=` with nothing after it is what an environment variable
# that expanded to nothing produces, and a presence test on the value alone
# would read it as "no shard requested" and run the whole selection on every leg
# while exiting 0.
select_shard_eq() {
  (cd "$repo" && bash scripts/affected-tests.sh "--shard=$1" -- "${shard_paths[@]}" 2>/dev/null)
}

shard_rc=0
shard_full="$(select_shard "")" || shard_rc=$?
full_sorted="$(printf '%s\n' "$shard_full" | grep . | sort)"
full_count="$(printf '%s\n' "$full_sorted" | grep -c . || true)"
shard_union=""
shard_sum=0
for legix in 0 1 2; do
  leg_out="$(select_shard "$legix/3")" || shard_rc=$?
  shard_sum=$((shard_sum + $(printf '%s\n' "$leg_out" | grep -c . || true)))
  shard_union+="$leg_out"$'\n'
done
union_sorted="$(printf '%s' "$shard_union" | grep . | sort)"
if [[ "$shard_rc" -eq 0 ]] && [[ "$full_count" -ge 3 ]] &&
  [[ "$union_sorted" == "$full_sorted" ]] && [[ "$shard_sum" -eq "$full_count" ]]; then
  ok "--shard legs union to the whole selection with no suite on two legs"
else
  fail "--shard is not a partition (rc=$shard_rc, full=$full_count, sum=$shard_sum)"
fi

out="$(select_shard 0/1)"
if [[ "$(printf '%s\n' "$out" | grep . | sort)" == "$full_sorted" ]]; then
  ok "--shard 0/1 is the unsharded selection"
else
  fail "--shard 0/1 changed the selection"
fi

# The empty leg. It is the short-circuit CI depends on: a leg that draws
# nothing must EXIT 0, because a leg that skipped would make the matrix result
# `skipped` and ci-status is fail-closed on that.
out="$(select_shard 999/1000)"
RC=$?
if [[ "$RC" -eq 0 ]] && [[ -z "$(printf '%s' "$out" | grep . || true)" ]]; then
  ok "a leg with no suites exits 0 and prints no selection"
else
  fail "empty leg should exit 0 with nothing selected (rc=$RC): $out"
fi

# A spec this script cannot read must never become leg 0 of 1, which runs
# everything and would report a full pass from a typo'd fan-out. These exit
# before any derivation, so they cost nothing.
for badspec in 4/4 bogus 0/0 1/ /4 "1/4/4" "-1/4"; do
  select_shard "$badspec" >/dev/null
  RC=$?
  if [[ "$RC" -eq 2 ]]; then
    ok "--shard '$badspec' is a usage error, not a silent full run"
  else
    fail "--shard '$badspec' should exit 2, got rc=$RC"
  fi
done

out="$(select_shard_eq "")"
RC=$?
if [[ "$RC" -eq 2 ]]; then
  ok "an empty --shard= is a usage error, not a silent full run"
else
  fail "--shard= should exit 2, got rc=$RC with $(printf '%s\n' "$out" | grep -c . || true) suite(s)"
fi

out="$(select_shard_eq 0/3)"
if [[ -n "$(printf '%s' "$out" | grep . || true)" ]] &&
  [[ "$(printf '%s\n' "$out" | grep . | sort)" == "$(select_shard 0/3 | grep . | sort)" ]]; then
  ok "--shard=<spec> and --shard <spec> select the same leg"
else
  fail "the equals form of --shard does not match the space form"
fi

# --- --run --shard executes each suite on exactly one leg -------------------
# The partition above is about selection; this is about execution. Two legs are
# enough to prove each selected suite ran, on exactly one of them.
: >"$marker"
shard_rc=0
for legix in 0 1; do
  (cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh \
    --run --shard "$legix/2" lib/widget.sh >/dev/null 2>&1) || shard_rc=$?
done
marker_text="$(cat "$marker")"
count_of() { printf '%s' "$marker_text" | grep -o "$1" | grep -c . || true; }
if [[ "$shard_rc" -eq 0 ]] &&
  [[ "$(count_of lib-widget)" -eq 1 ]] &&
  [[ "$(count_of beta-hook)" -eq 1 ]]; then
  ok "--run --shard runs the whole selection across the legs, each suite once"
else
  fail "sharded --run did not cover the selection exactly once (rc=$shard_rc): $marker_text"
fi

# --- --run propagates a suite failure --------------------------------------
suite_body alpha-hook 1 >"$repo/plugins/alpha/hooks/alpha-hook.test.sh"
(cd "$repo" && bash scripts/affected-tests.sh --run plugins/alpha/hooks/alpha-hook.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 1 ]]; then
  ok "--run exits non-zero when a selected suite fails"
else
  fail "--run should propagate a suite failure (rc=$RC)"
fi
rm -rf "$repo" "$marker"

# --- LIVE repo: the derived copy set equals the published manifest today ---
# The synthetic cases above prove the mechanism; this one proves it is still
# wired to THIS repository, which is what rots. The oracle is each script's
# --print-manifest surface (not a transcription of src=/copies=( scraping), so
# renaming those variables cannot make this assertion go green for the wrong
# reason.
for src in lib/hook-utils.sh lib/parse-concern-value.sh docs/conventions/standards/README.md; do
  derived="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh --print-fanout "$src" 2>/dev/null | sort)"
  manifest="scripts/sync-shared-copies.sh"
  case "$src" in
  lib/hook-utils.sh) manifest="scripts/sync-hook-utils.sh" ;;
  *) ;;
  esac
  expected="$(cd "$REPO_ROOT" && bash "$manifest" --print-manifest | awk -F '\t' -v s="$src" '$1=="src"{on=($2==s)} on && $1=="copy" && $2!=""{print $2}' | while IFS= read -r pat; do
    if [[ -e "$pat" ]]; then
      printf '%s\n' "$pat"
    else
      # shellcheck disable=SC2086 # a published entry may still be a glob.
      for m in $pat; do [[ -e "$m" ]] && printf '%s\n' "$m"; done
    fi
  done | sort)"
  if [[ -n "$derived" && "$derived" == "$expected" ]]; then
    ok "live derivation for $src matches $manifest ($(printf '%s\n' "$derived" | wc -l | tr -d ' ') copies)"
  else
    fail "live derivation drifted for $src: derived=[$derived] expected=[$expected]"
  fi
done

# Every live sync-*.sh (except the test helper) must implement the surface.
# The publisher's stdout is captured, then matched in-shell with no pipe: an
# early-exit reader on a pipe can kill a still-writing producer with SIGPIPE,
# which this suite's pipefail then reports as a failed assertion.
live_missing=0
for manifest in "$REPO_ROOT"/scripts/sync-*.sh; do
  case "$manifest" in
  *.test.sh) continue ;;
  *) ;;
  esac
  live_out=""
  live_out="$(bash "$manifest" --print-manifest)" || {
    fail "live $manifest --print-manifest exited non-zero"
    live_missing=1
    continue
  }
  if [[ $'\n'$live_out != *$'\n'src$'\t'* ]]; then
    fail "live $manifest --print-manifest did not emit a src line"
    live_missing=1
  fi
done
if [[ "$live_missing" -eq 0 ]]; then
  ok "every live scripts/sync-*.sh implements --print-manifest"
fi

# --- renaming src/copies in the publisher does not change fan-out ----------
# The old consumer scraped those spellings out of source text. A publisher
# that never uses them, but still implements --print-manifest, must fan out
# the same way — this is the assertion that the parsed contract is gone.
mk_repo repo_renamed
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
{
  printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n'
  printf 'canonical="lib/widget.sh"\n'
  printf 'vendored=(plugins/*/hooks/widget.sh)\n'
  printf 'if [[ "${1:-}" == "--print-manifest" ]]; then\n'
  printf '  printf "src\\t%%s\\n" "$canonical"\n'
  printf '  for c in "${vendored[@]}"; do\n'
  printf '    printf "copy\\t%%s\\n" "$c"\n'
  printf '  done\n'
  printf '  exit 0\n'
  printf 'fi\n'
} >"$repo_renamed/scripts/sync-widget.sh"
run_sel "$repo_renamed" lib/widget.sh
if [[ "$RC" -eq 0 ]] &&
  has_line "$OUT" lib/widget.test.sh &&
  has_line "$OUT" plugins/alpha/hooks/alpha-hook.test.sh &&
  has_line "$OUT" plugins/beta/hooks/beta-hook.test.sh; then
  ok "a publisher that never spells src=/copies=( still fans out via --print-manifest"
else
  fail "renamed-variable publisher should still fan out (rc=$RC): $OUT"
fi
rm -rf "$repo_renamed"

# --- a publisher with several src blocks fans each one out ------------------
# scripts/sync-shared-copies.sh publishes one block per canonical. The widget
# block comes first, so a reader that keeps only the last src misses it.
mk_repo repo_multi
printf 'other() { :; }\n' >"$repo_multi/lib/other.sh"
printf 'other() { :; }\n' >"$repo_multi/plugins/alpha/hooks/other.sh"
printf '#!/usr/bin/env bash\nprintf "src\\tlib/widget.sh\\ncopy\\tplugins/alpha/hooks/widget.sh\\ncopy\\tplugins/beta/hooks/widget.sh\\nsrc\\tlib/other.sh\\ncopy\\tplugins/alpha/hooks/other.sh\\n"\n' \
  >"$repo_multi/scripts/sync-widget.sh"
run_sel "$repo_multi" --print-fanout lib/widget.sh
if [[ "$RC" -eq 0 ]] &&
  has_line "$OUT" plugins/alpha/hooks/widget.sh &&
  has_line "$OUT" plugins/beta/hooks/widget.sh &&
  ! contains "$OUT" other.sh; then
  ok "each src block in one manifest fans out to its own copies"
else
  fail "a multi-block manifest should fan out its first block (rc=$RC): $OUT"
fi
rm -rf "$repo_multi"

# The consumer must not scrape src=/copies=( source text. The old helpers
# (`manifest_src`, a `/^src=/` awk, a `/^copies=(/` grep) are the scrape.
if grep -qE 'manifest_src|manifest_copy_patterns|manifest_declares_copies|/\^src=|/\^copies=\(' \
  "$REPO_ROOT/scripts/affected-tests.sh"; then
  fail "affected-tests.sh still scrapes src=/copies=( source text"
else
  ok "affected-tests.sh no longer scrapes src=/copies=( source text"
fi

# --- LIVE repo: a real shared-lib change reaches a real carrying plugin ----
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh lib/hook-utils.sh 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" lib/hook-utils.test.sh &&
  has_line "$out" plugins/guardrails/hooks/block-no-verify.test.sh &&
  has_line "$out" plugins/eol-normalizer/hooks/eol-normalizer.test.sh; then
  ok "live shared-lib change reaches suites in more than one carrying plugin"
else
  fail "live hook-utils fan-out (rc=$RC): $out"
fi

# --- LIVE repo: a STRUCTURAL basename that is also a sync src -------------
# docs/conventions/standards/README.md is both. R3/R4 must ignore the basename
# (every plugin has a README.md, so the match carries no signal) while R5 must
# still fan the change out to the differently-named copies the manifest
# declares — plugins/*/reference/standards-contract.md — and on to the suites
# that bind against them. Neither the synthetic fixture nor the copy-set
# assertions above isolate that interaction.
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh docs/conventions/standards/README.md 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/planning/tests/standards-binding.test.sh &&
  has_line "$out" plugins/review/tests/standards-binding.test.sh; then
  ok "a structural basename that is also a sync src still fans out"
else
  fail "standards-contract fan-out (rc=$RC): $out"
fi

# --- LIVE repo: reference YAML with no lane is UNMAPPED, not silently clean --
# The reference YAML under plugins/toolchain/ and docs/conventions/
# ecosystem-commands/ is read by NO lane: no yamllint step exists, every
# check-jsonschema step names its files and none names these,
# validate-plugin-contracts.mjs never mentions yaml, and plugins/toolchain
# ships no *.test.sh. A bare *.yaml/*.yml no-suite entry (true for workflow
# YAML, false for these) would report a covering lane that does not exist, so
# these must fail loud instead.
#
# This case pins that. If someone gives these files a real lane and records the
# class again, this assertion is SUPPOSED to fail — update it together with the
# no-suite entry, and make sure the entry names the lane that actually reads
# them. Workflow YAML must stay covered via the .github/* entry throughout.
# The probe paths are DISCOVERED with a glob, never written out literally. That
# is not tidiness — a literal basename here would make this file a suite that
# "references" the probe, R3 would select it, and the path would come back
# MAPPED at exit 0. The assertion would then fail for a reason that has nothing
# to do with the no-suite list. This is the MATCHING rule documented in
# affected-tests.sh's header, met head-on: naming a file in a suite is exactly
# what makes the selector consider it covered.
# The exit status of this head pipe is never read, so its early exit is harmless.
mapfile -t eco_yaml < <(cd "$REPO_ROOT" && git ls-files \
  'plugins/toolchain/reference/ecosystems/*.yaml' \
  'docs/conventions/ecosystem-commands/examples/*.yaml' | head -2)
if [[ ${#eco_yaml[@]} -eq 0 ]]; then
  fail "no reference YAML found to probe — the case below would be vacuous"
fi
for y in ${eco_yaml[@]+"${eco_yaml[@]}"}; do
  out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh "$y" 2>&1)"
  RC=$?
  if [[ "$RC" -eq 1 ]] && contains "$out" 'UNMAPPED'; then
    ok "reference YAML with no covering lane is UNMAPPED: $y"
  else
    fail "$y should be UNMAPPED, not silently covered (rc=$RC): $out"
  fi
done

# ... while YAML under .github/, which actionlint/zizmor/check-jsonschema DO
# read, stays covered by the .github/* entry. Without this, the cases above
# would pass just as well if someone deleted .github/* too — and since the
# probe here is itself a *.yaml, it is the direct evidence that dropping the
# bare *.yaml entry did not orphan the one YAML that had a real lane.
#
# Asserted as a SILENT no-suite exit (rc 0 AND an empty selection), not merely
# rc 0: a path that some suite happens to name is selected by R3 long before the
# no-suite list is consulted, which would pass a bare rc-0 check while proving
# nothing about .github/*. That is not hypothetical — .github/workflows/ci.yml
# is named by two suites and reaches exit 0 through R3, so it cannot serve as
# this probe. Discovered by glob for the R3 reason given above.
#
# The candidate is additionally FILTERED to one that no grepped-language file
# names at all, rather than assuming the sole `.github/*.yaml` qualifies. That
# assumption held until a suite acquired a real transitive claim on it:
# .claude/cloud-bootstrap.sh's pin comment names .github/actionlint.yaml, and
# scripts/check-plugin-catalog-enablement.sh reads cloud-bootstrap.sh, so the
# walk now runs actionlint.yaml -> cloud-bootstrap.sh -> that gate's suite and
# reaches exit 0 through R3 exactly the way ci.yml does. Both edges are real and
# neither should be severed to keep a probe convenient, so the probe moves
# instead — the same resolution the ci.yml sentence above records.
#
# The filter is an INDEPENDENT oracle (a direct git grep for the basename), not
# a call to affected-tests.sh: picking the probe with the tool under test would
# make the assertion below tautological. One incoming reference anywhere is
# enough to disqualify a candidate, because R3's first level would then have
# somewhere to go.
mapfile -t wf_candidates < <(cd "$REPO_ROOT" && git ls-files '.github/*.yaml' '.github/*.yml')
wf_yaml=()
for c in ${wf_candidates[@]+"${wf_candidates[@]}"}; do
  if ! (cd "$REPO_ROOT" && git grep -q -F -- "${c##*/}" \
    -- '*.sh' '*.bash' '*.js' '*.mjs' '*.cjs' '*.py' '*.ps1' '*.psm1') 2>/dev/null; then
    wf_yaml=("$c")
    break
  fi
done
if [[ ${#wf_yaml[@]} -eq 0 ]]; then
  fail "no unreferenced .github YAML found to probe — the case below would be vacuous"
fi
for y in ${wf_yaml[@]+"${wf_yaml[@]}"}; do
  out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh "$y" 2>/dev/null)"
  RC=$?
  if [[ "$RC" -eq 0 && -z "$out" ]]; then
    ok ".github YAML stays a recorded no-suite class via .github/*: $y"
  else
    fail ".github YAML should exit 0 with no suites (rc=$RC): $out"
  fi
done

# --- LIVE repo: the false coverage that masked a real suite ----------------
# babysit_lease.py's suite is scripts/tests/test_babysit_lease.py, and nothing
# in the corpus spells that filename: every consumer says `import
# babysit_lease`. Under the old substring lookup the file still came back
# MAPPED, at exit 0, with five suites — none of them its own — purely because
# `babysit_lease.py` is a substring of `manage_babysit_lease.py`. That is the
# masked-zero-coverage shape the boundary rule exists to expose, and exposing it
# is only half the fix: the co-located rule then has to find the real suite by
# path, or a covered file reports UNMAPPED.
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh plugins/source-control/skills/babysit-prs/scripts/babysit_lease.py 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_lease.py; then
  ok "live: a .py whose only suite sits in tests/ maps to that suite"
else
  fail "live tests/ subdirectory suite (rc=$RC): $out"
fi

# --- LIVE repo: a co-located change stays narrow ---------------------------
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh plugins/eol-normalizer/hooks/eol-normalizer.sh 2>/dev/null)"
RC=$?
count="$(printf '%s\n' "$out" | grep -c '.')"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/eol-normalizer/hooks/eol-normalizer.test.sh && [[ "$count" -lt 10 ]]; then
  ok "live co-located change selects a narrow set ($count suites)"
else
  fail "live co-located selection too wide or wrong (rc=$RC, count=$count): $out"
fi

# --- per-ecosystem suite naming --------------------------------------------
# The selector was shell-only: R2 looked for <stem>.test.sh and nothing else,
# and the reverse lookup searched `-- '*.sh'`. Every one of the ~180 non-shell
# suites in this repo was therefore invisible, so a .py sitting NEXT TO its own
# test_<stem>.py was reported UNMAPPED — a false "nothing covers this" that
# trains people to reach for --allow-unmapped and erodes the fail-loud contract.
# Each ecosystem names its suites differently, so each needs its own case.
mk_repo repo
mkdir -p "$repo/eco"

# Python: the suite PREFIXES the stem, and this repo folds `-` to `_` for the
# suites covering its hyphenated scripts.
printf 'def helper():\n    return 1\n' >"$repo/eco/widget_mod.py"
printf 'import widget_mod\n' >"$repo/eco/test_widget_mod.py"
printf 'def helper():\n    return 1\n' >"$repo/eco/check-thing.py"
printf 'import importlib\n' >"$repo/eco/test_check_thing.py"

# ... and the one convention that puts the suite in a SUBDIRECTORY. The suite
# imports the MODULE, so it never spells the filename and the reference rule
# has nothing to match: only a path rule can find it.
mkdir -p "$repo/eco/pkg/tests"
printf 'def helper():\n    return 1\n' >"$repo/eco/pkg/mod_thing.py"
printf 'import mod_thing\n' >"$repo/eco/pkg/tests/test_mod_thing.py"

# Node: co-located <stem>.test.js / .test.mjs.
printf 'export const a = 1;\n' >"$repo/eco/gadget.js"
printf 'import { a } from "./gadget.js";\n' >"$repo/eco/gadget.test.js"
printf 'export const b = 2;\n' >"$repo/eco/probe.mjs"
printf 'import { b } from "./probe.mjs";\n' >"$repo/eco/probe.test.mjs"

# Pester: the suite SUFFIXES the stem and lives in a mirrored tree, so it is
# found by the reference rule (it dot-sources the file) rather than by R2.
mkdir -p "$repo/eco/ps" "$repo/eco/pstests"
printf 'function Get-Thing { 1 }\n' >"$repo/eco/ps/Get-Thing.ps1"
printf ". (Join-Path \$PSScriptRoot 'Get-Thing.ps1')\nDescribe 'Get-Thing' { }\n" >"$repo/eco/pstests/Get-Thing.Tests.ps1"

run_sel "$repo" eco/widget_mod.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/test_widget_mod.py; then
  ok "python: a co-located test_<stem>.py is selected"
else
  fail "python co-located (rc=$RC): $OUT"
fi

run_sel "$repo" eco/check-thing.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/test_check_thing.py; then
  ok "python: a hyphenated stem finds its underscore-folded suite"
else
  fail "python hyphen fold (rc=$RC): $OUT"
fi

run_sel "$repo" eco/pkg/mod_thing.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/pkg/tests/test_mod_thing.py; then
  ok "python: a suite in a tests/ subdirectory covers its module"
else
  fail "python tests/ subdirectory (rc=$RC): $OUT"
fi

run_sel "$repo" eco/gadget.js
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/gadget.test.js; then
  ok "node: a co-located <stem>.test.js is selected"
else
  fail "node co-located (rc=$RC): $OUT"
fi

run_sel "$repo" eco/probe.mjs
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/probe.test.mjs; then
  ok "node: a co-located <stem>.test.mjs is selected"
else
  fail "node .mjs co-located (rc=$RC): $OUT"
fi

run_sel "$repo" eco/ps/Get-Thing.ps1
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/pstests/Get-Thing.Tests.ps1; then
  ok "powershell: a Pester suite in a mirrored tree is found by reference"
else
  fail "pester reference (rc=$RC): $OUT"
fi

# --- a changed non-shell suite selects ITSELF (R1 is not shell-only) --------
run_sel "$repo" eco/test_widget_mod.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/test_widget_mod.py; then
  ok "a changed non-shell suite selects itself"
else
  fail "non-shell self-selection (rc=$RC): $OUT"
fi

# --- BOTH covering suites, not just the first ------------------------------
# A .py can be covered twice over: by a co-located test_<stem>.py AND by a
# <stem>.test.sh that drives it. Returning only the first is an under-selection,
# the one direction this tool treats as unsafe, so both must come back.
printf 'def helper():\n    return 1\n' >"$repo/eco/dual.py"
printf 'import dual\n' >"$repo/eco/test_dual.py"
suite_body dual >"$repo/eco/dual.test.sh"
run_sel "$repo" eco/dual.py
if [[ "$RC" -eq 0 ]] &&
  has_line "$OUT" eco/test_dual.py &&
  has_line "$OUT" eco/dual.test.sh; then
  ok "a file covered in two ecosystems selects BOTH suites"
else
  fail "dual-ecosystem coverage (rc=$RC): $OUT"
fi

# --- R4: another language counts only where it runs or loads the file ------
# A file in another language that merely contains the name (a string, a log
# message) is not a dependent and its suite is not selected: across languages
# the text says nothing about a dependency unless the line runs or loads the
# file. An interpreter on the line or a path to the file does; a bare name from
# the file's own directory, with no interpreter on the line, does not.
mkdir -p "$repo/eco/hop" "$repo/eco/elsewhere"
printf 'export const c = 3;\n' >"$repo/eco/hop/origin.js"
printf 'echo "origin.js is the entry point"\n' >"$repo/eco/elsewhere/mention.test.sh"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
printf 'node "$ROOT/eco/hop/origin.js"\n' >"$repo/eco/elsewhere/node-runs.test.sh"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
printf 'cp "$SRC/eco/hop/origin.js" "$DEST"\n' >"$repo/eco/elsewhere/path-loads.test.sh"
printf 'run_suite origin.js\n' >"$repo/eco/hop/wrapper.test.sh"
printf 'node origin.js\n' >"$repo/eco/hop/node-wrapper.test.sh"
# A .py naming a shell script by bare name, with no interpreter on the line,
# is not a dependent of it either.
printf 'echo hop\n' >"$repo/eco/hop/hop-tool.sh"
printf 'TOOL = "hop-tool.sh"\n' >"$repo/eco/hop/test_hop_listing.py"
# A .ps1 that runs the js, so the walk crosses into it once, and a shell file
# that runs the .ps1: reaching ITS suite takes a second transition.
printf "node origin.js\nfunction Get-Far { 2 }\n" >"$repo/eco/hop/Far.ps1"
suite_body far >"$repo/eco/hop/Far.Tests.ps1"
printf 'pwsh -File Far.ps1\n' >"$repo/eco/hop/far-runner.sh"
suite_body far-runner >"$repo/eco/hop/far-runner.test.sh"
run_sel "$repo" eco/hop/origin.js
if ! has_line "$OUT" eco/elsewhere/mention.test.sh &&
  has_line "$OUT" eco/elsewhere/node-runs.test.sh &&
  has_line "$OUT" eco/elsewhere/path-loads.test.sh &&
  has_line "$OUT" eco/hop/node-wrapper.test.sh &&
  ! has_line "$OUT" eco/hop/wrapper.test.sh; then
  ok "R4: another language's suite runs only where its line runs or loads the file"
else
  fail "R4: cross-language selection wrong (rc=$RC): $OUT"
fi
if has_line "$OUT" eco/hop/Far.Tests.ps1 && ! has_line "$OUT" eco/hop/far-runner.test.sh; then
  ok "R4: a chain crosses languages once and cannot cross a second time"
else
  fail "R4: the transition budget was not applied (rc=$RC): $OUT"
fi
run_sel "$repo" eco/hop/hop-tool.sh
if ! has_line "$OUT" eco/hop/test_hop_listing.py; then
  ok "R4: a bare shell-script name in another language is not a dependency"
else
  fail "R4: a bare .sh name selected a Python suite (rc=$RC): $OUT"
fi

# --- --run refuses to guess a runner for another ecosystem -----------------
# Selected-but-not-run must never report as success. The invocations differ per
# lane (python -m unittest against a named module, npm test, node --test,
# vitest, Pester) and cannot be derived from a suite path; a guessed runner
# either errors as though the suite failed, or exits 0 having run nothing, which
# is a PASS the change never earned. Exit 3 says "ran the shell ones, these
# still need their own lane".
OUT="$(cd "$repo" && bash scripts/affected-tests.sh --run eco/gadget.js 2>&1)"
RC=$?
if [[ "$RC" -eq 3 ]] && contains "$OUT" 'NOT RUN'; then
  ok "--run reports a non-shell suite as NOT RUN and exits 3"
else
  fail "--run should exit 3 naming the unrun suite (rc=$RC): $OUT"
fi

# --- LIVE repo: the false-UNMAPPED regression this all exists to fix -------
# hook_telemetry.py sits directly beside test_hook_telemetry.py and was still
# reported UNMAPPED. Asserted against the LIVE repo, not a fixture: the point is
# that the tool tracks THIS corpus's real conventions.
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh plugins/disk-hygiene/lib/hook_telemetry.py 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/disk-hygiene/lib/test_hook_telemetry.py; then
  ok "live: a .py beside its test_<stem>.py is no longer UNMAPPED"
else
  fail "live python co-located selection (rc=$RC): $out"
fi

# --- crossing once does not stop the walk in the destination language ------
# The cap is one language TRANSITION per path, not one hop. A weaker
# "stop dead after crossing" rule looks equivalent and is not: helper.py ->
# runner.sh -> command.sh -> command.test.sh is a real chain whose SECOND edge is
# shell-to-shell, and stopping at runner.sh drops command.test.sh. That is an
# under-selection, which this tool treats as the unsafe direction, so the
# destination-language walk has to keep going.
mk_repo repo
mkdir -p "$repo/eco/chain"
printf 'def helper():\n    return 1\n' >"$repo/eco/chain/helper.py"
# The shell wrapper that drives the Python helper: one crossing, py -> sh.
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these, not this shell
printf 'python3 "$(dirname "$0")/helper.py"\n' >"$repo/eco/chain/runner.sh"
# A shell dependent of the wrapper: the SECOND edge, shell -> shell.
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these, not this shell
printf 'source "$(dirname "$0")/runner.sh"\n' >"$repo/eco/chain/command.sh"
suite_body command >"$repo/eco/chain/command.test.sh"

run_sel "$repo" eco/chain/helper.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/chain/command.test.sh; then
  ok "after crossing languages once, the same-family walk continues"
else
  fail "py -> sh -> sh chain lost its suite (rc=$RC): $OUT"
fi

# --- Python imports name the module they load ---------------------------------
# `import tool` never spells tool.py, so the import line is the edge: from the
# module's directory or below it, by a dotted path that spells it, or from
# anywhere in the plugin when the module name is unique there. A module of the
# same name elsewhere in the plugin makes the bare import ambiguous, and a
# module nothing imports selects only its own suites.
mkdir -p "$repo/plugins/alpha/scripts/tests" "$repo/plugins/alpha/skills/one/scripts" \
  "$repo/plugins/beta/scripts" "$repo/plugins/alpha/pkg/sub"
printf 'def run():\n    return 1\n' >"$repo/plugins/alpha/scripts/tool.py"
printf 'from tool import run\n' >"$repo/plugins/alpha/scripts/runner.py"
printf 'import runner\n' >"$repo/plugins/alpha/scripts/test_runner.py"
printf 'import sys\nimport tool as t\n' >"$repo/plugins/alpha/scripts/tests/test_tool_behavior.py"
printf 'import tool\n' >"$repo/plugins/alpha/skills/one/scripts/use_tool.py"
printf 'import use_tool\n' >"$repo/plugins/alpha/skills/one/scripts/test_use_tool.py"
printf 'from . import tool\n' >"$repo/plugins/alpha/scripts/rel_user.py"
printf 'import rel_user\n' >"$repo/plugins/alpha/scripts/test_rel_user.py"
printf 'import tool\n' >"$repo/plugins/beta/scripts/other.py"
printf 'import other\n' >"$repo/plugins/beta/scripts/test_other.py"
printf 'X = 1\n' >"$repo/plugins/alpha/pkg/sub/deep.py"
printf 'from pkg.sub.deep import X\n' >"$repo/plugins/alpha/dotted.py"
printf 'import dotted\n' >"$repo/plugins/alpha/test_dotted.py"
git_test_config "$repo" add plugins >/dev/null
git_test_config "$repo" commit -qm pyimports >/dev/null
run_sel "$repo" plugins/alpha/scripts/tool.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/scripts/test_runner.py &&
  has_line "$OUT" plugins/alpha/scripts/tests/test_tool_behavior.py &&
  has_line "$OUT" plugins/alpha/skills/one/scripts/test_use_tool.py &&
  has_line "$OUT" plugins/alpha/scripts/test_rel_user.py &&
  ! has_line "$OUT" plugins/beta/scripts/test_other.py; then
  ok "python: an import (also 'from . import') selects from the module's directory, below it, and across its plugin"
else
  fail "python: import selection wrong for tool.py (rc=$RC): $OUT"
fi
run_sel "$repo" plugins/alpha/pkg/sub/deep.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/test_dotted.py; then
  ok "python: a dotted import that spells the module's path selects"
else
  fail "python: dotted import lost (rc=$RC): $OUT"
fi
printf 'def run():\n    return 2\n' >"$repo/plugins/alpha/skills/one/scripts/tool.py"
run_sel "$repo" plugins/alpha/scripts/tool.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/scripts/test_runner.py &&
  ! has_line "$OUT" plugins/alpha/skills/one/scripts/test_use_tool.py; then
  ok "python: a module name two directories of a plugin carry resolves by directory only"
else
  fail "python: an ambiguous module name still selected across the plugin (rc=$RC): $OUT"
fi
rm -f "$repo/plugins/alpha/skills/one/scripts/tool.py"

# --- the crossing budget is aggregated per path, never assigned ------------
# One path can be hit several times in a single round by different patterns, and
# those hits can disagree about whether the chain reaching it has already
# crossed. Assigning rather than aggregating let whichever hit `git grep` emitted
# LAST decide, so an incidental cross-family mention could spend a path's budget
# and block its own genuine crossing later — order-dependent under-selection.
#
# Reaching two families in ONE round takes a cross-family sync manifest, since
# R5 seeds every copy alongside the source. zed.sh names the shell source first
# and the JS copy second, so a last-write-wins bug resolves to "already crossed".
mk_repo repo2
mkdir -p "$repo2/eco/agg" "$repo2/plugins/alpha/hooks"
write_print_manifest "$repo2/scripts/sync-mixed.sh" "lib/mixed.sh" \
  "plugins/*/hooks/mixed.js"
printf 'mixed_helper() { echo mixed; }\n' >"$repo2/lib/mixed.sh"
printf 'export const mixed = 1;\n' >"$repo2/plugins/alpha/hooks/mixed.js"

# Names the shell source FIRST, the JS copy SECOND — so the cross-family hit is
# the one a last-write-wins bug would keep. The second line runs the copy, so
# R4 takes it as a crossing; a bare mention would make no dependent at all.
printf 'source "lib/mixed.sh"\nnode mixed.js\n' >"$repo2/eco/agg/zed.sh"
# A genuine crossing OUT of zed.sh, which is exactly what a wrongly-spent budget
# would block. Its suite is the assertion.
printf 'import subprocess  # drives zed.sh\n' >"$repo2/eco/agg/zed_user.py"
printf 'import zed_user\n' >"$repo2/eco/agg/test_zed_user.py"

run_sel "$repo2" lib/mixed.sh
if has_line "$OUT" eco/agg/test_zed_user.py; then
  ok "a path's crossing budget survives an unrelated cross-family hit"
else
  fail "crossing budget was spent by an incidental hit (rc=$RC): $OUT"
fi

# --- R3/R4 NAME a file, they do not merely contain its name ----------------
# The reverse lookup used to be an unanchored substring search, so any basename
# that sat inside another path in the corpus inherited that path's suites. That
# is not just noisy over-selection: it is FALSE COVERAGE at exit 0, which is the
# one direction this tool is built to refuse. `get.sh` is a substring of
# `widget.sh`, which this fixture references from every plugin, so a new
# get.sh covered by nothing at all used to come back mapped.
mk_repo repo3
mkdir -p "$repo3/eco/name"
printf 'echo get\n' >"$repo3/plugins/alpha/hooks/get.sh"

# A file that is ONLY ever named path-qualified. `/` is not a path-token
# character, so this must keep selecting: it is the shape of every real
# `source "$dir/lib.sh"` and `import "./gadget.js"` in the corpus.
printf 'echo target\n' >"$repo3/eco/name/deep-target.sh"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
{
  printf '#!/usr/bin/env bash\n'
  printf 'bash "$REPO_ROOT/eco/name/deep-target.sh"\n'
} >"$repo3/eco/name/driver.test.sh"

# A file only ever named at the END OF A SENTENCE. The trailing `.` is
# punctuation, not part of the name, and this is how half the comments in this
# repo cite the suite that covers them.
printf 'echo prose\n' >"$repo3/eco/name/prose-target.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "Every rejected shape is covered by prose-target.sh."\n'
} >"$repo3/eco/name/prose.test.sh"

# A file named with an ELLIPSIS butted straight against it. The mirror of the
# sentence-final case, and the narrower one: `./x` never needs the strip because
# the `/` already delimits the token, so only a literal `...x` reaches it. It is
# a real prose shape and it is in the over-selecting direction, so it is kept —
# and kept means tested, or the branch is just an untested claim.
printf 'echo ellipsis\n' >"$repo3/eco/name/ellipsis-target.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "the rest of that argument lives in ...ellipsis-target.sh"\n'
} >"$repo3/eco/name/ellipsis.test.sh"

# A basename the token rule cannot spell, because `+` is not a path-token
# character. Such a name must fall back to the old substring test rather than
# to no coverage at all — a name the rule cannot express has to over-select.
printf 'echo plus\n' >"$repo3/eco/name/plus+tool.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'bash eco/name/plus+tool.sh\n'
} >"$repo3/eco/name/plus.test.sh"

# A file whose only mention from its DEPENDENT sits behind a shell default:
# `"${TARGET:-<name>}"`. The `-` of the `:-` operator is inside the path-token
# class, so without the operator strip the token is `-<name>` and the reverse
# lookup never reaches the dependent.
#
# This case is here because it fails SILENTLY, which is worse than the shapes
# above and is why it must be tested rather than argued about. The target has a
# co-located suite of its own, so it stays MAPPED and the run still exits 0 —
# while the dependent's suite, the one that actually drives it, is quietly
# dropped. That is an under-selection reported as success, the exact failure
# this whole file is built to refuse. Both suites must come back.
printf 'echo defaulted\n' >"$repo3/eco/name/defaulted-target.sh"
suite_body defaulted-target >"$repo3/eco/name/defaulted-target.test.sh"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
{
  printf '#!/usr/bin/env bash\n'
  printf 'TARGET="${TARGET:-defaulted-target.sh}"\n'
  printf 'bash "$(dirname "${BASH_SOURCE[0]}")/$TARGET"\n'
} >"$repo3/eco/name/defaulting-runner.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'bash eco/name/defaulting-runner.sh\n'
} >"$repo3/eco/name/defaulting-runner.test.sh"

git_test_config "$repo3" add plugins eco >/dev/null
git_test_config "$repo3" commit -qm names >/dev/null

out="$(cd "$repo3" && bash scripts/affected-tests.sh plugins/alpha/hooks/get.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 1 ]] && contains "$out" 'UNMAPPED'; then
  ok "a basename buried in a longer token is UNMAPPED, not falsely covered"
else
  fail "get.sh should be UNMAPPED, not covered by widget.sh's suites (rc=$RC): $out"
fi

# The exit code alone is not the assertion: what must be gone is the SELECTION
# the substring match handed it. Under --allow-unmapped the run proceeds, so an
# empty selection is direct evidence that no unrelated suite was borrowed.
run_sel "$repo3" --allow-unmapped plugins/alpha/hooks/get.sh
if [[ "$RC" -eq 0 && -z "$OUT" ]]; then
  ok "the borrowed suites are gone, not merely re-labeled"
else
  fail "get.sh still selects unrelated suites (rc=$RC): $OUT"
fi

run_sel "$repo3" eco/name/deep-target.sh
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/name/driver.test.sh; then
  ok "a path-qualified reference still names the file"
else
  fail "path-qualified reference lost (rc=$RC): $OUT"
fi

run_sel "$repo3" eco/name/prose-target.sh
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/name/prose.test.sh; then
  ok "a reference at the end of a sentence still names the file"
else
  fail "sentence-final reference lost (rc=$RC): $OUT"
fi

run_sel "$repo3" eco/name/ellipsis-target.sh
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/name/ellipsis.test.sh; then
  ok "a reference butted against an ellipsis still names the file"
else
  fail "ellipsis-prefixed reference lost (rc=$RC): $OUT"
fi

run_sel "$repo3" eco/name/defaulted-target.sh
if [[ "$RC" -eq 0 ]] &&
  has_line "$OUT" eco/name/defaulted-target.test.sh &&
  has_line "$OUT" eco/name/defaulting-runner.test.sh; then
  ok "a reference behind a \${VAR:-default} still names the file"
else
  fail "defaulted reference lost its dependent's suite (rc=$RC): $OUT"
fi

run_sel "$repo3" eco/name/plus+tool.sh
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/name/plus.test.sh; then
  ok "a basename the token rule cannot spell falls back to the substring test"
else
  fail "untokenizable basename lost its coverage (rc=$RC): $OUT"
fi

# R1/R2 are a path rule and never went through the reverse lookup, so the same
# substring-shaped file must still find its own co-located suite — and still not
# the ones it used to borrow.
suite_body get >"$repo3/plugins/alpha/hooks/get.test.sh"
run_sel "$repo3" plugins/alpha/hooks/get.sh
if [[ "$RC" -eq 0 ]] &&
  has_line "$OUT" plugins/alpha/hooks/get.test.sh &&
  ! has_line "$OUT" plugins/beta/hooks/beta-hook.test.sh; then
  ok "co-located selection is untouched by the boundary rule"
else
  fail "co-located suite lost or unrelated suite still borrowed (rc=$RC): $OUT"
fi
rm -rf "$repo3"

# --- a comment-only mention makes no dependent and selects no suite ----------
# Hub files cite neighboring scripts in prose, and counting those as edges
# fanned one plugin's change out to most of the corpus; a suite citing a file
# in prose does not run it either. Every code line still names the file, as do
# a trailing comment on one, a shellcheck source directive and a JSDoc type
# import.
mk_repo repo3
mkdir -p "$repo3/eco/cmt"
printf 'echo hub\n' >"$repo3/eco/cmt/hub-target.sh"
suite_body hub-target >"$repo3/eco/cmt/hub-target.test.sh"
# Each dependent below has a suite of its own that does not name hub-target.sh,
# so that suite comes back only through an R4 edge.
mk_cmt_dependent() { # <stem> <ext> <body>
  printf '%b' "$3" >"$repo3/eco/cmt/$1.$2"
  suite_body "$1" >"$repo3/eco/cmt/$1.test.$2"
}
mk_cmt_dependent sh-comment sh '#!/usr/bin/env bash\n# see hub-target.sh\n  # also hub-target.sh\necho hub\n'
mk_cmt_dependent js-comment js '// see hub-target.sh\n/* hub-target.sh */\n/**\n * hub-target.sh\n */\nexport const x = 1;\n'
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
mk_cmt_dependent sh-code sh 'source "$(dirname "$0")/hub-target.sh"\n'
mk_cmt_dependent sh-trailing sh 'echo ok # runs after hub-target.sh\n'
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
mk_cmt_dependent sh-directive sh '# shellcheck source=hub-target.sh\n. "$HUB"\n'
mk_cmt_dependent js-code js 'spawnSync("bash", ["hub-target.sh"]);\n'
mk_cmt_dependent js-typeimport js '/** @import { T } from "./hub-target.sh" */\n/** @param {import("./hub-target.sh").T} t */\nexport const y = 2;\n'
printf '#!/usr/bin/env bash\n# covers hub-target.sh\n' >"$repo3/eco/cmt/hub-prose.test.sh"
# A Python import never spells the .py, so a comment naming the module is the
# only text edge from an importer; it keeps counting. Prose alone does not.
printf 'X = 1\n' >"$repo3/eco/cmt/hubmod.py"
printf 'import hubmod\n' >"$repo3/eco/cmt/test_hubmod.py"
printf '# hubmod.py is shared with a sibling\nfrom hubmod import X\n' >"$repo3/eco/cmt/pyimporter.py"
printf 'import pyimporter\n' >"$repo3/eco/cmt/test_pyimporter.py"
printf '# see hubmod.py\nimport os\n' >"$repo3/eco/cmt/pyprose.py"
printf 'import pyprose\n' >"$repo3/eco/cmt/test_pyprose.py"
git_test_config "$repo3" add eco >/dev/null
git_test_config "$repo3" commit -qm comments >/dev/null

run_sel "$repo3" eco/cmt/hub-target.sh
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/cmt/hub-target.test.sh &&
  ! has_line "$OUT" eco/cmt/sh-comment.test.sh &&
  ! has_line "$OUT" eco/cmt/js-comment.test.js; then
  ok "a comment-only mention in a non-suite file no longer selects"
else
  fail "comment-only mention still made a dependent (rc=$RC): $OUT"
fi

if has_line "$OUT" eco/cmt/sh-code.test.sh &&
  has_line "$OUT" eco/cmt/sh-trailing.test.sh &&
  has_line "$OUT" eco/cmt/sh-directive.test.sh &&
  has_line "$OUT" eco/cmt/js-code.test.js &&
  has_line "$OUT" eco/cmt/js-typeimport.test.js; then
  ok "a code mention, a trailing comment, a shellcheck directive and a JSDoc import still select"
else
  fail "a non-comment mention lost its dependent (rc=$RC): $OUT"
fi

if ! has_line "$OUT" eco/cmt/hub-prose.test.sh; then
  ok "a suite that names the file only in a comment is not selected"
else
  fail "a suite's comment-only mention still selected it (rc=$RC): $OUT"
fi

run_sel "$repo3" eco/cmt/hubmod.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/cmt/test_pyimporter.py &&
  ! has_line "$OUT" eco/cmt/test_pyprose.py; then
  ok "a comment naming a module the .py imports by name still selects; prose alone does not"
else
  fail "python import-by-name comment edge lost or prose comment kept (rc=$RC): $OUT"
fi
rm -rf "$repo3"

# --- LIVE repo: ci.yml actually fans the selection out -----------------------
# `--shard` only buys anything if the workflow both PASSES it and creates more
# than one runner to pass it from. Either half alone is silently useless: a
# shard spec with no matrix runs leg 0 of 1 (everything, as before), and a
# matrix with no shard spec runs the whole selection on every leg. Pinned
# together, in the job that owns them.
live_ci="$REPO_ROOT/.github/workflows/ci.yml"
test_bash_block="$(awk '
  /^  [A-Za-z_][A-Za-z0-9_-]*:[[:blank:]]*(#.*)?$/ {
    job = $0; sub(/:.*$/, "", job); sub(/^  /, "", job)
  }
  job == "test-bash"
' "$live_ci")"
# shellcheck disable=SC2016 # deliberate: these are workflow literals to match, not shell expansions.
if grep -q 'affected-tests\.sh --run --jobs 3 --shard "\$LEG/\$LEGS"' <<<"$test_bash_block" &&
  grep -q '^    strategy:' <<<"$test_bash_block" &&
  grep -q 'LEG: \${{ strategy\.job-index }}' <<<"$test_bash_block" &&
  grep -q 'LEGS: \${{ strategy\.job-total }}' <<<"$test_bash_block"; then
  ok "ci.yml test-bash declares a matrix, runs three suites at a time, and passes the leg through to --shard"
else
  fail "ci.yml test-bash no longer fans the affected selection across a matrix at --jobs 3"
fi

# --- ci.yml never asks for more than the proven three ------------------------
# #3694: at --jobs 4 three separate suites failed by producing empty output from
# an external command. Three is the ceiling, on either path.
if grep -qE -- '--jobs ([04-9]|[1-9][0-9]+)' "$live_ci"; then
  fail "ci.yml passes a --jobs count other than 3: $(grep -oE -- '--jobs [0-9]+' "$live_ci" | sort -u | tr '\n' ' ')"
else
  ok "ci.yml asks for no more than the proven three concurrent suites (#3694)"
fi

# --- R7: the autonomy reference tree selects the plugin-contract suite -------
# Those files are markdown no suite names, so without a path rule they fell to
# the no-suite *.md class while the contract validator gates them. The scope is
# pinned both ways: nested files are in, and neither another plugin's
# reference/ nor an autonomy file outside reference/ is.
contract_suite=scripts/validate-plugin-contracts.test.sh
mk_repo repo
mkdir -p "$repo/plugins/autonomy/reference/sub" "$repo/plugins/beta/reference"
suite_body plugin-contracts >"$repo/$contract_suite"
printf '# top\n' >"$repo/plugins/autonomy/reference/top-doc.md"
printf '# nested\n' >"$repo/plugins/autonomy/reference/sub/nested-doc.md"
printf '# autonomy\n' >"$repo/plugins/autonomy/README.md"
printf '# other\n' >"$repo/plugins/beta/reference/other-doc.md"
git_test_config "$repo" add scripts plugins >/dev/null
git_test_config "$repo" commit -qm reference >/dev/null

for p in plugins/autonomy/reference/top-doc.md plugins/autonomy/reference/sub/nested-doc.md; do
  run_sel "$repo" "$p"
  if [[ "$RC" -eq 0 ]] && has_line "$OUT" "$contract_suite"; then
    ok "R7: $p selects the plugin-contract suite"
  else
    fail "R7: $p did not select the plugin-contract suite (rc=$RC): $OUT"
  fi
done

out="$(cd "$repo" && bash scripts/affected-tests.sh --explain plugins/autonomy/reference/top-doc.md 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && contains "$out" "select: $contract_suite  (path class:"; then
  ok "R7: --explain reports the path-class reason"
else
  fail "R7: --explain lacks the path-class reason (rc=$RC): $out"
fi

for p in plugins/beta/reference/other-doc.md plugins/autonomy/README.md; do
  run_sel "$repo" "$p"
  if [[ "$RC" -eq 0 ]] && ! has_line "$OUT" "$contract_suite"; then
    ok "R7 scope: $p does not select the plugin-contract suite"
  else
    fail "R7 scope: $p selected the plugin-contract suite or failed (rc=$RC): $OUT"
  fi
done
rm -rf "$repo"

# --- LIVE repo: a real autonomy reference doc selects the contract suite -----
# The probe doc is discovered, never spelled: a basename written here would make
# this suite name that file, and R3 would then cover it without R7. The suite
# path above IS spelled on purpose: renaming the suite selects this file, and
# this case then fails instead of R7 silently selecting nothing.
# The assertion is on the R7 reason, not on bare selection: a live doc can also
# reach the suite through R4 fan-out (a hook naming it), which would pass without
# R7. The seed is walked first, so R7's reason is the one recorded.
# The exit status of this head pipe is never read, so its early exit is harmless.
live_ref="$(cd "$REPO_ROOT" && git ls-files 'plugins/autonomy/reference/*.md' | head -n 1)"
if [[ -z "$live_ref" ]]; then
  fail "LIVE R7: no tracked plugins/autonomy/reference/*.md to probe"
else
  out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh --explain "$live_ref" 2>&1)"
  RC=$?
  if [[ "$RC" -eq 0 ]] && contains "$out" "select: $contract_suite  (path class:"; then
    ok "LIVE R7: $live_ref selects the plugin-contract suite through R7"
  else
    fail "LIVE R7: $live_ref did not select the plugin-contract suite through R7 (rc=$RC): $out"
  fi
fi

# --- R8: a declared scope selects the suite that scans a directory -----------
# A suite that greps or globs a directory never spells the files it reads, so
# scripts/affected-tests-scopes.txt declares them, and a matching change selects
# it and counts as mapped. Pinned: the glob crosses `/`, the plugin's other
# suites stay out, an inline comment ends the entry, and a plugin file nothing
# names or declares is still UNMAPPED.
mk_repo repo
mkdir -p "$repo/plugins/alpha/skills/one" "$repo/plugins/alpha/tests"
printf -- '---\nname: one\n---\n' >"$repo/plugins/alpha/skills/one/SKILL.md"
printf 'kind: probe\n' >"$repo/plugins/alpha/skills/one/probe.yaml"
suite_body alpha-scan >"$repo/plugins/alpha/tests/scan.test.sh"
printf 'import test from "node:test";\n' >"$repo/plugins/alpha/tests/scan.test.mjs"
printf 'import unittest\n' >"$repo/plugins/alpha/tests/test_scan.py"
printf 'echo orphan\n' >"$repo/plugins/alpha/zzorphan-plugin.sh"
{
  printf '# fixture scopes\n'
  printf 'plugins/alpha/tests/scan.test.sh  plugins/alpha/skills/*.md plugins/alpha/*.yaml  # scans skill bodies\n'
  printf 'plugins/alpha/tests/scan.test.mjs  plugins/alpha/skills/*/SKILL.md\n'
} >"$repo/scripts/affected-tests-scopes.txt"
git_test_config "$repo" add plugins scripts >/dev/null
git_test_config "$repo" commit -qm r8 >/dev/null

run_sel "$repo" plugins/alpha/skills/one/SKILL.md
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/tests/scan.test.sh &&
  has_line "$OUT" plugins/alpha/tests/scan.test.mjs &&
  ! has_line "$OUT" plugins/alpha/hooks/alpha-hook.test.sh &&
  ! has_line "$OUT" plugins/alpha/tests/test_scan.py; then
  ok "R8: a SKILL.md edit selects the suites that declare it and no other suite of the plugin"
else
  fail "R8: declared-scope selection wrong for a SKILL.md edit (rc=$RC): $OUT"
fi

out="$(cd "$repo" && bash scripts/affected-tests.sh --explain plugins/alpha/skills/one/SKILL.md 2>&1)"
if contains "$out" "select: plugins/alpha/tests/scan.test.sh  (test-scope plugins/alpha/skills/*.md)" &&
  ! contains "$out" "scans skill bodies"; then
  ok "R8: --explain reports the declared glob"
else
  fail "R8: --explain lacks the declared glob: $out"
fi

run_sel "$repo" plugins/alpha/skills/one/probe.yaml
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/tests/scan.test.sh; then
  ok "R8: a declared file no other rule reaches is mapped, not UNMAPPED"
else
  fail "R8: a declared file was not mapped by its scope (rc=$RC): $OUT"
fi

run_sel "$repo" plugins/alpha/zzorphan-plugin.sh
if [[ "$RC" -eq 1 ]]; then
  ok "R8: a plugin file no suite names or declares is still UNMAPPED"
else
  fail "R8: a plugin file nothing names or declares was mapped (rc=$RC): $OUT"
fi

# The list is checked: an entry naming no suite fails every run, and a glob
# matching no file fails the run that changes the list.
cp "$repo/scripts/affected-tests-scopes.txt" "$TMP_ROOT/scopes.keep"
printf 'plugins/alpha/tests/gone.test.sh  plugins/alpha/*\n' >>"$repo/scripts/affected-tests-scopes.txt"
out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/beta/hooks/beta-hook.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" "names 'plugins/alpha/tests/gone.test.sh', which is not a suite"; then
  ok "R8: an entry naming no suite fails the run"
else
  fail "R8: a stale suite entry was not refused (rc=$RC): $out"
fi
cp "$TMP_ROOT/scopes.keep" "$repo/scripts/affected-tests-scopes.txt"
printf 'plugins/alpha/tests/scan.test.sh  plugins/nowhere/*\n' >>"$repo/scripts/affected-tests-scopes.txt"
out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/beta/hooks/beta-hook.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  ok "R8: a glob matching nothing is not checked while the list is unchanged"
else
  fail "R8: an unchanged list failed the run (rc=$RC): $out"
fi
out="$(cd "$repo" && bash scripts/affected-tests.sh --allow-unmapped scripts/affected-tests-scopes.txt 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" '  - plugins/nowhere/*'; then
  ok "R8: a changed list declaring a glob that matches nothing fails loud"
else
  fail "R8: a stale glob in a changed list was not refused (rc=$RC): $out"
fi
cp "$TMP_ROOT/scopes.keep" "$repo/scripts/affected-tests-scopes.txt"
out="$(cd "$repo" && bash scripts/affected-tests.sh --allow-unmapped scripts/affected-tests-scopes.txt 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  ok "R8: a changed list whose globs all match passes the check"
else
  fail "R8: a valid list was refused (rc=$RC): $out"
fi

# --- --unmapped-corpus: an unmapped file selects its own language's corpus ---
# The report stays, the exit says so (4), and only the file's language runs: a
# shell file never starts the Python corpus, and the other way round.
run_sel "$repo" --unmapped-corpus plugins/alpha/zzorphan-plugin.sh
if [[ "$RC" -eq 4 ]] && has_line "$OUT" plugins/alpha/tests/scan.test.sh &&
  has_line "$OUT" plugins/beta/hooks/beta-hook.test.sh && has_line "$OUT" lib/widget.test.sh &&
  ! has_line "$OUT" plugins/alpha/tests/test_scan.py && ! has_line "$OUT" plugins/alpha/tests/scan.test.mjs; then
  ok "--unmapped-corpus: an unmapped .sh selects the shell corpus only, at exit 4"
else
  fail "--unmapped-corpus: wrong corpus or exit for an unmapped .sh (rc=$RC): $OUT"
fi
printf 'X = 1\n' >"$repo/plugins/alpha/zz_orphan_mod.py"
run_sel "$repo" --unmapped-corpus plugins/alpha/zz_orphan_mod.py
if [[ "$RC" -eq 4 ]] && has_line "$OUT" plugins/alpha/tests/test_scan.py &&
  ! has_line "$OUT" plugins/alpha/tests/scan.test.sh; then
  ok "--unmapped-corpus: an unmapped .py selects the Python corpus only"
else
  fail "--unmapped-corpus: wrong corpus for an unmapped .py (rc=$RC): $OUT"
fi
out="$(cd "$repo" && bash scripts/affected-tests.sh --unmapped-corpus plugins/alpha/zz_orphan_mod.py 2>&1 >/dev/null)"
if contains "$out" 'UNMAPPED: 1 changed file(s)'; then
  ok "--unmapped-corpus: the unmapped report is still printed"
else
  fail "--unmapped-corpus: the unmapped report went missing: $out"
fi
run_sel "$repo" --unmapped-corpus --allow-unmapped plugins/alpha/zz_orphan_mod.py
if [[ "$RC" -eq 2 ]]; then
  ok "--unmapped-corpus with --allow-unmapped is a usage error"
else
  fail "--unmapped-corpus with --allow-unmapped should exit 2 (rc=$RC)"
fi
rm -rf "$repo"

# --- --with-always is accepted and widens nothing ----------------------------
# A caller that still passes it must neither fail nor get a wider selection:
# the live-tree suites it used to add are declared in the scopes list now.
mk_repo repo
run_sel "$repo" --with-always plugins/alpha/hooks/alpha-hook.sh
with_out="$OUT" with_rc="$RC"
run_sel "$repo" plugins/alpha/hooks/alpha-hook.sh
if [[ "$with_rc" -eq 0 && "$RC" -eq 0 && "$with_out" == "$OUT" ]]; then
  ok "--with-always is accepted and changes nothing"
else
  fail "--with-always changed the run (rc=$with_rc vs $RC): [$with_out] vs [$OUT]"
fi
rm -rf "$repo"

# --- LIVE repo: the two suite breaks only a full main run caught --------------
# Both were a skill body edit breaking a suite that never spells the body's
# path the plain way: one scans its plugin's markdown (R8 declares it), the
# other spells the body relative to its plugin (AMBIGUOUS NAMES resolves it).
# The probe bodies are discovered, never spelled, so this suite does not name
# them and run on every edit to them.
for probe in 'plugins/github/skills/advise/S*.md|plugins/github/github.test.sh' \
  'plugins/planning/skills/interview/S*.md|plugins/planning/tests/interview-defenses.test.sh'; do
  body="$(cd "$REPO_ROOT" && git ls-files "${probe%%|*}")"
  out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh "$body" 2>/dev/null)"
  RC=$?
  if [[ -n "$body" && "$RC" -eq 0 ]] && has_line "$out" "${probe#*|}"; then
    ok "LIVE: $body selects ${probe#*|}"
  else
    fail "LIVE: '$body' did not select ${probe#*|} (rc=$RC): $out"
  fi
done

# --- ambiguous names: a shared basename counts only where it resolves ------
# Skills reuse reference names freely, so a bare `probe-doc.md` says nothing
# about which one. A mention names a file only when it resolves to it: a path
# suffix no other file of that name ends in, any mention from the file's own
# directory, or a path relative to a directory below the root holding both
# files. The structural docs (SKILL.md and the like) always resolve this way.
mk_repo repo
own_a=plugins/alpha/skills/sa
own_b=plugins/alpha/skills/sb
mkdir -p "$repo/$own_a/reference" "$repo/$own_a/scripts" "$repo/$own_b/reference" "$repo/$own_b/scripts" \
  "$repo/plugins/beta/skills/sc/scripts" "$repo/plugins/gamma/skills/sa/reference" \
  "$repo/plugins/alpha/skills/one" "$repo/plugins/beta/skills/one" "$repo/plugins/alpha/tests" \
  "$repo/plugins/alpha/.claude-plugin"
for d in "$own_a" "$own_b" plugins/gamma/skills/sa; do
  printf '# probe\n' >"$repo/$d/reference/probe-doc.md"
done
# shellcheck disable=SC2016 # deliberate: the emitted fixtures must expand these
{
  printf 'grep -q wording "$SKILL_DIR/reference/probe-doc.md"\n' >"$repo/$own_a/scripts/sa.test.sh"
  printf 'grep -q wording "$SKILL_DIR/reference/probe-doc.md"\n' >"$repo/$own_b/scripts/sb.test.sh"
  printf 'grep -q wording "$ROOT/plugins/alpha/skills/sb/reference/probe-doc.md"\n' \
    >"$repo/plugins/beta/skills/sc/scripts/sc.test.sh"
  printf 'grep -q wording probe-doc.md\n' >"$repo/plugins/beta/skills/sc/scripts/sc-bare.test.sh"
  printf 'cat plugins/gamma/skills/sa/reference/probe-doc.md\n' >"$repo/plugins/beta/skills/sc/scripts/sc-gamma.test.sh"
  # A bare name from a directory above the file: one probe-doc.md below gamma's
  # skill, two below alpha's skills/ directory.
  printf 'grep -c . probe-doc.md\n' >"$repo/plugins/gamma/skills/sa/above.test.sh"
  printf 'grep -c . probe-doc.md\n' >"$repo/plugins/alpha/skills/above-both.test.sh"
  printf '# reads plugins/alpha/skills/sa/reference/probe-doc.md\n' >"$repo/$own_a/scripts/sa-comment.test.sh"
  # A bare mention from the file's own directory, in a script whose suite is its sibling.
  printf 'grep -c . probe-doc.md\n' >"$repo/$own_a/reference/count.sh"
  suite_body count >"$repo/$own_a/reference/count.test.sh"
  # The SKILL.md shape: a plugin suite spelling the body relative to its plugin.
  printf -- '---\nname: one\n---\n' >"$repo/plugins/alpha/skills/one/SKILL.md"
  printf -- '---\nname: one\n---\n' >"$repo/plugins/beta/skills/one/SKILL.md"
  printf 'body="$PLUGIN_DIR/skills/one/SKILL.md"\n' >"$repo/plugins/alpha/tests/skill-body.test.sh"
  printf '{ "name": "alpha" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
  printf 'jq . "$PLUGIN_DIR/.claude-plugin/plugin.json"\n' >"$repo/plugins/alpha/tests/manifest.test.sh"
}
git_test_config "$repo" add plugins >/dev/null
git_test_config "$repo" commit -qm ambiguous >/dev/null

run_sel "$repo" "$own_a/reference/probe-doc.md"
if [[ "$RC" -eq 0 ]] && has_line "$OUT" "$own_a/scripts/sa.test.sh" &&
  has_line "$OUT" "$own_a/reference/count.test.sh" &&
  ! has_line "$OUT" "$own_b/scripts/sb.test.sh" &&
  ! has_line "$OUT" plugins/beta/skills/sc/scripts/sc.test.sh &&
  ! has_line "$OUT" plugins/beta/skills/sc/scripts/sc-bare.test.sh &&
  ! has_line "$OUT" plugins/beta/skills/sc/scripts/sc-gamma.test.sh &&
  ! has_line "$OUT" "$own_a/scripts/sa-comment.test.sh"; then
  ok "ambiguous: skill-relative and same-directory mentions resolve; bare, other-skill and comment ones do not"
else
  fail "ambiguous: skill A's probe-doc.md selection wrong (rc=$RC): $OUT"
fi

run_sel "$repo" "$own_b/reference/probe-doc.md"
if [[ "$RC" -eq 0 ]] && has_line "$OUT" "$own_b/scripts/sb.test.sh" &&
  has_line "$OUT" plugins/beta/skills/sc/scripts/sc.test.sh &&
  ! has_line "$OUT" "$own_a/scripts/sa.test.sh"; then
  ok "ambiguous: a unique path suffix resolves from another plugin"
else
  fail "ambiguous: skill B's probe-doc.md selection wrong (rc=$RC): $OUT"
fi

run_sel "$repo" plugins/gamma/skills/sa/reference/probe-doc.md
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/beta/skills/sc/scripts/sc-gamma.test.sh &&
  ! has_line "$OUT" "$own_a/scripts/sa.test.sh"; then
  ok "ambiguous: a same-named skill in another plugin is told apart by its path"
else
  fail "ambiguous: gamma's probe-doc.md selection wrong (rc=$RC): $OUT"
fi
if has_line "$OUT" plugins/gamma/skills/sa/above.test.sh; then
  ok "ambiguous: a bare name from above resolves when only one such file sits below"
else
  fail "ambiguous: a bare name unique below its namer did not resolve (rc=$RC): $OUT"
fi
run_sel "$repo" "$own_a/reference/probe-doc.md"
if ! has_line "$OUT" plugins/alpha/skills/above-both.test.sh; then
  ok "ambiguous: a bare name from above does not resolve when two such files sit below"
else
  fail "ambiguous: a bare name with two files below its namer resolved (rc=$RC): $OUT"
fi

run_sel "$repo" plugins/alpha/skills/one/SKILL.md
alpha_out="$OUT" alpha_rc="$RC"
run_sel "$repo" plugins/beta/skills/one/SKILL.md
if [[ "$alpha_rc" -eq 0 ]] && has_line "$alpha_out" plugins/alpha/tests/skill-body.test.sh &&
  [[ "$RC" -eq 0 ]] && ! has_line "$OUT" plugins/alpha/tests/skill-body.test.sh; then
  ok "ambiguous: a SKILL.md spelled relative to its plugin selects that plugin's suite only"
else
  fail "ambiguous: SKILL.md resolution wrong (rc=$alpha_rc/$RC): [$alpha_out] [$OUT]"
fi

# MANIFESTS: a suite that spells its plugin's manifest exactly is still not
# selected by it; the manifest gates own it.
run_sel "$repo" plugins/alpha/.claude-plugin/plugin.json
if [[ "$RC" -eq 0 && -z "$OUT" ]]; then
  ok "manifests: a plugin.json selects no suite through a mention"
else
  fail "manifests: plugin.json selected a suite (rc=$RC): $OUT"
fi

# A path that spells only the name, or a path from the repository root alone,
# could be a file the suite builds under a temporary directory, so neither
# resolves; a mention from the file's own directory does.
printf '# root\n' >"$repo/README.md"
# shellcheck disable=SC2016 # deliberate: the emitted fixtures must expand these
{
  printf 'grep -q x "$PLUGIN_DIR/README.md"\n' >"$repo/plugins/alpha/tests/readme.test.sh"
  printf 'grep -q x "$REPO_ROOT/README.md"\n' >"$repo/scripts/zz-root-readme.test.sh"
  # docs/guide.md at the root and a fixture copy ending in the same path.
  printf 'grep -q x "$REPO_ROOT/docs/guide.md"\n' >"$repo/scripts/zz-root-path.test.sh"
  printf 'grep -q x README.md\n' >"$repo/zz-root-local.test.sh"
}
mkdir -p "$repo/docs" "$repo/plugins/alpha/fixtures/docs"
printf '# guide\n' >"$repo/docs/guide.md"
printf '# guide\n' >"$repo/plugins/alpha/fixtures/docs/guide.md"
run_sel "$repo" README.md
root_out="$OUT"
run_sel "$repo" plugins/alpha/README.md
if has_line "$root_out" zz-root-local.test.sh && ! has_line "$root_out" scripts/zz-root-readme.test.sh &&
  ! has_line "$root_out" plugins/alpha/tests/readme.test.sh && ! has_line "$OUT" plugins/alpha/tests/readme.test.sh; then
  ok "ambiguous: a path spelling only the name does not resolve; the file's own directory does"
else
  fail "ambiguous: name-only path resolution wrong: [$root_out] [$OUT]"
fi
run_sel "$repo" docs/guide.md
if [[ "$RC" -eq 0 ]] && ! has_line "$OUT" scripts/zz-root-path.test.sh; then
  ok "ambiguous: a path from the repository root alone does not resolve"
else
  fail "ambiguous: a root-relative path resolved (rc=$RC): $OUT"
fi
rm -rf "$repo"

# --- R5 copies inside skill directories still reach every copy's suite -------
# A shared source outside any skill, copied into each skill's reference/, with
# each skill's suite naming its own copy bare. The basename is carried three
# times, but a shared library's copies keep the plain rule, so the source's
# fan-out reaches every suite.
mk_repo repo
mkdir -p "$repo/plugins/alpha/skills/sa/reference" "$repo/plugins/beta/skills/sb/reference"
write_print_manifest "$repo/scripts/sync-guard.sh" "lib/guard-util.sh" \
  "plugins/*/skills/*/reference/guard-util.sh"
printf 'guard_util() { echo guard; }\n' >"$repo/lib/guard-util.sh"
for p in alpha beta; do
  s=s${p:0:1}
  printf 'guard_util() { echo guard; }\n' >"$repo/plugins/$p/skills/$s/reference/guard-util.sh"
  printf '#!/usr/bin/env bash\nsource guard-util.sh\n' >"$repo/plugins/$p/skills/$s/reference/$s.test.sh"
done
git_test_config "$repo" add lib scripts plugins >/dev/null
git_test_config "$repo" commit -qm guard >/dev/null

run_sel "$repo" lib/guard-util.sh
if [[ "$RC" -eq 0 ]] &&
  has_line "$OUT" plugins/alpha/skills/sa/reference/sa.test.sh &&
  has_line "$OUT" plugins/beta/skills/sb/reference/sb.test.sh; then
  ok "R5: an in-skill shared-lib copy still reaches every copy's suite"
else
  fail "R5: in-skill copy fan-out lost a suite (rc=$RC): $OUT"
fi

# The out-of-skill shape (hook-utils.sh style): the fixture's widget.sh copies
# live in plugins/*/hooks/, each consumer suite sourcing its own plugin's copy.
run_sel "$repo" lib/widget.sh
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/hooks/alpha-hook.test.sh &&
  has_line "$OUT" plugins/beta/hooks/beta-hook.test.sh; then
  ok "R5: a hooks-dir shared-lib copy still reaches every copy's suite"
else
  fail "R5: hooks-dir copy fan-out lost a suite (rc=$RC): $OUT"
fi
rm -rf "$repo"

# --- --replay: each commit selected against its parent, with this tree's rules --
# A replay carries this tree's lists to every commit, since the commits may
# predate them; --against runs the selector at <ref> with <ref>'s lists and
# prints only the suites the two disagree on.
mk_repo repo
printf '#!/usr/bin/env bash\necho old\n' >"$repo/scripts/zz-old-scan.test.sh"
printf '#!/usr/bin/env bash\necho new\n' >"$repo/scripts/zz-new-scan.test.sh"
printf 'scripts/zz-old-scan.test.sh  plugins/alpha/*\n' >"$repo/scripts/affected-tests-scopes.txt"
git_test_config "$repo" add scripts >/dev/null
git_test_config "$repo" commit -qm scans >/dev/null
printf '# edited\n' >>"$repo/plugins/alpha/hooks/alpha-hook.sh"
git_test_config "$repo" commit -qam 'edit alpha hook' >/dev/null
alpha_commit="$(git -C "$repo" rev-parse HEAD)"
printf 'scripts/zz-new-scan.test.sh  plugins/alpha/*\n' >"$repo/scripts/affected-tests-scopes.txt"

out="$(cd "$repo" && bash scripts/affected-tests.sh --replay HEAD~1..HEAD 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] && has_line "$out" "commit $alpha_commit 2 0  edit alpha hook" &&
  has_line "$out" "  plugins/alpha/hooks/alpha-hook.test.sh  (co-located with plugins/alpha/hooks/alpha-hook.sh)" &&
  has_line "$out" "  scripts/zz-new-scan.test.sh  (test-scope plugins/alpha/*)"; then
  ok "--replay selects each commit against its parent with this tree's declarations"
else
  fail "--replay output wrong (rc=$RC): $out"
fi

out="$(cd "$repo" && bash scripts/affected-tests.sh --replay HEAD~1..HEAD --against HEAD 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && has_line "$out" "commit $alpha_commit 2 2 0 0  edit alpha hook" &&
  has_line "$out" "  + scripts/zz-new-scan.test.sh  (test-scope plugins/alpha/*)" &&
  has_line "$out" "  - scripts/zz-old-scan.test.sh  (test-scope plugins/alpha/*)" &&
  ! contains "$out" "alpha-hook.test.sh" && contains "$out" "replay: 1 commit(s)"; then
  ok "--replay --against prints only the suites the two selectors disagree on, and a summary"
else
  fail "--replay --against output wrong (rc=$RC): $out"
fi

# A commit this selector maps to no suite still reports what <ref> ran as
# dropped, not as added.
printf 'scripts/zz-old-scan.test.sh  plugins/beta/*\n' >"$repo/scripts/affected-tests-scopes.txt"
git_test_config "$repo" commit -qam 'scan beta' >/dev/null
printf 'notes\n' >"$repo/plugins/beta/zz-notes.yaml"
git_test_config "$repo" add plugins >/dev/null
git_test_config "$repo" commit -qm 'add beta notes' >/dev/null
beta_commit="$(git -C "$repo" rev-parse HEAD)"
printf 'scripts/zz-new-scan.test.sh  plugins/alpha/*\n' >"$repo/scripts/affected-tests-scopes.txt"
out="$(cd "$repo" && bash scripts/affected-tests.sh --replay HEAD~1..HEAD --against HEAD 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] && contains "$out" "commit $beta_commit 0 1 " &&
  has_line "$out" "  - scripts/zz-old-scan.test.sh  (test-scope plugins/beta/*)" && ! contains "$out" "  + "; then
  ok "--replay --against lists a commit's suites as dropped when this selector picks none"
else
  fail "--replay --against with an empty selection wrong (rc=$RC): $out"
fi

for args in "--replay HEAD~1..HEAD plugins/alpha/hooks/alpha-hook.sh" "--against HEAD" "--replay HEAD~1..HEAD --run"; do
  # shellcheck disable=SC2086 # deliberate: each case is a word list
  (cd "$repo" && bash scripts/affected-tests.sh $args >/dev/null 2>&1)
  RC=$?
  if [[ "$RC" -eq 2 ]]; then
    ok "usage: '$args' exits 2"
  else
    fail "usage: '$args' should exit 2, got rc=$RC"
  fi
done
rm -rf "$repo"

# --- --help reaches the actual end of the header -----------------------------
# usage() used to extract a hardcoded sed range that stopped mid-header as the
# comment block grew. Pin a sentence that lives on the last header
# lines so a drifted range cannot come back unnoticed.
help_out="$(bash scripts/affected-tests.sh --help)"
if contains "$help_out" 'Both stages fail loud'; then
  ok "--help reaches the end of the header (derived usage)"
else
  fail "--help truncated before the header's last sentence: $help_out"
fi

test_harness::report
