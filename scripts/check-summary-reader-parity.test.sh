#!/usr/bin/env bash
# Parity gate: every reader of `metadata.summary` must return the same verdict,
# and the verdict they share must be the correct one.
#
# Three pieces of code in this repository read skill frontmatter, and they used
# to disagree. A malformed summary reached CI twice, failing in opposite
# directions, each time after clearing the local check meant to catch it
# (#3189). Making them merely agree was not enough: agreement on a wrong rule is
# still wrong, so this gate pins the verdicts to an oracle rather than to each
# other.
#
#   Reader A  plugins/skill-quality/scripts/skill-frontmatter.sh
#             (bash; ships inside the installable plugin, no Node available)
#   Reader C  scripts/cheatsheet-config.mjs, summaryError
#             (JavaScript; repo-internal, drives the cheat-sheet generator)
#   Oracle    a real YAML parser (PyYAML), the same reader
#             scripts/check-hook-exec-form.sh already relies on
#
# The contract is a FIXED POINT: the literal text after `summary:` must be the
# value every reader recovers. Readers A and C are fast, single-line
# approximations of that. The oracle is the definition, so it also catches the
# classes no character-level rule can reach: values a resolver reads as a
# non-string (`true`, `12:34`, `2026-08-23`) and multi-line plain scalars whose
# continuation lines a line-oriented reader never sees.
#
# Two sweeps:
#   1. the shared case table, proving the RULE SET
#   2. every SKILL.md in the tree, proving the TREE
#
# Exit 0 = parity holds; 1 = a reader diverged; 2 = the gate could not run.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
REPO_ROOT="$PWD"

CASES="plugins/skill-quality/scripts/summary-contract-cases.json"
LIB="plugins/skill-quality/scripts/skill-frontmatter.sh"
CONFIG="scripts/cheatsheet-config.mjs"
REQUIREMENTS=".github/requirements-ci.txt"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

for f in "$CASES" "$LIB" "$CONFIG"; do
  [[ -f "$f" ]] || {
    echo "missing required file: $f" >&2
    exit 2
  }
done
command -v jq >/dev/null 2>&1 || {
  echo "jq is required to read the shared case table" >&2
  exit 2
}
command -v node >/dev/null 2>&1 || {
  echo "node is required to run the JavaScript guard" >&2
  exit 2
}

# --- PyYAML resolution -------------------------------------------------------
# Same ladder scripts/check-hook-exec-form.sh uses. This gate does NOT skip when
# PyYAML is unavailable: the oracle is the only thing here that proves the
# shared verdict is correct rather than merely shared, so clearing without it
# would report green while proving the weaker half of the claim.
pyyaml_pin="$(awk '/^pyyaml==/ {
  sub(/^pyyaml==/, "")
  sub(/[[:space:];].*$/, "")
  print
  exit
}' "$REQUIREMENTS" 2>/dev/null)"

reader_cmd=()
for candidate in python3 python py; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
    reader_cmd=("$candidate")
    break
  fi
done
if ((${#reader_cmd[@]} == 0)) && [[ -n "$pyyaml_pin" ]] && command -v uv >/dev/null 2>&1; then
  reader_cmd=(uv run --quiet --no-project --with "pyyaml==$pyyaml_pin" python)
fi
if ((${#reader_cmd[@]} == 0)); then
  echo "check-summary-reader-parity: no python with PyYAML available, and no uv to borrow one." >&2
  echo "The YAML oracle is what proves the readers agree on the CORRECT value," >&2
  echo "so this gate stops rather than clearing on the two regex readers alone." >&2
  echo "  * install the pin: pip install 'pyyaml==${pyyaml_pin:-<see $REQUIREMENTS>}'" >&2
  echo "  * or install uv: https://docs.astral.sh/uv/" >&2
  exit 2
fi

# shellcheck source=../plugins/skill-quality/scripts/skill-frontmatter.sh
source "$LIB"

# --- Reader C and the oracle, driven in one batch each -----------------------
# Both are process-expensive, so each runs once over the whole table rather than
# once per case.

js_verdicts() {
  # The single-quoted payload is a Node program; nothing in it should expand.
  # shellcheck disable=SC2016
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    import { pathToFileURL } from "node:url";
    const [casesPath, configPath] = process.argv.slice(1);
    const { summaryError } = await import(pathToFileURL(configPath).href);
    const { cases } = JSON.parse(readFileSync(casesPath, "utf8"));
    for (const c of cases) {
      const err = summaryError(c.value);
      process.stdout.write(`${c.id}\t${err ? "invalid" : "valid"}\n`);
    }
  ' "$CASES" "$REPO_ROOT/$CONFIG"
}

yaml_verdicts() {
  "${reader_cmd[@]}" - "$CASES" <<'PY'
import json, sys, yaml

# Windows defaults stdout to the ANSI code page and translates "\n" to CRLF.
# Both corrupt this gate's tab-separated channel: the trailing CR rides along on
# the last field and every non-ASCII summary comes back mojibake, so identical
# values compare unequal and the gate reports divergences that do not exist.
sys.stdout.reconfigure(encoding="utf-8", newline="\n")

with open(sys.argv[1], encoding="utf-8") as fh:
    cases = json.load(fh)["cases"]

for c in cases:
    value = c["value"]
    # Parse the value in the exact structural position it occupies in a
    # SKILL.md: an indented sub-key of a top-level `metadata:` block.
    doc = "metadata:\n  summary: " + value + "\n"
    try:
        parsed = yaml.safe_load(doc)
    except Exception:
        verdict = "reject"
    else:
        got = (parsed or {}).get("metadata")
        got = got.get("summary") if isinstance(got, dict) else None
        if isinstance(got, str) and got == value:
            verdict = "roundtrip"
        else:
            verdict = "shift"
    print(f"{c['id']}\t{verdict}")
PY
}

declare -A JS_VERDICT YAML_VERDICT
while IFS=$'\t' read -r id verdict; do
  [[ -n "$id" ]] && JS_VERDICT["$id"]="$verdict"
done < <(js_verdicts)
while IFS=$'\t' read -r id verdict; do
  [[ -n "$id" ]] && YAML_VERDICT["$id"]="$verdict"
done < <(yaml_verdicts)

# --- Sweep 1: the shared case table ------------------------------------------

case_count=0
# The VALUE travels base64-encoded, deliberately. A bare @tsv field escapes an
# embedded tab into a literal backslash-t, so the bash reader would judge a
# different string than the other two readers judge and the gate would report a
# divergence it manufactured itself. Encoding also survives jq's CRLF output on
# Windows, which otherwise rides along on the final field and silently adds a
# codepoint to every value.
while IFS=$'\t' read -r id expect expect_yaml value_b64; do
  [[ -n "$id" ]] || continue
  value_b64="${value_b64%$'\r'}"
  value="$(printf '%s' "$value_b64" | base64 -d)"
  case_count=$((case_count + 1))

  if skill_frontmatter::summary_error "$value" >/dev/null; then
    bash_verdict=valid
  else
    bash_verdict=invalid
  fi
  js_verdict="${JS_VERDICT[$id]:-<absent>}"
  yaml_verdict="${YAML_VERDICT[$id]:-<absent>}"

  if [[ "$bash_verdict" != "$expect" ]]; then
    fail "$id: bash reader said $bash_verdict, contract says $expect"
  elif [[ "$js_verdict" != "$expect" ]]; then
    fail "$id: JavaScript guard said $js_verdict, contract says $expect"
  else
    pass "$id: both readers agree ($expect)"
  fi

  # The oracle. A value both readers ACCEPT must round-trip through a real
  # parser as the identical string; that is the safety-critical direction and it
  # is asserted for every accepted case, whatever the table claims.
  if [[ "$expect" == valid && "$yaml_verdict" != roundtrip ]]; then
    fail "$id: accepted by both readers but a real YAML parser says $yaml_verdict — the readers agree on a value the parser does not produce"
  fi
  # Where the table records what the parser does, hold it to that, so a rule
  # cannot outlive the parser behavior that justified it.
  if [[ -n "$expect_yaml" && "$expect_yaml" != null && "$yaml_verdict" != "$expect_yaml" ]]; then
    fail "$id: table records YAML behavior '$expect_yaml' but the parser gave '$yaml_verdict'"
  fi
done < <(jq -r '.cases[] | [.id, (if .valid then "valid" else "invalid" end), (.yaml // ""), (.value | @base64)] | @tsv' "$CASES")

if ((case_count == 0)); then
  fail "the shared case table produced no cases"
else
  pass "shared case table: $case_count cases exercised against both readers and the YAML oracle"
fi

# --- Sweep 2: every SKILL.md in the tree -------------------------------------
# The case table proves the rule set; this proves the tree. Three-way value
# agreement, not just verdict agreement: the readers must extract the SAME TEXT
# from real files, which is where a scoping divergence shows up.

tree_report="$(
  "${reader_cmd[@]}" - "$REPO_ROOT" <<'PY'
import pathlib, re, sys, yaml

# See the note in the case-table reader: UTF-8 and LF are load-bearing for the
# tab-separated channel this writes.
sys.stdout.reconfigure(encoding="utf-8", newline="\n")

root = pathlib.Path(sys.argv[1])
for path in sorted(root.glob("plugins/*/skills/*/SKILL.md")):
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    if not lines or not re.match(r"^---[ \t]*$", lines[0]):
        continue
    in_meta = False
    raw = None
    fm_end = None
    for i, line in enumerate(lines[1:], start=1):
        if re.match(r"^---[ \t]*$", line):
            fm_end = i
            break
        if re.match(r"^metadata:[ \t]*$", line):
            in_meta = True
            continue
        if re.match(r"^[^ \t]", line):
            in_meta = False
            continue
        if not in_meta:
            continue
        m = re.match(r"^[ \t]+([A-Za-z0-9-]+):[ \t]*(.*)$", line)
        if m and m.group(1) == "summary" and raw is None:
            raw = m.group(2).strip()
    if raw is None:
        continue
    rel = path.relative_to(root).as_posix()
    try:
        parsed_doc = yaml.safe_load("\n".join(lines[1:fm_end]))
    except Exception as exc:
        print(f"{rel}\t<parse-error:{type(exc).__name__}>\t{raw}")
        continue
    got = (parsed_doc or {}).get("metadata")
    got = got.get("summary") if isinstance(got, dict) else None
    if not isinstance(got, str):
        print(f"{rel}\t<non-string:{type(got).__name__}>\t{raw}")
    else:
        print(f"{rel}\t{got}\t{raw}")
PY
)"

tree_count=0
while IFS=$'\t' read -r rel parsed regex_read; do
  [[ -n "$rel" ]] || continue
  tree_count=$((tree_count + 1))

  # Frontmatter only. Feeding the whole file would let a `metadata:` line in the
  # BODY answer for the frontmatter, which is the same class of mistake this
  # gate exists to catch.
  bash_read="$(skill_frontmatter::extract <"$REPO_ROOT/$rel" |
    skill_frontmatter::metadata_field summary --raw)"

  if [[ "$parsed" == "<parse-error:"* ]]; then
    fail "$rel: frontmatter does not parse as YAML ($parsed) — the skill would load with EMPTY metadata"
    continue
  fi
  if [[ "$parsed" == "<non-string:"* ]]; then
    fail "$rel: metadata.summary parses as $parsed, not a string — the parsed value and the regex-read text disagree"
    continue
  fi
  if [[ "$bash_read" != "$regex_read" ]]; then
    fail "$rel: bash reader read [$bash_read] but the generator's reader read [$regex_read]"
    continue
  fi
  if [[ "$parsed" != "$regex_read" ]]; then
    fail "$rel: a real YAML parser yields [$parsed] but the regex readers read [$regex_read]"
    continue
  fi
  if ! skill_frontmatter::summary_error "$bash_read" >/dev/null; then
    fail "$rel: summary is in the tree but fails the shared contract"
  fi
done <<<"$tree_report"

if ((tree_count == 0)); then
  fail "no SKILL.md carrying metadata.summary was found — the tree sweep proved nothing"
else
  pass "tree sweep: $tree_count summaries agree across the bash reader, the generator's reader, and a real YAML parser"
fi

if ((fails > 0)); then
  printf '\n%d parity failure(s)\n' "$fails" >&2
  exit 1
fi
printf '\nsummary reader parity holds\n'
