---
bump: patch
---

### Fixed

- Intake admission no longer starves the issue lane:
  - An issue waits behind an older `admission-deferred` issue only when that one waits for room: it keeps `status: ready`, carries no `do-not-merge`, `needs-human` or untrusted-provenance label, and has no open pull request. An unreadable or incomplete read still counts as one ahead.
  - On a triage verdict, an issue whose only obstacle is missing acceptance criteria, on a body a listed human wrote that intake's refinement has not yet refined, waits at `status: ready` for that refinement instead of being refused. The trusted-criteria gate is unchanged.
  - The protected-path check also reads the body's prose outside task items and code fences, a soft-wrapped sentence as one. Evidence lines (`Basis:`, `See ...`), paths cited at a line (`a.yml:3`) and negated mentions do not count.
  - A charge word in the title or stated work no longer holds the issue in a clause that only lowers or removes the charge, such as "shorten their retention", "set a retention policy" or "drop the billing alert", unless that clause also takes one on ("drop the old job and move to larger runners"), lowers a guard on spend ("remove the spending limit") or names the charge it moves to ("cut over to larger runners", "retire the old runner in favour of larger runners"). Every other clause still holds, whatever its verb. Azure now counts as a billing account there.
  - A model eval run (`claude plugin eval`, `measure-invocation`, trigger probes, before-and-after eval numbers) goes to the host queue (`host-run`) with no hold. Subscription usage and the accounts' promotional API credits stop at a spending limit and never bill. Only an eval item that names a billing account (Azure, larger runners, Actions or private-repo minutes or storage, an API key beyond the credits, another provider such as Bedrock, Vertex, Foundry, AWS or GCP, `--provider` or `CLAUDE_CODE_USE_*`) still holds for the owner as a paid eval (`.github/scripts/intake-triage/admit.mjs`).
