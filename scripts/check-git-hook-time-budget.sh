#!/usr/bin/env bash
# docs/adr/0072-place-each-check-by-coverage-cost-and-model-facing-output.md
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
base="" force=0 runs=3 budget_ms=3000

usage() {
  cat >&2 <<'EOF'
Time every pre-commit and pre-push entry the root lefthook.yml runs, on a throwaway
fixture repository (a 10-file staged change, then a two-commit push), and fail a hook
whose entries together take longer than its budget: ADR 0072, pre-commit 3 s on a
10-file commit, pre-push 3 s.

  scripts/check-git-hook-time-budget.sh [--base <ref> | --force] [--root <dir>]
                                        [--runs <n>] [--budget-ms <ms>]

  --base <ref>     run only when the diff from <ref> touches lefthook.yml, .lefthook/**,
                   plugins/*/git-hooks/**, a configured plugin's lib/git-hooks/**, an
                   asset its git-hooks/entries.json lists or this script; otherwise
                   report not applicable
  --force          run whatever the diff
  --root <dir>     the repository whose lefthook.yml is timed (default: this one)
  --runs <n>       runs per entry; an entry's time is the median (default 3)
  --budget-ms <ms> the budget of each hook (default 3000)

Each entry runs the way lefthook runs a remote's job: the remote's root is linked under
the fixture's .git/info/lefthook-remotes/, and the entry's script runs from there with
its runner and the fixture as the working directory. A pre-push entry gets the remote
name and URL as arguments and one pushed ref on stdin. A remote config outside this
checkout is named and not timed. Times print in seconds and in S, one no-op
`bash -c :` spawn measured in the same run (docs/contracts/hook-budget/README.md), so a
slow runner shows as a larger S; the pass/fail line is the budget in seconds.

Exit 0 within budget or not applicable, 1 over budget, 2 usage or setup error.
EOF
  exit 2
}

while (($#)); do
  case "$1" in
    --base) base="${2:-}" && shift ;;
    --force) force=1 ;;
    --root) ROOT="$(cd "${2:-}" && pwd)" || exit 2 && shift ;;
    --runs) runs="${2:-}" && shift ;;
    --budget-ms) budget_ms="${2:-}" && shift ;;
    *) usage ;;
  esac
  shift
done
[[ "$runs" =~ ^[1-9][0-9]*$ && "$budget_ms" =~ ^[1-9][0-9]*$ ]] || usage
((force)) || [[ -n "$base" ]] || usage

config="$ROOT/lefthook.yml"
[[ -f "$config" ]] || {
  echo "GIT HOOK TIME BUDGET: not applicable: $config does not exist."
  exit 0
}

configs=("lefthook.yml")
while IFS= read -r c; do
  if [[ -f "$ROOT/$c" ]]; then
    configs+=("$c")
  else
    echo "NOTICE: remote config $c is not in this checkout; its entries are not timed."
  fi
done < <(awk '/^remotes:/ { r = 1; next } /^[^ #]/ { r = 0 } r && /^[ \t]*-[ \t]+[^:# \t]+\.ya?ml[ \t]*$/ { print $NF }' "$config")

jobs_of() {
  awk -v cfg="$1" '
    function flush() {
      if (kind != "") printf "%s\t%s\t%s\t%s\t%s\t%s\n", cfg, ev, (name == "" ? val : name), runner, kind, val
      name = ""; runner = ""; kind = ""; val = ""
    }
    function value(line) { sub(/^[^:]*:[ \t]*/, "", line); gsub(/^["\047]|["\047][ \t]*$/, "", line); return line }
    /^[^ #]/ { flush(); ev = $0; sub(/:.*/, "", ev); next }
    ev != "pre-commit" && ev != "pre-push" { next }
    /^[ \t]*-[ \t]/ { flush(); sub(/-/, " ") }
    /^[ \t]+name:/ { name = value($0) }
    /^[ \t]+runner:/ { runner = value($0) }
    /^[ \t]+(script|run):/ { kind = ($0 ~ /^[ \t]+script:/ ? "script" : "run"); val = value($0) }
    END { flush() }
  ' "$ROOT/$1"
}

mapfile -t jobs < <(for c in "${configs[@]}"; do jobs_of "$c"; done)
if ((${#jobs[@]} == 0)); then
  echo "GIT HOOK TIME BUDGET: not applicable: lefthook.yml configures no pre-commit or pre-push entry."
  exit 0
fi

if ((! force)); then
  git -C "$ROOT" rev-parse --verify --quiet "$base^{commit}" >/dev/null || {
    echo "GIT HOOK TIME BUDGET: base $base is not a commit in this clone." >&2
    exit 2
  }
  watched=(lefthook.yml '.lefthook/*' 'plugins/*/git-hooks/*' scripts/check-git-hook-time-budget.sh)
  for c in "${configs[@]:1}"; do
    plugin="${c%/git-hooks/*}"
    [[ "$plugin" != "$c" ]] || continue
    watched+=("$plugin/lib/git-hooks/*")
    if [[ -f "$ROOT/$plugin/git-hooks/entries.json" ]] && command -v jq >/dev/null 2>&1; then
      while IFS= read -r a; do watched+=("$plugin/$a"); done < <(jq -r '.entries[].assets[]?' "$ROOT/$plugin/git-hooks/entries.json")
    fi
  done
  hit=""
  while IFS= read -r f; do
    for w in "${watched[@]}"; do
      # shellcheck disable=SC2053
      [[ "$f" == $w ]] && hit="$f" && break 2
    done
  done < <(git -C "$ROOT" diff --name-only "$base"...HEAD --)
  if [[ -z "$hit" ]]; then
    echo "GIT HOOK TIME BUDGET: not applicable: the change touches no git-hook config, hook script or script a hook entry calls."
    exit 0
  fi
  echo "GIT HOOK TIME BUDGET: $hit changed; timing the git-hook entries."
fi

now_us() { printf '%s' "${EPOCHREALTIME//[!0-9]/}"; }
median() { sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'; }
secs() { awk -v us="$1" 'BEGIN { printf "%.3f s", us / 1e6 }'; }
in_s() { awk -v us="$1" -v s="$S" 'BEGIN { printf "%.0f S", us / s }'; }

S="$(for _ in {1..21}; do t0=$(now_us) && bash -c : && echo $(($(now_us) - t0)); done | median)"
((S > 0)) || S=1

fx="$(mktemp -d)" || exit 2
trap 'rm -rf "$fx"' EXIT
g() { git -C "$fx" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main
mkdir -p "$fx/.git/no-hooks" "$fx/.git/info/lefthook-remotes" "$fx/docs/conventions"
g config core.hooksPath "$fx/.git/no-hooks"
ln -s "$ROOT" "$fx/.git/info/lefthook-remotes/repo"
find "$ROOT/docs/conventions" -maxdepth 1 -type f -exec cp {} "$fx/docs/conventions/" \; 2>/dev/null
printf 'fixture\n' >"$fx/README.md"
g add -A && g commit -q -m base || exit 2
base_sha="$(g rev-parse HEAD)"

write_file() {
  mkdir -p "$fx/${1%/*}"
  # shellcheck disable=SC2059
  for i in $(seq 1 120); do printf -- "$2\n" "$i" "$i"; done >"$fx/$1"
}
write_file src/one.sh 'value_%d="item-%d"'
write_file src/two.sh 'printf "%%s\\n" "line %d of %d"'
write_file src/three.py 'value_%d = "item-%d"'
write_file src/four.py 'print("line %d of %d")'
write_file src/five.js 'export const value%d = "item-%d";'
write_file src/six.ts 'export const total%d: number = %d;'
write_file docs/seven.md 'Line %d of the fixture guide, item %d.'
write_file docs/eight.md '- Item %d: the fixture lists entry %d.'
write_file config/nine.yml 'key_%d: value-%d'
write_file config/ten.json '"key_%d": %d,'
g add -A

run_entry() {
  local cfg=$1 runner=$2 kind=$3 val=$4 ev=$5 dir path
  shift 5
  if [[ "$kind" == run ]]; then
    sh -c "$val" "$ev" "$@"
    return
  fi
  dir="$fx/.git/info/lefthook-remotes/repo"
  [[ "$cfg" == lefthook.yml ]] && dir="$ROOT"
  path="$dir/.lefthook/$ev/$val"
  if [[ -n "$runner" ]]; then
    # shellcheck disable=SC2086
    $runner "$path" "$@"
  else
    "$path" "$@"
  fi
}

over=0
time_hook() {
  local ev=$1 what=$2 line cfg e name runner kind val us total=0 slow="" slow_us=0 rc
  shift 2
  local push_ref
  push_ref="refs/heads/main $(g rev-parse HEAD) refs/heads/main $base_sha"
  echo
  echo "$ev ($what), median of $runs run(s) per entry:"
  for line in "${jobs[@]}"; do
    IFS=$'\t' read -r cfg e name runner kind val <<<"$line"
    [[ "$e" == "$ev" ]] || continue
    rc=0
    us="$(for _ in $(seq 1 "$runs"); do
      t0=$(now_us)
      (cd "$fx" && run_entry "$cfg" "$runner" "$kind" "$val" "$ev" "$@" <<<"$push_ref") >"$fx/.git/entry.log" 2>&1 || echo "rc $?" >&2
      echo $(($(now_us) - t0))
    done 2>"$fx/.git/entry.rc" | median)"
    [[ -s "$fx/.git/entry.rc" ]] && rc="$(awk '{ print $2; exit }' "$fx/.git/entry.rc")"
    printf '  %-48s %9s  %7s  exit %s\n' "$name" "$(secs "$us")" "$(in_s "$us")" "$rc"
    if ((rc != 0)); then
      echo "    WARNING: $name exited $rc on the fixture, so its time may not cover a full run:"
      sed -n '1,5s/^/    | /p' "$fx/.git/entry.log"
    fi
    total=$((total + us))
    ((us > slow_us)) && slow_us=$us && slow=$name
  done
  if [[ -z "$slow" ]]; then
    echo "  no configured entry"
    return
  fi
  local budget_us=$((budget_ms * 1000))
  printf '  %-48s %9s  %7s  budget %s (%s)\n' total "$(secs "$total")" "$(in_s "$total")" "$(secs "$budget_us")" "$(in_s "$budget_us")"
  if ((total > budget_us)); then
    over=1
    echo "FAIL: $ev took $(secs "$total"), over its $(secs "$budget_us") budget (ADR 0072); slowest entry: $slow at $(secs "$slow_us"). Move a check over budget to the pre-PR check or CI, or make it faster."
  fi
}

echo "S, one no-op bash -c : spawn, median of 21: $(awk -v us="$S" 'BEGIN { printf "%.2f ms", us / 1e3 }')"
time_hook pre-commit "10 staged files"
g commit -q -m "fixture: ten files" || exit 2
printf 'one more line\n' >>"$fx/src/one.sh"
printf 'one more line\n' >>"$fx/docs/seven.md"
g commit -q -am "fixture: two edits" || exit 2
time_hook pre-push "2 pushed commits, 10 files" origin https://example.invalid/fixture.git

echo
if ((over)); then
  exit 1
fi
echo "GIT HOOK TIME BUDGET: every hook is within its budget."
