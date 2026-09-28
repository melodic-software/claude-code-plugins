---
description: "Draw one entity's state diagram from an explicit XState createMachine block or a Stateless Configure/Permit table. Ad hoc status assignments are refused. Use when: 'map states', 'state diagram', 'state machine', 'unreachable state', 'dead-end state'. Skip when: the question is a request trace (/architecture:map-flow) or message topology (/architecture:map-events)."
argument-hint: "[entity] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Draw a cited state diagram, or refuse when the table is not explicit
---

## Repository context

The current repository is both the CONSUMER, whose convention home declares where artifacts land,
and the DEFAULT SUBJECT, the repository whose tracked source declares the state machine.

Collect with an **individual** Bash call, one command per call: the project root,
`git rev-parse --show-toplevel`. Treat a failure (not a repository, git unavailable) as an unknown
value and carry on; `${CLAUDE_PROJECT_DIR}` is the resolver's `--root` either way. An optional
`[entity]` argument selects one machine when the record holds several.

## Purpose

Answer "which states exist, and which transitions leave them" from an explicit transition table.
Every transition cites a file. The scripts collect and render. Do not draw a transition the script
did not emit. A status assignment scattered through the code is not a transition.

## Resolve home

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. This skill writes into `architecture_dir`.
It does not read `landscape_dialect` and it does not add a dialect key. A state diagram is not a
C4 diagram type.

Run `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"` and
follow the exit code. Never parse the root instruction file yourself. Exit 0 means read
`<home>/architecture/README.md` for `architecture_dir`. Exit 1, 2, and 3 mean there is no declared
home.

Per key, in order: `--out <dir>` wins for this run alone, then a declared `architecture_dir`, then
one question. `architecture_dir` has NO default. An undeclared and unconfirmed home, including
every non-interactive run, STOPS and points at `/architecture:setup`. Do not invent a directory.

This skill never writes the consumer's root instruction file or its topic doc.

## Build the record

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-states.sh" \
  --repo "<subject-repo>" --generated-on "<YYYY-MM-DD>" \
  --out "<architecture_dir>/states.json"
```

The record is schema_version 1 in the one-object-per-line layout the script writes. The shipped
libraries are XState `createMachine` and Stateless `Configure` / `Permit` / `PermitIf`. Confidence
is `high` only when every transition came from one of those tables. Ad hoc `.Status =` assignments,
and an XState `invoke`, are refusals: the record says so and the renderer draws no transitions.

Several entities in one record are not a diagram until the operator names one.

`subject` is the github.com origin repository name when that remote resolves, otherwise the
directory basename.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-states.sh" \
  --record "<architecture_dir>/states.json" --out "<architecture_dir>" \
  --entity "<entity-or-omit>"
```

Write `states.json` first, then render from it. The picture is a mermaid `stateDiagram-v2` in
`states.md`. One entity per diagram. Several entities and no `--entity` exits 3, names both, and
draws nothing.

The script prints one summary line on stdout:
`states: status=<drawn|refused> reason=<reason|none> confidence=<c> entity=<id|none> states=<n> transitions=<n> unreachable=<n> dead_ends=<n>`.
Keep it for the report.

Exit 1 means the record is unreadable or not in the one-object-per-line layout. Nothing was
written. Report that message. Do not reformat the record by hand and do not draw from it.

## Close with the report

End every run with this block, in this order:

- **Artifacts**: each path written, or `none written` when the run stopped before a home existed.
- **Status**: `drawn` or `refused`, and the reason when it is a refusal.
- **Entity**: the id, or that several were found and none was chosen.
- **Confidence**: the summary's `confidence=`.
- **Findings**: `unreachable=` and `dead_ends=` from the summary line.
- **Dialect**: mermaid `stateDiagram-v2`. `landscape_dialect` was not read. No key was added.

## What this skill does NOT do

- Treat an ad hoc status assignment as a transition.
- Infer a missing guard, or a transition that skips an expected path. No expected path is declared.
- Chart message topology or a request trace. Those are `/architecture:map-events` and
  `/architecture:map-flow`.
- Add a dialect key, or read `landscape_dialect`. A state diagram is not a C4 type.
- Fetch anything, or edit a source file. The only writes are `states.json` and `states.md` under
  the resolved output directory.
- Invent a home.

## Next

- A transition leaves the process: `/architecture:map-events`.
- The diagram settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **A state diagram is not a C4 diagram.** Claim: the C4 diagrams are system context, containers,
  components, and code, plus system landscape, dynamic, and deployment. None of those is a state
  machine. Basis: <https://c4model.com/diagrams>, fetched 2026-09-28. As of 2026-09-28. Recheck
  when that index adds a state diagram. On firing, decide whether this skill should read
  `landscape_dialect`, and record the outcome in this plugin's `CHANGELOG.md`.
- **Only an explicit table is drawn.** Stateless `Configure` / `Permit` / `PermitIf`, and XState
  `createMachine`, are the shipped grammars. A `.Status =` assignment is a refusal. An XState
  `invoke` is a refusal and contributes no transition. Verified 2026-09-28 against the Stateless
  configure/permit shape and the XState `createMachine` shape used by the collector tests. Recheck
  when either library renames those calls.
- **One entity per diagram.** Two machines and no `--entity` is a refusal that names both. Do not
  draw them on one picture.
- **Unreachable and dead-end are findings, not a failed run.** A state in the table that no
  transition reaches is unreachable. A reachable non-final state with no outgoing transition is a
  dead-end. Neither changes the exit code of a drawn record.
- **Skip-path is not assessed.** The script has no declared expected path to compare.
- **A reformatted record is refused.** `render-states.sh` exits 1 and writes nothing.
