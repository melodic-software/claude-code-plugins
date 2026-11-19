# shellcheck shell=bash

browser_setup() {
  local prefix="$1" session_prefix="$2" tool
  shift 2
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "SKIP: $tool not installed"
      exit 0
    fi
  done

  if ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/$prefix.XXXXXX") || [[ ! -d "$tmp" ]]; then
    echo "FAIL: mktemp gave no scratch dir"
    exit 1
  fi
  BROWSER_TMP_PREFIX="$prefix"
  d="$tmp/run"
  mkdir -m 700 "$d" "$tmp/b"
  session="$session_prefix-$$"
  trap finish EXIT
}
pw() { (cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" "$@"); }
finish() {
  # shellcheck disable=SC2310  # cleanup on exit: a browser that is already gone is fine
  pw close >/dev/null 2>&1 || true
  bash "${bridge:?}/notes-bridge.sh" --dir "$d" stop >/dev/null 2>&1 || true
  case "$tmp" in
    */"$BROWSER_TMP_PREFIX".*) rm -rf -- "$tmp" ;;
    *) ;;
  esac
}

fails=0
ok() { echo "PASS: $1"; }
bad() {
  echo "FAIL: $1"
  fails=$((fails + 1))
}

browser_serve() {
  started=$(bash "${bridge:?}/notes-bridge.sh" --dir "$d" ensure-running --page explore-directions.html)
  port=$(printf '%s' "$started" | sed -n 's/.*"url": "http:\/\/127\.0\.0\.1:\([0-9]*\)\/".*/\1/p')
  [[ -n "$port" ]] || {
    echo "FAIL: ensure-running printed no url: $started"
    exit 1
  }
}

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
result() {
  python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if line.startswith("\""):
        print(json.loads(line))
        break
'
}
code() {
  local path
  path=$(native "$1")
  (cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" run-code --filename "$path" 2>&1) || true
}
check() {
  if python3 -c "import json, sys; r = json.loads(sys.argv[1]); $2" "$3"; then ok "$1"; else bad "$1: $3"; fi
}
