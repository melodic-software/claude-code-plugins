#!/usr/bin/env bash
# Names of the records and renderings the map-* family writes into
# architecture_dir.
#
# Source this file. is_family_record BASENAME returns 0 when BASENAME is one of
# them, 1 otherwise. Evidence collectors skip these files: a record's own URLs
# and hosts are output, not configuration. The names come from each skill's
# renderer and record; family-records.test.sh asserts the renderers agree.
#
# Executing this file prints usage and exits 2.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'family-records.sh: source this file; it is not a command\n' >&2
  exit 2
fi

is_family_record() {
  case "$1" in
  landscape.json | landscape.md | landscape.dsl | portfolio.md | \
    dependency-graph.json | dependency-graph.md | components.md | \
    containers.json | containers.md | context.json | context.md | \
    deployment.json | deployment.md | events.json | events.md | \
    flow.json | flow.md | data-model.json | data-model.md | data-model.dbml | \
    states.json | states.md)
    return 0
    ;;
  *) return 1 ;;
  esac
}
