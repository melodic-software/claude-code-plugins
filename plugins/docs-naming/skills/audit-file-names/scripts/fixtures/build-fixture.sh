#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

dest="${1:?usage: build-fixture.sh <destination> [--variant <name>]}"
variant="clean"
if [[ "${2:-}" == "--variant" ]]; then
  variant="${3:?--variant needs a name}"
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../lib/layer-yaml.sh
. "$here/../../../../lib/layer-yaml.sh"

mkdir -p "$dest"
cp -R "$here/tree/." "$dest/"
mkdir -p "$dest/docs/conventions"
layer_yaml_render "$(jq -c '.file_names' "$here/config.json")" >"$dest/docs/conventions/docs-naming.yaml"
chmod +x "$dest/tools/gen.sh"

case "$variant" in
collision)
  printf '# beta\n\nThe lowercase twin that makes the BETA.md proposal a collision.\n' >"$dest/docs/beta.md"
  ;;
clean) ;;
*)
  printf 'build-fixture: unknown variant %s\n' "$variant" >&2
  exit 2
  ;;
esac

git init -q "$dest"
git -C "$dest" config user.email fixture@example.invalid
git -C "$dest" config user.name "Fixture"
git -C "$dest" config commit.gpgsign false
git -C "$dest" config core.autocrlf false
git -C "$dest" add -A >/dev/null
git -C "$dest" commit -qm "fixture tree" >/dev/null
printf '%s\n' "$dest"
