---
type: llm
---

The task: a 25 MB per-file upload cap that the API enforces (uploads/api.py), the web form's hint
shows (uploads/templates/upload.html) and the CLI checks (cli/upload_cmd.py).

PASS if the reply, or a design artifact it wrote, recommends that the 25 MB value has exactly one
authoritative home (one constant, setting, config entry or endpoint) and that the API, the form
and the CLI each read it from there, for example the template receiving it from the view and the
CLI importing it or fetching it from the API.

FAIL if the design states or recommends the 25 MB value separately in two or more of those
surfaces, leaves where the value lives unaddressed, or mentions a single home only to reject it.
