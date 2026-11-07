#!/usr/bin/env bash
# Seeds the same committed slugify change as qz-library-path-repo-identity.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../qz-library-path-repo-identity/scaffold.sh"
