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
RISK_UNPINNABLE=0
CONFIG_ROOT="$(cd "$REPO_ROOT" 2>/dev/null && pwd -P)" || CONFIG_ROOT="$REPO_ROOT"
CONFIG_TARGET_DIR="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd -P)" ||
  CONFIG_TARGET_DIR="$(dirname "$FILE")"
collect_risky_configs() {
  local cursor dir candidate config risky
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
      *.cjs | *.mjs)
        RISK_CONFIGS+=("$config")
        # A module-loading key in an EXECUTABLE config names entries
        # markdownlint-cli2 resolves ITSELF, so an entry can be any expression
        # that produces a string — `path.join(...)`, `["./rules","x.cjs"]
        # .join("/")`, a concatenation, a helper call, a value imported from
        # elsewhere. That space cannot be enumerated by a text scan, and each
        # attempt only moves the edge, so a JS config carrying one of these keys
        # gets no approval route at all.
        #
        # A JS config WITHOUT these keys stays approvable: its only code loading
        # is its own require/import calls, whose arguments unpinnable_js_specifier
        # reads exactly. A repo that does name custom rules from a JS config must
        # move those entries to a declarative config, where they are data this
        # scan can read rather than an expression it must predict.
        if grep -Eq 'customRules|markdownItPlugins|outputFormatters' "$config" 2>/dev/null; then
          RISK_UNPINNABLE=1
        fi
        ;;
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
        #
        # The two tiers are INDEPENDENT tests, not a chain: a config can carry a
        # literal key AND an escaped module VALUE
        # (`"customRules": ["./rules.cjs"]`), and chaining them would let
        # the tier-one match suppress the tier-two verdict — the collector would
        # then hash the raw escaped spelling rather than the file markdownlint
        # decodes it to and loads, leaving an approval valid across edits to it.
        risky=0
        if grep -Eq 'customRules|markdownItPlugins|outputFormatters' "$config" 2>/dev/null; then
          risky=1
        fi
        if [[ "$config" == *.jsonc ]] &&
          grep -Eq '\\u[0-9a-fA-F]{4}' "$config" 2>/dev/null; then
          risky=1
          RISK_UNVERIFIABLE=1
        fi
        if [[ "$config" == *.yaml ]] &&
          grep -Eq '\\[xuU][0-9a-fA-F]|\\$|!![A-Za-z]' "$config" 2>/dev/null; then
          risky=1
          RISK_UNVERIFIABLE=1
        fi
        if ((risky == 1)); then
          RISK_CONFIGS+=("$config")
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

# True when a JS source names code this text scan cannot pin to a file.
#
# Two independent tests, because neither alone covers the shape space.
#
# 1. PATH-BUILDING MACHINERY anywhere in the file. markdownlint-cli2 resolves
#    `customRules`/`markdownItPlugins`/`outputFormatters` entries itself, so
#    `customRules: [path.join(__dirname, "rules", "x.cjs")]` carries no loader
#    call to anchor a pattern on — and the entries are conventionally written
#    across several lines, so no line-scoped anchor could see the key and the
#    expression together either. String concatenation and template
#    interpolation assemble a specifier the same way and are refused with it.
#    The `path` module is refused at its IMPORT rather than at its call sites,
#    because a call site can be spelled through any alias — `p.join(...)`,
#    `const { join } = require("path")` — while the import cannot: a file that
#    pulls in `path` is building paths, and this scan cannot pin what it builds.
#    Matching bare `.join(`/`.resolve(` instead would refuse every
#    `array.join(",")` and `Promise.resolve`, which is collateral, not caution.
#
# 2. A LOADER RESIDUE. Delete every plainly-written loader call — `require("x")`
#    / `import("x")` — from the text, then look for a loader token in what
#    remains. A proximity pattern cannot decide this, because JavaScript
#    permits a comment or newline at any token boundary, so
#    `require/*c*/(path.join(...))` sits outside any fixed window; and counting
#    occurrences cannot either, because `grep -o` consumes the boundary
#    character a word-start guard needs and so undercounts a nested
#    `require(require("x"))`. Deleting first leaves nothing to align: a loader
#    the plain-form pattern did not consume is a loader whose argument this
#    scan cannot read.
#
# Plus a string literal carrying a letter-capable escape (backslash-u/x/octal),
# which Node decodes to a different path than the raw text resolved here — a
# specifier can hide its real spelling that way.
#
# Every pattern is POSIX ERE: no `\b`, which is a GNU extension that BSD grep
# (macOS system grep, the platform this file targets) may read as a literal `b`,
# turning the whole predicate into a silent pass — the one failure direction
# this function must not have. Word starts and ends are spelled as bracket
# expressions instead, and the residue test uses `grep -q` rather than `-o` so
# no boundary character is consumed.
#
# Deliberately over-approximating: a `path.join` used to read a data file,
# `process.cwd()` in an unrelated call, or `__dirname` inside a string refuses
# approval too. That is the fail-closed direction, and its cost is a skipped
# lint run.
unpinnable_js_specifier() {
  local file="$1"
  if grep -Eq \
    -e "(require[[:space:]]*\([[:space:]]*|from[[:space:]]*)[\"'](node:)?path[\"']" \
    -e 'path[[:space:]]*\.[[:space:]]*(join|resolve|normalize)[[:space:]]*\(' \
    -e 'require[[:space:]]*\.[[:space:]]*resolve[[:space:]]*\(' \
    -e 'import[[:space:]]*\.[[:space:]]*meta' \
    -e 'process[[:space:]]*\.' \
    -e '__dirname|__filename' \
    -e '\$\{' \
    -e "[\"'][[:space:]]*\+|\+[[:space:]]*[\"']" \
    -e "[\"'][^\"']*\\\\[uxUX0-7]" \
    "$file" 2>/dev/null; then
    return 0
  fi
  sed -E "s/(require|import)[[:space:]]*\([[:space:]]*(\"[^\"]*\"|'[^']*')/ /g" "$file" 2>/dev/null |
    grep -Eq "(^|[^A-Za-z0-9_\$])(require($|[^A-Za-z0-9_\$])|import[[:space:]]*\()"
}

MODULE_FILES=()
collect_module_files() {
  local item dir str tag base candidate resolved entry scanned=0
  local queue=("$@")
  local seen_scan=$'\n' seen_module=$'\n'
  local quoted_string_re="\"[^\"]+\"|'[^']+'"
  # YAML plain scalars carry no quotes, so `customRules: [./rules/local.cjs]`
  # is invisible to the quoted-string scan and its module would never enter the
  # signature. Path-shaped bare tokens are therefore harvested too. Restricted
  # to tokens containing a `/` or `.` below, so an ordinary word (a key name, a
  # rule id) is not tried as a path; over-collecting a token that resolves to
  # nothing costs nothing, which is the same over-approximation the quoted scan
  # already relies on.
  local plain_token_re="[A-Za-z0-9_.@~/+-]+"

  while ((${#queue[@]} > 0)); do
    item="${queue[0]}"
    if ((${#queue[@]} > 1)); then queue=("${queue[@]:1}"); else queue=(); fi
    case "$seen_scan" in *$'\n'"$item"$'\n'*) continue ;; *) ;; esac
    seen_scan+="$item"$'\n'
    scanned=$((scanned + 1))
    ((scanned <= 64)) || return 1
    # A module specifier this text scan cannot read as written names code it
    # cannot pin, so the state gets no approval at all: an approval whose
    # signature omits the module would survive arbitrary edits to it.
    # unpinnable_js_specifier answers that question for a JS source; a
    # declarative config is judged by the separate key/escape tiers above.
    case "$item" in
    *.cjs | *.mjs | *.js)
      if unpinnable_js_specifier "$item"; then
        RISK_UNPINNABLE=1
        return 1
      fi
      ;;
    *) ;;
    esac
    dir="$(dirname "$item")"
    while IFS= read -r str; do
      # The stream carries both harvests, each tagged with its kind: Q keeps the
      # quoted scan's exact prior behavior (strip the delimiters, try every
      # token), P adds bare tokens and admits only path-shaped ones.
      tag="${str:0:1}"
      str="${str:1}"
      if [[ "$tag" == Q ]]; then
        str="${str#?}"
        str="${str%?}"
      else
        case "$str" in */* | *.*) ;; *) continue ;; esac
      fi
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
            # hook::physical_path degrades to the unchanged lexical path when no
            # canonicalizer resolves it. A symlink whose physical path came back
            # unchanged is the observable signature of that degradation — a
            # symlink never canonicalizes to itself — and the boundary check
            # below would then read an escaping symlink as in-repository and pin
            # it by its lexical path, leaving the external target free to change
            # under a live approval. Same test the membership scope above uses,
            # and the same fail-closed answer.
            if [[ -L "$candidate" && "$resolved" == "$candidate" ]]; then
              RISK_UNPINNABLE=1
              return 1
            fi
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
          *)
            # A repository path that RESOLVES outside the repository — a symlink
            # aimed out of the tree, or a `../` escape — names code no signature
            # over repository content can cover: the approval state is unchanged
            # when the external target changes, or when the symlink is re-aimed
            # at a different existing target, yet Node follows it and executes
            # the new code. Hashing the external file instead would extend the
            # signature beyond the repository the approval is scoped to, so the
            # state is refused rather than signed. CONFIG_ROOT is itself a
            # physical path (`pwd -P`), so this compares like with like and a
            # symlinked checkout does not read as an escape.
            RISK_UNPINNABLE=1
            return 1
            ;;
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
    done < <(
      grep -oE "$quoted_string_re" "$item" 2>/dev/null | sed 's/^/Q/'
      grep -oE "$plain_token_re" "$item" 2>/dev/null | sed 's/^/P/'
    )
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
  ((RISK_UNPINNABLE == 0)) || return 1
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
    elif ((RISK_UNPINNABLE == 1)); then
      APPROVE_HINT="The configuration or a module it references names code through an expression this hook cannot pin to a file (a built path, a template, a concatenation, or a loader argument it cannot read), so the code that would execute cannot be bound to an approval and linting stays disabled for this repository."
    else
      APPROVE_HINT="Approval state is unavailable (CLAUDE_PLUGIN_DATA unset or unusable, or the configuration's referenced modules could not be tracked), so linting stays disabled for this repository."
    fi
    # Approvable states key the notice by signature; states with no approval
    # route (unverifiable / untrackable / no store) have no signature, so key
    # by the risky configs' content instead — otherwise every such state
    # would share one key and only the first would ever notice in a session,
    # while an unchanged state still dedupes.
    if [[ -n "$TRUST_DIR" ]]; then
      TRUST_NOTICE_KEY="markdown-format-trust-${TRUST_DIR##*/}"
    else
      TRUST_NOTICE_KEY="markdown-format-trust-noroute-$(
        {
          printf '%s\n' "$REPO_ROOT"
          for config in "${RISK_CONFIGS[@]}"; do
            git hash-object "$config" 2>/dev/null || printf 'undigested\n'
          done
        } | git hash-object --stdin 2>/dev/null || printf 'unkeyed'
      )"
    fi
    if hook::notice_once "$TRUST_NOTICE_KEY" "$INPUT"; then
      hook::emit_skip_notice PostToolUse \
        "markdown-format trust gate: Markdown lint/format skipped — this repository's markdownlint configuration can execute repository-supplied code ($RISK_LIST). $APPROVE_HINT"
    fi
    emit_tel "skipped" '[]'
    exit 0
  fi
fi

# Per-run cap on how many individual violation lines reach the context. The
# whole finding set is ALWAYS summarized — count plus the leading rule codes —
# so raising or lowering this never hides the fact that findings exist; it only
# bounds the detail. 0 means unlimited.
#
# Read from the CLAUDE_PLUGIN_OPTION_<KEY> environment mirror, not a
# `${user_config.*}` placeholder: shell-form hook commands reject
# `${user_config.*}` substitution outright — "substituting a configured value
# into a shell command would let the shell run whatever that value contains, so
# the component fails" — while every option is exported to hook processes as
# CLAUDE_PLUGIN_OPTION_<KEY> anyway (Plugins reference, "User configuration",
# https://code.claude.com/docs/en/plugins-reference, fetched 2026-07-26). A
# value that is not a non-negative integer falls back to the default rather
# than being interpolated anywhere.
MAX_FINDINGS=20
case "${CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_MAX_FINDINGS:-}" in
"") ;;
*[!0-9]*) ;;
*) MAX_FINDINGS="${CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_MAX_FINDINGS}" ;;
esac

FIX_OUTPUT=$(cd "$REPO_ROOT" && "${MDLINT[@]}" --fix "$FILE" 2>&1)
LINT_RC=$?
BASE="$(basename "$FILE")"

# markdownlint-cli2 reports the fixes it WROTE as a bare count line and nothing
# more — it has no per-fix detail to offer. That count is still the only signal
# that this hook changed the file, so it is reported rather than dropped; the
# clean-after-fix path used to emit nothing at all, which made a rewrite of the
# user's file indistinguishable from the hook not running.
FIXES_LINE=""
while IFS= read -r line; do
  case "$line" in
  "Attempted: 0 fixes"*) ;;
  "Attempted:"*) FIXES_LINE="$line" ;;
  *) ;;
  esac
done <<<"$FIX_OUTPUT"

# Split the output into violation lines and everything else. The banner lines
# markdownlint-cli2 always prints (its version, the resolved `Finding:` glob
# list, `Linting: N files`, `Summary: N issues`) carry no information about the
# file being edited and cost context on every single edit, so they do not enter
# the report — the counts below are derived here instead. Violation lines are
# identified by the " MD<digits>/" rule-code pattern, matching what the
# telemetry schema calls a finding.
findings_raw=""
FINDING_COUNT=0
RULE_TALLY=""
while IFS= read -r line; do
  if [[ "$line" =~ [[:space:]](MD[0-9]+)/ ]]; then
    findings_raw+="$line"$'\n'
    FINDING_COUNT=$((FINDING_COUNT + 1))
    RULE_TALLY+="${BASH_REMATCH[1]}"$'\n'
  fi
done <<<"$FIX_OUTPUT"

hook::ctx_reset
CTX=""
SYSMSG=""

if [[ -n "$FIXES_LINE" ]]; then
  CTX+="markdown-format rewrote $BASE after your edit — markdownlint-cli2 reports \"$FIXES_LINE\" (structural fixes only; it reports no per-fix detail)."$'\n'
  SYSMSG="markdown-format rewrote $BASE: $FIXES_LINE."
fi

if ((FINDING_COUNT > 0)); then
  # Rule histogram, highest count first, so a report truncated to N lines still
  # says WHICH rules dominate — the single most useful thing about a 300-finding
  # set, and the thing a raw first-N truncation destroys.
  RULE_SUMMARY=$(printf '%s' "$RULE_TALLY" | sort | uniq -c | sort -rn |
    awk 'NR<=5 {printf "%s%s x%s", (NR>1 ? ", " : ""), $2, $1} END {print ""}' 2>/dev/null) || RULE_SUMMARY=""

  # Delta gate. A file edited eight times in a session produced eight
  # byte-identical whole-file dumps; re-sending an unchanged finding set is pure
  # cost. The SUMMARY still goes out every time — suppressing the message
  # entirely would recreate, on this plugin, exactly the invisible-hook problem
  # the disclosure above exists to fix.
  SAME_AS_LAST=0
  DIGEST_FILE=""
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] && command -v git >/dev/null 2>&1; then
    session_key=$(printf '%s' "$INPUT" | jq -r '.session_id // "no-session"' 2>/dev/null) || session_key="no-session"
    session_key="${session_key//[^A-Za-z0-9_-]/-}"
    file_key=$(printf '%s' "$FILE" | git hash-object --stdin 2>/dev/null) || file_key=""
    # The cap is part of the digest input: the truncation hint tells the user to
    # raise markdown_format_max_findings to see the rest, and a digest over the
    # finding set alone would then answer that with "unchanged, detail omitted"
    # — making the advice this hook gives impossible to act on.
    digest_now=$(printf '%s\n%s' "$MAX_FINDINGS" "$findings_raw" | git hash-object --stdin 2>/dev/null) || digest_now=""
    if [[ -n "$file_key" && -n "$digest_now" ]]; then
      digest_dir="${CLAUDE_PLUGIN_DATA%/}/finding-digests"
      if mkdir -p "$digest_dir" 2>/dev/null; then
        find "$digest_dir" -type f -mtime +7 -delete 2>/dev/null
        DIGEST_FILE="$digest_dir/${session_key}.${file_key}"
        if [[ -f "$DIGEST_FILE" ]] && [[ "$(cat "$DIGEST_FILE" 2>/dev/null)" == "$digest_now" ]]; then
          SAME_AS_LAST=1
        fi
        printf '%s' "$digest_now" >"$DIGEST_FILE" 2>/dev/null || DIGEST_FILE=""
      fi
    fi
  fi

  CTX+="markdown-format: $BASE has $FINDING_COUNT markdownlint finding(s)${RULE_SUMMARY:+ — $RULE_SUMMARY}."$'\n'
  if ((SAME_AS_LAST == 1)); then
    CTX+="  Unchanged from the previous run on this file; per-finding detail omitted. A rule firing in bulk here (a house style markdownlint does not know about) is configured away once in this repository's markdownlint config, not re-read every edit."$'\n'
  else
    shown=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      if ((MAX_FINDINGS > 0 && shown >= MAX_FINDINGS)); then break; fi
      CTX+="  $line"$'\n'
      shown=$((shown + 1))
    done <<<"$findings_raw"
    if ((FINDING_COUNT > shown)); then
      CTX+="  ... and $((FINDING_COUNT - shown)) more finding(s), omitted to bound context. Raise markdown_format_max_findings to see them, or configure the dominant rule in this repository's markdownlint config."$'\n'
    fi
  fi
elif ((LINT_RC != 0)) && [[ -n "$FIX_OUTPUT" ]]; then
  # Non-zero exit with no parseable violation line: markdownlint itself broke
  # (bad config, unreadable file). That diagnostic must never be swallowed by
  # the banner filter above, so the raw output goes through, still bounded.
  CTX+="markdown-format: markdownlint-cli2 failed for $BASE (tool break, not a finding):"$'\n'
  shown=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if ((MAX_FINDINGS > 0 && shown >= MAX_FINDINGS)); then
      CTX+="  ... output truncated."$'\n'
      break
    fi
    CTX+="  $line"$'\n'
    shown=$((shown + 1))
  done <<<"$FIX_OUTPUT"
fi

# Compose ONE stdout document: Claude Code parses a hook's entire stdout as a
# single JSON document, so the agent-channel report and the user-channel
# mutation notice are emitted together rather than printed twice.
CTX="${CTX%"${CTX##*[![:space:]]}"}"
hook::emit_channels PostToolUse "$CTX" "$SYSMSG"

# Build the findings array in one jq pass (one JSON string per matched line).
# The telemetry payload is NOT capped — a sink is a machine, and the cap exists
# to protect the model's context, not a log file.
FINDINGS_JSON='[]'
if [[ -n "$findings_raw" ]]; then
  FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
fi

emit_tel "ok" "$FINDINGS_JSON"
exit 0
