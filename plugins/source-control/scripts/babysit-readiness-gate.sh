#!/usr/bin/env bash
# babysit-readiness-gate.sh — deterministic readiness pre-gate for babysit.
#
# Converts the three weakest tier-9 babysit steps into a tier-5 mechanical
# block (per the 2026-05-28 audit, AUDIT.md, findings R1+R5+R6 — one mechanism):
#
#   R1 finding decomposition  — every source finding must be individually
#                               classified, not batch-glossed (review-discipline.md §2)
#   R5 addressed/unaddressed  — findings present but unclassified = unaddressed
#   R6 checklist completeness — the iteration checklist (babysit-prs loop.md
#                               §5.5) has no unticked box
#
# Why a gate, not prose: the audit proved the advisory "MANDATORY subagent
# dispatch for >=3 findings" rule produced ZERO of its mandated per-finding
# tables across multi-finding PRs — one audit classified 16 findings of ~32.
# Prose "MANDATORY" is a word; this gate counts rows, not intentions, and
# refuses to let readiness be declared while the counts don't add up.
#
# DETECTION (aggregate, schema-grounded on fetch-all-pr-comments.sh output,
# which carries {id,type,author,body,...} but NOT reply-thread links):
#   findings   = OCCURRENCES of a severity marker (CRITICAL|IMPORTANT|SUGGESTION,
#                or codex P1/P2/P3 per review-discipline.md §2) across all NON-self
#                comments — counted per match, not per line, so N findings on one
#                line each count (else a multi-finding line under-counts and the
#                gate false-passes)
#   classified = TABLE ROWS (`|`-prefixed lines) carrying a classification
#                token (VALID|INCORRECT|UNCERTAIN) across all SELF replies —
#                one per line, so prose repetition never inflates the count.
#                Word-boundary matched so "INVALID" does not count as "VALID".
#                Capped at findings so a surplus of rows cannot mask an
#                unclassified finding (the Python path refines this to a
#                per-surface credit — see the classifier-preference note below).
#   BLOCK when findings > 0 AND classified < findings (under-decomposed /
#   unaddressed — R1+R5), OR when a --checklist file has any "- [ ]" (R6).
#
# This is a PURE PREDICATE — detection only, no GitHub writes. The skill runs
# it before completing an iteration / scheduling the next wake.
#
# NOT a merge-readiness check. This gate is blind to branch rules, review
# decision, unresolved threads, required checks, and head match. Only the merge
# gate (babysit_merge.py, via the source-control-babysit-merge wrapper) reports
# whether the PR may be merged -- GitHub's own mergeability AND the plugin's own
# policy holds (dependency-manager author, unprotected base, autopilot tier).
# A passing classification verdict is never evidence of that. The token is not
# spelled at the start of a line here: this header is the --help output, and a
# caller's ^READINESS_ grep would read documentation as a malformed verdict.
# See skills/babysit-prs/reference/safety.md "Two Gates, One Merge-Ready Authority".
#
# Usage:
#   babysit-readiness-gate.sh <pr>
#   babysit-readiness-gate.sh <pr> --comments-json <file>   # skip network (tests/reuse)
#   babysit-readiness-gate.sh <pr> --checklist <file>       # also gate R6
#   babysit-readiness-gate.sh <pr> --self 'login,login2'    # self authors, full override
#                              (else `gh api user` login)
#   babysit-readiness-gate.sh <pr> --extra-self 'bot1,bot2' # extra self authors added to the
#                              `gh api user` login — the invoking skill wires the
#                              babysit_self_logins userConfig option here
#   babysit-readiness-gate.sh --help
#
# Repo resolution (live comment fetch): owner/repo is auto-derived from the
#   CURRENT directory via `gh repo view`, so run this from a checkout of the
#   target repo. When that cannot resolve (e.g. a recheck pass whose cwd is not
#   the target repo), export FETCH_COMMENTS_OWNER and FETCH_COMMENTS_REPO to
#   override — the gate passes them through to fetch-all-pr-comments.sh.
#
# Stdout (machine-readable — EXACTLY ONE verdict line on EVERY check run,
# including every failure path, so an absent verdict line can only mean the gate
# never ran). `--help` is NOT a check run: it prints this header and exits 0
# carrying no verdict, so never parse a help run for one:
#   READINESS_OK findings=<n> classified=<n> checklist=<clean|n/a>
#   READINESS_BLOCKED reason=<under-decomposed|checklist-incomplete> findings=<n> classified=<n> unticked=<n>
#   READINESS_UNPROVEN reason=<bad-args|identity-unresolved|prereq-missing|comments-unreadable|fetch-failed> pr=<n|unknown>
#
# The READINESS_UNPROVEN token is the fail-closed third verdict, and the reason
# this gate emits on the paths where it used to write stderr only: a caller that
# greps stdout for a verdict saw NOTHING on those paths, which is
# indistinguishable from a run that was never attempted — the exact confusion
# that let a blocked gate be reported as readiness (#787). UNPROVEN means
# readiness was NOT proven; it never licenses substituting live `gh` state
# (mergeStateStatus, the check rollup) for the gate's verdict. See
# skills/babysit-prs/reference/safety.md "Lane-Script Reachability". Exit codes
# are unchanged — the token is additive.
#
# Every header line describing a verdict stays indented or mid-sentence: an
# unindented `READINESS_*` here would leave `--help` output matching a caller's
# `^READINESS_` verdict grep.
#
# Exit codes:
#   0  ready (decomposition satisfied + checklist clean/absent)
#   1  blocked (READINESS_BLOCKED names the reason)
#   3  invalid argument (READINESS_UNPROVEN reason=bad-args), or the self
#      identity could not be resolved with valid arguments — an expired `gh`
#      auth, an unreachable API, or an offline snapshot replay
#      (reason=identity-unresolved). The two share exit 3 so callers keyed on
#      the code are unaffected; the reason is what tells an operator whether to
#      fix the flags or repair the identity prerequisite.
#   4  prerequisite missing (jq), the PR comment fetch failed, or the resolved
#      comment payload is not a JSON array — see stderr for the cause
#      (owner/repo may be unresolved; see Repo resolution above)
#      (READINESS_UNPROVEN reason=prereq-missing|fetch-failed|comments-unreadable)

set -uo pipefail
# Matches the `export PYTHONUTF8=1` convention the bin/ babysit wrappers already
# apply before invoking babysit_python (source-control-babysit-merge,
# source-control-babysit-resolve-thread). This gate is the third babysit_python
# caller and the one that parses fetch-all-pr-comments.sh-shaped JSON (via
# babysit_findings.py --comments-json), which commonly carries non-ASCII bytes
# (bot badges, reaction emoji) from bot review comments — PEP 540 UTF-8 mode
# keeps the interpreter's default I/O encoding independent of the Windows ANSI
# code page (cp1252) for any code path that does not pin encoding="utf-8"
# itself (#597).
export PYTHONUTF8=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PR_NUMBER=""
COMMENTS_JSON=""
CHECKLIST=""
SELF_CSV=""
EXTRA_SELF_CSV=""

# Print the header block (everything after the shebang up to the first
# non-comment line) with its comment markers stripped. Derived rather than a
# hardcoded line range, which silently truncated or over-ran as the header grew.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
    "${BASH_SOURCE[0]}"
  exit 0
}

# Emit the fail-closed third verdict on stdout, then exit with the code the
# caller already documents. Every non-verdict exit routes through here so the
# machine-readable stream never goes silent: silence is reserved for "the gate
# never ran at all", which is the only state this script cannot report itself.
unproven() { # unproven <reason> <exit-code>
  printf 'READINESS_UNPROVEN reason=%s pr=%s\n' "$1" "${PR_NUMBER:-unknown}"
  exit "$2"
}

# Assert a flag's value argument is present and not itself a flag, else exit 3.
require_value() {
  [[ -n "${2:-}" && "$2" != -* ]] || {
    printf 'babysit-readiness-gate: %s requires an argument\n' "$1" >&2
    unproven bad-args 3
  }
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --comments-json)
    require_value "$1" "${2:-}"
    COMMENTS_JSON="$2"
    shift 2
    ;;
  --checklist)
    require_value "$1" "${2:-}"
    CHECKLIST="$2"
    shift 2
    ;;
  --self)
    require_value "$1" "${2:-}"
    SELF_CSV="$2"
    shift 2
    ;;
  --extra-self)
    require_value "$1" "${2:-}"
    EXTRA_SELF_CSV="$2"
    shift 2
    ;;
  -*)
    printf 'babysit-readiness-gate: unknown flag %q (use --help)\n' "$1" >&2
    unproven bad-args 3
    ;;
  *)
    if [[ -z "$PR_NUMBER" ]]; then
      PR_NUMBER="$1"
    else
      printf 'babysit-readiness-gate: unexpected argument %q\n' "$1" >&2
      unproven bad-args 3
    fi
    shift
    ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
have jq || {
  printf 'babysit-readiness-gate: jq required\n' >&2
  unproven prereq-missing 4
}

if [[ -z "$PR_NUMBER" && -z "$COMMENTS_JSON" ]]; then
  printf 'babysit-readiness-gate: <pr> required (or --comments-json <file>)\n' >&2
  unproven bad-args 3
fi

# --- Resolve comments JSON (fixture file OR live fetch) -----------------------

COMMENTS=""
if [[ -n "$COMMENTS_JSON" ]]; then
  if [[ ! -f "$COMMENTS_JSON" ]]; then
    printf 'babysit-readiness-gate: --comments-json file not found: %s\n' "$COMMENTS_JSON" >&2
    unproven bad-args 3
  fi
  COMMENTS="$(cat "$COMMENTS_JSON")"
else
  COMMENTS="$(bash "$SCRIPT_DIR/fetch-all-pr-comments.sh" "$PR_NUMBER")" || {
    printf 'babysit-readiness-gate: could not fetch comments for PR %s (fetch-all-pr-comments error above).\n' "$PR_NUMBER" >&2
    printf 'babysit-readiness-gate: owner/repo is auto-derived from the current directory (%s) via gh repo view. Run from a checkout of the target repo, or export FETCH_COMMENTS_OWNER and FETCH_COMMENTS_REPO to override.\n' "$PWD" >&2
    unproven fetch-failed 4
  }
fi

# The counters below consume this payload as a JSON ARRAY (`.[]`). Anything else
# — a truncated or hand-edited snapshot, a scalar, an object, an error document a
# fetch returned with exit 0 — used to reach them unchecked: jq failed, the
# counts stayed 0, and the gate printed `READINESS_OK findings=0`. That is a
# ready verdict derived from data the gate never read, which is exactly the
# fail-open this script exists to close. Validated once here, on the RESOLVED
# payload, so the snapshot path and the live-fetch path are both covered.
printf '%s' "$COMMENTS" | jq -e 'type == "array"' >/dev/null || {
  printf 'babysit-readiness-gate: comment payload is not a JSON array (source: %s)\n' \
    "${COMMENTS_JSON:-live fetch}" >&2
  unproven comments-unreadable 4
}

# --- Resolve self authors (whose replies are the classification rows) ---------

SELF_LOGINS=()
if [[ -n "$SELF_CSV" ]]; then
  IFS=',' read -r -a SELF_LOGINS <<<"$SELF_CSV"
else
  # --extra-self (csv) covers extra posting identities — e.g. a project bot
  # account whose replies carry the classification tables — added on top of the
  # personal login. The invoking skill wires the babysit_self_logins userConfig
  # option here.
  if [[ -n "$EXTRA_SELF_CSV" ]]; then
    IFS=',' read -r -a SELF_LOGINS <<<"$EXTRA_SELF_CSV"
  fi
  personal_login="$(gh api user --jq .login 2>/dev/null | tr -d '\r')"
  [[ -n "$personal_login" ]] && SELF_LOGINS+=("$personal_login")
fi
# Reaching here means neither --self nor --extra-self was supplied AND the
# supported `gh api user` default failed — expired auth, an unreachable API, or
# an offline replay of a saved snapshot. The ARGUMENTS were valid, so reporting
# `reason=bad-args` sends an operator (and the loop report that quotes this
# verdict verbatim) off to edit flags that are already correct. The prerequisite
# to repair is the identity lookup, and the reason now says so. The exit code
# stays 3 for callers already keyed on it.
if [[ ${#SELF_LOGINS[@]} -eq 0 ]]; then
  printf 'babysit-readiness-gate: cannot resolve self identity: the gh api user lookup returned no login (pass --self or --extra-self)\n' >&2
  unproven identity-unresolved 3
fi
SELF_JSON="$(printf '%s\n' "${SELF_LOGINS[@]}" | jq -R . | jq -s .)"

# --- Split bodies by author class --------------------------------------------

# Matches BOTH reviewer severity vocabularies, counting ONE marker per finding,
# PORTABLY. BSD grep on macOS does NOT support the `\b` word-boundary escape (it
# matches a literal "b"); POSIX `-w` whole-word matching works on GNU + BSD
# (codex r3327816802). claude uses the words CRITICAL|IMPORTANT|SUGGESTION,
# matched whole-word so "INVALID" is not a finding and the lowercase
# priority:p0-critical .. p3-low labels some repos use do not false-count. codex
# uses a P0|P1|P2|P3 shields.io badge (per review-discipline.md §2): keyed on the
# shield-URL segment `/badge/P{N}-`, which appears exactly once per finding (the
# alt-text `![PN Badge]` carries the token a second time, so a bare `P[0-3]` would  # spellchecker:disable-line
# double-count), is the rigid badge-template structure, and is unambiguous —
# `/badge/P0-` never matches a lowercase priority:p0-critical label, so a codex P0
# finding is counted (r3327701794). Words and badges are counted separately and
# summed because `-w` cannot bound the badge URL (its match starts right after a
# word char in `shields.io/badge/...`).
SEVERITY_WORDS_RE='CRITICAL|IMPORTANT|SUGGESTION'
SEVERITY_BADGE_RE='/badge/P[0-3]-'
# Plain bracketed P-severity markers ([P0] .. [P3]) — a common reviewer format
# with neither a severity word nor a shields badge. The badge alt text is
# `![PN Badge]` (space before the closing bracket), so this pattern cannot  # spellchecker:disable-line
# double-count a badge finding. Bounded to P0-P3 (the documented reviewer
# range, matching SEVERITY_BADGE_RE) so incidental [P4]+ text cannot inflate
# the finding count into a false READINESS_BLOCKED.
SEVERITY_PLAIN_RE='\[P[0-3]\]'
CLASSIFY_RE='VALID|INCORRECT|UNCERTAIN'

# Findings are counted across ALL comment bodies, not just non-self ones: in an
# interactive babysit run SELF_JSON includes the authenticated gh user, and a
# maintainer can author a SOURCE finding (a severity / badge), not only a
# classification reply. Counting findings over every body keeps those self
# findings visible (codex r3327878326). A classification reply carries a
# VALID/INCORRECT/UNCERTAIN token, NOT a severity/badge, so it never inflates the
# finding count; classifications are still counted only from self bodies.
# Neither extraction suppresses jq's stderr, and both route a non-zero status
# through the fail-closed verdict. Swallowing them left a jq failure looking
# exactly like a comment set with no bodies — findings=0, READINESS_OK — so the
# gate could pass on input it never parsed. The array-shape check above rejects
# the common malformed payloads; these guards catch what survives it (an array
# whose elements are not comment objects).
non_self_bodies="$(printf '%s' "$COMMENTS" |
  jq -r --argjson self "$SELF_JSON" '
    .[] | select((.author as $a | $self | index($a)) | not) | .body // ""')" || {
  printf 'babysit-readiness-gate: could not read comment bodies (source: %s)\n' \
    "${COMMENTS_JSON:-live fetch}" >&2
  unproven comments-unreadable 4
}
self_bodies="$(printf '%s' "$COMMENTS" |
  jq -r --argjson self "$SELF_JSON" '
    .[] | select((.author as $a | $self | index($a))) | .body // ""')" || {
  printf 'babysit-readiness-gate: could not read comment bodies (source: %s)\n' \
    "${COMMENTS_JSON:-live fetch}" >&2
  unproven comments-unreadable 4
}

# Self classification-table rows are EXCLUDED from the finding corpus: a
# reply row like `| 1 | CRITICAL: null deref | VALID | ... |` repeats the
# source severity word, which would otherwise mint a phantom finding
# (findings=2 classified=1 → permanently blocked) — codex r3564159124.
# Non-table self content (a maintainer authoring a genuine source finding)
# still counts. The [^A-Za-z] guards keep e.g. "INVALID" rows countable.
self_source_bodies="$(printf '%s\n' "$self_bodies" |
  grep -vE '^[[:space:]]*\|.*[^A-Za-z](VALID|INCORRECT|UNCERTAIN)([^A-Za-z]|$)' || true)"
all_bodies="$non_self_bodies
$self_source_bodies"

# FINDINGS: grep -o ... | grep -c . counts OCCURRENCES (one match per output
# line), not input lines — a single line with two markers must count as two
# findings, or the gate under-counts and false-passes (the very R1
# decomposition gap it gates). `-w` = POSIX whole-word (portable to BSD grep);
# the badge URL is counted with a plain `-o` grep (no `-w`) and summed in.
#
# CLASSIFICATIONS: counted as TABLE ROWS (markdown `|`-prefixed lines carrying
# a token), one per line — NOT free occurrences. A prose reply repeating
# "VALID" in its evidence sentence must not count twice, or the gate
# false-passes while findings lack per-finding rows (codex r3564093178). The
# per-finding classification TABLE is the mandated reply format
# (review-discipline.md §2), so non-table prose classifications intentionally
# do not count.
sev_words=$(printf '%s\n' "$all_bodies" | grep -owE "$SEVERITY_WORDS_RE" | grep -c . || true)
sev_badges=$(printf '%s\n' "$all_bodies" | grep -oE "$SEVERITY_BADGE_RE" | grep -c . || true)
sev_plain=$(printf '%s\n' "$all_bodies" | grep -oE "$SEVERITY_PLAIN_RE" | grep -c . || true)
classified=$(printf '%s\n' "$self_bodies" | grep -E '^[[:space:]]*\|' | grep -cwE "$CLASSIFY_RE" || true)
sev_words=${sev_words//[^0-9]/}
sev_badges=${sev_badges//[^0-9]/}
sev_plain=${sev_plain//[^0-9]/}
classified=${classified//[^0-9]/}
findings=$((${sev_words:-0} + ${sev_badges:-0} + ${sev_plain:-0}))
classified=${classified:-0}

# Cap classified at findings: a surplus of classification rows cannot offset
# findings that do not exist. This is the coarse, thread-state-free analogue of
# the Python counter's per-surface credit (#642) — the bash degrade has no
# reply-thread links, so it cannot bucket thread vs PR-level, but capping still
# stops an over-count of rows from masking an unclassified finding, and keeps
# the degrade count convergent with the Python `min(classified, findings)` on
# thread-state-free input.
((classified > findings)) && classified="$findings"

# --- Prefer the shared Python classifier when available -----------------------

# The bash counts above are the Python-free safe-tier degrade (reference/loop.md
# is that path, and it runs this gate). When a Python 3.11+ interpreter is
# present, re-count via the shared babysit_classify module instead: it owns the
# severity vocabulary as ONE source of truth rather than a second bash copy that
# can drift from the snapshot classifier (the divergence class #534 exists to
# close), and it discounts a severity marker carried in a resolved or outdated
# thread, so a lifetime badge no longer inflates the count into a false
# READINESS_BLOCKED (#465). It also credits classifications per surface — a
# PR-level (non-thread) row cannot offset a finding raised fresh in an open
# review thread — closing a fail-open the thread-blind bash degrade cannot see
# (#642). A convergence test pins the two counts together on thread-state-free
# input; if the Python counter cannot run (no interpreter, or a transient live
# fetch failure) the bash degrade counts above stand.
# BABYSIT_READINESS_BASH_ONLY=1 forces the degrade even when Python is present --
# the operator escape that exercises (and, in the gate's own tests, pins) the
# Python-free path deterministically.
PY_SCRIPTS="$SCRIPT_DIR/../skills/babysit-prs/scripts"
if [[ "${BABYSIT_READINESS_BASH_ONLY:-}" != 1 && -f "$PY_SCRIPTS/babysit-python.sh" ]]; then
  # shellcheck source=../skills/babysit-prs/scripts/babysit-python.sh
  . "$PY_SCRIPTS/babysit-python.sh"
  self_csv_joined="$(
    IFS=,
    printf '%s' "${SELF_LOGINS[*]}"
  )"
  if [[ -n "$COMMENTS_JSON" ]]; then
    py_out="$(babysit_python "$PY_SCRIPTS/babysit_findings.py" \
      --comments-json "$COMMENTS_JSON" --self "$self_csv_joined" 2>/dev/null)"
  else
    py_out="$(babysit_python "$PY_SCRIPTS/babysit_findings.py" \
      --pr "$PR_NUMBER" --self "$self_csv_joined" 2>/dev/null)"
  fi
  if [[ "$py_out" =~ findings=([0-9]+)[[:space:]]+classified=([0-9]+) ]]; then
    findings="${BASH_REMATCH[1]}"
    classified="${BASH_REMATCH[2]}"
  fi
fi

# --- R6: checklist completeness ----------------------------------------------

unticked=0
checklist_state="n/a"
if [[ -n "$CHECKLIST" ]]; then
  if [[ ! -f "$CHECKLIST" ]]; then
    printf 'babysit-readiness-gate: --checklist file not found: %s\n' "$CHECKLIST" >&2
    unproven bad-args 3
  fi
  unticked=$(grep -cE '^[[:space:]]*-[[:space:]]\[[[:space:]]\]' "$CHECKLIST" || true)
  unticked=${unticked//[^0-9]/}
  unticked=${unticked:-0}
  ((unticked == 0)) && checklist_state="clean" || checklist_state="incomplete"
fi

# --- Verdict ------------------------------------------------------------------

if ((findings > 0 && classified < findings)); then
  printf 'READINESS_BLOCKED reason=under-decomposed findings=%s classified=%s unticked=%s\n' \
    "$findings" "$classified" "$unticked"
  exit 1
fi

if ((unticked > 0)); then
  printf 'READINESS_BLOCKED reason=checklist-incomplete findings=%s classified=%s unticked=%s\n' \
    "$findings" "$classified" "$unticked"
  exit 1
fi

printf 'READINESS_OK findings=%s classified=%s checklist=%s\n' \
  "$findings" "$classified" "$checklist_state"
exit 0
