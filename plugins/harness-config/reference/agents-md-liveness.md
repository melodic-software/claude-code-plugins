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

**No hooks setting is an availability condition.** `agents-md@builtin` is a built-in mod, so our
checks never count `disableAllHooks`, `allowManagedHooksOnly`, `--bare` or `--safe-mode` against
it. A session that loads no instruction files at all (`--bare` without `--add-dir`, `--safe-mode`,
`CLAUDE_CODE_DISABLE_CLAUDE_MDS`) reads no `AGENTS.md` either.

- **Pointer**: for which settings stop built-in mods, see the "Mods built into Claude Code"
  section of <https://code.claude.com/docs/en/plugins/mods/overview> and the "What runs under
  `allowManagedHooksOnly`" section of <https://code.claude.com/docs/en/settings-reference>; for the
  plugin's own statement, its
  [README](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md) at commit
  `2282079d6ac8`.
- **As of**: 2026-10-01
- **Recheck trigger**: the overview's built-in-mods section or the README's settings paragraph
  changes.

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
settings (`~/.claude/settings.json`) or managed settings, and ignore the key in project and local
settings files. A `--settings` file is unverified since the
[`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) entry stopped
naming the flag (as of 2026-10-07; recheck when the entry names `--settings` again or a probe shows
a `--settings` value read or ignored).

- **Pointer**: for where the setting is honored and its JSON shape, see
  <https://code.claude.com/docs/en/memory#choose-which-instruction-files-load>.
- **As of**: 2026-09-21
- **Recheck trigger**: the option key or plugin id changes, the honored scope set changes, or the
  setting becomes readable from project or local settings.

Because the honored scopes are user and managed, resolve the **effective** value across them.
Reading one scope answers the wrong question in both directions: a user scope naming the default
can be overridden by a managed one, and the reverse.

**The legacy key still counts.** Read `projectInstructions` under the same `agents-md@builtin`
entry as well as `instructionFiles`:

- **Claim**: the option was first keyed `projectInstructions`, with the values `claude`,
  `agents-fallback`, `both` and `none`. While `instructionFiles` reads as its default, a stored
  `projectInstructions` value is honored: `none` as `managed-only`, `claude` as `claude-md`,
  `agents-fallback` as `claude-md-or-agents-md`, `both` as `claude-md-and-agents-md`, and any other
  value as `claude-md`. Once `instructionFiles` is set to anything but its default, the old key is
  not read, and the session says so: "option projectInstructions in settings is not read:
  instructionFiles ... is set; remove projectInstructions".
- **Basis**: the
  [plugin's README](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md),
  "Setting the option", commit `2282079d6ac8` (2026-09-30), read 2026-10-01; the quoted warning
  is a string in the Claude Code 2.1.287 binary. The memory page does not mention the old key.
- **As of**: 2026-10-01, Claude Code 2.1.287.
- **Recheck trigger**: the README drops or changes the paragraph, or a release note removes
  `projectInstructions`.

So a `projectInstructions` value with no `instructionFiles` beside it sets the effective mode, and
`none` or an unknown value makes `AGENTS.md` unread.

## Where a read `AGENTS.md` differs from a `CLAUDE.md`

- **Claim**: an `AGENTS.md` read through the **Project instructions** setting differs from a
  `CLAUDE.md` in three documented places. `InstructionsLoaded` hooks don't fire for it (they do for
  an `AGENTS.md` a `CLAUDE.md` imports or symlinks to). Directories added with `--add-dir` while
  `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` is set load their `CLAUDE.md` but not their
  `AGENTS.md`. An `@path` import of a file outside the working directory loads "only if you already
  approved external imports for this project, with no prompt". A nested `AGENTS.md` attaches when
  Claude opens a file in its directory with the Read tool.
- **Basis**: <https://code.claude.com/docs/en/memory>, "Where AGENTS.md differs from CLAUDE.md"
  table and "When Claude Code reads AGENTS.md", fetched 2026-10-01. The plugin's README lists more
  loader differences under "Where it still differs from CLAUDE.md", such as a nested file attaching
  on a text `Read` only, not on an `@`-mention or an IDE selection; where it and the memory page
  disagree (the README says `/memory` does not know `AGENTS.md` files; the memory page says to run
  `/memory` to check one, and that only versions before v2.1.280 omitted it), the memory page wins.
- **As of**: 2026-10-01.
- **Recheck trigger**: a row is added to or removed from that table.

What this changes for a check: an `AGENTS.md` under an `--add-dir` directory is never a live
surface on its own, and an `InstructionsLoaded` hook log is no evidence that a natively read
`AGENTS.md` did or did not load.

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
