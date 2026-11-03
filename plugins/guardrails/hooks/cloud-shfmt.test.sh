#!/usr/bin/env bash
# Tests for cloud-shfmt.sh, the cloud SessionStart step that installs the pinned
# shfmt: it acts only in a cloud session, installs only a download whose hash
# matches, records why it could not, and always exits 0.
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"
SUT="$HOOK_DIR/cloud-shfmt.sh"
PASS=0 FAIL=0
ok() {
  PASS=$((PASS + 1))
  echo "ok: $*"
}
bad() {
  FAIL=$((FAIL + 1))
  echo "FAIL: $*" >&2
}
T=$(mktemp -d)
trap 'rm -rf "${T:?}"' EXIT

# A PATH with the tools the step uses but no shfmt, and a curl stub that writes
# the bytes in $FAKE_BODY, or fails with $FAKE_RC.
BIN="$T/bin"
mkdir -p "$BIN"
for t in bash mktemp rm sha256sum install mkdir uname env cat; do
  ln -s "$(type -P "$t")" "$BIN/$t"
done
cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
[[ -n "${FAKE_RC:-}" ]] && exit "$FAKE_RC"
while (($#)); do [[ "$1" == -o ]] && out=$2; shift; done
printf '%s' "${FAKE_BODY:-}" >"$out"
EOF
chmod +x "$BIN/curl"
NOTE_REL=.local/state/claude-guardrails/shfmt-install-failed

run_step() { # <home> [env...]: run the step as SessionStart does; sets RC
  local home=$1
  shift
  env -i PATH="$BIN" HOME="$home" "$@" "$BIN/bash" "$SUT" >/dev/null 2>&1
  RC=$?
}

# Not a cloud session: nothing is written, exit 0.
H="$T/local"
mkdir -p "$H"
run_step "$H" FAKE_BODY=x
if ((RC == 0)) && [[ ! -e "$H/.local" ]]; then ok "a local session is left alone"; else bad "local session: rc=$RC, $(ls -A "$H")"; fi

# Cloud session, download fails: exit 0, no binary, the reason recorded.
H="$T/cloud-fail"
mkdir -p "$H"
run_step "$H" CLAUDE_CODE_REMOTE=true FAKE_RC=6
if ((RC == 0)) && [[ ! -e "$H/.local/bin/shfmt" ]] && grep -q 'download failed: curl exit 6' "$H/$NOTE_REL" 2>/dev/null; then
  ok "a failed download exits 0 and records why"
else
  bad "failed download: rc=$RC, note [$(cat "$H/$NOTE_REL" 2>/dev/null)]"
fi

# Cloud session, a download whose hash is not the pin's: nothing installed.
H="$T/cloud-mismatch"
mkdir -p "$H"
run_step "$H" CLAUDE_CODE_REMOTE=true FAKE_BODY='not shfmt'
if ((RC == 0)) && [[ ! -e "$H/.local/bin/shfmt" ]] && grep -q 'checksum mismatch' "$H/$NOTE_REL" 2>/dev/null; then
  ok "a download with the wrong hash is not installed"
else
  bad "hash mismatch: rc=$RC, note [$(cat "$H/$NOTE_REL" 2>/dev/null)]"
fi

# The install itself, with a hash computed here for the stub's bytes.
H="$T/cloud-ok"
mkdir -p "$H"
body='#!/bin/sh
echo stub'
sha=$(printf '%s' "$body" | sha256sum)
sha=${sha%% *}
# shellcheck disable=SC2016  # the child shell expands these
if out=$(env -i PATH="$BIN" HOME="$H" FAKE_BODY="$body" "$BIN/bash" -c 'source "$1"; cloud_shfmt::install https://x/y "$2" "$HOME/.local/bin/shfmt"' -- "$SUT" "$sha") &&
  [[ -x "$H/.local/bin/shfmt" && "$("$H/.local/bin/shfmt")" == stub ]]; then
  ok "a download with the matching hash is installed executable"
else
  bad "matching hash: [$out]"
fi

# shfmt already in ~/.local/bin: no download, and a stale note goes.
mkdir -p "$H/.local/state/claude-guardrails"
echo stale >"$H/$NOTE_REL"
run_step "$H" CLAUDE_CODE_REMOTE=true FAKE_RC=6
if ((RC == 0)) && [[ ! -e "$H/$NOTE_REL" ]]; then ok "an installed shfmt clears a stale note"; else bad "installed shfmt: rc=$RC, note still there"; fi

# The pin agrees with the repository's other shfmt pins.
pin=$(sed -n 's/^CLOUD_SHFMT_PIN="\(.*\)"$/\1/p' "$SUT")
sha=$(sed -n 's/^CLOUD_SHFMT_SHA="\(.*\)"$/\1/p' "$SUT")
boot="$REPO_ROOT/.claude/cloud-bootstrap.sh"
if [[ -f "$boot" ]]; then
  if grep -q "^shfmt_pin=\"$pin\"" "$boot" && grep -q "^shfmt_sha=\"$sha\"" "$boot"; then
    ok "the pin and hash match .claude/cloud-bootstrap.sh"
  else
    bad "the pin $pin / $sha differs from .claude/cloud-bootstrap.sh"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
((FAIL == 0))
