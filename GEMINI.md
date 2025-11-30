# GEMINI.md

## ⚠️ Agent Context & Workflow Rules ⚠️

**1. Single Source of Truth (General):**
   - **ALWAYS** read `CLAUDE.md` in the root directory first. It contains the core project conventions, commands, and setup instructions used by Claude Code.
   - Treat `CLAUDE.md` as the primary entry point for understanding the project structure and general workflows.

**2. Documentation & Domain Expertise:**
   - **Anthropic / Claude / Claude Code:**
     - For ANY task related to updating, extending, or understanding the Claude ecosystem, you **MUST** refer to:
       `plugins/claude-ecosystem/skills/docs-management`
     - Do not make assumptions. Drive all changes based on the documentation found there.
   - **Google Gemini CLI (You):**
     - For ANY task related to updating, extending, configuring, or understanding the Gemini CLI ecosystem, you **MUST** refer to:
       `plugins/google-ecosystem/skills/gemini-cli-docs`
     - This is your self-reference documentation.

**3. Change Management:**
   - Changes to the Claude ecosystem must be 100% driven by the `docs-management` skill.
   - Changes to the Gemini ecosystem must be 100% driven by the `gemini-cli-docs` skill.

## Project Overview

This repository hosts a sophisticated plugin-based architecture for an AI assistant, likely Anthropic's Claude. The core of the project is the `claude-ecosystem` plugin, which provides a comprehensive set of "skills" and "commands" for interacting with the assistant and its documentation. A new `google-ecosystem` plugin is also present, designed to provide similar functionality for Google's Gemini.

The architecture emphasizes a "pure delegation" model. Meta-skills (e.g., `skill-development`) provide high-level guidance and workflows, but delegate to a central `docs-management` skill for retrieving the actual documentation. This `docs-management` skill includes a complete Python-based system for scraping, indexing, and searching documentation, ensuring that the assistant always has access to the latest information.

The project uses a combination of Markdown files for defining skills and commands, and Python for the underlying implementation of the documentation management system. The `google-ecosystem-plugin-plan.md` indicates a strategy to replicate the search and documentation infrastructure from the `claude-ecosystem` for the Gemini CLI.

**Key Technologies:**

*   Python
*   Markdown
*   YAML for configuration
*   Python Libraries: `pyyaml`, `requests`, `beautifulsoup4`, `markdownify`, `spacy`, `yake`
*   Testing: `pytest`
*   Linting/Formatting: `ruff`, `mypy`

## Building and Running

### Dependencies

To set up the development environment for the `docs-management` skill (the core Python component), install the dependencies defined in `plugins/claude-ecosystem/skills/docs-management/pyproject.toml`.

You can install them using pip:

```bash
pip install pyyaml requests beautifulsoup4 markdownify spacy yake
python -m spacy download en_core_web_sm
```

For development, also install the development dependencies:

```bash
pip install ruff mypy pytest pytest-cov types-pyyaml types-requests types-beautifulsoup4
```

### Running Tests

Tests for the `docs-management` skill can be run using `pytest`. It is recommended to use the provided helper scripts to avoid path issues.

**On Windows (PowerShell):**

```powershell
.\plugins\claude-ecosystem\skills\docs-management\.pytest_runner.ps1
```

**On macOS/Linux:**

```bash
bash plugins/claude-ecosystem/skills/docs-management/.pytest_runner.sh
```

Alternatively, you can navigate to the skill's directory and run pytest directly:

```bash
cd plugins/claude-ecosystem/skills/docs-management
pytest tests/
```

### Documentation Management

The `docs-management` skill has a set of Python scripts for managing the documentation.

**Scraping Documentation:**

```bash
python plugins/claude-ecosystem/skills/docs-management/scripts/core/scrape_all_sources.py --parallel --skip-existing
```

**Refreshing the Index:**

```bash
# Note: CLAUDE.md mentions using python 3.12 for this command
python plugins/claude-ecosystem/skills/docs-management/scripts/management/refresh_index.py
```

## Development Conventions

*   **Plugin Structure:** Plugins are self-contained directories containing skills, agents, commands, and hooks. The `plugin.json` file in the `.claude-plugin` directory is the plugin manifest.
*   **Skills:** Skills are defined in `SKILL.md` files, which include a YAML frontmatter for metadata (`name`, `description`, `allowed-tools`) and a Markdown body for instructions. They follow a "pure delegation" pattern, querying the `docs-management` skill for detailed information.
*   **Commands:** Commands are also defined in Markdown files and provide a way to execute specific actions.
*   **Python:** Python code is used for the `docs-management` system. It is typed and formatted using `ruff` and `mypy`, with configurations in `pyproject.toml`.
*   **Testing:** `pytest` is used for testing. Tests are organized into `unit` and `integration` categories.
*   **Path Handling:** The project has specific conventions for handling paths, especially on Windows, to avoid "path doubling" issues. It's recommended to use the provided helper scripts for running tests and other commands.
*   **Contribution:** The `CLAUDE.md` file provides detailed instructions for the AI on how to interact with the repository, including what commands to use for different tasks. This implies a development workflow that is tightly integrated with the AI assistant itself.

## Agent Workflow Best Practices

*   **Prioritize Native Skill Interfaces**: When interacting with a specific skill (e.g., `gemini-cli-docs`), **ALWAYS** check its `SKILL.md` for documented CLI commands (e.g., `python scripts/core/find_docs.py`) or explicit API usage examples. These are the intended and most reliable ways to leverage the skill's capabilities.
*   **Avoid Custom Scripting (unless necessary)**: Only resort to creating temporary or custom Python scripts to interact with internal APIs (e.g., `gemini_docs_api.py`) if no direct CLI wrapper or documented usage is provided by the skill itself, or if existing wrappers are insufficient for the specific task at hand. Creating temporary scripts should be a last resort.

## Plugin Architecture & Discovery

To effectively plan and execute tasks, you must understand where tools and skills reside.

### Plugin Roots (Where to Scan)

When looking for available capabilities (skills, agents, commands), scan these locations in order:

1.  **Source Directory (Current Repo):** `plugins/`
    *   *Structure:* `plugins/<plugin-name>/skills/`, `plugins/<plugin-name>/agents/`
    *   *Primary Source:* This repository IS the source for the `claude-ecosystem` and `google-ecosystem`.
2.  **User Global Plugins:** `~/.claude/plugins` (or Windows equivalent: `%USERPROFILE%\.claude\plugins`)
3.  **Project Local Plugins:** `.claude/plugins`

### Marketplaces

*   **Global Catalog:** `~/.claude/marketplace.json`
*   **Local Catalog:** `.claude-plugin/marketplace.json` (in this repo)

### Key Ecosystems

1.  **Claude Ecosystem (`plugins/claude-ecosystem`):**
    *   Contains ALL meta-skills for Claude Code development (e.g., `skill-development`, `plugin-development`).
    *   **Use for:** Understanding how to build/modify the AI assistant itself.
2.  **Google Ecosystem (`plugins/google-ecosystem`):**
    *   Contains Gemini-specific skills (`gemini-mcp-integration`, `gemini-extension-development`).
    *   **Use for:** Planning and building Gemini CLI extensions, MCP servers, and workflows.

### Dynamic Discovery Strategy

If you need to know "what tools are available":

1.  **Read** `.claude-plugin/marketplace.json` to see defined plugins.
2.  **List** `plugins/<plugin-name>/skills` to find specific capabilities.
3.  **Read** the `SKILL.md` of any relevant skill to understand its `allowed-tools` and delegation rules.
