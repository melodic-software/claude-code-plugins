#!/usr/bin/env bash
# Gate: the audit skill's documented argument grammar must match what
# audit-fleet.sh actually accepts.
#
#   scripts/check-fleet-audit-doc-grammar.sh --check
#
# Why this lives outside SKILL.md and audit-fleet.sh: #2646 rebased cleanly and
# reverted only the skill prose, leaving the parser untouched. Every script-side
# test stayed green while the skill instructed agents to refuse a valid
# invocation (claude-code-plugins#2713). A check that only lives inside either
# protected file cannot defend the agreement between them.
#
# Agreement is established by probing the script and reading its answers — never
# by pattern-matching the parser source:
#   1. Bare positional is in both or neither (probe --apply-plan <missing> <dir>).
#   2. Every scope form the no-scope remedy names has a grammar bullet in SKILL.md.
#   3. No-scope stops non-zero with the remedy block (no report).
#
# The environment is sealed (HOME / USERPROFILE / CLAUDE_PROJECT_DIR /
# XDG_CONFIG_HOME → scratch) so a maintainer config cannot change the verdict.
# An unrecognized probe outcome is a hard exit 2 ("probe inconclusive"), never
# a pass. FLEET_DOC_GRAMMAR_SCRIPT / FLEET_DOC_GRAMMAR_SKILL override paths
# (self-test injection and historical proofs).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

SCRIPT="${FLEET_DOC_GRAMMAR_SCRIPT:-plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh}"
SKILL="${FLEET_DOC_GRAMMAR_SKILL:-plugins/repo-fleet-hygiene/skills/audit/SKILL.md}"

mode="${1:-}"
case "$mode" in
--check) ;;
*)
  echo "usage: $(basename "$0") --check" >&2
  exit 2
  ;;
esac

if [[ ! -f "$SCRIPT" ]]; then
  echo "check-fleet-audit-doc-grammar: collector not found: $SCRIPT" >&2
  exit 2
fi
if [[ ! -f "$SKILL" ]]; then
  echo "check-fleet-audit-doc-grammar: skill not found: $SKILL" >&2
  exit 2
fi

seal_dir="$(mktemp -d)"
probe_out="$seal_dir/probe.out"
trap 'rm -rf "$seal_dir"' EXIT
mkdir -p "$seal_dir/home" "$seal_dir/xdg" "$seal_dir/project" "$seal_dir/probe"

# Seal config/project env so probes never reach a maintainer fleet config or an
# incidental project-scoped rung. No network, no gh, no discovery.
run_sealed() {
  env -i \
    PATH="$PATH" \
    HOME="$seal_dir/home" \
    USERPROFILE="$seal_dir/home" \
    XDG_CONFIG_HOME="$seal_dir/xdg" \
    CLAUDE_PROJECT_DIR="$seal_dir/project" \
    TMPDIR="$seal_dir/probe" \
    bash "$SCRIPT" "$@" >"$probe_out" 2>&1
}

# Classify --apply-plan <missing> <dir>: three distinguishable outcomes after the
# argument loop and before config resolution / discovery.
#   rejected     → "unknown argument"
#   accepted     → "cannot be combined with audit discovery flags"
#   ignored      → "apply-plan file not found"
# anything else  → inconclusive (exit 2)
classify_bare_positional() {
  local missing="$seal_dir/probe/missing-plan-$$.json"
  local bare="$seal_dir/probe/bare-dir-$$"
  mkdir -p "$bare"
  rm -f "$missing"
  run_sealed --apply-plan "$missing" "$bare" || true
  if grep -Fq "unknown argument" "$probe_out"; then
    printf 'rejected'
    return 0
  fi
  if grep -Fq "cannot be combined with audit discovery flags" "$probe_out"; then
    printf 'accepted'
    return 0
  fi
  if grep -Fq "apply-plan file not found" "$probe_out"; then
    printf 'ignored'
    return 0
  fi
  echo "check-fleet-audit-doc-grammar: probe inconclusive (bare positional): $(tr '\n' ' ' <"$probe_out")" >&2
  exit 2
}

# argument-hint carries a bare positional form when it documents [<dir>], not
# merely --root <dir> / --repo <dir> as flag values.
argument_hint_has_bare() {
  local hint
  hint="$(grep -E '^argument-hint:' "$SKILL" | head -n1 || true)"
  [[ -n "$hint" ]] || return 1
  [[ "$hint" == *'[<dir>]'* ]]
}

# Leading code span of each Input-resolution grammar bullet (structured surface).
grammar_spans() {
  awk '
    /^## Input resolution/ { p = 1; next }
    p && /^## / { exit }
    p && /^- `/ {
      line = $0
      sub(/^- `/, "", line)
      sub(/`.*/, "", line)
      if (length(line) > 0) print line
    }
  ' "$SKILL"
}

grammar_covers_token() {
  local token="$1" span
  while IFS= read -r span; do
    [[ -n "$span" ]] || continue
    if [[ "$span" == "$token" || "$span" == "$token "* ]]; then
      return 0
    fi
  done < <(grammar_spans)
  return 1
}

# No-scope probe: must stop non-zero with the remedy block, never a report.
# Parse scope tokens from the script's own remedy (first field of each indented
# form line), so the expected set tracks the script without a hand list.
probe_no_scope_and_collect_tokens() {
  local tokens_file="$1" rc=0
  run_sealed || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "check-fleet-audit-doc-grammar: no-scope probe exited 0 (expected non-zero stop)" >&2
    exit 2
  fi
  if ! grep -Fq "no scope resolved" "$probe_out"; then
    echo "check-fleet-audit-doc-grammar: probe inconclusive (no-scope): $(tr '\n' ' ' <"$probe_out")" >&2
    exit 2
  fi
  # Remedy block: either the no-config form ("Give it a scope instead") or the
  # consumed-empty-config form ("Add scope to that config"). Sealed env should
  # hit the former; either way we require the indented scope-form lines.
  if ! grep -Eq 'Give it a scope instead|Add scope to that config' "$probe_out"; then
    echo "check-fleet-audit-doc-grammar: no-scope stop missing remedy block" >&2
    exit 1
  fi
  if grep -Eq 'Fleet verdict|Repo Fleet Hygiene —|repositories_audited' "$probe_out"; then
    echo "check-fleet-audit-doc-grammar: no-scope probe produced a report instead of stopping" >&2
    exit 1
  fi

  : >"$tokens_file"
  # Indented remedy forms: "  <dir> ..." or "  --root <dir> ..." (not git config lines).
  while IFS= read -r line; do
    case "$line" in
    '  <dir>'* | '  --'[a-z]*)
      # First field; for "--root <dir>" keep only --root.
      # shellcheck disable=SC2086 # intentional word-split of the indented form line
      set -- $line
      token="$1"
      [[ -n "$token" ]] || continue
      printf '%s\n' "$token" >>"$tokens_file"
      ;;
    *) ;;
    esac
  done <"$probe_out"
  if [[ ! -s "$tokens_file" ]]; then
    echo "check-fleet-audit-doc-grammar: probe inconclusive (no scope tokens in remedy)" >&2
    exit 2
  fi
  sort -u -o "$tokens_file" "$tokens_file"
}

errors=0

bare_status="$(classify_bare_positional)"
case "$bare_status" in
accepted)
  if argument_hint_has_bare; then
    :
  else
    echo "MISSING BARE POSITIONAL: parser accepts a bare <dir> but argument-hint does not document [<dir>]" >&2
    errors=$((errors + 1))
  fi
  if ! grammar_covers_token '<dir>'; then
    echo "MISSING GRAMMAR BULLET: parser accepts a bare <dir> but Input resolution has no \`<dir>\` bullet" >&2
    errors=$((errors + 1))
  fi
  ;;
rejected | ignored)
  if argument_hint_has_bare; then
    echo "STALE BARE POSITIONAL: argument-hint documents [<dir>] but parser does not accept a bare path ($bare_status)" >&2
    errors=$((errors + 1))
  fi
  if grammar_covers_token '<dir>'; then
    echo "STALE GRAMMAR BULLET: Input resolution documents \`<dir>\` but parser does not accept a bare path ($bare_status)" >&2
    errors=$((errors + 1))
  fi
  ;;
*)
  echo "check-fleet-audit-doc-grammar: probe inconclusive (bare status '$bare_status')" >&2
  exit 2
  ;;
esac

tokens_tmp="$seal_dir/tokens"
probe_no_scope_and_collect_tokens "$tokens_tmp"

while IFS= read -r token; do
  [[ -n "$token" ]] || continue
  # Bare <dir> is already asserted against the bare-positional probe above.
  [[ "$token" == '<dir>' ]] && continue
  if ! grammar_covers_token "$token"; then
    echo "MISSING GRAMMAR BULLET: remedy names $token but Input resolution has no matching bullet" >&2
    errors=$((errors + 1))
  fi
done <"$tokens_tmp"

if [[ "$errors" -gt 0 ]]; then
  echo "check-fleet-audit-doc-grammar: FAILED — $errors gap(s)" >&2
  exit 1
fi

echo "check-fleet-audit-doc-grammar: passed — documented grammar matches parser probes"
exit 0
