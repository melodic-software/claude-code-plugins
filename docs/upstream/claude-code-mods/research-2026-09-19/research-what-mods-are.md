# What a mod is

Self-contained. Pin: 2026-09-19, Claude Code 2.1.278, `mods/` at `92ec78f2`.
Basis labels: `OBSERVED` / `SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` /
`INFERRED`.

## Definition

In the README's definition, a mod is an ordinary plugin that keeps its behavior
in a hooks module: a single `register(on, options)` function that attaches a
`($, e, next)` function to each engine event it handles. The folder holds the
source of the four mods compiled into the Claude Code binary.

`SOURCE` · HIGH · `mods/README.md:L3-6`; see `repo-primary/RESEARCH-mod-definition.md`.

A mod is **not a new artifact kind**. It is an ordinary plugin
(`.claude-plugin/plugin.json` + `hooks/hooks.json`) whose only distinguishing
component is the hooks module. Everything a plugin manifest can carry still
applies. `SOURCE` · HIGH · `repo-primary/RESEARCH-mod-definition.md`

Staff said the same in one line: a mod is a plugin built on function hooks, and
plugins themselves do not change. `STAFF` · HIGH · issue #91870 body, dated
Sep 9, 2026; see `x-threads/RESEARCH-staff-statements.md`.

Product naming: "Claude Mods" is the product name; "function hook" remains the
documented implementation primitive. `STAFF` · HIGH ·
`x-threads/RESEARCH-staff-statements.md`.

## The three signatures

- `Register` (`:L7252`) takes `on: On` and `options: PluginOptions`, and its return type is
  `unknown`.
- `PluginOptions` (`:L6137`) is a read-only record from string keys to a string, number, boolean
  or read-only string array.
- `On` (`:L5398`) has two call forms: pattern and hook, or pattern, matcher and hook. The pattern
  is a `Pattern`, the matcher a `Matcher` over the `Args` of that pattern's `MatchedNames`, and
  the hook type follows from them (`HookFor` or `MatchedHook`, behind `NoInfer`). Each form returns
  a `Registration` of that hook type.

The hook body takes `$` (`EngineInterface`), `e` (`Frozen<Args<N>>`) and `next` (`GlobNext<P>`),
and returns `EventResult<N>` or a promise of it (`:L4132`). `e` is **frozen**: a hook
rewrites by passing a copy to `next`, never by mutating `e`.
`SOURCE` · HIGH · `repo-primary/RESEARCH-mod-definition.md`

`register` is typed `=> unknown` and may return early, so **which hooks exist at
all can depend on an option**, and `agents-md` does exactly this.
`SOURCE` · HIGH · `mods/agents-md/hooks/register.ts:L40-90`.

## The fold / chain model

- `next(e)` passes the call to the lower hooks and last to core. `SOURCE` · HIGH
- Returning **without** calling `next` takes the call. `{ deny: reason }`
  refuses; `{ result }` / `{ value }` answers. `SOURCE` `OBSERVED` · HIGH ·
  `architecture-pdf/DENY-AND-ERROR-SEMANTICS.md`
- `next.to(e, tier)` skips past intervening tiers.
- One plugin's registrations nest as made, the earliest outside; a duplicate throws.
  `SOURCE` · HIGH · `On` JSDoc `:L5390`
- `next` carries read-only metadata: `next.event`, `next.origin` (`.tier`,
  `.kind`), `next.trace`, `next.budget` (a live `HookBudget`, current whenever it
  is read). `next.origin` is also the recursion guard: a plugin's own `$` call
  does not re-enter its own hook for that event. `SOURCE` · HIGH ·
  `repo-primary/RESEARCH-chain-and-tiers.md`
- `engine.create` is the noun fold: `{ ...await next(e), myNoun }` adds a noun to
  `$` without replacing anything beneath. `SOURCE` · HIGH ·
  `mods/telemetry/README.md`
- `tool.list` may call `next` twice (once via `next.to`, once normally) and merge
  the results, the way to compare a result with and without the tiers above the
  caller. `SOURCE` · HIGH · `mods/sec-default/hooks/register.ts`

Staff called it an onion: for one event instance the earliest-registered plugin
wraps every later hook, and no plugin lower in the chain can stop one above it.
`STAFF` · HIGH,
issue #91870 comment 5530555431, 2026-09-03T18:50:55Z.

## No ambients

The declarations give a hooks module a sandboxed runtime without DOM or Node
APIs; every file is treated as ES module code regardless of extension, so `require` is absent.

`SOURCE` · HIGH · `.d.ts:L14-23`. Also: **no timers** (time goes through
`$.clock`); no global `fetch` (HTTP is `$.http.fetch`); no `fs`/`process` (those
are `$.fs` and `$.process`). Globals are `h`, `Fragment`, JSX names, plus the
web APIs the runtime provides (`URL`, `TextEncoder`, `AbortController`,
`crypto.subtle`, `console`). `SOURCE` · HIGH ·
`repo-primary/RESEARCH-mod-definition.md`

This is why every `$` call is interceptable: there is no way around it.

## The five tiers

`TIERS` lists five tiers in order: `prepend`, `user`, `append`, `builtin`, `core`.

`SOURCE` · HIGH · `.d.ts:L9547`. Its JSDoc lists the tiers from outside in: an
outer tier holds more authority, and hooks on one event always nest in exactly
that sequence. `core` is a tier and the base of the fold
(`.d.ts:9530`, `:9547`); a plugin can seat only in the four `PluginTier` values
`prepend | user | append | builtin` (`Exclude<Tier, 'core'>`), which is why the
CLI's invalid-tier error and a 2026-09-19 maintainer comment both list four.

| Tier | Who | Note |
|---|---|---|
| `prepend` | plugins named first in managed settings | highest authority |
| `user` | everything a person installs | **above `builtin`** |
| `append` | plugins named last in managed settings | |
| `builtin` | plugins compiled into Claude Code (the four mods) | |
| `core` | the engine's innermost link | lowest |

Two properties a plugin author must carry:

1. **`user` sits above `builtin`.** A plugin you install wraps `diff` and
   `agents-md`, not the other way round. `SOURCE` · HIGH
2. **`builtin` is not privileged for outbound calls.** A built-in's own `$` calls
   fire through the whole chain: a built-in calling `$.fs.read` still passes through
   every user-tier `fs.read` hook above it. `SOURCE` · HIGH

`repo-primary/RESEARCH-chain-and-tiers.md` carries the source lines for both.

## Seating

Where hooks modules load, and either settings are managed or the organization is
on a Team/Enterprise plan, the CLI puts `sec-default` at the head of the prepend
tier. A managed `prependPlugins` list replaces that default: the list becomes the
entire prepend tier, e.g. `["acme-guard@acme-tools", "sec-default@builtin"]`.
`SOURCE` · HIGH · `mods/sec-default/README.md:L47-55`.

`prependPlugins` and `appendPlugins` are real managed-settings keys implemented
in 2.1.278 (12 and 10 occurrences respectively, with live UX strings that report
the seat a managed `prependPlugins` list gives a plugin, and that a plugin the
list omits stays unseated). `BINARY` · HIGH ·
`surfaces-desktop/VERIFICATION.md` finding B. Neither key appears in the
CHANGELOG or in any docs page. `OBSERVED` · HIGH

Staff ruled out, with no exception, any way for a mod to set its place in the order.
`STAFF` · HIGH · #91870 comment 5738020815, 2026-09-19T00:53:54Z.

## What a third-party mod can and cannot do

A plugin a person installs lands in the `user` tier (`--plugin-dir` likewise).

**May:**

- Register hooks on any of the 92 statically-named events, the 33 `classic.*`
  events, and any noun another loaded plugin declares. `SOURCE`
- Call `next(e)`, return `{ deny }` / `{ value }` / `{ result }`, or answer
  itself. `SOURCE` `OBSERVED`
- Wrap every `builtin` and `core` behavior, including the four shipped mods.
  `SOURCE`
- Add a noun to `$` at `engine.create` for other plugins to call. `SOURCE`
- Restyle or remove an element for **every other plugin** by hooking
  `ui.resolve`. `SOURCE` · HIGH · `repo-primary/RESEARCH-tooling.md`
- Veto another plugin's load at `plugin.register` with `{ refuse: string }`; the
  transcript names the refusing plugin and the reason. `SOURCE` · HIGH

**May not:**

- Use `next.to`. It is typed to `append | builtin | core` only
  (`TargetTier = Exclude<Tier, 'prepend' | 'user'>`, `.d.ts:L9446`) **and takes
  effect only when managed settings seat the plugin**: under `--plugin-dir` it
  loads, but its `next.to` calls can do nothing except pass. `SOURCE` · HIGH ·
  `mods/sec-default/README.md:L52-55`. A message in the binary agrees: `next.to`
  works only for plugins seated by `prependPlugins` or `appendPlugins`.
  `BINARY` · HIGH
- Choose its own tier or registration order. `STAFF` · HIGH
- Reach what `sec-default` guards on a managed machine: the organization's
  classic hooks, the instructions it adds to the prompt, its managed settings and
  its limits on which tools may run.
  `SOURCE` · HIGH
- Hook `$.ui.ask`: it is the one `$` method with **no** corresponding event
  (`grep -c "'ui.ask'"` → 0 over the whole 12,990-line file). The consequence
  "therefore not interceptable" is `INFERRED` · the absence itself is `SOURCE` ·
  HIGH · `repo-primary/RESEARCH-event-catalog.md`
- Hook a component its surface has not marked as hookable. Staff gave the
  internal permission-request component as the example: its surface never
  marks it hookable, so no plugin can hook it. `STAFF` · HIGH
- Spell `on`, `$` or `$.env` other than literally: the host statically scans the
  source and **a module that does not spell them literally does not load**.
  `SOURCE` `BINARY` · HIGH · see `research-api-surface.md`.

## The four shipped mods

| Mod | Its job | Seat |
|---|---|---|
| `sec-default` | Guards what an organization configures (its classic hooks, the instructions it adds to the prompt, managed settings and limits on which tools may run) from plugins a person adds; it sets no rules itself. | The outermost seat wherever settings are managed or the account is a Team/Enterprise one; a managed `prependPlugins` list overrides that |
| `diff` | `/diff`: a side pane, next to the conversation, listing what the session has changed and not yet committed. | Built in |
| `telemetry` | Contributes a `$.telemetry` noun with `log` and `mark` during `engine.create`; nothing leaves the machine when analytics are disabled. | Built in (`mods/telemetry/README.md` narrows it further to internal builds) |
| `agents-md` | Loads `AGENTS.md` as the project's instructions, controlled by a single option. | Built in |

`SOURCE` · HIGH · `mods/README.md`. Register-module sizes as a complexity signal:
`sec-default` 1,998 B · `telemetry` 1,746 B · `agents-md` 9,507 B · `diff`
23,421 B. `diff` is the reference implementation for UI work.
