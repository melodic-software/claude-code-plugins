# Claude Desktop / claude.ai account memory (direction only)

This is a **separate, server-side store** from Claude Code auto memory. It belongs to your
claude.ai account (used by the Claude Desktop app and claude.ai chat), not local files under
`~/.claude/`. This skill cannot read or delete it — it can only tell you where to go.

Because it is account-side, "going stateless" in Claude Code does nothing to it, and vice
versa. Handle both if you want to be stateless everywhere.

## Guided steps (verify labels in the live app)

The exact menu labels are not verified against a fetched doc in this session and the product
UI changes — treat these as directions to the right area, and confirm against what you see:

1. Open **Settings** in Claude Desktop or on claude.ai, and find the **Memory** (or
   personalization) section.
2. **Turn the memory toggle off** to stop new memories being saved. Turning it off does
   **not** delete what is already saved.
3. **Clear existing saved memories** using the separate "clear"/"delete" control in that
   section — this is a distinct action from the toggle.
4. Review the **privacy / model-training** setting while you are there: whether your chats can
   be used to improve models is a separate control from memory. Adjust it to your preference.

## Honesty notes

- Do not claim the account memory was deleted — you cannot verify it from here. Confirm the
  outcome is the user's to check in the app.
- If the user needs exact current steps, point them to Anthropic's official Help Center for
  the Claude app "Memory" article rather than asserting labels from training data.
