---
bump: minor
---

### Added

- **The interview page gates a decision ahead of an open prerequisite (`frontierLock`).** Under the default, `confirm`, saving a decision on a question whose `dependsOn` names a question still open asks first ("Q100 depends on Q22, which is still open.", with Go to Q22 and Answer anyway). Answer anyway stores `outOfOrder` on the event, and the prerequisite's first decision marks the question stale for review. The rail shows a padlock `Locked` chip in place of `Blocked`. `hard` disables Save and the server refuses such a decision with 409 `blocked`, naming the open ids in `waitsOn`; `off` keeps the earlier behavior. Ask, Rephrase and Research this stay enabled in every mode ([#9709](https://github.com/melodic-software/claude-code-plugins/issues/9709)).
- **`round.sh add` and `add-round` expect declared dependencies.** A question that omits `dependsOn` (`[]`, or `add --depends none`, declares it independent), or names a question still open in its own round, gets a warning naming it; the `requireDepends` setting turns both into refusals. The page protocol now requires every posted question to declare `dependsOn`, so the lock has prerequisites to act on.

### Fixed

- Escape on the interview page's "Accept current recommendation anyway?" and "Wrap up with N items outstanding?" dialogs cancels; before, it confirmed whenever the page's previous dialog had been confirmed.
- The server's accept-all check (`accept-audit`) leaves out a question whose prerequisite is held or has only a decision a user hold set aside, as the page already did; before, a hand-built request could accept it.
