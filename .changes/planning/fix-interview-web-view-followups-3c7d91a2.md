---
bump: patch
---

### Fixed

- When no session has listened for 30 seconds, the interview page's timer now updates the question chips and the receipt line together; before, the receipt line could keep "Sent to Claude" for up to two seconds after a chip read "No session is listening".
