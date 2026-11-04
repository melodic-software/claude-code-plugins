#!/usr/bin/env bash
# A repository whose .gitattributes declares an eol=lf rule, so check has a policy to resolve.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/repo.sh" '*.sh text eol=lf'
