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
# Two-form split (decide-lane #2237, DEFER): `SKILL.md` uses the paired
# `${CLAUDE_SKILL_DIR}/scripts/…` form that matches its grants; bundled
# `context/*.md` files keep the interpreter-led
# `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/…` form because substitution
# of `${CLAUDE_SKILL_DIR}` into on-demand context files is unverified — a wrong
# conversion expands to `/scripts/…` and fails silently. See
# `skills/clean/reference/invocation-forms.md`.
#
# SC2016 is disabled file-wide on purpose. Every single-quoted `${…}` here is a
# fixed string searched for VERBATIM in markdown and frontmatter, where those
# placeholders are substituted by Claude Code at load time. Letting the shell
# expand any of them would make this gate silently match nothing.
# shellcheck disable=SC2016
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SKILLS=(clean)

# Optional per-skill allowlist, space-separated and sorted. When a skill names
# one, the granted set must equal it EXACTLY — this is the guard for a
# deliberate narrowing decision, which the pairing checks below cannot catch on
# their own: a script that is bundled, executable, and mentioned in the body
# "pairs" fine, so a later edit could re-widen the grant to cover it and every
# other assertion here would still pass green.
# `clean` names one because its grant scope carries real blast radius: only the
# READ-ONLY scripts are pre-approved. The mutating ones (clean-caches,
# clean-build, git-prune, git-tree-reset[-batch], remove-path, clean-batch) must
# keep routing through the PreToolUse destructive guard and the permission flow,
# and every one of them is bundled, executable, and invoked in the skill's
# markdown — so without this allowlist a grant added for any of them would
# satisfy every other check here and land silently.
expected_granted() {
  case "$1" in
    clean) echo "git-branch-audit.sh git-stash-audit.sh preflight.sh resolve-clean-action.sh scan.sh" ;;
    *) echo "" ;;
  esac
}

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
    # Bundled context files must stay on `${CLAUDE_PLUGIN_ROOT}` until substitution
    # scope for on-demand context is verified (#2237). Direct
    # `${CLAUDE_SKILL_DIR}/scripts/…` there would look paired but expand to
    # `/scripts/…` if the placeholder is not substituted.
    if [[ "$f" == skills/*/context/* ]]; then
      if grep -qF '${CLAUDE_SKILL_DIR}/scripts/' "$f"; then
        fail "$f: context file must not use \${CLAUDE_SKILL_DIR}/scripts/ — keep \${CLAUDE_PLUGIN_ROOT} form (#2237)"
      fi
      # Every bundled-script reference must retain the interpreter-led PLUGIN_ROOT
      # prefix — banning SKILL_DIR alone still passes if a command is rerouted to
      # another invalid path such as bash /wrong/preflight.sh.
      required='bash ${CLAUDE_PLUGIN_ROOT}/skills/'"$skill"'/scripts/'
      invocations="$(grep -F 'skills/'"$skill"'/scripts/' "$f" || true)"
      if [[ -n "$invocations" ]]; then
        while IFS= read -r line; do
          if [[ "$line" != *"$required"* ]]; then
            fail "$f: context script invocation must use bash \${CLAUDE_PLUGIN_ROOT}/skills/$skill/scripts/… — got: $line"
          fi
        done <<<"$invocations"
        pass "$f: context script invocations use interpreter-led \${CLAUDE_PLUGIN_ROOT} form"
      else
        pass "$f: context file has no bundled-script invocations to pin"
      fi
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
  fi
done

if [[ $fails -ne 0 ]]; then
  echo "allowed-tools pairing contract violated." >&2
  exit 1
fi
echo "All allowed-tools pairing checks passed."
