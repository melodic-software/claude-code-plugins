#!/usr/bin/env bash
# Keep each plugin's CHANGELOG.md honest against its manifest version.
#
#   scripts/check-changelog-parity.sh --check             fail if a versioned
#                                                         plugin has no sibling
#                                                         CHANGELOG.md
#   scripts/check-changelog-parity.sh --check-bump <ref>  fail if a plugin's
#                                                         manifest version
#                                                         changed vs <ref> but
#                                                         its CHANGELOG.md does
#                                                         not ADD a `## [<v>]`
#                                                         entry for the new
#                                                         version (present at
#                                                         head, absent at <ref>)
#
# Two complementary gaps the same audit surfaced:
#   * --check is the static repo-wide invariant: a plugins/<name>/.claude-plugin/
#     plugin.json carrying a `version` must ship a plugins/<name>/CHANGELOG.md.
#     It catches a plugin that has bumped versions but never kept a changelog at
#     all (autonomy shipped 5 minor bumps with none).
#   * --check-bump is the go-forward PR discipline: a version change must ADD a
#     `## [<version>]` entry for the new version — present in the plugin's
#     CHANGELOG.md at head AND absent from it at <ref>. Two failure classes the
#     gate must not conflate: (a) checking for the version's own entry, not
#     merely that the file was touched, so an unrelated edit — whitespace, the
#     title, an old release — cannot satisfy the gate; (b) requiring the entry
#     to be newly added, so reusing a heading that already existed at <ref>
#     (a bump with no fresh release note) cannot satisfy it either. An entry
#     documented as `## <version>` (no brackets) is a separate FORMAT failure,
#     reported as such rather than as undocumented. It applies to EVERY plugin,
#     grandfathered or not — the moment a debt-listed plugin bumps again it must
#     start its changelog.
#
# Existing "versioned but changelog-less" debt is grandfathered by plugin NAME in
# scripts/changelog-parity-baseline.txt (same stale-guarded idiom as
# scripts/orphaned-fixtures-baseline.txt): --check exempts a listed plugin but
# fails on a STALE entry — one that now has a CHANGELOG.md (or no version) — so
# the exemption cannot outlive the debt. The baseline never relaxes --check-bump.
#
# Fail-closed: a versioned plugin with neither a CHANGELOG.md nor a baseline
# entry fails. CHANGELOG_PARITY_BASELINE overrides the baseline path (test
# injection).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

BASELINE="${CHANGELOG_PARITY_BASELINE:-scripts/changelog-parity-baseline.txt}"

mode="${1:-}"
case "$mode" in
--check | --check-bump) ;;
*)
  echo "usage: $(basename "$0") [--check | --check-bump <base-ref>]" >&2
  exit 2
  ;;
esac

# Grandfathered plugin names (static-check exemptions).
declare -A grandfathered
if [[ -f "$BASELINE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    grandfathered["$line"]=1
  done <"$BASELINE"
fi

manifests=(plugins/*/.claude-plugin/plugin.json)
if [[ ! -e "${manifests[0]}" ]]; then
  echo "error: no plugin manifests found under plugins/*/.claude-plugin/" >&2
  exit 2
fi

version_of() { jq -r '.version // empty' "$1" 2>/dev/null; }

if [[ "$mode" == "--check" ]]; then
  declare -A saw_debt
  missing=0
  for manifest in "${manifests[@]}"; do
    plugin_dir="${manifest%/.claude-plugin/plugin.json}"
    name="${plugin_dir##*/}"
    [[ -n "$(version_of "$manifest")" ]] || continue
    if [[ -f "$plugin_dir/CHANGELOG.md" ]]; then
      if [[ -n "${grandfathered[$name]:-}" ]]; then
        echo "STALE BASELINE: '$name' in $BASELINE now has a CHANGELOG.md — remove it." >&2
        missing=$((missing + 1))
        # Mark handled so the second stale-scan loop does not re-report it.
        saw_debt["$name"]=1
      fi
      continue
    fi
    if [[ -n "${grandfathered[$name]:-}" ]]; then
      saw_debt["$name"]=1
      continue
    fi
    echo "MISSING CHANGELOG: $plugin_dir carries a versioned $manifest but no $plugin_dir/CHANGELOG.md." >&2
    echo "  Add $plugin_dir/CHANGELOG.md, or grandfather '$name' in $BASELINE with its owning issue." >&2
    missing=$((missing + 1))
  done
  # A baseline name that matches no versioned-and-changelog-less plugin is stale.
  for name in "${!grandfathered[@]}"; do
    if [[ -z "${saw_debt[$name]:-}" ]]; then
      echo "STALE BASELINE: '$name' in $BASELINE no longer names a versioned plugin missing a CHANGELOG.md — remove it." >&2
      missing=$((missing + 1))
    fi
  done
  if ((missing > 0)); then
    exit 1
  fi
  echo "Every versioned plugin has a CHANGELOG.md (or a stale-guarded baseline entry)."
  exit 0
fi

# --check-bump mode
if [[ -z "${2:-}" ]]; then
  echo "usage: $(basename "$0") --check-bump <base-ref>" >&2
  exit 2
fi
base="$2"
if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "check-changelog-parity: base ref '$base' is not a resolvable commit." >&2
  exit 2
fi

# Scope the bump check to plugins THIS change set actually touched. A stale
# branch whose base ref (main) has advanced an UNTOUCHED plugin's version must
# not red-line on it and force a merge-from-main — the untouched plugin is not in
# the PR's own diff. Three-dot base...HEAD is diff(merge-base(base,HEAD), HEAD),
# i.e. only the commits unique to this branch, so a version main advanced after
# the branch forked is excluded whether CI checks out the PR head or the
# auto-merge commit. The filter keys on the MANIFEST path, not the plugin root:
# the gate compares .version in exactly plugins/<name>/.claude-plugin/plugin.json,
# so a version bump is definitionally a change to that file — manifest-scoping is
# precisely "plugins whose version this change set could have changed," and (unlike
# plugin-root scoping) a cosmetic touch elsewhere under the plugin dir cannot pull
# a main-only advance back into scope.
declare -A bumped_candidate
# Read the change set's touched paths via COMMAND substitution, not process
# substitution: this gate is a required CI merge check, and a git failure here
# must fail loud, never silently pass. Process substitution swallows git's exit
# status, so a diff that genuinely cannot be computed (e.g. no common ancestor
# between "$base" and HEAD -> "fatal: no merge base", exit 128) would yield an
# empty result, skip every plugin's bumped_candidate guard below, and let the
# gate exit 0 without checking anything (fail-open). Command substitution
# propagates that non-zero status so the guard fires. A legitimate empty diff
# ("zero files changed") succeeds with empty output and correctly leaves
# bumped_candidate empty.
if ! diff_paths="$(git diff --name-only "$base...HEAD")"; then
  echo "check-changelog-parity: 'git diff --name-only $base...HEAD' failed (no common ancestor between '$base' and HEAD, or history not fetched deeply enough); refusing to pass without checking." >&2
  exit 2
fi
while IFS= read -r path; do
  case "$path" in
  plugins/*/.claude-plugin/plugin.json)
    rest="${path#plugins/}"
    bumped_candidate["${rest%%/*}"]=1
    ;;
  *) ;;
  esac
done <<<"$diff_paths"

undocumented=0
malformed=0
preexisting=0
for manifest in "${manifests[@]}"; do
  plugin_dir="${manifest%/.claude-plugin/plugin.json}"
  name="${plugin_dir##*/}"
  changelog="$plugin_dir/CHANGELOG.md"

  # Only plugins whose manifest this change set touched are in scope (see the
  # bumped_candidate note above); a plugin main advanced but this branch never
  # touched is not the PR's to document.
  [[ -n "${bumped_candidate[$name]:-}" ]] || continue

  base_version="$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
  # Absent at base => new plugin in this change set; the static --check owns
  # whether its initial CHANGELOG.md exists, not the bump gate.
  [[ -n "$base_version" ]] || continue
  head_version="$(version_of "$manifest")"
  [[ "$head_version" != "$base_version" ]] || continue

  # Require the bumped version's own entry at head, not merely that the file
  # changed: an unrelated edit (whitespace, title, an old release) must not
  # satisfy the gate. The match is a FIXED-STRING heading anchored to line
  # start (awk index()==1) and OUTSIDE fenced code, so the version string
  # appearing in prose, an indented line, or a fenced example never satisfies —
  # or falsely pre-exists — the release entry, and SemVer metacharacters
  # (1.0.1+build.1) never leak into a regex. Fence tracking follows CommonMark:
  # a fence line is a run of >=3 backticks or tildes indented at most three
  # SPACES (four-plus, or a tab, is indented code); an opening backtick fence
  # rejects an info string containing a backtick; a CLOSE requires the same
  # delimiter char, a run at least as long as the opener, and nothing but
  # whitespace after it — so a ~~~ line, a ```not-a-close line, or an indented
  # would-be closer inside a ``` block never prematurely re-opens the heading.
  # HTML raw blocks are tracked alongside fences: a heading inside a multi-line
  # <!-- --> comment is not rendered Markdown, so it neither satisfies nor
  # pre-exists the release entry. A same-line "<!-- ## [x] -->" can never match
  # anyway (the heading is not at column one). Comment markers inside fenced
  # code are content; fence markers inside a comment are suppressed.
  heading="## [${head_version}]"
  has_heading() {
    awk -v h="$heading" '
      {
        if (!infence && inhtml) {
          p = index($0, "-->")
          if (p == 0) next
          inhtml = 0
          rem = substr($0, p + 3)
          while ((q = index(rem, "<!--")) > 0) {
            rem = substr(rem, q + 4)
            r = index(rem, "-->")
            if (r == 0) { inhtml = 1; break }
            rem = substr(rem, r + 3)
          }
          next
        }
        if (match($0, /^ {0,3}`+/) || match($0, /^ {0,3}~+/)) {
          seg = substr($0, RSTART, RLENGTH)
          sub(/^ +/, "", seg)
          mchar = substr(seg, 1, 1)
          mlen = length(seg)
          rest = substr($0, RSTART + RLENGTH)
          if (mlen >= 3) {
            if (!infence) {
              # opening fence; a backtick info string must not contain a backtick
              if (!(mchar == "`" && rest ~ /`/)) { infence = 1; fchar = mchar; flen = mlen; next }
            } else if (mchar == fchar && mlen >= flen && rest ~ /^[ \t]*$/) {
              infence = 0; next
            }
          }
        }
        if (!infence && index($0, h) == 1) { found = 1; exit }
        if (!infence) {
          rem = $0
          while ((q = index(rem, "<!--")) > 0) {
            rem = substr(rem, q + 4)
            r = index(rem, "-->")
            if (r == 0) { inhtml = 1; break }
            rem = substr(rem, r + 3)
          }
        }
      }
      END { exit !found }
    '
  }
  if [[ -f "$changelog" ]] && has_heading <"$changelog"; then
    # The release entry must be ADDED by this change set, not merely present:
    # a heading that already existed in the changelog at $base means the bump
    # reused a pre-existing entry and shipped no new release note. Require it
    # absent from the base changelog. (git show fails for a changelog that is
    # new at $base -> empty -> counts as absent, which is correct: it was added
    # here.)
    if git show "$base:$changelog" 2>/dev/null | has_heading; then
      echo "PRE-EXISTING CHANGELOG ENTRY: $name bumped $base_version -> $head_version but '## [$head_version]' already existed in $changelog at $base; add the release entry in this change set." >&2
      preexisting=$((preexisting + 1))
    fi
    continue
  fi

  # Split the failure: a heading that names the version but omits the brackets
  # (## <version>) is a FORMAT error the author can fix in place, not a missing
  # release. Escape ALL ERE metacharacters (SemVer allows + in build metadata),
  # not just dots.
  # shellcheck disable=SC2016  # single quotes are deliberate: $ is an ERE metachar being escaped, not a shell expansion
  esc="$(printf '%s' "$head_version" | sed -E 's/[][\\.|$(){}?+*^]/\\&/g')"
  if found="$([[ -f "$changelog" ]] && grep -m1 -E "^##[[:space:]]+${esc}([[:space:]]|\$)" "$changelog")"; then
    echo "CHANGELOG FORMAT: $name $head_version is documented as '${found}' but must use the bracketed Keep-a-Changelog heading '## [$head_version]'." >&2
    malformed=$((malformed + 1))
  else
    echo "UNDOCUMENTED BUMP: $name went $base_version -> $head_version but $changelog has no '## [$head_version]' entry at head." >&2
    undocumented=$((undocumented + 1))
  fi
done

if ((undocumented > 0 || malformed > 0 || preexisting > 0)); then
  ((undocumented > 0)) && echo "Add a '## [<version>]' entry for every plugin whose version changed." >&2
  ((malformed > 0)) && echo "Convert unbracketed changelog headings to the '## [<version>]' Keep-a-Changelog form." >&2
  ((preexisting > 0)) && echo "Add the bumped version's '## [<version>]' entry in this change set; it must be absent from the base changelog, not merely present at head." >&2
  exit 1
fi
echo "Every plugin whose version changed vs $base has a '## [<version>]' CHANGELOG.md entry."
