---
description: "Legacy point-dont-copy 1. The doc, given in the prompt, pastes a framework's config table and rewords its retry-policy section. paraphrase-drift-named (regex) and copies-corrected (llm, legacy expectations 1-3) check both copies are flagged, the paraphrase is said to drift like a copy, and each is replaced by a pointer. Legacy expectation 4 (cross-stack port) is graded in pdc-port-semantics-gate. Read-only."
tags: [discipline, point-dont-copy, outcome, narration, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Flags the pasted config table and the reworded retry section, says the paraphrase drifts as a verbatim copy does, and replaces both with pointers to the Tern pages."
---

/discipline:point-dont-copy review the onboarding doc I just wrote. It pastes in the framework's configuration reference and rewords its retry-policy section in my own words.

Here is docs/onboarding.md as it stands:

```markdown
# Onboarding: the orders service

## Configuration reference (from the Tern docs)

| Key | Default | Meaning |
|---|---|---|
| `tern.http.port` | `8080` | Port the HTTP server listens on. |
| `tern.http.max-body` | `1MB` | Largest request body accepted. |
| `tern.pool.size` | `16` | Worker threads in the request pool. |
| `tern.log.level` | `info` | Minimum log level written. |

Source: https://tern.example.dev/docs/configuration

## Retries

When a downstream call fails, Tern tries it again up to three times. It waits 200 ms before
the first retry and doubles the wait each time, and it retries only on connection errors and 503
responses, never on other 4xx or 5xx codes. (Tern's retry policy docs:
https://tern.example.dev/docs/retry-policy)

## Running locally

Run `make dev` and open http://localhost:8080.
```
