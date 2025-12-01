---
source_url: http://geminicli.com/docs/cli/tutorials
source_type: llms-txt
content_hash: sha256:3352bc1bd22d10942e8ce583c11f9f0747f582b38ff1c9a1d3100aec2a4cb581
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"d0095fe9f292db4bc2a97449340c15b3079cd4850818269437b441f6e8931181"'
last_modified: '2025-12-01T02:03:17Z'
---

# Tutorials

This page contains tutorials for interacting with Gemini CLI.

## Setting up a Model Context Protocol (MCP) server

> [!CAUTION] Before using a third-party MCP server, ensure you trust its source
> and understand the tools it provides. Your use of third-party servers is at
> your own risk.

This tutorial demonstrates how to set up an MCP server, using the
[GitHub MCP server](https://github.com/github/github-mcp-server) as an example.
The GitHub MCP server provides tools for interacting with GitHub repositories,
such as creating issues and commenting on pull requests.

### Prerequisites

Before you begin, ensure you have the following installed and configured:

- **Docker:** Install and run [Docker].
- **GitHub Personal Access Token (PAT):** Create a new [classic] or
  [fine-grained] PAT with the necessary scopes.

[Docker]: https://www.docker.com/
[classic]: https://github.com/settings/tokens/new
[fine-grained]: https://github.com/settings/personal-access-tokens/new

### Guide

#### Configure the MCP server in `settings.json`

In your project's root directory, create or open the
[`.gemini/settings.json` file](/docs/get-started/configuration). Within the
file, add the `mcpServers` configuration block, which provides instructions for
how to launch the GitHub MCP server.

```json
{
  "mcpServers": {
    "github": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        "-e",
        "GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    }
  }
}
```

#### Set your GitHub token

> [!CAUTION] Using a broadly scoped personal access token that has access to
> personal and private repositories can lead to information from the private
> repository being leaked into the public repository. We recommend using a
> fine-grained access token that doesn't share access to both public and private
> repositories.

Use an environment variable to store your GitHub PAT:

```bash
GITHUB_PERSONAL_ACCESS_TOKEN="pat_YourActualGitHubTokenHere"
```

Gemini CLI uses this value in the `mcpServers` configuration that you defined in
the `settings.json` file.

#### Launch Gemini CLI and verify the connection

When you launch Gemini CLI, it automatically reads your configuration and
launches the GitHub MCP server in the background. You can then use natural
language prompts to ask Gemini CLI to perform GitHub actions. For example:

```bash
"get all open issues assigned to me in the 'foo/bar' repo and prioritize them"
```
