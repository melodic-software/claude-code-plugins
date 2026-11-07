#!/usr/bin/env bash
# Makes the eval workspace its own git repository for a /verification:setup case. AGENTS.md binds
# docs/conventions as the convention home, so setup-apply.mjs makes no convention-home offer.
# none: no docs/conventions/verification.yaml and no .gitignore, so .work/ is not ignored.
# proof-path: a committed docs/conventions/verification.yaml holding proof_level: path.
# workers-2: a committed docs/conventions/verification.yaml holding live_workers: 2.
set -euo pipefail
set -o noclobber
mode="${1:?mode: none, proof-path or workers-2}"
case "${mode}" in
none | proof-path | workers-2) ;;
*) echo "unknown mode: ${mode}" >&2 && exit 2 ;;
esac
here="$(pwd -P)"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
bash "$(dirname "${BASH_SOURCE[0]}")/workspace-guard.sh" docs AGENTS.md README.md .gitignore .work

GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.name='Fabrikam Fixture' -c user.email='fixture@fabrikam.example' "$@"
}
g -c init.defaultBranch=main init -q --template=
if [[ "$(git rev-parse --show-toplevel)" != "${here}" ]]; then
  echo "git did not create a repository here: ${PWD}" >&2
  exit 3
fi
printf '# invoice-service\n\nFabrikam invoice service.\n' >README.md
mkdir -p docs/conventions
printf '# Conventions\n\nTeam conventions for the invoice service.\n' >docs/conventions/README.md
cat >AGENTS.md <<'MD'
# invoice-service

<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `docs/conventions`, read the topic doc there
before changing a governed surface.
<!-- END GENERATED: convention-home -->
MD
case "${mode}" in
proof-path) printf 'proof_level: path\n' >docs/conventions/verification.yaml ;;
workers-2) printf 'live_workers: 2\n' >docs/conventions/verification.yaml ;;
*) ;; # none; the mode was checked above
esac
g add -A
g commit -q -m "invoice-service fixture"
