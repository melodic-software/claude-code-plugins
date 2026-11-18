#!/bin/sh
# shellcheck shell=sh
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
*/info/lefthook-remotes/*) ;;
*) exit 0 ;;
esac
exec sh "${src%/*}/../remote-entry.sh" pre-commit markdown-format-remote-format "${src%/*}/../../plugins/markdown-format/git-hooks/format.sh" "$@"
