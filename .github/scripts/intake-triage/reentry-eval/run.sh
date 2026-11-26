#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 2 ]] || {
  echo "usage: run.sh <ci-workflows clone> <out dir> [plugin eval flags...]" >&2
  exit 2
}
clone=$1 out=$2
shift 2
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
git -C "$clone" show "$sha:.github/actions/check-intake-triage-verdict/verdict.cjs" >"$out/verdict.cjs"
node "$here/build-suite.mjs" --reusable "$out/reusable.yml" --verdict "$out/verdict.cjs" --sha "$sha" --out "$out/with"
node "$here/build-suite.mjs" --reusable "$out/reusable.yml" --verdict "$out/verdict.cjs" --sha "$sha" --out "$out/without" --no-instructions

flags=(--scaffold --trust-plugin --no-publish --model sonnet --judge-model opus --runs 3 -j 4 "$@")
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
plugin_eval=(env HOME="$out/home" CLAUDE_CONFIG_DIR="$config" CLAUDE_CODE_EFFORT_LEVEL=medium "${CLAUDE_BIN:-claude}" plugin eval)
rc=0
"${plugin_eval[@]}" "$out/with" "${flags[@]}" --output-dir "$out/results-with" || rc=$?
"${plugin_eval[@]}" "$out/without" "${flags[@]}" --ablation none --output-dir "$out/results-without" || rc=$?
echo "built from ci-workflows $sha (caller ref $ref); results in $out/results-with and $out/results-without"
exit "$rc"
