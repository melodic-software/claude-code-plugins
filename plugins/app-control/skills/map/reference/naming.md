# Names and locations

Read in step 1 of `create`, again when naming feature folders in step 4, and before every write.

## Slug rule

The app slug (for `control-<app slug>`) and each feature folder name come from a title:

1. Lower-case it.
2. Replace each run of characters outside `a-z0-9` with a single `-`.
3. Drop any `-` at the start or end; an empty result becomes `app`.
4. Cut the result to 64 characters.

`Billing / Export!` is `billing-export`, so its folder is `features/billing-export/README.md`. A
second title with the same slug gets `-2`, a third `-3`: cut the slug to 64 characters minus the
suffix's length, drop a trailing `-`, then append the suffix. Compose each path yourself and pass
it quoted; a title never reaches a shell.

## Location rules

This skill writes a control skill only to `.claude/skills/control-<slug>/` under the repository
root; `/app-control:drive` reads it from there as it reads any repository control skill. `--dir` is
refused when it:

- is absolute: starts with `/`, `\`, `~` or a drive letter such as `C:`;
- contains `..` anywhere;
- is the repository root (`.` or `./`), or the skills root `.claude/skills` itself, with or
  without a leading `./` or a trailing `/`, in any letter case;
- holds a character outside `A-Z a-z 0-9 . _ - /`;
- has an empty or `.` segment anywhere but one leading `./` and one trailing `/`;
- has a segment that starts with `run-` or ends in `verify`: we reserve those names for launch
  and verify recipes, and this skill writes nothing into a recipe's directory;
- passes every check above but, without one leading `./` and one trailing `/`, is not exactly
  `.claude/skills/control-<s>`, where `<s>` is already a slug (the slug rule leaves it unchanged).

Report the first rule a refused value breaks.

## Real paths

The text checks above see only the string. Before the first write, and again before each write,
resolve the real path (every symlink followed) of:

- the control skill directory, and every parent of it that already exists;
- every file and directory map writes inside it, `config/.gitignore` included;
- the instruction file the pointer goes to.

Each must sit under the repository root's real path, with no symlink anywhere between the root and
the file, and no `.git` segment. A path that fails is refused: write nothing there, and stop when it
is the control skill directory.

## Pointer target

The pointer goes to the instruction file the repository treats as its source. When `CLAUDE.md`
only imports another file with an `@` line (such as `@AGENTS.md`), that import is the source, but
follow it only when its real path passes the checks above. An import that points outside the
repository, or through a symlink, is not followed: write the pointer into the `CLAUDE.md` that holds
the import, and report the import as not followed.

## Upstream recipes

Where `/run-skill-generator` writes and what a `verify` skill records are upstream specifics. Read
them live at <https://code.claude.com/docs/en/skills#run-and-verify-your-app> (as of 2026-10-24;
recheck when a Claude Code release note names `/run-skill-generator`, `/verify` or the per-commit
verify run).
