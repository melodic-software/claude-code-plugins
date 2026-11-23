#!/usr/bin/env bash
# test-scope: plugins/multi-agent/skills/route/scripts/delegate
# test-scope: plugins/multi-agent/scripts/resolve-roles.sh plugins/multi-agent/scripts/yaml-subset.awk
# test-scope: plugins/multi-agent/reference/defaults.yaml plugins/multi-agent/lib/config-root.sh
# test-scope: plugins/multi-agent/lib/resolve-convention-home.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

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
mkdir -p "$T/home" "$T/repo"
printf 'schema: 1\nvendors:\n  auto_delegation: %s\n' true >"$T/home/on.yaml"
printf 'schema: 1\nvendors:\n  auto_delegation: %s\n' false >"$T/home/off.yaml"
git -C "$T/repo" init -q
cp "$T/home/on.yaml" "$T/repo/on.yaml"

fails=0
check() {
  if [[ "$2" == "$3" ]]; then echo "PASS: $1"; else
    echo "FAIL: $1: expected '$2', got '$3'" >&2
    fails=1
  fi
}
run_as() {
  local f="$1"
  shift
  (cd "$T" && PATH="$T/bin:$PATH" "$HERE/delegate" --user-file "$f" "$@")
}
run() { run_as "$T/home/on.yaml" "$@"; }

out="$(printf 'draw a cat' | run codex 2>&1)"
check "codex runs with the fixed flags" "[run][codex][--use][task][--mode][write][--prompt-file]" "$(head -1 <<<"$out" | sed 's/\[[^]]*prompt\.md\]//')"
check "the prompt file holds stdin" "prompt=draw a cat" "$(sed -n 2p <<<"$out")"

out="$(printf 'x' | run antigravity --model gpt-5.5 --effort high 2>&1)"
check "model and effort pass through after the fixed flags" "[--model][gpt-5.5][--effort][high]" "$(head -1 <<<"$out" | sed 's/.*prompt\.md\]//')"

out="$(printf 'review this' | run codex --use investigate 2>&1)"
check "investigate runs read-only" "[run][codex][--use][investigate][--mode][read-only][--prompt-file]" "$(head -1 <<<"$out" | sed 's/\[[^]]*prompt\.md\]//')"
out="$(printf 'x' | run antigravity --use task --effort high 2>&1)"
check "an explicit --use task keeps write mode" "[run][antigravity][--use][task][--mode][write][--prompt-file][--effort][high]" "$(head -1 <<<"$out" | sed 's/\[[^]]*prompt\.md\]//')"

for bad in "--add-dir /" "--unsandboxed auto" "--resume" "--last" "--prompt-file /etc/hosts" "--mode read" "--mode write" "--use review" "--use" "--use investigate --use task"; do
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

printf 'x' | run_as "$T/home/off.yaml" codex >/dev/null 2>&1
check "refuses when the user layer has auto-delegation off" 2 "$?"
printf 'x' | run_as "$T/home/missing.yaml" codex >/dev/null 2>&1
check "refuses when the user layer file is missing" 2 "$?"
printf 'x' | run_as "$T/repo/on.yaml" codex >/dev/null 2>&1
check "refuses a user file inside a git work tree" 2 "$?"
out="$(printf 'x' | (cd "$T" && HOME="$T/home" PATH="$T/bin:$PATH" "$HERE/delegate" --user-file '~/on.yaml' codex) 2>&1)"
check "expands a leading ~/ in --user-file to HOME" "[run][codex][--use][task][--mode][write][--prompt-file]" "$(head -1 <<<"$out" | sed 's/\[[^]]*prompt\.md\]//')"
printf 'x' | (cd "$T" && PATH="$T/bin:$PATH" "$HERE/delegate" codex) >/dev/null 2>&1
check "refuses without --user-file" 2 "$?"

exit "$fails"
