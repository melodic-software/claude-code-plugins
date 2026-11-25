#!/usr/bin/env bash
# Unit tests for affected-tests.sh. Selection only — nothing here runs a real
# suite, because the point of the tool is that the real suites are expensive.
#
# Most scenarios build a throwaway git repo carrying a MINIATURE version of this
# repo's own shape: a shared lib with a sync manifest, two carrying plugins, and
# co-located suites. The cases that must be proved against the LIVE repository
# (the derived shared-lib copy sets, real fan-outs and discovered probes) run the
# selector over the whole tree, so they live in scripts/affected-tests-live.sh,
# which the lint-repo job runs on every pull request.
# test-scope: scripts/affected-tests* .github/workflows/pr-require-checks.yml
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

mk_repo() {
  local dir
  fixture_tree::build "$1" --sut "$SCRIPT" --git --label affected-tests-fixture || return 1
  dir="${!1}"

  mkdir -p "$dir/lib" "$dir/plugins/alpha/hooks" "$dir/plugins/beta/hooks"
  cp "$NO_SUITE" "$dir/scripts/affected-tests-no-suite.txt"

  cp "$REPO_ROOT/scripts/run-plugin-tests.sh" "$dir/scripts/run-plugin-tests.sh"
  : >"$dir/scripts/run-plugin-tests-serial.txt"

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

run_sel "$repo" plugins/beta/hooks/beta-hook.test.sh
out="$OUT"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
  ok "a changed *.test.sh selects itself"
else
  fail "self-selection (rc=$RC): $out"
fi

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

out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh plugins/alpha/hooks/alpha-hook.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && ! contains "$out" 'UNMAPPED'; then
  ok "a changed file reached by an earlier file's walk is not reported unmapped"
else
  fail "shared-walk file falsely unmapped (rc=$RC): $out"
fi

for p in alpha beta; do
  printf 'u() { :; }\n' >"$repo/plugins/$p/hooks/util.sh"
  # shellcheck disable=SC2016 # deliberate: the emitted file must expand these
  printf 'source "$(dirname "${BASH_SOURCE[0]}")/util.sh"\n' >"$repo/plugins/$p/hooks/$p-tool.sh"
  suite_body "$p-tool" >"$repo/plugins/$p/hooks/$p-tool.test.sh"
done
run_sel "$repo" plugins/alpha/hooks/util.sh
alone="$OUT"
run_sel "$repo" plugins/beta/hooks/util.sh
alone+=$'\n'"$OUT"
run_sel "$repo" plugins/alpha/hooks/util.sh plugins/beta/hooks/util.sh
out="$OUT"
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/alpha/hooks/alpha-tool.test.sh &&
  has_line "$out" plugins/beta/hooks/beta-tool.test.sh &&
  [[ "$(sort -u <<<"$out")" == "$(sort -u <<<"$alone")" ]]; then
  ok "two seeds sharing a basename select the union of what each selects alone"
else
  fail "shared-basename seeds (rc=$RC): got [$out], alone [$alone]"
fi
for p in alpha beta; do
  rm -f "$repo/plugins/$p/hooks/util.sh" "$repo/plugins/$p/hooks/$p-tool.sh" "$repo/plugins/$p/hooks/$p-tool.test.sh"
done

out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/alpha/README.md 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && ! contains "$out" 'UNMAPPED'; then
  ok "a recorded no-suite path class exits 0 without an unmapped report"
else
  fail "no-suite class should exit 0 quietly (rc=$RC): $out"
fi

out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/alpha/hooks/removed-helper.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] &&
  contains "$out" 'deleted: plugins/alpha/hooks/removed-helper.sh' &&
  ! contains "$out" 'UNMAPPED'; then
  ok "a deleted unmapped path exits 0 with a visible deleted note"
else
  fail "deleted unmapped path should be a note, not an error (rc=$RC): $out"
fi

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

mk_widget_consumer "$repo/plugins/alpha/hooks/alpha-extra.sh"
suite_body alpha-extra >"$repo/plugins/alpha/hooks/alpha-extra.test.sh"
run_sel "$repo" --base "$base"
out="$OUT"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/alpha/hooks/alpha-extra.test.sh; then
  ok "diff mode includes untracked files"
else
  fail "untracked file missed by diff mode (rc=$RC): $out"
fi

shim="$repo.bin"
mkdir -p "$shim"
printf '#!/usr/bin/env bash\n[[ " $* " == *" -F -f "* ]] && echo grep >>"%s"\nexec %q "$@"\n' \
  "$shim/greps" "$(command -v git)" >"$shim/git"
chmod +x "$shim/git"
explain_with() {
  : >"$shim/greps"
  OUT="$(cd "$repo" && PATH="$shim:$PATH" AFFECTED_TESTS_TREE_GREPS="$1" bash scripts/affected-tests.sh \
    --explain --allow-unmapped scripts/zzorphan-tool.sh lib/widget.sh plugins/alpha/hooks/alpha-extra.sh 2>&1)"
  RC=$?
  GREPS=$(wc -l <"$shim/greps")
}
explain_with 99
tree_out="$OUT" tree_rc="$RC" tree_greps="$GREPS"
explain_with 1
if [[ "$tree_greps" -gt 1 && "$GREPS" -eq 1 && "$RC" -eq "$tree_rc" ]] && [[ -n "$OUT" && "$OUT" == "$tree_out" ]]; then
  ok "the name lines select what the tree grep selects ($tree_greps tree greps against 1)"
else
  fail "name lines diverge from the tree grep (greps $tree_greps/$GREPS, rc $tree_rc/$RC): $OUT // $tree_out"
fi
rm -rf "$shim"

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

abs="$repo/plugins/beta/hooks/beta-hook.sh"
run_sel "$repo" "$abs"
out="$OUT"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
  ok "an absolute path under the repo root resolves to the same selection"
else
  fail "absolute path not normalized (rc=$RC): $out"
fi

out="$(cd "$repo" && bash scripts/affected-tests.sh /elsewhere/lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" 'absolute'; then
  ok "an absolute path outside the repo is refused out loud"
else
  fail "foreign absolute path should exit 2 (rc=$RC): $out"
fi

marker="$(mktemp "$TMP_ROOT/affected-tests-marker.XXXXXX")"
: >"$marker"
(cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh --run lib/widget.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 0 ]] && grep -q 'lib-widget' "$marker" && grep -q 'beta-hook' "$marker"; then
  ok "--run executes every selected suite"
else
  fail "--run did not execute the selection (rc=$RC): $(cat "$marker")"
fi

cat >"$repo/lib/pathprobe.test.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PATH" >"${MARKER_FILE:-/dev/null}"
EOF
printf 'probe\n' >"$repo/lib/pathprobe.sh"
mkdir -p "$repo/.work/venv/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/.work/venv/bin/python"
chmod +x "$repo/.work/venv/bin/python"
(cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh --run lib/pathprobe.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 0 && "$(cat "$marker")" == "$repo/.work/venv/bin:"* ]]; then
  ok "--run puts the CI venv's bin first on PATH for a suite"
else
  fail "--run did not put the venv first (rc=$RC): $(cat "$marker")"
fi
(cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh --run --jobs 2 lib/pathprobe.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 0 && "$(cat "$marker")" == "$repo/.work/venv/bin:"* ]]; then
  ok "--run --jobs 2 puts the CI venv's bin first on PATH too"
else
  fail "--run --jobs 2 did not put the venv first (rc=$RC): $(cat "$marker")"
fi
rm -rf "$repo/.work"
(cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh --run lib/pathprobe.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 0 && "$(cat "$marker")" == "$PATH" ]]; then
  ok "--run leaves PATH unchanged with no CI venv"
else
  fail "--run changed PATH with no venv (rc=$RC): $(cat "$marker")"
fi
rm -f "$repo/lib/pathprobe.sh" "$repo/lib/pathprobe.test.sh"

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

out="$(cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh --run --budget 600 lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && contains "$out" 'within a 600s budget' && contains "$out" 's of the 600s budget.'; then
  ok "--run --budget 600 runs the selection through run-plugin-tests.sh against the budget"
else
  fail "--run --budget 600 did not run the selection against the budget (rc=$RC): $out"
fi
for bad in 0 x -1 '' '='; do
  if [[ "$bad" == = ]]; then
    (cd "$repo" && bash scripts/affected-tests.sh --run --budget= lib/widget.sh >/dev/null 2>&1)
  else
    (cd "$repo" && bash scripts/affected-tests.sh --run --budget "$bad" lib/widget.sh >/dev/null 2>&1)
  fi
  RC=$?
  if [[ "$RC" -eq 2 ]]; then
    ok "--budget '$bad' is a usage error (rc=2)"
  else
    fail "--budget '$bad' should exit 2, got rc=$RC"
  fi
done

shard_paths=(lib/widget.sh plugins/alpha/hooks/alpha-hook.sh plugins/beta/hooks/beta-hook.sh)
select_shard() {
  local spec="$1"
  local -a argv=(bash scripts/affected-tests.sh)
  [[ -n "$spec" ]] && argv+=(--shard "$spec")
  (cd "$repo" && "${argv[@]}" -- "${shard_paths[@]}" 2>/dev/null)
}
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

out="$(cd "$repo" && bash scripts/affected-tests.sh --shard 999/1000 -- "${shard_paths[@]}" 2>&1 >/dev/null)"
RC=$?
if [[ "$RC" -eq 2 ]] && [[ "$out" == *"leg 999 of 1000 draws none of the"* ]]; then
  ok "a leg that draws no suite exits 2 and says why"
else
  fail "empty leg should exit 2 naming the leg (rc=$RC): $out"
fi
if [[ -z "$(select_shard 999/1000 | grep . || true)" ]]; then
  ok "an empty leg prints no selection"
else
  fail "an empty leg printed a selection"
fi

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

suite_body alpha-hook 1 >"$repo/plugins/alpha/hooks/alpha-hook.test.sh"
(cd "$repo" && bash scripts/affected-tests.sh --run plugins/alpha/hooks/alpha-hook.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 1 ]]; then
  ok "--run exits non-zero when a selected suite fails"
else
  fail "--run should propagate a suite failure (rc=$RC)"
fi
rm -rf "$repo" "$marker"

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

if grep -qE 'manifest_src|manifest_copy_patterns|manifest_declares_copies|/\^src=|/\^copies=\(' \
  "$REPO_ROOT/scripts/affected-tests.sh"; then
  fail "affected-tests.sh still scrapes src=/copies=( source text"
else
  ok "affected-tests.sh no longer scrapes src=/copies=( source text"
fi

eco_yaml=(plugins/toolchain/reference/ecosystems/zz-probe.yaml
  docs/contracts/ecosystem-commands/examples/zz-probe.yaml)
mk_repo repo
for y in "${eco_yaml[@]}"; do
  mkdir -p "$repo/${y%/*}"
  printf 'name: probe\n' >"$repo/$y"
done
git_test_config "$repo" add plugins docs >/dev/null
git_test_config "$repo" commit -qm eco-yaml >/dev/null
out="$(cd "$repo" && bash scripts/affected-tests.sh "${eco_yaml[@]}" 2>&1)"
RC=$?
for y in "${eco_yaml[@]}"; do
  if [[ "$RC" -eq 1 ]] && has_line "$out" "  - $y"; then
    ok "reference YAML with no covering lane is UNMAPPED: $y"
  else
    fail "$y should be UNMAPPED, not silently covered (rc=$RC): $out"
  fi
done
rm -rf "$repo"

mk_repo repo
mkdir -p "$repo/eco"

printf 'def helper():\n    return 1\n' >"$repo/eco/widget_mod.py"
printf 'import widget_mod\n' >"$repo/eco/test_widget_mod.py"
printf 'def helper():\n    return 1\n' >"$repo/eco/check-thing.py"
printf 'import importlib\n' >"$repo/eco/test_check_thing.py"

mkdir -p "$repo/eco/pkg/tests"
printf 'def helper():\n    return 1\n' >"$repo/eco/pkg/mod_thing.py"
printf 'import mod_thing\n' >"$repo/eco/pkg/tests/test_mod_thing.py"

printf 'export const a = 1;\n' >"$repo/eco/gadget.js"
printf 'import { a } from "./gadget.js";\n' >"$repo/eco/gadget.test.js"
printf 'export const b = 2;\n' >"$repo/eco/probe.mjs"
printf 'import { b } from "./probe.mjs";\n' >"$repo/eco/probe.test.mjs"

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

printf 'export const w = 3;\n' >"$repo/eco/wrapped.mjs"
printf 'import { w } from "./wrapped.mjs";\n' >"$repo/eco/wrapped-cases.test.mjs"
# shellcheck disable=SC2016 # deliberate: the emitted file must expand these, not this shell
printf 'node "$(dirname "$0")/wrapped-cases.test.mjs"\n' >"$repo/eco/wrapped-cases.test.sh"

run_sel "$repo" eco/wrapped.mjs
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/wrapped-cases.test.mjs && has_line "$OUT" eco/wrapped-cases.test.sh; then
  ok "R9: a Node suite reached through a mention selects its sibling .test.sh wrapper"
else
  fail "R9 wrapper via mention (rc=$RC): $OUT"
fi

run_sel "$repo" eco/probe.mjs
if [[ "$RC" -eq 0 ]] && [[ "$OUT" != *.test.sh* ]]; then
  ok "R9: a Node suite with no sibling .test.sh adds no shell suite"
else
  fail "R9 without a wrapper (rc=$RC): $OUT"
fi

run_sel "$repo" eco/ps/Get-Thing.ps1
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/pstests/Get-Thing.Tests.ps1; then
  ok "powershell: a Pester suite in a mirrored tree is found by reference"
else
  fail "pester reference (rc=$RC): $OUT"
fi

run_sel "$repo" eco/test_widget_mod.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/test_widget_mod.py; then
  ok "a changed non-shell suite selects itself"
else
  fail "non-shell self-selection (rc=$RC): $OUT"
fi

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

mkdir -p "$repo/eco/imp/harness"
printf 'X = 1\n' >"$repo/eco/imp/lib_mod.py"
printf 'from lib_mod import X\n' >"$repo/eco/imp/user_mod.py"
printf 'import user_mod\n' >"$repo/eco/imp/test_user_mod.py"
printf 'def run():\n    return 1\n' >"$repo/eco/imp/harness/stub_h.py"
printf 'from harness.stub_h import run\n' >"$repo/eco/imp/test_dotted.py"
printf 'import os, harness.other\nfrom harness import (stub_h as s)\n' >"$repo/eco/imp/test_named.py"
printf 'import lib_mod_extra\nNAME = "lib_mod"\n' >"$repo/eco/imp/test_lookalike.py"
run_sel "$repo" eco/imp/lib_mod.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/imp/test_user_mod.py && ! has_line "$OUT" eco/imp/test_lookalike.py; then
  ok "R3: a module change reaches the suite of the code importing it, and not a lookalike name"
else
  fail "python import of a module (rc=$RC): $OUT"
fi
printf 'from harness import (\n    other_name,\n    stub_h,\n)\n' >"$repo/eco/imp/test_wrapped.py"
printf 'from harness import other_name, \\\n    stub_h\n' >"$repo/eco/imp/test_backslash.py"
run_sel "$repo" eco/imp/harness/stub_h.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/imp/test_dotted.py && has_line "$OUT" eco/imp/test_named.py &&
  has_line "$OUT" eco/imp/test_wrapped.py && has_line "$OUT" eco/imp/test_backslash.py; then
  ok "R3: a dotted component or an imported name equal to the stem names the module, on a wrapped line too"
else
  fail "python dotted, from-import or wrapped import (rc=$RC): $OUT"
fi
OUT="$(cd "$repo" && AFFECTED_TESTS_WRAP_LINES=2 bash scripts/affected-tests.sh eco/imp/harness/stub_h.py 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$OUT" "ran past 2 lines"; then
  ok "R3: a wrapped import cut short by the joining window fails loud"
else
  fail "python wrapped import past the window (rc=$RC): $OUT"
fi

mkdir -p "$repo/eco/imp/pkgx" "$repo/eco/imp/other"
printf 'VALUE = 1\n' >"$repo/eco/imp/pkgx/__init__.py"
printf 'VALUE = 2\n' >"$repo/eco/imp/pkgx/mod.py"
: >"$repo/eco/imp/other/__init__.py"
printf 'from pkgx.mod import VALUE\n' >"$repo/eco/imp/test_pkg_user.py"
printf 'import json\n' >"$repo/eco/imp/test_no_pkg.py"
run_sel "$repo" eco/imp/pkgx/__init__.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/imp/test_pkg_user.py && ! has_line "$OUT" eco/imp/test_no_pkg.py; then
  ok "R3: a package's __init__.py reaches a suite outside the package that imports it"
else
  fail "python package __init__.py (rc=$RC): $OUT"
fi

mkdir -p "$repo/eco/amb/a/skill/scripts" "$repo/eco/amb/b/tests"
printf 'A = 1\n' >"$repo/eco/amb/a/util.py"
printf 'B = 1\n' >"$repo/eco/amb/b/util.py"
printf 'import util\n' >"$repo/eco/amb/a/test_near.py"
printf 'import util\n' >"$repo/eco/amb/a/skill/scripts/test_lib_user.py"
printf 'import util\n' >"$repo/eco/amb/b/tests/test_child.py"
printf 'import util\n' >"$repo/eco/amb/test_above.py"
run_sel "$repo" eco/amb/a/util.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/amb/a/test_near.py && has_line "$OUT" eco/amb/a/skill/scripts/test_lib_user.py &&
  ! has_line "$OUT" eco/amb/b/tests/test_child.py && ! has_line "$OUT" eco/amb/test_above.py; then
  ok "R3: an ambiguous module resolves from the nearest directory holding one, never from above two"
else
  fail "python ambiguous import, nearest module (rc=$RC): $OUT"
fi
run_sel "$repo" eco/amb/b/util.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/amb/b/tests/test_child.py && ! has_line "$OUT" eco/amb/a/test_near.py; then
  ok "R3: an ambiguous module resolves from its tests/ child"
else
  fail "python ambiguous import, tests/ child (rc=$RC): $OUT"
fi

mkdir -p "$repo/plugins/alpha/fixtures" "$repo/plugins/beta/surface"
printf 'def main():\n    return 1\n' >"$repo/plugins/alpha/fixtures/serve.py"
printf 'from bridge_x import (\n    serve,\n)\n' >"$repo/plugins/beta/surface/test_server.py"
printf 'import serve\n' >"$repo/plugins/beta/test_plain.py"
run_sel "$repo" --allow-unmapped plugins/alpha/fixtures/serve.py
if [[ "$RC" -eq 0 && -z "$OUT" ]]; then
  ok "R3: an imported name selects nothing through a same-named module in another plugin"
else
  fail "python import across plugins (rc=$RC): $OUT"
fi
printf 'from helpers import serve\n' >"$repo/plugins/alpha/test_not_pkg.py"
printf 'from fixtures import serve\n' >"$repo/plugins/alpha/test_pkg.py"
run_sel "$repo" plugins/alpha/fixtures/serve.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/test_pkg.py && ! has_line "$OUT" plugins/alpha/test_not_pkg.py &&
  ! has_line "$OUT" plugins/beta/surface/test_server.py; then
  ok "R3: an imported name names a module only in the package it is imported from"
else
  fail "python imported name outside its package (rc=$RC): $OUT"
fi

mkdir -p "$repo/eco/cf/sub" "$repo/eco/pk/tests"
printf 'import pytest\n' >"$repo/eco/cf/conftest.py"
printf 'assert True\n' >"$repo/eco/cf/test_top.py"
printf 'assert True\n' >"$repo/eco/cf/sub/test_deep.py"
: >"$repo/eco/pk/__init__.py"
printf 'assert True\n' >"$repo/eco/pk/tests/test_pk.py"
run_sel "$repo" eco/cf/conftest.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/cf/test_top.py && has_line "$OUT" eco/cf/sub/test_deep.py &&
  ! has_line "$OUT" eco/test_widget_mod.py; then
  ok "R2: a conftest.py selects every test module at or below its directory, and none outside it"
else
  fail "conftest.py (rc=$RC): $OUT"
fi
run_sel "$repo" eco/pk/__init__.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/pk/tests/test_pk.py && ! has_line "$OUT" eco/cf/test_top.py; then
  ok "R2: a package __init__.py selects the test modules of its package"
else
  fail "__init__.py (rc=$RC): $OUT"
fi

mkdir -p "$repo/eco/hop" "$repo/eco/elsewhere"
printf 'export const c = 3;\n' >"$repo/eco/hop/origin.js"
printf 'echo "origin.js is the entry point"\n' >"$repo/eco/elsewhere/mention.test.sh"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
printf 'node "$ROOT/eco/hop/origin.js"\n' >"$repo/eco/elsewhere/node-runs.test.sh"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
printf 'cp "$SRC/eco/hop/origin.js" "$DEST"\n' >"$repo/eco/elsewhere/path-loads.test.sh"
printf 'run_suite origin.js\n' >"$repo/eco/hop/wrapper.test.sh"
printf 'node origin.js\n' >"$repo/eco/hop/node-wrapper.test.sh"
printf 'echo hop\n' >"$repo/eco/hop/hop-tool.sh"
printf 'TOOL = "hop-tool.sh"\n' >"$repo/eco/hop/test_hop_listing.py"
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
# still need their own lane", and --write-not-run lists them for a caller that
# runs them (scripts/check-affected.sh --tests).
printf 'stale\n' >"$TMP_ROOT/not-run"
OUT="$(cd "$repo" && bash scripts/affected-tests.sh --run --write-not-run "$TMP_ROOT/not-run" eco/gadget.js 2>&1)"
RC=$?
if [[ "$RC" -eq 3 ]] && contains "$OUT" 'NOT RUN'; then
  ok "--run reports a non-shell suite as NOT RUN and exits 3"
else
  fail "--run should exit 3 naming the unrun suite (rc=$RC): $OUT"
fi
NOT_RUN="$(cat "$TMP_ROOT/not-run")"
if has_line "$NOT_RUN" eco/gadget.test.js && ! has_line "$NOT_RUN" stale; then
  ok "--write-not-run replaces the file with the selected suites --run did not run"
else
  fail "--write-not-run should list eco/gadget.test.js and drop the old content: $NOT_RUN"
fi
OUT="$(cd "$repo" && bash scripts/affected-tests.sh --run --write-not-run "$TMP_ROOT/not-run" eco/hop/far-runner.test.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 && ! -s "$TMP_ROOT/not-run" ]]; then
  ok "--write-not-run empties the file when every selected suite ran"
else
  fail "--write-not-run should leave an empty file after a shell-only run (rc=$RC): $(cat "$TMP_ROOT/not-run") $OUT"
fi

rm -rf "$TMP_ROOT/each" && mkdir -p "$TMP_ROOT/each"
printf '%s\n' 000000:eco/gadget.js 000001:eco/hop/far-runner.test.sh 000002:eco/gone.sh >"$TMP_ROOT/each.list"
(cd "$repo" && bash scripts/affected-tests.sh --allow-unmapped --each-from "$TMP_ROOT/each.list" --each-out "$TMP_ROOT/each" 2>/dev/null)
RC=$?
each_same=1
for keyed in 000000:eco/gadget.js 000001:eco/hop/far-runner.test.sh; do
  run_sel "$repo" --allow-unmapped "${keyed#*:}"
  [[ "$OUT" == "$(cat "$TMP_ROOT/each/${keyed%%:*}.out")" && -n "$OUT" ]] || each_same=0
done
if [[ "$RC" -eq 0 && "$each_same" -eq 1 ]]; then
  ok "--each-from: each listed path selects what its own one-file run selects"
else
  fail "--each-from answers differ from one-file runs (rc=$RC): $(cat "$TMP_ROOT"/each/*.out)"
fi
if grep -q '^deleted: eco/gone.sh' "$TMP_ROOT/each/000002.err" && [[ ! -s "$TMP_ROOT/each/000002.out" ]]; then
  ok "--each-from: a path that maps to nothing and no longer exists is reported deleted, selecting nothing"
else
  fail "--each-from: eco/gone.sh should be deleted with no suite: $(cat "$TMP_ROOT/each/000002.err" "$TMP_ROOT/each/000002.out")"
fi
rm -rf "$TMP_ROOT/each-corpus" && mkdir -p "$TMP_ROOT/each-corpus"
printf '%s\n' 000000:scripts/zzorphan-tool.sh 000001:plugins/alpha/README.md >"$TMP_ROOT/each-corpus.list"
(cd "$repo" && bash scripts/affected-tests.sh --unmapped-corpus --each-from "$TMP_ROOT/each-corpus.list" --each-out "$TMP_ROOT/each-corpus" 2>/dev/null)
RC=$?
each_same=1
for keyed in 000000:scripts/zzorphan-tool.sh 000001:plugins/alpha/README.md; do
  one_out="$(cd "$repo" && bash scripts/affected-tests.sh --explain --unmapped-corpus -- "${keyed#*:}" 2>"$TMP_ROOT/each-one.err")"
  one_mark="$(grep -m1 -oE '^(no-suite|deleted|UNMAPPED):' "$TMP_ROOT/each-one.err")"
  each_mark="$(grep -m1 -oE '^(no-suite|deleted|UNMAPPED):' "$TMP_ROOT/each-corpus/${keyed%%:*}.err")"
  [[ "$one_out" == "$(cat "$TMP_ROOT/each-corpus/${keyed%%:*}.out")" && -n "$one_mark" && "$one_mark" == "$each_mark" ]] || each_same=0
done
if [[ "$RC" -eq 0 && "$each_same" -eq 1 && -s "$TMP_ROOT/each-corpus/000000.out" ]] &&
  grep -q '^UNMAPPED:' "$TMP_ROOT/each-corpus/000000.err" && grep -q '^no-suite:' "$TMP_ROOT/each-corpus/000001.err"; then
  ok "--each-from: an unmapped code file selects its corpus under --unmapped-corpus and a no-suite path says no-suite, as their own runs do"
else
  fail "--each-from: unmapped and no-suite answers differ from their own runs (rc=$RC): $(head -n2 "$TMP_ROOT"/each-corpus/*.err)"
fi
run_sel "$repo" --each-from "$TMP_ROOT/each.list"
if [[ "$RC" -eq 2 ]]; then
  ok "--each-from without --each-out is a usage error (exit 2)"
else
  fail "--each-from alone should exit 2, got $RC"
fi
OUT="$(cd "$repo" && bash scripts/affected-tests.sh --write-not-run "$TMP_ROOT/not-run" eco/gadget.js 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$OUT" 'only applies to --run'; then
  ok "--write-not-run without --run is a usage error"
else
  fail "--write-not-run without --run should exit 2 (rc=$RC): $OUT"
fi

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

mk_repo repo2
mkdir -p "$repo2/eco/agg" "$repo2/plugins/alpha/hooks"
write_print_manifest "$repo2/scripts/sync-mixed.sh" "lib/mixed.sh" \
  "plugins/*/hooks/mixed.js"
printf 'mixed_helper() { echo mixed; }\n' >"$repo2/lib/mixed.sh"
printf 'export const mixed = 1;\n' >"$repo2/plugins/alpha/hooks/mixed.js"

printf 'source "lib/mixed.sh"\nnode mixed.js\n' >"$repo2/eco/agg/zed.sh"
printf 'import subprocess\nsubprocess.run(["bash", "zed.sh"])\n' >"$repo2/eco/agg/zed_user.py"
printf 'import zed_user\n' >"$repo2/eco/agg/test_zed_user.py"

run_sel "$repo2" lib/mixed.sh
if has_line "$OUT" eco/agg/test_zed_user.py; then
  ok "a path's crossing budget survives an unrelated cross-family hit"
else
  fail "crossing budget was spent by an incidental hit (rc=$RC): $OUT"
fi

mk_repo repo3
mkdir -p "$repo3/eco/name"
printf 'echo get\n' >"$repo3/plugins/alpha/hooks/get.sh"

printf 'echo target\n' >"$repo3/eco/name/deep-target.sh"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
{
  printf '#!/usr/bin/env bash\n'
  printf 'bash "$REPO_ROOT/eco/name/deep-target.sh"\n'
} >"$repo3/eco/name/driver.test.sh"

printf 'echo prose\n' >"$repo3/eco/name/prose-target.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "Every rejected shape is covered by prose-target.sh."\n'
} >"$repo3/eco/name/prose.test.sh"

printf 'echo ellipsis\n' >"$repo3/eco/name/ellipsis-target.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "the rest of that argument lives in ...ellipsis-target.sh"\n'
} >"$repo3/eco/name/ellipsis.test.sh"

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

mk_repo repo3
mkdir -p "$repo3/eco/cmt"
printf 'echo hub\n' >"$repo3/eco/cmt/hub-target.sh"
suite_body hub-target >"$repo3/eco/cmt/hub-target.test.sh"
mk_cmt_dependent() {
  printf '%b' "$3" >"$repo3/eco/cmt/$1.$2"
  suite_body "$1" >"$repo3/eco/cmt/$1.test.$2"
}
mk_cmt_dependent sh-comment sh '#!/usr/bin/env bash\n# see hub-target.sh\n  # also hub-target.sh\necho hub\n'
mk_cmt_dependent js-comment js '// see hub-target.sh\n/* hub-target.sh */\n/**\n * hub-target.sh\n */\nexport const x = 1;\n'
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
mk_cmt_dependent sh-code sh 'source "$(dirname "$0")/hub-target.sh"\n'
mk_cmt_dependent sh-trailing sh 'echo ok # runs after hub-target.sh\n'
mk_cmt_dependent sh-quoted-hash sh 'echo "# hub-target.sh"\n'
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
mk_cmt_dependent sh-redirect sh 'printf x >"$T/hub-target.sh"\necho y >>$T/hub-target.sh\n'
printf 'X = 2  # see hubmod.py\n' >"$repo3/eco/cmt/pytrail.py"
printf 'import pytrail\n' >"$repo3/eco/cmt/test_pytrail.py"
printf 'import hubmod  # eco/cmt/hubmod.py\n' >"$repo3/eco/cmt/pyimport.py"
printf 'import pyimport\n' >"$repo3/eco/cmt/test_pyimport.py"
# shellcheck disable=SC2016 # deliberate: the emitted fixture must expand these
mk_cmt_dependent sh-directive sh '# shellcheck source=hub-target.sh\n. "$HUB"\n'
mk_cmt_dependent js-code js 'spawnSync("bash", ["hub-target.sh"]);\n'
mk_cmt_dependent js-typeimport js '/** @import { T } from "./hub-target.sh" */\n/** @param {import("./hub-target.sh").T} t */\nexport const y = 2;\n'
printf '#!/usr/bin/env bash\n# covers hub-target.sh\n' >"$repo3/eco/cmt/hub-prose.test.sh"
printf 'X = 1\n' >"$repo3/eco/cmt/hubmod.py"
printf 'import hubmod\n' >"$repo3/eco/cmt/test_hubmod.py"
printf '# see hubmod.py\nimport os\n' >"$repo3/eco/cmt/pyprose.py"
printf 'import pyprose\n' >"$repo3/eco/cmt/test_pyprose.py"
git_test_config "$repo3" add eco >/dev/null
git_test_config "$repo3" commit -qm comments >/dev/null

run_sel "$repo3" eco/cmt/hub-target.sh
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/cmt/hub-target.test.sh &&
  ! has_line "$OUT" eco/cmt/sh-comment.test.sh &&
  ! has_line "$OUT" eco/cmt/sh-trailing.test.sh &&
  ! has_line "$OUT" eco/cmt/sh-redirect.test.sh &&
  ! has_line "$OUT" eco/cmt/js-comment.test.js; then
  ok "a comment-only, trailing-comment or redirect-target mention in a non-suite file no longer selects"
else
  fail "comment-only mention still made a dependent (rc=$RC): $OUT"
fi

if has_line "$OUT" eco/cmt/sh-code.test.sh &&
  has_line "$OUT" eco/cmt/sh-quoted-hash.test.sh &&
  has_line "$OUT" eco/cmt/sh-directive.test.sh &&
  has_line "$OUT" eco/cmt/js-code.test.js &&
  has_line "$OUT" eco/cmt/js-typeimport.test.js; then
  ok "a code mention, a quoted '#', a shellcheck directive and a JSDoc import still select"
else
  fail "a non-comment mention lost its dependent (rc=$RC): $OUT"
fi

if ! has_line "$OUT" eco/cmt/hub-prose.test.sh; then
  ok "a suite that names the file only in a comment is not selected"
else
  fail "a suite's comment-only mention still selected it (rc=$RC): $OUT"
fi

run_sel "$repo3" eco/cmt/hubmod.py
if [[ "$RC" -eq 0 ]] && has_line "$OUT" eco/cmt/test_hubmod.py &&
  ! has_line "$OUT" eco/cmt/test_pyprose.py && ! has_line "$OUT" eco/cmt/test_pytrail.py &&
  has_line "$OUT" eco/cmt/test_pyimport.py; then
  ok "a Python comment naming a module selects nothing, except one on its import line"
else
  fail "python: a comment-only mention still selected (rc=$RC): $OUT"
fi
rm -rf "$repo3"

# --- LIVE repo: pr-require-checks.yml actually fans the selection out -----------------------
# The plan's legs only buy anything if the workflow both sizes its matrix from
# them and has each leg run its own suites. Either half alone is silently
# useless: a plan read by no matrix runs one leg, and a matrix whose legs do
# not pick their own list runs nothing or everything. Pinned together, in the
# job that owns them.
live_ci="$REPO_ROOT/.github/workflows/pr-require-checks.yml"
test_bash_block="$(awk '
  /^  [A-Za-z_][A-Za-z0-9_-]*:[[:blank:]]*(#.*)?$/ {
    job = $0; sub(/:.*$/, "", job); sub(/^  /, "", job)
  }
  job == "test-bash"
' "$live_ci")"
# shellcheck disable=SC2016 # deliberate: these are workflow literals to match, not shell expansions.
if grep -q 'run-plugin-tests\.sh --jobs 3 --suites-from "\$RUNNER_TEMP/leg-suites\.txt"' <<<"$test_bash_block" &&
  grep -q "leg: \${{ fromJSON(needs\.select-tests\.outputs\.bash_legs || '\[0\]') }}" <<<"$test_bash_block" &&
  grep -q 'LEG: \${{ strategy\.job-index }}' <<<"$test_bash_block" &&
  grep -q 'PLAN: \${{ needs\.select-tests\.outputs\.bash_plan }}' <<<"$test_bash_block" &&
  grep -q "jq -r --arg leg \"\$LEG\" '\.\[\$leg\] // \[\] | \.\[\]' <<<\"\$PLAN\"" <<<"$test_bash_block"; then
  ok "pr-require-checks.yml test-bash sizes its matrix from the plan and runs each leg's suites three at a time"
else
  fail "pr-require-checks.yml test-bash no longer fans the planned selection across a matrix at --jobs 3"
fi

# --- pr-require-checks.yml never asks for more than the proven three ------------------------
# #3694: at --jobs 4 three separate suites failed by producing empty output from
# an external command. Three is the ceiling, on either path.
if grep -qE -- '--jobs ([04-9]|[1-9][0-9]+)' "$live_ci"; then
  fail "pr-require-checks.yml passes a --jobs count other than 3: $(grep -oE -- '--jobs [0-9]+' "$live_ci" | sort -u | tr '\n' ' ')"
else
  ok "pr-require-checks.yml asks for no more than the proven three concurrent suites (#3694)"
fi

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

mk_repo repo
mkdir -p "$repo/plugins/alpha/skills/one" "$repo/plugins/alpha/tests"
printf -- '---\nname: one\n---\n' >"$repo/plugins/alpha/skills/one/SKILL.md"
printf 'kind: probe\n' >"$repo/plugins/alpha/skills/one/probe.yaml"
printf '#!/usr/bin/env bash\n# Scans the skill bodies.\n# test-scope: plugins/alpha/skills/*.md\n\n# test-scope: plugins/alpha/*.yaml  # and the probes\necho alpha-scan\n' \
  >"$repo/plugins/alpha/tests/scan.test.sh"
printf '# test-scope: plugins/alpha/skills/*/SKILL.md\n"""Scans the skill bodies."""\nimport unittest\n' \
  >"$repo/plugins/alpha/tests/test_scan.py"
printf '#!/usr/bin/env bash\necho late\n# test-scope: plugins/alpha/skills/*.md\n' >"$repo/plugins/alpha/tests/late.test.sh"
printf 'import test from "node:test";\n' >"$repo/plugins/alpha/tests/scan.test.mjs"
printf '// Scans the skill bodies.\n// test-scope: plugins/alpha/skills/*.md\nimport test from "node:test";\n' \
  >"$repo/plugins/alpha/tests/scoped.test.mjs"
printf '#!/usr/bin/env node\n// test-scope: plugins/alpha/skills/*.md\nimport test from "node:test";\n' \
  >"$repo/plugins/alpha/tests/shebang.test.mjs"
printf 'import test from "node:test";\n// test-scope: plugins/alpha/skills/*.md\n' >"$repo/plugins/alpha/tests/late.test.mjs"
printf '#!/usr/bin/env bash\n# test-scope: plugins/nowhere/*\necho stale\n' >"$repo/plugins/alpha/tests/stale.test.sh"
printf 'echo orphan\n' >"$repo/plugins/alpha/zzorphan-plugin.sh"
git_test_config "$repo" add plugins >/dev/null
git_test_config "$repo" commit -qm r8 >/dev/null

run_sel "$repo" plugins/alpha/skills/one/SKILL.md
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/tests/scan.test.sh &&
  has_line "$OUT" plugins/alpha/tests/test_scan.py &&
  ! has_line "$OUT" plugins/alpha/tests/late.test.sh &&
  ! has_line "$OUT" plugins/alpha/tests/scan.test.mjs &&
  has_line "$OUT" plugins/alpha/tests/scoped.test.mjs &&
  has_line "$OUT" plugins/alpha/tests/shebang.test.mjs &&
  ! has_line "$OUT" plugins/alpha/tests/late.test.mjs &&
  ! has_line "$OUT" plugins/alpha/hooks/alpha-hook.test.sh; then
  ok "R8: a SKILL.md edit selects the suites whose headers declare it and no other suite of the plugin"
else
  fail "R8: declared-scope selection wrong for a SKILL.md edit (rc=$RC): $OUT"
fi

out="$(cd "$repo" && bash scripts/affected-tests.sh --explain plugins/alpha/skills/one/SKILL.md 2>&1)"
if contains "$out" "select: plugins/alpha/tests/scan.test.sh  (test-scope plugins/alpha/skills/*.md)" &&
  ! contains "$out" "and the probes"; then
  ok "R8: --explain reports the declared glob"
else
  fail "R8: --explain lacks the declared glob: $out"
fi

run_sel "$repo" plugins/alpha/skills/one/probe.yaml
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/tests/scan.test.sh; then
  ok "R8: a file declared on a second header line, which no other rule reaches, is mapped"
else
  fail "R8: a declared file was not mapped by its scope (rc=$RC): $OUT"
fi

run_sel "$repo" plugins/alpha/zzorphan-plugin.sh
if [[ "$RC" -eq 1 ]]; then
  ok "R8: a plugin file no suite names or declares is still UNMAPPED"
else
  fail "R8: a plugin file nothing names or declares was mapped (rc=$RC): $OUT"
fi

out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/beta/hooks/beta-hook.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  ok "R8: a glob matching nothing is not checked while its suite is unchanged"
else
  fail "R8: an unchanged suite's stale glob failed the run (rc=$RC): $out"
fi
out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/alpha/tests/stale.test.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && contains "$out" "plugins/alpha/tests/stale.test.sh declares test-scope globs" &&
  contains "$out" '  - plugins/nowhere/*'; then
  ok "R8: a changed suite declaring a glob that matches nothing fails loud"
else
  fail "R8: a stale glob in a changed suite was not refused (rc=$RC): $out"
fi
rm -rf "$TMP_ROOT/each-stale" && mkdir -p "$TMP_ROOT/each-stale"
printf '%s\n' 000000:plugins/alpha/tests/stale.test.sh 000001:plugins/alpha/tests/scan.test.sh >"$TMP_ROOT/each-stale.list"
(cd "$repo" && bash scripts/affected-tests.sh --each-from "$TMP_ROOT/each-stale.list" --each-out "$TMP_ROOT/each-stale" 2>/dev/null)
RC=$?
if [[ "$RC" -eq 0 && ! -e "$TMP_ROOT/each-stale/000000.out" && -e "$TMP_ROOT/each-stale/000001.out" ]]; then
  ok "R8: --each-from leaves a suite with a glob matching nothing unanswered, as its own run exits 2, and answers the rest"
else
  fail "R8: --each-from should skip only the stale-glob suite (rc=$RC): $(ls "$TMP_ROOT/each-stale")"
fi
out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/alpha/tests/scan.test.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  ok "R8: a changed suite whose globs all match passes the check"
else
  fail "R8: a valid declaration was refused (rc=$RC): $out"
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
printf 'name: orphan\n' >"$repo/plugins/alpha/zz-orphan-data.cfg"
run_sel "$repo" --unmapped-corpus plugins/alpha/zz-orphan-data.cfg
if [[ "$RC" -eq 4 && -z "$OUT" ]]; then
  ok "--unmapped-corpus: unmapped data selects no corpus, at exit 4"
else
  fail "--unmapped-corpus: unmapped data should select nothing at exit 4 (rc=$RC): $OUT"
fi
printf '#!/usr/bin/env bash\necho orphan\n' >"$repo/plugins/alpha/zz-orphan-tool"
run_sel "$repo" --unmapped-corpus plugins/alpha/zz-orphan-tool
if [[ "$RC" -eq 4 ]] && has_line "$OUT" plugins/alpha/tests/scan.test.sh &&
  ! has_line "$OUT" plugins/alpha/tests/test_scan.py; then
  ok "--unmapped-corpus: an unmapped extensionless script selects the shell corpus"
else
  fail "--unmapped-corpus: wrong corpus for an extensionless script (rc=$RC): $OUT"
fi
run_sel "$repo" --unmapped-corpus --allow-unmapped plugins/alpha/zz_orphan_mod.py
if [[ "$RC" -eq 2 ]]; then
  ok "--unmapped-corpus with --allow-unmapped is a usage error"
else
  fail "--unmapped-corpus with --allow-unmapped should exit 2 (rc=$RC)"
fi
rm -rf "$repo"

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
  printf 'grep -c . probe-doc.md\n' >"$repo/plugins/gamma/skills/sa/above.test.sh"
  printf 'grep -c . probe-doc.md\n' >"$repo/plugins/alpha/skills/above-both.test.sh"
  printf '# reads plugins/alpha/skills/sa/reference/probe-doc.md\n' >"$repo/$own_a/scripts/sa-comment.test.sh"
  printf 'grep -c . probe-doc.md\n' >"$repo/$own_a/reference/count.sh"
  suite_body count >"$repo/$own_a/reference/count.test.sh"
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

run_sel "$repo" plugins/alpha/.claude-plugin/plugin.json
if [[ "$RC" -eq 0 && -z "$OUT" ]]; then
  ok "manifests: a plugin.json selects no suite through a mention"
else
  fail "manifests: plugin.json selected a suite (rc=$RC): $OUT"
fi

printf '# root\n' >"$repo/README.md"
# shellcheck disable=SC2016 # deliberate: the emitted fixtures must expand these
{
  printf 'grep -q x "$PLUGIN_DIR/README.md"\n' >"$repo/plugins/alpha/tests/readme.test.sh"
  printf 'grep -q x "$REPO_ROOT/README.md"\n' >"$repo/scripts/zz-root-readme.test.sh"
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

run_sel "$repo" lib/widget.sh
if [[ "$RC" -eq 0 ]] && has_line "$OUT" plugins/alpha/hooks/alpha-hook.test.sh &&
  has_line "$OUT" plugins/beta/hooks/beta-hook.test.sh; then
  ok "R5: a hooks-dir shared-lib copy still reaches every copy's suite"
else
  fail "R5: hooks-dir copy fan-out lost a suite (rc=$RC): $OUT"
fi
rm -rf "$repo"

mk_repo repo
scan_suite() {
  {
    printf '#!/usr/bin/env bash\n'
    if [[ -n "${2:-}" ]]; then printf '# test-scope: %s\n' "$2"; fi
    printf 'echo %s\n' "$1"
  } >"$repo/scripts/zz-$1-scan.test.sh"
}
scan_suite old 'plugins/alpha/*'
scan_suite new
git_test_config "$repo" add scripts >/dev/null
git_test_config "$repo" commit -qm scans >/dev/null
printf '# edited\n' >>"$repo/plugins/alpha/hooks/alpha-hook.sh"
git_test_config "$repo" commit -qam 'edit alpha hook' >/dev/null
alpha_commit="$(git -C "$repo" rev-parse HEAD)"
scan_suite old
scan_suite new 'plugins/alpha/*'

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

scan_suite old 'plugins/beta/*'
scan_suite new
git_test_config "$repo" commit -qam 'scan beta' >/dev/null
printf 'notes\n' >"$repo/plugins/beta/zz-notes.yaml"
git_test_config "$repo" add plugins >/dev/null
git_test_config "$repo" commit -qm 'add beta notes' >/dev/null
beta_commit="$(git -C "$repo" rev-parse HEAD)"
scan_suite old
scan_suite new 'plugins/alpha/*'
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

mk_repo repo
mkdir -p "$repo/pkg/nested" "$repo/pkg/node_modules/yaml"
printf '{"dependencies":{"yaml":"2.9.1"},"devDependencies":{"@scope/tool":"1.0.0"}}\n' >"$repo/pkg/package.json"
printf '{"dependencies":{"yaml":"2.9.1"}}\n' >"$repo/pkg/nested/package.json"
printf '{"devDependencies":{"graphql":"17.1.0"}}\n' >"$repo/package.json"
printf 'import { parse } from "yaml";\n' >"$repo/pkg/reader.mjs"
printf 'const t = require("@scope/tool/sub");\n' >"$repo/pkg/tooled.cjs"
printf 'import { x } from "./reader.mjs";\n' >"$repo/pkg/caller.mjs"
printf 'import fs from "node:fs";\n' >"$repo/pkg/plain.mjs"
printf 'import { parse } from "yaml";\n' >"$repo/pkg/nested/inner.mjs"
printf 'import { parse } from "yaml";\n' >"$repo/pkg/node_modules/yaml/index.mjs"
for s in reader tooled caller plain nested/inner node_modules/yaml/index; do
  printf 'import "node:test";\n' >"$repo/pkg/$s.test.mjs"
done
git_test_config "$repo" add -f pkg package.json >/dev/null
git_test_config "$repo" commit -qm pkg >/dev/null

run_sel "$repo" pkg/package.json
if [[ "$RC" -eq 0 ]] && has_line "$OUT" pkg/reader.test.mjs && has_line "$OUT" pkg/tooled.test.mjs &&
  has_line "$OUT" pkg/caller.test.mjs && ! contains "$OUT" pkg/plain.test.mjs &&
  ! contains "$OUT" pkg/nested/ && ! contains "$OUT" node_modules; then
  ok "R10: a package.json selects what its scope's bare importers reach, short of a nested package"
else
  fail "R10: package-scope selection wrong (rc=$RC): $OUT"
fi

printf '{"devDependencies":{"@scope/tool":"1.0.0"}}\n' >"$repo/pkg/package.json"
run_sel "$repo" pkg/package.json
if [[ "$RC" -eq 0 ]] && has_line "$OUT" pkg/reader.test.mjs && has_line "$OUT" pkg/tooled.test.mjs; then
  ok "R10: a dependency the change removes still selects what imports it"
else
  fail "R10: a removed dependency lost its importers (rc=$RC): $OUT"
fi
git -C "$repo" checkout -q -- pkg/package.json

run_sel "$repo" package.json
if [[ "$RC" -eq 0 ]] && ! contains "$OUT" .test.; then
  ok "R10: a package.json no module in its scope bare-imports from selects nothing"
else
  fail "R10: the root package.json should select nothing (rc=$RC): $OUT"
fi
rm -rf "$repo"

help_out="$(bash scripts/affected-tests.sh --help)"
if contains "$help_out" '--each-from' && contains "$help_out" 'Exit: 0'; then
  ok "--help lists the flags and the exit codes"
else
  fail "--help should list the flags and the exit codes: $help_out"
fi

test_harness::report
