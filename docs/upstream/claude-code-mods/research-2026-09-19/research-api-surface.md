# The API surface

Self-contained. Pin: 2026-09-19, Claude Code 2.1.278, `mods/` at `92ec78f2`,
declarations written by 2.1.277. Basis labels: `OBSERVED` / `SOURCE` / `BINARY` /
`STAFF` / `COMMUNITY` / `INFERRED`.

**The full verbatim catalog — every event name, every noun member, in
declaration order, with file-and-line citations — is
`repo-primary/RESEARCH-event-catalog.md`.** This sidecar is the summary. A
fresh-context verifier scripted a set-diff of that catalog against the `.d.ts`
and found **0 invented and 0 missed** names, matching in declaration order
(`repo-primary/VERIFICATION.md`, checks 1.1–1.12).

## How the name space is assembled

```ts
export type EventOf = CoreEventOf & NounEventOf;              // :L3885
type CoreEventOf = EngineEventOf & ClassicEventOf & OpEventOf; // :L3017
export type EventName = keyof EventOf;                         // :L3875
```

`SOURCE` · HIGH.

## Counts

| Family | Count | Where | Basis |
|---|---|---|---|
| `EngineEventOf` — the fold points | **38** | `.d.ts:L3213` | `SOURCE` HIGH |
| `OpEventOf` — one per `$` method | **54** | `.d.ts:L5460` | `SOURCE` HIGH |
| **Statically named before any plugin noun** | **92** | 38 + 54 | `SOURCE` HIGH |
| `ClassicEventOf` — `classic.<HookEvent>` | **33** | derived from the 33-member `HookInput` union, `.d.ts:L4240` | `SOURCE` HIGH |
| `NounEventOf` | **0 until a plugin declares a noun** | `.d.ts:L5359` | `SOURCE` HIGH |
| `$` nouns on `CoreEngineInterface` | **19** | `.d.ts:L2016` | `SOURCE` HIGH |
| Noun members (depth-2) | **69** | scripted walk | `SOURCE` HIGH |
| Invalidatable events (`$.ui.invalidate`) | **7** | `.d.ts:L4618` | `SOURCE` HIGH |
| `RenderComponent` values | **15** | `.d.ts:L7291` | `SOURCE` HIGH |
| `RenderSurface` values | **4** | `.d.ts:L8233` | `SOURCE` HIGH |

The 19 nouns, in declaration order: `plugin, ui, model, audio, mcp, session,
turn, prompt, tool, command, config, agent, fs, store, clock, http, process,
settings, env`. `SOURCE` · HIGH.

Three engine events carry special machinery: `engine.create` (the noun fold,
`NextResult` is `EngineInterfaceBuilt`), `turn.step` (the only
`StreamingEventName`, an async generator), `ui.render` (the only
`RenderEventName`). `SOURCE` · HIGH.

Every op-event result is `ValueOrDeny<OpValueOf[N]>`; a `{ deny }` on an op
**rejects the caller's promise**. `SOURCE` · HIGH ·
`mods/telemetry/tests/register.test.ts:L343-351`.

`$.ui.ask` is the single asymmetry: declared at `.d.ts:L2128`, with **no**
`ui.ask` event anywhere. A scripted walk over all 69 members found no fourth
exception beyond `plugin.name` and `plugin.root`, which are data.
`SOURCE` · HIGH · `repo-primary/VERIFICATION.md` check 2.2.

## Pattern selection

```ts
export type Pattern = EventName | Glob | Negation;   // :L5995
```

One event (`tool.call`), a namespace (`classic.*`, `ui.*`), everything (`*`), or
everything-but (`!tool.*`). `Namespace<N>` recurses on dots, so multi-level
namespaces are selectable. `SOURCE` · HIGH · `.d.ts:L8317`, `:L5101`.

Staff: a single hook on `*` sees every event *"including every plugin's own calls
on `$`, so an audit log is one function."* `STAFF` · HIGH.

## Matcher forms

The second `On` overload takes a matcher between pattern and hook. Every form
used in the tree: `SOURCE` · HIGH · `repo-primary/RESEARCH-mod-definition.md`

| Form | Example | Source |
|---|---|---|
| Scalar equality | `on('tool.call', { tool: 'Read' }, …)` | `agents-md/hooks/register.ts:L179` |
| Boolean | `on('agent.spawn', { fork: true }, …)` | `agents-md/hooks/register.ts:L168` |
| Array = OR | `on('command.run', { command: ['clear', 'resume'] }, …)` | `diff/hooks/register.ts:L841` |
| Nested object, over array **elements** | `on('prompt.context', { instructionFiles: { kind: Files.DROPPED_KINDS } }, …)` | `agents-md/hooks/register.ts:L75-77` |
| Render component | `on('ui.render', { component: 'Pane' }, …)` | `diff/hooks/register.ts:L673` |
| Pane / request id | `on('ui.close', { id: … })`, `on('ui.scroll', { requestId: … })` | `diff/hooks/register.ts:L758, L820` |
| Own plugin | `on('ui.focus', { plugin: … }, …)` | `diff/hooks/register.ts:L799` |

Matchers narrow the type as well as the dispatch. A `ui.render` matcher's
`component` selects from the closed 15-member `RenderComponent` union:
`AskUserQuestion, UserMessage, AssistantMessage, ToolUse, ToolResult, ToolGroup,
ToolProgress, CommandOutput, Spinner, TurnDuration, InfoNotice, SessionMode,
PromptHint, AbovePrompt, Pane`. `SOURCE` · HIGH · `.d.ts:L7291`. (The producing
lane omitted this list; its verifier added it — `repo-primary/VERIFICATION.md`
row 9.7.)

## UI primitives per `RenderSurface`

Elements are **not globals**: `const { Box, Text } = await $.ui.resolve(e)`.
`SOURCE` · HIGH · `.d.ts:L21-23`.

```ts
export type RenderSurface = 'terminal' | 'desktop' | 'mobile' | 'vscode';  // :L8233
```

| Element | terminal | desktop | vscode | mobile |
|---|---|---|---|---|
| `Box`, `Text`, `Button`, `Link`, `Code`, `Markdown` | yes | yes | yes | yes |
| `Input`, `Select` | yes | yes | yes | **no** |
| `Svg` | **no** | yes | yes | yes |
| `Client` (plugin-drawn region) | yes | yes | **no** | **no** |
| `Raster`, `Image` | yes | **no** | **no** | **no** |

`SOURCE` · HIGH · `surfaces-desktop/RESEARCH-mods-surfaces.md`. Both absences
carry an explicit *"not a limit of the device; the table grows when the protocol
does"* note. A mod built on `Client` reaches terminal and Desktop only today.

A session may draw on **several surfaces at once**; clients attach
(`session.attach`) and detach mid-session, so a render hook must read `e.surface`
per ask and must not branch once at `session.start`. `$.session.surface()` is
deprecated in favour of `surfaces()`. `SOURCE` · HIGH.

Interaction events, and what `next(e)` resolves to: `SOURCE` · HIGH ·
`repo-primary/RESEARCH-tooling.md`

| Element | Event | `next(e)` resolves to |
|---|---|---|
| `Button` | `ui.press` | `{ element }`, after the element's own `onPress` in its plugin's environment |
| `Input` | `ui.input` | `{ element, value }`; `next({ ...e, value })` rewrites the typing |
| `Select` | `ui.select` | `{ element, value }` |
| `Client` | `ui.message` | `{}`; only this plugin's hooks see it; one per instance per frame |
| `Pane` / `AbovePrompt` | `ui.scroll` | `{}` after moving to `e.offset`; no `next` leaves it undrawn |
| focus ring | `ui.focus` | — |

`TextProps` (`.d.ts:L9509-9527`): `hover, color, backgroundColor, dimColor, bold,
italic, underline, strikethrough, inverse, wrap`, with
`wrap?: 'wrap' | 'end' | 'middle' | 'truncate' | 'truncate-start' |
'truncate-middle' | 'truncate-end'`. Hover is handled surface-side: *"No hook
runs and nothing crosses to the plugin."* A link whose scheme is not `https:`,
`http:` or `file:` draws as text (`.d.ts:L4759`). A tree that does not validate
draws the engine's own; only `--plugin-dir` is told why. `SOURCE` · HIGH.

`$.ui.mount` (test kit) hands back a `Mounted` drawing with **thirteen** members:
`drawn, find, findAll, press, input, select, key, pointer, post, advance, resize,
redraw, unmount`. `SOURCE` · HIGH · `.d.ts:L11807`, `:L11819` (the producing lane
listed five; its verifier corrected it — `repo-primary/VERIFICATION.md` row 9.8).

## Options

`plugin.json` declares a `userConfig` block (key with `type`, `title`,
`description`, `required`, `default`, `options` enum); the engine surfaces it
under `/config`; the resolved value arrives as `register(on, options)`'s second
argument, typed `PluginOptions`. `SOURCE` · HIGH ·
`mods/agents-md/.claude-plugin/plugin.json`.

Six rules, each load-bearing: `SOURCE` · HIGH ·
`mods/agents-md/README.md:L47-74`, `repo-primary/RESEARCH-mod-definition.md`

1. **Scope.** Options are read from user settings (`~/.claude/settings.json`),
   `--settings`, or managed settings — *"a project's `.claude/settings.json` is
   **not** read for plugin options."* **Per-repository configuration is not
   expressible through this mechanism.**
2. **Key is `<name>@<provenance>`**: `agents-md@builtin` bundled,
   `<name>@<marketplace>` installed, `"<name>"` (or `<name>@inline`) under
   `--plugin-dir`.
3. Changing it reloads the module; the next context the engine builds carries the
   new mode.
4. An out-of-enum value degrades to the default and is told once in the
   transcript; it does not fail.
5. `/plugin` can turn a built-in off — the supported off-switch for a built-in mod.
6. **The host fills the default before `register` sees it**, so a plugin cannot
   tell "unset" from "set to the default".

`PluginOptions` also carries **undeclared** keys, which is how `agents-md`
honours a renamed option from stored settings (`COMPAT_BREAK(<id>)` comment
convention, legacy-key fallback, one `$.ui.log` line). `SOURCE` · HIGH.

## The static source scan

```ts
export type PluginRegisterUses = {
  events: readonly string[];  // the on(...) patterns as written, in registration order
  calls:  readonly string[];  // what it calls on $, "noun.method", sorted
  env?: { reads: readonly string[]; writes: readonly string[] };
};  // :L6196
```

JSDoc: *"Exact, since a module that spells `on`, `$` or `$.env` other than
literally does not load."* Corroborated independently by two readable binary
strings, including the `modules` field's own `describe()`: *"What it hooks and
calls is read from its source before it loads."* `SOURCE` `BINARY` · HIGH ·
`repo-primary/VERIFICATION.md` row 6.11.

**Hard authoring constraint.** A module that computes an event name, aliases `$`,
or builds an env-var name at run time **does not load**. Write
`$.env.get('FOO')` literally. Staff corroborate: *"The engine does refuse if the
author does things like `$[<arbitrary expr>]`, both during plugin registration at
startup and during the manual validation tool."* `STAFF` · HIGH.

The scan is of the source **as written**: a module registering conditionally
still declares every pattern it *could* use. `SOURCE` · HIGH.

`plugin.register` (`.d.ts:L6140`) is the gate that sees this. Its input carries
`name`, `tier`, `root`, `version`, `provenance` and `uses`; its result is
`{ allow: true } | { refuse: string }`. `SOURCE` · HIGH.

## Manifest shape and the one-module rule

`hooks/hooks.json` in all four shipped mods:

```json
{ "description": "…", "modules": ["./register.ts"] }
```

- **`modules` takes exactly one path.** The shipping 2.1.278 manifest schema caps
  it at 1: *"hooks.json `modules` names one hooks module per plugin; a second
  entry is refused."* The array type is a schema artifact, not extensibility.
  **Do not design a multi-module plugin.** `BINARY` · HIGH ·
  `repo-primary/VERIFICATION.md` row 5.1 (this corrected a `WRONG` claim in the
  producing lane).
- **One `hooks.json` may carry classic settings-format `hooks`, `modules`, or
  both.** Schema refine message: *"hooks.json must have `hooks` (the hook
  matchers) or `modules` (hooks modules), or both."* Confirmed independently by a
  local `claude plugin validate` probe accepting both and rejecting a malformed
  classic block, and by `pleaseai/honmoon` in the wild.
  `BINARY` `OBSERVED` `COMMUNITY` · HIGH · `community-falsification/VERIFICATION.md`
  row 5. None of the four shipped mods does this.
- `surface` is a retired top-level key, now refused with a migration message
  pointing at the `Client` element's `module` option. `BINARY` · MEDIUM
- The allowed top-level key set `{$schema, description, hooks, modules, surface}`
  is a **minified-variable inference**. `INFERRED` · MEDIUM

`.claude-plugin/plugin.json` is an ordinary manifest. `telemetry` adds
`"types": "./types/index.d.ts"`; `agents-md` adds `userConfig`. **No `hooks` key
appears in any of the four** — the module is found through the conventional
`hooks/hooks.json` path. `SOURCE` · HIGH.

## Noun contracts (composing mods)

A mod that adds a noun owns its types in its own `types/index.d.ts`, a
declaration file with no imports that declaration-merges onto `EngineInterface`
in `claude-code`, and names that file as `"types"` in `plugin.json`. The value its
`engine.create` hook returns is checked against `EngineInterface['<noun>']`, so
the implementation cannot drift from what callers read. `SOURCE` · HIGH ·
`mods/README.md:L84-107`.

`diff` consumes `telemetry`'s noun and degrades silently when absent — *"where it
is absent the rows are dropped and nothing else changes"* — the documented
posture for an optional noun, with a first-class test for the absent case.
`SOURCE` · HIGH.

## Limits

| Limit | Value | Basis |
|---|---|---|
| Files a hooks module may link | **512** | `BINARY` HIGH (`var eo=512`, plus the refusal template *"is past the 512 files a hooks module may link and was not read"*) |
| Total module bytes | **8,388,608** (8 MiB) | `BINARY` HIGH (`var oo=8388608`, refusal template) |
| Hook budget `ms` | **10,000** per dispatch, the hook's **own** time; waits on `next` and `$` are free, `$.clock` waits excepted | `SOURCE` `OBSERVED` HIGH — `.d.ts:L4173-4205`; cut observed live at 10,249.9 ms |
| `.catch` handler grace `catchMs` | **1,000** | `SOURCE` HIGH |
| `lingerMs` | **5,000** | `SOURCE` HIGH |
| Test timeout | **5,000 ms** default, or `timeoutMs` | `SOURCE` HIGH |
| `Code` element source cap | **10,000** characters | `SOURCE` MEDIUM (commit `30a68508`) |
| `TelemetryChoice.of` members | **32** | `SOURCE` MEDIUM |
| `hooks.json` size cap | exists; numeric value not read | `BINARY` MEDIUM (*"hooks.json is past the size cap and was not read"*) |

Both module-graph limits are counted over the transitive import closure, and both
refuse at the offending file: *"was not read"*, so the load fails at the import
rather than truncating. `BINARY` · HIGH ·
`repo-primary/RESEARCH-enablement-and-limits.md`.

The loader rewrites suffixes (`.js` → `.ts`/`.tsx`, `.jsx` → `.tsx`, `.mjs` →
`.mts`, `.cjs` → `.cts`, plus `<path>/index<ext>`), which is why every mod's
`hooks/index.ts` writes `export * from './register.js'` against a file named
`register.ts`. `BINARY` · HIGH.

Hooks run in a **worker process, one per plugin**, with a heartbeat/wedge
detector and a crash fuse that turns function hooks off for the session after
repeated unattributed crashes. `BINARY` · MEDIUM on the threshold constant, HIGH
that the fuse exists. `repo-primary/VERIFICATION.md` row 6.9 corrected
"a separate worker process" to **one worker per plugin**.
