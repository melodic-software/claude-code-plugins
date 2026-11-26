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

- Old user: still applies.
'
layer "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md" '## Gotchas

- Old personal: still applies.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected warning, not substitution
old_read() { printf 'Warning: bugs read `%s`, an old config path. Run `/bugs:setup apply` to %s, then delete the old file.' "$1" "$2"; }
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected warning, not substitution
superseded() { printf 'Warning: bugs no longer reads the gotchas in `%s`, because `%s` supplies the %s layer. Run `/bugs:setup apply` to %s, then delete the old file.' "$1" "$2" "$3" "$4"; }
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected warning, not substitution
user_move() { printf 'move its `## Gotchas` to %s and any `areas` or `filing_posture` to the homes `/bugs:setup check` names' "$1"; }
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected warning, not substitution
personal_move() { printf 'move what it holds into `%s`' "$1"; }
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected warning, not substitution
any_user_file='a file outside `~/.claude` that the bugs `gotchas_file` option names'

# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected fixture, not substitution
run_case "old files only: values apply, one warning per old file" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (old path) (`%s`)\n\n- Old user: still applies.\n\n#### personal override (old path) (`%s`)\n\n- Old personal: still applies.\n' "$HOME/.claude/bugs.md" "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md")"$'\n\n'"$(old_read "$HOME/.claude/bugs.md" "$(user_move "$any_user_file")")"$'\n\n'"$(old_read "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md" "$(personal_move "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md")")" --user-file '${user_config.gotchas_file}'

# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected fixture, not substitution
run_case "empty option value is unset: old file read" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (old path) (`%s`)\n\n- Old user: still applies.\n\n#### personal override (old path) (`%s`)\n\n- Old personal: still applies.\n' "$HOME/.claude/bugs.md" "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md")"$'\n\n'"$(old_read "$HOME/.claude/bugs.md" "$(user_move "$any_user_file")")"$'\n\n'"$(old_read "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md" "$(personal_move "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md")")" --user-file ''

layer "$HOME/notes/bugs-gotchas.md" '## Gotchas

- New user: wins.
'
layer "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md" '## Gotchas

- New personal: wins.
'
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected fixture, not substitution
run_case "both present: new wins, warning names both" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (`%s`)\n\n- New user: wins.\n\n#### personal override (`%s`)\n\n- New personal: wins.\n' "$HOME/notes/bugs-gotchas.md" "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md")"$'\n\n'"$(superseded "$HOME/.claude/bugs.md" "$HOME/notes/bugs-gotchas.md" userConfig "$(user_move "\`$HOME/notes/bugs-gotchas.md\`")")"$'\n\n'"$(superseded "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md" "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md" "personal override" "$(personal_move "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md")")" --user-file "$HOME/notes/bugs-gotchas.md"

rm "$CLAUDE_PROJECT_DIR/docs/conventions/bugs.local.md" "$CLAUDE_PROJECT_DIR/.claude/bugs.local.md"
# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected fixture, not substitution
run_case "option naming the old file reads it as the old path, with a warning" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (old path) (`%s`)\n\n- Old user: still applies.\n' "$HOME/.claude/bugs.md")"$'\n\n'"$(old_read "$HOME/.claude/bugs.md" "$(user_move "$any_user_file")")" --user-file "$HOME/.claude/bugs.md"

# shellcheck disable=SC2016  # backticks are the literal markdown code spans in the expected fixture, not substitution
run_case "option naming a missing file leaves the old file read, warning names the option's file" "$(printf '### Consumer gotchas (cascade)\n\n#### userConfig (old path) (`%s`)\n\n- Old user: still applies.\n' "$HOME/.claude/bugs.md")"$'\n\n'"$(old_read "$HOME/.claude/bugs.md" "$(user_move "\`$HOME/notes/missing.md\`")")" --user-file "$HOME/notes/missing.md"

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
