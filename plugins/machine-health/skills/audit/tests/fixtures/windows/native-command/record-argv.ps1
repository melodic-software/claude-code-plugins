# Records this process's argv, one base64 line per argument, then prints a marker.
$exit = 0
if ($null -ne $env:NATIVE_ARGV_EXIT -and $env:NATIVE_ARGV_EXIT -ne '') {
    $exit = [int]$env:NATIVE_ARGV_EXIT
}
$lines = [System.Collections.Generic.List[string]]::new()
foreach ($a in $args) {
    $lines.Add([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$a)))
}
[System.IO.File]::WriteAllLines($env:NATIVE_ARGV_LOG, $lines)
Write-Output 'recorded'
exit $exit
