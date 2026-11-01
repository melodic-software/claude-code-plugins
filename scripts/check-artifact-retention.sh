#!/usr/bin/env bash
# Check that every actions/upload-artifact step keeps its artifact for exactly
# the days .github/artifact-retention.json names for the artifact's family.
#
#   scripts/check-artifact-retention.sh          discover: list every finding
#   scripts/check-artifact-retention.sh --check  same, explicit form matching the
#                                                sibling gates (exit 1 on any finding)
#
# Scope: every step whose `uses:` starts with `actions/upload-artifact@` in
# .github/workflows/*.yml and *.yaml, and in .github/actions/*/action.yml and
# action.yaml.
#
# MATCHING. A step's family is found from its `with.name`, first rule that
# applies:
#   1. A name with no `${{` is a static name. It matches the family whose key
#      equals it, exactly. A `*` family never takes a static name.
#   2. A name with `${{` after some literal text matches the family whose key
#      is that literal text followed by `*`, compared exactly:
#      `patch-${{ inputs.lane }}-...` matches `patch-*` and nothing else, so
#      `verdict-*` never takes `dependency-verdict-...`.
#   3. A name that starts with `${{` (computed in an earlier step) matches the
#      family whose `uploads` list holds `<file>#<job id>` for the job holding
#      the step; in a composite action the job id is `runs`.
# A step with no name, a name matching no family, or a name two families claim
# is a finding. So is a step with no `retention-days`, one whose value is not a
# whole number of days (an expression), and one whose value differs from its
# family's. `max` is the repository maximum, 90 days. One expression passes: a
# row naming `computed-by` (the script that sets it, which must exist) lets its
# steps read `${{ steps.<id>.outputs.retention-days }}`; the row's value records
# the longest that script returns.
#
# SCAN. Each row's `scan` says whether its uploads are lane or eval artifacts
# that lib/publish-gate.mjs scanLeak clears first. `upload`: each upload step
# follows a .github/actions/scan-upload step over the identical path and its
# `if:` requires that step's clean output, or it reads from the read runner's
# leak-scan output directory and requires leak-scan's clean output.
# `plaintext`: an earlier scan step in the same steps clears the plaintext the
# upload seals. `none`: no scan. A scanned upload with no such step is a finding.
#
# The table is held to its own rules too: it must pass
# .github/artifact-retention.schema.json; each reader and max-reader must start
# with a path that exists in the repository; a `max` row must name a
# max-reader, the reader that needs 90 days, and it must be one of its readers;
# every `uploads` entry must name a job that uploads a computed name; and every
# family must match at least one step, so a removed upload leaves no row behind.
#
# WHY. An upload with no retention-days keeps its artifact for the repository
# default, 90 days, and every artifact kept lengthens the repository-wide
# artifact listing that the pr-verify evidence reader pages through on each
# read. Each family's row records who reads it and why its length is needed, so
# a longer retention is a decision with a stated reader, not a default.
#
# The work is in check-artifact-retention.mjs beside this file. It parses YAML
# with the `yaml` package and validates the table with `ajv`, both installed by
# `npm ci --prefix .github/standards/runner-policy`.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one `path:line: finding` per offender on stderr, the clean-run
# statement on stdout. Exit: 0 clean, 1 any finding, 2 usage or environment
# (no node, the packages not installed, or the table or its schema unreadable).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if ! command -v node >/dev/null 2>&1; then
  printf 'check-artifact-retention: node is not on PATH\n' >&2
  exit 2
fi
exec node "$SCRIPT_DIR/check-artifact-retention.mjs"
