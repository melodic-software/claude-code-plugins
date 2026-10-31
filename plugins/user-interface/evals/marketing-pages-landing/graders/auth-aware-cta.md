---
type: llm
arm: both
---
PASS only if the reply's code makes the hero or header call to action depend on whether the visitor
is signed in: signed-in visitors get a destination inside the app (a dashboard, `/app`, or another
app route such as `/habits`, labeled for example "Go to Dashboard" or "Open App"), and signed-out
visitors get signup. A ternary on the destination, a ternary on the label, or a conditional render
of two different links all count. FAIL if every call to action in the code points at signup (or
another fixed route) whatever the auth state, even when the prose says signed-in visitors would see
something else, or if the reply contains no code.
