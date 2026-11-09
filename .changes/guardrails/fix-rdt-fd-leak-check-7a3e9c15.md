---
bump: patch
---

### Fixed

- The descriptor-leak check in the root-delete guard's resolver test compares the descriptor set of a subshell it owns, so a descriptor another case still has open in the test shell no longer fails it, and a descriptor `rdt_bounded_to` leaves in (or takes from) its caller still does.
