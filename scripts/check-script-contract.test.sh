#!/usr/bin/env bash
# Contract suite for the scripts/check-*.sh family: the part a CALLER must know
# is the same for every member, and this is what holds it.
#
#   bash scripts/check-script-contract.test.sh
#
# The contract itself is stated once, in README.md, "The check-script contract":
# exit 0 clean, 1 findings, 2 environment or usage, findings on stderr. Each
# script's header points at that statement rather than restating it; this suite
# is what makes the statement true rather than aspirational. Nothing here judges
# what a member checks or how well; the members' own co-located suites own that.
#
# THREE DIMENSIONS, and why they are split the way they are:
#
#   ENVIRONMENT  For every member that declares a prerequisite, the prerequisite
#                is taken away and the run must exit 2 with a diagnostic on
#                stderr and NOTHING on stdout. This is the dimension a reader
#                cannot settle by inspection, and the one that costs the most
#                when it drifts: an exit 1 for a missing tool makes "your tree is
#                wrong" and "I could not look" one signal to every lane that
#                reads only the code.
#
#   CLEAN        A clean corpus exits 0 with its statement on stdout.
#
#   VIOLATION    A seeded violation exits 1 with the finding on stderr, and the
#                finding does NOT also appear on stdout.
#
# The clean and violation dimensions run against a FIXTURE, never the live tree:
# a family suite that read the checkout would report another change in flight as
# a contract breach. Fixtures cost a seeding recipe per member, so those two
# dimensions cover the members whose recipe is written below; the environment
# dimension needs no recipe and covers every member that declares a prerequisite.
# A member with neither is registered with `-` in both columns and is held to the
# contract only by its own suite until a recipe is written for it.
#
# THE REGISTRY IS THE STOPPING RULE. Every scripts/check-*.sh must have a row: a
# new member fails as UNREGISTERED rather than being silently uncovered, and a
# row naming a script that no longer exists fails as stale. Registering by
# basename is also what routes a member's changes back here, since
# scripts/affected-tests.sh selects any suite that NAMES the changed file.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)" || exit 2

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh" || exit 2

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
f=""

# --- the registry ------------------------------------------------------------
# <basename> | <prerequisite to remove> | <argv> | <fixture recipe>
#
# Prerequisite forms: a bare tool name is hidden from PATH; NAME=VALUE is an
# environment override that points the member at a tool that is not there. `-`
# means the member declares no prerequisite of its own, so there is nothing to
# take away.
#
# Argv is what it takes to REACH the prerequisite check, nothing more; a member
# that reads its mode first needs that mode here or it would exit 2 for usage
# and the run would prove the wrong thing.
REGISTRY=(
  "check-changed-skills.sh|-|-|-"
  "check-changelog-parity.sh|-|--check|changelog_parity"
  "check-contract-slice-prune.sh|-|-|-"
  "check-cross-plugin-source-drift.sh|-|-|-"
  "check-detector-findings-crosswalk.sh|-|-|-"
  "check-discriminating-test-skips.sh|-|-|-"
  "check-docs-only-gate.sh|-|-|-"
  "check-docs-only.sh|-|-|-"
  "check-drive-root-litter.sh|-|-|-"
  "check-fixture-git-isolation.sh|-|-|-"
  "check-fleet-audit-doc-grammar.sh|-|-|-"
  "check-fleet-finding-test-coverage.sh|-|-|-"
  "check-hook-exec-form.sh|jq|-|hook_exec_form"
  "check-hook-userconfig-argv.sh|jq|-|hook_userconfig_argv"
  "check-hook-wiring-liveness.sh|jq|-|-"
  "check-hooks-description.sh|jq|-|hooks_description"
  "check-html-assets.sh|HTMLHINT_BIN=/nonexistent/htmlhint|-|html_assets"
  "check-killswitch-hoist.sh|jq|-|killswitch_hoist"
  "check-lane-coverage.sh|-|-|-"
  "check-loop-lane-floor-drift.sh|git|-|-"
  "check-orphaned-fixtures.sh|-|-|-"
  "check-plugin-catalog-enablement.sh|jq|-|-"
  "check-plugin-manifest-presence.sh|jq|-|-"
  "check-purged-em-dashes.sh|jq|-|-"
  "check-queue-front-matter.sh|-|-|queue_front_matter"
  "check-shell-portability.sh|-|-|-"
  "check-silent-revert.sh|git|--verify-known-incidents|-"
  "check-silent-skips.sh|-|-|-"
  "check-skill-count-claims.sh|-|-|-"
  "check-skill-leaf-names.sh|-|-|-"
  "check-skill-portability.sh|-|-|-"
  "check-skill-precompute-compose.sh|-|-|-"
  "check-stale-base-overlap.sh|-|-|-"
  "check-vendor-version-bump.sh|-|-|-"
)

# --- running a member --------------------------------------------------------

CAP_RC=0
CAP_OUT=""
CAP_ERR=""

# run_in <dir> <command...> — a subshell rather than `env -C`, whose --chdir is a
# GNU extension this repo cannot assume on every host it runs on.
run_in() {
  local dir="$1"
  shift
  (cd "$dir" && "$@")
}

# capture <command...> — run it with the two streams kept apart, because keeping
# them apart is half of what this suite asserts.
capture() {
  local outf errf
  outf="$(mktemp)" || return 2
  errf="$(mktemp)" || return 2
  "$@" >"$outf" 2>"$errf"
  CAP_RC=$?
  CAP_OUT="$(cat "$outf")"
  CAP_ERR="$(cat "$errf")"
  rm -f "$outf" "$errf"
  return 0
}

# hidden_path <tool> — sets HIDDEN_PATH to a PATH directory mirroring this host's
# PATH with one tool missing. Mirroring is the only portable way to remove ONE
# name: the tools share directories with everything else the member needs, so
# dropping a directory would starve the member of the coreutils it runs on and
# the exit code would stop meaning what the assertion reads it as.
#
# The answer comes back through a global rather than stdout because the cache and
# the cleanup list must survive the call: `$(hidden_path jq)` would run this in a
# subshell, so every caller would rebuild the mirror and every mirror would
# outlive the run in $TMPDIR.
declare -A HIDDEN_PATHS=()
HIDDEN_PATH=""
hidden_path() {
  local tool="$1" dir entry
  if [[ -n "${HIDDEN_PATHS[$tool]:-}" ]]; then
    HIDDEN_PATH="${HIDDEN_PATHS[$tool]}"
    return 0
  fi
  dir="$(mktemp -d)" || return 2
  local -a parts=()
  IFS=':' read -r -a parts <<<"$PATH"
  local i
  # Later PATH entries are linked first so that earlier ones overwrite them:
  # `ln -sf` keeps the last link written, and PATH precedence is first-wins.
  for ((i = ${#parts[@]} - 1; i >= 0; i--)); do
    entry="${parts[i]}"
    [[ -d "$entry" ]] || continue
    ln -sf "$entry"/* "$dir"/ 2>/dev/null || true
  done
  rm -f "$dir/$tool"
  HIDDEN_PATHS["$tool"]="$dir"
  HIDDEN_PATH="$dir"
  if [[ -e "$dir/$tool" ]]; then
    return 2
  fi
}

cleanup_hidden_paths() {
  local key
  if ((${#HIDDEN_PATHS[@]} == 0)); then
    return 0
  fi
  for key in "${!HIDDEN_PATHS[@]}"; do
    [[ -n "${HIDDEN_PATHS[$key]}" ]] && rm -rf "${HIDDEN_PATHS[$key]}"
  done
  HIDDEN_PATHS=()
}

# Installed BEFORE the first fixture_tree::build so the builder chains this trap
# rather than replacing it: it records whatever trap it finds and runs it first.
trap cleanup_hidden_paths EXIT

# --- shared assertions -------------------------------------------------------

assert_env_failure() { # <label>
  local label="$1"
  if ((CAP_RC == 2)) && [[ -n "$CAP_ERR" && -z "$CAP_OUT" ]]; then
    ok "$label: a missing prerequisite exits 2 and reports on stderr"
  else
    fail "$label: wanted exit 2 with a stderr diagnostic and no stdout (rc=$CAP_RC, stdout='$CAP_OUT', stderr='$CAP_ERR')"
  fi
}

assert_clean() { # <label>
  local label="$1"
  if ((CAP_RC == 0)) && [[ -n "$CAP_OUT" ]]; then
    ok "$label: a clean tree exits 0 and says so on stdout"
  else
    fail "$label: wanted exit 0 with a stdout statement (rc=$CAP_RC, stdout='$CAP_OUT', stderr='$CAP_ERR')"
  fi
}

assert_violation() { # <label> <needle>
  local label="$1" needle="$2"
  if ((CAP_RC == 1)) && [[ "$CAP_ERR" == *"$needle"* && "$CAP_OUT" != *"$needle"* ]]; then
    ok "$label: a seeded violation exits 1 with its finding on stderr"
  else
    fail "$label: wanted exit 1 with '$needle' on stderr only (rc=$CAP_RC, stdout='$CAP_OUT', stderr='$CAP_ERR')"
  fi
}

# --- fixture recipes ---------------------------------------------------------
# One function per covered member: build the fixture for <clean|violation>, run
# the member against it, and leave the result in CAP_*. Each is the SMALLEST
# tree the member accepts, since the point here is the interface and not the
# rule.

HOOKS_LABELED='{"description":"Guards Bash calls.","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash x.sh"}]}]}}'

recipe::hooks_description() { # <clean|violation>
  local body="$HOOKS_LABELED"
  [[ "$1" == violation ]] && body='{"hooks":{"PreToolUse":[]}}'
  fixture_tree::build f --sut "$SELF_DIR/check-hooks-description.sh" --plugins || return 2
  mkdir -p "$f/plugins/alpha/hooks"
  printf '%s\n' "$body" >"$f/plugins/alpha/hooks/hooks.json"
  capture run_in "$f" bash scripts/check-hooks-description.sh
}

recipe::hook_userconfig_argv() { # <clean|violation>
  local body="$HOOKS_LABELED"
  # shellcheck disable=SC2016  # the token is the literal violation; expansion would erase it
  [[ "$1" == violation ]] && body='{"description":"Guards Bash calls.","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash","args":["${user_config.level}"]}]}]}}'
  fixture_tree::build f --sut "$SELF_DIR/check-hook-userconfig-argv.sh" --plugins || return 2
  mkdir -p "$f/plugins/alpha/hooks"
  printf '%s\n' "$body" >"$f/plugins/alpha/hooks/hooks.json"
  capture run_in "$f" bash scripts/check-hook-userconfig-argv.sh
}

recipe::hook_exec_form() { # <clean|violation>
  local body="$HOOKS_LABELED"
  [[ "$1" == violation ]] && body='{"description":"Guards Bash calls.","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash","args":["x.sh"]}]}]}}'
  fixture_tree::build f \
    --sut "$SELF_DIR/check-hook-exec-form.sh" \
    --sut "$SELF_DIR/check-hook-exec-form-frontmatter.py" --plugins || return 2
  mkdir -p "$f/plugins/alpha/hooks" "$f/.github"
  cp "$REPO_ROOT/.github/requirements-ci.txt" "$f/.github/requirements-ci.txt"
  printf '%s\n' "$body" >"$f/plugins/alpha/hooks/hooks.json"
  capture run_in "$f" bash scripts/check-hook-exec-form.sh
}

recipe::killswitch_hoist() { # <clean|violation>
  # The gate pins its inlined predicate against the real hook::is_enabled, so the
  # fixture carries the real library: a stub would let the pin pass on text this
  # repo does not ship.
  local guard
  fixture_tree::build f --sut "$SELF_DIR/check-killswitch-hoist.sh" --plugins || return 2
  mkdir -p "$f/lib" "$f/plugins/alpha/hooks"
  cp "$REPO_ROOT/lib/hook-utils.sh" "$f/lib/hook-utils.sh"
  # shellcheck disable=SC2016  # the guard body is literal shell text; nothing here should expand
  guard='#!/usr/bin/env bash
[[ "${CLAUDE_PLUGIN_OPTION_DEMO_GUARD_ENABLED:-true}" == "true" ]] || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
exit 0'
  if [[ "$1" == violation ]]; then
    # shellcheck disable=SC2016  # see above
    guard='#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
[[ "${CLAUDE_PLUGIN_OPTION_DEMO_GUARD_ENABLED:-true}" == "true" ]] || exit 0
exit 0'
  fi
  printf '%s\n' "$guard" >"$f/plugins/alpha/hooks/demo-guard.sh"
  jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"bash ${CLAUDE_PLUGIN_ROOT}/hooks/demo-guard.sh"}]}]}}' \
    >"$f/plugins/alpha/hooks/hooks.json"
  capture run_in "$f" bash scripts/check-killswitch-hoist.sh
}

recipe::queue_front_matter() { # <clean|violation>
  local status=unclaimed
  [[ "$1" == violation ]] && status=open
  fixture_tree::build f --sut "$SELF_DIR/check-queue-front-matter.sh" --label queue || return 2
  mkdir -p "$f/queue"
  cat >"$f/queue/20260908-item.md" <<EOF
---
id: 20260908-item
title: Item
status: $status
created: 2026-09-08T12:00:00Z
producer: contract-suite
---
EOF
  capture run_in "$f" bash scripts/check-queue-front-matter.sh queue
}

recipe::html_assets() { # <clean|violation>
  local asset=plugins/demo/reference/html-chrome.html
  fixture_tree::build f --sut "$SELF_DIR/check-html-assets.sh" --git --plugins || return 2
  mkdir -p "$f/plugins/demo/reference"
  cat >"$f/$asset" <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>t</title></head>
<body><p>ok</p></body></html>
HTML
  git -C "$f" add -A >/dev/null 2>&1
  if [[ "$1" == violation ]]; then
    printf '%s\n' "plugins/demo/reference/ghost.html" >"$f/manifest.txt"
  else
    printf '%s\n' "$asset" >"$f/manifest.txt"
  fi
  capture env CHECK_HTML_ASSETS_ROOT="$f" HTML_ASSETS_MANIFEST="$f/manifest.txt" \
    HTMLHINT_BIN="$REPO_ROOT/node_modules/.bin/htmlhint" \
    bash "$f/scripts/check-html-assets.sh"
}

recipe::changelog_parity() { # <clean|violation>
  fixture_tree::build f --sut "$SELF_DIR/check-changelog-parity.sh" --plugins || return 2
  mkdir -p "$f/plugins/alpha/.claude-plugin"
  printf '%s\n' '{"name":"alpha","version":"0.1.0"}' >"$f/plugins/alpha/.claude-plugin/plugin.json"
  if [[ "$1" != violation ]]; then
    printf '## [0.1.0] - 2026-09-08\n\n- First release.\n' >"$f/plugins/alpha/CHANGELOG.md"
  fi
  capture run_in "$f" bash scripts/check-changelog-parity.sh --check
}

# The finding each recipe's violation arm must produce, keyed by recipe slug.
declare -A VIOLATION_NEEDLE=(
  [hooks_description]='HOOKS DESCRIPTION:'
  [hook_userconfig_argv]='USERCONFIG ARGV:'
  [hook_exec_form]='EXEC-FORM HOOK:'
  [killswitch_hoist]='VIOLATION:'
  [queue_front_matter]='VIOLATION:'
  [html_assets]='MISSING:'
  [changelog_parity]='MISSING CHANGELOG:'
)

# --- 1. every member is registered, and every row names a member -------------

registered=""
for row in "${REGISTRY[@]}"; do
  registered+="${row%%|*}"$'\n'
done

present=""
while IFS= read -r path; do
  present+="$(basename "$path")"$'\n'
done < <(find "$SELF_DIR" -maxdepth 1 -name 'check-*.sh' ! -name '*.test.sh' | sort)

unregistered="$(comm -23 <(printf '%s' "$present" | sort) <(printf '%s' "$registered" | sort))"
stale="$(comm -13 <(printf '%s' "$present" | sort) <(printf '%s' "$registered" | sort))"

if [[ -z "$unregistered" ]]; then
  ok "every scripts/check-*.sh carries a contract row"
else
  fail "UNREGISTERED: these check scripts have no row in this suite, so nothing holds them to the contract: $(printf '%s' "$unregistered" | tr '\n' ' ')"
fi
if [[ -z "$stale" ]]; then
  ok "every contract row names a scripts/check-*.sh that exists"
else
  fail "STALE ROW: these rows name no script: $(printf '%s' "$stale" | tr '\n' ' ')"
fi

# --- 2. the environment dimension, over every member that declares one -------

env_covered=0
for row in "${REGISTRY[@]}"; do
  IFS='|' read -r name prereq argv _recipe <<<"$row"
  [[ "$prereq" == "-" ]] && continue
  [[ -f "$SELF_DIR/$name" ]] || continue
  env_covered=$((env_covered + 1))
  args=()
  [[ "$argv" != "-" ]] && read -r -a args <<<"$argv"
  if [[ "$prereq" == *=* ]]; then
    capture run_in "$REPO_ROOT" env "$prereq" bash "$SELF_DIR/$name" ${args[@]+"${args[@]}"}
  else
    if ! hidden_path "$prereq"; then
      fail "$name: could not build a PATH without $prereq"
      continue
    fi
    capture run_in "$REPO_ROOT" env PATH="$HIDDEN_PATH" bash "$SELF_DIR/$name" ${args[@]+"${args[@]}"}
  fi
  assert_env_failure "$name (no $prereq)"
done

if ((env_covered >= 11)); then
  ok "the environment dimension covered $env_covered members"
else
  fail "the environment dimension covered only $env_covered members; a prerequisite row was dropped rather than a script"
fi

# --- 3. the clean and violation dimensions, over every member with a recipe --

recipe_covered=0
for row in "${REGISTRY[@]}"; do
  IFS='|' read -r name _prereq _argv recipe <<<"$row"
  [[ "$recipe" == "-" ]] && continue
  recipe_covered=$((recipe_covered + 1))

  if ! "recipe::$recipe" clean; then
    fail "$name: the clean fixture could not be built"
    continue
  fi
  assert_clean "$name"
  rm -rf "$f"

  if ! "recipe::$recipe" violation; then
    fail "$name: the violation fixture could not be built"
    continue
  fi
  assert_violation "$name" "${VIOLATION_NEEDLE[$recipe]}"
  rm -rf "$f"
done

if ((recipe_covered >= 7)); then
  ok "the clean and violation dimensions covered $recipe_covered members"
else
  fail "the clean and violation dimensions covered only $recipe_covered members; a recipe was dropped rather than a script"
fi

test_harness::report
