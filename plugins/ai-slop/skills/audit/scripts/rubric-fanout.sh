#!/usr/bin/env bash
# Deterministic steps of the rubric fan-out (context/rubric-fanout.md).
#
#   plan     order a `detect.sh --list-targets` file, pack it into batches by
#            `wc -w`, write batch-NN.txt lists and batch-NN.paths sidecars,
#            print each batch's digest (list plus listed files' contents)
#   extract  the catalog's `v1: rubric` entries plus "Signs of human writing"
#   status   per batch: complete, or missing or stale (with the failed check)
#            plus the batch's current digest
#   merge    one merged rubric file, written only when every batch is complete
#
# Exit: 0 ok; 1 when status or merge finds a batch that is not complete;
# 2 on usage errors and refusals.
set -u
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/opt-value.sh
source "$SCRIPT_DIR/lib/opt-value.sh"
CATALOG="$SCRIPT_DIR/../reference/catalog.md"
ME="rubric-fanout.sh"

usage() {
  cat <<'EOF'
rubric-fanout.sh: deterministic steps of the /ai-slop:audit rubric fan-out.

Usage:
  rubric-fanout.sh plan --out <dir> [--budget N] [--order auto|repo|mtime] <targets-file>
  rubric-fanout.sh extract [--out <file>]
  rubric-fanout.sh status --batches <dir> --results <dir>
  rubric-fanout.sh merge --batches <dir> --results <dir> --out <file>

<targets-file> is `detect.sh --list-targets` output: <key><TAB><path> per line.
Order repo: impact class (CLAUDE.md, AGENTS.md, SKILL.md, README.md, .claude/rules/),
then 90-day change count, then key. Order mtime: newest first, then key.
Exit: 0 ok, 1 a batch is not complete, 2 usage error or refusal.
EOF
}

die() {
  echo "$ME: $*" >&2
  exit 2
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

# read_sidecar <sidecar>: SIDECAR holds its non-empty lines, a trailing CR
# stripped from each.
read_sidecar() {
  local p
  SIDECAR=()
  while IFS= read -r p || [[ -n "$p" ]]; do
    p="${p%$'\r'}"
    [[ -n "$p" ]] && SIDECAR+=("$p")
  done <"$1"
}

# batch_digest <list>: with a batch-NN.paths sidecar, the sha256 of the list's
# bytes, a fixed separator line, then one sha256 call's output over every
# listed path, so the digest binds the files' contents too. The separator keeps
# an all-unreadable batch from matching the list-only digest; status reports a
# batch with an unreadable path as stale before its digest is compared.
# Without the sidecar, the list's sha256.
# The list is hashed from stdin: given a file name holding a backslash,
# sha256sum escapes the name and prefixes the hash with `\`.
batch_digest() {
  local sidecar="${1%.txt}.paths"
  {
    cat -- "$1"
    if [[ -f "$sidecar" ]]; then
      printf '%s\n' "--- rubric-fanout batch contents ---"
      read_sidecar "$sidecar"
      [[ "${#SIDECAR[@]}" -gt 0 ]] && sha256 -- "${SIDECAR[@]}" 2>/dev/null
    fi
  } | sha256 | cut -d' ' -f1
}

mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

is_impact() {
  case "/$1" in
  */CLAUDE.md | */AGENTS.md | */SKILL.md | */README.md | */.claude/rules/*) return 0 ;;
  *) return 1 ;;
  esac
}

cmd_plan() {
  local out="" budget=50000 order=auto targets=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --out) require_opt_value "$ME" "$@"; out="$2"; shift 2 ;;
    --budget) require_opt_value "$ME" "$@"; budget="$2"; shift 2 ;;
    --order) require_opt_value "$ME" "$@"; order="$2"; shift 2 ;;
    -*) die "plan: unknown option: $1" ;;
    *) targets="$1"; shift ;;
    esac
  done
  [[ -n "$out" && -n "$targets" ]] || die "plan needs --out <dir> and a targets file"
  [[ "$budget" =~ ^[1-9][0-9]*$ ]] || die "plan: --budget must be a positive integer"
  [[ -r "$targets" ]] || die "plan: cannot read targets file: $targets"
  mkdir -p "$out" || die "plan: cannot create $out"
  if compgen -G "$out/batch-*.txt" >/dev/null; then
    die "plan: $out already holds batch lists; plan into a fresh directory, or run status to resume"
  fi

  local -a keys=() paths=()
  local key path
  while IFS=$'\t' read -r key path; do
    key="${key%$'\r'}"
    path="${path%$'\r'}"
    [[ -n "$key" ]] || continue
    keys+=("$key")
    paths+=("${path:-$key}")
  done <"$targets"
  if [[ "${#keys[@]}" -eq 0 ]]; then
    echo "$ME: plan: targets file lists no files; no batches written" >&2
    return 0
  fi

  local top
  top="$(git -C "$(dirname "${paths[0]}")" rev-parse --show-toplevel 2>/dev/null)"
  if [[ "$order" == auto ]]; then
    order=mtime
    [[ -n "$top" ]] && order=repo
  fi

  local i ordered
  case "$order" in
  repo)
    local -A changes=()
    if [[ -n "$top" ]]; then
      local n k
      while IFS=$'\t' read -r n k; do
        changes[$k]="$n"
      done < <(git -C "$top" -c core.quotePath=false log --since=90.days --name-only --format= 2>/dev/null |
        awk 'NF { c[$0]++ } END { for (k in c) printf "%d\t%s\n", c[k], k }')
    fi
    # Keys are relative to the project directory, which may sit below the
    # toplevel, so each file's repository path is its directory's
    # `--show-prefix` plus its name. One git call per directory, not per file.
    local -A prefix=()
    local d rel
    ordered="$(for i in "${!keys[@]}"; do
      d="$(dirname "${paths[$i]}")"
      [[ -n "${prefix[$d]+set}" ]] || prefix[$d]="$(git -C "$d" rev-parse --show-prefix 2>/dev/null)"
      rel="${prefix[$d]}${paths[$i]##*/}"
      c=1
      is_impact "${keys[$i]}" && c=0
      printf '%d\t%d\t%s\t%d\n' "$c" "${changes[$rel]:-0}" "${keys[$i]}" "$i"
    done | sort -t$'\t' -k1,1n -k2,2nr -k3,3 | cut -f4)"
    ;;
  mtime)
    ordered="$(for i in "${!keys[@]}"; do
      printf '%d\t%s\t%d\n' "$(mtime "${paths[$i]}")" "${keys[$i]}" "$i"
    done | sort -t$'\t' -k1,1nr -k2,2 | cut -f3)"
    ;;
  *) die "plan: --order must be auto, repo, or mtime" ;;
  esac

  # Pack: add files until the next one would exceed the budget. A file larger
  # than the budget lands alone, because the batch before it is flushed first.
  # Each file's absolute path goes to the batch's .paths sidecar. An absolute
  # path (POSIX or Windows form) is kept as given; a relative one resolves
  # against the cwd, one cd per directory, or is kept as given when its
  # directory cannot be entered.
  local -a lists=() plists=() words=() counts=()
  local -A absdir=()
  local cur="" cur_p="" cur_w=0 cur_n=0 w dir ap
  for i in $ordered; do
    w="$(wc -w <"${paths[$i]}" 2>/dev/null | tr -d ' ')"
    [[ -n "$w" ]] || { echo "$ME: plan: cannot read ${paths[$i]}; counted as 0 words" >&2; w=0; }
    if [[ "$cur_n" -gt 0 && $((cur_w + w)) -gt "$budget" ]]; then
      lists+=("$cur"); plists+=("$cur_p"); words+=("$cur_w"); counts+=("$cur_n")
      cur="" cur_p="" cur_w=0 cur_n=0
    fi
    ap="${paths[$i]}"
    case "$ap" in
    /* | [A-Za-z]:[/\\]*) ;;
    *)
      dir="$(dirname "$ap")"
      [[ -n "${absdir[$dir]+set}" ]] ||
        absdir[$dir]="$(CDPATH='' cd -P -- "$dir" >/dev/null 2>&1 && pwd)"
      [[ -n "${absdir[$dir]}" ]] && ap="${absdir[$dir]}/${ap##*/}"
      ;;
    esac
    [[ -f "$ap" && -r "$ap" ]] || echo "$ME: plan: sidecar path unreadable: $ap" >&2
    cur_p+="$ap"$'\n'
    cur+="${keys[$i]}"$'\n'
    cur_w=$((cur_w + w))
    cur_n=$((cur_n + 1))
  done
  lists+=("$cur"); plists+=("$cur_p"); words+=("$cur_w"); counts+=("$cur_n")

  local width=${#lists[@]} b nn list
  width=${#width}
  [[ "$width" -lt 2 ]] && width=2
  for b in "${!lists[@]}"; do
    nn="$(printf '%0*d' "$width" $((b + 1)))"
    list="$out/batch-$nn.txt"
    printf '%s' "${lists[$b]}" >"$list" || die "plan: cannot write $list"
    printf '%s' "${plists[$b]}" >"$out/batch-$nn.paths" || die "plan: cannot write $out/batch-$nn.paths"
    printf 'batch=%s list=%s files=%d words=%d digest=%s\n' \
      "$nn" "$list" "${counts[$b]}" "${words[$b]}" "$(batch_digest "$list")"
  done
}

cmd_extract() {
  local out=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --out) require_opt_value "$ME" "$@"; out="$2"; shift 2 ;;
    *) die "extract: unknown argument: $1" ;;
    esac
  done
  [[ -r "$CATALOG" ]] || die "extract: cannot read catalog: $CATALOG"
  # A `### rule-` section runs to the next heading and is kept only when its
  # body carries `- v1: rubric`. The human-writing section is kept whole.
  # shellcheck disable=SC2016  # an awk program, not a shell expansion
  local prog='
    function flush() { if (rubric) printf "%s", buf; buf = ""; rubric = 0; inrule = 0 }
    { sub(/\r$/, "") }
    /^## / { flush(); human = ($0 ~ /^## Signs of human writing[[:space:]]*$/) }
    /^### / { flush(); if (!human && $0 ~ /^### rule-/) inrule = 1 }
    human { print; next }
    inrule { buf = buf $0 "\n"; if ($0 ~ /^- v1: rubric[[:space:]]*$/) rubric = 1 }
    END { flush() }'
  if [[ -n "$out" ]]; then
    awk "$prog" "$CATALOG" >"$out" || die "extract: cannot write $out"
  else
    awk "$prog" "$CATALOG"
  fi
}

# header <result> <name>: the header's value when it appears exactly once;
# fails otherwise, since merge sums every copy and a joined value can match.
header() {
  [[ "$(tr -d '\r' <"$1" | grep -c "^$2:")" == 1 ]] || return 1
  tr -d '\r' <"$1" | sed -n "s/^$2:[[:space:]]*//p" | tr -d '[:space:]'
}

# status_rows <batches> <results>: one `batch=NN status=...` row per list. A
# missing or stale row ends with the batch's current digest; a complete row
# ends with `status=complete`.
status_rows() {
  local batches="$1" results="$2" list nn res d n got p bad
  for list in "$batches"/batch-*.txt; do
    [[ -f "$list" ]] || continue
    nn="${list##*/batch-}"
    nn="${nn%.txt}"
    res="$results/rubric-batch-$nn.md"
    d="$(batch_digest "$list")"
    if [[ ! -f "$res" ]]; then
      echo "batch=$nn status=missing digest=$d"
      continue
    fi
    n="$(awk 'NF' "$list" | wc -l | tr -d ' ')"
    # A sidecar that does not name one readable file per list entry cannot
    # bind the contents, so the batch is stale until it is planned again.
    if [[ -f "${list%.txt}.paths" ]]; then
      read_sidecar "${list%.txt}.paths"
      bad=0
      [[ "${#SIDECAR[@]}" == "$n" ]] || bad=1
      for p in ${SIDECAR[@]+"${SIDECAR[@]}"}; do
        [[ -f "$p" && -r "$p" ]] || bad=1
      done
      if [[ "$bad" == 1 ]]; then
        echo "batch=$nn status=stale reason=paths digest=$d"
        continue
      fi
    fi
    if ! got="$(header "$res" batch)" || [[ "$got" != "$d" ]]; then
      echo "batch=$nn status=stale reason=digest digest=$d"
      continue
    fi
    if ! got="$(header "$res" files_reviewed)" || [[ "$got" != "$n" ]]; then
      echo "batch=$nn status=stale reason=files_reviewed digest=$d"
      continue
    fi
    if tr -d '\r' <"$res" | awk 'NR == FNR { if (NF) k[$0] = 1; next }
         /^## / && !(substr($0, 4) in k) { bad = 1 } END { exit !bad }' "$list" -; then
      echo "batch=$nn status=stale reason=foreign-heading digest=$d"
      continue
    fi
    if ! got="$(header "$res" files_with_findings)" ||
      [[ "$got" != "$(tr -d '\r' <"$res" | grep -c '^## ')" ]]; then
      echo "batch=$nn status=stale reason=files_with_findings digest=$d"
      continue
    fi
    echo "batch=$nn status=complete"
  done
}

parse_dirs() {
  BATCHES="" RESULTS="" OUT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --batches) require_opt_value "$ME" "$@"; BATCHES="$2"; shift 2 ;;
    --results) require_opt_value "$ME" "$@"; RESULTS="$2"; shift 2 ;;
    --out) require_opt_value "$ME" "$@"; OUT="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
    esac
  done
  [[ -n "$BATCHES" && -n "$RESULTS" ]] || die "--batches <dir> and --results <dir> are required"
  compgen -G "$BATCHES/batch-*.txt" >/dev/null || die "no batch-*.txt lists in $BATCHES"
}

cmd_status() {
  parse_dirs "$@"
  local rows
  rows="$(status_rows "$BATCHES" "$RESULTS")"
  printf '%s\n' "$rows"
  ! grep -qv 'status=complete$' <<<"$rows"
}

cmd_merge() {
  parse_dirs "$@"
  [[ -n "$OUT" ]] || die "merge needs --out <file>"
  local rows
  rows="$(status_rows "$BATCHES" "$RESULTS")"
  if grep -qv 'status=complete$' <<<"$rows"; then
    echo "$ME: merge refused: not every batch is complete" >&2
    printf '%s\n' "$rows"
    return 1
  fi
  local -a files=()
  local nn
  while IFS= read -r nn; do
    nn="${nn#batch=}"
    files+=("$RESULTS/rubric-batch-${nn%% *}.md")
  done <<<"$rows"
  local f
  {
    awk '
      { sub(/\r$/, "") }
      /^files_reviewed:/ { fr += $2 }
      /^files_with_findings:/ { fw += $2 }
      END { printf "files_reviewed: %d\nfiles_with_findings: %d\nbatches: %d\n", fr, fw, ARGC - 1 }' "${files[@]}"
    awk '
      /^- L[0-9]+ rule-[a-z0-9-]+:/ { r = $3; sub(/:$/, "", r); t[r]++ }
      END { for (r in t) printf "rule_total: %s=%d\n", r, t[r] }' "${files[@]}" | sort
    for f in "${files[@]}"; do
      echo
      tr -d '\r' <"$f" | grep -Ev '^(batch|files_reviewed|files_with_findings):' || true
    done
  } >"$OUT" || die "merge: cannot write $OUT"
  echo "$ME: merged ${#files[@]} batch result(s) into $OUT"
}

case "${1:-}" in
plan | extract | status | merge)
  cmd="$1"
  shift
  "cmd_$cmd" "$@"
  ;;
--help | -h)
  usage
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
