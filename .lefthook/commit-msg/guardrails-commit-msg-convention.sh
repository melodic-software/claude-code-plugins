#!/usr/bin/env bash
# The guardrails commit-msg-convention entry for consumers of the plugin's lefthook remote
# (plugins/guardrails/git-hooks/lefthook-remote.yml). Lefthook looks up a remote's scripts
# under this repository's root .lefthook/, so this runs the plugin's own script, which finds its libs beside it.
# Skip the work-tree copy, so only the fetched copy of main in lefthook-remotes/ runs. Backslashes
# become slashes first: lefthook on Windows passes a backslash path.
src=${BASH_SOURCE[0]//\\//}
[[ $src == */info/lefthook-remotes/* ]] || exit 0
exec bash "${src%/*}/../../plugins/guardrails/git-hooks/commit-msg-convention.sh" "$@"
