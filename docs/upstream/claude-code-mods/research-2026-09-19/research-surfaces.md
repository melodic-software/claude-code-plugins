<!-- markdownlint-disable MD049 -->

# Surfaces: where plugins reach, and where mods reach

Self-contained. Pin: 2026-09-19, Claude Code 2.1.278. Basis labels: `OBSERVED` /
`SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` / `INFERRED`.

Lane: `surfaces-desktop/`, with corrections in its `VERIFICATION.md`.

## The question splits in two

Whether a surface can run a mod is a conjunction:

1. **Does the surface run the Claude Code engine at all?** Well documented. Chat
   is the only listed surface that does not.
2. **Does that engine process have hooks modules enabled?** Barely documented at
   all, and not per surface. The gate reads the env var or the rollout result
   plus hook policy — **it reads no surface, host, or client type**.
   `BINARY` · HIGH · `surfaces-desktop/VERIFICATION.md` finding C.

A surface that loads plugins and classic hooks today does **not** thereby load
mods.

## The matrix

`D` = documented · `I` = inferred · `U` = unknown · `X` = documented no.

| Surface | Runs the engine | Plugins + marketplaces | Classic hooks | Mods: could a hooks module load? |
|---|---|---|---|---|
| **CLI, interactive** | D yes, canonically | D yes | D yes | **D yes** with the gate on. `RenderSurface` `terminal`. Verified `OBSERVED`. |
| **CLI, `-p` / headless** | D yes | D yes | D yes | Engine yes, **draws nowhere**: `session.start.surface` is `null`, `$.session.surfaces()` empty. Non-UI hooks run; UI hooks have no destination. |
| **Desktop, Code tab, local session** | D yes, *"the same underlying engine with a graphical interface"*; shares `~/.claude.json`, `~/.claude/settings.json`, `CLAUDE.md`, hooks, skills | D yes, plugin browser in the `+` menu | D yes | **I yes**, on two unconfirmed sub-conditions: (a) the **bundled** CLI carries the runtime; (b) the env var or the rollout reaches that process. Desktop's local-environment editor is a documented mechanism for (b) but not a documented outcome. `RenderSurface` includes `desktop`. |
| **Desktop, Code tab, cloud session** | D yes, in an Anthropic-managed VM | D **no plugin browser**; repo `enabledPlugins` or claude.ai account sync only | D yes, from those plugins | **U.** Env vars are settable on the cloud environment; nothing says the gate is honoured there. |
| **Desktop, Cowork tab** | D yes — *"Cowork in the Claude Desktop app runs its sessions on Claude Code"* | D account/org plugins from **Customize**, synced through claude.ai, not `~/.claude` | D yes — a synced plugin's *"skills, agents, hooks, MCP servers, and LSP servers all load"* | **U.** Engine yes and plugin hooks load, so the only missing condition is the gate. No source says a person can set it in a Cowork session. |
| **Desktop, Chat tab** | D **no** | D installable, only **skills** run | D no | **X** for plugin hooks: they do not run in chat at all. |
| **claude.ai chat (web)** | D no | same as Chat tab | D no | **X**, same basis. |
| **claude.ai/code (web), mobile Code tab** | D yes — clients onto cloud sessions | D repo-declared or account-synced only; `/plugin` unavailable | D yes | **U**, same reasoning as Desktop cloud. `RenderSurface` has `mobile`, whose element table has no `Input`/`Select`/`Client`. |
| **VS Code extension** | D yes, bundles a private CLI copy for the chat panel | D yes; graphical manager, *"the same CLI commands under the hood"*, shared both ways | D yes | **I yes** if the gate reaches the bundled CLI. `RenderSurface` includes `vscode`, whose table lacks `Client`. Whether the extension passes the env var through is **U**. |
| **JetBrains plugin** | D indirectly — *"runs the `claude` command in your IDE's integrated terminal"*, does not bundle a CLI | D yes, because it is a terminal session | D yes | **D-adjacent yes**: a JetBrains session is a `terminal` surface, so the CLI answer applies unchanged. |
| **Agent SDK** | D yes | D `{ type: "local", path }` only | D yes | Engine yes, **draws nowhere** (`surface` null for *"a `-p` run or the SDK"*). Whether the SDK honours the gate is **U**. |

All `D` rows: `SOURCE` (docs) · HIGH, fetched 2026-09-19 —
`surfaces-desktop/RESEARCH-surface-matrix.md` carries the verbatim quote and URL
for each.

## Desktop specifically: demoed, not shipped

**The resolution every downstream agent must carry:** Claude Code Desktop was
**demoed in an internal prototype on 2026-09-03 only. It is not shipped
support.** `STAFF` · HIGH · `x-threads/VERIFICATION.md` row 4;
`community-falsification/RESEARCH-falsification.md` claim 3.

Every Desktop reference in circulation traces to two roots, both dated
2026-09-03, six days before the public flag:

1. One staff comment: *"_my_ personal goal is for this to work on any surface
   powered by the Claude Code binary. **Our internal prototype supports local
   Claude Code Desktop at the moment, as demonstrated in a few of the videos.**
   other surfaces are top of mind but tbd."*
2. Two demo-video captions in the issue body: *"One hook on `ui.press` sees the
   same button pressed in the terminal and in the desktop app"* and *"A plugin
   hides sensitive values in Claude Code Desktop until you hover over them."*

A case-insensitive `desktop` grep over all 203 comments returns exactly that one
staff comment and nothing later. **No community report of a mod running in
Desktop was found** (checked: `anthropics/claude-code` issues and PRs, HN
Algolia, GitHub code search, four blogs, web search; unchecked: Reddit, Discord,
X). The HN submission title *"Claude Mods, Functional Hooks in Claude Code and
Desktop"* propagates Desktop as settled fact; it links only to the issue, which
does not support it.

**Do not write "confirmed on Desktop" anywhere.** The `x-threads` lane originally
did; its verifier corrected it in four places.

Two further Desktop-specific constraints: the Desktop-bundled CLI **lags** the
standalone one (the CHANGELOG records a fix landing *"on Claude Desktop (once
Desktop bundles this CLI version)"*), and the `144`/`110`-column pane-width rule
is written in terminal terms — whether Desktop applies the same test is unknown.
`SOURCE` · MEDIUM.

**The highest-value cheap experiment is empirical, not bibliographic:** set the
variable in Desktop's local-environment editor (or `env` in
`~/.claude/settings.json`), load a trivial mod with `--plugin-dir`, and see
whether it registers.

## Cowork: the row most likely to be misread

Cowork **is** a Claude Code host and **does** run plugin hooks — but only for
plugins synced from a claude.ai account or org, not from `~/.claude`. A
mods-bearing plugin distributed that way would be *delivered* to Cowork; whether
its module would *load* there depends entirely on the gate, which nothing sourced
addresses for Cowork. `SOURCE` · HIGH.

Cowork **never** fetches server-managed settings from the admin console, while
managed settings do reach the terminal, both IDE extensions, the Desktop Code tab
and Agent SDK sessions. `SOURCE` · HIGH ·
`surfaces-desktop/RESEARCH-enterprise-policy.md`.

Cowork and Chat are **merging into one Claude**, announced 2026-09-16, staged
Pro/Max → Team/Free → Enterprise with 30 days' notice to Enterprise admins.
`SOURCE` · HIGH. Whether Claude Code stays a separate mode after the merge is
**UNVERIFIABLE first-party**: the announcement body never names Claude Code at
all, and on re-fetch only one of three secondary outlets (9to5Mac) carries the
two-mode claim. `surfaces-desktop/VERIFICATION.md` row 3b. Current docs still
describe three tabs — documentation lag on a rolling change, not a contradiction.

## `RenderSurface` and what depends on it

```ts
export type RenderSurface = 'terminal' | 'desktop' | 'mobile' | 'vscode';
```

Four values. **No `cowork`, no `chat`, no `web`.** A browser tab maps to no
value, which is a gap rather than a denial. `SOURCE` · HIGH. The per-surface
element table is in `research-api-surface.md`.

Three distinct failure cases for a UI-dependent mod, which are not the same
thing: `SOURCE` · HIGH · `surfaces-desktop/RESEARCH-mods-surfaces.md`

1. **No surface at all** (`-p`, SDK). `surfaces()` empty. Nothing in the types
   describes `ui.open` throwing there, so what happens is **unknown**; branch on
   `isInteractive` or an empty `surfaces()`.
2. **A narrower table.** `$.ui.resolve(e)` returns `Elements[e.surface]`,
   narrowed on the surface, so destructuring `Raster` on desktop is a type error
   rather than a runtime surprise. This is the designed path.
3. **A pane the surface refuses.** A pane waits undrawn below 144 columns (110
   once asked), judged at each open, and a hook on `ui.open` may refuse it.

## The framing that matters for an investment decision

The plugin **format** already reaches every surface, and account-synced plugins
already carry hooks into Cowork and cloud sessions. A plugin shipping skills and
agents alongside a hooks module degrades gracefully everywhere; **one whose
entire value is the hooks module reaches almost nobody today.**
`INFERRED` · HIGH-supported · `surfaces-desktop/RESEARCH.md`.

Reaching Cowork and Chat users at all requires the claude.ai account/org plugin
path, not a git marketplace — a publishing choice that gates any non-CLI reach
regardless of how function hooks land. `SOURCE` · HIGH.
