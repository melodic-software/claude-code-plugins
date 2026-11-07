#!/usr/bin/env bash
# Declares a convention home in the current repository: the marked pointer region in AGENTS.md,
# docs/conventions/architecture/README.md with architecture_dir docs/architecture, and, with
# --dialect, docs/conventions/authoring-formats/README.md setting diagram_dialect.system.
# Optional: --layers <list> adds component_layers; --landscape <dialect> adds landscape_dialect.
# The caller runs the repository guard first; this script only refuses to overwrite.
set -euo pipefail
set -o noclobber
dialect=""
layers=""
landscape=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --dialect) dialect="${2:?--dialect needs a value}" && shift 2 ;;
  --layers) layers="${2:?--layers needs a value}" && shift 2 ;;
  --landscape) landscape="${2:?--landscape needs a value}" && shift 2 ;;
  *) echo "unknown argument: $1" >&2 && exit 2 ;;
  esac
done

cat >AGENTS.md <<'MD'
# Agent instructions

<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `docs/conventions`. Read the topic doc there before changing a governed surface.
<!-- END GENERATED: convention-home -->
MD

mkdir -p docs/conventions/architecture
{
  printf '# architecture conventions\n\n```yaml\narchitecture_dir: docs/architecture\n'
  [[ -z "${landscape}" ]] || printf 'landscape_dialect: %s\n' "${landscape}"
  [[ -z "${layers}" ]] || printf 'component_layers: %s\n' "${layers}"
  printf '```\n'
} >docs/conventions/architecture/README.md

if [[ -n "${dialect}" ]]; then
  mkdir -p docs/conventions/authoring-formats
  # shellcheck disable=SC2016 # the backticks are a literal markdown fence
  printf '# authoring formats\n\n```yaml\ndiagram_dialect:\n  system: %s\n```\n' "${dialect}" \
    >docs/conventions/authoring-formats/README.md
fi
