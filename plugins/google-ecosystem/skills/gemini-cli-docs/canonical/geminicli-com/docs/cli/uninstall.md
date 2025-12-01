---
source_url: http://geminicli.com/docs/cli/uninstall
source_type: llms-txt
content_hash: sha256:eb0d3fd017728be556d8ec858f9b3792c5936f82f6c4dcf2240df4457c32d66f
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"756ebe174a359cacab70e59680a0cf1b3fd611e28d02487cc6d4122510195216"'
last_modified: '2025-12-01T02:03:17Z'
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

## Method 2: Using npm (Global Install)

If you installed the CLI globally (e.g., `npm install -g @google/gemini-cli`),
use the `npm uninstall` command with the `-g` flag to remove it.

```bash
npm uninstall -g @google/gemini-cli
```

This command completely removes the package from your system.
