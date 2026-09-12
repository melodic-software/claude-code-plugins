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
#   apply-rename.sh --regenerate-only [--config <json>] [--root <dir>]
#                   [--config <json>] [--root <dir>] [--dry-run]
#   apply-rename.sh --help
#
# Exit: 0 applied (or, with --dry-run, planned), 1 blocked (the reason and the
#       remedy on stderr; nothing was changed), 2 usage or a missing
#       prerequisite.
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
  printf '%s' "$planned" | awk -F'\t' 'NF==3 {print "WOULD-EDIT\t" $1 "\t" $2 "\t" $3}'
  printf 'WOULD-SKIP\t%d\n' "$skipped"
  printf 'WOULD-REGENERATE\t%s\n' "${TOUCHED_GENERATED# }"
  exit 0
fi

# --- apply -------------------------------------------------------------------

set_status() {
  tmp="$ARTIFACT.tmp.$$"
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

set_status applying

# Every OTHER record whose sites live in the file being moved now points at a
# path that no longer exists. Rewriting those site rows in place is what lets a
# tree whose renamed files cite each other be applied one finding at a time: the
# next apply finds its sites where the plan says they are.
remap_sites() {
  tmp="$ARTIFACT.tmp.$$"
  awk -v old="| \`$OLD\` |" -v new="| \`$NEW\` |" '
    index($0, old) == 1 { sub(/^\| `[^`]*` \|/, new); print; next }
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
  if ! awk -v ln="$lineno" -v from="$from" -v to="$to" '
    NR == ln {
      n = 0
      out = ""
      rest = $0
      while ((p = index(rest, from)) > 0) {
        out = out substr(rest, 1, p - 1) to
        rest = substr(rest, p + length(from))
        n++
      }
      $0 = out rest
      if (n == 0) { print "ZERO\t" NR > "/dev/stderr" }
    }
    { print }
  ' "$ROOT/$file" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    blocked "cannot rewrite $file:$lineno"
  fi
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
