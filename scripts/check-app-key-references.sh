#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

pattern='automation_lanes_app_private_key|app-private-key|automation_lanes_app_client_id'
dirs=()
for dir in .github/workflows .github/actions; do
  [[ -d "$dir" ]] && dirs+=("$dir")
done
if [[ "${#dirs[@]}" -eq 0 ]]; then
  printf 'check-app-key-references: neither .github/workflows nor .github/actions exists\n' >&2
  exit 2
fi

rc=0
hits=$(grep -rnIiE -- "$pattern" "${dirs[@]}") || rc=$?
if [[ "$rc" -gt 1 ]]; then
  printf 'check-app-key-references: grep failed (exit %s)\n' "$rc" >&2
  exit 2
fi
if [[ -n "$hits" ]]; then
  while IFS= read -r hit; do
    rest=${hit#*:}
    printf '%s:%s: references the lanes App key or client id\n' "${hit%%:*}" "${rest%%:*}" >&2
  done <<<"$hits"
  exit 1
fi
printf 'check-app-key-references: no workflow or action references the lanes App key or client id\n'
