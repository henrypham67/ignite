# End-to-end run on Windows: bootstrap from this checkout with fixed answers
# (through Windows PowerShell 5.1, as on a blank laptop), then check that a
# second apply changes nothing and, without admin, that the needs-IT list is
# there and nothing failed. It installs real software: CI runners only.
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
if (-not $env:IGNITE_LOCAL_SOURCE) { $env:IGNITE_LOCAL_SOURCE = $repo }

$answers = @(
    '--no-tty',
    '--promptString', 'Work email for git=ci@example.com',
    '--promptChoice', 'Company git host: github.com or a self-hosted GitLab=github',
    '--promptBool', 'Use AWS=true',
    '--promptBool', 'Use Azure=false',
    '--promptBool', 'Use GCP=false',
    '--promptBool', 'Company licenses Docker Desktop=false',
    '--promptBool', 'Install specialist tools=false',
    '--promptBool', 'Install personal apps=false',
    '--promptBool', 'Change default tool choices=false'
)

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'bootstrap.ps1') @answers
if ($LASTEXITCODE -ne 0) { throw "bootstrap.ps1 exited $LASTEXITCODE" }

$chezmoi = Join-Path $HOME '.local\bin\chezmoi.exe'
$common = @('--source', $env:IGNITE_LOCAL_SOURCE, '--no-tty')
& $chezmoi @common apply
if ($LASTEXITCODE -ne 0) { throw 'second chezmoi apply failed' }
& $chezmoi @common verify --exclude=scripts
if ($LASTEXITCODE -ne 0) { throw 'chezmoi verify found differences' }
$changes = & $chezmoi @common status --exclude=scripts
if ($changes) { throw "a second apply still has changes:`n$($changes -join "`n")" }

if ($env:IGNITE_NO_ADMIN -eq '1') {
    $report = Join-Path $env:LOCALAPPDATA 'ignite\report.tsv'
    $rows = @(Get-Content -LiteralPath $report | ForEach-Object { , ($_ -split "`t") })
    if (-not ($rows | Where-Object { $_[1] -eq 'needs-it' })) { throw "expected needs-IT rows in $report" }
    $failed = @($rows | Where-Object { $_[1] -eq 'failed' })
    if ($failed) { throw "installs failed without admin:`n$(($failed | ForEach-Object { $_ -join ' ' }) -join "`n")" }
}
Write-Output 'e2e ok'
