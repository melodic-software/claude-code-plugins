# Lane reference

Per-detector detail for `/code-tidying:audit-dead-code`. The lane roster, the measured confidence
of each lane, and the shape/tier table live in SKILL.md; this file carries the invocation, the
degradation mechanics, and the reasons a lane is shaped the way it is.

Every number here is measurement, not documentation. A change that contradicts one needs a new
measurement, not an argument.

## Lane reference

### knip — TS/JS

- **Invocation:** `knip --reporter json --no-progress`, run with cwd set to the **project root**,
  one root per `package.json`. Never one run for the whole repository: a monorepo's workspaces have
  their own installs, their own configs, and their own restore state, and one broken workspace must
  not condemn the others.
- **Findings are filtered to what the root OWNS and what the caller asked for** — paths under that
  root and under no nested root, never a path excluded from candidate scope (`node_modules`, `dist`,
  `build`, `vendor`, `**/evals/fixtures/**`), and never a file outside the scoped `TS_FILES` set.
  Invoking knip at a root does not restrict what it *reports*: it walks the whole subtree, nested
  workspaces included, and has no per-file input mode that preserves cross-file usage. Measured on
  this marketplace before the ownership filter existed, the repo-root run emitted **213 of its 288
  candidates** for files owned by roots the same scan had already declared `degraded` — the
  withheld false positives came back in through the outer root. A narrow target such as
  `src/one-file.ts` still invokes knip at the project root (so usage across files is visible) and
  then drops every finding whose path is not in that target set.
- **Binary resolution:** the repo-local `node_modules/.bin` walk first (upward from the project
  root, symlinks followed with a hop cap, physical target required to stay inside the repository),
  then PATH. A pinned devDependency is the version that matches the project it is judging.
  Measured: `npm i -D knip` leaves knip **off PATH**, so a bare-name probe reports "missing" on a
  correctly configured repo.
- **Restore probe is DIRECT and walks ancestors.** `node_modules` present and non-empty at the
  resolved root *or an ancestor up to the repo root* — the same walk `dc_locate_binary` uses for a
  hoisted workspace install. It is never inferred from knip's `unresolved` / `unlisted` output:
  measured, restored and unrestored JSON were **byte-identical**: those keys report source defects,
  not restore state. A nested package with no local `node_modules` is therefore restored when the
  hoisted ancestor install is present, and degraded only when no ancestor has a nonempty cache.
- **Degradation is read from stderr.** Any `ERROR:` line makes the run degraded. Measured, a failed
  `vitest.config.ts` load produced **2 phantom "unused files"** while the `ERROR:` line went to
  stderr — which `--reporter json` discards. The stdout blob of a degraded run looks perfectly
  healthy, so stdout genuinely cannot establish run health here.
- **Exit codes:** `0` clean, `1` findings, `1` hard error. Findings and failure are indistinguishable.
- **Config evaluation is disclosed, not denied.** knip loads a repository-controlled
  `knip.config.{ts,js,mjs,cjs}` through `jiti`; a planted side effect in one **fired**. Every run
  that loads a config module says so in the report. The same experiment in Python did not fire:
  vulture is genuinely pure.
- **Class members are absent from knip 6.** `--include classMembers` returns
  `ERROR: Invalid issue type`. The lane does not claim them.
- **Measured JSON shape** (6.32.2): `{"issues":[{"file":"…","files":[{"name":"…"}],"exports":
  [{"name":"…","line":13,"col":17,"pos":533}],"types":[],"enumMembers":[],…}]}`. The parser is
  deliberately tolerant of a flattened future shape and routes anything it cannot recognize into
  T3 drift rather than dropping it.

### vulture — Python

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
  it. The parse error is written to **stderr** in `<path>:<line>: <message>` shape — the same shape
  a finding wears on stdout — and the exit code is `1` alone or `3` when real findings coexist.
- **Two stderr shapes, opposite meanings.** A `<path>:<line>: <message>` line means one input file
  was unparsable: the lane still ran over everything else, and it is reported as an input note.
  Anything else on stderr (a usage error, a traceback) means the run itself is unsound and the lane
  is degraded. Conflating them would let one stray `.toml` in scope suppress the whole Python lane.
  knip's `ERROR:` stderr rule does **not** generalize here.
- **Exit codes:** `0` clean, `3` findings, `1` input error. Health comes from the shape of stderr,
  never from the code.
- **Pipeline safety:** vulture raises `BrokenPipeError` and returns 1 when its stdout closes early,
  so its output is written to a temp file and read back in full — never piped into a truncating
  reader.

### gopls — Go

- **Invocation:** `gopls check -severity=hint`, run with cwd set to the module root, one root per
  `go.mod`. Per the official docs gopls "does not run the actual compiler": it runs `go list` plus
  its own front end, and Go has no `build.rs` equivalent, so there is no project code to execute.
  That is why Go passes the no-build rule while Rust and .NET do not.
- **Unexported symbols only.** That is the lane's **declared coverage**, not a defect. An exported
  symbol is reachable from outside the module and no in-module analysis can call it dead.
- **Ownership, as in the knip lane.** A module is handed only the `.go` files it owns — paths under
  it and under no nested `go.mod` — and a diagnostic about a file it does not own is dropped, so a
  nested module's symbols are reported by that module's own run alone.
- **No native suppression.** Measured (gopls v0.20.0 / go1.24.7): `//lint:ignore U1000`,
  `//lint:ignore unusedfunc`, `//nolint:…`, and `// Deprecated:` are all still reported — the hint
  comes from gopls's own `unusedfunc` analyzer, not from staticcheck. See
  [adjudication.md](adjudication.md) "Suppression formats".
- **Precondition:** a resolvable module cache — the same class of precondition as `node_modules`.
- **Degradation has two shapes, both with exit 0.** An unresolved dependency prints an import error
  on **stdout** and suppresses the hints; a workspace-load failure leaves **stdout empty** and puts
  the error on **stderr**. Either way the lane produces false **NEGATIVES** — the opposite of knip's
  false positives. The report must not describe the two with one shared phrase.
- **Paths are absolute and cwd-independent.** `gopls check -h` exposes only `-severity`; no flag
  relativizes them, so the script relativizes to the repo root itself. The column field is a
  **range** (`17:6-17`) whenever the diagnostic spans one.
- **Measured output shape:** `/abs/path/dead-and-dynamic.go:17:6-17: function "deadHandler" is
  unused` — exit **0** while carrying that finding, with the used and exported functions correctly
  left un-hinted.

### grep — shell and other symbol languages

- **The portable floor is `grep -w -F -f <names>`** over the repository's tracked files. `-F` is
  **mandatory**: without it `core.ts` matches `coreXts`. None of `-w`, `-F`, `-f` is a GNU-only
  construct, so the lane runs on a BSD userland unchanged.
- **Extractor set:** shell function definitions (`name() {`, `function name`) and PowerShell
  `function Name`. Names shorter than three characters are dropped — at that length the reference
  search is noise rather than evidence.
- **Precision over recall, deliberately.** 4/4 true positives and 0 false positives over 546 `.sh`
  files and 177,793 lines, at 3.1s; shellcheck found **0** of the same 4.
- **The known false-**alive** classes.** `$`, `-`, and `.` are non-word characters, so `foo` matches
  inside `$foo`, `foo-bar`, and `foo.bar`. A hit like that reads as a reference and quietly saves a
  symbol that may in fact be dead. The cost is **missed** dead code, never condemned live code —
  acceptable for a read-only skill, and the reason the lane ships as high-precision/low-recall.
- **A hit adjacent to `$`, `-`, or `.` is never an automatic `alive`** during adjudication: inspect
  it before crediting it as a reference.

## Why Rust, .NET, and an LSP scanning lane are absent

- **Rust and .NET**: rust-analyzer's dead-code signal comes from `cargo check`, which compiles
  `build.rs` and proc macros; the Roslyn server signals "project needs to be restored"; clangd needs
  `compile_commands.json`; jdtls needs a built classpath. Every one of them builds or executes
  project code. The exclusion trigger is a detector that does neither — that trigger is what
  admitted Go.
- **An LSP scanning lane**: Claude Code's `LSP` tool is model-callable only. No bash script can
  reach it, and it has no batch mode, so enumerating every symbol would cost one model turn each.
  It is retained only as an optional per-candidate assist inside the already-bounded adjudication.
- **`DiagnosticTag.Unnecessary`**: wrong scope everywhere (file-local/private only), push-only
  delivery, and Claude Code's diagnostics normalizer strips `tags` entirely.
- **pyright as a Python detector**: measured, it misses `dead_fn`, `DeadClass`, and `dead_method` —
  its unused checks fire only on `_`-prefixed file-local names. It would strictly *reduce* recall
  against vulture.
