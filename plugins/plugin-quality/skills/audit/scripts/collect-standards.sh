#!/usr/bin/env bash
# Standards-alignment collector for one audited component.
#
# Resolves the consumer convention home with resolve-convention-home.sh.
# Exit 1 from that resolver is the unresolved-home fallback: this script
# names the five topics and infers nothing. Exit 3 is forwarded. A resolved
# home runs a closed probe set and cites the convention line plus the
# component line when a probe disagrees. invocation-mode, untrusted-content and
# windows-path-emit report `finding`. seam-phrasing grades prose (the gate
# belongs where an invocation is instructed, not where one is described), so
# it reports `candidate` leads that do not change the exit; the auditor reads
# each against the convention before recording a finding.
#
# Exit: 0 no disagreement (including unresolved-home), 1 one or more
# findings or a missing citation basis, 2 usage, 3 the resolver FAILed.
#
#   collect-standards.sh --component <file> --root <repo>
set -uo pipefail

usage() {
  cat <<'EOF'
collect-standards.sh — check one component against its convention home.

Usage:
  collect-standards.sh --component <file> --root <repo>

Exit: 0 aligned, not-applicable, or convention-home unresolved (fallback
stated, nothing inferred); 1 a disagreement or a citation basis that is
gone; 2 usage; 3 resolve-convention-home.sh FAILed.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../lib/resolve-convention-home.sh"

COMPONENT=""
ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --component)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --component needs a file" >&2
      exit 2
    fi
    COMPONENT="$2"
    shift 2
    ;;
  --root)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --root needs a directory" >&2
      exit 2
    fi
    ROOT="$2"
    shift 2
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -z "$COMPONENT" || -z "$ROOT" ]]; then
  echo "ERROR: --component and --root are required" >&2
  usage >&2
  exit 2
fi
if [[ ! -f "$COMPONENT" ]]; then
  echo "ERROR: component not found: $COMPONENT" >&2
  exit 2
fi
if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: root not found: $ROOT" >&2
  exit 2
fi
if [[ ! -f "$RESOLVER" ]]; then
  echo "ERROR: resolver missing: $RESOLVER" >&2
  exit 2
fi

resolver_err="$(mktemp)"
home_out="$(bash "$RESOLVER" --root "$ROOT" 2>"$resolver_err")"
home_rc=$?
# The resolver writes duplicate: notices to stderr. Keep them off this
# script's stdout so the report stays one record per line.
if [[ -s "$resolver_err" ]]; then
  cat "$resolver_err" >&2
fi
rm -f "$resolver_err"

# 1 no pointer, 4 declined, 5 not applicable (home, ancestor of home, or outside git): no home binds, so grade from the topic docs.
if [[ "$home_rc" -eq 1 || "$home_rc" -eq 4 || "$home_rc" -eq 5 ]]; then
  echo "convention-home: unresolved"
  echo "fallback: convention home unresolved; grade invocation-mode, seam-phrasing, untrusted-content, windows-path-emit, and hook-budget from those topic docs once a home is configured. Nothing was inferred."
  echo "probes: skipped"
  exit 0
fi
if [[ "$home_rc" -eq 3 ]]; then
  echo "convention-home: invalid"
  exit 3
fi
if [[ "$home_rc" -ne 0 ]]; then
  echo "ERROR: resolver exit $home_rc" >&2
  exit 2
fi

echo "convention-home: $home_out"
findings=0

cite() {
  local file="$1" needle="$2" line
  [[ -f "$file" ]] || return 0
  line="$(grep -n -F "$needle" "$file" | head -n 1 | cut -d: -f1)"
  printf '%s' "$line"
}

emit_probe() {
  # name status convention component note
  printf 'probe: %s status=%s convention=%s component=%s note=%s\n' \
    "$1" "$2" "$3" "$4" "$5"
  if [[ "$2" == "finding" || "$2" == "basis-missing" ]]; then
    findings=$((findings + 1))
  fi
}

# topic_rel <topic> - the topic's contract, relative to the root: the
# marketplace contract folder docs/contracts/<topic>/README.md when present,
# else <home>/<topic>/README.md (a convention home that still holds the topic).
topic_rel() {
  if [[ -f "$ROOT/docs/contracts/$1/README.md" ]]; then
    printf 'docs/contracts/%s/README.md' "$1"
  else
    printf '%s/%s/README.md' "$home_out" "$1"
  fi
}

# topic_ready <topic> [<needle>] - sets t_rel, t_file and, given a needle,
# t_cite (the needle's line in the topic). Emits topic-absent or basis-missing
# and returns 1 when the topic cannot be graded.
topic_ready() {
  t_rel="$(topic_rel "$1")"
  t_file="$ROOT/$t_rel"
  if [[ ! -f "$t_file" ]]; then
    emit_probe "$1" topic-absent - - "convention file absent"
    return 1
  fi
  [[ $# -ge 2 ]] || return 0
  t_cite="$(cite "$t_file" "$2")"
  if [[ -z "$t_cite" ]]; then
    emit_probe "$1" basis-missing "$t_rel" - "citation sentence absent"
    return 1
  fi
}

# --- invocation-mode -------------------------------------------------------
if topic_ready invocation-mode "The key is written"; then
  if [[ "$(basename "$COMPONENT")" != "SKILL.md" ]]; then
    emit_probe invocation-mode not-applicable "$t_rel:$t_cite" - "not a skill file"
  elif grep -E -q '^disable-model-invocation:' \
    < <(awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f==1{print} f>=2{exit}' "$COMPONENT"); then
    emit_probe invocation-mode aligned "$t_rel:$t_cite" - "explicit disable-model-invocation"
  else
    emit_probe invocation-mode finding "$t_rel:$t_cite" "$COMPONENT:1" "disable-model-invocation key absent"
  fi
fi

# --- seam-phrasing ---------------------------------------------------------
# Only an optional cross-plugin reference needs the gate; a sibling skill in
# the owning plugin or a declared dependency does not.
exempt_plugins() {
  local dir
  dir="$(cd "$(dirname "$COMPONENT")" && pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude-plugin/plugin.json" ]]; then
      awk '
        function str(s) { if (match(s, /:[[:space:]]*"[^"]+"/)) { s = substr(s, RSTART, RLENGTH); gsub(/^:[[:space:]]*"|"$/, "", s); return s } }
        !own && /"name"[[:space:]]*:/ { own = 1; print str($0); next }
        /"dependencies"[[:space:]]*:/ { dep = 1 }
        dep && /"name"[[:space:]]*:/ { print str($0) }
        dep && /^[[:space:]]*"[^"]+",?[[:space:]]*$/ { v = $0; gsub(/^[[:space:]]*"|",?[[:space:]]*$/, "", v); print v }
        dep && /]/ { dep = 0 }
      ' "$dir/.claude-plugin/plugin.json"
      return
    fi
    dir="$(dirname "$dir")"
  done
}
if topic_ready seam-phrasing "explicit installed-ness"; then
  # Exempt: the owning plugin and any manifest `dependencies` entry, one name
  # per line from the nearest plugin.json above the component.
  exempt="|$(exempt_plugins | paste -sd'|' -)|"
  # shellcheck disable=SC2016 # the backticks are the invocation token, not an expansion
  seam_out="$(
    awk -v comp="$COMPONENT" -v conv="$t_rel:$t_cite" -v exempt="$exempt" '
      { line[NR] = $0 }
      # An invocation token is `/ns:skill` with optional arguments, or bare `ns:skill`.
      function cross_plugin(s,    tok, ns) {
        while (match(s, /`(\/[A-Za-z0-9][A-Za-z0-9-]*:[A-Za-z0-9][A-Za-z0-9-]*([ ][^`]*)?|[A-Za-z0-9][A-Za-z0-9-]*:[A-Za-z0-9][A-Za-z0-9-]*)`/)) {
          tok = substr(s, RSTART + 1, RLENGTH - 2)
          sub(/^\//, "", tok)
          ns = tok
          sub(/:.*/, "", ns)
          if (index(exempt, "|" ns "|") == 0) return 1
          s = substr(s, RSTART + RLENGTH)
        }
        return 0
      }
      END {
        seen = 0
        for (i = 1; i <= NR; i++) {
          if (line[i] ~ /plugin install/ || line[i] ~ /marketplace add/) continue
          if (!cross_plugin(line[i])) continue
          seen++
          window = line[i]
          if (i + 1 <= NR) window = window "\n" line[i + 1]
          if (i + 2 <= NR) window = window "\n" line[i + 2]
          if (window ~ /installed/ || window ~ /Absent:/ || window ~ /fallback/) continue
          printf "probe: seam-phrasing status=candidate convention=%s component=%s:%d note=no gate or fallback within three lines; confirm the line instructs the invocation\n", conv, comp, i
        }
        print "seam-invocations=" seen
      }
    ' "$COMPONENT"
  )"
  seam_count="${seam_out##*seam-invocations=}"
  seam_hits="$(printf '%s\n' "$seam_out" | grep 'status=candidate' || true)"
  if [[ -n "$seam_hits" ]]; then
    printf '%s\n' "$seam_hits"
  elif [[ "$seam_count" -gt 0 ]]; then
    emit_probe seam-phrasing aligned "$t_rel:$t_cite" - "every cross-plugin invocation is gated or an install recipe"
  else
    emit_probe seam-phrasing not-applicable "$t_rel:$t_cite" - "no optional cross-plugin invocation"
  fi
fi

# --- untrusted-content -----------------------------------------------------
# The convention grades file for file on `never instructions to you`. An ingest
# signal in the frontmatter (a `tools:` list) declares a capability, not a read.
if topic_ready untrusted-content "DATA, never instructions"; then
  ingest_line="$(awk '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm && /^---[[:space:]]*$/ { fm = 0; next }
    !fm && /WebFetch|curl |gh issue|gh pr|gh api/ { print NR; exit } # prereq-ok: a pattern matched against the audited file, not a command this script runs
  ' "$COMPONENT")"
  if [[ -z "$ingest_line" ]]; then
    emit_probe untrusted-content not-applicable "$t_rel:$t_cite" - "no ingest signal"
  elif grep -F -q 'never instructions to you' "$COMPONENT"; then
    emit_probe untrusted-content aligned "$t_rel:$t_cite" - "framing spine present"
  else
    emit_probe untrusted-content finding "$t_rel:$t_cite" "$COMPONENT:$ingest_line" "ingest without the framing spine"
  fi
fi

# --- windows-path-emit -----------------------------------------------------
if topic_ready windows-path-emit "path-conversion suppressor"; then
  export_line="$(grep -n -E '(export|declare[[:space:]]+-x|typeset[[:space:]]+-x)[[:space:]]+(MSYS_NO_PATHCONV|MSYS2_ARG_CONV_EXCL)' "$COMPONENT" | head -n 1 | cut -d: -f1 || true)"
  if [[ -n "$export_line" ]]; then
    emit_probe windows-path-emit finding "$t_rel:$t_cite" "$COMPONENT:$export_line" "exported path-conversion suppressor"
  else
    emit_probe windows-path-emit not-graded "$t_rel:$t_cite" - "only an exported path-conversion suppressor is graded; read the component for a POSIX path handed to a Windows-native process"
  fi
fi

# --- hook-budget -----------------------------------------------------------
if topic_ready hook-budget; then
  emit_probe hook-budget not-applicable "$t_rel" - "cost is measured, not grep-graded; the hook lens owns it"
fi

if [[ "$findings" -gt 0 ]]; then
  echo "status: findings=$findings"
  exit 1
fi
echo "status: clean"
exit 0
