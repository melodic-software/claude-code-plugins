---
schema_version: "1.1"
name: principles-dialog-copy
description: "Happy path: a leave-team confirmation dialog and its failure toast get copy that names the outcome on the button and tells the user how to fix the failure, instead of OK and a generic error"
tags: [web, principles, copy, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The dialog's confirm button names what it does (leaving the team), not OK, Yes, Submit or Confirm, and the failure toast says what happened (the user is the team's last admin) and what to do next (make another member an admin first), not a generic error"
---

Design the dialog a member sees in our React app when they choose to leave a team, and the toast
shown when leaving fails because they are the team's only admin. Here is the current draft:

```jsx
<Dialog title="Are You Sure?">
  <p>This action cannot be undone.</p>
  <button onClick={leaveTeam}>OK</button>
  <button onClick={close}>Cancel</button>
</Dialog>

toast.error("An error occurred");
```

This run cannot write files, so put the revised JSX, with its copy, in your reply.
