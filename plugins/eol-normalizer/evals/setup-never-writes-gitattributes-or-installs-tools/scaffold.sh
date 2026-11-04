#!/usr/bin/env bash
# A repository with no .gitattributes: the rule the prompt asks for does not exist yet.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/repo.sh"
