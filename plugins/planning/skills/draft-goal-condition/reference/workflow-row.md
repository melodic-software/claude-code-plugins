# The workflow row: routing decisions

Detail behind the workflow-row caveats under Step 0 in [SKILL.md](../SKILL.md). Each entry is
our routing decision, in our words, with the record parts beside it. The decisions live here so
the skill can still route when the docs pages cannot be fetched. When a pointer can be read,
read it live; on a mismatch the live section wins, and this file is refreshed.

## Where the keyword form fits

We recommend the `ultracode` keyword only for a prompt a person types: at the interactive
prompt, in an IDE extension panel, in a Remote Control client, or through an Agent SDK host that
marks the input as typed by a person. For a prompt that reaches the session any other way (a
`-p` run, an SDK prompt not marked as a person's input, a scheduled task, a webhook payload or a
relayed pull request comment), we tell the user the keyword does not start a workflow there and
do not recommend it.

- **Pointer**: when the prompt that would carry the keyword does not come from a person typing
  it, fetch <https://code.claude.com/docs/en/workflows#where-the-keyword-works> live.
- **As of**: 2026-11-02
- **Recheck trigger**: that section adds or drops a prompt source, or a release note changes where
  the keyword triggers a workflow.

## Which plans reach the workflow lever

We offer the workflow lever on every paid plan and to Anthropic API, Amazon Bedrock, Google
Cloud Agent Platform and Microsoft Foundry users. On Pro we tell the user to switch on the
**Dynamic workflows** row in `/config` before the first run. When the lever is missing on a plan
that should have it, we name the off switches (that `/config` row, a settings key, an
environment variable, a managed setting) as the first thing to check.

- **Pointer**: when the user's plan or provider decides whether the lever is reachable, fetch the
  availability note at the top of <https://code.claude.com/docs/en/workflows> live (it sits above
  the first heading and has no anchor of its own); for the off switches, fetch
  <https://code.claude.com/docs/en/workflows#turn-workflows-off>.
- **As of**: 2026-11-02
- **Recheck trigger**: the note changes its plan or provider list or the Pro step, or moves under
  a heading with its own anchor; or a release note changes which plans get dynamic workflows.

## When the standing setting fits

We recommend `/effort ultracode` only when workflows are on and the session's model supports
`xhigh` effort. Otherwise we recommend the keyword form, or a plain request for a workflow, per
task.

- **Pointer**: when recommending the standing setting, fetch
  <https://code.claude.com/docs/en/model-config#when-ultracode-is-available> live.
- **As of**: 2026-11-02
- **Recheck trigger**: that section adds or drops a condition, or a release note changes when
  ultracode is available.
