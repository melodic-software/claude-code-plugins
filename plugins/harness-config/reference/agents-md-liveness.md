# Whether a session reads an `AGENTS.md`: availability, then the mode

Every check in this plugin that decides whether an `AGENTS.md` is a live instruction surface turns
on two questions, in this order: is `AGENTS.md` support **available** in the session at all, and if
so, which files does the **Project instructions** setting load. Both are recorded here in the
shape the
[upstream-drift convention](../../../docs/conventions/upstream-drift/README.md#required-parts)
defines: our decision, a pointer to the upstream section, the as-of date, the recheck trigger.

**Why the record lives here.** A plugin never imports files from a sibling plugin
([plugin philosophy](../../../docs/plugin-philosophy.md), "It never imports files from a sibling
plugin or discovers another plugin's installation directory"). A consumer can install
`harness-config` without any sibling, and `harness-config` declares no dependency on one, so a pointer
into another plugin's private reference would leave these conditions unresolvable in an ordinary
standalone install. Each record below cites the upstream page directly. Where a sibling plugin keeps
its own record of the same upstream fact, that is a parallel record, not this one's source.

## Availability: three conditions, any one of which ends the question

Our checks treat `AGENTS.md` support as unavailable, so that no `AGENTS.md` is read natively at
any path under any mode, when any one of these holds for the session:

1. the Claude Code version is below v2.1.277, or below v2.1.281 in a session that fetches no
   feature flags from Anthropic (a third-party provider such as Amazon Bedrock, or telemetry
   disabled);
2. the built-in `agents-md` plugin is disabled in `/plugin`;
3. it may be the first session after an upgrade from a version without `AGENTS.md` support.

For such a session the remedy we recommend is a `CLAUDE.md` that imports the `AGENTS.md`.

- **Pointer**: for when `AGENTS.md` support is unavailable and the import remedy, see
  <https://code.claude.com/docs/en/memory#when-agents-md-support-is-unavailable>.
- **As of**: 2026-10-01
- **Recheck trigger**: a condition is added to or removed from that section's list, a version
  floor in it moves, or its remedy changes.

**Two of the three resolve from what this plugin already reads.** Condition 1 is a version
comparison, plus the provider and telemetry configuration on a CLI between the two floors.
Condition 2 is whether the built-in `agents-md` plugin is enabled, which the permission-and-settings
lanes already inventory. Condition 3 resolves only as "this may be that session", so it is the one
that commonly stays unresolved. Do not treat the whole question as unresolvable because one
condition is: resolve what is resolvable first, because a condition known TRUE settles it with no
further work.

## The mode: four values, and where the value lives

Our checks read the **Project instructions** setting as one of four values:

- `claude-md-or-agents-md`, the default: an `AGENTS.md` loads only where no `CLAUDE.md` or
  `CLAUDE.local.md` sits in the working directory or above it (displacement).
- `claude-md-and-agents-md`: both load, `CLAUDE.md` first per directory, and an `AGENTS.md` that a
  `CLAUDE.md` already imports or symlinks counts once.
- `claude-md` and `managed-only`: no `AGENTS.md` loads.

**So two of the four values make an `AGENTS.md` unread regardless of displacement**, and
displacement is a condition of the default value alone.

- **Pointer**: for the values and what each loads, see
  <https://code.claude.com/docs/en/memory#choose-which-instruction-files-load>.
- **As of**: 2026-09-21
- **Recheck trigger**: a value is added, removed or renamed, the default moves, or a value changes
  which files it loads.

**Where the value lives**, which is what a check reads rather than the `/config` panel: our checks
read the `instructionFiles` option under the `agents-md@builtin` key of `pluginConfigs`, from user
settings (`~/.claude/settings.json`), a `--settings` file or managed settings, and ignore the key
in project and local settings files.

- **Pointer**: for where the setting is honored and its JSON shape, see
  <https://code.claude.com/docs/en/memory#choose-which-instruction-files-load>.
- **As of**: 2026-09-21
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
