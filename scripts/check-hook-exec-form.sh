#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/hook-configs.sh
. scripts/lib/hook-configs.sh || exit 2

errors=0
execform_errors=0

on_hook() {
  local file="$1" where="$2" cmd="$5"
  [[ "$3" == exec ]] || return 0
  case "$cmd" in
  */* | *\\*) return 0 ;;
  *) ;;
  esac
  # shellcheck disable=SC2310  # allowed_exec_name is a pure loop test; it cannot fail unexpectedly
  if hook_configs::allowed_exec_name "$cmd"; then
    return 0
  fi
  echo "EXEC-FORM HOOK: ${file}:${where}: exec-form hook (\`args\` present) with bare command \"${cmd}\"" >&2
  errors=$((errors + 1))
  execform_errors=$((execform_errors + 1))
}

on_unreadable() {
  case "$1" in
  json)
    echo "UNREADABLE HOOK CONFIG: ${2}: not parseable as JSON — this gate cannot clear it" >&2
    errors=$((errors + 1))
    ;;
  frontmatter)
    echo "UNREADABLE FRONTMATTER: ${2}:${3}: ${4}" >&2
    errors=$((errors + 1))
    ;;
  *) ;;
  esac
}

hook_configs::scan check-hook-exec-form on_hook on_unreadable

if ((errors > 0)); then
  if ((execform_errors == 0)); then
    cat >&2 <<'UNREADABLE'

Nothing above is an exec-form violation: the gate refused input it could not
read. That is deliberate — a hook declaration this gate cannot parse is one it
cannot clear, and clearing it anyway is the silent no-op the gate exists to
catch. Fix the malformed JSON or YAML and the gate will read it.
UNREADABLE
    exit 1
  fi
  cat >&2 <<'REMEDY'

An exec-form hook (a hook object carrying `args`) resolves `command` as an
executable through PATH — it is not a shell command line. A bare name is
machine-dependent: on Windows `bash` resolves to the WSL relay shipped as
bash.exe under System32, and `python3` to a zero-length WindowsApps App
Execution Alias stub, so the hook never launches. A failed launch is a
NON-BLOCKING error, so a PreToolUse guard wired this way silently enforces
nothing (#1416: 73 recorded runs, every one a hook_non_blocking_error, while
the guard was believed live).

For a bash-scripted hook, run the script through the node launcher: `node` is
the bare name this gate allows, and the launcher finds a real bash itself, never
the WSL relay. The launcher comes first in `args`, then the script, then the
script's own arguments:

    "command": "node",
    "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs",
             "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh", "--flag"]

Each carrying plugin has its own hooks/exec-bash.mjs, copied from
lib/exec-bash.mjs by scripts/sync-shared-copies.sh. An option gate is a launcher
flag placed before the script: `--require-true NAME` or
`--run-if-unset-or-true NAME`.

Or keep exec form and give `command` a ${CLAUDE_PLUGIN_ROOT}-rooted or absolute
path to a real executable: a binary, not a script. On Windows exec form has no
shell to read a `#!` line, so a `.sh` path as `command` fails to spawn (EFTYPE).

This gate does not inspect shell form (the whole command line in `command`, no
`args`, `shell: bash`), so a hook written that way is not flagged.
REMEDY
  exit 1
fi
echo "No exec-form hooks with a bare command name."
