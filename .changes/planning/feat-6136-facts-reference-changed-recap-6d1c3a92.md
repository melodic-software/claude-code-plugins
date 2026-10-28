---
bump: minor
---

### Added

- `round.sh add`, `add-round` (and its `--check`), `apply` and `revise` warn, naming the question, on a `facts` field that holds more than its `Checked against:` line yet carries no link, `file:line` or `judgment` label, so a claim a question rests on cannot reach the user unchecked. It warns and never refuses, beside the existing basis-label and bare-file warnings.
- `export-ledger --recap --changed --ledger L` lists only the rows whose status, question or answer changed since the last saved recap, then one `Unchanged since the last recap (N): <count> <status>, ...` line for the rest. It lists every row when no recap has been saved yet.

### Changed

- `round.sh export-ledger --recap --ledger L` reads the ledger alone when `--dir` is absent or names no directory, so the terminal lane, which has no page data, runs the same recap command; read alone, a ledger without exactly one open-question register is refused. Each recap that fits the restate cap saves its rows beside the ledger in `<L stem>.last-recap.json`, which every later recap overwrites.
- `interview` Step 3 generates the confirmation recap with that command and pastes it verbatim, with no paraphrase and no HTML or collapsible block, and adds `--changed` after the first confirmation. The page lane's `restate` keeps the full recap, because the Brief's Decisions section is read from it.
