#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint Markdown via markdownlint-cli2.
# Triggered on Write|Edit of *.md and *.mdc (Cursor MDC = markdown + frontmatter).
#
# ADVISORY: always exits 0 — unfixable markdownlint violations surface via
# additionalContext but never block the edit. Uses the consuming repo's own
# markdownlint config — ships none. When that configuration can execute code
# (.cjs/.mjs config, or module-loading keys), the lint run itself is gated on
# an explicit per-repo trust approval; see the trust gate below.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "MARKDOWN_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# formatting work (pre-format exits below do not emit telemetry). EPOCHREALTIME is
# Bash 5.0+; on older bash it is unset, so default to empty — referencing it bare
# under `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Emit this run's telemetry envelope: $1 status, $2 findings JSON array.
# Two guards: the high-res start stamp (EPOCHREALTIME is Bash 5.0+; on older
# bash it is empty and telemetry is skipped, so the hook still formats rather
# than aborting) and the sink opt-in. The data payload costs a jq subprocess,
# so it is built here after both guards — never on the unwired path.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  hook::emit_telemetry "markdown-format" "PostToolUse" "$1" "$start" "$(build_data_json "$2")" "$REPO_ROOT"
}

INPUT=$(hook::buffer_stdin) || exit 0

# jq-free applicability pre-filter: never emit the jq notice for an edit this
# hook would not process anyway (the Write|Edit matcher is broader than the
# Markdown filter).
RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0
case "$RAW_FILE" in
*.md | *.mdc) ;;
*) exit 0 ;;
esac

# jq is required to parse Claude Code's hook payload and to emit structured
# PostToolUse context. Absent → visible once-per-session skip notice on both
# the agent and user channels, exit 0.
hook::require_jq PostToolUse markdown-format "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
*.md | *.mdc) ;;
*) exit 0 ;;
esac

# Does <dir> sit inside a git working tree? Git's repository-selection and
# discovery environment variables are cleared first: an inherited GIT_DIR or
# GIT_WORK_TREE (a repository wrapper that launched the session) overrides
# discovery outright, so `git -C <out-of-tree dir>` would answer with the
# overridden repository and admit an external file. GIT_COMMON_DIR,
# GIT_CEILING_DIRECTORIES and GIT_DISCOVERY_ACROSS_FILESYSTEM skew the same
# probe in the other direction. The verdict must come from the directory alone,
# never from ambient state. Names per the official environment list —
# https://git-scm.com/docs/git, "The Git Repository" and "Git Discovery".
in_git_working_tree() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_DISCOVERY_ACROSS_FILESYSTEM
    git -C "$1" rev-parse --show-toplevel
  ) >/dev/null 2>&1
}

# markdownlint applies repo-doc rules, so when no CLAUDE_PROJECT_DIR anchors
# membership (e.g. an autonomous session whose cwd is not a repo), scope to
# git-working-tree containment instead: a scratch/temp .md outside any working
# tree (a lane's comment-body composed for gh --body-file) must not be linted
# with rules that do not apply to it. When CLAUDE_PROJECT_DIR is set,
# hook::read_file_path already enforced membership. This scoping is local to
# markdown-format on purpose — the shared guard stays location-agnostic for
# hooks whose value does not depend on repository membership.
#
# Membership is tested on the PHYSICAL path, matching hook::read_file_path: an
# in-repository symlink to an out-of-tree file would otherwise pass on its
# lexical parent while --fix rewrites the external target under repo rules.
#
# hook::physical_path degrades to the unchanged lexical path when no
# canonicalizer resolves it (neither realpath nor readlink -f present, or both
# failing). That degradation is safe for the shared prefix guard but not here:
# the lexical parent of an escaping symlink IS a working tree, so admitting it
# hands the external target to --fix. A symlink whose physical path came back
# unchanged is therefore the observable signature of failed canonicalization —
# checking the outcome rather than probing for a resolver also covers a
# resolver that exists but fails — and this scope fails closed on it.
if [[ -z "${CLAUDE_PROJECT_DIR:-}" ]]; then
  FILE_PHYSICAL="$(hook::physical_path "$FILE")"
  if [[ -L "$FILE" && "$FILE_PHYSICAL" == "$FILE" ]]; then
    exit 0
  fi
  if ! in_git_working_tree "$(dirname "$FILE_PHYSICAL")"; then
    exit 0
  fi
fi

# Resolve repo root early — needed for CWD-anchored config discovery and for
# computing the schema-required repo-relative path in data.file.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"

# Telemetry-payload precursors — TOOL and FILE_REL feed only the envelope's
# data object, so both are built only when a sink is wired: the unwired
# default path spawns zero telemetry-only subprocesses (the tool_name jq
# parse, and 2× cygpath on Windows).
#
# FILE_REL is the repo-relative path: schema requires "relative to the
# consuming repo root". On Windows Git Bash, git rev-parse --show-toplevel
# returns a drive-letter path while FILE may be in POSIX mount form. Normalize
# both through cygpath -lm (long name, forward-slash mixed form) when
# available so the prefix strip compares the same representation. On
# Linux/macOS, cygpath is absent and both paths are already POSIX. Falls back
# to raw FILE on any normalization error.
TOOL=""
FILE_REL="$FILE"
if hook::telemetry_enabled; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  if command -v cygpath >/dev/null 2>&1; then
    _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
    _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
    if [[ -n "$_file_lm" && -n "$_root_lm" ]]; then
      FILE_REL="${_file_lm#"$_root_lm"/}"
    fi
  else
    FILE_REL="${FILE#"$REPO_ROOT"/}"
  fi
fi

# Build the telemetry data object for the current TOOL/FILE_REL. $1 is the
# findings JSON array. jq is authoritative. The fallback is a fixed empty-shape
# object — NOT an interpolation of TOOL/FILE_REL, which could inject quotes or
# backslashes from a path and corrupt the envelope. The fallback is essentially
# unreachable in practice (it fires only if `jq -n` fails, and when jq is absent
# hook::emit_telemetry drops the envelope anyway), so losing the values here is
# harmless and strictly safer than emitting malformed JSON.
build_data_json() {
  jq -n \
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --argjson findings "$1" \
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null ||
    printf '{"tool":"","file":"","findings":[]}'
}

# Resolve the consuming repository's pinned npm binary without invoking a
# package runner. npm creates an extensionless POSIX shim in node_modules/.bin
# alongside its Windows .cmd launcher; Git Bash executes the POSIX shim. Follow
# symlinks before accepting it and require the physical target to remain inside
# this repository's node_modules tree. This rejects a checked-in or replaced
# .bin symlink that escapes the repository trust boundary.
resolve_repo_markdownlint() {
  local candidate="$REPO_ROOT/node_modules/.bin/markdownlint-cli2"
  local root_physical target link target_dir depth=0

  [[ -f "$candidate" && -x "$candidate" ]] || return 1
  root_physical="$(cd -P -- "$REPO_ROOT" 2>/dev/null && pwd -P)" || return 1
  target="$candidate"

  while [[ -L "$target" ]]; do
    depth=$((depth + 1))
    ((depth <= 32)) || return 1
    link="$(readlink "$target" 2>/dev/null)" || return 1
    case "$link" in
    /*) target="$link" ;;
    [A-Za-z]:[\\/]*)
      command -v cygpath >/dev/null 2>&1 || return 1
      target="$(cygpath -u "$link" 2>/dev/null)" || return 1
      ;;
    *) target="$(dirname -- "$target")/$link" ;;
    esac
  done

  [[ -f "$target" && -x "$target" ]] || return 1
  target_dir="$(cd -P -- "$(dirname -- "$target")" 2>/dev/null && pwd -P)" || return 1
  target="$target_dir/$(basename -- "$target")"
  case "$target" in
  "$root_physical"/node_modules/*) ;;
  *) return 1 ;;
  esac

  printf '%s' "$candidate"
}

MDLINT=()
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  MDLINT=(markdownlint-cli2)
elif REPO_MDLINT="$(resolve_repo_markdownlint)"; then
  MDLINT=("$REPO_MDLINT")
else
  # Never invoke a package runner here: hooks must not download or execute an
  # unpinned package as a side effect of editing a file. Degrade visibly on
  # both channels, once per session.
  if hook::notice_once "markdown-format-markdownlint" "$INPUT"; then
    hook::emit_skip_notice PostToolUse \
      "markdown-format: markdownlint-cli2 is neither on PATH nor available as a contained repository-local node_modules/.bin executable — Markdown lint skipped for this session. Install it explicitly; this hook does not invoke npx or download tools."
  fi
  emit_tel "skipped" '[]'
  exit 0
fi

# markdownlint-cli2 configuration can cross a code-execution boundary. Its
# official configuration contract loads .cjs/.mjs modules directly and passes
# customRules, markdownItPlugins, and outputFormatters module identifiers to
# Node's require/import machinery. Discover only the configuration files that
# apply to this file (repo root through its parent directory), honoring the
# documented same-directory precedence so a shadowed executable config does not
# create a false warning.
RISK_CONFIGS=()
RISK_UNVERIFIABLE=0
CONFIG_ROOT="$(cd "$REPO_ROOT" 2>/dev/null && pwd -P)" || CONFIG_ROOT="$REPO_ROOT"
CONFIG_TARGET_DIR="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd -P)" ||
  CONFIG_TARGET_DIR="$(dirname "$FILE")"
collect_risky_configs() {
  local cursor dir candidate config
  local dirs=()

  cursor="$CONFIG_TARGET_DIR"
  while :; do
    # Guarded for bash 3.2 + `set -u`: expanding an empty array errs there.
    if ((${#dirs[@]} > 0)); then dirs=("$cursor" "${dirs[@]}"); else dirs=("$cursor"); fi
    [[ "$cursor" == "$CONFIG_ROOT" ]] && break
    dir="$(dirname "$cursor")"
    [[ "$dir" != "$cursor" ]] || return 0
    cursor="$dir"
  done

  for dir in "${dirs[@]}"; do
    config=""
    for candidate in \
      .markdownlint-cli2.jsonc \
      .markdownlint-cli2.yaml \
      .markdownlint-cli2.cjs \
      .markdownlint-cli2.mjs; do
      if [[ -f "$dir/$candidate" ]]; then
        config="$dir/$candidate"
        break
      fi
    done
    if [[ -n "$config" ]]; then
      case "$config" in
      *.cjs | *.mjs) RISK_CONFIGS+=("$config") ;;
      *)
        # A textual scan cannot see a module-loading key spelled through
        # string escapes (JSONC "customRules") or YAML escape/tag
        # machinery, and building a second parser here would only open a
        # differential-parsing gap against the parser markdownlint-cli2
        # actually uses. The predicate is instead a fail-closed
        # over-approximation in two tiers. Tier one: the literal key words
        # ANYWHERE in the file — no key-colon anchor, because YAML
        # explicit-key syntax (`? customRules` with `:` on the next line)
        # separates the key from its colon — mark the config code-loading.
        # Tier two: any construct capable of synthesizing a spelling the
        # scan cannot see (JSONC \uXXXX escapes; YAML \x/\u/\U escapes,
        # escaped line joins, !! tags — a !!binary key decodes to arbitrary
        # text) marks it UNVERIFIABLE: it gates AND refuses approval below,
        # because text whose meaning cannot be read cannot be meaningfully
        # reviewed. YAML anchors/aliases stay verifiable — an alias only
        # reuses a node whose text is spelled literally elsewhere in the
        # same file, where tier one sees it.
        if grep -Eq 'customRules|markdownItPlugins|outputFormatters' "$config" 2>/dev/null; then
          RISK_CONFIGS+=("$config")
        elif [[ "$config" == *.jsonc ]] &&
          grep -Eq '\\u[0-9a-fA-F]{4}' "$config" 2>/dev/null; then
          RISK_CONFIGS+=("$config")
          RISK_UNVERIFIABLE=1
        elif [[ "$config" == *.yaml ]] &&
          grep -Eq '\\[xuU][0-9a-fA-F]|\\$|!![A-Za-z]' "$config" 2>/dev/null; then
          RISK_CONFIGS+=("$config")
          RISK_UNVERIFIABLE=1
        fi
        ;;
      esac
    fi

    config=""
    for candidate in \
      .markdownlint.jsonc \
      .markdownlint.json \
      .markdownlint.yaml \
      .markdownlint.yml \
      .markdownlint.cjs \
      .markdownlint.mjs; do
      if [[ -f "$dir/$candidate" ]]; then
        config="$dir/$candidate"
        break
      fi
    done
    case "$config" in
    *.cjs | *.mjs) RISK_CONFIGS+=("$config") ;;
    *) ;;
    esac
  done
}

# The approval signature must cover the code that would RUN, not only the
# config that names it: a customRules/markdownItPlugins/outputFormatters
# module — or a file require()d by an approved .cjs/.mjs config — can change
# (e.g. on a branch switch) while the config text stays identical, and a
# config-only signature would keep honoring the stale approval. Enumerating
# the true module graph would mean executing Node resolution, which is the
# very thing being gated, so approximate it conservatively from text: collect
# every string literal in each risky config, resolve it against the config's
# directory and the repo root, and for each hit inside this repository take
# the file (or, for a directory, its package.json/index entry points, the
# files Node's directory-require loads) into MODULE_FILES — then rescan each
# collected file the same way, so a repo rule module's own relative requires
# are covered transitively. Bounded at 64 scanned files; exceeding the bound
# returns 1 and the caller fails closed. Bare package identifiers resolve to
# node_modules, which the user installs explicitly — that separate trust
# decision is not folded into this repository-content signature.
# Bash 3.2-compatible throughout (macOS system bash): dedup state lives in
# newline-delimited strings rather than associative arrays, and every array
# expansion is guarded non-empty — `"${arr[@]}"` on an empty array is an
# unbound-variable error under `set -u` before bash 4.4.
MODULE_FILES=()
collect_module_files() {
  local item dir str base candidate resolved entry scanned=0
  local queue=("$@")
  local seen_scan=$'\n' seen_module=$'\n'
  local quoted_string_re="\"[^\"]+\"|'[^']+'"

  while ((${#queue[@]} > 0)); do
    item="${queue[0]}"
    if ((${#queue[@]} > 1)); then queue=("${queue[@]:1}"); else queue=(); fi
    case "$seen_scan" in *$'\n'"$item"$'\n'*) continue ;; *) ;; esac
    seen_scan+="$item"$'\n'
    scanned=$((scanned + 1))
    ((scanned <= 64)) || return 1
    dir="$(dirname "$item")"
    while IFS= read -r str; do
      str="${str#?}"
      str="${str%?}"
      [[ -n "$str" && "$str" != *$'\n'* ]] || continue
      for base in "$dir/$str" "$CONFIG_ROOT/$str"; do
        # Node's CommonJS resolution tries the literal path, then the
        # .cjs/.mjs/.js/.json/.node extension candidates, then a directory's
        # package.json/index entry points — an extensionless
        # require("./rules/local-rule") must still pin local-rule.cjs.
        for candidate in "$base" "$base.cjs" "$base.mjs" "$base.js" "$base.json" "$base.node"; do
          resolved=""
          if [[ -f "$candidate" ]]; then
            resolved="$(hook::physical_path "$candidate")"
          elif [[ "$candidate" == "$base" && -d "$candidate" ]]; then
            for entry in package.json index.js index.cjs index.mjs; do
              if [[ -f "$candidate/$entry" ]]; then
                queue+=("$(hook::physical_path "$candidate/$entry")")
              fi
            done
            continue
          else
            continue
          fi
          case "$resolved" in
          "$CONFIG_ROOT"/*) ;;
          *) continue ;;
          esac
          case "$seen_module" in
          *$'\n'"$resolved"$'\n'*) ;;
          *)
            seen_module+="$resolved"$'\n'
            MODULE_FILES+=("$resolved")
            queue+=("$resolved")
            ;;
          esac
        done
      done
    done < <(grep -oE "$quoted_string_re" "$item" 2>/dev/null)
  done
  return 0
}

# Resolve the trust-approval marker directory for the current repo +
# risky-config content state into TRUST_DIR. CLAUDE_PLUGIN_DATA is the
# official persistent plugin-state location and survives plugin updates; the
# signature is content-addressed over every risky config PLUS every resolved
# code-loading input it references (see collect_module_files), so a change to
# the configuration or to a referenced repository module yields a new
# directory and revokes a prior approval. Returns 1 when the state base is
# unavailable, a config or module cannot be digested, the module scan
# overflows its bound, or the config was classified unverifiable — the caller
# must fail CLOSED and skip the lint run: configuration that can execute code
# and whose approval cannot be verified is never run. Named trust-approvals,
# NOT trust-advisories: that directory's markers recorded only that a warning
# had been shown, and reading them as approvals would silently grant trust.
TRUST_DIR=""
resolve_trust_dir() {
  local state_base="${CLAUDE_PLUGIN_DATA:-}" signature config module digest
  TRUST_DIR=""
  [[ -n "$state_base" ]] || return 1
  ((RISK_UNVERIFIABLE == 0)) || return 1
  if command -v cygpath >/dev/null 2>&1 && [[ "$state_base" == [A-Za-z]:\\* ]]; then
    state_base="$(cygpath -u "$state_base" 2>/dev/null)" || return 1
  fi
  MODULE_FILES=()
  collect_module_files "${RISK_CONFIGS[@]}" || return 1
  signature=$(
    {
      printf '%s\n' "$REPO_ROOT"
      for config in "${RISK_CONFIGS[@]}"; do
        digest=$(git hash-object "$config" 2>/dev/null) || return 1
        printf '%s\t%s\n' "$config" "$digest"
      done
      # Guarded for bash 3.2 + `set -u`: expanding an empty array errs there.
      if ((${#MODULE_FILES[@]} > 0)); then
        for module in "${MODULE_FILES[@]}"; do
          digest=$(git hash-object "$module" 2>/dev/null) || return 1
          printf 'module\t%s\t%s\n' "$module" "$digest"
        done
      fi
    } | git hash-object --stdin 2>/dev/null
  ) || return 1
  [[ -n "$signature" ]] || return 1
  TRUST_DIR="${state_base%/}/trust-approvals/$signature"
}

hook::ctx_reset
collect_risky_configs
# Trust gate: markdownlint-cli2's configuration contract loads .cjs/.mjs
# config modules and customRules/markdownItPlugins/outputFormatters module
# identifiers through Node's require/import machinery, so running the linter
# under such configuration executes repository-supplied code. That must never
# happen on the strength of a markdown edit alone: the lint run is skipped
# until the user, having reviewed the configuration, records an explicit
# approval of this exact configuration state. The skip is reported on both
# channels once per session; the notice key carries the state signature so a
# configuration change re-notices within the same session.
if ((${#RISK_CONFIGS[@]} > 0)); then
  resolve_trust_dir || TRUST_DIR=""
  if [[ -z "$TRUST_DIR" || ! -d "$TRUST_DIR" ]]; then
    RISK_LIST=""
    for config in "${RISK_CONFIGS[@]}"; do
      config="${config#"$CONFIG_ROOT"/}"
      RISK_LIST+="${RISK_LIST:+, }$config"
    done
    if [[ -n "$TRUST_DIR" ]]; then
      APPROVE_HINT="Review these files and their installed dependencies; to approve this exact configuration state and enable linting, run: mkdir -p '$TRUST_DIR' (any change to the configuration or a referenced repository module revokes the approval)."
    elif ((RISK_UNVERIFIABLE == 1)); then
      APPROVE_HINT="The configuration contains constructs (string escapes or tags) that defeat textual verification, so it cannot be reviewed as written and linting stays disabled for this repository."
    else
      APPROVE_HINT="Approval state is unavailable (CLAUDE_PLUGIN_DATA unset or unusable, or the configuration's referenced modules could not be tracked), so linting stays disabled for this repository."
    fi
    if hook::notice_once "markdown-format-trust-${TRUST_DIR##*/}" "$INPUT"; then
      hook::emit_skip_notice PostToolUse \
        "markdown-format trust gate: Markdown lint/format skipped — this repository's markdownlint configuration can execute repository-supplied code ($RISK_LIST). $APPROVE_HINT"
    fi
    emit_tel "skipped" '[]'
    exit 0
  fi
fi

if FIX_OUTPUT=$(cd "$REPO_ROOT" && "${MDLINT[@]}" --fix "$FILE" 2>&1); then
  # Clean after fix — emit ok with empty findings.
  hook::ctx_flush PostToolUse
  emit_tel "ok" '[]'
  exit 0
fi

# Residual findings — surface one JSON object via additionalContext, then
# emit ok with findings.
# ctx_append receives all output lines (human-readable context for Claude Code).
# FINDINGS_JSON is filtered to violation lines only — schema requires
# "Unfixable markdownlint violations remaining after --fix, one per line";
# banner/diagnostic lines (version, Finding:, Linting:, Summary:) are excluded.
# Violation lines are identified by the " MD<digits>/" rule-code pattern.
hook::ctx_append "markdown-format: $(basename "$FILE") has markdownlint findings:"
findings_raw=""
while IFS= read -r line; do
  hook::ctx_append "  $line"
  if [[ "$line" =~ [[:space:]]MD[0-9]+/ ]]; then
    findings_raw+="$line"$'\n'
  fi
done <<<"$FIX_OUTPUT"
hook::ctx_flush PostToolUse

# Build the findings array in one jq pass (one JSON string per matched line).
FINDINGS_JSON='[]'
if [[ -n "$findings_raw" ]]; then
  FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
fi

emit_tel "ok" "$FINDINGS_JSON"
exit 0
