# Analyzer reference

Per-detector detail for `/code-tidying:audit-dead-code`. The analyzer roster, the measured confidence
of each analyzer, and the shape/tier table live in SKILL.md; this file carries the invocation, the
degradation mechanics, and the reasons an analyzer is shaped the way it is.

Every number here is measurement, not documentation. A change that contradicts one needs a new
measurement, not an argument. Basis: the tool versions named per analyzer below, as recorded on
2026-08-23. Recheck trigger: a major version bump in knip, vulture, gopls, or the Go toolchain.

## Analyzer reference

### Coverage accounting

Every in-scope source file is either covered or named. Covered means an analyzer took the file as input
and reached `ran` or `degraded`. Uncovered files are one `Note: uncovered <path> — <reason>` line
each, after `Summary coverage: covered=N uncovered=M`. The reasons are `no analyzer for the language`,
`no manifest root`, `tool not installed`, `tool could not parse it`, and `analyzer not selected`.

`files=` on an `Analyzer:` line is that input count, including `skipped` and `no-manifest`. `Summary
total: files-with-findings=` is the number of files that emitted a candidate. A clean-result note
is printed only when `uncovered=0`, some analyzer reached `ran`, and there are no candidates. Uncovered
files suppress both that note and the scan-of-nothing note.

`no-manifest` is the state when knip has no `package.json` root, or gopls has no `go.mod` root.
`files=` is the real language count, which is zero only when no such file is in scope. A source
file that sits outside every manifest root of its language is uncovered with `no manifest root`
even when some other root ran, unless another analyzer took it. The grep analyzer takes JS/TS that no
`package.json` root owns, so a full run covers it and only `--analyzer knip` leaves it listed.
`skipped` stays the missing-or-uninvocable binary state.

Source files with no analyzer are the extensions in `DC_NOLANE_EXTS` (Rust, F# and VB, JVM, Ruby, C
and C++, and the others listed there) and extensionless files whose shebang names a non-shell
interpreter. Add a lowercase extension to `DC_NOLANE_EXTS` (`scripts/lib/dead-code-shapes.sh`) to
classify it. An extensionless file with a line-1 shell shebang (`sh`, `bash`, `dash`, `zsh`, `ksh`,
including `env` forms) joins the shell analyzer, and one with no shebang is not source. The grep analyzer
covers the no-analyzer files when it runs. Docs, JSON, YAML, and other
non-source paths are not in the coverage total.

### knip: TS/JS

- **Invocation:** `knip --reporter json --no-progress`, run with cwd set to the **project root**,
  one root per `package.json`. Never one run for the whole repository: a monorepo's workspaces have
  their own installs, their own configs, and their own restore state, and one broken workspace must
  not condemn the others.
- **Findings are filtered to what the root owns and what the caller asked for**: paths under that
  root and under no nested root, never a path excluded from candidate scope (`node_modules`, `dist`,
  `build`, `vendor`, `**/evals/fixtures/**`), and never a file outside the scoped `TS_FILES` set.
  Invoking knip at a root does not restrict what it *reports*: it walks the whole subtree, nested
  workspaces included, and has no per-file input mode that preserves cross-file usage. Without the
  ownership filter an outer root re-emits the very candidates a nested degraded root withheld, so
  one broken workspace's false positives reach the report through the repo-root run. A narrow
  target such as `src/one-file.ts` still invokes knip at the project root (so usage across files is
  visible) and then drops every finding whose path is not in that target set.
- **Binary resolution:** the repo-local `node_modules/.bin` walk first (upward from the project
  root, symlinks followed with a hop cap, physical target required to stay inside the repository),
  then PATH. A pinned devDependency is the version that matches the project it is judging.
  Measured: `npm i -D knip` leaves knip **off PATH**, so a bare-name probe reports "missing" on a
  correctly configured repo.
- **Restore probe is direct and walks ancestors.** `node_modules` present and non-empty at the
  resolved root *or an ancestor up to the repo root*, the same walk `dc_locate_binary` uses for a
  hoisted workspace install. It is never inferred from knip's `unresolved` / `unlisted` output:
  measured, restored and unrestored JSON were **byte-identical**: those keys report source defects,
  not restore state. A nested package with no local `node_modules` is therefore restored when the
  hoisted ancestor install is present, and degraded only when no ancestor has a nonempty cache.
- **Degradation is read from stderr.** Any `ERROR:` line makes the run degraded. Measured, a failed
  `vitest.config.ts` load produced **2 phantom "unused files"** while the `ERROR:` line went to
  stderr, which `--reporter json` discards. The stdout blob of a degraded run looks perfectly
  healthy, so stdout genuinely cannot establish run health here.
- **Exit codes:** the analyzer never reads knip's exit code; run health comes from stderr, as above.
  Pointer: [knip CLI `--no-exit-code`](https://knip.dev/reference/cli#--no-exit-code).
- **Config evaluation is disclosed, not denied.** Measured: a side effect planted in a
  repository-controlled `knip.config.{ts,js,mjs,cjs}` **fired**, so knip runs that module as code. Every run that
  loads a config module says so in the report. The same experiment in Python did not fire:
  vulture is genuinely pure.
  - **Pointer**: when checking which config file names knip loads, fetch
    [knip configuration: Location](https://knip.dev/overview/configuration#location) live.
- **Class members are absent from knip 6.** `--include classMembers` returns
  `ERROR: Invalid issue type`. The analyzer does not claim them.
- **Measured JSON shape** (6.32.2): `{"issues":[{"file":"…","files":[{"name":"…"}],"exports":
  [{"name":"…","line":5,"col":17,"pos":84}],"types":[],"enumMembers":[],…}]}`. The parser is
  deliberately tolerant of a flattened future shape and routes anything it cannot recognize into
  T3 drift rather than dropping it.

### vulture: Python

- **Invocation:** one process over **every in-scope `*.py` file at once**. Chunking would fragment
  vulture's cross-file usage counting and inflate its already-low precision.
- **Pre-applied suppressions**, the false-positive classes measured to matter:
  `--ignore-names 'test_*,pytest_*'` and `--ignore-decorators` for route/fixture/property/command
  decorators. A consumer extends these through the native whitelist, not by editing the script.
- **The confidence knob does not exist for this skill's targets.** `--min-confidence 60` yields 18
  findings on the trap fixtures; `70`, `90`, and `100` yield **0**. Every unused function, class,
  method, variable, and attribute is pinned at exactly 60. 100 is reserved for intra-function
  unreachable code. This is why `--max` orders by git recency and not by confidence.
- **Input filtering is mandatory.** Handed a non-Python file, vulture logs a parse error and skips
  it. The parse error is written to **stderr** in `<path>:<line>: <message>` shape, the same shape
  a finding wears on stdout.
- **Two stderr shapes, opposite meanings.** A `<path>:<line>: <message>` line means one input file
  was unparsable: the analyzer still ran over everything else, and it is reported as an input note.
  Anything else on stderr (a usage error, a traceback) means the run itself is unsound and the analyzer
  is degraded. Conflating them would let one stray `.toml` in scope suppress the whole Python analyzer.
  knip's `ERROR:` stderr rule does **not** generalize here.
- **Exit codes:** health comes from the shape of stderr, never from the code. Pointer:
  [vulture exit codes](https://github.com/jendrikseipp/vulture#exit-codes).
- **Pipeline safety:** vulture's output is written to a temp file and read back in full, never
  piped into a truncating reader; a stdout closed early fails the run (measured, versions per the
  record above).

### gopls: Go

- **Invocation:** `gopls check -severity=hint`, run with cwd set to the module root, one root per
  `go.mod`. Go passes the no-build rule while Rust and a .NET build analyzer do not: a gopls run <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  executes no project code, since Go has no `build.rs` equivalent.
  - **Pointer**: when checking how gopls computes its diagnostics, fetch
    [Gopls: Diagnostics](https://go.dev/gopls/features/diagnostics) live.
- **Unexported symbols only.** That is the analyzer's **declared coverage**, not a defect. An exported
  symbol is reachable from outside the module and no in-module analysis can call it dead.
- **Ownership, as in the knip analyzer.** A module is handed only the `.go` files it owns, paths under
  it and under no nested `go.mod`, and a diagnostic about a file it does not own is dropped, so a
  nested module's symbols are reported by that module's own run alone.
- **No native suppression.** Measured (gopls v0.20.0 / go1.24.7): `//lint:ignore U1000`,
  `//lint:ignore unusedfunc`, `//nolint:…`, and `// Deprecated:` are all still reported. The hint
  comes from gopls's own `unusedfunc` analyzer, not from staticcheck. See
  [adjudication.md](adjudication.md) "Suppression formats".
- **Precondition:** a resolvable module cache, the same class of precondition as `node_modules`.
- **Degradation has two shapes, both with exit 0.** An unresolved dependency prints an import error
  on **stdout** and suppresses the hints; a workspace-load failure leaves **stdout empty** and puts
  the error on **stderr**. Either way the analyzer produces false **negatives**, the opposite of knip's
  false positives. The report must not describe the two with one shared phrase.
- **Paths are absolute and cwd-independent.** The script relativizes them to the repo root
  itself rather than relying on a gopls flag. The column field is a **range** (`17:6-17`) whenever
  the diagnostic spans one.
  - **Pointer**: when checking whether `gopls check` has gained a flag that relativizes paths, run
    `gopls check -h`, or fetch [gopls command line](https://go.dev/gopls/command-line) live.
- **Measured output shape:** `/abs/path/dead-and-dynamic.go:11:6-17: function "deadHandler" is
  unused`. Exit **0** while carrying that finding, with the used and exported functions correctly
  left un-hinted.

<!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
### grep: shell, PowerShell, C#, and standalone JS/TS

- **The portable floor is `grep -w -F -f <names>`** over the repository's tracked files. `-F` is
  **mandatory**: without it `core.ts` matches `coreXts`. None of `-w`, `-F`, `-f` is a GNU-only
  construct, so the analyzer runs on a BSD userland unchanged.
- **Extractor set:** shell function definitions (`name() {`, `function name`), PowerShell
  `function Name`, and, in JS/TS files that no `package.json` root owns, `function`, `class`,
  `const`, `let` and `var` declarations with or without `export` (`async` and `default` allowed).
  Names shorter than three characters are dropped. At that length the reference search is noise
  rather than evidence. A file inside a `package.json` root is knip's and is never extracted here,
  so no export is reported twice.
- **Precision over recall, deliberately.** 4/4 true positives and 0 false positives over 546 `.sh`
  files and 177,793 lines, at 3.1s; shellcheck found **0** of the same 4.
- **The known false-**alive** classes.** `$`, `-`, and `.` are non-word characters, so `foo` matches
  inside `$foo`, `foo-bar`, and `foo.bar`. A hit like that reads as a reference and quietly saves a
  symbol that may in fact be dead. The cost is **missed** dead code, never condemned live code,
  which is acceptable for a read-only skill and the reason the analyzer ships as high-precision/low-recall.
- **JS/TS symbols use the same referenced-anywhere rule** (a name whose only repository-wide hits
  are its own definition sites is a candidate) and emit `ts-unreferenced-symbol` at tier 2.
  The figures are derived, not a dated scan: they come from the candidate set
  `scripts/dead-code-scan.test.sh` asserts. That test scans the trap corpus (`ts-entry.ts`,
  `ts-used.ts`, `ts-orphan.ts`, `dead-and-dynamic.ts`) plus `standalone.mjs`, with no
  `package.json`, and one extra test-only file, `computed.mjs`. It asserts exactly 5
  candidates. The fifth, `handleAlpha`, is defined only in `computed.mjs`. Over the corpus
  alone, that leaves 4 candidates: 3 true (`parseLegacyManifest`, `renderLegacyRow`,
  `formatLegacyRow`) and 1 false (`main`, an entry-point export nothing imports), so **75%
  precision**. Re-measure with a scan before quoting the figure as recorded. It finds all 3 dead symbols only
  because nothing else in the corpus spells their names: a name in a comment or a string literal
  (`renderPanel`) saves the symbol, so recall drops wherever prose names a dead symbol. A name
  assembled at run time is a candidate. Tier 2 follows from the figure. The precision is below the tier 1 shell symbols,
  and an export used only by an outside consumer reads as unreferenced. A symbol used only inside
  its own file counts as referenced and stays unreported.
- **C# is read as text and nothing is built.** No `dotnet`, MSBuild, restore or analyzer runs. The <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  extractor takes `class`, `struct`, `interface`, `enum` and `record` declarations, and members
  whose line opens with `public`, `internal`, `protected` or `private`. The name is the last word
  before the parameter list, initializer, terminator or accessor body. Not extracted: a member with
  no access modifier (private by default), an override or operator (reached without spelling the
  name), a constructor, an indexer and a tuple-typed member. A line yields one name, so
  `int alpha, beta;` yields only `beta`, and `int alpha = 1, beta = 2;` only `alpha`. There is no overload or type resolution, and no unused-parameter or unused-`using`
  detection.
- **Two C# shapes, one reference rule.** A `private` declaration (not `private protected`) is <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  `cs-unreferenced-private`; any other is `cs-unreferenced-symbol`. Both use the
  referenced-anywhere rule above. A private member is accessible "only within the body of the
  class or the struct where you declare them", and from nested types in that body
  ([private keyword](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/private)), <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  but a partial type spreads that body over files: "Any class, struct, or interface members
  declared in a partial definition are available to all the other parts"
  ([Partial classes and members](https://learn.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/partial-classes-and-methods)). <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  The repository-wide search covers both, and a reflection lookup by a string literal in another
  file. The cost is recall: a dead name that matches any other word in the repository is saved.
  No stop list is applied, because a short common name (`Get`, `Name`) costs recall, never
  precision. Both pages read 2026-10-29.
- **Markup is in the reference corpus.** `.razor` and `.cshtml` files are tracked, so the search <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  reads them. A component names its handler in markup as `@on{DOM EVENT}="{DELEGATE}"`
  ([Blazor event handling](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/event-handling), <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  read 2026-10-29), so a code-behind handler `@onclick` names, or a `[Parameter]` property a
  parent sets, is saved. The analyzer extracts nothing from markup, and markup is not in the coverage
  total.
- **C# figures** come from the trap corpus `cs-orders.cs`, `cs-program.cs`, <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  `OrderCounter.razor.cs`, `OrderCounter.razor` and `OrderPage.razor`: the candidate set <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  `scripts/dead-code-scan.test.sh` asserts, recorded 2026-10-29. `cs-unreferenced-private`: 3
  candidates, 2 true (`_staleCounter`, `FormatLegacyOrder`) and 1 false (`OnAudit`, invoked by
  reflection under a name built at run time), so **66.7% precision**. Of 3 dead private members it
  found 2, so **66.7% recall**: the dead private `Clamp` is saved by the live `QuantityRules.Clamp`.
  `cs-unreferenced-symbol`: 3 candidates, 1 true (`LegacyOrderExporter`) and 2 false
  (`AuditRequestHandler`, created by assembly scanning; `Sku`, read only by `JsonSerializer`), so
  **33.3% precision** and **100% recall** (1 of 1). Saved: the interface implementation `Handle`,
  the Razor handler `HandleRefresh`, the parameter `Total` and the used class `QuantityRules`.
  Each shape yields a false dead, so both are tier 2.
- **How the C# pass fails.** False dead: reflection by a computed name, DI or assembly scanning, <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  MediatR-style handler discovery, a property only a serializer reads, a member a source generator
  calls, a <!-- spellchecker:off -->`[JSInvokable("alias")]`<!-- spellchecker:on --> method JavaScript calls by the alias, a component only `@page`
  routing reaches, and an entry-point `Main`. False alive: a dead name shared with any other
  identifier, string or comment in the repository.
- **A hit adjacent to `$`, `-`, or `.` is never an automatic `alive`** during adjudication: inspect
  it before crediting it as a reference.
- **`unreferenced-file` reuses this search** on two keys per source file: the basename and the
  repo-relative path. A file in a language with no analyzer also gets its stem as a key, because a
  compiled unit is named by its stem (`new Widget()`, `mod widget;`), never its filename. A hit in
  any other tracked file saves it. That includes CI workflows, settings, manifests, and docs. A hit
  inside the file itself does not. The input set is shell, PowerShell, Python entry points (line-1
  shebang, a `__name__` guard, or `__main__.py`), JS/TS that no `package.json` root owns, C# (keyed <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  on its stem with every extension dropped, so `Counter.razor.cs` is saved by `<Counter`), and <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  source extensions with no analyzer. Go stays on the gopls analyzer. Knip still owns unused TS/JS files
  inside a manifest root. The shape is tier 2: a computed path, a glob, `python -m`, or a build
  file that never spells the path can still load the file, so the candidate is uncertain, not
  dead. Precision of this shape is unmeasured beyond the fixture contract (a workflow reference
  saves the script it names; a script named nowhere is the one candidate).
- **`-H -o` attribute each match to its file**, and the analyzer relies on BSD grep taking both flags.
  Pointer: [FreeBSD grep(1)](https://man.freebsd.org/cgi/man.cgi?query=grep&sektion=1).

<!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
## Why Rust, a .NET build analyzer, and an LSP scanning analyzer are absent

- **Rust and a .NET build analyzer**: rust-analyzer's dead-code signal comes from `cargo check`, which <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  compiles `build.rs` and proc macros; the Roslyn server signals "project needs to be restored";
  clangd needs `compile_commands.json`; jdtls needs a built classpath. Every one of them builds or
  executes project code. The exclusion trigger is a detector that does neither. That trigger is
  what admitted Go, and what admits the grep analyzer's C# pass, which reads `.cs` text and runs no <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  .NET tool. A Roslyn or ReSharper analyzer, with unused parameters and unnecessary `using` directives, <!-- portability-ok: R6 kept-adapter operation - dead-code-scan.sh C# grep pass -->
  stays excluded. Source files in the other languages still enter the grep analyzer's
  `unreferenced-file` search, which does not build.
- **An LSP scanning analyzer**: an analyzer is a detector the scan script runs in one batch. Claude Code's
  `LSP` tool is used only as an optional per-candidate assist inside the already-bounded
  adjudication. Pointer:
  [LSP tool behavior](https://code.claude.com/docs/en/tools-reference#lsp-tool-behavior).
- **`DiagnosticTag.Unnecessary`**: wrong scope everywhere (file-local/private only), push-only
  delivery, and Claude Code's diagnostics normalizer strips `tags` entirely.
- **pyright as a Python detector**: measured, it misses `dead_fn`, `DeadClass`, and `dead_method`.
  Its unused checks fire only on `_`-prefixed file-local names. It would strictly *reduce* recall
  against vulture.
