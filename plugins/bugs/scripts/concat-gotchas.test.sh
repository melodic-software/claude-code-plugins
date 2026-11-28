#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/concat-gotchas.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: concat-gotchas.sh missing: $SCRIPT" >&2
  exit 1
fi

PASS=0
FAIL=0

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1
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
  shift 2
  local actual
  if [[ "$NO_GIT" -eq 0 && ! -e "$CLAUDE_PROJECT_DIR/.git" && "$CLAUDE_PROJECT_DIR" != "$HOME" ]]; then
    git init -q "$CLAUDE_PROJECT_DIR"
  fi
  actual="$(HOME="$HOME" CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" bash "$SCRIPT" "$@")"
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
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '# bugs config

```yaml
areas: []
```

## Gotchas

- Team focus area: skip the billing sandbox.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code span in the expected fixture, not substitution
run_case "team-only layer" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n- Team focus area: skip the billing sandbox.\n' "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md")"

HOME="${FIXTURES}/home-k"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-k"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '# bugs

Why the focus areas are what they are.

## Gotchas

- Team: the docs home holds the team gotchas.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code span in the expected fixture, not substitution
run_case "team layer from docs/conventions/bugs.md" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n- Team: the docs home holds the team gotchas.\n' "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md")"

HOME="${FIXTURES}/home-b"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-b"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
layer "$HOME/notes/bugs-gotchas.md" '## Gotchas

- User: this machine has no GPU.
'
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '# bugs

## Keys

focus areas concatenate.

## Gotchas

- Team: do not file from the sandbox.
'
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md" '## Gotchas

- Personal override: my fork uses a different tracker.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected fixture, not substitution
run_case "new layers only concatenate in cascade order, no warning" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (`%s`)\n\n- User: this machine has no GPU.\n\n#### team (`%s`)\n\n- Team: do not file from the sandbox.\n\n#### personal override (`%s`)\n\n- Personal override: my fork uses a different tracker.\n' "$HOME/notes/bugs-gotchas.md" "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md")" --user-file "$HOME/notes/bugs-gotchas.md"

HOME="${FIXTURES}/home-l"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-l"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
layer "$HOME/.claude/bugs.md" '## Gotchas

- Old user: ignored.
'
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md" '## Gotchas

- Old personal: ignored.
'
# shellcheck disable=SC2016  # literal placeholder passed to test the unexpanded option form
run_case "retired old paths alone are ignored, no warning" $'(none)' --user-file '${user_config.gotchas_file}'
run_case "empty option value is unset: retired old paths are ignored" $'(none)' --user-file ''
run_case "option naming a missing file ignores retired old paths" $'(none)' --user-file "$HOME/notes/missing.md"

layer "$HOME/notes/bugs-gotchas.md" '## Gotchas

- New user: read.
'
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md" '## Gotchas

- New personal: read.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected fixture, not substitution
run_case "new files beside retired old paths: only new files are read, no warning" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (`%s`)\n\n- New user: read.\n\n#### personal override (`%s`)\n\n- New personal: read.\n' "$HOME/notes/bugs-gotchas.md" "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md")" --user-file "$HOME/notes/bugs-gotchas.md"

HOME="${FIXTURES}/home-m"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-m"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '## Gotchas

- Shared: read once, as the userConfig layer.
'
# shellcheck disable=SC2016  # backticks are literal markdown in the expected output
run_case "team file named by the option is read once, as the userConfig layer" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (`%s`)\n\n- Shared: read once, as the userConfig layer.\n' "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md")" --user-file "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md"

HOME="${FIXTURES}/home-c"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-c"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '# bugs

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
run_case "heading inside a fence is ignored; next H2 ends the section" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n- Real: respect the fence.\n' "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md")"

HOME="${FIXTURES}/home-d"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-d"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '## Gotchas

### Nested note

Keep the subsection.

## Other

Stop here.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code span in the expected fixture, not substitution
run_case "deeper heading is section content" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n### Nested note\n\nKeep the subsection.\n' "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md")"

HOME="${FIXTURES}/home-e"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-e"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '## Keys

focus areas.

## Gotchas
'
run_case "empty Gotchas section is skipped" $'(none)'

HOME="${FIXTURES}/home-f"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-f"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
layer "$HOME/bugs-gotchas.md" '# no gotchas heading

areas: []
'
run_case "layer without Gotchas heading is skipped" $'(none)' --user-file "$HOME/bugs-gotchas.md"

HOME="${FIXTURES}/home-g"
CLAUDE_PROJECT_DIR="${FIXTURES}/repo-g"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '## Gotchas

- Run the seed first:

```bash
## not a heading
make seed
```

## Next
'
# shellcheck disable=SC2016  # backticks are literal markdown in the expected output
run_case "fenced block inside Gotchas is kept whole" "$(printf '### Consumer gotchas (cascade)\n\n#### team (`%s`)\n\n- Run the seed first:\n\n```bash\n## not a heading\nmake seed\n```\n' "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md")"

HOME="${FIXTURES}/home-h"
CLAUDE_PROJECT_DIR="$HOME"
mkdir -p "$HOME"
layer "$HOME/docs/conventions/bugs.md" '## Gotchas

- User: read once.
'
layer "$HOME/docs/conventions/bugs.local.md" '## Gotchas

- Personal override under home: not a layer here.
'
# shellcheck disable=SC2016  # backticks are literal markdown in the expected output
run_case "home-rooted session reads the userConfig file once, no team layer or personal override" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (`%s`)\n\n- User: read once.\n' "$HOME/docs/conventions/bugs.md")" --user-file "$HOME/docs/conventions/bugs.md"

HOME="${FIXTURES}/home-i"
CLAUDE_PROJECT_DIR="${FIXTURES}/not-a-repo"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '## Gotchas

- Not a repository: skipped.
'
NO_GIT=1
run_case "root outside a git work tree has no team layer" $'(none)'
NO_GIT=0

HOME="${FIXTURES}/home-j/user"
CLAUDE_PROJECT_DIR="${FIXTURES}/home-j/USER"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.md" '## Gotchas

- Home in another case: not a team layer.
'
run_case "root equal to home up to case has no team layer" $'(none)'

if [[ "$FAIL" -gt 0 ]]; then
  echo "concat-gotchas tests: $PASS passed, $FAIL failed"
  exit 1
fi
echo "concat-gotchas tests: $PASS passed"
exit 0
