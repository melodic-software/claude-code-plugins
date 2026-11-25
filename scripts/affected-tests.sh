#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SELF="$SCRIPT_DIR/${BASH_SOURCE[0]##*/}"
cd "${AFFECTED_TESTS_ROOT:-$SCRIPT_DIR/..}" || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
# shellcheck source=lib/pytest-python.sh
. "$SCRIPT_DIR/lib/pytest-python.sh" || exit 2
# shellcheck source=lib/test-git-env.sh
. "$SCRIPT_DIR/lib/test-git-env.sh" || exit 2
# shellcheck source=lib/shard-spec.sh
. "$SCRIPT_DIR/lib/shard-spec.sh" || exit 2

NO_SUITE_LIST="${AFFECTED_TESTS_NO_SUITE:-scripts/affected-tests-no-suite.txt}"
SCOPES_LIST="${AFFECTED_TESTS_SCOPES:-}"
DIFF_BASE=""

STRUCTURAL_BASENAMES=" README.md SKILL.md AGENTS.md CLAUDE.md index.md "
MANIFEST_BASENAMES=" plugin.json marketplace.json hooks.json settings.json package.json package-lock.json "
MANIFEST_BASENAMES+="CHANGELOG.md LICENSE "

usage() {
  cat <<'EOF'
usage: scripts/affected-tests.sh [options] [path...]
Select the test suites that cover the changed files (the diff vs the base ref, or the paths given).
  --run                      run the selected suites, sequentially
  --jobs N                   with --run, N shell suites at a time
  --budget S                 with --run, time against an S-second budget (PLUGIN_TEST_SHARE_WARN_ONLY=1 warns)
  --write-not-run FILE       with --run, write each selected suite it did not run to FILE
  --base REF                 diff base (default: origin/main)
  --explain                  report why each suite was selected (stderr)
  --allow-unmapped           downgrade an unmapped file to a warning
  --unmapped-corpus          select an unmapped file's whole language corpus
  --shard I/N                keep only leg I of N of the selection
  --print-fanout P           print the copy set derived for shared source P
  --each-from LIST --each-out DIR
                             answer each <key>:<path> line of LIST as its own one-file diff
  --replay RANGE [--against REF]
                             select every first-parent commit of RANGE; with --against, diff against REF's selector
  --with-always              accepted, changes nothing
Exit: 0 selected or nothing to do; 1 an unmapped file or a failing suite; 2 usage or a broken
derivation; 3 --run also selected suites outside shell it did not run; 4 --unmapped-corpus met an
unmapped file.
EOF
}

base_ref=""
do_run=0
allow_unmapped=0
unmapped_corpus=0
explain=0
print_fanout=""
shard_spec=""
replay_range=""
against_ref=""
not_run_file=""
each_from=""
each_out=""
jobs=1
budget=""
budget_given=0
shard_given=0
shard_index=0
shard_total=1
declare -a explicit_paths=()

need_value() {
  if [[ "$2" -lt 2 || -z "$3" ]]; then
    echo "error: $1 needs a value ($4)." >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --run) do_run=1 ;;
  --allow-unmapped) allow_unmapped=1 ;;
  --unmapped-corpus) unmapped_corpus=1 ;;
  --explain) explain=1 ;;
  --with-always) ;;
  --jobs)
    need_value "$1" $# "${2:-}" "a positive integer"
    jobs="$2"
    shift
    ;;
  --jobs=*) jobs="${1#--jobs=}" ;;
  --budget)
    need_value "$1" $# "${2:-}" "seconds, a positive integer"
    budget="$2"
    budget_given=1
    shift
    ;;
  --budget=*) budget="${1#--budget=}" budget_given=1 ;;
  --base)
    need_value "$1" $# "${2:-}" "a ref"
    base_ref="$2"
    shift
    ;;
  --base=*) base_ref="${1#--base=}" ;;
  --shard)
    need_value "$1" $# "${2:-}" "<index>/<total>"
    shard_spec="$2"
    shard_given=1
    shift
    ;;
  --shard=*)
    shard_spec="${1#--shard=}"
    shard_given=1
    ;;
  --print-fanout)
    need_value "$1" $# "${2:-}" "a path"
    print_fanout="$2"
    shift
    ;;
  --replay)
    need_value "$1" $# "${2:-}" "a revision range"
    replay_range="$2"
    shift
    ;;
  --against)
    need_value "$1" $# "${2:-}" "a ref"
    against_ref="$2"
    shift
    ;;
  --write-not-run)
    need_value "$1" $# "${2:-}" "a file"
    not_run_file="$2"
    shift
    ;;
  --each-from)
    need_value "$1" $# "${2:-}" "a file of <key>:<path> lines"
    each_from="$2"
    shift
    ;;
  --each-out)
    need_value "$1" $# "${2:-}" "a directory"
    each_out="$2"
    shift
    ;;
  --)
    shift
    explicit_paths+=("$@")
    break
    ;;
  -*)
    echo "error: unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
  *) explicit_paths+=("$1") ;;
  esac
  shift
done

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --jobs wants a positive integer; got: $jobs" >&2
  exit 2
fi
if [[ "$budget_given" -eq 1 && ! "$budget" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --budget wants a positive number of seconds; got: $budget" >&2
  exit 2
fi
if [[ "$shard_given" -eq 1 ]] && ! parse_shard "$shard_spec"; then
  echo "error: --shard wants <index>/<total> with total >= 1 and 0 <= index < total; got: $shard_spec" >&2
  exit 2
fi
if [[ "$allow_unmapped" -eq 1 && "$unmapped_corpus" -eq 1 ]]; then
  echo "error: --allow-unmapped and --unmapped-corpus answer the same question two ways; pass one." >&2
  exit 2
fi
if [[ -n "$against_ref" && -z "$replay_range" ]]; then
  echo "error: --against only applies to --replay." >&2
  exit 2
fi
if [[ -n "$not_run_file" && "$do_run" -eq 0 ]]; then
  echo "error: --write-not-run only applies to --run." >&2
  exit 2
fi
if [[ -n "$not_run_file" ]] && ! : >"$not_run_file"; then
  echo "error: cannot write --write-not-run file: $not_run_file" >&2
  exit 2
fi
if [[ -n "$each_from" || -n "$each_out" ]]; then
  if [[ -z "$each_from" || -z "$each_out" || ! -d "$each_out" || ! -r "$each_from" ]]; then
    echo "error: --each-from wants a readable list and --each-out an existing directory; pass both." >&2
    exit 2
  fi
  if [[ ${#explicit_paths[@]} -gt 0 || -n "$base_ref" || -n "$replay_range" || "$do_run" -eq 1 || "$shard_given" -eq 1 ]]; then
    echo "error: --each-from takes its files from the list; it combines with no paths, --base, --replay, --run or --shard." >&2
    exit 2
  fi
fi
if [[ -n "$replay_range" ]] && [[ ${#explicit_paths[@]} -gt 0 || -n "$base_ref" || "$do_run" -eq 1 || "$shard_given" -eq 1 ]]; then
  echo "error: --replay takes its changed files from each commit; it combines with no paths, --base, --run or --shard." >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/affected-tests.XXXXXX")" || exit 2
trap 'rm -rf "$WORK_DIR"' EXIT

declare -A SYNC_SRC_COPIES=()
declare -A SYNC_SCRIPT_SRC=()

register_sync_block() {
  local script="$1" src="$2" has_copy_key="$3" pattern match
  shift 3
  local -a expanded=()
  if [[ -z "$src" ]]; then
    echo "error: $script --print-manifest declared copies but no src= — the shared-lib derivation cannot read it." >&2
    echo "       Teach scripts/affected-tests.sh the new manifest shape; do not hardcode a copy list." >&2
    exit 2
  fi
  SYNC_SCRIPT_SRC["$script"]+="$src"$'\n'
  if ((has_copy_key == 0)); then
    SYNC_SRC_COPIES["$src"]=""
    return 0
  fi
  for pattern in "$@"; do
    if [[ -e "$pattern" ]]; then
      expanded+=("$pattern")
      continue
    fi
    # shellcheck disable=SC2086 # a manifest entry may still be a glob;
    for match in $pattern; do
      [[ -e "$match" ]] && expanded+=("$match")
    done
  done
  if [[ ${#expanded[@]} -eq 0 ]]; then
    echo "error: $script yielded ZERO copy paths for $src." >&2
    echo "       An empty derivation is the hardcoded-list failure mode one level up: it would" >&2
    echo "       silently stop fanning a shared-lib change out to its carrying plugins." >&2
    exit 2
  fi
  printf -v SYNC_SRC_COPIES["$src"] '%s\n' "${expanded[@]}"
}

build_sync_map() {
  local script line kind value rc errfile outfile i
  local -a block_src=() block_has_copy=() block_patterns=() patterns=()
  outfile="$WORK_DIR/print-manifest.out"
  errfile="$WORK_DIR/print-manifest.err"
  for script in scripts/sync-*.sh; do
    [[ -f "$script" && "$script" != *.test.sh ]] || continue
    rc=0
    bash "$script" --print-manifest >"$outfile" 2>"$errfile" || rc=$?

    block_src=()
    block_has_copy=()
    block_patterns=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      kind="${line%%$'\t'*}"
      if [[ "$kind" == "$line" ]]; then
        value=""
      else
        value="${line#*$'\t'}"
      fi
      case "$kind" in
      src)
        block_src+=("$value")
        block_has_copy+=(0)
        block_patterns+=("")
        ;;
      copy)
        if [[ ${#block_src[@]} -eq 0 ]]; then
          block_src+=("")
          block_has_copy+=(0)
          block_patterns+=("")
        fi
        i=$((${#block_src[@]} - 1))
        block_has_copy[i]=1
        block_patterns[i]+="$value"$'\n'
        ;;
      *) ;;
      esac
    done <"$outfile"

    if ((rc != 0)); then
      if [[ ! -s "$outfile" ]] && grep -q '^usage:' "$errfile"; then
        continue
      fi
      echo "error: $script --print-manifest failed (exit $rc)." >&2
      cat "$errfile" >&2
      exit 2
    fi

    for i in "${!block_src[@]}"; do
      patterns=()
      while IFS= read -r line; do
        [[ -z "$line" ]] || patterns+=("$line")
      done <<<"${block_patterns[i]}"
      register_sync_block "$script" "${block_src[i]}" "${block_has_copy[i]}" ${patterns[@]+"${patterns[@]}"}
    done
  done
  if [[ ${#SYNC_SCRIPT_SRC[@]} -eq 0 ]]; then
    echo "error: no scripts/sync-*.sh manifests found — shared-lib fan-out would be silently empty." >&2
    exit 2
  fi
}

declare -A AMBIGUOUS=()
declare -A SYNC_MEMBER=()
declare -a SCOPE_SUITES=() SCOPE_GLOBS=()
CODE_SPECS=('*.sh' '*.bash' '*.js' '*.mjs' '*.cjs' '*.py' '*.ps1' '*.psm1')
UNTRACKED=()
build_tree_index() {
  local b src copy suite
  if ! git ls-files --cached --others --exclude-standard >"$WORK_DIR/all-files" ||
    ! awk '{ sub(/.*\//, ""); if (++count[$0] == 2) print }' "$WORK_DIR/all-files" >"$WORK_DIR/ambiguous"; then
    echo "error: listing the tree failed." >&2
    exit 2
  fi
  if ! git ls-files --others --exclude-standard -- "${CODE_SPECS[@]}" >"$WORK_DIR/untracked-code"; then
    echo "error: listing the untracked code files failed." >&2
    exit 2
  fi
  [[ -s "$WORK_DIR/untracked-code" ]] && UNTRACKED=(--untracked)
  awk -v s="$STRUCTURAL_BASENAMES" '{ b = $0; sub(/.*\//, "", b) } NR == FNR { n[b]++; next }
    n[b] > 1 || b == "__init__.py" || index(s, " " b " ")' "$WORK_DIR/all-files" "$WORK_DIR/all-files" \
    >"$WORK_DIR/resolvable-files" || {
    echo "error: listing the files of the resolvable names failed." >&2
    exit 2
  }
  local grep_rc=0 wrap_rc=0 WRAP_LINES="${AFFECTED_TESTS_WRAP_LINES:-1000}"
  git grep --untracked -E '^[[:blank:]]*(from|import)[[:blank:]]' -- '*.py' >"$WORK_DIR/py-imports" || grep_rc=$?
  git grep --untracked --null -E -A "$WRAP_LINES" '^[[:blank:]]*from[[:blank:]].*import[[:blank:]]*([(][^)]*|.*\\[[:blank:]]*)$' \
    -- '*.py' >"$WORK_DIR/py-wrapped" || wrap_rc=$?
  if [[ "$grep_rc" -gt 1 || "$wrap_rc" -gt 1 ]]; then
    echo "error: 'git grep' failed (exit $grep_rc, $wrap_rc) listing the Python import lines." >&2
    exit 2
  fi
  if ! tr '\0' '\t' <"$WORK_DIR/py-wrapped" | awk -v max="$WRAP_LINES" '
    function close_open() { if (open && n >= max) cut = 1; open = 0 }
    { i = index($0, "\t") }
    i == 0 { close_open(); next }
    { p = substr($0, 1, i - 1); t = substr($0, i + 1); sub(/#.*/, "", t) }
    open && p == path {
      s = s " " t; n++
      if (paren ? index(t, ")") : t !~ /\\[[:blank:]]*$/) { print path ":" s; open = 0 }
      next
    }
    { close_open() }
    t ~ /^[[:blank:]]*from[[:blank:]].*import[[:blank:]]*(\([^)]*|.*\\[[:blank:]]*)$/ {
      path = p; s = t; open = 1; n = 0; paren = index(t, "(") > 0
    }
    END { close_open(); exit cut }' >>"$WORK_DIR/py-imports"; then
    echo "error: a wrapped Python import ran past $WRAP_LINES lines, or joining the wrapped imports failed." >&2
    exit 2
  fi
  while IFS= read -r b; do
    AMBIGUOUS["$b"]=1
  done <"$WORK_DIR/ambiguous"
  for src in "${!SYNC_SRC_COPIES[@]}"; do
    SYNC_MEMBER["$src"]=1
    while IFS= read -r copy; do
      [[ -n "$copy" ]] && SYNC_MEMBER["$copy"]=1
    done <<<"${SYNC_SRC_COPIES[$src]}"
  done

  local -a entries=() words=()
  local entry i decls
  if [[ -n "$SCOPES_LIST" ]]; then
    read_list::into entries "$SCOPES_LIST" --comments inline || exit 2
  else
    decls="$(scope_declarations "$WORK_DIR/all-files")" || exit 2
    read_list::into_text entries "$decls" --comments inline || exit 2
  fi
  for entry in ${entries[@]+"${entries[@]}"}; do
    read -r -a words <<<"$entry"
    suite="${words[0]}"
    for ((i = 1; i < ${#words[@]}; i++)); do
      SCOPE_SUITES+=("$suite")
      SCOPE_GLOBS+=("${words[i]}")
    done
  done
}

declare -A NAMED=()
TREE_GREPS=0
build_name_lines() {
  local b names_rc=0 lines_rc=0 counts_rc=0 named_rc=0
  {
    awk '{ sub(/.*\//, "") } $0 != ""' "$WORK_DIR/all-files"
    printf '%s\n' "${changed[@]##*/}" | awk '$0 != ""'
    printf '%s' ${SYNC_SRC_COPIES[@]+"${SYNC_SRC_COPIES[@]}"} | awk '{ sub(/.*\//, "") } $0 != ""'
  } | sort -u >"$WORK_DIR/names" || names_rc=2
  git grep ${UNTRACKED[@]+"${UNTRACKED[@]}"} -I -h -e '' -- "${CODE_SPECS[@]}" >"$WORK_DIR/code-lines" || lines_rc=$?
  git grep ${UNTRACKED[@]+"${UNTRACKED[@]}"} -I -c -e '' -- "${CODE_SPECS[@]}" >"$WORK_DIR/code-counts" || counts_rc=$?
  LC_ALL=C grep -naF -f "$WORK_DIR/names" "$WORK_DIR/code-lines" >"$WORK_DIR/named" || named_rc=$?
  if ((names_rc > 1 || lines_rc > 1 || counts_rc > 1 || named_rc > 1)) || ! awk '
    FILENAME == ARGV[1] {
      i = length($0); while (substr($0, i, 1) != ":") i--
      path[++n] = substr($0, 1, i - 1); end[n] = end[n - 1] + substr($0, i + 1); next
    }
    { i = index($0, ":"); ln = substr($0, 1, i - 1) + 0; while (ln > end[f]) f++; print path[f] ":" substr($0, i + 1) }
  ' "$WORK_DIR/code-counts" "$WORK_DIR/named" >"$WORK_DIR/name-lines"; then
    echo "error: reading the code lines of the tree failed." >&2
    exit 2
  fi
  rm -f "$WORK_DIR/code-lines" "$WORK_DIR/named"
  while IFS= read -r b; do NAMED["$b"]=1; done <"$WORK_DIR/names"
}

scope_declarations() {
  awk '
    { b = $0; sub(/.*\//, "", b); c = b ~ /\.test\.m?js$/ ? "//" : "#" }
    !(c == "//" || /\.test\.sh$|\.Tests\.ps1$/ || b ~ /^test_.*\.py$/) { next }
    {
      n = 0
      while ((getline line < $0) > 0) {
        sub(/\r$/, "", line)
        if (++n == 1 && line ~ /^#!/) continue
        if (index(line, c) != 1 && line !~ /^[ \t]*$/) break
        if (sub("^" c "[ \t]*test-scope:", "", line)) print $0 " " line
      }
      close($0)
    }' "$1"
}

declare -A SUITES=()
declare -a UNMAPPED=()
declare -a DELETED=()
declare -A HITS_CACHE=() GREP_CACHE=()
LOOKUPS=0

SEED_HITS=0
add_suite() {
  local suite="$1" reason="$2"
  [[ -f "$suite" ]] || return 1
  if [[ -z "${SUITES[$suite]:-}" ]]; then
    SUITES["$suite"]="$reason"
  fi
  SEED_HITS=$((SEED_HITS + 1))
  return 0
}

is_suite_path() {
  case "$1" in
  *.test.sh | *.test.js | *.test.mjs | *.Tests.ps1) return 0 ;;
  *) ;;
  esac
  case "${1##*/}" in
  test_*.py) return 0 ;;
  *) ;;
  esac
  return 1
}

LANG_FAMILY=""
lang_family() {
  case "$1" in
  *.sh | *.bash) LANG_FAMILY='sh' ;;
  *.js | *.mjs | *.cjs) LANG_FAMILY='node' ;;
  *.py) LANG_FAMILY='py' ;;
  *.ps1 | *.psm1) LANG_FAMILY='ps' ;;
  *) LANG_FAMILY="ext:${1##*.}" ;;
  esac
}

token_hits() {
  awk -v plainf="$1" -v resf="$2" -v allf="$5" -v impf="$6" '
    function dir_of(p) { sub(/[^\/]*$/, "", p); return p }
    function base_of(p) { sub(/.*\//, "", p); return p }
    function ends(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
    # Plain names: a basename that is itself a path token gets the exact test;
    # anything else keeps the substring test rather than losing coverage.
    FILENAME == plainf {
      if ($0 == "") next
      b = base_of($0)
      if (b ~ /^[A-Za-z0-9_.-]+$/) want[b] = 1
      else loose[b] = 1
      if (b ~ /\.py$/) { want_stem[substr(b, 1, length(b) - 3)] = 1; pl[b, ++npl[b]] = $0 }
      # A package initializer is reached through its package name (import_names).
      if (b == "__init__.py") rt[b, ++nrt[b]] = $0
      next
    }
    FILENAME == resf {
      if ($0 == "") next
      b = base_of($0)
      rt[b, ++nrt[b]] = $0
      next
    }
    FILENAME == allf {
      b = base_of($0)
      if (b in nrt) same[b, ++nsame[b]] = $0
      next
    }
    # R3 for a Python import, which names a module and never its file:
    # `from a.b import c as d, e` names a.py and b.py, and c.py and e.py where
    # the package a/b/ holds them, since an imported name can be a submodule.
    # Same language, so no transition.
    FILENAME == impf {
      i = index($0, ":")
      if (i == 0) next
      path = substr($0, 1, i - 1)
      text = substr($0, i + 1)
      sub(/#.*/, "", text)
      gsub(/[(),\\]/, " ", text)
      n = split(text, w, /[ \t]+/)
      from_line = 0; held = ""; mod = ""
      for (j = 1; j <= n; j++) {
        if (w[j] == "as") { j++; continue }
        if (w[j] == "") continue
        if (w[j] == "from") { from_line = 1; continue }
        if (w[j] == "import") { if (from_line) held = from_pkg(path, mod); continue }
        if (from_line && held == "") mod = w[j]
        m = split(w[j], comp, ".")
        for (k = 1; k <= m; k++) if (comp[k] != "") import_names(path, comp[k], held)
      }
      next
    }
    # from_pkg: the package directory of `from m import`, as "=" and the exact
    # directory for a relative m, or "~" and the trailing path for an absolute
    # one. Never empty, so it marks the names after `import` too.
    function from_pkg(path, m,   a, d, r) {
      d = match(m, /^\.+/) ? RLENGTH : 0
      r = substr(m, d + 1)
      gsub(/\./, "/", r)
      if (r != "") r = r "/"
      if (d == 0) return "~" r
      for (a = dir_of(path); d > 1; d--) sub(/[^\/]*\/$/, "", a)
      return "=" a r
    }
    # in_pkg: whether directory dt is the package held, "" holding everything.
    function in_pkg(dt, held,   wd) {
      if (held == "") return 1
      wd = substr(held, 2)
      if (substr(held, 1, 1) == "=") return dt == wd
      return dt == wd || ends(dt, "/" wd)
    }
    # root_of: the plugin or lib root holding p (plugins/<p>/, lib/<l>/,
    # .github/scripts/<x>/), empty outside one. An import never leaves it.
    function root_of(p) {
      if (match(p, /^(plugins|lib)\/[^\/]+\//) || match(p, /^\.github\/scripts\/[^\/]+\//))
        return substr(p, 1, RLENGTH)
      return ""
    }
    # import_names: module c, imported by path, names c.py when that is a
    # frontier path under the importer root; an ambiguous c.py resolves when it
    # is the only module of that name in the nearest directory, from the
    # importer up to its root, holding one. An imported name (held set) names
    # only a module of the package held.
    function import_names(path, c, held,   b, k, key, r) {
      b = c ".py"
      r = root_of(path)
      if (c in want_stem) for (k = 1; k <= npl[b]; k++)
        if ((r == "" || index(pl[b, k], r) == 1) && in_pkg(dir_of(pl[b, k]), held)) {
          key = path SUBSEP b
          if (!(key in kept)) order[++nkept] = key
          kept[key] = 1
          break
        }
      if (b in nrt) for (k = 1; k <= nrt[b]; k++)
        if (rt[b, k] != path && in_pkg(dir_of(rt[b, k]), held) && nearest_module(path, rt[b, k], "")) {
          key = path SUBSEP rt[b, k]
          if (!(key in rhit)) { rhit[key] = 1; print "r\t" path "\t" rt[b, k] }
        }
      # Importing package c, or anything inside it, runs c/__init__.py.
      b = "__init__.py"
      if (b in nrt) for (k = 1; k <= nrt[b]; k++)
        if (rt[b, k] != path && pkg_of(rt[b, k]) == c && in_pkg(parent_of(rt[b, k]), held) &&
          nearest_module(path, rt[b, k], c)) {
          key = path SUBSEP rt[b, k]
          if (!(key in rhit)) { rhit[key] = 1; print "r\t" path "\t" rt[b, k] }
        }
    }
    function pkg_of(p) { p = dir_of(p); sub(/\/$/, "", p); return base_of(p) }
    function parent_of(p) { p = dir_of(p); sub(/[^\/]*\/$/, "", p); return p }
    # uniq_suffix: the shortest path suffix, two components or more, that no
    # other file of the same basename ends in; empty when there is none.
    function uniq_suffix(t,   n, pa, k, j, suf, b, i, o, clash) {
      n = split(t, pa, "/")
      b = pa[n]
      for (k = 2; k <= n; k++) {
        suf = pa[n - k + 1]
        for (j = n - k + 2; j <= n; j++) suf = suf "/" pa[j]
        clash = 0
        for (i = 1; i <= nsame[b]; i++) {
          o = same[b, i]
          if (o != t && (o == suf || ends(o, "/" suf))) { clash = 1; break }
        }
        if (!clash) return suf
      }
      return ""
    }
    # resolves: does path token pt, written in file namer, mean target t? Any
    # mention from the directory of t does. A bare name does from a directory
    # above t when no other file of that name sits below that directory. A path
    # does when it ends in the shortest unique suffix of t, or in the path of t
    # relative to a directory below the root holding both files, when that
    # relative path has a directory in it ($SCRIPT_DIR/lib/x.sh,
    # $PLUGIN_DIR/skills/<s>/SKILL.md).
    function resolves(namer, pt, t,   u, a, i, b, rel) {
      a = dir_of(namer)
      if (a == dir_of(t)) return 1
      b = base_of(t)
      if (!index(pt, "/")) {
        if (a != "" && index(t, a) != 1) return 0
        for (i = 1; i <= nsame[b]; i++)
          if (same[b, i] != t && (a == "" || index(same[b, i], a) == 1)) return 0
        return 1
      }
      if (!(t in usuf)) usuf[t] = uniq_suffix(t)
      u = usuf[t]
      if (u != "" && (pt == u || ends(pt, "/" u))) return 1
      for (; a != ""; sub(/[^\/]*\/$/, "", a)) {
        if (index(t, a) != 1) continue
        rel = substr(t, length(a) + 1)
        if (index(rel, "/") && (pt == rel || ends(pt, "/" rel))) return 1
      }
      return 0
    }
    # nearest_module: whether t is the one module of its name in the nearest
    # directory, from the importer namer up to its root (root_of, else the
    # repository root), that holds any. The importer reaches it through its own
    # directory, a tests/ parent or a sys.path entry for its plugin lib/, never
    # across two candidates and never from another plugin.
    # With pkg set, t is a package __init__.py and only those of package pkg count.
    function nearest_module(namer, t, pkg,   a, b, i, n, hit, r) {
      b = base_of(t)
      r = root_of(namer)
      for (a = dir_of(namer); ; sub(/[^\/]*\/$/, "", a)) {
        n = 0; hit = 0
        for (i = 1; i <= nsame[b]; i++)
          if ((a == "" || index(same[b, i], a) == 1) && (pkg == "" || pkg_of(same[b, i]) == pkg)) {
            n++; if (same[b, i] == t) hit = 1
          }
        if (n > 0) return n == 1 && hit
        if (a == r) return 0
      }
    }
    # runs_or_loads: R4. An interpreter or process API on the line, or a path
    # to the file.
    function runs_or_loads(name, n,   j) {
      if (exec_line) return 1
      for (j = 1; j <= n; j++) if (ends(ptok[j], "/" name)) return 1
      return 0
    }
    function keep(path, name, n) {
      key = path SUBSEP name
      if (!(key in kept)) { kept[key] = 0; order[++nkept] = key }
      if (!kept[key] && runs_or_loads(name, n)) kept[key] = 1
    }
    # comment_only: a whole-line comment names nothing (COMMENTS in the header),
    # except a shellcheck source directive and a JSDoc type import.
    function comment_only(path, text) {
      if (path ~ /\.(js|mjs|cjs)$/)
        return text ~ /^[ \t]*(\/\/|\/\*|\*([ \t\/]|$))/ && text !~ /@import|import\(/
      if (text ~ /^[ \t]*#[ \t]*shellcheck[ \t]+source=/) return 0
      return text ~ /^[ \t]*#/
    }
    # code_part: a shell, Python or PowerShell line with its trailing comment
    # cut, a `#` outside quotes that starts the line or follows a blank, so
    # `${#x}` and `$#` stay code. A trailing shellcheck source directive stays.
    function code_part(text,   n, k, c, q, prev) {
      n = length(text); q = ""; prev = " "
      for (k = 1; k <= n; k++) {
        c = substr(text, k, 1)
        if (q == "\"" && c == "\\") { k++; prev = "x"; continue }
        if (q != "") { if (c == q) q = ""; prev = c; continue }
        if (c == "\"" || c == "'\''") q = c
        else if (c == "#" && (prev == " " || prev == "\t") &&
          substr(text, k) !~ /^#[ \t]*shellcheck[ \t]+source=/)
          return substr(text, 1, k - 1)
        prev = c
      }
      return text
    }
    {
      i = index($0, ":")
      # No separator means no path: git grep says "Binary file X matches" that way.
      if (i == 0) next
      path = substr($0, 1, i - 1)
      text = substr($0, i + 1)
      if (comment_only(path, text)) next
      # A Python import keeps its comment: `import x  # scripts/x.py` is how a
      # module import, which never spells the file name, names the file.
      if (path ~ /\.(sh|bash|ps1|psm1)$/ || (path ~ /\.py$/ && text !~ /^[ \t]*(import|from)[ \t]/))
        text = code_part(text)
      # A shell redirect target is written, not read: a suite that seeds a
      # fixture with `printf x >"$dir/docs/a.md"` does not read docs/a.md.
      if (path ~ /\.(sh|bash)$/) gsub(/>>?[ \t]*("[^"]*"|[^ \t;|&()<>]+)/, "", text)
      # A word, not an extension: the `.sh` of `x.sh` is no interpreter.
      exec_line = text ~ /(^|[^A-Za-z0-9_.-])(bash|sh|zsh|python3?|node|deno|pwsh|powershell|uv|npx|source|subprocess|Popen|check_output|check_call|spawn[A-Za-z0-9_]*|exec[A-Za-z0-9_]*|execa|child_process|Start-Process|Invoke-Expression)([^A-Za-z0-9_-]|$)/
      # Path tokens. A leading `.` stays: `./x`, `../x` and `.claude-plugin/x`
      # are paths, not punctuation.
      np = split(text, ptok, /[^A-Za-z0-9_.\/-]+/)
      for (j = 1; j <= np; j++) {
        sub(/\.+$/, "", ptok[j])
        sub(/^[-+=?]+/, "", ptok[j])
        b = base_of(ptok[j])
        if (!(b in nrt)) continue
        for (k = 1; k <= nrt[b]; k++)
          if (rt[b, k] != path && resolves(path, ptok[j], rt[b, k])) {
            key = path SUBSEP rt[b, k]
            if (!(key in rhit)) { rhit[key] = 1; print "r\t" path "\t" rt[b, k] }
          }
      }
      n = split(text, tok, /[^A-Za-z0-9_.-]+/)
      for (j = 1; j <= n; j++) {
        t = tok[j]
        if (t == "") continue
        if (t in want) { keep(path, t, np); continue }
        sub(/\.+$/, "", t)
        if (t in want) { keep(path, t, np); continue }
        sub(/^[-+=?.]+/, "", t)
        if (t in want) keep(path, t, np)
      }
      for (name in loose)
        if (index(text, name) > 0) {
          key = path SUBSEP name
          if (!(key in kept)) order[++nkept] = key
          kept[key] = 1
        }
    }
    END {
      for (k = 1; k <= nkept; k++) {
        split(order[k], kv, SUBSEP)
        print "p\t" kv[1] "\t" kv[2] "\t" kept[order[k]]
      }
    }
  ' "$1" "$2" "$5" "$6" "$3" >"$4"
}

package_scope_importers() {
  local manifest="$1" dir deps="" copy
  dir="${manifest%/*}"
  [[ "$dir" == "$manifest" ]] && dir="."
  for copy in "head" "${DIFF_BASE:-HEAD}"; do
    if [[ "$copy" == head ]]; then
      [[ -f "$manifest" ]] || continue
      copy="$(cat "$manifest")" || exit 2
    else
      git cat-file -e "$copy:$manifest" 2>/dev/null || continue
      copy="$(git show "$copy:$manifest")" || exit 2
    fi
    if ! copy="$(jq -r '[.dependencies, .devDependencies, .optionalDependencies, .peerDependencies]
        | map(select(type == "object") | keys[]) | unique[]' <<<"$copy")"; then
      echo "error: cannot read the dependencies of $manifest (R10 needs jq and valid JSON)." >&2
      exit 2
    fi
    deps+="$copy"$'\n'
  done
  deps="$(sort -u <<<"$deps" | sed '/^$/d')"
  [[ -n "$deps" ]] || return 0
  awk -v d="$dir/" -v deps="$deps" '
    BEGIN { n = split(deps, list, "\n"); for (i = 1; i <= n; i++) want[list[i]] = 1 }
    FNR == NR { if ($0 ~ /(^|\/)package\.json$/) { p = $0; sub(/[^\/]*$/, "", p); pkg[p] = 1 }; next }
    /(^|\/)node_modules\// || !/\.(js|mjs|cjs)$/ || /\.test\.(js|mjs|cjs)$/ { next }
    d != "./" && index($0, d) != 1 { next }
    {
      n = split($0, part, "/"); up = ""
      for (k = 1; k < n; k++) up = up part[k] "/"
      for (k = n - 1; k >= 1 && up != d; k--) {
        if (up in pkg) next
        up = substr(up, 1, length(up) - length(part[k]) - 1)
      }
      print
    }
  ' "$WORK_DIR/all-files" "$WORK_DIR/all-files" >"$WORK_DIR/scope-files"
  [[ -s "$WORK_DIR/scope-files" ]] || return 0
  awk -v deps="$deps" '
    BEGIN { n = split(deps, list, "\n"); for (i = 1; i <= n; i++) want[list[i]] = 1 }
    {
      file = $0; found = 0
      while (!found && (getline line <file) > 0)
        while (match(line, /(from|import|require)[ \t]*\(?[ \t]*["\047][^"\047]+["\047]/)) {
          spec = substr(line, RSTART, RLENGTH)
          line = substr(line, RSTART + RLENGTH)
          sub(/^[^"\047]*["\047]/, "", spec); sub(/["\047]$/, "", spec)
          name = spec
          if (name ~ /^@/) { split(name, s, "/"); name = s[1] "/" s[2] } else sub(/\/.*/, "", name)
          if (name in want) { print file; found = 1; break }
        }
      close(file)
    }' "$WORK_DIR/scope-files"
}

colocated_suites() {
  local p="$1" stem dir base candidate
  if is_suite_path "$p"; then
    printf '%s\n' "$p"
    return 0
  fi
  stem="${p%.*}"
  dir="${p%/*}"
  [[ "$dir" == "$p" ]] && dir="."
  base="${stem##*/}"
  local -a candidates=(
    "$stem.test.sh"
    "$stem.test.js"
    "$stem.test.mjs"
    "$stem.Tests.ps1"
    "$dir/test_$base.py"
    "$dir/tests/test_$base.py"
  )
  [[ "$base" == *-* ]] && candidates+=(
    "$dir/test_${base//-/_}.py"
    "$dir/tests/test_${base//-/_}.py"
  )
  for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" ]] && printf '%s\n' "$candidate"
  done
  case "${p##*/}" in
  conftest.py | __init__.py)
    awk -v d="$dir/" '{ b = $0; sub(/.*\//, "", b) } b ~ /^test_.*\.py$/ && (d == "./" || index($0, d) == 1)' \
      "$WORK_DIR/all-files"
    ;;
  *) ;;
  esac
  return 0
}

select_for() {
  local seed="$1"
  local -a frontier=() next=()
  local p b sib copy line kind hit_path hit_name hit_x grep_rc
  local origin_family hit_family hop_state
  local pattern_key plain_key resolve_key hits_key matched hits covered
  local -a index_files=()
  local -A PATTERN_ORIGIN=() PATTERN_CROSSED=() CROSSED=()
  local -A VISITED=()
  SEED_HITS=0

  local -a sources=("$seed")
  while IFS= read -r line; do
    [[ -n "$line" ]] && sources+=("$line")
  done <<<"${SYNC_SCRIPT_SRC[$seed]:-}"
  for line in "${sources[@]}"; do
    frontier+=("$line")
    while IFS= read -r copy; do
      [[ -n "$copy" ]] && frontier+=("$copy")
    done <<<"${SYNC_SRC_COPIES[$line]:-}"
  done
  if [[ "${seed##*/}" == package.json && "$seed" != *node_modules/* ]]; then
    if ! package_scope_importers "$seed" >"$WORK_DIR/scope-importers"; then
      echo "error: the package-scope import scan of $seed failed; refusing to under-select." >&2
      exit 2
    fi
    while IFS= read -r line; do
      frontier+=("$line")
    done <"$WORK_DIR/scope-importers"
  fi

  while [[ ${#frontier[@]} -gt 0 ]]; do
    : >"$WORK_DIR/patterns"
    : >"$WORK_DIR/plain"
    : >"$WORK_DIR/resolve"
    pattern_key="" plain_key="" resolve_key="" covered=1
    next=()
    for p in "${frontier[@]}"; do
      [[ -n "${VISITED[$p]:-}" ]] && continue
      VISITED["$p"]=1
      colocated_suites "$p" >"$WORK_DIR/colocated"
      while IFS= read -r sib; do
        [[ -n "$sib" ]] || continue
        if [[ "$sib" == "$p" ]]; then
          add_suite "$sib" "changed suite" || true
        else
          add_suite "$sib" "co-located with $p" || true
        fi
      done <"$WORK_DIR/colocated"
      case "$p" in
      plugins/autonomy/reference/*)
        add_suite "scripts/validate-plugin-contracts"".test.sh" \
          "path class: autonomy reference/ is gated by the contract validator" || true
        ;;
      *) ;;
      esac
      b="${p##*/}"
      [[ "$MANIFEST_BASENAMES" == *" $b "* ]] && continue
      printf '%s\n' "$b" >>"$WORK_DIR/patterns"
      [[ -n "${NAMED[$b]:-}" ]] || covered=0
      pattern_key+="$b"$'\n'
      if [[ "$STRUCTURAL_BASENAMES" == *" $b "* ]] ||
        [[ -n "${AMBIGUOUS[$b]:-}" && -z "${SYNC_MEMBER[$p]:-}" ]]; then
        printf '%s\n' "$p" >>"$WORK_DIR/resolve"
        resolve_key+="$p"$'\n'
        continue
      fi
      lang_family "$p"
      origin_family="$LANG_FAMILY"
      if [[ -z "${PATTERN_ORIGIN[$b]:-}" ]]; then
        PATTERN_ORIGIN["$b"]="$origin_family"
        PATTERN_CROSSED["$b"]="${CROSSED[$p]:-0}"
      else
        [[ "${PATTERN_ORIGIN[$b]}" == "$origin_family" ]] || PATTERN_ORIGIN["$b"]='*'
        [[ "${CROSSED[$p]:-0}" == "0" ]] && PATTERN_CROSSED["$b"]=0
      fi
      printf '%s\n' "$p" >>"$WORK_DIR/plain"
      plain_key+="$p"$'\n'
    done

    [[ -s "$WORK_DIR/patterns" ]] || break

    hits_key="$pattern_key"$'\x01'"$plain_key"$'\x01'"$resolve_key"
    hits="${HITS_CACHE[$hits_key]:-}"
    if [[ -z "$hits" ]]; then
      matched="${GREP_CACHE[$pattern_key]:-}"
      if [[ -z "$matched" ]]; then
        LOOKUPS=$((LOOKUPS + 1))
        matched="$WORK_DIR/matched-lines.$LOOKUPS"
        grep_rc=0
        if ((covered)); then
          LC_ALL=C grep -aF -f "$WORK_DIR/patterns" "$WORK_DIR/name-lines" >"$matched" || grep_rc=$?
        else
          git grep ${UNTRACKED[@]+"${UNTRACKED[@]}"} -F -f "$WORK_DIR/patterns" -- "${CODE_SPECS[@]}" \
            >"$matched" || grep_rc=$?
          TREE_GREPS=$((TREE_GREPS + 1))
          ((TREE_GREPS == ${AFFECTED_TESTS_TREE_GREPS:-16})) && build_name_lines
        fi
        if [[ "$grep_rc" -gt 1 ]]; then
          echo "error: the grep failed (exit $grep_rc) resolving dependents of the current level." >&2
          echo "       Refusing to continue: an unreadable reverse lookup silently UNDER-selects, and" >&2
          echo "       under-selection is reported as success by everything downstream." >&2
          exit 2
        fi
        GREP_CACHE["$pattern_key"]="$matched"
      fi
      LOOKUPS=$((LOOKUPS + 1))
      hits="$WORK_DIR/hits.$LOOKUPS"
      index_files=(/dev/null /dev/null)
      [[ -n "$resolve_key" || "$plain_key" == *.py$'\n'* ]] && index_files[0]="$WORK_DIR/resolvable-files"
      [[ "$plain_key$resolve_key" == *.py$'\n'* ]] && index_files[1]="$WORK_DIR/py-imports"
      if ! token_hits "$WORK_DIR/plain" "$WORK_DIR/resolve" "$matched" "$hits" "${index_files[@]}"; then
        echo "error: the token filter over the reverse lookup failed on the current level." >&2
        echo "       Refusing to continue: a partial filter silently UNDER-selects, and" >&2
        echo "       under-selection is reported as success by everything downstream." >&2
        exit 2
      fi
      HITS_CACHE["$hits_key"]="$hits"
    fi
    while IFS=$'\t' read -r kind hit_path hit_name hit_x; do
      [[ -n "$hit_path" ]] || continue
      if [[ "$kind" == r ]]; then
        if is_suite_path "$hit_path"; then
          add_suite "$hit_path" "references ${hit_name##*/} (resolves to $hit_name)" || true
        elif [[ -z "${VISITED[$hit_path]:-}" ]]; then
          CROSSED["$hit_path"]=0
          next+=("$hit_path")
        fi
        continue
      fi
      lang_family "$hit_path"
      hit_family="$LANG_FAMILY"
      origin_family="${PATTERN_ORIGIN[$hit_name]:-*}"
      if [[ "$origin_family" == '*' || "$hit_family" == "$origin_family" ]]; then
        hop_state="${PATTERN_CROSSED[$hit_name]:-0}"
      elif [[ "$origin_family" == ext:* ]]; then
        hop_state=0
      elif [[ "$hit_x" != 1 ]]; then
        continue
      elif ! is_suite_path "$hit_path" && [[ "${PATTERN_CROSSED[$hit_name]:-0}" == 1 ]]; then
        continue
      else
        hop_state=1
      fi
      if is_suite_path "$hit_path"; then
        add_suite "$hit_path" "references $hit_name" || true
        continue
      fi
      [[ -n "${VISITED[$hit_path]:-}" ]] && continue
      if [[ "${CROSSED[$hit_path]:-1}" != "0" ]]; then
        CROSSED["$hit_path"]="$hop_state"
      fi
      next+=("$hit_path")
    done <"$hits"

    frontier=(${next[@]+"${next[@]}"})
  done
}

check_scope_globs() {
  local i
  for i in "${!SCOPE_GLOBS[@]}"; do
    if [[ "${SCOPE_SUITES[i]}" == "$1" ]]; then printf '%s\n' "${SCOPE_GLOBS[i]}"; fi
  done | awk '
    # The glob dialect of the lists: `*` any run of characters, `/` included.
    function to_regex(g,   r, i, c) {
      r = "^"
      for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*") r = r ".*"
        else if (c == "?") r = r "."
        else if (index(".+(){}|^$\\", c)) r = r "\\" c
        else r = r c
      }
      return r "$"
    }
    FNR == NR { if (!($0 in want)) { want[$0] = to_regex($0); order[++n] = $0 } next }
    { for (g in want) if (!(g in hit) && $0 ~ want[g]) hit[g] = 1 }
    END { for (i = 1; i <= n; i++) if (!(order[i] in hit)) { print order[i]; bad = 1 } exit bad }
  ' - "$WORK_DIR/all-files" >"$WORK_DIR/stale-globs" && return 0
  echo "error: $1 declares test-scope globs that match no file of the tree:" >&2
  sed 's/^/  - /' "$WORK_DIR/stale-globs" >&2
  exit 2
}

select_scoped() {
  local p="$1" i
  for i in "${!SCOPE_GLOBS[@]}"; do
    # shellcheck disable=SC2053 # the right-hand side is a glob pattern by design.
    [[ "$p" == ${SCOPE_GLOBS[i]} ]] || continue
    add_suite "${SCOPE_SUITES[i]}" "test-scope ${SCOPE_GLOBS[i]}" || true
  done
}

declare -a NO_SUITE_PATTERNS=()
load_no_suite_patterns() {
  if [[ ! -f "$NO_SUITE_LIST" ]]; then
    echo "error: missing $NO_SUITE_LIST — the no-suite classification cannot be applied," >&2
    echo "       and without it every doc and manifest change would report as unmapped." >&2
    exit 2
  fi
  read_list::into NO_SUITE_PATTERNS "$NO_SUITE_LIST" --comments inline || exit 2
  if [[ ${#NO_SUITE_PATTERNS[@]} -eq 0 ]]; then
    echo "error: $NO_SUITE_LIST has no active patterns." >&2
    exit 2
  fi
}

is_no_suite() {
  local p="$1" pat
  for pat in "${NO_SUITE_PATTERNS[@]}"; do
    # shellcheck disable=SC2053 # the right-hand side is a glob pattern by design.
    [[ "$p" == $pat ]] && return 0
  done
  return 1
}

changed_from_diff() {
  local base="" mb
  if [[ -n "$base_ref" ]]; then
    if ! changed_files::verify_base "$base_ref"; then
      echo "error: base ref '$base_ref' does not resolve to a commit." >&2
      exit 2
    fi
    base="$base_ref"
  elif ! changed_files::resolve_base base; then
    echo "error: no diff base resolved (tried --base, origin/main, origin/master, main, master)." >&2
    echo "       Pass --base <ref>, or give explicit paths." >&2
    exit 2
  fi
  local merge_head_file=""
  local -a merge_heads=()
  merge_head_file="$(git rev-parse --git-path MERGE_HEAD 2>/dev/null)" || merge_head_file=""
  if [[ -n "$merge_head_file" && -f "$merge_head_file" ]]; then
    mapfile -t merge_heads <"$merge_head_file"
  fi
  mb="$(git merge-base "$base" HEAD "${merge_heads[@]}" 2>/dev/null)" || mb="$base"
  DIFF_BASE="$mb"
  if ! git diff --name-only "$mb" --; then
    echo "error: 'git diff --name-only $mb' failed; refusing to report an empty change set." >&2
    exit 2
  fi
  if ! git ls-files --others --exclude-standard; then
    echo "error: 'git ls-files --others' failed; refusing to report an empty change set." >&2
    exit 2
  fi
}

if [[ -n "$print_fanout" ]]; then
  build_sync_map
  print_fanout="${print_fanout#./}"
  if [[ -z "${SYNC_SRC_COPIES[$print_fanout]+set}" ]]; then
    echo "error: $print_fanout is not the src of any scripts/sync-*.sh manifest." >&2
    exit 2
  fi
  printf '%s' "${SYNC_SRC_COPIES[$print_fanout]}"
  exit 0
fi

replay_select() {
  local out="$1" tree="$2" sel="$3" list="$4" scopes="$5" rc=0
  shift 5
  AFFECTED_TESTS_ROOT="$tree" AFFECTED_TESTS_NO_SUITE="$list" AFFECTED_TESTS_SCOPES="$scopes" \
    bash "$sel" --explain --allow-unmapped "$@" >/dev/null 2>"$out.err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "error: the selector $sel failed (exit $rc) on a replayed commit:" >&2
    cat "$out.err" >&2
    exit 2
  fi
  awk '/^select: / { sub(/^select: /, ""); i = index($0, "  ("); print substr($0, 1, i - 1) "\t" substr($0, i + 3, length($0) - i - 3) }' \
    "$out.err" | sort >"$out.sel"
  awk '/^UNMAPPED:/ { f = 1; next } f && /^  - / { sub(/^  - /, ""); print; next } { f = 0 }' "$out.err" >"$out.unmapped"
}

run_replay() {
  local tree="$WORK_DIR/replay-tree" against="$WORK_DIR/against" against_scopes="" against_sha=""
  local c subject n_new n_old u_new u_old
  local -a commits=() changed=() against_flags=()
  if ! git rev-list --first-parent --reverse "$replay_range" >"$WORK_DIR/commits"; then
    echo "error: '$replay_range' is not a revision range git can list." >&2
    exit 2
  fi
  mapfile -t commits <"$WORK_DIR/commits"
  if [[ ${#commits[@]} -eq 0 ]]; then
    echo "error: '$replay_range' holds no commits to replay." >&2
    exit 2
  fi
  cp "$NO_SUITE_LIST" "$WORK_DIR/replay-no-suite" || exit 2
  if [[ -n "$SCOPES_LIST" ]]; then
    cp "$SCOPES_LIST" "$WORK_DIR/replay-scopes" || exit 2
  elif ! git ls-files --cached --others --exclude-standard >"$WORK_DIR/replay-files" ||
    ! scope_declarations "$WORK_DIR/replay-files" >"$WORK_DIR/replay-scopes"; then
    echo "error: could not read this tree's declared test scopes." >&2
    exit 2
  fi
  if ! git clone -q --shared --no-checkout . "$tree"; then
    echo "error: could not make the scratch clone for the replay." >&2
    exit 2
  fi
  if [[ -n "$against_ref" ]]; then
    mkdir -p "$against/scripts" || exit 2
    if ! git show "$against_ref:scripts/affected-tests.sh" >"$against/selector.orig" ||
      ! git archive "$against_ref" scripts/lib | tar -x -C "$against" ||
      ! git show "$against_ref:scripts/affected-tests-no-suite.txt" >"$against/no-suite.txt"; then
      echo "error: could not read the selector, its scripts/lib/ or its no-suite list at '$against_ref'." >&2
      exit 2
    fi
    awk '$0 == "cd \"$SCRIPT_DIR/..\" || exit 2" { print "cd \"${AFFECTED_TESTS_ROOT:-$SCRIPT_DIR/..}\" || exit 2"; n++; next }
      index($0, "AFFECTED_TESTS_ROOT") { n++ } { print } END { exit n ? 0 : 1 }' \
      "$against/selector.orig" >"$against/scripts/affected-tests.sh" || {
      echo "error: the selector at '$against_ref' cannot be pointed at another tree." >&2
      exit 2
    }
    grep -q -- '--with-always)' "$against/scripts/affected-tests.sh" && against_flags+=(--with-always)
    git show "$against_ref:scripts/affected-tests-always.txt" >"$against/always.txt" 2>/dev/null ||
      rm -f "$against/always.txt"
    against_scopes="$against/scopes.txt"
    if ! changed_files::verify_base "$against_ref" || ! against_sha="$(git rev-parse "$against_ref")" ||
      ! git -C "$tree" -c advice.detachedHead=false checkout -q --detach "$against_sha" ||
      ! git -C "$tree" ls-files >"$against/files" ||
      ! (cd "$tree" && scope_declarations "$against/files") >"$against_scopes"; then
      echo "error: could not read the declared test scopes at '$against_ref'." >&2
      exit 2
    fi
  fi

  for c in "${commits[@]}"; do
    git -C "$tree" -c advice.detachedHead=false checkout -q --detach "$c" || exit 2
    subject="$(git -C "$tree" log -1 --format=%s "$c")" || exit 2
    if ! git -C "$tree" diff --no-renames --name-only "$c^" "$c" >"$WORK_DIR/replay-changed"; then
      echo "error: could not diff $c against its parent." >&2
      exit 2
    fi
    mapfile -t changed <"$WORK_DIR/replay-changed"
    [[ ${#changed[@]} -gt 0 ]] || continue
    replay_select "$WORK_DIR/new" "$tree" "$SELF" "$WORK_DIR/replay-no-suite" "$WORK_DIR/replay-scopes" \
      -- "${changed[@]}"
    n_new=$(grep -c . "$WORK_DIR/new.sel")
    u_new=$(grep -c . "$WORK_DIR/new.unmapped")
    if [[ -z "$against_ref" ]]; then
      printf 'commit %s %s %s  %s\n' "$c" "$n_new" "$u_new" "$subject"
      sed 's/^/  unmapped /' "$WORK_DIR/new.unmapped"
      awk -F '\t' '{ print "  " $1 "  (" $2 ")" }' "$WORK_DIR/new.sel"
      printf '%s\t%s\t-\t%s\t-\n' "$c" "$n_new" "$u_new" >>"$WORK_DIR/replay-counts"
      continue
    fi
    if [[ -f "$against/always.txt" ]]; then
      awk -v root="$tree" '/^#/ || NF == 0 { print; next } { if ((getline _ < (root "/" $1)) >= 0) print; close(root "/" $1) }' \
        "$against/always.txt" >"$WORK_DIR/always-now"
      export AFFECTED_TESTS_ALWAYS="$WORK_DIR/always-now"
    fi
    replay_select "$WORK_DIR/old" "$tree" "$against/scripts/affected-tests.sh" "$against/no-suite.txt" \
      "$against_scopes" ${against_flags[@]+"${against_flags[@]}"} -- "${changed[@]}"
    n_old=$(grep -c . "$WORK_DIR/old.sel")
    u_old=$(grep -c . "$WORK_DIR/old.unmapped")
    printf 'commit %s %s %s %s %s  %s\n' "$c" "$n_new" "$n_old" "$u_new" "$u_old" "$subject"
    sed 's/^/  unmapped /' "$WORK_DIR/new.unmapped"
    awk -F '\t' 'FILENAME == ARGV[1] { n[$1] = $2; next } { o[$1] = $2 }
      END {
        for (s in n) if (!(s in o)) print "  + " s "  (" n[s] ")"
        for (s in o) if (!(s in n)) print "  - " s "  (" o[s] ")"
      }' "$WORK_DIR/new.sel" "$WORK_DIR/old.sel" | sort -k2
    printf '%s\t%s\t%s\t%s\t%s\n' "$c" "$n_new" "$n_old" "$u_new" "$u_old" >>"$WORK_DIR/replay-counts"
  done

  [[ -s "$WORK_DIR/replay-counts" ]] || {
    echo "Replayed ${#commits[@]} commit(s); none changed a file." >&2
    return 0
  }
  awk -F '\t' -v against="$against_ref" '
    function pct(a, n, q,   i) { i = int(q * n); if (i >= n) i = n - 1; return a[i + 1] }
    function sortn(a, n,   i, j, t) { for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t } }
    { nn[++c] = $2; tn += $2; un += ($4 > 0); if (against != "") { no[c] = $3; to += $3; uo += ($5 > 0) } }
    END {
      sortn(nn, c)
      printf "replay: %d commit(s); this selector: suites per commit p50 %d, p95 %d, max %d, total %d; commits with an unmapped file %d\n", c, pct(nn, c, .5), pct(nn, c, .95), nn[c], tn, un
      if (against != "") {
        sortn(no, c)
        printf "replay: %s: suites per commit p50 %d, p95 %d, max %d, total %d; commits with an unmapped file %d\n", against, pct(no, c, .5), pct(no, c, .95), no[c], to, uo
      }
    }' "$WORK_DIR/replay-counts" >&2
}

if [[ -n "$replay_range" ]]; then
  run_replay
  exit 0
fi

declare -a changed=() each_keys=()
if [[ -n "$each_from" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *:?* ]] || continue
    each_keys+=("${line%%:*}")
    changed+=("${line#*:}")
  done <"$each_from"
elif [[ ${#explicit_paths[@]} -gt 0 ]]; then
  for p in "${explicit_paths[@]}"; do
    p="${p#./}"
    case "$p" in
    "$PWD"/*) p="${p#"$PWD"/}" ;;
    /* | [A-Za-z]:[/\\]*)
      echo "error: '$p' is absolute and does not sit under this repository as spelled." >&2
      echo "       Pass repository-relative paths (Git Bash spells this checkout '$PWD')." >&2
      exit 2
      ;;
    *) ;;
    esac
    changed+=("$p")
  done
else
  changed_from_diff >"$WORK_DIR/changed.raw"
  if ! sort -u "$WORK_DIR/changed.raw" >"$WORK_DIR/changed"; then
    echo "error: sorting the changed-file list failed; refusing to report an empty change set." >&2
    exit 2
  fi
  mapfile -t changed <"$WORK_DIR/changed"
fi

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "No changed files against the base ref; nothing to select." >&2
  exit 0
fi

select_unmapped_corpus() {
  local -A corpora=()
  local f lang suite
  for f in "$@"; do
    lang_family "$f"
    case "$LANG_FAMILY" in
    sh | py | node | ps) corpora["$LANG_FAMILY"]=1 ;;
    *)
      [[ -f "$f" && "$(head -c 2 "$f" 2>/dev/null)" == '#!' ]] && corpora[sh]=1
      ;;
    esac
  done
  CORPUS_LANGS="${!corpora[*]}"
  [[ -n "$CORPUS_LANGS" ]] || return 0
  awk -v want=" $CORPUS_LANGS " '
    { b = $0; sub(/.*\//, "", b) }
    /\.test\.sh$/ { e = "sh" }
    /\.test\.m?js$/ { e = "node" }
    /\.Tests\.ps1$/ { e = "ps" }
    b ~ /^test_.*\.py$/ { e = "py" }
    e != "" && index(want, " " e " ") { print e "\t" $0 }
    { e = "" }' "$WORK_DIR/all-files" >"$WORK_DIR/corpus"
  while IFS=$'\t' read -r lang suite; do
    add_suite "$suite" "unmapped-corpus: the $lang corpus of an unmapped file" || true
  done <"$WORK_DIR/corpus"
}

run_each() {
  local i f s
  for i in "${!changed[@]}"; do
    f="${changed[i]}"
    if [[ -z "$SCOPES_LIST" && " ${SCOPE_SUITES[*]-} " == *" $f "* ]] && ! (check_scope_globs "$f") 2>/dev/null; then
      continue
    fi
    SUITES=()
    select_for "$f"
    select_scoped "$f"
    {
      if [[ "$SEED_HITS" -eq 0 ]]; then
        if is_no_suite "$f"; then
          echo "no-suite: $f (recorded in $NO_SUITE_LIST; a non-shell CI lane covers it)"
        elif [[ ! -e "$f" ]]; then
          echo "deleted: $f (no longer exists and no surviving suite names it; nothing left to cover)"
        else
          echo "UNMAPPED: 1 changed file(s) map to no test suite:"
          [[ "$unmapped_corpus" -eq 1 ]] && select_unmapped_corpus "$f"
        fi
      fi
    } >"$each_out/${each_keys[i]}.err"
    if [[ ${#SUITES[@]} -gt 0 ]]; then
      for s in "${!SUITES[@]}"; do
        case "$s" in
        *.test.js | *.test.mjs) add_suite "${s%.test.*}.test.sh" "wraps $s" || true ;;
        *) ;;
        esac
      done
      printf '%s\n' "${!SUITES[@]}" | sort -u
    fi >"$each_out/${each_keys[i]}.out"
  done
}

build_sync_map
load_no_suite_patterns
build_tree_index

if [[ -n "$each_from" ]]; then
  run_each
  exit 0
fi

declare -a NO_SUITE_FILES=()
for f in "${changed[@]}"; do
  [[ -n "$f" ]] || continue
  [[ -z "$SCOPES_LIST" && " ${SCOPE_SUITES[*]-} " == *" $f "* ]] && check_scope_globs "$f"
  select_for "$f"
  select_scoped "$f"
  if [[ "$SEED_HITS" -eq 0 ]]; then
    if is_no_suite "$f"; then
      NO_SUITE_FILES+=("$f")
    elif [[ ! -e "$f" ]]; then
      DELETED+=("$f")
    else
      UNMAPPED+=("$f")
    fi
  fi
done

if [[ ${#NO_SUITE_FILES[@]} -gt 0 && "$explain" -eq 1 ]]; then
  for f in "${NO_SUITE_FILES[@]}"; do
    echo "no-suite: $f (recorded in $NO_SUITE_LIST; a non-shell CI lane covers it)" >&2
  done
fi

if [[ ${#DELETED[@]} -gt 0 ]]; then
  printf 'deleted: %s (no longer exists and no surviving suite names it; nothing left to cover)\n' "${DELETED[@]}" >&2
fi

corpus_used=0
if [[ ${#UNMAPPED[@]} -gt 0 ]]; then
  echo "UNMAPPED: ${#UNMAPPED[@]} changed file(s) map to no test suite:" >&2
  printf '  - %s\n' "${UNMAPPED[@]}" >&2
  echo "This is NOT 'nothing to run' — it is 'this tool does not know what covers these'." >&2
  echo "Fix one of: add a co-located <stem>.test.sh; make a suite name the file; declare a" >&2
  echo "test-scope on the suite that reads it; or record the path class in $NO_SUITE_LIST" >&2
  echo "with the CI lane that does cover it." >&2
  if [[ "$unmapped_corpus" -eq 1 ]]; then
    select_unmapped_corpus "${UNMAPPED[@]}"
    if [[ -n "$CORPUS_LANGS" ]]; then
      echo "Selecting the whole corpus of each unmapped code file's language under --unmapped-corpus: $CORPUS_LANGS." >&2
    else
      echo "Every unmapped file is data no suite reads; --unmapped-corpus selects no corpus for it." >&2
    fi
    corpus_used=1
  elif [[ "$allow_unmapped" -eq 0 ]]; then
    echo "Re-run with --allow-unmapped to proceed anyway." >&2
    exit 1
  else
    echo "Proceeding under --allow-unmapped." >&2
  fi
fi

declare -a selected=()
if [[ ${#SUITES[@]} -gt 0 ]]; then
  for s in "${!SUITES[@]}"; do
    case "$s" in
    *.test.js | *.test.mjs) add_suite "${s%.test.*}.test.sh" "wraps $s" || true ;;
    *) ;;
    esac
  done
  if ! printf '%s\n' "${!SUITES[@]}" | sort -u >"$WORK_DIR/selected"; then
    echo "error: sorting the selected-suite list failed; refusing to report an empty selection" >&2
    echo "       when ${#SUITES[@]} suite(s) were selected." >&2
    exit 2
  fi
  mapfile -t selected <"$WORK_DIR/selected"
fi

if [[ ${#selected[@]} -eq 0 ]]; then
  if [[ "$corpus_used" -eq 1 ]]; then
    echo "No suites selected (every unmapped file is data no suite reads)." >&2
    exit 4
  fi
  echo "No suites selected (every changed file is a recorded no-suite class or a deletion)." >&2
  exit 0
fi

if [[ "$shard_total" -gt 1 ]]; then
  declare -a leg=()
  for ((si = shard_index; si < ${#selected[@]}; si += shard_total)); do
    leg+=("${selected[$si]}")
  done
  echo "shard: leg $shard_index of $shard_total keeps ${#leg[@]} of ${#selected[@]} selected suite(s)." >&2
  if [[ ${#leg[@]} -eq 0 ]]; then
    echo "error: leg $shard_index of $shard_total draws none of the ${#selected[@]} selected suite(s); use at most ${#selected[@]} leg(s)." >&2
    exit 2
  fi
  selected=("${leg[@]}")
fi

if [[ "$explain" -eq 1 ]]; then
  for s in "${selected[@]}"; do
    echo "select: $s  (${SUITES[$s]})" >&2
  done
fi

if [[ "$do_run" -eq 0 ]]; then
  printf '%s\n' "${selected[@]}"
  [[ "$corpus_used" -eq 1 ]] && exit 4
  exit 0
fi

declare -a runnable=() delegated=()
for s in "${selected[@]}"; do
  case "$s" in
  *.test.sh) runnable+=("$s") ;;
  *) delegated+=("$s") ;;
  esac
done
if [[ -n "$not_run_file" && ${#delegated[@]} -gt 0 ]] &&
  ! printf '%s\n' "${delegated[@]}" >"$not_run_file"; then
  echo "error: cannot write --write-not-run file: $not_run_file" >&2
  exit 2
fi

if venv_bin=$(pytest_python::venv_bin); then
  PATH="$venv_bin:$PATH"
fi

failed=0
if [[ ${#runnable[@]} -gt 0 ]] && [[ "$jobs" -gt 1 || -n "$budget" ]]; then
  echo "Running ${#runnable[@]} selected shell suite(s) across up to $jobs job(s)${budget:+ within a ${budget}s budget}." >&2
  list="$WORK_DIR/selection.txt"
  printf '%s\n' "${runnable[@]}" >"$list"
  bash "$SCRIPT_DIR/run-plugin-tests.sh" --jobs "$jobs" ${budget:+--budget "$budget"} --suites-from "$list" || failed=1
elif [[ ${#runnable[@]} -gt 0 ]]; then
  echo "Running ${#runnable[@]} selected shell suite(s) sequentially." >&2
  n=0
  for s in "${runnable[@]}"; do
    n=$((n + 1))
    echo "=== $s ==="
    if (test_git_env::isolate "$WORK_DIR/gitconfig.$n" && bash "$s"); then
      echo "PASS: $s"
    else
      echo "FAIL: $s" >&2
      failed=1
    fi
  done
fi

if [[ ${#delegated[@]} -gt 0 ]]; then
  echo "NOT RUN: ${#delegated[@]} selected suite(s) belong to an ecosystem this" >&2
  echo "runner does not execute. They are SELECTED, not skipped — run each from" >&2
  echo "its own lane:" >&2
  printf '  - %s\n' "${delegated[@]}" >&2
fi

if [[ "$failed" -ne 0 ]]; then
  echo "One or more selected suites failed." >&2
  exit 1
fi
if [[ ${#delegated[@]} -gt 0 ]]; then
  echo "${#runnable[@]} shell suite(s) passed or were skipped; ${#delegated[@]} still need their own lane." >&2
  exit 3
fi
if [[ "$corpus_used" -eq 1 ]]; then
  echo "All ${#runnable[@]} selected suites passed or were skipped, including an unmapped file's corpus." >&2
  exit 4
fi
echo "All ${#runnable[@]} selected suites passed or were skipped."
