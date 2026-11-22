# hotspots: plain-git churn×complexity recipe (Tier 0, evidence rung 2)

Mechanical, reproducible hotspot scoring with nothing but git and POSIX tools. Output: a ranked
set of churn×complexity hotspot files, each carrying an evidence citation in the shape the
candidate table expects, e.g. `hotspot: 14 commits/90d × indent 412 (1,038 LOC) — rung 2`.

The method (Tornhill's hotspot analysis, productized as CodeScene) combines two orthogonal
per-file signals: **change frequency** (how often the file appears in commits over a window,
mined from `git log`) and **complexity**. CodeScene's canonical mechanical complexity metric is
**indentation-based complexity**: logical indentations counted with blank lines stripped, chosen
because it is fast, automated, and language-neutral. This recipe uses that proxy and
records LOC alongside it.

## Step 0: history-depth gate (always first)

Every `git` command in this recipe runs against the target repository's root. When the target
is not the session's working directory, prefix each with `git -C <target-root>` (root resolved
per SKILL.md "Repo as parameter") so the evidence never comes from the invoking repo. Replace `<target-root>` in the Step 3
block with the resolved root in every case, including when the target is the session's own
repository.

Churn from partial history produces confidently-wrong rankings, which are worse than no
rankings. Run this gate before counting anything:

```bash
# 1. Shallow clone? (any checkout can be; the gate never assumes full history)
git rev-parse --is-shallow-repository

# 2. Oldest reachable commit date (ISO YYYY-MM-DD)
git log --reverse --format=%cs | head -n 1
```

Resolve the gate:

- **`is-shallow-repository` prints `true`** → do not compute churn. Record an evidence-gap line
  (format: unattended.md), e.g. `gap: churn — shallow clone; history truncated, rankings would be wrong`.
  When repo-history evidence matters for this run, also propose an instrument-first
  candidate per ranking.md ("fetch full history / unshallow the clone so future runs can rank on
  churn").
- **Not shallow, but the oldest commit is dated after the requested `--since` window start**
  (ISO dates compare lexically, so the agent can compare the two strings directly) → the window
  is not covered. If the repository is simply younger than the window, shrink the window to the
  span history actually covers and cite the shrunk window explicitly in every hotspot citation
  (`12 commits/38d`, never presented as a 90-day count). If the covered span is too short to be
  meaningful (a handful of days or commits), record the evidence gap instead and let churn sit
  this run out.
- **Not shallow and the window is covered** → proceed.

## Step 1: windowed change frequency (churn)

Default window: 90 days, overridable through the config cascade Step 2 describes. The window is
the main tuning knob.

```bash
excludes='<the ERE Step 2 builds>'
git log --since="90 days ago" --pretty=format: --name-only |
  grep -v '^$' | grep -Ev "$excludes" | sort | uniq -c | sort -rn | head -50
```

Each output row is `<churn> <path>`: how many commits touched that path inside the window.

Steps 1, 3 and 4 share `excludes`, `indent_of` and `raw`, so run everything from Step 1's
`excludes` assignment through Step 4's `rm -f "$raw"` as one Bash call.

## Step 2: exclusions (resolved from the repository, cascade-overridable)

Raw churn is dominated by mechanical files that say nothing about improvement value: lockfiles,
generated or minified output, snapshots, vendored trees. The plugin ships no list of them. Build
Step 1's `excludes` as one ERE, alternatives joined with `|`, from two sources:

1. **Declared patterns:** `churn_exclude`, unioned across the config cascade (`userConfig`, the
   team `<home>/improvement.yaml`, the gitignored personal `<home>/improvement.local.yaml`, and
   any old file its dual-read window still reads), which also sets the churn window. These are
   already EREs: use them as written. Key contract: `../../../reference/config.md`.
2. **The repository's own mechanical files**, unless `churn_exclude_defaults` is `false`: resolve
   them through the plugin's copy of the ecosystem-resolution steps,
   [`reference/ecosystem-resolution.md`](../../../reference/ecosystem-resolution.md). Read the
   paths the target's `.gitattributes` marks as generated or vendored, then the lockfiles,
   generated or minified output, snapshots and vendored trees its build and manifest files imply.
   Turn each into an ERE: escape the characters of a literal file or directory name, convert a
   glob's `**/` to `(.*/)?` and its `*` to `[^/]*`, and anchor with `(^|/)` in front and `$` (a
   file) or `/` (a directory) behind. Name the file each pattern came from in the run's output.
   The scan asks nothing and writes no record; `/improvement:setup apply` offers to persist them
   as `churn_exclude` entries.

   This plugin still reads, or reports as retired, the `.claude/` paths named here; until the plugin migrates, keep config where this page says it is read, then move it where [config locations](../../../reference/config-locations.md) says.

All layers absent is a valid state. When item 2 resolves nothing while `churn_exclude_defaults` is
on, record an evidence-gap line (format: unattended.md), e.g.
`gap: churn exclusions — no mechanical files resolved from the repository — declare churn_exclude or run /improvement:setup apply`.
When the two sources yield no pattern at all, set `excludes='^$'`, which matches no path, and count
churn without exclusions.

## Step 3: indentation count as the complexity proxy (record LOC alongside)

For each surviving high-churn file, compute the indentation-based complexity proxy: tabs expanded
to four spaces, blank lines skipped, leading whitespace counted in 4-space logical units. Record
LOC alongside. LOC is the crude size cross-check, indentation is the canonical mechanical
metric:

```bash
# indent_of <file> -> "<indent-units> <loc>"
indent_of() {
  awk '{
    line = $0
    gsub(/\t/, "    ", line)
    if (line ~ /^ *$/) next
    match(line, /[^ ]/)
    total += int((RSTART - 1) / 4)
    loc++
  }
  END { printf "%d %d\n", total, loc }' "$1"
}
```

Combine with Step 1's output (drop paths deleted since, because churn counts history while the
tree holds the present):

```bash
raw="${TMPDIR:-/tmp}/hotspots.$$"
git log --since="90 days ago" --pretty=format: --name-only |
  grep -v '^$' | grep -Ev "$excludes" | sort | uniq -c | sort -rn | head -50 |
  while read -r churn f; do
    [ -f "<target-root>/$f" ] || continue
    printf '%s %s %s\n' "$churn" "$(indent_of "<target-root>/$f")" "$f"
  done > "$raw"
```

Each row is now `<churn> <indent-units> <loc> <path>`.

Comment lines are included in the count this proxy produces (full comment stripping is
language-specific); that is a known coarseness of the zero-dependency form. Note it when two
candidates are close, and prefer an installed analyzer's complexity numbers when the repo's own
toolchain provides one (presence-gated, cited as such).

## Step 4: churn×complexity quadrant ranking

Plot churn against indentation complexity; classify against the medians of the surviving set:

| Quadrant | Reading | Action |
|---|---|---|
| High churn × high complexity | The hotspot quadrant | Candidate material: rank by churn×indent product, descending |
| High churn × low complexity | Mechanical or process churn | Not a refactoring candidate; may seed an automation/process candidate instead |
| Low churn × high complexity | Complex but stable | Deliberately left alone, per the method's own doctrine |
| Low churn × low complexity | Quiet | Ignore |

Compute the quadrant in the shell rather than by hand; the medians, the filter, the product,
and the sort are all determined by the rows above:

```bash
n=$(wc -l < "$raw")
mid=$(( (n + 1) / 2 ))
med_churn=$(cut -d' ' -f1 "$raw" | sort -n | sed -n "${mid}p")
med_indent=$(cut -d' ' -f2 "$raw" | sort -n | sed -n "${mid}p")

# hotspot quadrant only, ranked by churn x indent, descending
awk -v mc="$med_churn" -v mi="$med_indent" \
  '$1 > mc && $2 > mi { printf "%d %s\n", $1 * $2, $0 }' "$raw" | sort -rn
rm -f "$raw"
```

Each surviving row is `<churn×indent> <churn> <indent-units> <loc> <path>`. Read the quadrant
table above to classify what the filter excluded; the caveats below decide which surviving rows
become candidates. The temp file lives outside the target repository, so a scan never leaves an
artifact in it.

Each hotspot becomes a candidate with citation
`hotspot: <churn> commits/<window> × indent <n> (<loc> LOC) — rung 2` and confidence per
ranking.md's rung mapping.

## Caveats (carry these into the candidate, not just the footnotes)

Hotspot ranking is probabilistic, not deterministic. Present hotspots as evidence-cited
*candidates*, never verdicts; the interview/pipeline stage validates:

- **Refactoring churn inflates scores without indicating debt.** A file recently cleaned up
  ranks high precisely because it was just improved. Check recent commit subjects before
  proposing.
- **Healthy churn** (tests, active feature work) must be distinguished from rework; the
  candidate statement should say which the evidence suggests.
- **File-level aggregation masks statement-level dynamics.** A huge file with one hot function
  ranks the same as a uniformly-churning one.
- **Rename handling changes counts.** `git log` follows the default rename detection; pass
  `--no-renames` when you need raw path-string counts, and say which you used in the citation
  when it materially changes a ranking.
