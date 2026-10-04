#!/usr/bin/env bash
# Builds a small site repository with a frozen harness, then leaves a climb run mid-way:
# attempt a2 is committed on climb/template-parses and does not change the parse count.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p pages templates
for page in about blog contact docs home; do printf '%s\n' "$page" >"pages/$page.txt"; done
for template in footer header nav; do printf '<%s>\n' "$template" >"templates/$template.html"; done

cat >render.sh <<'EOF'
#!/usr/bin/env bash
# Renders every page, reading each template once per page.
set -euo pipefail
for page in pages/*.txt; do
  for template in templates/*.html; do
    : "$(<"$template")"
    printf 'PARSE %s\n' "$template"
  done
  printf 'PAGE %s\n' "$page"
done
EOF

cat >bench.sh <<'EOF'
#!/usr/bin/env bash
# Frozen harness: runs the render and prints the counter, the error count and the work count.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
out="$(bash render.sh)"
rc=$?
parses="$(grep -c '^PARSE ' <<<"$out")"
pages="$(grep -c '^PAGE ' <<<"$out")"
errors=0
[[ $rc -eq 0 ]] || errors=1
printf 'parses=%s errors=%s pages=%s\n' "$parses" "$errors" "$pages"
EOF

cat >test.sh <<'EOF'
#!/usr/bin/env bash
# Project test: every page renders once.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ "$(bash render.sh | grep -c '^PAGE ')" -eq "$(find pages -name '*.txt' | wc -l)" ]]
echo "test: pass"
EOF

printf '.work/\nclimb-worktrees/\n' >.gitignore
git add .gitignore pages templates render.sh bench.sh test.sh
git commit -q -m "site build with a frozen parse-count harness"
start="$(git rev-parse HEAD)"

slice=".work/site-build/climb/template-parses"
mkdir -p "$slice"
printf '{"counter": "parses", "direction": "lower", "gain_floor": 0}\n' >"$slice/keep-rule.json"
printf 'id\thypothesis\tchange\tbefore\tafter\tdelta\ttests\tverdict\tnote\n' >"$slice/log.tsv"
printf 'a1\tnav is parsed for pages that never show it\tskip nav for pages without a menu\t15\t15\t0\tpass\treverted\tdropped 0f3c2aa\n' >>"$slice/log.tsv"

# The two worktrees sit in an ignored directory inside the eval workspace, so removing the
# workspace at the end of the run removes them too; nothing is left under the system temp.
root="$PWD/climb-worktrees"
git worktree add -q -b climb/template-parses "$root/climb" "$start"
git worktree add -q --detach "$root/baseline" "$start"
printf '# templates are read in name order\n' >>"$root/climb/render.sh"
git -C "$root/climb" commit -q -am "a2: read templates in name order"
attempt="$(git -C "$root/climb" rev-parse HEAD)"

cat >"$slice/state.txt" <<EOF
goal: parses lower, Realistic target 5, min_attempts 4
harness: bash bench.sh (frozen at $start, discriminate exit 0)
tests: bash test.sh
checkout: $PWD
climb worktree: $root/climb (branch climb/template-parses)
baseline worktree: $root/baseline (detached)
last kept: $start
attempt a2: $attempt
attempt a2 hypothesis: reading templates in name order lets later pages reuse the parse
keep rule: $PWD/$slice/keep-rule.json
log: $PWD/$slice/log.tsv
EOF
