---
bump: patch
---

### Changed

- `/corrections:codify note` now says why to note a correction rather than only acknowledge it
  (an acknowledged correction is lost when the session ends), that a note `group` never routes to
  codify changes nothing, and that an agent writing the same instruction or correction a second
  time appends a note.
- `/corrections:codify` section 3 now ties scope to one-off or pattern: a one-off below the
  threshold stays a `note` row, a recurring mistake that meets the guardrail criterion gets a
  checking rung, a mistake that holds for every repository becomes a team standard, and a run past
  the count ends in a proposed check, a placed rule or a filed work item.
