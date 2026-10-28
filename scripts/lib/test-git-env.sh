#!/usr/bin/env bash
# Sourced by the test runners: scripts/run-test-file.sh, scripts/affected-tests.sh,
# scripts/run-plugin-tests.sh and scripts/run-outside-node-suites.sh.
#
# test_git_env::isolate <file> writes a fixed test identity with commit and tag
# signing off to <file>, then exports GIT_CONFIG_GLOBAL=<file> and
# GIT_CONFIG_NOSYSTEM=1, so every suite the runner spawns reads that file in
# place of the host's ~/.gitconfig and system config. A host that signs every
# commit then cannot fail a fixture `git commit` through its signing program,
# and no suite passes on the host's identity alone. Local config a suite writes
# into its own fixture still wins over the file (git-config(1), FILES).
#
# Each suite gets its own file: a suite that writes `git config --global` writes
# into it, and a file shared across parallel suites would race on its lock and
# leak settings between them.
#
# A suite that must read the host's real git config opts out by unsetting both
# variables itself: `unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM`.

test_git_env::isolate() {
  printf '[user]\n\tname = test\n\temail = t@t.test\n[commit]\n\tgpgsign = false\n[tag]\n\tgpgsign = false\n' >"$1" || return
  export GIT_CONFIG_GLOBAL="$1" GIT_CONFIG_NOSYSTEM=1
}
