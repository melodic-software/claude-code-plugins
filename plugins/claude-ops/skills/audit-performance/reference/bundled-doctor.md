# The bundled `doctor` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The sibling `audit-install-state` and `audit-skill-visibility` skills keep
their own records against the same surface.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `doctor` (alias `/checkup`) is a bundled skill that "diagnoses issues and can fix them": installation health (duplicate or leftover installs, `PATH`, unparseable settings), unused skills, MCP servers, and plugins against their context cost, slow hooks, a newer version on the release channel, `CLAUDE.md` deduplication and trimming, auto mode and read-only pre-approval offers. "Reports findings first and asks for confirmation before changing anything" | The `/doctor` row on <https://code.claude.com/docs/en/commands> | 2026-09-11 | The row changes its check list or its fix behavior |
| `claude doctor` from the terminal "prints read-only installation diagnostics without starting a session" | Same row | 2026-09-11 | The row drops the terminal form |
| It survives `disableBundledSkills` (2.1.205 or later); `DISABLE_DOCTOR_COMMAND` or a `skillOverrides` entry `"doctor": "off"` hides it | The bundled skills section of <https://code.claude.com/docs/en/skills>; the installed 2.1.263 binary registers it with `aliases:["checkup"]`, `isEnabled:()=>!DISABLE_DOCTOR_COMMAND`, and `survivesBundledKillSwitch` | 2026-09-11 | Either page changes the exemption, or a release note names the gate |
| It has no timed or profiling mode: nothing in its description measures how long a hook, a stat walk, or a spawn takes | The row above lists checks and fixes, not timings | 2026-09-11 | A release gives `/doctor` a timed or profiling mode |

## Why the verdict is complementary

Two of `doctor`'s checks, slow hooks and a newer version, sit on this skill's suspects 2 and 4.
`doctor` answers them by inspection and offers to fix. This skill answers "why is it slow right
now" by measurement, at the moment it is slow, with the engine's own phase timings as first-class
evidence, and it refuses to delete anything. `claude doctor` in the terminal is the one read-only
native form and is worth running beside this capture when a session will not start.

## Presence

`doctor` is the one bundled skill the kill switch leaves typable, but an environment variable or
a `skillOverrides` entry still hides it, and headless contexts may lack it. This skill never
depends on it and never chains into a `doctor` fix: the capture is complete on its own.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which `doctor`
appears as a bundled skill marked gated. This record re-verifies the registration on the installed
2.1.263 binary by string search and reads the two pages named above, all on 2026-09-11.
