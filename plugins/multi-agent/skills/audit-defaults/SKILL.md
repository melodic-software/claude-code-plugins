---
description: "Recheck every bundled multi-agent role default (model, effort, the fan-out guard) against the upstream pointer recorded beside it, and report which defaults have drifted or whose recheck trigger has fired, each with fetched evidence and a proposed diff to reference/defaults.yaml. Proposes only; never edits a file. Use when: 'are the routing defaults current', 'audit the role map', 'recheck model defaults', 'did the workflow guidance change', 'new model released, check the defaults', or when an as-of date in defaults.yaml looks old."
argument-hint: "[<role>|fanout]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Recheck the routing defaults against their upstream sources
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/list-pointers.sh:*)", "WebFetch", "Read", "Skill"]
shell: bash
---

## Purpose

Each default in
[`${CLAUDE_PLUGIN_ROOT}/reference/defaults.yaml`](${CLAUDE_PLUGIN_ROOT}/reference/defaults.yaml)
records its basis as a pointer, an as-of date and a recheck trigger. This skill
reads those records, goes to each source, and says whether the default still
follows from it. The defaults change only through a reviewed edit to that file.

## Steps

1. **List the records.** Run:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/list-pointers.sh
   ```

   The first block is `owner<TAB>key<TAB>value` for every `pointer*`, `as_of`
   and `recheck`; the second is the current value of every default. With an
   argument, keep only that owner's rows. Done when you hold the list of
   distinct sources to read.
2. **Fetch each source.** A URL pointer: fetch it with WebFetch and read the
   anchored section. The `/workflow-authoring` pointer names a skill bundled
   with Claude Code: load it with the Skill tool when it is in the skill
   listing and read what it says about `opts.model` and `opts.effort`; when it
   is not listed, record that source as unread rather than recalling it. Done
   when every source is marked read or unread.
3. **Judge each default.** For each owner, decide one of:
   - `current`: the source still supports the value.
   - `drifted`: the source now supports a different value. Name it.
   - `trigger fired`: the recheck event happened (a new model row, a changed
     section) even if the value still holds. Say what happened.
   - `unread`: a source could not be fetched or loaded.

   Done when every owner has a verdict.
4. **Propose.** For every non-`current` row, write the diff to
   `defaults.yaml` you would make, including the new `as_of`. Do not apply it.
   Done when the diff block, or `No changes proposed.`, is written.

## Output

A table: owner, key, current value, verdict, evidence (the pointer plus at
most one short quoted sentence that decides it), proposed value. Then the
proposed diff in one fenced `diff` block, or `No changes proposed.` State how
many sources were read and how many were not.

## What this skill does NOT do

- Edit `defaults.yaml`, a consumer layer, or any script.
- Judge a consumer's own overrides. Their layer is their decision.

## Next

/multi-agent:route all, to see the resolved map after an accepted change lands.

## Gotchas

- A `current` verdict needs the fetched text. A page that fails to load is
  `unread`, never `current`.
- The cost page's measurements are per model generation. A new model row there
  is a recheck event for the worker and the fan-out guard even when no number
  for the old models moved.
- The fan-out guard is a user requirement as well as an upstream-backed
  default: propose changing `fanout.model` when the evidence supports it, but
  never propose turning the guard off.
