---
source_url: http://geminicli.com/docs/cli
source_type: llms-txt
content_hash: sha256:ed0401f7a5f14962968ade96e1d66dfd065ee3fbc0b21fd1818c9e4832e3c02f
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"0ef55d434418b526ec6b9c6745075edf0ea5c6f5a3c55ba3afc0ba632c51d070"'
last_modified: '2025-12-01T02:03:17Z'
---

# Gemini CLI

Within Gemini CLI, `packages/cli` is the frontend for users to send and receive
prompts with the Gemini AI model and its associated tools. For a general
overview of Gemini CLI, see the [main documentation page](/docs).

## Basic features

- **[Commands](/docs/cli/commands):** A reference for all built-in slash commands
- **[Custom Commands](/docs/cli/custom-commands):** Create your own commands and
  shortcuts for frequently used prompts.
- **[Headless Mode](/docs/cli/headless):** Use Gemini CLI programmatically for
  scripting and automation.
- **[Model Selection](/docs/cli/model):** Configure the Gemini AI model used by the
  CLI.
- **[Settings](/docs/cli/settings):** Configure various aspects of the CLI's behavior
  and appearance.
- **[Themes](/docs/cli/themes):** Customizing the CLI's appearance with different
  themes.
- **[Keyboard Shortcuts](/docs/cli/keyboard-shortcuts):** A reference for all
  keyboard shortcuts to improve your workflow.
- **[Tutorials](/docs/cli/tutorials):** Step-by-step guides for common tasks.

## Advanced features

- **[Checkpointing](/docs/cli/checkpointing):** Automatically save and restore
  snapshots of your session and files.
- **[Enterprise Configuration](/docs/cli/enterprise):** Deploying and manage Gemini
  CLI in an enterprise environment.
- **[Sandboxing](/docs/cli/sandbox):** Isolate tool execution in a secure,
  containerized environment.
- **[Telemetry](/docs/cli/telemetry):** Configure observability to monitor usage and
  performance.
- **[Token Caching](/docs/cli/token-caching):** Optimize API costs by caching tokens.
- **[Trusted Folders](/docs/cli/trusted-folders):** A security feature to control
  which projects can use the full capabilities of the CLI.
- **[Ignoring Files (.geminiignore)](/docs/cli/gemini-ignore):** Exclude specific
  files and directories from being accessed by tools.
- **[Context Files (GEMINI.md)](/docs/cli/gemini-md):** Provide persistent,
  hierarchical context to the model.

## Non-interactive mode

Gemini CLI can be run in a non-interactive mode, which is useful for scripting
and automation. In this mode, you pipe input to the CLI, it executes the
command, and then it exits.

The following example pipes a command to Gemini CLI from your terminal:

```bash
echo "What is fine tuning?" | gemini
```

You can also use the `--prompt` or `-p` flag:

```bash
gemini -p "What is fine tuning?"
```

For comprehensive documentation on headless usage, scripting, automation, and
advanced examples, see the **[Headless Mode](/docs/cli/headless)** guide.
