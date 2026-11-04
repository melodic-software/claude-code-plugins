#!/usr/bin/env bash
# edit-config.sh — apply one jq edit to a built fixture's team layer.
#
# edit-config.sh <root> [jq options...] <filter>
#
# The filter sees the layer as the resolver does, `{schema, file_names}`, and the
# result's `file_names` is written back to <root>/docs/conventions/docs-naming.yaml.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../lib/layer-yaml.sh
. "$here/../../../../lib/layer-yaml.sh"

root="${1:?usage: edit-config.sh <root> [jq options...] <filter>}"
shift
file="$root/docs/conventions/docs-naming.yaml"
doc="$(layer_yaml_to_json "$file")" || exit 2
doc="$(printf '%s' "$doc" | jq -c "$@")" || exit 2
layer_yaml_render "$(printf '%s' "$doc" | jq -c '.file_names')" >"$file"
