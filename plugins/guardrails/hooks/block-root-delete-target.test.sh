#!/usr/bin/env bash
# Contract test for block-root-delete-target.sh (guardrails plugin).
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

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-root-delete-target.sh"
GUARD_UNDER_TEST="$HOOK"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# --- 1. MUST FIRE: the operand normalizes to a filesystem root ----------------
# The measured gap this guard closes. `rm -rf "\\"` passed all eight guards of
# the Bash dispatcher at rc 0, because no guard inspected the TARGET of a
# recursive delete at all.
expect_both 'rm -rf "\\" blocks' 2 --command 'rm -rf "\\"'
expect_both 'rm -rf \\ blocks' 2 --command 'rm -rf \\'
expect_both 'rm -rf / blocks' 2 --command 'rm -rf /'
expect_both 'rm -rf /* blocks' 2 --command 'rm -rf /*'
expect_both 'rm -rf "//" blocks' 2 --command 'rm -rf "//"'

# Recursion spelled every way the flag parser must recognize.
expect_both 'rm -r / blocks' 2 --command 'rm -r /'
expect_both 'rm --recursive / blocks' 2 --command 'rm --recursive /'
expect_both 'rm -Rf / blocks (capital R)' 2 --command 'rm -Rf /'
expect_both 'rm -rf -- / blocks (end of options)' 2 --command 'rm -rf -- /'

# Home, in the spellings the tokenizer hands over verbatim. Detection never
# evaluates an expansion, so `$HOME` is matched as the literal it is written as.
expect_both 'rm -rf ~ blocks' 2 --command 'rm -rf ~'
expect_both 'rm -rf $HOME blocks' 2 --command 'rm -rf $HOME'
expect_both 'rm -rf "$HOME" blocks' 2 --command 'rm -rf "$HOME"'
expect_both 'rm -rf ${HOME} blocks' 2 --command 'rm -rf ${HOME}'

# Windows and MSYS drive roots. `C:\` arrives from the tokenizer as `C:`,
# because the backslash is a bash escape; `C:/` keeps its slash. Both normalize
# to the same drive root.
expect_both 'rm -rf C:\ blocks' 2 --command 'rm -rf C:\'
expect_both 'rm -rf c:/ blocks' 2 --command 'rm -rf c:/'
expect_both 'rm -rf C: blocks' 2 --command 'rm -rf C:'
expect_both 'rm -rf /c blocks (MSYS drive root)' 2 --command 'rm -rf /c'
expect_both 'rm -rf /c/* blocks' 2 --command 'rm -rf /c/*'
expect_both 'rm -rf /mnt/c blocks (WSL drive root)' 2 --command 'rm -rf /mnt/c'
expect_both 'rm -rf /cygdrive/c blocks' 2 --command 'rm -rf /cygdrive/c'

# Command-word resolution: a launcher, a path-qualified name, an .exe suffix
# and a quote-escaped name all resolve to the same `rm`.
expect_both 'sudo rm -rf / blocks' 2 --command 'sudo rm -rf /'
expect_both 'env rm -rf / blocks' 2 --command 'env rm -rf /'
expect_both '/bin/rm -rf / blocks' 2 --command '/bin/rm -rf /'
expect_both 'rm.exe -rf / blocks' 2 --command 'rm.exe -rf /'
expect_both '\rm -rf / blocks (quote-escaped name)' 2 --command '\rm -rf /'

# A later segment of a compound command is inspected on its own.
expect_both 'cd foo && rm -rf / blocks' 2 --command 'cd foo && rm -rf /'

# Any operand may be the root, not only the first.
expect_both 'rm -rf ./ok / blocks on the second operand' 2 --command 'rm -rf ./ok /'

# --no-preserve-root is refused whatever the operand: the flag exists only to
# defeat the one protection coreutils ships for this mistake.
expect_both 'rm -rf --no-preserve-root ./x blocks' 2 --command 'rm -rf --no-preserve-root ./x'

# A trailing segment that carries no NAME leaves the operand rooted where it
# started, so every one of these still names a root. Stripping one glob suffix
# was not enough: `/*/` keeps a trailing slash, `/./*` keeps a dot segment, and
# `/.[!.]*` is the ordinary dotfile idiom.
expect_both 'rm -rf /*/ blocks' 2 --command 'rm -rf /*/'
expect_both 'rm -rf /./* blocks' 2 --command 'rm -rf /./*'
expect_both 'rm -rf /.[!.]* blocks (dotfile idiom)' 2 --command 'rm -rf /.[!.]*'
expect_both 'rm -rf ~/./* blocks' 2 --command 'rm -rf ~/./*'
expect_both 'rm -rf /c/*/ blocks' 2 --command 'rm -rf /c/*/'
expect_both 'rm -rf /. blocks' 2 --command 'rm -rf /.'
expect_both 'rm -rf /.. blocks' 2 --command 'rm -rf /..'

# A launcher option that takes its own operand must not swallow the command
# word. `sudo -u bob rm` puts `bob` where a naive skip reads the command.
expect_both 'sudo -u bob rm -rf / blocks' 2 --command 'sudo -u bob rm -rf /'
expect_both 'env -u FOO rm -rf / blocks' 2 --command 'env -u FOO rm -rf /'
expect_both 'timeout 60 rm -rf / blocks' 2 --command 'timeout 60 rm -rf /'
expect_both 'nice -n 10 rm -rf / blocks' 2 --command 'nice -n 10 rm -rf /'
expect_both 'nohup rm -rf / blocks' 2 --command 'nohup rm -rf /'

# A child shell runs its operand as a full command, so the operand is re-parsed
# with the same tokenizer, exactly as block-no-verify does for `git`.
expect_both 'bash -c rm -rf / blocks' 2 --command 'bash -c "rm -rf /"'
expect_both 'sh -c rm -rf / blocks' 2 --command "sh -c 'rm -rf /'"
expect_both 'bash -lc rm -rf / blocks' 2 --command 'bash -lc "rm -rf /"'
expect_both 'sudo bash -c rm -rf / blocks' 2 --command 'sudo bash -c "rm -rf /"'

# The command word is compared case-insensitively, so the substring prefilter
# in front of the parse must be too. On the Windows host this guard was written
# for, the filesystem and PATH lookup are case-insensitive and `RM` runs rm.
expect_both 'RM -rf / blocks (upper case)' 2 --command 'RM -rf /'
expect_both 'Rm.exe -rf C:\ blocks (mixed case)' 2 --command 'Rm.exe -rf C:\'
expect_both 'busybox rm -rf / blocks' 2 --command 'busybox rm -rf /'

# A DANGLING trailing backslash is the incident string minus its quotes. Bash
# passes a literal `\` when one ends the input, and MSYS resolves it to the
# current drive root. The tokenizer has no character left to emit, so the
# operand arrives empty and only its quoting provenance separates it from
# `rm -rf ""`.
expect_both 'rm -rf \ blocks (dangling backslash)' 2 --command 'rm -rf \'
expect_both 'rm -rf $(quoted backslash) blocks' 2 --command "rm -rf '\\'"

# coreutils accepts any unambiguous long-option prefix.
expect_both 'rm --r -f / blocks (abbreviated --recursive)' 2 --command 'rm --r -f /'
expect_both 'rm --rec -f / blocks' 2 --command 'rm --rec -f /'
expect_both 'rm -rf --no-p ./x blocks (abbreviated --no-preserve-root)' 2 --command 'rm -rf --no-p ./x'

# A UNC share root is the same class of loss as a drive root.
expect_both 'rm -rf //server/share blocks' 2 --command 'rm -rf //server/share'
# Single-quoted, because an UNQUOTED backslash-backslash-server form is not a
# UNC path to bash at all: the escapes collapse it to `\servershare`, and that
# is what rm would receive. The quoted spelling is the one that reaches the
# share, and both verdicts are pinned so the difference stays deliberate.
# portability-ok: a literal backslash pair inside a UNC path, not a grep -E escape
expect_both 'quoted UNC share root blocks' 2 --command "rm -rf '\\\\server\\share'"
# portability-ok: a literal backslash pair inside a UNC path, not a grep -E escape
expect_both 'unquoted UNC-looking path allowed (its escapes collapse)' 0 --command 'rm -rf \\server\share'

# --- 2. MUST NOT FIRE --------------------------------------------------------
# Quoted prose keeps `rm` INSIDE one word, so the command word is `git` or
# `echo` and the guard never reaches its flag parse. That falls out of command
# word resolution rather than a special case for message text.
expect_both 'git commit -m "rm -rf /" allowed' 0 --command 'git commit -m "rm -rf /"'
expect_both 'echo "rm -rf /" allowed' 0 --command 'echo "rm -rf /"'
expect_both 'echo rm allowed' 0 --command 'echo rm'

# Ordinary recursive deletes under the working tree: the whole point of the
# narrow trigger is that these stay untouched.
expect_both 'rm -rf ./build dist allowed' 0 --command 'rm -rf ./build dist'
expect_both 'rm -rf build/ allowed' 0 --command 'rm -rf build/'
expect_both 'rm -rf /tmp/x allowed' 0 --command 'rm -rf /tmp/x'
expect_both 'rm -rf "$TMPDIR/x" allowed' 0 --command 'rm -rf "$TMPDIR/x"'
expect_both 'rm -rf ~/.cache/foo allowed' 0 --command 'rm -rf ~/.cache/foo'
expect_both 'rm -rf $HOME/x allowed' 0 --command 'rm -rf $HOME/x'
expect_both 'rm -rf C:/dev/x allowed' 0 --command 'rm -rf C:/dev/x'
expect_both 'rm -rf /c/dev/x allowed' 0 --command 'rm -rf /c/dev/x'

# No recursion flag: the fire conditions never open.
expect_both 'rm -f /file allowed' 0 --command 'rm -f /file'
expect_both 'rm / allowed (no recursion)' 0 --command 'rm /'

# An operand that normalizes to EMPTY is not a root, and a recursive delete
# with no operand at all has nothing to match.
expect_both 'rm -rf "" allowed' 0 --command 'rm -rf ""'
expect_both 'rm -rf allowed (no operand)' 0 --command 'rm -rf'

# A trailing segment that carries a NAME stops the reduction, so these stay
# ordinary relative or nested deletes rather than roots.
expect_both 'rm -rf /tmp* allowed' 0 --command 'rm -rf /tmp*'
expect_both 'rm -rf ~/proj* allowed' 0 --command 'rm -rf ~/proj*'
expect_both 'rm -rf /c/dev/* allowed' 0 --command 'rm -rf /c/dev/*'
expect_both 'rm -rf /_ allowed (a directory named _)' 0 --command 'rm -rf /_'
expect_both 'rm -rf * allowed (cwd-relative, a declared gap)' 0 --command 'rm -rf *'
# A glob glued to a NAME is an ordinary prefix match, not the root it sits in.
expect_both 'rm -rf /c* allowed' 0 --command 'rm -rf /c*'
expect_both 'rm -rf ~* allowed' 0 --command 'rm -rf ~*'
# A child shell whose operand is an ordinary delete stays allowed.
expect_both 'bash -c rm -rf ./build allowed' 0 --command 'bash -c "rm -rf ./build"'
# A launcher whose real command is not rm stays allowed.
expect_both 'sudo -u bob ls / allowed' 0 --command 'sudo -u bob ls /'
# A path UNDER a UNC share is not the share root.
expect_both 'rm -rf //server/share/dir allowed' 0 --command 'rm -rf //server/share/dir'
# A long option that is not a prefix of either recognized name.
expect_both 'rm --force / allowed (no recursion)' 0 --command 'rm --force /'
expect_both 'rm --dir / allowed (no recursion)' 0 --command 'rm --dir /'

# A command word that merely ENDS in rm, or takes rm as a subcommand, is not rm.
expect_both 'perm -rf / allowed' 0 --command 'perm -rf /'
expect_both 'rmdir / allowed' 0 --command 'rmdir /'
expect_both 'git rm -rf src allowed (command word is git)' 0 --command 'git rm -rf src'

# A recursive READ of the root is not a delete.
expect_both 'ls -R / allowed' 0 --command 'ls -R /'

# --- 3. The block message ----------------------------------------------------
guard_invoke --command 'rm -rf /'
assert_exit "blocked case exits 2" 2 "$GUARD_RC"
assert_contains "blocked case names the BLOCKED token" "$GUARD_ERR" "BLOCKED:"

# --- 4. Tool gating: the declared PowerShell gap ------------------------------
# Remove-Item -Recurse -Force and `rd /s` are the same hazard through the
# PowerShell tool, and this guard does not cover them: it exits on a non-Bash
# tool_name, which also keeps it out of the PowerShell classifier path entirely.
# Pinned so widening it later is a deliberate change to this line.
expect "PowerShell payload is a declared gap, not a block" 0 \
  --tool PowerShell --command 'Remove-Item -Recurse -Force C:\'

# --- 5. Fail-closed inputs ---------------------------------------------------
rc=0
bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip, not a block" 0 "$rc"

expect "a stdin body that is not JSON fails closed" 2 --payload 'not json'

rc=0
bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{}}' >/dev/null 2>&1 || rc=$?
assert_exit "payload with no command is a skip" 0 "$rc"

# --- 6. Kill switch ----------------------------------------------------------
expect "kill switch disables the guard" 0 --command 'rm -rf /' \
  -- "CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ENABLED=false"

# --- 7. The guard installs no exit-time handler of its own --------------------
# abort-boundary.sh owns that slot for every guard in this plugin; a second one
# in the guard would run after it and could change the status the boundary
# settled. abort-boundary.test.sh asserts the same property across the whole
# set, and this pins it for this file on its own.
own_traps="$(grep -n 'trap' "$HOOK" | grep -Ei 'trap[^#]*(EXIT|[[:space:]]0[[:space:]]*$)' || true)"
assert_eq "the guard installs no exit-time handler of its own" "" "$own_traps"

report
