# shellcheck shell=bash disable=SC2154 # here, CHECKS_TMP and CHECKS_MODE come from the entry and check-lib.sh

secret_lib="$here/secret-patterns.sh"
[[ -f "$secret_lib" ]] || secret_lib="$here/../lib/secret-detection/secret-patterns.sh"
path_lib="$here/hardcoded-path-patterns.sh"
[[ -f "$path_lib" ]] || path_lib="$here/../lib/path-detection/hardcoded-path-patterns.sh"
# shellcheck source=../lib/secret-detection/secret-patterns.sh
. "$secret_lib" || return 1
# shellcheck source=../lib/path-detection/hardcoded-path-patterns.sh
. "$path_lib" || return 1

MAX_BYTES=1048576
scan_error=/dev/null
other_parents=()

scan_tool() {
  local tool=$1 rc
  shift
  command "$tool" "$@"
  rc=$?
  case "$tool:$rc" in
  *:0 | *:141 | grep:1) ;;
  *) printf 'guardrails: %s exited %s during the content scan\n' "$tool" "$rc" >>"$scan_error" ;;
  esac
  return "$rc"
}
awk() { scan_tool awk "$@"; }
grep() { scan_tool grep "$@"; }
sed() { scan_tool sed "$@"; }
sort() { scan_tool sort "$@"; }
cut() { scan_tool cut "$@"; }

EXEMPT_LIST=docs/conventions/guardrails-content-exempt.tsv
repo_exempt=()

path_exempt() {
  local e
  for e in ${repo_exempt[@]+"${repo_exempt[@]}"}; do
    case "$e" in
    */) [[ "$1" == "$e"* ]] && return 0 ;;
    *) [[ "$1" == "$e" ]] && return 0 ;;
    esac
  done
  builtin_exempt "$1"
}

builtin_exempt() {
  case "$1" in
  *.claude/hooks/* | *.lefthook/*) return 0 ;;
  *settings.local.json | *CLAUDE.local.md) return 0 ;;
  */.venv/* | .venv/* | */node_modules/* | node_modules/*) return 0 ;;
  *.env.example | *.env.sample | *.env.template) return 0 ;;
  *.claude/skills/*/context/* | *.claude/skills/*/completed/*) return 0 ;;
  */lib/secret-detection/* | */lib/path-detection/*) return 0 ;;
  .githooks/guardrails/secret-patterns.sh | .githooks/guardrails/hardcoded-path-patterns.sh | \
    .githooks/guardrails/machine-path-patterns.sh) return 0 ;;
  *) return 1 ;;
  esac
}

secret_exempt() {
  case "$1" in
  *tests/fixtures/* | *tests/testdata/* | *Tests/fixtures/* | *Tests/testdata/*) return 0 ;;
  *) builtin_exempt "$1" ;;
  esac
}

content_scan_init() {
  scan_error="$CHECKS_TMP/scan-error"
  local row
  repo_exempt=()
  while IFS= read -r row || [[ -n "$row" ]]; do
    row="${row%$'\r'}"
    row="${row%%$'\t'*}"
    [[ -n "$row" && "$row" != '#'* ]] && repo_exempt+=("$row")
  done < <(git show "refs/remotes/origin/HEAD:$EXEMPT_LIST" 2>/dev/null)
  scan_root="$PWD"
  local home="${HOME:-${USERPROFILE:-}}"
  home="${home%/}"
  if [[ -n "$home" ]] && [[ "$PWD/" == "$home"/* || "$home/" == "$PWD"/* ]]; then
    scan_root=""
  fi
}

src_has_nul() {
  local LC_ALL=C chunk
  IFS= read -r -d '' -n 8000 chunk <"$1" && ((${#chunk} < 8000))
}

ascii_text() {
  local LC_ALL=C non_ascii=$'[!\x01-\x7f]'
  [[ $1 != *$non_ascii* ]]
}

added_only() {
  awk -v want="$1" -v ranges="$CHECKS_TMP/ranges" '
    BEGIN { while ((getline l < ranges) > 0) { split(l, r, "\t"); if (r[1] == want) { n++; s[n] = r[2] + 0; e[n] = r[3] + 0 } } }
    { keep = 0; for (i = 1; i <= n; i++) if (NR >= s[i] && NR <= e[i]) { keep = 1; break } print (keep ? $0 : "") }'
}

scan_failed() {
  printf 'guardrails: %s: could not be scanned (is %s full?); free space there, then %s again.\n' \
    "$1" "$CHECKS_TMP" "$(checks_git_verb)" >&2
  exit 1
}

tab=$'\t'
untag() {
  sort -s -t "$tab" -k1,1n -k2,2n "$1" | cut -f3-
}

secret_findings() {
  sed -n 's/^\(.*\) (line \([0-9,]*\))$/\2 \1/p' |
    while read -r nums label; do
      for n in ${nums//,/ }; do
        printf '%s\t0\t%s:%s: secret or credential pattern: %s\n' "$2" "$1" "$n" "$label"
      done
    done
}

hpp_judge() {
  hpp::scan_text "${texts[$1]}" "$scan_root" "$PWD/${names[$1]}" |
    awk -v f="${names[$1]}" -v tag="${order[$1]}" '
      /^[^ \t].*:$/ && !/^[0-9]+:/ { label = substr($0, 1, length($0) - 1); next }
      match($0, /^[0-9]+:/) { printf "%s\t1\t%s:%s: machine-specific path (%s)\n", tag, f, substr($0, 1, RLENGTH - 1), label }' >>"${sinks[$1]}"
}

# Windows caps a command line at 32,767 characters; awk gets the matched line numbers in one argument.
# https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
JOIN_MAX=32768
hpp_sweep() {
  local from=$1 to=$2 i t joined="" mid
  if ((to - from == 1)); then
    hpp_judge "${pool[from]}"
    return
  fi
  for ((i = from; i < to && ${#joined} <= JOIN_MAX; i++)); do
    t="${texts[pool[i]]}"
    joined+="$t"
    [[ "${t: -1}" == $'\n' ]] || joined+=$'\n'
  done
  if ((${#joined} <= JOIN_MAX)); then
    hpp::scan_text "$joined" "$scan_root" >/dev/null && return
  fi
  mid=$(((from + to) / 2))
  hpp_sweep "$from" "$mid"
  hpp_sweep "$mid" "$to"
}

retyped_ranges() {
  local f p all="$CHECKS_TMP/retyped"
  : >"$all" || scan_failed .
  for f in "$@"; do
    [[ "$f" == *[\"\\[:cntrl:]]* ]] || printf '%s\t1\t2147483647\n' "$f" >>"$all" || scan_failed "$f"
  done
  for p in ${other_parents[@]+"${other_parents[@]}"}; do
    : >"$all.other"
    checks_added_ranges "$all.other" ACMRT "$p"
    checks_intersect_ranges "$all.other" "$all" >"$all.both" ||
      checks_tool_failed awk "$?" 'listing the lines the merge adds'
    mv "$all.both" "$all"
  done
  cat "$all" >>"$CHECKS_TMP/ranges" || scan_failed .
  cat "$all" >>"$CHECKS_TMP/path-ranges" || scan_failed .
}

content_scan() {
  local result=$1 i f s src sink text packed meta rest p
  paths=()
  keeps=()
  rm -rf "$CHECKS_TMP/scan"
  mkdir "$CHECKS_TMP/scan" || scan_failed .
  if [[ "$CHECKS_MODE" == worktree ]]; then
    while IFS= read -r -d '' f; do
      [[ -f "$f" && ! -L "$f" ]] || continue
      (($(wc -c <"$f" | tr -d ' ') <= MAX_BYTES)) || continue
      paths+=("$f")
    done < <(checks_files)
  else
    local -a staged=() blobs=() sizes=() retyped=()
    while IFS= read -r -d '' meta && IFS= read -r -d '' f; do
      case "${meta##* }" in
      R* | C*) IFS= read -r -d '' f || break ;;
      *) ;;
      esac
      rest="${meta#* }"
      case "${rest%% *}" in
      100644 | 100755) ;;
      *) continue ;;
      esac
      [[ "${meta##* }" == T ]] && retyped+=("$f")
      rest="${rest#* }"
      rest="${rest#* }"
      staged+=("$f")
      blobs+=("${rest%% *}")
    done < <(checks_diff --raw --no-abbrev -z --diff-filter=ACMRT)
    if [[ "$CHECKS_MODE" == pre-commit ]] && ((${#retyped[@]})); then
      retyped_ranges "${retyped[@]}"
    fi
    for p in ${other_parents[@]+"${other_parents[@]}"}; do
      drop_unchanged "$p"
    done
    if ((${#blobs[@]})); then
      while read -r s; do
        sizes+=("$s")
      done < <(printf '%s\n' "${blobs[@]}" | git cat-file --batch-check='%(objectsize)' 2>/dev/null)
    fi
    for ((i = 0; i < ${#staged[@]}; i++)); do
      s="${sizes[i]:-0}"
      [[ "$s" =~ ^[0-9]+$ ]] || s=0
      ((s <= MAX_BYTES)) || continue
      paths+=("${staged[i]}")
      keeps+=("${blobs[i]}")
    done
  fi

  local out="$CHECKS_TMP/findings" whole="$CHECKS_TMP/findings-whole" scanned=0
  : >"$out"
  : >"$whole"
  names=()
  texts=()
  sinks=()
  order=()
  for ((i = 0; i < ${#paths[@]}; i++)); do
    f="${paths[i]}"
    src="$f"
    if [[ "$CHECKS_MODE" != worktree ]]; then
      src="$CHECKS_TMP/blob"
      git cat-file blob "${keeps[i]}" >"$src" 2>/dev/null || scan_failed "$f"
    fi
    if src_has_nul "$src"; then
      secret_exempt "$f" && continue
      text="$(tr '\0' ' ' <"$src"; printf x)"
      packed="$(tr -d '\0' <"$src"; printf x)"
      {
        secrets::scan_text "${text%x}"
        echo --
        secrets::scan_text "${packed%x}"
      } | awk '$0 == "--" { p2 = 1; next }
        { l = $0; sub(/ \(line [0-9,]*\)$/, "", l) }
        p2 && (l in seen) { next }
        !p2 { seen[l] } { print }' | secret_findings "$f" "$i" >>"$whole"
      continue
    fi
    sink="$out"
    if [[ "$f" == *[\"\\[:cntrl:]]* ]]; then
      text="$(cat -- "$src"; printf x)"
      sink="$whole"
    else
      text="$(added_only "$f" <"$src"; printf x)"
    fi
    text="${text%x}"
    [[ "$text" == *[![:space:]]* ]] || continue
    names[scanned]="$f"
    texts[scanned]="$text"
    sinks[scanned]="$sink"
    order[scanned]="$i"
    printf '%s' "$text" >"$CHECKS_TMP/scan/$scanned" || scan_failed "$f"
    scanned=$((scanned + 1))
  done

  local -a secret_args=()
  for p in "${SECRET_PATTERNS[@]}"; do
    secret_args+=(-e "$p")
  done
  hits=()
  if ((scanned)); then
    : >"$CHECKS_TMP/secret-hits" || scan_failed .
    LC_ALL=C command grep -rlE "${secret_args[@]}" -- "$CHECKS_TMP/scan" >"$CHECKS_TMP/secret-hits" 2>/dev/null
    if (($? > 1)); then
      for ((i = 0; i < scanned; i++)); do
        hits[i]=1
      done
    else
      while IFS= read -r p; do
        p="${p##*/}"
        [[ "$p" =~ ^[0-9]+$ ]] && hits[p]=1
      done <"$CHECKS_TMP/secret-hits"
    fi
  fi
  for ((i = 0; i < scanned; i++)); do
    [[ -n "${hits[i]:-}" ]] || continue
    secret_exempt "${names[i]}" && continue
    secrets::scan_text "${texts[i]}" | secret_findings "${names[i]}" "${order[i]}" >>"${sinks[i]}"
  done

  pool=()
  for ((i = 0; i < scanned; i++)); do
    path_exempt "${names[i]}" && continue
    hpp::prefilter "${texts[i]}" "$scan_root"
    [[ $HPP_GATE == clean ]] && continue
    if ascii_text "${texts[i]}"; then
      pool+=("$i")
    else
      hpp_judge "$i"
    fi
  done
  ((${#pool[@]} == 0)) || hpp_sweep 0 "${#pool[@]}"

  {
    awk -F "$tab" '$2 != 1' "$out" | untag - | checks_filter_findings
    awk -F "$tab" '$2 == 1' "$out" | untag - | checks_filter_findings "$CHECKS_TMP/path-ranges"
    untag "$whole"
  } | sort -u -t: -k1,1 -k2,2n >"$result"
}

parent_diff() {
  local p=$1 tip
  shift
  if [[ "$CHECKS_MODE" == pre-push ]]; then
    read -r _ tip <"$CHECKS_TMP/push-ranges"
    git -c core.quotePath=false diff --no-ext-diff "$p" "$tip" "$@"
  else
    git -c core.quotePath=false diff --no-ext-diff --cached "$p" "$@"
  fi
}

drop_unchanged() {
  local LC_ALL=C f differ=$'\n' i
  local -a kept=() kept_blobs=()
  ((${#staged[@]})) || return 0
  parent_diff "$1" --raw --no-abbrev --no-renames -z -- >"$CHECKS_TMP/parent-diff" 2>/dev/null || return 0
  while IFS= read -r -d '' _ && IFS= read -r -d '' f; do
    differ+="$f"$'\n'
  done <"$CHECKS_TMP/parent-diff" || return 0
  for ((i = 0; i < ${#staged[@]}; i++)); do
    f="${staged[i]}"
    if [[ "$f" == *$'\n'* ]]; then
      GIT_LITERAL_PATHSPECS=1 parent_diff "$1" --quiet --no-renames -- "$f" 2>/dev/null && continue
    else
      [[ "$differ" == *$'\n'"$f"$'\n'* ]] || continue
    fi
    kept+=("$f")
    kept_blobs+=("${blobs[i]}")
  done
  staged=(${kept[@]+"${kept[@]}"})
  blobs=(${kept_blobs[@]+"${kept_blobs[@]}"})
}

content_report() {
  local verb
  verb="$(checks_git_verb)"
  if [[ -e "$scan_error" ]]; then
    cat "$1" "$scan_error" >&2
    printf 'guardrails: the content scan did not finish, so this change was not fully scanned; fix the tool failure named above, then %s again.\n' "$verb" >&2
    exit 1
  fi
  [[ -s "$1" ]] || exit 0
  cat "$1" >&2
  printf 'guardrails: remove the secrets or machine-specific paths above from %s, then %s again.\n' "$2" "$verb" >&2
  exit 1
}
