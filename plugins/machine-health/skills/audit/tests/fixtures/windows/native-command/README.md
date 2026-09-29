# native-command fixtures

`record-argv.ps1` is the recording stub for `Invoke-NativeCommand`. The adapter
suite runs it under `pwsh -File` and reads the argv the child process received,
one base64 line per argument, from `NATIVE_ARGV_LOG`.
