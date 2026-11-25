#!/usr/bin/env bash
# test-scope: plugins/session-flow/hooks/hooks.json

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "${TMP:?}"' EXIT
JQ="$(command -v jq)" || {
  echo "observer-catchup: jq not found on PATH" >&2
  exit 2
}
mkdir "$TMP/bin"
printf '#!/usr/bin/env bash\n: >"%s/mark"\nexec "%s" "$@"\n' "$TMP" "$JQ" >"$TMP/bin/jq"
chmod +x "$TMP/bin/jq"

pass=0 fail=0
gate_passes() {
  rm -f -- "$TMP/mark"
  env -i PATH="$TMP/bin:$PATH" HOME="$TMP" CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED=true "$@" \
    bash "$HOOK_DIR/observer-catchup.sh" <<<'{"source":"compact"}' >/dev/null 2>&1
  [[ -e $TMP/mark ]]
}

UNSET='<unset>'
changed=()
for att in "$UNSET" 0 1 true; do
  for ep in "$UNSET" cli sdk-cli claude-desktop; do
    envs=()
    [[ $att == "$UNSET" ]] || envs+=("CLAUDE_CODE_SESSION_ATTENDED=$att")
    [[ $ep == "$UNSET" ]] || envs+=("CLAUDE_CODE_ENTRYPOINT=$ep")
    old=no new=no got=no
    [[ $ep == cli ]] && old=yes
    [[ $att == 1 && $ep != sdk-cli ]] && new=yes
    gate_passes ${envs[@]+"${envs[@]}"} && got=yes
    cell="ATTENDED=$att ENTRYPOINT=$ep"
    if [[ $got == "$new" ]]; then
      pass=$((pass + 1))
      echo "ok   $cell arms=$got"
    else
      fail=$((fail + 1))
      echo "FAIL $cell: want arms=$new, got $got"
    fi
    [[ $old == "$new" ]] || changed+=("$cell: $old -> $new")
  done
done

printf 'changed from the old rule: %s\n' "${changed[@]}"
echo "observer-catchup: $pass passed, $fail failed"
((fail == 0))
