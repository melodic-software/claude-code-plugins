#!/usr/bin/env bash
# Hygiene checks, then the browser suites, for the interview surface.
#   bash surface.test.sh
# Suites and files it grades: index.html, tests/ui_a.js, tests/ui_b.js, tests/ui_c.js, tests/ui_journey.js
# (the user journey, run against tests/fixtures/journey), schema.py, and the JSON
# Schemas schema/questions.schema.json, schema/responses.schema.json, schema/event.schema.json,
# schema/visual.schema.json and schema/ops.schema.json.
# The browser suites run only where playwright-cli resolves; elsewhere they print a SKIP with
# the number of checks not run, never a pass.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../../.." && pwd)
pass=0
fail=0
skip=0
ok() { echo "ok: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

cd "$here" || exit 1
files=()
for f in server.py round.py round.sh watch.sh index.html exporters.py schema.py schema/*.schema.json tests/*.js; do
  [[ -f "$f" ]] && files+=("$f")
done

# AC35: no file names a producing skill (<plugin>:<skill>), with plugin names read from plugins/.
names=""
for p in "$root"/plugins/*/; do
  p=${p%/}
  names="${names:+$names|}${p##*/}"
done
# One exemption: exporters.py's ARBITER_PLAN line writes the Brief contract's arbiter token
# (the Deferred questions tag in the interview skill's Brief template), which names the resolver
# of a deferred question, never a visual's producer.
hits=$(grep -nE "(^|[^a-z0-9-])($names):[a-z-]+" "${files[@]}" |
  grep -vE '^exporters\.py:[0-9]+:ARBITER_PLAN = "\*\*arbiter: /planning:plan\*\*"$')
if [[ -z "$hits" ]]; then ok "AC35: no skill token in ${#files[@]} files"; else bad "AC35: skill tokens: $hits"; fi

# AC34: no user name, home path, or port other than the documented default 0 (a free port).
hits=""
for u in "${USER:-}" "${USERNAME:-}" "$(whoami 2>/dev/null)"; do
  u=${u##*\\}
  [[ "${#u}" -ge 3 ]] || continue
  h=$(grep -niwF -- "$u" "${files[@]}")
  hits="$hits$h"
done
if [[ -z "$hits" ]]; then ok "AC34: no user name"; else bad "AC34: user name found: $hits"; fi
hits=$(grep -nE '/[U]sers/|[Cc]:[\\/]+[U]sers|/[h]ome/' "${files[@]}")
if [[ -z "$hits" ]]; then ok "AC34: no home path"; else bad "AC34: home path found: $hits"; fi
hits=$(grep -noE '(127\.0\.0\.1|localhost):[0-9]+|--port[ =][0-9]+|PORT=[0-9]+' "${files[@]}" |
  grep -vE '[:= ]0$')
if [[ -z "$hits" ]]; then ok "AC34: no port but 0"; else bad "AC34: hardcoded port: $hits"; fi

# index.html lint, when the repo's htmlhint is installed.
if [[ -x "$root/node_modules/.bin/htmlhint" ]]; then
  if out=$("$root/node_modules/.bin/htmlhint" index.html 2>&1); then ok "htmlhint index.html"; else bad "htmlhint: $out"; fi
else
  echo "SKIP: 1 check not run (htmlhint not installed)"
  skip=$((skip + 1))
fi

# Result lines from a playwright-cli run-code output file: one PASS/FAIL/ERROR per line.
results() {
  grep -m1 'PASS\|FAIL\|ERROR' "$1" | awk '{ gsub(/\\n/, "\n"); print }' |
    sed 's/^.*"PASS/PASS/; s/^.*"FAIL/FAIL/; s/^.*"ERROR/ERROR/; s/"$//' | grep -E '^(PASS|FAIL|ERROR) '
}

grade() { # suite output-file
  local n=0 line
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      PASS\ *) ok "$1: ${line#PASS }" ;;
      *) bad "$1: $line" ;;
    esac
  done < <(results "$2")
  [[ "$n" -gt 0 ]] || bad "$1: no results ($(head -c 400 "$2"))"
  echo "$1: $n checks"
}

if command -v playwright-cli >/dev/null 2>&1; then
  # No fixture write or trap before the scratch dir is proven to exist.
  if ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/iv-surface.XXXXXX") || [[ ! -d "$tmp" ]]; then
    echo "FAIL: mktemp gave no scratch dir"
    exit 1
  fi
  d="$tmp/d3"
  c="$tmp/c3"
  e="$tmp/e3"
  j="$tmp/journey"
  session="iv-$$"
  # playwright-cli writes its logs under the working directory, so it runs from the scratch dir.
  pw() { (cd "$tmp" && playwright-cli -s="$session" "$@"); }
  finish() {
    pw close >/dev/null 2>&1
    bash "$here/round.sh" --dir "$d" stop >/dev/null 2>&1
    bash "$here/round.sh" --dir "$c" stop >/dev/null 2>&1
    bash "$here/round.sh" --dir "$e" stop >/dev/null 2>&1
    bash "$here/round.sh" --dir "$j" stop >/dev/null 2>&1
    case "$tmp" in
      */iv-surface.*) rm -rf -- "$tmp" ;;
      *) ;;
    esac
  }
  trap finish EXIT
  mkdir -p "$d"
  cp tests/fixtures/questions.json tests/fixtures/responses.json "$d/"
  bash "$here/round.sh" --dir "$d" add-round --file tests/round-d3.json --round 4 >/dev/null
  bash "$here/round.sh" --dir "$d" ensure-running --port 0 >/dev/null
  port=$(sed -n 's/^PORT=//p' "$d/.interview-session.env" | tr -d '\r')
  for s in ui_a ui_b; do
    sed "s/__PORT__/$port/" "tests/$s.js" >"$tmp/$s.js"
  done
  script_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
  pw open >/dev/null 2>&1
  pw run-code --filename "$(script_path "$tmp/ui_a.js")" >"$tmp/ui_a.out" 2>&1
  bash "$here/round.sh" --dir "$d" revise N2 --rec "Yes. Changed by Claude after you started." --affects none --force >/dev/null
  pw run-code --filename "$(script_path "$tmp/ui_b.js")" >"$tmp/ui_b.out" 2>&1

  # ui_c runs against a third server seeded with settings in every layer: the repo file through
  # CLAUDE_PROJECT_DIR (inherited by the detached server), the user file, and the data dir's
  # settings.json. It runs in three phases; the shell writes as Claude between them.
  repo="$tmp/repo"
  mkdir -p "$c" "$repo/.claude"
  cp tests/fixtures/ui_c/questions.json tests/fixtures/ui_c/responses.json tests/fixtures/ui_c/settings.json "$c/"
  cp tests/fixtures/ui_c/repo-settings.json "$repo/.claude/interview-surface.json"
  # File visuals: vi's PNG is the 1x1 image vp carries inline, vs's SVG carries a text marker,
  # and vx names a file that is never written.
  mkdir -p "$c/images" "$c/diagrams"
  printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=' |
    base64 -d >"$c/images/flow.png"
  printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 40"><text x="10" y="25">filemark</text></svg>' \
    >"$c/diagrams/flow.svg"
  bash "$here/round.sh" --dir "$c" archive X1 --why "The old path left the plan" >/dev/null
  CLAUDE_PROJECT_DIR="$repo" bash "$here/round.sh" --dir "$c" ensure-running --port 0 --emoji-markers true \
    --user-settings tests/fixtures/ui_c/user-settings.json >/dev/null
  cport=$(sed -n 's/^PORT=//p' "$c/.interview-session.env" | tr -d '\r')
  for n in 1 2 3; do
    sed "s/__PORT__/$cport/; s/__PHASE__/$n/" tests/ui_c.js >"$tmp/ui_c$n.js"
  done
  pw run-code --filename "$(script_path "$tmp/ui_c1.js")" >"$tmp/ui_c1.out" 2>&1
  bash "$here/round.sh" --dir "$c" revise A2 --rec "Yes, batch two, changed by Claude." --affects none --force >/dev/null
  # Drops alternative (b), which stale P2's kept decision names: phase 2 checks no Reconfirm is offered.
  bash "$here/round.sh" --dir "$c" revise P2 --alt "a:No" --alt "c:Never" --force >/dev/null
  bash "$here/round.sh" --dir "$c" ensure-running --emoji-markers false >/dev/null
  pw run-code --filename "$(script_path "$tmp/ui_c2.js")" >"$tmp/ui_c2.out" 2>&1
  py=$(command -v python3 || command -v python)
  unhandled() { "$py" "$here/round.py" --dir "${1:-$c}" status | sed -n 's/^ *#\([0-9][0-9]*\) .*/\1/p' | tr '\n' ' '; }
  read -r -a seqs <<<"$(unhandled)"
  [[ "${#seqs[@]}" -gt 0 ]] && bash "$here/round.sh" --dir "$c" handle --seq "${seqs[@]}" >/dev/null
  # Phase 3 posts a fresh wrapup and watches the freeze lift inside its 10 s window, so the
  # handle must land while the page script runs: this background handler polls for the new
  # unhandled event and handles it (playwright-cli's own start-up, about 5 s on this host,
  # would otherwise eat the window).
  (
    for _ in $(seq 1 40); do
      read -r -a late <<<"$(unhandled)"
      if [[ "${#late[@]}" -gt 0 ]]; then "$py" "$here/round.py" --dir "$c" handle --seq "${late[@]}"; break; fi
      sleep 0.5
    done
  ) >/dev/null 2>&1 &
  handler=$!
  pw run-code --filename "$(script_path "$tmp/ui_c3.js")" >"$tmp/ui_c3.out" 2>&1
  wait "$handler" 2>/dev/null

  # ui_c phase 4 runs against a fourth server whose one event was delivered in 2020 and never
  # handled, with no watcher ever polling.
  mkdir -p "$e"
  cp tests/fixtures/ui_d/questions.json tests/fixtures/ui_d/responses.json "$e/"
  bash "$here/round.sh" --dir "$e" ensure-running --port 0 >/dev/null
  eport=$(sed -n 's/^PORT=//p' "$e/.interview-session.env" | tr -d '\r')
  sed "s/__PORT__/$eport/; s/__PHASE__/4/" tests/ui_c.js >"$tmp/ui_c4.js"
  pw run-code --filename "$(script_path "$tmp/ui_c4.js")" >"$tmp/ui_c4.out" 2>&1

  # The journey runs against a fifth server seeded with an empty interview. It walks the whole
  # flow on one page in seven phases; the shell writes as Claude between them.
  mkdir -p "$j/ops"
  cp tests/fixtures/journey/questions.json tests/fixtures/journey/responses.json "$j/"
  bash "$here/round.sh" --dir "$j" add-round --file tests/fixtures/journey/round1.json --round 1 >/dev/null
  bash "$here/round.sh" --dir "$j" ensure-running --port 0 >/dev/null
  jport=$(sed -n 's/^PORT=//p' "$j/.interview-session.env" | tr -d '\r')
  for n in 1 2 3 4 5 6 7; do
    sed "s/__PORT__/$jport/; s/__PHASE__/$n/" tests/ui_journey.js >"$tmp/uj$n.js"
  done
  jhandle() {
    local s
    read -r -a s <<<"$(unhandled "$j")"
    [[ "${#s[@]}" -eq 0 ]] || bash "$here/round.sh" --dir "$j" handle --seq "${s[@]}" >/dev/null
  }
  japply() { # name ops-json
    printf '%s' "$2" >"$j/ops/$1.json"
    bash "$here/round.sh" --dir "$j" apply --file "$j/ops/$1.json" >/dev/null || bad "journey: ops $1 refused"
  }
  jrun() { pw run-code --filename "$(script_path "$tmp/uj$1.js")" >"$tmp/uj$1.out" 2>&1; }
  jrun 1
  jhandle
  japply a '{"ops": [{"op": "reply", "id": "Q4", "text": "Slow means over five minutes per run."}]}'
  japply b '{"ops": [{"op": "wait", "id": "Q3", "waitsOn": "the retry benchmark", "by": "claude"},
    {"op": "wait", "id": "Q5", "waitsOn": "whether the version must be pinned", "by": "user"},
    {"op": "set-status", "text": "Researching the retry benchmark for Q3"}]}'
  jrun 2
  # Phase 2 leaves its Answer anyway on Q3, then a note: the note gets the Notes reply.
  read -r -a js <<<"$(unhandled "$j")"
  note=${js[${#js[@]} - 1]}
  [[ "${#js[@]}" -lt 2 ]] || bash "$here/round.sh" --dir "$j" handle --seq "${js[@]:0:${#js[@]}-1}" >/dev/null
  japply c '{"ops": [{"op": "activity", "text": "Added a retry note to Q1", "ids": ["Q1"]},
    {"op": "wait", "id": "Q3", "clear": true}, {"op": "set-status", "clear": true},
    {"op": "reply", "id": "Q3", "text": "The benchmark settles it: three retries."}]}'
  bash "$here/round.sh" --dir "$j" add-round --file tests/fixtures/journey/round2.json --round 2 >/dev/null
  japply d '{"ops": [{"op": "note-reply", "seq": '"$note"', "text": "Yes, on track."}]}'
  jrun 3
  jhandle
  japply e '{"ops": [{"op": "confirm-commitments", "id": "Q2", "reason": "Confirmed in the terminal"},
    {"op": "record-terminal", "id": "Q4", "decision": "accept"},
    {"op": "confirm-commitments", "id": "Q4", "reason": "Said yes in the terminal"},
    {"op": "restate", "sections": {"goal": "Ship green builds to staging on their own.",
      "constraints": "Builds stop at ten minutes.", "planningOwned": "How the cache key is built."}}]}'
  jrun 4
  jhandle
  bash "$here/round.sh" --dir "$j" revise Q7 --rec "Yes, from the merged pull requests and their linked issues." --affects none --force >/dev/null
  japply f '{"ops": [{"op": "restate", "sections": {"goal": "Ship green builds to staging, with the linked issues in the release notes.",
    "constraints": "Builds stop at ten minutes."}}]}'
  jrun 5
  jhandle
  japply g '{"ops": [{"op": "wait", "id": "Q5", "clear": true},
    {"op": "record-terminal", "id": "Q5", "decision": "own", "text": "Pin it to the lock file."},
    {"op": "record-terminal", "id": "Q7", "decision": "accept"},
    {"op": "wait", "id": "Q3", "waitsOn": "a second benchmark", "by": "claude"},
    {"op": "group", "id": "g3", "title": "Release", "dependsOn": ["g2"]}]}'
  jrun 6
  japply h '{"ops": [{"op": "wait", "id": "Q3", "clear": true}]}'
  jrun 7
  grade ui_a "$tmp/ui_a.out"
  grade ui_b "$tmp/ui_b.out"
  for n in 1 2 3 4; do grade "ui_c.$n" "$tmp/ui_c$n.out"; done
  for n in 1 2 3 4 5 6 7; do grade "ui_journey.$n" "$tmp/uj$n.out"; done
else
  echo "SKIP: 240 browser checks not run, 86 of them the journey (playwright-cli not found)" # silent-skip-ok: browser checks need a local playwright-cli # discriminating-skip-ok: the API, watcher and hygiene checks above still grade this suite
  skip=$((skip + 240))
fi

echo "PASS=$pass FAIL=$fail SKIP=$skip"
[[ "$fail" -eq 0 ]]
