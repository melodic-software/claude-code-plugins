# hotspots — plain-git churn×complexity recipe (Tier 0, evidence rung 2)

Mechanical, reproducible hotspot scoring with nothing but git and POSIX tools. Output: a ranked
set of churn×complexity hotspot files, each carrying an evidence citation in the shape the
candidate table expects, e.g. `hotspot: 14 commits/90d × indent 412 (1,038 LOC) — rung 2`.

The method (Tornhill's hotspot analysis, productized as CodeScene) combines two orthogonal
per-file signals: **change frequency** (how often the file appears in commits over a window —
mined from `git log`) and **complexity**. CodeScene's canonical mechanical complexity metric is
**indentation-based complexity** — logical indentations counted with blank lines stripped —
chosen because it is fast, automated, and language-neutral. This recipe uses that proxy and
records LOC alongside it.

## Step 0 — history-depth gate (always first)

Churn from partial history produces confidently-wrong rankings, which are worse than no
rankings. Run this gate before counting anything:

```bash
# 1. Shallow clone? (cloud sessions often clone shallow)
git rev-parse --is-shallow-repository

# 2. Oldest reachable commit date (ISO YYYY-MM-DD)
git log --reverse --format=%cs | head -n 1
```

Resolve the gate:

- **`is-shallow-repository` prints `true`** → do NOT compute churn. Record an evidence-gap line
  (format: unattended.md) — e.g. `gap: churn — shallow clone; history truncated, rankings would
  be wrong` — and, when repo-history evidence matters for this run, propose an instrument-first
  candidate per ranking.md ("fetch full history / unshallow the clone so future runs can rank on
  churn").
- **Not shallow, but the oldest commit date falls after the requested `--since` window start**
  (ISO dates compare lexically, so the agent can compare the two strings directly) → the window
  is not covered. If the repository is simply younger than the window, shrink the window to the
  span history actually covers and cite the shrunk window explicitly in every hotspot citation
  (`12 commits/38d`, never presented as a 90-day count). If the covered span is too short to be
  meaningful (a handful of days or commits), record the evidence gap instead and let churn sit
  this run out.
- **Not shallow and the window is covered** → proceed.

## Step 1 — windowed change frequency (churn)

Default window: 90 days (overridable — see Step 2's config cascade note; the window is the main
tuning knob).

```bash
excludes='(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|poetry\.lock|uv\.lock|Gemfile\.lock|composer\.lock|go\.sum|packages\.lock\.json|flake\.lock)$|(^|/)(vendor|third_party|node_modules|dist|build|out)/|\.min\.(js|css)$|\.snap$'
git log --since="90 days ago" --pretty=format: --name-only |
  grep -v '^$' | grep -Ev "$excludes" | sort | uniq -c | sort -rn | head -50
```

Each output row is `<churn> <path>`: how many commits touched that path inside the window.

## Step 2 — exclusions (bundled defaults, cascade-overridable)

Raw churn is dominated by mechanical files — lockfiles, generated output, vendored trees — that
say nothing about improvement value. The `excludes` ERE above is the bundled default: lockfiles,
generated/minified artifacts, and vendored/dependency directories.

The consuming repo overrides or extends these globs through the `.claude/improvement.md` config
cascade (team file, `.claude/improvement.local.md` gitignored overlay, `~/.claude/improvement.md`
user-global), along with the churn window. Key contract: `../../../reference/config.md`. All
layers absent is a valid state — use the bundled defaults above.

## Step 3 — complexity proxy: indentation count (record LOC alongside)

For each surviving high-churn file, compute the indentation-based complexity proxy: tabs expanded
to four spaces, blank lines skipped, leading whitespace counted in 4-space logical units. Record
LOC alongside — LOC is the crude size cross-check, indentation is the canonical mechanical
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

Combine with Step 1's output (drop paths deleted since — churn counts history, the tree holds
the present):

```bash
git log --since="90 days ago" --pretty=format: --name-only |
  grep -v '^$' | grep -Ev "$excludes" | sort | uniq -c | sort -rn | head -50 |
  while read -r churn f; do
    [ -f "$f" ] || continue
    printf '%s %s %s\n' "$churn" "$(indent_of "$f")" "$f"
  done
```

Each row is now `<churn> <indent-units> <loc> <path>`.

Comment lines are included in the count this proxy produces (full comment stripping is
language-specific); that is a known coarseness of the zero-dependency form — note it when two
candidates are close, and prefer an installed analyzer's complexity numbers when the repo's own
toolchain provides one (presence-gated, cited as such).

## Step 4 — churn×complexity quadrant ranking

Plot churn against indentation complexity; classify against the medians of the surviving set:

| Quadrant | Reading | Action |
|---|---|---|
| High churn × high complexity | The hotspot quadrant | Candidate material — rank by churn×indent product, descending |
| High churn × low complexity | Mechanical or process churn | Not a refactoring candidate; may seed an automation/process candidate instead |
| Low churn × high complexity | Complex but stable | Deliberately left alone — the method's own doctrine |
| Low churn × low complexity | Quiet | Ignore |

Mechanically: compute the median churn and median indent over the surviving files; the hotspot
quadrant is above both medians; rank inside it by the product `churn × indent`.

Each hotspot becomes a candidate with citation
`hotspot: <churn> commits/<window> × indent <n> (<loc> LOC) — rung 2` and confidence per
ranking.md's rung mapping.

## Caveats (carry these into the candidate, not just the footnotes)

Hotspot ranking is probabilistic, not deterministic — present hotspots as evidence-cited
*candidates*, never verdicts; the interview/pipeline stage validates:

- **Refactoring churn inflates scores without indicating debt** — a file recently cleaned up
  ranks high precisely because it was just improved. Check recent commit subjects before
  proposing.
- **Healthy churn** (tests, active feature work) must be distinguished from rework; the
  candidate statement should say which the evidence suggests.
- **File-level aggregation masks statement-level dynamics** — a huge file with one hot function
  ranks the same as a uniformly-churning one.
- **Rename handling changes counts** — `git log` follows the default rename detection; pass
  `--no-renames` when you need raw path-string counts, and say which you used in the citation
  when it materially changes a ranking.
