# The built-in `/install-github-app` command: verification record

Detail behind the `/install-github-app` Boundary section in [SKILL.md](../SKILL.md). Each row is
a four-part record: the claim, the basis it rests on, the date it was checked, and the event that
makes it worth checking again. "The extraction" below is the `/harness-ops:inventory` extraction of
the installed 2.1.284 binary, 2026-09-29.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `install-github-app` is a built-in command described as "Set up Claude GitHub Actions for a repository". User-invocable only (not model-invocable), gated, not hidden | The extraction | 2026-09-29 | A release renames or removes it, ungates it, or changes its invocability |
| The commands reference documents `/install-github-app` as installing the Claude GitHub App for a repository, with an optional step to set up GitHub Actions workflows and secrets | <https://code.claude.com/docs/en/commands>, as parsed by `/harness-ops:inventory --docs` on 2026-09-29 | 2026-09-29 | That row changes or is removed |

## Why the verdict is complementary

`/install-github-app` performs one setup on one repository. This skill advises on the policy
around it, across repositories and organizations, and changes nothing on a bare invocation. The
model offers the command to the person because only the person runs it.
