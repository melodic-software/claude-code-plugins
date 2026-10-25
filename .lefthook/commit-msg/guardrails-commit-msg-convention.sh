#!/bin/sh
# The guardrails commit-msg-convention entry for consumers of the plugin's lefthook remote
# (plugins/guardrails/git-hooks/lefthook-remote.yml). Lefthook looks up a remote's scripts
# under this repository's root .lefthook/, so this runs the plugin's own script, which finds its libs beside it.
# Skip the work-tree copy, so only the fetched copy of main in lefthook-remotes/ runs. Backslashes
# become slashes first (\134 is the backslash): lefthook on Windows passes a backslash path. POSIX
# sh, run with sh, never bash by name: on Windows that can be System32's WSL launcher.
# shellcheck shell=sh
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
*/info/lefthook-remotes/*) ;;
*) exit 0 ;;
esac
exec sh "${src%/*}/../../plugins/guardrails/git-hooks/commit-msg-convention.sh" "$@"
