#!/usr/bin/env bash
# Gate: an exec-form hook must not resolve `command` as a bare PATH lookup.
#
#   scripts/check-hook-exec-form.sh    fail on any exec-form hook whose
#                                      `command` is a bare executable name
#
# Why: a hook object that carries `args` is in EXEC form, and exec form resolves
# `command` as an executable through PATH — it is not a shell command line. A
# bare name is therefore machine-dependent, and on Windows two spellings resolve
# to something that is not the interpreter the author meant:
#   * `bash`/`sh` -> the WSL relay C:\Windows\System32\bash.exe, which dies with
#     `execvpe(/bin/bash) failed: No such file or directory` when no distro
#     provides /bin/bash;
#   * `python`/`python3`/`py` -> the zero-length WindowsApps App Execution Alias
#     stub, which opens the Store instead of running the script.
# A failed hook launch is a NON-BLOCKING error, so a PreToolUse guard wired this
# way silently enforces nothing. That is not hypothetical: #1416 recorded 73
# launches of the disk-hygiene destructive guard, every one of them a
# `hook_non_blocking_error`, while the issue was closed COMPLETED.
#
# Why a gate rather than a checklist: this class has shipped three times.
# #1006 fixed it; #1504 reintroduced it while fixing a different resolution bug;
# #2570 fixed it again. `plugins/claude-config/skills/audit/reference/
# audit-checklist.md` Category D has carried it as an `error` row the whole
# time — a checklist a human reads is not a gate.
#
# The rule: exec form (an `args` key on the hook object) whose `command`
# contains NO path separator (`/` or `\`) fails, unless the name is on
# EXEC_NAME_ALLOWLIST below. Deliberately broader than a denylist of the names
# that have already burned us: a denylist can only ever hold the spellings
# someone was burned by, which is exactly how a {bash, sh} list would have waved
# `python3` through. `${CLAUDE_PLUGIN_ROOT}`-rooted and absolute paths carry a
# separator and pass untouched; so does shell form, which has no `args` at all
# and is never inspected here.
#
# Scope: the same hook-declaration surfaces the sibling userconfig-argv gate
# covers — the default `plugins/*/hooks/hooks.json`, any manifest-pointed hook
# config file (`hooks` as a string or an array of paths), and an inline manifest
# `hooks` object — PLUS skill/agent YAML frontmatter `hooks:` blocks, which that
# gate does not cover and which is where the third instance of this defect lived
# (#2568). A hooks/*.json file the manifest never references is not loaded by
# Claude Code and is not scanned. `.claude/settings.json` is repo-local developer
# config rather than shipped plugin surface and is out of scope; it declares no
# hooks today.
#
# Two parsers, one rule. JSON hook configs are read with `jq`, which parses that
# format completely. Frontmatter is read by
# scripts/check-hook-exec-form-frontmatter.py, which uses a real YAML parser for
# the reason its own doc-block records: a hand-rolled YAML walk lost three
# rounds of review to spellings it had not anticipated, and a gate that
# misparses is worse than no gate. Both readers only REPORT exec-form hooks; the
# rule below decides, so one implementation governs both surfaces.
#
# Relationship to scripts/check-hook-userconfig-argv.sh: complementary, not
# overlapping. That gate constrains WHETHER a `${user_config.*}` token may
# appear in a hook config; this one constrains WHAT SHAPE `command` takes once a
# hook is in exec form. Neither subsumes the other.
#
# Exit 0 = clean; 1 = one or more violations; 1 also for an environment problem
# (fail closed — never a silent skip).
# shellcheck disable=SC2016  # the jq program below is literal source, never shell-expanded
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-hook-exec-form: jq is required but not installed" >&2
  exit 1
fi

# How to run the frontmatter reader, resolved exactly the way scripts/run-ruff.sh
# resolves its pinned tool — the repo already had this problem and settled it:
#   1. a python on PATH that can already import yaml (the CI path, after the
#      hash-locked install of .github/requirements-ci.txt)
#   2. `uv run --with pyyaml==<pin>` when uv is available (cross-platform local
#      path; no global install, no virtualenv ceremony, and the same version CI
#      uses because the pin is read from that same file)
#   3. exit 1 — fail closed, never a silent skip
FRONTMATTER_READER="scripts/check-hook-exec-form-frontmatter.py"
REQUIREMENTS=".github/requirements-ci.txt"

# First `pyyaml==VERSION` line; ignore trailing backslashes / hash pins.
pyyaml_pin="$(awk '/^pyyaml==/ {
  sub(/^pyyaml==/, "")
  sub(/[[:space:]\\].*$/, "")
  print
  exit
}' "$REQUIREMENTS" 2>/dev/null || true)"

reader_cmd=()
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
    reader_cmd=("$candidate")
    break
  fi
done
if ((${#reader_cmd[@]} == 0)) && [[ -n "$pyyaml_pin" ]] && command -v uv >/dev/null 2>&1; then
  reader_cmd=(uv run --quiet --no-project --with "pyyaml==$pyyaml_pin" python)
fi
if ((${#reader_cmd[@]} == 0)); then
  {
    echo "check-hook-exec-form: no python with PyYAML available, and no uv to borrow one."
    echo "PyYAML reads the skill/agent frontmatter surface; without it this gate"
    echo "would clear files it never parsed, so it stops instead. Either:"
    echo "  * install the pin: pip install 'pyyaml==${pyyaml_pin:-<see $REQUIREMENTS>}'"
    echo "  * or install uv, which this script will use without touching your python"
  } >&2
  exit 1
fi

# Bare exec-form `command` names admitted despite carrying no path separator.
#
# Admission criterion is mechanical, not a judgement call about "real
# executables": a name qualifies only when NO Windows shim, relay, or App
# Execution Alias stub shadows it on PATH ahead of the real interpreter.
#   * `bash`, `sh`            -> shadowed by the WSL relay System32\bash.exe
#   * `python`, `python3`, `py` -> shadowed by zero-length WindowsApps stubs
#   * `node`                 -> no such shim exists; node.exe is the only
#                               resolution, which is why both
#                               docs/PLUGIN-PHILOSOPHY.md (Hooks row) and the
#                               claude-config audit checklist name
#                               `"command": "node", "args": [...]` as THE
#                               Windows-correct exec-form spelling.
# That criterion is NECESSARY but not SUFFICIENT, and the list is deliberately
# shorter than it allows: an entry must also answer a real, in-repo need that
# this repo's own docs sanction. `pwsh` and `deno` are unshimmed too and are
# still absent, because nothing here needs them — allowlist entries are
# demand-driven, never pre-emptive, since an unused entry is a hole nobody is
# watching. Adding a name is a reviewed change to this array plus its pinning
# test in scripts/check-hook-exec-form.test.sh — never a data-file edit.
EXEC_NAME_ALLOWLIST=(node)

errors=0
execform_errors=0

# is_bare <command> — true when the value carries no path separator in either
# spelling, i.e. Claude Code will resolve it through PATH.
is_bare() {
  case "$1" in
  */* | *\\*) return 1 ;;
  *) return 0 ;;
  esac
}

# allowed_name <command>
allowed_name() {
  local name
  for name in "${EXEC_NAME_ALLOWLIST[@]}"; do
    if [[ "$1" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

# flag <file> <where> <command>
flag() {
  local file="$1" where="$2" cmd="$3"
  echo "EXEC-FORM HOOK: ${file}:${where}: exec-form hook (\`args\` present) with bare command \"${cmd}\"" >&2
  errors=$((errors + 1))
  execform_errors=$((execform_errors + 1))
}

# consider <file> <where> <command> — apply the rule to one exec-form hook.
consider() {
  local file="$1" where="$2" cmd="$3"
  # shellcheck disable=SC2310  # is_bare/allowed_name are pure case/loop tests; neither can fail unexpectedly
  if ! is_bare "$cmd"; then
    return 0
  fi
  # shellcheck disable=SC2310  # see above
  if allowed_name "$cmd"; then
    return 0
  fi
  flag "$file" "$where" "$cmd"
}

# --- JSON hook configs ------------------------------------------------------

# Emits `<file>\t<jq-path>\t<command>` for every exec-form hook object reachable
# from __ROOT__. Recursive descent on purpose: `hooks` is an array in some
# manifests and an event-keyed object in others (the pre-#2570 disk-hygiene
# config was `.hooks.PreToolUse[0].hooks[0]`), and a shape-specific walk would
# miss one of them. The root path is included explicitly because jq's `paths`
# omits it. `input_filename` lets one jq process scan every file in the corpus
# (Command Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution). CRLF is stripped in jq so
# the separator test sees the real value without a `tr` exec per file.
JQ_EXEC_FORM='
  def render: map(if type == "number" then "[" + tostring + "]" else "." + . end) | join("");
  input_filename as $file
  | (__ROOT__) as $doc
  | ([[]] + [$doc | paths(objects)])[]
  | . as $p
  | ($doc | getpath($p)) as $o
  | select(($o | type) == "object")
  | select(($o | has("command")) and ($o | has("args")))
  | select(($o.command | type) == "string")
  | $file + "\t" + ($p | render) + "\t" + ($o.command | gsub("\r"; ""))
'

# scan_json_files <jq-root> <path-prefix> <file...>
#
# One jq over the files, same rule as a per-file scan. Fail closed on an
# unparsable hook config: a file this gate cannot read is a file this gate
# cannot clear. A batched jq that fails (one unreadable file aborts the rest)
# falls back to per-file so the diagnostic still names the offender; the live
# tree is valid JSON, so CI pays one jq.
scan_json_files() {
  local root="$1" prefix="$2"
  shift 2
  (($#)) || return 0
  local prog out file path cmd f
  prog="${JQ_EXEC_FORM//__ROOT__/$root}"
  if out="$(jq -r "$prog" "$@" 2>/dev/null)"; then
    while IFS=$'\t' read -r file path cmd; do
      [[ -n "$cmd" || -n "$path" || -n "$file" ]] || continue
      consider "$file" "${prefix}${path}" "$cmd"
    done <<<"$out"
    return 0
  fi
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    if ! out="$(jq -r "$prog" "$f" 2>/dev/null)"; then
      echo "UNREADABLE HOOK CONFIG: ${f}: not parseable as JSON — this gate cannot clear it" >&2
      errors=$((errors + 1))
      continue
    fi
    while IFS=$'\t' read -r file path cmd; do
      [[ -n "$cmd" || -n "$path" || -n "$file" ]] || continue
      consider "$file" "${prefix}${path}" "$cmd"
    done <<<"$out"
  done
}

# Manifest `.hooks` shape, one jq over every plugin.json. Unreadable manifests
# are skipped (manifest validity has its own gate); a batch failure falls back
# per-file so that skip still applies. Rows:
#   E<tab>file<tab>jq-path<tab>command  — inline object, already prefixed .hooks
#   P<tab>file<tab>rel                  — string or array-of-string hooks path
JQ_MANIFEST='
  def render: map(if type == "number" then "[" + tostring + "]" else "." + . end) | join("");
  input_filename as $file
  | (.hooks | type) as $t
  | if $t == "object" then
      (.hooks) as $doc
      | ([[]] + [$doc | paths(objects)])[]
      | . as $p
      | ($doc | getpath($p)) as $o
      | select(($o | type) == "object")
      | select(($o | has("command")) and ($o | has("args")))
      | select(($o.command | type) == "string")
      | "E\t" + $file + "\t" + ($p | render) + "\t" + ($o.command | gsub("\r"; ""))
    elif $t == "string" then
      "P\t" + $file + "\t" + (.hooks | gsub("\r"; ""))
    elif $t == "array" then
      .hooks[] | select(type == "string") | "P\t" + $file + "\t" + gsub("\r"; "")
    else
      empty
    end
'

# Extra hook-config paths queued from manifest string/array `.hooks` values.
# Global: bash 3.2 has no nameref, and a callee `eval` cannot append to a
# caller's `local -a`.
MANIFEST_EXTRA=()

scan_manifests() {
  (($#)) || return 0
  local out f
  MANIFEST_EXTRA=()
  if out="$(jq -r "$JQ_MANIFEST" "$@" 2>/dev/null)"; then
    _consume_manifest_rows "$out"
  else
    for f in "$@"; do
      [[ -f "$f" ]] || continue
      if out="$(jq -r "$JQ_MANIFEST" "$f" 2>/dev/null)"; then
        _consume_manifest_rows "$out"
      fi
    done
  fi
  ((${#MANIFEST_EXTRA[@]})) || return 0
  scan_json_files "." "" "${MANIFEST_EXTRA[@]}"
}

_consume_manifest_rows() {
  local rows="$1" kind file rest path cmd rel plugin
  while IFS=$'\t' read -r kind file rest; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
    E)
      path="${rest%%$'\t'*}"
      cmd="${rest#*$'\t'}"
      consider "$file" ".hooks${path}" "$cmd"
      ;;
    P)
      rel="$rest"
      plugin="${file%/.claude-plugin/plugin.json}"
      _queue_manifest_path "$plugin" "$file" "$rel"
      ;;
    *) ;;
    esac
  done <<<"$rows"
}

# Trust boundary, same rule the sibling gate applies: a manifest-pointed hook
# config must stay inside its own plugin directory. Reject absolute paths and
# any `..` segment (portable string check — no realpath dependency) with a
# visible skip, so a crafted manifest cannot point this gate at files outside
# the tree it claims to scan.
_queue_manifest_path() {
  local plugin="$1" manifest="$2" rel="$3" path
  [[ -n "$rel" ]] || return 0
  if [[ "$rel" == /* || "$rel" =~ ^[A-Za-z]: || "/$rel/" == *"/../"* ]]; then
    echo "check-hook-exec-form: skipping out-of-tree hooks path in $manifest: $rel" >&2
    return 0
  fi
  path="$plugin/${rel#./}"
  [[ -f "$path" ]] || return 0
  MANIFEST_EXTRA+=("$path")
}

# --- YAML frontmatter hooks blocks ------------------------------------------

# scan_frontmatter — one pass of the YAML reader over every markdown file under
# plugins/. It reports; the rule above decides. A reader that did not complete
# (exit 2: no PyYAML, bad usage) is an environment failure, not a clean tree, so
# it fails the gate rather than clearing 997 files by accident.
scan_frontmatter() {
  local out kind file line detail
  if ! out="$("${reader_cmd[@]}" "$FRONTMATTER_READER" plugins)"; then
    echo "UNREADABLE FRONTMATTER: the frontmatter reader did not complete — this gate cannot clear plugins/" >&2
    errors=$((errors + 1))
    return 0
  fi
  while IFS=$'\t' read -r kind file line detail; do
    case "$kind" in
    V) consider "$file" "$line" "$detail" ;;
    X)
      echo "UNREADABLE FRONTMATTER: ${file}:${line}: ${detail}" >&2
      errors=$((errors + 1))
      ;;
    *) ;;
    esac
  done <<<"$out"
}

# --- walk -------------------------------------------------------------------
# Default hooks.json and every plugin.json, each corpus in one jq. Manifest
# string/array `.hooks` paths queue a third (usually empty) batch. The previous
# walk paid one jq (and a `tr`) per hooks.json plus one-to-three jq per
# manifest (~96 jq on this tree).

hook_jsons=()
manifests=()
for plugin in plugins/*/; do
  plugin="${plugin%/}"
  [[ -f "$plugin/hooks/hooks.json" ]] && hook_jsons+=("$plugin/hooks/hooks.json")
  [[ -f "$plugin/.claude-plugin/plugin.json" ]] && manifests+=("$plugin/.claude-plugin/plugin.json")
done
scan_json_files "." "" "${hook_jsons[@]}"
scan_manifests "${manifests[@]}"

# Skill and agent frontmatter. Every markdown file under plugins/ is read, and
# only its frontmatter is interpreted, so a `hooks:` line in a prose body or a
# fenced example is never taken for a declaration.
scan_frontmatter

if ((errors > 0)); then
  if ((execform_errors == 0)); then
    cat >&2 <<'UNREADABLE'

Nothing above is an exec-form violation: the gate refused input it could not
read. That is deliberate — a hook declaration this gate cannot parse is one it
cannot clear, and clearing it anyway is the silent no-op the gate exists to
catch. Fix the malformed JSON or YAML and the gate will read it.
UNREADABLE
    exit 1
  fi
  cat >&2 <<'REMEDY'

An exec-form hook (a hook object carrying `args`) resolves `command` as an
executable through PATH — it is not a shell command line. A bare name is
machine-dependent: on Windows `bash` resolves to the WSL relay shipped as
bash.exe under System32, and `python3` to a zero-length WindowsApps App
Execution Alias stub, so the hook never launches. A failed launch is a
NON-BLOCKING error, so a PreToolUse guard wired this way silently enforces
nothing (#1416: 73 recorded runs, every one a hook_non_blocking_error, while
the guard was believed live).

Fix it the way #2570 did — shell form: the whole command line in `command`, no
`args`, and `shell: bash` so Claude Code resolves Git Bash itself instead of
doing a PATH lookup:

    "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh\" --flag",
    "shell": "bash"

Or keep exec form and give `command` a ${CLAUDE_PLUGIN_ROOT}-rooted or absolute
path to a real executable.
REMEDY
  exit 1
fi
echo "No exec-form hooks with a bare command name."
