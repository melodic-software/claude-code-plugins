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
# gate does not cover and which is where the surviving instance of this defect
# lives (#2568). A hooks/*.json file the manifest never references is not loaded
# by Claude Code and is not scanned. `.claude/settings.json` is repo-local
# developer config rather than shipped plugin surface and is out of scope; it
# declares no hooks today.
#
# Relationship to scripts/check-hook-userconfig-argv.sh: complementary, not
# overlapping. That gate constrains WHETHER a `${user_config.*}` token may
# appear in a hook config; this one constrains WHAT SHAPE `command` takes once a
# hook is in exec form. Neither subsumes the other.
#
# Exit 0 = clean; 1 = one or more violations; 1 also for an environment problem
# (fail closed — never a silent skip).
# shellcheck disable=SC2016  # the jq and awk programs below are literal source, never shell-expanded
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-hook-exec-form: jq is required but not installed" >&2
  exit 1
fi
if ! command -v awk >/dev/null 2>&1; then
  echo "check-hook-exec-form: awk is required but not installed" >&2
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
# Adding a name is a reviewed change to this array plus its pinning test in
# scripts/check-hook-exec-form.test.sh — never a data-file edit.
EXEC_NAME_ALLOWLIST=(node)

errors=0

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
scan_json() {
  local file="$1" root="$2" prefix="$3" prog path cmd
  [[ -f "$file" ]] || return 0
  prog="${JQ_EXEC_FORM//__ROOT__/$root}"
  # CRLF tolerance: on Windows (Git Bash) a checked-out JSON file can carry \r
  # inside string values; strip it so the separator test sees the real value.
  while IFS=$'\t' read -r path cmd; do
    [[ -n "$cmd" || -n "$path" ]] || continue
    consider "$file" "${prefix}${path}" "$cmd"
  done < <(jq -r "$prog" "$file" 2>/dev/null | tr -d '\r' || true)
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

# Minimal, purpose-built block-style YAML walk over a skill/agent frontmatter
# `hooks:` block. It tracks list items by indentation and reports every hook
# object carrying both `command` and `args`; the bareness rule stays in bash so
# one implementation governs both surfaces. Flow-style mappings (`{...}`) are
# NOT parsed — they fail the gate loudly rather than being walked wrongly, which
# is the fail-closed direction for a detector whose whole job is catching a
# silent no-op.
FRONTMATTER_AWK=$(
  cat <<'AWK'
function trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

function indent_of(s,   n) {
  n = 0
  while (substr(s, n + 1, 1) == " ") n++
  return n
}

# YAML scalar on the right of `key:`: single/double quoted (with backslash
# escapes inside double quotes) or plain with an optional trailing comment.
function parse_value(v,   q, i, c, out) {
  v = trim(v)
  if (v == "") return ""
  q = substr(v, 1, 1)
  if (q == "\"" || q == "'") {
    out = ""
    for (i = 2; i <= length(v); i++) {
      c = substr(v, i, 1)
      if (c == "\\" && q == "\"") {
        i++
        out = out substr(v, i, 1)
        continue
      }
      if (c == q) break
      out = out c
    }
    return out
  }
  i = index(v, " #")
  if (i > 0) v = substr(v, 1, i - 1)
  return trim(v)
}

function push(k, ln) {
  top++
  kindent[top] = k
  hascmd[top] = 0
  hasargs[top] = 0
  cmdval[top] = ""
  cmdline[top] = ln
}

function pop() {
  if (top == 0) return
  if (hascmd[top] && hasargs[top]) printf("V\t%d\t%s\n", cmdline[top], cmdval[top])
  top--
}

function close_deeper(ind) {
  while (top > 0 && kindent[top] > ind) pop()
}

function flush_all() {
  while (top > 0) pop()
}

function record_kv(s,   c, key, val) {
  if (top == 0) return
  c = index(s, ":")
  if (c == 0) return
  key = trim(substr(s, 1, c - 1))
  gsub(/^["']/, "", key)
  gsub(/["']$/, "", key)
  val = substr(s, c + 1)
  if (key == "command") {
    hascmd[top] = 1
    cmdval[top] = parse_value(val)
    cmdline[top] = NR
  } else if (key == "args") {
    hasargs[top] = 1
  }
}

function is_hooks_key(s) {
  return (s ~ /^[[:space:]]*hooks:[[:space:]]*(#.*)?$/)
}

function handle(line,   ind, rest, kidx) {
  if (line ~ /^[[:space:]]*$/) return
  if (line ~ /^[[:space:]]*#/) return
  ind = indent_of(line)

  if (!inhooks) {
    if (is_hooks_key(line)) {
      inhooks = 1
      hooks_indent = ind
    }
    return
  }

  if (ind <= hooks_indent) {
    flush_all()
    inhooks = 0
    hooks_indent = -1
    if (is_hooks_key(line)) {
      inhooks = 1
      hooks_indent = ind
    }
    return
  }

  # A `{` that is not the opening of a ${...} placeholder means flow style.
  if (line ~ /(^|[^$])[{]/) {
    flow = 1
    if (flowline == 0) flowline = NR
    return
  }

  if (line ~ /^[[:space:]]*-/) {
    rest = substr(line, ind + 2)
    close_deeper(ind)
    if (rest ~ /^[[:space:]]*$/) {
      kidx = -1
    } else {
      kidx = ind + 1 + indent_of(rest)
    }
    push(kidx, NR)
    if (kidx >= 0) record_kv(trim(rest))
    return
  }

  if (line ~ /^[[:space:]]*[^-[:space:]#][^:]*:/) {
    close_deeper(ind)
    if (top > 0 && kindent[top] == -1) kindent[top] = ind
    if (top > 0 && kindent[top] == ind) record_kv(trim(line))
    return
  }
}

BEGIN {
  state = 0
  inhooks = 0
  hooks_indent = -1
  top = 0
  flow = 0
  flowline = 0
}

{
  line = $0
  sub(/\r$/, "", line)

  if (state == 0) {
    if (NR == 1 && line == "---") {
      state = 1
      next
    }
    exit
  }

  if (line == "---" || line == "...") {
    flush_all()
    state = 2
    exit
  }

  handle(line)
}

END {
  if (state == 1) flush_all()
  if (flow) printf("F\t%d\t\n", flowline)
}
AWK
)

# scan_frontmatter <markdown file>
scan_frontmatter() {
  local file="$1" kind line cmd
  [[ -f "$file" ]] || return 0
  while IFS=$'\t' read -r kind line cmd; do
    case "$kind" in
    V) consider "$file" "$line" "$cmd" ;;
    F)
      echo "EXEC-FORM HOOK: ${file}:${line}: flow-style YAML in a frontmatter hooks block is not parseable by this gate — rewrite the block in block style" >&2
      errors=$((errors + 1))
      ;;
    *) ;;
    esac
  done < <(awk "$FRONTMATTER_AWK" "$file" || true)
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

# Skill and agent frontmatter. The grep only narrows the candidate set; the awk
# pass is what decides, and it looks at frontmatter only, so a `hooks:` line in
# a prose body or a fenced example is never read as a declaration.
while IFS= read -r md; do
  [[ -n "$md" ]] || continue
  scan_frontmatter "$md"
done < <(grep -rlE '^[[:space:]]*hooks:' --include='*.md' plugins/ 2>/dev/null | tr -d '\r' | sort || true)

if ((errors > 0)); then
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
