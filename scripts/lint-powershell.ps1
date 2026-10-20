# Run PSScriptAnalyzer over every PowerShell file in the repo that isn't a
# chezmoi template. Rendered templates are analysed by the test suites.
$ErrorActionPreference = 'Stop'
Import-Module PSScriptAnalyzer

$root = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -Path $root -Recurse -Include '*.ps1', '*.psm1' -File |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|\.superpowers|home)[\\/]' }

$findings = foreach ($file in $files) {
    Invoke-ScriptAnalyzer -Path $file.FullName -Severity Warning, Error
}

if ($findings) {
    $findings | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String -Width 200 | Write-Output
    exit 1
}
Write-Output "PSScriptAnalyzer: $($files.Count) file(s) clean"
