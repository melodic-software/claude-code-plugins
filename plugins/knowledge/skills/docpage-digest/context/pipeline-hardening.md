# Docpage-digest pipeline hardening

Spoke for the interview-ratified contract in `SKILL.md` (fence mandate, standing
gates, freeze/pin, subagent-death ladder). The skill file owns the binding
rules and each gate's blind spots; this file owns the format, invocation, and
pin-manifest shape so `SKILL.md` stays a procedure.

**Prerequisite:** `python3` (3.9+) on PATH for the two standing gates under
`scripts/`. Missing Python means say so and stop — there is no agent-judgment
fallback for a deterministic quote/snippet check.

## Fence mandate

Every verbatim quote — Key claims and Prompt snippets — lives in a **column-0
fenced container**. Labels on Key claims are bold `**CN.**` (C1, C2, …).

Why fencing is the only remedy that held:

- A *blockquote* quote is rewritten by the markdownlint-cli2 PostToolUse hook
  (`*` list markers become `-`; ordered lists renumber).
- A *bare inline code span* cannot hold a trailing space through that hook
  (three attested sites).
- `check-quotes.py`'s per-line `.strip()` then hid indented-fence corruption
  introduced by a REPAIR pass.

Shape (Key claims):

- A `## Key claims` (or `## Key claims (verbatim)`) heading.
- One `**CN.**` label per claim, optional tag after the label.
- Immediately after, a column-0 fence whose payload is the quote *bytes* —
  trailing spaces kept, no indent on the opener, no `.strip()` anywhere.

Shape (Prompt snippets):

- A `## Prompt snippets` (or `## Prompt snippets (exact)`) heading.
- Each snippet is a column-0 fence. A recognised none-marker (`none`, `n/a`,
  `(none)`, `no prompt snippets`) is the only legal empty form.

Blockquotes and inline code spans are forbidden as quote carriers.

## Standing gates

Run after the pin (below), before verifier arms are believed complete:

```text
python3 "${CLAUDE_PLUGIN_ROOT}/skills/docpage-digest/scripts/check-fences-exact.py" \
  --source <work-root>/source.md \
  --digest <work-root>/digests/01-….md \
  --digest <work-root>/digests/02-….md

python3 "${CLAUDE_PLUGIN_ROOT}/skills/docpage-digest/scripts/check-snippets.py" \
  --source <work-root>/source.md \
  --digest <work-root>/digests/01-….md \
  --digest <work-root>/digests/02-….md
```

Use `source.txt` when the original is a PDF extraction. Repeat `--digest` once
per digest file. A PASS prints the files, counts, and fields exercised; read it
as covering only that. Zero parsed claims or an unparsed Prompt-snippets
section is a failure, never a skip.

**A gate is a claim that needs its own evidence.** Do not believe a PASS until
that gate's negative-control suite has failed the known-bad fixtures. For these
two gates the evidence is `scripts/test_check_fences_exact.py` and
`scripts/test_check_snippets.py` (empty input, zero-parse, indented fence,
stripped trailing space, blockquote/inline substitutes, fabricated
quote/snippet). A newly written gate is not a required artifact until that
suite is green — the ordering is the one `SKILL.md` already states.

## Freeze / pin

Pin the tree on **agent-REPORTED completion**, never on file presence. A digest
file appearing on disk does not mean its agent is done (a unit's agent rewrote
its file seven minutes after a presence-based pin).

After every dispatched digest agent has *returned*:

1. Hash each frozen path (digests, INDEX.md, source.\*).
2. Write `<work-root>/verification/pin-manifest.json`:

```json
{
  "schema": "docpage-pin/v1",
  "pinned_at": "<ISO-8601 Z>",
  "pinned_on": "agent-reported-completion",
  "files": [
    {"path": "source.md", "sha256": "<hex64>"},
    {"path": "INDEX.md", "sha256": "<hex64>"},
    {"path": "digests/01-slug.md", "sha256": "<hex64>"}
  ]
}
```

That manifest freezes the tree for the verification window. Each arm hashes
what it audits and states those hashes in its verdict. A mismatch is BLOCKED,
not a content finding — re-pin and re-run the arm.

**A verdict file on disk is an intermediate write, never a report.** Do not
apply corrections, re-pin, or tick an arm complete because a verdict file
appeared. Wait for the arm to return.

## Subagent-death / usage-limit ladder

Dominant failure mode of the cloud-fleet run, ahead of any content defect
(lost agents, killed completion reports, mid-audit kills, slot exhaustion,
refused fan-out). `SKILL.md`'s degraded-verifier rule covers a *missing*
cross-vendor arm, not a session that cannot spawn.

1. **Retry window** — re-dispatch the same brief once; record the death and
   the retry.
2. **Inline-with-disclosure** — if the retry also dies, the orchestrator
   completes that unit inline and records `inline-with-disclosure` naming the
   dead slot and the unit.
3. **Degraded marker + re-run trigger** — if inline is impossible, write the
   marker on the checklist (and the verdict header if an arm is what died)
   and name the unfinished units. Do not tick the phase complete.

Silence is not a rung.
