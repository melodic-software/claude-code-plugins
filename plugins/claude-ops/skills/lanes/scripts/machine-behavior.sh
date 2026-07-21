#!/usr/bin/env bash
# machine-behavior.sh — emit a loop lane's MACHINE-BEHAVIOR environment block.
#
# Every /loop lane otherwise hand-assembles this block each session: the clone
# path, the worktree inventory (root + count + per-worktree branch), the gh
# identity it acts as, and the versions of the plugins it runs on. That is pure
# environment inspection with no reasoning, so it is scripted here and the lane
# prompt references the script instead of re-deriving the block every cycle
# (issue #538, item 1).
#
# DETERMINISM CONTRACT. This script emits ONLY mechanically unambiguous facts.
# It deliberately does NOT compute "deviations from standing rules": the standing
# rules are prose the script cannot read, so a deviation is a model judgment made
# by reading these facts against those rules — not a scripted field. Emitting a
# fabricated deviations verdict would put guessing inside the "deterministic"
# script. The block therefore ends with a one-line pointer reminding the lane to
# make that assessment itself.
#
# Plugin versions are the INSTALLED runtime versions (read from Claude Code's own
# installed_plugins.json), NOT the versions in the repo checkout. The block
# describes the environment the lane is actually running in, and per the lanes
# skill's context/refresh.md a running lane's installed plugin version can lag
# repo HEAD — the installed record is the honest number, the checkout is not.
#
# Usage:
#   machine-behavior.sh [--plugin <id>]... [--repo DIR]
#
#   --plugin <id>   Plugin to report a version for (repeatable). <id> matches the
#                   plugin NAME (the part before '@<marketplace>' in
#                   installed_plugins.json), e.g. `--plugin claude-ops`. With no
#                   --plugin flag, every installed plugin is reported — pass the
#                   specific ids a lane runs to keep the block tight.
#   --repo DIR      Repo root for the worktree inventory (default: the git
#                   toplevel of the current directory).
#   --help
#
# Output (stdout): a formatted text block, printed verbatim by the lane. It is
# greppable line-by-line (each fact on its own `key: value` line) and embeds
# directly into a telemetry-comment body. No JSON surface — nothing parses this.
#
# Fields that cannot be resolved degrade to an explicit `unavailable` marker
# rather than aborting: this is telemetry, and a partial block is more useful to
# a lane than no block. The one hard prerequisite is jq.
#
# Exit codes:
#   0  emitted (individual fields may read `unavailable`)
#   3  invalid argument
#   4  prerequisite missing (jq) or the repo could not be resolved
#
# Env overrides (testing only; production uses the real paths):
#   MACHINE_BEHAVIOR_INSTALLED_JSON  path to installed_plugins.json

set -uo pipefail

# Some native-Windows jq builds CRLF-terminate every line; `$(...)` strips only
# the trailing LF, leaving a stray CR that corrupts a captured value. Route every
# jq call through this wrapper (mirrors fleet-state.sh) so no call site forgets.
jq() { command jq "$@" | tr -d '\r'; }

err() { printf 'ERROR: %s\n' "$*" >&2; }

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

command -v jq >/dev/null 2>&1 || {
  err "jq not found (required)"
  exit 4
}

INSTALLED_JSON="${MACHINE_BEHAVIOR_INSTALLED_JSON:-$HOME/.claude/plugins/installed_plugins.json}"

REPO=""
declare -a WANT_PLUGINS=()
while (($#)); do
  case "$1" in
  --plugin)
    [[ -n "${2:-}" && "$2" != -* ]] || {
      err "option '--plugin' requires a value"
      exit 3
    }
    WANT_PLUGINS+=("$2")
    shift 2
    ;;
  --plugin=*)
    WANT_PLUGINS+=("${1#*=}")
    shift
    ;;
  --repo)
    [[ -n "${2:-}" && "$2" != -* ]] || {
      err "option '--repo' requires a value"
      exit 3
    }
    REPO="$2"
    shift 2
    ;;
  --repo=*)
    REPO="${1#*=}"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown argument: $1"
    exit 3
    ;;
  esac
done

# --- Repo resolution ---------------------------------------------------------
if [[ -n "$REPO" ]]; then
  [[ -d "$REPO" ]] || {
    err "repo not a directory: $REPO"
    exit 4
  }
  REPO="$(cd "$REPO" && pwd)"
else
  REPO="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" || true
  [[ -n "$REPO" ]] || {
    err "not inside a git repo; pass --repo DIR"
    exit 4
  }
fi

# --- gh identity -------------------------------------------------------------
# The account the lane acts as. Degrades to `unavailable` if gh is missing or
# unauthenticated — a lane with no gh is degraded, not a script failure.
gh_identity() {
  local login id
  if ! command -v gh >/dev/null 2>&1; then
    printf 'unavailable (gh not found)'
    return
  fi
  login="$(gh api user --jq '.login' 2>/dev/null | tr -d '\r')"
  id="$(gh api user --jq '.id' 2>/dev/null | tr -d '\r')"
  if [[ -z "$login" ]]; then
    printf 'unavailable (gh api user failed — not authenticated?)'
    return
  fi
  printf '%s (id %s)' "$login" "${id:-?}"
}

# --- Worktree inventory ------------------------------------------------------
# The main worktree owns the common git dir, so it is the dir holding `.git`
# (strip the trailing `/.git` or `/worktrees/...` common-dir suffix). Every
# worktree path + its branch is emitted raw: the worktrees legitimately live
# under different parents (repo dir, loop-worktrees, codex worktrees), so there
# is no single deterministic "pattern" to infer — the raw list IS the pattern.
CLONE_PATH="unavailable"
CURRENT_WT="unavailable"
WT_COUNT=0
declare -a WT_LINES=()

read_worktrees() {
  local porcelain common_dir
  porcelain="$(git -C "$REPO" worktree list --porcelain 2>/dev/null | tr -d '\r')" || return
  common_dir="$(git -C "$REPO" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
  # Main worktree = the dir that owns the common git dir.
  if [[ -n "$common_dir" ]]; then
    case "$common_dir" in
    */.git) CLONE_PATH="${common_dir%/.git}" ;;
    *) CLONE_PATH="$(dirname "$common_dir")" ;;
    esac
  fi
  CURRENT_WT="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"

  local path="" branch=""
  while IFS= read -r line; do
    case "$line" in
    "worktree "*) path="${line#worktree }" ;;
    "branch "*) branch="${line#branch refs/heads/}" ;;
    "detached") branch="(detached)" ;;
    "")
      if [[ -n "$path" ]]; then
        WT_LINES+=("$path|${branch:-(detached)}")
        WT_COUNT=$((WT_COUNT + 1))
        path="" branch=""
      fi
      ;;
    *) ;; # other porcelain fields (HEAD, bare, locked, …) are not needed here
    esac
  done <<<"$porcelain"$'\n'
}

# --- Plugin versions ---------------------------------------------------------
# INSTALLED runtime versions, keyed by plugin name. installed_plugins.json maps
# `<name>@<marketplace>` -> [ {scope, version, ...}, ... ]. Emit the distinct
# versions per selected name (more than one = a scope divergence, surfaced here
# but authoritatively reported by the `plugins` skill's fleet-state.sh).
plugin_versions() {
  if [[ ! -f "$INSTALLED_JSON" ]]; then
    printf '  unavailable (installed_plugins.json not found: %s)\n' "$INSTALLED_JSON"
    return
  fi
  if ! jq empty "$INSTALLED_JSON" 2>/dev/null; then
    printf '  unavailable (installed_plugins.json is not valid JSON: %s)\n' "$INSTALLED_JSON"
    return
  fi

  local want_json='[]'
  ((${#WANT_PLUGINS[@]})) && want_json="$(printf '%s\n' "${WANT_PLUGINS[@]}" | jq -R . | jq -cs .)"

  local rows
  rows="$(jq -r --argjson want "$want_json" '
    (.plugins // {})
    | to_entries
    | map({name: (.key | sub("@.*$"; "")), versions: [.value[].version] | unique})
    | group_by(.name)
    | map({name: .[0].name, versions: (map(.versions) | add | unique)})
    | (if ($want | length) > 0 then map(select(.name as $n | $want | index($n))) else . end)
    | sort_by(.name)
    | .[]
    | "  \(.name)  \(.versions | join(", "))\(if (.versions | length) > 1 then "  (scope-divergent)" else "" end)"
  ' "$INSTALLED_JSON")"

  if [[ -z "$rows" ]]; then
    if ((${#WANT_PLUGINS[@]})); then
      printf '  none of the requested plugins are installed: %s\n' "${WANT_PLUGINS[*]}"
    else
      printf '  (no plugins installed)\n'
    fi
    return
  fi
  printf '%s\n' "$rows"
}

# --- Emit --------------------------------------------------------------------
read_worktrees

printf '== MACHINE-BEHAVIOR ==\n'
printf 'gh-identity: %s\n' "$(gh_identity)"
printf 'clone-path: %s\n' "$CLONE_PATH"
printf 'current-worktree: %s\n' "$CURRENT_WT"
printf 'worktree-count: %s\n' "$WT_COUNT"
if ((WT_COUNT)); then
  printf 'worktrees:\n'
  local_line=""
  for local_line in "${WT_LINES[@]}"; do
    printf '  %s  [%s]\n' "${local_line%%|*}" "${local_line#*|}"
  done
fi
printf 'plugin-versions:\n'
plugin_versions
printf 'deviations: assess these facts against the lane standing rules (not scripted — see machine-behavior.sh header)\n'
