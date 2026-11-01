#!/usr/bin/env bash
# One doc paraphrasing a fictional vendor's retry defaults, linked to an unfetchable page.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/paraphrase-repo.sh"
