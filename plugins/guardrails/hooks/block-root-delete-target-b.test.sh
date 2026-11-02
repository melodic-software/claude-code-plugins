#!/usr/bin/env bash
# Contract test for block-root-delete-target.sh (guardrails plugin), part b of 5:
# sections 2c to 2j. The parts are block-root-delete-target.test.sh and
# block-root-delete-target-b.test.sh to -e.test.sh; block-root-delete-target-fixtures.sh
# holds what they share.
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained, with
# no host-repo assertion library.
#
# The core table runs through expect_both, so every verdict is asserted twice:
# once with the guard alone, and once under hooks/run-guards.sh. A guard that
# decides one way by itself and another under the dispatcher is a failure here
# rather than a blind spot.
#
# The guard is NOT host-gated, so no case forces OSTYPE: a recursive delete of
# `/`, of `~`, of `$HOME`, or with --no-preserve-root is unrecoverable on every
# host this plugin runs on, and CI is Linux.
#
# File-wide, and deliberate: every command string below is a LITERAL the guard
# must read exactly as an operator wrote it. `$HOME` and `${HOME}` are matched
# as text, because the guard never evaluates an expansion (SC2016), and `\\` is
# a real pair of backslashes rather than an escaped quote (SC1003). Expanding
# either here would test something other than what the guard sees.
# shellcheck disable=SC2016,SC1003

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=block-root-delete-target-fixtures.sh
source "$HOOK_DIR/block-root-delete-target-fixtures.sh"

# --- 2c. The allow corpus again, with a payload cwd ---------------------------
# A subset of section 2 re-run from the checkout toplevel. The expected flips
# are the targets outside the tree and temp: HOME, a drive, a root-level glob,
# a UNC path, and a `~name` prefix. Everything under the tree, under temp, or
# unplaceable keeps its allow.
while IFS='|' read -r rdt_want rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "with cwd: $rdt_cmd" "$rdt_want" "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
0|rm -rf ./build dist
0|rm -rf build/
0|rm -rf /tmp/x
0|rm -rf "$TMPDIR/x"
2|rm -rf ~/.cache/foo
2|rm -rf $HOME/x
2|rm -rf C:/build/x
2|rm -rf /c/build/x
2|rm -rf /tmp*
2|rm -rf ~/proj*
2|rm -rf /c/dev/*
2|rm -rf /_
0|rm -rf *
2|rm -rf /c*
2|rm -rf ~*
2|rm -rf //server/share/dir
0|bash -c "rm -rf ./build"
0|eval "rm -rf ./build"
0|echo "$(rm -rf ./build)"
0|env -S 'rm -rf ./build'
0|taskset 1 rm -rf ./build
0|flock /tmp/l rm -rf ./build
0|rm.EXE -rf ./build
0|su -c 'rm -rf ./build'
0|runuser -u bob -- rm -rf ./build
0|coproc shredder rm -rf ./build
0|{ rm -rf ./build; }
0|rm -f /file
0|git rm -rf src
0|rm -rf
EOF
# The escapes collapse to `\servershare`, a root-level name outside the tree.
# portability-ok: a literal backslash pair in a command string fed to the guard, not a grep -E escape
expect_both 'with cwd: rm -rf \\server\share' 2 "${RDT_CWD[@]}" --command 'rm -rf \\server\share'

# --- 2d. block_root_delete_target_allowed_roots -------------------------------
# A user-owned userConfig key adds roots on the temp-root rule. The fixture sits
# under the checkout's gitignored .work, outside every temp root, and every case
# runs from cwd `/`, outside any tree, so only the key can let a delete through:
# each allow is paired with the same command blocking while the key is unset.
# HOME is a fake directory beside the roots.
rdt_allowed_roots_fixture

rdt_ar 'unset key: a path under the root blocks' 2 "rm -rf '$RDT_AR/child'"
rdt_ar 'a path under the root allowed' 0 "rm -rf '$RDT_AR/child'" "$RDT_AR"
rdt_ar 'a deeper nonexistent path allowed' 0 "rm -rf '$RDT_AR/a/b/c'" "$RDT_AR"
rdt_ar 'unset key: a glob below a subdirectory blocks' 2 "rm -rf '$RDT_AR/child'/*"
rdt_ar 'a glob below a subdirectory allowed' 0 "rm -rf '$RDT_AR/child'/*" "$RDT_AR"
rdt_ar 'unset key: */x under the root blocks' 2 "rm -rf '$RDT_AR'/*/x"
rdt_ar '*/x under the root allowed' 0 "rm -rf '$RDT_AR'/*/x" "$RDT_AR"
rdt_ar 'unset key: a second root blocks' 2 "rm -rf '$RDT_AR2/child'"
rdt_ar 'a second root alone blocks the first root' 2 "rm -rf '$RDT_AR/child'" "$RDT_AR2"
rdt_ar 'a second comma-separated root allowed' 0 "rm -rf '$RDT_AR2/child'" "$RDT_AR,$RDT_AR2"
rdt_ar 'the first of two roots allowed' 0 "rm -rf '$RDT_AR/child'" "$RDT_AR,$RDT_AR2"
rdt_ar 'entries are trimmed' 0 "rm -rf '$RDT_AR2/child'" " $RDT_AR , $RDT_AR2 "
if MSYS=winsymlinks:lnk ln -s "$RDT_AR" "$RDT_AB/rootlink" 2>/dev/null && [[ -L "$RDT_AB/rootlink" ]]; then
  rdt_ar 'a symlinked root compares by real path' 0 "rm -rf '$RDT_AR/child'" "$RDT_AB/rootlink"
  rdt_ar 'a path through a symlinked root' 0 "rm -rf '$RDT_AB/rootlink/child'" "$RDT_AR"
  rdt_ar 'a symlinked root itself blocks' 2 "rm -rf '$RDT_AB/rootlink'" "$RDT_AB/rootlink"
else
  rdt_skip "ln -s makes no real symlink on this host (3 cases)"
fi

# Refused whatever is listed: the root, its glob, siblings, and every earlier
# refusal in the guard.
rdt_ar 'the root itself blocks' 2 "rm -rf '$RDT_AR'" "$RDT_AR"
rdt_ar 'the root with a trailing slash blocks' 2 "rm -rf '$RDT_AR/'" "$RDT_AR"
rdt_ar 'the root dot blocks' 2 "rm -rf '$RDT_AR/.'" "$RDT_AR"
rdt_ar 'the root glob blocks' 2 "rm -rf '$RDT_AR'/*" "$RDT_AR"
rdt_ar 'a child reached back to the root blocks' 2 "rm -rf '$RDT_AR/child/..'" "$RDT_AR"
rdt_ar 'a name-prefix sibling blocks' 2 "rm -rf '$RDT_AR-x/child'" "$RDT_AR"
rdt_ar 'a .. escape to a sibling blocks' 2 "rm -rf '$RDT_AR/../elsewhere'" "$RDT_AR"
rdt_ar 'a .. escape through a child blocks' 2 "rm -rf '$RDT_AR/child/../../elsewhere/x'" "$RDT_AR"
rdt_ar 'a sibling directory blocks' 2 "rm -rf '$RDT_AO/x'" "$RDT_AR"
rdt_ar 'rm -rf / blocks' 2 'rm -rf /' "$RDT_AR"
rdt_ar 'rm -rf ~ blocks' 2 'rm -rf ~' "$RDT_AR"
rdt_ar "rm -rf '\$HOME' blocks" 2 "rm -rf '\$HOME'" "$RDT_AR"
rdt_ar 'rm -rf "$HOME" blocks' 2 'rm -rf "$HOME"' "$RDT_AR"
rdt_ar 'rm -rf ${HOME} blocks' 2 'rm -rf ${HOME}' "$RDT_AR"
rdt_ar 'rm -rf ~/x blocks' 2 'rm -rf ~/x' "$RDT_AR"
rdt_ar '--no-preserve-root under the root blocks' 2 "rm -rf --no-preserve-root '$RDT_AR/child'" "$RDT_AR"
rdt_ar 'an empty operand blocks' 2 'rm -rf ""' "$RDT_AR"
rdt_ar 'a bare variable blocks' 2 'rm -rf $X' "$RDT_AR"
rdt_ar 'a bare variable beside an allowed path blocks' 2 "rm -rf '$RDT_AR/child' \$X" "$RDT_AR"
rdt_ar 'a root beside an allowed path blocks' 2 "rm -rf '$RDT_AR/child' /" "$RDT_AR"
rdt_ar 'a path outside beside an allowed one blocks' 2 "rm -rf '$RDT_AR/child' '$RDT_AO/x'" "$RDT_AR"
rdt_ar 'a drive root blocks' 2 'rm -rf C:/' "$RDT_AR"
rdt_ar 'a UNC share root blocks' 2 'rm -rf //server/share' "$RDT_AR"
rdt_ar 'a child shell outside the root blocks' 2 "bash -c 'rm -rf $RDT_AO/x'" "$RDT_AR"
rdt_ar 'a child shell under the root allowed' 0 "bash -c 'rm -rf $RDT_AR/child'" "$RDT_AR"
rdt_ar 'a cd out of the root then a relative delete blocks' 2 "cd '$RDT_AO' && rm -rf x" "$RDT_AR"

# HOME inside or above a listed root is never deletable through it.
rdt_ar 'HOME under the root blocks' 2 "rm -rf '$RDT_AR/h'" "$RDT_AR" "$RDT_AR/h"
rdt_ar 'a directory holding HOME blocks' 2 "rm -rf '$RDT_AR/h'" "$RDT_AR" "$RDT_AR/h/deep"
rdt_ar 'the root as HOME grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AR" "$RDT_AR"
rdt_ar 'a sibling of HOME under a listed root allowed' 0 "rm -rf '$RDT_AR/child'" "$RDT_AR" "$RDT_AR/h"

# A symlink inside a root that points outside is judged by where it points.
if MSYS=winsymlinks:lnk ln -s "$RDT_AO" "$RDT_AL/link" 2>/dev/null && [[ -L "$RDT_AL/link" ]]; then
  rdt_ar 'a real directory beside the link allowed' 0 "rm -rf '$RDT_AL/child'" "$RDT_AL"
  rdt_ar 'the link itself is unlinked, allowed' 0 "rm -rf '$RDT_AL/link'" "$RDT_AL"
  rdt_ar 'link/ out of the root blocks' 2 "rm -rf '$RDT_AL/link/'" "$RDT_AL"
  rdt_ar 'link/. out of the root blocks' 2 "rm -rf '$RDT_AL/link/.'" "$RDT_AL"
  rdt_ar 'a path through the link blocks' 2 "rm -rf '$RDT_AL/link/x'" "$RDT_AL"
  rdt_ar 'a */ glob matching the link blocks' 2 "rm -rf '$RDT_AL'/*/" "$RDT_AL"
  rdt_ar 'a */x glob through the link blocks' 2 "rm -rf '$RDT_AL'/*/x" "$RDT_AL"
  rdt_ar 'a cd into the link then a relative delete blocks' 2 "cd '$RDT_AL/link' && rm -rf x" "$RDT_AL"
else
  rdt_skip "ln -s makes no real symlink on this host (8 cases)"
fi

# An entry that grants nothing is ignored; the rest of the list still works.
# The relative entry drops a drive prefix (Windows toplevel is `D:/...`) or a
# leading slash, so it is relative on every host.
rdt_rel="$RDT_AR"
if [[ "$rdt_rel" =~ ^[A-Za-z]:/ ]]; then rdt_rel="${rdt_rel:3}"; else rdt_rel="${rdt_rel#/}"; fi
rdt_ar 'a relative root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$rdt_rel"
rdt_ar "the root '/' grants nothing" 2 "rm -rf '$RDT_AR/child'" /
# The guard drops `/` even where it maps to the Git install directory, which /opt lies under.
rdt_ar "the root '/' does not allow a top-level path" 2 'rm -rf /opt/rdt-allowed-x/y' /
rdt_ar 'an empty entry grants nothing' 2 "rm -rf '$RDT_AR/child'" ","
rdt_ar 'a root equal to HOME grants nothing' 2 "rm -rf '$RDT_AH/x'" "$RDT_AH"
rdt_ar 'HOME with a trailing slash grants nothing' 2 "rm -rf '$RDT_AH/x'" "$RDT_AH/"
rdt_ar 'a root holding HOME still refuses HOME itself' 2 "rm -rf '$RDT_AH'" "$RDT_AB"
rdt_ar 'a root holding HOME allows a sibling of HOME' 0 "rm -rf '$RDT_AO/x'" "$RDT_AB"
rdt_ar 'a trailing line break grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AR"$'\n'
rdt_ar 'a leading line break grants nothing' 2 "rm -rf '$RDT_AR/child'" $'\n'"$RDT_AR"
rdt_ar 'a line break entry beside a good one is skipped' 0 "rm -rf '$RDT_AR2/child'" "$RDT_AR"$'\n'",$RDT_AR2"
rdt_ar 'a .. root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AR/../root"
rdt_ar 'a .. root above the fixture grants nothing' 2 "rm -rf '$RDT_AO/x'" "$RDT_AR/.."
rdt_ar 'a * prefix entry does not reach below a matching child' 2 "rm -rf '$RDT_AR/child'" "$RDT_AB/ro*"
rdt_ar 'a bare * root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AB/*"
rdt_ar 'a ? root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AB/roo?"
rdt_ar 'a [ root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AB/roo[t]"
rdt_ar 'a UNC root grants nothing' 2 "rm -rf '$RDT_AR/child'" '//server/share'
rdt_ar 'a relative entry beside a good one is skipped' 0 "rm -rf '$RDT_AR/child'" "rel/root,$RDT_AR"
rdt_ar 'a .. entry beside a good one is skipped' 0 "rm -rf '$RDT_AR2/child'" "$RDT_AR/../root,$RDT_AR2"
rdt_ar 'a * entry beside a good one is skipped' 0 "rm -rf '$RDT_AR2/child'" "$RDT_AB/*,$RDT_AR2"
rdt_ar 'a root entry does not allow its sibling by prefix' 2 "rm -rf '$RDT_AB/root2/child'" "$RDT_AB/roo"

# A name-prefix entry (one trailing `*` after a literal name) allows a direct
# child of its directory whose name extends the prefix, and nothing else: the
# directory, the bare prefix, a sibling, a deeper path, a glob, a `..` and a
# symlink named like a child all stay refused (#6542).
RDT_PP="$RDT_AB/wt"
RDT_PX="$RDT_PP/.tmp-*"
mkdir -p "$RDT_PP/.tmp-6527/sub" "$RDT_PP/other-worktree" "$RDT_PP/.tmp-"
rdt_ar 'prefix: unset key, a matching child blocks' 2 "rm -rf '$RDT_PP/.tmp-6527'"
rdt_ar 'prefix: a matching child allowed' 0 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PX"
rdt_ar 'prefix: a matching child with a trailing slash allowed' 0 "rm -rf '$RDT_PP/.tmp-6527/'" "$RDT_PX"
rdt_ar 'prefix: a nonexistent matching child allowed' 0 "rm -rf '$RDT_PP/.tmp-new'" "$RDT_PX"
rdt_ar 'prefix: beside a directory entry allowed' 0 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_AR,$RDT_PX"
rdt_ar 'prefix: the directory itself blocks' 2 "rm -rf '$RDT_PP'" "$RDT_PX"
rdt_ar 'prefix: a sibling worktree blocks' 2 "rm -rf '$RDT_PP/other-worktree'" "$RDT_PX"
rdt_ar 'prefix: the bare prefix blocks' 2 "rm -rf '$RDT_PP/.tmp-'" "$RDT_PX"
rdt_ar 'prefix: a path below a matching child blocks' 2 "rm -rf '$RDT_PP/.tmp-6527/sub'" "$RDT_PX"
rdt_ar 'prefix: a matching child .. blocks' 2 "rm -rf '$RDT_PP/.tmp-6527/..'" "$RDT_PX"
rdt_ar 'prefix: a nested .tmp-x/../.. blocks' 2 "rm -rf '$RDT_PP/.tmp-6527/../..'" "$RDT_PX"
rdt_ar 'prefix: a .. escape to a sibling blocks' 2 "rm -rf '$RDT_PP/.tmp-6527/../other-worktree'" "$RDT_PX"
rdt_ar 'prefix: a trailing dot after the bare prefix blocks' 2 "rm -rf '$RDT_PP/.tmp-.'" "$RDT_PX"
rdt_ar 'prefix: a matching name with a trailing dot blocks' 2 "rm -rf '$RDT_PP/.tmp-6527.'" "$RDT_PX"
rdt_ar 'prefix: a matching name with a trailing space blocks' 2 "rm -rf '$RDT_PP/.tmp-6527 '" "$RDT_PX"
rdt_ar 'prefix: a nonexistent child/ blocks' 2 "rm -rf '$RDT_PP/.tmp-new/'" "$RDT_PX"
rdt_ar 'prefix: a nonexistent child/. blocks' 2 "rm -rf '$RDT_PP/.tmp-new/.'" "$RDT_PX"
rdt_ar 'prefix: a link made in the same command, then link/, blocks' 2 "ln -s '$RDT_AO' '$RDT_PP/.tmp-made' && rm -rf '$RDT_PP/.tmp-made/'" "$RDT_PX"
rdt_ar 'prefix: the glob of the prefix blocks' 2 "rm -rf '$RDT_PP'/.tmp-*" "$RDT_PX"
rdt_ar 'prefix: the glob of the directory blocks' 2 "rm -rf '$RDT_PP'/*" "$RDT_PX"
rdt_ar 'prefix: a glob below a matching child blocks' 2 "rm -rf '$RDT_PP/.tmp-6527'/*" "$RDT_PX"
rdt_ar 'prefix: a path outside blocks' 2 "rm -rf '$RDT_AO/x'" "$RDT_PX"
rdt_ar 'prefix: rm -rf / blocks' 2 'rm -rf /' "$RDT_PX"
rdt_ar 'prefix: a prefix under HOME grants nothing' 2 "rm -rf '$RDT_AH/.tmp-x'" "$RDT_AH/.tmp-*"
rdt_ar 'prefix: a root-level prefix grants nothing' 2 'rm -rf /.tmp-rdt-x' '/.tmp-*'
rdt_ar "prefix: a directory that resolves to '/' grants nothing" 2 'rm -rf /.tmp-rdt-x' '/./.tmp-*'
rdt_ar 'prefix: an empty name grants nothing' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PP/*"
rdt_ar 'prefix: a second glob character grants nothing' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PP/.tmp-?*"
rdt_ar 'prefix: a glob in the directory grants nothing' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_AB/w*/.tmp-*"
rdt_ar 'prefix: a .. in the directory grants nothing' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PP/../wt/.tmp-*"
rdt_ar 'prefix: a plain entry is not a prefix' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PP/.tmp-"
rdt_ar 'prefix: a VAR= prefix in the command grants nothing' 2 "$RDT_KEY='$RDT_PX' rm -rf '$RDT_PP/.tmp-6527'"
rdt_arp_pfx() { # <label> <want> <command>
  expect_both "allowed roots: PS prefix: $1" "$2" --tool PowerShell --cwd / --command "$3" -- "HOME=$RDT_AH" "$RDT_KEY=$RDT_PX"
}
rdt_arp_pfx 'Remove-Item on a matching child allowed' 0 "Remove-Item -Recurse -Force '$RDT_PP/.tmp-6527'"
rdt_arp_pfx 'Remove-Item on a sibling worktree blocks' 2 "Remove-Item -Recurse -Force '$RDT_PP/other-worktree'"
rdt_arp_pfx 'Remove-Item on a trailing-dot name blocks' 2 "Remove-Item -Recurse -Force '$RDT_PP/.tmp-6527.'"
if MSYS=winsymlinks:lnk ln -s "$RDT_AO" "$RDT_PP/.tmp-link" 2>/dev/null && [[ -L "$RDT_PP/.tmp-link" ]]; then
  rdt_ar 'prefix: a matching symlink out of the tree blocks' 2 "rm -rf '$RDT_PP/.tmp-link'" "$RDT_PX"
  rdt_ar 'prefix: a matching symlink/ out of the tree blocks' 2 "rm -rf '$RDT_PP/.tmp-link/'" "$RDT_PX"
  rdt_ar 'prefix: a path through a matching symlink blocks' 2 "rm -rf '$RDT_PP/.tmp-link/x'" "$RDT_PX"
  rdt_ar 'prefix: a matching symlink with a trailing dot blocks' 2 "rm -rf '$RDT_PP/.tmp-link.'" "$RDT_PX"
else
  rdt_skip "ln -s makes no real symlink on this host (4 cases)"
fi
# The user's own spelling on Windows: a drive-form entry, an MSYS-form operand.
if command -v cygpath >/dev/null 2>&1; then
  rdt_ar 'prefix: a drive-form entry allows an MSYS-form child' 0 "rm -rf '$RDT_PP/.tmp-6527'" "$(cygpath -m "$RDT_PP")/.tmp-*"
  rdt_ar 'prefix: a drive-form entry still blocks its directory' 2 "rm -rf '$RDT_PP'" "$(cygpath -m "$RDT_PP")/.tmp-*"
else
  rdt_skip "no cygpath on this host (2 cases)"
fi

# A segment entry (`<dir>/*/<name>`) allows a path strictly under <name> one
# directory level below <dir>, and nothing else: <name> itself, a sibling of
# it, a deeper level and a symlink stay refused, and a `*` that is not one
# whole segment, or a second `*`, grants nothing.
RDT_SR="$RDT_AB/wtroot"
RDT_SX="$RDT_SR/*/.work"
mkdir -p "$RDT_SR/wt-a/.work/tmp/sub" "$RDT_SR/wt-a/src" "$RDT_SR/wt-a/b/.work/tmp" "$RDT_SR/.work/tmp"
rdt_ar 'segment: unset key, a path under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'"
rdt_ar 'segment: a path under .work allowed' 0 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SX"
rdt_ar 'segment: a deeper path under .work allowed' 0 "rm -rf '$RDT_SR/wt-a/.work/tmp/sub'" "$RDT_SX"
rdt_ar 'segment: a nonexistent path under .work allowed' 0 "rm -rf '$RDT_SR/wt-new/.work/tmp'" "$RDT_SX"
rdt_ar 'segment: a glob below .work/tmp allowed' 0 "rm -rf '$RDT_SR/wt-a/.work/tmp'/*" "$RDT_SX"
rdt_ar 'segment: beside a directory entry allowed' 0 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_AR,$RDT_SX"
rdt_ar 'segment: a sibling of .work blocks' 2 "rm -rf '$RDT_SR/wt-a/src'" "$RDT_SX"
rdt_ar 'segment: .work itself blocks' 2 "rm -rf '$RDT_SR/wt-a/.work'" "$RDT_SX"
rdt_ar 'segment: .work with a trailing slash blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/'" "$RDT_SX"
rdt_ar 'segment: the glob of .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work'/*" "$RDT_SX"
rdt_ar 'segment: two levels under the directory blocks' 2 "rm -rf '$RDT_SR/wt-a/b/.work/tmp'" "$RDT_SX"
rdt_ar 'segment: zero levels under the directory blocks' 2 "rm -rf '$RDT_SR/.work/tmp'" "$RDT_SX"
rdt_ar 'segment: the one-level directory blocks' 2 "rm -rf '$RDT_SR/wt-a'" "$RDT_SX"
rdt_ar 'segment: the directory itself blocks' 2 "rm -rf '$RDT_SR'" "$RDT_SX"
rdt_ar 'segment: a .. escape to a sibling blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/../src'" "$RDT_SX"
rdt_ar 'segment: a one-level name ending in a dot blocks' 2 "rm -rf '$RDT_SR/.../.work/tmp'" "$RDT_SX"
rdt_ar 'segment: a dots-only name under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/...'" "$RDT_SX"
rdt_ar 'segment: a space-only name under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/ '" "$RDT_SX"
rdt_ar 'segment: a name ending in a dot under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp.'" "$RDT_SX"
rdt_ar 'segment: a nonexistent child/ under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/new/'" "$RDT_SX"
rdt_ar 'segment: a path outside blocks' 2 "rm -rf '$RDT_AO/x'" "$RDT_SX"
rdt_ar 'segment: a * inside a segment grants nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SR/wt-*/.work"
rdt_ar 'segment: a * inside the name grants nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SR/*/.wor*"
rdt_ar 'segment: two * segments grant nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_AB/*/*/.work"
rdt_ar 'segment: a * before a two-part tail grants nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SR/*/.work/tmp"
rdt_ar 'segment: a .. in the directory grants nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SR/../wtroot/*/.work"
rdt_ar 'segment: HOME as the directory grants nothing' 2 "rm -rf '$RDT_AH/x/.work/y'" "$RDT_AH/*/.work"
rdt_ar 'segment: a root-level directory grants nothing' 2 'rm -rf /rdt-x/.work/y' '/*/.work'
# A glob before the last component that matches nothing is judged by the
# literal directory in front of it, with what it deletes two levels below:
# .work itself is then enough, and the one-level directory still is not.
rdt_ar 'segment: an unmatched */x below .work allowed' 0 "rm -rf '$RDT_SR/wt-a/.work'/*/x" "$RDT_SX"
rdt_ar 'segment: an unmatched */x below the one-level directory blocks' 2 "rm -rf '$RDT_SR/wt-a'/*/x" "$RDT_SX"
if MSYS=winsymlinks:lnk ln -s "$RDT_AO" "$RDT_SR/wt-a/.work/link" 2>/dev/null && [[ -L "$RDT_SR/wt-a/.work/link" ]]; then
  rdt_ar 'segment: a symlink under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/link'" "$RDT_SX"
  rdt_ar 'segment: a path through a symlink under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/link/x'" "$RDT_SX"
else
  rdt_skip "ln -s makes no real symlink on this host (2 cases)"
fi

# A per-machine pair under one fake HOME: a worktree-root name prefix and a
# home .work directory. The intended targets pass; the worktree root, a sibling
# worktree, .work itself and HOME stay refused.
RDT_WH="$RDT_AB/wthome"
RDT_WK="$RDT_WH/worktrees/.tmp-*,$RDT_WH/.work"
mkdir -p "$RDT_WH/worktrees/.tmp-x" "$RDT_WH/worktrees/other" "$RDT_WH/.work/x"
rdt_ar 'pair: a .tmp- worktree child allowed' 0 "rm -rf '$RDT_WH/worktrees/.tmp-x'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: a path under HOME .work allowed' 0 "rm -rf '$RDT_WH/.work/x'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: the worktree root blocks' 2 "rm -rf '$RDT_WH/worktrees'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: a sibling worktree blocks' 2 "rm -rf '$RDT_WH/worktrees/other'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: .work itself blocks' 2 "rm -rf '$RDT_WH/.work'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: HOME blocks' 2 "rm -rf '$RDT_WH'" "$RDT_WK" "$RDT_WH"

# The key is read from the hook's own environment only. Naming it in the
# command text, as a prefix, an env launcher or an export, grants nothing.
rdt_ar 'a VAR= prefix in the command grants nothing' 2 "$RDT_KEY='$RDT_AR' rm -rf '$RDT_AR/child'"
rdt_ar 'an env launcher in the command grants nothing' 2 "env $RDT_KEY='$RDT_AR' rm -rf '$RDT_AR/child'"
rdt_ar 'an export in the command grants nothing' 2 "export $RDT_KEY='$RDT_AR'; rm -rf '$RDT_AR/child'"
rdt_ar 'a VAR= segment in the command grants nothing' 2 "$RDT_KEY='$RDT_AR'; rm -rf '$RDT_AR/child'"
rdt_ar 'a prefix cannot widen the listed roots' 2 "$RDT_KEY='$RDT_AR,$RDT_AO' rm -rf '$RDT_AO/x'" "$RDT_AR"

# The block message names the key and says the agent cannot set it.
guard_invoke --cwd / --command "rm -rf '$RDT_AO/x'" -- "HOME=$RDT_AH" "$RDT_KEY=$RDT_AR"
assert_exit 'allowed roots: a delete outside every root blocks' 2 "$GUARD_RC"
assert_contains 'allowed roots: the message names the key' "$GUARD_ERR" 'block_root_delete_target_allowed_roots'
assert_contains 'allowed roots: the message says only the user can set it' "$GUARD_ERR" 'only the user can'
assert_contains 'allowed roots: the message forbids a retry with another tool' "$GUARD_ERR" 'do not retry the delete with another tool (find -delete, rmtree, git clean)'

# PowerShell judges the same targets through the same arm.
rdt_arp 'unset key: Remove-Item under the root blocks' 2 "Remove-Item -Recurse -Force '$RDT_AR/child'"
rdt_arp 'Remove-Item under the root allowed' 0 "Remove-Item -Recurse -Force '$RDT_AR/child'" "$RDT_AR"
rdt_arp 'Remove-Item -LiteralPath under the root allowed' 0 "Remove-Item -LiteralPath '$RDT_AR/child' -Recurse" "$RDT_AR"
rdt_arp 'Remove-Item outside the root blocks' 2 "Remove-Item -Recurse -Force '$RDT_AO/x'" "$RDT_AR"
rdt_arp 'Remove-Item on the root itself blocks' 2 "Remove-Item -Recurse -Force '$RDT_AR'" "$RDT_AR"
rdt_arp 'Remove-Item on a sibling by prefix blocks' 2 "Remove-Item -Recurse -Force '$RDT_AR-x/child'" "$RDT_AR"
rdt_arp 'Remove-Item on a .. escape blocks' 2 "Remove-Item -Recurse -Force '$RDT_AR/../elsewhere'" "$RDT_AR"
rdt_arp 'Remove-Item on a drive root blocks' 2 'Remove-Item -Recurse -Force C:\' "$RDT_AR"
rdt_arp 'Remove-Item on $env:USERPROFILE blocks' 2 'Remove-Item -Recurse -Force $env:USERPROFILE' "$RDT_AR"
rdt_arp 'a $env: assignment in the command grants nothing' 2 "\$env:$RDT_KEY = '$RDT_AR'; Remove-Item -Recurse '$RDT_AR/child'"

# --- 2e. Protected trees (#9751) ----------------------------------------------
# Judged ahead of every root the outside-tree arm allows: the working tree, a
# temp root, the scratchpad and a listed root alike. Every fixture outside the
# checkout sits under the suite's temp directory, where the same delete passes
# without the arm, and each refusal is paired with an allow beside it.
expect_both 'protected: rm -rf .git blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .git'
expect_both 'protected: rm -rf ./.git/ blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ./.git/'
expect_both 'protected: the glob straight inside .git blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .git/*'
expect_both 'protected: a dot glob that matches .git blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .*'
expect_both 'protected: the toplevel itself blocks' 2 "${RDT_CWD[@]}" --command "rm -rf '$RDT_TOP'"
expect_both 'protected: the toplevel as . blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .'
expect_both 'protected: the toplevel as .. from a subdirectory blocks' 2 --cwd "$RDT_TOP/plugins" --command 'rm -rf ..'
expect_both 'protected: PS Remove-Item on .git blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'Remove-Item -Recurse -Force .git'
expect_both 'protected: a subdirectory of the toplevel allowed' 0 "${RDT_CWD[@]}" \
  --command 'rm -rf plugins/rdt-nonexistent/build'
expect_both 'protected: a path named under .git allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf .git/rdt-nonexistent-x'
expect_both 'protected: the toplevel glob leaves .git, allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf *'
# A glob matches dot names on PowerShell, and in bash once dotglob is on.
expect_both 'protected: PS Remove-Item * from the toplevel blocks (its * matches .git)' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'Remove-Item -Recurse -Force *'
# A bash child of the PowerShell tool globs as bash does: `*` skips .git.
expect_both 'protected: PS bash -c rm -rf * from the toplevel allowed (bash * skips .git)' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command "bash -c 'rm -rf *'"
expect_both 'protected: PS cmd /c bash -c rm -rf * from the toplevel allowed' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'cmd /c bash -c "rm -rf *"'
expect_both 'protected: PS bash -O dotglob -c rm -rf * blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "bash -O dotglob -c 'rm -rf *'"
expect_both 'protected: PS bash -c with shopt -s dotglob then rm -rf * blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "bash -c 'shopt -s dotglob; rm -rf *'"
expect_both 'protected: PS bash -c rm -rf * then Remove-Item * blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "bash -c 'rm -rf *'; Remove-Item -Recurse -Force *"
expect_both 'protected: PS Remove-Item * then bash -c rm -rf * blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force *; bash -c 'rm -rf *'"
expect_both 'protected: PS zsh -c rm -rf * keeps the PowerShell glob reading, blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "zsh -c 'rm -rf *'"
expect_both 'protected: PS wsl rm -rf * keeps the PowerShell glob reading, blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'wsl rm -rf *'
expect_both 'protected: dotglob then rm -rf * blocks' 2 "${RDT_CWD[@]}" --command 'shopt -s dotglob; rm -rf *'
expect_both 'protected: GLOBIGNORE then rm -rf * blocks' 2 "${RDT_CWD[@]}" --command 'GLOBIGNORE=x; rm -rf *'
# A case-insensitive filesystem removes .git through .GIT.
expect_both 'protected: rm -rf .GIT blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .GIT'
# Win32 trims a trailing dot or space, so `.git.` names `.git` there.
case "${OSTYPE:-}" in
msys* | cygwin* | win32)
  expect_both 'protected: PS Remove-Item on .git. blocks' 2 \
    --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force '.git.'"
  ;;
*) rdt_skip "a trailing-dot name is trimmed only on Windows (1 case)" ;;
esac

# A directory holding a .git is refused under temp too; a path inside it is
# not, and a symlink to it is unlinked, not followed.
mkdir -p "$TEST_TMPDIR/rdt-clone/.git" "$TEST_TMPDIR/rdt-clone/build"
expect_both 'protected: a throwaway clone under temp blocks' 2 "${RDT_CWD[@]}" \
  --command "rm -rf '$TEST_TMPDIR/rdt-clone'"
expect_both 'protected: a path inside that clone allowed' 0 "${RDT_CWD[@]}" \
  --command "rm -rf '$TEST_TMPDIR/rdt-clone/build'"
if MSYS=winsymlinks:lnk ln -s "$TEST_TMPDIR/rdt-clone" "$TEST_TMPDIR/rdt-clone-link" 2>/dev/null &&
  [[ -L "$TEST_TMPDIR/rdt-clone-link" ]]; then
  expect_both 'protected: a link to the clone is unlinked, allowed' 0 "${RDT_CWD[@]}" \
    --command "rm -rf '$TEST_TMPDIR/rdt-clone-link'"
  expect_both 'protected: link/ to the clone blocks' 2 "${RDT_CWD[@]}" \
    --command "rm -rf '$TEST_TMPDIR/rdt-clone-link/'"
else
  rdt_skip "ln -s makes no real symlink on this host (2 cases)"
fi

# Registered worktrees, from a registry built by hand the way git writes it,
# with a stub git that answers the given worktree as the toplevel. The guard
# reads <common dir>/worktrees/*/gitdir itself, so a root whose .git file is
# gone, one recorded by a relative path, a dot-named one and a directory
# holding one are refused, not only a root that holds its .git file.
rdt_worktree_fixture
rdt_wt 'a linked worktree root blocks' 2 "rm -rf '$RDT_WF/wt1'"
rdt_wt 'a registered root with no .git file blocks' 2 "rm -rf '$RDT_WF/wt-nogit'"
rdt_wt 'a root recorded by a relative path blocks' 2 "rm -rf '$RDT_WF/rel/wt2'"
rdt_wt 'a dot-named worktree blocks' 2 "rm -rf '$RDT_WF/.tmp-7'"
rdt_wt 'a directory holding a worktree root blocks' 2 "rm -rf '$RDT_WF/holder'"
rdt_wt 'a glob whose matches hold worktree roots blocks' 2 "rm -rf '$RDT_WF'/*"
rdt_wt 'the main worktree, the toplevel, blocks' 2 "rm -rf '$RDT_WF/main'"
rdt_wt 'a path under a worktree allowed' 0 "rm -rf '$RDT_WF/wt1/build'"
rdt_wt 'an unregistered sibling under temp allowed' 0 "rm -rf '$RDT_WF/other'"
rdt_wt 'from a linked worktree: the main root blocks' 2 "rm -rf '$RDT_WF/main'" "$RDT_WF/wt1"
rdt_wt 'from a linked worktree: a root with no .git file blocks' 2 "rm -rf '$RDT_WF/wt-nogit'" "$RDT_WF/wt1"
rdt_wt 'from a linked worktree: its own build allowed' 0 'rm -rf build' "$RDT_WF/wt1"

# Claude Code's temp tree, <base>/<project>/<session>/scratchpad. The payload
# scratchpad names the base: another session's scratchpad and every level that
# holds one are refused, and this session's scratchpad keeps its rules.
RDT_CB="$TEST_TMPDIR/claude-rdt"
RDT_OWN="$RDT_CB/-proj/sess-a/scratchpad"
RDT_OTH="$RDT_CB/-proj/sess-b/scratchpad"
mkdir -p "$RDT_OWN/x" "$RDT_OTH/x" "$RDT_CB/-proj/sess-b/tasks"
rdt_sp() { # <label> <want> <command>: from the checkout, with this session's scratchpad
  expect_both "protected: scratchpads: $1" "$2" --payload "$(rdt_pl "$3" "$RDT_TOP" "$RDT_OWN")"
}
rdt_sp "another session's scratchpad blocks" 2 "rm -rf '$RDT_OTH'"
rdt_sp "a path in another session's scratchpad blocks" 2 "rm -rf '$RDT_OTH/x'"
rdt_sp "another session's directory blocks" 2 "rm -rf '$RDT_CB/-proj/sess-b'"
rdt_sp "this session's directory blocks" 2 "rm -rf '$RDT_CB/-proj/sess-a'"
rdt_sp 'a project directory blocks' 2 "rm -rf '$RDT_CB/-proj'"
rdt_sp 'the base blocks' 2 "rm -rf '$RDT_CB'"
rdt_sp 'a glob over the sessions blocks' 2 "rm -rf '$RDT_CB/-proj/'*"
rdt_sp "a path in this session's scratchpad allowed" 0 "rm -rf '$RDT_OWN/x'"
rdt_sp "this session's scratchpad itself still blocks" 2 "rm -rf '$RDT_OWN'"
rdt_sp "another session's directory that is not its scratchpad allowed" 0 "rm -rf '$RDT_CB/-proj/sess-b/tasks'"
expect_both 'protected: scratchpads: with no payload scratchpad, that base is a plain temp path' 0 "${RDT_CWD[@]}" \
  --command "rm -rf '$RDT_OTH'"
# TMPDIR pointed at the base: the caller's own temp files there pass, and
# another session's scratchpad is still refused.
expect_both 'protected: scratchpads: TMPDIR at the base, a temp file there allowed' 0 \
  --payload "$(rdt_pl "rm -rf '$RDT_CB/rdt-own-tmp'" "$RDT_TOP" "$RDT_OWN")" -- "TMPDIR=$RDT_CB"
expect_both "protected: scratchpads: TMPDIR at the base, another session's scratchpad blocks" 2 \
  --payload "$(rdt_pl "rm -rf '$RDT_OTH'" "$RDT_TOP" "$RDT_OWN")" -- "TMPDIR=$RDT_CB"
# Without a payload scratchpad the base is <temp root>/claude-<uid>
# (<temp root>/claude on Windows); TMPDIR names a fixture temp root here.
RDT_TR="$TEST_TMPDIR/rdt-tmproot"
rdt_cn="claude-$UID"
case "${OSTYPE:-}" in
msys* | cygwin* | win32) rdt_cn=claude ;;
*) ;;
esac
mkdir -p "$RDT_TR/$rdt_cn/-p/s/scratchpad" "$RDT_TR/other"
expect_both "protected: scratchpads: one under <temp root>/$rdt_cn blocks" 2 "${RDT_CWD[@]}" \
  --command "rm -rf '$RDT_TR/$rdt_cn/-p/s/scratchpad'" -- "TMPDIR=$RDT_TR"
expect_both 'protected: scratchpads: a sibling under that temp root allowed' 0 "${RDT_CWD[@]}" \
  --command "rm -rf '$RDT_TR/other'" -- "TMPDIR=$RDT_TR"

# ~/.claude, from HOME, here a fake one under temp.
RDT_HF="$TEST_TMPDIR/rdt-home"
mkdir -p "$RDT_HF/.claude/projects" "$RDT_HF/other"
rdt_hc() { # <label> <want> <command>
  expect_both "protected: ~/.claude: $1" "$2" "${RDT_CWD[@]}" --command "$3" -- "HOME=$RDT_HF"
}
rdt_hc 'the directory blocks' 2 "rm -rf '$RDT_HF/.claude'"
rdt_hc 'a path under it blocks' 2 "rm -rf '$RDT_HF/.claude/projects'"
rdt_hc 'the ~ spelling blocks' 2 'rm -rf ~/.claude/projects'
rdt_hc 'a dot glob over HOME blocks' 2 "rm -rf '$RDT_HF/'.*"
rdt_hc 'a sibling under HOME allowed' 0 "rm -rf '$RDT_HF/other'"
rdt_hc 'a plain glob over HOME skips the dot name, allowed' 0 "rm -rf '$RDT_HF/'*"

# block_root_delete_target_protected_trees, read from the hook's environment.
RDT_PK=CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_PROTECTED_TREES
RDT_KP="$TEST_TMPDIR/rdt-keep"
mkdir -p "$RDT_KP/data/x" "$RDT_KP/scratch"
rdt_pt() { # <label> <want> <command> [trees]
  local -a env=()
  [[ -z "${4:-}" ]] || env+=("$RDT_PK=$4")
  expect_both "protected: listed trees: $1" "$2" "${RDT_CWD[@]}" --command "$3" -- ${env[@]+"${env[@]}"}
}
rdt_pt 'unset key: the tree under temp allowed' 0 "rm -rf '$RDT_KP/data'"
rdt_pt 'a listed tree blocks' 2 "rm -rf '$RDT_KP/data'" "$RDT_KP/data"
rdt_pt 'a path under a listed tree blocks' 2 "rm -rf '$RDT_KP/data/x'" "$RDT_KP/data"
rdt_pt 'a directory holding a listed tree blocks' 2 "rm -rf '$RDT_KP'" "$RDT_KP/data"
rdt_pt 'a glob whose matches reach a listed tree blocks' 2 "rm -rf '$RDT_KP/'*" "$RDT_KP/data"
rdt_pt 'a sibling of a listed tree allowed' 0 "rm -rf '$RDT_KP/scratch'" "$RDT_KP/data"
rdt_pt 'the second of two trimmed entries blocks' 2 "rm -rf '$RDT_KP/scratch'" " $RDT_KP/data , $RDT_KP/scratch "
rdt_pt 'a listed tree inside the working tree blocks' 2 'rm -rf .work/rdt-keep-x/y' "$RDT_TOP/.work/rdt-keep-x"
rdt_pt 'a relative entry protects nothing' 0 "rm -rf '$RDT_KP/data'" 'rel/data'
rdt_pt 'a .. entry protects nothing' 0 "rm -rf '$RDT_KP/data'" "$RDT_KP/scratch/../data"
rdt_pt 'a glob entry protects nothing' 0 "rm -rf '$RDT_KP/data'" "$RDT_KP/da*"
rdt_pt 'a bad entry beside a good one is skipped' 2 "rm -rf '$RDT_KP/data'" "rel/x,$RDT_KP/data"
rdt_pt "the root '/' protects nothing" 0 'rm -rf build' /
rdt_pt 'emptying the key in the command lifts nothing' 2 "$RDT_PK= rm -rf '$RDT_KP/data'" "$RDT_KP/data"
# Under an allowed root too: the same delete passes in section 2d.
expect_both 'protected: listed trees: a listed tree under an allowed root blocks' 2 --cwd / \
  --command "rm -rf '$RDT_AR/child'" -- "HOME=$RDT_AH" "$RDT_KEY=$RDT_AR" "$RDT_PK=$RDT_AR/child"

# The refusal says what the tree is, carries a Fix line, and asks when attended.
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf .git'
assert_exit 'protected: a .git delete exits 2' 2 "$GUARD_RC"
assert_contains 'protected: the message names what it removes' "$GUARD_ERR" 'a .git.'
assert_contains 'protected: the message names the class' "$GUARD_ERR" 'A protected tree is refused'
assert_contains 'protected: the message carries a Fix line' "$GUARD_ERR" 'Fix:'
guard_invoke "${RDT_CWD[@]}" --command "rm -rf '$RDT_KP/data'" -- "$RDT_PK=$RDT_KP/data"
assert_contains 'protected: a listed tree names the key' "$GUARD_ERR" 'a tree in block_root_delete_target_protected_trees'
expect 'protected: attended, a .git delete asks' 0 "${RDT_CWD[@]}" --command 'rm -rf .git' \
  -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq 'protected: attended, the decision is ask' ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"

# --- 2f. find deletes (#9752) -------------------------------------------------
# A find whose expression deletes (-delete, or an -exec, -execdir, -ok or
# -okdir whose command word is rm, rmdir or unlink) has each start point judged
# as an operand of a recursive rm. Every form runs against a root, HOME, a path
# outside the allowed roots and a path strictly inside the tree.
RDT_FIND_FORMS=(
  'find TGT -delete'
  "find -L TGT -name '*.o' -type f -delete"
  'find TGT -type d -name build -exec rm -rf {} +'
  'find TGT -execdir rm -f {} \;'
  "find TGT -ok /bin/rm {} ';'"
  'find TGT -okdir unlink {} \;'
  'find TGT -depth -type d -empty -exec rmdir {} +'
)
rdt_find() { # <label> <want> <start point> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_FIND_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "find: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_find 'a root blocks' 2 /
rdt_find 'HOME blocks' 2 '$HOME'
rdt_find 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_find 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'find: find ~ -delete blocks' 2 --command 'find ~ -delete'
expect_both 'find: a path under HOME blocks with a cwd' 2 "${RDT_CWD[@]}" --command 'find ~/Documents/x -delete'
expect_both 'find: a path under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'find /tmp/rdt-x -delete'
expect_both 'find: /tmp itself blocks' 2 "${RDT_CWD[@]}" --command 'find /tmp -name rdt-x -delete'
expect_both 'find: a path under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "find '$RDT_SPT/x' -exec rm -rf {} +" "$RDT_TOP" "$RDT_SPT")"
expect_both 'find: the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "find '$RDT_SPT' -name x -delete" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'find: unset key, a start point under the root blocks' 2 "find '$RDT_AR/child' -delete"
rdt_ar 'find: a start point under the root allowed' 0 "find '$RDT_AR/child' -delete" "$RDT_AR"
rdt_ar 'find: -exec rm under the root allowed' 0 "find '$RDT_AR/child' -name x -exec rm -rf {} +" "$RDT_AR"
rdt_ar 'find: the root itself blocks' 2 "find '$RDT_AR' -name x -delete" "$RDT_AR"
rdt_ar 'find: a start point outside the root blocks' 2 "find '$RDT_AO/x' -delete" "$RDT_AR"

# find descends into .git, so a find delete started at the toplevel is refused
# as a directory holding a .git whatever its filters; one started below passes.
expect_both 'find: . from the toplevel blocks' 2 "${RDT_CWD[@]}" --command "find . -name '*.pyc' -delete"
expect_both 'find: no start point from the toplevel is . and blocks' 2 "${RDT_CWD[@]}" \
  --command "find -name '*.pyc' -delete"
expect_both 'find: no start point from a subdirectory allowed' 0 --cwd "$RDT_TOP/plugins" \
  --command "find -name '*.pyc' -delete"
expect_both 'find: a .git start point blocks' 2 "${RDT_CWD[@]}" --command 'find .git -name x -exec rm {} +'
# GNU reads a first primary spelled -f... as the expression, so `.` is judged
# though BSD reads it as -f and a start point.
expect_both 'find: -fstype first still judges . from the toplevel' 2 "${RDT_CWD[@]}" \
  --command 'find -fstype ext4 -delete'
# With -files0-from GNU reads the start points from a file (a declared gap),
# so its reading adds no `.`; the BSD reading's names lie inside the tree.
expect_both 'find: -files0-from judges no . from the toplevel' 0 "${RDT_CWD[@]}" \
  --command 'find -files0-from list -delete'
# Under -H, -L or -follow find follows a start point that is a symlink, so it
# is judged by where it points; without them the link itself is the target.
if MSYS=winsymlinks:lnk ln -s /opt/rdt-link-target "$TEST_TMPDIR/rdt-find-link" 2>/dev/null &&
  [[ -L "$TEST_TMPDIR/rdt-find-link" ]]; then
  expect_both 'find: a link start point under temp, not followed, allowed' 0 "${RDT_CWD[@]}" \
    --command "find '$TEST_TMPDIR/rdt-find-link' -delete"
  expect_both 'find: -H follows a link start point outside, blocks' 2 "${RDT_CWD[@]}" \
    --command "find -H '$TEST_TMPDIR/rdt-find-link' -exec rm -rf {} +"
  expect_both 'find: -L follows it, blocks' 2 "${RDT_CWD[@]}" \
    --command "find -L '$TEST_TMPDIR/rdt-find-link' -delete"
  expect_both 'find: -follow follows it, blocks' 2 "${RDT_CWD[@]}" \
    --command "find '$TEST_TMPDIR/rdt-find-link' -follow -delete"
  # From a subdirectory, so the `.` the GNU reading adds is allowed.
  expect_both 'find: a BSD -xL cluster follows it, blocks' 2 --cwd "$RDT_TOP/plugins" \
    --command "find -xL '$TEST_TMPDIR/rdt-find-link' -delete"
  expect_both 'find: a BSD -x cluster does not follow it, allowed' 0 --cwd "$RDT_TOP/plugins" \
    --command "find -x '$TEST_TMPDIR/rdt-find-link' -delete"
  rm -f "$TEST_TMPDIR/rdt-find-link"
else
  rdt_skip "ln -s makes no real symlink on this host (6 cases)"
fi

# Leading options of either reading, a later start point, an action before
# -delete, and a find reached through a launcher, a child shell or a
# substitution.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "find: $rdt_cmd blocks" 2 --command "$rdt_cmd"
done <<'EOF'
find -H -P / -delete
find -D tree / -delete
find -O3 / -delete
find -- / -delete
find -x / -delete
find -dx -f / -name x -delete
find -sf/ -delete
find build / -delete
find / -exec echo {} \; -delete
/usr/bin/find / -delete
sudo find / -delete
bash -c 'find / -exec rm -rf {} +'
echo "$(find / -delete)"
EOF

# A find that does not delete, a deleter's name that is not an action's command
# word, a -delete inside an action's command, and the mechanism as quoted prose.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "find: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "find: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
find / -name rm -type f
find / -exec grep -l rm {} +
find / -exec echo -delete {} +
git commit -m "find / -delete"
git commit -m "find / -exec rm -rf {} +"
echo 'find ~ -okdir unlink {} \;'
EOF

guard_invoke "${RDT_CWD[@]}" --command 'find /opt/nonexistent-rdt/x -delete'
assert_exit 'find: outside the tree exits 2' 2 "$GUARD_RC"
assert_contains 'find: the refusal names the start point' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"
guard_invoke "${RDT_CWD[@]}" --command "find . -name '*.pyc' -delete"
assert_contains 'find: the toplevel refusal names the .git it holds' "$GUARD_ERR" 'a directory holding a .git'

# --- 2g. pipeline-fed deletes (#9754) -----------------------------------------
# xargs or parallel running a recursive delete takes its targets from the items
# it reads. A confined listing (a find without -printf or -exec, git ls-files),
# through line filters at most, has its targets judged as a recursive rm's; any
# other source is refused. Every form runs against a root, HOME, a path outside
# the allowed roots and a path strictly inside the tree.
RDT_PIPE_FORMS=(
  'find TGT -type f | xargs rm -rf'
  'find TGT -print0 | xargs -0 rm -rf --'
  "find TGT -name '*.o' | grep -v keep | sort -u | xargs -n 1 rm -rf"
  'find TGT -type d | head -n 5 | xargs -I{} rm -rf {}'
  'find TGT | xargs sudo rm -rf'
  'find TGT | parallel rm -rf'
  "find TGT | parallel -j 4 'rm -rf {}'"
)
rdt_pipe() { # <label> <want> <start point> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_PIPE_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "pipe: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_pipe 'a root blocks' 2 /
rdt_pipe 'HOME blocks' 2 '$HOME'
rdt_pipe 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_pipe 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'pipe: find ~ blocks' 2 --command 'find ~ -type f | xargs rm -rf'
expect_both 'pipe: a find under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'find /tmp/rdt-x -type f | xargs rm -rf'
expect_both 'pipe: a find under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "find '$RDT_SPT/x' -type f | xargs rm -rf" "$RDT_TOP" "$RDT_SPT")"
expect_both 'pipe: a find of the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "find '$RDT_SPT' -name x | xargs rm -rf" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'pipe: unset key, a find under the root blocks' 2 "find '$RDT_AR/child' -type f | xargs rm -rf"
rdt_ar 'pipe: a find under the root allowed' 0 "find '$RDT_AR/child' -type f | xargs rm -rf" "$RDT_AR"
rdt_ar 'pipe: a find of the root itself blocks' 2 "find '$RDT_AR' -name x | xargs rm -rf" "$RDT_AR"
expect_both 'pipe: a find from the toplevel blocks' 2 "${RDT_CWD[@]}" --command "find . -name '*.pyc' | xargs rm -rf"
expect_both 'pipe: a find run from another directory is judged from there' 2 "${RDT_CWD[@]}" \
  --command 'find build -type f | env -C /opt xargs rm -rf'
# git ls-files lists names strictly under the directory it runs from.
expect_both 'pipe: git ls-files inside the tree allowed' 0 "${RDT_CWD[@]}" --command 'git ls-files -z | xargs -0 rm -rf'
expect_both 'pipe: git ls-files from a subdirectory allowed' 0 --cwd "$RDT_TOP/plugins" \
  --command 'git ls-files --others --exclude-standard | grep -v keep | xargs rm -rf'
expect_both 'pipe: git ls-files with no tree blocks' 2 --cwd / --command 'git ls-files | xargs rm -rf'
expect_both 'pipe: git ls-files after a cd outside blocks' 2 "${RDT_CWD[@]}" \
  --command 'cd /opt && git ls-files | xargs rm -rf'
# parallel's ::: items are its targets.
expect_both 'pipe: parallel items inside the tree allowed' 0 "${RDT_CWD[@]}" \
  --command 'parallel rm -rf {} ::: plugins/rdt-nonexistent build/rdt-x'
expect_both 'pipe: parallel items outside the tree block' 2 "${RDT_CWD[@]}" \
  --command 'parallel rm -rf {} ::: build/rdt-x /opt/nonexistent-rdt/x'
# Items on the line replace stdin; a file source beside them does not.
expect_both 'pipe: parallel items with an unread pipe allowed' 0 "${RDT_CWD[@]}" \
  --command 'cat list | parallel rm -rf {} ::: build/rdt-x'
expect_both 'pipe: parallel items beside a file source block' 2 "${RDT_CWD[@]}" \
  --command 'parallel rm -rf {} ::: build/rdt-x :::: list'

# A listing that is not confined, a file or a stdin no listing feeds, a filter
# that can rewrite a line, and a listing the tokenizer splits out of order.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "pipe: $rdt_cmd blocks" 2 --command "$rdt_cmd"
  expect_both "pipe: $rdt_cmd blocks with a cwd" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
cat list | xargs rm -rf
cat list | xargs -0 rm -r
xargs rm -rf
xargs rm -rf < list
find build | xargs rm -rf < list
xargs -a list rm -rf
xargs --arg-file=list rm -rf
xargs -0a list rm -rf
grep -l x src | xargs rm -rf
find build | sed 's,^,/,' | xargs rm -rf
find build | grep -o x | xargs rm -rf
find build | cut -c1 | xargs rm -rf
find build -printf '/\n' | xargs rm -rf
find build -fprintf /dev/stdout '/\n' | xargs rm -rf
find build -ls | xargs rm -rf
find build -exec echo / \; | xargs rm -rf
git ls-files --format=/ | xargs rm -rf
git ls-files --form=/ | xargs rm -rf
git -C /opt ls-files | xargs rm -rf
sudo find build | xargs rm -rf
find build; cat list | xargs rm -rf
{ cat list; find build; } | xargs rm -rf
cat list $(find build) | xargs rm -rf
find build | (cat list; cat) | xargs rm -rf
find build | xargs -I{} sh -c 'rm -rf {}' < list
cat list | xargs -I{} sh -c 'rm -rf {}'
cat list | sudo xargs rm -rf
cat list | bash -c 'xargs rm -rf'
cat list | bash -c 'find build; xargs rm -rf'
echo "$(cat list | xargs rm -rf)"
find build | xargs rm -rf /
cat list | parallel rm -rf
parallel rm -rf
parallel rm -rf :::: list
parallel -a list rm -rf
find build | parallel --arg-sep ,, rm -rf ,, x
parallel rm -rf ::: /
parallel 'rm -rf {}' ::: /
parallel -j 2 rm -rf ::: /
parallel ::: 'rm -rf /'
parallel -j 2 ::: 'rm -rf /'
EOF

# A command that does not delete recursively, and the mechanism as quoted prose.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "pipe: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "pipe: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git commit -m "cat list | xargs rm -rf"
git commit -m "find / | xargs rm -rf"
echo 'parallel rm -rf ::: /'
cat list | xargs grep -l rm
cat list | xargs rm -f
find / -name x | xargs echo rm -rf /
parallel echo ::: rm-rf-nothing
EOF

guard_invoke --command 'cat list | xargs rm -rf'
assert_exit 'pipe: an unconfined listing exits 2' 2 "$GUARD_RC"
assert_contains 'pipe: the refusal names the cause' "$GUARD_ERR" 'no confined listing produced'
guard_invoke "${RDT_CWD[@]}" --command 'find /opt/nonexistent-rdt/x -type f | xargs rm -rf'
assert_contains 'pipe: the refusal names the start point' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"
guard_invoke --cwd / --command 'git ls-files | xargs rm -rf'
assert_contains 'pipe: the refusal names the git ls-files entry' "$GUARD_ERR" "the operand '(a file git ls-files lists)'"
expect 'pipe: attended, an unconfined listing asks' 0 --command 'cat list | xargs rm -rf' \
  -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq 'pipe: attended, the decision is ask' ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"

# --- 2h. rsync deletes (#9756) -------------------------------------------------
# A --del, --delete or --delete-<mode> option deletes in the destination, the
# last operand; --remove-source-files deletes from the sources before it. Each
# is judged as a recursive rm operand. Every form runs against a root, HOME, a
# path outside the allowed roots and a path strictly inside the tree.
RDT_RSYNC_FORMS=(
  'rsync -a --delete src/ TGT'
  'rsync -a --del src/ TGT'
  'rsync -av --delete-after src/ TGT'
  'rsync -a --delete-excluded --exclude=.cache src/ TGT'
  'rsync -ae ssh --delete-before src/ TGT'
  'rsync -a src/ TGT --delete'
  'sudo rsync -a --delete src/ TGT'
  'rsync -a --remove-source-files TGT build/rdt-out'
  'rsync -a --remove-source-files build/rdt-x TGT/ build/rdt-out'
)
rdt_rsync() { # <label> <want> <target> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_RSYNC_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "rsync: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_rsync 'a root blocks' 2 /
rdt_rsync 'HOME blocks' 2 '$HOME'
rdt_rsync 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_rsync 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'rsync: a delete into ~ blocks' 2 --command 'rsync -a --delete src/ ~'
expect_both 'rsync: a drive root is judged, not read as a host' 2 --command 'rsync -a --delete src/ C:/'
expect_both 'rsync: a delete under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'rsync -a --delete src/ /tmp/rdt-x'
expect_both 'rsync: a delete under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "rsync -a --delete src/ '$RDT_SPT/x'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'rsync: a delete into the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "rsync -a --delete src/ '$RDT_SPT'" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'rsync: unset key, a delete under the root blocks' 2 "rsync -a --delete src/ '$RDT_AR/child'"
rdt_ar 'rsync: a delete under the root allowed' 0 "rsync -a --delete src/ '$RDT_AR/child'" "$RDT_AR"
rdt_ar 'rsync: a delete into the root itself blocks' 2 "rsync -a --delete src/ '$RDT_AR'" "$RDT_AR"
rdt_ar 'rsync: moved sources under the root allowed' 0 "rsync -a --remove-source-files '$RDT_AR/child' build/rdt-out" "$RDT_AR"
expect_both 'rsync: a delete into the toplevel blocks' 2 "${RDT_CWD[@]}" --command 'rsync -a --delete src/ .'
expect_both 'rsync: a cd outside before the delete blocks' 2 "${RDT_CWD[@]}" \
  --command 'cd /opt && rsync -a --delete src/ x'
# The items xargs appends are the rsync's operands.
expect_both 'rsync: xargs fed by a confined listing allowed' 0 "${RDT_CWD[@]}" \
  --command 'find build -type d | xargs rsync -a --delete src/'
expect_both 'rsync: xargs fed by an unconfined listing blocks' 2 "${RDT_CWD[@]}" \
  --command 'cat list | xargs rsync -a --delete src/'

# An rsync that deletes nothing, a remote target, an option's argument, and
# the mechanism as quoted prose.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "rsync: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "rsync: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
rsync -a src/ /opt/nonexistent-rdt/x
rsync -a --delay-updates src/ /
rsync --delete /
rsync -a --remove-source-files --exclude /opt build/rdt-x build/rdt-out
rsync -a -T /opt --remove-source-files build/rdt-x build/rdt-out
rsync -ae /opt/ssh --remove-source-files build/rdt-x build/rdt-out
git commit -m "rsync -a --delete src/ /"
echo 'rsync --remove-source-files / build/rdt-out'
EOF

# A remote operand is left alone. Run from / (no tree), where the same word
# read as a local relative path would be refused.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "rsync: remote, $rdt_cmd allowed" 0 --cwd / --command "$rdt_cmd"
done <<'EOF'
rsync -a --delete src/ host:/
rsync -a --delete src/ user@host:dir
rsync -a --delete src/ rsync://host/module/
rsync -a --remove-source-files host:/ /tmp/rdt-out
EOF

# A brace, a glob or an expansion that can change which word is last or read
# as a host.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "rsync: $rdt_cmd blocks" 2 --command "$rdt_cmd"
done <<'EOF'
rsync -a --delete {src/,/}
rsync -a --delete src/ / {,}
rsync -a --delete src/ "${HOME:-x}"
rsync -a --delete src/ {h:,/}
rsync -a --delete src/ ~ --time-limit 60
rsync -a --delete src/ ~ --zl 3
rsync -a --remove-sent-files / /tmp/rdt-out
echo "$(rsync -a --del src/ /)"
parallel ::: 'rsync -a --del src/ /'
EOF

guard_invoke "${RDT_CWD[@]}" --command 'rsync -a --delete src/ /opt/nonexistent-rdt/x'
assert_exit 'rsync: an outside destination exits 2' 2 "$GUARD_RC"
assert_contains 'rsync: the refusal names the destination' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

# --- 2i. robocopy deletes (#9758) ----------------------------------------------
# /MIR or /PURGE deletes in the destination, the second operand; /MOVE or /MOV
# deletes from the source, the first. Each is judged as a recursive rm operand,
# from the Bash and the PowerShell tool. Every form runs against a root, HOME,
# a path outside the allowed roots and a path strictly inside the tree.
RDT_ROBOCOPY_FORMS=(
  'robocopy src TGT /MIR'
  'robocopy src TGT /mir /R:2 /W:5'
  'robocopy src TGT /E /PURGE'
  'robocopy src TGT //MIR'
  'robocopy /MIR src TGT'
  'robocopy src TGT a.txt /XF a.tmp b.tmp /MIR'
  'robocopy.exe src TGT /MIR /LOG:build/rdt.log'
  'robocopy TGT build/rdt-out /MOVE'
  'robocopy TGT build/rdt-out /E /MOV'
)
rdt_robocopy() { # <label> <want> <target> [guard_invoke option ...]: every form, both tools
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_ROBOCOPY_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "robocopy: $label: $c" "$want" --command "$c" "$@"
    expect_both "robocopy: PS $label: $c" "$want" --tool PowerShell --command "$c" "$@"
  done
}
rdt_robocopy 'a root blocks' 2 /
rdt_robocopy 'HOME blocks' 2 '$HOME'
rdt_robocopy 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_robocopy 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'robocopy: PS a mirror into a drive root blocks' 2 \
  --tool PowerShell --command 'robocopy src C:\ /MIR'
expect_both 'robocopy: PS a mirror outside the tree blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'robocopy src D:\rdt-x\y /PURGE'
expect_both 'robocopy: PS cmd /c robocopy into a drive root blocks' 2 \
  --tool PowerShell --command 'cmd /c robocopy src C:\ /MIR'
expect_both 'robocopy: PS cmd /c robocopy inside the tree allowed' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'cmd /c "robocopy src build\rdt-out /MIR"'
expect_both 'robocopy: a mirror under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'robocopy src /tmp/rdt-x /MIR'
expect_both 'robocopy: a mirror under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "robocopy src '$RDT_SPT/x' /MIR" "$RDT_TOP" "$RDT_SPT")"
expect_both 'robocopy: a mirror into the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "robocopy src '$RDT_SPT' /MIR" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'robocopy: unset key, a mirror under the root blocks' 2 "robocopy src '$RDT_AR/child' /MIR"
rdt_ar 'robocopy: a mirror under the root allowed' 0 "robocopy src '$RDT_AR/child' /MIR" "$RDT_AR"
rdt_ar 'robocopy: a mirror into the root itself blocks' 2 "robocopy src '$RDT_AR' /MIR" "$RDT_AR"
rdt_ar 'robocopy: a move from under the root allowed' 0 "robocopy '$RDT_AR/child' build/rdt-out /MOVE" "$RDT_AR"
expect_both 'robocopy: PS a mirror under an allowed root allowed' 0 --tool PowerShell --cwd / \
  --command "robocopy src '$RDT_AR/child' /MIR" -- "HOME=$RDT_AH" "$RDT_KEY=$RDT_AR"
expect_both 'robocopy: a mirror into the toplevel blocks' 2 "${RDT_CWD[@]}" --command 'robocopy src . /MIR'
# The items xargs appends are the robocopy's operands.
expect_both 'robocopy: xargs fed by an unconfined listing blocks' 2 "${RDT_CWD[@]}" \
  --command 'cat list | xargs robocopy src /MIR'

# A robocopy that deletes nothing, a side it does not delete from, a /XF list
# entry, a fully quoted glob, and the mechanism as quoted prose.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd allowed" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
  expect_both "robocopy: PS $rdt_cmd allowed" 0 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
robocopy src /opt/nonexistent-rdt/x /E
robocopy /opt/nonexistent-rdt/x build/rdt-out /MIR
robocopy build/rdt-x /opt/nonexistent-rdt/x /MOVE
robocopy src build/rdt-out /XF / /MIR
robocopy '/opt/nonexistent-rdt/*' build/rdt-out /MIR
git commit -m "robocopy src / /MIR"
echo 'robocopy / build/rdt-out /MOVE'
EOF

# From the Bash tool a brace or a glob can change which word is the source or
# the destination, so every operand is judged; a substitution body is judged.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
robocopy /opt/nonexistent-rdt/* build/rdt-out /MIR
robocopy {src,/} /MIR
robocopy $UNSET src / /MIR
robocopy "$@" /MIR
robocopy src / -MIR
echo "$(robocopy src / /MIR)"
EOF

# From the Bash tool MSYS rewrites a single-slash one-letter word to that
# drive's root, so `/e` is an operand there and never the /E option; from the
# PowerShell tool it is the option, and the robocopy names no destination.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
robocopy src /e /MIR
robocopy src /S /PURGE
robocopy src /x /e /MIR
robocopy /e build/rdt-out /MOVE
EOF
expect_both 'robocopy: PS robocopy src /e /MIR allowed' 0 --tool PowerShell "${RDT_CWD[@]}" \
  --command 'robocopy src /e /MIR'

# A prefix that turns MSYS path conversion off for the robocopy makes `/e` the
# /E option again, so the destination is the word after the source. A bare
# assignment in its own segment is not exported, and an exclusion list that
# does not cover the word leaves it converted.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
MSYS_NO_PATHCONV=1 robocopy /e empty /opt/nonexistent-rdt/x /MIR
MSYS2_ARG_CONV_EXCL='*' robocopy /e empty /opt/nonexistent-rdt/x /MIR
MSYS2_ARG_CONV_EXCL='--x;/e' robocopy /e empty /opt/nonexistent-rdt/x /MIR
env MSYS_NO_PATHCONV=1 robocopy /e empty /opt/nonexistent-rdt/x /MIR
MSYS_NO_PATHCONV=1; robocopy src /e /MIR
MSYS2_ARG_CONV_EXCL=--x robocopy src /e /MIR
MSYS2_ARG_CONV_EXCL= robocopy src /e /MIR
EOF

# A suppressor value that expands at run time, or an env option that can drop
# the suppressor before robocopy starts, leaves the conversion state unknown,
# so every operand is judged, each single-slash one-letter word included.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
MSYS2_ARG_CONV_EXCL=$X robocopy /e empty /opt/nonexistent-rdt/x /MIR
MSYS_NO_PATHCONV=1 env -u MSYS_NO_PATHCONV robocopy /e /opt/nonexistent-rdt/x empty /MIR
MSYS_NO_PATHCONV=1 env -i robocopy /e /opt/nonexistent-rdt/x empty /MIR
EOF
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd allowed" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
MSYS_NO_PATHCONV=1 robocopy src /e /MIR
MSYS2_ARG_CONV_EXCL='*' robocopy src /e /MIR
MSYS_NO_PATHCONV=1 robocopy /e empty build/rdt-out /MIR
EOF

# From the PowerShell tool an array, an unset variable or a grouping can
# change which word is the destination, and `--%` is dropped before robocopy
# sees its arguments.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: PS $rdt_cmd blocks" 2 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
robocopy --% src C:\ /MIR
robocopy $null src C:\ /MIR
robocopy $pair /MIR
robocopy (Get-Pair) /MIR
EOF

guard_invoke "${RDT_CWD[@]}" --command 'robocopy src /opt/nonexistent-rdt/x /MIR'
assert_exit 'robocopy: an outside destination exits 2' 2 "$GUARD_RC"
assert_contains 'robocopy: the refusal names the destination' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

# --- 2j. git worktree remove --force (#9760) ---------------------------------
# -f or --force removes the worktree's directory even when it holds changes.
# Its <worktree> operand is judged as a recursive rm operand, and so is every
# registered worktree root whose path ends in it. Every form runs against a
# root, HOME, a path outside the allowed roots and a path inside the tree.
RDT_GWT_FORMS=(
  'git worktree remove --force TGT'
  'git worktree remove -f TGT'
  'git worktree remove -f -f TGT'
  'git worktree remove TGT --force'
  'git worktree remove --forc -- TGT'
  'git -c core.x=1 --no-pager worktree remove -ff TGT'
)
rdt_gwt() { # <label> <want> <target> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_GWT_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "git worktree: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_gwt 'a root blocks' 2 /
rdt_gwt 'HOME blocks' 2 '$HOME'
rdt_gwt '~ blocks' 2 '~'
rdt_gwt 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_gwt 'inside the tree allowed' 0 build/rdt-wt-nonexistent "${RDT_CWD[@]}"
expect_both 'git worktree: the toplevel blocks' 2 "${RDT_CWD[@]}" --command 'git worktree remove --force .'
expect_both 'git worktree: under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'git worktree remove --force /tmp/rdt-wt-x'
expect_both 'git worktree: under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "git worktree remove --force '$RDT_SPT/wt'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'git worktree: the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "git worktree remove --force '$RDT_SPT'" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'git worktree: unset key, under the root blocks' 2 "git worktree remove --force '$RDT_AR/child'"
rdt_ar 'git worktree: under the root allowed' 0 "git worktree remove --force '$RDT_AR/child'" "$RDT_AR"
rdt_ar 'git worktree: the root itself blocks' 2 "git worktree remove --force '$RDT_AR'" "$RDT_AR"

# Without a force flag git refuses an unclean worktree; other subcommands, and
# the mechanism as quoted prose, delete nothing.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "git worktree: $rdt_cmd allowed" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git worktree remove /opt/nonexistent-rdt/x
git worktree add /opt/nonexistent-rdt/x
git worktree list
git worktree prune
git commit -m "git worktree remove --force /"
git commit -m 'drop it' -m "git worktree remove --force ~"
echo 'git worktree remove --force /'
EOF

# Launchers, child shells, substitutions, braces, and a relative name under
# an option that selects another repository.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "git worktree: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
sudo git worktree remove --force /
bash -c 'git worktree remove --force ~'
echo "$(git worktree remove --force /)"
git worktree remove --force {build/rdt-x,/}
git -C /opt/nonexistent-rdt worktree remove --force wt
git --git-dir=/opt/nonexistent-rdt/.git worktree remove --force wt
GIT_DIR=/opt/nonexistent-rdt/.git git worktree remove --force wt
env GIT_DIR=/opt/nonexistent-rdt/.git git worktree remove --force wt
X=wt; git -C /opt/nonexistent-rdt worktree remove --force "$X"
cd /opt/nonexistent-rdt && git worktree remove --force wt
cat list | xargs git worktree remove --force
EOF

# Registered worktrees, on the fixture of section 2e: under the suite's temp
# directory a linked worktree is strictly under a temp root, so removing it
# passes, by path or by its trailing name; the toplevel, a directory holding a
# worktree, and the worktree the session runs in stay refused.
rdt_wt 'git worktree remove of a linked worktree allowed' 0 "git worktree remove --force '$RDT_WF/wt1'"
rdt_wt 'git worktree remove by trailing name allowed' 0 'git worktree remove --force wt1'
rdt_wt 'git worktree remove of the toplevel blocks' 2 "git worktree remove --force '$RDT_WF/main'"
rdt_wt 'git worktree remove of a directory holding one blocks' 2 "git worktree remove --force '$RDT_WF/holder'"
rdt_wt 'from a linked worktree: git worktree remove of itself blocks' 2 \
  "git worktree remove --force '$RDT_WF/wt1'" "$RDT_WF/wt1"
rdt_wt 'from a linked worktree: git worktree remove of itself by name blocks' 2 \
  'git worktree remove --force wt1' "$RDT_WF/wt1"

# Outside every temp root (the checkout's .work), a registered worktree stays
# protected, a trailing name included and one inside the toplevel too, until
# an allowed root other than the toplevel holds it.
RDT_GW="$RDT_AB/gwt"
mkdir -p "$RDT_GW/main/.git/worktrees/n1" "$RDT_GW/main/.git/worktrees/n2" "$RDT_GW/n1" "$RDT_GW/main/n2"
printf '%s\n' "$RDT_GW/n1/.git" >"$RDT_GW/main/.git/worktrees/n1/gitdir"
printf 'gitdir: %s\n' "$RDT_GW/main/.git/worktrees/n1" >"$RDT_GW/n1/.git"
printf '%s\n' "$RDT_GW/main/n2/.git" >"$RDT_GW/main/.git/worktrees/n2/gitdir"
printf 'gitdir: %s\n' "$RDT_GW/main/.git/worktrees/n2" >"$RDT_GW/main/n2/.git"
rdt_gw() { # <label> <want> <command> [roots]: from the fixture's main worktree
  local -a env=("PATH=$TEST_TMPDIR/bin-git-top:$PATH" "RDT_STUB_TOP=$RDT_GW/main" "HOME=$RDT_AH")
  [[ -z "${4:-}" ]] || env+=("$RDT_KEY=$4")
  expect_both "git worktree: $1" "$2" --cwd "$RDT_GW/main" --command "$3" -- "${env[@]}"
}
rdt_gw 'a worktree outside temp blocks' 2 "git worktree remove --force '$RDT_GW/n1'"
rdt_gw 'a worktree outside temp by trailing name blocks' 2 'git worktree remove --force n1'
rdt_gw 'a worktree outside temp by a trailing glob blocks' 2 'git worktree remove --force n*'
rdt_gw 'a worktree inside the toplevel blocks' 2 'git worktree remove --force n2'
rdt_gw 'a worktree under an allowed root allowed' 0 "git worktree remove --force '$RDT_GW/n1'" "$RDT_GW"
rdt_gw 'a worktree under an allowed root by trailing name allowed' 0 'git worktree remove --force n1' "$RDT_GW"

guard_invoke "${RDT_CWD[@]}" --command 'git worktree remove --force /opt/nonexistent-rdt/x'
assert_exit 'git worktree: an outside worktree exits 2' 2 "$GUARD_RC"
assert_contains 'git worktree: the refusal names the worktree' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

rdt_finish
