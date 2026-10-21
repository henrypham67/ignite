# Make $PROFILE load ignite's profile. $PROFILE often lives under a
# OneDrive-redirected Documents folder on company laptops, so chezmoi can't
# manage it directly: add one dot-source line instead, once.
function Install-IgniteProfileShim {
    param([Parameter(Mandatory)][string]$ProfilePath)
    $line = '. "$HOME\.config\powershell\profile.ps1"'
    $dir = Split-Path -Parent $ProfilePath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $existing = @()
    if (Test-Path -LiteralPath $ProfilePath) {
        $existing = @(Get-Content -LiteralPath $ProfilePath)
    }
    if ($existing -notcontains $line) {
        # A last line without a newline would get the shim glued onto it.
        $text = ''
        if (Test-Path -LiteralPath $ProfilePath) { $text = [IO.File]::ReadAllText($ProfilePath) }
        if ($text -and -not $text.EndsWith("`n")) {
            [IO.File]::AppendAllText($ProfilePath, [Environment]::NewLine)
        }
        Add-Content -LiteralPath $ProfilePath -Value $line -Encoding utf8NoBOM
    }
}
