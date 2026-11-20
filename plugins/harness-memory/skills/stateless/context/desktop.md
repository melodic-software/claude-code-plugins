# Claude Desktop / claude.ai account memory (direction only)

This is a **separate, server-side store** from Claude Code auto memory. It belongs to your
claude.ai account (used by the Claude Desktop app and claude.ai chat), not local files under
`~/.claude/`. This skill cannot read or delete it, and can only tell you where to go.

Because it is account-side, "going stateless" in Claude Code does nothing to it, and vice
versa. Handle both if you want to be stateless everywhere.

## Direction steps (the current labels are read live)

We direct the user to three things in the account's settings and name no menu label as
verified, since the product UI changes; the current labels and steps for the first two are in the
article below, and the app's own privacy settings carry the third:

1. **Turn account memory off**, so no new memories are saved.
2. **Clear the memories already saved**, as its own step: we never present turning memory off
   as deleting what is saved, because going stateless means nothing kept.
3. **Review the chat-data and model-training setting**, because being stateless everywhere
   reaches past memory, and the choice is the user's.

## Honesty notes

- Do not claim the account memory was deleted, since you cannot verify it from here. Confirm the
  outcome is the user's to check in the app.
- If the user needs exact current steps, point them to the Help Center article below rather than
  asserting labels from training data.

- **Pointer**: in
  [Use Claude's chat search and memory to build on previous context](https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context),
  the [Turn memory on or off for your account](https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context#h_c9b905eb3f)
  and [View and manage your memory](https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context#h_463c0c336e)
  sections.
