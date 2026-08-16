#!/usr/bin/env bash
# Self-test for check-fleet-audit-doc-grammar.sh. Synthetic trees prove each
# assertion and the inconclusive-probe guard; a historical extract of a6be07f9
# proves the gate goes red on the docs-only silent revert (#2713).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-fleet-audit-doc-grammar.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# Minimal stub collector: classifies the bare-positional probe and the no-scope
# probe from argv / emptiness without touching git or the network.
write_stub_script() {
  local path="$1"
  local bare_mode="$2" # accept | reject | ignore | noise
  local noscope_mode="$3" # remedy | report | noise | zero
  cat >"$path" <<EOF
#!/usr/bin/env bash
set -uo pipefail
# synthetic audit-fleet stub for doc-grammar self-test
if [[ "\${1:-}" == "--apply-plan" ]]; then
  case "$bare_mode" in
  accept)
    if [[ \$# -ge 3 ]]; then
      echo "Error: --apply-plan cannot be combined with audit discovery flags" >&2
      exit 2
    fi
    echo "Error: apply-plan file not found: \$2" >&2
    exit 2
    ;;
  reject)
    if [[ \$# -ge 3 ]]; then
      echo "Error: unknown argument: \$3" >&2
      exit 2
    fi
    echo "Error: apply-plan file not found: \$2" >&2
    exit 2
    ;;
  ignore)
    echo "Error: apply-plan file not found: \$2" >&2
    exit 2
    ;;
  noise)
    echo "Error: something unexpected happened" >&2
    exit 2
    ;;
  esac
fi
if [[ \$# -eq 0 ]]; then
  case "$noscope_mode" in
  remedy)
    echo "Error: no scope resolved: no bare path, --root, or --repo, and no config-supplied fleet.root/fleet.repo" >&2
    cat >&2 <<'REMEDY'

No bare path, --root, --repo, or --config was given, so no repository scope resolved. Give it a scope instead:

  <dir>            bare path — same as --root (drive roots like D: are allowed)
  --root <dir>     bounded recursive repository discovery
  --repo <dir>     one exact repository or worktree
  --config <file>  a Git-format fleet config listing fleet.root / fleet.repo entries

Or run /repo-fleet-hygiene:setup apply to write a config the audit picks up on its own.
REMEDY
    exit 2
    ;;
  report)
    echo "Error: no scope resolved: no bare path, --root, or --repo, and no config-supplied fleet.root/fleet.repo" >&2
    echo "Give it a scope instead:" >&2
    echo "  --root <dir>     bounded recursive repository discovery" >&2
    echo "Fleet verdict: CLEAN" >&2
    exit 2
    ;;
  noise)
    echo "Error: unexpected no-scope failure mode" >&2
    exit 2
    ;;
  zero)
    echo "Fleet verdict: CLEAN"
    exit 0
    ;;
  esac
fi
echo "Error: unexpected stub invocation: \$*" >&2
exit 2
EOF
  chmod +x "$path"
}

write_skill() {
  local path="$1"
  local hint="$2"
  shift 2
  {
    printf '%s\n' '---'
    printf 'argument-hint: "%s"\n' "$hint"
    printf '%s\n' '---'
    printf '%s\n' ''
    printf '%s\n' '## Input resolution'
    printf '%s\n' ''
    local bullet
    for bullet in "$@"; do
      # shellcheck disable=SC2016 # markdown code spans use literal backticks
      printf -- '- `%s`: synthetic grammar bullet\n' "$bullet"
    done
    printf '%s\n' ''
    printf '%s\n' '## Evidence rules'
    printf '%s\n' ''
    printf '%s\n' 'Synthetic skill body.'
  } >"$path"
}

mk_tree() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/plugins/repo-fleet-hygiene/skills/audit/scripts" "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-fleet-audit-doc-grammar.sh"
  printf '%s' "$dir"
}

run_check() {
  local repo="$1"
  (cd "$repo" && bash scripts/check-fleet-audit-doc-grammar.sh --check)
}

# Aligned tree: bare accepted + hint + grammar bullets covering remedy tokens.
repo="$(mk_tree)"
write_stub_script "$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" accept remedy
write_skill "$repo/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
  '[<dir>]... [--root <dir>]... [--repo <dir>]... [--config <file>] | --apply-plan <path>' \
  '<dir>' '--root <dir>' '--repo <dir>' '--config <file>' '--apply-plan <path>'
if run_check "$repo" >/dev/null; then ok "aligned skill+parser passes --check"; else fail "aligned tree wrongly flagged"; fi
rm -rf "$repo"

# Bare accepted but argument-hint omits [<dir>] (the #2646 shape).
repo="$(mk_tree)"
write_stub_script "$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" accept remedy
write_skill "$repo/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
  '[--root <dir>]... [--repo <dir>]... [--config <file>] | --apply-plan <path>' \
  '<dir>' '--root <dir>' '--repo <dir>' '--config <file>'
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"MISSING BARE POSITIONAL"* ]]; then
  ok "missing bare positional in argument-hint red-lines"
else
  fail "missing bare positional not caught: rc=$rc out='$out'"
fi
rm -rf "$repo"

# Bare accepted but Input-resolution grammar omits the <dir> bullet.
repo="$(mk_tree)"
write_stub_script "$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" accept remedy
write_skill "$repo/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
  '[<dir>]... [--root <dir>]... [--repo <dir>]... [--config <file>] | --apply-plan <path>' \
  '--root <dir>' '--repo <dir>' '--config <file>'
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"MISSING GRAMMAR BULLET"* && "$out" == *'<dir>'* ]]; then
  ok "missing <dir> grammar bullet red-lines"
else
  fail "missing <dir> bullet not caught: rc=$rc out='$out'"
fi
rm -rf "$repo"

# Remedy names --repo but skill omits that bullet.
repo="$(mk_tree)"
write_stub_script "$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" accept remedy
write_skill "$repo/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
  '[<dir>]... [--root <dir>]... [--config <file>] | --apply-plan <path>' \
  '<dir>' '--root <dir>' '--config <file>'
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"MISSING GRAMMAR BULLET"* && "$out" == *'--repo'* ]]; then
  ok "missing --repo grammar bullet red-lines"
else
  fail "missing --repo bullet not caught: rc=$rc out='$out'"
fi
rm -rf "$repo"

# Hint documents bare positional but parser rejects it.
repo="$(mk_tree)"
write_stub_script "$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" reject remedy
write_skill "$repo/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
  '[<dir>]... [--root <dir>]... [--repo <dir>]... [--config <file>] | --apply-plan <path>' \
  '<dir>' '--root <dir>' '--repo <dir>' '--config <file>'
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"STALE BARE POSITIONAL"* ]]; then
  ok "stale bare positional in argument-hint red-lines"
else
  fail "stale bare positional not caught: rc=$rc out='$out'"
fi
rm -rf "$repo"

# No-scope produces a report instead of a clean stop.
repo="$(mk_tree)"
write_stub_script "$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" accept report
write_skill "$repo/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
  '[<dir>]... [--root <dir>]... [--repo <dir>]... [--config <file>] | --apply-plan <path>' \
  '<dir>' '--root <dir>' '--repo <dir>' '--config <file>'
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"produced a report"* ]]; then
  ok "no-scope report-instead-of-stop red-lines"
else
  fail "no-scope report not caught: rc=$rc out='$out'"
fi
rm -rf "$repo"

# Inconclusive bare-positional probe → exit 2 (never a pass).
repo="$(mk_tree)"
write_stub_script "$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" noise remedy
write_skill "$repo/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
  '[<dir>]... [--root <dir>]... [--repo <dir>]... [--config <file>] | --apply-plan <path>' \
  '<dir>' '--root <dir>' '--repo <dir>' '--config <file>'
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"probe inconclusive"* ]]; then
  ok "inconclusive bare probe exits 2"
else
  fail "inconclusive bare probe not guarded: rc=$rc out='$out'"
fi
rm -rf "$repo"

# Inconclusive no-scope probe → exit 2.
repo="$(mk_tree)"
write_stub_script "$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" accept noise
write_skill "$repo/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
  '[<dir>]... [--root <dir>]... [--repo <dir>]... [--config <file>] | --apply-plan <path>' \
  '<dir>' '--root <dir>' '--repo <dir>' '--config <file>'
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"probe inconclusive"* ]]; then
  ok "inconclusive no-scope probe exits 2"
else
  fail "inconclusive no-scope probe not guarded: rc=$rc out='$out'"
fi
rm -rf "$repo"

# Historical proof (#2713): a6be07f9's SKILL.md + audit-fleet.sh must go red,
# naming the missing bare positional form.
if git rev-parse --verify --quiet "a6be07f9^{commit}" >/dev/null 2>&1; then
  hist="$(mktemp -d)"
  mkdir -p "$hist/scripts" \
    "$hist/a6be07f9/plugins/repo-fleet-hygiene/skills/audit/scripts"
  cp "$SCRIPT" "$hist/scripts/check-fleet-audit-doc-grammar.sh"
  git show a6be07f9:plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh \
    >"$hist/a6be07f9/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh"
  git show a6be07f9:plugins/repo-fleet-hygiene/skills/audit/SKILL.md \
    >"$hist/a6be07f9/plugins/repo-fleet-hygiene/skills/audit/SKILL.md"
  chmod +x "$hist/a6be07f9/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh"
  out="$(
    cd "$hist" &&
      FLEET_DOC_GRAMMAR_SCRIPT="$hist/a6be07f9/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" \
        FLEET_DOC_GRAMMAR_SKILL="$hist/a6be07f9/plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
        bash scripts/check-fleet-audit-doc-grammar.sh --check 2>&1
  )"
  rc=$?
  if [[ $rc -ne 0 && "$out" == *"MISSING BARE POSITIONAL"* ]]; then
    ok "historical a6be07f9 goes red naming missing bare positional"
  else
    fail "historical a6be07f9 did not go red as expected: rc=$rc out='$out'"
  fi
  rm -rf "$hist"
else
  # Historical proof-of-red must fail closed when the anchor is unavailable —
  # scoring the skip as ok would let a shallow clone or rewritten history
  # report green while proving nothing (#2807).
  fail "historical proof unavailable (a6be07f9 not in this clone)"
fi

# Live tree must pass.
if (cd "$SELF_DIR/.." && bash scripts/check-fleet-audit-doc-grammar.sh --check) >/dev/null; then
  ok "repository skill+parser passes --check"
else
  fail "repository skill+parser fails --check"
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
