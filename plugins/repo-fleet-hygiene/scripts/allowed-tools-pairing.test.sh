#!/usr/bin/env bash
# test-scope: plugins/repo-fleet-hygiene/skills/*.md plugins/repo-fleet-hygiene/skills/*/scripts/*
# shellcheck disable=SC2016
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SKILLS=(audit apply sync setup)

expected_granted() {
  case "$1" in
  *) echo "" ;;
  esac
}

fails=0
pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1" >&2
  fails=1
}
note() { echo "NOTE: $1"; }

allowed_tools() {
  awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$1" |
    awk '/^allowed-tools:/{f=1;print;next} f&&/^[A-Za-z_-]+:/{exit} f'
}

for skill in "${SKILLS[@]}"; do
  md="skills/$skill/SKILL.md"
  [[ -f "$md" ]] || {
    fail "$skill: SKILL.md missing"
    continue
  }
  at="$(allowed_tools "$md")"

  if grep -qF 'Bash(bash ' <<<"$at"; then
    fail "$skill: allowed-tools carries an interpreter-led 'Bash(bash …' grant"
  else
    pass "$skill: no interpreter-led grant in allowed-tools"
  fi

  if grep -qF 'CLAUDE_PLUGIN_ROOT' <<<"$at"; then
    fail "$skill: allowed-tools uses \${CLAUDE_PLUGIN_ROOT} (repo convention: the skill-local path is the exercised shape. The token DOES substitute in a plugin skill; runtime matching is what is unverified)"
  else
    pass "$skill: allowed-tools free of \${CLAUDE_PLUGIN_ROOT}"
  fi

  mapfile -t mds < <(find "skills/$skill" -name '*.md' -not -path '*/evals/*' | sort)
  for f in "${mds[@]}"; do
    if grep -qF 'bash ${CLAUDE_SKILL_DIR}' "$f" || grep -qF 'bash "${CLAUDE_SKILL_DIR}' "$f"; then
      fail "$f: body invokes a bundled script through 'bash' — rule cannot stay non-interpreter-led"
    fi
    if grep -qF '"${CLAUDE_SKILL_DIR}/scripts/' "$f"; then
      fail "$f: body quotes the bundled-script path — an unquoted rule will not match it"
    fi
  done

  mapfile -t granted < <(grep -oE 'Bash\(\$\{CLAUDE_SKILL_DIR\}/scripts/[^:)]+' <<<"$at" | sed 's|.*/||')
  if [[ ${#granted[@]} -eq 0 ]]; then
    fail "$skill: no \${CLAUDE_SKILL_DIR} bundled-script grant found"
  fi
  for g in "${granted[@]}"; do
    if [[ -x "skills/$skill/scripts/$g" ]]; then
      pass "$skill: granted script $g exists and is executable"
    else
      fail "$skill: granted script $g missing or not executable"
    fi
    if grep -rqF "\${CLAUDE_SKILL_DIR}/scripts/$g" "skills/$skill" --include='*.md'; then
      pass "$skill: grant for $g is paired with a body invocation"
    else
      fail "$skill: grant for $g has no matching body invocation (dead grant)"
    fi
  done

  expected="$(expected_granted "$skill")"
  if [[ -n "$expected" ]]; then
    actual="$(printf '%s\n' "${granted[@]}" | sort -u | tr '\n' ' ')"
    actual="${actual% }"
    if [[ "$actual" == "$expected" ]]; then
      pass "$skill: granted set matches the allowlist exactly"
    else
      fail "$skill: granted set drifted from the allowlist
    expected: $expected
    actual:   $actual"
    fi
  else
    note "$skill: names no allowlist, so the granted-set comparison did not run"
  fi
done

if [[ $fails -ne 0 ]]; then
  echo "allowed-tools pairing contract violated." >&2
  exit 1
fi
echo "All allowed-tools pairing checks passed."
