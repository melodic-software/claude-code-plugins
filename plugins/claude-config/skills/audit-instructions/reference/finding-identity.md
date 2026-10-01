# Finding identity for audit-instructions

Every finding this skill reports carries an identity that survives a re-run, so a finding filed
from one report can be matched against the next run's output, suppressed, or carried forward.
The identity rules are `audit-pass`'s and are adopted whole:
[`../../audit-pass/reference/finding-identity.md`](../../audit-pass/reference/finding-identity.md)
owns the tuple, `anchor/v1`, normalization, the heading-path discriminator, `finding_id/v1`, and
`group/v1`. This file states only the choices this skill makes inside that contract.

## The tuple, as this skill fills it

```text
identity = (check, claim, sites)
```

- **`check`** is `claude-config/audit-instructions/<id>`, where `<id>` is the catalog id as the
  report prints it (`I33`, `I28-a`). Sub-rows keep their own id, so `I8-b` and `I8-c` are two checks.
- **`claim`** is the template below for that id, verbatim. A template carries no bound parameters
  today, so the claim id is the whole template. Free prose in `claim` is a hard error.
- **`sites`** is one `(surface, anchor)` pair per finding. A check that fires at several sites
  reports one finding per site, all sharing one `group`. **I15 is the one pairwise claim**: a
  cross-surface conflict is one finding with two sites, never two linked findings, and the order the
  lane met the two surfaces in does not change its id.
- **`surface`** is the repo-relative POSIX path of the physical file, or `user:<path under the home
  directory>` for a user-scope surface. Under the home directory only an instruction file is a
  surface: a markdown file, or, inside a `.claude` tree or the resolved
  `${CLAUDE_CONFIG_DIR:-~/.claude}`, a `settings.json`, `settings.local.json` or `hooks.json`, or
  any file beneath a `skills/` directory.
- **`anchor`** is always an excerpt anchor (`e:`), over the flagged line's text, discriminated by the
  enclosing heading path. Every check in this catalog is about a sentence, so none takes the
  whole-surface form (`s:`): an `s:` finding survives every edit to its file, including the edit
  that remediates it.

`primary_site`, the `Surface:Line` cell, the rendered heading path, and the Finding and Proposed
change prose are presentation. None of them enters the hash.

## Deriving the id

`scripts/finding-ids.sh` derives every constituent from a scan-shaped row, reading the flagged line
and its heading path from the file and delegating the hashing to `audit-pass`'s
`finding-identity.sh`, so a lane never computes an anchor by hand:

```shell
printf '%s\n' 'reference/spoke.md:3:I33' 'a.md:4|b.md:9|I15' |
  bash "<skill-dir>/scripts/finding-ids.sh"
```

A single-site row is `<path>:<line>:<id>`; the pairwise row is `<pathA>:<lineA>|<pathB>:<lineB>|I15`.
Each output line is the input row, then `finding_id/v1`, then `group/v1`, then one `surface=anchor`
field per site, tab-separated. `--records` prints the same finding as a JSON record that
`finding-identity.sh validate-record` accepts. A row the script cannot identify (an id with no
template, a pairwise row for a check that is not I15, a surface outside the repository and the home
directory, a file under the home directory that is not an instruction file, an unreadable line)
prints `#REFUSED`, the row, and the reason, and is never given an id.

## Claim templates

| Check | Claim template | Sites |
|---|---|---|
| I6 | `I6.bare-prohibition` | 1 |
| I7 | `I7.request-without-reason` | 1 |
| I8 | `I8.model-era-reaudit` | 1 |
| I8-a | `I8-a.instructed-self-check` | 1 |
| I8-b | `I8-b.conservative-reporting` | 1 |
| I8-c | `I8-c.dont-think-directive` | 1 |
| I8-d | `I8-d.short-turn-assumption` | 1 |
| I8-e | `I8-e.forced-interim-status` | 1 |
| I8-f | `I8-f.think-carefully-steer` | 1 |
| I9 | `I9.example-hygiene` | 1 |
| I10 | `I10.reasoning-echo-directive` | 1 |
| I11 | `I11.mcp-where-cli-equivalent` | 1 |
| I12 | `I12.stale-harness-claim` | 1 |
| I13 | `I13.non-loading-citation` | 1 |
| I14 | `I14.already-loaded-retrieval` | 1 |
| I15 | `I15.cross-surface-conflict` | 2 |
| I16 | `I16.definition-site-locality` | 1 |
| I17 | `I17.thinking-disabled-where-forbidden` | 1 |
| I17-a | `I17-a.universal-thinking-off-switch` | 1 |
| I17-b | `I17-b.mid-session-change-without-cost` | 1 |
| I17-c | `I17-c.fixed-thinking-budget` | 1 |
| I17-d | `I17-d.tool-reliance-without-nudge` | 1 |
| I18 | `I18.thinking-blocks-altered` | 1 |
| I18-a | `I18-a.leading-thinking-block-required` | 1 |
| I19 | `I19.benchmark-figure-without-trigger` | 1 |
| I20 | `I20.prefilled-response` | 1 |
| I21 | `I21.effort-pinned-across-model-change` | 1 |
| I22 | `I22.routing-without-baseline` | 1 |
| I23 | `I23.self-estimated-budget-trigger` | 1 |
| I24 | `I24.silent-generalization` | 1 |
| I25 | `I25.rejected-sampling-parameter` | 1 |
| I26 | `I26.generic-negative-steering` | 1 |
| I27 | `I27.effort-lowered-for-brevity` | 1 |
| I28 | `I28.trigger-emphasis` | 1 |
| I28-a | `I28-a.forced-compliance-emphasis` | 1 |
| I28-b | `I28-b.blanket-tool-default` | 1 |
| I29 | `I29.body-restatement` | 1 |
| I29-a | `I29-a.description-restatement` | 1 |
| I29-b | `I29-b.sibling-restatement` | 1 |
| I30 | `I30.stamp-without-recheck-trigger` | 1 |
| I31 | `I31.migration-relative-phrasing` | 1 |
| I32 | `I32.route-to-absent-skill` | 1 |
| I33 | `I33.spoke-self-description` | 1 |
| I34 | `I34.maintainer-rationale-in-yaml` | 1 |
| I35 | `I35.settled-answers-instruction` | 1 |

A new catalog check lands here and in `scripts/finding-ids.sh` in the same change;
`scripts/finding-ids.test.sh` fails when the two tables or the catalog's check headings disagree.
