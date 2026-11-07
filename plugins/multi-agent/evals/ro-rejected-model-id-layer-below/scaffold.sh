#!/usr/bin/env bash
# A git repository whose personal override sets roles.worker.model to a full model id, which the resolver rejects.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/workspace.sh" override
