#!/usr/bin/env bash
# skill-evidence.sh — the one reader of the mandatory-skill evidence a pull
# request carries for a given head commit.
#
# WHAT IT ANSWERS. Given a head SHA and either a skill-usage ledger or a pull
# request body, which mandatory skills have evidence that they ran against that
# head, which have none, and which ran against a commit that is no longer
# fresh. Four consumers read the same verdicts from here: the pull-request
# skill's prep and ready steps, the PreToolUse gate on the ready-for-review
# flip, the ci-status validator, and the babysit merge gate.
#
# ONE GRAMMAR, TWO READERS. This script is one of them; the babysit gate's
# Python parser (`parse_skill_evidence_block` in
# `plugins/source-control/skills/babysit-prs/scripts/babysit_util.py`) is the
# other, because that gate judges a body it never has a checkout for. Both
# readers are pinned to the same row shape, `<skill> <40-hex sha>
# <timestamp>`, read the SHA case-insensitively and lowercase it, and apply
# the same freshness rule. A row carrying anything else where the SHA belongs
# is skipped here behind a `warning=malformed-row` line, which is this
# script's form of the `parsed: false` the Python reader returns.
#
# THE MAP is the consuming repository's own, in `.claude/source-control.md`
# under the H2 `## pr_skill_evidence`, one bullet per rule:
#
#   - <class> | <patterns> | <skills>
#
#   <class>     a label used in messages.
#   <patterns>  whitespace-separated gitignore patterns. `@file:<path>` reads
#               patterns from a repository file (`#` comments and blank lines
#               ignored), and the path stays inside the checkout: an absolute
#               ref or one carrying a `..` segment is refused with a `warning=`
#               line and its rule skipped. A pattern starting with `!` is a
#               gitignore negation, which `check-ignore` would report as a
#               match on the very path it excludes, so it is dropped with a
#               `warning=` line. `@renamed` matches when the diff renames
#               anything. A field may be wrapped in one pair of backticks,
#               which is how a glob list survives a markdown formatter, and is
#               stripped here.
#   <skills>    whitespace-separated required skills. `a,b` means any one of a
#               or b. A trailing `!` marks the terminal skill, of which the map
#               holds at most one.
#
# A missing file, a missing section, and a section whose body is `none` all
# mean the same thing: no rules, the mechanism is inert, every subcommand
# prints nothing useful and exits 0.
#
# ONE LAYER, BY DESIGN. This script reads exactly one config file: `--config`
# when given, otherwise `.claude/source-control.md` under the repository root.
# The three-layer merge that `reference/config-resolution.md` documents is
# resolved in prose by the skills that call this script, never here. A reader
# that needs the merged value passes the merged file through `--config`.
#
# FRESHNESS, two tiers, because a ledger row is stamped when a skill is
# INVOKED, before any edit that skill goes on to make:
#
#   * the terminal skill needs a row whose SHA EQUALS the head. It is the seal
#     the pre-PR order places last, and it is non-mutating, so it terminates.
#   * every other mandatory skill needs a row at the head or at an ANCESTOR of
#     it, reported with `commits-since=<n>` so a reader sees how far back the
#     evidence sits.
#
# Ancestry comes from git when a repository is present, and otherwise from a
# saved REST compare payload (`--compare`), so CI and the merge gate never need
# history on disk. A row absent from that payload is not proven to be an
# ancestor and is reported stale: this direction costs a re-run, the other
# direction reports evidence that does not exist.
#
# EXIT CODES: 0 on every audit path, whatever the verdict, because every
# consumer is advisory. 2 on a usage error, a missing prerequisite (jq, gh), or
# a ref this repository cannot resolve.
#
# Output is line-oriented `key=value`, on stdout. Diagnostics go to stderr.

set -uo pipefail
# Pathname expansion is OFF for the whole run. The map's fields are split on
# whitespace, and a pattern like `**/*.sh` left to the shell would expand
# against the working directory into whatever files happen to sit two levels
# down, so the map would quietly match a different set of paths in every
# checkout. Nothing here needs globbing.
set -f
export LC_ALL=C

PROG=${0##*/}
TAB=$(printf '\t')

WORKDIR=""
cleanup() {
  if [[ -n "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
  return 0
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
skill-evidence.sh — mandatory-skill evidence for a pull request head.

Usage:
  skill-evidence.sh classes (--base <ref> | --files <file>) [--config <file>]
  skill-evidence.sh check --head <sha> (--ledger <file> | --body <file>)
                    (--base <ref> | --files <file>) [--compare <json>]
                    [--config <file>]
  skill-evidence.sh render --ledger <file> --head <sha> [--config <file>]
  skill-evidence.sh report --repo <owner/repo> [--sample <n>]
  skill-evidence.sh <subcommand> --help
  skill-evidence.sh --help

Subcommands:
  classes   Print `class=<name>` for every class the diff touches.
  check     Print the per-skill verdict for a head, then `verdict=<v>`.
  render    Print the fenced `skill-evidence` block for a head.
  report    Print the advisory gate's firing counts over merged PRs.

The mandatory map is the `## pr_skill_evidence` section of the repository's
`.claude/source-control.md`, one rule per bullet:

  - <class> | <patterns> | <skills>

No map, or a map whose body is `none`: the mechanism is inert and every
subcommand exits 0 with nothing useful to say.

Exit codes: 0 on every audit path, 2 on a usage or environment error.
EOF
}

usage_classes() {
  cat <<'EOF'
skill-evidence.sh classes (--base <ref> | --files <file>) [--config <file>]

Print one `class=<name>` line per class of the mandatory map that the changed
paths match, in map order, and a `warning=<what>` line per pattern the reader
refuses to honour as written. Inert map: no output.

  --base <ref>    Diff `merge-base(<ref>, HEAD)..HEAD` for the changed paths.
  --files <file>  Read the changed paths from this file, one per line, instead
                  of the diff. Renames are unknown in this mode, so `@renamed`
                  never matches.
  --config <file> Read the map from this file instead of the repository's
                  `.claude/source-control.md`.
EOF
}

usage_check() {
  cat <<'EOF'
skill-evidence.sh check --head <sha> (--ledger <file> | --body <file>)
                  (--base <ref> | --files <file>) [--compare <json>]
                  [--config <file>]

Report the mandatory skills of every detected class against <sha>.

  --head <sha>      The commit the evidence is owed for. With `--base`, it must
                    resolve in this repository.
  --ledger <file>   Read evidence from a skill-usage JSONL ledger (jq required).
  --body <file>     Read evidence from the fenced `skill-evidence` block of a
                    pull request body. The first block wins; a second one emits
                    `warning=second-block-ignored`. A row whose SHA field is
                    not 40 hex characters is skipped, as it is in a ledger,
                    and emits `warning=malformed-row`.
  --base <ref>      Detect classes from `merge-base(<ref>, <head>)..<head>`.
  --files <file>    Detect classes from this newline-separated path list.
  --compare <json>  A saved REST compare payload (an array of compare results,
                    or one result) used for ancestry instead of git. A row
                    whose SHA the payload does not carry is reported stale.
  --config <file>   Read the map from this file.

Output lines: `class=<name>`, `missing=<skill>` (an any-of group prints the
group), `stale=<skill> sha=<sha>`, `fresh=<skill> sha=<sha> commits-since=<n>`,
`warning=<what>` for a map the reader would not honour as written, and a final
`verdict=clean|gap|inert`.
EOF
}

usage_render() {
  cat <<'EOF'
skill-evidence.sh render --ledger <file> --head <sha> [--config <file>]

Print the fenced `skill-evidence` block for <sha>: one `<skill> <sha> <ts>` row
per skill the map names, latest row per skill, sorted by skill name, counting
only rows at the head or on its history. No qualifying row: no output.
EOF
}

usage_report() {
  cat <<'EOF'
skill-evidence.sh report --repo <owner/repo> [--sample <n>]

Count the ci-status validator's marker comments over recently merged pull
requests and print `fired=<n> agreed=<n> sampled=<n>`:

  fired    merged PRs that carried a `verdict=gap` marker.
  agreed   of those, the ones that later carried a `verdict=clean` marker
           before the merge, at the same head or a later one.
  sampled  merged PRs read (default 40, `--sample` to change).

Walks recently-updated closed pull requests one page at a time and stops at
`--sample` merged ones, at the last page, or at five pages, whichever comes
first. Reads the markers currently visible, so a validator that rewrites its
comment in place is counted by what the comment says now.
Only comments authored by `github-actions[bot]` are counted: the marker is
plain text anyone can paste, and a count a pull request can inflate is not a
promotion signal. This is the promotion-time report, never a gate.
EOF
}

die_usage() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

note() {
  printf '%s: %s\n' "$PROG" "$1" >&2
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 ||
    die_usage "$1 is required for this subcommand but is not on PATH"
}

# ---------------------------------------------------------------------------
# Repository and config
# ---------------------------------------------------------------------------

REPO_ROOT=""
resolve_repo_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] && [[ -d "${CLAUDE_PROJECT_DIR}" ]]; then
    REPO_ROOT=$(cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd)
    return 0
  fi
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
  return 0
}

git_present() {
  [[ -n "$REPO_ROOT" ]] && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1
}

CONFIG_FILE=""
RULES_FILE=""
TERMINAL_TOKEN=""

# load_config — write one `<class>\t<patterns>\t<skills>` line per rule into
# RULES_FILE and set TERMINAL_TOKEN. An absent surface, an absent section and a
# `none` body all leave the file empty, which every caller reads as inert.
load_config() {
  RULES_FILE="$WORKDIR/rules.tsv"
  : >"$RULES_FILE"
  TERMINAL_TOKEN=""

  local file="$CONFIG_FILE"
  if [[ -z "$file" ]]; then
    if [[ -z "$REPO_ROOT" ]]; then
      return 0
    fi
    file="$REPO_ROOT/.claude/source-control.md"
  fi
  [[ -f "$file" ]] || return 0

  # A field may be written as a markdown code span. A pattern field usually has
  # to be: `**/*.sh **/*.py` is a pair of strong-emphasis markers to a markdown
  # formatter, which rewrites the line and silently changes the map. One pair
  # of wrapping backticks per field is stripped here so the surface can be
  # written the way markdown wants it.
  tr -d '\r' <"$file" | awk -F'|' -v OFS="$TAB" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function unspan(s) {
      s = trim(s)
      if (length(s) > 1 && substr(s, 1, 1) == "`" && substr(s, length(s), 1) == "`") {
        s = substr(s, 2, length(s) - 2)
      }
      return trim(s)
    }
    /^## / { insec = ($0 ~ /^##[ \t]+pr_skill_evidence[ \t]*$/); next }
    !insec { next }
    {
      t = trim($0)
      if (t == "") next
      if (substr(t, 1, 1) != "-") next
      c = trim($1); sub(/^-[ \t]*/, "", c); c = unspan(c)
      p = unspan($2)
      s = unspan($3)
      if (NF < 3 || c == "" || p == "" || s == "") {
        print "skill-evidence.sh: ignoring malformed rule: " t > "/dev/stderr"
        next
      }
      print c, p, s
    }
  ' >"$RULES_FILE"

  local class pats skills tok
  while IFS="$TAB" read -r class pats skills; do
    for tok in $skills; do
      case "$tok" in
      *'!')
        if [[ -z "$TERMINAL_TOKEN" ]]; then
          TERMINAL_TOKEN=${tok%!}
        else
          note "more than one terminal skill in the map; keeping $TERMINAL_TOKEN and reading ${tok%!} as ordinary"
        fi
        ;;
      *) ;;
      esac
    done
  done <"$RULES_FILE"
  return 0
}

config_is_inert() {
  [[ ! -s "$RULES_FILE" ]]
}

# ---------------------------------------------------------------------------
# Changed paths and class detection
# ---------------------------------------------------------------------------

PATHS_FILE=""
RENAMED_ANY=false

# collect_paths_from_diff <base-ref> <endpoint> — the diff's changed paths, plus
# the old and the new name of every rename, into PATHS_FILE.
collect_paths_from_diff() {
  local base="$1" endpoint="$2" mb="" renames=""
  git_present || die_usage "class detection from --base needs a git repository"
  git -C "$REPO_ROOT" rev-parse --verify --quiet "$endpoint" >/dev/null 2>&1 ||
    die_usage "cannot resolve <$endpoint> in this repository"
  git -C "$REPO_ROOT" rev-parse --verify --quiet "$base" >/dev/null 2>&1 ||
    die_usage "cannot resolve base ref <$base> in this repository"

  mb=$(git -C "$REPO_ROOT" merge-base "$base" "$endpoint" 2>/dev/null) || mb=""
  if [[ -z "$mb" ]]; then
    die_usage "no merge base between <$base> and <$endpoint>"
  fi

  git -C "$REPO_ROOT" diff --name-only "$mb..$endpoint" 2>/dev/null >"$PATHS_FILE"

  renames=$(git -C "$REPO_ROOT" diff --name-status -M --diff-filter=R "$mb..$endpoint" 2>/dev/null) || renames=""
  if [[ -n "$renames" ]]; then
    RENAMED_ANY=true
    printf '%s\n' "$renames" | awk -F'\t' 'NF >= 3 { print $2; print $3 }' >>"$PATHS_FILE"
  fi
  return 0
}

collect_paths_from_file() {
  local file="$1"
  [[ -f "$file" ]] || die_usage "path list not found: $file"
  tr -d '\r' <"$file" | awk 'NF > 0' >"$PATHS_FILE"
  return 0
}

# class_matches <patterns> — 0 when any changed path matches the class.
class_matches() {
  local pats="$1" tok pfile raw out ref line
  pfile="$WORKDIR/patterns"
  raw="$WORKDIR/patterns.raw"
  : >"$pfile"
  : >"$raw"

  for tok in $pats; do
    case "$tok" in
    '@renamed')
      if [[ "$RENAMED_ANY" == true ]]; then
        return 0
      fi
      ;;
    '@file:'*)
      ref="${tok#@file:}"
      # The ref is joined to the repository root, so it names a file inside the
      # checkout or it names nothing. An absolute path or a `..` segment would
      # read a file the map has no claim on, which is how a map becomes a
      # reader of `/etc/passwd`. The rule is skipped, not the run: the map is
      # advisory everywhere it is read.
      case "/$ref/" in
      "//"* | *"/../"*)
        printf 'warning=unsafe-pattern-file ref=%s\n' "$ref"
        return 1
        ;;
      *) ;;
      esac
      if [[ -n "$REPO_ROOT" ]] && [[ -f "$REPO_ROOT/$ref" ]]; then
        tr -d '\r' <"$REPO_ROOT/$ref" |
          awk '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") } NF > 0 && substr($0, 1, 1) != "#"' >>"$raw"
      else
        note "pattern file not found, class rule degraded: $ref"
      fi
      ;;
    *)
      printf '%s\n' "$tok" >>"$raw"
      ;;
    esac
  done

  # A gitignore negation re-includes a path, and `check-ignore -v` reports the
  # negated line as the matching source just as it reports a positive one. A
  # class would therefore count `!scripts/keep.sh` as a match on the very file
  # the author wrote it to exclude. Negations are dropped before git sees them,
  # from both sources, so a class matches only what it names.
  while IFS= read -r line; do
    case "$line" in
    '!'*) printf 'warning=negation-pattern-ignored pattern=%s\n' "$line" ;;
    *) printf '%s\n' "$line" >>"$pfile" ;;
    esac
  done <"$raw"

  [[ -s "$pfile" ]] || return 1
  [[ -s "$PATHS_FILE" ]] || return 1
  git_present || return 1

  # `check-ignore --no-index` still consults the repository's own ignore rules,
  # so a tracked path the repository gitignores would match from the WRONG
  # source. Keeping only the lines whose source is this pattern file is what
  # makes the verdict the map's and not `.gitignore`'s.
  out="$WORKDIR/check-ignore.out"
  : >"$out"
  git -C "$REPO_ROOT" -c core.excludesFile="$pfile" check-ignore --no-index -v --stdin \
    <"$PATHS_FILE" >"$out" 2>/dev/null
  awk -v src="$pfile:" 'index($0, src) == 1 { found = 1; exit } END { exit !found }' "$out"
}

DETECTED=""
detect_classes() {
  local class pats skills
  DETECTED=""
  git_present ||
    die_usage "class detection needs a git repository: the map's patterns are evaluated by git check-ignore"
  while IFS="$TAB" read -r class pats skills; do
    if class_matches "$pats"; then
      DETECTED="$DETECTED $class"
    fi
  done <"$RULES_FILE"
  return 0
}

class_detected() {
  case " $DETECTED " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Evidence rows
# ---------------------------------------------------------------------------

ROWS_FILE=""

# sort_rows — skill ascending, timestamp descending, so the first row a query
# reads for a skill is its latest.
sort_rows() {
  local sorted="$WORKDIR/rows.sorted"
  sort -t "$TAB" -k1,1 -k3,3r "$ROWS_FILE" >"$sorted" 2>/dev/null || cp "$ROWS_FILE" "$sorted"
  mv "$sorted" "$ROWS_FILE"
  return 0
}

MALFORMED_ROW=false

# keep_well_formed <in> <out> — copy the rows whose SHA field is 40 hex
# characters, lowercased, and set MALFORMED_ROW when anything else was
# dropped. The length test with a character class rather than an interval
# expression, because a `{40}` repetition is not portable across every awk
# this repository runs on.
keep_well_formed() {
  local in="$1" out="$2" marker="$WORKDIR/malformed"
  rm -f "$marker"
  awk -F"$TAB" -v OFS="$TAB" -v marker="$marker" '
    {
      sha = tolower($2)
      if (length(sha) == 40 && sha ~ /^[0-9a-f]+$/) { print $1, sha, $3; next }
      print "malformed" > marker
    }
  ' "$in" >"$out"
  if [[ -f "$marker" ]]; then
    MALFORMED_ROW=true
  fi
  return 0
}

# rows_from_ledger <file> — `<skill>\t<sha>\t<ts>` per SkillUse row.
rows_from_ledger() {
  local file="$1" raw
  require_tool jq
  : >"$ROWS_FILE"
  MALFORMED_ROW=false
  if [[ ! -f "$file" ]]; then
    note "ledger not found, reading as no rows: $file"
    return 0
  fi
  raw="$WORKDIR/rows.raw"
  tr -d '\r' <"$file" | jq -r '
    select(type == "object")
    | select((.event // "") == "SkillUse")
    | select((.skill // "") != "" and (.sha // "") != "")
    | [.skill, (.sha | tostring), (.ts // "")]
    | @tsv
  ' 2>/dev/null >"$raw" ||
    note "the ledger has a line jq could not parse; reading the rows before it"
  keep_well_formed "$raw" "$ROWS_FILE"
  sort_rows
  return 0
}

SECOND_BLOCK=false

# rows_from_body <file> — the rows of the FIRST fenced `skill-evidence` block.
# HTML comment regions are dropped before the scan, so a commented-out block is
# never evidence.
rows_from_body() {
  local file="$1" marker raw
  : >"$ROWS_FILE"
  SECOND_BLOCK=false
  MALFORMED_ROW=false
  if [[ ! -f "$file" ]]; then
    note "body file not found, reading as no rows: $file"
    return 0
  fi

  marker="$WORKDIR/second-block"
  raw="$WORKDIR/rows.raw"
  rm -f "$marker"

  tr -d '\r' <"$file" | awk -v OFS="$TAB" -v marker="$marker" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    {
      line = $0
      while (1) {
        if (incomment) {
          i = index(line, "-->")
          if (i == 0) { line = ""; break }
          incomment = 0
          line = substr(line, i + 3)
          continue
        }
        i = index(line, "<!--")
        if (i == 0) break
        incomment = 1
        line = substr(line, 1, i - 1) " "
      }
      t = trim(line)
      if (infence) {
        if (t == "```" || t == "~~~") { infence = 0; done = 1; next }
        if (t == "") next
        n = split(t, f, /[ \t]+/)
        if (n >= 3) print f[1], f[2], f[3]
        next
      }
      if (t == "```skill-evidence" || t == "~~~skill-evidence") {
        if (done) { print "second" > marker; next }
        infence = 1
      }
    }
  ' >"$raw"

  if [[ -f "$marker" ]]; then
    SECOND_BLOCK=true
  fi
  keep_well_formed "$raw" "$ROWS_FILE"
  sort_rows
  return 0
}

# ---------------------------------------------------------------------------
# Freshness
# ---------------------------------------------------------------------------

COMPARE_FILE=""
HEAD_SHA=""

is_ancestor() {
  local sha="$1" status
  [[ "$sha" == "$HEAD_SHA" ]] && return 0
  if [[ -n "$COMPARE_FILE" ]]; then
    # `.base_commit.sha` ONLY. Every payload in the array is a
    # `compare/<row>...<head>` result, so `base_commit` is the row the entry
    # was fetched for and `merge_base_commit` is wherever those two histories
    # last met. Matching the merge base hands a row somebody else's verdict:
    # when row A has diverged, its merge base is typically row B, so B would
    # read A's `diverged` status and be reported stale while its own
    # `identical` entry sits unread in the same array.
    status=$(jq -r --arg sha "$sha" '
      [ (if type == "array" then .[] else . end)
        | select((.base_commit.sha // "") == $sha)
        | (.status // "") ] | .[0] // ""
    ' "$COMPARE_FILE" 2>/dev/null) || status=""
    case "$status" in
    identical | ahead) return 0 ;;
    *) return 1 ;;
    esac
  fi
  git_present || return 1
  git -C "$REPO_ROOT" merge-base --is-ancestor "$sha" "$HEAD_SHA" >/dev/null 2>&1
}

commits_since() {
  local sha="$1" n
  if ! git_present; then
    printf 'unknown'
    return 0
  fi
  n=$(git -C "$REPO_ROOT" rev-list --count --no-merges "$sha..$HEAD_SHA" 2>/dev/null) || n=""
  if [[ -z "$n" ]]; then
    printf 'unknown'
  else
    printf '%s' "$n"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# classes
# ---------------------------------------------------------------------------

cmd_classes() {
  local base="" files="" arg class pats skills
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --help | -h)
      usage_classes
      exit 0
      ;;
    --base)
      [[ $# -ge 2 ]] || die_usage "--base needs a value"
      base="$2"
      shift 2
      ;;
    --files)
      [[ $# -ge 2 ]] || die_usage "--files needs a value"
      files="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || die_usage "--config needs a value"
      CONFIG_FILE="$2"
      shift 2
      ;;
    *) die_usage "unknown option for classes: $arg" ;;
    esac
  done

  if [[ -n "$base" ]] && [[ -n "$files" ]]; then
    die_usage "classes takes --base or --files, never both"
  fi
  if [[ -z "$base" ]] && [[ -z "$files" ]]; then
    die_usage "classes needs --base <ref> or --files <file>"
  fi

  load_config
  config_is_inert && return 0

  PATHS_FILE="$WORKDIR/paths"
  : >"$PATHS_FILE"
  if [[ -n "$base" ]]; then
    collect_paths_from_diff "$base" "HEAD"
  else
    collect_paths_from_file "$files"
  fi
  detect_classes

  while IFS="$TAB" read -r class pats skills; do
    class_detected "$class" && printf 'class=%s\n' "$class"
  done <"$RULES_FILE"
  return 0
}

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

cmd_check() {
  local ledger="" body="" base="" files="" arg
  local class pats skills tok group seen="" verdict="clean"
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --help | -h)
      usage_check
      exit 0
      ;;
    --head)
      [[ $# -ge 2 ]] || die_usage "--head needs a value"
      HEAD_SHA="$2"
      shift 2
      ;;
    --ledger)
      [[ $# -ge 2 ]] || die_usage "--ledger needs a value"
      ledger="$2"
      shift 2
      ;;
    --body)
      [[ $# -ge 2 ]] || die_usage "--body needs a value"
      body="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || die_usage "--base needs a value"
      base="$2"
      shift 2
      ;;
    --files)
      [[ $# -ge 2 ]] || die_usage "--files needs a value"
      files="$2"
      shift 2
      ;;
    --compare)
      [[ $# -ge 2 ]] || die_usage "--compare needs a value"
      COMPARE_FILE="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || die_usage "--config needs a value"
      CONFIG_FILE="$2"
      shift 2
      ;;
    *) die_usage "unknown option for check: $arg" ;;
    esac
  done

  [[ -n "$HEAD_SHA" ]] || die_usage "check needs --head <sha>"
  if [[ -n "$ledger" ]] && [[ -n "$body" ]]; then
    die_usage "check takes --ledger or --body, never both"
  fi
  if [[ -z "$ledger" ]] && [[ -z "$body" ]]; then
    die_usage "check needs --ledger <file> or --body <file>"
  fi
  if [[ -n "$base" ]] && [[ -n "$files" ]]; then
    die_usage "check takes --base or --files, never both"
  fi
  if [[ -z "$base" ]] && [[ -z "$files" ]]; then
    die_usage "check needs --base <ref> or --files <file> to detect classes"
  fi
  if [[ -n "$COMPARE_FILE" ]]; then
    [[ -f "$COMPARE_FILE" ]] || die_usage "compare payload not found: $COMPARE_FILE"
    require_tool jq
  fi

  load_config
  if config_is_inert; then
    printf 'verdict=inert\n'
    return 0
  fi

  PATHS_FILE="$WORKDIR/paths"
  : >"$PATHS_FILE"
  if [[ -n "$base" ]]; then
    collect_paths_from_diff "$base" "$HEAD_SHA"
  else
    collect_paths_from_file "$files"
  fi
  detect_classes

  ROWS_FILE="$WORKDIR/rows.tsv"
  if [[ -n "$ledger" ]]; then
    rows_from_ledger "$ledger"
  else
    rows_from_body "$body"
  fi

  while IFS="$TAB" read -r class pats skills; do
    class_detected "$class" || continue
    printf 'class=%s\n' "$class"
  done <"$RULES_FILE"

  if [[ "$SECOND_BLOCK" == true ]]; then
    printf 'warning=second-block-ignored\n'
  fi
  # A row whose SHA field is not 40 hex characters is not evidence of
  # anything: the readers key on a commit id, and `main` or a short SHA names
  # no commit either of them can compare. Skipped, and said out loud, so a
  # body that looks complete to a human is not silently read as empty.
  if [[ "$MALFORMED_ROW" == true ]]; then
    printf 'warning=malformed-row\n'
  fi

  while IFS="$TAB" read -r class pats skills; do
    class_detected "$class" || continue
    for tok in $skills; do
      group=${tok%!}
      case " $seen " in
      *" $group "*) continue ;;
      *) seen="$seen $group" ;;
      esac
      evaluate_requirement "$group" || verdict="gap"
    done
  done <"$RULES_FILE"

  printf 'verdict=%s\n' "$verdict"
  return 0
}

# evaluate_requirement <group> — print the one line this requirement earns.
# Returns 1 when the requirement is unmet.
evaluate_requirement() {
  local group="$1" members member row sha ts query
  local stale_skill="" stale_sha=""
  local terminal=false

  members=$(printf '%s\n' "$group" | tr ',' ' ')
  query="$WORKDIR/query.tsv"
  if [[ -n "$TERMINAL_TOKEN" ]] && [[ "$group" == "$TERMINAL_TOKEN" ]]; then
    terminal=true
  fi

  for member in $members; do
    awk -F"$TAB" -v s="$member" '$1 == s' "$ROWS_FILE" >"$query"
    while IFS="$TAB" read -r row sha ts; do
      [[ -n "$sha" ]] || continue
      if [[ "$terminal" == true ]]; then
        if [[ "$sha" == "$HEAD_SHA" ]]; then
          printf 'fresh=%s sha=%s commits-since=0\n' "$row" "$sha"
          return 0
        fi
      elif is_ancestor "$sha"; then
        printf 'fresh=%s sha=%s commits-since=%s\n' "$row" "$sha" "$(commits_since "$sha")"
        return 0
      fi
      if [[ -z "$stale_skill" ]]; then
        stale_skill="$row"
        stale_sha="$sha"
      fi
    done <"$query"
  done

  if [[ -n "$stale_skill" ]]; then
    printf 'stale=%s sha=%s\n' "$stale_skill" "$stale_sha"
  else
    printf 'missing=%s\n' "$group"
  fi
  return 1
}

# ---------------------------------------------------------------------------
# render
# ---------------------------------------------------------------------------

cmd_render() {
  local ledger="" arg class pats skills tok member wanted="" out query row sha ts
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --help | -h)
      usage_render
      exit 0
      ;;
    --ledger)
      [[ $# -ge 2 ]] || die_usage "--ledger needs a value"
      ledger="$2"
      shift 2
      ;;
    --head)
      [[ $# -ge 2 ]] || die_usage "--head needs a value"
      HEAD_SHA="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || die_usage "--config needs a value"
      CONFIG_FILE="$2"
      shift 2
      ;;
    *) die_usage "unknown option for render: $arg" ;;
    esac
  done

  [[ -n "$ledger" ]] || die_usage "render needs --ledger <file>"
  [[ -n "$HEAD_SHA" ]] || die_usage "render needs --head <sha>"

  load_config
  config_is_inert && return 0

  ROWS_FILE="$WORKDIR/rows.tsv"
  rows_from_ledger "$ledger"

  # The map's whole skill vocabulary: a block reports the skills the map names,
  # never every skill the ledger happens to hold.
  while IFS="$TAB" read -r class pats skills; do
    for tok in $skills; do
      for member in $(printf '%s\n' "${tok%!}" | tr ',' ' '); do
        case " $wanted " in
        *" $member "*) ;;
        *) wanted="$wanted $member" ;;
        esac
      done
    done
  done <"$RULES_FILE"

  out="$WORKDIR/render.tsv"
  query="$WORKDIR/query.tsv"
  : >"$out"
  for member in $wanted; do
    awk -F"$TAB" -v s="$member" '$1 == s' "$ROWS_FILE" >"$query"
    while IFS="$TAB" read -r row sha ts; do
      [[ -n "$sha" ]] || continue
      if is_ancestor "$sha"; then
        printf '%s%s%s%s%s\n' "$row" "$TAB" "$sha" "$TAB" "$ts" >>"$out"
        break
      fi
    done <"$query"
  done

  [[ -s "$out" ]] || return 0

  # A row whose timestamp the ledger never carried still renders three fields,
  # so the block a reader parses back has the grammar it promises.
  printf '%s\n' '```skill-evidence'
  sort -t "$TAB" -k1,1 "$out" | awk -F"$TAB" '{ print $1, $2, ($3 == "" ? "-" : $3) }'
  printf '%s\n' '```'
  return 0
}

# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

# The hard ceiling on pages of closed pull requests `report` will walk. Four
# hundred closed pull requests, newest-updated first, is far past any sample a
# promotion review asks for, and the cap is what keeps an unlucky repository
# (one whose recent closed pull requests are mostly unmerged) from turning a
# bounded report into an unbounded walk.
MAX_REPORT_PAGES=5

cmd_report() {
  local repo="" sample=40 arg
  local numbers fired=0 agreed=0 sampled=0 number markers result
  local merged_count page payload page_numbers page_size
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --help | -h)
      usage_report
      exit 0
      ;;
    --repo)
      [[ $# -ge 2 ]] || die_usage "--repo needs a value"
      repo="$2"
      shift 2
      ;;
    --sample)
      [[ $# -ge 2 ]] || die_usage "--sample needs a value"
      sample="$2"
      shift 2
      ;;
    *) die_usage "unknown option for report: $arg" ;;
    esac
  done

  [[ -n "$repo" ]] || die_usage "report needs --repo <owner/repo>"
  case "$sample" in
  '' | *[!0-9]*) die_usage "--sample takes a positive integer" ;;
  *) ;;
  esac
  require_tool gh
  require_tool jq

  # ONE PAGE AT A TIME, NEWEST FIRST, NEVER `--paginate`. The question is
  # about the most recently merged pull requests, and `--paginate` would walk
  # every closed pull request a repository has ever had to answer it. Sorting
  # by `updated` descending puts the candidates on the first page, and the
  # walk stops at the first of: `--sample` merged pull requests in hand, a
  # short page (the last one), or the page cap below, which bounds the call
  # count whatever the repository's shape.
  #
  # The sample is taken AFTER the capture, never by a reader inside the
  # pipeline: under pipefail an early-exiting reader makes the whole pipeline
  # look like a failure and the run would report nothing sampled.
  numbers=""
  merged_count=0
  page=1
  while [[ "$page" -le "$MAX_REPORT_PAGES" ]] && [[ "$merged_count" -lt "$sample" ]]; do
    payload=$(gh api \
      "repos/$repo/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=$page" \
      2>/dev/null) || payload=""
    [[ -n "$payload" ]] || break
    page_numbers=$(printf '%s\n' "$payload" |
      jq -r 'if type == "array" then .[] else . end
             | select((.merged_at // null) != null) | .number' 2>/dev/null) || page_numbers=""
    page_size=$(printf '%s\n' "$payload" |
      jq -r 'if type == "array" then length else 1 end' 2>/dev/null) || page_size=0
    if [[ -n "$page_numbers" ]]; then
      if [[ -n "$numbers" ]]; then
        numbers=$(printf '%s\n%s\n' "$numbers" "$page_numbers")
      else
        numbers="$page_numbers"
      fi
      merged_count=$(printf '%s\n' "$numbers" | awk 'NF > 0 { n++ } END { print n + 0 }')
    fi
    case "$page_size" in
    '' | *[!0-9]*) break ;;
    *) [[ "$page_size" -ge 100 ]] || break ;;
    esac
    page=$((page + 1))
  done
  numbers=$(printf '%s\n' "$numbers" | awk -v n="$sample" 'NF > 0 && ++seen <= n')

  for number in $numbers; do
    sampled=$((sampled + 1))
    markers=$(gh api --paginate "repos/$repo/issues/$number/comments?per_page=100" 2>/dev/null |
      jq -r 'if type == "array" then .[] else . end
             | select((.user.login // "") == "github-actions[bot]")
             | (.body // "")' 2>/dev/null |
      tr -d '\r' |
      grep -o '<!-- pr-skill-evidence head=[0-9a-fA-F]* verdict=[a-z]* -->') || markers=""
    [[ -n "$markers" ]] || continue
    # AGREEMENT IS ANY LATER CLEAN MARKER, AT WHATEVER HEAD. The pair being
    # counted is "the reporter said gap, and then the same pull request said
    # clean". Requiring a different head missed the case the gate is best at:
    # a block re-rendered into the body with no new commit, which closes the
    # gap at the head the gap was reported for. The markers arrive in comment
    # order, so position in this stream is the "later" the count means.
    result=$(printf '%s\n' "$markers" | awk '
      /verdict=gap/ { fired = 1; next }
      /verdict=clean/ { if (fired) agreed = 1 }
      END { print fired + 0, agreed + 0 }
    ')
    case "$result" in
    '1 1')
      fired=$((fired + 1))
      agreed=$((agreed + 1))
      ;;
    '1 0') fired=$((fired + 1)) ;;
    *) ;;
    esac
  done

  printf 'fired=%s agreed=%s sampled=%s\n' "$fired" "$agreed" "$sampled"
  return 0
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

main() {
  local sub
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 2
  fi
  sub="$1"
  shift
  case "$sub" in
  --help | -h | help)
    usage
    exit 0
    ;;
  classes | check | render | report) ;;
  *) die_usage "unknown subcommand: $sub" ;;
  esac

  command -v git >/dev/null 2>&1 || die_usage "git is required but is not on PATH"
  WORKDIR=$(mktemp -d) || die_usage "cannot create a temporary directory"
  resolve_repo_root

  case "$sub" in
  classes) cmd_classes "$@" ;;
  check) cmd_check "$@" ;;
  render) cmd_render "$@" ;;
  report) cmd_report "$@" ;;
  *) die_usage "unknown subcommand: $sub" ;;
  esac
}

main "$@"
