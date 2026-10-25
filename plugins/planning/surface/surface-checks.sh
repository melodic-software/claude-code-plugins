#!/usr/bin/env bash
# Hygiene checks, then the browser groups, for the interview surface. The suites run it:
#   bash surface-checks.sh                 the hygiene checks and the main part (surface.test.sh)
#   bash surface-checks.sh --part <part>   one part's browser groups (surface-<part>.test.sh)
#   bash surface-checks.sh --part all      the hygiene checks and every browser group
# Each browser group runs against its own server, so the parts are independent and the test
# planner can give each suite its own leg.
# Files it grades: index.html, tests/ui_a.js, tests/ui_b.js, tests/ui_c.js, tests/ui_e.js, tests/ui_journey.js, tests/ui_live.js,
# tests/ui_page.js
# (the user journey, run against tests/fixtures/journey), schema.py, and the JSON
# Schemas schema/questions.schema.json, schema/responses.schema.json, schema/event.schema.json,
# schema/visual.schema.json and schema/ops.schema.json.
# The browser groups run only where playwright-cli resolves; elsewhere they print a SKIP with
# the number of checks not run, never a pass.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../../.." && pwd)
pass=0
fail=0
skip=0
ok() { echo "ok: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

# The browser groups of each part, and each group's check count for the SKIP line.
declare -A PARTS=([main]="ab e live page" [ui-c]="c" [journey]="journey")
declare -A CHECKS=([ab]=97 [c]=186 [e]=20 [journey]=235 [live]=18 [page]=83)
part=main
case "$#:${1:-}" in
  0:) ;;
  2:--part) part=$2 ;;
  *)
    echo "usage: surface-checks.sh [--part ${!PARTS[*]} all]" >&2
    exit 2
    ;;
esac
if [[ "$part" == all ]]; then
  groups=""
  for p in "${!PARTS[@]}"; do groups+=" ${PARTS[$p]}"; done
elif [[ -n "${PARTS[$part]+x}" ]]; then
  groups=${PARTS[$part]}
else
  echo "surface-checks.sh: no part '$part'; the parts are ${!PARTS[*]} and all" >&2
  exit 2
fi

cd "$here" || exit 1
if [[ "$part" == main || "$part" == all ]]; then
  files=()
  for f in server.py round.py round.sh watch.sh wake.sh index.html exporters.py schema.py schema/*.schema.json tests/*.js; do
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
  # of a deferred question, never a visual's producer. A CSS declaration after `{` or `;`
  # (`{animation:pulse ...}`) is a property, not a token.
  hits=$(grep -nE "(^|[^a-z0-9{;-])($names):[a-z-]+" "${files[@]}" |
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

if command -v playwright-cli >/dev/null 2>&1; then # prereq-ok: test-only, run by the surface-*.test.sh suites
  # No fixture write or trap before the scratch dir is proven to exist.
  if ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/iv-surface.XXXXXX") || [[ ! -d "$tmp" ]]; then
    echo "FAIL: mktemp gave no scratch dir"
    exit 1
  fi
  d="$tmp/d3"
  c="$tmp/c3"
  e="$tmp/e3"
  j="$tmp/journey"
  g="$tmp/g3"
  session="iv-$$"
  # playwright-cli writes its logs under the working directory, so it runs from the scratch dir.
  pw() { (cd "$tmp" && playwright-cli -s="$session" "$@"); } # prereq-ok: test-only, run by the surface-*.test.sh suites
  finish() {
    pw close >/dev/null 2>&1
    bash "$here/round.sh" --dir "$d" stop >/dev/null 2>&1
    bash "$here/round.sh" --dir "$c" stop >/dev/null 2>&1
    bash "$here/round.sh" --dir "$e" stop >/dev/null 2>&1
    bash "$here/round.sh" --dir "$j" stop >/dev/null 2>&1
    bash "$here/round.sh" --dir "$g" stop >/dev/null 2>&1
    [[ -z "${pg:-}" ]] || bash "$here/round.sh" --dir "$pg" stop >/dev/null 2>&1
    case "$tmp" in
      */iv-surface.*) rm -rf -- "$tmp" ;;
      *) ;;
    esac
  }
  trap finish EXIT
  script_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
  py=$(command -v python3 || command -v python)
  unhandled() { "$py" "$here/round.py" --dir "${1:-$c}" status | sed -n 's/^ *#\([0-9][0-9]*\) .*/\1/p' | tr '\n' ' '; }
  pw open >/dev/null 2>&1

  group_ab() {
    mkdir -p "$d"
    cp tests/fixtures/questions.json tests/fixtures/responses.json "$d/"
    bash "$here/round.sh" --dir "$d" add-round --file tests/round-d3.json --round 4 >/dev/null
    bash "$here/round.sh" --dir "$d" ensure-running --port 0 >/dev/null
    port=$(sed -n 's/^PORT=//p' "$d/.interview-session.env" | tr -d '\r')
    for s in ui_a ui_b; do
      sed "s/__PORT__/$port/" "tests/$s.js" >"$tmp/$s.js"
    done
    pw run-code --filename "$(script_path "$tmp/ui_a.js")" >"$tmp/ui_a.out" 2>&1
    bash "$here/round.sh" --dir "$d" revise N2 --rec "Yes. Changed by Claude after you started." --affects none --keep-alternatives --force >/dev/null
    pw run-code --filename "$(script_path "$tmp/ui_b.js")" >"$tmp/ui_b.out" 2>&1
    grade ui_a "$tmp/ui_a.out"
    grade ui_b "$tmp/ui_b.out"
  }

  group_c() {
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
    bash "$here/round.sh" --dir "$c" archive D0 --why "The old path left the plan" >/dev/null
    CLAUDE_PROJECT_DIR="$repo" bash "$here/round.sh" --dir "$c" ensure-running --port 0 --emoji-markers true \
      --user-settings tests/fixtures/ui_c/user-settings.json >/dev/null
    cport=$(sed -n 's/^PORT=//p' "$c/.interview-session.env" | tr -d '\r')
    for n in 1 2 3; do
      sed "s/__PORT__/$cport/; s/__PHASE__/$n/" tests/ui_c.js >"$tmp/ui_c$n.js"
    done
    pw run-code --filename "$(script_path "$tmp/ui_c1.js")" >"$tmp/ui_c1.out" 2>&1
    bash "$here/round.sh" --dir "$c" revise A2 --rec "Yes, batch two, changed by Claude." --affects none --keep-alternatives --force >/dev/null
    # Drops alternative (b), which stale P2's kept decision names: phase 2 checks no Reconfirm is offered.
    bash "$here/round.sh" --dir "$c" revise Q1 --commit "Uses a private cache" --commit "Runs on every commit" --force >/dev/null
    bash "$here/round.sh" --dir "$c" revise P2 --alt "a:No" --alt "c:Never" --force >/dev/null
    # A recommendation change on P1 marks its decided dependent P2 upstream changed: phase 2 reads the banner.
    bash "$here/round.sh" --dir "$c" revise P1 --rec "Yes, the upstream step, revised." --affects none --keep-alternatives --force >/dev/null
    # Claude declares Q3 as being revised: phase 2 reads the mark on its rail card and detail pane.
    printf '%s' '{"ops": [{"op": "revising-by-claude", "ids": ["Q3"], "why": "auditing the cache choice"}]}' >"$tmp/revising.json"
    bash "$here/round.sh" --dir "$c" apply --file "$tmp/revising.json" >/dev/null 2>&1
    bash "$here/round.sh" --dir "$c" ensure-running --emoji-markers false >/dev/null
    pw run-code --filename "$(script_path "$tmp/ui_c2.js")" >"$tmp/ui_c2.out" 2>&1
    read -r -a seqs <<<"$(unhandled)"
    [[ "${#seqs[@]}" -gt 0 ]] && bash "$here/round.sh" --dir "$c" handle --seq "${seqs[@]}" >/dev/null
    # Phase 3 posts a fresh wrapup and watches the freeze lift inside its 10 s window, so the
    # handle must land while the page script runs: this background handler polls for the new
    # unhandled event and handles it (playwright-cli's own start-up, about 5 s on this host,
    # would otherwise eat the window). It holds the handle 2 s so the page's check at 600 ms
    # still sees the freeze: a poll that lands at once would lift it before the check.
    (
      for _ in $(seq 1 40); do
        read -r -a late <<<"$(unhandled)"
        if [[ "${#late[@]}" -gt 0 ]]; then
          sleep 2
          "$py" "$here/round.py" --dir "$c" handle --seq "${late[@]}"
          break
        fi
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
    # Phase 5, same server: an interview round 3, then a newer design round 1, for the header's
    # derived round across two stages.
    for r in interview-3:3 design-1:1; do
      bash "$here/round.sh" --dir "$e" add-round --file "tests/fixtures/ui_d/round-${r%:*}.json" --round "${r#*:}" >/dev/null ||
        bad "ui_c.5: add-round ${r%:*} refused"
    done
    sed "s/__PORT__/$eport/; s/__PHASE__/5/" tests/ui_c.js >"$tmp/ui_c5.js"
    pw run-code --filename "$(script_path "$tmp/ui_c5.js")" >"$tmp/ui_c5.out" 2>&1

    # ui_c phase 6 runs against a fifth server with one question and no events. A background
    # handler waits for the page to arm a watcher (the lease shows in /api/state), then handles
    # the answer as a handle-only apply while the page stays open.
    f="$tmp/f3"
    mkdir -p "$f"
    cp tests/fixtures/ui_d/questions.json "$f/"
    bash "$here/round.sh" --dir "$f" ensure-running --port 0 >/dev/null
    fport=$(sed -n 's/^PORT=//p' "$f/.interview-session.env" | tr -d '\r')
    sed "s/__PORT__/$fport/; s/__PHASE__/6/" tests/ui_c.js >"$tmp/ui_c6.js"
    (
      for _ in $(seq 1 120); do
        if grep -q '"watcher": *"w1"' <<<"$(curl -fs "http://127.0.0.1:$fport/api/state")"; then
          sleep 4
          read -r -a late <<<"$(unhandled "$f")"
          [[ "${#late[@]}" -gt 0 ]] && "$py" "$here/round.py" --dir "$f" handle --seq "${late[@]}"
          break
        fi
        sleep 0.5
      done
    ) >/dev/null 2>&1 &
    handler=$!
    pw run-code --filename "$(script_path "$tmp/ui_c6.js")" >"$tmp/ui_c6.out" 2>&1
    wait "$handler" 2>/dev/null
    bash "$here/round.sh" --dir "$f" stop >/dev/null 2>&1
    for n in 1 2 3 4 5 6; do grade "ui_c.$n" "$tmp/ui_c$n.out"; done
  }

  group_e() {
    # ui_e runs against its own server: one recommended and one withheld question, no events.
    mkdir -p "$g"
    cp tests/fixtures/ui_e/questions.json "$g/"
    bash "$here/round.sh" --dir "$g" ensure-running --port 0 >/dev/null
    gport=$(sed -n 's/^PORT=//p' "$g/.interview-session.env" | tr -d '\r')
    sed "s/__PORT__/$gport/" tests/ui_e.js >"$tmp/ui_e.js"
    pw run-code --filename "$(script_path "$tmp/ui_e.js")" >"$tmp/ui_e.out" 2>&1
    bash "$here/round.sh" --dir "$g" stop >/dev/null 2>&1
    grade ui_e "$tmp/ui_e.out"
  }

  group_journey() {
    # The journey runs against a fifth server seeded with an empty interview. It walks the whole
    # flow on one page in twenty phases; the shell writes as Claude between them.
    mkdir -p "$j/ops"
    cp tests/fixtures/journey/questions.json tests/fixtures/journey/responses.json "$j/"
    bash "$here/round.sh" --dir "$j" add-round --file tests/fixtures/journey/round1.json --round 1 >/dev/null
    bash "$here/round.sh" --dir "$j" ensure-running --port 0 >/dev/null
    jport=$(sed -n 's/^PORT=//p' "$j/.interview-session.env" | tr -d '\r')
    for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
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
    japply a '{"ops": [{"op": "reply", "id": "Q4", "text": "Slow means over five minutes per run."}, {"op": "context", "percent": 78, "zone": "amber"}]}'
    japply b '{"ops": [{"op": "wait", "id": "Q3", "waitsOn": "the retry benchmark", "by": "claude"},
    {"op": "wait", "id": "Q5", "waitsOn": "whether the version must be pinned to the lock file or float with each new runner image release", "by": "user"},
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
    # The reply to the note goes to the log; the Notes reply that asks raises the notice (phase 3).
    japply d2 '{"ops": [{"op": "note-reply", "needsAnswer": true, "text": "Should the retry count stay at three?"}]}'
    jrun 3
    jhandle
    japply e '{"ops": [{"op": "confirm-commitments", "id": "Q2", "reason": "Confirmed in the terminal"},
    {"op": "record-terminal", "id": "Q4", "decision": "accept"},
    {"op": "confirm-commitments", "id": "Q4", "reason": "Said yes in the terminal"},
    {"op": "restate", "sections": {"goal": "Ship green builds to staging on their own.",
      "constraints": "Builds stop at ten minutes.", "planningOwned": "How the cache key is built."}}]}'
    # A Notes reply that asks lands after the restatement: the restate notice must stay shown over it (phase 4).
    japply e2 '{"ops": [{"op": "note-reply", "needsAnswer": true, "text": "One more thing: what should the cache key include?"}]}'
    jrun 4
    jhandle
    bash "$here/round.sh" --dir "$j" revise Q7 --rec "Yes, from the merged pull requests and their linked issues." --affects none --keep-alternatives --force >/dev/null
    japply f '{"ops": [{"op": "restate", "sections": {"goal": "Ship green builds to staging, with the linked issues in the release notes.",
    "constraints": "Builds stop at ten minutes."}}]}'
    jrun 5
    jhandle
    # Near the 500-character line cap, with an unbroken token: phase 6 checks the page never widens.
    long="on the runner image, whether a supercalifragilisticexpialidocious_unbroken_token_that_never_wraps_0123456789 is acceptable"
    long="$long; $long; $long; and whether the lock file wins over the runner image default for every job"
    japply g '{"ops": [{"op": "wait", "id": "Q5", "clear": true},
    {"op": "record-terminal", "id": "Q5", "decision": "own", "text": "Pin it to the lock file."},
    {"op": "record-terminal", "id": "Q7", "decision": "accept"},
    {"op": "wait", "id": "Q3", "waitsOn": "a second benchmark '"$long"'", "by": "claude"},
    {"op": "set-status", "text": "Running a second benchmark '"$long"'"},
    {"op": "group", "id": "g3", "title": "Release", "dependsOn": ["g2"]},
    {"op": "add", "question": {"id": "Q8_runner_image_cache_key_follow_up_0123456789", "group": "g1", "stage": "interview",
      "short": "Cache key follow-up", "title": "Should the cache key include the runner image?",
      "recommendation": "Yes.", "commits": [], "alternatives": [{"key": "a", "text": "No"}, {"key": "b", "text": "Only on main"}]}},
    {"op": "record-terminal", "id": "Q8_runner_image_cache_key_follow_up_0123456789", "decision": "accept"}]}'
    jrun 6
    japply h '{"ops": [{"op": "wait", "id": "Q3", "clear": true}, {"op": "set-status", "clear": true}]}'
    jrun 7
    japply i '{"ops": [{"op": "activity", "text": "Checked the cache key while you were looking"}]}'
    jrun 8
    # One log entry, one plain Notes reply, then a Notes reply that asks: only the asking reply counts
    # in the title (phases 9, 11 and 13).
    japply j '{"ops": [{"op": "activity", "text": "Checked the cache key again while the tab was hidden"}, {"op": "note-reply", "text": "Still on track."}]}'
    japply j2 '{"ops": [{"op": "note-reply", "needsAnswer": true, "text": "Still on track on your side?"}]}'
    jrun 9
    jrun 10
    japply k '{"ops": [{"op": "activity", "text": "Checked the cache key with the panel open"}, {"op": "note-reply", "text": "Nothing new yet."}]}'
    japply k2 '{"ops": [{"op": "note-reply", "needsAnswer": true, "text": "Anything new on your side?"}]}'
    jrun 11
    jrun 12
    japply l '{"ops": [{"op": "activity", "text": "Checked the cache key after the page loaded hidden"}, {"op": "note-reply", "text": "Checking again."}]}'
    japply l2 '{"ops": [{"op": "note-reply", "needsAnswer": true, "text": "Should I check again?"}]}'
    jrun 13
    jhandle
    japply m '{"ops": [{"op": "add", "question": {"id": "Q9", "group": "g1", "stage": "interview",
    "short": "Pattern scope", "title": "Which patterns count?", "recommendation": "Only the ones in the lock file.",
    "commits": [], "alternatives": [{"key": "a", "text": "All of them"}, {"key": "b", "text": "None"}]}}]}'
    # The added Q9 goes to the log; the asking reply after it is what raises the toast in phase 14.
    japply m2 '{"ops": [{"op": "note-reply", "needsAnswer": true, "text": "Q9 is new: which patterns count?"}]}'
    jrun 14
    read -r -a js <<<"$(unhandled "$j")"
    bash "$here/round.sh" --dir "$j" revise Q9 --rec "All of them, since the lock file lists none." --alt "a:Only the ones in the lock file" --alt "b:Whatever the config names" --affects none --seq "${js[${#js[@]} - 1]}" >/dev/null
    jhandle
    # The revision goes to the log; the asking reply after it raises the notification in phase 15.
    japply m3 '{"ops": [{"op": "note-reply", "needsAnswer": true, "text": "Does that pattern scope work for you?"}]}'
    jrun 15
    # Phase 16 runs after the wrap-up: a new open question, a range in a question's facts, and a
    # third restatement the wrap-up never saw.
    japply n '{"ops": [{"op": "revise", "id": "Q6", "facts": "Compare Q1-Q3, Q6 and Q9 before deciding."},
    {"op": "add", "question": {"id": "Q10", "group": "g1", "stage": "interview", "short": "Cache scope", "title": "Which jobs share the cache?",
      "recommendation": "Only the jobs on the same runner image.", "commits": ["Shares one cache across jobs"], "alternatives": [{"key": "a", "text": "Every job"}, {"key": "b", "text": "None"}]}},
    {"op": "restate", "sections": {"goal": "Ship green builds to staging, with the linked issues in the release notes.",
      "constraints": "Builds stop at ten minutes and share one cache."}}]}'
    # A Notes reply after the restatement: the restate notice outranks it in phase 16.
    japply n2 '{"ops": [{"op": "note-reply", "needsAnswer": true, "text": "Anything else before the Brief?"}]}'
    # An ordinary Claude note after it must not unpin the question.
    sleep 1
    japply n3 '{"ops": [{"op": "note-reply", "text": "The restatement is posted."}]}'
    jrun 16
    # Phase 17 confirms the third restatement. The shell then posts a status and the finish op,
    # phase 18 reads the modal, the shell stops the server (phase 19 reads the offline reason) and
    # starts it again on the same data dir, which must keep its port (phase 20 reads the restart).
    jrun 17
    japply o '{"ops": [{"op": "set-status", "text": "Done: the Brief is written"},
    {"op": "finish", "brief": "docs/PLAN.md", "next": "Run the plan with the next step.", "text": "The interview is complete."},
    {"op": "context", "handoff": "Resume from docs/handoff.md in a fresh session."}]}'
    jrun 18
    bash "$here/round.sh" --dir "$j" stop >/dev/null
    jrun 19
    bash "$here/round.sh" --dir "$j" ensure-running --port 0 >/dev/null
    [[ "$(sed -n 's/^PORT=//p' "$j/.interview-session.env" | tr -d '\r')" == "$jport" ]] || bad "journey: stop then ensure-running changed the port"
    jrun 20
    bash "$here/round.sh" --dir "$j" stop >/dev/null 2>&1
    for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do grade "ui_journey.$n" "$tmp/uj$n.out"; done
  }

  group_live() {
    # ui_live runs against a sixth server on the journey's first round. One tab stays open with a note
    # half typed while the shell applies as Claude: reply with rec, revise, record-terminal, handle-only,
    # then a revise of only an accepted question's title and short.
    l="$tmp/live"
    mkdir -p "$l/ops"
    cp tests/fixtures/journey/questions.json tests/fixtures/journey/responses.json "$l/"
    bash "$here/round.sh" --dir "$l" add-round --file tests/fixtures/journey/round1.json --round 1 >/dev/null
    bash "$here/round.sh" --dir "$l" ensure-running --port 0 >/dev/null
    lport=$(sed -n 's/^PORT=//p' "$l/.interview-session.env" | tr -d '\r')
    for n in 1 2 3 4 5 6; do
      sed "s/__PORT__/$lport/; s/__PHASE__/$n/" tests/ui_live.js >"$tmp/ul$n.js"
    done
    lrun() { pw run-code --filename "$(script_path "$tmp/ul$1.js")" >"$tmp/ul$1.out" 2>&1; }
    lrun 1
    printf '%s' '{"ops": [{"op": "reply", "id": "Q1", "text": "Narrowed.", "rec": "Yes, but only for tagged releases.", "why": "Pushes are too noisy.", "affects": "none", "keepAlternatives": true}]}' >"$l/ops/a.json"
    bash "$here/round.sh" --dir "$l" apply --file "$l/ops/a.json" >/dev/null || bad "live: reply op refused"
    lrun 2
    bash "$here/round.sh" --dir "$l" revise Q1 --rec "Yes, every push on main and every tag." --alt "a:Only on tags" --alt "b:Only by hand" --affects none --force >/dev/null || bad "live: revise refused"
    lrun 3
    printf '%s' '{"ops": [{"op": "record-terminal", "id": "Q2", "decision": "accept"}]}' >"$l/ops/b.json"
    bash "$here/round.sh" --dir "$l" apply --file "$l/ops/b.json" >/dev/null || bad "live: record-terminal op refused"
    read -r -a ls <<<"$(unhandled "$l")"
    [[ "${#ls[@]}" -gt 0 ]] || bad "live: the page's accept left no event to handle"
    printf '%s' '{"ops": [{"op": "handle", "seqs": ['"${ls[*]// /, }"']}]}' >"$l/ops/c.json"
    bash "$here/round.sh" --dir "$l" apply --file "$l/ops/c.json" >/dev/null || bad "live: handle op refused"
    lrun 4
    # #7757: the page ticks Q3's commitment, then a revise of only its title and short must leave it closed
    lrun 5
    bash "$here/round.sh" --dir "$l" revise Q3 --title "Should the build cache its dependencies between runs?" --short "Dependency cache" --force >/dev/null || bad "live: title and short revise refused"
    grep -qE 'open: .*Q3 |Q3 .*to confirm' <<<"$(bash "$here/round.sh" --dir "$l" status)" && bad "live: status lists Q3 open or to confirm after the title and short revise"
    lrun 6
    bash "$here/round.sh" --dir "$l" stop >/dev/null 2>&1
    for n in 1 2 3 4 5 6; do grade "ui_live.$n" "$tmp/ul$n.out"; done
  }

  group_page() {
    # ui_page runs against a seventh server on its own round: the choices, chips, banners, header
    # and layout of one question page, with the shell writing as Claude between phases.
    pg="$tmp/page"
    mkdir -p "$pg/ops"
    cp tests/fixtures/journey/questions.json tests/fixtures/journey/responses.json "$pg/"
    bash "$here/round.sh" --dir "$pg" add-round --file tests/fixtures/ui_page/round.json --round 1 >/dev/null || bad "page: add-round refused"
    bash "$here/round.sh" --dir "$pg" ensure-running --port 0 >/dev/null
    gport=$(sed -n 's/^PORT=//p' "$pg/.interview-session.env" | tr -d '\r')
    gphases=14
    for n in $(seq 1 "$gphases"); do
      sed "s/__PORT__/$gport/; s/__PHASE__/$n/" tests/ui_page.js >"$tmp/up$n.js"
    done
    grun() { pw run-code --filename "$(script_path "$tmp/up$1.js")" >"$tmp/up$1.out" 2>&1; }
    grev() { bash "$here/round.sh" --dir "$pg" revise "$@" --affects none --keep-alternatives --force >/dev/null || bad "page: revise $1 refused"; }
    grun 1
    grev Q1 --rec "Ship it on Tuesday. Watch the error logs for a week after."
    grun 2
    grev Q1 --rec "Ship it on Wednesday."
    grun 3
    grun 4
    grev Q3 --rec "The default image, pinned by digest." --why "A digest cannot move under a tag."
    grun 5
    grun 6
    read -r -a gs <<<"$(unhandled "$pg")"
    bash "$here/round.sh" --dir "$pg" reply Q8 --text "The support team reads them first." --seq "${gs[${#gs[@]} - 1]}" >/dev/null || bad "page: reply refused"
    grun 7
    grun 8
    grun 9
    printf '%s' '{"ops": [{"op": "add", "question": {"id": "Q9", "group": "g1", "stage": "interview", "short": "Notes owner", "title": "Who writes the release notes?", "recommendation": "The release owner.", "dependsOn": ["Q8"], "commits": [], "alternatives": [{"key": "a", "text": "Each author"}, {"key": "b", "text": "Nobody"}]}},
    {"op": "record-terminal", "id": "Q9", "decision": "accept"}]}' >"$pg/ops/t.json"
    bash "$here/round.sh" --dir "$pg" apply --file "$pg/ops/t.json" >/dev/null || bad "page: add and record-terminal refused"
    # An older terminal record has no rev: strip it, then revise Q9 so only the time orders the two.
    "$py" -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); [q["terminal"].pop("rev", None) for q in d["questions"] if q["id"] == "Q9"]; json.dump(d, open(p, "w"))' "$pg/questions.json"
    grev Q9 --rec "The release owner, with the support lead."
    # Phase 10: a Notes reply that asks belongs under Needs you, a plain one in the log.
    bash "$here/round.sh" --dir "$pg" note-reply --text "Plain note: the owner is settled." >/dev/null || bad "page: note-reply refused"
    bash "$here/round.sh" --dir "$pg" note-reply --text "Asking note: should support sign off?" --needs-answer >/dev/null || bad "page: note-reply --needs-answer refused"
    grun 10
    grun 11
    printf '%s' '{"ops": [{"op": "constraint", "text": "Builds stop at ten minutes."}, {"op": "constraint", "text": "Stdlib only."}]}' >"$pg/ops/k.json"
    bash "$here/round.sh" --dir "$pg" apply --file "$pg/ops/k.json" >/dev/null || bad "page: constraint ops refused"
    grun 12
    # Phases 13 and 14, the frontier lock: Q11 is open in round 2 and Q12 in round 3 depends on it.
    # Phase 13 runs the default confirm; the shell then sets the data dir's lock to hard.
    printf '%s' '{"ops": [{"op": "add", "question": {"id": "Q11", "group": "g1", "stage": "interview", "round": 2, "short": "Rollout", "title": "How wide is the first rollout?", "recommendation": "One region.", "dependsOn": [], "commits": [], "alternatives": [{"key": "a", "text": "Every region"}, {"key": "b", "text": "Staff only"}]}},
    {"op": "add", "question": {"id": "Q12", "group": "g1", "stage": "interview", "round": 3, "short": "Rollout gate", "title": "What gates the second region?", "recommendation": "A clean week of error logs.", "dependsOn": ["Q11"], "commits": [], "alternatives": [{"key": "a", "text": "A fixed date"}, {"key": "b", "text": "Nothing"}]}}]}' >"$pg/ops/lock.json"
    bash "$here/round.sh" --dir "$pg" apply --file "$pg/ops/lock.json" >/dev/null || bad "page: the frontier-lock questions were refused"
    grun 13
    printf '%s' '{"frontierLock": "hard"}' >"$pg/settings.json"
    grun 14
    bash "$here/round.sh" --dir "$pg" stop >/dev/null 2>&1
    for n in $(seq 1 "$gphases"); do grade "ui_page.$n" "$tmp/up$n.out"; done
  }

  for grp in $groups; do "group_$grp"; done
else
  browser=0
  for grp in $groups; do browser=$((browser + CHECKS[$grp])); done
  echo "SKIP: $browser browser checks of groups ${groups# } not run (playwright-cli not found)" # silent-skip-ok: browser checks need a local playwright-cli # discriminating-skip-ok: the API, watcher and hygiene checks above still grade this suite
  skip=$((skip + browser))
fi

echo "PASS=$pass FAIL=$fail SKIP=$skip"
[[ "$fail" -eq 0 ]]
