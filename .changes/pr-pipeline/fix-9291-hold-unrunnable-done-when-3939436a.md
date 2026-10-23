---
bump: patch
---

### Fixed

- Intake admission refuses `agent-ready` for an issue whose done-when asks for what an unattended lane run cannot do: a run on a named host or OS (such as a Windows 11 host), a paid eval, a run repeated N times, a measurement over time, or a page on a host outside resolve-issue's web-access domains. The issue gets `status: needs-decision` and the admission comment names each such item and recommends splitting it into a needs-human child issue. The intake rubric raises the `intent` flag for the same items.
