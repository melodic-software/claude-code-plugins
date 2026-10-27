---
bump: minor
---

### Added

- **`/planning:interview` checks each draft round against earlier answers before it is shown.** Every round after the first gets a pre-round contradiction pass: a fresh-context sub-agent runs only the assumption sweep's contradiction category over the draft round, the answered register rows and the confirmed constraints, and each conflict is fixed in the draft (a revised recommendation, or one question naming both sides) before the round is asked inline or posted with `add-round`. `context/assumption-sweep.md` "Pre-round contradiction pass" holds the rule, with an eval case.
- **Sweep rounds are labeled on the page.** `add-round` takes `meta.kind: "sweep"`, stored on the round's `rounds` entry rather than in meta, and the page labels that round `Sweep: reconciling earlier answers`. A question's new `reconciles` list names the earlier questions whose answers it reconciles, and the page shows each one's decision beside the question. `add-round` refuses an unknown `kind`, a `kind` on a round with no questions, and a `reconciles` id that is not in the register, naming it.
