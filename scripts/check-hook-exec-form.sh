#!/usr/bin/env bash
# Gate: an exec-form hook must not resolve `command` as a bare PATH lookup.
#
#   scripts/check-hook-exec-form.sh    fail on any exec-form hook whose
#                                      `command` is a bare executable name
#
# Why: a hook object that carries `args` is in EXEC form, and exec form resolves
# `command` as an executable through PATH — it is not a shell command line. A
# bare name is therefore machine-dependent, and on Windows two spellings resolve
# to something that is not the interpreter the author meant:
#   * `bash`/`sh` -> the WSL relay C:\Windows\System32\bash.exe, which dies with
#     `execvpe(/bin/bash) failed: No such file or directory` when no distro
#     provides /bin/bash;
#   * `python`/`python3`/`py` -> the zero-length WindowsApps App Execution Alias
#     stub, which opens the Store instead of running the script.
# A failed hook launch is a NON-BLOCKING error, so a PreToolUse guard wired this
# way silently enforces nothing. That is not hypothetical: #1416 recorded 73
# launches of the disk-hygiene destructive guard, every one of them a
# `hook_non_blocking_error`, while the issue was closed COMPLETED.
#
# Why a gate rather than a checklist: this class has shipped three times.
# #1006 fixed it; #1504 reintroduced it while fixing a different resolution bug;
# #2570 fixed it again. `plugins/harness-config/skills/audit/reference/
# audit-checklist.md` Category D has carried it as an `error` row the whole
# time — a checklist a human reads is not a gate.
#
# The rule: exec form (an `args` key on the hook object) whose `command`
# contains NO path separator (`/` or `\`) fails, unless the name is on
# EXEC_NAME_ALLOWLIST in scripts/lib/hook-configs.sh. Deliberately broader than a denylist of the names
# that have already burned us: a denylist can only ever hold the spellings
# someone was burned by, which is exactly how a {bash, sh} list would have waved
# `python3` through. `${CLAUDE_PLUGIN_ROOT}`-rooted and absolute paths carry a
# separator and pass untouched; so does shell form, which has no `args` at all
# and is never inspected here.
#
# Scope: the plugin hook-config corpus scripts/lib/hook-configs.sh enumerates,
# the same one the sibling userconfig-argv gate covers (the default
# `plugins/*/hooks/hooks.json`, manifest-pointed hook config files and inline
# manifest `hooks` maps) PLUS skill/agent YAML frontmatter `hooks:` blocks,
# which that gate does not cover and which is where the third instance of this
# defect lived (#2568). `.claude/settings.json` is repo-local developer config
# rather than shipped plugin surface and is out of scope; it declares no hooks
# today. The library reads JSON with `jq` and frontmatter with a real YAML
# parser (scripts/check-hook-exec-form-frontmatter.py records why); both only
# REPORT hooks, and the rule below decides.
#
# Relationship to scripts/check-hook-userconfig-argv.sh: complementary, not
# overlapping. That gate constrains WHETHER a `${user_config.*}` token may
# appear in a hook config; this one constrains WHAT SHAPE `command` takes once a
# hook is in exec form. Neither subsumes the other.
#
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr. That is
# the whole family's contract, stated once in scripts/README.md, "The check-script
# contract", and held by scripts/check-script-contract.test.sh. A hook
# declaration in the TREE that this gate cannot parse is a finding (1), not an
# environment problem: the input is what is wrong, and clearing it would be the
# silent no-op the gate exists to catch. Exit 2 is reserved for the reader side
# — no jq, no PyYAML, a frontmatter reader that did not complete — where nothing
# was inspected at all.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/hook-configs.sh
. scripts/lib/hook-configs.sh || exit 2

errors=0
execform_errors=0

# on_hook <file> <where> <form> <args> <command> <argv>: flag an exec-form hook
# whose command carries no path separator in either spelling (Claude Code
# resolves it through PATH) and is not an allowlisted name.
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

# on_unreadable <surface> <file> <where> <detail>. Fail closed on an unparsable
# hook config or frontmatter: input this gate cannot read is input it cannot
# clear. An unparsable manifest is skipped; manifest validity has its own gate.
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
