# The Windows secrets file: created once, names appended, values never touched.

Describe 'Sync-IgniteSecretsFile' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'helper.ps1')
        $rendered = Join-Path $TestDrive 'secrets-lib.ps1'
        Invoke-IgniteRender -Fixture 'windows-admin' -Path (Join-Path $IgniteRepo 'home/.chezmoitemplates/secrets.ps1') |
            Set-Content -LiteralPath $rendered
        . $rendered
    }

    BeforeEach {
        $script:File = Join-Path $TestDrive "$([guid]::NewGuid())/secrets.ps1"
    }

    It 'creates the file with an empty line per name' {
        Sync-IgniteSecretsFile -Path $File -Names @('GITLAB_PRIVATE_TOKEN', 'GITLAB_USERNAME')
        $lines = Get-Content -LiteralPath $File
        $lines | Should -Contain "`$env:GITLAB_PRIVATE_TOKEN = ''"
        $lines | Should -Contain "`$env:GITLAB_USERNAME = ''"
    }

    It 'keeps existing values byte-identical and appends only missing names' {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $File) | Out-Null
        $original = "`$env:GITLAB_PRIVATE_TOKEN = 'a b`$c`"d'`n# my note`n"
        [IO.File]::WriteAllText($File, $original)
        Sync-IgniteSecretsFile -Path $File -Names @('GITLAB_PRIVATE_TOKEN', 'GITLAB_USERNAME')
        Sync-IgniteSecretsFile -Path $File -Names @('GITLAB_PRIVATE_TOKEN', 'GITLAB_USERNAME')
        [IO.File]::ReadAllText($File) | Should -BeExactly ($original + "`$env:GITLAB_USERNAME = ''" + [Environment]::NewLine)
    }
}
