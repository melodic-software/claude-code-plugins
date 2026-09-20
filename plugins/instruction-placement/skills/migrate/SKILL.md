---
description: "Move a repository's instruction content to AGENTS.md as the one content home, keeping a one-line `@AGENTS.md` CLAUDE.md shim while a shim is what makes it load. Plans first with a read-only script: one state per directory, Codex's byte budget per root-to-directory path, case-variant filenames, home suppressors, code that finds a path by the existence of CLAUDE.md, links into CLAUDE.md, and every claude-code-action pin. Then splits content by where each kind belongs: every-conversation text in the root AGENTS.md, sometimes-relevant text in the repo's own docs home behind a pointer, Claude-specific text in `.claude/rules/` with a `paths:` glob. Every write is operator-gated; load is verified, never assumed. Use when: 'migrate to AGENTS.md', 'move CLAUDE.md content to AGENTS.md', 'make AGENTS.md the source of truth', 'add the AGENTS.md shim', 'our CLAUDE.md should be one line', 'share instructions with Codex and Cursor', 'plan the AGENTS.md migration'. Not for removing shims: that is a separate cutover."
argument-hint: "[plan | apply] [path ...]. Default: plan the repository at the current root"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  [
    "Bash(${CLAUDE_PLUGIN_ROOT}/skills/migrate/scripts/plan-migration.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh:*)",
    "Read",
    "Grep",
    "Glob",
    "Edit",
    "Write",
    "WebFetch",
  ]
metadata:
  workflow-stage: implement
  summary: Move a repository's instruction content to AGENTS.md behind an operator gate
---

# Migrate a repository to AGENTS.md

## Purpose

One tool-agnostic instruction source per repository, small enough to load every session, readable
by Codex, Cursor and every other agent that reads `AGENTS.md`, and still reaching Claude Code in the
sessions that cannot read `AGENTS.md` directly.

Two mutating skills live in this plugin. `/instruction-placement:realign` executes findings a
sibling audit produced, one at a time. This one owns a different unit of work: a repository's move
from `CLAUDE.md` to `AGENTS.md` as the content home, which is a decision about a whole instruction
layer rather than a list of findings. It gates every write on the operator just as `realign` does.

**Removing shims is not this skill's job today.** That is a cutover with upstream conditions of its
own, and it ships separately. Never delete a `CLAUDE.md` shim here, however unnecessary it looks.

## Invocation mode

`disable-model-invocation: false`, the fleet default. No exception class in the
[invocation-mode rubric](../../../../docs/conventions/invocation-mode/README.md) fits: this is not a
`setup` skill (class ii), not maintainer-only (class iii), and not class (i) either, since the human
already decides every write at the gate below rather than deciding the *timing* of an unattended
mutation. It is also a chain target: `/claude-memory:audit`'s N1 fix route and this plugin's own
`setup` remediation both point a repository here, and the invocation-reach invariant makes a `true`
skill unreachable from another skill.

## The target shape

- The root `CLAUDE.md` is exactly the one line `@AGENTS.md`. No heading, no comment, no other text.
- Every directory with a Claude-audience nested `AGENTS.md` has a sibling `CLAUDE.md` that is
  exactly `@AGENTS.md`.
- `AGENTS.md` carries the content. `CLAUDE.md` carries nothing but the import.
- `.cursor/`, `.codex/` and `.github/` belong to those tools. Their instruction files are never
  given a Claude shim and never merged into `AGENTS.md`.

## Where each kind of text goes

Each kind of text goes to the best current native location for it. That is the whole convention;
the three destinations below follow from it.

| Text | Destination | Why |
|---|---|---|
| Shared, relevant to **every** conversation | root `AGENTS.md` | It has to be resident, and every agent reads this file |
| Shared, relevant **sometimes** | the repository's **existing docs home**, behind a one-line pointer in `AGENTS.md` that says *when* to read it | It earns its place only at the moment it applies, and a resident copy taxes every session |
| **Claude-specific** | `.claude/rules/<topic>.md` with a `paths:` glob, or a stated always-relevant reason | Other tools never read it, and the glob is what makes the cost conditional |
| **Tool-agnostic but about one file or area** | Short: stays resident in root `AGENTS.md`. Long: the docs home, behind a pointer whose condition names the file. Scoped to one directory: a nested `AGENTS.md` | `AGENTS.md` has no path scoping, and `.claude/rules/` would hide it from the other tools that need it. Length decides between resident and pointer; a directory boundary is what makes the nested file fit |
| Another tool's | that tool's own directory, untouched | It is theirs |

The docs home is **detected, never imposed**: `plan-migration.sh` emits a `DOCSHOME` row naming the
directory the repository already keeps (`docs/`, `doc/`, `documentation/`). Use that one. Create
`docs/` only when the row says `absent`, and never relocate an existing home as part of a migration.

A pointer is not a summary. One line naming the file and the condition that should send a reader to
it ("Read `docs/release-process.md` before cutting a release") beats a paragraph restating it.

`/docs-hygiene:write-for-agents` owns how this text is written: invoke it via the Skill tool when
that plugin is installed, for the root `AGENTS.md`, every new `.claude/rules/` file, and every
pointer. Where it is not installed, write the text here and say that the write-side doctrine was
not available, rather than skipping the move.

## Plan first

```bash
${CLAUDE_PLUGIN_ROOT}/skills/migrate/scripts/plan-migration.sh --root <repo>
```

**Always pass `--root`.** A shell's working directory does not persist between tool calls, so a run
without it plans whatever directory the call happened to land in. `--root` may point anywhere inside
the repository; the script resolves to the toplevel itself.

Read-only: it has no other mode, and `--dry-run` is accepted and ignored so an older caller does
not break. A kind with nothing to report prints a
tab-separated `<KIND>` / `NONE` row, so a clean repository is visibly clean rather than
indistinguishable from a run that never happened. Its rows are the facts a migration turns on:

| Row | What it decides |
|---|---|
| `DIR` | `<path> <state> <CLAUDE.md bytes> <AGENTS.md bytes>`. The state names the work; the table below says what Apply does for each |
| `BUDGET` | `<path> <cumulative AGENTS.md bytes, root to that path> <OK\|OVER>`, against Codex's project-doc budget, which is cumulative across the files it loads rather than per file. The number and its dated record live beside `CODEX_PROJECT_DOC_BUDGET` in `scripts/plan-migration.sh`; read it there rather than restating it. `OVER` means content has to move out before the migration, not after |
| `CASE` | A filename differing only by case. Claude Code matches names exactly; NTFS does not, so the repository behaves differently per developer until it is renamed |
| `SUPPRESS` | A bare `~/CLAUDE.md` or `~/CLAUDE.local.md`. Present, it is read instead of `AGENTS.md` in every directory below home, and no repository-side change fixes that |
| `PATHDET` | Code that finds a path by the existence of `CLAUDE.md`. Each one works while the shim exists and breaks at cutover. Report them; fixing them is not this run's scope unless the operator asks |
| `CITE` | A markdown link resolving into `CLAUDE.md`. Each is retargeted in the same PR as the content move, or the link dies |
| `MENTION` | Every other tracked occurrence of the literal `CLAUDE.md`: a YAML list entry, a comment, a path in a config, including under `.claude/`, which is where a Claude-configured repo most often enumerates its own instruction files. Neither a link nor an existence call, so it is nobody else's row. A content directory holding more than ten is rolled up to `<dir>/ <count> rows`; `.claude/` and `.github/` never are, because a leak lives in configuration. `--expand-mentions` prints them all. **A roll-up is the answer, not a deferral**: a content directory (captured prose, vendored docs) is reported by count and left alone, because every one of its mentions is the same non-finding. Triage the individually-listed rows with the operator |
| `DOCSHOME` | Where a pointer target lands |
| `ACTION` | Every `claude-code-action` pin. Each decides the CLI version CI installs, and so whether CI reads `AGENTS.md` at all |

Present the plan, with the content split you propose per file, and stop. Nothing is written until
the operator accepts.

**Dispatched runs.** Where this skill runs under a brief that already states the accepted target
shape, that brief is the acceptance, and the plan output is still returned to the dispatcher with
the work. The worker triages the `MENTION`, `CITE`, `PATHDET` and `ACTION` rows and returns that
triage in its report; anything needing a write **outside** the accepted target shape is the
dispatcher's decision, not the worker's. This changes nothing for an interactive run: there, the
operator still accepts before anything is written.

**"Nothing to split" is a valid outcome, not a failure to find work.** A small root file whose
content is all every-conversation material stays whole in the root `AGENTS.md`. Steps 2 and 3 then
produce nothing, and no `docs/` directory and no `.claude/rules/` file is created. Say that plainly
rather than manufacturing a pointer or a rule to have something to show.

Likewise, **a repository with no Claude-specific text creates no `.claude/rules/` file and never
calls `glob-tools.sh`**. That is step 3 finding nothing to do, not step 3 being skipped; report it
as a result so nobody reads the absence as an omission.

## Apply

**The shortest path per `DIR` state.** Most directories need a fraction of the full sequence, and a
step with nothing to do is a result, not an omission:

| State | What Apply does |
|---|---|
| `agents-only` | **Create the shim only**: a `CLAUDE.md` containing exactly `@AGENTS.md`. Steps 1, 2, 3 and 5 are no-ops; step 6 still runs |
| `content-in-claude` | The full sequence: split the content, then create the shim where none existed |
| `both-with-content` | The full sequence, deciding per section which file it belongs in, then reduce `CLAUDE.md` to the import |
| `shim-with-comment` | **Strip the comment only.** The note moves into `AGENTS.md` or is deleted, the operator's call |
| `shim` | Nothing. Already the target shape; report it and move on |
| `zero-byte` | Nothing to move. Ask the operator whether the empty files are deliberate before touching them |

The full sequence, one directory at a time, deepest last, in this order, because an interruption
between steps must leave content duplicated rather than deleted:

0. **Fix any `CASE` row first**, before anything else touches the tree. A filename differing only by
   case means the repository already behaves differently per developer, and every later step would
   be built on a file whose identity is not settled.
1. **Create or extend `AGENTS.md`** with the content that belongs there. Merge under a new heading;
   never clobber an existing file. **Moved text moves verbatim.** The hard rule below wins over any
   write-side advice: `/docs-hygiene:write-for-agents` governs text you are *writing new* here
   (pointer lines, a rules file's always-relevant reason, a new heading), never text you are
   relocating. Rewording moved text is a separate, later edit the operator asks for by name.
2. **Write the pointer targets** into the detected docs home, and the pointer lines into `AGENTS.md`.
3. **Write the `.claude/rules/` files.** Fetch the current rules frontmatter format at authoring
   time rather than writing it from memory: `curl -sL https://code.claude.com/docs/en/memory.md`
   and read its "Path-specific rules" section. Validate every glob with
   `${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh` before the file is written; a glob matching
   nothing is a rule that never fires, and nothing goes red.
4. **Write the shim**: `CLAUDE.md` containing exactly `@AGENTS.md`, one line. Create it where the
   directory had none (the whole job for an `agents-only` row), or reduce an existing one to that
   line once its content has a home. An HTML-comment note inside a shim is content: move it into
   `AGENTS.md` or delete it with the operator's say-so.
5. **Retarget every `CITE` row** in the same change. A link into `CLAUDE.md` whose content moved is
   a dead link the moment the move lands, so it is not a follow-up.
6. **Offer the index; never write it unasked.** The generated rules index is a *Claude-only* block
   in the tool-agnostic `AGENTS.md`, and it is not free: in `medley` the render was 6,860 bytes,
   +52% on the always-loaded file, pushing the worst Codex path to 28,870 of its 32,768-byte
   budget. So run `render` first, report the byte cost and the resulting worst-path `BUDGET` row,
   and write it only on the operator's acceptance:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh render --root <repo>
   ${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh write --file AGENTS.md --root <repo>
   ```

   It earns its cost where deferred surfaces are many and a worker would otherwise never learn they
   exist. It does not where the repository has a handful of nested files a reader meets anyway, or
   where the budget is already tight. **A repository that declines the index is not broken**:
   `check` reports `NO-BLOCK` and `index-drift` stays quiet, because a repository that never
   adopted an index is not drifting from one. With nothing to index at all, `write` says
   `NO-INDEX-NEEDED` and writes nothing; do not hand-write a block in either case.
7. **Run the repository's own markdown lint**, if it has one: check for a `lint:md` script in
   `package.json`, a `lefthook.yml` markdown hook, or a `.markdownlint*` config, and run what you
   find. A regenerated block or a moved heading can trip MD022 (blanks around headings), MD024
   (duplicate headings, likely when a section lands beside a similar one) or MD047 (single trailing
   newline). **A fresh worktree may need the repository's own install step first** (`npm ci`,
   `uv sync`, `dotnet restore`, whatever its README names). A wall of failures on a markdown-only
   diff is unprovisioned tooling until something shows otherwise: check that before reading it as
   the migration's doing, and never "fix" source you did not touch to make a linter start.
8. **Re-run the plan** and confirm the states moved the way the operator accepted.

Where a directory has a nested `AGENTS.md`, `render-index.sh wiring` says whether it needs a shim:
an `UNWIRED` row does, a `NATIVE` row does not.

**Before writing nested shims, look for a gate that classifies changed paths by directory prefix.**
A hook or CI rule keyed on `apps/`, `libs/` or `services/` reads `<dir>/CLAUDE.md` as code and
applies a code lane to it; in `medley` that tripped a runtime-affecting pre-push gate. Grep the
hook and workflow configs for those prefixes, and report each as an item for the operator. **The
fix belongs to the repository's gate, through its own tests.** Teach it that an instruction file is
not code. Never bypass the gate, and never rename or relocate a shim to dodge it.

**The rows Apply does not act on, and where each goes instead.** Every one is reported, none is
silently dropped:

- `PATHDET`: listed in the PR body as a cutover blocker. This skill changes none of them. Code that
  finds a path by the existence of `CLAUDE.md` keeps working while the shim exists, and rewriting it
  is the cutover's business.
- `ACTION`: listed in the PR body for the cutover check, which is what reads the pins.
- `SUPPRESS`: reported to the operator as theirs. No repository-side change reaches a bare
  `~/CLAUDE.md`.
- `BUDGET` with `OVER`: content moves out before the migration proceeds in that subtree, not after.

## Verify the load, never assume it

`verify-load.sh` drives one real `claude -p` turn with an `InstructionsLoaded` hook and prints
`VERDICT PASS|FAIL|UNKNOWN`. **`UNKNOWN` (exit 3) is a third outcome, never a pass**: rerun once,
escalate if it stays. A canary counts only against a non-empty `AGENTS.md`.

Four legs, every one run, none assumed: `verify-load.sh` per migrated surface; `render-index.sh
reachable --file AGENTS.md --root <repo>` captured **before and after**, which is the root-level
parallel of `wiring` and the whole load evidence for an `agents-only` repository (`NATIVE` before
the shim, `LOADED` after); a headless Claude canary; and a Codex canary where that CLI is
installed. The worked invocations, where the canary token goes, the Codex rollout check, and the
progressive-disclosure caveat are in
[`reference/verification.md`](reference/verification.md). Read it before running any of them.

## Why the shim stays

The shim is what carries `AGENTS.md` in two cases a repository cannot talk itself out of: a
`CLAUDE.md` above the file being read instead of it, and a session that cannot read `AGENTS.md`
directly at all.

- **Claim**: Claude Code reads `AGENTS.md` as the project instructions only where there is no
  `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in the working directory or above it, and
  attaches a subdirectory's `AGENTS.md` on a Read there under the same condition. Reading it
  directly needs v2.1.277 or later and is unavailable in some sessions (some providers, telemetry
  disabled, `disableAllHooks` or `allowManagedHooksOnly` set, the built-in `agents-md` plugin
  disabled in `/plugin`, the first session after an install or upgrade). A `CLAUDE.md` containing
  `@AGENTS.md` never makes Claude read the file twice.
- **Basis**: [memory](https://code.claude.com/docs/en/memory), "AGENTS.md", "When Claude Code reads
  AGENTS.md", "When AGENTS.md support is unavailable", "Remove an earlier AGENTS.md workaround";
  confirmed by canary runs on Claude Code 2.1.278.
- **As of**: 2026-09-19.
- **Recheck trigger**: that page changes which file names count for the check or which sessions lack
  support, or a release note names `AGENTS.md` or instruction-file loading.

It is priced, not free. A directly read `AGENTS.md` is absent from `/memory` and the `/context`
Memory files, and fires no `InstructionsLoaded` hook; one reached through a shim behaves like part
of its `CLAUDE.md` and keeps both. That is a reason the shim is worth its ~55 tokens, and a reason
removing it later is a decision rather than tidying.

Every upstream fact the eventual cutover turns on lives as a four-part dated record in
[`reference/sources.md`](reference/sources.md): the remote flag and how its code default is read,
the documented feature-flag dependency, the CLI floor, the `claude-code-action` release to CLI map,
the CI canary result, and what shim removal costs. Read it before arguing about the shim from
memory. One record there bears on verification today: `verify-load.sh` detects a load through the
`InstructionsLoaded` hook, so it measures a **shimmed** surface and cannot see an `AGENTS.md` that
Claude reads directly.

**One setting changes the reading, and no repository can ship it.** Under `instructionFiles:
claude-md-and-agents-md`, Claude Code loads both files, "each directory's `CLAUDE.md` files first
and its `AGENTS.md` after them", so an unimported nested `AGENTS.md` does load and an `UNWIRED` row
is a false positive for that operator. The import stays harmless there: "Claude Code skips an
`AGENTS.md` it has already loaded, so one that your `CLAUDE.md` imports or symlinks to isn't read
twice". The value is a user, `--settings` or managed setting, ignored in project and local settings,
so a repository cannot rely on it and the gates keep the default's answer
([memory](https://code.claude.com/docs/en/memory), "Choose which instruction files load"; fetched
2026-09-19; recheck when that table changes or a release note names the setting).

## Hard rules

- **Never delete a `CLAUDE.md` shim.** Reducing one to its import line is this skill's work;
  removing it is the separate cutover.
- **Never create or move instruction files into `.cursor/`, `.codex/` or `.github/`.** Another
  tool's instruction file is not an unshimmed Claude surface, and no Claude shim or moved
  instruction text belongs in those trees. That is the whole rule: a CI or tooling file that merely
  *enumerates* instruction-file paths (a `DOCUMENTATION_ROOTS` list, a lint glob, a docs gate) is in
  scope for the move, because the move is what breaks it. Edit it minimally, add the new path rather
  than rewriting the gate, and show it to the operator as its own item.
- **Never rewrite content while moving it.** A relocation whose diff also improves the prose is a
  diff nobody can review.
- **Create the destination before excising the source.** An interruption then duplicates content
  rather than losing it.
- **Never report a load verified without probing it.** `UNKNOWN` is not `PASS`, and a canary against
  an empty `AGENTS.md` proves nothing.
- **Never leave the index stale.** Regenerating it is part of the move.

## Next

`/instruction-placement:check`. The gate that keeps every new `paths:` glob resolving and the index
in sync after the move.

## Gotchas

- **The root `CLAUDE.md` is what suppresses a nested `AGENTS.md`, so both move together.** A repo
  that adds nested `AGENTS.md` files while keeping a content-bearing root `CLAUDE.md` gets files
  that review as correct and load nothing.
- **`/init` writes `CLAUDE.md`.** Running it after a migration re-creates the content the migration
  moved out. Say so in the PR body of a repository whose contributors run it.
- **A `CLAUDE.md` that tells Claude in prose to read `AGENTS.md` does not load it.** Only an
  `@AGENTS.md` import does. Replace the sentence, never keep it as a belt.
- **A committed symlink is not portable.** On a Windows checkout it materializes as a plain text
  file holding the link target, so the import is the form that works everywhere.
- **A `CLAUDE.local.md` one developer keeps silently turns `AGENTS.md` off for them.** It counts for
  the same check as `CLAUDE.md`, and no gate in the repository can see it.
- **Codex truncates past its project-doc budget**, which is one cumulative allowance across the
  files it loads, not a per-file cap (the dated record is beside `CODEX_PROJECT_DOC_BUDGET` in
  `scripts/plan-migration.sh`). A `BUDGET` row reading `OVER` means a Codex
  session in that directory is already losing instructions; fix it before the move, not after.
- **A `SUPPRESS` row is outside the repository's reach.** Nothing in a PR fixes a bare
  `~/CLAUDE.md`; report it to the operator as theirs to decide.
