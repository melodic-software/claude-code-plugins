#!/usr/bin/env bash
# Exit: always 0 on audit paths (a read-only audit must never fail the caller);
# 2 on unknown arguments or unreadable --paths-file, when no temporary
# directory can be made for the scan's per-file streams (removed on exit), or
# when prose extraction fails.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/opt-value.sh
source "$SCRIPT_DIR/lib/opt-value.sh"
# shellcheck source=lib/cascade-read.sh
source "$SCRIPT_DIR/lib/cascade-read.sh"
# shellcheck source=lib/config-layers.sh
source "$SCRIPT_DIR/lib/config-layers.sh"
# shellcheck source=lib/resolve-targets.sh
source "$SCRIPT_DIR/lib/resolve-targets.sh"

export LC_ALL=C

EM_DASH=$'\xe2\x80\x94'
EMOJI_ERE=$'(\xf0\x9f|\xe2[\x98-\x9e\xac\xad])'
CURLY_ERE=$'(\xe2\x80[\x98\x99\x9c\x9d\x8b]|\xc2\xa0)'

DEFAULT_VOCAB="delve tapestry testament pivotal crucial underscores boasts intricate intricacies meticulous meticulously garner bolstered fostering showcasing vibrant nestled groundbreaking renowned interplay enduring utilize leverage facilitate pre-existing"

MODEL_PHRASES=("the part most people skip" "(the|my) honest take" "that.s the unlock")

PATTERN_RULES=(
  "rule-em-dash|zero-tolerance|0|0|typography|${EM_DASH}"
  "rule-emoji-formatting|formatting emoji|0|0|typography|$(printf '\t')[ ]?[ ]?[ ]?(>[ ]?)*(#+[[:space:]]+|[-*+][[:space:]]+)?${EMOJI_ERE}"
  "rule-curly-artifacts|unicode artifact|0|0|typography|${CURLY_ERE}"
  "rule-significance-inflation|phrase match|1|1|wording|(stands as a testament|testament to|pivotal (moment|role)|underscores (its|the) (importance|significance)|reflects broader|enduring legacy|marks a (significant )?shift|evolving landscape|indelible mark|deeply rooted|setting the stage for|rich tapestry|key turning point|(crucial|vital) role)"
  "rule-negative-parallelism|construction match|1|0|wording|(not (just|only|simply|merely) [^.]{0,80}but|isn.t [^.;]{0,60}[;,] it.s)"
  "rule-challenges-conclusion|formula match|1|0|wording|(despite [^.]{0,80}(challenge|hurdle)|challenges (remain|ahead|persist)|faces (several|numerous|significant|ongoing) challenges)"
  "rule-knowledge-cutoff-disclaimer|assistant-frame residue|1|1|wording|(knowledge cutoff|as of my last (knowledge )?(update|training)|up to my last training( update)?|i cannot browse|i do not have access to real|as an ai( language)? model|while specific details are (limited|scarce)|not widely (available|documented|disclosed)|(in|from) the (provided|available) (sources|search results)|based on (the )?available information)"
  "rule-llm-citation-artifacts|citation residue|0|0|typography|(oaicite|\[cite:|grok_card|attached_file|contentReference|filecite)"
  "rule-utm-params|tracking parameter|0|0|typography|utm_[a-z]+="
  "rule-chatbot-artifacts|chat-turn residue|1|1|wording|(i hope this helps|let me know if you|feel free to (ask|reach out)|i.d be happy to|happy to help|great question|you.re absolutely right|found the smoking gun)"
  "rule-filler-phrases|filler phrase|1|1|wording|(in order to|due to the fact that|it( is|.s) (important to note|worth noting)|it should be noted)"
  "rule-stacked-hedging|stacked hedge|1|1|wording|((could|may|might) potentially|(could|might) possibly)"
  "rule-model-era-phrases|phrase match|1|1|wording|__PHRASES__"
)
DENSITY_MIN_HITS=3
DENSITY_RULES=(
  "rule-ai-vocabulary|ai_vocabulary|3.0|__VOCAB__"
  "rule-copulative-avoidance|copulative_avoidance|4.0|(serves as|stands as|functions as|operates as|acts as a|represents a|marks a|boasts|features a|offers a|maintains a|refers to)"
)

PATHS_FILE=""
TARGETS=()
OFFSET=0
LIMIT=0
SHOW_CONFIG=0
LIST_TARGETS=0

usage() {
  cat <<'EOF'
detect.sh: emit AI-slop findings for /ai-slop:audit.

Usage:
  detect.sh [file.md ...]
  detect.sh --paths-file <file>
  detect.sh --offset N --limit N   # chunk the sorted target list
  detect.sh --list-targets [...]   # print <key><TAB><path> per file a scan would read, then exit
  detect.sh --show-config          # print effective config per layer, then exit
  detect.sh --help

With no paths, scans the repository's tracked markdown (git ls-files '*.md').
A --paths-file with no non-blank line scans nothing; it also reads --list-targets output.
--list-targets ignores --offset/--limit; --show-config wins over it.
Exit: 0 on audit; 2 on unknown arguments, unreadable --paths-file, no
temporary directory, or failed prose extraction.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file) require_opt_value "detect.sh" "$@"; PATHS_FILE="$2"; shift 2 ;;
  --offset) require_opt_value "detect.sh" "$@"; OFFSET="$2"; shift 2 ;;
  --limit) require_opt_value "detect.sh" "$@"; LIMIT="$2"; shift 2 ;;
  --show-config) SHOW_CONFIG=1; shift ;;
  --list-targets) LIST_TARGETS=1; shift ;;
  --help | -h) usage; exit 0 ;;
  -*) echo "detect.sh: unknown option: $1" >&2; exit 2 ;;
  *) TARGETS+=("$1"); shift ;;
  esac
done

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git -c core.fsmonitor= -c core.hooksPath=/dev/null rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

resolve_config_layers "$REPO_ROOT" "$SHOW_CONFIG"

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0
HAVE_JSON_LAYER=0
for _cfg in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
  [[ "$_cfg" == *.json ]] && HAVE_JSON_LAYER=1
done

VOCAB="$DEFAULT_VOCAB"
PHRASE_ADD=()
PHRASE_REMOVE=()
PHRASE_ADD_LAYER=""
PHRASE_REMOVE_LAYER=""
EXCLUDED_GLOBS=()
EM_DASH_ALLOWED_GLOBS=()
DISABLED_RULES=""
declare -A RULE_ALLOWED_GLOBS

threshold_for() {
  local key="$1" default="$2" v
  cascade::scalar v ".thresholds.${key}" ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
  printf '%s' "${v:-$default}"
}

if [[ "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  cascade::list EXCLUDED_GLOBS excluded_paths "${CFG_LAYERS[@]}"
  cascade::list EM_DASH_ALLOWED_GLOBS em_dash_allowed_paths "${CFG_LAYERS[@]}"
  _disabled=()
  cascade::list _disabled disabled_rules "${CFG_LAYERS[@]}"
  DISABLED_RULES="${_disabled[*]-}"
  cascade::slug_map RULE_ALLOWED_GLOBS rule_allowed_paths "${CFG_LAYERS[@]}"
  _add=()
  _remove=()
  cascade::list _add vocab_add "${CFG_LAYERS[@]}"
  cascade::list _remove vocab_remove "${CFG_LAYERS[@]}"
  add="${_add[*]-}"
  remove="${_remove[*]-}"
  [[ -n "${add// /}" ]] && VOCAB="$VOCAB $add"
  if [[ -n "${remove// /}" ]]; then
    filtered=""
    for w in $VOCAB; do
      case " $remove " in
      *" $w "*) ;;
      *) filtered="$filtered $w" ;;
      esac
    done
    VOCAB="${filtered# }"
  fi
  cascade::list PHRASE_ADD phrase_add "${CFG_LAYERS[@]}"
  PHRASE_ADD_LAYER="$cascade_list_layer"
  cascade::list PHRASE_REMOVE phrase_remove "${CFG_LAYERS[@]}"
  PHRASE_REMOVE_LAYER="$cascade_list_layer"
fi
if [[ "$HAVE_JQ" -eq 0 && "$HAVE_JSON_LAYER" -eq 1 ]]; then
  echo "Note: jq not found; JSON config layers present but unread, using defaults" >&2
fi

VOCAB_ERE="($(printf '%s' "$VOCAB" | tr ' ' '|'))"

phrase_fragment_ok() {
  grep -E -- "($1)" /dev/null >/dev/null 2>&1
  [[ $? -ne 2 ]]
}
EFFECTIVE_PHRASES=()
for frag in "${MODEL_PHRASES[@]}"; do
  for r in ${PHRASE_REMOVE[@]+"${PHRASE_REMOVE[@]}"}; do
    [[ "$frag" == "$r" ]] && continue 2
  done
  EFFECTIVE_PHRASES+=("$frag")
done
for frag in ${PHRASE_ADD[@]+"${PHRASE_ADD[@]}"}; do
  [[ -z "${frag//[[:space:]]/}" ]] && continue
  if ! phrase_fragment_ok "$frag"; then
    echo "Note: phrase_add fragment is not a valid ERE, skipped: '$frag' (${PHRASE_ADD_LAYER})" >&2
    continue
  fi
  EFFECTIVE_PHRASES+=("$frag")
done
PHRASES_ERE=""
if [[ "${#EFFECTIVE_PHRASES[@]}" -gt 0 ]]; then
  PHRASES_ERE="($(
    IFS='|'
    printf '%s' "${EFFECTIVE_PHRASES[*]}"
  ))"
fi

if [[ "${#EM_DASH_ALLOWED_GLOBS[@]}" -gt 0 ]]; then
  RULE_ALLOWED_GLOBS["rule-em-dash"]="${RULE_ALLOWED_GLOBS["rule-em-dash"]:-} ${EM_DASH_ALLOWED_GLOBS[*]}"
fi

rule_allowed() {
  local slug="$1" file="$2" globs
  globs="${RULE_ALLOWED_GLOBS[$slug]:-}"
  [[ -z "${globs// /}" ]] && return 1
  local -a glob_arr=()
  read -r -a glob_arr <<<"$globs"
  [[ "${#glob_arr[@]}" -eq 0 ]] && return 1
  matches_glob "$file" "${glob_arr[@]}"
}

rule_disabled() {
  case " $DISABLED_RULES " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  echo "Config layers (later refines earlier):"
  if [[ "${#CFG_LAYERS[@]}" -eq 0 ]]; then
    echo "  (none; bundled defaults)"
  else
    for layer in "${CFG_LAYERS[@]}"; do echo "  $layer"; done
  fi
  [[ -n "$OLD_PATH_NOTE" ]] && echo "$OLD_PATH_NOTE"
  for entry in "${DENSITY_RULES[@]}"; do
    IFS='|' read -r slug key default _ <<<"$entry"
    _val=""
    cascade::scalar _val ".thresholds.${key}" ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
    echo "Effective: threshold_${key}=${_val:-$default} (rule $slug) [layer: ${cascade_scalar_layer:-default}]"
  done
  _scratch=()
  cascade::list _scratch vocab_add ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
  _vocab_add_layer="$cascade_list_layer"
  cascade::list _scratch vocab_remove ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
  _vocab_remove_layer="$cascade_list_layer"
  echo "Effective: vocab=$VOCAB [layer: add ${_vocab_add_layer:-default}, remove ${_vocab_remove_layer:-default}]"
  echo "Effective: model_phrases=${PHRASES_ERE:-"(empty roster; rule inert)"} [layer: add ${PHRASE_ADD_LAYER:-default}, remove ${PHRASE_REMOVE_LAYER:-default}]"
  cascade::list _scratch excluded_paths ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
  echo "Effective: excluded_paths=${EXCLUDED_GLOBS[*]:-} [layer: ${cascade_list_layer:-default}]"
  cascade::list _scratch em_dash_allowed_paths ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
  _em_dash_layer="${cascade_list_layer:-default}"
  echo "Effective: em_dash_allowed_paths=${EM_DASH_ALLOWED_GLOBS[*]:-} [layer: $_em_dash_layer]"
  declare -A _slug_scratch=()
  cascade::slug_map _slug_scratch rule_allowed_paths ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
  for slug in "${!RULE_ALLOWED_GLOBS[@]}"; do
    _slug_layer="${cascade_slug_layer[$slug]:-}"
    if [[ "$slug" == rule-em-dash ]]; then
      _slug_layer="${_slug_layer:+$_slug_layer, }$_em_dash_layer"
      _slug_layer="${_slug_layer%, default}"
    fi
    echo "Effective: rule_allowed_paths[$slug]=${RULE_ALLOWED_GLOBS[$slug]# } [layer: ${_slug_layer:-default}]"
  done
  cascade::list _scratch disabled_rules ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
  echo "Effective: disabled_rules=${DISABLED_RULES:-} [layer: ${cascade_list_layer:-default}]"
  exit 0
fi

resolve_targets TARGETS "$REPO_ROOT" "$PATHS_FILE" "$OFFSET" "$LIMIT" "$LIST_TARGETS" ${TARGETS[@]+"${TARGETS[@]}"} || exit $?

matches_glob() {
  local path="$1" rel="${1#"$REPO_ROOT"/}" g
  shift
  for g in "$@"; do
    # shellcheck disable=SC2254
    case "$path" in $g) return 0 ;; *) ;; esac
    # shellcheck disable=SC2254
    case "$rel" in $g) return 0 ;; *) ;; esac
  done
  return 1
}

if [[ "$LIST_TARGETS" -eq 1 ]]; then
  for file in ${TARGETS[@]+"${TARGETS[@]}"}; do
    [[ "${#EXCLUDED_GLOBS[@]}" -gt 0 ]] && matches_glob "$file" "${EXCLUDED_GLOBS[@]}" && continue
    printf '%s\t%s\n' "${file#"$REPO_ROOT"/}" "$file"
  done
  exit 0
fi

# shellcheck disable=SC2016 # awk program text, not shell expansions
EXTRACT_AWK='
  function fence_char(s) {
    if (substr(s, 1, 3) == "```") return "`"
    if (substr(s, 1, 3) == "~~~") return "~"
    return ""
  }
  # An ordered marker carries at most nine digits (CommonMark "Lists"), so a
  # longer run is a number in prose, not a list. Without the cap a line such
  # as `1234567890. ` followed by a fence opened one, and every following
  # line was read as code until a bare closer or end of file.
  function marker_len(s,   n) {
    if (s ~ /^[-*+]/) return 1
    n = 0
    while (n < 9 && substr(s, n + 1, 1) ~ /^[0-9]$/) n++
    if (n > 0 && (substr(s, n + 1, 1) == "." || substr(s, n + 1, 1) == ")")) return n + 1
    return 0
  }
  # Inline code spans go, and so does a line ignore marker: the marker and its
  # reason are control syntax the author did not write as prose, so a rule
  # must not be charged a decline for a word that appears only there.
  function stripped(s,   t) {
    t = s
    gsub(/`[^`]*`/, "", t)
    gsub(/<!-- ai-slop-ignore(-file|-start|-end)?(:[^>]*)? -->/, "", t)
    return t
  }
  # One output row. NUL bytes are dropped from it, as capturing the per-file
  # extraction into a shell variable dropped them; left in, they would make
  # grep read the stream file as binary and report no matching lines.
  function out_row(n, text,   s) {
    s = sprintf("%d\t%s", n, text)
    if (gsub(/\000/, "", s) > 0) had_nul = 1
    return s
  }
  # One source line ($0, line number ln). Returns 1 at a file-level marker,
  # which declines the whole file wherever it sits, even inside a fence.
  function line_step(   ind, rest, fc, fi, ml, sp) {
    if ($0 ~ /^[[:space:]]*<!-- ai-slop-ignore-file(:[^>]*)? -->[[:space:]]*$/) {
      stopped = 1
      return 1
    }
    if (gen_line) {
      if ($0 ~ /^[[:space:]]*<!-- END GENERATED:[^>]*-->[[:space:]]*$/) gen_line = 0
      return 0
    }
    ind = 0
    while (substr($0, ind + 1, 1) == " ") ind++
    rest = substr($0, ind + 1)
    # A fence opened inside a list item ends with its CONTAINER, not only at a
    # closer. A non-blank line indented less than the content column of that
    # item ends the item, and lazy continuation reaches a paragraph but never
    # a fenced block, so such a line belongs to the document. Clear the fence
    # and fall through, so the line is judged on its own: it may be prose, and
    # it may itself be an opener. A blank line does NOT end an item, which is
    # why this tests rest. A document-level fence keeps fence_ind 0, so the
    # comparison is never true for one and no top-level case moves.
    if (fence != "" && fence_ind > 0 && rest != "" && ind < fence_ind) fence = ""
    fc = fence_char(rest)
    fi = 0
    if (fc == "" && ind <= 3) {
      ml = marker_len(rest)
      if (ml > 0) {
        sp = 0
        while (substr(rest, ml + sp + 1, 1) == " ") sp++
        if (sp >= 1 && sp <= 4) {
          fc = fence_char(substr(rest, ml + sp + 1))
          if (fc != "") fi = ind + ml + sp
        }
      }
    }
    if (fence == "") {
      if (fc != "" && ind <= 3) { fence = fc; fence_ind = fi; fence_line = ln; return 0 }
    } else {
      if (fence_char(rest) == fence && ind <= fence_ind + 3) fence = ""
      return 0
    }
    if ($0 ~ /^[[:space:]]*<!-- BEGIN GENERATED:[^>]*-->[[:space:]]*$/) { gen_line = ln; return 0 }
    if ($0 ~ /^[[:space:]]*<!-- ai-slop-ignore-start(:[^>]*)? -->[[:space:]]*$/) { ignored = 1; return 0 }
    if ($0 ~ /^[[:space:]]*<!-- ai-slop-ignore-end(:[^>]*)? -->[[:space:]]*$/) { ignored = 0; return 0 }
    if (ignored) { D[++n_decl] = out_row(ln, stripped($0)); return 0 }
    if ($0 ~ /<!-- ai-slop-ignore(:[^>]*)? -->/ && $0 !~ /`<!-- ai-slop-ignore(:[^>]*)? -->/) {
      D[++n_decl] = out_row(ln, stripped($0))
      return 0
    }
    P[++np] = out_row(ln, stripped($0))
    return 0
  }
  # Quotation exemption for one row of stream st; returns 1 and sets SQ when
  # the row survives.
  function strip_row(st, row,   tab, lineno, text, q, before, after) {
    tab = index(row, "\t")
    if (tab == 0) return 0
    lineno = substr(row, 1, tab - 1)
    text = substr(row, tab + 1)
    if (text ~ /^[ ]?[ ]?[ ]?>/) return 0
    if (text ~ /^[[:space:]]*$/ || text ~ /^[[:space:]]*(#|[-*+] |[0-9]+\. |\|)/) OPEN[st] = 0
    if (OPEN[st]) {
      q = index(text, "\"")
      if (q == 0) { SQ = lineno "\t"; return 1 }
      text = substr(text, q + 1)
      OPEN[st] = 0
    }
    gsub(/"[^"]*"/, "", text)
    q = index(text, "\"")
    if (q > 0) {
      # A lone quote opens a span only when it sits where an opening quote
      # sits: after the line start, whitespace, or an opening bracket, and
      # directly before a non-space character. An inch or second mark
      # (6", 30") or a stray closing quote fails that test, so it is
      # dropped and the prose on both sides stays scanned instead of
      # blanking the rest of the paragraph.
      before = (q > 1) ? substr(text, q - 1, 1) : " "
      after = substr(text, q + 1, 1)
      if (before ~ /[[:space:](\[{]/ && after ~ /[^[:space:]]/) {
        text = substr(text, 1, q - 1)
        OPEN[st] = 1
      } else {
        text = substr(text, 1, q - 1) substr(text, q + 1)
      }
    }
    SQ = lineno "\t" text
    return 1
  }
  function text_col(row,   tab) {
    tab = index(row, "\t")
    return tab ? substr(row, tab + 1) : row
  }
  # put(stream, k, rows, n, text_only): write one stream file.
  function put(stream, k, rows, n, text_only,   path, i) {
    path = dir "/" stream "/" k
    if (n == 0) print "" > path
    for (i = 1; i <= n; i++) print (text_only ? text_col(rows[i]) : rows[i]) > path
    close(path)
  }
  # quoted_free(src, n, st, dst): strip src[1..n] into dst; returns the row count.
  function quoted_free(src, n, st, dst,   i, m) {
    m = 0
    OPEN[st] = 0
    for (i = 1; i <= n; i++) if (strip_row(st, src[i])) dst[++m] = SQ
    return m
  }
  function scan_file(k, f,   r, nw, ndw) {
    fence = ""; fence_ind = 0; fence_line = 0; gen_line = 0; ignored = 0; stopped = 0
    ln = 0; np = 0; n_decl = 0; had_nul = 0
    split("", P); split("", D); split("", W); split("", DW)
    while ((r = (getline < f)) > 0) {
      ln++
      if (line_step()) break
    }
    if (r < 0) printf "detect.sh: %s: cannot be read; scanned as empty\n", f > "/dev/stderr"
    close(f)
    if (fence != "" && !stopped) {
      printf "detect.sh: %s: code fence opened at line %d is never closed; the rest of the file was read as code\n", f, fence_line > "/dev/stderr"
    }
    if (gen_line && !stopped) {
      printf "detect.sh: %s: generated region opened at line %d is never closed; the rest of the file was skipped\n", f, gen_line > "/dev/stderr"
    }
    if (stopped) { print k "\tmarker"; return }
    if (had_nul) printf "detect.sh: %s: NUL bytes dropped from the scanned text\n", f > "/dev/stderr"
    nw = quoted_free(P, np, "p", W)
    put("P", k, P, np, 0); put("TP", k, P, np, 1)
    put("W", k, W, nw, 0); put("TW", k, W, nw, 1)
    if (n_decl > 0) {
      ndw = quoted_free(D, n_decl, "d", DW)
      put("DP", k, D, n_decl, 0)
      put("DW", k, DW, ndw, 0); put("TDW", k, DW, ndw, 1)
    }
    print k "\tscan\t" (n_decl > 0 ? 1 : 0)
  }
  {
    tab = index($0, "\t")
    scan_file(substr($0, 1, tab - 1), substr($0, tab + 1))
  }
'

# shellcheck disable=SC2016 # awk program text, not shell expansions
FINDING_AWK='
  BEGIN { for (j = 0; j < 256; j++) ORD[sprintf("%c", j)] = j }
  function excerpt(s,   n, i, b, need) {
    s = substr(s, 1, 80)
    n = length(s)
    for (i = 0; i < 4 && n - i >= 1; i++) {
      b = ORD[substr(s, n - i, 1)]
      if (b < 128) break
      if (b >= 192) {
        need = (b >= 240) ? 4 : (b >= 224) ? 3 : 2
        if (i + 1 < need) s = substr(s, 1, n - i - 1)
        break
      }
    }
    gsub(/\|/, "/", s)
    return s
  }
  {
    c = index($0, ":")
    path = substr($0, 1, c - 1)
    k = substr(path, index(path, "/") + 1)
    row = substr($0, c + 1)
    sub(/^\t+/, "", row)
    t = index(row, "\t")
    if (t == 0) { lineno = row; text = "" }
    else {
      lineno = substr(row, 1, t - 1)
      text = substr(row, t + 1)
      sub(/^\t+/, "", text)
      sub(/\t+$/, "", text)
    }
    if (lineno == "") next
    print k "\t" lineno "\t" excerpt(text)
  }
'

ALL_RULES=()
for entry in "${PATTERN_RULES[@]}" "${DENSITY_RULES[@]}"; do ALL_RULES+=("${entry%%|*}"); done

declare -A FINDINGS DECLINED DECL_MARKER DECL_QUOTE DECL_CONFIG
for slug in "${ALL_RULES[@]}"; do
  FINDINGS[$slug]=0
  DECLINED[$slug]=0
  DECL_MARKER[$slug]=0
  DECL_QUOTE[$slug]=0
  DECL_CONFIG[$slug]=0
done

decline_rule() {
  local slug="$1" n="$2" cause="$3"
  DECLINED[$slug]=$((DECLINED[$slug] + n))
  case "$cause" in
  marker) DECL_MARKER[$slug]=$((DECL_MARKER[$slug] + n)) ;;
  quote) DECL_QUOTE[$slug]=$((DECL_QUOTE[$slug] + n)) ;;
  config) DECL_CONFIG[$slug]=$((DECL_CONFIG[$slug] + n)) ;;
  *)
    echo "detect.sh: internal error: unknown decline cause '$cause'" >&2
    exit 2
    ;;
  esac
}

decline_all_rules() {
  local n="$1" cause="$2" slug
  for slug in "${ALL_RULES[@]}"; do
    decline_rule "$slug" "$n" "$cause"
  done
}

TOTAL_FILES=0
DECLINED_FILES=0

declare -A OUT=()
emit_finding() {
  local row
  printf -v row 'Finding: rule=ai-slop/audit/%s file=%s line=%s fired=%s excerpt=%s\n' \
    "$2" "${REL_OF[$1]}" "$3" "$4" "$5"
  OUT[$1]+="$row"
  FINDINGS[$2]=$((FINDINGS[$2] + 1))
}

SCAN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-slop-detect.XXXXXX")" || {
  echo "detect.sh: cannot create a temporary directory; nothing was scanned" >&2
  exit 2
}
trap 'rm -rf "$SCAN_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$SCAN_DIR"/{P,W,TP,TW,DP,DW,TDW} || {
  echo "detect.sh: cannot create the scan's stream directories; nothing was scanned" >&2
  exit 2
}

scan_grep() {
  local stream="$1"
  shift
  (cd "$SCAN_DIR" && grep -r "$@" "$stream")
}

file_counts() {
  awk -v mode="$1" '
    {
      c = index($0, ":")
      path = substr($0, 1, c - 1)
      k = substr(path, index(path, "/") + 1)
      if (mode == "c") { if (substr($0, c + 1) + 0 > 0) print k "\t" substr($0, c + 1) }
      else if (!(k in n)) { n[k] = 1; order[++m] = k } else n[k]++
    }
    END { if (mode == "o") for (i = 1; i <= m; i++) print order[i] "\t" n[order[i]] }
  '
}

FILE_OF=()
REL_OF=()
STATE_OF=()
SCANNED=()
declare -A HAS_DECL=()
k=0
for file in ${TARGETS[@]+"${TARGETS[@]}"}; do
  k=$((k + 1))
  FILE_OF[k]="$file"
  REL_OF[k]="${file#"$REPO_ROOT"/}"
  if [[ "${#EXCLUDED_GLOBS[@]}" -gt 0 ]] && matches_glob "$file" "${EXCLUDED_GLOBS[@]}"; then
    DECLINED_FILES=$((DECLINED_FILES + 1))
    decline_all_rules 1 config
    STATE_OF[k]=excluded
    continue
  fi
  TOTAL_FILES=$((TOTAL_FILES + 1))
  printf '%s\t%s\n' "$k" "$file"
done >"$SCAN_DIR/list"
N_TARGETS=$k

extract_prose() {
  awk -v dir="$SCAN_DIR" "$EXTRACT_AWK" "$SCAN_DIR/list" >"$SCAN_DIR/status"
}
extract_prose
extract_status=$?
if [[ "$extract_status" -eq 134 ]]; then
  echo "detect.sh: prose extraction aborted (awk exit 134); retrying once" >&2
  extract_prose
  extract_status=$?
fi
if [[ "$extract_status" -ne 0 ]]; then
  echo "detect.sh: prose extraction failed; nothing was scanned" >&2
  exit 2
fi
if [[ "$(wc -l <"$SCAN_DIR/status" | tr -d ' ')" -ne "$TOTAL_FILES" ]]; then
  echo "detect.sh: prose extraction returned fewer files than it was given; nothing was scanned" >&2
  exit 2
fi

while IFS=$'\t' read -r k state has_decl; do
  STATE_OF[k]="$state"
  if [[ "$state" == marker ]]; then
    DECLINED_FILES=$((DECLINED_FILES + 1))
    decline_all_rules 1 marker
    continue
  fi
  SCANNED+=("$k")
  [[ "$has_decl" == 1 ]] && HAS_DECL[$k]=1
done <"$SCAN_DIR/status"

declare -A ALLOWED=()
mark_allowed() {
  local slug="$1" charge="$2" kk
  ALLOWED=()
  [[ -z "${RULE_ALLOWED_GLOBS[$slug]:-}" ]] && return 0
  for kk in ${SCANNED[@]+"${SCANNED[@]}"}; do
    if rule_allowed "$slug" "${FILE_OF[kk]}"; then
      ALLOWED[$kk]=1
      [[ "$charge" == 1 ]] && decline_rule "$slug" 1 config
    fi
  done
}

declare -A FULL_HITS=() KEPT_HITS=()
for entry in "${PATTERN_RULES[@]}"; do
  IFS='|' read -r slug label ci word class ere <<<"$entry"
  if [[ "$ere" == "__PHRASES__" ]]; then
    [[ -z "$PHRASES_ERE" ]] && continue
    ere="$PHRASES_ERE"
  fi
  rule_disabled "$slug" && continue
  [[ "${#SCANNED[@]}" -eq 0 ]] && continue
  mark_allowed "$slug" 1
  flags=(-E)
  [[ "$ci" == "1" ]] && flags+=(-i)
  [[ "$word" == "1" ]] && flags+=(-w)
  stream=P
  declined_stream=DP
  if [[ "$class" == "wording" ]]; then
    stream=W
    declined_stream=DW
    FULL_HITS=()
    KEPT_HITS=()
    while IFS=$'\t' read -r kk n; do FULL_HITS[$kk]="$n"; done < <(scan_grep P -c "${flags[@]}" -- "$ere" | file_counts c)
    while IFS=$'\t' read -r kk n; do KEPT_HITS[$kk]="$n"; done < <(scan_grep W -c "${flags[@]}" -- "$ere" | file_counts c)
    for kk in "${!FULL_HITS[@]}"; do
      [[ -n "${ALLOWED[$kk]:-}" ]] && continue
      [[ "${FULL_HITS[$kk]}" -gt "${KEPT_HITS[$kk]:-0}" ]] &&
        decline_rule "$slug" $((FULL_HITS[$kk] - ${KEPT_HITS[$kk]:-0})) quote
    done
  fi
  if [[ "${#HAS_DECL[@]}" -gt 0 ]]; then
    while IFS=$'\t' read -r kk n; do
      [[ -n "${ALLOWED[$kk]:-}" ]] && continue
      decline_rule "$slug" "$n" marker
    done < <(scan_grep "$declined_stream" -c "${flags[@]}" -- "$ere" | file_counts c)
  fi
  while IFS= read -r row; do
    kk="${row%%$'\t'*}"
    row="${row#*$'\t'}"
    [[ -n "${ALLOWED[$kk]:-}" ]] && continue
    emit_finding "$kk" "$slug" "${row%%$'\t'*}" "$label" "${row#*$'\t'}"
  done < <(scan_grep "$stream" "${flags[@]}" -- "$ere" | awk "$FINDING_AWK")
done

declare -A WORDS=()
if [[ "${#SCANNED[@]}" -gt 0 ]]; then
  while IFS=$'\t' read -r kk n; do WORDS[$kk]="$n"; done < <(
    cd "$SCAN_DIR" && find TW -type f -exec wc -w {} + |
      awk '$2 ~ /^TW\// { print substr($2, 4) "\t" $1 }'
  )
fi
for entry in "${DENSITY_RULES[@]}"; do
  IFS='|' read -r slug key default ere <<<"$entry"
  rule_disabled "$slug" && continue
  [[ "${#SCANNED[@]}" -eq 0 ]] && continue
  [[ "$ere" == "__VOCAB__" ]] && ere="$VOCAB_ERE"
  mark_allowed "$slug" 0
  if [[ "${#HAS_DECL[@]}" -gt 0 ]]; then
    while IFS=$'\t' read -r kk n; do
      [[ -n "${ALLOWED[$kk]:-}" ]] && continue
      decline_rule "$slug" "$n" marker
    done < <(scan_grep TDW -E -o -i -w -- "$ere" | file_counts o)
  fi
  threshold="$(threshold_for "$key" "$default")"
  FULL_HITS=()
  KEPT_HITS=()
  while IFS=$'\t' read -r kk n; do KEPT_HITS[$kk]="$n"; done < <(scan_grep TW -E -o -i -w -- "$ere" | file_counts o)
  while IFS=$'\t' read -r kk n; do FULL_HITS[$kk]="$n"; done < <(scan_grep TP -E -o -i -w -- "$ere" | file_counts o)
  candidates=""
  for kk in "${SCANNED[@]}"; do
    words="${WORDS[$kk]:-0}"
    [[ "$words" -gt 0 ]] || continue
    if [[ -n "${ALLOWED[$kk]:-}" ]]; then
      decline_rule "$slug" 1 config
      continue
    fi
    hits="${KEPT_HITS[$kk]:-0}"
    full_hits="${FULL_HITS[$kk]:-0}"
    [[ "$full_hits" -gt "$hits" ]] && decline_rule "$slug" $((full_hits - hits)) quote
    [[ "$hits" -lt "$DENSITY_MIN_HITS" ]] && continue
    candidates+="$kk"$'\t'"$hits"$'\t'"$words"$'\n'
  done
  [[ -z "$candidates" ]] && continue
  fired=()
  while IFS=$'\t' read -r kk hits words density over; do
    [[ "$kk" =~ ^[0-9]+$ && "$over" == 1 ]] && fired+=("$kk"$'\t'"$hits"$'\t'"$words"$'\t'"$density")
  done < <(printf '%s' "$candidates" | awk -F '\t' -v t="$threshold" '{
    split(sprintf("%.1f", ($2 * 1000) / $3), d, "\n")
    print $1 "\t" $2 "\t" $3 "\t" d[1] "\t" ((d[1] >= t) ? 1 : 0)
  }')
  [[ "${#fired[@]}" -eq 0 ]] && continue
  FIRST=()
  while IFS= read -r row; do
    kk="${row%%:*}"
    kk="${kk#W/}"
    row="${row#*:}"
    [[ "$kk" =~ ^[0-9]+$ ]] && FIRST[kk]="${row%%$'\t'*}"
  done < <(scan_grep W -E -i -m1 -- "$ere")
  for row in "${fired[@]}"; do
    IFS=$'\t' read -r kk hits words density <<<"$row"
    first_line="${FIRST[kk]:-}"
    emit_finding "$kk" "$slug" "${first_line:-1}" \
      "density $density/1000 words, threshold $threshold ($hits hits in $words words)" \
      "density rule"
  done
done

for ((k = 1; k <= N_TARGETS; k++)); do
  case "${STATE_OF[k]:-}" in
  excluded) echo "Declined: file=${REL_OF[k]} cause=excluded-glob" ;;
  marker) echo "Declined: file=${REL_OF[k]} cause=file-marker" ;;
  *) printf '%s' "${OUT[$k]:-}" ;;
  esac
done

TOTAL_FINDINGS=0
for slug in "${ALL_RULES[@]}"; do
  disabled=0
  rule_disabled "$slug" && disabled=1
  echo "Summary rule=ai-slop/audit/$slug findings=${FINDINGS[$slug]} declined=${DECLINED[$slug]} declined_marker=${DECL_MARKER[$slug]} declined_quote=${DECL_QUOTE[$slug]} declined_config=${DECL_CONFIG[$slug]} disabled=$disabled"
  TOTAL_FINDINGS=$((TOTAL_FINDINGS + FINDINGS[$slug]))
done
echo "Summary total: $TOTAL_FINDINGS findings across $TOTAL_FILES files scanned ($DECLINED_FILES files declined)"
exit 0
