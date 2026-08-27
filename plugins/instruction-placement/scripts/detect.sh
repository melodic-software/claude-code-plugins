#!/usr/bin/env bash
# detect.sh — deterministic fact emitter for the audit skill.
#
# WHY. The audit's judgment layer decides WHERE content belongs. It should not
# also be responsible for enumerating the corpus, finding section boundaries, or
# counting normative markers — those are mechanical, and doing them by reading
# makes findings irreproducible in two ways that matter:
#
#   * `realign` excises content by the line range the audit cited. A range that
#     came from a model reading a file is a guess; a range that came from here is
#     a fact, and the difference is whether an apply removes the right text.
#   * Two audit runs over an unchanged repository should produce the same
#     candidate set. Only a deterministic segmentation gets that.
#
# This script emits FACTS ONLY and adjudicates nothing. It does not know what a
# safety rail is, whether content is derivable, or which destination fits — all
# of that is the skill's, and stays there.
#
# Output is deterministic TSV on stdout: sorted, no timestamps, no absolute
# paths, one record per line, record type in field 1.
#
#   FILE     path  tier  total_lines
#   SECTION  path  start  end  level  heading
#   SIGNAL   path  start  normative_hits  markers
#   HINT     path  start  kind  value        (kind: ext | dir | lang)
#   RULE     path  scope  globs             (scope: scoped | unscoped)
#   SKIP     path  reason
#   SUMMARY  files_swept  files_skipped  sections  rules
#
# Frontmatter and fenced code blocks are excluded from signal and hint counting:
# a convention stated inside an example block is illustrating, not instructing.
#
# Usage:
#   detect.sh [--root <dir>] [--tier core|expanded] [--] [<path>...]
#
#   no paths   sweep the corpus (core tier, plus expanded unless --tier core)
#   <path>...  emit facts for exactly these files
#
# Exit: 0 on a successful emission (including zero findings); 2 on usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/discover.sh
. "$SCRIPT_DIR/lib/discover.sh"

usage() {
  cat <<'EOF'
detect.sh — deterministic fact emitter for instruction-placement's audit.

Usage:
  detect.sh [--root <dir>] [--tier core|expanded] [--] [<path>...]

  --root <dir>       repository root (default: cwd)
  --tier core        instruction surfaces only; skip ordinary documentation
  --tier expanded    instruction surfaces plus tracked documentation (default)
  <path>...          emit facts for exactly these files, ignoring tier

Records (TSV, sorted, deterministic):
  FILE     path  tier  total_lines
  SECTION  path  start  end  level  heading
  SIGNAL   path  start  normative_hits  markers
  HINT     path  start  kind  value          kind: ext | dir | lang
  RULE     path  scope  globs                scope: scoped | unscoped
  SKIP     path  reason
  SUMMARY  files_swept  files_skipped  sections  rules

Facts only — this script classifies nothing and proposes nothing.

Exit: 0 success; 2 usage error.
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

ROOT="$PWD"
TIER="expanded"
declare -a EXPLICIT=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    [[ $# -lt 2 ]] && die "--root needs a path"
    ROOT="$2"
    shift 2
    ;;
  --tier)
    [[ $# -lt 2 ]] && die "--tier needs core or expanded"
    case "$2" in
    core | expanded) TIER="$2" ;;
    *) die "--tier must be core or expanded" ;;
    esac
    shift 2
    ;;
  --)
    shift
    while [[ $# -gt 0 ]]; do
      EXPLICIT+=("$1")
      shift
    done
    ;;
  -*) die "unknown argument: $1" ;;
  *)
    EXPLICIT+=("$1")
    shift
    ;;
  esac
done

[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"
cd "$ROOT" || die "cannot enter --root: $ROOT"

# ---------------------------------------------------------------------------
# Corpus rules. Exclusions are absolute and applied before anything else, so
# nothing below can reach the fact stream. Mirrors context/corpus.md; that
# document is the prose owner and this is its executable form.
# ---------------------------------------------------------------------------
is_excluded() {
  case "$1" in
  */evals/fixtures/* | evals/fixtures/*) return 0 ;;
  */node_modules/* | node_modules/*) return 0 ;;
  */vendor/* | vendor/*) return 0 ;;
  .git/*) return 0 ;;
  CHANGELOG.md | */CHANGELOG.md) return 0 ;;
  *) return 1 ;;
  esac
}

classify_tier() {
  case "$1" in
  CLAUDE.md | AGENTS.md | CLAUDE.local.md | .claude/CLAUDE.md) printf 'core' ;;
  */CLAUDE.md | */AGENTS.md | */CLAUDE.local.md) printf 'core' ;;
  .claude/rules/*.md | */.claude/rules/*.md) printf 'core' ;;
  CONTRIBUTING.md | SECURITY.md | ARCHITECTURE.md | CONVENTIONS.md) printf 'named' ;;
  *guidelines*.md | *Guidelines*.md) printf 'named' ;;
  *conventions*.md | *Conventions*.md) printf 'named' ;;
  *standards*.md | *Standards*.md) printf 'named' ;;
  *style*.md | *Style*.md) printf 'named' ;;
  # `*` matches `/` in a case glob, so `docs/*.md` already covers every depth.
  docs/*.md | documentation/*.md | .github/*.md) printf 'docs' ;;
  */README.md) printf 'module-readme' ;;
  *) printf 'other' ;;
  esac
}

# ---------------------------------------------------------------------------
# Build the file list.
# ---------------------------------------------------------------------------
declare -a FILES=()
SKIPPED=0
SKIP_ROWS="$(mktemp)"
trap 'rm -f "$SKIP_ROWS"' EXIT

if ((${#EXPLICIT[@]} > 0)); then
  for f in "${EXPLICIT[@]}"; do
    f="${f#./}"
    if [[ ! -f "$f" ]]; then
      printf 'SKIP\t%s\tnot a readable file\n' "$f" >>"$SKIP_ROWS"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    FILES+=("$f")
  done
else
  tracked="$(git ls-files -z 2>/dev/null | tr '\0' '\n')"
  if [[ -z "$tracked" ]]; then
    tracked="$(find . -type f -name '*.md' 2>/dev/null | sed 's|^\./||')"
  fi
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$f" == *.md ]] || continue
    if is_excluded "$f"; then
      printf 'SKIP\t%s\texcluded by corpus rules\n' "$f" >>"$SKIP_ROWS"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    tier="$(classify_tier "$f")"
    if [[ "$TIER" == "core" && "$tier" != "core" ]]; then
      printf 'SKIP\t%s\toutside the core tier\n' "$f" >>"$SKIP_ROWS"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    FILES+=("$f")
  done <<<"$tracked"

  # Rules reached through a symlink are not tracked by design; discovery owns
  # that asymmetry, so pull them in from there rather than from the git listing.
  #
  # The exclusion and tier filters run again here. Skipping them would let this
  # loop UNDO the one above: a tracked rule under an excluded subtree is written
  # to SKIP_ROWS and left out of FILES, then re-added here because it is "not
  # already in FILES" -- emitting a SKIP row and a FILE row for the same path and
  # counting it in both summary totals. `context/corpus.md` states exclusions are
  # absolute and applied before any classification, so nothing below can reach
  # the candidate set; a second entry point into that set has to enforce the same
  # rule or the invariant is only true of the first one.
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    for existing in "${FILES[@]}"; do
      [[ "$existing" == "$r" ]] && continue 2
    done
    # Already SKIP-rowed by the loop above, so this is a silent drop rather than
    # a second row for the same path.
    is_excluded "$r" && continue
    [[ "$TIER" == "core" && "$(classify_tier "$r")" != "core" ]] && continue
    FILES+=("$r")
  done < <(ip_discover_rules .)
fi

# ---------------------------------------------------------------------------
# Per-file emission.
#
# One awk pass per file produces SECTION, SIGNAL, and HINT records together, so
# the line accounting for fences and frontmatter is done once and cannot drift
# between the three record types.
# ---------------------------------------------------------------------------
ROWS="$(mktemp)"
trap 'rm -f "$SKIP_ROWS" "$ROWS"' EXIT
SECTION_COUNT=0
RULE_COUNT=0

emit_file_facts() {
  local file="$1"
  # The path comes in through ENVIRON rather than `awk -v`: POSIX has -v process
  # escape sequences, so a path containing a backslash is rewritten before the
  # program sees it (gawk reads `\t` as a tab and drops an unknown escape's
  # backslash; mawk passes both through). Every fact this emits is keyed by the
  # path, so a mangled one silently misattributes findings.
  IP_FILE_PATH="$file" awk '
    BEGIN { path = ENVIRON["IP_FILE_PATH"] }
    function flush_section(endline,   markerlist) {
      if (sec_start == 0) return
      printf "SECTION\t%s\t%d\t%d\t%d\t%s\n", path, sec_start, endline, sec_level, sec_head
      markerlist = ""
      for (m in seen_marker) markerlist = markerlist (markerlist == "" ? "" : ",") m
      if (norm_hits > 0) {
        n = split(markerlist, arr, ",")
        # deterministic marker order
        for (i = 1; i <= n; i++)
          for (j = i + 1; j <= n; j++)
            if (arr[j] < arr[i]) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }
        markerlist = ""
        for (i = 1; i <= n; i++) markerlist = markerlist (i == 1 ? "" : ",") arr[i]
        printf "SIGNAL\t%s\t%d\t%d\t%s\n", path, sec_start, norm_hits, markerlist
      }
      for (h in hints) printf "HINT\t%s\t%d\t%s\n", path, sec_start, h
      delete seen_marker
      delete hints
      norm_hits = 0
    }
    BEGIN {
      sec_start = 0; sec_level = 0; sec_head = ""; norm_hits = 0; fm = 0; fence = 0
      # Config directories and dotfiles that look like extensions but name a
      # location. Measured: `.claude` alone accounted for 840 false hints.
      split(".claude .github .git .work .vscode .idea .venv .cursor .devin " \
            ".windsurf .local .env .gitignore .gitattributes .editorconfig " \
            ".npmrc .nvmrc .dockerignore .clinerules .cursorrules", dd, " ")
      for (i in dd) dotdirs[dd[i]] = 1
    }

    # YAML frontmatter: only when it opens on line 1.
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }

    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }

    /^#{1,6}[[:space:]]/ {
      flush_section(NR - 1)
      lvl = 0
      while (substr($0, lvl + 1, 1) == "#") lvl++
      sec_start = NR
      sec_level = lvl
      sec_head = $0
      sub(/^#+[[:space:]]*/, "", sec_head)
      gsub(/\t/, " ", sec_head)
      next
    }

    {
      line = tolower($0)
      # Normative markers. Word-boundary-ish matching without GNU-only \b.
      split("must never always required prohibited forbidden", pos, " ")
      for (i in pos)
        if (line ~ ("(^|[^a-z])" pos[i] "([^a-z]|$)")) { norm_hits++; seen_marker[pos[i]] = 1 }
      if (line ~ /(^|[^a-z])do not([^a-z]|$)/)   { norm_hits++; seen_marker["do-not"] = 1 }
      if (line ~ /(^|[^a-z])don'"'"'t([^a-z]|$)/) { norm_hits++; seen_marker["do-not"] = 1 }
      if (line ~ /(^|[^a-z])prefer([^a-z]|$)/)   { norm_hits++; seen_marker["prefer"] = 1 }

      # Glob-derivation hints, taken literally from the text.
      #
      # No interval expressions anywhere below: mawk 1.3.4 panics outright on
      # some interval-plus-escape combinations, and because a fact emitter runs
      # under a skill, that panic is easy to mistake for "this file has no
      # sections". Plain +/* quantifiers behave identically across awks.
      #
      # A leading non-alphanumeric is required so `*.cs` and `` `.cs` `` match
      # while `corpus.md` and `e.g.` do not — a dot mid-word is punctuation, not
      # an extension. Both the full dotted run and its final segment are emitted,
      # so `*.test.ts` yields `.test.ts` AND `.ts`.
      # Three precision rules, each earned from a real over-firing measured on a
      # 1,137-file corpus where `.claude` was the single most common "extension":
      #
      #   1. A token followed by `/` is a DIRECTORY component (`.claude/rules/`),
      #      never an extension.
      #   2. A known config dotdir or dotfile is never an extension, even bare.
      #   3. Real extensions are lowercase. This drops `.NET` and `.DS_Store`
      #      without needing either in a denylist.
      src = " " $0
      while (match(src, /[^A-Za-z0-9]\.[A-Za-z][A-Za-z0-9.]*/)) {
        tok = substr(src, RSTART + 1, RLENGTH - 1)
        after = substr(src, RSTART + RLENGTH, 1)
        sub(/\.+$/, "", tok)
        if (after != "/" && tok ~ /^\.[a-z][a-z0-9.]*$/ && length(tok) < 24 &&
            !(tok in dotdirs)) {
          hints["ext\t" tok] = 1
          if (index(substr(tok, 2), ".") > 0) {
            n = split(tok, segs, ".")
            if (segs[n] != "") hints["ext\t." segs[n]] = 1
          }
        }
        src = substr(src, RSTART + RLENGTH)
      }
      src = $0
      while (match(src, /`[A-Za-z0-9_.\/-]+\/`?/)) {
        tok = substr(src, RSTART + 1, RLENGTH - 1)
        sub(/`$/, "", tok)
        if (tok ~ /\/$/) hints["dir\t" tok] = 1
        src = substr(src, RSTART + RLENGTH)
      }
    }
    END { flush_section(NR) }
  ' "$file"
}

# A small, documented language→extension table. Deterministic and auditable;
# the skill may accept or override any hint, and an unknown language simply
# produces no `lang` hint rather than a guess.
lang_hints() {
  local file="$1"
  # ENVIRON rather than `awk -v`, for the reason given in emit_file_facts above.
  IP_FILE_PATH="$file" awk '
    BEGIN {
      path = ENVIRON["IP_FILE_PATH"]
      # CASE-SENSITIVE, and split into two sets — measured on a 1,137-file
      # corpus where lowercase "go" produced 338 false hints from the ordinary
      # English verb, and "shell"/"bash" produced 675 more from prose about
      # shells rather than about shell scripts.
      #
      # unambiguous[]: spellings that are never ordinary English, so they match
      # in any case. ambiguous[]: language names that collide with common words,
      # matched ONLY in their conventional capitalized form.
      unambiguous["TypeScript"]=".ts"; unambiguous["typescript"]=".ts"
      unambiguous["JavaScript"]=".js"; unambiguous["javascript"]=".js"
      unambiguous["PowerShell"]=".ps1"; unambiguous["powershell"]=".ps1"
      unambiguous["Terraform"]=".tf"; unambiguous["terraform"]=".tf"
      unambiguous["Kotlin"]=".kt"; unambiguous["kotlin"]=".kt"
      unambiguous["Python"]=".py"; unambiguous["python"]=".py"
      unambiguous["csharp"]=".cs"; unambiguous["C#"]=".cs"
      unambiguous["YAML"]=".yml"; unambiguous["yaml"]=".yml"

      ambiguous["Go"]=".go"; ambiguous["Rust"]=".rs"; ambiguous["Swift"]=".swift"
      ambiguous["Java"]=".java"; ambiguous["Ruby"]=".rb"; ambiguous["PHP"]=".php"
      ambiguous["SQL"]=".sql"; ambiguous["Bash"]=".sh"; ambiguous["Shell"]=".sh"
      fm = 0; fence = 0; sec = 0
    }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^#+[[:space:]]/ { sec = NR; next }
    {
      for (k in unambiguous)
        if ($0 ~ ("(^|[^A-Za-z#+])" k "([^A-Za-z#+]|$)")) seen[sec "\t" unambiguous[k]] = 1
      for (k in ambiguous)
        if ($0 ~ ("(^|[^A-Za-z#+])" k "([^A-Za-z#+]|$)")) seen[sec "\t" ambiguous[k]] = 1
    }
    END { for (s in seen) { split(s, p, "\t"); printf "HINT\t%s\t%s\tlang\t%s\n", path, p[1], p[2] } }
  ' "$file"
}

for f in "${FILES[@]}"; do
  tier="$(classify_tier "$f")"
  total="$(wc -l <"$f" 2>/dev/null | tr -d ' ')"
  {
    printf 'FILE\t%s\t%s\t%s\n' "$f" "$tier" "${total:-0}"
    emit_file_facts "$f"
    lang_hints "$f"
  } >>"$ROWS"
done

# Existing rule inventory, from the shared discovery layer.
while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  # One parser, shared with glob-tools.sh and render-index.sh. A private copy
  # here would risk the brace-comma bug: splitting the inline flow form
  # `["src/*.{ts,tsx}"]` on the brace comma turns one correct glob into two
  # broken ones.
  globs="$(ip_parse_paths "$rule" | paste -sd, -)"
  if [[ -n "$globs" ]]; then
    printf 'RULE\t%s\tscoped\t%s\n' "$rule" "$globs" >>"$ROWS"
  else
    printf 'RULE\t%s\tunscoped\t-\n' "$rule" >>"$ROWS"
  fi
  RULE_COUNT=$((RULE_COUNT + 1))
done < <(ip_discover_rules .)

SECTION_COUNT="$(grep -c '^SECTION	' "$ROWS" || true)"

LC_ALL=C sort "$SKIP_ROWS" 2>/dev/null
LC_ALL=C sort "$ROWS"
printf 'SUMMARY\t%s\t%s\t%s\t%s\n' \
  "${#FILES[@]}" "$SKIPPED" "$SECTION_COUNT" "$RULE_COUNT"

exit 0
