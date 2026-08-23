# Dead-Code Detection Tool Landscape (2025–2026)

> **Status:** durable measurement record, graduated from the `dead-code-detection-skill` contract
> slice when `/code-tidying:audit-dead-code` shipped. It is the evidence base behind that skill's
> lane roster and its exclusions — anything here that a later change contradicts needs new
> measurement, not argument. Two rows were corrected after this survey by direct capture and the
> corrections live in the skill's `context/lanes.md`: vulture's parse error goes to **stderr**
> (exit 1, or 3 alongside findings), not stdout with exit 0; and `gopls check` emits **absolute,
> cwd-independent paths** with no relative-path flag. `gopls check -severity=hint` was also
> established later — see `dead-code-lsp-viability.md` — as a CLI dead-code detector that does not
> build, which is why Go is a shipped lane despite this document predating that finding.

Research input for a Claude Code skill that orchestrates per-ecosystem dead-code detectors
("tool-first, model-verified" auditing: run the best static tool, parse its machine-readable
output, then have the model adjudicate each finding against dynamic-usage evidence).

Researched 2026-08-17 via web sources; tool status/deprecation verified against current docs
and repos, not training memory. Sources listed at the end of each section.

---

## 1. TypeScript / JavaScript

### Landscape verdict

**knip is the single consolidated winner.** Its three historical competitors are all archived
and point users at knip:

| Tool | Status (2026) |
|---|---|
| **knip** | Actively maintained, the standard recommendation |
| ts-prune | **Archived / maintenance mode** — README recommends knip |
| depcheck | **Archived (2025)** — recommends knip |
| unimported | **Archived** — same author as knip; recommends knip |

### knip

- **Detects:** unused files, unused exports (values *and* types), unused enum members,
  unused class members (opt-in), duplicate exports, unused `dependencies`/`devDependencies`,
  unlisted dependencies, unlisted binaries, unresolved imports. Workspace/monorepo aware.
- **Entry-point handling:** ~182 framework plugins auto-detect entry points and config-file
  references (Next.js, Vite, Vitest, Astro, Storybook, ESLint configs, etc.) — this is its
  main false-positive defense. Manual config via `knip.json`: `entry`, `project`,
  `ignore`, `ignoreDependencies`, `ignoreBinaries`, `ignoreExportsUsedInFile`, per-workspace
  overrides. Individual exports can be kept alive with a `/** @public */` JSDoc tag.
- **Modes:** default (includes dev/test surface) vs `--production` (strict: only production
  entry points; finds test-only code too). `--fix` can auto-remove unused exports/deps.
- **Machine-readable output:** yes — `--reporter json` (also `compact`, `markdown`,
  `codeowners`; custom reporters/preprocessors supported).
- **Blind spots / FP sources:** dynamic `import()` with computed paths, string-keyed
  dispatch (`require(someVar)`), webpack magic comments, DI containers resolving by string
  token, exports consumed only by an external repo (published library surface — use
  `ignoreExportsUsedInFile` / `@public` / entry config), framework conventions not covered
  by a plugin, code referenced only from HTML/templates/CMS config.

### ts-prune (superseded)

TS-compiler-API scan for un-imported exports only; no file/dependency/class-member analysis.
Text output (`path:line - name (used in module)`); no JSON. Keep only for legacy pipelines.

### Scope-local complements

`tsc --noUnusedLocals/--noUnusedParameters` and ESLint `no-unused-vars` catch
function/module-local dead variables — orthogonal to knip's cross-module analysis.

Sources: knip.dev (Comparison & Migration, Unused exports, Getting started), github.com/nadeesha/ts-prune,
github.com/depcheck/depcheck, effectivetypescript.com 2023-07-29 knip recommendation update.

---

## 2. Python

### vulture (dead code)

- **Detects:** unused functions, classes, methods, variables, attributes, imports,
  properties, and unreachable code (`after return`, `if False`, etc.). Pure AST analysis,
  no imports executed.
- **Confidence model:** each finding gets 60–100% confidence (100% = provably unreachable;
  60% = name never referenced). `--min-confidence N` filters; 100 gives near-zero FPs but
  only unreachable-code findings; 60 gives full recall with FPs.
- **Suppression:** `--ignore-names "visit_*,do_*"`, `--ignore-decorators "@app.route"`,
  and **whitelist modules** — `--make-whitelist` emits a Python file that fake-references
  the flagged names; commit it and pass it as an extra argument. Config lives in
  `pyproject.toml [tool.vulture]`.
- **Machine-readable output:** **no native JSON** — stable one-line-per-finding text
  (`file:line: unused function 'x' (60% confidence)`) that is trivially parseable;
  treat as line-oriented, not JSON.
- **Blind spots:** `getattr`/`globals()` reflection, framework entry points (Django views
  referenced from `urls.py` strings, Celery tasks, pytest fixtures, plugin registries,
  signal handlers), names used only in templates, `__all__`-driven re-export surfaces,
  dataclass/pydantic fields consumed by serialization.

### deadcode (PyPI) — newer alternative

Vulture-inspired, presented at EuroPython 2024; adds `--fix` (auto-removal), richer ignore
flags (e.g. ignore-if-decorated-with), `pyproject.toml` config. Worth offering as an
alternative backend; vulture remains the default choice on maturity.

### deptry (dependencies)

- **Detects:** unused/obsolete declared dependencies (DEP002), missing (undeclared)
  dependencies (DEP001), transitive deps used directly (DEP003), misplaced dev deps (DEP004).
  Understands PEP 621, Poetry, uv, requirements files.
- **Suppression:** `pyproject.toml [tool.deptry]` per-rule ignores
  (`ignore = ["DEP002"]`, `per_rule_ignores = { DEP002 = ["pkg"] }`), package-to-module
  mapping overrides.
- **Machine-readable output:** yes — `--json-output <file>`.
- **Blind spots:** deps invoked only as CLI tools, plugins loaded by entry-point metadata
  (pytest plugins, setuptools plugins), optional extras, deps imported inside `try/except`.

### ruff (scope-local dead code)

Relevant rules: **F401** unused imports (autofixable; `__init__.py` re-export and
`__all__` aware), **F841** unused local variables, **ARG00x** unused function/method
arguments, **ERA001** commented-out code, **F811** redefinition shadowing. Ruff is
scope-local only — it cannot find cross-module unused symbols. Suppression via
`# noqa: F401` or per-file-ignores. **JSON: yes** — `--output-format json` (also SARIF,
GitLab, JUnit). Use ruff as a cheap first pass; vulture for cross-module analysis.

Sources: github.com/jendrikseipp/vulture (README), pypi.org/project/vulture,
deptry.com docs via search, docs.astral.sh/ruff (linter, rules F401), EuroPython 2024 deadcode talk.

---

## 3. .NET (C#) ecosystem

### Roslyn built-in analyzers (ship with the .NET SDK)

- **IDE0051** (remove unused private member) and **IDE0052** (remove unread private
  member — written but never read). **Private accessibility only** by design; the compiler
  cannot assume anything about `internal`/`public` reachability. Related: IDE0060/CA1801
  unused parameters, CS0168/CS0219 unused locals, IDE0005 unnecessary usings.
- **Configuration:** `.editorconfig` severity (`dotnet_diagnostic.IDE0051.severity = warning`);
  enable in build with `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>`.
- **Suppression:** `#pragma warning disable IDE0051`, `[SuppressMessage]`, GlobalSuppressions.cs.
- **Machine-readable output:** yes — build with `-warnaserror`-style capture plus
  `/p:ErrorLog=diag.sarif` (MSBuild emits **SARIF**), or `dotnet format analyzers --verify-no-changes --report`.
- **Known FPs (documented in dotnet/roslyn issues):** members used only by source
  generators (`IIncrementalGenerator` output, issue #78934), reflection, serializers
  (JSON/XML), Unity serialized fields (Unity ships suppressors, e.g. USP0008), WPF/WinForms
  designer references, stale IDE state (#76857).

### ReSharper command-line tools — InspectCode (`jb inspectcode`)

- Free CLI (`dotnet tool install -g JetBrains.ReSharper.GlobalTools`), runs ReSharper's
  **solution-wide analysis**, which is what catches non-private dead code:
  `UnusedMember.Global`, `UnusedType.Global`, `UnusedMethodReturnValue.Global`,
  `UnusedParameter.Global`, etc.
- **Machine-readable output:** yes — **SARIF is the default output format since 2024.1**
  (`-o=result.sarif`; `-f=Xml|Html|Text|Sarif`, multiple via `-f=Html;Xml`).
- **Suppression / known-alive:** JetBrains.Annotations `[UsedImplicitly]`,
  `[PublicAPI]`, `ImplicitUseTargetFlags`, plus comment suppressions and severity config
  in `.DotSettings`.
- **Blind spots:** reflection, DI container registration by scanning
  (`services.Scan(...)`, MediatR handlers, ASP.NET conventions — controllers/minimal-API
  handlers are usually recognized, but custom convention layers are not), config-string
  type references, serialization contracts.

### Others

Roslynator (RCS1213 remove unused member) overlaps IDE0051; NDepend (commercial) does
solution-wide dead-code queries (CQLinq) with reflection caveats. For the skill:
IDE0051/IDE0052 via build SARIF for privates + InspectCode SARIF for solution-wide.

Sources: learn.microsoft.com IDE0051/IDE0052 pages, jetbrains.com/help/resharper/InspectCode.html,
JetBrains .NET Tools Blog (ReSharper 2024.1 SARIF default), dotnet/roslyn issues #78934, #76857, #30965.

---

## 4. Shell

### shellcheck — the only real option

- **SC2034** "foo appears unused. Verify use (or export if used externally)." — unused
  variables, file-local scope only. **SC2317** "Command appears to be unreachable" and
  **SC2329** "This function is never invoked" (present in 0.11.0) fire ONLY inside a region
  already proven unreachable — e.g. after `exit 0` — and are notoriously noisy with `trap`
  handlers and callback-style functions.
- **Measured limit — the load-bearing one.** A top-level function that is defined and never
  called in an otherwise-live script produces **zero findings**, verified against shellcheck
  0.11.0 with `-o all`, `-S style`, and `--include=SC2329`. Over this repository's 546
  tracked `.sh` files (177,793 lines), shellcheck reports **0** dead functions in ~60s
  wall (`-P8`); a single `rg -F -w` pass over all tracked files finds **4 genuinely dead
  functions in 0.3s**. Any claim that shellcheck detects never-called functions in live
  code is false. There is likewise **no cross-file unused-function analysis**: `source`d
  files are followed only when the path is static or annotated
  (`# shellcheck source=lib.sh`), and shellcheck analyzes one script's scope at a time.
  **Consequence for a tool-first design: shell is a model/grep lane, not a tool-backed one.**
- **Suppression:** `# shellcheck disable=SC2034` (line, function, or file scope — file
  scope via directive on first line after shebang), `export` the variable, use `_` for
  throwaways, `.shellcheckrc` (`disable=SC2034`).
- **Machine-readable output:** yes — `--format=json1` (also `json`, `gcc`, `checkstyle`,
  `diff`).
- **Documented FP classes (by design — shellcheck does not resolve even trivial
  indirection):** `export "$name"`, `eval` references, `declare -n` namerefs,
  `[[ -v "FOO[$KEY]" ]]`, variables consumed by a sourcing/sourced script, variables read
  by external tools via `env`, variables used only in `unset`.
- **Skill implication:** shell is the weakest ecosystem — expect the model-verification
  pass to carry most of the weight (grep for the variable/function name across all scripts,
  including dynamically sourced ones, and in `envsubst`/template files).

Sources: github.com/koalaman/shellcheck/wiki/SC2034, shellcheck.net/wiki/SC2034,
koalaman/shellcheck issues #718, #2461, #3379, #3275.

---

## 5. Go

Two complementary tools; use both.

### staticcheck (honnef.co/go/tools) — `unused` checks (U1000/U1001)

- **Detects:** unused **unexported** functions, types, fields, vars, consts within a
  package/module. Exported identifiers are assumed alive (a deliberate design — it can't
  know external importers). Also usefully: SA4006 (value never read), SA9003 (empty branch).
- **Suppression:** `//lint:ignore U1000 reason` comment, `-checks` flag, per-file config.
- **Machine-readable output:** yes — `staticcheck -f json`.
- **Blind spots:** reflection (`reflect.Value.MethodByName`), `//go:linkname`, cgo
  references, build-tag-gated usage, struct fields used only via encoding/json tags
  (usually recognized via marshaling, but dynamic map-based access is not).

### deadcode (golang.org/x/tools/cmd/deadcode) — whole-program

- **Approach:** loads whole program, builds a Rapid Type Analysis (RTA) call graph from
  `main` entry points; reports **unreachable functions** — including exported ones —
  grouped by package. `-test` includes test binaries as roots (essential to avoid flagging
  test-only helpers). `-whylive` explains reachability; `-filter` scopes packages.
- **Machine-readable output:** yes — `-json` (array of Package objects); also `-f=` Go
  templates.
- **Limits:** functions only — does **not** report unused types, vars, consts, or struct
  fields (open issue golang/go#64945); needs a `main` (or test) entry point, so pure
  libraries must be analyzed via `-test` or through a consumer; dynamic calls are handled
  soundly by RTA for interface dispatch, but reflection-driven calls are only heuristically
  covered (it keeps methods of types that flow into reflect).
- No ignore-file mechanism — filtering is by package pattern or post-processing JSON.

### golangci-lint

Bundles `unused` (staticcheck's), plus `unparam` (unused params/results) and
`ineffassign`. Its old `deadcode`/`varcheck`/`structcheck` linters were deprecated and
removed — do not recommend them. JSON via `--out-format json`.

Sources: pkg.go.dev/golang.org/x/tools/cmd/deadcode, go.dev/blog/deadcode,
golang/go#64945, golangci/golangci-lint discussion #6082.

---

## 6. Rust

### rustc `dead_code` lint (in-crate dead code)

- Built into every compile; warns on unused functions, structs, enums, variants, fields,
  consts. **Crate-local reachability:** in a library, anything reachable from the public
  API is considered live — it cannot see whether downstream crates actually use `pub` items.
- **Suppression:** `#[allow(dead_code)]` / `#[expect(dead_code)]` (expect warns if the
  suppression becomes stale — nice for audits), `_`-prefixed names.
- **Machine-readable:** `cargo check --message-format=json` yields structured diagnostics.
- **Blind spots:** items used only under other `#[cfg]` feature combinations (check with
  `--all-features` / feature matrix), FFI symbols consumed externally (`#[no_mangle]` is
  auto-exempt), macro-generated references usually resolve fine.
- Related allow-by-default lint: `unused_crate_dependencies` (rustc) — noisy per-target;
  the ecosystem prefers the cargo tools below.

### cargo-machete (unused dependencies — fast, stable toolchain)

- Regex/text-level scan of `src/` for each dependency's name; seconds even on large
  workspaces. `--with-metadata` improves accuracy.
- **Suppression:** `[package.metadata.cargo-machete] ignored = ["crate"]` (also workspace
  level) and `renamed` mapping for renamed deps. `--fix` removes them from Cargo.toml.
- **Machine-readable output:** yes — `--json` (per-package unused + ignored_used lists).
- **FPs:** deps used only through procedural macros, build scripts, or doc examples.

### cargo-udeps (unused dependencies — accurate, nightly)

- Compiles the crate and inspects compiler dep-tracking output; more accurate than
  machete but much slower and **requires nightly**.
- **Suppression:** `[package.metadata.cargo-udeps.ignore]` (workspace-level support
  requested, issue #231). **JSON:** `--output json`.
- **FPs:** deps used only in doc-tests.
- Both actively maintained as of 2026. Newer third option: **cargo-shear** (AST-based via
  syn, fast, `--fix`, feature-complete status) — reasonable middle ground.

**Skill recommendation:** rustc `dead_code` (+ `#[expect]`) for code, cargo-machete
(default, fast, JSON) with cargo-udeps as the high-accuracy escalation for dependencies.

Sources: lib.rs/crates/cargo-udeps, github.com/bnjbvr/cargo-machete (README: --json, metadata ignored/renamed),
crates.io/crates/cargo-shear, rustprojectprimer.com/checks/unused.html, est31/cargo-udeps#231.

---

## 7. Cross-language / generic approaches

### Coverage-based (dynamic) detection

Run the system under representative load (production or full test/E2E suite) with
coverage instrumentation; code never executed over the observation window is a
dead-code *candidate*. Examples: V8 coverage for Node, `coverage.py` (low-overhead with
Python 3.12+ `sys.monitoring`), JaCoCo in production for JVM, gcov/LLVM profiles.

- **Strengths:** immune to reflection/DI/string-dispatch — it observes truth.
- **Tradeoffs:** absence of execution ≠ dead (error handlers, leap-year/seasonal paths,
  admin tools, disaster-recovery code); needs a representative window; runtime overhead;
  per-line rather than per-symbol granularity.
- **Tombstoning variant:** insert a log-once "tombstone" in suspected-dead code, deploy,
  wait months, delete anything whose tombstone never fired. Low-risk, slow.

### Build-graph / automated-deletion prior art

- **Google "Sensenmann"** (Google engineering blog, 2023): automated dead-code deletion
  at scale — build-dependency-graph reachability from binaries/tests marks dead targets,
  auto-generates deletion changelists, human review gates merges. The closest large-scale
  precedent for "tool proposes, reviewer adjudicates."
- **Uber Piranha:** rule-based automated removal of *stale feature-flag* code paths
  (multi-language) — a specialized dead-branch remover.

### Grep / reference-tracing (the universal fallback)

Extract candidate symbols, then search the entire repo — including non-code files
(templates, YAML/JSON config, SQL, docs, CI, other languages) — for each name.

- **Strengths:** language-agnostic, catches exactly what static analyzers miss
  (string-keyed dispatch, config-file references, cross-language boundaries).
- **Tradeoffs:** no scope awareness (common names collide: `run`, `init`, `name`);
  misses computed names (`getattr(obj, "handle_" + kind)`); a *hit* proves little
  (comment? dead caller?) and a *miss* on short names proves little either.
- **Best used as the verification layer, not the detector:** a static-tool finding +
  zero repo-wide grep hits (with the declaration excluded) is strong dual evidence of
  deadness; grep hits are leads for the model to inspect, not proof of life.
- LSP "find references" is the precise version of this where a language server exists.

---

## Summary comparison table

| Ecosystem | Primary tool | Detects | JSON output | Suppression / known-alive | Key blind spots |
|---|---|---|---|---|---|
| TS/JS | **knip** (ts-prune/depcheck/unimported all archived → knip) | unused files, exports, types, enum/class members, deps | `--reporter json` | knip.json entry/ignore lists, `@public` tag, 182 framework plugins, `--production` | dynamic import paths, string DI tokens, external consumers of a published lib |
| Python code | **vulture** (alt: deadcode) | unused funcs/classes/vars/attrs/imports, unreachable code, 60–100% confidence | no (parseable text lines) | whitelist modules (`--make-whitelist`), `ignore_names`, `ignore_decorators`, `min_confidence` | getattr/reflection, framework entry points (Django urls, Celery, pytest), template refs |
| Python deps | **deptry** | unused/missing/transitive/misplaced deps | `--json-output` | per-rule ignores in `[tool.deptry]` | CLI-only tools, entry-point plugins, optional extras |
| Python scope-local | **ruff** (F401/F841/ARG/ERA001) | unused imports/locals/args, commented-out code | `--output-format json` | `# noqa`, per-file-ignores, `__all__` | scope-local only, no cross-module view |
| .NET private | **Roslyn IDE0051/IDE0052** | unused/unread private members | SARIF via `/p:ErrorLog` | `.editorconfig`, `#pragma`, `[SuppressMessage]` | source generators, reflection, serializers, Unity fields |
| .NET solution-wide | **InspectCode (`jb inspectcode`)** | UnusedMember/Type.Global etc. | SARIF (default since 2024.1) | `[UsedImplicitly]`, `[PublicAPI]`, .DotSettings | DI assembly scanning, reflection, convention layers |
| Shell | **shellcheck** (SC2034, SC2317, SC2329) | unused vars (file-local); unreachable commands/functions ONLY inside a provably-unreachable region | `--format=json1` | `# shellcheck disable=`, `.shellcheckrc`, export, `_` | never-called functions in live code (measured: 0 found repo-wide); all indirection (eval, namerefs, `export "$name"`), cross-file sourcing, trap callbacks |
| Go | **staticcheck U1000** + **x/tools deadcode** | unexported unused symbols; whole-program unreachable functions (incl. exported) | `-f json`; `-json` | `//lint:ignore`; `-filter`/`-test` (deadcode has no ignore file) | reflection, linkname, cgo, build tags; deadcode: functions only, needs main/test roots |
| Rust code | **rustc `dead_code`** | unused items/fields in-crate | `--message-format=json` | `#[expect(dead_code)]`, `_` prefix | pub API of libraries, cfg/feature combos, external FFI consumers |
| Rust deps | **cargo-machete** (escalate: cargo-udeps; alt: cargo-shear) | unused Cargo deps | `--json`; `--output json` | `[package.metadata.cargo-machete] ignored/renamed`; udeps metadata ignore | machete: proc-macro/build-script usage; udeps: doc-tests, nightly-only |

---

## False-positive classes common to all ecosystems

These are the things no static detector can know, and exactly what the model-verification
pass must check before condemning code:

1. **Reflection / dynamic lookup** — `getattr`, `reflect.MethodByName`,
   `Type.GetMethod`, `globals()[name]`, Ruby-style send. Symbol name appears only as data.
2. **String-keyed dispatch & registries** — route tables, plugin registries, event-name
   maps, DI containers resolving by string/token, ORM/serializer field names, CLI
   subcommand maps.
3. **Framework entry points & conventions** — code invoked by the framework, never by
   user code: Django views in `urls.py`, ASP.NET controllers, pytest fixtures/hooks,
   Celery tasks, serverless handlers, `main`s referenced only in deploy config, trap/signal
   handlers in shell.
4. **Dynamic import / lazy loading** — computed `import()`/`__import__`/`require(x)`
   paths, entry-point metadata (Python entry_points, OSGi-style plugins).
5. **External consumers** — public API of a published library, FFI/`#[no_mangle]`
   symbols, exported shell variables read by child processes or sourcing scripts,
   webhooks/RPC handlers called from outside the repo.
6. **Cross-language references** — symbol referenced from templates (HTML/Jinja), YAML/
   JSON config, SQL, IaC, CI pipelines, another language in the same repo.
7. **Code generation** — source generators (Roslyn `IIncrementalGenerator`), protobuf/
   OpenAPI codegen, macros: the *reference* exists only in generated or generator code.
8. **Conditional compilation / environment gating** — cfg features, build tags,
   `#ifdef`, platform-specific branches; dead under the analyzed configuration only.
9. **Serialization contracts** — fields "unread" in code but required for wire/DB
   compatibility (write-only fields, JSON round-tripping).
10. **Intentionally dormant code** — error/DR handlers, seasonal logic, deprecation
    shims kept for one release, test fixtures — *reachable* but rarely executed (this is
    the coverage-based approach's false-positive class, mirrored).

Conversely, the highest-confidence true positives share a signature: unexported/private
symbol + zero references outside its own declaration + no string occurrence of its name
anywhere in the repo + not matching any framework naming convention.

---

## Prior art: LLM-assisted detection & verification-pass patterns

- **Datadog engineering blog, "Using LLMs to filter out false positives"** — production
  use of an LLM as a post-filter on static-analysis findings; the LLM reasons about
  context static tools can't (data flow across functions, validation in callers, findings
  in dead/test/deprecated paths).
- **LLM4PFA** (arXiv 2506.10322) — LLM-agent path-feasibility analysis over static bug
  reports; filters **72–96% of false positives**, beating baselines by 41–106%.
- **QASecClaw** (arXiv 2605.01885) — multi-agent pattern: high-recall SAST engine first,
  coding-specialized LLM as *secondary verifier* of each finding. Architecturally the
  same "tool-first, model-verified" shape this skill proposes.
- **KNighter** (arXiv 2503.09002) — LLM-synthesized static checkers with a built-in
  *triage agent* that identifies false alarms and feeds iterative checker refinement.
- **IRIS, LLift, ZeroFalse** — academic line of work on LLM contextual reasoning /
  constraint checking to suppress static-analysis FPs.
- **Non-LLM precedent for the workflow itself:** Google Sensenmann (automated detection
  - generated deletion CLs + human gate) and Uber Piranha (automated stale-branch removal).
- **Existing Claude-skill prior art (small):** community skills wrapping single tools
  exist — a `vulture-dead-code` skill (laurigates/claude-plugins) and a `cargo-machete`
  skill on skill marketplaces. They are thin single-tool wrappers; none found that
  orchestrate multi-ecosystem detection with a model adjudication pass.

**Design implications for the skill's verification pass**

1. Run the detector; parse JSON/SARIF (or vulture's line format) into findings.
2. For each finding, gather *evidence*, not vibes: repo-wide grep for the symbol name
   (including strings, templates, config, other languages), framework-convention check,
   export/visibility check, git-blame recency, cfg/feature-gate check.
3. Verdict per finding: **dead** (delete), **alive** (add to the tool's native suppression
   mechanism — knip ignore/`@public`, vulture whitelist, `[UsedImplicitly]`,
   `#[expect(dead_code)]`, `# shellcheck disable` — so the next run is cleaner), or
   **uncertain** (surface to human; optionally propose a tombstone/coverage probe).
4. Require the model to cite the evidence for "alive" verdicts — the literature's main
   caution is LLMs accepting plausible-looking usage; the Datadog/QASecClaw pattern works
   because the LLM adjudicates *with retrieved context*, not from the finding alone.

---

## Key sources

- https://knip.dev/explanations/comparison-and-migration ; https://knip.dev/typescript/unused-exports ; https://effectivetypescript.com/2023/07/29/knip/
- https://github.com/nadeesha/ts-prune ; https://github.com/depcheck/depcheck
- https://github.com/jendrikseipp/vulture ; https://pypi.org/project/vulture/
- https://docs.astral.sh/ruff/linter/ ; https://docs.astral.sh/ruff/rules/unused-import/
- https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0051 ; .../ide0052
- https://www.jetbrains.com/help/resharper/InspectCode.html ; https://blog.jetbrains.com/dotnet/2024/04/09/resharper-2024-1/
- https://github.com/dotnet/roslyn/issues/78934 ; /76857 ; /30965
- https://github.com/koalaman/shellcheck/wiki/SC2034 ; shellcheck issues #718, #2461, #3379
- https://pkg.go.dev/golang.org/x/tools/cmd/deadcode ; https://go.dev/blog/deadcode ; https://github.com/golang/go/issues/64945
- https://github.com/bnjbvr/cargo-machete ; https://lib.rs/crates/cargo-udeps ; https://crates.io/crates/cargo-shear ; https://rustprojectprimer.com/checks/unused.html
- https://www.datadoghq.com/blog/using-llms-to-filter-out-false-positives/
- https://arxiv.org/pdf/2506.10322 (LLM4PFA) ; https://arxiv.org/html/2605.01885v1 (QASecClaw) ; https://arxiv.org/html/2503.09002v2 (KNighter)
