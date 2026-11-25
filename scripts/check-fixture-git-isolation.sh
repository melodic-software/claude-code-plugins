#!/usr/bin/env bash
# Exit: 0 clean, 1 a violation or a stale baseline entry, 2 usage.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "$SCRIPT_DIR/.." || exit 1
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

BASELINE="scripts/fixture-git-isolation-baseline.txt"
GBASELINE="scripts/fixture-git-global-baseline.txt"
mode="check"
case "${1:-}" in
"" | --check) ;;
--list) mode="list" ;;
*)
  echo "usage: scripts/check-fixture-git-isolation.sh [--check|--list]" >&2
  exit 2
  ;;
esac

scan() {
  awk -f "$SCRIPT_DIR/lib/fixture-git-isolation-scan.awk" "$@"
}

declare -A ISOLATING_BASENAME=() IS_FIXTURE=() CLEARS_FILE=() SCOPED=() SOURCES=()
declare -A GEV=() BYBASE=() GHARNESS=()

mapfile -t tracked < <(git ls-files '*.sh' '*.py' 2>/dev/null)
((${#tracked[@]} > 0)) || {
  echo "error: no tracked *.sh or *.py files found — run from inside the repository" >&2
  exit 2
}
mapfile -t js_suites < <(git ls-files '*.test.mjs' '*.test.js' '*.test.cjs' '*.test.ts' 2>/dev/null)
declare -A IS_TRACKED=()
for f in "${tracked[@]}"; do
  IS_TRACKED["$f"]=1
  [[ "$f" == *.sh ]] && BYBASE["${f##*/}"]+=" $f"
done

while IFS=$'\t' read -r kind file extra; do
  case "$kind" in
  CLEARS)
    ISOLATING_BASENAME["${file##*/}"]=1
    CLEARS_FILE["$file"]=1
    ;;
  FIXTURE) IS_FIXTURE["$file"]=1 ;;
  SCOPE) SCOPED["$file"]=1 ;;
  SOURCE) SOURCES["$file"]="${SOURCES["$file"]:-} $extra" ;;
  G) GEV["$file"]+=" ${extra//$'\t'/:}" ;;
  *) ;;
  esac
done < <(scan "${tracked[@]}" ${js_suites[@]+"${js_suites[@]}"})

g_eval() {
  local ev kind rest ln arg state=0 fstate=0 bad="" bit late="" deferred
  local -A fin=()
  for ev in ${GEV["$1"]:-}; do
    [[ "$ev" == K:* ]] || continue
    arg="${ev#K:*:}"
    fin["${arg%%=*}"]="${arg#*=}"
  done
  for ev in ${GEV["$1"]:-}; do
    kind="${ev%%:*}" rest="${ev#*:}"
    ln="${rest%%:*}" arg="${rest#*:}"
    bit=1
    [[ "$arg" == N ]] && bit=2
    case "$kind" in
    S) state=$((state | bit)) fstate=$((fstate | bit)) ;;
    U) state=$((state & ~bit)) fstate=$((fstate & ~bit)) ;;
    s) fstate=$((fstate | bit)) ;;
    u) fstate=$((fstate & ~bit)) ;;
    D)
      deferred=0
      [[ "$arg" == *:F ]] && arg="${arg%:F}" deferred=1
      case "${fin[$arg]:-inherit}" in
      full) ;;
      fresh) [[ -n "$bad" ]] || bad="$ln" ;;
      *)
        if ((deferred)); then
          [[ -n "$late" ]] || late="$ln"
        else
          ((state == 3)) || [[ -n "$bad" ]] || bad="$ln"
        fi
        ;;
      esac
      ;;
    F) [[ -n "$late" ]] || late="$ln" ;;
    R) ((state == 3)) || [[ -n "$bad" ]] || bad="$ln" ;;
    B) [[ -n "$bad" ]] || bad="$ln" ;;
    C) (($2 < 4)) && g_harness "$1" "$arg" $(($2 + 1)) && state=3 ;;
    *) ;;
    esac
  done
  ((fstate == 3)) || [[ -n "$bad" || -z "$late" ]] || bad="$late"
  G_STATE=$state G_BAD=$bad
}

g_resolve() {
  local tail="${2##*[\})]}" dir="" base seg
  local -a segs out
  [[ "$tail" =~ ^\$[A-Za-z_][A-Za-z0-9_]* ]] && tail="${tail:${#BASH_REMATCH[0]}}"
  tail="${tail#/}"
  [[ "$1" == */* ]] && dir="${1%/*}"
  local -a bases=()
  while [[ -n "$dir" ]]; do
    bases+=("$dir")
    [[ "$dir" == */* ]] && dir="${dir%/*}" || dir=""
  done
  G_RES=""
  for base in ${bases[@]+"${bases[@]}"} ""; do
    IFS=/ read -ra segs <<<"${base:+$base/}$tail"
    out=()
    for seg in "${segs[@]}"; do
      case "$seg" in
      "" | .) ;;
      ..) ((${#out[@]})) && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$seg") ;;
      esac
    done
    G_RES=""
    for seg in ${out[@]+"${out[@]}"}; do G_RES+="${G_RES:+/}$seg"; done
    [[ -n "${IS_TRACKED[$G_RES]:-}" ]] && return
  done
  G_RES=""
}

g_harness() {
  local f key files
  g_resolve "$1" "$2"
  f="$G_RES"
  if [[ -n "$f" ]]; then key="$f" files="$f"; else key="${2##*/}" files="${BYBASE[${2##*/}]:-}"; fi
  if [[ -z "${GHARNESS[$key]:-}" ]]; then
    GHARNESS["$key"]=0
    if [[ -n "$files" ]]; then
      GHARNESS["$key"]=1
      for f in $files; do
        g_eval "$f" "$3"
        ((G_STATE == 3)) && [[ -z "$G_BAD" || -n "${SCOPED[$f]:-}" ]] || {
          GHARNESS["$key"]=0
          break
        }
      done
    fi
  fi
  ((GHARNESS[$key] == 1))
}

sources_isolating_harness() {
  local b
  for b in ${SOURCES["$1"]:-}; do
    [[ -n "${ISOLATING_BASENAME[$b]:-}" ]] && return 0
  done
  return 1
}

declare -A BASELINED=()
BASELINE_ENTRIES=()
if [[ -f "$BASELINE" ]]; then
  read_list::into BASELINE_ENTRIES "$BASELINE" --comments inline || exit 2
  for line in ${BASELINE_ENTRIES[@]+"${BASELINE_ENTRIES[@]}"}; do
    BASELINED["$line"]=1
  done
fi

violations=()
covered=()

mapfile -t suites < <(git ls-files '*.test.sh' '*test_*.py' '*_test.py' 2>/dev/null | sort -u)
for t in "${suites[@]}"; do
  [[ -n "${IS_FIXTURE[$t]:-}" ]] || continue
  if [[ -n "${CLEARS_FILE[$t]:-}" ]] || sources_isolating_harness "$t"; then
    covered+=("$t")
    [[ "$mode" == "list" ]] && printf 'isolated    %s\n' "$t"
    continue
  fi
  if [[ -n "${SCOPED[$t]:-}" ]]; then
    covered+=("$t")
    [[ "$mode" == "list" ]] && printf 'declared    %s\n' "$t"
    continue
  fi
  read_list::mark_used "$t"
  if [[ -n "${BASELINED[$t]:-}" ]]; then
    [[ "$mode" == "list" ]] && printf 'baselined   %s\n' "$t"
    continue
  fi
  violations+=("$t")
  [[ "$mode" == "list" ]] && printf 'VIOLATION   %s\n' "$t"
done

stale=()
read_list::stale_to stale BASELINE_ENTRIES

declare -A GBASELINED=()
GBASELINE_ENTRIES=()
if [[ -f "$GBASELINE" ]]; then
  read_list::into GBASELINE_ENTRIES "$GBASELINE" --comments inline || exit 2
  for line in ${GBASELINE_ENTRIES[@]+"${GBASELINE_ENTRIES[@]}"}; do
    GBASELINED["$line"]=1
  done
fi
read_list::reset_used
gviolations=()
gchecked=0
for t in "${suites[@]}" ${js_suites[@]+"${js_suites[@]}"}; do
  [[ -n "${GEV[$t]:-}" && -z "${SCOPED[$t]:-}" ]] || continue
  g_eval "$t" 0
  [[ -z "$G_BAD" && " ${GEV[$t]}" == *" "[RFBD]:* ]] && gchecked=$((gchecked + 1))
  [[ -n "$G_BAD" ]] || continue
  read_list::mark_used "$t"
  if [[ -n "${GBASELINED[$t]:-}" ]]; then
    [[ "$mode" == "list" ]] && printf 'baselined   %s (global config)\n' "$t"
    continue
  fi
  gviolations+=("$t:$G_BAD")
  [[ "$mode" == "list" ]] && printf 'VIOLATION   %s:%s (global config)\n' "$t" "$G_BAD"
done
gstale=()
read_list::stale_to gstale GBASELINE_ENTRIES

if [[ "$mode" == "list" ]]; then
  printf '\n%d isolated, %d baselined, %d violating\n' \
    "${#covered[@]}" "$((${#BASELINED[@]} - ${#stale[@]}))" "${#violations[@]}"
  printf 'global config: %d baselined, %d violating\n' \
    "$((${#GBASELINED[@]} - ${#gstale[@]}))" "${#gviolations[@]}"
  exit 0
fi

rc=0

if ((${#gviolations[@]} > 0)); then
  rc=1
  {
    printf 'GIT GLOBAL CONFIG ISOLATION: %d suite(s) run git while reading the host global or system git config.\n\n' "${#gviolations[@]}"
    printf '  %s\n' "${gviolations[@]}"
    cat <<EOF

Each names the line of the first git command that runs with GIT_CONFIG_GLOBAL
not exported or GIT_CONFIG_NOSYSTEM=1 not set: never set, set only after that
line, unset again before it, or replaced by an env= dict that drops both. Such
a command reads the host's ~/.gitconfig and system config (signing, hooks,
url rewrites, identity), so the suite passes or fails by machine. The test
runners export both (scripts/lib/test-git-env.sh); a suite run directly does not.

Fix by exporting both before the first git command, at the top of the suite:

    export GIT_CONFIG_GLOBAL="\${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

(Python: os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull) and
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"; JS: process.env.GIT_CONFIG_GLOBAL ??=
"/dev/null" and process.env.GIT_CONFIG_NOSYSTEM = "1"), or by sourcing a
harness that does (scripts/test-git-helpers.sh), and keep both in any env dict.
A suite that must read the host config declares "# fixture-isolation-scope: <reason>".
Do not add a new suite to $GBASELINE.
EOF
  } >&2
fi

if ((${#gstale[@]} > 0)); then
  rc=1
  while IFS= read -r s; do
    read_list::stale_line "$GBASELINE" "$s" 'no longer shadows a violation'
  done < <(printf '%s\n' "${gstale[@]}" | sort)
fi

if ((${#violations[@]} > 0)); then
  rc=1
  {
    printf 'FIXTURE GIT ISOLATION: %d suite(s) build a git fixture without clearing the inherited git environment.\n\n' "${#violations[@]}"
    printf '  %s\n' "${violations[@]}"
    cat <<EOF

Each builds a repository or writes a git identity, so under an inherited ABSOLUTE
GIT_DIR — which overrides repository discovery and outranks -C — it writes that
identity into the CALLER's .git/config, shared by every worktree of the clone,
instead of into its fixture. Any process can export it; a git hook is one way and
an ad-hoc command is another, which is why this is cleared unconditionally.

Fix by clearing the environment once, at the top of the suite:

    unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

or by sourcing a harness that already does (scripts/test-git-helpers.sh).
Do not add a new suite to $BASELINE — it records pre-existing debt only.
EOF
  } >&2
fi

if ((${#stale[@]} > 0)); then
  rc=1
  printf '\n%d entry(ies) in %s no longer shadow a violation.\nDelete each line below — the debt it recorded is paid.\n\n' "${#stale[@]}" "$BASELINE" >&2
  while IFS= read -r s; do
    read_list::stale_line "$BASELINE" "$s" 'no longer shadows a violation'
  done < <(printf '%s\n' "${stale[@]}" | sort)
fi

if ((rc == 0)); then
  printf 'fixture git isolation: OK (%d isolated, %d baselined; %d git-running suites read no host config, %d baselined)\n' \
    "${#covered[@]}" "${#BASELINED[@]}" "$gchecked" "${#GBASELINED[@]}"
fi
exit "$rc"
