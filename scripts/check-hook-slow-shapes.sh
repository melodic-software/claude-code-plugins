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
#     The transcript grows every turn, so the read cost grows with it. A builtin
#     read such as `mapfile -s N <"$TRANSCRIPT"` spawns no process, so no spawn
#     counter can see it.
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
#     one extra exec on every fire. A leading `bash`
#     (`bash "${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh` with `"shell": "bash"`) execs
#     bash directly. Each `;`, `&&`, `||` and `|` segment is checked, so an
#     opt-in row's `exec "${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh` counts too. Exec
#     form (`args` present) is out of scope.
#
# Scope: the plugin hook-config corpus scripts/lib/hook-configs.sh enumerates
# (hooks.json, manifest-pointed and inline manifest configs, skill/agent
# frontmatter `hooks:`), the same one scripts/check-hook-exec-form.sh reads.
# Shape (a) scans every `.sh` word of every command that resolves to a file:
# `${CLAUDE_PLUGIN_ROOT}` paths, and bare names under the declaring plugin's
# hooks/ directory (launcher arguments).
#
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr (scripts/README.md,
# "The check-script contract"). An unparsable hook config is a finding (1), as in
# the exec-form gate: a file this gate cannot read is one it cannot clear.
# shellcheck disable=SC2016  # jq programs and messages are literal text, never shell-expanded
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/hook-configs.sh
. scripts/lib/hook-configs.sh || exit 2

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

# on_hook <file> <where> <form> <args> <command> <argv>. A non-array `args`
# leaves the command line unreadable, so it is a finding as well as a command.
# shellcheck disable=SC2329  # called by hook_configs::scan by name
on_hook() {
  if [[ "$4" == other ]]; then
    finding "UNREADABLE HOOK CONFIG: ${1}:${2}: args is not an array; this gate cannot clear it"
  fi
  consider "$1" "$2" "$3" "$6"
}

# on_unreadable <surface> <file> <where> <detail>: every unreadable surface,
# an unparsable manifest included, is a finding.
# shellcheck disable=SC2329  # called by hook_configs::scan by name
on_unreadable() {
  case "$1" in
  frontmatter) finding "UNREADABLE FRONTMATTER: ${2}:${3}: ${4}" ;;
  *) finding "UNREADABLE HOOK CONFIG: ${2}: not parseable as JSON; this gate cannot clear it" ;;
  esac
}

hook_configs::scan check-hook-slow-shapes on_hook on_unreadable

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
