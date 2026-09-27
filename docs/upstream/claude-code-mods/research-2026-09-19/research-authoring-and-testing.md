# Authoring and testing a mod

Self-contained. Pin: 2026-09-19, Claude Code 2.1.278, `mods/` at `92ec78f2`.
Basis labels: `OBSERVED` / `SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` /
`INFERRED`.

Everything here was exercised on this machine unless marked otherwise.

## File layout

```
<plugin>/
  .claude-plugin/plugin.json      name, version, description, author
                                  + "types": "./types/index.d.ts"  (if it provides a noun)
                                  + "userConfig": { … }            (if it takes options)
  hooks/hooks.json                { "description": "…", "modules": ["./register.ts"] }
  hooks/register.ts               export function register(on, options) { … }
  hooks/index.ts                  a barrel; NOT an entry point, never referenced by hooks.json
  types/index.d.ts                the noun contract, if any
  tests/register.test.ts          beside hooks/register.ts
  tests/fixtures/                 one export per file, for what several tests share
```

`SOURCE` · HIGH · `mods/README.md:L15-18, L34-37`;
`repo-primary/RESEARCH-mod-definition.md`. The tree bears it out: 31 test files
at `92ec78f2`, mirroring the `hooks/` layout
(`diff/tests/git/probes/branch-base-of.test.ts` beside
`diff/hooks/git/probes/branch-base-of.ts`).

`mods/tsconfig.json`, complete: `target/lib` es2023, `types: []`, `module`
esnext, `moduleResolution` bundler, `strict`, `noUncheckedIndexedAccess`,
`noEmit`, `skipLibCheck`, `jsx: "react"`, `jsxFactory: "h"`,
`jsxFragmentFactory: "Fragment"`, `include: ["types", "*/types/**/*.d.ts",
"*/hooks", "*/tests"]`. The single-plugin variant the `.d.ts` recommends is
identical except `"include": [".claude/types", "hooks", "tests"]`. `lib` names no
DOM deliberately: *"the environment has none, and its `Text` would shadow the
element."* `SOURCE` · HIGH.

Minimum toolchain: **TypeScript 5.4+**. `SOURCE` · HIGH · `.d.ts:L1-10`.

## `/plugin-types`

The `.d.ts` is generated, not hand-written. Its header names the version that
wrote it (`// Written by Claude Code 2.1.277.`) and says: *"Written by
`/plugin-types`; regenerate with that command after an update rather than
editing."* `SOURCE` · HIGH.

Four artifact families under `.claude/types/`:

| File | Contents |
|---|---|
| `claude-code.d.ts` | the engine API (12,990 lines) |
| `claude-code-mcp.d.ts` | MCP surface |
| `claude-code-plugins.d.ts` | index of the enabled plugins' type contracts |
| `claude-code-plugins/<plugin>.d.ts` | one per plugin naming a `"types"` contract |

`SOURCE` · HIGH · `.d.ts:L74-81`, with the generator and its filename-collision
logic present in the 2.1.278 binary. `BINARY` · HIGH.

`/plugin-types` is a **slash command**, not a `claude plugin` subcommand:
`claude plugin-types` falls through to an ordinary agent prompt, and
`claude plugin --help` lists no `types` subcommand. `OBSERVED` · MEDIUM ·
`official-docs-changelog/RESEARCH-enablement.md` EN-5 (note: that probe tests a
CLI subcommand while the README describes a slash command, so the MEDIUM is not
fully earned by its cited evidence — `official-docs-changelog/VERIFICATION.md`
row 7). **Not run end to end in any lane.**

Staff: *"If anyone decides to enable the experimental flag, `/plugin-types` will
make available a full listing of the available `$` affordances."* `STAFF` · HIGH.

Known defect: `/plugin-types` omitted op events `session.authorize` and
`flag.value` that the hooks load line lists (issue #92469, 2.1.263), and
`agent.offer`'s doc comment says `offered` while `AgentOfferResult` declares
`isOffered` (#92440). Generated types are already incomplete and drift from their
own comments. `COMMUNITY` · HIGH.

## `claude plugin validate <dir>`

Listed **unconditionally** in `claude plugin --help` on 2.1.278. `OBSERVED` · HIGH.

For a hooks module it does more than manifest linting: it *"reads a plugin's
manifest and its hooks module's source the way the engine will and reports what
the module hooks and calls and everything the engine would refuse, before any
session loads it."* The lists it prints are exactly `PluginRegisterUses`'s
`events`, `calls` and `env`. `SOURCE` · HIGH.

Staff caveat: *"`validate` only syntactically checks your plugin"* — it does not
prove that a `$` noun the plugin calls is provided by anything upstream.
`STAFF` · HIGH.

## `claude plugin test [dir]`

```
Usage: claude plugin test [dir]

Runs a function-hooks plugin's tests: every *.test.ts and *.test.tsx under
dir (default: the current folder), each file in a child of this binary, in
an environment like the one its hooks run in. A test file imports its kit
from 'claude-code/testing'. Exits 1 when a test fails.
```

`OBSERVED` · HIGH. It is **not registered** without the gate
(`error: unknown command 'test'`) and **stays hidden from `claude plugin --help`
even with the flag set**. `OBSERVED` · HIGH.

There is also a `--file` form the binary intercepts before the argument parser,
printing a `REPORT_MARK` payload when hooks modules are off — `INFERRED` as a
machine-readable CI path; format not determined. `BINARY` · MEDIUM.
The runner's environment allowlist (`PATH`, `HOME`, `CLAUDE_CONFIG_DIR`,
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`) forces
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS: "1"`, so function hooks are always on inside
the test runner. `BINARY` · MEDIUM · `surfaces-desktop/VERIFICATION.md`.

## `--plugin-dir` — running one from source

`claude --plugin-dir mods/diff`. `SOURCE` · HIGH. Long-established and
well-covered in the CHANGELOG (12 entries, none about hooks modules). Relevant
behaviors: accepts a **folder of plugins** (children added or removed while
running are picked up); accepts `.zip`; a local dev copy overrides an installed
marketplace plugin of the same name unless force-enabled by managed settings; one
path per flag. `SOURCE` · HIGH.

Sets `provenance` to `<name>@inline` (`.d.ts:L6167`), and a `--plugin-dir` plugin
lands in the **`user` tier**, so `next.to` is refused. `SOURCE` · HIGH.

## The `claude-code/testing` kit

`declare module 'claude-code/testing'` at `.d.ts:L11257`. Exports: `describe`,
`test`, `expect`, `mock`, `tier`. `SOURCE` · HIGH.

### The seating model — the part worth copying

> A test gets the engine's own `$` and a plugin's `on`. Each call on `$` is one
> the engine makes, through every hook of the mod loaded as it ships. The hooks
> the test registers with `on` sit beneath the mod, where the rest of the world
> would be, and **nothing is beneath them: a call they leave unanswered throws,
> naming its event.**

`SOURCE` · HIGH · `mods/README.md:L28-32`. The test **is the world**. An
unstubbed call is a loud failure, not a silent undefined. Plugins load at the
test's first call on `$`, so a test registers its hooks before it.

### `tier`, `mock`, inline plugins

- `tier('builtin')` is a **file-level statement**, called once before `describe`.
  Legal values: `prepend`, `user` (the default when unsaid), `append`, `builtin`
  — recovered by feeding an invalid one:
  `tier("nonsense"): the tier is 'prepend', 'user', 'append' or 'builtin'`.
  `OBSERVED` · HIGH · `official-docs-changelog/VERIFICATION.md` row 5.
- `mock` covers **three nouns only**: `mock.clock`, `mock.store`, `mock.env`.
  `$.fs`, `$.process`, `$.http`, `$.settings`, `$.session` and the rest are
  stubbed by hand with `on(...)`. `SOURCE` · HIGH · `.d.ts:L11702`.
- `mock.clock` answers from an in-memory clock that moves only when the test
  moves it; a held wait *"past a hook's budget (ten seconds of real time) is let
  go, as a hook that overran."* `await clock.settle()` lets fire-and-forget work
  land before asserting. `SOURCE` · HIGH.
- `mock.env` covers the static case; a **varying** environment inside one test is
  a hand-written `on('env.get', …)`. `SOURCE` · HIGH ·
  `mods/telemetry/tests/register.test.ts:L79-83`.
- `TestOptions.plugins` seats **inline plugins**, written literally in the test
  file with their own `tier` — how a noun provider *or* a fake consumer is
  seated. `telemetry`'s tests invert the usual shape: seat a fake consumer, drive
  it with `$.command.run`. `SOURCE` · HIGH.
- Matchers observed in use: `toEqual`, `toMatchObject`, `toBe`, `toContain`,
  `toEndWith`, `toHaveLength`, `toBeDefined`, plus a **message as `expect`'s
  second argument**. `SOURCE` · HIGH.
- `$.ui.mount` draws a component through the plugin on a named surface; one body
  can run over several surfaces. It exercises the mod, *"never a surface's
  paint"*. `SOURCE` · HIGH.

### Two limits of the kit, both observed

1. **`$.tool.call` does not dispatch `classic.PreToolUse` inside the kit.** The
   classic chain is driven by core, which the kit replaces. Test classic
   behavior live instead. `OBSERVED` · HIGH ·
   `architecture-pdf/DENY-AND-ERROR-SEMANTICS.md` (d).
2. **The 10 s hook budget is not observed inside the kit.** A probe spinning 13 s
   returned its own value and `.catch` never fired; the two failures were the
   kit's own 5,000 ms per-test timeout. The probe used `await Promise.resolve()`,
   which never drains the microtask queue, so it cannot distinguish "the kit does
   not enforce the budget" from "the enforcer was starved". **A null result, not
   a finding.** The budget *is* enforced live. `OBSERVED` · HIGH · same file (e).

## Patterns from the shipped mods

### `diff` — the `Host` indirection pattern

The largest module does **not** thread `$` through its internals. At
`session.start` it binds one `Host` object of thin lambdas (20 members) and
closes over it; everything afterwards uses `host`, never `$`.
`SOURCE` · HIGH · `mods/diff/hooks/register.ts:L623-655`. Three consequences:

- **`$` is stable across dispatches.** Capturing it in one hook and using it from
  another is the reference implementation's own pattern.
- The `$`-call surface stays **literal and greppable**, which the host's pre-load
  source scan requires.
- The module's whole interior is testable against a plain object.

Two more facts `diff` settles: `$.command.register` **can throw** on a name a
built-in already holds, and collision is a normal condition to stand down from,
not an exception; `$.ui.resolve(e)` is **awaited** and destructured.
`SOURCE` · HIGH.

### `agents-md` — options and migration

- Conditional registration: `register` returns early, so which hooks exist
  depends on the option. `SOURCE` · HIGH
- Renaming a published option without breaking stored settings: read the legacy
  key from the open `PluginOptions` record, map old values to new, tell the
  person once with `$.ui.log`, mark the removal with `COMPAT_BREAK(<id>)`.
  `SOURCE` · HIGH
- The absent-noun case is a **first-class test**: one test with a telemetry
  provider seated and one without, asserting the second *"goes on untouched"*.
  `SOURCE` · HIGH

### Event and result shapes confirmed against real code

`SOURCE` · HIGH · `repo-primary/RESEARCH-event-catalog.md`

- `prompt.context` carries **two** parallel collections, `blocks[]` and
  `instructionFiles[]` (`kind` ∈ `managed | user | project | local | memory`, in
  load order). A hook answers with the file list changed and **the engine
  re-renders `blocks.claudeMd` from the answered files** — a hook adds *files*,
  never prose.
- `tool.call`'s result carries `context`, an array a hook may append to, which is
  how a hook rides extra material down on a tool result.
- `prompt.submit`'s `e.context` is a `string[]` a hook extends; the result
  carries `.drop`.
- `agent.spawn`'s result carries `result.agentId`, so a hook can correlate a new
  loop with its parent after `next` resolves.
- `ui.close` is **deniable** by the pane's own plugin; `e.origin.kind ===
  'person'` separates a human close from a programmatic one.
- `$.clock.after` / `every` return a `Timer` with `.cancel()`.

## Windows notes

- **The toolchain works.** A hand-written four-file mod passes `claude plugin
  test` green on Windows 11 / 2.1.278 in 0.27 s; reproduced independently on a
  different mod at 0.30 s. No shell, no quoting, no path translation involved.
  `OBSERVED` · HIGH · `community-falsification/VERIFICATION.md` row 10.
- The one substantial independent migration report is itself from a Windows
  author. `COMMUNITY` · HIGH
- **Not defect-free.** Issue #92533 (below) carries an independent **Windows**
  reproduction at 2.1.272 as its sole comment. `COMMUNITY` · HIGH
- claudefa.st argues Windows gains most from mods because there is *"no shell in
  the execution path"*, citing ~90 ms process-spawn latency on Windows against
  2–14 ms on macOS for classic bash hooks. **Tier 2, unreplicated.**
  `COMMUNITY` · LOW
- The Windows bugs that do exist in the tracker (#94313 `/diff` syntax
  highlighting, #92771 Shift+Enter) touch the `diff` mod's surface but are
  ordinary terminal bugs, not hooks-module failures. `COMMUNITY` · HIGH

## Undocumented sharp edges reported by the first non-trivial implementer

An `h` local-variable rule in surface modules; `Client` module paths that must be
string literals; a render band about half the terminal height redrawing about ten
times a second. His own summary: *"All of that is workable, just undocumented
right now."* `COMMUNITY` · HIGH · `x-threads/RESEARCH-community-claims.md`.

## One first-party resource not read by any lane

2.1.278 bundles a `plugin-authoring` skill: *"Write or debug a Claude Code plugin
made of function hooks … Load it before writing or changing such a plugin; it
says where the exact types come from, how to run a plugin under development, and
where the engine reports what it refused."* `BINARY` · HIGH. **Its body was never
extracted.** This is the cheapest unexploited first-party source in the corpus.
