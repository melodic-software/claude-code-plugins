# L1-derivability — `M-repo-root`

10 files. Repo root, `.claude/`, `.github/`, `prompts/`. Contains all three `T1` always-loaded files.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 8 |
| `out-of-scope: functional artifact` | 2 |

No deletions, no pointer conversions, no cache verdicts.

## `AGENTS.md` (0 bytes) — verdict: `keep-owns-facts` [audience: agent, T1]

| Factor | Reading |
|--------|---------|
| Derivable? | not applicable — the file has no content to derive |
| Re-derivation cost | not applicable |
| Drift risk | none |
| Fact ownership | owns a **decision**: the emptiness is deliberate and the slot is deliberately preserved |

The rubric requires checking `git log` before ruling on an empty file, and the check is decisive.
`git log -1 -- AGENTS.md` is commit `6763cf77` ("chore: blank the retired standards-synced
AGENTS.md (#2991)"), whose body states:

> Blank `AGENTS.md` to 0 bytes and update the provenance pointer in `docs/CLOUD-SESSIONS.md`.

and

> The file is blanked rather than deleted to preserve the slot (`CLAUDE.md`'s `@AGENTS.md` import
> stays).

Deleting it breaks `CLAUDE.md`'s import and reverses a recorded decision. This is the rubric's own
worked example ("An empty root `CLAUDE.md` whose `git log` shows it was deliberately emptied … is a
recorded decision"), reached independently here.

## `CLAUDE.md` (11 bytes, `@AGENTS.md`) — verdict: `keep-owns-facts` [audience: agent, T1]

The single-line import is the mechanism that preserves the slot above. Landed by `adc7b8ed`
("docs(claude): bridge AGENTS.md into Claude sessions with a one-line import (#2887)"). It owns the
bridge decision, and the always-loaded cost is 11 bytes. The PLAN already directs lanes not to treat
the near-empty T1 budget as a defect; L1 concurs and proposes no change.

## `.claude/rules/vendor-docs-are-not-style.md` (455 bytes) — verdict: `keep-owns-facts` [audience: agent, T1]

Owns a cross-cutting constraint that no single file states: that the vendor tree is reference
material whose formatting must not propagate into this repo's own instruction surfaces, and that the
`ai-slop` audit's exclusion of that tree is deliberate rather than an oversight. Exploration finds
the exclusion; it never finds the intent behind it.

## The remaining five `keep-owns-facts`

`README.md`, `SECURITY.md`, `REVIEW.md`, `prompts/cloud-bootstrap-rollout.md`,
`prompts/loops/loop-lane-prompts.md`.

`REVIEW.md` is worth naming: it is injected verbatim as the highest-priority instruction block for
every review agent, and its own lines 3-6 record the constraint that makes its shape non-obvious
("It does not expand `@` imports and does not read a cited file into the prompt. It sees only the
words printed below"). That is a platform constraint no code states.

`prompts/cloud-bootstrap-rollout.md` and `prompts/loops/loop-lane-prompts.md` are paste kits, which
looks like the functional-artifact shape, but both carry dated rationale and ownership tables around
the pasteable blocks (`cloud-bootstrap-rollout.md:12` "## Why this layout (verified 2026-08-15)";
`loop-lane-prompts.md:8-12` names "every owner of every open-item state the machinery produces —
**including the states that carry more than one owner, and the states that are deliberately or
currently unowned**"). A cross-cutting ownership map of deliberately-unowned states is precisely the
invariant class no single file holds. Both keep.

## Out-of-scope: functional artifacts (2)

```text
.claude/source-control.md
.github/pull_request_template.md
```

`.claude/source-control.md` is configuration the `source-control` skills read at runtime (its own
header: "resolved by `/source-control:commit` and `/source-control:pull-request`"), and
`.github/pull_request_template.md` is a template GitHub consumes. Both are inputs, not prose, so the
four factors do not apply.
