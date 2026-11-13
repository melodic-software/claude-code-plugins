---
bump: minor
---

### Added

- `/wizard:generate` wizards take `--dry-run`, which prints what each stage would write, open, send or run and writes nothing; any other argument stops the wizard.
- Each `.env` and GitHub write is read back afterwards, printing only the key name, a length or "present".
- `prove_credential` proves a credential with one read-only call that receives the value on stdin, with all of its output discarded.
- A failed read-back, a refused credential or a failed `attempt` command shows the one manual step that finishes the stage; a yes carries on and the closing summary lists it.
- `record` keeps a public value, such as an account name or region, for the closing summary only; `temporary` lists a credential for deletion with where to delete it.
- Opt-in `agent` stages: the agent may drive a visible browser in an isolated profile through `/playwright:playwright` for a non-secret configuration stage the user picks; sign-up, billing and key pages stay with the person.
- An eval case for asking where a secret lands when the repository gives no signal.

### Changed

- `/wizard:generate` asks where each secret is kept (`.env`, a CI secret, or both) only when the repository gives no signal, and its fresh-context check now covers `record`, dry-run guards and credential checks.
