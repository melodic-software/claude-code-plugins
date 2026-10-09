---
bump: patch
---

### Changed

- **research-deep pilots a wide fan-out.** When the multi-topic check finds more than about 4 topics, the skill spawns one `discovery:researcher` alone, waits for its return, and confirms plan usage remains before spawning the rest, so a usage limit cannot stop every researcher at once.
