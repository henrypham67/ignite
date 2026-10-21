# Shared helpers for the Pester suite. Dot-source from BeforeAll.

$script:IgniteRepo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

# Render a template file for a fixture machine, as the bats render_file helper does.
function Invoke-IgniteRender {
    param(
        [Parameter(Mandatory)][string]$Fixture,
        [Parameter(Mandatory)][string]$Path
    )
    $config = Join-Path $IgniteRepo "tests/fixtures/config/$Fixture.toml"
    $state = Join-Path ([IO.Path]::GetTempPath()) "ignite-pester-$([guid]::NewGuid()).boltdb"
    try {
        Get-Content -Raw -LiteralPath $Path |
            chezmoi --source $IgniteRepo --config $config --persistent-state $state execute-template
        if ($LASTEXITCODE -ne 0) { throw "chezmoi execute-template failed for $Path ($Fixture)" }
    }
    finally {
        Remove-Item -LiteralPath $state -ErrorAction SilentlyContinue
    }
}
