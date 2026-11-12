# The bundled `doctor` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is our decision
and the pointer to read live. A row that records a copied string adds the date it was derived and
the event that makes it worth deriving again; a row guarding our own decision keeps only that
event. The sibling `audit-install-state` and `audit-skill-visibility` skills keep their own records
against the same surface.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| We treat `doctor` (alias `/checkup`) as the native setup checkup that inspects and offers fixes, and we never chain into its fixes. What it checks and how it confirms are read live | [skills: check your setup with /doctor](https://code.claude.com/docs/en/skills#check-your-setup-with-/doctor); the `/doctor` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | | |
| We name `claude doctor` in the terminal as the read-only native form, worth running when a session will not start | The same `/doctor` row | | |
| We never assume `doctor` is present: it survives the bundled-skill kill switch, but other switches can hide it. Our binary reading on the installed 2.1.263 registers it with `aliases:["checkup"]`, `isEnabled:()=>!DISABLE_DOCTOR_COMMAND`, and `survivesBundledKillSwitch` | [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills); [`disableBundledSkills`](https://code.claude.com/docs/en/settings-reference#disablebundledskills) | 2026-10-11 | Either page changes the exemption, or a release note names the gate |
| We treat `doctor` as having no timed or profiling mode, so measurement stays this skill's | The `/doctor` row and section above list checks and fixes, not timings | | |
| Capture first. This skill is capture-at-moment; its Never-read rule bars transcripts, and a `/doctor` session can read them, so a person who wants the transcript-derived history asks there. That is not time-sensitive | This skill's Never-read rule; the owner's 2026-08-31 comment on issue #3533, which derived the hook-timeout aggregate by hand from `hook_cancelled` attachments (whether `/doctor` prints such an aggregate is not established) | | A release gives `/doctor` a timed or profiling mode, or this skill's Never-read rule stops covering transcripts (the engine gains a transcript read) |

## Why the verdict is complementary

Two of `doctor`'s checks, slow hooks and a newer version, sit on this skill's suspects 2 and 4.
`doctor` answers them by inspection and offers to fix. This skill answers "why is it slow right
now" by measurement, at the moment it is slow, with the engine's own phase timings as first-class
evidence, and it refuses to delete anything. `claude doctor` in the terminal is the one read-only
native form and is worth running beside this capture when a session will not start.

## Presence

We never assume `doctor` is present; what can hide it is read live from the bundled-skills
pointer in the table above. This skill never
depends on it and never chains into a `doctor` fix: the capture is complete on its own.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which `doctor`
appears as a bundled skill marked gated. This record re-verifies the registration on the installed
2.1.263 binary by string search and reads the two pages named above, all on 2026-09-11.
