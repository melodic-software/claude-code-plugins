# The measures, and what the collectors actually compute

Definitions first, then the gap between the definition and the number a given tool prints. The
second half matters as much as the first: every row in a report carries the collector that produced
it, and two collectors for one measure can disagree on the same function.

## Cyclomatic complexity

T. J. McCabe, "A Complexity Measure", IEEE Transactions on Software Engineering SE-2(4),
December 1976. The measure is a property of a function's control-flow graph:

```text
v(G) = e - n + 2p
```

`e` is edges, `n` is nodes, `p` is connected components. For a single module `p` is 1 and the form
reduces to `v(G) = e - n + 2`. Two equivalent statements from NIST SP 500-235 are easier to apply by
hand: when every decision is binary and there are `p` binary decision predicates, `v(G) = p + 1`; and
for a planar flow graph, `v(G)` equals the number of regions including the infinite one.

What it counts is the number of linearly independent paths, which is why McCabe framed it as a
testability measure: it is the size of a basis set of paths a test suite would have to exercise. It
says nothing directly about how hard a function is to read. The paper's own caveat about large case
statements is in [thresholds.md](thresholds.md).

## Cognitive complexity

G. Ann Campbell, SonarSource, *Cognitive Complexity: a new way of measuring understandability*,
white paper version 1.7, 29 August 2023. The paper's abstract states the motive directly:

> Cyclomatic Complexity was initially formulated as a measurement of the "testability and
> maintainability" of the control flow of a module. While it excels at measuring the former, its
> underlying mathematical model is unsatisfactory at producing a value that measures the latter.

Cognitive complexity abandons the graph model. It increments on structures that break linear reading
and adds a nesting penalty, so a deeply nested loop costs more than a flat one, while a `switch`
with many cases costs once rather than once per case. Two functions with equal cyclomatic complexity
routinely carry different cognitive complexity, which is the point of the measure rather than a
defect in either.

The white paper prescribes no threshold. SonarSource's rule `S3776` ships a configurable default of
15, and that is a product decision by the same vendor, not a claim the paper makes.

## Halstead difficulty

Maurice H. Halstead, *Elements of Software Science*, Elsevier North-Holland, 1977. The primitives
are counted over a program's tokens:

| Symbol | Meaning |
|---|---|
| `n1` | distinct operators |
| `n2` | distinct operands |
| `N1` | total occurrences of operators |
| `N2` | total occurrences of operands |

Vocabulary is `n = n1 + n2` and length is `N = N1 + N2`. The three derived measures that get
conflated:

| Measure | Formula | Depends on |
|---|---|---|
| Volume | `V = N * log2(n)` | length and vocabulary, so it is a size measure |
| Difficulty | `D = (n1 / 2) * (N2 / n2)` | operator variety and operand reuse, with no length term |
| Effort | `E = D * V` | both, difficulty scaled by volume |

Difficulty reads as half the operator vocabulary times the average reuse of each operand. Doubling a
program's length without changing its operator set or its operand-reuse ratio leaves difficulty
unchanged while volume and effort both rise. A difficulty figure that scales with file size is
measuring something else. Effort is defined in terms of difficulty, so it is not an independent
alternative to it.

## Lines per file, and the ISO function-percentage form

The default mode counts lines per file: total, blank, comment, and code when `scc` resolves, and
total plus non-blank from the bundled counter otherwise. The comparison runs against non-blank
lines.

ISO/IEC 5055:2021 files a large-file weakness at 7.1.26 (CWE-1080, usage name "Excessively large
file"), and its informative clause 6.3 Table 1 carries a 1000-line figure. The normative detection
pattern attached to that weakness, §8.2.115, measures something different: a
`FunctionProcedureOrMethod` whose non-empty lines exceed a percentage of the file's, default 5%. So
the standard's normative form is a function-to-file ratio, and the line count is informative only.
The plugin implements both: `size.mode: file-lines` compares files against `size.file_lines`, and
`size.mode: iso-8.2.115` adds a per-function percentage against `size.function_lines_pct`. The
second needs a collector that reports function end lines, which no Bash collector does; that lane
says so and the run continues.

## Duplication

Clone detection here is token-based, not syntax-tree-based. `jscpd` tokenizes the source and
fingerprints it with Rabin-Karp; PMD CPD uses the same family of algorithm. Token-based detection
finds type-1 clones (exact copies) and type-2 clones (copies with renamed identifiers) and misses
type-3 structural clones that an AST comparison would find. For a percentage of duplicated lines
that is the right trade, and it is also the reason a report of zero duplication is not a report of
zero repetition.

`duplication.min_tokens` (default 50) and `duplication.min_lines` (default 5) are the floor passed
to the collector: a repeated region smaller than that is not reported as a clone. Raising
`min_tokens` yields fewer and larger clone groups, and the number moves with the setting, so a
duplication percentage is only comparable against another run with the same floor.

**Exclusion is not suppression.** A clone whose every instance sits at a path listed in a declared
sanctioned-replication registry is dropped from the debt total and listed under `excluded[]` with
the registry line that sanctioned it. That is a fact about the target repository, derived from a
file the repository maintains. Suppression, by contrast, is an operator judgement recorded against a
finding, and this plugin emits no findings, so it has no suppression surface.

## Coverage, per file and per function

The plugin runs no tests. It reads an artifact a test run already produced, and it never reads
coverage.py's `.coverage` SQLite file, whose schema the project documents as changing without a
major version bump.

| Format | Read from | Per-function detail |
|---|---|---|
| lcov tracefile | `DA:` line records, `FN:`/`FNDA:` or lcov 2.2 `FNL:`/`FNA:` | function hit flag |
| Cobertura XML | `line` elements with `number` and `hits` | `method` elements where present |
| coverage.py JSON | `coverage json` output | its own `functions` regions, 7.6.0 and later |
| Go cover profile | `file:start.col,end.col numstmt count` blocks | exact statement ranges |

Four traps a parser has to handle, and the report is only as good as the handling. lcov 2.2 replaced
the `FN:`/`FNDA:` pairing with index-based `FNL:`/`FNA:` records, so a parser written to the older
shape reports zero function coverage on modern output. An lcov `BRDA:` record's taken field can be a
literal `-`, meaning the branch was never evaluated, which is not the same as zero. A Cobertura
`condition-coverage` attribute is a display string such as `50% (1/2)` while `line-rate` on the same
document is a 0-to-1 decimal. And two different DTDs are both called `coverage-04.dtd` with many
producers adhering to neither, so the parse is permissive and a missing attribute is treated as
absent rather than zero.

Per-function coverage is taken from the artifact's own regions when it carries them, and otherwise
from a line-range join: executable lines with a non-zero hit count inside the function's start and
end lines, with nested function ranges subtracted from the parent first. A join that matches fewer
than all files in scope reports how many matched, so a path-normalization miss never reads as "no
executable lines".

## Type debt

Two lanes produce a number, and the two numbers are different measures over different populations.

- **TypeScript**, through `type-coverage`: the count of identifiers whose type is not `any` divided
  by the total identifier count. It inspects resolved types, so it catches implicit and explicit
  `any` alike. It also counts `unknown` as typed, so rewriting `any` to `unknown` raises the
  percentage without adding type information.
- **Python**, through `mypy --any-exprs-report`: counts of `Any` expressions, plus a type-checking
  coverage report in Cobertura XML. Counts, not a ratio over the same population as the TypeScript
  figure.

Comparing the two, or averaging them, is unsupported. C# reports `not-applicable`: no off-the-shelf
tool produces a comparable percentage, and a `dynamic` or bare `object` occurrence count is not
comparable to a ratio. No standard and no CWE anchors any of this; see [thresholds.md](thresholds.md).

## Where a collector differs from the textbook

- **`scc` is not a cyclomatic collector.** Its complexity figure is a per-file count of substring
  matches against a hardcoded per-language keyword list, computed without parsing. It is neither
  per-function nor a graph measure, so the plugin uses `scc` for line counting only and never
  surfaces its complexity number.
- **Halstead from `multimetric` is per file.** It emits volume, difficulty, effort, time, and bugs
  for a file rather than a function, so those rows carry `function: null` and are labelled
  file-level. Python is the exception: `radon hal -j` reports the suite per function.
- **`gocyclo` output is a text scrape.** It has no JSON mode; its only format is
  `<complexity> <package> <function> <file:line:column>` plus a template flag. The adapter parses
  that text and the row is labelled with the tool's name.
- **`shellmetrics` values vary by the shell that runs it**, which its own documentation states. Two
  machines can print different Bash complexity for the same script.
- **ESLint-based collectors report violations, not distributions.** The core `complexity` rule and
  `sonarjs/cognitive-complexity` fire above a threshold and stay silent below it, so they are run at
  a threshold of zero to make every function report. They resolve only when the repository already
  wires ESLint.
- **Start-line-only collectors cost the CRAP join.** `shellmetrics`, `gocyclo`, `gocognit`, and the
  ESLint rules report where a function starts and not where it ends. Without an end line there is no
  range to join coverage against, so that lane's CRAP row is `not-applicable` with the reason stated
  rather than a silent null. `lizard` and `radon` report both lines, and coverage.py and Go cover
  profiles carry their own regions.

Which tool is tried in which order per lane is data, not prose:
`${CLAUDE_PLUGIN_ROOT}/scripts/collector-ladder.tsv`, with the per-tool stamps in
`${CLAUDE_PLUGIN_ROOT}/reference/collectors.md`.
