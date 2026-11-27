# Home-root leftover hints

Each baseline hint below names a home-root leftover class, the owner it was traced to, and where
to read the owner's own account. A hint is a discovery signal, never proof: the investigation in
step 2 of the skill still answers its five questions, and every `requires` condition only narrows
which entries the hint reaches. Read the pointer before relying on a claim. The scan's
`unmet_hint_conditions` says which condition kept a matching name out.

## Claude Code

- **`claude-sandbox-placeholder-*`** (Linux, files, `zero_bytes`, medium). The sandbox holds a
  write denial on a missing file with a 0-byte read-only placeholder and a killed session leaves
  it behind; `claude doctor` lists them, and they go only while no other session runs in that
  folder. The hints cover the shell startup and git files the sandbox's protected-paths list
  names, plus the package-manager and `.env` names a WSL2 home was seen to carry. A non-empty file
  is real config and never matches. `claude-sandbox-placeholder-node-modules` covers a
  `node_modules` tree holding only empty directories. Pointers:
  [0-byte placeholder files](https://code.claude.com/docs/en/sandboxing#0-byte-read-only-files-appear-at-claude-settings-paths-and-yes-and-dont-ask-again-doesnt-save),
  [protected paths](https://code.claude.com/docs/en/sandboxing#protected-paths),
  [stale sandbox mask files](https://code.claude.com/docs/en/errors#stale-sandbox-mask-files-left-by-a-killed-session).
- **`claude-json-failed-atomic-write`** (all platforms, existing hint) matches
  `.claude.json.tmp.<pid>.<hex>` at any depth, so the home root and `%USERPROFILE%` alike.
- **`claude-json-pre-onboarding-backup`** (all platforms, low). No Claude Code page names this
  file; the documented backups live under `~/.claude/backups`, and on Windows `.claude.json` sits
  in `%USERPROFILE%`. It can hold account and MCP settings, hence low. Pointer:
  [the `.claude` directory](https://code.claude.com/docs/en/claude-directory).

## Tool caches and state

| Hint | Owner | Condition, ceiling | Native command | Pointer |
|---|---|---|---|---|
| `pytest-cache` | pytest cacheprovider | medium | `pytest --cache-clear` | [cache how-to](https://docs.pytest.org/en/stable/how-to/cache.html) |
| `ruff-cache` | Ruff | medium | `ruff clean` | [cache-dir setting](https://docs.astral.sh/ruff/settings/#cache-dir) |
| `n-node-prefix` | tj/n `N_PREFIX` (Linux, macOS) | low: holds the active Node.js | `n prune`, `n uninstall` | [n README](https://github.com/tj/n#readme) |
| `pip-legacy-config-dir` | pip legacy per-user config (Linux, macOS) | `absent_children: pip.conf`, medium | `pip cache purge` (for the real cache) | [pip configuration](https://pip.pypa.io/en/stable/topics/configuration/#location) |
| `biome-legacy-home-dir` | unproven: current Biome writes nothing here | low | `biome clean` (logs only) | [biome_fs cache dir](https://github.com/biomejs/biome/blob/main/crates/biome_fs/src/utils.rs) |
| `semgrep-user-data` | Semgrep CLI | `absent_children: settings.yml` (the API token), medium | `semgrep logout` | [semgrep env.py](https://github.com/semgrep/semgrep/blob/develop/cli/src/semgrep/env.py) |
| `playwright-cli-output` | Playwright CLI output folder | medium; may hold credentials | none | [playwright-cli README](https://github.com/microsoft/playwright-cli#readme) |
| `storybook-user-settings` | Storybook per-user folder | `absent_children: main.*` (a project config), medium | none | [storybook-config-dir.ts](https://github.com/storybookjs/storybook/blob/next/code/core/src/common/utils/storybook-config-dir.ts) |
| `nvidia-cuda-compute-cache`, `-windows` | CUDA JIT cache (`~/.nv`, `%APPDATA%\NVIDIA\ComputeCache`) | medium | none | [CUDA environment variables](https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/environment-variables.html) |
| `dotnet-template-engine-cache` | `dotnet new` template engine | low: holds installed template packages | none documented (the SDK hides a cache-rebuild option) | [IPathInfo.cs](https://github.com/dotnet/templating/blob/main/src/Microsoft.TemplateEngine.Abstractions/IPathInfo.cs) |
| `mcp-remote-auth-store` | mcp-remote OAuth store | `unreferenced: mcp-remote` in the home-level MCP configs, low | none | [mcp-remote README](https://github.com/geelen/mcp-remote#readme) |
| `ubuntu-motd-shown-stamp`, `ubuntu-landscape-sysinfo-log` | Ubuntu login MOTD (Linux) | medium; recreated unless `~/.hushlogin` exists | none | [update-motd.sh](https://git.launchpad.net/ubuntu/+source/update-motd/plain/update-motd.sh?h=ubuntu/noble), [landscape-sysinfo(1)](https://manpages.ubuntu.com/manpages/noble/man1/landscape-sysinfo.1.html) |

`mcp-remote-auth-store` reads `~/.claude.json`, `~/.mcp.json`, Cursor, Windsurf, Copilot, Claude
Desktop and VS Code user configs on every platform's path. It cannot see project `.mcp.json`
files, so its reason asks for that check. MCP config locations:
[Claude Code](https://code.claude.com/docs/en/claude-directory),
[Claude Desktop](https://modelcontextprotocol.io/docs/develop/connect-local-servers),
[Cursor](https://cursor.com/docs/context/mcp),
[VS Code](https://code.visualstudio.com/docs/agents/reference/mcp-configuration).

## The evals plugin's state

- **`evals-legacy-docker-link-lock`** (Linux, `absent_siblings: .docker-link-swap.json`, medium):
  the home-root lock an earlier evals version used. The legacy manifest beside it is never a
  candidate: it lists links still to restore, and `docker-links.py restore` is its owner's
  removal. Both owner commands, and the `~/.ev` run roots that `prune-run-roots.py` prunes, are in
  [owner-registry.json](owner-registry.json).

## Kept on purpose

No baseline hint names `~/.ev`, `.ServiceHub` (C# Dev Kit; a live socket there blocks preview on
its handle check), `.dcp` (.NET Aspire control plane state), `.observability`, `.work`,
`.hushlogin`, a non-empty dotfile, or an app store such as `.cache`, `.npm`, `.nuget`, `.dotnet`,
`.bun`, `.claude`, `.config`, `.local`, `.vscode-server`, `.cursor`, `.docker`, `.gnupg` or `.ssh`.
`test_home_leftover_catalog.py` holds one of each and asserts every verdict.
