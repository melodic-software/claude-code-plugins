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
# operator-home directory (~/.claude/context-guard/bin/), is installed by
# /context-guard:setup apply, and is never version-pinned.
#
# SHELL REQUIREMENT: Bash. As with the tee, on Windows this means Git Bash, so
# the wiring invokes it explicitly:
#   bash ~/.claude/context-guard/bin/statusline-shim.sh [wrapped-command...]
#
# CONTRACT — the shim is transparent in every path:
#   tee found      → exec bash <tee> "$@"   (the tee owns transparency from
#                                            there; see statusline-tee.sh)
#   tee not found  → exec "$@"              (wrapped statusline runs unchanged;
#                                            the ONLY loss is the snapshot)
#   tee not found  → one-line notice        (the shim WAS the whole statusline,
#     and no wrapped args                    so silence would leave a blank bar)
# It never edits, never writes, and never touches the snapshot directory.
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
# RESOLUTION: the glob collects every NON-ORPHANED tee across marketplaces
# and ranks them in two steps. First, a version directory the install record
# (<effective-config-dir>/plugins/installed_plugins.json) names as an
# installPath outranks one it does not name, so a staged or stray directory
# never beats the installed one. Second, within a rank, two version
# directories whose names are dotted numbers compare by VALUE, so 0.10.0 beats
# 0.9.0 (a lexical sort gets that backwards). Any other pair keeps the older
# rule, newest mtime: a name that is not a dotted number carries no order, and
# a symlinked development checkout's name says nothing about its age. mtime
# alone was not enough: plugin cache copies can carry EQUAL mtimes, `-nt` then
# never fires, and the first glob match won, which a verifier traced as 0.7.38
# running while 0.7.54 was installed (#4675). Marketplace directories named
# temp_* are skipped: the cache holds transient temp_git_*/temp_local_* clones
# during marketplace operations. If two DIFFERENT marketplaces both ship a
# plugin named context-guard, the one the record names wins; with both or
# neither named, the higher version, then the newer mtime, wins. The
# rate-limit-guard shim ranks a cache miss by the same rule.
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
# STAGED — a newer version fetched for a pending update — so the marker's
# absence is not itself a claim of installation; the install record, then the
# version and mtime order under RESOLUTION, picks the winner among unmarked
# candidates. If upstream renames or drops the marker, the test finds nothing
# and resolution falls back to that order alone: a stale tee, never a broken
# statusline.
#
# THE INSTALL RECORD is documented: "`installed_plugins.json` records each
# install with its `scope`, `installPath`, and `version`" (plugins loading
# reference, "Check which stage a plugin reached",
# https://code.claude.com/docs/en/plugins/loading, fetched 2026-09-27). It is
# read as one builtin `read` and tested as a substring match on the
# installPath's last four segments, never a JSON parse, so there is no jq
# spawn. Its schema is not documented beyond those three fields, so a record
# the match cannot read ranks every candidate the same and the version and
# mtime rules decide, exactly as with no record.
#
# Pure builtins (glob, one `read`, stat tests, no subprocesses), because the
# statusline command runs on every session event and on the refresh interval.

set -uo pipefail

PLUGIN_NAME="context-guard"

# shim-revision: 4
# Bumped whenever this file's content changes. The installed copy is a
# BYTE-IDENTICAL copy of this file, so /context-guard:setup check compares the
# two directly; the marker is for humans reading the installed copy.

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

# Set the variable named $1 to 2 when the install record (the caller's
# `record`) names marketplace $2's version directory $3 of this plugin as an
# installPath, spelled with `/` or with the JSON-escaped `\\` a Windows path
# carries, and to 1 otherwise. The quoted operands match literally, whatever
# the names contain.
recorded_tier() {
  local _t=1
  if [[ -n "$record" ]] &&
    [[ "$record" == *"cache/$2/$PLUGIN_NAME/$3\""* ||
      "$record" == *"cache\\\\$2\\\\$PLUGIN_NAME\\\\$3\""* ]]; then
    _t=2
  fi
  printf -v "$1" '%s' "$_t"
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
  # The install record ranks candidates, so it is read only once a second one
  # turns up: with a single non-orphaned tee, the common case, there is nothing
  # to rank. It is read whole with a builtin. `read -d ''` returns 1 at end of
  # file, which is the normal case here, so its status is ignored; an absent or
  # unreadable record leaves it empty and every candidate unrecorded.
  local record="" record_read=0 record_file="$config_dir/plugins/installed_plugins.json"
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
    if [[ -z "$RESOLVED" ]]; then
      RESOLVED="$cand"
      best_ver="$ver"
      continue
    fi
    if ((!record_read)); then
      record_read=1
      if [[ -f "$record_file" ]]; then
        IFS= read -r -d '' record 2>/dev/null <"$record_file" || true
      fi
      rest="${RESOLVED#"$cache"/}"
      recorded_tier best_tier "${rest%%/*}" "$best_ver"
    fi
    recorded_tier tier "$mkt" "$ver"
    if ((tier > best_tier)) ||
      { ((tier == best_tier)) && newer_candidate "$cand" "$ver" "$RESOLVED" "$best_ver"; }; then
      RESOLVED="$cand"
      best_tier=$tier
      best_ver="$ver"
    fi
  done
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
