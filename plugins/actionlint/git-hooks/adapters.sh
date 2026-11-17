#!/bin/sh
# shellcheck shell=bash
# actionlint's side of lib/git-hooks/resolve-tool.sh: the ecosystem id whose
# record setup reports (hooks never run it), the files it acts on, and its
# actionlint adapter. Sourced by the lint entry.
#
# The adapter governs a workflow file only when the repository's own actionlint
# config sits at the repository root: .github/actionlint.yaml or
# .github/actionlint.yml, the one place actionlint reads it from. Lint only:
# actionlint never rewrites, so there is no format concern. The embedded
# ShellCheck and pyflakes integrations stay off (-shellcheck= -pyflakes=):
# they spawn a process per run block.

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=actionlint
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=github-actions
# shellcheck disable=SC2034 # read by the entry: the config names whose drift refuses a commit
RT_DRIFT_CONFIGS="actionlint.yaml actionlint.yml"
AL_INSTALL='the kjanat/actionlint v1.17.0 release asset, checked against its checksums file: https://github.com/kjanat/actionlint/releases/tag/v1.17.0'
AL_FLAGS='-oneline -shellcheck= -pyflakes='

rt_wants() {
  case "$1" in
  .githooks/* | */.githooks/*) return 1 ;;
  .github/workflows/*.yml | .github/workflows/*.yaml | */.github/workflows/*.yml | */.github/workflows/*.yaml) return 0 ;;
  *) return 1 ;;
  esac
}

# al__config <root>: 0 when the root carries an actionlint config; AL_CONFIG
# names it, repo-relative.
al__config() {
  local name
  for name in actionlint.yaml actionlint.yml; do
    if [[ -f "$1/.github/$name" ]]; then
      AL_CONFIG=".github/$name"
      return 0
    fi
  done
  return 1
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entry
al__set() { # <root>
  RT_ADAPTER=actionlint RT_TOOL=actionlint RT_BIN=actionlint RT_DIR="$1" RT_INSTALL="$AL_INSTALL"
  RT_CONFIGS="actionlint.yaml actionlint.yml"
  RT_DETAIL="config $AL_CONFIG; binary actionlint on PATH"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entry
rt_adapter() { # <concern> <file> <root>
  [[ "$1" == lint ]] || return 1
  al__config "$3" || return 1
  al__set "$3"
  # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN and the files
  RT_SCRIPT='"$RT_BIN" '"$AL_FLAGS"' -- "$@"'
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() { # <concern> <root>
  if [[ "$1" != lint ]]; then
    RT_DETAIL="actionlint only lints"
    return 1
  fi
  if ! al__config "$2"; then
    RT_DETAIL="no actionlint config: .github/actionlint.yaml or .github/actionlint.yml"
    return 1
  fi
  al__set "$2"
}

# rt_config_counts <config path>: 0 only for the root's .github config, the
# one actionlint reads.
rt_config_counts() {
  [[ "$1" == .github/actionlint.yaml || "$1" == .github/actionlint.yml ]]
}

# rt_lint_index <path>: lint the staged copy of a file, for one partly staged
# or gone from the work tree; -stdin-filename keeps the config's paths: rules
# for that path and names it in the findings.
rt_lint_index() {
  # shellcheck disable=SC2086 # AL_FLAGS splits into its flags
  git show ":$1" 2>/dev/null | (cd "$RT_DIR" && "$RT_BIN" $AL_FLAGS -stdin-filename "$1" -)
  return "${PIPESTATUS[1]}"
}
