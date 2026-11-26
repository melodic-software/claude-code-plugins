#!/usr/bin/env bash
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
