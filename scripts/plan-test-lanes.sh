#!/usr/bin/env bash
# Plan the test lanes from the change's suite selection: which suites each lane
# of pr-require-checks.yml runs, on how many legs and with which optional toolchains, and which
# jobs and steps of pr-test-windows.yml run.
#
#   scripts/plan-test-lanes.sh                 the whole tree
#   scripts/plan-test-lanes.sh --base <ref>    the change since the merge base with <ref>
#   scripts/plan-test-lanes.sh -- <path>...    the change made of these paths
#
# Prints one `key=value` line per key on stdout, the form $GITHUB_OUTPUT takes,
# and a summary on stderr:
#   bash, python, node        `true` when the lane has work, else `false`
#   bash_legs, python_legs    the lane's matrix, a JSON list of leg numbers (`[0]` at least)
#   bash_plan, python_plan    a JSON object from leg number to the suites that leg runs
#   bash_needs, python_needs  a JSON object from leg number to the optional toolchains
#                             its suites need: animation (the animation and
#                             speech suites), inventory, duckdb
#   node_packages             the Node packages to install and test, space-separated
#   windows_jobs              the pr-test-windows.yml jobs to run, a JSON list
#   windows_steps             the pr-test-windows.yml steps to run, a JSON list of the keys
#                             in scripts/test-windows-plan.txt
#   unmapped                  how many changed files mapped to no suite
#
# THE SELECTION is scripts/affected-tests.sh --unmapped-corpus over the changed
# files: the suites the change runs or reads, plus the whole corpus of an
# unmapped file's language. Each suite goes to the lane of its ecosystem:
#   *.test.sh               test-bash
#   test_*.py               test-python (eval fixtures under /evals/fixtures/ are data)
#   *.test.js .mjs .cjs     the sibling <stem>.test.sh when there is one (CI runs such a
#                           suite only through it), else the Node package holding it.
#                           Eval fixtures (scripts/outside-node-exclusions.txt) are data.
#                           A Node suite with neither fails the plan: no lane would run it.
#   *.Tests.ps1             test-windows; Pester has no Linux lane
#
# WIDER THAN THE SELECTION, NEVER NARROWER:
#   - the whole tree (no base and no paths: a schedule, a dispatch, a push with no
#     usable base), or a change to pr-require-checks.yml or .github/actions/: every suite of
#     every pr-require-checks.yml lane. pr-test-windows.yml, .github/actions/ and .python-version
#     (every Windows job sets up its Python from it) do the same for the Windows
#     plan.
#   - a Python pin (.python-version, pyproject.toml, uv.lock, requirements*.txt,
#     .github/requirements-ci*.txt): every Python suite.
#   - a Node pin (.node-version, the root package.json or package-lock.json):
#     every Node package.
#   - a Node package also runs when a file under its directory, its test facade or
#     a `file:` dependency of its package.json changed.
#
# LEGS ARE SIZED FROM SUITE-SECONDS: ceil(seconds / budget), at least 1, at most
# the lane's cap and the suite count. test-bash takes 120 s a leg (three suites
# run at a time, so about 40 s of wall) up to 6 legs, and the whole tree always
# takes 6; test-python takes 180 s a leg (one suite at a time) up to 4. A
# suite's seconds are its median wall in scripts/suite-seconds.txt, measured
# over whole-tree CI runs; a suite the file does not list counts 5, and a suite
# scripts/run-plugin-tests-serial.txt runs alone counts three times its
# seconds. Suites go longest first to the least-loaded leg, so the legs finish
# close together, and every selected suite lands on exactly one leg.
#
# Exit: 0 planned; 2 usage, a failed selector or listing, or a selected suite no
# lane runs.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2
# shellcheck source=lib/read-list.sh
. scripts/lib/read-list.sh || exit 2
# shellcheck source=lib/changed-files.sh
. scripts/lib/changed-files.sh || exit 2

SECONDS_LIST="scripts/suite-seconds.txt"
WINDOWS_LIST="scripts/test-windows-plan.txt"
PACKAGES_LIST="scripts/outside-node-packages.txt"
EXCLUSIONS_LIST="scripts/outside-node-exclusions.txt"
DEFAULT_SECONDS=5
# The four Node sub-projects with CI steps of their own in test-node:
# <package> <owner directory of its suites> [<test facade>]. The packages in
# scripts/outside-node-packages.txt follow, each its own owner.
SUBPROJECTS="\
plugins/miro/server plugins/miro/
plugins/ai-briefing/skills/generate/output/build plugins/ai-briefing/skills/generate/ plugins/ai-briefing/skills/generate/scripts/run-tests.sh
plugins/knowledge/skills/video-digest/extraction plugins/knowledge/skills/video-digest/ plugins/knowledge/skills/video-digest/scripts/run-tests.sh
plugins/knowledge/skills/course-digest/extraction plugins/knowledge/skills/course-digest/ plugins/knowledge/skills/course-digest/scripts/run-tests.sh"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}" >&2
  exit 2
}
die() {
  echo "plan-test-lanes: $*" >&2
  exit 2
}

base=""
given=0
declare -a changed=()
while (($# > 0)); do
  case "$1" in
  --base)
    [[ $# -ge 2 && -n "$2" ]] || usage
    base="$2"
    shift 2
    ;;
  --)
    shift
    given=1
    changed=("${@#./}")
    break
    ;;
  *) usage ;;
  esac
done
[[ -n "$base" && "$given" -eq 1 ]] && usage

WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT

# --- the change -------------------------------------------------------------

whole=0
whole_windows=0
python_pin=0
node_pin=0
if [[ -n "$base" ]]; then
  changed_files::verify_base "$base" || die "base ref '$base' does not resolve to a commit"
  mb="$(git merge-base "$base" HEAD)" || die "'$base' and HEAD have no merge base"
  # The selector's own reading of a diff: the working tree against the merge
  # base, deletions included, plus untracked files. A failed listing is fatal,
  # never an empty change.
  changed_files::into changed "$mb" --include-deleted || die "listing the files changed since $mb failed"
  git ls-files --others --exclude-standard >"$WORK/untracked" || die "listing the untracked files failed"
  mapfile -t -O "${#changed[@]}" changed <"$WORK/untracked"
elif [[ "$given" -eq 0 ]]; then
  whole=1
  whole_windows=1
fi
for f in ${changed[@]+"${changed[@]}"}; do
  case "$f" in
  .github/workflows/pr-require-checks.yml) whole=1 ;;
  .github/workflows/pr-test-windows.yml) whole_windows=1 ;;
  .github/actions/*)
    whole=1
    whole_windows=1
    ;;
  .python-version)
    # Every Windows job sets up its Python from this pin too.
    python_pin=1
    whole_windows=1
    ;;
  pyproject.toml | uv.lock | requirements*.txt | .github/requirements-ci*.txt) python_pin=1 ;;
  .node-version | package.json | package-lock.json) node_pin=1 ;;
  *) ;;
  esac
done

# --- the selection ----------------------------------------------------------

unmapped=0
: >"$WORK/selection"
if [[ ${#changed[@]} -gt 0 ]] && ((!whole || !whole_windows)); then
  rc=0
  bash scripts/affected-tests.sh --unmapped-corpus -- "${changed[@]}" >"$WORK/selection" 2>"$WORK/selector.err" || rc=$?
  case "$rc" in
  0) ;;
  4)
    unmapped=$(awk '/^UNMAPPED:/ { print $2; exit }' "$WORK/selector.err")
    awk '/^UNMAPPED:/ { f = 1; print; next } f && /^  - / { print; next } { f = 0 }' "$WORK/selector.err" >&2
    ;;
  *)
    cat "$WORK/selector.err" >&2
    die "scripts/affected-tests.sh exited $rc; the selection is unknown"
    ;;
  esac
fi

# Assigned through a nameref, which shellcheck cannot follow (SC2154).
exclusions=() outside=() rows=()
read_list::into exclusions "$EXCLUSIONS_LIST" --comments inline || exit 2
read_list::into outside "$PACKAGES_LIST" --comments inline || exit 2

# Every Node package as `<package> <owner> [<facade>]`.
packages="$SUBPROJECTS"
for p in "${outside[@]}"; do packages+=$'\n'"$p $p/"; done

# owner_package <suite>: the package whose owner directory holds <suite>.
owner_package() {
  local pkg owner rest
  while read -r pkg owner rest; do
    [[ "$1" == "$owner"* ]] && {
      printf '%s\n' "$pkg"
      return 0
    }
  done <<<"$packages"
  return 1
}

# normpath <path>: fold `.` and `..` out of a relative path.
normpath() {
  local -a out=() parts=()
  local part
  IFS=/ read -r -a parts <<<"$1"
  for part in "${parts[@]}"; do
    case "$part" in
    "" | .) ;;
    ..) [[ ${#out[@]} -gt 0 ]] && unset 'out[${#out[@]}-1]' ;;
    *) out+=("$part") ;;
    esac
  done
  (IFS=/ && printf '%s\n' "${out[*]}")
}

declare -A BASH_SET=() PY_SET=() PKG_SET=()
while IFS= read -r s; do
  [[ -n "$s" ]] || continue
  case "$s" in
  *.test.sh) BASH_SET["$s"]=1 ;;
  *.Tests.ps1) ;;
  *.test.js | *.test.mjs | *.test.cjs)
    wrapper="${s%.test.*}.test.sh"
    if [[ -f "$wrapper" ]]; then
      BASH_SET["$wrapper"]=1
      continue
    fi
    for e in ${exclusions[@]+"${exclusions[@]}"}; do
      [[ "$s" == "$e"* ]] && continue 2
    done
    pkg="$(owner_package "$s")" ||
      die "$s is a selected Node suite that no lane runs: it has no sibling .test.sh and no Node package in the test-node lane holds it"
    PKG_SET["$pkg"]=1
    ;;
  *)
    [[ "${s##*/}" == test_*.py ]] || die "the selector returned '$s', which is no suite kind this planner knows"
    [[ "$s" == */evals/fixtures/* ]] || PY_SET["$s"]=1
    ;;
  esac
done <"$WORK/selection"

python_corpus() {
  git ls-files --cached --others --exclude-standard |
    awk '{ b = $0; sub(/.*\//, "", b) } b ~ /^test_.*\.py$/ && !/\/evals\/fixtures\//' ||
    die "listing the Python suites failed"
}

if ((whole)); then
  bash scripts/run-plugin-tests.sh --list >"$WORK/bash" || die "listing the shell corpus failed"
  python_corpus >"$WORK/python"
else
  printf '%s\n' ${BASH_SET[@]+"${!BASH_SET[@]}"} | LC_ALL=C sort -u | grep . >"$WORK/bash"
  if ((python_pin)); then
    python_corpus >"$WORK/python"
  else
    printf '%s\n' ${PY_SET[@]+"${!PY_SET[@]}"} | LC_ALL=C sort -u | grep . >"$WORK/python"
  fi
fi

# A package runs on the whole tree, on a Node pin, when a selected suite sits
# under its owner, or when a file under it, its facade or a `file:` dependency
# changed.
node_packages=""
while read -r pkg owner facade; do
  [[ -n "$pkg" ]] || continue
  run=$((whole || node_pin))
  [[ -n "${PKG_SET[$pkg]+x}" ]] && run=1
  if ((!run)) && [[ ${#changed[@]} -gt 0 ]]; then
    triggers=("$pkg/")
    [[ -n "$facade" ]] && triggers+=("$facade")
    if [[ -f "$pkg/package.json" ]]; then
      while IFS= read -r dep; do
        [[ -n "$dep" ]] && triggers+=("$(normpath "$pkg/$dep")/")
      done < <(jq -r '[.dependencies, .devDependencies] | map(. // {}) | add | to_entries[]
          | select(.value | startswith("file:")) | .value | ltrimstr("file:")' "$pkg/package.json" | tr -d '\r')
    fi
    for f in "${changed[@]}"; do
      for t in "${triggers[@]}"; do
        if [[ "$t" == */ && "$f" == "$t"* ]] || [[ "$f" == "$t" ]]; then
          run=1
          break 2
        fi
      done
    done
  fi
  ((run)) && node_packages+="${node_packages:+ }$pkg"
done <<<"$packages"

# --- legs -------------------------------------------------------------------

# pack <lane> <budget> <cap> <force> <list> [<serial-list>]: the lane's legs,
# plan and needs. A suite on <serial-list> runs alone while the other suites run
# three at a time (scripts/run-plugin-tests.sh), so it weighs three times its
# seconds.
pack() {
  local lane="$1" budget="$2" cap="$3" force="$4" list="$5" serial="${6:-/dev/null}"
  awk -v def="$DEFAULT_SECONDS" '
    FILENAME == ARGV[1] { if ($0 !~ /^[[:blank:]]*(#|$)/) secs[$1] = $2; next }
    FILENAME == ARGV[2] { sub(/#.*/, ""); if (NF) alone[$1] = 1; next }
    NF { printf "%s\t%s\n", (($1 in secs) ? secs[$1] : def) * (($1 in alone) ? 3 : 1), $1 }' \
    "$SECONDS_LIST" "$serial" "$list" |
    LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k2,2 |
    awk -F '\t' -v lane="$lane" -v budget="$budget" -v cap="$cap" -v force="$force" '
      function need(p,   s) {
        s = ""
        # The animation wheels are also where the speech suites get numpy.
        if (p ~ /^plugins\/(animation|speech)\//) s = s " animation"
        if (p ~ /^plugins\/harness-ops\/skills\/inventory\//) s = s " inventory"
        if (p ~ /^plugins\/harness-ops\//) s = s " duckdb"
        return s
      }
      {
        if ($2 ~ /["\\]/) { print "plan-test-lanes: a suite path carries a quote or a backslash: " $2 > "/dev/stderr"; bad = 1; exit }
        n++; sec[n] = $1 + 0; path[n] = $2; total += $1
      }
      END {
        if (bad) exit 2
        if (n == 0) {
          printf "%s=false\n%s_legs=[0]\n%s_plan={}\n%s_needs={}\n", lane, lane, lane, lane
          printf "%s: nothing selected\n", lane > "/dev/stderr"
          exit 0
        }
        legs = int((total + budget - 1) / budget)
        if (force || legs > cap) legs = cap
        if (legs > n) legs = n
        if (legs < 1) legs = 1
        for (i = 1; i <= n; i++) {
          best = 0
          for (l = 1; l < legs; l++) if (load[l] < load[best]) best = l
          load[best] += sec[i]
          items[best] = items[best] (cnt[best]++ ? "," : "") "\"" path[i] "\""
          split(need(path[i]), w, " ")
          for (k in w) if (w[k] != "") has[best, w[k]] = 1
        }
        legsj = ""; planj = ""; needsj = ""; loads = ""
        for (l = 0; l < legs; l++) {
          s = ""
          if ((l, "animation") in has) s = s " animation"
          if ((l, "inventory") in has) s = s " inventory"
          if ((l, "duckdb") in has) s = s " duckdb"
          sub(/^ /, "", s)
          legsj = legsj (l ? "," : "") l
          planj = planj (l ? "," : "") "\"" l "\":[" items[l] "]"
          needsj = needsj (l ? "," : "") "\"" l "\":\"" s "\""
          loads = loads (l ? " " : "") load[l] "s/" cnt[l]
        }
        printf "%s=true\n%s_legs=[%s]\n%s_plan={%s}\n%s_needs={%s}\n", lane, lane, legsj, lane, planj, lane, needsj
        printf "%s: %d suite(s), %d suite-seconds, %d leg(s): %s\n", lane, n, total, legs, loads > "/dev/stderr"
      }' || die "planning the $lane legs failed"
}

pack bash 120 6 "$whole" "$WORK/bash" scripts/run-plugin-tests-serial.txt
pack python 180 4 0 "$WORK/python"
echo "node=$([[ -n "$node_packages" ]] && echo true || echo false)"
echo "node_packages=$node_packages"
echo "node: ${node_packages:-nothing selected}" >&2

# --- test-windows -----------------------------------------------------------

read_list::into rows "$WINDOWS_LIST" --comments inline || exit 2
declare -A KEY_ON=() JOB_ON=()
declare -a keys=() jobs=()
for row in "${rows[@]}"; do
  read -r job key pats <<<"$row"
  [[ -n "$key" ]] || die "$WINDOWS_LIST: '$row' names a job and no step key"
  # read -a splits without globbing, so a pattern stays a pattern.
  read -r -a patterns <<<"${pats:-$key}"
  [[ -n "${JOB_ON[$job]+x}" ]] || {
    JOB_ON["$job"]=0
    jobs+=("$job")
  }
  [[ -n "${KEY_ON[$key]+x}" ]] || {
    KEY_ON["$key"]=0
    keys+=("$key")
  }
  on="$whole_windows"
  if ((!on)); then
    for pat in "${patterns[@]}"; do
      while IFS= read -r s; do
        # shellcheck disable=SC2053 # the right-hand side is a glob on purpose.
        [[ -n "$s" && "$s" == $pat ]] && {
          on=1
          break 2
        }
      done <"$WORK/selection"
    done
  fi
  if ((on)); then
    KEY_ON["$key"]=1
    JOB_ON["$job"]=1
  fi
done
json_on() {
  local -n _set="$1"
  shift
  local json="" x
  for x in "$@"; do
    [[ "${_set[$x]}" == 1 ]] && json+="${json:+,}\"$x\""
  done
  printf '[%s]' "$json"
}
echo "windows_jobs=$(json_on JOB_ON "${jobs[@]}")"
echo "windows_steps=$(json_on KEY_ON "${keys[@]}")"
echo "test-windows: $(json_on JOB_ON "${jobs[@]}")" >&2
echo "unmapped=${unmapped:-0}"
