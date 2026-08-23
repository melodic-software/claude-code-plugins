# LSP viability for `code-tidying:audit-dead-code`

> **Graduated** from the `dead-code-detection-skill` contract slice when
> `/code-tidying:audit-dead-code` shipped. Its decision-relevant outcomes, now reflected in the
> shipped skill: the `LSP` tool is model-callable only and has no batch mode, so it is an optional
> per-candidate assist inside the bounded adjudication pass and never a lane; `gopls check
> -severity=hint` detects dead Go code **without building**, which is why Go ships as a lane;
> `DiagnosticTag.Unnecessary` and pyright are rejected; Rust and .NET stay excluded.
>
> **Status:** research, 2026-08-23. Answers the priority question raised against `PLAN.md` revision 4:
> *can Language Server Protocol servers supply dead-code detection, or at minimum semantic
> "find all references", as a cross-language mechanism that replaces or augments the per-language
> detectors and the `grep -w -F` lane?*
>
> Every claim below is either a verbatim quote from official documentation (cited) or a measurement
> taken in this container (marked **MEASURED**). Nothing here is from training memory.

---

## Verdict, in one paragraph

**LSP is reachable from a skill, but not usefully.** Claude Code does expose a first-class,
model-callable `LSP` tool with a `findReferences` operation, and the "zero non-definition
references" algorithm genuinely works over it — measured. But the tool is *per-symbol, per-call, and
model-mediated*: each query costs one model turn, there is no batch mode, no script can reach it, and
it is inactive unless the consumer has separately installed a code-intelligence plugin **and** its
binary. That makes it unusable as a repository-wide scanner. **The one genuinely new result is
unrelated to the tool: `gopls check -severity=hint` is a CLI batch dead-code detector for Go that
neither builds nor executes project code** — measured — which directly contradicts the constraint
that excluded Go from the plan. Rust and .NET remain excluded. Recommendation: keep the three-lane
design, add Go via `gopls check` if the scope is worth it, and record the LSP tool as an
*adjudication-time* affordance for individual uncertain candidates, never as a lane.

---

## 1. Can the algorithm be built from LSP primitives?

Yes — the primitives are all specified and all present.

Per the [LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/):

- `textDocument/references` takes a `ReferenceContext` — "*A context value including a property to
  control whether declarations should be included in the result*" — via `includeDeclaration`.
- `textDocument/documentSymbol` enumerates symbols in one file; `workspace/symbol` searches
  symbols across the workspace.
- `textDocument/prepareCallHierarchy` + `callHierarchy/incomingCalls` trace callers.

**MEASURED** — a minimal JSON-RPC client (`scratchpad/lspprobe.py`) driving `pyright-langserver
--stdio` over a four-file Python fixture:

| Probe | Result |
|---|---|
| `references(includeDeclaration=true)` on a **used** function | **2** |
| `references(includeDeclaration=true)` on a **dead** function | **1** |
| `references` on `public_dead_fn`, consumed by a file the client **never opened** | **3** |

So the rule is `resultCount == 1 → no non-definition reference → dead candidate`, and it resolves
**cross-file from the on-disk index** without the consuming file being opened. The algorithm is real.

Two documented limits that survive into any implementation:

1. **`includeDeclaration` shifts the threshold, it does not remove the problem.** With it `true`,
   dead is `1`, not `0`. Servers differ on whether a declaration yields one entry or several
   (a `def` line plus the name token), so the threshold is per-server and must be calibrated, not assumed.
2. **An import counts as a reference.** `public_dead_fn` scored 3: declaration, the `from mod2
   import public_dead_fn` line, and the call. A symbol that is only re-exported and never called
   scores >1 and reads as alive. This is the same false-alive class the plan already accepts for the
   grep lane — LSP narrows it, it does not close it.

---

## 2 + 3. Per-server capability table

| Server | `references` | `workspace/symbol` | Unused-code diagnostics | `DiagnosticTag.Unnecessary` | Needs build / restore? | CLI batch mode |
|---|---|---|---|---|---|---|
| **gopls** | yes | yes ("*searches an index of all the symbols in the workspace*" — [go.dev](https://go.dev/gopls/features/navigation)) | **yes — `unusedfunc`**: unexported funcs, methods, types, vars, consts never referenced. Also `unusedimport` (on), `unusedparams`/`unusedvariable`/`unusedwrite`/`unusedresult` (off) — [go.dev/gopls/analyzers](https://go.dev/gopls/analyzers) | emitted as **Hint** severity (**MEASURED**) | **No build, no execution.** "*Gopls does not run the actual compiler*… runs `go list` … then processes those packages in a similar manner to the compiler front-end*" — [go.dev](https://go.dev/gopls/features/diagnostics). Needs a **resolvable module graph** (populated module cache) | **YES — `gopls check -severity=hint <files…>`** (**MEASURED**) |
| **pyright / pyright-langserver** | yes (**MEASURED**, cross-file) | yes | **only private, file-local symbols** — `reportUnusedImport`/`Variable`/`Function`/`Class`; the latter two fire **only on `_`-prefixed names** (**MEASURED**) | **yes, `tags:[1]`, severity 4** on the LSP wire with default config (**MEASURED**) | Needs installed deps for import resolution; unresolved imports degrade the analysis, not block it | `pyright --outputjson` — but see the trap below |
| **typescript-language-server / tsserver** | yes | yes | `noUnusedLocals`/`noUnusedParameters` only — file-local, never unused *exports* (TS 6133 etc.) | yes — tsserver marks unused-variable suggestions with `Unnecessary` ([TS #23288](https://github.com/microsoft/TypeScript/issues/23288)) | Needs `node_modules` resolvable; diagnostics are computed **per open document** ([tsls #253](https://github.com/typescript-language-server/typescript-language-server/issues/253)) | no |
| **rust-analyzer** | yes | yes | Dead-code (`dead_code` lint) comes **from `cargo check`**, not from rust-analyzer's own analysis — "*most errors and warnings provided by rust-analyzer come from the `cargo check` integration*" ([book](https://rust-analyzer.github.io/book/diagnostics.html)) | yes, for cargo-sourced unused lints | **YES — runs `cargo check`, which compiles `build.rs` and proc macros.** Executes project code | `rust-analyzer diagnostics <path>` and `analysis-stats` exist ([DeepWiki](https://deepwiki.com/rust-lang/rust-analyzer/7.2-command-line-interface)) but inherit the same requirement |
| **csharp-ls / Roslyn (`Microsoft.CodeAnalysis.LanguageServer`)** | yes | yes | Roslyn IDE analyzers (IDE0051 unused private member, etc.) | yes | **YES — restore required.** The Roslyn server "*sends a custom LSP notification indicating that the project needs to be restored*"; without it diagnostics for external libraries do not work ([lsp-mode](https://emacs-lsp.github.io/lsp-mode/page/lsp-csharp-roslyn/)) | no |
| **clangd** | yes | yes | `-Wunused-variable` etc. from the clang frontend — file-local only | yes | Needs `compile_commands.json`; "*should exist in some parent directory and should have a valid command*" ([clangd FAQ](https://clangd.llvm.org/faq)) — i.e. a configured build | no |
| **jdtls** | yes | yes | Eclipse JDT unused-warnings — file/type-local | yes | Needs a resolved classpath (Maven/Gradle import, which runs the build tool) | no |
| **bash-language-server** | yes — "*Find references*", "*Workspace symbols*" listed ([repo](https://github.com/bash-lsp/bash-language-server)) | yes | "*Simple diagnostics reporting*" — shellcheck passthrough, **no unused-symbol analysis** | no | none | no |

### The `DiagnosticTag.Unnecessary` question, settled

The tag is real and standard — value 1, "*Unused or unnecessary code. Clients are allowed to render
diagnostics with this tag faded out*" — and servers do emit it. **MEASURED**: pyright emits
`severity=4, tags=[1]` on the wire with an empty `pyrightconfig.json`.

But it is **not a viable cross-language dead-code signal**, for three independent reasons:

1. **Scope.** Every server that emits it emits it for *file-local, private, or intra-function*
   unused code — unused imports, unused locals, unexported/underscore-private members. That is the
   category ruff/eslint/shellcheck already cover and that the plan explicitly is not chasing. The
   cross-file unreferenced-export category — the whole point of this skill — is precisely what no
   server tags.
2. **Delivery model.** Diagnostics are *pushed* per open document. Getting them repo-wide means
   opening every file in the workspace and waiting for each publish.
3. **Claude Code drops the tag.** See §5.

The `unusedfunc` analyzer in gopls is the exception that proves the rule: it is *not* delivered as
`Unnecessary`-tagged noise, it is a genuine cross-file package-scope analyzer, and it is the only
one in the table.

---

## 4. The build/restore question — per server

This is the constraint that excluded Go, Rust, and .NET in `PLAN.md`. The answers are not uniform.

**gopls — passes.** It does not invoke the compiler; it runs `go list` for metadata and then its own
type-checker. Go has no `build.rs` equivalent, and `go generate` is not run. What it needs is a
**resolvable module graph** — the same class of precondition as `node_modules` for knip.

**MEASURED**, trap fixture `scratchpad/gotrap/`, gopls v0.23.0, ~2.1 s cold:

```
gopls check -severity=hint main.go
main.go:7:6-22:  function "deadUnexportedFn" is unused
main.go:11:6-14: type "deadType" is unused
main.go:15:5-12: var "deadVar" is unused
main.go:17:7-16: const "deadConst" is unused
```

`DeadExportedFn` and `DeadExportedType` were correctly **not** reported — `unusedfunc`
"*excludes exported functions to avoid false positives in library code*". Conservative by design;
low recall, high precision. That is the same character the plan assigns to the grep lane.

**MEASURED — gopls degradation modes.** Both are the knip shape, and both must be handled:

| State | stdout | exit | stderr |
|---|---|---|---|
| Unresolved dependency (`GOPROXY=off`, dep not in cache) | `could not import …` **and the unused hints are suppressed** | **0** | empty |
| Workspace load failure (toolchain mismatch) | **empty** | **0** | `initial workspace load failed: packages.Load error: …` |

So: exit code is useless as run health (identical to the knip finding); the degraded run produces
**false negatives, not false positives** (unlike knip, which manufactures false "unused files"); and
one degradation signal is on stdout, mixed into the finding stream, while the other is on stderr.
Both need parsing. `gopls check` also takes **file arguments only** — a directory or `./...` errors
with `getFile: … is a directory` — so the caller supplies a glob.

**rust-analyzer — fails, unchanged.** Its dead-code signal comes from `cargo check`, which compiles
build scripts and proc macros. The plan's measurement (`cargo check` runs `build.rs`) stands.

**Roslyn/.NET — fails, unchanged.** Requires a restored solution and the server explicitly signals
"project needs to be restored" before diagnostics are trustworthy. A restore is a network fetch,
which the plan forbids.

**clangd / jdtls — fail.** `compile_commands.json` is a build artifact; a jdtls classpath comes from
running Maven/Gradle import.

**pyright — passes on the build test, fails on the usefulness test.** It needs no build, but see §6:
its CLI reports nothing that vulture does not report better.

**Incidental corroboration of an existing plan constraint.** `command -v rust-analyzer` succeeds in
this container and returns `/root/.cargo/bin/rust-analyzer`, but **invoking it fails**:
`error: Unknown binary 'rust-analyzer' in official toolchain`. It is a rustup shim with no server
behind it. This is a direct second instance of the plan's rule *"presence is proven by invocation,
never by `command -v`"*, in a tool family the plan had not tested.

---

## 5. Claude Code's LSP support — is it reachable from a skill?

### It exists, it is a real model tool, and it is documented

Per the [Tools reference](https://code.claude.com/docs/en/tools-reference):

> | `LSP` | Code intelligence via language servers: jump to definitions, find references, report type errors and warnings. | **Permission required: No** |

And the *LSP tool behavior* section, verbatim:

> The LSP tool gives Claude code intelligence from a running language server. After each file edit,
> it automatically reports type errors and warnings so Claude can fix issues without a separate build
> step. Claude can also call it directly to navigate code […]
>
> Claude Code keeps the tool inactive until you install a
> [code intelligence plugin](https://code.claude.com/docs/en/discover-plugins#code-intelligence) for
> your language. Claude Code takes the language server's configuration from the plugin, and you
> install the server binary yourself.
>
> Claude Code keeps the tool active for the rest of a session once it has had a language server
> available in that session.

Tool names in that reference are "*the exact strings you use in permission rules, subagent tool
lists, and hook matchers*" — so `LSP` is nameable in a skill's `allowed-tools`.

**So the answer to the load-bearing question is: yes, a skill can drive the LSP tool — by
instructing the model to call it. No, a skill's bash script cannot.**

### What the tool actually accepts and returns (verified against the shipped binary)

Read from `node_modules/@anthropic-ai/claude-code-linux-x64/claude` (v2.x, this repo's pinned copy).
The tool's own description string:

> Interact with Language Server Protocol (LSP) servers to get code intelligence features.
> Supported operations: `goToDefinition`, `findReferences`, `hover`, `documentSymbol`,
> `workspaceSymbol`, `goToImplementation`, `prepareCallHierarchy`, `incomingCalls`, `outgoingCalls`.

| Property | Value (from the binary) | Consequence for this skill |
|---|---|---|
| Input schema | `operation`, `filePath`, `line`, `character` — **all required**; `query` optional | Even `workspaceSymbol` demands a `filePath`/`line`/`character`. A `findReferences` call needs the symbol's **exact 1-based position**, so every query must be preceded by a position lookup |
| `includeDeclaration` | **hard-coded `true`**, not exposed: `context:{includeDeclaration:!0}` | The dead threshold is `resultCount == 1`, and it cannot be changed to `0` |
| Output schema | includes `resultCount` and `fileCount` | Good news — the count is returned directly, no parsing of a reference list |
| `isReadOnly` | `true` | Safe for a report-only skill |
| `isConcurrencySafe` | `true` | Parallel calls are permitted |
| `shouldDefer` | `true` | Not in the base tool list; the model must `ToolSearch` for it first |
| `isEnabled` | `isConnected()` on the LSP server manager | Inert unless a server is actually connected |
| `maxResultSizeChars` | `100_000` | Large result sets truncate |
| File size limit | 10 MB — "*File too large for LSP analysis*" | Large generated files are skipped |
| Diagnostics operation | **none** | There is no way to ask the tool for diagnostics |

### Diagnostics are a side channel, and the tag is stripped

The `.lsp.json` `diagnostics` field (default `true`) controls "*whether to push diagnostics into
Claude's context after edits*" ([plugins reference](https://code.claude.com/docs/en/plugins-reference#lsp-servers)).
In the binary the handler is labelled `[PASSIVE DIAGNOSTICS]` and fires on **any**
`textDocument/publishDiagnostics` the server sends, not only for edited files — so opening a file via
the `LSP` tool can push diagnostics in asynchronously. But:

- The normalizer keeps only `{message, severity, range, source, code}` — **`tags` is discarded.**
  `DiagnosticTag.Unnecessary` never reaches the model as a tag.
- The rendered block is capped at 4000 characters and then `…[truncated]`.
- Delivery is deduplicated, asynchronous, and unaddressable — it arrives in context, not as a
  tool result a skill can iterate over.

**Conclusion: `DiagnosticTag.Unnecessary` is unreachable from a Claude Code skill**, both because the
tool has no diagnostics operation and because the passive path strips the tag.

### Local repo state

`grep -ri "lsp"` across `plugins/*/.claude-plugin/` and `docs/` finds **no `.lsp.json` and no
`lspServers` declaration anywhere in this repository.** The only references are infrastructural and
already correct:

- `scripts/validate-plugin-contracts.mjs:271` — `lspServers: [".lsp.json"]`
- `plugins/claude-ops/skills/inventory/scripts/inventory.py:88` — inventories `lsp-servers`
- `docs/OFFICIAL-DOCS.md:44` — tracks the LSP servers doc page
- `docs/PLUGIN-PHILOSOPHY.md:180` — "*Adopt on need. Consumer must have the language-server binary;
  declare the prerequisite per the failure-behavior rules.*"

That last line is the governing house policy and it points the same way as this research.

**MEASURED**: the `LSP` tool is **absent from this session's tool list**, exactly as
`isEnabled(){return isConnected()}` predicts — no code-intelligence plugin is installed here.

---

## 6. Practicality

### Cost of the model-mediated path

The `LSP` tool has no batch mode. A repository sweep would be:

1. `documentSymbol` once per source file, to get every symbol's line/character.
2. `findReferences` once per symbol.

Each is a separate tool call, and **each tool call is a model turn**. A repository with a few
thousand symbols means a few thousand turns. Against this skill's actual budget — the plan already
caps *adjudication* at `--max <n>` with subagent fan-out precisely because model attention is the
scarce resource — a per-symbol scan is off by orders of magnitude. It is not a scanner.

The oft-quoted "LSP find-references is ~50 ms vs ~45 s for text search" figure measures the *server*,
not the round trip. The measured floor here is different and worse: 3.1 s for the **entire** grep
lane over 546 files and 177,793 lines (plan baseline), versus one model turn per symbol.

### Which servers have a CLI batch mode

| Server | CLI batch mode | Useful here? |
|---|---|---|
| **gopls** | `gopls check -severity=hint <files…>` | **Yes** — the only real win in this document |
| pyright | `pyright --outputjson` | No — see trap below |
| rust-analyzer | `rust-analyzer diagnostics <path>` | No — needs `cargo check` |
| tsserver / clangd / jdtls / csharp-ls / bash-language-server | none | — |

### Measured trap: pyright's CLI and its LSP disagree

**MEASURED**, same fixture, same default `pyrightconfig.json` (`{}`):

- `pyright --outputjson .` → `errorCount 0, warningCount 0` — **nothing at all**.
- The LSP session → two `severity=4, tags=[1]` diagnostics for the same file.

The CLI silently drops Hint-severity diagnostics. So the CLI's `--outputjson` **cannot** see the
`Unnecessary` signal at all, and to make it report anything the consumer's `pyrightconfig.json` must
opt in with `reportUnusedImport`/`reportUnusedVariable`/etc. — repo-controlled configuration that the
skill must not edit.

And even fully opted in, pyright is strictly worse than vulture for this skill's target.
**MEASURED**, with all four `reportUnused*` rules set to `warning`:

| Fixture symbol | pyright | vulture (plan baseline) |
|---|---|---|
| unused `import os` | reported | reported |
| unused local `x` | reported | reported |
| `_private_dead_fn` | reported | reported |
| `_PrivateDeadClass` | reported | reported |
| `dead_fn` (module-level, public) | **missed** | reported |
| `DeadClass` (public) | **missed** | reported |
| `dead_method` (method) | **missed** | reported |

pyright's unused-symbol checks are private-and-file-local by construction. **A pyright lane would
strictly reduce recall against the existing vulture lane.** Drop the idea.

---

## 7. Prior art

- **[microsoft/multilspy](https://github.com/microsoft/multilspy)** — a Python LSP *client library*
  ("*find the callers of a function or the instantiations of a class (`textDocument/references`)*"),
  supporting Python, Rust, Java, Go, JavaScript, C#, Ruby, Dart. This is the right shape for
  scripting LSP, and the closest thing to a ready-made engine for the algorithm in §1.
  **But it is a Python dependency the skill would have to install**, and it drives the same servers
  with the same build/restore preconditions. It moves the work, not the wall.
- **`lsp-devtools`** — an LSP debugging/inspection toolkit, not a query engine; no dead-code use.
- **LSP-based dead-code tooling in agent harnesses** exists as a pattern — several third-party
  Claude Code / Codex LSP bridges describe "*semantic reference counting with grep-based fallback
  when references are unresolvable*" and "*Orphan / Exported-Unused classification*" — which is
  independent convergence on the §1 algorithm and on the *hybrid* posture. Notably, none of them
  ship as a repo-wide scanner; they all serve per-symbol navigation.
- **No mature, general "LSP-based dead code detector"** turned up in searching. The mature tools in
  each ecosystem (knip, vulture, `golang.org/x/tools/cmd/deadcode`, `cargo-udeps`) all bypass LSP.

---

## Recommendation against `PLAN.md` revision 4

| Question | Answer |
|---|---|
| Does LSP replace the grep lane? | **No.** The tool is not scriptable, costs a model turn per symbol, and is inactive on any machine without a code-intelligence plugin + binary. The grep lane's 3.1 s / 546-file floor is not in danger. |
| Does LSP replace knip or vulture? | **No.** No server does cross-file unreferenced-export analysis except gopls's `unusedfunc` (Go only, unexported only). pyright would strictly lose recall vs vulture. |
| Does LSP reopen Go / Rust / .NET? | **Go: yes, and not via LSP-the-protocol — via `gopls check`, a CLI.** Rust and .NET: no, unchanged. |
| Is `DiagnosticTag.Unnecessary` usable? | **No.** Wrong scope (file-local/private), push-only delivery, and Claude Code strips `tags` from the diagnostics it injects. |
| Can a skill query an LSP server? | **Yes, via the model-callable `LSP` tool — but not from a script, and only when the consumer has installed a code-intelligence plugin and its binary.** |

**Proposed changes, smallest first:**

1. **Do not add an LSP lane.** Record this document as the closing evidence for that.
2. **Amend the `Out-of-scope` trigger for Go.** The plan says the trigger is "*a detector that
   neither builds nor executes project code*". `gopls check -severity=hint` **is** that detector, and
   the trigger has therefore fired for Go — but not for Rust or .NET. Either admit a Go lane with the
   measured degradation handling above (stdout `could not import` → DEGRADED; stderr `initial
   workspace load failed` → DEGRADED; exit code ignored; module-cache probed directly the way
   `node_modules` is), or restate the Go exclusion on the honest ground — *scope*, not *mechanism*.
   Leaving the current wording is the one option that is now factually wrong.
3. **Optionally, an adjudication-time affordance.** During the bounded `--max` adjudication pass the
   skill may already spend a model turn per candidate. A single `LSP` `findReferences` call there —
   `resultCount == 1` → `dead`, `> 1` → inspect — is affordable at that granularity and would
   materially sharpen the `$`/`-`/`.` false-alive class the plan documents. Guard it: it is
   opportunistic, so the skill must check the tool is available rather than assume it, cite it as
   evidence when it fires, and fall through to the existing grep evidence when it does not.
   This is an enhancement to adjudication, **not** a fourth lane.

---

## Reproduction

All fixtures and probes are in this session's scratchpad
(`/tmp/claude-0/…/scratchpad/`): `gotrap/` (Go trap fixture), `godep/` (unresolved-dependency
fixture), `pyt/` (Python trap fixture), `lspprobe.py` (minimal `pyright-langserver` JSON-RPC client),
`show.py` (pyright JSON formatter). gopls v0.23.0 was built into `scratchpad/gopath/bin`.
Container inventory at time of measurement: `pyright` 1.1.408 and `pyright-langserver` present;
`go` 1.24.7 present; `rust-analyzer` present **as a non-functional rustup shim only**;
`gopls`, `typescript-language-server`, `bash-language-server`, `clangd`, `jdtls`, `csharp-ls`
not installed.

## Sources

- [Claude Code — Tools reference](https://code.claude.com/docs/en/tools-reference)
- [Claude Code — Plugins reference, LSP servers](https://code.claude.com/docs/en/plugins-reference#lsp-servers)
- [Claude Code — Discover plugins, Code intelligence](https://code.claude.com/docs/en/discover-plugins#code-intelligence)
- [Claude Code — Create plugins, Add LSP servers to your plugin](https://code.claude.com/docs/en/plugins)
- [LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
- [gopls — Diagnostics](https://go.dev/gopls/features/diagnostics)
- [gopls — Navigation features](https://go.dev/gopls/features/navigation)
- [gopls — Analyzers](https://go.dev/gopls/analyzers)
- [gopls — `unusedfunc` package](https://pkg.go.dev/golang.org/x/tools/gopls/internal/analysis/unusedfunc)
- [rust-analyzer — Diagnostics](https://rust-analyzer.github.io/book/diagnostics.html)
- [rust-analyzer — Command Line Interface](https://deepwiki.com/rust-lang/rust-analyzer/7.2-command-line-interface)
- [lsp-mode — C# (csharp-roslyn)](https://emacs-lsp.github.io/lsp-mode/page/lsp-csharp-roslyn/)
- [clangd — FAQ](https://clangd.llvm.org/faq)
- [bash-language-server](https://github.com/bash-lsp/bash-language-server)
- [typescript-language-server #253 — Diagnostics across files within a project](https://github.com/typescript-language-server/typescript-language-server/issues/253)
- [TypeScript #23288 — mark TS Server unused variable suggestion diagnostics](https://github.com/microsoft/TypeScript/issues/23288)
- [microsoft/multilspy](https://github.com/microsoft/multilspy)
