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
# That criterion is NECESSARY but not SUFFICIENT, and the list is deliberately
# shorter than it allows: an entry must also answer a real, in-repo need that
# this repo's own docs sanction. `pwsh` and `deno` are unshimmed too and are
# still absent, because nothing here needs them — allowlist entries are
# demand-driven, never pre-emptive, since an unused entry is a hole nobody is
# watching. Adding a name is a reviewed change to this array plus its pinning
# test in scripts/check-hook-exec-form.test.sh — never a data-file edit.
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

# Purpose-built block-style YAML walk over a skill/agent frontmatter `hooks:`
# block. It tracks list items by indentation and reports every hook object
# carrying both `command` and `args`; the bareness rule stays in bash so one
# implementation governs both surfaces.
#
# Two design commitments, both learned from review findings on this gate:
#
#  1. NO SPELLING PREFILTER. Every *.md under plugins/ is handed to the walk,
#     which decides. Trying to grep for the key first meant enumerating its
#     spellings, and YAML has unboundedly many: `hooks:`, `"hooks":`,
#     `'hooks':`, `hooks :`, and escaped forms such as `"hooks":` that
#     decode to the same key. A file the prefilter drops is a file the gate
#     never looks at, so the prefilter is simply gone. Double-quoted keys and
#     scalars are escape-DECODED here (\uXXXX, \xXX, \\, \", …) before
#     comparison, the same move the sibling userconfig-argv gate makes for
#     \u-escaped JSON.
#
#  2. FAIL CLOSED ON ANYTHING IT CANNOT WALK. Inside a hooks block, a line that
#     is not blank, a comment, a list item, or a `key:` mapping — a YAML alias
#     (`*shared`), an anchor (`&base`), a merge key (`<<: *base`), a flow
#     mapping (`{...}`), a block scalar's continuation — is REPORTED, never
#     skipped. Each of those expands to structure this walk does not model, and
#     a detector whose whole job is catching a silent no-op must not have one of
#     its own. Outside a hooks block nothing is judged, so unrelated frontmatter
#     shapes cannot produce a false positive.
#
# The `hooks` key is recognised only as a TOP-LEVEL frontmatter key (indent 0),
# which is the only position Claude Code reads one from; that also keeps an
# indented `hooks:` inside some other key's value from being mistaken for a
# declaration now that every markdown file is walked.
FRONTMATTER_AWK=$(
  cat <<'AWK'
function trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

function trim_left(s) {
  sub(/^[[:space:]]+/, "", s)
  return s
}

function indent_of(s,   n) {
  n = 0
  while (substr(s, n + 1, 1) == " ") n++
  return n
}

function hexval(h,   i, c, v, d) {
  v = 0
  if (length(h) == 0) return -1
  for (i = 1; i <= length(h); i++) {
    c = tolower(substr(h, i, 1))
    d = index("0123456789abcdef", c) - 1
    if (d < 0) return -1
    v = v * 16 + d
  }
  return v
}

# YAML double-quoted escapes. Non-ASCII code points collapse to "?" -- they can
# never spell part of `hooks`, and the value side only needs the path-separator
# test, which no escape above 127 can satisfy.
function decode_double(s,   i, c, out, h, v) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c != "\\") {
      out = out c
      continue
    }
    i++
    c = substr(s, i, 1)
    if (c == "u") {
      h = substr(s, i + 1, 4)
      i += 4
      v = hexval(h)
      out = out ((v >= 1 && v < 128) ? sprintf("%c", v) : "?")
      continue
    }
    if (c == "x") {
      h = substr(s, i + 1, 2)
      i += 2
      v = hexval(h)
      out = out ((v >= 1 && v < 128) ? sprintf("%c", v) : "?")
      continue
    }
    if (c == "n") { out = out "\n"; continue }
    if (c == "t") { out = out "\t"; continue }
    out = out c
  }
  return out
}

# A YAML scalar: double-quoted (escape-decoded), single-quoted ('' -> '), or
# plain with an optional trailing comment.
function parse_scalar(v,   q, i, c, raw) {
  v = trim(v)
  if (v == "") return ""
  q = substr(v, 1, 1)
  if (q == "\"") {
    raw = ""
    for (i = 2; i <= length(v); i++) {
      c = substr(v, i, 1)
      if (c == "\\") {
        raw = raw c substr(v, i + 1, 1)
        i++
        continue
      }
      if (c == "\"") break
      raw = raw c
    }
    return decode_double(raw)
  }
  if (q == "'") {
    raw = ""
    for (i = 2; i <= length(v); i++) {
      c = substr(v, i, 1)
      if (c == "'") {
        if (substr(v, i + 1, 1) == "'") {
          raw = raw "'"
          i++
          continue
        }
        break
      }
      raw = raw c
    }
    return raw
  }
  i = index(v, " #")
  if (i > 0) v = substr(v, 1, i - 1)
  return trim(v)
}

# split_kv(s) -> 1 when s is a `key: value` mapping line, setting G_key (decoded)
# and G_val (the raw remainder, untrimmed of quotes).
function split_kv(s,   q, i, c, k, rest, n) {
  s = trim_left(s)
  if (s == "") return 0
  q = substr(s, 1, 1)
  if (q == "\"" || q == "'") {
    k = ""
    for (i = 2; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q == "\"" && c == "\\") {
        k = k c substr(s, i + 1, 1)
        i++
        continue
      }
      if (c == q) break
      k = k c
    }
    if (i > length(s)) return 0
    rest = trim_left(substr(s, i + 1))
    if (substr(rest, 1, 1) != ":") return 0
    G_key = (q == "\"") ? decode_double(k) : k
    G_val = trim(substr(rest, 2))
    return 1
  }
  n = index(s, ":")
  if (n == 0) return 0
  k = trim(substr(s, 1, n - 1))
  if (k == "") return 0
  G_key = k
  G_val = trim(substr(s, n + 1))
  return 1
}

function emit_v(ln, val) { printf("V\t%s\t%d\t%s\n", curfile, ln, val) }

function emit_x(ln, reason) {
  printf("X\t%s\t%d\t%s\n", curfile, ln, reason)
  top = 0
  state = 2
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
  if (hascmd[top] && hasargs[top]) emit_v(cmdline[top], cmdval[top])
  top--
}

function close_deeper(ind) {
  while (top > 0 && kindent[top] > ind) pop()
}

function flush_all() {
  while (top > 0) pop()
}

function record_kv(   ) {
  if (top == 0) return
  if (G_key == "command") {
    hascmd[top] = 1
    cmdval[top] = parse_scalar(G_val)
    cmdline[top] = FNR
  } else if (G_key == "args") {
    hasargs[top] = 1
  }
}

function handle(line,   ind, rest, kidx, isdash) {
  if (line ~ /^[[:space:]]*$/) return
  if (line ~ /^[[:space:]]*#/) return
  ind = indent_of(line)
  isdash = (line ~ /^[[:space:]]*-([[:space:]]|$)/)

  if (!inhooks) {
    # Only a top-level frontmatter key declares hooks.
    if (ind != 0) return
    if (!split_kv(line)) return
    if (G_key != "hooks") return
    if (G_val != "") {
      emit_x(FNR, "the hooks key carries its whole declaration on the key line (flow mapping, anchor, or alias); this gate walks block style only")
      return
    }
    inhooks = 1
    return
  }

  # A sequence may sit at the key's own indentation, so only a non-dash line at
  # or left of it closes the block.
  if (ind == 0 && !isdash) {
    flush_all()
    inhooks = 0
    handle(line)
    return
  }

  # A `{` that is not the opening of a ${...} placeholder means flow style.
  if (line ~ /(^|[^$])[{]/) {
    emit_x(FNR, "flow-style YAML mapping in a hooks block; this gate walks block style only")
    return
  }

  if (isdash) {
    rest = substr(line, ind + 2)
    close_deeper(ind)
    if (trim(rest) ~ /^[&*]/) {
      emit_x(FNR, "YAML anchor or alias in a hooks block; this gate cannot expand one")
      return
    }
    if (rest ~ /^[[:space:]]*$/) {
      kidx = -1
    } else {
      kidx = ind + 1 + indent_of(rest)
    }
    push(kidx, FNR)
    # A list item that is not a mapping is a plain scalar -- `args:` as a block
    # sequence is exactly this, and it is walkable: a scalar can never be a hook
    # object, so the pushed frame simply pops with no keys recorded.
    if (kidx >= 0 && split_kv(rest)) {
      if (G_val ~ /^[&*]/) {
        emit_x(FNR, "YAML anchor or alias in a hooks block; this gate cannot expand one")
        return
      }
      record_kv()
    }
    return
  }

  if (trim(line) ~ /^[&*]/) {
    emit_x(FNR, "YAML anchor or alias in a hooks block; this gate cannot expand one")
    return
  }

  if (split_kv(line)) {
    close_deeper(ind)
    if (G_val ~ /^[&*]/) {
      emit_x(FNR, "YAML anchor or alias in a hooks block; this gate cannot expand one")
      return
    }
    if (top > 0 && kindent[top] == -1) kindent[top] = ind
    if (top > 0 && kindent[top] == ind) record_kv()
    return
  }

  emit_x(FNR, "a line in a hooks block this gate cannot classify (alias, block scalar, or other non-block-style YAML)")
}

FNR == 1 {
  flush_all()
  curfile = FILENAME
  inhooks = 0
  top = 0
  line = $0
  sub(/\r$/, "", line)
  state = (line == "---") ? 1 : 2
  next
}

state != 1 { next }

{
  line = $0
  sub(/\r$/, "", line)
  if (line == "---" || line == "...") {
    flush_all()
    state = 2
    next
  }
  handle(line)
}

END { flush_all() }
AWK
)

# scan_frontmatter — one awk pass over every markdown file under plugins/. Fail
# closed for the same reason scan_json does: a pass that did not complete has
# cleared nothing. `find -exec … +` batches the argument list, and awk resets
# its own state per file, so the batching is invisible to the result.
scan_frontmatter() {
  local out kind file line detail
  if ! out="$(find plugins -type f -name '*.md' -exec awk "$FRONTMATTER_AWK" {} +)"; then
    echo "UNREADABLE FRONTMATTER: the frontmatter walk over plugins/ did not complete — this gate cannot clear it" >&2
    errors=$((errors + 1))
    return 0
  fi
  while IFS=$'\t' read -r kind file line detail; do
    case "$kind" in
    V) consider "$file" "$line" "$detail" ;;
    X)
      echo "UNWALKABLE HOOKS BLOCK: ${file}:${line}: ${detail}" >&2
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

# Skill and agent frontmatter. Every markdown file under plugins/ is walked (no
# spelling prefilter — see the walk's doc-block), and the walk reads frontmatter
# only, so a `hooks:` line in a prose body or a fenced example is never read as
# a declaration.
scan_frontmatter

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
