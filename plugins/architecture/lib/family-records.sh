#!/usr/bin/env bash

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
    flow.json | flow.md | data-model.json | data-model.md | data-model.dbml)
    return 0
    ;;
  *) return 1 ;;
  esac
}
