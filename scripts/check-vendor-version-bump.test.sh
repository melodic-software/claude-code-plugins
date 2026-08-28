#!/usr/bin/env bash
# Unit tests for check-vendor-version-bump.sh. Builds a tiny synthetic repo
# tree per scenario in a temp dir (git-initialized, since the gate diffs
# against a base ref) and invokes the script against it directly — the
# script's own `cd "$(dirname "$0")/.."` makes this work unmodified: copy it
# to <fixture>/scripts/ and it operates on the fixture tree.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-vendor-version-bump.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

# plugin <fixture> <name> <version> — a plugin with one vendored source file.
plugin() {
  local fixture="$1" name="$2" version="$3"
  mkdir -p "$fixture/plugins/$name/.claude-plugin" "$fixture/plugins/$name/vendor/pkg"
  printf '{"name":"%s","version":"%s"}\n' "$name" "$version" \
    >"$fixture/plugins/$name/.claude-plugin/plugin.json"
  printf 'module.exports = 1;\n' >"$fixture/plugins/$name/vendor/pkg/index.js"
}

set_version() {
  local fixture="$1" name="$2" version="$3"
  printf '{"name":"%s","version":"%s"}\n' "$name" "$version" \
    >"$fixture/plugins/$name/.claude-plugin/plugin.json"
}

# base_fixture → two vendored plugins committed as the base ref. Prints the
# fixture dir; the base ref is HEAD.
base_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-vendor-version-bump.sh"
  chmod +x "$dir/scripts/check-vendor-version-bump.sh"
  plugin "$dir" alpha 1.0.0
  plugin "$dir" beta 2.0.0
  git_init_test_repo "$dir" || return 1
  git -C "$dir" add -A
  git_test_config "$dir" commit -qm base
  printf '%s' "$dir"
}

run_gate() (
  local fixture="$1"
  shift
  cd "$fixture" && bash scripts/check-vendor-version-bump.sh "$@"
)

# --- no vendor change passes ------------------------------------------------
f="$(base_fixture)"
echo tweak >"$f/plugins/alpha/README.md"
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  ok "passes when no vendor/ tree changed"
else
  fail "should pass with no vendor change, got: $out"
fi
rm -rf "$f"

# --- vendor edit with a bump passes ----------------------------------------
f="$(base_fixture)"
echo 'module.exports = 2;' >"$f/plugins/alpha/vendor/pkg/index.js"
set_version "$f" alpha 1.0.1
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  ok "passes when the vendoring plugin bumped its version"
else
  fail "should pass on vendor edit + bump, got: $out"
fi
rm -rf "$f"

# --- vendor edit without a bump fails ---------------------------------------
f="$(base_fixture)"
echo 'module.exports = 2;' >"$f/plugins/alpha/vendor/pkg/index.js"
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  fail "vendor edit without a bump should fail, got success: $out"
elif grep -q "STALE VERSION: plugins/alpha/vendor/" <<<"$out"; then
  ok "vendor edit without a bump fails as STALE VERSION"
else
  fail "expected STALE VERSION for alpha, got: $out"
fi
rm -rf "$f"

# --- an ADDED vendor file needs a bump too ----------------------------------
f="$(base_fixture)"
echo 'module.exports = 3;' >"$f/plugins/alpha/vendor/pkg/extra.js"
git -C "$f" add plugins/alpha/vendor/pkg/extra.js
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  fail "added vendor file without a bump should fail, got success: $out"
else
  ok "an added vendor file without a bump fails"
fi
rm -rf "$f"

# --- a DELETED vendor file needs a bump too ---------------------------------
f="$(base_fixture)"
git -C "$f" rm -q plugins/beta/vendor/pkg/index.js
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  fail "deleted vendor file without a bump should fail, got success: $out"
elif grep -q "STALE VERSION: plugins/beta/vendor/" <<<"$out"; then
  ok "a deleted vendor file without a bump fails"
else
  fail "expected STALE VERSION for beta, got: $out"
fi
rm -rf "$f"

# --- a cross-plugin vendor MOVE checks the source plugin too ----------------
# git's default rename detection collapses a byte-identical move to one R100
# record whose --name-only line is the destination only; without --no-renames
# in the gate, alpha's vendor deletion vanishes from the diff and bumping beta
# alone passes.
f="$(base_fixture)"
git -C "$f" mv plugins/alpha/vendor/pkg/index.js plugins/beta/vendor/pkg/moved.js
set_version "$f" beta 2.0.1
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  fail "a vendor file moved alpha -> beta with only beta bumped should fail, got success: $out"
elif grep -q "STALE VERSION: plugins/alpha/vendor/" <<<"$out"; then
  ok "a cross-plugin vendor move without a source-plugin bump fails as STALE VERSION"
else
  fail "expected STALE VERSION for alpha on the move, got: $out"
fi
rm -rf "$f"

# --- the same move with both plugins bumped passes --------------------------
f="$(base_fixture)"
git -C "$f" mv plugins/alpha/vendor/pkg/index.js plugins/beta/vendor/pkg/moved.js
set_version "$f" alpha 1.0.1
set_version "$f" beta 2.0.1
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  ok "a cross-plugin vendor move with both plugins bumped passes"
else
  fail "move with both plugins bumped should pass, got: $out"
fi
rm -rf "$f"

# --- only the unbumped plugin is named --------------------------------------
f="$(base_fixture)"
echo 'module.exports = 2;' >"$f/plugins/alpha/vendor/pkg/index.js"
set_version "$f" alpha 1.0.1
echo 'module.exports = 2;' >"$f/plugins/beta/vendor/pkg/index.js"
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  fail "one unbumped plugin of two should fail, got success: $out"
elif grep -q "plugins/beta/vendor/" <<<"$out" && ! grep -q "plugins/alpha/vendor/" <<<"$out"; then
  ok "names the unbumped plugin and not the bumped one"
else
  fail "expected beta named and alpha not, got: $out"
fi
rm -rf "$f"

# --- a plugin new in this change set is exempt ------------------------------
f="$(base_fixture)"
plugin "$f" gamma 0.1.0
git -C "$f" add plugins/gamma
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  ok "a plugin absent at the base ref is exempt (initial release carries the source)"
else
  fail "new plugin's vendor tree should be exempt, got: $out"
fi
rm -rf "$f"

# --- deleting the manifest is not an off switch -----------------------------
f="$(base_fixture)"
echo 'module.exports = 2;' >"$f/plugins/alpha/vendor/pkg/index.js"
git -C "$f" rm -q plugins/alpha/.claude-plugin/plugin.json
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  fail "vendor edit with the manifest deleted should fail, got success: $out"
else
  ok "a deleted manifest cannot double as the gate's off switch"
fi
rm -rf "$f"

# --- a vendor/ nested below the plugin root is out of scope -----------------
f="$(base_fixture)"
mkdir -p "$f/plugins/alpha/skills/digest/vendor"
echo nested >"$f/plugins/alpha/skills/digest/vendor/lib.js"
git -C "$f" add plugins/alpha/skills/digest
if out="$(run_gate "$f" --check-bump HEAD 2>&1)"; then
  ok "a vendor/ nested below the plugin root is out of scope"
else
  fail "nested vendor dir should not trip the gate, got: $out"
fi
rm -rf "$f"

# --- a failed git diff is a loud exit, not a pass ---------------------------
# Fault-inject a PATH-front git shim that fails only the diff subcommand, so
# the gate's own rev-parse still resolves the base ref. Without the gate
# checking the diff's status, the failure drains to an empty plugin list and
# the gate reports "nothing changed" over a tree carrying a real violation.
f="$(base_fixture)"
echo 'module.exports = 2;' >"$f/plugins/alpha/vendor/pkg/index.js"
mkdir -p "$f/shim"
real_git="$(command -v git)"
# shellcheck disable=SC2016  # the shim's ${1:-} and $@ are the SHIM's own expansions, deliberately unexpanded here
printf '#!/usr/bin/env bash\nif [ "${1:-}" = diff ]; then echo "fatal: simulated git diff failure" >&2; exit 128; fi\nexec %s "$@"\n' "$real_git" >"$f/shim/git"
chmod +x "$f/shim/git"
status=0
out="$(PATH="$f/shim:$PATH" run_gate "$f" --check-bump HEAD 2>&1)" || status=$?
if [[ "$status" -eq 2 && "$out" == *"git diff failed"* ]]; then
  ok "a failed git diff exits 2 instead of passing blind"
else
  fail "a failed git diff should exit 2 naming the diff, got status $status: $out"
fi
rm -rf "$f"

# --- broken or absent jq is a loud exit, not a blanket exemption ------------
# With jq unusable every manifest read comes back empty, which the loop would
# misread as the new-plugin carve-out for every plugin — a full-open gate over
# a tree carrying a real violation.
f="$(base_fixture)"
echo 'module.exports = 2;' >"$f/plugins/alpha/vendor/pkg/index.js"
mkdir -p "$f/shim"
printf '#!/usr/bin/env bash\nexit 127\n' >"$f/shim/jq"
chmod +x "$f/shim/jq"
status=0
out="$(PATH="$f/shim:$PATH" run_gate "$f" --check-bump HEAD 2>&1)" || status=$?
if [[ "$status" -eq 2 && "$out" == *"jq is required"* ]]; then
  ok "unusable jq exits 2 instead of exempting every plugin"
else
  fail "unusable jq should exit 2 naming jq, got status $status: $out"
fi
rm -rf "$f"

# --- usage and unresolvable base ref exit 2 ---------------------------------
f="$(base_fixture)"
expect_exit_2() {
  local label="$1"
  shift
  local status=0
  run_gate "$f" "$@" >/dev/null 2>&1 || status=$?
  if [[ "$status" -eq 2 ]]; then
    ok "$label exits 2"
  else
    fail "$label should exit 2, got $status"
  fi
}
expect_exit_2 "no arguments"
expect_exit_2 "missing base ref" --check-bump
expect_exit_2 "unresolvable base ref" --check-bump no-such-ref
rm -rf "$f"

test_harness::report
