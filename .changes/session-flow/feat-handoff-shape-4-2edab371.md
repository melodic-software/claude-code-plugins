---
bump: minor
---

### Added

- `save_point.py validate` fails a handoff that reuses an id retired anywhere earlier in its
  chain for a different rule, question or decision. Handoffs written from now on carry a
  `checks: 3` stamp, and the check applies only to them; older files validate as before.
- `handoff_chain.py` holds the section table of each handoff shape and one reader of a chain's hot
  files and hop files, which `save_point.py` and `parse_transcript.py --chain-from` now share.
- `save_point.py validate`, `emit` and the new `read` and `chain` commands read shape-4 handoffs,
  whose binding sections stay whole in the hot file while Direction changes, Observations and
  Suggested skills may move to the hop file. `new` still writes shape 3.
- `save_point.py read <file> --section <name>` prints one section, following a move to the hop
  file; `chain <file> --json` lists every hop of the chain, read from hop files where a hot file is
  gone. `parse_transcript.py --chain-from` adds each hop's sections as `handoff_journey`.
- `validate` fails, on files stamped `checks: 3`, an `UNVERIFIED` mark whose line does not name
  what settles it as `(settle: <command or URL>)`; the marks `new` writes carry one.

### Changed

- `save_point.py new --previous` with a missing or unreadable predecessor writes the handoff
  anyway, names the file as `previous_handoff` with `previous_status`, and prints one WARN line;
  it used to exit 1.
- `tidy_work.py clean --apply` shrinks a finished shape-3 or shape-4 chain to its newest hot file
  and its hop files; it used to remove the whole chain. Shape-2 chains leave as before.
