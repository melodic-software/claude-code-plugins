#!/usr/bin/env bash
# Sourced by an audit scaffold after git-workspace.sh. Defines:
#   au_copy <fixture> <dest>  copy skills/audit/evals/fixtures/<fixture> to <dest> in the workspace,
#                             outside the evals/fixtures/ corpus the scan prunes, dropping the
#                             file's leading comment block (the corpus headers name the expected rule)
#                             from its first cant-fail-ok: line on
#   au_commit                 commit the workspace
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
au_fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/audit/evals/fixtures" && pwd)"

au_copy() {
  local src="${au_fixtures}/${1:?fixture}" dest="${2:?dest}"
  [[ -f "${src}" ]] || { echo "missing audit fixture: ${src}" >&2 && exit 3; }
  mkdir -p "$(dirname "${dest}")"
  awk 'body || !/^[[:space:]]*(\/\/|#)/ || /cant-fail-ok:/ { body = 1; print }' "${src}" >"${dest}"
}

au_commit() {
  g add -A
  g commit -q -m "test suite"
}
