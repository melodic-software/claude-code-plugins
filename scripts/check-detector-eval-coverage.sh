#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

PAIRS_DEFAULT=(
  "plugins/harness-config/skills/audit-permission-grants/scripts/permission-rule-check.sh|plugins/harness-config/skills/audit-permission-grants/evals/evals.json|P[0-9]+[a-z]?"
)

QUALIFYING_ID_ERE='[A-Z][A-Za-z]*[0-9]+[A-Za-z0-9]*'

mode="${1:-discover}"
if [[ "$#" -gt 1 || ("$mode" != discover && "$mode" != --check) ]]; then
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "check-detector-eval-coverage: jq not found; cannot read any eval suite" >&2
  exit 2
fi
if ! command -v shfmt >/dev/null 2>&1; then
  echo "check-detector-eval-coverage: shfmt not found; cannot read emit call sites (pin mvdan/sh v3.14.1, shfmt --to-json --language-dialect bash)" >&2
  exit 2
fi
shfmt_version="$(shfmt --version 2>/dev/null || true)"
shfmt_norm="${shfmt_version#v}"
IFS=. read -r shfmt_maj shfmt_min _ <<<"${shfmt_norm%%[^0-9.]*}"
if [[ -z "${shfmt_maj:-}" || -z "${shfmt_min:-}" ]] || ((shfmt_maj < 3 || (shfmt_maj == 3 && shfmt_min < 13))); then
  echo "check-detector-eval-coverage: shfmt ${shfmt_version:-unknown} is older than v3.13.0 and drops a call after a # that bash keeps; CI pins mvdan/sh v3.14.1" >&2
  exit 2
fi

EMIT_SCAN_JQ=""
read -r -d '' EMIT_SCAN_JQ <<'JQ'
def static:
  if type != "object" or ((.Parts // null) | type) != "array" or (.Parts | length) != 1 then null
  else
    .Parts[0] as $p
    | if $p.Type == "Lit" then $p.Value
      elif $p.Type == "SglQuoted" then $p.Value
      elif $p.Type == "DblQuoted"
        and (($p.Parts // []) | length) == 1
        and ($p.Parts[0].Type == "Lit")
      then $p.Parts[0].Value
      else null
      end
  end;

# One word that names an emitter: `emit` or `emit<suffix>` with no whitespace, so
# a quoted `eval "emit error P9"` body is text, not a name.
def is_emit_name: test("^emit[^[:space:]]*$");

def pure_param_at_star:
  type == "object"
  and .Type == "ParamExp"
  and (.Param.Value == "@" or .Param.Value == "*")
  and (.Exp == null)
  and (.Repl == null)
  and (.Length == null)
  and (.Index == null)
  and (.Slice == null)
  and (.Excl != true);

def is_forward:
  ((.Parts // null) | type) == "array" and (.Parts | length) == 1 and (
    (.Parts[0] | pure_param_at_star)
    or (
      .Parts[0].Type == "DblQuoted"
      and ((.Parts[0].Parts // []) | length) == 1
      and (.Parts[0].Parts[0] | pure_param_at_star)
    )
  );

# The words of a call (after the command word) end in a forwarder that stands in
# the severity or the id: `emit "$@"`, `emit error "$@"`. A word after the
# forwarder (`emit error "$@" P1`) leaves the id computed, not forwarded.
def forwards:
  (length == 1 and (.[0] | is_forward)) or (length == 2 and (.[1] | is_forward));

def emit_words:
  . as $c
  | ($c.Args[0] | static) as $w0
  | ($c.Args[1] | static) as $w1
  | if (($w0 == "command") or ($w0 == "builtin") or ($w0 == "exec") or ($w0 == "nohup") or ($w0 == "eval"))
      and ($w1 != null)
      and ($w1 | is_emit_name)
    then $c.Args[1:]
    else $c.Args
    end;

# A wrapper the walk does not follow whose LATER word names an emitter
# (`command -p emit ...`, `env FOO=1 emit ...`, `xargs emit ...`). emit_words
# handles the words it shifts; this finds the rest, so they count as candidates
# and surface as UNRESOLVED instead of vanishing. Not a call: a lookup (`command
# -v emit`, `-pv`, an option before the name), a call with no arguments, and a
# forwarder, the same exclusions the main walk applies.
def hidden_wrapped_emit:
  (.Args[0] | static) as $w0
  | if ($w0 == "command" or $w0 == "builtin" or $w0 == "exec" or $w0 == "nohup"
        or $w0 == "eval" or $w0 == "env" or $w0 == "xargs")
    then
      [.Args[1:][] | static] as $ws
      | ($ws | map(. != null and is_emit_name) | index(true)) as $i
      | if $i == null then null
        else
          (.Args[1:][$i + 1:]) as $after
          | if ($w0 == "command" and ($ws[:$i] | any(. != null and test("^-[pvV]*[vV][pvV]*$"))))
              or ($after | length) == 0
              or ($after | forwards)
            then null
            else $w0 + " ... " + $ws[$i]
            end
        end
    else null
    end;

[
  .. | objects | select(.Type == "CallExpr" and ((.Args // []) | length) > 0)
] as $calls
| reduce $calls[] as $c (
    {candidates: 0, lines: []};
    ($c | emit_words) as $args
    | ($args[0] | static) as $cmd
    | if ($cmd == null) or (($cmd | is_emit_name) | not) then
        ($c | hidden_wrapped_emit) as $hidden
        | if $hidden == null then .
          else
            .candidates += 1
            | .lines += ["UNRESOLVED line " + ($c.Pos.Line | tostring) + ": " + $hidden]
          end
      else
        ($args[1:] | map(select(. != null))) as $rest
        | if ($rest | length) == 0 then .
          elif ($rest | forwards) then .
          else
            .candidates += 1
            | ($rest[0] | static) as $sev
            | ($rest[1] // null | static) as $id
            | if ($sev != null and $id != null
                  and ($sev | test("^[A-Za-z][A-Za-z0-9_]*$"))
                  and ($id | test("\\A(" + $idre + ")\\z")))
              then .lines += ["ID " + $id]
              else .lines += ["UNRESOLVED line " + ($c.Pos.Line | tostring) + ": " + $cmd]
              end
          end
      end
  )
| .lines[], "CANDIDATES \(.candidates)"
JQ

scan_emits() {
  local file="$1" idre="$2" outfile="$3"
  # pipefail makes the pipeline fail when either shfmt or jq does.
  # shellcheck disable=SC2094  # "$file" is only read; "$outfile" is a separate temp file
  shfmt --language-dialect bash --filename "$(basename -- "$file")" --to-json <"$file" 2>/dev/null |
    jq -r --arg idre "$idre" "$EMIT_SCAN_JQ" >"$outfile"
}

COVERAGE_AWK=""
read -r -d '' COVERAGE_AWK <<'AWK'
BEGIN {
  apos = sprintf("%c", 39)
  cue = "(^|[^a-z0-9])(not|never|without|excludes?|omits?|ignores?|neither|nor|no)([^a-z0-9]|$)"
  ncue = "[a-z]n" apos "t([^a-z0-9]|$)"
}
{
  rest = $0
  done = ""
  while (match(rest, idre)) {
    s = RSTART
    l = RLENGTH
    before = (s > 1) ? substr(rest, s - 1, 1) : substr(done, length(done), 1)
    after = substr(rest, s + l, 1)
    id = substr(rest, s, l)
    if ((before == "" || before !~ /[A-Za-z0-9_]/) && (after == "" || after !~ /[A-Za-z0-9_]/)) {
      print "NAMED " id
      clause = done substr(rest, 1, s - 1)
      # The id's OWN predicate: back to the previous clause break (`,` included,
      # which `must be flagged as P4` needs), then the two words immediately
      # before the id. A cue anywhere else in the sentence -- "A rule without a
      # scope suffix must be flagged as P4" -- disclaims nothing.
      if (match(clause, /^.*[.;:,]/)) clause = substr(clause, RSTART + RLENGTH)
      w = clause
      sub(/[[:space:]]+$/, "", w)
      win = ""
      cnt = 0
      while (cnt < 2 && match(w, /[^[:space:]]+$/)) {
        win = substr(w, RSTART) " " win
        w = substr(w, 1, RSTART - 1)
        sub(/[[:space:]]+$/, "", w)
        cnt++
      }
      win = tolower(win)
      if (win ~ cue || win ~ ncue) print "DISCLAIMED " id
      else print "COVERING " id
    }
    done = done substr(rest, 1, s + l - 1)
    rest = substr(rest, s + l)
  }
}
AWK

pairs=()
if [[ -n "${DETECTOR_EVAL_COVERAGE_PAIRS:-}" ]]; then
  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] && pairs+=("$line")
  done <<<"$DETECTOR_EVAL_COVERAGE_PAIRS"
else
  pairs=("${PAIRS_DEFAULT[@]}")
fi

if [[ "${#pairs[@]}" -eq 0 ]]; then
  echo "check-detector-eval-coverage: no registered pairs; there is nothing this run could have inspected" >&2
  exit 2
fi

tmp_dir="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp_dir"' EXIT
emitted_tmp="$tmp_dir/emitted"
named_tmp="$tmp_dir/named"
covering_tmp="$tmp_dir/covering"
disclaimed_tmp="$tmp_dir/disclaimed"
scan_tmp="$tmp_dir/scan"
strings_tmp="$tmp_dir/strings"
report_tmp="$tmp_dir/report"
advisory_tmp="$tmp_dir/advisory"
: >"$report_tmp"
: >"$advisory_tmp"

errors=0
total_emitted=0
total_named=0
advisories=0

qualifying_detectors() {
  local evals_path skill script count
  for evals_path in plugins/*/skills/*/evals/evals.json; do
    [[ -f "$evals_path" ]] || continue
    skill="${evals_path%/evals/evals.json}"
    for script in "$skill"/scripts/*.sh; do
      [[ -f "$script" && "$script" != *.test.sh ]] || continue
      if scan_emits "$script" "$QUALIFYING_ID_ERE" "$scan_tmp"; then
        count="$(sed -n 's/^ID //p' "$scan_tmp" | sort -u | grep -c .)" || count=0
      else
        count=0
      fi
      [[ "$count" -ge 2 ]] && printf '%s\n' "$script"
    done
  done
}

for row in "${pairs[@]}"; do
  detector="${row%%|*}"
  rest="${row#*|}"
  evals="${rest%%|*}"
  id_re="${rest#*|}"

  if [[ -z "$detector" || -z "$evals" || -z "$id_re" || "$evals" == "$rest" ]]; then
    echo "check-detector-eval-coverage: malformed registry row: $row" >&2
    exit 2
  fi
  if [[ ! -r "$detector" ]]; then
    echo "check-detector-eval-coverage: detector not readable: $detector" >&2
    exit 2
  fi
  if [[ ! -r "$evals" ]]; then
    echo "check-detector-eval-coverage: eval suite not readable: $evals" >&2
    exit 2
  fi

  if ! jq -e . "$evals" >/dev/null 2>&1; then
    echo "check-detector-eval-coverage: $evals is not valid JSON; the eval-named id set cannot be read" >&2
    exit 2
  fi
  if ! jq -e 'type == "object" and (.evals | type) == "array" and (.evals | length) > 0 and ([.evals[] | type] | all(. == "object"))' \
    "$evals" >/dev/null 2>&1; then
    echo "check-detector-eval-coverage: $evals is not a suite this gate can read coverage out of; it must be a JSON object whose 'evals' is a non-empty array of objects" >&2
    exit 2
  fi

  if ! scan_emits "$detector" "$id_re" "$scan_tmp"; then
    echo "check-detector-eval-coverage: $detector has an emit call site shfmt could not parse; the emitted id set cannot be read" >&2
    exit 2
  fi
  sed -n 's/^ID //p' "$scan_tmp" | sort -u >"$emitted_tmp"
  candidate_count="$(sed -n 's/^CANDIDATES //p' "$scan_tmp" | tail -n 1)"
  resolved_count="$(grep -c '^ID ' "$scan_tmp")"

  if [[ "$candidate_count" != "$resolved_count" ]]; then
    {
      echo "check-detector-eval-coverage: $detector has $candidate_count emit call site(s) but only $resolved_count resolved to a check id under /${id_re}/; the emitted id set is incomplete, so no verdict is available"
      sed -n 's/^UNRESOLVED /  unparsed: /p' "$scan_tmp"
    } >&2
    exit 2
  fi

  jq -r '.evals[] | (.expected_output, .expectations) | .. | strings | @json' "$evals" >"$strings_tmp"
  awk -v idre="$id_re" "$COVERAGE_AWK" "$strings_tmp" >"$scan_tmp"
  sed -n 's/^NAMED //p' "$scan_tmp" | sort -u >"$named_tmp"
  sed -n 's/^COVERING //p' "$scan_tmp" | sort -u >"$covering_tmp"
  sed -n 's/^DISCLAIMED //p' "$scan_tmp" | sort -u >"$disclaimed_tmp"

  emitted_count="$(grep -c . "$emitted_tmp")"
  named_count="$(grep -c . "$named_tmp")"

  if [[ "$emitted_count" -eq 0 ]]; then
    echo "check-detector-eval-coverage: no check ids extracted from $detector with /${id_re}/; the extraction, not the eval suite, is broken" >&2
    exit 2
  fi

  total_emitted=$((total_emitted + emitted_count))
  total_named=$((total_named + named_count))

  if [[ "$mode" == "discover" ]]; then
    {
      echo "$detector"
      echo "  evals:          $evals"
      echo "  id pattern:     $id_re"
      echo "  emitted ids:    $emitted_count"
      echo "  eval-named ids: $named_count"
      while IFS= read -r id; do
        if grep -Fxq -- "$id" "$covering_tmp"; then
          printf '    COVERED    %s\n' "$id"
        elif grep -Fxq -- "$id" "$disclaimed_tmp"; then
          advisories=$((advisories + 1))
          printf '    DISCLAIMED %s\n' "$id"
        else
          printf '    UNCOVERED  %s\n' "$id"
        fi
      done <"$emitted_tmp"
      while IFS= read -r id; do
        grep -Fxq -- "$id" "$emitted_tmp" || printf '    UNEMITTABLE %s\n' "$id"
      done <"$named_tmp"
    } >>"$report_tmp"
  else
    while IFS= read -r id; do
      if grep -Fxq -- "$id" "$covering_tmp"; then
        continue
      fi
      if grep -Fxq -- "$id" "$disclaimed_tmp"; then
        printf 'DISCLAIMED CHECK ID: %s is emitted by %s and named in %s only inside a negated clause, so nothing there exercises it (advisory, not a finding)\n' \
          "$id" "$detector" "$evals" >>"$advisory_tmp"
        advisories=$((advisories + 1))
        continue
      fi
      echo "UNCOVERED CHECK ID: $id is emitted by $detector and covered by no case in $evals" >&2
      errors=$((errors + 1))
    done <"$emitted_tmp"

    while IFS= read -r id; do
      if ! grep -Fxq -- "$id" "$emitted_tmp"; then
        echo "UNEMITTABLE CHECK ID: $id is named in $evals and $detector cannot emit it" >&2
        errors=$((errors + 1))
      fi
    done <"$named_tmp"
  fi
done

registered_detectors=""
for row in "${pairs[@]}"; do
  registered_detectors+="${row%%|*}"$'\n'
done
while IFS= read -r candidate; do
  [[ -n "$candidate" ]] || continue
  if ! grep -Fxq -- "$candidate" <<<"$registered_detectors"; then
    if [[ "$mode" == "discover" ]]; then
      printf 'UNREGISTERED PAIR: %s emits check ids beside an eval suite and has no registry row\n' \
        "$candidate" >>"$report_tmp"
    else
      echo "UNREGISTERED PAIR: $candidate emits check ids beside an eval suite and has no registry row, so nothing compares them; add a row" >&2
      errors=$((errors + 1))
    fi
  fi
done < <(qualifying_detectors)

denominator="${#pairs[@]} pair(s), $total_emitted emitted id(s), $total_named eval-named id(s)"
if [[ "$advisories" -gt 0 ]]; then
  denominator+=", $advisories disclaimed-only id(s)"
fi

if [[ "$mode" == "discover" ]]; then
  cat "$report_tmp"
  echo "check-detector-eval-coverage: $denominator"
  exit 0
fi

cat "$advisory_tmp"

if [[ "$errors" -gt 0 ]]; then
  echo "check-detector-eval-coverage: FAILED — $errors gap(s) across $denominator" >&2
  exit 1
fi

if [[ "$advisories" -gt 0 ]]; then
  echo "check-detector-eval-coverage: passed with advisories — every emitted check id is named by an eval case ($advisories only inside a negated clause, which exercises nothing) and every eval-named id is emittable ($denominator)"
  exit 0
fi

echo "check-detector-eval-coverage: passed — every emitted check id is covered by an eval case and every eval-named id is emittable ($denominator)"
exit 0
