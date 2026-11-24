#!/usr/bin/env bash
# docs/adr/0072-place-each-check-by-coverage-cost-and-model-facing-output.md
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
# shellcheck source=lib/gate-entry.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/gate-entry.sh" || exit 2
base="" force=0 scope_only=0 runs=3 budget_ms=3000 ref_ms="" ref_host_ms=1000 ref_files=400
parts_host_ms="307 46 40" share_commit="0.26 0.37 0.37" share_push="0 0.5 0.5"
desk_commit_ms=1934 desk_push_ms=1207 zero=0000000000000000000000000000000000000000

usage() {
  cat >&2 <<'EOF'
Time every pre-commit and pre-push entry that the root lefthook.yml and every shipped
plugins/*/git-hooks/*.yml config hold, and fail a hook whose entries that ran together
take longer than its budget: ADR 0072, pre-commit 3 s on a 10-file commit, pre-push 3 s.
pre-commit runs on a throwaway fixture repository with 10 staged files. pre-push runs on
the real checkout, whose size its entries' cost grows with: HEAD pushed as a new
non-default branch, ranged from origin/main.

The budget is calibrated per hook, so a slower runner does not flake: three reference
parts that run none of the hooks' code and do not grow with the repository are timed in
the same run, median of 5 each: pwsh (one start compiling a one-line type with Add-Type,
since a bare start misses the assembly load and JIT the hooks pay, without timing a tool
the hooks run), starts (bare python3, node, bash, git) and files (git status over a
generated 400-file tree, one node process reading and parsing it). Their values on the
host that set the budget are 307, 46 and 40 ms (Linux on WSL2, 24 CPUs, 2026-11-24, median
of five runs), which put pre-commit at 1934 ms and pre-push at 1207 ms, HEAD one commit
past origin/main. A hook's reference ratio weights each part's ratio to that host by the
share of the hook's own time that kind of work takes on it: pre-commit 0.26 pwsh, 0.37
starts, 0.37 files; pre-push 0.5 starts, 0.5 files, no pwsh. Its scaled budget is 3 s x
that ratio. Every run prints the hooks' own ratio (total / desk total) beside the
reference ratio; in CI it warns when they differ by over 30%. Raw seconds, the ratio and
the scaled budget all print; pass/fail is on the scaled budget.
Under a tracer (TracerPid not 0) the times print and nothing is judged.

The fixture sets checks.skipmissing (ADR 0072 item 4) to every tool the entries.json
files name, so an entry whose tool is not installed reports SKIPPED. Locally it is
listed as skipped with the tool, outside the total; under GITHUB_ACTIONS=true it fails
the gate with the tool's name, since CI installs every hook tool first.

  scripts/check-git-hook-time-budget.sh [--base <ref> | --force] [--root <dir>]
                                        [--runs <n>] [--budget-ms <ms>] [--scope-only]
                                        [--ref-ms <ms>] [--ref-host-ms <ms>]

  --base <ref>     run only when the diff from <ref> touches lefthook.yml, .lefthook/**,
                   plugins/*/git-hooks/**, a hook plugin's lib/git-hooks/**, an asset
                   its git-hooks/entries.json lists or this script, or adds or removes
                   a plugins/*/.claude-plugin/plugin.json; otherwise report not
                   applicable
  --force          run whatever the diff
  --root <dir>     the repository whose hook entries are timed (default: this one)
  --runs <n>       runs per entry; an entry's time is the median (default 3)
  --budget-ms <ms> the budget of each hook on the reference host (default 3000)
  --ref-ms <ms>    time no reference: both hooks' ratio is <ms> / --ref-host-ms
  --ref-host-ms <ms> the divisor for --ref-ms (default 1000)
  --scope-only     time nothing: print applies=true or applies=false on stdout (the
                   form GITHUB_OUTPUT takes), every other line on stderr

Each entry runs the way lefthook runs a remote's job: the remote's root is linked under
the fixture's .git/info/lefthook-remotes/, and the entry's script runs from there with
its runner. A pre-push entry gets the remote name and URL as arguments and the pushed
ref on stdin; a run: command gets lefthook's {1} and {2} filled and a relative command
resolved against the repository. Every pre-commit run starts from the same staged files,
so a formatter's rewrite does not carry over between runs; a group with piped: true runs
its members in order on one staged state, as lefthook does, and is timed as one unit.

S, one no-op `bash -c :` spawn measured in the same run
(docs/contracts/hook-budget/README.md), also prints.

Under GITHUB_ACTIONS=true, a pre-push entry that exits non-zero or prints "left to CI"
or "was not checked" fails the gate: the pushed-and-passing run must execute every check.
Locally it is a warning.

Exit 0 within budget or not applicable, 1 over budget, a tool missing in CI or an entry
that could not start (exit 126 or 127), 2 usage or setup error. Findings print on stderr.
EOF
  exit 2
}

while (($#)); do
  case "$1" in
    --base) base="${2:-}" && shift ;;
    --force) force=1 ;;
    --scope-only) scope_only=1 ;;
    --root) ROOT="$(cd "${2:-}" && pwd)" || exit 2 && shift ;;
    --runs) runs="${2:-}" && shift ;;
    --budget-ms) budget_ms="${2:-}" && shift ;;
    --ref-ms) ref_ms="${2:-}" && shift ;;
    --ref-host-ms) ref_host_ms="${2:-}" && shift ;;
    *) usage ;;
  esac
  shift
done
[[ "$runs" =~ ^[1-9][0-9]*$ && "$budget_ms" =~ ^[1-9][0-9]*$ && "$ref_host_ms" =~ ^[1-9][0-9]*$ ]] || usage
[[ -z "$ref_ms" || "$ref_ms" =~ ^[1-9][0-9]*$ ]] || usage
((force)) || [[ -n "$base" ]] || usage
if ((scope_only)); then
  exec 3>&1 1>&2
fi
not_applicable() {
  echo "GIT HOOK TIME BUDGET: not applicable: $1"
  ((scope_only)) && echo applies=false >&3
  exit 0
}

config="$ROOT/lefthook.yml"
[[ -f "$config" ]] || not_applicable "$config does not exist."

configs=("lefthook.yml")
for c in "$ROOT"/plugins/*/git-hooks/*.yml; do
  [[ -f "$c" ]] && configs+=("${c#"$ROOT"/}")
done

jobs_of() {
  awk -v cfg="$1" '
    function flush() {
      if (kind != "") printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", cfg, ev, (name == "" ? val : name), runner, kind, val, (gind >= 0 ? cfg ":" gname : ""), piped
      name = ""; runner = ""; kind = ""; val = ""
    }
    function value(line) { sub(/^[^:]*:[ \t]*/, "", line); gsub(/^["\047]|["\047][ \t]*$/, "", line); return line }
    BEGIN { gind = -1; piped = 0 }
    /^[^ #]/ { flush(); ev = $0; sub(/:.*/, "", ev); gind = -1; piped = 0; next }
    ev != "pre-commit" && ev != "pre-push" { next }
    /^[ \t]*-[ \t]/ {
      flush(); match($0, /^[ \t]*/); item = RLENGTH
      if (gind >= 0 && item <= gind) { gind = -1; piped = 0 }
      sub(/-/, " ")
    }
    /^[ \t]+group:/ { gname = name; gind = item; piped = 0; name = ""; next }
    /^[ \t]+piped:[ \t]*true/ { if (gind >= 0) piped = 1 }
    /^[ \t]+name:/ { name = value($0) }
    /^[ \t]+runner:/ { runner = value($0) }
    /^[ \t]+(script|run):/ { kind = ($0 ~ /^[ \t]+script:/ ? "script" : "run"); val = value($0) }
    END { flush() }
  ' "$ROOT/$1"
}

mapfile -t jobs < <(for c in "${configs[@]}"; do jobs_of "$c"; done)
if ((${#jobs[@]} == 0)); then
  not_applicable "no hook config holds a pre-commit or pre-push entry."
fi

if ((! force)); then
  (cd "$ROOT" && gate_entry::require_base "$base" "GIT HOOK TIME BUDGET: base $base is not a commit in this clone.")
  watched=(lefthook.yml '.lefthook/*' 'plugins/*/git-hooks/*' scripts/check-git-hook-time-budget.sh)
  for c in "${configs[@]:1}"; do
    plugin="${c%/git-hooks/*}"
    [[ "$plugin" != "$c" ]] || continue
    watched+=("$plugin/lib/git-hooks/*")
    if [[ -f "$ROOT/$plugin/git-hooks/entries.json" ]] && command -v jq >/dev/null 2>&1; then
      while IFS= read -r a; do watched+=("$plugin/$a"); done < <(jq -r '.entries[].assets[]?' "$ROOT/$plugin/git-hooks/entries.json")
    fi
  done
  queue=()
  for line in "${jobs[@]}"; do
    IFS=$'\037' read -r cfg _ _ _ kind val _ <<<"$line"
    [[ "$cfg" == lefthook.yml && "$kind" == run ]] || continue
    first=${val%% *}
    [[ -f "$ROOT/$first" ]] && queue+=("$first")
  done
  declare -A seen=()
  while ((${#queue[@]})); do
    f=${queue[0]}
    queue=("${queue[@]:1}")
    [[ -z "${seen[$f]:-}" ]] || continue
    seen[$f]=1
    watched+=("$f")
    while IFS= read -r token; do
      while [[ -n "$token" ]]; do
        if [[ -f "$ROOT/${f%/*}/$token" ]]; then
          queue+=("$(realpath -m --relative-to="$ROOT" "$ROOT/${f%/*}/$token")")
          break
        elif [[ -f "$ROOT/$token" ]]; then
          queue+=("$(realpath -m --relative-to="$ROOT" "$ROOT/$token")")
          break
        fi
        [[ "$token" == */* ]] || break
        token=${token#*/}
      done
    done < <(sed -E -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*(echo|printf)[[:space:]]/d' -e 's/[[:space:]]#.*//' "$ROOT/$f" |
      grep -oE '[A-Za-z0-9_./-]+\.(sh|mjs|py|awk)' | sort -u)
  done
  hit=""
  while IFS=$'\t' read -r status f; do
    if [[ "$status" == [AD] && "$f" == plugins/*/.claude-plugin/plugin.json ]]; then
      hit="$f" && break
    fi
    for w in "${watched[@]}"; do
      # shellcheck disable=SC2053
      [[ "$f" == $w ]] && hit="$f" && break 2
    done
  done < <(git -C "$ROOT" diff --no-renames --name-status "$base"...HEAD --)
  if [[ -z "$hit" ]]; then
    not_applicable "the change touches no git-hook config, hook script or script a hook entry calls, and adds or removes no plugin."
  fi
  echo "GIT HOOK TIME BUDGET: $hit changed; timing the git-hook entries."
fi
if ((scope_only)); then
  echo applies=true >&3
  exit 0
fi

now_us() { printf '%s' "${EPOCHREALTIME//[!0-9]/}"; }
median() { sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'; }
secs() { awk -v us="$1" 'BEGIN { printf "%.3f s", us / 1e6 }'; }
in_s() { awk -v us="$1" -v s="$S" 'BEGIN { printf "%.0f S", us / s }'; }

S="$(for _ in {1..21}; do t0=$(now_us) && bash -c : && echo $(($(now_us) - t0)); done | median)"
((S > 0)) || S=1

fx="$(mktemp -d)" || exit 2
refdir="$(mktemp -d)" || exit 2
trap 'rm -rf "$fx" "$refdir"' EXIT

part_pwsh() {
  pwsh -NoProfile -NonInteractive -Command "Add-Type -TypeDefinition 'public static class A { public static int F() { return 1; } }'" >/dev/null
}
part_starts() {
  python3 -c 0
  node -e 0
  bash -c :
  git --version >/dev/null
}
part_files() {
  git -C "$refdir" status --porcelain --untracked-files=all >/dev/null
  node -e '
    const fs = require("fs");
    let n = 0;
    for (const e of fs.readdirSync(process.argv[1], { recursive: true, withFileTypes: true }))
      if (e.isFile()) n += JSON.stringify(JSON.parse(fs.readFileSync(e.parentPath + "/" + e.name, "utf8"))).length;
    process.stdout.write(String(n));
  ' "$refdir/tree" >/dev/null
}
ratio_of() {
  awk -v s="$1" -v m="${parts_ms[*]}" -v h="$parts_host_ms" 'BEGIN {
    split(s, a, " "); split(m, b, " "); split(h, c, " ")
    for (i = 1; i <= 3; i++) r += a[i] * b[i] / c[i]
    printf "%.4f", r
  }'
}
if [[ -n "$ref_ms" ]]; then
  ratio_commit="$(awk -v a="$ref_ms" -v b="$ref_host_ms" 'BEGIN { printf "%.4f", a / b }')"
  ratio_push=$ratio_commit
  ref_line="reference workload: $ref_ms ms; reference host: $ref_host_ms ms; ratio $(awk -v r="$ratio_commit" 'BEGIN { printf "%.2f", r }') for both hooks"
else
  for tool in pwsh python3 node; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "GIT HOOK TIME BUDGET: $tool is not installed, so the reference workload cannot run." >&2
      exit 2
    }
  done
  git init -q "$refdir"
  mkdir -p "$refdir/tree"
  for ((i = 0; i < ref_files; i++)); do
    printf '{"name": "item-%d", "lines": ["one", "two", "three"], "n": %d}\n' "$i" "$i" >"$refdir/tree/$((i % 20))-$i.json"
  done
  : >"$refdir/pwsh" && : >"$refdir/starts" && : >"$refdir/files"
  for _ in 1 2 3 4 5; do
    for p in pwsh starts files; do
      t0=$(now_us)
      "part_$p"
      echo $((($(now_us) - t0) / 1000)) >>"$refdir/$p"
    done
  done
  parts_ms=("$(median <"$refdir/pwsh")" "$(median <"$refdir/starts")" "$(median <"$refdir/files")")
  ratio_commit="$(ratio_of "$share_commit")"
  ratio_push="$(ratio_of "$share_push")"
  read -r h_pwsh h_starts h_files <<<"$parts_host_ms"
  ref_line="reference workload: $((parts_ms[0] + parts_ms[1] + parts_ms[2])) ms: pwsh ${parts_ms[0]} ms (desk $h_pwsh), starts ${parts_ms[1]} ms (desk $h_starts), files ${parts_ms[2]} ms (desk $h_files), median of 5 each"
fi
limit_of() { awk -v b="$budget_ms" -v r="$1" 'BEGIN { printf "%.0f", b * 1000 * r }'; }
tracer="$(awk '/^TracerPid:/ { print $2 }' /proc/$$/status 2>/dev/null)"
g() { git -C "$fx" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main
mkdir -p "$fx/.git/no-hooks" "$fx/.git/info/lefthook-remotes" "$fx/docs/conventions"
g config core.hooksPath "$fx/.git/no-hooks"
tools="$(cat "$ROOT"/plugins/*/git-hooks/entries.json 2>/dev/null | jq -rs '[.[].entries[].tools[]?] + ["pygments"] | unique | join(",")' 2>/dev/null)"
g config checks.skipmissing "${tools:-pygments}"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=checks.skipmissing GIT_CONFIG_VALUE_0="${tools:-pygments}"
ln -s "$ROOT" "$fx/.git/info/lefthook-remotes/repo"
find "$ROOT/docs/conventions" -maxdepth 1 -type f -exec cp {} "$fx/docs/conventions/" \; 2>/dev/null
for f in .editorconfig .shellcheckrc _typos.toml ruff.toml biome.json .markdownlint-cli2.jsonc PSScriptAnalyzerSettings.psd1; do
  [[ -f "$ROOT/$f" ]] && cp "$ROOT/$f" "$fx/$f"
done
[[ -f "$fx/ruff.toml" ]] || : >"$fx/ruff.toml"
[[ -f "$fx/biome.json" ]] || echo '{}' >"$fx/biome.json"
[[ -f "$fx/.markdownlint-cli2.jsonc" ]] || echo '{}' >"$fx/.markdownlint-cli2.jsonc"
[[ -f "$fx/PSScriptAnalyzerSettings.psd1" ]] || echo '@{}' >"$fx/PSScriptAnalyzerSettings.psd1"
printf 'fixture\n' >"$fx/README.md"
g add -A && g commit -q -m base || exit 2
base_sha="$(g rev-parse HEAD)"
g update-ref refs/remotes/origin/main "$base_sha"
g symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

write_file() {
  mkdir -p "$fx/${1%/*}"
  {
    [[ -z "$3" ]] || printf '%s\n' "$3"
    # shellcheck disable=SC2059
    for i in $(seq 1 120); do printf -- "$2\n" "$i" "$i"; done
    [[ -z "${4:-}" ]] || printf '%s\n' "$4"
  } >"$fx/$1"
}
write_file src/one.sh 'echo "value %d of %d"' '#!/usr/bin/env bash'
write_file src/two.sh 'printf "%%s\\n" "line %d of %d"' '#!/usr/bin/env bash'
write_file src/three.py 'print("line %d of %d")' ''
write_file src/four.js 'export const value%d = "item-%d";' ''
write_file src/five.ts 'export const total%d: number = %d;' ''
write_file src/six.go 'var value%d = "item-%d"' 'package fixture'
write_file src/seven.ps1 "Write-Output 'line %d of %d'" ''
write_file docs/eight.md '- Item %d: the fixture lists entry %d.' $'# Fixture list\n'
write_file docs/nine.md 'Line %d of the fixture guide, item %d.' $'# Fixture guide\n'
write_file config/ten.json '  "key_%d": %d,' '{' '  "end": 0
}'
g add -A

run_entry() {
  local cfg=$1 runner=$2 kind=$3 val=$4 ev=$5 dir path
  shift 5
  if [[ "$kind" == run ]]; then
    local i=1 a first=${val%% *}
    for a in "$@"; do
      val=${val//"{$i}"/$a}
      i=$((i + 1))
    done
    [[ "$first" != /* && -e "$ROOT/$first" ]] && val="$ROOT/$val"
    sh -c "$val" "$ev" "$@"
    return
  fi
  dir="$fx/.git/info/lefthook-remotes/repo"
  [[ "$cfg" == lefthook.yml ]] && dir="$ROOT"
  path="$dir/.lefthook/$ev/$val"
  [[ -f "$path" ]] || {
    echo "no such script: .lefthook/$ev/$val" >&2
    return 127
  }
  if [[ -n "$runner" ]]; then
    # shellcheck disable=SC2086
    $runner "$path" "$@"
  else
    "$path" "$@"
  fi
}

over=0
counted=0
judge_entry() {
  local k=$1 name=$2 ev=$3 log="$fx/.git/m$1.log" rc=0 us missing
  counted=0
  us="$(median <"$fx/.git/m$k.us")"
  [[ -s "$fx/.git/m$k.rc" ]] && rc="$(head -n 1 "$fx/.git/m$k.rc")"
  missing="$(sed -n 's/.*SKIPPED: \(.*\) (missing).*/\1/p; s/.*NOTICE: \([^ ]*\) missing.*/\1/p' "$log" | head -n 1)"
  if [[ -n "$missing" && "${GITHUB_ACTIONS:-}" == true ]]; then
    printf '  %-48s %9s  FAIL: %s is not installed on this runner\n' "$name" - "$missing" >&2
    over=1
    return
  elif [[ -n "$missing" ]]; then
    printf '  %-48s %9s  skipped: %s is not installed\n' "$name" - "$missing"
    return
  fi
  printf '  %-48s %9s  %7s  exit %s\n' "$name" "$(secs "$us")" "$(in_s "$us")" "$rc"
  if ((rc == 126 || rc == 127)); then
    echo "FAIL: $name could not start (exit $rc), so its time was not measured:" >&2
    sed -n '1,5s/^/    | /p' "$log" >&2
    over=1
    return
  elif [[ "$ev" == pre-push ]] && { ((rc != 0)) || grep -qE 'left to CI|was not checked' "$log"; }; then
    if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
      echo "FAIL: $name did not run every check on the pushed range (exit $rc):" >&2
      sed -n '1,5s/^/    | /p' "$log" >&2
      over=1
    else
      echo "    WARNING: $name did not run every check on the pushed range (exit $rc); in CI this fails:"
      sed -n '1,5s/^/    | /p' "$log"
    fi
  elif ((rc != 0)); then
    echo "    WARNING: $name exited $rc on the fixture, so its time may not cover a full run:"
    sed -n '1,5s/^/    | /p' "$log"
  fi
  counted=1
}

time_hook() {
  local ev=$1 what=$2 repo=$3 line cfg e name runner kind val grp piped g2 total=0 slow="" slow_us=0 tree="" push_ref
  local i j k n unit_us unit_name
  local -a rows=() parts
  shift 3
  [[ "$repo" == "$fx" ]] && tree="$(g write-tree)"
  push_ref="refs/heads/hook-budget-check $(git -C "$repo" rev-parse HEAD) refs/heads/hook-budget-check $zero"
  echo
  echo "$ev ($what), median of $runs run(s) per entry; a piped group runs its members in order on one staged state:"
  for line in "${jobs[@]}"; do
    IFS=$'\037' read -r _ e _ <<<"$line"
    [[ "$e" == "$ev" ]] && rows+=("$line")
  done
  n=${#rows[@]}
  i=0
  while ((i < n)); do
    IFS=$'\037' read -r _ _ name _ _ _ grp piped <<<"${rows[i]}"
    j=$((i + 1))
    if [[ -n "$grp" && "$piped" == 1 ]]; then
      while ((j < n)); do
        IFS=$'\037' read -r _ _ _ _ _ _ g2 _ <<<"${rows[j]}"
        [[ "$g2" == "$grp" ]] || break
        j=$((j + 1))
      done
    fi
    for ((k = i; k < j; k++)); do : >"$fx/.git/m$k.us" && : >"$fx/.git/m$k.rc"; done
    for _ in $(seq 1 "$runs"); do
      [[ -z "$tree" ]] || { g read-tree "$tree" && g checkout-index -a -f; }
      for ((k = i; k < j; k++)); do
        IFS=$'\037' read -r cfg _ name runner kind val _ <<<"${rows[k]}"
        t0=$(now_us)
        (cd "$repo" && run_entry "$cfg" "$runner" "$kind" "$val" "$ev" "$@" <<<"$push_ref") >"$fx/.git/m$k.log" 2>&1 || echo "$?" >>"$fx/.git/m$k.rc"
        echo $(($(now_us) - t0)) >>"$fx/.git/m$k.us"
      done
    done
    ((j - i > 1)) && echo "  group ${grp#*:} (piped):"
    parts=()
    for ((k = i; k < j; k++)); do
      IFS=$'\037' read -r _ _ name _ <<<"${rows[k]}"
      judge_entry "$k" "$name" "$ev"
      ((counted)) && parts+=("$fx/.git/m$k.us")
    done
    if ((${#parts[@]})); then
      unit_us="$(paste "${parts[@]}" | awk '{ s = 0; for (f = 1; f <= NF; f++) s += $f; print s }' | median)"
      unit_name=$name
      if ((j - i > 1)); then
        unit_name="group ${grp#*:}"
        printf '  %-48s %9s  %7s\n' "$unit_name total" "$(secs "$unit_us")" "$(in_s "$unit_us")"
      fi
      total=$((total + unit_us))
      ((unit_us > slow_us)) && slow_us=$unit_us && slow=$unit_name
    fi
    i=$j
  done
  if [[ -z "$slow" ]]; then
    echo "  no entry ran"
    return
  fi
  local desk_ms=$desk_commit_ms ratio=$ratio_commit limit_us
  [[ "$ev" == pre-push ]] && desk_ms=$desk_push_ms && ratio=$ratio_push
  limit_us="$(limit_of "$ratio")"
  printf '  %-48s %9s  %7s\n' total "$(secs "$total")" "$(in_s "$total")"
  awk -v t="$total" -v d="$desk_ms" -v ref="$ratio" -v l="$limit_us" -v ev="$ev" -v ci="${GITHUB_ACTIONS:-}" 'BEGIN {
    hooks = t / 1000 / d
    printf "  reference ratio %.2f; scaled budget %.3f s; hooks ratio %.2f (this total / desk total %d ms)\n", ref, l / 1e6, hooks, d
    if (ci == "true" && (hooks > ref * 1.3 || ref > hooks * 1.3))
      printf "::warning title=git-hook reference drift::%s hooks ratio %.2f and reference ratio %.2f differ by more than 30%%; the reference may not track what the hooks pay.\n", ev, hooks, ref
  }'
  if [[ -n "$tracer" && "$tracer" != 0 ]]; then
    echo "  not judged: a tracer (pid $tracer) slows every syscall"
  elif ((total > limit_us)); then
    over=1
    echo >&2 "FAIL: $ev took $(secs "$total"), over its scaled budget of $(secs "$limit_us") ($budget_ms ms x reference ratio $(awk -v r="$ratio" 'BEGIN { printf "%.2f", r }'); ADR 0072); slowest entry: $slow at $(secs "$slow_us"). Optimize it first; move it to CI only if it still risks the budget."
  fi
}

echo "S, one no-op bash -c : spawn, median of 21: $(awk -v us="$S" 'BEGIN { printf "%.2f ms", us / 1e3 }')"
echo "$ref_line"
time_hook pre-commit "10 staged files on the fixture" "$fx"
pp_remote="$(git -C "$ROOT" remote get-url origin 2>/dev/null || echo https://example.invalid/repo.git)"
time_hook pre-push "HEAD of the real checkout as a new branch" "$ROOT" origin "$pp_remote"

echo
if ((over)); then
  exit 1
fi
echo "GIT HOOK TIME BUDGET: every hook is within its budget."
