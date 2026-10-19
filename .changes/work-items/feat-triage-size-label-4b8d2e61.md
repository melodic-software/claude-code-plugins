---
bump: minor
---

### Added

- `/work-items:triage` sets an item's issue dimensions when the repository's `docs/conventions/pr-pipeline.yaml` has `models.issue-dimensions`: before an autonomous-eligible outcome's label edit it chooses one key per dimension from that block and runs `skills/triage/scripts/set-dimensions.sh`, which maps each key to its option id through the block and sets the fields through the tracker seam. An item whose size is `split`, or whose uncertainty mode is not `run`, is human-gated with a comment naming the next step (`/work-items:decompose`, planning or research, or a probe) instead of taking `agent-ready`.
- The tracker seam's `set-fields` verb sets single-select issue fields by option id, refusing an id that is not one of its field's options before writing. The GitHub adapter implements it for organization issue fields.
