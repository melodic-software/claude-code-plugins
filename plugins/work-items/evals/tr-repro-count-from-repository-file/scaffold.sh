#!/usr/bin/env bash
# docs/conventions/work-items.yaml holding only triage_repro_count: 4, and a week-number script whose bug reproduces offline.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" repro-count-repo
