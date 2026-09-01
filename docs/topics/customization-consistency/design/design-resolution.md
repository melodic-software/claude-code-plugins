# Design resolution — customization-consistency

outcome: resolved-by-tournament

The design-significant surface of this effort (the retired-convention mechanism: retirements.yaml
schema, shared helper CLI contract, audit-pass sweep lane) went through an explicit
design-it-twice tournament instead of /planning:design: three independently authored candidate
designs, three blind fresh-context validators with repo fact-checking, unanimous winner plus a
converged hybrid, approved by the user 2026-09-01. The approved contract is committed beside this
file: `mechanism-spec.md` (winning design, normative) + `mechanism-validation.md` (tally + hybrid
amendments). Losing candidates remain in the memory tier
(`.work/customization-consistency/mechanism-candidates/`, machine-local). The remaining work (doc amendments, drift fixes, per-surface migrations) is
convention/prose work with no new types or module topology — Tier C for /planning:design
purposes.

Type sketch (the one new machine contract):

- `plugins/<plugin>/retirements.yaml` — append-only records: id, retired (date),
  plugin_version, kind (file|dir|line), path, match/content_match, action
  (delete|remove-line|migrate), successor (prose), note, demotion (active|report-only).
- `lib/check-retirements.sh` — args: manifest path + consumer-repo root; output TSV findings;
  exit 0 clean / 1 findings / 2 invalid manifest; `--clean <id>` (+ `--i-migrated` for migrate
  kinds).
