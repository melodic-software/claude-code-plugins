# Whether a session reads an `AGENTS.md`: the three gates

Every check in this plugin that decides whether an `AGENTS.md` is a live instruction surface turns
on the same three conditions. They are recorded here, in this plugin, as the four-part record the
[upstream-drift convention](../../../../../docs/conventions/upstream-drift/README.md) defines:
claim, basis, as-of date, recheck trigger.

**Why the record lives here.** A plugin never imports files from a sibling plugin
([plugin philosophy](../../../../../docs/plugin-philosophy.md), "It never imports files from a
sibling plugin or discovers another plugin's installation directory"). A consumer can install
`claude-config` without any sibling, and `claude-config` declares no dependency on one, so a pointer
into another plugin's private reference would leave these gates unresolvable in an ordinary
standalone install. Each record below therefore cites the upstream page directly. Where a sibling
plugin keeps its own record of the same fact, that is a parallel record of a shared upstream truth,
not this one's source.

**All three gates must hold.** A gate known false excludes the file regardless of the others; a gate
merely unresolved leaves it included, which puts the conservative direction where the answer is
unknown rather than where it is known to be no. The consuming check states which direction its own
lane errs in.

## Gate 1: the instruction-files mode

- **Claim**: the **Project instructions** setting chooses which of the two filename families load.
  Its default value is `claude-md-or-agents-md`, under which a `CLAUDE.md`, `.claude/CLAUDE.md` or
  `CLAUDE.local.md` in the working directory or any directory above it makes Claude Code read those
  instead of an `AGENTS.md`. Under `claude-md-and-agents-md` **both** load, in the order "each
  directory's `CLAUDE.md` files first and its `AGENTS.md` after them", so an `AGENTS.md` beside a
  `CLAUDE.md` is live. A file already loaded is not read twice: "Claude Code skips an `AGENTS.md`
  it has already loaded, so one that your `CLAUDE.md` imports or symlinks to isn't read twice."
- **Basis**: <https://code.claude.com/docs/en/memory>, "Choose which instruction files load", and
  "When Claude Code reads AGENTS.md".
- **As of**: 2026-09-19.
- **Recheck trigger**: that section renames a value, changes the default, changes the stated load
  order, or drops the skip-if-already-loaded sentence.

**Scope.** The setting is a user, `--settings` or managed one, and is ignored in project and local
settings, so no repository can ship it and reading a single scope answers the wrong question in
both directions. Resolve the **effective** value across those scopes.

- **Basis**: the same page's settings table, read together with
  <https://code.claude.com/docs/en/settings> on which scopes a user-level key is honoured in.
- **As of**: 2026-09-19.
- **Recheck trigger**: the setting becomes readable from project or local settings.

## Gate 2: the CLI version floor

- **Claim**: "Reading `AGENTS.md` directly requires Claude Code v2.1.277 or later."
- **Basis**: <https://code.claude.com/docs/en/memory>, the AGENTS.md section.
- **As of**: 2026-09-20.
- **Recheck trigger**: the page states a different floor, or drops the sentence.

## Gate 3: the remote feature flag

- **Claim**: reading `AGENTS.md` directly is gated on a remote feature flag, so a session on a
  new enough CLI still may not read the file. The flag's code default is off in the builds examined.
- **Basis**: <https://code.claude.com/docs/en/memory>, which states the capability is being rolled
  out, together with the shipped bundle read as bytes. The bundle reading is machine-local and per
  build, so it is evidence for a given install rather than a portable claim.
- **As of**: 2026-09-20.
- **Recheck trigger**: the page stops describing the reading as gated, or announces general
  availability.

## What a check does with an unresolved gate

Neither the flag nor the effective mode is reliably readable from inside an audit, so "unresolved"
is the common case rather than the exception, and each lane picks the direction that cannot invent
work:

- **Inventory lanes** (`audit-instructions` Phase A, `audit-prompting-postures`' surface set)
  record the file when every gate is satisfied **or unresolved**. Inventorying is additive: it
  bounds what may produce a finding, and cannot by itself produce one.
- **Finding lanes** (I14's redundant-read check, I15's comparison set and its co-residency row)
  leave the surface alone when a gate is unresolved. Flagging a read proposes deleting the only
  thing that loads the file, and pairing a non-resident surface reports a conflict against
  something nothing loads.
