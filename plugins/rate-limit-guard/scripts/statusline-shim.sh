#!/usr/bin/env bash
# statusline-shim: version-independent locator for this plugin's statusline
# tee. The operator wires the SHIM into their statusline once; the shim finds
# whichever version of the tee is installed at the time it runs.
#
# WHY THIS EXISTS: ${CLAUDE_PLUGIN_ROOT} is version-pinned
# (<config-dir>/plugins/cache/<marketplace>/<plugin>/<version>/) and changes on
# every plugin update, with the old directory lingering ~14 days before
# cleanup (plugins reference, "Plugin caching and file resolution" — that
# section was titled "Plugin cache and file access" when this was first
# cited; re-fetched 2026-08-10, cache root `~/.claude/plugins/cache`).
# Wiring that raw path into settings.json means the tee silently
# stops on the next version bump and breaks outright once the old directory is
# pruned. The shim is the stable wiring target: it lives in this plugin's
# operator-home directory (~/.claude/rate-limit-guard/bin/), is installed by
# /rate-limit-guard:setup apply, and is never version-pinned.
#
# SHELL REQUIREMENT: Bash. As with the tee, on Windows this means Git Bash, so
# the wiring invokes it explicitly:
#   bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh [wrapped-command...]
#
# CONTRACT — the shim is transparent in every path:
#   tee found      → exec bash <tee> "$@"   (the tee owns transparency from
#                                            there; see statusline-tee.sh)
#   tee not found  → exec "$@"              (wrapped statusline runs unchanged;
#                                            the ONLY loss is the contract file)
#   tee not found  → one-line notice        (the shim WAS the whole statusline,
#     and no wrapped args                    so silence would leave a blank bar)
# It never edits. It writes exactly one thing: the resolution cache described
# under RESOLUTION, under the EFFECTIVE config dir, and only when a resolution
# was found. That is the contract directory only in the default configuration;
# an operator running a relocated CLAUDE_CONFIG_DIR has the cache beside their
# relocated plugin cache, while the tee's and the hook's files stay anchored on
# $HOME. reference/reader-contract.md carries the same qualifier.
#
# CACHE ROOT: the cache lives under the EFFECTIVE configuration directory,
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude} — "Override the configuration directory
# (default: ~/.claude). All settings, session history, and plugins are stored
# under this path" (environment-variables reference,
# https://code.claude.com/docs/en/env-vars, fetched 2026-07-25). Anchoring on
# $HOME alone would resolve nothing for an operator running a relocated config
# dir (the documented multi-account alias), so the shim would silently take the
# no-tee path forever after they wired it.
#
# RESOLUTION is cache-first. The answer is remembered in ONE file,
# <effective-config-dir>/<plugin>/.statusline-tee-path, derived from
# PLUGIN_NAME so that a sibling shim caches under its own name, and written
# only when the glob below actually ran. A render with a usable cache costs
# four stat tests and no fork: the cached line is decomposed SEGMENT BY SEGMENT
# and must name a non-temp_* marketplace, this plugin, a version directory and
# the tee itself; then the file must exist, its version directory must not be a
# symlink, and that directory must not carry the orphan marker. Anything
# failing falls through to the glob, so an empty, truncated, stale or
# hand-edited cache file costs one walk and never a wrong exec. The segment
# test is what keeps the cache from widening what the shim will exec: a cache
# file can only ever name a path at exactly the depth and shape the glob itself
# produces, dot segments included, since without `dotglob` a `*` matches no
# leading dot. That revalidation, not the way the file is written, is what
# makes a concurrent truncate-and-write safe: a reader that sees a torn or
# empty line simply walks.
#
# On a MISS the glob collects every NON-ORPHANED tee across marketplaces and
# ranks them in two steps. First, a version directory the install record
# (<effective-config-dir>/plugins/installed_plugins.json) names as an
# installPath outranks one it does not name, so a staged or stray directory
# never beats the installed one. Second, within a rank, two version
# directories whose names are dotted numbers compare by VALUE, so 0.10.0 beats
# 0.9.0 (a lexical sort gets that backwards). Any other pair keeps the older
# rule, newest mtime: a name that is not a dotted number carries no order, and
# a symlinked development checkout's name says nothing about its age. mtime
# alone was not enough: plugin cache copies can carry EQUAL mtimes, `-nt` then
# never fires, and the first glob match won, which a verifier traced as 0.8.1
# running while 0.8.9 was installed (#4676). Marketplace directories named
# temp_* are skipped: the cache holds transient temp_git_*/temp_local_* clones
# during marketplace operations. If two DIFFERENT marketplaces both ship a
# plugin named rate-limit-guard, the one the record names wins; with both or
# neither named, the higher version, then the newer mtime, wins.
#
# The CACHE sharpens that limitation, and this is the one thing it makes worse.
# Installing from marketplace B while an un-orphaned copy from marketplace A is
# already cached leaves A resolved: the two installs carry different
# marketplace identities, so nothing orphans A, and a hit never runs the mtime
# comparison that used to hand the render to B. B takes over once A is orphaned
# or pruned, or once the cache file is deleted, which reference/
# reader-contract.md already states a cleanup tool may do freely. Accepted
# deliberately: re-globbing often enough to notice a second marketplace is the
# entire cost this cache exists to avoid, and no cheap invalidator
# distinguishes the case. The cache root's own mtime is not one, since it
# changes whenever ANY plugin is installed and whenever a temp_* clone appears.
#
# Finding NO tee writes
# nothing and creates nothing: the absence is never cached, so installing the
# plugin takes effect on the very next render.
#
# Verified empirically 2026-07-24: the cache copy does NOT preserve the source
# file's timestamps — an installed tee carries its INSTALL time (measured: a
# source committed at 03:08 installed at 12:38 carried 12:38), so "newest
# mtime" is "most recently installed".
#
# ORPHAN SKIP — why mtime alone is not enough: "When you update or uninstall a
# plugin, the previous version directory is marked as orphaned and removed
# automatically 14 days later. The grace period lets concurrent Claude Code
# sessions that already loaded the old version keep running without errors"
# (plugins reference, "Plugin caching and file resolution",
# https://code.claude.com/docs/en/plugins-reference, fetched 2026-08-10).
# UNINSTALL therefore leaves the tee on disk for ~14 days, and an mtime-only
# shim keeps executing it for that whole window: the operator removes the
# plugin and it keeps writing snapshots, with no signal that it is still
# running. A candidate whose version directory carries the orphan marker is
# skipped, so uninstalling stops the tee at the next statusline refresh.
#
# The MARKING is documented; the marker's on-disk spelling is not. Measured on
# Claude Code 2.1.220, 2026-07-30, against a relocated CLAUDE_CONFIG_DIR: an
# uninstall writes `<version-dir>/.orphaned_at` (epoch-ms) and leaves
# scripts/statusline-tee.sh in place. Reproducible on any live cache: every
# superseded version directory of a plugin carries the marker and the currently
# installed one does not. A directory can also be marker-less while merely
# STAGED (a newer version fetched for a pending update), so the marker's
# absence is not itself a claim of installation; the install record, then the
# version and mtime order under RESOLUTION, picks the winner among unmarked
# candidates whenever the glob runs. Under the cache the marker is
# also the PRIMARY invalidator rather than only a candidate filter: a cached
# resolution holds until its version directory is marked orphaned, is pruned,
# or turns out to be a symlink, so a newer unmarked directory does not take
# over before one of those fires. An ordinary update marks the superseded
# directory, so the upgrade path is unaffected; a staged-but-not-installed
# fetch is the case that changes. If upstream renames or drops the marker, the
# cached tee lingers until its directory is pruned and the existence test
# re-globs: a stale tee, never a broken statusline.
#
# THE INSTALL RECORD is documented: "`installed_plugins.json` records each
# install with its `scope`, `installPath`, and `version`" (plugins loading
# reference, "Check which stage a plugin reached",
# https://code.claude.com/docs/en/plugins/loading, fetched 2026-09-27). Only a
# MISS reads it, as one builtin `read`, and the test is a substring match on
# the installPath's last four segments, never a JSON parse: no jq spawn, and
# the hit path never touches it. Its schema is not documented beyond those
# three fields, so a record the match cannot read ranks every candidate the
# same and the version and mtime rules decide, exactly as with no record. The
# orphan marker stays the hit path's invalidator: that test is a stat.
#
# SYMLINKED DEVELOPMENT CHECKOUTS are rejected by the cache deliberately. "If
# you symlink a development checkout into the cache as a plugin's version
# entry, Claude Code never marks the link as orphaned and never removes it or
# the folders that hold it" (plugins reference, "Plugin caching and file
# resolution", https://code.claude.com/docs/en/plugins-reference, fetched
# 2026-09-21). Neither the orphan test nor the existence test could ever
# release such an entry, so caching one would pin the dev checkout permanently
# and installing the real marketplace copy would never take effect. Such a
# resolution is therefore never WRITTEN, and is rejected on read as well in
# case an older revision recorded one. Rejecting it on read alone would be
# worse than no cache at all: the glob would re-elect the same symlink every
# render and rewrite the file every render, so that operator would pay the
# failed hit test plus a write on top of the walk. Skipping the write puts them
# back on exactly the glob behavior at exactly the pre-cache cost.
#
# KNOWN GAP: on Windows an unprivileged development checkout is often a
# junction rather than a symlink, and `-L` does not report a junction. Whether
# Claude Code also never-orphans a junctioned version entry is unverified, so a
# junctioned dev checkout may still be pinned on Git Bash.
#
# The HIT path is pure builtins, stat tests and parameter expansion with no
# subprocess at all, because the statusline command runs on every session event
# and on the refresh interval. A first-time MISS forks twice, `mkdir` and
# `chmod`, to create this plugin's directory under the effective config dir
# when it is not already there; the cache write itself is a builtin redirect.
# Every write is best-effort, so failing to record the answer still execs the
# tee.

set -uo pipefail

PLUGIN_NAME="rate-limit-guard"

# shim-revision: 5
# Bumped whenever this file's content changes. The installed copy is a
# BYTE-IDENTICAL copy of this file, so /rate-limit-guard:setup check compares
# the two directly; the marker is for humans reading the installed copy.

RESOLVED=""

# Succeeds when candidate $1 (version directory name $2) outranks the current
# pick $3 (name $4) within one tier. Two plain directories whose names are
# dotted numbers compare by value, segment by segment, a missing segment
# counting as 0, so 0.10.0 outranks 0.9.0. Any other pair, and a tie in value,
# keeps the mtime order: a name that is not a dotted number carries no order,
# and a symlinked development checkout's name says nothing about its age.
newer_candidate() {
  local cand="$1" ver="$2" best="$3" best_ver="$4"
  local num='^[0-9]{1,9}(\.[0-9]{1,9})*$'
  if [[ "$ver" =~ $num && "$best_ver" =~ $num ]] &&
    [[ ! -L "${cand%/scripts/statusline-tee.sh}" && ! -L "${best%/scripts/statusline-tee.sh}" ]]; then
    local x="$ver." y="$best_ver." sx sy
    while [[ -n "$x" || -n "$y" ]]; do
      sx="${x%%.*}" x="${x#*.}"
      sy="${y%%.*}" y="${y#*.}"
      ((10#${sx:-0} > 10#${sy:-0})) && return 0
      ((10#${sx:-0} < 10#${sy:-0})) && return 1
    done
  fi
  [[ "$cand" -nt "$best" ]]
}

resolve_tee() {
  # The effective config dir anchors the cache path. CLAUDE_CONFIG_DIR wins when
  # set and non-empty; otherwise $HOME/.claude. With neither there is nothing to
  # resolve.
  local config_dir="${CLAUDE_CONFIG_DIR:-}"
  if [[ -z "$config_dir" ]]; then
    [[ -n "${HOME:-}" ]] || return 0
    config_dir="$HOME/.claude"
  fi

  local cache="$config_dir/plugins/cache"
  # Both of these are derived HERE rather than at top level: with HOME and
  # CLAUDE_CONFIG_DIR both unset there is no config dir to anchor them to, and
  # `set -u` would abort the shim outright instead of degrading.
  local cache_dir="$config_dir/$PLUGIN_NAME"
  local cache_file="$cache_dir/.statusline-tee-path"

  # HIT PATH. The -f guard is load-bearing twice over: an input redirect on an
  # absent file prints to stderr, which the shim must leave clean, and a failed
  # redirect would leave `cached` unset for `set -u` to abort on. -f is a stat
  # test, so it says nothing about READABILITY; 2>/dev/null covers the
  # mode-000 case and precedes the input redirect for the reason given at the
  # write below. A nonzero read status is treated as no cached line, which
  # costs a walk on a file whose last line carries no newline and then rewrites
  # it with one.
  if [[ -f "$cache_file" ]]; then
    local cached=""
    IFS= read -r cached 2>/dev/null <"$cache_file" || cached=""
    # SEGMENT decomposition, not one pattern: inside [[ ]] a `*` matches `/`,
    # so a shape test cannot constrain depth and would accept paths the glob
    # can never produce. $cache stays QUOTED wherever it is a pattern operand,
    # or a `*`, `?` or `[` in the operator's own config-dir path would be read
    # as a pattern.
    local crest="${cached#"$cache"/}" cmkt="" cplug="" cver=""
    if [[ "$crest" != "$cached" ]]; then
      cmkt="${crest%%/*}"
      crest="${crest#*/}"
      cplug="${crest%%/*}"
      crest="${crest#*/}"
      cver="${crest%%/*}"
      crest="${crest#*/}"
      # A segment starting with a dot is rejected because the glob below can
      # never produce one: without `dotglob`, `*` does not match a leading dot.
      # Without this test, `.` and `..` pass as a marketplace or a version and
      # reach two levels ABOVE the cache root, and `..` also defeats the
      # symlink guard structurally, because a `cdir` ending in `/..` or `/.` is
      # never itself a link.
      if [[ -n "$cmkt" && "$cmkt" != temp_* && "$cmkt" != .* && "$cplug" == "$PLUGIN_NAME" ]] &&
        [[ -n "$cver" && "$cver" != .* && "$crest" == "scripts/statusline-tee.sh" ]]; then
        local cdir="${cached%/scripts/statusline-tee.sh}"
        # Present, not a symlinked dev checkout no invalidator could release,
        # and not marked orphaned by an update or an uninstall.
        if [[ -f "$cached" && ! -L "$cdir" && ! -e "$cdir/.orphaned_at" ]]; then
          RESOLVED="$cached"
          return 0
        fi
      fi
    fi
  fi

  # The install record, read whole with a builtin. `read -d ''` returns 1 at
  # end of file, which is the normal case here, so its status is ignored; an
  # absent or unreadable record leaves it empty and every candidate unrecorded.
  local record="" record_file="$config_dir/plugins/installed_plugins.json"
  if [[ -f "$record_file" ]]; then
    IFS= read -r -d '' record 2>/dev/null <"$record_file" || true
  fi

  local cand mkt rest ver cdir tier best_tier=0 best_ver=""
  for cand in "$cache"/*/"$PLUGIN_NAME"/*/scripts/statusline-tee.sh; do
    # An unmatched glob expands to the literal pattern; -f rejects it.
    [[ -f "$cand" ]] || continue
    rest="${cand#"$cache"/}"
    mkt="${rest%%/*}"
    [[ "$mkt" == temp_* ]] && continue
    cdir="${cand%/scripts/statusline-tee.sh}"
    # Uninstalled or superseded: the version directory is marked orphaned and
    # lingers ~14 days. Running it would keep an uninstalled plugin writing.
    [[ -e "$cdir/.orphaned_at" ]] && continue
    ver="${cdir##*/}"
    # Tier 2: an installPath in the record ends in this version directory,
    # spelled with `/` or with the JSON-escaped `\\` a Windows path carries.
    # The quoted operands match literally, whatever the names contain.
    tier=1
    if [[ -n "$record" ]] &&
      [[ "$record" == *"cache/$mkt/$PLUGIN_NAME/$ver\""* ||
        "$record" == *"cache\\\\$mkt\\\\$PLUGIN_NAME\\\\$ver\""* ]]; then
      tier=2
    fi
    if [[ -z "$RESOLVED" ]] || ((tier > best_tier)) ||
      { ((tier == best_tier)) && newer_candidate "$cand" "$ver" "$RESOLVED" "$best_ver"; }; then
      RESOLVED="$cand"
      best_tier=$tier
      best_ver="$ver"
    fi
  done

  # Remember the answer. Never a negative entry: finding nothing leaves the
  # directory uncreated, so a later install takes effect on the next render.
  [[ -n "$RESOLVED" ]] || return 0
  # A symlinked version directory is rejected on read, so recording one would
  # make every later render fail the hit test, re-elect the same symlink, and
  # rewrite this file: strictly more work than no cache at all. Leaving it
  # unwritten keeps a development checkout on exactly the pre-cache path.
  [[ -L "${RESOLVED%/scripts/statusline-tee.sh}" ]] && return 0
  if [[ ! -d "$cache_dir" ]]; then
    mkdir -p "$cache_dir" 2>/dev/null || return 0
    # Owner-only, matching the posture the tee gives its own directory. The two
    # are the same directory only when CLAUDE_CONFIG_DIR is unset; the tee's is
    # hard-anchored on $HOME.
    chmod 700 "$cache_dir" 2>/dev/null || true
  fi
  # A pre-planted symlink here would be followed and truncated through, so the
  # write is skipped rather than aimed at whatever it points to. Losing the
  # cache costs a glob on the next render; nothing else depends on it.
  [[ -L "$cache_file" ]] && return 0
  # 2>/dev/null precedes the output redirect on purpose: redirections apply
  # left to right, so one placed after it would not yet be in effect when bash
  # reports a failure to open the target.
  printf '%s\n' "$RESOLVED" 2>/dev/null >"$cache_file" || true
  return 0
}

resolve_tee

if [[ -n "$RESOLVED" ]]; then
  exec bash "$RESOLVED" "$@"
fi

# No tee installed (plugin removed, cache cleaned, or never installed).
if (($#)); then
  exec "$@"
fi

printf '%s: statusline tee not found — run /%s:setup check\n' \
  "$PLUGIN_NAME" "$PLUGIN_NAME"
exit 0
