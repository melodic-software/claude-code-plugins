# GENERATED from lib/prerequisites.ps1 by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Run prerequisites.mjs from this directory with the same arguments and exit code.
# Without node on PATH, print one fixed line and exit 1, because the checker
# cannot run and node is itself a missing required dependency.
#
#   pwsh -NoProfile -File prerequisites.ps1 check <plugin-root> [--for <scope>]
#
# node-notice is the one mode that never needs node, the counterpart of the same
# mode in prerequisites.sh (read its header for the contract):
#
#   powershell -NoProfile -File prerequisites.ps1 node-notice <check-command> [<enabled-option-name>]
$node = Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($args.Count -gt 0 -and $args[0] -eq 'node-notice') {
    if ($null -ne $node) { exit 0 }
    $check = if ($args.Count -gt 1) { [string]$args[1] } else { '' }
    $option = if ($args.Count -gt 2) { [string]$args[2] } else { '' }
    if ($option -match '^[A-Z0-9_]+$') {
        $enabled = [Environment]::GetEnvironmentVariable("CLAUDE_PLUGIN_OPTION_$option")
        if ($enabled -and $enabled -ne 'true') { exit 0 }
    }
    $session = 'no-session'
    if ([Console]::IsInputRedirected) {
        $found = [regex]::Match([Console]::In.ReadToEnd(), '"session_id"\s*:\s*"([^"]*)"')
        if ($found.Success -and $found.Groups[1].Value) { $session = $found.Groups[1].Value -replace '[^A-Za-z0-9_-]', '-' }
    }
    if ($session -ne 'no-session') {
        $latch = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'claude-plugins-node-missing'
        try {
            [void][IO.Directory]::CreateDirectory($latch)
            Get-ChildItem -LiteralPath $latch -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
            $stream = [IO.File]::Open((Join-Path -Path $latch -ChildPath $session), [IO.FileMode]::CreateNew)
            $stream.Dispose()
        } catch [IO.IOException] {
            exit 0
        } catch {
        }
    }
    $plugin = ($check.TrimStart('/') -split ':')[0]
    if (-not $plugin) { $plugin = 'plugin' }
    if (-not $check) { $check = 'the plugin check skill' }
    $msg = "${plugin}: node is not on PATH, so the hooks of this plugin and of every other plugin that launches through node cannot start and do nothing. Install Node.js from https://nodejs.org/en/download and restart Claude Code. Run $check to verify. This notice shows once per session."
    [Console]::Out.WriteLine('{"systemMessage":"' + $msg + '","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"WARNING: ' + $msg + ' Tell the user."}}')
    exit 0
}
if ($null -eq $node) {
    [Console]::Out.WriteLine('prerequisites: node was not found on PATH, so no prerequisite was checked. Install Node.js from https://nodejs.org/en/download, then run this check again.')
    exit 1
}
& $node.Source (Join-Path -Path $PSScriptRoot -ChildPath 'prerequisites.mjs') @args
exit $LASTEXITCODE
