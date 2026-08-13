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

# Emits `<jq-path>\t<command>` for every exec-form hook object reachable from
# __ROOT__. Recursive descent on purpose: `hooks` is an array in some manifests
# and an event-keyed object in others (the pre-#2570 disk-hygiene config was
# `.hooks.PreToolUse[0].hooks[0]`), and a shape-specific walk would miss one of
# them. The root path is included explicitly because jq's `paths` omits it.
JQ_EXEC_FORM='
  def render: map(if type == "number" then "[" + tostring + "]" else "." + . end) | join("");
  (__ROOT__) as $doc
  | ([[]] + [$doc | paths(objects)])[]
  | . as $p
  | ($doc | getpath($p)) as $o
  | select(($o | type) == "object")
  | select(($o | has("command")) and ($o | has("args")))
  | select(($o.command | type) == "string")
  | ($p | render) + "\t" + $o.command
'

# scan_json <file> <jq root expression> <reported path prefix>
#
# Fail closed on an unparsable hook config: a file this gate cannot read is a
# file this gate cannot clear, and silently skipping it would recreate the
# no-op-that-looks-green failure the gate exists to prevent. (The manifest's own
# validity is a different gate's job, and the inline-object call site is only
# reached after the manifest has already parsed.)
scan_json() {
  local file="$1" root="$2" prefix="$3" prog out path cmd
  [[ -f "$file" ]] || return 0
  prog="${JQ_EXEC_FORM//__ROOT__/$root}"
  # CRLF tolerance: on Windows (Git Bash) a checked-out JSON file can carry \r
  # inside string values; strip it so the separator test sees the real value.
  if ! out="$(jq -r "$prog" "$file" 2>/dev/null | tr -d '\r')"; then
    echo "UNREADABLE HOOK CONFIG: ${file}: not parseable as JSON — this gate cannot clear it" >&2
    errors=$((errors + 1))
    return 0
  fi
  while IFS=$'\t' read -r path cmd; do
    [[ -n "$cmd" || -n "$path" ]] || continue
    consider "$file" "${prefix}${path}" "$cmd"
  done <<<"$out"
}

# scan_manifest_path <plugin-dir> <manifest> <relative hooks path> — trust
# boundary, same rule the sibling gate applies: a manifest-pointed hook config
# must stay inside its own plugin directory. Reject absolute paths and any `..`
# segment (portable string check — no realpath dependency) with a visible skip,
# so a crafted manifest cannot point this gate at files outside the tree it
# claims to scan.
scan_manifest_path() {
  local plugin="$1" manifest="$2" rel="$3"
  [[ -n "$rel" ]] || return 0
  if [[ "$rel" == /* || "$rel" =~ ^[A-Za-z]: || "/$rel/" == *"/../"* ]]; then
    echo "check-hook-exec-form: skipping out-of-tree hooks path in $manifest: $rel" >&2
    return 0
  fi
  scan_json "$plugin/${rel#./}" "." ""
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

for plugin in plugins/*/; do
  plugin="${plugin%/}"
  manifest="$plugin/.claude-plugin/plugin.json"

  # Default location, always loaded when present.
  scan_json "$plugin/hooks/hooks.json" "." ""

  [[ -f "$manifest" ]] || continue
  hooks_type="$(jq -r '.hooks | type' "$manifest" 2>/dev/null | tr -d '\r' || echo invalid)"
  case "$hooks_type" in
  string)
    rel="$(jq -r '.hooks' "$manifest" | tr -d '\r')"
    scan_manifest_path "$plugin" "$manifest" "$rel"
    ;;
  array)
    while IFS= read -r rel; do
      rel="${rel%$'\r'}"
      scan_manifest_path "$plugin" "$manifest" "$rel"
    done < <(jq -r '.hooks[] | select(type == "string")' "$manifest" 2>/dev/null || true)
    ;;
  object)
    scan_json "$manifest" ".hooks" ".hooks"
    ;;
  *) ;; # null, absent, or unparsable manifest (manifest validity has its own gate)
  esac
done

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
