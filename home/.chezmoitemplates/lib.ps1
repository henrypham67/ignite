# ignite install helpers, rendered into each Windows install script (pwsh 7).
# Nothing here may stop the calling script: a failed install is written to the
# report and the run carries on.
#
# Report: $env:LOCALAPPDATA\ignite\report.tsv, one row per problem:
# source<TAB>status<TAB>item<TAB>detail, status failed|needs-it|skipped.

function Get-IgniteReportPath {
    Join-Path $env:LOCALAPPDATA 'ignite/report.tsv'
}

function ConvertTo-IgniteField {
    param([AllowEmptyString()][string]$Text)
    $Text -replace "[`t`r`n]", ' '
}

# Drop the rows a script wrote last time, so a retry that succeeds leaves no
# stale failure behind.
function Reset-IgniteReport {
    param([Parameter(Mandatory)][string]$Source)
    $report = Get-IgniteReportPath
    if (-not (Test-Path -LiteralPath $report)) { return }
    $keep = @(Get-Content -LiteralPath $report | Where-Object { ($_ -split "`t")[0] -ne $Source })
    Set-Content -LiteralPath $report -Value $keep -Encoding utf8NoBOM
}

function Add-IgniteReport {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Item,
        [AllowEmptyString()][string]$Detail = ''
    )
    $report = Get-IgniteReportPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $report) | Out-Null
    $fields = @($Source, $Status, $Item, $Detail) | ForEach-Object { ConvertTo-IgniteField $_ }
    Add-Content -LiteralPath $report -Value ($fields -join "`t") -Encoding utf8NoBOM
}

function Test-IgniteSkipped {
    param([Parameter(Mandatory)][string]$Item)
    $skip = @("$env:IGNITE_SKIP" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $skip -contains $Item
}

# Run a script block, showing its output. On failure (a throw or a non-zero
# native exit code), record the last line it printed. Never throws.
function Invoke-IgniteTry {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    if (Test-IgniteSkipped -Item $Item) {
        Add-IgniteReport -Source $Source -Status skipped -Item $Item -Detail 'IGNITE_SKIP'
        return
    }
    Write-Host "==> ignite ${Source}: $Item"
    $lines = [System.Collections.Generic.List[string]]::new()
    $failed = $false
    $ErrorActionPreference = 'Stop'
    try {
        $global:LASTEXITCODE = 0
        & $ScriptBlock 2>&1 | ForEach-Object {
            $text = "$_"
            $lines.Add($text)
            Write-Host $text
        }
        if ($LASTEXITCODE -ne 0) { $failed = $true }
    }
    catch {
        $failed = $true
        $lines.Add($_.Exception.Message)
    }
    if ($failed) {
        $detail = $lines | Where-Object { $_ -match '\S' } | Select-Object -Last 1
        if (-not $detail) { $detail = "exit status $LASTEXITCODE" }
        if (($lines -join "`n") -match '(?i)rate limit') {
            $detail = "$detail; set GITHUB_TOKEN and retry"
        }
        Add-IgniteReport -Source $Source -Status failed -Item $Item -Detail $detail
    }
}

# Make freshly installed tools visible to the rest of the script: reload PATH
# from the registry (Windows only; elsewhere keep the current PATH), then put
# the per-user tool dirs first.
function Update-IgnitePath {
    $rest = @($env:Path)
    if ($IsWindows) {
        $rest = @(
            [Environment]::GetEnvironmentVariable('Path', 'Machine'),
            [Environment]::GetEnvironmentVariable('Path', 'User')
        )
    }
    $parts = @(
        (Join-Path $HOME '.local/bin'),
        (Join-Path $env:LOCALAPPDATA 'mise/shims'),
        (Join-Path $HOME '.krew/bin')
    ) + $rest | Where-Object { $_ }
    $env:Path = $parts -join [IO.Path]::PathSeparator
}
