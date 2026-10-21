---
bump: minor
---

### Changed

- The Propose a question button at the foot of the question list is a standard secondary button, its border at the 3:1 field-boundary strength, instead of a faint ghost button.
- Past 12 people, the shared interview page's Host view shows each person on one compact line (presence dot, name, state and a menu button that opens their card with the host's actions); at 12 or fewer the rows stay as they were.
- On the shared interview page, the comment box works before a pick on every question that takes one, including a choice with Something else and a scale; the comment goes in with the pick, and a comment typed before choosing Something else becomes the own option's draft.

### Fixed

- On the shared interview page, a stale page's attachment chip x no longer takes a just-sent file off the post that carries it: the chip asks to remove only a draft, and the server refuses once the file is carried (#8615).
- On a phone, tabbing into the answer box no longer opens the full-height writing sheet, which held Tab inside it and left Pass, the Claude bar, Ask Claude and Discussion out of keyboard reach; a tap still opens it.
- A chat reaction chip keeps one label whether or not you reacted; its pressed state says which, as the WAI-ARIA toggle-button pattern asks.
- The shared interview page's header count says "Only you here" when no one else has the page open, instead of a bare "1 here" that read as someone else.
- On a phone, the host's Who must answer button wraps below the question's position with the chips, so the previous and next arrows stay on the position's row.
- Text on the shared interview page meets WCAG 2.2 AA contrast in dark and light on its main states: the light theme's accent is a shade darker so white text on it (primary buttons, badges, your own chat bubbles) reaches 4.5:1, the dark theme's chat badge uses dark text on its red, and a pressed people chip's count no longer uses the faint color.
