#!/usr/bin/env bash
# AI-slop findings for /ai-slop:audit. Read-only.
#
# Rules: the catalog entries with v1=script (reference/catalog.md is the
# inventory; the severity crosswalk in the detector-findings convention holds
# the argued tier per rule). Two rule classes:
#   pattern  fires per prose line matching the rule's expression
#   density  fires per file when matches per 1000 words reach the threshold
#
# Output: Finding rows (rule/file/line/fired/excerpt), then Summary rows with
# per-rule finding and declined counts. All key=value, line-oriented.
# Exit: always 0 on audit paths (a read-only audit must never fail the caller);
# 2 on unknown arguments or unreadable --paths-file.
#
# Prose extraction: fenced code blocks, inline code spans, and ignore-marked
# lines and blocks are removed before any rule runs; exempted candidates are
# counted as declined per rule, never silently dropped.
#
# Unicode: matching uses LC_ALL=C byte sequences and POSIX ERE only, so
# behavior is identical across GNU and BSD grep and independent of the host
# locale. Em dash is \xE2\x80\x94; emoji classes are \xF0\x9F.. and
# \xE2[\x98-\x9E\xAC\xAD]..; curly quotes and invisible-space residue are
# \xE2\x80[\x98\x99\x9C\x9D\x8B] and \xC2\xA0.
set -u

# All text processing runs in the C locale: the byte-sequence rules require it,
# and word counts diverge between UTF-8 and C locales (caught by the CI
# portability probe — a UTF-8 default runner counted 12 words where C counted
# 15 on the same line). Forcing it here makes output identical on every
# machine regardless of the caller's locale.
export LC_ALL=C

EM_DASH=$'\xe2\x80\x94'
EMOJI_ERE=$'(\xf0\x9f|\xe2[\x98-\x9e\xac\xad])'
CURLY_ERE=$'(\xe2\x80[\x98\x99\x9c\x9d\x8b]|\xc2\xa0)'

# Distinctive AI-vocabulary defaults (catalog rule-ai-vocabulary; config-tunable).
# The trailing three are the Cursor plain-word additions (catalog calibration
# record, second pass): common enough alone that only the density gate makes
# them safe to ship.
DEFAULT_VOCAB="delve tapestry testament pivotal crucial underscore underscores boasts intricate intricacies meticulous meticulously garner bolstered fostering showcasing vibrant nestled groundbreaking renowned interplay enduring utilize leverage facilitate"

# --- Rule registry ---------------------------------------------------------------
# Pattern rules: slug|fired label|case-insensitive(0/1)|whole-word(0/1)|ERE
#
# whole-word adds grep's POSIX -w: the match must be bounded by non-word
# characters on both sides. Phrase rules need it — without it "great question"
# fires on "These are great questions for the reviewer", reporting an
# IMPORTANT-tier chat-residue finding on ordinary prose (reported in review,
# reproduced, covered below). GNU's \b would express this inline but is not
# POSIX, and this script's cross-grep parity claim rests on POSIX ERE only.
#
# It is OFF for rules whose match legitimately abuts a word character or is not
# word-shaped at all: the byte-class rules (em dash, emoji, curly quotes),
# the two EREs carrying `[^.]{0,80}` wildcards, the citation tokens (`[cite:`
# is followed by digits), and `utm_[a-z]+=` (followed by its value).
PATTERN_RULES=(
  "rule-em-dash|zero-tolerance|0|0|${EM_DASH}"
  "rule-emoji-formatting|formatting emoji|0|0|$(printf '\t')(#+[[:space:]]+|[-*+][[:space:]]+)?${EMOJI_ERE}"
  "rule-curly-artifacts|unicode artifact|0|0|${CURLY_ERE}"
  "rule-significance-inflation|phrase match|1|1|(stands as a testament|testament to|pivotal (moment|role)|underscores (its|the) (importance|significance)|reflects broader|enduring legacy|marks a (significant )?shift|evolving landscape|indelible mark|deeply rooted|setting the stage for|rich tapestry|key turning point|(crucial|vital) role)"
  "rule-negative-parallelism|construction match|1|0|(not (just|only|simply|merely) [^.]{0,80}but|isn.t [^.;]{0,60}[;,] it.s)"
  "rule-challenges-conclusion|formula match|1|0|(despite [^.]{0,80}(challenge|hurdle)|challenges (remain|ahead|persist)|faces (several|numerous|significant|ongoing) challenges)"
  "rule-knowledge-cutoff-disclaimer|assistant-frame residue|1|1|(knowledge cutoff|as of my last (update|training)|i cannot browse|i do not have access to real|as an ai( language)? model)"
  "rule-llm-citation-artifacts|citation residue|0|0|(oaicite|\[cite:|grok_card|attached_file|contentReference|filecite)"
  "rule-utm-params|tracking parameter|0|0|utm_[a-z]+="
  "rule-chatbot-artifacts|chat-turn residue|1|1|(i hope this helps|let me know if you|feel free to (ask|reach out)|i.d be happy to|happy to help|great question|you.re absolutely right|found the smoking gun)"
  "rule-filler-phrases|filler phrase|1|1|(in order to|due to the fact that|it( is|.s) (important to note|worth noting)|it should be noted)"
  "rule-stacked-hedging|stacked hedge|1|1|((could|may|might) potentially|(could|might) possibly)"
)
# Density rules: slug|threshold key|default threshold|ERE (vocab ERE is built at runtime).
# A density rule needs BOTH density >= threshold AND at least DENSITY_MIN_HITS
# matches: short files otherwise fire on a single normal-prose occurrence
# (measured on this repo: one triad in a 201-word doc hit 5.0/1000).
DENSITY_MIN_HITS=3
DENSITY_RULES=(
  "rule-ai-vocabulary|ai_vocabulary|3.0|__VOCAB__"
  "rule-copulative-avoidance|copulative_avoidance|4.0|(serves as|stands as|functions as|operates as|acts as a|represents a|marks a|boasts|features a|offers a|maintains a|refers to)"
  "rule-rule-of-three|rule_of_three|3.0|[A-Za-z]+, [A-Za-z]+, and [A-Za-z]+"
)

PATHS_FILE=""
TARGETS=()
OFFSET=0
LIMIT=0
SHOW_CONFIG=0

usage() {
  cat <<'EOF'
detect.sh: emit AI-slop findings for /ai-slop:audit.

Usage:
  detect.sh [file.md ...]
  detect.sh --paths-file <file>
  detect.sh --offset N --limit N   # chunk the sorted target list
  detect.sh --show-config          # print effective config per layer, then exit
  detect.sh --help

With no paths, scans the repository's tracked markdown (git ls-files '*.md').
Exit: 0 on audit, 2 on unknown arguments or unreadable --paths-file.
EOF
}

require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "detect.sh: $opt requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    require_opt_value "$@"
    PATHS_FILE="$2"
    shift 2
    ;;
  --offset)
    require_opt_value "$@"
    OFFSET="$2"
    shift 2
    ;;
  --limit)
    require_opt_value "$@"
    LIMIT="$2"
    shift 2
    ;;
  --show-config)
    SHOW_CONFIG=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  -*)
    echo "detect.sh: unknown option: $1" >&2
    exit 2
    ;;
  *)
    TARGETS+=("$1")
    shift
    ;;
  esac
done

# --- Config cascade (.claude/ai-slop.json; user-global -> team -> overlay) ------

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

CFG_LAYERS=()
[[ -f "${HOME:-/nonexistent}/.claude/ai-slop.json" ]] && CFG_LAYERS+=("$HOME/.claude/ai-slop.json")
[[ -f "$REPO_ROOT/.claude/ai-slop.json" ]] && CFG_LAYERS+=("$REPO_ROOT/.claude/ai-slop.json")
[[ -f "$REPO_ROOT/.claude/ai-slop.local.json" ]] && CFG_LAYERS+=("$REPO_ROOT/.claude/ai-slop.local.json")

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

VOCAB="$DEFAULT_VOCAB"
EXCLUDED_GLOBS=()
EM_DASH_ALLOWED_GLOBS=()
DISABLED_RULES=""

# cfg_scalar <jq-path>: last layer that defines the key wins (per-key override).
cfg_scalar() {
  local path="$1" layer v out=""
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    v="$(jq -r "$path // empty" "$layer" 2>/dev/null)" && [[ -n "$v" ]] && out="$v"
  done
  printf '%s' "$out"
}

cfg_array() {
  local path="$1" layer v out=""
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    v="$(jq -r "($path // empty) | .[]" "$layer" 2>/dev/null | tr '\n' ' ')"
    [[ -n "${v// /}" ]] && out="$v"
  done
  printf '%s' "$out"
}

# threshold_for <threshold key> <default>: .thresholds.<key> from config, else default.
threshold_for() {
  local key="$1" default="$2" v
  v="$(cfg_scalar ".thresholds.${key}")"
  [[ -n "$v" ]] && printf '%s' "$v" || printf '%s' "$default"
}

if [[ "$HAVE_JQ" -eq 1 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  read -r -a EXCLUDED_GLOBS <<<"$(cfg_array '.excluded_paths')"
  read -r -a EM_DASH_ALLOWED_GLOBS <<<"$(cfg_array '.em_dash_allowed_paths')"
  DISABLED_RULES="$(cfg_array '.disabled_rules')"
  add="$(cfg_array '.vocab_add')"
  remove="$(cfg_array '.vocab_remove')"
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
elif [[ "$HAVE_JQ" -eq 0 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  echo "Note: jq not found; config layers present but unread, using defaults" >&2
fi

VOCAB_ERE="($(printf '%s' "$VOCAB" | tr ' ' '|'))"

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
  for entry in "${DENSITY_RULES[@]}"; do
    IFS='|' read -r slug key default _ <<<"$entry"
    echo "Effective: threshold_${key}=$(threshold_for "$key" "$default") (rule $slug)"
  done
  echo "Effective: vocab=$VOCAB"
  echo "Effective: excluded_paths=${EXCLUDED_GLOBS[*]:-}"
  echo "Effective: em_dash_allowed_paths=${EM_DASH_ALLOWED_GLOBS[*]:-}"
  echo "Effective: disabled_rules=${DISABLED_RULES:-}"
  exit 0
fi

# --- Target list -----------------------------------------------------------------

if [[ -n "$PATHS_FILE" ]]; then
  if [[ ! -r "$PATHS_FILE" ]]; then
    echo "detect.sh: cannot read --paths-file: $PATHS_FILE" >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && TARGETS+=("$line")
  done <"$PATHS_FILE"
fi

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  while IFS= read -r line; do
    TARGETS+=("$REPO_ROOT/$line")
  done < <(git -C "$REPO_ROOT" ls-files '*.md' 2>/dev/null)
fi

# Directory targets expand to the markdown beneath them (tracked files when the
# directory is inside a git checkout, a filesystem walk otherwise). Without
# this a directory fails the scan loop's -f test and is skipped silently.
#
# ONE anchor, the caller's own spelling of the directory. A directory has
# several spellings on Git Bash: git answers `C:/Users/...` for the same
# checkout a shell reaches as `/tmp/...`. The earlier expansion built its
# prefix from `git rev-parse --show-toplevel` and its filter from `pwd`, so on
# any host where those disagree no candidate survived the filter and the walk
# below silently replaced the tracked-files listing it was meant to back up.
# `ls-files` C-quotes any path holding a non-ASCII byte unless
# `core.quotePath=false`, so a tracked `café.md` (or a filename that itself
# holds an em dash) would arrive as a literal quoted escape, fail the scan
# loop's existence test, and produce neither a finding nor a declined row.
#
# Running `ls-files` with `-C <dir>` needs neither: it is already
# restricted to that directory's subtree and answers in paths relative to it,
# so `<dir>` is the only anchor and cannot disagree with itself.
#
# The branch is chosen up front from `--is-inside-work-tree`, never from an
# empty pipeline, so a walk is only ever the answer for a directory that is
# genuinely outside a checkout. Inside one, a listing that fails says so on
# stderr rather than degrading into a different set of files.
#
# Strip one trailing slash, except when that would turn a Windows drive root
# (`C:/`) into a drive-relative path (`C:`). Windows then treats the target as
# "cwd on that drive", so git -C / find can scan the wrong tree or nothing.
# Unix root `/` is the same class: stripping leaves empty, so the original
# spelling is kept. `C:\` is unchanged because this strip only removes `/`.
normalize_dir_target() {
  local dir="${1%/}"
  if [[ -z "$dir" || "$dir" == [A-Za-z]: ]]; then
    printf '%s\n' "$1"
    return 0
  fi
  printf '%s\n' "$dir"
}

expand_dir_target() {
  local dir inside listing status
  dir="$(normalize_dir_target "$1")"

  inside="$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null || true)"
  if [[ "$inside" != "true" ]]; then
    find "$dir" -name '*.md' -type f 2>/dev/null
    return 0
  fi

  listing="$(git -C "$dir" -c core.quotePath=false ls-files '*.md')"
  status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "detect.sh: git ls-files failed under $dir (exit $status); that directory expanded to nothing" >&2
    return 0
  fi

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    if [[ "$dir" == */ || "$dir" == *\\ ]]; then
      printf '%s%s\n' "$dir" "$rel"
    else
      printf '%s/%s\n' "$dir" "$rel"
    fi
  done <<<"$listing"
}

EXPANDED=()
for t in ${TARGETS[@]+"${TARGETS[@]}"}; do
  if [[ -d "$t" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && EXPANDED+=("$line")
    done < <(expand_dir_target "$t")
  else
    EXPANDED+=("$t")
  fi
done
TARGETS=(${EXPANDED[@]+"${EXPANDED[@]}"})

mapfile -t TARGETS < <(printf '%s\n' ${TARGETS[@]+"${TARGETS[@]}"} | sort -u)
if [[ "$OFFSET" -gt 0 || "$LIMIT" -gt 0 ]]; then
  end="${#TARGETS[@]}"
  [[ "$LIMIT" -gt 0 ]] && end=$((OFFSET + LIMIT))
  mapfile -t TARGETS < <(printf '%s\n' ${TARGETS[@]+"${TARGETS[@]}"} | awk -v s="$OFFSET" -v e="$end" 'NR > s && NR <= e')
fi

matches_glob() {
  # matches_glob <path> <glob>...: any glob matches the path (or its repo-relative form).
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

# --- Prose extraction ------------------------------------------------------------
# Emits "lineno<TAB>text" for prose lines; strips fenced code blocks, inline code
# spans, and honors the ignore markers. DECLINE rows record exempted candidates.
#
# Markers must be WELL-FORMED comment markers, not prose mentions (the
# audit-noise precedent): the file/start/end forms must stand alone on their
# line, and the trailing line form must not be backtick-quoted. Without this, a
# document that DOCUMENTS the markers exempts itself — found by dogfooding when
# the plugin's own README declined and was silently half-scanned.
#
# Every form takes the same optional `: reason`, because the fix flow tells the
# operator to suppress with one (audit SKILL.md, step 3) and the catalog names
# the marker as the remedy for a recorded false-positive class. When only the
# file form parsed a reason, the two forms an operator reaches for first failed
# differently and silently: a line marker carrying a reason did not match, so
# the finding stayed AND the reason text landed in its own excerpt; a `-start`
# carrying one never opened the block, so the whole block was scanned. The `-end`
# form takes one for the same reason in the dangerous direction — an unmatched
# `-end` leaves `ignored` set and silently swallows the rest of the file.
#
# The backtick guard mirrors the line-marker pattern exactly rather than matching
# any string starting with the marker prefix. A prefix match would let a
# backticked mention of `-start`, `-end`, or `-file` veto a genuine line marker
# sharing that line, rejecting the suppression and quoting the operator's own
# marker back inside the excerpt — the same failure this parser exists to avoid,
# in a new shape. Covered by the mixed-marker case in detect.test.sh.
extract_prose() {
  # Fences per CommonMark: openers may be indented up to three spaces (matched
  # with [ ]? repetition — mawk has no {n,m} intervals), and a fence closes
  # only on its OWN character, so ~~~ inside a backtick fence stays content.
  awk '
    BEGIN { fence = ""; ignored = 0 }
    /^[[:space:]]*<!-- ai-slop-ignore-file(:[^>]*)? -->[[:space:]]*$/ { print "DECLINE\tfile"; exit }
    /^[ ]?[ ]?[ ]?```/ {
      if (fence == "") { fence = "`"; next }
      if (fence == "`") { fence = ""; next }
    }
    /^[ ]?[ ]?[ ]?~~~/ {
      if (fence == "") { fence = "~"; next }
      if (fence == "~") { fence = ""; next }
    }
    fence != "" { next }
    /^[[:space:]]*<!-- ai-slop-ignore-start(:[^>]*)? -->[[:space:]]*$/ { ignored = 1; next }
    /^[[:space:]]*<!-- ai-slop-ignore-end(:[^>]*)? -->[[:space:]]*$/ { ignored = 0; next }
    ignored { print "DECLINE\tblock"; next }
    /<!-- ai-slop-ignore(:[^>]*)? -->/ && $0 !~ /`<!-- ai-slop-ignore(:[^>]*)? -->/ { print "DECLINE\tline"; next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)   # inline code spans
      printf "%d\t%s\n", NR, line
    }
  ' "$1"
}

# Truncate an excerpt to at most 80 BYTES without splitting a multi-byte UTF-8
# sequence: under the script's forced LC_ALL=C, `cut -c` counts bytes, so an em
# dash / curly quote / emoji straddling the boundary — exactly this tool's own
# targets — would be cut mid-character and emit invalid UTF-8 into the finding.
# Scans back over at most three trailing continuation bytes; if their lead byte
# declares more bytes than survived the cut, the whole partial sequence drops.
truncate_excerpt() {
  awk '
    BEGIN { for (j = 0; j < 256; j++) ORD[sprintf("%c", j)] = j }
    {
      s = substr($0, 1, 80)
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
      print s
      exit
    }
  '
}

# --- Scan ------------------------------------------------------------------------

ALL_RULES=()
for entry in "${PATTERN_RULES[@]}"; do ALL_RULES+=("${entry%%|*}"); done
for entry in "${DENSITY_RULES[@]}"; do ALL_RULES+=("${entry%%|*}"); done

declare -A FINDINGS DECLINED
for slug in "${ALL_RULES[@]}"; do
  FINDINGS[$slug]=0
  DECLINED[$slug]=0
done

decline_all_rules() {
  local n="$1" slug
  for slug in "${ALL_RULES[@]}"; do
    DECLINED[$slug]=$((DECLINED[$slug] + n))
  done
}

TOTAL_FILES=0
DECLINED_FILES=0

emit_finding() {
  # emit_finding <slug> <rel> <lineno> <fired> <excerpt>
  printf 'Finding: rule=ai-slop/audit/%s file=%s line=%s fired=%s excerpt=%s\n' \
    "$1" "$2" "$3" "$4" "$5"
  FINDINGS[$1]=$((FINDINGS[$1] + 1))
}

for file in ${TARGETS[@]+"${TARGETS[@]}"}; do
  [[ -f "$file" ]] || continue
  rel="${file#"$REPO_ROOT"/}"

  if [[ "${#EXCLUDED_GLOBS[@]}" -gt 0 ]] && matches_glob "$file" "${EXCLUDED_GLOBS[@]}"; then
    DECLINED_FILES=$((DECLINED_FILES + 1))
    decline_all_rules 1
    echo "Declined: file=$rel cause=excluded-glob"
    continue
  fi

  TOTAL_FILES=$((TOTAL_FILES + 1))
  prose="$(extract_prose "$file")"

  # A file-level marker declines the WHOLE file wherever it sits — extraction
  # stops at the marker, so match the DECLINE row anywhere, not only as a
  # prefix (a mid-file marker would otherwise truncate the scan silently).
  if printf '%s\n' "$prose" | LC_ALL=C grep -q $'^DECLINE\tfile'; then
    DECLINED_FILES=$((DECLINED_FILES + 1))
    decline_all_rules 1
    echo "Declined: file=$rel cause=file-marker"
    continue
  fi

  declines="$(printf '%s\n' "$prose" | LC_ALL=C grep -c '^DECLINE' || true)"
  prose="$(printf '%s\n' "$prose" | LC_ALL=C grep -v '^DECLINE' || true)"
  [[ "$declines" -gt 0 ]] && decline_all_rules "$declines"

  # Pattern rules: one finding per matching prose line.
  for entry in "${PATTERN_RULES[@]}"; do
    IFS='|' read -r slug label ci word ere <<<"$entry"
    rule_disabled "$slug" && continue
    if [[ "$slug" == "rule-em-dash" && "${#EM_DASH_ALLOWED_GLOBS[@]}" -gt 0 ]] &&
      matches_glob "$file" "${EM_DASH_ALLOWED_GLOBS[@]}"; then
      DECLINED[$slug]=$((DECLINED[$slug] + 1))
      continue
    fi
    flags=(-E)
    [[ "$ci" == "1" ]] && flags+=(-i)
    [[ "$word" == "1" ]] && flags+=(-w)
    while IFS=$'\t' read -r lineno text; do
      [[ -z "$lineno" ]] && continue
      excerpt="$(printf '%s' "$text" | truncate_excerpt | tr '|' '/')"
      emit_finding "$slug" "$rel" "$lineno" "$label" "$excerpt"
    done < <(printf '%s\n' "$prose" | LC_ALL=C grep "${flags[@]}" -- "$ere" || true)
  done

  # Density rules: one finding per file when density reaches the threshold.
  words="$(printf '%s\n' "$prose" | cut -f2- | wc -w | tr -d ' ')"
  if [[ "$words" -gt 0 ]]; then
    for entry in "${DENSITY_RULES[@]}"; do
      IFS='|' read -r slug key default ere <<<"$entry"
      rule_disabled "$slug" && continue
      [[ "$ere" == "__VOCAB__" ]] && ere="$VOCAB_ERE"
      threshold="$(threshold_for "$key" "$default")"
      hits="$(printf '%s\n' "$prose" | cut -f2- | LC_ALL=C grep -E -o -i -w -- "$ere" | wc -l | tr -d ' ')"
      [[ "$hits" -lt "$DENSITY_MIN_HITS" ]] && continue
      density="$(awk -v h="$hits" -v w="$words" 'BEGIN { printf "%.1f", (h * 1000) / w }')"
      over="$(awk -v d="$density" -v t="$threshold" 'BEGIN { print (d >= t) ? 1 : 0 }')"
      if [[ "$over" -eq 1 ]]; then
        first_line="$(printf '%s\n' "$prose" | LC_ALL=C grep -E -i -m1 -- "$ere" | cut -f1)"
        emit_finding "$slug" "$rel" "${first_line:-1}" \
          "density $density/1000 words, threshold $threshold ($hits hits in $words words)" \
          "density rule"
      fi
    done
  fi
done

TOTAL_FINDINGS=0
for slug in "${ALL_RULES[@]}"; do
  disabled=0
  rule_disabled "$slug" && disabled=1
  echo "Summary rule=ai-slop/audit/$slug findings=${FINDINGS[$slug]} declined=${DECLINED[$slug]} disabled=$disabled"
  TOTAL_FINDINGS=$((TOTAL_FINDINGS + FINDINGS[$slug]))
done
echo "Summary total: $TOTAL_FINDINGS findings across $TOTAL_FILES files scanned ($DECLINED_FILES files declined)"
exit 0
