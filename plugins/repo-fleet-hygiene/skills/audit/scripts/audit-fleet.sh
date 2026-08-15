#!/usr/bin/env bash
# Read-only cross-repository Git/GitHub hygiene collector.
# Intentionally contains no mutating Git/GitHub operation.
# --apply-plan is a read-only dry-run approval artifact over a prior plan file.
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: audit-fleet.sh [DIR]... [--root DIR]... [--repo DIR]... [--config FILE]
                      [--canonical github.com/owner/repo=PATH]...
                      [--max-depth 1..12] [--project-dir DIR]
                      [--detail] [--plan-file PATH]
       audit-fleet.sh --apply-plan PATH

Read-only. Discovers repositories, resolves optional canonical checkouts, and
reports confidence-tiered branch, worktree, and GitHub-identity findings.

A bare DIR is equivalent to --root DIR. Windows drive letters like D: are
normalized to D:/ so discovery starts at the drive root, not "cwd on D:".

Default human output is a per-repository rollup (counts by finding kind,
collapsed targets, and an explicit CLEAN / N candidates / BLOCKED verdict)
plus one fleet-scale action plan that lists recommended skill invocations
once per repository. Per-finding detail is available with --detail.
A machine-readable action-plan JSON is always written (--plan-file selects
the path; otherwise a temp file is used and named in the report).

--apply-plan PATH reads a previously emitted plan and prints the ordered
dry-run approval artifact (branches before worktrees). It performs no
mutation; re-derive OIDs at real execution time.

When no CLI scope is given, config-supplied fleet.root / fleet.repo is the
machine-wide default. With neither CLI nor config scope, the run stops and
names how to set scope — it does not audit the session project directory.

--project-dir supplies the session's project directory for the project-scoped
config rung only (not as an implicit audit target). It is passed in rather
than read from the environment, which does not carry it. An empty value means
"no project directory": the project config rung is skipped.
EOF
}

# Windows drive-letter alone (D:) means "cwd on that drive" in shells; a fleet
# discovery root means the volume root. Append / so -d and discovery agree.
normalize_discovery_root() {
  local p="$1"
  if [[ "$p" =~ ^[A-Za-z]:$ ]]; then
    printf '%s/' "$p"
  else
    printf '%s' "$p"
  fi
}

fail() {
  printf 'Error: ' >&2
  display_value "$*" >&2
  printf '\n' >&2
  exit 2
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Path presentation. MSYS/Cygwin render Windows drives as /c/..., a form no Windows shell, file
# manager, or IDE accepts. This report is actionable text whose paths get pasted, so convert to the
# drive form for PRESENTATION ONLY -- every comparison, dedup key, and filesystem test upstream
# keeps the native form it was given.
WINDOWS_PATH_DISPLAY=false
CASE_INSENSITIVE_PATHS=false
case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*)
  WINDOWS_PATH_DISPLAY=true
  CASE_INSENSITIVE_PATHS=true
  ;;
*) ;;
esac

WINDOWS_DRIVE_LETTERS="abcdefghijklmnopqrstuvwxyz"

to_native_path() {
  local text="$1" i lower_drive upper_drive
  [[ "$WINDOWS_PATH_DISPLAY" == "true" && "$text" == */* ]] || {
    printf '%s' "$text"
    return 0
  }
  # Convert at the value start and after a space: the report's two shapes are a bare path field and
  # a path embedded in a handoff sentence. The case pre-filter keeps the tr fork to drives actually
  # present, and avoids ${var^} / ${var,,} so bash 3.2 (macOS system bash) still runs this.
  for ((i = 0; i < 26; i++)); do
    lower_drive="${WINDOWS_DRIVE_LETTERS:i:1}"
    case "$text" in
    "/$lower_drive/"* | *" /$lower_drive/"*) ;;
    *) continue ;;
    esac
    upper_drive="$(printf '%s' "$lower_drive" | tr '[:lower:]' '[:upper:]')"
    [[ "$text" == "/$lower_drive/"* ]] && text="$upper_drive:/${text#"/$lower_drive/"}"
    text="${text//" /$lower_drive/"/" $upper_drive:/"}"
  done
  printf '%s' "$text"
}

# Keep ordinary printable report values readable, but encode any control-bearing value as one Bash
# %q field. Git permits newlines and terminal-control bytes in filesystem paths; raw rendering would
# let a crafted registration forge Finding/Confidence/Handoff lines in this actionable report.
display_value() {
  local value="$1" escaped
  local LC_ALL=C
  if [[ "$value" =~ ^[[:print:]]*$ ]]; then
    to_native_path "$value"
  else
    printf -v escaped '%q' "$value"
    printf '%s' "$escaped"
  fi
}

print_field() {
  local label="$1" value="$2"
  printf '%s: ' "$label"
  display_value "$value"
  printf '\n'
}

# Fail closed before executing either external state reader. The allowlists constrain command,
# option order, arity, and dynamic operand shape; caller-controlled global options, aliases, config
# injection, write-capable API methods, and all other Git/gh subcommands are rejected.
git_probe_allowed() {
  local key remote ref
  case "${1:-}" in
  config)
    [[ "${2:-}" == "--file" && -n "${3:-}" ]] || return 1
    if [[ $# -eq 4 && "$4" == "--list" ]]; then
      return 0
    fi
    if [[ $# -eq 5 && "$4" == "--get" ]]; then
      key="$5"
      [[ "$key" == "fleet.maxDepth" || "$key" =~ ^canonical\.github\.com/[^/[:cntrl:]]+/[^/[:cntrl:]]+\.path$ ]]
      return
    fi
    if [[ $# -eq 6 && "$4" == "--null" && "$5" == "--get-all" ]]; then
      [[ "$6" == "fleet.root" || "$6" == "fleet.repo" || "$6" == "fleet.ackUnavailable" ]]
      return
    fi
    if [[ $# -eq 6 && "$4" == "--get-regexp" && "$5" == "-z" ]]; then
      # Fixed literal pattern only -- not an arbitrary caller-supplied regex.
      [[ "$6" == '^canonical\.[^[:cntrl:]]+\.path$' ]]
      return
    fi
    return 1
    ;;
  -C)
    [[ $# -ge 4 && -n "${2:-}" ]] || return 1
    case "$3" in
    rev-parse)
      # --show-prefix is read-only and operand-free, like --show-toplevel. It is the probe that
      # tells a work-tree ROOT (empty) from a path below one (non-empty) without any path
      # arithmetic, which is what keeps a leftover directory from being read as the worktree it is
      # registered as.
      # --is-bare-repository is the same shape again, and it is what separates a
      # bare hub's legitimately-absent working tree from a probe that failed.
      [[ $# -eq 4 && ("$4" == "--show-toplevel" || "$4" == "--show-prefix" || "$4" == "--is-bare-repository") ]] ||
        [[ $# -eq 5 && "$4" == "--path-format=absolute" && "$5" == "--git-common-dir" ]]
      ;;
    remote)
      if [[ $# -eq 3 ]]; then
        return 0
      fi
      remote="${5:-}"
      [[ $# -eq 5 && "$4" == "get-url" && -n "$remote" && "$remote" != -* &&
        ! "$remote" =~ [[:cntrl:][:space:]] ]]
      ;;
    worktree)
      [[ $# -eq 7 && "$4" == "list" && "$5" == "--porcelain" && "$6" == "-z" && "$7" == "--" ]]
      ;;
    symbolic-ref)
      ref="${4:-}"
      [[ $# -eq 4 && "$ref" == refs/remotes/*/HEAD && ! "$ref" =~ [[:cntrl:][:space:]] ]]
      ;;
    branch)
      [[ $# -eq 4 && "$4" == "--show-current" ]]
      ;;
    log)
      [[ $# -eq 6 && "$4" == "-1" && "$5" == "--format=%ct" && "$6" == "HEAD" ]]
      ;;
    for-each-ref)
      [[ $# -eq 6 && "$4" == "--format=%(refname:short)%09%(objectname)%00" && "$5" == "--" ]] || return 1
      [[ "$6" == "refs/heads/" ]] && return 0
      [[ "$6" == refs/remotes/*/ && ! "$6" =~ [[:cntrl:][:space:]] ]]
      ;;
    ls-remote)
      # Read-only live remote probe: prove a named head still exists upstream without fetch/prune.
      remote="${5:-}"
      ref="${6:-}"
      [[ $# -eq 6 && "$4" == "--heads" && -n "$remote" && "$remote" != -* &&
        ! "$remote" =~ [[:cntrl:][:space:]] && "$ref" == refs/heads/* &&
        ! "$ref" =~ [[:cntrl:][:space:]] ]]
      ;;
    merge-base)
      ref="${6:-}"
      [[ $# -eq 6 && "$4" == "--is-ancestor" && -n "${5:-}" && "${5:-}" != -* &&
        ! "${5:-}" =~ [[:cntrl:][:space:]] && "$ref" == refs/remotes/* &&
        ! "$ref" =~ [[:cntrl:][:space:]] ]]
      ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

run_git_probe() {
  if ! git_probe_allowed "$@"; then
    printf 'Rejected non-allowlisted Git probe\n' >&2
    return 126
  fi
  (
    # Repository selectors and command-scoped config must come only from the validated argv above.
    # GIT_CONFIG_COUNT=0 neutralizes inherited GIT_CONFIG_KEY_*/VALUE_* pairs even when the parent
    # environment contains them; the older aggregate injection variable is removed explicitly.
    # GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM are pinned to /dev/null (per git(1) ENVIRONMENT) so an
    # inherited selector or a global includeIf (e.g. an injected url.*.insteadOf) can never redirect
    # a probe away from the repository's own on-disk config.
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_PREFIX
    # Subshell-local env only; SC2030/SC2031 are false cross-function hits vs run_convention_git.
    # shellcheck disable=SC2030,SC2031
    export GIT_CONFIG_COUNT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      GIT_NO_LAZY_FETCH=1 GIT_OPTIONAL_LOCKS=0 GIT_PAGER=cat GIT_TERMINAL_PROMPT=0
    command git "$@"
  )
}

# Convention-root reads (melodic.worktreeroot) must see global/includeIf config, so they are a
# separate allowlist from run_git_probe. Fixed key and flag order only.
convention_git_allowed() {
  case "${1:-}" in
  -C)
    [[ $# -ge 4 && -n "${2:-}" ]] || return 1
    case "$3" in
    rev-parse)
      [[ $# -eq 4 && "$4" == "--git-dir" ]]
      ;;
    config)
      [[ $# -eq 7 && "$4" == "--get-all" && "$5" == "--show-origin" &&
        "$6" == "--type=path" && "$7" == "melodic.worktreeroot" ]]
      ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

run_convention_git() {
  if ! convention_git_allowed "$@"; then
    printf 'Rejected non-allowlisted convention Git probe\n' >&2
    return 126
  fi
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_PREFIX
    # Do not null GIT_CONFIG_GLOBAL/SYSTEM: melodic.worktreeroot is expected outside the repo.
    # Subshell-local env only; SC2030/SC2031 are false cross-function hits vs run_git_probe.
    # shellcheck disable=SC2030,SC2031
    export GIT_CONFIG_COUNT=0 GIT_NO_LAZY_FETCH=1 GIT_OPTIONAL_LOCKS=0 GIT_PAGER=cat \
      GIT_TERMINAL_PROMPT=0
    command git "$@"
  )
}

# Aliased GraphQL merged-PR page size. GitHub admits first/last in 1..100; each alias costs one
# node. Measured live: cost stays 1 for at least 40 aliases (nodeCount equals the alias count).
# 100 aliases per page stays well under the 500_000-node ceiling and the 5_000-point/hour primary
# limit. Single-sourced with the allowlist so nothing reachable by a caller can change it.
MERGED_PR_GRAPHQL_ALIAS_PAGE=100

# Fixed jq flatten for the aliased GraphQL response — single-sourced with the allowlist pin.
# Filters rateLimit and null repository payloads; emits one TSV row per merged PR node.
MERGED_PR_GRAPHQL_JQ='.data|to_entries[]|select(.key|test("^b[0-9]+$"))|.value//empty|.pullRequests.nodes[]?|[.number,.headRefName,.headRefOid,.mergedAt,.url]|@tsv'

# Escape a value for inclusion in a GraphQL string literal (owner, name, headRefName).
graphql_string_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

# Admit only the collector's query-shaped merged-PR GraphQL document: no mutation/subscription,
# exact headRefName matching (never the search API's prefix-matching head: qualifier), first:1.
graphql_query_admitted() {
  local q=${1-}
  [[ -n "$q" ]] || return 1
  [[ "$q" =~ [[:cntrl:]] ]] && return 1
  # Literal brace prefixes: query{...} or query {...}
  [[ "$q" == "query{"* || "$q" == "query {"* ]] || return 1
  case "$(printf '%s' "$q" | tr '[:upper:]' '[:lower:]')" in
  *mutation* | *subscription*) return 1 ;;
  *) ;; # admitted shape continues below
  esac
  [[ "$q" == *'headRefName:'* && "$q" == *'first:1'* && "$q" == *'states:[MERGED]'* &&
    "$q" == *'pullRequests('* && "$q" == *'repository(owner:'* ]]
}

gh_probe_allowed() {
  case "${1:-}" in
  auth)
    [[ $# -eq 4 && "$2" == "status" && "$3" == "--hostname" && "$4" == "github.com" ]]
    ;;
  api)
    # Three read-only shapes: repository identity GET, authenticated-login GET, and the aliased
    # GraphQL merged-PR query (query documents only; fixed --jq flatten).
    if [[ $# -eq 8 && "$2" =~ ^repos/[^/[:cntrl:][:space:]]+/[^/[:cntrl:][:space:]]+$ &&
      "$3" == "--hostname" && "$4" == "github.com" && "$5" == "--method" && "$6" == "GET" &&
      "$7" == "--template" && "$8" == '{{printf "%s\t%s" .full_name .default_branch}}' ]]; then
      return 0
    fi
    if [[ $# -eq 8 && "$2" == "user" &&
      "$3" == "--hostname" && "$4" == "github.com" && "$5" == "--method" && "$6" == "GET" &&
      "$7" == "--template" && "$8" == '{{.login}}' ]]; then
      return 0
    fi
    if [[ $# -eq 8 && "$2" == "graphql" && "$3" == "--hostname" && "$4" == "github.com" &&
      "$5" == "-f" && "$6" == query=* && "$7" == "--jq" && "$8" == "$MERGED_PR_GRAPHQL_JQ" ]]; then
      graphql_query_admitted "${6#query=}"
      return
    fi
    return 1
    ;;
  *) return 1 ;;
  esac
}

# GitHub CLI has no request-timeout flag. Prefer GNU timeout/gtimeout only when its documented
# --kill-after capability is present. The pure-Bash watchdog is the platform-safe fallback and still
# escalates TERM to KILL after a finite grace period. The test switch can only shorten both bounds.
GH_TIMEOUT_SECONDS=30
GH_KILL_AFTER_SECONDS=5
if [[ "${REPO_FLEET_TEST_FAST_TIMEOUTS:-}" == "1" ]]; then
  GH_TIMEOUT_SECONDS=1
  GH_KILL_AFTER_SECONDS=1
fi
GH_TIMEOUT_COMMAND=""
if [[ "${REPO_FLEET_FORCE_BASH_TIMEOUT:-}" != "1" ]]; then
  for candidate in timeout gtimeout; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" --help 2>&1 | grep -Fq -- '--kill-after'; then
      GH_TIMEOUT_COMMAND="$candidate"
      break
    fi
  done
fi

run_with_bash_timeout() {
  local child watchdog status
  "$@" &
  child=$!
  (
    sleep "$GH_TIMEOUT_SECONDS"
    kill -TERM "$child" 2>/dev/null || exit 0
    sleep "$GH_KILL_AFTER_SECONDS"
    kill -KILL "$child" 2>/dev/null || true
  ) &
  watchdog=$!
  wait "$child"
  status=$?
  kill -TERM "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$status"
}

run_bounded_gh() {
  if ! gh_probe_allowed "$@"; then
    printf 'Rejected non-allowlisted gh probe\n' >&2
    return 126
  fi
  (
    unset GH_REPO GH_DEBUG DEBUG GH_FORCE_TTY GH_PAGER PAGER GH_EDITOR GIT_EDITOR VISUAL EDITOR \
      GH_BROWSER BROWSER
    export GH_HOST=github.com GH_PROMPT_DISABLED=1 GH_TELEMETRY=false GH_NO_UPDATE_NOTIFIER=1 \
      GH_NO_EXTENSION_UPDATE_NOTIFIER=1 GH_SPINNER_DISABLED=1 NO_COLOR=1
    if [[ -n "$GH_TIMEOUT_COMMAND" ]]; then
      "$GH_TIMEOUT_COMMAND" --signal=TERM --kill-after="${GH_KILL_AFTER_SECONDS}s" \
        "${GH_TIMEOUT_SECONDS}s" gh "$@"
    else
      run_with_bash_timeout gh "$@"
    fi
  )
}

# Tests source these fail-closed wrappers directly to exercise forbidden Git/gh vectors without
# running discovery. Normal execution continues into the collector below.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

command -v git >/dev/null 2>&1 || fail "git is required"

ROOT_ARGS=()
REPO_ARGS=()
OVERRIDE_KEYS=()
OVERRIDE_PATHS=()
CONFIG_FILE=""
MAX_DEPTH=""
PROJECT_DIR_ARG=""
DETAIL=false
PLAN_FILE=""
APPLY_PLAN=""
PLAN_FILE_EXPLICIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  # An empty value is rejected rather than accepted-and-skipped: the discovery loops ignore an
  # empty entry, so accepting one would let the header's scope count claim an argument that
  # contributed nothing. A CLI typo stops the run, as everywhere else in this grammar.
  --root)
    [[ $# -ge 2 && -n "$2" ]] || fail "--root requires a directory"
    ROOT_ARGS+=("$(normalize_discovery_root "$2")")
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 && -n "$2" ]] || fail "--repo requires a directory"
    REPO_ARGS+=("$2")
    shift 2
    ;;
  --config)
    [[ $# -ge 2 && -n "$2" ]] || fail "--config requires a file"
    [[ -z "$CONFIG_FILE" ]] || fail "--config may be supplied only once"
    CONFIG_FILE="$2"
    shift 2
    ;;
  --canonical)
    [[ $# -ge 2 ]] || fail "--canonical requires github.com/owner/repo=PATH"
    pair="$2"
    [[ "$pair" == *=* ]] || fail "invalid --canonical value: $pair"
    key="${pair%%=*}"
    value="${pair#*=}"
    key="$(lower "$key")"
    [[ "$key" =~ ^github\.com/[^/]+/[^/]+$ && -n "$value" ]] ||
      fail "invalid --canonical value: $pair"
    OVERRIDE_KEYS+=("$key")
    OVERRIDE_PATHS+=("$value")
    shift 2
    ;;
  --max-depth)
    [[ $# -ge 2 ]] || fail "--max-depth requires an integer"
    MAX_DEPTH="$2"
    shift 2
    ;;
  --project-dir)
    [[ $# -ge 2 ]] || fail "--project-dir requires a directory"
    PROJECT_DIR_ARG="$2"
    shift 2
    ;;
  --detail)
    DETAIL=true
    shift
    ;;
  --plan-file)
    [[ $# -ge 2 && -n "$2" ]] || fail "--plan-file requires a path"
    PLAN_FILE="$2"
    PLAN_FILE_EXPLICIT=true
    shift 2
    ;;
  --apply-plan)
    [[ $# -ge 2 && -n "$2" ]] || fail "--apply-plan requires a path"
    [[ -z "$APPLY_PLAN" ]] || fail "--apply-plan may be supplied only once"
    APPLY_PLAN="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    # Reject unknown dashed tokens; that is the injection boundary. Bare paths
    # (including drive roots) are accepted below as --root equivalents (#2599).
    fail "unknown argument: $1"
    ;;
  *)
    # Bare positional path ≡ --root. An empty value is rejected rather than
    # accepted-and-skipped so the header cannot claim a scope that contributed
    # nothing.
    [[ -n "$1" ]] || fail "bare path requires a directory"
    ROOT_ARGS+=("$(normalize_discovery_root "$1")")
    shift
    ;;
  esac
done

# --apply-plan is a standalone read-only mode: render an ordered dry-run approval
# artifact from a prior audit plan. No discovery, no GitHub calls, no mutation.
if [[ -n "$APPLY_PLAN" ]]; then
  if [[ ${#ROOT_ARGS[@]} -gt 0 || ${#REPO_ARGS[@]} -gt 0 || -n "$CONFIG_FILE" ||
    ${#OVERRIDE_KEYS[@]} -gt 0 || -n "$MAX_DEPTH" || -n "$PROJECT_DIR_ARG" ||
    "$DETAIL" == "true" || "$PLAN_FILE_EXPLICIT" == "true" ]]; then
    fail "--apply-plan cannot be combined with audit discovery flags"
  fi
  [[ -f "$APPLY_PLAN" ]] || fail "apply-plan file not found: $APPLY_PLAN"
  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required to read an action plan"
  fi
  APPLY_PLAN_PATH="$APPLY_PLAN" python3 - <<'PY'
import json, os, sys
path = os.environ["APPLY_PLAN_PATH"]
try:
    with open(path, encoding="utf-8") as f:
        plan = json.load(f)
except (OSError, json.JSONDecodeError) as e:
    print(f"Error: invalid action plan JSON: {e}", file=sys.stderr)
    sys.exit(2)
if not isinstance(plan, dict) or plan.get("schema_version") != 1:
    print("Error: action plan schema_version must be 1", file=sys.stderr)
    sys.exit(2)
actions = plan.get("actions")
if not isinstance(actions, list):
    print("Error: action plan missing actions list", file=sys.stderr)
    sys.exit(2)

def phase(op: str) -> int:
    if op == "delete-merged-local-branches":
        return 1
    if op == "cleanup-worktrees":
        return 2
    return 9

ordered = sorted(
    enumerate(actions),
    key=lambda it: (
        phase(str(it[1].get("operation", ""))),
        str(it[1].get("canonical", "")),
        it[0],
    ),
)
print("Repo Fleet Hygiene — apply-plan dry-run (no mutations)")
print("Mode: read-only approval artifact; re-derive OIDs at execution time")
print("Confirmation model: ONE gate for this entire plan (not per repository)")
print("Order rule: delete/clean branches before pruning worktrees")
print(f"Plan: {path}")
summary = plan.get("summary") if isinstance(plan.get("summary"), dict) else {}
if summary:
    print(
        "Summary: repositories_audited={ra} high={h} medium={m} low={l} unknown={u} acknowledged={a}".format(
            ra=summary.get("repositories_audited", "?"),
            h=summary.get("high", "?"),
            m=summary.get("medium", "?"),
            l=summary.get("low", "?"),
            u=summary.get("unknown", "?"),
            a=summary.get("acknowledged", "?"),
        )
    )
print()
if not ordered:
    print("Actions: none")
else:
    print(f"Actions: {len(ordered)}")
    for step, (_idx, action) in enumerate(ordered, 1):
        skill = action.get("skill", "?")
        canonical = action.get("canonical", "?")
        operation = action.get("operation", "?")
        kinds = action.get("kinds") or []
        targets = action.get("targets") or []
        print(f"{step}. {skill}")
        print(f"   repository: {canonical}")
        print(f"   operation: {operation}")
        if kinds:
            print(f"   kinds: {', '.join(map(str, kinds))}")
        if targets:
            print(f"   targets ({len(targets)}):")
            for t in targets:
                print(f"     - {t}")
        print("   note: re-derive OIDs at execution time; do not trust plan tips")
        print()
print("Mutations: none; this invocation only renders the approval artifact.")
PY
  exit $?
fi

# Project directory. ${CLAUDE_PROJECT_DIR} is documented to substitute in a skill's markdown
# content and in its allowed-tools Bash rules -- NOT to be present in the Bash tool's environment,
# which is where this collector runs. Reading it from the environment left the project rung of the
# config ladder permanently unreachable, so the skill body passes it in as --project-dir, where the
# documented substitution applies. The environment is still honored for callers that genuinely have
# it (hooks, MCP stdio servers, a direct shell).
#
# The ${...} guard below is defence in depth, not the primary path: when Claude Code does not
# substitute the placeholder, the literal reaches the shell, which expands the unset variable to an
# empty string before this script is entered -- so the ordinary miss arrives as empty and is handled
# by the emptiness checks. The guard catches only a literal that survives shell expansion (a
# single-quoted argument, or a caller that invokes this script without a shell), where treating
# "${CLAUDE_PROJECT_DIR}" as a directory name would be strictly worse than treating it as absent.
PROJECT_DIR="${PROJECT_DIR_ARG:-${CLAUDE_PROJECT_DIR:-}}"
case "$PROJECT_DIR" in
"\${"*) PROJECT_DIR="" ;;
*) ;;
esac

# Config resolution ladder: explicit --config, then the project-scoped file,
# then the user-global one. A fleet config is inherently machine-scoped, so a
# user-global ~/.claude file is honored when the current project carries none —
# that file is recorded user intent, not a guessed broader machine root. The
# consumed source is named in the report header so silent non-consumption
# cannot happen.
CONFIG_SOURCE="none"
if [[ -n "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" ]] || fail "config file not found: $CONFIG_FILE"
  CONFIG_SOURCE="explicit --config"
else
  if [[ -n "$PROJECT_DIR" && -f "$PROJECT_DIR/.claude/repo-fleet-hygiene.conf" ]]; then
    CONFIG_FILE="$PROJECT_DIR/.claude/repo-fleet-hygiene.conf"
    CONFIG_SOURCE="project"
  else
    home_dir="${HOME:-${USERPROFILE:-}}"
    if [[ -n "$home_dir" && -f "$home_dir/.claude/repo-fleet-hygiene.conf" ]]; then
      CONFIG_FILE="$home_dir/.claude/repo-fleet-hygiene.conf"
      CONFIG_SOURCE="user-global"
    fi
  fi
fi
if [[ -n "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" 2>/dev/null && pwd -P)/$(basename "$CONFIG_FILE")"
  # An invalid config fails loud regardless of how it was found — an
  # auto-probed file never silently falls back to a narrower scope.
  run_git_probe config --file "$CONFIG_FILE" --list >/dev/null 2>&1 || fail "invalid Git config: $CONFIG_FILE"
  CONFIG_DIR="$(dirname "$CONFIG_FILE")"
else
  CONFIG_DIR=""
fi

if [[ -z "$MAX_DEPTH" && -n "$CONFIG_FILE" ]]; then
  MAX_DEPTH="$(run_git_probe config --file "$CONFIG_FILE" --get fleet.maxDepth 2>/dev/null || true)"
fi
MAX_DEPTH="${MAX_DEPTH:-5}"
[[ "$MAX_DEPTH" =~ ^[0-9]+$ && "$MAX_DEPTH" -ge 1 && "$MAX_DEPTH" -le 12 ]] ||
  fail "max depth must be an integer from 1 through 12"

resolve_input_path() {
  local value="$1" base="$2"
  if [[ "$value" =~ ^/ || "$value" =~ ^[A-Za-z]:[\\/] ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$base" "$value"
  fi
}

# Entries before these counts came from the command line; entries appended from config below sit
# at or past them. The failure unit differs by origin: a CLI typo should stop the run, but a
# config-sourced path that has since been deleted degrades per-entry (stale-config-entry UNKNOWN)
# so removing five repos right after an audit cannot abort every subsequent fleet run.
CLI_ROOT_COUNT=${#ROOT_ARGS[@]}
CLI_REPO_COUNT=${#REPO_ARGS[@]}
if [[ -n "$CONFIG_FILE" ]]; then
  while IFS= read -r -d '' value; do
    [[ -n "$value" ]] && ROOT_ARGS+=("$(resolve_input_path "$value" "$CONFIG_DIR")")
  done < <(run_git_probe config --file "$CONFIG_FILE" --null --get-all fleet.root 2>/dev/null || true)
  while IFS= read -r -d '' value; do
    [[ -n "$value" ]] && REPO_ARGS+=("$(resolve_input_path "$value" "$CONFIG_DIR")")
  done < <(run_git_probe config --file "$CONFIG_FILE" --null --get-all fleet.repo 2>/dev/null || true)
fi

# Acknowledged known-inaccessible GitHub identities (fleet.ackUnavailable,
# repeatable). An acknowledgment only demotes a 404/403
# github-identity-unavailable finding to ACKNOWLEDGED prominence — it never
# suppresses the finding, never touches non-404/403 failures, and never
# affects evidence from a successful API response.
ACK_KEYS=()
if [[ -n "$CONFIG_FILE" ]]; then
  while IFS= read -r -d '' value; do
    [[ -n "$value" ]] || continue
    ack_key="$(lower "$value")"
    [[ "$ack_key" =~ ^github\.com/[^/[:cntrl:][:space:]]+/[^/[:cntrl:][:space:]]+$ ]] ||
      fail "invalid fleet.ackUnavailable value (expected github.com/owner/repository): $value"
    ACK_KEYS+=("$ack_key")
  done < <(run_git_probe config --file "$CONFIG_FILE" --null --get-all fleet.ackUnavailable 2>/dev/null || true)
fi

is_acked() {
  local key a
  key="$(lower "$1")"
  for a in "${ACK_KEYS[@]:-}"; do
    [[ -n "$a" && "$a" == "$key" ]] && return 0
  done
  return 1
}

UNRESOLVED_SCOPE=false
SCOPE_FALLBACK_NOTE="so no repository scope resolved"
if [[ ${#ROOT_ARGS[@]} -eq 0 && ${#REPO_ARGS[@]} -eq 0 ]]; then
  # No CLI and no config-supplied fleet.root/fleet.repo. A fleet tool's no-argument form is
  # machine-wide config scope when present; without it, refuse the old project-directory-as-exact
  # --repo default rather than auditing an unintended tree (#2599).
  UNRESOLVED_SCOPE=true
fi

# Scope provenance: which rung actually supplied the audited roots/repos. This is a different
# question from which config FILE was consumed, and the header used to answer it with a fixed
# literal that could contradict the run's own inputs two lines later. Config-supplied scope is
# ADDITIVE to any CLI-supplied scope, so both contributions are named rather than one masking the
# other. Bare positional paths count as command-line --root equivalents.
cli_scope_count=$((CLI_ROOT_COUNT + CLI_REPO_COUNT))
config_scope_count=$((${#ROOT_ARGS[@]} - CLI_ROOT_COUNT + ${#REPO_ARGS[@]} - CLI_REPO_COUNT))
SCOPE_PROVENANCE=""
[[ "$cli_scope_count" -gt 0 ]] &&
  SCOPE_PROVENANCE="command line ($cli_scope_count --root/--repo argument(s))"
if [[ "$config_scope_count" -gt 0 ]]; then
  [[ -n "$SCOPE_PROVENANCE" ]] && SCOPE_PROVENANCE="$SCOPE_PROVENANCE + "
  SCOPE_PROVENANCE="${SCOPE_PROVENANCE}config $CONFIG_SOURCE ($config_scope_count fleet.root/fleet.repo entr(ies))"
fi

path_key() {
  local value="${1//\\//}"
  while [[ "$value" == */ ]]; do value="${value%/}"; done
  if [[ "$CASE_INSENSITIVE_PATHS" == "true" ]]; then
    lower "$value"
  else
    printf '%s' "$value"
  fi
}

# Physical path for containment comparisons. git worktree list reports resolved
# paths; melodic.worktreeroot may be a symlink alias. Same realpath||readlink -f
# idiom as source-control/hook-utils. Annotate: earlier subshell+continuation join
# state in this file can miss the shell-portability-lint auto-guard.
physical_path() {
  local resolved
  # portability-ok: realpath||readlink -f ladder (hook-utils idiom); auto-guard can miss after subshell+continuation join state
  if resolved=$(realpath -- "$1" 2>/dev/null) || resolved=$(readlink -f -- "$1" 2>/dev/null); then
    [[ -n "$resolved" ]] && {
      printf '%s' "$resolved"
      return 0
    }
  fi
  printf '%s' "$1"
}

# Worktree-root convention is owned by source-control (#2597 / #2606). This collector reads it and
# reports conformance; it never invents a default root. Prefer the machine-readable git key
# (melodic.worktreeroot, #2610) when present; otherwise the source-control pluginConfigs /
# CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT surface. Every git-config read is gated on rev-parse --git-dir
# first: under dubious ownership, git config --get returns the global default as though it were the
# repository's answer (rc=0, no stderr). Attribution uses --show-origin so a conditional include is
# not collapsed to a bare "global" scope.
CONFIGURED_WORKTREE_ROOT=""
CONFIGURED_WORKTREE_ROOT_ORIGIN=""
CONFIGURED_WORKTREE_ROOT_SOURCE="unset"
FLEET_WT_LINKED=0
FLEET_WT_CONFORMING=0
FLEET_WT_NONCONFORMING=0
FLEET_WT_TOOL_OWNED=0
PLUGINCONFIGS_JQ_MISSING=false
PLUGINCONFIGS_SETTINGS_PATH=""

# Sanitize a branch name into the slug half of <owner>-<repo>-<slug>, matching source-control's
# worktree-create helper so the expected location names the path create would have used.
worktree_slug() {
  local slug="$1"
  slug="${slug//[^A-Za-z0-9._-]/-}"
  while [[ "$slug" == *--* ]]; do slug="${slug//--/-}"; done
  slug="${slug#-}"
  slug="${slug%-}"
  printf '%s' "$slug"
}

expected_worktree_dirname() {
  local owner="$1" repo="$2" branch="$3" slug
  slug="$(worktree_slug "$branch")"
  [[ -n "$slug" ]] || slug="detached"
  if [[ -n "$owner" && -n "$repo" ]]; then
    printf '%s-%s-%s' "$owner" "$repo" "$slug"
  elif [[ -n "$repo" ]]; then
    printf '%s-%s' "$repo" "$slug"
  else
    printf '%s' "$slug"
  fi
}

# Tool-owned locations the source-control convention explicitly exempts from "misplaced" —
# Codex ($CODEX_HOME/worktrees, default ~/.codex/worktrees) and Cursor (~/.cursor/worktrees).
# Claude Code's in-repo .claude/worktrees/ is tool-created but NON-conforming by the fleet rule
# (EnterWorktree(name:)), so it is not classified tool-owned here.
is_tool_owned_worktree() {
  local key tool_home
  key="$(path_key "$1")"
  [[ "$key" == *"/.codex/worktrees/"* || "$key" == *"/.codex/worktrees" ||
    "$key" == *"/.cursor/worktrees/"* || "$key" == *"/.cursor/worktrees" ]] && return 0
  tool_home="${CODEX_HOME:-}"
  if [[ -n "$tool_home" ]]; then
    tool_home="$(path_key "$tool_home")"
    [[ "$key" == "$tool_home/worktrees/"* || "$key" == "$tool_home/worktrees" ]] && return 0
  fi
  return 1
}

under_configured_root() {
  local wt_key root_key
  [[ -n "$CONFIGURED_WORKTREE_ROOT" ]] || return 1
  wt_key="$(path_key "$(physical_path "$1")")"
  root_key="$(path_key "$(physical_path "$CONFIGURED_WORKTREE_ROOT")")"
  [[ "$wt_key" == "$root_key" || "$wt_key" == "$root_key"/* ]]
}

# Gate + last-wins read of melodic.worktreeroot from one repository. Sets
# CONFIGURED_WORKTREE_ROOT / _ORIGIN / _SOURCE on success.
try_read_melodic_worktree_root() {
  local probe="$1" line origin value last_origin="" last_value=""
  [[ -n "$probe" && -d "$probe" ]] || return 1
  run_convention_git -C "$probe" rev-parse --git-dir >/dev/null 2>&1 || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -n "$line" ]] || continue
    # --show-origin prefixes "file:<path><TAB><value>" (or "command:..." / "standard input").
    if [[ "$line" == *$'\t'* ]]; then
      origin="${line%%$'\t'*}"
      value="${line#*$'\t'}"
    else
      origin="unknown"
      value="$line"
    fi
    [[ -n "$value" ]] || continue
    last_origin="$origin"
    last_value="$value"
  done < <(run_convention_git -C "$probe" config --get-all --show-origin --type=path melodic.worktreeroot 2>/dev/null)
  [[ -n "$last_value" ]] || return 1
  CONFIGURED_WORKTREE_ROOT="$last_value"
  CONFIGURED_WORKTREE_ROOT_ORIGIN="$last_origin"
  CONFIGURED_WORKTREE_ROOT_SOURCE="melodic.worktreeroot"
  return 0
}

# Fallback when #2610's git key is unset: source-control's existing worktree_root userConfig,
# surfaced as CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT in a plugin session, else pluginConfigs in the
# user settings file. Never invents the plugin-data default — an absent key stays unset.
try_read_source_control_worktree_root() {
  local env_val settings home_dir cfg_dir value
  env_val="${CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT:-}"
  case "$env_val" in
  '' | "\${"*) ;;
  *)
    CONFIGURED_WORKTREE_ROOT="$env_val"
    CONFIGURED_WORKTREE_ROOT_ORIGIN="env:CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT"
    CONFIGURED_WORKTREE_ROOT_SOURCE="source-control:worktree_root"
    return 0
    ;;
  esac

  cfg_dir="${CLAUDE_CONFIG_DIR:-}"
  home_dir="${HOME:-${USERPROFILE:-}}"
  if [[ -n "$cfg_dir" && -f "$cfg_dir/settings.json" ]]; then
    settings="$cfg_dir/settings.json"
  elif [[ -n "$home_dir" && -f "$home_dir/.claude/settings.json" ]]; then
    settings="$home_dir/.claude/settings.json"
  else
    return 1
  fi
  # Marketplace-qualified keys are source-control@<marketplace>; also accept a bare source-control
  # entry. jq last-wins across matching entries so a more-specific install can override.
  # jq is not a declared plugin requirement (README: Git + Bash / Git Bash). Missing jq must not
  # look identical to "key unset" — that would falsely report worktree-root-unconfigured.
  if ! command -v jq >/dev/null 2>&1; then
    PLUGINCONFIGS_JQ_MISSING=true
    PLUGINCONFIGS_SETTINGS_PATH="$settings"
    return 1
  fi
  value="$(
    jq -r '
      (.pluginConfigs // {})
      | to_entries
      | map(select(.key == "source-control" or (.key | startswith("source-control@"))))
      | map(.value.options.worktree_root // empty)
      | map(select(type == "string" and length > 0))
      | last // empty
    ' "$settings" 2>/dev/null || true
  )"
  [[ -n "$value" ]] || return 1
  CONFIGURED_WORKTREE_ROOT="$value"
  CONFIGURED_WORKTREE_ROOT_ORIGIN="file:$settings"
  CONFIGURED_WORKTREE_ROOT_SOURCE="source-control:worktree_root"
  return 0
}

resolve_configured_worktree_root() {
  local probe
  CONFIGURED_WORKTREE_ROOT=""
  CONFIGURED_WORKTREE_ROOT_ORIGIN=""
  CONFIGURED_WORKTREE_ROOT_SOURCE="unset"
  # Fleet-wide single root: first TARGET whose melodic.worktreeroot resolves wins (discovery
  # order). Per-repository includeIf roots that intentionally differ are not modeled — the
  # header and every conformance finding name that one root. Prefer a machine-global
  # pluginConfigs / CLAUDE_PLUGIN_OPTION value when repositories disagree.
  for probe in "${TARGETS[@]:-}"; do
    [[ -n "$probe" ]] || continue
    try_read_melodic_worktree_root "$probe" && return 0
  done
  if [[ -n "$PROJECT_DIR" ]]; then
    try_read_melodic_worktree_root "$PROJECT_DIR" && return 0
  fi
  try_read_source_control_worktree_root && return 0
  return 1
}


# directory_has_non_git_entries <dir>: true when <dir> still looks like a former non-bare
# checkout left with core.bare=true. Real `git init --bare` hubs store HEAD/config/objects/refs
# at the repository root and never have an in-tree `.git`; the anomaly this finding targets keeps
# a nested `.git` (file or directory) beside leftover working-tree content (#2602).
directory_has_non_git_entries() {
  local dir="$1" child name
  # Ordinary bare hubs have no nested .git — do not treat their admin files as checkout debris.
  [[ -e "$dir/.git" || -L "$dir/.git" ]] || return 1
  for child in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [[ -e "$child" || -L "$child" ]] || continue
    name="$(basename "$child")"
    case "$name" in
    . | .. | .git) continue ;;
    *) return 0 ;;
    esac
  done
  # Nested .git alone still marks the misconfigured non-bare shape (empty work tree).
  return 0
}

# count_worktree_registrations <dir>: how many porcelain worktree records git reports. The main
# (possibly bare) registration counts as one; linked worktrees push the total above one.
count_worktree_registrations() {
  local dir="$1" record count=0
  while IFS= read -r -d '' record; do
    record="${record%$'\r'}"
    [[ "$record" == "worktree "* ]] && count=$((count + 1))
  done < <(run_git_probe -C "$dir" worktree list --porcelain -z -- 2>/dev/null)
  printf '%s\n' "$count"
}

# classify_bare_live_tree <dir>: when <dir> is bare AND has working-tree content or linked
# worktrees, print evidence and return 0. Otherwise return non-zero. Does not mutate state.
classify_bare_live_tree() {
  local dir="$1" bare wt_count=0 has_content="false" evidence="" detail=""
  bare="$(run_git_probe -C "$dir" rev-parse --is-bare-repository 2>/dev/null | tr -d '\r')" || return 1
  [[ "$bare" == "true" ]] || return 1
  wt_count="$(count_worktree_registrations "$dir")"
  directory_has_non_git_entries "$dir" && has_content="true"
  # Pure bare hub (no checkout debris, no linked registrations): not this finding.
  if [[ "$has_content" != "true" && "$wt_count" -le 1 ]]; then
    return 1
  fi
  if [[ "$has_content" == "true" && "$wt_count" -gt 1 ]]; then
    detail="populated working-tree content and $((wt_count - 1)) linked worktree registration(s)"
  elif [[ "$has_content" == "true" ]]; then
    detail="populated working-tree content"
  else
    detail="$((wt_count - 1)) linked worktree registration(s)"
  fi
  evidence="core.bare=true coincides with $detail; linked worktrees keep working -- only the main worktree is disabled"
  printf '%s\n' "$evidence"
}

# record_bare_live_tree <path> <evidence> <common_key>: defer a bare-repo-with-working-tree finding.
# Dedup is by common-dir among anomaly records only — a linked worktree already queued for audit
# must not suppress the anomaly finding for the misconfigured main path.
record_bare_live_tree() {
  local path="$1" evidence="$2" common_key="$3" existing
  for existing in "${BARE_LIVE_TREE_COMMON_KEYS[@]:-}"; do
    [[ "$existing" == "$common_key" ]] && return 0
  done
  BARE_LIVE_TREE_PATHS+=("$path")
  BARE_LIVE_TREE_EVIDENCE+=("$evidence")
  BARE_LIVE_TREE_COMMON_KEYS+=("$common_key")
}

# record_rejected_target <origin> <candidate> <config_reason> <discovery_reason>: after reject_target
# returned (config/discovery), append the matching per-entry skip record. CLI/default never reach
# here — reject_target exits for those origins.
record_rejected_target() {
  local origin="$1" candidate="$2" config_reason="$3" discovery_reason="$4"
  if [[ "$origin" == "config" ]]; then
    STALE_CONFIG_PATHS+=("$candidate")
    STALE_CONFIG_REASONS+=("$config_reason")
  elif [[ "$origin" == "discovery" ]]; then
    DISCOVERY_SKIP_PATHS+=("$candidate")
    DISCOVERY_SKIP_REASONS+=("$discovery_reason")
    if [[ "$discovery_reason" == *"not readable"* ]]; then
      DISCOVERY_UNREADABLE_COUNT=$((DISCOVERY_UNREADABLE_COUNT + 1))
    else
      DISCOVERY_NONREPO_COUNT=$((DISCOVERY_NONREPO_COUNT + 1))
    fi
  fi
}

# discovery_skip_reason <candidate> <fallback>: prefer an unreadable classification when the path
# cannot be entered; otherwise the caller-supplied non-repository reason.
discovery_skip_reason() {
  local candidate="$1" fallback="$2"
  if [[ ! -r "$candidate" || ! -x "$candidate" ]]; then
    printf '%s\n' "discovered path is not readable"
  else
    printf '%s\n' "$fallback"
  fi
}


TARGETS=()
TARGET_COMMON_KEYS=()
# Candidates that resolved to a different main worktree than the path reached, reported in the
# header so the substitution is never silent.
RETARGETED_FROM=()
RETARGETED_TO=()
# Stale config-sourced entries collected during argument processing; the report header has not
# printed yet, so they are emitted as per-entry UNKNOWN findings once it has.
STALE_CONFIG_PATHS=()

DISCOVERY_SKIP_PATHS=()
DISCOVERY_SKIP_REASONS=()
DISCOVERY_NONREPO_COUNT=0
DISCOVERY_UNREADABLE_COUNT=0

# Paths where core.bare=true coincides with working-tree content and/or linked worktrees. Rejecting
# these as "not a Git working tree" would omit the one administrative anomaly this collector exists
# to surface (#2602); they are reported as findings and never abort the run.
BARE_LIVE_TREE_PATHS=()
BARE_LIVE_TREE_EVIDENCE=()
BARE_LIVE_TREE_COMMON_KEYS=()

STALE_CONFIG_REASONS=()
# reject_target <origin> <message>: apply the rejection policy for a target that failed a
# prerequisite. "config" returns 1 so the caller records a stale-config entry and continues; every
# other origin stops the run. "default" is the implicit no-argument target — the same hard failure,
# plus the scope remedies, because the operator did not choose this path and the bare rejection
# gives them nothing to act on.
reject_target() {
  local origin="$1" message="$2"
  [[ "$origin" == "config" ]] && return 1
  printf 'Error: ' >&2
  display_value "$message" >&2
  printf '\n' >&2
  if [[ "$origin" == "default" ]]; then
    # A config can be consumed yet carry no scope: valid entries like maxDepth or
    # acknowledgments without any fleet.root/fleet.repo. Claiming --config was
    # omitted would send the operator to create a file that already exists, so
    # the remedy names the consumed config and directs scope INTO it.
    if [[ -n "$CONFIG_FILE" ]]; then
      cat >&2 <<EOF

No bare path, --root, or --repo was given, and the consumed config ($CONFIG_SOURCE: $CONFIG_FILE)
carries no fleet.root or fleet.repo entries, $SCOPE_FALLBACK_NOTE. Add scope to that config:

  git config --file "$CONFIG_FILE" --add fleet.root <dir>   bounded recursive repository discovery
  git config --file "$CONFIG_FILE" --add fleet.repo <dir>   one exact repository or worktree

Or pass a bare path / --root <dir> / --repo <dir> for a one-off scope.
EOF
    else
      cat >&2 <<EOF

No bare path, --root, --repo, or --config was given, $SCOPE_FALLBACK_NOTE. Give it a scope instead:

  <dir>            bare path — same as --root (drive roots like D: are allowed)
  --root <dir>     bounded recursive repository discovery
  --repo <dir>     one exact repository or worktree
  --config <file>  a Git-format fleet config listing fleet.root / fleet.repo entries

Or run /repo-fleet-hygiene:setup apply to write a config the audit picks up on its own.
EOF
    fi
  fi
  exit 2
}

if [[ "$UNRESOLVED_SCOPE" == "true" ]]; then
  reject_target default \
    "no scope resolved: no bare path, --root, or --repo, and no config-supplied fleet.root/fleet.repo"
fi

# main_worktree <dir>: the repository-of-record checkout for <dir>, or non-zero when the porcelain
# cannot answer. `git worktree list --porcelain` lists the MAIN worktree first regardless of which
# worktree it runs from (git-worktree(1)), and the collector already relies on that ordering when it
# classifies registrations. `rev-parse --show-toplevel` cannot substitute: inside a linked worktree
# it returns the LINKED root, so it can never distinguish the two.
main_worktree() {
  local dir="$1" record=""
  # -z records are NUL-delimited and command substitution would drop the NULs outright, so read the
  # first record directly off the stream.
  IFS= read -r -d '' record < <(run_git_probe -C "$dir" worktree list --porcelain -z -- 2>/dev/null)
  record="${record%$'\r'}"
  [[ "$record" == "worktree "* ]] || return 1
  record="${record#worktree }"
  [[ -n "$record" ]] || return 1
  printf '%s\n' "$record"
}

# add_target <path> <origin>: origin "cli" hard-fails on an invalid path (a typo should stop the
# run); origin "default" hard-fails with the scope remedies; origin "config" records a
# stale-config-entry and continues (the entry, not the run, is the failure unit for a tracked fleet
# config); origin "discovery" records a discovery-skip and continues (a husk under --root must not
# abort every subsequent repository). Invalid config SYNTAX still hard-fails upstream. A bare
# repository with live working-tree content or linked worktrees is classified as a finding instead
# of rejected (#2602).
add_target() {
  local candidate="$1" origin="${2:-cli}" top common common_key existing main_top main_resolved rt_known rt_existing
  local bare_live_evidence=""
  if [[ ! -d "$candidate" ]]; then
    reject_target "$origin" "repository directory not found: $candidate"
    record_rejected_target "$origin" "$candidate" \
      "configured fleet.repo path is not a directory" \
      "$(discovery_skip_reason "$candidate" "discovered path is not a directory")"
    return 0
  fi
  top="$(run_git_probe -C "$candidate" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" || {
    # Git repository that is not a work tree: classify the bare+live-tree anomaly before treating
    # the path as an ordinary rejection. Common-dir still resolves on these repositories.
    if bare_live_evidence="$(classify_bare_live_tree "$candidate")" &&
      common="$(run_git_probe -C "$candidate" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')" &&
      [[ -n "$common" ]]; then
      record_bare_live_tree "$candidate" "$bare_live_evidence" "$(path_key "$common")"
      return 0
    fi
    reject_target "$origin" "not a Git working tree: $candidate"
    record_rejected_target "$origin" "$candidate" \
      "configured fleet.repo path is not a Git working tree" \
      "$(discovery_skip_reason "$candidate" "discovered path is not a Git working tree")"
    return 0
  }
  common="$(run_git_probe -C "$candidate" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')" || {
    reject_target "$origin" "cannot resolve Git common directory: $candidate"
    record_rejected_target "$origin" "$candidate" \
      "cannot resolve the Git common directory for the configured path" \
      "$(discovery_skip_reason "$candidate" "cannot resolve the Git common directory for the discovered path")"
    return 0
  }
  # Siblings sharing one common directory are one repository, and the dedup below keeps whichever
  # arrives first -- which for recursive discovery is glob order. Retarget to the repository of
  # record BEFORE that tie-break, so a linked worktree reached first can never become the canonical
  # path every emitted handoff points at. The .git test is a cost gate only: a main worktree carries
  # .git as a DIRECTORY and a linked one as a FILE, so an ordinary sweep never pays for the probe.
  if [[ ! -d "$top/.git" ]] && main_top="$(main_worktree "$candidate")" && [[ -n "$main_top" ]]; then
    # The porcelain's first record is NOT always a checkout, and three ordinary shapes all present a
    # .git file so they reach here: a submodule reports the superproject's .git/modules/<name> admin
    # directory, --separate-git-dir reports the detached git directory, and a worktree of a bare
    # repository reports the bare repository. Adopting any of them would aim every handoff INSIDE
    # another repository's administrative directory -- the precise harm this retarget exists to
    # prevent. So re-resolve the porcelain's answer as a working tree and adopt only a genuine,
    # different checkout: bare and separate-git-dir fail this probe and are skipped, a submodule
    # resolves back to the path we already had and self-cancels, and a real linked worktree resolves
    # to its main worktree and retargets.
    main_resolved="$(run_git_probe -C "$main_top" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" || main_resolved=""
    if [[ -n "$main_resolved" && "$(path_key "$main_resolved")" != "$(path_key "$top")" ]]; then
      # Disclose the retarget. The operator supplied or discovered one path and the report is about
      # another, so substituting it silently would be the same class of defect as a header asserting
      # a scope the run's own inputs contradict. A config may name one path twice; record each
      # distinct source once so the grouped header line cannot list the same path repeatedly.
      rt_known=false
      for rt_existing in "${RETARGETED_FROM[@]:-}"; do
        [[ -n "$rt_existing" && "$rt_existing" == "$top" ]] && {
          rt_known=true
          break
        }
      done
      if [[ "$rt_known" == "false" ]]; then
        RETARGETED_FROM+=("$top")
        RETARGETED_TO+=("$main_resolved")
      fi
      top="$main_resolved"
    fi
  fi
  common_key="$(path_key "$common")"
  for existing in "${TARGET_COMMON_KEYS[@]:-}"; do
    [[ "$existing" == "$common_key" ]] && return 0
  done
  TARGETS+=("$top")
  TARGET_COMMON_KEYS+=("$common_key")
}


repo_index=0
for repo in "${REPO_ARGS[@]:-}"; do
  if [[ -n "$repo" ]]; then
    if [[ "$repo_index" -lt "$CLI_REPO_COUNT" ]]; then
      add_target "$repo" cli
    else
      add_target "$repo" config
    fi
  fi
  repo_index=$((repo_index + 1))
done

discover_repositories() {
  local dir="$1" depth="$2" child name
  [[ -d "$dir" && ! -L "$dir" ]] || return 0
  # Unreadable directories are ordinary under a volume-wide --root (e.g. Windows $RECYCLE.BIN).
  # Count and move on; never abort the walk. A .git marker that is somehow still visible is recorded
  # as a discovery skip so the header's unreadable count is not the only signal.
  if [[ ! -r "$dir" || ! -x "$dir" ]]; then
    if [[ -e "$dir/.git" ]]; then
      reject_target discovery "not a Git working tree: $dir"
      record_rejected_target discovery "$dir" "" "discovered path is not readable"
    else
      DISCOVERY_UNREADABLE_COUNT=$((DISCOVERY_UNREADABLE_COUNT + 1))
    fi
    return 0
  fi
  if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
    # Discovery origin: a .git marker that is not a usable working tree degrades per-entry.
    add_target "$dir" discovery
    return 0
  fi
  [[ "$depth" -lt "$MAX_DEPTH" ]] || return 0
  for child in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [[ -d "$child" && ! -L "$child" ]] || continue
    name="$(basename "$child")"
    case "$name" in
    . | .. | .git | node_modules | vendor | .venv) continue ;;
    *) discover_repositories "$child" $((depth + 1)) ;;
    esac
  done
}


ROOT_LABELS=()
ROOT_COUNTS=()
root_index=0
for root in "${ROOT_ARGS[@]:-}"; do
  [[ -n "$root" ]] || {
    root_index=$((root_index + 1))
    continue
  }
  if [[ ! -d "$root" ]]; then
    # Same per-entry degradation as add_target: a configured root that has since been deleted
    # is a stale-config-entry finding, not a run abort; a CLI --root typo still stops the run.
    [[ "$root_index" -ge "$CLI_ROOT_COUNT" ]] || fail "discovery root not found: $root"
    STALE_CONFIG_PATHS+=("$root")
    STALE_CONFIG_REASONS+=("configured fleet.root path is not a directory")
    root_index=$((root_index + 1))
    continue
  fi
  # discover_repositories deliberately skips symlinks (-L). Accepting a symlink root here would
  # record ROOT_LABELS and exit "0 repositories" even when the target tree is full of repos (#2599).
  # Non-readable/non-executable directories are the same false-empty class.
  if [[ -L "$root" ]]; then
    [[ "$root_index" -ge "$CLI_ROOT_COUNT" ]] || fail "discovery root is a symlink (refused): $root"
    STALE_CONFIG_PATHS+=("$root")
    STALE_CONFIG_REASONS+=("configured fleet.root path is a symlink; discovery refuses symlinked roots")
    root_index=$((root_index + 1))
    continue
  fi
  if [[ ! -r "$root" || ! -x "$root" ]]; then
    [[ "$root_index" -ge "$CLI_ROOT_COUNT" ]] || fail "discovery root is not traversable: $root"
    STALE_CONFIG_PATHS+=("$root")
    STALE_CONFIG_REASONS+=("configured fleet.root path is not readable/executable")
    root_index=$((root_index + 1))
    continue
  fi
  root_index=$((root_index + 1))
  # Per-root visibility: attribute newly discovered repositories to this root so a root that
  # contributed none is still reported. Deduplication credits a repo shared by nested/overlapping
  # roots to the first root that reaches it, keeping sum(root counts) + explicit --repo == discovered.
  root_before=${#TARGETS[@]}
  discover_repositories "$root" 0
  ROOT_LABELS+=("$root")
  ROOT_COUNTS+=($((${#TARGETS[@]} - root_before)))
done

# An all-stale config (every entry deleted since the last run) must still produce a report whose
# stale-config-entry findings tell the user what to remediate. A discovery root that exists but
# contains no repositories is a valid empty audit ("0 repositories found"), not an error — the
# operator named that tree (#2599). Hard-fail only when nothing was ever in scope: no roots walked,
# no repos, and no stale/skip/bare-live entry to report.
if [[ ${#TARGETS[@]} -eq 0 && ${#STALE_CONFIG_PATHS[@]} -eq 0 && ${#DISCOVERY_SKIP_PATHS[@]} -eq 0 && ${#BARE_LIVE_TREE_PATHS[@]} -eq 0 && ${#ROOT_LABELS[@]} -eq 0 ]]; then
  fail "no Git working trees found in the requested scope"
fi

# Resolve the worktree convention root once for the fleet. Never invent a default: unset stays
# unset and the report describes placement without asserting conformance.
resolve_configured_worktree_root || true

GH_READY=false
if command -v gh >/dev/null 2>&1 && run_bounded_gh auth status --hostname github.com >/dev/null 2>&1; then
  GH_READY=true
fi

# Which gh account produced the GitHub evidence changes how UNKNOWN findings read (a dozen HTTP
# 404s under
# the wrong login is expected, under the right one it is a real signal), so the header names it.
# Best-effort: any probe failure keeps the plain header line. This is the cheap subset of the
# tracked per-domain-gh-auth request (multiple accounts per host) — see the plugin backlog.
GH_ACCOUNT=""
if [[ "$GH_READY" == "true" ]]; then
  GH_ACCOUNT="$(run_bounded_gh api user --hostname github.com --method GET --template '{{.login}}' 2>/dev/null | tr -d '\r\n')" || GH_ACCOUNT=""
fi

select_remote() {
  local repo="$1" remotes count
  if run_git_probe -C "$repo" remote get-url origin >/dev/null 2>&1; then
    SELECTED_REMOTE="origin"
  else
    remotes="$(run_git_probe -C "$repo" remote 2>/dev/null | tr -d '\r')"
    count="$(printf '%s\n' "$remotes" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$count" == "1" ]]; then
      SELECTED_REMOTE="$(printf '%s\n' "$remotes" | sed '/^$/d')"
    else
      SELECTED_REMOTE=""
      return 1
    fi
  fi
  SELECTED_URL="$(run_git_probe -C "$repo" remote get-url "$SELECTED_REMOTE" 2>/dev/null | tr -d '\r')" || return 1
}

parse_github_url() {
  local url="$1" rest authority path host
  PARSED_KEY=""
  PARSED_SLUG=""
  if [[ "$url" == *://* ]]; then
    rest="${url#*://}"
    authority="${rest%%/*}"
    path="${rest#*/}"
    host="${authority##*@}"
    host="${host%%:*}"
  elif [[ "$url" =~ ^[^@]+@([^:]+):(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  else
    return 1
  fi
  host="$(lower "$host")"
  path="${path#/}"
  path="${path%/}"
  path="${path%.git}"
  [[ "$host" == "github.com" && "$path" =~ ^[^/]+/[^/]+$ ]] || return 1
  PARSED_SLUG="$path"
  PARSED_KEY="github.com/$(lower "$path")"
}

lookup_override() {
  local key="$1" i configured entry name value
  OVERRIDE_VALUE=""
  for ((i = 0; i < ${#OVERRIDE_KEYS[@]}; i++)); do
    if [[ "${OVERRIDE_KEYS[$i]}" == "$key" ]]; then
      OVERRIDE_VALUE="${OVERRIDE_PATHS[$i]}"
      return 0
    fi
  done
  if [[ -n "$CONFIG_FILE" ]]; then
    configured="$(run_git_probe config --file "$CONFIG_FILE" --get "canonical.$key.path" 2>/dev/null || true)"
    if [[ -z "$configured" ]]; then
      # git config subsection names are case-sensitive, so a config section
      # written with GitHub's display casing (the setup skill allows
      # case-preserving owner/name) never matches the lowercase key above --
      # regardless of what casing the discovered remote itself happens to
      # use, which need not match the config's casing either. Scan every
      # canonical.*.path entry and compare case-insensitively.
      while IFS= read -r -d '' entry; do
        name="${entry%%$'\n'*}"
        value="${entry#*$'\n'}"
        name="${name#canonical.}"
        name="${name%.path}"
        if [[ "$(lower "$name")" == "$key" ]]; then
          configured="$value"
          break
        fi
      done < <(run_git_probe config --file "$CONFIG_FILE" --get-regexp -z \
        '^canonical\.[^[:cntrl:]]+\.path$' 2>/dev/null || true)
    fi
    if [[ -n "$configured" ]]; then
      OVERRIDE_VALUE="$(resolve_input_path "$configured" "$CONFIG_DIR")"
      return 0
    fi
  fi
  return 1
}

github_identity() {
  local slug="$1" result error
  GH_ID_STATUS="UNKNOWN"
  GH_ID_ACTUAL=""
  GH_ID_DEFAULT=""
  GH_ID_REASON="GitHub CLI unavailable or unauthenticated"
  $GH_READY || return 1
  if ! result="$(run_bounded_gh api "repos/$slug" --hostname github.com --method GET \
    --template '{{printf "%s\t%s" .full_name .default_branch}}' 2>&1)"; then
    if [[ "$result" == *"HTTP 404"* ]]; then
      error="HTTP 404 (not found or inaccessible)"
    elif [[ "$result" == *"HTTP 403"* ]]; then
      error="HTTP 403 (forbidden or inaccessible)"
    else
      error="GitHub API request failed"
    fi
    GH_ID_REASON="$error"
    return 1
  fi
  IFS=$'\t' read -r GH_ID_ACTUAL GH_ID_DEFAULT <<<"$result"
  [[ -n "$GH_ID_ACTUAL" ]] || {
    GH_ID_REASON="GitHub API returned no canonical repository identity"
    return 1
  }
  GH_ID_STATUS="OK"
  GH_ID_REASON=""
  return 0
}

FINDINGS_HIGH=0
FINDINGS_MEDIUM=0
FINDINGS_LOW=0
FINDINGS_UNKNOWN=0
FINDINGS_ACKED=0
REPOS_AUDITED=0
# Per-repo GitHub identity observations for the cross-repo duplicate-checkout pass after the loop.
IDENT_KEYS=()
IDENT_PATHS=()
# Per-repository finding tally, reset by analyze_repo: a section that ends with zero findings
# emits an explicit "Findings: none" marker so clean output is distinguishable from truncation.
REPO_FINDING_COUNT=0

# Buffered findings for rollup / action-plan rendering (#2608, #2609).
F_CONF=()
F_KIND=()
F_TARGET=()
F_EVIDENCE=()
F_DISP=()
F_HANDOFF=()
F_REPO_IDX=()
R_DISCOVERED=()
R_CANONICAL=()
R_REMOTE=()
R_RESOLUTION=()
R_COUNTED=()
CURRENT_REPO_IDX=-1

json_escape() {
  # Minimal JSON string escape for path/report text. Iterate bytes under LC_ALL=C so
  # ${#s}/${s:i:1} are stable, but only \u00XX-escape ASCII controls. Bytes >= 0x80 pass
  # through unchanged so complete UTF-8 code points stay intact (byte-wise \u00C3\u00A9
  # style escapes would mojibake non-ASCII repository paths such as répô).
  local s="$1" out="" i c hex o
  local LC_ALL=C
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
    '"') out+='\"' ;;
    $'\\') out+=$'\\' ;;
    $'\b') out+='\b' ;; # portability-ok: bash ANSI-C quoted backspace byte for JSON escape, not GNU grep \\b word-boundary
    $'\f') out+='\f' ;;
    $'\n') out+='\n' ;;
    $'\r') out+='\r' ;;
    $'\t') out+='\t' ;;
    *)
      printf -v o '%d' "'$c"
      if ((o < 32)); then
        printf -v hex '%02X' "$o"
        out+="\\u00${hex}"
      else
        out+="$c"
      fi
      ;;
    esac
  done
  printf '%s' "$out"
}

begin_repo_record() {
  local discovered="$1" canonical="$2" remote="$3" resolution="$4"
  CURRENT_REPO_IDX=${#R_DISCOVERED[@]}
  R_DISCOVERED+=("$discovered")
  R_CANONICAL+=("$canonical")
  R_REMOTE+=("$remote")
  R_RESOLUTION+=("$resolution")
  R_COUNTED+=("false")
  REPO_FINDING_COUNT=0
}

mark_repo_counted() {
  [[ "$CURRENT_REPO_IDX" -ge 0 ]] || return 0
  R_COUNTED[CURRENT_REPO_IDX]="true"
}

update_repo_canonical() {
  local canonical="$1"
  [[ "$CURRENT_REPO_IDX" -ge 0 ]] || return 0
  R_CANONICAL[CURRENT_REPO_IDX]="$canonical"
}

emit_finding() {
  local confidence="$1" kind="$2" target="$3" evidence="$4" disposition="$5" handoff="$6"
  REPO_FINDING_COUNT=$((REPO_FINDING_COUNT + 1))
  case "$confidence" in
  HIGH) FINDINGS_HIGH=$((FINDINGS_HIGH + 1)) ;;
  MEDIUM) FINDINGS_MEDIUM=$((FINDINGS_MEDIUM + 1)) ;;
  LOW) FINDINGS_LOW=$((FINDINGS_LOW + 1)) ;;
  ACKNOWLEDGED) FINDINGS_ACKED=$((FINDINGS_ACKED + 1)) ;;
  *) FINDINGS_UNKNOWN=$((FINDINGS_UNKNOWN + 1)) ;;
  esac
  F_CONF+=("$confidence")
  F_KIND+=("$kind")
  F_TARGET+=("$target")
  F_EVIDENCE+=("$evidence")
  F_DISP+=("$disposition")
  F_HANDOFF+=("$handoff")
  F_REPO_IDX+=("$CURRENT_REPO_IDX")
}

print_finding_block() {
  local confidence="$1" kind="$2" target="$3" evidence="$4" disposition="$5" handoff="$6"
  print_field Finding "$kind"
  print_field Confidence "$confidence"
  print_field Target "$target"
  print_field Evidence "$evidence"
  print_field Disposition "$disposition"
  print_field Handoff "$handoff"
  printf '%s\n' '---'
}

# Actionable fleet-batch handoff kinds. Manual-review and informational findings stay in the
# rollup but do not produce a skill invocation in the action plan.
branch_action_kind() {
  [[ "$1" == "merged-local-branch" ]]
}

worktree_action_kind() {
  case "$1" in
  merged-worktree | prunable-worktree | missing-worktree | reclaimable-worktree) return 0 ;;
  *) return 1 ;;
  esac
}

repo_verdict() {
  # Candidate counts follow actionable plan kinds (branch_action_kind / worktree_action_kind),
  # not mere HIGH/MEDIUM confidence. Manual-review findings such as locked-worktree or
  # merged-pr-tip-drift stay visible in kind counts but do not inflate "N candidates" when the
  # action plan correctly lists "Actions: none".
  local repo_idx="$1"
  local i conf kind target
  local unknown=0
  local -a cand_targets=()
  local seen t
  for ((i = 0; i < ${#F_KIND[@]}; i++)); do
    [[ "${F_REPO_IDX[$i]}" == "$repo_idx" ]] || continue
    conf="${F_CONF[$i]}"
    kind="${F_KIND[$i]}"
    target="${F_TARGET[$i]}"
    if [[ "$conf" == "UNKNOWN" ]]; then
      unknown=$((unknown + 1))
    elif branch_action_kind "$kind" || worktree_action_kind "$kind"; then
      seen=false
      for t in "${cand_targets[@]:-}"; do
        [[ "$t" == "$target" ]] && {
          seen=true
          break
        }
      done
      [[ "$seen" == "true" ]] || cand_targets+=("$target")
    fi
  done
  if [[ "$unknown" -gt 0 ]]; then
    printf 'BLOCKED (evidence gap)'
  elif [[ ${#cand_targets[@]} -gt 0 ]]; then
    printf '%s candidates' "${#cand_targets[@]}"
  else
    printf 'CLEAN'
  fi
}

repo_kind_counts_text() {
  local repo_idx="$1"
  local i kind k
  local -a keys=()
  local -a counts=()
  local found idx
  for ((i = 0; i < ${#F_KIND[@]}; i++)); do
    [[ "${F_REPO_IDX[$i]}" == "$repo_idx" ]] || continue
    kind="${F_KIND[$i]}"
    found=false
    idx=0
    for ((k = 0; k < ${#keys[@]}; k++)); do
      if [[ "${keys[$k]}" == "$kind" ]]; then
        found=true
        idx=$k
        break
      fi
    done
    if [[ "$found" == "true" ]]; then
      counts[idx]=$((counts[idx] + 1))
    else
      keys+=("$kind")
      counts+=(1)
    fi
  done
  if [[ ${#keys[@]} -eq 0 ]]; then
    printf '%s' '—'
    return 0
  fi
  local first=true kind_sorted
  # Stable alphabetical kind order keeps the rollup table diffable.
  while IFS= read -r kind_sorted; do
    [[ -n "$kind_sorted" ]] || continue
    for ((k = 0; k < ${#keys[@]}; k++)); do
      [[ "${keys[$k]}" == "$kind_sorted" ]] || continue
      if [[ "$first" == "true" ]]; then
        first=false
      else
        printf ', '
      fi
      printf '%s=%s' "$kind_sorted" "${counts[$k]}"
      break
    done
  done < <(printf '%s\n' "${keys[@]}" | LC_ALL=C sort)
}

print_collapsed_target_detail() {
  local repo_idx="$1"
  local i target kind conf t j seen
  local -a targets=()
  for ((i = 0; i < ${#F_KIND[@]}; i++)); do
    [[ "${F_REPO_IDX[$i]}" == "$repo_idx" ]] || continue
    target="${F_TARGET[$i]}"
    seen=false
    for t in "${targets[@]:-}"; do
      [[ "$t" == "$target" ]] && {
        seen=true
        break
      }
    done
    [[ "$seen" == "true" ]] || targets+=("$target")
  done
  if [[ ${#targets[@]} -eq 0 ]]; then
    printf 'Findings: none\n'
    printf '%s\n' '---'
    return 0
  fi
  local first_kinds kinds_line
  for t in "${targets[@]}"; do
    print_field Target "$t"
    kinds_line=""
    first_kinds=true
    for ((j = 0; j < ${#F_KIND[@]}; j++)); do
      [[ "${F_REPO_IDX[$j]}" == "$repo_idx" && "${F_TARGET[$j]}" == "$t" ]] || continue
      kind="${F_KIND[$j]}"
      conf="${F_CONF[$j]}"
      if [[ "$first_kinds" == "true" ]]; then
        first_kinds=false
        kinds_line="$kind ($conf)"
      else
        kinds_line+=", $kind ($conf)"
      fi
    done
    print_field Findings "$kinds_line"
    # One Finding/Confidence pair per kind under the shared Target keeps legacy report greps
    # working while still collapsing to a single target entry (#2608).
    for ((j = 0; j < ${#F_KIND[@]}; j++)); do
      [[ "${F_REPO_IDX[$j]}" == "$repo_idx" && "${F_TARGET[$j]}" == "$t" ]] || continue
      print_field Finding "${F_KIND[$j]}"
      print_field Confidence "${F_CONF[$j]}"
      print_field Evidence "${F_EVIDENCE[$j]}"
      print_field Disposition "${F_DISP[$j]}"
      print_field Handoff "${F_HANDOFF[$j]}"
    done
    printf '%s\n' '---'
  done
}


analyze_repo() {
  local discovered="$1" discovered_remote="" discovered_url="" discovered_key="" discovered_slug=""
  local canonical="$discovered" canonical_remote="" canonical_url="" canonical_key="" canonical_slug=""
  local override_source="git-native" expected_actual="" expected_default="" expected_reason=""
  local canonical_actual="" canonical_reason="" github_repo="" default_branch="" current_branch=""
  local expected_common="" actual_common="" branch tip pr_match pr_any
  local pr_num pr_branch pr_oid pr_merged pr_url attached wt_index branch_index is_main ancestry_status
  local ref_record branch_status=1 branch_inventory_valid=true
  local remote_ref_record remote_branch_status=1 remote_branch_short
  local repo_pr_rows="" repo_pr_available=false protected=false protection_reason=""
  local remote_inventory_failed=false
  local gql_owner="" gql_name="" gql_owner_esc="" gql_name_esc="" gql_query="" gql_page_rows=""
  local gql_page_start=0 gql_page_end=0 gql_alias_i=0 gql_bi=0 gql_branch_esc=""
  local -a WT_PATHS=() WT_BRANCHES=() WT_PRUNABLE=() WT_LOCKED=()
  local -a BRANCH_NAMES=() BRANCH_TIPS=() REMOTE_BRANCH_NAMES=() REMOTE_BRANCH_TIPS=()
  local -a GQL_BRANCHES=()
  local remote_tip push_state ri
  local repo_wt_linked=0 repo_wt_conforming=0 repo_wt_nonconforming=0 repo_wt_tool_owned=0
  local wt_owner="" wt_repo="" expected_wt_path="" expected_dirname="" placement_paths=""
  local origin_url="" wt_basename="" layout_prefix="" creation_slug="" informational_expected=""
  REPO_FINDING_COUNT=0

  select_remote "$discovered" && {
    discovered_remote="$SELECTED_REMOTE"
    discovered_url="$SELECTED_URL"
    if parse_github_url "$discovered_url"; then
      discovered_key="$PARSED_KEY"
      discovered_slug="$PARSED_SLUG"
    fi
  }

  if [[ -n "$discovered_key" ]] && lookup_override "$discovered_key"; then
    [[ -d "$OVERRIDE_VALUE" ]] || {
      begin_repo_record "$discovered" "unresolved" "${discovered_key:-unknown}" "$override_source"
      emit_finding UNKNOWN canonical-override-invalid "$OVERRIDE_VALUE" \
        "override for $discovered_key is not a directory" "Stop for this repository" "Correct the override and rerun"
      return
    }
    canonical="$(run_git_probe -C "$OVERRIDE_VALUE" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" || {
      begin_repo_record "$discovered" "unresolved" "${discovered_key:-unknown}" "$override_source"
      emit_finding UNKNOWN canonical-override-invalid "$OVERRIDE_VALUE" \
        "override for $discovered_key is not a Git working tree" "Stop for this repository" "Correct the override and rerun"
      return
    }
    override_source="configured"
  fi

  select_remote "$canonical" && {
    canonical_remote="$SELECTED_REMOTE"
    canonical_url="$SELECTED_URL"
    if parse_github_url "$canonical_url"; then
      canonical_key="$PARSED_KEY"
      canonical_slug="$PARSED_SLUG"
    fi
  }

  begin_repo_record "$discovered" "$canonical" "${discovered_key:-unknown}" "$override_source"


  if [[ -z "$discovered_key" ]]; then
    emit_finding UNKNOWN github-identity-unavailable "$discovered" \
      "remote is missing, ambiguous, credential-only, or not a github.com owner/repository URL" \
      "Local Git/worktree evidence only" "Configure/select an unambiguous GitHub remote and rerun"
  else
    github_identity "$discovered_slug"
    expected_actual="$GH_ID_ACTUAL"
    expected_default="$GH_ID_DEFAULT"
    expected_reason="$GH_ID_REASON"
    if [[ "$GH_ID_STATUS" == "OK" ]]; then
      # Resolved identity is the PR/query authority even when the configured remote is stale.
      # Do not return after github-remote-moved: local branch/worktree facts do not depend on the
      # remote URL matching full_name, and a silent stop here would look identical to a clean repo.
      github_repo="$expected_actual"
      if [[ "$(lower "$expected_actual")" != "$(lower "$discovered_slug")" ]]; then
        emit_finding HIGH github-remote-moved "$discovered_remote ($discovered_slug -> $expected_actual)" \
          "GitHub REST resolved the configured remote identity to canonical full_name $expected_actual; branch and worktree analysis continues against that resolved identity" \
          "Human-reviewed remote update; local classification is not deferred" \
          "Review git remote set-url for $discovered_remote in $discovered"
      fi
    elif [[ "$expected_reason" == *"HTTP 404"* || "$expected_reason" == *"HTTP 403"* ]] && is_acked "$discovered_key"; then
      # Acked demotion applies ONLY to the foreseeable-inaccessible statuses;
      # any other failure (network, timeout, malformed response) keeps full
      # UNKNOWN prominence with its real reason even for an acked identity.
      emit_finding ACKNOWLEDGED github-identity-unavailable "$discovered_key" \
        "$expected_reason; acknowledged known-inaccessible via fleet.ackUnavailable" \
        "Acknowledged; no GitHub evidence combined" \
        "Remove the fleet.ackUnavailable entry to restore UNKNOWN prominence"
    else
      emit_finding UNKNOWN github-identity-unavailable "$discovered_key" "$expected_reason" \
        "Do not infer moved, deleted, or clean" "Restore GitHub access/authentication and rerun"
    fi
  fi

  # Duplicate-checkout keys use the GitHub-canonicalized identity when resolution succeeded, so an
  # old checkout whose remote still says old/repo pairs with a fresh clone of new/repo; the parsed
  # remote is only the fallback when canonical resolution is unavailable.
  if [[ -n "$github_repo" ]]; then
    IDENT_KEYS+=("github.com/$(lower "$github_repo")")
    IDENT_PATHS+=("$discovered")
  elif [[ -n "$discovered_key" ]]; then
    IDENT_KEYS+=("$(lower "$discovered_key")")
    IDENT_PATHS+=("$discovered")
  fi

  if [[ "$canonical" != "$discovered" ]]; then
    if [[ -z "$canonical_key" ]]; then
      emit_finding UNKNOWN canonical-identity-unverified "$canonical" \
        "canonical override has a missing, ambiguous, credential-only, or non-github.com remote" \
        "Stop; do not combine canonical local state with discovered GitHub evidence" \
        "Correct the canonical override/remote and rerun"
      return
    fi
    if [[ "$(lower "$canonical_key")" != "$(lower "$discovered_key")" ]]; then
      github_identity "$canonical_slug"
      canonical_actual="$GH_ID_ACTUAL"
      canonical_reason="$GH_ID_REASON"
      if [[ -z "$expected_actual" || -z "$canonical_actual" ]]; then
        emit_finding UNKNOWN canonical-identity-unverified "$canonical" \
          "different remote identities could not both be verified: ${canonical_reason:-discovered identity unavailable}" \
          "Stop; do not combine local/GitHub evidence" "Restore GitHub access or correct the override"
        return
      fi
      if [[ "$(lower "$expected_actual")" != "$(lower "$canonical_actual")" ]]; then
        emit_finding UNKNOWN canonical-identity-conflict "$canonical" \
          "discovered checkout resolves to $expected_actual but override resolves to $canonical_actual" \
          "Stop; do not combine local/GitHub evidence" "Correct the canonical override and rerun"
        return
      fi
    fi
  fi

  expected_common="$(run_git_probe -C "$canonical" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
  [[ -n "$expected_common" ]] || {
    emit_finding UNKNOWN git-common-dir-unavailable "$canonical" "git could not resolve the canonical common directory" \
      "Stop for this repository" "Repair/replace the canonical override, then rerun"
    return
  }

  # Resolved through git rather than taken from discovery so that it and the porcelain's worktree
  # paths come from ONE source. A filesystem-derived path and a git-emitted one differ by spelling
  # on Windows (/d/repos/x vs D:/repos/x), and path_key normalizes separators and case but not the
  # drive form — a containment test across those two forms silently never matches.
  # A BARE canonical has no working tree, so `--show-toplevel` fails there by
  # design and there is nothing for a worktree to be nested inside — a legitimate
  # skip, not an unknown. Any OTHER failure is an unknown, and it gets a finding
  # rather than a silent skip: every sibling probe in this function reports when
  # it cannot answer, and a placement check that quietly did not run reads
  # identically to one that ran and found nothing.
  local canonical_top canonical_bare="false"
  [[ "$(run_git_probe -C "$canonical" rev-parse --is-bare-repository 2>/dev/null | tr -d '\r')" == "true" ]] &&
    canonical_bare="true"
  canonical_top="$(run_git_probe -C "$canonical" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  if [[ -z "$canonical_top" && "$canonical_bare" != "true" ]]; then
    emit_finding UNKNOWN worktree-placement-unverifiable "$canonical" \
      "git rev-parse --show-toplevel gave no working-tree root for a non-bare canonical checkout" \
      "Do not infer that this repository's worktrees are correctly placed" \
      "Inspect the canonical checkout, then rerun"
  fi

  # Parse the stable NUL-delimited porcelain format. Only these registrations are worktree evidence.
  local wt_path="" wt_branch="" wt_prunable="false" wt_locked="false" field worktree_status=1
  local wt_prefix status_handoff_targets="" status_handoff_count=0
  while IFS= read -r -d '' field; do
    if [[ -z "$field" ]]; then
      if [[ -n "$wt_path" ]]; then
        WT_PATHS+=("$wt_path")
        WT_BRANCHES+=("$wt_branch")
        WT_PRUNABLE+=("$wt_prunable")
        WT_LOCKED+=("$wt_locked")
      fi
      wt_path="" wt_branch="" wt_prunable="false" wt_locked="false"
      continue
    fi
    case "$field" in
    __repo_fleet_status__\ *) worktree_status="${field#__repo_fleet_status__ }" ;;
    worktree\ *) wt_path="${field#worktree }" ;;
    branch\ refs/heads/*) wt_branch="${field#branch refs/heads/}" ;;
    prunable*) wt_prunable="true" ;;
    locked*) wt_locked="true" ;;
    *) ;;
    esac
  done < <(
    run_git_probe -C "$canonical" worktree list --porcelain -z -- 2>/dev/null
    printf '\0__repo_fleet_status__ %s\0' "$?"
  )
  if [[ "$worktree_status" != "0" ]]; then
    emit_finding UNKNOWN worktree-inventory-unavailable "$canonical" \
      "git worktree list --porcelain -z failed" \
      "Stop local branch/worktree classification for this repository" \
      "Repair Git metadata or correct the canonical checkout, then rerun"
    return
  fi
  if [[ -n "$wt_path" ]]; then
    WT_PATHS+=("$wt_path")
    WT_BRANCHES+=("$wt_branch")
    WT_PRUNABLE+=("$wt_prunable")
    WT_LOCKED+=("$wt_locked")
  fi

  for ((wt_index = 0; wt_index < ${#WT_PATHS[@]}; wt_index++)); do
    wt_path="${WT_PATHS[$wt_index]}"
    wt_branch="${WT_BRANCHES[$wt_index]}"
    is_main=false
    [[ "$wt_index" -eq 0 ]] && is_main=true
    if [[ "${WT_LOCKED[$wt_index]}" == "true" && "$is_main" == "false" ]]; then
      emit_finding HIGH locked-worktree "$wt_path${wt_branch:+ ($wt_branch)}" \
        "git worktree porcelain marks the registration locked" \
        "Manual review before any cleanup handoff" \
        "Inspect the lock reason with git worktree list --verbose in $canonical"
    fi
    if [[ ! -d "$wt_path" ]]; then
      if [[ "${WT_PRUNABLE[$wt_index]}" == "true" ]]; then
        emit_finding HIGH prunable-worktree "$wt_path${wt_branch:+ ($wt_branch)}" \
          "git worktree porcelain marks the missing registration prunable" \
          "Candidate dry-run handoff" "Run /source-control:worktree cleanup --dry-run in $canonical"
      else
        emit_finding MEDIUM missing-worktree "$wt_path${wt_branch:+ ($wt_branch)}" \
          "registered worktree path is absent but not currently marked prunable" \
          "Manual review" "Run /source-control:worktree cleanup --dry-run in $canonical"
      fi
      continue
    fi
    # A registered path that is not a work-tree ROOT still answers `git -C` — with the CONTAINING
    # repository's state rather than its own, at exit 0, which is indistinguishable from a healthy
    # clean worktree. `--show-prefix` is the discriminator, and it needs no path arithmetic: empty
    # exactly at a work-tree root, non-empty anywhere below one. `--is-inside-work-tree` cannot
    # answer it, because a leftover directory inside a repository genuinely IS inside that work
    # tree. Both branches stop here: every probe below would describe the wrong repository.
    if ! wt_prefix="$(run_git_probe -C "$wt_path" rev-parse --show-prefix 2>/dev/null | tr -d '\r')"; then
      emit_finding UNKNOWN worktree-root-unverifiable "$wt_path${wt_branch:+ ($wt_branch)}" \
        "git rev-parse --show-prefix failed at the registered path" \
        "Do not read any git -C probe of this path as the worktree's own state" \
        "Inspect the registered path and Git metadata, then rerun"
      continue
    elif [[ -n "$wt_prefix" ]]; then
      emit_finding HIGH worktree-not-a-root "$wt_path${wt_branch:+ ($wt_branch)}" \
        "git rev-parse --show-prefix returns $wt_prefix, so the registered path is a subdirectory of a work tree rather than its root; probing it reports the containing repository's state at exit 0" \
        "Manual review; never infer this worktree is clean from a git -C probe of the path" \
        "Run /source-control:worktree cleanup --dry-run in $canonical"
      continue
    fi
    # Placement drift. A worktree inside its own repository's working tree is what makes a read
    # matching a path-scoped rule's glob also load the parent checkout's copy of that rule; the
    # sanctioned placement is an external root outside every repository.
    if [[ "$is_main" == "false" && -n "$canonical_top" ]] &&
      [[ "$(path_key "$wt_path")" == "$(path_key "$canonical_top")"/* ]]; then
      emit_finding MEDIUM worktree-nested-in-repository "$wt_path${wt_branch:+ ($wt_branch)}" \
        "registered worktree root is inside the canonical checkout's own working tree ($canonical_top)" \
        "Manual placement decision; never auto-move or auto-remove" \
        "Recreate it at an external root with /source-control:worktree create, then remove this one"
    fi
    # Conformance against the configured worktree root (#2606). Main checkout is never expected
    # under the root. Tool-owned (Codex/Cursor) is distinguished from misplaced; when no root is
    # configured, record placement only — never invent a convention.
    if [[ "$is_main" == "false" ]]; then
      repo_wt_linked=$((repo_wt_linked + 1))
      FLEET_WT_LINKED=$((FLEET_WT_LINKED + 1))
      if [[ -n "$placement_paths" ]]; then
        placement_paths+=", "
      fi
      placement_paths+="$wt_path${wt_branch:+ ($wt_branch)}"
      # Match /source-control:worktree create dirname rules (#2606 review):
      # owner/repo come from `origin` only; without origin, owner is omitted and
      # repo is the checkout basename. Never use select_remote's sole-GitHub
      # fallback (e.g. upstream) — that falsely flags creator-compliant trees.
      wt_owner=""
      wt_repo=""
      origin_url=""
      if origin_url="$(run_git_probe -C "$canonical" remote get-url origin 2>/dev/null | tr -d '\r')" &&
        [[ -n "$origin_url" ]]; then
        if parse_github_url "$origin_url"; then
          wt_owner="${PARSED_SLUG%%/*}"
          wt_repo="${PARSED_SLUG#*/}"
        fi
      fi
      if [[ -z "$wt_repo" ]]; then
        wt_repo="${canonical##*/}"
        wt_owner=""
      fi
      # Creation-time path identity: when the dirname already matches the create
      # pattern, recover that slug. Porcelain's current branch is mutable
      # (rename/detach) and must not redefine expected layout for comparison.
      wt_basename="${wt_path##*/}"
      creation_slug=""
      if [[ -n "$wt_owner" ]]; then
        layout_prefix="${wt_owner}-${wt_repo}-"
      else
        layout_prefix="${wt_repo}-"
      fi
      if [[ -n "$layout_prefix" && "$wt_basename" == "$layout_prefix"* && "$wt_basename" != "$layout_prefix" ]]; then
        creation_slug="${wt_basename#"$layout_prefix"}"
      fi
      if [[ -n "$creation_slug" ]]; then
        expected_dirname="${layout_prefix}${creation_slug}"
      else
        # Non-create-shaped names: recreate guidance uses the same slug rules as create.
        expected_dirname="$(expected_worktree_dirname "$wt_owner" "$wt_repo" "$wt_branch")"
      fi
      if [[ -n "$CONFIGURED_WORKTREE_ROOT" ]]; then
        expected_wt_path="${CONFIGURED_WORKTREE_ROOT%/}/$expected_dirname"
        if is_tool_owned_worktree "$wt_path"; then
          repo_wt_tool_owned=$((repo_wt_tool_owned + 1))
          FLEET_WT_TOOL_OWNED=$((FLEET_WT_TOOL_OWNED + 1))
          informational_expected="${CONFIGURED_WORKTREE_ROOT%/}/$(expected_worktree_dirname "$wt_owner" "$wt_repo" "$wt_branch")"
          emit_finding LOW worktree-tool-owned "$wt_path${wt_branch:+ ($wt_branch)}" \
            "linked worktree sits in a tool-owned location (Codex ~/.codex/worktrees or Cursor ~/.cursor/worktrees); exempt from configured-root conformance; expected fleet location would be $informational_expected (root from $CONFIGURED_WORKTREE_ROOT_SOURCE, origin $CONFIGURED_WORKTREE_ROOT_ORIGIN)" \
            "Informational; tool-managed lifecycle, not a misplaced-fleet finding" \
            "Leave to the owning tool, or recreate at the configured root with /source-control:worktree create if migrating"
        elif under_configured_root "$wt_path" &&
          [[ "$(path_key "$(physical_path "$wt_path")")" == "$(path_key "$(physical_path "$expected_wt_path")")" ]]; then
          repo_wt_conforming=$((repo_wt_conforming + 1))
          FLEET_WT_CONFORMING=$((FLEET_WT_CONFORMING + 1))
        elif under_configured_root "$wt_path"; then
          repo_wt_nonconforming=$((repo_wt_nonconforming + 1))
          FLEET_WT_NONCONFORMING=$((FLEET_WT_NONCONFORMING + 1))
          emit_finding MEDIUM worktree-wrong-layout "$wt_path${wt_branch:+ ($wt_branch)}" \
            "linked worktree is under the configured root ($CONFIGURED_WORKTREE_ROOT) but not at the expected layout path $expected_wt_path (<owner>-<repo>-<slug> or <repo>-<slug>); root from $CONFIGURED_WORKTREE_ROOT_SOURCE, origin $CONFIGURED_WORKTREE_ROOT_ORIGIN" \
            "Manual placement decision; never auto-move" \
            "Recreate at $expected_wt_path with /source-control:worktree create, then remove this one"
        else
          repo_wt_nonconforming=$((repo_wt_nonconforming + 1))
          FLEET_WT_NONCONFORMING=$((FLEET_WT_NONCONFORMING + 1))
          emit_finding MEDIUM worktree-outside-configured-root "$wt_path${wt_branch:+ ($wt_branch)}" \
            "linked worktree is outside the configured worktree root $CONFIGURED_WORKTREE_ROOT; expected location $expected_wt_path; root from $CONFIGURED_WORKTREE_ROOT_SOURCE, origin $CONFIGURED_WORKTREE_ROOT_ORIGIN" \
            "Manual placement decision; never auto-move" \
            "Recreate at $expected_wt_path with /source-control:worktree create, then remove this one"
        fi
      fi
    fi
    if ! actual_common="$(run_git_probe -C "$wt_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')" ||
      [[ -z "$actual_common" ]]; then
      emit_finding UNKNOWN worktree-common-dir-unavailable "$wt_path${wt_branch:+ ($wt_branch)}" \
        "git could not resolve the registered worktree common directory" \
        "Do not infer an administrative mismatch" \
        "Inspect the registered path and Git metadata, then rerun"
    elif [[ "$(path_key "$actual_common")" != "$(path_key "$expected_common")" ]]; then
      emit_finding HIGH worktree-admin-mismatch "$wt_path${wt_branch:+ ($wt_branch)}" \
        "expected common dir $expected_common; actual $actual_common" \
        "Manual administrative-directory decision; never auto-repair/remove" \
        "Inspect both repositories; consider git worktree repair only after choosing the authority"
    elif [[ "$is_main" == "false" && "${WT_LOCKED[$wt_index]}" != "true" ]]; then
      # Disposability (stranded / unknown / safe) is owned by /source-control:worktree status.
      # Do not emit a weaker porcelain-clean reclaimability verdict here (#2605 / #2597).
      status_handoff_count=$((status_handoff_count + 1))
      if [[ -n "$status_handoff_targets" ]]; then
        status_handoff_targets+=", "
      fi
      status_handoff_targets+="$wt_path${wt_branch:+ ($wt_branch)}"
    fi
  done
  if ((status_handoff_count > 0)); then
    emit_finding MEDIUM worktree-status-handoff "$canonical ($status_handoff_count linked)" \
      "linked unlocked worktrees with reliable admin named for stranded-work classification owned by /source-control:worktree status: $status_handoff_targets; this collector emits no git-status-based disposability substitute" \
      "Delegate; stranded and unknown outrank stale; never treat porcelain emptiness as reclaimable" \
      "Run /source-control:worktree status in $canonical; use /source-control:worktree cleanup --dry-run only after Work is safe"
  fi

  # Per-repository conformance / placement rollup (#2606). Always state counts when linked
  # worktrees were classified; with a configured root this is the conformance verdict, without it
  # placement only.
  if ((repo_wt_linked > 0)); then
    if [[ -n "$CONFIGURED_WORKTREE_ROOT" ]]; then
      print_field 'Worktree conformance' \
        "$repo_wt_conforming conforming, $repo_wt_nonconforming outside/wrong-layout, $repo_wt_tool_owned tool-owned of $repo_wt_linked linked (root $CONFIGURED_WORKTREE_ROOT)"
      # Emit even when every linked worktree conforms: the fleet headline this check exists for.
      emit_finding LOW worktree-root-conformance "$canonical" \
        "$repo_wt_nonconforming of $repo_wt_linked linked worktrees are outside the configured root or wrong layout ($repo_wt_conforming conforming, $repo_wt_tool_owned tool-owned); root $CONFIGURED_WORKTREE_ROOT from $CONFIGURED_WORKTREE_ROOT_SOURCE, origin $CONFIGURED_WORKTREE_ROOT_ORIGIN" \
        "Informational rollup; per-worktree outside/wrong-layout findings carry the actionable expected paths" \
        "Migrate non-conforming worktrees with /source-control:worktree create at the configured root"
    else
      print_field 'Worktree placement' \
        "$repo_wt_linked linked; no configured worktree root — locations: $placement_paths"
      emit_finding LOW worktree-root-unconfigured "$canonical" \
        "$repo_wt_linked linked worktree(s) with no configured worktree root (melodic.worktreeroot and source-control worktree_root unset); placement: $placement_paths" \
        "Descriptive only; no convention asserted" \
        "Set melodic.worktreeroot or source-control worktree_root, then rerun for conformance"
    fi
  fi

  default_branch="$expected_default"
  if [[ -z "$default_branch" && -n "$canonical_remote" ]]; then
    default_branch="$(run_git_probe -C "$canonical" symbolic-ref "refs/remotes/$canonical_remote/HEAD" 2>/dev/null | sed "s|^refs/remotes/$canonical_remote/||" | tr -d '\r')"
  fi
  if ! current_branch="$(run_git_probe -C "$canonical" branch --show-current 2>/dev/null | tr -d '\r')"; then
    emit_finding UNKNOWN current-branch-unavailable "$canonical" \
      "git branch --show-current failed" \
      "Stop local branch classification; the checked-out branch cannot be protected reliably" \
      "Repair Git metadata or correct the canonical checkout, then rerun"
    return
  fi

  # Git emits one LF after every custom for-each-ref format. Terminate each complete branch/tip
  # record with an explicit NUL, strip only that Git-added record separator, and preserve the
  # producer's exit status in a separate NUL field. Never classify partial output from a failed probe.
  while IFS= read -r -d '' ref_record; do
    while [[ "$ref_record" == $'\n'* || "$ref_record" == $'\r'* ]]; do
      ref_record="${ref_record:1}"
    done
    [[ -n "$ref_record" ]] || continue
    if [[ "$ref_record" == __repo_fleet_ref_status__\ * ]]; then
      branch_status="${ref_record#__repo_fleet_ref_status__ }"
      continue
    fi
    if [[ "$ref_record" != *$'\t'* ]]; then
      branch_inventory_valid=false
      continue
    fi
    branch="${ref_record%%$'\t'*}"
    tip="${ref_record#*$'\t'}"
    if [[ -z "$branch" || -z "$tip" || "$tip" == *$'\t'* ]]; then
      branch_inventory_valid=false
      continue
    fi
    BRANCH_NAMES+=("$branch")
    BRANCH_TIPS+=("$tip")
  done < <(
    run_git_probe -C "$canonical" for-each-ref \
      '--format=%(refname:short)%09%(objectname)%00' -- refs/heads/ 2>/dev/null
    printf '\0__repo_fleet_ref_status__ %s\0' "$?"
  )
  if [[ "$branch_status" != "0" || "$branch_inventory_valid" != "true" ]]; then
    emit_finding UNKNOWN branch-inventory-unavailable "$canonical" \
      "git for-each-ref failed or returned a malformed branch/tip record" \
      "Stop local branch classification for this repository" \
      "Repair Git metadata or correct the canonical checkout, then rerun"
    return
  fi

  # Remote-tracking inventory is local-only evidence for merged-pr-tip-drift push-state wording.
  # Merge evidence itself is gathered by exact headRefName GraphQL aliases below and does not
  # depend on these refs (auto-deleted-then-pruned heads stay queryable on GitHub).
  if [[ -n "$canonical_remote" ]]; then
    while IFS= read -r -d '' remote_ref_record; do
      while [[ "$remote_ref_record" == $'\n'* || "$remote_ref_record" == $'\r'* ]]; do
        remote_ref_record="${remote_ref_record:1}"
      done
      [[ -n "$remote_ref_record" ]] || continue
      if [[ "$remote_ref_record" == __repo_fleet_ref_status__\ * ]]; then
        remote_branch_status="${remote_ref_record#__repo_fleet_ref_status__ }"
        continue
      fi
      [[ "$remote_ref_record" == *$'\t'* ]] || continue
      remote_branch_short="${remote_ref_record%%$'\t'*}"
      remote_tip="${remote_ref_record#*$'\t'}"
      # refs/remotes/<remote>/ also yields a bare "<remote>" entry (the symbolic HEAD pointer to
      # the remote's default branch, e.g. refs/remotes/origin/HEAD -> refname:short "origin") --
      # require the literal "<remote>/" prefix so that entry is excluded, not misread as a branch.
      if [[ "$remote_branch_short" == "$canonical_remote/"* ]]; then
        remote_branch_short="${remote_branch_short#"$canonical_remote"/}"
        if [[ -n "$remote_branch_short" ]]; then
          REMOTE_BRANCH_NAMES+=("$remote_branch_short")
          REMOTE_BRANCH_TIPS+=("$remote_tip")
        fi
      fi
    done < <(
      run_git_probe -C "$canonical" for-each-ref \
        '--format=%(refname:short)%09%(objectname)%00' -- "refs/remotes/$canonical_remote/" 2>/dev/null
      printf '\0__repo_fleet_ref_status__ %s\0' "$?"
    )
    if [[ "$remote_branch_status" != "0" ]]; then
      # Partial producer output is discarded so tip-drift push-state never trusts a half-built list.
      REMOTE_BRANCH_NAMES=()
      REMOTE_BRANCH_TIPS=()
      remote_inventory_failed=true
      emit_finding UNKNOWN remote-branch-inventory-unavailable "$canonical" \
        "git for-each-ref for refs/remotes/$canonical_remote/ failed" \
        "Remote-tracking tip comparison for merged-pr-tip-drift is unavailable; GraphQL merge evidence still runs" \
        "Repair Git metadata or correct the canonical checkout, then rerun"
    fi
  fi

  # One aliased GraphQL query per page of local branches (exact headRefName, first:1, MERGED).
  # Per-branch aliases retire the REST window truncation and the privacy-gated --head fallback:
  # every non-default local branch the operator asked about is queried by exact name. Fail closed
  # when gh/GraphQL is unavailable — never infer unmerged from a missing row after a failed page.
  if [[ -n "$github_repo" && "$GH_READY" == "true" ]]; then
    gql_owner="${github_repo%%/*}"
    gql_name="${github_repo#*/}"
    if [[ -z "$gql_owner" || -z "$gql_name" || "$gql_owner" == */* || "$github_repo" != */* ]]; then
      emit_finding UNKNOWN github-pr-evidence-unavailable "$github_repo" \
        "resolved GitHub identity is not owner/name shaped for GraphQL" "Do not infer branch merge state" \
        "Restore GitHub access/authentication and rerun"
    else
      gql_owner_esc="$(graphql_string_escape "$gql_owner")"
      gql_name_esc="$(graphql_string_escape "$gql_name")"
      GQL_BRANCHES=()
      for branch in "${BRANCH_NAMES[@]:-}"; do
        [[ -n "$branch" && "$branch" != "$default_branch" ]] || continue
        [[ "$branch" =~ [[:cntrl:]] ]] && continue
        GQL_BRANCHES+=("$branch")
      done
      # Remote-only heads (local already deleted) still need exact headRefName GraphQL rows
      # for merged-remote-branch classification.
      for remote_branch_short in "${REMOTE_BRANCH_NAMES[@]:-}"; do
        [[ -n "$remote_branch_short" && "$remote_branch_short" != "$default_branch" ]] || continue
        [[ "$remote_branch_short" =~ [[:cntrl:]] ]] && continue
        already=false
        for existing in "${GQL_BRANCHES[@]:-}"; do
          [[ "$existing" == "$remote_branch_short" ]] && { already=true; break; }
        done
        [[ "$already" == "true" ]] || GQL_BRANCHES+=("$remote_branch_short")
      done
      repo_pr_available=true
      repo_pr_rows=""
      gql_page_start=0
      while [[ "$gql_page_start" -lt "${#GQL_BRANCHES[@]}" ]]; do
        gql_page_end=$((gql_page_start + MERGED_PR_GRAPHQL_ALIAS_PAGE))
        [[ "$gql_page_end" -gt "${#GQL_BRANCHES[@]}" ]] && gql_page_end=${#GQL_BRANCHES[@]}
        gql_query='query{rateLimit{cost nodeCount}'
        gql_alias_i=0
        for ((gql_bi = gql_page_start; gql_bi < gql_page_end; gql_bi++)); do
          gql_branch_esc="$(graphql_string_escape "${GQL_BRANCHES[$gql_bi]}")"
          gql_query+="b${gql_alias_i}:repository(owner:\"${gql_owner_esc}\",name:\"${gql_name_esc}\"){pullRequests(headRefName:\"${gql_branch_esc}\",first:1,states:[MERGED]){nodes{number headRefName headRefOid mergedAt url}}}"
          gql_alias_i=$((gql_alias_i + 1))
        done
        gql_query+='}'
        if ! gql_page_rows="$(run_bounded_gh api graphql --hostname github.com -f "query=$gql_query" \
          --jq "$MERGED_PR_GRAPHQL_JQ" 2>/dev/null)"; then
          repo_pr_available=false
          break
        fi
        if [[ -n "$gql_page_rows" ]]; then
          if [[ -n "$repo_pr_rows" ]]; then
            repo_pr_rows+=$'\n'"$gql_page_rows"
          else
            repo_pr_rows="$gql_page_rows"
          fi
        fi
        gql_page_start=$gql_page_end
      done
      if [[ "$repo_pr_available" != "true" ]]; then
        emit_finding UNKNOWN github-pr-evidence-unavailable "$github_repo" \
          "aliased GraphQL merged-PR query failed" "Do not infer branch merge state" \
          "Restore GitHub access/authentication and rerun"
      fi
    fi
  fi

  for ((branch_index = 0; branch_index < ${#BRANCH_NAMES[@]}; branch_index++)); do
    branch="${BRANCH_NAMES[$branch_index]}"
    tip="${BRANCH_TIPS[$branch_index]}"
    attached=false
    is_main=false
    for ((wt_index = 0; wt_index < ${#WT_BRANCHES[@]}; wt_index++)); do
      if [[ "${WT_BRANCHES[$wt_index]}" == "$branch" ]]; then
        attached=true
        [[ "$wt_index" -eq 0 ]] && is_main=true
      fi
    done
    protected=false
    [[ "$branch" == "$default_branch" || "$branch" == "$current_branch" ]] && protected=true
    [[ "$is_main" == "true" ]] && protected=true

    pr_match="" pr_any=""
    if [[ "$repo_pr_available" == "true" && "$branch" != "$default_branch" ]]; then
      while IFS=$'\t' read -r pr_num pr_branch pr_oid pr_merged pr_url; do
        [[ -n "$pr_num" ]] || continue
        [[ "$pr_branch" == "$branch" ]] || continue
        [[ -z "$pr_any" ]] && pr_any="$pr_num|$pr_oid|$pr_merged|$pr_url"
        if [[ "$pr_oid" == "$tip" ]]; then
          pr_match="$pr_num|$pr_oid|$pr_merged|$pr_url"
          break
        fi
      done <<<"$repo_pr_rows"
    fi

    if [[ -n "$pr_match" ]]; then
      IFS='|' read -r pr_num pr_oid pr_merged pr_url <<<"$pr_match"
      if [[ "$attached" == "true" && "$is_main" == "false" ]]; then
        emit_finding HIGH merged-worktree "$canonical :: $branch" \
          "GitHub PR #$pr_num MERGED; headRefOid $pr_oid equals local tip; branch is worktree-attached" \
          "Candidate worktree dry-run handoff before branch cleanup" \
          "Run /source-control:worktree cleanup --dry-run in $canonical"
      elif [[ "$protected" == "false" ]]; then
        emit_finding HIGH merged-local-branch "$canonical :: $branch" \
          "GitHub PR #$pr_num MERGED; headRefOid $pr_oid equals local tip ($pr_url)" \
          "Candidate per-repository branch-audit handoff" "Run /repo-hygiene:clean git in $canonical"
      else
        # Protected AND exact-OID merged. Without this arm the evidence is computed
        # and then discarded: neither branch above fires, so the strongest merge
        # evidence the collector has produces no finding at all. The weaker
        # merged-pr-tip-drift below carries no protection guard and DOES emit, so
        # silence here reads as "nothing merged" rather than "merged but protected".
        # Reported, never a cleanup candidate -- the protection rule is unchanged
        # and this kind is deliberately absent from branch_action_kind().
        protection_reason="branch is protected"
        if [[ "$branch" == "$default_branch" ]]; then
          protection_reason="default branch"
        elif [[ "$branch" == "$current_branch" ]]; then
          protection_reason="current branch of the canonical checkout"
        elif [[ "$is_main" == "true" ]]; then
          protection_reason="attached to the main worktree"
        fi
        emit_finding LOW merged-protected-branch "$canonical :: $branch" \
          "GitHub PR #$pr_num MERGED; headRefOid $pr_oid equals local tip ($pr_url); $protection_reason" \
          "Informational only; protected branches are never branch-cleanup candidates" \
          "Switch off this branch in $canonical, then rerun to reclassify it"
      fi
    elif [[ -n "$pr_any" && "$branch" != "$default_branch" ]]; then
      IFS='|' read -r pr_num pr_oid pr_merged pr_url <<<"$pr_any"
      # Whether the local tip matches the last-fetched remote-tracking ref changes the cleanup
      # risk profile, so the evidence names that observation from the already-collected inventory
      # -- purely local, no network. A remote-tracking ref only records what the remote advertised
      # at the LAST FETCH (the branch may have been deleted or force-pushed since), so the
      # evidence is framed as cached local observation, never as current remote reachability.
      # Absence from that ref does not prove the tip was never pushed: post-merge head deletion
      # plus prune is common, and the tip object may still exist on the remote under another ref.
      if [[ "$remote_inventory_failed" == "true" || -z "$canonical_remote" ]]; then
        push_state="remote-tracking inventory unavailable, push state unknown"
      else
        push_state="local tip not on the last-fetched remote-tracking ref (tip differs from merged PR headRefOid; commits may still be on the remote)"
        for ((ri = 0; ri < ${#REMOTE_BRANCH_NAMES[@]}; ri++)); do
          if [[ "${REMOTE_BRANCH_NAMES[$ri]}" == "$branch" && "${REMOTE_BRANCH_TIPS[$ri]}" == "$tip" ]]; then
            push_state="local tip matches the last-fetched remote-tracking ref (pushed as of the last fetch; verify current remote state before relying on recoverability)"
            break
          fi
        done
      fi
      emit_finding MEDIUM merged-pr-tip-drift "$canonical :: $branch" \
        "GitHub PR #$pr_num MERGED at headRefOid $pr_oid, but current local tip is $tip; $push_state" \
        "Manual review; not a cleanup candidate" "Inspect commits added after PR #$pr_num"
    elif [[ "$protected" == "false" && "$attached" == "false" && -n "$canonical_remote" && -n "$default_branch" ]]; then
      run_git_probe -C "$canonical" merge-base --is-ancestor "$tip" \
        "refs/remotes/$canonical_remote/$default_branch" 2>/dev/null
      ancestry_status=$?
      if [[ "$ancestry_status" == "0" ]]; then
        emit_finding LOW local-ancestry-only "$canonical :: $branch" \
          "local tip is an ancestor of $canonical_remote/$default_branch; no matching GitHub merged-PR evidence" \
          "Informational only" "Review in /repo-hygiene:clean git; do not infer PR merge"
      elif [[ "$ancestry_status" != "1" ]]; then
        emit_finding UNKNOWN local-ancestry-unavailable "$canonical :: $branch" \
          "git merge-base --is-ancestor failed with status $ancestry_status" \
          "Do not infer local ancestry" "Repair Git metadata or restore missing objects, then rerun"
      fi
    fi
  done

  # Merged remote branches that still exist on the remote are a distinct class from local cleanup:
  # delete_branch_on_merge was off (or blocked), so the head ref remains on origin after merge.
  # Match GraphQL merged-PR rows against the REMOTE tip (not the local tip). This also catches
  # remote-only heads (local already deleted). A last-fetched remote-tracking tip alone is not
  # live proof — after merge-and-auto-delete without a pruning fetch the cached ref can linger —
  # so HIGH requires ls-remote to confirm the head still exists at the matched tip. When
  # ls-remote fails, report the cached observation at MEDIUM. Empty ls-remote means the remote
  # head is gone; emit nothing. Enabling GitHub delete_branch_on_merge is complementary and is
  # never a substitute for this visibility; this collector never changes that setting.
  if [[ "$repo_pr_available" == "true" && "$remote_inventory_failed" == "false" && -n "$canonical_remote" ]]; then
    for ((ri = 0; ri < ${#REMOTE_BRANCH_NAMES[@]}; ri++)); do
      remote_branch_short="${REMOTE_BRANCH_NAMES[$ri]}"
      remote_tip="${REMOTE_BRANCH_TIPS[$ri]}"
      [[ -n "$remote_branch_short" && -n "$remote_tip" ]] || continue
      [[ "$remote_branch_short" == "$default_branch" ]] && continue
      pr_match=""
      while IFS=$'\t' read -r pr_num pr_branch pr_oid pr_merged pr_url; do
        [[ -n "$pr_num" ]] || continue
        [[ "$pr_branch" == "$remote_branch_short" ]] || continue
        if [[ "$pr_oid" == "$remote_tip" ]]; then
          pr_match="$pr_num|$pr_oid|$pr_merged|$pr_url"
          break
        fi
      done <<<"$repo_pr_rows"
      if [[ -n "$pr_match" ]]; then
        IFS='|' read -r pr_num pr_oid pr_merged pr_url <<<"$pr_match"
        live_out=""
        live_status=0
        live_out="$(run_git_probe -C "$canonical" ls-remote --heads "$canonical_remote" \
          "refs/heads/$remote_branch_short" 2>/dev/null)" || live_status=$?
        live_oid=""
        if [[ "$live_status" -eq 0 && -n "$live_out" ]]; then
          live_oid="${live_out%%[[:space:]]*}"
          live_oid="${live_oid%%$'\t'*}"
        fi
        if [[ "$live_status" -eq 0 && -n "$live_oid" && "$live_oid" == "$remote_tip" ]]; then
          emit_finding HIGH merged-remote-branch "$canonical :: $canonical_remote/$remote_branch_short" \
            "GitHub PR #$pr_num MERGED; headRefOid $pr_oid equals last-fetched $canonical_remote/$remote_branch_short tip ($pr_url); ls-remote confirmed refs/heads/$remote_branch_short still at $live_oid (delete_branch_on_merge not enabled or blocked for this repository)" \
            "Optional remote-branch deletion preview; separate from local branch/worktree cleanup" \
            "Preview only: git -C $canonical push --delete --dry-run $canonical_remote $remote_branch_short. Enabling GitHub delete_branch_on_merge is complementary (stops this class accruing) and is not a substitute for this finding; change that setting in the repository's settings-owning automation, never via an org-admin API call from this audit"
        elif [[ "$live_status" -eq 0 ]]; then
          # Empty or tip-mismatched ls-remote: remote head is gone or moved; do not blame
          # delete_branch_on_merge on a stale local remote-tracking observation.
          :
        else
          emit_finding MEDIUM merged-remote-branch "$canonical :: $canonical_remote/$remote_branch_short" \
            "GitHub PR #$pr_num MERGED; headRefOid $pr_oid equals last-fetched $canonical_remote/$remote_branch_short tip ($pr_url); current remote existence could not be verified (ls-remote failed) — may be a stale local remote-tracking observation after a prune-less fetch" \
            "Optional remote-branch deletion preview; separate from local branch/worktree cleanup" \
            "Preview only: git -C $canonical push --delete --dry-run $canonical_remote $remote_branch_short. Re-verify with ls-remote or a pruning fetch before acting. Enabling GitHub delete_branch_on_merge is complementary (stops this class accruing) and is not a substitute for this finding; change that setting in the repository's settings-owning automation, never via an org-admin API call from this audit"
        fi
      fi
    done
  fi

  REPOS_AUDITED=$((REPOS_AUDITED + 1))
  mark_repo_counted
}

printf 'Repo Fleet Hygiene Audit\n'
printf 'Mode: read-only (no fetch, prune, repair, delete, checkout, or remote update)\n'
printf 'Presentation: per-repository rollup by default; pass --detail for collapsed per-target evidence\n'
if [[ -n "$CONFIG_FILE" ]]; then
  print_field Config "$CONFIG_FILE ($CONFIG_SOURCE)"
else
  print_field Config "none (no explicit --config, and no project or user-global config file found)"
fi
print_field Scope "$SCOPE_PROVENANCE"
if [[ -n "$CONFIGURED_WORKTREE_ROOT" ]]; then
  printf 'Worktree root: '
  display_value "$CONFIGURED_WORKTREE_ROOT"
  printf ' (source: %s' "$CONFIGURED_WORKTREE_ROOT_SOURCE"
  if [[ -n "$CONFIGURED_WORKTREE_ROOT_ORIGIN" ]]; then
    printf '; origin: '
    display_value "$CONFIGURED_WORKTREE_ROOT_ORIGIN"
  fi
  printf ')\n'
else
  printf 'Worktree root: unset (no melodic.worktreeroot git key and no source-control worktree_root; placement reported without asserting a convention)\n'
fi
if [[ "$GH_READY" == "true" && -n "$GH_ACCOUNT" ]]; then
  printf 'GitHub evidence: available (account: '
  display_value "$GH_ACCOUNT"
  printf ')\n'
else
  printf 'GitHub evidence: %s\n' "$([[ "$GH_READY" == "true" ]] && echo available || echo unavailable)"
fi
# Two different quantities previously shared the bare label "repositories": this one counts
# discovery targets, the Summary line counts repositories that completed a local audit. Both are
# qualified so a reader cannot read a shortfall as a discrepancy.
printf 'Repositories discovered (audit targets after deduplication): %s\n' "${#TARGETS[@]}"
# One line per repository of record, listing every path that resolved into it. A separate line per
# retargeted path would print N lines for a repository the count above reports once, which reads as
# N repositories -- the same header-contradicts-itself defect this report is being corrected for.
RT_REPORTED=()
for ((rt_index = 0; rt_index < ${#RETARGETED_TO[@]}; rt_index++)); do
  rt_to="${RETARGETED_TO[$rt_index]}"
  rt_seen=false
  for rt_prev in "${RT_REPORTED[@]:-}"; do
    [[ -n "$rt_prev" && "$rt_prev" == "$rt_to" ]] && {
      rt_seen=true
      break
    }
  done
  [[ "$rt_seen" == "true" ]] && continue
  RT_REPORTED+=("$rt_to")
  printf 'Resolved to main worktree: '
  display_value "$rt_to"
  printf ' (reached via'
  rt_count=0
  for ((rt_j = 0; rt_j < ${#RETARGETED_TO[@]}; rt_j++)); do
    [[ "${RETARGETED_TO[$rt_j]}" == "$rt_to" ]] || continue
    [[ "$rt_count" -gt 0 ]] && printf ','
    printf ' '
    display_value "${RETARGETED_FROM[$rt_j]}"
    rt_count=$((rt_count + 1))
  done
  printf ')\n'
done
for ((root_index = 0; root_index < ${#ROOT_LABELS[@]}; root_index++)); do
  printf 'Root '
  display_value "${ROOT_LABELS[$root_index]}"
  printf ': %s repositories\n' "${ROOT_COUNTS[$root_index]}"
done

# Discovery walks directories that are mostly not repositories; when a .git marker fails validation
# (or a directory is unreadable), the path is skipped rather than aborting. Report the counts so
# silence is not mistaken for a complete walk.
if [[ ${#ROOT_LABELS[@]} -gt 0 ]]; then
  printf 'Discovery skips: %s non-repository, %s unreadable\n' \
    "$DISCOVERY_NONREPO_COUNT" "$DISCOVERY_UNREADABLE_COUNT"
fi

# Config-sourced entries that failed per-entry validation during argument processing (the header
# had not printed yet); each is a visible finding, never a silent skip. Fleet-scoped: no repository
# record owns them, so CURRENT_REPO_IDX stays -1 and the rollup lists them under Fleet-level.
CURRENT_REPO_IDX=-1
for ((stale_index = 0; stale_index < ${#STALE_CONFIG_PATHS[@]}; stale_index++)); do
  emit_finding UNKNOWN stale-config-entry "${STALE_CONFIG_PATHS[$stale_index]}" \
    "${STALE_CONFIG_REASONS[$stale_index]} (source: $CONFIG_FILE)" \
    "Entry skipped; the rest of the fleet was audited" \
    "Remove or correct the entry via /repo-fleet-hygiene:setup apply, or restore the path, then rerun"
done

# Discovery-sourced husks/unreadable paths with a .git marker; same visibility rule as stale config.
for ((skip_index = 0; skip_index < ${#DISCOVERY_SKIP_PATHS[@]}; skip_index++)); do
  printf '\n'
  emit_finding UNKNOWN discovery-skip "${DISCOVERY_SKIP_PATHS[$skip_index]}" \
    "${DISCOVERY_SKIP_REASONS[$skip_index]}" \
    "Path skipped; the rest of the fleet was audited" \
    "No action required for ordinary non-repositories; inspect unexpected .git markers, then rerun"
done

# Bare repositories that still have working-tree content or linked worktrees (#2602). Reported
# before per-repo analysis so the anomaly is visible even when no worktree could be audited.
for ((bare_index = 0; bare_index < ${#BARE_LIVE_TREE_PATHS[@]}; bare_index++)); do
  printf '\n'
  print_field Repo "${BARE_LIVE_TREE_PATHS[$bare_index]}"
  print_field Canonical unresolved
  emit_finding MEDIUM bare-repo-with-working-tree "${BARE_LIVE_TREE_PATHS[$bare_index]}" \
    "${BARE_LIVE_TREE_EVIDENCE[$bare_index]}" \
    "Manual review only; never auto-rewrite core.bare" \
    "Run git config --local core.bare false in ${BARE_LIVE_TREE_PATHS[$bare_index]} (preferred over extensions.worktreeConfig); linked worktrees are unaffected"
done

for target in "${TARGETS[@]}"; do
  analyze_repo "$target"
done

# Cross-repository view: multiple independent checkouts of the same normalized GitHub identity are
# each audited on their own local state (correct), but the coincidence itself gets one LOW
# informational line per identity -- never more, since same-identity clones legitimately diverge.
CURRENT_REPO_IDX=-1
DUP_REPORTED=()
for ((di = 0; di < ${#IDENT_KEYS[@]}; di++)); do
  dup_key="${IDENT_KEYS[$di]}"
  dup_seen=false
  for dup_prev in "${DUP_REPORTED[@]:-}"; do
    [[ -n "$dup_prev" && "$dup_prev" == "$dup_key" ]] && {
      dup_seen=true
      break
    }
  done
  [[ "$dup_seen" == "true" ]] && continue
  DUP_REPORTED+=("$dup_key")
  DUP_PATHS=()
  for ((dj = 0; dj < ${#IDENT_KEYS[@]}; dj++)); do
    [[ "${IDENT_KEYS[$dj]}" == "$dup_key" ]] && DUP_PATHS+=("${IDENT_PATHS[$dj]}")
  done
  if [[ "${#DUP_PATHS[@]}" -ge 2 ]]; then
    emit_finding LOW duplicate-checkout "$dup_key" \
      "${#DUP_PATHS[@]} distinct checkouts resolve to the same GitHub identity: ${DUP_PATHS[*]}" \
      "Informational only; same-identity clones have independent local state" \
      "Consolidate manually if unintended; no automated action"
  fi
done

# Fleet-level worktree-root conformance headline (#2606). Emitted even when every other finding is
# empty — "N of M outside the configured root" is the signal this fleet lacked. Buffered before the
# human rollup so kind counts and --detail include these findings.
if [[ "$PLUGINCONFIGS_JQ_MISSING" == "true" ]]; then
  emit_finding UNKNOWN worktree-root-pluginconfigs-unreadable "fleet" \
    "settings file $PLUGINCONFIGS_SETTINGS_PATH may declare source-control worktree_root, but jq is not installed so the pluginConfigs fallback could not be read (melodic.worktreeroot was also unset)" \
    "Do not treat the fleet as unconfigured; install jq or set melodic.worktreeroot, then rerun" \
    "Install jq on PATH, or set melodic.worktreeroot via git config / includeIf"
fi
if [[ -n "$CONFIGURED_WORKTREE_ROOT" ]]; then
  emit_finding LOW worktree-root-conformance-summary "fleet" \
    "$FLEET_WT_NONCONFORMING of $FLEET_WT_LINKED linked worktrees are outside the configured root or wrong layout ($FLEET_WT_CONFORMING conforming, $FLEET_WT_TOOL_OWNED tool-owned); root $CONFIGURED_WORKTREE_ROOT from $CONFIGURED_WORKTREE_ROOT_SOURCE, origin $CONFIGURED_WORKTREE_ROOT_ORIGIN" \
    "Fleet rollup; migrate non-conforming placements toward the configured root" \
    "Use /source-control:worktree create at the configured root; tool-owned entries are exempt"
else
  emit_finding LOW worktree-root-unconfigured "fleet" \
    "$FLEET_WT_LINKED linked worktree(s) across the fleet; no configured worktree root (melodic.worktreeroot and source-control worktree_root unset) — placement reported without asserting a convention" \
    "Descriptive only; no convention asserted" \
    "Set melodic.worktreeroot (git config) or source-control worktree_root, then rerun for conformance"
fi

# --- Human rollup (#2608) ---------------------------------------------------
printf '\n'
printf 'Repository rollup\n'
printf 'Presentation: counts by finding kind; duplicate targets collapsed in detail/plan\n'
if [[ "$DETAIL" == "true" ]]; then
  print_field Detail "on (--detail); per-repository collapsed target blocks follow the action plan"
else
  print_field Detail "off (pass --detail for per-target evidence)"
fi

fleet_blocked=0
fleet_candidates=0
fleet_clean=0
for ((ri = 0; ri < ${#R_DISCOVERED[@]}; ri++)); do
  verdict="$(repo_verdict "$ri")"
  kinds="$(repo_kind_counts_text "$ri")"
  printf 'Repo: '
  display_value "${R_CANONICAL[$ri]}"
  printf '\n'
  print_field Verdict "$verdict"
  print_field 'Kind counts' "$kinds"
  case "$verdict" in
  CLEAN) fleet_clean=$((fleet_clean + 1)) ;;
  BLOCKED*) fleet_blocked=$((fleet_blocked + 1)) ;;
  *) fleet_candidates=$((fleet_candidates + 1)) ;;
  esac
  printf '%s\n' '---'
done

# Fleet-level findings (stale config, duplicate-checkout) get their own rollup row.
fleet_level_count=0
for ((i = 0; i < ${#F_KIND[@]}; i++)); do
  [[ "${F_REPO_IDX[$i]}" == "-1" ]] && fleet_level_count=$((fleet_level_count + 1))
done
if [[ "$fleet_level_count" -gt 0 ]]; then
  printf 'Repo: fleet-level\n'
  print_field Verdict "$(repo_verdict -1)"
  print_field 'Kind counts' "$(repo_kind_counts_text -1)"
  printf '%s\n' '---'
fi

case "$fleet_blocked" in
0)
  if [[ "$fleet_candidates" -gt 0 ]]; then
    fleet_verdict="$fleet_candidates repositories with candidates"
  else
    fleet_verdict="CLEAN"
  fi
  ;;
*)
  fleet_verdict="BLOCKED ($fleet_blocked repositories with evidence gaps)"
  ;;
esac
print_field 'Fleet verdict' "$fleet_verdict"
printf 'Fleet counts: clean=%s with_candidates=%s blocked=%s\n' \
  "$fleet_clean" "$fleet_candidates" "$fleet_blocked"

# --- Fleet-scale action plan (#2609) ----------------------------------------
# One recommended skill invocation per (canonical repository, skill). Branch cleanups are listed
# before worktree cleanups so an operator approving the plan never prunes a worktree before the
# branch that still anchors its reflog.
printf '\n'
printf 'Fleet action plan\n'
printf 'Confirmation model: ONE gate for this entire plan (not per repository per skill)\n'
printf 'Order rule: delete/clean branches before pruning worktrees; re-derive OIDs at execution\n'
printf 'Mode: read-only plan (producing this plan performs no mutation)\n'

ACTION_SKILL=()
ACTION_CANONICAL=()
ACTION_OPERATION=()
ACTION_PHASE=()
ACTION_KINDS=()
# Targets are real array elements owned by action index (ACTION_TARGET_OWNER), not a
# delimited string: Unix paths may contain newlines, so no in-band separator is safe,
# and bash scalars cannot store NUL either.
ACTION_TARGET_OWNER=()
ACTION_TARGET_VALUE=()

append_or_extend_action() {
  local skill="$1" canonical="$2" operation="$3" phase="$4" kind="$5" target="$6"
  local i ti
  for ((i = 0; i < ${#ACTION_SKILL[@]}; i++)); do
    if [[ "${ACTION_SKILL[$i]}" == "$skill" && "${ACTION_CANONICAL[$i]}" == "$canonical" &&
      "${ACTION_OPERATION[$i]}" == "$operation" ]]; then
      case ",${ACTION_KINDS[$i]}," in
      *",$kind,"*) ;;
      *)
        if [[ -n "${ACTION_KINDS[i]}" ]]; then
          ACTION_KINDS[i]="${ACTION_KINDS[i]},$kind"
        else
          ACTION_KINDS[i]="$kind"
        fi
        ;;
      esac
      for ((ti = 0; ti < ${#ACTION_TARGET_OWNER[@]}; ti++)); do
        if [[ "${ACTION_TARGET_OWNER[ti]}" == "$i" && "${ACTION_TARGET_VALUE[ti]}" == "$target" ]]; then
          return 0
        fi
      done
      ACTION_TARGET_OWNER+=("$i")
      ACTION_TARGET_VALUE+=("$target")
      return 0
    fi
  done
  i=${#ACTION_SKILL[@]}
  ACTION_SKILL+=("$skill")
  ACTION_CANONICAL+=("$canonical")
  ACTION_OPERATION+=("$operation")
  ACTION_PHASE+=("$phase")
  ACTION_KINDS+=("$kind")
  ACTION_TARGET_OWNER+=("$i")
  ACTION_TARGET_VALUE+=("$target")
}

for ((i = 0; i < ${#F_KIND[@]}; i++)); do
  kind="${F_KIND[$i]}"
  target="${F_TARGET[$i]}"
  repo_idx="${F_REPO_IDX[$i]}"
  [[ "$repo_idx" -ge 0 ]] || continue
  canonical="${R_CANONICAL[$repo_idx]}"
  [[ "$canonical" != "unresolved" ]] || continue
  if branch_action_kind "$kind"; then
    append_or_extend_action "/repo-hygiene:clean git" "$canonical" \
      "delete-merged-local-branches" "1" "$kind" "$target"
  elif worktree_action_kind "$kind"; then
    append_or_extend_action "/source-control:worktree cleanup --dry-run" "$canonical" \
      "cleanup-worktrees" "2" "$kind" "$target"
  fi
done

# Stable order: phase (branch=1 before worktree=2), then canonical path, then original index.
ACTION_ORDER=()
for ((i = 0; i < ${#ACTION_SKILL[@]}; i++)); do
  ACTION_ORDER+=("$i")
done
if [[ ${#ACTION_ORDER[@]} -gt 0 ]]; then
  mapfile -t ACTION_ORDER < <(
    for i in "${ACTION_ORDER[@]}"; do
      printf '%s\t%s\t%05d\n' "${ACTION_PHASE[$i]}" "${ACTION_CANONICAL[$i]}" "$i"
    done | LC_ALL=C sort | awk -F '\t' '{print $3+0}'
  )
fi

if [[ ${#ACTION_ORDER[@]} -eq 0 ]]; then
  printf 'Actions: none\n'
else
  printf 'Actions: %s (unique repository/skill pairs)\n' "${#ACTION_ORDER[@]}"
  step=0
  for i in "${ACTION_ORDER[@]}"; do
    step=$((step + 1))
    printf '%s. ' "$step"
    display_value "${ACTION_SKILL[$i]}"
    printf '\n'
    printf '   repository: '
    display_value "${ACTION_CANONICAL[$i]}"
    printf '\n'
    print_field '   operation' "${ACTION_OPERATION[$i]}"
    print_field '   kinds' "${ACTION_KINDS[$i]}"
    target_count=0
    for ((ti = 0; ti < ${#ACTION_TARGET_OWNER[@]}; ti++)); do
      [[ "${ACTION_TARGET_OWNER[$ti]}" == "$i" ]] || continue
      target_count=$((target_count + 1))
    done
    printf '   targets (%s):\n' "$target_count"
    for ((ti = 0; ti < ${#ACTION_TARGET_OWNER[@]}; ti++)); do
      [[ "${ACTION_TARGET_OWNER[$ti]}" == "$i" ]] || continue
      printf '     - '
      display_value "${ACTION_TARGET_VALUE[$ti]}"
      printf '\n'
    done
  done
fi
printf 'Handoff: approve this plan once, then run /repo-fleet-hygiene:apply --plan-file <path> (or --apply-plan for a read-only preview)\n'

# --- Machine-readable plan artifact ----------------------------------------
if [[ -z "$PLAN_FILE" ]]; then
  PLAN_FILE="$(mktemp "${TMPDIR:-/tmp}/repo-fleet-hygiene-plan.XXXXXX.json")"
fi
{
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "mode": "read-only",\n'
  printf '  "generated_by": "repo-fleet-hygiene/audit",\n'
  printf '  "execution_order_rule": "delete-merged-local-branches before cleanup-worktrees; re-derive OIDs at execution time",\n'
  printf '  "confirmation_model": "one-gate-for-entire-plan",\n'
  printf '  "summary": {\n'
  printf '    "repositories_audited": %s,\n' "$REPOS_AUDITED"
  printf '    "high": %s,\n' "$FINDINGS_HIGH"
  printf '    "medium": %s,\n' "$FINDINGS_MEDIUM"
  printf '    "low": %s,\n' "$FINDINGS_LOW"
  printf '    "unknown": %s,\n' "$FINDINGS_UNKNOWN"
  printf '    "acknowledged": %s,\n' "$FINDINGS_ACKED"
  printf '    "fleet_verdict": "%s"\n' "$(json_escape "$fleet_verdict")"
  printf '  },\n'
  printf '  "repositories": [\n'
  for ((ri = 0; ri < ${#R_DISCOVERED[@]}; ri++)); do
    [[ "$ri" -gt 0 ]] && printf ',\n'
    verdict="$(repo_verdict "$ri")"
    kinds="$(repo_kind_counts_text "$ri")"
    printf '    {\n'
    printf '      "discovered": "%s",\n' "$(json_escape "${R_DISCOVERED[$ri]}")"
    printf '      "canonical": "%s",\n' "$(json_escape "${R_CANONICAL[$ri]}")"
    printf '      "remote": "%s",\n' "$(json_escape "${R_REMOTE[$ri]}")"
    printf '      "verdict": "%s",\n' "$(json_escape "$verdict")"
    printf '      "kind_counts_text": "%s",\n' "$(json_escape "$kinds")"
    printf '      "audited": %s,\n' "$([[ "${R_COUNTED[$ri]}" == "true" ]] && echo true || echo false)"
    printf '      "targets": [\n'
    # Collapse findings by target for this repository.
    target_list=()
    for ((fi = 0; fi < ${#F_KIND[@]}; fi++)); do
      [[ "${F_REPO_IDX[$fi]}" == "$ri" ]] || continue
      t="${F_TARGET[$fi]}"
      seen=false
      for prev in "${target_list[@]:-}"; do
        [[ "$prev" == "$t" ]] && {
          seen=true
          break
        }
      done
      [[ "$seen" == "true" ]] || target_list+=("$t")
    done
    for ((ti = 0; ti < ${#target_list[@]}; ti++)); do
      [[ "$ti" -gt 0 ]] && printf ',\n'
      t="${target_list[$ti]}"
      printf '        {\n'
      printf '          "target": "%s",\n' "$(json_escape "$t")"
      printf '          "findings": [\n'
      first_finding=true
      for ((fi = 0; fi < ${#F_KIND[@]}; fi++)); do
        [[ "${F_REPO_IDX[$fi]}" == "$ri" && "${F_TARGET[$fi]}" == "$t" ]] || continue
        [[ "$first_finding" == "true" ]] && first_finding=false || printf ',\n'
        printf '            {\n'
        printf '              "kind": "%s",\n' "$(json_escape "${F_KIND[$fi]}")"
        printf '              "confidence": "%s",\n' "$(json_escape "${F_CONF[$fi]}")"
        printf '              "evidence": "%s",\n' "$(json_escape "${F_EVIDENCE[$fi]}")"
        printf '              "disposition": "%s",\n' "$(json_escape "${F_DISP[$fi]}")"
        printf '              "handoff": "%s"\n' "$(json_escape "${F_HANDOFF[$fi]}")"
        printf '            }'
      done
      printf '\n          ]\n'
      printf '        }'
    done
    printf '\n      ]\n'
    printf '    }'
  done
  printf '\n  ],\n'
  printf '  "actions": [\n'
  first_action=true
  step=0
  for i in "${ACTION_ORDER[@]:-}"; do
    [[ -n "$i" ]] || continue
    [[ "$first_action" == "true" ]] && first_action=false || printf ',\n'
    step=$((step + 1))
    printf '    {\n'
    printf '      "order": %s,\n' "$step"
    printf '      "phase": %s,\n' "${ACTION_PHASE[$i]}"
    printf '      "skill": "%s",\n' "$(json_escape "${ACTION_SKILL[$i]}")"
    printf '      "canonical": "%s",\n' "$(json_escape "${ACTION_CANONICAL[$i]}")"
    printf '      "operation": "%s",\n' "$(json_escape "${ACTION_OPERATION[$i]}")"
    printf '      "kinds": ['
    first_kind=true
    IFS=',' read -r -a kind_arr <<<"${ACTION_KINDS[$i]}"
    for k in "${kind_arr[@]:-}"; do
      [[ -n "$k" ]] || continue
      [[ "$first_kind" == "true" ]] && first_kind=false || printf ', '
      printf '"%s"' "$(json_escape "$k")"
    done
    printf '],\n'
    printf '      "targets": ['
    first_t=true
    for ((ti = 0; ti < ${#ACTION_TARGET_OWNER[@]}; ti++)); do
      [[ "${ACTION_TARGET_OWNER[$ti]}" == "$i" ]] || continue
      [[ "$first_t" == "true" ]] && first_t=false || printf ', '
      printf '"%s"' "$(json_escape "${ACTION_TARGET_VALUE[$ti]}")"
    done
    printf '],\n'
    printf '      "note": "Re-derive OIDs at execution time; do not trust plan tips."\n'
    printf '    }'
  done
  printf '\n  ]\n'
  printf '}\n'
} >"$PLAN_FILE" || fail "cannot write plan file: $PLAN_FILE"
print_field 'Action plan' "$PLAN_FILE"
printf 'Apply dry-run: %s --apply-plan ' "$0"
display_value "$PLAN_FILE"
printf '\n'

# --- Optional detail: collapsed per-target blocks + confidence groups -------
if [[ "$DETAIL" == "true" ]]; then
  printf '\n'
  printf 'Detail (targets collapsed; one entry per path/branch)\n'
  for ((ri = 0; ri < ${#R_DISCOVERED[@]}; ri++)); do
    printf '\n'
    print_field Repo "${R_DISCOVERED[$ri]}"
    print_field Canonical "${R_CANONICAL[$ri]}"
    print_field 'Canonical resolution' "${R_RESOLUTION[$ri]}"
    print_field Remote "${R_REMOTE[$ri]}"
    print_field Verdict "$(repo_verdict "$ri")"
    print_collapsed_target_detail "$ri"
  done
  if [[ "$fleet_level_count" -gt 0 ]]; then
    printf '\n'
    print_field Repo fleet-level
    print_collapsed_target_detail -1
  fi
fi

printf '\nSummary: repositories_audited=%s high=%s medium=%s low=%s unknown=%s acknowledged=%s\n' \
  "$REPOS_AUDITED" "$FINDINGS_HIGH" "$FINDINGS_MEDIUM" "$FINDINGS_LOW" "$FINDINGS_UNKNOWN" "$FINDINGS_ACKED"
# Deliberately a statement of the enforcing mechanism, not a tally. The previous line printed a
# hardcoded "Mutation count: 0", which would have read identically in a build that mutated -- an
# unfalsifiable reassurance in the exact place a reader looks for assurance. A real counter is not
# available either: most probes run inside command substitution, so an increment would be lost with
# the subshell and would undercount. The allowlists are the fact; they are named so a reader can go
# read them.
printf 'Mutations: none possible; every Git and gh invocation is checked against a read-only\n'
printf '  command allowlist (git_probe_allowed / gh_probe_allowed) and rejected otherwise.\n'
