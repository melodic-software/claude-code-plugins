#!/usr/bin/env bash
# A git repository with no docs/conventions/discipline.yaml.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/su-repo.sh" fresh
