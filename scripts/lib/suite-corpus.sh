# shellcheck shell=bash

suite_corpus::shell() {
  local _sc_tmp _sc_path _sc_rc=0
  _sc_tmp="$(mktemp)" || {
    printf 'suite-corpus: mktemp failed\n' >&2
    return 1
  }
  if ! git ls-files -z --cached --others --exclude-standard -- '*.test.sh' >"$_sc_tmp"; then
    rm -f "$_sc_tmp"
    printf 'suite-corpus: git ls-files failed in %s; refusing to report an empty corpus\n' "$PWD" >&2
    return 1
  fi
  while IFS= read -r -d '' _sc_path; do
    if [[ -f "$_sc_path" ]]; then
      printf '%s\n' "$_sc_path"
    fi
  done <"$_sc_tmp" | LC_ALL=C sort -u || _sc_rc=1
  rm -f "$_sc_tmp"
  return "$_sc_rc"
}
