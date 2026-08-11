#!/usr/bin/env bash
# Contract: every bundled-script `allowed-tools` grant in this plugin is PAIRED
# with the invocation its skill body actually tells Claude to run.
#
# A Bash permission rule is matched against the literal command string, and
# `bash` is NOT one of the wrappers Claude Code strips before matching
# (the stripped set is timeout/time/nice/nohup/stdbuf/command/builtin/noglob).
# So `Bash(bash <path>:*)` is interpreter-led, while a rule written without
# `bash` stops matching the moment the body still says `bash <path>`. Only the
# paired form — direct invocation in the body, direct path in the rule — is both
# non-interpreter-led AND live. Quoting counts too: an unquoted rule does not
# match a quoted body path, which is how one grant in this repo shipped dead.
#
# `${CLAUDE_SKILL_DIR}` is the only skill-relative token substituted in
# `allowed-tools`; `${CLAUDE_PLUGIN_ROOT}` stays a literal string there and the
# grant is inert.
#
# SC2016 is disabled file-wide on purpose. Every single-quoted `${…}` here is a
# fixed string searched for VERBATIM in markdown and frontmatter, where those
# placeholders are substituted by Claude Code at load time. Letting the shell
# expand any of them would make this gate silently match nothing.
# shellcheck disable=SC2016
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SKILLS=(explore-directions pressure-test)

fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; fails=1; }

# Frontmatter is the leading `---`-delimited block; the allowed-tools value runs
# to the next top-level key so a YAML list is captured whole.
allowed_tools() {
  awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$1" |
    awk '/^allowed-tools:/{f=1;print;next} f&&/^[A-Za-z_-]+:/{exit} f'
}

for skill in "${SKILLS[@]}"; do
  md="skills/$skill/SKILL.md"
  [[ -f "$md" ]] || { fail "$skill: SKILL.md missing"; continue; }
  at="$(allowed_tools "$md")"

  if grep -qF 'Bash(bash ' <<<"$at"; then
    fail "$skill: allowed-tools carries an interpreter-led 'Bash(bash …' grant"
  else
    pass "$skill: no interpreter-led grant in allowed-tools"
  fi

  if grep -qF 'CLAUDE_PLUGIN_ROOT' <<<"$at"; then
    fail "$skill: allowed-tools uses \${CLAUDE_PLUGIN_ROOT} (never substituted there — inert grant)"
  else
    pass "$skill: allowed-tools free of \${CLAUDE_PLUGIN_ROOT}"
  fi

  # Every markdown file bundled with the skill must invoke the script the same
  # way the rule spells it: no `bash` wrapper, no quotes around the path.
  mapfile -t mds < <(find "skills/$skill" -name '*.md' -not -path '*/evals/*' | sort)
  for f in "${mds[@]}"; do
    if grep -qF 'bash ${CLAUDE_SKILL_DIR}' "$f" || grep -qF 'bash "${CLAUDE_SKILL_DIR}' "$f"; then
      fail "$f: body invokes a bundled script through 'bash' — rule cannot stay non-interpreter-led"
    fi
    if grep -qF '"${CLAUDE_SKILL_DIR}/scripts/' "$f"; then
      fail "$f: body quotes the bundled-script path — an unquoted rule will not match it"
    fi
  done

  # Each granted script must exist, be executable, and be invoked by the body —
  # a grant nothing runs is dead weight, and a non-executable target cannot be
  # invoked directly at all.
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
done

if [[ $fails -ne 0 ]]; then
  echo "allowed-tools pairing contract violated." >&2
  exit 1
fi
echo "All allowed-tools pairing checks passed."
