---
bump: minor
---

### Added

- `save_point.py new` writes `next_question_id` and `next_decision_id` floors beside `next_rule_id`; the first hop that adopts them starts above every `Q<n>` / `D<n>` its predecessor names. `validate` fails a shape-3 hot file that drops a predecessor `[Q<n>]` or `[D<n>]` unless this hop's file lists it, with a reason, under `## Retired open questions` / `## Retired decisions`; an entry without an id still passes (#13847).
- `save_point.py fill` takes a `retire` key, a list of `{"ref", "reason"}` objects naming `[R<n>]`, `[Q<n>]`, `[D<n>]`, `[h<k>]#<i>` or `amendment#<i>`: it copies each entry's bytes into this hop's file under its retire heading, removes it from the hot file, and adds a Review before you continue line naming the hop file and heading. `validate` requires that pointer for every heading other than `## Retired rules`, and `new` carries the predecessor's pointers forward (#13847).

### Changed

- `save_point.py validate` lets a shape-3 hot file retire a predecessor goal amendment or Direction-changes line: each one stays in order or is listed verbatim in this hop's file under `## Retired goal amendments` / `## Retired direction changes`, followed by a `Retired: <reason>` line. The goal quote, intent, vision and opening ask still stay byte for byte. A reason `codified in [R<n>]` fails when `[R<n>]` is not in the hot file (#13847).
