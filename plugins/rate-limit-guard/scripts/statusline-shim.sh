#!/usr/bin/env bash
# statusline-shim: version-independent locator for this plugin's statusline
# tee. The operator wires the SHIM into their statusline once; the shim finds
# whichever version of the tee is installed at the time it runs.
#
# WHY THIS EXISTS: ${CLAUDE_PLUGIN_ROOT} is version-pinned
# (~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/) and changes on
# every plugin update, with the old directory lingering ~14 days before
# cleanup (plugins reference, "Plugin cache and file access", fetched
# 2026-07-24). Wiring that raw path into settings.json means the tee silently
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
#                                            the ONLY loss is the tee file)
#   tee not found  → one-line notice        (the shim WAS the whole statusline,
#     and no wrapped args                    so silence would leave a blank bar)
# It never edits, never writes, and never touches the contract directory.
#
# RESOLUTION: the newest installed tee by MTIME across marketplaces, which is
# the most recently installed one — deliberately not a version sort, since
# version directory names sort lexically ("0.9.0" > "0.10.0") and carry no
# guarantee of being semver at all. Marketplace directories named temp_* are
# skipped: the cache holds transient temp_git_*/temp_local_* clones during
# marketplace operations. Documented limitation: if two DIFFERENT marketplaces
# both ship a plugin named rate-limit-guard, the most recently installed one
# wins.
#
# Verified empirically 2026-07-24: the cache copy does NOT preserve the source
# file's timestamps — an installed tee carries its INSTALL time (measured: a
# source committed at 03:08 installed at 12:38 carried 12:38), so "newest
# mtime" is "most recently installed" even against an orphaned older version
# directory lingering from a previous install. An alternative authoritative
# source exists — ~/.claude/plugins/installed_plugins.json maps
# <plugin>@<marketplace> to the current installPath — but it is an UNDOCUMENTED
# internal file carrying its own schema version, and reading it would put a jq
# spawn on every statusline refresh. Revisit only if upstream documents it.
#
# Pure builtins — glob + `-nt` tests, no subprocesses — because the statusline
# command runs on every session event and on the refresh interval.

set -uo pipefail

PLUGIN_NAME="rate-limit-guard"

# shim-revision: 1
# Bumped whenever this file's content changes. The installed copy is a
# BYTE-IDENTICAL copy of this file, so /rate-limit-guard:setup check compares
# the two directly; the marker is for humans reading the installed copy.

RESOLVED=""

resolve_tee() {
  # HOME anchors the cache path; without it there is nothing to resolve.
  [[ -n "${HOME:-}" ]] || return 0

  local cache="$HOME/.claude/plugins/cache"
  local cand mkt rest
  for cand in "$cache"/*/"$PLUGIN_NAME"/*/scripts/statusline-tee.sh; do
    # An unmatched glob expands to the literal pattern; -f rejects it.
    [[ -f "$cand" ]] || continue
    rest="${cand#"$cache"/}"
    mkt="${rest%%/*}"
    [[ "$mkt" == temp_* ]] && continue
    if [[ -z "$RESOLVED" || "$cand" -nt "$RESOLVED" ]]; then
      RESOLVED="$cand"
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
