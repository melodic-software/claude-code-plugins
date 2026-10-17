---
description: "A persona request ('act as a security expert'). The raised version rewrites it into the work a security reviewer does, names concrete methods and an outside check, fences scope, and executes nothing."
tags: [discipline, be-ambitious, outcome]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "Rewrites 'act as a security expert' into what a security reviewer does (for example threat modeling the login flow, checking password hashing, rate limiting and session handling against a named standard); an outside check; a scope fence; no Write, Edit or Bash call."
---

/discipline:be-ambitious Act as a security expert and review my login handler:

```python
@app.post("/login")
def login(form):
    user = db.query(f"SELECT * FROM users WHERE email = '{form.email}'")
    if user and user.password == form.password:
        session["uid"] = user.id
        return redirect("/")
    return "bad login", 401
```
