#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Fail a workflow whose expanded template memory nears the known-failing figure.

Usage: check-workflow-template-size.sh [--check]

Every workflow in .github/workflows/ that calls a local reusable through
`uses: ./.github/workflows/<file>` is estimated as GitHub's template parser
charges it (actions/runner src/Sdk/DTObjectTemplating/ObjectTemplating/
TemplateMemory.cs): 24 bytes per node, and 26 bytes plus 2 per character more
for each string, over the caller plus every called file once per call job.
A caller at or above failing-figure minus margin in
.github/workflow-template-size.json is a finding. The figure is the estimate of
the first commit GitHub refused with "Maximum object size exceeded", an
empirical reference, not a documented GitHub limit.

Output follows the check-script contract (scripts/README.md, "The check-script
contract"): one path:line: finding per caller on stderr, each passing caller's
estimate and headroom on stdout. Exit 0 clean, 1 any finding, 2 usage or
environment (no node, no yaml package, an unreadable config, or a call to a
missing file, a call cycle or a workflow that does not parse). The yaml package
comes from npm ci --prefix .github/standards/runner-policy.
EOF
}

case "${1:-}" in
'' | --check) ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

if ! command -v node >/dev/null 2>&1; then
  printf 'check-workflow-template-size: node is not on PATH\n' >&2
  exit 2
fi
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-workflow-template-size.mjs" "$@"
