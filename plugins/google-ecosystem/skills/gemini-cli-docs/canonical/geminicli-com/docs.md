---
source_url: http://geminicli.com/docs
source_type: llms-txt
content_hash: sha256:d70d43edb15e8d1568e5b6438f51a580685ab6c2280975c48152357521992647
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"a812f576ea6a5b764c0114f87100357b16f67912d7e8ee81f8e3076de6307a66"'
last_modified: Sun, 30 Nov 2025 17:03:27 GMT
---

# Welcome to Gemini CLI documentation

This documentation provides a comprehensive guide to installing, using, and
developing Gemini CLI. This tool lets you interact with Gemini models through a
command-line interface.

## Overview

Gemini CLI brings the capabilities of Gemini models to your terminal in an
interactive Read-Eval-Print Loop (REPL) environment. Gemini CLI consists of a
client-side application (`packages/cli`) that communicates with a local server
(`packages/core`), which in turn manages requests to the Gemini API and its AI
models. Gemini CLI also contains a variety of tools for tasks such as performing
file system operations, running shells, and web fetching, which are managed by
`packages/core`.

## Navigating the documentation

This documentation is organized into the following sections:

### Get started

- **[Gemini CLI Quickstart](/docs/get-started):** Let's get started with
  Gemini CLI.
- **[Installation](/docs/get-started/installation):** Install and run Gemini CLI.
- **[Authentication](/docs/get-started/authentication):** Authenticate Gemini
  CLI.
- **[Configuration](/docs/get-started/configuration):** Information on
  configuring the CLI.
- **[Examples](/docs/get-started/examples):** Example usage of Gemini CLI.
- **[Get started with Gemini 3](/docs/get-started/gemini-3):** Learn how to
  enable and use Gemini 3.

### CLI

- **[CLI overview](/docs/cli):** Overview of the command-line interface.
- **[Commands](/docs/cli/commands):** Description of available CLI commands.
- **[Enterprise](/docs/cli/enterprise):** Gemini CLI for enterprise.
- **[Model Selection](/docs/cli/model):** Select the model used to process your
  commands with `/model`.
- **[Settings](/docs/cli/settings):** Configure various aspects of the CLI's
  behavior and appearance with `/settings`.
- **[Themes](/docs/cli/themes):** Themes for Gemini CLI.
- **[Token Caching](/docs/cli/token-caching):** Token caching and optimization.
- **[Tutorials](/docs/cli/tutorials):** Tutorials for Gemini CLI.
- **[Checkpointing](/docs/cli/checkpointing):** Documentation for the
  checkpointing feature.
- **[Telemetry](/docs/cli/telemetry):** Overview of telemetry in the CLI.
- **[Trusted Folders](/docs/cli/trusted-folders):** An overview of the Trusted
  Folders security feature.

### Core

- **[Gemini CLI core overview](/docs/core):** Information about Gemini CLI
  core.
- **[Memport](/docs/core/memport):** Using the Memory Import Processor.
- **[Tools API](/docs/core/tools-api):** Information on how the core manages and
  exposes tools.
- **[Policy Engine](/docs/core/policy-engine):** Use the Policy Engine for
  fine-grained control over tool execution.

### Tools

- **[Gemini CLI tools overview](/docs/tools):** Information about Gemini
  CLI's tools.
- **[File System Tools](/docs/tools/file-system):** Documentation for the
  `read_file` and `write_file` tools.
- **[MCP servers](/docs/tools/mcp-server):** Using MCP servers with Gemini CLI.
- **[Shell Tool](/docs/tools/shell):** Documentation for the `run_shell_command`
  tool.
- **[Web Fetch Tool](/docs/tools/web-fetch):** Documentation for the `web_fetch`
  tool.
- **[Web Search Tool](/docs/tools/web-search):** Documentation for the
  `google_web_search` tool.
- **[Memory Tool](/docs/tools/memory):** Documentation for the `save_memory`
  tool.
- **[Todo Tool](/docs/tools/todos):** Documentation for the `write_todos` tool.

### Extensions

- **[Extensions](/docs/extensions):** How to extend the CLI with new
  functionality.
- **[Get Started with Extensions](/docs/extensions/getting-started-extensions):**
  Learn how to build your own extension.
- **[Extension Releasing](/docs/extensions/extension-releasing):** How to release
  Gemini CLI extensions.

### IDE integration

- **[IDE Integration](/docs/ide-integration):** Connect the CLI to your
  editor.
- **[IDE Companion Extension Spec](/docs/ide-integration/ide-companion-spec):**
  Spec for building IDE companion extensions.

### About the Gemini CLI project

- **[Architecture Overview](/docs/architecture):** Understand the high-level
  design of Gemini CLI, including its components and how they interact.
- **[Contributing & Development Guide](https://github.com/google-gemini/gemini-cli/blob/main/CONTRIBUTING.md):** Information for
  contributors and developers, including setup, building, testing, and coding
  conventions.
- **[NPM](/docs/npm):** Details on how the project's packages are structured.
- **[Troubleshooting Guide](/docs/troubleshooting):** Find solutions to common
  problems.
- **[FAQ](/docs/faq):** Frequently asked questions.
- **[Terms of Service and Privacy Notice](/docs/tos-privacy):** Information on
  the terms of service and privacy notices applicable to your use of Gemini CLI.
- **[Releases](/docs/releases):** Information on the project's releases and
  deployment cadence.

We hope this documentation helps you make the most of Gemini CLI!
