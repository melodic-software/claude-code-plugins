# Coverage ledger: trust measures computable in claude-code-plugins

Corpus: bounded. Three named measures, the three named skills, and the named delivery-metrics definitions.

Narrowed explicitly: row 1's revert logic was read from SKILL.md's Deploy signal section and the script was run, not read; row 2 read only the Owner touches row of SKILL.md (queue labels and telemetry rows were not read, as they bear on none of the three measures).

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | /work-items:measure-delivery | SKILL.md read end to end and its scripts' change-fail and rework logic located (what git data, what revert detection) | [x] |
| 2 | /work-items:morning-brief | SKILL.md sections on owner touches, queue labels and telemetry read; data source for "owner touches" identified | [x] |
| 3 | /corrections:codify | SKILL.md read end to end; what it records (any ledger, label, file) identified or its absence stated | [x] |
| 4 | DORA change fail rate definition | dora.dev metrics page fetched and definition quoted | [x] |
| 5 | DORA deployment rework rate definition | dora.dev metrics page fetched and definition quoted | [x] |
| 6 | Published revert-rate definition | at least two non-DORA sources searched; a definition quoted or absence recorded with sources checked | [x] |
| 7 | Published autonomous-merge (no-human-touch) share definition | at least two sources searched; a definition quoted or absence recorded with sources checked | [x] |
| 8 | Revert rate for this repository | value computed with a recorded read-only command, or the blocker named | [x] |
| 9 | No-human-touch merge share for this repository | value computed with a recorded read-only command over a stated window, or the blocker named | [x] |
| 10 | Corrections converted to checks for this repository | value computed with a recorded command, or the missing data source named | [x] |
