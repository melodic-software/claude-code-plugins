## Why the in-context listing cannot be the sole source

Officially documented behavior of the skill listing, and the reason this ladder exists at all:

- The listing **always carries every skill name**, but when many skills are installed Claude Code
  **shortens descriptions to fit a character budget**, and on overflow it **drops descriptions
  starting with the skills you invoke least**. The budget scales with the context window
  (`skillListingBudgetFraction`, default 1%); `skillListingMaxDescChars` caps each entry.
- A skill set to `disable-model-invocation: true` is **absent from the model's listing entirely**:
  not truncated, gone.
