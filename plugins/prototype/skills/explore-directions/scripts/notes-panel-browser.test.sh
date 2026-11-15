#!/usr/bin/env bash
# Browser check of the notes host's Notes panel (notes-bridge/host.html) on the explore-directions
# eval fixture with the bundled switcher inlined, served by this plugin's notes-bridge copy and
# driven through playwright-cli. N hides and shows the panel with the focus on its button, then in
# the panel; a draft is saved, edited, deleted and sent, the editor giving the focus back to the
# control that opened it; the note's status moves from sent to delivered once a watcher takes it,
# and to handled with the reply once the session applies its ops; a note and a reply holding
# `<img src=x onerror=...>` show as text, create no element and run no handler.
# SKIPs without playwright-cli, python3 or curl.
# test-scope: plugins/prototype/notes-bridge/* plugins/prototype/skills/explore-directions/assets/variant-switcher.html
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
bridge=$(cd "$skill/../../notes-bridge" && pwd)
for tool in playwright-cli python3 curl; do # prereq-ok: test-only
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not installed"
    exit 0
  fi
done

if ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/ed-notes-panel.XXXXXX") || [[ ! -d "$tmp" ]]; then
  echo "FAIL: mktemp gave no scratch dir"
  exit 1
fi
d="$tmp/run"
mkdir -m 700 "$d" "$tmp/b"
session="edp-$$"
pw() { (cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" "$@"); } # prereq-ok: test-only
finish() {
  # shellcheck disable=SC2310  # cleanup on exit: a browser that is already gone is fine
  pw close >/dev/null 2>&1 || true
  bash "$bridge/notes-bridge.sh" --dir "$d" stop >/dev/null 2>&1 || true
  case "$tmp" in
    */ed-notes-panel.*) rm -rf -- "$tmp" ;;
    *) ;;
  esac
}
trap finish EXIT

fails=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }

marker='<!-- The bundled assets/variant-switcher.html is inlined whole here; elided from this fixture. -->'
while IFS= read -r line; do
  if [[ "$line" == "$marker" ]]; then cat "$skill/assets/variant-switcher.html"; else printf '%s\n' "$line"; fi
done <"$skill/evals/fixtures/shipments-mockup.html" >"$d/explore-directions.html"

started=$(bash "$bridge/notes-bridge.sh" --dir "$d" ensure-running --page explore-directions.html)
port=$(printf '%s' "$started" | sed -n 's/.*"url": "http:\/\/127\.0\.0\.1:\([0-9]*\)\/".*/\1/p')
[[ -n "$port" ]] || {
  echo "FAIL: ensure-running printed no url: $started"
  exit 1
}

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
# Run one page script (placeholders replaced from name=value pairs) and grade each line it returns.
run() { # script label [NAME=value ...]
  local src=$1 label=$2 out line path n=0
  shift 2
  python3 -c '
import sys
src, dst, *pairs = sys.argv[1:]
text = open(src, encoding="utf-8").read()
for pair in pairs:
    k, v = pair.split("=", 1)
    text = text.replace(f"__{k}__", v)
open(dst, "w", encoding="utf-8").write(text)
' "$src" "$tmp/$label.js" "PORT=$port" "$@"
  path=$(native "$tmp/$label.js")
  out=$(cd "$tmp" && TMPDIR="$tmp/b" playwright-cli -s="$session" run-code --filename "$path" 2>&1) || true # prereq-ok: test-only
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      PASS\ *) ok "$label: ${line#PASS }" ;;
      *) bad "$label: $line" ;;
    esac
  done < <(python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if line.startswith("\""):
        print(json.loads(line))
        break
' <<<"$out" | tr -d '\r' | grep -E '^(PASS|FAIL|ERROR) ')
  ((n > 0)) || bad "$label: no results ($(printf '%s' "$out" | head -c 400))"
}

pw open >/dev/null 2>&1
run "$here/notes-panel-browser-take.js" take

# A watcher takes the note, which stamps it delivered.
if WATCH_ID="edp-watch" timeout 30 bash "$bridge/watch.sh" "$d" >"$tmp/wake.json"; then
  ok "the watcher took the note"
else
  bad "the watcher exited without the note"
fi
run "$here/notes-panel-browser-wait.js" delivered "WANT=delivered to Claude" "REPLY=[]"

reply='<img src=y onerror="window.__xss=2">Moved it to the top.'
python3 -c 'import json, sys; json.dump({"replies": [{"seq": 1, "text": sys.argv[2]}]}, open(sys.argv[1], "w"))' "$d/ops.json" "$reply"
bash "$bridge/notes-bridge.sh" --dir "$d" apply --file "$d/ops.json" >/dev/null
run "$here/notes-panel-browser-wait.js" handled "WANT=handled" "REPLY=$(python3 -c 'import json, sys; print(json.dumps([sys.argv[1]]))' "$reply")"
run "$here/notes-panel-browser-refuse.js" refuse

if ((fails)); then
  echo "notes-panel-browser: $fails failed"
  exit 1
fi
echo "notes-panel-browser: all passed"
