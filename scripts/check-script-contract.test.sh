#!/usr/bin/env bash
# test-scope: docs/upstream/*.md
set -uo pipefail
unset CHECK_DATA_ROOT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)" || exit 2

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh" || exit 2

f=""

REGISTRY=(
  "check-adr-numbers.sh|-|-|adr_numbers"
  "check-affected.sh|-|-|-"
  "check-as-of-recheck.sh|-|-|as_of_recheck"
  "check-cost-figures.sh|-|-|cost_figures"
  "check-app-key-references.sh|-|-|-"
  "check-artifact-retention.sh|node|-|-"
  "check-all-skills-verb-contract.sh|-|-|-"
  "check-cant-fail-scan.sh|-|-|-"
  "check-changed-links-online.sh|LYCHEE=/nonexistent/lychee|HEAD|-"
  "check-changed-skills.sh|-|-|-"
  "check-changelog-fragments.sh|-|--check|changelog_fragments"
  "check-changelog-parity.sh|-|--check|changelog_parity"
  "check-comment-hygiene.sh|curl|HEAD|-"
  "check-conformance-registry.sh|-|-|-"
  "check-convention-yaml.sh|CHECK_JSONSCHEMA_BIN=/nonexistent/check-jsonschema|--check|convention_yaml"
  "check-cross-plugin-source-drift.sh|-|-|-"
  "check-detector-eval-coverage.sh|jq|-|-"
  "check-detector-findings-crosswalk.sh|-|-|-"
  "check-discriminating-test-skips.sh|-|-|-"
  "check-docs-naming.sh|git|-|docs_naming"
  "check-docs-only-gate.sh|-|-|-"
  "check-docs-only.sh|-|-|-"
  "check-drive-root-litter.sh|-|-|-"
  "check-engineering-concepts.sh|node|-|-"
  "check-fixture-git-isolation.sh|-|-|-"
  "check-fleet-audit-doc-grammar.sh|-|-|-"
  "check-fleet-finding-test-coverage.sh|-|-|-"
  "check-git-hook-time-budget.sh|-|-|-"
  "check-guardrails-ps-differential.sh|jq|-|-"
  "check-hook-exec-form.sh|jq|-|hook_exec_form"
  "check-exec-form-windows-probe.sh|jq|-|exec_form_windows_probe"
  "check-hook-slow-shapes.sh|jq|-|hook_slow_shapes"
  "check-hook-userconfig-argv.sh|jq|-|hook_userconfig_argv"
  "check-hook-wiring-liveness.sh|jq|-|-"
  "check-hooks-description.sh|jq|-|hooks_description"
  "check-html-assets.sh|HTMLHINT_BIN=/nonexistent/htmlhint|-|html_assets"
  "check-killswitch-hoist.sh|jq|-|killswitch_hoist"
  "check-lane-coverage.sh|-|-|-"
  "check-lifecycle-map.sh|jq|--check|lifecycle_map"
  "check-loop-lane-floor-drift.sh|git|-|-"
  "check-org-repo-tokens.sh|git|-|-"
  "check-orphaned-fixtures.sh|-|-|-"
  "check-pipefail-grep-q.sh|awk|-|pipefail_grep_q"
  "check-plugin-catalog-enablement.sh|jq|-|-"
  "check-plugin-imports.sh|git|-|plugin_imports"
  "check-plugin-manifest-presence.sh|jq|-|-"
  "check-plugin-profiles.sh|node|-|-"
  "check-publisher-token-alignment.sh|-|-|-"
  "check-purged-em-dashes.sh|jq|-|-"
  "check-queue-front-matter.sh|-|-|queue_front_matter"
  "check-read-caller-keys.sh|node|-|-"
  "check-scan-carrier-secret-shadow.sh|gh|o/r|-"
  "check-shell-portability.sh|-|-|-"
  "check-silent-revert.sh|git|--verify-known-incidents|-"
  "check-silent-skips.sh|-|-|-"
  "check-skill-count-claims.sh|-|-|-"
  "check-skill-links.sh|python3|-|-"
  "check-skill-leaf-names.sh|-|-|-"
  "check-skill-portability.sh|-|-|-"
  "check-skill-precompute-compose.sh|-|-|-"
  "check-spoke-plugin-root.sh|-|-|spoke_plugin_root"
  "check-stale-base-overlap.sh|-|-|-"
  "check-standards-contract-bump.sh|-|-|-"
  "check-test-tmp-cleanup.sh|git|-|-"
  "check-upstream-drift.sh|gh|-|upstream_drift"
  "check-vendor-version-bump.sh|-|-|-"
  "check-workflow-template-size.sh|node|-|-"
)

CAP_RC=0
CAP_OUT=""
CAP_ERR=""

run_in() {
  local dir="$1"
  shift
  (cd "$dir" && "$@")
}

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

declare -A HIDDEN_PATHS=()
HIDDEN_PATH=""
HIDDEN_ROOT=""
hidden_path() {
  local tool="$1" entry file mirror n=0
  if [[ -n "${HIDDEN_PATHS[$tool]:-}" ]]; then
    HIDDEN_PATH="${HIDDEN_PATHS[$tool]}"
    return 0
  fi
  [[ -n "$HIDDEN_ROOT" ]] || HIDDEN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hidden-path.XXXXXX")" || return 2
  local -a parts=() kept=()
  IFS=':' read -r -a parts <<<"$PATH"
  for entry in "${parts[@]}"; do
    if [[ ! -e "$entry/$tool" && ! -e "$entry/$tool.exe" ]]; then
      kept+=("$entry")
      continue
    fi
    mirror="$HIDDEN_ROOT/$tool.$((n++))"
    mkdir "$mirror" || return 2
    for file in "$entry"/*; do
      [[ ! -f "$file" || "${file##*/}" == "$tool" || "${file##*/}" == "$tool.exe" ]] && continue
      MSYS=winsymlinks:nativestrict ln -s "$file" "$mirror/" || return 2
    done
    kept+=("$mirror")
  done
  HIDDEN_PATH="$(IFS=':' && printf '%s' "${kept[*]}")"
  HIDDEN_PATHS["$tool"]="$HIDDEN_PATH"
}

cleanup_hidden_paths() {
  [[ -n "$HIDDEN_ROOT" ]] && rm -rf "$HIDDEN_ROOT"
  return 0
}

trap cleanup_hidden_paths EXIT

assert_env_failure() {
  local label="$1"
  if ((CAP_RC == 2)) && [[ -n "$CAP_ERR" && -z "$CAP_OUT" ]]; then
    ok "$label: a missing prerequisite exits 2 and reports on stderr"
  else
    fail "$label: wanted exit 2 with a stderr diagnostic and no stdout (rc=$CAP_RC, stdout='$CAP_OUT', stderr='$CAP_ERR')"
  fi
}

assert_clean() {
  local label="$1"
  if ((CAP_RC == 0)) && [[ -n "$CAP_OUT" ]]; then
    ok "$label: a clean tree exits 0 and says so on stdout"
  else
    fail "$label: wanted exit 0 with a stdout statement (rc=$CAP_RC, stdout='$CAP_OUT', stderr='$CAP_ERR')"
  fi
}

assert_violation() {
  local label="$1" needle="$2"
  if ((CAP_RC == 1)) && [[ "$CAP_ERR" == *"$needle"* && "$CAP_OUT" != *"$needle"* ]]; then
    ok "$label: a seeded violation exits 1 with its finding on stderr"
  else
    fail "$label: wanted exit 1 with '$needle' on stderr only (rc=$CAP_RC, stdout='$CAP_OUT', stderr='$CAP_ERR')"
  fi
}

HOOKS_LABELED='{"description":"Guards Bash calls.","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash x.sh"}]}]}}'

recipe::hooks_description() {
  local body="$HOOKS_LABELED"
  [[ "$1" == violation ]] && body='{"hooks":{"PreToolUse":[]}}'
  fixture_tree::build f --sut "$SELF_DIR/check-hooks-description.sh" --plugins || return 2
  mkdir -p "$f/plugins/alpha/hooks"
  printf '%s\n' "$body" >"$f/plugins/alpha/hooks/hooks.json"
  capture run_in "$f" bash scripts/check-hooks-description.sh
}

recipe::hook_userconfig_argv() {
  local body="$HOOKS_LABELED"
  # shellcheck disable=SC2016  # the token is the literal violation; expansion would erase it
  [[ "$1" == violation ]] && body='{"description":"Guards Bash calls.","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash","args":["${user_config.level}"]}]}]}}'
  fixture_tree::build f --sut "$SELF_DIR/check-hook-userconfig-argv.sh" --plugins || return 2
  mkdir -p "$f/plugins/alpha/hooks"
  printf '%s\n' "$body" >"$f/plugins/alpha/hooks/hooks.json"
  capture run_in "$f" bash scripts/check-hook-userconfig-argv.sh
}

recipe::exec_form_windows_probe() {
  local body='{"description":"Asks.","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["x.mjs"]}]}]}}'
  # shellcheck disable=SC2016
  [[ "$1" == violation ]] && body='{"description":"Asks.","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh","args":["a"]}]}]}}'
  fixture_tree::build f \
    --sut "$SELF_DIR/check-exec-form-windows-probe.sh" \
    --sut "$SELF_DIR/check-hook-exec-form-frontmatter.py" --plugins || return 2
  mkdir -p "$f/plugins/alpha/hooks" "$f/.github"
  cp "$REPO_ROOT/.github/requirements-ci.txt" "$f/.github/requirements-ci.txt"
  printf '%s\n' "$body" >"$f/plugins/alpha/hooks/hooks.json"
  capture run_in "$f" bash scripts/check-exec-form-windows-probe.sh
}

recipe::hook_exec_form() {
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

recipe::hook_slow_shapes() {
  # shellcheck disable=SC2016  # the literal hooks.json command; Claude Code expands it, not this suite
  local cmd='bash "${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh'
  # shellcheck disable=SC2016  # see above
  [[ "$1" == violation ]] && cmd='"${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh'
  fixture_tree::build f \
    --sut "$SELF_DIR/check-hook-slow-shapes.sh" \
    --sut "$SELF_DIR/check-hook-exec-form-frontmatter.py" --plugins || return 2
  mkdir -p "$f/plugins/alpha/hooks" "$f/.github"
  cp "$REPO_ROOT/.github/requirements-ci.txt" "$f/.github/requirements-ci.txt"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$f/plugins/alpha/hooks/x.sh"
  # Git Bash converts path-like arguments to Windows paths: https://www.msys2.org/docs/filesystem-paths/
  printf '%s' "$cmd" | jq -Rs '{hooks:{Stop:[{hooks:[{type:"command",command:.}]}]}}' \
    >"$f/plugins/alpha/hooks/hooks.json"
  capture run_in "$f" bash scripts/check-hook-slow-shapes.sh
}

recipe::killswitch_hoist() {
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

recipe::docs_naming() {
  local name=plugin-philosophy.md
  [[ "$1" == violation ]] && name=PLUGIN-Philosophy.md
  fixture_tree::build f --sut "$SELF_DIR/check-docs-naming.sh" --git --label docs-naming || return 2
  mkdir -p "$f/docs"
  printf 'seed\n' >"$f/docs/$name"
  git_test_config "$f" add -A >/dev/null || return 2
  git_test_config "$f" commit -qm seed >/dev/null || return 2
  capture run_in "$f" bash scripts/check-docs-naming.sh --check
}

recipe::plugin_imports() {
  # shellcheck disable=SC2016  # the source lines are literal fixture text
  local load='source "$SCRIPT_DIR/../lib/x.sh"'
  # shellcheck disable=SC2016
  [[ "$1" == violation ]] && load='source "$SCRIPT_DIR/../../beta/lib/x.sh"'
  fixture_tree::build f --sut "$SELF_DIR/check-plugin-imports.sh" --git --plugins --label plugin-imports || return 2
  mkdir -p "$f/plugins/alpha/scripts" "$f/plugins/beta/lib"
  printf '%s\n' "$load" >"$f/plugins/alpha/scripts/a.sh"
  printf 'x\n' >"$f/plugins/beta/lib/x.sh"
  git_test_config "$f" add -A >/dev/null || return 2
  capture run_in "$f" bash scripts/check-plugin-imports.sh
}

recipe::convention_yaml() {
  fixture_tree::build f --sut "$SELF_DIR/check-convention-yaml.sh" --git --label convention-yaml || return 2
  mkdir -p "$f/docs/conventions" "$f/plugins/alpha/schemas" "$f/lib"
  cp "$REPO_ROOT/lib/yaml-subset.awk" "$f/lib/yaml-subset.awk"
  cp "$REPO_ROOT/lib/resolve-convention-home.sh" "$f/lib/resolve-convention-home.sh"
  printf 'mode: on\n' >"$f/docs/conventions/alpha.yaml"
  [[ "$1" == violation ]] || printf '{}\n' >"$f/plugins/alpha/schemas/alpha.schema.json"
  git_test_config "$f" add -A >/dev/null || return 2
  git_test_config "$f" commit -qm seed >/dev/null || return 2
  capture run_in "$f" env -u GITHUB_ACTIONS -u GITHUB_BASE_REF CHECK_JSONSCHEMA_BIN=true bash scripts/check-convention-yaml.sh --check
}

recipe::adr_numbers() {
  fixture_tree::build f --sut "$SELF_DIR/check-adr-numbers.sh" --label adr-numbers || return 2
  mkdir -p "$f/docs/adr"
  printf 'seed\n' >"$f/docs/adr/0001-first.md"
  [[ "$1" == violation ]] && printf 'seed\n' >"$f/docs/adr/0001-second.md"
  printf '# none\n' >"$f/scripts/adr-numbers-baseline.txt"
  capture run_in "$f" bash scripts/check-adr-numbers.sh --check
}

recipe::spoke_plugin_root() {
  local spoke=plugins/demo/skills/audit/context/step.md
  fixture_tree::build f --sut "$SELF_DIR/check-spoke-plugin-root.sh" --label spoke-plugin-root || return 2
  mkdir -p "$f/${spoke%/*}"
  printf 'run <skill-dir>/scripts/a.sh\n' >"$f/$spoke"
  # shellcheck disable=SC2016  # the token is literal fixture text
  [[ "$1" == violation ]] && printf 'run ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/a.sh\n' >"$f/$spoke"
  printf '# none\n' >"$f/scripts/spoke-plugin-root-baseline.txt"
  capture run_in "$f" bash scripts/check-spoke-plugin-root.sh --check
}

recipe::as_of_recheck() {
  local skill=plugins/demo/skills/audit/SKILL.md
  fixture_tree::build f --sut "$SELF_DIR/check-as-of-recheck.sh" --label as-of-recheck || return 2
  mkdir -p "$f/${skill%/*}"
  printf 'Cap 3, as of 2026-01-01; recheck when the cap moves.\n' >"$f/$skill"
  [[ "$1" == violation ]] && printf 'Cap 3, as of 2026-01-01.\n' >"$f/$skill"
  printf '# none\n' >"$f/scripts/as-of-recheck-baseline.txt"
  capture run_in "$f" bash scripts/check-as-of-recheck.sh --check
}

recipe::cost_figures() {
  local skill=plugins/demo/skills/audit/SKILL.md
  fixture_tree::build f --sut "$SELF_DIR/check-cost-figures.sh" --label cost-figures || return 2
  mkdir -p "$f/${skill%/*}"
  printf 'Rates: the pricing page.\n' >"$f/$skill"
  [[ "$1" == violation ]] && printf 'A run costs 0.4 USD.\n' >"$f/$skill"
  printf '# none\n' >"$f/scripts/cost-figures-baseline.txt"
  printf '# none\n' >"$f/scripts/cost-figures-exempt.txt"
  capture run_in "$f" bash scripts/check-cost-figures.sh --check
}

recipe::queue_front_matter() {
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

recipe::html_assets() {
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

recipe::changelog_parity() {
  fixture_tree::build f --sut "$SELF_DIR/check-changelog-parity.sh" --plugins || return 2
  mkdir -p "$f/plugins/alpha/.claude-plugin"
  printf '%s\n' '{"name":"alpha","version":"0.1.0"}' >"$f/plugins/alpha/.claude-plugin/plugin.json"
  if [[ "$1" != violation ]]; then
    printf '## [0.1.0] - 2026-09-08\n\n- First release.\n' >"$f/plugins/alpha/CHANGELOG.md"
  fi
  capture run_in "$f" bash scripts/check-changelog-parity.sh --check
}

recipe::changelog_fragments() {
  local listed=alpha
  [[ "$1" == violation ]] && listed=""
  fixture_tree::build f --sut "$SELF_DIR/check-changelog-fragments.sh" --plugins || return 2
  mkdir -p "$f/plugins/alpha/.claude-plugin" "$f/.changes/alpha"
  printf '%s\n' '{"name":"alpha","version":"0.1.0"}' >"$f/plugins/alpha/.claude-plugin/plugin.json"
  printf '%s\n' "$listed" >"$f/scripts/fragment-plugins.txt"
  printf -- '---\nbump: none\n---\n\nTests only.\n' >"$f/.changes/alpha/feat-x-0123abcd.md"
  capture run_in "$f" bash scripts/check-changelog-fragments.sh --check
}

recipe::pipefail_grep_q() {
  # shellcheck disable=SC2016  # literal shell source for the fixture; nothing here should expand
  local body='grep -q x <<<"$v"'
  # shellcheck disable=SC2016  # see above
  [[ "$1" == violation ]] && body='echo "$v" | grep -q x'
  fixture_tree::build f --sut "$SELF_DIR/check-pipefail-grep-q.sh" --git || return 2
  printf '%s\n' "$body" >"$f/scripts/sample.sh"
  capture run_in "$f" bash scripts/check-pipefail-grep-q.sh
}

recipe::upstream_drift() {
  local pin=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  local blob=1111111111111111111111111111111111111111
  fixture_tree::build f --sut "$SELF_DIR/check-upstream-drift.sh" --label upstream-drift || return 2
  mkdir -p "$f/docs/upstream" "$f/fx/acme__widgets"
  # shellcheck disable=SC2016  # literal marker backticks
  printf '**Last audited upstream state:** `acme/widgets@%s`\n\n- [a](https://github.com/acme/widgets/blob/%s/a.md)\n' \
    "$pin" "$pin" >"$f/docs/upstream/widgets.md"
  printf '%s a.md\n' "$blob" >"$f/fx/acme__widgets/$pin.tree"
  if [[ "$1" == violation ]]; then
    printf '%s\n' "$head" >"$f/fx/acme__widgets/HEAD"
    printf '2222222222222222222222222222222222222222 a.md\n' >"$f/fx/acme__widgets/$head.tree"
  else
    printf '%s\n' "$pin" >"$f/fx/acme__widgets/HEAD"
  fi
  capture run_in "$f" env UPSTREAM_DRIFT_FIXTURE_DIR="$f/fx" bash scripts/check-upstream-drift.sh
}

recipe::lifecycle_map() {
  fixture_tree::build f --sut "$SELF_DIR/check-lifecycle-map.sh" --label lifecycle-map || return 2
  mkdir -p "$f/.github/workflows" "$f/.claude-plugin" "$f/docs/conventions/lifecycle-map"
  : >"$f/.github/workflows/ci.yml"
  if [[ "$1" == violation ]]; then
    printf '{"plugins":[{"name":"alpha"},{"name":"beta"}]}\n' >"$f/.claude-plugin/marketplace.json"
  else
    printf '{"plugins":[{"name":"alpha"}]}\n' >"$f/.claude-plugin/marketplace.json"
  fi
  cat >"$f/docs/conventions/lifecycle-map/README.md" <<'MD'
# Lifecycle map

## Pull request checks

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| CI (`ci.yml`) | own run | runner | no | push | diff | status |

## Plugins

### On the map

| Plugin | Tasks that use it, and how |
|---|---|
| `alpha` | CI runs it |

### Not an automated task

None.
MD
  capture run_in "$f" bash scripts/check-lifecycle-map.sh --check
}

declare -A VIOLATION_NEEDLE=(
  [lifecycle_map]='MISSING PLUGIN:'
  [hooks_description]='HOOKS DESCRIPTION:'
  [hook_userconfig_argv]='USERCONFIG ARGV:'
  [hook_exec_form]='EXEC-FORM HOOK:'
  [exec_form_windows_probe]='EXEC-FORM WINDOWS:'
  [hook_slow_shapes]='ENV SHEBANG:'
  [killswitch_hoist]='VIOLATION:'
  [queue_front_matter]='VIOLATION:'
  [html_assets]='MISSING:'
  [changelog_parity]='MISSING CHANGELOG:'
  [changelog_fragments]='NOT IN FRAGMENT MODE:'
  [docs_naming]='is not lower-kebab-case'
  [plugin_imports]='plugins/alpha/scripts/a.sh:1: breaks the boundary rule'
  [convention_yaml]='docs/conventions/alpha.yaml: no schema'
  [adr_numbers]='0001: docs/adr/0001-first.md, docs/adr/0001-second.md'
  [spoke_plugin_root]='plugins/demo/skills/audit/context/step.md: contains'
  [as_of_recheck]='plugins/demo/skills/audit/SKILL.md:1: FIX: add a recheck trigger'
  [cost_figures]='plugins/demo/skills/audit/SKILL.md:1: FIX: delete the figure and link the page'
  [pipefail_grep_q]='PIPED EARLY-EXIT GREP:'
  [upstream_drift]='docs/upstream/widgets.md:3: acme/widgets M a.md'
)

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
      fail "$name: could not build a PATH without $prereq (no native symlinks here? Git Bash needs Developer Mode)"
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
