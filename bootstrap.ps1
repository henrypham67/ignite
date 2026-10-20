# ignite bootstrap for Windows. Run from a normal (non-elevated) PowerShell:
#
#   irm https://raw.githubusercontent.com/henrypham67/ignite/main/bootstrap.ps1 | iex
#
# Environment:
#   IGNITE_CA_CERT       company root CA (PEM) for TLS-inspecting proxies
#   IGNITE_NO_ADMIN=1    take the no-admin path even for an administrator
#   IGNITE_SKIP          comma-separated catalog entries to skip
#   IGNITE_REPO, IGNITE_REF, IGNITE_LOCAL_SOURCE   where the dotfiles come from
#
# Must run under Windows PowerShell 5.1 (what a blank laptop has): no ??, ?.,
# ternaries, && / || chains or -Parallel. Everything after the bootstrap runs
# under PowerShell 7.

$IgniteRawBase = 'https://raw.githubusercontent.com/henrypham67/ignite/main'
$IgniteBin = Join-Path $HOME '.local\bin'
$IgniteConfig = Join-Path $HOME '.config\ignite'

function Write-IgniteLog {
    param([string]$Message)
    Write-Host "==> ignite: $Message"
}

# ------------------------------------------------------------------ report
# Same format as lib.ps1 (a chezmoi template that doesn't exist yet). Written
# without a BOM: Windows PowerShell 5.1's -Encoding UTF8 would add one.

function Get-IgniteReportFile {
    Join-Path $env:LOCALAPPDATA 'ignite\report.tsv'
}

function Reset-IgniteBootstrapReport {
    $report = Get-IgniteReportFile
    if (-not (Test-Path -LiteralPath $report)) { return }
    $keep = @(Get-Content -LiteralPath $report | Where-Object { ($_ -split "`t")[0] -ne 'bootstrap' })
    $text = ''
    if ($keep.Count -gt 0) { $text = ($keep -join "`n") + "`n" }
    [IO.File]::WriteAllText($report, $text, (New-Object Text.UTF8Encoding $false))
}

function Add-IgniteBootstrapReport {
    param([string]$Status, [string]$Item, [string]$Detail)
    $report = Get-IgniteReportFile
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $report) | Out-Null
    $line = (@('bootstrap', $Status, $Item, $Detail) | ForEach-Object { $_ -replace "[`t`r`n]", ' ' }) -join "`t"
    [IO.File]::AppendAllText($report, "$line`n", (New-Object Text.UTF8Encoding $false))
}

# --------------------------------------------------------------- detection

function ConvertFrom-IgniteWhoamiGroups {
    param([string]$Text)
    [regex]::Matches($Text, '\bS-1-[0-9-]+') | ForEach-Object { $_.Value }
}

function Get-IgniteGroupSids {
    ConvertFrom-IgniteWhoamiGroups -Text ((whoami /groups) | Out-String)
}

# Administrators group membership, not whether this shell is elevated: a
# member can elevate through UAC.
function Test-IgniteCanElevate {
    if ($env:IGNITE_NO_ADMIN -eq '1') { return $false }
    return @(Get-IgniteGroupSids) -contains 'S-1-5-32-544'
}

function Test-IgniteIsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IgniteGitAvailable {
    [bool](Get-Command git -ErrorAction SilentlyContinue)
}

# ------------------------------------------------------------------- paths

function ConvertTo-IgniteWslPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        return '/mnt/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/')
    }
    return ($Path -replace '\\', '/')
}

function Get-IgniteLinuxOneLiner {
    param([AllowNull()][AllowEmptyString()][string]$CaWslPath)
    $url = "$IgniteRawBase/bootstrap.sh"
    if (-not $CaWslPath) { return "curl -fsSL $url | bash" }
    $quoted = "'" + ($CaWslPath -replace "'", "'\''") + "'"
    return "curl --cacert $quoted -fsSL $url | IGNITE_CA_CERT=$quoted bash"
}

function Add-IgniteUserPath {
    param([string]$Dir)
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @("$user" -split ';' | Where-Object { $_ })
    if ($parts -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('Path', (@($Dir) + $parts) -join ';', 'User')
    }
    if (@($env:Path -split ';') -notcontains $Dir) { $env:Path = "$Dir;$env:Path" }
}

function Update-IgniteSessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($IgniteBin, $user, $machine) | Where-Object { $_ }) -join ';'
}

function Set-IgniteUserEnv {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path "Env:$Name" -Value $Value
}

# ---------------------------------------------------------------------- CA

function Resolve-IgniteCaPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = $Path
    if ($resolved -match '^~[\\/]') {
        $resolved = Join-Path $HOME $resolved.Substring(2)
    }
    elseif (-not [IO.Path]::IsPathRooted($resolved)) {
        $resolved = Join-Path (Get-Location).Path $resolved
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "IGNITE_CA_CERT not found: $resolved"
    }
    return $resolved
}

function Install-IgniteCa {
    param([Parameter(Mandatory = $true)][string]$Path, [bool]$CanElevate)
    $source = Resolve-IgniteCaPath -Path $Path
    New-Item -ItemType Directory -Force -Path $IgniteConfig | Out-Null
    $ca = Join-Path $IgniteConfig 'ca.pem'
    $bundle = Join-Path $IgniteConfig 'ca-bundle.pem'
    if ($source -ne $ca) { Copy-Item -LiteralPath $source -Destination $ca -Force }

    # Trust it in Windows first, so the downloads below get through the proxy.
    if ($CanElevate) {
        $command = "Import-Certificate -FilePath '$ca' -CertStoreLocation Cert:\LocalMachine\Root | Out-Null"
        Invoke-IgniteElevated -Command $command
    }
    else {
        Write-IgniteLog 'adding the company CA to your user trust store (confirm the dialog)'
        Import-Certificate -FilePath $ca -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
    }

    # Tools with their own CA lists (python, aws, curl) get Mozilla's roots plus ours.
    $roots = (Invoke-WebRequest -UseBasicParsing -Uri 'https://curl.se/ca/cacert.pem').Content
    [IO.File]::WriteAllText($bundle, $roots + "`n" + [IO.File]::ReadAllText($ca), (New-Object Text.UTF8Encoding $false))

    Set-IgniteUserEnv -Name IGNITE_CA_CERT_INSTALLED -Value $ca
    Set-IgniteUserEnv -Name IGNITE_CA_BUNDLE -Value $bundle
    foreach ($name in @('SSL_CERT_FILE', 'REQUESTS_CA_BUNDLE', 'AWS_CA_BUNDLE', 'CURL_CA_BUNDLE')) {
        Set-IgniteUserEnv -Name $name -Value $bundle
    }
    Set-IgniteUserEnv -Name NODE_EXTRA_CA_CERTS -Value $ca
    Write-IgniteLog "company CA installed: $ca"
}

# ------------------------------------------------------------ prerequisites

# Run a block of PowerShell elevated, once: inline when this shell already is,
# otherwise through a single UAC prompt.
function Invoke-IgniteElevated {
    param([Parameter(Mandatory = $true)][string]$Command)
    if (Test-IgniteIsElevated) {
        & ([scriptblock]::Create($Command))
        return
    }
    $script = Join-Path ([IO.Path]::GetTempPath()) "ignite-admin-$([guid]::NewGuid()).ps1"
    Set-Content -LiteralPath $script -Value $Command -Encoding UTF8
    try {
        Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script)
    }
    finally {
        Remove-Item -LiteralPath $script -ErrorAction SilentlyContinue
    }
}

function Test-IgniteSkipped {
    param([string]$Item)
    $skip = @("$env:IGNITE_SKIP" -split ',' | ForEach-Object { $_.Trim() })
    return ($skip -contains $Item)
}

# The admin-only prerequisites, as one block of PowerShell for a single UAC prompt.
function Get-IgniteAdminCommand {
    param([bool]$HasWinget, [bool]$NeedsWsl)
    $steps = @()
    if ($HasWinget) {
        $winget = 'winget install --id {0} -e --silent --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity'
        $steps += ($winget -f 'Git.Git')
        $steps += ($winget -f 'Microsoft.PowerShell')
    }
    if ($NeedsWsl -and -not (Test-IgniteSkipped -Item 'wsl')) {
        $steps += 'wsl.exe --install --no-distribution'
    }
    return ($steps -join "`n")
}

function Test-IgniteWsl {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    & wsl.exe --status *> $null
    return ($LASTEXITCODE -eq 0)
}

# Returns the WSL state after prerequisites: 'ready', 'reboot' or 'missing'.
function Install-IgnitePrereqs {
    param([bool]$CanElevate)
    $wslBefore = Test-IgniteWsl
    $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    if (-not $hasWinget) {
        Add-IgniteBootstrapReport -Status needs-it -Item winget -Detail 'winget (App Installer) is missing; Scoop is used instead'
    }
    if ($CanElevate) {
        $command = Get-IgniteAdminCommand -HasWinget $hasWinget -NeedsWsl (-not $wslBefore)
        if ($command) {
            Write-IgniteLog 'installing admin prerequisites (one UAC prompt)'
            Invoke-IgniteElevated -Command $command
        }
    }

    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-IgniteLog 'installing Scoop'
        $installer = Invoke-RestMethod -UseBasicParsing -Uri 'https://get.scoop.sh'
        if (Test-IgniteIsElevated) {
            & ([scriptblock]::Create($installer)) -RunAsAdmin
        }
        else {
            & ([scriptblock]::Create($installer))
        }
    }
    Update-IgniteSessionPath
    if (-not $CanElevate -or -not $hasWinget) {
        foreach ($app in @('git', 'pwsh')) {
            if (-not (Get-Command $app -ErrorAction SilentlyContinue)) {
                & scoop install $app
                if ($LASTEXITCODE -ne 0) { Add-IgniteBootstrapReport -Status failed -Item $app -Detail 'scoop install failed' }
            }
        }
    }
    Update-IgniteSessionPath

    if ($wslBefore) { return 'ready' }
    if (Test-IgniteSkipped -Item 'wsl') { return 'skipped' }
    if ($CanElevate) { return 'reboot' }
    return 'missing'
}

function Install-IgniteTools {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
        Justification = 'chezmoi and mise publish their Windows installers as scripts to run this way')]
    param()
    New-Item -ItemType Directory -Force -Path $IgniteBin | Out-Null
    Add-IgniteUserPath -Dir $IgniteBin
    if (-not (Test-Path -LiteralPath (Join-Path $IgniteBin 'chezmoi.exe'))) {
        Write-IgniteLog 'installing chezmoi'
        Invoke-Expression "&{$(Invoke-RestMethod -UseBasicParsing -Uri 'https://get.chezmoi.io/ps1')} -b '$IgniteBin'"
    }
    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
        Write-IgniteLog 'installing mise'
        Invoke-Expression (Invoke-RestMethod -UseBasicParsing -Uri 'https://mise.run/powershell')
    }
    Update-IgniteSessionPath
}

# ----------------------------------------------------------------- chezmoi

function Get-IgniteChezmoiArgs {
    param([AllowEmptyCollection()][string[]]$Forward = @())
    $result = @()
    if (-not (Test-IgniteGitAvailable)) { $result += @('--use-builtin-git', 'on') }
    $result += @('init', '--apply')
    if ($env:IGNITE_LOCAL_SOURCE) {
        $result += @('--source', $env:IGNITE_LOCAL_SOURCE)
    }
    else {
        $repo = 'henrypham67/ignite'
        if ($env:IGNITE_REPO) { $repo = $env:IGNITE_REPO }
        $result += "https://github.com/$repo.git"
    }
    if ($env:IGNITE_REF) { $result += @('--branch', $env:IGNITE_REF) }
    if ($Forward) { $result += $Forward }
    return $result
}

function Install-IgniteWslDistro {
    param([string]$WslState)
    if ($WslState -eq 'skipped') {
        Add-IgniteBootstrapReport -Status skipped -Item WSL -Detail 'IGNITE_SKIP'
        return
    }
    if ($WslState -eq 'reboot') {
        Add-IgniteBootstrapReport -Status needs-it -Item WSL -Detail 'reboot then re-run the bootstrap'
        return
    }
    if ($WslState -eq 'missing') {
        Add-IgniteBootstrapReport -Status needs-it -Item WSL -Detail 'needs admin to enable WSL'
        return
    }
    $distros = ((& wsl.exe --list --quiet) | Out-String) -replace "`0", ''
    if ($distros -match '(?m)^Ubuntu') { return }
    Write-IgniteLog 'installing WSL Ubuntu'
    & wsl.exe --install -d Ubuntu --no-launch
    if ($LASTEXITCODE -ne 0) {
        Add-IgniteBootstrapReport -Status failed -Item WSL-Ubuntu -Detail "wsl --install exited $LASTEXITCODE"
    }
}

function Main {
    param([string[]]$Forward = @())
    $ErrorActionPreference = 'Stop'
    $canElevate = Test-IgniteCanElevate
    $env:IGNITE_ADMIN = '0'
    if ($canElevate) { $env:IGNITE_ADMIN = '1' }
    Write-IgniteLog ("windows, " + $(if ($canElevate) { 'with admin' } else { 'without admin' }))

    Reset-IgniteBootstrapReport
    Set-IgniteUserEnv -Name XDG_CONFIG_HOME -Value (Join-Path $HOME '.config')
    if ($env:IGNITE_CA_CERT) { Install-IgniteCa -Path $env:IGNITE_CA_CERT -CanElevate $canElevate }

    $wslState = Install-IgnitePrereqs -CanElevate $canElevate
    Install-IgniteTools

    $chezmoiArgs = Get-IgniteChezmoiArgs -Forward $Forward
    Write-IgniteLog ("chezmoi " + ($chezmoiArgs -join ' '))
    & (Join-Path $IgniteBin 'chezmoi.exe') @chezmoiArgs
    if ($LASTEXITCODE -ne 0) { throw "chezmoi init --apply failed ($LASTEXITCODE)" }

    Install-IgniteWslDistro -WslState $wslState

    $caWsl = $null
    if ($env:IGNITE_CA_CERT_INSTALLED) { $caWsl = ConvertTo-IgniteWslPath -Path $env:IGNITE_CA_CERT_INSTALLED }
    Write-Host ''
    if ($wslState -eq 'reboot') { Write-Host 'WSL was just enabled: reboot, open Ubuntu once, then run inside it:' }
    else { Write-Host 'For the Linux side, open Ubuntu (WSL) and run:' }
    Write-Host "  $(Get-IgniteLinuxOneLiner -CaWslPath $caWsl)"
    Write-Host ''

    $doctor = Join-Path $IgniteBin 'ignite-doctor.ps1'
    if (Test-Path -LiteralPath $doctor) {
        & pwsh -NoProfile -File $doctor
        exit $LASTEXITCODE
    }
    Write-IgniteLog 'done (ignite-doctor not found)'
}

if ($env:IGNITE_SOURCE_ONLY -ne '1') { Main -Forward $args }
