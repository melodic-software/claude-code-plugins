#!/usr/bin/env bash
# Black-box contract test for check-test-tmp-cleanup.sh.
#
# Self-contained and cwd-independent: builds a throwaway git repository with
# fixture *.test.sh files, runs the checker against it, and
# asserts on exit code and output. The SUT resolves the repository root
# relative to its own location, so the fixture carries a copy of it under
# scripts/ and every case commits its files so `git ls-files` sees them.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-test-tmp-cleanup.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# The fixture bodies name the command without spelling it in one piece, so this
# suite is not itself a temp-creating suite the checker would flag.
MK="mk"'temp'

# shellcheck disable=SC2016  # the fixture body must reach the file unexpanded
write_clean() { printf 'd=$(%s -d)\ntrap '"'"'rm -rf "$d"'"'"' EXIT\n' "$MK" >"$1"; }
# shellcheck disable=SC2016  # the fixture body must reach the file unexpanded
write_offender() { printf 'd=$(%s -d)\nrm -rf "$d"\n' "$MK" >"$1"; }
write_fixture_user() { printf 'fixture_tree::build f\nln -s /usr/bin/%s f/bin/\n' "$MK" >"$1"; }
write_comment_only() { printf '# uses %s somewhere else\necho hi\n' "$MK" >"$1"; }

# JS fixtures: a folder under os.tmpdir() with and without a removal hook.
write_js_offender() { printf 'const d = mkdtempSync(join(tmpdir(), "x-"));\n' >"$1"; }
write_js_unbound() { printf 'after(() => {});\nconst f = join(mkdtempSync(join(tmpdir(), "x-")), "f");\n' >"$1"; }
write_js_hooked() { printf 'after(() => rmSync(d));\nconst d = mkdtempSync(join(tmpdir(), "x-"));\n' >"$1"; }
write_js_helper() { printf 'import { tempDir } from "../lib/test-tmp.mjs";\nconst d = tempDir("x-");\n' >"$1"; }
write_js_bare_beside_helper() { printf 'import { tempDir } from "../lib/test-tmp.mjs";\nconst d = mkdtempSync(join(tmpdir(), "x-"));\n' >"$1"; }
write_js_under_root() { printf 'after(() => {});\nconst d = join(mkdtempSync(join(root, "x-")), "f");\n' >"$1"; }

# mk_repo <out-var>: a repo with one clean suite, one comment-only suite. The builder assigns through a nameref, which shellcheck
# cannot follow.
mk_repo() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --git || return 1
  dir="${!1}"
  mkdir -p "$dir/plugins/p"
  write_clean "$dir/plugins/p/clean.test.sh"
  write_comment_only "$dir/plugins/p/comment.test.sh"
}

# run_case <label> <expected-rc> <setup> [<must-name>...]
# <setup> runs inside the fixture root before everything is committed; each
# <must-name> must appear in the output of a failing run.
run_case() {
  local label="$1" expected="$2" setup="$3"
  shift 3
  local repo out rc s
  mk_repo repo || {
    fail "$label: fixture build failed"
    return
  }
  (cd "$repo" && eval "$setup") || {
    fail "$label: setup failed"
    return
  }
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm case >/dev/null
  out="$(bash "$repo/scripts/check-test-tmp-cleanup.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
    return
  fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<<"$out"; then
      fail "$label: '$s' not named in output: $out"
      return
    fi
  done
  ok "$label"
}

run_case "clean suites pass" 0 ":"

run_case "an offender fails and is named" 1 \
  "$(declare -f write_offender); MK=$MK; write_offender plugins/p/bad.test.sh" \
  "plugins/p/bad.test.sh"

run_case "a suite cleaned by fixture_tree::build passes" 0 \
  "$(declare -f write_fixture_user); MK=$MK; write_fixture_user plugins/p/ft.test.sh"

run_case "a JS suite with a tmpdir folder and no removal hook fails and is named" 1 \
  "$(declare -f write_js_offender); write_js_offender plugins/p/bad.test.mjs" \
  "plugins/p/bad.test.mjs"

run_case "a JS suite whose folder is never bound to a name fails despite a hook" 1 \
  "$(declare -f write_js_unbound); write_js_unbound plugins/p/unbound.test.mjs" \
  "plugins/p/unbound.test.mjs"

run_case "a JS suite that imports the helper and still makes a bare tmpdir folder fails and is named" 1 \
  "$(declare -f write_js_bare_beside_helper); write_js_bare_beside_helper plugins/p/bare.test.mjs" \
  "plugins/p/bare.test.mjs"

run_case "JS suites with a removal hook, the helper, or a folder under a cleaned root pass" 0 \
  "$(declare -f write_js_hooked write_js_helper write_js_under_root); write_js_hooked plugins/p/h.test.mjs; write_js_helper plugins/p/t.test.js; write_js_under_root plugins/p/r.test.mjs"

# Findings on stderr only.
repo=""
if mk_repo repo; then
  write_offender "$repo/plugins/p/bad.test.sh"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm case >/dev/null
  stdout="$(bash "$repo/scripts/check-test-tmp-cleanup.sh" 2>/dev/null)"
  rc=$?
  if [[ $rc -eq 1 && -z "$stdout" ]]; then
    ok "discover mode exits 1 with nothing on stdout"
  else
    fail "discover mode should exit 1 with an empty stdout (rc=$rc): $stdout"
  fi
else
  fail "discover mode: fixture build failed"
fi

bash "$SUT_SRC" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

test_harness::report
