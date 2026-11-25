#!/usr/bin/env bash
# Exit 0 clean, 1 failures, 2 environment (node missing).
set -uo pipefail

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)" || exit 2
node="$(command -v node)" || {
  echo "session-attended: node not found on PATH" >&2
  exit 2
}
scratch="$(mktemp -d)" || exit 2
trap 'rm -rf -- "${scratch:?}"' EXIT

fails=0
pass() { printf 'ok   %s\n' "$1"; }
bad() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  fails=$((fails + 1))
}

rows() {
  "$node" --input-type=module - "$here" "$scratch" <<'NODE'
import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const [here, scratch] = process.argv.slice(2);
const { default: cases } = await import(pathToFileURL(`${here}/session-attended.fixtures.mjs`).href);
const out = [];
cases.forEach((c, i) => {
  let dir = here;
  if ("data" in c) {
    dir = `${scratch}/${i}`;
    mkdirSync(dir);
    for (const f of ["session-attended.sh", "session-attended.mjs"]) copyFileSync(`${here}/${f}`, `${dir}/${f}`);
    if (c.data !== null) writeFileSync(`${dir}/session-attended.env`, c.data);
  }
  const pairs = Object.entries(c.env).map(([k, v]) => `${k}=${v}`);
  out.push(c.name, String(c.attended), dir, String(pairs.length), ...pairs);
});
process.stdout.write(out.map((f) => `${f}\0`).join(""));
NODE
}

records="$scratch/rows"
rows >"$records" || {
  echo "session-attended: could not load the fixture table" >&2
  exit 2
}

count=0
while IFS= read -r -d '' name && IFS= read -r -d '' want && IFS= read -r -d '' dir && IFS= read -r -d '' n; do
  pairs=()
  for ((i = 0; i < n; i++)); do
    IFS= read -r -d '' pair
    pairs+=("$pair")
  done
  count=$((count + 1))

  # shellcheck disable=SC2016  # the $1 belongs to the child shell
  err="$(env -i ${pairs[@]+"${pairs[@]}"} "$BASH" -c 'set -uo pipefail; source "$1"; hook::session_attended' _ "$dir/session-attended.sh" 2>&1 >/dev/null)"
  rc=$?
  case "$rc" in
  0) got=true ;;
  1) got=false ;;
  *) got="exit $rc" ;;
  esac
  if [[ "$got" == "$want" && -z "$err" ]]; then
    pass "bash: $name -> $want"
  else
    bad "bash: $name" "want $want silently, got $got, stderr: $err"
  fi

  out="$(env -i ${pairs[@]+"${pairs[@]}"} "$node" --input-type=module -e '
const { pathToFileURL } = await import("node:url");
const { sessionAttended } = await import(pathToFileURL(process.argv[1]).href);
process.stdout.write(String(sessionAttended(process.env)));
' "$dir/session-attended.mjs" 2>"$scratch/node.err")"
  err="$(<"$scratch/node.err")"
  if [[ "$out" == "$want" && -z "$err" ]]; then
    pass "node: $name -> $want"
  else
    bad "node: $name" "want $want silently, got '$out', stderr: $err"
  fi
done <"$records"
((count > 0)) || bad "fixture table" "no cases read"

# shellcheck disable=SC2016  # the script belongs to the child shell
leak="$(env -i "$BASH" -c '
set -euo pipefail
opts_before="$(set +o; shopt -p)"
vars_before="$(compgen -v)"
source "$1"
hook::session_attended || true
CLAUDE_CODE_SESSION_ATTENDED=1 hook::session_attended || true
vars_after="$(compgen -v)"
[[ "$(set +o; shopt -p)" == "$opts_before" ]] || echo "options changed"
comm -13 <(printf "%s\n" "$vars_before" | sort) <(printf "%s\n" "$vars_after" | sort) |
  grep -vx -e opts_before -e vars_before -e vars_after -e "SESSION_[A-Z_]*" || true
' _ "$here/session-attended.sh" 2>&1)"
if [[ -z "$leak" ]]; then
  pass "bash: the reader leaves caller options and variables alone"
else
  bad "bash: the reader leaves caller options and variables alone" "$leak"
fi

if ((fails)); then
  echo "$fails failure(s)"
  exit 1
fi
echo "all $count cases pass on both readers"
