#!/usr/bin/env bash
# Every single-quoted `${...}` below is a jq or awk program argument, never a shell expansion.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"
# shellcheck source=../../../lib/load-config.sh
. "$SCRIPT_DIR/../../../lib/load-config.sh"

die() {
  printf 'apply-rename: %s\n' "$1" >&2
  exit "${2:-2}"
}

blocked() {
  printf 'apply-rename: blocked: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Execute one accepted rename from a file-name findings plan.
Usage: apply-rename.sh --artifact <plan.md> --id <FN-xxxxxxxx> [--config <json>] [--root <dir>] [--dry-run]
       apply-rename.sh --regenerate-only [--config <json>] [--root <dir>]
  --artifact <plan.md>  the findings plan
  --id <FN-xxxxxxxx>    the finding to apply
  --config <json>       a resolved configuration document
  --root <dir>          repository root
  --dry-run             plan without changing the tree
  --regenerate-only     only rerun the generated-file regenerators
Exit: 0 applied (or planned with --dry-run); 1 blocked (tree unchanged, reason on stderr);
2 usage or a missing prerequisite.
EOF
}

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
  --user-config)
    shift
    [[ $# -gt 0 ]] || die "--user-config needs a value"
    export CLAUDE_PLUGIN_OPTION_FILE_NAMES="$1"
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

resolve_git_root

load_config

generated_rows() {
  printf '%s' "$CONFIG" | jq -r '.file_names.generated[] | [.path, (.regenerate // "")] | @tsv'
}

GENERATED_PATHS=" $(cfg '.file_names.generated[].path' | tr '\n' ' ')"

if [[ "$REGEN_ONLY" -eq 1 ]]; then
  ran=""
  while IFS="$(printf '\t')" read -r gpath gcmd; do
    [[ -n "$gpath" ]] || continue
    [[ -n "$gcmd" && "$gcmd" != "null" ]] || die "generated file '$gpath' declares no regenerate command"
    (cd "$ROOT" && eval "$gcmd") >/dev/null 2>&1 || die "the regenerator for '$gpath' failed" 1
    ran="$ran $gpath"
  done <<EOF
$(generated_rows)
EOF
  printf 'REGENERATED\t%s\n' "${ran# }"
  exit 0
fi

PLAN_BRANCH="$(awk -F': ' '/^branch: /{print $2; exit}' "$ARTIFACT")"
NOW_BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null)"
if [[ -z "$NOW_BRANCH" ]]; then
  NOW_BRANCH="detached-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf unknown)"
fi
[[ "$PLAN_BRANCH" == "$NOW_BRANCH" ]] ||
  blocked "the plan was written on branch '$PLAN_BRANCH' and this checkout is on '$NOW_BRANCH'; re-audit here"

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
$(generated_rows)
EOF
}

rewrite_plan() {
  local what="$1" tmp="$ARTIFACT.tmp.$$"
  shift
  TEMPS+=("$tmp")
  awk "$@" "$ARTIFACT" >"$tmp" || die "cannot $what"
  cat "$tmp" >"$ARTIFACT" || die "cannot write the plan"
  rm -f "$tmp"
}

set_status() {
  rewrite_plan "update the plan" -v id="$ID" -v st="$1" '
    $0 ~ "^### " id " " { inrec = 1 }
    inrec && /^- \*\*Status:\*\* / && !done { print "- **Status:** " st; done = 1; next }
    /^### FN-/ && $2 != id { inrec = 0 }
    { print }
  '
}

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

RESUMING=0
if git -C "$ROOT" ls-files --error-unmatch "$OLD" >/dev/null 2>&1; then
  :
elif [[ "$STATUS" == "applying" ]] && git -C "$ROOT" ls-files --error-unmatch "$NEW" >/dev/null 2>&1; then
  RESUMING=1
  printf 'apply-rename: resuming an interrupted apply of %s\n' "$ID" >&2
else
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

set_status applying

remap_sites() {
  rewrite_plan "remap the sibling site rows" -v old="| \`$OLD\` |" -v new="| \`$NEW\` |" '
    index($0, old) == 1 { print new substr($0, length(old) + 1); next }
    { print }
  '
}

if [[ "$RESUMING" -eq 0 ]]; then
  git -C "$ROOT" mv "$OLD" "$NEW" || blocked "git mv refused: $OLD to $NEW"
  remap_sites
  planned="$(printf '%s' "$planned" | awk -F'\t' -v old="$OLD" -v new="$NEW" '
    NF == 3 { if ($1 == old) { $1 = new } print $1 "\t" $2 "\t" $3 }
  ')
"
fi

while IFS="$(printf '\t')" read -r file lineno form; do
  [[ -n "$file" ]] || continue
  if [[ "$form" == "bare-stem" ]]; then
    from="$OLD_STEM"
    to="$NEW_STEM"
    anchored=1
  else
    from="$OLD_BASE"
    to="$NEW_BASE"
    anchored=0
  fi
  tmp="$ROOT/$file.tmp.$$"

  prefix_re=''
  suffix_re=''
  exclude_prefix_re=''
  case "$form" in
  md-link) prefix_re='\]\([^)]*$' ;;
  backtick-path)
    prefix_re='`[^`]*$'
    suffix_re='^[^`]*`'
    ;;
  raw-url) prefix_re='raw\.githubusercontent\.com[^ )"'"'"']*$' ;;
  github-url) prefix_re='github\.com[^ )"'"'"']*$' ;;
  plain) exclude_prefix_re='(\]\([^)]*|`[^`]*|https?://[^ )"'"'"']*)$' ;;
  *) ;;
  esac
  awkerr="$ROOT/$file.err.$$"
  TEMPS+=("$tmp" "$awkerr")
  if ! AR_LN="$lineno" AR_FROM="$from" AR_TO="$to" AR_ANCHORED="$anchored" \
    AR_PREFIX_RE="$prefix_re" AR_SUFFIX_RE="$suffix_re" \
    AR_EXCLUDE_PREFIX_RE="$exclude_prefix_re" \
    awk '
    function namechar(c) { return (c ~ /[A-Za-z0-9_-]/) }
    BEGIN {
      ln = ENVIRON["AR_LN"] + 0
      from = ENVIRON["AR_FROM"]
      to = ENVIRON["AR_TO"]
      anchored = ENVIRON["AR_ANCHORED"] + 0
      prefix_re = ENVIRON["AR_PREFIX_RE"]
      suffix_re = ENVIRON["AR_SUFFIX_RE"]
      exclude_prefix_re = ENVIRON["AR_EXCLUDE_PREFIX_RE"]
    }
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
    msg="$(tr '\n' ' ' <"$awkerr")"
    blocked "cannot rewrite $file:$lineno${msg:+: $msg}"
  fi
  if grep -q '^ZERO$' "$awkerr" 2>/dev/null; then
    printf 'apply-rename: substitution hit zero times, left as found: %s:%s\n' "$file" "$lineno" >&2
    zero_hits=$((zero_hits + 1))
    rm -f "$tmp" "$awkerr"
    continue
  fi
  rm -f "$awkerr"
  cat "$tmp" >"$ROOT/$file" || blocked "cannot write $file"
  rm -f "$tmp"
  edits=$((edits + 1))
done <<EOF
$planned
EOF

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
$(generated_rows)
EOF

set_status applied

printf 'APPLIED\t%s\t%s\t%s\n' "$ID" "$OLD" "$NEW"
printf 'EDITED\t%d\n' "$edits"
printf 'SKIPPED\t%d\n' "$skipped"
printf 'DRIFTED\t%d\n' "$zero_hits"
printf 'REGENERATED\t%s\n' "${regenerated# }"
exit 0
