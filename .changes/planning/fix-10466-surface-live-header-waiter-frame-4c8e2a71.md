---
bump: patch
---

### Fixed

- The surface-ui-c browser suite no longer flakes on loaded runners: its checks wait on what the
  page or the page server shows instead of fixed pauses. Picking a question retries until the card
  holds the selection, even when a re-render collapses its group mid-click; saves wait until the
  server records the event; phases 1 and 2 wait for the page to show an external answer, revise or
  Accept all result before checking it; and phase 6 checks Live only once the server counts the
  waiter, and the released state only once the server reports reading with no lease and no waiter.
  A server test covers the state frame a waiter arriving or leaving pushes while the lease is held.
