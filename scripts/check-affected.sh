#!/usr/bin/env bash
set -uo pipefail

usage() {
  echo "usage: $(basename "$0") [--tests] [--jobs N] [--budget S] [--base <ref>] [--no-fetch] [--uncommitted]" >&2
  exit 2
}

run_tests=0
mem_free_kib() {
  local free dir="${CHECK_AFFECTED_CGROUP_DIR:-/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)}" max cur inactive
  free="$(awk '/^MemAvailable:/ { print $2 }' "${CHECK_AFFECTED_MEMINFO:-/proc/meminfo}" 2>/dev/null)"
  [[ "$free" =~ ^[0-9]+$ ]] || return 1
  while [[ -n "$dir" ]]; do
    if [[ -r "$dir/memory.max" && -r "$dir/memory.current" ]]; then
      max="$(<"$dir/memory.max")" cur="$(<"$dir/memory.current")"
      inactive="$(awk '$1 == "inactive_file" { print $2 }' "$dir/memory.stat" 2>/dev/null)"
      if [[ "$max" =~ ^[0-9]+$ && "$cur" =~ ^[0-9]+$ ]]; then
        cur=$(((max - cur + ${inactive:-0}) / 1024))
        ((cur >= free)) || free=$((cur > 0 ? cur : 0))
      fi
    fi
    [[ "${dir%/*}" != "$dir" ]] || break
    dir="${dir%/*}"
  done
  echo "$free"
}
cores="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
[[ "$cores" =~ ^[1-9][0-9]*$ ]] || cores=2
jobs=$((cores > 1 ? cores - 1 : 1))
((jobs <= 8)) || jobs=8
if free_kib="$(mem_free_kib)"; then
  mem_jobs=$((free_kib / (2 * 1024 * 1024)))
  ((mem_jobs >= 1)) || mem_jobs=1
  ((jobs <= mem_jobs)) || jobs=$mem_jobs
fi
jobs="${CHECK_AFFECTED_JOBS:-$jobs}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || jobs=1
budget="${CHECK_AFFECTED_BUDGET:-120}"
[[ "$budget" =~ ^[1-9][0-9]*$ ]] || budget=120
fetch=1
uncommitted=0
base=
while (($#)); do
  case "$1" in
  --tests) run_tests=1 ;;
  --no-fetch) fetch=0 ;;
  --uncommitted) uncommitted=1 ;;
  --jobs)
    [[ $# -ge 2 ]] || usage
    jobs="$2"
    shift
    ;;
  --jobs=*) jobs="${1#--jobs=}" ;;
  --budget)
    [[ $# -ge 2 ]] || usage
    budget="$2"
    shift
    ;;
  --budget=*) budget="${1#--budget=}" ;;
  --base)
    [[ $# -ge 2 && -n "$2" ]] || usage
    base="$2"
    shift
    ;;
  *) usage ;;
  esac
  shift
done
[[ "$jobs" =~ ^[1-9][0-9]*$ && "$budget" =~ ^[1-9][0-9]*$ ]] || usage

tools="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)" || exit 2
top="$(git -C "${CHECK_DATA_ROOT:-$tools}" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "check-affected: ${CHECK_DATA_ROOT:-$tools} is not inside a git work tree" >&2
  exit 2
}
cd "$top" || exit 2

if ((uncommitted)); then
  if [[ -z "$base" ]]; then
    base=HEAD
  elif ((fetch)) && [[ "$base" == */* ]]; then
    git fetch --quiet "${base%%/*}" "${base#*/}" 2>/dev/null || export CHECK_AFFECTED_FETCH_FAILED=1
  fi
  base="$(git rev-parse --verify --quiet "$base^{commit}")" || {
    echo "check-affected: cannot resolve the base to a commit" >&2
    exit 2
  }
  snap="$(mktemp -d)" || exit 2
  trap 'rm -rf "$snap"' EXIT
  objects="$(cd "$(git rev-parse --git-common-dir)/objects" && pwd -P)" || exit 2
  index="$(git rev-parse --git-path index)" || exit 2
  shallow="$(git rev-parse --git-path shallow)" || exit 2
  [[ ! -f "$index" ]] || cp "$index" "$snap/index" || exit 2
  mkdir "$snap/objects" || exit 2
  export GIT_INDEX_FILE="$snap/index" GIT_OBJECT_DIRECTORY="$snap/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$objects"
  paths=()
  while IFS= read -r -d '' f; do
    if [[ -f "$f" || -L "$f" || -d "$f" || ! -e "$f" ]]; then paths+=("$f"); fi
  done < <(git ls-files -z --modified --others --exclude-standard)
  if ((${#paths[@]})); then
    printf '%s\0' "${paths[@]}" | git add -A --pathspec-from-file=- --pathspec-file-nul || exit 2
    if [[ ${CHECK_AFFECTED_SCRIPT_EXEC_BIT:-} == 1 ]]; then
      for f in "${paths[@]}"; do
        [[ -f "$f" && ! -L "$f" ]] || continue
        if [[ "$f" == *.sh || "$(head -c 2 -- "$f")" == '#!' ]]; then git update-index --chmod=+x -- "$f" || exit 2; fi
      done
    fi
  fi
  tree="$(git write-tree)" || exit 2
  if [[ "$tree" == "$(git rev-parse "HEAD^{tree}")" ]]; then
    commit="$(git rev-parse HEAD)" || exit 2
  else
    commit="$(git -c user.name=check-affected -c user.email=check-affected@localhost \
      commit-tree "$tree" -p HEAD -m 'check-affected: uncommitted work')" || exit 2
  fi
  unset GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  git -c init.defaultBranch=snapshot init --quiet --template= "$snap/tree" || exit 2
  printf '%s\n' "$snap/objects" "$objects" >"$snap/tree/.git/objects/info/alternates" || exit 2
  [[ ! -f "$shallow" ]] || cp "$shallow" "$snap/tree/.git/shallow" || exit 2
  git -C "$snap/tree" -c core.hooksPath=/dev/null checkout --quiet --detach "$commit" || exit 2
  args=(--base "$base" --no-fetch --jobs "$jobs" --budget "$budget")
  ((run_tests)) && args+=(--tests)
  own=
  [[ "$(pwd -P)" != "$tools" ]] || own="$tools"
  rc=0
  CHECK_AFFECTED_SNAPSHOT_OF="$own" CHECK_DATA_ROOT="$snap/tree" bash "$tools/scripts/check-affected.sh" "${args[@]}" || rc=$?
  exit "$rc"
fi
printf -v deadline '%(%s)T' -1
deadline=$((deadline + budget))
base="${base:-origin/main}"
snapshot=0
[[ -z "${CHECK_AFFECTED_SNAPSHOT_OF-}" || "$CHECK_AFFECTED_SNAPSHOT_OF" != "$tools" ]] || snapshot=1
unset CHECK_AFFECTED_SNAPSHOT_OF
foreign=0
if [[ "$(pwd -P)" != "$tools" ]]; then
  foreign=1
  export CHECK_DATA_ROOT="$PWD"
  # UV_NO_CONFIG stops uv reading uv.toml or [tool.uv] from the checked tree's directories.
  # https://docs.astral.sh/uv/reference/environment/#uv_no_config
  export UV_NO_CONFIG=1
else
  unset CHECK_DATA_ROOT
fi

gates_file="$tools/scripts/check-affected-gates.txt"
declare -a passed=() skipped=() failed=()
out="$(mktemp)" || exit 2
trap 'rm -rf "$out" "$out.failures" "$out.patterns" "$out.not-run" "$out.left" "$out.node" "$out.md" "$out.cl" "$out.voc"' EXIT

skip() { skipped+=("$1 ($2)"); }

std_config() {
  local org
  if [[ -f "$tools/$1" ]]; then
    printf '%s\n' "$tools/$1"
  elif org="$(bash "$tools/lib/org-standards.sh" dir --root "$tools" 2>/dev/null)" && [[ -f "$org/$1" ]]; then
    printf '%s\n' "$org/$1"
  fi
}

std_unread() {
  echo "$1: neither this tree nor the standards org layer has it (lib/org-standards.sh dir could not read the org layer)"
  return 1
}
no_std_config() {
  if [[ -n "${CI:-}" || -n "${STANDARDS_DIR:-}" ]]; then
    run_check "$1" "bash lib/org-standards.sh dir --root ." std_unread "$2"
  else
    skip "$1" "no $2 here, and the standards org layer could not be read"
  fi
}

fail_check() {
  failed+=("$1")
  {
    printf '\nFAIL %s (exit %s). Reproduce: %s\n' "$1" "$2" "$3"
    tail -n 15 "$out"
  } >>"$out.failures"
}

run_check() {
  local name="$1" repro="$2" rc=0
  shift 2
  "$@" >"$out" 2>&1 || rc=$?
  local line
  while IFS= read -r line; do
    skip "$name: ${line#SKIP }" "reported by the check"
  done < <(grep '^SKIP ' "$out")
  case "$rc" in
  0) passed+=("$name") ;;
  2 | 127) skip "$name" "could not run, exit $rc: $(tail -n 1 "$out")" ;;
  *) fail_check "$name" "$rc" "$repro" ;;
  esac
}

fetched=1
[[ -z "${CHECK_AFFECTED_FETCH_FAILED-}" ]] || fetched=0
if ((fetch)) && [[ "$base" == */* ]]; then
  git fetch --quiet "${base%%/*}" "${base#*/}" 2>/dev/null || fetched=0
fi
base_name="$base"
base="$(git rev-parse --verify --quiet "$base^{commit}")" || {
  echo "check-affected: cannot compute the merge-base of HEAD and $base_name: it names no commit" >&2
  exit 2
}

merge_base="$(git merge-base HEAD "$base" 2>/dev/null)" || {
  echo "check-affected: cannot compute the merge-base of HEAD and $base" >&2
  exit 2
}
if ! all_raw="$(git diff --name-only "$merge_base" HEAD)" ||
  ! changed_raw="$(git diff --name-only --diff-filter=d "$merge_base" HEAD)"; then
  echo "check-affected: git diff against $merge_base failed" >&2
  exit 2
fi
mapfile -t changed <<<"$changed_raw"
[[ -n "${changed[0]-}" ]] || changed=()
if [[ -z "$all_raw" && "$(git rev-list --count "$base...HEAD")" != 0 ]]; then
  echo "check-affected: no changed files in $top since $merge_base, yet HEAD is not $base_name, so nothing would be checked. Run the check-affected.sh inside the tree you mean to check, or name that tree in CHECK_DATA_ROOT." >&2
  exit 2
fi

if ((${#changed[@]})) && ! git diff --quiet HEAD -- "${changed[@]}"; then
  echo "check-affected: SKIP every check (uncommitted edits to changed files; the checks read the working tree, a push sends HEAD, and CI checks the pushed commit). Commit or stash them, then rerun." >&2
  exit 0
fi

declare -a md=() sh=() py=() shebang=() plugins=()
skill_touched=0
drift_touched=0
for f in ${changed[@]+"${changed[@]}"}; do
  case "$f" in
  *.md) md+=("$f") ;;
  *.sh | *.bash) sh+=("$f") ;;
  *.py) py+=("$f") ;;
  *) ;;
  esac
  [[ -f "$f" && "$(head -c 2 "$f")" == '#!' ]] && shebang+=("$f")
done
while IFS= read -r f; do
  case "$f" in
  plugins/*/*)
    p="${f#plugins/}"
    p="${p%%/*}"
    [[ -d "plugins/$p" && " ${plugins[*]-} " != *" $p "* ]] && plugins+=("$p")
    [[ "$f" == plugins/*/skills/* ]] && skill_touched=1
    drift_touched=1
    ;;
  scripts/cross-plugin-source-registry.txt | scripts/check-cross-plugin-source-drift.sh) drift_touched=1 ;;
  *) ;;
  esac
done <<<"$all_raw"

md_config=""
((${#md[@]} == 0)) || md_config="$(std_config .markdownlint-cli2.jsonc)"
if ((${#md[@]} == 0)); then
  skip markdown "no changed .md"
elif ! command -v markdownlint-cli2 >/dev/null 2>&1; then
  skip markdown "markdownlint-cli2 not installed"
elif [[ -z "$md_config" ]]; then
  no_std_config markdown .markdownlint-cli2.jsonc
elif ((foreign)); then
  markdown_staged() {
    local stage f kind mode data rc=0
    stage="$out.md"
    mkdir "$stage" || return 2
    while IFS= read -r f; do
      mkdir -p "$stage/${f%/*}" && cp "$tools/$f" "$stage/$f" || rc=2
    done < <(cd "$tools" && find . -name node_modules -prune -o -name .git -prune -o -name '.markdownlint*' -type f -print)
    [[ -f "$stage/.markdownlint-cli2.jsonc" ]] || cp "$md_config" "$stage/.markdownlint-cli2.jsonc" || rc=2
    for f in ${changed[@]+"${changed[@]}"}; do
      case "${f##*/}" in
      .markdownlint-cli2.jsonc) kind=options ;;
      .markdownlint.jsonc | .markdownlint.json) kind=config ;;
      .markdownlint*)
        echo "SKIP config $f (refused: only .markdownlint-cli2.jsonc, .markdownlint.jsonc and .markdownlint.json are read as data)"
        continue
        ;;
      *) continue ;;
      esac
      mode="$(git ls-tree HEAD -- "$f" | cut -d' ' -f1)"
      if [[ "$mode" != 100644 && "$mode" != 100755 ]]; then
        echo "SKIP config $f (refused: not a regular file)"
      elif data="$(git show "HEAD:$f" | node "$tools/scripts/lib/markdownlint-config-data.mjs" "$kind")"; then
        mkdir -p "$stage/$(dirname "$f")" && printf '%s\n' "$data" >"$stage/$f" || rc=2
      else
        echo "SKIP config $f (refused: ${data:-the data check could not run})"
      fi
    done
    for f in "${md[@]}"; do
      mkdir -p "$stage/$(dirname "$f")" && git show "HEAD:$f" >"$stage/$f" || rc=2
    done
    ((rc)) || (cd "$stage" && markdownlint-cli2 --config .markdownlint-cli2.jsonc "${md[@]}") || rc=$?
    rm -rf "$stage"
    return "$rc"
  }
  run_check markdown "markdownlint-cli2 --config .markdownlint-cli2.jsonc ${md[*]}" markdown_staged
else
  run_check markdown "markdownlint-cli2 --config $md_config ${md[*]}" \
    markdownlint-cli2 --config "$md_config" "${md[@]}"
fi

sc_rc=""
((${#sh[@]} == 0)) || sc_rc="$(std_config .shellcheckrc)"
if ((${#sh[@]} == 0)); then
  skip shellcheck "no changed shell"
elif ! command -v shellcheck >/dev/null 2>&1; then
  skip shellcheck "shellcheck not installed"
elif [[ -z "$sc_rc" ]]; then
  no_std_config shellcheck .shellcheckrc
else
  run_check shellcheck "shellcheck --rcfile $sc_rc ${sh[*]}" \
    shellcheck --rcfile "$sc_rc" "${sh[@]}"
fi

run_check shell-portability "scripts/check-shell-portability.sh $merge_base" \
  "$tools/scripts/check-shell-portability.sh" "$merge_base"

exec_bit() {
  local f mode bad=0
  for f in ${shebang[@]+"${shebang[@]}"}; do
    mode="$(git ls-files -s -- "$f" | cut -d' ' -f1)"
    [[ -z "$mode" || "$mode" == 100755 ]] && continue
    echo "$f starts with #! but is $mode in the index; run: git update-index --chmod=+x $f"
    bad=1
  done
  return "$bad"
}
run_check exec-bit "git ls-files -s -- <file> for each changed #! file" exec_bit

frag() {
  "$tools/scripts/check-changelog-fragments.sh" --check &&
    "$tools/scripts/check-changelog-fragments.sh" --check-required "$base"
}
run_check changelog-fragments \
  "scripts/check-changelog-fragments.sh --check && scripts/check-changelog-fragments.sh --check-required $base" frag

if ((fetched)); then
  run_check stale-base-overlap "scripts/check-stale-base-overlap.sh --check $base" \
    "$tools/scripts/check-stale-base-overlap.sh" --check "$base"
else
  skip stale-base-overlap "git fetch of $base_name failed"
fi

if ((${#py[@]} == 0)); then
  skip ruff "no changed .py"
else
  run_check ruff "scripts/run-ruff.sh check --force-exclude ${py[*]}" "$tools/scripts/run-ruff.sh" check --force-exclude "${py[@]}"
fi

hygiene_workflow=.github/workflows/pr-require-checks.yml
step_input() {
  awk -v id="$1" -v key="$2" '
    function words(s, a, n, i) { n = split(s, a, " "); for (i = 1; i <= n; i++) print a[i] }
    blk { match($0, /^ */); if (NF && RLENGTH <= kind) exit; words($0); next }
    ind { match($0, /^ */); if (NF && RLENGTH < ind) exit }
    $0 ~ "^ *(- )?id: " id "$" { match($0, /^ *(- )?/); ind = RLENGTH; next }
    ind && $0 ~ "^ *" key ":( |$)" {
      match($0, /^ */); kind = RLENGTH; sub("^ *" key ": *", "")
      if ($0 ~ /^[>|][-+]?$/) { blk = 1; next }
      words($0); exit
    }' "$hygiene_workflow"
}

typos_check() {
  local g
  local -a excludes=()
  if [[ ! -f "$hygiene_workflow" ]]; then
    echo "typos: $hygiene_workflow is missing, so its typos step's exclude globs cannot be read"
    return 1
  fi
  while IFS= read -r g; do excludes+=(--exclude "$g"); done < <(step_input typos exclude)
  if ((${#excludes[@]} == 0)); then
    echo "typos: $hygiene_workflow has no exclude globs on its typos step (id: typos)"
    return 1
  fi
  typos --config "$1" --force-exclude "${excludes[@]}" -- "${changed[@]}" || return 1
}
typos_rel=_typos.toml
[[ -f "$hygiene_workflow" ]] && typos_rel=$(step_input typos config | head -n 1)
typos_rel=${typos_rel:-_typos.toml}
typos_org=1
if [[ "$typos_rel" == _typos.toml ]] && org="$(bash "$tools/lib/org-standards.sh" dir --root "$tools" 2>/dev/null)" &&
  [[ -f "$org/_typos.toml" ]]; then
  typos_config="$org/_typos.toml"
else
  [[ "$typos_rel" != _typos.toml ]] || typos_org=0
  typos_config="$tools/$typos_rel"
  [[ -f "$typos_config" ]] || typos_config="$PWD/$typos_rel"
fi
if ((${#changed[@]} == 0)); then
  skip typos "no changed files"
elif ! command -v typos >/dev/null 2>&1; then
  skip typos "typos not installed"
elif ((!typos_org)) && [[ -n "${CI:-}" || -n "${STANDARDS_DIR:-}" ]]; then
  no_std_config typos _typos.toml
elif [[ ! -f "$typos_config" ]]; then
  skip typos "no $typos_rel"
else
  run_check typos "typos --config $typos_rel ${changed[*]}" typos_check "$typos_config"
fi

if ((${#changed[@]} == 0)); then
  skip comment-hygiene "no changed files"
else
  run_check comment-hygiene "bash scripts/check-comment-hygiene.sh $merge_base ${changed[*]}" \
    bash "$tools/scripts/check-comment-hygiene.sh" "$merge_base" "${changed[@]}"
fi

comment_lint=plugins/code-tidying/git-hooks/comment-lint.sh
comment_lint_merge_base_diff() {
  local d="$out.cl" f files home head
  head="$(git rev-parse HEAD)" &&
    git -c init.defaultBranch=lint init --quiet --template= "$d" &&
    printf '%s\n' "$(cd "$(git rev-parse --git-common-dir)/objects" && pwd -P)" >"$d/.git/objects/info/alternates" &&
    git -C "$d" update-ref --no-deref HEAD "$merge_base" &&
    git -C "$d" read-tree "$head" || return 2
  copy_from_merge_base() {
    if git cat-file -e "$merge_base:$1" 2>/dev/null; then
      mkdir -p "$d/$(dirname "$1")" && git show "$merge_base:$1" >"$d/$1"
    fi
  }
  copy_from_merge_base AGENTS.md && copy_from_merge_base CLAUDE.md || return 2
  home="$(bash "$tools/plugins/code-tidying/lib/resolve-convention-home.sh" --root "$d" --ref "$merge_base" 2>/dev/null)" || home=""
  [[ -n "$home" && "$home" != /* && "$home" != *..* ]] || home=docs/conventions
  files="$(bash "$tools/plugins/code-tidying/scripts/comment-settings.sh" --files)" || return 2
  while IFS= read -r f; do
    copy_from_merge_base "${home%/}/$f" || return 2
  done <<<"$files"
  (cd "$d" && AI_AGENT=ci sh "$tools/$comment_lint")
}
if ((${#changed[@]} == 0)); then
  skip comment-lint "no changed files"
elif [[ ! -f "$tools/$comment_lint" ]]; then
  skip comment-lint "no $comment_lint beside this script"
elif ! python3 -c 'import pygments' >/dev/null 2>&1; then
  skip comment-lint "python3 with pygments not installed"
else
  run_check comment-lint \
    "AI_AGENT=ci sh $comment_lint --worktree for uncommitted edits, else bash plugins/code-tidying/git-hooks/comment-lint-ci.sh HEAD $merge_base" \
    comment_lint_merge_base_diff
fi

vocabulary=scripts/check-vocabulary.py
vocabulary_senses=scripts/vocabulary-senses.json
declare -a vocabulary_files=() vocabulary_links=()
for f in ${changed[@]+"${changed[@]}"}; do
  case "$(git ls-tree HEAD -- "$f" | cut -d' ' -f1)" in
  100644 | 100755) vocabulary_files+=("$f") ;;
  120000) vocabulary_links+=("$f") ;;
  *) ;;
  esac
done
vocabulary_staged() {
  local d="$out.voc" f
  for f in "${vocabulary_files[@]}"; do
    mkdir -p "$d/$(dirname "$f")" && git show "HEAD:$f" >"$d/$f" || return 2
  done
  mkdir -p "$d/scripts" && cp "$tools/$vocabulary" "$tools/$vocabulary_senses" "$d/scripts/" || return 2
  (cd "$d" && python3 -I "$vocabulary" -- "${vocabulary_files[@]}")
}
if ! command -v python3 >/dev/null 2>&1; then
  skip vocabulary "python3 not installed"
elif [[ ! -f "$tools/$vocabulary" || ! -f "$tools/$vocabulary_senses" ]]; then
  skip vocabulary "no $vocabulary and $vocabulary_senses beside this script"
elif grep -qxE 'scripts/(check-vocabulary\.py|vocabulary-senses\.json)' <<<"$all_raw"; then
  if ((foreign)); then
    skip vocabulary "the branch changes the checker or its senses file; CI runs the branch's copy"
  elif ! git diff --quiet HEAD; then
    skip vocabulary "the branch changes the checker or its senses file, and the whole-tree scan would read uncommitted edits a push does not send"
  else
    run_check vocabulary "python3 -I scripts/check-vocabulary.py" python3 -I "$tools/$vocabulary"
  fi
elif ((${#vocabulary_files[@]} == 0)); then
  skip vocabulary "no changed regular file"
else
  for f in ${vocabulary_links[@]+"${vocabulary_links[@]}"}; do
    skip "vocabulary: $f" "a symlink, which CI scans through to its target"
  done
  run_check vocabulary "python3 -I scripts/check-vocabulary.py ${vocabulary_files[*]}" vocabulary_staged
fi

machine_paths_lib=plugins/guardrails/lib/path-detection/machine-path-patterns.sh
machine_paths_default_types='*.cs *.csproj *.json *.jsonc *.js *.jsx *.md *.props *.ps1 *.psm1 *.py *.sh *.slnx *.targets *.tmpl *.toml *.ts *.tsx *.yaml *.yml'
declare -a machine_paths_types=() machine_paths_excludes=() machine_paths_files=()
[[ -f "$hygiene_workflow" ]] && while IFS= read -r g; do machine_paths_types+=("${g//[\"\']/}"); done < <(step_input machine_paths extensions)
((${#machine_paths_types[@]})) || read -ra machine_paths_types <<<"$machine_paths_default_types"
for f in ${changed[@]+"${changed[@]}"}; do
  for g in "${machine_paths_types[@]}"; do
    # shellcheck disable=SC2053 # $g is a glob on purpose.
    if [[ "$f" == $g ]]; then
      machine_paths_files+=(":(literal)$f")
      break
    fi
  done
done

machine_paths_load() {
  git show "$merge_base:$machine_paths_lib" >"$out.patterns" 2>/dev/null || return 1
  # shellcheck source=../plugins/guardrails/lib/path-detection/machine-path-patterns.sh
  . "$out.patterns" || return 1
  [[ -n "${HPP_WIN_USER_BODY-}" && -n "${HPP_MACOS_USER_BODY-}" && -n "${HPP_LINUX_USER_BODY-}" &&
    -n "${HPP_WIN_REPO_BODY-}" && -n "${HPP_ESCAPED_WIN_REPO_BODY-}" ]]
}

machine_paths_exempt() {
  local span child rest trimmed n=0
  while IFS= read -r span; do
    [[ -n "$span" ]] || continue
    n=$((n + 1))
    child="${span##*[/\\]}"
    rest="$(printf '%s' "$child" | LC_ALL=C tr -d '[:punct:]')" || return 1
    rest="${rest//$'\342\200\246'/}"
    [[ -n "$child" && -z "$rest" ]] && continue
    if [[ "$2" == 1 ]]; then
      trimmed="$(printf '%s\n' "$child" | LC_ALL=C sed 's/[^A-Za-z0-9._-]*$//')" || return 1
      [[ "${trimmed%.}" == Shared ]] && continue
    fi
    return 1
  done < <(printf '%s\n' "$3" | grep -oE -- "$1")
  ((n))
}

machine_paths_scan() {
  local matches line content rc=0 found=0
  matches="$(git grep -nIE -e "$3" -- "${machine_paths_files[@]}" "${machine_paths_excludes[@]}")" || rc=$?
  ((rc <= 1)) || return 2
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    content="${line#*:*:}"
    if [[ "$content" != "$line" ]]; then
      [[ "$content" == *machine-path:allow* ]] && continue
      machine_paths_exempt "$3" "$2" "$content" && continue
    fi
    echo "$1: $line"
    found=1
  done <<<"$matches"
  return "$found"
}

machine_paths_check() {
  local boundary i g rc found=0 errored=0
  if [[ ! -f "$hygiene_workflow" ]]; then
    echo "machine-specific-paths: $hygiene_workflow is missing, so its machine-paths step's exclude pathspecs cannot be read"
    return 1
  fi
  while IFS= read -r g; do
    if [[ "$g" != ':(exclude)'* && "$g" != ':!'* && "$g" != ':^'* ]]; then
      echo "machine-specific-paths: $hygiene_workflow's machine-paths step excludes '$g', which is not an exclusion pathspec"
      return 1
    fi
    machine_paths_excludes+=("$g")
  done < <(step_input machine_paths exclude)
  if ((${#machine_paths_excludes[@]} == 0)); then
    echo "machine-specific-paths: $hygiene_workflow has no exclude pathspecs on its machine-paths step (id: machine_paths)"
    return 1
  fi
  boundary=$'(^|[[:space:]"\'`(=]|file://)'
  local -a labels=("Windows user path" "macOS user path" "Linux user path" "Windows repo path" "Escaped Windows repo path")
  local -a patterns=("$HPP_WIN_USER_BODY" "$boundary$HPP_MACOS_USER_BODY" "$boundary$HPP_LINUX_USER_BODY"
    "$HPP_WIN_REPO_BODY" "$HPP_ESCAPED_WIN_REPO_BODY")
  for i in "${!labels[@]}"; do
    rc=0
    machine_paths_scan "${labels[i]}" "$((i == 1))" "${patterns[i]}" || rc=$?
    case "$rc" in
    0) ;;
    1) found=1 ;;
    *)
      echo "${labels[i]}: git grep failed"
      errored=1
      ;;
    esac
  done
  if ((found)); then
    echo "Use portable placeholders (<repo-root>, <user>) or relative paths, or mark the line machine-path:allow."
    return 1
  fi
  ((errored)) && return 2
  return 0
}

if ((${#machine_paths_files[@]} == 0)); then
  skip machine-specific-paths "no changed file of a type it scans"
elif ! machine_paths_load; then
  skip machine-specific-paths "no loadable $machine_paths_lib at the merge-base"
else
  run_check machine-specific-paths "scripts/check-affected.sh --base $base" machine_paths_check
fi

run_check size-check "bash plugins/code-metrics/skills/audit/scripts/audit-size.sh --check --base $base" \
  env -u CLAUDE_PLUGIN_ROOT bash "$tools/plugins/code-metrics/skills/audit/scripts/audit-size.sh" --check --base "$base"

run_check spoke-plugin-root "scripts/check-spoke-plugin-root.sh --check" \
  "$tools/scripts/check-spoke-plugin-root.sh" --check

run_check as-of-recheck "scripts/check-as-of-recheck.sh --check" \
  "$tools/scripts/check-as-of-recheck.sh" --check

run_check cost-figures "scripts/check-cost-figures.sh --check" \
  "$tools/scripts/check-cost-figures.sh" --check

run_check token-literals "scripts/check-token-literals.sh --base $merge_base" \
  "$tools/scripts/check-token-literals.sh" --base "$merge_base"

rv=plugins/guardrails/git-hooks/reference-verify.sh
if [[ -f "$tools/$rv" ]]; then
  run_check reference-verify "sh $rv --base $base" sh "$tools/$rv" --base "$base"
else
  skip reference-verify "no $rv in this repository"
fi
lf=plugins/bash-format/git-hooks/lint-full.sh
if [[ -f "$tools/$lf" ]]; then
  run_check lint-full "sh $lf --base $base" sh "$tools/$lf" --base "$base"
else
  skip lint-full "no $lf in this repository"
fi

if ((drift_touched)); then
  run_check cross-plugin-source-drift "scripts/check-cross-plugin-source-drift.sh --check" \
    "$tools/scripts/check-cross-plugin-source-drift.sh" --check
else
  skip cross-plugin-source-drift "no plugin file, drift script or registry changed"
fi

run_check plugin-imports "scripts/check-plugin-imports.sh" \
  "$tools/scripts/check-plugin-imports.sh"

if ((foreign)) && grep -qx scripts/sync-plugin-options-docs.py <<<"$all_raw"; then
  skip plugin-options-docs "the branch changes the generator; CI runs the branch's copy"
else
  run_check plugin-options-docs "python3 scripts/sync-plugin-options-docs.py --check" \
    python3 "$tools/scripts/sync-plugin-options-docs.py" --check
fi

parity() {
  local p="$tools/scripts/check-changelog-parity.sh"
  "$p" --check &&
    CHANGELOG_PARITY_COLLISIONS=advisory "$p" --check-bump "$base" &&
    "$p" --check-preserved "$base" &&
    "$p" --check-order
}
run_check changelog-parity \
  "scripts/check-changelog-parity.sh --check; CHANGELOG_PARITY_COLLISIONS=advisory scripts/check-changelog-parity.sh --check-bump $base; scripts/check-changelog-parity.sh --check-preserved $base; scripts/check-changelog-parity.sh --check-order" \
  parity

halt=${#failed[@]}
halt_why="a static check failed above"

if ((halt)); then
  skip validate-plugins "$halt_why"
elif ((${#plugins[@]} == 0)); then
  skip validate-plugins "no plugin changed"
elif ! command -v claude >/dev/null 2>&1; then
  skip validate-plugins "claude CLI not installed"
else
  contracts_skip=
  if ((foreign && !snapshot)) && grep -qxE 'scripts/validate-plugin-contracts\.(mjs|test\.sh)' <<<"$all_raw"; then
    contracts_skip="the branch changes the validator; CI runs the branch's copy"
  fi
  run_check validate-plugins "scripts/validate-plugins.sh --only \"${plugins[*]}\"" \
    env CHECK_SKIP_CONTRACTS="$contracts_skip" "$tools/scripts/validate-plugins.sh" --only "${plugins[*]}"
fi

if ((halt)); then
  skip changed-skills "$halt_why"
elif ((!skill_touched)); then
  skip changed-skills "no changed skill file"
elif ((foreign)); then
  skip changed-skills "runs the checked tree's own skill-quality code"
elif ((run_tests)); then
  run_check changed-skills "scripts/check-changed-skills.sh $base" \
    env PLUGIN_TEST_DEADLINE="$deadline" "$tools/scripts/check-changed-skills.sh" "$base"
else
  run_check changed-skills "CHECK_SKILL_SKIP_SCRIPT_TESTS=1 scripts/check-changed-skills.sh $base" \
    env CHECK_SKILL_SKIP_SCRIPT_TESTS=1 "$tools/scripts/check-changed-skills.sh" "$base"
fi

scoped_suites=()
for f in ${changed[@]+"${changed[@]}"}; do
  case "${f##*/}" in
  *.test.sh | *.test.js | *.test.mjs | test_*.py | *.Tests.ps1) grep -q 'test-scope:' "$f" 2>/dev/null && scoped_suites+=("$f") ;;
  *) ;;
  esac
done
scope_globs() {
  local rc=0
  "$tools/scripts/affected-tests.sh" --allow-unmapped "$@" >/dev/null || rc=$?
  ((rc == 0)) && return 0
  ((rc == 2)) && grep -q 'declares test-scope globs that match no file' "$out" && return 1
  return 2
}
if ((run_tests)); then
  :
elif ((halt)); then
  skip test-scope-globs "$halt_why"
elif ((${#scoped_suites[@]} == 0)); then
  skip test-scope-globs "no changed test file declares test-scope"
else
  run_check test-scope-globs "scripts/affected-tests.sh --allow-unmapped ${scoped_suites[*]}" scope_globs "${scoped_suites[@]}"
fi

if ((run_tests && halt)); then
  skip tests "$halt_why"
elif ((run_tests && foreign && !snapshot)); then
  skip tests "runs the checked tree's own test code"
elif ((run_tests)); then
  npm_failed=0
  rc=0
  bash "$tools/scripts/setup-env.sh" --node --root "$tools" >"$out" 2>&1 || rc=$?
  if ((rc == 0)); then
    grep '^setup-env: installed' "$out" >&2
  elif ((rc == 2 || rc == 127)); then
    skip npm-deps "could not run, exit $rc: $(tail -n 1 "$out")"
  else
    npm_failed=1
    fail_check npm-deps "$rc" "bash scripts/setup-env.sh --node"
  fi
  affected() {
    local rc=0 node_rc=0 s pkg ex t n=0 missing='' now
    local -a pkgs=() exclusions=() node=() unrun=() left=()
    local -A pkg_suites=()
    leave() {
      left+=("$1")
      echo "SKIP $1 (past the ${budget}s budget, left to CI)"
    }
    env -u CHECK_DATA_ROOT PLUGIN_TEST_SHARE_WARN_ONLY=1 PLUGIN_TEST_DEADLINE="$deadline" PLUGIN_TEST_LEFT_FILE="$out.left" \
      "$tools/scripts/affected-tests.sh" --run --jobs "$jobs" --budget "$budget" --base "$base" --write-not-run "$out.not-run" || rc=$?
    if [[ -s "$out.left" ]]; then
      while IFS= read -r s; do leave "$s"; done <"$out.left"
    fi
    if ((rc == 0 && ${#left[@]})); then
      echo "${#left[@]} selected suite(s) left to CI, past the ${budget}s budget"
      return 2
    fi
    ((rc == 3)) || return "$rc"
    # shellcheck source=lib/read-list.sh
    . "$tools/scripts/lib/read-list.sh" &&
      read_list::into pkgs "$tools/scripts/outside-node-packages.txt" --comments inline &&
      read_list::into exclusions "$tools/scripts/outside-node-exclusions.txt" --comments inline || return 2
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      n=$((n + 1))
      for ex in ${exclusions[@]+"${exclusions[@]}"}; do
        [[ "$s" == "$ex"* ]] && continue 2
      done
      for pkg in ${pkgs[@]+"${pkgs[@]}"}; do
        if [[ "$s" == "$pkg"/* ]]; then
          node+=("$s")
          pkg_suites[$pkg]+="$s"$'\n'
          continue 2
        fi
      done
      case "$s" in
      *.test.js | *.test.mjs) [[ -f "${s%.test.*}.test.sh" ]] && continue ;;
      *) ;;
      esac
      unrun+=("$s")
    done <"$out.not-run"
    if ((n == 0)); then
      echo "affected-tests exited 3 but named no unrun suite"
      return 2
    fi
    if ((${#node[@]})); then
      for t in npm jq; do
        command -v "$t" >/dev/null 2>&1 || missing+="${missing:+, }$t"
      done
    fi
    if [[ -n "$missing" ]]; then
      unrun+=("${node[@]}")
    else
      for pkg in ${pkgs[@]+"${pkgs[@]}"}; do
        [[ -n "${pkg_suites[$pkg]-}" ]] || continue
        printf -v now '%(%s)T' -1
        if ((now >= deadline)); then
          while IFS= read -r s; do leave "$s"; done <<<"${pkg_suites[$pkg]%$'\n'}"
          continue
        fi
        printf '%s' "${pkg_suites[$pkg]}" >"$out.node" || return 2
        rc=0
        bash "$tools/scripts/run-outside-node-suites.sh" --paths "$out.node" || rc=$?
        ((rc == 0 || node_rc == 1)) || node_rc=$rc
      done
    fi
    local summary=''
    ((${#left[@]} == 0)) || summary="${#left[@]} selected suite(s) left to CI, past the ${budget}s budget"
    if ((${#unrun[@]})); then
      printf 'not run here: %s\n' "${unrun[@]}"
      summary+="${summary:+; }${#unrun[@]} selected suite(s) not run here, left to their own CI lanes${missing:+ ($missing not installed)}"
    fi
    [[ -z "$summary" ]] || echo "$summary"
    ((node_rc == 0)) || return "$node_rc"
    [[ -z "$summary" ]] || return 2
  }
  if ((npm_failed)); then
    skip tests "npm dependencies did not install"
  else
    run_check tests "scripts/affected-tests.sh --run --jobs $jobs --budget $budget --base $base" affected
  fi
fi

for s in ${skipped[@]+"${skipped[@]}"}; do echo "check-affected: SKIP $s" >&2; done
if [[ -f "$gates_file" ]]; then
  while read -r gate kind reason; do
    [[ "$kind" == ci-only ]] && echo "check-affected: CI only: $gate ($reason)" >&2
  done < <(grep -v '^[[:space:]]*\(#\|$\)' "$gates_file")
else
  echo "check-affected: SKIP the CI-only list ($gates_file is missing)" >&2
fi
if ((${#failed[@]})); then
  cat "$out.failures" >&2
  printf '\ncheck-affected: %d failed (%s), %d passed, %d skipped. Diff: %s..HEAD\n' \
    "${#failed[@]}" "${failed[*]}" "${#passed[@]}" "${#skipped[@]}" "$merge_base" >&2
  exit 1
fi
printf 'check-affected: %d passed, %d skipped over %d changed files since %s\n' \
  "${#passed[@]}" "${#skipped[@]}" "${#changed[@]}" "$merge_base"
