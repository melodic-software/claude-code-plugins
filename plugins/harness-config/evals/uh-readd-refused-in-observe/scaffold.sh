#!/usr/bin/env bash
# The quay repo mid-experiment: an experiment branch with the strip committed, phase observe, and a three-row stumble ledger.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" unhobble
git switch -q -c experiment/unhobble-opus-5-5
base="$(git rev-parse HEAD)"
dir=.claude/unhobble/quay-opus-5-5-20261020-k7q2
mkdir -p "$dir"
cat >"$dir/manifest.json" <<JSON
{
  "experiment_id": "quay-opus-5-5-20261020-k7q2",
  "origin_url": "",
  "branch": "experiment/unhobble-opus-5-5",
  "branch_deviation": "",
  "base_commit": "$base",
  "target_model": "opus-5-5",
  "effort": "high",
  "phase": "observe",
  "phase_timestamps": {"snapshot": "2026-10-20T09:12:00Z", "bare": "2026-10-20T09:40:00Z", "observe": "2026-10-21T08:05:00Z"},
  "surfaces": [
    {"path": "CLAUDE.md", "class": "convention", "action": "split", "stripped_sections": ["Working style"], "restore": "git"},
    {"path": ".claude/rules/python-style.md", "class": "behavioral", "action": "stripped", "restore": "git"},
    {"path": ".claude/settings.json#hooks.UserPromptSubmit[0]", "class": "behavioral", "action": "stripped", "restore": "manifest-backup"},
    {"path": ".claude/settings.json#hooks.PreToolUse[0]", "class": "policy", "action": "kept"}
  ]
}
JSON
cat >"$dir/stumbles.md" <<'MD'
# Stumbles

| Date | Task | What happened | Expected | Suspected missing instruction | Severity | Effort |
|------|------|---------------|----------|-------------------------------|----------|--------|
| 2026-10-22 | add retry to handler | ran `python -m pytest tests` from src/ and got import errors | run `pytest` from the root | run pytest from the repository root | low | high |
| 2026-10-24 | order status endpoint | ran `pytest` inside src/quay and saw no tests collected | run `pytest` from the root | run pytest from the repository root | low | high |
| 2026-10-27 | split handler module | used `%` formatting in a new log line | f-strings | prefer f-strings | low | high |
MD
git rm -q .claude/rules/python-style.md
sed -i '/^## Working style/,$d' CLAUDE.md
jq 'del(.hooks.UserPromptSubmit)' .claude/settings.json >.claude/settings.json.new
mv .claude/settings.json.new .claude/settings.json
git add -A
git commit -q -m "experiment: strip instruction surfaces for unhobble baseline"
