#!/usr/bin/env bash
# Deterministic steps of the rubric fan-out (context/rubric-fanout.md).
#
#   plan     order a `detect.sh --list-targets` file, pack it into batches by
#            `wc -w`, write batch-NN.txt lists and batch-NN.paths sidecars,
#            print each batch's digest (list plus listed files' contents),
#            and write cues.txt: whole-scope and per-batch counts of the
#            saturation cues (load-bearing, seam) with a saturated verdict
#   extract  the catalog's `v1: rubric` entries plus "Signs of human writing"
#   status   per batch: complete, or missing or stale (with the failed check)
#            plus the batch's current digest
#   merge    one merged rubric file, written only when every batch is complete;
#            totals `declined:` result lines, and with cues.txt flags batches
#            whose cue verdicts disagree on `consistency:` lines
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

plan also writes <dir>/cues.txt:
  scope_digest=<sha>                                sha256 over the printed batch
                                                    digests, one per line
  scope_files=<S>                                   readable regular listed files
  cue=<c> occurrences=<O> files=<F> saturated=yes|no  whole scope; yes when
                                                    F >= 10 and F*10 >= S
  batch=<NN> cue=<c> occurrences=<O> files=<F>      per batch, when O > 0
Cues: load-bearing (load-bearing, load bearing) and seam (seam, seams), any
case, bounded by [^a-z0-9_] or the line edge, so non-load-bearing counts and
seamless does not; every match on a line counts, and a cue split across a line
break is not counted. Skipped, as the rubric skips them: a UTF-8 BOM; YAML
frontmatter (a --- first line through the next --- or ... line, when one
exists; with none, the first --- is a thematic break and the file is counted);
fenced code (any indent, the opener possibly after list-item or blockquote
markers, a backtick opener's info string holding no backtick, closed by a run
of the opener's character at least as long or by the end of its list item or
blockquote); indented code (4 columns, after a blank line, outside a list);
blockquote lines; HTML comments, which may span lines (one opened mid-line
and never closed ends with its paragraph); the (url) part of a
[text](url) link; code spans (a run of N backticks through the next run of
exactly N, on one line); and double-quoted spans, straight or curly, which may
wrap onto later lines of the same paragraph.

A result may carry `declined: <rule-id> <cue> reason=saturated|boundary|cap`
lines (cap: dropped by the per-file or per-batch finding cap). The cue token
(load bearing, with its space, is accepted too) is keyed to its cue name:
lowercased, load bearing and load_bearing read as load-bearing, and a
trailing s dropped when that leaves a cue name (seams is seam). merge strips
those lines from the bodies, totals them on `declined_total:` lines, and leaves
any other `declined:` line in the body. A finding's quote may wrap onto
indented continuation lines, up to a blank line, heading or the next line at
the left margin. When cues.txt exists it prints
`consistency:` lines for a saturated cue quoted in a
rule-abstract-metaphor-jargon finding, a reason=saturated decline of a cue that
is not saturated (or not a cue at all), and a batch holding a cue it neither
reported nor declined; each rule named there gets ` consistency=flagged` on its
rule_total. When the batch digests no longer match cues.txt's scope_digest (a
listed file changed after plan), or cues.txt has no scope_digest line, merge
prints `consistency: cues.txt stale reason=digest` instead of those checks;
plan again to restore them.
Exit: 0 ok, 1 a batch is not complete, 2 usage error or refusal.
EOF
}

# A well-formed decline line; merge strips and totals only these.
DECLINED_RE='^declined: rule-[a-z0-9-]+ [^ ]+( [Bb][Ee][Aa][Rr][Ii][Nn][Gg])? reason=(saturated|boundary|cap) *$'

# The saturation cues and cue_hits(s, c): the matches of cue c in s, compared
# lowercase and bounded by [^a-z0-9_] or the string's edge. POSIX awk only.
# shellcheck disable=SC2016  # an awk program, not a shell expansion
CUE_AWK='
function cue_hits(s, c,   re, n, off, st, pre, post) {
  s = tolower(s); n = 0; off = 0
  re = (c == "seam") ? "seams?" : "load[- ]bearing"
  while (match(substr(s, off + 1), re)) {
    st = off + RSTART
    pre = (st > 1) ? substr(s, st - 1, 1) : ""
    post = substr(s, st + RLENGTH, 1)
    if (pre !~ /[a-z0-9_]/ && post !~ /[a-z0-9_]/) { n++; off = st + RLENGTH - 1 } else off = st
  }
  return n
}
# unspan(s): s with code spans blanked out. As in CommonMark, a run of N
# backticks opens a span that closes at the next run of exactly N; a run with
# no such closer is literal text.
function unspan(s,   out, n, st, t, k) {
  out = ""
  while (match(s, /`+/)) {
    st = RSTART; n = RLENGTH; out = out substr(s, 1, st - 1)
    t = substr(s, st + n); k = 0
    while (match(substr(t, k + 1), /`+/)) {
      if (RLENGTH == n) break
      k += RSTART + RLENGTH - 1
    }
    if (RSTART && RLENGTH == n) { out = out " "; s = substr(t, k + RSTART + n) }
    else { out = out substr(s, st, n); s = t }
  }
  return out s
}
# prose(s): s with code spans, HTML comments, link URLs and "double-quoted"
# spans (curly quotes too) blanked out. A comment left open sets hcopen and a
# quote left open at the line end sets qopen; the caller resumes both on the
# next line and clears qopen at a paragraph boundary. As in detect.sh, a lone
# quote opens a span only after a space or opening bracket and before a
# non-space, so an inch mark (6") is dropped instead.
function prose(s,   q, pre, post) {
  s = unspan(s)
  while ((q = index(s, "<!--"))) {
    if ((pre = index(substr(s, q + 4), "-->"))) s = substr(s, 1, q - 1) " " substr(s, q + pre + 6)
    else { hcblock = (q < 5 && substr(s, 1, q - 1) !~ /[^ ]/); s = substr(s, 1, q - 1); hcopen = 1 }
  }
  gsub(/\]\([^)]*\)/, "]", s)
  while ((q = index(s, LQ))) s = substr(s, 1, q - 1) "\"" substr(s, q + 3)
  while ((q = index(s, RQ))) s = substr(s, 1, q - 1) "\"" substr(s, q + 3)
  if (qopen) {
    if (!(q = index(s, "\""))) return ""
    s = substr(s, q + 1); qopen = 0
  }
  gsub(/"[^"]*"/, " ", s)
  if ((q = index(s, "\""))) {
    pre = (q > 1) ? substr(s, q - 1, 1) : " "; post = substr(s, q + 1, 1)
    if (pre ~ /[ \t([{]/ && post ~ /[^ \t]/) { s = substr(s, 1, q - 1); qopen = 1 }
    else s = substr(s, 1, q - 1) " " substr(s, q + 1)
  }
  return s
}
# lead(s, bq, lists): the length of s up to its content: whitespace, then `>`
# markers when bq, then list-item markers (-, *, +, 1. or 1) and a space) when
# lists, in any order and nesting.
function lead(s, bq, lists,   p, r) {
  p = 0
  for (;;) {
    r = substr(s, p + 1)
    if (match(r, /^[ \t]+/) || (bq && match(r, /^>/)) ||
      (lists && match(r, /^([-*+]|[0-9]+[.)])[ \t]/))) p += RLENGTH
    else return p
  }
}
# cue_key(w): a declined cue keyed to its cue name: lowercase, load bearing
# (or load_bearing) as load-bearing, and a trailing s dropped when that leaves a
# cue name.
function cue_key(w,   i) {
  w = tolower(w); sub(/^load[ _]bearing$/, "load-bearing", w)
  if (w ~ /s$/) for (i = 1; i <= nc; i++) if (substr(w, 1, length(w) - 1) == C[i]) return C[i]
  return w
}
BEGIN { nc = split("load-bearing seam", C, " "); LQ = "\342\200\234"; RQ = "\342\200\235" }'

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
# listed path that is a readable regular file, so the digest binds the files'
# contents too. The separator keeps an all-unreadable batch from matching the
# list-only digest; status reports a batch with an unreadable path as stale
# before its digest is compared. A FIFO or other non-regular path is never
# opened. Without a readable regular sidecar, the list's sha256.
# The list is hashed from stdin: given a file name holding a backslash,
# sha256sum escapes the name and prefixes the hash with `\`.
batch_digest() {
  local sidecar="${1%.txt}.paths" p
  local -a files=()
  {
    cat -- "$1"
    if [[ -f "$sidecar" && -r "$sidecar" ]]; then
      printf '%s\n' "--- rubric-fanout batch contents ---"
      read_sidecar "$sidecar"
      for p in ${SIDECAR[@]+"${SIDECAR[@]}"}; do
        [[ -f "$p" && -r "$p" ]] && files+=("$p")
      done
      [[ "${#files[@]}" -gt 0 ]] && sha256 -- "${files[@]}" 2>/dev/null
    fi
  } | sha256 | cut -d' ' -f1
}

# sidecar_bad <list> <n>: succeeds when the list's sidecar exists but cannot
# bind the contents: it is not a readable regular file, its length differs
# from the list's n entries, or a path it names is not a readable regular
# file. No sidecar at all is not bad.
sidecar_bad() {
  local sidecar="${1%.txt}.paths" p
  [[ -e "$sidecar" || -L "$sidecar" ]] || return 1
  [[ -f "$sidecar" && -r "$sidecar" ]] || return 0
  read_sidecar "$sidecar"
  [[ "${#SIDECAR[@]}" == "$2" ]] || return 0
  for p in ${SIDECAR[@]+"${SIDECAR[@]}"}; do
    [[ -f "$p" && -r "$p" ]] || return 0
  done
  return 1
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
  [[ -f "$targets" && -r "$targets" ]] || die "plan: cannot read targets file: $targets"
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
    w=""
    [[ -f "${paths[$i]}" && -r "${paths[$i]}" ]] && w="$(wc -w <"${paths[$i]}" 2>/dev/null | tr -d ' ')"
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

  local width=${#lists[@]} b nn list scope="" digest digests=""
  width=${#width}
  [[ "$width" -lt 2 ]] && width=2
  for b in "${!lists[@]}"; do
    nn="$(printf '%0*d' "$width" $((b + 1)))"
    list="$out/batch-$nn.txt"
    printf '%s' "${lists[$b]}" >"$list" || die "plan: cannot write $list"
    printf '%s' "${plists[$b]}" >"$out/batch-$nn.paths" || die "plan: cannot write $out/batch-$nn.paths"
    digest="$(batch_digest "$list")"
    digests+="$digest"$'\n'
    printf 'batch=%s list=%s files=%d words=%d digest=%s\n' \
      "$nn" "$list" "${counts[$b]}" "${words[$b]}" "$digest"
    while IFS= read -r ap; do
      [[ -n "$ap" && -f "$ap" && -r "$ap" ]] && scope+="$nn"$'\t'"$ap"$'\n'
    done <<<"${plists[$b]}"
  done

  # Cue counts over the whole scope, one `<NN><TAB><path>` line per readable
  # regular file on stdin; awk opens each with getline, so no path is parsed
  # as an argument and a FIFO never reaches it. scope_digest binds these counts
  # to the batch digests just printed, so merge can tell when they went stale.
  # shellcheck disable=SC2016  # an awk program, not a shell expansion
  printf '%s' "$scope" | RF_SCOPE="$(printf '%s' "$digests" | sha256 | cut -d' ' -f1)" awk "$CUE_AWK"'
    {
      t = index($0, "\t"); b = substr($0, 1, t - 1); f = substr($0, t + 1)
      if (!(b in seen)) { seen[b] = 1; order[++nb] = b }
      S++; fence = ""; fm = 0; ln = 0; qopen = 0; hcopen = 0; pblank = 1; icode = 0; inlist = 0
      for (i = 1; i <= nc; i++) h[i] = 0
      while ((getline line < f) > 0) {
        sub(/\r$/, "", line); ln++
        if (ln == 1) {
          if (substr(line, 1, 3) == "\357\273\277") line = substr(line, 4)
          if (line ~ /^---[ \t]*$/) {
            # Frontmatter only when a closing --- or ... follows; otherwise
            # the --- is a thematic break. Scan ahead, then reopen past line 1.
            while ((getline t < f) > 0) if (t ~ /^(---|\.\.\.)[ \t]*\r?$/) { fm = 1; break }
            close(f); getline t < f
            continue
          }
        }
        if (fm) { if (line ~ /^(---|\.\.\.)[ \t]*$/) fm = 0; continue }
        if (fence != "") {
          # The container ends the fence: a blockquote fence at a line with no
          # `>`, a list-item fence at a non-blank line indented less than the
          # item content. That line is then read on its own.
          match(line, /^[ \t]*/)
          if (fbq ? line !~ /^[ \t]*>/ : (fcol && line ~ /[^ \t]/ && RLENGTH < fcol)) fence = ""
          else {
            # A closer, at any indent, is a run of the opener character alone,
            # at least as long.
            run = substr(line, lead(line, fbq, 0) + 1); sub(/[ \t]*$/, "", run)
            t = run; gsub(substr(fence, 1, 1), "", t)
            if (t == "" && length(run) >= length(fence)) fence = ""
            continue
          }
        }
        if (hcopen) {
          # Inside an HTML comment: skip to its close, then read the rest as
          # prose. One opened mid-line and left open ends with its paragraph.
          if (!(t = index(line, "-->"))) {
            if (!hcblock && line !~ /[^ \t]/) { hcopen = 0; pblank = 1; qopen = 0 }
            continue
          }
          hcopen = 0; s = prose(substr(line, t + 3))
          for (i = 1; i <= nc; i++) h[i] += cue_hits(s, C[i])
          pblank = 0; continue
        }
        if (line !~ /[^ \t]/) { pblank = 1; qopen = 0; continue }
        # Indented code: 4 columns of indent after a blank line or more
        # indented code, outside a list.
        if ((pblank || icode) && !inlist && line ~ /^( *\t|    )/) { icode = 1; pblank = 0; continue }
        icode = 0
        if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])([ \t]|$)/) inlist = 1
        else if (line ~ /^#/ || (pblank && line ~ /^[^ \t]/)) inlist = 0
        pblank = 0
        # A fence opener; a backtick fence info string holds no backtick, so
        # a line starting with an inline ```x``` span opens nothing.
        p = lead(line, 1, 1); run = substr(line, p + 1)
        if (match(run, /^(```+|~~~+)/) && !(run ~ /^`/ && index(substr(run, RLENGTH + 1), "`"))) {
          fence = substr(run, 1, RLENGTH); t = substr(line, 1, p)
          fbq = (t ~ />/); gsub(/[ \t>]/, "", t); fcol = (t != "") ? p : 0; qopen = 0
          continue
        }
        if (line ~ /^[ \t]*>/) continue
        if (line !~ /[^ \t]/ || line ~ /^[ \t]*(#|[-*+] |[0-9]+[.)] |\|)/) qopen = 0
        s = prose(line)
        for (i = 1; i <= nc; i++) h[i] += cue_hits(s, C[i])
      }
      close(f)
      for (i = 1; i <= nc; i++) if (h[i]) { O[i] += h[i]; F[i]++; BO[b, i] += h[i]; BF[b, i]++ }
    }
    END {
      printf "scope_digest=%s\nscope_files=%d\n", ENVIRON["RF_SCOPE"], S
      for (i = 1; i <= nc; i++)
        printf "cue=%s occurrences=%d files=%d saturated=%s\n", C[i], O[i], F[i], (F[i] >= 10 && F[i] * 10 >= S) ? "yes" : "no"
      for (k = 1; k <= nb; k++) for (i = 1; i <= nc; i++) if (BO[order[k], i])
        printf "batch=%s cue=%s occurrences=%d files=%d\n", order[k], C[i], BO[order[k], i], BF[order[k], i]
    }' >"$out/cues.txt" || die "plan: cannot write $out/cues.txt"
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
  local batches="$1" results="$2" list nn res d n got reason
  for list in "$batches"/batch-*.txt; do
    [[ -f "$list" ]] || continue
    nn="${list##*/batch-}"
    nn="${nn%.txt}"
    res="$results/rubric-batch-$nn.md"
    d="$(batch_digest "$list")"
    n="$(awk 'NF' "$list" | wc -l | tr -d ' ')"
    # A sidecar that does not name one readable file per list entry cannot
    # bind the contents, so the batch needs planning again, not a dispatch.
    reason=""
    sidecar_bad "$list" "$n" && reason=" reason=paths"
    if [[ ! -f "$res" ]]; then
      echo "batch=$nn status=missing$reason digest=$d"
      continue
    fi
    if [[ -n "$reason" ]]; then
      echo "batch=$nn status=stale$reason digest=$d"
      continue
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
  local nn scope="" cues=""
  while IFS= read -r nn; do
    nn="${nn#batch=}"
    nn="${nn%% *}"
    files+=("$RESULTS/rubric-batch-$nn.md")
    scope+="$nn"$'\t'"$RESULTS/rubric-batch-$nn.md"$'\n'
  done <<<"$rows"
  # cues.txt counts the contents plan saw: its scope_digest must still equal
  # the sha256 over every list's current digest, else its verdicts are stale.
  local list stale=""
  if [[ -f "$BATCHES/cues.txt" && -r "$BATCHES/cues.txt" ]]; then
    cues="$BATCHES/cues.txt"
    if [[ "$(tr -d '\r' <"$cues" | sed -n 's/^scope_digest=//p')" != "$(
      for list in "$BATCHES"/batch-*.txt; do batch_digest "$list"; done | sha256 | cut -d' ' -f1
    )" ]]; then
      cues="" stale=1
    fi
  fi
  local f
  {
    awk '
      { sub(/\r$/, "") }
      /^files_reviewed:/ { fr += $2 }
      /^files_with_findings:/ { fw += $2 }
      END { printf "files_reviewed: %d\nfiles_with_findings: %d\nbatches: %d\n", fr, fw, ARGC - 1 }' "${files[@]}"
    # Totals, then consistency flags, then decline totals, each group sorted.
    # Results come as `<NN><TAB><path>` lines on stdin; cues.txt by ENVIRON.
    # shellcheck disable=SC2016  # an awk program, not a shell expansion
    printf '%s' "$scope" | RF_CUES="$cues" RF_STALE="$stale" RF_DECLINED="$DECLINED_RE" awk "$CUE_AWK"'
      function add(list, b) { return list == "" ? b : list "," b }
      # last(s, t): the position of the last t in s, or 0.
      function last(s, t,   p, k) {
        p = 0
        while ((k = index(substr(s, p + 1), t)) > 0) p += k
        return p
      }
      # quoted(s): from the first `"` to the last `" --`, else the last `"`.
      function quoted(s,   i) {
        i = index(s, "\""); if (!i) return ""
        s = substr(s, i + 1)
        i = last(s, "\" --"); if (!i) i = last(s, "\"")
        return i ? substr(s, 1, i - 1) : s
      }
      BEGIN {
        MJ = "rule-abstract-metaphor-jargon"; cf = ENVIRON["RF_CUES"]; DECLINED = ENVIRON["RF_DECLINED"]
        if (ENVIRON["RF_STALE"] != "") print "2\tconsistency: cues.txt stale reason=digest"
        if (cf != "") {
          have = 1
          while ((getline line < cf) > 0) {
            sub(/\r$/, "", line); split(line, a, " ")
            if (line ~ /^cue=/) sat[substr(a[1], 5)] = (a[4] == "saturated=yes")
            else if (line ~ /^batch=/) occ[substr(a[1], 7), substr(a[2], 5)] = substr(a[3], 13) + 0
          }
          close(cf)
        }
      }
      # report(): a pending metaphor-jargon finding, its continuation lines
      # joined, marks each cue its quote holds as reported in batch b.
      function report(   i) {
        if (mj != "") for (i = 1; i <= nc; i++) if (cue_hits(quoted(mj), C[i])) rep[b, C[i]] = 1
        mj = ""
      }
      {
        t = index($0, "\t"); b = substr($0, 1, t - 1); f = substr($0, t + 1)
        B[++nb] = b; mj = ""
        while ((getline line < f) > 0) {
          sub(/\r$/, "", line)
          # An indented line continues the finding above it.
          if (mj != "" && line ~ /^[ \t]+[^ \t]/ && line !~ /^[ \t]*- L[0-9]+ rule-/) {
            sub(/^[ \t]+/, "", line); mj = mj " " line; continue
          }
          report()
          if (line ~ /^- L[0-9]+ rule-[a-z0-9-]+:/) {
            split(line, a, " "); r = a[3]; sub(/:$/, "", r); total[r]++
            if (r == MJ) mj = line
          } else if (line ~ DECLINED) {
            if (split(line, a, " ") > 4 && a[4] !~ /^reason=/) { a[3] = a[3] " " a[4]; a[4] = a[5] }
            a[3] = cue_key(a[3])
            dec[b, a[2], a[3]] = 1
            k = a[2] " " a[3] " " a[4]
            if ((b, k) in once) continue
            once[b, k] = 1
            dl[k] = add(dl[k], b)
          }
        }
        report(); close(f)
      }
      END {
        if (have) {
          for (i = 1; i <= nc; i++) {
            c = C[i]; r1 = r3 = ""
            for (j = 1; j <= nb; j++) {
              b = B[j]
              if (sat[c] && rep[b, c]) r1 = add(r1, b)
              if (occ[b, c] > 0 && !rep[b, c] && !((b, MJ, c) in dec)) r3 = add(r3, b)
            }
            if (r1 != "") { print "2\tconsistency: " MJ " cue=" c " saturated=yes reported_in=" r1; flag[MJ] = 1 }
            if (r3 != "") { print "2\tconsistency: " MJ " cue=" c " unaccounted_in=" r3; flag[MJ] = 1 }
          }
          for (k in dl) {
            split(k, a, " ")
            if (a[3] == "reason=saturated" && !((a[2] in sat) && sat[a[2]])) {
              print "2\tconsistency: " a[1] " cue=" a[2] " saturated=no declined_in=" dl[k]; flag[a[1]] = 1
            }
          }
        }
        for (r in total) print "1\trule_total: " r "=" total[r] ((r in flag) ? " consistency=flagged" : "")
        for (k in dl) print "3\tdeclined_total: " k " batches=" dl[k]
      }' | sort | cut -f2-
    for f in "${files[@]}"; do
      echo
      tr -d '\r' <"$f" | grep -Ev "^(batch|files_reviewed|files_with_findings):|$DECLINED_RE" || true
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
