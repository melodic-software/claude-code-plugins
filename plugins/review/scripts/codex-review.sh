#!/usr/bin/env bash
# Run the OpenAI Codex plugin's (`codex@openai-codex`) review through its companion runtime
# script. The plugin's `/codex:*` commands set `disable-model-invocation: true`, so a skill cannot
# invoke them; this script runs the same `codex-companion.mjs` those commands run, by the plugin's
# install path as `claude plugin list --json` reports it.
#
# Usage (from the root of the repository under review):
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-review.sh" --base <ref> [--adversarial]
#        [--model <model>] [--brief-file <file>]
#
# `--brief-file` runs adversarial-review with the file's text as its focus text. Both review
# commands review committed history from the base only, take a model and no effort, and keep no
# resumable thread; this script never runs the companion's task mode.
#
# Output: the first stdout line is the surface status, one of
#   codex: ran
#   codex: skipped (<reason>)
#   codex: failed (<reason>)
# After `codex: ran`, the rest of stdout is the review exactly as the companion printed it.
# `skipped` means Codex never started: no node, no claude CLI, the plugin not installed or not
# enabled, its companion missing, or the Codex CLI absent or not logged in. `failed` means the
# review started and exited non-zero.
#
# Exit code: 0 for every status, 2 for a usage error.
#
# Environment:
#   FANOUT_CODEX_CLAUDE_BIN  the claude CLI to ask for the install path (default: claude)
set -uo pipefail

usage() {
  cat <<'EOF'
codex-review.sh: run the Codex plugin's review through its companion runtime script.

Usage:
  codex-review.sh --base <ref> [--adversarial] [--model <model>] [--brief-file <file>]

  --base <ref>          the review diff base, passed to Codex as --base
  --adversarial         run adversarial-review instead of review
  --model <model>       the Codex model, passed through as --model
  --brief-file <file>   run adversarial-review with the file's text as focus text

Prints `codex: ran` and the review, or `codex: skipped (<reason>)`, or
`codex: failed (<reason>)`. Exits 0 for each, 2 for a usage error.
EOF
}

base=""
command_name="review"
model=""
brief_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --base)
    if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
      printf 'codex-review.sh: --base needs a ref\n' >&2
      exit 2
    fi
    base="$2"
    shift 2
    ;;
  --adversarial)
    command_name="adversarial-review"
    shift
    ;;
  --model)
    if [[ $# -lt 2 || ! "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]]; then
      printf 'codex-review.sh: --model needs a model name (letters, digits, ".", "_", ":", "/", "-")\n' >&2
      exit 2
    fi
    model="$2"
    shift 2
    ;;
  --brief-file)
    if [[ $# -lt 2 || ! -f "$2" || ! -r "$2" || ! -s "$2" ]]; then
      printf 'codex-review.sh: --brief-file needs a readable, non-empty file\n' >&2
      exit 2
    fi
    brief_file="$2"
    command_name="adversarial-review"
    shift 2
    ;;
  *)
    printf 'codex-review.sh: unknown argument: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -z "$base" ]]; then
  printf 'codex-review.sh: --base <ref> is required\n' >&2
  exit 2
fi

skip() {
  printf 'codex: skipped (%s)\n' "$1"
  exit 0
}

command -v node >/dev/null 2>&1 || skip "node not found"

claude_bin="${FANOUT_CODEX_CLAUDE_BIN:-claude}"
command -v "$claude_bin" >/dev/null 2>&1 || skip "claude CLI not found, so the codex plugin cannot be located"

plugin_list=$("$claude_bin" plugin list --json 2>/dev/null) || skip "claude plugin list --json failed"

# The first enabled codex@openai-codex installation. A plugin loaded in place from its
# marketplace folder reports that folder as readFromFolder instead of installPath.
plugin_root=$(printf '%s' "$plugin_list" | node -e '
let entries;
try { entries = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch {}
if (!Array.isArray(entries)) process.stdout.write("::unreadable::");
else {
  const hit = entries.find((e) => e && e.id === "codex@openai-codex" && e.enabled === true);
  const root = hit && (hit.readFromFolder || hit.installPath);
  if (typeof root === "string" && root) process.stdout.write(root);
}
' 2>/dev/null)
[[ "$plugin_root" != "::unreadable::" ]] || skip "claude plugin list --json gave no readable list"
[[ -n "$plugin_root" ]] || skip "codex@openai-codex is not installed or not enabled"

companion="$plugin_root/scripts/codex-companion.mjs"
[[ -f "$companion" ]] || skip "codex companion runtime not found at $companion"

# `setup --json` with neither review-gate flag only reports; it changes nothing.
setup_json=$(node "$companion" setup --json 2>/dev/null)
readiness=$(printf '%s' "$setup_json" | node -e '
let status = "unreadable";
try {
  const report = JSON.parse(require("fs").readFileSync(0, "utf8"));
  status = report?.codex?.available !== true ? "no-cli" : report.auth?.loggedIn !== true ? "no-login" : "ready";
} catch {}
process.stdout.write(status);
' 2>/dev/null)
case "$readiness" in
ready) ;;
no-cli) skip "Codex CLI not installed" ;;
no-login) skip "Codex CLI not logged in" ;;
*) skip "codex setup check gave no readable report" ;;
esac

stderr_file=$(mktemp) || skip "mktemp failed"
trap 'rm -f "$stderr_file"' EXIT
args=("$command_name" --wait --base "$base")
[[ -z "$model" ]] || args+=(--model "$model")
# `--` ends the companion's options, so focus text starting with a dash stays text.
[[ -z "$brief_file" ]] || args+=(-- "$(cat "$brief_file")")
rc=0
review=$(node "$companion" "${args[@]}" 2>"$stderr_file") || rc=$?
if [[ "$rc" -ne 0 ]]; then
  last_error=$(grep -v '^[[:space:]]*$' "$stderr_file" | tail -n 1)
  printf 'codex: failed (%s exited %s%s)\n' "$command_name" "$rc" "${last_error:+: $last_error}"
  exit 0
fi
printf 'codex: ran\n'
printf '%s\n' "$review"
