#!/usr/bin/env bash
# Tests for concat-gotchas.sh.
# Each case: PASS prints, FAIL prints. Non-zero exit on any FAIL.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/concat-gotchas.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: concat-gotchas.sh missing: $SCRIPT" >&2
  exit 1
fi

PASS=0
FAIL=0

# Fixture repos must never inherit the caller's git environment.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
NO_GIT=0

FIXTURES="$(mktemp -d)"
trap 'rm -rf "$FIXTURES"' EXIT

layer() {
  local path="$1" body="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$body" >"$path"
}

run_case() {
  local desc="$1" expected="$2"
  local actual
  if [[ "$NO_GIT" -eq 0 && ! -e "$CLAUDE_PROJECT_DIR/.git" && "$CLAUDE_PROJECT_DIR" != "$HOME" ]]; then
    git init -q "$CLAUDE_PROJECT_DIR"
  fi
  actual="$(HOME="$HOME" CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" bash "$SCRIPT")"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "       got:"
    printf '%s\n' "$actual" | sed 's/^/         /'
    echo "       wanted:"
    printf '%s\n' "$expected" | sed 's/^/         /'
    FAIL=$((FAIL + 1))
  fi
}

HOME="${FIXTURES}/empty-home"
CLAUDE_PROJECT_DIR="${FIXTURES}/empty-repo"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

run_case "no layers prints (none)" $'(none)'

HOME="${FIXTURES}/home-a"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-a"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.md" '# bugs config

```yaml
lanes: []
```

## Gotchas

- Team lane: skip the billing sandbox.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code span in the expected fixture, not substitution
run_case "team-only layer" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n- Team lane: skip the billing sandbox.\n' "$CLAUDE_PROJECT_DIR/.claude/bugs.md")"

HOME="${FIXTURES}/home-b"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-b"
mkdir -p "$HOME/.claude" "$CLAUDE_PROJECT_DIR/.claude"
layer "$HOME/.claude/bugs.md" '## Gotchas

- User: this machine has no GPU.
'
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.md" '# bugs

## Keys

lanes concatenate.

## Gotchas

- Team: do not file from the sandbox.
'
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md" '## Gotchas

- Overlay: my fork uses a different tracker.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected fixture, not substitution
run_case "three layers concatenate in cascade order" "$(printf '### Consumer gotchas (cascade)\n\n#### user-global (`%s`)\n\n- User: this machine has no GPU.\n\n#### team (`%s`)\n\n- Team: do not file from the sandbox.\n\n#### local overlay (`%s`)\n\n- Overlay: my fork uses a different tracker.\n' "$HOME/.claude/bugs.md" "$CLAUDE_PROJECT_DIR/.claude/bugs.md" "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md")"

HOME="${FIXTURES}/home-c"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-c"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.md" '# bugs

```markdown
## Gotchas

- Fenced: this is an example, not a gotcha.
```

## Gotchas

- Real: respect the fence.

## Next

- Ignore this.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code span in the expected fixture, not substitution
run_case "heading inside a fence is ignored; next H2 ends the section" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n- Real: respect the fence.\n' "$CLAUDE_PROJECT_DIR/.claude/bugs.md")"

HOME="${FIXTURES}/home-d"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-d"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.md" '## Gotchas

### Nested note

Keep the subsection.

## Other

Stop here.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code span in the expected fixture, not substitution
run_case "deeper heading is section content" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n### Nested note\n\nKeep the subsection.\n' "$CLAUDE_PROJECT_DIR/.claude/bugs.md")"

HOME="${FIXTURES}/home-e"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-e"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.md" '## Keys

lanes.

## Gotchas
'
run_case "empty Gotchas section is skipped" $'(none)'

HOME="${FIXTURES}/home-f"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-f"
mkdir -p "$HOME/.claude" "$CLAUDE_PROJECT_DIR"
layer "$HOME/.claude/bugs.md" '# no gotchas heading

lanes: []
'
run_case "layer without Gotchas heading is skipped" $'(none)'

HOME="${FIXTURES}/home-g"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-g"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.md" '## Gotchas

- Run the seed first:

```bash
## not a heading
make seed
```

## Next
'
# shellcheck disable=SC2016  # backticks are literal markdown in the expected output
run_case "fenced block inside Gotchas is kept whole" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n- Run the seed first:\n\n```bash\n## not a heading\nmake seed\n```\n' "$CLAUDE_PROJECT_DIR/.claude/bugs.md")"

HOME="${FIXTURES}/home-h"
CLAUDE_PROJECT_DIR="$HOME"
mkdir -p "$HOME/.claude"
layer "$HOME/.claude/bugs.md" '## Gotchas

- User: read once.
'
layer "$HOME/.claude/bugs.local.md" '## Gotchas

- Overlay under home: not a layer here.
'
# shellcheck disable=SC2016  # backticks are literal markdown in the expected output
run_case "home-rooted session reads user-global once, no team or overlay" "$(printf '### Consumer gotchas (cascade)\n\n#### user-global (`%s`)\n\n- User: read once.\n' "$HOME/.claude/bugs.md")"

HOME="${FIXTURES}/home-i"
CLAUDE_PROJECT_DIR="${FIXTURES}/not-a-repo"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.md" '## Gotchas

- Not a repository: skipped.
'
NO_GIT=1
run_case "root outside a git work tree has no team layer" $'(none)'
NO_GIT=0

if [[ "$FAIL" -gt 0 ]]; then
  echo "concat-gotchas tests: $PASS passed, $FAIL failed"
  exit 1
fi
echo "concat-gotchas tests: $PASS passed"
exit 0
