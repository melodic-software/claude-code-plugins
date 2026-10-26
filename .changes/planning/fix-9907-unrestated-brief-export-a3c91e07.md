---
bump: patch
---

### Fixed

- `/planning:interview`: `round.sh export-brief` stamps every page export. With no restatement the TLDR reads `- Restatement: UNCONFIRMED (no restatement posted)`, and every export adds a `- Page title:` line. `check-open-questions.sh --brief` fails that stamp (`brief=unconfirmed`). It also fails a stamped export whose Goal is still the page title, or whose only criterion is `none recorded in the interview surface`, while any question is answered (`brief=placeholder`). Before, such a Brief passed the gate clean. A hand-written Brief with no `Restatement:` line still passes.
