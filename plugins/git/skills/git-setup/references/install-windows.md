# Windows Installation

## Option 1: Git for Windows Installer (Recommended for Control)

**Best for**: Users who want full control over installation options.

**Download**: [Git for Windows Official](https://git-scm.com/install/windows)

**Installation wizard options:**

- **Default editor**: Select VS Code if already installed, or configure later
- **Line ending conversion**: "Checkout Windows-style, commit Unix-style" (recommended)
- **Terminal emulator**: Use Windows' default console (recommended)
- **Credential helper**: Git Credential Manager (recommended)

**Note**: Install VS Code first if you want to select it as the editor during installation.

## Option 2: winget (Quick Install with Defaults)

**Best for**: Quick setup with sensible defaults.

```powershell
winget install --id Git.Git -e --source winget
```

**Note**: No wizard - uses default configuration.

## Verify Installation (Windows)

```powershell
git --version
# Expected output: git version 2.52.0.windows.1 (or newer)
```

## Windows-Specific Configuration

### System-Level Config (Optional - Requires Administrator)

**⚠️ Important**: Open PowerShell as **Administrator** to set these settings, otherwise you'll get:
`error: could not lock config file C:/Program Files/Git/etc/gitconfig: Permission denied`

```powershell
# Long paths on Windows (highly recommended)
git config --system core.longpaths true

# These are likely already set by Git for Windows installer:
git config --system init.defaultBranch main
git config --system http.sslBackend schannel
git config --system credential.helper manager
git config --system core.autocrlf true
```

**Note**: These settings are typically pre-configured by the Git for Windows installer.

### Enable Win32 Long Paths (Recommended)

If you enabled `core.longpaths`, also enable Win32 long paths in Windows:

**Via Group Policy Editor:**

1. Press WIN + R
2. Enter `gpedit.msc` and hit OK
3. Navigate to: Computer Configuration → Administrative Templates → System → Filesystem → Enable Win32 long paths
4. Right click and select `Edit`
5. Check the `Enabled` radio button and click OK

**Verify it's enabled:**

```powershell
Get-ItemProperty -Path HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem -Name LongPathsEnabled
```

## Windows-Specific Troubleshooting

**File path limitations:**

If repositories break due to Windows file path limitations:

1. Enable `core.longpaths` in Git (see System-Level Config above)
2. Enable Win32 long paths in Windows (see above)
3. See: [Solving Windows Path Length Limitations in Git](https://www.shadynagy.com/solving-windows-path-length-limitations-in-git/)

**Slow `git status` performance:**

- Ensure `core.fsmonitor=true` is set (see **git-config** skill)
- Ensure `core.untrackedCache=true` is set (see **git-config** skill)
- Consider excluding antivirus scanning for `.git` folders
- Consider using WSL2 for repositories with many files (better filesystem performance)

**Git Bash command history not working in Windows Terminal:**

If the up arrow key doesn't cycle through command history when using Git Bash in Windows Terminal:

1. Run the standalone **Git Bash** application (not in Windows Terminal) at least once
2. This creates the required `.bash_history` file in your home directory
3. After this, Windows Terminal's Git Bash profile will work correctly

For detailed troubleshooting and alternative solutions, see: **git-bash-history-troubleshooting.md**
