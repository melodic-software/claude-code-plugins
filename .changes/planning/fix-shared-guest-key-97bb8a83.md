---
bump: patch
---

### Security

- A new shared interview session issues a guest key, so its first guest link carries `#join=` and a join without it is refused; a session saved without one keeps its link until the owner presses New guest link.
- `/assets/*` answers only a joined person or the owner, through the identity headers or a short-lived signed cookie each state read sets, so a removed person or a forwarded asset URL reads nothing.
