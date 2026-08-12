#!/usr/bin/env bash
# Per-project state key for anything a plugin writes under ${CLAUDE_PLUGIN_DATA}.
#
# WHY. ${CLAUDE_PLUGIN_DATA} resolves to ~/.claude/plugins/data/{id}/, keyed to
# the plugin identifier and nothing else (plugins reference, § Persistent data
# directory). There is no project, checkout, worktree, or session segment in the
# formula. So a skill that writes a fixed filename there has one file per
# MACHINE: every run from every repository overwrites the last, and a skill that
# READS it back can serve one project's findings as another's.
#
# This prints the missing segment. The scheme is `audit-pass`'s, reused rather
# than reinvented — see
# skills/audit-pass/reference/run-state-and-resumability.md §3:
#
#   <state-key> = <repo-identity>/<worktree-discriminator>
#
#   repo-identity          the first configured remote URL normalized to
#                          host/owner/repo, lowercased, scheme/credentials/.git
#                          stripped. No remote -> local/<sha256 of repo root,12>.
#                          Not a repo at all -> nonrepo/<sha256 of cwd,12>.
#   worktree-discriminator sha256 of the canonicalized worktree root, cut to 8.
#                          Two worktrees of one repository legitimately hold
#                          different content and must not share a report.
#
# SECURITY — this is why the identity is validated rather than merely lowercased.
# A remote URL is arbitrary text that becomes DIRECTORY COMPONENTS in the caller's
# path. A remote of `../../../etc` would walk a report out of the plugin's own
# namespace. Any identity that is not a plain lowercase segment path is replaced
# by a hash, so it still keys deterministically and still stays inside the
# namespace. Every rejected shape is covered by state-key.test.sh.
#
# NOT a substitute for a per-run filename. Keying stops cross-project collision;
# it does not stop a same-project rerun overwriting yesterday's report. A caller
# that needs history writes one file per run under this key and appends a line
# to a history file — see docs/conventions/plugin-data-report-keying/.
#
# Usage:
#   state-key.sh [--root <path>] [--explain]
#
#   --root <path>  derive for that directory instead of the current one
#   --explain      write the rung taken and its inputs to stderr
#
# Exit: 0 always on a successful derivation — every input reaches some rung, so
# there is no "cannot key" outcome. 2 on a bad argument or an unusable --root.
#
# Shared source: this file is byte-identical across the plugins that carry it and
# is registered in scripts/cross-plugin-source-registry.txt. Edit the canonical
# copy (claude-config) and copy it over the others.

set -uo pipefail

usage() {
  cat <<'EOF'
state-key.sh — per-project state key for ${CLAUDE_PLUGIN_DATA} writes.

Prints <repo-identity>/<worktree-discriminator> for a directory, so a report
persisted under the plugin data directory belongs to one project rather than to
the machine.

Usage:
  state-key.sh [--root <path>] [--explain] [--help]

  --root <path>  derive for that directory instead of the current one
  --explain      write the rung taken and its inputs to stderr

Exit: 0 on a derivation; 2 on a bad argument or an unusable --root.
EOF
}

ROOT_ARG=""
EXPLAIN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --root needs a path" >&2
      exit 2
    fi
    ROOT_ARG="$2"
    shift 2
    ;;
  --explain)
    EXPLAIN=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -n "$ROOT_ARG" ]]; then
  if [[ ! -d "$ROOT_ARG" ]]; then
    echo "ERROR: --root is not a directory: $ROOT_ARG" >&2
    exit 2
  fi
  cd "$ROOT_ARG" || exit 2
fi

# sha256sum is absent on stock macOS; shasum -a 256 is the portable partner.
# Neither is guaranteed, so a third rung keeps the key derivable rather than
# letting the whole scheme fail on a minimal image.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256
  else
    echo "ERROR: no sha256sum or shasum on PATH — cannot derive a state key" >&2
    exit 2
  fi
}

hash12() { printf '%s' "$1" | sha256 | cut -c1-12; }
hash8() { printf '%s' "$1" | sha256 | cut -c1-8; }

# "the FIRST configured remote" — not necessarily one named `origin`. A repo
# whose only remote is `upstream` still has a remote and must not fall through
# to the local rung.
remote_name=$(git remote 2>/dev/null | tr -d '\r' | head -1)
remote=""
if [[ -n "$remote_name" ]]; then
  remote=$(git config --get "remote.${remote_name}.url" 2>/dev/null | tr -d '\r')
fi
# tr -d '\r': Git on Windows can return a CRLF-terminated path.
root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')

rung=""
if [[ -n "$remote" ]]; then
  identity=$(printf '%s' "$remote" |
    sed -e 's#^[a-z+]*://##' -e 's#^[^@/]*@##' -e 's#:#/#' -e 's#\.git$##' |
    tr '[:upper:]' '[:lower:]')
  # A remote URL is arbitrary text and becomes DIRECTORY COMPONENTS here, so
  # accept it only in the shape the scheme means — segments of [a-z0-9._-] each
  # starting alphanumeric. That rejects `../central` (a relative filesystem
  # remote, which would otherwise write outside the caller's namespace),
  # absolute local paths, and backslashes. Anything rejected still keys
  # deterministically, by hash.
  if printf '%s' "$identity" | grep -qE '^[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)*$'; then
    rung="remote"
  else
    identity="remote/$(hash12 "$remote")"
    rung="remote-hashed"
  fi
elif [[ -n "$root" ]]; then
  identity="local/$(hash12 "$root")"
  rung="local"
else
  # Not a git repository. `audit-pass`'s ladder stops at the two git rungs
  # because it refuses non-git targets; a report-only skill audits them, so the
  # scheme needs a third rung rather than a failure.
  identity="nonrepo/$(hash12 "$PWD")"
  rung="nonrepo"
fi

discriminator=$(hash8 "${root:-$PWD}")

if [[ $EXPLAIN -eq 1 ]]; then
  {
    echo "rung:          $rung"
    echo "remote:        ${remote:-<none>}"
    echo "repo root:     ${root:-<not a git repository>}"
    echo "cwd:           $PWD"
    echo "identity:      $identity"
    echo "discriminator: $discriminator"
  } >&2
fi

printf '%s/%s\n' "$identity" "$discriminator"
