# Body edit-time escalation

An exception to the labeler precondition in [`../SKILL.md`](../SKILL.md)'s admission gate. The
other refusals refuse the candidate again each cycle; a candidate refused only on its body edit
time is escalated once (`kind=escalated`, to human attention), not refused again each cycle. Two
`label-provenance` results qualify:

- a body edited after admission (`body_edit.after_admission` `true`);
- an edit time the adapter could not read (`after_admission` `null`, as when the GitHub adapter's
  GraphQL read fails).

The cycle report lists it as `body edit: #<item> (<body_edit.reason>) -> escalated`, and the
escalation question names the cause:

- **Edit after admission.** A person with write access reads the body and applies the label again
  to admit it.
- **Edit-time read reported unavailable.** Applying the label again does not clear the refusal. The
  question says so, quotes the reason, and asks the person to rerun the loop where the read
  succeeds or work the item attended through `/work-items:work`.

The `body_edit` fields are defined in the work-item tracker's `CONTRACT.md` ("Verbs (core public
surface)").
