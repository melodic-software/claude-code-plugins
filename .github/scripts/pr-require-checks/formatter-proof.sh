#!/usr/bin/env bash
# Exit codes:
#   0  proof
#   1  no proof, each reason printed
#   2  usage error, or the proof could not run, which is no proof either
set -uo pipefail

usage() {
  cat <<'EOF'
usage: formatter-proof.sh [--classify] [--work-dir DIR] <base> <head>

Decide whether a change is the pinned formatters' output over its base: the
formatter-only proof that lets ci-status accept a pull request without the AI
review lanes (owner decision, row L438 of docs/owner-decisions.md in the org's
architecture repository).

Run inside a checkout whose object store holds <base>, a commit, and <head>, a
commit or tree (a pull request's test merge commit in CI). Every changed path
must be one of:
- an added changelog fragment, .changes/<plugin>/<name>.md, of at most 16384
  bytes, that the base's changelog_fragments::validate accepts, with bump
  patch or none, for a plugin holding a reproduced file;
- a registered copy (scripts/shared-copies.txt) or a file holding a block
  scripts/sync-hold-floor.py writes, regenerated from the formatted base;
- a shell file (*.sh, *.bash) an .editorconfig shell section governs, run
  through bash-format's shfmt_rewrite, its array-subscript guard included;
- a Python file (*.py, *.pyi) under a Ruff config, run through the
  python-format hook's two Ruff commands by scripts/run-ruff.sh.
The proof holds when re-running those formatters and regenerators over a
scratch worktree of <base> reproduces every changed path's head blob byte for
byte. Any other path, an added, deleted or renamed path, a mode change, a
formatter or tool that fails or is off its pin, or one differing byte is no
proof. Every formatter, regenerator and pin comes from <base>; <head> is read
as blob ids only, so none of its code runs.

--classify  stop after sorting the paths, before any tool runs: exit 0 says the
            change may be formatter-only, so the caller installs the tools
--work-dir  where the scratch worktree goes (default: $RUNNER_TEMP, else a temp
            directory); it is removed on exit
EOF
}

classify=0 work=""
while (($#)); do
  case $1 in
    --classify) classify=1 ;;
    --work-dir)
      work=${2:-}
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) break ;;
  esac
  shift
done
if (($# != 2)) || [[ -z $1 || -z $2 ]]; then
  usage >&2
  exit 2
fi
repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "formatter-proof: not inside a git checkout" >&2
  exit 2
}
if ! base=$(git -C "$repo" rev-parse --verify --quiet "$1^{commit}") ||
  ! head=$(git -C "$repo" rev-parse --verify --quiet "$2^{tree}"); then
  echo "formatter-proof: '$1' is not a commit or '$2' not a tree-ish here" >&2
  exit 2
fi

reasons=()
no() { reasons+=("$1"); }
fail_run() {
  echo "formatter-proof: $1; no proof" >&2
  exit 2
}
verdict() {
  local r
  if ((${#reasons[@]})); then
    echo "no proof: ${#reasons[@]} reason(s):"
    for r in "${reasons[@]:0:40}"; do echo "- $r"; done
    ((${#reasons[@]} <= 40)) || echo "- and $((${#reasons[@]} - 40)) more"
    exit 1
  fi
}

work=${work:-${RUNNER_TEMP:-}}
scratch=$(mktemp -d "${work:-${TMPDIR:-/tmp}}/formatter-proof.XXXXXX") || fail_run "no scratch directory"
tree="$scratch/tree"
cleanup() {
  if [[ -d $tree ]]; then
    git -C "$repo" worktree remove --force "$tree" >/dev/null 2>&1
    git -C "$repo" worktree prune >/dev/null 2>&1
  fi
  rm -rf "${scratch:?}"
}
trap cleanup EXIT

declare -A is_copy=()
while read -r _ copy _; do
  [[ -z $copy ]] || is_copy[$copy]=1
done < <(git -C "$repo" show "$base:scripts/shared-copies.txt" 2>/dev/null | grep -vE '^[[:space:]]*(#|$)')
holds_sync_hold_floor_block() {
  grep -qE '(^|[[:space:]#/])BEGIN (hold-floor|api-budget) ' < <(git -C "$repo" cat-file blob "$base:$1")
}

git -C "$repo" diff --raw -z --no-renames --no-abbrev "$base" "$head" >"$scratch/diff" || fail_run "could not diff $base and $head"
fragment_cap=16384
shell=() python=() regen=() fragments=()
declare -A want=() was=()
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  read -r old_mode new_mode old_blob new_blob status <<<"${meta#:}"
  if [[ $path == .changes/* ]]; then
    if [[ $status == A && $new_mode == 100644 && $path =~ ^\.changes/[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9._-]*\.md$ ]]; then
      size=$(git -C "$repo" cat-file -s "$new_blob") || fail_run "could not read $path"
      if ((size > fragment_cap)); then
        no "$path: a fragment of $size bytes, over the $fragment_cap-byte cap"
      else
        fragments+=("$path") want[$path]=$new_blob
      fi
    else
      no "$path: a change under .changes/ other than one added fragment .md file"
    fi
    continue
  fi
  if [[ $status != M ]]; then
    case $status in A) no "$path: added" ;; D) no "$path: deleted" ;; *) no "$path: changed as $status" ;; esac
    continue
  fi
  if [[ $old_mode != "$new_mode" || ($new_mode != 100644 && $new_mode != 100755) ]]; then
    no "$path: mode $old_mode to $new_mode"
    continue
  fi
  case $path in
    plugins/source-control/skills/babysit-prs/scripts/tests/* | scripts/lib/*.test.sh) ;;
    scripts/run-ruff.sh | scripts/sync-shared-copies.sh | scripts/sync-hold-floor.py | scripts/lib/* | \
      plugins/bash-format/git-hooks/* | plugins/source-control/skills/babysit-prs/scripts/*)
      no "$path: the proof runs this file, so a change to it needs review"
      continue
      ;;
    *) ;;
  esac
  want[$path]=$new_blob was[$path]=$old_blob
  if [[ -n ${is_copy[$path]:-} ]]; then
    regen+=("$path")
    continue
  fi
  case $path in
    .githooks/*) no "$path: neither formatter covers it, and no regenerator writes it" ;;
    *.sh | *.bash) shell+=("$path") ;;
    *.py | *.pyi) python+=("$path") ;;
    *)
      if holds_sync_hold_floor_block "$path"; then
        regen+=("$path")
      else
        no "$path: neither formatter covers it, and no regenerator writes it"
      fi
      ;;
  esac
done <"$scratch/diff"
((${#shell[@]} + ${#python[@]})) || no "no file the formatters cover changed"
verdict
if ((classify)); then
  echo "candidate: ${#shell[@]} shell, ${#python[@]} Python and ${#regen[@]} regenerated file(s), ${#fragments[@]} fragment(s)"
  exit 0
fi

git -C "$repo" worktree add --detach -q "$tree" "$base" >/dev/null 2>&1 || fail_run "could not check out $base"

shfmt_pin=$(sed -nE 's/^[[:space:]]*version=(v[0-9.]+)[[:space:]]*$/\1/p' "$tree/.github/actions/setup-pinned-shfmt/action.yml")
if ((${#shell[@]})); then
  [[ -n $shfmt_pin && $(shfmt --version 2>/dev/null) == "$shfmt_pin" ]] || fail_run "shfmt is not the base's pin ${shfmt_pin:-unknown}"
  # shellcheck source=../../../plugins/bash-format/git-hooks/shfmt-rewrite.sh
  . "$tree/plugins/bash-format/git-hooks/shfmt-rewrite.sh" || fail_run "the base's shfmt-rewrite.sh did not load"
fi

ruff_config() {
  local dir=${1%/*}
  [[ $dir == "$1" ]] && dir=.
  while :; do
    [[ -f $tree/$dir/.ruff.toml || -f $tree/$dir/ruff.toml ]] && return 0
    grep -qE '^[[:space:]]*\[tool\.ruff(\]|[.])' "$tree/$dir/pyproject.toml" 2>/dev/null && return 0
    [[ $dir == . ]] && return 1
    case $dir in */*) dir=${dir%/*} ;; *) dir=. ;; esac
  done
}

shfmt_lane() {
  local f err i
  cd "$tree" || exit 2
  for ((i = $1; i < ${#shell[@]}; i += $2)); do
    f=${shell[i]}
    shfmt_governed "$f" || {
      echo "reason: $f: no .editorconfig shell section governs it, so shfmt does not format it"
      continue
    }
    err=$(shfmt --apply-ignore "$f" 2>&1 >/dev/null) || {
      echo "failed: $f: shfmt failed: ${err%%$'\n'*}"
      continue
    }
    shfmt_rewrite "$f"
  done
  [[ -z ${SHFMT_NOTE:-} ]] || echo "note: $SHFMT_NOTE"
}
lanes=$(nproc 2>/dev/null) && [[ $lanes =~ ^[1-9][0-9]*$ ]] || lanes=2
((lanes <= 8)) || lanes=8
pids=()
for ((l = 0; l < lanes; l++)); do
  shfmt_lane "$l" "$lanes" >"$scratch/shfmt.$l.log" 2>&1 &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid" || echo "failed: an shfmt lane exited non-zero" >>"$scratch/shfmt.0.log"; done
cat "$scratch"/shfmt.*.log >"$scratch/run.log"
(
  cd "$tree" || exit 2
  py=()
  for f in ${python[@]+"${python[@]}"}; do
    if ruff_config "$f"; then py+=("$f"); else echo "reason: $f: no Ruff config governs it"; fi
  done
  if ((${#py[@]})); then
    ruff=(bash "$tree/scripts/run-ruff.sh")
    out=$("${ruff[@]}" check --fix-only --fixable I --no-unsafe-fixes --force-exclude --no-cache --quiet -- "${py[@]}" 2>&1) ||
      echo "failed: ruff check --fix-only failed: ${out%%$'\n'*}"
    out=$("${ruff[@]}" format --force-exclude --no-cache --quiet -- "${py[@]}" 2>&1) ||
      echo "failed: ruff format failed: ${out%%$'\n'*}"
  fi
  out=$(bash scripts/sync-shared-copies.sh 2>&1) || echo "failed: scripts/sync-shared-copies.sh failed: ${out%%$'\n'*}"
  out=$(python3 -I scripts/sync-hold-floor.py 2>&1) || echo "failed: scripts/sync-hold-floor.py failed: ${out%%$'\n'*}"
) >>"$scratch/run.log" 2>&1
paths=(${shell[@]+"${shell[@]}"} ${python[@]+"${python[@]}"} ${regen[@]+"${regen[@]}"})
for f in ${fragments[@]+"${fragments[@]}"}; do
  { mkdir -p "$tree/${f%/*}" && git -C "$repo" cat-file blob "${want[$f]}" >"$tree/$f"; } || fail_run "could not write $f"
done
(
  cd "$tree" || exit 2
  ((${#fragments[@]})) || exit 0
  unset CF_LIST
  # shellcheck source=../../../scripts/lib/changelog-fragments.sh
  . scripts/lib/changelog-fragments.sh || {
    echo "failed: the base's changelog-fragments.sh did not load"
    exit 0
  }
  for f in "${fragments[@]}"; do
    err=$(changelog_fragments::validate "$f" 2>&1 >/dev/null)
    case $? in
      0) ;;
      1)
        echo "reason: $f: the base's fragment validator refuses it: ${err%%$'\n'*}"
        continue
        ;;
      *)
        echo "failed: the base's fragment validator could not check $f"
        continue
        ;;
    esac
    bump=$(changelog_fragments::bump_of "$f")
    [[ $bump == patch || $bump == none ]] || echo "reason: $f: bump: $bump, past the patch a formatter-only change may release"
    plugin=${f#.changes/} plugin=${plugin%%/*}
    root=$(changelog_fragments::root_of "$plugin")
    for p in ${paths[@]+"${paths[@]}"}; do [[ $p == "$root"/* ]] && continue 2; done
    echo "reason: $f: no reproduced file belongs to $plugin"
  done
) >>"$scratch/run.log" 2>&1
while IFS= read -r line; do
  case $line in
    'failed: '*) fail_run "${line#failed: }" ;;
    'note: '*) echo "${line#note: }" ;;
    'reason: '*) no "${line#reason: }" ;;
    '') ;;
    *) fail_run "unexpected output: $line" ;;
  esac
done <"$scratch/run.log"

mapfile -t got < <(cd "$tree" && printf '%s\n' "${paths[@]}" | git hash-object --stdin-paths) || fail_run "could not hash the formatted files"
((${#got[@]} == ${#paths[@]})) || fail_run "hashed ${#got[@]} of ${#paths[@]} formatted files"
for i in "${!paths[@]}"; do
  p=${paths[i]}
  [[ ${got[i]} == "${want[$p]}" ]] && continue
  if [[ ${got[i]} == "${was[$p]}" ]]; then
    no "$p: the formatters leave the base as it is, but the head changes it"
  else
    no "$p: the formatted base differs from the head"
  fi
done
verdict
echo "proof: ${#paths[@]} file(s) reproduced byte for byte (${#shell[@]} shfmt, ${#python[@]} Ruff, ${#regen[@]} regenerated); ${#fragments[@]} changelog fragment(s) accepted"
