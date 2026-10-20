---
bump: patch
---

### Changed

- Shared session: Offer file in the attach picker attaches the offered file to the draft at once, as a pasted picture
  does; the chip reads "Waiting for the host" and Send waits for it. The uploader's own file row shows the thumbnail
  made in their browser.
- Shared session: Report a problem and Your reports take a screenshot by picking or pasting it, shown as the same
  attachment chip every other form uses.
- Shared session: one time phrase everywhere ("just now", "5 min ago"), one avatar, name and time line whose avatar
  opens the person card from the keyboard, "You" as the one self label, and one class each for the unread dot, inline
  link button, counter and empty state.

### Fixed

- Shared session: a received picture offered on a question that nothing ever carried (from before attachments) shows
  under that question: to everyone once the host approves it, and before then to the host (with Approve picture) and
  its uploader (with Remove). Snapshots carry it in a new optional `questionPics` field. A form's unsent picture and
  one a post carried, even one since cleared, deleted or hidden, never show there or read back to anyone else; new
  uploads record this in optional `draft` and `carried` marks, and taking a pasted picture off a form removes it.
  State files move to schemaVersion 7: the upgrade marks every older upload carried except an offer made before forms
  attached pictures that nothing carries.
- Shared session: times no longer read "now ago", and "You marked this round ready" goes by person, so someone else
  with the same name no longer reads it.
