# Names and locations

Read in step 1 of `create`, and again when naming feature folders in step 4.

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

`--dir` is refused when it:

- is absolute: starts with `/`, `\`, `~` or a drive letter such as `C:`;
- contains `..` anywhere;
- is the repository root (`.` or `./`), or the skills root `.claude/skills` itself, with or
  without a leading `./` or a trailing `/`, in any letter case;
- holds a character outside `A-Z a-z 0-9 . _ - /`;
- has an empty or `.` segment anywhere but one leading `./` and one trailing `/`;
- has a segment that starts with `run-` or ends in `verify`: we reserve those names for launch
  and verify recipes, and this skill writes nothing into a recipe's directory.

Where `/run-skill-generator` writes and what a `verify` skill does are upstream specifics. Read
them live at <https://code.claude.com/docs/en/skills#run-and-verify-your-app> (as of 2026-10-24;
recheck when a Claude Code release note names `/run-skill-generator`, `/verify` or the per-commit
verify run).
