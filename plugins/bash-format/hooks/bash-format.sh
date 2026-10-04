#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint shell scripts via shfmt + ShellCheck.
# Triggered on Write|Edit of *.sh and *.bash files.
#
# ADVISORY: always exits 0. ShellCheck findings (warning severity and above)
# surface via additionalContext but never block the edit. Uses the consuming
# repo's own .shellcheckrc and .editorconfig — ships none.
#
# shfmt is gated on the consumer opting in: it runs only when an .editorconfig
# governs the edited file (walking up to the repo root). Without that opt-in the
# file is left unformatted rather than rewritten to shfmt's built-in defaults.
# ShellCheck (non-mutating) always runs when available.

set -uo pipefail

# Kill switch FIRST, before any library is sourced: a disabled hook must not
# pay to parse hook-utils.sh to learn it is off. Same predicate as
# hook::is_enabled; scripts/check-killswitch-hoist.sh pins the two together.
[[ "${CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$HOOK_DIR/rewrite-guard.sh"

# The SessionStart compact|clear row: the model lost the reports with its
# context, so the findings sent this session are sent again.
if [[ "${1:-}" == --reset-digests ]]; then
  hook::buffer_stdin_to INPUT && hook::findings_digest_reset "$INPUT"
  exit 0
fi

# The whole prologue: the start stamp, the buffered payload, the jq-free
# applicability filter, the jq gate, the parsed path with its basename and
# directory, the file-anchored repo root (which bounds the .editorconfig
# opt-in walk below), and the telemetry-only TOOL and FILE_REL behind the sink
# opt-in. Exits 0 itself on every path this hook has nothing to do on —
# including a Write or Edit of anything but a shell file, which it decides
# before the jq gate so a non-shell edit never triggers the jq notice.
hook::begin bash-format PostToolUse '*.sh' '*.bash'

# A file the repository gitignores is neither rewritten nor reported unless
# bash_format_lint_gitignored is set: a rewrite there has no `git checkout`
# to undo it.
if hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_BASH_FORMAT_LINT_GITIGNORED:-false}" "$FILE"; then
  hook::finish skipped findings array '[]'
fi

# A section header governs shell files when it names a shell extension —
# `[*.sh]` / `[*.bash]` (incl. path prefixes like `[**/*.sh]`) or a brace list
# naming sh or bash (`[*.{sh,bash}]`). A bare `[*]` catch-all is intentionally
# NOT treated as shell opt-in (#1817): most repos set only line-ending / charset
# properties under `[*]`, and treating that as an shfmt opt-in rewrote shell
# files to shfmt's built-in defaults. Path-only sections such as `[scripts/**]`
# are also excluded — matching those correctly means reimplementing EditorConfig
# globbing, and the safe bias is to leave files untouched when unsure. $1 is the
# text inside the brackets.
# shellcheck disable=SC2329  # called from the walk predicate below, which hook::walk_up_to invokes by name
section_applies_to_shell() {
  local h="$1"
  [[ "$h" =~ \*\.(sh|bash)([^[:alnum:]]|$) ]] && return 0
  [[ "$h" =~ [{,](sh|bash)[,}] ]] && return 0
  return 1
}

# Consumer opt-in for shfmt: an EditorConfig SECTION that names shell files
# (not merely the presence of any .editorconfig — a repo whose .editorconfig
# only configures other languages, or only a bare `[*]` for line endings, must
# not have its shell files rewritten to shfmt's built-in defaults). Walks up
# from the file to the repo root. This gate is the whole formatting opt-in, so
# it inherits hook::walk_up_to's fail-closed ceiling: a repo root that is not a
# directory leaves shell files unformatted rather than reading an .editorconfig
# from above the repository.
#
# The predicate answers 2 for a `root = true` config that names no shell
# section: EditorConfig's own search semantics end the search at such a file, so
# a shell section further up must not be consulted.
# shellcheck disable=SC2329  # invoked by name, as hook::walk_up_to's predicate
editorconfig_shell_section_here() {
  local cfg="$1/.editorconfig" line is_root=0
  [[ -f "$cfg" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]]; then
      section_applies_to_shell "${BASH_REMATCH[1]}" && return 0
    elif [[ "$line" =~ ^[[:space:]]*[Rr][Oo][Oo][Tt][[:space:]]*=[[:space:]]*[Tt][Rr][Uu][Ee][[:space:]]*$ ]]; then
      is_root=1
    fi
  done <"$cfg"
  ((is_root)) && return 2
  return 1
}

shell_editorconfig_opt_in() {
  # shellcheck disable=SC2034  # the gate reads the walk's verdict, not which directory carried the config
  local file_dir root="" hit=""
  file_dir="${FILE%/*}"
  [[ "$file_dir" == "$FILE" ]] && file_dir=.
  [[ -n "$file_dir" ]] || file_dir=/
  [[ -d "$file_dir" ]] || return 1
  # Existence check only, no canonicalization: git already answers an absolute
  # path, and a relative hint walks from the spelling `cd` would have used.
  [[ -d "$REPO_ROOT" ]] && root="$REPO_ROOT"
  hook::walk_up_to hit "$file_dir" "$root" editorconfig_shell_section_here
}

ran_any=0

# Notice accumulators, one per channel: a run can lack shfmt AND shellcheck,
# and can carry ShellCheck findings alongside a pending shfmt notice —
# everything must compose into the single JSON document hook::finish emits at
# the end. append_notice <model-text> [<user-text>]; either may be "".
MODEL_NOTICE=""
USER_NOTICE=""
SHFMT_MODEL="" SHFMT_USER="" SC_MODEL="" SC_USER=""
append_notice() {
  if [[ -n "$1" ]]; then
    [[ -n "$MODEL_NOTICE" ]] && MODEL_NOTICE+=" "
    MODEL_NOTICE+="$1"
  fi
  if [[ -n "${2:-}" ]]; then
    [[ -n "$USER_NOTICE" ]] && USER_NOTICE+=" "
    USER_NOTICE+="$2"
  fi
}

# Subscript guard. shfmt parses an unquoted array subscript as arithmetic,
# because a static parser cannot tell an associative array from an indexed one,
# and spaces its operators: `${m[a-b]}` becomes `${m[a - b]}`, a different key
# (https://github.com/mvdan/sh/issues/956 and the "Caveats" section of the
# mvdan/sh README). The guard compares the source text of every subscript
# before and after the rewrite, in syntax-tree order, and puts the original
# bytes back when any of them differs.
# The tree is the same on both sides, because shfmt reads the spaced and the
# unspaced form as one expression, so the subscripts pair up one to one. A
# span is widened over the blanks beside it before the compare: the tree's
# span leaves out the padding in `${m[ key ]}`, which is part of an
# associative key and which shfmt drops. Offsets are bytes, so the slicing runs
# under LC_ALL=C. A file holding a NUL byte cannot be held in a bash variable
# and is not guarded. A tree that cannot be read on either side, or that
# yields a different number of subscripts, fails closed: the rewrite is put
# back, since an unchecked rewrite may have changed a key.
SUBSCRIPT_ORIG=""
SUBSCRIPT_GUARD=0
subscript_guard_begin() {
  local LC_ALL=C
  SUBSCRIPT_GUARD=0
  # read returns 0 only when it stopped at a NUL before end of file.
  IFS= read -r -d '' SUBSCRIPT_ORIG <"$1" && return 0
  SUBSCRIPT_GUARD=1
}

# subscript_spans <file> <reader>: prints "start end line" for each array
# subscript of the script on stdin; fails when the tree cannot be read. The
# script's pipefail carries a shfmt failure out of the pipeline, which runs
# shfmt and jq side by side rather than one after the other.
subscript_spans() {
  shfmt "$2" --filename "$1" 2>/dev/null |
    jq -r '.. | objects | select(.Index? | type == "object") | .Index | "\(.Pos.Offset) \(.End.Offset) \(.Pos.Line)"' 2>/dev/null
}

# subscript_text <source> <start> <end>: sets SUBSCRIPT_TEXT to the span
# widened over the blanks on both sides.
SUBSCRIPT_TEXT=""
subscript_text() {
  local src="$1" s="$2" e="$3"
  while ((s > 0)) && [[ "${src:s-1:1}" == [[:blank:]] ]]; do s=$((s - 1)); done
  while ((e < ${#src})) && [[ "${src:e:1}" == [[:blank:]] ]]; do e=$((e + 1)); done
  SUBSCRIPT_TEXT="${src:s:e-s}"
}

# subscript_guard_end <file> <reader>
subscript_guard_end() {
  local file="$1" reader="$2" LC_ALL=C new="" spans span s e l was now i
  local n=0 named="" first_was="" first_now="" noun="the array subscript" key="a different key"
  local -a before=() after=()
  ((SUBSCRIPT_GUARD)) || return 0
  IFS= read -r -d '' new <"$file"
  [[ "$new" == "$SUBSCRIPT_ORIG" ]] && return 0
  if spans=$(subscript_spans "$file" "$reader" <<<"$SUBSCRIPT_ORIG"); then
    while IFS= read -r span; do [[ -n "$span" ]] && before+=("$span"); done <<<"$spans"
    ((${#before[@]})) || return 0
    if spans=$(subscript_spans "$file" "$reader" <<<"$new"); then
      while IFS= read -r span; do [[ -n "$span" ]] && after+=("$span"); done <<<"$spans"
    fi
  fi
  if ((${#before[@]} == 0 || ${#after[@]} != ${#before[@]})); then
    printf '%s' "$SUBSCRIPT_ORIG" >"$file"
    append_notice "bash-format: shfmt rewrote $FILE_BASE but its syntax tree could not be read to check array subscripts, so $FILE_BASE was left as written."
    return 0
  fi
  for ((i = 0; i < ${#before[@]}; i++)); do
    span="${before[i]}"
    s="${span%% *}" span="${span#* }"
    e="${span%% *}" l="${span#* }"
    subscript_text "$SUBSCRIPT_ORIG" "$s" "$e"
    was="$SUBSCRIPT_TEXT"
    span="${after[i]}"
    s="${span%% *}" span="${span#* }"
    e="${span%% *}"
    subscript_text "$new" "$s" "$e"
    now="$SUBSCRIPT_TEXT"
    [[ "$was" == "$now" ]] && continue
    n=$((n + 1))
    if ((n == 1)); then
      first_was="$was" first_now="$now"
    elif ((n <= 5)); then
      named+=", "
    fi
    ((n <= 5)) && named+="\`[$was]\` on line $l as \`[$now]\`"
  done
  ((n)) || return 0
  ((n > 1)) && noun="the array subscripts" key="each a different key"
  ((n > 5)) && named+=", and $((n - 5)) more"
  printf '%s' "$SUBSCRIPT_ORIG" >"$file"
  append_notice "bash-format: shfmt would rewrite $noun $named, $key if the array is associative, so $FILE_BASE was left as written. Quote the key ([\"$first_was\"]) if the array is associative; if it is indexed, write it as shfmt prints it ([$first_now])."
}

# Tool path for shfmt/ShellCheck. On Windows/MSYS, Claude Code may hand the
# hook a POSIX mount path (`/c/...`), a mixed drive path (`C:/...`), or a
# backslash Win32 path. GHC-based ShellCheck opens paths via openBinaryFile and
# can fail that open on some spellings even when bash's `[[ -f ]]` succeeded on
# the original (#1817). Prefer cygpath's mixed long form when available so both
# tools see one stable existing path; fall back to FILE unchanged elsewhere.
# cygpath is looked up only on the Windows bash hosts (the OSTYPE set
# hook::repo_relative_path_to uses): elsewhere the lookup misses after probing
# every PATH directory, which on WSL includes the /mnt/c entries, one 9P round
# trip each.
TOOL_FILE="$FILE"
case "${OSTYPE:-}" in
msys* | cygwin* | win32)
  if command -v cygpath >/dev/null 2>&1; then
    _tool_lm=$(cygpath -lm -- "$FILE" 2>/dev/null)
    if [[ -n "$_tool_lm" && -f "$_tool_lm" ]]; then
      TOOL_FILE="$_tool_lm"
    fi
  fi
  ;;
*) ;;
esac

# Format pass (opt-in, mutating). No parser/printer flags — that keeps
# .editorconfig formatting in effect. --apply-ignore is a utility flag (not a
# parser/printer flag, so it does not disable editorconfig formatting): it makes
# shfmt honor `ignore = true` editorconfig rules for this single direct file,
# which it otherwise skips for direct-file invocations — so a repo's opt-out for
# generated/vendored scripts is respected, not overwritten.
# The consumer opted in via .editorconfig but shfmt is absent → visible
# once-per-session skip notice, not a silent gap (dim-9 doctrine). No opt-in →
# quiet (N/A, the repo chose not to format).
if shell_editorconfig_opt_in; then
  if command -v shfmt >/dev/null 2>&1; then
    # --apply-ignore requires shfmt 3.8+ (2024-02). Older versions reject the
    # flag, and they cannot honor direct-file ignore rules anyway — that is
    # exactly the capability the flag adds — so they get a plain in-place format.
    #
    # The version is decided by PROBING the flag, not by inferring it from a
    # failed format run. `--apply-ignore -w || -w` re-formatted WITHOUT the flag
    # whenever the first call failed for ANY reason, so a transient failure on a
    # 3.8+ shfmt silently discarded the repo's `ignore = true` opt-out and
    # re-tabbed a file the consumer had asked shfmt to leave alone (#1817). A
    # capability probe cannot confuse "this shfmt has no such flag" with "this
    # run failed": where the flag exists, a failing run now leaves the file
    # untouched, which is the only safe reading of a formatter that did not
    # complete.
    #
    # The probe's own failure is classified the same way: only a confirmed
    # unsupported-flag rejection (the Go flag parser's "flag provided but not
    # defined", or a wrapper's "unknown flag", naming apply-ignore) takes the
    # plain-format compatibility path. Any other probe failure — a wrapper
    # flaking on its first invocation, a transient exec error — says nothing
    # about the flag, so falling back would mutate through the same discarded
    # opt-out; the file is left untouched and the skip is said out loud.
    #
    # Re-check existence immediately before mutating: the earlier
    # hook::read_file_path guard can race a deleted scratch/worktree file, and
    # shfmt/ShellCheck then surface GHC's openBinaryFile error (#1817).
    if [[ -f "$TOOL_FILE" || -f "$FILE" ]]; then
      _fmt_target="$TOOL_FILE"
      [[ -f "$_fmt_target" ]] || _fmt_target="$FILE"
      # Content-mutation disclosure (#1596): shfmt rewrites structural layout
      # only; name the rewrite on the user channel and stay silent on no-op paths.
      hook::rewrite_guard_begin "$_fmt_target"
      subscript_guard_begin "$_fmt_target"
      # The tree reader follows the same probe: shfmt before 3.6 has only
      # -tojson, which every release through 3.14.1 still accepts with the
      # same subscript offsets.
      _tree_reader=""
      if probe_err=$(shfmt --apply-ignore --version 2>&1 >/dev/null); then
        _tree_reader=--to-json
        shfmt --apply-ignore -w "$_fmt_target" 2>/dev/null
      elif [[ "$probe_err" == *apply-ignore* ]] &&
        [[ "$probe_err" == *"flag provided but not defined"* || "$probe_err" == *"unknown flag"* ]]; then
        _tree_reader=-tojson
        shfmt -w "$_fmt_target" 2>/dev/null
      else
        append_notice "" "bash-format: shfmt probe failed (${probe_err%%$'\n'*}); $FILE_BASE not formatted."
      fi
      subscript_guard_end "$_fmt_target" "$_tree_reader"
      ran_any=1
    fi
  elif hook::prereq_notice_to SHFMT_MODEL SHFMT_USER shfmt "$INPUT"; then
    append_notice "$SHFMT_MODEL" "$SHFMT_USER"
  fi
fi

# Lint pass (always-on, non-mutating). -x follows `source`/`.` directives;
# -f gcc gives one finding per line; -S warning drops info/style noise. Config
# (.shellcheckrc) is auto-discovered from the file's directory upward.
# ShellCheck absent → visible once-per-session skip notice (dim-9 doctrine).
CTX=""
FINDINGS_JSON='[]'
if command -v shellcheck >/dev/null 2>&1; then
  # Same race window as the format pass: skip quietly if the file is already
  # gone rather than reporting GHC's openBinaryFile as a ShellCheck finding.
  if [[ -f "$TOOL_FILE" || -f "$FILE" ]]; then
    ran_any=1
    _lint_target="$TOOL_FILE"
    [[ -f "$_lint_target" ]] || _lint_target="$FILE"
    SC_OUTPUT=$(shellcheck -x -f gcc -S warning "$_lint_target" 2>&1) || true
    # If ShellCheck still failed to open the path, retry the original spelling
    # once — some hosts accept only one of the two forms — then drop any
    # remaining openBinaryFile noise so a path/race miss is never a finding.
    if [[ "$SC_OUTPUT" == *openBinaryFile* && "$_lint_target" != "$FILE" && -f "$FILE" ]]; then
      SC_OUTPUT=$(shellcheck -x -f gcc -S warning "$FILE" 2>&1) || true
    fi
    if [[ "$SC_OUTPUT" == *openBinaryFile* ]]; then
      SC_OUTPUT=$(printf '%s\n' "$SC_OUTPUT" | grep -v 'openBinaryFile' || true)
    fi
    # The heading names the file once, so each line drops the gcc format's path
    # prefix, in whichever spelling ShellCheck was handed. --delta sends a
    # finding set once per (session, agent, file); a clean run goes through it
    # too, so findings that come back after a fix are sent again.
    SC_OUTPUT=$'\n'"$SC_OUTPUT"
    SC_OUTPUT="${SC_OUTPUT//$'\n'"$_lint_target:"/$'\n'}"
    SC_OUTPUT="${SC_OUTPUT//$'\n'"$FILE:"/$'\n'}"
    hook::findings_to CTX "bash-format: $FILE_BASE has findings:" \
      "$SC_OUTPUT" FINDINGS_JSON --max 20 --delta "$INPUT" "$FILE"
  fi
elif hook::prereq_notice_to SC_MODEL SC_USER shellcheck "$INPUT"; then
  append_notice "$SC_MODEL" "$SC_USER"
fi

# hook::finish is the exit: it takes the shfmt disclosure (settling data.changed
# and releasing the snapshot whether or not shfmt ever ran), emits telemetry
# with that verdict, and composes the one JSON document — findings and the
# model's notices on the agent channel, the user's notices and the rewrite
# disclosure on the user channel. CTX arrives from hook::findings_to
# unterminated, so the notice joins onto it with a single newline.
if [[ -n "$MODEL_NOTICE" ]]; then
  [[ -n "$CTX" ]] && CTX+=$'\n'
  CTX+="$MODEL_NOTICE"
fi

status="ok"
[[ $ran_any -eq 0 ]] && status="skipped"
hook::finish --context "$CTX" --message "$USER_NOTICE" \
  --disclose "bash-format: reformatted $FILE_BASE." \
  "$status" findings array "$FINDINGS_JSON"
