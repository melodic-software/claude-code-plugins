#!/usr/bin/env bash
set -u

usage() {
  cat <<'EOF'
rule-inventory.sh - rule-to-enforcer inventory and its per-tier rollups.

Usage:
  rule-inventory.sh [--root DIR] [--rows] [--limit N]

  --root DIR  repository to inventory (default: the git toplevel of the
              current directory, else the current directory)
  --rows      print the inventory itself, one tab-separated row per rule:
              rule, enforcer, rung, tier; no summary
  --limit N   how many "sits lower than it could" candidates the summary lists
              (default 15; the total is always printed)

Sources, one adapter each:
  declared    rule_inventory.declared in <convention home>/harness-config.yaml,
              each item {rule, enforcer, rung}; the only source for rungs no
              file shows. With no pointer region the home is docs/conventions;
              a declined home, one that cannot apply, or one that does not
              resolve gives no declared rows, named with the reason
  settings    .claude/settings.json: each permissions.deny entry is a
              harness-setting; each PreToolUse or PermissionRequest handler is
              an action-guard
  ecosystems  .claude/ecosystems/*.yaml: each command line of check-cmd is an
              analyzer-pack-rule, of test-cmd a behavior-test, of build-cmd a
              compiler-setting
  test files  tracked files named *.test.*, *.spec.*, *_test.*, test_*.* or
              *Tests.*, outside fixtures and testdata directories, one
              behavior-test row per file (a unit of files, not of test cases)
  control     .claude/skills/control-*/SKILL.md, a runtime-verification each
  review      statements of REVIEW.md, an automated-review each
  instruction statements of every tracked CLAUDE.md and AGENTS.md and of
              .claude/rules/*.md, an instruction each
  skills      every other .claude/skills/*/SKILL.md, a skill each
  human       statements of CONTRIBUTING.md and checklist items of the pull
              request template, a human-review each
A statement is one list item or one prose paragraph, its wrapped lines joined;
headings, tables, fences, comments and @-imports are not statements. Files
under a fixtures, evals, tests or testdata directory are not read as the
repository's own instructions.

Never counted, and named as "present, not counted" when present: CI workflows,
git hook managers (lefthook, pre-commit, husky), .claude/settings.local.json,
and the hooks and settings of the plugins the project settings enable. A check
that runs only in one of those is in no row.

Sits lower than it could: a guidance-tier statement in which never, do not,
don't or must not is followed, within six words of the same clause, by a
backticked literal forbids that literal, which a pattern check could match.
It is listed unless the statement carries "Enforced by:" or the literal
appears as a whole token in the pattern text of a static-analysis or
codebase row: a deny entry, a hook's matcher and if value, a recorded
command line, or a declared rule. A whole token is not preceded or followed
by a letter, digit, _, - or ., so --force is not inside --force-exclude.
Test file names and enforcer labels name a file, not a pattern, and are not
searched. These are candidates for a person to judge, not findings.

Exit: 0 once the inventory is produced (a source it could not read is named
in the output); 2 for a usage error, a root it cannot enter, or a ladder copy
it cannot read.
EOF
}

root=""
rows_only=0
limit=15
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help) usage; exit 0 ;;
  --root)
    [[ $# -ge 2 ]] || { echo "rule-inventory.sh: --root needs a directory" >&2; exit 2; }
    root="$2"; shift ;;
  --rows) rows_only=1 ;;
  --limit)
    [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { echo "rule-inventory.sh: --limit needs a number" >&2; exit 2; }
    limit="$2"; shift ;;
  *) echo "rule-inventory.sh: unrecognized argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

script_dir="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$script_dir/../../.." && pwd)}"
ladder="${RULE_INVENTORY_LADDER:-$script_dir/../context/enforcement-ladder.md}"
yaml_awk="$plugin_root/lib/yaml-subset.awk"
resolve_home="$plugin_root/lib/resolve-convention-home.sh"

if [[ -z "$root" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  root="${root:-$PWD}"
fi
if [[ ! -d "$root" ]] || ! cd -- "$root" 2>/dev/null; then
  echo "rule-inventory.sh: root $root is not a directory this run could enter" >&2
  exit 2
fi
root="$PWD"

[[ -r "$ladder" ]] || { echo "rule-inventory.sh: ladder copy $ladder is not readable" >&2; exit 2; }
ladder_version="$(awk -F': *' '/^enforcement-ladder:/ {print $2; exit}' "$ladder")"
rungs="$(awk '
  /^## / && seen { exit }
  /^### Tier [0-9]+: / { tier = $3; sub(/:$/, "", tier); name = $0; sub(/^### Tier [0-9]+: /, "", name); seen = 1; next }
  !tier { next }
  /^[0-9]+\. \*\*`[a-z-]+`\*\*/ { id = $0; sub(/^[0-9]+\. \*\*`/, "", id); sub(/`.*/, "", id); print id "\t" tier "\t" name; next }
  /^\| `[a-z-]+` \|/ { id = $0; sub(/^\| `/, "", id); sub(/`.*/, "", id); print id "\t" tier "\t" name }
' "$ladder")"
[[ -n "$rungs" ]] || { echo "rule-inventory.sh: no rung ids found in $ladder" >&2; exit 2; }
rung_map=" $(awk -F'\t' '{printf "%s:%s ", $1, $2}' <<<"$rungs")"

work="$(mktemp -d)" || exit 2
trap 'rm -rf -- "$work"' EXIT
rows="$work/rows.tsv"
: >"$rows"
notes="$work/notes.txt"
: >"$notes"
note() { printf '%s\n' "$*" >>"$notes"; }
cover="$work/cover.txt"
: >"$cover"

emit() {
  local t="${rung_map#* "$3":}"
  local text="${1//[$'\t\r']/ }"
  if [[ "$t" == "$rung_map" ]]; then
    note "skipped: rung \`$3\` from $2 is not a rung of ladder $ladder_version"
    return
  fi
  t="${t%% *}"
  [[ "$text" =~ ^[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] && text="${BASH_REMATCH[1]}"
  printf '%s\t%s\t%s\t%s\n' "$text" "$2" "$3" "$t" >>"$rows"
  [[ -z "${4:-}" || "$t" -gt 2 ]] || printf '%s\n' "${4//[$'\t\r']/ }" >>"$cover"
}

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -c core.quotepath=off ls-files >"$work/files" 2>/dev/null
else
  find . -path ./.git -prune -o -path ./node_modules -prune -o -type f -print | sed 's|^\./||' >"$work/files"
fi
own_files() { grep -Ev '(^|/)(fixtures|evals|tests|testdata)/' "$work/files"; }

list_items() {
  awk -v only_check="${2:-0}" '
    function flush() { if (text != "" && (only_check != 1 || check)) print start "\t" text; text = ""; check = 0 }
    function add(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); text = text == "" ? s : text " " s }
    NR == 1 && /^---[[:space:]]*$/ { front = 1; next }
    front { if (/^---[[:space:]]*$/) front = 0; next }
    /^[[:space:]]*(```|~~~)/ { flush(); fence = !fence; next }
    fence { next }
    comment { if (/-->/) comment = 0; next }
    /^[[:space:]]*<!--/ { flush(); if ($0 !~ /-->/) comment = 1; next }
    /^[[:space:]]*$/ || /^[[:space:]]*#/ || /^[[:space:]]*\|/ || /^@[^[:space:]]+[[:space:]]*$/ { flush(); next }
    /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+[^[:space:]]/ {
      flush(); start = NR; t = $0
      if (t ~ /^[[:space:]]*[-*+][[:space:]]+\[[ xX]\][[:space:]]+/) { check = 1; sub(/^[[:space:]]*[-*+][[:space:]]+\[[ xX]\][[:space:]]+/, "", t) }
      else sub(/^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+/, "", t)
      add(t); next
    }
    { if (text == "") start = NR; add($0) }
    END { flush() }
  ' "$1"
}
emit_items() {
  local line text
  while IFS=$'\t' read -r line text; do
    emit "$text" "$1:$line" "$2"
  done < <(list_items "$1" "${3:-0}")
}

read_status() {
  if [[ ! -e "$1" ]]; then echo absent
  elif [[ ! -r "$1" ]]; then echo unreadable
  else echo ok; fi
}

home="docs/conventions"
skip=""
if [[ ! -r "$resolve_home" ]]; then
  note "declared: no convention-home resolver at $resolve_home, so the default home $home is read"
else
  h="$(bash "$resolve_home" --root "$root" 2>"$work/home.err")"
  case $? in
  0) home="$h" ;;
  1) ;;
  4) skip="the repository declined a convention home" ;;
  5) skip="no convention home applies to this root" ;;
  *) skip="the convention home did not resolve ($(head -n 1 "$work/home.err"))" ;;
  esac
fi
decl="$home/harness-config.yaml"
status="$(read_status "$decl")"
if [[ -n "$skip" ]]; then
  [[ "$status" == absent ]] || skip="$skip ($decl is present and not read)"
  status=skipped
fi
case "$status" in
skipped) note "declared: not read, so no declared rows: $skip" ;;
absent) note "declared: $decl absent, so no declared rows" ;;
unreadable) note "declared: $decl unreadable" ;;
*)
  if ! command -v awk >/dev/null || [[ ! -r "$yaml_awk" ]]; then
    note "declared: $decl not parsed (no YAML reader at $yaml_awk)"
  elif ! flat="$(awk -f "$yaml_awk" "$decl")"; then
    note "declared: $decl does not parse: ${flat#error	}"
  else
    n=0
    while :; do
      r="$(awk -F'\t' -v k="rule_inventory.declared.$n.rule" '$1 == k {print $2}' <<<"$flat")"
      e="$(awk -F'\t' -v k="rule_inventory.declared.$n.enforcer" '$1 == k {print $2}' <<<"$flat")"
      g="$(awk -F'\t' -v k="rule_inventory.declared.$n.rung" '$1 == k {print $2}' <<<"$flat")"
      [[ -n "$r$e$g" ]] || break
      if [[ "$g" == semgrep-rule ]]; then
        note "declared: item $n names semgrep-rule, read as syntax-pattern-rule (renamed in ladder 3.0.0)"
        g=syntax-pattern-rule
      fi
      if [[ -z "$r" || -z "$g" ]]; then
        note "declared: item $n in $decl lacks a rule or a rung; skipped"
      else
        emit "$r" "${e:-declared in $decl}" "$g" "$r"
      fi
      n=$((n + 1))
    done
    note "declared: $decl read, $n item(s)"
  fi
  ;;
esac

settings=".claude/settings.json"
case "$(read_status "$settings")" in
absent) note "settings: $settings absent" ;;
unreadable) note "settings: $settings unreadable" ;;
*)
  if ! command -v jq >/dev/null; then
    note "settings: $settings not read (jq is not on PATH)"
  elif ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
    note "settings: $settings is not a JSON object"
  else
    while IFS= read -r d; do emit "$d" "$settings permissions.deny" harness-setting "$d"; done \
      < <(jq -r '(.permissions.deny // [])[] | strings' "$settings")
    while IFS=$'\t' read -r ev m cond; do
      emit "$ev $m${cond:+ if $cond}" "$settings hooks" action-guard "$m${cond:+ $cond}"
    done < <(jq -r '(.hooks // {}) | to_entries[] | select(.key == "PreToolUse" or .key == "PermissionRequest")
        | .key as $ev | (.value // [])[] | (.matcher // "*") as $m | (.hooks // [])[]
        | [$ev, $m, (.if // "")] | map(tostring | gsub("[\t\r\n]"; " ")) | join("\t")' "$settings")
    note "settings: $settings read"
  fi
  ;;
esac

eco_n=0
for f in .claude/ecosystems/*.yaml; do
  [[ -e "$f" ]] || continue
  if [[ ! -r "$f" ]]; then note "ecosystems: $f unreadable"; continue; fi
  eco_n=$((eco_n + 1))
  name="${f##*/}"; name="${name%.yaml}"
  while IFS=$'\t' read -r key cmd; do
    case "$key" in
    check-cmd) rung=analyzer-pack-rule ;;
    test-cmd) rung=behavior-test ;;
    build-cmd) rung=compiler-setting ;;
    *) continue ;;
    esac
    emit "$name $key: $cmd" "$f" "$rung" "$cmd"
  done < <(awk '
    function val(v) { sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); return v }
    block && /^[^[:space:]#]/ { block = "" }
    block { l = val($0); if (l != "" && l !~ /^#/) print block "\t" l; next }
    /^(check|test|build)-cmd:/ {
      k = $0; sub(/:.*/, "", k); v = $0; sub(/^[^:]*:/, "", v); v = val(v)
      if (v == "|" || v == ">" || v == "|-" || v == ">-") { block = k; next }
      if (v == "" || v == "null" || v == "~") next
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      print k "\t" v
    }
  ' "$f")
done
if [[ "$eco_n" -eq 0 ]]; then
  note "ecosystems: no .claude/ecosystems/*.yaml record, so no recorded build, test or check command"
else
  note "ecosystems: $eco_n record(s) read"
fi

tests="$(grep -Ev '(^|/)(fixtures|testdata)/' "$work/files" | grep -E '(^|/)([^/]+\.test\.[^/]+|[^/]+\.spec\.[^/]+|[^/]+_test\.[^/]+|test_[^/]+\.[^/]+|[^/]*[a-z]Tests\.[^/]+)$' || true)"
if [[ -n "$tests" ]]; then
  while IFS= read -r t; do emit "tests in $t" "$t" behavior-test; done <<<"$tests"
fi
note "test files: one behavior-test row per test file found by name; tests in files named otherwise are not counted"

for s in .claude/skills/*/SKILL.md; do
  [[ -e "$s" ]] || continue
  d="${s%/SKILL.md}"; d="${d##*/}"
  case "$d" in
  control-*) emit "runtime verification through the $d skill" "$s" runtime-verification ;;
  *) emit "the $d skill's procedure" "$s" skill ;;
  esac
done

review_seen=0
if [[ -r REVIEW.md ]]; then emit_items REVIEW.md automated-review; review_seen=1; fi
[[ "$review_seen" = 1 ]] || note "review: REVIEW.md absent"
inst="$(own_files | grep -E '(^|/)(CLAUDE|AGENTS)\.md$' || true)"
rules="$(own_files | grep -E '^\.claude/rules/[^/]+\.md$' || true)"
inst_n=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if [[ -r "$f" ]]; then emit_items "$f" instruction; inst_n=$((inst_n + 1)); else note "instruction: $f unreadable"; fi
done <<<"$inst
$rules"
note "instruction: $inst_n instruction file(s) read"

human_n=0
for f in CONTRIBUTING.md docs/CONTRIBUTING.md .github/CONTRIBUTING.md; do
  [[ -r "$f" ]] && { emit_items "$f" human-review; human_n=$((human_n + 1)); }
done
for f in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md PULL_REQUEST_TEMPLATE.md docs/pull_request_template.md; do
  [[ -r "$f" ]] && { emit_items "$f" human-review 1; human_n=$((human_n + 1)); }
done
[[ "$human_n" -gt 0 ]] || note "human: no CONTRIBUTING.md and no pull request template in this repository"

wf="$(grep -Ec '^\.github/workflows/[^/]+\.ya?ml$' "$work/files")"
[[ "$wf" -eq 0 ]] || note "present, not counted: $wf CI workflow file(s) under .github/workflows; a check that runs only there is in no row"
for f in lefthook.yml lefthook.yaml .lefthook.yml .pre-commit-config.yaml .husky; do
  [[ -e "$f" ]] && note "present, not counted: $f (git hooks); a check that runs only there is in no row"
done
[[ -e .claude/settings.local.json ]] && note "present, not counted: .claude/settings.local.json (one person's settings)"
if [[ -r "$settings" ]] && command -v jq >/dev/null &&
  jq -e '(.enabledPlugins // {}) | to_entries | any(.value == true)' "$settings" >/dev/null 2>&1; then
  note "present, not counted: hooks and settings of the plugins $settings enables"
fi

if [[ "$rows_only" = 1 ]]; then
  cat "$rows"
  exit 0
fi

covered() {
  awk '
    function tok(c) { return c ~ /[[:alnum:]_.-]/ }
    BEGIN { lit = ARGV[1]; ARGV[1] = ""; n = length(lit) }
    {
      p = 0
      while ((i = index(substr($0, p + 1), lit)) > 0) {
        s = p + i
        if (!tok(substr($0, s - 1, s > 1)) && !tok(substr($0, s + n, 1))) { found = 1; exit }
        p = s
      }
    }
    END { exit !found }
  ' "$1" "$cover"
}
lower="$work/lower.txt"
: >"$lower"
# shellcheck disable=SC2016 # the backticks are Markdown code-span delimiters
forbid_re='(^|[^[:alpha:]])([Nn]ever|NEVER|[Dd]o not|[Dd]on'"'"'t|[Mm]ust not)(([[:space:]]+[^[:space:]`.,;:]+){0,6})[[:space:]]+`([^`]+)`'
while IFS=$'\t' read -r rule enforcer rung tier; do
  [[ "$tier" -ge 4 ]] || continue
  [[ "$rule" != *"Enforced by:"* ]] || continue
  rest="$rule"
  open=""
  while [[ "$rest" =~ $forbid_re ]]; do
    lit="${BASH_REMATCH[5]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    covered "$lit" || open="${open:+$open, }\`$lit\`"
  done
  [[ -z "$open" ]] || printf '%s: forbids %s (%s)\n' "$enforcer" "$open" "$rung" >>"$lower"
done <"$rows"

total="$(wc -l <"$rows" | tr -d ' ')"
echo "Rule-to-enforcer inventory: $total rule(s) in $root"
echo "Ladder: enforcement-ladder ${ladder_version:-unknown}. Counts only; the ladder sets no share or count to reach."
echo
echo "| Tier | Rules | By rung |"
echo "|---|---|---|"
for t in $(cut -f2 <<<"$rungs" | uniq); do
  tname="$(awk -F'\t' -v t="$t" '$2 == t {print $3; exit}' <<<"$rungs")"
  n="$(awk -F'\t' -v t="$t" '$4 == t' "$rows" | wc -l | tr -d ' ')"
  by="$(awk -F'\t' -v t="$t" '$4 == t {c[$3]++} END {for (r in c) print r " " c[r]}' "$rows" | sort | paste -sd, - | sed 's/,/, /g')"
  if [[ "$n" -eq 0 ]]; then
    case "$t" in
    1) if [[ -n "$skip" ]]; then by="declared rows not read (see the declared source line); no file shows this tier"
       else by="none declared; no file shows this tier, so only declared rows count"; fi ;;
    *) by="none found in the sources below" ;;
    esac
  fi
  echo "| $t $tname | $n | $by |"
done
echo
echo "A row is one deny entry, hook handler, recorded command, test file, skill or guidance statement, whatever it holds."
echo
nl="$(wc -l <"$lower" | tr -d ' ')"
echo "Sits lower than it could: $nl guidance rule(s) forbid a literal that a pattern check could match (candidates to judge, not findings)"
head -n "$limit" "$lower" | sed 's/^/- /'
[[ "$nl" -le "$limit" ]] || echo "- ... and $((nl - limit)) more (--limit to list more)"
echo
echo "Sources:"
sed 's/^/- /' "$notes"
exit 0
