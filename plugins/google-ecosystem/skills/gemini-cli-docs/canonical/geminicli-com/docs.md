---
source_url: http://geminicli.com/docs
source_type: llms-txt
content_hash: sha256:e8e66b6810993d3e7cafc4d3ea8debfd08bd54a9bf5e3629b32736dc8e54dc3f
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"ae6450932670e8de61d80c7e31d2eb461e8324873d4b1e7f252cf621f141b33a"'
last_modified: '2025-12-01T20:04:32Z'
---

# Welcome to Gemini CLI documentation

This documentation provides a comprehensive guide to installing, using, and
developing Gemini CLI, a tool that lets you interact with Gemini models through
a command-line interface.

## Gemini CLI overview

Gemini CLI brings the capabilities of Gemini models to your terminal in an
interactive Read-Eval-Print Loop (REPL) environment. Gemini CLI consists of a
client-side application (`packages/cli`) that communicates with a local server
(`packages/core`), which in turn manages requests to the Gemini API and its AI
models. Gemini CLI also contains a variety of tools for tasks such as performing
file system operations, running shells, and web fetching, which are managed by
`packages/core`.

## Navigating the documentation

This documentation is organized into the following sections:

### Overview

- **[Architecture overview](/docs/architecture):** Understand the high-level
  design of Gemini CLI, including its components and how they interact.
- **[Contribution guide](https://github.com/google-gemini/gemini-cli/blob/main/CONTRIBUTING.md):** Information for contributors and
  developers, including setup, building, testing, and coding conventions.

### Get started

- **[Gemini CLI quickstart](/docs/get-started):** Let's get started with
  Gemini CLI.
- **[Gemini 3 Pro on Gemini CLI](/docs/get-started/gemini-3):** Learn how to
  enable and use Gemini 3.
- **[Authentication](/docs/get-started/authentication):** Authenticate to Gemini
  CLI.
- **[Configuration](/docs/get-started/configuration):** Learn how to configure
  the CLI.
- **[Installation](/docs/get-started/installation):** Install and run Gemini CLI.
- **[Examples](/docs/get-started/examples):** Example usage of Gemini CLI.

### CLI

- **[Introduction: Gemini CLI](/docs/cli):** Overview of the command-line
  interface.
- **[Commands](/docs/cli/commands):** Description of available CLI commands.
- **[Checkpointing](/docs/cli/checkpointing):** Documentation for the
  checkpointing feature.
- **[Custom commands](/docs/cli/custom-commands):** Create your own commands and
  shortcuts for frequently used prompts.
- **[Enterprise](/docs/cli/enterprise):** Gemini CLI for enterprise.
- **[Headless mode](/docs/cli/headless):** Use Gemini CLI programmatically for
  scripting and automation.
- **[Keyboard shortcuts](/docs/cli/keyboard-shortcuts):** A reference for all
  keyboard shortcuts to improve your workflow.
- **[Model selection](/docs/cli/model):** Select the model used to process your
  commands with `/model`.
- **[Sandbox](/docs/cli/sandbox):** Isolate tool execution in a secure,
  containerized environment.
- **[Settings](/docs/cli/settings):** Configure various aspects of the CLI's
  behavior and appearance with `/settings`.
- **[Telemetry](/docs/cli/telemetry):** Overview of telemetry in the CLI.
- **[Themes](/docs/cli/themes):** Themes for Gemini CLI.
- **[Token caching](/docs/cli/token-caching):** Token caching and optimization.
- **[Trusted Folders](/docs/cli/trusted-folders):** An overview of the Trusted
  Folders security feature.
- **[Tutorials](/docs/cli/tutorials):** Tutorials for Gemini CLI.
- **[Uninstall](/docs/cli/uninstall):** Methods for uninstalling the Gemini CLI.

### Core

- **[Introduction: Gemini CLI core](/docs/core):** Information about Gemini
  CLI core.
- **[Memport](/docs/core/memport):** Using the Memory Import Processor.
- **[Tools API](/docs/core/tools-api):** Information on how the core manages and
  exposes tools.
- **[Policy Engine](/docs/core/policy-engine):** Use the Policy Engine for
  fine-grained control over tool execution.

### Tools

- **[Introduction: Gemini CLI tools](/docs/tools):** Information about
  Gemini CLI's tools.
- **[File system tools](/docs/tools/file-system):** Documentation for the
  `read_file` and `write_file` tools.
- **[Shell tool](/docs/tools/shell):** Documentation for the `run_shell_command`
  tool.
- **[Web fetch tool](/docs/tools/web-fetch):** Documentation for the `web_fetch`
  tool.
- **[Web search tool](/docs/tools/web-search):** Documentation for the
  `google_web_search` tool.
- **[Memory tool](/docs/tools/memory):** Documentation for the `save_memory`
  tool.
- **[Todo tool](/docs/tools/todos):** Documentation for the `write_todos` tool.
- **[MCP servers](/docs/tools/mcp-server):** Using MCP servers with Gemini CLI.

### Extensions

- **[Introduction: Extensions](/docs/extensions):** How to extend the CLI
  with new functionality.
- **[Get Started with extensions](/docs/extensions/getting-started-extensions):**
  Learn how to build your own extension.
- **[Extension releasing](/docs/extensions/extension-releasing):** How to release
  Gemini CLI extensions.

### IDE integration

- **[Introduction to IDE integration](/docs/ide-integration):** Connect the
  CLI to your editor.
- **[IDE companion extension spec](/docs/ide-integration/ide-companion-spec):**
  Spec for building IDE companion extensions.

### Development

- **[NPM](/docs/npm):** Details on how the project's packages are structured.
- **[Releases](/docs/releases):** Information on the project's releases and
  deployment cadence.
- **[Changelog](/docs/changelogs):** Highlights and notable changes to
  Gemini CLI.
- **[Integration tests](/docs/integration-tests):** Information about the
  integration testing framework used in this project.
- **[Issue and PR automation](/docs/issue-and-pr-automation):** A detailed
  overview of the automated processes we use to manage and triage issues and
  pull requests.

### Support

- **[FAQ](/docs/faq):** Frequently asked questions.
- **[Troubleshooting guide](/docs/troubleshooting):** Find solutions to common
  problems.
- **[Quota and pricing](/docs/quota-and-pricing):** Learn about the free tier and
  paid options.
- **[Terms of service and privacy notice](/docs/tos-privacy):** Information on
  the terms of service and privacy notices applicable to your use of Gemini CLI.

We hope this documentation helps you make the most of Gemini CLI!
