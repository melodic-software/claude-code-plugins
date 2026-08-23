#!/usr/bin/env bash
# Drift check: the citation fields the auditor produces and the audit skill
# consumes must also appear on the emitted work-item body schema. The
# emit-schema gap was exactly this drop — produce and consume required a
# retrieval channel plus a byte count or line number; config.md's body
# sections did not.
#
# Asserts the load-bearing phrases in all three files after normalization
# (backticks/emphasis stripped, whitespace flattened). A wording change on
# one surface fails this lane until the other two move with it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDITOR="$SCRIPT_DIR/../agents/auditor.md"
SKILL="$SCRIPT_DIR/../skills/audit/SKILL.md"
CONFIG="$SCRIPT_DIR/../reference/config.md"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

norm() {
  tr -d '`*' <"$1" | tr '\n' ' ' | tr -s ' '
}

for f in "$AUDITOR" "$SKILL" "$CONFIG"; do
  if [[ ! -r "$f" ]]; then
    echo "FAIL: required file missing or unreadable: $f" >&2
    exit 1
  fi
done

AUDITOR_N=$(norm "$AUDITOR")
SKILL_N=$(norm "$SKILL")
CONFIG_N=$(norm "$CONFIG")

# all_three <label> <fixed-phrase>
all_three() {
  local label="$1" phrase="$2" where=""
  [[ "$AUDITOR_N" == *"$phrase"* ]] || where="auditor.md"
  [[ "$SKILL_N" == *"$phrase"* ]] || where="${where:+$where and }audit/SKILL.md"
  [[ "$CONFIG_N" == *"$phrase"* ]] || where="${where:+$where and }reference/config.md"
  if [[ -z "$where" ]]; then
    ok "$label"
  else
    fail "$label: phrase not found in $where: '$phrase'"
  fi
}

all_three "retrieval channel" "retrieval channel"
# auditor.md says "the fetched byte count or the line number"; the skill and
# emit schema say "byte count or line number". Both halves must appear.
all_three "byte count" "byte count"
all_three "line number" "line number"
all_three "unverified on a missing field" "unverified"

# The emit schema is the surface that dropped the channel. Pin the body
# paragraph itself, not just a mention somewhere in config.md.
CONFIG_BODY=$(printf '%s' "$CONFIG_N" | sed -n 's/.*Body sections: \(.*\) Claim protocol.*/\1/p')
if [[ -z "$CONFIG_BODY" ]]; then
  fail "config.md body-sections paragraph not found"
else
  ok "config.md body-sections paragraph present"
fi

body_has() {
  local label="$1" phrase="$2"
  if [[ "$CONFIG_BODY" == *"$phrase"* ]]; then
    ok "emit body $label"
  else
    fail "emit body $label: phrase not in Body sections paragraph: '$phrase'"
  fi
}

body_has "URL" "URL"
body_has "fetch date" "fetch date"
body_has "retrieval channel" "retrieval channel"
body_has "byte-or-line locator" "byte count or line number"
body_has "rung-1 curl" "rung-1 curl"
body_has "rung-2 WebFetch" "rung-2 WebFetch"
body_has "omitted field emitted unverified" "emitted as unverified"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
