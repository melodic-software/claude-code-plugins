#!/usr/bin/env bash
# sample.sh: build the unlabeled calibration set. Draws the in-use stratum from
# the git histories of three repositories, then assigns every case file of
# labels.tsv a split. Refuses once any label cell is filled. Reads the
# repositories only (git log, git show, git ls-tree, git grep); writes cases/u*/
# and labels.tsv here.
#
#   sample.sh [<directory holding the three clones>]
#
# Population (design DT13): every test block a commit created or changed, in a
# file an adapter claims, outside fixtures and testdata directories, up to the
# commits pinned below; "changed" is the scanner's --blocks --lines over the
# lines the commit added, as the hooks scope a write. Draw, in two phases:
# shuffle the (commit, test file) pairs whose commit added lines to the file
# and take the first PAIRS, list every block each one changed, then shuffle
# that pool and take TARGET blocks. Each phase is uniform, so every block has
# the same chance and the stratum keeps the population's FLAG prevalence.
#
# A case is the test file plus the code it tests, at the same commit, each
# copied verbatim to cases/<id>/<repository path>.fixture. The code under test
# is found from the test's text (resolve below). A pair whose code cannot be
# resolved, whose file the scanner cannot read, or whose lexer lost sync, is
# dropped in phase 1 and counted, before any block is drawn.
#
# Split: within each stratum, case files are shuffled with SEED and taken as
# holdout until holdout holds at least a third of the stratum's rows, so no file
# has rows on both sides. Every shuffle is Fisher-Yates over Park-Miller
# (16807 * x mod 2^31-1), exact in any awk, so the draw does not depend on the
# platform's RNG.
#
# Prints the draw's counts, including how many drawn blocks carry a finding
# from the scanner's provenance-shaped rules (rule-recomputed-expectation,
# rule-constant-restatement, rule-recomputed-derived; design DT7).
set -uo pipefail

SEED=20260930
TARGET=60
PAIRS=240
CAP=20
REPOS=(
  "claude-code-plugins fa4142d113fdf3a0da352d27dcfb373f2ac398b1"
  "medley 4a7c01a14a31199076c5f22eb313d6dea1c7c4ce"
  "ci-runner 18f5366fdb1d88b9880bc0323c976a3c94fbc832"
)
export TESTS='\.(test|spec)\.(js|jsx|ts|tsx|mjs|cjs)$|Tests?\.cs$|\.bats$|_test\.go$|\.test\.sh$|\.Tests\.ps1$|(^|/)test_[^/]*\.py$|_test\.py$'
export PROVENANCE='testing/audit/rule-(recomputed-expectation|constant-restatement|recomputed-derived)[]]'
SRC='sh|bash|js|mjs|cjs|ts|tsx|jsx|mts|cts|py|ps1|psm1|go|cs|awk'

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCANNER="$HERE/../../scripts/cant-fail-scan.sh"
LABELS="$HERE/labels.tsv"
ROOT="${1:-$HOME/repos/github.com/melodic-software}"

# shuffle: the input lines in Park-Miller Fisher-Yates order, seeded by $1.
shuffle() {
  awk -v st="$1" '{ a[++n] = $0 }
    END {
      for (i = n; i > 1; i--) { st = (16807 * st) % 2147483647; j = st % i + 1; t = a[i]; a[i] = a[j]; a[j] = t }
      for (i = 1; i <= n; i++) print a[i]
    }'
}

# resolve <repo> <commit> <test path> <test file>: print, one per line and at
# most CAP, the repository paths at <commit> of the code the test imports or
# calls: files named by the test's stem (foo.test.ts -> foo.ts, test_foo.py ->
# foo.py, Foo.Tests.ps1 -> Foo.ps1, FooTests.cs -> Foo.cs), every path or
# relative import the text names, Python modules it imports, the package's
# other files for Go, and the files declaring the C# types it names. A name is
# tried against the test's directory, then the repository root, then as a path
# suffix anywhere, nearest the test first. Other test files are left out.
# ponytail: one level only (what the test names, not what that code imports); text heuristics, so a path built at run time is missed.
resolve() {
  local r="$1" c="$2" p="$3" f="$4" d stem ids
  d="$(dirname "$p")"
  git -C "$r" ls-tree -r --name-only "$c" >"$TMP/tree"
  stem="${p##*/}"
  stem="$(sed -E 's/\.(test|spec)\.[a-z]+$//; s/_test\.(go|py)$//; s/^test_(.*)\.py$/\1/; s/\.Tests\.ps1$//; s/Tests?\.cs$//; s/\.(bats|test\.sh)$//' <<<"$stem")"
  {
    echo "./$stem"
    [[ "$p" == *.py ]] && echo "py:$stem"
    grep -oE "[A-Za-z0-9_./\${}@-]*[A-Za-z0-9_-]\.($SRC)\b" "$f"
    grep -oE "['\"]\.\.?/[^'\"]+['\"]" "$f" | tr -d "'\""
    sed -nE 's/^[[:space:]]*from[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*)[[:space:]]+import[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1 \1.\2/p
      s/^[[:space:]]*import[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*).*/\1/p' "$f" | tr ' .' '\n/' | sed 's#^#py:#'
    [[ "$p" == *.go ]] && awk -v d="$d" '{ x = $0; sub(/\/[^\/]*$/, "", x) } x == d && /\.go$/ && !/_test\.go$/' "$TMP/tree"
    if [[ "$p" == *.cs ]]; then
      ids="$(grep -oE '\b[A-Z][A-Za-z0-9_]{2,}\b' "$f" | sort -u | head -n 300 | paste -sd'|')"
      [[ -z "$ids" ]] || git -C "$r" grep -lE "(class|record|struct|interface|enum)[[:space:]]+($ids)\b" "$c" -- '*.cs' | sed "s#^$c:##"
    fi
  } | awk -v d="$d" -v self="$p" -v cap="$CAP" '
    function norm(x,   n, i, k, out, s) {
      n = split(x, s, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (s[i] == "" || s[i] == ".") continue
        if (s[i] == "..") { if (k) k--; continue }
        out[++k] = s[i]
      }
      x = ""; for (i = 1; i <= k; i++) x = x (i > 1 ? "/" : "") out[i]
      return x
    }
    function near(a,   n, m, i, s, t) {
      n = split(a, s, "/"); m = split(d, t, "/")
      for (i = 1; i < n && i <= m && s[i] == t[i]; i++);
      return i
    }
    function exact(x,   e, k) {
      split(",.ts,.tsx,.js,.mjs,.cjs,.py,.sh,.ps1,.psm1,/index.ts,/index.js,/__init__.py", e, ",")
      for (k = 1; k <= 13; k++) if ((x e[k]) in tree) return x e[k]
      return ""
    }
    function suffix(x,   q, best, b, s, e, k, n) {
      split(",.py,/__init__.py", e, ","); best = ""; b = -1
      for (k = 1; k <= 3; k++) {
        if (!((x e[k]) in tail)) continue
        n = split(tail[x e[k]], q, SUBSEP)
        for (s = 1; s <= n; s++) if (near(q[s]) > b || (near(q[s]) == b && length(q[s]) < length(best))) { best = q[s]; b = near(q[s]) }
      }
      return best
    }
    FNR == NR {
      tree[$0] = 1
      m = split($0, s, "/"); x = ""
      for (i = m; i >= 1; i--) { x = s[i] (x == "" ? "" : "/" x); tail[x] = (x in tail) ? tail[x] SUBSEP $0 : $0 }
      next
    }
    {
      x = $0; py = sub(/^py:/, "", x)
      sub(/^.*[$][({]?[A-Za-z_][A-Za-z0-9_]*[)}]?\//, "", x)
      if (x == "") next
      hit = ""
      if (x ~ /^\.\.?\//) hit = exact(norm(d "/" x))
      else {
        if (!py) hit = exact(norm(d "/" x))
        if (hit == "") hit = exact(norm(x))
        if (hit == "" && (py || x ~ /\.[A-Za-z0-9]+$/)) hit = suffix(norm(x))
      }
      if (hit == "" || hit == self || hit ~ ENVIRON["TESTS"] || (hit in seen)) next
      seen[hit] = 1
      print hit
      if (++n >= cap) exit
    }' "$TMP/tree" -
}

[[ -f "$LABELS" ]] || {
  echo "sample.sh: no $LABELS" >&2
  exit 2
}
if awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
  $c["human_label"] $c["model_label"] $c["adjudicated_label"] $c["judge_verdict"] != "" { f = 1 } END { exit !f }' "$LABELS"; then
  echo "sample.sh: labels.tsv already holds labels; redrawing would orphan them" >&2
  exit 1
fi

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "${TMP:?}"' EXIT

for spec in "${REPOS[@]}"; do
  read -r name sha <<<"$spec"
  git -C "$ROOT/$name" cat-file -e "$sha^{commit}" 2>/dev/null || {
    echo "sample.sh: $ROOT/$name lacks $sha" >&2
    exit 2
  }
  git -C "$ROOT/$name" log --no-renames --format='C %H' --numstat "$sha" |
    awk -v r="$name" '/^C / { c = $2; next }
      NF >= 3 && $1 != "-" && $1 > 0 {
        p = $0; sub(/^[^\t]*\t[^\t]*\t/, "", p)
        if (p ~ ENVIRON["TESTS"] && p !~ /(^|\/)(fixtures|testdata|__fixtures__)\//) print r "\t" c "\t" p
      }'
done | LC_ALL=C sort -u >"$TMP/pairs"

# Phase 1: the first PAIRS pairs, every block each changed. Pool lines:
# pair, ordinal, start, end, pre-screen hit (0 or 1), name.
skipped=0 unresolved=0 unresolved_blocks=0 k=0
: >"$TMP/pool"
while IFS=$'\t' read -r name commit path; do
  k=$((k + 1))
  mkdir -p "$TMP/p$k"
  printf '%s\t%s\t%s\n' "$name" "$commit" "$path" >"$TMP/p$k/pair"
  f="$TMP/p$k/${path##*/}"
  git -C "$ROOT/$name" show "$commit:$path" >"$f" 2>/dev/null || {
    skipped=$((skipped + 1))
    continue
  }
  # The lines this commit added or changed in the file, as "start-end" ranges.
  git -C "$ROOT/$name" show --no-renames --format= -U0 "$commit" -- "$path" |
    sed -nE 's/^@@ -[0-9,]+ \+([0-9]+)(,([0-9]+))? @@.*/\1 \3/p' |
    awk '{ n = ($2 == "" ? 1 : $2); if (n > 0) printf "%s%d-%d", (k++ ? "," : ""), $1, $1 + n - 1 }' >"$TMP/p$k/ranges"
  [[ -s "$TMP/p$k/ranges" ]] || continue
  lines="$(tr ',' '\n' <"$TMP/p$k/ranges" | awk -F- '{ for (i = $1; i <= $2; i++) printf "%s%d", (k++ ? "," : ""), i }')"
  if ! bash "$SCANNER" --file "$f" --blocks --lines "$lines" >"$TMP/p$k/scan" 2>&1 ||
    grep -q 'lost sync (not judged): [1-9]' "$TMP/p$k/scan"; then
    skipped=$((skipped + 1))
    continue
  fi
  grep -q '^block ' "$TMP/p$k/scan" || continue
  resolve "$ROOT/$name" "$commit" "$path" "$f" >"$TMP/p$k/code"
  if [[ ! -s "$TMP/p$k/code" ]]; then
    unresolved=$((unresolved + 1))
    unresolved_blocks=$((unresolved_blocks + $(grep -c '^block ' "$TMP/p$k/scan")))
    continue
  fi
  awk -v k="$k" '
    $1 == "finding" && $0 ~ ENVIRON["PROVENANCE"] { n = $3; sub(/:[^:]*$/, "", n); sub(/^.*:/, "", n); hit[n + 0] = 1 }
    $1 == "block" { b[++nb] = $0 }
    END {
      for (i = 1; i <= nb; i++) {
        split(b[i], w, " "); r = w[2]; sub(/^.*:/, "", r); split(r, se, "-")
        name = b[i]; sub(/^block [^ ]+ [0-9]+ /, "", name)
        h = 0; for (l in hit) if (l + 0 >= se[1] + 0 && l + 0 <= se[2] + 0) h = 1
        print k "\t" w[3] "\t" se[1] "\t" se[2] "\t" h "\t" name
      }
    }' "$TMP/p$k/scan" >>"$TMP/pool"
done < <(shuffle "$SEED" <"$TMP/pairs" | head -n "$PAIRS")

# Phase 2: TARGET blocks of the pool, written in pool order.
shuffle "$SEED" <"$TMP/pool" | head -n "$TARGET" | sort -t$'\t' -k1,1n -k3,3n >"$TMP/drawn"
find "$HERE/cases" -mindepth 1 -maxdepth 1 -name 'u[0-9]*' -exec rm -rf {} +
: >"$TMP/rows"
id="" last="" j=0 n=0
while IFS=$'\t' read -r p ord _ _ _ bname; do
  if [[ "$p" != "$last" ]]; then
    last="$p" j=0 n=$((n + 1))
    id="$(printf 'u%02d' "$n")"
    IFS=$'\t' read -r name commit path <"$TMP/p$p/pair"
    mkdir -p "$(dirname "$HERE/cases/$id/$path")"
    cp "$TMP/p$p/${path##*/}" "$HERE/cases/$id/$path.fixture"
    while read -r c; do
      mkdir -p "$(dirname "$HERE/cases/$id/$c")"
      git -C "$ROOT/$name" show "$commit:$c" >"$HERE/cases/$id/$c.fixture"
    done <"$TMP/p$p/code"
    adapter="$(sed -n 's/^  adapter: //p' "$TMP/p$p/scan" | head -n 1)"
  fi
  j=$((j + 1))
  test="$bname"
  ((ord > 1)) && test+=" #$ord"
  printf '%s-%d\t%s:%s@%s\t%s\tcases/%s/%s.fixture\t%s\t\t\t\t\t\t\tchanged %s; code under test: %s\tin-use\t\n' \
    "$id" "$j" "$name" "$path" "$commit" "$adapter" "$id" "$path" "$test" "$(<"$TMP/p$p/ranges")" \
    "$(paste -sd' ' "$TMP/p$p/code")" >>"$TMP/rows"
done <"$TMP/drawn"

# Keep the authored strata, replace in-use, then split every stratum by file.
{
  head -n 1 "$LABELS"
  awk -F'\t' 'NR > 1 && $13 != "in-use"' "$LABELS"
  cat "$TMP/rows"
} >"$TMP/all"
awk -F'\t' 'NR > 1 { print $13 }' "$TMP/all" | awk '!seen[$0]++' >"$TMP/strata"
: >"$TMP/holdout"
while read -r s; do
  awk -F'\t' -v s="$s" 'NR > 1 && $13 == s { n[$4]++; if (!seen[$4]++) o[++m] = $4 } END { for (i = 1; i <= m; i++) print n[o[i]] "\t" o[i] }' "$TMP/all" |
    shuffle "$SEED" | awk -F'\t' '{ a[NR] = $0; t += $1 } END { for (i = 1; i <= NR && 3 * h < t; i++) { split(a[i], x, "\t"); h += x[1]; print x[2] } }' >>"$TMP/holdout"
done <"$TMP/strata"
awk -F'\t' -v OFS='\t' 'NR == FNR { h[$1] = 1; next } FNR > 1 { $14 = ($4 in h) ? "holdout" : "tune" } 1' \
  "$TMP/holdout" "$TMP/all" >"$LABELS"

echo "population: $(wc -l <"$TMP/pairs") pairs; phase 1: $k pairs, $skipped unreadable, $unresolved dropped with unresolved code ($unresolved_blocks blocks), $(wc -l <"$TMP/pool") blocks kept"
echo "phase 2: $(wc -l <"$TMP/drawn") blocks in $n files; provenance-shaped scanner findings: $(awk -F'\t' '{ s += $5 } END { print s + 0 }' "$TMP/drawn") drawn, $(awk -F'\t' '{ s += $5 } END { print s + 0 }' "$TMP/pool") in the pool"
awk -F'\t' 'NR > 1 { n[$13]++; h[$13] += $14 == "holdout"; if (!f[$4]++) { fn[$13]++; fh[$13] += $14 == "holdout" } } END { for (s in n) print s ": " n[s] " rows in " fn[s] " files, holdout " h[s] " rows in " fh[s] " files" }' "$LABELS"
