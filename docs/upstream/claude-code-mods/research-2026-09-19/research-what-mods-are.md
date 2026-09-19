# What a mod is

Self-contained. Pin: 2026-09-19, Claude Code 2.1.278, `mods/` at `92ec78f2`.
Basis labels: `OBSERVED` / `SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` /
`INFERRED`.

## Definition

> A mod is a Claude Code plugin whose behaviour lives in a hooks module: one
> `register(on, options)` entry that hooks the engine's events as functions
> `($, e, next)`. These four ship inside Claude Code; this folder is their
> source, published as it is built into the binary.

`SOURCE` · HIGH · `mods/README.md:L3-6` — see `repo-primary/RESEARCH-mod-definition.md`.

A mod is **not a new artifact kind**. It is an ordinary plugin
(`.claude-plugin/plugin.json` + `hooks/hooks.json`) whose only distinguishing
component is the hooks module. Everything a plugin manifest can carry still
applies. `SOURCE` · HIGH · `repo-primary/RESEARCH-mod-definition.md`

Staff say the same in one sentence: *"A mod is just a plugin that uses function
hooks, nothing is changing there."* `STAFF` · HIGH · issue #91870 body, dated
Sep 9, 2026 — `x-threads/RESEARCH-staff-statements.md`.

Product naming: "Claude Mods" is the product name; "function hook" remains the
documented implementation primitive. `STAFF` · HIGH ·
`x-threads/RESEARCH-staff-statements.md`.

## The three signatures

```ts
export type Register = (on: On, options: PluginOptions) => unknown;   // :L7252
export type PluginOptions = Readonly<Record<string, string | number | boolean | readonly string[]>>;  // :L6137
export type On = {
  <P extends Pattern>(pattern: P, hook: NoInfer<HookFor<P>>): Registration<HookFor<P>>;
  <P extends Pattern, const M extends Matcher<Args<MatchedNames<P>>>>(pattern: P, matcher: M, hook: NoInfer<MatchedHook<P, M>>): Registration<MatchedHook<P, M>>;
};  // :L5398
```

The hook body is `($: EngineInterface, e: Frozen<Args<N>>, next: GlobNext<P>) =>
EventResult<N> | Promise<EventResult<N>>` (`:L4132`). `e` is **frozen**: a hook
rewrites by passing a copy to `next`, never by mutating `e`.
`SOURCE` · HIGH · `repo-primary/RESEARCH-mod-definition.md`

`register` is typed `=> unknown` and may return early, so **which hooks exist at
all can depend on an option** — `agents-md` does exactly this.
`SOURCE` · HIGH · `mods/agents-md/hooks/register.ts:L40-90`.

## The fold / chain model

- `next(e)` runs the hooks beneath, then core. `SOURCE` · HIGH
- Returning **without** calling `next` takes the call. `{ deny: reason }`
  refuses; `{ result }` / `{ value }` answers. `SOURCE` `OBSERVED` · HIGH ·
  `architecture-pdf/DENY-AND-ERROR-SEMANTICS.md`
- `next.to(e, tier)` skips past intervening tiers.
- A plugin's own registrations nest in order, first outermost; a repeat throws.
  `SOURCE` · HIGH · `On` JSDoc `:L5390`
- `next` carries read-only metadata: `next.event`, `next.origin` (`.tier`,
  `.kind`), `next.trace`, `next.budget` (a live `HookBudget`, read fresh on each
  access). `next.origin` is also the recursion guard — a plugin's own `$` call
  does not re-enter its own hook for that event. `SOURCE` · HIGH ·
  `repo-primary/RESEARCH-chain-and-tiers.md`
- `engine.create` is the noun fold: `{ ...await next(e), myNoun }` adds a noun to
  `$` without replacing anything beneath. `SOURCE` · HIGH ·
  `mods/telemetry/README.md`
- `tool.list` may call `next` twice (once via `next.to`, once normally) and merge
  the results — the pattern for "what would this look like without the tier above
  me". `SOURCE` · HIGH · `mods/sec-default/hooks/register.ts`

Staff's own framing: *"the plugin registered first 'owns' all subsequent hooks on
a given event instance. There is no capability for a plugin 'further down the
chain' to inhibit a plugin above it; it's an 'onion model'."* `STAFF` · HIGH,
issue #91870 comment 5530555431, 2026-09-03T18:50:55Z.

## No ambients

> A hooks module runs in an environment of its own: no DOM, no Node. … is an ES
> module whatever its suffix: there is no `require`.

`SOURCE` · HIGH · `.d.ts:L14-23`. Also: **no timers** — time goes through
`$.clock`; no global `fetch` — HTTP is `$.http.fetch`; no `fs`/`process` — those
are `$.fs` and `$.process`. Globals are `h`, `Fragment`, the JSX namespace, and
the environment's web APIs (`URL`, `TextEncoder`, `AbortController`,
`crypto.subtle`, `console`). `SOURCE` · HIGH ·
`repo-primary/RESEARCH-mod-definition.md`

This is why every `$` call is interceptable: there is no way around it.

## The five tiers

```ts
const TIERS: readonly ["prepend", "user", "append", "builtin", "core"];
```

`SOURCE` · HIGH · `.d.ts:L9547`. JSDoc, verbatim: *"The chain's five tiers,
outermost first: earlier is outer is more authority, and same-event hooks nest in
this order and no other way."* `core` is a tier and the base of the fold
(`.d.ts:9530`, `:9547`); a plugin can seat only in the four `PluginTier` values
`prepend | user | append | builtin` (`Exclude<Tier, 'core'>`), which is why the
CLI's invalid-tier error and a 2026-09-19 maintainer comment both list four.

| Tier | Who | Note |
|---|---|---|
| `prepend` | managed plugins an administrator lists first | highest authority |
| `user` | everything a person installs | **above `builtin`** |
| `append` | managed plugins an administrator lists last | |
| `builtin` | the plugins bundled in the binary (the four mods) | |
| `core` | the engine's innermost link | lowest |

Two properties a plugin author must carry:

1. **`user` sits above `builtin`.** A plugin you install wraps `diff` and
   `agents-md`, not the other way round. `SOURCE` · HIGH
2. **`builtin` is not privileged for outbound calls.** *"a built-in's `$` calls
   still raise everywhere"* — a built-in calling `$.fs.read` still passes through
   every user-tier `fs.read` hook above it. `SOURCE` · HIGH

`repo-primary/RESEARCH-chain-and-tiers.md` carries both quotes in full.

## Seating

`sec-default` is seated first in the prepend tier wherever hooks modules load, on
a machine with managed settings or for a Team/Enterprise organization, **unless**
managed settings define `prependPlugins`: then that list is the whole prepend
tier, e.g. `["acme-guard@acme-tools", "sec-default@builtin"]`.
`SOURCE` · HIGH · `mods/sec-default/README.md:L47-55`.

`prependPlugins` and `appendPlugins` are real managed-settings keys implemented
in 2.1.278 (12 and 10 occurrences respectively, with live UX strings such as
*"seated by managed prependPlugins at position "*, *"not seated: managed
prependPlugins does not list it"*). `BINARY` · HIGH ·
`surfaces-desktop/VERIFICATION.md` finding B. Neither key appears in the
CHANGELOG or in any docs page. `OBSERVED` · HIGH

Staff: *"mods cannot dictate their own registration order, full-stop."*
`STAFF` · HIGH · #91870 comment 5738020815, 2026-09-19T00:53:54Z.

## What a third-party mod may and may not do

A plugin a person installs lands in the `user` tier (`--plugin-dir` likewise).

**May:**

- Register hooks on any of the 92 statically-named events, the 33 `classic.*`
  events, and any noun another loaded plugin declares. `SOURCE`
- Call `next(e)`, return `{ deny }` / `{ value }` / `{ result }`, or answer
  itself. `SOURCE` `OBSERVED`
- Wrap every `builtin` and `core` behaviour, including the four shipped mods.
  `SOURCE`
- Add a noun to `$` at `engine.create` for other plugins to call. `SOURCE`
- Restyle or remove an element for **every other plugin** by hooking
  `ui.resolve`. `SOURCE` · HIGH · `repo-primary/RESEARCH-tooling.md`
- Veto another plugin's load at `plugin.register` with `{ refuse: string }`; the
  transcript names the refusing plugin and the reason. `SOURCE` · HIGH

**May not:**

- Use `next.to`. It is typed to `append | builtin | core` only
  (`TargetTier = Exclude<Tier, 'prepend' | 'user'>`, `.d.ts:L9446`) **and is
  refused outside a managed tier** — *"loading it with `--plugin-dir` seats a
  plugin that can only pass."* `SOURCE` · HIGH ·
  `mods/sec-default/README.md:L52-55`. The binary's own string agrees:
  *"next.to is available to managed plugins (prependPlugins / appendPlugins)
  only"*. `BINARY` · HIGH
- Choose its own tier or registration order. `STAFF` · HIGH
- Reach anything `sec-default` guards on a managed machine — an org's classic
  hooks, prompt content, managed settings and tool policy. `SOURCE` · HIGH
- Hook `$.ui.ask`: it is the one `$` method with **no** corresponding event
  (`grep -c "'ui.ask'"` → 0 over the whole 12,990-line file). The consequence
  "therefore not interceptable" is `INFERRED` · the absence itself is `SOURCE` ·
  HIGH · `repo-primary/RESEARCH-event-catalog.md`
- Hook a component the surface does not declare hookable. Staff: *"our internal
  'permission request component' is simply not something you can hook into,
  because the surface does not declare it as being hookable."* `STAFF` · HIGH
- Spell `on`, `$` or `$.env` other than literally — the host statically scans the
  source and **a module that does not spell them literally does not load**.
  `SOURCE` `BINARY` · HIGH · see `research-api-surface.md`.

## The four shipped mods

| Mod | What it does | Seated |
|---|---|---|
| `sec-default` | Keeps an organization's classic hooks, prompt content, managed settings and tool policy out of reach of the plugins a person installs; adds no policy of its own. | Outermost, on a machine with managed settings or for a Team/Enterprise org, unless managed `prependPlugins` says otherwise |
| `diff` | `/diff`: the session's uncommitted changes in a pane beside the transcript. | Built in |
| `telemetry` | Adds `$.telemetry` (`log`, `mark`) in the `engine.create` fold; sends nothing where analytics are off. | Built in (`mods/telemetry/README.md` narrows it further to internal builds) |
| `agents-md` | `AGENTS.md` as project instructions, by one option. | Built in |

`SOURCE` · HIGH · `mods/README.md`. Register-module sizes as a complexity signal:
`sec-default` 1,998 B · `telemetry` 1,746 B · `agents-md` 9,507 B · `diff`
23,421 B. `diff` is the reference implementation for UI work.
