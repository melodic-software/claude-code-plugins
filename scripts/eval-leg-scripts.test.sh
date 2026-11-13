#!/usr/bin/env bash
# Behavior test for the eval-dispatch leg scripts and the pinned ffmpeg install:
# each refusal prints its error line and exits 1, the accepting paths write the
# step outputs, and install-pinned-ffmpeg.sh checks the archive's SHA-256 and
# downloads into a cache dir only when the archive is missing. A stub curl
# stands in for the network.
# test-scope: .github/scripts/plugin-eval/check-bwrap.sh .github/scripts/plugin-eval/choose-plugins.sh .github/scripts/plugin-eval/stage-suites.sh .github/scripts/plugin-eval/check-label-sender.sh .github/scripts/lib/install-pinned-ffmpeg.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub" "$T/empty" "$T/rt" "$T/cache" "$T/root"
cat >"$T/stub/curl" <<EOF
#!/bin/sh
touch "$T/curl-ran"
while [ \$# -gt 0 ]; do
  if [ "\$1" = -o ]; then shift; printf x >"\$1"; fi
  shift
done
EOF
chmod +x "$T/stub/curl"
S="$ROOT/.github/scripts"
P="PATH=$PATH"

# expect <name> <exit> <last output line> <env...> -- <script> [args...]
expect() {
  local name=$1 want_rc=$2 want=$3 envs=()
  shift 3
  while [[ $1 != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  out=$(env -i "${envs[@]}" /bin/bash "$@" 2>&1)
  local rc=$?
  if [[ $rc -eq $want_rc && "$(tail -1 <<<"$out")" == "$want" ]]; then
    ok "$name"
  else
    fail "$name: exit $rc, output [$out]"
  fi
}

printf '{"actors":[{"id":1,"kind":"human"},{"id":2,"kind":"bot"}]}' >"$T/list.json"
expect "an untrusted verdict is refused" 1 "::error::the trigger is not trusted (reason: unreadable)" \
  "$P" PROCEED=false LIST="$T/list.json" SENDER_ID=1 -- "$S/plugin-eval/check-label-sender.sh"
expect "a label from a listed human passes" 0 "" \
  "$P" PROCEED=true LIST="$T/list.json" SENDER_ID=1 -- "$S/plugin-eval/check-label-sender.sh"
expect "a label from a listed bot is refused" 1 "::error::untrusted-actor: the 'eval: run' label did not come from a listed human" \
  "$P" PROCEED=true LIST="$T/list.json" SENDER_ID=2 -- "$S/plugin-eval/check-label-sender.sh"

expect "a dispatch target outside plugins/ is refused" 1 "::error::target must be a plugin directory, plugins/<name>" \
  "$P" EVENT=workflow_dispatch TARGET=docs GITHUB_OUTPUT="$T/out1" -- "$S/plugin-eval/choose-plugins.sh"
expect "a dispatch target is chosen" 0 "" \
  "$P" EVENT=workflow_dispatch TARGET=plugins/foo/ GITHUB_OUTPUT="$T/out2" -- "$S/plugin-eval/choose-plugins.sh"
if [[ "$(cat "$T/out2")" == $'go=true\nlist<<EOF\nplugins/foo\nEOF' ]]; then
  ok "the chosen target is written as go and list"
else
  fail "choose-plugins wrote [$(cat "$T/out2")]"
fi

expect "a plugin with no eval suite is skipped" 0 "::notice::plugins/none has no eval suite; skipped." \
  "$P" LIST=plugins/none ROOT="$T/root" DETERMINISTIC=false GITHUB_OUTPUT="$T/out3" -- "$S/plugin-eval/stage-suites.sh"
if [[ "$(cat "$T/out3")" == go=false ]]; then ok "nothing staged writes go=false"; else fail "stage-suites wrote [$(cat "$T/out3")]"; fi

expect "a missing bwrap is refused" 1 "::error::bwrap is not on PATH: the Bash sandbox needs it" \
  PATH="$T/empty" -- "$S/plugin-eval/check-bwrap.sh"

asset=ffmpeg-n8.1.3-9-g29e619e767-linux64-gpl-8.1.tar.xz
expect "a downloaded archive with the wrong SHA-256 is refused" 1 "::error::$asset does not match FFMPEG_SHA256" \
  PATH="$T/stub:$PATH" RUNNER_TEMP="$T/rt" GITHUB_PATH="$T/path" -- "$S/lib/install-pinned-ffmpeg.sh" "$T/bin"
printf x >"$T/cache/$asset"
rm -f "$T/curl-ran"
expect "a cached archive is checked too" 1 "::error::$asset does not match FFMPEG_SHA256" \
  PATH="$T/stub:$PATH" GITHUB_PATH="$T/path" -- "$S/lib/install-pinned-ffmpeg.sh" "$T/bin" "$T/cache"
if [[ ! -e "$T/curl-ran" ]]; then ok "a cached archive is not downloaded again"; else fail "curl ran with the archive cached"; fi
out=$(env -i "$P" /bin/bash "$S/lib/install-pinned-ffmpeg.sh" 2>&1)
rc=$?
if [[ $rc -eq 1 && $out == *"usage: install-pinned-ffmpeg.sh <bin-dir> [cache-dir]" ]]; then
  ok "no bin dir is a usage error"
else
  fail "no bin dir: exit $rc, output [$out]"
fi

test_harness::report
