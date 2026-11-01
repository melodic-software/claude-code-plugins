#!/usr/bin/env bash
# Two established contexts, Support and Billing, with a context map and one table glossary each.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/support-billing-contexts.sh"
