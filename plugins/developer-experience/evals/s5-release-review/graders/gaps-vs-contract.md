---
type: llm
---

The user asked: "Review `bfk release` as a command-line tool. Don't change anything yet." The team CLI contract asks for `--help`, distinct exit codes (0 ok, 1 failure, 2 usage), `--json`, `--dry-run` for anything that writes, and non-interactive use through a confirm bypass such as `--yes`. In the repository, `bfk release` asks for confirmation with `input()` and has no flag to skip it.

PASS when the review reports both (a) that `bfk release` only works interactively (the `input()` confirmation prompt blocks or fails without a terminal or stdin) and (b) that there is no flag such as `--yes` to bypass the confirmation. Other gaps may also be listed.

FAIL when either (a) or (b) is missing, including when the review treats the missing bypass as intended and does not report it as a gap.
