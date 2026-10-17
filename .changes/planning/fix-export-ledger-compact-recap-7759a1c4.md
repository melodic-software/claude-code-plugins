---
bump: minor
---

### Added

- `round.sh export-ledger --recap --out F` writes the interview confirmation gate's compact recap: one `Q<N> <status>: <question> (<answer>)` line per live question, every withdrawn row collapsed into one `Withdrawn (N): ...` line, and long answers cut until the recap fits the 20,000-character restate cap, so a long interview's recap no longer needs hand-trimming before `restate`. `context/surface.md` Confirmation gate names this form.
