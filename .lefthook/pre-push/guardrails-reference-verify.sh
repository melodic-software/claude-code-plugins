#!/usr/bin/env bash
# The guardrails reference-verify entry for consumers of the plugin's lefthook remote
# (plugins/guardrails/git-hooks/lefthook-remote.yml). Lefthook looks up a remote's scripts
# under this repository's root .lefthook/, so this runs the plugin's own script, which finds its libs beside it.
exec bash "${BASH_SOURCE[0]%/*}/../../plugins/guardrails/git-hooks/reference-verify.sh" "$@"
