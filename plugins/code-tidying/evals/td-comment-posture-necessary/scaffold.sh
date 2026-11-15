#!/usr/bin/env bash
set -euo pipefail

posture="${1:-}"
git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p scripts tests
cat >CLAUDE.md <<'EOF'
# status-tools

Shell tooling that checks a service status endpoint.

## Tests

Run `bash tests/fetch-status.test.sh` after any change under `scripts/`. It must print `PASS`.
EOF
cat >scripts/fetch-status.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

fetch_status() {
  local base_url="$1"
  curl --silent --max-time 5 "$base_url/status"
}

fetch_status "${1:?usage: fetch-status.sh BASE_URL}"
EOF
cat >tests/fetch-status.test.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
curl() { printf '%s\n' "$*"; }
export -f curl
out="$(bash scripts/fetch-status.sh https://example.invalid)"
[[ "$out" == "--silent --max-time 5 https://example.invalid/status" ]] || { echo "FAIL: curl arguments changed: $out"; exit 1; }
echo PASS
EOF
git add CLAUDE.md scripts/fetch-status.sh tests/fetch-status.test.sh
if [[ -n "$posture" ]]; then
  mkdir -p docs/conventions
  printf 'comment_posture: %s\n' "$posture" >docs/conventions/code-tidying.yaml
  git add docs/conventions/code-tidying.yaml
fi
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add status tooling" -m "Uses a 5 second timeout to stay under the load balancer's 6 second idle cutoff."
git checkout -q -b feature/status-tooling
