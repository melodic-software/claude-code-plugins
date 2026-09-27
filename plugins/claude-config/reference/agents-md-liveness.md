# Whether a session reads an `AGENTS.md`: availability, then the mode

Every check in this plugin that decides whether an `AGENTS.md` is a live instruction surface turns
on two questions, in this order: is `AGENTS.md` support **available** in the session at all, and if
so, which files does the **Project instructions** setting load. Both are recorded here as the
four-part record the
[upstream-drift convention](../../../docs/conventions/upstream-drift/README.md) defines: claim,
basis, as-of date, recheck trigger.

**Why the record lives here.** A plugin never imports files from a sibling plugin
([plugin philosophy](../../../docs/plugin-philosophy.md), "It never imports files from a sibling
plugin or discovers another plugin's installation directory"). A consumer can install
`claude-config` without any sibling, and `claude-config` declares no dependency on one, so a pointer
into another plugin's private reference would leave these conditions unresolvable in an ordinary
standalone install. Each record below cites the upstream page directly. Where a sibling plugin keeps
its own record of the same upstream fact, that is a parallel record, not this one's source.

## Availability: four documented conditions, any one of which ends the question

- **Claim**: in these sessions "Claude reads `CLAUDE.md` files only, and **Project instructions**
  doesn't appear in the `/config` settings panel", so no `AGENTS.md` is read natively at any path
  under any mode:
  1. "You're on a Claude Code version before v2.1.277";
  2. "Your session doesn't fetch feature flags from Anthropic, for example because you use Amazon
     Bedrock or another third-party provider, or you disabled telemetry. The linked section has the
     full list";
  3. "It's your first session after you install or upgrade to a version with `AGENTS.md` support.
     Claude reads `AGENTS.md` from your next session on";
  4. "You or your organization set `disableAllHooks` or `allowManagedHooksOnly`, or you disabled the
     built-in `agents-md` plugin in `/plugin`".

  The page's own remedy for these sessions is the shim: "To give Claude your `AGENTS.md` in these
  sessions, import it from a `CLAUDE.md`."
- **Basis**: <https://code.claude.com/docs/en/memory>, "When AGENTS.md support is unavailable".
- **As of**: 2026-09-21.
- **Recheck trigger**: a condition is added to or removed from that list, the list's opening claim
  changes, or the remedy sentence changes.

**Three of the four are resolvable, and two of those from settings this plugin already reads.**
Condition 1 is a version comparison. Condition 4 is `disableAllHooks`, `allowManagedHooksOnly` and
whether the built-in `agents-md` plugin is enabled, all of which the permission-and-settings lanes
already inventory. Condition 3 is resolvable only as "this may be that session" and condition 2
only from the provider and telemetry configuration, so those two are the ones that commonly stay
unresolved. Do not treat the whole question as unresolvable because one condition is: resolve what
is resolvable first, because a condition known TRUE settles it with no further work.

## The mode: four values, and where the value lives

- **Claim**: the **Project instructions** setting takes one of four values.
  `claude-md-or-agents-md` reads "Your `CLAUDE.md` files, or your `AGENTS.md` files when you have no
  `CLAUDE.md` or `CLAUDE.local.md` in your working directory or above it. **This is the default**".
  `claude-md-and-agents-md` reads both, "each directory's `CLAUDE.md` files first and its
  `AGENTS.md` after them", and "Claude Code skips an `AGENTS.md` it has already loaded, so one that
  your `CLAUDE.md` imports or symlinks to isn't read twice". `claude-md` reads "Your `CLAUDE.md`
  files only". `managed-only` reads "Only your organization's managed `CLAUDE.md` and auto memory at
  launch", and under it "every `AGENTS.md`" is left out.
  **So two of the four values make an `AGENTS.md` unread regardless of displacement**, and
  displacement is a condition of the default value alone.
- **Basis**: <https://code.claude.com/docs/en/memory>, "Choose which instruction files load", value
  table.
- **As of**: 2026-09-21.
- **Recheck trigger**: a value is added, removed or renamed, the default moves, or a value's
  description changes which files it loads.

**Where the value lives**, which is what a check reads rather than the `/config` panel:

- **Claim**: "Add it under the built-in `agents-md` plugin's ID in `pluginConfigs`, in
  `~/.claude/settings.json`, a `--settings` file, or managed settings. **Claude Code ignores it in
  project and local settings files.**" The documented shape is the `instructionFiles` option under
  the `agents-md@builtin` key.
- **Basis**: the same section, its settings paragraph and JSON example.
- **As of**: 2026-09-21.
- **Recheck trigger**: the option key or plugin id changes, the honored scope set changes, or the
  setting becomes readable from project or local settings.

Because the honored scopes are user, `--settings` and managed, resolve the **effective** value
across them. Reading one scope answers the wrong question in both directions: a user scope naming
the default can be overridden by a managed one, and the reverse.

## What a check does with an unresolved condition

Resolve first, then fall back. A condition known false settles the question cheaply, and several are
knowable. Where one genuinely cannot be resolved for the session under audit, each lane errs in the
direction that cannot invent work:

- **Inventory lanes** (`audit-instructions` Phase A) record the file when every condition is
  satisfied **or unresolved**. Inventorying is additive there: it bounds what may produce a finding
  and cannot by itself produce one.
- **`audit-prompting-postures`' surface set** also records it, but inventorying is not additive in
  that skill, because its Phase C emits a verdict for every inventoried component. It records the
  file and emits `NOT-APPLICABLE` with the unresolved condition as the failed predicate.
- **Finding lanes** (I14's redundant-read check, I15's comparison set and its co-residency row)
  leave the surface alone when a condition is unresolved. Flagging a read proposes deleting the only
  thing that loads the file, and pairing a non-resident surface reports a conflict against something
  nothing loads.
- **`unhobble`'s strip candidacy** keeps a file whose availability is merely unresolved, and keeps
  any file a `CLAUDE.md` imports or symlinks regardless of availability, since that import is
  itself a live path into context.
