#!/usr/bin/env bash
# Decision rows are component decisions. A skip item leaves no row. A replace
# candidate awaiting a human verdict reads nominated, never replaced.
# shellcheck disable=SC2015  # ok/bad are pure; A && ok || bad is the assertion form
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECIDE="$SCRIPT_DIR/changelog-decisions.sh"
SURFACES="$SCRIPT_DIR/discover-surfaces.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

ok() { echo "ok: $*"; }
bad() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

cat >"$TMP/decisions.tsv" <<'EOF'
correct	Fable 5.1 supersedes Fable 5	257-001	docs/PLUGIN-PHILOSOPHY.md	Fable 5 the rung above / fable resolves to Fable 5.1	open	changelog says 5.1; docs page still says Fable 5
replace	Stale sandbox mask files	257-006	audit-install-state	/doctor warns for mask files	pending human verdict	
adopt	permission-prompts none	259-002	hop_chain.py	unattended runs no longer choose between dontAsk and bypassPermissions		
note	SessionStart is background	261-004	hook-budget	the hooks page says SessionStart runs in the background		
skip	vscode-only tooltip	261-099	—	ui only		
EOF

out=$(bash "$DECIDE" "$TMP/decisions.tsv")
rc=$?
[[ "$rc" -eq 0 ]] && ok "renderer exits 0" || bad "renderer exit $rc"
[[ "$out" == *"Fable 5.1 supersedes Fable 5"* ]] && ok "correct row emitted" || bad "missing correct row"
row=$(printf '%s\n' "$out" | grep 'Stale sandbox')
[[ "$row" == *"| nominated |"* ]] && ok "replace row is nominated" || bad "replace row: $row"
[[ "$row" != *"| replaced |"* ]] && ok "replace row is not marked replaced" || bad "row says replaced: $row"
[[ "$out" != *"vscode-only"* && "$out" != *"261-099"* ]] && ok "skip left no row" || bad "skip leaked: $out"
[[ "$out" == *"## Docs lag"* && "$out" == *"changelog says 5.1"* ]] && ok "docs lag carries the disagreement" || bad "docs lag missing"

printf 'correct\tNo sentence\t1\towner\t\t\t\n' >"$TMP/bad.tsv"
if bash "$DECIDE" "$TMP/bad.tsv" >/dev/null 2>"$TMP/err"; then
  bad "a correct row with no sentence was accepted"
else
  ok "a correct row with no sentence is rejected"
fi

# Marketplace and consumer shapes.
mk_root="$TMP/market"
mkdir -p "$mk_root/plugins/demo/.claude-plugin" "$mk_root/plugins/demo/skills/one" \
  "$mk_root/.claude-plugin" "$mk_root/docs/conventions/example" "$mk_root/.claude/rules"
printf '{}\n' >"$mk_root/.claude-plugin/marketplace.json"
printf '# s\n' >"$mk_root/plugins/demo/skills/one/SKILL.md"
printf '# c\n' >"$mk_root/docs/conventions/example/README.md"
printf '# r\n' >"$mk_root/.claude/rules/a.md"
m_out=$(bash "$SURFACES" "$mk_root")
[[ "$m_out" == "repo-shape: marketplace"* ]] && ok "marketplace shape" || bad "marketplace shape: $m_out"
[[ "$m_out" == *"plugins"* && "$m_out" == *"plugin skills"* ]] && ok "marketplace classes" || bad "marketplace classes: $m_out"

c_root="$TMP/consumer"
mkdir -p "$c_root/.claude/rules" "$c_root/.claude/skills/local"
printf '# project\n' >"$c_root/CLAUDE.md"
printf '# rule\n' >"$c_root/.claude/rules/b.md"
printf '# skill\n' >"$c_root/.claude/skills/local/SKILL.md"
c_out=$(bash "$SURFACES" "$c_root")
[[ "$c_out" == "repo-shape: consumer"* ]] && ok "consumer shape" || bad "consumer shape: $c_out"
[[ "$c_out" == *"CLAUDE.md"* && "$c_out" == *"path-scoped rules"* ]] && ok "consumer classes" || bad "consumer classes: $c_out"
[[ "$c_out" != *"repo-shape: marketplace"* ]] && ok "consumer is not a marketplace" || bad "consumer labeled marketplace"

echo "FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
