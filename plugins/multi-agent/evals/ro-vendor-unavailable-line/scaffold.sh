#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/workspace.sh" repo
mkdir -p docs/conventions
cat >docs/conventions/multi-agent.yaml <<'EOF'
schema: 1
vendors:
  routing: true
  codex:
    in_use: true
  antigravity:
    in_use: false
EOF

stub_dir="$(git rev-parse --path-format=absolute --git-common-dir)/eval-external-agents/bin"
mkdir -p "$stub_dir"
cat >"$stub_dir/external-agents" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
prod="${2:-}"
if [[ "$cmd" == "models" && "$prod" == "codex" ]]; then
  cat <<'JSON'
{
  "schema": 1,
  "product": "codex",
  "status": "unavailable",
  "reason": "codex binary not found"
}
JSON
  exit 4
fi
echo "unexpected external-agents invocation: $*" >&2
exit 2
EOF
chmod +x "$stub_dir/external-agents"

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/vendor-boards.sh" all-read
