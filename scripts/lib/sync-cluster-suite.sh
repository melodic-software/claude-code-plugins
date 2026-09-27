# shellcheck shell=bash
# Shared driver for the scripts/sync-<cluster>.test.sh suites. Sourced, never
# executed.
#
# Each of those suites drives one scripts/sync-<cluster>.sh gate through the
# same five cases: sync rewrites the vendored copy, `--check` DISCRIMINATES
# between a matching and a drifted cluster, the drift message names both paths,
# `--print-manifest` publishes src and copy, and `--check-bump` demands a
# carrier version bump. They differ only in the cluster's paths, its canonical
# content, and two arms not every gate has. Written out per suite, the copies
# were free to drift on the part that decides whether the gate is tested at all
# -- the discriminating arm -- while reading as if all four covered the same
# ground.
#
# A suite states its cluster's constants and nothing else:
#
#   sync_cluster_suite::run \
#     --script <absolute path to the gate under test> \
#     --canonical <repo-relative canonical path> \
#     --copy <repo-relative vendored copy path> \
#     --v1 <canonical content, printf %b escapes> \
#     --v2 <canonical content after it changes, printf %b escapes> \
#     --drift <content written over the copy to drift it> \
#     [--check-agree-note <text appended to the both-arms-agree failure>] \
#     [--unknown-flag-arm] \
#     [--unchanged-bump-arm]
#
# Case names and failure wordings are the CI log surface and live here once, so
# a grep that matches one suite matches all four.
#
# The carrying plugin names are read off the two paths: both live under
# plugins/<name>/, which is the same shape the gates' own manifest walk assumes.
#
# WHY THE GIT CLEAR IS REPEATED HERE. scripts/check-fixture-git-isolation.sh
# credits a suite that sources an isolating harness, resolving harnesses ONE
# level deep by basename. This file builds the git fixture on its sourcers'
# behalf, so it must perform the clear itself or leave every sourcer uncredited.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/sync-cluster-suite.sh is sourced-only\n' >&2
  exit 2
fi

_sync_cluster_suite_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-harness.sh
. "$_sync_cluster_suite_lib_dir/test-harness.sh"
# shellcheck source=fixture-tree.sh
. "$_sync_cluster_suite_lib_dir/fixture-tree.sh"
unset _sync_cluster_suite_lib_dir

# fixture_tree::build assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
_scs_fixture=""

# _write <path> <printf %b content>
sync_cluster_suite::_write() {
  printf '%b' "$2" >"$1"
}

# _manifest <plugin> <version>
sync_cluster_suite::_manifest() {
  printf '{"name":"%s","version":"%s"}\n' "$1" "$2" \
    >"$_scs_fixture/plugins/$1/.claude-plugin/plugin.json"
}

# _new_fixture -> fresh tree with the gate and the shared engine it sources
# copied in, plus the four directories the cluster occupies.
sync_cluster_suite::_new_fixture() {
  fixture_tree::build _scs_fixture --sut "$_scs_script" || return 1
  mkdir -p "$_scs_fixture/${_scs_canonical%/*}" \
    "$_scs_fixture/plugins/$_scs_src_plugin/.claude-plugin" \
    "$_scs_fixture/${_scs_copy%/*}" \
    "$_scs_fixture/plugins/$_scs_copy_plugin/.claude-plugin"
}

# _base_fixture -> canonical + a matching copy, both plugins at 0.1.0.
sync_cluster_suite::_base_fixture() {
  sync_cluster_suite::_new_fixture || return 1
  sync_cluster_suite::_write "$_scs_fixture/$_scs_canonical" "$_scs_v1"
  sync_cluster_suite::_write "$_scs_fixture/$_scs_copy" "$_scs_v1"
  sync_cluster_suite::_manifest "$_scs_src_plugin" 0.1.0
  sync_cluster_suite::_manifest "$_scs_copy_plugin" 0.1.0
}

sync_cluster_suite::_drift_copy() {
  sync_cluster_suite::_write "$_scs_fixture/$_scs_copy" "$_scs_drift"
}

sync_cluster_suite::_run_mode() (
  cd "$_scs_fixture" && bash "scripts/$_scs_gate" "$@"
)

# _git_fixture -> the base commit sha on stdout.
sync_cluster_suite::_git_fixture() {
  # On refusal (e.g. TMPDIR inside the checkout) stop before add/commit can
  # resolve to the enclosing real repository.
  git_init_test_repo "$_scs_fixture" || return 1
  git -C "$_scs_fixture" add -A
  git -C "$_scs_fixture" commit -qm base
  git -C "$_scs_fixture" rev-parse HEAD
}

# --- sync copies the canonical into the carrying plugin ---------------------
sync_cluster_suite::_case_sync() {
  local out
  sync_cluster_suite::_base_fixture
  sync_cluster_suite::_drift_copy
  if out="$(sync_cluster_suite::_run_mode 2>&1)" &&
    cmp -s "$_scs_fixture/$_scs_canonical" "$_scs_fixture/$_scs_copy"; then
    ok "sync makes the carrying copy byte-identical to the canonical"
  else
    fail "sync should copy the canonical into $_scs_copy_plugin, got: $out"
  fi
  rm -rf "$_scs_fixture"
}

# --- --check DISCRIMINATES --------------------------------------------------
# discriminating-skip-required: a gate whose arms agree proves nothing.
# What the cluster shares is the whole point of it: the two carriers disagreeing
# about the vendored content is the failure the gate prevents. So drift a copy
# and assert the verdict FLIPS, rather than asserting only that each arm printed
# its own expected string.
sync_cluster_suite::_case_check_discriminates() {
  local clean_verdict drifted_verdict
  sync_cluster_suite::_base_fixture
  if sync_cluster_suite::_run_mode --check >/dev/null 2>&1; then
    clean_verdict=pass
  else
    clean_verdict=fail
  fi
  sync_cluster_suite::_drift_copy
  if sync_cluster_suite::_run_mode --check >/dev/null 2>&1; then
    drifted_verdict=pass
  else
    drifted_verdict=fail
  fi
  if [[ "$clean_verdict" != "$drifted_verdict" ]]; then
    ok "--check discriminates: matching copies '$clean_verdict', drifted copies '$drifted_verdict'"
  else
    fail "--check returned '$clean_verdict' for BOTH matching and drifted copies$_scs_check_agree_note"
  fi
  if [[ "$clean_verdict" == pass && "$drifted_verdict" == fail ]]; then
    ok "--check passes on a matching cluster and fails on a drifted one"
  else
    fail "expected clean=pass drifted=fail, got clean=$clean_verdict drifted=$drifted_verdict"
  fi
  rm -rf "$_scs_fixture"
}

# --- a drift message names the file to fix ----------------------------------
sync_cluster_suite::_case_drift_message() {
  local out
  sync_cluster_suite::_base_fixture
  sync_cluster_suite::_drift_copy
  out="$(sync_cluster_suite::_run_mode --check 2>&1)" || true
  if [[ "$out" == *"$_scs_copy"* && "$out" == *"$_scs_canonical"* ]]; then
    ok "the drift message names both the drifted copy and the canonical"
  else
    fail "drift message should name both paths, got: $out"
  fi
  rm -rf "$_scs_fixture"
}

# --- --print-manifest publishes src and copies ------------------------------
sync_cluster_suite::_case_print_manifest() {
  local out
  sync_cluster_suite::_base_fixture
  out="$(sync_cluster_suite::_run_mode --print-manifest 2>&1)"
  if [[ "$out" == *"src"*"$_scs_canonical"* && "$out" == *"copy"*"$_scs_copy"* ]]; then
    ok "--print-manifest publishes src and copy, so affected-tests can derive the fan-out"
  else
    fail "--print-manifest should publish src and copy, got: $out"
  fi
  rm -rf "$_scs_fixture"
}

# --- an unknown flag is a usage error ---------------------------------------
sync_cluster_suite::_case_unknown_flag() {
  local out rc
  sync_cluster_suite::_base_fixture
  out="$(sync_cluster_suite::_run_mode --bogus-flag 2>&1)"
  rc=$?
  if ((rc == 2)) && [[ "$out" == *"usage: $_scs_gate"* ]]; then
    ok "an unknown flag exits 2 with a usage line naming this gate"
  else
    fail "expected exit 2 and a usage line, got rc=$rc out: $out"
  fi
  rm -rf "$_scs_fixture"
}

# --- --check-bump requires a carrier version bump when canonical changed -----
sync_cluster_suite::_case_check_bump() {
  local base out
  sync_cluster_suite::_base_fixture
  if base="$(sync_cluster_suite::_git_fixture)"; then
    if ((_scs_unchanged_bump_arm == 1)); then
      if out="$(sync_cluster_suite::_run_mode --check-bump "$base" 2>&1)"; then
        ok "--check-bump passes when the canonical is unchanged vs the base ref"
      else
        fail "--check-bump should pass on an unchanged canonical, got: $out"
      fi
    fi
    sync_cluster_suite::_write "$_scs_fixture/$_scs_canonical" "$_scs_v2"
    sync_cluster_suite::_write "$_scs_fixture/$_scs_copy" "$_scs_v2"
    if sync_cluster_suite::_run_mode --check-bump "$base" >/dev/null 2>&1; then
      fail "--check-bump should fail when the canonical changed but no carrier version moved"
    else
      ok "--check-bump fails when the canonical changed but no carrier version moved"
    fi
    sync_cluster_suite::_manifest "$_scs_copy_plugin" 0.2.0
    sync_cluster_suite::_manifest "$_scs_src_plugin" 0.2.0
    if sync_cluster_suite::_run_mode --check-bump "$base" >/dev/null 2>&1; then
      ok "--check-bump passes once the carrying plugins bumped"
    else
      fail "--check-bump should pass after both carriers bumped"
    fi
  else
    fail "could not init a git fixture; --check-bump arms did not run"
  fi
  rm -rf "$_scs_fixture"
}

sync_cluster_suite::run() {
  _scs_script=""
  _scs_canonical=""
  _scs_copy=""
  _scs_v1=""
  _scs_v2=""
  _scs_drift=""
  _scs_check_agree_note=""
  _scs_unknown_flag_arm=0
  _scs_unchanged_bump_arm=0
  while (($# > 0)); do
    case "$1" in
    --script | --canonical | --copy | --v1 | --v2 | --drift | --check-agree-note)
      if (($# < 2)); then
        printf 'sync-cluster-suite: %s needs a value\n' "$1" >&2
        return 2
      fi
      case "$1" in
      --script) _scs_script="$2" ;;
      --canonical) _scs_canonical="$2" ;;
      --copy) _scs_copy="$2" ;;
      --v1) _scs_v1="$2" ;;
      --v2) _scs_v2="$2" ;;
      --drift) _scs_drift="$2" ;;
      *) _scs_check_agree_note="$2" ;;
      esac
      shift 2
      ;;
    --unknown-flag-arm)
      _scs_unknown_flag_arm=1
      shift
      ;;
    --unchanged-bump-arm)
      _scs_unchanged_bump_arm=1
      shift
      ;;
    *)
      printf 'sync-cluster-suite: unknown option %s\n' "$1" >&2
      return 2
      ;;
    esac
  done

  local missing=""
  [[ -n "$_scs_script" ]] || missing="$missing --script"
  [[ -n "$_scs_canonical" ]] || missing="$missing --canonical"
  [[ -n "$_scs_copy" ]] || missing="$missing --copy"
  [[ -n "$_scs_v1" ]] || missing="$missing --v1"
  [[ -n "$_scs_v2" ]] || missing="$missing --v2"
  [[ -n "$_scs_drift" ]] || missing="$missing --drift"
  if [[ -n "$missing" ]]; then
    printf 'sync-cluster-suite: missing required option(s):%s\n' "$missing" >&2
    return 2
  fi

  _scs_gate="${_scs_script##*/}"
  local rest
  rest="${_scs_canonical#plugins/}"
  _scs_src_plugin="${rest%%/*}"
  rest="${_scs_copy#plugins/}"
  _scs_copy_plugin="${rest%%/*}"

  sync_cluster_suite::_case_sync
  sync_cluster_suite::_case_check_discriminates
  sync_cluster_suite::_case_drift_message
  sync_cluster_suite::_case_print_manifest
  if ((_scs_unknown_flag_arm == 1)); then
    sync_cluster_suite::_case_unknown_flag
  fi
  sync_cluster_suite::_case_check_bump
}
