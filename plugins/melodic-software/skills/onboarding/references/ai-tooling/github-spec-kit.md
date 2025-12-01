# GitHub Spec Kit

Last Verified: 2025-11-16  
Requires: Python 3.12+, uv  

[GitHub Spec Kit](https://github.com/github/spec-kit) is a toolkit for **spec-driven development** that helps you generate and iterate on product/engineering specs, plans, and tasks alongside AI agents like GitHub Copilot and Claude Code.

This doc focuses on installing and running Spec Kit using **uv**.

---

## Prerequisites

1. **Python 3.12+ and uv installed**
   - Python and uv installation documentation is available via the **python** skill
   - Invoke the skill for platform-specific installation guidance
2. **Git installed and configured**
   - You need Git to fetch Spec Kit from GitHub.

Once Python 3.12+ and uv are installed, you can manage Spec Kit as a uv “tool”.

---

## Install Spec Kit CLI with uv

Spec Kit provides the `specify-cli` tool from the `github/spec-kit` repository.  
Install it globally via uv:

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
```

If you need to force a reinstall or upgrade from the Git repo:

```bash
uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git
```

Then verify:

```bash
specify --help
```

If `specify` is not found, ensure that your uv tool bin directory (typically `~/.local/bin` on macOS/Linux or `%USERPROFILE%\.local\bin` on Windows) is on your PATH.

---

## Managing Spec Kit with uv

You can use the standard uv tool commands to manage Spec Kit:

```bash
# List all uv-managed tools (including specify-cli)
uv tool list

# Upgrade specify-cli (if installed from a versioned source)
uv tool upgrade specify-cli

# Uninstall specify-cli
uv tool uninstall specify-cli
```

For more details on uv’s tool management, see the official uv docs:  
<https://docs.astral.sh/uv/getting-started/installation/> and <https://docs.astral.sh/uv/>.

---

## Next steps

Once `specify-cli` is installed:

- Initialize or open a Spec Kit-enabled repo (for example, one generated from Spec Kit templates).
- Use the built-in Spec Kit commands like `/speckit.init`, `/speckit.plan`, `/speckit.tasks`, and `/speckit.implement` as described in the Spec Kit README:  
  <https://github.com/github/spec-kit>

Refer to the Spec Kit docs and README for the full workflow and best practices around spec-driven development on GitHub.
