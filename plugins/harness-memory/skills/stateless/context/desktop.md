# Claude Desktop / claude.ai account memory (direction only)

This is a **separate, server-side store** from Claude Code auto memory. It belongs to your
claude.ai account (used by the Claude Desktop app and claude.ai chat), not local files under
`~/.claude/`. This skill cannot read or delete it, and can only tell you where to go.

Because it is account-side, "going stateless" in Claude Code does nothing to it, and vice
versa. Handle both if you want to be stateless everywhere.

## Guided steps (verify labels in the live app)

The exact menu labels are not verified against a fetched doc in this session and the product
UI changes, so treat these as directions to the right area, and confirm against what you see:

1. Open **Settings** in Claude Desktop or on claude.ai, and find the **Memory** (or
   personalization) section.
2. **Turn the memory toggle off** to stop new memories being saved. Turning it off does
   **not** delete what is already saved.
3. **Clear existing saved memories** using the separate "clear"/"delete" control in that
   section. This is a distinct action from the toggle.
4. Review the **privacy / model-training** setting while you are there: whether your chats can
   be used to improve models is a separate control from memory. Adjust it to your preference.

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
- **As of**: 2026-10-11
- **Recheck trigger**: the article is retitled or moved, either section is renamed, or the app's
  memory controls no longer match the guided steps above.
