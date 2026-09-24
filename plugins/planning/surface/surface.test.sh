#!/usr/bin/env bash
# Hygiene checks, then the browser suites, for the interview surface.
#   bash surface.test.sh
# Suites and files it grades: index.html, tests/ui_a.js, tests/ui_b.js, and the JSON Schemas
# schema/questions.schema.json and schema/responses.schema.json once they ship.
# The browser suites run only where playwright-cli resolves; elsewhere they print a SKIP with
# the number of checks not run, never a pass.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../../.." && pwd)
pass=0
fail=0
skip=0
ok() { echo "ok: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

cd "$here" || exit 1
files=()
for f in server.py round.py round.sh watch.sh index.html exporters.py tests/*.js; do
  [[ -f "$f" ]] && files+=("$f")
done

# AC35: no file names a producing skill (<plugin>:<skill>), with plugin names read from plugins/.
names=""
for p in "$root"/plugins/*/; do
  p=${p%/}
  names="${names:+$names|}${p##*/}"
done
hits=$(grep -nE "(^|[^a-z0-9-])($names):[a-z-]+" "${files[@]}")
if [[ -z "$hits" ]]; then ok "AC35: no skill token in ${#files[@]} files"; else bad "AC35: skill tokens: $hits"; fi

# AC34: no user name, home path, or port other than the documented default 8766 (or 0).
hits=""
for u in "${USER:-}" "${USERNAME:-}" "$(whoami 2>/dev/null)"; do
  u=${u##*\\}
  [[ "${#u}" -ge 3 ]] || continue
  h=$(grep -niwF -- "$u" "${files[@]}")
  hits="$hits$h"
done
if [[ -z "$hits" ]]; then ok "AC34: no user name"; else bad "AC34: user name found: $hits"; fi
hits=$(grep -nE '/Users/|[Cc]:[\\/]+Users|/home/' "${files[@]}")
if [[ -z "$hits" ]]; then ok "AC34: no home path"; else bad "AC34: home path found: $hits"; fi
hits=$(grep -noE '(127\.0\.0\.1|localhost):[0-9]+|--port[ =][0-9]+|PORT=[0-9]+' "${files[@]}" |
  grep -vE ':(8766|0)$|[ =](8766|0)$')
if [[ -z "$hits" ]]; then ok "AC34: no port but 8766 or 0"; else bad "AC34: hardcoded port: $hits"; fi

# index.html lint, when the repo's htmlhint is installed.
if [[ -x "$root/node_modules/.bin/htmlhint" ]]; then
  if out=$("$root/node_modules/.bin/htmlhint" index.html 2>&1); then ok "htmlhint index.html"; else bad "htmlhint: $out"; fi
else
  echo "SKIP: 1 check not run (htmlhint not installed)"
  skip=$((skip + 1))
fi

# Result lines from a playwright-cli run-code output file: one PASS/FAIL/ERROR per line.
results() {
  grep -m1 'PASS\|FAIL\|ERROR' "$1" | awk '{ gsub(/\\n/, "\n"); print }' |
    sed 's/^.*"PASS/PASS/; s/^.*"FAIL/FAIL/; s/^.*"ERROR/ERROR/; s/"$//' | grep -E '^(PASS|FAIL|ERROR) '
}

grade() { # suite output-file
  local n=0 line
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      PASS\ *) ok "$1: ${line#PASS }" ;;
      *) bad "$1: $line" ;;
    esac
  done < <(results "$2")
  [[ "$n" -gt 0 ]] || bad "$1: no results ($(head -c 400 "$2"))"
  echo "$1: $n checks"
}

if command -v playwright-cli >/dev/null 2>&1; then
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/iv-surface.XXXXXX")
  d="$tmp/d3"
  session="iv-$$"
  # playwright-cli writes its logs under the working directory, so it runs from the scratch dir.
  pw() { (cd "$tmp" && playwright-cli -s="$session" "$@"); }
  finish() {
    pw close >/dev/null 2>&1
    bash "$here/round.sh" --dir "$d" stop >/dev/null 2>&1
    case "$tmp" in
      */iv-surface.*) rm -rf -- "$tmp" ;;
      *) ;;
    esac
  }
  trap finish EXIT
  mkdir -p "$d"
  cp tests/fixtures/questions.json tests/fixtures/responses.json "$d/"
  bash "$here/round.sh" --dir "$d" add-round --file tests/round-d3.json --round 4 >/dev/null
  bash "$here/round.sh" --dir "$d" ensure-running --port 0 >/dev/null
  port=$(sed -n 's/^PORT=//p' "$d/.interview-session.env" | tr -d '\r')
  for s in ui_a ui_b; do
    sed "s/__PORT__/$port/" "tests/$s.js" >"$tmp/$s.js"
  done
  script_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
  pw open >/dev/null 2>&1
  pw run-code --filename "$(script_path "$tmp/ui_a.js")" >"$tmp/ui_a.out" 2>&1
  bash "$here/round.sh" --dir "$d" revise N2 --rec "Yes. Changed by Claude after you started." --force >/dev/null
  pw run-code --filename "$(script_path "$tmp/ui_b.js")" >"$tmp/ui_b.out" 2>&1
  grade ui_a "$tmp/ui_a.out"
  grade ui_b "$tmp/ui_b.out"
else
  echo "SKIP: 61 browser checks not run (playwright-cli not found)" # silent-skip-ok: browser checks need a local playwright-cli # discriminating-skip-ok: the API, watcher and hygiene checks above still grade this suite
  skip=$((skip + 61))
fi

echo "PASS=$pass FAIL=$fail SKIP=$skip"
[[ "$fail" -eq 0 ]]
