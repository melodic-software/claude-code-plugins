#!/usr/bin/env bash
# The fixture pages hold CSS and JavaScript source as literal data on purpose.
# shellcheck disable=SC2016
set -uo pipefail
unset CHECK_DATA_ROOT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "${SELF_DIR}/.." && pwd)" || exit 2
SCRIPT="${SELF_DIR}/check-token-literals.sh"

# shellcheck source=lib/test-harness.sh
. "${SELF_DIR}/lib/test-harness.sh" || exit 2
# shellcheck source=lib/fixture-tree.sh
. "${SELF_DIR}/lib/fixture-tree.sh" || exit 2

f=""
RC=0
OUT=""
ERR=""
PAGE=plugins/demo/templates/view.html

run_script() {
  local script="$1" outf errf
  shift
  outf="$(mktemp)" || exit 2
  errf="$(mktemp)" || exit 2
  RC=0
  bash "${script}" "$@" >"${outf}" 2>"${errf}" || RC=$?
  OUT="$(cat "${outf}")"
  ERR="$(cat "${errf}")"
  rm -f "${outf}" "${errf}"
}

run_check() { run_script "${f}/scripts/check-token-literals.sh" "$@"; }

new_tree() {
  fixture_tree::build f --sut "${SCRIPT}" --git --plugins --label token-literals || exit 2
  mkdir -p "${f}/lib" "${f}/plugins/demo/templates" "${f}/plugins/demo/reference"
  cp "${REPO_ROOT}/lib/html-tokens.css" "${f}/lib/html-tokens.css"
  printf '%s\n' \
    'lib/html-chrome.html plugins/demo/reference/html-chrome.html' \
    'lib/html-tokens.css plugins/demo/reference/html-tokens.css' >"${f}/scripts/shared-copies.txt"
  cp "${f}/lib/html-tokens.css" "${f}/plugins/demo/reference/html-tokens.css"
  printf '<style>\n:root { --bg: #FAF9F5; --sans: system-ui, sans-serif; }\n</style>\n' \
    >"${f}/plugins/demo/reference/html-chrome.html"
}

write_page() {
  local path="$1"
  shift
  mkdir -p "$(dirname "${f}/${path}")"
  printf '%s\n' "$@" >"${f}/${path}"
  git -C "${f}" add -A >/dev/null 2>&1
}

expect_clean() {
  local label="$1"
  run_check
  if ((RC == 0)) && [[ -n "${OUT}" && -z "${ERR}" ]]; then
    ok "${label}"
  else
    fail "${label}: wanted exit 0, a stdout statement and empty stderr (rc=${RC}, stdout='${OUT}', stderr='${ERR}')"
  fi
}

expect_finding() {
  local label="$1" needle="$2"
  run_check
  if ((RC == 1)) && [[ "${ERR}" == *"${needle}"* && "${OUT}" != *"${needle}"* ]]; then
    ok "${label}"
  else
    fail "${label}: wanted exit 1 with '${needle}' on stderr only (rc=${RC}, stdout='${OUT}', stderr='${ERR}')"
  fi
}

new_tree
write_page "${PAGE}" '<style>' ':root {' '  --accent: #123456;' '}' '</style>'
expect_finding "an injected literal palette value fails, naming file and line" \
  "TOKEN LITERAL: ${PAGE}:3: --accent: #123456"
write_page "${PAGE}" '<style>' ':root {' '}' '</style>'
expect_clean "the same page passes once the literal is removed"

write_page "${PAGE}" '<style>' ':root { --sans: Arial, sans-serif; }' '</style>'
expect_finding "a literal type stack fails" "TOKEN LITERAL: ${PAGE}:2: --sans: Arial, sans-serif"

write_page "${PAGE}" '<style>' ':root { --link: var(--page-link); }' '</style>'
expect_finding "a role pointed at a page-local property fails" "TOKEN LITERAL: ${PAGE}:2: --link: var(--page-link)"

write_page "${PAGE}" '<style>' ':root { --accent: var(--clay); --link: var( --clay-deep ); }' '.card--accent:hover { color: var(--accent); }' '</style>'
expect_clean "a role pointed at a token-layer property, a BEM modifier and a var() use pass"

write_page plugins/demo/scripts/build.mjs 'const css = `:root { --muted: #6B6A64; }`;'
expect_finding "a literal inside a JavaScript page builder fails" "TOKEN LITERAL: plugins/demo/scripts/build.mjs:1:"
git -C "${f}" rm -qf plugins/demo/scripts/build.mjs

write_page plugins/demo/evals/case/page.html ':root { --bg: #000000; }'
write_page plugins/demo/scripts/build.test.mjs 'const css = ":root { --bg: #000000; }";'
write_page plugins/demo/README.md '`--bg: #000000;`'
expect_clean "evals, tests and markdown are not page sources"

write_page plugins/demo/templates/untracked-check.html ':root { --fg: #111111; }'
git -C "${f}" rm -q --cached plugins/demo/templates/untracked-check.html
expect_finding "an untracked page is scanned too" "TOKEN LITERAL: plugins/demo/templates/untracked-check.html:1:"
rm -f "${f}/plugins/demo/templates/untracked-check.html"

write_page "${PAGE}" ':root { --bg: #000000; }'
printf '%s\n' "# pages still to migrate" "${PAGE}  # wave 9" >"${f}/scripts/token-literals-allowlist.txt"
expect_clean "an allowlisted page passes"
write_page "${PAGE}" ':root { }'
expect_finding "an allowlist entry with nothing left to migrate fails, so the list shrinks" \
  "STALE ALLOWLIST: ${PAGE}"
printf '%s\n' "plugins/demo/templates/gone.html" >"${f}/scripts/token-literals-allowlist.txt"
expect_finding "an allowlist entry for a missing file fails" "STALE ALLOWLIST: plugins/demo/templates/gone.html"
rm -f "${f}/scripts/token-literals-allowlist.txt"

new_tree
write_page "${PAGE}" ':root { }'
rm -f "${f}/lib/html-tokens.css"
run_check
if ((RC == 2)) && [[ -n "${ERR}" && -z "${OUT}" ]]; then
  ok "a missing token layer exits 2"
else
  fail "a missing token layer: wanted exit 2 on stderr (rc=${RC}, stdout='${OUT}', stderr='${ERR}')"
fi

new_tree
printf ':root { --bg: #FFFFFF; }\n' >"${f}/lib/html-tokens.css"
run_check
if ((RC == 2)) && [[ "${ERR}" == *"palette role"* && -z "${OUT}" ]]; then
  ok "a token layer with no dark-scheme roles exits 2 rather than checking nothing"
else
  fail "a token layer with no roles: wanted exit 2 (rc=${RC}, stdout='${OUT}', stderr='${ERR}')"
fi

new_tree
run_check --bogus
if ((RC == 2)) && [[ -n "${ERR}" && -z "${OUT}" ]]; then
  ok "an unknown argument exits 2"
else
  fail "an unknown argument: wanted exit 2 (rc=${RC}, stdout='${OUT}', stderr='${ERR}')"
fi
run_check --help
if ((RC == 0)) && [[ "${OUT}" == *"Usage:"* ]]; then
  ok "--help prints usage on stdout"
else
  fail "--help: wanted exit 0 and usage (rc=${RC}, stdout='${OUT}', stderr='${ERR}')"
fi

test_harness::report
