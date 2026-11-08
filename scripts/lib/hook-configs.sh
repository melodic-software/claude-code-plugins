# shellcheck shell=bash
# The plugin hook-config corpus, enumerated once for every gate that reads it.
# Sourced, never executed. Callers run from the repository root.
#
# The corpus is every surface Claude Code loads a plugin hook from:
#   * the default `plugins/*/hooks/hooks.json`;
#   * a manifest `hooks` value (https://code.claude.com/docs/en/plugins-reference,
#     "hooks": "Path, object, or array of either"): a `.json` file path, an
#     inline event map, or an array mixing both. A pointed file goes through
#     scripts/lib/manifest-path-guard.sh, which refuses one outside the plugin;
#   * a top-level `hooks:` block in skill or agent YAML frontmatter, read by
#     scripts/check-hook-exec-form-frontmatter.py with a real YAML parser.
# A hooks/*.json file no manifest names is not loaded by Claude Code and is not
# part of the corpus. As of: 2026-11-08. Recheck when that page changes the
# accepted `hooks` shapes.
#
#   hook_configs::scan <gate> <on-hook> <on-unreadable>
#
# Calls <on-hook> once per hook object that carries a string `command`, in walk
# order (hooks.json files, inline manifest maps, pointed files, frontmatter):
#
#   <on-hook> <file> <where> <form> <args> <command> <argv>
#     where    jq path (`.hooks.Stop[0].hooks[0]`) or frontmatter line number
#     form     exec (an `args` key is present) | shell
#     args     array | none | other (present but not an array or sequence)
#     command  `command` with every CR, LF and TAB mapped to a space
#     argv     command plus array args joined by spaces, mapped the same way;
#              for frontmatter, the command alone
#
# Mapping instead of stripping keeps one hook on one row: a raw newline split
# the row, so `"node\n"` cleared as `node`, and its second line became a
# finding with the wrong file. Calls <on-unreadable> for input the walk could
# not read:
#
#   <on-unreadable> <surface> <file> <where> <detail>
#     surface  json (a hook config file) | manifest | frontmatter
#
# Each gate decides what an unreadable surface means for it. scan itself exits
# 2 when nothing could be inspected: no jq, no python with PyYAML (nor uv to
# borrow the CI pin), or a frontmatter reader that did not complete. Call it as
# a plain statement, never inside `if` or `||`, so the callbacks keep errexit.
#
#   hook_configs::sources <gate>
#
# Fills HOOK_CONFIG_SOURCES with one `<file><TAB><event-map jq path>` entry per
# JSON hook config: `.hooks` for a hooks.json or pointed file, `.hooks` or
# `.hooks[N]` for an inline map in a manifest. For gates that walk events
# rather than every hook object. An unreadable manifest is skipped here.
#
#   hook_configs::allowed_exec_name <command>
#
# True when <command> is on EXEC_NAME_ALLOWLIST below.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/hook-configs.sh is sourced-only\n' >&2
  exit 2
fi

# shellcheck source=manifest-path-guard.sh
. "$(dirname "${BASH_SOURCE[0]}")/manifest-path-guard.sh"

# Row fields are joined with US (0x1f), not TAB: a non-whitespace IFS keeps an
# empty field (the root path, an empty command) in its column.
HOOK_CONFIGS_SEP=$'\x1f'

# shellcheck disable=SC2016  # jq source, never shell-expanded
HOOK_CONFIGS_JQ_DEFS='
  def render: map(if type == "number" then "[" + tostring + "]" else "." + . end) | join("");
  def flat: gsub("[\r\n\t\u001f]"; " ");
  def hook_rows($file; $doc; $prefix):
    ([[]] + [$doc | paths(objects)])[] as $p
    | ($doc | getpath($p)) as $o
    | select(($o | type) == "object")
    | select(($o.command | type) == "string")
    | ($o | has("args")) as $exec
    | ($exec and (($o.args | type) == "array")) as $array
    | ["H", $file, $prefix + ($p | render),
       (if $exec then "exec" else "shell" end),
       (if $array then "array" elif $exec then "other" else "none" end),
       $o.command,
       ([$o.command] + (if $array then $o.args | map(tostring) else [] end) | join(" "))]
    | map(flat) | join("\u001f");
'

# Hook files: every hook row under the whole document.
# shellcheck disable=SC2016  # jq source, never shell-expanded
HOOK_CONFIGS_JQ_FILE="${HOOK_CONFIGS_JQ_DEFS}"'input_filename as $file | hook_rows($file; .; "")'

# Manifests. $mode rows: hook rows of each inline map, P rows for each path.
# $mode sources: I rows naming each inline map, P rows for each path.
# shellcheck disable=SC2016  # jq source, never shell-expanded
HOOK_CONFIGS_JQ_MANIFEST="${HOOK_CONFIGS_JQ_DEFS}"'
  input_filename as $file
  | def inline($doc; $at):
      if $mode == "rows" then hook_rows($file; $doc; $at) else ["I", $file, $at] | join("\u001f") end;
    def pointed($rel): ["P", $file, ($rel | flat)] | join("\u001f");
    .hooks as $h
    | if ($h | type) == "object" then inline($h; ".hooks")
      elif ($h | type) == "string" then pointed($h)
      elif ($h | type) == "array" then
        $h | to_entries[]
        | if (.value | type) == "string" then pointed(.value)
          elif (.value | type) == "object" then inline(.value; ".hooks[" + (.key | tostring) + "]")
          else empty end
      else empty end
'

# Bare exec-form `command` names admitted despite carrying no path separator,
# read by scripts/check-hook-exec-form.sh and
# scripts/check-exec-form-windows-probe.sh.
#
# Admission criterion is mechanical, not a judgment call about "real
# executables": a name qualifies only when NO Windows shim, relay, or App
# Execution Alias stub shadows it on PATH ahead of the real interpreter.
#   * `bash`, `sh`            -> shadowed by the WSL relay System32\bash.exe
#   * `python`, `python3`, `py` -> shadowed by zero-length WindowsApps stubs
#   * `node`                 -> no such shim exists; node.exe is the only
#                               resolution, which is why both
#                               docs/plugin-philosophy.md (Hooks row) and the
#                               harness-config audit checklist name
#                               `"command": "node", "args": [...]` as THE
#                               Windows-correct exec-form spelling.
# That criterion is NECESSARY but not SUFFICIENT, and the list is deliberately
# shorter than it allows: an entry must also answer a real, in-repo need that
# this repo's own docs sanction. `pwsh` and `deno` are unshimmed too and are
# still absent, because nothing here needs them — allowlist entries are
# demand-driven, never pre-emptive, since an unused entry is a hole nobody is
# watching. Adding a name is a reviewed change to this array plus its pinning
# test in scripts/check-hook-exec-form.test.sh — never a data-file edit.
#
# `bash` stays off this list. A bash-scripted row uses `"command": "node"` and
# `hooks/exec-bash.mjs` (canonical `lib/exec-bash.mjs`), which finds a real bash
# and never the WSL relay. Option gates are `--require-true` and
# `--run-if-unset-or-true` on that launcher, not a shell command line.
#   Claim: exec form offers no portable `command` that names Git Bash. `command`
#     is resolved on PATH (bare `bash` finds the WSL relay); `shell` is "Ignored
#     when `args` is set"; a `.sh` path as `command` is not a real executable
#     there (libuv EFTYPE); and the only placeholders are CLAUDE_PROJECT_DIR,
#     CLAUDE_PLUGIN_ROOT, CLAUDE_PLUGIN_DATA and `${user_config.*}`, none of
#     which names a shell. The gate-legal route is the `node` launcher above,
#     not an allowlist entry for `bash`.
#   Basis: https://code.claude.com/docs/en/hooks, "Command hook fields", the
#     `shell` row, verbatim: "Ignored when `args` is set". "Exec form and shell
#     form" resolves `command` on PATH and, on Windows, to a real executable.
#     https://github.com/anthropics/claude-code/issues/90495 (Windows exec-form
#     `args` dropped, the hook still routed through bash.exe): open, last
#     updated 2026-08-29.
#   As of: 2026-09-29.
#   Recheck: the hooks reference adds a shell or interpreter placeholder for
#     exec form, or stops ignoring `shell` when `args` is set; or #90495 closes.
EXEC_NAME_ALLOWLIST=(node)

# hook_configs::allowed_exec_name <command>
hook_configs::allowed_exec_name() {
  local name
  for name in "${EXEC_NAME_ALLOWLIST[@]}"; do
    [[ "$1" == "$name" ]] && return 0
  done
  return 1
}

# hook_configs::_need_jq <gate>
hook_configs::_need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "$1: jq is required but not installed" >&2
    exit 2
  fi
}

# hook_configs::_corpus: fills _HC_HOOK_JSONS and _HC_MANIFESTS.
hook_configs::_corpus() {
  local plugin
  _HC_HOOK_JSONS=()
  _HC_MANIFESTS=()
  for plugin in plugins/*/; do
    plugin="${plugin%/}"
    [[ -f "$plugin/hooks/hooks.json" ]] && _HC_HOOK_JSONS+=("$plugin/hooks/hooks.json")
    [[ -f "$plugin/.claude-plugin/plugin.json" ]] && _HC_MANIFESTS+=("$plugin/.claude-plugin/plugin.json")
  done
  return 0
}

# hook_configs::_manifest_out <out-var> <mode> <on-unreadable> <manifest...>
# One jq over every manifest; a batch failure falls back per file so the
# unreadable one is named. Output has its line-end CRs removed: every CR inside
# a value was already mapped to a space.
hook_configs::_manifest_out() {
  local -n _hc_mo="$1"
  local _hc_mode="$2" _hc_bad="$3" _hc_one _hc_f
  shift 3
  _hc_mo=""
  (($#)) || return 0
  if _hc_mo="$(jq -r --arg mode "$_hc_mode" "$HOOK_CONFIGS_JQ_MANIFEST" "$@" 2>/dev/null)"; then
    _hc_mo="${_hc_mo//$'\r'/}"
    return 0
  fi
  _hc_mo=""
  for _hc_f in "$@"; do
    if _hc_one="$(jq -r --arg mode "$_hc_mode" "$HOOK_CONFIGS_JQ_MANIFEST" "$_hc_f" 2>/dev/null)"; then
      _hc_mo+="${_hc_one//$'\r'/}"$'\n'
    elif [[ -n "$_hc_bad" ]]; then
      "$_hc_bad" manifest "$_hc_f" "" "not parseable as JSON"
    fi
  done
  return 0
}

# hook_configs::_pointed <gate> <seen-assoc> <out-array> <manifest> <rel>
hook_configs::_pointed() {
  local -n _hc_seen="$2" _hc_into="$3"
  local _hc_manifest="$4" _hc_path
  manifest_path_guard::resolve_to _hc_path "$1" "$_hc_manifest" "${_hc_manifest%/.claude-plugin/plugin.json}" "$5"
  [[ -f "$_hc_path" && -z "${_hc_seen[$_hc_path]:-}" ]] || return 0
  _hc_seen["$_hc_path"]=1
  _hc_into+=("$_hc_path")
}

# hook_configs::_scan_files <on-hook> <on-unreadable> <file...>
hook_configs::_scan_files() {
  local on_hook="$1" on_bad="$2" out f
  shift 2
  (($#)) || return 0
  if out="$(jq -r "$HOOK_CONFIGS_JQ_FILE" "$@" 2>/dev/null)"; then
    hook_configs::_dispatch "$on_hook" "${out//$'\r'/}"
    return 0
  fi
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    if ! out="$(jq -r "$HOOK_CONFIGS_JQ_FILE" "$f" 2>/dev/null)"; then
      "$on_bad" json "$f" "" "not parseable as JSON"
      continue
    fi
    hook_configs::_dispatch "$on_hook" "${out//$'\r'/}"
  done
}

# hook_configs::_dispatch <on-hook> <rows>: H rows only.
hook_configs::_dispatch() {
  local kind file where form args cmd argv
  while IFS="$HOOK_CONFIGS_SEP" read -r kind file where form args cmd argv; do
    [[ "$kind" == H ]] || continue
    "$1" "$file" "$where" "$form" "$args" "$cmd" "$argv"
  done <<<"$2"
}

# hook_configs::_reader <gate>: fills HOOK_CONFIGS_READER with the command that
# runs the frontmatter reader, resolved the way scripts/run-ruff.sh resolves its
# pinned tool: a python on PATH that imports yaml (CI, after the hash-locked
# install of .github/requirements-ci.txt), else `uv run --with pyyaml==<pin>`
# from that same file, else exit 2. Never a silent skip.
hook_configs::_reader() {
  local pin candidate
  HOOK_CONFIGS_READER=()
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
      HOOK_CONFIGS_READER=("$candidate")
      return 0
    fi
  done
  # First `pyyaml==VERSION` line; ignore trailing backslashes and hash pins.
  pin="$(awk '/^pyyaml==/ { sub(/^pyyaml==/, ""); sub(/[[:space:]\\].*$/, ""); print; exit }' \
    .github/requirements-ci.txt 2>/dev/null || true)"
  if [[ -n "$pin" ]] && command -v uv >/dev/null 2>&1; then
    HOOK_CONFIGS_READER=(uv run --quiet --no-project --with "pyyaml==$pin" python)
    return 0
  fi
  {
    echo "$1: no python with PyYAML available, and no uv to borrow one."
    echo "PyYAML reads the skill/agent frontmatter surface; without it this gate"
    echo "would clear files it never parsed, so it stops instead. Either:"
    echo "  * install the pin: pip install 'pyyaml==${pin:-<see .github/requirements-ci.txt>}'"
    echo "  * or install uv, which this script will use without touching your python"
  } >&2
  exit 2
}

# hook_configs::scan <gate> <on-hook> <on-unreadable>
hook_configs::scan() {
  local gate="$1" on_hook="$2" on_bad="$3" out kind file rest line detail
  local -a pointed=()
  local -A seen=()
  hook_configs::_need_jq "$gate"
  hook_configs::_reader "$gate"
  hook_configs::_corpus
  for file in ${_HC_HOOK_JSONS[@]+"${_HC_HOOK_JSONS[@]}"}; do
    seen["$file"]=1
  done
  hook_configs::_scan_files "$on_hook" "$on_bad" ${_HC_HOOK_JSONS[@]+"${_HC_HOOK_JSONS[@]}"}

  hook_configs::_manifest_out out rows "$on_bad" ${_HC_MANIFESTS[@]+"${_HC_MANIFESTS[@]}"}
  hook_configs::_dispatch "$on_hook" "$out"
  while IFS="$HOOK_CONFIGS_SEP" read -r kind file rest; do
    [[ "$kind" == P ]] || continue
    hook_configs::_pointed "$gate" seen pointed "$file" "$rest"
  done <<<"$out"
  hook_configs::_scan_files "$on_hook" "$on_bad" ${pointed[@]+"${pointed[@]}"}

  if ! out="$("${HOOK_CONFIGS_READER[@]}" scripts/check-hook-exec-form-frontmatter.py plugins)"; then
    echo "$gate: the frontmatter reader did not complete; this gate cannot clear plugins/" >&2
    exit 2
  fi
  while IFS=$'\t' read -r kind file line detail; do
    detail="${detail%$'\r'}"
    case "$kind" in
    V) "$on_hook" "$file" "$line" exec array "$detail" "$detail" ;;
    N) "$on_hook" "$file" "$line" exec other "$detail" "$detail" ;;
    S) "$on_hook" "$file" "$line" shell none "$detail" "$detail" ;;
    X) "$on_bad" frontmatter "$file" "$line" "$detail" ;;
    *) ;;
    esac
  done <<<"$out"
  return 0
}

# hook_configs::sources <gate>
hook_configs::sources() {
  local gate="$1" out kind file rest
  local -a pointed=()
  local -A seen=()
  hook_configs::_need_jq "$gate"
  hook_configs::_corpus
  HOOK_CONFIG_SOURCES=()
  for file in ${_HC_HOOK_JSONS[@]+"${_HC_HOOK_JSONS[@]}"}; do
    # shellcheck disable=SC2034  # read by hook_configs::_pointed through a nameref
    seen["$file"]=1
    HOOK_CONFIG_SOURCES+=("$file"$'\t'".hooks")
  done
  hook_configs::_manifest_out out sources "" ${_HC_MANIFESTS[@]+"${_HC_MANIFESTS[@]}"}
  while IFS="$HOOK_CONFIGS_SEP" read -r kind file rest; do
    case "$kind" in
    I) HOOK_CONFIG_SOURCES+=("$file"$'\t'"$rest") ;;
    P) hook_configs::_pointed "$gate" seen pointed "$file" "$rest" ;;
    *) ;;
    esac
  done <<<"$out"
  for file in ${pointed[@]+"${pointed[@]}"}; do
    HOOK_CONFIG_SOURCES+=("$file"$'\t'".hooks")
  done
  return 0
}
