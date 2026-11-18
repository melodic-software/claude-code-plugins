#!/bin/sh
# shellcheck shell=sh
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
*/info/lefthook-remotes/*) ;;
*) exit 0 ;;
esac
exec sh "${src%/*}/../remote-entry.sh" pre-commit guardrails-remote-pre-commit-content "${src%/*}/../../plugins/guardrails/git-hooks/pre-commit-content.sh" "$@"
