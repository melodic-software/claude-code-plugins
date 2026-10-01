#!/usr/bin/env bash
# sample.sh: build the unlabeled calibration set. Draws the in-use stratum from
# the git histories of three repositories, then assigns every row of labels.tsv
# a split. Refuses once any label cell is filled. Reads the repositories only
# (git log and git show); writes cases/u*.fixture and labels.tsv here.
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
# the same chance and the stratum keeps the population's FLAG prevalence. A
# pair whose file the scanner cannot read, whose lexer lost sync, or that fails
# this repository's typos check is skipped and counted. A case file is the
# whole test file at that commit, verbatim.
#
# Split: within each stratum, rows are shuffled with SEED and the first third,
# rounded up, is holdout. Every shuffle is Fisher-Yates over Park-Miller
# (16807 * x mod 2^31-1), exact in any awk, so the draw does not depend on the
# platform's RNG.
#
# Prints the draw's counts, including the deterministic pre-screen: how many
# drawn blocks carry a finding from the scanner's provenance rules
# (rule-recomputed-expectation, rule-constant-restatement,
# rule-recomputed-derived; design DT7). The pre-screen is the scanner's
# verdict, not a label.
set -uo pipefail

SEED=20260930
TARGET=60
PAIRS=240
REPOS=(
  "claude-code-plugins fa4142d113fdf3a0da352d27dcfb373f2ac398b1"
  "medley 4a7c01a14a31199076c5f22eb313d6dea1c7c4ce"
  "ci-runner 18f5366fdb1d88b9880bc0323c976a3c94fbc832"
)
export TESTS='\.(test|spec)\.(js|jsx|ts|tsx|mjs|cjs)$|Tests?\.cs$|\.bats$|_test\.go$|\.test\.sh$|\.Tests\.ps1$|(^|/)test_[^/]*\.py$|_test\.py$'
export PROVENANCE='testing/audit/rule-(recomputed-expectation|constant-restatement|recomputed-derived)[]]'

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCANNER="$HERE/../../scripts/cant-fail-scan.sh"
LABELS="$HERE/labels.tsv"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 2
ROOT="${1:-$HOME/repos/github.com/melodic-software}"

# shuffle: the input lines in Park-Miller Fisher-Yates order, seeded by $1.
shuffle() {
  awk -v st="$1" '{ a[++n] = $0 }
    END {
      for (i = n; i > 1; i--) { st = (16807 * st) % 2147483647; j = st % i + 1; t = a[i]; a[i] = a[j]; a[j] = t }
      for (i = 1; i <= n; i++) print a[i]
    }'
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
skipped=0 misspelled=0 k=0
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
  # A verbatim case cannot be edited to pass this repository's spell-check.
  # ponytail: drops files the spell-check rejects; a caller-side typos exclude for cases/ would end the skip.
  if ! typos --config "$TOP/_typos.toml" "$f" >/dev/null 2>&1; then
    misspelled=$((misspelled + 1))
    continue
  fi
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
rm -f "$HERE"/cases/u[0-9]*.fixture
: >"$TMP/rows"
id="" last="" j=0 n=0
while IFS=$'\t' read -r p ord _ _ _ bname; do
  if [[ "$p" != "$last" ]]; then
    last="$p" j=0 n=$((n + 1))
    id="$(printf 'u%02d' "$n")"
    IFS=$'\t' read -r name commit path <"$TMP/p$p/pair"
    base="${path##*/}"
    cp "$TMP/p$p/$base" "$HERE/cases/$id.$base.fixture"
    adapter="$(sed -n 's/^  adapter: //p' "$TMP/p$p/scan" | head -n 1)"
  fi
  j=$((j + 1))
  test="$bname"
  ((ord > 1)) && test+=" #$ord"
  printf '%s-%d\t%s:%s@%s\t%s\tcases/%s.%s.fixture\t%s\t\t\t\t\t\t\tchanged %s\tin-use\t\n' \
    "$id" "$j" "$name" "$path" "$commit" "$adapter" "$id" "$base" "$test" "$(<"$TMP/p$p/ranges")" >>"$TMP/rows"
done <"$TMP/drawn"

# Keep the authored strata, replace in-use, then split every stratum.
{
  head -n 1 "$LABELS"
  awk -F'\t' 'NR > 1 && $13 != "in-use"' "$LABELS"
  cat "$TMP/rows"
} >"$TMP/all"
awk -F'\t' 'NR > 1 { print $13 }' "$TMP/all" | awk '!seen[$0]++' >"$TMP/strata"
: >"$TMP/holdout"
while read -r s; do
  awk -F'\t' -v s="$s" 'NR > 1 && $13 == s { print $1 }' "$TMP/all" | shuffle "$SEED" >"$TMP/ids"
  head -n $((($(wc -l <"$TMP/ids") + 2) / 3)) "$TMP/ids" >>"$TMP/holdout"
done <"$TMP/strata"
awk -F'\t' -v OFS='\t' 'NR == FNR { h[$1] = 1; next } FNR > 1 { $14 = ($1 in h) ? "holdout" : "tune" } 1' \
  "$TMP/holdout" "$TMP/all" >"$LABELS"

echo "population: $(wc -l <"$TMP/pairs") pairs; phase 1: $k pairs, $skipped unreadable, $misspelled failing the spell-check, $(wc -l <"$TMP/pool") blocks changed"
echo "phase 2: $(wc -l <"$TMP/drawn") blocks in $n files; pre-screen provenance findings: $(awk -F'\t' '{ s += $5 } END { print s + 0 }' "$TMP/drawn") drawn, $(awk -F'\t' '{ s += $5 } END { print s + 0 }' "$TMP/pool") in the pool"
awk -F'\t' 'NR > 1 { n[$13]++; h[$13] += $14 == "holdout" } END { for (s in n) print s ": " n[s] " rows, holdout " h[s] }' "$LABELS"
