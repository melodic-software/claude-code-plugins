#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-label-sender.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}

mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
*"/pulls/"*) printf '%s\n' "$STUB_DRAFT" ;;
*"/events"*) printf '%s\n' "$STUB_EVENTS" | jq -c '.[]' ;;
*) exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
printf '{"version":1,"actors":[{"id":11,"login":"person","kind":"human"},{"id":22,"login":"bot[bot]","kind":"bot"}]}\n' >"$TMP/list.json"

LABELED='[{"event":"labeled","label":{"name":"eval: run"},"actor":{"id":11},"created_at":"2026-11-19T10:00:00Z"}]'

case_() {
  local label=$1 want=$2 rc=0 out
  shift 2
  out=$(env -i PATH="$TMP/bin:$PATH" GITHUB_REPOSITORY=o/r LIST="$TMP/list.json" \
    PROCEED=true REASON=ok PR_NUMBER=7 ACTOR_ID=11 RUN_CREATED_AT=2026-11-19T10:00:20Z \
    RUN_PATH=.github/workflows/pr-run-plugin-evals-label.yml STUB_DRAFT=false STUB_EVENTS="$LABELED" \
    "$@" bash "$CHECK" 2>&1) || rc=$?
  if [[ $rc == "$want" ]]; then ok "$label"; else not_ok "$label: expected rc $want, got $rc: $out"; fi
}

case_ 'a listed human labeled eval: run just before the recorder run: passes' 0
case_ 'an untrusted trigger verdict: fails' 1 PROCEED=false
case_ 'a run started by another workflow: fails' 1 RUN_PATH=.github/workflows/other.yml
case_ 'no pull request number: fails' 1 PR_NUMBER=
case_ 'a listed bot that labeled eval: run: fails' 1 ACTOR_ID=22 \
  STUB_EVENTS='[{"event":"labeled","label":{"name":"eval: run"},"actor":{"id":22},"created_at":"2026-11-19T10:00:00Z"}]'
case_ 'an unlisted actor that labeled eval: run: fails' 1 ACTOR_ID=33 \
  STUB_EVENTS='[{"event":"labeled","label":{"name":"eval: run"},"actor":{"id":33},"created_at":"2026-11-19T10:00:00Z"}]'
case_ 'a draft pull request: fails' 1 STUB_DRAFT=true
case_ 'an unreadable pull request: fails' 1 STUB_DRAFT=
case_ 'another label started the run: fails' 1 \
  STUB_EVENTS='[{"event":"labeled","label":{"name":"other"},"actor":{"id":11},"created_at":"2026-11-19T10:00:00Z"}]'
case_ 'the eval label came from someone else: fails' 1 \
  STUB_EVENTS='[{"event":"labeled","label":{"name":"eval: run"},"actor":{"id":44},"created_at":"2026-11-19T10:00:00Z"}]'
case_ 'the eval label is older than ten minutes before the run: fails' 1 RUN_CREATED_AT=2026-11-19T10:10:01Z
case_ 'the eval label is after the run was created: fails' 1 RUN_CREATED_AT=2026-11-19T09:59:59Z

exit "$FAILED"
