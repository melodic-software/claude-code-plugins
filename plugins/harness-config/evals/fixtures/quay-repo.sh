#!/usr/bin/env bash
# Seeds quay, a small Python service, in a git repository on main, with one variant of Claude Code
# configuration on top. Usage: quay-repo.sh <variant>
#   plain         project settings with one narrow allow rule
#   grants       fragile allow grants: an interpreter wildcard, a user-home path, a project skill
#                 naming the plugin-root token, and a bundled plugin that self-grants permissions
#   exempt        one interpreter-wildcard grant that CLAUDE.md declares a deliberate exemption
#   state-merge   a project deny and a local allow for the same rule, and a boolean disableAutoMode
#   state-entry   allow rules of several shapes for an auto-mode carry-over question
#   state-broken  project rules plus a local settings file that is not valid JSON
#   automation    formatter and linter already run by pre-commit and CI, no database, and a history
#                 whose only "secret" commits are dependency bumps
#   postures      three project skills: one deletes with no gate, one delegates deletion to a
#                 script that asks first, and one reports and stops
#   unhobble      instruction surfaces of mixed kinds and two hooks, one a policy gate
set -euo pipefail

variant="${1:?usage: quay-repo.sh <variant>}"

mkdir -p .claude src/quay tests
printf '__pycache__/\n.venv/\n.claude/settings.local.json\n' >.gitignore
printf 'def handle(order):\n    return {"id": order["id"], "status": "queued"}\n' >src/quay/app.py
printf 'from quay.app import handle\n\n\ndef test_handle():\n    assert handle({"id": 1})["status"] == "queued"\n' >tests/test_app.py
cat >pyproject.toml <<'TOML'
[project]
name = "quay"
version = "0.4.0"
dependencies = ["httpx>=0.27", "secrets-manager-client>=2.1"]

[tool.ruff]
line-length = 100
TOML

cat >CLAUDE.md <<'MD'
# Quay

Quay queues outbound orders for the warehouse service.

## Commands

- `pytest` runs the tests.
- `ruff check .` and `ruff format .` lint and format.
MD

case "$variant" in
plain)
  printf '{\n  "permissions": {\n    "allow": ["Bash(pytest)"]\n  }\n}\n' >.claude/settings.json
  ;;
grants)
  owner="dana"
  cat >.claude/settings.json <<JSON
{
  "permissions": {
    "allow": [
      "Bash(pytest)",
      "Bash(python3 *)",
      "Bash(/home/${owner}/tools/release.sh:*)"
    ]
  }
}
JSON
  mkdir -p .claude/skills/release
  cat >.claude/skills/release/SKILL.md <<'MD'
---
name: release
description: Tag a quay release. Use when asked to cut or tag a release.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/tag.sh *)
---

# Release

Run `scripts/tag.sh <version>` and push the tag.
MD
  mkdir -p plugins/quay-tools/.claude-plugin plugins/quay-tools/skills/notes plugins/quay-tools/scripts
  printf '{\n  "name": "quay-tools",\n  "version": "0.1.0"\n}\n' >plugins/quay-tools/.claude-plugin/plugin.json
  cat >plugins/quay-tools/settings.json <<'JSON'
{
  "permissions": {
    "allow": ["Bash(ruff format *)"]
  }
}
JSON
  cat >plugins/quay-tools/skills/notes/SKILL.md <<'MD'
---
name: notes
description: Format quay release notes. Use when asked to tidy release notes.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/fmt-notes.sh *)
---

# Notes

Run the shared formatter on the notes file.
MD
  printf '#!/usr/bin/env bash\ncat "$@"\n' >plugins/quay-tools/scripts/fmt-notes.sh
  chmod +x plugins/quay-tools/scripts/fmt-notes.sh
  ;;
exempt)
  cat >.claude/settings.json <<'JSON'
{
  "permissions": {
    "allow": ["Bash(pytest)", "Bash(python3 *)"]
  }
}
JSON
  cat >>CLAUDE.md <<'MD'

## Permission exemptions

- `Bash(python3 *)` in `.claude/settings.json` is a deliberate broad grant. The data scripts under
  `scripts/` are run ad hoc, and we accept the auto-mode drop for this one rule.
MD
  ;;
state-merge)
  cat >.claude/settings.json <<'JSON'
{
  "permissions": {
    "allow": ["Bash(pytest)"],
    "deny": ["Bash(git push:*)"],
    "disableAutoMode": true
  }
}
JSON
  cat >.claude/settings.local.json <<'JSON'
{
  "permissions": {
    "allow": ["Bash(git push:*)"]
  }
}
JSON
  ;;
state-entry)
  cat >.claude/settings.json <<'JSON'
{
  "permissions": {
    "allow": ["Bash(pytest)", "Bash(ruff check .)", "Bash(python3 *)", "Bash(npx *)"]
  }
}
JSON
  ;;
state-broken)
  cat >.claude/settings.json <<'JSON'
{
  "permissions": {
    "allow": ["Bash(pytest)"],
    "deny": ["Read(./.env)"]
  }
}
JSON
  printf '{\n  "permissions": {\n    "allow": ["Bash(ruff check .)",]\n  \n' >.claude/settings.local.json
  ;;
automation)
  mkdir -p .github/workflows
  cat >.pre-commit-config.yaml <<'YAML'
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
      - id: ruff-format
YAML
  cat >.github/workflows/ci.yml <<'YAML'
name: ci
on: [pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ruff pytest
      - run: ruff format --check .
      - run: ruff check .
      - run: pytest
YAML
  printf '{\n  "permissions": {\n    "allow": ["Bash(pytest)", "Bash(ruff check .)"]\n  }\n}\n' >.claude/settings.json
  ;;
postures)
  mkdir -p .claude/skills/purge-builds .claude/skills/wipe-cache .claude/skills/lint-report scripts
  cat >.claude/skills/purge-builds/SKILL.md <<'MD'
---
name: purge-builds
description: Free disk space by deleting quay build output and stale release branches. Use when the disk is full or builds are stale.
---

# Purge builds

1. Run `rm -rf build/ dist/ .venv/` from the repository root.
2. Delete every remote branch named `release/*` older than 30 days with `git push origin --delete <branch>`.
3. Report how much space was freed.
MD
  cat >.claude/skills/wipe-cache/SKILL.md <<'MD'
---
name: wipe-cache
description: Clear quay's local HTTP cache. Use when responses look stale.
---

# Wipe cache

Run `bash scripts/wipe-cache.sh` and report what it printed.
MD
  cat >scripts/wipe-cache.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cache_dir="${QUAY_CACHE_DIR:-.cache/http}"
if ! { : </dev/tty; } 2>/dev/null; then
  echo "wipe-cache needs a person at a terminal to confirm. Nothing deleted." >&2
  exit 1
fi
read -r -p "Delete everything under ${cache_dir}? [y/N] " answer </dev/tty
[[ "$answer" == "y" ]] || { echo "Nothing deleted."; exit 0; }
rm -rf "${cache_dir:?}/"*
echo "Cache cleared."
SH
  chmod +x scripts/wipe-cache.sh
  cat >.claude/skills/lint-report/SKILL.md <<'MD'
---
name: lint-report
description: Summarize ruff findings for quay. Use when asked what the linter reports.
---

# Lint report

1. Run `ruff check . --output-format concise`.
2. Group the findings by rule and list the three most common.
3. Ask the user which group to fix first, then stop.
MD
  ;;
unhobble)
  mkdir -p .claude/rules .claude/hooks
  cat >>CLAUDE.md <<'MD'

## Conventions

- Order ids are integers, never strings.
- Public functions carry type hints.

## Working style

- Think step by step before every answer.
- Always read a file in full before editing it.
- Never guess a command; run `pytest` to check.
MD
  cat >.claude/rules/python-style.md <<'MD'
---
paths: ["src/**/*.py"]
---

- Prefer f-strings over `%` formatting.
- Keep functions under 40 lines.
MD
  cat >.claude/hooks/secret-gate.sh <<'SH'
#!/usr/bin/env bash
# Blocks a commit command whose staged diff adds a line that looks like a credential.
input="$(cat)"
case "$input" in
*'git commit'*)
  if git diff --cached | grep -E -q '^\+.*(api_key|secret_key)\s*='; then
    echo "Staged diff adds a credential-like line; remove it before committing." >&2
    exit 2
  fi
  ;;
esac
exit 0
SH
  cat >.claude/hooks/think-reminder.sh <<'SH'
#!/usr/bin/env bash
# Adds a coaching reminder to every prompt. Silent unless QUAY_COACH is set.
[[ -n "${QUAY_COACH:-}" ]] && echo "Reminder: plan before you edit."
exit 0
SH
  chmod +x .claude/hooks/secret-gate.sh .claude/hooks/think-reminder.sh
  cat >.claude/settings.json <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/secret-gate.sh"}]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/think-reminder.sh"}]
      }
    ]
  }
}
JSON
  ;;
*)
  echo "unknown variant: $variant" >&2
  exit 2
  ;;
esac

git init -q -b main
git config user.name quay
git config user.email quay@example.invalid
git add -A
git commit -q -m "feat: seed quay order queue"

if [[ "$variant" == "automation" ]]; then
  for n in 1 2 3 4 5 6; do
    printf '# bump %s\n' "$n" >>pyproject.toml
    git commit -q -am "chore(deps): bump secrets-manager-client to 2.1.$n"
  done
  for msg in "fix: retry warehouse timeouts" "feat: add order status endpoint" "docs: describe queue states" \
    "fix: handle empty order payloads" "refactor: split handler module" "test: cover retry path"; do
    printf '# %s\n' "$msg" >>src/quay/app.py
    git commit -q -am "$msg"
  done
fi
