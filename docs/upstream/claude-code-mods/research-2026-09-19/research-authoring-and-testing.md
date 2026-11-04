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
  hooks/register.ts               exports register(on, options), the entry point
  hooks/index.ts                  a barrel; NOT an entry point, never referenced by hooks.json
  types/index.d.ts                the noun contract, if any
  tests/register.test.ts          mirrors the module's path under hooks/
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
DOM deliberately: the runtime has no DOM, and the DOM's `Text` type would hide
the element of that name. `SOURCE` · HIGH.

Minimum toolchain: **TypeScript 5.4+**. `SOURCE` · HIGH · `.d.ts:L1-10`.

## `/plugin-types`

The `.d.ts` is generated, not hand-written. Its header names the version that
wrote it (2.1.277), credits `/plugin-types` as the generator, and tells readers
to rerun it whenever Claude Code updates instead of changing the file by hand.
`SOURCE` · HIGH.

Four artifact families under `.claude/types/`:

| File | Contents |
|---|---|
| `claude-code.d.ts` | the engine API (12,990 lines) |
| `claude-code-mcp.d.ts` | MCP surface |
| `claude-code-plugins.d.ts` | lists the type contracts of every enabled plugin |
| `claude-code-plugins/<plugin>.d.ts` | one per plugin naming a `"types"` contract |

`SOURCE` · HIGH · `.d.ts:L74-81`, with the generator and its filename-collision
logic present in the 2.1.278 binary. `BINARY` · HIGH.

`/plugin-types` is a **slash command**, not a `claude plugin` subcommand:
`claude plugin-types` falls through to an ordinary agent prompt, and
`claude plugin --help` lists no `types` subcommand. `OBSERVED` · MEDIUM ·
`official-docs-changelog/RESEARCH-enablement.md` EN-5 (note: that probe tests a
CLI subcommand while the README describes a slash command, so the MEDIUM is not
fully earned by its cited evidence; see `official-docs-changelog/VERIFICATION.md`
row 7). **Not run end to end in any lane.**

Staff: once someone turns the experimental flag on, `/plugin-types` lists every
`$` affordance there is. `STAFF` · HIGH.

Known defect: `/plugin-types` omitted op events `session.authorize` and
`flag.value` that the hooks load line lists (issue #92469, 2.1.263), and
`agent.offer`'s doc comment says `offered` while `AgentOfferResult` declares
`isOffered` (#92440). Generated types are already incomplete and drift from their
own comments. `COMMUNITY` · HIGH.

## `claude plugin validate <dir>`

Listed **unconditionally** in `claude plugin --help` on 2.1.278. `OBSERVED` · HIGH.

For a hooks module it does more than manifest linting: it parses the manifest
and the module's source as the engine would, then lists the module's hooks and
calls and every refusal the engine would raise, all before a session ever loads
the plugin. The lists it prints are exactly `PluginRegisterUses`'s
`events`, `calls` and `env`. `SOURCE` · HIGH.

Staff caveat: `validate` checks syntax and nothing more, so it does not
prove that a `$` noun the plugin calls is provided by anything upstream.
`STAFF` · HIGH.

## `claude plugin test [dir]`

Its help text, in our words: the command runs the `*.test.ts` and `*.test.tsx` files
of a plugin built on function hooks, under `[dir]` (the current folder by default),
each in a child process of the binary, inside an environment that mirrors the
hooks runtime. Test files import their kit from `claude-code/testing`, and the
command exits with status 1 when any test fails.

`OBSERVED` · HIGH. It is **not registered** without the gate
(`error: unknown command 'test'`) and **stays hidden from `claude plugin --help`
even with the flag set**. `OBSERVED` · HIGH.

There is also a `--file` form the binary intercepts before the argument parser,
printing a `REPORT_MARK` payload when hooks modules are off. It reads as a
machine-readable CI path (`INFERRED`); format not determined. `BINARY` · MEDIUM.
The runner's environment allowlist (`PATH`, `HOME`, `CLAUDE_CONFIG_DIR`,
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`) forces
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS: "1"`, so function hooks are always on inside
the test runner. `BINARY` · MEDIUM · `surfaces-desktop/VERIFICATION.md`.

## `--plugin-dir`: running one from source

`claude --plugin-dir mods/diff`. `SOURCE` · HIGH. Long-established and
well-covered in the CHANGELOG (12 entries, none about hooks modules). Relevant
behaviors: accepts a **folder of plugins** (it notices children that come or go
mid-run); accepts `.zip`; a local dev copy overrides an installed marketplace
plugin of the same name unless managed settings force that plugin on; one
path per flag. `SOURCE` · HIGH.

Sets `provenance` to `<name>@inline` (`.d.ts:L6167`), and a `--plugin-dir` plugin
lands in the **`user` tier**, so `next.to` is refused. `SOURCE` · HIGH.

## The `claude-code/testing` kit

`declare module 'claude-code/testing'` at `.d.ts:L11257`. Exports: `describe`,
`test`, `expect`, `mock`, `tier`. `SOURCE` · HIGH.

### The seating model: the part worth copying

In our words: a test receives the engine's real `$` and a plugin's `on`. Every
`$` call travels through each hook of the mod as shipped. Hooks the test
registers through `on` sit under the mod, standing in for everything else, and
**nothing sits under them: a call none of them answers throws an error that
names the event.**

`SOURCE` · HIGH · `mods/README.md:L28-32`. The test **is the world**. An
unstubbed call is a loud failure, not a silent undefined. Plugins load when the
test first calls `$`, so its hooks must be registered ahead of that call.

### `tier`, `mock`, inline plugins

- `tier('builtin')` is a **file-level statement**, called once before `describe`.
  Legal values: `prepend`, `user` (the default when unsaid), `append`, `builtin`
  (recovered by feeding an invalid one:
  `tier("nonsense"): the tier is 'prepend', 'user', 'append' or 'builtin'`).
  `OBSERVED` · HIGH · `official-docs-changelog/VERIFICATION.md` row 5.
- `mock` covers **three nouns only**: `mock.clock`, `mock.store`, `mock.env`.
  `$.fs`, `$.process`, `$.http`, `$.settings`, `$.session` and the rest are
  stubbed by hand with `on(...)`. `SOURCE` · HIGH · `.d.ts:L11702`.
  **Drifted since the pin:** the live docs list a fourth, `mock.session(on)`,
  which needs Claude Code v2.1.293 or later. Read the current list at
  [test: Stub what Claude Code would answer](https://code.claude.com/docs/en/plugins/mods/test#stub-what-claude-code-would-answer)
  (as of 2026-10-30; recheck when that section adds or drops a `mock` export).
- `mock.clock` answers from an in-memory clock that advances solely under the
  test's control; a wait held beyond the hook's ten-second real-time budget is
  released and counted as an overrun. `await clock.settle()` lets fire-and-forget work
  land before asserting. `SOURCE` · HIGH.
- `mock.env` covers the static case; a **varying** environment inside one test is
  a hand-written `on('env.get', …)`. `SOURCE` · HIGH ·
  `mods/telemetry/tests/register.test.ts:L79-83`.
- `TestOptions.plugins` seats **inline plugins**, written literally in the test
  file with their own `tier`, which is how a noun provider *or* a fake consumer is
  seated. `telemetry`'s tests invert the usual shape: seat a fake consumer, drive
  it with `$.command.run`. `SOURCE` · HIGH.
- Matchers observed in use: `toEqual`, `toMatchObject`, `toBe`, `toContain`,
  `toEndWith`, `toHaveLength`, `toBeDefined`, plus a **message as `expect`'s
  second argument**. `SOURCE` · HIGH.
- `$.ui.mount` renders a component via the plugin for a chosen surface; one test
  body can cover several surfaces. It tests the mod, not how a surface paints.
  `SOURCE` · HIGH.

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

### `diff`: the `Host` indirection pattern

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

### `agents-md`: options and migration

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
  re-renders `blocks.claudeMd` from the answered files**: a hook adds *files*,
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
- claudefa.st argues Windows gains most from mods because no shell sits between
  Claude Code and the hook, citing ~90 ms process-spawn latency on Windows against
  2–14 ms on macOS for classic bash hooks. **Tier 2, unreplicated.**
  `COMMUNITY` · LOW
- The Windows bugs that do exist in the tracker (#94313 `/diff` syntax
  highlighting, #92771 Shift+Enter) touch the `diff` mod's surface but are
  ordinary terminal bugs, not hooks-module failures. `COMMUNITY` · HIGH

## Undocumented sharp edges reported by the first non-trivial implementer

A rule about the local variable `h` in surface modules; `Client` module paths that
must be string literals; a render band about half the terminal height redrawing
roughly 10 times per second. His own summary: each one can be worked around, but none is
documented yet. `COMMUNITY` · HIGH · `x-threads/RESEARCH-community-claims.md`.

## One first-party resource not read by any lane

2.1.278 bundles a `plugin-authoring` skill. Its description, in our words: it is
for writing and debugging function-hook plugins, should be loaded before such a
plugin is written or changed, and covers the source of the exact types, running
a plugin during development, and finding the engine's refusals. `BINARY` · HIGH. **Its body was never
extracted.** This is the cheapest unexploited first-party source in the corpus.
