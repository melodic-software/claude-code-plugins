# CRAP: the formula, the history, and what it does not predict

## The formula

Alberto Savoia, with his Agitar Labs colleague Bob Evans, July 2007. The formula is identical
character for character in every authorial artifact, the original announcement and the Crap4j
project FAQ alike:

```text
CRAP(m) = comp(m)^2 * (1 - cov(m)/100)^3 + comp(m)
```

`comp(m)` is the cyclomatic complexity of method `m`. `cov(m)` is its automated-test coverage,
expressed on a 0-to-100 scale, which is what the `/100` is for. A reimplementation that feeds it a
0-to-1 fraction computes something else entirely.

Two details the authors state and most restatements drop. The coverage the FAQ specifies is **basis
path coverage**, not line coverage; substituting line coverage, as this plugin and most other
implementations do, changes the number. And the authors reserved the right to change the metric:
"we believe that the current version of CRAP is a very good start [...] we also believe that metrics
should be open to change and evolve."

## Worked values

The cubed coverage term is what gives CRAP its shape: coverage buys down the squared complexity
term fast at first and the linear `+ comp` tail never goes away.

| comp | cov | CRAP | Reading |
|---|---|---|---|
| 5 | 0 | 30 | `25 * 1 + 5` |
| 5 | 50 | 8.125 | half the coverage removes seven eighths of the squared term |
| 5 | 100 | 5 | full coverage leaves the complexity itself |
| 30 | 0 | 930 | `900 * 1 + 30` |
| 30 | 100 | 30 | the same function, fully covered |
| 40 | 100 | 40 | complexity is the floor, always |

The last row is the caveat worth carrying: **a function with 100% coverage and complexity 40 still
has CRAP 40.** The score never falls below the complexity, so a high CRAP on a fully covered
function is a statement about complexity alone, and reading it as a coverage gap is wrong.

## The name, corrected

The acronym has more than one authorial expansion, and asserting a single canonical one overstates
the record.

- The earliest authorial expansion, from the July 2007 announcement, is
  **Change Risk Analysis and Predictions**. The Crap4j homepage carries that wording still.
- A later 2007 post uses the singular "Change Risk Analysis and Prediction", and one teaser adds a
  fourth string, "Change Risk Analyzer and Predictor".
- The authors then replaced the expansion outright with **Change Risk Anti-Patterns**, and the
  Crap4j FAQ says so in a self-titled question: "Hey, didn't CRAP used to stand for Change Risk
  Analysis and Prediction? Did you change the acronym?" The answer: "Yes it did, and yes we did.
  [...] we determined that thinking of CRAP as an anti-pattern detector rather than a metric would
  be both more accurate and more useful."

So the current authorial name is Change Risk Anti-Patterns, the rename is the authors' own rather
than a propagated error, and the tools that use either wording are quoting an author. Cite both, in
that order, and note the authors' own site carries both.

## Not a validated change-risk predictor

**CRAP is not a validated change-risk predictor.** The name promises change risk; the formula is an
arithmetic combination of two static measures, published on a blog and in a tool FAQ, with no study
behind it. What the record supports:

- The formula, the variable definitions, and the authors' own suggested cutoff of 30 are documented
  by the authors. The cutoff is presented as a judgement call after "much debate", not as a result.
- No validation study for CRAP surfaced in this plugin's literature pass. The absence is what the
  claim rests on, so read it as "no supporting evidence found", not as a refutation.
- The surrounding literature argues against fixed thresholds generally. Nagappan, Ball and Zeller
  (ICSE 2006) found no single set of complexity metrics that acts as a universally best defect
  predictor, and Majumder, Mody and Menzies (EMSE 2022, 700 projects) warn that metric-importance
  results from small studies change dramatically at scale. A composite of two such metrics inherits
  that problem rather than escaping it.

### Why an unactionable score gets ignored

Lewis, Lin, Sadowski, Zhu, Ou and Whitehead, "Does Bug Prediction Support Human Developers? Findings
from a Google Case Study", ICSE 2013, deployed a bug-prediction algorithm across Google and reported
"no identifiable change in developer behavior". The mechanism, from the paper itself: "unless there
was an actionable means of removing the flag [...] developers did not find value in the bug
prediction, and ignored it." Developers rated the flagged files as plausibly bug-prone and still did
nothing differently.

That is the reason a CRAP number is reported here beside the function that produced it, with its two
inputs visible, rather than as a ranked list of scores. A score with no explanation and no route to
removing it is inert, and this is a Tier-1 finding from the organization that ran the experiment.

## How this plugin computes it

CRAP is a derived output of `/code-metrics:audit-coverage`, which takes `comp` from the sibling
complexity run and `cov` from a coverage artifact that already exists. The join has stated semantics
because every one of them can change a number:

1. **The artifact's own per-function region wins** when it carries one, either the function's own
   line map or its start and end lines: coverage.py JSON `functions` regions (7.6.0 and later),
   lcov 2.2 `FNL`/`FNA` leaders that carry an end line, and Cobertura `method` regions. The row
   records `cov_source: artifact-region`. A Go cover profile is not one of these: its blocks are
   statement counts over line ranges, it names no function, and it says which lines carry the
   statements in no block at all, so a Go function has neither a region nor executable lines to
   join and its `cov_source` is `line-range` with `cov` and CRAP both `null`.
2. **Otherwise a line-range join**: executable lines with a non-zero hit count between the
   function's start and end lines, with nested function ranges subtracted from the parent first. The
   row records `cov_source: line-range`. The range comes from a collector that reports function end
   lines, which means `lizard` or `radon`.
3. **A short name that fits more than one function is refused, not guessed.** Where the artifact
   records a function as `run` rather than as `Alpha.run`, the record binds to the function whose
   declared range holds the lines the artifact placed it at. Where no range separates the
   candidates, because the artifact placed none of them at a line or because two of them fall
   inside the same range, the row records `cov_source: ambiguous` with `cov` and CRAP both `null`,
   a `coverage-ambiguous` label, and a `reason` saying which way it was unresolvable.
4. **A lane whose resolved collector reports only start lines** gets a `run[]` row
   `<lane>/crap: not-applicable` with the reason "the resolved collector reports no function end
   lines", rather than a null that would quietly cover the whole lane. In this version Bash is that
   lane, and it is a documented gap.
5. **A function-hit flag of zero forces `cov: 0`.** lcov `FNDA`/`FNA` records and Cobertura
   `method` hits say whether the function was entered at all. Without that check, a declaration line
   executed at import time reports a small non-zero coverage for a function nothing ever called.
6. **`cov: null` gives `crap: null`, never 0.** A function with no executable lines in the artifact
   was not measured. Substituting zero would fabricate the maximal CRAP for that complexity, which
   is the single most misleading number this plugin could print.

A join that matches fewer than all of the files in scope reports "partial, N of M scope files", so a
path-normalization failure never reads as an honest zero.

## Reading a CRAP number

- It combines two measures whose own caveats still apply, in
  [measures.md](measures.md) and [thresholds.md](thresholds.md). Nothing about the combination
  validates either input.
- It moves under refactoring in ways that are not improvements. Splitting one function of complexity
  30 into six of complexity 5 drops the top CRAP from 930 to 30 at zero coverage while the code does
  the same thing.
- The shipped reference is `null`. The authors' 30 is available as a value you can set, and it is
  their suggestion rather than a standard.
