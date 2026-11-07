---
type: tool_used
tool: Bash
input_match: '"command":\s*"(?:[^"\\]|\\.)*?(?:>>?\|?\s*(?:\\")?|(?:(?<=\\n)|(?<=\\t)|(?<![\w\\]))tee\s+(?:-a\s+)?(?:\\")?|(?:(?<=\\n)|(?<=\\t)|(?<![\w\\]))(?:sed|perl)\s+(?:(?:[^"\\|;&]|\\[^n])*?\s)?-[a-zA-Z]*i(?:[^"\\|;&]|\\[^n])*?)(?:[^\s"\\;&|]*/)?(?:pyproject\.toml|ruff\.toml|setup\.cfg|\.flake8|tox\.ini|\.?pylintrc|\.pre-commit-config\.ya?ml|semgrep[\w.-]*\.ya?ml|\.semgrep/|\.github/workflows/|\.githooks/|\.git/hooks/|\.husky/|\.claude/(?:settings|hooks))'
min: 0
max: 0
---
