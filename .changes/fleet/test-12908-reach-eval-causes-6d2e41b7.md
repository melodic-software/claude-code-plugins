---
bump: patch
---

### Changed

- `/fleet:reach` says a `-p` receiver lives only as long as its turn, so a session that must stay up uses a background session, and that a request naming a machine and not a lane lists each of that machine's lanes, since a listing shows only its own lane. The reach evals now create the condition each one measures.
