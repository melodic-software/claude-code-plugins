---
source_url: http://geminicli.com/docs/cli/uninstall
source_type: llms-txt
content_hash: sha256:72ca379de3ea73cb64be1214df8bf71c535b005da1ef66f5533407769ea9ba85
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"578017eb4604106ce92c3c4bf5ba72ad627d472f228d3095f548884cc9289082"'
last_modified: '2025-12-01T20:04:32Z'
---

# Uninstalling the CLI

Your uninstall method depends on how you ran the CLI. Follow the instructions
for either npx or a global npm installation.

## Method 1: Using npx

npx runs packages from a temporary cache without a permanent installation. To
"uninstall" the CLI, you must clear this cache, which will remove gemini-cli and
any other packages previously executed with npx.

The npx cache is a directory named `_npx` inside your main npm cache folder. You
can find your npm cache path by running `npm config get cache`.

**For macOS / Linux**

```bash
# The path is typically ~/.npm/_npx
rm -rf "$(npm config get cache)/_npx"
```

**For Windows**

_Command Prompt_

```cmd
:: The path is typically %LocalAppData%\npm-cache\_npx
rmdir /s /q "%LocalAppData%\npm-cache\_npx"
```

_PowerShell_

```powershell
# The path is typically $env:LocalAppData\npm-cache\_npx
Remove-Item -Path (Join-Path $env:LocalAppData "npm-cache\_npx") -Recurse -Force
```

## Method 2: Using npm (global install)

If you installed the CLI globally (e.g., `npm install -g @google/gemini-cli`),
use the `npm uninstall` command with the `-g` flag to remove it.

```bash
npm uninstall -g @google/gemini-cli
```

This command completely removes the package from your system.
