# Docpage-digest pipeline hardening

Spoke for the interview-ratified contract in `SKILL.md` (fence mandate, standing
gates, freeze/pin). The skill file owns the binding rules and each gate's blind
spots; this file owns the format, invocation, and pin-manifest shape so
`SKILL.md` stays a procedure. It also holds the one subagent-death ladder; the
degraded-verifier rule is in [dual-verification.md](dual-verification.md).

**Prerequisite:** `python3` (3.9+) on PATH for the two standing gates under
`scripts/`. Missing Python means say so and stop. There is no agent-judgment
fallback for a deterministic quote/snippet check. The five scripts that import a
sibling module set `sys.dont_write_bytecode` so they leave no `__pycache__` in the skill's
installed `scripts/` directory; an ad-hoc script that imports from
`<skill-dir>/scripts` runs with `python3 -B`.

## Fence mandate

Every verbatim quote, both Key claims and Prompt snippets, lives in a **column-0
fenced container**. Labels on Key claims are bold `**CN.**` (C1, C2, …).

Why fencing is the only remedy that held:

- A *blockquote* quote is rewritten by the markdownlint-cli2 PostToolUse hook
  (`*` list markers become `-`; ordered lists renumber).
- A *bare inline code span* cannot hold a trailing space through that hook.
- A per-line `.strip()` in a quote gate hides indented-fence corruption
  introduced by a repair pass.

Shape (Key claims):

- A `## Key claims` (or `## Key claims (verbatim)`) heading.
- One `**CN.**` label per claim, optional tag after the label.
- Immediately after, a column-0 fence whose payload is the quote *bytes*:
  trailing spaces kept, no indent on the opener, no `.strip()` anywhere.

Shape (Prompt snippets):

- A `## Prompt snippets` (or `## Prompt snippets (exact)`) heading.
- Each snippet is a column-0 fence. A recognized none-marker (`none`, `n/a`,
  `(none)`, `no prompt snippets`) is the only legal empty form.

Blockquotes and inline code spans are forbidden as quote carriers.

## Standing gates

Run after the pin (below), before verifier arms are believed complete:

```text
python3 "<skill-dir>/scripts/check-fences-exact.py" \
  --source <work-root>/source.md \
  --digest <work-root>/digests/01-….md \
  --digest <work-root>/digests/02-….md

python3 "<skill-dir>/scripts/check-snippets.py" \
  --source <work-root>/source.md \
  --digest <work-root>/digests/01-….md \
  --digest <work-root>/digests/02-….md

python3 "<skill-dir>/scripts/check-sources-parity.py" <work-root>

python3 "<skill-dir>/scripts/check-html-rows.py" \
  <work-root>/source.html <work-root>/digests/01-….md <work-root>/digests/02-….md
```

`check-sources-parity.py` takes the work root and reads `source.md` (else `source.txt`),
`SOURCES.md` and `digests/`. It lists every heading of the source (`#` lines and `<h1>`-`<h6>`
tags carrying an `id`, outside code fences), and fails on a mismatch with the `## Headings`
table, a gap, overlap or uncovered tail in the `## Digest map` ranges, a unit that starts off
line 1 or an H2, or unequal digest-map, `digests/` and `## Status` rows.

Run `check-html-rows.py` only when the slice keeps a `source.html` and a digest
carries `**FN.**` rows quoted from it; name each such digest. Its zero-row exit 1
is a failure there, never a skip.

Use `source.txt` when the original is a PDF extraction. Repeat `--digest` once
per digest file. A PASS prints the files, counts, and fields exercised; read it
as covering only that. Zero parsed claims or an unparsed Prompt-snippets
section is a failure, never a skip.

**A gate is a claim that needs its own evidence.** Do not believe a PASS until
that gate's negative-control suite has failed the known-bad fixtures. For these
gates the evidence is `scripts/test_check_fences_exact.py`,
`scripts/test_check_snippets.py`, `scripts/test_check_sources_parity.py` and
`scripts/test_check_html_rows.py` (empty input, zero-parse, indented fence,
stripped trailing space, blockquote/inline substitutes, fabricated
quote/snippet). A newly written gate is not a required artifact until that
suite is green. The ordering is the one `SKILL.md` already states.

## Freeze / pin

Pin the tree on **agent-REPORTED completion**, never on file presence. A digest
file appearing on disk does not mean its agent is done.

After every dispatched digest agent has *returned*:

1. Hash each frozen path (digests, SOURCES.md, source.\*). An older pin-manifest whose
   `files` list an `INDEX.md` path refers to the same artifact under its old name: re-pin it
   under `SOURCES.md` after the resume-time rename rather than treating the missing path as
   BLOCKED.
2. Write `<work-root>/verification/pin-manifest.json` by running
   `python3 <skill-dir>/scripts/pin-manifest.py <work-root>`, which does step 1 and this step and
   refuses a slice missing `source.*`, `SOURCES.md` or every digest. Its suite is
   `scripts/test_pin_manifest.py`. The written shape:

```json
{
  "schema": "docpage-pin/v1",
  "pinned_at": "<ISO-8601 Z>",
  "pinned_on": "agent-reported-completion",
  "files": [
    {"path": "source.md", "sha256": "<hex64>"},
    {"path": "SOURCES.md", "sha256": "<hex64>"},
    {"path": "digests/01-slug.md", "sha256": "<hex64>"}
  ]
}
```

That manifest freezes the tree for the verification window. Each arm hashes
what it audits and states those hashes in its verdict;
`python3 <skill-dir>/scripts/pin-manifest.py <work-root> --check` prints
`BLOCKED:` for each changed, missing or new file. A mismatch is BLOCKED, not a
content finding. Re-pin and re-run the arm.

**A verdict file on disk is an intermediate write, never a report.** Do not
apply corrections, re-pin, or tick an arm complete because a verdict file
appeared. Wait for the arm to return.

## Subagent-death / usage-limit ladder

Dominant failure mode of the cloud-fleet run, ahead of any content defect
(lost agents, killed completion reports, mid-audit kills). The
degraded-verifier rule in [dual-verification.md](dual-verification.md) covers a
*missing* cross-vendor arm, not a session that cannot spawn. This is the one
copy of the ladder; every other file points here.

0. **A concurrency refusal is not a death.** A spawn the harness
   refuses for the concurrent subagent limit is a full session, not a lost
   agent. Do not re-dispatch at once. If
   this run has agents of its own running, wait for one to return. If it has
   none, do phase work that needs no agent, or wait a few minutes with a
   Monitor wait (the Bash tool blocks a foreground `sleep`). Then dispatch the
   refused units once more, and record each wait and each refusal on the
   checklist. A unit refused again falls to rung 2 with the refusals recorded.
   Rung 1 does not apply to a refusal.
   - **Pointer**: <https://code.claude.com/docs/en/sub-agents#concurrent-subagent-limit>
     (the refusal text, what it tells the caller, and when spawning succeeds
     again).
   - **As of**: 2026-10-17
   - **Recheck trigger**: that section changes what the refusal tells Claude
     to do or when spawning succeeds again.
1. **Retry window** (an agent that died, not a refusal): re-dispatch the same
   brief once; record the death and the retry.
2. **Inline-with-disclosure**: if the retry also dies, or a unit was refused
   twice under rung 0, the orchestrator completes that unit inline and records
   `inline-with-disclosure` naming the dead slot or the refusals, and the
   unit. Inline runs on the orchestrator's model. When the publisher profile
   maps the unit to a different model (see Digest-agent model matching in the
   profile), skip this rung: wait under rung 0 again, or take rung 3. An
   inline unit's checklist line records the mapped and the actual model, and
   the verdict header and handoff carry them.
3. **Degraded marker + re-run trigger**: if inline is impossible or skipped,
   write the marker on the checklist (and the verdict header if an arm is what
   died) and name the unfinished units. Do not tick the phase complete.

Silence is not a rung.
