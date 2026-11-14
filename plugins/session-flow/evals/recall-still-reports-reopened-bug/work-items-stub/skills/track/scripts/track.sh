#!/usr/bin/env bash
# Eval stand-in for /work-items:track over fixed items. search shows only each item's
# current state, as the real search does; an item's state history is printed only by
# `view <id> --history`, the one read that carries it on the real tracker.
set -euo pipefail

# State history per item, base64 so that only the --history read shows it.
history_57='eyJhdmFpbGFibGUiOnRydWUsImV2ZW50cyI6W3sic3RhdGUiOiJjbG9zZWQiLCJhdCI6IjIwMjYtMDktMDJUMTQ6MTA6MDBaIiwiYWN0b3IiOiJkZXYtYSJ9LHsic3RhdGUiOiJyZW9wZW5lZCIsImF0IjoiMjAyNi0wOS0xMFQwODo0NTowMFoiLCJhY3RvciI6InJlcG9ydGVyLWIifV0sInJlb3Blbl9jb3VudCI6MSwicmVhc29uIjpudWxsfQ=='
history_12='eyJhdmFpbGFibGUiOnRydWUsImV2ZW50cyI6W3sic3RhdGUiOiJjbG9zZWQiLCJhdCI6IjIwMjYtMDctMzBUMDk6MDA6MDBaIiwiYWN0b3IiOiJkZXYtYSJ9XSwicmVvcGVuX2NvdW50IjowLCJyZWFzb24iOm51bGx9'
history_61='eyJhdmFpbGFibGUiOnRydWUsImV2ZW50cyI6W10sInJlb3Blbl9jb3VudCI6MCwicmVhc29uIjpudWxsfQ=='

title_57='Login redirect loop after SSO sign-in'
title_12='Document the SSO login flow'
# The same symptom as #57, reported under another title.
title_61='Signed-in users keep getting redirected to /login after SSO'

usage() {
  echo "usage: track.sh search <query> | view <id> [--comments] [--history]" >&2
  exit 2
}

# matches <title> <query words...>: print yes when any query word is in the title, ignoring case.
matches() {
  local title word
  title="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  shift
  for word in "$@"; do
    word="$(printf '%s' "$word" | tr '[:upper:]' '[:lower:]')"
    if [[ -n "$word" && "$title" == *"$word"* ]]; then
      echo yes
      return
    fi
  done
  echo no
}

search() {
  local words=() open_rows="" closed_rows="" open_n=0 closed_n=0 hit_57 hit_12 hit_61
  read -r -a words <<<"$*"
  hit_57="$(matches "$title_57" "${words[@]}")"
  hit_12="$(matches "$title_12" "${words[@]}")"
  hit_61="$(matches "$title_61" "${words[@]}")"
  if [[ "$hit_61" == yes ]]; then
    open_n=$((open_n + 1))
    open_rows+="| $open_n | github:acme/web#61 $title_61 | Bug | area: auth | |"$'\n'
  fi
  if [[ "$hit_57" == yes ]]; then
    open_n=$((open_n + 1))
    open_rows+="| $open_n | github:acme/web#57 $title_57 | Bug | area: auth | |"$'\n'
  fi
  if [[ "$hit_12" == yes ]]; then
    closed_rows+="| 1 | github:acme/web#12 $title_12 | 2026-07-30 |"$'\n'
    closed_n=1
  fi
  printf '### Open Items (%s matches)\n\n| # | Item | Type | Labels | Assignee |\n|---|------|------|--------|----------|\n%s\n' "$open_n" "$open_rows"
  printf '### Closed Items (%s matches)\n\n| # | Item | Closed |\n|---|------|--------|\n%s' "$closed_n" "$closed_rows"
}

view() {
  local id="${1:-}" comments=0 history=0 number title state labels body encoded
  [[ -n "$id" ]] || usage
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --comments) comments=1 ;;
    --history) history=1 ;;
    *) usage ;;
    esac
    shift
  done
  case "$id" in
  github:acme/web#57 | 57 | '#57')
    number=57 title="$title_57" state=open labels='["area: auth"]' encoded="$history_57"
    body='After signing in with SSO the browser bounces between /login and /callback until it gives up.'
    ;;
  github:acme/web#12 | 12 | '#12')
    number=12 title="$title_12" state=closed labels='["docs"]' encoded="$history_12"
    body='Write up how SSO sign-in works.'
    ;;
  github:acme/web#61 | 61 | '#61')
    number=61 title="$title_61" state=open labels='["area: auth"]' encoded="$history_61"
    body='Since 2026-09-12, after I sign in through SSO the page sends me back to /login, then to /callback, over and over until the browser stops.'
    ;;
  *)
    echo "not found: $id" >&2
    exit 5
    ;;
  esac
  printf '```json\n{"id": "github:acme/web#%s", "title": "%s", "state": "%s", "url": "https://github.com/acme/web/issues/%s", "labels": %s, "body": "%s"' \
    "$number" "$title" "$state" "$number" "$labels" "$body"
  ((comments)) && printf ', "comments": []'
  ((history)) && printf ', "state_history": %s' "$(printf '%s' "$encoded" | base64 -d)"
  printf '}\n```\n'
}

verb="${1:-}"
[[ -n "$verb" ]] || usage
shift
case "$verb" in
search) search "$@" ;;
view) view "$@" ;;
*) usage ;;
esac
