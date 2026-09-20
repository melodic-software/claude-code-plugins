#!/usr/bin/env bash
# cutover-check.sh — may the `@AGENTS.md` CLAUDE.md shims come out yet?
#
# Read-only. It probes each graded cutover condition, prints [MET], [UNMET] or
# [UNREACH] with the evidence the verdict rests on, and exits non-zero unless
# every graded condition is [MET]. Nothing here writes to a repository; the
# removal is `remove-shims.sh`, which refuses without a passing run of this.
#
# The graded conditions, and what each reads:
#
#   1  Native AGENTS.md reading no longer depends on the remote flag: the
#      shipped bundle's code default for the flag is true, OR the env-vars page
#      no longer lists AGENTS.md under "Features that need feature-flag
#      fetching". Either one alone is enough; neither is [UNMET].
#   2  Every `claude-code-action` pin in every named repository installs a CLI
#      at or above the floor, and a CI canary with a lone AGENTS.md is on
#      record. Both clauses hold, or the condition does not.
#   3  A token canary with a lone non-empty AGENTS.md returns its line from a
#      cwd under home AND from a cwd on a second drive or path. One metered
#      `claude -p` turn per leg, in a scratch directory this script creates and
#      removes.
#   4  No named repository locates a path by the existence of CLAUDE.md, except
#      where a reviewed acknowledgement file says why that row is harmless.
#
# Every upstream number it compares against (the CLI floor, the action release
# to CLI map, the CI canary run) is parsed from `reference/sources.md`, which
# carries the four-part dated record for each. Parsing is fail-hard: a record
# this script cannot read is a fact it must not silently skip checking.
#
# Usage:
#   cutover-check.sh --repo <dir> [--repo <dir> ...] [options]
#   cutover-check.sh --help
#
# Exit: 0 every graded condition [MET]; 1 any other verdict; 2 usage or an
# unparsable record.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_MIGRATION="$SCRIPT_DIR/plan-migration.sh"
SOURCES_MD="$SCRIPT_DIR/../reference/sources.md"

FLAG_NAME="tengu_agents_md_mod"
ENV_VARS_URL="https://code.claude.com/docs/en/env-vars.md"
ENV_VARS_HEADING="## Features that need feature-flag fetching"

# Bytes read either side of a flag-string occurrence. The declaration and the
# export sit within a few hundred bytes of it on the builds seen so far; the
# window is wide enough to survive a re-minification that moves them apart and
# small enough that every occurrence is cheap to scan.
BUNDLE_WINDOW=2000

BUNDLE=""
ENV_VARS_FILE=""
CLAUDE_BIN="claude"
CANARY_HOME_ROOT=""
CANARY_ALT_ROOT=""
SKIP_CANARY=0
REPOS=()

usage() {
  cat <<'EOF'
cutover-check.sh — may the `@AGENTS.md` CLAUDE.md shims come out yet?

Usage: cutover-check.sh --repo <dir> [--repo <dir> ...] [options]

  --repo <dir>              a repository to check; repeatable, at least one
                            required. There is no current-directory default: a
                            cutover is a fleet decision, not a cwd accident
  --bundle <path>           the Claude Code bundle to read the flag's code
                            default from (default: `claude` on PATH)
  --env-vars-file <path>    read the env-vars page from this file instead of
                            fetching it
  --sources <path>          the four-part records to compare against
                            (default: ../reference/sources.md)
  --claude-bin <path>       the CLI the condition-3 canary runs (default: claude)
  --canary-home-root <dir>  where the home-cwd canary makes its scratch
                            directory (default: $HOME/.cache)
  --canary-alt-root <dir>   where the second-path canary makes its scratch
                            directory (default: D:/scratch where a D: drive
                            exists, else $TMPDIR)
  --skip-canary             do not run condition 3; it reports [UNREACH]
  --help                    this message

Each graded condition prints [MET], [UNMET] or [UNREACH] with its evidence.
[UNREACH] is never a pass: a probe that could not measure is not a condition
that holds.

Exit: 0 every graded condition [MET], 1 any other verdict, 2 usage or an
unparsable record in sources.md.
EOF
}

need_arg() {
  [[ $2 -ge 2 ]] || {
    echo "cutover-check: $1 needs a value" >&2
    exit 2
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --repo)
    need_arg "$1" $#
    REPOS+=("$2")
    shift 2
    ;;
  --bundle)
    need_arg "$1" $#
    BUNDLE="$2"
    shift 2
    ;;
  --env-vars-file)
    need_arg "$1" $#
    ENV_VARS_FILE="$2"
    shift 2
    ;;
  --sources)
    need_arg "$1" $#
    SOURCES_MD="$2"
    shift 2
    ;;
  --claude-bin)
    need_arg "$1" $#
    CLAUDE_BIN="$2"
    shift 2
    ;;
  --canary-home-root)
    need_arg "$1" $#
    CANARY_HOME_ROOT="$2"
    shift 2
    ;;
  --canary-alt-root)
    need_arg "$1" $#
    CANARY_ALT_ROOT="$2"
    shift 2
    ;;
  --skip-canary)
    SKIP_CANARY=1
    shift
    ;;
  *)
    echo "cutover-check: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

[[ ${#REPOS[@]} -gt 0 ]] || {
  echo "cutover-check: at least one --repo is required" >&2
  exit 2
}
# A repeated --repo grades the same tree twice and inflates every count, which
# reads as broader coverage than the run had. The comparison is on the
# repository each path RESOLVES to, not on the string: `X` and `X/` and
# `X/sub` are one tree, and the plan climbs to the toplevel anyway.
REPO_KEYS=()
for i in "${!REPOS[@]}"; do
  key="$(cd "${REPOS[$i]}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  REPO_KEYS+=("${key:-${REPOS[$i]}}")
done
for i in "${!REPO_KEYS[@]}"; do
  for j in "${!REPO_KEYS[@]}"; do
    ((j > i)) || continue
    [[ "${REPO_KEYS[$i]}" != "${REPO_KEYS[$j]}" ]] || {
      echo "cutover-check: ${REPOS[$i]} and ${REPOS[$j]} are the same repository" >&2
      exit 2
    }
  done
done
[[ -f "$SOURCES_MD" ]] || {
  echo "cutover-check: cannot read records: $SOURCES_MD" >&2
  exit 2
}

met() { printf '  [MET]     %s\n' "$1"; }
unmet() { printf '  [UNMET]   %s\n' "$1"; }
unreach() { printf '  [UNREACH] %s\n' "$1"; }
note() { printf '            %s\n' "$1"; }

trim() {
  local s="${1%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# A source line may carry a literal tab, and the acknowledgement file is
# tab-separated, so such a row could never be written down. Both sides see the
# tab as a space: a tab-versus-space difference is not a code change worth
# re-reviewing, and a row nobody can acknowledge is a row that fails closed
# forever.
normalize_text() { printf '%s' "$(trim "$1")" | tr '\t' ' '; }

# The body of one `## ` section of the records file. Line endings are stripped
# before the heading is matched, not after: a CRLF checkout of this file would
# otherwise match no heading at all and make every record unparsable.
section() {
  tr -d '\r' <"$SOURCES_MD" | awk -v h="$1" '$0 == h { f = 1; next } f && /^## / { exit } f'
}

# A record this script cannot read is a fact it must not skip verifying.
require() {
  [[ -n "$2" ]] || {
    echo "cutover-check: cannot parse $1 from $SOURCES_MD" >&2
    exit 2
  }
  printf '%s' "$2"
}

# --- the records ----------------------------------------------------------
CLI_FLOOR="$(require "the CLI floor" \
  "$(section '## The minimum CLI version' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | tr -d 'v')")"
# shellcheck disable=SC2016 # the backticks are markdown in the record, not a command substitution
CI_CANARY_RUN="$(require "the CI canary run id" \
  "$(section '## The CI canary' | grep -oE 'run `[0-9]{6,}`' | head -n 1 | tr -d 'run `')")"
CI_CANARY_ASOF="$(section '## The CI canary' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -n 1)"

ACTION_MAP="$(mktemp)"
# shellcheck disable=SC2016 # the backticks are markdown in the record's heading
section '## `claude-code-action` release to installed CLI version' |
  awk -F'|' '/^\| `v/ { gsub(/[ `]/, "", $2); gsub(/[ `]/, "", $3); gsub(/[ `]/, "", $4);
                        print $2 "\t" $3 "\t" $4 }' >"$ACTION_MAP"
[[ -s "$ACTION_MAP" ]] || {
  echo "cutover-check: cannot parse the claude-code-action release map from $SOURCES_MD" >&2
  exit 2
}

PLAN_OUT="$(mktemp -d)"

# Scratch directories the canary creates, so an interrupted leg leaves none
# behind. Only paths this script made are ever in here, and only ones whose
# name it chose: an empty entry is skipped rather than removed.
CANARY_DIRS=()
clean_canary_dirs() {
  local d
  for d in ${CANARY_DIRS[@]+"${CANARY_DIRS[@]}"}; do
    case "$d" in
    */cutover-canary.??????) rm -rf "$d" ;;
    *) ;;
    esac
  done
  CANARY_DIRS=()
}
trap 'rm -f "$ACTION_MAP"; rm -rf "$PLAN_OUT"; clean_canary_dirs' EXIT INT TERM

# `a >= b` over dotted numeric versions. `sort -V` would do it and is GNU-only.
ver_ge() {
  local -a a b
  local i x y
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    x="${a[i]:-0}"
    y="${b[i]:-0}"
    ((10#$x > 10#$y)) && return 0
    ((10#$x < 10#$y)) && return 1
  done
  return 0
}

# --- one plan per repository, reused by conditions 2 and 4 ----------------
# Keyed by POSITION, not by the path. A name normalized for the filesystem
# collides (`/repos/foo-bar` and `/repos/foo_bar` normalize the same), and the
# second plan then overwrites the first, so one repository is graded twice and
# the other not at all.
repo_plan() {
  local repo="$1" i=0
  for i in "${!REPOS[@]}"; do
    [[ "${REPOS[$i]}" == "$repo" ]] && {
      printf '%s/%s.plan' "$PLAN_OUT" "$i"
      return 0
    }
  done
  printf '%s/unknown.plan' "$PLAN_OUT"
}

# A repository that cannot be planned yields no ACTION and no PATHDET rows, and
# both conditions that read them would pass on the silence. A named site the
# check cannot see is a usage error, not a clean result.
for repo in "${REPOS[@]}"; do
  bash "$PLAN_MIGRATION" --root "$repo" >"$(repo_plan "$repo")" 2>/dev/null || {
    echo "cutover-check: cannot plan $repo: not a git repository, or unreadable" >&2
    exit 2
  }
done

# --- Condition 1 ----------------------------------------------------------
# The flag's code default is minifier-assigned: the plugin exports
# `isOnByDefault:()=>X` and declares `var X=!0` (true) or `var X=!1` (false)
# nearby. Both the identifier and the byte offsets are per build, so both are
# resolved at run time and neither is ever hardcoded. The surrounding bytes are
# not text, so the window is flattened before it is matched.
condition_1() {
  local bundle="$BUNDLE" line off start window id esc val seen="" verdict=""
  echo "Condition 1: native AGENTS.md reading no longer depends on the remote flag"

  [[ -n "$bundle" ]] || bundle="$(command -v "$CLAUDE_BIN" 2>/dev/null)"
  if [[ -z "$bundle" || ! -f "$bundle" ]]; then
    note "bundle: not found (looked for '$CLAUDE_BIN')"
  else
    while IFS= read -r line; do
      off="${line%%:*}"
      [[ "$off" =~ ^[0-9]+$ ]] || continue
      start=$((off - BUNDLE_WINDOW))
      ((start < 0)) && start=0
      window="$(tail -c "+$((start + 1))" "$bundle" | head -c $((BUNDLE_WINDOW * 2)) |
        tr -c '[:print:]' ' ')"
      # The identifier is taken from the REGISTRATION, `Gl("<flag>",<id>)`, not
      # from the first `isOnByDefault` in the window. Those are the same symbol
      # on the builds seen so far, and nothing in a minified bundle guarantees
      # it: a window holding two plugins would otherwise resolve this flag's
      # default from a neighbour's variable. The export is still required, and
      # required to name the SAME identifier, so a window where the two cannot
      # be tied together answers nothing.
      id="$(printf '%s' "$window" |
        grep -oE "\"${FLAG_NAME}\",[A-Za-z_\$][A-Za-z0-9_\$]*" | head -n 1)"
      id="${id##*,}"
      [[ -n "$id" ]] || continue
      esc="$(printf '%s' "$id" | sed 's/[$]/\\$/g')"
      printf '%s' "$window" | grep -qE "isOnByDefault:\(\)=>${esc}([^A-Za-z0-9_\$]|$)" || {
        note "bundle offset $off: registration names $id, but no isOnByDefault export ties to it"
        continue
      }
      val="$(printf '%s' "$window" | grep -oE "var ${esc}=(!0|!1)" | head -n 1)"
      val="${val##*=}"
      [[ -n "$val" ]] || continue
      note "bundle $bundle offset $off: \"$FLAG_NAME\",$id with isOnByDefault:()=>$id, var $id=$val"
      case "$val" in
      # Agreeing occurrences are one answer, not a disagreement: the same
      # declaration is reachable from more than one offset on some builds.
      '!0') case "$seen" in *true*) ;; *) seen="${seen}true " ;; esac ;;
      '!1') case "$seen" in *false*) ;; *) seen="${seen}false " ;; esac ;;
      *) ;;
      esac
    done < <(grep -abo "$FLAG_NAME" "$bundle" 2>/dev/null)
    case "$seen" in
    "") note "bundle: no window ties '$FLAG_NAME' to a resolvable code default" ;;
    "true ") verdict="default-true" ;;
    "false ") verdict="default-false" ;;
    *) note "bundle: occurrences disagree on the default ($seen)" ;;
    esac
  fi

  local ev="$ENV_VARS_FILE" body="" heading_found=0 bullet_found=0
  if [[ -z "$ev" ]]; then
    ev="$PLAN_OUT/env-vars.md"
    curl -sL --max-time 60 "$ENV_VARS_URL" -o "$ev" 2>/dev/null || :
  fi
  if [[ -s "$ev" ]]; then
    body="$(awk -v h="$ENV_VARS_HEADING" '$0 == h { f = 1; next } f && /^## / { exit } f' "$ev" | tr -d '\r')"
    [[ -n "$body" ]] && heading_found=1
    case "$body" in
    *AGENTS.md*) bullet_found=1 ;;
    *) ;;
    esac
    note "env-vars: heading $([[ $heading_found -eq 1 ]] && echo found || echo absent), AGENTS.md bullet $([[ $bullet_found -eq 1 ]] && echo present || echo absent) ($ev)"
  else
    note "env-vars: page not read (fetch failed or file empty)"
  fi

  if [[ "$verdict" == "default-true" ]]; then
    met "the bundle's code default for $FLAG_NAME is true, so no flag fetch is needed"
    return 0
  fi
  if ((heading_found == 1 && bullet_found == 0)); then
    met "the env-vars feature-flag list no longer carries the AGENTS.md bullet"
    return 0
  fi
  if [[ "$verdict" == "default-false" ]] && ((heading_found == 1 && bullet_found == 1)); then
    unmet "code default false and the env-vars list still carries the AGENTS.md bullet"
    return 1
  fi
  unreach "neither probe could answer; an unread default is not a default of true"
  return 2
}

# --- Condition 2 ----------------------------------------------------------
action_cli_version() {
  local ref="$1" tag commit ver
  # An empty ref would prefix-match the map's first row and borrow its version.
  [[ -n "$ref" ]] || return 1
  while IFS=$'\t' read -r tag commit ver; do
    [[ -n "$tag" ]] || continue
    if [[ "$ref" == "$tag" || "$commit" == "$ref"* ]]; then
      printf '%s' "$ver"
      return 0
    fi
  done <"$ACTION_MAP"
  return 1
}

condition_2() {
  local repo kind row ref ver pins=0 below=0 unknown=0 rows
  echo "Condition 2: every claude-code-action pin installs CLI $CLI_FLOOR or later, and the CI canary is on record"

  for repo in "${REPOS[@]}"; do
    # A plan with no ACTION row at all is a plan that did not run this scan.
    # "Checked, and there is none" arrives as an explicit NONE row, so silence
    # is a defect and never an absence of pins.
    rows="$(awk -F'\t' '$1 == "ACTION"' "$(repo_plan "$repo")")"
    if [[ -z "$rows" ]]; then
      note "$repo: the plan carries no ACTION row; the pin scan did not report"
      unknown=$((unknown + 1))
      continue
    fi
    while IFS=$'\t' read -r kind row; do
      [[ "$kind" == "ACTION" ]] || continue
      # An ERROR row carries its detail in a further tab-separated field, which
      # `read` leaves attached to this one.
      if [[ "$row" == ERROR* ]]; then
        note "$repo: the pin scan failed (${row#ERROR?})"
        unknown=$((unknown + 1))
        continue
      fi
      if [[ "$row" == "NONE" ]]; then
        note "$repo: no claude-code-action pin"
        continue
      fi
      ref="$(printf '%s' "$row" | grep -oE 'claude-code-action(/[A-Za-z0-9._-]+)*@[A-Za-z0-9._-]+' | head -n 1)"
      ref="${ref#*@}"
      pins=$((pins + 1))
      # An empty ref is a `uses:` line this script could not parse, and an
      # empty needle prefix-matches the first row of the release map, so it
      # would silently borrow that row's CLI version.
      if [[ -z "$ref" ]]; then
        unknown=$((unknown + 1))
        note "$repo: could not parse a ref out of the pin ($row)"
        continue
      fi
      if ver="$(action_cli_version "$ref")"; then
        if ver_ge "$ver" "$CLI_FLOOR"; then
          note "$repo: pin $ref installs CLI $ver, at or above $CLI_FLOOR"
        else
          below=$((below + 1))
          note "$repo: pin $ref installs CLI $ver, BELOW $CLI_FLOOR ($row)"
        fi
      else
        unknown=$((unknown + 1))
        note "$repo: pin $ref is not in the release map in $SOURCES_MD"
      fi
    done <"$(repo_plan "$repo")"
  done
  note "CI canary: run $CI_CANARY_RUN on record, as of ${CI_CANARY_ASOF:-unknown}"
  if ((pins == 0)); then
    note "no pin in any named repository: a fleet verdict needs every in-scope repository named,"
    note "and a lane that delegates to a reusable workflow is not an ACTION row"
  fi

  if ((unknown > 0)); then
    unreach "$unknown pin(s) map to no known CLI version; an unreadable map is not a satisfied floor"
    return 2
  fi
  if ((below > 0)); then
    unmet "$below of $pins pin(s) install a CLI below $CLI_FLOOR"
    return 1
  fi
  met "$pins pin(s) at or above CLI $CLI_FLOOR, and the lone-AGENTS.md CI canary passed in run $CI_CANARY_RUN"
  return 0
}

# --- Condition 3 ----------------------------------------------------------
# A token canary, not verify-load.sh: that script detects a load through an
# InstructionsLoaded hook, which does not fire for an AGENTS.md Claude reads
# directly, which is exactly the surface this condition measures. The record is
# in reference/sources.md, "What the loss means for measuring the cutover".
#
# The token is in the prompt, so a reply echoing it proves nothing. The rest of
# the canary line is not, so the whole line coming back is the evidence.
#
# The turn runs with NO TOOLS (`--tools ""`). A canary that let the model read
# the file proves only that the file is readable: with `--allowedTools Read` and
# an AGENTS.md in the working directory, a reply quoting it is consistent with a
# Read the model made for itself. A root AGENTS.md is project instructions at
# session start, so nothing needs to be read for it to be quotable, and a reply
# from a session that COULD not read anything is evidence of a load. Proven
# 2026-09-20 on 2.1.278 before adoption: the token line came back from a scratch
# directory holding one AGENTS.md and nothing else, and a directory with no
# AGENTS.md answered NONE. The run is logged in the migration slice's Phase 6
# proof.
canary_leg() {
  local root="$1" label="$2" dir token line reply rc=0
  mkdir -p "$root" 2>/dev/null || {
    note "$label: cannot create $root"
    return 2
  }
  if (cd "$root" && git rev-parse --show-toplevel >/dev/null 2>&1); then
    note "$label: $root is inside a git repository; a canary writes an AGENTS.md and must not do that in a working tree"
    return 2
  fi
  dir="$(mktemp -d "$root/cutover-canary.XXXXXX" 2>/dev/null)" || {
    note "$label: cannot create a scratch directory under $root"
    return 2
  }
  # Registered before the file is written, so an interrupt between the two
  # leaves nothing behind either way.
  CANARY_DIRS+=("$dir")
  token="CUTOVER-$$-${RANDOM}"
  line="Canary token: $token. Whoever quotes this line has loaded the project instructions."
  printf '%s\n' "$line" >"$dir/AGENTS.md"
  reply="$(cd "$dir" && "$CLAUDE_BIN" -p \
    "Quote back, verbatim, every line of your project instructions that contains $token. If there are none, say NONE." \
    --model haiku --tools "" </dev/null 2>/dev/null)" || rc=$?
  clean_canary_dirs
  if ((rc != 0)); then
    note "$label ($root): the CLI exited $rc"
    return 2
  fi
  case "$reply" in
  *"$line"*)
    note "$label ($root): the canary line came back"
    return 0
    ;;
  *NONE*)
    note "$label ($root): clean NONE, the lone AGENTS.md did not load"
    return 1
    ;;
  *)
    note "$label ($root): neither the line nor NONE came back"
    return 2
    ;;
  esac
}

condition_3() {
  echo "Condition 3: a lone non-empty AGENTS.md loads from a home cwd and from a second-path cwd"
  if ((SKIP_CANARY == 1)); then
    unreach "--skip-canary: the canary did not run"
    return 2
  fi
  local home_root="$CANARY_HOME_ROOT" alt_root="$CANARY_ALT_ROOT" rc_home=0 rc_alt=0
  [[ -n "$home_root" ]] || home_root="${HOME:-/tmp}/.cache"
  if [[ -z "$alt_root" ]]; then
    if [[ -d "/d" ]]; then alt_root="/d/scratch"; else alt_root="${TMPDIR:-/tmp}"; fi
  fi
  canary_leg "$home_root" "home cwd" || rc_home=$?
  canary_leg "$alt_root" "second-path cwd" || rc_alt=$?

  if ((rc_home == 2 || rc_alt == 2)); then
    unreach "a leg could not measure; an unmeasured canary is never a pass"
    return 2
  fi
  if ((rc_home == 1 || rc_alt == 1)); then
    unmet "a lone AGENTS.md did not load in at least one cwd"
    return 1
  fi
  met "both legs returned the canary line from a lone non-empty AGENTS.md"
  return 0
}

# --- Condition 4 ----------------------------------------------------------
# The grep cannot tell "reads CLAUDE.md as an instruction file" from "locates a
# path by its existence", and that distinction is the condition. So the
# judgment lives in a reviewed per-repository file and the default fails
# closed: a row nobody acknowledged is [UNMET] and is named. No path
# convention exempts anything, test trees included — the one real blocker in
# this fleet lives under `tests/`.
ACK_REASON=""
ack_lookup() {
  local ack="$1" path="$2" text="$3" p t r
  ACK_REASON=""
  [[ -f "$ack" ]] || return 1
  while IFS=$'\t' read -r p t r || [[ -n "$p" ]]; do
    p="$(trim "${p:-}")"
    [[ -z "$p" || "$p" == \#* ]] && continue
    [[ "$p" == "$path" && "$(normalize_text "${t:-}")" == "$text" ]] || continue
    ACK_REASON="$(trim "${r:-}")"
    # A row with no reason acknowledges nothing. The reason IS the review; a
    # path and a copy of the line are only the match key.
    [[ -n "$ACK_REASON" ]] || return 1
    return 0
  done <"$ack"
  return 1
}

condition_4() {
  local repo ack kind row path rest text acked=0 unacked=0 unreadable=0 rows
  echo "Condition 4: no repository locates a path by the existence of CLAUDE.md"
  note "scope: every tracked file except *.md and each repository's own acknowledgement list,"
  note "which quotes a detector on every line by design; no other path convention is exempt"

  for repo in "${REPOS[@]}"; do
    ack="$repo/.claude/cutover-pathdet-ack.txt"
    rows="$(awk -F'\t' '$1 == "PATHDET"' "$(repo_plan "$repo")")"
    if [[ -z "$rows" ]]; then
      note "$repo: the plan carries no PATHDET row; the detection scan did not report"
      unreadable=$((unreadable + 1))
      continue
    fi
    while IFS=$'\t' read -r kind row; do
      [[ "$kind" == "PATHDET" ]] || continue
      if [[ "$row" == ERROR* ]]; then
        note "$repo: the detection scan failed (${row#ERROR?})"
        unreadable=$((unreadable + 1))
        continue
      fi
      if [[ "$row" == "NONE" ]]; then
        note "$repo: no path detection"
        continue
      fi
      path="${row%%:*}"
      rest="${row#*:}"
      text="$(normalize_text "${rest#*:}")"
      # Matching drops the line number so a row that moves still matches;
      # reporting keeps it, so an operator has somewhere to jump to.
      if ack_lookup "$ack" "$path" "$text"; then
        acked=$((acked + 1))
        note "$repo: acknowledged $path:${rest%%:*}: $ACK_REASON"
      else
        unacked=$((unacked + 1))
        note "$repo: UNACKNOWLEDGED $path:${rest%%:*}: $text"
      fi
    done <"$(repo_plan "$repo")"
  done

  if ((unreadable > 0)); then
    unreach "$unreadable repository scan(s) did not report; an unread tree is not a clean tree"
    return 2
  fi
  if ((unacked > 0)); then
    unmet "$unacked path-detection row(s) have no reviewed acknowledgement"
    return 1
  fi
  met "$acked path-detection row(s), every one acknowledged with a reviewed reason"
  return 0
}

# --- report ---------------------------------------------------------------
echo "=== AGENTS.md cutover check ==="
echo
echo "Repositories: ${REPOS[*]}"
echo "Records:      $SOURCES_MD"
echo

FAILED=0
UNMET_LIST=""
grade() { # <condition number> <its exit status>
  if (($2 != 0)); then
    FAILED=$((FAILED + 1))
    UNMET_LIST="${UNMET_LIST}${UNMET_LIST:+, }$1"
  fi
  echo
}

rc=0
condition_1 || rc=$?
grade 1 "$rc"
rc=0
condition_2 || rc=$?
grade 2 "$rc"
rc=0
condition_3 || rc=$?
grade 3 "$rc"
rc=0
condition_4 || rc=$?
grade 4 "$rc"

if ((FAILED == 0)); then
  echo "=== Verdict: every graded condition MET. remove-shims may run. ==="
  exit 0
fi
echo "=== Verdict: NOT MET. Condition(s) $UNMET_LIST are not [MET]; nothing is removed. ==="
exit 1
