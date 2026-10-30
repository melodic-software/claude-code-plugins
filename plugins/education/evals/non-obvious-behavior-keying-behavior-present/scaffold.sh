#!/usr/bin/env bash
# Seeds the same workspace as non-obvious-behavior-keying, so the pair differs only in prompt.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../non-obvious-behavior-keying/scaffold.sh"
