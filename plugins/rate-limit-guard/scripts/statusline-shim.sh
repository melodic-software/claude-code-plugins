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
# It never edits and never touches the contract directory. It writes exactly
# one thing: the resolution cache described under RESOLUTION, inside this
# plugin's own operator-home directory, and only when a resolution was found.
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
# produces.
#
# On a MISS the glob picks the newest NON-ORPHANED tee by MTIME across
# marketplaces, which is the most recently installed one, deliberately not a
# version sort, since version directory names sort lexically ("0.9.0" >
# "0.10.0") and carry no guarantee of being semver at all. Marketplace
# directories named temp_* are skipped: the cache holds transient
# temp_git_*/temp_local_* clones during marketplace operations. Documented
# limitation: if two DIFFERENT marketplaces both ship a plugin named
# rate-limit-guard, the most recently installed one wins. Finding NO tee writes
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
# absence is not itself a claim of installation; mtime picks the winner among
# unmarked candidates whenever the glob runs. Under the cache the marker is
# also the PRIMARY invalidator rather than only a candidate filter: a cached
# resolution holds until its version directory is marked orphaned, is pruned,
# or turns out to be a symlink, so a newer unmarked directory does not take
# over before one of those fires. An ordinary update marks the superseded
# directory, so the upgrade path is unaffected; a staged-but-not-installed
# fetch is the case that changes. If upstream renames or drops the marker, the
# cached tee lingers until its directory is pruned and the existence test
# re-globs: a stale tee, never a broken statusline.
#
# An alternative authoritative source exists — ~/.claude/plugins/
# installed_plugins.json maps <plugin>@<marketplace> to the current installPath
# — but it is an UNDOCUMENTED internal file carrying its own schema version,
# and reading it would put a jq spawn on every statusline refresh. The orphan
# marker is preferred over it on both counts: the behavior it reports is
# documented, and the test is a builtin. Revisit only if upstream documents the
# file.
#
# SYMLINKED DEVELOPMENT CHECKOUTS are rejected by the cache deliberately. "If
# you symlink a development checkout into the cache as a plugin's version
# entry, Claude Code never marks the link as orphaned and never removes it or
# the folders that hold it" (plugins reference, "Plugin caching and file
# resolution", https://code.claude.com/docs/en/plugins-reference, fetched
# 2026-09-21). Neither the orphan test nor the existence test could ever
# release such an entry, so caching one would pin the dev checkout permanently
# and installing the real marketplace copy would never take effect. A cached
# path whose version directory is a symlink is therefore rejected on read,
# which puts that operator back on exactly the glob behavior at exactly the
# cost it had before this cache existed.
#
# The HIT path is pure builtins, stat tests and parameter expansion with no
# subprocess at all, because the statusline command runs on every session event
# and on the refresh interval. A MISS may fork `mkdir` once, to create this
# plugin's operator-home directory when it is not already there; the cache
# write itself is a builtin redirect. Every write is best-effort, so failing to
# record the answer still execs the tee.

set -uo pipefail

PLUGIN_NAME="rate-limit-guard"

# shim-revision: 4
# Bumped whenever this file's content changes. The installed copy is a
# BYTE-IDENTICAL copy of this file, so /rate-limit-guard:setup check compares
# the two directly; the marker is for humans reading the installed copy.

RESOLVED=""

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
  # redirect would leave `cached` unset for `set -u` to abort on. The read's
  # exit status is never branched on, since `read` returns nonzero on a final
  # line carrying no trailing newline.
  if [[ -f "$cache_file" ]]; then
    local cached=""
    IFS= read -r cached <"$cache_file" || cached=""
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
      if [[ -n "$cmkt" && "$cmkt" != temp_* && "$cplug" == "$PLUGIN_NAME" ]] &&
        [[ -n "$cver" && "$crest" == "scripts/statusline-tee.sh" ]]; then
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

  local cand mkt rest
  for cand in "$cache"/*/"$PLUGIN_NAME"/*/scripts/statusline-tee.sh; do
    # An unmatched glob expands to the literal pattern; -f rejects it.
    [[ -f "$cand" ]] || continue
    rest="${cand#"$cache"/}"
    mkt="${rest%%/*}"
    [[ "$mkt" == temp_* ]] && continue
    # Uninstalled or superseded: the version directory is marked orphaned and
    # lingers ~14 days. Running it would keep an uninstalled plugin writing.
    [[ -e "${cand%/scripts/statusline-tee.sh}/.orphaned_at" ]] && continue
    if [[ -z "$RESOLVED" || "$cand" -nt "$RESOLVED" ]]; then
      RESOLVED="$cand"
    fi
  done

  # Remember the answer. Never a negative entry: finding nothing leaves the
  # directory uncreated, so a later install takes effect on the next render.
  [[ -n "$RESOLVED" ]] || return 0
  if [[ ! -d "$cache_dir" ]]; then
    mkdir -p "$cache_dir" 2>/dev/null || return 0
    # Owner-only, the posture the tee gives this same directory.
    chmod 700 "$cache_dir" 2>/dev/null || true
  fi
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
