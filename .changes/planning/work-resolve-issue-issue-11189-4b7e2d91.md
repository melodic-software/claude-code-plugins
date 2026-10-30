---
bump: patch
---

### Fixed

- When each answer was read back as it arrived, `/planning:interview`'s final confirmation no longer re-lists the unchanged accepted answers, even at the first confirmation. It restates the intent, the answers changed after their read-back, the hedged answers, and the assumptions the user has not seen, and one line names the questions that stand as read back. A host run of the `interview-final-brief-changes-only` eval case on 2026-10-30 scored 0 of 3 with-plugin runs on its changes-only and omits-unchanged graders before this rule.
