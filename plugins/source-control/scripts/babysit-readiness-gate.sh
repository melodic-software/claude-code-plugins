#!/usr/bin/env bash
# Exit codes:
#   0  ready (decomposition satisfied + checklist clean/absent)
#   1  blocked (READINESS_BLOCKED names the reason)
#   3  invalid argument (READINESS_UNPROVEN reason=bad-args), or the self
#      identity could not be resolved with valid arguments — an expired `gh`
#      auth, an unreachable API, or an offline snapshot replay
#      (reason=identity-unresolved). The two share exit 3 so callers keyed on
#      the code are unaffected; the reason is what tells an operator whether to
#      fix the flags or repair the identity prerequisite.
#   4  prerequisite missing (jq), the PR comment fetch failed, the resolved
#      comment payload is not a JSON array, or a --checklist file that exists
#      could not be read — see stderr for the cause (owner/repo may be
#      unresolved; see Repo resolution above). An unreadable checklist is
#      UNPROVEN rather than clean: zero matches and zero readable lines are the
#      same count, and only one of them is evidence.
#      (READINESS_UNPROVEN reason=prereq-missing|fetch-failed|comments-unreadable|checklist-unreadable)

set -uo pipefail
export PYTHONUTF8=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PR_NUMBER=""
COMMENTS_JSON=""
CHECKLIST=""
SELF_CSV=""
EXTRA_SELF_CSV=""
REPO_SLUG=""

usage() {
  cat <<'EOF'
babysit-readiness-gate.sh: block readiness while a PR's review findings outnumber its classified rows.

Usage:
  babysit-readiness-gate.sh <pr> [options]

  --repo <owner/repo>      the PR's repository (default: the current directory's)
  --comments-json <file>   read comments from this file, no network
  --checklist <file>       also block on an unticked "- [ ]" box
  --self <logins>          self authors, comma-separated (default: the `gh api user` login)
  --extra-self <logins>    self authors added to the `gh api user` login
  FETCH_COMMENTS_OWNER and FETCH_COMMENTS_REPO override the repository; --repo sets both.

Stdout, one verdict line on every check run (--help prints none):
  READINESS_OK findings=<n> classified=<n> checklist=<clean|n/a>
  READINESS_BLOCKED reason=<reason> findings=<n> classified=<n> unticked=<n>
  READINESS_UNPROVEN reason=<reason> pr=<n|unknown>

Exit codes:
  0  ready
  1  blocked
  3  invalid argument, or the self identity could not be resolved
  4  prerequisite missing, the comment fetch failed or is not a JSON array,
     or the checklist could not be read
EOF
  exit 0
}

unproven() { # unproven <reason> <exit-code>
  printf 'READINESS_UNPROVEN reason=%s pr=%s\n' "$1" "${PR_NUMBER:-unknown}"
  exit "$2"
}

require_value() {
  [[ -n "${2:-}" && "$2" != -* ]] || {
    printf 'babysit-readiness-gate: %s requires an argument\n' "$1" >&2
    unproven bad-args 3
  }
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --comments-json | --checklist | --self | --extra-self | --repo)
    require_value "$1" "${2:-}"
    case "$1" in
    --comments-json) COMMENTS_JSON="$2" ;;
    --checklist) CHECKLIST="$2" ;;
    --self) SELF_CSV="$2" ;;
    --extra-self) EXTRA_SELF_CSV="$2" ;;
    *) REPO_SLUG="$2" ;;
    esac
    shift 2
    ;;
  -*)
    printf 'babysit-readiness-gate: unknown flag %q (use --help)\n' "$1" >&2
    unproven bad-args 3
    ;;
  *)
    if [[ -z "$PR_NUMBER" ]]; then
      if [[ ! "$1" =~ ^[0-9]+$ ]]; then
        printf 'babysit-readiness-gate: <pr> must be a number, got %q\n' "$1" >&2
        unproven bad-args 3
      fi
      PR_NUMBER="$1"
    else
      printf 'babysit-readiness-gate: unexpected argument %q\n' "$1" >&2
      unproven bad-args 3
    fi
    shift
    ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  printf 'babysit-readiness-gate: jq required\n' >&2
  unproven prereq-missing 4
}

if [[ -z "$PR_NUMBER" && -z "$COMMENTS_JSON" ]]; then
  printf 'babysit-readiness-gate: <pr> required (or --comments-json <file>)\n' >&2
  unproven bad-args 3
fi

if [[ -n "$REPO_SLUG" ]]; then
  if [[ ! "$REPO_SLUG" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    printf 'babysit-readiness-gate: --repo must be owner/repo, got %q\n' "$REPO_SLUG" >&2
    unproven bad-args 3
  fi
  FETCH_COMMENTS_OWNER="${REPO_SLUG%%/*}"
  FETCH_COMMENTS_REPO="${REPO_SLUG#*/}"
  export FETCH_COMMENTS_OWNER FETCH_COMMENTS_REPO
fi

COMMENTS=""
if [[ -n "$COMMENTS_JSON" ]]; then
  if [[ ! -f "$COMMENTS_JSON" ]]; then
    printf 'babysit-readiness-gate: --comments-json file not found: %s\n' "$COMMENTS_JSON" >&2
    unproven bad-args 3
  fi
  COMMENTS="$(cat "$COMMENTS_JSON")" || {
    printf 'babysit-readiness-gate: could not read --comments-json file: %s\n' "$COMMENTS_JSON" >&2
    unproven comments-unreadable 4
  }
else
  COMMENTS="$(bash "$SCRIPT_DIR/fetch-all-pr-comments.sh" "$PR_NUMBER")" || {
    printf 'babysit-readiness-gate: could not fetch comments for PR %s (fetch-all-pr-comments error above).\n' "$PR_NUMBER" >&2
    if [[ -n "${FETCH_COMMENTS_OWNER:-}" && -n "${FETCH_COMMENTS_REPO:-}" ]]; then
      printf 'babysit-readiness-gate: target repo was %s/%s (from --repo or FETCH_COMMENTS_*).\n' \
        "$FETCH_COMMENTS_OWNER" "$FETCH_COMMENTS_REPO" >&2
    else
      printf 'babysit-readiness-gate: owner/repo is auto-derived from the current directory (%s) via gh repo view. Pass --repo owner/repo when cwd is not the target checkout, or export FETCH_COMMENTS_OWNER and FETCH_COMMENTS_REPO.\n' "$PWD" >&2
    fi
    unproven fetch-failed 4
  }
fi

printf '%s' "$COMMENTS" | jq -e '
  type == "array"
  and all(.[];
    type == "object"
    and has("author")
    and ((.author | type) as $author | $author == "string" or $author == "null")
    and (.body | type) == "string")
' >/dev/null || {
  printf 'babysit-readiness-gate: comment payload is not a JSON array of {author,body} objects (source: %s)\n' \
    "${COMMENTS_JSON:-live fetch}" >&2
  unproven comments-unreadable 4
}

SELF_LOGINS=()
if [[ -n "$SELF_CSV" ]]; then
  IFS=',' read -r -a SELF_LOGINS <<<"$SELF_CSV"
else
  if [[ -n "$EXTRA_SELF_CSV" ]]; then
    IFS=',' read -r -a SELF_LOGINS <<<"$EXTRA_SELF_CSV"
  fi
  personal_login="$(gh api user --jq .login 2>/dev/null | tr -d '\r')"
  [[ -n "$personal_login" ]] && SELF_LOGINS+=("$personal_login")
fi
if [[ ${#SELF_LOGINS[@]} -eq 0 ]]; then
  printf 'babysit-readiness-gate: cannot resolve self identity: the gh api user lookup returned no login (pass --self or --extra-self)\n' >&2
  unproven identity-unresolved 3
fi
SELF_JSON="$(printf '%s\n' "${SELF_LOGINS[@]}" | jq -nR '[inputs]')"

SEVERITY_WORDS_RE='CRITICAL|IMPORTANT|SUGGESTION'
SEVERITY_BADGE_RE='/badge/P[0-3]-'
SEVERITY_PLAIN_RE='\[P[0-3]\]'
CLASSIFY_CELL_RE='[|][^a-z0-9_|]*(valid|incorrect|uncertain)([ \t]*[^a-z0-9_ \t|][^|]*)?[ \t]*([|]|$)'
CLASSIFY_ROW_RE="^[[:space:]]*[|].*${CLASSIFY_CELL_RE}"

classify_rows() {
  awk -v pat="$CLASSIFY_ROW_RE" -v mode="$1" '
    {
      hit = (tolower($0) ~ pat)
      if (mode == "count") { n += hit } else if (!hit) { print }
    }
    END { if (mode == "count") print n + 0 }
  '
}

bodies_unreadable() {
  printf 'babysit-readiness-gate: could not read comment bodies (source: %s)\n' \
    "${COMMENTS_JSON:-live fetch}" >&2
  unproven comments-unreadable 4
}
bodies_where() {
  printf '%s' "$COMMENTS" | jq -r --argjson self "$SELF_JSON" \
    '.[] | select((.author as $a | $self | index($a)) '"$1"') | .body // ""'
}
non_self_bodies="$(bodies_where '| not')" || bodies_unreadable
self_bodies="$(bodies_where '')" || bodies_unreadable

self_source_bodies="$(printf '%s\n' "$self_bodies" | classify_rows strip)"
all_bodies="$non_self_bodies
$self_source_bodies"

sev_words=$(printf '%s\n' "$all_bodies" | grep -owE "$SEVERITY_WORDS_RE" | grep -c . || true)
sev_badges=$(printf '%s\n' "$all_bodies" | grep -oE "$SEVERITY_BADGE_RE" | grep -c . || true)
sev_plain=$(printf '%s\n' "$all_bodies" | grep -oE "$SEVERITY_PLAIN_RE" | grep -c . || true)
classified=$(printf '%s\n' "$self_bodies" | classify_rows count)
sev_words=${sev_words//[^0-9]/}
sev_badges=${sev_badges//[^0-9]/}
sev_plain=${sev_plain//[^0-9]/}
classified=${classified//[^0-9]/}
findings=$((${sev_words:-0} + ${sev_badges:-0} + ${sev_plain:-0}))
classified=${classified:-0}

((classified > findings)) && classified="$findings"

PY_SCRIPTS="$SCRIPT_DIR/../skills/babysit-prs/scripts"
if [[ "${BABYSIT_READINESS_BASH_ONLY:-}" != 1 && -f "$PY_SCRIPTS/babysit-python.sh" ]]; then
  # shellcheck source=../skills/babysit-prs/scripts/babysit-python.sh
  . "$PY_SCRIPTS/babysit-python.sh"
  self_csv_joined="$(
    IFS=,
    printf '%s' "${SELF_LOGINS[*]}"
  )"
  if [[ -n "$COMMENTS_JSON" ]]; then
    py_source=(--comments-json "$COMMENTS_JSON")
  else
    py_source=(--pr "$PR_NUMBER")
  fi
  py_out="$(babysit_python "$PY_SCRIPTS/babysit_findings.py" \
    "${py_source[@]}" --self "$self_csv_joined" 2>/dev/null)"
  if [[ "$py_out" =~ findings=([0-9]+)[[:space:]]+classified=([0-9]+) ]]; then
    findings="${BASH_REMATCH[1]}"
    classified="${BASH_REMATCH[2]}"
  fi
fi

unticked=0
checklist_state="n/a"
if [[ -n "$CHECKLIST" ]]; then
  if [[ ! -f "$CHECKLIST" ]]; then
    printf 'babysit-readiness-gate: --checklist file not found: %s\n' "$CHECKLIST" >&2
    unproven bad-args 3
  fi
  grep_status=0
  unticked=$(grep -cE '^[[:space:]]*-[[:space:]]\[[[:space:]]\]' "$CHECKLIST") || grep_status=$?
  if ((grep_status > 1)); then
    printf 'babysit-readiness-gate: --checklist could not be read: %s\n' "$CHECKLIST" >&2
    unproven checklist-unreadable 4
  fi
  unticked=${unticked//[^0-9]/}
  unticked=${unticked:-0}
  ((unticked == 0)) && checklist_state="clean" || checklist_state="incomplete"
fi

blocked=""
if ((findings > 0 && classified < findings)); then
  blocked=under-decomposed
elif ((unticked > 0)); then
  blocked=checklist-incomplete
fi
if [[ -n "$blocked" ]]; then
  printf 'READINESS_BLOCKED reason=%s findings=%s classified=%s unticked=%s\n' \
    "$blocked" "$findings" "$classified" "$unticked"
  exit 1
fi

printf 'READINESS_OK findings=%s classified=%s checklist=%s\n' \
  "$findings" "$classified" "$checklist_state"
exit 0
