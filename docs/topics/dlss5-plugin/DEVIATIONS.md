# Deviations: gaming plugin implementation

Append-only. Types: plan-confirmed, discovery, deviation, human-decision.

- **deviation (Phase 2): fresh snapshot on every apply.** Plan said: auto-snapshot only when
  `snapshot.json` is absent. Found: `remove` keeps the snapshot, so a re-apply after a game update
  would reuse a stale tree and the next `remove` would report the update as drift. Chose: `apply`
  always snapshots after its refusal gates pass (a manifest's presence already blocks apply, so the
  tree is pre-install). Revisit: never, unless snapshotting becomes too slow on large games.
  Evidence: `Do-Apply` in `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1`; selftest
  `apply with no prior snapshot snapshots first`.
- **deviation (Phase 2): `pending.json` lists intended destinations once.** Plan said: append each
  destination as it lands. Found: the collision gate guarantees no intended destination existed
  before apply, so the intended list is exactly what a crash could leave behind. Chose: write the
  intended list before the first copy. Revisit: if the collision gate is ever relaxed. Evidence:
  selftest `copy fault leaves tree byte-identical`.
- **deviation (Phase 2): anti-cheat scan shape off Steam.** Plan said: walk up to four ancestors
  and scan from there. Found: a recursive scan rooted four levels up can reach a whole library and
  refuse a game because a sibling game has anti-cheat. Chose: recursive scan (depth 4) of the exe
  dir, plus the direct children of each of up to four ancestors, stopping above the drive root.
  Steam titles scan from `steamapps\common\<X>` recursively (depth 4) as planned. Revisit: when a
  title puts anti-cheat deeper than both. Evidence: selftest
  `EasyAntiCheat three levels above the exe dir refuses`.
- **deviation (Phase 2): status exit codes implemented in the script now.** Plan said: Phase 4
  documents them, and assigned no script work item. Chose: `Get-Stat` computes `Bad` per the
  Decisions row (manifest-listed `OptiScaler.ini` drift is expected). Evidence: selftests
  `OptiScaler.ini drift is expected, not bad` and `changed manifest file is bad`.
- **discovery (Phase 2): red was not observed per case.** The selftest cases were written together
  with the port and passed on first run, so no case was seen failing first. A fresh-context
  verifier reviews the phase instead. Outcome: see the Phase 2 verifier result.
