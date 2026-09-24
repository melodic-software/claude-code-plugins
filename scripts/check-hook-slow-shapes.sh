#!/usr/bin/env bash
# Gate: plugin hooks must not ship two shapes whose cost a spawn budget misses
# or that every fire pays for nothing.
#
#   scripts/check-hook-slow-shapes.sh   fail on either shape below
#
# (a) TRANSCRIPT READ. A registered hook script reads the whole session
#     transcript: `mapfile`, `readarray`, `cat`, `grep`, `jq`, `sed` or `awk`
#     over the transcript variable, or an input redirect from it (`while read
#     ... done <"$TRANSCRIPT"`), on a line with no `tail -c` / `head -c` bound.
#     The transcript grows every turn, so the read cost grows with it. #4408 was
#     `mapfile -s N <"$TRANSCRIPT"`: a bash builtin, zero extra processes, and
#     11.6 s per fire at a 10 MB transcript, which no spawn counter can see.
#     The transcript variable is any variable whose name contains
#     "transcript" (any case) in a script that mentions `.transcript_path`. That
#     is a naming heuristic, not dataflow: hook-failure-audit.sh takes the path
#     out of a library array (`HOOK_JQ_FIELDS[0]`), which no textual dataflow
#     rule follows. A read the script bounds some other way (a size check
#     above it) is excused by `slow-shape-ok: <reason>` on the line or the line
#     above. Out of reach: a path handed to another process (`--transcript
#     "$T"`), a variable filled by `read` or `printf -v` rather than `name=`,
#     readers not in the list (`wc`, `tac`), a read continued onto the next
#     line with a backslash, a read inside a library the script sources, and a
#     command whose text merely contains `tail -c` or `head -c` (`grep -c
#     "tail -c" "$T"` and the whole-file `tail -c +1 "$T"` read as bounded).
#     The hook-census `growth` ratchets in .performance/ratchets.json measure
#     the actual bytes read and are the behavioral check behind this text match.
#
# (b) ENV SHEBANG. A shell-form hook runs a script as its command word, with no
#     interpreter in front of it, and that script starts `#!/usr/bin/env`. The
#     kernel then runs /usr/bin/env, which looks up and execs the interpreter:
#     one extra exec on every fire. A leading `bash` (the #4421 shape,
#     `bash "${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh` with `"shell": "bash"`) execs
#     bash directly. Each `;`, `&&`, `||` and `|` segment is checked, so an
#     opt-in row's `exec "${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh` counts too. Exec
#     form (`args` present) is out of scope.
#
# Scope: the hook-declaration surfaces scripts/check-hook-exec-form.sh reads,
# read the same way: `plugins/*/hooks/hooks.json`, manifest-pointed hook configs
# (through scripts/lib/manifest-path-guard.sh), an inline manifest `hooks`
# object, and skill/agent frontmatter `hooks:` (through
# scripts/check-hook-exec-form-frontmatter.py, whose S records are the
# shell-form rows). Shape (a) scans every `.sh` word of every command that
# resolves to a file: `${CLAUDE_PLUGIN_ROOT}` paths, and bare names under the
# declaring plugin's hooks/ directory (launcher arguments).
#
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr (README.md,
# "The check-script contract"). An unparsable hook config is a finding (1), as in
# the exec-form gate: a file this gate cannot read is one it cannot clear.
# shellcheck disable=SC2016  # jq programs and messages are literal text, never shell-expanded
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/manifest-path-guard.sh
. scripts/lib/manifest-path-guard.sh || exit 2

if ! command -v jq >/dev/null 2>&1; then
  echo "check-hook-slow-shapes: jq is required but not installed" >&2
  exit 2
fi

# The frontmatter reader needs PyYAML, resolved the way check-hook-exec-form.sh
# resolves it: a python that imports yaml, else `uv run --with` the CI pin.
READER="scripts/check-hook-exec-form-frontmatter.py"
pyyaml_pin="$(awk '/^pyyaml==/ { sub(/^pyyaml==/, ""); sub(/[[:space:]\\].*$/, ""); print; exit }' \
  .github/requirements-ci.txt 2>/dev/null || true)"
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
  echo "check-hook-slow-shapes: no python with PyYAML and no uv; the frontmatter surface cannot be read" >&2
  exit 2
fi

commands=0
# Findings are buffered and printed once, sorted under LC_ALL=C, so the order
# never depends on glob collation, jq key order or the walk.
FINDINGS=()
finding() {
  FINDINGS+=("$1")
}

# Scripts shape (a) scans, keyed by path, each mapped to one declaring site.
declare -A SCRIPTS=()

# plugin_of <file>: plugins/<name> for any file under plugins/<name>/.
plugin_of() {
  local rest="${1#plugins/}"
  printf 'plugins/%s' "${rest%%/*}"
}

# consider <file> <where> <form> <command-line>
consider() {
  local file="$1" where="$2" form="$3" cmd="$4" plugin seg word path first shebang
  local -a segs words
  commands=$((commands + 1))
  plugin="$(plugin_of "$file")"
  cmd="${cmd//&&/;}"
  cmd="${cmd//||/;}"
  cmd="${cmd//|/;}"
  # ponytail: splits on ; && || | even inside quotes, and skips only `exec` and
  # VAR= as leading words (`env`, `timeout`, `nice` hide the script); no
  # registered command has either shape today.
  IFS=';' read -r -a segs <<<"$cmd"
  for seg in "${segs[@]}"; do
    read -r -a words <<<"$seg" || true
    ((${#words[@]})) || continue
    first=1
    for word in "${words[@]}"; do
      if ((first)) && [[ "$word" == exec || "$word" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        continue
      fi
      word="${word//\"/}"
      word="${word//\'/}"
      path="${word//\$\{CLAUDE_PLUGIN_ROOT\}/$plugin}"
      path="${path//\$CLAUDE_PLUGIN_ROOT/$plugin}"
      if ((first)) && [[ "$form" == shell && "$path" == */* && -f "$path" ]]; then
        shebang=""
        IFS= read -r shebang <"$path" || true
        if [[ "$shebang" == '#!/usr/bin/env'* ]]; then
          shebang="${shebang%$'\r'}"
          read -r _ interp _ <<<"$shebang" || true
          finding "ENV SHEBANG: ${file}:${where}: runs ${word} (${shebang}) with no interpreter prefix; register it as ${interp:-bash} ${word}"
        fi
      fi
      first=0
      [[ "$path" == *.sh ]] || continue
      [[ "$path" == */* ]] || path="$plugin/hooks/$path"
      if [[ -f "$path" ]]; then
        SCRIPTS["$path"]=1
      fi
    done
  done
  return 0
}

# Emits `<file>\t<jq-path>\t<shell|exec>\t<command [args...]>` for every object
# carrying a string `command` reachable from __ROOT__ (recursive descent, as in
# check-hook-exec-form.sh, because `hooks` is an array in some configs and an
# event-keyed object in others).
JQ_COMMANDS='
  def render: map(if type == "number" then "[" + tostring + "]" else "." + . end) | join("");
  input_filename as $file
  | (__ROOT__) as $doc
  | ([[]] + [$doc | paths(objects)])[] as $p
  | ($doc | getpath($p)) as $o
  | select(($o | type) == "object")
  | select(($o.command | type) == "string")
  | $file + "\t" + ($p | render) + "\t" + (if $o | has("args") then "exec" else "shell" end)
    + "\t" + ([$o.command] + (($o.args // []) | map(tostring)) | join(" ") | gsub("[\r\n\t]"; " "))
'

consume_rows() { # <prefix> <rows>
  local file path form cmd
  while IFS=$'\t' read -r file path form cmd; do
    [[ -n "$file" ]] || continue
    consider "$file" "$1$path" "$form" "${cmd%$'\r'}"
  done <<<"$2"
}

scan_json_files() { # <jq-root> <path-prefix> <file...>
  local prog="${JQ_COMMANDS//__ROOT__/$1}" prefix="$2" out f
  shift 2
  for f in "$@"; do
    if ! out="$(jq -r "$prog" "$f" 2>/dev/null)"; then
      finding "UNREADABLE HOOK CONFIG: ${f}: not parseable as JSON; this gate cannot clear it"
      continue
    fi
    consume_rows "$prefix" "$out"
  done
}

hook_jsons=()
resolved="" # written by manifest_path_guard::resolve_to through a nameref
for plugin in plugins/*/; do
  plugin="${plugin%/}"
  [[ -f "$plugin/hooks/hooks.json" ]] && hook_jsons+=("$plugin/hooks/hooks.json")
  manifest="$plugin/.claude-plugin/plugin.json"
  [[ -f "$manifest" ]] || continue
  # A native Windows jq ends lines with CRLF; every jq line read here drops the CR.
  if ! kind="$(jq -r '.hooks | type' "$manifest" 2>/dev/null)"; then
    finding "UNREADABLE HOOK CONFIG: ${manifest}: not parseable as JSON; this gate cannot clear it"
    continue
  fi
  case "${kind%$'\r'}" in
  object) scan_json_files ".hooks" ".hooks" "$manifest" ;;
  string | array)
    while IFS= read -r rel; do
      rel="${rel%$'\r'}"
      [[ -n "$rel" ]] || continue
      manifest_path_guard::resolve_to resolved check-hook-slow-shapes "$manifest" "$plugin" "$rel"
      [[ -f "$resolved" ]] && hook_jsons+=("$resolved")
    done < <(jq -r '.hooks | if type == "string" then . else .[] | select(type == "string") end' "$manifest")
    ;;
  *) ;;
  esac
done
((${#hook_jsons[@]} == 0)) || scan_json_files "." "" "${hook_jsons[@]}"

if ! fm="$("${reader_cmd[@]}" "$READER" plugins)"; then
  echo "check-hook-slow-shapes: the frontmatter reader did not complete; this gate cannot clear plugins/" >&2
  exit 2
fi
while IFS=$'\t' read -r kind file line detail; do
  detail="${detail%$'\r'}"
  case "$kind" in
  S) consider "$file" "$line" shell "$detail" ;;
  V) consider "$file" "$line" exec "$detail" ;;
  X) finding "UNREADABLE FRONTMATTER: ${file}:${line}: ${detail}" ;;
  *) ;;
  esac
done <<<"$fm"

if ((commands == 0)); then
  ((${#FINDINGS[@]} == 0)) || printf '%s\n' "${FINDINGS[@]}" | LC_ALL=C sort >&2
  echo "check-hook-slow-shapes: no command hooks found; refusing to report clean" >&2
  exit 1
fi

# --- shape (a) ---------------------------------------------------------------
READERS_RE='(^|[^A-Za-z0-9_-])(mapfile|readarray|cat|grep|jq|sed|awk)([^A-Za-z0-9_-]|$)'
# Sorted: an associative array's key order is unspecified, and the findings
# must come out in the same order on every run.
mapfile -t scripts < <(printf '%s\n' "${!SCRIPTS[@]}" | LC_ALL=C sort)
for script in ${scripts[@]+"${scripts[@]}"}; do
  [[ -n "$script" ]] || continue
  grep -q 'transcript_path' "$script" || continue
  mapfile -t vars < <(grep -oiE '[A-Za-z0-9_]*transcript[A-Za-z0-9_]*=' "$script" | tr -d '=' | sort -u)
  ((${#vars[@]})) || continue
  n=0
  prev=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    above="$prev"
    prev="$line"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *slow-shape-ok:* || "$above" == *slow-shape-ok:* ]] && continue
    # One simple command at a time: a bound counts only when it reads the file
    # itself (`tail -c N -- "$T"`), not from an earlier command on the line
    # (`head -c 1 x; cat "$T"`) or a later pipeline stage (`cat "$T" | head -c`).
    # ponytail: splits on ; & | inside quotes and $( ) too; that only splits
    # more finely, never joins a bound to a read it does not govern.
    segline="${line//&&/;}"
    segline="${segline//||/;}"
    segline="${segline//|/;}"
    segline="${segline//&/;}"
    IFS=';' read -r -a segs <<<"$segline"
    for seg in "${segs[@]}"; do
      [[ "$seg" == *'tail -c'* || "$seg" == *'head -c'* ]] && continue
      hit=""
      for v in "${vars[@]}"; do
        ref="\\\$\\{?${v}([^A-Za-z0-9_]|$)"
        redirect="(^|[^<])<[[:space:]]*\"?${ref}"
        [[ "$seg" =~ $ref ]] || continue
        if [[ "$seg" =~ $READERS_RE || "$seg" =~ $redirect ]]; then
          hit="$v"
          break
        fi
      done
      if [[ -n "$hit" ]]; then
        finding "TRANSCRIPT READ: ${script}:${n}: reads \$${hit} whole with no tail -c/head -c bound: ${line#"${line%%[![:space:]]*}"}"
        break
      fi
    done
  done <"$script"
done

if ((${#FINDINGS[@]} > 0)); then
  printf '%s\n' "${FINDINGS[@]}" | LC_ALL=C sort >&2
  cat >&2 <<'REMEDY'

ENV SHEBANG: prefix the command word with bash, keeping the path's quoting, and
pin "shell": "bash" on the row (the #4421 shape):
    "command": "bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/x.sh", "shell": "bash"
TRANSCRIPT READ: read a bounded tail (`tail -c N -- "$TRANSCRIPT"`) or resume
from a byte cursor, as hook-failure-audit.sh does since #4408. A read already
bounded by a size check above it takes `# slow-shape-ok: <reason>`.
REMEDY
  echo "check-hook-slow-shapes: ${#FINDINGS[@]} finding(s)" >&2
  exit 1
fi
printf 'check-hook-slow-shapes: %d hook command(s), %d script(s): no slow hook shapes\n' \
  "$commands" "${#SCRIPTS[@]}"
