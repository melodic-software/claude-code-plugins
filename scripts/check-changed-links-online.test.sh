#!/usr/bin/env bash
# Cases for scripts/check-changed-links-online.sh: which URLs it takes from a
# diff, and what it hands lychee, against a throwaway repository and a stub
# lychee that records its arguments and input.
# test-scope: scripts/check-changed-links-online.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-changed-links-online.sh"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export TMPDIR="$TMP_ROOT"

repo="$TMP_ROOT/repo"
git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid "$@"; }

mkdir -p "$repo/docs" "$repo/scripts/fixtures"
printf 'Kept: <https://kept.example.org/a>\nGone: <https://gone.example.org/b>\n' >"$repo/docs/a.md"
g add -A
g commit -q -m base
base="$(g rev-parse HEAD)"

cat >"$repo/docs/a.md" <<'EOF'
Kept: <https://kept.example.org/a>
New [link](https://new.example.org/page#section).
Again https://new.example.org/page#section, and plain http://plain.example.org/x.
++ starts with a plus https://plus.example.org/p
EOF
printf 'See https://code.example.org/c\n' >"$repo/docs/b.txt"
printf '| a | <https://fixture.example.org/f> |\n' >"$repo/scripts/fixtures/hooks-lifecycle-table.md"
g add -A
g commit -q -m change

run() { (cd "$repo" && bash "$SCRIPT" "$@"); }

out="$(run --list "$base")"
want=$'http://plain.example.org/x\nhttps://new.example.org/page#section\nhttps://plus.example.org/p'
if [[ $out == "$want" ]]; then
  pass "--list takes added markdown URLs once each, trailing punctuation dropped"
else
  bad "--list output" "want: $want; got: $out"
fi
# absent <host> <case>: the --list output does not name <host>.
absent() { if [[ $out != *"$1"* ]]; then pass "$2"; else bad "$2" "$out"; fi; }
absent kept.example.org "an unchanged line's URL is not listed"
absent gone.example.org "a removed line's URL is not listed"
absent code.example.org "a non-markdown file is not read"
absent fixture.example.org "an excluded fixture is not read"

stub="$TMP_ROOT/lychee"
cat >"$stub" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TMPDIR/args"
cat "${@: -1}" >"$TMPDIR/input"
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$stub"

if out="$(LYCHEE="$stub" run "$base" 2>&1)"; then
  pass "a passing lychee run exits 0"
else
  bad "passing run" "$out"
fi
if grep -qx -- '--config' "$TMP_ROOT/args" && grep -qx 'lychee.toml' "$TMP_ROOT/args"; then
  pass "lychee reads lychee.toml"
else
  bad "lychee args" "$(cat "$TMP_ROOT/args")"
fi
if grep -qx -- '--offline' "$TMP_ROOT/args"; then
  bad "online run passed --offline" "$(cat "$TMP_ROOT/args")"
else
  pass "the run is online"
fi
if [[ "$(cat "$TMP_ROOT/input")" == $'<http://plain.example.org/x>\n<https://new.example.org/page#section>\n<https://plus.example.org/p>' ]]; then
  pass "lychee's input is the listed URLs as autolinks"
else
  bad "lychee input" "$(cat "$TMP_ROOT/input")"
fi

if STUB_EXIT=2 LYCHEE="$stub" run "$base" >/dev/null 2>&1; then
  bad "a failing lychee run exited 0"
else
  pass "a failing lychee run fails the check"
fi

rm -f "$TMP_ROOT/args"
head="$(g rev-parse HEAD)"
if out="$(LYCHEE="$stub" run "$head" 2>&1)" && [[ ! -e $TMP_ROOT/args && $out == *"No external links"* ]]; then
  pass "a diff with no added URLs passes without running lychee"
else
  bad "empty diff" "$out"
fi

if run >/dev/null 2>&1; then bad "no base ref exited 0"; else pass "a missing base ref is a usage error"; fi

test_harness::report
