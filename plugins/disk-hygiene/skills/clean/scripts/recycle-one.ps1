# Recycle one literal path. Refuses rather than permanently deleting.
param(
    [Parameter(Mandatory = $true)]
    [string] $LiteralPath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $LiteralPath)) {
    exit 2
}
Add-Type -AssemblyName Microsoft.VisualBasic
$item = Get-Item -LiteralPath $LiteralPath
if ($item.PSIsContainer) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $item.FullName,
        'OnlyErrorDialogs',
        'SendToRecycleBin')
} else {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
        $item.FullName,
        'OnlyErrorDialogs',
        'SendToRecycleBin')
}
