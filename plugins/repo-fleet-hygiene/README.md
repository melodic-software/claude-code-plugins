# repo-fleet-hygiene

`repo-fleet-hygiene` audits Git and GitHub state across many local repositories. It reports:

- local branches whose matching GitHub pull request is merged;
- merged-PR, missing, prunable, or administratively mismatched worktree registrations; and
- GitHub repositories whose configured remote resolves to a different owner or name.

The plugin is deliberately **report-only**. It never fetches, prunes, repairs, deletes, checks out, or
rewrites anything. Every finding names its evidence, confidence, disposition, and exact target. Cleanup
stays with the existing per-repository capabilities:

- `/repo-hygiene:clean git` for a local-branch audit and its own confirmation gate;
- `/source-control:worktree cleanup --dry-run` for worktree cleanup planning; and
- `git worktree repair` only as a manually reviewed option for an administrative mismatch.

## Actions

| Skill | Purpose |
|---|---|
| `/repo-fleet-hygiene:audit` | Scan one repository, explicit repositories, or repository-tree roots and render a fleet report |
| `/repo-fleet-hygiene:setup` | Create or update the optional tracked fleet configuration without touching user settings |

## Quick start

Audit the current project repository (zero configuration):

```text
/repo-fleet-hygiene:audit
```

Audit one or more repository-tree roots:

```text
/repo-fleet-hygiene:audit --root D:/repos/github.com --root D:/work/internal
```

Audit exact repositories without recursive discovery:

```text
/repo-fleet-hygiene:audit --repo D:/repos/github.com/acme/api --repo D:/repos/github.com/acme/web
```

The skill automatically uses `.claude/repo-fleet-hygiene.conf` in the consumer project when present,
or accepts `--config <path>` explicitly. Explicit CLI roots/repos are additive.

## Configuration

Configuration uses Git's own config-file grammar, so no JSON parser or third-party runtime is required.
Relative paths resolve from the configuration file's directory. Repeat `root` and `repo` as needed:

```gitconfig
[fleet]
    root = ../../repos/github.com
    repo = ../../special/exact-checkout
    maxDepth = 5

# Key by the remote identity observed before GitHub redirect resolution.
# This is the supported escape hatch for manager-owned/non-obvious canonical checkouts.
[canonical "github.com/acme/dotfiles"]
    path = ../../../.local/share/chezmoi
```

Resolution order is explicit `--canonical REMOTE=PATH`, config `[canonical "REMOTE"]`, then
`git rev-parse --show-toplevel` on the discovered checkout. `REMOTE` is the normalized
`github.com/owner/repository` identity from the selected fetch remote. A canonical override changes
where local branches and worktrees are read; it does not suppress remote-migration detection.

The selected remote is `origin` when present, otherwise the sole configured remote. Ambiguous or
non-GitHub remotes are reported as unknown rather than guessed. This is GitHub-only v1; GitHub
Enterprise and other forges are not contacted.

## Confidence and safety

| Confidence | Meaning | Cleanup disposition |
|---|---|---|
| `HIGH` | Direct authoritative evidence agrees (for example, a GitHub merged PR head OID equals the local branch tip) | Candidate for the named per-repo tool's own dry run/gate |
| `MEDIUM` | Direct evidence identifies a condition, but another fact prevents safe cleanup (for example, commits after the merged PR head) | Manual review |
| `LOW` | Local or indirect evidence only | Informational; never a cleanup candidate |
| `UNKNOWN` | A prerequisite, permission, identity, or API result is unavailable/ambiguous | Investigate; never infer absence or safety |

Absolute local paths appear only in local report output. The only network calls are authenticated,
read-only `gh` queries to `github.com`; no report content, file content, or git object is uploaded.
When `gh` is absent or unauthenticated, the Git/worktree portion still runs and all GitHub-backed
claims become `UNKNOWN`. Each `gh` invocation has a 30-second deadline; a timeout degrades only the
affected GitHub evidence instead of stalling the fleet.

## Requirements

- Git with `git worktree list --porcelain -z` and `git rev-parse --path-format=absolute` support.
- Bash (Claude Code's Bash tool; Git Bash is the supported Windows path).
- Optional: authenticated GitHub CLI (`gh`) plus `timeout` (GNU/Linux and Git Bash) or `gtimeout`
  (GNU coreutils on macOS) for bounded merged-PR and moved/renamed-repository evidence. Without either
  timeout spelling, the GitHub portion reports unavailable rather than making an unbounded call.

## Security review

The plugin-acceptance review is recorded in
[`reference/security-review.md`](skills/audit/reference/security-review.md). The audit script uses no
`eval`, never sources consumer configuration, never follows filesystem links during discovery, sends
no local content to GitHub, and contains no mutating Git/GitHub command.

The current official documentation and the decisions each source supports are recorded in
[`reference/official-sources.md`](skills/audit/reference/official-sources.md).

## License

MIT (SPDX-License-Identifier: MIT). See the repository root LICENSE.
