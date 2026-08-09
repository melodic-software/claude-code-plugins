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
NO_SUITE="$SELF_DIR/affected-tests-no-suite.txt"

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
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t.test
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.autocrlf false

  mkdir -p "$dir/scripts" "$dir/lib" \
    "$dir/plugins/alpha/hooks" "$dir/plugins/beta/hooks"
  cp "$SCRIPT" "$dir/scripts/affected-tests.sh"
  cp "$NO_SUITE" "$dir/scripts/affected-tests-no-suite.txt"

  # A sync manifest in the same shape as the real ones: a `src=` line and a
  # GLOB `copies=(...)` array. The selector must read the copy set out of this
  # file rather than knowing the plugin names.
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Fixture sync manifest.\n'
    printf 'set -euo pipefail\n'
    printf 'src="lib/widget.sh"\n'
    printf 'copies=(plugins/*/hooks/widget.sh)\n'
    # shellcheck disable=SC2016 # deliberate: the fixture manifest's own body
    printf 'echo "${src} ${copies[0]}"\n'
  } >"$dir/scripts/sync-widget.sh"

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

  git -C "$dir" add scripts lib plugins >/dev/null
  git -C "$dir" commit -qm base >/dev/null
  printf '%s' "$dir"
}

# run_sel <repo> <args...> -> stdout on fd1, exit status in RC
RC=0
run_sel() {
  local repo="$1"
  shift
  local out
  out="$(cd "$repo" && bash scripts/affected-tests.sh "$@" 2>/dev/null)"
  RC=$?
  printf '%s' "$out"
}

has_line() {
  printf '%s\n' "$1" | grep -qxF "$2"
}

# --- co-located mapping ----------------------------------------------------
repo="$(mk_repo)"
out="$(run_sel "$repo" plugins/alpha/hooks/alpha-hook.sh)"
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/alpha/hooks/alpha-hook.test.sh &&
  ! has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
  ok "co-located: a hook selects its own suite and not a sibling plugin's"
else
  fail "co-located mapping (rc=$RC): $out"
fi

# --- a changed suite selects itself ----------------------------------------
out="$(run_sel "$repo" plugins/beta/hooks/beta-hook.test.sh)"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/beta/hooks/beta-hook.test.sh; then
  ok "a changed *.test.sh selects itself"
else
  fail "self-selection (rc=$RC): $out"
fi

# --- shared-lib fan-out, derived from the sync manifest --------------------
out="$(run_sel "$repo" lib/widget.sh)"
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
git -C "$repo" add plugins/gamma >/dev/null
git -C "$repo" commit -qm gamma >/dev/null
out="$(run_sel "$repo" lib/widget.sh)"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/gamma/hooks/gamma-hook.test.sh; then
  ok "a newly carrying plugin is picked up with no selector or manifest edit"
else
  fail "derived fan-out missed a new carrying plugin (rc=$RC): $out"
fi

# --- an empty derivation is a loud error, not an empty selection -----------
sedless="$repo/scripts/sync-widget.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'src="lib/widget.sh"\n'
  printf 'copies=(plugins/*/hooks/nothing-matches-this.sh)\n'
} >"$sedless"
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
out="$(run_sel "$repo" --base "$base")"
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
out="$(run_sel "$repo" --base "$base")"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/alpha/hooks/alpha-extra.test.sh; then
  ok "diff mode includes untracked files"
else
  fail "untracked file missed by diff mode (rc=$RC): $out"
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

# --- LIVE repo: the derived copy set equals the manifest's glob today ------
# The synthetic cases above prove the mechanism; this one proves it is still
# wired to THIS repository, which is what rots.
for src in lib/hook-utils.sh lib/parse-concern-value.sh docs/conventions/standards/README.md; do
  derived="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh --print-fanout "$src" 2>/dev/null | sort)"
  manifest="scripts/sync-$(basename "${src%.*}").sh"
  case "$src" in
  docs/conventions/standards/README.md) manifest="scripts/sync-standards-contract.sh" ;;
  *) ;;
  esac
  # Re-derive independently: read the manifest's own copies array with a
  # different implementation than the selector's, then compare.
  expected="$(cd "$REPO_ROOT" && awk '
    /^copies=\(/ { inarr = 1; line = $0; sub(/^copies=\(/, "", line) }
    !inarr { next }
    { if (line == "" && $0 !~ /^copies=\(/) line = $0
      sub(/#.*$/, "", line)
      closed = (line ~ /\)/)
      if (closed) sub(/\).*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") print line
      if (closed) exit
      line = "" }
  ' "$manifest" | while IFS= read -r pat; do
    # shellcheck disable=SC2086 # the manifest entry is a glob by design.
    for m in $pat; do [[ -e "$m" ]] && printf '%s\n' "$m"; done
  done | sort)"
  if [[ -n "$derived" && "$derived" == "$expected" ]]; then
    ok "live derivation for $src matches $manifest ($(printf '%s\n' "$derived" | wc -l | tr -d ' ') copies)"
  else
    fail "live derivation drifted for $src: derived=[$derived] expected=[$expected]"
  fi
done

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

# --- LIVE repo: a co-located change stays narrow ---------------------------
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh plugins/eol-normalizer/hooks/eol-normalizer.sh 2>/dev/null)"
RC=$?
count="$(printf '%s\n' "$out" | grep -c '.')"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/eol-normalizer/hooks/eol-normalizer.test.sh && [[ "$count" -lt 10 ]]; then
  ok "live co-located change selects a narrow set ($count suites)"
else
  fail "live co-located selection too wide or wrong (rc=$RC, count=$count): $out"
fi

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
((FAIL == 0))
