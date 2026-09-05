# code-metrics design threads

Light-form module design for the `code-metrics` plugin, derived from the locked Brief in
[`../PLAN.md`](../PLAN.md) and the interview's research corpora (memory slice, not committed).
Every thread is RESOLVED with its rationale recorded, or TAGGED-DEFERRED with the research tag that
would resolve it. Companion artifacts: [`contracts.md`](contracts.md) (config keys, output shape,
collector adapter contract), [`module-boundary.md`](module-boundary.md) (what lives where, seams
in and out), [`domain-model.md`](domain-model.md) (measures, lanes, collectors, thresholds).

| # | Thread | Status |
|---|---|---|
| T1 | Collector strategy and presence gating | RESOLVED |
| T2 | Lane detection | RESOLVED |
| T3 | Measurement scope | RESOLVED |
| T4 | Config surface, keys, merge form | RESOLVED |
| T5 | Output contract | RESOLVED |
| T6 | Threshold semantics under ADR 0003 | RESOLVED |
| T7 | CRAP and the function-level coverage join | RESOLVED |
| T8 | Sanctioned replication as an exclusion | RESOLVED |
| T9 | Type debt for C# | RESOLVED |
| T10 | The size measure and its default | RESOLVED |
| T11 | Cognitive complexity gaps | RESOLVED |
| T12 | Halstead difficulty | RESOLVED |
| T13 | Test-seam posture | RESOLVED |
| T14 | Prerequisite install policy | RESOLVED |
| T15 | Upstream drift on tool facts | RESOLVED |
| T16 | Native overlap | RESOLVED |
| T17 | Suppression surface | RESOLVED |
| T18 | Design defaults: configurability, extension, observability, testability | RESOLVED |
| T19 | The C# complexity lane | TAGGED-DEFERRED |
| T20 | Cross-platform posture | RESOLVED |
| T21 | Shared code inside the plugin | RESOLVED |
| T22 | Reading YAML without a YAML library | RESOLVED |

## T1. Collector strategy and presence gating. RESOLVED

**Decision.** Each measure has an ordered collector list per lane. The first collector that resolves
on `PATH` (or in the repository's own `node_modules/.bin` for npm tools) is used; when none resolves
the lane reports `unavailable` with the collector names and their install hints, and the run
continues with the other lanes. The plugin never installs, downloads, or `npx`-fetches a collector.

| Measure | TS/JS | Python | Bash | Go |
|---|---|---|---|---|
| Cyclomatic | `lizard`, then ESLint core `complexity` at max 0 when ESLint is wired | `lizard`, then `radon cc -j` | `shellmetrics`, then `multimetric` | `lizard`, then `gocyclo` (text scrape, labelled) |
| Cognitive | `eslint-plugin-sonarjs` `cognitive-complexity` at max 0 when wired | none maintained (reported as such) | none found (reported as such) | `gocognit -json` |
| Halstead difficulty | `multimetric` | `radon hal -j`, then `multimetric` | `multimetric` | `multimetric` |
| Size (lines) | `scc --format json`, then the bundled counter | same | same | same |
| Duplication | `jscpd --reporters json` | same | same (jscpd covers shell) | `jscpd`, then `dupl` |
| Coverage | parse existing artifacts only (lcov, Cobertura, coverage.py JSON) | same, coverage.py JSON preferred for its per-function regions (7.6.0 and later) | same (kcov emits Cobertura and JSON, not lcov) | Go's own cover profile (`file:start.col,end.col numstmt count`) through a bundled parser; Go emits neither lcov nor Cobertura |
| Type debt | `type-coverage` | `mypy --any-exprs-report` | not applicable | not applicable |

**Rationale.** `lizard` 1.24.0 (2026-08-19) is current, per-function, and covers TS, JS, Python and Go
from one dependency, which keeps the gate list short; it does not cover shell, so Bash keeps its own
pair. Native tools stay ahead of `lizard` only where the repository already wires them (ESLint,
radon), because a repository's own wired tool is the number its team already reads. `scc` is
demoted to line counting, its complexity figure never surfaces (Brief: substring matching, file
level). The install ban is the philosophy's prerequisite rule: never execute an undeclared tool as
an incidental fallback. Every collector above is declared in the README and probed by `setup check`.

**The ladder is data, not code.** The whole table ships in Phase 1 as
`scripts/collector-ladder.tsv` (`lane`, `measure`, `tool`, in ladder order, one row per rung,
every tool above listed before any adapter exists); the dispatcher reads it and reports a listed
tool whose adapter file is absent as `unavailable` with reason `adapter not shipped`. Adding a
collector is then one adapter file plus one ladder row, and no phase after the first edits the
dispatcher. The config override `lanes.<lane>.collectors.<measure>` validates its names against
the ladder file, never against a directory listing.

**A collector succeeds when it produced parseable output**, not when it exited 0: ESLint exits 1
whenever it reports (and at `max: 0` it always reports), mypy exits 1 on any type error while still
writing its report. Each adapter suite carries a case for its tool's reporting exit code. A tool
that produced no parseable output is the `collect` failure that maps to exit 3.

## T2. Lane detection. RESOLVED

**Decision.** Lanes are detected from file extensions of the in-scope files against a bundled
extension map (`.ts .tsx .mts .cts .js .jsx .mjs .cjs` → `typescript`; `.py .pyi` → `python`;
`.sh .bash` → `bash`; `.go` → `go`; `.cs` → `dotnet`, reported as deferred). When the consuming
repository tracks `.claude/ecosystems/<ecosystem>.yaml` files (the marketplace-wide
`ecosystem-commands` convention), their `globs` override the bundled map for that ecosystem and a
resolved `enabled: false` opts the lane out; the file resolves through the same three cascade
layers the convention prescribes (user-global, team, overlay), via the plugin's own config
resolver, so this is not a single-layer deviation. The globs are gitignore-style, so matching goes
through a bundled `scripts/pathglob.py` that translates `**` and `*` correctly at the Python 3.9
floor (`fnmatch` cannot). No framework detection: no measure here depends on a framework.

**Rationale.** Extension mapping is deterministic, needs no tool, and matches how `toolchain:check`
classifies files. Reading the consumer's tracked ecosystem files is a convention seam, not a plugin
import, so it needs no presence gate on another plugin; the bundled map is the fallback.

## T3. Measurement scope. RESOLVED

**Decision.** Default scope is the change: files changed against the merge base with the default
branch (`git diff --name-only <merge-base>`), plus uncommitted changes. An explicit path list or
`--all` widens it. Every report names its scope in its header. Deleted and binary files are dropped.

**Rationale.** The Brief scopes measurement to a change and rules out a repo-wide dashboard. Change
scope also keeps runtime proportional to the work in hand; `--all` exists because a baseline for
`verification:measure` sometimes needs the whole tree.

## T4. Config surface, keys, merge form. RESOLVED

**Decision.** One surface, `.claude/code-metrics.yaml`, layered per the config cascade (user-global
`~/.claude/code-metrics.yaml`, team `.claude/code-metrics.yaml`, overlay
`.claude/code-metrics.local.yaml`), **per-key override** declared, because every value is a scalar
or closed list. Keys are in [`contracts.md`](contracts.md). No manifest `userConfig`: there is no
personal scalar that is not also a team choice. `setup` ships on criteria (a) and (b) of the setup
contract (a consumer config surface and external CLI prerequisites).

**Rationale.** Per-key override is the cascade's sanctioned form for scalars; concatenation would
merge two threshold lists into nonsense. A single file rather than a folder because the keys are one
concern; the folder form is for per-ecosystem lifecycles, and lane overrides nest under one key.

## T5. Output contract. RESOLVED

**Decision.** Every collector script writes one JSON document (`schema: code-metrics/v1`) to stdout
and diagnostics to stderr; the skill renders the markdown report from that JSON. The JSON carries
`scope`, `lanes` (with `collector` and `status` per lane), `measures` (per file or per function),
`thresholds` (the resolved values with `provenance` strings), `unavailable` (what could not be
measured and why), and a top-level `status`: `complete` (every implied lane and measure ran),
`partial` (at least one did not), or `empty` (nothing was measured). Exit code 0 whenever the
document was produced, including `empty` runs; exit 2 for a usage error, which includes any path
the operator named explicitly (`--artifacts`, `--registry`, a scope path) that does not exist;
exit 3 when a resolved collector ran and produced no parseable output. Auto-discovery that finds
no artifact is not a usage error: it is `unavailable` with the paths searched as the reason. The
markdown headline for an `empty` run reads "Measured nothing", and the pointer to
`verification:measure` says that `empty` on either side of a comparison is INCONCLUSIVE.

**Rationale.** A stable JSON shape is what lets `verification:measure` (by pointer, presence-gated)
and a future `check` gate consume the numbers without re-parsing prose. Exit 0 on `unavailable`
follows the prerequisite taxonomy: an optional-feature absence warns visibly and continues, and the
warning is in the JSON as well as on stderr, so a silent skip is impossible by construction. The
liveness-assertion convention adds the other half: a pass must mean the capability ran, so a
consumer that reads only the exit code is told in the JSON and the headline that nothing ran, and
a typo in an operator-named path is refused rather than reported as a reduced result.

## T6. Threshold semantics under ADR 0003. RESOLVED

**Decision.** Thresholds are reference values printed beside each measure with their provenance; the
report counts values at or above the reference (`over_reference`) but attaches no severity, no
pass/fail, no exit code, and writes no findings file. A `check` gate, which would need ADR 0003's
measured corpus sweep, is out of V1 and each description says so.

**Rationale.** ADR 0003 gates default-on findings on measured precision. Reporting a number next to
a cited reference is a measurement; deciding it is a defect is a finding. Keeping V1 on the
measurement side means no sweep is owed and no false-positive budget is spent.

## T7. CRAP and the function-level coverage join. RESOLVED

**Decision.** `audit-coverage` computes CRAP per function as
`comp^2 * (1 - cov/100)^3 + comp` (Savoia and Evans, 2007), where `comp` is the function's
cyclomatic complexity from `audit-complexity`'s JSON and `cov` is the function's line coverage
percentage, taken in this order of preference and recorded per row as `cov_source`:

1. The artifact's own per-function region when it carries one (coverage.py JSON `functions`,
   7.6.0 and later; Go cover profile blocks, which are exact statement ranges).
2. The line-range join: executable lines with a non-zero hit within the function's start and end
   lines, with the ranges of nested functions subtracted from the parent first. The range comes
   from a collector that reports function end lines (`lizard`, `radon`); a lane whose resolved
   collector reports only a start line (`shellmetrics`, `gocyclo`, `gocognit`, ESLint) reports
   `crap: null` with a `run[]` row `<lane>/crap: not-applicable, reason: the resolved collector
   reports no function end lines`. In V1 Bash has no such collector, so Bash CRAP is a documented
   gap, not a silent null.

`FNDA`/`FNA` records (and Cobertura `<method>` hits) supply a function-hit flag beside the
percentage; when the flag says the function was never entered, `cov` is reported as `0` rather
than the 1/N that a declaration line executed at import would produce. A function with no
executable lines in the artifact reports `cov: null` and `crap: null`, never 0.

Artifact paths are normalized on both sides before the join (Cobertura `<source>` prefixes and
the repository root stripped, forward slashes, symlinks resolved once, an optional
`coverage.path_prefix_strip` for compiled-output layouts), and a join that matches fewer than all
scope files adds a `run[]` reason `coverage: partial, N of M scope files present in the
artifacts`, so a total miss never reads as "no executable lines".

**Rationale.** The artifact's own regions are exact where they exist; the line-range join is the
method that works across lcov, Cobertura, and coverage.py JSON alike and sidesteps the lcov 2.x
change where `FN`/`FNDA` pairing became `FNL`/`FNA` (a parser written to the old pairing misreads
2.x output). Null over zero because a fabricated 0% would produce a fabricated maximal CRAP; a
visible `not-applicable` row over a null because the stress test showed the null would otherwise
cover a whole lane by construction.

## T8. Sanctioned replication as an exclusion. RESOLVED

**Decision.** `duplication.registries` lists files whose lines name a path-within-plugin (the shape
of this repository's `scripts/cross-plugin-source-registry.txt`: one relative path per line,
comments with `#`). A clone whose every instance sits at a listed relative path inside a distinct
top-level plugin directory is dropped from the debt total and listed under `excluded`, with the
registry line that sanctioned it. Anything else the consumer wants ignored goes through jscpd's own
`--ignore` patterns via `duplication.ignore`.

**Rationale.** Deliberate replication declared by the target repository is an exclusion (derived
from the target's own state), not a suppression (an operator judgement on a finding), so the
finding-suppression record is the wrong instrument. The Brief's fixture, this repository's
`hook-utils.sh` cluster reporting zero debt, is the acceptance test for the mechanism.

## T9. Type debt for C#. RESOLVED

**Decision.** V1 omits the C# type-debt number. The lane row reports `not-applicable` with the
sentence "no tool produces a comparable percentage for C#; a `dynamic`/`object` occurrence count is
not comparable to a ratio", and the `principles` skill records why.

**Rationale.** The Brief allows a labelled count or omission. A count presented beside two true
percentages invites the comparison it cannot support, and the C# lane as a whole is deferred (T19),
so omission keeps V1 internally consistent. Switch condition: a Roslyn analyzer that emits an
identifier-level ratio becomes available.

## T10. The size measure and its default. RESOLVED

**Decision.** `audit-size` reports, per file, `lines_total`, `lines_blank`, `lines_comment`,
`lines_code` when `scc` resolves, and `lines_total` plus `lines_non_blank` (labelled
`comment-agnostic`) from the bundled counter otherwise. The default reference is the plugin's own
number, `size.file_lines: 1000`, labelled "plugin default; coincides with the informative figure in
ISO/IEC 5055:2021 §6.3 Table 1, which is not normative". `500` is documented as the selectable
figure from the operator's source list, and `size.function_lines_pct: 5` implements the normative
§8.2.115 alternative (a function whose non-empty lines exceed 5% of the file's) when
`size.mode: iso-8.2.115` is set.

**Rationale.** Q20 ruled that the file-line figure ships as the plugin's own labelled number, never
as ISO-backed. 1000 is the figure the interview settled before the refutation and remains the
better-known reference; the honest label is what the refutation demanded. `scc` is the right tool
here because comment-aware counting is exactly what it does well.

## T11. Cognitive complexity gaps. RESOLVED

**Decision.** Cognitive complexity is reported for TS/JS (`eslint-plugin-sonarjs`, only when the
repository wires ESLint) and Go (`gocognit`). Python and Bash rows state "no maintained collector
found (validated 2026-09-04)" and the run continues. The measure definition cited is Campbell,
SonarSource, with the note that no standard sets a threshold.

**Rationale.** The tooling corpus found nothing maintained for those two lanes. Stating the gap is
the prerequisite rule's "report the missing optional capability clearly"; inventing a
cognitive-complexity approximation would be a new measure with no provenance.

## T12. Halstead difficulty. RESOLVED

**Decision.** Python reports the full Halstead suite from `radon hal -j`, per function; every
other lane reports the five derived measures `multimetric` emits (volume, difficulty, effort,
time, bugs), which are **per file** (probed 2026-09-05: `multimetric` has no per-function
granularity), so those rows carry `function: null` and the report labels them file-level. Difficulty is the headline number because it is the one on the operator's list; no threshold
is shipped, only a `halstead.difficulty` reference key defaulting to `null`.

**Rationale.** The corpus found no maintained native Halstead tool for TS/JS, C# or Go; `multimetric`
is the only cross-lane route and lacks the primitives. Shipping no default reference is the honest
reading of "no standard sets a threshold" (Halstead 1977 sets none).

## T13. Test-seam posture. RESOLVED

**Decision.** One seam: each script's command line. Shell suites (`*.test.sh`) run the script
against committed fixtures under the plugin's `scripts/fixtures/` directory and assert on the JSON
it prints (shape, values, `unavailable` rows); Python suites (`test_*.py`) drive the pure functions
(parsers, the CRAP formula, config merge, the YAML subset) through `subprocess` at the same
command-line seam, loading a module directly only through
`importlib.util.spec_from_file_location` where a function has no CLI (the repository's idiom for
hyphenated script names). Collector presence is stubbed by **stubs the suite generates at
runtime** in a temporary directory prepended to `PATH`, each replaying a committed capture from
`scripts/fixtures/tool-output/`; no fake executable is committed, matching every existing suite in
the repository. A suite whose case needs the real tool and cannot find it prints a visible `SKIP`
line naming the tool and exits 0, never a silent pass. No seam on SKILL.md prose beyond
`skill-quality:check` and the skill's `evals/` file.

**Rationale.** The scripts are the only executable surface; the prose is instruction. Testing at the
CLI seam keeps one seam per skill and exercises the JSON contract that downstream consumers read.
Runtime stubs avoid committed executables, which have no precedent here, need preserved exec bits,
and fall outside every `affected-tests.sh` mapping rule.

## T14. Prerequisite install policy. RESOLVED

**Decision.** `setup check` probes every collector and prints each missing one with its install
hint; `setup apply` writes or updates `.claude/code-metrics.yaml` from answers and recommends the
recursive `.claude/**/*.local.*` ignore line. Neither action installs anything or edits the
consumer's `.gitignore`.

**Rationale.** The philosophy's setup contract: `check` verifies, `apply` configures idempotently, no
plugin writes the consumer's ignore file, and installs are the operator's act.

## T15. Upstream drift on tool facts. RESOLVED

**Decision.** Each collector adapter carries a stamp block (claim, basis URL, as-of date, recheck
trigger) in `reference/collectors.md`, one row per tool, with the versions verified 2026-09-04. The
lcov 2.2 `FNL`/`FNA` fact and the coverage.py SQLite-is-internal fact carry their own rows.

**Rationale.** The `upstream-drift` convention owns the four-part record; tool versions and output
formats are the facts most likely to rot.

## T16. Native overlap. RESOLVED

**Decision.** No native Claude Code surface measures code, so no description carries a native
presence phrase and no overlap-store row is owed. The `principles` skill mentions no native command.

**Rationale.** The native-references convention applies when a native surface materially overlaps;
none does. Recheck trigger: a Claude Code release note adds a metrics or complexity command.

## T17. Suppression surface. RESOLVED

**Decision.** None in V1. The plugin emits measures, not findings, so there is nothing to suppress;
the only "ignore" mechanisms are scope (T3) and duplication exclusion (T8).

**Rationale.** The finding-suppression convention is for kept findings. Adding a record with no
findings to key it to would be ceremony.

## T18. Design defaults. RESOLVED

- **Configurability.** Everything an operator might tune is a key in `.claude/code-metrics.yaml`
  (T4); nothing is an environment variable.
- **Extension.** A new lane or collector is one adapter file under the plugin's shared scripts
  directory plus one row in `scripts/collector-ladder.tsv` and one stamped row in the reference
  table; the dispatcher reads the ladder file and never a directory listing (T1).
- **Observability.** Every report opens with a "Coverage of this run" table: lane, collector used,
  status (`ok`, `unavailable`, `not-applicable`, `deferred`), and reason. The same table is in the
  JSON. Nothing is skipped silently.
- **Testability.** T13.

## T19. The C# complexity lane. TAGGED-DEFERRED

**Status.** Deferred by Q21. Research tag: `probe:dotnet-metrics-linux`, a runtime probe of
`Microsoft.CodeAnalysis.Metrics` 5.6.0 on Linux (`dotnet build /t:Metrics` equivalence to
`msbuild /t:Metrics`, or the `CodeAnalysisMetricData` API route). Until then `.cs` files are
detected and reported as `deferred` with that sentence, so the lane's absence is visible.

## T20. Cross-platform posture. RESOLVED

**Decision.** Entry points are bash scripts; parsers and the JSON assembly are Python 3 standard
library only (`json`, `csv`, `xml.etree`, `re`, `pathlib`). Python 3 is a declared required
prerequisite, resolved by the repository's candidate loop (`python3`, then `python`, then `py -3`,
first that runs and reports 3.9 or later) and probed at the entry point with a remediation
message. Paths are handled as the repository's cross-platform contract prescribes (Git Bash on
Windows, forward slashes in output).

**Rationale.** The repository's own scripts are bash plus Python, the ruff wrapper is pinned for
Python, and stdlib-only avoids a second dependency surface. Bash-only parsing of XML and lcov would
be fragile.

## T21. Shared code inside the plugin. RESOLVED

**Decision.** Code used by more than one skill (lane detection, config resolution, JSON assembly,
collector probing) lives once under `plugins/code-metrics/scripts/` and is invoked by relative path
from each skill's own script. Nothing is copied between skills, and nothing is imported from another
plugin.

**Rationale.** The plugin is the encapsulation boundary (ADR 0018); intra-plugin sharing is
ordinary code reuse, and the vendoring-with-sync-gate pattern (ADR 0019) is for cross-plugin copies
only. The path `plugins/code-metrics/lib/` is avoided so the branch stays clear of the `lib/`
surfaces the hook lanes own.

## T22. Reading YAML without a YAML library. RESOLVED

**Decision.** The Python standard library has no YAML parser and T20 rules out a third-party one,
so the plugin bundles `scripts/yaml_subset.py`, a parser for the documented subset every surface it
reads is written in: block mappings, block sequences, flow sequences of scalars (`["*.sh", "*.bash"]`,
the form the ecosystem-commands examples use), plain and quoted scalars (`str`, `int`, `float`,
`true`/`false`, `null`), and `#` comments. Flow mappings (`{ a: 1 }`), anchors, aliases, multi-line
scalars, and tags are outside the subset: the parser reports the line and the surface is treated
as unreadable (`run[]` reason names the file and the construct), never silently partial. The config
contract in `contracts.md` is written in block style so it never needs a flow mapping.

**Rationale.** The fleet has no shared YAML reader (its only readers are flat-scalar shell helpers)
and no `PyYAML` prerequisite anywhere; declaring one would make a required-for-correctness
dependency out of a config file that is optional. The subset is small enough to test exhaustively
and covers the consumer's ecosystem files, whose schema uses only these constructs. Switch
condition: a consumer surface this plugin must read legitimately needs a construct outside the
subset.
