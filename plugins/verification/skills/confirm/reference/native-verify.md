# The bundled `verify` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `verify` is a bundled skill described as verifying "that a code change actually does what it's supposed to by exercising it end-to-end and observing behavior", driving "the affected flow, not just tests or typecheck"; it "bootstraps this repo's project verify skill if none exists yet" and is not for "a diff that only touches tests, docs, or other code with no runtime surface to drive" | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29 | 2026-09-29 | A release renames or removes it, or changes its description |
| Its registration disables model invocation: the person runs it, the model does not | Same extraction (`disable_model_invocation` true, `user_invocable` true); the commands page says "`/verify` runs only when you invoke it. Before v2.1.215, Claude could also run `/verify` on its own" | 2026-09-29 | A release changes its invocability, or the commands page note changes |
| `/verify` confirms a change "by building your project's app, running it, and observing the result, rather than relying on tests or type checks"; `/run-skill-generator` writes a per-project skill at `.claude/skills/run-<name>/` that `/run` and `/verify` then follow | The `/verify` and `/run-skill-generator` rows on <https://code.claude.com/docs/en/commands>; the run-and-verify section of <https://code.claude.com/docs/en/skills> | 2026-09-29 | Either row or that section changes |
| Bundled skills turn off with `disableBundledSkills`, and one bundled skill hides with a `skillOverrides` entry of `"off"` | <https://code.claude.com/docs/en/skills> | 2026-09-29 | The skills page changes either setting |

## Why the verdict is complementary

`/verify` observes the running app and answers "does it behave". This skill answers "did we build
the right thing": it gates on the mechanical pass, matches the change against the plan or intent,
names the couplings the change leans on, and renders the verdict from a fresh context. A drive of
the running app is one kind of evidence inside that verdict, so the model offers `/verify` to the
person as an addition when the change has a runtime surface, and never as a substitute.
