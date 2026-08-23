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

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/affected-tests.sh"

# A fixture runs a COPY of the gate, so it must also carry the shared
# libraries that copy sources (scripts/lib/*.sh). Staging them here keeps the
# fixture a faithful copy; without it the copied gate dies on a missing
# source at line 1 and every assertion below turns into the same opaque
# failure. See #2914.
stage_libs() {
  mkdir -p "$1/lib"
  cp "$SELF_DIR/lib/changed-files.sh" "$SELF_DIR/lib/read-list.sh" \
    "$SELF_DIR/lib/sync-cluster.sh" "$1/lib/"
}

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
  dir="$(mktemp -d "${TMPDIR:-/tmp}/affected-tests-fixture.XXXXXX")"
  git_init_safe "$dir"

  mkdir -p "$dir/scripts" "$dir/lib" \
    "$dir/plugins/alpha/hooks" "$dir/plugins/beta/hooks"
  cp "$SCRIPT" "$dir/scripts/affected-tests.sh"
  stage_libs "$dir/scripts"
  cp "$NO_SUITE" "$dir/scripts/affected-tests-no-suite.txt"

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
  printf '%s' "$dir"
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

has_line() {
  printf '%s\n' "$1" | grep -qxF "$2"
}

# --- co-located mapping ----------------------------------------------------
repo="$(mk_repo)"
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
sedless="$repo/scripts/sync-widget.sh"
write_print_manifest "$sedless" "lib/widget.sh" \
  "plugins/*/hooks/nothing-matches-this.sh"
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q 'ZERO copy paths'; then
  ok "a sync manifest that yields no copies fails loudly"
else
  fail "empty derivation should exit 2 (rc=$RC): $out"
fi
rm -rf "$repo"

# --- unmapped file: fail loud, and the documented escape hatch -------------
repo="$(mk_repo)"
out="$(cd "$repo" && bash scripts/affected-tests.sh scripts/zzorphan-tool.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'UNMAPPED'; then
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
# The reverse lookup used to read from `< <(git grep ... 2>/dev/null || true)`,
# which discarded git's diagnostic and erased its exit code, making a git ERROR
# (>=2) identical to NO MATCH (1). Both came back as "no dependents": a change
# that normally fans out to many suites selected one or none, at exit 0. That is
# under-selection reported as success — the exact fail-open this tool exists to
# refuse — so the shim below makes `git grep` fail and demands a loud exit.
#
# The shim delegates every other subcommand to the REAL git, captured as an
# absolute path so the shim cannot recurse into itself via PATH.
shimdir="$(mktemp -d "${TMPDIR:-/tmp}/affected-tests-shim.XXXXXX")"
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
if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q "git grep' failed"; then
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
  if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q "needs a"; then
    ok "$flag with no value exits 2 (usage), not 1"
  else
    fail "$flag with no value should exit 2 (rc=$RC): $out"
  fi
done

# --- a sync-*.sh that is not a manifest is skipped, not fatal --------------
# build_sync_map used to exit 2 on ANY scripts/sync-*.sh without a published
# src. This suite runs in a REQUIRED CI lane, so the first future helper that
# merely shares the prefix would have turned that lane red repo-wide. Half a
# manifest (one published key, not the other) must still be fatal.
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
if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q 'no src='; then
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
if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q 'no src='; then
  ok "an empty published src with no copies is a half-manifest, not a helper"
else
  fail "empty src with no copies should exit 2 (rc=$RC): $out"
fi
rm -f "$repo/scripts/sync-helper.sh"

# --- a file an earlier seed already walked past is still MAPPED ------------
# Regression: the shared lib's walk reaches alpha-hook.sh as a dependent. With
# one visited set across seeds, alpha-hook.sh's own walk was short-circuited,
# it contributed nothing, and it was reported unmapped — a false alarm that
# trains people to reach for --allow-unmapped.
out="$(cd "$repo" && bash scripts/affected-tests.sh lib/widget.sh plugins/alpha/hooks/alpha-hook.sh 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && ! printf '%s' "$out" | grep -q 'UNMAPPED'; then
  ok "a changed file reached by an earlier file's walk is not reported unmapped"
else
  fail "shared-walk file falsely unmapped (rc=$RC): $out"
fi

# --- a no-suite class is NOT an unmapped failure ---------------------------
out="$(cd "$repo" && bash scripts/affected-tests.sh plugins/alpha/README.md 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && ! printf '%s' "$out" | grep -q 'UNMAPPED'; then
  ok "a recorded no-suite path class exits 0 without an unmapped report"
else
  fail "no-suite class should exit 0 quietly (rc=$RC): $out"
fi

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

# --- a broken diff is fatal, never an empty selection ----------------------
# The producer used to run inside a process substitution, so its fatal exit
# killed only the subshell: mapfile succeeded with nothing and the run reported
# "nothing to select" and exit 0. A validation caller would read that as clean.
out="$(cd "$repo" && bash scripts/affected-tests.sh --base definitely-not-a-ref 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && ! printf '%s' "$out" | grep -q 'nothing to select'; then
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
if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q 'absolute'; then
  ok "an absolute path outside the repo is refused out loud"
else
  fail "foreign absolute path should exit 2 (rc=$RC): $out"
fi

# --- --run executes the selected suites, sequentially ----------------------
marker="$(mktemp "${TMPDIR:-/tmp}/affected-tests-marker.XXXXXX")"
: >"$marker"
(cd "$repo" && MARKER_FILE="$marker" bash scripts/affected-tests.sh --run lib/widget.sh >/dev/null 2>&1)
RC=$?
if [[ "$RC" -eq 0 ]] && grep -q 'lib-widget' "$marker" && grep -q 'beta-hook' "$marker"; then
  ok "--run executes every selected suite"
else
  fail "--run did not execute the selection (rc=$RC): $(cat "$marker")"
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
  manifest="scripts/sync-$(basename "${src%.*}").sh"
  case "$src" in
  docs/conventions/standards/README.md) manifest="scripts/sync-standards-contract.sh" ;;
  *) ;;
  esac
  expected="$(cd "$REPO_ROOT" && bash "$manifest" --print-manifest | awk -F '\t' '$1=="copy" && $2!=""{print $2}' | while IFS= read -r pat; do
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
# Capture stdout first: `cmd | grep -q` under pipefail is a race — grep -q
# closes the pipe on the first match and a still-writing publisher dies
# SIGPIPE, which this suite's pipefail then treats as a failed assertion.
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
  if ! printf '%s\n' "$live_out" | grep -q $'^src\t'; then
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
repo_renamed="$(mk_repo)"
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
# The no-suite list used to carry bare *.yaml and *.yml entries whose comment
# named actionlint, zizmor, the workflow check-jsonschema step and the
# runner-policy lane. That is true for workflow YAML and false for the reference
# YAML under plugins/toolchain/ and docs/conventions/ecosystem-commands/, which
# NO lane reads: no yamllint step exists, every check-jsonschema step names its
# files and none names these, validate-plugin-contracts.mjs never mentions yaml,
# and plugins/toolchain ships no *.test.sh. The entries were removed so these
# fail loud instead of reporting a covering lane that does not exist.
#
# This case pins that. If someone gives these files a real lane and records the
# class again, this assertion is SUPPOSED to fail — update it together with the
# no-suite entry, and make sure the entry names the lane that actually reads
# them. Workflow YAML must stay covered via the .github/* entry throughout.
# The probe paths are DISCOVERED with a glob, never written out literally. That
# is not tidiness — a literal basename here would make this file a suite that
# "references" the probe, R3 would select it, and the path would come back
# MAPPED at exit 0. The assertion would then fail for a reason that has nothing
# to do with the no-suite list. This is the substring-match limit documented in
# affected-tests.sh's header, met head-on: naming a file in a suite is exactly
# what makes the selector consider it covered.
mapfile -t eco_yaml < <(cd "$REPO_ROOT" && git ls-files \
  'plugins/toolchain/reference/ecosystems/*.yaml' \
  'docs/conventions/ecosystem-commands/examples/*.yaml' | head -2)
if [[ ${#eco_yaml[@]} -eq 0 ]]; then
  fail "no reference YAML found to probe — the case below would be vacuous"
fi
for y in ${eco_yaml[@]+"${eco_yaml[@]}"}; do
  out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh "$y" 2>&1)"
  RC=$?
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'UNMAPPED'; then
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
mapfile -t wf_yaml < <(cd "$REPO_ROOT" && git ls-files '.github/*.yaml' | head -1)
if [[ ${#wf_yaml[@]} -eq 0 ]]; then
  fail "no .github YAML found to probe — the case below would be vacuous"
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
repo="$(mk_repo)"
mkdir -p "$repo/eco"

# Python: the suite PREFIXES the stem, and this repo folds `-` to `_` for the
# suites covering its hyphenated scripts.
printf 'def helper():\n    return 1\n' >"$repo/eco/widget_mod.py"
printf 'import widget_mod\n' >"$repo/eco/test_widget_mod.py"
printf 'def helper():\n    return 1\n' >"$repo/eco/check-thing.py"
printf 'import importlib\n' >"$repo/eco/test_check_thing.py"

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

# --- cross-language matches are followed exactly one hop -------------------
# Widening the corpus to four ecosystems introduced an edge that never existed
# when the reverse lookup was `-- '*.sh'`: a match ACROSS languages. Left
# uncapped, those coincidental matches chained (js -> ps1 -> sh) and saturated
# on the far-end hubs — measured at every .js in the repo selecting the same 156
# of 439 suites. One hop still reaches the suite covering the crossed-to file,
# which is what keeps a .sh wrapper around a .py helper working; what it must
# NOT do is keep walking from there and drag in that file's own dependents.
mkdir -p "$repo/eco/hop"
printf 'export const c = 3;\n' >"$repo/eco/hop/origin.js"
# A .ps1 that merely MENTIONS the js basename — not a real dependency.
printf "# mentions origin.js in a comment only\nfunction Get-Far { 2 }\n" >"$repo/eco/hop/Far.ps1"
# A shell file that depends on the .ps1, with its own suite. Reaching this suite
# would require a SECOND cross-language hop, which the rule forbids.
printf 'echo "runs Far.ps1"\n' >"$repo/eco/hop/far-runner.sh"
suite_body far-runner >"$repo/eco/hop/far-runner.test.sh"
run_sel "$repo" eco/hop/origin.js
if ! has_line "$OUT" eco/hop/far-runner.test.sh; then
  ok "a chain that already crossed languages cannot cross a second time"
else
  fail "cross-language walk took a second transition (rc=$RC): $OUT"
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
if [[ "$RC" -eq 3 ]] && printf '%s' "$OUT" | grep -q 'NOT RUN'; then
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
repo="$(mk_repo)"
mkdir -p "$repo/eco/chain"
printf 'def helper():\n    return 1\n' >"$repo/eco/chain/helper.py"
# The shell wrapper that drives the Python helper: one crossing, py -> sh.
printf 'echo "runs helper.py"\n' >"$repo/eco/chain/runner.sh"
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
repo2="$(mk_repo)"
mkdir -p "$repo2/eco/agg" "$repo2/plugins/alpha/hooks"
write_print_manifest "$repo2/scripts/sync-mixed.sh" "lib/mixed.sh" \
  "plugins/*/hooks/mixed.js"
printf 'mixed_helper() { echo mixed; }\n' >"$repo2/lib/mixed.sh"
printf 'export const mixed = 1;\n' >"$repo2/plugins/alpha/hooks/mixed.js"

# Names the shell source FIRST, the JS copy SECOND — so the cross-family hit is
# the one a last-write-wins bug would keep.
printf 'source "lib/mixed.sh"\n# also mirrors mixed.js\n' >"$repo2/eco/agg/zed.sh"
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

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
((FAIL == 0))
