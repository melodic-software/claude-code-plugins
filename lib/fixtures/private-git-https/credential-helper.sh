#!/bin/sh
protocol=""
host=""
path=""
while IFS='=' read -r key value; do
  [ -n "$key" ] || break
  case $key in
    protocol) protocol=$value ;;
    host) host=$value ;;
    path) path=/$value ;;
    *) ;;
  esac
done
printf '%s %s://%s%s\n' "$1" "$protocol" "$host" "$path" >>"$CRED_LOG"
[ -z "${CRED_HANG:-}" ] || sleep 30
[ "$1" != get ] || printf 'username=reader\npassword=fixture-token\n'
