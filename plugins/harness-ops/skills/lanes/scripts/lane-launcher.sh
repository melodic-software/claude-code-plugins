#!/usr/bin/env bash
# lane-launcher.sh — start/restart/stop/status loop lanes as background Claude
# Code sessions seeded from canonical prompt files.
#
# The morning refresh ritual — cancel each loop, clear, re-paste its canonical
# prompt across N lanes — collapses to one command. `start`/`restart` pull the
# repo and refresh the plugin marketplace, then launch each configured lane as a
# named background session seeded with the lane's canonical prompt file.
# `status`/`stop` read and manage those sessions through the CLI's own
# background-session surface.
#
# Verified CLI surface (claude 2.1.215 — see the skill's Verification section;
# --settings re-verified against the CLI reference, 2026-07-25):
#   claude --bg -n <name> --permission-mode auto [--permission-prompts none]
#     [--model M] [--effort E]
#     [--settings JSON] "<prompt>"                              launch, return now
#   claude agents --json                                        list sessions
#                                                               (pid, cwd, kind,
#                                                               startedAt,
#                                                               sessionId, name,
#                                                               status)
#   claude stop <sessionId>                                     stop one session
#   claude plugin marketplace update                            refresh catalog(s)
# There is no `claude agents stop` verb: `stop`/`restart` target the sessionId
# that `agents --json` reports, and ONLY for a name present in the lane config —
# so the wrapper can never stop an unrelated session (e.g. a hand-started one).
#
# PROMPT-FILE STORAGE IS PROVISIONAL. Today prompts live in the lanes concern
# home under the session-local memory root (the config's `prompt_dir`, default
# `.work/lanes`). That home is a sanctioned placement, not a durable one: the
# memory root is session-local, so a fresh machine still starts with no prompts.
# A forthcoming loop-prompt authoring skill is slated to own durable
# cross-machine prompt storage; when it lands, repoint `prompt_dir` at that
# home — the resolution seam is the single `resolve_prompt_dir` function below
# and nothing else.
#
# Usage:
#   lane-launcher.sh [start]              pull + update, launch lanes not running
#   lane-launcher.sh restart [lane...]    stop then start (all lanes, or named)
#   lane-launcher.sh status               per-lane running state
#   lane-launcher.sh stop [lane...]       stop running lanes (all, or named)
#
# Options:
#   --config FILE      lane config JSON (default resolution order below)
#   --repo DIR         repo root for git pull + default launch cwd
#                      (default: the git toplevel of the current directory)
#   --no-pull          skip the git pull step (start / restart)
#   --no-update        skip the plugin marketplace update step (start / restart)
#   --dry-run          print the commands that would run; mutate nothing
#   --agents-json FILE read the session list from FILE instead of
#                      `claude agents --json` (offline / scripted / test reuse)
#   --data-dir DIR     base dir for the per-lane launch-commit marker (below);
#                      default: $CLAUDE_PLUGIN_DATA env var if it names
#                      harness-ops, else
#                      ~/.claude/plugins/data/harness-ops. NOTE: CLAUDE_PLUGIN_DATA
#                      is exported to hook/MCP/LSP subprocesses but NOT to a
#                      script a skill shells out to via the Bash tool (Claude
#                      Code plugins-reference, "Environment variables") — the
#                      lanes skill's SKILL.md passes --data-dir explicitly with
#                      the inline-substituted value so a real Claude Code
#                      session resolves the correct marketplace-qualified
#                      directory; this env-var/fallback path only kicks in for
#                      a direct/manual invocation (tests, a hand-run shell).
#   --gate-arm-script FILE
#                      override discovery of the autonomy plugin's
#                      lane-stop-gate-arm.sh (tests / dev checkouts). Default
#                      discovery walks this script's own install anchor —
#                      <config>/plugins/cache/*/autonomy/*/hooks/ — never an
#                      environment-derived path (see "Lane-stop gate arming").
#   --telemetry-json FILE
#                      read lane telemetry comments from FILE instead of `gh`:
#                      a JSON object mapping lane name -> comments array, e.g.
#                      {"work":[{"body":"..."}]} (offline / tests)
#   --help
#
# Launch-commit marker (#792):
#   After the pre-launch `git pull` (start/restart), the repo HEAD is captured
#   once and, for every lane actually (re)started this run, written to
#   `<data-dir>/lanes/<repo-key>/<lane>-launch-commit` (bare 40/64-hex SHA +
#   newline; <repo-key> digests the canonical repo path, so same-named lanes in
#   different repos never share a marker — recompute it by hand with
#   `printf '%s' "$(git rev-parse --show-toplevel)" | git hash-object --stdin`) —
#   the `<lane-launch-commit>` context/refresh.md's staleness probe reads. A
#   lane skipped by `start` (already running) keeps its existing marker
#   untouched. Best-effort: a write failure (or an unresolvable HEAD) warns on
#   stderr but never fails an already-launched session — and removes any marker
#   the PREVIOUS launch left, so the probe skips rather than trusting a commit
#   this session never launched at. The lane name is the marker's filename, so
#   config preflight rejects a name that is not a single path component.
#
# Config resolution (first hit wins):
#   --config FILE  →  $HARNESS_OPS_LANES_CONFIG  →  <repo>/.work/lanes/lanes.json
#   Compatibility: when none of those hit and the pre-move `<repo>/.work/lanes.json`
#   exists, that file is read instead, with a one-line deprecation WARNING. A
#   config resolved at the pre-move path also keeps the pre-move `prompt_dir`
#   default (".work"), so a config that never named one still finds the prompts
#   it left beside itself. Move both to `.work/lanes/` to clear the warning;
#   $HARNESS_OPS_LANES_CONFIG remains the escape hatch for a config kept elsewhere.
#
# Config schema (see context/config.md for the full contract):
#   { "prompt_dir": ".work/lanes",
#     "lanes": [ {"name":"work","prompt":"work.md","model":"opus","effort":"high"} ] }
#   prompt_dir  optional; base for relative `prompt` paths; default ".work/lanes"
#               (".work" for a config resolved at the pre-move path above).
#   name        required; the lane's session name (also the --name value).
#   prompt      required; path to the canonical prompt file (absolute, or
#               relative to prompt_dir).
#   model       optional; passed as --model.
#   effort      required; passed as --effort (low|medium|high|xhigh|max|ultracode).
#               start/restart refuse a lane with none; the other lanes still launch.
#               ultracode additionally requires the installed CLI to meet
#               ULTRACODE_MIN_VERSION; a lane below it is skipped, not launched.
#
# CLAUDE_CODE_EFFORT_LEVEL in the launcher's environment, which every lane
# inherits, may override lane --effort values and agent and skill effort pins,
# so start/restart print one WARNING per run naming its value.
#   settings    optional; a JSON OBJECT passed inline as --settings for that
#               session only (e.g. a pluginConfigs override opting the lane into
#               the autonomy plugin's lane-stop gate). Non-object values are
#               rejected.
#   stage       optional; the stage skill the lane runs, `<plugin>:<skill>`
#               (e.g. `work-items:work-loop`). Selects the lane's
#               `skill.<plugin>.<skill>` key in the execution-target file.
#   telemetry   optional; {"issue": N, "repo": "owner/name", "marker": "..."},
#               the lane's telemetry binding (context/restart-consumer.md). A
#               cloud-session lane reads its fallback marker there.
#
# Execution target (docs/conventions/execution-target/README.md in the
# marketplace repository is the contract):
#   start/restart fetch origin's default branch, read
#   docs/conventions/execution-target.yaml from that commit (never the working
#   tree), print the SHA, and resolve each launching lane's host:
#   skill.<plugin>.<skill>, then class.untrusted-provenance for a stage whose
#   input is always untrusted, then default, then local-worktree. An absent
#   file, an unreadable one, or an unknown value keeps today's launch.
#     local-worktree    claude --bg from the repo root (today's launch)
#     local-background  claude --bg from the lane's linked worktree
#     cloud-session     claude --cloud from a clean linked worktree at the
#                       fetched commit, only when the Claude GitHub App covers
#                       the repository and the lane's telemetry is readable;
#                       the prompt gains the stage-start probe preamble
#     cloud-routine,    print setup steps; launch nothing
#     cloud-project
#   A refused cloud launch runs local-worktree, except for a stage whose input
#   is always untrusted, which is skipped with an error instead.
#
# Lane-stop gate arming (#1784):
#   A lane whose settings request the autonomy lane-stop gate
#   (pluginConfigs["autonomy[@…]"].options.lane_stop_gate_enabled == true) is
#   ARMED at launch: the launcher generates a random arm id, runs the autonomy
#   plugin's hooks/lane-stop-gate-arm.sh (which writes a per-session record
#   under autonomy's own install-derived data directory), and injects the id
#   into the lane's --settings as lane_stop_gate_arm_id. The gate honors the
#   record — never the bare CLAUDE_PLUGIN_OPTION_* environment, which a watched
#   repository's own settings.json `env` block can populate. FAIL-CLOSED at
#   launch: a lane that requests the gate but cannot be armed (helper missing,
#   arming error, managed-settings veto) is skipped with an error — launching
#   it silently ungated would defeat the operator's request. Arm-helper
#   discovery uses the launcher's own plugins/cache install anchor (or the
#   --gate-arm-script override); an env-derived location would hand the same
#   repo env block the redirect this design closes.
#
# Exit codes:
#   0  ok
#   1  a refresh step (pull / marketplace update) failed, or a lane could not be
#      launched or stopped (per-lane errors name it; the other lanes still ran)
#   3  invalid argument / malformed config
#   4  prerequisite missing (claude or jq), or repo / config could not be resolved

set -uo pipefail

VALID_EFFORTS="low medium high xhigh max ultracode"

# Where a lane's level is chosen, named in the no-effort refusal. As of
# 2026-10-02; recheck when that section is renamed or moved.
EFFORT_TABLE_URL="https://code.claude.com/docs/en/model-config#choose-an-effort-level"

# `ultracode` is the one effort upstream gates on a CLI version, so it is the one
# the static allowlist cannot settle on its own. Below the floor the CLI rejects the
# value outright (`Unknown --effort value 'ultracode'`) and starts the session at the
# default effort, so the launcher skips the lane rather than launching it at an
# unintended effort — restart preflights this BEFORE stopping, keeping a healthy lane
# up. https://code.claude.com/docs/en/model-config#adjust-effort-level
ULTRACODE_MIN_VERSION="2.1.203"

# Unattended lanes keep auto mode (the classifier still decides) and deny only
# the calls that would have prompted. Below this floor the flag is an unknown
# option, so the launcher omits it. https://code.claude.com/docs/en/headless
PERMISSION_PROMPTS_MIN_VERSION="2.1.259"

# Compared component by component in awk — deliberately NOT `sort -V`, which is a
# GNU-only construct this repo's portability lane rejects. Missing components
# compare as 0, so "2.2" reads as 2.2.0.
version_at_least() { # <candidate> <minimum>
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  awk -F. -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".")
    n = (na > nb ? na : nb)
    for (i = 1; i <= n; i++) {
      av = (i <= na ? x[i] + 0 : 0); bv = (i <= nb ? y[i] + 0 : 0)
      if (av > bv) exit 0
      if (av < bv) exit 1
    }
    exit 0
  }' 2>/dev/null
}

# Memoized: every lane in a run shares one `claude --version` probe. Callers read
# CLI_VERSION_CACHE directly — a `$(cli_version)` substitution would populate the
# cache inside a subshell and throw it away, re-probing once per lane.
CLI_VERSION_CACHE=""
cli_version() {
  [[ -n "$CLI_VERSION_CACHE" ]] && return 0
  CLI_VERSION_CACHE="$(claude --version 2>/dev/null | tr -d '\r' |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  [[ -n "$CLI_VERSION_CACHE" ]] || CLI_VERSION_CACHE="unknown"
  return 0
}

ACTION="start"
CONFIG=""
REPO=""
NO_PULL=0
NO_UPDATE=0
DRY_RUN=0
AGENTS_JSON_FILE=""
DATA_DIR_OVERRIDE=""
GATE_ARM_SCRIPT_OVERRIDE=""
TELEMETRY_JSON_FILE=""
LAUNCH_COMMIT=""
declare -a TARGET_LANES=()

# --- Small emitters -----------------------------------------------------------
err() { printf 'ERROR: %s\n' "$*" >&2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

# Guard for a space-separated option that consumes the next token: reject a
# missing value or one that looks like another flag, so `--config --dry-run`
# fails loudly instead of silently swallowing `--dry-run` as the config path.
# Usage: `check_optarg "$1" "${2:-}" || exit 3` (kept out of a subshell so the
# caller's exit actually fires).
check_optarg() {
  [[ -n "${2:-}" && "$2" != -* ]] && return 0
  err "option '$1' requires a non-option argument"
  return 1
}

# Print the leading comment header (everything after the shebang up to the first
# non-comment line), stripped of the leading '# '. Robust to header length so a
# reformat never bleeds code into --help.
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

# --- Argument parse -----------------------------------------------------------
# First non-option token is the action; remaining non-option tokens are lane
# names (targets for restart/stop).
parse_args() {
  local seen_action=0
  while (($#)); do
    case "$1" in
    start | restart | status | stop)
      if ((seen_action)); then TARGET_LANES+=("$1"); else
        ACTION="$1"
        seen_action=1
      fi
      ;;
    --config)
      check_optarg "$1" "${2:-}" || exit 3
      CONFIG="$2"
      shift
      ;;
    --config=*) CONFIG="${1#*=}" ;;
    --repo)
      check_optarg "$1" "${2:-}" || exit 3
      REPO="$2"
      shift
      ;;
    --repo=*) REPO="${1#*=}" ;;
    --no-pull) NO_PULL=1 ;;
    --no-update) NO_UPDATE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --agents-json)
      check_optarg "$1" "${2:-}" || exit 3
      AGENTS_JSON_FILE="$2"
      shift
      ;;
    --agents-json=*) AGENTS_JSON_FILE="${1#*=}" ;;
    --data-dir)
      check_optarg "$1" "${2:-}" || exit 3
      DATA_DIR_OVERRIDE="$2"
      shift
      ;;
    --data-dir=*) DATA_DIR_OVERRIDE="${1#*=}" ;;
    --gate-arm-script)
      check_optarg "$1" "${2:-}" || exit 3
      GATE_ARM_SCRIPT_OVERRIDE="$2"
      shift
      ;;
    --gate-arm-script=*) GATE_ARM_SCRIPT_OVERRIDE="${1#*=}" ;;
    --telemetry-json)
      check_optarg "$1" "${2:-}" || exit 3
      TELEMETRY_JSON_FILE="$2"
      shift
      ;;
    --telemetry-json=*) TELEMETRY_JSON_FILE="${1#*=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while (($#)); do
        TARGET_LANES+=("$1")
        shift
      done
      break
      ;;
    -*)
      err "unknown option: $1 (see --help)"
      exit 3
      ;;
    *)
      # A bare token before the action is an unknown action; after it, a lane.
      if ((seen_action)); then TARGET_LANES+=("$1"); else
        err "unknown action: $1 (want: start restart status stop)"
        exit 3
      fi
      ;;
    esac
    shift
  done
}

# --- Prerequisites ------------------------------------------------------------
require_jq() {
  command -v jq >/dev/null 2>&1 || {
    err "jq not found (required)"
    exit 4
  }
}

# `claude` is only needed for real mutating/reading calls. Dry runs and
# fixture-fed (--agents-json) reads must work with no CLI installed.
require_claude() {
  ((DRY_RUN)) && return 0
  # A fixture-fed status read (--agents-json) makes no claude call, so it works
  # fully offline as documented; only the paths that actually shell out to
  # claude (launch / stop / marketplace update, or a live agents list) need it.
  [[ "$ACTION" == "status" && -n "$AGENTS_JSON_FILE" ]] && return 0
  command -v claude >/dev/null 2>&1 || {
    err "claude CLI not found (required)"
    exit 4
  }
}

# --- Repo + config resolution -------------------------------------------------
resolve_repo() {
  if [[ -n "$REPO" ]]; then
    [[ -d "$REPO" ]] || {
      err "repo not a directory: $REPO"
      exit 4
    }
    REPO="$(cd "$REPO" && pwd)"
    return 0
  fi
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    {
      err "not inside a git repo; pass --repo DIR"
      exit 4
    }
}

# The lanes concern home under the memory root, and the pre-move path it
# superseded. `lanes/` is a reserved first-level concern name, so the config and
# the lane prompts live inside it; the pre-move layout leaves them as bare files
# AT the memory root, outside any reserved name.
LANES_CONFIG_REL=".work/lanes/lanes.json"
LEGACY_LANES_CONFIG_REL=".work/lanes.json"

# Set when the resolved config IS the pre-move `<repo>/.work/lanes.json` —
# however it was resolved, not only through the fallback below. A config sitting
# at the old path was authored against the old prompt-dir default, so
# resolve_prompt_dir keeps giving it that default; otherwise a config that never
# named a `prompt_dir` would start looking for its prompts one directory deeper
# than it left them and skip every lane with "prompt file not found".
LEGACY_CONFIG_HOME=0

resolve_config() {
  if [[ -z "$CONFIG" ]]; then
    CONFIG="${HARNESS_OPS_LANES_CONFIG:-$REPO/$LANES_CONFIG_REL}"
    # Backward compatibility for a checkout that predates the move. Only the
    # DEFAULT falls back: an explicit --config or $HARNESS_OPS_LANES_CONFIG is
    # used verbatim, as documented, so the escape hatch keeps meaning exactly
    # what it says. Warn rather than fail: an operator whose lanes ran this
    # morning must not have `start` exit 4 on them, and the warning is what
    # turns a silent old-path read into a visible one-step migration.
    if [[ -z "${HARNESS_OPS_LANES_CONFIG:-}" && ! -f "$CONFIG" && -f "$REPO/$LEGACY_LANES_CONFIG_REL" ]]; then
      warn "reading the pre-move lane config at $REPO/$LEGACY_LANES_CONFIG_REL"
      warn "  move it (and the lane prompt files) to $REPO/.work/lanes/ — this fallback is temporary"
      CONFIG="$REPO/$LEGACY_LANES_CONFIG_REL"
    fi
  fi
  [[ "$CONFIG" == "$REPO/$LEGACY_LANES_CONFIG_REL" ]] && LEGACY_CONFIG_HOME=1
  [[ -f "$CONFIG" ]] || {
    err "lane config not found: $CONFIG"
    exit 4
  }
  jq -e . "$CONFIG" >/dev/null 2>&1 || {
    err "lane config is not valid JSON: $CONFIG"
    exit 3
  }
  local n
  n="$(jq -r '(.lanes // []) | length' "$CONFIG")"
  [[ "$n" -gt 0 ]] || {
    err "lane config has no lanes: $CONFIG"
    exit 3
  }
  # Lane names are the safety key: stop/restart resolve a sessionId by name and
  # every action snapshots sessions once, so a duplicated name would launch two
  # same-named sessions while stop reaches only the most-recent one. Reject it at
  # config time rather than silently acting on an ambiguous set.
  local dupes
  dupes="$(jq -r '[.lanes[].name | select(. != null)] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' "$CONFIG")" || {
    err "lane config validation query failed (duplicate lane names): $CONFIG"
    exit 3
  }
  [[ -z "$dupes" ]] || {
    err "lane config has duplicate lane names: $dupes (names must be unique): $CONFIG"
    exit 3
  }
  # The name is also a path component: it keys the per-lane launch-commit marker
  # at <data-dir>/lanes/<name>-launch-commit (#792). A name carrying a path
  # separator (or `.`/`..`) would escape that directory and let two distinct
  # lanes — say `work` and `group/../work` — share one marker file, so a
  # targeted restart of one would make the other's staleness probe read a launch
  # commit it never launched at. Reject rather than silently encode, so the
  # documented marker path stays literally true for every accepted name.
  local traversal
  traversal="$(jq -r '
    [ .lanes[].name
      | select(. != null)
      | select(type == "string")
      | select(test("[/\\\\]") or . == "." or . == "..") ] | join(", ")' "$CONFIG")" || {
    err "lane config validation query failed (lane name path safety): $CONFIG"
    exit 3
  }
  [[ -z "$traversal" ]] || {
    err "lane config has lane names that are not usable as a path component: $traversal"
    err "  (a name must not contain '/' or '\\', or be '.' or '..'): $CONFIG"
    exit 3
  }
  # The scalar lane fields are strings, and typing them HERE is what lets
  # `lane_field` keep answering "" for an absent field: `// ""` is jq's
  # alternative operator, so it fires on any falsy value — a mistyped
  # `"effort": false` collapsed to the same "" an unset field produces and the
  # lane launched with no effort at all, silently. A wrong type is a config
  # error like the duplicate/traversal names above, not a per-lane skip. An
  # explicit `null` is the JSON spelling of "no value" and stays equivalent to
  # an absent field. `settings` is deliberately NOT typed here — it is checked
  # per lane in validate_launch_inputs, which skips just that lane.
  local mistyped
  mistyped="$(jq -r '
    [ .lanes
      | to_entries[]
      | .key as $i
      | .value
      | to_entries[]
      | select(.key == "name" or .key == "model" or .key == "effort" or .key == "prompt" or .key == "stage")
      | select(.value != null and (.value | type) != "string")
      | "lane #\($i) .\(.key) is \(.value | type)" ]
    | join(", ")' "$CONFIG")" || {
    err "lane config validation query failed (lane field typing): $CONFIG"
    exit 3
  }
  [[ -z "$mistyped" ]] || {
    err "lane config has non-string values for string fields: $mistyped"
    err "  (name/model/effort/prompt/stage must be JSON strings): $CONFIG"
    exit 3
  }
  # `stage` becomes part of an execution-target key, so it is held to the
  # `<plugin>:<skill>` shape here, before any lane launches or stops.
  local badstage
  badstage="$(jq -r '
    [ .lanes[]
      | select(.stage != null)
      | select(.stage | test("^[a-z0-9][a-z0-9-]*:[a-z0-9][a-z0-9-]*$") | not)
      | .name // "?" ] | join(", ")' "$CONFIG")" || {
    err "lane config validation query failed (lane stage shape): $CONFIG"
    exit 3
  }
  [[ -z "$badstage" ]] || {
    err "lane config has a stage that is not <plugin>:<skill> (lowercase, digits, '-'): $badstage: $CONFIG"
    exit 3
  }
}

# Print <path> as it stands when it is already absolute (POSIX or a Windows
# drive), else anchored under the base directory <base>. Both the prompt dir and
# each lane's prompt file resolve that way.
path_under() { # <base> <path>
  case "$2" in
  /* | [A-Za-z]:[\\/]*) printf '%s' "$2" ;; # absolute (POSIX or Windows drive)
  *) printf '%s' "$1/$2" ;;
  esac
}

# The one prompt-storage seam — repoint here when a durable prompt home exists.
# Default: the `lanes/` concern home under the memory root. A config resolved at
# the pre-move path keeps the pre-move default (see LEGACY_CONFIG_HOME); an
# explicit `prompt_dir` wins over both, so a moved config that still names
# ".work" keeps reading prompts from there until its author moves them too.
resolve_prompt_dir() {
  local d default=".work/lanes"
  ((LEGACY_CONFIG_HOME)) && default=".work"
  d="$(jq -r --arg default "$default" '.prompt_dir // $default' "$CONFIG")"
  path_under "$REPO" "$d"
}

# --- Launch-commit marker (#792) ----------------------------------------------
# Base data dir: --data-dir, else $CLAUDE_PLUGIN_DATA when its last path segment
# names this plugin (another plugin's SessionStart hook can export its own data
# dir under that name), else the same ~/.claude/plugins/data/harness-ops
# fallback check-all.sh uses (e.g. a direct script invocation outside a Claude
# Code session, as in the test suite).
resolve_data_dir() {
  local base="$DATA_DIR_OVERRIDE" seg="${CLAUDE_PLUGIN_DATA:-}"
  if [[ -z "$base" ]]; then
    seg="${seg%[/\\]}"
    seg="${seg##*[/\\]}"
    if [[ "$seg" == harness-ops || "$seg" == harness-ops-* ]]; then
      base="$CLAUDE_PLUGIN_DATA"
    else
      base="$HOME/.claude/plugins/data/harness-ops"
    fi
  fi
  printf '%s/lanes' "${base%/}"
}

# The data dir is plugin-wide, but a lane name is only unique WITHIN one repo:
# this launcher manages lanes in any repo `--repo` points at, and `work` is a
# conventional name everywhere. Without a repo component, starting `work` in
# repo B would overwrite repo A's marker, and A's probe would then diff against
# a SHA from an unrelated history — usually an "invalid revision" error, at best
# a silently wrong answer.
#
# Three properties the key must have, all learned the hard way:
#   * Injective. A character-folding scheme (e.g. `tr -c 'A-Za-z0-9_-' '-'`)
#     collapses `/repos/foo-bar` and `/repos/foo/bar` onto one key, which is the
#     very collision this component exists to prevent. `git hash-object` over
#     the exact path string cannot.
#   * Derived from the CANONICAL path. `--repo` may name a symlink, which
#     `resolve_repo` preserves; context/refresh.md's probe independently asks
#     git for the toplevel. Both sides therefore key on `git rev-parse
#     --show-toplevel` — git reports the physical, symlink-resolved working
#     tree — so the probe always looks where the launcher wrote.
#   * Digested IN the target repository. `git hash-object` uses the object
#     format of whatever repository it resolves, so an UNSCOPED call keys on
#     the CALLER's format — and the launcher manages any repo `--repo` names,
#     from a cwd that is often somewhere else entirely. Against a SHA-256
#     checkout that produced a 40-hex SHA-1 key while the probe, which runs
#     inside that checkout, computed the 64-hex SHA-256 one: the marker landed
#     in a directory the probe never reads, silently disabling staleness
#     detection. `-C` puts both sides on the target's format.
#     The `-C` anchor is $REPO, not the hashed $top: resolve_repo guarantees
#     $REPO is an existing directory, while $top is a string git handed back
#     (or the $REPO fallback). Both sit in the same repository, so they share
#     an object format — but anchoring on a path that may not exist would fail
#     the digest into the "unkeyed" fallback below, collapsing every such repo
#     onto ONE key and undoing the injectivity this component exists for.
# Falls back to $REPO only when the directory is not a git repo at all, where
# the probe could not run anyway. Computed once per run.
REPO_MARKER_KEY=""
repo_marker_key() {
  if [[ -z "$REPO_MARKER_KEY" ]]; then
    local top
    top="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || top=""
    [[ -n "$top" ]] || top="$REPO"
    REPO_MARKER_KEY="$(printf '%s' "$top" | git -C "$REPO" hash-object --stdin 2>/dev/null)"
    [[ -n "$REPO_MARKER_KEY" ]] || REPO_MARKER_KEY="unkeyed"
  fi
  printf '%s' "$REPO_MARKER_KEY"
}

launch_commit_marker_path() {
  printf '%s/%s/%s-launch-commit' "$(resolve_data_dir)" "$(repo_marker_key)" "$1"
}

# Captures the repo HEAD once per start/restart invocation (after the
# pre-launch pull, if any ran). A hex-only `git rev-parse HEAD` value carries
# no injection risk; empty on failure (detached-HEAD-less/unresolvable repo),
# which downstream write_launch_commit_marker treats as "skip, don't write".
capture_launch_commit() {
  LAUNCH_COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || LAUNCH_COMMIT=""
}

# A launch that cannot record its own commit must not leave the PREVIOUS
# launch's marker on disk: the refresh probe would read that older commit as
# this session's launch point and keep reporting merges the session already
# consumed — indefinitely, since nothing later rewrites it. Removing it degrades
# the probe to its honest "no marker → skip" branch instead. Best-effort like
# the write itself: a failed removal only warns.
invalidate_launch_commit_marker() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  if rm -f "$path" 2>/dev/null; then
    err "  removed the previous launch's marker so the staleness probe skips rather than trusts it: $path"
  else
    err "  stale launch-commit marker could not be removed — the staleness probe will read an obsolete commit: $path"
  fi
}

# Writes the captured launch commit to <data-dir>/lanes/<name>-launch-commit.
# Best-effort and always returns 0: a marker write failure must never fail a
# lane that has already (or would already) launch — only warn on stderr. The
# caller passes the already-resolved marker path (launch_lane resolves it
# once per lane).
write_launch_commit_marker() {
  local path="$1"
  if [[ -z "$LAUNCH_COMMIT" ]]; then
    err "launch-commit marker skipped for $path: repo HEAD could not be resolved"
    invalidate_launch_commit_marker "$path"
    return 0
  fi
  if ! mkdir -p "$(dirname "$path")" 2>/dev/null || ! printf '%s\n' "$LAUNCH_COMMIT" >"$path" 2>/dev/null; then
    err "launch-commit marker write failed: $path"
    invalidate_launch_commit_marker "$path"
  fi
  return 0
}

# --- Session list (real CLI or fixture) --------------------------------------
# Loaded once, in the main shell, into SESSIONS_JSON — not lazily inside a
# `$(...)`/pipe subshell where an `exit` would only kill the subshell and leave
# the script's status at 0 (the same reason the --agents-json existence check
# lives in main). Loading once also gives every lane a single, consistent
# snapshot instead of re-shelling `claude agents --json` per lane.
#
# A genuine live-list failure must NOT be coerced to an empty list: doing so
# makes every lane look stopped, so a real `start` would relaunch lanes that are
# still alive (duplicate sessions) and `status` would report false "stopped".
# load_sessions therefore fails on a live error and main aborts — except under
# --dry-run, which mutates nothing, where previewing against an empty list is
# harmless and preserves the documented offline-dry-run behavior.
#
# `claude agents --json` (no --all) lists ACTIVE sessions only — interactive and
# running background; completed/terminal background sessions are excluded by the
# CLI (they surface only under --all, carrying a `state` like "done" rather than
# an active `status`). A name match here is therefore already a live-lane match.
# Do NOT add --all without also filtering terminal sessions out of this lookup.
SESSIONS_JSON=""

load_sessions() {
  local raw
  if [[ -n "$AGENTS_JSON_FILE" ]]; then
    raw="$(cat "$AGENTS_JSON_FILE")" || return 1
  else
    raw="$(claude agents --json)" || {
      ((DRY_RUN)) && {
        SESSIONS_JSON='[]'
        return 0
      }
      return 1
    }
  fi
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$raw" || return 1
  SESSIONS_JSON="$raw"
}

# sessionId of a running lane session with the given name (empty if none). If
# several match, the most recently started wins.
#
# Restricted to `kind == "background"`: lanes are always launched with `--bg`, so
# a lane is by construction a background session. An interactive window that
# happens to share a lane name (e.g. a hand-started `work`) is therefore never
# matched — never skipped by `start`, never handed to `claude stop`. Since a real
# lane is always background, this can only exclude non-lane sessions, never a live
# lane, so it cannot cause a duplicate launch.
running_session_id() {
  local name="$1"
  jq -r --arg n "$name" \
    '[ .[] | select(.name == $n and .kind == "background") ] | sort_by(.startedAt) | last | .sessionId // empty' \
    <<<"$SESSIONS_JSON"
}

# --- Per-lane field extraction ------------------------------------------------
# String lane field; "" when absent. The `//` alternative is falsy-triggered
# rather than presence-triggered, so "" would also be the answer for a
# non-string value — resolve_config rejects those at config time, which is what
# keeps "" here meaning exactly one thing: the field is absent.
lane_field() { jq -r --argjson i "$1" --arg k "$2" '.lanes[$i][$k] // ""' "$CONFIG"; }

# Structured (non-string) lane field, emitted as compact JSON; empty ONLY when
# the field is absent. Used for `settings`, whose value is a JSON object rather
# than a scalar. Presence is `has`, not `//`: the alternative operator fires on
# every falsy value, so a `"settings": false` yielded `empty` and reached bash
# as "" — indistinguishable from unset. validate_launch_inputs guards its type
# check on `[[ -n "$settings" ]]`, so that check was skipped entirely and
# launch_lane omitted `--settings` with no error at all. An explicit `null` is
# the JSON spelling of "no value" and still reads as absent; every other value,
# `false` included, now reaches the type check.
lane_json_field() {
  jq -c --argjson i "$1" --arg k "$2" \
    '.lanes[$i] as $l | if ($l | has($k)) and $l[$k] != null then $l[$k] else empty end' "$CONFIG"
}

# --- Lane-stop gate arming (#1784) --------------------------------------------
# The autonomy Stop-hook gate reads its per-session config from a launcher-armed
# record, never the bare environment (see the header). These helpers detect a
# lane's gate request in its settings object, arm the gate through autonomy's
# own helper, and inject the arm id into the lane's --settings.

# ONE definition of "a pluginConfigs entry that requested the gate": an autonomy
# key (bare or marketplace-qualified) whose OWN options.lane_stop_gate_enabled
# is true (boolean or "true"). Interpolated into every query below — a jq filter
# cannot ride in as a --arg — so detection, option extraction, and arm-id
# injection can never disagree about which entry asked. Settings may carry
# several autonomy installs, and an entry that did NOT ask must be left alone in
# all three: not read for options, and not handed an arm id. The gate never
# treats this channel as a trusted verdict in either direction, so the arm id is
# not overriding that entry's own `false` — the defect is narrower and still
# real: the launcher marks an install the lane never asked to arm, so the
# settings it hands to `claude` misdescribe what was requested and the record
# stops being a faithful account of which install the operator opted in.
GATE_ENTRY_REQUESTED='(.key == "autonomy" or (.key | startswith("autonomy@")))
       and (.value.options.lane_stop_gate_enabled | . == true or . == "true")'

lane_requests_stop_gate() {
  jq -e "[ (.pluginConfigs // {}) | to_entries[]
           | select($GATE_ENTRY_REQUESTED) ] | length > 0" >/dev/null 2>&1 <<<"$1"
}

# String-valued gate option from the lane's REQUESTING entries (last wins),
# prefixed `v:` so an EXPLICITLY EMPTY value survives the trip through bash.
# Empty is a meaningful verdict here, not an absence: a lane that sets
# lane_stop_gate_marker to "" is disabling the marker channel for this session,
# and an arm record carrying no marker key at all resolves the opposite way —
# the gate falls through to the user-level marker, where a leftover global
# marker file can authorize a stop the lane never signaled. Prints nothing at
# all when no requesting entry carries the option as a string.
gate_option_from_settings() {
  jq -r --arg k "$2" "
    [ (.pluginConfigs // {}) | to_entries[]
      | select($GATE_ENTRY_REQUESTED)
      | .value.options[\$k] | select(type == \"string\") | \"v:\" + . ] | last // empty" <<<"$1"
}

# Candidate arm helpers, one path per line. The override wins outright; default
# discovery anchors on THIS script's own install path under plugins/cache and
# globs every installed autonomy version — arming all of them is idempotent
# (same-marketplace versions share one data directory; a second marketplace's
# install keeps its own, and whichever install is active reads its own store).
# Deliberately NOT an env-derived walk (CLAUDE_CONFIG_DIR/HOME): the launcher
# runs inside a session whose project may be the watched repo itself, so a repo
# env block reaches this process — an env-derived path would let it misdirect
# arming into a store the real gate never reads, silently un-gating the lane.
# An unanchored dev checkout without the override finds nothing, and a
# gate-requesting lane then fails closed below.
find_gate_arm_scripts() {
  if [[ -n "$GATE_ARM_SCRIPT_OVERRIDE" ]]; then
    printf '%s\n' "$GATE_ARM_SCRIPT_OVERRIDE"
    return 0
  fi
  local self cache s
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 0
  [[ "$self" == */plugins/cache/*/*/* ]] || return 0
  cache="${self%%/plugins/cache/*}/plugins/cache"
  for s in "$cache"/*/autonomy/*/hooks/lane-stop-gate-arm.sh; do
    [[ -f "$s" ]] && printf '%s\n' "$s"
  done
  return 0
}

# A random, filename-safe arm id (the gate validates ^[A-Za-z0-9_-]{8,64}$).
generate_arm_id() {
  local id=""
  if [[ -r /dev/urandom ]] && command -v od >/dev/null 2>&1; then
    id="$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')"
  fi
  [[ -n "$id" ]] || id="$(date +%s 2>/dev/null)$$${RANDOM}${RANDOM}"
  printf '%s' "$id"
}

# Arm the gate for one lane and print the settings JSON with the arm id
# injected. Returns 1 (lane must be skipped — fail closed) when no helper is
# found or ANY found helper fails; helper stdout/stderr goes to stderr so it
# can never leak into the settings this function prints.
#
# EVERY discovered helper must arm. Each install writes into its OWN
# install-derived store, and the launcher cannot tell which install the session
# will load — so one helper succeeding does not prove the ACTIVE one is armed.
# Accepting a partial arm would launch a lane carrying an id its own gate
# resolves to nothing: ungated, with only a stale-arm notice to show for it.
arm_stop_gate() {
  local name="$1" settings="$2" arm_id sentinel marker script found=0 failed=0
  arm_id="$(generate_arm_id)"
  sentinel="$(gate_option_from_settings "$settings" lane_stop_gate_sentinel)"
  marker="$(gate_option_from_settings "$settings" lane_stop_gate_marker)"
  # The two options forward on DIFFERENT conditions, because the gate reads an
  # empty value differently for each. An empty marker disables the marker
  # channel, so `v:`-prefixed-and-empty is a verdict that must reach the record;
  # an empty sentinel is not a configured value at all — lane-stop-gate.sh
  # substitutes the default token for it — so recording one would buy nothing
  # while suppressing the record's fall-through to the user-level sentinel.
  local -a args=(--id "$arm_id" --cwd "$REPO")
  [[ "$sentinel" == v:?* ]] && args+=(--sentinel "${sentinel#v:}")
  [[ "$marker" == v:* ]] && args+=(--marker "${marker#v:}")
  while IFS= read -r script; do
    [[ -n "$script" ]] || continue
    found=1
    bash "$script" "${args[@]}" >&2 || failed=1
  done < <(find_gate_arm_scripts)
  if ((found == 0)); then
    # Normally unreachable: validate_launch_inputs preflights helper presence.
    err "lane '$name': lane-stop gate requested but no autonomy gate-arm helper was found (install/update the autonomy plugin, or pass --gate-arm-script) — skipped"
    return 1
  fi
  if ((failed)); then
    err "lane '$name': lane-stop gate arming failed — skipped (launching ungated would defeat the request)"
    return 1
  fi
  jq -c --arg id "$arm_id" \
    ".pluginConfigs |= with_entries(
       if $GATE_ENTRY_REQUESTED
       then .value.options.lane_stop_gate_arm_id = \$id else . end)" <<<"$settings"
}

# --- Execution target ---------------------------------------------------------
# The contract is docs/conventions/execution-target/README.md in the marketplace
# repository. The file is a policy floor: it is read only from origin's default
# branch after a fetch, never from the working tree, so an unmerged edit cannot
# move a lane. Everything read from it, from `gh`, or from a telemetry comment
# is data: values are checked against fixed sets before use and nothing from
# them is evaluated or used as an array subscript.
ET_FILE="docs/conventions/execution-target.yaml"
ET_VALUES="local-worktree local-background cloud-session cloud-routine cloud-project"
ET_READER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/parse-concern-value.sh"
ET_LOADED=0
ET_TEXT=""
ET_SHA=""
ET_REF=""
ET_NOTE=""
# Set by resolve_lane_target for the lane being launched.
LANE_TARGET=""
LANE_TARGET_KEY=""
LANE_WORKTREE=""

ET_SLUG=""
ET_REFUSED=0

# Stages whose input is always untrusted (raw intake). Such a stage resolves the
# class.untrusted-provenance key.
stage_input_always_untrusted() { [[ "$1" == "work-items:triage" ]]; }

# Stages whose input never includes untrusted content (the README table's
# "never" rows). Empty: every local-lane stage can read raw intake, a fork pull
# request or an untrusted-provenance item, and the X1 guard (no connector
# tools, failed egress) has no deterministic check yet, so the launcher itself
# refuses cloud-session for them. A lane with no `stage` or an unknown stage
# counts as untrusted: lanes.json is lane-writable.
ET_TRUSTED_STAGES=""
stage_may_read_untrusted() {
  [[ -n "$1" && " $ET_TRUSTED_STAGES " == *" $1 "* ]] && return 1
  return 0
}

# 0 when origin's URL is ambiguous (several remote.origin.url values) or a
# url.<base>.insteadOf / pushInsteadOf rule in any config scope rewrites it.
origin_url_rewritten() {
  local urls url entry value
  urls="$(git -C "$REPO" config --get-all remote.origin.url 2>/dev/null)" || return 1
  [[ "$urls" == *$'\n'* ]] && return 0
  url="$urls"
  # --null: a key holds the rewritten base, which may contain spaces.
  while IFS= read -r -d '' entry; do
    [[ "$entry" == *$'\n'* ]] || continue
    value="${entry#*$'\n'}"
    [[ -n "$value" && "$url" == "$value"* ]] && return 0
  done < <(git -C "$REPO" config --null --get-regexp '^url\..*\.(insteadof|pushinsteadof)$' 2>/dev/null)
  return 1
}

# owner/repo of origin, from its configured URL (the remote `claude --cloud`
# and the fetch use), lowercased; empty when it is not a github.com URL.
origin_slug() {
  local url slug
  url="$(git -C "$REPO" config --get remote.origin.url 2>/dev/null)" || return 0
  case "$url" in
  https://github.com/*) slug="${url#https://github.com/}" ;;
  git@github.com:*) slug="${url#git@github.com:}" ;;
  ssh://git@github.com/*) slug="${url#ssh://git@github.com/}" ;;
  *) return 0 ;;
  esac
  slug="${slug%/}"
  slug="${slug%.git}"
  [[ "$slug" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ && "$slug" != *..* ]] || return 0
  printf '%s' "$slug" | tr '[:upper:]' '[:lower:]'
}

# Plugins a stage needs loaded in a cloud session. Mirrors the required-plugin
# table in the contract README; change both together.
stage_required_plugins() {
  case "$1" in
  work-items:work-loop | work-items:work) printf 'work-items implementation source-control' ;;
  work-items:triage) printf 'work-items' ;;
  source-control:babysit-loop) printf 'source-control work-items' ;;
  source-control:babysit-prs) printf 'source-control' ;;
  *) printf '%s' "${1%%:*}" ;;
  esac
}

# Fetch origin's default branch once per run and keep the file text from that
# commit. Any failure leaves ET_TEXT empty, which resolves every lane to
# local-worktree; the reason is printed once.
load_execution_target() {
  ((ET_LOADED)) && return 0
  ET_LOADED=1
  local head branch sha remote_head
  head="$(git -C "$REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || head=""
  branch="${head#origin/}"
  if [[ "$head" != origin/* || ! "$branch" =~ ^[A-Za-z0-9._/-]+$ || "$branch" == *..* || "$branch" == -* ]]; then
    ET_NOTE="no origin default branch resolved; every lane launches local-worktree"
    info "execution-target: $ET_NOTE"
    return 0
  fi
  # The local origin/HEAD symref can go stale or be moved (`git remote
  # set-head`), so the remote's own HEAD decides the branch. This catches a
  # stale or moved symref; it is not a boundary against someone who can write
  # the checkout's git config, who could also point origin elsewhere. The two
  # cheap config checks below refuse the plain forms of that: a url.*.insteadOf
  # or pushInsteadOf rule that rewrites origin's URL, and more than one
  # remote.origin.url.
  if origin_url_rewritten; then
    ET_REFUSED=1
    ET_NOTE="origin's URL is rewritten by a url.*.insteadOf rule or remote.origin.url has more than one value; policy not read, every lane launches local-worktree and work-items:triage lanes are skipped"
    err "execution-target: $ET_NOTE"
    return 0
  fi
  remote_head="$(git -C "$REPO" ls-remote --symref origin HEAD 2>/dev/null |
    awk -F '\t' '$2 == "HEAD" && $1 ~ /^ref: refs\/heads\// { sub(/^ref: refs\/heads\//, "", $1); print $1; exit }')" || remote_head=""
  if [[ -z "$remote_head" || "$remote_head" != "$branch" ]]; then
    ET_REFUSED=1
    ET_NOTE="origin's HEAD could not be read or disagrees with the local origin/HEAD ($head); policy not read, every lane launches local-worktree and work-items:triage lanes are skipped"
    err "execution-target: $ET_NOTE"
    return 0
  fi
  ET_SLUG="$(origin_slug)"
  info "git fetch origin $branch ($REPO)"
  if ! run git -C "$REPO" fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/$branch"; then
    ET_NOTE="fetch of origin/$branch failed; every lane launches local-worktree"
    err "execution-target: $ET_NOTE"
    return 0
  fi
  sha="$(git -C "$REPO" rev-parse --verify --quiet --end-of-options "refs/remotes/origin/$branch^{commit}" 2>/dev/null)" || sha=""
  if [[ ! "$sha" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
    ET_NOTE="origin/$branch does not resolve to a commit; every lane launches local-worktree"
    err "execution-target: $ET_NOTE"
    return 0
  fi
  ET_SHA="$sha" ET_REF="origin/$branch"
  if ! ET_TEXT="$(git -C "$REPO" show --end-of-options "$sha:$ET_FILE" 2>/dev/null)"; then
    ET_TEXT=""
    ET_NOTE="$ET_FILE absent at $ET_REF $ET_SHA; every lane launches local-worktree"
    info "execution-target: $ET_NOTE"
    return 0
  fi
  # A file the parser rejects is not read as partial policy.
  if ! bash "$ET_READER" --strict - default >/dev/null 2>&1 <<<"$ET_TEXT"; then
    ET_TEXT=""
    ET_NOTE="$ET_FILE at $ET_REF $ET_SHA does not parse; every lane launches local-worktree"
    err "execution-target: $ET_NOTE"
    return 0
  fi
  info "execution-target: read $ET_FILE at $ET_REF $ET_SHA"
}

# Sets LANE_TARGET and LANE_TARGET_KEY for a lane's stage (may be empty).
resolve_lane_target() {
  local stage="$1" key v
  LANE_TARGET="local-worktree" LANE_TARGET_KEY="built-in default"
  [[ -n "$ET_TEXT" ]] || return 0
  local -a keys=()
  [[ -n "$stage" ]] && keys+=("skill.${stage%%:*}.${stage#*:}")
  [[ -n "$stage" ]] && stage_input_always_untrusted "$stage" && keys+=("class.untrusted-provenance")
  keys+=("default")
  for key in "${keys[@]}"; do
    v="$(bash "$ET_READER" - "$key" <<<"$ET_TEXT" 2>/dev/null)" || v=""
    [[ -n "$v" ]] || continue
    if [[ " $ET_VALUES " == *" $v "* ]]; then
      LANE_TARGET="$v" LANE_TARGET_KEY="$key"
    else
      err "execution-target: unknown value $(printf '%q' "$v") at $key in $ET_FILE at $ET_REF $ET_SHA; local-worktree"
      LANE_TARGET_KEY="$key (unknown value)"
    fi
    return 0
  done
}

# The lane's linked worktree, under the plugin data dir keyed like the
# launch-commit marker.
lane_worktree_path() { printf '%s/%s/worktrees/%s' "$(resolve_data_dir)" "$(repo_marker_key)" "$1"; }

# Prepare the lane's linked worktree at <sha>. With <require_clean> set, a
# worktree holding any change refuses (return 1); without it, a dirty
# worktree is used as it stands (a local lane's own work in progress).
ensure_lane_worktree() {
  local name="$1" sha="$2" require_clean="$3" path common_repo common_wt status
  path="$(lane_worktree_path "$name")"
  if [[ ! -e "$path" ]]; then
    ((DRY_RUN)) || mkdir -p "$(dirname "$path")" || return 1
    run git -C "$REPO" worktree add --quiet --detach "$path" "$sha" || return 1
    LANE_WORKTREE="$path"
    return 0
  fi
  common_repo="$(cd "$REPO" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || return 1
  common_wt="$(cd "$path" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || return 1
  if [[ -z "$common_repo" || "$common_repo" != "$common_wt" ]]; then
    err "lane '$name': $path is not a linked worktree of $REPO"
    return 1
  fi
  status="$(git -C "$path" status --porcelain --untracked-files=all 2>/dev/null)" || return 1
  if [[ -n "$status" ]]; then
    if ((require_clean)); then
      err "lane '$name': linked worktree $path has uncommitted or untracked changes"
      return 1
    fi
    info "  lane '$name': linked worktree has changes; launching from it as it stands"
  else
    run git -C "$path" checkout --quiet --detach "$sha" || return 1
  fi
  LANE_WORKTREE="$path"
}

# 0 when an installation of the Claude GitHub App (slug `claude`) reachable
# from the user's gh token covers the repository. Any read failure is a no:
# without the App, `claude --cloud` uploads a bundle of every local branch and
# uncommitted tracked changes instead of cloning.
claude_app_covers_repo() {
  # The slug comes from origin's URL, the remote `claude --cloud` clones from,
  # never from gh's default repository (which may be an upstream).
  local slug="$ET_SLUG" owner id selection login repos
  [[ -n "$slug" ]] || return 1
  owner="${slug%%/*}"
  local installs
  installs="$(gh api --paginate user/installations \
    --jq '.installations[] | select(.app_slug == "claude") | [(.id | tostring), .repository_selection, .account.login] | @tsv' 2>/dev/null)" || return 1
  while IFS=$'\t' read -r id selection login; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    login="$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')"
    if [[ "$selection" == "all" && "$login" == "$owner" ]]; then
      return 0
    fi
    if [[ "$selection" == "selected" ]]; then
      repos="$(gh api --paginate "user/installations/$id/repositories" --jq '.repositories[].full_name' 2>/dev/null)" || continue
      printf '%s\n' "$repos" | tr '[:upper:]' '[:lower:]' | grep -qxF -- "$slug" && return 0
    fi
  done <<<"$installs"
  return 1
}

# Bodies of the comments on the lane's telemetry issue written by an authorized
# author (the gh-authenticated login, or the lane's `telemetry.author`), as a
# JSON array. Prints the reason and returns 1 when the binding is incomplete or
# the read fails. A cloud lane needs an explicit numeric `telemetry.issue` in
# this repository: no title search, and a `telemetry.repo` naming another
# repository is refused. Bodies are parsed by jq only.
lane_telemetry_bodies() {
  local idx="$1" name="$2" repo issue raw me bot
  repo="$(jq -r --argjson i "$idx" '(.lanes[$i].telemetry // {}).repo // ""' "$CONFIG")"
  repo="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$repo" && "$repo" != "$ET_SLUG" ]]; then
    printf 'telemetry.repo names a repository other than origin (%s)' "${ET_SLUG:-unknown}"
    return 1
  fi
  repo="$ET_SLUG"
  [[ -n "$repo" ]] || {
    printf 'origin is not a github.com repository'
    return 1
  }
  issue="$(jq -r --argjson i "$idx" '(.lanes[$i].telemetry // {}).issue // "" | tostring' "$CONFIG")"
  [[ "$issue" =~ ^[0-9]+$ ]] || {
    printf 'the lane has no numeric telemetry.issue'
    return 1
  }
  bot="$(jq -r --argjson i "$idx" '(.lanes[$i].telemetry // {}).author // ""' "$CONFIG")"
  if [[ -n "$bot" && ! "$bot" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$ ]]; then
    printf 'telemetry.author is not a GitHub login'
    return 1
  fi
  # An app's bot account writes for every installation or workflow that holds
  # its token, pull request runs included, so it names no single writer. The
  # gh login never ends in [bot] (checked below), so no bot is the operator.
  if [[ "$(printf '%s' "$bot" | tr '[:upper:]' '[:lower:]')" == *"[bot]" ]]; then
    printf 'telemetry.author %s is a bot account, which is not allowed' "$bot"
    return 1
  fi
  me="$(gh api user --jq .login 2>/dev/null)" || me=""
  [[ "$me" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || {
    printf 'the gh-authenticated login could not be read'
    return 1
  }
  if [[ -n "$TELEMETRY_JSON_FILE" ]]; then
    warn "lane '$name': telemetry read from the local file $TELEMETRY_JSON_FILE (--telemetry-json, a test aid), not from GitHub"
    raw="$(jq -c --arg l "$name" '(.[$l] // [])[] | {body: (.body // ""), login: (.user.login // "")}' "$TELEMETRY_JSON_FILE" 2>/dev/null)" || {
      printf 'the telemetry fixture could not be read'
      return 1
    }
  else
    raw="$(gh api --paginate "repos/$repo/issues/$issue/comments?per_page=100" -q '.[] | {body: (.body // ""), login: (.user.login // "")}' 2>/dev/null)" || {
      printf 'the comments on #%s could not be read' "$issue"
      return 1
    }
  fi
  printf '%s' "$raw" | jq -s -c --arg me "$me" --arg bot "$bot" \
    '[ .[] | select(.login == $me or ($bot != "" and .login == $bot)) | .body ]' 2>/dev/null || {
    printf 'the telemetry comments could not be parsed'
    return 1
  }
}

# Prints the newest `execution_target_fallback` value (compact JSON, `null`
# when the lane's state block carries none) from the lane's authorized
# telemetry comments; on failure prints the reason and returns 1.
lane_fallback_value() {
  local idx="$1" name="$2" bodies marker
  bodies="$(lane_telemetry_bodies "$idx" "$name")" || {
    printf '%s' "$bodies"
    return 1
  }
  marker="$(jq -r --argjson i "$idx" '(.lanes[$i].telemetry // {}).marker // ""' "$CONFIG")"
  jq -r --arg m "$marker" '
    def blocks: [ scan("```[^\n]*\n((?:(?!```)[\\s\\S])*)```") | .[0] ];
    def state: [ blocks[] | (try fromjson catch null)
                 | select(type == "object" and has("execution_target_fallback")) ] | first;
    [ .[]
      | select(contains("<!-- harness-ops:lane-telemetry marker="))
      | select($m == "" or contains("marker=" + $m + " ") or contains("marker=" + $m + "@"))
      | state | select(. != null) | .execution_target_fallback ]
    | last // null | tojson' <<<"$bodies" 2>/dev/null || return 1
}

# The preamble a cloud-session lane's prompt opens with: the stage-start probe.
stage_probe_preamble() {
  local name="$1" stage="$2"
  local plugins
  plugins="$(stage_required_plugins "${stage:-unknown:unknown}")"
  cat <<PREAMBLE
Stage-start probe (execution target cloud-session; lane $name; stage ${stage:-unset}; policy read from $ET_REF at $ET_SHA via $LANE_TARGET_KEY). Do this before any other step:
1. Confirm each of these plugins is loaded in this session, not only declared: $plugins.
2. Confirm one read from the work-item tracker succeeds.
3. For a stage that merges, confirm the merge wrapper's read-only check passes.
4. Record in this lane's telemetry state block, under "execution_target_probe": the session's permission mode, whether any connector (MCP) tools are present, and whether a request to a host outside the Trusted network allowlist fails.
5. If step 1, 2 or 3 fails: set "execution_target_fallback" in the lane's telemetry state block to {"reason": "<what failed>", "at": "<UTC time>"}; for a per-item stage also put the marker comment <!-- execution-target:fallback v1 --> on the item and clear its in-flight mark; claim nothing and stop. The next launch runs this lane local-worktree.
6. If every step passes, set "execution_target_fallback" to null and continue with the lane prompt below.
7. Before reading untrusted input (raw intake, a pull request from a fork, an untrusted-provenance item): continue only when no connector tools are present and the step 4 egress request failed. Otherwise do not read it and do not fall back to a local host: stop, record the reason in the lane telemetry, and leave the item for /work-items:attend-queue.

PREAMBLE
}

# Per-lane fallback record: the hash of the fallback value already honored, so
# one fallback moves exactly one launch to the local host.
lane_fallback_record_path() { printf '%s/%s/%s-execution-target-fallback' "$(resolve_data_dir)" "$(repo_marker_key)" "$1"; }
# Per-lane cloud launch record: `claude agents --json` does not list cloud
# sessions, so `start` reads this to avoid a second cloud session per run.
lane_cloud_record_path() { printf '%s/%s/%s-cloud-launch' "$(resolve_data_dir)" "$(repo_marker_key)" "$1"; }

write_record() { # <path> <content>
  ((DRY_RUN)) && {
    printf 'DRY-RUN: write %s\n' "$1"
    return 0
  }
  if ! { mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" >"$1"; } 2>/dev/null; then
    err "could not write $1"
  fi
  return 0
}

# Print the setup steps for a host the launcher does not start.
print_setup_steps() {
  local name="$1" stage="$2" target="$3" prompt_path="$4"
  info "  lane '$name': $target is set by $LANE_TARGET_KEY ($ET_REF $ET_SHA); the launcher starts nothing for it."
  case "$target" in
  cloud-routine)
    info "    1. At claude.ai, create a routine for this repository whose prompt is $prompt_path."
    info "    2. Remove every connector from the routine; the contract's row for stage ${stage:-unset} lists none it may carry."
    info "    3. Give it its own trigger (schedule or GitHub event). The launcher holds no routine token."
    ;;
  cloud-project)
    info "    1. Install the Claude GitHub App on this repository if it is not installed."
    info "    2. At claude.ai, add the repository to a project and start a thread whose first message is $prompt_path."
    ;;
  *) ;;
  esac
  info "    A local session of this lane is left as it is; stop it with \`stop $name\` once the new host runs."
}

# --- Command runner -----------------------------------------------------------
# Echoes the command; runs it unless --dry-run.
run() {
  if ((DRY_RUN)); then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# --- Lane launch --------------------------------------------------------------
# Validates a lane's launch inputs (prompt present + non-empty, effort set + allowed);
# returns 1 with a per-lane error on the first failure. Split out from launch_lane
# so restart can preflight these BEFORE stopping a running lane — a recoverable
# prompt/effort error must not take a healthy session down and fail to relaunch it.
validate_launch_inputs() {
  local name="$1" effort="$2" prompt_path="$3" settings="${4:-}"
  if [[ ! -f "$prompt_path" ]]; then
    err "lane '$name': prompt file not found: $prompt_path — skipped"
    return 1
  fi
  if [[ ! -s "$prompt_path" ]]; then
    err "lane '$name': prompt file is empty: $prompt_path — skipped"
    return 1
  fi
  if [[ -z "$effort" ]]; then
    err "lane '$name': no effort set — add lanes[].effort, chosen from the \"Choose an effort level\" table at $EFFORT_TABLE_URL — skipped"
    return 1
  fi
  if [[ " $VALID_EFFORTS " != *" $effort "* ]]; then
    err "lane '$name': invalid effort '$effort' (want: $VALID_EFFORTS) — skipped"
    return 1
  fi
  if [[ "$effort" == "ultracode" ]]; then
    # The same exemption require_claude documents: a dry run must preview with no
    # CLI installed. With no binary to probe the gate cannot be evaluated, so the
    # preview says so rather than refusing a lane a real run may well launch. Keyed
    # on the binary's absence, not on an "unknown" version — a CLI whose --version
    # is unparsable is installed, and stays refused.
    if ((DRY_RUN)) && ! command -v claude >/dev/null 2>&1; then
      info "  lane '$name': effort 'ultracode' version gate not evaluated (no claude CLI to probe)"
    else
      cli_version
      if ! version_at_least "$CLI_VERSION_CACHE" "$ULTRACODE_MIN_VERSION"; then
        err "lane '$name': effort 'ultracode' needs Claude Code >= $ULTRACODE_MIN_VERSION (installed: $CLI_VERSION_CACHE) — skipped"
        return 1
      fi
    fi
  fi
  # `settings` must be a JSON object — the launcher passes it verbatim to
  # `claude --settings`, and a string/array/scalar would make the whole session
  # fail to launch with an opaque CLI error instead of a per-lane skip here.
  if [[ -n "$settings" ]] && ! jq -e 'type == "object"' <<<"$settings" >/dev/null 2>&1; then
    err "lane '$name': settings must be a JSON object — skipped"
    return 1
  fi
  # A gate request with no discoverable arm helper is a launch-input error too,
  # and it belongs HERE so restart's preflight catches it BEFORE stopping a
  # healthy running lane (same doctrine as the prompt/effort checks above). A
  # helper that exists but fails at arm time still surfaces in launch_lane.
  # Command substitution, NOT `find_gate_arm_scripts | grep -q .`: under
  # pipefail, grep -q exits on the first line and the producer takes SIGPIPE on
  # its next write, so a machine carrying TWO autonomy installs would read as
  # "no helper found" and refuse to launch a gate-requesting lane.
  if [[ -n "$settings" ]] && lane_requests_stop_gate "$settings" &&
    [[ -z "$(find_gate_arm_scripts)" ]]; then
    err "lane '$name': lane-stop gate requested but no autonomy gate-arm helper was found (install/update the autonomy plugin, or pass --gate-arm-script) — skipped"
    return 1
  fi
}

launch_lane() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" settings="${5:-}" cwd="${6:-$REPO}"
  validate_launch_inputs "$name" "$effort" "$prompt_path" "$settings" || return 1

  # Arm the lane-stop gate BEFORE launching (fail closed — see header). Under
  # --dry-run nothing is written; the preview line stands in for the arming.
  if [[ -n "$settings" ]] && lane_requests_stop_gate "$settings"; then
    if ((DRY_RUN)); then
      printf 'DRY-RUN: arm lane-stop gate for %s (arm id injected into --settings)\n' "$name"
    else
      settings="$(arm_stop_gate "$name" "$settings")" || return 1
    fi
  fi

  # Explicit auto: a Manual defaultMode would stall an unattended lane at its
  # first prompt. Never bypassPermissions. --permission-prompts none is added
  # from Claude Code 2.1.259; older CLIs reject it. What it does in a --bg lane
  # is unprobed: see the Record in SKILL.md.
  local -a cmd=(claude --bg -n "$name" --permission-mode auto)
  cli_version
  if version_at_least "$CLI_VERSION_CACHE" "$PERMISSION_PROMPTS_MIN_VERSION"; then
    cmd+=(--permission-prompts none)
  fi
  [[ -n "$model" ]] && cmd+=(--model "$model")
  cmd+=(--effort "$effort")
  [[ -n "$settings" ]] && cmd+=(--settings "$settings")

  local marker_path
  marker_path="$(launch_commit_marker_path "$name")"

  if ((DRY_RUN)); then
    # Keep the seeded prompt out of the echoed command — show a size placeholder.
    local bytes
    bytes="$(wc -c <"$prompt_path" | tr -d ' ')"
    [[ "$cwd" == "$REPO" ]] || printf 'DRY-RUN: cd %q\n' "$cwd"
    printf 'DRY-RUN:'
    printf ' %q' "${cmd[@]}"
    printf ' %q\n' "<prompt: $prompt_path (${bytes}B)>"
    printf 'DRY-RUN: write launch-commit marker %s <- %s\n' "$marker_path" "${LAUNCH_COMMIT:-<unresolved>}"
    return 0
  fi

  local prompt
  prompt="$(cat "$prompt_path")"
  cmd+=("$prompt")
  (cd "$cwd" && "${cmd[@]}") || return 1
  # Best-effort: a marker write failure must not fail an already-launched lane.
  write_launch_commit_marker "$marker_path"
}

# Returns: 0 stopped OK · 2 was not running · other = `claude stop` failed
# (its exit code). Callers must distinguish 2 (benign) from a real stop failure.
stop_lane_if_running() {
  local name="$1" sid
  sid="$(running_session_id "$name")"
  [[ -n "$sid" ]] || return 2
  info "  stop $name ($sid)"
  run claude stop "$sid"
}

# Launch one lane on the host its execution target names (LANE_TARGET, already
# resolved). <action> is start or restart: `start` leaves a lane already sent to
# the cloud alone, `restart` sends a new one.
launch_on_target() {
  local idx="$1" name="$2" model="$3" effort="$4" prompt_path="$5" settings="$6" stage="$7" action="$8"
  case "$LANE_TARGET" in
  local-background)
    validate_launch_inputs "$name" "$effort" "$prompt_path" "$settings" || return 1
    if ensure_lane_worktree "$name" "$ET_SHA" 0; then
      launch_lane "$name" "$model" "$effort" "$prompt_path" "$settings" "$LANE_WORKTREE"
    else
      err "lane '$name': no usable linked worktree; launching local-worktree"
      launch_lane "$name" "$model" "$effort" "$prompt_path" "$settings"
    fi
    ;;
  cloud-session) launch_cloud_lane "$@" ;;
  *) launch_lane "$name" "$model" "$effort" "$prompt_path" "$settings" ;;
  esac
}

# A cloud launch that cannot meet the cloud launch rule runs local-worktree,
# except for a stage whose input is always untrusted: it is not run locally.
# The error a lane whose stage may read untrusted input gets in place of a
# cloud or local launch. It names the escalation route; it files nothing.
untrusted_skip() { # <name> <stage> <why>
  err "lane '$1': $3; stage ${2:-unset} may read untrusted input, so it does not run on a cloud host or fall back to a local one: skipped. Nothing was filed; escalate it through /work-items:attend-queue."
  return 1
}

refuse_cloud() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" settings="$5" stage="$6" reason="$7"
  if stage_may_read_untrusted "$stage"; then
    untrusted_skip "$name" "$stage" "cloud-session refused ($reason)"
    return 1
  fi
  err "lane '$name': cloud-session refused ($reason); launching local-worktree"
  launch_lane "$name" "$model" "$effort" "$prompt_path" "$settings"
}

launch_cloud_lane() {
  local idx="$1" name="$2" model="$3" effort="$4" prompt_path="$5" settings="$6" stage="$7" action="$8"
  local -a base=("$name" "$model" "$effort" "$prompt_path" "$settings" "$stage")
  validate_launch_inputs "$name" "$effort" "$prompt_path" "$settings" || return 1

  # The X1 guard (no connector tools, failed egress) has no deterministic check
  # yet, so a stage that may read untrusted input never goes to the cloud. The
  # probe preamble repeats the guard as a second line of defense.
  if stage_may_read_untrusted "$stage"; then
    untrusted_skip "$name" "$stage" "cloud-session refused (the launcher cannot yet check for connector tools and denied egress)"
    return 1
  fi

  local fallback hash recorded record cloud_record
  record="$(lane_fallback_record_path "$name")"
  cloud_record="$(lane_cloud_record_path "$name")"
  if ! fallback="$(lane_fallback_value "$idx" "$name")"; then
    refuse_cloud "${base[@]}" "lane telemetry could not be read: ${fallback:-unknown reason}; a probe fallback could not reach this launcher"
    return
  fi
  if [[ "$fallback" != "null" ]]; then
    hash="$(printf '%s' "$fallback" | git -C "$REPO" hash-object --stdin 2>/dev/null)" || hash=""
    recorded="$(cat "$record" 2>/dev/null)" || recorded=""
    if [[ -n "$hash" && "$hash" != "$recorded" ]]; then
      info "  lane '$name': telemetry carries an execution-target fallback; this launch runs local-worktree"
      write_record "$record" "$hash"
      if [[ -e "$cloud_record" ]]; then
        if ((DRY_RUN)); then printf 'DRY-RUN: remove %s\n' "$cloud_record"; else rm -f "$cloud_record"; fi
      fi
      launch_lane "$name" "$model" "$effort" "$prompt_path" "$settings"
      return
    fi
  fi
  if [[ "$action" == "start" && -e "$cloud_record" ]]; then
    info "  skip $name: already sent to the cloud ($(head -n 1 "$cloud_record" 2>/dev/null | tr -cd '[:print:]')); restart sends a new session"
    return 0
  fi
  if [[ -n "$settings" ]] && lane_requests_stop_gate "$settings"; then
    refuse_cloud "${base[@]}" "the lane requests the lane-stop gate, which cannot be armed in a cloud session"
    return
  fi
  if ! claude_app_covers_repo; then
    refuse_cloud "${base[@]}" "no Claude GitHub App installation covering this repository was found through gh api user/installations"
    return
  fi
  if ! ensure_lane_worktree "$name" "$ET_SHA" 1; then
    refuse_cloud "${base[@]}" "no clean linked worktree at $ET_REF $ET_SHA"
    return
  fi

  if ((DRY_RUN)); then
    local bytes
    bytes="$(wc -c <"$prompt_path" | tr -d ' ')"
    printf 'DRY-RUN: cd %q\n' "$LANE_WORKTREE"
    printf 'DRY-RUN: claude --cloud %q\n' "<stage-start probe preamble + prompt: $prompt_path (${bytes}B)>"
    write_record "$cloud_record" "$(date -u +%Y-%m-%dT%H:%M:%SZ) at $ET_SHA"
    return 0
  fi
  local prompt
  prompt="$(stage_probe_preamble "$name" "$stage")$(cat "$prompt_path")"
  (cd "$LANE_WORKTREE" && claude --cloud "$prompt") || return 1
  write_record "$cloud_record" "$(date -u +%Y-%m-%dT%H:%M:%SZ) at $ET_SHA"
}

# --- Refresh step (pull + marketplace update) --------------------------------
refresh_repo_and_plugins() {
  local rc=0
  if ((NO_PULL)); then
    info "skip git pull (--no-pull)"
  else
    info "git pull --ff-only ($REPO)"
    run git -C "$REPO" pull --ff-only || rc=1
  fi
  # Capture HEAD for the launch-commit marker (#792) regardless of --no-pull —
  # a skipped pull still leaves a well-defined HEAD to record. A pure read
  # (`git rev-parse HEAD`), so it runs under --dry-run too: dry-run's `run`
  # wrapper never actually pulled, so this reports the pre-existing HEAD in
  # the preview line below without writing anything to disk.
  capture_launch_commit
  if ((NO_UPDATE)); then
    info "skip plugin marketplace update (--no-update)"
  else
    info "claude plugin marketplace update"
    run claude plugin marketplace update || rc=1
  fi
  # A skipped step (--no-pull/--no-update) leaves rc=0, so this only fires on an
  # UNEXPECTED failure of a step that actually ran — the intentional-bypass path
  # stays clean. Callers abort the launch on non-zero (see action_start/restart).
  ((rc)) && err "refresh failed (pass --no-pull/--no-update to skip refresh intentionally)"
  return "$rc"
}

# --- Target validation --------------------------------------------------------
# Reject any explicit TARGET_LANES name absent from the config. Called from main
# ahead of action dispatch so an invalid target fails fast (exit 3) BEFORE any
# refresh/mutation runs — matching stop's fail-first DX rather than pulling the
# repo and updating plugins only to reject a misspelled target afterward.
validate_target_lanes() {
  ((${#TARGET_LANES[@]})) || return 0
  local t known
  for t in "${TARGET_LANES[@]}"; do
    known="$(jq -r --arg n "$t" '[.lanes[].name] | index($n) // "no"' "$CONFIG")"
    [[ "$known" != "no" ]] || {
      err "unknown lane '$t' (not in $CONFIG)"
      exit 3
    }
  done
}

# --- Lane iteration helper ----------------------------------------------------
# Runs `callback <name> <model> <effort> <prompt_path> <settings>` for every
# lane, or only the lanes named in TARGET_LANES. Target names are validated up
# front by validate_target_lanes (called from main), so every name here is
# already known.
for_each_lane() {
  local callback="$1" pdir
  pdir="$(resolve_prompt_dir)"
  local count
  count="$(jq -r '.lanes | length' "$CONFIG")"

  local i name model effort prompt_path settings stage failures=0
  for ((i = 0; i < count; i++)); do
    name="$(lane_field "$i" name)"
    [[ -n "$name" ]] || {
      err "config lane #$i has no name"
      exit 3
    }
    if ((${#TARGET_LANES[@]})); then
      printf '%s\n' "${TARGET_LANES[@]}" | grep -qxF "$name" || continue
    fi
    model="$(lane_field "$i" model)"
    effort="$(lane_field "$i" effort)"
    prompt_path="$(path_under "$pdir" "$(lane_field "$i" prompt)")"
    settings="$(lane_json_field "$i" settings)"
    stage="$(lane_field "$i" stage)"
    # A per-lane callback failure must not abort the sweep (other lanes still
    # get their turn) but must surface in the aggregate exit status.
    "$callback" "$name" "$model" "$effort" "$prompt_path" "$settings" "$i" "$stage" || failures=1
  done
  return "$failures"
}

# --- Actions ------------------------------------------------------------------
# Resolve the lane's execution target and say which key supplied it.
plan_lane_target() {
  local name="$1" stage="$2"
  load_execution_target
  resolve_lane_target "$stage"
  [[ -n "$ET_TEXT" ]] && info "  $name: execution target $LANE_TARGET ($LANE_TARGET_KEY)"
  # A refused policy read (origin's HEAD unreadable or disagreeing) may be
  # tampering; a stage whose input is always untrusted then does not run.
  if ((ET_REFUSED)) && [[ -n "$stage" ]] && stage_input_always_untrusted "$stage"; then
    untrusted_skip "$name" "$stage" "the execution-target policy could not be read safely"
    return 1
  fi
  # No cloud host takes a stage that may read untrusted input. Refusing here,
  # before restart stops the running session, keeps a refused lane up.
  case "$LANE_TARGET" in
  cloud-session)
    if stage_may_read_untrusted "$stage"; then
      untrusted_skip "$name" "$stage" "cloud-session refused (the launcher cannot yet check for connector tools and denied egress)"
      return 1
    fi
    ;;
  cloud-routine | cloud-project)
    if stage_may_read_untrusted "$stage"; then
      untrusted_skip "$name" "$stage" "$LANE_TARGET refused"
      return 1
    fi
    ;;
  *) ;;
  esac
  return 0
}

_start_one() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" settings="${5:-}" idx="${6:-0}" stage="${7:-}" sid
  sid="$(running_session_id "$name")"
  if [[ -n "$sid" ]]; then
    info "  skip $name — already running ($sid)"
    return 0
  fi
  plan_lane_target "$name" "$stage" || return 1
  case "$LANE_TARGET" in
  cloud-routine | cloud-project)
    print_setup_steps "$name" "$stage" "$LANE_TARGET" "$prompt_path"
    return 0
    ;;
  *) ;;
  esac
  info "  start $name${model:+ --model $model}${effort:+ --effort $effort}${settings:+ --settings <lane config>}"
  launch_on_target "$idx" "$name" "$model" "$effort" "$prompt_path" "$settings" "$stage" start
}

_restart_one() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" settings="${5:-}" idx="${6:-0}" stage="${7:-}"
  # Preflight the launch inputs BEFORE stopping: a recoverable prompt/effort
  # error must not take down a healthy running lane we would then fail to relaunch.
  validate_launch_inputs "$name" "$effort" "$prompt_path" "$settings" || return 1
  # A host the launcher does not start leaves the running lane up as well.
  plan_lane_target "$name" "$stage" || return 1
  case "$LANE_TARGET" in
  cloud-routine | cloud-project)
    print_setup_steps "$name" "$stage" "$LANE_TARGET" "$prompt_path"
    return 0
    ;;
  *) ;;
  esac
  stop_lane_if_running "$name"
  local s=$?
  # A genuine stop failure (not the benign "was not running", 2) means the old
  # session may still be alive — relaunching would create a second session under
  # the same name, so refuse and surface the failure.
  if [[ $s -ne 0 && $s -ne 2 ]]; then
    err "  $name — stop failed; not relaunching (would duplicate the session name)"
    return 1
  fi
  info "  start $name${model:+ --model $model}${effort:+ --effort $effort}${settings:+ --settings <lane config>}"
  launch_on_target "$idx" "$name" "$model" "$effort" "$prompt_path" "$settings" "$stage" restart
}

_stop_one() {
  local name="$1"
  stop_lane_if_running "$name"
  case $? in
  0) : ;;
  2) info "  $name — not running" ;;
  *)
    err "  $name — stop failed"
    return 1
    ;;
  esac
}

_status_one() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" sid state="stopped"
  sid="$(running_session_id "$name")"
  [[ -n "$sid" ]] && state="running"
  local pflag=""
  [[ -f "$prompt_path" ]] || pflag=" [prompt MISSING]"
  printf '  %-12s %-8s %-8s %-8s %s%s\n' \
    "$name" "${model:-–}" "${effort:-–}" "$state" "${sid:-–}" "$pflag"
}

# We treat a set variable as able to override every lane's --effort and every agent
# pin, so a set value is said once. Pointer: for its precedence, see the
# CLAUDE_CODE_EFFORT_LEVEL row at https://code.claude.com/docs/en/env-vars#variables.
# As of: 2026-10-02. Recheck trigger: that row's precedence changes.
warn_effort_env_override() {
  [[ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]] || return 0
  warn "CLAUDE_CODE_EFFORT_LEVEL=$CLAUDE_CODE_EFFORT_LEVEL is set and every lane inherits it; it may override lane --effort values and agent effort pins, so those may not hold"
}

# scope suffix for the header line, e.g. " (work babysit)" when lanes are named.
lane_scope() { ((${#TARGET_LANES[@]})) && printf ' (%s)' "${TARGET_LANES[*]}"; }

action_start() {
  local rc=0
  info "== lanes: start =="
  warn_effort_env_override
  # A failed refresh aborts BEFORE launching: never seed lanes from stale
  # repo/plugin state the user did not sign off on (--no-pull/--no-update is the
  # intentional-skip path, which leaves the refresh status 0).
  refresh_repo_and_plugins || return 1
  info "lanes:"
  for_each_lane _start_one || rc=1
  return "$rc"
}

action_restart() {
  local rc=0
  info "== lanes: restart$(lane_scope) =="
  warn_effort_env_override
  refresh_repo_and_plugins || return 1
  info "lanes:"
  for_each_lane _restart_one || rc=1
  return "$rc"
}

action_stop() {
  info "== lanes: stop$(lane_scope) =="
  for_each_lane _stop_one
}

action_status() {
  info "== lanes: status =="
  printf '  %-12s %-8s %-8s %-8s %s\n' "LANE" "MODEL" "EFFORT" "STATE" "SESSION"
  for_each_lane _status_one
}

# --- Main ---------------------------------------------------------------------
main() {
  parse_args "$@"
  require_jq
  require_claude
  resolve_repo
  resolve_config
  # Validate explicit targets up front — before session load and, crucially,
  # before any action's refresh step mutates the repo/plugin state.
  validate_target_lanes
  [[ -z "$AGENTS_JSON_FILE" || -f "$AGENTS_JSON_FILE" ]] || {
    err "agents-json file not found: $AGENTS_JSON_FILE"
    exit 4
  }
  load_sessions || {
    if [[ -n "$AGENTS_JSON_FILE" ]]; then
      err "agents-json file is not a JSON array: $AGENTS_JSON_FILE"
    else
      err "could not list sessions: 'claude agents --json' failed — aborting so start/stop never act on fabricated state"
    fi
    exit 4
  }
  case "$ACTION" in
  start) action_start ;;
  restart) action_restart ;;
  status) action_status ;;
  stop) action_stop ;;
  *)
    err "unknown action: $ACTION (want: start restart status stop)"
    exit 3
    ;;
  esac
}

main "$@"
