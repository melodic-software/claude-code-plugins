---
type: handoff
handoff_shape: 3
date: 2026-09-01T10:00:00Z
topic: widget
session_id: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
transcript: /work/projects/-work-repo/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jsonl
chain:
  - 20260901T100000Z-handoff-widget.md
---

## Original goal

**Goal (verbatim, 2026-09-01):**

> Make the widget importer idempotent so a re-run never duplicates rows.

**Amended:** None.

Opening ask:
Make the widget importer idempotent.

**Next action serves it by:** the re-run test proves a second import adds nothing.

## Resumption brief

A shape-3 file: this validator must refuse to judge it and must never rewrite it.

## Resume prompt

`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @/work/repo/.work/handoffs/20260901T100000Z-handoff-widget.md, confirm its Original goal still governs the remaining next steps, then continue them. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
Prior session: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.
Handoff origin: ssh://git@github.com/example/repo .work/handoffs/20260901T100000Z-handoff-widget.md
Next:
Add the re-run test
──────────────────────────────────────────────────────────

Or reopen the producing session in place: `claude --resume aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`.
