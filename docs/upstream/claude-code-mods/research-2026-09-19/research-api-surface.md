# The API surface

Self-contained. Pin: 2026-09-19, Claude Code 2.1.278, `mods/` at `92ec78f2`,
declarations written by 2.1.277. Basis labels: `OBSERVED` / `SOURCE` / `BINARY` /
`STAFF` / `COMMUNITY` / `INFERRED`.

**The full verbatim catalog (every event name, every noun member, in
declaration order, with file-and-line citations) is
`repo-primary/RESEARCH-event-catalog.md`.** This sidecar is the summary. A
fresh-context verifier scripted a set-diff of that catalog against the `.d.ts`
and found **0 invented and 0 missed** names, matching in declaration order
(`repo-primary/VERIFICATION.md`, checks 1.1–1.12).

## How the name space is assembled

`EventOf` is the intersection of `CoreEventOf` and `NounEventOf` (`:L3885`). `CoreEventOf` is
in turn the intersection of `EngineEventOf`, `ClassicEventOf` and `OpEventOf` (`:L3017`).
`EventName` is the set of keys of `EventOf` (`:L3875`).

`SOURCE` · HIGH.

## Counts

| Family | Count | Where | Basis |
|---|---|---|---|
| `EngineEventOf`: the fold points | **38** | `.d.ts:L3213` | `SOURCE` HIGH |
| `OpEventOf`: one per `$` method | **54** | `.d.ts:L5460` | `SOURCE` HIGH |
| **Statically named before any plugin noun** | **92** | 38 + 54 | `SOURCE` HIGH |
| `ClassicEventOf`: `classic.<HookEvent>` | **33** | derived from the 33-member `HookInput` union, `.d.ts:L4240` | `SOURCE` HIGH |
| `NounEventOf` | **0 while no plugin noun is declared** | `.d.ts:L5359` | `SOURCE` HIGH |
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

`Pattern` accepts an `EventName`, a `Glob` or a `Negation` (`:L5995`).

One event (`tool.call`), a namespace (`classic.*`, `ui.*`), everything (`*`), or
everything-but (`!tool.*`). `Namespace<N>` recurses on dots, so multi-level
namespaces are selectable. `SOURCE` · HIGH · `.d.ts:L8317`, `:L5101`.

Staff: a `*` hook receives all events, plugins' own `$` calls included, which
makes an audit log a single function. `STAFF` · HIGH.

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
lane omitted this list; its verifier added it, per `repo-primary/VERIFICATION.md`
row 9.7.)

## UI primitives per `RenderSurface`

Elements are **not globals**: `const { Box, Text } = await $.ui.resolve(e)`.
`SOURCE` · HIGH · `.d.ts:L21-23`.

`RenderSurface` takes one of four literals: `'terminal'`, `'desktop'`, `'mobile'` or `'vscode'`
(`:L8233`).

| Element | terminal | desktop | vscode | mobile |
|---|---|---|---|---|
| `Box`, `Text`, `Button`, `Link`, `Code`, `Markdown` | yes | yes | yes | yes |
| `Input`, `Select` | yes | yes | yes | **no** |
| `Svg` | **no** | yes | yes | yes |
| `Client` (plugin-drawn region) | yes | yes | **no** | **no** |
| `Raster`, `Image` | yes | **no** | **no** | **no** |

`SOURCE` · HIGH · `surfaces-desktop/RESEARCH-mods-surfaces.md`. Both absences
carry a note that the gap belongs to the protocol, not the device, and closes as
the protocol grows. A mod built on `Client` reaches terminal and Desktop only today.

One session can draw on **several surfaces simultaneously**; clients attach
(`session.attach`) and detach mid-session, so a render hook must read `e.surface`
per ask and must not branch once at `session.start`. `$.session.surface()` is
deprecated in favor of `surfaces()`. `SOURCE` · HIGH.

Interaction events, and what `next(e)` resolves to: `SOURCE` · HIGH ·
`repo-primary/RESEARCH-tooling.md`

| Element | Event | `next(e)` resolves to |
|---|---|---|
| `Button` | `ui.press` | `{ element }`, after the element's own `onPress` in its plugin's environment |
| `Input` | `ui.input` | `{ element, value }`; `next({ ...e, value })` rewrites the typing |
| `Select` | `ui.select` | `{ element, value }` |
| `Client` | `ui.message` | `{}`; visible to this plugin's hooks alone; at most one per instance in each frame |
| `Pane` / `AbovePrompt` | `ui.scroll` | `{}` after moving to `e.offset`; no `next` leaves it undrawn |
| focus ring | `ui.focus` | none |

`TextProps` (`.d.ts:L9509-9527`): `hover, color, backgroundColor, dimColor, bold,
italic, underline, strikethrough, inverse, wrap`, with
`wrap?: 'wrap' | 'end' | 'middle' | 'truncate' | 'truncate-start' |
'truncate-middle' | 'truncate-end'`. The surface handles hover itself, with no
hook call and no data sent to the plugin. Links with any scheme besides `https:`,
`http:` or `file:` render as plain text (`.d.ts:L4759`). An invalid tree is
replaced by the engine's default rendering; only `--plugin-dir` reports the reason. `SOURCE` · HIGH.

`$.ui.mount` (test kit) hands back a `Mounted` drawing with **thirteen** members:
`drawn, find, findAll, press, input, select, key, pointer, post, advance, resize,
redraw, unmount`. `SOURCE` · HIGH · `.d.ts:L11807`, `:L11819` (the producing lane
listed five; its verifier corrected it, per `repo-primary/VERIFICATION.md` row 9.8).

## Options

`plugin.json` declares a `userConfig` block (key with `type`, `title`,
`description`, `required`, `default`, `options` enum); the engine surfaces it
under `/config`; the resolved value arrives as `register(on, options)`'s second
argument, typed `PluginOptions`. `SOURCE` · HIGH ·
`mods/agents-md/.claude-plugin/plugin.json`.

Six rules, each load-bearing: `SOURCE` · HIGH ·
`mods/agents-md/README.md:L47-74`, `repo-primary/RESEARCH-mod-definition.md`

1. **Scope.** Options come from user settings (`~/.claude/settings.json`),
   `--settings`, or the managed layer; `.claude/settings.json` in a project is
   **never** consulted for plugin options. **Per-repository configuration is not
   expressible through this mechanism.**
2. **Key is `<name>@<provenance>`**: `agents-md@builtin` bundled,
   `<name>@<marketplace>` installed, `"<name>"` (or `<name>@inline`) under
   `--plugin-dir`.
3. A change makes the module load again, and the engine's following context carries
   the new mode.
4. An out-of-enum value degrades to the default with a single transcript notice; it
   does not fail.
5. `/plugin` can turn a built-in off, and is the supported way to disable one.
6. **The host fills the default before `register` sees it**, so a plugin cannot
   tell "unset" from "set to the default".

`PluginOptions` also carries **undeclared** keys, which is how `agents-md`
honors a renamed option from stored settings (`COMPAT_BREAK(<id>)` comment
convention, legacy-key fallback, one `$.ui.log` line). `SOURCE` · HIGH.

## The static source scan

`PluginRegisterUses` (`:L6196`) is an object type with two read-only string lists,
`events` and `calls`, and an optional `env` object holding `reads` and `writes`
string lists. `events` holds the `on(...)` patterns in registration order and `calls` the sorted
`noun.method` calls on `$`. The JSDoc calls both exact, because a module that
writes `on`, `$` or `$.env` in any non-literal form fails to load. Two readable
binary strings corroborate it independently, one of them the `modules` field's
own `describe()`, which says hooks and calls come from the module's source,
scanned ahead of loading. `SOURCE` `BINARY` · HIGH ·
`repo-primary/VERIFICATION.md` row 6.11.

**Hard authoring constraint.** A module that computes an event name, aliases `$`,
or builds an env-var name at run time **does not load**. Write
`$.env.get('FOO')` literally. Staff corroborate: the engine refuses a module that
indexes `$` with a computed expression (`$[<arbitrary expr>]`), both when plugins
register at startup and in the manual validation tool. `STAFF` · HIGH.

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
  it at 1: its message allows a plugin a single hooks module and rejects any
  second entry. The array type is a schema artifact, not extensibility.
  **Do not design a multi-module plugin.** `BINARY` · HIGH ·
  `repo-primary/VERIFICATION.md` row 5.1 (this corrected a `WRONG` claim in the
  producing lane).
- **One `hooks.json` may carry classic settings-format `hooks`, `modules`, or
  both.** The schema's refine message requires at least one of `hooks` (classic
  matchers) and `modules`, and accepts the two together. Confirmed independently by a
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
appears in any of the four**; the module is found through the conventional
`hooks/hooks.json` path. `SOURCE` · HIGH.

## Noun contracts (composing mods)

To contribute a noun, a mod keeps its types in its own `types/index.d.ts`: an
import-free declaration file merged into `EngineInterface` in `claude-code`,
named as `"types"` in `plugin.json`. Its `engine.create` hook's return value is
type-checked against `EngineInterface['<noun>']`, which keeps the implementation
in step with the types callers see. `SOURCE` · HIGH ·
`mods/README.md:L84-107`.

`diff` consumes `telemetry`'s noun and degrades silently when absent (it leaves
out the rows that need it and otherwise behaves the same), the documented
posture for an optional noun, with a first-class test for the absent case.
`SOURCE` · HIGH.

## Limits

| Limit | Value | Basis |
|---|---|---|
| Files one hooks module can link | **512** | `BINARY` HIGH (`var eo=512`, plus a refusal template reporting a file beyond that count as skipped) |
| Total module bytes | **8,388,608** (8 MiB) | `BINARY` HIGH (`var oo=8388608`, refusal template) |
| Hook budget `ms` | **10,000** per dispatch, the hook's **own** time; waits on `next` and `$` are free, `$.clock` waits excepted | `SOURCE` `OBSERVED` HIGH: `.d.ts:L4173-4205`; cut observed live at 10,249.9 ms |
| `.catch` handler grace `catchMs` | **1,000** | `SOURCE` HIGH |
| `lingerMs` | **5,000** | `SOURCE` HIGH |
| Test timeout | **5,000 ms** default, or `timeoutMs` | `SOURCE` HIGH |
| `Code` element source cap | **10,000** characters | `SOURCE` MEDIUM (commit `30a68508`) |
| `TelemetryChoice.of` members | **32** | `SOURCE` MEDIUM |
| `hooks.json` size cap | exists; numeric value not read | `BINARY` MEDIUM (a refusal template reports an oversized `hooks.json` as unread) |

Both module-graph limits are counted over the transitive import closure, and both
refuse at the offending file, reporting it unread, so the load fails at the import
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
