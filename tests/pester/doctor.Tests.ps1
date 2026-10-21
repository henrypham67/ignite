# ignite-doctor.ps1 rendered for windows-admin, with its checks mocked.

Describe 'ignite-doctor.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'helper.ps1')
        $script:Doctor = Join-Path $TestDrive 'ignite-doctor.ps1'
        Invoke-IgniteRender -Fixture 'windows-admin' -Path (Join-Path $IgniteRepo 'home/dot_local/bin/ignite-doctor.ps1.tmpl') |
            Set-Content -LiteralPath $Doctor
        $env:IGNITE_SOURCE_ONLY = '1'
        . $Doctor
        $env:IGNITE_SOURCE_ONLY = $null
    }

    BeforeEach {
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Force -Path (Join-Path $env:LOCALAPPDATA 'ignite') | Out-Null
        $script:Report = Join-Path $env:LOCALAPPDATA 'ignite/report.tsv'
        Mock Get-IgniteManualStep { @() }
        Mock Get-IgniteVersion { '9.9.9' }
        Mock Write-Host {}
        # On Windows the real one rebuilds PATH from the registry, which would
        # drop chezmoi (added by CI) for every test file that runs after this.
        Mock Update-IgnitePath {}
    }

    It 'all present exits 0' {
        Mock Test-IgniteCheck { $true }
        Mock Test-IgniteAlternative { $false }
        Invoke-IgniteDoctor | Should -Be 0
    }

    It 'missing k9s exits 1 and prints MISSING k9s' {
        Mock Test-IgniteCheck { $Value -ne 'k9s' }
        Mock Test-IgniteAlternative { $false }
        Invoke-IgniteDoctor | Should -Be 1
        Should -Invoke Write-Host -ParameterFilter { "$Object" -match '^\s+MISSING\s+k9s' }
    }

    It 'failed rows print a retry that re-runs only the failed scripts' {
        Mock Test-IgniteCheck { $true }
        Mock Test-IgniteAlternative { $false }
        Set-Content -LiteralPath $Report -Value @("mise`tfailed`tk9s`tboom", "scoop`tfailed`tawscli`tboom")
        Invoke-IgniteDoctor | Out-Null
        $root = ($HOME -replace '\\', '/')
        Should -Invoke Write-Host -ParameterFilter { "$Object" -eq "    chezmoi state delete --bucket=entryState --key='$root/.chezmoiscripts/20-mise.ps1'" }
        Should -Invoke Write-Host -ParameterFilter { "$Object" -eq "    chezmoi state delete --bucket=entryState --key='$root/.chezmoiscripts/25-scoop.ps1'" }
        Should -Invoke Write-Host -ParameterFilter { "$Object" -eq '    chezmoi apply' }
        Should -Invoke Write-Host -Times 0 -ParameterFilter { "$Object" -match 'delete-bucket' }
    }

    It 'needs-it row is listed and not counted missing' {
        Mock Test-IgniteCheck { $Value -ne 'rdctl' }
        Mock Test-IgniteAlternative { $false }
        Set-Content -LiteralPath $Report -Value "plan`tneeds-it`trancher-desktop`tneeds admin"
        Invoke-IgniteDoctor | Should -Be 0
        Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'rancher-desktop.*needs admin' }
    }
}
