---
bump: patch
---

### Fixed

- The notes panel no longer drops a click on a note row when the list re-renders while the mouse button is down, for instance when the server pushes a state change. The row is selected and its Edit, Withdraw and Move or resize actions show, where before they stayed hidden. Only a primary-button press holds the re-render, and the hold ends when the pointer leaves the list, a context menu opens or the window loses focus, so the list never freezes after a right-click or a drag into the mockup.
