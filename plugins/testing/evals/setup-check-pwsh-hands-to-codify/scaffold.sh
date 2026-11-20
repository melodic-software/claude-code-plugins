#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src tests
cat >src/Calc.ps1 <<'PS1'
function Add-Numbers([int]$a, [int]$b) { $a + $b }
PS1
cat >tests/Calc.Tests.ps1 <<'PS1'
BeforeAll { . "$PSScriptRoot/../src/Calc.ps1" }
Describe 'Add-Numbers' {
    It 'adds two numbers' {
        Add-Numbers 2 3 | Should -Be 5
    }
}
PS1
git add src/Calc.ps1 tests/Calc.Tests.ps1
git commit -q -m "seed"
