#!/usr/bin/env bash
# Contract for scripts/plugin-validate-report.mjs. No claude binary required.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$ROOT/scripts/plugin-validate-report.mjs"
fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

run() {
  printf '%s' "$1" | node "$SUT"
}

out="$(run '{
  "success": false,
  "strict": true,
  "target": "/tmp/plug",
  "manifest": {
    "file": "/tmp/plug/.claude-plugin/plugin.json",
    "errors": [{"path": "name", "message": "Plugin name cannot contain spaces", "code": null}],
    "warnings": [],
    "notes": []
  },
  "contents": [
    {
      "file": "/tmp/plug/skills/demo/SKILL.md",
      "errors": [],
      "warnings": [{"path": "description", "message": "No description in frontmatter", "code": null}],
      "notes": []
    }
  ]
}')"
rc=$?
if [[ $rc -eq 0 ]] \
  && grep -q $'validate\ttarget\t/tmp/plug\tsuccess=false\tstrict=true' <<<"$out" \
  && grep -q $'manifest\t/tmp/plug/.claude-plugin/plugin.json\terrors\tname: Plugin name cannot contain spaces' <<<"$out" \
  && grep -q $'contents\t/tmp/plug/skills/demo/SKILL.md\twarnings\tdescription: No description in frontmatter' <<<"$out"; then
  pass "per-file errors and warnings render"
else
  fail "per-file render (rc=$rc): $out"
fi

out="$(run '{"success": true, "strict": false, "target": "/tmp/ok", "manifest": null, "contents": []}')"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'success=true' <<<"$out" && [[ $(wc -l <<<"$out") -eq 1 ]]; then
  pass "a clean report is one summary line"
else
  fail "clean report (rc=$rc): $out"
fi

# gatingHooks item shape and the "gating hook without .catch: tool.call"
# wording come from the plugin commands reference and the mods create page.
out="$(run '{
  "success": true,
  "strict": false,
  "target": "/tmp/mod",
  "manifest": null,
  "contents": [
    {
      "file": "/tmp/mod/hooks/index.ts",
      "errors": [],
      "warnings": [],
      "notes": [],
      "gatingHooks": [
        {"module": "./guard.tsx", "pattern": "tool.call", "hook": "tool.call", "hasCatch": false},
        {"module": "./caught.tsx", "pattern": "prompt.submit", "hook": "prompt.submit", "hasCatch": true}
      ]
    }
  ]
}')"
rc=$?
if [[ $rc -eq 0 ]] \
  && grep -q $'contents\t/tmp/mod/hooks/index.ts\twarnings\t./guard.tsx gating hook without .catch: tool.call' <<<"$out" \
  && ! grep -q 'caught' <<<"$out" \
  && [[ $(wc -l <<<"$out") -eq 2 ]]; then
  pass "a gating hook without .catch renders as a warning; one with .catch does not"
else
  fail "gatingHooks render (rc=$rc): $out"
fi

out="$(run 'not json' 2>/dev/null)"
rc=$?
if [[ $rc -eq 2 ]]; then
  pass "non-JSON exits 2"
else
  fail "non-JSON should exit 2 (rc=$rc)"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
