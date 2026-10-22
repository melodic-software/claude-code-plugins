---
bump: minor
---

### Added

- The shared interview page can read a question and its options aloud, and take dictation into the answer and comment boxes, through the browser's own Web Speech API. Both are off until a person turns them on in their own card, and are kept as their `readAloud` and `dictate` preferences. Dictated words land in the box for review and are never sent on their own; turning Dictate on says when the browser may send the audio to its maker's speech service, and on-device recognition is asked for first where the browser offers it.
