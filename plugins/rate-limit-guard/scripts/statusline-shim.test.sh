#!/usr/bin/env bash
# Black-box contract test for statusline-shim.sh (the version-independent
# locator the operator wires into their statusline).
#
# Proves: (a) RESOLUTION — the newest installed tee by mtime wins across
# version directories whose names do NOT sort lexically (0.10.0 vs 0.9.0),
# transient temp_* marketplace clones are skipped, version directories marked
# orphaned by an update or an uninstall are skipped even when they are the
# newest, the marketplace directory name is never assumed, and other plugins'
# trees are ignored; (b)
# TRANSPARENCY — the wrapped statusline command receives the stdin bytes and
# its stdout and exit code pass through, whether the tee was found or not;
# (c) the NO-TEE paths — a missing tee degrades to running the wrapped command
# alone, and with no wrapped command the shim prints one diagnostic line and
# exits 0 rather than exec'ing an empty argv; (d) CHAINING — two shims in
# series each locate their own tee and the innermost command still owns
# stdout, which is how rate-limit-guard and context-guard compose; (e) CACHING:
# the resolved path is remembered in one file under the EFFECTIVE config dir,
# keyed by plugin name, so a hit skips the glob entirely and rewrites nothing,
# while a cache that is deleted, names a temp_* marketplace, or whose version
# directory is orphaned, pruned or a symlink is rejected and re-globbed.
# Finding no tee caches nothing at all.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM="$SCRIPT_DIR/statusline-shim.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
assert_eq() {
  local want="$1" got="$2" what="$3"
  if [[ "$want" == "$got" ]]; then
    ok "$what"
  else
    fail "$what — want [$want] got [$got]"
  fi
}
assert_contains() {
  local hay="$1" needle="$2" what="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    ok "$what"
  else
    fail "$what — [$hay] does not contain [$needle]"
  fi
}
assert_not_contains() {
  local hay="$1" needle="$2" what="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    ok "$what"
  else
    fail "$what — [$hay] unexpectedly contains [$needle]"
  fi
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

INPUT='{"session_id":"sess-42","context_window":{"used_percentage":8}}'

# Plant a fake tee that identifies itself, then behaves like the real one:
# transparent passthrough of stdin, stdout, and exit code.
#   $1 = HOME root, $2 = marketplace dir, $3 = plugin name, $4 = version,
#   $5 = marker printed to stderr when this tee runs
plant_tee() {
  local home="$1" mkt="$2" plugin="$3" version="$4" marker="$5"
  local dir="$home/.claude/plugins/cache/$mkt/$plugin/$version/scripts"
  mkdir -p "$dir"
  cat >"$dir/statusline-tee.sh" <<EOF
#!/usr/bin/env bash
echo "TEE:$marker" >&2
if ((\$#)); then exec "\$@"; fi
echo "standalone:$marker"
EOF
  printf '%s' "$dir/statusline-tee.sh"
}

# Mark a planted tee's VERSION directory the way Claude Code marks one on an
# update or an uninstall: `.orphaned_at` holding an epoch-ms timestamp
# (measured on Claude Code 2.1.220). The directory keeps its files for ~14 days
# afterwards, which is the window this marker exists to close.
#   $1 = the tee path returned by plant_tee
orphan_tee() {
  local tee="$1"
  printf '1785448003467' >"${tee%/scripts/statusline-tee.sh}/.orphaned_at"
}

# The shim's resolution cache file, spelled the way the shim spells it: keyed by
# plugin name under the EFFECTIVE config dir, so the chaining case can name both
# links' caches. No fixture ever creates this directory: the shim's miss path
# has to, and case 25 is what proves it does not create it when there is nothing
# to cache.
#   $1 = the effective config dir, $2 = the plugin name
cache_path() {
  printf '%s' "$1/$2/.statusline-tee-path"
}

# The one line a cache file holds, or the empty string when there is no cache
# file. Guarded the way the shim guards its own read, so an absent file is not
# an error on this side either.
cache_line() {
  local line=""
  if [[ -f "$1" ]]; then
    IFS= read -r line <"$1" || line=""
  fi
  printf '%s' "$line"
}

# Wrapped statusline stand-in: echoes the stdin it received, prints a fixed
# line, and exits with a chosen code.
make_wrapped() {
  local path="$1" rc="$2"
  cat >"$path" <<EOF
#!/usr/bin/env bash
echo "stdin:\$(cat)"
echo "RENDER"
exit $rc
EOF
  chmod +x "$path"
}

# Runner core: feed INPUT on stdin to `env <args>`, capturing stdout, stderr,
# and the exit code.
OUT=""
ERR=""
RC=0
run_env() {
  local errfile="$WORK/stderr.$$"
  # A here-string, never a pipe: a shim that finds nothing to run exits before
  # reading stdin, and a printf still writing then fails on the closed pipe.
  OUT="$(env "$@" <<<"$INPUT" 2>"$errfile")"
  RC=$?
  ERR="$(<"$errfile")"
  rm -f "$errfile"
}

# HOME-scoped invocation; remaining args are the wrapped command.
# CLAUDE_CONFIG_DIR is cleared so an ambient relocated config dir on the
# developer's machine cannot leak into the HOME-anchored cases.
run() {
  local home="$1"
  shift
  run_env -u CLAUDE_CONFIG_DIR "HOME=$home" bash "$SHIM" "$@"
}

# Same capture with CLAUDE_CONFIG_DIR SET rather than cleared, for the relocated
# config-dir cases: $1 = HOME, $2 = the config dir (empty exercises the fallback
# to $HOME/.claude), remaining args are the wrapped command.
run_cfg() {
  local home="$1" cfg="$2"
  shift 2
  run_env "HOME=$home" "CLAUDE_CONFIG_DIR=$cfg" bash "$SHIM" "$@"
}

# Capture an xtrace of ONE render into a file, the shape bench/trace-probe.sh
# uses: BASH_XTRACEFD names a descriptor the caller opens, so the trace never
# mixes into the shim's stdout or stderr. Only the shim itself is traced, since
# the tee it execs is a fresh bash without -x.
#   $1 = HOME root, $2 = the trace file, remaining args are the wrapped command
trace_run() {
  local home="$1" trace="$2"
  shift 2
  printf '%s' "$INPUT" |
    env -u CLAUDE_CONFIG_DIR "HOME=$home" BASH_XTRACEFD=9 bash -x "$SHIM" "$@" \
      >/dev/null 2>&1 9>"$trace"
}

# --- 1. single installed tee: resolved, and the chain stays transparent -----
H1="$WORK/h1"
plant_tee "$H1" "some-marketplace" "rate-limit-guard" "0.1.0" "v1" >/dev/null
make_wrapped "$H1/render.sh" 0
run "$H1" bash "$H1/render.sh"
assert_contains "$ERR" "TEE:v1" "resolves the installed tee (marketplace name not assumed)"
assert_contains "$OUT" "stdin:$INPUT" "stdin bytes reach the wrapped command"
assert_contains "$OUT" "RENDER" "wrapped command owns stdout"
assert_eq "0" "$RC" "wrapped exit code passes through (0)"

# --- 2. exit code of the wrapped command is preserved, not swallowed --------
make_wrapped "$H1/render-fail.sh" 3
run "$H1" bash "$H1/render-fail.sh"
assert_eq "3" "$RC" "nonzero wrapped exit code passes through"

# --- 3. newest by MTIME wins, and lexical order would get it wrong ----------
# 0.9.0 is lexically LAST (a naive glob loop would pick it) but 0.10.0 is the
# newer install; the shim must pick 0.10.0.
H2="$WORK/h2"
OLD="$(plant_tee "$H2" "mkt" "rate-limit-guard" "0.9.0" "old")"
NEW="$(plant_tee "$H2" "mkt" "rate-limit-guard" "0.10.0" "new")"
touch -t 202001010000 "$OLD"
touch -t 203001010000 "$NEW"
make_wrapped "$H2/render.sh" 0
run "$H2" bash "$H2/render.sh"
assert_contains "$ERR" "TEE:new" "newest-by-mtime version wins over lexically-later name"

# --- 4. transient temp_* marketplace clones are skipped ---------------------
H3="$WORK/h3"
REAL="$(plant_tee "$H3" "melodic-software" "rate-limit-guard" "0.1.0" "real")"
TMP="$(plant_tee "$H3" "temp_git_1784663154120_oirbvy" "rate-limit-guard" "0.1.0" "tempclone")"
touch -t 202001010000 "$REAL"
touch -t 203001010000 "$TMP" # newer, and must STILL lose
make_wrapped "$H3/render.sh" 0
run "$H3" bash "$H3/render.sh"
assert_contains "$ERR" "TEE:real" "temp_* marketplace clone skipped even when newer"

# --- 5. other plugins' trees are ignored ------------------------------------
H4="$WORK/h4"
plant_tee "$H4" "mkt" "context-guard" "0.1.0" "sibling" >/dev/null
make_wrapped "$H4/render.sh" 0
run "$H4" bash "$H4/render.sh"
assert_eq "" "$ERR" "another plugin's tee is not resolved"
assert_contains "$OUT" "RENDER" "wrapped command still runs when no tee is found"
assert_eq "0" "$RC" "no-tee passthrough preserves exit code (0)"

# --- 6. no tee + failing wrapped command: still transparent -----------------
make_wrapped "$H4/render-fail.sh" 7
run "$H4" bash "$H4/render-fail.sh"
assert_eq "7" "$RC" "no-tee passthrough preserves a nonzero exit code"

# --- 7. no tee AND no wrapped command: one notice, exit 0, no empty exec ----
run "$H4"
assert_contains "$OUT" "rate-limit-guard" "standalone no-tee case names the plugin"
assert_contains "$OUT" "setup check" "standalone no-tee case points at the setup remediation"
assert_eq "0" "$RC" "standalone no-tee case exits 0"
# $() strips the trailing newline, so re-add one before counting.
assert_eq "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "standalone no-tee notice is one line"

# --- 8. tee found, no wrapped command: the tee's standalone mode runs -------
run "$H1"
assert_contains "$OUT" "standalone:v1" "no wrapped command hands standalone mode to the tee"

# --- 9. HOME unset: nothing to resolve, wrapped command unaffected ----------
make_wrapped "$WORK/render-nohome.sh" 0
OUT="$(printf '%s' "$INPUT" | env -u HOME -u CLAUDE_CONFIG_DIR bash "$SHIM" bash "$WORK/render-nohome.sh" 2>/dev/null)"
RC=$?
assert_contains "$OUT" "RENDER" "unset HOME degrades to the wrapped command"
assert_eq "0" "$RC" "unset HOME preserves the wrapped exit code"

# --- 10. chaining: two shims in series, each resolving its own tee ----------
# This is the two-plugin composition: rate-limit-guard shim wraps context-guard
# shim wraps the operator's statusline.
H5="$WORK/h5"
plant_tee "$H5" "melodic-software" "rate-limit-guard" "0.1.0" "rlg" >/dev/null
plant_tee "$H5" "melodic-software" "context-guard" "0.1.0" "cg" >/dev/null
# A sibling shim for the second link: same source, different plugin name.
SIB="$WORK/rlg-shim.sh"
sed 's/^PLUGIN_NAME="rate-limit-guard"$/PLUGIN_NAME="context-guard"/' "$SHIM" >"$SIB"
make_wrapped "$H5/render.sh" 0
run "$H5" bash "$SIB" bash "$H5/render.sh"
assert_contains "$ERR" "TEE:rlg" "chain: rate-limit-guard tee runs"
assert_contains "$ERR" "TEE:cg" "chain: context-guard tee runs"
assert_contains "$OUT" "stdin:$INPUT" "chain: stdin bytes survive both hops"
assert_contains "$OUT" "RENDER" "chain: innermost command owns stdout"
assert_eq "0" "$RC" "chain: exit code passes through both hops"

# --- 11. chain with a missing middle tee stays transparent ------------------
H6="$WORK/h6"
plant_tee "$H6" "melodic-software" "rate-limit-guard" "0.1.0" "rlg" >/dev/null
make_wrapped "$H6/render.sh" 0
run "$H6" bash "$SIB" bash "$H6/render.sh"
assert_contains "$ERR" "TEE:rlg" "chain: present tee still runs when the sibling tee is absent"
assert_contains "$OUT" "RENDER" "chain: absent sibling tee does not break the statusline"

# --- 12. relocated config dir: CLAUDE_CONFIG_DIR anchors the cache ----------
# The documented multi-account setup (`CLAUDE_CONFIG_DIR=~/.claude-work claude`)
# moves the plugin cache with it, so a $HOME-only shim would silently resolve
# nothing forever after the operator wired it.
H7="$WORK/h7"
CFG="$WORK/cfg-relocated"
# plant_tee lays its cache under <arg>/.claude, so planting into $WORK/reloc and
# then renaming that .claude subtree gives a config dir at an arbitrary path —
# exactly what CLAUDE_CONFIG_DIR names.
plant_tee "$WORK/reloc" "some-marketplace" "rate-limit-guard" "0.1.0" "reloc" >/dev/null
mv "$WORK/reloc/.claude" "$CFG"
make_wrapped "$WORK/render-cfg.sh" 0
run_cfg "$H7" "$CFG" bash "$WORK/render-cfg.sh"
assert_contains "$ERR" "TEE:reloc" "CLAUDE_CONFIG_DIR anchors the cache when HOME holds no cache"
assert_contains "$OUT" "RENDER" "relocated config dir stays transparent"
assert_eq "0" "$RC" "relocated config dir preserves the wrapped exit code"

# --- 13. CLAUDE_CONFIG_DIR wins over a cache under HOME ---------------------
plant_tee "$H7" "some-marketplace" "rate-limit-guard" "0.1.0" "home" >/dev/null
run_cfg "$H7" "$CFG" bash "$WORK/render-cfg.sh"
assert_contains "$ERR" "TEE:reloc" "an explicit CLAUDE_CONFIG_DIR overrides the HOME default"
assert_not_contains "$ERR" "TEE:home" "the HOME cache is not consulted when CLAUDE_CONFIG_DIR is set"

# --- 14. empty CLAUDE_CONFIG_DIR falls back to HOME -------------------------
run_cfg "$H7" "" bash "$WORK/render-cfg.sh"
assert_contains "$ERR" "TEE:home" "an empty CLAUDE_CONFIG_DIR falls back to \$HOME/.claude"

# --- 15. UNINSTALLED plugin: the orphaned tee is not executed ---------------
# `claude plugin uninstall` writes .orphaned_at into the version directory and
# leaves the files there for ~14 days. Without the marker check the shim keeps
# finding and running the removed plugin's tee for that whole window.
H8="$WORK/h8"
GONE="$(plant_tee "$H8" "melodic-software" "rate-limit-guard" "0.4.0" "uninstalled")"
orphan_tee "$GONE"
make_wrapped "$H8/render.sh" 0
run "$H8" bash "$H8/render.sh"
assert_eq "" "$ERR" "an uninstalled plugin's orphaned tee is not executed"
assert_contains "$OUT" "RENDER" "uninstalled plugin still leaves the statusline running"
assert_eq "0" "$RC" "uninstalled plugin preserves the wrapped exit code"

# --- 16. orphaned loses to an installed sibling even when it is newer -------
# The update path: the superseded directory is marked orphaned. Give it the
# newer mtime so only the marker can decide.
H9="$WORK/h9"
KEEP="$(plant_tee "$H9" "mkt" "rate-limit-guard" "0.4.0" "installed")"
DEAD="$(plant_tee "$H9" "mkt" "rate-limit-guard" "0.3.9" "orphaned")"
orphan_tee "$DEAD"
touch -t 202001010000 "$KEEP"
touch -t 203001010000 "$DEAD"
make_wrapped "$H9/render.sh" 0
run "$H9" bash "$H9/render.sh"
assert_contains "$ERR" "TEE:installed" "orphaned version directory skipped even when newest by mtime"
assert_not_contains "$ERR" "TEE:orphaned" "the orphaned tee does not also run"

# --- 17. the cache is authoritative, and a hit rewrites nothing -------------
# The first render resolves by glob and remembers the answer. A v2 installed
# afterwards with a NEWER mtime and no orphan marker does not take over: that
# is the behavior the cache buys, and case 3 already established that mtime
# order is observable, so this observation discriminates. The mtime sentinel is
# the no-churn half: a hit that rewrote the file would bump it past the
# sentinel planted just after it.
H10="$WORK/h10"
C10="$(cache_path "$H10/.claude" "rate-limit-guard")"
PIN1="$(plant_tee "$H10" "mkt" "rate-limit-guard" "0.1.0" "pin1")"
make_wrapped "$H10/render.sh" 0
run "$H10" bash "$H10/render.sh"
assert_contains "$ERR" "TEE:pin1" "the first render resolves by glob"
assert_eq "$PIN1" "$(cache_line "$C10")" "a miss remembers the resolved tee path"
touch -t 202001010000 "$C10"
touch -t 202001020000 "$H10/sentinel"
PIN2="$(plant_tee "$H10" "mkt" "rate-limit-guard" "0.2.0" "pin2")"
touch -t 203001010000 "$PIN2"
run "$H10" bash "$H10/render.sh"
assert_contains "$ERR" "TEE:pin1" "the cached tee wins over a newer unmarked version"
assert_not_contains "$ERR" "TEE:pin2" "the newer unmarked version does not also run"
UNTOUCHED="no"
[[ "$H10/sentinel" -nt "$C10" ]] && UNTOUCHED="yes"
assert_eq "yes" "$UNTOUCHED" "a cache hit rewrites nothing"

# --- 18. a hit skips the glob entirely, proven by xtrace --------------------
# Case 17 alone cannot show this: a shim that globbed first and then preferred a
# valid cached path would resolve the same tee at exactly today's cost, and the
# cost is the whole point. The first assertion names the shim's own loop
# variable deliberately: it is a WHITE-BOX cost assertion, and the trace is the
# only place the absence of a walk is observable through a transparent shim.
# Several candidates are planted because the miss trace grows with them while
# the hit trace does not, which is what makes the length comparison meaningful.
H11="$WORK/h11"
plant_tee "$H11" "mkt-a" "rate-limit-guard" "0.1.0" "t1" >/dev/null
plant_tee "$H11" "mkt-b" "rate-limit-guard" "0.2.0" "t2" >/dev/null
plant_tee "$H11" "temp_git_1784663154120_zzzzzz" "rate-limit-guard" "0.3.0" "t3" >/dev/null
plant_tee "$H11" "mkt-c" "rate-limit-guard" "0.4.0" "t4" >/dev/null
make_wrapped "$H11/render.sh" 0
MISS_TRACE="$WORK/trace-miss.txt"
HIT_TRACE="$WORK/trace-hit.txt"
trace_run "$H11" "$MISS_TRACE" bash "$H11/render.sh"
trace_run "$H11" "$HIT_TRACE" bash "$H11/render.sh"
# Positive control first: without it, a bash that ever traced the loop
# differently would make the hit assertion below pass while the loop ran.
assert_contains "$(<"$MISS_TRACE")" "for cand in" "the probe can see the glob loop at all"
assert_not_contains "$(<"$HIT_TRACE")" "for cand in" "a cache hit never enters the glob loop"
MISS_LINES="$(wc -l <"$MISS_TRACE" | tr -d ' ')"
HIT_LINES="$(wc -l <"$HIT_TRACE" | tr -d ' ')"
SHORTER="no"
((HIT_LINES < MISS_LINES)) && SHORTER="yes"
assert_eq "yes" "$SHORTER" "the hit trace is strictly shorter than the miss trace ($HIT_LINES vs $MISS_LINES)"

# --- 19. deleting the cache file makes the next render re-glob --------------
rm -f "$C10"
run "$H10" bash "$H10/render.sh"
assert_contains "$ERR" "TEE:pin2" "a deleted cache file re-globs and picks the newer version"
assert_eq "$PIN2" "$(cache_line "$C10")" "the re-glob remembers the new answer"

# --- 20. an orphan-marked cached version directory is rejected --------------
# The update path, and the reason the marker is the PRIMARY cache invalidator:
# without it the cached v1 would keep winning forever.
H12="$WORK/h12"
C12="$(cache_path "$H12/.claude" "rate-limit-guard")"
ORPH1="$(plant_tee "$H12" "mkt" "rate-limit-guard" "0.1.0" "orph1")"
make_wrapped "$H12/render.sh" 0
run "$H12" bash "$H12/render.sh"
ORPH2="$(plant_tee "$H12" "mkt" "rate-limit-guard" "0.2.0" "orph2")"
orphan_tee "$ORPH1"
run "$H12" bash "$H12/render.sh"
assert_contains "$ERR" "TEE:orph2" "an orphan-marked cached version directory re-globs"
assert_eq "$ORPH2" "$(cache_line "$C12")" "the re-glob replaces the orphaned cache entry"

# --- 21. a cached tee that no longer exists is rejected ---------------------
# The end of the ~14-day grace period: the version directory is finally pruned.
H13="$WORK/h13"
C13="$(cache_path "$H13/.claude" "rate-limit-guard")"
PRUNE1="$(plant_tee "$H13" "mkt" "rate-limit-guard" "0.1.0" "prune1")"
make_wrapped "$H13/render.sh" 0
run "$H13" bash "$H13/render.sh"
PRUNE2="$(plant_tee "$H13" "mkt" "rate-limit-guard" "0.2.0" "prune2")"
rm -rf "${PRUNE1%/scripts/statusline-tee.sh}"
run "$H13" bash "$H13/render.sh"
assert_contains "$ERR" "TEE:prune2" "a pruned cached version directory re-globs"
assert_eq "$PRUNE2" "$(cache_line "$C13")" "the re-glob replaces the pruned cache entry"

# --- 22. each effective config dir keeps its own cache file -----------------
# A relocated CLAUDE_CONFIG_DIR and the $HOME default must never answer for one
# another, which is why the cache is anchored on the effective config dir and
# not on $HOME the way the tee's own files are.
H14="$WORK/h14"
CFG2="$WORK/cfg-two"
plant_tee "$WORK/reloc2" "some-marketplace" "rate-limit-guard" "0.1.0" "cfgtee" >/dev/null
mv "$WORK/reloc2/.claude" "$CFG2"
CFGTEE="$CFG2/plugins/cache/some-marketplace/rate-limit-guard/0.1.0/scripts/statusline-tee.sh"
HOMETEE="$(plant_tee "$H14" "some-marketplace" "rate-limit-guard" "0.1.0" "hometee")"
make_wrapped "$WORK/render-two.sh" 0
run_cfg "$H14" "$CFG2" bash "$WORK/render-two.sh"
assert_contains "$ERR" "TEE:cfgtee" "a relocated config dir resolves its own tee"
assert_eq "$CFGTEE" "$(cache_line "$(cache_path "$CFG2" "rate-limit-guard")")" \
  "the relocated config dir's cache lives under that config dir"
run "$H14" bash "$WORK/render-two.sh"
assert_contains "$ERR" "TEE:hometee" "the HOME default resolves its own tee, not the relocated one"
assert_eq "$HOMETEE" "$(cache_line "$(cache_path "$H14/.claude" "rate-limit-guard")")" \
  "the HOME default keeps a cache file of its own"

# --- 23. a temp_* marketplace is never the cached answer --------------------
# Both directions: the glob never records one, and a cache file naming one is
# rejected on read rather than exec'd.
H15="$WORK/h15"
C15="$(cache_path "$H15/.claude" "rate-limit-guard")"
TREAL="$(plant_tee "$H15" "melodic-software" "rate-limit-guard" "0.1.0" "treal")"
TTEMP="$(plant_tee "$H15" "temp_git_1784663154120_oirbvy" "rate-limit-guard" "0.1.0" "ttemp")"
touch -t 202001010000 "$TREAL"
touch -t 203001010000 "$TTEMP" # newer, and must still lose
make_wrapped "$H15/render.sh" 0
run "$H15" bash "$H15/render.sh"
assert_eq "$TREAL" "$(cache_line "$C15")" "a temp_* clone is never the cached answer"
printf '%s\n' "$TTEMP" >"$C15"
run "$H15" bash "$H15/render.sh"
assert_not_contains "$ERR" "TEE:ttemp" "a cache file naming a temp_* clone is rejected"
assert_contains "$ERR" "TEE:treal" "the rejected cache re-globs to the real marketplace"

# --- 24. chained shims keep separate cache files ----------------------------
# The sibling shim differs from this one only in PLUGIN_NAME, so a cache path
# not derived from it would make both links resolve the same tee.
H16="$WORK/h16"
CRLG="$(plant_tee "$H16" "melodic-software" "rate-limit-guard" "0.1.0" "crlg")"
CCG="$(plant_tee "$H16" "melodic-software" "context-guard" "0.1.0" "ccg")"
make_wrapped "$H16/render.sh" 0
run "$H16" bash "$SIB" bash "$H16/render.sh"
assert_eq "$CRLG" "$(cache_line "$(cache_path "$H16/.claude" "rate-limit-guard")")" \
  "chain: this shim caches under its own plugin name"
assert_eq "$CCG" "$(cache_line "$(cache_path "$H16/.claude" "context-guard")")" \
  "chain: the sibling shim caches under a different plugin name"
run "$H16" bash "$SIB" bash "$H16/render.sh"
assert_contains "$ERR" "TEE:crlg" "chain: this plugin's tee still runs from its cache"
assert_contains "$ERR" "TEE:ccg" "chain: the sibling's tee still runs from its own cache"

# --- 25. no tee found writes nothing ----------------------------------------
# Never negatively cached: not even the directory is created, so installing the
# plugin takes effect on the very next render instead of after a sentinel ages
# out. This case asserts an absence, so it also holds for a shim with no cache
# at all; PLAN criterion 8 requires it anyway, as the guard against a sentinel
# being added later.
H17="$WORK/h17"
C17="$(cache_path "$H17/.claude" "rate-limit-guard")"
plant_tee "$H17" "mkt" "context-guard" "0.1.0" "notmine" >/dev/null
make_wrapped "$H17/render.sh" 0
run "$H17" bash "$H17/render.sh"
MADE_DIR="no"
[[ -d "${C17%/*}" ]] && MADE_DIR="yes"
assert_eq "no" "$MADE_DIR" "no tee found creates no directory"
assert_eq "" "$(cache_line "$C17")" "no tee found writes no cache file"

# --- 26. a symlinked version directory is never pinned ----------------------
# A development checkout symlinked into the cache is never marked orphaned and
# never pruned, so neither the orphan test nor the existence test could ever
# release it: caching one would pin the dev checkout permanently and installing
# the real marketplace copy would never take effect. Rejecting it puts that
# operator back on exactly the glob behavior at exactly the pre-cache cost.
# `ln -s` under Git Bash writes a COPY unless MSYS picks a symlink strategy.
# winsymlinks:sys is the one that needs no elevation (nativestrict fails with
# "Operation not permitted" without the privilege, and a junction is a
# different object), and MSYS is inert on Linux and macOS, where ln -s already
# links. On a host that can plant no symlink at all this case fails loudly
# rather than skipping, which is the suite's only channel and matches the rest
# of it.
H18="$WORK/h18"
C18="$(cache_path "$H18/.claude" "rate-limit-guard")"
DEVSRC="$(plant_tee "$WORK/devsrc" "mkt" "rate-limit-guard" "9.9.9" "devco")"
DEVLINKDIR="$H18/.claude/plugins/cache/mkt/rate-limit-guard/9.9.9"
mkdir -p "${DEVLINKDIR%/*}"
MSYS=winsymlinks:sys ln -s "${DEVSRC%/scripts/statusline-tee.sh}" "$DEVLINKDIR"
make_wrapped "$H18/render.sh" 0
run "$H18" bash "$H18/render.sh"
assert_contains "$ERR" "TEE:devco" "a symlinked development checkout still resolves"
# Not merely rejected on read: never written. Recording it would make every
# later render fail the hit test, re-elect the same symlink and rewrite the
# file, which is strictly more work than the pre-cache walk.
assert_eq "" "$(cache_line "$C18")" "a symlinked resolution is never cached"
SYMREAL="$(plant_tee "$H18" "mkt" "rate-limit-guard" "0.2.0" "symreal")"
touch -t 203001010000 "$SYMREAL"
run "$H18" bash "$H18/render.sh"
assert_contains "$ERR" "TEE:symreal" "a symlinked cached version directory is rejected and re-globs"
assert_not_contains "$ERR" "TEE:devco" "the symlinked development checkout is not pinned"
# The READ-side guard needs its own fixture. The write-side guard keeps this
# cache file empty, so nothing above ever reaches the read test, and deleting
# `! -L "$cdir"` from the hit path breaks nothing. Plant the symlinked path by
# hand, which is the state an older revision of the shim would have left.
printf '%s\n' "$DEVLINKDIR/scripts/statusline-tee.sh" >"$C18"
run "$H18" bash "$H18/render.sh"
assert_not_contains "$ERR" "TEE:devco" "a hand-planted symlinked cache entry is rejected on read"
assert_contains "$ERR" "TEE:symreal" "the rejected symlink entry re-globs to the installed version"

# --- 27. a cached path carrying dot segments is rejected --------------------
# Without `dotglob` the resolving glob's `*` never matches a leading dot, so a
# cached `.` or `..` segment names a path the glob could not have produced. A
# pair of `..` segments reaches ABOVE the cache root entirely, and `..` also
# disarms the symlink guard structurally, because a version directory spelled
# `<something>/..` is never itself a link. The escape target is a REAL runnable
# tee, so this case fails if the path is accepted rather than passing merely
# because the file was missing.
H19="$WORK/h19"
C19="$(cache_path "$H19/.claude" "rate-limit-guard")"
DOTREAL="$(plant_tee "$H19" "mkt" "rate-limit-guard" "0.1.0" "dotreal")"
CACHEROOT="$H19/.claude/plugins/cache"
# Both escape targets have to be genuinely REACHABLE, or the case passes
# because a component was missing rather than because the dot test rejected
# it. `..` only traverses through directories that exist, so the intermediate
# <plugins>/rate-limit-guard is planted too.
ESCAPED="$H19/.claude/plugins/scripts"
mkdir -p "$ESCAPED" "$H19/.claude/plugins/rate-limit-guard" "$CACHEROOT/rate-limit-guard/scripts"
sed 's/TEE:dotreal/TEE:escaped/' "$DOTREAL" >"$ESCAPED/statusline-tee.sh"
sed 's/TEE:dotreal/TEE:escaped/' "$DOTREAL" >"$CACHEROOT/rate-limit-guard/scripts/statusline-tee.sh"
make_wrapped "$H19/render.sh" 0
# One ordinary render first, so the shim creates its own directory. Writing the
# fixture cache before it exists would fail silently (the suite sets no -e) and
# the case would then pass for the wrong reason.
run "$H19" bash "$H19/render.sh"
assert_eq "$DOTREAL" "$(cache_line "$C19")" "the dot-segment fixture starts from a real cached resolution"
printf '%s\n' "$CACHEROOT/../rate-limit-guard/../scripts/statusline-tee.sh" >"$C19"
run "$H19" bash "$H19/render.sh"
assert_not_contains "$ERR" "TEE:escaped" "a cached path with .. segments never escapes the cache root"
assert_contains "$ERR" "TEE:dotreal" "the rejected .. path re-globs to the real tee"
printf '%s\n' "$CACHEROOT/./rate-limit-guard/./scripts/statusline-tee.sh" >"$C19"
run "$H19" bash "$H19/render.sh"
assert_not_contains "$ERR" "TEE:escaped" "a cached path with . segments does not reach the planted decoy"
assert_contains "$ERR" "TEE:dotreal" "a cached path with . segments is rejected and re-globs"

# --- 28. every other malformed cache shape falls back to the glob -----------
# The header's broadest safety claim is that an empty, truncated, stale or
# hand-edited cache file costs one walk and never a wrong exec. Cases 20, 21,
# 23 and 26 each exercise a SHAPE-VALID path failing a filesystem test; these
# are the shape failures themselves. The decoy outside the cache root is a real
# runnable tee, so an accepted path runs it and the case fails loudly.
H20="$WORK/h20"
C20="$(cache_path "$H20/.claude" "rate-limit-guard")"
SHAPEREAL="$(plant_tee "$H20" "mkt" "rate-limit-guard" "0.1.0" "shapereal")"
DECOY="$H20/decoy-tee.sh"
sed 's/TEE:shapereal/TEE:decoy/' "$SHAPEREAL" >"$DECOY"
# Every decoy below is a REAL runnable tee at the exact path its cache line
# names. Without that, a shape case passes because -f found nothing rather than
# because the shape test rejected it, which is the trap case 27 already names.
DEEPDIR="$H20/.claude/plugins/cache/mkt/rate-limit-guard/0.1.0/extra/scripts"
mkdir -p "$DEEPDIR"
sed 's/TEE:shapereal/TEE:deepdecoy/' "$SHAPEREAL" >"$DEEPDIR/statusline-tee.sh"
# The cache-root anchor is only reachable with a RELATIVE cache line: an
# absolute path outside the cache leaves the prefix strip a no-op and is
# rejected by the empty-marketplace test instead, so it never consults the
# anchor. This one decomposes perfectly and resolves against the process cwd.
RELDIR="$WORK/relmkt/rate-limit-guard/0.1.0/scripts"
mkdir -p "$RELDIR"
sed 's/TEE:shapereal/TEE:reldecoy/' "$SHAPEREAL" >"$RELDIR/statusline-tee.sh"
make_wrapped "$H20/render.sh" 0
run "$H20" bash "$H20/render.sh"
# Written flat rather than in a loop: the suite reconciles PASS+FAIL against a
# COLUMN-ANCHORED count of assert_ calls, and a loop body would indent these
# out of that count.
printf '\n' >"$C20"
run "$H20" bash "$H20/render.sh"
assert_contains "$ERR" "TEE:shapereal" "an empty cache line re-globs"
printf '%s\n' "$DECOY" >"$C20"
run "$H20" bash "$H20/render.sh"
assert_not_contains "$ERR" "TEE:decoy" "a cache line naming a tee outside the cache root is never exec'd"
assert_contains "$ERR" "TEE:shapereal" "the outside-the-cache line re-globs"
printf '%s\n' "${SHAPEREAL%/statusline-tee.sh}" >"$C20"
run "$H20" bash "$H20/render.sh"
assert_contains "$ERR" "TEE:shapereal" "a cache line missing the tee filename re-globs"
printf '%s\n' "$DEEPDIR/statusline-tee.sh" >"$C20"
run "$H20" bash "$H20/render.sh"
assert_not_contains "$ERR" "TEE:deepdecoy" "a cache line one directory too deep is never exec'd"
assert_contains "$ERR" "TEE:shapereal" "a cache line one directory too deep re-globs"
printf '%s\n' "  $SHAPEREAL" >"$C20"
run "$H20" bash "$H20/render.sh"
assert_contains "$ERR" "TEE:shapereal" "a cache line with leading whitespace re-globs"
printf '%s\r\n' "$SHAPEREAL" >"$C20"
run "$H20" bash "$H20/render.sh"
assert_contains "$ERR" "TEE:shapereal" "a cache line with a trailing carriage return re-globs"
# Relative line: run from $WORK so the decoy is reachable from the cwd the
# shim inherits, which is the only way the cache-root anchor is load-bearing.
printf '%s\n' "relmkt/rate-limit-guard/0.1.0/scripts/statusline-tee.sh" >"$C20"
CWD_BEFORE="$PWD"
cd "$WORK" || exit 1
run "$H20" bash "$H20/render.sh"
cd "$CWD_BEFORE" || exit 1
assert_not_contains "$ERR" "TEE:reldecoy" "a relative cache line is never resolved against the cwd"
assert_contains "$ERR" "TEE:shapereal" "a relative cache line re-globs"

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0))
