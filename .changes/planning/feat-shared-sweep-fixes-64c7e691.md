---
bump: patch
---

### Fixed

- **Shared interview page: the QA sweep's 37 findings.** Counts on the welcome card and in the rail are per person, and the catch-up note sits in the round it is about; the welcome card no longer asks a joined guest for their name, and its first step names its round. The chat "Sent to Claude" marker sits under its bubble. Locked and read-only hints no longer point "above"; the Pass trigger hides while its form is open. The host reads "Waiting for you to run it" on their own queue. Claude's reports render headings, lists, bold and code instead of raw markdown, and drop the empty "via Claude" line. The question's Ask box and the Ask Claude panel share one layout, placeholder and "Run it on my own Claude" switch. Proposal actions keep one order, and a sheet's close button stays on its title row. Toolbars wrap instead of cutting chips, and phone tab rows fade at the cut edge. Attach is one square button everywhere, dialog buttons match the page's, and the attach dialog names what the file goes with and styles its file button. Pick formats share one results hint and one "Write your own" wording; a comment written before the picks rides with Save, with no second primary button. Report a problem puts its screenshot before Send. A renamed joiner ("Ivy 2") is told so, arriving in a later round shows no "Round 2 is here." toast, and a waiting guest stops sending a refused heartbeat and polls less often. Phone tap targets reach 44 px, avatars never draw initials below 9 px, the top bar title uses the free width, the chat button never covers the column, and the prototype tile and empty option feet no longer show blank boxes.
- **Shared interview page: "Who must answer" stays on the question's column.** The panel kept the question's width at wide sizes; a new `column` rule in the alignment check holds every focus-view block to it.
- **Shared interview page on phones.** A long saved answer wraps inside the folded field, the answer sheet's Save sits under the field in thumb reach, and the chat message and reaction menus open as bottom sheets clear of the home indicator.

### Added

- **Shared interview page: a question's background.** The `context` stored on a question now shows under its text.
