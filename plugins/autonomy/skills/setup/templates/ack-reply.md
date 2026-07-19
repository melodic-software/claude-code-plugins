# Acknowledgment template

Closed-loop acknowledgment (contract obligation 6) for bidirectional surfaces — one line,
item URL first (it is the join key an auditor follows), class token for audit:

```text
Queued as <item-url> (autonomy: <class> signal)
```

Posted as a tracker comment on the source event, a chat thread reply, or the surface's
native response form. Reply-less surfaces (temporal schedules, plain webhooks with no
response channel) satisfy the obligation through `signal.raw_link` alone — no synthetic
reply surface is invented.
