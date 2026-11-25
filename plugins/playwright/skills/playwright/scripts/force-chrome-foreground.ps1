
#Requires -Version 7.4

[CmdletBinding()]
param(
    [string] $TitleMatch = '.*'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    Write-Verbose 'Non-Windows host -- no-op.'
    exit 0
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Win32Focus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    public const int SW_RESTORE = 9;
}
'@

$chrome = Get-Process chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match $TitleMatch } |
    Select-Object -First 1

if (-not $chrome) {
    Write-Error "No Chrome process with a visible window matching '$TitleMatch'."
    exit 1
}

[void][Win32Focus]::ShowWindow($chrome.MainWindowHandle, [Win32Focus]::SW_RESTORE)
$setOk = [Win32Focus]::SetForegroundWindow($chrome.MainWindowHandle)
$actual = [Win32Focus]::GetForegroundWindow()
if (-not $setOk -or $actual -ne $chrome.MainWindowHandle) {
    Write-Error ("SetForegroundWindow did not take focus (returned $setOk; actual " +
        "foreground hWnd=$actual, requested=$($chrome.MainWindowHandle)). " +
        'Likely blocked by Windows'' no-steal-focus policy -- retry after a ' +
        'user gesture (Alt-Tab, click), or call AllowSetForegroundWindow ' +
        'from the parent process before spawning.')
    exit 1
}
