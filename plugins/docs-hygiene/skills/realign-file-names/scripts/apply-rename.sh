#!/usr/bin/env bash
# apply-rename.sh — execute ONE accepted rename from a file-name findings plan.
#
# One finding per invocation. The plan's record is the instruction set: this
# script never re-inventories the tree, never re-derives a form, a tier, or an
# action, and never decides which site to touch. It applies what the record says
# after proving the record still describes the tree.
#
# THE DRIFT GUARD IS PER SITE, NOT PER FILE. A whole-file content hash cannot be
# the test: in any real doc tree the renamed files cite each other, so applying
# the first accepted rename edits a file another finding names, and a file-level
# guard would block every rename after the first. What is checked instead is
# exact and narrow: the old path is still in the INDEX, and each site's recorded
# line still carries the old name. A site that no longer matches is reported and
# skipped; a substitution that would hit zero times is reported, never a silent
# no-op.
#
# EXISTENCE IS ASKED OF THE INDEX, NEVER THE FILESYSTEM. On a case-insensitive
# checkout `[[ -e docs/foo.md ]]` is true while only `docs/Foo.md` exists, so a
# filesystem test would refuse every case-only rename on the platforms the whole
# rule exists to protect.
#
# THE WRITE-BACK PRESERVES THE INODE. Edits go through a temp file and are
# written back with `cat`, never moved over the target: `mv` replaces the inode
# and drops the executable bit, and a reference sweep across a real repository
# edits hook scripts and gate scripts that stop launching the moment they lose
# it.
#
# AN INTERRUPTED RUN RESUMES. `applying` is written before `git mv` and cleared
# after the last edit, so a run that died between them is resumed rather than
# blocked: the maps are idempotent, and an old path that is gone while the new
# path is present is a half-finished apply, not a drifted tree.
#
# Every single-quoted `${...}` below is a jq or awk program argument, never a
# shell expansion.
# shellcheck disable=SC2016
#
# Usage:
#   apply-rename.sh --artifact <plan.md> --id <FN-xxxxxxxx>
#                   [--config <json>] [--root <dir>] [--dry-run]
#   apply-rename.sh --regenerate-only [--config <json>] [--root <dir>]
#   apply-rename.sh --help
#
# Exit: 0 applied (or, with --dry-run, planned), 1 blocked (the reason and the
#       remedy on stderr; the TREE is unchanged, and a record the operator had
#       accepted is marked `blocked` so the decision does not read as still
#       queued), 2 usage or a missing prerequisite.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"

die() {
  printf 'apply-rename: %s\n' "$1" >&2
  exit "${2:-2}"
}

blocked() {
  printf 'apply-rename: blocked: %s\n' "$1" >&2
  exit 1
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

# Every temp file this run creates is named `*.tmp.$$` or `*.err.$$` beside its
# target, so a run killed mid-edit does not leave clutter inside the consumer's
# worktree for the resume to trip over.
TEMPS=()
# shellcheck disable=SC2329  # invoked by the EXIT trap below, not by name
cleanup() {
  [[ ${#TEMPS[@]} -gt 0 ]] && rm -f "${TEMPS[@]}"
  return 0
}
trap cleanup EXIT

ARTIFACT=""
ID=""
CONFIG_FILE=""
ROOT=""
DRY_RUN=0
REGEN_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --artifact)
    shift
    [[ $# -gt 0 ]] || die "--artifact needs a file"
    ARTIFACT="$1"
    ;;
  --id)
    shift
    [[ $# -gt 0 ]] || die "--id needs a finding id"
    ID="$1"
    ;;
  --config)
    shift
    [[ $# -gt 0 ]] || die "--config needs a file"
    CONFIG_FILE="$1"
    ;;
  --root)
    shift
    [[ $# -gt 0 ]] || die "--root needs a directory"
    ROOT="$1"
    ;;
  --dry-run)
    DRY_RUN=1
    ;;
  --regenerate-only)
    REGEN_ONLY=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument '$1'"
    ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || die "git is required and is not on PATH"
command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"
if [[ "$REGEN_ONLY" -eq 0 ]]; then
  [[ -n "$ARTIFACT" ]] || die "--artifact is required"
  [[ -n "$ID" ]] || die "--id is required"
  [[ -r "$ARTIFACT" ]] || die "cannot read the plan at $ARTIFACT"
fi

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "'$ROOT' is not a git repository"

# --- configuration (for the generated set and its regenerators) ---------------

if [[ -n "$CONFIG_FILE" ]]; then
  [[ -r "$CONFIG_FILE" ]] || die "cannot read the configuration at $CONFIG_FILE"
  CONFIG="$(jq -e . "$CONFIG_FILE" 2>/dev/null | tr -d '\r')" || die "the configuration at $CONFIG_FILE is not valid JSON"
else
  [[ -f "$RESOLVER" ]] || die "resolver missing at $RESOLVER"
  CONFIG="$(bash "$RESOLVER" resolve --root "$ROOT")" || exit 2
fi

cfg() {
  printf '%s' "$CONFIG" | jq -r "$1" 2>/dev/null | tr -d '\r'
}

GENERATED_PATHS=" $(cfg '.file_names.generated[].path' | tr '\n' ' ')"

# `--regenerate-only` is the closing pass of a realign run. A generated record is
# rebuilt per finding only when the plan recorded a site inside it, so the LAST
# rename of a run can leave a derived sample or index stale: the record named no
# site for a file that did not appear in it at audit time. Running every declared
# regenerator once at the end settles that, and is a no-op on a tree already
# current.
if [[ "$REGEN_ONLY" -eq 1 ]]; then
  ran=""
  while IFS="$(printf '\t')" read -r gpath gcmd; do
    [[ -n "$gpath" ]] || continue
    [[ -n "$gcmd" && "$gcmd" != "null" ]] || die "generated file '$gpath' declares no regenerate command"
    (cd "$ROOT" && eval "$gcmd") >/dev/null 2>&1 || die "the regenerator for '$gpath' failed" 1
    ran="$ran $gpath"
  done <<EOF
$(printf '%s' "$CONFIG" | jq -r '.file_names.generated[] | [.path, (.regenerate // "")] | @tsv')
EOF
  printf 'REGENERATED\t%s\n' "${ran# }"
  exit 0
fi

# --- the record --------------------------------------------------------------

PLAN_BRANCH="$(awk -F': ' '/^branch: /{print $2; exit}' "$ARTIFACT")"
NOW_BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null)"
if [[ -z "$NOW_BRANCH" ]]; then
  NOW_BRANCH="detached-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf unknown)"
fi
[[ "$PLAN_BRANCH" == "$NOW_BRANCH" ]] ||
  blocked "the plan was written on branch '$PLAN_BRANCH' and this checkout is on '$NOW_BRANCH'; re-audit here"

# THE ID IS VALIDATED BEFORE IT REACHES A PATTERN. It is interpolated into awk
# regexes below, so an id carrying regex metacharacters would select more than
# one record: `--id 'FN-.*'` would take its paths from the first match while
# absorbing every record's site rows, and one acceptance would then move one
# file and edit the sites of findings the operator never saw.
[[ "$ID" =~ ^FN-[0-9a-f]+$ ]] ||
  die "--id must be a finding id of the form FN-xxxxxxxx, not '$ID'"

RECORD="$(awk -v id="$ID" '
  $0 ~ "^### " id " " { inrec = 1; print; next }
  inrec && /^### FN-/ { exit }
  inrec { print }
' "$ARTIFACT")"
[[ -n "$RECORD" ]] || blocked "the plan carries no finding '$ID'"

OLD="$(printf '%s' "$RECORD" | sed -n "1s/^### $ID \`\\([^\`]*\\)\` to \`\\([^\`]*\\)\`.*/\\1/p")"
NEW="$(printf '%s' "$RECORD" | sed -n "1s/^### $ID \`\\([^\`]*\\)\` to \`\\([^\`]*\\)\`.*/\\2/p")"
STATUS="$(printf '%s' "$RECORD" | awk '/^- \*\*Status:\*\* /{print $3; exit}')"
[[ -n "$OLD" && -n "$NEW" ]] || blocked "cannot read the paths from record '$ID'"

case "$STATUS" in
pending | accepted | applying) ;;
applied) blocked "finding '$ID' is already applied" ;;
*) blocked "finding '$ID' is '$STATUS'; only a pending, accepted, or interrupted record is applied" ;;
esac

# A regenerator that does not resolve stops the run BEFORE anything moves. A
# tree with the file renamed and its generated record stale is worse than a tree
# nobody touched.
check_regenerators() {
  while IFS="$(printf '\t')" read -r gpath gcmd; do
    [[ -n "$gpath" ]] || continue
    case "$1" in
    *" $gpath "*) ;;
    *) continue ;;
    esac
    [[ -n "$gcmd" && "$gcmd" != "null" ]] || blocked "generated file '$gpath' declares no regenerate command"
    first="${gcmd%% *}"
    rest="${gcmd#* }"
    target="$first"
    case "$first" in
    bash | sh | zsh | python | python3 | node | ruby | perl | pwsh)
      [[ "$rest" != "$gcmd" ]] && target="${rest%% *}"
      ;;
    *) ;;
    esac
    command -v "$target" >/dev/null 2>&1 || [[ -e "$ROOT/$target" ]] ||
      blocked "the regenerator for '$gpath' resolves to nothing: $target"
  done <<EOF
$(printf '%s' "$CONFIG" | jq -r '.file_names.generated[] | [.path, (.regenerate // "")] | @tsv')
EOF
}

set_status() {
  tmp="$ARTIFACT.tmp.$$"
  TEMPS+=("$tmp")
  awk -v id="$ID" -v st="$1" '
    $0 ~ "^### " id " " { inrec = 1 }
    inrec && /^- \*\*Status:\*\* / && !done { print "- **Status:** " st; done = 1; next }
    /^### FN-/ && $2 != id { inrec = 0 }
    { print }
  ' "$ARTIFACT" >"$tmp" || {
    rm -f "$tmp"
    die "cannot update the plan"
  }
  cat "$tmp" >"$ARTIFACT" || {
    rm -f "$tmp"
    die "cannot write the plan"
  }
  rm -f "$tmp"
}

# --- the sites ---------------------------------------------------------------
#
# Every row of the record's site table, exactly as the audit classified it.

SITES="$(printf '%s' "$RECORD" | awk -F' *\\| *' '
  /^\| `/ {
    file = $2; gsub(/`/, "", file)
    print file "\t" $3 "\t" $4 "\t" $5 "\t" $6
  }
')"

OLD_BASE="${OLD##*/}"
NEW_BASE="${NEW##*/}"
OLD_STEM="${OLD_BASE%.*}"
NEW_STEM="${NEW_BASE%.*}"

# --- drift: is the record still true? ----------------------------------------

RESUMING=0
if git -C "$ROOT" ls-files --error-unmatch "$OLD" >/dev/null 2>&1; then
  :
elif [[ "$STATUS" == "applying" ]] && git -C "$ROOT" ls-files --error-unmatch "$NEW" >/dev/null 2>&1; then
  RESUMING=1
  printf 'apply-rename: resuming an interrupted apply of %s\n' "$ID" >&2
else
  # A record the operator ACCEPTED, whose file has since moved, is a decision
  # the tree can no longer carry out. Recording `blocked` is what keeps that
  # visible across the re-audit: a record left `accepted` reads as work still
  # queued. A `pending` record is left alone, because nothing was decided about
  # it yet and there is nothing to block.
  case "$STATUS" in
  accepted | applying) set_status blocked ;;
  *) ;;
  esac
  blocked "'$OLD' is no longer tracked at this root; the fix is a re-audit, not a guess"
fi

edits=0
skipped=0
zero_hits=0
planned=""

# The tier is read and discarded: the audit already turned it into the action,
# and re-deriving one here is exactly the second judgment this stage must not make.
while IFS="$(printf '\t')" read -r file lineno form _tier action; do
  [[ -n "$file" ]] || continue
  case "$action" in
  edit) ;;
  *)
    skipped=$((skipped + 1))
    continue
    ;;
  esac
  case "$GENERATED_PATHS" in
  *" $file "*)
    skipped=$((skipped + 1))
    continue
    ;;
  *) ;;
  esac
  [[ -f "$ROOT/$file" ]] || {
    printf 'apply-rename: site skipped, file gone: %s\n' "$file" >&2
    skipped=$((skipped + 1))
    continue
  }
  line="$(sed -n "${lineno}p" "$ROOT/$file" 2>/dev/null)"
  if [[ "$form" == "bare-stem" ]]; then
    needle="$OLD_STEM"
  else
    needle="$OLD_BASE"
  fi
  case "$line" in
  *"$needle"*)
    planned="$planned$file	$lineno	$form
"
    ;;
  *)
    # Either already applied (a resumed run) or drifted since the audit. Both
    # are reported; neither is edited blind.
    if [[ "$RESUMING" -eq 1 ]]; then
      skipped=$((skipped + 1))
    else
      printf 'apply-rename: site no longer carries the old name, skipped: %s:%s\n' "$file" "$lineno" >&2
      zero_hits=$((zero_hits + 1))
    fi
    ;;
  esac
done <<EOF
$SITES
EOF

TOUCHED_GENERATED=" $(printf '%s' "$SITES" | awk -F'\t' '$5=="regenerate" {print $1}' | sort -u | tr '\n' ' ')"
check_regenerators "$TOUCHED_GENERATED"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'DRY-RUN\t%s\t%s\t%s\n' "$ID" "$OLD" "$NEW"
  # The per-tier form table, straight from the record's own rows: one line per
  # tier naming which forms it would rewrite and which it would only list. An
  # operator reading a dry run is deciding about the citations, not the move,
  # and a flat edit list hides which tier each one belongs to.
  printf '%s' "$SITES" | awk -F'\t' '
    NF >= 5 {
      tier = $4
      seen[tier] = 1
      if ($5 == "edit" && !index(" " rewrites[tier] " ", " " $3 " ")) {
        rewrites[tier] = rewrites[tier] " " $3
      }
      if ($5 != "edit" && !index(" " listed[tier] " ", " " $3 " ")) {
        listed[tier] = listed[tier] " " $3
      }
    }
    END {
      for (t in seen) {
        printf "WOULD-TIER\t%s\trewrites: %s\tlists: %s\n", t,
          (rewrites[t] == "" ? "(none)" : substr(rewrites[t], 2)),
          (listed[t] == "" ? "(none)" : substr(listed[t], 2))
      }
    }
  ' | sort
  printf '%s' "$planned" | awk -F'\t' 'NF==3 {print "WOULD-EDIT\t" $1 "\t" $2 "\t" $3}'
  printf 'WOULD-SKIP\t%d\n' "$skipped"
  printf 'WOULD-REGENERATE\t%s\n' "$(printf '%s' "${TOUCHED_GENERATED# }" | sed 's/ *$//')"
  exit 0
fi

# --- apply -------------------------------------------------------------------

set_status applying

# Every OTHER record whose sites live in the file being moved now points at a
# path that no longer exists. Rewriting those site rows in place is what lets a
# tree whose renamed files cite each other be applied one finding at a time: the
# next apply finds its sites where the plan says they are.
remap_sites() {
  tmp="$ARTIFACT.tmp.$$"
  TEMPS+=("$tmp")
  # `new` is spliced in by length, never handed to `sub` as a replacement
  # string: there an `&` in a path component would expand to the whole match
  # and corrupt the row.
  awk -v old="| \`$OLD\` |" -v new="| \`$NEW\` |" '
    index($0, old) == 1 { print new substr($0, length(old) + 1); next }
    { print }
  ' "$ARTIFACT" >"$tmp" || {
    rm -f "$tmp"
    die "cannot remap the sibling site rows"
  }
  cat "$tmp" >"$ARTIFACT" || {
    rm -f "$tmp"
    die "cannot write the plan"
  }
  rm -f "$tmp"
}

if [[ "$RESUMING" -eq 0 ]]; then
  git -C "$ROOT" mv "$OLD" "$NEW" || blocked "git mv refused: $OLD to $NEW"
  remap_sites
  # A file that cites ITSELF has its own sites planned against the old path,
  # which the move just retired. `remap_sites` fixes the artifact's rows; this
  # fixes the rows already read into this run, so a self-citing offender does
  # not fail mid-apply with the tree half-changed.
  planned="$(printf '%s' "$planned" | awk -F'\t' -v old="$OLD" -v new="$NEW" '
    NF == 3 { if ($1 == old) { $1 = new } print $1 "\t" $2 "\t" $3 }
  ')
"
fi

# Each edit is written back through the SAME inode so mode bits and symlink
# targets survive; a sweep across a real repository edits executable scripts.
while IFS="$(printf '\t')" read -r file lineno form; do
  [[ -n "$file" ]] || continue
  if [[ "$form" == "bare-stem" ]]; then
    from="$OLD_STEM"
    to="$NEW_STEM"
  else
    from="$OLD_BASE"
    to="$NEW_BASE"
  fi
  tmp="$ROOT/$file.tmp.$$"
  # The substitution is LITERAL, never a regex. A basename carries dots
  # (`v1.2.schema.json`), and `gsub` would read each one as "any character" and
  # rewrite a line the audit never pointed at.
  #
  # A BARE STEM IS ANCHORED. The sweep only records a bare-stem site where the
  # characters around the stem are not name characters, so applying one
  # unanchored would undo that care: a line naming both `Alpha-One` and
  # `Alpha-One-notes.md` would have the second rewritten into a reference to a
  # file nobody renamed.
  anchored=0
  [[ "$form" == "bare-stem" ]] && anchored=1

  # AND A BASENAME IS REPLACED ONLY WHERE THE RECORDED FORM PUTS IT. One line
  # can carry the same basename twice in two shapes, and the tier may allow one
  # and freeze the other: a historical record reading
  # "links [Alpha](../Alpha-One.md) and names Alpha-One.md in prose" has an
  # editable `md-link` and a frozen `plain`, and replacing every occurrence
  # rewrites the narrative that `links-and-paths` exists to preserve.
  #
  # The test is the left context the sweep itself used to classify the form,
  # applied per occurrence rather than per line. This is not re-deriving the
  # form: the record names it, and this is where that name is honoured.
  # `plain` and `table-or-key` carry no context requirement, which is what
  # makes them the forms a frozen tier reports rather than edits.
  # All three reset every iteration. They are set per form in the branches
  # below, and a form that sets none would otherwise inherit the last one that
  # did, so a `plain` row following a `backtick-path` row would be anchored to a
  # code span it is not in and match nothing.
  prefix_re=''
  suffix_re=''
  exclude_prefix_re=''
  case "$form" in
  md-link) prefix_re='\]\([^)]*$' ;;
  # A code span is closed as well as opened, so both sides are checked: the
  # text before must open one and the text after must close it. The left test
  # alone would also match from a CLOSING backtick, and rewrite a link target
  # that follows a code span on the same line.
  backtick-path)
    prefix_re='`[^`]*$'
    suffix_re='^[^`]*`'
    ;;
  raw-url) prefix_re='raw\.githubusercontent\.com[^ )"'"'"']*$' ;;
  github-url) prefix_re='github\.com[^ )"'"'"']*$' ;;
  # `plain` is the residue form, so it is anchored by exclusion: it edits the
  # occurrences no shaped form covers. Without that, a `plain` row on a line
  # that also carries a link would rewrite the link target too, which is the
  # frozen half on a tier that allows prose and not paths.
  plain) exclude_prefix_re='(\]\([^)]*|`[^`]*|https?://[^ )"'"'"']*)$' ;;
  *) prefix_re='' ;;
  esac
  awkerr="$ROOT/$file.err.$$"
  TEMPS+=("$tmp" "$awkerr")
  if ! awk -v ln="$lineno" -v from="$from" -v to="$to" -v anchored="$anchored" \
    -v prefix_re="$prefix_re" -v suffix_re="$suffix_re" \
    -v exclude_prefix_re="$exclude_prefix_re" '
    function namechar(c) { return (c ~ /[A-Za-z0-9_-]/) }
    NR == ln {
      n = 0
      out = ""
      rest = $0
      # `seen` is the ORIGINAL text left of the cursor. `out` cannot stand in
      # for it: it already carries replacements, and a context test has to ask
      # about the line as the sweep read it.
      seen = ""
      while ((p = index(rest, from)) > 0) {
        before = (p > 1 ? substr(rest, p - 1, 1) : (length(seen) > 0 ? substr(seen, length(seen), 1) : ""))
        after = substr(rest, p + length(from), 1)
        ok = 1
        if (prefix_re != "" && (seen substr(rest, 1, p - 1)) !~ prefix_re) { ok = 0 }
        if (suffix_re != "" && substr(rest, p + length(from)) !~ suffix_re) { ok = 0 }
        if (exclude_prefix_re != "" && (seen substr(rest, 1, p - 1)) ~ exclude_prefix_re) { ok = 0 }
        if (anchored == 1) {
          if (before != "" && namechar(before)) { ok = 0 }
          if (after != "" && namechar(after)) { ok = 0 }
        }
        if (ok == 1) {
          out = out substr(rest, 1, p - 1) to
          n++
        } else {
          out = out substr(rest, 1, p - 1) from
        }
        seen = seen substr(rest, 1, p + length(from) - 1)
        rest = substr(rest, p + length(from))
      }
      $0 = out rest
      if (n == 0) { print "ZERO" > "/dev/stderr" }
    }
    { print }
  ' "$ROOT/$file" >"$tmp" 2>"$awkerr"; then
    rm -f "$tmp"
    msg="$(tr '\n' ' ' <"$awkerr")"
    rm -f "$awkerr"
    blocked "cannot rewrite $file:$lineno${msg:+: $msg}"
  fi
  # A recorded site that matched the pre-flight but substitutes zero times is
  # reported rather than silently written back unchanged.
  if grep -q '^ZERO$' "$awkerr" 2>/dev/null; then
    printf 'apply-rename: substitution hit zero times, left as found: %s:%s\n' "$file" "$lineno" >&2
    zero_hits=$((zero_hits + 1))
    rm -f "$tmp" "$awkerr"
    continue
  fi
  rm -f "$awkerr"
  cat "$tmp" >"$ROOT/$file" || {
    rm -f "$tmp"
    blocked "cannot write $file"
  }
  rm -f "$tmp"
  edits=$((edits + 1))
done <<EOF
$planned
EOF

# --- regenerate --------------------------------------------------------------

regenerated=""
while IFS="$(printf '\t')" read -r gpath gcmd; do
  [[ -n "$gpath" ]] || continue
  case "$TOUCHED_GENERATED" in
  *" $gpath "*) ;;
  *) continue ;;
  esac
  (cd "$ROOT" && eval "$gcmd") >/dev/null 2>&1 ||
    blocked "the regenerator for '$gpath' failed; the rename is applied and this record stays 'applying'"
  regenerated="$regenerated $gpath"
done <<EOF
$(printf '%s' "$CONFIG" | jq -r '.file_names.generated[] | [.path, (.regenerate // "")] | @tsv')
EOF

set_status applied

printf 'APPLIED\t%s\t%s\t%s\n' "$ID" "$OLD" "$NEW"
printf 'EDITED\t%d\n' "$edits"
printf 'SKIPPED\t%d\n' "$skipped"
printf 'DRIFTED\t%d\n' "$zero_hits"
printf 'REGENERATED\t%s\n' "${regenerated# }"
exit 0
