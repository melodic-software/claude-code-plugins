# Code Editors

## Visual Studio Code

- [https://code.visualstudio.com/](https://code.visualstudio.com/)
- [https://code.visualstudio.com/download](https://code.visualstudio.com/download)

The CLI tool can be installed, BUT if you install VSCode manually or update the settings to add `code` to your PATH its not going to add anything.

```powershell
winget install --id Microsoft.VisualStudioCode -e --source winget
winget install --id Microsoft.VisualStudioCode.CLI -e --source winget # optional
```

### WSL Integration (Optional)

If you've installed WSL, VS Code can seamlessly integrate with your Linux environment using the Remote-WSL extension. This allows you to:

- Open projects directly in your WSL filesystem
- Use Linux-based tools and compilers
- Run and debug applications in a Linux environment
- Access the full Linux command line within VS Code

To set up WSL integration:

1. Install WSL if you haven't already - see [WSL Setup Windows](../wsl/wsl-setup-windows.md)
2. Install the [WSL extension](vscode:extension/ms-vscode-remote.remote-wsl) in VS Code - see [official docs](https://code.visualstudio.com/docs/remote/wsl-tutorial)
3. Open a WSL terminal and navigate to your project directory
4. Run `code .` to open the current directory in VS Code with WSL integration

For more details, see the [VS Code WSL documentation](https://code.visualstudio.com/docs/remote/wsl).

### Visual Studio Code Insiders

[https://code.visualstudio.com/insiders/](https://code.visualstudio.com/insiders/)

The CLI tool can be installed, BUT if you install VSCode manually or update the settings to add `code-insiders` (alias) to your PATH its not going to add anything.

```powershell
winget install --id Microsoft.VisualStudioCode.Insiders -e --source winget
winget install --id Microsoft.VisualStudioCode.Insiders.CLI -e --source winget # optional
```

## Visual Studio

- [https://visualstudio.microsoft.com/downloads/](https://visualstudio.microsoft.com/downloads/)
- [https://visualstudio.microsoft.com/vs/](https://visualstudio.microsoft.com/vs/)
- [https://visualstudio.microsoft.com/hub/](https://visualstudio.microsoft.com/hub/)

## Visual Studio Insiders

- [https://visualstudio.microsoft.com/insiders/](https://visualstudio.microsoft.com/insiders/)

## Jetbrains IDEs

The easiest way to manage and install Jetbrains IDEs, and other applications is to use their [JetBrains Toolbox App](https://www.jetbrains.com/toolbox-app/)
