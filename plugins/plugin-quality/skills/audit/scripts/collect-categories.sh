#!/usr/bin/env bash
# Grade an audit-notes ledger for the three named categories and the two
# seams that ride with them (standards alignment, emitted-finding samples).
#
# A category that is absent, or present but neither `none` nor a finding,
# is a skipped category. That is the defect this script exists to make
# visible. Research is graded on each finding that carries a remediation:
# `open-question`, or `tier-0` / `tier-1` with a primary and at least two
# corroborators. A remediation with neither is not a recommendation.
#
# The audit's other returns ride in the same file under `## Blindspots`,
# `## Doc-worthy gotchas` and `## Unverified claims`. Those headings are
# allowed and their bodies are not graded. Any other heading is malformed.
#
# Exit: 0 complete, 1 incomplete or malformed, 2 usage.
# The report is stdout. Usage errors are stderr.
#
#   collect-categories.sh --notes <audit-notes.md>
set -uo pipefail

usage() {
  cat <<'EOF'
collect-categories.sh — grade an audit-notes category ledger.

Usage:
  collect-categories.sh --notes <audit-notes.md>

Exit: 0 every required section is none, unresolved, not-applicable, or
findings with the required fields; 1 a section or field is missing or
malformed; 2 usage.
EOF
}

NOTES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --notes)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --notes needs a file" >&2
      exit 2
    fi
    NOTES="$2"
    shift 2
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -z "$NOTES" ]]; then
  echo "ERROR: --notes is required" >&2
  usage >&2
  exit 2
fi
if [[ ! -f "$NOTES" ]]; then
  echo "ERROR: notes file not found: $NOTES" >&2
  exit 2
fi

awk '
function trim(s) {
  sub(/\r$/, "", s)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
  return s
}
function problem(msg) {
  print "problem: " msg
  bad = 1
}
function close_finding() {
  if (!finding_open) return
  if (!has_evidence && section != "Emitted findings")
    problem("finding-missing-evidence section=" section " title=" title)
  if (has_remediation) {
    if (research == "") problem("remediation-without-research section=" section " title=" title)
    else if (research == "open-question") { }
    else if (research == "tier-0" || research == "tier-1") {
      if (primary == "") problem("research-missing-primary section=" section " title=" title)
      if (corroborators + 0 < 2 || corroborators !~ /^[0-9]+$/)
        problem("research-corroborators section=" section " title=" title " value=" corroborators)
    } else problem("research-bad-value section=" section " title=" title " value=" research)
  }
  if (section == "Standards alignment") {
    if (convention == "" || component == "")
      problem("standards-finding-uncited section=" section " title=" title)
  }
  if (section == "Emitted findings") {
    if (plugin_said == "") problem("emitted-missing-plugin-said title=" title)
    if (verdict != "confirmed" && verdict != "false" && verdict != "unvalidated")
      problem("emitted-bad-verdict title=" title " value=" verdict)
    if ((verdict == "false" || verdict == "confirmed") && basis == "")
      problem("emitted-" verdict "-without-basis title=" title)
  }
  finding_open = 0
}
function close_section() {
  if (section == "") return
  close_finding()
  if (marker != "" && items > 0) problem("section-mixed section=" section)
  else if (marker == "" && items == 0) problem("section-empty section=" section)
  seen[section] = 1
}
function reset_finding() {
  finding_open = 1
  items++
  has_evidence = 0
  has_remediation = 0
  research = ""
  primary = ""
  corroborators = ""
  convention = ""
  component = ""
  plugin_said = ""
  verdict = ""
  basis = ""
}
BEGIN {
  bad = 0
  section = ""
  marker = ""
  items = 0
  finding_open = 0
  title = ""
}
{
  line = trim($0)
  if (line ~ /^## /) {
    close_section()
    name = substr(line, 4)
    if (name == "Blindspots" || name == "Doc-worthy gotchas" || name == "Unverified claims") {
      section = ""
      marker = ""
      items = 0
      finding_open = 0
      next
    }
    if (name != "Errors" && name != "Improvements" && name != "Quality of life" &&
        name != "Standards alignment" && name != "Emitted findings") {
      problem("unknown-section name=" name)
      section = ""
    } else if (name in seen) {
      problem("duplicate-section name=" name)
      section = name
    } else {
      section = name
    }
    marker = ""
    items = 0
    finding_open = 0
    next
  }
  if (section == "" || line == "") next
  if (line ~ /^### /) {
    if (marker != "") problem("section-mixed section=" section)
    close_finding()
    title = substr(line, 5)
    reset_finding()
    next
  }
  if (!finding_open && marker == "" && items == 0 &&
      (line == "none" || line == "unresolved" || line == "not-applicable")) {
    if (line == "none") marker = "none"
    else if (line == "unresolved") {
      if (section != "Standards alignment") problem("marker-not-allowed section=" section " marker=unresolved")
      marker = "unresolved"
    } else {
      if (section != "Emitted findings") problem("marker-not-allowed section=" section " marker=not-applicable")
      marker = "not-applicable"
    }
    next
  }
  if (!finding_open) next
  split(line, kv, ":")
  key = kv[1]
  val = trim(substr(line, length(key) + 2))
  if (key == "evidence") has_evidence = (val != "")
  else if (key == "remediation") {
    has_remediation = 1
    if (val == "") problem("remediation-empty section=" section " title=" title)
  }
  else if (key == "research") research = val
  else if (key == "primary") primary = val
  else if (key == "corroborators") corroborators = val
  else if (key == "convention") convention = val
  else if (key == "component") component = val
  else if (key == "plugin-said") plugin_said = val
  else if (key == "verdict") verdict = val
  else if (key == "basis") basis = val
}
END {
  close_section()
  req[1] = "Errors"
  req[2] = "Improvements"
  req[3] = "Quality of life"
  req[4] = "Standards alignment"
  req[5] = "Emitted findings"
  for (i = 1; i <= 5; i++) if (!(req[i] in seen)) problem("missing-section name=" req[i])
  if (bad) print "status: incomplete"
  else print "status: complete"
  exit bad
}
' "$NOTES"
