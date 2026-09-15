#!/usr/bin/env bash
# Self-test for check-fleet-audit-doc-grammar.sh. Synthetic collector stubs and
# skill bodies prove each assertion and the inconclusive-probe guard; the
# historical block proves the gate goes red against the commit that shipped the
# docs-only silent revert (claude-code-plugins#2646 / #2713).
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A synthetic collector reproducing only the two probe surfaces the gate reads:
# the argument loop's treatment of a bare positional, and the no-scope stop.
#   $1 dir, $2 positional mode (accept|reject|ignore), $3 no-scope mode (stop|report|garble)
write_collector() {
  local dir="$1" positional="$2" noscope="$3"
  local positional_case
  case "$positional" in
  accept) positional_case='ROOTS+=("$1"); shift' ;;
  reject) positional_case='echo "Error: unknown argument: $1" >&2; exit 2' ;;
  ignore) positional_case='shift' ;;
  *)
    echo "write_collector: bad positional mode $positional" >&2
    exit 2
    ;;
  esac

  local noscope_body
  case "$noscope" in
  stop) noscope_body='cat >&2 <<'"'"'EOF'"'"'
Error: no scope resolved: no bare path, --root, or --repo

No bare path, --root, --repo, or --config was given. Give it a scope instead:

  <dir>            bare path — same as --root
  --root <dir>     bounded recursive repository discovery
  --repo <dir>     one exact repository or worktree
  --config <file>  a Git-format fleet config
EOF
exit 2' ;;
  report) noscope_body='echo "Fleet report: 0 repositories"; exit 0' ;;
  garble) noscope_body='echo "Error: something else entirely" >&2; exit 2' ;;
  *)
    echo "write_collector: bad no-scope mode $noscope" >&2
    exit 2
    ;;
  esac

  cat >"$dir/audit-fleet.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
ROOTS=()
APPLY=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
  --apply-plan)
    APPLY="\$2"
    shift 2
    ;;
  --root | --repo | --config)
    ROOTS+=("\$2")
    shift 2
    ;;
  -*)
    echo "Error: unknown argument: \$1" >&2
    exit 2
    ;;
  *)
    $positional_case
    ;;
  esac
done
if [[ -n "\$APPLY" ]]; then
  if [[ \${#ROOTS[@]} -gt 0 ]]; then
    echo "Error: --apply-plan cannot be combined with audit discovery flags" >&2
    exit 2
  fi
  [[ -f "\$APPLY" ]] || {
    echo "Error: apply-plan file not found: \$APPLY" >&2
    exit 2
  }
  echo "approval artifact"
  exit 0
fi
if [[ \${#ROOTS[@]} -eq 0 ]]; then
  $noscope_body
fi
echo "Fleet report: \${#ROOTS[@]} scope entries"
EOF
}

# A synthetic skill body. $2 is the argument-hint value; the remaining arguments
# are the grammar bullet tokens.
write_skill() {
  local dir="$1" hint="$2"
  shift 2
  {
    printf -- '---\n'
    printf 'description: "synthetic"\n'
    printf 'user-invocable: true\n'
    printf 'argument-hint: "%s"\n' "$hint"
    printf -- '---\n\n'
    printf '## Purpose\n\nSynthetic body.\n\n'
    printf '## Input resolution\n\n'
    local token
    for token in "$@"; do
      printf -- '- `%s <value>`: synthetic bullet.\n' "$token"
    done
    printf '\n## Evidence rules\n\n- `not-a-grammar-bullet`: outside the grammar section.\n'
  } >"$dir/SKILL.md"
}

run_check() {
  local dir="$1"
  FLEET_DOC_GRAMMAR_SCRIPT="$dir/audit-fleet.sh" \
    FLEET_DOC_GRAMMAR_SKILL="$dir/SKILL.md" \
    bash "$SCRIPT" --check 2>&1
}

new_case() {
  local dir
  dir="$(mktemp -d "$WORK/case.XXXXXX")"
  printf '%s' "$dir"
}

FULL_HINT='[<dir>]... [--root <dir>]... [--repo <dir>]... [--config <file>]'
NO_POSITIONAL_HINT='[--root <dir>]... [--repo <dir>]... [--config <file>]'

# Agreement passes.
dir="$(new_case)"
write_collector "$dir" accept stop
write_skill "$dir" "$FULL_HINT" '<dir>' --root --repo --config
out="$(run_check "$dir")"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "matching grammar passes --check"
else
  fail "matching grammar wrongly flagged: rc=$rc out='$out'"
fi

# Assertion 1, the #2646 shape: parser accepts a bare positional, argument-hint
# does not document one.
dir="$(new_case)"
write_collector "$dir" accept stop
write_skill "$dir" "$NO_POSITIONAL_HINT" --root --repo --config
out="$(run_check "$dir")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"parser accepts a bare positional path but argument-hint documents no bare positional form"* ]]; then
  ok "undocumented bare positional red-lines"
else
  fail "undocumented bare positional not caught: rc=$rc out='$out'"
fi

# Assertion 1, inverse: documented but not accepted.
dir="$(new_case)"
write_collector "$dir" reject stop
write_skill "$dir" "$FULL_HINT" '<dir>' --root --repo --config
out="$(run_check "$dir")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"argument-hint documents a bare positional form but the parser does not accept one (probe: rejected)"* ]]; then
  ok "documented-but-rejected bare positional red-lines"
else
  fail "documented-but-rejected positional not caught: rc=$rc out='$out'"
fi

# A silently ignored positional is not an accepted form either.
dir="$(new_case)"
write_collector "$dir" ignore stop
write_skill "$dir" "$FULL_HINT" '<dir>' --root --repo --config
out="$(run_check "$dir")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"(probe: ignored)"* ]]; then
  ok "silently ignored positional does not count as accepted"
else
  fail "ignored positional misclassified: rc=$rc out='$out'"
fi

# Assertion 2: a scope form the collector names with no grammar bullet.
dir="$(new_case)"
write_collector "$dir" accept stop
write_skill "$dir" "$FULL_HINT" '<dir>' --root --repo
out="$(run_check "$dir")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"the collector names '--config' as a way to supply scope, but"* ]]; then
  ok "undocumented scope form red-lines"
else
  fail "undocumented scope form not caught: rc=$rc out='$out'"
fi

# A backticked bullet outside the Input resolution section is not a grammar
# entry — write_skill puts one under Evidence rules on every case above.
dir="$(new_case)"
write_collector "$dir" accept stop
write_skill "$dir" "$FULL_HINT" '<dir>' --root --repo --config
if [[ "$(run_check "$dir")" == *"not-a-grammar-bullet"* ]]; then
  fail "a bullet outside the grammar section leaked into the grammar set"
else
  ok "bullets outside the Input resolution section are not grammar entries"
fi

# Assertion 3: a no-scope run that reports instead of stopping.
dir="$(new_case)"
write_collector "$dir" accept report
write_skill "$dir" "$FULL_HINT" '<dir>' --root --repo --config
out="$(run_check "$dir")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"a no-scope run produced a report"* ]]; then
  ok "no-scope run that reports red-lines"
else
  fail "no-scope report not caught: rc=$rc out='$out'"
fi

# Inconclusive guard: a no-scope stop with no parseable remedy block is exit 2,
# never a pass.
dir="$(new_case)"
write_collector "$dir" accept garble
write_skill "$dir" "$FULL_HINT" '<dir>' --root --repo --config
out="$(run_check "$dir")"
rc=$?
if [[ $rc -eq 2 && "$out" == *"probe inconclusive"* ]]; then
  ok "unparseable remedy block is inconclusive (exit 2), not a pass"
else
  fail "garbled no-scope probe did not go inconclusive: rc=$rc out='$out'"
fi

# Inconclusive guard: a skill body with no argument-hint is exit 2.
dir="$(new_case)"
write_collector "$dir" accept stop
write_skill "$dir" "$FULL_HINT" '<dir>' --root --repo --config
grep -v '^argument-hint:' "$dir/SKILL.md" >"$dir/SKILL.md.tmp"
mv "$dir/SKILL.md.tmp" "$dir/SKILL.md"
out="$(run_check "$dir")"
rc=$?
if [[ $rc -eq 2 && "$out" == *"no quoted argument-hint frontmatter field"* ]]; then
  ok "missing argument-hint is inconclusive (exit 2), not a pass"
else
  fail "missing argument-hint did not go inconclusive: rc=$rc out='$out'"
fi

# Inconclusive guard: a grammar list too small to be real is exit 2.
dir="$(new_case)"
write_collector "$dir" accept stop
write_skill "$dir" "$FULL_HINT" '<dir>' --root
out="$(run_check "$dir")"
rc=$?
if [[ $rc -eq 2 && "$out" == *"grammar list"*"bullet(s)"* ]]; then
  ok "an implausibly small grammar list is inconclusive (exit 2), not a pass"
else
  fail "small grammar list did not go inconclusive: rc=$rc out='$out'"
fi

# Historical proof (#2713): a6be07f9 is the merge of #2646 — the docs-only
# rebase that reverted the skill layer while leaving the parser untouched. The
# gate must go red on that pair, and must go GREEN when that same commit's
# parser is read against the current skill body, because the defect was
# entirely on the documentation side.
if git -C "$SELF_DIR/.." rev-parse --verify --quiet 'a6be07f9^{commit}' >/dev/null 2>&1; then
  hist="$WORK/historical"
  mkdir -p "$hist"
  git -C "$SELF_DIR/.." show 'a6be07f9:plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh' \
    >"$hist/audit-fleet.sh"
  git -C "$SELF_DIR/.." show 'a6be07f9:plugins/repo-fleet-hygiene/skills/audit/SKILL.md' \
    >"$hist/SKILL.md"

  out="$(run_check "$hist")"
  rc=$?
  if [[ $rc -eq 1 && "$out" == *"argument-hint documents no bare positional form"* ]]; then
    ok "a6be07f9 (#2646) goes red, naming the missing bare positional form"
  else
    fail "a6be07f9 did not go red on the bare positional: rc=$rc out='$out'"
  fi
  if [[ "$out" == *"the collector names '<dir>' as a way to supply scope"* ]]; then
    ok "a6be07f9 also goes red on the missing <dir> grammar bullet"
  else
    fail "a6be07f9 missing <dir> bullet not reported: out='$out'"
  fi

  out="$(
    FLEET_DOC_GRAMMAR_SCRIPT="$hist/audit-fleet.sh" \
      FLEET_DOC_GRAMMAR_SKILL="$SELF_DIR/../plugins/repo-fleet-hygiene/skills/audit/SKILL.md" \
      bash "$SCRIPT" --check 2>&1
  )"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    ok "a6be07f9's parser passes against the current skill body (the revert was docs-only)"
  else
    fail "a6be07f9's parser wrongly flagged against the current skill body: rc=$rc out='$out'"
  fi
else
  # Not a skip that vacates the case: the shipped-tree case below still runs,
  # and CI checks out full history precisely so this block executes there.
  echo "note: a6be07f9 not present in this clone; historical proof not evaluated" >&2
  fail "historical proof could not run (shallow clone) — fetch full history"
fi

# The shipped tree must pass.
out="$(cd "$SELF_DIR/.." && bash scripts/check-fleet-audit-doc-grammar.sh --check 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "shipped tree passes --check"
else
  fail "shipped tree fails --check: rc=$rc out='$out'"
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
