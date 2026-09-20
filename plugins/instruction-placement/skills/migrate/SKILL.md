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
bash "${CLAUDE_PLUGIN_ROOT}/skills/migrate/scripts/plan-migration.sh" --dry-run
```

Read-only, and `--dry-run` is the only mode it has. Its rows are the facts a migration turns on:

| Row | What it decides |
|---|---|
| `DIR` | One state per directory: `content-in-claude`, `shim`, `agents-only`, `both-with-content`, `zero-byte`. The state names the work |
| `BUDGET` | `AGENTS.md` bytes summed root-to-directory against Codex's project-doc budget, which is cumulative across the files it loads rather than per file. The number and its dated record live beside `CODEX_PROJECT_DOC_BUDGET` in `scripts/plan-migration.sh`; read it there rather than restating it. `OVER` means content has to move out before the migration, not after |
| `CASE` | A filename differing only by case. Claude Code matches names exactly; NTFS does not, so the repository behaves differently per developer until it is renamed |
| `SUPPRESS` | A bare `~/CLAUDE.md` or `~/CLAUDE.local.md`. Present, it is read instead of `AGENTS.md` in every directory below home, and no repository-side change fixes that |
| `PATHDET` | Code that finds a path by the existence of `CLAUDE.md`. Each one works while the shim exists and breaks at cutover. Report them; fixing them is not this run's scope unless the operator asks |
| `CITE` | A markdown link resolving into `CLAUDE.md`. Each is retargeted in the same PR as the content move, or the link dies |
| `DOCSHOME` | Where a pointer target lands |
| `ACTION` | Every `claude-code-action` pin. Each decides the CLI version CI installs, and so whether CI reads `AGENTS.md` at all |

Present the plan, with the content split you propose per file, and stop. Nothing is written until
the operator accepts.

## Apply

Work one directory at a time, deepest last, and in this order per directory, because an interruption
between steps must leave content duplicated rather than deleted:

1. **Create or extend `AGENTS.md`** with the content that belongs there. Merge under a new heading;
   never clobber an existing file.
2. **Write the pointer targets** into the detected docs home, and the pointer lines into `AGENTS.md`.
3. **Write the `.claude/rules/` files.** Fetch the current rules frontmatter format at authoring
   time rather than writing it from memory: `curl -sL https://code.claude.com/docs/en/memory.md`
   and read its "Path-specific rules" section. Validate every glob with
   `"${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh"` before the file is written; a glob matching
   nothing is a rule that never fires, and nothing goes red.
4. **Reduce `CLAUDE.md` to `@AGENTS.md`**, one line, once its content has a home. An HTML-comment
   note inside a shim is content: move it into `AGENTS.md` or delete it with the operator's say-so.
5. **Regenerate the index**: `"${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh" write --file AGENTS.md`.
6. **Re-run the plan** and confirm the states moved the way the operator accepted.

Where a directory has a nested `AGENTS.md`, `render-index.sh wiring` says whether it needs a shim:
an `UNWIRED` row does, a `NATIVE` row does not.

## Verify the load, never assume it

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh" --help
```

It drives one real `claude -p` turn with an `InstructionsLoaded` hook and prints
`VERDICT PASS|FAIL|UNKNOWN`. **`UNKNOWN` (exit 3) is a third outcome, never a pass**: it means the
probe could not measure, so rerun it once and escalate if it stays `UNKNOWN`. A canary counts only
against a non-empty `AGENTS.md`; an empty file passes every canary and carries nothing.

For a headless canary, put a token in the working-tree `AGENTS.md`, never in a commit, and ask for
the instruction lines rather than for the tokens:

```bash
claude -p "Read the file <a file in that directory>. Then quote back, verbatim, every line of your
  project instructions that contains the word CANARY. If there are none, say NONE." \
  --model haiku --allowedTools Read
```

**Ask for the lines, and name a file that exists.** "List every canary token in your instructions"
reads as an exfiltration request and gets refused, which proves nothing about the loader; and a
Read of a missing file never fires the nested trigger the canary is testing. Remove the token and
confirm `git status --porcelain` is clean before committing.

Then run `/docs-hygiene:audit-progressive-disclosure` via the Skill tool, when it is installed, on
the finished root `AGENTS.md`: a root file that grew during the migration has moved the cost rather
than removed it.

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
- **Never write into `.cursor/`, `.codex/` or `.github/`.** Another tool's instruction file is not
  an unshimmed Claude surface.
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
