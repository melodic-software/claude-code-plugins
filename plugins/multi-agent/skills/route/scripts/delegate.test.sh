#!/usr/bin/env bash
# test-scope: plugins/multi-agent/skills/route/scripts/delegate
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat >"$T/bin/external-agents" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do printf '[%s]' "$a"; done
printf '\n'
while [[ $# -gt 0 ]]; do
  [[ "$1" == --prompt-file ]] && printf 'prompt=%s\n' "$(cat "$2")"
  shift
done
EOF
chmod +x "$T/bin/external-agents"

fails=0
check() {
  if [[ "$2" == "$3" ]]; then echo "PASS: $1"; else
    echo "FAIL: $1: expected '$2', got '$3'" >&2
    fails=1
  fi
}
run() { PATH="$T/bin:$PATH" "$HERE/delegate" "$@"; }

out="$(printf 'draw a cat' | run codex 2>&1)"
check "codex runs with the fixed flags" "[run][codex][--use][task][--mode][write][--prompt-file]" "$(head -1 <<<"$out" | sed 's/\[[^]]*prompt\.md\]//')"
check "the prompt file holds stdin" "prompt=draw a cat" "$(sed -n 2p <<<"$out")"

out="$(printf 'x' | run antigravity --model gpt-5.5 --effort high 2>&1)"
check "model and effort pass through after the fixed flags" "[--model][gpt-5.5][--effort][high]" "$(head -1 <<<"$out" | sed 's/.*prompt\.md\]//')"

for bad in "--add-dir /" "--unsandboxed auto" "--resume" "--last" "--prompt-file /etc/hosts" "--mode read"; do
  # shellcheck disable=SC2086
  printf 'x' | run codex $bad >/dev/null 2>&1
  check "rejects $bad" 2 "$?"
done
printf 'x' | run claude >/dev/null 2>&1
check "rejects an unknown product" 2 "$?"
printf 'x' | run codex --model 'a b' >/dev/null 2>&1
check "rejects a model id with a space" 2 "$?"
run codex </dev/null >/dev/null 2>&1
check "rejects an empty prompt" 2 "$?"

exit "$fails"
