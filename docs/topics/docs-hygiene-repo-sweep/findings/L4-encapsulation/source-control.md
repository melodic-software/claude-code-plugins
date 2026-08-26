# L4 encapsulation. Leaked skills in `plugins/source-control`

17 violations across five skills. Two shapes: plugin-level reference docs reaching down into skill
bodies (7), and skill-to-skill reaches between `babysit-loop`, `babysit-prs`, and `pull-request` (9).
One heading-anchor cite.

`plugins/source-control/reference/` already exists as a plugin-shared surface outside every skill
directory, which makes the promote target obvious for most of these.

## V-sc-01. `plugins/source-control/reference/config-resolution.md:179`

**Owning skill:** `source-control:babysit-loop`. **Private surface:** `reference/promotion-evidence-resolution.md`. **Leak kind:** private subdir.

```text
(`skills/babysit-loop/reference/promotion-evidence-resolution.md`). Until that seam qualifies,
```

**Public surface element:** `/source-control:babysit-loop`. The plugin-level config-resolution doc
wants the promotion-evidence rule as shared vocabulary, not the skill's behavior, so the durable fix
is **Path A within the plugin**: move the rule to `plugins/source-control/reference/promotion-evidence-resolution.md`
(one directory up, outside every skill), and have the skill cite the plugin-shared copy.

**Replacement text (post-promotion):**

```text
([`promotion-evidence-resolution.md`](promotion-evidence-resolution.md)). Until that seam qualifies,
```

**Replacement text (if the promotion is deferred and only the cite is fixed):**

```text
(resolved by `/source-control:babysit-loop`, which owns the promotion-evidence rule). Until that seam qualifies,
```

## V-sc-02. `plugins/source-control/reference/review-discipline.md:306`

**Owning skill:** `source-control:babysit-loop`. **Private surface:** `reference/pre-escalation-dispatch.md`. **Leak kind:** private subdir.

```text
(`skills/babysit-loop/reference/pre-escalation-dispatch.md`). Where it has none — no subagent
```

**Public surface element:** `/source-control:babysit-loop`.

**Replacement text:**

```text
(the pre-escalation dispatch `/source-control:babysit-loop` runs). Where it has none, no subagent
```

## V-sc-03. `plugins/source-control/reference/review-discipline.md:171`

**Owning skill:** `source-control:babysit-prs`. **Private surface:** `reference/safety.md`. **Leak kind:** private subdir.

```text
gate's `ready` field alone (`skills/babysit-prs/reference/safety.md` "Two Gates, One Merge-Ready
```

**Public surface element:** `/source-control:babysit-prs`. The two-gates rule is shared discipline
across `babysit-prs`, `babysit-loop`, and `pull-request`, so **Path A within the plugin**: promote
the "Two Gates, One Merge-Ready" section into `plugins/source-control/reference/merge-readiness.md`.

**Replacement text (post-promotion):**

```text
gate's `ready` field alone ([`merge-readiness.md`](merge-readiness.md) "Two Gates, One Merge-Ready
```

## V-sc-04. `plugins/source-control/reference/review-discipline.md:271`

**Owning skill:** `source-control:babysit-prs`. **Private surface:** `reference/safety.md`. **Leak kind:** private subdir.

```text
  `skills/babysit-prs/reference/safety.md`'s Never Do Automatically entry "Resolve any thread over
```

**Replacement text (post-promotion, same target as V-sc-03):**

```text
  [`merge-readiness.md`](merge-readiness.md)'s Never Do Automatically entry "Resolve any thread over
```

## V-sc-05. `plugins/source-control/reference/review-discipline.md:303`

**Owning skill:** `source-control:babysit-prs`. **Private surface:** `reference/independent-resolution.md`. **Leak kind:** private subdir.

```text
`skills/babysit-prs/reference/independent-resolution.md` owns that contract, and two invocations
```

**Public surface element:** `/source-control:babysit-prs`.

**Replacement text:**

```text
`/source-control:babysit-prs` owns that contract, and two invocations
```

## V-sc-06, V-sc-07, V-sc-08. `plugins/source-control/skills/babysit-loop/SKILL.md` reaches into `babysit-prs`

**Owning skill:** `source-control:babysit-prs`. **Private surfaces:** `reference/loop.md`,
`reference/orchestration.md`. **Leak kind:** private subdir. Skill-to-skill, and the citations carry
section numbers (`§5.1.2`, `§5.3`), so they are pinned to the target's internal numbering as well as
its file layout.

| # | `path:line` | Verbatim | Replacement text |
|---|---|---|---|
| V-sc-06 | `plugins/source-control/skills/babysit-loop/SKILL.md:52` | ``its [loop reference](../babysit-prs/reference/loop.md) §5.1.2–§5.1.3), and the foreign-activity`` | ``the per-PR pass `/source-control:babysit-prs` runs), and the foreign-activity`` |
| V-sc-07 | `plugins/source-control/skills/babysit-loop/SKILL.md:54` | ``PR; its [orchestration reference](../babysit-prs/reference/orchestration.md)). The grace window`` | ``PR; `/source-control:babysit-prs` owns that orchestration). The grace window`` |
| V-sc-08 | `plugins/source-control/skills/babysit-loop/SKILL.md:463` | ``babysit-prs [loop reference](../babysit-prs/reference/loop.md) §5.3, that mapping owns the`` | ```/source-control:babysit-prs` owns that mapping, and it owns the`` |

Where `babysit-loop` needs the *values* rather than the behavior (the §5.1.2 grace window, the §5.3
mapping), promote those two tables to `plugins/source-control/reference/` and cite them there. The
replacement text above is the route-only form; pick per cite once the content is inspected.

## V-sc-09 through V-sc-13. `babysit-prs` reaches into `pull-request`

**Owning skill:** `source-control:pull-request`. **Private surfaces:** `reference/monitor.md`,
`reference/readiness.md`. **Leak kind:** private subdir. Five cites, all section-pinned.

| # | `path:line` | Verbatim | Replacement text |
|---|---|---|---|
| V-sc-09 | `plugins/source-control/skills/babysit-prs/reference/loop.md:124` | ``   [pull-request monitor.md](../../pull-request/reference/monitor.md) §3.0.05)`` | ``   the push-channel check `/source-control:pull-request monitor` performs first)`` |
| V-sc-10 | `plugins/source-control/skills/babysit-prs/reference/loop.md:127` | ``   [pull-request monitor.md](../../pull-request/reference/monitor.md) §3.0.1)`` | ``   the Monitor-tool fallback `/source-control:pull-request monitor` uses)`` |
| V-sc-11 | `plugins/source-control/skills/babysit-prs/reference/loop.md:386` | ``[pull-request readiness.md](../../pull-request/reference/readiness.md) "Expected PR actors":`` | ``the expected-PR-actors list `/source-control:pull-request` resolves:`` |
| V-sc-12 | `plugins/source-control/skills/babysit-prs/reference/loop.md:395` | ``[pull-request monitor.md](../../pull-request/reference/monitor.md) §3.2. Max 3 CI fix`` | ```/source-control:pull-request monitor`. Max 3 CI fix`` |
| V-sc-13 | `plugins/source-control/skills/babysit-prs/reference/loop.md:404` | ``([pull-request monitor.md](../../pull-request/reference/monitor.md) §3.3.1 step 4), which`` | ``(the CI-fix step of `/source-control:pull-request monitor`), which`` |

`monitor` and `readiness` are documented actions/phases of `/source-control:pull-request` (its action
table lists `prep`, `create`, `monitor`, `comments`, `merge`, `status`, `full`), so the public
surface genuinely covers what these cites want. No missing action to file.

## V-sc-14. `plugins/source-control/skills/babysit-prs/reference/stuck-checks.md:19`

**Owning skill:** `source-control:pull-request`. **Private surface:** `reference/readiness.md`. **Leak kind:** private subdir.

```text
skill's [readiness reference](../../pull-request/reference/readiness.md) (the `codex-review`
```

**Replacement text:**

```text
skill (`/source-control:pull-request status`) (the `codex-review`
```

## V-sc-15. `plugins/work-items/skills/setup/reference/overlay-ignore-probes.md:18` reaches across plugins

**Owning skill:** `source-control:setup`. **Private surface:** `reference/apply-convention.md`.
**Leak kind:** private subdir. Cross-plugin, which is the worst case for portability: `work-items`
can be installed without `source-control` at all.

```text
(`plugins/source-control/skills/setup/reference/apply-convention.md`, `layer=local`).
```

**Public surface element:** `/source-control:setup`.

**Replacement text:**

```text
(`/source-control:setup`, which applies the convention at `layer=local`).
```

## V-sc-16. `plugins/source-control/README.md:309`

**Owning skill:** `source-control:worktree`. **Private surface:** `fixtures/README.md`. **Leak kind:** private subdir.

Verbatim (the cite at the end of a long table cell):

```text
Probe, verbatim harness output and the as-of stamp: `skills/worktree/fixtures/README.md`.
```

**Public surface element:** `/source-control:worktree`. The README is quoting a measured probe
result as evidence for an option's documented behavior. That evidence is a plugin-level fact, not a
skill-internal one, so **Path A within the plugin**: move the probe record to
`plugins/source-control/reference/worktree-create-gate-probe.md`.

**Replacement text (post-promotion):**

```text
Probe, verbatim harness output and the as-of stamp: [`reference/worktree-create-gate-probe.md`](reference/worktree-create-gate-probe.md).
```

## V-sc-17. `plugins/source-control/reference/worktree-root-convention.md:66` cites a heading anchor

**Owning skill:** `source-control:worktree`. **Private surface:** `SKILL.md#the-nesting-invariant-verified`.
**Leak kind:** heading anchor. Heading anchors are body structure and are private at any depth; a
bare `SKILL.md` path would be legal but discouraged, the anchor is not.

```text
   [the nesting invariant](../skills/worktree/SKILL.md#the-nesting-invariant-verified)
```

**Public surface element:** `/source-control:worktree`. The nesting invariant is convention-level
vocabulary that a plugin-shared convention doc is already the natural owner of.

**Replacement text:**

```text
   the nesting invariant `/source-control:worktree` enforces
```

## Cross-lane observations

- L2 (progressive disclosure): `plugins/source-control/skills/babysit-prs/reference/loop.md` is both
  a heavy split candidate and the origin of five of these cites. If L2 splits it, V-sc-09..13 must
  re-resolve against the post-split layout before wave 3 applies them.
- L3 (SSOT): the merge-readiness two-gates rule (V-sc-03, V-sc-04) reads as a duplication cluster as
  well as an encapsulation one. Same target file resolves both.
