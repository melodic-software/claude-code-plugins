#!/usr/bin/env bash
# Keep each plugin's CHANGELOG.md honest against its manifest version.
#
#   scripts/check-changelog-parity.sh --check             fail if a versioned
#                                                         plugin has no sibling
#                                                         CHANGELOG.md, or that
#                                                         CHANGELOG's newest
#                                                         version heading is
#                                                         ABOVE the manifest
#                                                         `version`
#   scripts/check-changelog-parity.sh --check-bump <ref>  fail if a plugin's
#                                                         manifest version
#                                                         changed vs <ref> but
#                                                         its CHANGELOG.md does
#                                                         not ADD a `## [<v>]`
#                                                         entry for the new
#                                                         version (present at
#                                                         head, absent at <ref>),
#                                                         or the new version is
#                                                         not strictly greater
#                                                         than the one at <ref>
#   scripts/check-changelog-parity.sh --check-preserved <ref>
#                                                         fail if a changelog
#                                                         this change set touched
#                                                         DROPS a `## [<v>]`
#                                                         entry it carried at the
#                                                         fork point
#
# Three complementary gaps the same audit surfaced:
#   * --check is the static repo-wide invariant: a plugins/<name>/.claude-plugin/
#     plugin.json carrying a `version` must ship a plugins/<name>/CHANGELOG.md.
#     It catches a plugin that has bumped versions but never kept a changelog at
#     all (autonomy shipped 5 minor bumps with none). It also owns the REVERSE
#     direction of the parity pair: the changelog's newest version heading must
#     not exceed the manifest `version`. Nothing else covers that direction —
#     --check-bump fires only when the manifest version CHANGED, and
#     --check-order is satisfied by a correctly ordered heading list — so a
#     release note written ahead of its bump reaches main unseen, which is how
#     docs-hygiene shipped a `## [0.9.7]` the manifest went 0.9.6 -> 0.10.0
#     straight past (claude-code-plugins#2131). A manifest ABOVE the newest
#     heading stays legal: a bump with no consumer-visible change need not write
#     a release note.
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
#     start its changelog. A bump must also be MONOTONIC: strictly greater than
#     the version at <ref>, so a branch briefed against a stale base can neither
#     regress a version main has already moved past nor collide on a number
#     another change set claimed first (see the VERSION REGRESSION / VERSION
#     COLLISION checks below).
#   * --check-preserved is the other half of that PR discipline: the bump gate
#     polices what a change set ADDS and never what it REMOVES, so a released
#     section could be deleted — its notes absorbed into the new release — with
#     all three other modes green (claude-code-plugins#2264). --check-bump asks
#     only about the bumped version, --check-order reads a gap in the sequence as
#     correctly ordered, and --check compares the manifest against the changelog
#     MAXIMUM. The live producer is a concurrent bump: when two change sets bump
#     one plugin, git's conflict region tends to open BELOW the newest heading,
#     so a plausible merge-forward resolution writes both releases under a single
#     heading — or RELABELS the older heading to the new version — and leaves no
#     conflict marker behind to catch it. Deletion is never the correct treatment
#     of a yanked release either: Keep a Changelog keeps the heading and marks it
#     `## [0.0.5] - 2014-12-13 [YANKED]`, which this gate reads as preserved.
#     There is deliberately no exemption list. Both removals an author might
#     reach for have a legal non-deleting form: mark a yanked release [YANKED],
#     and ANNOTATE a note written against a version the manifest then skipped
#     rather than folding it into the release that shipped — the manifest cannot
#     be bumped back down onto the skipped number, which --check-bump would read
#     as a VERSION REGRESSION. The one deletion in this repo's recent history —
#     04822fc4 folding docs-hygiene's never-released `## [0.9.7]` into
#     `## [0.10.0]` while closing #2131 — is that second shape, and in the diff
#     it is indistinguishable from the absorption this gate exists to catch.
#     That is precisely why the remedy is to annotate the section rather than to
#     hand a required gate an off switch.
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
--check | --check-bump | --check-order | --check-preserved) ;;
*)
  echo "usage: $(basename "$0") [--check | --check-bump <base-ref> | --check-order | --check-preserved <base-ref>]" >&2
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

# --check-order: every changelog reads newest-first, with no version repeated.
#
# The gap this closes shipped: docs/conventions/loop-lane/CHANGELOG.md reached
# main reading 6.0.0 -> 3.1.1 -> 5.0.0 -> 4.0.0. The 3.1.1 entry was authored
# against 3.1.0 and merged after 4.0.0 had already landed, so its number was a
# regression the moment it merged. Nothing caught it: --check and --check-bump
# both reason about ONE version at a time, and neither reads the sequence. Any
# two branches that stage the same next version, or one that sits on a stale
# base, produce this — and the reviewer sees only their own diff hunk, never the
# resulting order.
#
# Convention changelogs are in scope precisely because that is where it shipped:
# they are unversioned by any manifest, so --check and --check-bump never look
# at them at all.

# A fixed-width key so a lexical comparison orders versions NUMERICALLY. Five
# digits per field is far beyond any version this repo will reach. Every caller —
# the shared heading extractor and both manifest-version paths — may carry a
# SemVer `+build`/`-prerelease` tail, which is stripped before the split to keep
# every field numeric. Stripping build metadata is SemVer-exact (it carries no
# precedence); pre-release ORDERING is deliberately not modeled — no manifest in
# this repo uses it — so an equal-core pre-release keys equal to its release.
version_sort_key() {
  local IFS='.'
  # shellcheck disable=SC2086  # deliberate word-split of the dotted version on IFS
  set -- ${1%%[+-]*}
  printf '%05d.%05d.%05d' "$((10#${1:-0}))" "$((10#${2:-0}))" "$((10#${3:-0}))"
}

# The lines of a markdown file that RENDER as markdown — everything outside
# fenced code blocks and multi-line HTML comments. Every mode reads a changelog
# through this, so a `## [1.2.3]` shown as an EXAMPLE can neither satisfy
# --check-bump's release-entry requirement nor masquerade as a real heading to
# --check and --check-order. One tracker, not three, so the modes cannot drift.
#
# Fence tracking follows CommonMark: a fence line is a run of >=3 backticks or
# tildes indented at most three SPACES (four-plus, or a tab, is indented code);
# an opening backtick fence rejects an info string containing a backtick; a CLOSE
# requires the same delimiter char, a run at least as long as the opener, and
# nothing but whitespace after it — so a ~~~ line, a ```not-a-close line, or an
# indented would-be closer inside a ``` block never prematurely re-opens the
# content. Comment markers inside fenced code are content; fence markers inside a
# comment are suppressed. A line that BEGINS inside a comment is suppressed whole
# even when the comment closes on it: what follows `-->` can never be a
# column-one heading anyway. Reads $1, or stdin when $1 is `-`.
rendered_lines() {
  awk '
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
      if (infence) next
      print
      rem = $0
      while ((q = index(rem, "<!--")) > 0) {
        rem = substr(rem, q + 4)
        r = index(rem, "-->")
        if (r == 0) { inhtml = 1; break }
        rem = substr(rem, r + 3)
      }
    }
  ' "$1"
}

# The version headings a changelog declares, in file order. Every heading form
# this repo actually uses: `## [1.2.3]` (plugins, Keep a Changelog),
# `## 1.2.3 — date` (conventions), and the two-component `## 1.2` several
# convention changelogs use. Requiring a patch component would make the gates
# built on this silently check NOTHING in those files — worse than not covering
# them, because the pass would be indistinguishable. The optional
# `+build`/`-prerelease` tail is admitted for the same reason: manifests and
# --check-bump both accept those forms, so dropping such a heading would leave
# exactly that class unchecked. version_sort_key strips the tail before
# comparing. Shared by --check-order and --check so the two directions of the
# parity pair cannot read a changelog differently.
changelog_versions() {
  rendered_lines "$1" |
    grep -oE '^##[[:space:]]+\[?[0-9]+\.[0-9]+(\.[0-9]+)?([+-][0-9A-Za-z][0-9A-Za-z.-]*)?\]?(\(|$|[[:space:]])' |
    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?([+-][0-9A-Za-z][0-9A-Za-z.-]*)?'
}

# Version headings present at the fork point but absent at head. Uses
# changelog_versions on both sides so plugin, convention, and two-component
# heading forms share one reader. Reads the base blob with command substitution
# (never process substitution) so a git failure fails closed. A changelog that
# is new at the fork point is a legitimate pass — probe with git cat-file -e
# first so "absent" is not conflated with "git failed".
missing_preserved_headings() {
  local merge_base="$1" changelog="$2"
  local base_body missing v
  declare -A head_seen

  if ! git cat-file -e "$merge_base:$changelog" 2>/dev/null; then
    return 0
  fi
  if ! base_body="$(git show "$merge_base:$changelog")"; then
    echo "check-changelog-parity: 'git show $merge_base:$changelog' failed; refusing to pass without checking." >&2
    return 2
  fi

  mapfile -t base_versions < <(printf '%s\n' "$base_body" | changelog_versions -)
  ((${#base_versions[@]} > 0)) || return 0

  mapfile -t head_versions < <(changelog_versions "$changelog")
  for v in "${head_versions[@]}"; do head_seen["$v"]=1; done

  missing=""
  for v in "${base_versions[@]}"; do
    [[ -n "${head_seen[$v]:-}" ]] && continue
    missing+="${missing:+$'\n'}$v"
  done
  if [[ -n "$missing" ]]; then
    printf '%s\n' "$missing"
  fi
  return 0
}

if [[ "$mode" == "--check-order" ]]; then
  changelogs=(plugins/*/CHANGELOG.md docs/conventions/*/CHANGELOG.md)
  misordered=0
  duplicated=0
  checked=0
  for changelog in "${changelogs[@]}"; do
    [[ -f "$changelog" ]] || continue
    checked=$((checked + 1))
    mapfile -t versions < <(changelog_versions "$changelog")
    ((${#versions[@]} > 1)) || continue

    dupes="$(printf '%s\n' "${versions[@]}" | sort | uniq -d)"
    if [[ -n "$dupes" ]]; then
      echo "DUPLICATE CHANGELOG VERSION: $changelog lists $(printf '%s' "$dupes" | tr '\n' ' ')more than once. Two branches almost certainly staged the same version; renumber one." >&2
      duplicated=$((duplicated + 1))
    fi

    # Compare on a zero-padded key rather than `sort -V`, which this repo's
    # shell-portability lint bans (it is a GNU extension). Padding each field to
    # a fixed width makes a plain lexical `>` numerically correct, so 10.0.0
    # still outranks 9.0.0.
    prev=""
    prev_key=""
    for v in "${versions[@]}"; do
      key="$(version_sort_key "$v")"
      if [[ -n "$prev_key" && "$key" > "$prev_key" ]]; then
        echo "MISORDERED CHANGELOG: $changelog is not newest-first — $v (below $prev). A version that merged after a higher one already landed is a regression; renumber it above the entry it followed." >&2
        misordered=$((misordered + 1))
        break
      fi
      prev="$v"
      prev_key="$key"
    done
  done

  if ((misordered > 0 || duplicated > 0)); then
    echo "Changelogs must read newest-first with no repeated version. Renumber against what is on the DEFAULT BRANCH, not against the base the branch was cut from." >&2
    exit 1
  fi
  echo "All $checked changelog(s) read newest-first with no duplicate versions."
  exit 0
fi

if [[ "$mode" == "--check" ]]; then
  declare -A saw_debt
  missing=0
  ahead=0
  for manifest in "${manifests[@]}"; do
    plugin_dir="${manifest%/.claude-plugin/plugin.json}"
    name="${plugin_dir##*/}"
    version="$(version_of "$manifest")"
    [[ -n "$version" ]] || continue
    if [[ -f "$plugin_dir/CHANGELOG.md" ]]; then
      if [[ -n "${grandfathered[$name]:-}" ]]; then
        echo "STALE BASELINE: '$name' in $BASELINE now has a CHANGELOG.md — remove it." >&2
        missing=$((missing + 1))
        # Mark handled so the second stale-scan loop does not re-report it.
        saw_debt["$name"]=1
      fi
      # Validated for EVERY plugin that keeps a changelog, not only one with a
      # heading to compare against: an uncomparable manifest version is a defect
      # in its own right, and --check-bump refuses it unconditionally for every
      # plugin in its scope. Gating it on an unrelated precondition would let a
      # malformed version ride through behind a not-yet-written release note.
      if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-].*)?$ ]]; then
        echo "check-changelog-parity: $name carries a non-SemVer manifest version '$version'; refusing to pass without a comparable version." >&2
        exit 2
      fi
      # Reverse parity: the newest heading must not outrun the manifest. Only the
      # NEWEST is compared — an older heading naming a version the manifest never
      # took is invisible from the tree alone, but it can only get there by first
      # being the newest, which this catches in the change set that writes it.
      mapfile -t headings < <(changelog_versions "$plugin_dir/CHANGELOG.md")
      newest="${headings[0]:-}"
      if [[ -n "$newest" && "$(version_sort_key "$newest")" > "$(version_sort_key "$version")" ]]; then
        echo "CHANGELOG AHEAD OF MANIFEST: $plugin_dir/CHANGELOG.md documents $newest but $manifest carries $version." >&2
        echo "  Bump the manifest to $newest, or fold that entry into the version that actually ships." >&2
        ahead=$((ahead + 1))
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
  if ((missing > 0 || ahead > 0)); then
    ((ahead > 0)) && echo "A changelog entry must not name a version the manifest has not reached; the manifest may sit above the newest heading, never below it." >&2
    exit 1
  fi
  echo "Every versioned plugin has a CHANGELOG.md (or a stale-guarded baseline entry), and none documents a version above its manifest."
  exit 0
fi

# ===================== the two diff modes: shared prologue ==================
# --check-bump and --check-preserved both reason about what THIS change set did
# to a file, so both need the same three things resolved the same way: the base
# ref, the fork point, and the change set's own touched paths. Resolved once so
# the two modes cannot drift into reading the diff differently.
if [[ -z "${2:-}" ]]; then
  echo "usage: $(basename "$0") $mode <base-ref>" >&2
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
# the PR's own diff. Diffing fork point to branch tip (resolved below) covers
# only the commits unique to this branch, so a version main advanced after the
# branch forked is excluded whether CI checks out the PR head or the
# auto-merge commit. The filter keys on the MANIFEST path, not the plugin root:
# the gate compares .version in exactly plugins/<name>/.claude-plugin/plugin.json,
# so a version bump is definitionally a change to that file — manifest-scoping is
# precisely "plugins whose version this change set could have changed," and (unlike
# plugin-root scoping) a cosmetic touch elsewhere under the plugin dir cannot pull
# a main-only advance back into scope.
declare -A bumped_candidate
# The changelogs this change set touched, in `git diff` order, for
# --check-preserved. Same two roots --check-order sweeps.
touched_changelogs=()
declare -A seen_changelog
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
# The change set is THIS BRANCH's own commits: fork point to branch tip. On a
# pull_request checkout HEAD is the event's synthetic merge commit (parent 1 =
# base tip, parent 2 = the branch's own tip); diffing or merge-basing against
# that commit degenerates to the base tip, which hides a same-number collision
# twice over — the manifest byte-matches the base tip (so it never becomes a
# candidate) and fork_version equals head_version (so it reads as not-bumped).
# When HEAD has that shape, use the branch's own tip.
head_commit=HEAD
if git rev-parse -q --verify 'HEAD^2' >/dev/null 2>&1 && git merge-base --is-ancestor 'HEAD^1' "$base" 2>/dev/null; then
  head_commit='HEAD^2'
fi
if ! merge_base="$(git merge-base "$base" "$head_commit")"; then
  echo "check-changelog-parity: 'git merge-base $base $head_commit' failed (no common ancestor, or history not fetched deeply enough); refusing to pass without checking." >&2
  exit 2
fi
if ! diff_paths="$(git diff --name-only "$merge_base" "$head_commit")"; then
  echo "check-changelog-parity: 'git diff --name-only $merge_base $head_commit' failed; refusing to pass without checking." >&2
  exit 2
fi
while IFS= read -r path; do
  case "$path" in
  plugins/*/.claude-plugin/plugin.json)
    rest="${path#plugins/}"
    bumped_candidate["${rest%%/*}"]=1
    ;;
  plugins/*/CHANGELOG.md | docs/conventions/*/CHANGELOG.md)
    # A `case` glob's `*` spans `/`, so the depth is re-checked explicitly: only
    # a changelog exactly one directory below a root is in scope, never one
    # nested deeper inside a plugin.
    rest="${path#plugins/}"
    rest="${rest#docs/conventions/}"
    if [[ "$rest" == "${rest%%/*}/CHANGELOG.md" && -z "${seen_changelog[$path]:-}" ]]; then
      seen_changelog["$path"]=1
      touched_changelogs+=("$path")
    fi
    ;;
  *) ;;
  esac
done <<<"$diff_paths"

# ============================ --check-preserved =============================
# Every version heading a touched changelog carried at the FORK POINT must still
# be there at head. Compared against the fork point, never the base TIP: a branch
# that has not integrated main would read every heading main added after the fork
# as "deleted" — a false positive on a required gate. The two semantics coincide
# in the scenario this catches, because absorbing a section requires having
# merged main forward in the first place (that is what opens the conflict
# region), and once the base is an ancestor of head the fork point IS the base
# tip.
#
# Matching is on the VERSION the heading names, via the shared extractor, so a
# heading reformatted between the `## [1.2.3]` and `## 1.2.3 — date` forms still
# reads as preserved (that is --check-bump's FORMAT concern, not a deletion), and
# a yanked release marked `## [0.0.5] - 2014-12-13 [YANKED]` keeps its version in
# the list exactly as Keep a Changelog intends.
#
# Reading discipline: a git read is COMMAND substitution with its status checked
# (a failed git read must never read as "nothing to preserve" and pass), while
# the heading extraction's status is deliberately ignored — `grep -oE` exits 1 on
# a changelog with no version headings at all, which is not an error. No reader
# in this path exits early on its input, so no writer can take SIGPIPE under
# pipefail (see the has_heading note in --check-bump).
if [[ "$mode" == "--check-preserved" ]]; then
  deleted=0
  compared=0
  declare -A head_seen
  for changelog in "${touched_changelogs[@]}"; do
    # Absent at the fork point => added by this change set; nothing to preserve.
    # `git ls-tree` is the probe that separates that from a git invocation which
    # genuinely FAILED: a path missing from the tree is exit 0 with EMPTY output,
    # an unusable rev is a non-zero exit. (`git cat-file -e` cannot make that
    # distinction — it exits 128 for both, so a change set ADDING a changelog
    # would fail the gate.) A failure must never read as "nothing to preserve".
    if ! base_listing="$(git ls-tree -r --name-only "$merge_base" -- "$changelog")"; then
      echo "check-changelog-parity: 'git ls-tree -r --name-only $merge_base -- $changelog' failed; refusing to pass without checking." >&2
      exit 2
    fi
    [[ -n "$base_listing" ]] || continue
    if ! base_body="$(git show "$merge_base:$changelog")"; then
      echo "check-changelog-parity: 'git show $merge_base:$changelog' failed; refusing to pass without checking." >&2
      exit 2
    fi
    mapfile -t base_versions < <(printf '%s\n' "$base_body" | changelog_versions -)
    ((${#base_versions[@]} > 0)) || continue

    head_versions=()
    if [[ -f "$changelog" ]]; then
      mapfile -t head_versions < <(changelog_versions "$changelog")
    elif [[ ! -d "${changelog%/CHANGELOG.md}" ]]; then
      # The whole plugin/convention directory went with it — a removal, not an
      # absorbed section. A rename lands here too: the old path's directory is
      # gone, and the new path is new at the fork point (skipped above). A
      # directory rename can therefore carry an absorption past this gate — a
      # known boundary, not an oversight: renaming a plugin is a reviewed
      # identity change, and --check-bump's manifest scoping has the same
      # property. `--no-renames` would not close it, since the old path would
      # still land in this branch.
      continue
    fi

    head_seen=()
    if ((${#head_versions[@]} > 0)); then
      for v in "${head_versions[@]}"; do head_seen["$v"]=1; done
    fi
    missing=""
    for v in "${base_versions[@]}"; do
      [[ -n "${head_seen[$v]:-}" ]] && continue
      head_seen["$v"]=1 # a version repeated at base is reported once
      missing="${missing}${missing:+ }$v"
    done
    compared=$((compared + ${#base_versions[@]}))

    if [[ -n "$missing" ]]; then
      echo "DELETED CHANGELOG ENTRY: $changelog documented $missing at the fork point but no longer does." >&2
      # Two different failures reach one counter, and they need different
      # remediation: telling an author whose whole file is gone to restore a
      # heading "above the entry that replaced it" names an entry that does not
      # exist.
      if [[ -f "$changelog" ]]; then
        echo "  A released section's heading vanished. The usual cause is a CHANGELOG merge-forward resolved by writing the new release under the PREVIOUS release's heading — absorbing it — or by RELABELLING that heading to the new version; git leaves no conflict marker behind for either. Restore the heading with its own notes above the entry that replaced it." >&2
      else
        echo "  The changelog itself was deleted while its directory survived. Restore $changelog with every release note it carried at $merge_base." >&2
      fi
      echo "  Neither removal an author might intend needs a deletion. A yanked release keeps its heading, marked '## [<version>] - <date> [YANKED]' (Keep a Changelog). A note written against a version the manifest then SKIPPED keeps its heading too — say so in the section body rather than folding the notes into the release that shipped; the manifest cannot be bumped back down onto the skipped number, which --check-bump reads as a VERSION REGRESSION." >&2
      deleted=$((deleted + 1))
    fi
  done

  if ((deleted > 0)); then
    echo "A released '## [<version>]' entry may never be dropped by a change set; every heading present at the fork point must still be present at head." >&2
    exit 1
  fi
  echo "All ${#touched_changelogs[@]} changed changelog(s) preserve every version heading they carried at $merge_base ($compared heading(s) compared)."
  exit 0
fi

# ============================== --check-bump ================================
undocumented=0
malformed=0
preexisting=0
nonmonotonic=0
absorbed=0
declare -A absorbed_reported

for changelog in "${touched_changelogs[@]}"; do
  [[ -n "${absorbed_reported[$changelog]:-}" ]] && continue
  absorbed_reported["$changelog"]=1
  [[ -f "$changelog" ]] || continue
  missing_headings="$(missing_preserved_headings "$merge_base" "$changelog")" ||
    exit 2
  if [[ -n "$missing_headings" ]]; then
    echo "ABSORBED CHANGELOG HEADING: $changelog lost release section heading(s) vs the fork point (a merge-forward may have fused two releases into one section):" >&2
    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      echo "  ## [$v]" >&2
    done <<<"$missing_headings"
    absorbed=$((absorbed + 1))
  fi
done

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

  # "Did this branch bump?" is head vs the FORK POINT, never vs the base tip:
  # once the base ref advances past the fork, the tip comparison misreads both
  # directions — head==tip despite a real bump (two branches claimed the same
  # number: a collision that must FAIL, not read as not-bumped), and head!=tip
  # despite no bump at all (a cosmetic manifest edit on a stale branch, which
  # must stay out of scope rather than red-line as a regression).
  fork_version="$(git show "$merge_base:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
  [[ "$head_version" != "$fork_version" ]] || continue

  # Monotonicity: the bumped version must land strictly ABOVE what the base ref
  # carries NOW, not merely differ from it. A brief written against a stale base
  # otherwise ships a silent downgrade (0.21.x onto a 0.25.0 main reads as a
  # valid parity pair), and concurrent branches staging one number merge as an
  # equal-version collision. Compare on the zero-padded key (see
  # version_sort_key) so 0.10.0 outranks 0.9.0 numerically, not lexically.
  for v in "$head_version" "$base_version"; do
    if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-].*)?$ ]]; then
      echo "check-changelog-parity: $name carries a non-SemVer manifest version '$v'; refusing to pass without a comparable version." >&2
      exit 2
    fi
  done
  head_key="$(version_sort_key "$head_version")"
  base_key="$(version_sort_key "$base_version")"
  if [[ ! "$head_key" > "$base_key" ]]; then
    if [[ "$head_key" == "$base_key" ]]; then
      echo "VERSION COLLISION: $name is bumped to $head_version but $base already carries $base_version — another change set claimed that number first; renumber above it." >&2
    else
      echo "VERSION REGRESSION: $name is bumped to $head_version but $base already carries $base_version — merging would move the version BACKWARD; renumber above $base_version." >&2
    fi
    nonmonotonic=$((nonmonotonic + 1))
    continue
  fi

  # Require the bumped version's own entry at head, not merely that the file
  # changed: an unrelated edit (whitespace, title, an old release) must not
  # satisfy the gate. The match is a FIXED-STRING heading anchored to line start
  # (awk index()==1) over rendered_lines only, so the version string appearing in
  # prose, an indented line, a fenced example, or an HTML comment never satisfies
  # — or falsely pre-exists — the release entry, and SemVer metacharacters
  # (1.0.1+build.1) never leak into a regex. A same-line "<!-- ## [x] -->" can
  # never match anyway (the heading is not at column one).
  #
  # The reader must consume ALL of its input, never exit on first match: this
  # script runs under pipefail, and a reader that exits while rendered_lines is
  # still writing kills the writer with SIGPIPE (exit 141), which pipefail then
  # reports as the pipeline's failure — a FOUND heading misread as missing. A
  # real changelog puts the newest heading near the top of a file larger than
  # one stdio buffer, exactly the shape that loses the race (#2130 failed CI on
  # a correctly documented bump); the small fixtures in the test suite fit in
  # one buffer and can never trip it.
  heading="## [${head_version}]"
  has_heading() {
    rendered_lines - | awk -v h="$heading" '
      index($0, h) == 1 { found = 1 }
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

if ((undocumented > 0 || malformed > 0 || preexisting > 0 || nonmonotonic > 0 || absorbed > 0)); then
  ((undocumented > 0)) && echo "Add a '## [<version>]' entry for every plugin whose version changed." >&2
  ((malformed > 0)) && echo "Convert unbracketed changelog headings to the '## [<version>]' Keep-a-Changelog form." >&2
  ((preexisting > 0)) && echo "Add the bumped version's '## [<version>]' entry in this change set; it must be absent from the base changelog, not merely present at head." >&2
  ((nonmonotonic > 0)) && echo "Renumber every bumped version strictly above the base ref's CURRENT version, not the version the branch was cut from." >&2
  ((absorbed > 0)) && echo "Restore every '## [<version>]' heading that existed at the fork point; release notes must not be relabelled or absorbed into a newer section." >&2
  exit 1
fi
echo "Every plugin whose version changed vs $base has a '## [<version>]' CHANGELOG.md entry."
