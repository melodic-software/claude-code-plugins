---
bump: patch
---

### Changed

- A handoff now checks a goal's condition before carrying it into the goal region. A condition that ties its proof to this conversation, such as "shown by output you produced", gets a warning above the region that suggests commit- or file-anchored wording, and the condition itself stays verbatim. A goal already met at a recorded commit or file, with only the user's decisions left, gets no goal region and a note listing those decisions. `/session-flow:continue-in-background` redrafts such a goal instead of launching with it (#8763).
