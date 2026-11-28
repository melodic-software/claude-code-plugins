#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr
# shellcheck disable=SC2016  # jq programs and messages are literal text, never shell-expanded
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/hook-configs.sh
. scripts/lib/hook-configs.sh || exit 2

commands=0
FINDINGS=()
finding() {
  FINDINGS+=("$1")
}
print_findings() {
  ((${#FINDINGS[@]} == 0)) || printf '%s\n' "${FINDINGS[@]}" | LC_ALL=C sort >&2
}

declare -A SCRIPTS=()

plugin_of() {
  local rest="${1#plugins/}"
  printf 'plugins/%s' "${rest%%/*}"
}

consider() {
  local file="$1" where="$2" form="$3" cmd="$4" plugin seg word path first shebang
  local -a segs words
  commands=$((commands + 1))
  plugin="$(plugin_of "$file")"
  cmd="${cmd//&&/;}"
  cmd="${cmd//||/;}"
  cmd="${cmd//|/;}"
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

# shellcheck disable=SC2329  # called by hook_configs::scan by name
on_hook() {
  if [[ "$4" == other ]]; then
    finding "UNREADABLE HOOK CONFIG: ${1}:${2}: args is not an array; this gate cannot clear it"
  fi
  consider "$1" "$2" "$3" "$6"
}

# shellcheck disable=SC2329  # called by hook_configs::scan by name
on_unreadable() {
  case "$1" in
  frontmatter) finding "UNREADABLE FRONTMATTER: ${2}:${3}: ${4}" ;;
  *) finding "UNREADABLE HOOK CONFIG: ${2}: not parseable as JSON; this gate cannot clear it" ;;
  esac
}

hook_configs::scan check-hook-slow-shapes on_hook on_unreadable

if ((commands == 0)); then
  print_findings
  echo "check-hook-slow-shapes: no command hooks found; refusing to report clean" >&2
  exit 1
fi

READERS_RE='(^|[^A-Za-z0-9_-])(mapfile|readarray|cat|grep|jq|sed|awk)([^A-Za-z0-9_-]|$)'
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
  print_findings
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
