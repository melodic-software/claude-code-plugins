---
description: Prime agent with codebase understanding. Runs git ls-files, reads README, and summarizes project structure.
---

# Prime - Understand This Codebase

Execute these steps to understand the codebase structure, then provide a concise summary:

1. **List all tracked files:**

   ```bash
   git ls-files
   ```

2. **Read the README:**
   Read the README.md file (or README if no .md extension)

3. **Check for CLAUDE.md:**
   Look for CLAUDE.md or .claude/CLAUDE.md for project-specific instructions

4. **Summarize your understanding:**
   Provide a brief summary covering:
   - Project purpose (what does this do?)
   - Technology stack (languages, frameworks)
   - Key directories and their purposes
   - Entry points (main files, servers, CLI)
   - How to run/test (if documented)
   - Any special conventions or rules from CLAUDE.md

Keep the summary concise - focus on what an agent needs to know to work effectively in this codebase.
