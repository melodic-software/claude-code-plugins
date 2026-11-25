#!/usr/bin/env bash

test_git_env::isolate() {
  printf '[user]\n\tname = test\n\temail = t@t.test\n[commit]\n\tgpgsign = false\n[tag]\n\tgpgsign = false\n' >"$1" || return
  export GIT_CONFIG_GLOBAL="$1" GIT_CONFIG_NOSYSTEM=1
}
