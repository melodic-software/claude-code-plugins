#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../code-reviewer-loosening-spec-requested/scaffold.sh"
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/spec-author.sh" 41 4102 "no reason"
