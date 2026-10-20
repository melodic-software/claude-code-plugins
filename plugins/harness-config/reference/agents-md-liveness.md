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

## Availability: any listed condition ends the question

Our checks treat `AGENTS.md` support as unavailable, so that no `AGENTS.md` is read natively at
any path under any mode, when any one of the conditions the pointer lists holds for the session.
Read the list and its version floors live; this file keeps no copy of them. The conditions fall into
three kinds, which decide how each resolves: a version comparison (against a floor that can depend
on the provider and telemetry configuration), whether the built-in plugin is disabled, and whether
this may be the first session after an upgrade.

For such a session the remedy we recommend is a `CLAUDE.md` that imports the `AGENTS.md`.

- **Pointer**: when deciding whether `AGENTS.md` support is available, fetch
  [memory: when AGENTS.md support is unavailable](https://code.claude.com/docs/en/memory#when-agents-md-support-is-unavailable)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: a condition is added to or removed from that section's list, or its remedy
  changes.

**No hooks setting is an availability condition.** The built-in plugin that reads `AGENTS.md` is a
built-in mod, so our
checks never count `disableAllHooks`, `allowManagedHooksOnly`, `--bare` or `--safe-mode` against
it. A session that loads no instruction files at all (`--bare` without `--add-dir`, `--safe-mode`,
`CLAUDE_CODE_DISABLE_CLAUDE_MDS`) reads no `AGENTS.md` either.

- **Pointer**: when deciding which settings stop built-in mods, fetch
  [mods overview: mods built into Claude Code](https://code.claude.com/docs/en/plugins/mods/overview#mods-built-into-claude-code)
  and
  [settings reference: what runs under `allowManagedHooksOnly`](https://code.claude.com/docs/en/settings-reference#what-runs-under-allowmanagedhooksonly)
  live; for the plugin's own statement, read its
  [README](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md) at commit
  `2282079d6ac8`.
- **As of**: 2026-10-18 for the two docs sections; 2026-10-01 for the README commit.
- **Recheck trigger**: the overview's built-in-mods section or the settings reference's
  `allowManagedHooksOnly` section changes which settings stop built-in mods, or the README's
  settings paragraph changes.

**Two of the three kinds resolve from what this plugin already reads.** A version condition is a
comparison against the floor the pointer states, plus the provider and telemetry configuration
where the floor depends on them. Plugin enablement is whether the built-in plugin that reads
`AGENTS.md` is enabled, which the permission-and-settings lanes already inventory. The
first-session-after-upgrade condition resolves only as "this may be that session", so it is the one
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
read the `instructionFiles` option under the built-in plugin's entry in `pluginConfigs`, from user
settings (`~/.claude/settings.json`), a `--settings` file or managed settings, and ignore the entry
in project and local settings files. The plugin has had more than one id, and a settings file may
carry its entry under any id the pointer says the installed version reads; read every such id, not
one, and treat a value found under any of them as set.

- **Pointer**: when locating the stored value, fetch
  [memory: choose which instruction files load](https://code.claude.com/docs/en/memory#choose-which-instruction-files-load)
  live for the plugin ids, which ids each version reads, the honored scopes and the JSON shape; for
  the `--settings` and `pluginConfigs` scopes, see
  [settings: change a setting for one session](https://code.claude.com/docs/en/settings#change-a-setting-for-one-session)
  and [settings reference: pluginConfigs](https://code.claude.com/docs/en/settings-reference#pluginconfigs).
- **As of**: 2026-10-11
- **Recheck trigger**: the option key changes, a plugin id is added or retired, the settings guide
  stops letting `--settings` set user-scope keys, the `pluginConfigs` scope changes, or the setting
  becomes readable from project or local settings.

Because the honored scopes are user, `--settings` and managed, resolve the **effective** value
across them. Reading one scope answers the wrong question in both directions: a user scope naming
the default can be overridden by a managed one, and the reverse.

**The legacy key still counts.** Read `projectInstructions` under the same plugin entry, at every id
above, as well as `instructionFiles`:

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
