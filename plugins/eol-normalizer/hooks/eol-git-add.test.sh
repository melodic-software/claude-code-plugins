#!/usr/bin/env bash
# Why eol-normalizer ships no pre-commit entry: `git add` applies the same
# .gitattributes to the bytes it stores, so rewriting a staged file's working-tree
# line endings and re-staging it can never change what a commit holds.
#
# For each path shape the plugin handles, the file is staged twice in throwaway
# repos with the same .gitattributes: once with the bytes as written, once after
# normalize_eol_file (the plugin's own rewrite) has rewritten them. The blob git
# stores must be identical, and for the `eol=` arms it must carry no CR. The
# shapes the plugin skips (-text, binary under text=auto) are stored as written
# either way, so the plugin and git agree there too.
# test-scope: plugins/eol-normalizer/hooks/normalize-eol.sh

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v git >/dev/null 2>&1 || {
  echo "SKIP: git not on PATH -- eol-git-add tests skipped"
  exit 0
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

# shellcheck source=normalize-eol.sh
source "$HOOK_DIR/normalize-eol.sh"

ATTRS=$'*.sh eol=lf\n*.txt eol=crlf\n*.auto text=auto eol=lf\n*.raw -text eol=lf\n'

# stored <repo-name> <file> <content-printf-arg> <rewrite:0|1> -> "<blob-sha> <CR count>"
stored() {
  local r="$WORK/$1" f="$2" rewrite="$4"
  rm -rf "$r"
  git init -q "$r"
  printf '%s' "$ATTRS" >"$r/.gitattributes"
  # shellcheck disable=SC2059  # the caller passes the file's bytes as a printf format
  printf "$3" >"$r/$f"
  ((rewrite)) && normalize_eol_file "$r" "$r/$f" >/dev/null
  git -C "$r" add -- "$f" 2>/dev/null
  printf '%s %s' "$(git -C "$r" rev-parse ":$f")" "$(git -C "$r" cat-file blob ":$f" | tr -cd '\r' | wc -c | tr -d ' ')"
}

check() { # <label> <file> <bytes> <want CR in blob>
  local raw rewritten
  raw="$(stored raw "$2" "$3" 0)"
  rewritten="$(stored rewritten "$2" "$3" 1)"
  expect "$1: the blob is the same with or without the plugin's rewrite" "$raw" "$rewritten"
  expect "$1: CR bytes in the stored blob" "$4" "${raw##* }"
}

check "eol=lf, CRLF file" a.sh 'echo a\r\necho b\r\n' 0
check "eol=crlf, LF file" a.txt 'one\ntwo\n' 0
check "eol=crlf, CRLF file" b.txt 'one\r\ntwo\r\n' 0
check "text=auto eol=lf, CRLF text" a.auto 'one\r\ntwo\r\n' 0
check "-text eol=lf, CRLF file (neither git nor the plugin converts)" a.raw 'one\r\ntwo\r\n' 2
check "text=auto, binary content (neither converts)" b.auto 'BIN\r\n\000\001\r\ndata' 2

echo "eol-git-add: $PASS passed, $FAIL failed"
((FAIL == 0))
