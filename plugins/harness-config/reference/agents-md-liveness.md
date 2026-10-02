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
`harness-config` without any sibling, and `harness-config` declares no dependency on one, so a pointer
into another plugin's private reference would leave these conditions unresolvable in an ordinary
standalone install. Each record below cites the upstream page directly. Where a sibling plugin keeps
its own record of the same upstream fact, that is a parallel record, not this one's source.

## Availability: three documented conditions, any one of which ends the question

- **Claim**: in these sessions "Claude reads `CLAUDE.md` files only, and **Project instructions**
  doesn't appear in the `/config` settings panel", so no `AGENTS.md` is read natively at any path
  under any mode:
  1. "You're on a Claude Code version before v2.1.277";
  2. "You disabled the built-in `agents-md` plugin in `/plugin`";
  3. "In some cases, it's your first session after you upgrade from v2.1.276 or earlier. Claude
     reads `AGENTS.md` from your next session on".

  The page adds a version-bounded fourth: "Before v2.1.281, some sessions, such as those on Amazon
  Bedrock or with telemetry disabled, read `CLAUDE.md` files only. On those versions, update Claude
  Code." Its remedy for every one of these sessions is the shim: "To give Claude your `AGENTS.md` in
  any of these sessions, import it from a `CLAUDE.md`."
- **Basis**: <https://code.claude.com/docs/en/memory>, "When AGENTS.md support is unavailable",
  fetched as raw markdown 2026-10-01 (50,074 bytes). The 2.1.281 entry of the
  [changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) reads "Changed
  AGENTS.md support to also work on Amazon Bedrock, Google Vertex AI, Microsoft Foundry, LLM
  gateways, and sessions with telemetry disabled".
- **As of**: 2026-10-01, Claude Code 2.1.287.
- **Recheck trigger**: a condition is added to or removed from that list, the list's opening claim
  changes, the pre-2.1.281 sentence changes, or the remedy sentence changes.

**No hooks setting is an availability condition.** "The settings and flags that stop installed mods,
such as `disableAllHooks`, `--bare`, and `--safe-mode`, don't stop built-in mods", and
`agents-md@builtin` is one ([mods overview](https://code.claude.com/docs/en/plugins/mods/overview),
"Mods built into Claude Code", fetched 2026-10-01). Under `allowManagedHooksOnly`, "Mods built into
Claude Code keep running" ([settings reference](https://code.claude.com/docs/en/settings-reference),
"What runs under `allowManagedHooksOnly`", fetched 2026-10-01). The
[plugin's README](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md),
commit `2282079d6ac8`, agrees: "No hooks setting or CLI mode turns it off". Where the engine
loads no instruction files at all (`--bare` without `--add-dir`, `--safe-mode`,
`CLAUDE_CODE_DISABLE_CLAUDE_MDS`), it finds no `AGENTS.md` either, per that README. Recheck when the
overview's built-in sentence or the README's paragraph changes.

**All three are resolvable or bounded.** Condition 1 is a version comparison, and so is the
pre-2.1.281 provider and telemetry gap. Condition 2 is whether `agents-md@builtin` is enabled.
Condition 3 is resolvable only as "this may be that session", so it is the one that commonly stays
unresolved. Resolve what is resolvable first, because a condition known TRUE settles it with no
further work.

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
  table, fetched 2026-10-01.
- **As of**: 2026-10-01.
- **Recheck trigger**: a value is added, removed or renamed, the default moves, or a value's
  description changes which files it loads.

**Where the value lives**, which is what a check reads rather than the `/config` panel:

- **Claim**: "Add it under the built-in `agents-md` plugin's ID in `pluginConfigs`, in
  `~/.claude/settings.json`, a `--settings` file, or managed settings. **Claude Code ignores it in
  project and local settings files.**" The documented shape is the `instructionFiles` option under
  the `agents-md@builtin` key.
- **Basis**: the same section, its settings paragraph and JSON example.
- **As of**: 2026-10-01.
- **Recheck trigger**: the option key or plugin id changes, the honored scope set changes, or the
  setting becomes readable from project or local settings.

Because the honored scopes are user, `--settings` and managed, resolve the **effective** value
across them. Reading one scope answers the wrong question in both directions: a user scope naming
the default can be overridden by a managed one, and the reverse.

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
