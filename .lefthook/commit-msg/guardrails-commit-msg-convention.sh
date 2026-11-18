#!/bin/sh
# shellcheck shell=sh
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
*/info/lefthook-remotes/*) ;;
*) exit 0 ;;
esac
exec sh "${src%/*}/../remote-entry.sh" commit-msg guardrails-remote-commit-msg-convention "${src%/*}/../../plugins/guardrails/git-hooks/commit-msg-convention.sh" "$@"
