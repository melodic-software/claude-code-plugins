#!/usr/bin/env bash
# pr-bump-plugin-version.yml runs on pull_request, so its own checkout is the
# pull request's code. A job holding `contents: write` runs only what this
# allowlist names: remote actions pinned to a commit SHA, `bash` on a script in
# main's checkout at .base, and the inline steps whose sha256 is recorded below.
# It sets no working-directory, shell or unlisted env var, and the workflow sets
# no defaults or env. Mutants of the workflow prove each rule can fail.
# test-scope: .github/workflows/pr-bump-plugin-version.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

WORKFLOW="$ROOT/.github/workflows/pr-bump-plugin-version.yml"

# A new or edited inline step: confirm it runs nothing from the pull request's
# checkout, then record its body's sha256 (the audit prints it).
ALLOWED_RUN_LINES=("test ! -e .base")
ALLOWED_RUN_BLOCKS=(
  4d224f92decf5efabf8b5a538f5501cc7bebc6ea9ed3e5286b0e813a943801ca # Commit release metadata
)
ALLOWED_ENV=(BASE_REF PR_NUMBER PR_TITLE GH_TOKEN HEAD_REF)

contains() {
  local needle=$1 item
  shift
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

# One record per line: job id, kind, value. A run block's value is its body,
# lines joined by \x1f.
records() {
  awk '
    function ind(s) { match(s, /^ */); return RLENGTH }
    function emit(kind, value) { print job "\t" kind "\t" value }
    /^jobs:/ { in_jobs = 1; next }
    /^[^ #]/ { if ($0 ~ /^(defaults|env):/) { job = "(workflow)"; emit("top", $1) } in_jobs = 0 }
    !in_jobs { next }
    in_run {
      if ($0 ~ /^[[:space:]]*$/ || ind($0) > run_ind) { body = body $0 "\037"; next }
      sub(/(\037)+$/, "", body); emit("runblock", body); in_run = 0
    }
    in_env {
      if (ind($0) > env_ind) {
        if (key_ind == 0) key_ind = ind($0)
        if (ind($0) == key_ind) { k = $0; sub(/^ */, "", k); sub(/:.*/, "", k); emit("env", k) }
        next
      }
      in_env = 0; key_ind = 0
    }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); next }
    {
      t = $0; sub(/^ */, "", t); k_ind = ind($0)
      if (t ~ /^- /) { sub(/^- /, "", t); k_ind += 2 }
      if (t ~ /^contents:[[:space:]]*write/) emit("writes", "")
      else if (t ~ /^run:[[:space:]]*[|>][-+]?[[:space:]]*$/) { in_run = 1; run_ind = k_ind; body = "" }
      else if (t ~ /^(run|uses|working-directory|shell):/) {
        kind = t; sub(/:.*/, "", kind); v = t; sub(/^[a-z-]+:[[:space:]]*/, "", v); emit(kind, v)
      } else if (t ~ /^env:[[:space:]]*$/) { in_env = 1; env_ind = k_ind }
    }
    END { if (in_run) { sub(/(\037)+$/, "", body); emit("runblock", body) } }
  ' "$1"
}

# Print one finding per line for every write job's step outside the allowlist.
audit() {
  local recs writers id kind value sum
  recs="$(records "$1")"
  writers="$(awk -F'\t' '$2 == "writes" { print $1 }' <<<"$recs" | sort -u)"
  if [[ -z "$writers" ]]; then
    echo "no job holds contents: write; the bump cannot land"
    return
  fi
  while IFS=$'\t' read -r id kind value; do
    if [[ "$id" == "(workflow)" ]]; then
      echo "the workflow sets top-level $value, which reaches every job"
      continue
    fi
    grep -qxF "$id" <<<"$writers" || continue
    case "$kind" in
    uses)
      [[ "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}([[:space:]]+#.*)?$ ]] ||
        echo "$id: uses '$value' is not a remote action pinned to a commit SHA"
      ;;
    run)
      if contains "$value" "${ALLOWED_RUN_LINES[@]}"; then
        :
      elif [[ "$value" =~ ^bash\ \.base/scripts/[A-Za-z0-9_-]+\.sh(\ |$) && "$value" != *..* && ! "$value" =~ [\;\&\|\`\<\>] && "$value" != *"\$("* ]]; then
        :
      else
        echo "$id: run '$value' is neither bash on a .base script nor a listed line"
      fi
      ;;
    runblock)
      sum="$(printf '%s' "${value//$'\037'/$'\n'}" | sha256sum)"
      sum="${sum%% *}"
      contains "$sum" "${ALLOWED_RUN_BLOCKS[@]}" ||
        echo "$id: an inline run block is not on the allowlist (sha256 $sum)"
      ;;
    working-directory | shell)
      echo "$id: sets $kind '$value'"
      ;;
    env)
      contains "$value" "${ALLOWED_ENV[@]}" || echo "$id: sets env $value, which is not listed"
      ;;
    *) ;;
    esac
  done <<<"$recs"
}

findings="$(audit "$WORKFLOW")"
if [[ -z "$findings" ]]; then
  ok "every step of the write job is on the allowlist"
else
  fail "the write job runs steps off the allowlist:"$'\n'"$findings"
fi
if grep -Eq '^ +run: bash \.base/scripts/dependabot-plugin-bump\.sh ' "$WORKFLOW"; then
  ok "the job runs main's bump script"
else
  fail "the job does not run .base/scripts/dependabot-plugin-bump.sh"
fi
base_ref="$(awk '/path: \.base$/ { print prev } { prev = $0 }' "$WORKFLOW")"
if [[ "$base_ref" =~ ref:\ refs/heads/main$ ]]; then
  ok ".base is main, not a ref the pull request picks"
else
  fail "the .base checkout does not pin ref: refs/heads/main (line before path: '$base_ref')"
fi

# Each mutant adds one step to the write job; the audit must flag every one
# with a finding the unmutated workflow does not have.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mutants=(
  "      - uses: './.github/actions/download-full-history'"
  "      - run: ./scripts/x.sh"
  "      - run: npm ci"
  "      - run: bash \"\$GITHUB_WORKSPACE/scripts/x.sh\""
  "      - working-directory: plugins/x"$'\n'"        run: bash build.sh"
  "      - run: bash .base/scripts/x.sh; npm ci"
  "      - env:"$'\n'"          BASH_ENV: scripts/x.sh"$'\n'"        run: bash .base/scripts/x.sh"
  "      - run: |"$'\n'"          bash scripts/x.sh"
)
for mutant in "${mutants[@]}"; do
  awk -v add="$mutant" '{ print } /^    steps:$/ { print add }' "$WORKFLOW" >"$tmp/mutant.yml"
  if [[ -n "$(comm -13 <(sort <<<"$findings") <(audit "$tmp/mutant.yml" | sort))" ]]; then
    ok "the audit flags: ${mutant//$'\n'/ / }"
  else
    fail "the audit passes a step that runs pull request code: $mutant"
  fi
done

test_harness::report
