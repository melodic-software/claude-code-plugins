#!/usr/bin/env bash
# Runs the intake re-entry eval (#8491) on the subscription login: builds the
# suite from a ci-workflows clone at the ref the caller pins, with and without
# this repository's instructions, outside any git tree, then runs
# `claude plugin eval` on each build at the triage profile's model.
#
#   run.sh <ci-workflows clone> <out dir outside any git tree> [extra plugin eval flags...]
set -euo pipefail

[[ $# -ge 2 ]] || {
  echo "usage: run.sh <ci-workflows clone> <out dir> [plugin eval flags...]" >&2
  exit 2
}
clone=$1 out=$2
shift 2
# Subscription login only: an API key in the environment would bill it instead.
if [[ -n "${ANTHROPIC_API_KEY:-}" || -n "${CLAUDE_API_KEY:-}" ]]; then
  echo "run.sh: an API key is set; this eval runs on the subscription login only" >&2
  exit 2
fi
if git -C "$(dirname "$out")" rev-parse --git-dir >/dev/null 2>&1; then
  echo "run.sh: $out is inside a git tree; plugin eval needs a copy outside one" >&2
  exit 2
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
caller="$here/../../../workflows/intake-triage.yml"
ref=$(sed -n 's|^ *uses: melodic-software/ci-workflows/\.github/workflows/intake-triage\.yml@\([^ ]*\).*|\1|p' "$caller")
git -C "$clone" fetch --quiet origin
sha=$(git -C "$clone" rev-parse "origin/$ref^{commit}" 2>/dev/null || git -C "$clone" rev-parse "$ref^{commit}")
mkdir -p "$out/home"
git -C "$clone" show "$sha:.github/workflows/intake-triage.yml" >"$out/reusable.yml"
node "$here/build-suite.mjs" --reusable "$out/reusable.yml" --sha "$sha" --out "$out/with"
node "$here/build-suite.mjs" --reusable "$out/reusable.yml" --sha "$sha" --out "$out/without" --no-instructions

# The triage profile (docs/conventions/pr-pipeline.yaml, models.profiles.triage).
flags=(--scaffold --trust-plugin --no-publish --model sonnet --judge-model opus --runs 3 -j 4 "$@")
# An empty HOME keeps the host's own stores (a Docker context link among them)
# out of the run; the login stays in the operator's config dir.
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
env=(env HOME="$out/home" CLAUDE_CONFIG_DIR="$config" CLAUDE_CODE_EFFORT_LEVEL=medium "${CLAUDE_BIN:-claude}" plugin eval)
# A failing case exits nonzero; run the baseline either way.
rc=0
"${env[@]}" "$out/with" "${flags[@]}" --output-dir "$out/results-with" || rc=$?
"${env[@]}" "$out/without" "${flags[@]}" --ablation none --output-dir "$out/results-without" || rc=$?
echo "built from ci-workflows $sha (caller ref $ref); results in $out/results-with and $out/results-without"
exit "$rc"
