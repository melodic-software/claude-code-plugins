#!/usr/bin/env bash
# test-scope: .github/scripts/pr-require-checks/formatter-proof.sh plugins/bash-format/git-hooks/shfmt-rewrite.sh scripts/run-ruff.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/pr-require-checks/formatter-proof.sh"

# shellcheck source=../../../scripts/lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=../../../scripts/test-git-helpers.sh
. "$ROOT/scripts/test-git-helpers.sh"

pin="$(sed -nE 's/^[[:space:]]*version=(v[0-9.]+)[[:space:]]*$/\1/p' "$ROOT/.github/actions/setup-pinned-shfmt/action.yml")"
if [[ "$(shfmt --version 2>/dev/null)" != "$pin" ]] || ! bash "$ROOT/scripts/run-ruff.sh" --version >/dev/null 2>&1 ||
  ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: needs shfmt $pin, the pinned Ruff (scripts/run-ruff.sh), jq and python3"
  test_harness::report
  exit
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

put() {
  mkdir -p "$(dirname "$R/$1")"
  printf '%b' "$2" >"$R/$1"
}
tg() { git_test_config "$R" "$@"; }

R="$TMP/repo"
mkdir -p "$R"
git_init_test_repo "$R" || exit 1
for f in .editorconfig ruff.toml plugins/bash-format/git-hooks/shfmt-rewrite.sh \
  .github/actions/setup-pinned-shfmt/action.yml scripts/run-ruff.sh .github/requirements-ci.txt; do
  mkdir -p "$(dirname "$R/$f")"
  cp "$ROOT/$f" "$R/$f"
done
# shellcheck disable=SC2016 # the stand-in script's own text, expanded when it runs
put scripts/sync-shared-copies.sh '#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
grep -vE "^[[:space:]]*(#|$)" scripts/shared-copies.txt | while read -r src copy; do
  { printf "# GENERATED from %s\\n" "$src"; cat "$src"; } >"$copy"
done
'
put scripts/sync-hold-floor.py 'import pathlib
root = pathlib.Path(__file__).resolve().parent.parent
conf = root / "conf/demo.yml"
lines = conf.read_text().split("\\n")
begin = lines.index("# BEGIN hold-floor demo")
end = lines.index("# END hold-floor demo")
body = ["  " + line for line in (root / "lib/a.sh").read_text().removesuffix("\\n").split("\\n")]
conf.write_text("\\n".join(lines[: begin + 1] + body + lines[end:]))
'
put scripts/shared-copies.txt '# canonical copy\nlib/a.sh plugins/p/a.sh\n'
put lib/a.sh 'if true;then echo hi;fi\n'
put plugins/p/a.sh '# GENERATED from lib/a.sh\nif true;then echo hi;fi\n'
put conf/demo.yml 'key: 1\n# BEGIN hold-floor demo\n  if true;then echo hi;fi\n# END hold-floor demo\n'
put tool/b.py 'x=1\n'
put lib/ok.sh 'echo ok\n'
put lib/broken.sh 'if then (\n'
put tool/broken.py 'def (:\n'
put docs/x.md '# X\n'
tg add -A && tg commit -q -m base || exit 1
BASE="$(tg rev-parse HEAD)"

A_FMT='if true; then echo hi; fi\n'
make_head() {
  local name=$1
  shift
  tg checkout -q -B "$name" "$BASE" || return 1
  while (($# >= 2)); do
    if [[ $2 == - ]]; then tg rm -q "$1"; else put "$1" "$2"; fi
    shift 2
  done
  tg add -A && tg commit -q --allow-empty -m "$name" && tg rev-parse HEAD
}
FORMATTED=(lib/a.sh "$A_FMT" plugins/p/a.sh "# GENERATED from lib/a.sh\n$A_FMT"
  conf/demo.yml "key: 1\n# BEGIN hold-floor demo\n  ${A_FMT%\\n}\n# END hold-floor demo\n" tool/b.py 'x = 1\n')

prove() {
  RC=0
  OUT="$(cd "$R" && bash "$SCRIPT" --work-dir "$TMP" "$@" 2>&1)" || RC=$?
}
expect() {
  local label=$1 rc=$2 needle=$3
  if [[ $RC == "$rc" && $OUT == *"$needle"* ]]; then ok "$label"; else fail "$label: want rc=$rc and '$needle', got rc=$RC: $OUT"; fi
}

h="$(make_head pure "${FORMATTED[@]}")"
prove "$BASE" "$h"
expect "a pure formatter diff, its copy and its hold-floor block regenerated, is a proof" 0 \
  "proof: 4 file(s) reproduced byte for byte (1 shfmt, 1 Ruff, 2 regenerated)"
if [[ "$(git -C "$R" worktree list --porcelain | grep -c '^worktree ')" == 1 && -z "$(find "$TMP" -maxdepth 1 -name 'formatter-proof.*')" ]]; then
  ok "the scratch worktree is removed"
else
  fail "the scratch worktree is left: $(git -C "$R" worktree list) $(ls -A "$TMP")"
fi

h="$(make_head extra "${FORMATTED[@]}" tool/b.py 'x = 1 \n')"
prove "$BASE" "$h"
expect "one byte the formatter does not write is no proof" 1 "- tool/b.py: the formatted base differs from the head"

h="$(make_head fragment "${FORMATTED[@]}" .changes/p/note.md 'note\n')"
prove "$BASE" "$h"
expect "an added changelog fragment beside the formatting is set aside" 0 "1 changelog fragment(s) set aside"

h="$(make_head fragment-edit "${FORMATTED[@]}" .changes/p/note.txt 'note\n')"
prove "$BASE" "$h"
expect "a .changes file that is not a fragment .md is no proof" 1 ".changes/p/note.txt: a change under .changes/ other than one added fragment .md file"

h="$(make_head stale-copy "${FORMATTED[@]}" plugins/p/a.sh "# GENERATED from lib/a.sh\n$A_FMT# edited\n")"
prove "$BASE" "$h"
expect "a copy that is not its formatted canonical's is no proof" 1 "- plugins/p/a.sh: the formatted base differs from the head"

h="$(make_head copy-only plugins/p/a.sh "# GENERATED from lib/a.sh\n$A_FMT" tool/b.py 'x = 1\n')"
prove "$BASE" "$h"
expect "a formatted copy whose canonical did not change is no proof" 1 "- plugins/p/a.sh: the formatters leave the base as it is, but the head changes it"

h="$(make_head block "${FORMATTED[@]}" conf/demo.yml "key: 2\n# BEGIN hold-floor demo\n  ${A_FMT%\\n}\n# END hold-floor demo\n")"
prove "$BASE" "$h"
expect "a byte outside the regenerated block is no proof" 1 "- conf/demo.yml: the formatted base differs from the head"

h="$(make_head docs "${FORMATTED[@]}" docs/x.md '# X\n\nMore.\n')"
prove "$BASE" "$h"
expect "a file type neither formatter covers is no proof" 1 "- docs/x.md: neither formatter covers it, and no regenerator writes it"

h="$(make_head unchanged-format "${FORMATTED[@]}" lib/ok.sh 'echo  ok\n')"
prove "$BASE" "$h"
expect "a change to a file the formatter leaves alone is no proof" 1 "- lib/ok.sh: the formatters leave the base as it is, but the head changes it"

h="$(make_head added "${FORMATTED[@]}" lib/new.sh 'echo new\n')"
prove "$BASE" "$h"
expect "an added file is no proof" 1 "- lib/new.sh: added"
h="$(make_head deleted "${FORMATTED[@]}" docs/x.md -)"
prove "$BASE" "$h"
expect "a deleted file is no proof" 1 "- docs/x.md: deleted"
tg checkout -q -B mode "$BASE" && put lib/a.sh "$A_FMT" && chmod +x "$R/lib/a.sh" && tg add -A && tg commit -q -m mode
prove "$BASE" "$(tg rev-parse HEAD)"
expect "a mode change is no proof" 1 "- lib/a.sh: mode 100644 to 100755"

h="$(make_head none docs/x.md '# Y\n')"
prove "$BASE" "$h"
expect "a change with no formatter file is no proof" 1 "- no file the formatters cover changed"

h="$(make_head broken "${FORMATTED[@]}" lib/broken.sh 'if then ( \n')"
prove "$BASE" "$h"
expect "a formatter that fails is no proof" 2 "lib/broken.sh: shfmt failed"
h="$(make_head broken-py "${FORMATTED[@]}" tool/broken.py 'def (:  \n')"
prove "$BASE" "$h"
expect "a Ruff run that fails is no proof" 2 "ruff format failed"

mkdir -p "$TMP/old-shfmt"
printf '#!/bin/sh\necho v3.0.0\n' >"$TMP/old-shfmt/shfmt"
chmod +x "$TMP/old-shfmt/shfmt"
h="$(make_head pin "${FORMATTED[@]}")"
RC=0
OUT="$(cd "$R" && PATH="$TMP/old-shfmt:$PATH" bash "$SCRIPT" --work-dir "$TMP" "$BASE" "$h" 2>&1)" || RC=$?
expect "an shfmt that is not the base's pin is no proof" 2 "shfmt is not the base's pin $pin"

prove --classify "$BASE" "$h"
expect "--classify passes a formatter diff before any tool runs" 0 "candidate: 1 shell, 1 Python and 2 regenerated file(s), 0 fragment(s)"
h="$(make_head classify-docs docs/x.md '# Y\n' lib/a.sh "$A_FMT")"
prove --classify "$BASE" "$h"
expect "--classify refuses a file no formatter or regenerator covers" 1 "- docs/x.md: neither formatter covers it"

prove "$BASE"
expect "a missing argument is a usage error" 2 "usage: formatter-proof.sh"
prove "$BASE" 0000000000000000000000000000000000000000
expect "an unknown head is a usage error" 2 "not a commit or"

test_harness::report
