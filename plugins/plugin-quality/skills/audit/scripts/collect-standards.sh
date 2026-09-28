#!/usr/bin/env bash
# Standards-alignment collector for one audited component.
#
# Resolves the consumer convention home with resolve-convention-home.sh.
# Exit 1 from that resolver is the unresolved-home fallback: this script
# names the five topics and infers nothing. Exit 3 is forwarded. A resolved
# home runs a closed probe set and cites the convention line plus the
# component line when a probe disagrees.
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

if [[ "$home_rc" -eq 1 ]]; then
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
HOME_DIR="$ROOT/$home_out"
findings=0

cite() {
  local file="$1" needle="$2" line
  if [[ ! -f "$file" ]]; then
    printf ''
    return
  fi
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

topic_file() {
  printf '%s/%s/README.md' "$HOME_DIR" "$1"
}

# --- invocation-mode -------------------------------------------------------
inv_file="$(topic_file invocation-mode)"
inv_cite="$(cite "$inv_file" "The key is written")"
base="$(basename "$COMPONENT")"
if [[ ! -f "$inv_file" ]]; then
  emit_probe invocation-mode topic-absent - - "convention file absent"
elif [[ -z "$inv_cite" ]]; then
  emit_probe invocation-mode basis-missing "$home_out/invocation-mode/README.md" - "citation sentence absent"
elif [[ "$base" != "SKILL.md" ]]; then
  emit_probe invocation-mode not-applicable "$home_out/invocation-mode/README.md:$inv_cite" - "not a skill file"
else
  if awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f==1{print} f>=2{exit}' "$COMPONENT" |
    grep -E -q '^disable-model-invocation:'; then
    emit_probe invocation-mode aligned "$home_out/invocation-mode/README.md:$inv_cite" - "explicit disable-model-invocation"
  else
    emit_probe invocation-mode finding "$home_out/invocation-mode/README.md:$inv_cite" "$COMPONENT:1" "disable-model-invocation key absent"
  fi
fi

# --- seam-phrasing ---------------------------------------------------------
seam_file="$(topic_file seam-phrasing)"
seam_cite="$(cite "$seam_file" "explicit installed-ness")"
if [[ ! -f "$seam_file" ]]; then
  emit_probe seam-phrasing topic-absent - - "convention file absent"
elif [[ -z "$seam_cite" ]]; then
  emit_probe seam-phrasing basis-missing "$home_out/seam-phrasing/README.md" - "citation sentence absent"
else
  seam_hits="$(
    awk -v comp="$COMPONENT" -v conv="$home_out/seam-phrasing/README.md:$seam_cite" '
      {
        line[NR] = $0
      }
      END {
        hits = 0
        for (i = 1; i <= NR; i++) {
          if (line[i] ~ /plugin install/ || line[i] ~ /marketplace add/) continue
          if (line[i] ~ /`\/?[A-Za-z0-9][A-Za-z0-9-]*:[A-Za-z0-9][A-Za-z0-9-]*`/) {
            window = line[i]
            if (i + 1 <= NR) window = window "\n" line[i + 1]
            if (i + 2 <= NR) window = window "\n" line[i + 2]
            if (window ~ /installed/ || window ~ /Absent:/ || window ~ /fallback/) continue
            hits++
            printf "probe: seam-phrasing status=finding convention=%s component=%s:%d note=invocation without installed-ness gate or adjacent fallback\n", conv, comp, i
          }
        }
        if (hits == 0) print "seam-clear"
      }
    ' "$COMPONENT"
  )"
  if [[ "$seam_hits" == "seam-clear" ]]; then
    # Distinguish "no invocations" from "all gated" by a second scan.
    # shellcheck disable=SC2016 # the backticks are the invocation token, not an expansion
    if grep -E -q '`/?[A-Za-z0-9][A-Za-z0-9-]*:[A-Za-z0-9][A-Za-z0-9-]*`' "$COMPONENT"; then
      emit_probe seam-phrasing aligned "$home_out/seam-phrasing/README.md:$seam_cite" - "every invocation is gated or an install recipe"
    else
      emit_probe seam-phrasing not-applicable "$home_out/seam-phrasing/README.md:$seam_cite" - "no cross-plugin invocation"
    fi
  else
    printf '%s\n' "$seam_hits"
    findings=$((findings + $(printf '%s\n' "$seam_hits" | grep -c 'status=finding' || true)))
  fi
fi

# --- untrusted-content -----------------------------------------------------
unc_file="$(topic_file untrusted-content)"
unc_cite="$(cite "$unc_file" "DATA, never instructions")"
if [[ ! -f "$unc_file" ]]; then
  emit_probe untrusted-content topic-absent - - "convention file absent"
elif [[ -z "$unc_cite" ]]; then
  emit_probe untrusted-content basis-missing "$home_out/untrusted-content/README.md" - "citation sentence absent"
elif ! grep -E -q 'WebFetch|curl |gh issue|gh pr|gh api' "$COMPONENT"; then
  emit_probe untrusted-content not-applicable "$home_out/untrusted-content/README.md:$unc_cite" - "no ingest signal"
elif grep -F -q 'DATA, never instructions' "$COMPONENT"; then
  emit_probe untrusted-content aligned "$home_out/untrusted-content/README.md:$unc_cite" - "framing spine present"
else
  ingest_line="$(grep -n -E 'WebFetch|curl |gh issue|gh pr|gh api' "$COMPONENT" | head -n 1 | cut -d: -f1)"
  emit_probe untrusted-content finding "$home_out/untrusted-content/README.md:$unc_cite" "$COMPONENT:$ingest_line" "ingest without the framing spine"
fi

# --- windows-path-emit -----------------------------------------------------
win_file="$(topic_file windows-path-emit)"
win_cite="$(cite "$win_file" "path-conversion suppressor")"
if [[ ! -f "$win_file" ]]; then
  emit_probe windows-path-emit topic-absent - - "convention file absent"
elif [[ -z "$win_cite" ]]; then
  emit_probe windows-path-emit basis-missing "$home_out/windows-path-emit/README.md" - "citation sentence absent"
else
  export_line="$(grep -n -E 'export[[:space:]]+(MSYS_NO_PATHCONV|MSYS2_ARG_CONV_EXCL)|declare[[:space:]]+-x[[:space:]]+(MSYS_NO_PATHCONV|MSYS2_ARG_CONV_EXCL)|typeset[[:space:]]+-x[[:space:]]+(MSYS_NO_PATHCONV|MSYS2_ARG_CONV_EXCL)' "$COMPONENT" | head -n 1 | cut -d: -f1 || true)"
  if [[ -n "$export_line" ]]; then
    emit_probe windows-path-emit finding "$home_out/windows-path-emit/README.md:$win_cite" "$COMPONENT:$export_line" "exported path-conversion suppressor"
  else
    emit_probe windows-path-emit not-applicable "$home_out/windows-path-emit/README.md:$win_cite" - "no exported path-conversion suppressor"
  fi
fi

# --- hook-budget -----------------------------------------------------------
hook_file="$(topic_file hook-budget)"
if [[ ! -f "$hook_file" ]]; then
  emit_probe hook-budget topic-absent - - "convention file absent"
else
  emit_probe hook-budget not-applicable "$home_out/hook-budget/README.md" - "cost is measured, not grep-graded; the hook lens owns it"
fi

if [[ "$findings" -gt 0 ]]; then
  echo "status: findings=$findings"
  exit 1
fi
echo "status: clean"
exit 0
